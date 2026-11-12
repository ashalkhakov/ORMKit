/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlowPlayController.h"
#import "ORMFlow.h"
#import "ORMFlowWalk.h"
#import "ORMForm.h"
#import "ORMFormSession.h"

/* A line of a form's values: an element of the form's; a repeat's heading
 * (no element, no row); one of its rows (no element); an element of a row. */
@interface ORMFlowPlayEntry : NSObject
@property (nonatomic, strong) ORMFormElement *element;
@property (nonatomic, copy) NSString *repeat;
@property (nonatomic) NSUInteger row;
@end

@implementation ORMFlowPlayEntry
@end

static ORMFlowPlayEntry *
ORMFlowPlayEntryOf(ORMFormElement *element, NSString *repeat, NSUInteger row)
{
	ORMFlowPlayEntry *entry = [[ORMFlowPlayEntry alloc] init];
	entry.element = element;
	entry.repeat = repeat;
	entry.row = row;
	return entry;
}

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
	return (NSInteger)(_walk.session != nil ? [[self entriesShown] count] : [_walk.rows count]);
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
		if ([[column identifier] isEqualToString:@"value"]) {
			return [self shownValueOfRow:row];
		}
		/* What the last save refused of it, beside its name. */
		ORMFlowPlayEntry *entry = [self entryOfRow:row];
		NSString *error = [_walk.session.errors objectForKey:[self errorKeyOf:entry] ?: @""];
		/* Its role is its control's to show (a field to enter, a given
		 * value's text), and its tooltip's to say. */
		NSString *name = [self nameOf:entry];
		return error != nil ? [NSString stringWithFormat:@"⚠︎ %@: %@", name, error] : name;
	}
	if ([[column identifier] isEqualToString:@"value"]) {
		return [self shownValueOfRow:row];
	}
	return [NSString stringWithFormat:@"Row %ld", (long)row + 1];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView != self.values) {
		NSTableCellView *line = [tableView makeViewWithIdentifier:@"line" owner:self];
		[line.textField setStringValue:[self tableView:tableView objectValueForTableColumn:column row:row] ?: @""];
		return line;
	}
	BOOL isValue = [[column identifier] isEqualToString:@"value"];
	NSString *editor = isValue ? [self editorOfRow:row] : @"name";
	NSTableCellView *view = [tableView makeViewWithIdentifier:editor owner:self];
	NSString *shown = [self tableView:tableView objectValueForTableColumn:column row:row];
	if (!isValue) {
		NSString *refused = _walk.session != nil ? [_walk.session.errors objectForKey:[self errorKeyOf:[self entryOfRow:row]] ?: @""] : nil;
		[view.textField setStringValue:shown];
		[view.textField setTextColor:refused != nil ? [NSColor systemRedColor] : [NSColor controlTextColor]];
		NSString *role = _walk.session != nil ? [self elementOfRow:row].role : nil;
		[view setToolTip:refused != nil ? shown : role != nil ? [NSString stringWithFormat:@"%@ (%@)", shown, role] : nil];
		return view;
	}
	ORMFlowPlayEntry *entry = [self entryOfRow:row];
	ORMFormElement *element = entry.element;
	NSString *value = [self valueOf:entry];
	if ([editor isEqualToString:@"number"]) {
		NSNumberFormatter *formatter = [view.textField formatter];
		BOOL whole = [element.schemaType hasSuffix:@"integer"] || [element.schemaType hasSuffix:@"int"] ||
		             [element.schemaType hasSuffix:@"long"] || [element.schemaType hasSuffix:@"short"];
		[formatter setAllowsFloats:!whole];
		[formatter setMaximumFractionDigits:whole ? 0 : 6];
		[view.textField setObjectValue:[value length] > 0 ? [NSDecimalNumber decimalNumberWithString:value
		                                                                                      locale:@{ NSLocaleDecimalSeparator : @"." }]
		                                                  : nil];
	} else if ([editor isEqualToString:@"text"] || [editor isEqualToString:@"shown"] || [editor isEqualToString:@"rows"]) {
		[view.textField setStringValue:[editor isEqualToString:@"text"] ? value : shown];
	} else if ([editor isEqualToString:@"date"] || [editor isEqualToString:@"dateTime"]) {
		NSDatePicker *picker = nil;
		for (NSView *each in [view subviews]) {
			if ([each isKindOfClass:[NSDatePicker class]]) {
				picker = (NSDatePicker *)each;
			}
		}
		/* A day is the same day everywhere; a moment is shown where the user is. */
		[picker setTimeZone:[editor isEqualToString:@"date"] ? [NSTimeZone timeZoneForSecondsFromGMT:0] : [NSTimeZone localTimeZone]];
		NSDate *date = [self dateOf:value];
		[picker setDateValue:date ?: [NSDate date]];
		/* Empty: Set alone, where the picker goes; a picker shown always
		 * holds the value, Clear beside it. */
		for (NSView *each in [view subviews]) {
			BOOL set = [each isKindOfClass:[NSButton class]] && [(NSButton *)each action] == @selector(setDate:);
			[each setHidden:set == (date != nil)];
		}
	} else if ([editor isEqualToString:@"flag"]) {
		NSButton *box = [[view subviews] firstObject];
		[box setState:[value isEqualToString:@"true"] ? NSControlStateValueOn : NSControlStateValueOff];
	} else if ([editor isEqualToString:@"choice"]) {
		NSPopUpButton *popUp = [[view subviews] firstObject];
		[popUp removeAllItems];
		[popUp addItemWithTitle:@"(none)"];
		NSArray *keys = (entry.repeat != nil ? [_walk.session choicesNamed:element.name inRepeat:entry.repeat row:entry.row error:NULL]
		                                     : [_walk.session choicesNamed:element.name error:NULL]) ?: @[];
		if ([value length] > 0 && ![keys containsObject:value]) {
			keys = [keys arrayByAddingObject:value];
		}
		for (NSString *key in keys) {
			NSString *label = [self labelOfKey:key entry:entry];
			/* Two of the same label kept apart. */
			NSString *title = [popUp itemWithTitle:label] != nil ? [NSString stringWithFormat:@"%@ (%@)", label, key] : label;
			[popUp addItemWithTitle:title];
			[[popUp lastItem] setRepresentedObject:key];
		}
		NSInteger chosen = [popUp indexOfItemWithRepresentedObject:value];
		[popUp selectItemAtIndex:chosen >= 0 ? chosen : 0];
	}
	return view;
}

