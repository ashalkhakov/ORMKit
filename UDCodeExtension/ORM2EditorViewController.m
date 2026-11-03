/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORM2EditorViewController.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "ORMModelViewController.h"
#import "ORM2TextDiff.h"
#import "ORMPane.h"

/* The model's issues, among the document's diagnostics. */
static UDDiagnosticSource const ORM2IssueSource = @"orm2";

/* The tab's view (ORM2Editor.xib): its controller after it in the chain,
 * wherever UDCode puts it, so the Editor menu's items and Undo reach the
 * tab. AppKit puts a view controller there by itself (since 10.10),
 * gnustep-gui does not; and a view put in another is given its superview
 * as the next responder again. */
@interface ORM2EditorView : NSView
@property (nonatomic, weak) IBOutlet NSResponder *controller;
@end

@implementation ORM2EditorView

- (void)setNextResponder:(NSResponder *)responder
{
	NSResponder *controller = self.controller;
	if (controller == nil || responder == controller) {
		[super setNextResponder:responder];
		return;
	}
	[controller setNextResponder:responder];
	[super setNextResponder:controller];
}

@end

@interface ORM2EditorViewController ()
@property (nonatomic, weak) IBOutlet NSView *problemView;
@property (nonatomic, weak) IBOutlet NSTextField *problemLabel;
@property (nonatomic, readwrite, strong) ORMModelViewController *modelController;
@property (nonatomic, readwrite, copy) NSString *problem;
@end

@implementation ORM2EditorViewController
{
	__weak id<UDWorkbench> _workbench;
	/* The text being read (what the editor reports then is no change of
	 * the user's), or written (what the text model reports then is the
	 * editor's own). */
	BOOL _reading;
	BOOL _writing;
	/* Each issue's element, by its diagnostic's line and message. */
	NSMutableDictionary<NSString *, NSString *> *_issueElements;
}

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench
{
	if ((self = [super initWithNibName:@"ORM2Editor" bundle:[NSBundle bundleForClass:[ORM2EditorViewController class]]])) {
		_document = document;
		_workbench = workbench;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textDidChange:)
		                                             name:UDTextModelDidChangeNotification object:document.textModel];
		[self read];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)loadView
{
	[super loadView];
	[self show];
}

#pragma mark Reading

/* The text as a model, with no undo of its own (the text's is the undo); a
 * model NORMA saved without a diagram given one to draw on, as ORMDocument
 * gives it, written with the next change. nil, and why, when it is none. */
- (ORMEditor *)editorOfText:(NSString *)text problem:(NSString **)problem
{
	NSString *reason = nil;
	NSXMLDocument *xml = ORMParseDocument([text dataUsingEncoding:NSUTF8StringEncoding], &reason);
	ORMModel *model = xml != nil ? [ORMModel modelOfDocument:xml reason:&reason] : nil;
	if (model == nil) {
		*problem = [NSString stringWithFormat:@"This is not an ORM model that can be shown: %@", reason ?: @"it cannot be read."];
		return nil;
	}
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:xml undoManager:nil];
	if ([model.diagrams count] == 0 && [xml rootElement] != model.modelElement) {
		NSString *diagram = [editor.diagramEditor addDiagramNamed:model.name];
		for (ORMObjectType *type in [editor.model visibleObjectTypes]) {
			[editor.diagramEditor placeElement:type.identifier onDiagram:diagram at:ORMAutomaticPlacement];
		}
		for (ORMFactType *fact in [editor.model ordinaryFactTypes]) {
			[editor.diagramEditor placeElement:fact.identifier onDiagram:diagram at:ORMAutomaticPlacement];
		}
		[editor.diagramEditor arrangeDiagram:diagram];
	}
	return editor;
}

/* The text read into the editor: the one there given the new model, or
 * one made for it; or, when it is no model, why. */
- (void)read
{
	NSString *problem = nil;
	_reading = YES;
	ORMEditor *editor = [self editorOfText:[_document.textModel getValue] problem:&problem];
	if (editor == nil) {
		self.problem = problem;
	} else if (_modelController == nil) {
		self.problem = nil;
		self.modelController = [[ORMModelViewController alloc] initHostedWithEditor:editor];
		_modelController.documentURL = _document.fileURL;
		__weak ORM2EditorViewController *weakSelf = self;
		_modelController.modelChangeHandler = ^{
			[weakSelf write];
			[weakSelf scheduleIssues];
		};
		_modelController.showLowerHandler = ^(NSViewController *pane) {
			ORM2EditorViewController *strongSelf = weakSelf;
			[strongSelf->_workbench showEditorBottomPane:pane];
		};
		_modelController.insertChosenHandler = ^{
			ORM2EditorViewController *strongSelf = weakSelf;
			[strongSelf->_workbench closeLibrary];
		};
	} else {
		self.problem = nil;
		_modelController.documentURL = _document.fileURL;
		_modelController.editor = editor;
	}
	_reading = NO;
	[self show];
	[self scheduleIssues];
}

