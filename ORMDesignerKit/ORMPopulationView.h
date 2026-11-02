/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* The Population tab under the canvas (docs/WINDOW.md): the sample
 * population of the fact type or object type shown, as a table.
 * - A fact type's: a row a fact, a column a role, each cell its player as
 *   the table names it (a value; an entity's reference mode value).
 *   Editing a cell names that player anew; + adds a row, a fact once each
 *   of its cells is named; − removes the facts selected.
 * - An object type's: a row an instance; + and − add and remove them.
 * Each is one change through ORMPopulationEditor, undone with the model.
 * What it refuses, and what the population breaks there, is said under
 * the table. */
@interface ORMPopulationView : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) ORMEditor *editor;
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTextField *title;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *status;
/* The element shown: a fact type or an object type; others, nothing. */
@property (nonatomic, copy) NSString *elementId;
/* Read again, for the model as it is. */
- (void)reload;
- (IBAction)addRow:(id)sender;
- (IBAction)removeRows:(id)sender;
/* What a cell says; and setting it, as editing it does. */
- (NSString *)textAtRow:(NSInteger)row column:(NSInteger)column;
- (void)setText:(NSString *)text atRow:(NSInteger)row column:(NSInteger)column;
@end
