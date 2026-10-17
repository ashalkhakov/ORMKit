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
		ORMDetach(existing);
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
		ORMDetach(outer);
		return;
	}
	outer = outer ?: ORMEnsureChild(document, owner, CORE, container);
	if (inner == nil) {
		inner = ORMNewElementWithId(document, CORE, item, nil);
		ORMAddChild(outer, inner);
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
                 NSArray<NSString *> *useIds, NSSet<NSString *> *gone)
{
	NSMutableArray *children = [NSMutableArray array];
	NSMutableArray *refs = [NSMutableArray array];
	NSMutableArray *ids = [NSMutableArray array];
	for (NSXMLElement *child in ORMChildren(container, CORE, @"Role")) {
		if ([gone containsObject:ORMRef(child) ?: @""]) {
			/* A role the model has just taken away. */
			ORMDetach(child);
		} else if ([[model elementWithId:ORMRef(child)] isKindOfClass:[ORMRole class]]) {
			[children addObject:child];
			[refs addObject:ORMRef(child)];
			[ids addObject:ORMAttribute(child, @"id") ?: @""];
		}
	}
	NSArray *wanted = [roles valueForKey:@"identifier"];
	if (container == nil || ([refs isEqualToArray:wanted] && (useIds == nil || [ids isEqualToArray:useIds]))) {
		return;
	}
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	for (NSXMLElement *child in children) {
		[kept setObject:child forKey:ORMRef(child) ?: @""];
		ORMDetach(child);
	}
	for (NSUInteger i = 0; i < [wanted count]; i++) {
		NSString *identifier = [wanted objectAtIndex:i];
		NSXMLElement *child = [kept objectForKey:identifier];
		if (child == nil) {
			/* A constraint's use of a role has an id of its own, the
			 * model's. */
			NSString *useId = i < [useIds count] ? [useIds objectAtIndex:i] : nil;
			child = [useId length] > 0 ? ORMNewElementWithId(document, CORE, @"Role", useId)
			                           : ORMNewElement(document, CORE, @"Role");
			ORMSetAttribute(child, @"ref", identifier);
		} else if (i < [useIds count] && [[useIds objectAtIndex:i] length] > 0
		           && ![ORMAttribute(child, @"id") ?: @"" isEqualToString:[useIds objectAtIndex:i]]) {
			ORMSetAttribute(child, @"id", [useIds objectAtIndex:i]);
		}
		ORMAddChild(container, child);
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
			ORMDetach(child);
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
	for (ORMStoredQuery *query in self.model.storedQueries) {
		[self writeElement:query];
	}
	for (ORMCoreDataMapping *mapping in self.model.coreDataMappings) {
		[self writeElement:mapping];
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
			ORMAddChild(kinds, kind);
			kindId = ORMAttribute(kind, @"id");
		}
		NSXMLElement *custom = ORMNewElementWithId(_document, CORE, @"CustomReferenceMode", nil);
		ORMSetAttribute(custom, @"Name", name);
		ORMAddChild(custom, ORMNewRef(_document, CORE, @"Kind", kindId));
		ORMAddChild(ORMEnsureChild(_document, modelElement, CORE, @"CustomReferenceModes"), custom);
	}
}

#pragma mark What NORMA keeps beside the model

