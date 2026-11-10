/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>

@class UDCodeDocument;
@class ORMFlowWindowController;

/* A .flow document's tab in UDCode (ORM2FlowEditor.xib): ORMDesignerKit's
 * flow designer (ORMFlowWindowController's view: the model's forms and
 * lists to place, the canvas, what is wrong of the flow, the inspector,
 * Play) over the flow its text holds and the model it names, read from
 * beside the file.
 *
 * The text is the flow. Each change the designer makes is written back as
 * one edit of the text (the lines it changed), so the text's undo undoes
 * it, saving and the tab's dot are the document's; the text changed
 * otherwise is read again. A text that is no flow, or names no model that
 * can be read, shows why, and offers it as text. */
@interface ORM2FlowEditorViewController : NSViewController

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
