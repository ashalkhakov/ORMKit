/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMInsertPalette.h"
#import "ORMPane.h"

NSString *const ORMInsertDragType = @"org.ormkit.designer.insert-tool";

@implementation ORMInsertPalette
{
	/* The canvas's tool being shown: its row selected, not chosen again. */
	BOOL _showing;
}

+ (NSArray<NSArray *> *)items
{
	return @[ @[ @"Select", @"Pick, move and resize what is on the diagram.", @(ORMToolPointer) ],
		      @[ @"Entity Type", @"Click or drop where it goes.", @(ORMToolEntityType) ],
		      @[ @"Value Type", @"Click or drop where it goes.", @(ORMToolValueType) ],
		      @[ @"Fact Type", @"Click its players in reading order, then where it goes.", @(ORMToolFactType) ],
		      @[ @"Subtype", @"Drag from the subtype to its supertype.", @(ORMToolSubtype) ],
		      @[ @"Role Player", @"Drag from a role box to the object type that plays it.", @(ORMToolConnectRole) ],
		      @[ @"Uniqueness", @"Click the roles, then Return.", @(ORMToolUniqueness) ],
		      @[ @"Inclusive Or", @"Click the roles, then Return.", @(ORMToolInclusiveOr) ],
		      @[ @"Exclusion", @"Click each sequence's roles, Option-Tab between them.", @(ORMToolExclusion) ],
		      @[ @"Exclusive Or", @"Click the roles, then Return.", @(ORMToolExclusiveOr) ],
		      @[ @"Subset", @"Click the subset's roles, Option-Tab, the superset's.", @(ORMToolSubset) ],
		      @[ @"Equality", @"Click each sequence's roles, Option-Tab between them.", @(ORMToolEquality) ],
		      @[ @"Frequency", @"Click the roles, then Return.", @(ORMToolFrequency) ],
		      @[ @"Ring", @"Click the two roles, then Return.", @(ORMToolRing) ],
		      @[ @"Value Comparison", @"Click the two roles, then Return.", @(ORMToolValueComparison) ],
		      @[ @"Note", @"Click or drop where it goes.", @(ORMToolNote) ] ];
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		if (!ORMLoadPaneNib(self, @"ORMInsertPalette")) {
			return nil;
		}
		ORMFillHost(self, _content);
		/* A drag from here is a copy, into this application: without
		 * saying so, a table's drags are for nothing. */
		[_table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
		[_table setDraggingSourceOperationMask:NSDragOperationNone forLocal:NO];
		[_table reloadData];
	}
	return self;
}

- (void)showTool:(ORMCanvasTool)tool
{
	NSUInteger row = NSNotFound;
	NSArray *items = [ORMInsertPalette items];
	for (NSUInteger i = 0; i < [items count] && row == NSNotFound; i++) {
		if ([[[items objectAtIndex:i] lastObject] integerValue] == tool) {
			row = i;
		}
	}
	_showing = YES;
	if (row != NSNotFound) {
		[_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	}
	_showing = NO;
}

#pragma mark The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return (NSInteger)[[ORMInsertPalette items] count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	(void)tableView;
	(void)column;
	return [[[ORMInsertPalette items] objectAtIndex:(NSUInteger)row] firstObject];
}

- (NSString *)tableView:(NSTableView *)tableView
         toolTipForCell:(NSCell *)cell
                   rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)column
                    row:(NSInteger)row
          mouseLocation:(NSPoint)location
{
	(void)tableView;
	(void)cell;
	(void)rect;
	(void)column;
	(void)location;
	return [[[ORMInsertPalette items] objectAtIndex:(NSUInteger)row] objectAtIndex:1];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	(void)notification;
	NSInteger row = [_table selectedRow];
	if (_showing || row < 0) {
		return;
	}
	ORMCanvasTool tool = (ORMCanvasTool)[[[[ORMInsertPalette items] objectAtIndex:(NSUInteger)row] lastObject] integerValue];
	[self.delegate insertPalette:self didChooseTool:tool];
}

/* An object type or a note, dragged: placed where it is dropped. */
- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pasteboard
{
	(void)tableView;
	NSNumber *tool = [[[ORMInsertPalette items] objectAtIndex:[rows firstIndex]] lastObject];
	if (![@[ @(ORMToolEntityType), @(ORMToolValueType), @(ORMToolNote) ] containsObject:tool]) {
		return NO;
	}
	[pasteboard declareTypes:@[ ORMInsertDragType ] owner:nil];
	return [pasteboard setString:[tool stringValue] forType:ORMInsertDragType];
}

@end
