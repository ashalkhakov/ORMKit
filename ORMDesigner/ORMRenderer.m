/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMRenderer.h"

/* A role box, in points: NORMA's 0.16 by 0.11 inches. */
static const double ORMBoxWidth = 0.16 * 72.0;
static const double ORMBoxHeight = 0.11 * 72.0;
/* How far an objectified fact type's outline stands off its boxes. */
static const double ORMObjectifiedPadding = 5.0;

@implementation ORMDrawingState

- (instancetype)init
{
	if ((self = [super init])) {
		_selectedShapes = [NSSet set];
		_selectedRoles = [NSSet set];
		_pickedSequences = @[];
	}
	return self;
}

@end

#pragma mark Colours and fonts

static NSColor *
ORMRGB(double r, double g, double b)
{
	return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
}

/* Whether the view being drawn is in a dark appearance. */
static BOOL
ORMIsDark(void)
{
#if defined(__APPLE__)
	if (@available(macOS 10.14, *)) {
		NSAppearanceName name = [[NSAppearance currentAppearance]
			bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
		return [name isEqualToString:NSAppearanceNameDarkAqua];
	}
#endif
	return NO;
}

NSColor *
ORMInkColor(void)
{
	return ORMIsDark() ? ORMRGB(0.88, 0.88, 0.88) : ORMRGB(0.0, 0.0, 0.0);
}

NSColor *
ORMPaperColor(void)
{
	return ORMIsDark() ? ORMRGB(0.12, 0.12, 0.13) : ORMRGB(1.0, 1.0, 1.0);
}

NSColor *
ORMObjectTypeColor(void)
{
	return ORMIsDark() ? ORMRGB(0.55, 0.70, 1.0) : ORMRGB(0.0, 0.0, 0.55);
}

NSColor *
ORMConstraintColor(ORMModality modality)
{
	if (modality == ORMDeontic) {
		return ORMIsDark() ? ORMRGB(0.40, 0.65, 1.0) : ORMRGB(0.0, 0.35, 0.85);
	}
	return ORMIsDark() ? ORMRGB(0.85, 0.55, 0.95) : ORMRGB(0.50, 0.0, 0.50);
}

NSColor *
ORMSelectionColor(void)
{
	return ORMRGB(0.10, 0.45, 0.95);
}

NSColor *
ORMPickColor(void)
{
	return ORMRGB(0.95, 0.55, 0.10);
}

NSColor *
ORMErrorColor(void)
{
	return ORMRGB(0.85, 0.10, 0.10);
}

NSFont *
ORMDiagramFont(ORMDiagram *diagram, BOOL bold)
{
	double size = diagram.baseFontSize > 1 ? diagram.baseFontSize : 7.0;
	NSFont *font = nil;
	NSString *name = diagram.baseFontName;
	if ([name length] > 0) {
		font = [NSFont fontWithName:bold ? [name stringByAppendingString:@" Bold"] : name size:size];
	}
	if (font == nil) {
		font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
	}
	return font;
}

static NSDictionary *
ORMTextAttributes(ORMDiagram *diagram, NSColor *color, BOOL bold)
{
	return @{ NSFontAttributeName: ORMDiagramFont(diagram, bold), NSForegroundColorAttributeName: color };
}

#pragma mark Geometry

static NSArray<ORMRole *> *
ORMShownRoles(ORMShape *shape)
{
	NSMutableArray *roles = [NSMutableArray array];
	for (ORMRole *role in shape.roleDisplayOrder) {
		if (!role.player.isImplicitBooleanValue) {
			[roles addObject:role];
		}
	}
	return roles;
}

NSRect
ORMRoleStrip(ORMShape *shape)
{
	NSUInteger count = MAX([ORMShownRoles(shape) count], (NSUInteger)1);
	NSRect bounds = shape.bounds;
	if (shape.orientation == ORMFactTypeHorizontal) {
		double width = ORMBoxWidth * count;
		return NSMakeRect(NSMidX(bounds) - width / 2, NSMidY(bounds) - ORMBoxHeight / 2, width, ORMBoxHeight);
	}
	double height = ORMBoxWidth * count;
	return NSMakeRect(NSMidX(bounds) - ORMBoxHeight / 2, NSMidY(bounds) - height / 2, ORMBoxHeight, height);
}

NSArray<NSValue *> *
ORMRoleBoxes(ORMShape *shape)
{
	NSArray *roles = ORMShownRoles(shape);
	NSRect strip = ORMRoleStrip(shape);
	NSMutableArray *boxes = [NSMutableArray array];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		NSRect box;
		switch (shape.orientation) {
		case ORMFactTypeHorizontal:
			box = NSMakeRect(NSMinX(strip) + i * ORMBoxWidth, NSMinY(strip), ORMBoxWidth, ORMBoxHeight);
			break;
		case ORMFactTypeVerticalRotatedRight:
			box = NSMakeRect(NSMinX(strip), NSMinY(strip) + i * ORMBoxWidth, ORMBoxHeight, ORMBoxWidth);
			break;
		case ORMFactTypeVerticalRotatedLeft:
			box = NSMakeRect(NSMinX(strip), NSMaxY(strip) - (i + 1) * ORMBoxWidth, ORMBoxHeight, ORMBoxWidth);
			break;
		}
		[boxes addObject:[NSValue valueWithRect:box]];
	}
	return boxes;
}

