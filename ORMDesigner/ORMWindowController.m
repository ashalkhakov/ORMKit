/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMWindowController.h"
#import "ORMCoreDataController.h"
#import "ORMDocument.h"
#import "ORMQueryController.h"
#import "ORMInsertPalette.h"
#import "ORMIssuesView.h"
#import "ORMSearchNavigator.h"
#import "ORMPopulationView.h"
#import "ORMPane.h"
#import "ThirdParty/DMTabBar/DMTabBar.h"

static const double ORMFactBarHeight = 30;

@interface ORMWindowController () <ORMInsertPaletteDelegate, ORMNavigatorDelegate>
@property (nonatomic, readwrite, strong) IBOutlet ORMCanvasView *canvas;
@property (nonatomic, readwrite, strong) IBOutlet ORMInspectorView *inspector;
@property (nonatomic, readwrite, strong) IBOutlet NSTextView *verbalization;
@property (nonatomic, readwrite, strong) IBOutlet NSTextField *factEditor;
@property (nonatomic, readwrite, strong) IBOutlet NSPopUpButton *diagramPopup;
@property (nonatomic, strong) IBOutlet NSView *diagramTabsBar;
@property (nonatomic, readwrite, strong) IBOutlet NSTextField *status;
@property (nonatomic, strong) IBOutlet NSOutlineView *browserOutline;
@property (nonatomic, strong) IBOutlet NSView *toolBar;
@property (nonatomic, strong) IBOutlet NSPopUpButton *addPopUp;
@property (nonatomic, strong) IBOutlet NSSearchField *filterField;
@property (nonatomic, strong) IBOutlet NSScrollView *canvasScroll;
@property (nonatomic, strong) IBOutlet NSScrollView *verbalizationScroll;
@property (nonatomic, strong) IBOutlet NSScrollView *inspectorScroll;
@property (nonatomic, strong) IBOutlet NSSplitView *columnsSplit;
@property (nonatomic, strong) IBOutlet NSSplitView *middleSplit;
/* The navigator (docs/WINDOW.md): its tab bar and tabs, and the hosts of
 * the panes put in them. */
@property (nonatomic, strong) IBOutlet NSView *leftTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *leftTabView;
@property (nonatomic, strong) IBOutlet NSView *insertHost;
@property (nonatomic, strong) IBOutlet NSView *searchHost;
@property (nonatomic, strong) IBOutlet NSView *issuesHost;
@property (nonatomic, strong) ORMInsertPalette *insertPalette;
@property (nonatomic, strong) ORMSearchNavigator *searchNavigator;
@property (nonatomic, strong) ORMIssuesView *issuesView;
/* The tabs under the canvas, and the Population tab's pane. */
@property (nonatomic, strong) IBOutlet NSView *lowerTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *lowerTabView;
@property (nonatomic, strong) IBOutlet NSView *populationHost;
@property (nonatomic, strong) ORMPopulationView *populationView;
@end

@implementation ORMWindowController
{
	__weak ORMDocument *_document;
	ORMCoreDataController *_coreData;
	ORMQueryController *_queries;
	/* What the verbalization shows when nothing is selected: the model, or
	 * nothing. */
	BOOL _verbalizesModel;
}

- (instancetype)initWithDocument:(ORMDocument *)document
{
	if ((self = [super initWithWindowNibName:@"ORMDocumentWindow"])) {
		_document = document;
		[self window];
	}
	return self;
}

#pragma mark Building

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

/* The navigator's tabs, as RDLDesigner's (docs/WINDOW.md): a badge each,
 * its name the tool tip; and the panes put in them. */
