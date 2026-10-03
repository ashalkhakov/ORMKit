/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMReadingText.h"

@interface ORMReadingPart ()
@property (nonatomic, readwrite) NSUInteger roleIndex;
@property (nonatomic, readwrite, copy) NSString *preBoundText;
@property (nonatomic, readwrite, copy) NSString *postBoundText;
@property (nonatomic, readwrite, copy) NSString *followingText;
@end

@implementation ORMReadingPart
@end

@interface ORMReadingText ()
@property (nonatomic, readwrite, copy) NSString *frontText;
@property (nonatomic, readwrite, copy) NSArray<ORMReadingPart *> *parts;
@end

/* The text before a placeholder split into what stays and what binds to
 * it: from the last word ending in a hyphen followed by whitespace, with
 * the hyphen taken out. */
static void
ORMSplitPreBound(NSString *text, NSString **free, NSString **bound)
{
	NSRegularExpression *hyphen = [NSRegularExpression regularExpressionWithPattern:@"(\\S+)-(\\s+)" options:0
	                                                                         error:NULL];
	NSTextCheckingResult *last = [[hyphen matchesInString:text options:0 range:NSMakeRange(0, [text length])] lastObject];
	if (last == nil) {
		*free = text;
		*bound = nil;
		return;
	}
	NSRange word = [last rangeAtIndex:1];
	*free = [text substringToIndex:word.location];
	*bound = [NSString stringWithFormat:@"%@%@%@", [text substringWithRange:word],
	          [text substringWithRange:[last rangeAtIndex:2]], [text substringFromIndex:NSMaxRange([last range])]];
}

/* The text after a placeholder split into what binds back to it and
 * what follows: up to the end of the first word starting with a hyphen
 * after whitespace ("{1} of -birth" binds " of birth"), the hyphen taken
 * out. */
static void
ORMSplitPostBound(NSString *text, NSString **bound, NSString **free)
{
	NSRegularExpression *hyphen = [NSRegularExpression regularExpressionWithPattern:@"^((?:\\s+[^\\s-]\\S*)*?\\s+)-(\\S+)" options:0
	                                                                         error:NULL];
	NSTextCheckingResult *first = [hyphen firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
	if (first == nil) {
		*bound = nil;
		*free = text;
		return;
	}
	*bound = [NSString stringWithFormat:@"%@%@", [text substringWithRange:[first rangeAtIndex:1]],
	          [text substringWithRange:[first rangeAtIndex:2]]];
	*free = [text substringFromIndex:NSMaxRange([first range])];
}

@implementation ORMReadingText

+ (instancetype)readingTextWithString:(NSString *)text arity:(NSUInteger)arity reason:(NSString **)reason
{
	NSRegularExpression *placeholder = [NSRegularExpression regularExpressionWithPattern:@"\\{(\\d+)\\}" options:0
	                                                                              error:NULL];
	NSArray *matches = [placeholder matchesInString:text ?: @"" options:0 range:NSMakeRange(0, [text length])];
	NSMutableIndexSet *seen = [NSMutableIndexSet indexSet];
	for (NSTextCheckingResult *match in matches) {
		NSUInteger index = (NSUInteger)[[text substringWithRange:[match rangeAtIndex:1]] integerValue];
		if (index >= arity || [seen containsIndex:index]) {
			if (reason != NULL) {
				*reason = index >= arity
					? [NSString stringWithFormat:@"The reading names role {%lu}, but the fact type has %lu.",
					   (unsigned long)index, (unsigned long)arity]
					: [NSString stringWithFormat:@"The reading names role {%lu} twice.", (unsigned long)index];
			}
			return nil;
		}
		[seen addIndex:index];
	}
	if ([seen count] != arity) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"A reading must place each of the %lu roles once.",
			           (unsigned long)arity];
		}
		return nil;
	}

	/* The literal texts around the placeholders: one more than there are
	 * placeholders. */
	NSMutableArray *literals = [NSMutableArray array];
	NSUInteger at = 0;
	for (NSTextCheckingResult *match in matches) {
		[literals addObject:[text substringWithRange:NSMakeRange(at, [match range].location - at)]];
		at = NSMaxRange([match range]);
	}
	[literals addObject:[text substringFromIndex:at]];

	ORMReadingText *reading = [[self alloc] init];
	NSMutableArray *parts = [NSMutableArray array];
	for (NSUInteger i = 0; i < [matches count]; i++) {
		ORMReadingPart *part = [[ORMReadingPart alloc] init];
		NSTextCheckingResult *match = [matches objectAtIndex:i];
		part.roleIndex = (NSUInteger)[[text substringWithRange:[match rangeAtIndex:1]] integerValue];
		[parts addObject:part];
	}
	/* Each literal between two placeholders may hold the post-bound text
	 * of the one before and the pre-bound text of the one after. */
	for (NSUInteger i = 0; i < [literals count]; i++) {
		NSString *literal = [literals objectAtIndex:i];
		NSString *post = nil;
		if (i > 0) {
			NSString *rest = nil;
			ORMSplitPostBound(literal, &post, &rest);
			literal = rest;
		}
		NSString *pre = nil;
		NSString *free = literal;
		if (i < [parts count]) {
			ORMSplitPreBound(literal, &free, &pre);
		}
		if (i == 0) {
			reading.frontText = free;
		} else {
			ORMReadingPart *before = [parts objectAtIndex:i - 1];
			before.postBoundText = post;
			before.followingText = free;
		}
		if (i < [parts count]) {
			[[parts objectAtIndex:i] setPreBoundText:pre];
		}
	}
	reading.parts = parts;
	return reading;
}

