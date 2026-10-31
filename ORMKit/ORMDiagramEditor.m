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

/* An entity type that heads a group of its own in Arrange in Groups: used
 * by this many of the diagram's fact types and subtypings or more. */
static const NSUInteger ORMAnchorDegree = 4;
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

/* The two keys' sets made one, unless each has an anchor (the sets'
 * anchors kept by root). Whether they are one. */
static BOOL
ORMGroupJoinApart(NSMutableDictionary<NSString *, NSString *> *parents, NSMutableDictionary<NSString *, NSString *> *anchored,
                  NSString *a, NSString *b)
{
	NSString *ra = ORMGroupRoot(parents, a);
	NSString *rb = ORMGroupRoot(parents, b);
	if ([ra isEqualToString:rb]) {
		return YES;
	}
	NSString *anchor = [anchored objectForKey:ra];
	NSString *other = [anchored objectForKey:rb];
	if (anchor != nil && other != nil) {
		return NO;
	}
	[parents setObject:ra forKey:rb];
	if (anchor == nil && other != nil) {
		[anchored setObject:other forKey:ra];
	}
	return YES;
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

/* The diagram's top-level shapes' frames: what a new shape keeps clear of. */
static NSArray<NSValue *> *
ORMShapeFrames(ORMDiagram *diagram)
{
	NSMutableArray *frames = [NSMutableArray array];
	for (ORMShape *shape in diagram.shapes) {
		[frames addObject:[NSValue valueWithRect:shape.bounds]];
	}
	return frames;
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
		/* Clear of the others by 4 points, spiralling out. */
		origin = DKFreeSpotNear(size, near, ORMShapeFrames(diagram), 4).origin;
	}
	NSRect bounds = NSMakeRect(origin.x, origin.y, size.width, size.height);
	__block NSString *created = nil;
	[_editor modelChange:existing != nil ? @"Add Another Shape" : @"Place on Diagram" with:^{
		created = [self addShape:kind of:element bounds:bounds on:diagram].identifier;
	}];
	return created;
}

/* A new top-level shape, inside a model change; a fact type's with its
 * reading and role names. */
