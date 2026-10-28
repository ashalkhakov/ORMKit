/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataValidation.h"
#import "ORMJoinedFacade.h"
#import "ORMVerbalizer.h"
#import "ORMVerbalizerPriv.h"
#import "ORMOutlineReader.h"
#import "ORMQueryPlanner.h"
#if __has_include(<ORMRuntime/ORMRuntime.h>)
#import <ORMRuntime/ORMRuntime.h>
#else
#import "ORMRuntime.h"
#endif
#import "ORMCDModel+CoreData.h"
#import "ORMQuery.h"
#import "ORMPath.h"
#import "ORMConstraintQueries.h"
#import "ORMXML.h"
#import "ORMQueryPlaces.h"
#import "ORMPopulationStore.h"
#import <CoreData/CoreData.h>
#import <ODataKit/ODataPropertyMapper.h>

/* An Objective-C string literal's contents. */
static NSString *
ORMEscaped(NSString *text)
{
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < [text length]; i++) {
		unichar c = [text characterAtIndex:i];
		if (c == '\\' || c == '"') {
			[out appendFormat:@"\\%C", c];
		} else if (c == '\n') {
			[out appendString:@"\\n"];
		} else {
			[out appendFormat:@"%C", c];
		}
	}
	return out;
}

static NSString *
ORMLiteral(NSString *text)
{
	return [NSString stringWithFormat:@"@\"%@\"", ORMEscaped(text ?: @"")];
}

/* A comment's text, with nothing in it that would end the comment. */
static NSString *
ORMCommentText(NSString *text)
{
	return [text stringByReplacingOccurrencesOfString:@"*/" withString:@"* /"];
}

/* "Mileage" for "mileage": a name as a rule's begins. */
static NSString *
ORMCapitalizedName(NSString *name)
{
	return [name length] > 0 ? [[[name substringToIndex:1] uppercaseString] stringByAppendingString:[name substringFromIndex:1]]
	                         : @"Value";
}

/* A bound as a number, or nil when it is not one. */
static NSNumber *
ORMBound(NSString *value)
{
	NSScanner *scanner = [NSScanner scannerWithString:value ?: @""];
	double number = 0;
	if (![scanner scanDouble:&number] || ![scanner isAtEnd]) {
		return nil;
	}
	return @(number);
}

@implementation ORMValidationGenerator
{
	ORMModel *_model;
	ORMCDModel *_coreData;
	NSArray<ORMMappingNote *> *_mapperNotes;
	NSString *_name;
	/* Property source (the far role) -> @[ entity, property ]. */
	NSMutableDictionary<NSString *, NSArray *> *_bySource;
	/* Entity name -> its rules. */
	NSMutableDictionary<NSString *, NSMutableArray<ORMRule *> *> *_rules;
	NSMutableArray<NSString *> *_notes;
	NSMutableArray<NSString *> *_skipped;
	NSUInteger _ruleCount;
	/* What the save hook does (docs/DERIVATION.md): the stored derivations it
	 * works out, in the order they are worked out; and, by the entity a rule
	 * reads, the ways back to it from what the rule reads: @[ entity,
	 * inverse keys ]. */
	NSMutableArray<ORMStoredDerivation *> *_derivations;
	NSMutableDictionary<NSString *, NSMutableOrderedSet<NSArray *> *> *_ruleBacks;
	/* The queries an app runs by name (docs/RUNTIME.md): their plans, and
	 * each one's method, @[ selector's stem, name, what it says ]. */
	NSMutableDictionary<NSString *, ORMQueryPlan *> *_queries;
	NSMutableArray<NSArray<NSString *> *> *_queryMethods;
	/* The joined entity types' code (docs/JOINED-ENTITIES.md). */
	ORMJoinedFacade *_joined;
	/* Rules are planned and asked as one predicate; a constraint said as
	 * rules is made in a copy of the document, not the model's. */
	ORMQueryPlanner *_planner;
	ORMQueryInterpreter *_interpreter;
	ORMEditor *_scratch;
	/* The reference data, as the tables' seeds. */
	NSArray<NSDictionary *> *_seeds;
}

- (instancetype)initWithModel:(ORMModel *)model
                     coreData:(ORMCDModel *)coreData
                        notes:(NSArray<ORMMappingNote *> *)notes
                         name:(NSString *)name
{
	if ((self = [super init])) {
		_model = model;
		_coreData = coreData;
		_mapperNotes = [notes copy] ?: @[];
		NSString *identifier = [ORMCoreDataMapper entityNameFor:name ?: @""];
		_name = [identifier length] > 0 ? identifier : @"Model";
		[self collect];
		_joined = [[ORMJoinedFacade alloc] initWithModel:model coreData:coreData name:_name];
	}
	return self;
}

- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping name:(NSString *)name
{
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:model mapping:mapping];
	ORMCDModel *coreData = [mapper map];
	return [self initWithModel:model coreData:coreData notes:mapper.notes name:name ?: mapping.name];
}

- (instancetype)initWithModel:(ORMModel *)model
                      mapping:(ORMCoreDataMapping *)mapping
                     coreData:(ORMCDModel *)coreData
                         name:(NSString *)name
{
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:model mapping:mapping];
	[mapper map];
	return [self initWithModel:model coreData:coreData notes:mapper.notes name:name ?: mapping.name];
}

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
}

- (NSUInteger)ruleCount
{
	return _ruleCount;
}

#pragma mark Where roles are

- (void)indexProperties
{
	_bySource = [NSMutableDictionary dictionary];
	for (ORMCDEntity *entity in _coreData.entities) {
		for (ORMCDProperty *property in [entity properties]) {
			if (property.source != nil) {
				[_bySource setObject:@[ entity, property ] forKey:property.source];
			}
		}
	}
}

/* The property a role's player has for it: the one traced to the role at
 * the other end of its binary (or unary) fact type. */
- (NSArray *)placeOf:(ORMRole *)role
{
	ORMRole *far = [role oppositeRole];
	return far != nil ? [_bySource objectForKey:far.identifier] : nil;
}

- (BOOL)entity:(ORMCDEntity *)entity inherits:(ORMCDEntity *)ancestor
{
	for (ORMCDEntity *at = entity; at != nil; at = at.parentName != nil ? [_coreData entityNamed:at.parentName] : nil) {
		if (at == ancestor) {
			return YES;
		}
	}
	return NO;
}

/* The entity that has every one of the properties: the one the others
 * are, or are ancestors of. */
- (ORMCDEntity *)entityHaving:(NSArray<NSArray *> *)places
{
	for (NSArray *candidate in places) {
		ORMCDEntity *entity = [candidate firstObject];
		BOOL all = YES;
		for (NSArray *place in places) {
			all = all && [self entity:entity inherits:[place firstObject]];
		}
		if (all) {
			return entity;
		}
	}
	return nil;
}

/* The roles' places, each sequence one role; nil unless every one has one
 * on the entity. */
- (NSArray<NSArray *> *)singleRolePlaces:(ORMConstraint *)constraint entity:(ORMCDEntity **)entity
{
	for (ORMRoleSequence *sequence in constraint.roleSequences) {
		if ([sequence.roles count] != 1) {
			return nil;
		}
	}
	return [self placesOfRoles:[constraint allRoles] entity:entity];
}

/* Each role's place; nil unless every one has one on the entity. */
- (NSArray<NSArray *> *)placesOfRoles:(NSArray<ORMRole *> *)roles entity:(ORMCDEntity **)entity
{
	NSMutableArray *places = [NSMutableArray array];
	for (ORMRole *role in roles) {
		NSArray *place = [self placeOf:role];
		if (place == nil) {
			return nil;
		}
		[places addObject:place];
	}
	*entity = [self entityHaving:places];
	return *entity != nil && [places count] > 0 ? places : nil;
}

/* Each sequence both roles of one binary, the first played on the entity:
 * the property from the first to the second. */
- (NSArray<NSArray *> *)pairPlaces:(ORMConstraint *)constraint entity:(ORMCDEntity **)entity
{
	NSMutableArray *places = [NSMutableArray array];
	for (ORMRoleSequence *sequence in constraint.roleSequences) {
		if ([sequence.roles count] != 2 || sequence.hasJoinPath) {
			return nil;
		}
		ORMRole *near = [sequence.roles objectAtIndex:0];
		if ([near oppositeRole] != [sequence.roles objectAtIndex:1]) {
			return nil;
		}
		NSArray *place = [self placeOf:near];
		if (place == nil) {
			return nil;
		}
		[places addObject:place];
	}
	*entity = [self entityHaving:places];
	return *entity != nil && [places count] > 0 ? places : nil;
}

