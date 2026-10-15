/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagramPainter.h"
#import "ORMReadingText.h"
#import "ORMPath.h"
#include <float.h>
#include <math.h>

/* A role box, in points: NORMA's 0.16 by 0.11 inches. */
static const double ORMBoxWidth = 0.16 * 72.0;
static const double ORMBoxHeight = 0.11 * 72.0;
/* How far an objectified fact type's outline stands off its boxes. */
static const double ORMObjectifiedPadding = 5.0;

#pragma mark Colours and fonts

ORMColor
ORMColorMake(double red, double green, double blue, double alpha)
{
	ORMColor color = { red, green, blue, alpha };
	return color;
}

ORMColor
ORMColorWithAlpha(ORMColor color, double alpha)
{
	color.alpha = alpha;
	return color;
}

NSString *
ORMColorHex(ORMColor color)
{
	int r = (int)lround(MIN(MAX(color.red, 0.0), 1.0) * 255);
	int g = (int)lround(MIN(MAX(color.green, 0.0), 1.0) * 255);
	int b = (int)lround(MIN(MAX(color.blue, 0.0), 1.0) * 255);
	return [NSString stringWithFormat:@"#%02x%02x%02x", r, g, b];
}

ORMColor
ORMDiagramInk(BOOL dark)
{
	return dark ? ORMColorMake(0.88, 0.88, 0.88, 1) : ORMColorMake(0, 0, 0, 1);
}

ORMColor
ORMDiagramPaper(BOOL dark)
{
	return dark ? ORMColorMake(0.12, 0.12, 0.13, 1) : ORMColorMake(1, 1, 1, 1);
}

ORMColor
ORMDiagramObjectType(BOOL dark)
{
	return dark ? ORMColorMake(0.55, 0.70, 1.0, 1) : ORMColorMake(0.0, 0.0, 0.55, 1);
}

ORMColor
ORMDiagramConstraint(ORMModality modality, BOOL dark)
{
	if (modality == ORMDeontic) {
		return dark ? ORMColorMake(0.40, 0.65, 1.0, 1) : ORMColorMake(0.0, 0.35, 0.85, 1);
	}
	return dark ? ORMColorMake(0.85, 0.55, 0.95, 1) : ORMColorMake(0.50, 0.0, 0.50, 1);
}

ORMColor
ORMDiagramSelection(void)
{
	return ORMColorMake(0.10, 0.45, 0.95, 1);
}

ORMColor
ORMDiagramPick(void)
{
	return ORMColorMake(0.95, 0.55, 0.10, 1);
}

ORMColor
ORMDiagramError(void)
{
	return ORMColorMake(0.85, 0.10, 0.10, 1);
}

@implementation ORMDrawingFont

+ (instancetype)fontNamed:(NSString *)name size:(double)size bold:(BOOL)bold
{
	ORMDrawingFont *font = [[self alloc] init];
	font.name = name;
	font.size = size;
	font.bold = bold;
	return font;
}

+ (instancetype)fontOfDiagram:(ORMDiagram *)diagram bold:(BOOL)bold
{
	double size = diagram.baseFontSize > 1 ? diagram.baseFontSize : 7.0;
	NSString *name = [diagram.baseFontName length] > 0 ? diagram.baseFontName : nil;
	return [self fontNamed:name size:size bold:bold];
}

@end

@implementation ORMDrawPath
{
	NSMutableArray *_elements;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_elements = [NSMutableArray array];
		_rect = NSZeroRect;
	}
	return self;
}

+ (instancetype)path
{
	return [[self alloc] init];
}

+ (instancetype)lineFrom:(NSPoint)from to:(NSPoint)to
{
	ORMDrawPath *path = [self path];
	[path moveTo:from];
	[path lineTo:to];
	return path;
}

