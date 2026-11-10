/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
/* UDCode's ORM2 extension against UDCode's own document and text model
 * (its SDK): a model is its document's text, each change one edit of it,
 * the text's undo undoing it; a text that is no model says why. */
#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "ORM2EditorViewController.h"
#import "ORM2FlowEditorViewController.h"
#import "ORMFlowWindowController.h"
#import "ORMFlowCanvasView.h"
#import "ORM2Extension.h"
#import "ORM2TextDiff.h"
#import "ORMModelViewController.h"

@interface ORM2Tests : XCTestCase
@end

@implementation ORM2Tests
{
	UDCodeDocument *_document;
	ORM2EditorViewController *_tab;
	NSWindow *_window;
	NSUInteger _edits;
}

- (void)setUp
{
	[super setUp];
	[NSApplication sharedApplication];
}

- (void)tearDown
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super tearDown];
}

- (NSString *)fixture:(NSString *)name
{
	NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
	/* gnustep-make compiles from the bundle's directory, and __FILE__ is
	 * then relative to it. */
	if (![here isAbsolutePath]) {
		here = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:here];
	}
	NSString *path = [[[[here stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
		stringByAppendingPathComponent:@"ORMKitTests/Fixtures"] stringByAppendingPathComponent:name];
	return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

- (void)countEdit:(NSNotification *)notification
{
	(void)notification;
	_edits++;
}

/* The tab over a document of the text, its view loaded in a window as
 * UDCode's tab would have it. */
- (void)openText:(NSString *)text
{
	_document = [[UDCodeDocument alloc] initWithText:text fileURL:nil languageMode:nil];
	_tab = [[ORM2EditorViewController alloc] initWithDocument:_document workbench:nil];
	_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 700)
	                                      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
	[_window setReleasedWhenClosed:NO];
	[[_tab view] setFrame:[[_window contentView] bounds]];
	[[_window contentView] addSubview:[_tab view]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(countEdit:)
	                                             name:UDTextModelDidChangeNotification object:_document.textModel];
}

- (void)testAModelOpensInTheEditor
{
	NSString *text = [self fixture:@"StockMate.orm"];
	XCTAssertNotNil(text);
	[self openText:text];
	XCTAssertNil(_tab.problem);
	XCTAssertNotNil(_tab.modelController);
	XCTAssertNotNil([_tab.modelController.editor.model objectTypeNamed:@"Product"]);
	XCTAssertEqualObjects([[_tab.modelController view] superview], [_tab view]);
	/* Opened, the text is as it was: nothing is written until it changes. */
	XCTAssertEqualObjects([_document.textModel getValue], text);
	XCTAssertEqual(_edits, (NSUInteger)0);
}

- (void)testAChangeIsOneEditOfTheTextAndItsUndoReadsTheModelAgain
{
	NSString *text = [self fixture:@"StockMate.orm"];
	[self openText:text];
	ORMEditor *editor = _tab.modelController.editor;
	NSString *diagram = [[editor.model.diagrams firstObject] identifier];
	NSString *reason = nil;
	NSString *added = [editor.objectTypeEditor addEntityTypeNamed:@"Courier" referenceMode:@"id" kind:ORMReferenceModePopular
	                                                    onDiagram:diagram at:NSMakePoint(40, 40) reason:&reason];
	XCTAssertNotNil(added, @"%@", reason);
	XCTAssertEqual(_edits, (NSUInteger)1);
	NSString *changed = [_document.textModel getValue];
	XCTAssertTrue([changed rangeOfString:@"Name=\"Courier\""].location != NSNotFound);
	/* What was written is what the editor would save. */
	XCTAssertEqualObjects(changed, [[NSString alloc] initWithData:[editor dataForSaving] encoding:NSUTF8StringEncoding]);
	XCTAssertTrue(_document.textModel.undoManager.canUndo);

	[_tab undo:nil];
	XCTAssertEqualObjects([_document.textModel getValue], text);
	/* Read again at once (the tab is in a window), the model has no Courier. */
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	XCTAssertNil([_tab.modelController.editor.model objectTypeNamed:@"Courier"]);
	XCTAssertNotNil([_tab.modelController.editor.model objectTypeNamed:@"Product"]);

	[_tab redo:nil];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	XCTAssertEqualObjects([_document.textModel getValue], changed);
	XCTAssertNotNil([_tab.modelController.editor.model objectTypeNamed:@"Courier"]);
}

/* The edit is the lines that differ, not the whole text. (The first
 * change of a file NORMA saved also drops what NORMA generates from the
 * model, its relational bridge and error list, which it makes again.) */
- (void)testTheEditIsTheLinesThatChanged
{
	[self openText:[self fixture:@"StockMate.orm"]];
	ORMObjectType *product = [_tab.modelController.editor.model objectTypeNamed:@"Product"];
	XCTAssertTrue([_tab.modelController.editor.elementEditor rename:product.identifier to:@"Item" reason:NULL]);
	NSString *text = [_document.textModel getValue];
	__block UDTextModelContentChange *change = nil;
	id observer = [[NSNotificationCenter defaultCenter] addObserverForName:UDTextModelDidChangeNotification
	                                                                object:_document.textModel queue:nil
	                                                            usingBlock:^(NSNotification *note) {
		change = [[[note userInfo] objectForKey:UDTextModelChangesKey] firstObject];
	}];
	ORMEditor *editor = _tab.modelController.editor;
	NSString *reason = nil;
	XCTAssertTrue([editor.elementEditor rename:product.identifier to:@"Article" reason:&reason], @"%@", reason);
	[[NSNotificationCenter defaultCenter] removeObserver:observer];
	XCTAssertNotNil(change);
	/* Whole lines, starting at a line's start: a few of them, not the file. */
	XCTAssertEqual(change.range.startColumn, (NSInteger)1);
	XCTAssertLessThan(change.rangeLength, (NSInteger)[text length] / 4);
	XCTAssertTrue([change.text rangeOfString:@"Article"].location != NSNotFound);
	XCTAssertTrue([[_document.textModel getValue] rangeOfString:@"Name=\"Article\""].location != NSNotFound);
}

/* Old with each change applied, last first (their offsets are old's). */
static NSString *
ORM2Applied(NSString *old, NSArray<ORM2TextChange *> *changes)
{
	NSMutableString *text = [old mutableCopy];
	for (ORM2TextChange *change in [changes reverseObjectEnumerator]) {
		[text replaceCharactersInRange:NSMakeRange(change.offset, change.length) withString:change.text];
	}
	return text;
}

- (void)testTheLineDiffChangesOnlyWhatDiffers
{
	NSString *old = @"a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\n";
	NSArray *same = ORM2LineChanges(old, old);
	XCTAssertEqual([same count], (NSUInteger)0);
	/* Two runs apart: b changed, a line after e added. */
	NSString *new = @"a\r\nB\r\nc\r\nd\r\ne\r\nx\r\nf\r\ng\r\n";
	NSArray *changes = ORM2LineChanges(old, new);
	XCTAssertEqual([changes count], (NSUInteger)2);
	ORM2TextChange *first = [changes firstObject], *last = [changes lastObject];
	XCTAssertEqual(first.offset, (NSUInteger)3);
	XCTAssertEqualObjects(first.text, @"B\r\n");
	XCTAssertEqual(last.length, (NSUInteger)0);
	XCTAssertEqualObjects(last.text, @"x\r\n");
	XCTAssertEqualObjects(ORM2Applied(old, changes), new);
	/* Lines dropped, at the start and the end, and no final line ending. */
	for (NSString *other in @[ @"c\r\nd\r\ne\r\nf\r\ng\r\n", @"a\r\nb\r\nc", @"", @"z", @"a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\nh" ]) {
		XCTAssertEqualObjects(ORM2Applied(old, ORM2LineChanges(old, other)), other);
		XCTAssertEqualObjects(ORM2Applied(other, ORM2LineChanges(other, old)), old);
	}
}

- (void)testATextThatIsNoModelSaysWhy
{
	[self openText:@"<not a model/>"];
	XCTAssertNil(_tab.modelController);
	XCTAssertNotNil(_tab.problem);
	/* Made one as text, it is shown. */
	UDTextModel *model = _document.textModel;
	UDRange all = [model validateRange:(UDRange){ 1, 1, NSIntegerMax, NSIntegerMax }];
	[model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:all text:[self fixture:@"StockMate.orm"]] ]];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	XCTAssertNil(_tab.problem);
	XCTAssertNotNil(_tab.modelController);
}

