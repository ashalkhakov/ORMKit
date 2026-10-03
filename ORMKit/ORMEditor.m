/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMReadingText.h"

/* NORMA's role box: 0.16 by 0.11 inches, with 0.032 a side around them
 * inside a fact type shape. */
const double ORMRoleBoxWidth = 0.16 * 72.0;
const double ORMRoleBoxHeight = 0.11 * 72.0;

NSSize
ORMDefaultObjectTypeSize(NSString *displayName, BOOL twoLines)
{
	/* Tahoma at NORMA's base size is about 0.055 inches a character. */
	double width = MAX(0.36, 0.055 * [displayName length] + 0.12) * ORMPointsPerInch;
	double height = (twoLines ? 0.359 : 0.2295) * ORMPointsPerInch;
	return NSMakeSize(round(width * 100) / 100, round(height * 100) / 100);
}

NSSize
ORMDefaultFactTypeSize(NSUInteger roles)
{
	return NSMakeSize((0.16 * MAX(roles, (NSUInteger)1) + 0.0638888889923692) * ORMPointsPerInch,
	                  0.24388888899236916 * ORMPointsPerInch);
}

@implementation ORMEditor
{
	NSUndoManager *_undoManager;
	/* How deep in changes and groups the editor is: only the outermost
	 * takes the snapshot. */
	NSUInteger _depth;
	BOOL _hasChanges;
}

#pragma mark Documents

/* Parsed from text rather than built node by node: gnustep-base leaves a
 * root element made with a namespace and then given the same namespace's
 * declaration pointing at a namespace it has freed. */
