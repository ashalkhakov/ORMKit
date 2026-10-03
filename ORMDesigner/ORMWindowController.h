/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMCanvasView.h"
#import "ORMInspectorView.h"
#import "ORMModelBrowser.h"

@class ORMDocument;

/* A document's window: the model browser on the left, the diagram with the
 * fact editor and the verbalization of the selection in the middle, the
 * inspector on the right, the tools across the top and a status line at the
 * bottom. Built in code, without Auto Layout (gnustep-gui has none): panes
 * keep their place with springs and struts. */
@interface ORMWindowController : NSWindowController <ORMCanvasDelegate, ORMInspectorDelegate, ORMModelBrowserDelegate,
                                                     NSTextFieldDelegate, NSTextViewDelegate, NSSplitViewDelegate>
- (instancetype)initWithDocument:(ORMDocument *)document;

@property (nonatomic, readonly, strong) ORMCanvasView *canvas;
@property (nonatomic, readonly, strong) ORMInspectorView *inspector;
@property (nonatomic, readonly, strong) ORMModelBrowser *browser;
@property (nonatomic, readonly, strong) NSTextView *verbalization;
@property (nonatomic, readonly, strong) NSTextField *factEditor;
@property (nonatomic, readonly, strong) NSPopUpButton *diagramPopup;
@property (nonatomic, readonly, strong) NSTextField *status;

/* The document's editor changed, or was replaced (a revert). */
- (void)editorDidChange;
/* Shows the message in the status line. */
- (void)say:(NSString *)message;
/* Adds the fact type the fact editor holds; what the fact editor's Add
 * does, and what tests drive. */
- (BOOL)addFactFromEditor;

- (IBAction)focusFactEditor:(id)sender;
/* What the browser's + adds: a new object type, its name in edit. */
- (IBAction)newEntityType:(id)sender;
- (IBAction)newValueType:(id)sender;
- (IBAction)focusBrowserFilter:(id)sender;
/* The browser's filter, as typed; what tests drive. */
- (void)filterBrowserWith:(NSString *)text;
- (IBAction)newDiagram:(id)sender;
- (IBAction)renameDiagram:(id)sender;
- (IBAction)deleteDiagram:(id)sender;
- (IBAction)chooseDiagram:(id)sender;
- (IBAction)arrangeDiagram:(id)sender;
- (IBAction)showOnDiagram:(id)sender;
- (IBAction)showRelated:(id)sender;
- (IBAction)objectifyFactType:(id)sender;
- (IBAction)unobjectifyFactType:(id)sender;
- (IBAction)verbalizeModel:(id)sender;
- (IBAction)exportDiagramAsPDF:(id)sender;
- (IBAction)exportDiagramAsPNG:(id)sender;
- (IBAction)exportVerbalization:(id)sender;
- (IBAction)showCoreDataMappings:(id)sender;
- (IBAction)synchronizeCoreData:(id)sender;
/* A Core Data model brought into this one, on a diagram of its own, with
 * a mapping to it. */
- (IBAction)importCoreData:(id)sender;
@end