/* The editor's parts are UDCode's panes': the tab has the diagram and the
 * Document Outline; the inspector, the panes under the diagram and the
 * Insert palette are the window's to place (UDEditorPanes). */
- (void)testItsPartsAreTheWindowsPanes
{
	[self openText:[self fixture:@"StockMate.orm"]];
	ORMModelViewController *editor = _tab.modelController;
	XCTAssertTrue(editor.hosted);
	NSArray *inspectors = [_tab inspectorViewControllers];
	XCTAssertEqual([inspectors count], (NSUInteger)1);
	XCTAssertEqualObjects([[inspectors firstObject] title], @"Element");
	XCTAssertFalse([[[inspectors firstObject] view] isDescendantOf:[_tab view]], @"not in the tab");
	XCTAssertTrue([editor.inspector isDescendantOf:[[inspectors firstObject] view]]);
	NSArray *titles = [[_tab bottomAreaViewControllers] valueForKey:@"title"];
	NSArray *expected = @[ @"Verbalization", @"Fact Entry", @"Population" ];
	XCTAssertEqualObjects(titles, expected);
	XCTAssertTrue([editor.verbalization isDescendantOf:[[[_tab bottomAreaViewControllers] firstObject] view]]);
	XCTAssertNotNil([_tab imageForBottomAreaViewController:[[_tab bottomAreaViewControllers] firstObject]]);
	XCTAssertNotNil([_tab libraryViewController]);
	XCTAssertTrue([editor.canvas isDescendantOf:[_tab view]], @"the diagram is the tab's");

	/* New Fact Type… asks for the Fact Entry pane. */
	__block NSViewController *asked = nil;
	editor.showLowerHandler = ^(NSViewController *pane) {
		asked = pane;
	};
	[editor focusFactEditor:nil];
	XCTAssertEqual(asked, [[_tab bottomAreaViewControllers] objectAtIndex:1]);
}