/* The text changed, not by the editor: read again, at once while the tab
 * shows (an undo), a moment later while it does not (typed in a tab of its
 * text, each key would be a read of the whole model); the diagram,
 * selection and inspected element kept where they still are. */
- (void)textDidChange:(NSNotification *)notification
{
	(void)notification;
	if (_writing) {
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(readAgain) object:nil];
	if ([self isViewLoaded] && [[self view] window] != nil) {
		[self readAgain];
	} else {
		[self performSelector:@selector(readAgain) withObject:nil afterDelay:0.3];
	}
}

- (void)readAgain
{
	ORMModelViewController *controller = _modelController;
	NSString *diagram = controller.canvas.diagramId;
	NSArray *selected = [controller.canvas selectedElements] ?: @[];
	NSString *inspected = controller.inspector.elementId;
	[self read];
	if (controller == nil || controller != _modelController || self.problem != nil) {
		return;
	}
	ORMModel *model = controller.editor.model;
	if (diagram != nil && [model elementWithId:diagram] != nil) {
		[controller openDiagram:diagram];
	}
	NSMutableArray *kept = [NSMutableArray array];
	for (NSString *element in selected) {
		if ([model elementWithId:element] != nil) {
			[kept addObject:element];
		}
	}
	if ([kept count] > 0) {
		[controller.canvas selectElements:kept];
	} else if (inspected != nil && [model elementWithId:inspected] != nil) {
		controller.inspector.elementId = inspected;
	}
}

#pragma mark Writing

/* The model written as the text: an edit for each run of lines that
 * differs (ORM2LineChanges), made at once, so undone as one, and a diff of
 * the file says what changed. */
- (void)write
{
	ORMEditor *editor = _modelController.editor;
	if (_reading || editor == nil) {
		return;
	}
	NSString *text = [[NSString alloc] initWithData:[editor dataForSaving] encoding:NSUTF8StringEncoding];
	UDTextModel *model = _document.textModel;
	NSString *old = [model getValue];
	/* A byte order mark the text as read did not show. */
	if ([text hasPrefix:@"\uFEFF"] && ![old hasPrefix:@"\uFEFF"]) {
		text = [text substringFromIndex:1];
	}
	if (text == nil || [text isEqualToString:old]) {
		return;
	}
	NSMutableArray *edits = [NSMutableArray array];
	for (ORM2TextChange *change in ORM2LineChanges(old, text)) {
		UDPosition from = [model getPositionAt:(NSInteger)change.offset];
		UDPosition to = [model getPositionAt:(NSInteger)(change.offset + change.length)];
		UDRange range = { from.line, from.column, to.line, to.column };
		[edits addObject:[[UDTextModelEdit alloc] initWithRange:range text:change.text]];
	}
	_writing = YES;
	[model applyEdits:edits];
	_writing = NO;
}

#pragma mark Showing

/* The editor filling the tab, after its view in the chain; or why there is
 * none. */
- (void)show
{
	if (![self isViewLoaded]) {
		return;
	}
	NSView *view = [_modelController view];
	if (self.problem == nil && view != nil) {
		if ([view superview] != [self view]) {
			[view setFrame:[[self view] bounds]];
			[view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
			[[self view] addSubview:view positioned:NSWindowBelow relativeTo:nil];
			if ([view nextResponder] != _modelController) {
				[_modelController setNextResponder:[view nextResponder]];
				[view setNextResponder:_modelController];
			}
		}
		[view setHidden:NO];
		[self.problemView setHidden:YES];
	} else {
		[view setHidden:YES];
		[self.problemLabel setStringValue:self.problem ?: @""];
		[self.problemView setHidden:NO];
	}
}

#pragma mark Issues

/* The model's issues found again a moment after it changes (a burst of
 * changes finds them once), as the designer's Issues pane does. */
- (void)scheduleIssues
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(findIssues) object:nil];
	[self performSelector:@selector(findIssues) withObject:nil afterDelay:0.5];
}

/* The issues as the document's diagnostics: each at the line its element
 * is written on (its id's), the model's first line when it has none; none
 * while the text is no model. */