- (void)writeNormaDataOf:(ORMElement *)element
{
	if (element.element == nil) {
		return;
	}
	if ([element isKindOfClass:[ORMObjectType class]]) {
		ORMObjectType *type = (ORMObjectType *)element;
		NSMutableArray *played = [NSMutableArray array];
		for (ORMRole *role in type.playedRoles) {
			/* A link fact type's proxy is played through the role it
			 * stands for, and NORMA does not list it. */
			if (role.proxiedRole != nil) {
				continue;
			}
			/* Older NORMA refers to a subtype fact's roles by their own
			 * element names, SubtypeMetaRole and SupertypeMetaRole. */
			NSString *local = [role.element localName];
			BOOL meta = [local isEqualToString:@"SubtypeMetaRole"] || [local isEqualToString:@"SupertypeMetaRole"];
			[played addObject:@[ meta ? local : @"Role", role.identifier ]];
		}
		NSXMLElement *container = ORMChild(type.element, CORE, @"PlayedRoles");
		if ([played count] > 0 || container != nil) {
			container = container ?: ORMEnsureChild(_document, type.element, CORE, @"PlayedRoles");
			ORMSyncRefs(_document, container, played);
			ORMPruneIfEmpty(container);
		}
		/* Written, it is what the file says: what the next name reads by. */
		if (type.kind == ORMEntityType) {
			NSString *mode = type.referenceMode ?: @"";
			if (![ORMAttribute(type.element, @"_ReferenceMode") ?: @"" isEqualToString:mode]) {
				ORMSetAttribute(type.element, @"_ReferenceMode", mode);
			}
			type.savedReferenceMode = mode;
		}
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		ORMFactType *fact = (ORMFactType *)element;
		NSXMLElement *factElement = fact.element;
		if (ORMAttribute(factElement, @"_Name") != nil || fact.kind == ORMFactTypeOrdinary) {
			NSString *name = [fact derivedName];
			if (![ORMAttribute(factElement, @"_Name") isEqualToString:name]) {
				ORMSetAttribute(factElement, @"_Name", name);
			}
			fact.savedDerivedName = name;
		}
		for (ORMRole *role in fact.roles) {
			NSString *local = [role.element localName];
			if ([local isEqualToString:@"Role"] || [local isEqualToString:@"SubtypeMetaRole"]
			    || [local isEqualToString:@"SupertypeMetaRole"]) {
				NSString *mandatory = role.isMandatory ? @"true" : @"false";
				NSString *multiplicity = ORMMultiplicityName([role multiplicity]);
				if (![ORMAttribute(role.element, @"_IsMandatory") isEqualToString:mandatory]) {
					ORMSetAttribute(role.element, @"_IsMandatory", mandatory);
				}
				if (![ORMAttribute(role.element, @"_Multiplicity") isEqualToString:multiplicity]) {
					ORMSetAttribute(role.element, @"_Multiplicity", multiplicity);
				}
			}
		}
		NSMutableArray *internal = [NSMutableArray array];
		for (ORMConstraint *constraint in fact.internalConstraints) {
			[internal addObject:@[ [constraint.element localName] ?: ORMConstraintElementName(constraint.kind),
			                       constraint.identifier ]];
		}
		NSXMLElement *container = ORMChild(factElement, CORE, @"InternalConstraints");
		if ([internal count] > 0 || container != nil) {
			container = container ?: ORMEnsureChild(_document, factElement, CORE, @"InternalConstraints");
			ORMSyncRefs(_document, container, internal);
			ORMPruneIfEmpty(container);
		}
		for (ORMReadingOrder *order in self.writesExpandedData ? fact.readingOrders : @[]) {
			for (ORMReading *reading in order.readings) {
				NSXMLElement *expanded = ORMExpandedData(_document, reading.text, [order.roles count]);
				NSXMLElement *existing = ORMChild(reading.element, CORE, @"ExpandedData");
				if (expanded == nil) {
					ORMDetach(existing);
				} else if (existing == nil) {
					NSUInteger index = [ORMChild(reading.element, CORE, @"Data") index] + 1;
					ORMInsertChildAt(reading.element, expanded, MIN(index, [reading.element childCount]));
				} else if (![ORMShapeOf(existing) isEqual:ORMShapeOf(expanded)]) {
					ORMInsertChildAt(reading.element, expanded, [existing index]);
					ORMDetach(existing);
				}
			}
		}
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		ORMConstraint *constraint = (ORMConstraint *)element;
		if (constraint.kind == ORMUniquenessConstraint) {
			NSString *target = constraint.preferredIdentifierFor.identifier;
			NSXMLElement *existing = ORMChild(constraint.element, CORE, @"PreferredIdentifierFor");
			if (target == nil) {
				ORMDetach(existing);
			} else if (existing == nil) {
				ORMAddChild(constraint.element, ORMNewRef(_document, CORE, @"PreferredIdentifierFor", target));
			} else if (![ORMRef(existing) isEqualToString:target]) {
				ORMSetAttribute(existing, @"ref", target);
			}
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
		ORMAddChild(ORMEnsureChild(_document, self.model.modelElement, CORE, @"DataTypes"), made);
	} else if ([element isKindOfClass:[ORMObjectType class]]) {
		made = ORMNewElementWithId(_document, CORE, ORMObjectTypeElementName([(ORMObjectType *)element kind]),
		                           element.identifier);
		ORMAddChild(ORMEnsureChild(_document, self.model.modelElement, CORE, @"Objects"), made);
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
		ORMAddChild(ORMEnsureChild(_document, self.model.modelElement, CORE, @"Facts"), made);
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		made = ORMNewElementWithId(_document, CORE, ORMConstraintElementName([(ORMConstraint *)element kind]),
		                           element.identifier);
		ORMAddChild(ORMEnsureChild(_document, self.model.modelElement, CORE, @"Constraints"), made);
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
		ORMAddChild(made, ORMNewRef(_document, DIAGRAM, @"Subject", self.model.identifier));
		/* After the last diagram, before what NORMA's extensions keep. */
		NSXMLElement *root = [_document rootElement];
		NSArray *diagrams = ORMChildren(root, DIAGRAM, @"ORMDiagram");
		NSUInteger index = [diagrams count] > 0 ? [[diagrams lastObject] index] + 1 : [root childCount];
		ORMInsertChildAt(root, made, index);
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
			ORMAddChild(relative, made);
		} else {
			NSXMLElement *shapes = ORMChild(shape.diagram.element, DIAGRAM, @"Shapes");
			if (shapes == nil) {
				shapes = ORMNewElement(_document, DIAGRAM, @"Shapes");
				/* Shapes come before the diagram's Subject. */
				ORMInsertChildAt(shape.diagram.element, shapes, 0);
			}
			ORMAddChild(shapes, made);
		}
	} else if ([element isKindOfClass:[ORMInstance class]]) {
		/* As NORMA writes a sample population's instance. */
		ORMInstance *instance = (ORMInstance *)element;
		made = ORMNewElementWithId(_document, CORE, instance.elementName, element.identifier);
		if (instance.value != nil) {
			ORMSetChildText(_document, made, CORE, @"Value", instance.value);
			if (instance.invariantValue != nil) {
				NSXMLElement *invariant = ORMNewElement(_document, CORE, @"InvariantValue");
				ORMSetText(invariant, instance.invariantValue);
				ORMAddChild(made, invariant);
			}
		}
		if ([instance.identifyingRoleInstances count] > 0) {
			NSXMLElement *refs = ORMNewElement(_document, CORE, @"RoleInstances");
			for (NSString *roleInstance in instance.identifyingRoleInstances) {
				ORMAddChild(refs, ORMNewRef(_document, CORE, @"EntityTypeRoleInstance", roleInstance));
			}
			ORMAddChild(made, refs);
		}
		if (instance.supertypeInstanceId != nil) {
			ORMAddChild(made, ORMNewRef(_document, CORE, @"SupertypeInstance", instance.supertypeInstanceId));
		}
		if (instance.objectifiedInstanceId != nil) {
			ORMAddChild(made, ORMNewRef(_document, CORE, @"ObjectifiedInstance", instance.objectifiedInstanceId));
		}
		ORMAddChild(ORMEnsureChild(_document, instance.objectType.element, CORE, @"Instances"), made);
	} else if ([element isKindOfClass:[ORMRoleInstance class]]) {
		ORMRoleInstance *roleInstance = (ORMRoleInstance *)element;
		made = ORMNewElementWithId(_document, CORE, roleInstance.elementName, element.identifier);
		ORMSetAttribute(made, @"ref", roleInstance.instanceId);
		ORMAddChild(ORMEnsureChild(_document, roleInstance.role.element, CORE, @"RoleInstances"), made);
	} else if ([element isKindOfClass:[ORMFactInstance class]]) {
		ORMFactInstance *fact = (ORMFactInstance *)element;
		made = ORMNewElementWithId(_document, CORE, @"FactTypeInstance", element.identifier);
		NSXMLElement *refs = ORMNewElement(_document, CORE, @"RoleInstances");
		for (NSString *roleInstance in fact.roleInstanceIds) {
			ORMAddChild(refs, ORMNewRef(_document, CORE, @"FactTypeRoleInstance", roleInstance));
		}
		ORMAddChild(made, refs);
		ORMAddChild(ORMEnsureChild(_document, fact.factType.element, CORE, @"Instances"), made);
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		ORMModelNote *note = (ORMModelNote *)element;
		made = ORMNewElementWithId(_document, CORE, @"ModelNote", element.identifier);
		ORMSetChildText(_document, made, CORE, @"Text", note.text ?: @"");
		if ([note.referencedElements count] > 0) {
			NSXMLElement *references = ORMNewElement(_document, CORE, @"ReferencedBy");
			for (ORMElement *referenced in note.referencedElements) {
				NSString *local = [referenced isKindOfClass:[ORMObjectType class]] ? @"ObjectType"
					: [referenced isKindOfClass:[ORMFactType class]] ? @"FactType" : @"Constraint";
				ORMAddChild(references, ORMNewRef(_document, CORE, local, referenced.identifier));
			}
			ORMAddChild(made, references);
		}
		ORMAddChild(ORMEnsureChild(_document, self.model.modelElement, CORE, @"ModelNotes"), made);
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
	if ([element isKindOfClass:[ORMCoreDataMapping class]]) {
		[self writeCoreDataMapping:(ORMCoreDataMapping *)element];
		return;
	}
	if ([element isKindOfClass:[ORMStoredQuery class]]) {
		[self writeStoredQuery:(ORMStoredQuery *)element];
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
		                 self.model, nil, self.gone);
	} else if ([element isKindOfClass:[ORMReading class]]) {
		[self writeReading:(ORMReading *)element];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		[self writeConstraint:(ORMConstraint *)element];
	} else if ([element isKindOfClass:[ORMRoleSequence class]]) {
		ORMWriteRoleRefs(_document, element.element, [(ORMRoleSequence *)element roles], self.model,
		                 [(ORMRoleSequence *)element roleUseIds], self.gone);
	} else if ([element isKindOfClass:[ORMValueConstraint class]]) {
		[self writeValueConstraint:(ORMValueConstraint *)element];
	} else if ([element isKindOfClass:[ORMInstance class]]) {
		/* A value renamed: its text, and its invariant form. */
		ORMInstance *instance = (ORMInstance *)element;
		for (NSArray *pair in @[ @[ @"Value", instance.value ?: [NSNull null] ],
		                         @[ @"InvariantValue", instance.invariantValue ?: [NSNull null] ] ]) {
			NSXMLElement *child = ORMChild(element.element, CORE, [pair firstObject]);
			NSString *text = [pair lastObject] == [NSNull null] ? nil : [pair lastObject];
			if (child != nil && text != nil && ![[child stringValue] isEqualToString:text]) {
				ORMSetText(child, text);
			}
		}
	} else if ([element isKindOfClass:[ORMRoleInstance class]]) {
		NSString *ref = [(ORMRoleInstance *)element instanceId];
		if (![ORMRef(element.element) isEqualToString:ref ?: @""]) {
			ORMSetAttribute(element.element, @"ref", ref);
		}
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
			ORMAddChild(made, ORMNewRef(_document, CORE, @"Role", role.proxiedRole.identifier));
			roles = roles ?: ORMEnsureChild(_document, element, CORE, @"FactRoles");
			ORMAddChild(roles, made);
			role.element = made;
		} else if (role.element == nil) {
			NSString *local = role.isSubtypeMetaRole ? @"SubtypeMetaRole"
				: role.isSupertypeMetaRole ? @"SupertypeMetaRole" : @"Role";
			NSXMLElement *made = ORMNewElementWithId(_document, CORE, local, role.identifier);
			ORMSetAttribute(made, @"_IsMandatory", @"false");
			ORMSetAttribute(made, @"_Multiplicity", @"Unspecified");
			ORMSetAttribute(made, @"Name", role.name ?: @"");
			roles = roles ?: ORMEnsureChild(_document, element, CORE, @"FactRoles");
			ORMAddChild(roles, made);
			role.element = made;
			[self writeRole:role];
		}
	}
	NSXMLElement *orders = ORMChild(element, CORE, @"ReadingOrders");
	ORMDetachOthers(orders, @"ReadingOrder", fact.readingOrders);
	for (ORMReadingOrder *order in fact.readingOrders) {
		if (order.element == nil) {
			NSXMLElement *made = ORMNewElementWithId(_document, CORE, @"ReadingOrder", order.identifier);
			ORMAddChild(made, ORMNewElement(_document, CORE, @"Readings"));
			ORMAddChild(made, ORMNewElement(_document, CORE, @"RoleSequence"));
			orders = orders ?: ORMEnsureChild(_document, element, CORE, @"ReadingOrders");
			ORMAddChild(orders, made);
			order.element = made;
			ORMWriteRoleRefs(_document, ORMChild(made, CORE, @"RoleSequence"), order.roles, self.model, nil, self.gone);
		}
		NSXMLElement *readings = ORMChild(order.element, CORE, @"Readings");
		ORMDetachOthers(readings, @"Reading", order.readings);
		for (ORMReading *reading in order.readings) {
			if (reading.element == nil) {
				NSXMLElement *made = ORMNewElementWithId(_document, CORE, @"Reading", reading.identifier);
				NSXMLElement *data = ORMNewElement(_document, CORE, @"Data");
				ORMSetText(data, reading.text ?: @"");
				ORMAddChild(made, data);
				ORMAddChild(readings, made);
				reading.element = made;
			}
		}
	}
}