- (void)makeNavigator
{
	DMTabBar *bar = (DMTabBar *)self.leftTabBar;
	if ([bar isKindOfClass:[DMTabBar class]]) {
		NSMutableArray *items = [NSMutableArray array];
		NSUInteger tag = 0;
		for (NSArray *page in @[ @[ @"O", @"Outline", @0.47, @0.53, @0.64 ], @[ @"I", @"Insert", @0.32, @0.60, @0.53 ],
		                         @[ @"S", @"Search", @0.36, @0.49, @0.72 ], @[ @"!", @"Issues", @0.72, @0.42, @0.40 ] ]) {
			DMTabBarItem *item = [DMTabBarItem tabBarItemWithIcon:ORMTabBadge([page objectAtIndex:0],
			                                                                  [[page objectAtIndex:2] doubleValue],
			                                                                  [[page objectAtIndex:3] doubleValue],
			                                                                  [[page objectAtIndex:4] doubleValue])
			                                                  tag:tag++];
			item.toolTip = [page objectAtIndex:1];
			[items addObject:item];
		}
		bar.tabBarItems = items;
		[bar setTarget:self action:@selector(navigatorTabChanged:)];
		bar.selectedIndex = 0;
	}
	self.insertPalette = [[ORMInsertPalette alloc] initWithFrame:[self.insertHost bounds]];
	self.insertPalette.delegate = self;
	ORMFillHost(self.insertHost, self.insertPalette);
	self.searchNavigator = [[ORMSearchNavigator alloc] initWithFrame:[self.searchHost bounds]];
	self.searchNavigator.delegate = self;
	ORMFillHost(self.searchHost, self.searchNavigator);
	self.issuesView = [[ORMIssuesView alloc] initWithFrame:[self.issuesHost bounds]];
	self.issuesView.delegate = self;
	ORMFillHost(self.issuesHost, self.issuesView);
}

/* The issues found again a moment after the model changes, as RDLDesigner's
 * problems pane does: a burst of changes finds them once. */
- (void)scheduleIssues
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(findIssues) object:nil];
	[self performSelector:@selector(findIssues) withObject:nil afterDelay:0.5];
}

- (void)findIssues
{
	self.issuesView.editor = [self editor];
	[self.issuesView reload];
}

/* An element chosen in a navigator: shown, on a page that shows it; a
 * query's id, the Queries window on it. */
- (void)navigatorDidChooseElement:(NSString *)elementId
{
	ORMModel *model = [self editor].model;
	if ([model elementWithId:elementId] == nil) {
		if ([ORMQuery queryWithId:elementId inModel:model] != nil) {
			ORMQueryController *queries = [self queryController];
			queries.queryId = elementId;
			[queries showWindow:self];
			[queries modelDidChange];
		}
		return;
	}
	if ([[_canvas diagram] shapeForSubject:elementId] == nil) {
		for (ORMDiagram *diagram in model.diagrams) {
			if ([diagram shapeForSubject:elementId] != nil) {
				[self openDiagram:diagram.identifier];
				break;
			}
		}
	}
	[self showElement:elementId];
}

/* The bar's item chosen: its tab. The sender is the bar, not the item. */
- (void)navigatorTabChanged:(id)sender
{
	if (![sender isKindOfClass:[DMTabBar class]]) {
		return;
	}
	NSInteger index = (NSInteger)[(DMTabBar *)sender selectedIndex];
	if (index >= 0 && index < [self.leftTabView numberOfTabViewItems]) {
		[self.leftTabView selectTabViewItemAtIndex:index];
	}
}

/* The top bar's alignment (docs/WINDOW.md): the shapes selected, lined up
 * as the button's tag says (ORMAlignment). */
- (IBAction)alignSelection:(id)sender
{
	NSString *reason = nil;
	if (![[self editor].diagramEditor alignShapes:_canvas.selectedShapes as:(ORMAlignment)[sender tag] reason:&reason]) {
		NSBeep();
		[self say:reason];
	}
}

- (void)insertPalette:(ORMInsertPalette *)palette didChooseTool:(ORMCanvasTool)tool
{
	(void)palette;
	[self.canvas useTool:tool];
}

- (void)filterBrowser:(id)sender
{
	(void)sender;
	_browser.filter = [_filterField stringValue];
}

/* The filter follows each keystroke. */
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] == _filterField) {
		[self filterBrowser:nil];
	}
}

- (IBAction)focusBrowserFilter:(id)sender
{
	(void)sender;
	[[self window] makeFirstResponder:_filterField];
}

- (void)filterBrowserWith:(NSString *)text
{
	[_filterField setStringValue:text ?: @""];
	[self filterBrowser:nil];
}

- (IBAction)newEntityType:(id)sender
{
	(void)sender;
	[_canvas createObjectTypeAt:ORMAutomaticPlacement value:NO];
}

- (IBAction)newValueType:(id)sender
{
	(void)sender;
	[_canvas createObjectTypeAt:ORMAutomaticPlacement value:YES];
}

/* What the XIB does not say: the tools, the browser around its outline,
 * the delegates of the custom views, the colours, and the panes' sizes. */
