/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMPane.h"
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* The navigator's Search tab (docs/WINDOW.md), as Xcode's find navigator:
 * the model's verbalization searched, each sentence holding the text under
 * the element it is about. Choosing a sentence chooses what it says. */
@interface ORMSearchNavigator : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, weak) id<ORMNavigatorDelegate> delegate;
@property (nonatomic, strong) ORMEditor *editor;
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSSearchField *field;
@property (nonatomic, strong) IBOutlet NSOutlineView *outline;
@property (nonatomic, strong) IBOutlet NSTextField *summary;
/* Searched for the text, as typed in the field. */
- (void)searchFor:(NSString *)text;
/* Searched again, for the model as it is. */
- (void)reload;
/* What was found: @[ element id, @[ sentence texts ] ] each. */
@property (nonatomic, readonly, copy) NSArray<NSArray *> *found;
@end
