/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMValidator.h"
#import "ORMQueryInterpreter.h"
#import <CoreData/CoreData.h>

/* What the property holds, as a set: nothing, one value, or a to-many's
 * objects. */
static NSSet *
ORMRelatedSet(id object, NSString *key)
{
	id value = [object valueForKey:key];
	if (value == nil) {
		return [NSSet set];
	}
	if ([value isKindOfClass:[NSSet class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSOrderedSet class]]) {
		return [(NSOrderedSet *)value set];
	}
	if ([value isKindOfClass:[NSArray class]]) {
		return [NSSet setWithArray:value];
	}
	return [NSSet setWithObject:value];
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
		NSPredicate *predicate = [self predicateOf:check model:[[object entity] managedObjectModel]];
		return predicate != nil && [[object entity] isKindOfEntity:[[[[object entity] managedObjectModel] entitiesByName]
		                                                              objectForKey:check.plan.entityName]]
		       && [predicate evaluateWithObject:object];
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
		*error = [violations count] == 1
			? [violations firstObject]
			: [NSError errorWithDomain:NSCocoaErrorDomain
			                      code:NSValidationMultipleErrorsError
			                  userInfo:@{ NSDetailedErrorsKey: violations,
				                          NSLocalizedDescriptionKey: @"Several constraints are violated." }];
	}
	return NO;
}

@end
