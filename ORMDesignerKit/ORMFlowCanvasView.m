/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlowCanvasView.h"

static NSString * const ORMScreenItemPrefix = @"screen:";
static NSString * const ORMTransitionItemPrefix = @"transition:";
/* A card's title bar, its port's radius, a return's length. */
static const double ORMFlowTitleHeight = 26;
static const double ORMFlowPortRadius = 5;
static const double ORMFlowReturnLength = 46;

/* What an action is said as on its arrow. */
static NSString *
ORMFlowSaid(ORMFlowTransition *transition)
{
	NSDictionary *said = @{ ORMFlowOnSubmitDone : @"saved", ORMFlowOnSubmitError : @"refused", ORMFlowOnCancel : @"cancelled",
		                    ORMFlowOnRowChosen : @"row chosen", ORMFlowOnTrigger : @"pressed" };
	NSString *on = [said objectForKey:transition.on ?: @""] ?: transition.on ?: @"?";
	if (transition.control != nil) {
		on = [NSString stringWithFormat:@"%@ %@", transition.control, on];
	}
	if ([transition.kind isEqualToString:ORMFlowKindBack]) {
		return [on stringByAppendingString:@" → back"];
	}
	if ([transition.kind isEqualToString:ORMFlowKindClose]) {
		return [on stringByAppendingString:@" → close"];
	}
	if ([transition.kind isEqualToString:ORMFlowKindOverlay]) {
		return [on stringByAppendingString:@" (over it)"];
	}
	return on;
}

/* How far the point is from the segment. */
static double
ORMDistanceToSegment(NSPoint p, NSPoint a, NSPoint b)
{
	double dx = b.x - a.x, dy = b.y - a.y;
	double length = dx * dx + dy * dy;
	double t = length > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / length : 0;
	t = MAX(0, MIN(1, t));
	double x = a.x + t * dx - p.x, y = a.y + t * dy - p.y;
	return sqrt(x * x + y * y);
}

@implementation ORMFlowCanvasView {
	/* Where the last press was: a double-click's, on a title or below it. */
	NSPoint _pressedAt;
	/* A transition being drawn out of a port: from which screen, to where. */
	NSString *_drawingFrom;
	NSPoint _drawingTo;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		self.dataSource = self;
		self.delegate = self;
	}
	return self;
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	self.dataSource = self;
	self.delegate = self;
}

- (void)setEditor:(ORMFlowEditor *)editor
{
	_editor = editor;
	self.selection = [NSSet set];
	[self reloadData];
}

+ (NSString *)itemOfScreen:(NSString *)screenId
{
	return [ORMScreenItemPrefix stringByAppendingString:screenId ?: @""];
}

+ (NSString *)itemOfTransition:(NSUInteger)index
{
	return [NSString stringWithFormat:@"%@%lu", ORMTransitionItemPrefix, (unsigned long)index];
}

- (NSArray<NSString *> *)selectedScreens
{
	NSMutableArray *screens = [NSMutableArray array];
	for (NSString *item in self.selection) {
		if ([item hasPrefix:ORMScreenItemPrefix]) {
			[screens addObject:[item substringFromIndex:[ORMScreenItemPrefix length]]];
		}
	}
	[screens sortUsingSelector:@selector(compare:)];
	return screens;
}

- (NSIndexSet *)selectedTransitions
{
	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
	for (NSString *item in self.selection) {
		if ([item hasPrefix:ORMTransitionItemPrefix]) {
			[indexes addIndex:(NSUInteger)[[item substringFromIndex:[ORMTransitionItemPrefix length]] integerValue]];
		}
	}
	return indexes;
}

- (void)selectScreen:(NSString *)screenId
{
	self.selection = screenId != nil ? [NSSet setWithObject:[ORMFlowCanvasView itemOfScreen:screenId]] : [NSSet set];
	[self.flowDelegate flowCanvasSelectionDidChange:self];
}

- (void)selectTransition:(NSUInteger)index
{
	self.selection = [NSSet setWithObject:[ORMFlowCanvasView itemOfTransition:index]];
	[self.flowDelegate flowCanvasSelectionDidChange:self];
}

#pragma mark Geometry

