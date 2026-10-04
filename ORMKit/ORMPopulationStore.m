/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPopulationStore.h"
#import "ORMCDModel+CoreData.h"
#import "ORMPath.h"
#import "ORMQueryPlaces.h"
#import <CoreData/CoreData.h>

/* A fact of the population: its fact type, and the instance playing each
 * role, by role id. */
@interface ORMPopulationFact : NSObject
/* The fact instance's id; nil for an identifying fact. */
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) ORMFactType *factType;
@property (nonatomic, copy) NSDictionary<NSString *, ORMInstance *> *byRole;
@end

@implementation ORMPopulationFact
@end

@implementation ORMPopulationStore
{
	ORMQueryPlaces *_places;
	NSMutableArray<NSString *> *_notes;
	NSMutableDictionary<NSString *, NSManagedObject *> *_objects;
	NSManagedObjectContext *_context;
	/* "role instance" to the facts the instance plays the role in. */
	NSMutableDictionary<NSString *, NSMutableArray<ORMPopulationFact *> *> *_played;
	NSDateFormatter *_dates;
	/* The facts an absorbed object type's parts were read from: kept in
	 * the attributes of those that absorb it. */
	NSHashTable<ORMPopulationFact *> *_reached;
	/* A fact instance's id to its objectifying instance's object. */
	NSMutableDictionary<NSString *, NSManagedObject *> *_objectified;
}

- (instancetype)initWithModel:(ORMModel *)model coreData:(ORMCDModel *)coreData
{
	if ((self = [super init])) {
		_model = model;
		_coreData = coreData;
		_places = [[ORMQueryPlaces alloc] initWithCoreData:coreData];
		_managedObjectModel = [self relaxed:[coreData managedObjectModel]];
		_notes = [NSMutableArray array];
	}
	return self;
}

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
}

- (NSManagedObjectModel *)relaxed:(NSManagedObjectModel *)model
{
	for (NSEntityDescription *entity in [model entities]) {
		for (NSPropertyDescription *property in [entity properties]) {
			[property setOptional:YES];
			if ([property isKindOfClass:[NSRelationshipDescription class]]) {
				[(NSRelationshipDescription *)property setMinCount:0];
			}
		}
	}
	return model;
}

- (NSManagedObject *)objectForInstance:(NSString *)instanceId
{
	return [_objects objectForKey:instanceId];
}

- (void)note:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2)
{
	va_list arguments;
	va_start(arguments, format);
	NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
	va_end(arguments);
	if (![_notes containsObject:text]) {
		[_notes addObject:text];
	}
}

static NSString *
ORMFactName(ORMFactType *fact)
{
	return [[fact primaryReading] expandedText] ?: fact.name;
}

- (ORMCDEntity *)cdEntityNamed:(NSString *)name
{
	for (ORMCDEntity *entity in _coreData.entities) {
		if ([entity.name isEqualToString:name]) {
			return entity;
		}
	}
	return nil;
}

#pragma mark Objects

/* The instance a subtype's instances come down to. */
static ORMInstance *
ORMRootOf(ORMInstance *instance)
{
	while ([instance supertypeInstance] != nil) {
		instance = [instance supertypeInstance];
	}
	return instance;
}

/* An object for each entity instance, of its most specific type's entity;
 * for a value of a type kept as an entity of values, one for the value. */
