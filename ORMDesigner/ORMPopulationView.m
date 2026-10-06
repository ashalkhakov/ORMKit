/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPopulationView.h"
#import "ORMPane.h"

@implementation ORMPopulationView
{
	/* The projection the rows were read from, held: its objects' links to
	 * one another are weak. */
	ORMModel *_model;
	ORMFactType *_fact;
	ORMObjectType *_type;
	/* An object type identified by several values: a column each. */
	NSArray<ORMRole *> *_parts;
	NSArray *_rows;
	/* A derived fact type's facts its rule derives and nothing stores
	 * (docs/DERIVATION.md), after the asserted ones, read only. */
	NSArray<ORMDerivedFact *> *_derived;
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
	return MAX(_fact != nil ? [[self roles] count] : [_parts count], (NSUInteger)1);
}

/* An instance as the table names it, as the population editor reads it. */
- (NSString *)nameOf:(ORMInstance *)instance
{
	return [self.editor.populationEditor nameOf:instance] ?: @"";
}

- (void)reload
{
	_model = self.editor.model;
	id element = _elementId != nil ? [_model elementWithId:_elementId] : nil;
	if ([element isKindOfClass:[ORMRole class]]) {
		/* A role selected: its fact type's population. */
		element = [(ORMRole *)element factType];
	}
	_fact = [element isKindOfClass:[ORMFactType class]] && [(ORMFactType *)element kind] == ORMFactTypeOrdinary ? element : nil;
	_type = [element isKindOfClass:[ORMObjectType class]] ? element : nil;
	_parts = _type != nil ? [self.editor.populationEditor compositeRolesOf:_type.identifier] : @[];
	_rows = _fact != nil ? [_fact instances] : (_type != nil ? [_type instances] : @[]);
	_derived = @[];
	ORMDerivationRule *rule = _fact.isDerived ? [_fact derivationRule] : nil;
	if (rule != nil && !rule.isStored) {
		NSMutableSet *asserted = [NSMutableSet set];
		for (ORMFactInstance *instance in _rows) {
			[asserted addObject:[self playersOf:instance.instancesByRole]];
		}
		NSMutableArray *derived = [NSMutableArray array];
		for (ORMDerivedFact *each in [[[[ORMDeriver alloc] initWithModel:_model] derivedFacts] objectForKey:_fact.identifier]) {
			if (![asserted containsObject:[self playersOf:each.players]]) {
				[derived addObject:each];
			}
		}
		_derived = derived;
	}
	if (_pending != nil && [_pending count] != [self columnCount]) {
		_pending = nil;
	}
	/* A column a role, or one for the instances. */
	NSMutableArray *titles = [NSMutableArray array];
	if (_fact != nil) {
		for (ORMRole *role in [self roles]) {
			[titles addObject:[role.name length] > 0 ? role.name : role.player.name ?: @"?"];
		}
	} else if ([_parts count] > 0) {
		for (ORMRole *role in _parts) {
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
		/* The cell too: a column whose cell is not editable never opens one. */
		[[column dataCell] setEditable:_fact != nil || _type != nil];
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
	/* The checker reads the whole population: not for a tab no one sees.
	 * Shown, the window reloads it. */
	NSArray *violations = [self isHiddenOrHasHiddenAncestor] || [self window] == nil
		? @[] : [[[ORMPopulationChecker alloc] initWithModel:self.editor.model] violations];
	for (ORMPopulationViolation *violation in violations) {
		if (violation.factType == _fact || [[violation.constraint factTypes] containsObject:_fact]) {
			[broken addObject:violation.text];
		}
	}
	NSString *counted = [NSString stringWithFormat:@"%lu %@", (unsigned long)[_rows count], [_rows count] == 1 ? @"fact" : @"facts"];
	if ([_derived count] > 0) {
		counted = [_rows count] == 0 ? [NSString stringWithFormat:@"%lu derived", (unsigned long)[_derived count]]
		                             : [NSString stringWithFormat:@"%@, %lu derived", counted, (unsigned long)[_derived count]];
	}
	[_status setStringValue:[broken count] == 0 ? counted
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

/* A fact by its players' ids (a value no instance has, by its text). */
- (NSDictionary *)playersOf:(NSDictionary *)players
{
	NSMutableDictionary *ids = [NSMutableDictionary dictionary];
	for (NSString *roleId in players) {
		id player = [players objectForKey:roleId];
		ORMRole *role = [_model elementWithId:roleId];
		if (role.player.isImplicitBooleanValue) {
			continue;
		}
		[ids setObject:[player isKindOfClass:[ORMInstance class]] ? [player identifier] : player forKey:roleId];
	}
	return ids;
}

/* Whether its facts all follow from its rule: none asserted by hand. */
- (BOOL)isFullyDerived
{
	return _fact.isDerived && ![_fact derivationRule].isPartial;
}

/* A derived row: after the asserted ones, before one being added. */
- (ORMDerivedFact *)derivedAtRow:(NSInteger)row
{
	NSInteger index = row - (NSInteger)[_rows count];
	return index >= 0 && (NSUInteger)index < [_derived count] ? [_derived objectAtIndex:(NSUInteger)index] : nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return (NSInteger)([_rows count] + [_derived count]) + (_pending != nil ? 1 : 0);
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	(void)tableView;
	(void)column;
	if ([cell respondsToSelector:@selector(setTextColor:)]) {
		/* Derived: shown, not edited. */
		[cell setTextColor:[self derivedAtRow:row] != nil ? [NSColor disabledControlTextColor] : [NSColor controlTextColor]];
	}
}

- (NSString *)textAtRow:(NSInteger)row column:(NSInteger)column
{
	if (row < 0 || column < 0) {
		return @"";
	}
	ORMDerivedFact *derived = [self derivedAtRow:row];
	if (derived != nil) {
		NSArray *roles = [self roles];
		ORMRole *role = (NSUInteger)column < [roles count] ? [roles objectAtIndex:(NSUInteger)column] : nil;
		id player = role != nil ? [derived.players objectForKey:role.identifier] : nil;
		return [player isKindOfClass:[ORMInstance class]] ? [self nameOf:player] : (player ?: @"");
	}
	if ((NSUInteger)row >= [_rows count]) {
		return (NSUInteger)column < [_pending count] ? [_pending objectAtIndex:(NSUInteger)column] : @"";
	}
	if (_fact != nil) {
		ORMFactInstance *fact = [_rows objectAtIndex:(NSUInteger)row];
		NSArray *roles = [self roles];
		ORMRole *role = (NSUInteger)column < [roles count] ? [roles objectAtIndex:(NSUInteger)column] : nil;
		return [self nameOf:role != nil ? [fact.instancesByRole objectForKey:role.identifier] : nil];
	}
	ORMInstance *instance = [_rows objectAtIndex:(NSUInteger)row];
	if ([_parts count] > 0) {
		/* A subtype's instance is identified as its supertype's is. */
		while ([instance supertypeInstance] != nil) {
			instance = [instance supertypeInstance];
		}
		ORMRole *role = (NSUInteger)column < [_parts count] ? [_parts objectAtIndex:(NSUInteger)column] : nil;
		return [self nameOf:role != nil ? [[instance identifyingInstancesByRole] objectForKey:role.identifier] : nil];
	}
	return [self nameOf:instance];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	return [self textAtRow:row column:[[tableView tableColumns] indexOfObject:column]];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	(void)tableView;
	(void)column;
	if ([self derivedAtRow:row] != nil || [self isFullyDerived]) {
		return NO;
	}
	return _fact != nil || _type != nil || (NSUInteger)row >= [_rows count];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	[self setText:[value description] atRow:row column:[[tableView tableColumns] indexOfObject:column]];
}

- (void)setText:(NSString *)text atRow:(NSInteger)row column:(NSInteger)column
{
	_refusal = nil;
	NSString *named = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
	if (row < 0 || column < 0 || [self derivedAtRow:row] != nil) {
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
		} else if ([_parts count] > 0) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			for (NSUInteger i = 0; i < [_parts count]; i++) {
				[byRole setObject:[pending objectAtIndex:i] forKey:[[_parts objectAtIndex:i] identifier]];
			}
			added = [self.editor.populationEditor addInstanceOf:_type.identifier namedByRole:byRole reason:&reason];
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
	if ([named isEqualToString:[self textAtRow:row column:column]]) {
		return;
	}
	if (_fact == nil) {
		/* An instance renamed: the value, or what identifies it. */
		ORMInstance *instance = [_rows objectAtIndex:(NSUInteger)row];
		NSString *reason = nil;
		BOOL renamed = [_parts count] > 0
		                   ? [self.editor.populationEditor renameInstance:instance.identifier
		                                                             role:[[_parts objectAtIndex:(NSUInteger)column] identifier]
		                                                               to:named
		                                                           reason:&reason]
		                   : [self.editor.populationEditor renameInstance:instance.identifier to:named reason:&reason];
		if (!renamed) {
			[self refuse:reason];
		}
		[self reload];
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
	if ([self isFullyDerived]) {
		[self refuse:[NSString stringWithFormat:@"\"%@\" is derived: its facts follow from its rule.",
		                                        [[_fact primaryReading] expandedText] ?: _fact.name]];
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
	if ([rows containsIndex:[_rows count] + [_derived count]]) {
		_pending = nil;
	}
	__block NSString *reason = nil;
	BOOL fact = _fact != nil;
	/* One change, undone as one; one refused, none removed. */
	BOOL removed = [chosen count] == 0 || [self.editor group:fact ? @"Remove Facts" : @"Remove Instances" trying:^BOOL {
		for (NSString *identifier in chosen) {
			NSString *why = nil;
			if (!(fact ? [self.editor.populationEditor removeFact:identifier reason:&why]
			           : [self.editor.populationEditor removeInstance:identifier reason:&why])) {
				reason = why;
				return NO;
			}
		}
		return YES;
	}];
	if (!removed) {
		[self refuse:reason];
	}
	[self reload];
}

@end
