/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class ORMFlow, ORMModel, ORMFlowWalk;

/* A flow played (ORMFlowPlayWindow.xib, docs/FORMS.md, Flows): walked
 * through over the model's sample population (ORMFlowWalk), as a domain
 * expert clicks through it before anything is built. The screen it is at
 * is named at the top; under it what it shows -- a list's rows, a form's
 * elements and their values, typed into as a user would; beside it the
 * ways on, a list's row chosen first; Submit saves the form, a refusal said
 * in the rule's words in the log at the bottom, and goes on as the flow
 * says; Start Over begins at its first entry again. */
@interface ORMFlowPlayController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithFlow:(ORMFlow *)flow model:(ORMModel *)model;
@property (nonatomic, readonly, strong) ORMFlowWalk *walk;

@property (nonatomic, strong) IBOutlet NSTextField *screenTitle;
@property (nonatomic, strong) IBOutlet NSTableView *values;
@property (nonatomic, strong) IBOutlet NSTableView *ways;
@property (nonatomic, strong) IBOutlet NSTableView *log;
@property (nonatomic, strong) IBOutlet NSButton *takeButton;
@property (nonatomic, strong) IBOutlet NSButton *submitButton;

/* The chosen way taken: for a row chosen, the row chosen in values. */
- (IBAction)takeWay:(id)sender;
- (IBAction)submit:(id)sender;
- (IBAction)startOver:(id)sender;
@end
