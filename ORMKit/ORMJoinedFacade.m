/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMJoinedFacade.h"
#import "ORMCoreDataMapper.h"

static NSString *
ORMQuoted(NSString *text)
{
	NSString *escaped = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
		stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
	return [NSString stringWithFormat:@"@\"%@\"", escaped];
}

static NSString *
ORMUpper(NSString *name)
{
	return [name length] > 0 ? [[[name substringToIndex:1] uppercaseString] stringByAppendingString:[name substringFromIndex:1]]
	                         : name;
}

/* The class an attribute's value is of. */
static NSString *
ORMClassOfAttribute(ORMCDAttribute *attribute)
{
	NSDictionary *classes = @{ @"String": @"NSString", @"Decimal": @"NSDecimalNumber", @"Date": @"NSDate",
		                       @"Binary": @"NSData", @"UUID": @"NSUUID", @"URI": @"NSURL" };
	NSString *type = attribute.attributeType ?: @"";
	if ([type hasPrefix:@"Integer"] || [type isEqualToString:@"Double"] || [type isEqualToString:@"Float"]
	    || [type isEqualToString:@"Boolean"]) {
		return @"NSNumber";
	}
	return [classes objectForKey:type];
}

/* A joined entity type's code: its class, its hub, its members (each
 * after the one it joins to) and its properties. */
@interface ORMJoinedType : NSObject
@property (nonatomic, strong) ORMObjectType *type;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, strong) ORMCDEntity *hub;
/* @[ entity, via name, outer, @[ @[ theirs, ours ] ], held names ]. */
@property (nonatomic, copy) NSArray<NSArray *> *members;
/* @[ name, entity name, declared type ]. */
@property (nonatomic, copy) NSArray<NSArray *> *properties;
@end

@implementation ORMJoinedType
@end

@implementation ORMJoinedFacade
{
	ORMModel *_model;
	ORMCDModel *_coreData;
	NSString *_prefix;
	NSArray<ORMJoinedType *> *_types;
}

- (instancetype)initWithModel:(ORMModel *)model coreData:(ORMCDModel *)coreData prefix:(NSString *)prefix
{
	if ((self = [super init])) {
		_model = model;
		_coreData = coreData;
		_prefix = prefix;
		[self collect];
	}
	return self;
}

- (BOOL)isEmpty
{
	return [_types count] == 0;
}

