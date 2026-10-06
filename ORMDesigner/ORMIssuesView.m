/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMIssuesView.h"

@implementation ORMIssuesView
{
	BOOL _reloading;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		if (!ORMLoadPaneNib(self, @"ORMIssuesView")) {
			return nil;
		}
		ORMFillHost(self, _content);
		_issues = @[];
	}
	return self;
}

- (void)reload
{
	ORMCoreDataMapping *mapping = self.editor != nil
		? [[ORMCoreDataMapping mappingsOfDocument:self.editor.document] firstObject] : nil;
	_issues = self.editor != nil ? [[[ORMIssueFinder alloc] initWithModel:self.editor.model mapping:mapping] issues] : @[];
	_reloading = YES;
	[_table reloadData];
	_reloading = NO;
	NSUInteger errors = 0, warnings = 0;
	for (ORMIssue *issue in _issues) {
		errors += issue.severity == ORMIssueError;
		warnings += issue.severity == ORMIssueWarning;
	}
	[_summary setStringValue:[_issues count] == 0 ? @"No issues"
	                                               : [NSString stringWithFormat:@"%lu %@, %lu %@, %lu %@", (unsigned long)errors,
	                                                                            errors == 1 ? @"error" : @"errors",
	                                                                            (unsigned long)warnings,
	                                                                            warnings == 1 ? @"warning" : @"warnings",
	                                                                            (unsigned long)([_issues count] - errors - warnings),
	                                                                            [_issues count] - errors - warnings == 1 ? @"note"
	                                                                                                                     : @"notes"]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return (NSInteger)[_issues count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	(void)tableView;
	(void)column;
	return [[_issues objectAtIndex:(NSUInteger)row] text];
}

- (void)tableView:(NSTableView *)tableView
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row
{
	(void)tableView;
	(void)column;
	if (![cell respondsToSelector:@selector(setTextColor:)]) {
		return;
	}
	ORMIssueSeverity severity = [[_issues objectAtIndex:(NSUInteger)row] severity];
	[cell setTextColor:severity == ORMIssueError
	                       ? [NSColor redColor]
	                       : (severity == ORMIssueWarning ? [NSColor orangeColor] : [NSColor disabledControlTextColor])];
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
	ORMIssue *issue = [_issues objectAtIndex:(NSUInteger)row];
	return [NSString stringWithFormat:@"%@: %@", issue.area, issue.text];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	(void)notification;
	NSInteger row = [_table selectedRow];
	if (_reloading || row < 0) {
		return;
	}
	NSString *element = [[_issues objectAtIndex:(NSUInteger)row] elementId];
	if (element != nil) {
		[self.delegate navigatorDidChooseElement:element];
	}
}

@end
