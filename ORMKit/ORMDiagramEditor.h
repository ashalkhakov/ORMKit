/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* How shapes are lined up, as NORMA's alignment commands line them up. */
typedef NS_ENUM(NSInteger, ORMAlignment) {
	/* Edges, to the outermost shape's. */
	ORMAlignLeft,
	ORMAlignRight,
	ORMAlignTop,
	ORMAlignBottom,
	/* Centres, to the first shape's: on one vertical line, or one
	 * horizontal line. */
	ORMAlignCentres,
	ORMAlignMiddles,
	/* Spaced evenly between the outermost two, centre to centre: across,
	 * or down. */
	ORMDistributeAcross,
	ORMDistributeDown,
};

/* Diagrams and their shapes: placing, moving, sizing and arranging.
 * Usually reached as an editor's diagramEditor. */
@interface ORMDiagramEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, weak) ORMEditor *editor;

- (NSString *)addDiagramNamed:(NSString *)name;
/* A shape for the element at the point (its top left). Readings and
 * value constraints come with fact types and object types. Its id; the
 * existing shape's when the diagram already shows the element. */
- (NSString *)placeElement:(NSString *)elementId onDiagram:(NSString *)diagramId at:(NSPoint)point;
/* Another shape for an object type or fact type, even where the diagram
 * shows it already, as NORMA allows: a busy diagram's lines kept short,
 * each drawn to the nearest of the shapes. Placed automatically, it is
 * beside the first. Its id; nil for anything else. */
- (NSString *)addShapeOfElement:(NSString *)elementId onDiagram:(NSString *)diagramId at:(NSPoint)point;
/* Of the shapes, those whose element has another shape (on this diagram
 * or another), removed as one change, and what is placed on them: the
 * shape goes, never the element, nor its last shape. How many went. */
- (NSUInteger)removeExtraShapes:(NSArray<NSString *> *)shapeIds;
/* Whether the shape's element has another shape in the model. */
- (BOOL)isExtraShape:(NSString *)shapeId;
- (void)moveShapes:(NSArray<NSString *> *)shapeIds by:(NSSize)delta;
- (void)setBounds:(NSRect)bounds ofShape:(NSString *)shapeId;
/* A fact type shape's role boxes in a new order. */
- (BOOL)setRoleDisplayOrder:(NSArray<NSString *> *)roleIds ofShape:(NSString *)shapeId reason:(NSString **)reason;
- (void)setOrientation:(ORMFactTypeOrientation)orientation ofShape:(NSString *)shapeId;
/* The fact type shapes (every one on the diagram when none is named)
 * turned and their role boxes ordered to where their players are, as
 * Halpin draws them: across, or down when the players are more above one
 * another than beside; each role's box on its player's side, the reading
 * marked when it runs against them. Their readings and role names moved
 * with them. Arrange does it too. One change; how many changed. */
- (NSUInteger)orientFactTypes:(NSArray<NSString *> *)shapeIds onDiagram:(NSString *)diagramId;
/* The shapes lined up, each moved with what is placed on it (its readings,
 * role names), as one change. NO, and why, for fewer than two shapes
 * (three to distribute). */
- (BOOL)alignShapes:(NSArray<NSString *> *)shapeIds as:(ORMAlignment)alignment reason:(NSString **)reason;
/* Lays the diagram out from scratch: what it shows, placed by its links. */
- (void)arrangeDiagram:(NSString *)diagramId;
/* Lays the diagram out in groups: each anchor (an entity type much used)
 * heads one of its own, with the fact types it plays in first and what
 * they bring along; what the rest of the fact types link is a group too.
 * A group shows each object type it links to that is elsewhere (a value
 * type used more than once, another anchor) once more, its lines kept
 * inside it; the groups side by side. Spare shapes are reused, more made
 * as needed, the rest removed. One change. */
- (void)arrangeDiagramInGroups:(NSString *)diagramId;

@end