- (void)collect
{
	NSMutableOrderedSet *typeIds = [NSMutableOrderedSet orderedSet];
	for (ORMCDEntity *entity in _coreData.entities) {
		NSString *joins = [entity.userInfo objectForKey:@"ormkit.joins"];
		if (joins != nil && [entity.userInfo objectForKey:@"ormkit.on"] != nil) {
			[typeIds addObject:joins];
		}
	}
	NSMutableSet *classes = [NSMutableSet set];
	for (ORMCDEntity *entity in _coreData.entities) {
		[classes addObject:[entity.representedClassName length] > 0 ? entity.representedClassName : entity.name];
	}
	NSMutableArray *types = [NSMutableArray array];
	for (NSString *typeId in typeIds) {
		ORMObjectType *type = [_model elementWithId:typeId];
		ORMCDEntity *hub = [_coreData entityWithSource:typeId];
		if (![type isKindOfClass:[ORMObjectType class]] || hub == nil) {
			continue;
		}
		ORMJoinedType *joined = [[ORMJoinedType alloc] init];
		joined.type = type;
		joined.hub = hub;
		NSString *name = [ORMCoreDataMapper entityNameFor:type.name];
		joined.className = [classes containsObject:name] ? [name stringByAppendingString:@"Joined"] : name;
		[classes addObject:joined.className];
		/* Each member after the one it joins to. */
		NSMutableArray *members = [NSMutableArray array];
		NSMutableSet *placed = [NSMutableSet setWithObject:hub.name];
		NSMutableArray *pending = [NSMutableArray array];
		for (ORMCDEntity *entity in _coreData.entities) {
			if ([[entity.userInfo objectForKey:@"ormkit.joins"] isEqualToString:typeId]
			    && [entity.userInfo objectForKey:@"ormkit.on"] != nil) {
				[pending addObject:entity];
			}
		}
		for (BOOL progress = YES; progress && [pending count] > 0;) {
			progress = NO;
			for (ORMCDEntity *entity in [pending copy]) {
				NSString *via = [entity.userInfo objectForKey:@"ormkit.via"];
				if (![placed containsObject:via]) {
					continue;
				}
				NSMutableArray *pairs = [NSMutableArray array];
				for (NSString *pair in [[entity.userInfo objectForKey:@"ormkit.on"] componentsSeparatedByString:@","]) {
					[pairs addObject:[pair componentsSeparatedByString:@" "]];
				}
				NSMutableArray *held = [NSMutableArray array];
				for (ORMCDProperty *property in [entity properties]) {
					if (![property.source hasPrefix:[entity.source stringByAppendingString:@"/"]]) {
						[held addObject:property.name];
					}
				}
				[members addObject:@[ entity, via, @([[entity.userInfo objectForKey:@"ormkit.outer"] isEqualToString:@"YES"]),
				                      pairs, held ]];
				[placed addObject:entity.name];
				[pending removeObject:entity];
				progress = YES;
			}
		}
		joined.members = members;
		/* The hub's properties, then each member's own. */
		NSMutableArray *properties = [NSMutableArray array];
		NSMutableSet *names = [NSMutableSet setWithArray:@[ @"object", @"delete", @"members", @"rowIn" ]];
		NSMutableArray *places = [NSMutableArray arrayWithObject:@[ hub, [hub properties] ]];
		for (NSArray *member in members) {
			ORMCDEntity *entity = [member firstObject];
			NSMutableArray *own = [NSMutableArray array];
			for (ORMCDProperty *property in [entity properties]) {
				if ([[member lastObject] containsObject:property.name]) {
					[own addObject:property];
				}
			}
			[places addObject:@[ entity, own ]];
		}
		for (NSArray *place in places) {
			ORMCDEntity *entity = [place firstObject];
			for (ORMCDProperty *property in [place lastObject]) {
				NSString *declared = nil;
				if ([property isKindOfClass:[ORMCDAttribute class]]) {
					NSString *class = ORMClassOfAttribute((ORMCDAttribute *)property);
					declared = class != nil ? [class stringByAppendingString:@" *"] : @"id";
				} else {
					declared = ((ORMCDRelationship *)property).toMany ? @"NSSet *" : @"NSManagedObject *";
				}
				NSString *name = property.name;
				if ([names containsObject:name]) {
					name = [name stringByAppendingString:entity.name];
				}
				[names addObject:name];
				[properties addObject:@[ name, property.name, entity.name, declared ]];
			}
		}
		joined.properties = properties;
		[types addObject:joined];
	}
	_types = types;
}

#pragma mark The code

- (NSString *)header
{
	if ([self isEmpty]) {
		return @"";
	}
	NSMutableString *out = [NSMutableString string];
	[out appendString:@"\n/* An entity type kept in several entities, joined on its identifiers\n"
	                  @" * (docs/JOINED-ENTITIES.md): each property read from and written to the entity\n"
	                  @" * that holds it, the row there made where a value is set, and let go of where\n"
	                  @" * its last one goes. */\n"
	                  @"@interface PFXJoined : NSObject\n"
	                  @"- (instancetype)initWithObject:(NSManagedObject *)object;\n"
	                  @"/* Its object in the hub, the entity every one has a row in. */\n"
	                  @"@property (nonatomic, readonly, strong) NSManagedObject *object;\n"
	                  @"/* Its row in a member, or the hub; nil where it has none. */\n"
	                  @"- (NSManagedObject *)rowIn:(NSString *)entityName;\n"
	                  @"/* Deletes its rows, the hub's and the members'. */\n"
	                  @"- (void)delete;\n"
	                  @"@end\n"];
	for (ORMJoinedType *joined in _types) {
		NSMutableArray *kept = [NSMutableArray arrayWithObject:joined.hub.name];
		for (NSArray *member in joined.members) {
			[kept addObject:[(ORMCDEntity *)[member firstObject] name]];
		}
		[out appendFormat:@"\n/* %@, kept in %@. */\n"
		                  @"@interface %@ : PFXJoined\n"
		                  @"+ (NSArray<%@ *> *)allInContext:(NSManagedObjectContext *)context;\n"
		                  @"/* A new one: its rows in the inner members are made when it is saved,\n"
		                  @" * by the values it is joined by. */\n"
		                  @"+ (instancetype)insertInContext:(NSManagedObjectContext *)context;\n",
		                  [joined.type.name stringByReplacingOccurrencesOfString:@"*/" withString:@"* /"],
		                  [kept componentsJoinedByString:@", "], joined.className, joined.className];
		for (NSArray *property in joined.properties) {
			NSString *declared = [property lastObject];
			[out appendFormat:@"@property (nonatomic, strong) %@%@%@;\n", declared,
			                  [declared hasSuffix:@"*"] ? @"" : @" ", [property firstObject]];
		}
		[out appendString:@"@end\n"];
	}
	return [out stringByReplacingOccurrencesOfString:@"PFX" withString:_prefix];
}

