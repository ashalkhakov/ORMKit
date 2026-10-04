/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#import "ORMAppDelegate.h"
#import "ORMCanvasView.h"
#import "ORMCoreDataController.h"
#import "ORMDocument.h"
#import "ORMQueryController.h"
#import "ORMSampleMenu.h"
#import "ORMWindowController.h"

/* The designer driven as a modeller would: a NORMA file opened, elements
 * picked, the fact editor typed into, constraints toggled, the diagram
 * exported, the Core Data model synchronized. The window is real; it is
 * never shown. */
@interface ORMDesignerTests : XCTestCase
@end

@implementation ORMDesignerTests
{
	ORMDocument *_document;
	ORMWindowController *_controller;
}

- (void)setUp
{
	[super setUp];
	/* Fonts and windows need the application first, on GNUstep. */
	[NSApplication sharedApplication];
}

- (NSString *)fixturePath:(NSString *)name
{
	NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
	/* gnustep-make compiles from the bundle's directory, and __FILE__ is
	 * then relative to it. */
	if (![here isAbsolutePath]) {
		here = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:here];
	}
	return [[[here stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"ORMKitTests/Fixtures"]
		stringByAppendingPathComponent:name];
}

- (void)open:(NSString *)fixture
{
	_document = [[ORMDocument alloc] init];
	NSError *error = nil;
	XCTAssertTrue([_document readFromData:[NSData dataWithContentsOfFile:[self fixturePath:fixture]]
	                               ofType:ORMDocumentType error:&error], @"%@", error);
	[_document makeWindowControllers];
	_controller = [[_document windowControllers] firstObject];
	XCTAssertNotNil(_controller);
}

- (NSString *)verbalizationText
{
	return [[_controller.verbalization textStorage] string];
}

- (void)testANormaModelOpensOnItsFirstDiagram
{
	[self open:@"StockMate.orm"];
	XCTAssertEqualObjects([[_controller.canvas diagram] name], @"Products");
	XCTAssertEqual([_controller.diagramPopup numberOfItems], (NSInteger)4);
	XCTAssertTrue([_controller.browser.outlineView numberOfRows] > 40);
	/* Nothing changed by opening it. */
	XCTAssertFalse([_document isDocumentEdited]);
	NSData *saved = [_document dataOfType:ORMDocumentType error:NULL];
	XCTAssertEqualObjects(saved, [NSData dataWithContentsOfFile:[self fixturePath:@"StockMate.orm"]]);
}

/* Each of NORMA's diagram pages is a tab under the canvas, and shown, its
 * shapes in view, when picked. */
- (void)testEachDiagramPageIsShown
{
	[self open:@"StockMate.orm"];
	[[_controller window] setContentSize:NSMakeSize(900, 600)];
	NSSegmentedControl *tabs = _controller.diagramTabs;
	XCTAssertEqual([tabs segmentCount], (NSInteger)4);
	XCTAssertEqual([tabs selectedSegment], (NSInteger)0);
	for (NSInteger i = [tabs segmentCount] - 1; i >= 0; i--) {
		[tabs setSelectedSegment:i];
		[_controller chooseDiagramTab:tabs];
		ORMDiagram *diagram = [_controller.canvas diagram];
		XCTAssertEqualObjects(diagram.name, [tabs labelForSegment:i]);
		XCTAssertEqualObjects(diagram.name, [_controller.diagramPopup titleOfSelectedItem]);
		NSRect visible = [_controller.canvas visibleRect];
		NSUInteger seen = 0;
		for (ORMShape *shape in diagram.shapes) {
			seen += NSIntersectsRect(visible, shape.bounds) ? 1 : 0;
		}
		XCTAssertTrue(seen > 0, @"%@: none of %lu shapes in %@", diagram.name, (unsigned long)[diagram.shapes count],
		              NSStringFromRect(visible));
	}
}

/* File > Open Sample: the samples, then ActiveFacts's in a submenu; one
 * opens as an untitled copy named as the sample, its queries ready. */
