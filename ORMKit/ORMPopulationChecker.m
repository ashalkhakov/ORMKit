/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPopulationChecker.h"
#import "ORMPath.h"
#import "ORMPopulationStore.h"
#import "ORMRuleChecker.h"
#import <CoreData/CoreData.h>

@interface ORMPopulationViolation ()
@property (nonatomic, readwrite, strong) ORMConstraint *constraint;
@property (nonatomic, readwrite, strong) ORMQuery *rule;
@property (nonatomic, readwrite, strong) ORMFactType *factType;
@property (nonatomic, readwrite, copy) NSString *text;
@end

@implementation ORMPopulationViolation

- (NSString *)description
{
	return self.text;
}

@end

@implementation ORMPopulationChecker
{
	/* Each fact type's facts: role id to the key of the instance playing
	 * it. */
	NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, NSString *> *> *> *_facts;
	/* An instance's key: an entity instance's root's id, a value's type and
	 * value. */
	NSMutableDictionary<NSString *, NSString *> *_names;
	NSMutableDictionary<NSString *, NSString *> *_values;
	NSMutableArray<ORMPopulationViolation *> *_violations;
	NSMutableArray<NSString *> *_unchecked;
}

- (instancetype)initWithModel:(ORMModel *)model
{
	if ((self = [super init])) {
		_model = model;
	}
	return self;
}

- (NSArray<NSString *> *)unchecked
{
	if (_unchecked == nil) {
		[self violations];
	}
	return _unchecked;
}

#pragma mark The population

static ORMInstance *
ORMRootInstance(ORMInstance *instance)
{
	while ([instance supertypeInstance] != nil) {
		instance = [instance supertypeInstance];
	}
	return instance;
}

- (NSString *)keyOf:(ORMInstance *)instance
{
	if (instance.value != nil) {
		NSString *key = [NSString stringWithFormat:@"%@:%@", instance.objectType.identifier, instance.value];
		[_values setObject:instance.value forKey:key];
		[_names setObject:[instance displayText] forKey:key];
		return key;
	}
	ORMInstance *root = ORMRootInstance(instance);
	if ([_names objectForKey:root.identifier] == nil) {
		[_names setObject:[NSString stringWithFormat:@"%@ %@", root.objectType.name, [root displayText]]
		           forKey:root.identifier];
	}
	return root.identifier;
}

- (NSString *)nameOf:(NSString *)key
{
	return [_names objectForKey:key] ?: key;
}

- (void)gather
{
	_facts = [NSMutableDictionary dictionary];
	_names = [NSMutableDictionary dictionary];
	_values = [NSMutableDictionary dictionary];
	void (^add)(ORMFactType *, NSDictionary *) = ^(ORMFactType *fact, NSDictionary *byRole) {
		NSMutableArray *list = [self->_facts objectForKey:fact.identifier];
		if (list == nil) {
			list = [NSMutableArray array];
			[self->_facts setObject:list forKey:fact.identifier];
		}
		[list addObject:byRole];
	};
	for (ORMFactType *fact in _model.factTypes) {
		for (ORMFactInstance *instance in [fact instances]) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			for (NSString *roleId in instance.instancesByRole) {
				[byRole setObject:[self keyOf:[instance.instancesByRole objectForKey:roleId]] forKey:roleId];
			}
			add(fact, byRole);
			if ([byRole count] < [[fact visibleRoles] count]) {
				[self violate:nil fact:fact text:[NSString stringWithFormat:@"A fact of \"%@\" lacks a role's player.",
				                                                           [self readingOf:fact]]];
			}
		}
	}
	/* An objectified fact and its objectifying instance: each the other's. */
	NSMutableSet *objectified = [NSMutableSet set];
	for (ORMObjectType *type in _model.objectTypes) {
		for (ORMInstance *instance in [type instances]) {
			if ([instance objectifiedInstance] != nil) {
				[objectified addObject:[instance objectifiedInstance].identifier];
			}
		}
	}
	for (ORMFactType *fact in _model.factTypes) {
		if (fact.objectifyingType == nil) {
			continue;
		}
		for (ORMFactInstance *instance in [fact instances]) {
			if (![objectified containsObject:instance.identifier]) {
				[self violate:nil fact:fact
				         text:[NSString stringWithFormat:@"A fact of \"%@\" is no %@.", [self readingOf:fact],
				                                         fact.objectifyingType.name]];
			}
		}
	}
	for (ORMObjectType *type in _model.objectTypes) {
		for (ORMInstance *instance in [type instances]) {
			NSString *key = [self keyOf:instance];
			NSDictionary *identifying = [instance identifyingInstancesByRole];
			for (NSString *roleId in identifying) {
				ORMRole *role = [_model elementWithId:roleId];
				ORMRole *other = [role.factType.roles count] == 2 ? [role oppositeRole] : nil;
				if (other != nil) {
					add(role.factType, @{ roleId: [self keyOf:[identifying objectForKey:roleId]], other.identifier: key });
				}
			}
		}
	}
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)factsOf:(ORMFactType *)fact
{
	return [_facts objectForKey:fact.identifier] ?: @[];
}

