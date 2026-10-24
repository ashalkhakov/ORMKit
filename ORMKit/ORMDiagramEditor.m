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

#pragma mark Arranging in groups

/* An object type that is a hub of a diagram, as Arrange in Groups takes
 * hubs out: used by two of its fact types or more, and a value type or an
 * entity type in this many or more. */
static const NSUInteger ORMHubDegree = 5;
/* Between groups, across and down. */
static const double ORMGroupGap = 0.75 * 72.0;

/* Union-find over element ids: the root of the key's set. */
static NSString *
ORMGroupRoot(NSMutableDictionary<NSString *, NSString *> *parents, NSString *key)
{
	NSString *root = key;
	while ([parents objectForKey:root] != nil && ![[parents objectForKey:root] isEqualToString:root]) {
		root = [parents objectForKey:root];
	}
	if ([parents objectForKey:key] == nil) {
		[parents setObject:key forKey:key];
	}
	/* Each on the way pointed at the root. */
	NSString *at = key;
	while (![at isEqualToString:root]) {
		NSString *next = [parents objectForKey:at];
		[parents setObject:root forKey:at];
		at = next;
	}
	return root;
}

static void
ORMGroupJoin(NSMutableDictionary<NSString *, NSString *> *parents, NSString *a, NSString *b)
{
	NSString *ra = ORMGroupRoot(parents, a);
	NSString *rb = ORMGroupRoot(parents, b);
	if (![ra isEqualToString:rb]) {
		[parents setObject:ra forKey:rb];
	}
}

/* The element an object type is shown as on the diagram: itself, or the
 * fact type it objectifies; nil when neither is shown. */
static NSString *
ORMShownNode(ORMObjectType *type, ORMDiagram *diagram)
{
	if (type == nil) {
		return nil;
	}
	if ([diagram shapeForSubject:type.identifier] != nil) {
		return type.identifier;
	}
	if (type.nestedFactType != nil && [diagram shapeForSubject:type.nestedFactType.identifier] != nil) {
		return type.nestedFactType.identifier;
	}
	return nil;
}

/* The centre of the shapes. */
static NSPoint
ORMCentreOf(NSArray<ORMShape *> *shapes)
{
	if ([shapes count] == 0) {
		return NSZeroPoint;
	}
	double x = 0;
	double y = 0;
	for (ORMShape *shape in shapes) {
		x += NSMidX(shape.bounds);
		y += NSMidY(shape.bounds);
	}
	return NSMakePoint(x / [shapes count], y / [shapes count]);
}

/* A group being laid out: its shapes, the hub shape it links to for each
 * hub, and where it lands. */
@interface ORMLayoutGroup : NSObject
@property (nonatomic, strong) NSMutableArray<ORMShape *> *shapes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ORMShape *> *hubShapes;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *hubs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *placed;
@property (nonatomic) NSSize size;
/* Its size's, for packing the largest first. */
@property (nonatomic, readonly) double area;
@end

@implementation ORMLayoutGroup
- (instancetype)init
{
	if ((self = [super init])) {
		_shapes = [NSMutableArray array];
		_hubShapes = [NSMutableDictionary dictionary];
		_hubs = [NSMutableOrderedSet orderedSet];
		_placed = [NSMutableDictionary dictionary];
	}
	return self;
}
@end


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

/* Every shape of the element on any of the model's diagrams. */
- (NSArray<ORMShape *> *)allShapesOf:(NSString *)elementId
{
	NSMutableArray *shapes = [NSMutableArray array];
	for (ORMDiagram *diagram in _editor.model.diagrams) {
		[shapes addObjectsFromArray:[diagram shapesForSubject:elementId]];
	}
	return shapes;
}

- (BOOL)isExtraShape:(NSString *)shapeId
{
	ORMShape *shape = [_editor.model elementWithId:shapeId];
	if (![shape isKindOfClass:[ORMShape class]] || shape.parent != nil || shape.subjectId == nil) {
		return NO;
	}
	return [[self allShapesOf:shape.subjectId] count] > 1;
}

