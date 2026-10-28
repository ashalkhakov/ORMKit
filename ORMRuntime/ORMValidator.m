/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMValidator.h"
#import "ORMQueryInterpreter.h"
#import <CoreData/CoreData.h>

/* Whether the value is an object deleted in its context, which counts
 * for nothing: a to-many may hold it until the context's pending changes
 * are processed (and after, where the rule is no action). */
static BOOL
ORMIsDeleted(id value)
{
	return [value isKindOfClass:[NSManagedObject class]] && [(NSManagedObject *)value isDeleted];
}

/* What the property holds, as a set: nothing, one value, or a to-many's
 * objects; none deleted. */
static NSSet *
ORMRelatedSet(id object, NSString *key)
{
	id value = [object valueForKey:key];
	if (value == nil || ORMIsDeleted(value)) {
		return [NSSet set];
	}
	NSSet *members = nil;
	if ([value isKindOfClass:[NSSet class]]) {
		members = value;
	} else if ([value isKindOfClass:[NSOrderedSet class]]) {
		members = [(NSOrderedSet *)value set];
	} else if ([value isKindOfClass:[NSArray class]]) {
		members = [NSSet setWithArray:value];
	} else {
		return [NSSet setWithObject:value];
	}
	for (id member in members) {
		if (ORMIsDeleted(member)) {
			NSMutableSet *live = [NSMutableSet set];
			for (id each in members) {
				if (!ORMIsDeleted(each)) {
					[live addObject:each];
				}
			}
			return live;
		}
	}
	return members;
}

/* Everything reachable from the objects through the relationship, them
 * included. */
static NSSet *
ORMReachable(NSSet *from, NSString *key)
{
	NSMutableSet *seen = [NSMutableSet setWithSet:from];
	NSMutableArray *pending = [NSMutableArray arrayWithArray:[from allObjects]];
	while ([pending count] > 0) {
		id at = [pending lastObject];
		[pending removeLastObject];
		for (id next in ORMRelatedSet(at, key)) {
			if (![seen containsObject:next]) {
				[seen addObject:next];
				[pending addObject:next];
			}
		}
	}
	return seen;
}

/* Whether the ring property holds of the object's relationship to
 * objects of its own entity. */
static BOOL
ORMRingHolds(NSString *property, id object, NSString *key)
{
	NSSet *related = ORMRelatedSet(object, key);
	if ([property isEqualToString:@"irreflexive"]) {
		return ![related containsObject:object];
	}
	if ([property isEqualToString:@"reflexive"]) {
		/* Related to anything, related to itself. */
		return [related count] == 0 || [related containsObject:object];
	}
	if ([property isEqualToString:@"purelyReflexive"]) {
		return [related count] == 0 || [related isEqualToSet:[NSSet setWithObject:object]];
	}
	if ([property isEqualToString:@"acyclic"]) {
		return ![ORMReachable(related, key) containsObject:object];
	}
	if ([property isEqualToString:@"stronglyIntransitive"]) {
		/* Nothing related directly is also reached the long way round. */
		NSMutableSet *second = [NSMutableSet set];
		for (id other in related) {
			[second unionSet:ORMRelatedSet(other, key)];
		}
		return ![ORMReachable(second, key) intersectsSet:related];
	}
	for (id other in related) {
		NSSet *back = ORMRelatedSet(other, key);
		if ([property isEqualToString:@"symmetric"] && ![back containsObject:object]) {
			return NO;
		}
		if ([property isEqualToString:@"asymmetric"] && [back containsObject:object]) {
			return NO;
		}
		if ([property isEqualToString:@"antisymmetric"] && other != object && [back containsObject:object]) {
			return NO;
		}
		if ([property isEqualToString:@"transitive"] && ![back isSubsetOfSet:related]) {
			return NO;
		}
		if ([property isEqualToString:@"intransitive"] && [back intersectsSet:related]) {
			return NO;
		}
	}
	return YES;
}

/* The two values compared by the comparison. */
static BOOL
ORMCompares(id a, id b, NSString *comparison)
{
	NSComparisonResult order = [a compare:b];
	if ([comparison isEqualToString:@"<"]) {
		return order == NSOrderedAscending;
	}
	if ([comparison isEqualToString:@"<="]) {
		return order != NSOrderedDescending;
	}
	if ([comparison isEqualToString:@">"]) {
		return order == NSOrderedDescending;
	}
	if ([comparison isEqualToString:@">="]) {
		return order != NSOrderedAscending;
	}
	if ([comparison isEqualToString:@"=="]) {
		return order == NSOrderedSame;
	}
	return order != NSOrderedSame;
}

