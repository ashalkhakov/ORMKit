/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMDiagramPainter.h"
#import <float.h>
#import <math.h>
#import <stdlib.h>

const NSPoint ORMAutomaticPlacement = { NAN, NAN };

BOOL
ORMIsAutomaticPlacement(NSPoint point)
{
	return isnan(point.x) || isnan(point.y);
}

/* NORMA's shape sizes, in points. */
static const double ORMConstraintShapeSize = 0.16 * 72.0;
static const double ORMRingShapeSize = 0.213333333 * 72.0;
static const double ORMReadingShapeHeight = 0.1295030266046524 * 72.0;
/* The gap between a fact type's boxes and its reading below them. */
static const double ORMReadingGap = 0.0647 * 72.0;
/* Room between shapes when the editor places them. */
static const double ORMSpacing = 0.5 * 72.0;

@implementation ORMDiagramEditor

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

#pragma mark Shapes

/* A new shape for the subject, inside a model change: on the diagram, or
 * placed on its parent. */
- (ORMShape *)addShape:(ORMShapeKind)kind
                    of:(ORMElement *)subject
                bounds:(NSRect)bounds
                parent:(ORMShape *)parent
                    on:(ORMDiagram *)diagram
{
	ORMShape *shape = [[ORMShape alloc] initWithModel:_editor.model];
	shape.kind = kind;
	shape.bounds = bounds;
	shape.isExpanded = YES;
	shape.subjectId = subject.identifier;
	shape.subject = subject;
	shape.parent = parent;
	shape.relativeShapes = @[];
	shape.roleDisplayOrder = @[];
	[diagram addShape:shape];
	[_editor wrote:shape];
	return shape;
}

/* NORMA's role name shape: a point above the role's box. */
static const double ORMRoleNameSize = 0.05 * 72.0;
static const double ORMRoleNameRise = 0.17 * 72.0;

- (void)showNameOfRole:(ORMRole *)role onShape:(ORMShape *)factShape
{
	ORMShape *shown = nil;
	for (ORMShape *child in factShape.relativeShapes) {
		if (child.kind == ORMShapeRoleName && child.subject == role) {
			shown = child;
		}
	}
	if ([role.name length] == 0) {
		if (shown != nil) {
			[self removeShapes:@[ shown ]];
		}
		return;
	}
	if (shown == nil) {
		NSRect box = ORMRoleBox(factShape, role);
		NSRect bounds = NSMakeRect(NSMinX(box) + 0.25 * NSWidth(box), NSMinY(box) - ORMRoleNameRise, ORMRoleNameSize,
		                           ORMRoleNameSize);
		[self addShape:ORMShapeRoleName of:role bounds:bounds parent:factShape on:factShape.diagram];
	}
}

- (void)showNameOfRole:(ORMRole *)role
{
	for (ORMDiagram *diagram in _editor.model.diagrams) {
		for (ORMShape *shape in [diagram allShapes]) {
			if (shape.kind == ORMShapeFactType && shape.subject == role.factType) {
				[self showNameOfRole:role onShape:shape];
			}
		}
	}
}

- (ORMDiagram *)diagramWithId:(NSString *)diagramId
{
	ORMDiagram *diagram = [_editor.model elementWithId:diagramId];
	return [diagram isKindOfClass:[ORMDiagram class]] ? diagram : nil;
}

/* Where the object type is drawn on the diagram: its own shape, or the
 * fact type it objectifies, whose outline its roles are drawn to. */
static ORMShape *
ORMPlayerShape(ORMObjectType *type, ORMDiagram *diagram)
{
	ORMShape *shape = [diagram shapeForSubject:type.identifier];
	if (shape == nil && type.nestedFactType != nil) {
		shape = [diagram shapeForSubject:type.nestedFactType.identifier];
	}
	return shape;
}

/* The shapes on the diagram the element is linked to: a fact type's
 * players, an object type's fact types, a constraint's fact types. An
 * objectified fact type is linked as its objectifying type is too. */
