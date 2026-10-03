/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* The diagram drawn into an AppKit view: ORMKit's painter (ORMDiagramPainter,
 * which has the notation and its geometry) on a surface of NSBezierPaths
 * and NSFonts, in the view's appearance. */

/* The colours, as NORMA has them, in the current appearance. */
NSColor *ORMInkColor(void);
NSColor *ORMPaperColor(void);
NSColor *ORMObjectTypeColor(void);
NSColor *ORMConstraintColor(ORMModality modality);
NSColor *ORMSelectionColor(void);
NSColor *ORMPickColor(void);
NSColor *ORMErrorColor(void);
NSFont *ORMDiagramFont(ORMDiagram *diagram, BOOL bold);

/* Drawing into the current graphics context. */
@interface ORMAppKitSurface : NSObject <ORMDrawingSurface>
+ (instancetype)surface;
@end

/* The bounds an object type shape needs for its name and reference mode in
 * the diagram's font. */
NSSize ORMObjectTypeSizeFor(ORMObjectType *type, ORMDiagram *diagram);
/* The size a reading shape needs. */
NSSize ORMReadingSizeFor(NSString *text, ORMDiagram *diagram);

/* Draws the diagram into the current context, in the current appearance. */
void ORMDrawDiagram(ORMDiagram *diagram, NSRect dirty, ORMDrawingState *state);
/* The rectangle the diagram's drawing covers: shapes, lines and labels. */
NSRect ORMDrawingBounds(ORMDiagram *diagram);
