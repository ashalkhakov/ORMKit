/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlowWindowController.h"
#import "ORMFlowPlayController.h"
#import "ORMDocument.h"
#import "ORMWindowController.h"
#import "ORMModelViewController.h"

/* The inspector's actions and kinds, in its pop-ups' order. */
static NSArray<NSString *> *
ORMFlowOns(void)
{
	return @[ ORMFlowOnSubmitDone, ORMFlowOnSubmitError, ORMFlowOnCancel, ORMFlowOnRowChosen, ORMFlowOnTrigger ];
}

static NSArray<NSString *> *
ORMFlowKinds(void)
{
	return @[ ORMFlowKindNavigate, ORMFlowKindOverlay, ORMFlowKindBack, ORMFlowKindClose ];
}

@implementation ORMFlowWindowController {
	NSArray<ORMQuery *> *_placeable;
	NSArray<NSString *> *_problemList;
}

- (instancetype)initWithEditor:(ORMFlowEditor *)editor
{
	if ((self = [super initWithWindowNibName:@"ORMFlowWindow"])) {
		_editor = editor;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(editorDidChange:)
		                                             name:ORMFlowEditorDidChangeNotification object:editor];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)windowNibName
{
	return @"ORMFlowWindow";
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	self.canvas.editor = self.editor;
	self.canvas.flowDelegate = self;
	[self.palette setDoubleAction:@selector(addToFlow:)];
	[self.palette setTarget:self];
	[self flowDidChange];
	/* The whole flow in view as it opens. */
	if ([self.editor.flow.screens count] > 0) {
		[self.canvas zoomToFit:nil];
	}
}

- (NSView *)hostedView
{
	NSWindow *window = [self window];
	/* Never shown: the XIB's window is visible at launch. */
	[window orderOut:nil];
	NSView *content = [window contentView];
	if (content != nil && [content window] == window) {
		[window setContentView:[[NSView alloc] initWithFrame:[content frame]]];
	}
	/* What is wrong of the flow is the host's to show (UDCode's Issues
	 * navigator): under the canvas, only its zoom. */
	NSScrollView *problems = [self.problems enclosingScrollView];
	NSView *pane = [problems superview];
	NSSplitView *split = (NSSplitView *)[pane superview];
	[problems setHidden:YES];
	if ([split isKindOfClass:[NSSplitView class]]) {
		[split setPosition:NSHeight([split bounds]) - 32 - [split dividerThickness] ofDividerAtIndex:0];
	}
	/* The inspector is the host's too: its pane out of the columns. */
	NSView *inspectorPane = [self.inspector superview];
	NSSplitView *columns = (NSSplitView *)[inspectorPane superview];
	if (_hostedInspectorView == nil && [columns isKindOfClass:[NSSplitView class]]) {
		/* The palette keeps its width; the canvas takes the inspector's. */
		CGFloat palette = NSWidth([[[columns subviews] firstObject] frame]);
		[inspectorPane removeFromSuperview];
		[columns adjustSubviews];
		[columns setPosition:palette ofDividerAtIndex:0];
		_hostedInspectorView = inspectorPane;
	}
	return content;
}

- (void)editorDidChange:(NSNotification *)notification
{
	[self flowDidChange];
}

- (void)flowDidChange
{
	_placeable = [[self.editor forms] arrayByAddingObjectsFromArray:[self.editor lists]];
	_problemList = [self.editor problems];
	/* What is selected and gone (undone) is not selected. */
	NSMutableSet *kept = [NSMutableSet set];
	for (NSString *screen in [self.canvas selectedScreens]) {
		if ([self.editor.flow screenWithId:screen] != nil) {
			[kept addObject:[ORMFlowCanvasView itemOfScreen:screen]];
		}
	}
	[[self.canvas selectedTransitions] enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
		if (index < [self.editor.flow.transitions count]) {
			[kept addObject:[ORMFlowCanvasView itemOfTransition:index]];
		}
	}];
	self.canvas.selection = kept;
	[self.canvas reloadData];
	[self.palette reloadData];
	[self.problems reloadData];
	[self showInspector];
}

