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
 * as a reader knows them, a van by its plate), then each repeat's rows (a
 * service's lines: a row added at its heading, taken away at its own line,
 * its elements entered as the form's are); beside it the
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
 * "number", "date", "dateTime", "flag", "choice" or "choices" (a set of
 * choices: each picked or not); a repeat's heading
 * "rows" (its Add), a row's "row" (its Remove). */
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
/* An empty date's Set: given today, its picker shown to change it (a
 * picker shown always holds its row's value). */
- (IBAction)setDate:(id)sender;
/* A set of choices' item picked, or no longer: its key in the row's
 * value, or out of it. */
- (IBAction)toggleChoice:(id)sender;
/* Its row's value emptied: a date's Clear. */
- (IBAction)clearValue:(id)sender;
/* A repeat's heading's Add: an empty row after its others. */
- (IBAction)addRow:(id)sender;
- (void)addRowAt:(NSInteger)line;
/* A row's Remove: the row taken away. */
- (IBAction)removeRow:(id)sender;
- (void)removeRowAt:(NSInteger)line;
/* The chosen way taken: for a row chosen, the row chosen in values. */
- (IBAction)takeWay:(id)sender;
- (IBAction)submit:(id)sender;
- (IBAction)startOver:(id)sender;
@end

/* Play's values (the XIB's class for them): a field typed into at the first
 * click, its row chosen or not. */
@interface ORMFlowPlayValuesTable : NSTableView
- (BOOL)validateProposedFirstResponder:(NSResponder *)responder forEvent:(NSEvent *)event;
@end
