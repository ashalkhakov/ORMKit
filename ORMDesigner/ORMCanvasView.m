/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCanvasView.h"
#import "ORMInsertPalette.h"

/* What a tool's drag is doing, between mouse down and up. Moving, the
 * band and panning are DiagramKit's. */
typedef NS_ENUM(NSInteger, ORMGesture) {
	ORMGestureNone,
	ORMGestureSubtype,
	ORMGestureConnect,
};

/* What is under a point: the shape, and the role box when it is one. */
@interface ORMHit : NSObject
@property (nonatomic, strong) ORMShape *shape;
@property (nonatomic, strong) ORMRole *role;
@end

@implementation ORMHit
@end

/* Room around the drawing to place new shapes in. */
static const double ORMCanvasMargin = 240.0;
/* The zoom NORMA's role boxes read best at. */
static const double ORMActualSize = 1.5;

@implementation ORMCanvasView
{
	/* The selection in the order it was made (DiagramKit's is a set), and
	 * the roles selected in it. */
	NSMutableArray<NSString *> *_selectedShapes;
	NSMutableArray<NSString *> *_selectedRoles;
	/* A constraint tool's role sequences, and the fact type tool's players. */
	NSMutableArray<NSMutableArray<NSString *> *> *_picked;
	NSMutableArray<NSString *> *_pickedPlayers;
	ORMGesture _gesture;
	NSPoint _down;
	NSPoint _at;
	ORMHit *_downHit;
	NSString *_hover;
}

- (void)setUpCanvas
{
	if (_selectedShapes != nil) {
		return;
	}
	_selectedShapes = [NSMutableArray array];
	_selectedRoles = [NSMutableArray array];
	_picked = [NSMutableArray array];
	_pickedPlayers = [NSMutableArray array];
	/* Its own data source and delegate: an outlet from a view to itself
	 * breaks ibtool. */
	self.dataSource = self;
	self.delegate = self;
	self.margin = ORMCanvasMargin;
	self.zoom = ORMActualSize;
	/* What the Insert palette drags here. */
	[self registerForDraggedTypes:@[ ORMInsertDragType ]];
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		[self setUpCanvas];
	}
	return self;
}

/* From the document window's XIB, which does not call -initWithFrame:. */
- (void)awakeFromNib
{
	[super awakeFromNib];
	[self setUpCanvas];
}

- (ORMDiagram *)diagram
{
	ORMDiagram *diagram = [self.editor.model elementWithId:self.diagramId];
	return [diagram isKindOfClass:[ORMDiagram class]] ? diagram : nil;
}

- (NSArray<NSString *> *)selectedShapes
{
	return [_selectedShapes copy];
}

- (NSArray<NSString *> *)selectedRoles
{
	return [_selectedRoles copy];
}

- (void)setDiagramId:(NSString *)diagramId
{
	if (![_diagramId isEqualToString:diagramId]) {
		_diagramId = [diagramId copy];
		[self clearSelection];
		[self cancelPending];
		[self reloadData];
	}
}

- (void)setTool:(ORMCanvasTool)tool
{
	_tool = tool;
	[self cancelPending];
	[self.canvasDelegate canvasToolDidChange:self];
	[self setNeedsDisplay:YES];
}

#pragma mark Geometry

/* The topmost thing under the point: labels, then constraints and notes,
 * then role boxes, fact types and object types. */