- (void)findIssues
{
	ORMEditor *editor = _modelController.editor;
	NSMutableArray *items = [NSMutableArray array];
	_issueElements = [NSMutableDictionary dictionary];
	if (editor != nil && self.problem == nil) {
		NSString *text = [_document.textModel getValue];
		ORMCoreDataMapping *mapping = [editor.model.coreDataMappings firstObject];
		for (ORMIssue *issue in [[[ORMIssueFinder alloc] initWithModel:editor.model mapping:mapping] issues]) {
			NSInteger line = 1;
			if (issue.elementId != nil) {
				NSRange at = [text rangeOfString:[NSString stringWithFormat:@"id=\"%@\"", issue.elementId]];
				if (at.location != NSNotFound) {
					line = [_document.textModel getPositionAt:(NSInteger)at.location].line;
				}
			}
			UDDiagnosticSeverity severity = issue.severity == ORMIssueError ? UDDiagnosticSeverityError
			                              : issue.severity == ORMIssueWarning ? UDDiagnosticSeverityWarning
			                                                                  : UDDiagnosticSeverityInfo;
			NSString *message = [issue.area length] > 0 ? [NSString stringWithFormat:@"%@: %@", issue.area, issue.text] : issue.text;
			[items addObject:[[UDDiagnosticItem alloc] initWithLine:line column:0 message:message severity:severity
			                                                 source:ORM2IssueSource]];
			if (issue.elementId != nil) {
				[_issueElements setObject:issue.elementId forKey:[NSString stringWithFormat:@"%ld %@", (long)line, message]];
			}
		}
	}
	[_document.diagnosticStore setDiagnostics:items forSource:ORM2IssueSource];
}

#pragma mark The window's panes (UDEditorPanes)

- (NSArray<NSViewController *> *)inspectorViewControllers
{
	NSViewController *inspector = _modelController.inspectorController;
	return inspector != nil ? @[ inspector ] : @[];
}

/* Element's tab: Xcode's Attributes inspector's sliders, drawn on GNUstep,
   which has no SF Symbols. */
- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController
{
	if (viewController != _modelController.inspectorController) {
		return nil;
	}
#ifndef GNUSTEP
	if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
		return [NSImage imageWithSystemSymbolName:@"slider.horizontal.3" accessibilityDescription:viewController.title];
	}
#endif
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
	[image lockFocus];
	[[NSColor colorWithCalibratedWhite:0.25 alpha:1] set];
	CGFloat knobs[] = { 10.5, 5.5, 8.5 };
	for (NSInteger row = 0; row < 3; row++) {
		CGFloat y = 3.5 + 4.5 * row;
		NSBezierPath *track = [NSBezierPath bezierPath];
		[track moveToPoint:NSMakePoint(1.5, y)];
		[track lineToPoint:NSMakePoint(14.5, y)];
		[track setLineWidth:1.2];
		[track setLineCapStyle:NSRoundLineCapStyle];
		[track stroke];
		[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(knobs[row] - 1.8, y - 1.8, 3.6, 3.6)] fill];
	}
	[image unlockFocus];
	return image;
}

- (NSArray<NSViewController *> *)bottomAreaViewControllers
{
	return _modelController.lowerControllers ?: @[];
}

/* Their badges, as the designer's tab bar has them. */
- (NSImage *)imageForBottomAreaViewController:(NSViewController *)viewController
{
	NSUInteger index = [_modelController.lowerControllers indexOfObject:viewController];
	NSArray *badges = @[ @[ @"V", @0.47, @0.53, @0.64 ], @[ @"F", @0.32, @0.60, @0.53 ], @[ @"P", @0.70, @0.48, @0.32 ] ];
	if (index == NSNotFound || index >= [badges count]) {
		return nil;
	}
	NSArray *badge = [badges objectAtIndex:index];
	NSImage *image = ORMTabBadge([badge objectAtIndex:0], [[badge objectAtIndex:1] doubleValue], [[badge objectAtIndex:2] doubleValue],
	                             [[badge objectAtIndex:3] doubleValue]);
	[image setSize:NSMakeSize(16, 16)];
	return image;
}

- (NSViewController *)libraryViewController
{
	return _modelController.insertController;
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic
{
	NSString *element = [_issueElements objectForKey:[NSString stringWithFormat:@"%ld %@", (long)diagnostic.line, diagnostic.message]];
	if (element != nil) {
		[_modelController showElementOrQuery:element];
	}
}

#pragma mark Actions

- (IBAction)undo:(id)sender
{
	(void)sender;
	[_document.textModel.undoManager undo];
}

- (IBAction)redo:(id)sender
{
	(void)sender;
	[_document.textModel.undoManager redo];
}

- (IBAction)showAsText:(id)sender
{
	(void)sender;
	[_workbench showDocumentAsText:_document];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	SEL action = [item action];
	if (sel_isEqual(action, @selector(undo:))) {
		return _document.textModel.undoManager.canUndo;
	}
	if (sel_isEqual(action, @selector(redo:))) {
		return _document.textModel.undoManager.canRedo;
	}
	return YES;
}

@end
