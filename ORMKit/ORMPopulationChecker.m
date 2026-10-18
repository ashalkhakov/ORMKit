/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPopulationChecker.h"
#import "ORMPopulationStore.h"
#import "ORMRuleChecker.h"
#import "ORMDeriver.h"
#import "ORMPath.h"
#import "ORMConstraintQueries.h"
#import "ORMEditorPriv.h"
#import "ORMCoreDataMapper.h"
#import "ORMXML.h"
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
	/* The constraints checked as rules (ORMConstraintQueries): over facts
	 * of more than one fact type, or comparing values. */
	NSMutableArray<ORMConstraint *> *_asRules;
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

/* A fact of the fact type: its players' keys by role. */
- (void)addFact:(NSDictionary *)byRole of:(ORMFactType *)fact
{
	NSMutableArray *list = [_facts objectForKey:fact.identifier];
	if (list == nil) {
		list = [NSMutableArray array];
		[_facts setObject:list forKey:fact.identifier];
	}
	[list addObject:byRole];
}

- (void)gather
{
	_facts = [NSMutableDictionary dictionary];
	_names = [NSMutableDictionary dictionary];
	_values = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in _model.factTypes) {
		for (ORMFactInstance *instance in [fact instances]) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			for (NSString *roleId in instance.instancesByRole) {
				[byRole setObject:[self keyOf:[instance.instancesByRole objectForKey:roleId]] forKey:roleId];
			}
			[self addFact:byRole of:fact];
			if ([byRole count] < [[fact visibleRoles] count]) {
				[self violate:nil fact:fact text:[NSString stringWithFormat:@"A fact of \"%@\" lacks a role's player.",
				                                                           [fact displayText]]];
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
				         text:[NSString stringWithFormat:@"A fact of \"%@\" is no %@.", [fact displayText],
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
				ORMRole *other = [role oppositeRole];
				if (other != nil) {
					[self addFact:@{ roleId: [self keyOf:[identifying objectForKey:roleId]], other.identifier: key }
					           of:role.factType];
				}
			}
		}
	}
}

/* The derived facts (docs/DERIVATION.md): those of a fact type derived
 * and not stored checked as its facts, beside any asserted; asserted ones
 * of a fully derived one, and stored ones the rule no longer derives, said
 * to be wrong. */
- (void)gatherDerived
{
	ORMDeriver *deriver = [[ORMDeriver alloc] initWithModel:_model];
	NSDictionary *derivedFacts = [deriver derivedFacts];
	[_unchecked addObjectsFromArray:[deriver notes]];
	for (NSString *factId in derivedFacts) {
		ORMFactType *fact = [_model elementWithId:factId];
		ORMDerivationRule *rule = [fact derivationRule];
		/* What is asserted, by the roles derived facts have: a unary's
		 * truth left out. */
		NSMutableSet *asserted = [NSMutableSet set];
		for (NSDictionary *byRole in [self factsOf:fact]) {
			NSMutableDictionary *visible = [NSMutableDictionary dictionaryWithDictionary:byRole];
			if ([fact implicitRole] != nil) {
				[visible removeObjectForKey:[fact implicitRole].identifier];
			}
			[asserted addObject:visible];
		}
		NSMutableArray *derived = [NSMutableArray array];
		for (ORMDerivedFact *each in [derivedFacts objectForKey:factId]) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			for (NSString *roleId in each.players) {
				id player = [each.players objectForKey:roleId];
				ORMRole *role = [_model elementWithId:roleId];
				NSString *key = player;
				if ([player isKindOfClass:[ORMInstance class]]) {
					key = [self keyOf:player];
				} else {
					key = [NSString stringWithFormat:@"%@:%@", role.player.identifier, player];
					[_values setObject:player forKey:key];
					[_names setObject:player forKey:key];
				}
				[byRole setObject:key forKey:roleId];
			}
			[derived addObject:byRole];
		}
		NSString *reading = [fact displayText];
		if (rule.isStored) {
			/* Kept: what is stored is what the rule says, the asserted ones
			 * of a partly derived one besides. */
			NSUInteger missing = 0;
			for (NSDictionary *byRole in derived) {
				missing += [asserted containsObject:byRole] ? 0 : 1;
			}
			NSUInteger extra = 0;
			for (NSDictionary *byRole in asserted) {
				extra += rule.isPartial || [derived containsObject:byRole] ? 0 : 1;
			}
			if (missing > 0 || extra > 0) {
				[self violate:nil fact:fact text:[NSString stringWithFormat:@"\"%@\" is stored out of date: %lu facts its rule "
				                                                           @"derives are missing, %lu are not derived.",
				                                                           reading, (unsigned long)missing,
				                                                           (unsigned long)extra]];
			}
			continue;
		}
		if (!rule.isPartial && [asserted count] > 0) {
			[self violate:nil fact:fact text:[NSString stringWithFormat:@"\"%@\" is derived: its facts are not asserted.",
			                                                           reading]];
		}
		NSMutableArray *list = [_facts objectForKey:factId];
		if (list == nil) {
			list = [NSMutableArray array];
			[_facts setObject:list forKey:factId];
		}
		for (NSDictionary *byRole in derived) {
			if (![asserted containsObject:byRole]) {
				[list addObject:byRole];
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
	_asRules = [NSMutableArray array];
	[self gather];
	[self gatherDerived];
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
			[_asRules addObject:constraint];
			break;
		}
	}
	[self checkValues];
	[self checkRules];
	return _violations;
}

