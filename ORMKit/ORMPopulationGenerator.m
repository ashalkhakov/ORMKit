/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPopulationGenerator.h"
#import "ORMPath.h"
#import "ORMXML.h"

@implementation ORMPopulationGenerator
{
	ORMSamplePopulation *_population;
	NSMutableArray<NSString *> *_notes;
	/* Each object type's instances, by type id: entity and subtype
	 * instances' ids. */
	NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *_pools;
	/* A subtype instance's supertype instance's, down to the root. */
	NSMutableDictionary<NSString *, NSString *> *_roots;
	/* Each fact type's facts so far: role id to instance id. */
	NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, NSString *> *> *> *_facts;
	/* What each uniqueness constraint has seen. */
	NSMutableDictionary<NSString *, NSMutableSet *> *_seen;
	NSMutableDictionary<NSString *, NSCountedSet *> *_frequencies;
	/* An objectified fact type's facts' ids, in their order. */
	NSMutableDictionary<NSString *, NSArray<NSString *> *> *_factIds;
	/* The facts identifying instances are, by fact type id: what a subset
	 * of one compares with ("CEO runs Company" only where the CEO works
	 * for it, an Employee identified by Company and number). */
	NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, NSString *> *> *> *_identifying;
}

- (instancetype)initWithModel:(ORMModel *)model
{
	if ((self = [super init])) {
		_model = model;
		_size = 5;
	}
	return self;
}

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
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
ORMReadingOf(ORMFactType *fact)
{
	return [[fact primaryReading] expandedText] ?: fact.name;
}

#pragma mark Values

/* The values a constraint lists, or its ranges' first ones, numbers
 * counted up within a range. */
- (NSString *)value:(NSUInteger)index allowedBy:(ORMValueConstraint *)constraint numeric:(BOOL)numeric
{
	NSMutableArray *values = [NSMutableArray array];
	for (ORMValueRange *range in constraint.ranges) {
		NSString *min = range.minValue ?: @"", *max = range.maxValue ?: @"";
		if ([min hasPrefix:@"'"] && [min hasSuffix:@"'"] && [min length] >= 2) {
			min = [min substringWithRange:NSMakeRange(1, [min length] - 2)];
		}
		if ([min isEqualToString:max] || [max length] == 0 || !numeric) {
			[values addObject:min];
			continue;
		}
		/* A numeric range: as many of its whole numbers as are wanted. */
		long long low = [min longLongValue] + (range.minInclusion == ORMRangeOpen ? 1 : 0);
		long long high = [max longLongValue] - (range.maxInclusion == ORMRangeOpen ? 1 : 0);
		for (long long n = low; n <= high && [values count] < 1000; n++) {
			[values addObject:[NSString stringWithFormat:@"%lld", n]];
		}
	}
	return [values count] > 0 ? [values objectAtIndex:index % [values count]] : nil;
}

/* How many values a constraint allows, as -value:allowedBy: counts them;
 * NSUIntegerMax for none. */
- (NSUInteger)capacityOf:(ORMValueConstraint *)constraint numeric:(BOOL)numeric
{
	if (constraint == nil) {
		return NSUIntegerMax;
	}
	NSMutableSet *values = [NSMutableSet set];
	for (NSUInteger i = 0; i < 1000; i++) {
		NSString *value = [self value:i allowedBy:constraint numeric:numeric];
		if (value == nil || [values containsObject:value]) {
			break;
		}
		[values addObject:value];
	}
	return [values count];
}

/* The index'th value of the type, the role's constraint first. */
- (NSString *)valueOf:(ORMObjectType *)type index:(NSUInteger)index role:(ORMRole *)role
{
	ORMDataType *dataType = type.dataType;
	BOOL numeric = dataType.family == ORMDataTypeNumeric;
	ORMValueConstraint *constraint = role.valueConstraint ?: type.valueConstraint;
	NSString *allowed = constraint != nil ? [self value:index allowedBy:constraint numeric:numeric] : nil;
	if (allowed != nil) {
		return allowed;
	}
	NSString *typeName = dataType.typeName ?: @"";
	if ([typeName rangeOfString:@"ObjectId"].location != NSNotFound
	    || [typeName rangeOfString:@"UniqueIdentifier"].location != NSNotFound) {
		/* An identifier Core Data keeps as a UUID. */
		return [NSString stringWithFormat:@"00000000-0000-4000-8000-%012lu", (unsigned long)index + 1];
	}
	switch (dataType.family) {
	case ORMDataTypeNumeric:
		return [NSString stringWithFormat:@"%lu", (unsigned long)index + 1];
	case ORMDataTypeTemporal: {
		NSUInteger day = index % 28 + 1, month = index / 28 % 12 + 1;
		if ([typeName rangeOfString:@"Date"].location == NSNotFound
		    && [typeName rangeOfString:@"Time"].location != NSNotFound) {
			return [NSString stringWithFormat:@"%02lu:00:00", (unsigned long)(index % 24)];
		}
		if ([typeName rangeOfString:@"Time"].location != NSNotFound
		    || [typeName rangeOfString:@"Timestamp"].location != NSNotFound) {
			return [NSString stringWithFormat:@"2026-%02lu-%02lu 09:00:00", (unsigned long)month, (unsigned long)day];
		}
		return [NSString stringWithFormat:@"2026-%02lu-%02lu", (unsigned long)month, (unsigned long)day];
	}
	case ORMDataTypeLogical:
		return index % 2 == 0 ? @"true" : @"false";
	default: {
		NSString *text = [NSString stringWithFormat:@"%@ %lu", type.name, (unsigned long)index + 1];
		NSInteger length = type.dataTypeLength;
		if (length > 0 && (NSInteger)[text length] > length) {
			/* Too long: the number alone, in as few digits as base 36 needs. */
			NSString *digits = @"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
			NSMutableString *short_ = [NSMutableString string];
			NSUInteger n = index + 1;
			do {
				[short_ insertString:[digits substringWithRange:NSMakeRange(n % 36, 1)] atIndex:0];
				n /= 36;
			} while (n > 0);
			text = [short_ length] <= (NSUInteger)length ? short_ : [short_ substringToIndex:(NSUInteger)length];
		}
		return text;
	}
	}
}

