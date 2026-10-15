/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMCanvasView.h"
#import "ORMInspectorView.h"
#import "ORMModelBrowser.h"

@class ORMDocument;

/* A document's window: the model browser on the left, the diagram (its
 * pages as tabs under it) with the fact editor and the verbalization of the
 * selection in the middle, the
 * inspector on the right, the tools across the top and a status line at the
 * bottom. ORMDocumentWindow.xib, without Auto Layout (gnustep-gui has none):
 * panes keep their place with springs and struts. */
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
/* Model > Merge Entity Types: the two entity types selected made one, kept
 * in both their entities (docs/JOINED-ENTITIES.md), by a value both have;
 * asked which where there are several. */
- (IBAction)mergeEntityTypes:(id)sender;
/* The ways two entity types can be merged: each @[ the kept one, its
 * value's role, the absorbed one, its value's role ], a candidate the
 * model sees first. */
- (NSArray<NSArray *> *)mergesOf:(NSArray<NSString *> *)entityTypeIds;
- (IBAction)verbalizeModel:(id)sender;
- (IBAction)exportDiagramAsPDF:(id)sender;
- (IBAction)exportDiagramAsPNG:(id)sender;
- (IBAction)exportVerbalization:(id)sender;
- (IBAction)showCoreDataMappings:(id)sender;
- (IBAction)synchronizeCoreData:(id)sender;
/* A Core Data model brought into this one, on a diagram of its own, with
 * a mapping to it. */
- (IBAction)importCoreData:(id)sender;
/* Conceptual queries: the window, and a new query from the selected
 * object type. */
- (IBAction)showQueries:(id)sender;
- (IBAction)newQueryFromSelection:(id)sender;
/* Query > Make Up a Sample Population. */
- (IBAction)makeUpPopulation:(id)sender;
/* The shapes selected, lined up as the sender's tag says (ORMAlignment). */
- (IBAction)alignSelection:(id)sender;
/* The diagram shown on the canvas, its page chosen. */
- (void)openDiagram:(NSString *)diagramId;
@end
