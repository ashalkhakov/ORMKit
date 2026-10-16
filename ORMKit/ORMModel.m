/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModelPriv.h"
#import "ORMXML.h"
#import "ORMReadingText.h"
#import <objc/runtime.h>

#define CORE ORMCoreNamespace

NSXMLElement *
ORMModelElementOfDocument(NSXMLDocument *document)
{
	NSXMLElement *root = [document rootElement];
	if (ORMIs(root, CORE, @"ORMModel")) {
		return root;
	}
	return ORMChild(root, CORE, @"ORMModel");
}

/* The element's text child's text, under a container: an object type's
 * Definitions/Definition/Text. */
static NSString *
ORMNestedText(NSXMLElement *element, NSString *container, NSString *item)
{
	NSXMLElement *first = [ORMGrandchildren(element, CORE, container, CORE, item) firstObject];
	return ORMChildText(first, CORE, @"Text");
}

@implementation ORMElement

- (instancetype)initWithElement:(NSXMLElement *)element model:(ORMModel *)model
{
	if ((self = [super init])) {
		_element = element;
		_model = model;
		_identifier = [ORMAttribute(element, @"id") copy];
		_name = [(ORMAttribute(element, @"Name") ?: ORMAttribute(element, @"_Name")) copy] ?: @"";
	}
	return self;
}

- (instancetype)initWithModel:(ORMModel *)model
{
	if ((self = [super init])) {
		_model = model;
		_identifier = [ORMNewId() copy];
		_name = @"";
	}
	return self;
}

- (void)reset
{
	_definitionText = nil;
	_noteText = nil;
	[self forgetDerivedValues];
}

- (void)forgetDerivedValues
{
}

- (void)resetWithElement:(NSXMLElement *)element model:(ORMModel *)model
{
	[self reset];
	_element = element;
	_model = model;
	_identifier = [ORMAttribute(element, @"id") copy];
	_name = [(ORMAttribute(element, @"Name") ?: ORMAttribute(element, @"_Name")) copy] ?: @"";
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@ %@>", NSStringFromClass([self class]), self.identifier, self.name];
}

@end

#pragma mark Object types

/* Longer names first: one name that is the start of another (Person,
 * PersonName) is tried after it. */
static NSInteger
ORMLongerFirst(NSString *a, NSString *b, void *context)
{
	(void)context;
	return [a length] > [b length] ? NSOrderedAscending : [a length] < [b length] ? NSOrderedDescending : NSOrderedSame;
}

@implementation ORMObjectType

- (void)reset
{
	[super reset];
	_kind = ORMEntityType;
	_defaultValue = nil;
	_isIndependent = _isExternal = _isPersonal = _isImplied = _isImplicitBooleanValue = NO;
	_playedRoles = nil;
	_preferredIdentifier = nil;
	_nestedFactType = nil;
	_referenceMode = nil;
	_referenceModeKind = ORMReferenceModeNone;
	_referenceModeValueType = nil;
	_referenceModeFactType = nil;
	_referenceModeRole = nil;
	_dataType = nil;
	_dataTypeLength = _dataTypeScale = 0;
	_valueConstraint = nil;
	_supertypes = _subtypes = nil;
	_supertypeFacts = nil;
	_ownValueConstraint = nil;
	_savedReferenceMode = nil;
	_objectificationId = nil;
}

- (void)forgetDerivedValues
{
	[super forgetDerivedValues];
	_family = nil;
	_familyNames = nil;
	_playedRoles = nil;
	_supertypes = _subtypes = nil;
	_supertypeFacts = nil;
	_referenceMode = nil;
	_referenceModeKind = ORMReferenceModeNone;
	_referenceModeValueType = nil;
	_referenceModeFactType = nil;
	_referenceModeRole = nil;
	_valueConstraint = nil;
}

- (BOOL)isCompatibleWith:(ORMObjectType *)other
{
	return other != nil && (other == self || [self isSubtypeOf:other] || [other isSubtypeOf:self]);
}


- (ORMObjectType *)valueType
{
	return self.kind == ORMValueType ? self : self.referenceModeValueType;
}

- (ORMObjectType *)identifiedType
{
	ORMObjectType *type = self;
	while (type.kind != ORMValueType && type.preferredIdentifier == nil && [type.supertypes count] > 0) {
		type = [type identifyingSupertype];
	}
	return type;
}

- (ORMObjectType *)identifyingSupertype
{
	ORMObjectType *chosen = nil;
	for (ORMFactType *fact in self.supertypeFacts) {
		ORMObjectType *supertype = [fact supertype];
		if (supertype != nil && (chosen == nil || fact.providesPreferredIdentifier)) {
			chosen = supertype;
		}
	}
	return chosen ?: [self.supertypes firstObject];
}

- (BOOL)isEntity
{
	return self.kind != ORMValueType;
}

- (NSString *)displayName
{
	NSString *name = self.name;
	if (self.referenceMode == nil) {
		return name;
	}
	switch (self.referenceModeKind) {
	case ORMReferenceModePopular:
		return [NSString stringWithFormat:@"%@(.%@)", name, self.referenceMode];
	case ORMReferenceModeUnitBased:
		return [NSString stringWithFormat:@"%@(%@:)", name, self.referenceMode];
	case ORMReferenceModeGeneral:
		return [NSString stringWithFormat:@"%@(%@)", name, self.referenceMode];
	case ORMReferenceModeNone:
		break;
	}
	return name;
}

- (BOOL)isSubtypeOf:(ORMObjectType *)supertype
{
	return [[self allSupertypes] indexOfObjectIdenticalTo:supertype] != NSNotFound;
}

- (NSArray<ORMObjectType *> *)allSupertypes
{
	NSMutableArray *found = [NSMutableArray array];
	NSMutableArray *pending = [self.supertypes mutableCopy];
	while ([pending count] > 0) {
		ORMObjectType *next = [pending firstObject];
		[pending removeObjectAtIndex:0];
		if ([found indexOfObjectIdenticalTo:next] != NSNotFound || next == self) {
			continue;
		}
		[found addObject:next];
		[pending addObjectsFromArray:next.supertypes];
	}
	return found;
}

@end

#pragma mark Fact types

@implementation ORMFactType
{
	/* The derived name, and what it was worked out from: worked out again
	 * only when that changes, -[ORMModel derive] asking after every edit. */
	NSString *_derivedName;
	NSArray *_derivedNameKey;
}

- (void)reset
{
	[super reset];
	_kind = ORMFactTypeOrdinary;
	_roles = nil;
	_readingOrders = nil;
	_internalConstraints = nil;
	_objectifyingType = nil;
	_impliedByFactType = nil;
	_linkFactTypes = nil;
	_isDerived = _providesPreferredIdentifier = NO;
	_preferredIdentificationPath = nil;
	_saysProvidesPreferredIdentifier = NO;
	_explicitName = nil;
	_savedDerivedName = nil;
}

- (void)forgetDerivedValues
{
	[super forgetDerivedValues];
	_internalConstraints = nil;
	_objectifyingType = nil;
	_linkFactTypes = nil;
	_providesPreferredIdentifier = NO;
}

- (BOOL)isLinkFactType
{
	for (ORMRole *role in self.roles) {
		if (role.proxiedRole != nil) {
			return YES;
		}
	}
	return NO;
}

- (ORMObjectType *)subtype
{
	return self.kind == ORMFactTypeSubtype && [self.roles count] == 2 ? [[self.roles firstObject] player] : nil;
}

- (ORMObjectType *)supertype
{
	return self.kind == ORMFactTypeSubtype && [self.roles count] == 2 ? [[self.roles lastObject] player] : nil;
}

- (NSString *)displayText
{
	return [[self primaryReading] expandedText] ?: self.name ?: @"";
}

- (NSArray<ORMRole *> *)visibleRoles
{
	NSMutableArray *roles = [NSMutableArray array];
	for (ORMRole *role in self.roles) {
		if (!role.player.isImplicitBooleanValue) {
			[roles addObject:role];
		}
	}
	return roles;
}

- (NSUInteger)arity
{
	return [[self visibleRoles] count];
}

- (BOOL)isUnary
{
	return [self arity] == 1 && self.kind == ORMFactTypeOrdinary;
}

- (BOOL)isBinary
{
	return [self arity] == 2;
}

- (ORMRole *)implicitRole
{
	for (ORMRole *role in self.roles) {
		if (role.player.isImplicitBooleanValue) {
			return role;
		}
	}
	return nil;
}

- (ORMReading *)primaryReading
{
	for (ORMReadingOrder *order in self.readingOrders) {
		if ([order.readings count] > 0) {
			return [order.readings firstObject];
		}
	}
	return nil;
}

- (ORMReading *)readingFromRole:(ORMRole *)role
{
	ORMReadingOrder *order = role != nil ? [self readingOrderStartingWithRole:role] : nil;
	return [order.readings firstObject] ?: [self primaryReading];
}

- (ORMReadingOrder *)readingOrderStartingWithRole:(ORMRole *)role
{
	for (ORMReadingOrder *order in self.readingOrders) {
		if ([order.roles firstObject] == role && [order.readings count] > 0) {
			return order;
		}
	}
	return nil;
}

- (ORMReadingOrder *)readingOrderForRoles:(NSArray<ORMRole *> *)roles
{
	for (ORMReadingOrder *order in self.readingOrders) {
		if ([order.roles isEqualToArray:roles] && [order.readings count] > 0) {
			return order;
		}
	}
	return nil;
}

- (NSArray<ORMConstraint *> *)uniquenessConstraints
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMConstraint *constraint in self.internalConstraints) {
		if (constraint.kind == ORMUniquenessConstraint) {
			[found addObject:constraint];
		}
	}
	return found;
}

- (BOOL)hasUniquenessOverRoles:(NSArray<ORMRole *> *)roles
{
	NSSet *wanted = [NSSet setWithArray:roles];
	for (ORMConstraint *constraint in [self uniquenessConstraints]) {
		if ([[NSSet setWithArray:[constraint allRoles]] isEqualToSet:wanted]) {
			return YES;
		}
	}
	return NO;
}

/* "Person_id" to "PersonId": each word capitalized, run together. */
static NSString *
ORMCapitalizedWords(NSString *text)
{
	NSMutableString *out = [NSMutableString string];
	for (NSString *word in [text componentsSeparatedByCharactersInSet:ORMNonAlphanumericCharacters()]) {
		if ([word length] > 0) {
			[out appendString:[[word substringToIndex:1] uppercaseString]];
			[out appendString:[word substringFromIndex:1]];
		}
	}
	return out;
}

/* "Person was born in Country" to "PersonWasBornInCountry": the reading's
 * own words capitalized and run together, the object type names in their
 * own case without punctuation (NORMA writes "WeightHaskgValue" and
 * "ProductHasProductId"). */
/* What the derived name is worked out from: the kind, the objectifying
 * type's name, the subtype's and supertype's, the primary reading and its
 * players', the visible roles' players', and the name the file has. */
- (NSArray *)derivedNameKey
{
	NSNull *none = [NSNull null];
	NSMutableArray *key = [NSMutableArray arrayWithObjects:@(self.kind), self.objectifyingType.name ?: none,
	                                                       self.savedDerivedName ?: none, nil];
	if (self.kind == ORMFactTypeSubtype) {
		[key addObject:[self subtype].name ?: none];
		[key addObject:[self supertype].name ?: none];
	}
	ORMReading *reading = [self primaryReading];
	[key addObject:reading.text ?: none];
	for (ORMRole *role in reading.readingOrder.roles) {
		[key addObject:role.player.name ?: none];
	}
	[key addObject:none];
	for (ORMRole *role in [self visibleRoles]) {
		[key addObject:role.player.name ?: none];
	}
	return key;
}

- (NSString *)derivedName
{
	NSArray *key = [self derivedNameKey];
	if (_derivedName == nil || ![_derivedNameKey isEqualToArray:key]) {
		_derivedName = [self derivedNameWorkedOut];
		_derivedNameKey = key;
	}
	return _derivedName;
}

- (NSString *)derivedNameWorkedOut
{
	/* NORMA has written the object type names three ways: punctuation
	 * taken out ("ProductHasProductId" for Product_Id, "WeightHaskgValue"),
	 * each word capitalized ("EventDateHasYmd", "PersonHasPersonId" for
	 * Person_id), and as they are ("JoinTypeHasJoinType_name"); and the
	 * reading's words with the rest of each lowercased ("IsValuetype" for
	 * "is ValueType"). The one the file has stands while it still fits. */
	NSString *saved = self.savedDerivedName;
	for (NSNumber *style in @[ @1, @2, @3 ]) {
		NSString *variant = [self derivedNameWithPlayers:[style integerValue]];
		if (variant != nil && [saved isEqualToString:variant]) {
			return variant;
		}
	}
	return [self derivedNameWithPlayers:0];
}