/* The model's issues are the document's diagnostics, each at its
 * element's line; one chosen selects its element. */
- (void)testItsIssuesAreTheDocumentsDiagnostics
{
	/* A model with an entity type that has no reference scheme: an error. */
	[self openText:[self fixture:@"StockMate.orm"]];
	ORMEditor *editor = _tab.modelController.editor;
	NSString *diagram = [[editor.model.diagrams firstObject] identifier];
	NSString *added = [editor.objectTypeEditor addEntityTypeNamed:@"Orphan" referenceMode:nil kind:ORMReferenceModeNone
	                                                    onDiagram:diagram at:NSMakePoint(40, 40) reason:NULL];
	XCTAssertNotNil(added);
	/* Found a moment after the change (half a second): waited for, up to
	 * five, as a loaded machine (CI's aarch64) takes longer. */
	UDDiagnosticItem *orphan = nil;
	for (NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5]; orphan == nil && [until timeIntervalSinceNow] > 0;) {
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		for (UDDiagnosticItem *item in _document.diagnosticStore.allDiagnostics) {
			if ([item.message rangeOfString:@"Orphan"].location != NSNotFound) {
				orphan = item;
			}
		}
	}
	XCTAssertNotNil(orphan, @"%@", [_document.diagnosticStore.allDiagnostics valueForKey:@"message"]);
	NSString *line = [_document.textModel getLineContent:orphan.line];
	XCTAssertTrue([line rangeOfString:added].location != NSNotFound, @"at its element's line: %@", line);
	[_tab.modelController.canvas clearSelection];
	[_tab revealDiagnostic:orphan];
	XCTAssertEqualObjects(_tab.modelController.inspector.elementId, added);
}

/* A flow's tab (ORM2FlowEditor.xib): the Fleet sample's flow, its model
 * read from beside it, in the flow designer's view, connected; a screen
 * renamed there is one edit of the text, which its undo takes back; a text
 * that is no flow says why. */