- (NSArray<ORMShape *> *)linkedShapesOf:(id)element on:(ORMDiagram *)diagram
{
	NSMutableArray *linked = [NSMutableArray array];
	NSMutableArray *subjects = [NSMutableArray array];
	if ([element isKindOfClass:[ORMFactType class]]) {
		for (ORMRole *role in [(ORMFactType *)element visibleRoles]) {
			ORMShape *player = role.player != nil ? ORMPlayerShape(role.player, diagram) : nil;
			if (player != nil) {
				[linked addObject:player];
			}
		}
		ORMObjectType *objectifying = [(ORMFactType *)element objectifyingType];
		if (objectifying != nil && [diagram shapeForSubject:objectifying.identifier] == nil) {
			for (ORMRole *role in [objectifying playedRoles]) {
				[subjects addObject:role.factType.identifier ?: @""];
			}
		}
	} else if ([element isKindOfClass:[ORMObjectType class]]) {
		for (ORMRole *role in [(ORMObjectType *)element playedRoles]) {
			[subjects addObject:role.factType.identifier ?: @""];
		}
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		for (ORMFactType *fact in [(ORMConstraint *)element factTypes]) {
			[subjects addObject:fact.identifier];
		}
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		for (ORMElement *referenced in [(ORMModelNote *)element referencedElements]) {
			[subjects addObject:referenced.identifier];
		}
	}
	for (NSString *subject in subjects) {
		ORMShape *shape = [diagram shapeForSubject:subject];
		if (shape != nil) {
			[linked addObject:shape];
		}
	}
	return linked;
}

/* Whether the rectangle is clear of the diagram's top-level shapes. */
static BOOL
ORMIsFree(ORMDiagram *diagram, NSRect rect, NSArray<NSValue *> *taken)
{
	NSRect padded = NSInsetRect(rect, -4, -4);
	for (ORMShape *shape in diagram.shapes) {
		if (NSIntersectsRect(padded, shape.bounds)) {
			return NO;
		}
	}
	for (NSValue *value in taken) {
		if (NSIntersectsRect(padded, [value rectValue])) {
			return NO;
		}
	}
	return YES;
}

/* A free spot for a shape of the size near the centre, spiralling out. */
static NSPoint
ORMFreeSpotNear(ORMDiagram *diagram, NSPoint center, NSSize size, NSArray<NSValue *> *taken)
{
	for (NSUInteger ring = 0; ring < 40; ring++) {
		NSUInteger steps = ring == 0 ? 1 : ring * 8;
		for (NSUInteger step = 0; step < steps; step++) {
			double angle = 2 * M_PI * step / steps;
			double radius = ring * ORMSpacing * 0.6;
			NSPoint origin = NSMakePoint(round(center.x + radius * cos(angle) - size.width / 2),
			                             round(center.y + radius * sin(angle) - size.height / 2));
			if (origin.x < 0 || origin.y < 0) {
				continue;
			}
			NSRect rect = NSMakeRect(origin.x, origin.y, size.width, size.height);
			if (ORMIsFree(diagram, rect, taken)) {
				return origin;
			}
		}
	}
	return NSMakePoint(center.x, center.y);
}

- (NSPoint)placeFor:(NSString *)elementId onDiagram:(NSString *)diagramId
{
	ORMDiagram *diagram = [self diagramWithId:diagramId];
	id element = [_editor.model elementWithId:elementId];
	NSArray *linked = [self linkedShapesOf:element on:diagram];
	NSPoint center;
	if ([linked count] > 0) {
		double x = 0;
		double y = 0;
		for (ORMShape *shape in linked) {
			x += NSMidX(shape.bounds);
			y += NSMidY(shape.bounds);
		}
		center = NSMakePoint(x / [linked count], y / [linked count]);
	} else {
		NSRect extent = [diagram extent];
		center = NSIsEmptyRect(extent) ? NSMakePoint(1.5 * 72, 1 * 72)
		                               : NSMakePoint(NSMaxX(extent) + ORMSpacing * 2, NSMinY(extent) + ORMSpacing);
	}
	return center;
}