- (NSUInteger)removeExtraShapes:(NSArray<NSString *> *)shapeIds
{
	NSMutableArray *removed = [NSMutableArray array];
	NSCountedSet *left = [NSCountedSet set];
	for (NSString *shapeId in shapeIds) {
		ORMShape *shape = [_editor.model elementWithId:shapeId];
		if (![self isExtraShape:shapeId] || [removed containsObject:shape]) {
			continue;
		}
		/* Never the last: what this call already takes counts. */
		NSUInteger remaining = [[self allShapesOf:shape.subjectId] count] - [left countForObject:shape.subjectId];
		if (remaining <= 1) {
			continue;
		}
		[left addObject:shape.subjectId];
		[removed addObject:shape];
	}
	if ([removed count] == 0) {
		return 0;
	}
	[_editor modelChange:@"Delete Extra Shape" with:^{
		[self removeShapes:removed];
	}];
	return [removed count];
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
			/* What is placed on it goes in its element, and comes back
			 * with it. */
			[_editor deleted:shape];
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

/* The nodes laid out, force-directed, about the origin: each spring
 * ([i, j, rest length]) pulls its two together, everything pushes
 * everything else away, and a last pass moves apart what still overlaps.
 * Deterministic: from a circle, in the nodes' order. */
static void
ORMSpringLayout(ORMLayoutNode *nodes, NSUInteger count, NSArray<NSArray *> *springs)
{
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
}

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
	ORMSpringLayout(nodes, count, springs);
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

#pragma mark Arranging in groups


/* The hubs of the diagram: object types its fact types and subtyping link
 * to twice or more, value types, and entity types used ORMHubDegree times
 * or more. */
- (NSSet<NSString *> *)hubsOf:(ORMDiagram *)diagram
{
	NSCountedSet *degree = [NSCountedSet set];
	NSMutableSet *facts = [NSMutableSet set];
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeFactType && shape.factType != nil && ![facts containsObject:shape.factType.identifier]) {
			[facts addObject:shape.factType.identifier];
			NSMutableSet *players = [NSMutableSet set];
			for (ORMRole *role in [shape.factType visibleRoles]) {
				if (role.player != nil && [diagram shapeForSubject:role.player.identifier] != nil) {
					[players addObject:role.player.identifier];
				}
			}
			for (NSString *player in players) {
				[degree addObject:player];
			}
		}
	}
	for (ORMShape *shape in diagram.shapes) {
		ORMObjectType *type = shape.kind == ORMShapeObjectType ? shape.objectType : nil;
		for (ORMObjectType *supertype in type.supertypes) {
			if ([diagram shapeForSubject:supertype.identifier] != nil) {
				[degree addObject:type.identifier];
				[degree addObject:supertype.identifier];
			}
		}
	}
	NSMutableSet *hubs = [NSMutableSet set];
	for (NSString *typeId in degree) {
		ORMObjectType *type = [_editor.model elementWithId:typeId];
		NSUInteger uses = [degree countForObject:typeId];
		if (uses >= 2 && (type.kind == ORMValueType || uses >= ORMHubDegree)) {
			[hubs addObject:typeId];
		}
	}
	return hubs;
}


/* The diagram's elements in groups: what its fact types and subtyping
 * link once the hubs are taken out; a fact type of hubs alone goes with
 * its first player's. Each group's elements, in the diagram's order. */