- (NSString *)valueToken:(ORMObjectType *)type index:(NSUInteger)index role:(ORMRole *)role
{
	return [_population value:[self valueOf:type index:index role:role] of:type.identifier];
}

#pragma mark Instances

/* The types an entity type's identifier is made of, its own first. */
- (NSArray<ORMObjectType *> *)identifyingTypesOf:(ORMObjectType *)type
{
	NSMutableArray *types = [NSMutableArray array];
	for (ORMRole *role in [type.preferredIdentifier allRoles]) {
		[types addObject:role.player];
	}
	return types;
}

/* Whether the type's instances are made here: an entity type identified by
 * its own preferred identifier, not a subtype's or an objectification's. */
- (BOOL)isIdentifiedRoot:(ORMObjectType *)type
{
	if (![type isEntity] || type.isImplicitBooleanValue) {
		return NO;
	}
	if (type.nestedFactType != nil) {
		return NO;
	}
	for (ORMFactType *fact in type.supertypeFacts) {
		if (fact.providesPreferredIdentifier) {
			return NO;
		}
	}
	return type.preferredIdentifier != nil;
}

/* How many instances the type needs at least: one for each instance of
 * another type that must play a role with it (each Company run by a CEO),
 * and enough for each subtype's share to have what it needs. */
- (NSUInteger)demandOf:(ORMObjectType *)type depth:(NSUInteger)depth
{
	NSUInteger demand = 0;
	for (ORMRole *own in type.playedRoles) {
		ORMRole *other = [own oppositeRole];
		if (other != nil && own.factType.kind == ORMFactTypeOrdinary && other.player != type && [other.player isEntity]
		    && [self mandatory:other]) {
			demand = MAX(demand, _size);
		}
	}
	/* Roles it plays one of at most (each Content the text of a Comment or
	 * of a Paragraph, not both), each with others that must play them with
	 * it: an instance for each of those, of each. An objectifying one has
	 * as many as its fact has facts, half as many again as others. */
	for (ORMConstraint *constraint in _model.constraints) {
		if (constraint.kind != ORMExclusionConstraint || [constraint.roleSequences count] < 2) {
			continue;
		}
		NSUInteger sum = 0;
		BOOL ours = YES;
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			ORMRole *role = [sequence.roles count] == 1 ? [sequence.roles firstObject] : nil;
			ORMRole *other = [role oppositeRole];
			ours = ours && role.player == type;
			if (other != nil && [other.player isEntity] && [self mandatory:other]) {
				sum += other.player.nestedFactType != nil ? _size * 3 / 2 : _size;
			}
		}
		if (ours) {
			demand = MAX(demand, sum);
		}
	}
	NSUInteger stride = [type.subtypes count] + 1;
	for (ORMObjectType *subtype in depth < 8 ? type.subtypes : @[]) {
		if ([subtype identifyingSupertype] == type && ![self isIdentifiedRoot:subtype]) {
			demand = MAX(demand, [self demandOf:subtype depth:depth + 1] * stride);
		}
	}
	return demand;
}

- (void)makeInstancesOf:(ORMObjectType *)type
{
	NSArray<ORMRole *> *roles = [type.preferredIdentifier allRoles];
	NSMutableArray *pool = [NSMutableArray array];
	/* How many identities there are: values run out where constrained.
	 * As many as its subtypes' shares need. */
	NSUInteger count = MAX(_size, [self demandOf:type depth:0]);
	NSUInteger combinations = 1;
	BOOL unbounded = NO;
	for (ORMRole *role in roles) {
		ORMObjectType *part = role.player;
		NSUInteger capacity;
		if ([part isEntity]) {
			capacity = [[_pools objectForKey:part.identifier] count];
		} else {
			capacity = [self capacityOf:role.valueConstraint ?: part.valueConstraint
			                    numeric:part.dataType.family == ORMDataTypeNumeric];
		}
		if (capacity == 0) {
			[self note:@"%@ has no instances: what identifies it has none.", type.name];
			[_pools setObject:pool forKey:type.identifier];
			return;
		}
		if (capacity == NSUIntegerMax) {
			unbounded = YES;
		} else {
			combinations = combinations * capacity > 10000 ? 10000 : combinations * capacity;
		}
	}
	if (!unbounded) {
		count = MIN(count, combinations);
	}
	for (NSUInteger k = 0; k < count; k++) {
		NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
		/* An unbounded part counts up and keeps identities apart; the others
		 * go round, as digits of k when none is unbounded. */
		NSUInteger radix = 1;
		for (ORMRole *role in roles) {
			ORMObjectType *part = role.player;
			NSArray *parts = [part isEntity] ? [_pools objectForKey:part.identifier] : nil;
			NSUInteger capacity = parts != nil ? [parts count]
			                                   : [self capacityOf:role.valueConstraint ?: part.valueConstraint
			                                              numeric:part.dataType.family == ORMDataTypeNumeric];
			NSUInteger index = unbounded ? k : (k / radix);
			if (!unbounded) {
				radix *= capacity;
			}
			if (parts != nil) {
				[byRole setObject:[parts objectAtIndex:index % [parts count]] forKey:role.identifier];
			} else {
				[byRole setObject:[self valueToken:part index:capacity == NSUIntegerMax ? k : index % capacity role:role]
				           forKey:role.identifier];
			}
		}
		NSString *instance = [_population instanceOf:type.identifier identifiedBy:byRole];
		[pool addObject:instance];
		/* Each identifying binary's fact. */
		for (ORMRole *role in roles) {
			ORMRole *own = [role oppositeRole];
			if (own.player != type || [byRole objectForKey:role.identifier] == nil) {
				continue;
			}
			NSMutableArray *facts = [_identifying objectForKey:role.factType.identifier];
			if (facts == nil) {
				facts = [NSMutableArray array];
				[_identifying setObject:facts forKey:role.factType.identifier];
			}
			[facts addObject:@{ own.identifier: instance, role.identifier: [byRole objectForKey:role.identifier] }];
		}
	}
	[_pools setObject:pool forKey:type.identifier];
}