/* The keys of the type's instances, its subtypes' among them. */
- (NSArray<NSString *> *)instancesOf:(ORMObjectType *)type
{
	NSMutableOrderedSet *keys = [NSMutableOrderedSet orderedSet];
	for (ORMInstance *instance in [type instances]) {
		[keys addObject:[self keyOf:instance]];
	}
	return [keys array];
}

- (NSString *)readingOf:(ORMFactType *)fact
{
	return [[fact primaryReading] expandedText] ?: fact.name;
}

- (void)violate:(ORMConstraint *)constraint fact:(ORMFactType *)fact text:(NSString *)text
{
	ORMPopulationViolation *violation = [[ORMPopulationViolation alloc] init];
	violation.constraint = constraint;
	violation.factType = fact ?: [[constraint factTypes] firstObject];
	violation.text = text;
	[_violations addObject:violation];
}

/* The keys a fact has at the roles, in their order; nil when it lacks one. */
static NSArray<NSString *> *
ORMProjection(NSDictionary<NSString *, NSString *> *fact, NSArray<ORMRole *> *roles)
{
	NSMutableArray *keys = [NSMutableArray array];
	for (ORMRole *role in roles) {
		NSString *key = [fact objectForKey:role.identifier];
		if (key == nil) {
			return nil;
		}
		[keys addObject:key];
	}
	return keys;
}

- (NSString *)namesOf:(NSArray<NSString *> *)keys
{
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *key in keys) {
		[names addObject:[self nameOf:key]];
	}
	return [names componentsJoinedByString:@", "];
}

/* The one fact type of the roles, or nil. */
static ORMFactType *
ORMOneFactType(NSArray<ORMRole *> *roles)
{
	ORMFactType *fact = [[roles firstObject] factType];
	for (ORMRole *role in roles) {
		if (role.factType != fact) {
			return nil;
		}
	}
	return fact;
}

#pragma mark The constraints

- (NSArray<ORMPopulationViolation *> *)violations
{
	_violations = [NSMutableArray array];
	_unchecked = [NSMutableArray array];
	[self gather];
	for (ORMConstraint *constraint in _model.constraints) {
		/* A subtype's or an objectification's link facts have no facts of
		 * their own: what they say is what the instances are. */
		BOOL structural = constraint.isImplied;
		for (ORMFactType *fact in [constraint factTypes]) {
			structural = structural || fact.kind != ORMFactTypeOrdinary;
		}
		if (structural) {
			continue;
		}
		switch (constraint.kind) {
		case ORMUniquenessConstraint:
			[self checkUniqueness:constraint];
			break;
		case ORMMandatoryConstraint:
			[self checkMandatory:constraint];
			break;
		case ORMFrequencyConstraint:
			[self checkFrequency:constraint];
			break;
		case ORMRingConstraint:
			[self checkRing:constraint];
			break;
		case ORMSubsetConstraint:
		case ORMEqualityConstraint:
		case ORMExclusionConstraint:
			[self checkSetComparison:constraint];
			break;
		case ORMValueComparisonConstraint:
			[_unchecked addObject:[NSString stringWithFormat:@"%@: value comparisons are not checked.", constraint.name]];
			break;
		}
	}
	[self checkValues];
	[self checkRules];
	return _violations;
}