#pragma mark Values

/* The form's elements, then each repeat's rows (a service's lines): its
 * heading, each row and the row's elements; a subtype's only where the
 * object is of it (a fill-up's litres, a service's lines, once it is one). */
- (NSArray<ORMFlowPlayEntry *> *)entriesShown
{
	ORMForm *form = _walk.session.form;
	NSString *kind = nil;
	for (ORMFormElement *element in form.elements) {
		if ([element.kind isEqualToString:@"subtype"]) {
			kind = [_walk.session valueForElement:element.name] ?: @"";
		}
	}
	NSMutableArray *shown = [NSMutableArray array];
	for (ORMFormElement *element in form.elements) {
		if (element.subtype == nil || [element.subtype isEqualToString:kind]) {
			[shown addObject:ORMFlowPlayEntryOf(element, nil, NSNotFound)];
		}
	}
	for (NSString *name in [form repeatNames]) {
		ORMForm *repeat = [form repeatNamed:name];
		if (repeat.subtype != nil && ![repeat.subtype isEqualToString:kind]) {
			continue;
		}
		[shown addObject:ORMFlowPlayEntryOf(nil, name, NSNotFound)];
		NSUInteger rows = [[_walk.session rowsOfRepeat:name] count];
		for (NSUInteger row = 0; row < rows; row++) {
			[shown addObject:ORMFlowPlayEntryOf(nil, name, row)];
			/* Its own elements: not its key (the row says it) nor its link. */
			for (ORMFormElement *element in repeat.elements) {
				if (![element.role isEqualToString:@"key"] && ![element.name isEqualToString:repeat.linkElement ?: @""]) {
					[shown addObject:ORMFlowPlayEntryOf(element, name, row)];
				}
			}
		}
	}
	return shown;
}

