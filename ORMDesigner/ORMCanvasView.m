/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCanvasView.h"
#import "ORMInsertPalette.h"

/* What a gesture is doing, between mouse down and up. */
typedef NS_ENUM(NSInteger, ORMGesture) {
	ORMGestureNone,
	ORMGestureMove,
	ORMGestureBand,
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

@implementation ORMCanvasView
{
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
	NSTextField *_renamer;
	NSString *_renaming;
	NSRect _canvasRect;
	BOOL _printing;
}

- (void)setUp
{
	_selectedShapes = [NSMutableArray array];
	_selectedRoles = [NSMutableArray array];
	_picked = [NSMutableArray array];
	_pickedPlayers = [NSMutableArray array];
	_zoom = 1.5;
	[self addTrackingRect:[self bounds] owner:self userData:NULL assumeInside:NO];
	/* What the Insert palette drags here. */
	[self registerForDraggedTypes:@[ ORMInsertDragType ]];
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		[self setUp];
	}
	return self;
}

/* From the document window's XIB, which does not call -initWithFrame:. */
- (void)awakeFromNib
{
	[super awakeFromNib];
	[self setUp];
}

- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)isOpaque
{
	return YES;
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
	(void)event;
	return YES;
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
		[self resize];
	}
}

- (void)setTool:(ORMCanvasTool)tool
{
	_tool = tool;
	[self cancelPending];
	[self.delegate canvasToolDidChange:self];
	[self setNeedsDisplay:YES];
}

- (void)setZoom:(double)zoom
{
	_zoom = MIN(MAX(zoom, 0.25), 6.0);
	[self resize];
}

#pragma mark Geometry

- (void)resize
{
	ORMDiagram *diagram = [self diagram];
	NSRect drawing = diagram != nil ? ORMDrawingBounds(diagram) : NSMakeRect(0, 0, 400, 300);
	NSRect area = NSUnionRect(drawing, NSMakeRect(0, 0, 1, 1));
	area.size.width += ORMCanvasMargin;
	area.size.height += ORMCanvasMargin;
	/* At least the visible area, so a small diagram can grow anywhere in it. */
	NSSize visible = [[self enclosingScrollView] contentSize];
	area.size.width = MAX(area.size.width, visible.width / self.zoom);
	area.size.height = MAX(area.size.height, visible.height / self.zoom);
	_canvasRect = area;
	[self setFrameSize:NSMakeSize(ceil(NSWidth(area) * self.zoom), ceil(NSHeight(area) * self.zoom))];
	[self setBoundsOrigin:area.origin];
	[self setBoundsSize:area.size];
	[self setNeedsDisplay:YES];
}

- (NSPoint)pointOf:(NSEvent *)event
{
	return [self convertPoint:[event locationInWindow] fromView:nil];
}

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

- (void)selectionChanged
{
	[self setNeedsDisplay:YES];
	[self.delegate canvasSelectionDidChange:self];
}

- (void)clearSelection
{
	[_selectedShapes removeAllObjects];
	[_selectedRoles removeAllObjects];
	[self selectionChanged];
}

- (void)selectElements:(NSArray<NSString *> *)elementIds
{
	[_selectedShapes removeAllObjects];
	[_selectedRoles removeAllObjects];
	ORMDiagram *diagram = [self diagram];
	for (NSString *elementId in elementIds) {
		id element = [self.editor.model elementWithId:elementId];
		if ([element isKindOfClass:[ORMRole class]]) {
			[_selectedRoles addObject:elementId];
			ORMShape *shape = [diagram shapeForSubject:[(ORMRole *)element factType].identifier];
			if (shape != nil && ![_selectedShapes containsObject:shape.identifier]) {
				[_selectedShapes addObject:shape.identifier];
			}
			continue;
		}
		ORMShape *shape = [diagram shapeForSubject:elementId];
		if (shape != nil && ![_selectedShapes containsObject:shape.identifier]) {
			[_selectedShapes addObject:shape.identifier];
		}
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
	[self resize];
}

#pragma mark Drawing

- (void)drawRect:(NSRect)dirty
{
	[ORMPaperColor() setFill];
	NSRectFill(dirty);
	ORMDiagram *diagram = [self diagram];
	if (diagram == nil) {
		return;
	}
	ORMDrawingState *state = [[ORMDrawingState alloc] init];
	state.selectedShapes = [NSSet setWithArray:_selectedShapes];
	state.selectedRoles = [NSSet setWithArray:_selectedRoles];
	state.pickedSequences = _picked;
	state.hoverElement = _hover;
	state.forPrinting = _printing;
	ORMDrawDiagram(diagram, dirty, state);
	if (_printing) {
		return;
	}
	[self drawPickedPlayers:diagram];
	[self drawGesture];
}

- (void)drawPickedPlayers:(ORMDiagram *)diagram
{
	for (NSUInteger i = 0; i < [_pickedPlayers count]; i++) {
		ORMShape *shape = [self.editor.model elementWithId:[_pickedPlayers objectAtIndex:i]];
		if (shape == nil) {
			continue;
		}
		NSRect badge = NSMakeRect(NSMaxX(shape.bounds) - 4, NSMinY(shape.bounds) - 6, 10, 10);
		[ORMPickColor() setFill];
		[[NSBezierPath bezierPathWithOvalInRect:badge] fill];
		NSDictionary *attributes = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:7],
		                              NSForegroundColorAttributeName: [NSColor whiteColor] };
		NSString *number = [NSString stringWithFormat:@"%lu", (unsigned long)i + 1];
		NSSize size = [number sizeWithAttributes:attributes];
		[number drawAtPoint:NSMakePoint(NSMidX(badge) - size.width / 2, NSMidY(badge) - size.height / 2)
		     withAttributes:attributes];
	}
	(void)diagram;
}