- (void)windowDidLoad
{
	[super windowDidLoad];
	[self makeNavigator];
	[self makeLowerTabs];
	[self.browserOutline setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	_browser = [[ORMModelBrowser alloc] initWithOutlineView:self.browserOutline];
	_browser.delegate = self;
	[self.addPopUp setBordered:NO];
	self.canvas.delegate = self;
	self.inspector.delegate = self;
#if defined(__APPLE__)
	/* gnustep-gui recurses without end tiling a scroll view that autohides
	 * its scrollers around a view that resizes with it: NSScrollView -tile
	 * resizes the clip view, which resizes the document view, which
	 * reflects back into -tile. */
	for (NSScrollView *scroll in @[ self.canvasScroll, self.verbalizationScroll, self.inspectorScroll,
	                                [self.browserOutline enclosingScrollView] ]) {
		[scroll setAutohidesScrollers:YES];
	}
#endif
	[self.canvasScroll setBackgroundColor:ORMPaperColor()];
	[self.verbalization setTextContainerInset:NSMakeSize(6, 6)];
	/* Colours set outright: a text view left to choose draws black on
	 * black under some gnustep-gui themes. */
	[self.verbalization setBackgroundColor:ORMPaperColor()];
	[self.verbalization setTextColor:ORMInkColor()];
	[self.factEditor setFont:[NSFont systemFontOfSize:12]];
	[self layoutColumns:self.columnsSplit];
	[self layoutMiddle:self.middleSplit];
	[self editorDidChange];
}

#pragma mark The tabs under the canvas

/* Verbalization, Fact entry and Population (docs/WINDOW.md): a badge each
 * on the bar under the canvas, the page popup on its right. */
- (void)makeLowerTabs
{
	DMTabBar *bar = (DMTabBar *)self.lowerTabBar;
	if ([bar isKindOfClass:[DMTabBar class]]) {
		NSMutableArray *items = [NSMutableArray array];
		NSUInteger tag = 0;
		for (NSArray *page in @[ @[ @"V", @"Verbalization", @0.47, @0.53, @0.64 ], @[ @"F", @"Fact entry", @0.32, @0.60, @0.53 ],
		                         @[ @"P", @"Population", @0.70, @0.48, @0.32 ] ]) {
			DMTabBarItem *item = [DMTabBarItem tabBarItemWithIcon:ORMTabBadge([page objectAtIndex:0],
			                                                                  [[page objectAtIndex:2] doubleValue],
			                                                                  [[page objectAtIndex:3] doubleValue],
			                                                                  [[page objectAtIndex:4] doubleValue])
			                                                  tag:tag++];
			item.toolTip = [page objectAtIndex:1];
			[items addObject:item];
		}
		bar.tabBarItems = items;
		[bar setTarget:self action:@selector(lowerTabChanged:)];
		bar.selectedIndex = 0;
	}
	self.populationView = [[ORMPopulationView alloc] initWithFrame:[self.populationHost bounds]];
	ORMFillHost(self.populationHost, self.populationView);
}

- (void)lowerTabChanged:(id)sender
{
	if (![sender isKindOfClass:[DMTabBar class]]) {
		return;
	}
	[self showLowerTab:(NSInteger)[(DMTabBar *)sender selectedIndex]];
}

/* The tab under the canvas, and its badge selected. */
- (void)showLowerTab:(NSInteger)index
{
	if (index < 0 || index >= [self.lowerTabView numberOfTabViewItems]) {
		return;
	}
	[self.lowerTabView selectTabViewItemAtIndex:index];
	if ([[[self.lowerTabView selectedTabViewItem] identifier] isEqual:@"population"]) {
		/* What it skipped while hidden: the checker's violations. */
		[self.populationView reload];
	}
	DMTabBar *bar = (DMTabBar *)self.lowerTabBar;
	if ([bar isKindOfClass:[DMTabBar class]] && (NSInteger)bar.selectedIndex != index) {
		bar.selectedIndex = (NSUInteger)index;
	}
}

/* The Population tab's element: the one selected, when it has one. */
- (void)showPopulationOf:(NSString *)elementId
{
	self.populationView.editor = [self editor];
	self.populationView.elementId = elementId;
}

#pragma mark Splits

/* The side panes keep their width and the verbalization its height; the
 * diagram takes what is left. GNUstep's own adjusting gives the last pane
 * the remainder, so this lays them out on both platforms. */
- (void)layoutColumns:(NSSplitView *)split
{
	NSArray *panes = [split subviews];
	if ([panes count] != 3) {
		return;
	}
	NSRect bounds = [split bounds];
	double divider = [split dividerThickness];
	double left = MIN(MAX(NSWidth([[panes objectAtIndex:0] frame]), 160), 340);
	double right = MIN(MAX(NSWidth([[panes objectAtIndex:2] frame]), 220), 420);
	double middle = MAX(NSWidth(bounds) - left - right - 2 * divider, 200);
	[[panes objectAtIndex:0] setFrame:NSMakeRect(0, 0, left, NSHeight(bounds))];
	[[panes objectAtIndex:1] setFrame:NSMakeRect(left + divider, 0, middle, NSHeight(bounds))];
	[[panes objectAtIndex:2] setFrame:NSMakeRect(left + middle + 2 * divider, 0, right, NSHeight(bounds))];
}

- (void)layoutMiddle:(NSSplitView *)split
{
	NSArray *panes = [split subviews];
	if ([panes count] != 2) {
		return;
	}
	NSRect bounds = [split bounds];
	double divider = [split dividerThickness];
	double lower = MIN(MAX(NSHeight([[panes objectAtIndex:1] frame]), ORMFactBarHeight + 40), NSHeight(bounds) - 120);
	double upper = MAX(NSHeight(bounds) - lower - divider, 80);
	[[panes objectAtIndex:0] setFrame:NSMakeRect(0, 0, NSWidth(bounds), upper)];
	[[panes objectAtIndex:1] setFrame:NSMakeRect(0, upper + divider, NSWidth(bounds), lower)];
}

- (void)splitView:(NSSplitView *)split resizeSubviewsWithOldSize:(NSSize)oldSize
{
	(void)oldSize;
	if (split == _columnsSplit) {
		[self layoutColumns:split];
	} else {
		[self layoutMiddle:split];
	}
}

#pragma mark The model

- (ORMEditor *)editor
{
	return _document.editor;
}

- (void)editorDidChange
{
	ORMEditor *editor = [self editor];
	__weak ORMWindowController *weakSelf = self;
	editor.changed = ^{
		[weakSelf modelChanged];
	};
	_canvas.editor = editor;
	_inspector.editor = editor;
	_browser.editor = editor;
	_coreData.editor = editor;
	_queries.editor = editor;
	self.searchNavigator.editor = editor;
	[self.searchNavigator reload];
	[self scheduleIssues];
	if (_canvas.diagramId == nil || [editor.model elementWithId:_canvas.diagramId] == nil) {
		_canvas.diagramId = [[editor.model.diagrams firstObject] identifier];
	}
	[self modelChanged];
	[_canvas resize];
}

- (void)modelChanged
{
	ORMModel *model = [self editor].model;
	[self.searchNavigator reload];
	[self scheduleIssues];
	if ([model elementWithId:_canvas.diagramId] == nil) {
		_canvas.diagramId = [[model.diagrams firstObject] identifier];
	}
	[_canvas modelDidChange];
	[_browser reload];
	_inspector.diagramId = _canvas.diagramId;
	if (_inspector.elementId != nil && [model elementWithId:_inspector.elementId] == nil) {
		_inspector.elementId = nil;
	}
	[_inspector modelDidChange];
	[self reloadDiagramPopup];
	[self showVerbalization];
	[_coreData modelDidChange];
	[_queries modelDidChange];
}

- (void)reloadDiagramPopup
{
	[_diagramPopup removeAllItems];
	for (ORMDiagram *diagram in [self editor].model.diagrams) {
		[_diagramPopup addItemWithTitle:diagram.name ?: @"Diagram"];
		[[_diagramPopup lastItem] setRepresentedObject:diagram.identifier];
		if ([diagram.identifier isEqualToString:_canvas.diagramId]) {
			[_diagramPopup selectItem:[_diagramPopup lastItem]];
		}
	}
}

/* The selection's sentences in the verbalization pane, coloured as NORMA
 * colours them, each object type's name a link to it. */
- (void)showVerbalization
{
	ORMVerbalizer *verbalizer = [[ORMVerbalizer alloc] initWithModel:[self editor].model];
	NSArray *elements = [_canvas selectedElements];
	if ([elements count] == 0 && _inspector.elementId != nil) {
		elements = @[ _inspector.elementId ];
	}
	[self showPopulationOf:[elements firstObject]];
	NSMutableArray *sentences = [NSMutableArray array];
	if ([elements count] == 0 && _verbalizesModel) {
		[sentences addObjectsFromArray:[verbalizer sentencesForModel]];
	}
	for (NSString *element in elements) {
		[sentences addObjectsFromArray:[verbalizer sentencesForElement:element]];
	}
	NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
	NSFont *font = [NSFont systemFontOfSize:12];
	NSArray *colors = @[ ORMInkColor(), ORMConstraintColor(ORMDeontic), ORMConstraintColor(ORMAlethic),
	                     [NSColor colorWithCalibratedRed:0.0 green:0.50 blue:0.0 alpha:1.0],
	                     [NSColor colorWithCalibratedRed:0.70 green:0.25 blue:0.0 alpha:1.0], ORMInkColor() ];
	for (ORMVerbalSentence *sentence in sentences) {
		NSMutableString *indent = [NSMutableString string];
		for (NSUInteger i = 0; i < sentence.level; i++) {
			[indent appendString:@"    "];
		}
		[text appendAttributedString:[[NSAttributedString alloc]
			initWithString:indent attributes:@{ NSFontAttributeName: font }]];
		for (ORMVerbalSpan *span in sentence.spans) {
			NSMutableDictionary *attributes = [@{ NSFontAttributeName: font,
			                                      NSForegroundColorAttributeName: [colors objectAtIndex:span.style] }
				mutableCopy];
			if (span.style == ORMVerbalObjectType && span.elementId != nil) {
				[attributes setObject:span.elementId forKey:NSLinkAttributeName];
			}
			[text appendAttributedString:[[NSAttributedString alloc] initWithString:span.text attributes:attributes]];
		}
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
		                                                             attributes:@{ NSFontAttributeName: font }]];
	}
	[[_verbalization textStorage] setAttributedString:text];
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)index
{
	(void)textView;
	(void)index;
	NSString *elementId = [link isKindOfClass:[NSURL class]] ? [(NSURL *)link absoluteString] : [link description];
	[self showElement:elementId];
	return YES;
}

