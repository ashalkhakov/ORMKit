/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPopulationView.h"
#import "ORMPane.h"

/* An instance as the table names it: a value as it is, an entity by its
 * reference mode's value (its supertype's, for a subtype's), else as the
 * model shows it. */
static NSString *
ORMNameOf(ORMInstance *instance)
{
	if (instance == nil) {
		return @"";
	}
	if (instance.value != nil) {
		return instance.value;
	}
	NSDictionary *identifying = [instance identifyingInstancesByRole];
	if ([identifying count] == 1) {
		return ORMNameOf([[identifying allValues] firstObject]);
	}
	if ([instance supertypeInstance] != nil) {
		return ORMNameOf([instance supertypeInstance]);
	}
	return [instance displayText] ?: @"";
}

@implementation ORMPopulationView
{
	/* The projection the rows were read from, held: its objects' links to
	 * one another are weak. */
	ORMModel *_model;
	ORMFactType *_fact;
	ORMObjectType *_type;
	NSArray *_rows;
	/* The row being added: a text for each column, until each is named. */
	NSMutableArray<NSString *> *_pending;
	NSString *_refusal;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		if (!ORMLoadPaneNib(self, @"ORMPopulationView")) {
			return nil;
		}
		ORMFillHost(self, _content);
		_rows = @[];
	}
	return self;
}

- (void)setElementId:(NSString *)elementId
{
	if (![_elementId isEqualToString:elementId ?: @""] || elementId == nil) {
		_pending = nil;
		_refusal = nil;
	}
	_elementId = [elementId copy];
	[self reload];
}

/* The roles a fact's columns are: those the reading shows. */
- (NSArray<ORMRole *> *)roles
{
	return _fact != nil ? [_fact visibleRoles] : @[];
}

- (NSUInteger)columnCount
{
	return _fact != nil ? MAX([[self roles] count], (NSUInteger)1) : 1;
}

