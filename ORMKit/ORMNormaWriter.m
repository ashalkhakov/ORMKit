/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMNormaWriter.h"
#import "ORMModelPriv.h"
#import "ORMXML.h"
#import "ORMDiagram.h"

#define CORE ORMCoreNamespace
#define DIAGRAM ORMDiagramNamespace

#pragma mark Values as NORMA writes them

/* A boolean attribute: left as it is where it reads as the value, so a
 * default the file spells out stays; else NORMA's way, the default left
 * out. */
static void
ORMWriteBool(NSXMLElement *element, NSString *name, BOOL value, BOOL fallback)
{
	if (element == nil || ORMBoolAttribute(element, name, fallback) == value) {
		return;
	}
	ORMSetAttribute(element, name, value == fallback ? nil : (value ? @"true" : @"false"));
}

/* A whole number: left as it is where it reads as the value; else
 * written, or left out where it is the default and NORMA leaves it out. */
static void
ORMWriteInteger(NSXMLElement *element, NSString *name, NSInteger value, NSInteger fallback)
{
	NSString *now = ORMAttribute(element, name);
	if (element == nil || (now != nil ? [now integerValue] == value : value == fallback)) {
		return;
	}
	ORMSetAttribute(element, name, value == fallback && now == nil ? nil : [NSString stringWithFormat:@"%ld", (long)value]);
}

/* A reference, <prefix:local ref="id"/>: made, pointed elsewhere, or
 * taken away (nil). */
static void
ORMWriteRef(NSXMLDocument *document, NSXMLElement *parent, NSString *local, NSString *target)
{
	NSXMLElement *existing = ORMChild(parent, CORE, local);
	if (target == nil) {
		[existing detach];
	} else if (existing == nil) {
		ORMInsertChild(parent, ORMNewRef(document, CORE, local, target));
	} else if (![ORMRef(existing) isEqualToString:target]) {
		ORMSetAttribute(existing, @"ref", target);
	}
}

/* NORMA's Definitions/Definition/Text, or Notes/Note/Text: the first
 * item's text, the container gone with the text. */
static void
ORMWriteNested(NSXMLDocument *document, NSXMLElement *owner, NSString *container, NSString *item, NSString *text)
{
	NSXMLElement *outer = ORMChild(owner, CORE, container);
	NSXMLElement *inner = [ORMChildren(outer, CORE, item) firstObject];
	if ([ORMChildText(inner, CORE, @"Text") ?: @"" isEqualToString:text ?: @""]) {
		return;
	}
	if ([text length] == 0) {
		[outer detach];
		return;
	}
	outer = outer ?: ORMEnsureChild(document, owner, CORE, container);
	if (inner == nil) {
		inner = ORMNewElementWithId(document, CORE, item, nil);
		[outer addChild:inner];
	}
	ORMSetChildText(document, inner, CORE, @"Text", text);
}

/* A text attribute: written where it differs; one the file leaves out is
 * left out while the value is empty. */
static void
ORMWriteText(NSXMLElement *element, NSString *name, NSString *value)
{
	NSString *now = ORMAttribute(element, name);
	if (element == nil || [now ?: @"" isEqualToString:value ?: @""]) {
		return;
	}
	ORMSetAttribute(element, name, [value length] == 0 && now == nil ? nil : value ?: @"");
}

/* The role references a container lists, in the order given: those it
 * has kept, with their own ids, the rest made, any other taken away. A
 * reference to a role the model does not have (a file NORMA left so) is
 * the file's: the model reads past it, and so does the writer. */