/* Shows the element: selected on the diagram when it is there, in the
 * inspector and verbalization in any case. */
- (void)showElement:(NSString *)elementId
{
	[_canvas selectElements:@[ elementId ]];
	_inspector.elementId = elementId;
	[self showVerbalization];
	[_browser reveal:elementId];
}

- (void)say:(NSString *)message
{
	[_status setStringValue:message ?: @""];
}

#pragma mark Delegates

- (void)canvasSelectionDidChange:(ORMCanvasView *)canvas
{
	/* The Queries window building from the diagram: a role box clicked
	 * extends the query; an object type, with no query yet, starts one. */
	if (_queries != nil && [[_queries window] isVisible] && _queries.buildsFromDiagram) {
		NSString *roleId = canvas.clickedRole;
		ORMRole *role = roleId != nil ? [[self editor].model elementWithId:roleId] : nil;
		if ([role isKindOfClass:[ORMRole class]]) {
			[_queries followRole:role];
		} else if (_queries.queryId == nil && [[canvas selectedElements] count] == 1) {
			id element = [[self editor].model elementWithId:[[canvas selectedElements] firstObject]];
			if ([element isKindOfClass:[ORMObjectType class]]) {
				[_queries addQueryFrom:[element identifier]];
			}
		}
	}
	NSArray *elements = [canvas selectedElements];
	_inspector.elementId = [elements firstObject];
	[self showVerbalization];
	if ([elements count] > 0) {
		[_browser reveal:[elements firstObject]];
	}
}