- (ORMShape *)addShape:(ORMShapeKind)kind of:(ORMElement *)element bounds:(NSRect)bounds on:(ORMDiagram *)diagram
{
	ORMShape *shape = [self addShape:kind of:element bounds:bounds parent:nil on:diagram];
	if ([element isKindOfClass:[ORMFactType class]]) {
		ORMFactType *fact = (ORMFactType *)element;
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
	return shape;
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

#pragma mark Orienting fact types

/* The centre of the player's shape nearest the point, on the diagram: its
 * own, or its objectified fact type's; NO when none is shown. */
static BOOL
ORMNearestPlayerCentre(ORMObjectType *player, ORMDiagram *diagram, NSPoint from, NSPoint *centre)
{
	NSMutableArray *candidates = [[diagram shapesForSubject:player.identifier] mutableCopy];
	if (player.nestedFactType != nil) {
		[candidates addObjectsFromArray:[diagram shapesForSubject:player.nestedFactType.identifier]];
	}
	double distance = DBL_MAX;
	for (ORMShape *candidate in candidates) {
		if (candidate.parent != nil) {
			continue;
		}
		double d = hypot(NSMidX(candidate.bounds) - from.x, NSMidY(candidate.bounds) - from.y);
		if (d < distance) {
			distance = d;
			*centre = NSMakePoint(NSMidX(candidate.bounds), NSMidY(candidate.bounds));
		}
	}
	return distance < DBL_MAX;
}

/* Roles by where their players are along one axis, as a sort sees them. */
static NSInteger
ORMCompareAlong(NSArray *a, NSArray *b, void *context)
{
	(void)context;
	double x = [[a objectAtIndex:1] doubleValue];
	double y = [[b objectAtIndex:1] doubleValue];
	if (x != y) {
		return x < y ? NSOrderedAscending : NSOrderedDescending;
	}
	return [[a objectAtIndex:2] compare:[b objectAtIndex:2]];
}

/* The fact type shape turned and its role boxes ordered as Halpin draws
 * them: along the line its players' shapes lie on (across, or down when
 * they are more above one another than beside), each role's box on its
 * player's side. Its reading and role names moved with it. Inside a model
 * change; whether it changed. */
- (BOOL)orientShape:(ORMShape *)shape
{
	if (shape.kind != ORMShapeFactType || shape.parent != nil || shape.factType == nil) {
		return NO;
	}
	NSArray *roles = shape.roleDisplayOrder;
	NSPoint centre = NSMakePoint(NSMidX(shape.bounds), NSMidY(shape.bounds));
	NSMutableArray *placed = [NSMutableArray array];
	double minX = DBL_MAX, maxX = -DBL_MAX, minY = DBL_MAX, maxY = -DBL_MAX;
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		NSPoint at;
		if (role.player == nil || role.player.isImplicitBooleanValue
		    || !ORMNearestPlayerCentre(role.player, shape.diagram, centre, &at)) {
			continue;
		}
		[placed addObject:@[ role, [NSValue valueWithPoint:at], @(i) ]];
		minX = MIN(minX, at.x);
		maxX = MAX(maxX, at.x);
		minY = MIN(minY, at.y);
		maxY = MAX(maxY, at.y);
	}
	/* Two players or more, apart: a ring of one shape stays as it is. */
	if ([placed count] < 2 || (maxX - minX < 1 && maxY - minY < 1)) {
		return NO;
	}
	BOOL vertical = maxY - minY > maxX - minX;
	NSMutableArray *keyed = [NSMutableArray array];
	for (NSArray *entry in placed) {
		NSPoint at = [[entry objectAtIndex:1] pointValue];
		[keyed addObject:@[ [entry objectAtIndex:0], @(vertical ? at.y : at.x), [entry objectAtIndex:2] ]];
	}
	[keyed sortUsingFunction:ORMCompareAlong context:NULL];
	NSMutableArray *order = [NSMutableArray array];
	for (NSArray *entry in keyed) {
		[order addObject:[entry objectAtIndex:0]];
	}
	/* Roles with no player shown keep their places after. */
	for (ORMRole *role in roles) {
		if ([order indexOfObjectIdenticalTo:role] == NSNotFound) {
			[order addObject:role];
		}
	}
	ORMFactTypeOrientation orientation = vertical ? ORMFactTypeVerticalRotatedRight : ORMFactTypeHorizontal;
	if (orientation == shape.orientation && [order isEqualToArray:roles]) {
		return NO;
	}
	if ((shape.orientation != ORMFactTypeHorizontal) != vertical) {
		NSRect bounds = shape.bounds;
		shape.bounds = NSMakeRect(round(centre.x - NSHeight(bounds) / 2), round(centre.y - NSWidth(bounds) / 2), NSHeight(bounds),
		                          NSWidth(bounds));
	}
	shape.orientation = orientation;
	shape.roleDisplayOrder = order;
	[_editor wrote:shape];
	/* The reading under it, or beside it; each role name over its box, or
	 * before it. */
	NSRect strip = ORMRoleStrip(shape);
	for (ORMShape *child in shape.relativeShapes) {
		NSRect bounds = child.bounds;
		if (child.kind == ORMShapeReading) {
			bounds.origin = vertical ? NSMakePoint(NSMaxX(strip) + ORMReadingGap, NSMidY(strip) - NSHeight(bounds) / 2)
			                         : NSMakePoint(NSMinX(strip), NSMaxY(strip) + ORMReadingGap);
		} else if (child.kind == ORMShapeRoleName && [child.subject isKindOfClass:[ORMRole class]]) {
			NSRect box = ORMRoleBox(shape, child.subject);
			if (NSIsEmptyRect(box)) {
				continue;
			}
			/* Its text runs on from its point: before the box, a text's
			 * width before it, as near as the editor can tell without
			 * drawing (the diagram's font, half as wide as it is high). */
			double width = ([[(ORMRole *)child.subject name] length] + 2) * 0.55 * shape.diagram.baseFontSize;
			bounds.origin = vertical ? NSMakePoint(NSMinX(box) - width - ORMReadingGap, NSMidY(box) - NSHeight(bounds) / 2)
			                         : NSMakePoint(NSMinX(box) + 0.25 * NSWidth(box), NSMinY(box) - ORMRoleNameRise);
		} else {
			continue;
		}
		bounds.origin = NSMakePoint(round(bounds.origin.x), round(bounds.origin.y));
		if (!NSEqualRects(bounds, child.bounds)) {
			child.bounds = bounds;
			[_editor wrote:child];
		}
	}
	return YES;
}

/* Every fact type shape on the diagram oriented; inside a model change. */
- (NSUInteger)orientShapesOn:(ORMDiagram *)diagram
{
	NSUInteger changed = 0;
	for (ORMShape *shape in [diagram.shapes copy]) {
		changed += [self orientShape:shape];
	}
	return changed;
}

- (NSUInteger)orientFactTypes:(NSArray<NSString *> *)shapeIds onDiagram:(NSString *)diagramId
{
	ORMDiagram *diagram = [self diagramWithId:diagramId];
	if (diagram == nil) {
		return 0;
	}
	NSMutableArray *shapes = [NSMutableArray array];
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeFactType && ([shapeIds count] == 0 || [shapeIds containsObject:shape.identifier])) {
			[shapes addObject:shape];
		}
	}
	__block NSUInteger changed = 0;
	[_editor group:@"Orient Fact Types" trying:^BOOL {
		[self->_editor modelChange:@"Orient Fact Types" with:^{
			for (ORMShape *shape in shapes) {
				changed += [self orientShape:shape];
			}
		}];
		return changed > 0;
	}];
	return changed;
}