- (NSSize)defaultSizeOf:(id)element
{
	if ([element isKindOfClass:[ORMObjectType class]]) {
		ORMObjectType *type = element;
		return ORMDefaultObjectTypeSize([type displayName], type.referenceMode != nil);
	}
	if ([element isKindOfClass:[ORMFactType class]]) {
		return ORMDefaultFactTypeSize([[(ORMFactType *)element visibleRoles] count]);
	}
	if ([element isKindOfClass:[ORMConstraint class]]) {
		double side = [(ORMConstraint *)element kind] == ORMRingConstraint ? ORMRingShapeSize : ORMConstraintShapeSize;
		return NSMakeSize(side, side);
	}
	if ([element isKindOfClass:[ORMModelNote class]]) {
		NSString *text = [(ORMModelNote *)element text];
		return NSMakeSize(MIN(3.0, 0.055 * [text length] + 0.15) * 72.0, 0.1415 * 72.0);
	}
	return NSMakeSize(0.5 * 72, 0.25 * 72);
}

- (NSString *)placeElement:(NSString *)elementId onDiagram:(NSString *)diagramId at:(NSPoint)point
{
	ORMShape *existing = [[self diagramWithId:diagramId] shapeForSubject:elementId];
	if (existing != nil) {
		return existing.identifier;
	}
	return [self newShapeOf:elementId onDiagram:diagramId at:point];
}

- (NSString *)addShapeOfElement:(NSString *)elementId onDiagram:(NSString *)diagramId at:(NSPoint)point
{
	id element = [_editor.model elementWithId:elementId];
	if (![element isKindOfClass:[ORMObjectType class]] && ![element isKindOfClass:[ORMFactType class]]) {
		return nil;
	}
	return [self newShapeOf:elementId onDiagram:diagramId at:point];
}

- (NSString *)newShapeOf:(NSString *)elementId onDiagram:(NSString *)diagramId at:(NSPoint)point
{
	ORMDiagram *diagram = [self diagramWithId:diagramId];
	id element = [_editor.model elementWithId:elementId];
	if (diagram == nil || element == nil) {
		return nil;
	}
	ORMShape *existing = [diagram shapeForSubject:elementId];
	ORMShapeKind kind = ORMShapeUnknown;
	if ([element isKindOfClass:[ORMObjectType class]]) {
		if ([(ORMObjectType *)element isImplicitBooleanValue]) {
			return nil;
		}
		kind = ORMShapeObjectType;
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		if ([(ORMFactType *)element kind] != ORMFactTypeOrdinary) {
			return nil;
		}
		kind = ORMShapeFactType;
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		ORMConstraint *constraint = element;
		if (![constraint isExternal] || constraint.isImplied) {
			return nil;
		}
		kind = constraint.kind == ORMFrequencyConstraint ? ORMShapeFrequencyConstraint
			: constraint.kind == ORMRingConstraint ? ORMShapeRingConstraint
			: constraint.kind == ORMValueComparisonConstraint ? ORMShapeValueComparisonConstraint
			: ORMShapeExternalConstraint;
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		kind = ORMShapeModelNote;
	} else {
		return nil;
	}
	NSSize size = [self defaultSizeOf:element];
	NSPoint origin = point;
	if (ORMIsAutomaticPlacement(point)) {
		/* Another shape: beside the first, clear of it. */
		NSPoint near = existing != nil ? NSMakePoint(NSMaxX(existing.bounds) + ORMSpacing + size.width / 2, NSMidY(existing.bounds))
		                               : [self placeFor:elementId onDiagram:diagramId];
		origin = ORMFreeSpotNear(diagram, near, size, @[]);
	}
	NSRect bounds = NSMakeRect(origin.x, origin.y, size.width, size.height);
	__block NSString *created = nil;
	[_editor modelChange:existing != nil ? @"Add Another Shape" : @"Place on Diagram" with:^{
		ORMShape *shape = [self addShape:kind of:element bounds:bounds parent:nil on:diagram];
		if ([element isKindOfClass:[ORMFactType class]]) {
			ORMFactType *fact = element;
			shape.roleDisplayOrder = fact.roles;
			ORMReadingOrder *order = [[fact primaryReading] readingOrder];
			if (order != nil) {
				NSString *text = [[fact primaryReading] expandedText];
				NSRect readingBounds = NSMakeRect(NSMinX(bounds), NSMaxY(bounds) + ORMReadingGap,
				                                  MAX(0.2, 0.05 * [text length]) * 72.0, ORMReadingShapeHeight);
				[self addShape:ORMShapeReading of:order bounds:readingBounds parent:shape on:diagram];
			}
			for (ORMRole *role in fact.roles) {
				[self showNameOfRole:role onShape:shape];
			}
		}
		created = shape.identifier;
	}];
	return created;
}

