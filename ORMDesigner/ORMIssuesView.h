/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMPane.h"
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* The navigator's Issues tab (docs/WINDOW.md), as Xcode's issue navigator:
 * the model's issues (ORMIssueFinder), errors in red and warnings in
 * orange, a count of each under them. Choosing one chooses its element. */
@interface ORMIssuesView : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) id<ORMNavigatorDelegate> delegate;
@property (nonatomic, strong) ORMEditor *editor;
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *summary;
/* The issues found again, for the model as it is. */
- (void)reload;
@property (nonatomic, readonly, copy) NSArray<ORMIssue *> *issues;
@end
