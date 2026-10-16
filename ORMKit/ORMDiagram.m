/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModelPriv.h"
#import "ORMXML.h"

#define DIAGRAM ORMDiagramNamespace

static ORMShapeKind
ORMShapeKindNamed(NSString *local)
{
	NSDictionary *kinds = @{ @"ObjectTypeShape": @(ORMShapeObjectType),
	                         @"FactTypeShape": @(ORMShapeFactType),
	                         @"ReadingShape": @(ORMShapeReading),
	                         @"RoleNameShape": @(ORMShapeRoleName),
	                         @"ObjectifiedFactTypeNameShape": @(ORMShapeObjectifiedFactTypeName),
	                         @"ValueConstraintShape": @(ORMShapeValueConstraint),
	                         @"ExternalConstraintShape": @(ORMShapeExternalConstraint),
	                         @"FrequencyConstraintShape": @(ORMShapeFrequencyConstraint),
	                         @"RingConstraintShape": @(ORMShapeRingConstraint),
	                         @"ValueComparisonConstraintShape": @(ORMShapeValueComparisonConstraint),
	                         @"ModelNoteShape": @(ORMShapeModelNote) };
	NSNumber *kind = [kinds objectForKey:local];
	return kind != nil ? [kind integerValue] : ORMShapeUnknown;
}

@implementation ORMShape

/* Kept as the file has them: NORMA's inches, read back into points, so
 * that the model is what reading the written file gives. */
- (void)setBounds:(NSRect)bounds
{
	_bounds = ORMParseBounds(ORMFormatBounds(bounds));
}

- (void)reset
{
	[super reset];
	_kind = ORMShapeUnknown;
	_bounds = NSZeroRect;
	_subject = nil;
	_subjectId = nil;
	_diagram = nil;
	_parent = nil;
	_relativeShapes = nil;
	_isExpanded = NO;
	_roleDisplayOrder = nil;
	_orientation = ORMFactTypeHorizontal;
	_constraintsBelow = _expandsReferenceMode = NO;
}

- (ORMObjectType *)objectType
{
	return [self.subject isKindOfClass:[ORMObjectType class]] ? self.subject : nil;
}

- (ORMFactType *)factType
{
	return [self.subject isKindOfClass:[ORMFactType class]] ? self.subject : nil;
}

- (ORMConstraint *)constraint
{
	return [self.subject isKindOfClass:[ORMConstraint class]] ? self.subject : nil;
}

- (NSPoint)center
{
	return NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds));
}

@end

@implementation ORMDiagram
{
	NSArray<ORMShape *> *_allShapes;
}

- (void)reset
{
	[super reset];
	_allShapes = nil;
	_shapes = nil;
	_isCompleteView = NO;
	_baseFontName = nil;
	_baseFontSize = 0;
}

- (ORMShape *)readShape:(NSXMLElement *)element parent:(ORMShape *)parent into:(NSMutableArray *)all
{
	ORMShape *shape = [self.model element:[ORMShape class] for:element];
	shape.kind = ORMShapeKindNamed([element localName]);
	shape.diagram = self;
	shape.parent = parent;
	shape.bounds = ORMParseBounds(ORMAttribute(element, @"AbsoluteBounds"));
	shape.isExpanded = ORMBoolAttribute(element, @"IsExpanded", NO);
	shape.subjectId = ORMRef(ORMChild(element, DIAGRAM, @"Subject"));
	shape.subject = [self.model elementWithId:shape.subjectId];
	shape.expandsReferenceMode = ORMBoolAttribute(element, @"ExpandRefMode", NO);
	NSString *orientation = ORMAttribute(element, @"DisplayOrientation");
	if ([orientation isEqualToString:@"VerticalRotatedRight"]) {
		shape.orientation = ORMFactTypeVerticalRotatedRight;
	} else if ([orientation isEqualToString:@"VerticalRotatedLeft"]) {
		shape.orientation = ORMFactTypeVerticalRotatedLeft;
	}
	shape.constraintsBelow = [ORMAttribute(element, @"ConstraintDisplayPosition") isEqualToString:@"Bottom"];

	if (shape.kind == ORMShapeFactType) {
		/* The roles the shape shows, left to right: its RoleDisplayOrder
		 * when it has one and it still names every role, else the fact
		 * type's own order. */
		NSArray *factRoles = shape.factType.roles ?: @[];
		NSMutableArray *order = [NSMutableArray array];
		for (NSXMLElement *roleRef in ORMGrandchildren(element, DIAGRAM, @"RoleDisplayOrder", DIAGRAM, @"Role")) {
			id role = [self.model elementWithId:ORMRef(roleRef)];
			if ([role isKindOfClass:[ORMRole class]] && [factRoles indexOfObjectIdenticalTo:role] != NSNotFound) {
				[order addObject:role];
			}
		}
		shape.roleDisplayOrder = [order count] == [factRoles count] ? order : factRoles;
	} else {
		shape.roleDisplayOrder = @[];
	}

	[all addObject:shape];
	[self.model registerElement:shape];
	NSMutableArray *relative = [NSMutableArray array];
	for (NSXMLNode *node in [ORMChild(element, DIAGRAM, @"RelativeShapes") children]) {
		if ([node kind] == NSXMLElementKind) {
			[relative addObject:[self readShape:(NSXMLElement *)node parent:shape into:all]];
		}
	}
	shape.relativeShapes = relative;
	return shape;
}

