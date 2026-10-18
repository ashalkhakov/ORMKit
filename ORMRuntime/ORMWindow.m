/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMWindow.h"

NSComparisonResult
ORMWindowCompare(id left, id right)
{
	BOOL none = left == nil || left == [NSNull null];
	BOOL other = right == nil || right == [NSNull null];
	if (none || other) {
		return none == other ? NSOrderedSame : none ? NSOrderedAscending : NSOrderedDescending;
	}
	return [left compare:right];
}

@implementation ORMWindow
{
	NSString *_function;
	ORMWindowOrder _order;
	/* The keys, sorted; for each i, the aggregate of the first i tuples and
	 * of those from i on. */
	NSArray *_keys;
	NSArray *_before;
	NSArray *_after;
}

/* A tuple's key, for sorting: @[ key, value ]. */
static NSInteger
ORMByKey(id left, id right, void *context)
{
	return ((ORMWindowOrder)context)([left firstObject], [right firstObject]);
}

- (id)resultOf:(NSUInteger)count sum:(NSDecimal)sum best:(id)best
{
	if ([_function isEqualToString:@"count"]) {
		return @(count);
	}
	if ([_function isEqualToString:@"sum"]) {
		return [NSDecimalNumber decimalNumberWithDecimal:sum];
	}
	if ([_function isEqualToString:@"average"]) {
		if (count == 0) {
			return nil;
		}
		NSDecimalNumber *total = [NSDecimalNumber decimalNumberWithDecimal:sum];
		return [total decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithMantissa:count exponent:0 isNegative:NO]];
	}
	return best;
}

/* The aggregates of the entries in order, the first n of them for each n
 * (from the end, backwards). */
- (NSArray *)runningOver:(NSArray<NSArray *> *)entries backwards:(BOOL)backwards
{
	BOOL greatest = [_function isEqualToString:@"max"];
	BOOL least = [_function isEqualToString:@"min"];
	NSUInteger n = [entries count];
	NSMutableArray *results = [NSMutableArray arrayWithCapacity:n + 1];
	NSUInteger count = 0;
	NSDecimal sum = [[NSDecimalNumber zero] decimalValue];
	id best = nil;
	[results addObject:[self resultOf:count sum:sum best:best] ?: [NSNull null]];
	for (NSUInteger i = 0; i < n; i++) {
		id value = [[entries objectAtIndex:backwards ? n - 1 - i : i] lastObject];
		if (value != [NSNull null]) {
			count++;
			if ([value isKindOfClass:[NSNumber class]]) {
				NSDecimal add = [value decimalValue];
				NSDecimalAdd(&sum, &sum, &add, NSRoundPlain);
			}
			if (best == nil || (greatest && _order(value, best) == NSOrderedDescending)
			    || (least && _order(value, best) == NSOrderedAscending)) {
				best = value;
			}
		}
		[results addObject:[self resultOf:count sum:sum best:best] ?: [NSNull null]];
	}
	if (!backwards) {
		return results;
	}
	/* From the end: the aggregate of those from i on, at i. */
	return [[results reverseObjectEnumerator] allObjects];
}

+ (instancetype)windowOf:(NSArray<NSArray *> *)tuples
                     key:(NSUInteger)keyColumn
                   value:(NSUInteger)valueColumn
                function:(NSString *)function
                   order:(ORMWindowOrder)order
{
	ORMWindow *window = [[self alloc] init];
	window->_function = [function copy];
	window->_order = order;
	NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[tuples count]];
	for (NSArray *tuple in tuples) {
		id key = keyColumn < [tuple count] ? [tuple objectAtIndex:keyColumn] : [NSNull null];
		id value = valueColumn < [tuple count] ? [tuple objectAtIndex:valueColumn] : [NSNull null];
		if (key != [NSNull null]) {
			[entries addObject:@[ key, value ?: [NSNull null] ]];
		}
	}
	[entries sortUsingFunction:ORMByKey context:(void *)order];
	NSMutableArray *keys = [NSMutableArray arrayWithCapacity:[entries count]];
	for (NSArray *entry in entries) {
		[keys addObject:[entry firstObject]];
	}
	window->_keys = keys;
	window->_before = [window runningOver:entries backwards:NO];
	window->_after = [window runningOver:entries backwards:YES];
	return window;
}

/* The first index whose key is not below the value (strictly: above it). */
- (NSUInteger)boundOf:(id)value above:(BOOL)above
{
	NSUInteger low = 0, high = [_keys count];
	while (low < high) {
		NSUInteger middle = low + (high - low) / 2;
		NSComparisonResult order = _order([_keys objectAtIndex:middle], value);
		if (order == NSOrderedAscending || (above && order == NSOrderedSame)) {
			low = middle + 1;
		} else {
			high = middle;
		}
	}
	return low;
}

- (id)aggregateWhereKey:(NSString *)comparison than:(id)value
{
	id result = nil;
	if (value == nil || value == [NSNull null]) {
		/* No comparison holds: of none. */
		result = [_before firstObject];
	} else if ([comparison isEqualToString:@"<"]) {
		result = [_before objectAtIndex:[self boundOf:value above:NO]];
	} else if ([comparison isEqualToString:@"<="]) {
		result = [_before objectAtIndex:[self boundOf:value above:YES]];
	} else if ([comparison isEqualToString:@">"]) {
		result = [_after objectAtIndex:[self boundOf:value above:YES]];
	} else if ([comparison isEqualToString:@">="]) {
		result = [_after objectAtIndex:[self boundOf:value above:NO]];
	}
	return result != [NSNull null] ? result : nil;
}

@end