/* The constraint queries, run against the population in a store. */
- (void)checkRules
{
	NSXMLDocument *document = [_model.modelElement rootDocument];
	ORMCoreDataMapping *mapping = document != nil ? [[ORMCoreDataMapping mappingsOfDocument:document] firstObject] : nil;
	ORMRuleChecker *rules = [[ORMRuleChecker alloc] initWithModel:_model mapping:mapping];
	if ([rules.rules count] == 0 && [rules.valueCalculations count] == 0) {
		return;
	}
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:_model coreData:rules.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	NSArray *found = context != nil ? [rules violationsInContext:context limit:100 error:&error] : nil;
	if (found == nil) {
		[_unchecked addObject:[NSString stringWithFormat:@"The constraint queries: %@", error.localizedDescription ?: @"?"]];
		return;
	}
	for (ORMRuleViolation *each in found) {
		ORMPopulationViolation *violation = [[ORMPopulationViolation alloc] init];
		violation.rule = each.rule;
		violation.text = each.text;
		[_violations addObject:violation];
	}
	[_unchecked addObjectsFromArray:rules.unchecked];
}

- (void)checkUniqueness:(ORMConstraint *)constraint
{
	NSArray<ORMRole *> *roles = [constraint allRoles];
	ORMFactType *fact = ORMOneFactType(roles);
	if (fact != nil) {
		NSMutableSet *seen = [NSMutableSet set];
		NSMutableSet *reported = [NSMutableSet set];
		for (NSDictionary *each in [self factsOf:fact]) {
			NSArray *keys = ORMProjection(each, roles);
			if (keys != nil && [seen containsObject:keys] && ![reported containsObject:keys]) {
				[reported addObject:keys];
				[self violate:constraint fact:fact
				         text:[NSString stringWithFormat:@"%@ occurs more than once in \"%@\".", [self namesOf:keys],
				                                         [self readingOf:fact]]];
			}
			if (keys != nil) {
				[seen addObject:keys];
			}
		}
		return;
	}
	/* External: binaries whose other roles one type plays; that type's
	 * instances each have their own combination. */
	ORMObjectType *common = nil;
	for (ORMRole *role in roles) {
		ORMRole *other = [role.factType.roles count] == 2 ? [role oppositeRole] : nil;
		if (other == nil || (common != nil && other.player != common)) {
			[_unchecked addObject:[NSString stringWithFormat:@"%@: its roles join through more than one object "
			                                                 @"type.", constraint.name]];
			return;
		}
		common = other.player;
	}
	NSMutableDictionary<NSString *, NSMutableArray *> *combinations = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		ORMRole *other = [role oppositeRole];
		for (NSDictionary *each in [self factsOf:role.factType]) {
			NSString *about = [each objectForKey:other.identifier];
			NSString *value = [each objectForKey:role.identifier];
			if (about == nil || value == nil) {
				continue;
			}
			NSMutableArray *combination = [combinations objectForKey:about];
			if (combination == nil) {
				combination = [NSMutableArray array];
				for (NSUInteger j = 0; j < [roles count]; j++) {
					[combination addObject:[NSNull null]];
				}
				[combinations setObject:combination forKey:about];
			}
			[combination replaceObjectAtIndex:i withObject:value];
		}
	}
	NSMutableDictionary *seen = [NSMutableDictionary dictionary];
	for (NSString *about in [[combinations allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSArray *combination = [combinations objectForKey:about];
		if ([combination containsObject:[NSNull null]]) {
			continue;
		}
		NSString *before = [seen objectForKey:combination];
		if (before != nil) {
			[self violate:constraint fact:nil
			         text:[NSString stringWithFormat:@"%@ and %@ both have %@.", [self nameOf:before], [self nameOf:about],
			                                         [self namesOf:combination]]];
		} else {
			[seen setObject:about forKey:combination];
		}
	}
}

- (void)checkMandatory:(ORMConstraint *)constraint
{
	NSArray<ORMRole *> *roles = [constraint allRoles];
	ORMObjectType *player = [[roles firstObject] player];
	if (player == nil || ![player isEntity]) {
		return;
	}
	NSMutableSet *playing = [NSMutableSet set];
	for (ORMRole *role in roles) {
		for (NSDictionary *each in [self factsOf:role.factType]) {
			NSString *key = [each objectForKey:role.identifier];
			if (key != nil) {
				[playing addObject:key];
			}
		}
	}
	for (NSString *key in [self instancesOf:player]) {
		if ([playing containsObject:key]) {
			continue;
		}
		NSString *what = [roles count] == 1 ? [NSString stringWithFormat:@"plays no role in \"%@\"",
		                                                                   [self readingOf:[[roles firstObject] factType]]]
		                                    : @"plays none of the roles one of which it must";
		[self violate:constraint fact:nil text:[NSString stringWithFormat:@"%@ %@.", [self nameOf:key], what]];
	}
}

- (void)checkFrequency:(ORMConstraint *)constraint
{
	NSArray<ORMRole *> *roles = [constraint allRoles];
	ORMFactType *fact = ORMOneFactType(roles);
	if (fact == nil) {
		[_unchecked addObject:[NSString stringWithFormat:@"%@: its roles are in more than one fact type.",
		                                                 constraint.name]];
		return;
	}
	NSCountedSet *counts = [[NSCountedSet alloc] init];
	NSMutableArray *order = [NSMutableArray array];
	for (NSDictionary *each in [self factsOf:fact]) {
		NSArray *keys = ORMProjection(each, roles);
		if (keys != nil) {
			if ([counts countForObject:keys] == 0) {
				[order addObject:keys];
			}
			[counts addObject:keys];
		}
	}
	for (NSArray *keys in order) {
		NSUInteger count = [counts countForObject:keys];
		if (count < constraint.minFrequency || (constraint.maxFrequency > 0 && count > constraint.maxFrequency)) {
			[self violate:constraint fact:fact
			         text:[NSString stringWithFormat:@"%@ occurs %lu times in \"%@\".", [self namesOf:keys],
			                                         (unsigned long)count, [self readingOf:fact]]];
		}
	}
}

- (void)checkRing:(ORMConstraint *)constraint
{
	NSArray<ORMRole *> *roles = [constraint allRoles];
	ORMFactType *fact = ORMOneFactType(roles);
	if (fact == nil || [roles count] != 2) {
		[_unchecked addObject:[NSString stringWithFormat:@"%@: a ring over more than one fact type is not checked.",
		                                                 constraint.name]];
		return;
	}
	NSMutableSet<NSArray *> *pairs = [NSMutableSet set];
	NSMutableArray<NSArray *> *ordered = [NSMutableArray array];
	for (NSDictionary *each in [self factsOf:fact]) {
		NSArray *pair = ORMProjection(each, roles);
		if (pair != nil && ![pairs containsObject:pair]) {
			[pairs addObject:pair];
			[ordered addObject:pair];
		}
	}
	ORMRingType type = constraint.ringType;
	NSString *reading = [self readingOf:fact];
	void (^broken)(NSString *, NSArray *) = ^(NSString *what, NSArray *keys) {
		[self violate:constraint fact:fact
		         text:[NSString stringWithFormat:@"%@ in \"%@\": %@.", what, reading, [self namesOf:keys]]];
	};
	NSMutableDictionary<NSString *, NSMutableArray *> *next = [NSMutableDictionary dictionary];
	for (NSArray *pair in ordered) {
		NSString *x = [pair firstObject], *y = [pair lastObject];
		NSMutableArray *list = [next objectForKey:x];
		if (list == nil) {
			list = [NSMutableArray array];
			[next setObject:list forKey:x];
		}
		[list addObject:y];
		BOOL self_ = [x isEqualToString:y];
		BOOL back = [pairs containsObject:@[ y, x ]];
		if ((type & ORMRingIrreflexive) && self_) {
			broken(@"Related to itself", @[ x ]);
		}
		if ((type & ORMRingPurelyReflexive) && !self_) {
			broken(@"Related to another", pair);
		}
		if ((type & ORMRingAsymmetric) && back) {
			broken(@"Related both ways", pair);
		}
		if ((type & ORMRingAntisymmetric) && back && !self_) {
			broken(@"Related both ways", pair);
		}
		if ((type & ORMRingSymmetric) && !back) {
			broken(@"Not related back", pair);
		}
		if ((type & ORMRingReflexive) && ![pairs containsObject:@[ x, x ]]) {
			broken(@"Not related to itself", @[ x ]);
		}
	}
	if (type & (ORMRingTransitive | ORMRingIntransitive | ORMRingStronglyIntransitive)) {
		for (NSArray *pair in ordered) {
			for (NSString *z in [next objectForKey:[pair lastObject]] ?: @[]) {
				BOOL closes = [pairs containsObject:@[ [pair firstObject], z ]];
				if ((type & ORMRingTransitive) && !closes) {
					broken(@"Not transitive", @[ [pair firstObject], [pair lastObject], z ]);
				}
				if ((type & (ORMRingIntransitive | ORMRingStronglyIntransitive)) && closes) {
					broken(@"Transitive", @[ [pair firstObject], [pair lastObject], z ]);
				}
			}
		}
	}
	if (type & ORMRingAcyclic) {
		/* A cycle: a node met again on the path that reached it. */
		NSMutableSet *done = [NSMutableSet set];
		for (NSArray *pair in ordered) {
			NSMutableArray *path = [NSMutableArray array];
			if ([self cycleFrom:[pair firstObject] next:next path:path done:done]) {
				broken(@"A cycle", path);
				return;
			}
		}
	}
}

- (BOOL)cycleFrom:(NSString *)node next:(NSDictionary *)next path:(NSMutableArray *)path done:(NSMutableSet *)done
{
	if ([path containsObject:node]) {
		[path addObject:node];
		return YES;
	}
	if ([done containsObject:node]) {
		return NO;
	}
	[path addObject:node];
	for (NSString *to in [next objectForKey:node] ?: @[]) {
		if ([self cycleFrom:to next:next path:path done:done]) {
			return YES;
		}
	}
	[path removeLastObject];
	[done addObject:node];
	return NO;
}

- (void)checkSetComparison:(ORMConstraint *)constraint
{
	NSMutableArray<NSSet *> *projections = [NSMutableArray array];
	for (ORMRoleSequence *sequence in constraint.roleSequences) {
		ORMFactType *fact = ORMOneFactType(sequence.roles);
		if (fact == nil) {
			[_unchecked addObject:[NSString stringWithFormat:@"%@: a sequence over more than one fact type is not "
			                                                 @"checked.", constraint.name]];
			return;
		}
		NSMutableSet *set = [NSMutableSet set];
		for (NSDictionary *each in [self factsOf:fact]) {
			NSArray *keys = ORMProjection(each, sequence.roles);
			if (keys != nil) {
				[set addObject:keys];
			}
		}
		[projections addObject:set];
	}
	if ([projections count] < 2) {
		return;
	}
	NSString *(^reading)(NSUInteger) = ^NSString *(NSUInteger i) {
		return [self readingOf:[[[[constraint.roleSequences objectAtIndex:i] roles] firstObject] factType]];
	};
	if (constraint.kind == ORMExclusionConstraint) {
		for (NSUInteger i = 0; i < [projections count]; i++) {
			for (NSUInteger j = i + 1; j < [projections count]; j++) {
				NSMutableSet *both = [[projections objectAtIndex:i] mutableCopy];
				[both intersectSet:[projections objectAtIndex:j]];
				for (NSArray *keys in both) {
					[self violate:constraint fact:nil
					         text:[NSString stringWithFormat:@"%@ is in both \"%@\" and \"%@\".", [self namesOf:keys],
					                                         reading(i), reading(j)]];
				}
			}
		}
		return;
	}
	/* Subset: the first in the second; equality: each in each. */
	NSUInteger count = constraint.kind == ORMSubsetConstraint ? 1 : [projections count];
	for (NSUInteger i = 0; i < count; i++) {
		for (NSUInteger j = 0; j < [projections count]; j++) {
			if (i == j || (constraint.kind == ORMSubsetConstraint && j != 1)) {
				continue;
			}
			NSMutableSet *missing = [[projections objectAtIndex:i] mutableCopy];
			[missing minusSet:[projections objectAtIndex:j]];
			for (NSArray *keys in missing) {
				[self violate:constraint fact:nil
				         text:[NSString stringWithFormat:@"%@ is in \"%@\" but not in \"%@\".", [self namesOf:keys],
				                                         reading(i), reading(j)]];
			}
		}
	}
}

#pragma mark Values

/* Whether the value is in one of the ranges: numbers compared as numbers,
 * the rest as text. */
static BOOL
ORMValueAllowed(NSString *value, ORMValueConstraint *constraint, BOOL numeric)
{
	NSString *(^bare)(NSString *) = ^NSString *(NSString *text) {
		if ([text length] >= 2 && [text hasPrefix:@"'"] && [text hasSuffix:@"'"]) {
			return [text substringWithRange:NSMakeRange(1, [text length] - 2)];
		}
		return text;
	};
	NSComparisonResult (^compare)(NSString *, NSString *) = ^NSComparisonResult(NSString *a, NSString *b) {
		if (numeric) {
			double x = [a doubleValue], y = [b doubleValue];
			return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
		}
		return [a compare:b];
	};
	for (ORMValueRange *range in constraint.ranges) {
		NSString *min = bare(range.minValue ?: @""), *max = bare(range.maxValue ?: @"");
		BOOL above = [min length] == 0 || (range.minInclusion == ORMRangeOpen ? compare(value, min) == NSOrderedDescending
		                                                                      : compare(value, min) != NSOrderedAscending);
		BOOL below = [max length] == 0 || (range.maxInclusion == ORMRangeOpen ? compare(value, max) == NSOrderedAscending
		                                                                      : compare(value, max) != NSOrderedDescending);
		if (above && below) {
			return YES;
		}
	}
	return [constraint.ranges count] == 0;
}

- (void)checkValues
{
	for (ORMObjectType *type in _model.objectTypes) {
		ORMValueConstraint *constraint = type.valueConstraint;
		if (constraint == nil || [type isEntity]) {
			continue;
		}
		BOOL numeric = type.dataType.family == ORMDataTypeNumeric;
		for (ORMInstance *instance in [type instances]) {
			if (instance.value != nil && !ORMValueAllowed(instance.value, constraint, numeric)) {
				[self violate:nil fact:nil
				         text:[NSString stringWithFormat:@"%@ is not among %@'s values %@.", [instance displayText],
				                                         type.name, [constraint displayText]]];
			}
		}
	}
	for (ORMFactType *fact in _model.factTypes) {
		for (ORMRole *role in fact.roles) {
			ORMValueConstraint *constraint = role.valueConstraint;
			if (constraint == nil) {
				continue;
			}
			BOOL numeric = constraint.valueType.dataType.family == ORMDataTypeNumeric;
			for (NSDictionary *each in [self factsOf:fact]) {
				NSString *value = [_values objectForKey:[each objectForKey:role.identifier] ?: @""];
				if (value != nil && !ORMValueAllowed(value, constraint, numeric)) {
					[self violate:nil fact:fact
					         text:[NSString stringWithFormat:@"%@ is not among the values %@ of \"%@\".",
					                                         [self nameOf:[each objectForKey:role.identifier]],
					                                         [constraint displayText], [self readingOf:fact]]];
				}
			}
		}
	}
}

@end