/* A shape's node in a layout: a fact type keeps room for its reading below
 * it. */
static NSSize
ORMLayoutSize(ORMShape *shape)
{
	NSSize size = shape.bounds.size;
	if (shape.kind == ORMShapeFactType) {
		size.width = MAX(size.width, 0.9 * 72);
		size.height += 0.25 * 72;
	}
	return size;
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
	if (diagram == nil || [shapes count] == 0) {
		return;
	}
	/* DiagramKit's force layout (ORMKit's own, once), its top left half an
	 * inch in. */
	DKForceLayout *layout = [[DKForceLayout alloc] init];
	layout.margin = 0.5 * 72;
	for (ORMShape *shape in shapes) {
		[layout addNode:shape.identifier size:ORMLayoutSize(shape) fixedAt:nil];
	}
	for (ORMShape *shape in shapes) {
		for (ORMShape *linked in [self linkedShapesOf:shape.subject on:diagram]) {
			double rest = shape.kind == ORMShapeFactType ? 0.85 * 72 : 0.6 * 72;
			[layout addSpringFrom:shape.identifier to:linked.identifier length:rest];
		}
		/* Subtypes sit near their supertypes. */
		for (ORMObjectType *supertype in shape.objectType.supertypes) {
			ORMShape *sup = [diagram shapeForSubject:supertype.identifier];
			if (sup != nil) {
				[layout addSpringFrom:shape.identifier to:sup.identifier length:1.1 * 72];
			}
		}
	}
	NSDictionary *frames = [layout layout];
	/* Each shape centred across its node, at its top. */
	NSMutableDictionary *placed = [NSMutableDictionary dictionary];
	for (ORMShape *shape in shapes) {
		NSRect frame = [[frames objectForKey:shape.identifier] rectValue];
		NSPoint at = NSMakePoint(round(NSMidX(frame) - NSWidth(shape.bounds) / 2), NSMinY(frame));
		[placed setObject:[NSValue valueWithPoint:at] forKey:shape.identifier];
	}
	[_editor modelChange:@"Arrange Diagram" with:^{
		for (ORMShape *shape in shapes) {
			NSPoint at = [[placed objectForKey:shape.identifier] pointValue];
			NSSize delta = NSMakeSize(at.x - NSMinX(shape.bounds), at.y - NSMinY(shape.bounds));
			for (ORMShape *moved in [self movedShapes:@[ shape.identifier ]]) {
				moved.bounds = NSOffsetRect(moved.bounds, delta.width, delta.height);
				[_editor wrote:moved];
			}
		}
		[self orientShapesOn:diagram];
	}];
}

#pragma mark Arranging in groups