+ (NSXMLDocument *)newDocumentNamed:(NSString *)name
{
	NSString *modelName = [name length] > 0 ? name : @"ORMModel1";
	NSString *escaped = [[[modelName stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
		stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"]
		stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
	NSString *modelId = ORMNewId();
	NSString *text = [NSString stringWithFormat:
		@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
		@"<ormRoot:ORM2 xmlns:orm=\"%@\" xmlns:ormDiagram=\"%@\" xmlns:ormRoot=\"%@\">\n"
		@"<orm:ORMModel id=\"%@\" Name=\"%@\">\n"
		@"<orm:DataTypes><orm:UnspecifiedDataType id=\"%@\" /></orm:DataTypes>\n"
		@"<orm:ReferenceModeKinds>\n"
		@"<orm:ReferenceModeKind id=\"%@\" FormatString=\"{1}\" ReferenceModeType=\"General\" />\n"
		@"<orm:ReferenceModeKind id=\"%@\" FormatString=\"{0}_{1}\" ReferenceModeType=\"Popular\" />\n"
		@"<orm:ReferenceModeKind id=\"%@\" FormatString=\"{1}Value\" ReferenceModeType=\"UnitBased\" />\n"
		@"</orm:ReferenceModeKinds>\n"
		@"</orm:ORMModel>\n"
		@"<ormDiagram:ORMDiagram id=\"%@\" IsCompleteView=\"false\" Name=\"%@\" BaseFontName=\"Tahoma\" "
		@"BaseFontSize=\"0.0972222238779068\"><ormDiagram:Subject ref=\"%@\" /></ormDiagram:ORMDiagram>\n"
		@"</ormRoot:ORM2>\n",
		ORMCoreNamespace, ORMDiagramNamespace, ORMRootNamespace, modelId, escaped, ORMNewId(), ORMNewId(), ORMNewId(),
		ORMNewId(), ORMNewId(), escaped, modelId];
	/* Parsed without a layout of its own: written as NORMA writes. */
	NSError *error = nil;
	return [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error];
}

- (instancetype)initWithDocument:(NSXMLDocument *)document undoManager:(NSUndoManager *)undoManager
{
	if ((self = [super init])) {
		_document = document;
		_undoManager = undoManager;
		_model = [ORMModel modelOfDocument:document reason:NULL];
	}
	return self;
}

- (BOOL)hasChanges
{
	return _hasChanges;
}

- (void)reread
{
	_model = [ORMModel modelOfDocument:_document reason:NULL];
}

- (void)change:(NSString *)name with:(void (^)(void))change
{
	/* The projection the change starts from is held for it: its objects'
	 * links to one another are weak. */
	__attribute__((objc_precise_lifetime)) ORMModel *start = _model;
	(void)start;
	if (_depth > 0) {
		change();
		[self normalize];
		[self reread];
		return;
	}
	NSXMLDocument *before = ORMCopyDocument(_document);
	BOOL hadChanges = _hasChanges;
	_depth++;
	change();
	[self normalize];
	_depth--;
	/* A manager that does not group by event (a document's that edits
	 * text in place, a test's) gets the step as a group of its own. */
	BOOL grouping = _undoManager != nil && [_undoManager groupingLevel] == 0;
	if (grouping) {
		[_undoManager beginUndoGrouping];
	}
	[_undoManager registerUndoWithTarget:self selector:@selector(restore:)
	                              object:@[ before, @(hadChanges) ]];
	[_undoManager setActionName:name];
	if (grouping) {
		[_undoManager endUndoGrouping];
	}
	_hasChanges = YES;
	[self reread];
	if (self.changed != nil) {
		self.changed();
	}
}

- (void)group:(NSString *)name with:(void (^)(void))operations
{
	[self change:name with:operations];
}

/* Undo and redo alike: the document and whether it had changes, swapped
 * for the ones now. */
- (void)restore:(NSArray *)state
{
	[_undoManager registerUndoWithTarget:self selector:@selector(restore:)
	                              object:@[ ORMCopyDocument(_document), @(_hasChanges) ]];
	_document = [state objectAtIndex:0];
	_hasChanges = [[state objectAtIndex:1] boolValue];
	[self reread];
	if (self.changed != nil) {
		self.changed();
	}
}

#pragma mark Saving

- (NSXMLDocument *)documentForSaving
{
	if (!_hasChanges) {
		return _document;
	}
	NSXMLDocument *copy = ORMCopyDocument(_document);
	NSArray *generated = ORMGeneratedNamespaces();
	NSXMLElement *root = [copy rootElement];
	for (NSXMLNode *child in [[root children] copy]) {
		if ([child kind] == NSXMLElementKind && [generated containsObject:[child URI]]) {
			[child detach];
		}
	}
	/* The settings that point at what was dropped. */
	for (NSXMLElement *state in ORMChildren(root, CORE, @"GenerationState")) {
		for (NSXMLElement *settings in ORMChildren(state, CORE, @"GenerationSettings")) {
			for (NSXMLNode *setting in [[settings children] copy]) {
				if ([generated containsObject:[setting URI]]) {
					[setting detach];
				}
			}
			ORMPruneIfEmpty(settings);
		}
		ORMPruneIfEmpty(state);
	}
	/* NORMA checks the model as it opens it and lists what it finds. */
	[ORMChild(ORMModelElementOfDocument(copy), CORE, @"ModelErrors") detach];
	return copy;
}

- (NSData *)dataForSaving
{
	return ORMDataOfDocument([self documentForSaving]);
}

#pragma mark Shared

- (NSXMLElement *)xml:(NSString *)elementId
{
	if (elementId == nil) {
		return nil;
	}
	ORMElement *projected = [_model elementWithId:elementId];
	NSXMLElement *element = projected.element;
	if (element != nil && [element rootDocument] == _document) {
		return element;
	}
	return ORMElementWithId(_document, elementId);
}

- (NSXMLElement *)section:(NSString *)local
{
	return ORMEnsureChild(_document, ORMModelElementOfDocument(_document), CORE, local);
}

- (NSString *)nextName:(NSString *)prefix
{
	NSUInteger highest = 0;
	for (NSXMLElement *element in ORMDescendants(ORMModelElementOfDocument(_document), CORE, nil)) {
		NSString *name = ORMAttribute(element, @"Name");
		if ([name hasPrefix:prefix]) {
			NSString *rest = [name substringFromIndex:[prefix length]];
			NSInteger number = [rest integerValue];
			if (number > 0 && [[NSString stringWithFormat:@"%ld", (long)number] isEqualToString:rest]) {
				highest = MAX(highest, (NSUInteger)number);
			}
		}
	}
	return [NSString stringWithFormat:@"%@%lu", prefix, (unsigned long)highest + 1];
}

- (NSString *)uniqueObjectTypeName:(NSString *)name
{
	NSMutableSet *taken = [NSMutableSet set];
	for (NSXMLNode *node in [ORMChild(ORMModelElementOfDocument(_document), CORE, @"Objects") children]) {
		if ([node kind] == NSXMLElementKind) {
			NSString *existing = ORMAttribute((NSXMLElement *)node, @"Name");
			if (existing != nil) {
				[taken addObject:existing];
			}
		}
	}
	if (![taken containsObject:name]) {
		return name;
	}
	for (NSUInteger i = 2;; i++) {
		NSString *candidate = [NSString stringWithFormat:@"%@%lu", name, (unsigned long)i];
		if (![taken containsObject:candidate]) {
			return candidate;
		}
	}
}

- (NSString *)dataTypeIdNamed:(NSString *)typeName
{
	NSXMLElement *types = [self section:@"DataTypes"];
	for (NSXMLElement *type in ORMChildren(types, CORE, typeName)) {
		return ORMAttribute(type, @"id");
	}
	NSXMLElement *type = ORMNewElementWithId(_document, CORE, typeName, nil);
	[types addChild:type];
	return ORMAttribute(type, @"id");
}

- (NSArray<ORMRole *> *)rolesWithIds:(NSArray<NSString *> *)roleIds reason:(NSString **)reason
{
	NSMutableArray *roles = [NSMutableArray array];
	for (NSString *roleId in roleIds) {
		ORMRole *role = [_model elementWithId:roleId];
		if (![role isKindOfClass:[ORMRole class]]) {
			if (reason != NULL) {
				*reason = @"Only roles can be constrained: pick role boxes.";
			}
			return nil;
		}
		if ([roles indexOfObjectIdenticalTo:role] != NSNotFound) {
			if (reason != NULL) {
				*reason = @"A role is picked twice.";
			}
			return nil;
		}
		[roles addObject:role];
	}
	if ([roles count] == 0) {
		if (reason != NULL) {
			*reason = @"No roles are picked.";
		}
		return nil;
	}
	return roles;
}

- (NSXMLElement *)newRoleSequence:(NSArray<NSString *> *)roleIds withId:(BOOL)withId
{
	NSXMLElement *sequence = withId ? ORMNewElementWithId(_document, CORE, @"RoleSequence", nil)
	                                : ORMNewElement(_document, CORE, @"RoleSequence");
	for (NSString *roleId in roleIds) {
		NSXMLElement *role = ORMNewElementWithId(_document, CORE, @"Role", nil);
		ORMSetAttribute(role, @"ref", roleId);
		[sequence addChild:role];
	}
	return sequence;
}

- (NSXMLElement *)newConstraint:(NSString *)local named:(NSString *)prefix
{
	NSXMLElement *constraint = ORMNewElementWithId(_document, CORE, local, nil);
	ORMSetAttribute(constraint, @"Name", [self nextName:prefix]);
	[[self section:@"Constraints"] addChild:constraint];
	return constraint;
}

#pragma mark Normalizing

/* Rewrites a list of <prefix:local ref/> children to name exactly the
 * targets: those already listed keep their place, missing ones go at the
 * end, so a model NORMA wrote comes back unchanged. */
static void
ORMSyncRefs(NSXMLDocument *document, NSXMLElement *container, NSArray<NSArray *> *targets)
{
	/* targets: [local name, id] pairs. */
	NSMutableArray *wanted = [targets mutableCopy];
	for (NSXMLNode *child in [[container children] copy]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		NSArray *pair = @[ [child localName], ORMRef((NSXMLElement *)child) ?: @"" ];
		NSUInteger index = [wanted indexOfObject:pair];
		if (index == NSNotFound) {
			[child detach];
		} else {
			[wanted removeObjectAtIndex:index];
		}
	}
	for (NSArray *pair in wanted) {
		[container addChild:ORMNewRef(document, [container URI], [pair objectAtIndex:0], [pair objectAtIndex:1])];
	}
}

static NSString *
ORMMultiplicityName(ORMMultiplicity multiplicity)
{
	switch (multiplicity) {
	case ORMMultiplicityZeroToOne: return @"ZeroToOne";
	case ORMMultiplicityZeroToMany: return @"ZeroToMany";
	case ORMMultiplicityExactlyOne: return @"ExactlyOne";
	case ORMMultiplicityOneToMany: return @"OneToMany";
	case ORMMultiplicityUnspecified: break;
	}
	return @"Unspecified";
}

/* An element as a comparable value: its local name, its attributes and
 * its children, without the namespace declarations and prefixes the two
 * platforms' NSXML give a new element differently. */
static NSArray *
ORMShapeOf(NSXMLElement *element)
{
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
	for (NSXMLNode *attribute in [element attributes]) {
		[attributes setObject:[attribute stringValue] ?: @"" forKey:[attribute localName] ?: [attribute name]];
	}
	NSMutableArray *children = [NSMutableArray array];
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			[children addObject:ORMShapeOf((NSXMLElement *)child)];
		}
	}
	return @[ [element localName] ?: @"", attributes, children ];
}

/* <orm:ExpandedData> as NORMA writes it for the reading. */
static NSXMLElement *
ORMExpandedData(NSXMLDocument *document, NSString *text, NSUInteger arity)
{
	ORMReadingText *reading = [ORMReadingText readingTextWithString:text arity:arity reason:NULL];
	if (reading == nil) {
		return nil;
	}
	NSXMLElement *expanded = ORMNewElement(document, CORE, @"ExpandedData");
	if ([reading.frontText length] > 0) {
		ORMSetAttribute(expanded, @"FrontText", reading.frontText);
	}
	for (ORMReadingPart *part in reading.parts) {
		if ([part.preBoundText length] == 0 && [part.postBoundText length] == 0 && [part.followingText length] == 0) {
			continue;
		}
		NSXMLElement *roleText = ORMNewElement(document, CORE, @"RoleText");
		ORMSetAttribute(roleText, @"RoleIndex", [NSString stringWithFormat:@"%lu", (unsigned long)part.roleIndex]);
		if ([part.preBoundText length] > 0) {
			ORMSetAttribute(roleText, @"PreBoundText", part.preBoundText);
		}
		if ([part.postBoundText length] > 0) {
			ORMSetAttribute(roleText, @"PostBoundText", part.postBoundText);
		}
		if ([part.followingText length] > 0) {
			ORMSetAttribute(roleText, @"FollowingText", part.followingText);
		}
		[expanded addChild:roleText];
	}
	return expanded;
}

- (void)normalize
{
	/* The model as the change left it. */
	ORMModel *model = [ORMModel modelOfDocument:_document reason:NULL];
	if (model == nil) {
		return;
	}

	for (ORMObjectType *type in model.objectTypes) {
		NSMutableArray *played = [NSMutableArray array];
		for (ORMRole *role in type.playedRoles) {
			[played addObject:@[ @"Role", role.identifier ]];
		}
		NSXMLElement *container = ORMChild(type.element, CORE, @"PlayedRoles");
		if ([played count] > 0 || container != nil) {
			container = container ?: ORMEnsureChild(_document, type.element, CORE, @"PlayedRoles");
			ORMSyncRefs(_document, container, played);
			ORMPruneIfEmpty(container);
		}
		if (type.kind == ORMEntityType) {
			ORMSetAttribute(type.element, @"_ReferenceMode", type.referenceMode ?: @"");
		}
		/* A preferred identifier that is gone. */
		NSXMLElement *identifier = ORMChild(type.element, CORE, @"PreferredIdentifier");
		if (identifier != nil && type.preferredIdentifier == nil) {
			[identifier detach];
		}
	}

	for (ORMFactType *fact in model.factTypes) {
		/* A unary's implicit value type is named by its reading. */
		if ([fact isUnary]) {
			ORMObjectType *implicit = nil;
			for (ORMRole *role in fact.roles) {
				if (role.player.isImplicitBooleanValue) {
					implicit = role.player;
				}
			}
			NSString *name = [[fact primaryReading] expandedText];
			if (implicit != nil && [name length] > 0 && ![implicit.name isEqualToString:name]
			    && [model objectTypeNamed:name] == nil) {
				ORMSetAttribute(implicit.element, @"Name", name);
			}
		}
		if (ORMAttribute(fact.element, @"_Name") != nil || fact.kind == ORMFactTypeOrdinary) {
			ORMSetAttribute(fact.element, @"_Name", [fact derivedName]);
		}
		for (ORMRole *role in fact.roles) {
			NSString *local = [role.element localName];
			if ([local isEqualToString:@"Role"] || [local isEqualToString:@"SubtypeMetaRole"]
			    || [local isEqualToString:@"SupertypeMetaRole"]) {
				ORMSetAttribute(role.element, @"_IsMandatory", role.isMandatory ? @"true" : @"false");
				ORMSetAttribute(role.element, @"_Multiplicity", ORMMultiplicityName([role multiplicity]));
			}
		}
		NSMutableArray *internal = [NSMutableArray array];
		for (ORMConstraint *constraint in fact.internalConstraints) {
			[internal addObject:@[ [constraint.element localName], constraint.identifier ]];
		}
		NSXMLElement *container = ORMChild(fact.element, CORE, @"InternalConstraints");
		if ([internal count] > 0 || container != nil) {
			container = container ?: ORMEnsureChild(_document, fact.element, CORE, @"InternalConstraints");
			ORMSyncRefs(_document, container, internal);
			ORMPruneIfEmpty(container);
		}
		for (ORMReadingOrder *order in fact.readingOrders) {
			for (ORMReading *reading in order.readings) {
				NSXMLElement *expanded = ORMExpandedData(_document, reading.text, [order.roles count]);
				NSXMLElement *existing = ORMChild(reading.element, CORE, @"ExpandedData");
				if (expanded == nil) {
					[existing detach];
				} else if (existing == nil) {
					NSUInteger index = [ORMChild(reading.element, CORE, @"Data") index] + 1;
					[reading.element insertChild:expanded atIndex:MIN(index, [reading.element childCount])];
				} else if (![ORMShapeOf(existing) isEqual:ORMShapeOf(expanded)]) {
					[reading.element replaceChildAtIndex:[existing index] withNode:expanded];
				}
			}
		}
	}

	[self normalizeImpliedMandatories:model];

	/* Each preferred identifier names what it identifies. */
	NSMutableDictionary *identified = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in model.objectTypes) {
		if (type.preferredIdentifier != nil) {
			[identified setObject:type.identifier forKey:type.preferredIdentifier.identifier];
		}
	}
	for (ORMConstraint *constraint in model.constraints) {
		if (constraint.kind != ORMUniquenessConstraint) {
			continue;
		}
		NSString *target = [identified objectForKey:constraint.identifier];
		NSXMLElement *existing = ORMChild(constraint.element, CORE, @"PreferredIdentifierFor");
		if (target == nil) {
			[existing detach];
		} else if (existing == nil) {
			[constraint.element addChild:ORMNewRef(_document, CORE, @"PreferredIdentifierFor", target)];
		} else if (![ORMRef(existing) isEqualToString:target]) {
			ORMSetAttribute(existing, @"ref", target);
		}
	}

	/* Shapes whose subject is gone, and role orders naming roles that are. */
	for (ORMDiagram *diagram in model.diagrams) {
		for (ORMShape *shape in [diagram allShapes]) {
			if (shape.subject == nil && shape.subjectId != nil && [shape.element rootDocument] == _document) {
				[shape.element detach];
				continue;
			}
			if (shape.kind == ORMShapeFactType) {
				NSXMLElement *order = ORMChild(shape.element, DIAGRAM, @"RoleDisplayOrder");
				NSArray *refs = ORMChildren(order, DIAGRAM, @"Role");
				BOOL stale = order != nil && [refs count] != [shape.roleDisplayOrder count];
				for (NSXMLElement *ref in refs) {
					if (![[model elementWithId:ORMRef(ref)] isKindOfClass:[ORMRole class]]) {
						stale = YES;
					}
				}
				if (stale) {
					NSMutableArray *pairs = [NSMutableArray array];
					for (ORMRole *role in shape.factType.roles) {
						[pairs addObject:@[ @"Role", role.identifier ]];
					}
					ORMSyncRefs(_document, order, pairs);
				}
			}
		}
	}
}