static void
ORMWriteRoleRefs(NSXMLDocument *document, NSXMLElement *container, NSArray<ORMRole *> *roles, ORMModel *model)
{
	NSMutableArray *children = [NSMutableArray array];
	NSMutableArray *refs = [NSMutableArray array];
	for (NSXMLElement *child in ORMChildren(container, CORE, @"Role")) {
		if ([[model elementWithId:ORMRef(child)] isKindOfClass:[ORMRole class]]) {
			[children addObject:child];
			[refs addObject:ORMRef(child)];
		}
	}
	NSArray *wanted = [roles valueForKey:@"identifier"];
	if (container == nil || [refs isEqualToArray:wanted]) {
		return;
	}
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	for (NSXMLElement *child in children) {
		[kept setObject:child forKey:ORMRef(child) ?: @""];
		[child detach];
	}
	for (NSString *identifier in wanted) {
		NSXMLElement *child = [kept objectForKey:identifier] ?: ORMNewRef(document, CORE, @"Role", identifier);
		[container addChild:child];
	}
}

/* A range's inclusion as NORMA names it. */
static NSString *
ORMInclusionName(ORMRangeInclusion inclusion)
{
	return inclusion == ORMRangeOpen ? @"Open" : inclusion == ORMRangeClosed ? @"Closed" : @"NotSet";
}

@implementation ORMNormaWriter
{
	NSXMLDocument *_document;
}

- (instancetype)initWithModel:(ORMModel *)model
{
	if ((self = [super init])) {
		_model = model;
		_document = [model.modelElement rootDocument];
	}
	return self;
}

- (void)writeModel
{
	for (ORMObjectType *type in self.model.objectTypes) {
		[self writeElement:type];
		[self writeElement:type.ownValueConstraint];
	}
	for (ORMFactType *fact in self.model.factTypes) {
		[self writeElement:fact];
		for (ORMRole *role in fact.roles) {
			[self writeElement:role];
			[self writeElement:role.valueConstraint];
		}
		for (ORMReadingOrder *order in fact.readingOrders) {
			[self writeElement:order];
			for (ORMReading *reading in order.readings) {
				[self writeElement:reading];
			}
		}
	}
	for (ORMConstraint *constraint in self.model.constraints) {
		[self writeElement:constraint];
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			[self writeElement:sequence];
		}
	}
	for (ORMModelNote *note in self.model.notes) {
		[self writeElement:note];
	}
	for (ORMDiagram *diagram in self.model.diagrams) {
		[self writeElement:diagram];
		for (ORMShape *shape in [diagram allShapes]) {
			[self writeElement:shape];
		}
	}
}

- (void)writeElement:(ORMElement *)element
{
	if (element == nil) {
		return;
	}
	if ([element isKindOfClass:[ORMObjectType class]]) {
		[self writeObjectType:(ORMObjectType *)element];
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		[self writeFactType:(ORMFactType *)element];
	} else if ([element isKindOfClass:[ORMRole class]]) {
		[self writeRole:(ORMRole *)element];
	} else if ([element isKindOfClass:[ORMReadingOrder class]]) {
		ORMWriteRoleRefs(_document, ORMChild(element.element, CORE, @"RoleSequence"), [(ORMReadingOrder *)element roles],
		                 self.model);
	} else if ([element isKindOfClass:[ORMReading class]]) {
		[self writeReading:(ORMReading *)element];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		[self writeConstraint:(ORMConstraint *)element];
	} else if ([element isKindOfClass:[ORMRoleSequence class]]) {
		ORMWriteRoleRefs(_document, element.element, [(ORMRoleSequence *)element roles], self.model);
	} else if ([element isKindOfClass:[ORMValueConstraint class]]) {
		[self writeValueConstraint:(ORMValueConstraint *)element];
	} else if ([element isKindOfClass:[ORMDiagram class]]) {
		[self writeDiagram:(ORMDiagram *)element];
	} else if ([element isKindOfClass:[ORMShape class]]) {
		[self writeShape:(ORMShape *)element];
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		NSString *text = [(ORMModelNote *)element text];
		if (![ORMChildText(element.element, CORE, @"Text") ?: @"" isEqualToString:text ?: @""]) {
			ORMSetChildText(_document, element.element, CORE, @"Text", text ?: @"");
		}
	}
}

#pragma mark Fact types