- (NSString *)keyOf:(NSArray *)place
{
	return [(ORMCDProperty *)[place lastObject] name];
}

/* The check that the property holds anything: a unary's attribute true, a
 * to-many not empty, anything else set. */
- (NSDictionary *)presenceOf:(NSArray *)place
{
	ORMCDProperty *property = [place lastObject];
	ORMRole *source = [_model elementWithId:property.source];
	if ([property isKindOfClass:[ORMCDAttribute class]] && source.player.isImplicitBooleanValue) {
		return @{ @"true": property.name };
	}
	return @{ @"present": property.name };
}

#pragma mark The rules

- (NSString *)textOf:(ORMConstraint *)constraint
{
	NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:_model] sentencesForElement:constraint.identifier];
	/* What the constraint says, not its fact type: its own sentences, or
	 * one it is said together with ("exactly one" is a uniqueness and a
	 * mandatory over the same role). */
	NSMutableArray *own = [NSMutableArray array];
	NSMutableArray *together = [NSMutableArray array];
	NSMutableArray *all = [NSMutableArray array];
	for (ORMVerbalSentence *sentence in sentences) {
		ORMConstraint *source = [_model elementWithId:sentence.sourceId];
		if (source == constraint) {
			[own addObject:[sentence text]];
		} else if ([source isKindOfClass:[ORMConstraint class]] && [[source allRoles] isEqualToArray:[constraint allRoles]]) {
			[together addObject:[sentence text]];
		}
		[all addObject:[sentence text]];
	}
	NSArray *texts = [own count] > 0 ? own : [together count] > 0 ? together : all;
	return [texts count] > 0 ? [texts componentsJoinedByString:@" "] : constraint.name;
}

- (void)add:(NSDictionary *)check to:(ORMCDEntity *)entity for:(ORMConstraint *)constraint keys:(NSArray *)keys
{
	[self add:check to:entity named:constraint.name ?: constraint.identifier text:[self textOf:constraint]
	     keys:keys deontic:constraint.modality == ORMDeontic];
}

/* A rule of the entity's, its check as the tables have it. */
- (ORMRule *)add:(NSDictionary *)list
              to:(ORMCDEntity *)entity
           named:(NSString *)name
            text:(NSString *)text
            keys:(NSArray *)keys
         deontic:(BOOL)deontic
{
	NSError *error = nil;
	ORMRuleCheck *check = [ORMRuleCheck checkWithPropertyList:list error:&error];
	NSAssert(check != nil, @"%@", error);
	ORMRule *rule = [ORMRule ruleNamed:name text:text keys:keys deontic:deontic check:check];
	NSMutableArray *rules = [_rules objectForKey:entity.name];
	if (rules == nil) {
		rules = [NSMutableArray array];
		[_rules setObject:rules forKey:entity.name];
	}
	[rules addObject:rule];
	_ruleCount++;
	return rule;
}

- (void)skip:(ORMConstraint *)constraint because:(NSString *)why
{
	NSString *text = [self textOf:constraint];
	[_skipped addObject:[NSString stringWithFormat:@"%@: %@", constraint.name ?: constraint.identifier, text]];
	[_notes addObject:[NSString stringWithFormat:@"%@: %@ (%@)", constraint.name ?: constraint.identifier,
	                                             why, text]];
}

- (NSArray *)keysOf:(NSArray<NSArray *> *)places
{
	NSMutableArray *keys = [NSMutableArray array];
	for (NSArray *place in places) {
		[keys addObject:[self keyOf:place]];
	}
	return keys;
}

- (void)disjunctiveMandatory:(ORMConstraint *)constraint
{
	/* One sequence of the roles, one of which is played. */
	ORMCDEntity *entity = nil;
	NSArray *places = [self placesOfRoles:[constraint allRoles] entity:&entity];
	if (places == nil) {
		[self rulesFor:constraint orSkipBecause:@"its roles are not all properties of one entity"];
		return;
	}
	NSMutableArray *terms = [NSMutableArray array];
	for (NSArray *place in places) {
		[terms addObject:[self presenceOf:place]];
	}
	[self add:@{ @"any": terms } to:entity for:constraint keys:[self keysOf:places]];
}

- (void)exclusion:(ORMConstraint *)constraint
{
	ORMCDEntity *entity = nil;
	NSArray *places = [self singleRolePlaces:constraint entity:&entity];
	if (places != nil) {
		NSMutableArray *terms = [NSMutableArray array];
		for (NSArray *place in places) {
			[terms addObject:[self presenceOf:place]];
		}
		/* With a disjunctive mandatory over the same roles: exactly one. */
		[self add:@{ @"count": terms, constraint.exclusiveOrPartner != nil ? @"exactly" : @"atMost": @1 }
		       to:entity
		      for:constraint
		     keys:[self keysOf:places]];
		return;
	}
	places = [self pairPlaces:constraint entity:&entity];
	if (places != nil) {
		NSMutableArray *terms = [NSMutableArray array];
		for (NSUInteger i = 0; i < [places count]; i++) {
			for (NSUInteger j = i + 1; j < [places count]; j++) {
				[terms addObject:@{ @"sets": @[ [self keyOf:[places objectAtIndex:i]], [self keyOf:[places objectAtIndex:j]] ],
					                @"relation": @"disjoint" }];
			}
		}
		[self add:@{ @"all": terms } to:entity for:constraint keys:[self keysOf:places]];
		return;
	}
	[self rulesFor:constraint orSkipBecause:@"its arguments are not properties of one entity"];
}

/* Subset (the first sequence within the second) and equality. */
- (void)setComparison:(ORMConstraint *)constraint
{
	BOOL equality = constraint.kind == ORMEqualityConstraint;
	ORMCDEntity *entity = nil;
	NSArray *places = [self singleRolePlaces:constraint entity:&entity];
	NSMutableArray *terms = [NSMutableArray array];
	if (places != nil) {
		for (NSUInteger i = 0; i + 1 < [places count]; i++) {
			NSDictionary *a = [self presenceOf:[places objectAtIndex:i]];
			NSDictionary *b = [self presenceOf:[places objectAtIndex:i + 1]];
			/* The first only where the second; equal, the other way too. */
			[terms addObject:@{ @"any": @[ @{ @"not": a }, b ] }];
			if (equality) {
				[terms addObject:@{ @"any": @[ @{ @"not": b }, a ] }];
			}
		}
	} else if ((places = [self pairPlaces:constraint entity:&entity]) != nil) {
		for (NSUInteger i = 0; i + 1 < [places count]; i++) {
			[terms addObject:@{ @"sets": @[ [self keyOf:[places objectAtIndex:i]], [self keyOf:[places objectAtIndex:i + 1]] ],
				                @"relation": equality ? @"equal" : @"subset" }];
		}
	}
	if ([terms count] == 0) {
		[self rulesFor:constraint orSkipBecause:@"its arguments are not properties of one entity"];
		return;
	}
	[self add:[terms count] == 1 ? [terms firstObject] : @{ @"all": terms } to:entity for:constraint
	     keys:[self keysOf:places]];
}