#pragma mark The palette

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == self.palette) {
		return (NSInteger)[_placeable count];
	}
	if (tableView == self.problems) {
		return (NSInteger)[_problemList count];
	}
	ORMFlowTransition *transition = [self chosenTransition];
	ORMFlowScreen *to = transition.toScreen != nil ? [self.editor.flow screenWithId:transition.toScreen] : nil;
	return (NSInteger)[[self.editor inputsOfScreen:to] count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView == self.palette) {
		ORMQuery *query = [_placeable objectAtIndex:(NSUInteger)row];
		return [NSString stringWithFormat:@"%@ (%@)", query.name, query.kind == ORMQueryForm ? @"form" : @"list"];
	}
	if (tableView == self.problems) {
		return [_problemList objectAtIndex:(NSUInteger)row];
	}
	ORMFlowTransition *transition = [self chosenTransition];
	ORMFlowScreen *to = [self.editor.flow screenWithId:transition.toScreen];
	NSString *input = [[self.editor inputsOfScreen:to] objectAtIndex:(NSUInteger)row];
	if ([[column identifier] isEqualToString:@"input"]) {
		return [self.editor nameOfNode:input inScreen:to];
	}
	for (ORMFlowGive *give in transition.gives) {
		if ([give.nodeId isEqualToString:input]) {
			return give.from;
		}
	}
	return @"";
}

/* What a transition gives an input, typed: "row", "result" or a screen's
 * node; nothing, left to the app. */
- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView != self.gives) {
		return;
	}
	NSUInteger index = [[self.canvas selectedTransitions] firstIndex];
	ORMFlowTransition *transition = [self chosenTransition];
	ORMFlowScreen *to = [self.editor.flow screenWithId:transition.toScreen];
	NSString *input = [[self.editor inputsOfScreen:to] objectAtIndex:(NSUInteger)row];
	NSString *from = [[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSMutableArray *gives = [NSMutableArray array];
	for (ORMFlowGive *give in transition.gives) {
		if (![give.nodeId isEqualToString:input]) {
			[gives addObject:give];
		}
	}
	if ([from length] > 0) {
		ORMFlowGive *give = [[ORMFlowGive alloc] init];
		give.nodeId = input;
		give.from = from;
		[gives addObject:give];
	}
	[self.editor setGives:gives ofTransition:index];
}

/* Where a new screen goes: right of what is there. */
- (NSPoint)freePlace
{
	double right = 40;
	for (ORMFlowScreen *screen in self.editor.flow.screens) {
		right = MAX(right, NSMaxX([self.canvas frameOfScreen:screen]) + 120);
	}
	return NSMakePoint(right, 60);
}

/* The Diagram menu's zoom (ORMModelMenus.xib), wherever the focus is in
 * the flow's window or tab: the canvas's. */
- (IBAction)zoomIn:(id)sender
{
	[self.canvas zoomIn:sender];
}

- (IBAction)zoomOut:(id)sender
{
	[self.canvas zoomOut:sender];
}

- (IBAction)zoomToFit:(id)sender
{
	[self.canvas zoomToFit:sender];
}

- (IBAction)zoomToActualSize:(id)sender
{
	[self.canvas zoomToActualSize:sender];
}

- (IBAction)zoomCanvasIn:(id)sender
{
	[self.canvas zoomIn:sender];
}

- (IBAction)zoomCanvasOut:(id)sender
{
	[self.canvas zoomOut:sender];
}

- (IBAction)zoomCanvasToFit:(id)sender
{
	[self.canvas zoomToFit:sender];
}

- (IBAction)zoomCanvasToActualSize:(id)sender
{
	[self.canvas zoomToActualSize:sender];
}

- (void)flowCanvas:(ORMFlowCanvasView *)canvas openScreen:(NSString *)screenId
{
	ORMFlowScreen *screen = [self.editor.flow screenWithId:screenId];
	NSString *queryId = screen.formId ?: screen.queryId;
	if (queryId == nil) {
		NSBeep();
		return;
	}
	if (self.openQueryHandler != nil) {
		self.openQueryHandler(queryId);
		return;
	}
	/* ORMDesigner: the model beside the flow, as a document of its own. */
	NSURL *flowURL = [[self document] fileURL];
	NSString *modelPath = self.editor.flow.modelPath;
	if (flowURL == nil || [modelPath length] == 0) {
		NSBeep();
		return;
	}
	NSURL *modelURL = [NSURL fileURLWithPath:modelPath relativeToURL:[flowURL URLByDeletingLastPathComponent]];
	[[NSDocumentController sharedDocumentController]
		openDocumentWithContentsOfURL:modelURL
		                      display:YES
		            completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
			    (void)alreadyOpen;
			    if (document == nil) {
				    if (error != nil) {
					    [NSApp presentError:error];
				    }
				    return;
			    }
			    for (NSWindowController *controller in [document windowControllers]) {
				    if ([controller isKindOfClass:[ORMWindowController class]]) {
					    [[(ORMWindowController *)controller modelController] showElementOrQuery:queryId];
				    }
			    }
		    }];
}