- (NSArray<NSArray<NSString *> *> *)groupsOf:(ORMDiagram *)diagram hubs:(NSSet<NSString *> *)hubs
{
	NSMutableDictionary *parents = [NSMutableDictionary dictionary];
	NSMutableOrderedSet *elements = [NSMutableOrderedSet orderedSet];
	for (ORMShape *shape in diagram.shapes) {
		if (shape.subjectId == nil || [hubs containsObject:shape.subjectId]) {
			continue;
		}
		[elements addObject:shape.subjectId];
		ORMGroupRoot(parents, shape.subjectId);
		if (shape.kind == ORMShapeFactType && shape.factType != nil) {
			NSString *first = nil;
			BOOL joined = NO;
			for (ORMRole *role in [shape.factType visibleRoles]) {
				NSString *node = ORMShownNode(role.player, diagram);
				if (node == nil || [node isEqualToString:shape.subjectId]) {
					continue;
				}
				first = first ?: node;
				if (![hubs containsObject:node]) {
					ORMGroupJoin(parents, shape.subjectId, node);
					joined = YES;
				}
			}
			if (!joined && first != nil) {
				ORMGroupJoin(parents, shape.subjectId, [@"hub:" stringByAppendingString:first]);
			}
		} else if (shape.kind == ORMShapeObjectType && shape.objectType != nil) {
			for (ORMObjectType *supertype in shape.objectType.supertypes) {
				NSString *node = ORMShownNode(supertype, diagram);
				if (node != nil && ![hubs containsObject:node]) {
					ORMGroupJoin(parents, shape.subjectId, node);
				}
			}
		} else {
			/* A constraint or note: with all it is about, which it keeps
			 * together, its lines short. */
			for (ORMShape *linked in [self linkedShapesOf:shape.subject on:diagram]) {
				if (linked.subjectId != nil && ![hubs containsObject:linked.subjectId]) {
					ORMGroupJoin(parents, shape.subjectId, linked.subjectId);
				}
			}
		}
	}
	NSMutableDictionary *byRoot = [NSMutableDictionary dictionary];
	NSMutableArray *order = [NSMutableArray array];
	NSMutableArray *loose = [NSMutableArray array];
	for (NSString *element in elements) {
		NSString *root = ORMGroupRoot(parents, element);
		NSMutableArray *group = [byRoot objectForKey:root];
		if (group == nil) {
			group = [NSMutableArray array];
			[byRoot setObject:group forKey:root];
			[order addObject:group];
		}
		[group addObject:element];
	}
	/* A group about one entity hub alone (its attributes, what only it
	 * links) is that hub's: in its home group, with the facts of hubs
	 * alone it comes first in. What is linked to nothing, together. */
	NSMutableArray *groups = [NSMutableArray array];
	NSMutableDictionary *homes = [NSMutableDictionary dictionary];
	for (NSMutableArray *group in order) {
		if ([group count] == 1 && [[[diagram shapeForSubject:group[0]] subject] isKindOfClass:[ORMObjectType class]]) {
			[loose addObjectsFromArray:group];
			continue;
		}
		NSString *root = ORMGroupRoot(parents, group[0]);
		NSString *home = [root hasPrefix:@"hub:"] ? [root substringFromIndex:4] : nil;
		if (home == nil) {
			NSOrderedSet *used = [self hubsOfGroup:group on:diagram hubs:hubs];
			ORMObjectType *only = [used count] == 1 ? [_editor.model elementWithId:[used firstObject]] : nil;
			home = [only isKindOfClass:[ORMObjectType class]] && only.isEntity ? only.identifier : nil;
		}
		if (home == nil) {
			[groups addObject:group];
			continue;
		}
		NSMutableArray *homeGroup = [homes objectForKey:home];
		if (homeGroup == nil) {
			homeGroup = [NSMutableArray array];
			[homes setObject:homeGroup forKey:home];
			[groups addObject:homeGroup];
		}
		[homeGroup addObjectsFromArray:group];
	}
	if ([loose count] > 0) {
		[groups addObject:loose];
	}
	return groups;
}

