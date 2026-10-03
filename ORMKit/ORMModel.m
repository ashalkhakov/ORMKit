/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModelPriv.h"
#import "ORMXML.h"

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

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@ %@>", NSStringFromClass([self class]), self.identifier, self.name];
}

@end

#pragma mark Object types

@implementation ORMObjectType

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

- (ORMReading *)primaryReading
{
	for (ORMReadingOrder *order in self.readingOrders) {
		if ([order.readings count] > 0) {
			return [order.readings firstObject];
		}
	}
	return nil;
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

/* "Person was born in Country" to "PersonWasBornInCountry": the reading's
 * own words capitalized and run together, the object type names in their
 * own case without punctuation (NORMA writes "WeightHaskgValue" and
 * "ProductHasProductId"). */
- (NSString *)derivedName
{
	if (self.kind == ORMFactTypeSubtype) {
		ORMObjectType *sub = [[self.roles firstObject] player];
		ORMObjectType *sup = [[self.roles lastObject] player];
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
	NSCharacterSet *separators = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
	NSScanner *scanner = [NSScanner scannerWithString:reading.text];
	[scanner setCharactersToBeSkipped:nil];
	while (![scanner isAtEnd]) {
		NSString *literal = nil;
		if ([scanner scanUpToString:@"{" intoString:&literal]) {
			for (NSString *word in [literal componentsSeparatedByCharactersInSet:separators]) {
				if ([word length] > 0) {
					[name appendString:[[word substringToIndex:1] uppercaseString]];
					[name appendString:[word substringFromIndex:1]];
				}
			}
		}
		if ([scanner scanString:@"{" intoString:NULL]) {
			NSInteger index = -1;
			if ([scanner scanInteger:&index] && [scanner scanString:@"}" intoString:NULL] && index >= 0
			    && (NSUInteger)index < [roles count]) {
				NSString *player = [[[roles objectAtIndex:index] player] name] ?: @"";
				[name appendString:[[player componentsSeparatedByCharactersInSet:separators]
				                       componentsJoinedByString:@""]];
			}
		}
	}
	return name;
}

@end

@implementation ORMRole

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
	ORMRole *opposite = [self oppositeRole];
	if (opposite == nil || [self.factType isUnary]) {
		return ORMMultiplicityUnspecified;
	}
	BOOL one = opposite.isUnique;
	BOOL mandatory = opposite.isMandatory;
	if (one) {
		return mandatory ? ORMMultiplicityExactlyOne : ORMMultiplicityZeroToOne;
	}
	return mandatory ? ORMMultiplicityOneToMany : ORMMultiplicityZeroToMany;
}

@end

@implementation ORMReadingOrder
@end

@implementation ORMReading

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
@end

@implementation ORMConstraint

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

static ORMRangeInclusion
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

@implementation ORMModel
{
	NSMutableDictionary<NSString *, id> *_elements;
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

- (void)registerElement:(ORMElement *)element
{
	if (element.identifier != nil) {
		[_elements setObject:element forKey:element.identifier];
	}
}

- (id)elementWithId:(NSString *)identifier
{
	return identifier != nil ? [_elements objectForKey:identifier] : nil;
}

- (ORMObjectType *)objectTypeNamed:(NSString *)name
{
	for (ORMObjectType *type in self.objectTypes) {
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
	_document = document;
	_modelElement = modelElement;
	_identifier = [ORMAttribute(modelElement, @"id") copy];
	_name = [ORMAttribute(modelElement, @"Name") copy] ?: @"";

	[self readDataTypes];
	[self readObjectTypes];
	[self readFactTypes];
	[self readConstraints];
	[self readNotes];
	[self linkObjectTypes];
	[self linkFactTypes];
	[self linkRoles];
	[self deriveReferenceModes];
	[self linkValueConstraints];
	self.extras = [NSMutableDictionary dictionary];
	[self readPathsAndPopulations];
	[self readDiagrams];
}

- (void)readDataTypes
{
	NSMutableArray *types = [NSMutableArray array];
	for (NSXMLNode *node in [ORMChild(_modelElement, CORE, @"DataTypes") children]) {
		if ([node kind] != NSXMLElementKind) {
			continue;
		}
		ORMDataType *type = [[ORMDataType alloc] initWithElement:(NSXMLElement *)node model:self];
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
	ORMValueConstraint *constraint = [[ORMValueConstraint alloc] initWithElement:element model:self];
	NSMutableArray *ranges = [NSMutableArray array];
	for (NSXMLElement *rangeElement in ORMGrandchildren(element, CORE, @"ValueRanges", CORE, @"ValueRange")) {
		ORMValueRange *range = [[ORMValueRange alloc] initWithElement:rangeElement model:self];
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
		ORMObjectType *type = [[ORMObjectType alloc] initWithElement:element model:self];
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
		type.valueConstraint = [self valueConstraintIn:ORMChild(element, CORE, @"ValueRestriction")];
		[types addObject:type];
		[self registerElement:type];
	}
	_objectTypes = types;
}

- (ORMRole *)readRole:(NSXMLElement *)element of:(ORMFactType *)fact index:(NSUInteger)index
{
	ORMRole *role = [[ORMRole alloc] initWithElement:element model:self];
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
		ORMFactType *fact = [[ORMFactType alloc] initWithElement:element model:self];
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
		/* Derived when the rule says how, formally or in words. */
		NSXMLElement *rule = ORMChild(element, CORE, @"DerivationRule");
		fact.isDerived = ORMChild(rule, CORE, @"FactTypeDerivationPath") != nil
			|| ORMChild(rule, CORE, @"DerivationExpression") != nil;
		fact.providesPreferredIdentifier = ORMBoolAttribute(element, @"PreferredIdentificationPath", NO)
			|| ORMBoolAttribute(element, @"ProvidesPreferredIdentifier", NO);
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
			ORMReadingOrder *order = [[ORMReadingOrder alloc] initWithElement:orderElement model:self];
			order.factType = fact;
			order.roles = [self rolesIn:ORMChild(orderElement, CORE, @"RoleSequence")];
			NSMutableArray *readings = [NSMutableArray array];
			for (NSXMLElement *readingElement in ORMGrandchildren(orderElement, CORE, @"Readings", CORE,
			                                                      @"Reading")) {
				ORMReading *reading = [[ORMReading alloc] initWithElement:readingElement model:self];
				reading.readingOrder = order;
				reading.text = ORMChildText(readingElement, CORE, @"Data") ?: @"";
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
 * role that is not (or no longer) in the model is skipped. */
- (NSArray<ORMRole *> *)rolesIn:(NSXMLElement *)sequence
{
	NSMutableArray *roles = [NSMutableArray array];
	for (NSXMLElement *child in ORMChildren(sequence, CORE, @"Role")) {
		id role = [self elementWithId:ORMRef(child)];
		if ([role isKindOfClass:[ORMRole class]]) {
			[roles addObject:role];
		}
	}
	return roles;
}

- (ORMRoleSequence *)readSequence:(NSXMLElement *)element
{
	ORMRoleSequence *sequence = [[ORMRoleSequence alloc] initWithElement:element model:self];
	sequence.roles = [self rolesIn:element];
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
		ORMConstraint *constraint = [[ORMConstraint alloc] initWithElement:element model:self];
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
		ORMModelNote *note = [[ORMModelNote alloc] initWithElement:element model:self];
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

- (void)linkObjectTypes
{
	NSMutableDictionary *objectifications = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in self.objectTypes) {
		NSXMLElement *element = type.element;
		type.preferredIdentifier = [self elementWithId:ORMRef(ORMChild(element, CORE, @"PreferredIdentifier"))];
		NSXMLElement *nested = ORMChild(element, CORE, @"NestedPredicate");
		ORMFactType *fact = [self elementWithId:ORMRef(nested)];
		if ([fact isKindOfClass:[ORMFactType class]]) {
			type.nestedFactType = fact;
			fact.objectifyingType = type;
			NSString *objectificationId = ORMAttribute(nested, @"id");
			if (objectificationId != nil) {
				[objectifications setObject:fact forKey:objectificationId];
			}
		}
		NSXMLElement *dataType = ORMChild(element, CORE, @"ConceptualDataType");
		type.dataType = [self elementWithId:ORMRef(dataType)];
	}
	for (ORMFactType *fact in self.factTypes) {
		NSXMLElement *implied = ORMChild(fact.element, CORE, @"ImpliedByObjectification");
		if (implied != nil) {
			fact.impliedByFactType = [objectifications objectForKey:ORMRef(implied)];
		}
	}
}

- (void)linkFactTypes
{
	/* Players, proxies, and each fact type's internal constraints. */
	NSMutableDictionary *played = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			NSXMLElement *player = ORMChild(role.element, CORE, @"RolePlayer");
			ORMObjectType *type = [self elementWithId:ORMRef(player)];
			if ([type isKindOfClass:[ORMObjectType class]]) {
				role.player = type;
				NSMutableArray *roles = [played objectForKey:type.identifier];
				if (roles == nil) {
					roles = [NSMutableArray array];
					[played setObject:roles forKey:type.identifier];
				}
				[roles addObject:role];
			}
			/* A link fact type's proxy: <orm:RoleProxy id><orm:Role ref/></orm:RoleProxy>. */
			if ([[role.element localName] isEqualToString:@"RoleProxy"]) {
				role.proxiedRole = [self elementWithId:ORMRef(ORMChild(role.element, CORE, @"Role"))];
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
			ORMFactType *fact = [facts firstObject];
			NSMutableArray *list = [internal objectForKey:fact.identifier];
			if (list == nil) {
				list = [NSMutableArray array];
				[internal setObject:list forKey:fact.identifier];
			}
			[list addObject:constraint];
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
		if (fact.kind == ORMFactTypeSubtype && !fact.providesPreferredIdentifier) {
			ORMObjectType *sub = [[fact.roles firstObject] player];
			/* NORMA leaves the attribute out where it is true by default:
			 * a subtype with no identifier of its own is identified
			 * through its (first) supertype. */
			if (ORMAttribute(fact.element, @"PreferredIdentificationPath") == nil && sub.preferredIdentifier == nil
			    && [sub.supertypeFacts firstObject] == fact) {
				fact.providesPreferredIdentifier = YES;
			}
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
			}
			if (constraint.kind == ORMUniquenessConstraint && constraint.isInternal
			    && [[constraint allRoles] count] == 1) {
				role.isUnique = YES;
			}
		}
	}
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			role.constraints = [byRole objectForKey:role.identifier] ?: @[];
		}
	}
}

/* NORMA's reference modes, from the preferred identifiers: an entity
 * type identified by one role of a binary fact type it plays the other
 * role of, where the identifying role's player is a value type named as
 * a reference mode names it. */
- (void)deriveReferenceModes
{
	NSMutableSet *customUnits = [NSMutableSet setWithArray:ORMUnitReferenceModes()];
	NSMutableSet *customGeneral = [NSMutableSet set];
	for (NSXMLElement *custom in ORMGrandchildren(_modelElement, CORE, @"CustomReferenceModes", CORE,
	                                              @"CustomReferenceMode")) {
		NSString *name = ORMAttribute(custom, @"Name");
		NSXMLElement *kindRef = ORMChild(custom, CORE, @"Kind") ?: ORMChild(custom, CORE, @"ReferenceModeKind");
		NSXMLElement *kind = ORMElementWithId(_document, ORMRef(kindRef));
		NSString *type = ORMAttribute(kind, @"ReferenceModeType");
		if ([type isEqualToString:@"UnitBased"]) {
			[customUnits addObject:name];
		} else if ([type isEqualToString:@"General"]) {
			[customGeneral addObject:name];
		}
	}
	for (ORMObjectType *type in self.objectTypes) {
		ORMConstraint *identifier = type.preferredIdentifier;
		if (!type.isEntity || identifier == nil || !identifier.isInternal || [[identifier allRoles] count] != 1) {
			continue;
		}
		ORMRole *role = [[identifier allRoles] firstObject];
		ORMRole *opposite = [role oppositeRole];
		ORMObjectType *value = role.player;
		if (opposite.player != type || value == nil || value.kind != ORMValueType) {
			continue;
		}
		NSString *saved = ORMAttribute(type.element, @"_ReferenceMode");
		NSString *popularPrefix = [type.name stringByAppendingString:@"_"];
		NSString *mode = nil;
		ORMReferenceModeKind kind = ORMReferenceModeNone;
		if ([value.name hasPrefix:popularPrefix] && [value.name length] > [popularPrefix length]) {
			mode = [value.name substringFromIndex:[popularPrefix length]];
			kind = ORMReferenceModePopular;
		} else if ([value.name hasSuffix:@"Value"] && [value.name length] > 5) {
			NSString *unit = [value.name substringToIndex:[value.name length] - 5];
			if ([customUnits containsObject:unit] || [saved isEqualToString:unit]) {
				mode = unit;
				kind = ORMReferenceModeUnitBased;
			}
		}
		if (mode == nil && ([customGeneral containsObject:value.name] || [saved isEqualToString:value.name])) {
			mode = value.name;
			kind = ORMReferenceModeGeneral;
		}
		if (mode == nil) {
			continue;
		}
		type.referenceMode = mode;
		type.referenceModeKind = kind;
		type.referenceModeValueType = value;
		type.referenceModeFactType = role.factType;
		if (type.valueConstraint == nil) {
			type.valueConstraint = value.valueConstraint;
		}
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
			role.valueConstraint.valueType = player.kind == ORMValueType ? player : player.referenceModeValueType;
		}
	}
}

- (void)readDiagrams
{
	NSMutableArray *diagrams = [NSMutableArray array];
	NSXMLElement *root = [_document rootElement];
	if (root != _modelElement) {
		for (NSXMLElement *element in ORMChildren(root, ORMDiagramNamespace, @"ORMDiagram")) {
			ORMDiagram *diagram = [[ORMDiagram alloc] initWithElement:element model:self];
			[self registerElement:diagram];
			[diagram readShapes];
			[diagrams addObject:diagram];
		}
	}
	_diagrams = diagrams;
}

@end