- (IBAction)openScreen:(id)sender
{
	NSArray *screens = [self.canvas selectedScreens];
	if ([screens count] != 1) {
		NSBeep();
		return;
	}
	[self flowCanvas:self.canvas openScreen:[screens firstObject]];
}

- (IBAction)play:(id)sender
{
	_player = [[ORMFlowPlayController alloc] initWithFlow:self.editor.flow model:self.editor.model];
	[_player showWindow:sender];
}

- (IBAction)addToFlow:(id)sender
{
	NSInteger row = [self.palette selectedRow] >= 0 ? [self.palette selectedRow] : [self.palette clickedRow];
	if (row < 0 || row >= (NSInteger)[_placeable count]) {
		NSBeep();
		return;
	}
	ORMFlowScreen *screen = [self.editor addScreenForQuery:[_placeable objectAtIndex:(NSUInteger)row] at:[self freePlace]];
	[self.canvas selectScreen:screen.identifier];
	[self.canvas scrollItemToVisible:[ORMFlowCanvasView itemOfScreen:screen.identifier]];
}

#pragma mark The inspector

- (ORMFlowScreen *)chosenScreen
{
	NSArray *screens = [self.canvas selectedScreens];
	return [screens count] == 1 && [[self.canvas selectedTransitions] count] == 0 ? [self.editor.flow screenWithId:[screens firstObject]] : nil;
}

- (ORMFlowTransition *)chosenTransition
{
	NSIndexSet *transitions = [self.canvas selectedTransitions];
	NSUInteger index = [transitions firstIndex];
	return [transitions count] == 1 && [[self.canvas selectedScreens] count] == 0 && index < [self.editor.flow.transitions count]
		? [self.editor.flow.transitions objectAtIndex:index] : nil;
}

- (void)flowCanvasSelectionDidChange:(ORMFlowCanvasView *)canvas
{
	[self showInspector];
}

