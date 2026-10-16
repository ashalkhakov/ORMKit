/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMPath.h"
#import "ORMNormaWriter.h"

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

static BOOL ORMChecksAgreement;

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
	ORMPopulationEditor *_populationEditor;
	/* A step of a group changed the document: the projection is read again
	 * when it is next asked for, not after every step. */
	BOOL _stale;
	/* A step of the change being made edited the XML: the model is read
	 * again after it. */
	BOOL _editedXML;
	/* What a model change changed, to be written, and took away. */
	NSMutableArray<ORMElement *> *_wrote;
	NSMutableArray<ORMElement *> *_deleted;
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

- (ORMPopulationEditor *)populationEditor
{
	if (_populationEditor == nil) {
		_populationEditor = [[ORMPopulationEditor alloc] initWithEditor:self];
	}
	return _populationEditor;
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

+ (BOOL)checksAgreement
{
	return ORMChecksAgreement;
}

+ (void)setChecksAgreement:(BOOL)checks
{
	ORMChecksAgreement = checks;
}

- (void)checkAgreement
{
	if (!ORMChecksAgreement || _model == nil) {
		return;
	}
	@autoreleasepool {
		ORMModel *fresh = [ORMModel modelOfDocument:_document reason:NULL];
		NSString *difference = ORMModelDisagreement(_model, fresh);
		if (difference != nil) {
			[NSException raise:NSInternalInconsistencyException
			            format:@"The model and the document disagree: %@", difference];
		}
	}
}

- (BOOL)hasChanges
{
	return _hasChanges;
}

/* The same model, read again from the document: what holds one of its
 * elements across a change holds it still. */
- (void)reread
{
	if (_model != nil && ORMModelElementOfDocument(_document) != nil) {
		[_model readDocumentAgain:_document];
	} else {
		_model = [ORMModel modelOfDocument:_document reason:NULL];
	}
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

/* A change, or a group of them; undone in one step. With rollback, a
 * change that says it was refused leaves the document as it was, and no
 * step to undo. */
- (BOOL)apply:(NSString *)name rollback:(BOOL)rollback with:(BOOL (^)(void))change
{
	return [self apply:name rollback:rollback editsXML:YES with:change];
}

- (BOOL)apply:(NSString *)name rollback:(BOOL)rollback editsXML:(BOOL)editsXML with:(BOOL (^)(void))change
{
	/* A step of a group is read back for the next, and the group as a
	 * whole normalized, from the readings it started with. */
	if (_depth > 0) {
		NSXMLDocument *before = rollback ? ORMCopyDocument(_document) : nil;
		BOOL done;
		/* What the step made is read when the next step, or the caller,
		 * asks. */
		@autoreleasepool {
			done = change();
		}
		if (!done && before != nil) {
			_document = before;
			_stale = YES;
		}
		if (editsXML) {
			_stale = YES;
			_editedXML = YES;
		}
		return done;
	}
	[_normalizer rememberUnaryReadings];
	NSXMLDocument *before = ORMCopyDocument(_document);
	BOOL hadChanges = _hasChanges;
	_editedXML = editsXML;
	_depth++;
	BOOL done = change();
	if (!done && rollback) {
		_depth--;
		_document = before;
		_hasChanges = hadChanges;
		[self reread];
		return NO;
	}
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
	if (_editedXML || _stale) {
		[self reread];
	}
	[self checkAgreement];
	if (self.changed != nil) {
		self.changed();
	}
	return done;
}

- (void)change:(NSString *)name with:(void (^)(void))change
{
	[self apply:name rollback:NO with:^BOOL {
		change();
		return YES;
	}];
}

- (void)modelChange:(NSString *)name with:(void (^)(void))change
{
	[self apply:name rollback:NO editsXML:NO with:^BOOL {
		/* The model as the steps before left it. */
		ORMModel *model = self.model;
		_wrote = [NSMutableArray array];
		_deleted = [NSMutableArray array];
		/* Each unary's reading as the change finds it: an implicit type is
		 * named by its reading when that changes, its player renamed too. */
		NSMutableDictionary *unaries = [NSMutableDictionary dictionary];
		for (ORMFactType *fact in model.factTypes) {
			NSString *reading = [self.factTypeEditor unaryReadingOf:fact];
			if (reading != nil) {
				[unaries setObject:reading forKey:fact.identifier];
			}
		}
		change();
		/* Shapes whose subject is gone go with it (the normalizer's rule). */
		if (model.diagramsRead) {
			for (ORMDiagram *diagram in model.diagrams) {
				for (ORMShape *shape in [diagram allShapes]) {
					if (shape.subjectId != nil && [model elementWithId:shape.subjectId] == nil
					    && [model elementWithId:shape.identifier] == shape) {
						[diagram removeShape:shape];
						[self deleted:shape];
					}
				}
			}
		}
		for (ORMFactType *fact in model.factTypes) {
			NSString *was = [unaries objectForKey:fact.identifier];
			if (was != nil) {
				[self.factTypeEditor renameImplicitBooleanOf:fact was:was];
			}
		}
		[model derive];
		if ([self.constraintEditor keepImpliedMandatories]) {
			[model derive];
		}
		ORMNormaWriter *writer = [[ORMNormaWriter alloc] initWithModel:model];
		writer.gone = [NSSet setWithArray:[_deleted valueForKey:@"identifier"]];
		for (ORMElement *element in _wrote) {
			if ([_deleted indexOfObjectIdenticalTo:element] == NSNotFound) {
				[writer writeElement:element];
			}
		}
		for (ORMElement *element in _deleted) {
			[element.element detach];
		}
		[writer writeReferenceModes];
		_wrote = nil;
		_deleted = nil;
		return YES;
	}];
}

- (void)wrote:(ORMElement *)element
{
	if (element != nil && [_wrote indexOfObjectIdenticalTo:element] == NSNotFound) {
		[_wrote addObject:element];
	}
}

- (void)deleted:(ORMElement *)element
{
	if (element != nil && [_deleted indexOfObjectIdenticalTo:element] == NSNotFound) {
		[_deleted addObject:element];
	}
}

- (void)group:(NSString *)name with:(void (^)(void))operations
{
	[self change:name with:operations];
}

- (BOOL)group:(NSString *)name trying:(BOOL (^)(void))operations
{
	return [self apply:name rollback:YES with:operations];
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
	[self checkAgreement];
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
	/* The document's names, and those of what a model change has made
	 * and not yet written. */
	NSMutableArray *names = [NSMutableArray array];
	for (NSXMLElement *element in ORMDescendants(ORMModelElementOfDocument(_document), CORE, nil)) {
		NSString *name = ORMAttribute(element, @"Name");
		if (name != nil) {
			[names addObject:name];
		}
	}
	if (_wrote != nil) {
		for (ORMElement *element in [[_model valueForKey:@"elementsById"] allValues]) {
			if (element.element == nil && element.name != nil) {
				[names addObject:element.name];
			}
		}
	}
	NSUInteger highest = 0;
	for (NSString *name in names) {
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
	if ([self.model objectTypeNamed:name] == nil) {
		return name;
	}
	for (NSUInteger i = 2;; i++) {
		NSString *candidate = [NSString stringWithFormat:@"%@%lu", name, (unsigned long)i];
		if ([self.model objectTypeNamed:candidate] == nil) {
			return candidate;
		}
	}
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