- (NSString *)derivedNameWithPlayers:(NSInteger)style
{
	/* An objectified fact type goes by its objectifying type's name. */
	if (self.objectifyingType.name != nil) {
		return self.objectifyingType.name;
	}
	if (self.kind == ORMFactTypeSubtype) {
		ORMObjectType *sub = [self subtype];
		ORMObjectType *sup = [self supertype];
		/* Older NORMA wrote "GirlIsASubtypeOfPerson". */
		NSString *older = [NSString stringWithFormat:@"%@IsASubtypeOf%@", sub.name ?: @"", sup.name ?: @""];
		if ([self.savedDerivedName isEqualToString:older]) {
			return older;
		}
		return [NSString stringWithFormat:@"%@IsSubtypeOf%@", sub.name ?: @"", sup.name ?: @""];
	}
	ORMReading *reading = [self primaryReading];
	NSMutableString *name = [NSMutableString string];
	if (reading == nil) {
		for (ORMRole *role in [self visibleRoles]) {
			[name appendString:role.player.name ?: @""];
		}
		return name;
	}
	NSArray *roles = reading.readingOrder.roles;
	NSCharacterSet *separators = ORMNonAlphanumericCharacters();
	NSScanner *scanner = [NSScanner scannerWithString:reading.text];
	[scanner setCharactersToBeSkipped:nil];
	while (![scanner isAtEnd]) {
		NSString *literal = nil;
		if ([scanner scanUpToString:@"{" intoString:&literal]) {
			for (NSString *word in [literal componentsSeparatedByCharactersInSet:separators]) {
				if ([word length] > 0) {
					[name appendString:[[word substringToIndex:1] uppercaseString]];
					[name appendString:style == 3 ? [[word substringFromIndex:1] lowercaseString] : [word substringFromIndex:1]];
				}
			}
		}
		if ([scanner scanString:@"{" intoString:NULL]) {
			NSInteger index = -1;
			if ([scanner scanInteger:&index] && [scanner scanString:@"}" intoString:NULL] && index >= 0
			    && (NSUInteger)index < [roles count]) {
				NSString *player = [[[roles objectAtIndex:index] player] name] ?: @"";
				player = style != 0 ? player
				                    : [[player componentsSeparatedByCharactersInSet:separators] componentsJoinedByString:@""];
				[name appendString:style == 1 ? ORMCapitalizedWords(player) : player];
			}
		}
	}
	return name;
}

@end

@implementation ORMRole

- (void)reset
{
	[super reset];
	_factType = nil;
	_player = nil;
	_index = 0;
	_isMandatory = _isUnique = _isAlethicMandatory = _isAlethicUnique = NO;
	_valueConstraint = nil;
	_isSubtypeMetaRole = _isSupertypeMetaRole = NO;
	_proxiedRole = nil;
	_proxies = nil;
	_constraints = nil;
	_roleInstances = nil;
}

- (void)forgetDerivedValues
{
	[super forgetDerivedValues];
	_isMandatory = _isUnique = _isAlethicMandatory = _isAlethicUnique = NO;
	_proxies = nil;
	_constraints = nil;
	/* A proxy is played by what plays the role it stands for. */
	if (_proxiedRole != nil) {
		_player = nil;
	}
}

- (ORMRole *)oppositeRole
{
	NSArray *roles = self.factType.roles;
	if ([roles count] != 2) {
		return nil;
	}
	return [roles objectAtIndex:1 - self.index];
}

- (ORMMultiplicity)multiplicity
{
	/* As NORMA reckons it: from the alethic constraints on the other role
	 * of a binary (for a link fact type's proxy, the role it stands for). */
	ORMRole *opposite = [self oppositeRole];
	opposite = opposite.proxiedRole ?: opposite;
	if (opposite == nil || [self.factType isUnary]) {
		return ORMMultiplicityUnspecified;
	}
	BOOL mandatory = NO;
	NSUInteger uniqueness = 0;
	BOOL wide = NO;
	for (ORMConstraint *constraint in opposite.constraints) {
		if (constraint.modality != ORMAlethic) {
			continue;
		}
		if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple) {
			mandatory = YES;
		} else if (constraint.kind == ORMUniquenessConstraint && constraint.isInternal) {
			uniqueness++;
			wide = wide || [[constraint allRoles] count] == 2;
		}
	}
	if (uniqueness > 1) {
		return ORMMultiplicityIndeterminate;
	}
	if (uniqueness == 0) {
		/* Nothing said of the other role: many, if this one is unique. */
		for (ORMConstraint *constraint in self.constraints) {
			if (constraint.kind == ORMUniquenessConstraint && constraint.isInternal && constraint.modality == ORMAlethic) {
				return mandatory ? ORMMultiplicityOneToMany : ORMMultiplicityZeroToMany;
			}
		}
		return ORMMultiplicityUnspecified;
	}
	if (wide) {
		return mandatory ? ORMMultiplicityOneToMany : ORMMultiplicityZeroToMany;
	}
	return mandatory ? ORMMultiplicityExactlyOne : ORMMultiplicityZeroToOne;
}

@end

@implementation ORMReadingOrder

- (void)reset
{
	[super reset];
	_factType = nil;
	_roles = nil;
	_unresolvedRoleIds = nil;
	_readings = nil;
}

@end

@implementation ORMReading

- (void)reset
{
	[super reset];
	_words = nil;
	_parsedText = nil;
	_readingOrder = nil;
	_text = nil;
}

- (BOOL)readsFromFirstRole
{
	ORMReadingText *text = [self parsedText];
	ORMReadingPart *first = [text.parts firstObject];
	return first != nil && [text.frontText length] == 0 && [first.preBoundText length] == 0 && first.roleIndex == 0;
}



- (NSString *)expandedText
{
	NSMutableString *text = [self.text mutableCopy] ?: [NSMutableString string];
	NSArray *roles = self.readingOrder.roles;
	for (NSUInteger i = 0; i < [roles count]; i++) {
		NSString *player = [[[roles objectAtIndex:i] player] name] ?: @"?";
		[text replaceOccurrencesOfString:[NSString stringWithFormat:@"{%lu}", (unsigned long)i] withString:player
		                         options:0 range:NSMakeRange(0, [text length])];
	}
	return text;
}

@end

#pragma mark Constraints

@implementation ORMRoleSequence

- (void)reset
{
	[super reset];
	_roles = nil;
	_roleUseIds = nil;
	_unresolvedRoleIds = nil;
	_hasJoinPath = NO;
}

- (void)setRoles:(NSArray<ORMRole *> *)roles
{
	NSMutableDictionary *uses = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < MIN([_roles count], [_roleUseIds count]); i++) {
		[uses setObject:[_roleUseIds objectAtIndex:i] forKey:[[_roles objectAtIndex:i] identifier] ?: @""];
	}
	NSMutableArray *ids = [NSMutableArray array];
	for (ORMRole *role in roles) {
		[ids addObject:[uses objectForKey:role.identifier ?: @""] ?: ORMNewId()];
	}
	_roles = [roles copy];
	_roleUseIds = ids;
}

- (void)setRoles:(NSArray<ORMRole *> *)roles useIds:(NSArray<NSString *> *)useIds
{
	_roles = [roles copy];
	_roleUseIds = [useIds copy];
}

@end

@implementation ORMConstraint

- (instancetype)initWithModel:(ORMModel *)model
{
	if ((self = [super initWithModel:model])) {
		/* As one is read where the file says none. */
		_minFrequency = 1;
	}
	return self;
}

- (void)reset
{
	[super reset];
	_kind = ORMUniquenessConstraint;
	_modality = ORMAlethic;
	_roleSequences = nil;
	_isInternal = _isSimple = _isImplied = NO;
	_preferredIdentifierFor = nil;
	_exclusiveOrPartner = nil;
	_minFrequency = _maxFrequency = 0;
	_ringType = 0;
	_comparisonOperator = nil;
	_impliedByObjectTypeId = nil;
}

- (NSArray<ORMRole *> *)allRoles
{
	NSMutableArray *roles = [NSMutableArray array];
	for (ORMRoleSequence *sequence in self.roleSequences) {
		for (ORMRole *role in sequence.roles) {
			if ([roles indexOfObjectIdenticalTo:role] == NSNotFound) {
				[roles addObject:role];
			}
		}
	}
	return roles;
}

- (NSArray<ORMFactType *> *)factTypes
{
	NSMutableArray *facts = [NSMutableArray array];
	for (ORMRole *role in [self allRoles]) {
		if (role.factType != nil && [facts indexOfObjectIdenticalTo:role.factType] == NSNotFound) {
			[facts addObject:role.factType];
		}
	}
	return facts;
}

- (BOOL)isExternal
{
	switch (self.kind) {
	case ORMUniquenessConstraint:
		return !self.isInternal;
	case ORMMandatoryConstraint:
		return !self.isSimple;
	default:
		return YES;
	}
}

static NSArray *
ORMRingTypeNames(void)
{
	/* NORMA's RingConstraintType values and what each combines. */
	return @[
		@[ @"Reflexive", @(ORMRingReflexive) ],
		@[ @"Irreflexive", @(ORMRingIrreflexive) ],
		@[ @"Symmetric", @(ORMRingSymmetric) ],
		@[ @"Asymmetric", @(ORMRingAsymmetric) ],
		@[ @"Antisymmetric", @(ORMRingAntisymmetric) ],
		@[ @"Transitive", @(ORMRingTransitive) ],
		@[ @"Intransitive", @(ORMRingIntransitive) ],
		@[ @"StronglyIntransitive", @(ORMRingStronglyIntransitive) ],
		@[ @"Acyclic", @(ORMRingAcyclic) ],
		@[ @"PurelyReflexive", @(ORMRingPurelyReflexive) ],
		@[ @"AcyclicTransitive", @(ORMRingAcyclic | ORMRingTransitive) ],
		@[ @"AcyclicIntransitive", @(ORMRingAcyclic | ORMRingIntransitive) ],
		@[ @"AcyclicStronglyIntransitive", @(ORMRingAcyclic | ORMRingStronglyIntransitive) ],
		@[ @"AsymmetricIntransitive", @(ORMRingAsymmetric | ORMRingIntransitive) ],
		@[ @"AsymmetricStronglyIntransitive", @(ORMRingAsymmetric | ORMRingStronglyIntransitive) ],
		@[ @"SymmetricIrreflexive", @(ORMRingSymmetric | ORMRingIrreflexive) ],
		@[ @"SymmetricIntransitive", @(ORMRingSymmetric | ORMRingIntransitive) ],
		@[ @"SymmetricStronglyIntransitive", @(ORMRingSymmetric | ORMRingStronglyIntransitive) ],
		@[ @"ReflexiveSymmetric", @(ORMRingReflexive | ORMRingSymmetric) ],
		@[ @"ReflexiveAntisymmetric", @(ORMRingReflexive | ORMRingAntisymmetric) ],
		@[ @"ReflexiveTransitive", @(ORMRingReflexive | ORMRingTransitive) ],
		@[ @"ReflexiveTransitiveAntisymmetric", @(ORMRingReflexive | ORMRingTransitive | ORMRingAntisymmetric) ],
		@[ @"SymmetricTransitive", @(ORMRingSymmetric | ORMRingTransitive) ],
		@[ @"TransitiveIrreflexive", @(ORMRingTransitive | ORMRingIrreflexive) ],
		@[ @"TransitiveAsymmetric", @(ORMRingTransitive | ORMRingAsymmetric) ],
		@[ @"TransitiveAntisymmetric", @(ORMRingTransitive | ORMRingAntisymmetric) ],
		@[ @"TransitiveIntransitive", @(ORMRingTransitive | ORMRingIntransitive) ],
		@[ @"TransitiveAsymmetricIntransitive", @(ORMRingTransitive | ORMRingAsymmetric | ORMRingIntransitive) ],
	];
}

+ (NSString *)nameOfRingType:(ORMRingType)type
{
	for (NSArray *pair in ORMRingTypeNames()) {
		if ([[pair objectAtIndex:1] unsignedIntegerValue] == type) {
			return [pair objectAtIndex:0];
		}
	}
	return @"Undefined";
}

+ (ORMRingType)ringTypeNamed:(NSString *)name
{
	for (NSArray *pair in ORMRingTypeNames()) {
		if ([[pair objectAtIndex:0] isEqualToString:name]) {
			return [[pair objectAtIndex:1] unsignedIntegerValue];
		}
	}
	return 0;
}

@end

#pragma mark Values and data types

ORMRangeInclusion
ORMInclusionNamed(NSString *name)
{
	if ([name isEqualToString:@"Open"]) {
		return ORMRangeOpen;
	}
	if ([name isEqualToString:@"Closed"]) {
		return ORMRangeClosed;
	}
	return ORMRangeInclusionNotSet;
}

/* A value as FORML writes it: text quoted, other values bare. Without a
 * data type to go by, a value that reads as a number is a number. */