/* A constraint's role sequences: one of its own where it has one without
 * an id, else each in RoleSequences with its id; each role used with an id
 * of its own. */
/* NORMA's purpose of a pathed role. */
static NSString *
ORMPurposeName(ORMPathedRolePurpose purpose)
{
	switch (purpose) {
	case ORMPathStartRole:
		return @"StartRole";
	case ORMPathSameFactType:
		return @"SameFactType";
	case ORMPathOuterJoin:
		return @"PostOuterJoin";
	case ORMPathInnerJoin:
		break;
	}
	return @"PostInnerJoin";
}

/* A role path made, as NORMA writes one: its root, its pathed roles and
 * the paths that go on from its end. */
- (NSXMLElement *)rolePath:(ORMRolePath *)path named:(NSString *)local
{
	NSXMLElement *element = ORMNewElementWithId(_document, CORE, local, path.identifier);
	if (path.rootObjectType != nil) {
		NSXMLElement *root = ORMNewElementWithId(_document, CORE, @"RootObjectType", path.rootId);
		ORMSetAttribute(root, @"ref", path.rootObjectType.identifier);
		ORMAddChild(element, root);
	}
	if ([path.pathedRoles count] > 0) {
		NSXMLElement *pathedRoles = ORMNewElement(_document, CORE, @"PathedRoles");
		for (ORMPathedRole *pathed in path.pathedRoles) {
			NSXMLElement *role = ORMNewElementWithId(_document, CORE, @"PathedRole", pathed.identifier);
			ORMSetAttribute(role, @"ref", pathed.role.identifier);
			ORMSetAttribute(role, @"Purpose", ORMPurposeName(pathed.purpose));
			ORMAddChild(pathedRoles, role);
		}
		ORMAddChild(element, pathedRoles);
	}
	if ([path.subPaths count] > 0) {
		NSXMLElement *subPaths = ORMNewElement(_document, CORE, @"SubPaths");
		for (ORMRolePath *sub in path.subPaths) {
			ORMAddChild(subPaths, [self rolePath:sub named:@"SubPath"]);
		}
		ORMAddChild(element, subPaths);
	}
	return element;
}

