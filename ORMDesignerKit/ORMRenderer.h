/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <DiagramKitUI/DiagramKitUI.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* The diagram in AppKit: ORMKit's painter (ORMDiagramPainter, which has the
 * notation and its geometry) on DiagramKit's surface of NSBezierPaths and
 * NSFonts (DKAppKitSurface), in the view's appearance. */

/* The colours, as NORMA has them, in the current appearance. */
NSColor *ORMInkColor(void);
NSColor *ORMPaperColor(void);
NSColor *ORMConstraintColor(ORMModality modality);

/* The size a reading shape needs, as AppKit sets its text. */
NSSize ORMReadingSizeFor(NSString *text, ORMDiagram *diagram);
/* The rectangle the diagram's drawing covers: shapes, lines and labels. */
NSRect ORMDrawingBounds(ORMDiagram *diagram);