- (ORMFlowPlayEntry *)entryOfRow:(NSInteger)row
{
	NSArray *entries = [self entriesShown];
	return row >= 0 && row < (NSInteger)[entries count] ? [entries objectAtIndex:(NSUInteger)row] : nil;
}

- (ORMFormElement *)elementOfRow:(NSInteger)row
{
	return [self entryOfRow:row].element;
}

/* As a line names it: the element's label, a repeat's what its rows are
 * of, a row numbered. */
- (NSString *)nameOf:(ORMFlowPlayEntry *)entry
{
	if (entry.element != nil) {
		return entry.element.label ?: entry.element.name;
	}
	NSString *of = [_walk.session.form repeatNamed:entry.repeat].entityName ?: entry.repeat;
	return entry.row == NSNotFound ? of : [NSString stringWithFormat:@"%@ %lu", of, (unsigned long)entry.row + 1];
}

/* What a save's refusal is said under: the element's name, a row's
 * "serviceLines[0].part". */
- (NSString *)errorKeyOf:(ORMFlowPlayEntry *)entry
{
	if (entry.element == nil) {
		return entry.row == NSNotFound ? entry.repeat : nil;
	}
	return entry.repeat != nil ? [NSString stringWithFormat:@"%@[%lu].%@", entry.repeat, (unsigned long)entry.row, entry.element.name]
	                           : entry.element.name;
}

- (NSString *)valueOf:(ORMFlowPlayEntry *)entry
{
	if (entry.element == nil) {
		return @"";
	}
	if (entry.repeat != nil) {
		NSArray *rows = [_walk.session rowsOfRepeat:entry.repeat];
		return entry.row < [rows count] ? [[rows objectAtIndex:entry.row] objectForKey:entry.element.name] ?: @"" : @"";
	}
	return [_walk.session valueForElement:entry.element.name] ?: @"";
}

- (NSString *)labelOfKey:(NSString *)key entry:(ORMFlowPlayEntry *)entry
{
	return entry.repeat != nil ? [_walk labelOfKey:key element:entry.element.name inRepeat:entry.repeat]
	                           : [_walk labelOfKey:key element:entry.element.name];
}

- (NSString *)editorOfRow:(NSInteger)row
{
	ORMFlowPlayEntry *entry = [self entryOfRow:row];
	if (entry != nil && entry.element == nil) {
		/* A repeat's heading adds a row, a row is taken away; a list's
		 * rows are only read. */
		if ([_walk.session.form repeatNamed:entry.repeat].isList) {
			return @"shown";
		}
		return entry.row == NSNotFound ? @"rows" : @"row";
	}
	ORMFormElement *element = entry.element;
	if (element == nil || ![element.role isEqualToString:@"entered"]) {
		return @"shown";
	}
	NSString *type = element.schemaType ?: @"";
	if ([element.kind isEqualToString:@"reference"] || element.items != nil) {
		return @"choice";
	}
	if ([type hasSuffix:@":boolean"]) {
		return @"flag";
	}
	if ([type hasSuffix:@":date"]) {
		return @"date";
	}
	if ([type hasSuffix:@":dateTime"]) {
		return @"dateTime";
	}
	for (NSString *number in @[ @":decimal", @":double", @":float", @":integer", @":int", @":long", @":short" ]) {
		if ([type hasSuffix:number]) {
			return @"number";
		}
	}
	return @"text";
}

/* xsd's lexical forms of a date, in UTC, as the form's table has them. */
static NSDateFormatter *
ORMFlowPlayFormatter(NSString *format)
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
	[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	[formatter setDateFormat:format];
	return formatter;
}

