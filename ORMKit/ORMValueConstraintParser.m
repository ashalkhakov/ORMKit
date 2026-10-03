/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMValueConstraintParser.h"

@implementation ORMValueConstraintParser

/* The items of the list, split at commas outside quotes. */
static NSArray *
ORMSplitItems(NSString *text, NSString **reason)
{
	NSMutableArray *items = [NSMutableArray array];
	NSMutableString *current = [NSMutableString string];
	unichar quote = 0;
	for (NSUInteger i = 0; i < [text length]; i++) {
		unichar c = [text characterAtIndex:i];
		if (quote != 0) {
			[current appendFormat:@"%C", c];
			if (c == quote) {
				/* '' inside quotes is a quote. */
				if (i + 1 < [text length] && [text characterAtIndex:i + 1] == quote) {
					i++;
					continue;
				}
				quote = 0;
			}
			continue;
		}
		if (c == '\'' || c == '"') {
			quote = c;
			[current appendFormat:@"%C", c];
		} else if (c == ',') {
			[items addObject:[current copy]];
			[current setString:@""];
		} else {
			[current appendFormat:@"%C", c];
		}
	}
	if (quote != 0) {
		if (reason != NULL) {
			*reason = @"A quoted value is not closed.";
		}
		return nil;
	}
	[items addObject:current];
	return items;
}

/* A value without its quotes; nil with why when it is quoted badly. */
static NSString *
ORMUnquote(NSString *value, NSString **reason)
{
	NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed length] >= 2) {
		unichar first = [trimmed characterAtIndex:0];
		unichar last = [trimmed characterAtIndex:[trimmed length] - 1];
		if ((first == '\'' || first == '"') && last == first) {
			NSString *inner = [trimmed substringWithRange:NSMakeRange(1, [trimmed length] - 2)];
			NSString *doubled = [NSString stringWithFormat:@"%C%C", first, first];
			return [inner stringByReplacingOccurrencesOfString:doubled withString:[NSString stringWithFormat:@"%C", first]];
		}
	}
	if ([trimmed hasPrefix:@"'"] || [trimmed hasPrefix:@"\""]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"%@ is not quoted properly.", trimmed];
		}
		return nil;
	}
	return trimmed;
}

/* The ".." of a range, outside quotes; NSNotFound when there is none. */
static NSUInteger
ORMRangeSeparator(NSString *item)
{
	unichar quote = 0;
	for (NSUInteger i = 0; i + 1 < [item length]; i++) {
		unichar c = [item characterAtIndex:i];
		if (quote != 0) {
			if (c == quote) {
				quote = 0;
			}
			continue;
		}
		if (c == '\'' || c == '"') {
			quote = c;
		} else if (c == '.' && [item characterAtIndex:i + 1] == '.') {
			return i;
		}
	}
	return NSNotFound;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)rangesFromString:(NSString *)text reason:(NSString **)reason
{
	NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed hasPrefix:@"{"] && [trimmed hasSuffix:@"}"]) {
		trimmed = [trimmed substringWithRange:NSMakeRange(1, [trimmed length] - 2)];
	}
	NSArray *items = ORMSplitItems(trimmed, reason);
	if (items == nil) {
		return nil;
	}
	NSMutableArray *ranges = [NSMutableArray array];
	for (NSString *raw in items) {
		NSString *item = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([item length] == 0) {
			if (reason != NULL) {
				*reason = @"An item of the list is empty.";
			}
			return nil;
		}
		NSString *minInclusion = @"NotSet";
		NSString *maxInclusion = @"NotSet";
		unichar first = [item characterAtIndex:0];
		unichar last = [item characterAtIndex:[item length] - 1];
		NSUInteger separator = ORMRangeSeparator(item);
		if (separator != NSNotFound && (first == '[' || first == '(')) {
			minInclusion = first == '[' ? @"Closed" : @"Open";
			item = [item substringFromIndex:1];
			separator--;
		}
		if (separator != NSNotFound && (last == ']' || last == ')')) {
			maxInclusion = last == ']' ? @"Closed" : @"Open";
			item = [item substringToIndex:[item length] - 1];
		}
		NSString *min = nil;
		NSString *max = nil;
		if (separator == NSNotFound) {
			min = ORMUnquote(item, reason);
			max = min;
		} else {
			min = ORMUnquote([item substringToIndex:separator], reason);
			max = ORMUnquote([item substringFromIndex:separator + 2], reason);
			if (min != nil && max != nil && [min length] == 0 && [max length] == 0) {
				if (reason != NULL) {
					*reason = @"A range needs at least one bound.";
				}
				return nil;
			}
		}
		if (min == nil || max == nil) {
			return nil;
		}
		[ranges addObject:@{ @"min": min, @"max": max, @"minInclusion": minInclusion, @"maxInclusion": maxInclusion }];
	}
	return ranges;
}

@end
