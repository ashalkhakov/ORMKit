/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMPath.h"
#import "ORMNormaWriter.h"
#import "ORMQuery.h"
#import "ORMVerbalizer.h"

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
	/* In tests, the check that the writer kept up NORMA's data. */
	ORMNormalizer *_normalizer;
	BOOL _writesExpandedData;
	BOOL _writesImpliedMandatories;
	ORMObjectTypeEditor *_objectTypeEditor;
	ORMFactTypeEditor *_factTypeEditor;
	ORMConstraintEditor *_constraintEditor;
	ORMDiagramEditor *_diagramEditor;
	ORMElementEditor *_elementEditor;
	ORMPopulationEditor *_populationEditor;
	/* A refused step of a group put back what it did: the model is read
	 * again when it is next asked for. */
	BOOL _stale;
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
		_writesExpandedData = ORMWritesExpandedData(_model);
		_writesImpliedMandatories = ORMWritesImpliedMandatories(_model);
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

@synthesize writesExpandedData = _writesExpandedData;
@synthesize writesImpliedMandatories = _writesImpliedMandatories;

/* An older NORMA wrote no ExpandedData: a file with readings and none
 * gets none. */
static BOOL
ORMWritesExpandedData(ORMModel *model)
{
	if (model.readingsHaveExpandedData) {
		return YES;
	}
	for (ORMFactType *fact in model.factTypes) {
		for (ORMReadingOrder *order in fact.readingOrders) {
			if ([order.readings count] > 0) {
				return NO;
			}
		}
	}
	return YES;
}

/* An older NORMA wrote no implied mandatory constraints: a file that
 * needs some and has none stays as it is. */