- (ORMHit *)hitAt:(NSPoint)point
{
	ORMDiagram *diagram = [self diagram];
	ORMHit *hit = [[ORMHit alloc] init];
	double slop = 2.0 / self.zoom;
	for (ORMShape *shape in [diagram.shapes reverseObjectEnumerator]) {
		for (ORMShape *child in shape.relativeShapes) {
			NSRect bounds = child.bounds;
			if (child.kind == ORMShapeReading && [child.subject isKindOfClass:[ORMReadingOrder class]]) {
				NSSize size = ORMReadingSizeFor(ORMReadingDisplayText(shape, child.subject), diagram);
				bounds.size = size;
			}
			if (NSPointInRect(point, NSInsetRect(bounds, -slop, -slop))) {
				hit.shape = child;
				return hit;
			}
		}
	}
	for (ORMShape *shape in [diagram.shapes reverseObjectEnumerator]) {
		BOOL constraintLike = shape.kind == ORMShapeExternalConstraint || shape.kind == ORMShapeFrequencyConstraint
			|| shape.kind == ORMShapeRingConstraint || shape.kind == ORMShapeValueComparisonConstraint
			|| shape.kind == ORMShapeModelNote;
		if (constraintLike && NSPointInRect(point, NSInsetRect(shape.bounds, -slop, -slop))) {
			hit.shape = shape;
			return hit;
		}
	}
	for (ORMShape *shape in [diagram.shapes reverseObjectEnumerator]) {
		if (shape.kind != ORMShapeFactType) {
			continue;
		}
		for (ORMRole *role in shape.roleDisplayOrder) {
			NSRect box = ORMRoleBox(shape, role);
			if (!NSIsEmptyRect(box) && NSPointInRect(point, NSInsetRect(box, -slop, -slop))) {
				hit.shape = shape;
				hit.role = role;
				return hit;
			}
		}
	}
	for (ORMShape *shape in [diagram.shapes reverseObjectEnumerator]) {
		if (shape.kind == ORMShapeObjectType && NSPointInRect(point, shape.bounds)) {
			hit.shape = shape;
			return hit;
		}
	}
	for (ORMShape *shape in [diagram.shapes reverseObjectEnumerator]) {
		if (shape.kind != ORMShapeFactType) {
			continue;
		}
		NSRect area = NSInsetRect(ORMRoleStrip(shape), -6, -6);
		if (shape.factType.objectifyingType != nil) {
			area = NSInsetRect(ORMRoleStrip(shape), -12, -9);
		}
		if (NSPointInRect(point, area)) {
			hit.shape = shape;
			return hit;
		}
	}
	return nil;
}

#pragma mark What the canvas shows

- (NSRect)diagramBoundsForCanvas:(DKCanvasView *)canvas
{
	(void)canvas;
	ORMDiagram *diagram = [self diagram];
	return diagram != nil ? ORMDrawingBounds(diagram) : NSZeroRect;
}

/* The shapes: a label or a role box's fact type, as -hitAt: finds them. */
- (id)canvas:(DKCanvasView *)canvas itemAtPoint:(NSPoint)point
{
	(void)canvas;
	return [self hitAt:point].shape.identifier;
}

/* What a band selects: the top-level shapes it touches. */
- (NSArray *)canvas:(DKCanvasView *)canvas itemsInRect:(NSRect)rect
{
	(void)canvas;
	NSMutableArray *items = [NSMutableArray array];
	for (ORMShape *shape in [self diagram].shapes) {
		if (NSIntersectsRect(rect, shape.bounds)) {
			[items addObject:shape.identifier];
		}
	}
	return items;
}

- (NSRect)canvas:(DKCanvasView *)canvas frameOfItem:(id)item
{
	(void)canvas;
	ORMShape *shape = [self.editor.model elementWithId:item];
	return [shape isKindOfClass:[ORMShape class]] ? shape.bounds : NSZeroRect;
}

/* ORMKit's painter, on the paper; the roles and what a tool has picked
 * with the canvas's selection, and, on screen, the tool's own marks. */
- (void)canvas:(DKCanvasView *)canvas drawInRect:(NSRect)rect surface:(id<DKSurface>)surface state:(DKDrawingState *)state
{
	(void)canvas;
	[surface fillPath:[DKPath pathWithRect:rect] color:ORMDiagramPaper(state.dark)];
	ORMDiagram *diagram = [self diagram];
	if (diagram == nil) {
		return;
	}
	ORMDrawingState *drawing = [[ORMDrawingState alloc] init];
	drawing.selection = state.selection;
	drawing.hoveredItem = state.hoveredItem;
	drawing.forPrinting = state.forPrinting;
	drawing.dark = state.dark;
	drawing.zoom = state.zoom;
	drawing.selectedRoles = [NSSet setWithArray:_selectedRoles];
	drawing.pickedSequences = _picked;
	drawing.hoverElement = _hover;
	ORMPaintDiagram(diagram, surface, drawing);
	if (state.forPrinting) {
		return;
	}
	[self drawPickedPlayersOn:surface];
	if (_gesture != ORMGestureNone) {
		[surface strokePath:[DKPath pathWithLineFrom:_down to:_at] color:DKColorSelection() width:1.2 style:DKStrokeSolid];
	}
}

/* The fact type tool's players, numbered in the order picked. */
- (void)drawPickedPlayersOn:(id<DKSurface>)surface
{
	DKFont *font = [DKFont systemFontOfSize:7 bold:YES];
	for (NSUInteger i = 0; i < [_pickedPlayers count]; i++) {
		ORMShape *shape = [self.editor.model elementWithId:[_pickedPlayers objectAtIndex:i]];
		if (shape == nil) {
			continue;
		}
		NSRect badge = NSMakeRect(NSMaxX(shape.bounds) - 4, NSMinY(shape.bounds) - 6, 10, 10);
		[surface fillPath:[DKPath pathWithOvalInRect:badge] color:ORMDiagramPick()];
		NSString *number = [NSString stringWithFormat:@"%lu", (unsigned long)i + 1];
		NSSize size = [surface sizeOfText:number font:font];
		[surface drawText:number at:NSMakePoint(NSMidX(badge), NSMidY(badge) - size.height / 2) font:font
		            color:DKColorWhite()
		         centered:YES];
	}
}