NSRect
ORMRoleBox(ORMShape *shape, ORMRole *role)
{
	NSArray *roles = ORMShownRoles(shape);
	NSUInteger index = [roles indexOfObjectIdenticalTo:role];
	if (index == NSNotFound) {
		return NSZeroRect;
	}
	return [[ORMRoleBoxes(shape) objectAtIndex:index] rectValue];
}

NSPoint
ORMEdgePoint(NSRect rect, NSPoint toward)
{
	NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));
	double dx = toward.x - center.x;
	double dy = toward.y - center.y;
	if (fabs(dx) < 0.0001 && fabs(dy) < 0.0001) {
		return center;
	}
	double halfWidth = NSWidth(rect) / 2;
	double halfHeight = NSHeight(rect) / 2;
	double scale = 1.0 / MAX(fabs(dx) / MAX(halfWidth, 0.0001), fabs(dy) / MAX(halfHeight, 0.0001));
	return NSMakePoint(center.x + dx * scale, center.y + dy * scale);
}

/* The outline an objectified fact type is drawn in. */
static NSRect
ORMObjectifiedOutline(ORMShape *factTypeShape)
{
	return NSInsetRect(ORMRoleStrip(factTypeShape), -ORMObjectifiedPadding - 3, -ORMObjectifiedPadding);
}

/* What stands for the object type on the diagram: its shape, or the
 * objectified fact type's outline. */
static NSRect
ORMObjectTypeRect(ORMShape *shape)
{
	if (shape.kind == ORMShapeFactType) {
		return ORMObjectifiedOutline(shape);
	}
	return shape.bounds;
}

ORMShape *
ORMShapeOfObjectType(ORMDiagram *diagram, ORMObjectType *type, NSPoint near)
{
	if (type == nil) {
		return nil;
	}
	NSMutableArray *candidates = [[diagram shapesForSubject:type.identifier] mutableCopy];
	if (type.nestedFactType != nil) {
		[candidates addObjectsFromArray:[diagram shapesForSubject:type.nestedFactType.identifier]];
	}
	ORMShape *best = nil;
	double distance = DBL_MAX;
	for (ORMShape *shape in candidates) {
		if (shape.kind != ORMShapeObjectType && shape.kind != ORMShapeFactType) {
			continue;
		}
		NSRect rect = ORMObjectTypeRect(shape);
		double d = hypot(NSMidX(rect) - near.x, NSMidY(rect) - near.y);
		if (d < distance) {
			distance = d;
			best = shape;
		}
	}
	return best;
}

BOOL
ORMRoleLine(ORMDiagram *diagram, ORMShape *factTypeShape, ORMRole *role, NSPoint *atRole, NSPoint *atPlayer)
{
	NSRect box = ORMRoleBox(factTypeShape, role);
	if (NSIsEmptyRect(box)) {
		return NO;
	}
	NSPoint center = NSMakePoint(NSMidX(box), NSMidY(box));
	ORMShape *player = ORMShapeOfObjectType(diagram, role.player, center);
	if (player == nil || player == factTypeShape) {
		return NO;
	}
	NSRect target = ORMObjectTypeRect(player);
	NSPoint targetCenter = NSMakePoint(NSMidX(target), NSMidY(target));
	/* A binary's end roles leave from the strip's ends, as NORMA draws
	 * them, when the player lies that way. */
	NSRect strip = ORMRoleStrip(factTypeShape);
	NSArray *roles = ORMShownRoles(factTypeShape);
	NSPoint from = ORMEdgePoint(box, targetCenter);
	if (factTypeShape.orientation == ORMFactTypeHorizontal && [roles count] > 1) {
		if ([roles firstObject] == role && targetCenter.x < NSMinX(strip)) {
			from = NSMakePoint(NSMinX(box), NSMidY(box));
		} else if ([roles lastObject] == role && targetCenter.x > NSMaxX(strip)) {
			from = NSMakePoint(NSMaxX(box), NSMidY(box));
		} else {
			from = NSMakePoint(NSMidX(box), targetCenter.y < NSMidY(box) ? NSMinY(box) : NSMaxY(box));
		}
	}
	*atRole = from;
	*atPlayer = ORMEdgePoint(target, from);
	return YES;
}

NSPoint
ORMRoleAttachment(ORMShape *factTypeShape, ORMRole *role, NSPoint from)
{
	NSRect box = ORMRoleBox(factTypeShape, role);
	if (factTypeShape.orientation == ORMFactTypeHorizontal) {
		return NSMakePoint(NSMidX(box), from.y < NSMidY(box) ? NSMinY(box) : NSMaxY(box));
	}
	return NSMakePoint(from.x < NSMidX(box) ? NSMinX(box) : NSMaxX(box), NSMidY(box));
}

