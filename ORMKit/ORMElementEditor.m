/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"

@implementation ORMElementEditor

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

- (BOOL)rename:(NSString *)elementId to:(NSString *)name reason:(NSString **)reason
{
	id element = [_editor.model elementWithId:elementId];
	if (element == nil) {
		if (reason != NULL) {
			*reason = @"There is nothing to rename.";
		}
		return NO;
	}
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([element isKindOfClass:[ORMObjectType class]]) {
		ORMObjectType *type = element;
		if (![_editor.objectTypeEditor checkName:trimmed except:elementId reason:reason]) {
			return NO;
		}
		if ([trimmed isEqualToString:type.name]) {
			return YES;
		}
		/* Person_id follows Person to Human_id; a shared unit or general
		 * mode's value type stays. */
		ORMObjectType *value = type.referenceModeKind == ORMReferenceModePopular ? type.referenceModeValueType : nil;
		NSString *valueName = value != nil ? [_editor.objectTypeEditor valueTypeNameFor:trimmed mode:type.referenceMode kind:ORMReferenceModePopular] : nil;
		[_editor change:@"Rename" with:^{
			ORMSetAttribute(type.element, @"Name", trimmed);
			if (value != nil && [_editor.model objectTypeNamed:valueName] == nil) {
				ORMSetAttribute(value.element, @"Name", valueName);
			}
		}];
		return YES;
	}
	if ([element isKindOfClass:[ORMRole class]] || [element isKindOfClass:[ORMConstraint class]]
	    || [element isKindOfClass:[ORMDiagram class]] || [element isKindOfClass:[ORMFactType class]]) {
		if ([element isKindOfClass:[ORMConstraint class]] && [trimmed length] == 0) {
			if (reason != NULL) {
				*reason = @"A constraint needs a name.";
			}
			return NO;
		}
		NSXMLElement *xml = [(ORMElement *)element element];
		[_editor change:@"Rename" with:^{
			/* A fact type's own name; NORMA otherwise derives one. */
			ORMSetAttribute(xml, @"Name", trimmed);
		}];
		return YES;
	}
	if (reason != NULL) {
		*reason = @"That cannot be renamed.";
	}
	return NO;
}

- (BOOL)setDefinition:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason
{
	return [self setNested:@"Definitions" item:@"Definition" text:text of:elementId action:@"Set Definition"
	                reason:reason];
}

- (BOOL)setNote:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason
{
	return [self setNested:@"Notes" item:@"Note" text:text of:elementId action:@"Set Note" reason:reason];
}

- (NSString *)addNote:(NSString *)text
            attachedTo:(NSArray<NSString *> *)elementIds
             onDiagram:(NSString *)diagramId
                    at:(NSPoint)point
                reason:(NSString **)reason
{
	__block NSString *created = nil;
	[_editor group:@"Add Note" with:^{
		[_editor change:@"Add Note" with:^{
			NSXMLElement *note = ORMNewElementWithId(_editor.document, CORE, @"ModelNote", nil);
			ORMSetChildText(_editor.document, note, CORE, @"Text", [text length] > 0 ? text : @"Note");
			if ([elementIds count] > 0) {
				NSXMLElement *references = ORMNewElement(_editor.document, CORE, @"ReferencedBy");
				for (NSString *elementId in elementIds) {
					id element = [_editor.model elementWithId:elementId];
					NSString *local = [element isKindOfClass:[ORMObjectType class]] ? @"ObjectType"
						: [element isKindOfClass:[ORMFactType class]] ? @"FactType" : @"Constraint";
					[references addChild:ORMNewRef(_editor.document, CORE, local, elementId)];
				}
				[note addChild:references];
			}
			[[_editor section:@"ModelNotes"] addChild:note];
			created = ORMAttribute(note, @"id");
		}];
		if (diagramId != nil) {
			[_editor.diagramEditor placeElement:created onDiagram:diagramId at:point];
		}
	}];
	return created;
}

- (BOOL)setNoteText:(NSString *)text of:(NSString *)noteId reason:(NSString **)reason
{
	ORMModelNote *note = [_editor.model elementWithId:noteId];
	if (![note isKindOfClass:[ORMModelNote class]]) {
		if (reason != NULL) {
			*reason = @"Pick a note.";
		}
		return NO;
	}
	[_editor change:@"Edit Note" with:^{
		ORMSetChildText(_editor.document, note.element, CORE, @"Text", text);
	}];
	return YES;
}

/* What goes with the elements: closes the set of ids over what cannot
 * stand without what is in it. */