- (void)testAFlowOpensInItsTab
{
	NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
	if (![here isAbsolutePath]) {
		here = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:here];
	}
	NSString *path = [[[here stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
		stringByAppendingPathComponent:@"Samples/Fleet.flow"];
	NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
	XCTAssertNotNil(text, @"%@", path);
	UDCodeDocument *document = [[UDCodeDocument alloc] initWithText:text fileURL:[NSURL fileURLWithPath:path] languageMode:nil];
	ORM2FlowEditorViewController *tab = [[ORM2FlowEditorViewController alloc] initWithDocument:document workbench:nil];
	XCTAssertNil(tab.problem, @"%@", tab.problem);
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 760)
	                                               styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
	[window setReleasedWhenClosed:NO];
	[[tab view] setFrame:[[window contentView] bounds]];
	[[window contentView] addSubview:[tab view]];
	ORMFlowWindowController *designer = tab.flowController;
	XCTAssertNotNil(designer);
	for (NSString *outlet in @[ @"canvas", @"palette", @"problems", @"inspector", @"gives" ]) {
		XCTAssertNotNil([designer valueForKey:outlet], @"%@ connected", outlet);
	}
	XCTAssertTrue([designer.canvas isDescendantOf:[tab view]], @"the designer's view is the tab's");
	/* Its inspector a tab of the window's inspector, not a pane of the tab. */
	NSArray *inspectors = [tab inspectorViewControllers];
	XCTAssertEqual([inspectors count], 1u);
	XCTAssertTrue([designer.inspector isDescendantOf:[[inspectors firstObject] view]]);
	XCTAssertFalse([designer.inspector isDescendantOf:[tab view]]);
	XCTAssertNotNil([tab imageForInspectorViewController:[inspectors firstObject]]);
	XCTAssertNotNil(designer.openQueryHandler, @"a screen's form opens in the model's tab");
	XCTAssertFalse([[designer window] isVisible], @"its own window never shown");
	XCTAssertEqual([designer.editor.flow.screens count], 5u);
	XCTAssertEqual([designer.palette numberOfRows], 5, @"the model's four forms and its list");
	XCTAssertEqual([designer.problems numberOfRows], 0);

	[designer.editor renameScreen:@"Vehicles" to:@"Vans"];
	XCTAssertTrue([[document.textModel getValue] rangeOfString:@"Name=\"Vans\""].location != NSNotFound, @"written to the text");
	XCTAssertTrue(document.textModel.undoManager.canUndo);
	[document.textModel.undoManager undo];
	XCTAssertEqualObjects([document.textModel getValue], text, @"undone as the text");
	XCTAssertEqualObjects([designer.editor.flow screenWithId:@"Vehicles"].name, @"Vehicles", @"and read again");

	/* What is wrong of it: the document's diagnostics, at its screen's
	 * line, not a table in the tab; choosing one chooses its screen. */
	XCTAssertTrue([[designer.problems enclosingScrollView] isHidden], @"the Issues navigator's, not the tab's");
	NSUInteger flowIssues = 0;
	for (UDDiagnosticItem *item in document.diagnosticStore.allDiagnostics) {
		flowIssues += [item.source isEqualToString:@"ormflow"] ? 1 : 0;
	}
	XCTAssertEqual(flowIssues, 0u, @"the sample holds");
	NSUInteger index = [designer.editor.flow.transitions count];
	XCTAssertNotNil([designer.editor addTransitionFrom:@"RecordFillUp" to:@"Vehicles"]);
	[designer.editor setOn:ORMFlowOnRowChosen control:nil ofTransition:index];
	UDDiagnosticItem *rowless = nil;
	for (UDDiagnosticItem *item in document.diagnosticStore.allDiagnostics) {
		if ([item.message rangeOfString:@"a form has no rows to choose"].location != NSNotFound) {
			rowless = item;
		}
	}
	XCTAssertNotNil(rowless, @"%@", [document.diagnosticStore.allDiagnostics valueForKey:@"message"]);
	XCTAssertTrue([[document.textModel getLineContent:rowless.line] rangeOfString:@"id=\"RecordFillUp\""].location != NSNotFound,
	              @"at its screen's line");
	designer.canvas.selection = [NSSet set];
	[tab revealDiagnostic:rowless];
	XCTAssertEqualObjects(designer.canvas.selection, [NSSet setWithObject:[ORMFlowCanvasView itemOfScreen:@"RecordFillUp"]]);

	UDCodeDocument *broken = [[UDCodeDocument alloc] initWithText:@"<nothing" fileURL:nil languageMode:nil];
	ORM2FlowEditorViewController *none = [[ORM2FlowEditorViewController alloc] initWithDocument:broken workbench:nil];
	XCTAssertTrue([none.problem hasPrefix:@"This is not a flow that can be shown"], @"%@", none.problem);
	[window close];
}

/* The Editor menu's items and Undo reach the tab, and its editor, from
 * the canvas. */
- (void)testTheTabIsInTheChain
{
	[self openText:[self fixture:@"StockMate.orm"]];
	BOOL editor = NO, tab = NO;
	for (NSResponder *responder = _tab.modelController.canvas; responder != nil; responder = [responder nextResponder]) {
		editor = editor || responder == _tab.modelController;
		tab = tab || responder == _tab;
	}
	XCTAssertTrue(editor);
	XCTAssertTrue(tab);
	NSArray *titles = [[[[ORM2Extension alloc] init] editorMenuItemsForWorkbench:nil] valueForKey:@"title"];
	NSArray *expected = @[ @"Model", @"Diagram", @"Core Data", @"Query" ];
	XCTAssertEqualObjects(titles, expected);
}

@end
