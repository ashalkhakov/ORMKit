/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryController.h"

static NSArray<NSString *> *
ORMComparisonTitles(void)
{
	return @[ @"—", @"=", @"<>", @"<", @"<=", @">", @">=" ];
}

@implementation ORMQueryController
{
	NSPopUpButton *_queries;
	NSTextField *_name;
	NSPopUpButton *_startAt;
	NSOutlineView *_outline;
	NSTableView *_roles;
	NSButton *_list;
	NSPopUpButton *_comparison;
	NSTextField *_value;
	NSButton *_alternatives;
	NSPopUpButton *_operator;
	NSPopUpButton *_countComparison;
	NSTextField *_countValue;
	NSButton *_removeStep;
	NSTextView *_verbalization;
	NSTextView *_fetch;
	NSTextField *_status;
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
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(180, 120, 920, 660)
	                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
	                                                         | NSWindowStyleMaskResizable
	                                                 backing:NSBackingStoreBuffered
	                                                   defer:YES];
	[window setTitle:@"Conceptual Queries"];
	[window setReleasedWhenClosed:NO];
	[window setMinSize:NSMakeSize(720, 480)];
	if ((self = [super initWithWindow:window])) {
		_editor = editor;
		_items = [NSMutableDictionary dictionary];
		_children = [NSMutableDictionary dictionary];
		[self build];
		[self modelDidChange];
	}
	return self;
}

#pragma mark Building

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	[label setStringValue:text];
	[label setEditable:NO];
	[label setBordered:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
	NSButton *button = [[NSButton alloc] initWithFrame:frame];
	[button setTitle:title];
	[button setBezelStyle:NSBezelStyleRounded];
	[button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[button setTarget:self];
	[button setAction:action];
	return button;
}

- (NSButton *)check:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
	NSButton *check = [self button:title action:action frame:frame];
	[check setButtonType:NSButtonTypeSwitch];
	return check;
}