- (void)drawGesture
{
	NSColor *color = ORMSelectionColor();
	switch (_gesture) {
	case ORMGestureMove: {
		NSSize delta = NSMakeSize(_at.x - _down.x, _at.y - _down.y);
		for (NSString *shapeId in _selectedShapes) {
			ORMShape *shape = [self.editor.model elementWithId:shapeId];
			NSRect moved = NSOffsetRect(shape.bounds, delta.width, delta.height);
			NSBezierPath *path = [NSBezierPath bezierPathWithRect:moved];
			CGFloat pattern[2] = { 3.0, 2.0 };
			[path setLineDash:pattern count:2 phase:0];
			[color setStroke];
			[path setLineWidth:0.8];
			[path stroke];
		}
		break;
	}
	case ORMGestureBand: {
		NSRect band = NSMakeRect(MIN(_down.x, _at.x), MIN(_down.y, _at.y), fabs(_at.x - _down.x), fabs(_at.y - _down.y));
		[[color colorWithAlphaComponent:0.12] setFill];
		NSRectFillUsingOperation(band, NSCompositingOperationSourceOver);
		[color setStroke];
		NSBezierPath *path = [NSBezierPath bezierPathWithRect:band];
		[path setLineWidth:0.6];
		[path stroke];
		break;
	}
	case ORMGestureSubtype:
	case ORMGestureConnect: {
		NSBezierPath *path = [NSBezierPath bezierPath];
		[path moveToPoint:_down];
		[path lineToPoint:_at];
		[color setStroke];
		[path setLineWidth:1.2];
		[path stroke];
		break;
	}
	case ORMGestureNone:
		break;
	}
}

#pragma mark Saying

- (void)say:(NSString *)message
{
	[self.delegate canvas:self say:message ?: @""];
}

- (void)refuse:(NSString *)reason
{
	NSBeep();
	[self say:reason];
}

#pragma mark Mouse

