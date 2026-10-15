/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMReadingText.h"
#import "ORMXML.h"

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

/* A string's characters, to scan in C: freed by the caller. */
static unichar *
ORMCharactersOf(NSString *text, NSUInteger *length)
{
	*length = [text length];
	unichar *chars = malloc(sizeof(unichar) * (*length + 1));
	[text getCharacters:chars range:NSMakeRange(0, *length)];
	return chars;
}

/* The text before a placeholder split into what stays and what binds to
 * it: from the last word ending in a hyphen followed by whitespace, with
 * the hyphen taken out. */
static void
ORMSplitPreBound(NSString *text, NSString **unbound, NSString **bound)
{
	NSUInteger length = 0;
	unichar *chars = ORMCharactersOf(text, &length);
	/* The last word of two characters or more whose last is a hyphen,
	 * whitespace after it. */
	NSUInteger word = NSNotFound, hyphen = 0;
	for (NSUInteger at = 0; at < length;) {
		if (ORMIsWhitespace(chars[at])) {
			at++;
			continue;
		}
		NSUInteger start = at;
		while (at < length && !ORMIsWhitespace(chars[at])) {
			at++;
		}
		NSUInteger end = at;
		while (at < length && ORMIsWhitespace(chars[at])) {
			at++;
		}
		if (end - start >= 2 && chars[end - 1] == '-' && at > end) {
			word = start;
			hyphen = end - 1;
		}
	}
	free(chars);
	if (word == NSNotFound) {
		*unbound = text;
		*bound = nil;
		return;
	}
	*unbound = [text substringToIndex:word];
	*bound = [NSString stringWithFormat:@"%@%@", [text substringWithRange:NSMakeRange(word, hyphen - word)],
	          [text substringFromIndex:hyphen + 1]];
}

/* The text after a placeholder split into what binds back to it and
 * what follows: up to the end of the first word starting with a hyphen
 * after whitespace ("{1} of -birth" binds " of birth"), the hyphen taken
 * out. The text starts with whitespace, and no word before that one starts
 * with a hyphen. */
static void
ORMSplitPostBound(NSString *text, NSString **bound, NSString **unbound)
{
	NSUInteger length = 0;
	unichar *chars = ORMCharactersOf(text, &length);
	NSUInteger hyphen = NSNotFound, end = 0;
	NSUInteger at = 0;
	while (at < length && ORMIsWhitespace(chars[at])) {
		while (at < length && ORMIsWhitespace(chars[at])) {
			at++;
		}
		if (at == length) {
			break;
		}
		NSUInteger start = at;
		while (at < length && !ORMIsWhitespace(chars[at])) {
			at++;
		}
		if (chars[start] == '-') {
			if (at - start >= 2) {
				hyphen = start;
				end = at;
			}
			break;
		}
	}
	free(chars);
	if (hyphen == NSNotFound) {
		*bound = nil;
		*unbound = text;
		return;
	}
	*bound = [NSString stringWithFormat:@"%@%@", [text substringToIndex:hyphen],
	          [text substringWithRange:NSMakeRange(hyphen + 1, end - hyphen - 1)]];
	*unbound = [text substringFromIndex:end];
}

/* The placeholders of a reading, "{0}" to "{n}", left to right: each
 * @[ its range, its index ]. */
static NSArray<NSArray *> *
ORMPlaceholdersOf(NSString *text)
{
	NSUInteger length = 0;
	unichar *chars = ORMCharactersOf(text ?: @"", &length);
	NSMutableArray *found = [NSMutableArray array];
	for (NSUInteger at = 0; at < length; at++) {
		if (chars[at] != '{') {
			continue;
		}
		NSUInteger digit = at + 1;
		NSUInteger index = 0;
		while (digit < length && chars[digit] >= '0' && chars[digit] <= '9') {
			index = index * 10 + (NSUInteger)(chars[digit] - '0');
			digit++;
		}
		if (digit > at + 1 && digit < length && chars[digit] == '}') {
			[found addObject:@[ [NSValue valueWithRange:NSMakeRange(at, digit + 1 - at)], @(index) ]];
			at = digit;
		}
	}
	free(chars);
	return found;
}

@implementation ORMReadingText

+ (instancetype)readingTextWithString:(NSString *)text arity:(NSUInteger)arity reason:(NSString **)reason
{
	NSArray<NSArray *> *matches = ORMPlaceholdersOf(text);
	NSMutableIndexSet *seen = [NSMutableIndexSet indexSet];
	for (NSArray *match in matches) {
		NSUInteger index = [[match lastObject] unsignedIntegerValue];
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
	for (NSArray *match in matches) {
		NSRange range = [[match firstObject] rangeValue];
		[literals addObject:[text substringWithRange:NSMakeRange(at, range.location - at)]];
		at = NSMaxRange(range);
	}
	[literals addObject:[text substringFromIndex:at]];

	ORMReadingText *reading = [[self alloc] init];
	NSMutableArray *parts = [NSMutableArray array];
	for (NSUInteger i = 0; i < [matches count]; i++) {
		ORMReadingPart *part = [[ORMReadingPart alloc] init];
		part.roleIndex = [[[matches objectAtIndex:i] lastObject] unsignedIntegerValue];
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
		NSString *unbound = literal;
		if (i < [parts count]) {
			ORMSplitPreBound(literal, &unbound, &pre);
		}
		if (i == 0) {
			reading.frontText = unbound;
		} else {
			ORMReadingPart *before = [parts objectAtIndex:i - 1];
			before.postBoundText = post;
			before.followingText = unbound;
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