/* A sequence's join path made, as NORMA writes one: its role paths, and
 * where each of the sequence's role uses is projected from. */
- (void)writeJoinPath:(ORMRolePathOwner *)owner into:(NSXMLElement *)sequence
{
	NSXMLElement *rule = ORMNewElement(_document, CORE, @"JoinRule");
	NSXMLElement *joinPath = ORMNewElementWithId(_document, CORE, @"JoinPath", owner.identifier);
	NSXMLElement *components = ORMNewElement(_document, CORE, @"PathComponents");
	for (ORMRolePath *path in owner.paths) {
		ORMAddChild(components, [self rolePath:path named:@"RolePath"]);
	}
	ORMAddChild(joinPath, components);
	NSXMLElement *projections = ORMNewElement(_document, CORE, @"JoinPathProjections");
	NSXMLElement *projection = ORMNewElementWithId(_document, CORE, @"JoinPathProjection", owner.projectionId);
	ORMSetAttribute(projection, @"ref", [[owner.paths firstObject] identifier]);
	for (NSXMLElement *use in ORMChildren(sequence, CORE, @"Role")) {
		NSString *target = ORMAttribute(use, @"id");
		ORMPathSource *source = target != nil ? [owner.projections objectForKey:target] : nil;
		if (source == nil) {
			continue;
		}
		NSXMLElement *roleProjection = ORMNewElementWithId(_document, CORE, @"ConstraintRoleProjection",
		                                                  [owner.projectionIds objectForKey:target]);
		ORMSetAttribute(roleProjection, @"ref", target);
		NSXMLElement *from = ORMNewElement(_document, CORE, @"ProjectedFrom");
		if (source.kind == ORMPathSourceRoot) {
			ORMAddChild(from, ORMNewRef(_document, CORE, @"PathRoot", source.root.rootId));
		} else {
			ORMAddChild(from, ORMNewRef(_document, CORE, @"PathedRole", source.pathedRole.identifier));
		}
		ORMAddChild(roleProjection, from);
		ORMAddChild(projection, roleProjection);
	}
	ORMAddChild(projections, projection);
	ORMAddChild(joinPath, projections);
	ORMAddChild(rule, joinPath);
	ORMAddChild(sequence, rule);
}