/* The entity types with identifiers, each after the types it is identified
 * by; then the subtypes, each a share of its supertype's instances. */
- (void)makeInstances
{
	NSMutableArray<ORMObjectType *> *pending = [NSMutableArray array];
	for (ORMObjectType *type in _model.objectTypes) {
		if ([self isIdentifiedRoot:type]) {
			[pending addObject:type];
		} else if ([type isEntity] && type.preferredIdentifier == nil && [type.supertypeFacts count] == 0) {
			[self note:@"%@ has no preferred identifier: its instances are not made up.", type.name];
		}
	}
	BOOL progress = YES;
	while ([pending count] > 0 && progress) {
		progress = NO;
		for (ORMObjectType *type in [pending copy]) {
			BOOL ready = YES;
			for (ORMObjectType *part in [self identifyingTypesOf:type]) {
				ready = ready && (![part isEntity] || [_pools objectForKey:part.identifier] != nil);
			}
			if (ready) {
				[self makeInstancesOf:type];
				[pending removeObject:type];
				progress = YES;
			}
		}
		/* A subtype identified through its supertype is ready when the
		 * supertype is. */
		[self makeSubtypes];
	}
	for (ORMObjectType *type in pending) {
		[self note:@"%@ is identified by what cannot be made first: its instances are not made up.", type.name];
	}
}

- (void)makeSubtypes
{
	BOOL progress = YES;
	while (progress) {
		progress = NO;
		for (ORMObjectType *type in _model.objectTypes) {
			/* One with an identifier of its own is made with the others. */
			if ([_pools objectForKey:type.identifier] != nil || ![type isEntity] || [type.supertypes count] == 0
			    || [self isIdentifiedRoot:type]) {
				continue;
			}
			ORMObjectType *supertype = [type identifyingSupertype];
			NSArray *supers = [_pools objectForKey:supertype.identifier];
			if (supers == nil) {
				continue;
			}
			/* Sibling subtypes take shares apart: the i-th of n every
			 * (n + 1)-th instance from i, the rest none's. */
			NSArray *siblings = supertype.subtypes;
			NSUInteger position = [siblings indexOfObject:type];
			NSUInteger stride = [siblings count] + 1;
			NSMutableArray *pool = [NSMutableArray array];
			for (NSUInteger k = 0; k < [supers count]; k++) {
				if (k % stride == position) {
					NSString *supertypeInstance = [supers objectAtIndex:k];
					NSString *instance = [_population instanceOf:type.identifier supertypeInstance:supertypeInstance];
					[_roots setObject:[_roots objectForKey:supertypeInstance] ?: supertypeInstance forKey:instance];
					[pool addObject:instance];
				}
			}
			[_pools setObject:pool forKey:type.identifier];
			progress = YES;
		}
	}
}

- (NSString *)rootOf:(NSString *)instance
{
	return [_roots objectForKey:instance] ?: instance;
}

#pragma mark Facts

/* The fact types to fill: ordinary, asserted, not identifying anything
 * (those facts are the instances' identities). */
- (BOOL)isFilled:(ORMFactType *)fact
{
	if (fact.kind != ORMFactTypeOrdinary || fact.isDerived) {
		return NO;
	}
	/* An objectified fact type's spanning uniqueness identifies the type
	 * objectifying it: its facts are made, and that type's instances of
	 * them. */
	for (ORMRole *role in fact.roles) {
		for (ORMConstraint *constraint in role.constraints) {
			if (constraint.kind == ORMUniquenessConstraint && constraint.preferredIdentifierFor != nil
			    && constraint.preferredIdentifierFor != fact.objectifyingType) {
				return NO;
			}
		}
	}
	return YES;
}

/* Each set comparison's sequences, each in one fact type: what a fact type
 * must be in, or stay out of. */
- (NSArray<ORMConstraint *> *)setComparisonsOn:(ORMFactType *)fact
{
	NSMutableArray *constraints = [NSMutableArray array];
	for (ORMConstraint *constraint in _model.constraints) {
		if (constraint.kind != ORMSubsetConstraint && constraint.kind != ORMEqualityConstraint
		    && constraint.kind != ORMExclusionConstraint) {
			continue;
		}
		if ([[constraint factTypes] containsObject:fact]) {
			[constraints addObject:constraint];
		}
	}
	return constraints;
}

static ORMFactType *
ORMSequenceFact(ORMRoleSequence *sequence)
{
	ORMFactType *fact = [[sequence.roles firstObject] factType];
	for (ORMRole *role in sequence.roles) {
		if (role.factType != fact) {
			return nil;
		}
	}
	return fact;
}