- (void)outline:(NSRect)rect
{
	[self moveTo:NSMakePoint(NSMinX(rect), NSMinY(rect))];
	[self lineTo:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
	[self lineTo:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
	[self lineTo:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
	[self close];
}

+ (instancetype)rect:(NSRect)rect
{
	ORMDrawPath *path = [self path];
	path->_rect = rect;
	[path outline:rect];
	return path;
}

+ (instancetype)roundedRect:(NSRect)rect
{
	ORMDrawPath *path = [self rect:rect];
	path->_radius = MIN(MIN(NSHeight(rect), NSWidth(rect)) / 2.6, 9.0);
	return path;
}

+ (instancetype)oval:(NSRect)rect
{
	ORMDrawPath *path = [self rect:rect];
	path->_isOval = YES;
	return path;
}

- (void)moveTo:(NSPoint)point
{
	[_elements addObject:@[ @(ORMPathMove), [NSValue valueWithPoint:point] ]];
}

- (void)lineTo:(NSPoint)point
{
	[_elements addObject:@[ @(ORMPathLine), [NSValue valueWithPoint:point] ]];
}

- (void)close
{
	[_elements addObject:@[ @(ORMPathClose), [NSValue valueWithPoint:NSZeroPoint] ]];
}

- (NSArray<NSArray *> *)elements
{
	return [_elements copy];
}

@end

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
		NSRect box = NSZeroRect;
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

static NSString *ORMReadingPhrase(ORMShape *factTypeShape, ORMReadingOrder *order);

NSString *
ORMReadingDisplayText(ORMShape *factTypeShape, ORMReadingOrder *order)
{
	NSString *phrase = ORMReadingPhrase(factTypeShape, order);
	/* NORMA's marks after a derived fact type's reading: * derived, +
	 * partly; doubled, stored. */
	ORMDerivationRule *rule = order.factType.isDerived ? [order.factType derivationRule] : nil;
	if (rule == nil || [phrase length] == 0) {
		return phrase;
	}
	NSString *mark = rule.isPartial ? @"+" : @"*";
	return [NSString stringWithFormat:@"%@ %@%@", phrase, mark, rule.isStored ? mark : @""];
}

static NSString *
ORMReadingPhrase(ORMShape *factTypeShape, ORMReadingOrder *order)
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
			(void)index;
			return [NSString stringWithFormat:@"%@%@", pre ?: @"", post ?: @""];
		}];
		phrase = [phrase stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		return against ? [@"◀ " stringByAppendingString:phrase] : phrase;
	}
	NSString *phrase = [text expandWithNames:^NSString *(NSUInteger index, NSString *pre, NSString *post) {
		(void)index;
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
ORMObjectTypeSizeOn(id<ORMDrawingSurface> surface, ORMObjectType *type, ORMDiagram *diagram)
{
	ORMDrawingFont *font = [ORMDrawingFont fontOfDiagram:diagram bold:NO];
	NSSize name = [surface sizeOfText:ORMNameLine(type) font:font];
	NSString *mode = ORMReferenceModeLine(type);
	NSSize modeSize = mode != nil ? [surface sizeOfText:mode font:font] : NSZeroSize;
	double width = MAX(name.width, modeSize.width) + 12;
	double height = name.height + modeSize.height + 8;
	return NSMakeSize(ceil(MAX(width, 0.36 * 72)), ceil(MAX(height, mode != nil ? 0.359 * 72 : 0.2295 * 72)));
}

NSSize
ORMReadingSizeOn(id<ORMDrawingSurface> surface, NSString *text, ORMDiagram *diagram)
{
	NSSize size = [surface sizeOfText:text font:[ORMDrawingFont fontOfDiagram:diagram bold:NO]];
	return NSMakeSize(ceil(size.width + 2), ceil(size.height));
}

#pragma mark Drawing pieces

/* What every drawing function needs. */
typedef struct {
	__unsafe_unretained id<ORMDrawingSurface> surface;
	__unsafe_unretained ORMDrawingState *state;
	BOOL dark;
} ORMPainting;

static void
ORMStroke(ORMPainting *p, ORMDrawPath *path, ORMColor color, double width, BOOL dashed)
{
	[p->surface strokePath:path color:color width:width dashed:dashed];
}

static void
ORMDrawCentered(ORMPainting *p, NSString *text, NSRect rect, ORMDrawingFont *font, ORMColor color)
{
	NSSize size = [p->surface sizeOfText:text font:font];
	[p->surface drawText:text at:NSMakePoint(NSMidX(rect), NSMidY(rect) - size.height / 2) font:font color:color
	            centered:YES];
}

static void
ORMDrawSelection(ORMPainting *p, NSRect rect, BOOL rounded)
{
	NSRect outset = NSInsetRect(rect, -2.5, -2.5);
	ORMStroke(p, rounded ? [ORMDrawPath roundedRect:outset] : [ORMDrawPath rect:outset], ORMDiagramSelection(), 1.5, NO);
}

static void
ORMDrawObjectType(ORMPainting *p, ORMShape *shape)
{
	ORMObjectType *type = shape.objectType;
	if (type == nil) {
		return;
	}
	ORMDrawingState *state = p->state;
	NSRect rect = NSInsetRect(shape.bounds, 0.5, 0.5);
	ORMDrawPath *outline = [ORMDrawPath roundedRect:rect];
	[p->surface fillPath:outline color:ORMDiagramPaper(p->dark)];
	ORMStroke(p, outline, ORMDiagramObjectType(p->dark), 1.0, type.kind == ORMValueType);
	ORMDrawingFont *font = [ORMDrawingFont fontOfDiagram:shape.diagram bold:NO];
	ORMColor ink = ORMDiagramInk(p->dark);
	NSString *name = ORMNameLine(type);
	NSString *mode = ORMReferenceModeLine(type);
	if (mode == nil) {
		ORMDrawCentered(p, name, rect, font, ink);
	} else {
		NSSize nameSize = [p->surface sizeOfText:name font:font];
		NSSize modeSize = [p->surface sizeOfText:mode font:font];
		double top = NSMidY(rect) - (nameSize.height + modeSize.height) / 2;
		[p->surface drawText:name at:NSMakePoint(NSMidX(rect), top) font:font color:ink centered:YES];
		[p->surface drawText:mode at:NSMakePoint(NSMidX(rect), top + nameSize.height) font:font color:ink centered:YES];
	}
	if (!state.forPrinting && [state.selectedShapes containsObject:shape.identifier]) {
		ORMDrawSelection(p, shape.bounds, YES);
	}
	if (!state.forPrinting && [state.hoverElement isEqualToString:type.identifier]) {
		ORMStroke(p, [ORMDrawPath roundedRect:NSInsetRect(shape.bounds, -1.5, -1.5)],
		          ORMColorWithAlpha(ORMDiagramSelection(), 0.4), 1.0, NO);
	}
}

/* A uniqueness bar over the roles the constraint covers, at a level above
 * (or below) the boxes: solid over each covered box, dashed across boxes
 * it skips; doubled for a preferred identifier. */
static void
ORMDrawUniquenessBar(ORMPainting *p, ORMShape *shape, ORMConstraint *constraint, NSUInteger level, BOOL selected)
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
	ORMColor color = selected ? ORMDiagramSelection() : ORMDiagramConstraint(constraint.modality, p->dark);
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
		ORMStroke(p, [ORMDrawPath lineFrom:a to:b], color, 1.0, !isCovered);
		if (preferred && isCovered) {
			double shift = 1.6;
			NSPoint c = horizontal ? NSMakePoint(a.x, a.y + (shape.constraintsBelow ? shift : -shift))
			                       : NSMakePoint(a.x - shift, a.y);
			NSPoint d = horizontal ? NSMakePoint(b.x, b.y + (shape.constraintsBelow ? shift : -shift))
			                       : NSMakePoint(b.x - shift, b.y);
			ORMStroke(p, [ORMDrawPath lineFrom:c to:d], color, 1.0, NO);
		}
	}
}

static void
ORMDrawDot(ORMPainting *p, NSPoint at, double radius, ORMColor color, BOOL filled)
{
	ORMDrawPath *dot = [ORMDrawPath oval:NSMakeRect(at.x - radius, at.y - radius, radius * 2, radius * 2)];
	if (filled) {
		[p->surface fillPath:dot color:color];
	} else {
		[p->surface fillPath:dot color:ORMDiagramPaper(p->dark)];
		ORMStroke(p, dot, color, 1.0, NO);
	}
}

static void
ORMDrawFactType(ORMPainting *p, ORMShape *shape)
{
	ORMFactType *fact = shape.factType;
	if (fact == nil) {
		return;
	}
	ORMDrawingState *state = p->state;
	ORMDiagram *diagram = shape.diagram;
	NSArray *roles = ORMShownRoles(shape);
	NSArray *boxes = ORMRoleBoxes(shape);
	ORMColor ink = ORMDiagramInk(p->dark);
	ORMColor paper = ORMDiagramPaper(p->dark);

	/* The lines to the players first, under everything. */
	for (ORMRole *role in roles) {
		NSPoint atRole;
		NSPoint atPlayer;
		if (!ORMRoleLine(diagram, shape, role, &atRole, &atPlayer)) {
			continue;
		}
		ORMStroke(p, [ORMDrawPath lineFrom:atRole to:atPlayer], ink, 0.75, NO);
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
			ORMDrawDot(p, dot, 2.3, ORMDiagramConstraint(modality, p->dark), modality == ORMAlethic);
		}
	}

	if (fact.objectifyingType != nil) {
		NSRect outline = ORMObjectifiedOutline(shape);
		ORMDrawPath *path = [ORMDrawPath roundedRect:outline];
		[p->surface fillPath:path color:paper];
		ORMStroke(p, path, ORMDiagramObjectType(p->dark), 1.0, NO);
		ORMDrawingFont *font = [ORMDrawingFont fontOfDiagram:diagram bold:NO];
		NSString *name = [NSString stringWithFormat:@"\"%@\"", fact.objectifyingType.name];
		NSSize size = [p->surface sizeOfText:name font:font];
		BOOL hasLabelShape = NO;
		for (ORMShape *child in shape.relativeShapes) {
			if (child.kind == ORMShapeObjectifiedFactTypeName) {
				hasLabelShape = YES;
				[p->surface drawText:name at:child.bounds.origin font:font color:ink centered:NO];
			}
		}
		if (!hasLabelShape) {
			[p->surface drawText:name at:NSMakePoint(NSMidX(outline), NSMinY(outline) - size.height - 1) font:font
			               color:ink
			            centered:YES];
		}
	}

	for (NSUInteger i = 0; i < [boxes count]; i++) {
		NSRect box = [[boxes objectAtIndex:i] rectValue];
		ORMRole *role = [roles objectAtIndex:i];
		ORMColor fill = paper;
		if (!state.forPrinting && [state.selectedRoles containsObject:role.identifier]) {
			fill = ORMColorWithAlpha(ORMDiagramSelection(), 0.30);
		}
		for (NSUInteger s = 0; s < [state.pickedSequences count]; s++) {
			if ([[state.pickedSequences objectAtIndex:s] containsObject:role.identifier]) {
				fill = ORMColorWithAlpha(ORMDiagramPick(), 0.45);
			}
		}
		ORMDrawPath *boxPath = [ORMDrawPath rect:box];
		[p->surface fillPath:boxPath color:fill];
		ORMStroke(p, boxPath, ink, 0.75, NO);
		/* The picked role's place in its sequence, for the constraint
		 * being made. */
		for (NSUInteger s = 0; s < [state.pickedSequences count]; s++) {
			NSUInteger place = [[state.pickedSequences objectAtIndex:s] indexOfObject:role.identifier];
			if (place != NSNotFound) {
				NSString *label = [state.pickedSequences count] > 1
					? [NSString stringWithFormat:@"%lu.%lu", (unsigned long)s + 1, (unsigned long)place + 1]
					: [NSString stringWithFormat:@"%lu", (unsigned long)place + 1];
				ORMDrawCentered(p, label, box, [ORMDrawingFont fontNamed:nil size:5.5 bold:NO], ink);
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
		ORMDrawUniquenessBar(p, shape, constraint, level++, selected);
	}

	if (!state.forPrinting && [state.selectedShapes containsObject:shape.identifier]) {
		ORMDrawSelection(p, fact.objectifyingType != nil ? ORMObjectifiedOutline(shape)
		                                                  : NSInsetRect(ORMRoleStrip(shape), -3, -3),
		                 fact.objectifyingType != nil);
	}
}

static void
ORMDrawReading(ORMPainting *p, ORMShape *shape)
{
	ORMShape *factTypeShape = shape.parent;
	ORMReadingOrder *order = [shape.subject isKindOfClass:[ORMReadingOrder class]] ? shape.subject : nil;
	if (order == nil || factTypeShape == nil) {
		return;
	}
	NSString *text = ORMReadingDisplayText(factTypeShape, order);
	ORMDrawingFont *font = [ORMDrawingFont fontOfDiagram:shape.diagram bold:NO];
	[p->surface drawText:text at:shape.bounds.origin font:font color:ORMDiagramInk(p->dark) centered:NO];
	if (!p->state.forPrinting && [p->state.selectedShapes containsObject:shape.identifier]) {
		NSSize size = [p->surface sizeOfText:text font:font];
		ORMDrawSelection(p, NSMakeRect(NSMinX(shape.bounds), NSMinY(shape.bounds), size.width, size.height), NO);
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
ORMDrawArrowhead(ORMPainting *p, NSPoint tip, NSPoint from, ORMColor color, double size)
{
	double angle = atan2(tip.y - from.y, tip.x - from.x);
	ORMDrawPath *head = [ORMDrawPath path];
	[head moveTo:tip];
	[head lineTo:NSMakePoint(tip.x - size * cos(angle - 0.45), tip.y - size * sin(angle - 0.45))];
	[head lineTo:NSMakePoint(tip.x - size * cos(angle + 0.45), tip.y - size * sin(angle + 0.45))];
	[head close];
	[p->surface fillPath:head color:color];
}

static void
ORMDrawConstraintShape(ORMPainting *p, ORMShape *shape)
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
	BOOL selected = !p->state.forPrinting && [p->state.selectedShapes containsObject:shape.identifier];
	ORMColor color = selected ? ORMDiagramSelection() : ORMDiagramConstraint(constraint.modality, p->dark);
	NSRect rect = shape.bounds;
	NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));

	/* Dashed lines to the roles; a subset's to its superset sequence ends
	 * in an arrow. */
	for (NSUInteger s = 0; s < [constraint.roleSequences count]; s++) {
		ORMRoleSequence *sequence = [constraint.roleSequences objectAtIndex:s];
		for (NSValue *value in ORMSequenceAttachments(diagram, sequence.roles, center)) {
			NSPoint end = [value pointValue];
			NSPoint start = ORMEdgePoint(rect, end);
			ORMStroke(p, [ORMDrawPath lineFrom:start to:end], color, 0.75, YES);
			if (constraint.kind == ORMSubsetConstraint && s == 1) {
				ORMDrawArrowhead(p, end, start, color, 4.5);
			}
		}
	}

	ORMDrawPath *circle = [ORMDrawPath oval:NSInsetRect(rect, 0.5, 0.5)];
	if (constraint.kind != ORMFrequencyConstraint) {
		[p->surface fillPath:circle color:ORMDiagramPaper(p->dark)];
		ORMStroke(p, circle, color, 1.0, NO);
	}
	double inset = NSWidth(rect) * 0.28;
	NSRect inner = NSInsetRect(rect, inset, inset);
	ORMDrawingFont *symbol = [ORMDrawingFont fontNamed:nil size:MAX(NSHeight(rect) * 0.55, 5) bold:NO];
	switch (constraint.kind) {
	case ORMUniquenessConstraint: {
		BOOL preferred = constraint.preferredIdentifierFor != nil;
		double y = NSMidY(rect);
		ORMStroke(p, [ORMDrawPath lineFrom:NSMakePoint(NSMinX(inner) - 1, preferred ? y - 1.2 : y)
		                                to:NSMakePoint(NSMaxX(inner) + 1, preferred ? y - 1.2 : y)],
		          color, 1.0, NO);
		if (preferred) {
			ORMStroke(p, [ORMDrawPath lineFrom:NSMakePoint(NSMinX(inner) - 1, y + 1.2)
			                                to:NSMakePoint(NSMaxX(inner) + 1, y + 1.2)],
			          color, 1.0, NO);
		}
		break;
	}
	case ORMMandatoryConstraint:
		ORMDrawDot(p, center, NSWidth(rect) * 0.16, color, constraint.modality == ORMAlethic);
		break;
	case ORMExclusionConstraint:
		ORMStroke(p, [ORMDrawPath lineFrom:NSMakePoint(NSMinX(inner), NSMinY(inner))
		                                to:NSMakePoint(NSMaxX(inner), NSMaxY(inner))],
		          color, 1.0, NO);
		ORMStroke(p, [ORMDrawPath lineFrom:NSMakePoint(NSMinX(inner), NSMaxY(inner))
		                                to:NSMakePoint(NSMaxX(inner), NSMinY(inner))],
		          color, 1.0, NO);
		if (constraint.exclusiveOrPartner != nil) {
			ORMDrawDot(p, center, NSWidth(rect) * 0.12, color, YES);
		}
		break;
	case ORMSubsetConstraint:
		ORMDrawCentered(p, @"⊆", rect, symbol, color);
		break;
	case ORMEqualityConstraint:
		ORMDrawCentered(p, @"=", rect, symbol, color);
		break;
	case ORMRingConstraint:
		ORMDrawCentered(p, ORMRingAbbreviation(constraint.ringType), rect,
		                [ORMDrawingFont fontNamed:nil size:MAX(NSHeight(rect) * 0.32, 4) bold:NO], color);
		break;
	case ORMFrequencyConstraint:
		ORMDrawCentered(p, ORMFrequencyText(constraint), rect, [ORMDrawingFont fontOfDiagram:diagram bold:NO], color);
		break;
	case ORMValueComparisonConstraint: {
		NSDictionary *operators = @{ @"Equal": @"=", @"NotEqual": @"≠", @"LessThan": @"<",
		                             @"LessThanOrEqual": @"≤", @"GreaterThan": @">",
		                             @"GreaterThanOrEqual": @"≥" };
		ORMDrawCentered(p, [operators objectForKey:constraint.comparisonOperator] ?: @"?", rect, symbol, color);
		break;
	}
	}
	if (selected) {
		ORMDrawSelection(p, rect, NO);
	}
}

static void
ORMDrawSubtypeLinks(ORMPainting *p, ORMDiagram *diagram)
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
			ORMColor color = ORMDiagramConstraint(ORMAlethic, p->dark);
			ORMStroke(p, [ORMDrawPath lineFrom:start to:end], color, 1.6, !fact.providesPreferredIdentifier);
			ORMDrawArrowhead(p, end, start, color, 6.0);
		}
	}
}

