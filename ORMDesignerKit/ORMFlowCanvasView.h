/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMRenderer.h"

@class ORMFlowCanvasView;

@protocol ORMFlowCanvasDelegate <NSObject>
/* The selection changed: what the inspector shows. */
- (void)flowCanvasSelectionDidChange:(ORMFlowCanvasView *)canvas;
@end

/* A flow (docs/FORMS.md, Flows) drawn and edited: DiagramKit's canvas, its
 * own data source and delegate. Each screen a card -- its name, whether a
 * form or a list, and its outline as the model has it (= ? given, ✎
 * entered, ✓ shown) -- an entry a ▶ tab on its screen's card, each
 * transition an arrow from its screen's port (the dot on its right edge)
 * to the next, said with its action and what it gives, a return (back, or
 * the overlay closed) a short arrow down out of its screen. A drag from a
 * port to another screen adds a transition; a drag of screens moves them;
 * Delete removes what is selected. Its items are the screens' ids and the
 * transitions' indexes ("screen:<id>", "transition:<index>"). It changes the
 * flow through its editor and never itself. */
@interface ORMFlowCanvasView : DKCanvasView <DKCanvasDataSource, DKCanvasDelegate>
@property (nonatomic, weak) IBOutlet id<ORMFlowCanvasDelegate> flowDelegate;
@property (nonatomic, strong) ORMFlowEditor *editor;

/* The selected screens' ids, and transitions' indexes. */
- (NSArray<NSString *> *)selectedScreens;
- (NSIndexSet *)selectedTransitions;
- (void)selectScreen:(NSString *)screenId;
- (void)selectTransition:(NSUInteger)index;

/* Where a screen's card is, and its port; the item at a point. */
- (NSRect)frameOfScreen:(ORMFlowScreen *)screen;
- (NSPoint)portOfScreen:(ORMFlowScreen *)screen;
/* The route a transition is drawn along: its first point its screen's
 * port, its last the next screen's edge (a return's, below its screen). */
- (NSArray<NSValue *> *)routeOfTransition:(NSUInteger)index;

/* Each item's name, as the canvas has it. */
+ (NSString *)itemOfScreen:(NSString *)screenId;
+ (NSString *)itemOfTransition:(NSUInteger)index;

/* What is selected, gone (Delete). */
- (IBAction)delete:(id)sender;
@end