- (NSRect)frameOfScreen:(ORMFlowScreen *)screen
{
	return NSMakeRect(screen.x, screen.y, MAX(screen.width, 120), MAX(screen.height, 80));
}

- (NSPoint)portOfScreen:(ORMFlowScreen *)screen
{
	NSRect frame = [self frameOfScreen:screen];
	return NSMakePoint(NSMaxX(frame), NSMinY(frame) + ORMFlowTitleHeight / 2);
}

/* The screen a transition goes to: its own; a return's, the one it comes
 * back to -- an overlay closed, the screen it was opened over; Back, the
 * one screen whose way leads to it (nil where several do: it goes back to
 * whichever it came from). */
- (ORMFlowScreen *)targetOfTransition:(ORMFlowTransition *)transition
{
	ORMFlow *flow = self.editor.flow;
	if (transition.toScreen != nil) {
		return [flow screenWithId:transition.toScreen];
	}
	ORMFlowScreen *from = [flow screenWithId:transition.fromScreen];
	if ([transition.kind isEqualToString:ORMFlowKindClose]) {
		return from != nil ? [flow openerOf:from] : nil;
	}
	NSString *before = nil;
	for (ORMFlowTransition *each in flow.transitions) {
		if ([each.toScreen isEqualToString:transition.fromScreen] && ![each.fromScreen isEqualToString:transition.fromScreen]) {
			if (before != nil && ![before isEqualToString:each.fromScreen]) {
				return nil;
			}
			before = each.fromScreen;
		}
	}
	return before != nil ? [flow screenWithId:before] : nil;
}

/* Whether two transitions go the same way: from one screen to the same
 * screen, or both returns there. */
- (BOOL)transition:(ORMFlowTransition *)a goesAs:(ORMFlowTransition *)b
{
	if (![a.fromScreen isEqualToString:b.fromScreen] || (a.toScreen == nil) != (b.toScreen == nil)) {
		return NO;
	}
	ORMFlowScreen *one = [self targetOfTransition:a], *other = [self targetOfTransition:b];
	return one == other || [one.identifier isEqualToString:other.identifier];
}

/* Which of the transitions going the same way it is: they are drawn apart,
 * and said once, on the first. */
- (NSUInteger)laneOfTransition:(NSUInteger)index
{
	NSArray<ORMFlowTransition *> *transitions = self.editor.flow.transitions;
	ORMFlowTransition *transition = [transitions objectAtIndex:index];
	NSUInteger lane = 0;
	for (NSUInteger i = 0; i < index; i++) {
		if ([self transition:[transitions objectAtIndex:i] goesAs:transition]) {
			lane++;
		}
	}
	return lane;
}

- (NSArray<NSValue *> *)routeOfTransition:(NSUInteger)index
{
	NSArray<ORMFlowTransition *> *transitions = self.editor.flow.transitions;
	if (index >= [transitions count]) {
		return @[];
	}
	ORMFlowTransition *transition = [transitions objectAtIndex:index];
	ORMFlowScreen *from = [self.editor.flow screenWithId:transition.fromScreen];
	ORMFlowScreen *to = [self targetOfTransition:transition];
	if (from == nil) {
		return @[];
	}
	double lane = [self laneOfTransition:index] * 22.0;
	NSRect source = [self frameOfScreen:from];
	if (to == nil) {
		/* A return to whichever screen it came from: down out of it. */
		NSPoint start = NSMakePoint(NSMidX(source) + lane, NSMaxY(source));
		return @[ [NSValue valueWithPoint:start], [NSValue valueWithPoint:NSMakePoint(start.x, start.y + ORMFlowReturnLength)] ];
	}
	NSRect target = [self frameOfScreen:to];
	NSPoint start = [self portOfScreen:from];
	start.y += lane;
	if (NSMinX(target) > start.x + 20) {
		NSPoint end = NSMakePoint(NSMinX(target), NSMinY(target) + ORMFlowTitleHeight / 2 + lane);
		double middle = round((start.x + end.x) / 2);
		return @[ [NSValue valueWithPoint:start], [NSValue valueWithPoint:NSMakePoint(middle, start.y)],
			      [NSValue valueWithPoint:NSMakePoint(middle, end.y)], [NSValue valueWithPoint:end] ];
	}
	/* Back to the left: round under both screens, into the next's bottom. */
	double below = MAX(NSMaxY(source), NSMaxY(target)) + 30 + lane;
	NSPoint end = NSMakePoint(NSMidX(target) - lane, NSMaxY(target));
	return @[ [NSValue valueWithPoint:start], [NSValue valueWithPoint:NSMakePoint(start.x + 20, start.y)],
		      [NSValue valueWithPoint:NSMakePoint(start.x + 20, below)], [NSValue valueWithPoint:NSMakePoint(end.x, below)],
		      [NSValue valueWithPoint:end] ];
}