/* The fact types, each after those it must be a subset of. */
- (NSArray<ORMFactType *> *)factOrder
{
	NSMutableArray<ORMFactType *> *facts = [NSMutableArray array];
	for (ORMFactType *fact in _model.factTypes) {
		if ([self isFilled:fact]) {
			[facts addObject:fact];
		}
	}
	NSMutableArray *ordered = [NSMutableArray array];
	NSMutableSet *placed = [NSMutableSet set];
	BOOL progress = YES;
	while ([ordered count] < [facts count] && progress) {
		progress = NO;
		for (ORMFactType *fact in facts) {
			if ([placed containsObject:fact.identifier]) {
				continue;
			}
			BOOL ready = YES;
			for (ORMConstraint *constraint in [self setComparisonsOn:fact]) {
				if (constraint.kind == ORMExclusionConstraint || [constraint.roleSequences count] < 2) {
					continue;
				}
				ORMFactType *superset = ORMSequenceFact([constraint.roleSequences objectAtIndex:1]);
				BOOL subset = ORMSequenceFact([constraint.roleSequences firstObject]) == fact;
				if (subset && superset != nil && superset != fact && [facts containsObject:superset]
				    && ![placed containsObject:superset.identifier]) {
					ready = NO;
				}
			}
			/* After the fact types objectified by its players. */
			for (ORMRole *role in fact.roles) {
				for (ORMObjectType *type = role.player; type != nil; type = [type.supertypes firstObject]) {
					ORMFactType *nested = type.nestedFactType;
					if (nested != nil && nested != fact && [facts containsObject:nested]
					    && ![placed containsObject:nested.identifier]) {
						ready = NO;
					}
				}
			}
			if (ready) {
				[ordered addObject:fact];
				[placed addObject:fact.identifier];
				progress = YES;
			}
		}
	}
	for (ORMFactType *fact in facts) {
		if (![placed containsObject:fact.identifier]) {
			[ordered addObject:fact];
		}
	}
	return ordered;
}

/* The keys a fact has at the roles, roots for subtype instances. */
- (NSArray *)projectionOf:(NSDictionary<NSString *, NSString *> *)fact roles:(NSArray<ORMRole *> *)roles
{
	NSMutableArray *keys = [NSMutableArray array];
	for (ORMRole *role in roles) {
		NSString *key = [fact objectForKey:role.identifier];
		if (key == nil) {
			return nil;
		}
		[keys addObject:[self rootOf:key]];
	}
	return keys;
}

- (NSArray<NSDictionary *> *)factsOf:(ORMFactType *)fact
{
	return [_facts objectForKey:fact.identifier] ?: [_identifying objectForKey:fact.identifier] ?: @[];
}

/* Whether the fact keeps every constraint on its fact type, with the facts
 * made so far. */
- (BOOL)accepts:(NSDictionary<NSString *, NSString *> *)candidate of:(ORMFactType *)fact
{
	for (ORMConstraint *constraint in [fact uniquenessConstraints]) {
		NSArray *keys = [self projectionOf:candidate roles:[constraint allRoles]];
		if (keys != nil && [[_seen objectForKey:constraint.identifier] containsObject:keys]) {
			return NO;
		}
	}
	NSArray *roles = fact.roles;
	for (ORMRole *role in roles) {
		for (ORMConstraint *constraint in role.constraints) {
			if (constraint.kind == ORMFrequencyConstraint && constraint.maxFrequency > 0
			    && [[constraint factTypes] count] == 1) {
				NSArray *keys = [self projectionOf:candidate roles:[constraint allRoles]];
				if (keys != nil && [[_frequencies objectForKey:constraint.identifier] countForObject:keys]
				                       >= constraint.maxFrequency) {
					return NO;
				}
			}
			if (constraint.kind == ORMRingConstraint && [[constraint allRoles] count] == 2
			    && [[constraint factTypes] count] == 1 && role == [[constraint allRoles] firstObject]) {
				if (![self ring:constraint accepts:candidate]) {
					return NO;
				}
			}
		}
	}
	for (ORMConstraint *constraint in [self setComparisonsOn:fact]) {
		if (![self setComparison:constraint accepts:candidate of:fact]) {
			return NO;
		}
	}
	for (ORMRole *role in roles) {
		for (ORMConstraint *constraint in role.constraints) {
			if (constraint.kind == ORMUniquenessConstraint && !constraint.isInternal
			    && constraint.preferredIdentifierFor == nil && ![self external:constraint accepts:candidate role:role]) {
				return NO;
			}
		}
	}
	return YES;
}

/* The values an instance has at an external uniqueness constraint's roles
 * (binaries about it), the candidate's in its role's place. */
- (NSArray *)combinationOf:(NSString *)about at:(NSArray<ORMRole *> *)roles with:(NSDictionary *)candidate
                      role:(ORMRole *)changed
{
	NSMutableArray *combination = [NSMutableArray array];
	for (ORMRole *role in roles) {
		NSString *value = nil;
		if (role == changed) {
			value = [candidate objectForKey:role.identifier];
		} else {
			for (NSDictionary *fact in [self factsOf:role.factType]) {
				if ([[self rootOf:[fact objectForKey:[[role oppositeRole] identifier]] ?: @""] isEqualToString:about]) {
					value = [fact objectForKey:role.identifier];
				}
			}
		}
		if (value == nil) {
			return nil;
		}
		[combination addObject:[self rootOf:value]];
	}
	return combination;
}

- (BOOL)external:(ORMConstraint *)constraint accepts:(NSDictionary *)candidate role:(ORMRole *)role
{
	NSArray<ORMRole *> *roles = [constraint allRoles];
	for (ORMRole *each in roles) {
		if ([each.factType.roles count] != 2) {
			return YES;
		}
	}
	NSString *about = [self rootOf:[candidate objectForKey:[[role oppositeRole] identifier]] ?: @""];
	NSArray *mine = [self combinationOf:about at:roles with:candidate role:role];
	if (mine == nil) {
		return YES;
	}
	for (NSDictionary *fact in [self factsOf:role.factType]) {
		NSString *other = [self rootOf:[fact objectForKey:[[role oppositeRole] identifier]] ?: @""];
		if (![other isEqualToString:about]
		    && [[self combinationOf:other at:roles with:fact role:role] isEqualToArray:mine]) {
			return NO;
		}
	}
	return YES;
}