- (void)canvas:(ORMCanvasView *)canvas say:(NSString *)message
{
	(void)canvas;
	[self say:message];
}

- (void)canvasToolDidChange:(ORMCanvasView *)canvas
{
	[self.insertPalette showTool:canvas.tool];
}

- (void)inspector:(ORMInspectorView *)inspector say:(NSString *)message
{
	(void)inspector;
	[self say:message];
}

- (void)browser:(ORMModelBrowser *)browser didSelect:(NSString *)elementId
{
	(void)browser;
	id element = [[self editor].model elementWithId:elementId];
	if ([element isKindOfClass:[ORMDiagram class]]) {
		[self openDiagram:elementId];
		return;
	}
	[_canvas selectElements:@[ elementId ]];
	_inspector.elementId = elementId;
	[self showVerbalization];
}

- (void)browser:(ORMModelBrowser *)browser openDiagram:(NSString *)diagramId
{
	(void)browser;
	[self openDiagram:diagramId];
}

- (void)openDiagram:(NSString *)diagramId
{
	_canvas.diagramId = diagramId;
	_inspector.diagramId = diagramId;
	_inspector.elementId = nil;
	[self reloadDiagramPopup];
	[self showVerbalization];
}

#pragma mark Actions

- (void)zoomCanvasIn:(id)sender
{
	[_canvas zoomIn:sender];
}