- (NSPopUpButton *)popUp:(NSArray *)titles action:(SEL)action frame:(NSRect)frame
{
	NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
	[popUp addItemsWithTitles:titles];
	[popUp setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[popUp setTarget:self];
	[popUp setAction:action];
	return popUp;
}

- (NSTextField *)field:(NSRect)frame action:(SEL)action
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
	[field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[[field cell] setSendsActionOnEndEditing:YES];
	[field setTarget:self];
	[field setAction:action];
	return field;
}

- (NSScrollView *)scroll:(NSView *)view frame:(NSRect)frame
{
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
	[scroll setHasVerticalScroller:YES];
	[scroll setBorderType:NSBezelBorder];
	[scroll setDocumentView:view];
	return scroll;
}

- (NSTextView *)textView:(NSRect)frame
{
	NSTextView *text = [[NSTextView alloc] initWithFrame:frame];
	[text setEditable:NO];
	[text setRichText:NO];
	[text setAutoresizingMask:NSViewWidthSizable];
	return text;
}

- (void)place:(NSView *)view mask:(NSUInteger)mask in:(NSView *)content
{
	[view setAutoresizingMask:mask];
	[content addSubview:view];
}

- (void)build
{
	NSView *content = [[self window] contentView];
	NSRect bounds = [content bounds];
	double top = NSHeight(bounds);
	double width = NSWidth(bounds);
	NSUInteger topLeft = NSViewMinYMargin;
	NSUInteger topRight = NSViewMinYMargin | NSViewMinXMargin;

	/* The query, its name, and new ones. */
	[self place:[self label:@"Query:" frame:NSMakeRect(12, top - 32, 50, 18)] mask:topLeft in:content];
	_queries = [self popUp:@[] action:@selector(chooseQuery:) frame:NSMakeRect(62, top - 36, 200, 24)];
	[self place:_queries mask:topLeft in:content];
	[self place:[self button:@"−" action:@selector(removeQuery:) frame:NSMakeRect(266, top - 36, 30, 24)] mask:topLeft
	         in:content];
	_name = [self field:NSMakeRect(304, top - 34, 200, 22) action:@selector(nameChanged:)];
	[[_name cell] setPlaceholderString:@"Name"];
	[self place:_name mask:topLeft in:content];
	[self place:[self label:@"New query from:" frame:NSMakeRect(width - 400, top - 32, 100, 18)] mask:topRight
	         in:content];
	_startAt = [self popUp:@[] action:NULL frame:NSMakeRect(width - 298, top - 36, 190, 24)];
	[self place:_startAt mask:topRight in:content];
	[self place:[self button:@"New" action:@selector(newQuery:) frame:NSMakeRect(width - 104, top - 36, 92, 24)]
	       mask:topRight
	         in:content];

	double bottomPane = 190;
	double controls = 66;
	double middleTop = top - 46;
	double middleBottom = bottomPane + 30 + controls;
	double rolesWidth = 300;

	/* The outline: object types and the steps between them. */
	_outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, width - rolesWidth - 28, 200)];
	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"outline"];
	[[column headerCell] setStringValue:@"Outline"];
	[column setWidth:width - rolesWidth - 50];
	[column setEditable:NO];
	[_outline addTableColumn:column];
	[_outline setOutlineTableColumn:column];
	[_outline setDataSource:(id)self];
	[_outline setDelegate:(id)self];
	NSScrollView *outlineScroll = [self scroll:_outline
	                                     frame:NSMakeRect(8, middleBottom, width - rolesWidth - 24, middleTop - middleBottom)];
	[self place:outlineScroll mask:NSViewWidthSizable | NSViewHeightSizable in:content];

	/* Where the selected object type can go on to. */
	[self place:[self label:@"Go on through:" frame:NSMakeRect(width - rolesWidth - 8, middleTop - 2, 200, 18)]
	       mask:topRight
	         in:content];
	_roles = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, rolesWidth - 20, 200)];
	NSTableColumn *roleColumn = [[NSTableColumn alloc] initWithIdentifier:@"role"];
	[[roleColumn headerCell] setStringValue:@"Fact type"];
	[roleColumn setWidth:rolesWidth - 24];
	[roleColumn setEditable:NO];
	[_roles addTableColumn:roleColumn];
	[_roles setDataSource:(id)self];
	[_roles setDelegate:(id)self];
	[_roles setTarget:self];
	[_roles setDoubleAction:@selector(addStep:)];
	NSScrollView *rolesScroll = [self scroll:_roles
	                                   frame:NSMakeRect(width - rolesWidth - 8, middleBottom + 30, rolesWidth,
	                                                    middleTop - middleBottom - 50)];
	[self place:rolesScroll mask:NSViewHeightSizable | NSViewMinXMargin in:content];
	[self place:[self button:@"Add Step" action:@selector(addStep:)
	                   frame:NSMakeRect(width - rolesWidth - 8, middleBottom, 110, 24)]
	       mask:NSViewMaxYMargin | NSViewMinXMargin
	         in:content];

	/* The selected node's and step's settings. */
	double row1 = middleBottom - 30;
	double row2 = middleBottom - 60;
	NSUInteger bottomLeft = NSViewMaxYMargin;
	_list = [self check:@"List" action:@selector(listChanged:) frame:NSMakeRect(12, row1, 60, 20)];
	[self place:_list mask:bottomLeft in:content];
	[self place:[self label:@"Condition:" frame:NSMakeRect(80, row1 + 2, 64, 18)] mask:bottomLeft in:content];
	_comparison = [self popUp:ORMComparisonTitles() action:@selector(conditionChanged:)
	                    frame:NSMakeRect(144, row1 - 2, 64, 24)];
	[self place:_comparison mask:bottomLeft in:content];
	_value = [self field:NSMakeRect(212, row1, 140, 22) action:@selector(conditionChanged:)];
	[[_value cell] setPlaceholderString:@"Value"];
	[self place:_value mask:bottomLeft in:content];
	_alternatives = [self check:@"Its steps are alternatives (or)" action:@selector(alternativesChanged:)
	                      frame:NSMakeRect(364, row1, 240, 20)];
	[self place:_alternatives mask:bottomLeft in:content];

	[self place:[self label:@"Step:" frame:NSMakeRect(12, row2 + 2, 40, 18)] mask:bottomLeft in:content];
	_operator = [self popUp:@[ @"and", @"not", @"maybe" ] action:@selector(operatorChanged:)
	                  frame:NSMakeRect(52, row2 - 2, 90, 24)];
	[self place:_operator mask:bottomLeft in:content];
	[self place:[self label:@"Count:" frame:NSMakeRect(150, row2 + 2, 44, 18)] mask:bottomLeft in:content];
	_countComparison = [self popUp:ORMComparisonTitles() action:@selector(countChanged:)
	                         frame:NSMakeRect(194, row2 - 2, 64, 24)];
	[self place:_countComparison mask:bottomLeft in:content];
	_countValue = [self field:NSMakeRect(262, row2, 60, 22) action:@selector(countChanged:)];
	[self place:_countValue mask:bottomLeft in:content];
	_removeStep = [self button:@"Remove Step" action:@selector(removeStep:) frame:NSMakeRect(334, row2 - 2, 110, 24)];
	[self place:_removeStep mask:bottomLeft in:content];

	/* What the query says, and what Core Data is asked. */
	NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(8, 30, width - 16, bottomPane)];
	NSRect inner = NSMakeRect(0, 0, width - 36, bottomPane - 40);
	_verbalization = [self textView:inner];
	_fetch = [self textView:inner];
	[_fetch setFont:[NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]]];
	NSArray *panes = @[ @[ @"forml", @"FORML", _verbalization ], @[ @"fetch", @"Core Data Fetch", _fetch ] ];
	for (NSArray *pane in panes) {
		NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:[pane objectAtIndex:0]];
		[item setLabel:[pane objectAtIndex:1]];
		NSScrollView *scroll = [self scroll:[pane objectAtIndex:2] frame:inner];
		[scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[item setView:scroll];
		[tabs addTabViewItem:item];
	}
	[self place:tabs mask:NSViewWidthSizable | NSViewMaxYMargin in:content];

	_status = [self label:@"" frame:NSMakeRect(12, 6, width - 24, 18)];
	[self place:_status mask:NSViewWidthSizable | NSViewMaxYMargin in:content];
}