- (void)writeSequencesOf:(ORMConstraint *)constraint
{
	NSDictionary *joinPaths = [self.model.extras objectForKey:@"joinPaths"];
	for (ORMRoleSequence *sequence in constraint.roleSequences) {
		ORMRolePathOwner *joinPath = sequence.identifier != nil ? [joinPaths objectForKey:sequence.identifier] : nil;
		if (joinPath != nil && sequence.element != nil && ORMChild(sequence.element, CORE, @"JoinRule") == nil) {
			[self writeJoinPath:joinPath into:sequence.element];
		}
		if (sequence.element == nil) {
			NSXMLElement *made = sequence.identifier != nil
				? ORMNewElementWithId(_document, CORE, @"RoleSequence", sequence.identifier)
				: ORMNewElement(_document, CORE, @"RoleSequence");
			NSXMLElement *parent = sequence.identifier != nil
				? ORMEnsureChild(_document, constraint.element, CORE, @"RoleSequences")
				: constraint.element;
			ORMAddChild(parent, made);
			sequence.element = made;
			ORMWriteRoleRefs(_document, made, sequence.roles, self.model, sequence.roleUseIds, self.gone);
		}
	}
}

/* A fact type's derivation rule, each part compared as it is read: made,
 * its completeness, storage and words set, or taken away. What else it
 * holds (NORMA's role path) stays as the file has it. */
