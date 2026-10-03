/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagramPainter.h"

/* A diagram as SVG, drawn by the same painter as the editor draws it.
 *
 * Foundation has no fonts to measure with, so text widths are estimated
 * from the diagram font's size; text that is centred is centred by the SVG
 * renderer (text-anchor), so only left-set text depends on the estimate. */
@interface ORMSVGSurface : NSObject <ORMDrawingSurface>
/* The drawing so far as a standalone SVG document showing the rectangle,
 * on the paper colour, with the title. */
- (NSString *)documentWithBounds:(NSRect)bounds paper:(ORMColor)paper title:(NSString *)title;
@end

/* The diagram as an SVG document, light or dark. */
NSString *ORMSVGOfDiagram(ORMDiagram *diagram, BOOL dark);