/* How often the diagram uses each object type it shows: once for each of
 * its fact types the type plays in, once for each subtyping. */
- (NSCountedSet<NSString *> *)usesOn:(ORMDiagram *)diagram
{
	NSCountedSet *uses = [NSCountedSet set];
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
				[uses addObject:player];
			}
		}
	}
	NSMutableSet *types = [NSMutableSet set];
	for (ORMShape *shape in diagram.shapes) {
		ORMObjectType *type = shape.kind == ORMShapeObjectType ? shape.objectType : nil;
		if (type == nil || [types containsObject:type.identifier]) {
			continue;
		}
		[types addObject:type.identifier];
		for (ORMObjectType *supertype in type.supertypes) {
			if ([diagram shapeForSubject:supertype.identifier] != nil) {
				[uses addObject:type.identifier];
				[uses addObject:supertype.identifier];
			}
		}
	}
	return uses;
}

/* The hubs of the diagram, shown in each group that uses them: value types
 * used twice or more. */
- (NSSet<NSString *> *)hubsOf:(ORMDiagram *)diagram
{
	NSCountedSet *uses = [self usesOn:diagram];
	NSMutableSet *hubs = [NSMutableSet set];
	for (NSString *typeId in uses) {
		ORMObjectType *type = [_editor.model elementWithId:typeId];
		if (type.kind == ORMValueType && [uses countForObject:typeId] >= 2) {
			[hubs addObject:typeId];
		}
	}
	return hubs;
}

/* The anchors of the diagram, each at the head of a group of its own:
 * entity types used ORMAnchorDegree times or more. */
- (NSSet<NSString *> *)anchorsOf:(ORMDiagram *)diagram
{
	NSCountedSet *uses = [self usesOn:diagram];
	NSMutableSet *anchors = [NSMutableSet set];
	for (NSString *typeId in uses) {
		ORMObjectType *type = [_editor.model elementWithId:typeId];
		if (type.isEntity && [uses countForObject:typeId] >= ORMAnchorDegree) {
			[anchors addObject:typeId];
		}
	}
	return anchors;
}

/* The diagram's elements in groups, each anchor in one of its own: a fact
 * type with an anchor among its players goes with the first, and brings
 * along what else it links where that is not another anchor's; a fact type
 * of hubs alone goes with its first player's. Each group's elements, in the
 * diagram's order. */
