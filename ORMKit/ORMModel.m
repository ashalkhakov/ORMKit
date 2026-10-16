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

/* Whether the list has the object itself; no list has nothing. */
static BOOL
ORMContains(NSArray *list, id object)
{
	return list != nil && [list indexOfObjectIdenticalTo:object] != NSNotFound;
}

/* How the elements keep their links both ways, through the model. */
@interface ORMModel ()
- (BOOL)holdsRole:(ORMRole *)role;
- (void)linkRole:(ORMRole *)role;
- (void)unlinkRole:(ORMRole *)role;
- (NSArray<ORMRole *> *)rolesPlayedWith:(ORMRole *)role;
- (void)linkConstraint:(ORMConstraint *)constraint;
- (void)unlinkConstraint:(ORMConstraint *)constraint;
- (void)relinkObjectifying:(ORMFactType *)fact;
- (void)relinkIdentified:(ORMConstraint *)constraint;
- (NSArray *)list:(NSArray *)list adding:(ORMElement *)element;
- (NSArray *)referenceModeOf:(ORMObjectType *)type;
- (ORMObjectType *)impliedOwnerOf:(ORMConstraint *)constraint;
- (void)noteName:(NSString *)name;
@end

@interface ORMRole ()
/* Whether it is played as the role it stands for is: a proxy with no
 * player of its own. */
- (BOOL)playsThroughProxy;
@end

@interface ORMReading ()
- (void)parse;
@end

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

- (void)setName:(NSString *)name
{
	_name = [name copy];
	[_model noteName:_name];
}

- (void)reset
{
	_definitionText = nil;
	_noteText = nil;
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
	_dataType = nil;
	_dataTypeLength = _dataTypeScale = 0;
	_ownValueConstraint = nil;
	_savedReferenceMode = nil;
	_objectificationId = nil;
}

- (void)setNestedFactType:(ORMFactType *)fact
{
	ORMFactType *was = _nestedFactType;
	_nestedFactType = fact;
	if ([self.model holds:self]) {
		if (was.objectifyingType == self) {
			[self.model relinkObjectifying:was];
		}
		fact.objectifyingType = self;
	}
}

- (void)setPreferredIdentifier:(ORMConstraint *)identifier
{
	ORMConstraint *was = _preferredIdentifier;
	_preferredIdentifier = identifier;
	if ([self.model holds:self]) {
		if (was.preferredIdentifierFor == self) {
			[self.model relinkIdentified:was];
		}
		if (identifier.kind == ORMUniquenessConstraint) {
			identifier.preferredIdentifierFor = self;
		}
	}
}

- (void)setOwnValueConstraint:(ORMValueConstraint *)values
{
	_ownValueConstraint = values;
	values.owner = self;
}

/* What the subtype fact types it plays say of it: the supertypes, its
 * subtypes, the fact types to its supertypes; in the model's order. */
- (NSArray *)subtyping:(BOOL)up facts:(BOOL)facts
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMRole *role in self.playedRoles) {
		ORMFactType *fact = role.factType;
		if (fact.kind != ORMFactTypeSubtype || [fact.roles count] != 2
		    || !(up ? role.isSubtypeMetaRole : role.isSupertypeMetaRole)) {
			continue;
		}
		ORMObjectType *other = nil;
		for (ORMRole *each in fact.roles) {
			if (up ? each.isSupertypeMetaRole : each.isSubtypeMetaRole) {
				other = each.player;
			}
		}
		if (other != nil) {
			[found addObject:facts ? (id)fact : other];
		}
	}
	return found;
}

- (NSArray<ORMObjectType *> *)supertypes
{
	return [self subtyping:YES facts:NO];
}

- (NSArray<ORMObjectType *> *)subtypes
{
	return [self subtyping:NO facts:NO];
}

- (NSArray<ORMFactType *> *)supertypeFacts
{
	return [self subtyping:YES facts:YES];
}

- (NSString *)referenceMode
{
	return [[self.model referenceModeOf:self] objectAtIndex:0];
}

- (ORMReferenceModeKind)referenceModeKind
{
	NSArray *mode = [self.model referenceModeOf:self];
	return mode != nil ? [[mode objectAtIndex:1] integerValue] : ORMReferenceModeNone;
}