/* NORMA's implied disjunctive mandatory constraints: every instance of
 * an object type that is not independent plays some role, so one that
 * plays no mandatory role outside its own identification has an implied
 * inclusive-or over those roles. Kept as NORMA keeps them, one per object
 * type, pointing at it with ImpliedByObjectType. */
- (void)normalizeImpliedMandatories:(ORMModel *)model
{
	NSMutableDictionary *existing = [NSMutableDictionary dictionary];
	for (ORMConstraint *constraint in model.constraints) {
		NSString *owner = ORMRef(ORMChild(constraint.element, CORE, @"ImpliedByObjectType"));
		if (constraint.kind == ORMMandatoryConstraint && constraint.isImplied && owner != nil) {
			if ([existing objectForKey:owner] != nil || [model elementWithId:owner] == nil) {
				[constraint.element detach];
			} else {
				[existing setObject:constraint forKey:owner];
			}
		}
	}
	for (ORMObjectType *type in model.objectTypes) {
		NSSet *identifying = [NSSet setWithArray:type.preferredIdentifier.factTypes ?: @[]];
		NSMutableArray *roles = [NSMutableArray array];
		BOOL mandatory = NO;
		for (ORMRole *role in type.playedRoles) {
			if (role.isSupertypeMetaRole || [identifying containsObject:role.factType]) {
				continue;
			}
			if (role.isMandatory || role.isSubtypeMetaRole) {
				mandatory = YES;
			}
			[roles addObject:role.identifier];
		}
		ORMConstraint *current = [existing objectForKey:type.identifier];
		if (type.isIndependent || mandatory || [roles count] == 0) {
			[current.element detach];
			continue;
		}
		NSMutableArray *have = [NSMutableArray array];
		for (ORMRole *role in [current allRoles]) {
			[have addObject:role.identifier];
		}
		if (current != nil && [[NSSet setWithArray:have] isEqualToSet:[NSSet setWithArray:roles]]
		    && [have count] == [ORMChildren(ORMChild(current.element, CORE, @"RoleSequence"), CORE, @"Role") count]) {
			continue;
		}
		NSXMLElement *constraint = current.element;
		if (constraint == nil) {
			constraint = [self newConstraint:@"MandatoryConstraint" named:@"ImpliedMandatoryConstraint"];
			ORMSetAttribute(constraint, @"IsImplied", @"true");
		}
		[ORMChild(constraint, CORE, @"RoleSequence") detach];
		[constraint insertChild:[self newRoleSequence:roles withId:NO] atIndex:0];
		if (ORMChild(constraint, CORE, @"ImpliedByObjectType") == nil) {
			[constraint addChild:ORMNewRef(self.document, CORE, @"ImpliedByObjectType", type.identifier)];
		}
	}
}

@end