#pragma mark Selection

- (NSArray<NSString *> *)selectedElements
{
	if ([_selectedRoles count] > 0) {
		return [_selectedRoles copy];
	}
	NSMutableArray *elements = [NSMutableArray array];
	for (NSString *shapeId in _selectedShapes) {
		ORMShape *shape = [self.editor.model elementWithId:shapeId];
		id subject = shape.subject;
		if ([subject isKindOfClass:[ORMReadingOrder class]]) {
			subject = [(ORMReadingOrder *)subject factType];
		}
		NSString *identifier = [subject identifier];
		if (identifier != nil && ![elements containsObject:identifier]) {
			[elements addObject:identifier];
		}
	}
	return elements;
}

/* Every shape of the element on this diagram, added to the selection:
 * an element shown more than once is selected wherever it is. */
- (void)addShapesOf:(NSString *)elementId
{
	for (ORMShape *shape in [[self diagram] shapesForSubject:elementId]) {
		if (![_selectedShapes containsObject:shape.identifier]) {
			[_selectedShapes addObject:shape.identifier];
		}
	}
}

- (void)selectRole:(NSString *)roleId
{
	ORMRole *role = [self.editor.model elementWithId:roleId];
	[_selectedShapes removeAllObjects];
	[_selectedRoles removeAllObjects];
	if ([role isKindOfClass:[ORMRole class]]) {
		[self addShapesOf:role.factType.identifier];
		if ([_selectedShapes count] > 0) {
			[_selectedRoles addObject:roleId];
		}
	}
	_clickedRole = [roleId copy];
	[self selectionChanged];
}

- (void)clearSelection
{
	_clickedRole = nil;
	[_selectedShapes removeAllObjects];
	[_selectedRoles removeAllObjects];
	[self selectionChanged];
}

- (void)selectShapes:(NSArray<NSString *> *)shapeIds
{
	_clickedRole = nil;
	[_selectedShapes removeAllObjects];
	[_selectedRoles removeAllObjects];
	[_selectedShapes addObjectsFromArray:shapeIds];
	[self selectionChanged];
	[self scrollToSelection];
}

- (void)selectElements:(NSArray<NSString *> *)elementIds
{
	/* Not a click: no role was clicked to follow. */
	_clickedRole = nil;
	[_selectedShapes removeAllObjects];
	[_selectedRoles removeAllObjects];
	for (NSString *elementId in elementIds) {
		id element = [self.editor.model elementWithId:elementId];
		if ([element isKindOfClass:[ORMRole class]]) {
			[_selectedRoles addObject:elementId];
			[self addShapesOf:[(ORMRole *)element factType].identifier];
			continue;
		}
		[self addShapesOf:elementId];
	}
	[self selectionChanged];
	[self scrollToSelection];
}

- (void)scrollToSelection
{
	NSRect area = NSZeroRect;
	for (NSString *shapeId in _selectedShapes) {
		ORMShape *shape = [self.editor.model elementWithId:shapeId];
		if (shape != nil) {
			area = NSIsEmptyRect(area) ? shape.bounds : NSUnionRect(area, shape.bounds);
		}
	}
	if (!NSIsEmptyRect(area)) {
		[self scrollRectToVisible:NSInsetRect(area, -30, -30)];
	}
}

/* The selection, ordered and with its roles, made the canvas's, and the
 * window told. */
- (void)selectionChanged
{
	self.selection = [NSSet setWithArray:_selectedShapes];
	[self.canvasDelegate canvasSelectionDidChange:self];
}

/* The canvas selected by a gesture (a click, the band, Select All): what
 * it dropped dropped here, what it added added after, in the diagram's
 * order. A role is selected only by a click on its box (-pointerDown:). */