- (BOOL)ring:(ORMConstraint *)constraint accepts:(NSDictionary *)candidate
{
	NSArray<ORMRole *> *roles = [constraint allRoles];
	NSString *x = [self rootOf:[candidate objectForKey:[[roles firstObject] identifier]] ?: @""];
	NSString *y = [self rootOf:[candidate objectForKey:[[roles lastObject] identifier]] ?: @""];
	ORMRingType type = constraint.ringType;
	BOOL self_ = [x isEqualToString:y];
	if ((type & (ORMRingIrreflexive | ORMRingAsymmetric | ORMRingAcyclic | ORMRingIntransitive
	             | ORMRingStronglyIntransitive)) && self_) {
		return NO;
	}
	if ((type & ORMRingPurelyReflexive) && !self_) {
		return NO;
	}
	NSMutableDictionary<NSString *, NSMutableArray *> *next = [NSMutableDictionary dictionary];
	NSMutableSet *pairs = [NSMutableSet set];
	for (NSDictionary *fact in [self factsOf:[[roles firstObject] factType]]) {
		NSArray *pair = [self projectionOf:fact roles:roles];
		if (pair == nil) {
			continue;
		}
		[pairs addObject:pair];
		NSMutableArray *list = [next objectForKey:[pair firstObject]];
		if (list == nil) {
			list = [NSMutableArray array];
			[next setObject:list forKey:[pair firstObject]];
		}
		[list addObject:[pair lastObject]];
	}
	if ((type & (ORMRingAsymmetric | ORMRingAntisymmetric)) && !self_ && [pairs containsObject:@[ y, x ]]) {
		return NO;
	}
	if (type & ORMRingAcyclic) {
		/* A path from y back to x would close a cycle. */
		NSMutableArray *stack = [NSMutableArray arrayWithObject:y];
		NSMutableSet *visited = [NSMutableSet set];
		while ([stack count] > 0) {
			NSString *node = [stack lastObject];
			[stack removeLastObject];
			if ([node isEqualToString:x]) {
				return NO;
			}
			if (![visited containsObject:node]) {
				[visited addObject:node];
				[stack addObjectsFromArray:[next objectForKey:node] ?: @[]];
			}
		}
	}
	if ((type & ORMRingTransitive) && !self_) {
		/* Transitive where there are no chains of two: no fact goes on from
		 * where this one ends, or ends where it begins. */
		for (NSArray *pair in pairs) {
			NSString *a = [pair firstObject], *b = [pair lastObject];
			if ([a isEqualToString:b]) {
				continue;
			}
			if ([a isEqualToString:y] || [b isEqualToString:x]) {
				return NO;
			}
		}
	}
	if (type & (ORMRingIntransitive | ORMRingStronglyIntransitive)) {
		for (NSArray *pair in pairs) {
			NSString *a = [pair firstObject], *b = [pair lastObject];
			/* x y with a pair making a triangle of it. */
			if (([a isEqualToString:x] && [pairs containsObject:@[ b, y ]])
			    || ([b isEqualToString:y] && [pairs containsObject:@[ x, a ]])
			    || ([a isEqualToString:y] && [pairs containsObject:@[ x, b ]])
			    || ([b isEqualToString:x] && [pairs containsObject:@[ a, y ]])) {
				return NO;
			}
		}
	}
	return YES;
}

- (BOOL)setComparison:(ORMConstraint *)constraint accepts:(NSDictionary *)candidate of:(ORMFactType *)fact
{
	NSArray<ORMRoleSequence *> *sequences = constraint.roleSequences;
	NSUInteger mine = NSNotFound;
	for (NSUInteger i = 0; i < [sequences count]; i++) {
		if (ORMSequenceFact([sequences objectAtIndex:i]) == fact) {
			mine = i;
		}
	}
	if (mine == NSNotFound) {
		return YES;
	}
	NSArray *keys = [self projectionOf:candidate roles:[[sequences objectAtIndex:mine] roles]];
	if (keys == nil) {
		return YES;
	}
	BOOL (^has)(NSUInteger) = ^BOOL(NSUInteger i) {
		ORMRoleSequence *sequence = [sequences objectAtIndex:i];
		for (NSDictionary *other in [self factsOf:ORMSequenceFact(sequence)]) {
			if ([[self projectionOf:other roles:sequence.roles] isEqualToArray:keys]) {
				return YES;
			}
		}
		return NO;
	};
	if (constraint.kind == ORMExclusionConstraint) {
		for (NSUInteger i = 0; i < [sequences count]; i++) {
			if (i != mine && ORMSequenceFact([sequences objectAtIndex:i]) != nil && has(i)) {
				return NO;
			}
		}
		return YES;
	}
	/* Subset: the first in the second. Equality: each in the others made
	 * before. */
	for (NSUInteger i = 0; i < [sequences count]; i++) {
		ORMFactType *other = ORMSequenceFact([sequences objectAtIndex:i]);
		if (i == mine || other == nil || other == fact) {
			continue;
		}
		BOOL constrains = constraint.kind == ORMEqualityConstraint ? [_facts objectForKey:other.identifier] != nil
		                                                           : (mine == 0 && i == 1);
		if (constrains && !has(i)) {
			return NO;
		}
	}
	return YES;
}

/* The fact added, and for a symmetric ring its reverse too, or neither when
 * the reverse cannot be. Whether it was. */
- (BOOL)add:(NSDictionary<NSString *, NSString *> *)candidate to:(ORMFactType *)fact
{
	for (ORMConstraint *constraint in [[fact.roles firstObject] constraints]) {
		NSArray<ORMRole *> *ring = [constraint allRoles];
		if (constraint.kind != ORMRingConstraint || !(constraint.ringType & ORMRingSymmetric) || [ring count] != 2
		    || [[constraint factTypes] count] != 1) {
			continue;
		}
		if ([[ring firstObject] player] != [[ring lastObject] player]) {
			/* No fact can be of its roles' types the other way round: kept
			 * only by there being none, where none need be. */
			if (![self mandatory:[ring firstObject]] && ![self mandatory:[ring lastObject]]) {
				[self note:@"%@ is kept by \"%@\" having no facts: one the other way round would not be of its roles' "
				           @"types.", constraint.name, ORMReadingOf(fact)];
				return NO;
			}
			[self note:@"%@ is not kept: a fact the other way round would not be of its roles' types.", constraint.name];
			break;
		}
		NSMutableDictionary *reverse = [candidate mutableCopy];
		[reverse setObject:[candidate objectForKey:[[ring lastObject] identifier]] forKey:[[ring firstObject] identifier]];
		[reverse setObject:[candidate objectForKey:[[ring firstObject] identifier]] forKey:[[ring lastObject] identifier]];
		if ([reverse isEqualToDictionary:candidate]) {
			break;
		}
		[self record:candidate to:fact];
		if (![self accepts:reverse of:fact]) {
			[[_facts objectForKey:fact.identifier] removeLastObject];
			[self forget:candidate of:fact];
			return NO;
		}
		[self record:reverse to:fact];
		return YES;
	}
	[self record:candidate to:fact];
	return YES;
}