- (ORMObjectType *)referenceModeValueType
{
	return [[self.model referenceModeOf:self] objectAtIndex:2];
}

- (ORMFactType *)referenceModeFactType
{
	return [[self.model referenceModeOf:self] objectAtIndex:3];
}

- (ORMRole *)referenceModeRole
{
	return [[self.model referenceModeOf:self] objectAtIndex:4];
}

- (ORMValueConstraint *)valueConstraint
{
	ORMObjectType *value = [[self.model referenceModeOf:self] objectAtIndex:2];
	return self.ownValueConstraint ?: value.ownValueConstraint;
}

/* Its family: the types reached up and down from it, in the model's
 * order. */
- (NSArray<ORMObjectType *> *)family
{
	if ([self.supertypes count] == 0 && [self.subtypes count] == 0) {
		return @[ self ];
	}
	NSHashTable *members = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:self];
	while ([pending count] > 0) {
		ORMObjectType *each = [pending lastObject];
		[pending removeLastObject];
		if (![members containsObject:each]) {
			[members addObject:each];
			[pending addObjectsFromArray:each.subtypes];
			[pending addObjectsFromArray:each.supertypes];
		}
	}
	NSMutableArray *family = [NSMutableArray array];
	for (ORMObjectType *type in self.model.objectTypes) {
		if ([members containsObject:type]) {
			[family addObject:type];
		}
	}
	return family;
}

- (NSArray<NSString *> *)familyNames
{
	NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
	for (ORMObjectType *type in [self family]) {
		if (type.name != nil) {
			[names addObject:type.name];
		}
	}
	return [[names array] sortedArrayUsingFunction:ORMLongerFirst context:NULL];
}