- (void)canvasSelectionDidChange:(DKCanvasView *)canvas
{
	(void)canvas;
	NSSet *now = self.selection;
	NSMutableArray *kept = [NSMutableArray array];
	for (NSString *shapeId in _selectedShapes) {
		if ([now containsObject:shapeId]) {
			[kept addObject:shapeId];
		}
	}
	NSMutableArray *pending = [[self diagram].shapes mutableCopy] ?: [NSMutableArray array];
	for (NSUInteger i = 0; i < [pending count]; i++) {
		ORMShape *shape = [pending objectAtIndex:i];
		if ([now containsObject:shape.identifier] && ![kept containsObject:shape.identifier]) {
			[kept addObject:shape.identifier];
		}
		[pending addObjectsFromArray:shape.relativeShapes];
	}
	[_selectedShapes setArray:kept];
	[_selectedRoles removeAllObjects];
	[self selectionChanged];
}

- (IBAction)selectAll:(id)sender
{
	_clickedRole = nil;
	[super selectAll:sender];
}

- (void)modelDidChange
{
	ORMModel *model = self.editor.model;
	for (NSString *shapeId in [_selectedShapes copy]) {
		if (![[model elementWithId:shapeId] isKindOfClass:[ORMShape class]]) {
			[_selectedShapes removeObject:shapeId];
		}
	}
	for (NSString *roleId in [_selectedRoles copy]) {
		if (![[model elementWithId:roleId] isKindOfClass:[ORMRole class]]) {
			[_selectedRoles removeObject:roleId];
		}
	}
	self.selection = [NSSet setWithArray:_selectedShapes];
	[self reloadData];
}

- (void)say:(NSString *)message
{
	[self.canvasDelegate canvas:self say:message ?: @""];
}

- (void)refuse:(NSString *)reason
{
	NSBeep();
	[self say:reason];
}

#pragma mark The tools

/* A press, before the canvas makes anything of it: a tool's, or a role
 * box's. The pointer leaves the rest to the canvas (selecting, the band,
 * dragging the selection); a double-click on a shape too. */
- (BOOL)canvas:(DKCanvasView *)canvas mouseDown:(NSEvent *)event atPoint:(NSPoint)point
{
	(void)canvas;
	_down = point;
	_at = point;
	ORMHit *hit = [self hitAt:point];
	_downHit = hit;
	_clickedRole = [hit.role.identifier copy];
	if ([event clickCount] == 2 && hit != nil) {
		return NO;
	}
	BOOL extend = ([event modifierFlags] & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) != 0;
	BOOL taken = YES;
	switch (self.tool) {
	case ORMToolPointer:
		taken = [self pointerDown:hit extend:extend];
		break;
	case ORMToolEntityType:
	case ORMToolValueType:
		[self placeTool:self.tool at:point];
		break;
	case ORMToolFactType:
		[self factTypeToolDown:hit at:point];
		break;
	case ORMToolSubtype:
		if (hit.shape.kind == ORMShapeObjectType) {
			_gesture = ORMGestureSubtype;
		} else {
			[self refuse:@"Drag from the subtype to its supertype."];
		}
		break;
	case ORMToolConnectRole:
		if (hit.role != nil) {
			_gesture = ORMGestureConnect;
		} else {
			[self refuse:@"Drag from a role box to the object type that plays it."];
		}
		break;
	case ORMToolNote:
		[self placeTool:ORMToolNote at:point];
		break;
	default:
		[self constraintToolDown:hit];
		break;
	}
	[self setNeedsDisplay:YES];
	return taken;
}

- (void)canvas:(DKCanvasView *)canvas mouseDragged:(NSEvent *)event atPoint:(NSPoint)point
{
	(void)canvas;
	(void)event;
	if (_gesture == ORMGestureNone) {
		return;
	}
	_at = point;
	_hover = [self hitAt:point].shape.objectType.identifier;
	[self setNeedsDisplay:YES];
}

- (void)canvas:(DKCanvasView *)canvas mouseUp:(NSEvent *)event atPoint:(NSPoint)point
{
	(void)canvas;
	(void)event;
	_at = point;
	ORMGesture gesture = _gesture;
	_gesture = ORMGestureNone;
	_hover = nil;
	if (gesture == ORMGestureSubtype) {
		[self finishSubtype];
	} else if (gesture == ORMGestureConnect) {
		[self finishConnect];
	}
	[self setNeedsDisplay:YES];
}

/* A click with the pointer on a role box, as NORMA: the first selects the
 * fact type (the canvas does), the next the role; with Shift or Command,
 * the role is added or taken away, its fact type kept. A click elsewhere
 * on a shape selected leaves its roles. YES: the press is taken. */