static void
ORMDrawNote(ORMPainting *p, ORMShape *shape)
{
	ORMModelNote *note = [shape.subject isKindOfClass:[ORMModelNote class]] ? shape.subject : nil;
	if (note == nil) {
		return;
	}
	ORMDiagram *diagram = shape.diagram;
	ORMColor ink = ORMDiagramInk(p->dark);
	NSRect rect = shape.bounds;
	for (ORMElement *element in note.referencedElements) {
		ORMShape *target = [diagram shapeForSubject:element.identifier];
		if (target != nil) {
			NSPoint end = ORMEdgePoint(target.bounds, [shape center]);
			ORMStroke(p, [ORMDrawPath lineFrom:ORMEdgePoint(rect, end) to:end], ink, 0.6, YES);
		}
	}
	double fold = MIN(5.0, NSHeight(rect) / 2);
	ORMDrawPath *path = [ORMDrawPath path];
	[path moveTo:NSMakePoint(NSMinX(rect), NSMinY(rect))];
	[path lineTo:NSMakePoint(NSMaxX(rect) - fold, NSMinY(rect))];
	[path lineTo:NSMakePoint(NSMaxX(rect), NSMinY(rect) + fold)];
	[path lineTo:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
	[path lineTo:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
	[path close];
	/* The paper with a touch of yellow. */
	ORMColor paper = ORMDiagramPaper(p->dark);
	ORMColor fill = ORMColorMake(paper.red * 0.94 + 0.06, paper.green * 0.94 + 0.06 * 0.85, paper.blue * 0.94, 1);
	[p->surface fillPath:path color:fill];
	ORMStroke(p, path, ink, 0.6, NO);
	[p->surface drawText:note.text inRect:NSInsetRect(rect, 2, 1) font:[ORMDrawingFont fontOfDiagram:diagram bold:NO]
	               color:ink];
	if (!p->state.forPrinting && [p->state.selectedShapes containsObject:shape.identifier]) {
		ORMDrawSelection(p, rect, NO);
	}
}

static void
ORMDrawTextShape(ORMPainting *p, ORMShape *shape, NSString *text)
{
	ORMDrawingFont *font = [ORMDrawingFont fontOfDiagram:shape.diagram bold:NO];
	[p->surface drawText:text at:shape.bounds.origin font:font color:ORMDiagramConstraint(ORMAlethic, p->dark)
	            centered:NO];
	if (!p->state.forPrinting && [p->state.selectedShapes containsObject:shape.identifier]) {
		NSSize size = [p->surface sizeOfText:text font:font];
		ORMDrawSelection(p, NSMakeRect(NSMinX(shape.bounds), NSMinY(shape.bounds), size.width, size.height), NO);
	}
}

static void
ORMDrawRelative(ORMPainting *p, ORMShape *shape)
{
	switch (shape.kind) {
	case ORMShapeReading:
		ORMDrawReading(p, shape);
		break;
	case ORMShapeValueConstraint: {
		ORMValueConstraint *constraint = [shape.subject isKindOfClass:[ORMValueConstraint class]] ? shape.subject : nil;
		if (constraint == nil) {
			constraint = shape.parent.objectType.valueConstraint;
		}
		if (constraint != nil) {
			ORMDrawTextShape(p, shape, [constraint displayText]);
		}
		break;
	}
	case ORMShapeRoleName: {
		ORMRole *role = [shape.subject isKindOfClass:[ORMRole class]] ? shape.subject : nil;
		if ([role.name length] > 0) {
			ORMDrawTextShape(p, shape, [NSString stringWithFormat:@"[%@]", role.name]);
		}
		break;
	}
	default:
		break;
	}
	for (ORMShape *child in shape.relativeShapes) {
		ORMDrawRelative(p, child);
	}
}

#pragma mark The diagram

void
ORMPaintDiagram(ORMDiagram *diagram, id<ORMDrawingSurface> surface, ORMDrawingState *state)
{
	ORMDrawingState *drawing = state ?: [[ORMDrawingState alloc] init];
	ORMPainting painting = { surface, drawing, drawing.dark };
	ORMPainting *p = &painting;
	ORMDrawSubtypeLinks(p, diagram);
	/* Fact types (with their lines) under object types, constraints and
	 * notes over both. */
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeFactType) {
			ORMDrawFactType(p, shape);
		}
	}
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeObjectType) {
			ORMDrawObjectType(p, shape);
		}
	}
	for (ORMShape *shape in diagram.shapes) {
		switch (shape.kind) {
		case ORMShapeExternalConstraint:
		case ORMShapeFrequencyConstraint:
		case ORMShapeRingConstraint:
		case ORMShapeValueComparisonConstraint:
			ORMDrawConstraintShape(p, shape);
			break;
		case ORMShapeModelNote:
			ORMDrawNote(p, shape);
			break;
		default:
			break;
		}
	}
	for (ORMShape *shape in diagram.shapes) {
		for (ORMShape *child in shape.relativeShapes) {
			ORMDrawRelative(p, child);
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
			ORMDrawingFont *font = [ORMDrawingFont fontOfDiagram:diagram bold:NO];
			NSString *text = [type.valueConstraint displayText];
			NSSize size = [surface sizeOfText:text font:font];
			[surface drawText:text at:NSMakePoint(NSMaxX(shape.bounds), NSMinY(shape.bounds) - size.height) font:font
			            color:ORMDiagramConstraint(ORMAlethic, painting.dark)
			         centered:YES];
		}
	}
}

NSRect
ORMPaintedBounds(ORMDiagram *diagram, id<ORMDrawingSurface> surface)
{
	NSRect bounds = [diagram extent];
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeFactType && shape.factType.objectifyingType != nil) {
			bounds = NSUnionRect(bounds, NSInsetRect(ORMObjectifiedOutline(shape), 0, -14));
		}
		for (ORMShape *child in shape.relativeShapes) {
			if (child.kind == ORMShapeReading && [child.subject isKindOfClass:[ORMReadingOrder class]]) {
				NSSize size = ORMReadingSizeOn(surface, ORMReadingDisplayText(shape, child.subject), diagram);
				bounds = NSUnionRect(bounds, NSMakeRect(NSMinX(child.bounds), NSMinY(child.bounds), size.width,
				                                        size.height));
			}
		}
	}
	return NSInsetRect(bounds, -12, -12);
}
