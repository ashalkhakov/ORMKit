/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMRenderer.h"

#pragma mark Colours and fonts

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

static NSColor *
ORMNSColor(ORMColor color)
{
	return [NSColor colorWithCalibratedRed:color.red green:color.green blue:color.blue alpha:color.alpha];
}

NSColor *
ORMInkColor(void)
{
	return ORMNSColor(ORMDiagramInk(ORMIsDark()));
}

NSColor *
ORMPaperColor(void)
{
	return ORMNSColor(ORMDiagramPaper(ORMIsDark()));
}

NSColor *
ORMObjectTypeColor(void)
{
	return ORMNSColor(ORMDiagramObjectType(ORMIsDark()));
}

NSColor *
ORMConstraintColor(ORMModality modality)
{
	return ORMNSColor(ORMDiagramConstraint(modality, ORMIsDark()));
}

NSColor *
ORMSelectionColor(void)
{
	return ORMNSColor(ORMDiagramSelection());
}

NSColor *
ORMPickColor(void)
{
	return ORMNSColor(ORMDiagramPick());
}

NSColor *
ORMErrorColor(void)
{
	return ORMNSColor(ORMDiagramError());
}

static NSFont *
ORMNSFont(ORMDrawingFont *spec)
{
	NSFont *font = nil;
	if ([spec.name length] > 0) {
		font = [NSFont fontWithName:spec.bold ? [spec.name stringByAppendingString:@" Bold"] : spec.name size:spec.size];
	}
	if (font == nil) {
		font = spec.bold ? [NSFont boldSystemFontOfSize:spec.size] : [NSFont systemFontOfSize:spec.size];
	}
	return font;
}

NSFont *
ORMDiagramFont(ORMDiagram *diagram, BOOL bold)
{
	return ORMNSFont([ORMDrawingFont fontOfDiagram:diagram bold:bold]);
}

#pragma mark The surface

@implementation ORMAppKitSurface

+ (instancetype)surface
{
	return [[self alloc] init];
}

static NSBezierPath *
ORMBezierPath(ORMDrawPath *path)
{
	if (path.isOval) {
		return [NSBezierPath bezierPathWithOvalInRect:path.rect];
	}
	if (path.radius > 0) {
		return [NSBezierPath bezierPathWithRoundedRect:path.rect xRadius:path.radius yRadius:path.radius];
	}
	NSBezierPath *bezier = [NSBezierPath bezierPath];
	for (NSArray *element in path.elements) {
		NSPoint point = [[element objectAtIndex:1] pointValue];
		switch ((ORMPathElement)[[element objectAtIndex:0] integerValue]) {
		case ORMPathMove:
			[bezier moveToPoint:point];
			break;
		case ORMPathLine:
			[bezier lineToPoint:point];
			break;
		case ORMPathClose:
			[bezier closePath];
			break;
		}
	}
	return bezier;
}

- (NSDictionary *)attributesFor:(ORMDrawingFont *)font color:(ORMColor)color
{
	return @{ NSFontAttributeName: ORMNSFont(font), NSForegroundColorAttributeName: ORMNSColor(color) };
}

- (NSSize)sizeOfText:(NSString *)text font:(ORMDrawingFont *)font
{
	return [text sizeWithAttributes:@{ NSFontAttributeName: ORMNSFont(font) }];
}

- (void)strokePath:(ORMDrawPath *)path color:(ORMColor)color width:(double)width dashed:(BOOL)dashed
{
	NSBezierPath *bezier = ORMBezierPath(path);
	[ORMNSColor(color) setStroke];
	[bezier setLineWidth:width];
	if (dashed) {
		CGFloat pattern[2] = { 2.0, 2.0 };
		[bezier setLineDash:pattern count:2 phase:0];
	}
	[bezier stroke];
}

- (void)fillPath:(ORMDrawPath *)path color:(ORMColor)color
{
	[ORMNSColor(color) setFill];
	[ORMBezierPath(path) fill];
}

- (void)drawText:(NSString *)text
              at:(NSPoint)point
            font:(ORMDrawingFont *)font
           color:(ORMColor)color
        centered:(BOOL)centered
{
	NSDictionary *attributes = [self attributesFor:font color:color];
	if (centered) {
		point.x -= [text sizeWithAttributes:attributes].width / 2;
	}
	[text drawAtPoint:point withAttributes:attributes];
}

- (void)drawText:(NSString *)text inRect:(NSRect)rect font:(ORMDrawingFont *)font color:(ORMColor)color
{
	[text drawInRect:rect withAttributes:[self attributesFor:font color:color]];
}

@end

#pragma mark The diagram

NSSize
ORMObjectTypeSizeFor(ORMObjectType *type, ORMDiagram *diagram)
{
	return ORMObjectTypeSizeOn([ORMAppKitSurface surface], type, diagram);
}

NSSize
ORMReadingSizeFor(NSString *text, ORMDiagram *diagram)
{
	return ORMReadingSizeOn([ORMAppKitSurface surface], text, diagram);
}

void
ORMDrawDiagram(ORMDiagram *diagram, NSRect dirty, ORMDrawingState *state)
{
	(void)dirty;
	ORMDrawingState *drawing = state ?: [[ORMDrawingState alloc] init];
	drawing.dark = ORMIsDark();
	ORMPaintDiagram(diagram, [ORMAppKitSurface surface], drawing);
}

NSRect
ORMDrawingBounds(ORMDiagram *diagram)
{
	return ORMPaintedBounds(diagram, [ORMAppKitSurface surface]);
}