- (BOOL)isInSubtypeHierarchy
{
	return [self.supertypes count] > 0 || [self.subtypes count] > 0;
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

NSString *const ORMSubtypeReadingText = @"{0} is {1}";

/* By where each is in the list given. */
static NSInteger
ORMByPlace(id a, id b, void *list)
{
	NSUInteger i = [(__bridge NSArray *)list indexOfObjectIdenticalTo:a];
	NSUInteger j = [(__bridge NSArray *)list indexOfObjectIdenticalTo:b];
	return i < j ? NSOrderedAscending : i > j ? NSOrderedDescending : NSOrderedSame;
}

@implementation ORMFactType

- (void)reset
{
	[super reset];
	_kind = ORMFactTypeOrdinary;
	_roles = nil;
	_readingOrders = nil;
	_objectifyingType = nil;
	_impliedByFactType = nil;
	_linkFactTypes = nil;
	_isDerived = NO;
	_preferredIdentificationPath = nil;
	_saysProvidesPreferredIdentifier = NO;
	_explicitName = nil;
	_savedDerivedName = nil;
}

- (void)setRoles:(NSArray<ORMRole *> *)roles
{
	BOOL held = [self.model holds:self];
	for (ORMRole *role in held ? _roles : @[]) {
		if (!ORMContains(roles, role)) {
			[self.model unlinkRole:role];
		}
	}
	NSArray *was = _roles;
	_roles = [roles copy];
	for (ORMRole *role in held ? _roles : @[]) {
		if (!ORMContains(was, role)) {
			[self.model linkRole:role];
		}
	}
}

- (void)setImpliedByFactType:(ORMFactType *)fact
{
	BOOL held = [self.model holds:self];
	if (held && _impliedByFactType != nil) {
		_impliedByFactType.linkFactTypes = ORMWithout(_impliedByFactType.linkFactTypes, self);
		if ([_impliedByFactType.linkFactTypes count] == 0) {
			_impliedByFactType.linkFactTypes = nil;
		}
	}
	_impliedByFactType = fact;
	if (held && fact != nil) {
		fact.linkFactTypes = [self.model list:fact.linkFactTypes adding:self];
	}
}

/* Its name: the one given it, else the one NORMA keeps derived. */
- (NSString *)name
{
	return self.explicitName ?: self.savedDerivedName ?: @"";
}

/* The constraints its roles have that are its own: uniqueness over its
 * roles alone, mandatory on one of them; in the model's order. */
- (NSArray<ORMConstraint *> *)internalConstraints
{
	NSMutableArray *internal = [NSMutableArray array];
	for (ORMRole *role in self.roles) {
		for (ORMConstraint *constraint in role.constraints) {
			if ([internal indexOfObjectIdenticalTo:constraint] != NSNotFound) {
				continue;
			}
			NSArray *facts = [constraint factTypes];
			BOOL own = [facts count] == 1 && [facts firstObject] == self
				&& (constraint.kind == ORMUniquenessConstraint ? constraint.isInternal
			                                                    : (constraint.kind == ORMMandatoryConstraint ? constraint.isSimple : NO));
			if (own) {
				[internal addObject:constraint];
			}
		}
	}
	if ([internal count] > 1) {
		NSArray *all = self.model.constraints;
		[internal sortUsingFunction:ORMByPlace context:(__bridge void *)all];
	}
	return internal;
}

- (BOOL)providesPreferredIdentifier
{
	if ([self.preferredIdentificationPath boolValue] || self.saysProvidesPreferredIdentifier) {
		return YES;
	}
	/* NORMA leaves the attribute out where it is true by default: a
	 * subtype with no identifier of its own is identified through its
	 * (first) supertype. */
	if (self.kind == ORMFactTypeSubtype && self.preferredIdentificationPath == nil) {
		ORMObjectType *sub = [self subtype];
		return sub.preferredIdentifier == nil && [sub.supertypeFacts firstObject] == self;
	}
	return NO;
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

- (NSArray<ORMRole *> *)subtypeReadingRolesFrom:(ORMRole *)role
{
	if (self.kind != ORMFactTypeSubtype || [self.roles count] != 2) {
		return nil;
	}
	ORMRole *sub = [self.roles objectAtIndex:0];
	ORMRole *sup = [self.roles objectAtIndex:1];
	return role == sup ? @[ sup, sub ] : @[ sub, sup ];
}

- (NSString *)unaryReading
{
	return [self isUnary] ? [[self primaryReading] expandedText] ?: @"" : nil;
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
- (NSString *)derivedName
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

@synthesize player = _player;

- (void)reset
{
	[super reset];
	_factType = nil;
	_player = nil;
	_index = 0;
	_valueConstraint = nil;
	_isSubtypeMetaRole = _isSupertypeMetaRole = NO;
	_proxiedRole = nil;
	_proxies = nil;
	_constraints = nil;
	_roleInstances = nil;
}

/* A proxy is played by what plays the role it stands for, unless it
 * says otherwise. */
- (ORMObjectType *)player
{
	return _player ?: _proxiedRole.player;
}

- (BOOL)playsThroughProxy
{
	return _player == nil && _proxiedRole != nil;
}

- (void)setPlayer:(ORMObjectType *)player
{
	ORMModel *model = self.model;
	NSArray *moved = [model holdsRole:self] ? [model rolesPlayedWith:self] : @[];
	for (ORMRole *role in moved) {
		[model unlinkRole:role];
	}
	_player = player;
	for (ORMRole *role in moved) {
		[model linkRole:role];
	}
}

- (void)setProxiedRole:(ORMRole *)role
{
	ORMModel *model = self.model;
	BOOL held = [model holdsRole:self];
	if (held) {
		[model unlinkRole:self];
	}
	_proxiedRole = role;
	if (held) {
		[model linkRole:self];
	}
}

- (void)setValueConstraint:(ORMValueConstraint *)values
{
	_valueConstraint = values;
	values.owner = self;
}

/* What its own constraints say of it: mandatory, unique; alethically. */
- (BOOL)isSaid:(ORMConstraintKind)kind alethic:(BOOL)alethic
{
	for (ORMConstraint *constraint in self.constraints) {
		BOOL single = constraint.kind == ORMMandatoryConstraint ? constraint.isSimple : constraint.isInternal;
		if (constraint.kind == kind && single && [[constraint allRoles] count] == 1
		    && (!alethic || constraint.modality == ORMAlethic)) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)isMandatory
{
	return [self isSaid:ORMMandatoryConstraint alethic:NO];
}

- (BOOL)isAlethicMandatory
{
	return [self isSaid:ORMMandatoryConstraint alethic:YES];
}

- (BOOL)isUnique
{
	return [self isSaid:ORMUniquenessConstraint alethic:NO];
}

- (BOOL)isAlethicUnique
{
	return [self isSaid:ORMUniquenessConstraint alethic:YES];
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

/* Its readings parsed again for so many roles. */
- (void)setRoles:(NSArray<ORMRole *> *)roles
{
	_roles = [roles copy];
	for (ORMReading *reading in _readings) {
		[reading parse];
	}
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

- (void)setText:(NSString *)text
{
	_text = [text copy];
	[self parse];
}

- (void)setReadingOrder:(ORMReadingOrder *)order
{
	_readingOrder = order;
	[self parse];
}

/* Its words and its text parsed, as it reads now. */
- (void)parse
{
	_words = [ORMReadingText wordsOf:_text ?: @""];
	_parsedText = [ORMReadingText readingTextWithString:_text arity:[_readingOrder.roles count] reason:NULL];
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
	ORMModel *model = self.model;
	BOOL held = [model holds:_constraint] && ORMContains(_constraint.roleSequences, self);
	if (held) {
		[model unlinkConstraint:_constraint];
	}
	_roles = [roles copy];
	_roleUseIds = ids;
	if (held) {
		[model linkConstraint:_constraint];
	}
}

- (ORMFactType *)factType
{
	ORMFactType *fact = [[self.roles firstObject] factType];
	for (ORMRole *role in self.roles) {
		if (role.factType != fact) {
			return nil;
		}
	}
	return fact;
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

/* What says it is NORMA's implied mandatory constraint of an object type,
 * kept up in that type's list. */
- (void)setKind:(ORMConstraintKind)kind
{
	ORMObjectType *was = [self impliedOwner];
	_kind = kind;
	[self relinkImpliedFrom:was];
}

- (void)setIsImplied:(BOOL)implied
{
	ORMObjectType *was = [self impliedOwner];
	_isImplied = implied;
	[self relinkImpliedFrom:was];
}

- (void)setImpliedByObjectTypeId:(NSString *)identifier
{
	ORMObjectType *was = [self impliedOwner];
	_impliedByObjectTypeId = [identifier copy];
	[self relinkImpliedFrom:was];
}

/* The object type it is implied by, while it is in the model. */
- (ORMObjectType *)impliedOwner
{
	return [self.model holds:self] ? [self.model impliedOwnerOf:self] : nil;
}

/* Out of the list of the type it was implied by, into the one it is. */
- (void)relinkImpliedFrom:(ORMObjectType *)was
{
	ORMObjectType *now = [self impliedOwner];
	if (was != now) {
		was.impliedMandatories = ORMWithout(was.impliedMandatories, self);
		now.impliedMandatories = [self.model list:now.impliedMandatories adding:self];
	}
}

- (void)setRoleSequences:(NSArray<ORMRoleSequence *> *)sequences
{
	ORMModel *model = self.model;
	BOOL held = [model holds:self];
	if (held) {
		[model unlinkConstraint:self];
	}
	_roleSequences = [sequences copy];
	for (ORMRoleSequence *sequence in _roleSequences) {
		sequence.constraint = self;
	}
	if (held) {
		[model linkConstraint:self];
	}
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
	_owner = nil;
}

/* What it constrains the values of: a value type's own; a role's
 * player's value type. */
- (ORMObjectType *)valueType
{
	if ([self.owner isKindOfClass:[ORMRole class]]) {
		return [[(ORMRole *)self.owner player] valueType];
	}
	ORMObjectType *type = (ORMObjectType *)self.owner;
	return type.kind == ORMValueType ? type : nil;
}

- (BOOL)quotesValues
{
	return self.valueType.dataType == nil || [self.valueType.dataType quotesValues];
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

- (BOOL)isNumeric
{
	return self.family == ORMDataTypeNumeric;
}

- (BOOL)quotesValues
{
	switch (self.family) {
	case ORMDataTypeNumeric:
	case ORMDataTypeTemporal:
	case ORMDataTypeLogical:
		return NO;
	default:
		return YES;
	}
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
	/* While the model is read again: the elements read before, by id, to
	 * be read again in place. */
	NSMutableDictionary<NSString *, ORMElement *> *_reusable;
	/* While the model is read: no link is kept up until all is read. */
	BOOL _reading;
	/* The highest number each name stem has gone with
	 * ("InternalUniquenessConstraint" 7): what the next name takes. */
	NSMutableDictionary<NSString *, NSNumber *> *_highestNumbers;
	/* The reference modes it knows of by kind, from its custom ones. */
	NSSet<NSString *> *_unitModes;
	NSSet<NSString *> *_generalModes;
	NSSet<NSString *> *_popularModes;
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
	}
	for (ORMFactType *fact in self.factTypes) {
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
	[self cutLinks];
	_reusable = reusable;
	_diagrams = nil;
	[self readDocument:document model:ORMModelElementOfDocument(document)];
}

- (void)addElement:(ORMElement *)element
{
	[self registerElement:element];
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
	if (_reading) {
		return;
	}
	/* Linked to what it names, and what names it. */
	if ([element isKindOfClass:[ORMFactType class]]) {
		[self linkFactType:(ORMFactType *)element];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		[self linkConstraint:(ORMConstraint *)element];
	} else if ([element isKindOfClass:[ORMObjectType class]]) {
		ORMObjectType *type = (ORMObjectType *)element;
		if (type.nestedFactType != nil) {
			type.nestedFactType.objectifyingType = type;
		}
		if (type.preferredIdentifier.kind == ORMUniquenessConstraint) {
			type.preferredIdentifier.preferredIdentifierFor = type;
		}
	}
}

- (void)removeElement:(ORMElement *)element
{
	if (element == nil) {
		return;
	}
	/* Unlinked while it is still in the model. */
	if ([self holds:element] && [element isKindOfClass:[ORMFactType class]]) {
		[self unlinkFactType:(ORMFactType *)element];
	} else if ([self holds:element] && [element isKindOfClass:[ORMConstraint class]]) {
		[self unlinkConstraint:(ORMConstraint *)element];
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
	if (element.identifier != nil) {
		[self.removedIds addObject:element.identifier];
	}
	_dataTypes = ORMWithout(_dataTypes, element);
	_objectTypes = ORMWithout(_objectTypes, element);
	_factTypes = ORMWithout(_factTypes, element);
	_constraints = ORMWithout(_constraints, element);
	_notes = ORMWithout(_notes, element);
	/* What it objectified and identified are so by another, or none. */
	if ([element isKindOfClass:[ORMObjectType class]]) {
		ORMObjectType *type = (ORMObjectType *)element;
		if (type.nestedFactType.objectifyingType == type) {
			[self relinkObjectifying:type.nestedFactType];
		}
		if (type.preferredIdentifier.preferredIdentifierFor == type) {
			[self relinkIdentified:type.preferredIdentifier];
		}
	}
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
	return [_elements objectForKey:identifier];
}

@synthesize diagrams = _diagrams;

- (void)addDiagram:(ORMDiagram *)diagram
{
	_diagrams = [_diagrams arrayByAddingObject:diagram];
	[self registerElement:diagram];
}

- (ORMObjectType *)objectTypeNamed:(NSString *)name
{
	for (ORMObjectType *type in name != nil ? self.objectTypes : @[]) {
		if ([type.name isEqualToString:name]) {
			return type;
		}
	}
	return nil;
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
	_highestNumbers = [NSMutableDictionary dictionary];
	_reading = YES;
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
	self.extras = [NSMutableDictionary dictionary];
	[self readPathsAndPopulations];
	[self readCoreDataMappings];
	[self readQueries];
	[self readDiagrams];
	_reusable = nil;
	[self linkAll];
	for (ORMElement *element in [_elements allValues]) {
		[self noteName:element.name];
	}
	_reading = NO;
}

/* A name that ends in a number (no leading zero) noted for its stem. */
- (void)noteName:(NSString *)name
{
	NSUInteger end = [name length];
	NSUInteger start = end;
	while (start > 0 && [name characterAtIndex:start - 1] >= '0' && [name characterAtIndex:start - 1] <= '9') {
		start--;
	}
	if (start == 0 || start == end || [name characterAtIndex:start] == '0') {
		return;
	}
	NSString *stem = [name substringToIndex:start];
	NSInteger number = [[name substringFromIndex:start] integerValue];
	if (number > [[_highestNumbers objectForKey:stem] integerValue]) {
		[_highestNumbers setObject:@(number) forKey:stem];
	}
}

- (NSString *)nextNameWithPrefix:(NSString *)prefix
{
	NSInteger number = [[_highestNumbers objectForKey:prefix] integerValue] + 1;
	[_highestNumbers setObject:@(number) forKey:prefix];
	return [NSString stringWithFormat:@"%@%ld", prefix, (long)number];
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

#pragma mark Links

/* Each link the model keeps both ways, made once the model is read: the
 * roles each object type plays (its own, then those it plays through a
 * link fact type's proxies), each role's proxies and constraints, each
 * fact type's link fact types and what objectifies it, each uniqueness
 * constraint's object type it identifies; in the order of the model's
 * lists, as the setters keep them after. What the file keeps derived and
 * the model reads as said (_ReferenceMode, _Name) is what the links give. */
- (void)linkAll
{
	NSMapTable *played = [NSMapTable strongToStrongObjectsMapTable];
	NSMapTable *proxied = [NSMapTable strongToStrongObjectsMapTable];
	for (ORMObjectType *type in self.objectTypes) {
		[played setObject:[NSMutableArray array] forKey:type];
	}
	for (NSUInteger pass = 0; pass < 2; pass++) {
		for (ORMFactType *fact in self.factTypes) {
			for (ORMRole *role in fact.roles) {
				if ([role playsThroughProxy] == (pass == 1)) {
					[(NSMutableArray *)[played objectForKey:role.player] addObject:role];
				}
				if (pass == 0 && role.proxiedRole != nil) {
					NSMutableArray *proxies = [proxied objectForKey:role.proxiedRole];
					if (proxies == nil) {
						proxies = [NSMutableArray array];
						[proxied setObject:proxies forKey:role.proxiedRole];
					}
					[proxies addObject:role];
				}
			}
		}
	}
	for (ORMObjectType *type in self.objectTypes) {
		type.playedRoles = [played objectForKey:type];
	}
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			role.proxies = [proxied objectForKey:role];
			role.constraints = @[];
		}
		fact.linkFactTypes = nil;
		fact.objectifyingType = nil;
	}
	for (ORMObjectType *type in self.objectTypes) {
		type.impliedMandatories = nil;
	}
	for (ORMConstraint *constraint in self.constraints) {
		constraint.preferredIdentifierFor = nil;
		for (ORMRole *role in [constraint allRoles]) {
			role.constraints = [role.constraints ?: @[] arrayByAddingObject:constraint];
		}
		ORMObjectType *owner = [self impliedOwnerOf:constraint];
		owner.impliedMandatories = [owner.impliedMandatories ?: @[] arrayByAddingObject:constraint];
	}
	for (ORMFactType *fact in self.factTypes) {
		ORMFactType *objectified = fact.impliedByFactType;
		if (objectified != nil) {
			objectified.linkFactTypes = [objectified.linkFactTypes ?: @[] arrayByAddingObject:fact];
		}
	}
	for (ORMObjectType *type in self.objectTypes) {
		type.nestedFactType.objectifyingType = type;
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
		fact.lastUnaryReading = [fact unaryReading];
	}
}

- (BOOL)holds:(ORMElement *)element
{
	return !_reading && element.identifier != nil && [_elements objectForKey:element.identifier] == element;
}

/* Whether the role is one of a fact type the model holds. */
- (BOOL)holdsRole:(ORMRole *)role
{
	return [self holds:role.factType] && ORMContains(role.factType.roles, role);
}

/* Where an element goes in a list the model keeps in its own order: a
 * role by its fact type and place in it (one played through a proxy after
 * the rest), a fact type or constraint by its place in the model. */
- (NSArray<NSNumber *> *)orderOf:(ORMElement *)element
{
	if ([element isKindOfClass:[ORMRole class]]) {
		ORMRole *role = (ORMRole *)element;
		return @[ @([role playsThroughProxy] ? 1 : 0), @([self.factTypes indexOfObjectIdenticalTo:role.factType]),
			      @([role.factType.roles indexOfObjectIdenticalTo:role]) ];
	}
	NSArray *list = [element isKindOfClass:[ORMFactType class]] ? (NSArray *)self.factTypes : (NSArray *)self.constraints;
	return @[ @([list indexOfObjectIdenticalTo:element]) ];
}

static NSComparisonResult
ORMCompareOrders(NSArray<NSNumber *> *a, NSArray<NSNumber *> *b)
{
	for (NSUInteger i = 0; i < [a count] && i < [b count]; i++) {
		NSComparisonResult result = [[a objectAtIndex:i] compare:[b objectAtIndex:i]];
		if (result != NSOrderedSame) {
			return result;
		}
	}
	return NSOrderedSame;
}

/* The list with the element in its place; the list as it was where it is
 * in it already. */
- (NSArray *)list:(NSArray *)list adding:(ORMElement *)element
{
	if (element == nil || ORMContains(list, element)) {
		return list;
	}
	NSArray *order = [self orderOf:element];
	NSUInteger at = [list count];
	while (at > 0 && ORMCompareOrders([self orderOf:[list objectAtIndex:at - 1]], order) == NSOrderedDescending) {
		at--;
	}
	NSMutableArray *added = [NSMutableArray arrayWithArray:list ?: @[]];
	[added insertObject:element atIndex:at];
	return added;
}

/* A role taken into, or out of, the lists of what it is linked to: its
 * player's played roles, the proxied role's proxies. */
- (void)linkRole:(ORMRole *)role
{
	ORMObjectType *player = role.player;
	if (player != nil) {
		player.playedRoles = [self list:player.playedRoles adding:role];
		[self.relinkedTypes addObject:player];
	}
	if (role.proxiedRole != nil) {
		role.proxiedRole.proxies = [self list:role.proxiedRole.proxies adding:role];
	}
}

- (void)unlinkRole:(ORMRole *)role
{
	ORMObjectType *player = role.player;
	if (player != nil) {
		player.playedRoles = ORMWithout(player.playedRoles, role);
		[self.relinkedTypes addObject:player];
	}
	if (role.proxiedRole != nil) {
		role.proxiedRole.proxies = ORMWithout(role.proxiedRole.proxies, role);
	}
}

/* The roles whose player is the role's: it, and its proxies that play
 * through it. */
- (NSArray<ORMRole *> *)rolesPlayedWith:(ORMRole *)role
{
	NSMutableArray *roles = [NSMutableArray arrayWithObject:role];
	for (ORMRole *proxy in role.proxies) {
		if ([proxy playsThroughProxy]) {
			[roles addObject:proxy];
		}
	}
	return roles;
}

- (void)linkFactType:(ORMFactType *)fact
{
	for (ORMRole *role in fact.roles) {
		[self linkRole:role];
	}
	ORMFactType *objectified = fact.impliedByFactType;
	if (objectified != nil) {
		objectified.linkFactTypes = [self list:objectified.linkFactTypes adding:fact];
	}
}

- (void)unlinkFactType:(ORMFactType *)fact
{
	for (ORMRole *role in fact.roles) {
		[self unlinkRole:role];
	}
	ORMFactType *objectified = fact.impliedByFactType;
	if (objectified != nil) {
		objectified.linkFactTypes = ORMWithout(objectified.linkFactTypes, fact);
		if ([objectified.linkFactTypes count] == 0) {
			objectified.linkFactTypes = nil;
		}
	}
}

- (void)linkConstraint:(ORMConstraint *)constraint
{
	for (ORMRole *role in [constraint allRoles]) {
		role.constraints = [self list:role.constraints adding:constraint];
	}
	[self noteRelinked:constraint];
	ORMObjectType *owner = [self impliedOwnerOf:constraint];
	if (owner != nil) {
		owner.impliedMandatories = [self list:owner.impliedMandatories adding:constraint];
	}
}

- (void)unlinkConstraint:(ORMConstraint *)constraint
{
	for (ORMRole *role in [constraint allRoles]) {
		role.constraints = ORMWithout(role.constraints, constraint);
	}
	[self noteRelinked:constraint];
	ORMObjectType *owner = [self impliedOwnerOf:constraint];
	if (owner != nil) {
		owner.impliedMandatories = ORMWithout(owner.impliedMandatories, constraint);
	}
}

/* The object types a constraint's links tell of: the players of its fact
 * types' roles, the one it identifies. */
- (void)noteRelinked:(ORMConstraint *)constraint
{
	for (ORMRole *role in self.relinkedTypes != nil ? [constraint allRoles] : @[]) {
		for (ORMRole *each in role.factType.roles) {
			if (each.player != nil) {
				[self.relinkedTypes addObject:each.player];
			}
		}
	}
	if (constraint.preferredIdentifierFor != nil) {
		[self.relinkedTypes addObject:constraint.preferredIdentifierFor];
	}
}

/* The object type an implied mandatory constraint says it is implied by. */
- (ORMObjectType *)impliedOwnerOf:(ORMConstraint *)constraint
{
	if (constraint.kind != ORMMandatoryConstraint || !constraint.isImplied || constraint.impliedByObjectTypeId == nil) {
		return nil;
	}
	ORMObjectType *owner = [self elementWithId:constraint.impliedByObjectTypeId];
	return [owner isKindOfClass:[ORMObjectType class]] ? owner : nil;
}

/* What objectifies the fact type, what the constraint is the preferred
 * identifier of: the last object type in the model that says so. */
- (void)relinkObjectifying:(ORMFactType *)fact
{
	ORMObjectType *found = nil;
	for (ORMObjectType *type in self.objectTypes) {
		found = type.nestedFactType == fact ? type : found;
	}
	fact.objectifyingType = found;
}

- (void)relinkIdentified:(ORMConstraint *)constraint
{
	ORMObjectType *found = nil;
	for (ORMObjectType *type in constraint.kind == ORMUniquenessConstraint ? self.objectTypes : @[]) {
		found = type.preferredIdentifier == constraint ? type : found;
	}
	constraint.preferredIdentifierFor = found;
}

#pragma mark Reference modes

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

- (void)setCustomReferenceModes:(NSDictionary<NSString *, NSString *> *)modes
{
	_customReferenceModes = [modes copy];
	NSMutableSet *units = [NSMutableSet setWithArray:ORMUnitReferenceModes()];
	NSMutableSet *general = [NSMutableSet set];
	/* NORMA's own popular modes, and the model's: compared ignoring case. */
	NSMutableSet *popular = [NSMutableSet setWithArray:@[ @"id", @"name", @"code", @"title", @"nr", @"#" ]];
	for (NSString *name in modes) {
		NSString *type = [modes objectForKey:name];
		if ([type isEqualToString:@"UnitBased"]) {
			[units addObject:name];
		} else if ([type isEqualToString:@"General"]) {
			[general addObject:name];
		} else if ([type isEqualToString:@"Popular"]) {
			[popular addObject:[name lowercaseString]];
		}
	}
	_unitModes = units;
	_generalModes = general;
	_popularModes = popular;
}

/* NORMA's reference mode of an entity type identified by one role of a
 * binary fact type it plays the other role of, where the identifying
 * role's player is a value type named as a reference mode names it: the
 * mode, its kind, the value type, the fact type and the role; nil for
 * none. What NORMA saved settles how a name reads, else the modes the
 * model knows of. */
- (NSArray *)referenceModeOf:(ORMObjectType *)type
{
	ORMConstraint *identifier = type.preferredIdentifier;
	if (!type.isEntity || identifier == nil || !identifier.isInternal) {
		return nil;
	}
	NSArray *roles = [identifier allRoles];
	if ([roles count] != 1) {
		return nil;
	}
	ORMRole *role = [roles firstObject];
	ORMObjectType *value = role.player;
	if ([role oppositeRole].player != type || value == nil || value.kind != ORMValueType) {
		return nil;
	}
	NSString *saved = type.savedReferenceMode;
	NSString *popular = ORMReferenceModeIn(value.name, [self.referenceModeFormats objectForKey:@"Popular"], type.name);
	NSString *unit = ORMReferenceModeIn(value.name, [self.referenceModeFormats objectForKey:@"UnitBased"], type.name);
	NSString *mode = nil;
	ORMReferenceModeKind kind = ORMReferenceModeNone;
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
	} else if (popular != nil && [_popularModes containsObject:[popular lowercaseString]]) {
		mode = popular;
		kind = ORMReferenceModePopular;
	} else if (unit != nil && [_unitModes containsObject:unit]) {
		mode = unit;
		kind = ORMReferenceModeUnitBased;
	} else if ([_generalModes containsObject:value.name]) {
		mode = value.name;
		kind = ORMReferenceModeGeneral;
	}
	return mode != nil ? @[ mode, @(kind), value, role.factType, role ] : nil;
}

- (void)readDiagrams
{
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
