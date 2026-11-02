/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

@class ORMModelBrowser;

@protocol ORMModelBrowserDelegate <NSObject>
/* An element was picked in the browser. */
- (void)browser:(ORMModelBrowser *)browser didSelect:(NSString *)elementId;
/* A diagram was opened (double-clicked). */
- (void)browser:(ORMModelBrowser *)browser openDiagram:(NSString *)diagramId;
@end

/* The model as a list, as NORMA's Model Browser shows it: object types,
 * fact types, constraints and diagrams, whether or not a diagram shows
 * them. GNUstep's outline protocols make every method required, so the
 * conformance is declared only on Apple. */
@interface ORMModelBrowser : NSObject
#if defined(__APPLE__)
	<NSOutlineViewDataSource, NSOutlineViewDelegate>
#endif
- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView;
@property (nonatomic, weak) id<ORMModelBrowserDelegate> delegate;
@property (nonatomic, strong) ORMEditor *editor;
@property (nonatomic, readonly, strong) NSOutlineView *outlineView;
/* Shows only the elements whose names contain it, ignoring case, with
 * their groups expanded; nil or empty shows everything. */
@property (nonatomic, copy) NSString *filter;
- (void)reload;
/* Selects the element's row, without telling the delegate. */
- (void)reveal:(NSString *)elementId;
@end
