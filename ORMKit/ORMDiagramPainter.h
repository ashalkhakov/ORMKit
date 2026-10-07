/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagram.h"

/* Drawing an ORM2 diagram as NORMA draws it, onto any surface: the editor's
 * view, an SVG file. The notation and its geometry live here; a
 * surface only strokes and fills paths and sets text. Everything is in
 * diagram points, flipped: y grows downward, as NORMA's inches do.
 *
 * Object types are rounded rectangles, solid for entity types and dashed
 * for value types. A fact type is a row of role boxes, each joined by a line
 * to the object type that plays it; internal uniqueness constraints are bars
 * over the boxes, mandatory constraints dots where the line meets its object
 * type. External constraints are circles joined to their roles by dashed
 * lines; subtyping is an arrow to the supertype. NORMA keeps none of the
 * lines, so they are drawn from the model each time. */

typedef struct {
	double red, green, blue, alpha;
} ORMColor;

ORMColor ORMColorMake(double red, double green, double blue, double alpha);
ORMColor ORMColorWithAlpha(ORMColor color, double alpha);
/* "#800080", for SVG and the like. */
NSString *ORMColorHex(ORMColor color);

/* The colours, as NORMA has them: constraints violet when alethic, blue
 * when deontic; each with a dark counterpart. */
ORMColor ORMDiagramInk(BOOL dark);
ORMColor ORMDiagramPaper(BOOL dark);
ORMColor ORMDiagramObjectType(BOOL dark);
ORMColor ORMDiagramConstraint(ORMModality modality, BOOL dark);
ORMColor ORMDiagramSelection(void);
ORMColor ORMDiagramPick(void);
ORMColor ORMDiagramError(void);

/* A font by name (nil: the surface's own sans serif), size and weight. */
@interface ORMDrawingFont : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) double size;
@property (nonatomic) BOOL bold;
+ (instancetype)fontNamed:(NSString *)name size:(double)size bold:(BOOL)bold;
/* The diagram's own: NORMA's base font, 7 points when it says none. */
+ (instancetype)fontOfDiagram:(ORMDiagram *)diagram bold:(BOOL)bold;
@end

typedef NS_ENUM(NSInteger, ORMPathElement) {
	ORMPathMove,
	ORMPathLine,
	ORMPathClose,
};

/* A path to stroke or fill: lines, or one of the shapes a surface may
 * draw natively. */
@interface ORMDrawPath : NSObject
+ (instancetype)path;
+ (instancetype)lineFrom:(NSPoint)from to:(NSPoint)to;
+ (instancetype)rect:(NSRect)rect;
/* NORMA's rounding: a third of the shorter side, at most 9 points. */
+ (instancetype)roundedRect:(NSRect)rect;
+ (instancetype)oval:(NSRect)rect;
- (void)moveTo:(NSPoint)point;
- (void)lineTo:(NSPoint)point;
- (void)close;
/* A rect, rounded rect or oval: its rectangle and corner radius; else
 * NSZeroRect and the elements. */
@property (nonatomic, readonly) NSRect rect;
@property (nonatomic, readonly) double radius;
@property (nonatomic, readonly) BOOL isOval;
/* [kind, point] pairs: NSNumber of ORMPathElement, NSValue of a point. */
@property (nonatomic, readonly, copy) NSArray<NSArray *> *elements;
@end

@protocol ORMDrawingSurface <NSObject>
- (NSSize)sizeOfText:(NSString *)text font:(ORMDrawingFont *)font;
- (void)strokePath:(ORMDrawPath *)path color:(ORMColor)color width:(double)width dashed:(BOOL)dashed;
- (void)fillPath:(ORMDrawPath *)path color:(ORMColor)color;
/* Text from its top left corner, or centred on the point's x. */
- (void)drawText:(NSString *)text
              at:(NSPoint)point
            font:(ORMDrawingFont *)font
           color:(ORMColor)color
        centered:(BOOL)centered;
/* Text wrapped to the rectangle's width, from its top left. */
- (void)drawText:(NSString *)text inRect:(NSRect)rect font:(ORMDrawingFont *)font color:(ORMColor)color;
@end

/* What the canvas has picked out, for the drawing to show. */
@interface ORMDrawingState : NSObject
@property (nonatomic, copy) NSSet<NSString *> *selectedShapes;
@property (nonatomic, copy) NSSet<NSString *> *selectedRoles;
/* The role sequences a constraint tool is gathering, in order. */
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *pickedSequences;
/* The model element under the pointer, highlighted. */
@property (nonatomic, copy) NSString *hoverElement;
/* Print and export leave the selection out. */
@property (nonatomic) BOOL forPrinting;
/* The dark colours. */
@property (nonatomic) BOOL dark;
@end

/* The role boxes of a fact type shape, in display order, as rectangles. */
NSArray<NSValue *> *ORMRoleBoxes(ORMShape *factTypeShape);
/* One role's box; NSZeroRect when the shape does not show it. */
NSRect ORMRoleBox(ORMShape *factTypeShape, ORMRole *role);
/* The strip the boxes make. */
NSRect ORMRoleStrip(ORMShape *factTypeShape);
/* Where a line toward the point leaves the rectangle. */
NSPoint ORMEdgePoint(NSRect rect, NSPoint toward);
/* The shape on the diagram for the object type nearest the point: an
 * object type may be shown more than once. */
ORMShape *ORMShapeOfObjectType(ORMDiagram *diagram, ORMObjectType *type, NSPoint near);
/* Where a role's line meets its fact type and its player; NO when the
 * diagram does not show both. */
BOOL ORMRoleLine(ORMDiagram *diagram, ORMShape *factTypeShape, ORMRole *role, NSPoint *atRole, NSPoint *atPlayer);
/* The point an external constraint's dashed line goes to for a role. */
NSPoint ORMRoleAttachment(ORMShape *factTypeShape, ORMRole *role, NSPoint from);
/* The text a reading shape shows: "was born in", or "◀ is birthplace of"
 * when it reads against the boxes, or "… gave … to …". */
/* With NORMA's mark of a derived fact type after it: * derived, + partly
 * derived, doubled when stored. */
NSString *ORMReadingDisplayText(ORMShape *factTypeShape, ORMReadingOrder *order);

/* The bounds an object type shape needs for its name and reference mode in
 * the diagram's font, as the surface measures it. */
NSSize ORMObjectTypeSizeOn(id<ORMDrawingSurface> surface, ORMObjectType *type, ORMDiagram *diagram);
/* The size a reading shape needs. */
NSSize ORMReadingSizeOn(id<ORMDrawingSurface> surface, NSString *text, ORMDiagram *diagram);

/* Draws the diagram onto the surface. */
void ORMPaintDiagram(ORMDiagram *diagram, id<ORMDrawingSurface> surface, ORMDrawingState *state);
/* The rectangle the diagram's drawing covers: shapes, lines and labels. */
NSRect ORMPaintedBounds(ORMDiagram *diagram, id<ORMDrawingSurface> surface);