NSString *
ORMReadingDisplayText(ORMShape *factTypeShape, ORMReadingOrder *order)
{
	ORMReading *reading = [order.readings firstObject];
	if (reading == nil) {
		return @"";
	}
	NSArray *shown = ORMShownRoles(factTypeShape);
	ORMReadingText *text = [ORMReadingText readingTextWithString:reading.text arity:[order.roles count] reason:NULL];
	if (text == nil) {
		return reading.text;
	}
	/* A binary or unary reading in its boxes' order loses its
	 * placeholders; one against them is marked so. */
	BOOL simple = [shown count] <= 2;
	BOOL along = [order.roles isEqualToArray:shown];
	BOOL against = [shown count] == 2 && [order.roles isEqualToArray:[[shown reverseObjectEnumerator] allObjects]];
	if (simple && (along || against || [shown count] == 1)) {
		NSString *phrase = [text expandWithNames:^NSString *(NSUInteger index, NSString *pre, NSString *post) {
			return [NSString stringWithFormat:@"%@%@", pre ?: @"", post ?: @""];
		}];
		phrase = [phrase stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		return against ? [@"◀ " stringByAppendingString:phrase] : phrase;
	}
	NSString *phrase = [text expandWithNames:^NSString *(NSUInteger index, NSString *pre, NSString *post) {
		return [NSString stringWithFormat:@"%@…%@", pre ?: @"", post ?: @""];
	}];
	return [phrase stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static NSString *
ORMReferenceModeLine(ORMObjectType *type)
{
	if (type.referenceMode == nil) {
		return nil;
	}
	switch (type.referenceModeKind) {
	case ORMReferenceModePopular:
		return [NSString stringWithFormat:@"(.%@)", type.referenceMode];
	case ORMReferenceModeUnitBased:
		return [NSString stringWithFormat:@"(%@:)", type.referenceMode];
	default:
		return [NSString stringWithFormat:@"(%@)", type.referenceMode];
	}
}

static NSString *
ORMNameLine(ORMObjectType *type)
{
	NSMutableString *name = [NSMutableString stringWithString:type.name ?: @""];
	if (type.isIndependent && type.kind != ORMObjectifiedType) {
		[name appendString:@" !"];
	}
	if (type.isExternal) {
		[name appendString:@" ^"];
	}
	return name;
}

NSSize
ORMObjectTypeSizeFor(ORMObjectType *type, ORMDiagram *diagram)
{
	NSDictionary *attributes = ORMTextAttributes(diagram, ORMInkColor(), NO);
	NSSize name = [ORMNameLine(type) sizeWithAttributes:attributes];
	NSString *mode = ORMReferenceModeLine(type);
	NSSize modeSize = mode != nil ? [mode sizeWithAttributes:attributes] : NSZeroSize;
	double width = MAX(name.width, modeSize.width) + 12;
	double height = name.height + modeSize.height + 8;
	return NSMakeSize(ceil(MAX(width, 0.36 * 72)), ceil(MAX(height, mode != nil ? 0.359 * 72 : 0.2295 * 72)));
}

NSSize
ORMReadingSizeFor(NSString *text, ORMDiagram *diagram)
{
	NSSize size = [text sizeWithAttributes:ORMTextAttributes(diagram, ORMInkColor(), NO)];
	return NSMakeSize(ceil(size.width + 2), ceil(size.height));
}

#pragma mark Drawing pieces

static void
ORMStroke(NSBezierPath *path, NSColor *color, double width, BOOL dashed)
{
	[color setStroke];
	[path setLineWidth:width];
	if (dashed) {
		CGFloat pattern[2] = { 2.0, 2.0 };
		[path setLineDash:pattern count:2 phase:0];
	}
	[path stroke];
}

static NSBezierPath *
ORMLine(NSPoint from, NSPoint to)
{
	NSBezierPath *path = [NSBezierPath bezierPath];
	[path moveToPoint:from];
	[path lineToPoint:to];
	return path;
}

static NSBezierPath *
ORMRoundedRect(NSRect rect)
{
	double radius = MIN(MIN(NSHeight(rect), NSWidth(rect)) / 2.6, 9.0);
	return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
}

static void
ORMDrawCentered(NSString *text, NSRect rect, NSDictionary *attributes)
{
	NSSize size = [text sizeWithAttributes:attributes];
	[text drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2, NSMidY(rect) - size.height / 2)
	   withAttributes:attributes];
}

static void
ORMDrawSelection(NSRect rect, BOOL rounded)
{
	NSRect outset = NSInsetRect(rect, -2.5, -2.5);
	NSBezierPath *path = rounded ? ORMRoundedRect(outset) : [NSBezierPath bezierPathWithRect:outset];
	ORMStroke(path, ORMSelectionColor(), 1.5, NO);
}

static void
ORMDrawObjectType(ORMShape *shape, ORMDrawingState *state)
{
	ORMObjectType *type = shape.objectType;
	if (type == nil) {
		return;
	}
	NSRect rect = NSInsetRect(shape.bounds, 0.5, 0.5);
	NSBezierPath *outline = ORMRoundedRect(rect);
	[ORMPaperColor() setFill];
	[outline fill];
	ORMStroke(outline, ORMObjectTypeColor(), 1.0, type.kind == ORMValueType);
	NSDictionary *attributes = ORMTextAttributes(shape.diagram, ORMInkColor(), NO);
	NSString *name = ORMNameLine(type);
	NSString *mode = ORMReferenceModeLine(type);
	if (mode == nil) {
		ORMDrawCentered(name, rect, attributes);
	} else {
		NSSize nameSize = [name sizeWithAttributes:attributes];
		NSSize modeSize = [mode sizeWithAttributes:attributes];
		double top = NSMidY(rect) - (nameSize.height + modeSize.height) / 2;
		[name drawAtPoint:NSMakePoint(NSMidX(rect) - nameSize.width / 2, top) withAttributes:attributes];
		[mode drawAtPoint:NSMakePoint(NSMidX(rect) - modeSize.width / 2, top + nameSize.height) withAttributes:attributes];
	}
	if (!state.forPrinting && [state.selectedShapes containsObject:shape.identifier]) {
		ORMDrawSelection(shape.bounds, YES);
	}
	if (!state.forPrinting && [state.hoverElement isEqualToString:type.identifier]) {
		ORMStroke(ORMRoundedRect(NSInsetRect(shape.bounds, -1.5, -1.5)), [ORMSelectionColor() colorWithAlphaComponent:0.4],
		          1.0, NO);
	}
}

/* A uniqueness bar over the roles the constraint covers, at a level above
 * (or below) the boxes: solid over each covered box, dashed across boxes
 * it skips; doubled for a preferred identifier. */
static void
ORMDrawUniquenessBar(ORMShape *shape, ORMConstraint *constraint, NSUInteger level, BOOL selected)
{
	NSArray *roles = ORMShownRoles(shape);
	NSArray *boxes = ORMRoleBoxes(shape);
	NSSet *covered = [NSSet setWithArray:[constraint allRoles]];
	NSInteger first = -1;
	NSInteger last = -1;
	for (NSUInteger i = 0; i < [roles count]; i++) {
		if ([covered containsObject:[roles objectAtIndex:i]]) {
			first = first < 0 ? (NSInteger)i : first;
			last = (NSInteger)i;
		}
	}
	if (first < 0) {
		return;
	}
	NSColor *color = selected ? ORMSelectionColor() : ORMConstraintColor(constraint.modality);
	BOOL preferred = constraint.preferredIdentifierFor != nil;
	BOOL horizontal = shape.orientation == ORMFactTypeHorizontal;
	double offset = 2.5 + level * 3.5;
	for (NSInteger i = first; i <= last; i++) {
		NSRect box = [[boxes objectAtIndex:(NSUInteger)i] rectValue];
		BOOL isCovered = [covered containsObject:[roles objectAtIndex:(NSUInteger)i]];
		NSPoint a;
		NSPoint b;
		if (horizontal) {
			double y = shape.constraintsBelow ? NSMaxY(box) + offset : NSMinY(box) - offset;
			a = NSMakePoint(NSMinX(box) + 1.2, y);
			b = NSMakePoint(NSMaxX(box) - 1.2, y);
		} else {
			double x = NSMinX(box) - offset;
			a = NSMakePoint(x, NSMinY(box) + 1.2);
			b = NSMakePoint(x, NSMaxY(box) - 1.2);
		}
		ORMStroke(ORMLine(a, b), color, 1.0, !isCovered);
		if (preferred && isCovered) {
			double shift = 1.6;
			NSPoint c = horizontal ? NSMakePoint(a.x, a.y + (shape.constraintsBelow ? shift : -shift))
			                       : NSMakePoint(a.x - shift, a.y);
			NSPoint d = horizontal ? NSMakePoint(b.x, b.y + (shape.constraintsBelow ? shift : -shift))
			                       : NSMakePoint(b.x - shift, b.y);
			ORMStroke(ORMLine(c, d), color, 1.0, NO);
		}
	}
}

static void
ORMDrawDot(NSPoint at, double radius, NSColor *color, BOOL filled)
{
	NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(at.x - radius, at.y - radius, radius * 2,
	                                                                      radius * 2)];
	if (filled) {
		[color setFill];
		[dot fill];
	} else {
		[ORMPaperColor() setFill];
		[dot fill];
		ORMStroke(dot, color, 1.0, NO);
	}
}

static void
ORMDrawFactType(ORMShape *shape, ORMDrawingState *state)
{
	ORMFactType *fact = shape.factType;
	if (fact == nil) {
		return;
	}
	ORMDiagram *diagram = shape.diagram;
	NSArray *roles = ORMShownRoles(shape);
	NSArray *boxes = ORMRoleBoxes(shape);

	/* The lines to the players first, under everything. */
	for (ORMRole *role in roles) {
		NSPoint atRole;
		NSPoint atPlayer;
		if (!ORMRoleLine(diagram, shape, role, &atRole, &atPlayer)) {
			continue;
		}
		ORMStroke(ORMLine(atRole, atPlayer), ORMInkColor(), 0.75, NO);
		if (role.isMandatory) {
			ORMModality modality = ORMAlethic;
			for (ORMConstraint *constraint in role.constraints) {
				if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple) {
					modality = constraint.modality;
				}
			}
			NSPoint direction = NSMakePoint(atRole.x - atPlayer.x, atRole.y - atPlayer.y);
			double length = MAX(hypot(direction.x, direction.y), 0.001);
			NSPoint dot = NSMakePoint(atPlayer.x + direction.x / length * 2.6, atPlayer.y + direction.y / length * 2.6);
			ORMDrawDot(dot, 2.3, ORMConstraintColor(modality), modality == ORMAlethic);
		}
	}

	if (fact.objectifyingType != nil) {
		NSRect outline = ORMObjectifiedOutline(shape);
		NSBezierPath *path = ORMRoundedRect(outline);
		[ORMPaperColor() setFill];
		[path fill];
		ORMStroke(path, ORMObjectTypeColor(), 1.0, NO);
		NSDictionary *attributes = ORMTextAttributes(diagram, ORMInkColor(), NO);
		NSString *name = [NSString stringWithFormat:@"\"%@\"", fact.objectifyingType.name];
		NSSize size = [name sizeWithAttributes:attributes];
		BOOL hasLabelShape = NO;
		for (ORMShape *child in shape.relativeShapes) {
			if (child.kind == ORMShapeObjectifiedFactTypeName) {
				hasLabelShape = YES;
				[name drawAtPoint:child.bounds.origin withAttributes:attributes];
			}
		}
		if (!hasLabelShape) {
			[name drawAtPoint:NSMakePoint(NSMidX(outline) - size.width / 2, NSMinY(outline) - size.height - 1)
			   withAttributes:attributes];
		}
	}

	for (NSUInteger i = 0; i < [boxes count]; i++) {
		NSRect box = [[boxes objectAtIndex:i] rectValue];
		ORMRole *role = [roles objectAtIndex:i];
		NSColor *fill = ORMPaperColor();
		if (!state.forPrinting && [state.selectedRoles containsObject:role.identifier]) {
			fill = [ORMSelectionColor() colorWithAlphaComponent:0.30];
		}
		for (NSUInteger s = 0; s < [state.pickedSequences count]; s++) {
			if ([[state.pickedSequences objectAtIndex:s] containsObject:role.identifier]) {
				fill = [ORMPickColor() colorWithAlphaComponent:0.45];
			}
		}
		[fill setFill];
		NSRectFill(box);
		ORMStroke([NSBezierPath bezierPathWithRect:box], ORMInkColor(), 0.75, NO);
		/* The picked role's place in its sequence, for the constraint
		 * being made. */
		for (NSUInteger s = 0; s < [state.pickedSequences count]; s++) {
			NSUInteger place = [[state.pickedSequences objectAtIndex:s] indexOfObject:role.identifier];
			if (place != NSNotFound) {
				NSString *label = [state.pickedSequences count] > 1
					? [NSString stringWithFormat:@"%lu.%lu", (unsigned long)s + 1, (unsigned long)place + 1]
					: [NSString stringWithFormat:@"%lu", (unsigned long)place + 1];
				NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:5.5],
				                              NSForegroundColorAttributeName: ORMInkColor() };
				ORMDrawCentered(label, box, attributes);
			}
		}
	}

	/* Internal uniqueness: one bar a level, the narrower nearer. */
	NSMutableArray *uniqueness = [NSMutableArray array];
	for (ORMConstraint *constraint in fact.internalConstraints) {
		if (constraint.kind == ORMUniquenessConstraint && !constraint.isImplied) {
			[uniqueness addObject:constraint];
		}
	}
	[uniqueness sortUsingComparator:^NSComparisonResult(ORMConstraint *a, ORMConstraint *b) {
		NSUInteger na = [[a allRoles] count];
		NSUInteger nb = [[b allRoles] count];
		return na < nb ? NSOrderedAscending : na > nb ? NSOrderedDescending : NSOrderedSame;
	}];
	NSUInteger level = 0;
	for (ORMConstraint *constraint in uniqueness) {
		BOOL selected = !state.forPrinting && [state.hoverElement isEqualToString:constraint.identifier];
		ORMDrawUniquenessBar(shape, constraint, level++, selected);
	}

	if (!state.forPrinting && [state.selectedShapes containsObject:shape.identifier]) {
		ORMDrawSelection(fact.objectifyingType != nil ? ORMObjectifiedOutline(shape) : NSInsetRect(ORMRoleStrip(shape), -3, -3),
		                 fact.objectifyingType != nil);
	}
}