- (void)testASampleOpensAsAnUntitledCopy
{
	NSString *root = [[[[self fixturePath:@"ActiveFacts"] stringByDeletingLastPathComponent]
		stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSArray *folders = @[ [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Samples"]],
	                      [NSURL fileURLWithPath:[self fixturePath:@"ActiveFacts"]] ];
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Open Sample"];
	[ORMSampleMenu fillMenu:menu fromFolders:folders];
	NSMutableArray *titles = [NSMutableArray array];
	for (NSMenuItem *item in [menu itemArray]) {
		[titles addObject:[item isSeparatorItem] ? @"-" : [item title]];
	}
	XCTAssertEqualObjects(titles, (@[ @"Company", @"UMLandORM", @"University", @"-", @"ActiveFacts" ]));
	XCTAssertEqual([[[menu itemWithTitle:@"ActiveFacts"] submenu] numberOfItems], (NSInteger)29);
	NSMenuItem *company = [menu itemWithTitle:@"Company"];
	XCTAssertEqual([company action], @selector(openSample:));

	NSUInteger before = [[[NSDocumentController sharedDocumentController] documents] count];
	[[[ORMAppDelegate alloc] init] openSample:company];
	ORMDocument *document = [[[NSDocumentController sharedDocumentController] documents] lastObject];
	XCTAssertEqual([[[NSDocumentController sharedDocumentController] documents] count], before + 1);
	XCTAssertNil([document fileURL]);
	XCTAssertEqualObjects([document displayName], @"Company");
	XCTAssertFalse([document isDocumentEdited]);
	XCTAssertEqual([[ORMQuery queriesInModel:document.editor.model] count], (NSUInteger)7);
	ORMWindowController *controller = [[document windowControllers] firstObject];
	XCTAssertEqualObjects([[controller.canvas diagram] name], @"Company");
	[document close];
}

- (void)testSelectingShowsTheInspectorAndVerbalization
{
	[self open:@"StockMate.orm"];
	ORMObjectType *product = [_document.editor.model objectTypeNamed:@"Product"];
	[_controller.canvas selectElements:@[ product.identifier ]];
	XCTAssertEqualObjects(_controller.inspector.elementId, product.identifier);
	XCTAssertTrue([[self verbalizationText] rangeOfString:@"Product is an entity type."].location != NSNotFound,
	              @"%@", [self verbalizationText]);
	XCTAssertEqual([_controller.canvas.selectedShapes count], (NSUInteger)1);
}

- (void)testTheBrowserFilters
{
	[self open:@"StockMate.orm"];
	NSOutlineView *outline = _controller.browser.outlineView;
	NSInteger all = [outline numberOfRows];
	[_controller filterBrowserWith:@"warehouse"];
	NSInteger rows = [outline numberOfRows];
	XCTAssertTrue(rows > 2 && rows < all, @"%ld of %ld", (long)rows, (long)all);
	for (NSInteger row = 0; row < rows; row++) {
		NSString *title = [[outline dataSource] outlineView:outline objectValueForTableColumn:nil
		                                              byItem:[outline itemAtRow:row]];
		XCTAssertTrue([title rangeOfString:@"Warehouse" options:NSCaseInsensitiveSearch].location != NSNotFound
		              || [outline isExpandable:[outline itemAtRow:row]], @"%@", title);
	}
	[_controller filterBrowserWith:@""];
	XCTAssertEqual([outline numberOfRows], all);
}

- (void)testTheBrowsersPlusAddsAnObjectType
{
	[self open:@"StockMate.orm"];
	[_controller newEntityType:nil];
	ORMObjectType *added = [_document.editor.model objectTypeNamed:@"EntityType"];
	XCTAssertNotNil(added);
	XCTAssertNotNil([[_controller.canvas diagram] shapeForSubject:added.identifier]);
}

- (void)testTheFactEditorAddsToTheDiagram
{
	[self open:@"StockMate.orm"];
	[_controller.factEditor setStringValue:@"Product(.Id) is supplied by Supplier(.code)"];
	XCTAssertTrue([_controller addFactFromEditor]);
	ORMModel *model = _document.editor.model;
	XCTAssertNotNil([model objectTypeNamed:@"Supplier"]);
	XCTAssertNotNil([[_controller.canvas diagram] shapeForSubject:[[model objectTypeNamed:@"Supplier"] identifier]]);
	/* NSDocument counts the change once the run loop turns. */
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
	XCTAssertTrue([_document isDocumentEdited]);
	XCTAssertTrue([[self verbalizationText] rangeOfString:@"Product is supplied by Supplier."].location != NSNotFound,
	              @"%@", [self verbalizationText]);
	/* A bad one says why and changes nothing. */
	NSUInteger facts = [model.factTypes count];
	[_controller.factEditor setStringValue:@"is lonely"];
	XCTAssertFalse([_controller addFactFromEditor]);
	XCTAssertEqual([_document.editor.model.factTypes count], facts);
	XCTAssertTrue([[_controller.status stringValue] length] > 0);
}

/* The fact editor takes constraints as the verbalizer says them, and
 * makes what they name. */
- (void)testTheFactEditorTakesConstraintSentences
{
	[self open:@"StockMate.orm"];
	/* A frequency is not read yet: refused, saying why, and nothing made. */
	[_controller.factEditor setStringValue:@"Each Supplier supplies at least 2 Product."];
	XCTAssertFalse([_controller addFactFromEditor]);
	XCTAssertNil([_document.editor.model objectTypeNamed:@"Each"]);
	XCTAssertTrue([[_controller.status stringValue] length] > 0);
	[_controller.factEditor setStringValue:@"Each Supplier supplies some Product."];
	XCTAssertTrue([_controller addFactFromEditor], @"%@", [_controller.status stringValue]);
	ORMModel *model = _document.editor.model;
	ORMObjectType *supplier = [model objectTypeNamed:@"Supplier"];
	XCTAssertNotNil(supplier);
	ORMRole *role = nil;
	for (ORMRole *each in supplier.playedRoles) {
		role = each;
	}
	XCTAssertTrue(role.isMandatory);
	XCTAssertTrue([[self verbalizationText] rangeOfString:@"Each Supplier supplies some Product."].location != NSNotFound,
	              @"%@", [self verbalizationText]);
}

- (void)testRolesAreConstrainedFromTheCanvas
{
	[self open:@"StockMate.orm"];
	[_controller.factEditor setStringValue:@"Product is stocked by Supplier(.code)"];
	XCTAssertTrue([_controller addFactFromEditor]);
	ORMFactType *fact = nil;
	for (ORMFactType *each in _document.editor.model.factTypes) {
		if ([[[each primaryReading] expandedText] isEqualToString:@"Product is stocked by Supplier"]) {
			fact = each;
		}
	}
	ORMRole *productRole = [fact.roles firstObject];
	[_controller.canvas selectElements:@[ productRole.identifier ]];
	[_controller.canvas toggleUniqueness:nil];
	[_controller.canvas toggleMandatory:nil];
	ORMRole *now = [_document.editor.model elementWithId:productRole.identifier];
	XCTAssertTrue(now.isUnique && now.isMandatory);
	XCTAssertTrue([[self verbalizationText] rangeOfString:@"Each Product is stocked by exactly one Supplier."].location
	              != NSNotFound, @"%@", [self verbalizationText]);
	/* And undone, one step at a time. */
	[[_document undoManager] undo];
	XCTAssertFalse([(ORMRole *)[_document.editor.model elementWithId:productRole.identifier] isMandatory]);
}

- (void)testTheDiagramExports
{
	[self open:@"StockMate.orm"];
	NSData *pdf = [_controller.canvas PDFData];
	XCTAssertTrue([pdf length] > 1000);
	XCTAssertEqualObjects([[NSString alloc] initWithData:[pdf subdataWithRange:NSMakeRange(0, 4)]
	                                            encoding:NSASCIIStringEncoding], @"%PDF");
#if defined(__APPLE__)
	NSData *png = [_controller.canvas PNGDataAtScale:2.0];
	XCTAssertTrue([png length] > 1000);
	NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ORMDesignerTests-Products.png"];
	[png writeToFile:out atomically:YES];
#endif
}

- (void)testTheCoreDataModelIsWrittenAndReadBack
{
	[self open:@"StockMate.orm"];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil
	                                                error:NULL];
	NSURL *documentURL = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"StockMate.orm"]];
	ORMCoreDataController *coreData = [[ORMCoreDataController alloc] initWithEditor:_document.editor
	                                                                   documentURL:documentURL];
	[coreData synchronize:nil];
	/* The window is the XIB's, its outlets connected. */
	XCTAssertEqualObjects([[coreData valueForKey:@"pathField"] stringValue], @"StockMate.xcdatamodeld");
	XCTAssertGreaterThan([(NSOutlineView *)[coreData valueForKey:@"preview"] numberOfRows], (NSInteger)10);
	XCTAssertTrue([[[coreData valueForKey:@"statusLabel"] stringValue] hasPrefix:@"Wrote "],
	              @"%@", [[coreData valueForKey:@"statusLabel"] stringValue]);
	NSString *package = [directory stringByAppendingPathComponent:@"StockMate.xcdatamodeld"];
	ORMCDModel *written = [ORMCDModel modelAtPath:package reason:NULL];
	XCTAssertNotNil(written);
	XCTAssertNotNil([written entityNamed:@"Product"]);
	XCTAssertNotNil([[ORMCoreDataMapping mappingsOfDocument:_document.editor.document].firstObject baseline]);
	/* Synchronized again with nothing changed: nothing to ask. */
	ORMCoreDataSync *again = [[ORMCoreDataSync alloc] initWithEditor:_document.editor mapping:coreData.mappingId
	                                                           theirs:written];
	XCTAssertEqual([again.changes count], (NSUInteger)0, @"%@", again.changes);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* A query built as ConQuer builds one: start at an object type, go on
 * through a fact type it plays in, and read it back in FORML and as a
 * fetch request. */
- (void)testAQueryIsBuiltFromTheModel
{
	[self open:@"StockMate.orm"];
	ORMEditor *editor = _document.editor;
	ORMQueryController *queries = [[ORMQueryController alloc] initWithEditor:editor];
	NSString *warehouse = [[editor.model objectTypeNamed:@"Warehouse"] identifier];
	NSString *query = [queries addQueryFrom:warehouse];
	XCTAssertNotNil(query);
	XCTAssertEqualObjects(queries.selectedId, [[ORMQuery queryWithId:query inModel:editor.model] root].identifier);
	ORMRole *contains = nil;
	for (ORMRole *role in [queries availableRoles]) {
		for (ORMRole *other in role.factType.roles) {
			if (other != role && [other.player.name isEqualToString:@"Location"]) {
				contains = role;
			}
		}
	}
	XCTAssertNotNil(contains, @"%@", [[queries availableRoles] valueForKeyPath:@"factType.name"]);
	XCTAssertNotNil([queries addStepThrough:contains]);
	ORMQuery *built = [ORMQuery queryWithId:query inModel:editor.model];
	XCTAssertEqual([built.root.steps count], 1u);
	XCTAssertTrue([[built outlineText] rangeOfString:@"Location"].location != NSNotFound, @"%@", [built outlineText]);
	XCTAssertTrue([[queries verbalizationText] hasPrefix:@"List each Warehouse where"], @"%@",
	              [queries verbalizationText]);
	XCTAssertTrue([[queries fetchText] rangeOfString:@"fetch Warehouse"].location != NSNotFound,
	              @"%@", [queries fetchText]);
	/* The window is the XIB's, its outlets connected: what it shows is what
	 * the controller says. */
	XCTAssertNotNil([queries window]);
	XCTAssertEqualObjects([[[queries valueForKey:@"verbalizationView"] textStorage] string], [queries verbalizationText]);
	XCTAssertEqualObjects([[[queries valueForKey:@"fetchView"] textStorage] string], [queries fetchText]);
	XCTAssertEqual([(NSOutlineView *)[queries valueForKey:@"outline"] numberOfRows], (NSInteger)3);
	/* Undone, the step is gone, and the window shows it. */
	[[_document undoManager] undo];
	[queries modelDidChange];
	XCTAssertEqual([[ORMQuery queryWithId:query inModel:editor.model].root.steps count], 0u);
}

/* The menu bar comes from MainMenu.xib, with what the XIB cannot hold set
 * in code. */
- (void)testTheMenuBarIsLoaded
{
	NSMenu *menu = [ORMAppDelegate newMainMenu];
	/* GNUstep's loader makes the application menu "Info" and adds Quit at
	 * the end, as its menus have them. */
	NSArray *titles = [[menu itemArray] valueForKey:@"title"];
	NSArray *ours = @[ @"File", @"Edit", @"Model", @"Diagram", @"Core Data", @"Query", @"Window" ];
	NSUInteger file = [titles indexOfObject:@"File"];
	XCTAssertTrue(file != NSNotFound && file + [ours count] <= [titles count], @"%@", titles);
	if (file != NSNotFound && file + [ours count] <= [titles count]) {
		XCTAssertEqualObjects([titles subarrayWithRange:NSMakeRange(file, [ours count])], ours);
	}
	NSMenu *model = [[menu itemWithTitle:@"Model"] submenu];
	XCTAssertEqual([[model itemWithTitle:@"Fact Type"] tag], (NSInteger)ORMToolFactType);
	NSMenu *constraints = [[model itemWithTitle:@"Add Constraint"] submenu];
	XCTAssertEqual([[constraints itemWithTitle:@"Value Comparison"] tag], (NSInteger)ORMToolValueComparison);
	NSMenuItem *remove = [[[menu itemWithTitle:@"Edit"] submenu] itemWithTitle:@"Remove from Diagram"];
	XCTAssertEqualObjects([remove keyEquivalent], @"\b");
	NSMenuItem *synchronize = [[[menu itemWithTitle:@"Core Data"] submenu] itemWithTitle:@"Synchronize"];
	XCTAssertEqualObjects([synchronize keyEquivalent], @"k");
	XCTAssertEqual([synchronize keyEquivalentModifierMask] & (NSEventModifierFlagCommand | NSEventModifierFlagOption
	                                                          | NSEventModifierFlagShift),
	               NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift);
}

/* Labels and node comparisons, as they are typed: "1" in Label, and
 * "Warehouse1" as a condition's value, the node so labelled. */
- (void)testAQueryCorrelatesAsTyped
{
	[self open:@"StockMate.orm"];
	ORMEditor *editor = _document.editor;
	ORMQueryController *queries = [[ORMQueryController alloc] initWithEditor:editor];
	NSString *query = [queries addQueryFrom:[[editor.model objectTypeNamed:@"Warehouse"] identifier]];
	NSString *root = queries.selectedId;
	[[queries valueForKey:@"labelField"] setStringValue:@"1"];
	[queries performSelector:@selector(labelChanged:) withObject:nil];
	ORMRole *(^roleTo)(NSString *) = ^ORMRole *(NSString *name) {
		for (ORMRole *role in [queries availableRoles]) {
			for (ORMRole *other in role.factType.roles) {
				if (other != role && [other.player.name isEqualToString:name]) {
					return role;
				}
			}
		}
		return nil;
	};
	XCTAssertNotNil([queries addStepThrough:roleTo(@"Location")]);
	ORMQueryNode *location = [[[[ORMQuery queryWithId:query inModel:editor.model].root.steps firstObject] nodes] firstObject];
	[queries selectElement:location.identifier];
	XCTAssertNotNil([queries addStepThrough:roleTo(@"Warehouse")]);
	ORMQueryNode *again = [[[ORMQuery queryWithId:query inModel:editor.model] nodes] lastObject];
	[queries selectElement:again.identifier];
	[[queries valueForKey:@"comparisonPopUp"] selectItemWithTitle:@"="];
	[[queries valueForKey:@"valueField"] setStringValue:@"Warehouse1"];
	[queries performSelector:@selector(conditionChanged:) withObject:nil];

	ORMQuery *built = [ORMQuery queryWithId:query inModel:editor.model];
	XCTAssertEqualObjects([built.root designation], @"Warehouse1");
	ORMQueryNode *last = [[built nodes] lastObject];
	XCTAssertEqualObjects(last.comparedNode.identifier, root);
	XCTAssertTrue([[built outlineText] rangeOfString:@"Warehouse = Warehouse1"].location != NSNotFound, @"%@", [built outlineText]);
}

/* An aggregate and an order, set in the window: warehouses with more
 * than two locations, the last first. */
- (void)testAQueryAggregatesAndSortsAsSet
{
	[self open:@"StockMate.orm"];
	ORMEditor *editor = _document.editor;
	ORMQueryController *queries = [[ORMQueryController alloc] initWithEditor:editor];
	NSString *query = [queries addQueryFrom:[[editor.model objectTypeNamed:@"Warehouse"] identifier]];
	[[queries valueForKey:@"sortPopUp"] selectItemAtIndex:ORMQueryDescending];
	[queries performSelector:@selector(sortChanged:) withObject:nil];
	ORMRole *contains = nil;
	for (ORMRole *role in [queries availableRoles]) {
		for (ORMRole *other in role.factType.roles) {
			if (other != role && [other.player.name isEqualToString:@"Location"]) {
				contains = role;
			}
		}
	}
	NSString *step = [queries addStepThrough:contains];
	XCTAssertEqualObjects(queries.selectedId, step);
	[[queries valueForKey:@"aggregatePopUp"] selectItemAtIndex:ORMQueryCount];
	[[queries valueForKey:@"countComparisonPopUp"] selectItemWithTitle:@">"];
	[[queries valueForKey:@"countField"] setStringValue:@"2"];
	[queries performSelector:@selector(countChanged:) withObject:nil];

	ORMQuery *built = [ORMQuery queryWithId:query inModel:editor.model];
	XCTAssertEqual(built.root.sortOrder, ORMQueryDescending);
	ORMQueryStep *made = [built.root.steps firstObject];
	XCTAssertEqualObjects(made.countComparison, @">");
	XCTAssertEqual(made.countValue, 2u);
	XCTAssertEqualObjects(made.aggregateNode.objectType.name, @"Location");
	XCTAssertTrue([[queries fetchText] rangeOfString:@"sorted by"].location != NSNotFound, @"%@", [queries fetchText]);
	XCTAssertTrue([[queries requestText] rangeOfString:@"GET Warehouses?$filter="].location != NSNotFound,
	              @"%@", [queries requestText]);
	XCTAssertTrue([[queries requestText] rangeOfString:@"$orderby="].location != NSNotFound, @"%@", [queries requestText]);
	XCTAssertEqualObjects([[[queries valueForKey:@"requestView"] textStorage] string], [queries requestText]);
}

- (void)testEveryMenuItemHasSomewhereToGo
{
	[self open:@"StockMate.orm"];
	NSMenu *menu = [ORMAppDelegate newMainMenu];
	NSArray *responders = @[ _controller, _controller.canvas, _document, [NSDocumentController sharedDocumentController],
	                         NSApp, [_controller window], [[ORMAppDelegate alloc] init] ];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:menu];
	NSArray *standard = @[ @"undo:", @"redo:", @"cut:", @"copy:", @"paste:", @"performMiniaturize:", @"arrangeInFront:",
	                       @"orderFrontStandardAboutPanel:", @"hide:", @"terminate:" ];
	while ([pending count] > 0) {
		NSMenu *current = [pending lastObject];
		[pending removeLastObject];
		for (NSMenuItem *item in [current itemArray]) {
			if ([item submenu] != nil) {
				[pending addObject:[item submenu]];
				continue;
			}
			SEL action = [item action];
			if (action == NULL || [standard containsObject:NSStringFromSelector(action)]) {
				continue;
			}
			BOOL handled = NO;
			for (id responder in responders) {
				handled = handled || [responder respondsToSelector:action];
			}
			XCTAssertTrue(handled, @"nothing answers %@ (%@)", NSStringFromSelector(action), [item title]);
		}
	}
}

@end