- (void)zoomCanvasOut:(id)sender
{
	[_canvas zoomOut:sender];
}

- (BOOL)addFactFromEditor
{
	NSString *text = [_factEditor stringValue];
	if ([[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
		return NO;
	}
	/* A fact type as the Fact Editor takes it, or a constraint as the
	 * verbalizer says it; what either names that the model lacks is made. */
	NSString *reason = nil;
	NSArray *made = [[[ORMSentenceEditor alloc] initWithEditor:[self editor]] addFromSentence:text onDiagram:_canvas.diagramId at:ORMAutomaticPlacement
	                                         reason:&reason];
	if (made == nil) {
		NSBeep();
		[self say:reason];
		return NO;
	}
	[_factEditor setStringValue:@""];
	ORMModel *model = [self editor].model;
	NSString *shown = nil;
	BOOL constraint = NO;
	for (NSString *identifier in made) {
		id element = [model elementWithId:identifier];
		if ([element isKindOfClass:[ORMConstraint class]]) {
			constraint = YES;
		}
		if (shown == nil && [element isKindOfClass:[ORMFactType class]]) {
			shown = identifier;
		}
	}
	shown = shown ?: [made lastObject];
	if (shown != nil) {
		[self showElement:shown];
	}
	[self say:[made count] == 0 ? @"The model says that already."
	          : constraint ? @"Added. The verbalization below says it back."
	                       : @"Added. Select a role and press U for uniqueness, M for mandatory."];
	return YES;
}

- (void)factEditorReturn:(id)sender
{
	(void)sender;
	[self addFactFromEditor];
}

- (IBAction)focusFactEditor:(id)sender
{
	(void)sender;
	[self showLowerTab:1];
	[[self window] makeFirstResponder:_factEditor];
}

- (IBAction)chooseDiagram:(id)sender
{
	(void)sender;
	NSString *diagramId = [[_diagramPopup selectedItem] representedObject];
	if (diagramId != nil) {
		[self openDiagram:diagramId];
	}
}

- (IBAction)newDiagram:(id)sender
{
	(void)sender;
	NSString *diagram = [[self editor].diagramEditor addDiagramNamed:nil];
	[self openDiagram:diagram];
	[self say:@"Show elements on it from the browser with Diagram ▸ Show Selection on Diagram."];
}

- (IBAction)renameDiagram:(id)sender
{
	(void)sender;
	[_canvas clearSelection];
	_inspector.elementId = nil;
	[self say:@"Rename the diagram in the inspector."];
}

- (IBAction)deleteDiagram:(id)sender
{
	(void)sender;
	if ([[self editor].model.diagrams count] <= 1) {
		NSBeep();
		[self say:@"A model keeps at least one diagram."];
		return;
	}
	[[self editor].elementEditor deleteElements:@[ _canvas.diagramId ]];
}

- (IBAction)arrangeDiagram:(id)sender
{
	(void)sender;
	[[self editor].diagramEditor arrangeDiagram:_canvas.diagramId];
}

/* The elements picked: on the canvas, or else in the inspector (from the
 * browser). */
- (NSArray<NSString *> *)pickedElements
{
	NSArray *elements = [_canvas selectedElements];
	if ([elements count] == 0 && _inspector.elementId != nil) {
		elements = @[ _inspector.elementId ];
	}
	return elements;
}

- (IBAction)showOnDiagram:(id)sender
{
	(void)sender;
	NSArray *elements = [self pickedElements];
	ORMEditor *editor = [self editor];
	[editor group:@"Show on Diagram" with:^{
		for (NSString *element in elements) {
			id item = [editor.model elementWithId:element];
			if ([item isKindOfClass:[ORMFactType class]]) {
				for (ORMRole *role in [(ORMFactType *)item visibleRoles]) {
					[editor.diagramEditor placeElement:role.player.identifier onDiagram:self->_canvas.diagramId at:ORMAutomaticPlacement];
				}
			}
			[editor.diagramEditor placeElement:element onDiagram:self->_canvas.diagramId at:ORMAutomaticPlacement];
		}
	}];
	[_canvas selectElements:elements];
}

- (IBAction)showRelated:(id)sender
{
	(void)sender;
	ORMEditor *editor = [self editor];
	NSString *diagram = _canvas.diagramId;
	NSArray *elements = [self pickedElements];
	[editor group:@"Show Related" with:^{
		for (NSString *element in elements) {
			ORMObjectType *type = [editor.model elementWithId:element];
			if (![type isKindOfClass:[ORMObjectType class]]) {
				continue;
			}
			for (ORMRole *role in type.playedRoles) {
				if (role.factType.kind != ORMFactTypeOrdinary) {
					continue;
				}
				for (ORMRole *other in [role.factType visibleRoles]) {
					[editor.diagramEditor placeElement:other.player.identifier onDiagram:diagram at:ORMAutomaticPlacement];
				}
				[editor.diagramEditor placeElement:role.factType.identifier onDiagram:diagram at:ORMAutomaticPlacement];
			}
			for (ORMObjectType *related in [type.supertypes arrayByAddingObjectsFromArray:type.subtypes]) {
				[editor.diagramEditor placeElement:related.identifier onDiagram:diagram at:ORMAutomaticPlacement];
			}
		}
	}];
}

- (NSString *)selectedFactType
{
	for (NSString *element in [self pickedElements]) {
		id item = [[self editor].model elementWithId:element];
		if ([item isKindOfClass:[ORMRole class]]) {
			item = [(ORMRole *)item factType];
		}
		if ([item isKindOfClass:[ORMFactType class]]) {
			return [item identifier];
		}
	}
	return nil;
}

- (IBAction)objectifyFactType:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	if ([[self editor].factTypeEditor objectifyFactType:[self selectedFactType] named:nil reason:&reason] == nil) {
		NSBeep();
		[self say:reason];
	}
}

- (IBAction)unobjectifyFactType:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	if (![[self editor].factTypeEditor unobjectifyFactType:[self selectedFactType] reason:&reason]) {
		NSBeep();
		[self say:reason];
	}
}

