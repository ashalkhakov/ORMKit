/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMJoinPathBuilder.h"
#import "ORMEditorPriv.h"

@implementation ORMJoinPathSpec

+ (instancetype)specWithAtoms:(NSArray<NSDictionary<NSString *, NSString *> *> *)atoms columns:(NSArray<NSString *> *)columns
{
	ORMJoinPathSpec *spec = [[self alloc] init];
	spec.atoms = atoms;
	spec.columns = columns;
	return spec;
}

@end

/* A role path as planned: its pathed roles ([role id, purpose, variable])
 * and the sub-paths that go on from its end. */
@interface ORMPlannedPath : NSObject
@property (nonatomic, strong) NSMutableArray<NSArray<NSString *> *> *pathedRoles;
@property (nonatomic, strong) NSMutableArray<ORMPlannedPath *> *subPaths;
@end

@implementation ORMPlannedPath

- (instancetype)init
{
	if ((self = [super init])) {
		_pathedRoles = [NSMutableArray array];
		_subPaths = [NSMutableArray array];
	}
	return self;
}

@end

/* A spec planned: the lead path, the root variable, and the role where
 * each variable is first played. */
@interface ORMPlannedJoin : NSObject
@property (nonatomic, strong) ORMPlannedPath *lead;
@property (nonatomic, copy) NSString *root;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *firstRoles;
/* The constraint's columns, in the order of its role uses. */
@property (nonatomic, copy) NSArray<NSString *> *columns;
@end

@implementation ORMPlannedJoin
@end

/* Whether two object types are related by subtyping, at any depth or
 * through a common supertype. */
static BOOL
ORMSameFamily(ORMObjectType *a, ORMObjectType *b)
{
	NSMutableSet *family = [NSMutableSet set];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:a];
	while ([pending count] > 0) {
		ORMObjectType *type = [pending lastObject];
		[pending removeLastObject];
		NSValue *key = [NSValue valueWithNonretainedObject:type];
		if ([family containsObject:key]) {
			continue;
		}
		[family addObject:key];
		[pending addObjectsFromArray:type.subtypes];
		[pending addObjectsFromArray:type.supertypes];
	}
	return [family containsObject:[NSValue valueWithNonretainedObject:b]];
}

@implementation ORMEditor (ORMJoinPaths)

/* The atom's roles in their fact type's order. */
- (NSArray<NSString *> *)orderedRolesOf:(NSDictionary<NSString *, NSString *> *)atom
{
	ORMRole *any = [self.model elementWithId:[[atom allKeys] firstObject]];
	NSMutableArray *ordered = [NSMutableArray array];
	for (ORMRole *role in any.factType.roles) {
		if ([atom objectForKey:role.identifier] != nil) {
			[ordered addObject:role.identifier];
		}
	}
	return ordered;
}

- (BOOL)plan:(ORMPlannedJoin *)join
        from:(NSString *)variable
        into:(ORMPlannedPath *)node
   remaining:(NSMutableArray *)remaining
     visited:(NSMutableSet *)visited
      reason:(NSString **)reason
{
	NSMutableArray *here = [NSMutableArray array];
	for (NSDictionary *atom in remaining) {
		if ([[atom allValues] containsObject:variable]) {
			[here addObject:atom];
		}
	}
	[remaining removeObjectsInArray:here];
	for (NSDictionary *atom in here) {
		ORMPlannedPath *branch = [here count] == 1 ? node : [[ORMPlannedPath alloc] init];
		NSArray *roles = [self orderedRolesOf:atom];
		NSString *entry = nil;
		for (NSString *role in roles) {
			if (entry == nil && [[atom objectForKey:role] isEqualToString:variable]) {
				entry = role;
			}
		}
		[branch.pathedRoles addObject:@[ entry, @"PostInnerJoin", variable ]];
		if ([join.firstRoles objectForKey:variable] == nil) {
			[join.firstRoles setObject:entry forKey:variable];
		}
		/* The other roles, the one the path goes on from last. */
		NSMutableArray *others = [NSMutableArray array];
		NSString *onward = nil;
		for (NSString *role in roles) {
			if ([role isEqualToString:entry]) {
				continue;
			}
			NSString *other = [atom objectForKey:role];
			if ([visited containsObject:other]) {
				if (reason != NULL) {
					*reason = [NSString stringWithFormat:@"The path comes back to %@: a cycle is not a path.", other];
				}
				return NO;
			}
			BOOL goesOn = NO;
			for (NSDictionary *rest in remaining) {
				goesOn = goesOn || [[rest allValues] containsObject:other];
			}
			if (goesOn) {
				if (onward != nil) {
					if (reason != NULL) {
						*reason = @"The path goes on from two roles of one fact type.";
					}
					return NO;
				}
				onward = role;
			} else {
				[others addObject:role];
			}
		}
		if (onward != nil) {
			[others addObject:onward];
		}
		for (NSString *role in others) {
			NSString *other = [atom objectForKey:role];
			[visited addObject:other];
			[branch.pathedRoles addObject:@[ role, @"SameFactType", other ]];
			if ([join.firstRoles objectForKey:other] == nil) {
				[join.firstRoles setObject:role forKey:other];
			}
		}
		if (onward != nil && ![self plan:join from:[atom objectForKey:onward] into:branch remaining:remaining
		                         visited:visited reason:reason]) {
			return NO;
		}
		if (branch != node) {
			[node.subPaths addObject:branch];
		}
	}
	return YES;
}