static void
ORMDrawReading(ORMShape *shape, ORMDrawingState *state)
{
	ORMShape *factTypeShape = shape.parent;
	ORMReadingOrder *order = [shape.subject isKindOfClass:[ORMReadingOrder class]] ? shape.subject : nil;
	if (order == nil || factTypeShape == nil) {
		return;
	}
	NSString *text = ORMReadingDisplayText(factTypeShape, order);
	NSDictionary *attributes = ORMTextAttributes(shape.diagram, ORMInkColor(), NO);
	[text drawAtPoint:shape.bounds.origin withAttributes:attributes];
	if (!state.forPrinting && [state.selectedShapes containsObject:shape.identifier]) {
		NSSize size = [text sizeWithAttributes:attributes];
		ORMDrawSelection(NSMakeRect(NSMinX(shape.bounds), NSMinY(shape.bounds), size.width, size.height), NO);
	}
}

/* The roles of a constraint's sequence grouped by the fact type shape
 * that shows them, and the point a dashed line goes to for each group. */
static NSArray<NSValue *> *
ORMSequenceAttachments(ORMDiagram *diagram, NSArray<ORMRole *> *roles, NSPoint from)
{
	NSMutableArray *points = [NSMutableArray array];
	NSMutableArray *facts = [NSMutableArray array];
	for (ORMRole *role in roles) {
		if (role.factType != nil && [facts indexOfObjectIdenticalTo:role.factType] == NSNotFound) {
			[facts addObject:role.factType];
		}
	}
	for (ORMFactType *fact in facts) {
		ORMShape *shape = nil;
		double distance = DBL_MAX;
		for (ORMShape *candidate in [diagram shapesForSubject:fact.identifier]) {
			double d = hypot(NSMidX(candidate.bounds) - from.x, NSMidY(candidate.bounds) - from.y);
			if (candidate.kind == ORMShapeFactType && d < distance) {
				distance = d;
				shape = candidate;
			}
		}
		if (shape == nil) {
			continue;
		}
		NSRect span = NSZeroRect;
		for (ORMRole *role in roles) {
			if (role.factType == fact) {
				NSRect box = ORMRoleBox(shape, role);
				span = NSIsEmptyRect(span) ? box : NSUnionRect(span, box);
			}
		}
		if (NSIsEmptyRect(span)) {
			continue;
		}
		[points addObject:[NSValue valueWithPoint:ORMEdgePoint(span, from)]];
	}
	return points;
}

