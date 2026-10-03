#import "NUDiagramView.h"
#import <math.h>

@interface NUDiagramView ()
@property (assign) NSPoint dragStart;
@property (assign) NSPoint dragOrigin;
@property (assign) BOOL dragging;
@property (assign) BOOL draggingFact;
@property (strong) NSMutableArray *linkStack;
@property (strong) NSMutableArray *pendingRefs;
@property (assign) BOOL draggingConstraint;
@property (assign) NSPoint hoverPoint;
@end

@implementation NUDiagramView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _tool = NUToolSelect;
        _selectedRoleIndex = -1;
        _linkStack = [NSMutableArray array];
        _pendingRefs = [NSMutableArray array];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)setDiagram:(NUDiagram *)diagram {
    _diagram = diagram;
    self.selectedObject = nil;
    self.selectedFact = nil;
    self.selectedSubtype = nil;
    self.selectedConstraint = nil;
    self.selectedRoleIndex = -1;
    [self.linkStack removeAllObjects];
    [self.pendingRefs removeAllObjects];
    [self recomputeSize];
    [self setNeedsDisplay:YES];
}

- (void)clearLinkStack {
    [self.linkStack removeAllObjects];
    [self.pendingRefs removeAllObjects];
    [self setNeedsDisplay:YES];
}

- (void)recomputeSize {
    CGFloat maxX = 900, maxY = 640;
    for (NUObjectType *o in self.diagram.objectTypes) {
        NSRect f = [o frame];
        if (NSMaxX(f) + 80 > maxX) maxX = NSMaxX(f) + 80;
        if (NSMaxY(f) + 80 > maxY) maxY = NSMaxY(f) + 80;
    }
    for (NUFactType *ft in self.diagram.factTypes) {
        NSRect f = [ft frame];
        if (NSMaxX(f) + 80 > maxX) maxX = NSMaxX(f) + 80;
        if (NSMaxY(f) + 80 > maxY) maxY = NSMaxY(f) + 80;
    }
    [self setFrameSize:NSMakeSize(maxX, maxY)];
}

- (void)fitObjectType:(NUObjectType *)ot {
    NSDictionary *attrs = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:12] };
    NSString *label = [ot displayName];
    NSSize s = [label sizeWithAttributes:attrs];
    if (ot.valueConstraint.length) {
        NSSize vs = [ot.valueConstraint sizeWithAttributes:
                     @{ NSFontAttributeName: [NSFont systemFontOfSize:10] }];
        if (vs.width > s.width) s.width = vs.width;
        s.height += 12;
    }
    ot.size = NSMakeSize(MAX(s.width + 28, 110), MAX(s.height + 22, 48));
}

- (void)drawBackground:(NSRect)dirty {
    [[NSColor colorWithCalibratedRed:0.97 green:0.97 blue:0.96 alpha:1] set];
    NSRectFill(dirty);
    [[NSColor colorWithCalibratedRed:0.90 green:0.91 blue:0.89 alpha:1] set];
    NSBezierPath *grid = [NSBezierPath bezierPath];
    [grid setLineWidth:1];
    for (CGFloat x = 0; x < NSMaxX(self.bounds); x += 24) {
        [grid moveToPoint:NSMakePoint(x, 0)];
        [grid lineToPoint:NSMakePoint(x, NSMaxY(self.bounds))];
    }
    for (CGFloat y = 0; y < NSMaxY(self.bounds); y += 24) {
        [grid moveToPoint:NSMakePoint(0, y)];
        [grid lineToPoint:NSMakePoint(NSMaxX(self.bounds), y)];
    }
    [grid stroke];
}

- (NSPoint)ellipseAnchor:(NSRect)box toward:(NSPoint)other {
    NSPoint c = NSMakePoint(NSMidX(box), NSMidY(box));
    CGFloat dx = other.x - c.x, dy = other.y - c.y;
    if (dx == 0 && dy == 0) return c;
    CGFloat a = box.size.width * 0.5, b = box.size.height * 0.5;
    CGFloat len = hypot(dx, dy);
    CGFloat ux = dx / len, uy = dy / len;
    CGFloat denom = sqrt((ux * ux) / (a * a) + (uy * uy) / (b * b));
    if (denom < 1e-6) return c;
    CGFloat t = 1.0 / denom;
    return NSMakePoint(c.x + ux * t, c.y + uy * t);
}

