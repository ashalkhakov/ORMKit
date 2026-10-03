/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMPath.h"

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
	/* NORMA's denormalized data, kept up after each change. */
	ORMNormalizer *_normalizer;
	ORMObjectTypeEditor *_objectTypeEditor;
	ORMFactTypeEditor *_factTypeEditor;
	ORMConstraintEditor *_constraintEditor;
	ORMDiagramEditor *_diagramEditor;
	ORMElementEditor *_elementEditor;
	/* A step of a group changed the document: the projection is read again
	 * when it is next asked for, not after every step. */
	BOOL _stale;
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
		_normalizer = [[ORMNormalizer alloc] initWithEditor:self];
	}
	return self;
}

#pragma mark Its parts

- (ORMObjectTypeEditor *)objectTypeEditor
{
	if (_objectTypeEditor == nil) {
		_objectTypeEditor = [[ORMObjectTypeEditor alloc] initWithEditor:self];
	}
	return _objectTypeEditor;
}

- (ORMFactTypeEditor *)factTypeEditor
{
	if (_factTypeEditor == nil) {
		_factTypeEditor = [[ORMFactTypeEditor alloc] initWithEditor:self];
	}
	return _factTypeEditor;
}

- (ORMConstraintEditor *)constraintEditor
{
	if (_constraintEditor == nil) {
		_constraintEditor = [[ORMConstraintEditor alloc] initWithEditor:self];
	}
	return _constraintEditor;
}

- (ORMDiagramEditor *)diagramEditor
{
	if (_diagramEditor == nil) {
		_diagramEditor = [[ORMDiagramEditor alloc] initWithEditor:self];
	}
	return _diagramEditor;
}

- (ORMElementEditor *)elementEditor
{
	if (_elementEditor == nil) {
		_elementEditor = [[ORMElementEditor alloc] initWithEditor:self];
	}
	return _elementEditor;
}

#pragma mark Its file

- (BOOL)writesExpandedData
{
	return _normalizer.writesExpandedData;
}

- (BOOL)writesImpliedMandatories
{
	return _normalizer.writesImpliedMandatories;
}

- (BOOL)hasChanges
{
	return _hasChanges;
}

- (void)reread
{
	_model = [ORMModel modelOfDocument:_document reason:NULL];
	_stale = NO;
}

@synthesize model = _model;

- (ORMModel *)model
{
	if (_stale) {
		@autoreleasepool {
			[self reread];
		}
	}
	return _model;
}

- (void)change:(NSString *)name with:(void (^)(void))change
{
	/* The projection the change starts from is held for it: its objects'
	 * links to one another are weak. */
	__attribute__((objc_precise_lifetime)) ORMModel *start = _model;
	(void)start;
	/* A step of a group is read back for the next, and the group as a
	 * whole normalized, from the readings it started with. */
	if (_depth > 0) {
		/* What the step made is read when the next step, or the caller,
		 * asks; the projection before it is let go of then. */
		@autoreleasepool {
			change();
		}
		_stale = YES;
		return;
	}
	[_normalizer rememberUnaryReadings];
	NSXMLDocument *before = ORMCopyDocument(_document);
	BOOL hadChanges = _hasChanges;
	_depth++;
	change();
	[_normalizer normalize];
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

- (NSXMLDocument *)documentForNorma
{
	NSXMLDocument *copy = ORMCopyDocument([self documentForSaving]);
	NSXMLElement *root = [copy rootElement];
	for (NSString *uri in ORMKitNamespaces()) {
		for (NSXMLElement *element in ORMDescendants(root, uri, nil)) {
			[element detach];
		}
	}
	for (NSXMLNode *namespace in [[root namespaces] copy]) {
		if ([ORMKitNamespaces() containsObject:[namespace stringValue]]) {
			[root removeNamespaceForPrefix:[namespace name]];
		}
	}
	return copy;
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
		ORMRole *role = [self.model elementWithId:roleId];
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

@end