- (void)writeFactType:(ORMFactType *)fact
{
	NSXMLElement *element = fact.element;
	/* A name given it; one NORMA derives (_Name) is the normalizer's. */
	if (ORMAttribute(element, @"Name") != nil) {
		ORMWriteText(element, @"Name", fact.name);
	}
	ORMWriteNested(_document, element, @"Definitions", @"Definition", fact.definitionText);
	ORMWriteNested(_document, element, @"Notes", @"Note", fact.noteText);
}

- (void)writeRole:(ORMRole *)role
{
	NSXMLElement *element = role.element;
	ORMWriteText(element, @"Name", role.name);
	/* A link fact type's proxy plays through the role it stands for. */
	if (role.proxiedRole == nil) {
		ORMWriteRef(_document, element, @"RolePlayer", role.player.identifier);
	}
}

- (void)writeReading:(ORMReading *)reading
{
	if (![ORMChildText(reading.element, CORE, @"Data") ?: @"" isEqualToString:reading.text ?: @""]) {
		ORMSetChildText(_document, reading.element, CORE, @"Data", reading.text ?: @"");
	}
}

#pragma mark Constraints and values

- (void)writeConstraint:(ORMConstraint *)constraint
{
	NSXMLElement *element = constraint.element;
	ORMWriteText(element, @"Name", constraint.name);
	NSString *modality = ORMAttribute(element, @"Modality");
	if ((constraint.modality == ORMDeontic) != [modality isEqualToString:@"Deontic"]) {
		ORMSetAttribute(element, @"Modality", constraint.modality == ORMDeontic ? @"Deontic" : nil);
	}
	ORMWriteBool(element, @"IsInternal", constraint.isInternal, NO);
	ORMWriteBool(element, @"IsSimple", constraint.isSimple, NO);
	ORMWriteBool(element, @"IsImplied", constraint.isImplied, NO);
	if (constraint.kind == ORMFrequencyConstraint) {
		ORMWriteInteger(element, @"MinFrequency", constraint.minFrequency, 1);
		ORMWriteInteger(element, @"MaxFrequency", constraint.maxFrequency, 0);
	}
	if (constraint.kind == ORMRingConstraint
	    && [ORMConstraint ringTypeNamed:ORMAttribute(element, @"Type")] != constraint.ringType) {
		ORMSetAttribute(element, @"Type", [ORMConstraint nameOfRingType:constraint.ringType]);
	}
	if (constraint.kind == ORMValueComparisonConstraint) {
		ORMWriteText(element, @"Operator", constraint.comparisonOperator);
	}
}

- (void)writeValueConstraint:(ORMValueConstraint *)values
{
	for (ORMValueRange *range in values.ranges) {
		NSXMLElement *element = range.element;
		ORMWriteText(element, @"MinValue", range.minValue);
		ORMWriteText(element, @"MaxValue", range.maxValue);
		for (NSArray *pair in @[ @[ @"MinInclusion", @(range.minInclusion) ], @[ @"MaxInclusion", @(range.maxInclusion) ] ]) {
			NSString *now = ORMAttribute(element, [pair firstObject]);
			ORMRangeInclusion inclusion = (ORMRangeInclusion)[[pair lastObject] integerValue];
			BOOL same = [now isEqualToString:ORMInclusionName(inclusion)]
			            || (now == nil && inclusion == ORMRangeInclusionNotSet);
			if (!same) {
				ORMSetAttribute(element, [pair firstObject], ORMInclusionName(inclusion));
			}
		}
	}
}

#pragma mark Diagrams

- (void)writeDiagram:(ORMDiagram *)diagram
{
	NSXMLElement *element = diagram.element;
	ORMWriteText(element, @"Name", diagram.name);
	ORMWriteBool(element, @"IsCompleteView", diagram.isCompleteView, NO);
	/* Tahoma where the file names none. */
	NSString *font = ORMAttribute(element, @"BaseFontName");
	if (![font ?: @"Tahoma" isEqualToString:diagram.baseFontName]) {
		ORMSetAttribute(element, @"BaseFontName", diagram.baseFontName);
	}
	/* In inches in the file, compared as read. */
	NSString *size = ORMAttribute(element, @"BaseFontSize");
	double now = size != nil ? [size doubleValue] * ORMPointsPerInch : 7.0;
	if (now != diagram.baseFontSize) {
		ORMSetAttribute(element, @"BaseFontSize", [NSString stringWithFormat:@"%g", diagram.baseFontSize / ORMPointsPerInch]);
	}
}