- (BOOL)pointerDown:(ORMHit *)hit extend:(BOOL)extend
{
	NSString *shapeId = hit.shape.identifier;
	BOOL selected = shapeId != nil && [_selectedShapes containsObject:shapeId];
	if (hit.role == nil) {
		if (selected && !extend && [_selectedRoles count] > 0) {
			[_selectedRoles removeAllObjects];
			[self selectionChanged];
		}
		return NO;
	}
	NSString *roleId = hit.role.identifier;
	if (extend) {
		if ([_selectedRoles containsObject:roleId]) {
			[_selectedRoles removeObject:roleId];
		} else {
			[_selectedRoles addObject:roleId];
		}
		if (!selected) {
			[_selectedShapes addObject:shapeId];
		}
		[self selectionChanged];
		return YES;
	}
	/* Part of a larger selection: the drag moves it all. */
	if (selected && [_selectedShapes count] == 1 && ![_selectedRoles containsObject:roleId]) {
		[_selectedRoles removeAllObjects];
		[_selectedRoles addObject:roleId];
		[self selectionChanged];
	}
	return NO;
}

- (BOOL)placeTool:(ORMCanvasTool)tool at:(NSPoint)point
{
	switch (tool) {
	case ORMToolEntityType:
	case ORMToolValueType:
		[self createObjectTypeAt:point value:tool == ORMToolValueType];
		return YES;
	case ORMToolNote: {
		NSString *reason = nil;
		NSString *note = [self.editor.elementEditor addNote:@"Note" attachedTo:@[] onDiagram:self.diagramId at:point reason:&reason];
		[self finishTool];
		[self selectElements:note != nil ? @[ note ] : @[]];
		return YES;
	}
	default:
		return NO;
	}
}

#pragma mark Dropped from the Insert palette

- (ORMCanvasTool)droppedTool:(id<NSDraggingInfo>)sender
{
	NSString *text = [[sender draggingPasteboard] stringForType:ORMInsertDragType];
	return text != nil ? (ORMCanvasTool)[text integerValue] : ORMToolPointer;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
	ORMCanvasTool tool = [self droppedTool:sender];
	return tool == ORMToolEntityType || tool == ORMToolValueType || tool == ORMToolNote ? NSDragOperationCopy
	                                                                                  : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
	return [self draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
	return [self placeTool:[self droppedTool:sender] at:[self convertPoint:[sender draggingLocation] fromView:nil]];
}

- (void)finishTool
{
	if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) == 0) {
		self.tool = ORMToolPointer;
	}
}

- (void)createObjectTypeAt:(NSPoint)point value:(BOOL)value
{
	NSString *base = value ? @"ValueType" : @"EntityType";
	NSString *name = base;
	for (NSUInteger i = 1; [self.editor.model objectTypeNamed:name] != nil; i++) {
		name = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)i];
	}
	NSString *reason = nil;
	NSString *created = value
		? [self.editor.objectTypeEditor addValueTypeNamed:name dataType:@"VariableLengthTextDataType" onDiagram:self.diagramId
		                              at:point reason:&reason]
		: [self.editor.objectTypeEditor addEntityTypeNamed:name referenceMode:@"id" kind:ORMReferenceModePopular onDiagram:self.diagramId
		                               at:point reason:&reason];
	if (created == nil) {
		[self refuse:reason];
		return;
	}
	[self finishTool];
	[self selectElements:@[ created ]];
	ORMShape *shape = [[self diagram] shapeForSubject:created];
	if (shape != nil) {
		[self beginRenaming:shape];
	}
}

- (void)factTypeToolDown:(ORMHit *)hit at:(NSPoint)point
{
	if (hit.shape.kind == ORMShapeObjectType) {
		[_pickedPlayers addObject:hit.shape.identifier];
		[self say:[NSString stringWithFormat:@"%lu player%@ picked; click where the fact type goes, or pick more.",
		                                     (unsigned long)[_pickedPlayers count],
		                                     [_pickedPlayers count] == 1 ? @"" : @"s"]];
		return;
	}
	if ([_pickedPlayers count] == 0) {
		[self refuse:@"Click the object types that play the roles, in order, then where the fact type goes."];
		return;
	}
	NSMutableArray *players = [NSMutableArray array];
	for (NSString *shapeId in _pickedPlayers) {
		ORMShape *shape = [self.editor.model elementWithId:shapeId];
		if (shape.objectType != nil) {
			[players addObject:shape.objectType.identifier];
		}
	}
	NSSize size = ORMDefaultFactTypeSize([players count]);
	NSString *reason = nil;
	NSString *fact = [self.editor.factTypeEditor addFactTypeWithPlayers:players reading:nil onDiagram:self.diagramId
	                                                  at:NSMakePoint(point.x - size.width / 2, point.y - size.height / 2)
	                                              reason:&reason];
	[_pickedPlayers removeAllObjects];
	if (fact == nil) {
		[self refuse:reason];
		return;
	}
	[self finishTool];
	[self selectElements:@[ fact ]];
	[self say:@"Type the fact type's reading in the inspector."];
}