- (void)readShapes
{
	self.isCompleteView = ORMBoolAttribute(self.element, @"IsCompleteView", NO);
	self.baseFontName = ORMAttribute(self.element, @"BaseFontName") ?: @"Tahoma";
	NSString *size = ORMAttribute(self.element, @"BaseFontSize");
	/* NORMA keeps the size in inches too. */
	self.baseFontSize = size != nil ? [size doubleValue] * ORMPointsPerInch : 7.0;
	NSMutableArray *shapes = [NSMutableArray array];
	NSMutableArray *all = [NSMutableArray array];
	for (NSXMLNode *node in [ORMChild(self.element, DIAGRAM, @"Shapes") children]) {
		if ([node kind] == NSXMLElementKind) {
			[shapes addObject:[self readShape:(NSXMLElement *)node parent:nil into:all]];
		}
	}
	self.shapes = shapes;
	_allShapes = all;
}

- (NSArray<ORMShape *> *)allShapes
{
	if (_allShapes == nil) {
		/* Each shape, then those placed on it, in the file's order. */
		NSMutableArray *all = [NSMutableArray array];
		NSMutableArray *pending = [NSMutableArray arrayWithArray:[[self.shapes reverseObjectEnumerator] allObjects]];
		while ([pending count] > 0) {
			ORMShape *shape = [pending lastObject];
			[pending removeLastObject];
			[all addObject:shape];
			[pending addObjectsFromArray:[[shape.relativeShapes reverseObjectEnumerator] allObjects]];
		}
		_allShapes = all;
	}
	return _allShapes;
}

- (void)addShape:(ORMShape *)shape
{
	shape.diagram = self;
	if (shape.parent != nil) {
		shape.parent.relativeShapes = [shape.parent.relativeShapes ?: @[] arrayByAddingObject:shape];
	} else {
		self.shapes = [self.shapes ?: @[] arrayByAddingObject:shape];
	}
	[self.model registerElement:shape];
	_allShapes = nil;
}

- (void)removeShape:(ORMShape *)shape
{
	for (ORMShape *child in [shape.relativeShapes copy]) {
		[self removeShape:child];
	}
	if (shape.parent != nil) {
		shape.parent.relativeShapes = ORMWithout(shape.parent.relativeShapes, shape);
	} else {
		self.shapes = ORMWithout(self.shapes, shape);
	}
	[self.model removeElement:shape];
	_allShapes = nil;
}

- (NSArray<ORMShape *> *)shapesForSubject:(NSString *)subjectId
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMShape *shape in [self allShapes]) {
		if ([shape.subjectId isEqualToString:subjectId]) {
			[found addObject:shape];
		}
	}
	return found;
}

- (ORMShape *)shapeForSubject:(NSString *)subjectId
{
	for (ORMShape *shape in [self allShapes]) {
		if ([shape.subjectId isEqualToString:subjectId]) {
			return shape;
		}
	}
	return nil;
}

- (NSRect)extent
{
	NSRect extent = NSZeroRect;
	for (ORMShape *shape in [self allShapes]) {
		extent = NSIsEmptyRect(extent) ? shape.bounds : NSUnionRect(extent, shape.bounds);
	}
	return extent;
}

@end