static NSString *
ORMRingAbbreviation(ORMRingType type)
{
	NSArray *parts = @[ @[ @(ORMRingIrreflexive), @"ir" ], @[ @(ORMRingAsymmetric), @"as" ],
	                    @[ @(ORMRingAntisymmetric), @"ans" ], @[ @(ORMRingIntransitive), @"it" ],
	                    @[ @(ORMRingStronglyIntransitive), @"sit" ], @[ @(ORMRingAcyclic), @"ac" ],
	                    @[ @(ORMRingSymmetric), @"sym" ], @[ @(ORMRingTransitive), @"tr" ],
	                    @[ @(ORMRingReflexive), @"rf" ], @[ @(ORMRingPurelyReflexive), @"prf" ] ];
	NSMutableArray *names = [NSMutableArray array];
	for (NSArray *part in parts) {
		if (type & [[part objectAtIndex:0] unsignedIntegerValue]) {
			[names addObject:[part objectAtIndex:1]];
		}
	}
	return [names componentsJoinedByString:@","];
}

static NSString *
ORMFrequencyText(ORMConstraint *constraint)
{
	if (constraint.maxFrequency == constraint.minFrequency) {
		return [NSString stringWithFormat:@"%lu", (unsigned long)constraint.minFrequency];
	}
	if (constraint.maxFrequency == 0) {
		return [NSString stringWithFormat:@"≥%lu", (unsigned long)constraint.minFrequency];
	}
	if (constraint.minFrequency <= 1) {
		return [NSString stringWithFormat:@"≤%lu", (unsigned long)constraint.maxFrequency];
	}
	return [NSString stringWithFormat:@"%lu..%lu", (unsigned long)constraint.minFrequency,
	        (unsigned long)constraint.maxFrequency];
}