- (NSString *)expandWithNames:(NSString * (^)(NSUInteger, NSString *, NSString *))name
{
	NSMutableString *out = [NSMutableString stringWithString:self.frontText ?: @""];
	for (ORMReadingPart *part in self.parts) {
		[out appendString:name(part.roleIndex, part.preBoundText, part.postBoundText) ?: @""];
		[out appendString:part.followingText ?: @""];
	}
	return out;
}

+ (NSString *)readingFromSentence:(NSString *)sentence withNames:(NSArray<NSString *> *)names reason:(NSString **)reason
{
	NSString *text = [sentence stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([text hasSuffix:@"."]) {
		text = [text substringToIndex:[text length] - 1];
	}
	NSMutableString *reading = [NSMutableString string];
	NSUInteger at = 0;
	for (NSUInteger i = 0; i < [names count]; i++) {
		NSString *name = [names objectAtIndex:i];
		/* The name as a whole word, from where the last one ended. */
		NSRange found = NSMakeRange(NSNotFound, 0);
		NSRange search = NSMakeRange(at, [text length] - at);
		while (YES) {
			NSRange candidate = [text rangeOfString:name options:0 range:search];
			if (candidate.location == NSNotFound) {
				break;
			}
			BOOL startsWord = candidate.location == 0
				|| ![[NSCharacterSet alphanumericCharacterSet]
				       characterIsMember:[text characterAtIndex:candidate.location - 1]];
			BOOL endsWord = NSMaxRange(candidate) == [text length]
				|| ![[NSCharacterSet alphanumericCharacterSet] characterIsMember:[text characterAtIndex:NSMaxRange(candidate)]];
			if (startsWord && endsWord) {
				found = candidate;
				break;
			}
			search = NSMakeRange(NSMaxRange(candidate), [text length] - NSMaxRange(candidate));
		}
		if (found.location == NSNotFound) {
			if (reason != NULL) {
				*reason = [NSString stringWithFormat:@"'%@' is not in the sentence after what comes before it.", name];
			}
			return nil;
		}
		[reading appendString:[text substringWithRange:NSMakeRange(at, found.location - at)]];
		[reading appendFormat:@"{%lu}", (unsigned long)i];
		at = NSMaxRange(found);
	}
	[reading appendString:[text substringFromIndex:at]];
	NSString *words = [[reading componentsSeparatedByCharactersInSet:[NSCharacterSet decimalDigitCharacterSet]]
		componentsJoinedByString:@""];
	words = [[words stringByReplacingOccurrencesOfString:@"{}" withString:@""]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if ([words length] == 0) {
		if (reason != NULL) {
			*reason = @"The sentence has no predicate: no words besides the object types.";
		}
		return nil;
	}
	return reading;
}

@end