/* The hubs a group's elements link to, in the order met. */
- (NSOrderedSet<NSString *> *)hubsOfGroup:(NSArray<NSString *> *)group on:(ORMDiagram *)diagram hubs:(NSSet<NSString *> *)hubs
{
	NSMutableOrderedSet *used = [NSMutableOrderedSet orderedSet];
	for (NSString *element in group) {
		id subject = [_editor.model elementWithId:element];
		if ([subject isKindOfClass:[ORMFactType class]]) {
			for (ORMRole *role in [(ORMFactType *)subject visibleRoles]) {
				NSString *node = ORMShownNode(role.player, diagram);
				if (node != nil && [hubs containsObject:node]) {
					[used addObject:node];
				}
			}
		} else if ([subject isKindOfClass:[ORMObjectType class]]) {
			NSArray *related = [[(ORMObjectType *)subject supertypes] arrayByAddingObjectsFromArray:[(ORMObjectType *)subject subtypes]];
			for (ORMObjectType *other in related) {
				NSString *node = ORMShownNode(other, diagram);
				if (node != nil && [hubs containsObject:node]) {
					[used addObject:node];
				}
			}
		}
	}
	return used;
}

/* A group laid out about the origin by Arrange's springs: its elements'
 * shapes and its hub shapes, each fact type pulled to its players' shapes
 * in the group, each subtype to its supertype, each constraint and note to
 * what it is about. Its shapes' top lefts from its own top left, and its
 * size. */