- (void)showFactType:(NSString *)factTypeId onDiagram:(NSString *)diagramId at:(NSPoint)point
{
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
	[_editor group:@"Add Fact Type" with:^{
		for (ORMRole *role in [fact visibleRoles]) {
			if (role.player != nil && ORMPlayerShape(role.player, [self diagramWithId:diagramId]) == nil) {
				[self placeElement:role.player.identifier onDiagram:diagramId at:ORMAutomaticPlacement];
			}
		}
		[self placeElement:factTypeId onDiagram:diagramId at:point];
	}];
}

- (void)removeShapes:(NSArray<ORMShape *> *)shapes
{
	for (ORMShape *shape in shapes) {
		if ([_editor.model elementWithId:shape.identifier] == shape) {
			for (ORMShape *carried in [self movedShapes:@[ shape.identifier ]]) {
				[_editor deleted:carried];
			}
			[shape.diagram removeShape:shape];
		}
	}
}

#pragma mark Diagrams

- (NSString *)addDiagramNamed:(NSString *)name
{
	__block NSString *created = nil;
	[_editor modelChange:@"Add Diagram" with:^{
		ORMDiagram *diagram = [[ORMDiagram alloc] initWithModel:_editor.model];
		diagram.name = [name length] > 0 ? name : [self nextDiagramName];
		diagram.baseFontName = @"Tahoma";
		/* NORMA's base size, in points as it reads. */
		diagram.baseFontSize = [@"0.0972222238779068" doubleValue] * ORMPointsPerInch;
		diagram.shapes = @[];
		[_editor.model addDiagram:diagram];
		[_editor wrote:diagram];
		created = diagram.identifier;
	}];
	return created;
}

- (NSString *)nextDiagramName
{
	NSMutableSet *names = [NSMutableSet set];
	for (ORMDiagram *diagram in _editor.model.diagrams) {
		[names addObject:diagram.name];
	}
	for (NSUInteger i = 1;; i++) {
		NSString *name = [NSString stringWithFormat:@"Diagram%lu", (unsigned long)i];
		if (![names containsObject:name]) {
			return name;
		}
	}
}

/* The shapes and every shape placed relative to them, once each. */
- (NSArray<ORMShape *> *)movedShapes:(NSArray<NSString *> *)shapeIds
{
	NSMutableArray *moved = [NSMutableArray array];
	NSMutableArray *pending = [NSMutableArray array];
	NSSet *named = [NSSet setWithArray:shapeIds];
	for (NSString *shapeId in shapeIds) {
		ORMShape *shape = [_editor.model elementWithId:shapeId];
		if (![shape isKindOfClass:[ORMShape class]]) {
			continue;
		}
		/* A shape whose parent moves moves with it. */
		BOOL carried = NO;
		for (ORMShape *parent = shape.parent; parent != nil; parent = parent.parent) {
			if ([named containsObject:parent.identifier]) {
				carried = YES;
			}
		}
		if (!carried) {
			[pending addObject:shape];
		}
	}
	while ([pending count] > 0) {
		ORMShape *shape = [pending lastObject];
		[pending removeLastObject];
		[moved addObject:shape];
		[pending addObjectsFromArray:shape.relativeShapes];
	}
	return moved;
}

