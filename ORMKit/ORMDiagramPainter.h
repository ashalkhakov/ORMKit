/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagram.h"
#import <DiagramKit/DiagramKit.h>

/* Drawing an ORM2 diagram as NORMA draws it, onto any surface: the editor's
 * view, an SVG file. The notation and its geometry live here; a surface
 * (DiagramKit's DKSurface) only strokes and fills paths and sets text. Everything is in
 * diagram points, flipped: y grows downward, as NORMA's inches do.
 *
 * Object types are rounded rectangles, solid for entity types and dashed
 * for value types. A fact type is a row of role boxes, each joined by a line
 * to the object type that plays it; internal uniqueness constraints are bars
 * over the boxes, mandatory constraints dots where the line meets its object
 * type. External constraints are circles joined to their roles by dashed
 * lines; subtyping is an arrow to the supertype. NORMA keeps none of the
 * lines, so they are drawn from the model each time, each to the nearest of
 * its ends' shapes. An object type or fact type with more than one shape in
 * the model is shaded, as NORMA shades it: a shadow behind each. */

/* The colours, as NORMA has them: constraints violet when alethic, blue
 * when deontic; each with a dark counterpart. What is selected is drawn in
 * DiagramKit's DKColorSelection(). */
DKColor ORMDiagramInk(BOOL dark);
DKColor ORMDiagramPaper(BOOL dark);
DKColor ORMDiagramObjectType(BOOL dark);
DKColor ORMDiagramConstraint(ORMModality modality, BOOL dark);
DKColor ORMDiagramPick(void);
DKColor ORMDiagramError(void);
/* The shadow behind a shape whose element has others, on this diagram or
 * another: NORMA's shading of an element shown more than once. */
DKColor ORMDiagramShadow(BOOL dark);

/* The diagram's font: NORMA's base font, 7 points when it says none (nil
 * name: the surface's own sans serif). */
DKFont *ORMDiagramFont(ORMDiagram *diagram, BOOL bold);

/* What the canvas has picked out, for the drawing to show: the selected
 * shapes (DiagramKit's selection, by shape id), and what ORM2 adds. */
@interface ORMDrawingState : DKDrawingState
@property (nonatomic, copy) NSSet<NSString *> *selectedRoles;
/* The role sequences a constraint tool is gathering, in order. */
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *pickedSequences;
/* The model element under the pointer, highlighted. */
@property (nonatomic, copy) NSString *hoverElement;
@end

/* The role boxes of a fact type shape, in display order, as rectangles. */
NSArray<NSValue *> *ORMRoleBoxes(ORMShape *factTypeShape);
/* One role's box; NSZeroRect when the shape does not show it. */
NSRect ORMRoleBox(ORMShape *factTypeShape, ORMRole *role);
/* The strip the boxes make. */
NSRect ORMRoleStrip(ORMShape *factTypeShape);
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
NSSize ORMObjectTypeSizeOn(id<DKSurface> surface, ORMObjectType *type, ORMDiagram *diagram);
/* The size a reading shape needs. */
NSSize ORMReadingSizeOn(id<DKSurface> surface, NSString *text, ORMDiagram *diagram);

/* Draws the diagram onto the surface. */
void ORMPaintDiagram(ORMDiagram *diagram, id<DKSurface> surface, ORMDrawingState *state);
/* The rectangle the diagram's drawing covers: shapes, lines and labels. */
NSRect ORMPaintedBounds(ORMDiagram *diagram, id<DKSurface> surface);

/* The diagram as an SVG document (DiagramKit's DKSVGSurface), light or
 * dark, on its paper and with its name for a title. */
NSString *ORMSVGOfDiagram(ORMDiagram *diagram, BOOL dark);