- (void)layOut:(ORMLayoutGroup *)group on:(ORMDiagram *)diagram
{
	NSArray *shapes = group.shapes;
	NSUInteger count = [shapes count];
	ORMLayoutNode *nodes = calloc(count, sizeof(ORMLayoutNode));
	NSMutableDictionary *index = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < count; i++) {
		ORMShape *shape = [shapes objectAtIndex:i];
		[index setObject:@(i) forKey:shape.identifier];
		/* By subject too, the group's one of each. */
		if ([index objectForKey:shape.subjectId] == nil) {
			[index setObject:@(i) forKey:shape.subjectId];
		}
		nodes[i].w = NSWidth(shape.bounds);
		nodes[i].h = NSHeight(shape.bounds);
		if (shape.kind == ORMShapeFactType) {
			nodes[i].w = MAX(nodes[i].w, 0.9 * 72);
			nodes[i].h += 0.25 * 72;
		}
	}
	NSMutableArray *springs = [NSMutableArray array];
	for (NSUInteger i = 0; i < count; i++) {
		ORMShape *shape = [shapes objectAtIndex:i];
		NSMutableArray *ends = [NSMutableArray array];
		double rest = 0.6 * 72;
		if (shape.kind == ORMShapeFactType) {
			rest = 0.85 * 72;
			for (ORMRole *role in [shape.factType visibleRoles]) {
				NSString *node = ORMShownNode(role.player, diagram);
				if (node != nil) {
					[ends addObject:node];
				}
			}
		} else if (shape.kind == ORMShapeObjectType) {
			rest = 1.1 * 72;
			/* Up and down: a hub's copy is pulled to its subtype too. */
			NSArray *related = [shape.objectType.supertypes arrayByAddingObjectsFromArray:shape.objectType.subtypes];
			for (ORMObjectType *other in related) {
				NSString *node = ORMShownNode(other, diagram);
				if (node != nil) {
					[ends addObject:node];
				}
			}
		} else {
			for (ORMShape *linked in [self linkedShapesOf:shape.subject on:diagram]) {
				if (linked.subjectId != nil) {
					[ends addObject:linked.subjectId];
				}
			}
		}
		for (NSString *end in ends) {
			ORMShape *hub = [group.hubShapes objectForKey:end];
			NSNumber *j = [index objectForKey:hub != nil ? hub.identifier : end];
			if (j != nil && [j unsignedIntegerValue] != i) {
				[springs addObject:@[ @(i), j, @(rest) ]];
			}
		}
	}
	/* What the springs link, laid out by them; what nothing links, in rows
	 * under it, as square as they come, not pushed off on its own. */
	BOOL *linked = calloc(MAX(count, 1), sizeof(BOOL));
	for (NSArray *spring in springs) {
		linked[[[spring objectAtIndex:0] unsignedIntegerValue]] = YES;
		linked[[[spring objectAtIndex:1] unsignedIntegerValue]] = YES;
	}
	NSMutableArray *linkedIndexes = [NSMutableArray array];
	NSMutableArray *alone = [NSMutableArray array];
	for (NSUInteger i = 0; i < count; i++) {
		[(linked[i] ? linkedIndexes : alone) addObject:@(i)];
	}
	free(linked);
	double bottom = 0;
	double left = 0;
	if ([linkedIndexes count] > 0) {
		NSUInteger linkedCount = [linkedIndexes count];
		ORMLayoutNode *sub = calloc(linkedCount, sizeof(ORMLayoutNode));
		NSMutableDictionary *at = [NSMutableDictionary dictionary];
		for (NSUInteger k = 0; k < linkedCount; k++) {
			sub[k] = nodes[[[linkedIndexes objectAtIndex:k] unsignedIntegerValue]];
			[at setObject:@(k) forKey:[linkedIndexes objectAtIndex:k]];
		}
		NSMutableArray *subSprings = [NSMutableArray array];
		for (NSArray *spring in springs) {
			[subSprings addObject:@[ [at objectForKey:[spring objectAtIndex:0]], [at objectForKey:[spring objectAtIndex:1]],
			                         [spring objectAtIndex:2] ]];
		}
		ORMSpringLayout(sub, linkedCount, subSprings);
		bottom = -DBL_MAX;
		left = DBL_MAX;
		for (NSUInteger k = 0; k < linkedCount; k++) {
			nodes[[[linkedIndexes objectAtIndex:k] unsignedIntegerValue]] = sub[k];
			bottom = MAX(bottom, sub[k].y + sub[k].h / 2);
			left = MIN(left, sub[k].x - sub[k].w / 2);
		}
		bottom += ORMGroupGap / 2;
		free(sub);
	}
	NSUInteger across = (NSUInteger)MAX(1, ceil(sqrt((double)[alone count])));
	double x = left;
	double y = bottom;
	double rowHeight = 0;
	for (NSUInteger k = 0; k < [alone count]; k++) {
		NSUInteger i = [[alone objectAtIndex:k] unsignedIntegerValue];
		if (k > 0 && k % across == 0) {
			x = left;
			y += rowHeight + ORMGroupGap / 2;
			rowHeight = 0;
		}
		nodes[i].x = x + nodes[i].w / 2;
		nodes[i].y = y + nodes[i].h / 2;
		x += nodes[i].w + ORMGroupGap / 2;
		rowHeight = MAX(rowHeight, nodes[i].h);
	}
	double minX = DBL_MAX;
	double minY = DBL_MAX;
	double maxX = -DBL_MAX;
	double maxY = -DBL_MAX;
	for (NSUInteger i = 0; i < count; i++) {
		minX = MIN(minX, nodes[i].x - nodes[i].w / 2);
		minY = MIN(minY, nodes[i].y - nodes[i].h / 2);
		maxX = MAX(maxX, nodes[i].x + nodes[i].w / 2);
		maxY = MAX(maxY, nodes[i].y + nodes[i].h / 2);
	}
	for (NSUInteger i = 0; i < count; i++) {
		ORMShape *shape = [shapes objectAtIndex:i];
		NSPoint at = NSMakePoint(round(nodes[i].x - minX - NSWidth(shape.bounds) / 2), round(nodes[i].y - minY - nodes[i].h / 2));
		[group.placed setObject:[NSValue valueWithPoint:at] forKey:shape.identifier];
	}
	group.size = count > 0 ? NSMakeSize(maxX - minX, maxY - minY) : NSZeroSize;
	free(nodes);
}