- (void)writeDerivationRuleOf:(ORMFactType *)fact
{
	ORMDerivationRule *rule = [self.model.derivationRules objectForKey:fact.identifier];
	NSXMLElement *element = ORMChild(fact.element, CORE, @"DerivationRule");
	if (rule == nil) {
		ORMDetach(element);
		return;
	}
	if (element == nil) {
		element = ORMNewElement(_document, CORE, @"DerivationRule");
		ORMInsertChild(fact.element, element);
	}
	NSXMLElement *path = ORMChild(element, CORE, @"FactTypeDerivationPath");
	if (path == nil && rule.pathId != nil) {
		path = ORMNewElementWithId(_document, CORE, @"FactTypeDerivationPath", rule.pathId);
		ORMAddChild(element, path);
	}
	NSXMLElement *expression = ORMChild(element, CORE, @"DerivationExpression");
	NSString *legacy = ORMAttribute(expression, @"DerivationStorage");
	NSString *completeness = ORMAttribute(path, @"DerivationCompleteness") ?: ORMAttribute(element, @"DerivationCompleteness");
	NSString *storage = ORMAttribute(path, @"DerivationStorage") ?: ORMAttribute(element, @"DerivationStorage");
	BOOL partial = [completeness isEqualToString:@"PartiallyDerived"] || [legacy hasPrefix:@"PartiallyDerived"];
	BOOL stored = [storage isEqualToString:@"Stored"] || [legacy hasSuffix:@"AndStored"];
	/* NORMA leaves out its defaults: fully derived, not stored. */
	if (partial != rule.isPartial) {
		ORMSetAttribute(path, @"DerivationCompleteness", rule.isPartial ? @"PartiallyDerived" : nil);
	}
	if (stored != rule.isStored) {
		ORMSetAttribute(path, @"DerivationStorage", rule.isStored ? @"Stored" : nil);
	}
	NSXMLElement *informal = ORMChild(path, CORE, @"InformalRule");
	NSXMLElement *note = ORMChild(informal, CORE, @"DerivationNote");
	NSString *text = ORMChildText(note, CORE, @"Body") ?: ORMChildText(expression, CORE, @"Body");
	if ([text length] == 0) {
		text = nil;
	}
	if ([text ?: @"" isEqualToString:rule.informalText ?: @""]) {
		return;
	}
	if ([rule.informalText length] == 0) {
		ORMDetach(informal);
		return;
	}
	if (path == nil) {
		return;
	}
	if (informal == nil) {
		informal = ORMNewElement(_document, CORE, @"InformalRule");
		ORMAddChild(path, informal);
	}
	if (note == nil) {
		note = ORMNewElementWithId(_document, CORE, @"DerivationNote", rule.noteId);
		ORMAddChild(informal, note);
	}
	ORMSetChildText(_document, note, CORE, @"Body", rule.informalText);
}

