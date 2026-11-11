/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMRenderer.h"

@class ORMFlowCanvasView;

@protocol ORMFlowCanvasDelegate <NSObject>
/* The selection changed: what the inspector shows. */
- (void)flowCanvasSelectionDidChange:(ORMFlowCanvasView *)canvas;
@optional
/* A screen double-clicked below its title: its form or list to be shown
 * where it is made, in the model. */
- (void)flowCanvas:(ORMFlowCanvasView *)canvas openScreen:(NSString *)screenId;
@end

/* A flow (docs/FORMS.md, Flows) drawn and edited: DiagramKit's canvas, its
 * own data source and delegate. Each screen a card -- its name, whether a
 * form or a list, and its outline as the model has it (= ? given,
 * (entered), (shown)) -- an entry a dot with an arrow into its screen, each
 * transition an arrow from its screen's port (the dot on its right edge)
 * to the next, said with its action and what it gives, a return (back, or
 * the overlay closed) a dotted arrow to the screen it comes back to. A drag from a
 * port to another screen adds a transition; a drag of screens moves them;
 * a double-click on a screen's title renames it, below it opens its form
 * or list in the model (the delegate's);
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
/* The entries (where the flow begins): drawn as a statechart's initial
 * state, a dot left of its screen with an arrow into it; selected, and
 * deleted, as the rest are ("entry:<index>"). */
+ (NSString *)itemOfEntry:(NSUInteger)index;
- (NSIndexSet *)selectedEntries;
- (void)selectEntry:(NSUInteger)index;
- (NSRect)dotOfEntry:(NSUInteger)index;

/* Where a screen's card is, and its port; the item at a point. */
- (NSRect)frameOfScreen:(ORMFlowScreen *)screen;
- (NSPoint)portOfScreen:(ORMFlowScreen *)screen;
/* The route a transition is drawn along: its first point its screen's
 * port, its last the next screen's edge. A return goes, dotted, to the
 * screen it comes back to (an overlay's opener; Back's one way in), or
 * down out of its screen where that is whichever it came from. */
- (NSArray<NSValue *> *)routeOfTransition:(NSUInteger)index;
/* What its arrow says: the actions of all going the same way on the first
 * ("saved, cancelled → back"), "" on the others; and what each gives. */
- (NSString *)textOfTransition:(NSUInteger)index;

/* Each item's name, as the canvas has it. */
+ (NSString *)itemOfScreen:(NSString *)screenId;
+ (NSString *)itemOfTransition:(NSUInteger)index;

/* What is selected, gone (Delete). */
- (IBAction)delete:(id)sender;
@end