- (void)constraintToolDown:(ORMHit *)hit
{
	if (hit.role == nil) {
		[self refuse:@"Click the roles the constraint spans; Option-Tab starts the next sequence, Return finishes."];
		return;
	}
	if ([_picked count] == 0) {
		[_picked addObject:[NSMutableArray array]];
	}
	NSMutableArray *sequence = [_picked lastObject];
	NSString *roleId = hit.role.identifier;
	if ([sequence containsObject:roleId]) {
		[sequence removeObject:roleId];
	} else {
		[sequence addObject:roleId];
	}
	[self setNeedsDisplay:YES];
}

- (void)cancelPending
{
	[_picked removeAllObjects];
	[_pickedPlayers removeAllObjects];
	[self setNeedsDisplay:YES];
}

- (IBAction)nextRoleSequence:(id)sender
{
	(void)sender;
	if ([_picked count] > 0 && [[_picked lastObject] count] > 0) {
		[_picked addObject:[NSMutableArray array]];
		[self say:[NSString stringWithFormat:@"Sequence %lu.", (unsigned long)[_picked count]]];
	}
}

/* Each picked role a sequence of its own, when only one sequence was
 * picked for a constraint that compares several. */
- (NSArray *)sequencesForComparison
{
	NSMutableArray *sequences = [NSMutableArray array];
	for (NSArray *sequence in _picked) {
		if ([sequence count] > 0) {
			[sequences addObject:sequence];
		}
	}
	if ([sequences count] == 1) {
		NSMutableArray *split = [NSMutableArray array];
		for (NSString *roleId in [sequences firstObject]) {
			[split addObject:@[ roleId ]];
		}
		return split;
	}
	return sequences;
}

- (IBAction)commitPending:(id)sender
{
	(void)sender;
	if (self.tool == ORMToolFactType || [_picked count] == 0) {
		return;
	}
	NSMutableArray *all = [NSMutableArray array];
	for (NSArray *sequence in _picked) {
		[all addObjectsFromArray:sequence];
	}
	NSString *reason = nil;
	NSString *created = nil;
	switch (self.tool) {
	case ORMToolUniqueness:
		created = [self.editor.constraintEditor addUniquenessConstraintOverRoles:all reason:&reason];
		break;
	case ORMToolInclusiveOr:
		created = [self.editor.constraintEditor addMandatoryConstraintOverRoles:all reason:&reason];
		break;
	case ORMToolExclusion:
		created = [self.editor.constraintEditor addSetComparisonConstraint:ORMExclusionConstraint sequences:[self sequencesForComparison]
		                                           reason:&reason];
		break;
	case ORMToolExclusiveOr:
		created = [self.editor.constraintEditor addExclusiveOrConstraintOverRoles:all reason:&reason];
		break;
	case ORMToolSubset:
		created = [self.editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint sequences:[self sequencesForComparison]
		                                           reason:&reason];
		break;
	case ORMToolEquality:
		created = [self.editor.constraintEditor addSetComparisonConstraint:ORMEqualityConstraint sequences:[self sequencesForComparison]
		                                           reason:&reason];
		break;
	case ORMToolFrequency:
		created = [self.editor.constraintEditor addFrequencyConstraintOverRoles:all min:2 max:0 reason:&reason];
		break;
	case ORMToolRing:
		created = [self.editor.constraintEditor addRingConstraint:ORMRingIrreflexive overRoles:all reason:&reason];
		break;
	case ORMToolValueComparison:
		created = [self.editor.constraintEditor addValueComparisonConstraint:@"LessThan" overRoles:all reason:&reason];
		break;
	default:
		break;
	}
	if (created == nil) {
		[self refuse:reason];
		return;
	}
	ORMConstraint *constraint = [self.editor.model elementWithId:created];
	if ([constraint isExternal]) {
		[self.editor.diagramEditor placeElement:created onDiagram:self.diagramId at:ORMAutomaticPlacement];
	}
	[_picked removeAllObjects];
	[self finishTool];
	[self selectElements:@[ created ]];
}

- (void)finishSubtype
{
	ORMHit *target = [self hitAt:_at];
	ORMObjectType *sub = _downHit.shape.objectType;
	ORMObjectType *sup = target.shape.objectType ?: target.shape.factType.objectifyingType;
	if (sub == nil || sup == nil || sub == sup) {
		return;
	}
	NSString *reason = nil;
	if ([self.editor.objectTypeEditor addSubtype:sub.identifier of:sup.identifier reason:&reason] == nil) {
		[self refuse:reason];
		return;
	}
	[self finishTool];
}