- (void)ring:(ORMConstraint *)constraint
{
	NSArray *roles = [constraint allRoles];
	ORMRole *near = [roles count] == 2 ? [roles objectAtIndex:0] : nil;
	NSArray *place = near != nil && [near oppositeRole] == [roles objectAtIndex:1] ? [self placeOf:near] : nil;
	if (place == nil || ![[place lastObject] isKindOfClass:[ORMCDRelationship class]]) {
		[self skip:constraint because:@"it is not over a relationship of an entity to itself"];
		return;
	}
	NSDictionary *checks = @{ @(ORMRingIrreflexive): @"irreflexive",
		                      @(ORMRingReflexive): @"reflexive",
		                      @(ORMRingPurelyReflexive): @"purelyReflexive",
		                      @(ORMRingSymmetric): @"symmetric",
		                      @(ORMRingAsymmetric): @"asymmetric",
		                      @(ORMRingAntisymmetric): @"antisymmetric",
		                      @(ORMRingTransitive): @"transitive",
		                      @(ORMRingIntransitive): @"intransitive",
		                      @(ORMRingStronglyIntransitive): @"stronglyIntransitive",
		                      @(ORMRingAcyclic): @"acyclic" };
	NSMutableArray *properties = [NSMutableArray array];
	for (NSNumber *bit in [[checks allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if ((constraint.ringType & [bit unsignedIntegerValue]) != 0) {
			[properties addObject:[checks objectForKey:bit]];
		}
	}
	if ([properties count] == 0) {
		[self skip:constraint because:@"it has no ring type"];
		return;
	}
	[self add:@{ @"ring": properties, @"key": [self keyOf:place] } to:[place firstObject] for:constraint
	     keys:@[ [self keyOf:place] ]];
}

- (void)valueComparison:(ORMConstraint *)constraint
{
	NSDictionary *operators = @{ @"LessThan": @"<", @"LessThanOrEqual": @"<=", @"GreaterThan": @">",
		                         @"GreaterThanOrEqual": @">=", @"Equal": @"==", @"NotEqual": @"!=" };
	NSString *operator = [operators objectForKey:constraint.comparisonOperator ?: @""];
	/* The roles compared: the values', each the source of its attribute,
	 * or their players'. */
	NSMutableArray *found = [NSMutableArray array];
	for (ORMRole *role in [constraint allRoles]) {
		NSArray *place = [_bySource objectForKey:role.identifier] ?: [self placeOf:role];
		if (place != nil) {
			[found addObject:place];
		}
	}
	ORMCDEntity *entity = [found count] == [[constraint allRoles] count] ? [self entityHaving:found] : nil;
	NSArray *places = entity != nil ? found : nil;
	if (operator == nil || [places count] != 2
	    || ![[[places objectAtIndex:0] lastObject] isKindOfClass:[ORMCDAttribute class]]
	    || ![[[places objectAtIndex:1] lastObject] isKindOfClass:[ORMCDAttribute class]]) {
		[self rulesFor:constraint orSkipBecause:@"it does not compare two attributes of one entity"];
		return;
	}
	[self add:@{ @"compare": [self keysOf:places], @"comparison": operator }
	       to:entity
	      for:constraint
	     keys:[self keysOf:places]];
}

/* A numeric attribute's value constraint that Core Data's one inclusive
 * minimum and maximum cannot hold. */
- (void)valuesOf:(ORMCDAttribute *)attribute on:(ORMCDEntity *)entity
{
	NSArray *numeric = @[ @"Integer 16", @"Integer 32", @"Integer 64", @"Decimal", @"Double", @"Float" ];
	if (![numeric containsObject:attribute.attributeType]) {
		return;
	}
	ORMRole *role = [_model elementWithId:attribute.source];
	if (![role isKindOfClass:[ORMRole class]]) {
		return;
	}
	ORMValueConstraint *values = role.valueConstraint ?: role.player.valueConstraint;
	BOOL open = NO;
	for (ORMValueRange *range in values.ranges) {
		open = open || range.minInclusion == ORMRangeOpen || range.maxInclusion == ORMRangeOpen;
	}
	if ([values.ranges count] < 2 && !open) {
		return;
	}
	NSMutableArray *ranges = [NSMutableArray array];
	for (ORMValueRange *range in values.ranges) {
		NSMutableDictionary *bounds = [NSMutableDictionary dictionary];
		if ([range.minValue length] > 0) {
			NSNumber *min = ORMBound(range.minValue);
			if (min == nil) {
				return;
			}
			[bounds setObject:min forKey:@"min"];
			[bounds setObject:@(range.minInclusion == ORMRangeOpen) forKey:@"minOpen"];
		}
		if ([range.maxValue length] > 0) {
			NSNumber *max = ORMBound(range.maxValue);
			if (max == nil) {
				return;
			}
			[bounds setObject:max forKey:@"max"];
			[bounds setObject:@(range.maxInclusion == ORMRangeOpen) forKey:@"maxOpen"];
		}
		[ranges addObject:bounds];
	}
	if ([ranges count] == 0) {
		return;
	}
	NSDictionary *condition = @{ @"within": attribute.name, @"ranges": ranges };
	NSString *text = [NSString stringWithFormat:@"The possible values of %@ are %@.", attribute.name,
	                                            [values displayText] ?: @""];
	[self add:condition to:entity named:values.name ?: values.identifier text:text keys:@[ attribute.name ] deontic:NO];
}

/* Required in ORM, optional in Core Data, which has no required to-one to
 * an entity with a uniqueness constraint. */
- (void)loosened:(ORMCDRelationship *)relationship on:(ORMCDEntity *)entity
{
	if (![[relationship.userInfo objectForKey:@"ormkit.mandatory"] isEqualToString:@"YES"]) {
		return;
	}
	ORMRole *far = [_model elementWithId:relationship.source];
	ORMRole *near = [far isKindOfClass:[ORMRole class]] ? [far oppositeRole] : nil;
	for (ORMConstraint *constraint in near.constraints) {
		if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple) {
			[self add:[self presenceOf:@[ entity, relationship ]] to:entity for:constraint keys:@[ relationship.name ]];
			return;
		}
	}
	[self add:[self presenceOf:@[ entity, relationship ]]
	       to:entity
	    named:relationship.name
	     text:[NSString stringWithFormat:@"Each %@ has some %@.", entity.name, relationship.name]
	     keys:@[ relationship.name ]
	  deontic:NO];
}

/* An absorbed value (a Distance: its quantity and its unit, properties of
 * whatever refers to it) is all of its parts or none: one that may be
 * left out is refused set in part. Its parts' sources are the role played
 * by it and, after a "/", each identifying role. */
- (void)wholeAbsorbedValuesOf:(ORMCDEntity *)entity
{
	NSMutableDictionary<NSString *, NSMutableArray<ORMCDProperty *> *> *parts = [NSMutableDictionary dictionary];
	NSMutableArray *order = [NSMutableArray array];
	NSArray *properties = [(NSArray *)entity.attributes arrayByAddingObjectsFromArray:(NSArray *)entity.relationships];
	for (ORMCDProperty *property in properties) {
		NSRange slash = [property.source ?: @"" rangeOfString:@"/"];
		if (slash.location == NSNotFound) {
			continue;
		}
		NSString *head = [property.source substringToIndex:slash.location];
		ORMRole *role = [_model elementWithId:head];
		if (![role isKindOfClass:[ORMRole class]] || [[role.player.preferredIdentifier allRoles] count] < 2) {
			continue;
		}
		NSMutableArray *group = [parts objectForKey:head];
		if (group == nil) {
			group = [NSMutableArray array];
			[parts setObject:group forKey:head];
			[order addObject:head];
		}
		[group addObject:property];
	}
	for (NSString *head in order) {
		NSArray *group = [parts objectForKey:head];
		BOOL optional = NO;
		for (ORMCDProperty *property in group) {
			optional = optional || (property.optional && ![[property.userInfo objectForKey:@"ormkit.mandatory"] isEqualToString:@"YES"]);
		}
		if ([group count] < 2 || !optional) {
			continue;
		}
		NSMutableArray *present = [NSMutableArray array];
		NSMutableArray *keys = [NSMutableArray array];
		for (ORMCDProperty *property in group) {
			[present addObject:[self presenceOf:@[ entity, property ]]];
			[keys addObject:property.name];
		}
		ORMRole *role = [_model elementWithId:head];
		NSString *called = [role.name length] > 0 ? role.name : role.player.name;
		NSString *last = [keys lastObject];
		NSString *listed = [[[keys subarrayWithRange:NSMakeRange(0, [keys count] - 1)] componentsJoinedByString:@", "]
			stringByAppendingFormat:@" and %@", last];
		[self add:@{ @"any": @[ @{ @"all": present }, @{ @"not": @{ @"any": present } } ] }
		       to:entity
		    named:[NSString stringWithFormat:@"%@IsWhole", ORMCapitalizedName(called)]
		     text:[NSString stringWithFormat:@"Each %@'s %@ is a whole %@ or none: %@ are set together or not at all.",
		                                     entity.name, called, role.player.name, listed]
		     keys:keys
		  deontic:NO];
	}
}

/* Each uniqueness the mapping gave an entity (Core Data's constraint, which
 * not every store enforces: FreeCoreData's does not), checked as a rule:
 * no other object of the entity has the same values. Said as the model's
 * constraint whose roles its properties are traced to; an identifier's
 * own uniqueness is its store's key. */
- (void)uniquenesses
{
	NSMutableDictionary<NSSet *, ORMConstraint *> *byRoles = [NSMutableDictionary dictionary];
	for (ORMConstraint *constraint in _model.constraints) {
		if (constraint.kind == ORMUniquenessConstraint) {
			[byRoles setObject:constraint forKey:[NSSet setWithArray:[[constraint allRoles] valueForKey:@"identifier"]]];
		}
	}
	for (ORMCDEntity *entity in _coreData.entities) {
		for (NSArray<NSString *> *names in [entity.uniquenessConstraints arrayByAddingObjectsFromArray:entity.checkedUniquenesses]) {
			NSMutableSet *sources = [NSMutableSet set];
			BOOL key = NO;
			for (NSString *name in names) {
				ORMCDProperty *property = nil;
				for (ORMCDProperty *each in [entity properties]) {
					property = [each.name isEqualToString:name] ? each : property;
				}
				key = key || property == nil || [[property.userInfo objectForKey:@"OData.key"] isEqualToString:@"YES"];
				if (property.source != nil) {
					[sources addObject:property.source];
				}
			}
			if (key) {
				continue;
			}
			ORMConstraint *constraint = [byRoles objectForKey:sources];
			NSString *name = constraint.name ?: [NSString stringWithFormat:@"%@Unique%@", entity.name,
			                                                               [names componentsJoinedByString:@"And"]];
			NSString *text = constraint != nil ? [self textOf:constraint]
			                                   : [NSString stringWithFormat:@"Each %@ has a %@ of its own.", entity.name,
			                                                                [names componentsJoinedByString:@" and "]];
			[self add:@{ @"unique": names } to:entity named:name text:text keys:names deontic:NO];
		}
	}
}

- (void)collect
{
	_derivations = [NSMutableArray array];
	_ruleBacks = [NSMutableDictionary dictionary];
	_rules = [NSMutableDictionary dictionary];
	_notes = [NSMutableArray array];
	_skipped = [NSMutableArray array];
	[self indexProperties];
	for (ORMCDEntity *entity in _coreData.entities) {
		for (ORMCDRelationship *relationship in entity.relationships) {
			[self loosened:relationship on:entity];
		}
		for (ORMCDAttribute *attribute in entity.attributes) {
			[self valuesOf:attribute on:entity];
		}
		[self wholeAbsorbedValuesOf:entity];
	}
	/* The constraints the mapper found Core Data cannot enforce. */
	NSMutableOrderedSet *unenforced = [NSMutableOrderedSet orderedSet];
	for (ORMMappingNote *note in _mapperNotes) {
		if (note.kind == ORMMappingUnenforced && note.elementId != nil) {
			[unenforced addObject:note.elementId];
		}
	}
	for (NSString *identifier in unenforced) {
		ORMConstraint *constraint = [_model elementWithId:identifier];
		if (![constraint isKindOfClass:[ORMConstraint class]]) {
			continue;
		}
		switch (constraint.kind) {
		case ORMMandatoryConstraint:
			[self disjunctiveMandatory:constraint];
			break;
		case ORMExclusionConstraint:
			[self exclusion:constraint];
			break;
		case ORMSubsetConstraint:
		case ORMEqualityConstraint:
			[self setComparison:constraint];
			break;
		case ORMRingConstraint:
			[self ring:constraint];
			break;
		case ORMValueComparisonConstraint:
			[self valueComparison:constraint];
			break;
		case ORMUniquenessConstraint:
			[self skip:constraint because:@"uniqueness across objects needs a fetch"];
			break;
		case ORMFrequencyConstraint:
			[self skip:constraint because:@"a frequency over several roles needs a fetch"];
			break;
		}
	}
	[self uniquenesses];
	[self rules];
	[self subtypeRules];
	[self derivations];
	[self queries];
	[self referenceData];
}

#pragma mark Reference data

/* A value as a seed keeps it: a decimal as its text, which a property
 * list would round; nil for one no property list holds. */
static id
ORMSeedValueOf(id value)
{
	if ([value isKindOfClass:[NSDecimalNumber class]]) {
		return [value descriptionWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
	}
	return [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDate class]]
		? value : nil;
}

/* The reference data (docs/EXPRESSIONS.md): the population of the fact
 * types marked so, put in a store of the mapping, and each entity object
 * a fact of them has, as a seed: what finds it (its entity's key), and
 * the properties those fact types are kept in. A fact kept elsewhere (a
 * fact type's own entity) is noted, not seeded. The instances of an
 * entity type marked so are seeds too, by their key alone (a kind named,
 * CostKind 'Fuel'; a subtype's, of its entity). */
- (void)referenceData
{
	NSMutableArray *facts = [NSMutableArray array];
	NSMutableArray *types = [NSMutableArray array];
	NSMutableSet *sources = [NSMutableSet set];
	for (ORMObjectType *type in _model.objectTypes) {
		if (type.isReferenceData) {
			[types addObject:type];
		}
	}
	for (ORMFactType *fact in _model.factTypes) {
		if (!fact.isReferenceData) {
			continue;
		}
		[facts addObject:fact];
		for (ORMRole *role in fact.roles) {
			[sources addObject:[ORMQueryPlaces sourceOfRole:role]];
		}
	}
	_seeds = @[];
	if ([facts count] == 0 && [types count] == 0) {
		return;
	}
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:_model coreData:_coreData];
	NSError *error = nil;
	if ([store newContextWithError:&error] == nil) {
		[_notes addObject:[NSString stringWithFormat:@"The reference data is not seeded: %@", error.localizedDescription]];
		return;
	}
	NSMutableArray *objects = [NSMutableArray array];
	for (ORMObjectType *type in types) {
		for (ORMInstance *instance in [type instances]) {
			NSManagedObject *object = [store objectForInstance:instance.identifier];
			if (object == nil) {
				[_notes addObject:[NSString stringWithFormat:@"%@ %@: reference data kept in no object, not seeded.", type.name,
				                                             [instance displayText]]];
			} else if ([objects indexOfObjectIdenticalTo:object] == NSNotFound) {
				[objects addObject:object];
			}
		}
	}
	for (ORMFactType *fact in facts) {
		BOOL kept = NO;
		for (ORMFactInstance *each in [fact instances]) {
			for (ORMInstance *player in [each.instancesByRole allValues]) {
				NSManagedObject *object = [store objectForInstance:player.identifier];
				if (object != nil && [objects indexOfObjectIdenticalTo:object] == NSNotFound) {
					[objects addObject:object];
				}
				kept = kept || object != nil;
			}
		}
		if (!kept && [[fact instances] count] > 0) {
			[_notes addObject:[NSString stringWithFormat:@"\"%@\": reference data kept in no object a player is, not seeded.",
			                                             [fact displayText]]];
		}
	}
	ODataPropertyMapper *keys = [[ODataPropertyMapper alloc] init];
	NSMutableArray *seeds = [NSMutableArray array];
	for (NSManagedObject *object in objects) {
		NSEntityDescription *entity = object.entity;
		NSArray *key = [[[keys keyAttributesForEntity:entity] valueForKey:@"name"] sortedArrayUsingSelector:@selector(compare:)];
		NSMutableDictionary *values = [NSMutableDictionary dictionary];
		NSMutableDictionary *refs = [NSMutableDictionary dictionary];
		for (NSAttributeDescription *attribute in [[entity attributesByName] allValues]) {
			BOOL theirs = [key containsObject:attribute.name]
				|| [sources containsObject:[attribute.userInfo objectForKey:ORMCDSourceKey] ?: @""];
			id value = theirs ? ORMSeedValueOf([object valueForKey:attribute.name]) : nil;
			if (value != nil) {
				[values setObject:value forKey:attribute.name];
			}
		}
		for (NSRelationshipDescription *relationship in [[entity relationshipsByName] allValues]) {
			NSUInteger index = !relationship.isToMany
				&& [sources containsObject:[relationship.userInfo objectForKey:ORMCDSourceKey] ?: @""]
				? [objects indexOfObjectIdenticalTo:[object valueForKey:relationship.name]] : NSNotFound;
			if (index != NSNotFound) {
				[refs setObject:@(index) forKey:relationship.name];
			}
		}
		[seeds addObject:@{ @"entity": entity.name, @"key": key, @"values": values, @"refs": refs }];
	}
	_seeds = seeds;
}