/* Where a transition's words go: at its route's middle segment. */
- (NSPoint)labelOfTransition:(NSUInteger)index
{
	NSArray<NSValue *> *route = [self routeOfTransition:index];
	if ([route count] < 2) {
		return NSZeroPoint;
	}
	NSUInteger middle = ([route count] - 1) / 2;
	NSPoint a = [[route objectAtIndex:middle] pointValue], b = [[route objectAtIndex:middle + 1] pointValue];
	return NSMakePoint((a.x + b.x) / 2, (a.y + b.y) / 2);
}

/* What a transition's arrow says: the actions of all going the same way
 * on the first ("saved, cancelled → back"), nothing on the others; and
 * what each gives, named as its screen names it. */
- (NSString *)textOfTransition:(NSUInteger)index
{
	NSArray<ORMFlowTransition *> *transitions = self.editor.flow.transitions;
	ORMFlowTransition *transition = [transitions objectAtIndex:index];
	if ([self laneOfTransition:index] > 0) {
		return @"";
	}
	NSMutableArray *actions = [NSMutableArray array];
	NSMutableArray *gives = [NSMutableArray array];
	for (ORMFlowTransition *each in transitions) {
		if (each != transition && ![self transition:each goesAs:transition]) {
			continue;
		}
		NSString *said = ORMFlowSaid(each);
		NSRange arrow = [said rangeOfString:@" → "];
		[actions addObject:arrow.location != NSNotFound ? [said substringToIndex:arrow.location] : said];
		/* A return gives to the screen it comes back to. */
		ORMFlowScreen *to = [self targetOfTransition:each];
		for (ORMFlowGive *give in each.gives) {
			[gives addObject:[NSString stringWithFormat:@"%@ = %@", [self.editor nameOfNode:give.nodeId inScreen:to], give.from ?: @"?"]];
		}
	}
	NSString *said = ORMFlowSaid(transition);
	NSRange arrow = [said rangeOfString:@" → "];
	NSString *tail = arrow.location != NSNotFound ? [said substringFromIndex:arrow.location] : @"";
	NSString *line = [[actions componentsJoinedByString:@", "] stringByAppendingString:tail];
	if ([transition.kind isEqualToString:ORMFlowKindOverlay] && arrow.location == NSNotFound) {
		line = [[actions componentsJoinedByString:@", "] stringByAppendingString:@" (over it)"];
		line = [line stringByReplacingOccurrencesOfString:@" (over it) (over it)" withString:@" (over it)"];
	}
	return [gives count] > 0 ? [NSString stringWithFormat:@"%@\n%@", line, [gives componentsJoinedByString:@", "]] : line;
}

#pragma mark DKCanvasDataSource

- (NSRect)diagramBoundsForCanvas:(DKCanvasView *)canvas
{
	NSRect bounds = NSMakeRect(0, 0, 400, 300);
	for (ORMFlowScreen *screen in self.editor.flow.screens) {
		bounds = NSUnionRect(bounds, NSInsetRect([self frameOfScreen:screen], -40, -40));
	}
	for (NSUInteger i = 0; i < [self.editor.flow.transitions count]; i++) {
		for (NSValue *point in [self routeOfTransition:i]) {
			NSPoint p = [point pointValue];
			bounds = NSUnionRect(bounds, NSMakeRect(p.x - 80, p.y - 20, 160, 60));
		}
	}
	return bounds;
}

