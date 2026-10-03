/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"

/* A diagram as NORMA saves it: ormDiagram:ORMDiagram, its shapes and
 * where they are, read into objects as the model is (ORMModel.h).
 *
 * NORMA keeps shapes, not links: the lines from a fact type's roles to
 * their players, subtype arrows and constraint connectors are drawn from
 * the model each time, between whatever shapes the diagram shows for
 * their ends. Bounds are in points here; the file has inches. */

typedef NS_ENUM(NSInteger, ORMShapeKind) {
	ORMShapeUnknown,
	ORMShapeObjectType,
	ORMShapeFactType,
	ORMShapeReading,
	ORMShapeRoleName,
	ORMShapeObjectifiedFactTypeName,
	ORMShapeValueConstraint,
	ORMShapeExternalConstraint,
	ORMShapeFrequencyConstraint,
	ORMShapeRingConstraint,
	ORMShapeValueComparisonConstraint,
	ORMShapeModelNote,
};

/* How a fact type shape lays out its role boxes. */
typedef NS_ENUM(NSInteger, ORMFactTypeOrientation) {
	ORMFactTypeHorizontal,
	ORMFactTypeVerticalRotatedRight,
	ORMFactTypeVerticalRotatedLeft,
};

@interface ORMShape : ORMElement
@property (nonatomic, readonly) ORMShapeKind kind;
@property (nonatomic, readonly) NSRect bounds;
/* What it shows: an object type, fact type, reading order, constraint,
 * value constraint, role or note. nil when the subject is gone. */
@property (nonatomic, readonly, weak) id subject;
@property (nonatomic, readonly, copy) NSString *subjectId;
@property (nonatomic, readonly, weak) ORMDiagram *diagram;
/* The shape it is placed relative to: a fact type's reading, say. */
@property (nonatomic, readonly, weak) ORMShape *parent;
@property (nonatomic, readonly, copy) NSArray<ORMShape *> *relativeShapes;
@property (nonatomic, readonly) BOOL isExpanded;

/* A fact type shape's role boxes, left to right: the roles in the order
 * the shape shows them, which need not be the fact type's. */
@property (nonatomic, readonly, copy) NSArray<ORMRole *> *roleDisplayOrder;
@property (nonatomic, readonly) ORMFactTypeOrientation orientation;
/* Whether its internal constraints are drawn below the boxes. */
@property (nonatomic, readonly) BOOL constraintsBelow;
/* An object type shape showing its reference mode as a fact type. */
@property (nonatomic, readonly) BOOL expandsReferenceMode;

- (ORMObjectType *)objectType;
- (ORMFactType *)factType;
- (ORMConstraint *)constraint;
- (NSPoint)center;
@end

@interface ORMDiagram : ORMElement
@property (nonatomic, readonly, copy) NSArray<ORMShape *> *shapes;
@property (nonatomic, readonly) BOOL isCompleteView;
@property (nonatomic, readonly, copy) NSString *baseFontName;
/* In points. */
@property (nonatomic, readonly) double baseFontSize;

/* Every shape, relative ones too, parents before children. */
- (NSArray<ORMShape *> *)allShapes;
/* The shapes on the diagram for the element, in order. */
- (NSArray<ORMShape *> *)shapesForSubject:(NSString *)subjectId;
- (ORMShape *)shapeForSubject:(NSString *)subjectId;
/* The union of every shape's bounds. */
- (NSRect)extent;
@end