- (void)showInspector
{
	ORMFlowScreen *screen = [self chosenScreen];
	ORMFlowTransition *transition = [self chosenTransition];
	if (screen != nil) {
		[self.inspector selectTabViewItemWithIdentifier:@"screen"];
		[self.screenName setStringValue:screen.name ?: @""];
		ORMQuery *query = [self.editor queryOfScreen:screen];
		[self.screenShows setStringValue:query != nil ? [NSString stringWithFormat:@"%@, a %@", query.name,
		                                                                             query.kind == ORMQueryForm ? @"form" : @"list"]
		                                              : @"Nothing the model has"];
		NSString *entry = @"";
		for (ORMFlowEntry *each in self.editor.flow.entries) {
			if ([each.screen isEqualToString:screen.identifier]) {
				entry = each.name ?: @"";
			}
		}
		[self.screenEntry setStringValue:entry];
		return;
	}
	if (transition != nil) {
		[self.inspector selectTabViewItemWithIdentifier:@"transition"];
		ORMFlowScreen *from = [self.editor.flow screenWithId:transition.fromScreen];
		[self.transitionFrom setStringValue:[NSString stringWithFormat:@"From %@", from.name ?: transition.fromScreen]];
		NSUInteger on = [ORMFlowOns() indexOfObject:transition.on ?: @""];
		[self.transitionOn selectItemAtIndex:on != NSNotFound ? (NSInteger)on : 0];
		[self.transitionControl setStringValue:transition.control ?: @""];
		NSUInteger kind = [ORMFlowKinds() indexOfObject:transition.kind ?: ORMFlowKindNavigate];
		[self.transitionKind selectItemAtIndex:kind != NSNotFound ? (NSInteger)kind : 0];
		[self.transitionTo removeAllItems];
		for (ORMFlowScreen *each in self.editor.flow.screens) {
			[self.transitionTo addItemWithTitle:each.name ?: each.identifier];
			[[self.transitionTo lastItem] setRepresentedObject:each.identifier];
		}
		NSInteger to = transition.toScreen != nil ? [self.transitionTo indexOfItemWithRepresentedObject:transition.toScreen] : -1;
		[self.transitionTo selectItemAtIndex:to];
		[self.transitionTo setEnabled:transition.toScreen != nil];
		[self.gives reloadData];
		return;
	}
	[self.inspector selectTabViewItemWithIdentifier:@"nothing"];
}

- (IBAction)renameScreen:(id)sender
{
	ORMFlowScreen *screen = [self chosenScreen];
	if (screen != nil) {
		[self.editor renameScreen:screen.identifier to:[self.screenName stringValue]];
	}
}

/* The screen's entry named so; none where it is emptied. */
- (IBAction)setEntry:(id)sender
{
	ORMFlowScreen *screen = [self chosenScreen];
	if (screen == nil) {
		return;
	}
	NSString *name = [[self.screenEntry stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSMutableArray *entries = [NSMutableArray array];
	for (ORMFlowEntry *entry in self.editor.flow.entries) {
		if (![entry.screen isEqualToString:screen.identifier]) {
			[entries addObject:entry];
		}
	}
	if ([name length] > 0) {
		ORMFlowEntry *entry = [[ORMFlowEntry alloc] init];
		entry.name = name;
		entry.screen = screen.identifier;
		[entries addObject:entry];
	}
	[self.editor setEntries:entries];
}

- (IBAction)addCancelBack:(id)sender
{
	ORMFlowScreen *screen = [self chosenScreen];
	if (screen != nil && [self.editor addReturnFrom:screen.identifier on:ORMFlowOnCancel kind:ORMFlowKindBack] != nil) {
		[self.canvas selectTransition:[self.editor.flow.transitions count] - 1];
	}
}

- (IBAction)chooseTransitionOn:(id)sender
{
	NSUInteger index = [[self.canvas selectedTransitions] firstIndex];
	NSInteger on = [self.transitionOn indexOfSelectedItem];
	if ([self chosenTransition] == nil || on < 0) {
		return;
	}
	[self.editor setOn:[ORMFlowOns() objectAtIndex:(NSUInteger)on] control:[self.transitionControl stringValue] ofTransition:index];
}

- (IBAction)chooseTransitionKind:(id)sender
{
	NSUInteger index = [[self.canvas selectedTransitions] firstIndex];
	NSInteger kind = [self.transitionKind indexOfSelectedItem];
	if ([self chosenTransition] == nil || kind < 0) {
		return;
	}
	[self.editor setKind:[ORMFlowKinds() objectAtIndex:(NSUInteger)kind] ofTransition:index];
}

- (IBAction)chooseTransitionTo:(id)sender
{
	NSUInteger index = [[self.canvas selectedTransitions] firstIndex];
	NSString *to = [[self.transitionTo selectedItem] representedObject];
	if ([self chosenTransition] != nil && to != nil) {
		[self.editor setTarget:to ofTransition:index];
	}
}

- (IBAction)delete:(id)sender
{
	[self.canvas delete:sender];
}

@end