- (NSArray<NSArray<NSString *> *> *)groupsOf:(ORMDiagram *)diagram hubs:(NSSet<NSString *> *)hubs anchors:(NSSet<NSString *> *)anchors
{
	NSMutableDictionary *parents = [NSMutableDictionary dictionary];
	NSMutableDictionary *anchored = [NSMutableDictionary dictionary];
	NSMutableOrderedSet *elements = [NSMutableOrderedSet orderedSet];
	for (ORMShape *shape in diagram.shapes) {
		if (shape.subjectId != nil && ![hubs containsObject:shape.subjectId]) {
			[elements addObject:shape.subjectId];
			ORMGroupRoot(parents, shape.subjectId);
		}
	}
	for (NSString *anchor in anchors) {
		[anchored setObject:anchor forKey:ORMGroupRoot(parents, anchor)];
	}
	/* What each fact type links, apart from itself and the hubs; and its
	 * anchor, its first player that is one. */
	NSMutableDictionary *players = [NSMutableDictionary dictionary];
	NSMutableDictionary *homes = [NSMutableDictionary dictionary];
	for (NSString *element in elements) {
		ORMFactType *fact = [_editor.model elementWithId:element];
		if (![fact isKindOfClass:[ORMFactType class]]) {
			continue;
		}
		NSMutableArray *linked = [NSMutableArray array];
		NSString *first = nil;
		for (ORMRole *role in [fact visibleRoles]) {
			NSString *node = ORMShownNode(role.player, diagram);
			if (node == nil || [node isEqualToString:element]) {
				continue;
			}
			first = first ?: node;
			if ([anchors containsObject:node] && [homes objectForKey:element] == nil) {
				[homes setObject:node forKey:element];
			}
			if (![hubs containsObject:node]) {
				[linked addObject:node];
			}
		}
		if ([linked count] == 0 && first != nil) {
			[linked addObject:[@"hub:" stringByAppendingString:first]];
		}
		[players setObject:linked forKey:element];
	}
	/* What is linked without an anchor first; each anchor's fact types
	 * then; subtyping; what the anchors' fact types bring along; and last
	 * the constraints and notes, with what they are about. Two anchors are
	 * never joined: what would join them is shown in both. */
	for (NSString *element in elements) {
		if ([homes objectForKey:element] == nil) {
			for (NSString *node in [players objectForKey:element]) {
				ORMGroupJoinApart(parents, anchored, element, node);
			}
		}
	}
	for (NSString *element in elements) {
		NSString *home = [homes objectForKey:element];
		if (home != nil) {
			ORMGroupJoinApart(parents, anchored, home, element);
		}
	}
	for (NSString *element in elements) {
		ORMObjectType *type = [_editor.model elementWithId:element];
		if ([type isKindOfClass:[ORMObjectType class]]) {
			for (ORMObjectType *supertype in type.supertypes) {
				NSString *node = ORMShownNode(supertype, diagram);
				if (node != nil && ![hubs containsObject:node]) {
					ORMGroupJoinApart(parents, anchored, element, node);
				}
			}
		}
	}
	for (NSString *element in elements) {
		if ([homes objectForKey:element] != nil) {
			for (NSString *node in [players objectForKey:element]) {
				ORMGroupJoinApart(parents, anchored, element, node);
			}
		}
	}
	for (NSString *element in elements) {
		id subject = [_editor.model elementWithId:element];
		if (![subject isKindOfClass:[ORMConstraint class]] && ![subject isKindOfClass:[ORMModelNote class]]) {
			continue;
		}
		for (ORMShape *linked in [self linkedShapesOf:subject on:diagram]) {
			if (linked.subjectId != nil && ![hubs containsObject:linked.subjectId]) {
				ORMGroupJoinApart(parents, anchored, element, linked.subjectId);
			}
		}
	}
	NSMutableDictionary *byRoot = [NSMutableDictionary dictionary];
	NSMutableArray *order = [NSMutableArray array];
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
	/* What is linked to nothing, together; but not what the groups show
	 * already (an anchor whose fact types all went to others). */
	NSMutableArray *groups = [NSMutableArray array];
	NSMutableArray *loose = [NSMutableArray array];
	NSMutableSet *shown = [NSMutableSet set];
	for (NSMutableArray *group in order) {
		if ([group count] == 1 && [[[diagram shapeForSubject:group[0]] subject] isKindOfClass:[ORMObjectType class]]) {
			[loose addObjectsFromArray:group];
		} else {
			[groups addObject:group];
			[shown addObjectsFromArray:[[self outsidersOfGroup:group on:diagram] array]];
		}
	}
	[loose removeObjectsInArray:[shown allObjects]];
	if ([loose count] > 0) {
		[groups addObject:loose];
	}
	return groups;
}

/* What a group's elements link to that is not in it, in the order met:
 * each shown in it too. The object types its fact types and subtypings
 * link to; the fact types its constraints and notes are about, and their
 * players. */