/* <Name>ReferenceData: its one method, seeding a context. */
- (NSString *)referenceDataInterface
{
	if ([_seeds count] == 0) {
		return @"";
	}
	return [NSString stringWithFormat:
		@"\n/* The model's reference data (docs/EXPRESSIONS.md), from the tables (%@.ormplans):\n"
		@" * each object found by its key or inserted, given what the reference data\n"
		@" * says. Call it before a store is first used, and after an update. */\n"
		@"@interface %@ReferenceData : NSObject\n"
		@"+ (BOOL)seedContext:(NSManagedObjectContext *)context error:(NSError **)error;\n"
		@"@end\n",
		_name, _name];
}

- (NSString *)referenceDataImplementation
{
	if ([_seeds count] == 0) {
		return @"";
	}
	return [NSString stringWithFormat:
		@"\n@implementation %@ReferenceData\n\n"
		@"+ (BOOL)seedContext:(NSManagedObjectContext *)context error:(NSError **)error\n"
		@"{\n"
		@"\tORMTables *tables = [ORMTables tablesNamed:%@ error:error];\n"
		@"\treturn tables != nil && [tables seedContext:context error:error];\n"
		@"}\n\n@end\n",
		_name, ORMLiteral(_name)];
}

/* The constraint queries (docs/RULES.md): each a predicate its root's
 * objects must not meet, asked of self. Checked from that entity only: a
 * change elsewhere on the rule's paths is seen when it is saved again, as
 * the check's comment says. */
