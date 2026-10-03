/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

@class ORMInspectorView;

@protocol ORMInspectorDelegate <NSObject>
/* A refused edit: why, for the status line. */
- (void)inspector:(ORMInspectorView *)inspector say:(NSString *)message;
@end

/* The properties of what is selected, edited in place: an object type's
 * kind, reference mode, data type and values; a fact type's readings; a
 * role's constraints; a constraint's settings; the diagram's name.
 *
 * Built in code from rows that know where their value lives in the model
 * and which editor operation sets it. Each edit is one undoable step. The
 * rows are rebuilt when the selection changes and only refilled when the
 * model does, so a field being typed in keeps its focus. */
@interface ORMInspectorView : NSView
@property (nonatomic, weak) id<ORMInspectorDelegate> delegate;
@property (nonatomic, strong) ORMEditor *editor;
/* What it shows: an element id (object type, fact type, role, constraint,
 * note), or a diagram's. */
@property (nonatomic, copy) NSString *elementId;
/* Shown when nothing is selected. */
@property (nonatomic, copy) NSString *diagramId;
- (void)modelDidChange;
@end