/* What -record:to: noted of the fact for its uniqueness constraints,
 * unnoted. */
- (void)forget:(NSDictionary *)candidate of:(ORMFactType *)fact
{
	for (ORMConstraint *constraint in [fact uniquenessConstraints]) {
		NSArray *keys = [self projectionOf:candidate roles:[constraint allRoles]];
		if (keys != nil) {
			[[_seen objectForKey:constraint.identifier] removeObject:keys];
		}
	}
}

- (void)record:(NSDictionary<NSString *, NSString *> *)candidate to:(ORMFactType *)fact
{
	NSMutableArray *list = [_facts objectForKey:fact.identifier];
	if (list == nil) {
		list = [NSMutableArray array];
		[_facts setObject:list forKey:fact.identifier];
	}
	[list addObject:candidate];
	for (ORMConstraint *constraint in [fact uniquenessConstraints]) {
		NSArray *keys = [self projectionOf:candidate roles:[constraint allRoles]];
		if (keys != nil) {
			NSMutableSet *seen = [_seen objectForKey:constraint.identifier];
			if (seen == nil) {
				seen = [NSMutableSet set];
				[_seen setObject:seen forKey:constraint.identifier];
			}
			[seen addObject:keys];
		}
	}
	for (ORMRole *role in fact.roles) {
		for (ORMConstraint *constraint in role.constraints) {
			if (constraint.kind == ORMFrequencyConstraint && role == [[constraint allRoles] firstObject]) {
				NSArray *keys = [self projectionOf:candidate roles:[constraint allRoles]];
				NSCountedSet *counts = [_frequencies objectForKey:constraint.identifier];
				if (counts == nil) {
					counts = [[NSCountedSet alloc] init];
					[_frequencies setObject:counts forKey:constraint.identifier];
				}
				if (keys != nil) {
					[counts addObject:keys];
				}
			}
		}
	}
}

/* The candidate'th fact: each role's player chosen by its own stride, so
 * candidates go through the pools' combinations; a value role's value
 * counted up where it is unique, round the pool's size where not. Roles in
 * fixed are given. */
- (NSDictionary *)candidate:(NSUInteger)t of:(ORMFactType *)fact fixed:(NSDictionary *)fixed
{
	NSMutableDictionary *candidate = [NSMutableDictionary dictionaryWithDictionary:fixed ?: @{}];
	NSArray<ORMRole *> *roles = [fact visibleRoles];
	NSUInteger j = 0;
	for (ORMRole *role in roles) {
		j++;
		if ([candidate objectForKey:role.identifier] != nil) {
			continue;
		}
		ORMObjectType *player = role.player;
		if ([player isEntity]) {
			NSArray *pool = [_pools objectForKey:player.identifier];
			if ([pool count] == 0) {
				return nil;
			}
			NSUInteger n = [pool count];
			[candidate setObject:[pool objectAtIndex:(t / n * j + t * j + (j - 1)) % n] forKey:role.identifier];
		} else {
			BOOL unique = NO;
			for (ORMConstraint *constraint in role.constraints) {
				unique = unique || (constraint.kind == ORMUniquenessConstraint && [[constraint allRoles] count] == 1);
			}
			[candidate setObject:[self valueToken:player index:unique ? t : t % _size role:role] forKey:role.identifier];
		}
	}
	return candidate;
}

- (BOOL)mandatory:(ORMRole *)role
{
	for (ORMConstraint *constraint in role.constraints) {
		if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple && !constraint.isImplied) {
			return YES;
		}
	}
	return NO;
}

/* A fact of the fact type the instance plays the role in, if one is
 * accepted within the tries. */
- (BOOL)cover:(NSString *)instance role:(ORMRole *)role
{
	ORMFactType *fact = role.factType;
	/* From the instance's place in its pool, so instances do not all take
	 * the same first partner. */
	NSUInteger start = [[_pools objectForKey:role.player.identifier] indexOfObject:instance];
	start = start == NSNotFound ? 0 : start;
	for (NSUInteger t = start; t < start + 200; t++) {
		NSDictionary *candidate = [self candidate:t of:fact fixed:@{ role.identifier: instance }];
		if (candidate == nil) {
			return NO;
		}
		if ([self accepts:candidate of:fact] && [self add:candidate to:fact]) {
			return YES;
		}
	}
	return NO;
}

- (NSSet *)playersOf:(ORMRole *)role
{
	NSMutableSet *players = [NSMutableSet set];
	for (NSDictionary *fact in [self factsOf:role.factType]) {
		NSString *player = [fact objectForKey:role.identifier];
		if (player != nil) {
			[players addObject:[self rootOf:player]];
		}
	}
	return players;
}

