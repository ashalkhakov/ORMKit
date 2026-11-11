/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>
#import <UDCodeKit/UDEditorPanes.h>

@class UDCodeDocument;
@class ORMFlowWindowController;

/* A .flow document's tab in UDCode (ORM2FlowEditor.xib): ORMDesignerKit's
 * flow designer (ORMFlowWindowController's view: the model's forms and
 * lists to place, the canvas and its zoom, Play) over the flow its text
 * holds and the model it names, read from beside the file. Its inspector
 * is the window's inspector pane's Flow tab, after File; a screen's form
 * or list opens in the model's tab, the query in its Queries window.
 *
 * The text is the flow. Each change the designer makes is written back as
 * one edit of the text (the lines it changed), so the text's undo undoes
 * it, saving and the tab's dot are the document's; the text changed
 * otherwise is read again. What is wrong of the flow is the document's
 * diagnostics, in the Issues navigator, each at its screen's line, the
 * screen chosen when it is. A text that is no flow, or names no model that
 * can be read, shows why, and offers it as text. */
@interface ORM2FlowEditorViewController : NSViewController <UDEditorPanes>

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench;

@property (nonatomic, readonly, strong) UDCodeDocument *document;
/* The designer, while the text is a flow of a model that can be read; nil,
 * and why, while it is not. */
@property (nonatomic, readonly, strong) ORMFlowWindowController *flowController;
@property (nonatomic, readonly, copy) NSString *problem;

- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
- (IBAction)showAsText:(id)sender;

@end
