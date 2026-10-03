/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFactSentence.h"
#import "ORMReadingText.h"

@interface ORMFactSentencePlayer ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *referenceMode;
@property (nonatomic, readwrite) ORMReferenceModeKind referenceModeKind;
@property (nonatomic, readwrite) BOOL isValueType;
@end

@implementation ORMFactSentencePlayer
@end

@interface ORMFactSentence ()
@property (nonatomic, readwrite, copy) NSArray<ORMFactSentencePlayer *> *players;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *readings;
@property (nonatomic, readwrite, copy) NSArray<NSArray<NSNumber *> *> *readingOrders;
@end

/* One reading taken apart: its text with a placeholder per object type, in
 * order, and the object types. */
@interface ORMParsedReading : NSObject
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, strong) NSMutableArray<ORMFactSentencePlayer *> *players;
@end

@implementation ORMParsedReading
@end

static BOOL
ORMIsNameCharacter(unichar c)
{
	return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c] || c == '_';
}

/* The parentheses after a name: "(.id)", "(kg:)", "(Code)", "()". */
static void
ORMReadMode(NSString *text, NSUInteger *at, ORMFactSentencePlayer *player)
{
	NSUInteger i = *at;
	if (i >= [text length] || [text characterAtIndex:i] != '(') {
		return;
	}
	NSRange close = [text rangeOfString:@")" options:0 range:NSMakeRange(i, [text length] - i)];
	if (close.location == NSNotFound) {
		return;
	}
	NSString *inside = [[text substringWithRange:NSMakeRange(i + 1, close.location - i - 1)]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	*at = NSMaxRange(close);
	if ([inside length] == 0) {
		player.isValueType = YES;
	} else if ([inside hasPrefix:@"."]) {
		player.referenceMode = [inside substringFromIndex:1];
		player.referenceModeKind = ORMReferenceModePopular;
	} else if ([inside hasSuffix:@":"]) {
		player.referenceMode = [inside substringToIndex:[inside length] - 1];
		player.referenceModeKind = ORMReferenceModeUnitBased;
	} else {
		player.referenceMode = inside;
		player.referenceModeKind = ORMReferenceModeGeneral;
	}
}

static ORMParsedReading *
ORMParseReading(NSString *text, NSArray<NSString *> *known)
{
	ORMParsedReading *parsed = [[ORMParsedReading alloc] init];
	parsed.text = [NSMutableString string];
	parsed.players = [NSMutableArray array];
	NSUInteger i = 0;
	NSUInteger length = [text length];
	while (i < length) {
		unichar c = [text characterAtIndex:i];
		BOOL wordStart = i == 0 || !ORMIsNameCharacter([text characterAtIndex:i - 1]);
		ORMFactSentencePlayer *player = nil;
		if (c == '[') {
			NSRange close = [text rangeOfString:@"]" options:0 range:NSMakeRange(i, length - i)];
			if (close.location != NSNotFound) {
				player = [[ORMFactSentencePlayer alloc] init];
				player.name = [[text substringWithRange:NSMakeRange(i + 1, close.location - i - 1)]
					stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				i = NSMaxRange(close);
			}
		} else if (wordStart && ORMIsNameCharacter(c)) {
			/* The longest name the model has that starts here, whole. */
			for (NSString *name in known) {
				if (i + [name length] <= length
				    && [[text substringWithRange:NSMakeRange(i, [name length])] isEqualToString:name]
				    && (i + [name length] == length || !ORMIsNameCharacter([text characterAtIndex:i + [name length]]))) {
					player = [[ORMFactSentencePlayer alloc] init];
					player.name = name;
					i += [name length];
					break;
				}
			}
			if (player == nil) {
				NSUInteger end = i;
				while (end < length && ORMIsNameCharacter([text characterAtIndex:end])) {
					end++;
				}
				BOOL capital = [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c];
				BOOL moded = end < length && [text characterAtIndex:end] == '(';
				if (capital || moded) {
					player = [[ORMFactSentencePlayer alloc] init];
					player.name = [text substringWithRange:NSMakeRange(i, end - i)];
					i = end;
				}
			}
		}
		if (player != nil) {
			ORMReadMode(text, &i, player);
			[parsed.text appendFormat:@"{%lu}", (unsigned long)[parsed.players count]];
			[parsed.players addObject:player];
			continue;
		}
		/* Literal text up to the next word. */
		NSUInteger end = i + 1;
		if (ORMIsNameCharacter(c)) {
			while (end < length && ORMIsNameCharacter([text characterAtIndex:end])) {
				end++;
			}
		}
		[parsed.text appendString:[text substringWithRange:NSMakeRange(i, end - i)]];
		i = end;
	}
	return parsed;
}

@implementation ORMFactSentence

+ (instancetype)sentenceWithString:(NSString *)input model:(ORMModel *)model reason:(NSString **)reason
{
	NSString *text = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([text hasSuffix:@"."]) {
		text = [text substringToIndex:[text length] - 1];
	}
	NSMutableArray *known = [NSMutableArray array];
	for (ORMObjectType *type in [model visibleObjectTypes]) {
		[known addObject:type.name];
	}
	/* Longest first, so "Order Line" wins over "Order". */
	[known sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		return [a length] > [b length] ? NSOrderedAscending : [a length] < [b length] ? NSOrderedDescending
		                                                                            : NSOrderedSame;
	}];
	NSArray *parts = [text componentsSeparatedByString:@"/"];
	ORMParsedReading *first = ORMParseReading([[parts firstObject] stringByTrimmingCharactersInSet:
	                                                                   [NSCharacterSet whitespaceCharacterSet]], known);
	if ([first.players count] == 0) {
		if (reason != NULL) {
			*reason = @"No object type in the sentence: capitalize them, or write Name(.id), Name() or [Two Words].";
		}
		return nil;
	}
	NSString *words = [[first.text componentsSeparatedByCharactersInSet:[[NSCharacterSet letterCharacterSet] invertedSet]]
		componentsJoinedByString:@""];
	if ([words length] == 0) {
		if (reason != NULL) {
			*reason = @"The sentence has no words between its object types to read as a predicate.";
		}
		return nil;
	}
	ORMFactSentence *sentence = [[self alloc] init];
	sentence.players = first.players;
	NSMutableArray *readings = [NSMutableArray arrayWithObject:[first.text
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	NSMutableArray *orders = [NSMutableArray array];
	NSMutableArray *identity = [NSMutableArray array];
	for (NSUInteger i = 0; i < [first.players count]; i++) {
		[identity addObject:@(i)];
	}
	[orders addObject:identity];
	for (NSUInteger p = 1; p < [parts count]; p++) {
		ORMParsedReading *other = ORMParseReading([[parts objectAtIndex:p] stringByTrimmingCharactersInSet:
		                                                                       [NSCharacterSet whitespaceCharacterSet]], known);
		if ([other.players count] != [first.players count]) {
			if (reason != NULL) {
				*reason = [NSString stringWithFormat:@"Reading %lu names %lu object types; the first names %lu.",
				           (unsigned long)p + 1, (unsigned long)[other.players count],
				           (unsigned long)[first.players count]];
			}
			return nil;
		}
		/* Each name's k-th use is the role of its k-th use in the first. */
		NSMutableArray *order = [NSMutableArray array];
		NSMutableDictionary *used = [NSMutableDictionary dictionary];
		for (ORMFactSentencePlayer *player in other.players) {
			NSUInteger seen = [[used objectForKey:player.name] unsignedIntegerValue];
			NSUInteger found = NSNotFound;
			NSUInteger count = 0;
			for (NSUInteger i = 0; i < [first.players count]; i++) {
				if ([[[first.players objectAtIndex:i] name] isEqualToString:player.name] && count++ == seen) {
					found = i;
					break;
				}
			}
			if (found == NSNotFound) {
				if (reason != NULL) {
					*reason = [NSString stringWithFormat:@"%@ is not in the first reading.", player.name];
				}
				return nil;
			}
			[used setObject:@(seen + 1) forKey:player.name];
			[order addObject:@(found)];
		}
		[orders addObject:order];
		[readings addObject:[other.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	}
	sentence.readings = readings;
	sentence.readingOrders = orders;
	return sentence;
}

@end

@implementation ORMEditor (ORMFactSentences)

- (NSString *)addFactTypeFromSentence:(NSString *)text
                            onDiagram:(NSString *)diagramId
                                   at:(NSPoint)point
                               reason:(NSString **)reason
{
	ORMFactSentence *sentence = [ORMFactSentence sentenceWithString:text model:self.model reason:reason];
	if (sentence == nil) {
		return nil;
	}
	if ([sentence.players count] > 1) {
		for (NSString *reading in sentence.readings) {
			if ([ORMReadingText readingTextWithString:reading arity:[sentence.players count] reason:reason] == nil) {
				return nil;
			}
		}
	}
	__block NSString *created = nil;
	__block NSString *failure = nil;
	[self group:@"Add Fact Type" with:^{
		NSMutableDictionary *ids = [NSMutableDictionary dictionary];
		for (ORMFactSentencePlayer *player in sentence.players) {
			if ([ids objectForKey:player.name] != nil) {
				continue;
			}
			ORMObjectType *existing = [self.model objectTypeNamed:player.name];
			NSString *identifier = existing.identifier;
			NSString *why = nil;
			if (identifier == nil && player.isValueType) {
				identifier = [self addValueTypeNamed:player.name dataType:nil onDiagram:diagramId
				                                  at:ORMAutomaticPlacement reason:&why];
			} else if (identifier == nil) {
				identifier = [self addEntityTypeNamed:player.name referenceMode:player.referenceMode
				                                 kind:player.referenceMode != nil ? player.referenceModeKind
				                                                                  : ORMReferenceModeNone
				                            onDiagram:diagramId at:ORMAutomaticPlacement reason:&why];
			}
			if (identifier == nil) {
				failure = why;
				return;
			}
			[ids setObject:identifier forKey:player.name];
		}
		NSMutableArray *players = [NSMutableArray array];
		for (ORMFactSentencePlayer *player in sentence.players) {
			[players addObject:[ids objectForKey:player.name]];
		}
		NSString *why = nil;
		created = [self addFactTypeWithPlayers:players reading:[sentence.readings firstObject] onDiagram:diagramId
		                                    at:point reason:&why];
		if (created == nil) {
			failure = why;
			return;
		}
		NSArray *roles = [[self.model elementWithId:created] roles];
		for (NSUInteger r = 1; r < [sentence.readings count]; r++) {
			NSMutableArray *order = [NSMutableArray array];
			for (NSNumber *index in [sentence.readingOrders objectAtIndex:r]) {
				[order addObject:[[roles objectAtIndex:[index unsignedIntegerValue]] identifier]];
			}
			[self addReading:[sentence.readings objectAtIndex:r] forRoles:order reason:NULL];
		}
	}];
	if (failure != nil) {
		if (reason != NULL) {
			*reason = failure;
		}
		return nil;
	}
	return created;
}

@end