/* A constraint query's plan, where the driver can ask it of one object:
 * it reads an entity, and its condition is one predicate. nil, and why,
 * where not. */
- (ORMQueryPlan *)rulePlanOf:(ORMQuery *)query reason:(NSString **)reason
{
	if (_planner == nil) {
		_planner = [[ORMQueryPlanner alloc] initWithCoreData:_coreData];
		_interpreter = [[ORMQueryInterpreter alloc] initWithModel:[_coreData managedObjectModel]];
	}
	ORMQueryPlan *plan = [_planner planForQuery:query];
	ORMCDEntity *entity = plan.entityName != nil ? [_coreData entityNamed:plan.entityName] : nil;
	if (entity == nil || [plan.notes count] > 0) {
		*reason = [plan.notes count] > 0 ? [plan.notes componentsJoinedByString:@" "] : @"it reads no entity";
		return nil;
	}
	/* One predicate; or, where that cannot be, asked of the object in
	 * memory, as long as that needs no store. */
	NSString *notOne = nil;
	if ([_interpreter predicateForPlan:plan reason:&notOne] != nil || [_interpreter asksOfOneObject:plan reason:NULL]) {
		return plan;
	}
	*reason = notOne;
	return nil;
}

/* A constraint query as a rule of the entity it reads: its plan, the
 * predicate its rows meet, which a valid object does not. nil, and why,
 * where the driver cannot ask it of one object. */
- (ORMRule *)addRuleOf:(ORMQuery *)query
                 named:(NSString *)name
                  text:(NSString *)text
               deontic:(BOOL)deontic
                reason:(NSString **)reason
{
	ORMQueryPlan *plan = [self rulePlanOf:query reason:reason];
	if (plan == nil) {
		return nil;
	}
	ORMCDEntity *entity = [_coreData entityNamed:plan.entityName];
	/* Its rows are what must not be: a valid object is none of them. */
	ORMRule *rule = [self add:@{ @"not": @{ @"plan": [plan propertyList] } }
	                       to:entity
	                    named:name
	                     text:text
	                     keys:@[]
	                  deontic:deontic];
	/* At save, again for each object a change reaches it from. */
	NSArray *backs = [self backsFrom:entity trails:[plan trailsFromRead]];
	if (backs != nil) {
		NSMutableOrderedSet *all = [_ruleBacks objectForKey:entity.name] ?: [NSMutableOrderedSet orderedSet];
		[all addObjectsFromArray:backs];
		[_ruleBacks setObject:all forKey:entity.name];
		rule.remark = [NSString stringWithFormat:@"Checked from %@, and by orm_prepareForSave: for each %@ a change "
		                                         @"reaches.",
		                                         entity.name, entity.name];
	} else {
		rule.remark = [NSString stringWithFormat:@"Checked from %@ only: a change to the objects it reaches is seen "
		                                         @"when %@ is saved again.",
		                                         entity.name, entity.name];
	}
	return rule;
}

/* A constraint the tables have no check for, as the rules that say it
 * (ORMConstraintQueries); skipped, with why, where they cannot. */
- (void)rulesFor:(ORMConstraint *)constraint orSkipBecause:(NSString *)why
{
	if (_scratch == nil) {
		_scratch = [[ORMEditor alloc] initWithDocument:ORMCopyDocument(_model.document) undoManager:nil];
	}
	ORMConstraint *copy = [_scratch.model elementWithId:constraint.identifier];
	NSString *reason = nil;
	/* Read from what has an entity of its own. */
	NSMutableSet *readable = [NSMutableSet set];
	for (ORMCDEntity *entity in _coreData.entities) {
		if (entity.source != nil) {
			[readable addObject:entity.source];
		}
	}
	ORMConstraintQueries *builder = [[ORMConstraintQueries alloc] initWithEditor:_scratch];
	builder.readable = readable;
	/* Its queries' ids the same each time: they are in the plans written. */
	ORMBeginIds([NSString stringWithFormat:@"rule.%@", constraint.identifier]);
	NSArray *made = copy != nil ? [builder queriesFor:copy reason:&reason] : nil;
	ORMEndIds();
	/* All its rules, or none. */
	BOOL plannable = made != nil;
	for (NSString *identifier in made) {
		plannable = plannable && [self rulePlanOf:[ORMQuery queryWithId:identifier inModel:_scratch.model] reason:&reason] != nil;
	}
	if (!plannable) {
		[self skip:constraint because:reason != nil ? [NSString stringWithFormat:@"%@; as a rule, %@", why, reason] : why];
		return;
	}
	NSString *name = constraint.name ?: constraint.identifier;
	for (NSUInteger i = 0; i < [made count]; i++) {
		NSString *each = [made count] > 1 ? [NSString stringWithFormat:@"%@ (%lu)", name, (unsigned long)i + 1] : name;
		[self addRuleOf:[ORMQuery queryWithId:[made objectAtIndex:i] inModel:_scratch.model] named:each
		           text:[self textOf:constraint] deontic:constraint.modality == ORMDeontic reason:&reason];
	}
}

- (void)rules
{
	for (ORMQuery *query in [ORMQuery queriesInModel:_model]) {
		if (query.kind != ORMQueryConstraint) {
			continue;
		}
		NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:_model] sentencesForQuery:query];
		NSString *text = [sentences count] > 0 ? [[sentences valueForKey:@"text"] componentsJoinedByString:@" "] : query.name;
		NSString *why = nil;
		ORMRule *rule = [self addRuleOf:query named:query.name text:text deontic:query.isDeontic reason:&why];
		if (rule == nil) {
			[_skipped addObject:[NSString stringWithFormat:@"%@: %@", query.name, text]];
			[_notes addObject:[NSString stringWithFormat:@"%@: %@ (%@)", query.name, why ?: @"?", text]];
			continue;
		}
	}
}

/* "Each FillUp is a MeteredEvent", where a rule derives MeteredEvent and
 * does not store it: FillUp is asserted, and its entity's objects must
 * meet the rule ("an Event that was at some Distance"), which nothing in
 * Core Data says, its properties being the supertype's, optional there
 * (docs/DERIVATION.md). A rule of the subtype's entity, its query "✓FillUp
 * + not is MeteredEvent", made in the copy of the document; skipped, with
 * why, where it cannot be planned. */
- (void)subtypeRules
{
	for (ORMObjectType *subtype in _model.objectTypes) {
		ORMDerivationRule *own = [subtype derivationRule];
		if (own != nil && !own.isStored) {
			continue;
		}
		for (ORMFactType *fact in subtype.supertypeFacts) {
			ORMObjectType *supertype = [fact supertype];
			ORMDerivationRule *rule = [supertype derivationRule];
			if (rule == nil || rule.isStored || [ORMQuery derivationOfSubtype:supertype inModel:_model] == nil) {
				continue;
			}
			if (_scratch == nil) {
				_scratch = [[ORMEditor alloc] initWithDocument:ORMCopyDocument(_model.document) undoManager:nil];
			}
			NSString *text = [NSString stringWithFormat:@"Each %@ is %@ %@.", subtype.name, ORMArticle(supertype.name),
			                                            supertype.name];
			NSString *name = [NSString stringWithFormat:@"%@IsA%@", subtype.name, supertype.name];
			NSString *outline = [NSString stringWithFormat:@"It is impossible that:\n✓%@\n  + not is %@", subtype.name,
			                                               supertype.name];
			NSString *why = nil;
			ORMBeginIds([NSString stringWithFormat:@"subtype.%@", fact.identifier]);
			NSString *made = [[[ORMOutlineReader alloc] initWithEditor:_scratch] addQueryNamed:name outline:outline
			                                                                            reason:&why];
			ORMEndIds();
			ORMQuery *query = made != nil ? [ORMQuery queryWithId:made inModel:_scratch.model] : nil;
			if (query == nil || [self addRuleOf:query named:name text:text deontic:NO reason:&why] == nil) {
				[_skipped addObject:[NSString stringWithFormat:@"%@: %@", name, text]];
				[_notes addObject:[NSString stringWithFormat:@"%@: %@ (%@)", name, why ?: @"?", text]];
			}
		}
	}
}