/* Each constraint checked as rules, its queries made: the constraint of
 * each query, by its id. */
- (void)makeRulesWith:(ORMConstraintQueries *)builder in:(ORMEditor *)scratch
         constraintOf:(NSMutableDictionary<NSString *, ORMConstraint *> *)constraintOf
{
	for (ORMConstraint *constraint in _asRules) {
		NSString *why = nil;
		NSArray *made = [builder queriesFor:[scratch.model elementWithId:constraint.identifier] reason:&why];
		if (made == nil) {
			[_unchecked addObject:[NSString stringWithFormat:@"%@: %@.", constraint.name, why]];
		}
		for (NSString *identifier in made) {
			[constraintOf setObject:constraint forKey:identifier];
		}
	}
}

/* The constraint queries, run against the population in a store. */
- (void)checkRules
{
	/* The constraints said as rules, beside the model's own: in a copy of
	 * the document, as they are not the model's. */
	ORMModel *model = _model;
	NSMutableDictionary<NSString *, ORMConstraint *> *constraintOf = [NSMutableDictionary dictionary];
	if ([_asRules count] > 0) {
		ORMEditor *scratch = [[ORMEditor alloc] initWithDocument:ORMCopyDocument(_model.document) undoManager:nil];
		ORMConstraintQueries *builder = [[ORMConstraintQueries alloc] initWithEditor:scratch];
		/* Read from what has an entity of its own in the store. */
		NSMutableSet *readable = [NSMutableSet set];
		ORMCDModel *coreData = [[[ORMCoreDataMapper alloc] initWithModel:_model
		                                                          mapping:[_model.coreDataMappings firstObject]] map];
		for (ORMCDEntity *entity in coreData.entities) {
			if (entity.source != nil) {
				[readable addObject:entity.source];
			}
		}
		builder.readable = readable;
		/* All of them one change, not one for each edit. */
		[scratch modelChange:@"Constraint Queries" with:^{
			[self makeRulesWith:builder in:scratch constraintOf:constraintOf];
		}];
		model = scratch.model;
	}
	ORMCoreDataMapping *mapping = [model.coreDataMappings firstObject];
	ORMRuleChecker *rules = [[ORMRuleChecker alloc] initWithModel:model mapping:mapping];
	if ([rules.rules count] == 0 && [rules.valueCalculations count] == 0) {
		return;
	}
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:rules.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	NSArray *found = context != nil ? [rules violationsInContext:context limit:100 error:&error] : nil;
	if (found == nil) {
		[_unchecked addObject:[NSString stringWithFormat:@"The constraint queries: %@", error.localizedDescription ?: @"?"]];
		return;
	}
	for (ORMRuleViolation *each in found) {
		ORMPopulationViolation *violation = [[ORMPopulationViolation alloc] init];
		ORMConstraint *constraint = [constraintOf objectForKey:each.rule.identifier];
		/* A constraint's as the constraint's, the model's own. */
		violation.constraint = constraint;
		violation.rule = constraint == nil ? [ORMQuery queryWithId:each.rule.identifier inModel:_model] ?: each.rule : nil;
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
				                                         [fact displayText]]];
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
		ORMRole *other = [role oppositeRole];
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
		                                                                   [[[roles firstObject] factType] displayText]]
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
			                                         (unsigned long)count, [fact displayText]]];
		}
	}
}

