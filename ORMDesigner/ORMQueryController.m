/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryController.h"

static NSArray<NSString *> *
ORMComparisonTitles(void)
{
	return @[ @"—", @"=", @"<>", @"<", @"<=", @">", @">=" ];
}

@interface ORMQueryController () <NSTabViewDelegate>
@property (nonatomic, strong) IBOutlet NSPopUpButton *queryPopUp;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *startAtPopUp;
@property (nonatomic, strong) IBOutlet NSOutlineView *outline;
@property (nonatomic, strong) IBOutlet NSTableView *roles;
@property (nonatomic, strong) IBOutlet NSButton *listCheck;
@property (nonatomic, strong) IBOutlet NSPopUpButton *comparisonPopUp;
@property (nonatomic, strong) IBOutlet NSTextField *valueField;
@property (nonatomic, strong) IBOutlet NSButton *alternativesCheck;
@property (nonatomic, strong) IBOutlet NSPopUpButton *operatorPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *countComparisonPopUp;
@property (nonatomic, strong) IBOutlet NSTextField *countField;
@property (nonatomic, strong) IBOutlet NSTextField *labelField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *aggregatePopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *aggregateNodePopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *groupPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *comparedPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *comparedGroupPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *sortPopUp;
@property (nonatomic, strong) IBOutlet NSButton *removeStepButton;
@property (nonatomic, strong) IBOutlet NSTextView *verbalizationView;
@property (nonatomic, strong) IBOutlet NSTextView *fetchView;
@property (nonatomic, strong) IBOutlet NSTextView *requestView;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;
@property (nonatomic, strong) IBOutlet NSTableView *resultsTable;
@property (nonatomic, strong) IBOutlet NSTextField *resultsLabel;
/* What the query is for (docs/RULES.md): its kind; a constraint's
 * modality; a calculation's function and node. */
@property (nonatomic, strong) IBOutlet NSPopUpButton *kindPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *modalityPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *functionPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *ofPopUp;
@property (nonatomic, strong) IBOutlet NSButton *buildCheck;
@end

/* The most rows the Results tab reads: a page of the plan's objects. */
static const NSUInteger ORMResultsPage = 200;

@implementation ORMQueryController
{
	/* The projection the query and its nodes were read from: theirs and the
	 * roles' links to one another are weak, so it is held until the next is
	 * read. */
	ORMModel *_model;
	/* The rules were not checked last time, the window hidden. */
	BOOL _rulesUnchecked;
	ORMQuery *_query;
	/* Node and step ids -> what they are in the query as now read. */
	NSMutableDictionary<NSString *, id> *_items;
	/* Each item's children, as read; the outline's items are these very
	 * strings, the same each time it asks. */
	NSMutableDictionary<NSString *, NSArray<NSString *> *> *_children;
	NSArray<NSString *> *_roots;
	NSArray<ORMRole *> *_available;
	NSString *_selectedId;
	/* The outline is being filled: what it says of its selection is its
	 * old one, not the user's. */
	BOOL _reloading;
	/* The sample population in a store, made again when the model changes,
	 * and the rows the query reads from it. */
	ORMPopulationStore *_store;
	NSManagedObjectContext *_context;
	ORMQueryResult *_result;
	NSString *_resultsNote;
}

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super initWithWindowNibName:@"ORMQueryWindow"])) {
		_editor = editor;
		_items = [NSMutableDictionary dictionary];
		_children = [NSMutableDictionary dictionary];
		[self window];
	}
	return self;
}

/* What the XIB does not say: the roles table's double click, and the
 * fetch request in a fixed-pitch font. */
- (void)windowDidLoad
{
	[super windowDidLoad];
	[self.roles setTarget:self];
	[self.roles setDoubleAction:@selector(addStep:)];
	[self.fetchView setFont:[NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]]];
	[self.requestView setFont:[NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]]];
	[self modelDidChange];
}

#pragma mark Reading the model

/* The document's queries, edited. */
- (ORMQueryEditor *)queries
{
	return [[ORMQueryEditor alloc] initWithEditor:self.editor];
}

- (NSString *)selectedId
{
	return _selectedId;
}

- (void)say:(NSString *)message
{
	[_statusLabel setStringValue:message ?: @""];
}

- (void)showWindow:(id)sender
{
	[super showWindow:sender];
	if (_rulesUnchecked) {
		[self modelDidChange];
	}
}