- (void)makeObjects
{
	NSMutableDictionary<NSString *, NSMutableArray<ORMInstance *> *> *groups = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in _model.objectTypes) {
		for (ORMInstance *instance in [type instances]) {
			if (instance.value != nil) {
				ORMCDEntity *values = [_places entityOf:type];
				if (values != nil) {
					[self makeValueObject:instance entity:values];
				}
				continue;
			}
			NSString *root = ORMRootOf(instance).identifier;
			NSMutableArray *group = [groups objectForKey:root];
			if (group == nil) {
				group = [NSMutableArray array];
				[groups setObject:group forKey:root];
			}
			[group addObject:instance];
		}
	}
	/* An objectifying instance's after the others', in rounds: folded into
	 * one of its fact's players' entities, it is that player's object,
	 * which may itself be folded into another's. */
	NSMutableArray *pending = [NSMutableArray array];
	for (NSString *root in [[groups allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if ([ORMRootOf([[groups objectForKey:root] firstObject]) objectifiedInstance] == nil) {
			[self makeObjectOf:[groups objectForKey:root] last:NO];
		} else {
			[pending addObject:root];
		}
	}
	for (BOOL progress = YES; progress && [pending count] > 0;) {
		progress = NO;
		for (NSString *root in [pending copy]) {
			if ([self makeObjectOf:[groups objectForKey:root] last:NO]) {
				[pending removeObject:root];
				progress = YES;
			}
		}
	}
	for (NSString *root in pending) {
		[self makeObjectOf:[groups objectForKey:root] last:YES];
	}
}

/* The object a group of instances (an instance and its subtypes') is:
 * of its most specific type's entity, or a player's it is folded into.
 * Whether it was made; an objectifying one waits (NO) for the player it is
 * folded into, but for the last time. */
- (BOOL)makeObjectOf:(NSArray<ORMInstance *> *)group last:(BOOL)last
{
	/* The type every other is a supertype of; the deepest one when there
	 * are several. */
	ORMInstance *specific = nil;
	for (ORMInstance *instance in group) {
		if (specific == nil || [instance.objectType isSubtypeOf:specific.objectType]
		    || [[instance.objectType allSupertypes] count] > [[specific.objectType allSupertypes] count]) {
			specific = instance;
		}
	}
	ORMCDEntity *entity = [_places entityOf:specific.objectType];
	ORMFactInstance *objectified = [ORMRootOf(specific) objectifiedInstance];
	NSManagedObject *object = [self foldedObjectOf:ORMRootOf(specific) entity:entity];
	if (object == nil && objectified != nil && !last) {
		/* A player still to be made may be the one it is folded into. */
		for (ORMInstance *player in [objectified.instancesByRole allValues]) {
			if ([ORMRootOf(player) objectifiedInstance] != nil && [_objects objectForKey:player.identifier] == nil) {
				return NO;
			}
		}
		if (entity == nil) {
			return NO;
		}
	}
	for (ORMInstance *instance in group) {
		if (instance != specific && ![specific.objectType isSubtypeOf:instance.objectType]) {
			[self note:@"%@ is a %@ and a %@: it is kept as a %@.", [specific displayText], specific.objectType.name,
			           instance.objectType.name, specific.objectType.name];
		}
	}
	if (entity == nil && object == nil) {
		/* Absorbed: its facts are kept as its players' attributes. */
		return YES;
	}
	if (object == nil) {
		object = [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:_context];
	}
	for (ORMInstance *instance in group) {
		[_objects setObject:object forKey:instance.identifier];
	}
	return YES;
}

- (NSManagedObject *)foldedObjectOf:(ORMInstance *)instance entity:(ORMCDEntity *)entity
{
	ORMFactInstance *fact = [instance objectifiedInstance];
	/* Folded into the player it is one to one with: a unary's, or one
	 * whose role is unique by itself. */
	NSArray *roles = [fact.factType.roles sortedArrayUsingComparator:^NSComparisonResult(ORMRole *a, ORMRole *b) {
		return a.isUnique == b.isUnique ? [@(a.index) compare:@(b.index)] : a.isUnique ? NSOrderedAscending
		                                                                                : NSOrderedDescending;
	}];
	for (ORMRole *role in roles) {
		NSManagedObject *object = [_objects objectForKey:[[fact.instancesByRole objectForKey:role.identifier] identifier] ?: @""];
		ORMCDEntity *its = object != nil ? [self cdEntityNamed:[[object entity] name]] : nil;
		if (its != nil && (entity == nil || its == entity || [_places entity:its inherits:entity])) {
			return object;
		}
	}
	return nil;
}

- (void)makeValueObject:(ORMInstance *)instance entity:(ORMCDEntity *)entity
{
	NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:_context];
	[_objects setObject:object forKey:instance.identifier];
	ORMCDProperty *value = [_places propertyOf:entity
	                                    source:[instance.objectType.identifier stringByAppendingString:@".value"]];
	if ([value isKindOfClass:[ORMCDAttribute class]]) {
		[self set:value of:object to:instance];
	}
}

#pragma mark Facts