- (void)moveShapes:(NSArray<NSString *> *)shapeIds by:(NSSize)delta
{
	NSArray *moved = [self movedShapes:shapeIds];
	if ([moved count] == 0 || (delta.width == 0 && delta.height == 0)) {
		return;
	}
	[_editor modelChange:@"Move" with:^{
		for (ORMShape *shape in moved) {
			shape.bounds = NSOffsetRect(shape.bounds, delta.width, delta.height);
			[_editor wrote:shape];
		}
	}];
}

- (BOOL)alignShapes:(NSArray<NSString *> *)shapeIds as:(ORMAlignment)alignment reason:(NSString **)reason
{
	NSMutableArray<ORMShape *> *shapes = [NSMutableArray array];
	for (NSString *shapeId in shapeIds) {
		ORMShape *shape = [_editor.model elementWithId:shapeId];
		if ([shape isKindOfClass:[ORMShape class]] && ![shapes containsObject:shape]) {
			[shapes addObject:shape];
		}
	}
	BOOL distributes = alignment == ORMDistributeAcross || alignment == ORMDistributeDown;
	if ([shapes count] < (distributes ? 3u : 2u)) {
		if (reason != NULL) {
			*reason = distributes ? @"Select three shapes or more to space evenly." : @"Select two shapes or more to align.";
		}
		return NO;
	}
	/* Where each goes: its offset. */
	NSMutableArray<NSValue *> *deltas = [NSMutableArray array];
	ORMShape *first = [shapes firstObject];
	double minX = INFINITY, maxX = -INFINITY, minY = INFINITY, maxY = -INFINITY;
	for (ORMShape *shape in shapes) {
		minX = MIN(minX, NSMinX(shape.bounds));
		maxX = MAX(maxX, NSMaxX(shape.bounds));
		minY = MIN(minY, NSMinY(shape.bounds));
		maxY = MAX(maxY, NSMaxY(shape.bounds));
	}
	NSArray *order = shapes;
	if (distributes) {
		BOOL across = alignment == ORMDistributeAcross;
		order = [shapes sortedArrayUsingComparator:^NSComparisonResult(ORMShape *a, ORMShape *b) {
			double p = across ? NSMidX(a.bounds) : NSMidY(a.bounds);
			double q = across ? NSMidX(b.bounds) : NSMidY(b.bounds);
			return p < q ? NSOrderedAscending : (p > q ? NSOrderedDescending : NSOrderedSame);
		}];
	}
	for (NSUInteger i = 0; i < [order count]; i++) {
		NSRect bounds = [[order objectAtIndex:i] bounds];
		NSSize delta = NSZeroSize;
		switch (alignment) {
		case ORMAlignLeft:
			delta.width = minX - NSMinX(bounds);
			break;
		case ORMAlignRight:
			delta.width = maxX - NSMaxX(bounds);
			break;
		case ORMAlignTop:
			delta.height = minY - NSMinY(bounds);
			break;
		case ORMAlignBottom:
			delta.height = maxY - NSMaxY(bounds);
			break;
		case ORMAlignCentres:
			delta.width = NSMidX(first.bounds) - NSMidX(bounds);
			break;
		case ORMAlignMiddles:
			delta.height = NSMidY(first.bounds) - NSMidY(bounds);
			break;
		case ORMDistributeAcross:
		case ORMDistributeDown: {
			BOOL across = alignment == ORMDistributeAcross;
			double start = across ? NSMidX([[order firstObject] bounds]) : NSMidY([[order firstObject] bounds]);
			double end = across ? NSMidX([[order lastObject] bounds]) : NSMidY([[order lastObject] bounds]);
			double at = start + (end - start) * (double)i / (double)([order count] - 1);
			if (across) {
				delta.width = at - NSMidX(bounds);
			} else {
				delta.height = at - NSMidY(bounds);
			}
			break;
		}
		}
		[deltas addObject:[NSValue valueWithSize:delta]];
	}
	NSArray *names = @[ @"Align Left Edges", @"Align Right Edges", @"Align Tops", @"Align Bottoms", @"Align Centres",
		                @"Align Middles", @"Distribute Across", @"Distribute Down" ];
	/* Each shape and what it carries, where it goes: worked out before the
	 * change, from the model as it is. */
	NSMutableArray *moves = [NSMutableArray array];
	for (NSUInteger i = 0; i < [order count]; i++) {
		NSSize delta = [[deltas objectAtIndex:i] sizeValue];
		if (delta.width == 0 && delta.height == 0) {
			continue;
		}
		for (ORMShape *shape in [self movedShapes:@[ [[order objectAtIndex:i] identifier] ]]) {
			[moves addObject:@[ shape, [NSValue valueWithRect:NSOffsetRect(shape.bounds, delta.width, delta.height)] ]];
		}
	}
	if ([moves count] == 0) {
		return YES;
	}
	[_editor modelChange:[names objectAtIndex:(NSUInteger)alignment] with:^{
		for (NSArray *move in moves) {
			ORMShape *shape = [move firstObject];
			shape.bounds = [[move lastObject] rectValue];
			[_editor wrote:shape];
		}
	}];
	return YES;
}

