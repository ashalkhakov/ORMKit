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
ORMWriteRoleRefs(NSXMLDocument *document, NSXMLElement *container, NSArray<ORMRole *> *roles, ORMModel *model,
                 BOOL withIds, NSSet<NSString *> *gone)
{
	NSMutableArray *children = [NSMutableArray array];
	NSMutableArray *refs = [NSMutableArray array];
	for (NSXMLElement *child in ORMChildren(container, CORE, @"Role")) {
		if ([gone containsObject:ORMRef(child) ?: @""]) {
			/* A role the model has just taken away. */
			[child detach];
		} else if ([[model elementWithId:ORMRef(child)] isKindOfClass:[ORMRole class]]) {
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
		NSXMLElement *child = [kept objectForKey:identifier];
		if (child == nil) {
			/* A constraint's use of a role has an id of its own. */
			child = withIds ? ORMNewElementWithId(document, CORE, @"Role", nil) : ORMNewElement(document, CORE, @"Role");
			ORMSetAttribute(child, @"ref", identifier);
		}
		[container addChild:child];
	}
}

/* A range's inclusion as NORMA names it. */
static NSString *
ORMInclusionName(ORMRangeInclusion inclusion)
{
	return inclusion == ORMRangeOpen ? @"Open" : inclusion == ORMRangeClosed ? @"Closed" : @"NotSet";
}

/* NORMA's element for each kind of object type. */
static NSString *
ORMObjectTypeElementName(ORMObjectTypeKind kind)
{
	return kind == ORMValueType ? @"ValueType" : kind == ORMObjectifiedType ? @"ObjectifiedType" : @"EntityType";
}

/* NORMA's element for each kind of shape. */
static NSString *
ORMShapeElementName(ORMShapeKind kind)
{
	switch (kind) {
	case ORMShapeObjectType:
		return @"ObjectTypeShape";
	case ORMShapeFactType:
		return @"FactTypeShape";
	case ORMShapeReading:
		return @"ReadingShape";
	case ORMShapeRoleName:
		return @"RoleNameShape";
	case ORMShapeObjectifiedFactTypeName:
		return @"ObjectifiedFactTypeNameShape";
	case ORMShapeValueConstraint:
		return @"ValueConstraintShape";
	case ORMShapeExternalConstraint:
		return @"ExternalConstraintShape";
	case ORMShapeFrequencyConstraint:
		return @"FrequencyConstraintShape";
	case ORMShapeRingConstraint:
		return @"RingConstraintShape";
	case ORMShapeValueComparisonConstraint:
		return @"ValueComparisonConstraintShape";
	case ORMShapeModelNote:
		return @"ModelNoteShape";
	case ORMShapeUnknown:
		break;
	}
	return nil;
}

/* NORMA's element for each kind of constraint. */
static NSString *
ORMConstraintElementName(ORMConstraintKind kind)
{
	switch (kind) {
	case ORMUniquenessConstraint:
		return @"UniquenessConstraint";
	case ORMMandatoryConstraint:
		return @"MandatoryConstraint";
	case ORMFrequencyConstraint:
		return @"FrequencyConstraint";
	case ORMRingConstraint:
		return @"RingConstraint";
	case ORMSubsetConstraint:
		return @"SubsetConstraint";
	case ORMEqualityConstraint:
		return @"EqualityConstraint";
	case ORMExclusionConstraint:
		return @"ExclusionConstraint";
	case ORMValueComparisonConstraint:
		return @"ValueComparisonConstraint";
	}
	return nil;
}

/* The children of a container that are no element of the model's list:
 * taken away. */
static void
ORMDetachOthers(NSXMLElement *container, NSString *local, NSArray<ORMElement *> *elements)
{
	NSArray *kept = [elements valueForKey:@"element"];
	for (NSXMLElement *child in ORMChildren(container, CORE, local)) {
		if ([kept indexOfObjectIdenticalTo:child] == NSNotFound) {
			[child detach];
		}
	}
}

@implementation ORMNormaWriter
{
	NSXMLDocument *_document;
	/* The XML elements this writer made: written whole, as the editors
	 * made them, defaults spelled out where they did. */
	NSMutableSet<NSXMLElement *> *_made;
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

- (void)writeReferenceModes
{
	NSXMLElement *modelElement = self.model.modelElement;
	NSMutableSet *written = [NSMutableSet set];
	for (NSXMLElement *custom in ORMGrandchildren(modelElement, CORE, @"CustomReferenceModes", CORE,
	                                              @"CustomReferenceMode")) {
		[written addObject:ORMAttribute(custom, @"Name") ?: @""];
	}
	NSDictionary *customs = self.model.customReferenceModes;
	for (NSString *name in [[customs allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if ([written containsObject:name]) {
			continue;
		}
		NSString *kindName = [customs objectForKey:name];
		NSXMLElement *kinds = ORMEnsureChild(_document, modelElement, CORE, @"ReferenceModeKinds");
		NSString *kindId = nil;
		for (NSXMLElement *kind in ORMChildren(kinds, CORE, @"ReferenceModeKind")) {
			if ([ORMAttribute(kind, @"ReferenceModeType") isEqualToString:kindName]) {
				kindId = ORMAttribute(kind, @"id");
			}
		}
		if (kindId == nil) {
			NSXMLElement *kind = ORMNewElementWithId(_document, CORE, @"ReferenceModeKind", nil);
			ORMSetAttribute(kind, @"FormatString", [self.model.referenceModeFormats objectForKey:kindName]);
			ORMSetAttribute(kind, @"ReferenceModeType", kindName);
			[kinds addChild:kind];
			kindId = ORMAttribute(kind, @"id");
		}
		NSXMLElement *custom = ORMNewElementWithId(_document, CORE, @"CustomReferenceMode", nil);
		ORMSetAttribute(custom, @"Name", name);
		[custom addChild:ORMNewRef(_document, CORE, @"Kind", kindId)];
		[ORMEnsureChild(_document, modelElement, CORE, @"CustomReferenceModes") addChild:custom];
	}
}

/* After an element is replaced by a copy: the elements read from its
 * children point at the copies. */
- (void)rebindChildrenOf:(ORMObjectType *)type
{
	ORMValueConstraint *constraint = type.ownValueConstraint;
	if (constraint != nil) {
		NSXMLElement *restriction = ORMChild(type.element, CORE, @"ValueRestriction");
		for (NSXMLNode *node in [restriction children]) {
			if ([node kind] == NSXMLElementKind && [[node URI] isEqualToString:CORE]) {
				constraint.element = (NSXMLElement *)node;
			}
		}
		NSArray *ranges = ORMGrandchildren(constraint.element, CORE, @"ValueRanges", CORE, @"ValueRange");
		for (NSUInteger i = 0; i < MIN([ranges count], [constraint.ranges count]); i++) {
			[[constraint.ranges objectAtIndex:i] setElement:[ranges objectAtIndex:i]];
		}
	}
}

/* The XML element of an element an editor made, where NORMA keeps its
 * kind, with its id. */
- (void)makeElementOf:(ORMElement *)element
{
	NSXMLElement *made = nil;
	if ([element isKindOfClass:[ORMDataType class]]) {
		made = ORMNewElementWithId(_document, CORE, [(ORMDataType *)element typeName], element.identifier);
		[ORMEnsureChild(_document, self.model.modelElement, CORE, @"DataTypes") addChild:made];
	} else if ([element isKindOfClass:[ORMObjectType class]]) {
		made = ORMNewElementWithId(_document, CORE, ORMObjectTypeElementName([(ORMObjectType *)element kind]),
		                           element.identifier);
		[ORMEnsureChild(_document, self.model.modelElement, CORE, @"Objects") addChild:made];
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		ORMFactTypeKind kind = [(ORMFactType *)element kind];
		made = ORMNewElementWithId(_document, CORE,
		                           kind == ORMFactTypeSubtype ? @"SubtypeFact"
		                           : kind == ORMFactTypeImplied ? @"ImpliedFact" : @"Fact",
		                           element.identifier);
		/* The name NORMA derives is the normalizer's to keep up; a subtype
		 * or link fact type starts with one, which tells it to. */
		if (kind != ORMFactTypeOrdinary) {
			ORMSetAttribute(made, @"_Name", [(ORMFactType *)element savedDerivedName]);
		}
		[ORMEnsureChild(_document, self.model.modelElement, CORE, @"Facts") addChild:made];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		made = ORMNewElementWithId(_document, CORE, ORMConstraintElementName([(ORMConstraint *)element kind]),
		                           element.identifier);
		[ORMEnsureChild(_document, self.model.modelElement, CORE, @"Constraints") addChild:made];
	} else if ([element isKindOfClass:[ORMDiagram class]]) {
		/* As NORMA starts one: its base font spelled out, in inches. */
		ORMDiagram *diagram = (ORMDiagram *)element;
		made = ORMNewElementWithId(_document, DIAGRAM, @"ORMDiagram", element.identifier);
		ORMSetAttribute(made, @"IsCompleteView", diagram.isCompleteView ? @"true" : @"false");
		ORMSetAttribute(made, @"Name", diagram.name);
		ORMSetAttribute(made, @"BaseFontName", diagram.baseFontName);
		NSString *normaSize = @"0.0972222238779068";
		ORMSetAttribute(made, @"BaseFontSize", diagram.baseFontSize == [normaSize doubleValue] * ORMPointsPerInch
		                                       ? normaSize
		                                       : [NSString stringWithFormat:@"%g", diagram.baseFontSize / ORMPointsPerInch]);
		[made addChild:ORMNewRef(_document, DIAGRAM, @"Subject", self.model.identifier)];
		/* After the last diagram, before what NORMA's extensions keep. */
		NSXMLElement *root = [_document rootElement];
		NSArray *diagrams = ORMChildren(root, DIAGRAM, @"ORMDiagram");
		NSUInteger index = [diagrams count] > 0 ? [[diagrams lastObject] index] + 1 : [root childCount];
		[root insertChild:made atIndex:index];
	} else if ([element isKindOfClass:[ORMShape class]]) {
		ORMShape *shape = (ORMShape *)element;
		made = ORMNewElementWithId(_document, DIAGRAM, ORMShapeElementName(shape.kind), element.identifier);
		ORMSetAttribute(made, @"IsExpanded", shape.isExpanded ? @"true" : @"false");
		ORMSetAttribute(made, @"AbsoluteBounds", ORMFormatBounds(shape.bounds));
		ORMInsertChild(made, ORMNewRef(_document, DIAGRAM, @"Subject", shape.subjectId));
		if (shape.parent != nil) {
			NSXMLElement *relative = ORMChild(shape.parent.element, DIAGRAM, @"RelativeShapes");
			if (relative == nil) {
				relative = ORMNewElement(_document, DIAGRAM, @"RelativeShapes");
				ORMInsertChild(shape.parent.element, relative);
			}
			[relative addChild:made];
		} else {
			NSXMLElement *shapes = ORMChild(shape.diagram.element, DIAGRAM, @"Shapes");
			if (shapes == nil) {
				shapes = ORMNewElement(_document, DIAGRAM, @"Shapes");
				/* Shapes come before the diagram's Subject. */
				[shape.diagram.element insertChild:shapes atIndex:0];
			}
			[shapes addChild:made];
		}
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		ORMModelNote *note = (ORMModelNote *)element;
		made = ORMNewElementWithId(_document, CORE, @"ModelNote", element.identifier);
		ORMSetChildText(_document, made, CORE, @"Text", note.text ?: @"");
		if ([note.referencedElements count] > 0) {
			NSXMLElement *references = ORMNewElement(_document, CORE, @"ReferencedBy");
			for (ORMElement *referenced in note.referencedElements) {
				NSString *local = [referenced isKindOfClass:[ORMObjectType class]] ? @"ObjectType"
					: [referenced isKindOfClass:[ORMFactType class]] ? @"FactType" : @"Constraint";
				[references addChild:ORMNewRef(_document, CORE, local, referenced.identifier)];
			}
			[made addChild:references];
		}
		[ORMEnsureChild(_document, self.model.modelElement, CORE, @"ModelNotes") addChild:made];
	} else {
		[NSException raise:NSInternalInconsistencyException format:@"The writer makes no %@ yet.", [element class]];
	}
	element.element = made;
	_made = _made ?: [NSMutableSet set];
	[_made addObject:made];
}

- (void)writeElement:(ORMElement *)element
{
	if (element == nil) {
		return;
	}
	if (element.element == nil) {
		[self makeElementOf:element];
	}
	if ([element isKindOfClass:[ORMObjectType class]]) {
		[self writeObjectType:(ORMObjectType *)element];
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		[self writeFactType:(ORMFactType *)element];
	} else if ([element isKindOfClass:[ORMRole class]]) {
		[self writeRole:(ORMRole *)element];
	} else if ([element isKindOfClass:[ORMReadingOrder class]]) {
		ORMWriteRoleRefs(_document, ORMChild(element.element, CORE, @"RoleSequence"), [(ORMReadingOrder *)element roles],
		                 self.model, NO, self.gone);
	} else if ([element isKindOfClass:[ORMReading class]]) {
		[self writeReading:(ORMReading *)element];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		[self writeConstraint:(ORMConstraint *)element];
	} else if ([element isKindOfClass:[ORMRoleSequence class]]) {
		ORMWriteRoleRefs(_document, element.element, [(ORMRoleSequence *)element roles], self.model, YES, self.gone);
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

/* A fact type's roles, reading orders and readings: those the model made
 * made, as NORMA writes them, those it took away gone. */
- (void)writePartsOf:(ORMFactType *)fact
{
	NSXMLElement *element = fact.element;
	NSXMLElement *roles = ORMChild(element, CORE, @"FactRoles");
	for (ORMRole *role in fact.roles) {
		if (role.element == nil && role.proxiedRole != nil) {
			/* A link fact type's proxy: the role it stands for, nothing more. */
			NSXMLElement *made = ORMNewElementWithId(_document, CORE, @"RoleProxy", role.identifier);
			[made addChild:ORMNewRef(_document, CORE, @"Role", role.proxiedRole.identifier)];
			roles = roles ?: ORMEnsureChild(_document, element, CORE, @"FactRoles");
			[roles addChild:made];
			role.element = made;
		} else if (role.element == nil) {
			NSString *local = role.isSubtypeMetaRole ? @"SubtypeMetaRole"
				: role.isSupertypeMetaRole ? @"SupertypeMetaRole" : @"Role";
			NSXMLElement *made = ORMNewElementWithId(_document, CORE, local, role.identifier);
			ORMSetAttribute(made, @"_IsMandatory", @"false");
			ORMSetAttribute(made, @"_Multiplicity", @"Unspecified");
			ORMSetAttribute(made, @"Name", role.name ?: @"");
			roles = roles ?: ORMEnsureChild(_document, element, CORE, @"FactRoles");
			[roles addChild:made];
			role.element = made;
			[self writeRole:role];
		}
	}
	NSXMLElement *orders = ORMChild(element, CORE, @"ReadingOrders");
	ORMDetachOthers(orders, @"ReadingOrder", fact.readingOrders);
	for (ORMReadingOrder *order in fact.readingOrders) {
		if (order.element == nil) {
			NSXMLElement *made = ORMNewElementWithId(_document, CORE, @"ReadingOrder", order.identifier);
			[made addChild:ORMNewElement(_document, CORE, @"Readings")];
			[made addChild:ORMNewElement(_document, CORE, @"RoleSequence")];
			orders = orders ?: ORMEnsureChild(_document, element, CORE, @"ReadingOrders");
			[orders addChild:made];
			order.element = made;
			ORMWriteRoleRefs(_document, ORMChild(made, CORE, @"RoleSequence"), order.roles, self.model, NO, self.gone);
		}
		NSXMLElement *readings = ORMChild(order.element, CORE, @"Readings");
		ORMDetachOthers(readings, @"Reading", order.readings);
		for (ORMReading *reading in order.readings) {
			if (reading.element == nil) {
				NSXMLElement *made = ORMNewElementWithId(_document, CORE, @"Reading", reading.identifier);
				NSXMLElement *data = ORMNewElement(_document, CORE, @"Data");
				[data setStringValue:reading.text ?: @""];
				[made addChild:data];
				[readings addChild:made];
				reading.element = made;
			}
		}
	}
}

/* A constraint's role sequences: one of its own where it has one without
 * an id, else each in RoleSequences with its id; each role used with an id
 * of its own. */
- (void)writeSequencesOf:(ORMConstraint *)constraint
{
	for (ORMRoleSequence *sequence in constraint.roleSequences) {
		if (sequence.element == nil) {
			NSXMLElement *made = sequence.identifier != nil
				? ORMNewElementWithId(_document, CORE, @"RoleSequence", sequence.identifier)
				: ORMNewElement(_document, CORE, @"RoleSequence");
			NSXMLElement *parent = sequence.identifier != nil
				? ORMEnsureChild(_document, constraint.element, CORE, @"RoleSequences")
				: constraint.element;
			[parent addChild:made];
			sequence.element = made;
			ORMWriteRoleRefs(_document, made, sequence.roles, self.model, YES, self.gone);
		}
	}
}

- (void)writeFactType:(ORMFactType *)fact
{
	NSXMLElement *element = fact.element;
	[self writePartsOf:fact];
	if (fact.impliedByFactType != nil) {
		ORMWriteRef(_document, element, @"ImpliedByObjectification",
		            fact.impliedByFactType.objectifyingType.objectificationId);
	}
	/* A name given it; one NORMA derives (_Name) is the normalizer's. */
	if (![ORMAttribute(element, @"Name") ?: @"" isEqualToString:fact.explicitName ?: @""]
	    || (ORMAttribute(element, @"Name") == nil) != (fact.explicitName == nil)) {
		ORMSetAttribute(element, @"Name", fact.explicitName);
	}
	NSNumber *path = fact.preferredIdentificationPath;
	if (path == nil) {
		ORMSetAttribute(element, @"PreferredIdentificationPath", nil);
	} else if (ORMBoolAttribute(element, @"PreferredIdentificationPath", NO) != [path boolValue]
	           || ORMAttribute(element, @"PreferredIdentificationPath") == nil) {
		ORMSetAttribute(element, @"PreferredIdentificationPath", [path boolValue] ? @"true" : @"false");
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
	[self writeValueConstraint:role.valueConstraint of:element as:@"RoleValueConstraint"];
}

/* An element's value constraint in its ValueRestriction: made where the
 * model made one, taken away where it took it away. */
- (void)writeValueConstraint:(ORMValueConstraint *)values of:(NSXMLElement *)owner as:(NSString *)local
{
	if (values == nil) {
		[ORMChild(owner, CORE, @"ValueRestriction") detach];
		return;
	}
	if (values.element == nil) {
		NSXMLElement *restriction = ORMEnsureChild(_document, owner, CORE, @"ValueRestriction");
		NSXMLElement *made = ORMNewElementWithId(_document, CORE, local, values.identifier);
		ORMSetAttribute(made, @"Name", values.name);
		[restriction addChild:made];
		values.element = made;
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
	[self writeSequencesOf:constraint];
	NSString *modality = ORMAttribute(element, @"Modality");
	if ((constraint.modality == ORMDeontic) != [modality isEqualToString:@"Deontic"]) {
		ORMSetAttribute(element, @"Modality", constraint.modality == ORMDeontic ? @"Deontic" : nil);
	}
	ORMWriteBool(element, @"IsInternal", constraint.isInternal, NO);
	ORMWriteBool(element, @"IsSimple", constraint.isSimple, NO);
	ORMWriteBool(element, @"IsImplied", constraint.isImplied, NO);
	ORMWriteRef(_document, element, @"ImpliedByObjectType", constraint.impliedByObjectTypeId);
	/* An exclusive-or: the exclusion and the mandatory name each other. */
	if (constraint.kind == ORMExclusionConstraint) {
		ORMWriteRef(_document, element, @"ExclusiveOrMandatoryConstraint", constraint.exclusiveOrPartner.identifier);
	} else if (constraint.kind == ORMMandatoryConstraint) {
		ORMWriteRef(_document, element, @"ExclusiveOrExclusionConstraint", constraint.exclusiveOrPartner.identifier);
	}
	if (constraint.kind == ORMFrequencyConstraint && [_made containsObject:element]) {
		ORMSetAttribute(element, @"MinFrequency", [NSString stringWithFormat:@"%lu", (unsigned long)constraint.minFrequency]);
		ORMSetAttribute(element, @"MaxFrequency", [NSString stringWithFormat:@"%lu", (unsigned long)constraint.maxFrequency]);
	} else if (constraint.kind == ORMFrequencyConstraint) {
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
	/* The ranges the model has, in its order: those it took away gone,
	 * those it made made, as NORMA writes a range. */
	NSXMLElement *container = ORMChild(values.element, CORE, @"ValueRanges");
	NSArray *kept = [values.ranges valueForKey:@"element"];
	for (NSXMLElement *child in ORMChildren(container, CORE, @"ValueRange")) {
		if ([kept indexOfObjectIdenticalTo:child] == NSNotFound) {
			[child detach];
		}
	}
	for (ORMValueRange *range in values.ranges) {
		if (range.element == nil) {
			container = container ?: ORMEnsureChild(_document, values.element, CORE, @"ValueRanges");
			NSXMLElement *made = ORMNewElementWithId(_document, CORE, @"ValueRange", range.identifier);
			ORMSetAttribute(made, @"MinValue", range.minValue ?: @"");
			ORMSetAttribute(made, @"MaxValue", range.maxValue ?: @"");
			ORMSetAttribute(made, @"MinInclusion", ORMInclusionName(range.minInclusion));
			ORMSetAttribute(made, @"MaxInclusion", ORMInclusionName(range.maxInclusion));
			[container addChild:made];
			range.element = made;
		}
	}
	if ([values.ranges count] == 0) {
		[container detach];
	}
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

/* A fact type shape's roles left to right, compared as the reader reads
 * them: its RoleDisplayOrder where that names every role, else the fact
 * type's order. Made where the model has an order and the shape none. */
- (void)writeRoleDisplayOrderOf:(ORMShape *)shape
{
	NSXMLElement *order = ORMChild(shape.element, DIAGRAM, @"RoleDisplayOrder");
	NSArray *factRoles = shape.factType.roles ?: @[];
	NSMutableArray *read = [NSMutableArray array];
	for (NSXMLElement *ref in ORMChildren(order, DIAGRAM, @"Role")) {
		id role = [self.model elementWithId:ORMRef(ref)];
		if ([role isKindOfClass:[ORMRole class]] && [factRoles indexOfObjectIdenticalTo:role] != NSNotFound) {
			[read addObject:role];
		}
	}
	NSArray *now = [read count] == [factRoles count] ? read : factRoles;
	if (order != nil && [now isEqualToArray:shape.roleDisplayOrder]) {
		return;
	}
	if (order == nil && ![_made containsObject:shape.element] && [now isEqualToArray:shape.roleDisplayOrder]) {
		return;
	}
	[order detach];
	NSXMLElement *display = ORMNewElement(_document, DIAGRAM, @"RoleDisplayOrder");
	for (ORMRole *role in shape.roleDisplayOrder) {
		[display addChild:ORMNewRef(_document, DIAGRAM, @"Role", role.identifier)];
	}
	ORMInsertChild(shape.element, display);
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
		/* Horizontal is NORMA's default, left out. */
		ORMSetAttribute(element, @"DisplayOrientation", shape.orientation == ORMFactTypeVerticalRotatedRight ? @"VerticalRotatedRight"
		                                                : shape.orientation == ORMFactTypeVerticalRotatedLeft ? @"VerticalRotatedLeft"
		                                                                                                      : nil);
	}
	if (shape.kind == ORMShapeFactType) {
		[self writeRoleDisplayOrderOf:shape];
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
	NSString *local = ORMObjectTypeElementName(type.kind);
	if (![[element localName] isEqualToString:local]) {
		/* Another kind: the same attributes and children under its name. */
		NSXMLElement *replacement = ORMNewElement(_document, CORE, local);
		for (NSXMLNode *attribute in [element attributes]) {
			[replacement addAttribute:[attribute copy]];
		}
		for (NSXMLNode *child in [element children]) {
			[replacement addChild:[child copy]];
		}
		/* Inserted beside it and the old one detached: gnustep-base's
		 * -replaceChildAtIndex:withNode: frees what libxml2 keeps in the
		 * document's dictionary. */
		[(NSXMLElement *)[element parent] insertChild:replacement atIndex:[element index]];
		[element detach];
		element = replacement;
		type.element = element;
		[self rebindChildrenOf:type];
	}
	ORMSetAttribute(element, @"Name", type.name);
	[self writeValueConstraint:type.ownValueConstraint of:element as:@"ValueConstraint"];
	if (type.kind != ORMValueType || type.dataType == nil) {
		[ORMChild(element, CORE, @"ConceptualDataType") detach];
	}
	ORMWriteBool(element, @"IsIndependent", type.isIndependent, NO);
	ORMWriteBool(element, @"IsExternal", type.isExternal, NO);
	ORMWriteBool(element, @"IsPersonal", type.isPersonal, NO);
	ORMWriteBool(element, @"IsImplicitBooleanValue", type.isImplicitBooleanValue, NO);
	if (type.savedReferenceMode == nil) {
		ORMSetAttribute(element, @"_ReferenceMode", nil);
	} else if (![ORMAttribute(element, @"_ReferenceMode") isEqualToString:type.savedReferenceMode]) {
		ORMSetAttribute(element, @"_ReferenceMode", type.savedReferenceMode);
	}
	ORMWriteNested(_document, element, @"Definitions", @"Definition", type.definitionText);
	ORMWriteNested(_document, element, @"Notes", @"Note", type.noteText);
	if (type.kind == ORMValueType) {
		NSXMLElement *dataType = ORMChild(element, CORE, @"ConceptualDataType");
		if (dataType == nil && type.dataType != nil) {
			/* NORMA gives it an id, and spells out its scale and length. */
			dataType = ORMNewElementWithId(_document, CORE, @"ConceptualDataType", nil);
			ORMSetAttribute(dataType, @"ref", type.dataType.identifier);
			ORMSetAttribute(dataType, @"Scale", @"0");
			ORMSetAttribute(dataType, @"Length", @"0");
			ORMInsertChild(element, dataType);
		} else if (type.dataType != nil) {
			ORMWriteRef(_document, element, @"ConceptualDataType", type.dataType.identifier);
		}
		ORMWriteInteger(dataType, @"Length", type.dataTypeLength, 0);
		ORMWriteInteger(dataType, @"Scale", type.dataTypeScale, 0);
	}
	ORMWriteRef(_document, element, @"PreferredIdentifier", type.preferredIdentifier.identifier);
	if (type.nestedFactType != nil && ORMChild(element, CORE, @"NestedPredicate") == nil) {
		/* NORMA gives the objectification an id, and spells IsImplied out. */
		NSXMLElement *nested = ORMNewElementWithId(_document, CORE, @"NestedPredicate", type.objectificationId);
		ORMSetAttribute(nested, @"ref", type.nestedFactType.identifier);
		ORMSetAttribute(nested, @"IsImplied", type.isImplied ? @"true" : @"false");
		ORMInsertChild(element, nested);
	} else if (type.nestedFactType != nil) {
		ORMWriteRef(_document, element, @"NestedPredicate", type.nestedFactType.identifier);
		ORMWriteBool(ORMChild(element, CORE, @"NestedPredicate"), @"IsImplied", type.isImplied, NO);
	}
}

@end