- (void)drawObjectType:(NUObjectType *)ot {
    NSRect f = [ot frame];
    BOOL sel = (ot == self.selectedObject);
    NSBezierPath *ell = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(f, 0.5, 0.5)];
    if (sel)
        [[NSColor colorWithCalibratedRed:0.86 green:0.90 blue:0.78 alpha:1] set];
    else
        [[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1] set];
    [ell fill];
    [[NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1] set];
    [ell setLineWidth:sel ? 2.2 : 1.3];
    if (ot.kind == NUObjectValue) {
        CGFloat dash[2] = {5, 3};
        [ell setLineDash:dash count:2 phase:0];
    }
    [ell stroke];

    NSDictionary *ta = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor blackColor]
    };
    NSString *label = [ot displayName];
    NSSize ts = [label sizeWithAttributes:ta];
    CGFloat textY = NSMidY(f) - ts.height * 0.5;
    if (ot.valueConstraint.length) textY -= 6;
    [label drawAtPoint:NSMakePoint(NSMidX(f) - ts.width * 0.5, textY) withAttributes:ta];
    if (ot.valueConstraint.length) {
        NSDictionary *va = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [NSColor darkGrayColor]
        };
        NSSize vs = [ot.valueConstraint sizeWithAttributes:va];
        [ot.valueConstraint drawAtPoint:NSMakePoint(NSMidX(f) - vs.width * 0.5, textY + ts.height)
                         withAttributes:va];
    }
}

- (void)drawUCBarFrom:(NSPoint)a to:(NSPoint)b {
    [[NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1] set];
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p setLineWidth:2.0];
    [p moveToPoint:a];
    [p lineToPoint:b];
    [p stroke];
    NSBezierPath *t = [NSBezierPath bezierPath];
    [t setLineWidth:1.4];
    [t moveToPoint:NSMakePoint(a.x, a.y - 3)];
    [t lineToPoint:NSMakePoint(a.x, a.y + 3)];
    [t moveToPoint:NSMakePoint(b.x, b.y - 3)];
    [t lineToPoint:NSMakePoint(b.x, b.y + 3)];
    [t stroke];
}