- (NSMutableSet *)closureOf:(NSArray<NSString *> *)elementIds
{
	ORMModel *model = _editor.model;
	NSMutableSet *doomed = [NSMutableSet set];
	NSMutableArray *pending = [elementIds mutableCopy];
	while ([pending count] > 0) {
		NSString *elementId = [pending lastObject];
		[pending removeLastObject];
		if ([doomed containsObject:elementId]) {
			continue;
		}
		id element = [model elementWithId:elementId];
		if (element == nil || [element isKindOfClass:[ORMShape class]]) {
			continue;
		}
		[doomed addObject:elementId];
		if ([element isKindOfClass:[ORMObjectType class]]) {
			ORMObjectType *type = element;
			for (ORMRole *role in type.playedRoles) {
				[pending addObject:role.factType.identifier];
			}
			if (type.nestedFactType != nil) {
				for (ORMFactType *fact in model.factTypes) {
					if (fact.impliedByFactType == type.nestedFactType) {
						[pending addObject:fact.identifier];
					}
				}
			}
			/* Its reference mode's value type, when nothing else uses it. */
			ORMObjectType *value = type.referenceModeValueType;
			if (value != nil && [value.playedRoles count] == 1) {
				[pending addObject:value.identifier];
			}
		} else if ([element isKindOfClass:[ORMFactType class]]) {
			ORMFactType *fact = element;
			for (ORMRole *role in fact.roles) {
				[doomed addObject:role.identifier];
				if (role.player.isImplicitBooleanValue) {
					[pending addObject:role.player.identifier];
				}
				/* Link fact types stand for the roles. */
				for (ORMFactType *link in model.factTypes) {
					for (ORMRole *linkRole in link.roles) {
						if (linkRole.proxiedRole == role) {
							[pending addObject:link.identifier];
						}
					}
				}
			}
			if (fact.objectifyingType != nil) {
				[pending addObject:fact.objectifyingType.identifier];
			}
		} else if ([element isKindOfClass:[ORMReading class]]) {
			ORMReading *reading = element;
			if ([reading.readingOrder.readings count] == 1) {
				[doomed addObject:reading.readingOrder.identifier];
			}
		}
	}
	return doomed;
}

- (void)deleteElements:(NSArray<NSString *> *)elementIds
{
	NSMutableArray *shapes = [NSMutableArray array];
	NSMutableArray *rest = [NSMutableArray array];
	for (NSString *elementId in elementIds) {
		id element = [_editor.model elementWithId:elementId];
		if ([element isKindOfClass:[ORMShape class]]) {
			[shapes addObject:element];
		} else if (element != nil) {
			[rest addObject:elementId];
		}
	}
	if ([shapes count] == 0 && [rest count] == 0) {
		return;
	}
	NSMutableSet *doomed = [self closureOf:rest];
	ORMModel *model = _editor.model;
	[_editor change:@"Delete" with:^{
		for (ORMShape *shape in shapes) {
			[shape.element detach];
		}
		/* Constraint arguments over doomed roles go; a constraint left
		 * without what it needs goes with them. */
		for (ORMConstraint *constraint in model.constraints) {
			if ([doomed containsObject:constraint.identifier]) {
				continue;
			}
			BOOL touched = NO;
			for (ORMRoleSequence *sequence in constraint.roleSequences) {
				for (NSXMLElement *ref in ORMChildren(sequence.element, CORE, @"Role")) {
					if ([doomed containsObject:ORMRef(ref) ?: @""]) {
						[ref detach];
						touched = YES;
					}
				}
			}
			if (!touched) {
				continue;
			}
			NSMutableArray *lengths = [NSMutableArray array];
			for (ORMRoleSequence *sequence in constraint.roleSequences) {
				[lengths addObject:@([ORMChildren(sequence.element, CORE, @"Role") count])];
			}
			BOOL setComparison = constraint.kind == ORMSubsetConstraint || constraint.kind == ORMEqualityConstraint
				|| constraint.kind == ORMExclusionConstraint;
			BOOL broken = [lengths containsObject:@0] || [[NSSet setWithArray:lengths] count] > 1;
			if (!setComparison) {
				broken = [lengths containsObject:@0];
			}
			if (constraint.kind == ORMRingConstraint && [[lengths firstObject] integerValue] < 2) {
				broken = YES;
			}
			if (broken) {
				[doomed addObject:constraint.identifier];
			}
		}
		for (NSString *elementId in doomed) {
			ORMElement *element = [model elementWithId:elementId];
			if ([element isKindOfClass:[ORMRole class]]) {
				continue;
			}
			/* Partners of an exclusive-or lose the link. */
			if ([element isKindOfClass:[ORMConstraint class]]) {
				ORMConstraint *partner = [(ORMConstraint *)element exclusiveOrPartner];
				[ORMChild(partner.element, CORE, @"ExclusiveOrExclusionConstraint") detach];
				[ORMChild(partner.element, CORE, @"ExclusiveOrMandatoryConstraint") detach];
			}
			[element.element detach];
		}
		[_editor.diagramEditor removeShapesOfSubjects:doomed];
	}];
}

/* Definitions/Definition/Text or Notes/Note/Text. */
- (BOOL)setNested:(NSString *)container item:(NSString *)item text:(NSString *)text of:(NSString *)elementId
           action:(NSString *)action reason:(NSString **)reason
{
	id target = [_editor.model elementWithId:elementId];
	if (![target isKindOfClass:[ORMObjectType class]] && ![target isKindOfClass:[ORMFactType class]]) {
		if (reason != NULL) {
			*reason = @"Only object types and fact types have definitions and notes.";
		}
		return NO;
	}
	NSXMLElement *owner = [(ORMElement *)target element];
	[_editor change:action with:^{
		NSXMLElement *outer = ORMChild(owner, CORE, container);
		if ([text length] == 0) {
			[outer detach];
			return;
		}
		outer = outer ?: ORMEnsureChild(_editor.document, owner, CORE, container);
		NSXMLElement *inner = ORMChild(outer, CORE, item);
		if (inner == nil) {
			inner = ORMNewElementWithId(_editor.document, CORE, item, nil);
			[outer addChild:inner];
		}
		ORMSetChildText(_editor.document, inner, CORE, @"Text", text);
	}];
	return YES;
}

@end