- (id)canvas:(DKCanvasView *)canvas itemAtPoint:(NSPoint)point
{
	for (NSUInteger i = [self.editor.flow.transitions count]; i > 0; i--) {
		NSArray<NSValue *> *route = [self routeOfTransition:i - 1];
		for (NSUInteger j = 0; j + 1 < [route count]; j++) {
			if (ORMDistanceToSegment(point, [[route objectAtIndex:j] pointValue], [[route objectAtIndex:j + 1] pointValue]) < 5) {
				return [ORMFlowCanvasView itemOfTransition:i - 1];
			}
		}
	}
	for (ORMFlowScreen *screen in [self.editor.flow.screens reverseObjectEnumerator]) {
		if (NSPointInRect(point, NSInsetRect([self frameOfScreen:screen], -ORMFlowPortRadius, 0))) {
			return [ORMFlowCanvasView itemOfScreen:screen.identifier];
		}
	}
	return nil;
}

- (NSArray *)canvas:(DKCanvasView *)canvas itemsInRect:(NSRect)rect
{
	NSMutableArray *items = [NSMutableArray array];
	for (ORMFlowScreen *screen in self.editor.flow.screens) {
		if (NSIntersectsRect(rect, [self frameOfScreen:screen])) {
			[items addObject:[ORMFlowCanvasView itemOfScreen:screen.identifier]];
		}
	}
	return items;
}

- (NSRect)canvas:(DKCanvasView *)canvas frameOfItem:(id)item
{
	if ([item hasPrefix:ORMScreenItemPrefix]) {
		ORMFlowScreen *screen = [self.editor.flow screenWithId:[item substringFromIndex:[ORMScreenItemPrefix length]]];
		return screen != nil ? [self frameOfScreen:screen] : NSZeroRect;
	}
	NSRect frame = NSZeroRect;
	for (NSValue *point in [self routeOfTransition:(NSUInteger)[[item substringFromIndex:[ORMTransitionItemPrefix length]] integerValue]]) {
		NSRect at = NSMakeRect([point pointValue].x, [point pointValue].y, 1, 1);
		frame = NSIsEmptyRect(frame) ? at : NSUnionRect(frame, at);
	}
	return frame;
}

- (BOOL)canvas:(DKCanvasView *)canvas canMoveItem:(id)item
{
	return [item hasPrefix:ORMScreenItemPrefix];
}

