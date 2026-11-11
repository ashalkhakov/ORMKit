/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMWindowController.h"
#import "ORMFlowDocument.h"
#import "ORMDocument.h"
#import "ORMPane.h"

@implementation ORMWindowController
{
	__weak ORMDocument *_document;
}

/* The XIB found in this framework: -initWithWindowNibName: looks in the
 * app's bundle. */
- (instancetype)initWithDocument:(ORMDocument *)document
{
	NSNib *nib = [[NSNib alloc] initWithNibNamed:@"ORMDocumentWindow" bundle:ORMDesignerKitBundle()];
	NSArray *objects = nil;
	if ((self = [super initWithWindow:nil])) {
		_document = document;
		if (![nib instantiateWithOwner:self topLevelObjects:&objects]) {
			return nil;
		}
		_modelController = [[ORMModelViewController alloc] initWithEditor:document.editor];
		_modelController.documentURL = [document fileURL];
		NSView *content = [[self window] contentView];
		NSView *view = [_modelController view];
		[view setFrame:[content bounds]];
		[view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[content addSubview:view];
		/* AppKit puts a view controller after its view in the chain (since
		 * 10.10); gnustep-gui does not. */
		if ([view nextResponder] != _modelController) {
			[_modelController setNextResponder:[view nextResponder]];
			[view setNextResponder:_modelController];
		}
	}
	return self;
}

- (void)editorDidChange
{
	_modelController.documentURL = [_document fileURL];
	_modelController.editor = _document.editor;
}

- (void)setDocument:(NSDocument *)document
{
	[super setDocument:document];
	_modelController.documentURL = [document fileURL];
}

/* Saved under another name: the Core Data mappings' paths are relative to
 * where it is now. */
- (void)synchronizeWindowTitleWithDocumentName
{
	[super synchronizeWindowTitleWithDocumentName];
	_modelController.documentURL = [[self document] fileURL];
}

- (IBAction)newFlow:(id)sender
{
	ORMDocument *document = (ORMDocument *)[self document];
	NSURL *modelURL = [document fileURL];
	if (modelURL == nil) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"Save the model first."];
		[alert setInformativeText:@"A flow names its model's file, and is saved beside it."];
		[alert runModal];
		return;
	}
	NSString *name = [NSString stringWithFormat:@"%@ Flow", document.editor.model.name ?: @"Model"];
	ORMFlowDocument *flow = [ORMFlowDocument flowForModelAtURL:modelURL model:document.editor.model named:name];
	[[NSDocumentController sharedDocumentController] addDocument:flow];
	[flow makeWindowControllers];
	[flow showWindows];
}

@end
