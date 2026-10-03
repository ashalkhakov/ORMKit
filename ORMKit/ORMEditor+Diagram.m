/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
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

@implementation ORMEditor (ORMDiagramEditing)

#pragma mark Shapes

- (NSXMLElement *)newShape:(NSString *)local subject:(NSString *)subjectId bounds:(NSRect)bounds
{
	NSXMLElement *shape = ORMNewElementWithId(self.document, DIAGRAM, local, nil);
	ORMSetAttribute(shape, @"IsExpanded", @"true");
	ORMSetAttribute(shape, @"AbsoluteBounds", ORMFormatBounds(bounds));
	ORMInsertChild(shape, ORMNewRef(self.document, DIAGRAM, @"Subject", subjectId));
	return shape;
}

- (NSXMLElement *)shapesOf:(NSXMLElement *)diagram
{
	NSXMLElement *shapes = ORMChild(diagram, DIAGRAM, @"Shapes");
	if (shapes == nil) {
		shapes = ORMNewElement(self.document, DIAGRAM, @"Shapes");
		/* Shapes come before the diagram's Subject. */
		[diagram insertChild:shapes atIndex:0];
	}
	return shapes;
}

- (ORMDiagram *)diagramWithId:(NSString *)diagramId
{
	ORMDiagram *diagram = [self.model elementWithId:diagramId];
	return [diagram isKindOfClass:[ORMDiagram class]] ? diagram : nil;
}

/* The shapes on the diagram the element is linked to: a fact type's
 * players, an object type's fact types, a constraint's fact types. */
