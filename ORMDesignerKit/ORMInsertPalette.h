/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMCanvasView.h"

/* What a drag from the palette carries: the tool's number, as text. */
extern NSString *const ORMInsertDragType;

@class ORMInsertPalette;

@protocol ORMInsertPaletteDelegate <NSObject>
/* A row chosen: its tool, for the canvas to take up. */
- (void)insertPalette:(ORMInsertPalette *)palette didChooseTool:(ORMCanvasTool)tool;
@end

/* The navigator's Insert tab (docs/WINDOW.md): everything that can be put
 * on the diagram, a row each, with how to put it there. Choosing a row arms
 * the canvas's tool, its next click placing it; an object type or a note is
 * also dragged onto the canvas, and placed where it is dropped. */
@interface ORMInsertPalette : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) id<ORMInsertPaletteDelegate> delegate;
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTableView *table;
/* The row of the canvas's tool selected, as it changes there. */
- (void)showTool:(ORMCanvasTool)tool;
/* The rows: @[ title, hint, @(tool) ]. */
+ (NSArray<NSArray *> *)items;
@end
