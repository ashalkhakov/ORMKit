/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

/* The panes of the document window's tab views (docs/WINDOW.md), as
 * RDLDesigner's are: each an NSView of its own, its XIB loaded with itself
 * as owner, put into a host view of the window's XIB. */

/* The view filling the host, and resizing with it. */
void ORMFillHost(NSView *host, NSView *view);
/* The pane's XIB, ORMDesignerKit's resource of the name, with the pane as
 * its owner: NO when there is none. */
BOOL ORMLoadPaneNib(NSView *pane, NSString *name);
/* Where ORMDesignerKit's XIBs are: the framework's bundle, or the bundle
 * it is compiled into (UDCode's ORM2, on GNUstep). */
NSBundle *ORMDesignerKitBundle(void);
/* A window's XIB in ORMDesignerKit: compiled (.nib) on a Mac, the XIB as it
 * is on GNUstep. For -initWithWindowNibPath:owner:, which, unlike
 * -initWithWindowNibName:, does not look in the app's bundle. */
NSString *ORMDesignerKitNibPath(NSString *name);

/* A tab bar's badge: the letters on a disc of the colour, as RDLDesigner's
 * and the XForms Designer's are (RDLTabBadge, XFDBadge). */
NSImage *ORMTabBadge(NSString *letters, double red, double green, double blue);

/* What a navigator pane tells of the element chosen in it: an element of
 * the model, or a query's id. */
@protocol ORMNavigatorDelegate <NSObject>
- (void)navigatorDidChooseElement:(NSString *)elementId;
@end