- (NSArray<ORMShape *> *)linkedShapesOf:(id)element on:(ORMDiagram *)diagram
{
	NSMutableArray *linked = [NSMutableArray array];
	NSMutableArray *subjects = [NSMutableArray array];
	if ([element isKindOfClass:[ORMFactType class]]) {
		for (ORMRole *role in [(ORMFactType *)element visibleRoles]) {
			[subjects addObject:role.player.identifier ?: @""];
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
	id element = [self.model elementWithId:elementId];
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
	ORMDiagram *diagram = [self diagramWithId:diagramId];
	id element = [self.model elementWithId:elementId];
	if (diagram == nil || element == nil) {
		return nil;
	}
	ORMShape *existing = [diagram shapeForSubject:elementId];
	if (existing != nil) {
		return existing.identifier;
	}
	NSString *local = nil;
	if ([element isKindOfClass:[ORMObjectType class]]) {
		if ([(ORMObjectType *)element isImplicitBooleanValue]) {
			return nil;
		}
		local = @"ObjectTypeShape";
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		if ([(ORMFactType *)element kind] != ORMFactTypeOrdinary) {
			return nil;
		}
		local = @"FactTypeShape";
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		ORMConstraint *constraint = element;
		if (![constraint isExternal] || constraint.isImplied) {
			return nil;
		}
		local = constraint.kind == ORMFrequencyConstraint ? @"FrequencyConstraintShape"
			: constraint.kind == ORMRingConstraint ? @"RingConstraintShape"
			: constraint.kind == ORMValueComparisonConstraint ? @"ValueComparisonConstraintShape"
			: @"ExternalConstraintShape";
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		local = @"ModelNoteShape";
	} else {
		return nil;
	}
	NSSize size = [self defaultSizeOf:element];
	NSPoint origin = point;
	if (ORMIsAutomaticPlacement(point)) {
		origin = ORMFreeSpotNear(diagram, [self placeFor:elementId onDiagram:diagramId], size, @[]);
	}
	NSRect bounds = NSMakeRect(origin.x, origin.y, size.width, size.height);
	__block NSString *created = nil;
	[self change:@"Place on Diagram" with:^{
		NSXMLElement *shape = [self newShape:local subject:elementId bounds:bounds];
		if ([element isKindOfClass:[ORMFactType class]]) {
			ORMFactType *fact = element;
			ORMReadingOrder *order = [[fact primaryReading] readingOrder];
			if (order != nil) {
				NSString *text = [[fact primaryReading] expandedText];
				NSRect readingBounds = NSMakeRect(NSMinX(bounds), NSMaxY(bounds) + ORMReadingGap,
				                                  MAX(0.2, 0.05 * [text length]) * 72.0, ORMReadingShapeHeight);
				NSXMLElement *reading = [self newShape:@"ReadingShape" subject:order.identifier bounds:readingBounds];
				NSXMLElement *relative = ORMNewElement(self.document, DIAGRAM, @"RelativeShapes");
				[relative addChild:reading];
				ORMInsertChild(shape, relative);
			}
			NSXMLElement *display = ORMNewElement(self.document, DIAGRAM, @"RoleDisplayOrder");
			for (ORMRole *role in fact.roles) {
				[display addChild:ORMNewRef(self.document, DIAGRAM, @"Role", role.identifier)];
			}
			ORMInsertChild(shape, display);
		}
		[[self shapesOf:diagram.element] addChild:shape];
		created = ORMAttribute(shape, @"id");
	}];
	return created;
}

- (void)showFactType:(NSString *)factTypeId onDiagram:(NSString *)diagramId at:(NSPoint)point
{
	ORMFactType *fact = [self.model elementWithId:factTypeId];
	[self group:@"Add Fact Type" with:^{
		for (ORMRole *role in [fact visibleRoles]) {
			if (role.player != nil && [[self diagramWithId:diagramId] shapeForSubject:role.player.identifier] == nil) {
				[self placeElement:role.player.identifier onDiagram:diagramId at:ORMAutomaticPlacement];
			}
		}
		[self placeElement:factTypeId onDiagram:diagramId at:point];
	}];
}

- (void)removeShapesOfSubjects:(NSSet<NSString *> *)subjectIds
{
	for (ORMDiagram *diagram in self.model.diagrams) {
		for (ORMShape *shape in [diagram allShapes]) {
			if ([subjectIds containsObject:shape.subjectId ?: @""]) {
				[shape.element detach];
			}
		}
	}
}

#pragma mark Diagrams

- (NSString *)addDiagramNamed:(NSString *)name
{
	__block NSString *created = nil;
	[self change:@"Add Diagram" with:^{
		NSXMLElement *root = [self.document rootElement];
		NSXMLElement *diagram = ORMNewElementWithId(self.document, DIAGRAM, @"ORMDiagram", nil);
		ORMSetAttribute(diagram, @"IsCompleteView", @"false");
		ORMSetAttribute(diagram, @"Name", [name length] > 0 ? name : [self nextDiagramName]);
		ORMSetAttribute(diagram, @"BaseFontName", @"Tahoma");
		ORMSetAttribute(diagram, @"BaseFontSize", @"0.0972222238779068");
		[diagram addChild:ORMNewRef(self.document, DIAGRAM, @"Subject", self.model.identifier)];
		/* After the last diagram, before what NORMA's extensions keep. */
		NSArray *diagrams = ORMChildren(root, DIAGRAM, @"ORMDiagram");
		NSUInteger index = [diagrams count] > 0 ? [[diagrams lastObject] index] + 1 : [root childCount];
		[root insertChild:diagram atIndex:index];
		created = ORMAttribute(diagram, @"id");
	}];
	return created;
}

- (NSString *)nextDiagramName
{
	NSMutableSet *names = [NSMutableSet set];
	for (ORMDiagram *diagram in self.model.diagrams) {
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
		ORMShape *shape = [self.model elementWithId:shapeId];
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
	[self change:@"Move" with:^{
		for (ORMShape *shape in moved) {
			NSRect bounds = NSOffsetRect(shape.bounds, delta.width, delta.height);
			ORMSetAttribute(shape.element, @"AbsoluteBounds", ORMFormatBounds(bounds));
		}
	}];
}

- (void)setBounds:(NSRect)bounds ofShape:(NSString *)shapeId
{
	ORMShape *shape = [self.model elementWithId:shapeId];
	if (![shape isKindOfClass:[ORMShape class]] || NSEqualRects(shape.bounds, bounds)) {
		return;
	}
	NSSize delta = NSMakeSize(NSMinX(bounds) - NSMinX(shape.bounds), NSMinY(bounds) - NSMinY(shape.bounds));
	NSArray *carried = [self movedShapes:@[ shapeId ]];
	[self change:@"Resize" with:^{
		ORMSetAttribute(shape.element, @"AbsoluteBounds", ORMFormatBounds(bounds));
		for (ORMShape *child in carried) {
			if (child != shape) {
				ORMSetAttribute(child.element, @"AbsoluteBounds",
				                ORMFormatBounds(NSOffsetRect(child.bounds, delta.width, delta.height)));
			}
		}
	}];
}

- (BOOL)setRoleDisplayOrder:(NSArray<NSString *> *)roleIds ofShape:(NSString *)shapeId reason:(NSString **)reason
{
	ORMShape *shape = [self.model elementWithId:shapeId];
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
	[self change:@"Reorder Roles" with:^{
		[ORMChild(shape.element, DIAGRAM, @"RoleDisplayOrder") detach];
		NSXMLElement *display = ORMNewElement(self.document, DIAGRAM, @"RoleDisplayOrder");
		for (NSString *roleId in roleIds) {
			[display addChild:ORMNewRef(self.document, DIAGRAM, @"Role", roleId)];
		}
		ORMInsertChild(shape.element, display);
	}];
	return YES;
}

- (void)setOrientation:(ORMFactTypeOrientation)orientation ofShape:(NSString *)shapeId
{
	ORMShape *shape = [self.model elementWithId:shapeId];
	if (![shape isKindOfClass:[ORMShape class]] || shape.kind != ORMShapeFactType || shape.orientation == orientation) {
		return;
	}
	NSString *name = orientation == ORMFactTypeVerticalRotatedRight ? @"VerticalRotatedRight"
		: orientation == ORMFactTypeVerticalRotatedLeft ? @"VerticalRotatedLeft" : nil;
	NSRect bounds = shape.bounds;
	BOOL wasVertical = shape.orientation != ORMFactTypeHorizontal;
	BOOL vertical = orientation != ORMFactTypeHorizontal;
	if (wasVertical != vertical) {
		NSPoint center = [shape center];
		bounds = NSMakeRect(center.x - NSHeight(bounds) / 2, center.y - NSWidth(bounds) / 2, NSHeight(bounds),
		                    NSWidth(bounds));
	}
	[self change:@"Rotate Fact Type" with:^{
		ORMSetAttribute(shape.element, @"DisplayOrientation", name);
		ORMSetAttribute(shape.element, @"AbsoluteBounds", ORMFormatBounds(bounds));
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
	[self change:@"Arrange Diagram" with:^{
		for (ORMShape *shape in shapes) {
			NSPoint at = [[placed objectForKey:shape.identifier] pointValue];
			NSSize delta = NSMakeSize(at.x - NSMinX(shape.bounds), at.y - NSMinY(shape.bounds));
			for (ORMShape *moved in [self movedShapes:@[ shape.identifier ]]) {
				ORMSetAttribute(moved.element, @"AbsoluteBounds",
				                ORMFormatBounds(NSOffsetRect(moved.bounds, delta.width, delta.height)));
			}
		}
	}];
}

@end