- (void)drawFactType:(NUFactType *)ft {
    BOOL sel = (ft == self.selectedFact);
    NSUInteger n = ft.roles.count;
    if (n == 0) return;

    for (NSUInteger i = 0; i < n; i++) {
        NSRect r = [ft roleFrameAtIndex:i];
        BOOL roleSel = sel && (self.selectedRoleIndex == (NSInteger)i);
        NSBezierPath *box = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)];
        if (roleSel)
            [[NSColor colorWithCalibratedRed:0.86 green:0.90 blue:0.78 alpha:1] set];
        else
            [[NSColor whiteColor] set];
        [box fill];
        [[NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1] set];
        [box setLineWidth:sel ? 1.6 : 1.1];
        [box stroke];
    }

    CGFloat barY = ft.origin.y - 7;
    if (ft.spanningUnique && n > 0) {
        NSRect a = [ft roleFrameAtIndex:0];
        NSRect b = [ft roleFrameAtIndex:n - 1];
        [self drawUCBarFrom:NSMakePoint(NSMinX(a) + 3, barY)
                         to:NSMakePoint(NSMaxX(b) - 3, barY)];
    } else {
        for (NSUInteger i = 0; i < n; i++) {
            if (!ft.roles[i].unique) continue;
            NSRect r = [ft roleFrameAtIndex:i];
            [self drawUCBarFrom:NSMakePoint(NSMinX(r) + 3, barY)
                             to:NSMakePoint(NSMaxX(r) - 3, barY)];
        }
    }

    NSDictionary *ra = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.15 green:0.15 blue:0.18 alpha:1]
    };
    NSString *reading = ft.reading ?: @"";
    NSSize rs = [reading sizeWithAttributes:ra];
    NSRect ff = [ft frame];
    [reading drawAtPoint:NSMakePoint(NSMidX(ff) - rs.width * 0.5, NSMaxY(ff) + 3)
          withAttributes:ra];

    for (NSUInteger i = 0; i < n; i++) {
        NURole *role = ft.roles[i];
        NUObjectType *ot = [self.diagram objectTypeWithId:role.playerId];
        if (!ot) continue;
        NSRect rf = [ft roleFrameAtIndex:i];
        NSRect of = [ot frame];
        NSPoint rc = NSMakePoint(NSMidX(rf), NSMidY(rf));
        NSPoint oc = NSMakePoint(NSMidX(of), NSMidY(of));
        NSPoint a = [self ellipseAnchor:of toward:rc];
        NSPoint b = rc;
        CGFloat dx = oc.x - rc.x, dy = oc.y - rc.y;
        if (fabs(dx) > fabs(dy))
            b.x = (dx > 0) ? NSMaxX(rf) : NSMinX(rf);
        else
            b.y = (dy > 0) ? NSMaxY(rf) : NSMinY(rf);

        [[NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1] set];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line setLineWidth:1.15];
        [line moveToPoint:a];
        [line lineToPoint:b];
        [line stroke];

        if (role.mandatory) {
            NSPoint dot = NSMakePoint(a.x + (b.x - a.x) * 0.12,
                                      a.y + (b.y - a.y) * 0.12);
            NSRect dr = NSMakeRect(dot.x - 4, dot.y - 4, 8, 8);
            [[NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1] set];
            [[NSBezierPath bezierPathWithOvalInRect:dr] fill];
        }
        if ([role hasFrequency]) {
            NSDictionary *fa = @{
                NSFontAttributeName: [NSFont systemFontOfSize:10],
                NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.15 green:0.15 blue:0.35 alpha:1]
            };
            NSString *lab = [role frequencyLabel];
            NSSize ls = [lab sizeWithAttributes:fa];
            [lab drawAtPoint:NSMakePoint(NSMidX(rf) - ls.width * 0.5, NSMinY(rf) - 16)
              withAttributes:fa];
        }
    }

    if (ft.ringKind != NURingNone) {
        NSRect fr = [ft frame];
        NSRect rr = NSMakeRect(NSMaxX(fr) + 6, NSMinY(fr) - 2, 28, 18);
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:rr];
        [[NSColor whiteColor] set];
        [ring fill];
        [[NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1] set];
        [ring setLineWidth:1.3];
        [ring stroke];
        NSString *rk = [NUFactType nameForRing:ft.ringKind];
        NSDictionary *ra2 = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:9],
            NSForegroundColorAttributeName: [NSColor blackColor]
        };
        NSSize rks = [rk sizeWithAttributes:ra2];
        [rk drawAtPoint:NSMakePoint(NSMidX(rr) - rks.width * 0.5,
                                    NSMidY(rr) - rks.height * 0.5)
         withAttributes:ra2];
    }
}

- (void)drawSubtype:(NUSubtype *)st {
    NUObjectType *sub = [self.diagram objectTypeWithId:st.subId];
    NUObjectType *sup = [self.diagram objectTypeWithId:st.superId];
    if (!sub || !sup) return;
    BOOL sel = (st == self.selectedSubtype);
    NSRect a = [sub frame], b = [sup frame];
    NSPoint ac = NSMakePoint(NSMidX(a), NSMidY(a));
    NSPoint bc = NSMakePoint(NSMidX(b), NSMidY(b));
    NSPoint from = [self ellipseAnchor:a toward:bc];
    NSPoint to = [self ellipseAnchor:b toward:ac];
    NSColor *col = sel
        ? [NSColor colorWithCalibratedRed:0.7 green:0.15 blue:0.1 alpha:1]
        : [NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1];
    [col set];
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p setLineWidth:sel ? 2.4 : 2.0];
    [p moveToPoint:from];
    [p lineToPoint:to];
    [p stroke];
    CGFloat ang = atan2(to.y - from.y, to.x - from.x);
    CGFloat s = 12;
    NSPoint p1 = NSMakePoint(to.x - s * cos(ang - 0.4), to.y - s * sin(ang - 0.4));
    NSPoint p2 = NSMakePoint(to.x - s * cos(ang + 0.4), to.y - s * sin(ang + 0.4));
    NSBezierPath *tri = [NSBezierPath bezierPath];
    [tri moveToPoint:to];
    [tri lineToPoint:p1];
    [tri lineToPoint:p2];
    [tri closePath];
    [tri fill];
}