- (void)modelDidChange
{
	ORMModel *model = self.editor.model;
	_model = model;
	_store = nil;
	_context = nil;
	NSArray *queries = [ORMQuery queriesInModel:model];
	if (self.queryId != nil && [ORMQuery queryWithId:self.queryId inModel:model] == nil) {
		self.queryId = nil;
	}
	if (self.queryId == nil) {
		self.queryId = [[queries firstObject] identifier];
	}
	[_queryPopUp removeAllItems];
	/* Checking the rules builds a store of the whole population: not for a
	 * window no one sees. Shown again, it checks them. */
	BOOL seen = [self isWindowLoaded] && [[self window] isVisible];
	_rulesUnchecked = !seen;
	NSSet *broken = seen ? [self brokenRules] : [NSSet set];
	for (ORMQuery *query in queries) {
		/* A rule or a calculation says so beside its name, and whether the
		 * sample population breaks it. */
		BOOL breaks = [broken containsObject:query.identifier];
		NSString *kind = query.kind == ORMQueryConstraint ? (breaks ? @" (rule, broken)" : @" (rule)")
			: (query.kind == ORMQueryCalculation ? (breaks ? @" (calculation, broken)" : @" (calculation)") : @"");
		[_queryPopUp addItemWithTitle:[query.name stringByAppendingString:kind]];
		[[_queryPopUp lastItem] setRepresentedObject:query.identifier];
		if ([query.identifier isEqualToString:self.queryId]) {
			[_queryPopUp selectItem:[_queryPopUp lastItem]];
		}
	}
	NSString *started = [[_startAtPopUp selectedItem] representedObject];
	[_startAtPopUp removeAllItems];
	NSArray *types = [[model visibleObjectTypes] sortedArrayUsingComparator:^NSComparisonResult(ORMObjectType *a,
	                                                                                              ORMObjectType *b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	for (ORMObjectType *type in types) {
		[_startAtPopUp addItemWithTitle:type.name ?: @"?"];
		[[_startAtPopUp lastItem] setRepresentedObject:type.identifier];
		if ([type.identifier isEqualToString:started]) {
			[_startAtPopUp selectItem:[_startAtPopUp lastItem]];
		}
	}

	_query = self.queryId != nil ? [ORMQuery queryWithId:self.queryId inModel:model] : nil;
	[_nameField setStringValue:_query.name ?: @""];
	[_nameField setEnabled:_query != nil];
	[self showKind];
	[_items removeAllObjects];
	[_children removeAllObjects];
	for (ORMQueryNode *node in [_query nodes]) {
		[_items setObject:node forKey:node.identifier];
		NSMutableArray *steps = [NSMutableArray array];
		for (ORMQueryStep *step in node.steps) {
			[_items setObject:step forKey:step.identifier];
			[steps addObject:step.identifier];
			[_children setObject:[step.nodes valueForKey:@"identifier"] forKey:step.identifier];
		}
		[_children setObject:steps forKey:node.identifier];
	}
	_roots = _query.root != nil ? @[ _query.root.identifier ] : @[];
	/* The children's strings are the keys': one instance for each item. */
	for (NSString *key in [_children allKeys]) {
		NSMutableArray *canonical = [NSMutableArray array];
		for (NSString *child in [_children objectForKey:key]) {
			[canonical addObject:[self canonical:child]];
		}
		[_children setObject:canonical forKey:[self canonical:key]];
	}
	_roots = [_roots count] > 0 ? @[ [self canonical:[_roots firstObject]] ] : @[];
	if (_selectedId != nil && [_items objectForKey:_selectedId] == nil) {
		_selectedId = nil;
	}
	if (_selectedId == nil) {
		_selectedId = _query.root.identifier;
	}
	_reloading = YES;
	[_outline reloadData];
	/* Each root, not nil: GNUstep expands nothing for a nil item. */
	for (NSString *root in _roots) {
		[_outline expandItem:root expandChildren:YES];
	}
	NSInteger row = _selectedId != nil ? [_outline rowForItem:[self canonical:_selectedId]] : -1;
	if (row >= 0) {
		[_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	}
	_reloading = NO;
	[self selectionDidChange];
	[self showQuery];
}

- (void)showQuery
{
	[_verbalizationView setString:[self verbalizationText]];
	[_fetchView setString:[self fetchText]];
	[_requestView setString:[self requestText]];
	_result = nil;
	if ([[[self.tabs selectedTabViewItem] identifier] isEqual:@"results"]) {
		[self showResults];
	}
	[self say:_query == nil ? @"Choose an object type to start a query from, and New."
	       : (_query.isComplete ? @"" : @"Something this query went through is no longer in the model.")];
}

- (NSString *)verbalizationText
{
	if (_query == nil) {
		return @"";
	}
	NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:self.editor.model] sentencesForQuery:_query];
	return [ORMVerbalizer plainTextOfSentences:sentences];
}

/* The request to the service ODataKit makes of the mapping. */
- (NSString *)requestText
{
	if (_query == nil) {
		return @"";
	}
	ORMCoreDataMapping *mapping = [[ORMCoreDataMapping mappingsOfDocument:self.editor.document] firstObject];
	NSError *error = nil;
	ORMQueryOData *odata = [ORMQueryOData requestForQuery:_query model:self.editor.model mapping:mapping error:&error];
	if (odata == nil) {
		return [NSString stringWithFormat:@"No request: %@", [error localizedDescription]];
	}
	NSMutableString *text = [NSMutableString stringWithString:[odata requestText]];
	for (NSString *note in odata.notes) {
		[text appendFormat:@"\nNote: %@", note];
	}
	return text;
}

- (NSString *)fetchText
{
	if (_query == nil) {
		return @"";
	}
	ORMCoreDataMapping *mapping = [[ORMCoreDataMapping mappingsOfDocument:self.editor.document] firstObject];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:self.editor.model mapping:mapping];
	ORMQueryPlan *plan = [planner planForQuery:_query];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	NSError *error = nil;
	NSString *program = plan.entityName != nil ? [interpreter programForPlan:plan error:&error] : nil;
	/* The plan, and how the interpreter runs it against a store. */
	NSMutableString *text = [NSMutableString stringWithFormat:@"%@\n\n%@", [plan text],
	                                                          program ?: [error localizedDescription] ?: @""];
	for (NSString *note in plan.notes) {
		[text appendFormat:@"\nNote: %@", note];
	}
	return text;
}