- (IBAction)verbalizeModel:(id)sender
{
	(void)sender;
	_verbalizesModel = !_verbalizesModel;
	[_canvas clearSelection];
	_inspector.elementId = nil;
	[self showVerbalization];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	SEL action = [item action];
	if (action == @selector(objectifyFactType:) || action == @selector(unobjectifyFactType:)) {
		ORMFactType *fact = [[self editor].model elementWithId:[self selectedFactType]];
		return fact != nil && (action == @selector(objectifyFactType:)) == (fact.objectifyingType == nil);
	}
	if (action == @selector(showOnDiagram:) || action == @selector(showRelated:)) {
		return [[self pickedElements] count] > 0;
	}
	if (action == @selector(verbalizeModel:)) {
		[item setState:_verbalizesModel ? NSControlStateValueOn : NSControlStateValueOff];
	}
	return YES;
}

#pragma mark Exporting

- (void)save:(NSData *)data suggesting:(NSString *)name type:(NSString *)type
{
	if (data == nil) {
		NSBeep();
		return;
	}
	NSSavePanel *panel = [NSSavePanel savePanel];
	[panel setAllowedFileTypes:@[ type ]];
	[panel setNameFieldStringValue:[name stringByAppendingPathExtension:type]];
	if ([panel runModal] == NSModalResponseOK) {
		NSError *error = nil;
		if (![data writeToURL:[panel URL] options:NSDataWritingAtomic error:&error]) {
			[self presentError:error];
		}
	}
}

- (NSString *)diagramName
{
	return [[_canvas diagram] name] ?: @"Diagram";
}

- (IBAction)exportDiagramAsPDF:(id)sender
{
	(void)sender;
	[self save:[_canvas PDFData] suggesting:[self diagramName] type:@"pdf"];
}

- (IBAction)exportDiagramAsPNG:(id)sender
{
	(void)sender;
	[self save:[_canvas PNGDataAtScale:3.0] suggesting:[self diagramName] type:@"png"];
}