- (NSPoint)centerForRef:(NURoleRef *)ref {
    NUFactType *ft = [self.diagram factTypeWithId:ref.factId];
    if (!ft) return NSZeroPoint;
    NSRect r = [ft roleFrameAtIndex:ref.roleIndex];
    return NSMakePoint(NSMidX(r), NSMidY(r));
}

- (NSRect)badgeRect:(NUConstraint *)c {
    return NSMakeRect(c.badge.x - 12, c.badge.y - 12, 24, 24);
}

- (void)drawConstraint:(NUConstraint *)c {
    BOOL sel = (c == self.selectedConstraint);
    NSColor *col = sel
        ? [NSColor colorWithCalibratedRed:0.7 green:0.15 blue:0.1 alpha:1]
        : [NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1];
    [col set];
    for (NURoleRef *ref in c.roles) {
        NSPoint p = [self centerForRef:ref];
        NSBezierPath *ln = [NSBezierPath bezierPath];
        [ln setLineWidth:sel ? 1.4 : 1.0];
        CGFloat dash[2] = {3, 3};
        [ln setLineDash:dash count:2 phase:0];
        [ln moveToPoint:p];
        [ln lineToPoint:c.badge];
        [ln stroke];
    }
    NSRect br = [self badgeRect:c];
    NSBezierPath *circ = [NSBezierPath bezierPathWithOvalInRect:br];
    [[NSColor colorWithCalibratedRed:0.97 green:0.97 blue:0.96 alpha:1] set];
    [circ fill];
    [col set];
    [circ setLineWidth:sel ? 2.0 : 1.3];
    [circ stroke];
    NSString *lab = [c markLabel];
    NSDictionary *ta = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:10],
        NSForegroundColorAttributeName: col
    };
    NSSize ts = [lab sizeWithAttributes:ta];
    [lab drawAtPoint:NSMakePoint(NSMidX(br) - ts.width * 0.5,
                                 NSMidY(br) - ts.height * 0.5)
      withAttributes:ta];
}

- (void)drawRect:(NSRect)dirty {
    [self drawBackground:dirty];
    for (NUSubtype *s in self.diagram.subtypes) [self drawSubtype:s];
    for (NUFactType *ft in self.diagram.factTypes) [self drawFactType:ft];
    for (NUConstraint *c in self.diagram.constraints) [self drawConstraint:c];
    for (NUObjectType *ot in self.diagram.objectTypes) [self drawObjectType:ot];

    if (self.linkStack.count && self.tool != NUToolSelect) {
        id last = [self.linkStack lastObject];
        NSPoint from = self.hoverPoint;
        if ([last isKindOfClass:[NUObjectType class]]) {
            NSRect f = [(NUObjectType *)last frame];
            from = NSMakePoint(NSMidX(f), NSMidY(f));
        }
        [[NSColor colorWithCalibratedRed:0.5 green:0.2 blue:0.1 alpha:1] set];
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p setLineWidth:1.1];
        CGFloat dash[2] = {4, 3};
        [p setLineDash:dash count:2 phase:0];
        [p moveToPoint:from];
        [p lineToPoint:self.hoverPoint];
        [p stroke];
    }
    if (self.pendingRefs.count) {
        [[NSColor colorWithCalibratedRed:0.5 green:0.2 blue:0.1 alpha:1] set];
        for (NURoleRef *ref in self.pendingRefs) {
            NSPoint from = [self centerForRef:ref];
            NSBezierPath *p = [NSBezierPath bezierPath];
            [p setLineWidth:1.1];
            CGFloat dash[2] = {4, 3};
            [p setLineDash:dash count:2 phase:0];
            [p moveToPoint:from];
            [p lineToPoint:self.hoverPoint];
            [p stroke];
        }
    }
}