- (void)writeShape:(ORMShape *)shape
{
	NSXMLElement *element = shape.element;
	/* Bounds in inches in the file: compared as read, so that NORMA's
	 * digits stay where they say the same. */
	if (!NSEqualRects(ORMParseBounds(ORMAttribute(element, @"AbsoluteBounds")), shape.bounds)) {
		ORMSetAttribute(element, @"AbsoluteBounds", ORMFormatBounds(shape.bounds));
	}
	ORMWriteBool(element, @"IsExpanded", shape.isExpanded, NO);
	ORMWriteBool(element, @"ExpandRefMode", shape.expandsReferenceMode, NO);
	NSString *orientation = ORMAttribute(element, @"DisplayOrientation");
	ORMFactTypeOrientation was = [orientation isEqualToString:@"VerticalRotatedRight"] ? ORMFactTypeVerticalRotatedRight
		: [orientation isEqualToString:@"VerticalRotatedLeft"] ? ORMFactTypeVerticalRotatedLeft : ORMFactTypeHorizontal;
	if (was != shape.orientation) {
		ORMSetAttribute(element, @"DisplayOrientation", shape.orientation == ORMFactTypeVerticalRotatedRight ? @"VerticalRotatedRight"
		                                                : shape.orientation == ORMFactTypeVerticalRotatedLeft ? @"VerticalRotatedLeft"
		                                                                                                      : @"Horizontal");
	}
	BOOL below = [ORMAttribute(element, @"ConstraintDisplayPosition") isEqualToString:@"Bottom"];
	if (below != shape.constraintsBelow) {
		ORMSetAttribute(element, @"ConstraintDisplayPosition", shape.constraintsBelow ? @"Bottom" : @"Top");
	}
	NSXMLElement *subject = ORMChild(element, DIAGRAM, @"Subject");
	if (shape.subjectId != nil && ![ORMRef(subject) isEqualToString:shape.subjectId]) {
		ORMSetAttribute(subject, @"ref", shape.subjectId);
	}
}

#pragma mark Object types

- (void)writeObjectType:(ORMObjectType *)type
{
	NSXMLElement *element = type.element;
	ORMSetAttribute(element, @"Name", type.name);
	ORMWriteBool(element, @"IsIndependent", type.isIndependent, NO);
	ORMWriteBool(element, @"IsExternal", type.isExternal, NO);
	ORMWriteBool(element, @"IsPersonal", type.isPersonal, NO);
	ORMWriteBool(element, @"IsImplicitBooleanValue", type.isImplicitBooleanValue, NO);
	ORMWriteNested(_document, element, @"Definitions", @"Definition", type.definitionText);
	ORMWriteNested(_document, element, @"Notes", @"Note", type.noteText);
	if (type.kind == ORMValueType) {
		NSXMLElement *dataType = ORMChild(element, CORE, @"ConceptualDataType");
		if (type.dataType != nil) {
			ORMWriteRef(_document, element, @"ConceptualDataType", type.dataType.identifier);
			dataType = ORMChild(element, CORE, @"ConceptualDataType");
		}
		ORMWriteInteger(dataType, @"Length", type.dataTypeLength, 0);
		ORMWriteInteger(dataType, @"Scale", type.dataTypeScale, 0);
	}
	ORMWriteRef(_document, element, @"PreferredIdentifier", type.preferredIdentifier.identifier);
	if (type.nestedFactType != nil) {
		ORMWriteRef(_document, element, @"NestedPredicate", type.nestedFactType.identifier);
		ORMWriteBool(ORMChild(element, CORE, @"NestedPredicate"), @"IsImplied", type.isImplied, NO);
	}
}

@end
