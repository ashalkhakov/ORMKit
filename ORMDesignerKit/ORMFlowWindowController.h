/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMFlowCanvasView.h"

@class ORMFlowPlayController;

/* A flow's window (ORMFlowWindow.xib, docs/FORMS.md, Flows): the model's
 * forms and lists on the left, to place as screens (Add to Flow, or a
 * double-click); the flow on its canvas in the middle, what is wrong of it
 * under it; on the right the inspector of what is selected -- a screen's
 * name, what it shows, its entry; a transition's action, where it goes and
 * what it gives the next form. Everything is changed through the flow's
 * editor, one undo step a change, and shown again as it is told. */
@interface ORMFlowWindowController : NSWindowController <ORMFlowCanvasDelegate, NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithEditor:(ORMFlowEditor *)editor;
@property (nonatomic, readonly, strong) ORMFlowEditor *editor;

@property (nonatomic, strong) IBOutlet ORMFlowCanvasView *canvas;
@property (nonatomic, strong) IBOutlet NSTableView *palette;
@property (nonatomic, strong) IBOutlet NSTableView *problems;
@property (nonatomic, strong) IBOutlet NSTabView *inspector;
@property (nonatomic, strong) IBOutlet NSTextField *screenName;
@property (nonatomic, strong) IBOutlet NSTextField *screenShows;
@property (nonatomic, strong) IBOutlet NSTextField *screenEntry;
@property (nonatomic, strong) IBOutlet NSTextField *transitionFrom;
@property (nonatomic, strong) IBOutlet NSPopUpButton *transitionOn;
@property (nonatomic, strong) IBOutlet NSTextField *transitionControl;
@property (nonatomic, strong) IBOutlet NSPopUpButton *transitionKind;
@property (nonatomic, strong) IBOutlet NSPopUpButton *transitionTo;
@property (nonatomic, strong) IBOutlet NSTableView *gives;

/* The palette's chosen form or list placed as a screen, right of the rest. */
- (IBAction)addToFlow:(id)sender;
- (IBAction)renameScreen:(id)sender;
- (IBAction)setEntry:(id)sender;
- (IBAction)addCancelBack:(id)sender;
- (IBAction)chooseTransitionOn:(id)sender;
- (IBAction)chooseTransitionKind:(id)sender;
- (IBAction)chooseTransitionTo:(id)sender;
- (IBAction)delete:(id)sender;
/* The flow played over the model's sample population, in a window of its
 * own (ORMFlowPlayController.h): begun again at each Play. */
- (IBAction)play:(id)sender;
@property (nonatomic, readonly, strong) ORMFlowPlayController *player;

/* Everything shown again, as the flow is now. */
- (void)flowDidChange;
@end