static void
ORMDrawArrowhead(NSPoint tip, NSPoint from, NSColor *color, double size)
{
	double angle = atan2(tip.y - from.y, tip.x - from.x);
	NSBezierPath *head = [NSBezierPath bezierPath];
	[head moveToPoint:tip];
	[head lineToPoint:NSMakePoint(tip.x - size * cos(angle - 0.45), tip.y - size * sin(angle - 0.45))];
	[head lineToPoint:NSMakePoint(tip.x - size * cos(angle + 0.45), tip.y - size * sin(angle + 0.45))];
	[head closePath];
	[color setFill];
	[head fill];
}

static void
ORMDrawConstraintShape(ORMShape *shape, ORMDrawingState *state)
{
	ORMConstraint *constraint = shape.constraint;
	if (constraint == nil) {
		return;
	}
	ORMDiagram *diagram = shape.diagram;
	/* An exclusive-or's mandatory half is drawn with its exclusion. */
	if (constraint.kind == ORMMandatoryConstraint && constraint.exclusiveOrPartner != nil
	    && [diagram shapeForSubject:constraint.exclusiveOrPartner.identifier] != nil) {
		return;
	}
	BOOL selected = !state.forPrinting && [state.selectedShapes containsObject:shape.identifier];
	NSColor *color = selected ? ORMSelectionColor() : ORMConstraintColor(constraint.modality);
	NSRect rect = shape.bounds;
	NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));

	/* Dashed lines to the roles; a subset's to its superset sequence ends
	 * in an arrow. */
	for (NSUInteger s = 0; s < [constraint.roleSequences count]; s++) {
		ORMRoleSequence *sequence = [constraint.roleSequences objectAtIndex:s];
		for (NSValue *value in ORMSequenceAttachments(diagram, sequence.roles, center)) {
			NSPoint end = [value pointValue];
			NSPoint start = ORMEdgePoint(rect, end);
			ORMStroke(ORMLine(start, end), color, 0.75, YES);
			if (constraint.kind == ORMSubsetConstraint && s == 1) {
				ORMDrawArrowhead(end, start, color, 4.5);
			}
		}
	}

	NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 0.5, 0.5)];
	BOOL circled = constraint.kind != ORMFrequencyConstraint;
	if (circled) {
		[ORMPaperColor() setFill];
		[circle fill];
		ORMStroke(circle, color, 1.0, NO);
	}
	double inset = NSWidth(rect) * 0.28;
	NSRect inner = NSInsetRect(rect, inset, inset);
	NSDictionary *symbol = @{ NSFontAttributeName: [NSFont systemFontOfSize:MAX(NSHeight(rect) * 0.55, 5)],
	                          NSForegroundColorAttributeName: color };
	switch (constraint.kind) {
	case ORMUniquenessConstraint: {
		BOOL preferred = constraint.preferredIdentifierFor != nil;
		double y = NSMidY(rect);
		ORMStroke(ORMLine(NSMakePoint(NSMinX(inner) - 1, preferred ? y - 1.2 : y),
		                  NSMakePoint(NSMaxX(inner) + 1, preferred ? y - 1.2 : y)), color, 1.0, NO);
		if (preferred) {
			ORMStroke(ORMLine(NSMakePoint(NSMinX(inner) - 1, y + 1.2), NSMakePoint(NSMaxX(inner) + 1, y + 1.2)), color,
			          1.0, NO);
		}
		break;
	}
	case ORMMandatoryConstraint:
		ORMDrawDot(center, NSWidth(rect) * 0.16, color, constraint.modality == ORMAlethic);
		break;
	case ORMExclusionConstraint:
		ORMStroke(ORMLine(NSMakePoint(NSMinX(inner), NSMinY(inner)), NSMakePoint(NSMaxX(inner), NSMaxY(inner))), color,
		          1.0, NO);
		ORMStroke(ORMLine(NSMakePoint(NSMinX(inner), NSMaxY(inner)), NSMakePoint(NSMaxX(inner), NSMinY(inner))), color,
		          1.0, NO);
		if (constraint.exclusiveOrPartner != nil) {
			ORMDrawDot(center, NSWidth(rect) * 0.12, color, YES);
		}
		break;
	case ORMSubsetConstraint:
		ORMDrawCentered(@"⊆", rect, symbol);
		break;
	case ORMEqualityConstraint:
		ORMDrawCentered(@"=", rect, symbol);
		break;
	case ORMRingConstraint: {
		NSDictionary *small = @{ NSFontAttributeName: [NSFont systemFontOfSize:MAX(NSHeight(rect) * 0.32, 4)],
		                         NSForegroundColorAttributeName: color };
		ORMDrawCentered(ORMRingAbbreviation(constraint.ringType), rect, small);
		break;
	}
	case ORMFrequencyConstraint: {
		NSDictionary *text = ORMTextAttributes(diagram, color, NO);
		ORMDrawCentered(ORMFrequencyText(constraint), rect, text);
		break;
	}
	case ORMValueComparisonConstraint: {
		NSDictionary *operators = @{ @"Equal": @"=", @"NotEqual": @"≠", @"LessThan": @"<",
		                             @"LessThanOrEqual": @"≤", @"GreaterThan": @">",
		                             @"GreaterThanOrEqual": @"≥" };
		ORMDrawCentered([operators objectForKey:constraint.comparisonOperator] ?: @"?", rect, symbol);
		break;
	}
	}
	if (selected) {
		ORMDrawSelection(rect, NO);
	}
}

