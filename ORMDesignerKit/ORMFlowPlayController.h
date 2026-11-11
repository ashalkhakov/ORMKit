/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class ORMFlow, ORMModel, ORMFlowWalk;

/* A flow played (ORMFlowPlayWindow.xib, docs/FORMS.md, Flows): walked
 * through over the model's sample population (ORMFlowWalk), as a domain
 * expert clicks through it before anything is built. The screen it is at
 * is named at the top; under it what it shows -- a list's rows, a form's
 * elements and their values, each entered with the control its type wants
 * (a date's picker, its calendar beside it on macOS; a flag's checkbox; a
 * number's field, which takes only numbers; a reference's choices, named
 * as a reader knows them, a van by its plate); beside it the
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

/* The control a row's value is shown in, its prototype's identifier in the
 * XIB: "shown" (not entered: a key, a given value, a list's row), "text",
 * "number", "date", "dateTime", "flag" or "choice". */
- (NSString *)editorOfRow:(NSInteger)row;
/* A row's value as it is shown: a reference by its label, a flag Yes or
 * No, a date in the user's way. */
- (NSString *)shownValueOfRow:(NSInteger)row;
/* A row's value set, as xsd writes it ("2026-11-10", "true", "40.5"), as
 * its control sets it. */
- (void)setValue:(NSString *)value ofRow:(NSInteger)row;

/* The control's value set as its row's: a field's text or number, a
 * picker's date, a checkbox's flag, a choice's key. */
- (IBAction)valueChanged:(id)sender;
/* A date's button: an empty one set to the date its picker shows (a
 * picker always shows one, and says nothing until it is changed), a set
 * one emptied. */
- (IBAction)setOrClearDate:(id)sender;
/* The chosen way taken: for a row chosen, the row chosen in values. */
- (IBAction)takeWay:(id)sender;
- (IBAction)submit:(id)sender;
- (IBAction)startOver:(id)sender;
@end

/* Play's values (the XIB's class for them): a field typed into at the first
 * click, its row chosen or not. */
@interface ORMFlowPlayValuesTable : NSTableView
@end