- (void)arrangeDiagramInGroups:(NSString *)diagramId
{
	ORMDiagram *diagram = [self diagramWithId:diagramId];
	if (diagram == nil || [diagram.shapes count] == 0) {
		return;
	}
	NSSet *hubs = [self hubsOf:diagram];
	NSArray *elementGroups = [self groupsOf:diagram hubs:hubs];
	NSMutableArray<ORMLayoutGroup *> *groups = [NSMutableArray array];
	/* An element of a group needs one shape: its lines all stay in it. */
	NSMutableArray *extra = [NSMutableArray array];
	for (NSArray *elements in elementGroups) {
		ORMLayoutGroup *group = [[ORMLayoutGroup alloc] init];
		for (NSString *element in elements) {
			NSArray *shapes = [diagram shapesForSubject:element];
			if ([shapes count] > 0) {
				[group.shapes addObject:[shapes firstObject]];
				[extra addObjectsFromArray:[shapes subarrayWithRange:NSMakeRange(1, [shapes count] - 1)]];
			}
		}
		[group.hubs unionOrderedSet:[self hubsOfGroup:elements on:diagram hubs:hubs]];
		[groups addObject:group];
	}
	[_editor modelChange:@"Arrange in Groups" with:^{
		[self removeShapes:extra];
		/* One shape of each hub for each group that uses it: its shapes
		 * reused, the group's nearest first; more made; the rest removed. */
		for (NSString *hub in [[hubs allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
			NSMutableArray *spare = [NSMutableArray array];
			for (ORMShape *shape in [diagram shapesForSubject:hub]) {
				if (shape.kind == ORMShapeObjectType) {
					[spare addObject:shape];
				}
			}
			for (ORMLayoutGroup *group in groups) {
				if (![group.hubs containsObject:hub]) {
					continue;
				}
				NSPoint centre = ORMCentreOf(group.shapes);
				ORMShape *best = nil;
				double distance = DBL_MAX;
				for (ORMShape *shape in spare) {
					double d = hypot(NSMidX(shape.bounds) - centre.x, NSMidY(shape.bounds) - centre.y);
					if (d < distance) {
						distance = d;
						best = shape;
					}
				}
				if (best != nil) {
					[spare removeObject:best];
				} else {
					ORMObjectType *type = [self->_editor.model elementWithId:hub];
					NSSize size = [self defaultSizeOf:type];
					best = [self addShape:ORMShapeObjectType of:type
					               bounds:NSMakeRect(centre.x, centre.y, size.width, size.height) parent:nil on:diagram];
				}
				[group.hubShapes setObject:best forKey:hub];
				[group.shapes addObject:best];
			}
			[self removeShapes:spare];
		}
		/* Each group laid out, then the groups in rows, the largest first. */
		double area = 0;
		double widest = 0;
		for (ORMLayoutGroup *group in groups) {
			[self layOut:group on:diagram];
			area += (group.size.width + ORMGroupGap) * (group.size.height + ORMGroupGap);
			widest = MAX(widest, group.size.width);
		}
		NSArray *bySize = [groups sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"area" ascending:NO] ]];
		double rowWidth = MAX(widest, sqrt(area) * 1.3);
		double x = 0.5 * 72;
		double y = 0.5 * 72;
		double rowHeight = 0;
		for (ORMLayoutGroup *group in bySize) {
			if (x > 0.5 * 72 && x + group.size.width > 0.5 * 72 + rowWidth) {
				x = 0.5 * 72;
				y += rowHeight + ORMGroupGap;
				rowHeight = 0;
			}
			for (ORMShape *shape in group.shapes) {
				NSPoint at = [[group.placed objectForKey:shape.identifier] pointValue];
				NSSize delta = NSMakeSize(x + at.x - NSMinX(shape.bounds), y + at.y - NSMinY(shape.bounds));
				for (ORMShape *moved in [self movedShapes:@[ shape.identifier ]]) {
					moved.bounds = NSOffsetRect(moved.bounds, delta.width, delta.height);
					[self->_editor wrote:moved];
				}
			}
			x += group.size.width + ORMGroupGap;
			rowHeight = MAX(rowHeight, group.size.height);
		}
	}];
}

@end