- (void)fill:(ORMFactType *)fact
{
	NSArray<ORMRole *> *roles = [fact visibleRoles];
	for (ORMRole *role in roles) {
		if ([role.player isEntity] && [[_pools objectForKey:role.player.identifier] count] == 0) {
			[self note:@"\"%@\" has no facts: %@ has no instances.", ORMReadingOf(fact), role.player.name];
			return;
		}
	}
	if ([_facts objectForKey:fact.identifier] == nil) {
		[_facts setObject:[NSMutableArray array] forKey:fact.identifier];
	}
	/* Every instance plays its mandatory roles. */
	for (ORMRole *role in roles) {
		if (![role.player isEntity] || ![self mandatory:role]) {
			continue;
		}
		for (NSString *instance in [_pools objectForKey:role.player.identifier]) {
			if (![[self playersOf:role] containsObject:[self rootOf:instance]] && ![self cover:instance role:role]) {
				[self note:@"%@ cannot play its role in \"%@\" as the constraints have it.", role.player.name,
				           ORMReadingOf(fact)];
				break;
			}
		}
	}
	/* Then more: as many as the largest pool, a functional role's player
	 * every third left out. */
	ORMRole *functional = nil;
	NSUInteger target = 0;
	for (ORMRole *role in roles) {
		NSUInteger count = [role.player isEntity] ? [[_pools objectForKey:role.player.identifier] count] : _size;
		target = MAX(target, count);
		if (role.isUnique && [role.player isEntity] && functional == nil) {
			functional = role;
		}
	}
	if (functional == nil && [roles count] > 1) {
		target = target * 3 / 2;
	}
	NSArray *pool = functional != nil ? [_pools objectForKey:functional.player.identifier] : nil;
	for (NSUInteger t = 0; t < target * 4 && [[self factsOf:fact] count] < target; t++) {
		NSDictionary *candidate = [self candidate:t of:fact fixed:nil];
		if (candidate == nil) {
			break;
		}
		if (functional != nil && ![self mandatory:functional]) {
			NSUInteger index = [pool indexOfObject:[candidate objectForKey:functional.identifier]];
			if (index != NSNotFound && index % 3 == 2) {
				continue;
			}
		}
		if ([self accepts:candidate of:fact]) {
			[self add:candidate to:fact];
		}
	}
}

/* What a subset or an equality still lacks, left out of the others: a
 * subset's facts not in its superset, an equality's not in all of its
 * sequences. Until nothing changes, as one may unsettle another. */
- (void)trimSetComparisons
{
	BOOL changed = YES;
	for (NSUInteger round = 0; changed && round < 10; round++) {
		changed = NO;
		for (ORMConstraint *constraint in _model.constraints) {
			if (constraint.kind != ORMSubsetConstraint && constraint.kind != ORMEqualityConstraint) {
				continue;
			}
			NSArray<ORMRoleSequence *> *sequences = constraint.roleSequences;
			BOOL single = [sequences count] >= 2;
			for (ORMRoleSequence *sequence in sequences) {
				single = single && ORMSequenceFact(sequence) != nil;
			}
			if (!single) {
				continue;
			}
			NSMutableArray<NSSet *> *projections = [NSMutableArray array];
			for (ORMRoleSequence *sequence in sequences) {
				NSMutableSet *set = [NSMutableSet set];
				for (NSDictionary *fact in [self factsOf:ORMSequenceFact(sequence)]) {
					NSArray *keys = [self projectionOf:fact roles:sequence.roles];
					if (keys != nil) {
						[set addObject:keys];
					}
				}
				[projections addObject:set];
			}
			NSUInteger trimmed = constraint.kind == ORMSubsetConstraint ? 1 : [sequences count];
			for (NSUInteger i = 0; i < trimmed; i++) {
				/* What the i-th must stay within: the superset, or all the
				 * others. */
				NSMutableSet *within = nil;
				for (NSUInteger j = 0; j < [sequences count]; j++) {
					if (j == i || (constraint.kind == ORMSubsetConstraint && j != 1)) {
						continue;
					}
					if (within == nil) {
						within = [[projections objectAtIndex:j] mutableCopy];
					} else {
						[within intersectSet:[projections objectAtIndex:j]];
					}
				}
				ORMRoleSequence *sequence = [sequences objectAtIndex:i];
				ORMFactType *fact = ORMSequenceFact(sequence);
				if (fact.objectifyingType != nil) {
					continue;
				}
				NSMutableArray *facts = [_facts objectForKey:fact.identifier];
				for (NSDictionary *each in [facts copy]) {
					NSArray *keys = [self projectionOf:each roles:sequence.roles];
					if (keys != nil && ![within containsObject:keys]) {
						[facts removeObject:each];
						[self forget:each of:fact];
						changed = YES;
					}
				}
			}
		}
	}
}

/* An instance of the objectifying type for each fact, and its subtypes'
 * shares of them. */
- (void)objectify:(ORMFactType *)fact
{
	NSMutableArray *ids = [NSMutableArray array];
	NSMutableArray *pool = [NSMutableArray array];
	ORMObjectType *type = fact.objectifyingType;
	/* Identified by values of its own rather than by the fact: those too. */
	NSArray<ORMRole *> *identifying = [type.preferredIdentifier allRoles];
	if ([[identifying firstObject] factType] == fact) {
		identifying = nil;
	}
	for (NSUInteger i = 0; i < [[self factsOf:fact] count]; i++) {
		NSString *identifier = ORMNewId();
		[ids addObject:identifier];
		NSMutableDictionary *byRole = nil;
		if ([identifying count] > 0) {
			byRole = [NSMutableDictionary dictionary];
			for (ORMRole *role in identifying) {
				NSArray *parts = [role.player isEntity] ? [_pools objectForKey:role.player.identifier] : nil;
				NSString *part = parts != nil ? ([parts count] > 0 ? [parts objectAtIndex:i % [parts count]] : nil)
				                              : [self valueToken:role.player index:i role:role];
				if (part != nil) {
					[byRole setObject:part forKey:role.identifier];
				}
			}
		}
		[pool addObject:[_population instanceOf:type.identifier objectifying:identifier identifiedBy:byRole]];
	}
	[_factIds setObject:ids forKey:fact.identifier];
	[_pools setObject:pool forKey:fact.objectifyingType.identifier];
	[self makeSubtypes];
}

/* Disjunctive mandatories: an instance playing none of the roles plays the
 * first it can. */