static BOOL
ORMWritesImpliedMandatories(ORMModel *model)
{
	for (ORMConstraint *constraint in model.constraints) {
		if (constraint.kind == ORMMandatoryConstraint && constraint.isImplied && constraint.impliedByObjectTypeId != nil) {
			return YES;
		}
	}
	return [ORMImpliedMandatoryRoles(model) count] == 0;
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

/* Where two documents' bytes first differ, in words. */
static NSString *
ORMFirstDifference(NSData *one, NSData *other)
{
	NSArray *a = [[[NSString alloc] initWithData:one encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
	NSArray *b = [[[NSString alloc] initWithData:other encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
	for (NSUInteger i = 0; i < MAX([a count], [b count]); i++) {
		NSString *l = i < [a count] ? [a objectAtIndex:i] : @"(none)";
		NSString *r = i < [b count] ? [b objectAtIndex:i] : @"(none)";
		if (![l isEqualToString:r]) {
			return [NSString stringWithFormat:@"line %lu:\n  one   %@\n  other %@", (unsigned long)i + 1, l, r];
		}
	}
	return @"the same";
}

/* In tests: after model changes, NORMA's data as the normalizer would
 * keep it is what the writer wrote. */
- (void)checkNormalized
{
	if (!ORMChecksAgreement || _model == nil) {
		return;
	}
	@autoreleasepool {
		NSData *written = ORMDataOfDocument(_document);
		[_normalizer rememberUnaryReadings];
		[_normalizer normalize];
		NSData *normalized = ORMDataOfDocument(_document);
		if (![written isEqualToData:normalized]) {
			[NSException raise:NSInternalInconsistencyException
			            format:@"The writer left NORMA's data for the normalizer: %@", ORMFirstDifference(written, normalized)];
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
	if (_depth > 0) {
		/* A step that may be refused keeps its own journal, inside the
		 * change's: refused, it puts back its part, and the model is read
		 * again from that when next asked for. */
		ORMXMLJournal *inner = rollback ? [[ORMXMLJournal alloc] initWithDocument:_document] : nil;
		if (inner != nil) {
			ORMOpenJournal(inner);
		}
		BOOL done;
		@autoreleasepool {
			done = change();
		}
		if (inner != nil) {
			ORMCloseJournal(inner);
		}
		if (!done && inner != nil) {
			[inner restore];
			_stale = YES;
		}
		return done;
	}
	if (ORMChecksAgreement) {
		[_normalizer rememberUnaryReadings];
	}
	/* Undo puts back the elements the change touched, each as it was. */
	ORMXMLJournal *journal = [[ORMXMLJournal alloc] initWithDocument:_document];
	ORMOpenJournal(journal);
	NSData *was = ORMChecksAgreement ? ORMDataOfDocument(_document) : nil;
	BOOL hadChanges = _hasChanges;
	_depth++;
	BOOL done = change();
	if (!done && rollback) {
		ORMCloseJournal(journal);
		_depth--;
		[journal restore];
		_hasChanges = hadChanges;
		[self reread];
		return NO;
	}
	if (_stale) {
		[self reread];
	}
	/* A derivation rule's words come from its query. */
	[self keepDerivationWords];
	[self checkNormalized];
	ORMCloseJournal(journal);
	_depth--;
	/* A manager that does not group by event (a document's that edits
	 * text in place, a test's) gets the step as a group of its own. */
	BOOL grouping = _undoManager != nil && [_undoManager groupingLevel] == 0;
	if (grouping) {
		[_undoManager beginUndoGrouping];
	}
	[_undoManager registerUndoWithTarget:self selector:@selector(restoreJournal:)
	                              object:@[ journal, @(hadChanges), was ?: (id)[NSNull null] ]];
	[_undoManager setActionName:name];
	if (grouping) {
		[_undoManager endUndoGrouping];
	}
	_hasChanges = YES;
	[self checkAgreement];
	if (self.changed != nil) {
		self.changed();
	}
	return done;
}

- (void)modelChange:(NSString *)name with:(void (^)(void))change
{
	[self apply:name rollback:NO with:^BOOL {
		[self changeModel:change];
		return YES;
	}];
}

/* A change to the model's elements, and what follows from it: NORMA's
 * rules kept, the model derived, what changed written. */
- (void)changeModel:(void (^)(void))change
{
	/* The model as the steps before left it. */
	ORMModel *model = self.model;
	_wrote = [NSMutableArray array];
	_deleted = [NSMutableArray array];
	model.removedNames = [NSMutableSet set];
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
	for (ORMDiagram *diagram in model.diagrams) {
		for (ORMShape *shape in [diagram allShapes]) {
			if (shape.subjectId != nil && [model elementWithId:shape.subjectId] == nil
			    && [model elementWithId:shape.identifier] == shape) {
				[diagram removeShape:shape];
				[self deleted:shape];
			}
		}
	}
	for (ORMFactType *fact in model.factTypes) {
		NSString *was = [unaries objectForKey:fact.identifier];
		if (was != nil) {
			[self.factTypeEditor renameImplicitBooleanOf:fact was:was];
		}
	}
	[self.constraintEditor keepImpliedMandatories];
	/* What the sample population comes to: each fact's instances. */
	BOOL populated = [model hasPopulation];
	for (ORMElement *element in [_wrote arrayByAddingObjectsFromArray:_deleted]) {
		populated = populated || [element isKindOfClass:[ORMInstance class]]
			|| [element isKindOfClass:[ORMRoleInstance class]] || [element isKindOfClass:[ORMFactInstance class]];
	}
	if (populated) {
		[model derivePopulations];
	}
	ORMNormaWriter *writer = [[ORMNormaWriter alloc] initWithModel:model];
	writer.gone = [NSSet setWithArray:[_deleted valueForKey:@"identifier"]];
	writer.writesExpandedData = _writesExpandedData;
	for (ORMElement *element in _wrote) {
		if ([_deleted indexOfObjectIdenticalTo:element] == NSNotFound) {
			[writer writeElement:element];
		}
	}
	for (ORMElement *element in [self affectedBy:[_wrote arrayByAddingObjectsFromArray:_deleted]]) {
		if ([_deleted indexOfObjectIdenticalTo:element] == NSNotFound) {
			[writer writeNormaDataOf:element];
		}
	}
	for (ORMElement *element in _deleted) {
		/* With the container it leaves empty (a population's Instances,
		 * RoleInstances; the queries, the Core Data mappings): NORMA writes
		 * none empty. */
		NSXMLElement *container = (NSXMLElement *)[element.element parent];
		ORMDetach(element.element);
		if ([container isKindOfClass:[NSXMLElement class]]
		    && [@[ @"Instances", @"RoleInstances", @"Queries", @"CoreDataMappings" ] containsObject:[container localName] ?: @""]) {
			BOOL empty = YES;
			for (NSXMLNode *child in [container children]) {
				empty = empty && [child kind] != NSXMLElementKind;
			}
			if (empty) {
				ORMDetach(container);
			}
		}
	}
	[writer writeReferenceModes];
	_wrote = nil;
	_deleted = nil;
	model.removedNames = nil;
}

/* A derivation query's fact type keeps the query's words as its rule's
 * (docs/DERIVATION.md), where the rule has words: what NORMA shows. */
- (void)keepDerivationWords
{
	ORMVerbalizer *verbalizer = nil;
	NSMutableArray *changes = [NSMutableArray array];
	for (ORMQuery *query in [ORMQuery queriesInModel:_model]) {
		ORMFactType *fact = query.kind == ORMQueryDerivation ? query.derivedFactType : nil;
		ORMDerivationRule *rule = fact != nil ? [_model.derivationRules objectForKey:fact.identifier] : nil;
		if (rule.noteId == nil) {
			continue;
		}
		verbalizer = verbalizer ?: [[ORMVerbalizer alloc] initWithModel:_model];
		NSString *text = [[ORMVerbalizer plainTextOfSentences:[verbalizer sentencesForQuery:query]]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([text length] > 0 && ![rule.informalText isEqualToString:text]) {
			[changes addObject:@[ fact, rule, text ]];
		}
	}
	if ([changes count] == 0) {
		return;
	}
	[self changeModel:^{
		for (NSArray *change in changes) {
			[(ORMDerivationRule *)[change objectAtIndex:1] setInformalText:[change lastObject]];
			[self wrote:[change firstObject]];
		}
	}];
}

- (void)wrote:(ORMElement *)element
{
	if (element != nil && [_wrote indexOfObjectIdenticalTo:element] == NSNotFound) {
		[_wrote addObject:element];
	}
}

/* The object types, fact types and constraints whose NORMA data a change
 * to the elements may change: an object type's fact types and identifier,
 * a fact type's players and internal constraints, a constraint's fact
 * types and what it identifies, an element's owner. */
- (NSArray<ORMElement *> *)affectedBy:(NSArray<ORMElement *> *)touched
{
	NSMutableArray *affected = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	NSMutableArray *pending = [NSMutableArray array];
	for (ORMElement *element in touched) {
		if ([element isKindOfClass:[ORMRole class]]) {
			[pending addObject:[(ORMRole *)element factType] ?: (id)[NSNull null]];
			[pending addObject:[(ORMRole *)element player] ?: (id)[NSNull null]];
		} else if ([element isKindOfClass:[ORMReading class]]) {
			[pending addObject:[[(ORMReading *)element readingOrder] factType] ?: (id)[NSNull null]];
		} else if ([element isKindOfClass:[ORMReadingOrder class]]) {
			[pending addObject:[(ORMReadingOrder *)element factType] ?: (id)[NSNull null]];
		} else if ([element isKindOfClass:[ORMRoleSequence class]]) {
			for (ORMRole *role in [(ORMRoleSequence *)element roles]) {
				[pending addObject:role.factType ?: (id)[NSNull null]];
			}
		}
		[pending addObject:element];
	}
	for (id element in pending) {
		if (element == [NSNull null] || [seen containsObject:[NSValue valueWithNonretainedObject:element]]) {
			continue;
		}
		BOOL own = [element isKindOfClass:[ORMObjectType class]] || [element isKindOfClass:[ORMFactType class]]
			|| [element isKindOfClass:[ORMConstraint class]];
		if (!own) {
			continue;
		}
		[seen addObject:[NSValue valueWithNonretainedObject:element]];
		[affected addObject:element];
	}
	/* One step out from each: what it names, and what names it. */
	NSArray *first = [affected copy];
	for (ORMElement *element in first) {
		NSMutableArray *related = [NSMutableArray array];
		if ([element isKindOfClass:[ORMObjectType class]]) {
			ORMObjectType *type = (ORMObjectType *)element;
			for (ORMRole *role in type.playedRoles) {
				[related addObject:role.factType ?: (id)[NSNull null]];
			}
			[related addObject:type.preferredIdentifier ?: (id)[NSNull null]];
			[related addObject:type.nestedFactType ?: (id)[NSNull null]];
		} else if ([element isKindOfClass:[ORMFactType class]]) {
			ORMFactType *fact = (ORMFactType *)element;
			for (ORMRole *role in fact.roles) {
				[related addObject:role.player ?: (id)[NSNull null]];
			}
			[related addObjectsFromArray:fact.internalConstraints ?: @[]];
			[related addObject:fact.objectifyingType ?: (id)[NSNull null]];
			/* A link fact type's role reckons with the role it stands for. */
			[related addObjectsFromArray:fact.linkFactTypes ?: @[]];
		} else if ([element isKindOfClass:[ORMConstraint class]]) {
			ORMConstraint *constraint = (ORMConstraint *)element;
			for (ORMRole *role in [constraint allRoles]) {
				[related addObject:role.factType ?: (id)[NSNull null]];
				for (ORMRole *proxy in role.proxies) {
					[related addObject:proxy.factType ?: (id)[NSNull null]];
				}
			}
			[related addObject:constraint.preferredIdentifierFor ?: (id)[NSNull null]];
		}
		for (id other in related) {
			if (other != [NSNull null] && ![seen containsObject:[NSValue valueWithNonretainedObject:other]]) {
				[seen addObject:[NSValue valueWithNonretainedObject:other]];
				[affected addObject:other];
			}
		}
	}
	return affected;
}

- (void)deleted:(ORMElement *)element
{
	if (element != nil && [_deleted indexOfObjectIdenticalTo:element] == NSNotFound) {
		[_deleted addObject:element];
	}
}

- (void)group:(NSString *)name with:(void (^)(void))operations
{
	[self apply:name rollback:NO with:^BOOL {
		operations();
		return YES;
	}];
}

- (BOOL)group:(NSString *)name trying:(BOOL (^)(void))operations
{
	return [self apply:name rollback:YES with:operations];
}

/* Undo and redo alike: the elements the change touched put back, and
 * whether the document had changes; the journal that does it again kept
 * for the other. In tests, the document is then the bytes it was. */
- (void)restoreJournal:(NSArray *)state
{
	NSData *now = ORMChecksAgreement ? ORMDataOfDocument(_document) : nil;
	ORMXMLJournal *again = [[state objectAtIndex:0] restore];
	[_undoManager registerUndoWithTarget:self selector:@selector(restoreJournal:)
	                              object:@[ again, @(_hasChanges), now ?: (id)[NSNull null] ]];
	_hasChanges = [[state objectAtIndex:1] boolValue];
	id expected = [state objectAtIndex:2];
	if (ORMChecksAgreement && expected != [NSNull null] && ![ORMDataOfDocument(_document) isEqualToData:expected]) {
		[NSException raise:NSInternalInconsistencyException
		            format:@"Undone or done again, the document is not what it was: %@",
		                   ORMFirstDifference(expected, ORMDataOfDocument(_document))];
	}
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
			ORMDetach(child);
		}
	}
	/* The settings that point at what was dropped. */
	for (NSXMLElement *state in ORMChildren(root, CORE, @"GenerationState")) {
		for (NSXMLElement *settings in ORMChildren(state, CORE, @"GenerationSettings")) {
			for (NSXMLNode *setting in [[settings children] copy]) {
				if ([generated containsObject:[setting URI]]) {
					ORMDetach(setting);
				}
			}
			ORMPruneIfEmpty(settings);
		}
		ORMPruneIfEmpty(state);
	}
	/* NORMA checks the model as it opens it and lists what it finds. */
	ORMDetach(ORMChild(ORMModelElementOfDocument(copy), CORE, @"ModelErrors"));
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
			ORMDetach(element);
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

- (NSString *)nextName:(NSString *)prefix
{
	/* The model's names, and those of what the change being made took out
	 * of it: the document's until it is written. */
	NSMutableArray *names = [NSMutableArray arrayWithArray:[_model.removedNames allObjects] ?: @[]];
	for (ORMElement *element in [[_model valueForKey:@"elementsById"] allValues]) {
		if (element.name != nil) {
			[names addObject:element.name];
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

@end