- (void)setBounds:(NSRect)bounds ofShape:(NSString *)shapeId
{
	ORMShape *shape = [_editor.model elementWithId:shapeId];
	if (![shape isKindOfClass:[ORMShape class]] || NSEqualRects(shape.bounds, bounds)) {
		return;
	}
	NSSize delta = NSMakeSize(NSMinX(bounds) - NSMinX(shape.bounds), NSMinY(bounds) - NSMinY(shape.bounds));
	NSArray *carried = [self movedShapes:@[ shapeId ]];
	[_editor modelChange:@"Resize" with:^{
		for (ORMShape *child in carried) {
			if (child != shape) {
				child.bounds = NSOffsetRect(child.bounds, delta.width, delta.height);
				[_editor wrote:child];
			}
		}
		shape.bounds = bounds;
		[_editor wrote:shape];
	}];
}

- (BOOL)setRoleDisplayOrder:(NSArray<NSString *> *)roleIds ofShape:(NSString *)shapeId reason:(NSString **)reason
{
	ORMShape *shape = [_editor.model elementWithId:shapeId];
	if (![shape isKindOfClass:[ORMShape class]] || shape.kind != ORMShapeFactType) {
		if (reason != NULL) {
			*reason = @"Pick a fact type on the diagram.";
		}
		return NO;
	}
	NSMutableSet *have = [NSMutableSet set];
	for (ORMRole *role in shape.factType.roles) {
		[have addObject:role.identifier];
	}
	if (![[NSSet setWithArray:roleIds] isEqualToSet:have] || [roleIds count] != [have count]) {
		if (reason != NULL) {
			*reason = @"The new order must name each of the fact type's roles once.";
		}
		return NO;
	}
	[_editor modelChange:@"Reorder Roles" with:^{
		NSMutableArray *roles = [NSMutableArray array];
		for (NSString *roleId in roleIds) {
			[roles addObject:[_editor.model elementWithId:roleId]];
		}
		shape.roleDisplayOrder = roles;
		[_editor wrote:shape];
	}];
	return YES;
}

- (void)setOrientation:(ORMFactTypeOrientation)orientation ofShape:(NSString *)shapeId
{
	ORMShape *shape = [_editor.model elementWithId:shapeId];
	if (![shape isKindOfClass:[ORMShape class]] || shape.kind != ORMShapeFactType || shape.orientation == orientation) {
		return;
	}
	NSRect bounds = shape.bounds;
	BOOL wasVertical = shape.orientation != ORMFactTypeHorizontal;
	BOOL vertical = orientation != ORMFactTypeHorizontal;
	if (wasVertical != vertical) {
		NSPoint center = [shape center];
		bounds = NSMakeRect(center.x - NSHeight(bounds) / 2, center.y - NSWidth(bounds) / 2, NSHeight(bounds),
		                    NSWidth(bounds));
	}
	[_editor modelChange:@"Rotate Fact Type" with:^{
		shape.orientation = orientation;
		shape.bounds = bounds;
		[_editor wrote:shape];
	}];
}