- (NSString *)membersLiteralOf:(ORMJoinedType *)joined
{
	NSMutableArray *items = [NSMutableArray array];
	for (NSArray *member in joined.members) {
		NSMutableArray *pairs = [NSMutableArray array];
		for (NSArray *pair in [member objectAtIndex:3]) {
			[pairs addObject:[NSString stringWithFormat:@"@[ %@, %@ ]", ORMQuoted([pair firstObject]),
			                                            ORMQuoted([pair lastObject])]];
		}
		NSMutableArray *held = [NSMutableArray array];
		for (NSString *name in [member lastObject]) {
			[held addObject:ORMQuoted(name)];
		}
		[items addObject:[NSString stringWithFormat:@"\t\t@{ @\"entity\": %@, @\"via\": %@, @\"outer\": @%@,\n"
		                                            @"\t\t   @\"on\": @[ %@ ],\n"
		                                            @"\t\t   @\"holds\": @[ %@ ] }",
		                                            ORMQuoted([(ORMCDEntity *)[member firstObject] name]),
		                                            ORMQuoted([member objectAtIndex:1]),
		                                            [[member objectAtIndex:2] boolValue] ? @"YES" : @"NO",
		                                            [pairs componentsJoinedByString:@", "],
		                                            [held componentsJoinedByString:@", "]]];
	}
	return [NSString stringWithFormat:@"@[\n%@\n\t]", [items componentsJoinedByString:@",\n"]];
}