- (void)canvas:(DKCanvasView *)canvas drawInRect:(NSRect)rect surface:(id<DKSurface>)surface state:(DKDrawingState *)state
{
	[surface fillPath:[DKPath pathWithRect:rect] color:ORMDiagramPaper(state.dark)];
	DKColor ink = ORMDiagramInk(state.dark);
	DKFont *label = [DKFont systemFontOfSize:10 bold:NO];
	for (NSUInteger i = 0; i < [self.editor.flow.transitions count]; i++) {
		NSString *item = [ORMFlowCanvasView itemOfTransition:i];
		BOOL selected = [state.selection containsObject:item];
		DKColor color = selected ? DKColorSelection() : ink;
		ORMFlowTransition *transition = [self.editor.flow.transitions objectAtIndex:i];
		/* Over it: dashed; a return: dotted. */
		BOOL back = [transition.kind isEqualToString:ORMFlowKindBack] || [transition.kind isEqualToString:ORMFlowKindClose];
		DKStrokeStyle style = [transition.kind isEqualToString:ORMFlowKindOverlay] ? DKStrokeDashed : back ? DKStrokeDotted : DKStrokeSolid;
		DKDrawRoute(surface, [self routeOfTransition:i], color, selected ? 2 : 1.2, style, DKEdgeEndNone, DKEdgeEndArrow);
		NSPoint at = [self labelOfTransition:i];
		NSString *text = [self textOfTransition:i];
		if ([text length] == 0) {
			continue;
		}
		NSSize size = [surface sizeOfText:text font:label wrappedToWidth:170];
		NSRect box = NSMakeRect(at.x - size.width / 2 - 3, at.y - size.height - 4, size.width + 6, size.height + 2);
		[surface fillPath:[DKPath pathWithRoundedRect:box radius:3] color:DKColorWithAlpha(ORMDiagramPaper(state.dark), 0.9)];
		[surface drawText:text inRect:NSInsetRect(box, 3, 1) font:label color:color];
	}
	DKFont *title = [DKFont systemFontOfSize:12 bold:YES], *small = [DKFont systemFontOfSize:9 bold:NO];
	DKFont *body = [DKFont fontWithName:@"Menlo" size:9.5 bold:NO];
	for (ORMFlowScreen *screen in self.editor.flow.screens) {
		NSRect frame = [self frameOfScreen:screen];
		if (!NSIntersectsRect(rect, NSInsetRect(frame, -60, -20))) {
			continue;
		}
		BOOL selected = [state.selection containsObject:[ORMFlowCanvasView itemOfScreen:screen.identifier]];
		ORMQuery *query = [self.editor queryOfScreen:screen];
		BOOL missing = (screen.formId != nil || screen.queryId != nil) && query == nil;
		DKColor edge = selected ? DKColorSelection() : missing ? ORMDiagramError() : ink;
		DKPath *card = [DKPath pathWithRoundedRect:frame radius:8];
		[surface fillPath:card color:ORMDiagramPaper(state.dark)];
		NSRect bar = NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), ORMFlowTitleHeight);
		DKColor barColor = screen.formId != nil ? DKColorWithAlpha(ORMDiagramObjectType(state.dark), 0.18)
			: DKColorWithAlpha(ink, 0.08);
		[surface fillPath:[DKPath pathWithRoundedRect:bar radius:8] color:barColor];
		[surface strokePath:card color:edge width:selected ? 2 : 1 style:DKStrokeSolid];
		[surface drawText:screen.name ?: screen.identifier at:NSMakePoint(NSMinX(frame) + 8, NSMinY(frame) + 6) font:title color:ink
		         centered:NO];
		NSString *kind = screen.formId != nil ? @"form" : screen.queryId != nil ? @"list" : @"placeholder";
		NSSize kindSize = [surface sizeOfText:kind font:small];
		[surface drawText:kind at:NSMakePoint(NSMaxX(frame) - kindSize.width - 12, NSMinY(frame) + 8) font:small color:ink centered:NO];
		NSString *outline = missing ? @"No longer in the model." : query != nil ? [query outlineText] : @"Not a form yet.";
		if ([outline hasPrefix:@"Form "]) {
			NSRange line = [outline rangeOfString:@"\n"];
			outline = line.location != NSNotFound ? [outline substringFromIndex:NSMaxRange(line)] : outline;
		}
		[surface drawText:outline inRect:NSMakeRect(NSMinX(frame) + 8, NSMinY(frame) + ORMFlowTitleHeight + 6, NSWidth(frame) - 16,
		                                            NSHeight(frame) - ORMFlowTitleHeight - 12)
		             font:body color:missing ? ORMDiagramError() : ink];
		/* Its port, out of which a transition is drawn. */
		NSPoint port = [self portOfScreen:screen];
		NSRect dot = NSMakeRect(port.x - ORMFlowPortRadius, port.y - ORMFlowPortRadius, 2 * ORMFlowPortRadius, 2 * ORMFlowPortRadius);
		[surface fillPath:[DKPath pathWithOvalInRect:dot] color:ORMDiagramPaper(state.dark)];
		[surface strokePath:[DKPath pathWithOvalInRect:dot] color:ink width:1 style:DKStrokeSolid];
		/* Its entries: a tab on its left. */
		double y = NSMinY(frame) + 4;
		for (ORMFlowEntry *entry in self.editor.flow.entries) {
			if (![entry.screen isEqualToString:screen.identifier]) {
				continue;
			}
			NSString *text = [@"▶ " stringByAppendingString:entry.name ?: @"?"];
			NSSize size = [surface sizeOfText:text font:small];
			NSRect tab = NSMakeRect(NSMinX(frame) - size.width - 14, y, size.width + 10, size.height + 6);
			[surface fillPath:[DKPath pathWithRoundedRect:tab radius:4] color:ORMDiagramPick()];
			[surface drawText:text at:NSMakePoint(NSMinX(tab) + 5, NSMinY(tab) + 3) font:small color:DKColorWhite() centered:NO];
			y = NSMaxY(tab) + 4;
		}
	}
	if (_drawingFrom != nil) {
		ORMFlowScreen *from = [self.editor.flow screenWithId:_drawingFrom];
		[surface strokePath:[DKPath pathWithLineFrom:[self portOfScreen:from] to:_drawingTo] color:DKColorSelection() width:1.5
		              style:DKStrokeDashed];
	}
}