- (NUObjectType *)objectAtPoint:(NSPoint)p {
    for (NSInteger i = (NSInteger)self.diagram.objectTypes.count - 1; i >= 0; i--) {
        NUObjectType *o = self.diagram.objectTypes[i];
        if (NSPointInRect(p, [o frame])) return o;
    }
    return nil;
}

- (NUFactType *)factAtPoint:(NSPoint)p roleIndex:(NSInteger *)idx {
    if (idx) *idx = -1;
    for (NSInteger i = (NSInteger)self.diagram.factTypes.count - 1; i >= 0; i--) {
        NUFactType *ft = self.diagram.factTypes[i];
        NSRect hit = NSInsetRect([ft frame], -4, -14);
        if (!NSPointInRect(p, hit)) continue;
        if (idx) {
            *idx = -1;
            for (NSUInteger r = 0; r < ft.roles.count; r++)
                if (NSPointInRect(p, NSInsetRect([ft roleFrameAtIndex:r], -2, -2)))
                    *idx = (NSInteger)r;
        }
        return ft;
    }
    return nil;
}

static CGFloat NUDistSeg(NSPoint p, NSPoint a, NSPoint b) {
    CGFloat vx = b.x - a.x, vy = b.y - a.y;
    CGFloat wx = p.x - a.x, wy = p.y - a.y;
    CGFloat c1 = vx * wx + vy * wy;
    if (c1 <= 0) return hypot(p.x - a.x, p.y - a.y);
    CGFloat c2 = vx * vx + vy * vy;
    if (c2 <= c1) return hypot(p.x - b.x, p.y - b.y);
    CGFloat t = c1 / c2;
    return hypot(p.x - (a.x + t * vx), p.y - (a.y + t * vy));
}

- (NUConstraint *)constraintAtPoint:(NSPoint)p {
    for (NSInteger i = (NSInteger)self.diagram.constraints.count - 1; i >= 0; i--) {
        NUConstraint *c = self.diagram.constraints[i];
        if (NSPointInRect(p, NSInsetRect([self badgeRect:c], -2, -2))) return c;
    }
    return nil;
}

- (NUSubtype *)subtypeAtPoint:(NSPoint)p {
    for (NUSubtype *s in self.diagram.subtypes) {
        NUObjectType *sub = [self.diagram objectTypeWithId:s.subId];
        NUObjectType *sup = [self.diagram objectTypeWithId:s.superId];
        if (!sub || !sup) continue;
        NSRect a = [sub frame], b = [sup frame];
        NSPoint ac = NSMakePoint(NSMidX(a), NSMidY(a));
        NSPoint bc = NSMakePoint(NSMidX(b), NSMidY(b));
        NSPoint from = [self ellipseAnchor:a toward:bc];
        NSPoint to = [self ellipseAnchor:b toward:ac];
        if (NUDistSeg(p, from, to) < 7) return s;
    }
    return nil;
}

- (void)notifyChange {
    if ([self.delegate respondsToSelector:@selector(diagramViewDidEdit:)])
        [self.delegate diagramViewDidEdit:self];
}
- (void)notifySelect {
    if ([self.delegate respondsToSelector:@selector(diagramViewSelectionDidChange:)])
        [self.delegate diagramViewSelectionDidChange:self];
}

- (void)clearSelectionKeepingTool {
    self.selectedObject = nil;
    self.selectedFact = nil;
    self.selectedSubtype = nil;
    self.selectedConstraint = nil;
    self.selectedRoleIndex = -1;
}

- (void)finishFactIfReady {
    NSUInteger need = 0;
    NSString *reading = @"... ...";
    if (self.tool == NUToolFactUnary) { need = 1; reading = @"..."; }
    else if (self.tool == NUToolFactBinary) { need = 2; reading = @"... ..."; }
    else if (self.tool == NUToolFactTernary) { need = 3; reading = @"... ... ..."; }
    if (need == 0 || self.linkStack.count < need) return;
    NSArray *players = [self.linkStack subarrayWithRange:NSMakeRange(0, need)];
    NUFactType *ft = [self.diagram addFactWithPlayers:players reading:reading];
    if (need == 1 && ft.roles.count) ft.roles[0].unique = YES;
    self.selectedFact = ft;
    self.selectedObject = nil;
    self.selectedSubtype = nil;
    [self.linkStack removeAllObjects];
    self.tool = NUToolSelect;
    [self notifyChange];
    [self notifySelect];
    [self recomputeSize];
    [self setNeedsDisplay:YES];
}