static NSString *
ORMQuoteValue(NSString *value, BOOL quotes)
{
	if ([value length] == 0) {
		return @"";
	}
	NSScanner *scanner = [NSScanner scannerWithString:value];
	double number;
	if (!quotes || ([scanner scanDouble:&number] && [scanner isAtEnd])) {
		return value;
	}
	return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
}

@implementation ORMValueRange

- (void)reset
{
	[super reset];
	_constraint = nil;
	_minValue = _maxValue = nil;
	_minInclusion = _maxInclusion = 0;
}

- (NSString *)displayText
{
	BOOL quotes = self.constraint == nil || [self.constraint quotesValues];
	NSString *min = ORMQuoteValue(self.minValue, quotes);
	NSString *max = ORMQuoteValue(self.maxValue, quotes);
	if ([self.minValue isEqualToString:self.maxValue]) {
		return min;
	}
	/* Bounds are closed unless a range says otherwise; say so only then. */
	BOOL bracketed = self.minInclusion == ORMRangeOpen || self.maxInclusion == ORMRangeOpen;
	NSString *open = !bracketed ? @"" : (self.minInclusion == ORMRangeOpen ? @"(" : @"[");
	NSString *close = !bracketed ? @"" : (self.maxInclusion == ORMRangeOpen ? @")" : @"]");
	return [NSString stringWithFormat:@"%@%@..%@%@", open, min, max, close];
}

@end

@implementation ORMValueConstraint

- (void)reset
{
	[super reset];
	_ranges = nil;
	_valueType = nil;
}

- (void)forgetDerivedValues
{
	[super forgetDerivedValues];
	_valueType = nil;
}

- (BOOL)quotesValues
{
	switch (self.valueType.dataType.family) {
	case ORMDataTypeNumeric:
	case ORMDataTypeTemporal:
	case ORMDataTypeLogical:
		return NO;
	default:
		return YES;
	}
}

- (NSString *)displayText
{
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMValueRange *range in self.ranges) {
		[parts addObject:[range displayText]];
	}
	return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
}

@end

@implementation ORMDataType

- (void)reset
{
	[super reset];
	_typeName = nil;
}

static NSArray *
ORMDataTypeTable(void)
{
	return @[
		@[ @"UnspecifiedDataType", @"Unspecified" ],
		@[ @"FixedLengthTextDataType", @"Text: Fixed Length" ],
		@[ @"VariableLengthTextDataType", @"Text: Variable Length" ],
		@[ @"LargeLengthTextDataType", @"Text: Large Length" ],
		@[ @"SignedIntegerNumericDataType", @"Numeric: Signed Integer" ],
		@[ @"SignedSmallIntegerNumericDataType", @"Numeric: Signed Small Integer" ],
		@[ @"SignedLargeIntegerNumericDataType", @"Numeric: Signed Large Integer" ],
		@[ @"UnsignedIntegerNumericDataType", @"Numeric: Unsigned Integer" ],
		@[ @"UnsignedTinyIntegerNumericDataType", @"Numeric: Unsigned Tiny Integer" ],
		@[ @"UnsignedSmallIntegerNumericDataType", @"Numeric: Unsigned Small Integer" ],
		@[ @"UnsignedLargeIntegerNumericDataType", @"Numeric: Unsigned Large Integer" ],
		@[ @"AutoCounterNumericDataType", @"Numeric: Auto Counter" ],
		@[ @"FloatingPointNumericDataType", @"Numeric: Floating Point" ],
		@[ @"SinglePrecisionFloatingPointNumericDataType", @"Numeric: Single Precision Floating Point" ],
		@[ @"DoublePrecisionFloatingPointNumericDataType", @"Numeric: Double Precision Floating Point" ],
		@[ @"DecimalNumericDataType", @"Numeric: Decimal" ],
		@[ @"MoneyNumericDataType", @"Numeric: Money" ],
		@[ @"FixedLengthRawDataDataType", @"Raw Data: Fixed Length" ],
		@[ @"VariableLengthRawDataDataType", @"Raw Data: Variable Length" ],
		@[ @"LargeLengthRawDataDataType", @"Raw Data: Large Length" ],
		@[ @"PictureRawDataDataType", @"Raw Data: Picture" ],
		@[ @"OleObjectRawDataDataType", @"Raw Data: OLE Object" ],
		@[ @"AutoTimestampTemporalDataType", @"Temporal: Auto Timestamp" ],
		@[ @"TimeTemporalDataType", @"Temporal: Time" ],
		@[ @"DateTemporalDataType", @"Temporal: Date" ],
		@[ @"DateAndTimeTemporalDataType", @"Temporal: Date & Time" ],
		@[ @"TrueOrFalseLogicalDataType", @"Logical: True or False" ],
		@[ @"YesOrNoLogicalDataType", @"Logical: Yes or No" ],
		@[ @"RowIdOtherDataType", @"Other: Row ID" ],
		@[ @"ObjectIdOtherDataType", @"Other: Object ID" ],
	];
}

+ (NSArray<NSString *> *)allTypeNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (NSArray *row in ORMDataTypeTable()) {
		[names addObject:[row objectAtIndex:0]];
	}
	return names;
}

+ (NSString *)displayNameOfTypeNamed:(NSString *)typeName
{
	for (NSArray *row in ORMDataTypeTable()) {
		if ([[row objectAtIndex:0] isEqualToString:typeName]) {
			return [row objectAtIndex:1];
		}
	}
	return typeName;
}

- (NSString *)displayName
{
	return [ORMDataType displayNameOfTypeNamed:self.typeName];
}

- (ORMDataTypeFamily)family
{
	NSString *type = self.typeName;
	if ([type hasSuffix:@"TextDataType"]) {
		return ORMDataTypeText;
	}
	if ([type hasSuffix:@"NumericDataType"]) {
		return ORMDataTypeNumeric;
	}
	if ([type hasSuffix:@"TemporalDataType"]) {
		return ORMDataTypeTemporal;
	}
	if ([type hasSuffix:@"LogicalDataType"]) {
		return ORMDataTypeLogical;
	}
	if ([type hasSuffix:@"RawDataDataType"]) {
		return ORMDataTypeRawData;
	}
	if ([type hasSuffix:@"OtherDataType"]) {
		return ORMDataTypeOther;
	}
	return ORMDataTypeUnspecified;
}

@end

@implementation ORMModelNote

- (void)reset
{
	[super reset];
	_text = nil;
	_referencedElements = nil;
}

@end

#pragma mark The model

/* NORMA's intrinsic unit-based reference modes; custom ones are read from
 * the model. A value type named kgValue identifies by kg. */
static NSArray *
ORMUnitReferenceModes(void)
{
	return @[ @"AUD", @"CE", @"cm", @"Celsius", @"EUR", @"Fahrenheit", @"ft", @"g", @"kg", @"km", @"kmph", @"L",
	          @"m", @"mile", @"mm", @"mph", @"USD", @"Year", @"day", @"hr", @"min", @"sec", @"in", @"lb" ];
}

NSArray *
ORMWithout(NSArray *array, id object)
{
	NSUInteger index = [array indexOfObjectIdenticalTo:object];
	if (index == NSNotFound) {
		return array;
	}
	NSMutableArray *rest = [array mutableCopy];
	[rest removeObjectAtIndex:index];
	return rest;
}

@implementation ORMModel
{
	NSMutableDictionary<NSString *, id> *_elements;
	/* Object types by name, the first of a name: made when first asked. */
	NSMutableDictionary<NSString *, ORMObjectType *> *_typesByName;
	/* Diagrams are read when first asked for: an editor reads the model
	 * after every step of a group, and most steps look at no shape. */
	BOOL _diagramsRead;
	/* While the model is read again: the elements read before, by id, to
	 * be read again in place. Kept until the diagrams are read. */
	NSMutableDictionary<NSString *, ORMElement *> *_reusable;
	/* What the last derive linked, by id, for the next to tell what a
	 * change took apart (-deriveAfterChanging:): each role's player, each
	 * fact type's roles and the fact type it is implied by, each object
	 * type's nested fact type and preferred identifier, each constraint's
	 * roles; and the reference mode formats it went by. nil until the
	 * model is derived in full. */
	NSMutableDictionary<NSString *, ORMObjectType *> *_derivedPlayers;
	NSMutableDictionary<NSString *, NSArray<ORMRole *> *> *_derivedRoles;
	NSMutableDictionary<NSString *, ORMFactType *> *_derivedImpliedBy;
	NSMutableDictionary<NSString *, ORMFactType *> *_derivedNested;
	NSMutableDictionary<NSString *, ORMConstraint *> *_derivedIdentifiers;
	NSMutableDictionary<NSString *, NSArray<ORMRole *> *> *_derivedConstraintRoles;
	NSDictionary *_derivedFormats;
	NSDictionary *_derivedCustomModes;
	/* Where each object type, fact type and constraint is in its list:
	 * made when asked, forgotten when one is added or taken away. */
	NSMapTable *_order;
}

+ (instancetype)modelOfDocument:(NSXMLDocument *)document reason:(NSString **)reason
{
	NSXMLElement *modelElement = ORMModelElementOfDocument(document);
	if (modelElement == nil) {
		if (reason != NULL) {
			*reason = @"The file has no ORM model in it.";
		}
		return nil;
	}
	ORMModel *model = [[self alloc] init];
	[model readDocument:document model:modelElement];
	return model;
}

- (void)dealloc
{
	[self cutLinks];
}

/* The model owns its elements; their links to one another are back
 * links, weak in spirit, but arrays hold strongly: a role holds its
 * constraints, which hold their sequences, which hold the role. Cut when
 * the model goes, or when it is read again, or what is gone outlives it. */
- (void)cutLinks
{
	for (ORMObjectType *type in self.objectTypes) {
		type.playedRoles = nil;
		type.supertypes = nil;
		type.subtypes = nil;
		type.supertypeFacts = nil;
	}
	for (ORMFactType *fact in self.factTypes) {
		fact.internalConstraints = nil;
		fact.linkFactTypes = nil;
		for (ORMRole *role in fact.roles) {
			role.constraints = nil;
			role.proxies = nil;
		}
		for (ORMReadingOrder *order in fact.readingOrders) {
			order.roles = nil;
		}
	}
	for (ORMConstraint *constraint in self.constraints) {
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			sequence.roles = nil;
		}
	}
	for (ORMModelNote *note in self.notes) {
		note.referencedElements = nil;
	}
}

- (id)element:(Class)elementClass for:(NSXMLElement *)xml
{
	NSString *identifier = ORMAttribute(xml, @"id");
	ORMElement *old = identifier != nil ? [_reusable objectForKey:identifier] : nil;
	if (old != nil && [old class] == elementClass) {
		/* Once: a file that gives two elements one id gets two. */
		[_reusable removeObjectForKey:identifier];
		[old resetWithElement:xml model:self];
		return old;
	}
	return [[elementClass alloc] initWithElement:xml model:self];
}

- (void)readDocumentAgain:(NSXMLDocument *)document
{
	NSMutableDictionary *reusable = [NSMutableDictionary dictionaryWithDictionary:_elements];
	/* Shapes not read since the last time are still to be had. */
	for (NSString *identifier in _reusable) {
		if ([reusable objectForKey:identifier] == nil) {
			[reusable setObject:[_reusable objectForKey:identifier] forKey:identifier];
		}
	}
	[self cutLinks];
	_reusable = reusable;
	_typesByName = nil;
	_diagrams = nil;
	_diagramsRead = NO;
	[self readDocument:document model:ORMModelElementOfDocument(document)];
}

- (void)addElement:(ORMElement *)element
{
	[self registerElement:element];
	_typesByName = nil;
	if ([element isKindOfClass:[ORMDataType class]]) {
		_dataTypes = [_dataTypes arrayByAddingObject:(id)element];
	} else if ([element isKindOfClass:[ORMObjectType class]]) {
		_objectTypes = [_objectTypes arrayByAddingObject:(id)element];
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		_factTypes = [_factTypes arrayByAddingObject:(id)element];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		_constraints = [_constraints arrayByAddingObject:(id)element];
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		_notes = [_notes arrayByAddingObject:(id)element];
	} else if ([element isKindOfClass:[ORMCoreDataMapping class]]) {
		self.coreDataMappings = [self.coreDataMappings ?: @[] arrayByAddingObject:element];
	} else if ([element isKindOfClass:[ORMStoredQuery class]]) {
		self.storedQueries = [self.storedQueries ?: @[] arrayByAddingObject:element];
	}
	/* Last in its list. */
	for (NSArray *list in _order != nil ? @[ _objectTypes ?: @[], _factTypes ?: @[], _constraints ?: @[] ] : @[]) {
		if ([list lastObject] == element) {
			[_order setObject:@([list count] - 1) forKey:element];
		}
	}
}