- (ORMPlannedJoin *)planSpec:(ORMJoinPathSpec *)spec reason:(NSString **)reason
{
	ORMPlannedJoin *join = [[ORMPlannedJoin alloc] init];
	join.root = [spec.columns firstObject];
	join.columns = spec.columns;
	join.lead = [[ORMPlannedPath alloc] init];
	join.firstRoles = [NSMutableDictionary dictionary];
	NSMutableArray *remaining = [NSMutableArray arrayWithArray:spec.atoms];
	NSMutableSet *visited = [NSMutableSet setWithObject:join.root ?: @""];
	if (join.root == nil || ![self plan:join from:join.root into:join.lead remaining:remaining visited:visited
	                              reason:reason]) {
		return nil;
	}
	if ([remaining count] > 0) {
		if (reason != NULL) {
			*reason = @"Some fact types of the path are not joined to the rest.";
		}
		return nil;
	}
	for (NSString *column in spec.columns) {
		if ([join.firstRoles objectForKey:column] == nil) {
			if (reason != NULL) {
				*reason = [NSString stringWithFormat:@"The path does not reach %@.", column];
			}
			return nil;
		}
	}
	return join;
}

/* The roles of a sequence: where each column is played. */
- (NSArray<NSString *> *)sequenceRolesOf:(ORMJoinPathSpec *)spec plan:(ORMPlannedJoin *)join
{
	NSMutableArray *roles = [NSMutableArray array];
	for (NSString *column in spec.columns) {
		if (join != nil) {
			[roles addObject:[join.firstRoles objectForKey:column]];
			continue;
		}
		NSDictionary *atom = [spec.atoms firstObject];
		for (NSString *role in [self orderedRolesOf:atom]) {
			if ([[atom objectForKey:role] isEqualToString:column]) {
				[roles addObject:role];
				break;
			}
		}
	}
	return roles;
}

/* <orm:PathedRoles> and <orm:SubPaths> of a planned path, recording the
 * pathed role element where each variable is first met. */
- (void)write:(ORMPlannedPath *)path into:(NSXMLElement *)element met:(NSMutableDictionary *)met
{
	NSXMLDocument *document = self.document;
	if ([path.pathedRoles count] > 0) {
		NSXMLElement *pathedRoles = ORMNewElement(document, CORE, @"PathedRoles");
		for (NSArray *pathed in path.pathedRoles) {
			NSXMLElement *role = ORMNewElementWithId(document, CORE, @"PathedRole", nil);
			ORMSetAttribute(role, @"ref", [pathed objectAtIndex:0]);
			ORMSetAttribute(role, @"Purpose", [pathed objectAtIndex:1]);
			[pathedRoles addChild:role];
			if ([met objectForKey:[pathed objectAtIndex:2]] == nil) {
				[met setObject:ORMAttribute(role, @"id") forKey:[pathed objectAtIndex:2]];
			}
		}
		[element addChild:pathedRoles];
	}
	if ([path.subPaths count] > 0) {
		NSXMLElement *subPaths = ORMNewElement(document, CORE, @"SubPaths");
		for (ORMPlannedPath *sub in path.subPaths) {
			NSXMLElement *subPath = ORMNewElementWithId(document, CORE, @"SubPath", nil);
			[self write:sub into:subPath met:met];
			[subPaths addChild:subPath];
		}
		[element addChild:subPaths];
	}
}