/* Whether the number is within the range. */
static BOOL
ORMWithin(double value, NSDictionary *range)
{
	NSNumber *min = [range objectForKey:@"min"];
	NSNumber *max = [range objectForKey:@"max"];
	if (min != nil && ([[range objectForKey:@"minOpen"] boolValue] ? value <= [min doubleValue] : value < [min doubleValue])) {
		return NO;
	}
	if (max != nil && ([[range objectForKey:@"maxOpen"] boolValue] ? value >= [max doubleValue] : value > [max doubleValue])) {
		return NO;
	}
	return YES;
}

static NSError *
ORMViolation(NSManagedObject *object, ORMRule *rule)
{
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	[info setObject:rule.text ?: rule.constraint ?: @"" forKey:NSLocalizedDescriptionKey];
	[info setObject:object forKey:NSValidationObjectErrorKey];
	if ([rule.keys count] > 0) {
		[info setObject:[rule.keys firstObject] forKey:NSValidationKeyErrorKey];
	}
	[info setObject:rule.constraint ?: @"" forKey:@"ORMConstraint"];
	[info setObject:rule.keys forKey:@"ORMKeys"];
	return [NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectValidationError userInfo:info];
}

@implementation ORMValidator
{
	/* A plan check's predicate, by the check and the model it is asked in. */
	NSMapTable<ORMRuleCheck *, NSMutableDictionary *> *_predicates;
}

- (instancetype)initWithTables:(ORMTables *)tables
{
	if ((self = [super init])) {
		_tables = tables;
		_predicates = [NSMapTable strongToStrongObjectsMapTable];
	}
	return self;
}

+ (instancetype)validatorNamed:(NSString *)name error:(NSError **)error
{
	static NSMutableDictionary<NSString *, ORMValidator *> *validators;
	@synchronized(self) {
		validators = validators ?: [NSMutableDictionary dictionary];
		ORMTables *tables = [ORMTables tablesNamed:name error:error];
		if (tables == nil) {
			return nil;
		}
		ORMValidator *validator = [validators objectForKey:name];
		if (validator == nil || validator.tables != tables) {
			validator = [[ORMValidator alloc] initWithTables:tables];
			[validators setObject:validator forKey:name];
		}
		return validator;
	}
}

/* The plan's condition as a predicate over the object read, in the
 * object's model, made once. */
- (NSPredicate *)predicateOf:(ORMRuleCheck *)check model:(NSManagedObjectModel *)model
{
	NSMutableDictionary *byModel = [_predicates objectForKey:check];
	if (byModel == nil) {
		byModel = [NSMutableDictionary dictionary];
		[_predicates setObject:byModel forKey:check];
	}
	NSValue *key = [NSValue valueWithNonretainedObject:model];
	id predicate = [byModel objectForKey:key];
	if (predicate == nil) {
		predicate = [[[ORMQueryInterpreter alloc] initWithModel:model] predicateForPlan:check.plan reason:NULL]
			?: (id)[NSNull null];
		[byModel setObject:predicate forKey:key];
	}
	return predicate != [NSNull null] ? predicate : nil;
}

/* No other object of the entity that has the keys (its own, or the
 * topmost of its ancestors that has them all), saved or in the context,
 * not deleted, has the object's values of them; one with a key not set
 * holds. A store's own uniqueness constraint is not every store's (not
 * FreeCoreData's), nor said in the model's words. */
static BOOL
ORMUniqueHolds(NSManagedObject *object, NSArray<NSString *> *keys)
{
	NSMutableArray *conditions = [NSMutableArray array];
	NSMutableArray *values = [NSMutableArray array];
	for (NSString *key in keys) {
		id value = [object valueForKey:key];
		if (value == nil) {
			return YES;
		}
		[conditions addObject:@"%K == %@"];
		[values addObject:key];
		[values addObject:value];
	}
	NSEntityDescription *entity = [object entity];
	while (entity.superentity != nil) {
		BOOL has = YES;
		for (NSString *key in keys) {
			has = has && [entity.superentity.propertiesByName objectForKey:key] != nil;
		}
		if (!has) {
			break;
		}
		entity = entity.superentity;
	}
	NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
	fetch.entity = entity;
	fetch.predicate = [NSPredicate predicateWithFormat:[conditions componentsJoinedByString:@" AND "] argumentArray:values];
	NSArray *alike = [[object managedObjectContext] executeFetchRequest:fetch error:NULL];
	for (NSManagedObject *other in alike) {
		if (other != object && ![other isDeleted]) {
			return NO;
		}
	}
	return YES;
}