/* Whether the instance plays in a fact made. */
- (BOOL)playsAnything:(NSString *)instance
{
	for (NSArray *facts in [_facts allValues]) {
		for (NSDictionary *fact in facts) {
			if ([[fact allValues] containsObject:instance]) {
				return YES;
			}
		}
	}
	return NO;
}

- (void)coverDisjunctions
{
	for (ORMConstraint *constraint in _model.constraints) {
		if (constraint.kind != ORMMandatoryConstraint || constraint.isSimple || constraint.isImplied) {
			continue;
		}
		NSArray<ORMRole *> *roles = [constraint allRoles];
		ORMObjectType *player = [[roles firstObject] player];
		BOOL filled = YES;
		for (ORMRole *role in roles) {
			filled = filled && [_facts objectForKey:role.factType.identifier] != nil;
		}
		if (![player isEntity] || !filled) {
			continue;
		}
		for (NSString *instance in [[_pools objectForKey:player.identifier] copy]) {
			BOOL plays = NO;
			for (ORMRole *role in roles) {
				plays = plays || [[self playersOf:role] containsObject:[self rootOf:instance]];
			}
			BOOL covered = plays;
			for (ORMRole *role in roles) {
				covered = covered || [self cover:instance role:role];
			}
			/* One too many, playing nothing at all: there is no need of it. */
			if (!covered && ![self playsAnything:instance] && [_population removeInstance:instance]) {
				[[_pools objectForKey:player.identifier] removeObject:instance];
				continue;
			}
			if (!covered) {
				[self note:@"%@ cannot play any of the roles %@ says one of which it must.", player.name, constraint.name];
				break;
			}
		}
	}
}

/* External uniqueness over binaries about one type: a second instance with
 * a combination another has loses its fact in the last of them. */
- (void)keepExternalUniqueness
{
	for (ORMConstraint *constraint in _model.constraints) {
		if (constraint.kind != ORMUniquenessConstraint || constraint.isInternal
		    || constraint.preferredIdentifierFor != nil) {
			continue;
		}
		NSArray<ORMRole *> *roles = [constraint allRoles];
		BOOL binaries = [roles count] > 1;
		for (ORMRole *role in roles) {
			binaries = binaries && [role.factType.roles count] == 2;
		}
		if (!binaries) {
			[self note:@"%@ is not kept: its roles are not of binaries about one type.", constraint.name];
			continue;
		}
		NSMutableDictionary<NSString *, NSMutableArray *> *combinations = [NSMutableDictionary dictionary];
		for (NSUInteger i = 0; i < [roles count]; i++) {
			ORMRole *role = [roles objectAtIndex:i];
			for (NSDictionary *fact in [self factsOf:role.factType]) {
				NSString *about = [fact objectForKey:[[role oppositeRole] identifier]];
				NSString *value = [fact objectForKey:role.identifier];
				if (about == nil || value == nil) {
					continue;
				}
				NSMutableArray *combination = [combinations objectForKey:[self rootOf:about]];
				if (combination == nil) {
					combination = [NSMutableArray array];
					for (NSUInteger k = 0; k < [roles count]; k++) {
						[combination addObject:[NSNull null]];
					}
					[combinations setObject:combination forKey:[self rootOf:about]];
				}
				[combination replaceObjectAtIndex:i withObject:[self rootOf:value]];
			}
		}
		NSMutableSet *seen = [NSMutableSet set];
		ORMRole *last = [roles lastObject];
		for (NSString *about in [[combinations allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			NSArray *combination = [combinations objectForKey:about];
			if ([combination containsObject:[NSNull null]]) {
				continue;
			}
			if (![seen containsObject:combination]) {
				[seen addObject:combination];
				continue;
			}
			if ([self mandatory:[last oppositeRole]] || last.factType.objectifyingType != nil) {
				[self note:@"%@ is not kept: %@ must play its role in \"%@\".", constraint.name,
				           [last oppositeRole].player.name, ORMReadingOf(last.factType)];
				break;
			}
			NSMutableArray *facts = [_facts objectForKey:last.factType.identifier];
			for (NSDictionary *fact in [facts copy]) {
				if ([[self rootOf:[fact objectForKey:[[last oppositeRole] identifier]] ?: @""] isEqualToString:about]) {
					[facts removeObject:fact];
				}
			}
		}
	}
}

#pragma mark The population

- (ORMSamplePopulation *)population
{
	_population = [[ORMSamplePopulation alloc] init];
	_notes = [NSMutableArray array];
	_pools = [NSMutableDictionary dictionary];
	_roots = [NSMutableDictionary dictionary];
	_facts = [NSMutableDictionary dictionary];
	_seen = [NSMutableDictionary dictionary];
	_frequencies = [NSMutableDictionary dictionary];
	_factIds = [NSMutableDictionary dictionary];
	_identifying = [NSMutableDictionary dictionary];
	[self makeInstances];
	for (ORMFactType *fact in [self factOrder]) {
		[self fill:fact];
		if (fact.objectifyingType != nil) {
			[self objectify:fact];
		}
	}
	[self coverDisjunctions];
	[self keepExternalUniqueness];
	[self trimSetComparisons];
	for (ORMConstraint *constraint in _model.constraints) {
		if (constraint.kind == ORMValueComparisonConstraint) {
			[self note:@"%@ is not kept: value comparisons are not made up to.", constraint.name];
		}
	}
	for (ORMFactType *fact in _model.factTypes) {
		NSArray *ids = [_factIds objectForKey:fact.identifier];
		/* Those made, not those identifying instances are. */
		NSArray *facts = [_facts objectForKey:fact.identifier] ?: @[];
		for (NSUInteger i = 0; i < [facts count]; i++) {
			if (i < [ids count]) {
				[_population factOf:fact.identifier players:[facts objectAtIndex:i] identifier:[ids objectAtIndex:i]];
			} else {
				[_population factOf:fact.identifier players:[facts objectAtIndex:i]];
			}
		}
	}
	return _population;
}

@end