/* The facts: each fact instance, and those identifying entity instances. */
- (NSArray<ORMPopulationFact *> *)facts
{
	NSMutableArray *facts = [NSMutableArray array];
	for (ORMFactType *fact in _model.factTypes) {
		for (ORMFactInstance *instance in [fact instances]) {
			ORMPopulationFact *each = [[ORMPopulationFact alloc] init];
			each.identifier = instance.identifier;
			each.factType = fact;
			each.byRole = instance.instancesByRole;
			[facts addObject:each];
		}
	}
	for (ORMObjectType *type in _model.objectTypes) {
		for (ORMInstance *instance in [type instances]) {
			NSDictionary *identifying = [instance identifyingInstancesByRole];
			for (NSString *roleId in identifying) {
				ORMRole *role = [_model elementWithId:roleId];
				ORMRole *other = nil;
				for (ORMRole *each in role.factType.roles) {
					if (each != role) {
						other = each;
					}
				}
				if (other == nil || [role.factType.roles count] != 2) {
					continue;
				}
				ORMPopulationFact *each = [[ORMPopulationFact alloc] init];
				each.factType = role.factType;
				each.byRole = @{ roleId: [identifying objectForKey:roleId], other.identifier: instance };
				[facts addObject:each];
			}
		}
	}
	return facts;
}

static NSString *
ORMPlayedKey(NSString *roleId, ORMInstance *instance)
{
	return [NSString stringWithFormat:@"%@ %@", roleId, instance.identifier];
}

/* What the trace reaches from the instance: "/role/role", each role's fact
 * followed from the instance playing its other role. */
- (ORMInstance *)follow:(NSString *)trace from:(ORMInstance *)instance
{
	for (NSString *roleId in [trace componentsSeparatedByString:@"/"]) {
		if ([roleId length] == 0) {
			continue;
		}
		ORMRole *role = [_model elementWithId:roleId];
		ORMRole *other = nil;
		for (ORMRole *each in role.factType.roles) {
			if (each != role) {
				other = each;
			}
		}
		ORMPopulationFact *fact = other != nil ? [[_played objectForKey:ORMPlayedKey(other.identifier, instance)]
		                                           firstObject]
		                                       : nil;
		instance = [fact.byRole objectForKey:roleId];
		if (instance == nil) {
			return nil;
		}
		[_reached addObject:fact];
	}
	return instance;
}

/* The fact set as a player's property: each player's object, the property
 * traced to each other role (or the absorbed parts under it). Whether
 * there was one. */
- (BOOL)placeOnPlayers:(ORMPopulationFact *)fact
{
	BOOL placed = NO;
	for (ORMRole *role in fact.factType.roles) {
		NSManagedObject *object = [_objects objectForKey:[[fact.byRole objectForKey:role.identifier] identifier] ?: @""];
		ORMCDEntity *entity = object != nil ? [self cdEntityNamed:[[object entity] name]] : nil;
		if (entity == nil) {
			continue;
		}
		for (ORMRole *other in fact.factType.roles) {
			if (other == role) {
				continue;
			}
			ORMInstance *player = [fact.byRole objectForKey:other.identifier];
			ORMCDProperty *property = [_places propertyOf:entity source:other.identifier];
			if (property != nil) {
				placed = [self set:property of:object to:player] || placed;
				continue;
			}
			for (NSArray *part in [_places absorbedParts:other.identifier on:entity]) {
				ORMInstance *reached = player != nil ? [self follow:[part firstObject] from:player] : nil;
				if (reached != nil) {
					placed = [self set:[part lastObject] of:object to:reached] || placed;
				}
			}
		}
	}
	return placed;
}

/* The fact as an object of its own entity: a property for each role. */
- (BOOL)placeAsObject:(ORMPopulationFact *)fact
{
	ORMFactType *factType = fact.factType;
	ORMCDEntity *entity = nil;
	for (ORMCDEntity *each in _coreData.entities) {
		if ([each.source isEqualToString:factType.identifier]) {
			entity = each;
		}
	}
	if (entity == nil && factType.objectifyingType != nil) {
		entity = [_places entityOf:factType.objectifyingType];
	}
	if (entity == nil) {
		return NO;
	}
	/* An objectified fact is the object its objectifying instance is. */
	NSManagedObject *object = fact.identifier != nil ? [_objectified objectForKey:fact.identifier] : nil;
	if (object == nil) {
		object = [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:_context];
	}
	for (ORMRole *role in factType.roles) {
		ORMInstance *player = [fact.byRole objectForKey:role.identifier];
		ORMCDProperty *property = [_places propertyOf:entity source:role.identifier];
		if (property != nil) {
			[self set:property of:object to:player];
			continue;
		}
		for (NSArray *part in [_places absorbedParts:role.identifier on:entity]) {
			ORMInstance *reached = player != nil ? [self follow:[part firstObject] from:player] : nil;
			if (reached != nil) {
				[self set:[part lastObject] of:object to:reached];
			}
		}
	}
	return YES;
}