- (IBAction)exportVerbalization:(id)sender
{
	(void)sender;
	ORMModel *model = [self editor].model;
	NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:model] sentencesForModel];
	NSString *html = [ORMVerbalizer HTMLOfSentences:sentences title:model.name];
	[self save:[html dataUsingEncoding:NSUTF8StringEncoding] suggesting:model.name ?: @"Model" type:@"html"];
}

- (void)printDocument:(id)sender
{
	(void)sender;
	NSPrintOperation *operation = [NSPrintOperation printOperationWithView:_canvas];
	[operation runOperation];
}

#pragma mark Core Data

- (ORMCoreDataController *)coreDataController
{
	if (_coreData == nil) {
		_coreData = [[ORMCoreDataController alloc] initWithEditor:[self editor] documentURL:[_document fileURL]];
	}
	_coreData.documentURL = [_document fileURL];
	return _coreData;
}

- (IBAction)showCoreDataMappings:(id)sender
{
	(void)sender;
	[[self coreDataController] showWindow:self];
}

- (IBAction)synchronizeCoreData:(id)sender
{
	(void)sender;
	ORMCoreDataController *controller = [self coreDataController];
	[controller showWindow:self];
	[controller synchronize:self];
}

#pragma mark Queries

- (ORMQueryController *)queryController
{
	if (_queries == nil) {
		_queries = [[ORMQueryController alloc] initWithEditor:[self editor]];
	}
	return _queries;
}

- (IBAction)showQueries:(id)sender
{
	(void)sender;
	[[self queryController] showWindow:self];
}

- (IBAction)newQueryFromSelection:(id)sender
{
	(void)sender;
	ORMObjectType *type = nil;
	for (NSString *element in [_canvas selectedElements]) {
		id found = [[self editor].model elementWithId:element];
		if ([found isKindOfClass:[ORMShape class]]) {
			found = [(ORMShape *)found subject];
		}
		if ([found isKindOfClass:[ORMObjectType class]]) {
			type = found;
			break;
		}
	}
	if (type == nil) {
		NSBeep();
		return;
	}
	ORMQueryController *controller = [self queryController];
	[controller addQueryFrom:type.identifier];
	[controller showWindow:self];
}

/* The sample population made up, and the queries shown to run on it. */
- (IBAction)makeUpPopulation:(id)sender
{
	ORMQueryController *controller = [self queryController];
	[controller makeUpPopulation:sender];
	[controller showWindow:self];
	[self say:@"A sample population: the Queries window's Results tab runs each query on it."];
}

- (IBAction)importCoreData:(id)sender
{
	(void)sender;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowedFileTypes:@[ @"xcdatamodeld", @"xcdatamodel" ]];
	/* A package on a Mac, a directory elsewhere. */
	[panel setCanChooseDirectories:YES];
	[panel setCanChooseFiles:YES];
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	NSString *path = [[panel URL] path];
	NSString *reason = nil;
	ORMCDModel *model = [ORMCDModel modelAtPath:path reason:&reason];
	ORMCoreDataController *controller = [self coreDataController];
	NSSet *diagrams = [NSSet setWithArray:[[self editor].model.diagrams valueForKey:@"identifier"]];
	BOOL onlyEmpty = [diagrams count] == 1 && [[[[self editor].model.diagrams firstObject] allShapes] count] == 0;
	NSArray *notes = nil;
	NSString *mapping = model != nil ? [[[ORMCoreDataImporter alloc] initWithEditor:[self editor]] importCoreDataModel:model
	                                                                 path:[controller pathRelativeToDocument:path]
	                                                                notes:&notes
	                                                               reason:&reason]
	                                 : nil;
	if (mapping == nil) {
		NSBeep();
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"The Core Data model cannot be imported."];
		[alert setInformativeText:reason ?: @""];
		[alert runModal];
		return;
	}
	for (ORMDiagram *diagram in [self editor].model.diagrams) {
		if (onlyEmpty || ![diagrams containsObject:diagram.identifier]) {
			[self openDiagram:diagram.identifier];
			break;
		}
	}
	controller.mappingId = mapping;
	[controller modelDidChange];
	[controller showWindow:self];
	[controller say:[notes count] > 0 ? [notes componentsJoinedByString:@" "]
	                                  : @"Imported: everything the Core Data model says, ORM says."];
}

@end