#pragma mark Results

/* Whether the model has a sample population to read. */
- (BOOL)hasPopulation
{
	for (ORMObjectType *type in self.editor.model.objectTypes) {
		if ([[type instances] count] > 0) {
			return YES;
		}
	}
	return NO;
}

/* The sample population in a store of the mapped model, made once for the
 * model as it is. */
- (NSManagedObjectContext *)populationContext:(ORMCDModel *)coreData error:(NSError **)error
{
	if (_context == nil) {
		_store = [[ORMPopulationStore alloc] initWithModel:self.editor.model coreData:coreData];
		_context = [_store newContextWithError:error];
	}
	return _context;
}

/* The rules and value calculations the sample population breaks, by id:
 * marked in the list. */
- (NSSet<NSString *> *)brokenRules
{
	if (![self hasPopulation]) {
		return [NSSet set];
	}
	ORMCoreDataMapping *mapping = [[ORMCoreDataMapping mappingsOfDocument:self.editor.document] firstObject];
	ORMRuleChecker *checker = [[ORMRuleChecker alloc] initWithModel:self.editor.model mapping:mapping];
	if ([checker.rules count] == 0 && [checker.valueCalculations count] == 0) {
		return [NSSet set];
	}
	NSManagedObjectContext *context = [self populationContext:checker.coreData error:NULL];
	NSArray *violations = context != nil ? [checker violationsInContext:context limit:1 error:NULL] : nil;
	return [NSSet setWithArray:[violations valueForKeyPath:@"rule.identifier"] ?: @[]];
}

- (ORMQueryResult *)result
{
	if (_result != nil || _query == nil) {
		return _result;
	}
	_resultsNote = nil;
	if (![self hasPopulation]) {
		_resultsNote = @"The model has no sample population: Make Up a Population gives it one.";
		return nil;
	}
	ORMCoreDataMapping *mapping = [[ORMCoreDataMapping mappingsOfDocument:self.editor.document] firstObject];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:self.editor.model mapping:mapping];
	NSError *error = nil;
	if ([self populationContext:planner.coreData error:&error] == nil) {
		_resultsNote = [NSString stringWithFormat:@"The population cannot be put in a store: %@", [error localizedDescription]];
		return nil;
	}
	ORMQueryPlan *plan = [planner planForQuery:_query];
	if (plan.entityName == nil) {
		_resultsNote = @"The query reads nothing yet.";
		return nil;
	}
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:_store.managedObjectModel];
	ORMQueryCursor *cursor = [interpreter cursorForPlan:plan inContext:_context error:&error];
	_result = [cursor nextPage:ORMResultsPage error:&error];
	if (_result == nil) {
		_resultsNote = [NSString stringWithFormat:@"The query cannot be run: %@", [error localizedDescription]];
		return nil;
	}
	/* A rule's rows are its violations. */
	BOOL rule = _query.kind == ORMQueryConstraint;
	NSUInteger found = rule && [_result.columnTitles count] == 0 ? [_result.objects count] : [_result.rows count];
	NSMutableString *note = [NSMutableString stringWithFormat:@"%lu %@ %@ the sample population%@.", (unsigned long)found,
	                                                          rule ? (found == 1 ? @"violation" : @"violations")
	                                                               : (found == 1 ? @"row" : @"rows"),
	                                                          rule ? @"of the rule in" : @"of",
	                                                          [cursor atEnd] ? @"" : @", the first page"];
	if ([_store.notes count] > 0) {
		[note appendFormat:@" Not in the store: %@", [_store.notes componentsJoinedByString:@" "]];
	}
	_resultsNote = note;
	return _result;
}