- (void)removeElement:(ORMElement *)element
{
	if (element == nil) {
		return;
	}
	if ([element isKindOfClass:[ORMValueConstraint class]]) {
		for (ORMValueRange *range in [(ORMValueConstraint *)element ranges]) {
			[self removeElement:range];
		}
	} else if ([element isKindOfClass:[ORMObjectType class]]) {
		[self removeElement:[(ORMObjectType *)element ownValueConstraint]];
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		for (ORMRole *role in [(ORMFactType *)element roles]) {
			[self removeElement:role.valueConstraint];
			[self removeElement:role];
		}
		for (ORMReadingOrder *order in [(ORMFactType *)element readingOrders]) {
			for (ORMReading *reading in order.readings) {
				[self removeElement:reading];
			}
			[self removeElement:order];
		}
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		for (ORMRoleSequence *sequence in [(ORMConstraint *)element roleSequences]) {
			[self removeElement:sequence];
		}
	}
	if (element.identifier != nil && [_elements objectForKey:element.identifier] == element) {
		[_elements removeObjectForKey:element.identifier];
	}
	if (element.name != nil) {
		[self.removedNames addObject:element.name];
	}
	_typesByName = nil;
	_order = nil;
	_dataTypes = ORMWithout(_dataTypes, element);
	_objectTypes = ORMWithout(_objectTypes, element);
	_factTypes = ORMWithout(_factTypes, element);
	_constraints = ORMWithout(_constraints, element);
	_notes = ORMWithout(_notes, element);
	self.coreDataMappings = ORMWithout(self.coreDataMappings, element);
	self.storedQueries = ORMWithout(self.storedQueries, element);
}

- (void)registerElement:(ORMElement *)element
{
	if (element.identifier != nil) {
		[_elements setObject:element forKey:element.identifier];
	}
}

- (NSDictionary *)elementsById
{
	return _elements;
}

- (ORMCoreDataMapping *)coreDataMappingWithId:(NSString *)identifier
{
	for (ORMCoreDataMapping *mapping in self.coreDataMappings) {
		if ([mapping.identifier isEqualToString:identifier]) {
			return mapping;
		}
	}
	return nil;
}

- (id)elementWithId:(NSString *)identifier
{
	if (identifier == nil) {
		return nil;
	}
	id element = [_elements objectForKey:identifier];
	if (element == nil && !_diagramsRead) {
		/* A diagram or a shape, perhaps. */
		[self readDiagrams];
		element = [_elements objectForKey:identifier];
	}
	return element;
}

@synthesize diagrams = _diagrams;

- (BOOL)diagramsRead
{
	return _diagramsRead;
}

- (void)addDiagram:(ORMDiagram *)diagram
{
	[self diagrams];
	_diagrams = [_diagrams arrayByAddingObject:diagram];
	[self registerElement:diagram];
}

- (NSArray<ORMDiagram *> *)diagrams
{
	if (!_diagramsRead) {
		[self readDiagrams];
	}
	return _diagrams;
}

- (ORMObjectType *)objectTypeNamed:(NSString *)name
{
	if (_typesByName == nil) {
		_typesByName = [NSMutableDictionary dictionary];
		for (ORMObjectType *type in self.objectTypes) {
			if (type.name != nil && [_typesByName objectForKey:type.name] == nil) {
				[_typesByName setObject:type forKey:type.name];
			}
		}
	}
	return name != nil ? [_typesByName objectForKey:name] : nil;
}

- (NSArray<ORMObjectType *> *)visibleObjectTypes
{
	NSMutableArray *types = [NSMutableArray array];
	for (ORMObjectType *type in self.objectTypes) {
		if (!type.isImplicitBooleanValue) {
			[types addObject:type];
		}
	}
	return types;
}

- (NSArray<ORMFactType *> *)ordinaryFactTypes
{
	NSMutableArray *facts = [NSMutableArray array];
	for (ORMFactType *fact in self.factTypes) {
		if (fact.kind == ORMFactTypeOrdinary) {
			[facts addObject:fact];
		}
	}
	return facts;
}

- (NSArray<ORMConstraint *> *)externalConstraints
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMConstraint *constraint in self.constraints) {
		if ([constraint isExternal] && !constraint.isImplied) {
			[found addObject:constraint];
		}
	}
	return found;
}

#pragma mark Reading

- (void)readDocument:(NSXMLDocument *)document model:(NSXMLElement *)modelElement
{
	_elements = [NSMutableDictionary dictionary];
	_order = nil;
	_derivedPlayers = nil;
	_document = document;
	_modelElement = modelElement;
	self.readingsHaveExpandedData = NO;
	_identifier = [ORMAttribute(modelElement, @"id") copy];
	_name = [ORMAttribute(modelElement, @"Name") copy] ?: @"";
	self.extras = nil;

	[self readDataTypes];
	[self readObjectTypes];
	[self readFactTypes];
	[self readConstraints];
	[self readNotes];
	[self readReferences];
	[self readReferenceModeKinds];
	[self derive];
	self.extras = [NSMutableDictionary dictionary];
	[self readPathsAndPopulations];
	[self readCoreDataMappings];
	[self readQueries];
}

- (void)readDataTypes
{
	NSMutableArray *types = [NSMutableArray array];
	for (NSXMLNode *node in [ORMChild(_modelElement, CORE, @"DataTypes") children]) {
		if ([node kind] != NSXMLElementKind) {
			continue;
		}
		ORMDataType *type = [self element:[ORMDataType class] for:(NSXMLElement *)node];
		type.typeName = [node localName];
		[types addObject:type];
		[self registerElement:type];
	}
	_dataTypes = types;
}

- (ORMValueConstraint *)valueConstraintIn:(NSXMLElement *)restriction
{
	NSXMLElement *element = nil;
	for (NSXMLNode *node in [restriction children]) {
		if ([node kind] == NSXMLElementKind && [[node URI] isEqualToString:CORE]) {
			element = (NSXMLElement *)node;
			break;
		}
	}
	if (element == nil) {
		return nil;
	}
	ORMValueConstraint *constraint = [self element:[ORMValueConstraint class] for:element];
	NSMutableArray *ranges = [NSMutableArray array];
	for (NSXMLElement *rangeElement in ORMGrandchildren(element, CORE, @"ValueRanges", CORE, @"ValueRange")) {
		ORMValueRange *range = [self element:[ORMValueRange class] for:rangeElement];
		range.minValue = ORMAttribute(rangeElement, @"MinValue") ?: @"";
		range.maxValue = ORMAttribute(rangeElement, @"MaxValue") ?: @"";
		range.minInclusion = ORMInclusionNamed(ORMAttribute(rangeElement, @"MinInclusion"));
		range.maxInclusion = ORMInclusionNamed(ORMAttribute(rangeElement, @"MaxInclusion"));
		range.constraint = constraint;
		[ranges addObject:range];
		[self registerElement:range];
	}
	constraint.ranges = ranges;
	[self registerElement:constraint];
	return constraint;
}