/* A node of the layout: a top-level shape, where it is, and how big. */
typedef struct {
	double x, y;   /* centre */
	double dx, dy; /* this round's displacement */
	double w, h;
	BOOL fixed;
} ORMLayoutNode;

/* Lays the diagram out from scratch, force-directed: each fact type pulls
 * toward its players and each constraint and note toward what it is
 * about, everything pushes everything else away, and a last pass moves
 * apart what still overlaps. Deterministic, starting from a circle in the
 * diagram's order, so the same model always comes out the same. */
- (void)arrangeDiagram:(NSString *)diagramId
{
	ORMDiagram *diagram = [self diagramWithId:diagramId];
	NSArray *shapes = [diagram.shapes copy];
	NSUInteger count = [shapes count];
	if (diagram == nil || count == 0) {
		return;
	}
	ORMLayoutNode *nodes = calloc(count, sizeof(ORMLayoutNode));
	NSMutableDictionary *index = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < count; i++) {
		ORMShape *shape = [shapes objectAtIndex:i];
		[index setObject:@(i) forKey:shape.identifier];
		nodes[i].w = NSWidth(shape.bounds);
		nodes[i].h = NSHeight(shape.bounds);
		/* A fact type keeps room for its reading below it. */
		if (shape.kind == ORMShapeFactType) {
			nodes[i].w = MAX(nodes[i].w, 0.9 * 72);
			nodes[i].h += 0.25 * 72;
		}
	}
	/* The springs: index pairs and their rest lengths. */
	NSMutableArray *springs = [NSMutableArray array];
	for (NSUInteger i = 0; i < count; i++) {
		ORMShape *shape = [shapes objectAtIndex:i];
		for (ORMShape *linked in [self linkedShapesOf:shape.subject on:diagram]) {
			NSNumber *j = [index objectForKey:linked.identifier];
			if (j != nil && [j unsignedIntegerValue] != i) {
				double rest = shape.kind == ORMShapeFactType ? 0.85 * 72 : 0.6 * 72;
				[springs addObject:@[ @(i), j, @(rest) ]];
			}
		}
		/* Subtypes sit near their supertypes. */
		for (ORMObjectType *supertype in shape.objectType.supertypes) {
			NSNumber *j = [index objectForKey:[[diagram shapeForSubject:supertype.identifier] identifier] ?: @""];
			if (j != nil) {
				[springs addObject:@[ @(i), j, @(1.1 * 72) ]];
			}
		}
	}
	/* Start on a circle, entity types first, their facts and values after,
	 * so what is related starts near. */
	double radius = MAX(2.0 * 72, sqrt((double)count) * 0.9 * 72);
	for (NSUInteger i = 0; i < count; i++) {
		double angle = 2 * M_PI * i / count;
		nodes[i].x = radius * cos(angle);
		nodes[i].y = radius * sin(angle);
	}
	/* The distance shapes settle at: about NORMA's spacing. */
	double k = 0.75 * 72;
	double temperature = radius / 3;
	for (NSUInteger round = 0; round < 400; round++) {
		for (NSUInteger i = 0; i < count; i++) {
			nodes[i].dx = 0;
			nodes[i].dy = 0;
		}
		for (NSUInteger i = 0; i < count; i++) {
			for (NSUInteger j = i + 1; j < count; j++) {
				double ddx = nodes[i].x - nodes[j].x;
				double ddy = nodes[i].y - nodes[j].y;
				double distance = MAX(hypot(ddx, ddy), 1.0);
				/* Bigger shapes keep further apart. */
				double reach = k * 0.6 + (nodes[i].w + nodes[j].w) / 4;
				double force = reach * reach / distance;
				nodes[i].dx += ddx / distance * force;
				nodes[i].dy += ddy / distance * force;
				nodes[j].dx -= ddx / distance * force;
				nodes[j].dy -= ddy / distance * force;
			}
		}
		for (NSArray *spring in springs) {
			NSUInteger i = [[spring objectAtIndex:0] unsignedIntegerValue];
			NSUInteger j = [[spring objectAtIndex:1] unsignedIntegerValue];
			double rest = [[spring objectAtIndex:2] doubleValue];
			double ddx = nodes[i].x - nodes[j].x;
			double ddy = nodes[i].y - nodes[j].y;
			double distance = MAX(hypot(ddx, ddy), 1.0);
			double stretch = distance - rest;
			double force = 2.0 * stretch * fabs(stretch) / k;
			nodes[i].dx -= ddx / distance * force;
			nodes[i].dy -= ddy / distance * force;
			nodes[j].dx += ddx / distance * force;
			nodes[j].dy += ddy / distance * force;
		}
		/* A weak pull to the middle, so what nothing links stays near. */
		for (NSUInteger i = 0; i < count; i++) {
			nodes[i].dx -= nodes[i].x * 0.03;
			nodes[i].dy -= nodes[i].y * 0.03;
		}
		for (NSUInteger i = 0; i < count; i++) {
			double length = MAX(hypot(nodes[i].dx, nodes[i].dy), 0.0001);
			double step = MIN(length, temperature);
			nodes[i].x += nodes[i].dx / length * step;
			nodes[i].y += nodes[i].dy / length * step;
		}
		temperature = MAX(temperature * 0.985, 1.0);
	}
	/* What still overlaps, pushed apart along the shorter way out. */
	double gap = 8;
	for (NSUInteger pass = 0; pass < 200; pass++) {
		BOOL moved = NO;
		for (NSUInteger i = 0; i < count; i++) {
			for (NSUInteger j = i + 1; j < count; j++) {
				double overlapX = (nodes[i].w + nodes[j].w) / 2 + gap - fabs(nodes[i].x - nodes[j].x);
				double overlapY = (nodes[i].h + nodes[j].h) / 2 + gap - fabs(nodes[i].y - nodes[j].y);
				if (overlapX <= 0 || overlapY <= 0) {
					continue;
				}
				moved = YES;
				if (overlapX < overlapY) {
					double sign = nodes[i].x < nodes[j].x || (nodes[i].x == nodes[j].x && i < j) ? -1 : 1;
					nodes[i].x += sign * overlapX / 2;
					nodes[j].x -= sign * overlapX / 2;
				} else {
					double sign = nodes[i].y < nodes[j].y || (nodes[i].y == nodes[j].y && i < j) ? -1 : 1;
					nodes[i].y += sign * overlapY / 2;
					nodes[j].y -= sign * overlapY / 2;
				}
			}
		}
		if (!moved) {
			break;
		}
	}
	/* Moved to the diagram's top left, half an inch in. */
	double minX = DBL_MAX;
	double minY = DBL_MAX;
	for (NSUInteger i = 0; i < count; i++) {
		minX = MIN(minX, nodes[i].x - nodes[i].w / 2);
		minY = MIN(minY, nodes[i].y - nodes[i].h / 2);
	}
	NSMutableDictionary *placed = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < count; i++) {
		ORMShape *shape = [shapes objectAtIndex:i];
		double x = round(nodes[i].x - minX + 0.5 * 72 - NSWidth(shape.bounds) / 2);
		double y = round(nodes[i].y - minY + 0.5 * 72 - nodes[i].h / 2);
		[placed setObject:[NSValue valueWithPoint:NSMakePoint(x, y)] forKey:shape.identifier];
	}
	free(nodes);
	[_editor modelChange:@"Arrange Diagram" with:^{
		for (ORMShape *shape in shapes) {
			NSPoint at = [[placed objectForKey:shape.identifier] pointValue];
			NSSize delta = NSMakeSize(at.x - NSMinX(shape.bounds), at.y - NSMinY(shape.bounds));
			for (ORMShape *moved in [self movedShapes:@[ shape.identifier ]]) {
				moved.bounds = NSOffsetRect(moved.bounds, delta.width, delta.height);
				[_editor wrote:moved];
			}
		}
	}];
}

@end