/* The rows in the table, a column each of the plan's columns. */
- (void)showResults
{
	ORMQueryResult *result = [self result];
	NSTableView *table = self.resultsTable;
	NSArray *titles = result.columnTitles ?: @[];
	while ([[table tableColumns] count] > MAX([titles count], (NSUInteger)1)) {
		[table removeTableColumn:[[table tableColumns] lastObject]];
	}
	while ([[table tableColumns] count] < [titles count]) {
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:
			[NSString stringWithFormat:@"%lu", (unsigned long)[[table tableColumns] count]]];
		[column setWidth:160];
		[[column dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[table addTableColumn:column];
	}
	for (NSUInteger i = 0; i < [[table tableColumns] count]; i++) {
		NSTableColumn *column = [[table tableColumns] objectAtIndex:i];
		[column setIdentifier:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
		[[column headerCell] setStringValue:i < [titles count] ? [titles objectAtIndex:i] : @""];
	}
	[table reloadData];
	[self.resultsLabel setStringValue:_resultsNote ?: @""];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item
{
	(void)tabView;
	if ([[item identifier] isEqual:@"results"]) {
		[self showResults];
	}
}

/* A value as a cell shows it: none as a dash. */
static NSString *
ORMCellText(id value)
{
	if (value == nil || value == [NSNull null]) {
		return @"—";
	}
	if ([value isKindOfClass:[NSArray class]]) {
		/* An object by the values identifying it: "BSc, U1". */
		NSMutableArray *parts = [NSMutableArray array];
		for (id part in value) {
			[parts addObject:ORMCellText(part)];
		}
		return [parts componentsJoinedByString:@", "];
	}
	if ([value isKindOfClass:[NSDate class]]) {
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		[formatter setDateFormat:@"yyyy-MM-dd HH:mm"];
		[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		return [formatter stringFromDate:value];
	}
	return [value description];
}

- (IBAction)makeUpPopulation:(id)sender
{
	(void)sender;
	ORMPopulationGenerator *generator = [[ORMPopulationGenerator alloc] initWithModel:self.editor.model];
	ORMSamplePopulation *population = [generator population];
	__block BOOL added = NO;
	__block NSString *reason = nil;
	/* Refused, the population there stays. */
	[self.editor group:@"Make Up a Sample Population" trying:^BOOL {
		[self.editor.populationEditor removePopulation];
		/* With what the stored derivations derive from it. */
		added = [self.editor.populationEditor addPopulation:population reason:&reason]
		        && [self.editor.populationEditor bringStoredDerivationsUpToDate:&reason];
		return added;
	}];
	if (!added) {
		[self say:[NSString stringWithFormat:@"No population: %@", reason]];
		return;
	}
	[self say:[generator.notes count] > 0 ? [generator.notes componentsJoinedByString:@" "]
	                                      : @"A sample population that meets the constraints."];
}

#pragma mark Selection

- (void)selectElement:(NSString *)nodeOrStepId
{
	_selectedId = [nodeOrStepId copy];
	NSInteger row = [_outline rowForItem:[self canonical:nodeOrStepId]];
	if (row >= 0) {
		[_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	}
	[self selectionDidChange];
}

- (ORMQueryNode *)selectedNode
{
	id item = _selectedId != nil ? [_items objectForKey:_selectedId] : nil;
	return [item isKindOfClass:[ORMQueryNode class]] ? item : nil;
}

- (ORMQueryStep *)selectedStep
{
	id item = _selectedId != nil ? [_items objectForKey:_selectedId] : nil;
	return [item isKindOfClass:[ORMQueryStep class]] ? item : nil;
}

- (NSArray<ORMRole *> *)availableRoles
{
	return _available ?: @[];
}

- (void)selectionDidChange
{
	ORMQueryNode *node = [self selectedNode];
	ORMQueryStep *step = [self selectedStep];
	for (NSControl *control in @[ _listCheck, _comparisonPopUp, _valueField, _alternativesCheck, _labelField,
	                              _sortPopUp ]) {
		[control setEnabled:node != nil];
	}
	for (NSControl *control in @[ _operatorPopUp, _aggregatePopUp, _aggregateNodePopUp, _countComparisonPopUp, _countField,
	                              _removeStepButton, _groupPopUp, _comparedPopUp, _comparedGroupPopUp ]) {
		[control setEnabled:step != nil];
	}
	[_listCheck setState:node.isProjected ? NSControlStateValueOn : NSControlStateValueOff];
	NSUInteger comparison = node.comparison != nil ? [ORMComparisonTitles() indexOfObject:node.comparison] : 0;
	[_comparisonPopUp selectItemAtIndex:comparison != NSNotFound ? (NSInteger)comparison : 0];
	/* Compared with another node: its designation, as it is typed. */
	[_valueField setStringValue:node.comparedNode != nil ? [node.comparedNode designation] : node.value ?: @""];
	[_labelField setStringValue:node.label ?: @""];
	[_alternativesCheck setState:node.combinesWithOr ? NSControlStateValueOn : NSControlStateValueOff];
	[_operatorPopUp selectItemAtIndex:step != nil ? step.operatorKind : 0];
	NSUInteger count = step.countComparison != nil ? [ORMComparisonTitles() indexOfObject:step.countComparison] : 0;
	[_countComparisonPopUp selectItemAtIndex:count != NSNotFound ? (NSInteger)count : 0];
	[_countField setStringValue:step.countComparison != nil ? step.aggregateValue ?: @"" : @""];
	[_aggregatePopUp selectItemAtIndex:step != nil ? step.aggregate : 0];
	[_sortPopUp selectItemAtIndex:node != nil ? node.sortOrder : 0];
	/* What the step's aggregate can be of: the nodes it reaches. */
	[_aggregateNodePopUp removeAllItems];
	NSMutableArray *below = [NSMutableArray arrayWithArray:step.nodes ?: @[]];
	for (NSUInteger i = 0; i < [below count]; i++) {
		ORMQueryNode *at = [below objectAtIndex:i];
		[_aggregateNodePopUp addItemWithTitle:[at designation]];
		[[_aggregateNodePopUp lastItem] setRepresentedObject:at.identifier];
		if (at == step.aggregateNode) {
			[_aggregateNodePopUp selectItem:[_aggregateNodePopUp lastItem]];
		}
		for (ORMQueryStep *next in at.steps) {
			[below addObjectsFromArray:next.nodes];
		}
	}
	/* What it is for, and what it is compared with: the nodes above. */
	[_groupPopUp removeAllItems];
	[_comparedGroupPopUp removeAllItems];
	for (ORMQueryNode *above = step.parent; above != nil; above = above.step.parent) {
		[_groupPopUp addItemWithTitle:[above designation]];
		[[_groupPopUp lastItem] setRepresentedObject:above.identifier];
		if (above == step.groupNode) {
			[_groupPopUp selectItem:[_groupPopUp lastItem]];
		}
		[_comparedGroupPopUp addItemWithTitle:[@"for " stringByAppendingString:[above designation]]];
		[[_comparedGroupPopUp lastItem] setRepresentedObject:above.identifier];
		if (above == step.comparedGroupNode) {
			[_comparedGroupPopUp selectItem:[_comparedGroupPopUp lastItem]];
		}
	}
	[_comparedPopUp selectItemAtIndex:step.comparesAggregates ? (NSInteger)step.comparedAggregate + 1 : 0];
	[_countField setHidden:step.comparesAggregates];
	[_comparedGroupPopUp setHidden:!step.comparesAggregates];
	_available = node != nil ? [ORMQuery rolesFrom:node.objectType] : @[];
	[_roles reloadData];
}

/* What the query is for, and what only its kind has. */
- (void)showKind
{
	ORMQueryKind kind = _query != nil ? _query.kind : ORMQueryList;
	[_kindPopUp setEnabled:_query != nil];
	[_kindPopUp selectItemAtIndex:kind];
	[_modalityPopUp setEnabled:kind == ORMQueryConstraint];
	[_modalityPopUp selectItemAtIndex:_query.isDeontic ? 1 : 0];
	[_functionPopUp setEnabled:kind == ORMQueryCalculation];
	[_functionPopUp selectItemAtIndex:kind == ORMQueryCalculation ? _query.calculationFunction : 0];
	/* What a calculation can be of: every node below the root. */
	[_ofPopUp removeAllItems];
	[_ofPopUp addItemWithTitle:@"—"];
	for (ORMQueryNode *node in kind == ORMQueryCalculation ? [_query nodes] : @[]) {
		if (node == _query.root) {
			continue;
		}
		[_ofPopUp addItemWithTitle:[node designation]];
		[[_ofPopUp lastItem] setRepresentedObject:node.identifier];
		if (node == _query.calculatedNode) {
			[_ofPopUp selectItem:[_ofPopUp lastItem]];
		}
	}
	[_ofPopUp setEnabled:kind == ORMQueryCalculation];
}

#pragma mark Actions

- (void)kindChanged:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	if (self.queryId == nil
	    || ![[self queries] setKind:(ORMQueryKind)[_kindPopUp indexOfSelectedItem] ofQuery:self.queryId reason:&reason]) {
		NSBeep();
		[self say:reason ?: @"Choose a query first."];
	}
}

- (void)modalityChanged:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	if (![[self queries] setDeontic:[_modalityPopUp indexOfSelectedItem] == 1 ofQuery:self.queryId reason:&reason]) {
		NSBeep();
		[self say:reason ?: @"Only a constraint is alethic or deontic."];
	}
}

- (void)calculationChanged:(id)sender
{
	(void)sender;
	NSString *nodeId = [[_ofPopUp selectedItem] representedObject];
	if (nodeId == nil) {
		[self say:@"Choose the node the calculation is of."];
		return;
	}
	NSString *reason = nil;
	if (![[self queries] setCalculation:(ORMQueryCalculationFunction)[_functionPopUp indexOfSelectedItem] ofNode:nodeId
	                            inQuery:self.queryId reason:&reason]) {
		NSBeep();
		[self say:reason ?: @"Only a calculation computes a value."];
	}
}

- (NSString *)addQueryFrom:(NSString *)objectTypeId
{
	NSString *reason = nil;
	NSString *query = [[self queries] addQueryNamed:nil from:objectTypeId reason:&reason];
	if (query == nil) {
		NSBeep();
		[self say:reason];
		return nil;
	}
	self.queryId = query;
	_selectedId = nil;
	[self modelDidChange];
	return query;
}

- (void)newQuery:(id)sender
{
	(void)sender;
	NSString *type = [[_startAtPopUp selectedItem] representedObject];
	if (type != nil) {
		[self addQueryFrom:type];
	}
}

- (void)chooseQuery:(id)sender
{
	(void)sender;
	self.queryId = [[_queryPopUp selectedItem] representedObject];
	_selectedId = nil;
	[self modelDidChange];
}

- (void)removeQuery:(id)sender
{
	(void)sender;
	if (self.queryId != nil) {
		[[self queries] removeQuery:self.queryId];
		self.queryId = nil;
		_selectedId = nil;
		[self modelDidChange];
	}
}

- (void)nameChanged:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	if (_query != nil && ![[_nameField stringValue] isEqualToString:_query.name]
	    && ![[self queries] renameQuery:_query.identifier to:[_nameField stringValue] reason:&reason]) {
		NSBeep();
		[self say:reason];
		[_nameField setStringValue:_query.name];
	}
}

- (NSString *)addStepThrough:(ORMRole *)role
{
	ORMQueryNode *node = [self selectedNode];
	if (node == nil || role == nil) {
		return nil;
	}
	NSString *reason = nil;
	NSString *step = [[self queries] addStepTo:node.identifier through:role.identifier reason:&reason];
	if (step == nil) {
		NSBeep();
		[self say:reason];
		return nil;
	}
	_selectedId = step;
	[self modelDidChange];
	return step;
}

- (BOOL)buildsFromDiagram
{
	return [_buildCheck state] == NSControlStateValueOn;
}

- (NSString *)followRole:(ORMRole *)role
{
	ORMQueryNode *node = [self selectedNode];
	if (node == nil) {
		[self say:@"Select the node to go on from."];
		return nil;
	}
	/* The role it enters by: one the node's object type plays, the role
	 * clicked the far end where it can be. By id: the role may be another
	 * projection's. */
	role = [_model elementWithId:role.identifier] ?: role;
	NSArray *playable = [[ORMQuery rolesFrom:node.objectType] valueForKey:@"identifier"];
	ORMRole *entry = nil;
	for (ORMRole *each in role.factType.roles) {
		if ([playable containsObject:each.identifier] && (entry == nil || entry == role)) {
			entry = each;
		}
	}
	if (entry == nil) {
		NSBeep();
		[self say:[NSString stringWithFormat:@"%@ plays no role of \"%@\".", node.objectType.name,
		                                     [[role.factType primaryReading] expandedText] ?: role.factType.name]];
		return nil;
	}
	NSString *step = [self addStepThrough:entry];
	if (step == nil) {
		return nil;
	}
	ORMQueryStep *added = [_items objectForKey:step];
	ORMQueryNode *reached = [added.nodes firstObject];
	for (ORMQueryNode *each in added.nodes) {
		if ([each.role.identifier isEqualToString:role.identifier]) {
			reached = each;
		}
	}
	if (reached != nil) {
		[self selectElement:reached.identifier];
	}
	return reached.identifier ?: step;
}

- (void)addStep:(id)sender
{
	(void)sender;
	NSInteger row = [_roles selectedRow];
	if (row >= 0 && (NSUInteger)row < [_available count]) {
		[self addStepThrough:[_available objectAtIndex:(NSUInteger)row]];
	}
}

- (void)removeStep:(id)sender
{
	(void)sender;
	ORMQueryStep *step = [self selectedStep];
	if (step != nil) {
		_selectedId = step.parent.identifier;
		[[self queries] removeStep:step.identifier];
		[self modelDidChange];
	}
}

- (void)listChanged:(id)sender
{
	(void)sender;
	ORMQueryNode *node = [self selectedNode];
	if (node != nil) {
		[[self queries] setProjected:[_listCheck state] == NSControlStateValueOn ofNode:node.identifier];
	}
}

- (void)conditionChanged:(id)sender
{
	(void)sender;
	ORMQueryNode *node = [self selectedNode];
	if (node == nil) {
		return;
	}
	NSInteger index = [_comparisonPopUp indexOfSelectedItem];
	NSString *comparison = index > 0 ? [ORMComparisonTitles() objectAtIndex:(NSUInteger)index] : nil;
	NSString *value = [_valueField stringValue];
	NSString *was = node.comparedNode != nil ? [node.comparedNode designation] : node.value ?: @"";
	if ([comparison isEqualToString:node.comparison ?: @""] && [value isEqualToString:was]) {
		return;
	}
	if (comparison == nil && node.comparison == nil) {
		return;
	}
	/* "Country1": another node of the query, of the same object type and
	 * with a label, rather than a value. */
	ORMQueryNode *other = nil;
	for (ORMQueryNode *candidate in comparison != nil ? [_query nodes] : @[]) {
		if (candidate != node && candidate.label != nil && candidate.objectType == node.objectType
		    && [[candidate designation] isEqualToString:value]) {
			other = candidate;
		}
	}
	NSString *reason = nil;
	BOOL done = other != nil ? [[self queries] setCondition:comparison toNode:other.identifier ofNode:node.identifier
	                                                 reason:&reason]
	                         : [[self queries] setCondition:comparison value:value ofNode:node.identifier reason:&reason];
	if (!done) {
		NSBeep();
		[self say:reason];
	}
}

- (void)labelChanged:(id)sender
{
	(void)sender;
	ORMQueryNode *node = [self selectedNode];
	if (node != nil) {
		[[self queries] setLabel:[[_labelField stringValue]
		                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
		                  ofNode:node.identifier];
	}
}

- (void)sortChanged:(id)sender
{
	(void)sender;
	ORMQueryNode *node = [self selectedNode];
	if (node != nil) {
		[[self queries] setSortOrder:(ORMQuerySort)MAX(0, [_sortPopUp indexOfSelectedItem]) ofNode:node.identifier];
	}
}

- (void)alternativesChanged:(id)sender
{
	(void)sender;
	ORMQueryNode *node = [self selectedNode];
	if (node != nil) {
		[[self queries] setCombinesWithOr:[_alternativesCheck state] == NSControlStateValueOn ofNode:node.identifier];
	}
}

- (void)operatorChanged:(id)sender
{
	(void)sender;
	ORMQueryStep *step = [self selectedStep];
	if (step != nil) {
		[[self queries] setOperator:(ORMQueryOperator)[_operatorPopUp indexOfSelectedItem] ofStep:step.identifier];
	}
}

- (void)countChanged:(id)sender
{
	(void)sender;
	ORMQueryStep *step = [self selectedStep];
	if (step == nil) {
		return;
	}
	NSInteger index = [_countComparisonPopUp indexOfSelectedItem];
	NSString *comparison = index > 0 ? [ORMComparisonTitles() objectAtIndex:(NSUInteger)index] : nil;
	NSString *value = [_countField stringValue];
	ORMQueryAggregate aggregate = (ORMQueryAggregate)MAX(0, [_aggregatePopUp indexOfSelectedItem]);
	NSString *nodeId = [[_aggregateNodePopUp selectedItem] representedObject];
	if ([comparison ?: @"" isEqualToString:step.countComparison ?: @""] && aggregate == step.aggregate
	    && [nodeId ?: @"" isEqualToString:step.aggregateNode.identifier ?: @""]
	    && (comparison == nil || [value isEqualToString:step.aggregateValue ?: @""])) {
		return;
	}
	NSString *reason = nil;
	if (![[self queries] setAggregate:aggregate ofNode:nodeId comparison:comparison value:value ofStep:step.identifier
	                           reason:&reason]) {
		NSBeep();
		[self say:reason];
	}
}

- (void)groupChanged:(id)sender
{
	(void)sender;
	ORMQueryStep *step = [self selectedStep];
	NSString *nodeId = [[_groupPopUp selectedItem] representedObject];
	NSString *reason = nil;
	if (step != nil && nodeId != nil && ![[self queries] setGroupNode:nodeId ofStep:step.identifier reason:&reason]) {
		NSBeep();
		[self say:reason];
	}
}

/* A value, or another aggregate of the same node for a node above. */
- (void)comparedChanged:(id)sender
{
	(void)sender;
	ORMQueryStep *step = [self selectedStep];
	if (step == nil) {
		return;
	}
	NSInteger index = [_comparedPopUp indexOfSelectedItem];
	NSString *nodeId = index > 0 ? ([[_comparedGroupPopUp selectedItem] representedObject] ?: step.parent.identifier) : nil;
	NSString *reason = nil;
	if (![[self queries] setComparedAggregate:(ORMQueryAggregate)MAX(0, index - 1) group:nodeId ofStep:step.identifier
	                                   reason:&reason]) {
		NSBeep();
		[self say:reason ?: @"Set the step's aggregate first."];
	}
}

#pragma mark The outline

/* Items are node and step ids: a node's children its steps, a step's
 * its nodes. */
- (NSString *)canonical:(NSString *)identifier
{
	for (NSString *key in _items) {
		if ([key isEqualToString:identifier]) {
			return key;
		}
	}
	return identifier;
}

- (NSArray<NSString *> *)childrenOf:(id)item
{
	if (item == nil) {
		return _roots ?: @[];
	}
	return [_children objectForKey:item] ?: @[];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	(void)outlineView;
	return (NSInteger)[[self childrenOf:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	(void)outlineView;
	return [[self childrenOf:item] objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	(void)outlineView;
	return [[self childrenOf:item] count] > 0;
}

- (NSString *)textOfNode:(ORMQueryNode *)node
{
	NSMutableString *text = [NSMutableString stringWithFormat:@"%@%@", node.isProjected ? @"✓ " : @"",
	                                                          [node designation]];
	if (node.comparedNode != nil) {
		[text appendFormat:@" %@ %@", node.comparison, [node.comparedNode designation]];
	} else if (node.comparison != nil) {
		[text appendFormat:@" %@ %@", node.comparison,
		                   [node isNumeric] ? node.value : [NSString stringWithFormat:@"'%@'", node.value ?: @""]];
	}
	if (node.sortOrder != ORMQueryUnsorted) {
		[text appendString:node.sortOrder == ORMQueryAscending ? @" ↑" : @" ↓"];
	}
	if (node.combinesWithOr && [node.steps count] > 1) {
		[text appendString:@"   (any of these)"];
	}
	return text;
}

- (NSString *)textOfStep:(ORMQueryStep *)step
{
	NSMutableString *reading = [NSMutableString stringWithString:[ORMQuery readingOfStep:step]];
	[reading replaceOccurrencesOfString:@"{0}"
	                         withString:[NSString stringWithFormat:@"that %@", step.parent.objectType.name]
	                            options:0
	                              range:NSMakeRange(0, [reading length])];
	for (NSUInteger i = 0; i < [step.nodes count]; i++) {
		[reading replaceOccurrencesOfString:[NSString stringWithFormat:@"{%lu}", (unsigned long)i + 1]
		                         withString:[[step.nodes objectAtIndex:i] objectType].name ?: @"?"
		                            options:0
		                              range:NSMakeRange(0, [reading length])];
	}
	NSString *operator = step.operatorKind == ORMQueryNot ? @"not " : step.operatorKind == ORMQueryMaybe ? @"maybe " : @"";
	NSString *group = step.groupNode != step.parent ? [@" for " stringByAppendingString:[step.groupNode designation]] : @"";
	NSString *compared = step.comparesAggregates
		? [NSString stringWithFormat:@"%@(%@) for %@", [ORMQuery nameOfAggregate:step.comparedAggregate],
		                             [step.aggregateNode designation], [step.comparedGroupNode designation]]
		: step.aggregateValue ?: @"";
	NSString *count = step.countComparison != nil
		? [NSString stringWithFormat:@"   %@(%@)%@ %@ %@", [ORMQuery nameOfAggregate:step.aggregate],
		                             [step.aggregateNode designation], group, step.countComparison, compared]
		: @"";
	return [NSString stringWithFormat:@"+ %@%@%@", operator, reading, count];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
	(void)outlineView;
	(void)column;
	id element = [_items objectForKey:item];
	if ([element isKindOfClass:[ORMQueryNode class]]) {
		return [self textOfNode:element];
	}
	if ([element isKindOfClass:[ORMQueryStep class]]) {
		return [self textOfStep:element];
	}
	return @"";
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	(void)notification;
	if (_reloading) {
		return;
	}
	NSInteger row = [_outline selectedRow];
	_selectedId = row >= 0 ? [_outline itemAtRow:row] : nil;
	[self selectionDidChange];
}

#pragma mark The roles table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == self.resultsTable) {
		return (NSInteger)[_result.rows count];
	}
	return (NSInteger)[_available count];
}

/* "lives in City", as the step would read. */
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView == self.resultsTable) {
		NSArray *values = [_result.rows objectAtIndex:(NSUInteger)row];
		NSUInteger index = (NSUInteger)[[column identifier] integerValue];
		return index < [values count] ? ORMCellText([values objectAtIndex:index]) : @"";
	}
	(void)column;
	ORMRole *role = [_available objectAtIndex:(NSUInteger)row];
	if (role.factType.kind == ORMFactTypeSubtype) {
		for (ORMRole *other in role.factType.roles) {
			if (other != role) {
				return [NSString stringWithFormat:@"is %@", other.player.name];
			}
		}
	}
	for (ORMReadingOrder *order in role.factType.readingOrders) {
		NSString *text = [[order.readings firstObject] text];
		if ([order.roles firstObject] == role && [text hasPrefix:@"{0}"]) {
			NSMutableString *reading = [[text substringFromIndex:3] mutableCopy];
			for (NSUInteger i = 1; i < [order.roles count]; i++) {
				[reading replaceOccurrencesOfString:[NSString stringWithFormat:@"{%lu}", (unsigned long)i]
				                         withString:[[order.roles objectAtIndex:i] player].name ?: @"?"
				                            options:0
				                              range:NSMakeRange(0, [reading length])];
			}
			return [reading stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		}
	}
	return [[role.factType primaryReading] expandedText] ?: role.factType.name;
}

@end
