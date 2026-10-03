/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* Drawing an ORM2 diagram as NORMA draws it, and the geometry the canvas
 * hit-tests with: plain functions of the projection, in diagram points
 * (flipped: y grows downward, as NORMA's inches do).
 *
 * Object types are rounded rectangles, solid for entity types and dashed
 * for value types. A fact type is a row of role boxes, each joined by a line
 * to the object type that plays it; internal uniqueness constraints are bars
 * over the boxes, mandatory constraints dots where the line meets its object
 * type. External constraints are circles joined to their roles by dashed
 * lines; subtyping is an arrow to the supertype. NORMA keeps none of the
 * lines, so they are drawn from the model each time. */

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
@end

/* The colours, as NORMA has them: constraints violet when alethic, blue
 * when deontic. Each has a dark-mode counterpart on Apple. */
NSColor *ORMInkColor(void);
NSColor *ORMPaperColor(void);
NSColor *ORMObjectTypeColor(void);
NSColor *ORMConstraintColor(ORMModality modality);
NSColor *ORMSelectionColor(void);
NSColor *ORMPickColor(void);
NSColor *ORMErrorColor(void);
NSFont *ORMDiagramFont(ORMDiagram *diagram, BOOL bold);

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
NSString *ORMReadingDisplayText(ORMShape *factTypeShape, ORMReadingOrder *order);
/* The bounds an object type shape needs for its name and reference mode in
 * the diagram's font. */
NSSize ORMObjectTypeSizeFor(ORMObjectType *type, ORMDiagram *diagram);
/* The size a reading shape needs. */
NSSize ORMReadingSizeFor(NSString *text, ORMDiagram *diagram);

/* Draws everything of the diagram that meets the rectangle. */
void ORMDrawDiagram(ORMDiagram *diagram, NSRect dirty, ORMDrawingState *state);
/* The rectangle the diagram's drawing covers: shapes, lines and labels. */
NSRect ORMDrawingBounds(ORMDiagram *diagram);
