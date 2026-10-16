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
		[_editor modelChange:@"Rename" with:^{
			if (value != nil && [_editor.model objectTypeNamed:valueName] == nil) {
				value.name = valueName;
				[_editor wrote:value];
			}
			type.name = trimmed;
			[_editor wrote:type];
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
		[_editor modelChange:@"Rename" with:^{
			if ([element isKindOfClass:[ORMFactType class]]) {
				/* A fact type's own name; NORMA otherwise derives one. */
				[(ORMFactType *)element setExplicitName:trimmed];
			} else {
				[(ORMElement *)element setName:trimmed];
			}
			[_editor wrote:element];
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
		[_editor modelChange:@"Add Note" with:^{
			ORMModel *model = _editor.model;
			ORMModelNote *note = [[ORMModelNote alloc] initWithModel:model];
			note.text = [text length] > 0 ? text : @"Note";
			NSMutableArray *referenced = [NSMutableArray array];
			for (NSString *elementId in elementIds) {
				id element = [model elementWithId:elementId];
				if (element != nil) {
					[referenced addObject:element];
				}
			}
			note.referencedElements = referenced;
			[model addElement:note];
			[_editor wrote:note];
			created = note.identifier;
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
	[_editor modelChange:@"Edit Note" with:^{
		note.text = text;
		[_editor wrote:note];
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
			for (ORMFactType *link in type.nestedFactType.linkFactTypes) {
				[pending addObject:link.identifier];
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
				for (ORMRole *proxy in role.proxies) {
					[pending addObject:proxy.factType.identifier];
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
	[_editor group:@"Delete" with:^{
		if ([doomed count] > 0) {
			[_editor modelChange:@"Delete" with:^{
				[self deleteFromModel:doomed];
			}];
		}
		/* Shapes are still taken away in the XML. */
		[_editor change:@"Delete" with:^{
			for (ORMShape *shape in shapes) {
				[shape.element detach];
			}
			[_editor.diagramEditor removeShapesOfSubjects:doomed];
		}];
	}];
}

/* The elements by id out of the model, and what they leave broken: a
 * constraint's arguments over doomed roles go, and a constraint left
 * without what it needs goes with them. */
- (void)deleteFromModel:(NSMutableSet<NSString *> *)doomed
{
	ORMModel *model = _editor.model;
	for (ORMConstraint *constraint in model.constraints) {
		if ([doomed containsObject:constraint.identifier]) {
			continue;
		}
		BOOL touched = NO;
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			NSMutableArray *kept = [NSMutableArray array];
			for (ORMRole *role in sequence.roles) {
				if (![doomed containsObject:role.identifier]) {
					[kept addObject:role];
				}
			}
			if ([kept count] != [sequence.roles count]) {
				sequence.roles = kept;
				[_editor wrote:sequence];
				touched = YES;
			}
		}
		if (!touched) {
			continue;
		}
		NSMutableArray *lengths = [NSMutableArray array];
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			[lengths addObject:@([sequence.roles count])];
		}
		BOOL setComparison = constraint.kind == ORMSubsetConstraint || constraint.kind == ORMEqualityConstraint
			|| constraint.kind == ORMExclusionConstraint;
		BOOL broken = [lengths containsObject:@0] || (setComparison && [[NSSet setWithArray:lengths] count] > 1);
		if (constraint.kind == ORMRingConstraint && [[lengths firstObject] integerValue] < 2) {
			broken = YES;
		}
		if (broken) {
			[doomed addObject:constraint.identifier];
		}
	}
	NSMutableArray *gone = [NSMutableArray array];
	for (NSString *elementId in doomed) {
		ORMElement *element = [model elementWithId:elementId];
		if ([element isKindOfClass:[ORMRole class]]) {
			/* Gone with its fact type; what uses it is written without it. */
			[_editor deleted:element];
		} else if (element != nil) {
			[gone addObject:element];
		}
	}
	for (ORMElement *element in gone) {
		if ([element isKindOfClass:[ORMReading class]]) {
			ORMReading *reading = (ORMReading *)element;
			ORMReadingOrder *order = reading.readingOrder;
			order.readings = ORMWithout(order.readings, reading);
			[_editor wrote:order.factType];
		} else if ([element isKindOfClass:[ORMReadingOrder class]]) {
			ORMReadingOrder *order = (ORMReadingOrder *)element;
			order.factType.readingOrders = ORMWithout(order.factType.readingOrders, order);
			[_editor wrote:order.factType];
		} else {
			/* Partners of an exclusive-or lose the link. */
			if ([element isKindOfClass:[ORMConstraint class]]) {
				ORMConstraint *partner = [(ORMConstraint *)element exclusiveOrPartner];
				if (partner != nil && ![doomed containsObject:partner.identifier]) {
					partner.exclusiveOrPartner = nil;
					[_editor wrote:partner];
				}
			}
			[_editor deleted:element];
		}
		[model removeElement:element];
	}
	/* What named what is gone: an identifier, a note's references. */
	for (ORMObjectType *type in model.objectTypes) {
		if (type.preferredIdentifier != nil && [doomed containsObject:type.preferredIdentifier.identifier]) {
			type.preferredIdentifier = nil;
			[_editor wrote:type];
		}
	}
	for (ORMModelNote *note in model.notes) {
		NSMutableArray *kept = [NSMutableArray array];
		for (ORMElement *referenced in note.referencedElements) {
			if (![doomed containsObject:referenced.identifier]) {
				[kept addObject:referenced];
			}
		}
		note.referencedElements = kept;
	}
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
	BOOL definition = [container isEqualToString:@"Definitions"];
	[_editor modelChange:action with:^{
		if (definition) {
			[(ORMElement *)target setDefinitionText:[text length] > 0 ? text : nil];
		} else {
			[(ORMElement *)target setNoteText:[text length] > 0 ? text : nil];
		}
		[_editor wrote:target];
	}];
	return YES;
}

@end
