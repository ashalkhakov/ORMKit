/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMCanvasView.h"
#import "ORMInspectorView.h"
#import "ORMModelBrowser.h"
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* A model's editor: the model browser and the other navigators on the
 * left, the diagram (its page chosen under it) with the verbalization, the
 * fact entry and the population under it in the middle, the inspector on
 * the right, the tools across the top and a status line at the bottom.
 * ORMModelView.xib, without Auto Layout (gnustep-gui has none): panes keep
 * their place with springs and struts.
 *
 * ORMDocument's window shows one (ORMWindowController), and an app that
 * edits a model in a view of its own (UDCode's ORM2 extension, a tab) puts
 * its view where it wants it: the editor is the model, whoever keeps it.
 * Its actions are the Diagram, Model and Query menus' items'. */
@interface ORMModelViewController : NSViewController <ORMCanvasDelegate, ORMInspectorDelegate, ORMModelBrowserDelegate,
                                                      NSTextFieldDelegate, NSTextViewDelegate, NSSplitViewDelegate>
/* From ORMModelView.xib, in this framework. */
- (instancetype)initWithEditor:(ORMEditor *)editor;
/* As -initWithEditor:, its parts the host's to place, as Xcode's editors
 * spread theirs over the window (UDCode's ORM2 tab): its view is the tool
 * bar, the Document Outline (Outline and Search) and the diagram; the
 * inspector, the panes under the diagram and the Insert palette are view
 * controllers of their own; the issues are the host's to show
 * (ORMIssueFinder), an issue chosen shown with -showElementOrQuery:. */
- (instancetype)initHostedWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, getter=isHosted) BOOL hosted;
/* Hosted, its parts: the inspector ("Element"); Verbalization, Fact Entry
 * and Population; the Insert palette (a Library). */
@property (nonatomic, readonly, strong) NSViewController *inspectorController;
@property (nonatomic, readonly, copy) NSArray<NSViewController *> *lowerControllers;
@property (nonatomic, readonly, strong) NSViewController *insertController;
/* Hosted: a pane under the diagram asked for (New Fact Type… the Fact
 * Entry), and a tool chosen in the Insert palette (its Library closed). */
@property (nonatomic, copy) void (^showLowerHandler)(NSViewController *pane);
@property (nonatomic, copy) void (^insertChosenHandler)(void);
/* An element shown, on a page that shows it, or a query's in the Queries
 * window: what choosing it in a navigator does. */
- (void)showElementOrQuery:(NSString *)identifier;

/* The Model, Diagram, Core Data and Query menus, from ORMModelMenus.xib,
 * new each time: a menu bar's (ORMDesigner's, after Edit) or a host's. Their
 * items go to the first responder, so to an editor in the chain. */
+ (NSArray<NSMenuItem *> *)modelMenuItems;

/* What is edited; set anew (a revert, a model read again), everything is
 * shown from the new one. */
@property (nonatomic, strong) ORMEditor *editor;
/* The model's file, which a Core Data mapping's paths are relative to; nil
 * while it has none. */
@property (nonatomic, copy) NSURL *documentURL;
/* Called after each change to the model, once the view has shown it: what
 * a host that keeps the model itself (as text, say) writes it out on. */
@property (nonatomic, copy) void (^modelChangeHandler)(void);

@property (nonatomic, readonly, strong) ORMCanvasView *canvas;
@property (nonatomic, readonly, strong) ORMInspectorView *inspector;
@property (nonatomic, readonly, strong) ORMModelBrowser *browser;
@property (nonatomic, readonly, strong) NSTextView *verbalization;
@property (nonatomic, readonly, strong) NSTextField *factEditor;
@property (nonatomic, readonly, strong) NSPopUpButton *diagramPopup;
@property (nonatomic, readonly, strong) NSTextField *status;

/* The editor's model changed outside it (it shows it again). */
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
/* Diagram > Arrange in Groups: its hubs shown in each group that uses
 * them, the groups side by side. */
- (IBAction)arrangeDiagramInGroups:(id)sender;
/* Diagram > Orient Fact Types: those selected, or all, turned and their
 * roles ordered to where their players are. */
- (IBAction)orientFactTypes:(id)sender;
- (IBAction)showOnDiagram:(id)sender;
/* Another shape of each object type and fact type picked, beside its
 * first, as NORMA allows; the new ones selected. */
- (IBAction)addAnotherShape:(id)sender;
/* The extra shapes selected removed, their elements kept. */
- (IBAction)deleteExtraShape:(id)sender;
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