- (void)readObjectTypes
{
	NSMutableArray *types = [NSMutableArray array];
	for (NSXMLNode *node in [ORMChild(_modelElement, CORE, @"Objects") children]) {
		if ([node kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *element = (NSXMLElement *)node;
		NSString *local = [element localName];
		ORMObjectType *type = [self element:[ORMObjectType class] for:element];
		type.defaultValue = ORMChildText(element, CORE, @"DefaultValue");
		if ([local isEqualToString:@"EntityType"]) {
			type.kind = ORMEntityType;
		} else if ([local isEqualToString:@"ValueType"]) {
			type.kind = ORMValueType;
		} else if ([local isEqualToString:@"ObjectifiedType"]) {
			type.kind = ORMObjectifiedType;
		} else {
			continue;
		}
		type.isIndependent = ORMBoolAttribute(element, @"IsIndependent", NO);
		type.isExternal = ORMBoolAttribute(element, @"IsExternal", NO);
		type.isPersonal = ORMBoolAttribute(element, @"IsPersonal", NO);
		type.isImplied = ORMBoolAttribute(ORMChild(element, CORE, @"NestedPredicate"), @"IsImplied", NO);
		type.isImplicitBooleanValue = ORMBoolAttribute(element, @"IsImplicitBooleanValue", NO);
		type.definitionText = ORMNestedText(element, @"Definitions", @"Definition");
		type.noteText = ORMNestedText(element, @"Notes", @"Note");
		NSXMLElement *dataType = ORMChild(element, CORE, @"ConceptualDataType");
		if (dataType != nil) {
			type.dataTypeLength = [ORMAttribute(dataType, @"Length") integerValue];
			type.dataTypeScale = [ORMAttribute(dataType, @"Scale") integerValue];
		}
		type.ownValueConstraint = [self valueConstraintIn:ORMChild(element, CORE, @"ValueRestriction")];
		type.savedReferenceMode = ORMAttribute(element, @"_ReferenceMode");
		[types addObject:type];
		[self registerElement:type];
	}
	_objectTypes = types;
}

- (ORMRole *)readRole:(NSXMLElement *)element of:(ORMFactType *)fact index:(NSUInteger)index
{
	ORMRole *role = [self element:[ORMRole class] for:element];
	role.factType = fact;
	role.index = index;
	role.isSubtypeMetaRole = [[element localName] isEqualToString:@"SubtypeMetaRole"];
	role.isSupertypeMetaRole = [[element localName] isEqualToString:@"SupertypeMetaRole"];
	role.valueConstraint = [self valueConstraintIn:ORMChild(element, CORE, @"ValueRestriction")];
	[self registerElement:role];
	return role;
}

- (void)readFactTypes
{
	NSMutableArray *facts = [NSMutableArray array];
	for (NSXMLNode *node in [ORMChild(_modelElement, CORE, @"Facts") children]) {
		if ([node kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *element = (NSXMLElement *)node;
		NSString *local = [element localName];
		ORMFactType *fact = [self element:[ORMFactType class] for:element];
		if ([local isEqualToString:@"Fact"]) {
			fact.kind = ORMFactTypeOrdinary;
		} else if ([local isEqualToString:@"SubtypeFact"]) {
			fact.kind = ORMFactTypeSubtype;
		} else if ([local isEqualToString:@"ImpliedFact"]) {
			fact.kind = ORMFactTypeImplied;
		} else {
			continue;
		}
		NSMutableArray *roles = [NSMutableArray array];
		for (NSXMLNode *roleNode in [ORMChild(element, CORE, @"FactRoles") children]) {
			if ([roleNode kind] != NSXMLElementKind) {
				continue;
			}
			[roles addObject:[self readRole:(NSXMLElement *)roleNode of:fact index:[roles count]]];
		}
		fact.roles = roles;
		fact.definitionText = ORMNestedText(element, @"Definitions", @"Definition");
		fact.noteText = ORMNestedText(element, @"Notes", @"Note");
		/* Derived when the rule says how, formally or in words. */
		NSXMLElement *rule = ORMChild(element, CORE, @"DerivationRule");
		fact.isDerived = ORMChild(rule, CORE, @"FactTypeDerivationPath") != nil
			|| ORMChild(rule, CORE, @"DerivationExpression") != nil;
		if (ORMAttribute(element, @"PreferredIdentificationPath") != nil) {
			fact.preferredIdentificationPath = @(ORMBoolAttribute(element, @"PreferredIdentificationPath", NO));
		}
		fact.saysProvidesPreferredIdentifier = ORMBoolAttribute(element, @"ProvidesPreferredIdentifier", NO);
		fact.explicitName = ORMAttribute(element, @"Name");
		fact.savedDerivedName = ORMAttribute(element, @"_Name");
		[facts addObject:fact];
		[self registerElement:fact];
	}
	_factTypes = facts;

	/* Reading orders after every role is known: a reading order names
	 * its roles by id. */
	for (ORMFactType *fact in facts) {
		NSMutableArray *orders = [NSMutableArray array];
		for (NSXMLElement *orderElement in ORMGrandchildren(fact.element, CORE, @"ReadingOrders", CORE,
		                                                    @"ReadingOrder")) {
			ORMReadingOrder *order = [self element:[ORMReadingOrder class] for:orderElement];
			order.factType = fact;
			NSArray *unresolved = nil;
			order.roles = [self rolesIn:ORMChild(orderElement, CORE, @"RoleSequence") unresolved:&unresolved];
			order.unresolvedRoleIds = unresolved;
			NSMutableArray *readings = [NSMutableArray array];
			for (NSXMLElement *readingElement in ORMGrandchildren(orderElement, CORE, @"Readings", CORE,
			                                                      @"Reading")) {
				ORMReading *reading = [self element:[ORMReading class] for:readingElement];
				reading.readingOrder = order;
				reading.text = ORMChildText(readingElement, CORE, @"Data") ?: @"";
				if (ORMChild(readingElement, CORE, @"ExpandedData") != nil) {
					self.readingsHaveExpandedData = YES;
				}
				[readings addObject:reading];
				[self registerElement:reading];
			}
			order.readings = readings;
			[orders addObject:order];
			[self registerElement:order];
		}
		fact.readingOrders = orders;
	}
}

/* The roles a sequence's children point at: <orm:Role ref=.../>, whose
 * own id, when it has one, names the constraint's use of the role. A
 * role that is not (or no longer) in the model is skipped, its ref put
 * aside. */
- (NSArray<ORMRole *> *)rolesIn:(NSXMLElement *)sequence unresolved:(NSArray **)unresolved
{
	return [self rolesIn:sequence unresolved:unresolved useIds:NULL];
}

/* The same, with each role's use's id ("" for none). */
- (NSArray<ORMRole *> *)rolesIn:(NSXMLElement *)sequence unresolved:(NSArray **)unresolved useIds:(NSArray **)useIds
{
	NSMutableArray *roles = [NSMutableArray array];
	NSMutableArray *refs = [NSMutableArray array];
	NSMutableArray *ids = [NSMutableArray array];
	for (NSXMLElement *child in ORMChildren(sequence, CORE, @"Role")) {
		id role = [self elementWithId:ORMRef(child)];
		if ([role isKindOfClass:[ORMRole class]]) {
			[roles addObject:role];
			[ids addObject:ORMAttribute(child, @"id") ?: @""];
		} else {
			[refs addObject:ORMRef(child) ?: @""];
		}
	}
	*unresolved = refs;
	if (useIds != NULL) {
		*useIds = ids;
	}
	return roles;
}

- (ORMRoleSequence *)readSequence:(NSXMLElement *)element
{
	ORMRoleSequence *sequence = [self element:[ORMRoleSequence class] for:element];
	NSArray *unresolved = nil;
	NSArray *useIds = nil;
	NSArray *roles = [self rolesIn:element unresolved:&unresolved useIds:&useIds];
	[sequence setRoles:roles useIds:useIds];
	sequence.unresolvedRoleIds = unresolved;
	sequence.hasJoinPath = ORMChild(element, CORE, @"JoinRule") != nil || ORMChild(element, CORE, @"JoinPath") != nil;
	[self registerElement:sequence];
	return sequence;
}

- (void)readConstraints
{
	NSDictionary *kinds = @{ @"UniquenessConstraint": @(ORMUniquenessConstraint),
	                         @"MandatoryConstraint": @(ORMMandatoryConstraint),
	                         @"FrequencyConstraint": @(ORMFrequencyConstraint),
	                         @"RingConstraint": @(ORMRingConstraint),
	                         @"SubsetConstraint": @(ORMSubsetConstraint),
	                         @"EqualityConstraint": @(ORMEqualityConstraint),
	                         @"ExclusionConstraint": @(ORMExclusionConstraint),
	                         @"ValueComparisonConstraint": @(ORMValueComparisonConstraint) };
	NSMutableArray *constraints = [NSMutableArray array];
	for (NSXMLNode *node in [ORMChild(_modelElement, CORE, @"Constraints") children]) {
		if ([node kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *element = (NSXMLElement *)node;
		NSNumber *kind = [kinds objectForKey:[element localName]];
		if (kind == nil) {
			continue;
		}
		ORMConstraint *constraint = [self element:[ORMConstraint class] for:element];
		constraint.kind = [kind integerValue];
		constraint.modality = [ORMAttribute(element, @"Modality") isEqualToString:@"Deontic"] ? ORMDeontic
		                                                                                     : ORMAlethic;
		NSMutableArray *sequences = [NSMutableArray array];
		NSXMLElement *single = ORMChild(element, CORE, @"RoleSequence");
		if (single != nil) {
			[sequences addObject:[self readSequence:single]];
		}
		for (NSXMLElement *sequence in ORMGrandchildren(element, CORE, @"RoleSequences", CORE, @"RoleSequence")) {
			[sequences addObject:[self readSequence:sequence]];
		}
		constraint.roleSequences = sequences;
		constraint.isInternal = ORMBoolAttribute(element, @"IsInternal", NO);
		constraint.isSimple = ORMBoolAttribute(element, @"IsSimple", NO);
		constraint.isImplied = ORMBoolAttribute(element, @"IsImplied", NO);
		constraint.minFrequency = MAX((NSInteger)1, [ORMAttribute(element, @"MinFrequency") integerValue]);
		constraint.maxFrequency = MAX((NSInteger)0, [ORMAttribute(element, @"MaxFrequency") integerValue]);
		constraint.ringType = [ORMConstraint ringTypeNamed:ORMAttribute(element, @"Type")];
		constraint.comparisonOperator = ORMAttribute(element, @"Operator");
		constraint.impliedByObjectTypeId = ORMRef(ORMChild(element, CORE, @"ImpliedByObjectType"));
		[constraints addObject:constraint];
		[self registerElement:constraint];
	}
	_constraints = constraints;

	for (ORMConstraint *constraint in constraints) {
		NSXMLElement *partner = ORMChild(constraint.element, CORE, @"ExclusiveOrExclusionConstraint")
			?: ORMChild(constraint.element, CORE, @"ExclusiveOrMandatoryConstraint");
		constraint.exclusiveOrPartner = [self elementWithId:ORMRef(partner)];
		NSXMLElement *identified = ORMChild(constraint.element, CORE, @"PreferredIdentifierFor");
		constraint.preferredIdentifierFor = [self elementWithId:ORMRef(identified)];
	}
}

- (void)readNotes
{
	NSMutableArray *notes = [NSMutableArray array];
	for (NSXMLElement *element in ORMGrandchildren(_modelElement, CORE, @"ModelNotes", CORE, @"ModelNote")) {
		ORMModelNote *note = [self element:[ORMModelNote class] for:element];
		note.text = ORMChildText(element, CORE, @"Text") ?: @"";
		[notes addObject:note];
		[self registerElement:note];
	}
	_notes = notes;
	for (ORMModelNote *note in notes) {
		NSMutableArray *referenced = [NSMutableArray array];
		for (NSXMLElement *element in ORMDescendants(note.element, CORE, nil)) {
			id target = [self elementWithId:ORMRef(element)];
			if (target != nil) {
				[referenced addObject:target];
			}
		}
		note.referencedElements = referenced;
	}
}

#pragma mark Linking

/* What each element names of another by id: preferred identifiers,
 * objectifications, data types, players, the roles proxies stand for. */
- (void)readReferences
{
	NSMutableDictionary *objectifications = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in self.objectTypes) {
		NSXMLElement *element = type.element;
		type.preferredIdentifier = [self elementWithId:ORMRef(ORMChild(element, CORE, @"PreferredIdentifier"))];
		NSXMLElement *nested = ORMChild(element, CORE, @"NestedPredicate");
		ORMFactType *fact = [self elementWithId:ORMRef(nested)];
		if ([fact isKindOfClass:[ORMFactType class]]) {
			type.nestedFactType = fact;
			NSString *objectificationId = ORMAttribute(nested, @"id");
			type.objectificationId = objectificationId;
			if (objectificationId != nil) {
				[objectifications setObject:fact forKey:objectificationId];
			}
		}
		type.dataType = [self elementWithId:ORMRef(ORMChild(element, CORE, @"ConceptualDataType"))];
	}
	for (ORMFactType *fact in self.factTypes) {
		NSXMLElement *implied = ORMChild(fact.element, CORE, @"ImpliedByObjectification");
		if (implied != nil) {
			fact.impliedByFactType = [objectifications objectForKey:ORMRef(implied)];
		}
		for (ORMRole *role in fact.roles) {
			/* A link fact type's proxy: <orm:RoleProxy id><orm:Role ref/></orm:RoleProxy>. */
			if ([[role.element localName] isEqualToString:@"RoleProxy"]) {
				id proxied = [self elementWithId:ORMRef(ORMChild(role.element, CORE, @"Role"))];
				role.proxiedRole = [proxied isKindOfClass:[ORMRole class]] ? proxied : nil;
			} else {
				id player = [self elementWithId:ORMRef(ORMChild(role.element, CORE, @"RolePlayer"))];
				role.player = [player isKindOfClass:[ORMObjectType class]] ? player : nil;
			}
		}
	}
}

/* How the model's reference mode kinds name value types, and its custom
 * reference modes. */
- (void)readReferenceModeKinds
{
	/* "{0}_{1}" (Person_id) in files NORMA writes now, "{0} {1}" (Person
	 * Name) in older ones. */
	NSMutableDictionary *formats = [@{ @"Popular": @"{0}_{1}", @"UnitBased": @"{1}Value", @"General": @"{1}" } mutableCopy];
	for (NSXMLElement *kind in ORMGrandchildren(_modelElement, CORE, @"ReferenceModeKinds", CORE, @"ReferenceModeKind")) {
		NSString *type = ORMAttribute(kind, @"ReferenceModeType");
		NSString *format = ORMAttribute(kind, @"FormatString");
		if (type != nil && [format rangeOfString:@"{1}"].location != NSNotFound) {
			[formats setObject:format forKey:type];
		}
	}
	self.referenceModeFormats = formats;
	NSMutableDictionary *customs = [NSMutableDictionary dictionary];
	for (NSXMLElement *custom in ORMGrandchildren(_modelElement, CORE, @"CustomReferenceModes", CORE,
	                                              @"CustomReferenceMode")) {
		NSString *name = ORMAttribute(custom, @"Name");
		NSXMLElement *kindRef = ORMChild(custom, CORE, @"Kind") ?: ORMChild(custom, CORE, @"ReferenceModeKind");
		NSString *type = ORMAttribute(ORMElementWithId(_document, ORMRef(kindRef)), @"ReferenceModeType");
		if (name != nil && type != nil) {
			[customs setObject:type forKey:name];
		}
	}
	self.customReferenceModes = customs;
}

#pragma mark Deriving

- (void)derive
{
	_typesByName = nil;
	for (ORMObjectType *type in self.objectTypes) {
		[type forgetDerivedValues];
		[type.ownValueConstraint forgetDerivedValues];
	}
	for (ORMFactType *fact in self.factTypes) {
		[fact forgetDerivedValues];
		for (ORMRole *role in fact.roles) {
			[role forgetDerivedValues];
			[role.valueConstraint forgetDerivedValues];
		}
	}
	for (ORMCoreDataMapping *mapping in self.coreDataMappings) {
		[mapping forgetDerivedValues];
	}
	[self linkObjectTypes];
	[self linkFactTypes];
	[self deriveFamiliesOf:self.objectTypes];
	for (ORMFactType *fact in self.factTypes) {
		[self deriveReadingsOf:fact];
	}
	[self linkRoles];
	[self deriveReferenceModes];
	[self linkValueConstraints];
	if (self.extras != nil) {
		[self derivePopulations];
	}
	/* What NORMA keeps derived beside the model, as it keeps it. Each
	 * preferred identifier names what it identifies. */
	for (ORMConstraint *constraint in self.constraints) {
		if (constraint.kind == ORMUniquenessConstraint) {
			constraint.preferredIdentifierFor = nil;
		}
	}
	for (ORMObjectType *type in self.objectTypes) {
		if (type.preferredIdentifier.kind == ORMUniquenessConstraint) {
			type.preferredIdentifier.preferredIdentifierFor = type;
		}
	}
	for (ORMObjectType *type in self.objectTypes) {
		if (type.kind == ORMEntityType) {
			type.savedReferenceMode = type.referenceMode ?: @"";
		}
	}
	for (ORMFactType *fact in self.factTypes) {
		if (fact.savedDerivedName != nil || fact.kind == ORMFactTypeOrdinary) {
			fact.savedDerivedName = [fact derivedName];
		}
		fact.name = fact.explicitName ?: fact.savedDerivedName ?: @"";
	}
	_derivedPlayers = [NSMutableDictionary dictionary];
	_derivedRoles = [NSMutableDictionary dictionary];
	_derivedImpliedBy = [NSMutableDictionary dictionary];
	_derivedNested = [NSMutableDictionary dictionary];
	_derivedIdentifiers = [NSMutableDictionary dictionary];
	_derivedConstraintRoles = [NSMutableDictionary dictionary];
	[self rememberFacts:self.factTypes types:self.objectTypes constraints:self.constraints];
}

#pragma mark Derived again after a change

/* What derive linked, for the next derive after a change: what the
 * change took apart is found by it. */
- (void)rememberFacts:(id<NSFastEnumeration>)facts types:(id<NSFastEnumeration>)types
          constraints:(id<NSFastEnumeration>)constraints
{
	for (ORMFactType *fact in facts) {
		if (fact.identifier == nil) {
			continue;
		}
		[_derivedRoles setObject:fact.roles ?: @[] forKey:fact.identifier];
		if (fact.impliedByFactType != nil) {
			[_derivedImpliedBy setObject:fact.impliedByFactType forKey:fact.identifier];
		} else {
			[_derivedImpliedBy removeObjectForKey:fact.identifier];
		}
		for (ORMRole *role in fact.roles) {
			if (role.identifier == nil) {
				continue;
			}
			if (role.player != nil) {
				[_derivedPlayers setObject:role.player forKey:role.identifier];
			} else {
				[_derivedPlayers removeObjectForKey:role.identifier];
			}
		}
	}
	for (ORMObjectType *type in types) {
		if (type.identifier == nil) {
			continue;
		}
		if (type.nestedFactType != nil) {
			[_derivedNested setObject:type.nestedFactType forKey:type.identifier];
		} else {
			[_derivedNested removeObjectForKey:type.identifier];
		}
		if (type.preferredIdentifier != nil) {
			[_derivedIdentifiers setObject:type.preferredIdentifier forKey:type.identifier];
		} else {
			[_derivedIdentifiers removeObjectForKey:type.identifier];
		}
	}
	for (ORMConstraint *constraint in constraints) {
		if (constraint.identifier != nil) {
			[_derivedConstraintRoles setObject:[constraint allRoles] ?: @[] forKey:constraint.identifier];
		}
	}
	_derivedFormats = self.referenceModeFormats;
	_derivedCustomModes = self.customReferenceModes;
}

/* Where an object type, fact type or constraint is in its list; NSNotFound
 * for one that is not in the model. */
- (NSUInteger)orderOf:(ORMElement *)element
{
	if (element == nil) {
		return NSNotFound;
	}
	if (_order == nil) {
		_order = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
		                               valueOptions:NSPointerFunctionsStrongMemory];
		for (NSArray *list in @[ self.objectTypes ?: @[], self.factTypes ?: @[], self.constraints ?: @[] ]) {
			NSUInteger i = 0;
			for (ORMElement *each in list) {
				[_order setObject:@(i++) forKey:each];
			}
		}
	}
	NSNumber *order = [_order objectForKey:element];
	return order != nil ? [order unsignedIntegerValue] : NSNotFound;
}

static NSInteger
ORMByOrder(NSArray *a, NSArray *b, void *context)
{
	(void)context;
	NSComparisonResult first = [[a objectAtIndex:0] compare:[b objectAtIndex:0]];
	return first != NSOrderedSame ? first : [[a objectAtIndex:1] compare:[b objectAtIndex:1]];
}

/* Object types, fact types or constraints still in the model, once each,
 * in the order of their list: the order derive's loops go in. */
- (NSArray *)inModelOrder:(id<NSFastEnumeration>)elements
{
	NSMutableArray *keyed = [NSMutableArray array];
	NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	for (ORMElement *element in elements) {
		NSUInteger order = [self orderOf:element];
		if (order == NSNotFound || [seen containsObject:element]) {
			continue;
		}
		[seen addObject:element];
		[keyed addObject:@[ @(order), @0, element ]];
	}
	[keyed sortUsingFunction:ORMByOrder context:NULL];
	NSMutableArray *sorted = [NSMutableArray array];
	for (NSArray *each in keyed) {
		[sorted addObject:[each lastObject]];
	}
	return sorted;
}

/* Roles still in the model (their fact type's), once each, in fact type
 * and role order. */
- (NSArray<ORMRole *> *)rolesInModelOrder:(id<NSFastEnumeration>)roles
{
	NSMutableArray *keyed = [NSMutableArray array];
	NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	for (ORMRole *role in roles) {
		NSUInteger order = [self orderOf:role.factType];
		NSUInteger index = order != NSNotFound ? [role.factType.roles indexOfObjectIdenticalTo:role] : NSNotFound;
		if (index == NSNotFound || [seen containsObject:role]) {
			continue;
		}
		[seen addObject:role];
		[keyed addObject:@[ @(order), @(index), role ]];
	}
	[keyed sortUsingFunction:ORMByOrder context:NULL];
	NSMutableArray *sorted = [NSMutableArray array];
	for (NSArray *each in keyed) {
		[sorted addObject:[each lastObject]];
	}
	return sorted;
}

static void
ORMAdd(id element, NSHashTable *to)
{
	if (element != nil) {
		[to addObject:element];
	}
}

/* Whether the constraint makes a fact type's internal constraint. */
static BOOL
ORMIsInternalConstraint(ORMConstraint *constraint, ORMFactType *fact)
{
	NSArray *facts = [constraint factTypes];
	return [facts count] == 1 && [facts firstObject] == fact
		&& (constraint.kind == ORMUniquenessConstraint ? constraint.isInternal
	                                                    : (constraint.kind == ORMMandatoryConstraint ? constraint.isSimple : NO));
}

- (void)deriveAfterChanging:(NSArray<ORMElement *> *)touched
{
	if (_derivedPlayers == nil || ![self.referenceModeFormats ?: @{} isEqualToDictionary:_derivedFormats ?: @{}]
	    || ![self.customReferenceModes ?: @{} isEqualToDictionary:_derivedCustomModes ?: @{}]) {
		[self derive];
		return;
	}
	NSHashTable *types = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	NSHashTable *facts = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	NSHashTable *constraints = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	BOOL populations = NO;
	BOOL names = NO;

	/* What the change touched, as what derive works on. */
	for (ORMElement *element in touched) {
		if ([element isKindOfClass:[ORMObjectType class]]) {
			[types addObject:element];
			names = YES;
		} else if ([element isKindOfClass:[ORMFactType class]]) {
			[facts addObject:element];
		} else if ([element isKindOfClass:[ORMRole class]]) {
			ORMAdd([(ORMRole *)element factType], facts);
		} else if ([element isKindOfClass:[ORMReadingOrder class]]) {
			ORMAdd([(ORMReadingOrder *)element factType], facts);
		} else if ([element isKindOfClass:[ORMReading class]]) {
			ORMAdd([[(ORMReading *)element readingOrder] factType], facts);
		} else if ([element isKindOfClass:[ORMConstraint class]]) {
			[constraints addObject:element];
		} else if ([element isKindOfClass:[ORMRoleSequence class]]) {
			for (ORMRole *role in [(ORMRoleSequence *)element roles]) {
				ORMAdd(role.factType, facts);
				for (ORMConstraint *constraint in role.constraints) {
					[constraints addObject:constraint];
				}
			}
		} else if ([element isKindOfClass:[ORMValueConstraint class]]) {
			ORMAdd([(ORMValueConstraint *)element valueType], types);
		} else if ([element isKindOfClass:[ORMValueRange class]]) {
			ORMAdd([[(ORMValueRange *)element constraint] valueType], types);
		} else if ([element isKindOfClass:[ORMInstance class]] || [element isKindOfClass:[ORMRoleInstance class]]
		           || [element isKindOfClass:[ORMFactInstance class]]) {
			populations = YES;
		}
	}
	/* One step out, by the links the last derive made: an object type's
	 * fact types (their names say its name), nested fact type and
	 * identifier; a constraint's fact types, then and now, and what it
	 * identified. */
	for (ORMObjectType *type in [types allObjects]) {
		for (ORMRole *role in type.playedRoles) {
			ORMAdd(role.factType, facts);
		}
		ORMAdd(type.nestedFactType, facts);
		ORMAdd([_derivedNested objectForKey:type.identifier ?: @""], facts);
		ORMAdd(type.preferredIdentifier, constraints);
		ORMAdd([_derivedIdentifiers objectForKey:type.identifier ?: @""], constraints);
	}
	for (ORMConstraint *constraint in [constraints allObjects]) {
		NSArray *was = [_derivedConstraintRoles objectForKey:constraint.identifier ?: @""] ?: @[];
		for (ORMRole *role in [[constraint allRoles] ?: @[] arrayByAddingObjectsFromArray:was]) {
			ORMAdd(role.factType, facts);
		}
		ORMAdd(constraint.preferredIdentifierFor, types);
	}
	/* A fact type's link fact types, and the fact type it links to; the
	 * fact types of its roles' proxies, and of the roles they stand for. */
	for (ORMFactType *fact in [facts allObjects]) {
		ORMAdd(fact.impliedByFactType, facts);
		ORMAdd([_derivedImpliedBy objectForKey:fact.identifier ?: @""], facts);
		for (ORMFactType *link in fact.linkFactTypes) {
			[facts addObject:link];
		}
		NSArray *was = [_derivedRoles objectForKey:fact.identifier ?: @""] ?: @[];
		for (ORMRole *role in [fact.roles ?: @[] arrayByAddingObjectsFromArray:was]) {
			for (ORMRole *proxy in role.proxies) {
				ORMAdd(proxy.factType, facts);
			}
			ORMAdd(role.proxiedRole.factType, facts);
		}
	}
	/* Their players, then and now. */
	for (ORMFactType *fact in facts) {
		NSArray *was = [_derivedRoles objectForKey:fact.identifier ?: @""] ?: @[];
		for (ORMRole *role in [fact.roles ?: @[] arrayByAddingObjectsFromArray:was]) {
			ORMAdd(role.player, types);
			ORMAdd([_derivedPlayers objectForKey:role.identifier ?: @""], types);
			ORMAdd(role.proxiedRole.player, types);
		}
	}

	NSArray<ORMFactType *> *factList = [self inModelOrder:facts];
	NSArray<ORMObjectType *> *typeList = [self inModelOrder:types];
	NSMutableArray<ORMRole *> *roles = [NSMutableArray array];
	for (ORMFactType *fact in factList) {
		[roles addObjectsFromArray:fact.roles];
	}

	/* What the links were, for what they may be now. */
	NSMapTable *wasObjectified = [NSMapTable strongToStrongObjectsMapTable];
	NSMapTable *wasLinks = [NSMapTable strongToStrongObjectsMapTable];
	NSMapTable *wasInternal = [NSMapTable strongToStrongObjectsMapTable];
	for (ORMFactType *fact in factList) {
		if (fact.objectifyingType != nil) {
			[wasObjectified setObject:fact.objectifyingType forKey:fact];
		}
		[wasLinks setObject:fact.linkFactTypes ?: @[] forKey:fact];
		[wasInternal setObject:fact.internalConstraints ?: @[] forKey:fact];
	}
	NSMapTable *wasProxies = [NSMapTable strongToStrongObjectsMapTable];
	NSMapTable *wasConstraints = [NSMapTable strongToStrongObjectsMapTable];
	for (ORMRole *role in roles) {
		[wasProxies setObject:role.proxies ?: @[] forKey:role];
		[wasConstraints setObject:role.constraints ?: @[] forKey:role];
	}
	NSMutableArray *wasFamilies = [NSMutableArray array];
	for (ORMObjectType *type in typeList) {
		[wasFamilies addObjectsFromArray:type.family ?: @[]];
	}
	NSMapTable *wasPlayed = [NSMapTable strongToStrongObjectsMapTable];
	NSMapTable *wasSubtyping = [NSMapTable strongToStrongObjectsMapTable];
	for (ORMObjectType *type in typeList) {
		[wasPlayed setObject:type.playedRoles ?: @[] forKey:type];
		NSMutableArray *subtyping = [NSMutableArray arrayWithArray:type.supertypeFacts ?: @[]];
		for (ORMObjectType *sub in type.subtypes) {
			[subtyping addObjectsFromArray:sub.supertypeFacts ?: @[]];
		}
		[wasSubtyping setObject:subtyping forKey:type];
	}

	/* Forgotten, as derive forgets everything. */
	for (ORMObjectType *type in typeList) {
		[type forgetDerivedValues];
		[type.ownValueConstraint forgetDerivedValues];
	}
	for (ORMFactType *fact in factList) {
		[fact forgetDerivedValues];
	}
	for (ORMRole *role in roles) {
		[role forgetDerivedValues];
		[role.valueConstraint forgetDerivedValues];
	}
	for (ORMCoreDataMapping *mapping in self.coreDataMappings) {
		[mapping forgetDerivedValues];
	}
	if (names) {
		_typesByName = nil;
	}

	/* linkObjectTypes: what objectifies each, the last that does; its
	 * link fact types. */
	for (ORMFactType *fact in factList) {
		NSMutableArray *candidates = [NSMutableArray arrayWithArray:typeList];
		if ([wasObjectified objectForKey:fact] != nil) {
			[candidates addObject:[wasObjectified objectForKey:fact]];
		}
		ORMObjectType *objectifying = nil;
		for (ORMObjectType *type in [self inModelOrder:candidates]) {
			objectifying = type.nestedFactType == fact ? type : objectifying;
		}
		fact.objectifyingType = objectifying;
		NSMutableArray *links = [NSMutableArray array];
		for (ORMFactType *link in [self inModelOrder:[[wasLinks objectForKey:fact] arrayByAddingObjectsFromArray:factList]]) {
			if (link.impliedByFactType == fact) {
				[links addObject:link];
			}
		}
		fact.linkFactTypes = [links count] > 0 ? links : nil;
	}

	/* linkFactTypes: proxies, and what plays a proxy. */
	for (ORMRole *role in roles) {
		NSMutableArray *proxies = [NSMutableArray array];
		for (ORMRole *proxy in [self rolesInModelOrder:[[wasProxies objectForKey:role] arrayByAddingObjectsFromArray:roles]]) {
			if (proxy.proxiedRole == role) {
				[proxies addObject:proxy];
			}
		}
		role.proxies = [proxies count] > 0 ? proxies : nil;
	}
	for (ORMRole *role in roles) {
		if (role.player == nil && role.proxiedRole.player != nil) {
			role.player = role.proxiedRole.player;
		}
	}
	/* The roles each plays, those it plays itself first, then the proxies. */
	for (ORMObjectType *type in typeList) {
		NSArray *candidates = [self rolesInModelOrder:[[wasPlayed objectForKey:type] arrayByAddingObjectsFromArray:roles]];
		NSMutableArray *played = [NSMutableArray array];
		NSMutableArray *proxied = [NSMutableArray array];
		for (ORMRole *role in candidates) {
			if (role.player == type && role.proxiedRole != nil) {
				[proxied addObject:role];
			} else if (role.player == type) {
				[played addObject:role];
			}
		}
		type.playedRoles = [played arrayByAddingObjectsFromArray:proxied];
	}
	/* Internal constraints. */
	NSArray *seeds = [constraints allObjects];
	for (ORMFactType *fact in factList) {
		NSMutableArray *candidates = [NSMutableArray arrayWithArray:[wasInternal objectForKey:fact]];
		[candidates addObjectsFromArray:seeds];
		for (ORMRole *role in fact.roles) {
			[candidates addObjectsFromArray:[wasConstraints objectForKey:role] ?: @[]];
		}
		NSMutableArray *internal = [NSMutableArray array];
		for (ORMConstraint *constraint in [self inModelOrder:candidates]) {
			if (ORMIsInternalConstraint(constraint, fact)) {
				[internal addObject:constraint];
			}
		}
		fact.internalConstraints = internal;
	}
	/* Subtyping. */
	for (ORMObjectType *type in typeList) {
		NSMutableArray *candidates = [NSMutableArray arrayWithArray:[wasSubtyping objectForKey:type]];
		[candidates addObjectsFromArray:factList];
		NSMutableArray *supers = [NSMutableArray array];
		NSMutableArray *subs = [NSMutableArray array];
		NSMutableArray *superFacts = [NSMutableArray array];
		for (ORMFactType *fact in [self inModelOrder:candidates]) {
			if (fact.kind != ORMFactTypeSubtype || [fact.roles count] != 2) {
				continue;
			}
			ORMObjectType *sub = nil;
			ORMObjectType *sup = nil;
			for (ORMRole *role in fact.roles) {
				if (role.isSubtypeMetaRole) {
					sub = role.player;
				} else if (role.isSupertypeMetaRole) {
					sup = role.player;
				}
			}
			if (sub == nil || sup == nil) {
				continue;
			}
			if (sub == type) {
				[supers addObject:sup];
				[superFacts addObject:fact];
			}
			if (sup == type) {
				[subs addObject:sub];
			}
		}
		type.supertypes = supers;
		type.subtypes = subs;
		type.supertypeFacts = superFacts;
	}
	for (ORMFactType *fact in factList) {
		[self deriveProvidesPreferredIdentifierOf:fact];
		[self deriveReadingsOf:fact];
	}
	/* Families: the types' now, and the rest of those they were in. */
	[self deriveFamiliesOf:[typeList arrayByAddingObjectsFromArray:[self inModelOrder:wasFamilies]]];

	/* linkRoles: each role's constraints, and what they make of it. */
	for (ORMRole *role in roles) {
		NSMutableArray *candidates = [NSMutableArray arrayWithArray:[wasConstraints objectForKey:role] ?: @[]];
		[candidates addObjectsFromArray:seeds];
		NSMutableArray *own = [NSMutableArray array];
		for (ORMConstraint *constraint in [self inModelOrder:candidates]) {
			NSArray *all = [constraint allRoles];
			for (ORMRole *each in all) {
				if (each != role) {
					continue;
				}
				[own addObject:constraint];
				if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple && [all count] == 1) {
					role.isMandatory = YES;
					role.isAlethicMandatory |= constraint.modality == ORMAlethic;
				}
				if (constraint.kind == ORMUniquenessConstraint && constraint.isInternal && [all count] == 1) {
					role.isUnique = YES;
					role.isAlethicUnique |= constraint.modality == ORMAlethic;
				}
			}
		}
		role.constraints = own;
	}

	/* Reference modes. */
	for (ORMObjectType *type in typeList) {
		type.valueConstraint = type.ownValueConstraint;
	}
	NSArray *modes = [self referenceModeSets];
	for (ORMObjectType *type in typeList) {
		[self deriveReferenceModeOf:type modes:modes];
	}
	/* linkValueConstraints. */
	for (ORMObjectType *type in typeList) {
		if (type.kind == ORMValueType) {
			type.valueConstraint.valueType = type;
		}
		for (ORMRole *role in type.playedRoles) {
			[role.valueConstraint forgetDerivedValues];
			role.valueConstraint.valueType = [role.player valueType];
		}
	}
	for (ORMRole *role in roles) {
		role.valueConstraint.valueType = [role.player valueType];
	}
	if (self.extras != nil && (populations || [[self.extras objectForKey:@"roleInstances"] count] > 0
	                           || [[self.extras objectForKey:@"factInstanceElements"] count] > 0
	                           || [[self.extras objectForKey:@"instances"] count] > 0)) {
		[self derivePopulations];
	}

	/* What NORMA keeps derived beside the model. */
	NSHashTable *identifiers = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	for (ORMConstraint *constraint in seeds) {
		[identifiers addObject:constraint];
	}
	for (ORMObjectType *type in typeList) {
		ORMAdd(type.preferredIdentifier, identifiers);
	}
	for (ORMConstraint *constraint in identifiers) {
		if (constraint.kind == ORMUniquenessConstraint) {
			constraint.preferredIdentifierFor = nil;
		}
	}
	for (ORMObjectType *type in typeList) {
		if (type.preferredIdentifier.kind == ORMUniquenessConstraint) {
			type.preferredIdentifier.preferredIdentifierFor = type;
		}
		if (type.kind == ORMEntityType) {
			type.savedReferenceMode = type.referenceMode ?: @"";
		}
	}
	for (ORMFactType *fact in factList) {
		if (fact.savedDerivedName != nil || fact.kind == ORMFactTypeOrdinary) {
			fact.savedDerivedName = [fact derivedName];
		}
		fact.name = fact.explicitName ?: fact.savedDerivedName ?: @"";
	}

	/* Remembered for the next change; what is gone forgotten. */
	[self rememberFacts:factList types:typeList constraints:[self inModelOrder:seeds]];
	for (ORMElement *element in touched) {
		if (element.identifier != nil && [_elements objectForKey:element.identifier] != element) {
			[_derivedRoles removeObjectForKey:element.identifier];
			[_derivedImpliedBy removeObjectForKey:element.identifier];
			[_derivedNested removeObjectForKey:element.identifier];
			[_derivedIdentifiers removeObjectForKey:element.identifier];
			[_derivedConstraintRoles removeObjectForKey:element.identifier];
			[_derivedPlayers removeObjectForKey:element.identifier];
		}
	}
}

- (void)linkObjectTypes
{
	for (ORMObjectType *type in self.objectTypes) {
		type.nestedFactType.objectifyingType = type;
	}
	for (ORMFactType *fact in self.factTypes) {
		ORMFactType *objectified = fact.impliedByFactType;
		if (objectified != nil) {
			objectified.linkFactTypes = [(objectified.linkFactTypes ?: @[]) arrayByAddingObject:fact];
		}
	}
}

- (void)linkFactTypes
{
	/* Players, proxies, and each fact type's internal constraints. */
	NSMutableDictionary *played = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			if (role.player != nil) {
				[[self list:played for:role.player.identifier] addObject:role];
			}
			ORMRole *proxied = role.proxiedRole;
			if (proxied != nil) {
				proxied.proxies = [(proxied.proxies ?: @[]) arrayByAddingObject:role];
			}
		}
	}
	/* A proxy is played by what plays the role it stands for, known only
	 * once every fact type's players are. */
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			if (role.player == nil && role.proxiedRole.player != nil) {
				role.player = role.proxiedRole.player;
				[[self list:played for:role.player.identifier] addObject:role];
			}
		}
	}
	for (ORMObjectType *type in self.objectTypes) {
		type.playedRoles = [played objectForKey:type.identifier] ?: @[];
	}

	NSMutableDictionary *internal = [NSMutableDictionary dictionary];
	for (ORMConstraint *constraint in self.constraints) {
		NSArray *facts = [constraint factTypes];
		BOOL isInternal = [facts count] == 1
			&& (constraint.kind == ORMUniquenessConstraint ? constraint.isInternal
			                                                : (constraint.kind == ORMMandatoryConstraint
			                                                       ? constraint.isSimple
			                                                       : NO));
		if (isInternal) {
			[[self list:internal for:[[facts firstObject] identifier]] addObject:constraint];
		}
	}
	for (ORMFactType *fact in self.factTypes) {
		fact.internalConstraints = [internal objectForKey:fact.identifier] ?: @[];
	}

	/* Subtyping. */
	NSMutableDictionary *supers = [NSMutableDictionary dictionary];
	NSMutableDictionary *subs = [NSMutableDictionary dictionary];
	NSMutableDictionary *superFacts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in self.factTypes) {
		if (fact.kind != ORMFactTypeSubtype || [fact.roles count] != 2) {
			continue;
		}
		ORMObjectType *sub = nil;
		ORMObjectType *sup = nil;
		for (ORMRole *role in fact.roles) {
			if (role.isSubtypeMetaRole) {
				sub = role.player;
			} else if (role.isSupertypeMetaRole) {
				sup = role.player;
			}
		}
		if (sub == nil || sup == nil) {
			continue;
		}
		[[self list:supers for:sub.identifier] addObject:sup];
		[[self list:subs for:sup.identifier] addObject:sub];
		[[self list:superFacts for:sub.identifier] addObject:fact];
	}
	for (ORMObjectType *type in self.objectTypes) {
		type.supertypes = [supers objectForKey:type.identifier] ?: @[];
		type.subtypes = [subs objectForKey:type.identifier] ?: @[];
		type.supertypeFacts = [superFacts objectForKey:type.identifier] ?: @[];
	}
	for (ORMFactType *fact in self.factTypes) {
		[self deriveProvidesPreferredIdentifierOf:fact];
	}
}