- (BOOL)check:(ORMRuleCheck *)check holdsOf:(NSManagedObject *)object
{
	NSString *kind = check.kind;
	NSString *key = [check.keys firstObject];
	if ([kind isEqualToString:@"present"]) {
		return [ORMRelatedSet(object, key) count] > 0;
	}
	if ([kind isEqualToString:@"true"]) {
		/* A unary's attribute: absent is false. */
		return [[object valueForKey:key] boolValue];
	}
	if ([kind isEqualToString:@"all"] || [kind isEqualToString:@"any"]) {
		BOOL all = [kind isEqualToString:@"all"];
		for (ORMRuleCheck *operand in check.operands) {
			if ([self check:operand holdsOf:object] != all) {
				return !all;
			}
		}
		return all;
	}
	if ([kind isEqualToString:@"not"]) {
		return ![self check:[check.operands firstObject] holdsOf:object];
	}
	if ([kind isEqualToString:@"count"]) {
		NSUInteger holding = 0;
		for (ORMRuleCheck *operand in check.operands) {
			holding += [self check:operand holdsOf:object] ? 1 : 0;
		}
		return check.exactly ? holding == check.number : holding <= check.number;
	}
	if ([kind isEqualToString:@"sets"]) {
		NSSet *a = ORMRelatedSet(object, key);
		NSSet *b = ORMRelatedSet(object, [check.keys lastObject]);
		if ([check.relation isEqualToString:@"disjoint"]) {
			return ![a intersectsSet:b];
		}
		return [check.relation isEqualToString:@"subset"] ? [a isSubsetOfSet:b] : [a isEqualToSet:b];
	}
	if ([kind isEqualToString:@"ring"]) {
		for (NSString *property in check.properties) {
			if (!ORMRingHolds(property, object, key)) {
				return NO;
			}
		}
		return YES;
	}
	if ([kind isEqualToString:@"unique"]) {
		return ORMUniqueHolds(object, check.keys);
	}
	if ([kind isEqualToString:@"compare"]) {
		id a = [object valueForKey:key];
		id b = [object valueForKey:[check.keys lastObject]];
		/* When both are set. */
		return a == nil || b == nil || ORMCompares(a, b, check.comparison);
	}
	if ([kind isEqualToString:@"within"]) {
		id value = [object valueForKey:key];
		if (value == nil) {
			return YES;
		}
		for (NSDictionary *range in check.ranges) {
			if (ORMWithin([value doubleValue], range)) {
				return YES;
			}
		}
		return NO;
	}
	if ([kind isEqualToString:@"plan"]) {
		NSManagedObjectModel *model = [[object entity] managedObjectModel];
		if (![[object entity] isKindOfEntity:[[model entitiesByName] objectForKey:check.plan.entityName]]) {
			return NO;
		}
		NSPredicate *predicate = [self predicateOf:check model:model];
		ORMQueryInterpreter *interpreter = nil;
		/* With objects deleted in the context, which a predicate would
		 * count among those of a to-many still holding them: asked by the
		 * interpreter, which passes them by, where it can be. */
		if (predicate != nil && [[[object managedObjectContext] deletedObjects] count] > 0) {
			interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
			if (![interpreter asksOfOneObject:check.plan reason:NULL]) {
				interpreter = nil;
			}
		}
		/* No predicate (a value computed): the plan asked of the object. */
		return predicate != nil && interpreter == nil
			? [predicate evaluateWithObject:object]
			: [interpreter ?: [[ORMQueryInterpreter alloc] initWithModel:model] plan:check.plan holdsOf:object];
	}
	return YES;
}

- (NSArray<NSError *> *)violationsOf:(NSManagedObject *)object deontic:(BOOL)deontic
{
	NSMutableArray *violations = [NSMutableArray array];
	/* The ancestors' rules first, as Core Data checks a superentity's. */
	NSMutableArray *entities = [NSMutableArray array];
	for (NSEntityDescription *entity = [object entity]; entity != nil; entity = [entity superentity]) {
		[entities insertObject:entity atIndex:0];
	}
	for (NSEntityDescription *entity in entities) {
		for (ORMRule *rule in [self.tables.rules objectForKey:[entity name]]) {
			if (rule.deontic == deontic && ![self check:rule.check holdsOf:object]) {
				[violations addObject:ORMViolation(object, rule)];
			}
		}
	}
	return violations;
}

- (BOOL)validate:(NSManagedObject *)object error:(NSError **)error
{
	return [ORMValidator report:[self violationsOf:object deontic:NO] error:error];
}

+ (BOOL)report:(NSArray<NSError *> *)violations error:(NSError **)error
{
	if ([violations count] == 0) {
		return YES;
	}
	if (error != NULL) {
		/* Under each name Apple's has filed them by: NSDetailedErrorsKey is
		 * "NSDetailedErrors" in a program built for macOS 12 or later, and
		 * itself before; a reader looks under its own. */
		NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:@"Several constraints are violated."
		                                                               forKey:NSLocalizedDescriptionKey];
		for (NSString *key in @[ NSDetailedErrorsKey, @"NSDetailedErrors", @"NSDetailedErrorsKey" ]) {
			[info setObject:violations forKey:key];
		}
		*error = [violations count] == 1
			? [violations firstObject]
			: [NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMultipleErrorsError userInfo:info];
	}
	return NO;
}

@end