- (NSDate *)dateOf:(NSString *)value
{
	for (NSString *format in @[ @"yyyy-MM-dd'T'HH:mm:ssXXXXX", @"yyyy-MM-dd'T'HH:mm:ss", @"yyyy-MM-dd'T'HH:mm", @"yyyy-MM-dd" ]) {
		NSDate *date = [ORMFlowPlayFormatter(format) dateFromString:value ?: @""];
		if (date != nil) {
			return date;
		}
	}
	return nil;
}

- (NSString *)shownValueOfRow:(NSInteger)row
{
	ORMFormElement *element = [self elementOfRow:row];
	if (_walk.session == nil) {
		if (row < 0 || row >= (NSInteger)[_walk.rows count]) {
			return @"";
		}
		NSDictionary *values = [_walk.rows objectAtIndex:(NSUInteger)row];
		NSMutableArray *texts = [NSMutableArray array];
		for (NSString *title in [[values allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			[texts addObject:[NSString stringWithFormat:@"%@: %@", title, [values objectForKey:title]]];
		}
		return [texts componentsJoinedByString:@", "];
	}
	ORMFlowPlayEntry *entry = [self entryOfRow:row];
	if (entry != nil && element == nil) {
		/* A heading: how many rows. */
		NSUInteger rows = [[_walk.session rowsOfRepeat:entry.repeat] count];
		return entry.row == NSNotFound ? [NSString stringWithFormat:@"%lu %@", (unsigned long)rows, rows == 1 ? @"row" : @"rows"] : @"";
	}
	NSString *value = [self valueOf:entry];
	if ([value length] == 0) {
		return [element.role isEqualToString:@"key"] ? @"(new)" : @"";
	}
	if ([element.kind isEqualToString:@"reference"]) {
		return [self labelOfKey:value entry:entry];
	}
	if ([element.schemaType hasSuffix:@":boolean"]) {
		return [value isEqualToString:@"true"] ? @"Yes" : @"No";
	}
	NSDate *date = [element.schemaType hasSuffix:@":date"] || [element.schemaType hasSuffix:@":dateTime"] ? [self dateOf:value] : nil;
	if (date != nil) {
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		[formatter setDateStyle:NSDateFormatterMediumStyle];
		BOOL day = [element.schemaType hasSuffix:@":date"];
		[formatter setTimeStyle:day ? NSDateFormatterNoStyle : NSDateFormatterShortStyle];
		[formatter setTimeZone:day ? [NSTimeZone timeZoneForSecondsFromGMT:0] : [NSTimeZone localTimeZone]];
		return [formatter stringFromDate:date];
	}
	return value;
}

- (void)setValue:(NSString *)value ofRow:(NSInteger)row
{
	ORMFlowPlayEntry *entry = [self entryOfRow:row];
	ORMFormElement *element = entry.element;
	if (element == nil) {
		return;
	}
	if (entry.repeat != nil) {
		NSMutableArray *rows = [[_walk.session rowsOfRepeat:entry.repeat] mutableCopy];
		if (entry.row >= [rows count]) {
			return;
		}
		NSMutableDictionary *changed = [[rows objectAtIndex:entry.row] mutableCopy];
		[changed setObject:value ?: @"" forKey:element.name];
		[rows replaceObjectAtIndex:entry.row withObject:changed];
		[_walk.session setRows:rows forRepeat:entry.repeat];
	} else {
		[_walk.session setValue:value ?: @"" forElement:element.name];
	}
	/* A kind chosen shows its part; a reference chosen, what is shown
	 * through it. */
	if ([element.kind isEqualToString:@"subtype"] || [element.kind isEqualToString:@"reference"]) {
		[self.values reloadData];
		[self.values selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
		return;
	}
	/* Choices that depend on it chosen again; the row shown as it is now
	 * (a date's picker, set, left alone: it says each change as it is typed). */
	NSString *editor = [self editorOfRow:row];
	if ([editor hasPrefix:@"date"] && [value length] > 0) {
		[self.values reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
		                        columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self.values columnWithIdentifier:@"name"]]];
	}
	NSMutableIndexSet *rows = [editor hasPrefix:@"date"] && [value length] > 0 ? [NSMutableIndexSet indexSet]
	                                                                         : [NSMutableIndexSet indexSetWithIndex:(NSUInteger)row];
	for (NSUInteger i = 0; i < [[self entriesShown] count]; i++) {
		if ([[self editorOfRow:(NSInteger)i] isEqualToString:@"choice"]) {
			[rows addIndex:i];
		}
	}
	[self.values reloadDataForRowIndexes:rows columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
}

- (IBAction)valueChanged:(id)sender
{
	NSInteger row = [self.values rowForView:sender];
	NSString *editor = [self editorOfRow:row];
	NSString *value = nil;
	if ([sender isKindOfClass:[NSDatePicker class]]) {
		value = [ORMFlowPlayFormatter([editor isEqualToString:@"date"] ? @"yyyy-MM-dd" : @"yyyy-MM-dd'T'HH:mm:ss'Z'")
		          stringFromDate:[sender dateValue]];
	} else if ([sender isKindOfClass:[NSPopUpButton class]]) {
		value = [[sender selectedItem] representedObject] ?: @"";
	} else if ([editor isEqualToString:@"flag"]) {
		value = [sender state] == NSControlStateValueOn ? @"true" : @"false";
	} else if ([[sender objectValue] isKindOfClass:[NSNumber class]]) {
		value = [[sender objectValue] description];
	} else {
		value = [sender stringValue];
	}
	if (row >= 0) {
		[self setValue:value ofRow:row];
	}
}

- (IBAction)setDate:(id)sender
{
	NSInteger row = [self.values rowForView:sender];
	for (NSView *each in [[sender superview] subviews]) {
		if ([each isKindOfClass:[NSDatePicker class]]) {
			[(NSDatePicker *)each setDateValue:[NSDate date]];
			[self valueChanged:each];
		}
	}
	/* Its picker shown, Set gone. */
	if (row >= 0) {
		[self.values reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
		                        columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self.values columnWithIdentifier:@"value"]]];
	}
}

