/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORM2FlowEditorViewController.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "ORMFlowDocument.h"
#import "ORMFlowWindowController.h"
#import "ORM2TextDiff.h"
#import "ORMFlowCanvasView.h"

/* What is wrong of the flow, among the document's diagnostics. */
static UDDiagnosticSource const ORM2FlowIssueSource = @"ormflow";

/* The tab's view (ORM2FlowEditor.xib): its controller after it in the
 * chain, wherever UDCode puts it, as ORM2EditorView's is. */
@interface ORM2FlowEditorView : NSView
@property (nonatomic, weak) IBOutlet NSResponder *controller;
@end

@implementation ORM2FlowEditorView

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

@interface ORM2FlowEditorViewController ()
@property (nonatomic, weak) IBOutlet NSView *problemView;
@property (nonatomic, weak) IBOutlet NSTextField *problemLabel;
@property (nonatomic, readwrite, strong) ORMFlowWindowController *flowController;
@property (nonatomic, readwrite, copy) NSString *problem;
@end

@implementation ORM2FlowEditorViewController
{
	__weak id<UDWorkbench> _workbench;
	/* The designer's view, out of its window, in the tab. */
	NSView *_flowView;
	/* The text being read (what the editor reports then is no change of
	 * the user's), or written (what the text model reports then is the
	 * editor's own). */
	BOOL _reading;
	BOOL _writing;
	/* Each problem's screen, by its diagnostic's line and message. */
	NSMutableDictionary<NSString *, NSString *> *_issueScreens;
}

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench
{
	if ((self = [super initWithNibName:@"ORM2FlowEditor" bundle:[NSBundle bundleForClass:[ORM2FlowEditorViewController class]]])) {
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

/* The text read: into the designer there, or one made for it with the
 * model the flow names, read from beside the file; or, when it is no flow
 * or its model cannot be read, why. */
- (void)read
{
	NSError *error = nil;
	ORMFlow *flow = [ORMFlow flowWithData:[[_document.textModel getValue] dataUsingEncoding:NSUTF8StringEncoding] error:&error];
	if (flow == nil) {
		self.problem = [NSString stringWithFormat:@"This is not a flow that can be shown: %@",
		                                          error.localizedDescription ?: @"it cannot be read."];
		[self show];
		return;
	}
	ORMFlowEditor *editor = _flowController.editor;
	_reading = YES;
	if (editor != nil && [editor.flow.modelPath isEqualToString:flow.modelPath]) {
		[editor readData:[flow XMLData] error:NULL];
		self.problem = nil;
	} else {
		NSString *reason = nil;
		NSURL *beside = [_document.fileURL URLByDeletingLastPathComponent];
		NSURL *modelURL = [flow.modelPath length] > 0 && beside != nil ? [NSURL fileURLWithPath:flow.modelPath relativeToURL:beside] : nil;
		ORMModel *model = modelURL != nil ? ORMFlowModelAt(modelURL, &reason) : nil;
		if (model == nil) {
			self.problem = [NSString stringWithFormat:@"The flow's model, %@, cannot be read: %@", flow.modelPath ?: @"none named",
			                                          reason ?: @"the flow names none."];
		} else {
			self.problem = nil;
			[self host:[[ORMFlowEditor alloc] initWithFlow:flow model:model undoManager:nil]];
		}
	}
	_reading = NO;
	[self show];
	[self findIssues];
}

/* The designer over the editor, its view the tab's, each change of its
 * written back to the text. */
- (void)host:(ORMFlowEditor *)editor
{
	if (_flowController != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:ORMFlowEditorDidChangeNotification object:_flowController.editor];
		[_flowView removeFromSuperview];
	}
	self.flowController = [[ORMFlowWindowController alloc] initWithEditor:editor];
	_flowView = [_flowController hostedView];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(flowDidChange:)
	                                             name:ORMFlowEditorDidChangeNotification object:editor];
}

/* The text changed, not by the designer: read again, at once while the
 * tab shows (an undo), a moment later while it does not. */
- (void)textDidChange:(NSNotification *)notification
{
	(void)notification;
	if (_writing) {
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(read) object:nil];
	if ([self isViewLoaded] && [[self view] window] != nil) {
		[self read];
	} else {
		[self performSelector:@selector(read) withObject:nil afterDelay:0.3];
	}
}

#pragma mark Writing

- (void)flowDidChange:(NSNotification *)notification
{
	(void)notification;
	[self write];
	[self findIssues];
}

#pragma mark Issues

/* What is wrong of the flow as the document's diagnostics: each at the
 * line of the screen it names (its id's), the flow's first line when it
 * names none; none while the text is no flow. */
- (void)findIssues
{
	ORMFlowEditor *editor = _flowController.editor;
	NSMutableArray *items = [NSMutableArray array];
	_issueScreens = [NSMutableDictionary dictionary];
	if (editor != nil && self.problem == nil) {
		NSString *text = [_document.textModel getValue];
		for (NSString *message in [editor problems]) {
			NSInteger line = 1;
			NSString *screenId = nil;
			for (ORMFlowScreen *screen in editor.flow.screens) {
				NSString *name = screen.name ?: screen.identifier;
				if ([name length] > 0 && [message rangeOfString:name].location != NSNotFound) {
					screenId = screen.identifier;
					break;
				}
			}
			if (screenId != nil) {
				NSRange at = [text rangeOfString:[NSString stringWithFormat:@"id=\"%@\"", screenId]];
				if (at.location != NSNotFound) {
					line = [_document.textModel getPositionAt:(NSInteger)at.location].line;
				}
				[_issueScreens setObject:screenId forKey:[NSString stringWithFormat:@"%ld %@", (long)line, message]];
			}
			[items addObject:[[UDDiagnosticItem alloc] initWithLine:line column:0 message:message severity:UDDiagnosticSeverityError
			                                                 source:ORM2FlowIssueSource]];
		}
	}
	[_document.diagnosticStore setDiagnostics:items forSource:ORM2FlowIssueSource];
}

/* A problem chosen in the Issues navigator: its screen chosen. */
- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic
{
	NSString *screen = [_issueScreens objectForKey:[NSString stringWithFormat:@"%ld %@", (long)diagnostic.line, diagnostic.message]];
	if (screen != nil) {
		[_flowController.canvas selectScreen:screen];
	}
}

/* The flow written as the text: an edit for each run of lines that
 * differs, made at once, so undone as one. */
- (void)write
{
	ORMFlowEditor *editor = _flowController.editor;
	if (_reading || editor == nil) {
		return;
	}
	NSString *text = [[NSString alloc] initWithData:[editor XMLData] encoding:NSUTF8StringEncoding];
	UDTextModel *model = _document.textModel;
	NSString *old = [model getValue];
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

/* The designer filling the tab; or why there is none. */
- (void)show
{
	if (![self isViewLoaded]) {
		return;
	}
	if (self.problem == nil && _flowView != nil) {
		if ([_flowView superview] != [self view]) {
			[_flowView setFrame:[[self view] bounds]];
			[_flowView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
			[[self view] addSubview:_flowView positioned:NSWindowBelow relativeTo:nil];
			if ([_flowView nextResponder] != _flowController) {
				[_flowController setNextResponder:[_flowView nextResponder]];
				[_flowView setNextResponder:_flowController];
			}
		}
		[_flowView setHidden:NO];
		[self.problemView setHidden:YES];
	} else {
		[_flowView setHidden:YES];
		[self.problemLabel setStringValue:self.problem ?: @""];
		[self.problemView setHidden:NO];
	}
}

#pragma mark Commands

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