/* A fact type's readings taken apart: their words, their text parsed. */
- (void)deriveReadingsOf:(ORMFactType *)fact
{
	for (ORMReadingOrder *order in fact.readingOrders) {
		for (ORMReading *reading in order.readings) {
			reading.words = [ORMReadingText wordsOf:reading.text ?: @""];
			reading.parsedText = [ORMReadingText readingTextWithString:reading.text arity:[order.roles count] reason:NULL];
		}
	}
}

/* The families of the object types, from their subtyping: each the types
 * it is related to up and down, in the model's order, and their names,
 * longest first; one family, one list, for all its types. */
- (void)deriveFamiliesOf:(NSArray<ORMObjectType *> *)types
{
	NSHashTable *done = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	for (ORMObjectType *type in types) {
		if ([done containsObject:type]) {
			continue;
		}
		NSHashTable *members = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
		NSMutableArray *pending = [NSMutableArray arrayWithObject:type];
		while ([pending count] > 0) {
			ORMObjectType *each = [pending lastObject];
			[pending removeLastObject];
			if (![members containsObject:each]) {
				[members addObject:each];
				[pending addObjectsFromArray:each.subtypes];
				[pending addObjectsFromArray:each.supertypes];
			}
		}
		NSArray *family = [members count] == 1 ? @[ type ] : [self inModelOrder:members];
		NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
		for (ORMObjectType *each in family) {
			if (each.name != nil) {
				[names addObject:each.name];
			}
		}
		NSArray *sorted = [[names array] sortedArrayUsingFunction:ORMLongerFirst context:NULL];
		for (ORMObjectType *each in family) {
			each.family = family;
			each.familyNames = sorted;
			[done addObject:each];
		}
	}
}