- (IBAction)clearValue:(id)sender
{
	NSInteger row = [self.values rowForView:sender];
	if (row >= 0) {
		[self setValue:@"" ofRow:row];
	}
}

- (IBAction)addRow:(id)sender
{
	[self addRowAt:[self.values rowForView:sender]];
}

- (void)addRowAt:(NSInteger)line
{
	ORMFlowPlayEntry *entry = [self entryOfRow:line];
	ORMForm *repeat = entry.element == nil ? [_walk.session.form repeatNamed:entry.repeat] : nil;
	if (repeat == nil || repeat.isList) {
		NSBeep();
		return;
	}
	NSArray *rows = [_walk.session rowsOfRepeat:entry.repeat] ?: @[];
	[_walk.session setRows:[rows arrayByAddingObject:[repeat instanceGiven:@{}]] forRepeat:entry.repeat];
	[self.values reloadData];
}

- (IBAction)removeRow:(id)sender
{
	[self removeRowAt:[self.values rowForView:sender]];
}

- (void)removeRowAt:(NSInteger)line
{
	ORMFlowPlayEntry *entry = [self entryOfRow:line];
	NSMutableArray *rows = [[_walk.session rowsOfRepeat:entry.repeat ?: @""] mutableCopy];
	if (entry.element != nil || entry.row >= [rows count]) {
		NSBeep();
		return;
	}
	[rows removeObjectAtIndex:entry.row];
	[_walk.session setRows:rows forRepeat:entry.repeat];
	[self.values reloadData];
}

@end

/* A field in a row not chosen yet is typed into at the first click, not
 * the second (AppKit's table would have the row chosen first). */
@implementation ORMFlowPlayValuesTable

- (BOOL)validateProposedFirstResponder:(NSResponder *)responder forEvent:(NSEvent *)event
{
	return YES;
}

@end