- (void)finishConnect
{
	ORMHit *target = [self hitAt:_at];
	ORMObjectType *player = target.shape.objectType ?: target.shape.factType.objectifyingType;
	ORMRole *role = _downHit.role;
	if (role == nil || player == nil) {
		return;
	}
	NSString *reason = nil;
	if (![self.editor.factTypeEditor setPlayer:player.identifier ofRole:role.identifier reason:&reason]) {
		[self refuse:reason];
		return;
	}
	[self finishTool];
}

- (IBAction)chooseTool:(id)sender
{
	[self useTool:(ORMCanvasTool)[sender tag]];
}

- (void)useTool:(ORMCanvasTool)tool
{
	self.tool = tool;
	NSDictionary *hints = @{
		@(ORMToolEntityType): @"Click where the entity type goes.",
		@(ORMToolValueType): @"Click where the value type goes.",
		@(ORMToolFactType): @"Click the players in reading order, then where the fact type goes.",
		@(ORMToolSubtype): @"Drag from the subtype to its supertype.",
		@(ORMToolConnectRole): @"Drag from a role box to the object type that plays it.",
		@(ORMToolNote): @"Click where the note goes.",
	};
	NSString *hint = [hints objectForKey:@(self.tool)];
	if (hint == nil && self.tool != ORMToolPointer) {
		hint = @"Click the roles; Option-Tab for the next sequence; Return to finish; Escape to cancel.";
	}
	[self say:hint ?: @""];
	[[self window] makeFirstResponder:self];
}

#pragma mark What the canvas did

/* Dragged or nudged: one move, the editor's, in the order selected. */
- (void)canvas:(DKCanvasView *)canvas moveItems:(NSArray *)items by:(NSSize)delta
{
	(void)canvas;
	NSMutableArray *shapes = [NSMutableArray array];
	for (NSString *shapeId in _selectedShapes) {
		if ([items containsObject:shapeId]) {
			[shapes addObject:shapeId];
		}
	}
	[self.editor.diagramEditor moveShapes:shapes by:delta];
}

- (void)canvas:(DKCanvasView *)canvas doubleClickedItem:(id)item
{
	(void)canvas;
	ORMShape *shape = item != nil ? [self.editor.model elementWithId:item] : nil;
	if (shape.kind == ORMShapeObjectType || shape.kind == ORMShapeModelNote) {
		[self beginRenaming:shape];
	}
}

#pragma mark Renaming

/* An object type's name or a note's text, typed in place over its shape. */
- (void)beginRenaming:(ORMShape *)shape
{
	NSString *text = shape.objectType.name ?: ([shape.subject isKindOfClass:[ORMModelNote class]]
	                                               ? [(ORMModelNote *)shape.subject text] : nil);
	if (text == nil) {
		return;
	}
	[self editTextOfItem:[shape.subject identifier] text:text inRect:NSInsetRect(shape.bounds, -10, 0)
	                font:ORMDiagramFont([self diagram], NO)];
}

- (void)canvas:(DKCanvasView *)canvas didEditTextOfItem:(id)item text:(NSString *)text
{
	(void)canvas;
	id element = [self.editor.model elementWithId:item];
	NSString *reason = nil;
	BOOL done = YES;
	if ([element isKindOfClass:[ORMModelNote class]]) {
		done = [self.editor.elementEditor setNoteText:text of:item reason:&reason];
	} else if (element != nil) {
		done = [self.editor.elementEditor rename:item to:text reason:&reason];
	}
	if (!done) {
		[self refuse:reason];
	}
}

#pragma mark Keys

/* ORM2's keys; the canvas has Space, the arrows and Delete. */
- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event charactersIgnoringModifiers];
	unichar key = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
	NSUInteger flags = [event modifierFlags];
	switch (key) {
	case NSDeleteCharacter:
	case NSBackspaceCharacter:
	case NSDeleteFunctionKey:
		if (flags & NSEventModifierFlagShift) {
			[self removeFromDiagram:nil];
			return;
		}
		break;
	case 27:
		[self cancelPending];
		self.tool = ORMToolPointer;
		[self say:@""];
		return;
	case NSCarriageReturnCharacter:
	case NSEnterCharacter:
		[self commitPending:nil];
		return;
	case NSTabCharacter:
		if (flags & NSEventModifierFlagOption) {
			[self nextRoleSequence:nil];
			return;
		}
		break;
	case 'u':
		if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) == 0) {
			[self toggleUniqueness:nil];
			return;
		}
		break;
	case 'm':
		if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) == 0) {
			[self toggleMandatory:nil];
			return;
		}
		break;
	default:
		break;
	}
	[super keyDown:event];
}