- (NSOrderedSet<NSString *> *)outsidersOfGroup:(NSArray<NSString *> *)group on:(ORMDiagram *)diagram
{
	NSSet *members = [NSSet setWithArray:group];
	NSMutableOrderedSet *used = [NSMutableOrderedSet orderedSet];
	NSMutableArray *pending = [group mutableCopy];
	for (NSString *element in group) {
		id subject = [_editor.model elementWithId:element];
		if (![subject isKindOfClass:[ORMConstraint class]] && ![subject isKindOfClass:[ORMModelNote class]]) {
			continue;
		}
		for (ORMShape *linked in [self linkedShapesOf:subject on:diagram]) {
			if (linked.kind == ORMShapeFactType && ![members containsObject:linked.subjectId] && ![used containsObject:linked.subjectId]) {
				[used addObject:linked.subjectId];
				[pending addObject:linked.subjectId];
			}
		}
	}
	for (NSString *element in pending) {
		id subject = [_editor.model elementWithId:element];
		NSMutableArray *types = [NSMutableArray array];
		if ([subject isKindOfClass:[ORMFactType class]]) {
			for (ORMRole *role in [(ORMFactType *)subject visibleRoles]) {
				[types addObject:role.player ?: (id)[NSNull null]];
			}
		} else if ([subject isKindOfClass:[ORMObjectType class]]) {
			[types addObjectsFromArray:[(ORMObjectType *)subject supertypes]];
			[types addObjectsFromArray:[(ORMObjectType *)subject subtypes]];
		}
		for (id type in types) {
			NSString *node = type != [NSNull null] ? ORMShownNode(type, diagram) : nil;
			/* An objectified fact type stays where it is. */
			if (node != nil && [node isEqualToString:[type identifier]] && ![members containsObject:node]) {
				[used addObject:node];
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
	/* Each shape's id by its own and by its subject's, the group's one of
	 * each. */
	NSMutableDictionary *index = [NSMutableDictionary dictionary];
	for (ORMShape *shape in shapes) {
		[index setObject:shape.identifier forKey:shape.identifier];
		if (shape.subjectId != nil && [index objectForKey:shape.subjectId] == nil) {
			[index setObject:shape.identifier forKey:shape.subjectId];
		}
	}
	/* The springs, [from, to, rest length], and the shapes they link. */
	NSMutableArray *springs = [NSMutableArray array];
	NSMutableSet *sprung = [NSMutableSet set];
	for (ORMShape *shape in shapes) {
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
			NSString *other = [index objectForKey:hub != nil ? hub.identifier : end];
			if (other != nil && ![other isEqualToString:shape.identifier]) {
				[springs addObject:@[ shape.identifier, other, @(rest) ]];
				[sprung addObject:shape.identifier];
				[sprung addObject:other];
			}
		}
	}
	/* What the springs link, laid out by them; what nothing links, in rows
	 * under it, as square as they come, not pushed off on its own. Each
	 * node's frame, by shape id. */
	NSMutableDictionary *frames = [NSMutableDictionary dictionary];
	double bottom = 0;
	double left = 0;
	if ([sprung count] > 0) {
		DKForceLayout *layout = [[DKForceLayout alloc] init];
		for (ORMShape *shape in shapes) {
			if ([sprung containsObject:shape.identifier]) {
				[layout addNode:shape.identifier size:ORMLayoutSize(shape) fixedAt:nil];
			}
		}
		for (NSArray *spring in springs) {
			[layout addSpringFrom:[spring objectAtIndex:0] to:[spring objectAtIndex:1]
			               length:[[spring objectAtIndex:2] doubleValue]];
		}
		[frames addEntriesFromDictionary:[layout layout]];
		bottom = -DBL_MAX;
		left = DBL_MAX;
		for (NSValue *frame in [frames allValues]) {
			bottom = MAX(bottom, NSMaxY([frame rectValue]));
			left = MIN(left, NSMinX([frame rectValue]));
		}
		bottom += ORMGroupGap / 2;
	}
	NSMutableArray *alone = [NSMutableArray array];
	for (ORMShape *shape in shapes) {
		if (![sprung containsObject:shape.identifier]) {
			[alone addObject:shape];
		}
	}
	NSUInteger across = (NSUInteger)MAX(1, ceil(sqrt((double)[alone count])));
	double x = left;
	double y = bottom;
	double rowHeight = 0;
	for (NSUInteger k = 0; k < [alone count]; k++) {
		ORMShape *shape = [alone objectAtIndex:k];
		NSSize size = ORMLayoutSize(shape);
		if (k > 0 && k % across == 0) {
			x = left;
			y += rowHeight + ORMGroupGap / 2;
			rowHeight = 0;
		}
		[frames setObject:[NSValue valueWithRect:NSMakeRect(x, y, size.width, size.height)] forKey:shape.identifier];
		x += size.width + ORMGroupGap / 2;
		rowHeight = MAX(rowHeight, size.height);
	}
	double minX = DBL_MAX;
	double minY = DBL_MAX;
	double maxX = -DBL_MAX;
	double maxY = -DBL_MAX;
	for (NSValue *value in [frames allValues]) {
		NSRect frame = [value rectValue];
		minX = MIN(minX, NSMinX(frame));
		minY = MIN(minY, NSMinY(frame));
		maxX = MAX(maxX, NSMaxX(frame));
		maxY = MAX(maxY, NSMaxY(frame));
	}
	for (ORMShape *shape in shapes) {
		NSRect frame = [[frames objectForKey:shape.identifier] rectValue];
		NSPoint at = NSMakePoint(round(NSMidX(frame) - minX - NSWidth(shape.bounds) / 2), round(NSMinY(frame) - minY));
		[group.placed setObject:[NSValue valueWithPoint:at] forKey:shape.identifier];
	}
	group.size = count > 0 ? NSMakeSize(maxX - minX, maxY - minY) : NSZeroSize;
}

- (void)arrangeDiagramInGroups:(NSString *)diagramId
{
	ORMDiagram *diagram = [self diagramWithId:diagramId];
	if (diagram == nil || [diagram.shapes count] == 0) {
		return;
	}
	NSSet *hubs = [self hubsOf:diagram];
	NSArray *elementGroups = [self groupsOf:diagram hubs:hubs anchors:[self anchorsOf:diagram]];
	NSMutableArray<ORMLayoutGroup *> *groups = [NSMutableArray array];
	/* An element of a group has one shape there; the rest are spare, and
	 * every shape of what is in none (a hub, an anchor shown elsewhere). */
	NSMutableDictionary<NSString *, NSMutableArray *> *spares = [NSMutableDictionary dictionary];
	for (ORMShape *shape in diagram.shapes) {
		if (shape.subjectId != nil && [spares objectForKey:shape.subjectId] == nil) {
			[spares setObject:[[diagram shapesForSubject:shape.subjectId] mutableCopy] forKey:shape.subjectId];
		}
	}
	NSMutableOrderedSet *shown = [NSMutableOrderedSet orderedSet];
	for (NSArray *elements in elementGroups) {
		ORMLayoutGroup *group = [[ORMLayoutGroup alloc] init];
		for (NSString *element in elements) {
			NSArray *shapes = [diagram shapesForSubject:element];
			if ([shapes count] > 0) {
				[group.shapes addObject:[shapes firstObject]];
				[spares setObject:[[shapes subarrayWithRange:NSMakeRange(1, [shapes count] - 1)] mutableCopy] forKey:element];
			}
		}
		[group.hubs unionOrderedSet:[self outsidersOfGroup:elements on:diagram]];
		[shown unionOrderedSet:group.hubs];
		[groups addObject:group];
	}
	[_editor modelChange:@"Arrange in Groups" with:^{
		/* A shape of each outsider for each group that links to it: its
		 * spare shapes reused, the group's nearest first; more made; the
		 * rest removed. */
		for (NSString *outsider in shown) {
			NSMutableArray *spare = [spares objectForKey:outsider] ?: [NSMutableArray array];
			for (ORMLayoutGroup *group in groups) {
				if (![group.hubs containsObject:outsider]) {
					continue;
				}
				NSPoint centre = ORMCentreOf(group.shapes);
				ORMShape *best = nil;
				double distance = DBL_MAX;
				for (ORMShape *shape in spare) {
					double d = hypot(NSMidX(shape.bounds) - centre.x, NSMidY(shape.bounds) - centre.y);
					if (shape.parent == nil && d < distance) {
						distance = d;
						best = shape;
					}
				}
				if (best != nil) {
					[spare removeObject:best];
				} else {
					id element = [self->_editor.model elementWithId:outsider];
					NSSize size = [self defaultSizeOf:element];
					best = [self addShape:[element isKindOfClass:[ORMFactType class]] ? ORMShapeFactType : ORMShapeObjectType
					                   of:element bounds:NSMakeRect(centre.x, centre.y, size.width, size.height) on:diagram];
				}
				[group.hubShapes setObject:best forKey:outsider];
				[group.shapes addObject:best];
			}
		}
		NSMutableArray *spare = [NSMutableArray array];
		for (NSString *element in [[spares allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			[spare addObjectsFromArray:[spares objectForKey:element]];
		}
		[self removeShapes:spare];
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
		[self orientShapesOn:diagram];
	}];
}

@end
