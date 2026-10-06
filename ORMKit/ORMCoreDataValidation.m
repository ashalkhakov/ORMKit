/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataValidation.h"
#import "ORMJoinedFacade.h"
#import "ORMVerbalizer.h"
#import "ORMQueryPlanner.h"
#if __has_include(<ORMRuntime/ORMRuntime.h>)
#import <ORMRuntime/ORMRuntime.h>
#else
#import "ORMRuntime.h"
#endif
#import "ORMCDModel+CoreData.h"
#import "ORMQuery.h"
#import "ORMPath.h"

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
		[self skip:constraint because:@"its roles are not all properties of one entity"];
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
	[self skip:constraint because:@"its arguments are not properties of one entity"];
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
		[self skip:constraint because:@"its arguments are not properties of one entity"];
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
		[self skip:constraint because:@"it does not compare two attributes of one entity"];
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
	[self rules];
	[self derivations];
	[self queries];
}

/* The constraint queries (docs/RULES.md): each a predicate its root's
 * objects must not meet, asked of self. Checked from that entity only: a
 * change elsewhere on the rule's paths is seen when it is saved again, as
 * the check's comment says. */
- (void)rules
{
	ORMQueryPlanner *planner = nil;
	ORMQueryInterpreter *interpreter = nil;
	for (ORMQuery *query in [ORMQuery queriesInModel:_model]) {
		if (query.kind != ORMQueryConstraint) {
			continue;
		}
		if (planner == nil) {
			planner = [[ORMQueryPlanner alloc] initWithCoreData:_coreData];
			interpreter = [[ORMQueryInterpreter alloc] initWithModel:[_coreData managedObjectModel]];
		}
		NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:_model] sentencesForQuery:query];
		NSString *text = [sentences count] > 0 ? [[sentences valueForKey:@"text"] componentsJoinedByString:@" "] : query.name;
		ORMQueryPlan *plan = [planner planForQuery:query];
		ORMCDEntity *entity = plan.entityName != nil ? [_coreData entityNamed:plan.entityName] : nil;
		NSString *why = nil;
		NSPredicate *predicate = nil;
		if (entity == nil || [plan.notes count] > 0) {
			why = entity == nil ? @"it reads no entity" : [plan.notes componentsJoinedByString:@" "];
		} else {
			/* What the driver asks of the object: one predicate. */
			predicate = [interpreter predicateForPlan:plan reason:&why];
		}
		if (predicate == nil) {
			[_skipped addObject:[NSString stringWithFormat:@"%@: %@", query.name, text]];
			[_notes addObject:[NSString stringWithFormat:@"%@: %@ (%@)", query.name, why ?: @"?", text]];
			continue;
		}
		/* Its rows are what must not be: a valid object is none of them. */
		ORMRule *rule = [self add:@{ @"not": @{ @"plan": [plan propertyList] } }
		                       to:entity
		                    named:query.name
		                     text:text
		                     keys:@[]
		                  deontic:query.isDeontic];
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
		if (query.kind != ORMQueryList && query.kind != ORMQueryCalculation) {
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
 * relationship is set to. nil where the plan lists either by no path. */
static ORMQueryPlan *
ORMObjectColumns(ORMQueryPlan *plan, ORMQueryNode *root, ORMQueryNode *node)
{
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMQueryNode *each in @[ root, node ]) {
		ORMPlanColumn *column = [plan columnOfNode:each.identifier];
		if (column == nil || column.value != nil) {
			return nil;
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
 * property the second role is mapped to set to what it reaches. The
 * driver asks the rule of each object a change can reach, in memory. */
- (void)derivations
{
	ORMQueryPlanner *planner = nil;
	for (ORMQuery *query in ORMInDependencyOrder([ORMQuery derivationsInModel:_model])) {
		ORMFactType *fact = query.derivedFactType;
		ORMDerivationRule *rule = fact.isDerived ? [fact derivationRule] : nil;
		if (!rule.isStored) {
			continue;
		}
		NSString *what = [[fact primaryReading] expandedText] ?: fact.name;
		NSString *why = nil;
		NSArray *roles = [fact visibleRoles];
		NSArray *columns = [query derivedColumns];
		NSArray *target = [roles count] == 2 ? [_bySource objectForKey:[(ORMRole *)[roles lastObject] identifier]] : nil;
		ORMCDEntity *entity = [target firstObject];
		ORMCDProperty *property = [target lastObject];
		if (rule.isPartial) {
			why = @"partly derived: what is asserted and what is derived are kept in one property";
		} else if ([roles count] != 2 || [columns count] != 2 || [columns firstObject] != query.root) {
			why = @"its rule does not go from one role's player to the other's";
		} else if (property == nil) {
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
			plan = [planned.notes count] == 0 ? ORMObjectColumns(planned, query.root, [columns lastObject]) : nil;
			trails = [plan trailsFromRead];
			if (plan == nil || ![plan.entityName isEqualToString:entity.name]) {
				why = @"its rule does not plan from the object the property is of";
			} else if ([plan.definitions count] > 0 || trails == nil) {
				why = @"its rule reads what no path from the object says, which is not asked of it in memory";
			}
		}
		NSArray *backs = why == nil ? [self backsFrom:entity trails:trails] : nil;
		if (why == nil && backs == nil) {
			why = @"a relationship on its path has no inverse";
		}
		if (why != nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: not worked out at save: %@.", what, why]];
			continue;
		}
		NSString *kind = [property isKindOfClass:[ORMCDAttribute class]] ? @"value"
			: (((ORMCDRelationship *)property).toMany ? @"objects" : @"object");
		[_derivations addObject:[ORMStoredDerivation derivationWithText:what root:entity.name plan:plan
		                                                         target:property.name
		                                                           kind:kind
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
	                  @"\tNSMutableSet *changed = [NSMutableSet setWithSet:[self insertedObjects]];\n"
	                  @"\t[changed unionSet:[self updatedObjects]];\n"
	                  @"\t[changed unionSet:[self deletedObjects]];\n"
	                  @"\t/* The model's tables (%@.ormplans), by the driver. */\n"
	                  @"\tORMTables *tables = [ORMTables tablesNamed:%@ error:error];\n"
	                  @"\tif (tables == nil) {\n"
	                  @"\t\treturn NO;\n"
	                  @"\t}\n"
	                  @"\tORMSaveHook *hook = [[ORMSaveHook alloc] initWithTables:tables];\n"
	                  @"\tif (![hook deriveInContext:self changed:changed error:error]) {\n"
	                  @"\t\treturn NO;\n"
	                  @"\t}\n"
	                  @"\tNSMutableArray<NSError *> *violations = [NSMutableArray array];\n",
	                  _name, ORMLiteral(_name)];
	[out appendString:@"\t[hook prepareJoinedInContext:self changed:changed violations:violations];\n"
	                  @"\t[hook checkInContext:self changed:changed violations:violations];\n"
	                  @"\treturn [ORMValidator report:violations error:error];\n"
	                  @"}\n\n@end\n"];
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
	return [[ORMTables tablesOfModel:_name queries:_queries derivations:_derivations rules:_rules ruleBacks:backs]
		tablesWithJoined:[_joined types]];
}

/* Whether the code reads tables: it has rules or a save hook. */
- (BOOL)hasTables
{
	return [_rules count] > 0 || [_queries count] > 0 || [self hasSaveHook];
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