/* A query's method's stem: its name in camel case, "Lives near work"
 * livesNearWork, one that starts with a digit "query" first. */
static NSString *
ORMSelectorStem(NSString *name)
{
	NSMutableString *stem = [NSMutableString string];
	BOOL upper = NO;
	for (NSUInteger i = 0; i < [name length]; i++) {
		unichar c = [name characterAtIndex:i];
		if (!(c < 128 && isalnum(c))) {
			upper = [stem length] > 0;
			continue;
		}
		NSString *letter = [NSString stringWithCharacters:&c length:1];
		[stem appendString:[stem length] == 0 ? [letter lowercaseString] : upper ? [letter uppercaseString] : letter];
		upper = NO;
	}
	if ([stem length] == 0 || isdigit([stem characterAtIndex:0])) {
		[stem insertString:@"query" atIndex:0];
	}
	return stem;
}

/* The queries an app runs (docs/RUNTIME.md): each list and calculation
 * the store can run, its plan in the tables, a method of <Name>Queries
 * running it by name. */
- (void)queries
{
	_queries = [NSMutableDictionary dictionary];
	_queryMethods = [NSMutableArray array];
	ORMQueryPlanner *planner = nil;
	NSMutableSet *stems = [NSMutableSet set];
	for (ORMQuery *query in [ORMQuery queriesInModel:_model]) {
		/* A subtype's rule, too, where the subtype is no entity of its
		 * own: which of its supertype's objects are of it (ServiceKind, a
		 * CostKind 'Maintenance' or 'Repair'), for an app to offer them. */
		ORMObjectType *subtype = query.kind == ORMQueryDerivation ? query.derivedSubtype : nil;
		BOOL ofSubtype = subtype != nil && ![[subtype derivationRule] isStored];
		if (query.kind != ORMQueryList && query.kind != ORMQueryCalculation && !ofSubtype) {
			continue;
		}
		planner = planner ?: [[ORMQueryPlanner alloc] initWithCoreData:_coreData];
		ORMQueryPlan *plan = [planner planForQuery:query];
		NSString *why = [plan.notes count] > 0 ? [plan.notes componentsJoinedByString:@" "]
			: [_queries objectForKey:query.name] != nil ? @"another query has its name" : nil;
		if (why != nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: not in the tables: %@", query.name, why]];
			continue;
		}
		NSString *stem = ORMSelectorStem(query.name);
		for (NSUInteger n = 2; [stems containsObject:stem]; n++) {
			stem = [NSString stringWithFormat:@"%@%lu", ORMSelectorStem(query.name), (unsigned long)n];
		}
		[stems addObject:stem];
		[_queries setObject:plan forKey:query.name];
		NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:_model] sentencesForQuery:query];
		[_queryMethods addObject:@[ stem, query.name, [[sentences valueForKey:@"text"] componentsJoinedByString:@" "] ?: @"" ]];
	}
}

/* <Name>Queries: a method for each query, running its plan by name. */
- (NSString *)queriesInterface
{
	if ([_queryMethods count] == 0) {
		return @"";
	}
	NSMutableString *out = [NSMutableString stringWithFormat:
		@"\n/* The model's queries (docs/QUERIES.md), run from the tables (%@.ormplans):\n"
		@" * in a context, every row; or as requests to the model's OData service. nil,\n"
		@" * and why, where it cannot be run there. */\n"
		@"@interface %@Queries : NSObject\n",
		_name, _name];
	for (NSArray *method in _queryMethods) {
		[out appendFormat:@"/* %@: %@ */\n"
		                  @"+ (ORMQueryResult *)%@InContext:(NSManagedObjectContext *)context error:(NSError **)error;\n"
		                  @"+ (ORMQueryOData *)%@RequestForModel:(NSManagedObjectModel *)model error:(NSError **)error;\n",
		                  ORMCommentText([method objectAtIndex:1]), ORMCommentText([method lastObject]),
		                  [method firstObject], [method firstObject]];
	}
	[out appendString:@"@end\n"];
	return out;
}

- (NSString *)queriesImplementation
{
	if ([_queryMethods count] == 0) {
		return @"";
	}
	NSMutableString *out = [NSMutableString stringWithFormat:@"\n@implementation %@Queries\n", _name];
	for (NSArray *method in _queryMethods) {
		[out appendFormat:@"\n+ (ORMQueryResult *)%@InContext:(NSManagedObjectContext *)context error:(NSError **)error\n"
		                  @"{\n"
		                  @"\treturn [[ORMTables tablesNamed:%@ error:error] runQuery:%@ inContext:context error:error];\n"
		                  @"}\n\n"
		                  @"+ (ORMQueryOData *)%@RequestForModel:(NSManagedObjectModel *)model error:(NSError **)error\n"
		                  @"{\n"
		                  @"\treturn [[ORMTables tablesNamed:%@ error:error] requestForQuery:%@ model:model error:error];\n"
		                  @"}\n",
		                  [method firstObject], ORMLiteral(_name), ORMLiteral([method objectAtIndex:1]),
		                  [method firstObject], ORMLiteral(_name), ORMLiteral([method objectAtIndex:1])];
	}
	[out appendString:@"\n@end\n"];
	return out;
}

#pragma mark The save hook

/* The property of the name on the entity or an ancestor. */
- (ORMCDProperty *)property:(NSString *)key of:(ORMCDEntity *)entity
{
	for (ORMCDEntity *at = entity; at != nil; at = at.parentName != nil ? [_coreData entityNamed:at.parentName] : nil) {
		for (ORMCDProperty *property in [at properties]) {
			if ([property.name isEqualToString:key]) {
				return property;
			}
		}
	}
	return nil;
}

/* The ways back to the entity from what the trails reach: for each entity
 * a relationship on them goes to, the inverse keys from there back, in the
 * order they are walked. nil where a relationship has no inverse. */
- (NSArray<NSArray *> *)backsFrom:(ORMCDEntity *)root trails:(NSArray<NSArray<NSString *> *> *)trails
{
	if (trails == nil) {
		return nil;
	}
	NSMutableOrderedSet *backs = [NSMutableOrderedSet orderedSet];
	for (NSArray *trail in trails) {
		ORMCDEntity *at = root;
		NSMutableArray *back = [NSMutableArray array];
		for (NSString *key in trail) {
			ORMCDProperty *property = [self property:key of:at];
			if (![property isKindOfClass:[ORMCDRelationship class]]) {
				break;
			}
			ORMCDRelationship *relationship = (ORMCDRelationship *)property;
			if ([relationship.inverseName length] == 0) {
				return nil;
			}
			[back insertObject:relationship.inverseName atIndex:0];
			at = [_coreData entityNamed:relationship.destination];
			if (at == nil) {
				return nil;
			}
			[backs addObject:@[ at.name, [back copy] ]];
		}
	}
	return [backs array];
}

/* The fact types the query steps through. */
static NSSet<ORMFactType *> *
ORMFactTypesRead(ORMQuery *query)
{
	NSMutableSet *read = [NSMutableSet set];
	for (ORMQueryNode *node in [query nodes]) {
		for (ORMQueryStep *step in node.steps) {
			if (step.factType != nil) {
				[read addObject:step.factType];
			}
		}
	}
	return read;
}

/* The derivations in dependency order (docs/DERIVATION.md, step 3): each
 * after those deriving the fact types it reads. A recursive one is refused,
 * so the order exists; were there a cycle, its derivations would come last,
 * as they were listed. */
