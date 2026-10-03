/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSVGSurface.h"

/* "12.5", "3": a coordinate, short. */
static NSString *
ORMSVGNumber(double value)
{
	NSString *text = [NSString stringWithFormat:@"%.2f", value];
	while ([text hasSuffix:@"0"]) {
		text = [text substringToIndex:[text length] - 1];
	}
	if ([text hasSuffix:@"."]) {
		text = [text substringToIndex:[text length] - 1];
	}
	return [text isEqualToString:@"-0"] ? @"0" : text;
}

static NSString *
ORMSVGEscape(NSString *text)
{
	NSString *escaped = [text ?: @"" stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
	escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
	escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
	return [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

/* The SVG paint for a colour: its hex, and its opacity when not opaque. */
static NSString *
ORMSVGPaint(NSString *attribute, ORMColor color)
{
	if (color.alpha >= 0.999) {
		return [NSString stringWithFormat:@"%@=\"%@\"", attribute, ORMColorHex(color)];
	}
	return [NSString stringWithFormat:@"%@=\"%@\" %@-opacity=\"%@\"", attribute, ORMColorHex(color), attribute,
	                                  ORMSVGNumber(color.alpha)];
}

/* A sans serif's advance for the character, in ems: what a Tahoma-like
 * face gives, near enough to lay out labels. */
static double
ORMSVGAdvance(unichar c)
{
	if (c == ' ') {
		return 0.31;
	}
	if ([@"iljtfrI.,:;!|'()[]" rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound) {
		return 0.30;
	}
	if ([@"mwMW@%" rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound) {
		return 0.85;
	}
	if (c >= 'A' && c <= 'Z') {
		return 0.64;
	}
	return 0.54;
}

@implementation ORMSVGSurface
{
	NSMutableString *_body;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_body = [NSMutableString string];
	}
	return self;
}

- (NSString *)family:(ORMDrawingFont *)font
{
	NSString *fallback = @"Tahoma, Verdana, 'DejaVu Sans', 'Helvetica Neue', Arial, sans-serif";
	if ([font.name length] == 0) {
		return fallback;
	}
	return [NSString stringWithFormat:@"'%@', %@", font.name, fallback];
}

- (NSSize)sizeOfText:(NSString *)text font:(ORMDrawingFont *)font
{
	double width = 0;
	for (NSUInteger i = 0; i < [text length]; i++) {
		width += ORMSVGAdvance([text characterAtIndex:i]);
	}
	return NSMakeSize(width * font.size * (font.bold ? 1.08 : 1.0), font.size * 1.21);
}

- (NSString *)shapeOf:(ORMDrawPath *)path
{
	NSRect rect = path.rect;
	if (path.isOval) {
		return [NSString stringWithFormat:@"<ellipse cx=\"%@\" cy=\"%@\" rx=\"%@\" ry=\"%@\"", ORMSVGNumber(NSMidX(rect)),
		                                  ORMSVGNumber(NSMidY(rect)), ORMSVGNumber(NSWidth(rect) / 2),
		                                  ORMSVGNumber(NSHeight(rect) / 2)];
	}
	if (!NSIsEmptyRect(rect)) {
		NSMutableString *shape = [NSMutableString stringWithFormat:@"<rect x=\"%@\" y=\"%@\" width=\"%@\" height=\"%@\"",
		                                                           ORMSVGNumber(NSMinX(rect)), ORMSVGNumber(NSMinY(rect)),
		                                                           ORMSVGNumber(NSWidth(rect)),
		                                                           ORMSVGNumber(NSHeight(rect))];
		if (path.radius > 0) {
			[shape appendFormat:@" rx=\"%@\"", ORMSVGNumber(path.radius)];
		}
		return shape;
	}
	NSMutableString *data = [NSMutableString string];
	for (NSArray *element in path.elements) {
		NSPoint point = [[element objectAtIndex:1] pointValue];
		switch ((ORMPathElement)[[element objectAtIndex:0] integerValue]) {
		case ORMPathMove:
			[data appendFormat:@"%@M%@ %@", [data length] > 0 ? @" " : @"", ORMSVGNumber(point.x), ORMSVGNumber(point.y)];
			break;
		case ORMPathLine:
			[data appendFormat:@" L%@ %@", ORMSVGNumber(point.x), ORMSVGNumber(point.y)];
			break;
		case ORMPathClose:
			[data appendString:@" Z"];
			break;
		}
	}
	return [NSString stringWithFormat:@"<path d=\"%@\"", data];
}

- (void)strokePath:(ORMDrawPath *)path color:(ORMColor)color width:(double)width dashed:(BOOL)dashed
{
	[_body appendFormat:@"%@ fill=\"none\" %@ stroke-width=\"%@\"%@/>\n", [self shapeOf:path], ORMSVGPaint(@"stroke", color),
	                    ORMSVGNumber(width), dashed ? @" stroke-dasharray=\"2 2\"" : @""];
}

- (void)fillPath:(ORMDrawPath *)path color:(ORMColor)color
{
	[_body appendFormat:@"%@ %@/>\n", [self shapeOf:path], ORMSVGPaint(@"fill", color)];
}

- (void)line:(NSString *)text at:(NSPoint)point font:(ORMDrawingFont *)font color:(ORMColor)color centered:(BOOL)centered
{
	if ([text length] == 0) {
		return;
	}
	/* The baseline an em below the top, as the editor's fonts sit. */
	[_body appendFormat:@"<text x=\"%@\" y=\"%@\" font-family=\"%@\" font-size=\"%@\"%@%@ %@>%@</text>\n",
	                    ORMSVGNumber(point.x), ORMSVGNumber(point.y + font.size), ORMSVGEscape([self family:font]),
	                    ORMSVGNumber(font.size), font.bold ? @" font-weight=\"bold\"" : @"",
	                    centered ? @" text-anchor=\"middle\"" : @"", ORMSVGPaint(@"fill", color), ORMSVGEscape(text)];
}

- (void)drawText:(NSString *)text
              at:(NSPoint)point
            font:(ORMDrawingFont *)font
           color:(ORMColor)color
        centered:(BOOL)centered
{
	[self line:text at:point font:font color:color centered:centered];
}

- (void)drawText:(NSString *)text inRect:(NSRect)rect font:(ORMDrawingFont *)font color:(ORMColor)color
{
	/* Wrapped at words to the width, line by line. */
	double y = NSMinY(rect);
	double height = font.size * 1.21;
	for (NSString *paragraph in [text ?: @"" componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
		NSMutableString *line = [NSMutableString string];
		for (NSString *word in [paragraph componentsSeparatedByString:@" "]) {
			NSString *longer = [line length] > 0 ? [NSString stringWithFormat:@"%@ %@", line, word] : word;
			if ([line length] > 0 && [self sizeOfText:longer font:font].width > NSWidth(rect)) {
				[self line:line at:NSMakePoint(NSMinX(rect), y) font:font color:color centered:NO];
				y += height;
				[line setString:word];
			} else {
				[line setString:longer];
			}
		}
		[self line:line at:NSMakePoint(NSMinX(rect), y) font:font color:color centered:NO];
		y += height;
		if (y > NSMaxY(rect)) {
			break;
		}
	}
}

- (NSString *)documentWithBounds:(NSRect)bounds paper:(ORMColor)paper title:(NSString *)title
{
	NSMutableString *svg = [NSMutableString string];
	[svg appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
	[svg appendFormat:@"<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"%@pt\" height=\"%@pt\" "
	                  @"viewBox=\"%@ %@ %@ %@\">\n",
	                  ORMSVGNumber(NSWidth(bounds)), ORMSVGNumber(NSHeight(bounds)), ORMSVGNumber(NSMinX(bounds)),
	                  ORMSVGNumber(NSMinY(bounds)), ORMSVGNumber(NSWidth(bounds)), ORMSVGNumber(NSHeight(bounds))];
	if ([title length] > 0) {
		[svg appendFormat:@"<title>%@</title>\n", ORMSVGEscape(title)];
	}
	[svg appendFormat:@"<rect x=\"%@\" y=\"%@\" width=\"%@\" height=\"%@\" %@/>\n", ORMSVGNumber(NSMinX(bounds)),
	                  ORMSVGNumber(NSMinY(bounds)), ORMSVGNumber(NSWidth(bounds)), ORMSVGNumber(NSHeight(bounds)),
	                  ORMSVGPaint(@"fill", paper)];
	[svg appendString:_body];
	[svg appendString:@"</svg>\n"];
	return svg;
}

@end

NSString *
ORMSVGOfDiagram(ORMDiagram *diagram, BOOL dark)
{
	ORMSVGSurface *surface = [[ORMSVGSurface alloc] init];
	ORMDrawingState *state = [[ORMDrawingState alloc] init];
	state.forPrinting = YES;
	state.dark = dark;
	ORMPaintDiagram(diagram, surface, state);
	return [surface documentWithBounds:ORMPaintedBounds(diagram, surface) paper:ORMDiagramPaper(dark) title:diagram.name];
}
