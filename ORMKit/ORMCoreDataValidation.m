/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataValidation.h"
#import "ORMVerbalizer.h"

/* One check: a condition that holds of a valid object, said in Objective-C
 * over self, with what to say when it does not. */
@interface ORMValidationRule : NSObject
@property (nonatomic, copy) NSString *constraint;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *condition;
@property (nonatomic, copy) NSArray<NSString *> *keys;
@property (nonatomic) BOOL deontic;
@end

@implementation ORMValidationRule
@end

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

/* A number as a C literal, or nil when the bound is not one. */
static NSString *
ORMNumberLiteral(NSString *value)
{
	NSScanner *scanner = [NSScanner scannerWithString:value ?: @""];
	double number = 0;
	if (![scanner scanDouble:&number] || ![scanner isAtEnd]) {
		return nil;
	}
	return [value rangeOfString:@"."].location == NSNotFound
	               && [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"eE"]].location
	                      == NSNotFound
		? [value stringByAppendingString:@".0"]
		: value;
}

@implementation ORMValidationGenerator
{
	ORMModel *_model;
	ORMCDModel *_coreData;
	NSArray<ORMMappingNote *> *_mapperNotes;
	NSString *_name;
	NSString *_prefix;
	/* Property source (the far role) -> @[ entity, property ]. */
	NSMutableDictionary<NSString *, NSArray *> *_bySource;
	/* Entity name -> its rules. */
	NSMutableDictionary<NSString *, NSMutableArray<ORMValidationRule *> *> *_rules;
	NSMutableArray<NSString *> *_notes;
	NSMutableArray<NSString *> *_skipped;
	NSUInteger _ruleCount;
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
		_prefix = _name;
		[self collect];
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

/* Whether the property holds anything: a unary's attribute true, a to-many
 * not empty, anything else set. */
- (NSString *)presenceOf:(NSArray *)place
{
	ORMCDProperty *property = [place lastObject];
	ORMRole *source = [_model elementWithId:property.source];
	if ([property isKindOfClass:[ORMCDAttribute class]] && source.player.isImplicitBooleanValue) {
		return [NSString stringWithFormat:@"%@True(self, %@)", _prefix, ORMLiteral(property.name)];
	}
	return [NSString stringWithFormat:@"%@Present(self, %@)", _prefix, ORMLiteral(property.name)];
}

- (NSString *)relatedOf:(NSArray *)place
{
	return [NSString stringWithFormat:@"%@Related(self, %@)", _prefix, ORMLiteral([self keyOf:place])];
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

- (void)add:(NSString *)condition to:(ORMCDEntity *)entity for:(ORMConstraint *)constraint keys:(NSArray *)keys
{
	[self add:condition to:entity named:constraint.name ?: constraint.identifier text:[self textOf:constraint]
	     keys:keys deontic:constraint.modality == ORMDeontic];
}

- (void)add:(NSString *)condition
         to:(ORMCDEntity *)entity
      named:(NSString *)name
       text:(NSString *)text
       keys:(NSArray *)keys
    deontic:(BOOL)deontic
{
	ORMValidationRule *rule = [[ORMValidationRule alloc] init];
	rule.constraint = name;
	rule.text = text;
	rule.condition = condition;
	rule.keys = keys;
	rule.deontic = deontic;
	NSMutableArray *rules = [_rules objectForKey:entity.name];
	if (rules == nil) {
		rules = [NSMutableArray array];
		[_rules setObject:rules forKey:entity.name];
	}
	[rules addObject:rule];
	_ruleCount++;
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
	[self add:[terms componentsJoinedByString:@" || "] to:entity for:constraint keys:[self keysOf:places]];
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
		NSString *bound = constraint.exclusiveOrPartner != nil ? @"== 1" : @"<= 1";
		[self add:[NSString stringWithFormat:@"(%@) %@", [terms componentsJoinedByString:@" + "], bound]
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
				[terms addObject:[NSString stringWithFormat:@"![%@ intersectsSet:%@]",
				                                            [self relatedOf:[places objectAtIndex:i]],
				                                            [self relatedOf:[places objectAtIndex:j]]]];
			}
		}
		[self add:[terms componentsJoinedByString:@" && "] to:entity for:constraint keys:[self keysOf:places]];
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
			NSString *a = [self presenceOf:[places objectAtIndex:i]];
			NSString *b = [self presenceOf:[places objectAtIndex:i + 1]];
			[terms addObject:equality ? [NSString stringWithFormat:@"%@ == %@", a, b]
			                          : [NSString stringWithFormat:@"(!%@ || %@)", a, b]];
		}
	} else if ((places = [self pairPlaces:constraint entity:&entity]) != nil) {
		for (NSUInteger i = 0; i + 1 < [places count]; i++) {
			NSString *a = [self relatedOf:[places objectAtIndex:i]];
			NSString *b = [self relatedOf:[places objectAtIndex:i + 1]];
			[terms addObject:[NSString stringWithFormat:equality ? @"[%@ isEqualToSet:%@]" : @"[%@ isSubsetOfSet:%@]",
			                                            a, b]];
		}
	}
	if ([terms count] == 0) {
		[self skip:constraint because:@"its arguments are not properties of one entity"];
		return;
	}
	[self add:[terms componentsJoinedByString:@" && "] to:entity for:constraint keys:[self keysOf:places]];
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
	NSDictionary *checks = @{ @(ORMRingIrreflexive): @"Irreflexive",
		                      @(ORMRingReflexive): @"Reflexive",
		                      @(ORMRingPurelyReflexive): @"PurelyReflexive",
		                      @(ORMRingSymmetric): @"Symmetric",
		                      @(ORMRingAsymmetric): @"Asymmetric",
		                      @(ORMRingAntisymmetric): @"Antisymmetric",
		                      @(ORMRingTransitive): @"Transitive",
		                      @(ORMRingIntransitive): @"Intransitive",
		                      @(ORMRingStronglyIntransitive): @"StronglyIntransitive",
		                      @(ORMRingAcyclic): @"Acyclic" };
	NSMutableArray *terms = [NSMutableArray array];
	for (NSNumber *bit in [[checks allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if ((constraint.ringType & [bit unsignedIntegerValue]) != 0) {
			[terms addObject:[NSString stringWithFormat:@"%@%@(self, %@)", _prefix, [checks objectForKey:bit],
			                                            ORMLiteral([self keyOf:place])]];
		}
	}
	if ([terms count] == 0) {
		[self skip:constraint because:@"it has no ring type"];
		return;
	}
	[self add:[terms componentsJoinedByString:@" && "] to:[place firstObject] for:constraint keys:@[ [self keyOf:place] ]];
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
	[self add:[NSString stringWithFormat:@"%@Compare(self, %@, %@, %@)", _prefix,
	                                     ORMLiteral([self keyOf:[places objectAtIndex:0]]),
	                                     ORMLiteral([self keyOf:[places objectAtIndex:1]]), ORMLiteral(operator)]
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
	NSMutableArray *alternatives = [NSMutableArray array];
	for (ORMValueRange *range in values.ranges) {
		NSMutableArray *bounds = [NSMutableArray array];
		if ([range.minValue length] > 0) {
			NSString *min = ORMNumberLiteral(range.minValue);
			if (min == nil) {
				return;
			}
			[bounds addObject:[NSString stringWithFormat:@"v %@ %@", range.minInclusion == ORMRangeOpen ? @">" : @">=",
			                                             min]];
		}
		if ([range.maxValue length] > 0) {
			NSString *max = ORMNumberLiteral(range.maxValue);
			if (max == nil) {
				return;
			}
			[bounds addObject:[NSString stringWithFormat:@"v %@ %@", range.maxInclusion == ORMRangeOpen ? @"<" : @"<=",
			                                             max]];
		}
		[alternatives addObject:[bounds count] > 0 ? [NSString stringWithFormat:@"(%@)",
		                                                                        [bounds componentsJoinedByString:@" && "]]
		                                           : @"YES"];
	}
	if ([alternatives count] == 0) {
		return;
	}
	NSString *condition = [NSString stringWithFormat:@"%@Within(self, %@, ^BOOL(double v) { return %@; })", _prefix,
	                                                 ORMLiteral(attribute.name),
	                                                 [alternatives componentsJoinedByString:@" || "]];
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
	NSArray *entities = [self entitiesWithRules];
	for (ORMCDEntity *entity in entities) {
		[out appendFormat:@"#import \"%@\"\n", [self headerOf:entity]];
	}
	for (ORMCDEntity *entity in entities) {
		[out appendFormat:@"\n@interface %@ (ORMValidation)\n", [self classOf:entity]];
		if (![self ancestorHasRules:entity]) {
			[out appendString:@"/* NO, with what is violated in the error: one NSError, or an\n"
			                  @" * NSValidationMultipleErrorsError with them under NSDetailedErrorsKey. */\n"
			                  @"- (BOOL)orm_validateConstraints:(NSError **)error;\n"
			                  @"/* The deontic rules broken: obligations to be told of, not enforced. */\n"
			                  @"- (NSArray<NSError *> *)orm_deonticViolations;\n"];
		}
		[out appendString:@"- (void)orm_collectViolations:(NSMutableArray<NSError *> *)violations deontic:(BOOL)deontic;\n"
		                  @"@end\n"];
	}
	return out;
}

- (NSString *)helpers
{
	NSString *helpers =
		@"#define PFX_UNUSED __attribute__((unused))\n\n"
		@"static PFX_UNUSED NSError *\n"
		@"PFXViolation(NSManagedObject *object, NSString *constraint, NSString *text, NSArray<NSString *> *keys)\n"
		@"{\n"
		@"\tNSMutableDictionary *info = [NSMutableDictionary dictionary];\n"
		@"\t[info setObject:text forKey:NSLocalizedDescriptionKey];\n"
		@"\t[info setObject:object forKey:NSValidationObjectErrorKey];\n"
		@"\tif ([keys count] > 0) {\n"
		@"\t\t[info setObject:[keys objectAtIndex:0] forKey:NSValidationKeyErrorKey];\n"
		@"\t}\n"
		@"\t[info setObject:constraint forKey:@\"ORMConstraint\"];\n"
		@"\t[info setObject:keys forKey:@\"ORMKeys\"];\n"
		@"\treturn [NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectValidationError userInfo:info];\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXReport(NSArray<NSError *> *violations, NSError **error)\n"
		@"{\n"
		@"\tif ([violations count] == 0) {\n"
		@"\t\treturn YES;\n"
		@"\t}\n"
		@"\tif (error != NULL) {\n"
		@"\t\t*error = [violations count] == 1\n"
		@"\t\t\t? [violations objectAtIndex:0]\n"
		@"\t\t\t: [NSError errorWithDomain:NSCocoaErrorDomain\n"
		@"\t\t\t                      code:NSValidationMultipleErrorsError\n"
		@"\t\t\t                  userInfo:@{ NSDetailedErrorsKey: violations,\n"
		@"\t\t\t                              NSLocalizedDescriptionKey: @\"Several constraints are violated.\" }];\n"
		@"\t}\n"
		@"\treturn NO;\n"
		@"}\n\n"
		@"/* What the property holds, as a set: nothing, one value, or a to-many's objects. */\n"
		@"static PFX_UNUSED NSSet *\n"
		@"PFXRelated(id object, NSString *key)\n"
		@"{\n"
		@"\tid value = [object valueForKey:key];\n"
		@"\tif (value == nil) {\n"
		@"\t\treturn [NSSet set];\n"
		@"\t}\n"
		@"\tif ([value isKindOfClass:[NSSet class]]) {\n"
		@"\t\treturn value;\n"
		@"\t}\n"
		@"\tif ([value isKindOfClass:[NSOrderedSet class]]) {\n"
		@"\t\treturn [(NSOrderedSet *)value set];\n"
		@"\t}\n"
		@"\tif ([value isKindOfClass:[NSArray class]]) {\n"
		@"\t\treturn [NSSet setWithArray:value];\n"
		@"\t}\n"
		@"\treturn [NSSet setWithObject:value];\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXPresent(id object, NSString *key)\n"
		@"{\n"
		@"\treturn [PFXRelated(object, key) count] > 0;\n"
		@"}\n\n"
		@"/* A unary's attribute: absent is false. */\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXTrue(id object, NSString *key)\n"
		@"{\n"
		@"\treturn [[object valueForKey:key] boolValue];\n"
		@"}\n\n"
		@"/* Everything reachable from the objects through the relationship, them included. */\n"
		@"static PFX_UNUSED NSSet *\n"
		@"PFXReachable(NSSet *from, NSString *key)\n"
		@"{\n"
		@"\tNSMutableSet *seen = [NSMutableSet setWithSet:from];\n"
		@"\tNSMutableArray *pending = [NSMutableArray arrayWithArray:[from allObjects]];\n"
		@"\twhile ([pending count] > 0) {\n"
		@"\t\tid at = [pending lastObject];\n"
		@"\t\t[pending removeLastObject];\n"
		@"\t\tfor (id next in PFXRelated(at, key)) {\n"
		@"\t\t\tif (![seen containsObject:next]) {\n"
		@"\t\t\t\t[seen addObject:next];\n"
		@"\t\t\t\t[pending addObject:next];\n"
		@"\t\t\t}\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn seen;\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXIrreflexive(id object, NSString *key)\n"
		@"{\n"
		@"\treturn ![PFXRelated(object, key) containsObject:object];\n"
		@"}\n\n"
		@"/* Related to anything, related to itself. */\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXReflexive(id object, NSString *key)\n"
		@"{\n"
		@"\tNSSet *related = PFXRelated(object, key);\n"
		@"\treturn [related count] == 0 || [related containsObject:object];\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXPurelyReflexive(id object, NSString *key)\n"
		@"{\n"
		@"\tfor (id other in PFXRelated(object, key)) {\n"
		@"\t\tif (other != object) {\n"
		@"\t\t\treturn NO;\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn YES;\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXSymmetric(id object, NSString *key)\n"
		@"{\n"
		@"\tfor (id other in PFXRelated(object, key)) {\n"
		@"\t\tif (![PFXRelated(other, key) containsObject:object]) {\n"
		@"\t\t\treturn NO;\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn YES;\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXAsymmetric(id object, NSString *key)\n"
		@"{\n"
		@"\tfor (id other in PFXRelated(object, key)) {\n"
		@"\t\tif ([PFXRelated(other, key) containsObject:object]) {\n"
		@"\t\t\treturn NO;\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn YES;\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXAntisymmetric(id object, NSString *key)\n"
		@"{\n"
		@"\tfor (id other in PFXRelated(object, key)) {\n"
		@"\t\tif (other != object && [PFXRelated(other, key) containsObject:object]) {\n"
		@"\t\t\treturn NO;\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn YES;\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXTransitive(id object, NSString *key)\n"
		@"{\n"
		@"\tNSSet *related = PFXRelated(object, key);\n"
		@"\tfor (id other in related) {\n"
		@"\t\tfor (id further in PFXRelated(other, key)) {\n"
		@"\t\t\tif (![related containsObject:further]) {\n"
		@"\t\t\t\treturn NO;\n"
		@"\t\t\t}\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn YES;\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXIntransitive(id object, NSString *key)\n"
		@"{\n"
		@"\tNSSet *related = PFXRelated(object, key);\n"
		@"\tfor (id other in related) {\n"
		@"\t\tfor (id further in PFXRelated(other, key)) {\n"
		@"\t\t\tif ([related containsObject:further]) {\n"
		@"\t\t\t\treturn NO;\n"
		@"\t\t\t}\n"
		@"\t\t}\n"
		@"\t}\n"
		@"\treturn YES;\n"
		@"}\n\n"
		@"/* Nothing related directly is also reached the long way round. */\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXStronglyIntransitive(id object, NSString *key)\n"
		@"{\n"
		@"\tNSSet *related = PFXRelated(object, key);\n"
		@"\tNSMutableSet *second = [NSMutableSet set];\n"
		@"\tfor (id other in related) {\n"
		@"\t\t[second unionSet:PFXRelated(other, key)];\n"
		@"\t}\n"
		@"\treturn ![PFXReachable(second, key) intersectsSet:related];\n"
		@"}\n\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXAcyclic(id object, NSString *key)\n"
		@"{\n"
		@"\treturn ![PFXReachable(PFXRelated(object, key), key) containsObject:object];\n"
		@"}\n\n"
		@"/* The two values compared, when both are set. */\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXCompare(id object, NSString *first, NSString *second, NSString *op)\n"
		@"{\n"
		@"\tid a = [object valueForKey:first];\n"
		@"\tid b = [object valueForKey:second];\n"
		@"\tif (a == nil || b == nil) {\n"
		@"\t\treturn YES;\n"
		@"\t}\n"
		@"\tNSComparisonResult order = [a compare:b];\n"
		@"\tif ([op isEqualToString:@\"<\"]) {\n"
		@"\t\treturn order == NSOrderedAscending;\n"
		@"\t} else if ([op isEqualToString:@\"<=\"]) {\n"
		@"\t\treturn order != NSOrderedDescending;\n"
		@"\t} else if ([op isEqualToString:@\">\"]) {\n"
		@"\t\treturn order == NSOrderedDescending;\n"
		@"\t} else if ([op isEqualToString:@\">=\"]) {\n"
		@"\t\treturn order != NSOrderedAscending;\n"
		@"\t} else if ([op isEqualToString:@\"==\"]) {\n"
		@"\t\treturn order == NSOrderedSame;\n"
		@"\t}\n"
		@"\treturn order != NSOrderedSame;\n"
		@"}\n\n"
		@"/* The number within the ranges, when it is set. */\n"
		@"static PFX_UNUSED BOOL\n"
		@"PFXWithin(id object, NSString *key, BOOL (^within)(double value))\n"
		@"{\n"
		@"\tid value = [object valueForKey:key];\n"
		@"\treturn value == nil || within([value doubleValue]);\n"
		@"}\n";
	return [helpers stringByReplacingOccurrencesOfString:@"PFX" withString:_prefix];
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
	[out appendString:[self helpers]];
	for (ORMCDEntity *entity in [self entitiesWithRules]) {
		NSString *class = [self classOf:entity];
		[out appendFormat:@"\n@implementation %@ (ORMValidation)\n\n", class];
		if (![self ancestorHasRules:entity]) {
			[out appendFormat:@"- (BOOL)orm_validateConstraints:(NSError **)error\n"
			                  @"{\n"
			                  @"\tNSMutableArray<NSError *> *violations = [NSMutableArray array];\n"
			                  @"\t[self orm_collectViolations:violations deontic:NO];\n"
			                  @"\treturn %@Report(violations, error);\n"
			                  @"}\n\n"
			                  @"- (NSArray<NSError *> *)orm_deonticViolations\n"
			                  @"{\n"
			                  @"\tNSMutableArray<NSError *> *violations = [NSMutableArray array];\n"
			                  @"\t[self orm_collectViolations:violations deontic:YES];\n"
			                  @"\treturn violations;\n"
			                  @"}\n\n",
			                  _prefix];
		}
		[out appendString:@"- (void)orm_collectViolations:(NSMutableArray<NSError *> *)violations deontic:(BOOL)deontic\n"
		                  @"{\n"];
		if ([self ancestorHasRules:entity]) {
			[out appendString:@"\t[super orm_collectViolations:violations deontic:deontic];\n"];
		}
		for (NSNumber *deontic in @[ @NO, @YES ]) {
			NSMutableArray *rules = [NSMutableArray array];
			for (ORMValidationRule *rule in [_rules objectForKey:entity.name]) {
				if (rule.deontic == [deontic boolValue]) {
					[rules addObject:rule];
				}
			}
			if ([rules count] == 0) {
				continue;
			}
			[out appendFormat:@"\tif (%@deontic) {\n", [deontic boolValue] ? @"" : @"!"];
			for (ORMValidationRule *rule in rules) {
				NSMutableArray *keys = [NSMutableArray array];
				for (NSString *key in rule.keys) {
					[keys addObject:ORMLiteral(key)];
				}
				[out appendFormat:@"\t\t/* %@ */\n"
				                  @"\t\tif (!(%@)) {\n"
				                  @"\t\t\t[violations addObject:%@Violation(self, %@,\n"
				                  @"\t\t\t                                  %@,\n"
				                  @"\t\t\t                                  @[ %@ ])];\n"
				                  @"\t\t}\n",
				                  ORMCommentText(rule.text), rule.condition, _prefix, ORMLiteral(rule.constraint),
				                  ORMLiteral(rule.text), [keys componentsJoinedByString:@", "]];
			}
			[out appendString:@"\t}\n"];
		}
		[out appendString:@"}\n\n@end\n"];
	}
	return out;
}

- (NSDictionary<NSString *, NSString *> *)files
{
	return @{ [_name stringByAppendingString:@"Validation.h"]: [self header],
		      [_name stringByAppendingString:@"Validation.m"]: [self implementation] };
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
