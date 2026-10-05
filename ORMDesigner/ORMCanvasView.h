/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMRenderer.h"

/* What a click on the canvas makes or picks. */
typedef NS_ENUM(NSInteger, ORMCanvasTool) {
	ORMToolPointer,
	ORMToolEntityType,
	ORMToolValueType,
	/* Click the players in order, then click where the fact type goes. */
	ORMToolFactType,
	/* Drag from the subtype to the supertype. */
	ORMToolSubtype,
	/* Drag from a role box to the object type that plays it. */
	ORMToolConnectRole,
	ORMToolNote,
	/* Constraint tools: click roles, Option-Tab for the next sequence,
	 * Return to finish. */
	ORMToolUniqueness,
	ORMToolInclusiveOr,
	ORMToolExclusion,
	ORMToolExclusiveOr,
	ORMToolSubset,
	ORMToolEquality,
	ORMToolFrequency,
	ORMToolRing,
	ORMToolValueComparison,
};

@class ORMCanvasView;

@protocol ORMCanvasDelegate <NSObject>
/* The selection changed: what the inspector and verbalization show. */
- (void)canvasSelectionDidChange:(ORMCanvasView *)canvas;
/* A message for the status line; refused operations say why. */
- (void)canvas:(ORMCanvasView *)canvas say:(NSString *)message;
/* The tool went back to the pointer, or changed. */
- (void)canvasToolDidChange:(ORMCanvasView *)canvas;
@end

/* A diagram, drawn and edited. The canvas makes its changes through the
 * editor; it never changes the model itself. */
@interface ORMCanvasView : NSView
@property (nonatomic, weak) id<ORMCanvasDelegate> delegate;
@property (nonatomic, strong) ORMEditor *editor;
/* The diagram shown, by id: it outlives each projection. */
@property (nonatomic, copy) NSString *diagramId;
- (ORMDiagram *)diagram;
@property (nonatomic) ORMCanvasTool tool;
/* 1 is the diagram's points; NORMA's role boxes read best at about 1.5. */
@property (nonatomic) double zoom;

/* The selected shapes and roles, by id. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *selectedShapes;
@property (nonatomic, readonly, copy) NSArray<NSString *> *selectedRoles;
/* The model elements the selection stands for: shapes' subjects, roles. */
- (NSArray<NSString *> *)selectedElements;
/* Selects the shapes on this diagram for the elements. */
- (void)selectElements:(NSArray<NSString *> *)elementIds;
/* A role box selected, as a click on it selects it. */
- (void)selectRole:(NSString *)roleId;
- (void)clearSelection;

/* After the editor changed the model: the projection is new. */
- (void)modelDidChange;
/* The frame for the drawing at the zoom. */
- (void)resize;

/* The diagram as PDF or PNG, without selection. */
- (NSData *)PDFData;
- (NSData *)PNGDataAtScale:(double)scale;

/* A new entity or value type, named EntityType, EntityType1, ... and
 * placed at the point (or wherever there is room), its name in edit. */
- (void)createObjectTypeAt:(NSPoint)point value:(BOOL)value;
- (IBAction)chooseTool:(id)sender;
/* The same, the tool given: what the Insert palette chooses. */
- (void)useTool:(ORMCanvasTool)tool;
/* What the tool puts at the point, in one click: an entity or value type,
 * or a note. NO for a tool that takes more (a fact type, a constraint). */
- (BOOL)placeTool:(ORMCanvasTool)tool at:(NSPoint)point;
- (IBAction)delete:(id)sender;
- (IBAction)removeFromDiagram:(id)sender;
- (IBAction)toggleUniqueness:(id)sender;
- (IBAction)toggleMandatory:(id)sender;
- (IBAction)nextRoleSequence:(id)sender;
- (IBAction)commitPending:(id)sender;
- (IBAction)rotateFactType:(id)sender;
- (IBAction)reverseRoleOrder:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)zoomToActualSize:(id)sender;
- (IBAction)zoomToFit:(id)sender;
@end