- (NSString *)implementation
{
	if ([self isEmpty]) {
		return @"";
	}
	NSMutableString *out = [NSMutableString string];
	[out appendString:
		@"\n/* Joined entity types (docs/JOINED-ENTITIES.md). A type's members: each\n"
		@" * @{ entity, via: the entity it joins to, outer: not every one has a row,\n"
		@" * on: @[ @[ via's key, its own ] ], holds: its keys }, each after its via. */\n\n"
		@"static PFX_UNUSED NSDictionary *\n"
		@"PFXMember(NSArray *members, NSString *entity)\n"
		@"{\n"
		@"\tfor (NSDictionary *member in members) {\n"
		@"\t\tif ([[member objectForKey:@\"entity\"] isEqualToString:entity]) {\n"
		@"\t\t\treturn member;\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn nil;\n"
		@"}\n\n"
		@"/* The hub's value: as given (the values before a change), or as it is. */\n"
		@"static PFX_UNUSED id\n"
		@"PFXHubValue(NSManagedObject *hub, NSDictionary *values, NSString *key)\n"
		@"{\n"
		@"\tid value = values != nil ? [values objectForKey:key] : [hub valueForKey:key];\n"
		@"\treturn value == [NSNull null] ? nil : value;\n"
		@"}\n\n"
		@"/* The hub's row in the entity, found by what joins it; made, with those\n"
		@" * values, where there is none and create says so. nil where there is none,\n"
		@" * or no value to join it by. */\n"
		@"static PFX_UNUSED NSManagedObject *\n"
		@"PFXMemberRow(NSManagedObject *hub, NSArray *members, NSString *entity, BOOL create, NSDictionary *values)\n"
		@"{\n"
		@"\tif ([[[hub entity] name] isEqualToString:entity]) {\n"
		@"\t\treturn hub;\n"
		@"\t}\n"
		@"\tNSDictionary *member = PFXMember(members, entity);\n"
		@"\tNSString *viaName = [member objectForKey:@\"via\"];\n"
		@"\tNSManagedObject *via = member != nil ? PFXMemberRow(hub, members, viaName, create, values) : nil;\n"
		@"\tif (via == nil) {\n"
		@"\t\treturn nil;\n"
		@"\t}\n"
		@"\tNSMutableArray *parts = [NSMutableArray array];\n"
		@"\tNSMutableArray *joining = [NSMutableArray array];\n"
		@"\tfor (NSArray *pair in [member objectForKey:@\"on\"]) {\n"
		@"\t\tid value = via == hub ? PFXHubValue(hub, values, [pair objectAtIndex:0]) : [via valueForKey:[pair objectAtIndex:0]];\n"
		@"\t\tif (value == nil) {\n"
		@"\t\t\treturn nil;\n"
		@"\t\t}\n"
		@"\t\t[joining addObject:value];\n"
		@"\t\t[parts addObject:[NSPredicate predicateWithFormat:@\"%K == %@\", [pair objectAtIndex:1], value]];\n"
		@"\t}\n"
		@"\tNSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entity];\n"
		@"\tfetch.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:parts];\n"
		@"\tNSManagedObject *row = [[[hub managedObjectContext] executeFetchRequest:fetch error:NULL] firstObject];\n"
		@"\tif (row == nil && create) {\n"
		@"\t\trow = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:[hub managedObjectContext]];\n"
		@"\t\tNSArray *on = [member objectForKey:@\"on\"];\n"
		@"\t\tfor (NSUInteger i = 0; i < [on count]; i++) {\n"
		@"\t\t\t[row setValue:[joining objectAtIndex:i] forKey:[[on objectAtIndex:i] objectAtIndex:1]];\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn row;\n"
		@"}\n\n"
		@"/* The hub's rows in its members, by entity. */\n"
		@"static PFX_UNUSED NSDictionary *\n"
		@"PFXMemberRows(NSManagedObject *hub, NSArray *members, NSDictionary *values)\n"
		@"{\n"
		@"\tNSMutableDictionary *rows = [NSMutableDictionary dictionary];\n"
		@"\tfor (NSDictionary *member in members) {\n"
		@"\t\tNSManagedObject *row = PFXMemberRow(hub, members, [member objectForKey:@\"entity\"], NO, values);\n"
		@"\t\tif (row != nil) {\n"
		@"\t\t\t[rows setObject:row forKey:[member objectForKey:@\"entity\"]];\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn rows;\n"
		@"}\n\n"
		@"/* Each row joined again by the values of the one it joins to, as they are now. */\n"
		@"static PFX_UNUSED void\n"
		@"PFXRejoin(NSManagedObject *hub, NSArray *members, NSDictionary *rows)\n"
		@"{\n"
		@"\tfor (NSDictionary *member in members) {\n"
		@"\t\tNSManagedObject *row = [rows objectForKey:[member objectForKey:@\"entity\"]];\n"
		@"\t\tNSString *viaName = [member objectForKey:@\"via\"];\n"
		@"\t\tNSManagedObject *via = [[[hub entity] name] isEqualToString:viaName] ? hub : [rows objectForKey:viaName];\n"
		@"\t\tif (row == nil || via == nil) {\n"
		@"\t\t\tcontinue;\n"
		@"\t\t}\n"
		@"\t\tfor (NSArray *pair in [member objectForKey:@\"on\"]) {\n"
		@"\t\t\tid value = [via valueForKey:[pair objectAtIndex:0]];\n"
		@"\t\t\tid now = [row valueForKey:[pair objectAtIndex:1]];\n"
		@"\t\t\tif (value != now && ![value isEqual:now]) {\n"
		@"\t\t\t\t[row setValue:value forKey:[pair objectAtIndex:1]];\n"
		@"\t\t\t}\n"
		@"\t\t}\n"
		@"\t}\n"
		@"}\n\n"
		@"/* An outer member's row let go of where it keeps nothing, and nothing joins to it. */\n"
		@"static PFX_UNUSED void\n"
		@"PFXReleaseRow(NSManagedObject *hub, NSArray *members, NSString *entity)\n"
		@"{\n"
		@"\tNSDictionary *member = PFXMember(members, entity);\n"
		@"\tif (member == nil || ![[member objectForKey:@\"outer\"] boolValue]) {\n"
		@"\t\treturn;\n"
		@"\t}\n"
		@"\tNSManagedObject *row = PFXMemberRow(hub, members, entity, NO, nil);\n"
		@"\tif (row == nil) {\n"
		@"\t\treturn;\n"
		@"\t}\n"
		@"\tfor (NSString *key in [member objectForKey:@\"holds\"]) {\n"
		@"\t\tif (PFXPresent(row, key)) {\n"
		@"\t\t\treturn;\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\tfor (NSDictionary *other in members) {\n"
		@"\t\tif ([[other objectForKey:@\"via\"] isEqualToString:entity]\n"
		@"\t\t    && PFXMemberRow(hub, members, [other objectForKey:@\"entity\"], NO, nil) != nil) {\n"
		@"\t\t\treturn;\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\t[[row managedObjectContext] deleteObject:row];\n"
		@"\tPFXReleaseRow(hub, members, [member objectForKey:@\"via\"]);\n"
		@"}\n\n"
		@"/* What saving does for a type's hub objects: a new one's rows in its inner\n"
		@" * members made, a gone one's rows deleted, a changed one's joined again. NO\n"
		@" * where a row cannot be made: no value to join it by. */\n"
		@"static PFX_UNUSED void\n"
		@"PFXPrepareJoined(NSSet *changed, NSString *hubName, NSArray *members, NSMutableArray<NSError *> *violations)\n"
		@"{\n"
		@"\tfor (NSManagedObject *hub in [changed allObjects]) {\n"
		@"\t\tif (![[[hub entity] name] isEqualToString:hubName]) {\n"
		@"\t\t\tcontinue;\n"
		@"\t\t}\n"
		@"\t\tif ([hub isDeleted]) {\n"
		@"\t\t\tfor (NSManagedObject *row in [PFXMemberRows(hub, members, [hub committedValuesForKeys:nil]) allValues]) {\n"
		@"\t\t\t\t[[hub managedObjectContext] deleteObject:row];\n"
		@"\t\t\t}\n"
		@"\t\t\tcontinue;\n"
		@"\t\t}\n"
		@"\t\tif (![hub isInserted]) {\n"
		@"\t\t\tPFXRejoin(hub, members, PFXMemberRows(hub, members, [hub committedValuesForKeys:nil]));\n"
		@"\t\t\tcontinue;\n"
		@"\t\t}\n"
		@"\t\tfor (NSDictionary *member in members) {\n"
		@"\t\t\tif ([[member objectForKey:@\"outer\"] boolValue]\n"
		@"\t\t\t    || PFXMemberRow(hub, members, [member objectForKey:@\"entity\"], YES, nil) != nil) {\n"
		@"\t\t\t\tcontinue;\n"
		@"\t\t\t}\n"
		@"\t\t\tNSString *text = [NSString stringWithFormat:@\"%@ has no value to keep its %@ row by.\", hubName,\n"
		@"\t\t\t                                             [member objectForKey:@\"entity\"]];\n"
		@"\t\t\t[violations addObject:PFXViolation(hub, @\"Joined\", text, @[])];\n"
		@"\t\t}\n"
		@"\t}\n"
		@"}\n\n"
		@"@implementation PFXJoined\n"
		@"{\n"
		@"\tNSManagedObject *_object;\n"
		@"}\n\n"
		@"+ (NSArray *)members\n"
		@"{\n"
		@"\treturn @[];\n"
		@"}\n\n"
		@"- (instancetype)initWithObject:(NSManagedObject *)object\n"
		@"{\n"
		@"\tif ((self = [super init])) {\n"
		@"\t\t_object = object;\n"
		@"\t}\n"
		@"\treturn self;\n"
		@"}\n\n"
		@"- (NSManagedObject *)object\n"
		@"{\n"
		@"\treturn _object;\n"
		@"}\n\n"
		@"- (BOOL)isEqual:(id)other\n"
		@"{\n"
		@"\treturn [other isKindOfClass:[PFXJoined class]] && [((PFXJoined *)other).object isEqual:_object];\n"
		@"}\n\n"
		@"- (NSUInteger)hash\n"
		@"{\n"
		@"\treturn [_object hash];\n"
		@"}\n\n"
		@"- (NSManagedObject *)rowIn:(NSString *)entityName\n"
		@"{\n"
		@"\treturn PFXMemberRow(_object, [[self class] members], entityName, NO, nil);\n"
		@"}\n\n"
		@"- (id)valueForKey:(NSString *)key in:(NSString *)entityName\n"
		@"{\n"
		@"\treturn [[self rowIn:entityName] valueForKey:key];\n"
		@"}\n\n"
		@"- (void)setValue:(id)value forKey:(NSString *)key in:(NSString *)entityName\n"
		@"{\n"
		@"\tNSArray *members = [[self class] members];\n"
		@"\tBOOL some = value != nil && !([value respondsToSelector:@selector(count)] && [value count] == 0);\n"
		@"\tNSManagedObject *row = PFXMemberRow(_object, members, entityName, some, nil);\n"
		@"\tif (row == nil) {\n"
		@"\t\tif (some) {\n"
		@"\t\t\t[NSException raise:NSInternalInconsistencyException\n"
		@"\t\t\t            format:@\"%@ has no value to keep its %@ row by.\", [[_object entity] name], entityName];\n"
		@"\t\t}\n"
		@"\t\treturn;\n"
		@"\t}\n"
		@"\tNSDictionary *rows = PFXMemberRows(_object, members, nil);\n"
		@"\t[row setValue:value forKey:key];\n"
		@"\tPFXRejoin(_object, members, rows);\n"
		@"\tif (!some && row != _object) {\n"
		@"\t\tPFXReleaseRow(_object, members, entityName);\n"
		@"\t}\n"
		@"}\n\n"
		@"- (void)delete\n"
		@"{\n"
		@"\tfor (NSManagedObject *row in [PFXMemberRows(_object, [[self class] members], nil) allValues]) {\n"
		@"\t\t[[row managedObjectContext] deleteObject:row];\n"
		@"\t}\n"
		@"\t[[_object managedObjectContext] deleteObject:_object];\n"
		@"}\n\n"
		@"@end\n"];
	for (ORMJoinedType *joined in _types) {
		NSString *class = joined.className;
		[out appendFormat:@"\nstatic NSArray *\n"
		                  @"PFX%@Members(void)\n"
		                  @"{\n"
		                  @"\treturn %@;\n"
		                  @"}\n\n"
		                  @"@implementation %@\n\n"
		                  @"+ (NSArray *)members\n"
		                  @"{\n"
		                  @"\treturn PFX%@Members();\n"
		                  @"}\n\n"
		                  @"+ (NSArray<%@ *> *)allInContext:(NSManagedObjectContext *)context\n"
		                  @"{\n"
		                  @"\tNSMutableArray *all = [NSMutableArray array];\n"
		                  @"\tfor (NSManagedObject *object in [context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:%@]\n"
		                  @"\t                                                       error:NULL]) {\n"
		                  @"\t\t[all addObject:[[self alloc] initWithObject:object]];\n"
		                  @"\t}\n"
		                  @"\treturn all;\n"
		                  @"}\n\n"
		                  @"+ (instancetype)insertInContext:(NSManagedObjectContext *)context\n"
		                  @"{\n"
		                  @"\treturn [[self alloc] initWithObject:[NSEntityDescription insertNewObjectForEntityForName:%@\n"
		                  @"\t                                                          inManagedObjectContext:context]];\n"
		                  @"}\n",
		                  class, [self membersLiteralOf:joined], class, class, class, ORMQuoted(joined.hub.name),
		                  ORMQuoted(joined.hub.name)];
		for (NSArray *property in joined.properties) {
			NSString *name = [property firstObject];
			NSString *declared = [property lastObject];
			NSString *space = [declared hasSuffix:@"*"] ? @"" : @" ";
			[out appendFormat:@"\n- (%@)%@\n"
			                  @"{\n"
			                  @"\treturn [self valueForKey:%@ in:%@];\n"
			                  @"}\n\n"
			                  @"- (void)set%@:(%@)%@value\n"
			                  @"{\n"
			                  @"\t[self setValue:value forKey:%@ in:%@];\n"
			                  @"}\n",
			                  declared, name, ORMQuoted([property objectAtIndex:1]), ORMQuoted([property objectAtIndex:2]),
			                  ORMUpper(name), declared, space, ORMQuoted([property objectAtIndex:1]),
			                  ORMQuoted([property objectAtIndex:2])];
		}
		[out appendString:@"\n@end\n"];
	}
	/* The base class's private methods, declared for the classes'. */
	NSString *declarations = @"\n@interface PFXJoined ()\n"
	                         @"+ (NSArray *)members;\n"
	                         @"- (id)valueForKey:(NSString *)key in:(NSString *)entityName;\n"
	                         @"- (void)setValue:(id)value forKey:(NSString *)key in:(NSString *)entityName;\n"
	                         @"@end\n";
	return [[declarations stringByAppendingString:out] stringByReplacingOccurrencesOfString:@"PFX" withString:_prefix];
}

- (NSString *)saveStatements
{
	NSMutableString *out = [NSMutableString string];
	for (ORMJoinedType *joined in _types) {
		[out appendFormat:@"\t/* %@, joined: its members' rows kept with it. */\n"
		                  @"\tPFXPrepareJoined(changed, %@, PFX%@Members(), violations);\n",
		                  [joined.type.name stringByReplacingOccurrencesOfString:@"*/" withString:@"* /"],
		                  ORMQuoted(joined.hub.name), joined.className];
	}
	return [out stringByReplacingOccurrencesOfString:@"PFX" withString:_prefix];
}

@end
