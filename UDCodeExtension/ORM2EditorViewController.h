/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>

@class UDCodeDocument;
@class ORMModelViewController;

/* An .orm document's tab in UDCode (ORM2Editor.xib): ORMDesignerKit's
 * whole editor over the model its text holds, as VS Code's custom text
 * editors are.
 *
 * The text is the model. It is read into an ORMEditor with no undo of its
 * own; each change the editor makes is written back as one edit of the
 * text (the lines it changed), so the text's undo undoes it, saving and
 * the tab's dot are the document's, and a diff shows what changed. The
 * text changed otherwise (undone, edited as text, reverted) is read again,
 * the diagram, selection and inspected element kept where they still are.
 * A text that is no model shows why, and offers it as text. */
/* The bundle the extension was loaded from (ORM2Extension's -extensionDidLoad:);
 * until it is set, the one +bundleForClass: says. */
void ORM2SetBundle(NSBundle *bundle);

@interface ORM2EditorViewController : NSViewController

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench;

@property (nonatomic, readonly, strong) UDCodeDocument *document;
/* The editor, while the text is a model; nil, and why, while it is not. */
@property (nonatomic, readonly, strong) ORMModelViewController *modelController;
@property (nonatomic, readonly, copy) NSString *problem;

/* The document's text's undo, which every change of the model's is part of. */
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
/* The document in a tab of its own, as XML. */
- (IBAction)showAsText:(id)sender;

@end