#pragma mark Values

/* The attribute's type as the store has it, in the mapping's spelling: what
 * the value is converted to. */
static NSString *
ORMStoreTypeOf(NSAttributeDescription *attribute, NSString *mapped)
{
	switch ([attribute attributeType]) {
	case NSInteger16AttributeType:
	case NSInteger32AttributeType:
	case NSInteger64AttributeType:
		return @"Integer 64";
	case NSDecimalAttributeType:
		return @"Decimal";
	case NSDoubleAttributeType:
	case NSFloatAttributeType:
		return @"Double";
	case NSBooleanAttributeType:
		return @"Boolean";
	case NSDateAttributeType:
		return @"Date";
	case NSBinaryDataAttributeType:
		return @"Binary";
	case NSTransformableAttributeType:
		return @"Transformable";
	case NSStringAttributeType:
		return @"String";
	default:
		return mapped;
	}
}

- (id)valueOf:(NSString *)text type:(NSString *)attributeType
{
	NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if ([attributeType hasPrefix:@"Integer"]) {
		NSScanner *scanner = [NSScanner scannerWithString:trimmed];
		long long number;
		return [scanner scanLongLong:&number] && [scanner isAtEnd] ? @(number) : nil;
	}
	if ([attributeType isEqualToString:@"Decimal"]) {
		NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:trimmed
		                                                            locale:@{ NSLocaleDecimalSeparator: @"." }];
		return [number isEqualToNumber:[NSDecimalNumber notANumber]] ? nil : number;
	}
	if ([attributeType isEqualToString:@"Double"] || [attributeType isEqualToString:@"Float"]) {
		NSScanner *scanner = [NSScanner scannerWithString:trimmed];
		double number;
		return [scanner scanDouble:&number] && [scanner isAtEnd] ? @(number) : nil;
	}
	if ([attributeType isEqualToString:@"Boolean"]) {
		NSString *lower = [trimmed lowercaseString];
		if ([@[ @"true", @"yes", @"1" ] containsObject:lower]) {
			return @YES;
		}
		return [@[ @"false", @"no", @"0" ] containsObject:lower] ? @NO : nil;
	}
	if ([attributeType isEqualToString:@"Date"]) {
		return [self dateOf:trimmed];
	}
	if ([attributeType isEqualToString:@"Binary"]) {
		return [text dataUsingEncoding:NSUTF8StringEncoding];
	}
	if ([attributeType isEqualToString:@"UUID"]) {
		return [[NSUUID alloc] initWithUUIDString:trimmed];
	}
	if ([attributeType isEqualToString:@"URI"]) {
		return [NSURL URLWithString:trimmed];
	}
	return text;
}