- (void)deriveProvidesPreferredIdentifierOf:(ORMFactType *)fact
{
	fact.providesPreferredIdentifier = [fact.preferredIdentificationPath boolValue] || fact.saysProvidesPreferredIdentifier;
	/* NORMA leaves the attribute out where it is true by default: a
	 * subtype with no identifier of its own is identified through its
	 * (first) supertype. */
	if (fact.kind == ORMFactTypeSubtype && !fact.providesPreferredIdentifier && fact.preferredIdentificationPath == nil) {
		ORMObjectType *sub = [fact subtype];
		if (sub.preferredIdentifier == nil && [sub.supertypeFacts firstObject] == fact) {
			fact.providesPreferredIdentifier = YES;
		}
	}
}

- (NSMutableArray *)list:(NSMutableDictionary *)lists for:(NSString *)key
{
	NSMutableArray *list = [lists objectForKey:key];
	if (list == nil) {
		list = [NSMutableArray array];
		[lists setObject:list forKey:key];
	}
	return list;
}

- (void)linkRoles
{
	NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
	for (ORMConstraint *constraint in self.constraints) {
		for (ORMRole *role in [constraint allRoles]) {
			[[self list:byRole for:role.identifier] addObject:constraint];
			if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple && [[constraint allRoles] count] == 1) {
				role.isMandatory = YES;
				role.isAlethicMandatory |= constraint.modality == ORMAlethic;
			}
			if (constraint.kind == ORMUniquenessConstraint && constraint.isInternal
			    && [[constraint allRoles] count] == 1) {
				role.isUnique = YES;
				role.isAlethicUnique |= constraint.modality == ORMAlethic;
			}
		}
	}
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			role.constraints = [byRole objectForKey:role.identifier] ?: @[];
		}
	}
}