static NSArray<ORMQuery *> *
ORMInDependencyOrder(NSArray<ORMQuery *> *derivations)
{
	NSMutableSet *derived = [NSMutableSet set];
	for (ORMQuery *query in derivations) {
		if (query.derivedFactType != nil) {
			[derived addObject:query.derivedFactType];
		}
	}
	/* What each waits for: the fact types read that another derives. */
	NSMutableArray *waits = [NSMutableArray array];
	for (ORMQuery *query in derivations) {
		NSMutableSet *wait = [NSMutableSet setWithSet:ORMFactTypesRead(query)];
		[wait intersectSet:derived];
		if (query.derivedFactType != nil) {
			[wait removeObject:query.derivedFactType];
		}
		[waits addObject:wait];
	}
	NSMutableArray *ordered = [NSMutableArray array];
	NSMutableIndexSet *left = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [derivations count])];
	for (BOOL progress = YES; progress && [left count] > 0;) {
		progress = NO;
		for (NSUInteger i = [left firstIndex]; i != NSNotFound; i = [left indexGreaterThanIndex:i]) {
			if ([[waits objectAtIndex:i] count] > 0) {
				continue;
			}
			ORMQuery *query = [derivations objectAtIndex:i];
			[ordered addObject:query];
			[left removeIndex:i];
			for (NSMutableSet *wait in waits) {
				if (query.derivedFactType != nil) {
					[wait removeObject:query.derivedFactType];
				}
			}
			progress = YES;
		}
	}
	[ordered addObjectsFromArray:[derivations objectsAtIndexes:left]];
	return ordered;
}

/* The plan's columns for the object read and the node, by object: no
 * identifier's key, so that a row has the objects themselves, which a
 * relationship is set to; a computed value as it is. nil where the plan
 * lists the root by no path. */
static ORMQueryPlan *
ORMObjectColumns(ORMQueryPlan *plan, ORMQueryNode *root, NSArray<ORMQueryNode *> *nodes)
{
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMQueryNode *each in [@[ root ] arrayByAddingObjectsFromArray:nodes]) {
		ORMPlanColumn *column = [plan columnOfNode:each.identifier];
		if (column == nil || (column.value != nil && each == root)) {
			return nil;
		}
		/* A value node's, computed: the value itself. */
		if (column.value != nil) {
			[columns addObject:column];
			continue;
		}
		[columns addObject:[ORMPlanColumn columnTitled:column.title node:column.nodeId path:column.path
		                                         trail:column.trail
		                                    identifier:nil]];
	}
	return [ORMQueryPlan planReading:plan.entityName where:plan.condition columns:columns sorts:@[] notes:plan.notes
	                     definitions:plan.definitions];
}

/* The stored derived fact types worked out at save (docs/DERIVATION.md),
 * as the tables have them (docs/RUNTIME.md): those Core Data does not
 * derive itself, whose rule goes from the first role's player, the
 * property the second role is mapped to set to what it reaches (the
 * properties of the parts of a player of several identifying values,
 * where it is absorbed). Partly derived, only where the rule derives
 * something. The driver asks the rule of each object a change can reach,
 * in memory. */
- (void)derivations
{
	ORMQueryPlanner *planner = nil;
	for (ORMQuery *query in ORMInDependencyOrder([ORMQuery derivationsInModel:_model])) {
		ORMFactType *fact = query.derivedFactType;
		ORMDerivationRule *rule = fact.isDerived ? [fact derivationRule] : nil;
		if (!rule.isStored) {
			continue;
		}
		NSString *what = [fact displayText];
		NSString *why = nil;
		NSArray *roles = [fact visibleRoles];
		NSArray *groups = [query derivedColumnGroups];
		/* A unary's: its object's flag, the attribute traced to its implicit
		 * role; true for the objects its rule lists. */
		BOOL unary = [roles count] == 1;
		ORMRole *far = [roles count] == 2 ? [roles lastObject] : nil;
		for (ORMRole *role in unary ? fact.roles : @[]) {
			far = role.player.isImplicitBooleanValue ? role : far;
		}
		NSArray *target = far != nil ? [_bySource objectForKey:far.identifier] : nil;
		ORMCDEntity *entity = [target firstObject];
		ORMCDProperty *property = [target lastObject];
		/* A player of several identifying values, absorbed: its parts'
		 * properties on the root's entity, in its identifier's order. */
		NSMutableArray *targets = [NSMutableArray array];
		BOOL parted = !unary && [ORMQuery partRolesOf:far.player] != nil;
		if (parted && property == nil) {
			entity = [_coreData entityWithSource:query.root.objectType.identifier]
				?: [_coreData entityNamed:[ORMCoreDataMapper entityNameFor:query.root.objectType.name]];
			ORMQueryPlaces *places = [[ORMQueryPlaces alloc] initWithCoreData:_coreData];
			for (NSArray *keys in entity != nil ? [places identifyingPartsOfAbsorbed:far.player base:far.identifier on:entity] ?: @[] : @[]) {
				[targets addObject:[keys firstObject]];
			}
		}
		if ([roles count] != (unary ? 1 : 2) || [groups count] != [roles count] || [[groups firstObject] firstObject] != query.root) {
			why = @"its rule does not go from one role's player to the other's";
		} else if (parted && [targets count] != [[ORMQuery partRolesOf:far.player] count]) {
			why = @"its player is identified by several values, kept in no properties of the object";
		} else if (!parted && property == nil) {
			why = @"it is mapped to no property";
		} else if ([property isKindOfClass:[ORMCDAttribute class]] && ((ORMCDAttribute *)property).derivation != nil) {
			/* Core Data derives it. */
			continue;
		}
		ORMQueryPlan *plan = nil;
		NSArray *trails = nil;
		if (why == nil) {
			planner = planner ?: [[ORMQueryPlanner alloc] initWithCoreData:_coreData];
			ORMQueryPlan *planned = [planner planForQuery:query];
			plan = [planned.notes count] == 0 ? ORMObjectColumns(planned, query.root, unary ? @[] : [groups lastObject]) : nil;
			trails = [plan trailsFromRead];
			/* Of the entity, or a subentity of it (a Service's cost, kept on
			 * Record): those objects have the property too. */
			BOOL of = NO;
			for (ORMCDEntity *at = plan != nil ? [_coreData entityNamed:plan.entityName] : nil; at != nil && !of;
			     at = at.parentName != nil ? [_coreData entityNamed:at.parentName] : nil) {
				of = [at.name isEqualToString:entity.name];
			}
			if (!of) {
				why = @"its rule does not plan from the object the property is of";
			} else if (trails == nil) {
				why = @"its rule reads what no path from the object says, which is not asked of it in memory";
			}
		}
		NSArray *backs = why == nil ? [self backsFrom:[_coreData entityNamed:plan.entityName] trails:trails] : nil;
		if (why == nil && backs == nil) {
			why = @"a relationship on its path has no inverse";
		}
		if (why != nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: not worked out at save: %@.", what, why]];
			continue;
		}
		NSString *kind = unary ? @"flag" : parted ? @"values" : [property isKindOfClass:[ORMCDAttribute class]] ? @"value"
			: (((ORMCDRelationship *)property).toMany ? @"objects" : @"object");
		[_derivations addObject:[ORMStoredDerivation derivationWithText:what root:plan.entityName plan:plan
		                                                        targets:parted ? targets : @[ property.name ]
		                                                           kind:kind
		                                                        partial:rule.isPartial
		                                                          backs:backs]];
	}
}

/* The context's category: what orm_prepareForSave: does, by the tables. */
- (NSString *)saveHook
{
	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"\n@implementation NSManagedObjectContext (ORMSave)\n\n"
	                  @"- (BOOL)orm_prepareForSave:(NSError **)error\n"
	                  @"{\n"
	                  @"\t/* The model's tables (%@.ormplans), by the driver. */\n"
	                  @"\tORMTables *tables = [ORMTables tablesNamed:%@ error:error];\n"
	                  @"\treturn tables != nil && [[[ORMSaveHook alloc] initWithTables:tables] prepareForSaveInContext:self "
	                  @"error:error];\n"
	                  @"}\n\n@end\n",
	                  _name, ORMLiteral(_name)];
	return out;
}

- (BOOL)hasSaveHook
{
	return [_derivations count] > 0 || [_ruleBacks count] > 0 || ![_joined isEmpty];
}

#pragma mark Writing

- (NSString *)classOf:(ORMCDEntity *)entity
{
	return [entity.representedClassName length] > 0 ? entity.representedClassName : entity.name;
}

/* The header that declares the class: Xcode's for its class Codegen, the
 * user's own otherwise. */
- (NSString *)headerOf:(ORMCDEntity *)entity
{
	if ([entity.codeGenerationType isEqualToString:@"class"]) {
		return [NSString stringWithFormat:@"%@+CoreDataClass.h", [self classOf:entity]];
	}
	return [NSString stringWithFormat:@"%@.h", [self classOf:entity]];
}

