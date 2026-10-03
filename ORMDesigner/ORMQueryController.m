/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryController.h"

static NSArray<NSString *> *
ORMComparisonTitles(void)
{
	return @[ @"—", @"=", @"<>", @"<", @"<=", @">", @">=" ];
}

@interface ORMQueryController ()
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
@property (nonatomic, strong) IBOutlet NSButton *removeStepButton;
@property (nonatomic, strong) IBOutlet NSTextView *verbalizationView;
@property (nonatomic, strong) IBOutlet NSTextView *fetchView;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@end

@implementation ORMQueryController
{
	/* The projection the query and its nodes were read from: theirs and the
	 * roles' links to one another are weak, so it is held until the next is
	 * read. */
	ORMModel *_model;
	ORMQuery *_query;
	/* Node and step ids -> what they are in the query as now read. */
	NSMutableDictionary<NSString *, id> *_items;
	/* Each item's children, as read; the outline's items are these very
	 * strings, the same each time it asks. */
	NSMutableDictionary<NSString *, NSArray<NSString *> *> *_children;
	NSArray<NSString *> *_roots;
	NSArray<ORMRole *> *_available;
	NSString *_selectedId;
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

- (void)modelDidChange
{
	ORMModel *model = self.editor.model;
	_model = model;
	NSArray *queries = [ORMQuery queriesInModel:model];
	if (self.queryId != nil && [ORMQuery queryWithId:self.queryId inModel:model] == nil) {
		self.queryId = nil;
	}
	if (self.queryId == nil) {
		self.queryId = [[queries firstObject] identifier];
	}
	[_queryPopUp removeAllItems];
	for (ORMQuery *query in queries) {
		[_queryPopUp addItemWithTitle:query.name];
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
	[_outline reloadData];
	/* Each root, not nil: GNUstep expands nothing for a nil item. */
	for (NSString *root in _roots) {
		[_outline expandItem:root expandChildren:YES];
	}
	NSInteger row = _selectedId != nil ? [_outline rowForItem:[self canonical:_selectedId]] : -1;
	if (row >= 0) {
		[_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	}
	[self selectionDidChange];
	[self showQuery];
}

- (void)showQuery
{
	[_verbalizationView setString:[self verbalizationText]];
	[_fetchView setString:[self fetchText]];
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

- (NSString *)fetchText
{
	if (_query == nil) {
		return @"";
	}
	ORMCoreDataMapping *mapping = [[ORMCoreDataMapping mappingsOfDocument:self.editor.document] firstObject];
	ORMQueryFetch *fetch = [[ORMQueryFetch alloc] initWithQuery:_query model:self.editor.model mapping:mapping];
	NSMutableString *text = [NSMutableString stringWithString:[fetch objectiveCSource]];
	for (NSString *note in fetch.notes) {
		[text appendFormat:@"\nNote: %@", note];
	}
	return text;
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
	for (NSControl *control in @[ _listCheck, _comparisonPopUp, _valueField, _alternativesCheck, _labelField ]) {
		[control setEnabled:node != nil];
	}
	for (NSControl *control in @[ _operatorPopUp, _countComparisonPopUp, _countField, _removeStepButton ]) {
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
	[_countField setStringValue:step.countComparison != nil ? [NSString stringWithFormat:@"%lu",
	                                                                                    (unsigned long)step.countValue]
	                                                        : @""];
	_available = node != nil ? [ORMQuery rolesFrom:node.objectType] : @[];
	[_roles reloadData];
}

#pragma mark Actions

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
	NSUInteger value = (NSUInteger)MAX(0, [_countField integerValue]);
	if ([comparison ?: @"" isEqualToString:step.countComparison ?: @""] && (comparison == nil || value == step.countValue)) {
		return;
	}
	NSString *reason = nil;
	if (![[self queries] setCount:comparison value:value ofStep:step.identifier reason:&reason]) {
		NSBeep();
		[self say:reason];
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
	NSString *count = step.countComparison != nil
		? [NSString stringWithFormat:@"   count %@ %lu", step.countComparison, (unsigned long)step.countValue]
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
	NSInteger row = [_outline selectedRow];
	_selectedId = row >= 0 ? [_outline itemAtRow:row] : nil;
	[self selectionDidChange];
}

#pragma mark The roles table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return (NSInteger)[_available count];
}

/* "lives in City", as the step would read. */
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	(void)tableView;
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
