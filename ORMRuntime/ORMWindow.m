/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMWindow.h"
#import "ORMTuple.h"

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
	/* The keys and values, sorted by key. */
	NSArray *_keys;
	NSArray *_values;
	/* For each i, how many values (and their sum) among the first i. */
	NSUInteger *_counts;
	NSDecimal *_sums;
	/* For max and min: for each level k and i, the index of the best value
	 * of the 2^k from i (NSNotFound for none); its levels. */
	NSUInteger **_best;
	NSUInteger _levels;
}

/* A tuple's key, for sorting: @[ key, value ]. */
static NSInteger
ORMByKey(id left, id right, void *context)
{
	return ((ORMWindowOrder)context)([left firstObject], [right firstObject]);
}

- (void)dealloc
{
	free(_counts);
	free(_sums);
	for (NSUInteger k = 0; k < _levels; k++) {
		free(_best[k]);
	}
	free(_best);
}

/* The better of two values' indices, for max or min. */
- (NSUInteger)better:(NSUInteger)left or:(NSUInteger)right
{
	if (left == NSNotFound || right == NSNotFound) {
		return left == NSNotFound ? right : left;
	}
	NSComparisonResult order = _order([_values objectAtIndex:left], [_values objectAtIndex:right]);
	BOOL greatest = [_function isEqualToString:@"max"];
	return (greatest ? order != NSOrderedAscending : order != NSOrderedDescending) ? left : right;
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
	NSUInteger n = [entries count];
	NSMutableArray *keys = [NSMutableArray arrayWithCapacity:n];
	NSMutableArray *values = [NSMutableArray arrayWithCapacity:n];
	for (NSArray *entry in entries) {
		[keys addObject:[entry firstObject]];
		[values addObject:[entry lastObject]];
	}
	window->_keys = keys;
	window->_values = values;
	window->_counts = calloc(n + 1, sizeof(NSUInteger));
	window->_sums = calloc(n + 1, sizeof(NSDecimal));
	window->_sums[0] = [[NSDecimalNumber zero] decimalValue];
	for (NSUInteger i = 0; i < n; i++) {
		id value = [values objectAtIndex:i];
		window->_counts[i + 1] = window->_counts[i] + (value != [NSNull null]);
		window->_sums[i + 1] = window->_sums[i];
		if ([value isKindOfClass:[NSNumber class]]) {
			NSDecimal add = [value decimalValue];
			NSDecimalAdd(&window->_sums[i + 1], &window->_sums[i], &add, NSRoundPlain);
		}
	}
	if ([function isEqualToString:@"max"] || [function isEqualToString:@"min"]) {
		NSUInteger levels = 1;
		while (((NSUInteger)1 << levels) <= n) {
			levels++;
		}
		window->_levels = levels;
		window->_best = calloc(levels, sizeof(NSUInteger *));
		window->_best[0] = calloc(n + 1, sizeof(NSUInteger));
		for (NSUInteger i = 0; i < n; i++) {
			window->_best[0][i] = [values objectAtIndex:i] != [NSNull null] ? i : NSNotFound;
		}
		for (NSUInteger k = 1; k < levels; k++) {
			NSUInteger half = (NSUInteger)1 << (k - 1);
			window->_best[k] = calloc(n + 1, sizeof(NSUInteger));
			for (NSUInteger i = 0; i + ((NSUInteger)1 << k) <= n; i++) {
				window->_best[k][i] = [window better:window->_best[k - 1][i] or:window->_best[k - 1][i + half]];
			}
		}
	}
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

/* The aggregate of the sorted entries from low up to high. */
- (id)aggregateFrom:(NSUInteger)low to:(NSUInteger)high
{
	if (high < low) {
		high = low;
	}
	NSUInteger count = _counts[high] - _counts[low];
	if ([_function isEqualToString:@"count"]) {
		return @(count);
	}
	NSDecimal sum;
	NSDecimalSubtract(&sum, &_sums[high], &_sums[low], NSRoundPlain);
	if ([_function isEqualToString:@"sum"]) {
		return [NSDecimalNumber decimalNumberWithDecimal:sum];
	}
	if ([_function isEqualToString:@"average"]) {
		return count > 0 ? [[NSDecimalNumber decimalNumberWithDecimal:sum]
		                       decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithMantissa:count exponent:0
		                                                                                 isNegative:NO]]
		                 : nil;
	}
	if (_best == nil || high == low) {
		return nil;
	}
	NSUInteger k = 0;
	while (((NSUInteger)1 << (k + 1)) <= high - low) {
		k++;
	}
	NSUInteger best = [self better:_best[k][low] or:_best[k][high - ((NSUInteger)1 << k)]];
	return best != NSNotFound ? [_values objectAtIndex:best] : nil;
}

/* Where the entries a bound admits start (a lower bound) or end. */
- (NSUInteger)edgeOf:(NSString *)comparison than:(id)value lower:(BOOL *)lower
{
	*lower = [comparison hasPrefix:@">"];
	if ([comparison isEqualToString:@"<"] || [comparison isEqualToString:@">="]) {
		return [self boundOf:value above:NO];
	}
	return [self boundOf:value above:YES];
}

- (id)aggregateWhereKey:(NSString *)comparison than:(id)value
{
	return [self aggregateWhereKey:comparison than:value and:nil than:nil];
}

- (id)aggregateWhereKey:(NSString *)comparison than:(id)value and:(NSString *)other than:(id)otherValue
{
	NSUInteger low = 0, high = [_keys count];
	NSArray *bounds = other != nil ? @[ @[ comparison ?: @"", value ?: [NSNull null] ], @[ other, otherValue ?: [NSNull null] ] ]
	                               : @[ @[ comparison ?: @"", value ?: [NSNull null] ] ];
	for (NSArray *bound in bounds) {
		if (![@[ @"<", @"<=", @">", @">=" ] containsObject:[bound firstObject]] || [bound lastObject] == [NSNull null]) {
			/* No comparison holds: of none. */
			return [self aggregateFrom:0 to:0];
		}
		BOOL lower = NO;
		NSUInteger edge = [self edgeOf:[bound firstObject] than:[bound lastObject] lower:&lower];
		if (lower) {
			low = MAX(low, edge);
		} else {
			high = MIN(high, edge);
		}
	}
	return [self aggregateFrom:low to:high];
}

@end

/* A partition's window; with other columns, a window of the tuples of each
 * of their values, by them (a tuple). */
id
ORMWindowsOf(NSArray *tuples, NSUInteger key, NSUInteger value, NSArray<NSNumber *> *also, NSString *function, ORMWindowOrder order)
{
	if ([also count] == 0) {
		return [ORMWindow windowOf:tuples key:key value:value function:function order:order];
	}
	NSMutableDictionary *parts = [NSMutableDictionary dictionary];
	for (NSArray *tuple in tuples) {
		NSMutableArray *values = [NSMutableArray array];
		for (NSNumber *index in also) {
			NSUInteger at = [index unsignedIntegerValue];
			[values addObject:at < [tuple count] ? [tuple objectAtIndex:at] : [NSNull null]];
		}
		ORMTuple *part = [ORMTuple tupleWithValues:values];
		NSMutableArray *list = [parts objectForKey:part];
		if (list == nil) {
			list = [NSMutableArray array];
			[parts setObject:list forKey:part];
		}
		[list addObject:tuple];
	}
	NSMutableDictionary *windows = [NSMutableDictionary dictionary];
	for (ORMTuple *part in parts) {
		[windows setObject:[ORMWindow windowOf:[parts objectForKey:part] key:key value:value function:function order:order]
		            forKey:part];
	}
	return windows;
}