static void
ORMDrawSubtypeLinks(ORMDiagram *diagram)
{
	for (ORMShape *shape in diagram.shapes) {
		ORMObjectType *sub = shape.objectType;
		if (sub == nil) {
			continue;
		}
		for (ORMFactType *fact in sub.supertypeFacts) {
			ORMObjectType *sup = [[fact.roles lastObject] player];
			ORMShape *target = ORMShapeOfObjectType(diagram, sup, [shape center]);
			if (target == nil) {
				continue;
			}
			NSRect to = ORMObjectTypeRect(target);
			NSPoint end = ORMEdgePoint(to, [shape center]);
			NSPoint start = ORMEdgePoint(shape.bounds, NSMakePoint(NSMidX(to), NSMidY(to)));
			NSColor *color = ORMConstraintColor(ORMAlethic);
			ORMStroke(ORMLine(start, end), color, 1.6, !fact.providesPreferredIdentifier);
			ORMDrawArrowhead(end, start, color, 6.0);
		}
	}
}

static void
ORMDrawNote(ORMShape *shape, ORMDrawingState *state)
{
	ORMModelNote *note = [shape.subject isKindOfClass:[ORMModelNote class]] ? shape.subject : nil;
	if (note == nil) {
		return;
	}
	ORMDiagram *diagram = shape.diagram;
	NSRect rect = shape.bounds;
	for (ORMElement *element in note.referencedElements) {
		ORMShape *target = [diagram shapeForSubject:element.identifier];
		if (target != nil) {
			NSPoint end = ORMEdgePoint(target.bounds, [shape center]);
			ORMStroke(ORMLine(ORMEdgePoint(rect, end), end), ORMInkColor(), 0.6, YES);
		}
	}
	double fold = MIN(5.0, NSHeight(rect) / 2);
	NSBezierPath *path = [NSBezierPath bezierPath];
	[path moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
	[path lineToPoint:NSMakePoint(NSMaxX(rect) - fold, NSMinY(rect))];
	[path lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect) + fold)];
	[path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
	[path lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
	[path closePath];
	[[ORMPaperColor() blendedColorWithFraction:0.06 ofColor:ORMRGB(1.0, 0.85, 0.0)] setFill];
	[path fill];
	ORMStroke(path, ORMInkColor(), 0.6, NO);
	NSDictionary *attributes = ORMTextAttributes(diagram, ORMInkColor(), NO);
	[note.text drawInRect:NSInsetRect(rect, 2, 1) withAttributes:attributes];
	if (!state.forPrinting && [state.selectedShapes containsObject:shape.identifier]) {
		ORMDrawSelection(rect, NO);
	}
}

static void
ORMDrawTextShape(ORMShape *shape, NSString *text, ORMDrawingState *state)
{
	NSDictionary *attributes = ORMTextAttributes(shape.diagram, ORMConstraintColor(ORMAlethic), NO);
	[text drawAtPoint:shape.bounds.origin withAttributes:attributes];
	if (!state.forPrinting && [state.selectedShapes containsObject:shape.identifier]) {
		NSSize size = [text sizeWithAttributes:attributes];
		ORMDrawSelection(NSMakeRect(NSMinX(shape.bounds), NSMinY(shape.bounds), size.width, size.height), NO);
	}
}

static void
ORMDrawRelative(ORMShape *shape, ORMDrawingState *state)
{
	switch (shape.kind) {
	case ORMShapeReading:
		ORMDrawReading(shape, state);
		break;
	case ORMShapeValueConstraint: {
		ORMValueConstraint *constraint = [shape.subject isKindOfClass:[ORMValueConstraint class]] ? shape.subject : nil;
		if (constraint == nil) {
			constraint = shape.parent.objectType.valueConstraint;
		}
		if (constraint != nil) {
			ORMDrawTextShape(shape, [constraint displayText], state);
		}
		break;
	}
	case ORMShapeRoleName: {
		ORMRole *role = [shape.subject isKindOfClass:[ORMRole class]] ? shape.subject : nil;
		if ([role.name length] > 0) {
			ORMDrawTextShape(shape, [NSString stringWithFormat:@"[%@]", role.name], state);
		}
		break;
	}
	default:
		break;
	}
	for (ORMShape *child in shape.relativeShapes) {
		ORMDrawRelative(child, state);
	}
}

#pragma mark The diagram

void
ORMDrawDiagram(ORMDiagram *diagram, NSRect dirty, ORMDrawingState *state)
{
	(void)dirty;
	ORMDrawSubtypeLinks(diagram);
	/* Fact types (with their lines) under object types, constraints and
	 * notes over both. */
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeFactType) {
			ORMDrawFactType(shape, state);
		}
	}
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeObjectType) {
			ORMDrawObjectType(shape, state);
		}
	}
	for (ORMShape *shape in diagram.shapes) {
		switch (shape.kind) {
		case ORMShapeExternalConstraint:
		case ORMShapeFrequencyConstraint:
		case ORMShapeRingConstraint:
		case ORMShapeValueComparisonConstraint:
			ORMDrawConstraintShape(shape, state);
			break;
		case ORMShapeModelNote:
			ORMDrawNote(shape, state);
			break;
		default:
			break;
		}
	}
	for (ORMShape *shape in diagram.shapes) {
		for (ORMShape *child in shape.relativeShapes) {
			ORMDrawRelative(child, state);
		}
	}
	/* A value type's possible values, when the diagram has no shape of its
	 * own for them. */
	for (ORMShape *shape in diagram.shapes) {
		ORMObjectType *type = shape.objectType;
		if (type.valueConstraint == nil || type.kind != ORMValueType) {
			continue;
		}
		BOOL shown = NO;
		for (ORMShape *child in shape.relativeShapes) {
			shown = shown || child.kind == ORMShapeValueConstraint;
		}
		if (!shown) {
			NSDictionary *attributes = ORMTextAttributes(diagram, ORMConstraintColor(ORMAlethic), NO);
			NSString *text = [type.valueConstraint displayText];
			NSSize size = [text sizeWithAttributes:attributes];
			[text drawAtPoint:NSMakePoint(NSMaxX(shape.bounds) - size.width / 2, NSMinY(shape.bounds) - size.height)
			   withAttributes:attributes];
		}
	}
}

NSRect
ORMDrawingBounds(ORMDiagram *diagram)
{
	NSRect bounds = [diagram extent];
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeFactType && shape.factType.objectifyingType != nil) {
			bounds = NSUnionRect(bounds, NSInsetRect(ORMObjectifiedOutline(shape), 0, -14));
		}
		for (ORMShape *child in shape.relativeShapes) {
			if (child.kind == ORMShapeReading && [child.subject isKindOfClass:[ORMReadingOrder class]]) {
				NSSize size = ORMReadingSizeFor(ORMReadingDisplayText(shape, child.subject), diagram);
				bounds = NSUnionRect(bounds, NSMakeRect(NSMinX(child.bounds), NSMinY(child.bounds), size.width,
				                                        size.height));
			}
		}
	}
	return NSInsetRect(bounds, -12, -12);
}