/* The reference mode a value type's name gives under a kind's format,
 * "{0}" the entity type's name and "{1}" the mode; nil when it does not
 * fit or gives nothing. */
static NSString *
ORMReferenceModeIn(NSString *valueName, NSString *format, NSString *entityName)
{
	NSString *pattern = [format stringByReplacingOccurrencesOfString:@"{0}" withString:entityName ?: @""];
	NSRange mode = [pattern rangeOfString:@"{1}"];
	if (mode.location == NSNotFound) {
		return nil;
	}
	NSString *prefix = [pattern substringToIndex:mode.location];
	NSString *suffix = [pattern substringFromIndex:NSMaxRange(mode)];
	/* hasPrefix: and hasSuffix: say NO to an empty string on Apple. */
	if ([valueName length] <= [prefix length] + [suffix length]
	    || ([prefix length] > 0 && ![valueName hasPrefix:prefix])
	    || ([suffix length] > 0 && ![valueName hasSuffix:suffix])) {
		return nil;
	}
	return [valueName substringWithRange:NSMakeRange([prefix length],
	                                                 [valueName length] - [prefix length] - [suffix length])];
}

/* The model's reference modes by kind, for -deriveReferenceModeOf:: the
 * unit-based, the general, and the popular (lowercased) ones. */
- (NSArray<NSSet<NSString *> *> *)referenceModeSets
{
	NSMutableSet *customUnits = [NSMutableSet setWithArray:ORMUnitReferenceModes()];
	NSMutableSet *customGeneral = [NSMutableSet set];
	/* NORMA's own popular modes, and the model's: compared ignoring case. */
	NSMutableSet *popularModes = [NSMutableSet setWithArray:@[ @"id", @"name", @"code", @"title", @"nr", @"#" ]];
	for (NSString *name in self.customReferenceModes) {
		NSString *type = [self.customReferenceModes objectForKey:name];
		if ([type isEqualToString:@"UnitBased"]) {
			[customUnits addObject:name];
		} else if ([type isEqualToString:@"General"]) {
			[customGeneral addObject:name];
		} else if ([type isEqualToString:@"Popular"]) {
			[popularModes addObject:[name lowercaseString]];
		}
	}
	return @[ customUnits, customGeneral, popularModes ];
}

/* NORMA's reference modes, from the preferred identifiers: an entity
 * type identified by one role of a binary fact type it plays the other
 * role of, where the identifying role's player is a value type named as
 * a reference mode names it. */
- (void)deriveReferenceModes
{
	for (ORMObjectType *type in self.objectTypes) {
		type.valueConstraint = type.ownValueConstraint;
	}
	NSArray *modes = [self referenceModeSets];
	for (ORMObjectType *type in self.objectTypes) {
		[self deriveReferenceModeOf:type modes:modes];
	}
}

/* One entity type's, its value constraint already its own. */
- (void)deriveReferenceModeOf:(ORMObjectType *)type modes:(NSArray<NSSet<NSString *> *> *)modes
{
	NSDictionary *formats = self.referenceModeFormats;
	NSSet *customUnits = [modes objectAtIndex:0];
	NSSet *customGeneral = [modes objectAtIndex:1];
	NSSet *popularModes = [modes objectAtIndex:2];
	ORMConstraint *identifier = type.preferredIdentifier;
	if (!type.isEntity || identifier == nil || !identifier.isInternal || [[identifier allRoles] count] != 1) {
		return;
	}
	ORMRole *role = [[identifier allRoles] firstObject];
	ORMRole *opposite = [role oppositeRole];
	ORMObjectType *value = role.player;
	if (opposite.player != type || value == nil || value.kind != ORMValueType) {
		return;
	}
	NSString *saved = type.savedReferenceMode;
	/* The name read each way; what NORMA saved settles which, and
	 * else the modes the model knows of. */
	NSString *mode = nil;
	ORMReferenceModeKind kind = ORMReferenceModeNone;
	NSString *popular = ORMReferenceModeIn(value.name, [formats objectForKey:@"Popular"], type.name);
	NSString *unit = ORMReferenceModeIn(value.name, [formats objectForKey:@"UnitBased"], type.name);
	if (popular != nil && [saved isEqualToString:popular]) {
		mode = popular;
		kind = ORMReferenceModePopular;
	} else if (unit != nil && [saved isEqualToString:unit]) {
		mode = unit;
		kind = ORMReferenceModeUnitBased;
	} else if ([saved isEqualToString:value.name]) {
		mode = value.name;
		kind = ORMReferenceModeGeneral;
	} else if ([saved length] > 0 && [value.name isEqualToString:[type.name stringByAppendingString:saved]]) {
		/* Older NORMA: "OIALModel.id", saved as ".id". */
		mode = saved;
		kind = ORMReferenceModeGeneral;
	} else if (popular != nil && [popularModes containsObject:[popular lowercaseString]]) {
		mode = popular;
		kind = ORMReferenceModePopular;
	} else if (unit != nil && [customUnits containsObject:unit]) {
		mode = unit;
		kind = ORMReferenceModeUnitBased;
	} else if ([customGeneral containsObject:value.name]) {
		mode = value.name;
		kind = ORMReferenceModeGeneral;
	}
	if (mode == nil) {
		return;
	}
	type.referenceMode = mode;
	type.referenceModeKind = kind;
	type.referenceModeValueType = value;
	type.referenceModeFactType = role.factType;
	type.referenceModeRole = role;
	if (type.valueConstraint == nil) {
		type.valueConstraint = value.valueConstraint;
	}
}

/* What each value constraint constrains the values of. */
- (void)linkValueConstraints
{
	for (ORMObjectType *type in self.objectTypes) {
		if (type.kind == ORMValueType) {
			type.valueConstraint.valueType = type;
		}
	}
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			ORMObjectType *player = role.player;
			role.valueConstraint.valueType = [player valueType];
		}
	}
}

- (void)readDiagrams
{
	_diagramsRead = YES;
	NSMutableArray *diagrams = [NSMutableArray array];
	NSXMLElement *root = [_document rootElement];
	if (root != _modelElement) {
		for (NSXMLElement *element in ORMChildren(root, ORMDiagramNamespace, @"ORMDiagram")) {
			ORMDiagram *diagram = [self element:[ORMDiagram class] for:element];
			[self registerElement:diagram];
			[diagram readShapes];
			[diagrams addObject:diagram];
		}
	}
	_diagrams = diagrams;
	_reusable = nil;
}

@end

#pragma mark Agreement

/* The values an element is read with: the properties its readers set
 * (readwrite, from ORMModelPriv.h), not what is worked out from them. Its
 * XML element and its model are where it is, not what it is. A value
 * object's are all its properties. */
static NSArray<NSString *> *
ORMReadValueKeys(Class elementClass, BOOL all)
{
	NSMutableArray *keys = [NSMutableArray array];
	for (Class c = elementClass; c != Nil && c != [NSObject class]; c = class_getSuperclass(c)) {
		unsigned int count = 0;
		objc_property_t *properties = class_copyPropertyList(c, &count);
		for (unsigned int i = 0; i < count; i++) {
			NSString *name = [NSString stringWithUTF8String:property_getName(properties[i])];
			NSArray *attributes = [[NSString stringWithUTF8String:property_getAttributes(properties[i])]
				componentsSeparatedByString:@","];
			if ((all || ![attributes containsObject:@"R"]) && ![name isEqualToString:@"element"]
			    && ![name isEqualToString:@"model"] && ![keys containsObject:name]) {
				[keys addObject:name];
			}
		}
		free(properties);
	}
	return keys;
}

static NSString *ORMElementDisagreement(ORMElement *a, ORMElement *b);

/* Two values the same: elements by id (or, with none, by their values),
 * arrays and dictionaries item by item, the rest equal. */
static BOOL
ORMSameValue(id a, id b)
{
	/* No list is an empty one. */
	if (a == nil && ([b isKindOfClass:[NSArray class]] || [b isKindOfClass:[NSDictionary class]])) {
		return [b count] == 0;
	}
	if (b == nil && ([a isKindOfClass:[NSArray class]] || [a isKindOfClass:[NSDictionary class]])) {
		return [a count] == 0;
	}
	if (a == nil || b == nil) {
		return a == b;
	}
	if ([a isKindOfClass:[ORMElement class]] && [b isKindOfClass:[ORMElement class]]) {
		NSString *ida = [a identifier], *idb = [b identifier];
		if (ida != nil || idb != nil) {
			return [a class] == [b class] && [ida isEqualToString:idb];
		}
		return ORMElementDisagreement(a, b) == nil;
	}
	if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]]) {
		if ([a count] != [b count]) {
			return NO;
		}
		for (NSUInteger i = 0; i < [a count]; i++) {
			if (!ORMSameValue([a objectAtIndex:i], [b objectAtIndex:i])) {
				return NO;
			}
		}
		return YES;
	}
	if ([a isKindOfClass:[NSDictionary class]] && [b isKindOfClass:[NSDictionary class]]) {
		if ([a count] != [b count]) {
			return NO;
		}
		for (id key in a) {
			if (!ORMSameValue([a objectForKey:key], [b objectForKey:key])) {
				return NO;
			}
		}
		return YES;
	}
	/* A value object of ORMKit's that does not say when it is equal: by
	 * its values. */
	if ([a class] == [b class] && [NSStringFromClass([a class]) hasPrefix:@"ORM"]
	    && class_getMethodImplementation([a class], @selector(isEqual:))
	           == class_getMethodImplementation([NSObject class], @selector(isEqual:))) {
		for (NSString *key in ORMReadValueKeys([a class], YES)) {
			if (!ORMSameValue([a valueForKey:key], [b valueForKey:key])) {
				return NO;
			}
		}
		return YES;
	}
	return [a isEqual:b];
}

static NSString *
ORMElementDisagreement(ORMElement *a, ORMElement *b)
{
	if ([a class] != [b class]) {
		return [NSString stringWithFormat:@"%@ is %@ here, %@ there", a.identifier, [a class], [b class]];
	}
	for (NSString *key in ORMReadValueKeys([a class], NO)) {
		id va = [a valueForKey:key], vb = [b valueForKey:key];
		if (!ORMSameValue(va, vb)) {
			return [NSString stringWithFormat:@"%@'s %@: %@ here, %@ there", a, key, va, vb];
		}
	}
	return nil;
}

NSString *
ORMModelDisagreement(ORMModel *model, ORMModel *other)
{
	/* Shapes are read when the diagrams are. */
	[model diagrams];
	[other diagrams];
	NSDictionary *mine = [model valueForKey:@"elementsById"], *theirs = [other valueForKey:@"elementsById"];
	for (NSString *key in @[ @"identifier", @"name", @"referenceModeFormats", @"customReferenceModes", @"derivationRules", @"coreDataMappings", @"storedQueries", @"objectTypes", @"factTypes", @"constraints", @"dataTypes",
	                         @"notes", @"diagrams" ]) {
		if (!ORMSameValue([model valueForKey:key], [other valueForKey:key])) {
			return [NSString stringWithFormat:@"the model's %@ differ", key];
		}
	}
	for (NSString *identifier in mine) {
		ORMElement *a = [mine objectForKey:identifier], *b = [theirs objectForKey:identifier];
		if (b == nil) {
			return [NSString stringWithFormat:@"%@ is here only", a];
		}
		NSString *difference = ORMElementDisagreement(a, b);
		if (difference != nil) {
			return difference;
		}
	}
	for (NSString *identifier in theirs) {
		if ([mine objectForKey:identifier] == nil) {
			return [NSString stringWithFormat:@"%@ is there only", [theirs objectForKey:identifier]];
		}
	}
	return nil;
}