/* The <orm:JoinRule> for the sequence, as NORMA writes one. */
- (void)attach:(ORMPlannedJoin *)join to:(NSXMLElement *)sequence
{
	NSXMLDocument *document = self.document;
	NSXMLElement *rule = ORMNewElement(document, CORE, @"JoinRule");
	NSXMLElement *joinPath = ORMNewElementWithId(document, CORE, @"JoinPath", nil);
	NSXMLElement *components = ORMNewElement(document, CORE, @"PathComponents");
	NSXMLElement *lead = ORMNewElementWithId(document, CORE, @"RolePath", nil);
	NSXMLElement *root = ORMNewElementWithId(document, CORE, @"RootObjectType", nil);
	ORMRole *rootRole = [self.model elementWithId:[join.firstRoles objectForKey:join.root]];
	/* The root's own type when its name gives one of the player's
	 * family ("some Mapping" for an Absorption's role): the path is of
	 * those instances. */
	ORMObjectType *rootType = rootRole.player;
	NSString *named = join.root;
	while ([named length] > 1 && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[named characterAtIndex:[named length] - 1]]) {
		named = [named substringToIndex:[named length] - 1];
	}
	ORMObjectType *candidate = [self.model objectTypeNamed:named];
	if (candidate != nil && candidate != rootType && ORMSameFamily(candidate, rootType)) {
		rootType = candidate;
	}
	ORMSetAttribute(root, @"ref", rootType.identifier);
	[lead addChild:root];
	NSMutableDictionary *met = [NSMutableDictionary dictionary];
	[self write:join.lead into:lead met:met];
	[components addChild:lead];
	[joinPath addChild:components];

	/* Each role use of the sequence, from where its column is met. */
	NSXMLElement *projections = ORMNewElement(document, CORE, @"JoinPathProjections");
	NSXMLElement *projection = ORMNewElementWithId(document, CORE, @"JoinPathProjection", nil);
	ORMSetAttribute(projection, @"ref", ORMAttribute(lead, @"id"));
	NSArray *uses = ORMChildren(sequence, CORE, @"Role");
	NSArray *columns = join.columns;
	for (NSUInteger i = 0; i < [uses count] && i < [columns count]; i++) {
		NSString *column = [columns objectAtIndex:i];
		NSXMLElement *roleProjection = ORMNewElementWithId(document, CORE, @"ConstraintRoleProjection", nil);
		ORMSetAttribute(roleProjection, @"ref", ORMAttribute([uses objectAtIndex:i], @"id"));
		NSXMLElement *from = ORMNewElement(document, CORE, @"ProjectedFrom");
		if ([column isEqualToString:join.root]) {
			[from addChild:ORMNewRef(document, CORE, @"PathRoot", ORMAttribute(root, @"id"))];
		} else {
			[from addChild:ORMNewRef(document, CORE, @"PathedRole", [met objectForKey:column])];
		}
		[roleProjection addChild:from];
		[projection addChild:roleProjection];
	}
	[projections addChild:projection];
	[joinPath addChild:projections];
	[rule addChild:joinPath];
	[sequence addChild:rule];
}

- (NSString *)addSetComparisonConstraint:(ORMConstraintKind)kind
                               joinPaths:(NSArray<ORMJoinPathSpec *> *)specs
                                  reason:(NSString **)reason
{
	NSMutableArray *plans = [NSMutableArray array];
	NSMutableArray *sequences = [NSMutableArray array];
	for (ORMJoinPathSpec *spec in specs) {
		ORMPlannedJoin *plan = nil;
		if ([spec.atoms count] > 1) {
			plan = [self planSpec:spec reason:reason];
			if (plan == nil) {
				return nil;
			}
		}
		[plans addObject:plan ?: [NSNull null]];
		[sequences addObject:[self sequenceRolesOf:spec plan:plan]];
	}
	__block NSString *created = nil;
	__block NSString *why = nil;
	[self group:@"Add Constraint over a Join Path" with:^{
		NSString *refused = nil;
		created = [self addSetComparisonConstraint:kind sequences:sequences reason:&refused];
		why = refused;
		if (created == nil) {
			return;
		}
		[self change:@"Add Join Path" with:^{
			NSXMLElement *constraint = [self xml:created];
			NSArray *elements = ORMGrandchildren(constraint, CORE, @"RoleSequences", CORE, @"RoleSequence");
			for (NSUInteger i = 0; i < [elements count] && i < [plans count]; i++) {
				if ([plans objectAtIndex:i] != [NSNull null]) {
					[self attach:[plans objectAtIndex:i] to:[elements objectAtIndex:i]];
				}
			}
		}];
	}];
	if (created == nil && reason != NULL) {
		*reason = why;
	}
	return created;
}

@end