#pragma mark DKCanvasDelegate

- (void)canvas:(DKCanvasView *)canvas moveItems:(NSArray *)items by:(NSSize)delta
{
	NSMutableArray *screens = [NSMutableArray array];
	for (NSString *item in items) {
		if ([item hasPrefix:ORMScreenItemPrefix]) {
			[screens addObject:[item substringFromIndex:[ORMScreenItemPrefix length]]];
		}
	}
	[self.editor moveScreens:screens by:delta];
}

- (void)canvasSelectionDidChange:(DKCanvasView *)canvas
{
	[self.flowDelegate flowCanvasSelectionDidChange:self];
}

/* The screen whose port is at the point. */
- (ORMFlowScreen *)screenWithPortAt:(NSPoint)point
{
	for (ORMFlowScreen *screen in self.editor.flow.screens) {
		NSPoint port = [self portOfScreen:screen];
		if (hypot(point.x - port.x, point.y - port.y) <= ORMFlowPortRadius + 3) {
			return screen;
		}
	}
	return nil;
}

- (BOOL)canvas:(DKCanvasView *)canvas mouseDown:(NSEvent *)event atPoint:(NSPoint)point
{
	_pressedAt = point;
	ORMFlowScreen *from = [self screenWithPortAt:point];
	if (from == nil) {
		return NO;
	}
	_drawingFrom = [from.identifier copy];
	_drawingTo = point;
	[self setNeedsDisplay:YES];
	return YES;
}

- (void)canvas:(DKCanvasView *)canvas mouseDragged:(NSEvent *)event atPoint:(NSPoint)point
{
	_drawingTo = point;
	[self setNeedsDisplay:YES];
}

- (void)canvas:(DKCanvasView *)canvas mouseUp:(NSEvent *)event atPoint:(NSPoint)point
{
	NSString *from = _drawingFrom;
	_drawingFrom = nil;
	NSString *item = [self canvas:self itemAtPoint:point];
	if (from != nil && [item hasPrefix:ORMScreenItemPrefix]) {
		NSString *to = [item substringFromIndex:[ORMScreenItemPrefix length]];
		if ([self.editor addTransitionFrom:from to:to] != nil) {
			[self selectTransition:[self.editor.flow.transitions count] - 1];
		}
	}
	[self setNeedsDisplay:YES];
}

- (void)canvas:(DKCanvasView *)canvas doubleClickedItem:(id)item
{
	if (![item hasPrefix:ORMScreenItemPrefix]) {
		return;
	}
	ORMFlowScreen *screen = [self.editor.flow screenWithId:[item substringFromIndex:[ORMScreenItemPrefix length]]];
	NSRect frame = [self frameOfScreen:screen];
	/* Below its title: its form or list, where the model has it. */
	id<ORMFlowCanvasDelegate> delegate = self.flowDelegate;
	if (_pressedAt.y > NSMinY(frame) + ORMFlowTitleHeight && [delegate respondsToSelector:@selector(flowCanvas:openScreen:)]) {
		[delegate flowCanvas:self openScreen:screen.identifier];
		return;
	}
	[self editTextOfItem:item text:screen.name ?: @"" inRect:NSMakeRect(NSMinX(frame) + 4, NSMinY(frame) + 3, NSWidth(frame) - 60, 20)
	                font:[DKFont systemFontOfSize:12 bold:YES]];
}

- (void)canvas:(DKCanvasView *)canvas didEditTextOfItem:(id)item text:(NSString *)text
{
	[self.editor renameScreen:[item substringFromIndex:[ORMScreenItemPrefix length]] to:text];
}

- (IBAction)delete:(id)sender
{
	NSArray *screens = [self selectedScreens];
	NSIndexSet *transitions = [self selectedTransitions];
	if ([transitions count] > 0) {
		[self.editor removeTransitions:transitions];
	}
	if ([screens count] > 0) {
		[self.editor removeScreens:screens];
	}
	self.selection = [NSSet set];
	[self.flowDelegate flowCanvasSelectionDidChange:self];
}

@end