#pragma mark Commands

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	SEL action = [item action];
	if (action == @selector(chooseTool:)) {
		[item setState:[item tag] == self.tool ? NSControlStateValueOn : NSControlStateValueOff];
		return YES;
	}
	if (action == @selector(delete:) || action == @selector(removeFromDiagram:)) {
		return [_selectedShapes count] > 0;
	}
	if (action == @selector(toggleUniqueness:) || action == @selector(toggleMandatory:)) {
		return [_selectedRoles count] > 0;
	}
	if (action == @selector(commitPending:) || action == @selector(nextRoleSequence:)) {
		return [_picked count] > 0;
	}
	if (action == @selector(rotateFactType:) || action == @selector(reverseRoleOrder:)) {
		return [self selectedFactTypeShape] != nil;
	}
	return YES;
}

- (IBAction)delete:(id)sender
{
	(void)sender;
	NSArray *elements = [_selectedRoles count] > 0 ? nil : [self selectedElements];
	if ([elements count] == 0) {
		return;
	}
	/* Deleting a reading's shape means the reading's fact type here; a
	 * diagram's shapes alone go with Remove from Diagram. */
	[self.editor.elementEditor deleteElements:elements];
	[self clearSelection];
}

- (IBAction)removeFromDiagram:(id)sender
{
	(void)sender;
	if ([_selectedShapes count] == 0) {
		return;
	}
	[self.editor.elementEditor deleteElements:[_selectedShapes copy]];
	[self clearSelection];
}

- (IBAction)toggleUniqueness:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	BOOL done = YES;
	if ([_selectedRoles count] == 1) {
		ORMRole *role = [self.editor.model elementWithId:[_selectedRoles firstObject]];
		done = [self.editor.constraintEditor setUnique:!role.isUnique role:role.identifier reason:&reason];
	} else if ([_selectedRoles count] > 1) {
		done = [self.editor.constraintEditor addUniquenessConstraintOverRoles:[_selectedRoles copy] reason:&reason] != nil;
	}
	if (!done) {
		[self refuse:reason];
	}
}

- (IBAction)toggleMandatory:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	BOOL done = YES;
	if ([_selectedRoles count] == 1) {
		ORMRole *role = [self.editor.model elementWithId:[_selectedRoles firstObject]];
		done = [self.editor.constraintEditor setMandatory:!role.isMandatory role:role.identifier reason:&reason];
	} else if ([_selectedRoles count] > 1) {
		NSString *created = [self.editor.constraintEditor addMandatoryConstraintOverRoles:[_selectedRoles copy] reason:&reason];
		done = created != nil;
		if (done) {
			[self.editor.diagramEditor placeElement:created onDiagram:self.diagramId at:ORMAutomaticPlacement];
		}
	}
	if (!done) {
		[self refuse:reason];
	}
}

- (ORMShape *)selectedFactTypeShape
{
	for (NSString *shapeId in _selectedShapes) {
		ORMShape *shape = [self.editor.model elementWithId:shapeId];
		if (shape.kind == ORMShapeFactType) {
			return shape;
		}
	}
	return nil;
}

- (IBAction)rotateFactType:(id)sender
{
	(void)sender;
	ORMShape *shape = [self selectedFactTypeShape];
	if (shape != nil) {
		ORMFactTypeOrientation next = shape.orientation == ORMFactTypeHorizontal ? ORMFactTypeVerticalRotatedRight
			: shape.orientation == ORMFactTypeVerticalRotatedRight ? ORMFactTypeVerticalRotatedLeft
			                                                     : ORMFactTypeHorizontal;
		[self.editor.diagramEditor setOrientation:next ofShape:shape.identifier];
	}
}

- (IBAction)reverseRoleOrder:(id)sender
{
	(void)sender;
	ORMShape *shape = [self selectedFactTypeShape];
	if (shape == nil) {
		return;
	}
	NSMutableArray *order = [NSMutableArray array];
	for (ORMRole *role in [shape.roleDisplayOrder reverseObjectEnumerator]) {
		[order addObject:role.identifier];
	}
	NSString *reason = nil;
	if (![self.editor.diagramEditor setRoleDisplayOrder:order ofShape:shape.identifier reason:&reason]) {
		[self refuse:reason];
	}
}

- (IBAction)zoomToActualSize:(id)sender
{
	(void)sender;
	self.zoom = ORMActualSize;
}

@end