/* A ring constraint broken by the players with the keys. */
- (void)ring:(ORMConstraint *)constraint of:(ORMFactType *)fact broken:(NSString *)what by:(NSArray *)keys
{
	[self violate:constraint fact:fact
	         text:[NSString stringWithFormat:@"%@ in \"%@\": %@.", what, [fact displayText], [self namesOf:keys]]];
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
			[self ring:constraint of:fact broken:@"Related to itself" by:@[ x ]];
		}
		if ((type & ORMRingPurelyReflexive) && !self_) {
			[self ring:constraint of:fact broken:@"Related to another" by:pair];
		}
		if ((type & ORMRingAsymmetric) && back) {
			[self ring:constraint of:fact broken:@"Related both ways" by:pair];
		}
		if ((type & ORMRingAntisymmetric) && back && !self_) {
			[self ring:constraint of:fact broken:@"Related both ways" by:pair];
		}
		if ((type & ORMRingSymmetric) && !back) {
			[self ring:constraint of:fact broken:@"Not related back" by:pair];
		}
		if ((type & ORMRingReflexive) && ![pairs containsObject:@[ x, x ]]) {
			[self ring:constraint of:fact broken:@"Not related to itself" by:@[ x ]];
		}
	}
	if (type & (ORMRingTransitive | ORMRingIntransitive | ORMRingStronglyIntransitive)) {
		for (NSArray *pair in ordered) {
			for (NSString *z in [next objectForKey:[pair lastObject]] ?: @[]) {
				BOOL closes = [pairs containsObject:@[ [pair firstObject], z ]];
				if ((type & ORMRingTransitive) && !closes) {
					[self ring:constraint of:fact broken:@"Not transitive" by:@[ [pair firstObject], [pair lastObject], z ]];
				}
				if ((type & ORMRingIntransitive) && closes) {
					[self ring:constraint of:fact broken:@"Transitive" by:@[ [pair firstObject], [pair lastObject], z ]];
				}
			}
		}
	}
	if (type & ORMRingStronglyIntransitive) {
		/* x related to y, and y reached from x by a longer chain too: from
		 * each other thing x is related to. */
		for (NSArray *pair in ordered) {
			NSString *x = [pair firstObject];
			NSString *y = [pair lastObject];
			NSMutableSet *reached = [NSMutableSet set];
			NSMutableArray *queue = [NSMutableArray array];
			for (NSString *z in [next objectForKey:x] ?: @[]) {
				if (![z isEqualToString:y]) {
					[queue addObject:z];
				}
			}
			while ([queue count] > 0 && ![reached containsObject:y]) {
				NSString *at = [queue lastObject];
				[queue removeLastObject];
				for (NSString *after in [next objectForKey:at] ?: @[]) {
					if (![reached containsObject:after]) {
						[reached addObject:after];
						[queue addObject:after];
					}
				}
			}
			if ([reached containsObject:y]) {
				[self ring:constraint of:fact broken:@"Reached by a longer chain too" by:pair];
			}
		}
	}
	if (type & ORMRingAcyclic) {
		/* A cycle: a node met again on the path that reached it. */
		NSMutableSet *done = [NSMutableSet set];
		for (NSArray *pair in ordered) {
			NSMutableArray *path = [NSMutableArray array];
			if ([self cycleFrom:[pair firstObject] next:next path:path done:done]) {
				[self ring:constraint of:fact broken:@"A cycle" by:path];
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

/* The fact type a set comparison constraint's sequence is over. */
static NSString *
ORMSequenceReading(ORMConstraint *constraint, NSUInteger i)
{
	return [[[[[constraint.roleSequences objectAtIndex:i] roles] firstObject] factType] displayText];
}

- (void)checkSetComparison:(ORMConstraint *)constraint
{
	NSMutableArray<NSSet *> *projections = [NSMutableArray array];
	for (ORMRoleSequence *sequence in constraint.roleSequences) {
		ORMFactType *fact = ORMOneFactType(sequence.roles);
		if (fact == nil) {
			[_asRules addObject:constraint];
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
	if (constraint.kind == ORMExclusionConstraint) {
		for (NSUInteger i = 0; i < [projections count]; i++) {
			for (NSUInteger j = i + 1; j < [projections count]; j++) {
				NSMutableSet *both = [[projections objectAtIndex:i] mutableCopy];
				[both intersectSet:[projections objectAtIndex:j]];
				for (NSArray *keys in both) {
					[self violate:constraint fact:nil
					         text:[NSString stringWithFormat:@"%@ is in both \"%@\" and \"%@\".", [self namesOf:keys],
					                                         ORMSequenceReading(constraint, i), ORMSequenceReading(constraint, j)]];
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
				                                         ORMSequenceReading(constraint, i), ORMSequenceReading(constraint, j)]];
			}
		}
	}
}

#pragma mark Values

/* Whether the value is in one of the ranges: numbers compared as numbers,
 * the rest as text. */
/* A range's bound without its quotes. */
static NSString *
ORMUnquoted(NSString *text)
{
	if ([text length] >= 2 && [text hasPrefix:@"'"] && [text hasSuffix:@"'"]) {
		return [text substringWithRange:NSMakeRange(1, [text length] - 2)];
	}
	return text;
}

/* Two values compared as numbers, or else as text. */
static NSComparisonResult
ORMCompareValues(NSString *a, NSString *b, BOOL numeric)
{
	if (numeric) {
		double x = [a doubleValue], y = [b doubleValue];
		return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
	}
	return [a compare:b];
}

static BOOL
ORMValueAllowed(NSString *value, ORMValueConstraint *constraint, BOOL numeric)
{
	for (ORMValueRange *range in constraint.ranges) {
		NSString *min = ORMUnquoted(range.minValue ?: @""), *max = ORMUnquoted(range.maxValue ?: @"");
		NSComparisonResult low = ORMCompareValues(value, min, numeric);
		NSComparisonResult high = ORMCompareValues(value, max, numeric);
		BOOL above = [min length] == 0 || (range.minInclusion == ORMRangeOpen ? low == NSOrderedDescending
		                                                                      : low != NSOrderedAscending);
		BOOL below = [max length] == 0 || (range.maxInclusion == ORMRangeOpen ? high == NSOrderedAscending
		                                                                      : high != NSOrderedDescending);
		if (above && below) {
			return YES;
		}
	}
	return [constraint.ranges count] == 0;
}

- (void)checkValues
{
	for (ORMObjectType *type in _model.objectTypes) {
		if (type.kind != ORMValueType || [type.valuePattern length] == 0) {
			continue;
		}
		NSRegularExpression *pattern = [NSRegularExpression
			regularExpressionWithPattern:[NSString stringWithFormat:@"^(?:%@)$", type.valuePattern] options:0 error:NULL];
		for (ORMInstance *instance in [type instances]) {
			NSString *value = instance.value;
			if (value != nil && [pattern numberOfMatchesInString:value options:0 range:NSMakeRange(0, [value length])] == 0) {
				[self violate:nil fact:nil
				         text:[NSString stringWithFormat:@"%@ does not match %@'s pattern '%@'.", [instance displayText],
				                                         type.name, type.valuePattern]];
			}
		}
	}
	for (ORMObjectType *type in _model.objectTypes) {
		ORMValueConstraint *constraint = type.valueConstraint;
		if (constraint == nil || [type isEntity]) {
			continue;
		}
		BOOL numeric = [type.dataType isNumeric];
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
			BOOL numeric = [constraint.valueType.dataType isNumeric];
			for (NSDictionary *each in [self factsOf:fact]) {
				NSString *value = [_values objectForKey:[each objectForKey:role.identifier] ?: @""];
				if (value != nil && !ORMValueAllowed(value, constraint, numeric)) {
					[self violate:nil fact:fact
					         text:[NSString stringWithFormat:@"%@ is not among the values %@ of \"%@\".",
					                                         [self nameOf:[each objectForKey:role.identifier]],
					                                         [constraint displayText], [fact displayText]]];
				}
			}
		}
	}
}

@end
