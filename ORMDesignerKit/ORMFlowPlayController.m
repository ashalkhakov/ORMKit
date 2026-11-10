/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlowPlayController.h"
#import "ORMFlow.h"
#import "ORMFlowWalk.h"
#import "ORMForm.h"
#import "ORMFormSession.h"

@implementation ORMFlowPlayController {
	ORMFlow *_flow;
	ORMModel *_model;
	/* What it could not do, last, said in the log after the walk's. */
	NSString *_trouble;
}

- (instancetype)initWithFlow:(ORMFlow *)flow model:(ORMModel *)model
{
	if ((self = [super initWithWindowNibName:@"ORMFlowPlayWindow"])) {
		_flow = flow;
		_model = model;
	}
	return self;
}

- (NSString *)windowNibName
{
	return @"ORMFlowPlayWindow";
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self.ways setDoubleAction:@selector(takeWay:)];
	[self.ways setTarget:self];
	[self startOver:nil];
}

- (IBAction)startOver:(id)sender
{
	_walk = [[ORMFlowWalk alloc] initWithFlow:_flow model:_model mapping:nil];
	NSError *error = nil;
	_trouble = [_walk beginAt:nil error:&error] ? nil : error.localizedDescription ?: @"The flow cannot begin.";
	[self showAgain];
}

/* Everything shown as the walk is now. */
- (void)showAgain
{
	ORMFlowScreen *screen = _walk.screen;
	NSString *kind = _walk.session != nil ? @"form" : @"list";
	[self.screenTitle setStringValue:screen != nil ? [NSString stringWithFormat:@"%@ (%@)", screen.name ?: screen.identifier, kind]
	                                               : @"Out of the flow: Start Over to play it again."];
	[self.window setTitle:[NSString stringWithFormat:@"Play %@", _flow.name ?: @"Flow"]];
	[self.values reloadData];
	[self.ways reloadData];
	[self.log reloadData];
	if ([self.ways numberOfRows] > 0) {
		[self.ways selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
	if ([self.values numberOfRows] > 0 && _walk.session == nil) {
		[self.values selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
	if ([self.log numberOfRows] > 0) {
		[self.log scrollRowToVisible:[self.log numberOfRows] - 1];
	}
	[self.submitButton setEnabled:_walk.session != nil];
	[self.takeButton setEnabled:[[self waysOn] count] > 0];
}

/* The ways a user takes here: Submit takes the save's. */
- (NSArray<ORMFlowTransition *> *)waysOn
{
	NSMutableArray *ways = [NSMutableArray array];
	for (ORMFlowTransition *way in [_walk transitions]) {
		if (![way.on hasPrefix:@"Submit"]) {
			[ways addObject:way];
		}
	}
	return ways;
}

- (NSArray<NSString *> *)lines
{
	NSArray *lines = _walk.log ?: @[];
	return _trouble != nil ? [lines arrayByAddingObject:_trouble] : lines;
}

#pragma mark Acting

- (IBAction)takeWay:(id)sender
{
	NSArray *ways = [self waysOn];
	NSInteger chosen = [self.ways selectedRow];
	if (chosen < 0 || chosen >= (NSInteger)[ways count]) {
		NSBeep();
		return;
	}
	NSInteger row = [self.values selectedRow];
	NSError *error = nil;
	_trouble = [_walk take:[ways objectAtIndex:chosen] row:row < 0 ? 0 : row error:&error] ? nil : error.localizedDescription;
	[self showAgain];
}

- (IBAction)submit:(id)sender
{
	if (_walk.session == nil) {
		NSBeep();
		return;
	}
	[self.window makeFirstResponder:nil];
	NSError *error = nil;
	[_walk submit:&error];
	_trouble = error.localizedDescription;
	[self showAgain];
}

#pragma mark The tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == self.ways) {
		return (NSInteger)[[self waysOn] count];
	}
	if (tableView == self.log) {
		return (NSInteger)[[self lines] count];
	}
	return (NSInteger)(_walk.session != nil ? [_walk.session.form.elements count] : [_walk.rows count]);
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView == self.log) {
		return [[self lines] objectAtIndex:(NSUInteger)row];
	}
	if (tableView == self.ways) {
		ORMFlowTransition *way = [[self waysOn] objectAtIndex:(NSUInteger)row];
		ORMFlowScreen *to = way.toScreen != nil ? [_flow screenWithId:way.toScreen] : nil;
		NSString *on = way.control != nil ? [NSString stringWithFormat:@"%@ %@", way.on, way.control] : way.on;
		NSString *where = to != nil ? to.name ?: to.identifier : [way.kind lowercaseString];
		return [NSString stringWithFormat:@"%@ → %@%@", on, where, [way.kind isEqualToString:ORMFlowKindOverlay] ? @" (over it)" : @""];
	}
	if (_walk.session != nil) {
		ORMFormElement *element = [_walk.session.form.elements objectAtIndex:(NSUInteger)row];
		if ([[column identifier] isEqualToString:@"value"]) {
			return [_walk.session valueForElement:element.name] ?: @"";
		}
		/* What the last save refused of it, beside its name. */
		NSString *error = [_walk.session.errors objectForKey:element.name];
		NSString *name = [NSString stringWithFormat:@"%@ (%@)", element.label ?: element.name, element.role ?: @"?"];
		return error != nil ? [NSString stringWithFormat:@"⚠︎ %@: %@", name, error] : name;
	}
	NSDictionary *values = [_walk.rows objectAtIndex:(NSUInteger)row];
	if ([[column identifier] isEqualToString:@"value"]) {
		NSMutableArray *texts = [NSMutableArray array];
		for (NSString *title in [[values allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			[texts addObject:[NSString stringWithFormat:@"%@: %@", title, [values objectForKey:title]]];
		}
		return [texts componentsJoinedByString:@", "];
	}
	return [NSString stringWithFormat:@"Row %ld", (long)row + 1];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView != self.values || _walk.session == nil || ![[column identifier] isEqualToString:@"value"]) {
		return NO;
	}
	ORMFormElement *element = [_walk.session.form.elements objectAtIndex:(NSUInteger)row];
	return [element.role isEqualToString:@"entered"];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView != self.values || _walk.session == nil) {
		return;
	}
	ORMFormElement *element = [_walk.session.form.elements objectAtIndex:(NSUInteger)row];
	[_walk.session setValue:[value description] ?: @"" forElement:element.name];
}

@end