- (void)writeFactType:(ORMFactType *)fact
{
	NSXMLElement *element = fact.element;
	[self writePartsOf:fact];
	[self writeDerivationRuleOf:fact];
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
		ORMDetach(ORMChild(owner, CORE, @"ValueRestriction"));
		return;
	}
	if (values.element == nil) {
		NSXMLElement *restriction = ORMEnsureChild(_document, owner, CORE, @"ValueRestriction");
		NSXMLElement *made = ORMNewElementWithId(_document, CORE, local, values.identifier);
		ORMSetAttribute(made, @"Name", values.name);
		ORMAddChild(restriction, made);
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
			ORMDetach(child);
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
			ORMAddChild(container, made);
			range.element = made;
		}
	}
	if ([values.ranges count] == 0) {
		ORMDetach(container);
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
	ORMDetach(order);
	NSXMLElement *display = ORMNewElement(_document, DIAGRAM, @"RoleDisplayOrder");
	for (ORMRole *role in shape.roleDisplayOrder) {
		ORMAddChild(display, ORMNewRef(_document, DIAGRAM, @"Role", role.identifier));
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
		/* Another kind: renamed in place, its attributes and children kept. */
		NSString *prefix = [element prefix];
		ORMRename(element, [prefix length] > 0 ? [NSString stringWithFormat:@"%@:%@", prefix, local] : local);
	}
	ORMSetAttribute(element, @"Name", type.name);
	[self writeValueConstraint:type.ownValueConstraint of:element as:@"ValueConstraint"];
	if (type.valuePattern == nil) {
		ORMDetach(ORMChild(element, ORMValuesNamespace, @"Pattern"));
	} else if (ORMChild(element, ORMValuesNamespace, @"Pattern") == nil
	           || ![ORMChildText(element, ORMValuesNamespace, @"Pattern") isEqualToString:type.valuePattern]) {
		ORMSetChildText(_document, element, ORMValuesNamespace, @"Pattern", type.valuePattern);
	}
	if (type.kind != ORMValueType || type.dataType == nil) {
		ORMDetach(ORMChild(element, CORE, @"ConceptualDataType"));
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