- (BOOL)ancestorHasRules:(ORMCDEntity *)entity
{
	for (ORMCDEntity *at = entity.parentName != nil ? [_coreData entityNamed:entity.parentName] : nil; at != nil;
	     at = at.parentName != nil ? [_coreData entityNamed:at.parentName] : nil) {
		if ([[_rules objectForKey:at.name] count] > 0) {
			return YES;
		}
	}
	return NO;
}

/* Entities with rules, each after its ancestors, in the model's order. */
- (NSArray<ORMCDEntity *> *)entitiesWithRules
{
	NSMutableArray *ordered = [NSMutableArray array];
	NSMutableArray *pending = [NSMutableArray array];
	for (ORMCDEntity *entity in _coreData.entities) {
		if ([[_rules objectForKey:entity.name] count] > 0) {
			[pending addObject:entity];
		}
	}
	while ([pending count] > 0) {
		NSUInteger before = [pending count];
		for (ORMCDEntity *entity in [pending copy]) {
			BOOL ready = YES;
			for (ORMCDEntity *other in pending) {
				ready = ready && (other == entity || ![self entity:entity inherits:other]);
			}
			if (ready) {
				[ordered addObject:entity];
				[pending removeObject:entity];
			}
		}
		if ([pending count] == before) {
			[ordered addObjectsFromArray:pending];
			break;
		}
	}
	return ordered;
}

- (NSString *)header
{
	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"/* %@Validation.h: generated by ORMKit from %@. Do not edit: it is made again\n"
	                  @" * with the model.\n"
	                  @" *\n"
	                  @" * The model's constraints Core Data cannot enforce, checked. Call them from\n"
	                  @" * the class's own validation:\n"
	                  @" *\n"
	                  @" *   - (BOOL)validateForInsert:(NSError **)error\n"
	                  @" *   {\n"
	                  @" *       return [super validateForInsert:error] && [self orm_validateConstraints:error];\n"
	                  @" *   }\n"
	                  @" *\n"
	                  @" * and the same in validateForUpdate:. */\n\n",
	                  _name, ORMCommentText(_model.name ?: @"the ORM model")];
	[out appendString:@"#import <CoreData/CoreData.h>\n"];
	if ([self hasTables]) {
		/* The driver of the model's tables (docs/RUNTIME.md). */
		[out appendString:@"#import <ORMRuntime/ORMRuntime.h>\n"];
	}
	NSMutableArray *entities = [NSMutableArray array];
	for (ORMCDEntity *entity in [self entitiesWithRules]) {
		if (![self ancestorHasRules:entity]) {
			[entities addObject:entity];
		}
	}
	for (ORMCDEntity *entity in entities) {
		[out appendFormat:@"#import \"%@\"\n", [self headerOf:entity]];
	}
	for (ORMCDEntity *entity in entities) {
		[out appendFormat:@"\n/* Checked by the model's tables (%@.ormplans), a subentity's rules with\n"
		                  @" * its own. */\n"
		                  @"@interface %@ (ORMValidation)\n"
		                  @"/* NO, with what is violated in the error: one NSError, or an\n"
		                  @" * NSValidationMultipleErrorsError with them under NSDetailedErrorsKey. */\n"
		                  @"- (BOOL)orm_validateConstraints:(NSError **)error;\n"
		                  @"/* The deontic rules broken: obligations to be told of, not enforced. */\n"
		                  @"- (NSArray<NSError *> *)orm_deonticViolations;\n"
		                  @"@end\n",
		                  _name, [self classOf:entity]];
	}
	[out appendString:[_joined header]];
	[out appendString:[self queriesInterface]];
	[out appendString:[self referenceDataInterface]];
	if ([self hasSaveHook]) {
		[out appendString:@"\n/* Saving (docs/DERIVATION.md): call before save:, as Core Data's will-save\n"
		                  @" * notification cannot refuse one.\n"
		                  @" *\n"
		                  @" *   if ([context orm_prepareForSave:&error] && [context save:&error]) ...\n"
		                  @" *\n"
		                  @" * The stored derived facts are worked out for the objects the changes reach,\n"
		                  @" * then the rules are checked again for each object a change reaches. NO,\n"
		                  @" * with the alethic violations, when one is broken: save nothing then. */\n"
		                  @"@interface NSManagedObjectContext (ORMSave)\n"
		                  @"- (BOOL)orm_prepareForSave:(NSError **)error;\n"
		                  @"@end\n"];
	}
	return out;
}

- (NSString *)implementation
{
	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"/* %@Validation.m: generated by ORMKit from %@. Do not edit: it is made again\n"
	                  @" * with the model. */\n\n",
	                  _name, ORMCommentText(_model.name ?: @"the ORM model")];
	[out appendFormat:@"#import \"%@Validation.h\"\n\n", _name];
	if ([_skipped count] > 0) {
		[out appendString:@"/* Not checked here:\n"];
		for (NSString *skipped in _skipped) {
			[out appendFormat:@" *   %@\n", ORMCommentText(skipped)];
		}
		[out appendString:@" */\n\n"];
	}
	[out appendString:[_joined implementation]];
	[out appendString:[self queriesImplementation]];
	[out appendString:[self referenceDataImplementation]];
	/* Each entity's rules, its ancestors' too, are the driver's to check:
	 * a category on the topmost classes with rules. */
	for (ORMCDEntity *entity in [self entitiesWithRules]) {
		if ([self ancestorHasRules:entity]) {
			continue;
		}
		[out appendFormat:@"\n@implementation %@ (ORMValidation)\n\n"
		                  @"- (BOOL)orm_validateConstraints:(NSError **)error\n"
		                  @"{\n"
		                  @"\tORMValidator *validator = [ORMValidator validatorNamed:%@ error:error];\n"
		                  @"\treturn validator != nil && [validator validate:self error:error];\n"
		                  @"}\n\n"
		                  @"- (NSArray<NSError *> *)orm_deonticViolations\n"
		                  @"{\n"
		                  @"\treturn [[ORMValidator validatorNamed:%@ error:NULL] violationsOf:self deontic:YES] ?: @[];\n"
		                  @"}\n\n@end\n",
		                  [self classOf:entity], ORMLiteral(_name), ORMLiteral(_name)];
	}
	if ([self hasSaveHook]) {
		[out appendString:[self saveHook]];
	}
	return out;
}

- (ORMTables *)tables
{
	NSMutableDictionary *backs = [NSMutableDictionary dictionary];
	for (NSString *entity in _ruleBacks) {
		[backs setObject:[[_ruleBacks objectForKey:entity] array] forKey:entity];
	}
	ORMTables *tables = [[ORMTables tablesOfModel:_name queries:_queries derivations:_derivations rules:_rules ruleBacks:backs]
		tablesWithJoined:[_joined types]];
	tables.seeds = _seeds;
	return tables;
}

/* Whether the code reads tables: it has rules or a save hook. */
- (BOOL)hasTables
{
	return [_rules count] > 0 || [_queries count] > 0 || [_seeds count] > 0 || [self hasSaveHook];
}

- (NSDictionary<NSString *, NSString *> *)files
{
	NSMutableDictionary *files = [NSMutableDictionary dictionary];
	[files setObject:[self header] forKey:[_name stringByAppendingString:@"Validation.h"]];
	[files setObject:[self implementation] forKey:[_name stringByAppendingString:@"Validation.m"]];
	if ([self hasTables]) {
		NSData *data = [NSPropertyListSerialization dataWithPropertyList:[[self tables] propertyList]
		                                                          format:NSPropertyListXMLFormat_v1_0
		                                                         options:0
		                                                           error:NULL];
		[files setObject:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
		          forKey:[_name stringByAppendingString:@".ormplans"]];
	}
	return files;
}

- (BOOL)writeToDirectory:(NSString *)directory error:(NSError **)error
{
	if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
	                                                attributes:nil
	                                                     error:error]) {
		return NO;
	}
	NSDictionary *files = [self files];
	for (NSString *name in files) {
		NSString *path = [directory stringByAppendingPathComponent:name];
		NSData *data = [[files objectForKey:name] dataUsingEncoding:NSUTF8StringEncoding];
		/* Unchanged files are left alone, so a build does not see them as new. */
		if ([[NSData dataWithContentsOfFile:path] isEqualToData:data]) {
			continue;
		}
		if (![data writeToFile:path options:NSDataWritingAtomic error:error]) {
			return NO;
		}
	}
	return YES;
}

@end