- (void)mouseDown:(NSEvent *)event
{
	[[self window] makeFirstResponder:self];
	[self endRenaming];
	NSPoint point = [self pointOf:event];
	_down = point;
	_at = point;
	ORMHit *hit = [self hitAt:point];
	_downHit = hit;
	BOOL extend = ([event modifierFlags] & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) != 0;
	if ([event clickCount] == 2 && hit != nil) {
		[self doubleClick:hit];
		return;
	}
	switch (self.tool) {
	case ORMToolPointer:
		[self pointerDown:hit extend:extend];
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

- (void)pointerDown:(ORMHit *)hit extend:(BOOL)extend
{
	if (hit == nil) {
		if (!extend) {
			[_selectedShapes removeAllObjects];
			[_selectedRoles removeAllObjects];
			[self selectionChanged];
		}
		_gesture = ORMGestureBand;
		return;
	}
	NSString *shapeId = hit.shape.identifier;
	if (hit.role != nil) {
		NSString *roleId = hit.role.identifier;
		if (extend) {
			if ([_selectedRoles containsObject:roleId]) {
				[_selectedRoles removeObject:roleId];
			} else {
				[_selectedRoles addObject:roleId];
			}
		} else if (![_selectedRoles containsObject:roleId]) {
			[_selectedRoles removeAllObjects];
			[_selectedRoles addObject:roleId];
			[_selectedShapes removeAllObjects];
		}
		if (![_selectedShapes containsObject:shapeId]) {
			[_selectedShapes addObject:shapeId];
		}
		[self selectionChanged];
		_gesture = ORMGestureMove;
		return;
	}
	if (extend) {
		if ([_selectedShapes containsObject:shapeId]) {
			[_selectedShapes removeObject:shapeId];
		} else {
			[_selectedShapes addObject:shapeId];
		}
	} else if (![_selectedShapes containsObject:shapeId]) {
		[_selectedShapes removeAllObjects];
		[_selectedShapes addObject:shapeId];
	}
	[_selectedRoles removeAllObjects];
	[self selectionChanged];
	_gesture = ORMGestureMove;
}

- (void)mouseDragged:(NSEvent *)event
{
	_at = [self pointOf:event];
	[self autoscroll:event];
	if (_gesture == ORMGestureConnect || _gesture == ORMGestureSubtype) {
		ORMHit *hit = [self hitAt:_at];
		_hover = hit.shape.objectType.identifier;
	}
	[self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
	_at = [self pointOf:event];
	ORMGesture gesture = _gesture;
	_gesture = ORMGestureNone;
	_hover = nil;
	switch (gesture) {
	case ORMGestureMove: {
		NSSize delta = NSMakeSize(round(_at.x - _down.x), round(_at.y - _down.y));
		if (fabs(delta.width) >= 1 || fabs(delta.height) >= 1) {
			[self.editor.diagramEditor moveShapes:[_selectedShapes copy] by:delta];
		}
		break;
	}
	case ORMGestureBand:
		[self selectInBand];
		break;
	case ORMGestureSubtype:
		[self finishSubtype];
		break;
	case ORMGestureConnect:
		[self finishConnect];
		break;
	case ORMGestureNone:
		break;
	}
	[self setNeedsDisplay:YES];
}

- (void)selectInBand
{
	NSRect band = NSMakeRect(MIN(_down.x, _at.x), MIN(_down.y, _at.y), fabs(_at.x - _down.x), fabs(_at.y - _down.y));
	if (NSWidth(band) < 2 && NSHeight(band) < 2) {
		return;
	}
	for (ORMShape *shape in [self diagram].shapes) {
		if (NSIntersectsRect(band, shape.bounds) && ![_selectedShapes containsObject:shape.identifier]) {
			[_selectedShapes addObject:shape.identifier];
		}
	}
	[self selectionChanged];
}

- (void)finishTool
{
	if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) == 0) {
		self.tool = ORMToolPointer;
	}
}

#pragma mark Tools

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

#pragma mark Renaming

- (void)doubleClick:(ORMHit *)hit
{
	if (hit.shape.kind == ORMShapeObjectType) {
		[self beginRenaming:hit.shape];
	} else if (hit.shape.kind == ORMShapeModelNote) {
		[self beginRenaming:hit.shape];
	}
}

- (void)beginRenaming:(ORMShape *)shape
{
	[self endRenaming];
	NSString *text = shape.objectType.name ?: ([shape.subject isKindOfClass:[ORMModelNote class]]
	                                               ? [(ORMModelNote *)shape.subject text] : nil);
	if (text == nil) {
		return;
	}
	NSRect frame = NSInsetRect(shape.bounds, -10, 0);
	frame.size.height = MAX(NSHeight(frame), 14);
	_renamer = [[NSTextField alloc] initWithFrame:frame];
	[_renamer setStringValue:text];
	[_renamer setFont:ORMDiagramFont([self diagram], NO)];
	[_renamer setAlignment:NSTextAlignmentCenter];
	[_renamer setTarget:self];
	[_renamer setAction:@selector(renamerDone:)];
	_renaming = [[shape.subject identifier] copy];
	[self addSubview:_renamer];
	[self scrollRectToVisible:NSInsetRect(frame, -20, -20)];
	[[self window] makeFirstResponder:_renamer];
	[_renamer selectText:nil];
}

- (void)renamerDone:(id)sender
{
	(void)sender;
	[self endRenaming];
	[[self window] makeFirstResponder:self];
}

- (void)endRenaming
{
	if (_renamer == nil) {
		return;
	}
	NSString *text = [_renamer stringValue];
	NSString *target = _renaming;
	[_renamer removeFromSuperview];
	_renamer = nil;
	_renaming = nil;
	id element = [self.editor.model elementWithId:target];
	NSString *reason = nil;
	BOOL done = YES;
	if ([element isKindOfClass:[ORMModelNote class]]) {
		if (![text isEqualToString:[(ORMModelNote *)element text]]) {
			done = [self.editor.elementEditor setNoteText:text of:target reason:&reason];
		}
	} else if (element != nil && ![text isEqualToString:[(ORMElement *)element name]]) {
		done = [self.editor.elementEditor rename:target to:text reason:&reason];
	}
	if (!done) {
		[self refuse:reason];
	}
}

#pragma mark Keys

- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event charactersIgnoringModifiers];
	unichar key = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
	NSUInteger flags = [event modifierFlags];
	double step = (flags & NSEventModifierFlagShift) ? 10 : 1;
	switch (key) {
	case NSDeleteCharacter:
	case NSBackspaceCharacter:
	case NSDeleteFunctionKey:
		if (flags & NSEventModifierFlagShift) {
			[self removeFromDiagram:nil];
		} else {
			[self delete:nil];
		}
		return;
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
	case NSLeftArrowFunctionKey:
		[self nudge:NSMakeSize(-step, 0)];
		return;
	case NSRightArrowFunctionKey:
		[self nudge:NSMakeSize(step, 0)];
		return;
	case NSUpArrowFunctionKey:
		[self nudge:NSMakeSize(0, -step)];
		return;
	case NSDownArrowFunctionKey:
		[self nudge:NSMakeSize(0, step)];
		return;
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

- (void)nudge:(NSSize)delta
{
	if ([_selectedShapes count] > 0) {
		[self.editor.diagramEditor moveShapes:[_selectedShapes copy] by:delta];
	}
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

- (IBAction)selectAll:(id)sender
{
	(void)sender;
	[_selectedShapes removeAllObjects];
	for (ORMShape *shape in [self diagram].shapes) {
		[_selectedShapes addObject:shape.identifier];
	}
	[_selectedRoles removeAllObjects];
	[self selectionChanged];
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

#pragma mark Zoom

- (IBAction)zoomIn:(id)sender
{
	(void)sender;
	self.zoom = self.zoom * 1.25;
}

- (IBAction)zoomOut:(id)sender
{
	(void)sender;
	self.zoom = self.zoom / 1.25;
}

- (IBAction)zoomToActualSize:(id)sender
{
	(void)sender;
	self.zoom = 1.5;
}

- (IBAction)zoomToFit:(id)sender
{
	(void)sender;
	ORMDiagram *diagram = [self diagram];
	NSSize visible = [[self enclosingScrollView] contentSize];
	NSRect drawing = diagram != nil ? ORMDrawingBounds(diagram) : NSZeroRect;
	if (NSWidth(drawing) > 0 && NSHeight(drawing) > 0) {
		self.zoom = MIN(visible.width / NSWidth(drawing), visible.height / NSHeight(drawing));
		[self scrollPoint:drawing.origin];
	}
}

- (void)scrollWheel:(NSEvent *)event
{
	if ([event modifierFlags] & NSEventModifierFlagCommand) {
		self.zoom = self.zoom * ([event deltaY] > 0 ? 1.1 : 1 / 1.1);
		return;
	}
	[super scrollWheel:event];
}

#pragma mark Exporting

- (NSData *)PDFData
{
	ORMDiagram *diagram = [self diagram];
	if (diagram == nil) {
		return nil;
	}
	_printing = YES;
	NSData *data = [self dataWithPDFInsideRect:ORMDrawingBounds(diagram)];
	_printing = NO;
	[self setNeedsDisplay:YES];
	return data;
}

- (NSData *)PNGDataAtScale:(double)scale
{
	ORMDiagram *diagram = [self diagram];
	if (diagram == nil) {
		return nil;
	}
	double zoom = self.zoom;
	self.zoom = scale;
	_printing = YES;
	NSRect area = ORMDrawingBounds(diagram);
	NSBitmapImageRep *bitmap = nil;
#if defined(__APPLE__)
	bitmap = [self bitmapImageRepForCachingDisplayInRect:area];
	[self cacheDisplayInRect:area toBitmapImageRep:bitmap];
#else
	/* gnustep-gui's offscreen cache of a view is empty: draw it in its
	 * window and read the window back. */
	[self display];
	[self lockFocus];
	bitmap = [[NSBitmapImageRep alloc] initWithFocusedViewRect:area];
	[self unlockFocus];
#endif
	_printing = NO;
	self.zoom = zoom;
	return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

@end