- (BOOL)isConstraintTool {
    return self.tool == NUToolExtUnique || self.tool == NUToolSubset
        || self.tool == NUToolEquality || self.tool == NUToolExclusion
        || self.tool == NUToolFrequency || self.tool == NUToolRing;
}

- (void)commitPendingConstraint {
    NUConstraintKind kind = NUConstraintExternalUnique;
    NSInteger need = 2;
    NSInteger split = 1;
    if (self.tool == NUToolSubset) kind = NUConstraintSubset;
    else if (self.tool == NUToolEquality) kind = NUConstraintEquality;
    else if (self.tool == NUToolExclusion) kind = NUConstraintExclusion;
    else if (self.tool == NUToolExtUnique) kind = NUConstraintExternalUnique;
    else return;
    if ((NSInteger)self.pendingRefs.count < need) return;
    CGFloat ax = 0, ay = 0;
    for (NURoleRef *r in self.pendingRefs) {
        NSPoint p = [self centerForRef:r];
        ax += p.x; ay += p.y;
    }
    NSPoint badge = NSMakePoint(ax / self.pendingRefs.count,
                                ay / self.pendingRefs.count - 36);
    NUConstraint *c = [self.diagram addConstraint:kind
                                            roles:self.pendingRefs
                                            split:split
                                            badge:badge];
    [self.pendingRefs removeAllObjects];
    self.tool = NUToolSelect;
    self.selectedConstraint = c;
    self.selectedFact = nil;
    self.selectedObject = nil;
    [self notifyChange];
    [self notifySelect];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    self.hoverPoint = p;
    NUObjectType *ohit = [self objectAtPoint:p];
    NSInteger ridx = -1;
    NUFactType *fhit = [self factAtPoint:p roleIndex:&ridx];

    if (self.tool == NUToolRing) {
        if (fhit) {
            fhit.ringKind = (fhit.ringKind == NURingNone) ? NURingIrreflexive : fhit.ringKind;
            self.selectedFact = fhit;
            self.tool = NUToolSelect;
            [self notifyChange];
            [self notifySelect];
            [self setNeedsDisplay:YES];
        }
        return;
    }
    if (self.tool == NUToolFrequency) {
        if (fhit && ridx >= 0 && ridx < (NSInteger)fhit.roles.count) {
            NURole *role = fhit.roles[ridx];
            if (![role hasFrequency]) { role.freqMin = 1; role.freqMax = 1; }
            self.selectedFact = fhit;
            self.selectedRoleIndex = ridx;
            self.tool = NUToolSelect;
            [self notifyChange];
            [self notifySelect];
            [self setNeedsDisplay:YES];
        }
        return;
    }
    if (self.tool == NUToolExtUnique || self.tool == NUToolSubset
        || self.tool == NUToolEquality || self.tool == NUToolExclusion) {
        if (fhit && ridx >= 0) {
            [self.pendingRefs addObject:[NURoleRef refToFact:fhit.identifier role:ridx]];
            if (self.tool == NUToolSubset || self.tool == NUToolEquality) {
                if (self.pendingRefs.count >= 2) [self commitPendingConstraint];
            }
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.pendingRefs.count >= 2) [self commitPendingConstraint];
        return;
    }

    if (self.tool == NUToolFactUnary || self.tool == NUToolFactBinary ||
        self.tool == NUToolFactTernary) {
        if (ohit) {
            [self.linkStack addObject:ohit];
            [self finishFactIfReady];
            [self setNeedsDisplay:YES];
        }
        return;
    }
    if (self.tool == NUToolSubtype) {
        if (ohit) [self.linkStack addObject:ohit];
        if (self.linkStack.count >= 2) {
            [self.diagram addSubtypeFrom:self.linkStack[0] to:self.linkStack[1]];
            [self.linkStack removeAllObjects];
            self.tool = NUToolSelect;
            [self notifyChange];
        }
        [self setNeedsDisplay:YES];
        return;
    }

    self.dragging = NO;
    self.draggingFact = NO;
    self.draggingConstraint = NO;
    NUConstraint *chit = [self constraintAtPoint:p];
    if (chit) {
        [self clearSelectionKeepingTool];
        self.selectedConstraint = chit;
        self.draggingConstraint = YES;
        self.dragStart = p;
        self.dragOrigin = chit.badge;
        [self notifySelect];
        [self setNeedsDisplay:YES];
        return;
    }
    if (ohit) {
        [self clearSelectionKeepingTool];
        self.selectedObject = ohit;
        self.dragging = YES;
        self.dragStart = p;
        self.dragOrigin = ohit.origin;
        NSMutableArray *arr = self.diagram.objectTypes;
        [arr removeObject:ohit];
        [arr addObject:ohit];
        [self notifySelect];
        [self setNeedsDisplay:YES];
        return;
    }
    if (fhit) {
        [self clearSelectionKeepingTool];
        self.selectedFact = fhit;
        self.selectedRoleIndex = ridx;
        self.draggingFact = YES;
        self.dragStart = p;
        self.dragOrigin = fhit.origin;
        [self notifySelect];
        [self setNeedsDisplay:YES];
        return;
    }
    NUSubtype *shit = [self subtypeAtPoint:p];
    [self clearSelectionKeepingTool];
    self.selectedSubtype = shit;
    [self notifySelect];
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)e {
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    self.hoverPoint = p;
    if (self.tool != NUToolSelect) { [self setNeedsDisplay:YES]; return; }
    CGFloat dx = p.x - self.dragStart.x;
    CGFloat dy = p.y - self.dragStart.y;
    if (self.dragging && self.selectedObject) {
        self.selectedObject.origin = NSMakePoint(MAX(8, self.dragOrigin.x + dx),
                                                 MAX(8, self.dragOrigin.y + dy));
        [self recomputeSize];
        [self setNeedsDisplay:YES];
    } else if (self.draggingFact && self.selectedFact) {
        self.selectedFact.origin = NSMakePoint(MAX(8, self.dragOrigin.x + dx),
                                               MAX(8, self.dragOrigin.y + dy));
        [self recomputeSize];
        [self setNeedsDisplay:YES];
    } else if (self.draggingConstraint && self.selectedConstraint) {
        self.selectedConstraint.badge = NSMakePoint(self.dragOrigin.x + dx,
                                                    self.dragOrigin.y + dy);
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)e {
    if (self.dragging || self.draggingFact || self.draggingConstraint) [self notifyChange];
    self.dragging = NO;
    self.draggingFact = NO;
    self.draggingConstraint = NO;
}

- (void)keyDown:(NSEvent *)e {
    NSString *chars = [e charactersIgnoringModifiers];
    if (!chars.length) { [super keyDown:e]; return; }
    unichar ch = [chars characterAtIndex:0];
    if (ch == NSCarriageReturnCharacter || ch == NSEnterCharacter) {
        [self commitPendingConstraint];
        return;
    }
    if (ch == NSDeleteCharacter || ch == NSBackspaceCharacter || ch == NSDeleteFunctionKey) {
        if (self.selectedObject) {
            [self.diagram removeObjectType:self.selectedObject];
            self.selectedObject = nil;
        } else if (self.selectedConstraint) {
            [self.diagram removeConstraint:self.selectedConstraint];
            self.selectedConstraint = nil;
        } else if (self.selectedFact) {
            [self.diagram removeFactType:self.selectedFact];
            self.selectedFact = nil;
        } else if (self.selectedSubtype) {
            [self.diagram removeSubtype:self.selectedSubtype];
            self.selectedSubtype = nil;
        } else {
            [super keyDown:e];
            return;
        }
        [self notifyChange];
        [self notifySelect];
        [self recomputeSize];
        [self setNeedsDisplay:YES];
        return;
    }
    [super keyDown:e];
}

@end