/* A date as NORMA's samples write one: a day, a moment, or a time. */
- (NSDate *)dateOf:(NSString *)text
{
	if (_dates == nil) {
		_dates = [[NSDateFormatter alloc] init];
		[_dates setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
		[_dates setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	}
	for (NSString *format in @[ @"yyyy-MM-dd'T'HH:mm:ss", @"yyyy-MM-dd HH:mm:ss", @"yyyy-MM-dd'T'HH:mm",
	                            @"yyyy-MM-dd HH:mm", @"yyyy-MM-dd", @"HH:mm:ss", @"HH:mm" ]) {
		[_dates setDateFormat:format];
		NSDate *date = [_dates dateFromString:text];
		if (date != nil) {
			return date;
		}
	}
	return nil;
}

/* An attribute's value for the instance: a value's, converted to the
 * type the store has (type); the value identifying an entity whose type has
 * no entity of its own; YES for a unary's, which has no instance, or its
 * implicit truth. */
- (id)attributeValue:(ORMCDAttribute *)attribute type:(NSString *)type for:(ORMInstance *)instance
{
	if (instance == nil || instance.objectType.isImplicitBooleanValue) {
		return [type isEqualToString:@"Boolean"] ? @YES : nil;
	}
	while (instance.value == nil && [[instance identifyingInstancesByRole] count] == 1) {
		instance = [[[instance identifyingInstancesByRole] allValues] firstObject];
	}
	if (instance.value == nil) {
		return nil;
	}
	id value = [self valueOf:instance.value type:type];
	if (value == nil) {
		[self note:@"%@ is no %@ (%@).", [instance displayText], type, attribute.name];
	}
	return value;
}

/* The property of the object set to the instance, or the instance added
 * to it. Whether it was. */
- (BOOL)set:(ORMCDProperty *)property of:(NSManagedObject *)object to:(ORMInstance *)instance
{
	if ([property isKindOfClass:[ORMCDRelationship class]]) {
		ORMCDRelationship *relationship = (ORMCDRelationship *)property;
		NSManagedObject *target = [_objects objectForKey:instance.identifier ?: @""];
		if (target == nil) {
			return NO;
		}
		if (!relationship.toMany) {
			[object setValue:target forKey:relationship.name];
		} else if (relationship.ordered) {
			[[object mutableOrderedSetValueForKey:relationship.name] addObject:target];
		} else {
			[[object mutableSetValueForKey:relationship.name] addObject:target];
		}
		return YES;
	}
	ORMCDAttribute *attribute = (ORMCDAttribute *)property;
	NSString *type = ORMStoreTypeOf([[[object entity] attributesByName] objectForKey:attribute.name],
	                                attribute.attributeType);
	id value = [self attributeValue:attribute type:type for:instance];
	if (value == nil) {
		return NO;
	}
	if ([type isEqualToString:@"Transformable"]) {
		/* Many values for one instance, as an array. */
		NSArray *values = [object valueForKey:attribute.name] ?: @[];
		value = [values arrayByAddingObject:value];
	}
	[object setValue:value forKey:attribute.name];
	return YES;
}

#pragma mark The store

- (NSManagedObjectContext *)newContextWithError:(NSError **)error
{
	[_notes removeAllObjects];
	_objects = [NSMutableDictionary dictionary];
	_played = [NSMutableDictionary dictionary];
	_reached = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	NSPersistentStoreCoordinator *coordinator =
		[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_managedObjectModel];
	if ([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil
	                                      error:error] == nil) {
		return nil;
	}
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	[context setPersistentStoreCoordinator:coordinator];
	_context = context;
	[self makeObjects];
	_objectified = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in _model.objectTypes) {
		for (ORMInstance *instance in [type instances]) {
			NSManagedObject *object = [_objects objectForKey:instance.identifier];
			ORMFactInstance *fact = [instance objectifiedInstance];
			if (object != nil && fact != nil) {
				[_objectified setObject:object forKey:fact.identifier];
			}
		}
	}
	NSArray *facts = [self facts];
	for (ORMPopulationFact *fact in facts) {
		for (NSString *roleId in fact.byRole) {
			NSString *key = ORMPlayedKey(roleId, [fact.byRole objectForKey:roleId]);
			NSMutableArray *list = [_played objectForKey:key];
			if (list == nil) {
				list = [NSMutableArray array];
				[_played setObject:list forKey:key];
			}
			[list addObject:fact];
		}
	}
	NSMutableArray *unplaced = [NSMutableArray array];
	for (ORMPopulationFact *fact in facts) {
		if (fact.factType.kind != ORMFactTypeOrdinary) {
			continue;
		}
		if ([fact.byRole count] < [[fact.factType visibleRoles] count]) {
			[self note:@"A fact of \"%@\" lacks a role's player: it is left out.", ORMFactName(fact.factType)];
			continue;
		}
		if (![self placeOnPlayers:fact] && ![self placeAsObject:fact]) {
			[unplaced addObject:fact];
		}
	}
	for (ORMPopulationFact *fact in unplaced) {
		/* A fact of instances absorbed into others is kept where they are
		 * used, or nowhere when none is: only one with an object to be kept
		 * on is missing from the store. */
		BOOL objects = NO;
		for (ORMInstance *player in [fact.byRole allValues]) {
			objects = objects || [_objects objectForKey:player.identifier] != nil;
		}
		if (objects && ![_reached containsObject:fact]) {
			[self note:@"\"%@\" is kept nowhere in the store.", ORMFactName(fact.factType)];
		}
	}
	_context = nil;
	if (![context save:error]) {
		return nil;
	}
	return context;
}

@end