- (void)reload
{
	_model = self.editor.model;
	id element = _elementId != nil ? [_model elementWithId:_elementId] : nil;
	_fact = [element isKindOfClass:[ORMFactType class]] && [(ORMFactType *)element kind] == ORMFactTypeOrdinary ? element : nil;
	_type = [element isKindOfClass:[ORMObjectType class]] ? element : nil;
	_rows = _fact != nil ? [_fact instances] : (_type != nil ? [_type instances] : @[]);
	if (_pending != nil && [_pending count] != [self columnCount]) {
		_pending = nil;
	}
	/* A column a role, or one for the instances. */
	NSMutableArray *titles = [NSMutableArray array];
	if (_fact != nil) {
		for (ORMRole *role in [self roles]) {
			[titles addObject:[role.name length] > 0 ? role.name : role.player.name ?: @"?"];
		}
	} else {
		[titles addObject:_type.name ?: @""];
	}
	while ([[_table tableColumns] count] > [titles count]) {
		[_table removeTableColumn:[[_table tableColumns] lastObject]];
	}
	while ([[_table tableColumns] count] < [titles count]) {
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@""];
		[column setWidth:160];
		[[column dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[_table addTableColumn:column];
	}
	for (NSUInteger i = 0; i < [titles count]; i++) {
		NSTableColumn *column = [[_table tableColumns] objectAtIndex:i];
		[column setIdentifier:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
		[[column headerCell] setStringValue:[titles objectAtIndex:i]];
		[column setEditable:_fact != nil || _type != nil];
	}
	[_table reloadData];
	[_title setStringValue:_fact != nil ? [NSString stringWithFormat:@"Population of %@",
	                                                                  [[_fact primaryReading] expandedText] ?: _fact.name]
	                                    : (_type != nil ? [NSString stringWithFormat:@"Instances of %@", _type.name]
	                                                    : @"Select a fact type or an object type.")];
	[self showStatus];
}

/* What was refused; else what the population breaks of the fact type. */
- (void)showStatus
{
	if (_refusal != nil) {
		[_status setStringValue:_refusal];
		return;
	}
	if (_fact == nil) {
		[_status setStringValue:_type != nil ? [NSString stringWithFormat:@"%lu %@", (unsigned long)[_rows count],
		                                                                 [_rows count] == 1 ? @"instance" : @"instances"]
		                                      : @""];
		return;
	}
	NSMutableArray *broken = [NSMutableArray array];
	for (ORMPopulationViolation *violation in [[[ORMPopulationChecker alloc] initWithModel:self.editor.model] violations]) {
		if (violation.factType == _fact || [[violation.constraint factTypes] containsObject:_fact]) {
			[broken addObject:violation.text];
		}
	}
	[_status setStringValue:[broken count] == 0 ? [NSString stringWithFormat:@"%lu %@", (unsigned long)[_rows count],
	                                                                         [_rows count] == 1 ? @"fact" : @"facts"]
	                                            : [NSString stringWithFormat:@"%@%@", [broken firstObject],
	                                                                         [broken count] > 1
	                                                                             ? [NSString stringWithFormat:@" (and %lu more)",
	                                                                                                          (unsigned long)[broken count] - 1]
	                                                                             : @""]];
}

- (void)refuse:(NSString *)why
{
	_refusal = [why copy];
	NSBeep();
	[self showStatus];
}

#pragma mark The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return (NSInteger)[_rows count] + (_pending != nil ? 1 : 0);
}

- (NSString *)textAtRow:(NSInteger)row column:(NSInteger)column
{
	if (row < 0 || column < 0) {
		return @"";
	}
	if ((NSUInteger)row >= [_rows count]) {
		return (NSUInteger)column < [_pending count] ? [_pending objectAtIndex:(NSUInteger)column] : @"";
	}
	if (_fact != nil) {
		ORMFactInstance *fact = [_rows objectAtIndex:(NSUInteger)row];
		NSArray *roles = [self roles];
		ORMRole *role = (NSUInteger)column < [roles count] ? [roles objectAtIndex:(NSUInteger)column] : nil;
		return ORMNameOf(role != nil ? [fact.instancesByRole objectForKey:role.identifier] : nil);
	}
	return ORMNameOf([_rows objectAtIndex:(NSUInteger)row]);
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	return [self textAtRow:row column:[[tableView tableColumns] indexOfObject:column]];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	(void)tableView;
	(void)column;
	/* An instance is renamed by its facts, not here: only a new one is. */
	return _fact != nil || (NSUInteger)row >= [_rows count];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	[self setText:[value description] atRow:row column:[[tableView tableColumns] indexOfObject:column]];
}

- (void)setText:(NSString *)text atRow:(NSInteger)row column:(NSInteger)column
{
	_refusal = nil;
	NSString *named = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
	if (row < 0 || column < 0) {
		return;
	}
	if ((NSUInteger)row >= [_rows count]) {
		/* The row being added: a fact, or an instance, once named. */
		if (_pending == nil || (NSUInteger)column >= [_pending count]) {
			return;
		}
		[_pending replaceObjectAtIndex:(NSUInteger)column withObject:named];
		for (NSString *each in _pending) {
			if ([each length] == 0) {
				[_table reloadData];
				return;
			}
		}
		NSString *reason = nil;
		NSString *added = nil;
		NSArray *pending = [_pending copy];
		_pending = nil;
		if (_fact != nil) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			NSArray *roles = [self roles];
			for (NSUInteger i = 0; i < [roles count]; i++) {
				[byRole setObject:[pending objectAtIndex:i] forKey:[[roles objectAtIndex:i] identifier]];
			}
			added = [self.editor.populationEditor addFactOf:_fact.identifier named:byRole reason:&reason];
		} else {
			added = [self.editor.populationEditor addInstanceOf:_type.identifier named:[pending firstObject] reason:&reason];
		}
		if (added == nil) {
			_pending = [pending mutableCopy];
			[self refuse:reason];
		}
		[self reload];
		return;
	}
	if (_fact == nil || [named isEqualToString:[self textAtRow:row column:column]]) {
		return;
	}
	ORMFactInstance *fact = [_rows objectAtIndex:(NSUInteger)row];
	NSArray *roles = [self roles];
	if ((NSUInteger)column >= [roles count]) {
		return;
	}
	NSString *reason = nil;
	if ([self.editor.populationEditor setPlayer:named ofRole:[[roles objectAtIndex:(NSUInteger)column] identifier]
	                                     inFact:fact.identifier reason:&reason] == nil) {
		[self refuse:reason];
	}
	[self reload];
}

- (IBAction)addRow:(id)sender
{
	(void)sender;
	if (_fact == nil && _type == nil) {
		return;
	}
	_refusal = nil;
	_pending = [NSMutableArray array];
	for (NSUInteger i = 0; i < [self columnCount]; i++) {
		[_pending addObject:@""];
	}
	[_table reloadData];
	NSInteger row = [_table numberOfRows] - 1;
	[_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	[_table editColumn:0 row:row withEvent:nil select:YES];
	[self showStatus];
}

- (IBAction)removeRows:(id)sender
{
	(void)sender;
	_refusal = nil;
	NSIndexSet *rows = [_table selectedRowIndexes];
	NSMutableArray *chosen = [NSMutableArray array];
	[rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
		(void)stop;
		if (row < [self->_rows count]) {
			[chosen addObject:[[self->_rows objectAtIndex:row] identifier]];
		}
	}];
	if ([rows containsIndex:[_rows count]]) {
		_pending = nil;
	}
	NSString *reason = nil;
	for (NSString *identifier in chosen) {
		BOOL removed = _fact != nil ? [self.editor.populationEditor removeFact:identifier reason:&reason]
		                            : [self.editor.populationEditor removeInstance:identifier reason:&reason];
		if (!removed) {
			[self refuse:reason];
			break;
		}
	}
	[self reload];
}

@end