#pragma mark Reading the model

- (NSString *)selectedId
{
	return _selectedId;
}

- (void)say:(NSString *)message
{
	[_status setStringValue:message ?: @""];
}

- (void)modelDidChange
{
	ORMModel *model = self.editor.model;
	NSArray *queries = [ORMQuery queriesInModel:model];
	if (self.queryId != nil && [ORMQuery queryWithId:self.queryId inModel:model] == nil) {
		self.queryId = nil;
	}
	if (self.queryId == nil) {
		self.queryId = [[queries firstObject] identifier];
	}
	[_queries removeAllItems];
	for (ORMQuery *query in queries) {
		[_queries addItemWithTitle:query.name];
		[[_queries lastItem] setRepresentedObject:query.identifier];
		if ([query.identifier isEqualToString:self.queryId]) {
			[_queries selectItem:[_queries lastItem]];
		}
	}
	NSString *started = [[_startAt selectedItem] representedObject];
	[_startAt removeAllItems];
	NSArray *types = [[model visibleObjectTypes] sortedArrayUsingComparator:^NSComparisonResult(ORMObjectType *a,
	                                                                                              ORMObjectType *b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	for (ORMObjectType *type in types) {
		[_startAt addItemWithTitle:type.name ?: @"?"];
		[[_startAt lastItem] setRepresentedObject:type.identifier];
		if ([type.identifier isEqualToString:started]) {
			[_startAt selectItem:[_startAt lastItem]];
		}
	}

	_query = self.queryId != nil ? [ORMQuery queryWithId:self.queryId inModel:model] : nil;
	[_name setStringValue:_query.name ?: @""];
	[_name setEnabled:_query != nil];
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
	[_outline expandItem:nil expandChildren:YES];
	NSInteger row = _selectedId != nil ? [_outline rowForItem:[self canonical:_selectedId]] : -1;
	if (row >= 0) {
		[_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	}
	[self selectionDidChange];
	[self showQuery];
}

- (void)showQuery
{
	[_verbalization setString:[self verbalizationText]];
	[_fetch setString:[self fetchText]];
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
	for (NSControl *control in @[ _list, _comparison, _value, _alternatives ]) {
		[control setEnabled:node != nil];
	}
	for (NSControl *control in @[ _operator, _countComparison, _countValue, _removeStep ]) {
		[control setEnabled:step != nil];
	}
	[_list setState:node.isProjected ? NSControlStateValueOn : NSControlStateValueOff];
	NSUInteger comparison = node.comparison != nil ? [ORMComparisonTitles() indexOfObject:node.comparison] : 0;
	[_comparison selectItemAtIndex:comparison != NSNotFound ? (NSInteger)comparison : 0];
	[_value setStringValue:node.value ?: @""];
	[_alternatives setState:node.combinesWithOr ? NSControlStateValueOn : NSControlStateValueOff];
	[_operator selectItemAtIndex:step != nil ? step.operatorKind : 0];
	NSUInteger count = step.countComparison != nil ? [ORMComparisonTitles() indexOfObject:step.countComparison] : 0;
	[_countComparison selectItemAtIndex:count != NSNotFound ? (NSInteger)count : 0];
	[_countValue setStringValue:step.countComparison != nil ? [NSString stringWithFormat:@"%lu",
	                                                                                    (unsigned long)step.countValue]
	                                                        : @""];
	_available = node != nil ? [ORMQuery rolesFrom:node.objectType] : @[];
	[_roles reloadData];
}

#pragma mark Actions

- (NSString *)addQueryFrom:(NSString *)objectTypeId
{
	NSString *reason = nil;
	NSString *query = [self.editor addQueryNamed:nil from:objectTypeId reason:&reason];
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
	NSString *type = [[_startAt selectedItem] representedObject];
	if (type != nil) {
		[self addQueryFrom:type];
	}
}

- (void)chooseQuery:(id)sender
{
	(void)sender;
	self.queryId = [[_queries selectedItem] representedObject];
	_selectedId = nil;
	[self modelDidChange];
}

- (void)removeQuery:(id)sender
{
	(void)sender;
	if (self.queryId != nil) {
		[self.editor removeQuery:self.queryId];
		self.queryId = nil;
		_selectedId = nil;
		[self modelDidChange];
	}
}

- (void)nameChanged:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	if (_query != nil && ![[_name stringValue] isEqualToString:_query.name]
	    && ![self.editor renameQuery:_query.identifier to:[_name stringValue] reason:&reason]) {
		NSBeep();
		[self say:reason];
		[_name setStringValue:_query.name];
	}
}

- (NSString *)addStepThrough:(ORMRole *)role
{
	ORMQueryNode *node = [self selectedNode];
	if (node == nil || role == nil) {
		return nil;
	}
	NSString *reason = nil;
	NSString *step = [self.editor addStepTo:node.identifier through:role.identifier reason:&reason];
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
		[self.editor removeStep:step.identifier];
		[self modelDidChange];
	}
}

- (void)listChanged:(id)sender
{
	(void)sender;
	ORMQueryNode *node = [self selectedNode];
	if (node != nil) {
		[self.editor setProjected:[_list state] == NSControlStateValueOn ofNode:node.identifier];
	}
}

- (void)conditionChanged:(id)sender
{
	(void)sender;
	ORMQueryNode *node = [self selectedNode];
	if (node == nil) {
		return;
	}
	NSInteger index = [_comparison indexOfSelectedItem];
	NSString *comparison = index > 0 ? [ORMComparisonTitles() objectAtIndex:(NSUInteger)index] : nil;
	NSString *value = [_value stringValue];
	if ([comparison isEqualToString:node.comparison ?: @""] && [value isEqualToString:node.value ?: @""]) {
		return;
	}
	if (comparison == nil && node.comparison == nil) {
		return;
	}
	NSString *reason = nil;
	if (![self.editor setCondition:comparison value:value ofNode:node.identifier reason:&reason]) {
		NSBeep();
		[self say:reason];
	}
}

- (void)alternativesChanged:(id)sender
{
	(void)sender;
	ORMQueryNode *node = [self selectedNode];
	if (node != nil) {
		[self.editor setCombinesWithOr:[_alternatives state] == NSControlStateValueOn ofNode:node.identifier];
	}
}

- (void)operatorChanged:(id)sender
{
	(void)sender;
	ORMQueryStep *step = [self selectedStep];
	if (step != nil) {
		[self.editor setOperator:(ORMQueryOperator)[_operator indexOfSelectedItem] ofStep:step.identifier];
	}
}

- (void)countChanged:(id)sender
{
	(void)sender;
	ORMQueryStep *step = [self selectedStep];
	if (step == nil) {
		return;
	}
	NSInteger index = [_countComparison indexOfSelectedItem];
	NSString *comparison = index > 0 ? [ORMComparisonTitles() objectAtIndex:(NSUInteger)index] : nil;
	NSUInteger value = (NSUInteger)MAX(0, [_countValue integerValue]);
	if ([comparison ?: @"" isEqualToString:step.countComparison ?: @""] && (comparison == nil || value == step.countValue)) {
		return;
	}
	NSString *reason = nil;
	if (![self.editor setCount:comparison value:value ofStep:step.identifier reason:&reason]) {
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
	                                                          node.objectType.name ?: @"?"];
	if (node.comparison != nil) {
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
