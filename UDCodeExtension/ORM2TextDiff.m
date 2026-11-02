/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORM2TextDiff.h"

/* More edits than this (lines dropped and added) is a rewrite, made one run. */
static const NSInteger ORM2MostEdits = 2000;

@implementation ORM2TextChange

- (instancetype)initWithOffset:(NSUInteger)offset length:(NSUInteger)length text:(NSString *)text
{
	if ((self = [super init])) {
		_offset = offset;
		_length = length;
		_text = [text copy];
	}
	return self;
}

@end

/* The text's lines, each with its line ending ("\n", "\r\n" alike end at
 * the "\n"); the last one maybe without. */
static NSArray<NSString *> *
ORM2Lines(NSString *text)
{
	NSMutableArray *lines = [NSMutableArray array];
	NSUInteger length = [text length], start = 0;
	while (start < length) {
		NSRange end = [text rangeOfString:@"\n" options:NSLiteralSearch range:NSMakeRange(start, length - start)];
		NSUInteger next = end.location == NSNotFound ? length : NSMaxRange(end);
		[lines addObject:[text substringWithRange:NSMakeRange(start, next - start)]];
		start = next;
	}
	return lines;
}

NSArray<ORM2TextChange *> *
ORM2LineChanges(NSString *old, NSString *new)
{
	if ([old isEqualToString:new]) {
		return @[];
	}
	NSArray *a = ORM2Lines(old), *b = ORM2Lines(new);
	NSInteger n = (NSInteger)[a count], m = (NSInteger)[b count];
	/* The lines both start and end with, out of the search. */
	NSInteger head = 0;
	while (head < n && head < m && [[a objectAtIndex:(NSUInteger)head] isEqualToString:[b objectAtIndex:(NSUInteger)head]]) {
		head++;
	}
	NSInteger tail = 0;
	while (tail < n - head && tail < m - head
	       && [[a objectAtIndex:(NSUInteger)(n - 1 - tail)] isEqualToString:[b objectAtIndex:(NSUInteger)(m - 1 - tail)]]) {
		tail++;
	}
	NSInteger an = n - head - tail, bm = m - head - tail;
	/* Myers: for each number of edits d, the furthest x reached on each
	 * diagonal k = x - y; the diagonals d reaches (-d to d) kept per d, to
	 * walk back. Past ORM2MostEdits, a rewrite more than a change: one run. */
	NSInteger max = MIN(an + bm, ORM2MostEdits), offset = max + 1;
	NSMutableArray<NSData *> *trace = [NSMutableArray array];
	NSMutableData *frontier = [NSMutableData dataWithLength:sizeof(NSInteger) * (NSUInteger)(2 * max + 3)];
	NSInteger *v = [frontier mutableBytes];
	NSInteger found = -1;
	for (NSInteger d = 0; d <= max && found < 0; d++) {
		for (NSInteger k = -d; k <= d; k += 2) {
			NSInteger x = (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) ? v[offset + k + 1] : v[offset + k - 1] + 1;
			NSInteger y = x - k;
			while (x < an && y < bm && [[a objectAtIndex:(NSUInteger)(head + x)] isEqualToString:[b objectAtIndex:(NSUInteger)(head + y)]]) {
				x++;
				y++;
			}
			v[offset + k] = x;
			if (x >= an && y >= bm) {
				found = d;
				break;
			}
		}
		[trace addObject:[NSData dataWithBytes:v + offset - d length:sizeof(NSInteger) * (NSUInteger)(2 * d + 1)]];
	}
	if (found < 0) {
		NSUInteger from = 0, to = 0, i = 0;
		for (NSString *line in a) {
			if ((NSInteger)i < head) {
				from += [line length];
			}
			if ((NSInteger)i < n - tail) {
				to += [line length];
			}
			i++;
		}
		NSArray *middle = [b subarrayWithRange:NSMakeRange((NSUInteger)head, (NSUInteger)bm)];
		return @[ [[ORM2TextChange alloc] initWithOffset:from length:to - from text:[middle componentsJoinedByString:@""]] ];
	}
	/* Walked back from the end: each line kept, dropped (old's) or added
	 * (new's), last first. */
	NSMutableArray *steps = [NSMutableArray array];   /* @[ kind, old index, new index ] */
	NSInteger x = an, y = bm;
	for (NSInteger d = found; d > 0; d--) {
		/* d - 1's diagonals, from -(d - 1). */
		const NSInteger *w = (const NSInteger *)[[trace objectAtIndex:(NSUInteger)(d - 1)] bytes] + (d - 1);
		NSInteger k = x - y;
		NSInteger previous = (k == -d || (k != d && w[k - 1] < w[k + 1])) ? k + 1 : k - 1;
		NSInteger px = w[previous], py = px - previous;
		while (x > px && y > py) {
			x--;
			y--;
			[steps addObject:@[ @0, @(x), @(y) ]];
		}
		if (x == px) {
			y--;
			[steps addObject:@[ @1, @(x), @(y) ]];   /* new's line y added */
		} else {
			x--;
			[steps addObject:@[ @-1, @(x), @(y) ]];  /* old's line x dropped */
		}
	}
	while (x > 0 && y > 0) {
		x--;
		y--;
		[steps addObject:@[ @0, @(x), @(y) ]];
	}
	/* Runs of dropped and added lines, at old's character offsets. */
	NSMutableArray *offsets = [NSMutableArray arrayWithCapacity:(NSUInteger)n + 1];
	NSUInteger at = 0;
	for (NSString *line in a) {
		[offsets addObject:@(at)];
		at += [line length];
	}
	[offsets addObject:@(at)];
	NSMutableArray *changes = [NSMutableArray array];
	NSInteger runStart = -1, runEnd = -1;
	NSMutableString *added = nil;
	for (NSArray *step in [steps reverseObjectEnumerator]) {
		NSInteger kind = [[step objectAtIndex:0] integerValue];
		NSInteger i = head + [[step objectAtIndex:1] integerValue], j = head + [[step objectAtIndex:2] integerValue];
		if (kind == 0) {
			if (runStart >= 0) {
				NSUInteger from = [[offsets objectAtIndex:(NSUInteger)runStart] unsignedIntegerValue];
				NSUInteger to = [[offsets objectAtIndex:(NSUInteger)runEnd] unsignedIntegerValue];
				[changes addObject:[[ORM2TextChange alloc] initWithOffset:from length:to - from text:added]];
				runStart = -1;
			}
			continue;
		}
		if (runStart < 0) {
			runStart = runEnd = i;
			added = [NSMutableString string];
		}
		if (kind < 0) {
			runEnd = i + 1;
		} else {
			[added appendString:[b objectAtIndex:(NSUInteger)j]];
		}
	}
	if (runStart >= 0) {
		NSUInteger from = [[offsets objectAtIndex:(NSUInteger)runStart] unsignedIntegerValue];
		NSUInteger to = [[offsets objectAtIndex:(NSUInteger)runEnd] unsignedIntegerValue];
		[changes addObject:[[ORM2TextChange alloc] initWithOffset:from length:to - from text:added]];
	}
	return changes;
}
