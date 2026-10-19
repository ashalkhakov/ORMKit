/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMOutlineReader.h"
#import "ORMQuery.h"

/* What a node says in the outline: ✓, its label, its condition, its sort. */
@interface ORMOutlineNode : NSObject
@property (nonatomic) BOOL projected;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *comparison;
@property (nonatomic, copy) NSString *value;
@property (nonatomic) ORMQuerySort sort;
@end

@implementation ORMOutlineNode
@end

@class ORMOutlineToken;

/* A line: its depth (two spaces each), what it says, and its tokens. */
@interface ORMOutlineLine : NSObject
@property (nonatomic) NSUInteger number;
@property (nonatomic) NSUInteger depth;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<ORMOutlineToken *> *tokens;
@end

@implementation ORMOutlineLine
@end

/* What the first line says the query is for, where it says. */
@interface ORMOutlineHeader : NSObject
@property (nonatomic) ORMQueryKind kind;
@property (nonatomic) BOOL deontic;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *function;
@property (nonatomic, copy) NSString *calculated;
@property (nonatomic, strong) ORMFactType *derived;
@property (nonatomic, strong) ORMObjectType *subtype;
@property (nonatomic, strong) ORMOutlineLine *line;
@end

@implementation ORMOutlineHeader
@end

#pragma mark Tokens

/* An outline line is read as RDLKit reads an expression: lexed once into
 * tokens, from a buffer of its characters, and the tokens matched. Spaces
 * part tokens and are not tokens; what is taken as typed (a value, a list,
 * an expression) is the line's text between tokens' ranges. */

typedef NS_ENUM(NSInteger, ORMOutlineTokenKind) {
	/* Letters, digits and underscores, a point between digits: "City1",
	 * "was", "3.5". */
	ORMOutlineWord,
	/* A value in single quotes, as typed: "'O''Brien'". */
	ORMOutlineQuoted,
	/* A reading in double quotes, its text without them. */
	ORMOutlineReading,
	/* Any other character; a comparison of two whole: "✓", "(", "<=". */
	ORMOutlineSymbol,
};

@interface ORMOutlineToken : NSObject
@property (nonatomic) ORMOutlineTokenKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSRange range;
@end

@implementation ORMOutlineToken
@end

static BOOL
ORMIsWordCharacter(unichar c)
{
	static NSCharacterSet *letters;
	if (letters == nil) {
		letters = [NSCharacterSet alphanumericCharacterSet];
	}
	return c == '_' || [letters characterIsMember:c];
}

static void
ORMAddToken(NSMutableArray *tokens, NSString *text, ORMOutlineTokenKind kind, NSUInteger start, NSUInteger end, NSString *as)
{
	ORMOutlineToken *token = [[ORMOutlineToken alloc] init];
	token.kind = kind;
	token.range = NSMakeRange(start, end - start);
	token.text = as ?: [text substringWithRange:token.range];
	[tokens addObject:token];
}

static BOOL ORMIsComparison(ORMOutlineToken *token);

/* The text's tokens. A single quote opens a value only where one can
 * start, after a comparison, "(" or ","; elsewhere, and everywhere in a
 * reading (values NO), it is a symbol: "{1}'s father". */
static NSArray<ORMOutlineToken *> *
ORMOutlineLex(NSString *text, BOOL values)
{
	NSUInteger n = [text length];
	unichar *c = malloc(sizeof(unichar) * (n + 1));
	[text getCharacters:c range:NSMakeRange(0, n)];
	NSMutableArray *tokens = [NSMutableArray array];
	NSUInteger i = 0;
	while (i < n) {
		NSUInteger start = i;
		if (c[i] == ' ' || c[i] == '\t') {
			i++;
		} else if (ORMIsWordCharacter(c[i])) {
			while (i < n && (ORMIsWordCharacter(c[i])
			                 || (c[i] == '.' && i + 1 < n && i > start && c[i + 1] >= '0' && c[i + 1] <= '9'
			                     && c[i - 1] >= '0' && c[i - 1] <= '9'))) {
				i++;
			}
			ORMAddToken(tokens, text, ORMOutlineWord, start, i, nil);
		} else if (c[i] == '\'' && values
		           && (ORMIsComparison([tokens lastObject]) || [[[tokens lastObject] text] isEqualToString:@"("]
		               || [[[tokens lastObject] text] isEqualToString:@","])) {
			/* To the closing quote, a doubled one in it; to the end where
			 * none closes it. */
			for (i++; i < n; i++) {
				if (c[i] == '\'' && i + 1 < n && c[i + 1] == '\'') {
					i++;
				} else if (c[i] == '\'') {
					i++;
					break;
				}
			}
			ORMAddToken(tokens, text, ORMOutlineQuoted, start, i, nil);
		} else if (c[i] == '"' && values) {
			for (i++; i < n && c[i] != '"'; i++) {
			}
			NSUInteger close = i;
			i = i < n ? i + 1 : i;
			ORMAddToken(tokens, text, ORMOutlineReading, start, i,
			            [text substringWithRange:NSMakeRange(start + 1, close - start - 1)]);
		} else {
			BOOL pair = i + 1 < n && ((c[i] == '<' && (c[i + 1] == '>' || c[i + 1] == '=')) || (c[i] == '>' && c[i + 1] == '='));
			i += pair ? 2 : 1;
			ORMAddToken(tokens, text, ORMOutlineSymbol, start, i, nil);
		}
	}
	free(c);
	return tokens;
}

/* The token at the position, there, its text the one given: read. */
static BOOL
ORMNext(NSArray<ORMOutlineToken *> *tokens, NSUInteger *at, NSString *text)
{
	if (*at < [tokens count] && [[[tokens objectAtIndex:*at] text] isEqualToString:text]) {
		(*at)++;
		return YES;
	}
	return NO;
}

/* The line's text from the start of one token to the end of the one
 * before another: what it says there, as typed. */
static NSString *
ORMSource(NSString *text, NSArray<ORMOutlineToken *> *tokens, NSUInteger from, NSUInteger to)
{
	if (from >= to || to > [tokens count]) {
		return nil;
	}
	NSUInteger start = [[tokens objectAtIndex:from] range].location;
	return [text substringWithRange:NSMakeRange(start, NSMaxRange([[tokens objectAtIndex:to - 1] range]) - start)];
}

/* A comparison token: "<>", "<=", ">=", "=", "<", ">". */
static BOOL
ORMIsComparison(ORMOutlineToken *token)
{
	return token.kind == ORMOutlineSymbol && [@[ @"<>", @"<=", @">=", @"=", @"<", @">" ] containsObject:token.text];
}

/* The tokens from the position that touch one another, no space between:
 * how far a value typed bare runs ("-5", "2026-10-01"). */
static NSUInteger
ORMAdjacentEnd(NSArray<ORMOutlineToken *> *tokens, NSUInteger from)
{
	NSUInteger end = from + 1;
	while (end < [tokens count]
	       && [[tokens objectAtIndex:end] range].location == NSMaxRange([[tokens objectAtIndex:end - 1] range])) {
		end++;
	}
	return end;
}

/* An object type's name, as words: what a node's name is matched by. */
static NSArray<NSString *> *
ORMNameWords(NSString *name)
{
	NSMutableArray *words = [NSMutableArray array];
	for (ORMOutlineToken *token in ORMOutlineLex(name ?: @"", NO)) {
		[words addObject:token.text];
	}
	return words;
}

/* A node named so from the position: "✓", the name's words, its label's
 * digits after the last, " comparison value" (a list after "in", a quoted
 * value or what is typed bare after the others), "↑" or "↓". With
 * conditional NO, no condition is read: what looked like one is the
 * reading's own words. nil where no node of the name is there. */
static ORMOutlineNode *
ORMTakeNode(NSString *text, NSArray<ORMOutlineToken *> *tokens, NSUInteger *at, NSArray<NSString *> *name, BOOL conditional)
{
	NSUInteger i = *at, n = [tokens count];
	ORMOutlineNode *node = [[ORMOutlineNode alloc] init];
	node.projected = ORMNext(tokens, &i, @"✓");
	for (NSUInteger k = 0; k < [name count]; k++) {
		ORMOutlineToken *token = i < n ? [tokens objectAtIndex:i] : nil;
		NSString *word = [name objectAtIndex:k];
		if (token.kind != ORMOutlineWord || ![token.text hasPrefix:word]) {
			return nil;
		}
		NSString *label = [token.text substringFromIndex:[word length]];
		if ([label length] > 0 && (k + 1 < [name count]
		                           || [label rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location
		                                  != NSNotFound)) {
			return nil;
		}
		node.label = [label length] > 0 ? label : nil;
		i++;
	}
	if ([name count] == 0) {
		return nil;
	}
	ORMOutlineToken *next = i < n ? [tokens objectAtIndex:i] : nil;
	if (conditional && next.kind == ORMOutlineWord && [next.text isEqualToString:@"in"] && i + 1 < n
	    && [[[tokens objectAtIndex:i + 1] text] isEqualToString:@"("]) {
		NSUInteger close = i + 2;
		while (close < n && ![[[tokens objectAtIndex:close] text] isEqualToString:@")"]) {
			close++;
		}
		if (close < n) {
			node.comparison = @"in";
			node.value = ORMSource(text, tokens, i + 1, close + 1);
			i = close + 1;
		}
	} else if (conditional && ORMIsComparison(next) && i + 1 < n) {
		ORMOutlineToken *value = [tokens objectAtIndex:i + 1];
		NSUInteger end = value.kind == ORMOutlineQuoted ? i + 2 : ORMAdjacentEnd(tokens, i + 1);
		if (end > i + 1) {
			node.comparison = next.text;
			node.value = ORMSource(text, tokens, i + 1, end);
			i = end;
		}
	}
	if (ORMNext(tokens, &i, @"↑")) {
		node.sort = ORMQueryAscending;
	} else if (ORMNext(tokens, &i, @"↓")) {
		node.sort = ORMQueryDescending;
	}
	*at = i;
	return node;
}

/* A value node's line, "✓Length: Distance = Quantity2 - Quantity1 > 100 ↓":
 * whether it is ticked, its name, its type's name (nil where not given),
 * its expression, and what it says of the value. NO where it is none. */
static BOOL
ORMReadValueLine(ORMOutlineLine *line, NSString **name, NSString **typeName, NSString **expression, ORMOutlineNode *said)
{
	NSArray *tokens = line.tokens;
	NSString *text = line.text;
	NSUInteger at = 0, n = [tokens count];
	BOOL projected = ORMNext(tokens, &at, @"✓");
	ORMOutlineToken *first = at < n ? [tokens objectAtIndex:at] : nil;
	if (first.kind != ORMOutlineWord || [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[first.text characterAtIndex:0]]) {
		return NO;
	}
	at++;
	NSUInteger equals = at;
	if (ORMNext(tokens, &equals, @":")) {
		NSUInteger typeStart = equals;
		while (equals < n && ![[[tokens objectAtIndex:equals] text] isEqualToString:@"="]) {
			equals++;
		}
		if (equals == typeStart || equals >= n) {
			return NO;
		}
		*typeName = ORMSource(text, tokens, typeStart, equals);
	} else {
		*typeName = nil;
	}
	if (!ORMNext(tokens, &equals, @"=") || equals >= n) {
		return NO;
	}
	*name = first.text;
	if (said == nil) {
		return YES;
	}
	said.projected = projected;
	/* The expression, to the first comparison outside parentheses; the
	 * sort last. */
	NSUInteger end = n;
	if ([[[tokens lastObject] text] isEqualToString:@"↑"] || [[[tokens lastObject] text] isEqualToString:@"↓"]) {
		said.sort = [[[tokens lastObject] text] isEqualToString:@"↑"] ? ORMQueryAscending : ORMQueryDescending;
		end = n - 1;
	}
	NSInteger depth = 0;
	for (NSUInteger i = equals; i < end; i++) {
		ORMOutlineToken *token = [tokens objectAtIndex:i];
		depth += [token.text isEqualToString:@"("] ? 1 : [token.text isEqualToString:@")"] ? -1 : 0;
		if (depth == 0 && ORMIsComparison(token) && i > equals && i + 1 < end) {
			said.comparison = token.text;
			said.value = ORMSource(text, tokens, i + 1, end);
			end = i;
			break;
		}
	}
	*expression = ORMSource(text, tokens, equals, end);
	return *expression != nil;
}

static BOOL
ORMIsValueLine(ORMOutlineLine *line)
{
	NSString *name = nil, *typeName = nil, *expression = nil;
	return ![[[line.tokens firstObject] text] isEqualToString:@"+"] && ![line.text hasSuffix:@":"]
		&& ORMReadValueLine(line, &name, &typeName, &expression, nil);
}

static NSArray<NSString *> *
ORMAggregateNames(void)
{
	return @[ @"count", @"total", @"avg", @"max", @"min" ];
}

/* An aggregate from the position, "count(Language)": its function and
 * what it is of, as typed; NO where none is there. */
static BOOL
ORMTakeAggregate(NSString *text, NSArray<ORMOutlineToken *> *tokens, NSUInteger *at, NSString **function, NSString **of)
{
	NSUInteger i = *at, n = [tokens count];
	ORMOutlineToken *name = i < n ? [tokens objectAtIndex:i] : nil;
	if (![ORMAggregateNames() containsObject:name.text ?: @""] || !(i + 1 < n)
	    || ![[[tokens objectAtIndex:i + 1] text] isEqualToString:@"("]) {
		return NO;
	}
	NSUInteger close = i + 2;
	while (close < n && ![[[tokens objectAtIndex:close] text] isEqualToString:@")"]) {
		close++;
	}
	if (close >= n || close == i + 2) {
		return NO;
	}
	*function = name.text;
	*of = ORMSource(text, tokens, i + 2, close);
	*at = close + 1;
	return YES;
}

/* Whether the line is a step's aggregate: "+ count(Language) ...". */
static BOOL
ORMIsAggregateLine(ORMOutlineLine *line)
{
	NSUInteger at = 0;
	NSString *function = nil, *of = nil;
	return ORMNext(line.tokens, &at, @"+") && ORMTakeAggregate(line.text, line.tokens, &at, &function, &of);
}

/* A reading's parts: its words (each token's text), and its places ({0},
 * {1} ...) as numbers. */
static NSArray *
ORMReadingParts(NSString *reading, NSUInteger places)
{
	NSArray<ORMOutlineToken *> *tokens = ORMOutlineLex(reading, NO);
	NSMutableArray *parts = [NSMutableArray array];
	for (NSUInteger i = 0; i < [tokens count]; i++) {
		ORMOutlineToken *token = [tokens objectAtIndex:i];
		ORMOutlineToken *digits = i + 2 < [tokens count] ? [tokens objectAtIndex:i + 1] : nil;
		if ([token.text isEqualToString:@"{"] && digits.kind == ORMOutlineWord
		    && [[[tokens objectAtIndex:i + 2] text] isEqualToString:@"}"] && (NSUInteger)[digits.text integerValue] <= places
		    && [digits.text rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
			[parts addObject:@([digits.text integerValue])];
			i += 2;
		} else {
			[parts addObject:token.text];
		}
	}
	return parts;
}

/* What a step's tokens read as from its node, along the reading's parts:
 * each a word, the node above ("that City", @0), or a node of the step (@n,
 * the nth player's name), read on from the position to the end; what is
 * said of each node put in nodes. Where what a node says as a condition
 * leaves the rest unread, it is read again as the reading's own words. */
static BOOL
ORMMatchParts(NSString *text, NSArray<ORMOutlineToken *> *tokens, NSUInteger at, NSArray *parts, NSUInteger index,
              NSArray<NSArray<NSString *> *> *players, NSArray<NSString *> *above, NSMutableArray *nodes)
{
	if (index == [parts count]) {
		return at == [tokens count];
	}
	id part = [parts objectAtIndex:index];
	if ([part isKindOfClass:[NSString class]]) {
		return ORMNext(tokens, &at, part) && ORMMatchParts(text, tokens, at, parts, index + 1, players, above, nodes);
	}
	NSUInteger place = [part unsignedIntegerValue];
	if (place == 0) {
		if (!ORMNext(tokens, &at, @"that")) {
			return NO;
		}
		for (NSString *word in above) {
			if (!ORMNext(tokens, &at, word)) {
				return NO;
			}
		}
		return ORMMatchParts(text, tokens, at, parts, index + 1, players, above, nodes);
	}
	for (NSNumber *conditional in @[ @YES, @NO ]) {
		NSUInteger from = at;
		ORMOutlineNode *node = ORMTakeNode(text, tokens, &from, [players objectAtIndex:place - 1], [conditional boolValue]);
		if (node != nil && ORMMatchParts(text, tokens, from, parts, index + 1, players, above, nodes)) {
			[nodes replaceObjectAtIndex:place - 1 withObject:node];
			return YES;
		}
	}
	return NO;
}

@implementation ORMOutlineReader
{
	ORMQueryEditor *_queries;
	NSString *_query;
	NSArray<ORMOutlineLine *> *_lines;
	NSString *_failure;
	/* Conditions comparing with another node, once every node is made:
	 * @[ node id, comparison, designation, line ]. */
	NSMutableArray<NSArray *> *_comparisons;
	/* Value nodes, once every step is made: @[ node id, line ]. */
	NSMutableArray<NSArray *> *_values;
	ORMOutlineHeader *_header;
}

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
		_queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	}
	return self;
}

- (BOOL)fail:(NSString *)why line:(ORMOutlineLine *)line
{
	if (_failure == nil) {
		_failure = line != nil ? [NSString stringWithFormat:@"Line %lu, \"%@\": %@", (unsigned long)line.number, line.text, why]
		                       : why;
	}
	return NO;
}

- (ORMQuery *)query
{
	return [ORMQuery queryWithId:_query inModel:_editor.model];
}

/* A node, of a query read for it: its links up are not to be followed. */
- (ORMQueryNode *)node:(NSString *)nodeId
{
	for (ORMQueryNode *node in [[self query] nodes]) {
		if ([node.identifier isEqualToString:nodeId]) {
			return node;
		}
	}
	return nil;
}

/* The nodes below the node, it included. */
- (NSArray<ORMQueryNode *> *)subtreeOf:(ORMQueryNode *)node
{
	NSMutableArray *all = [NSMutableArray arrayWithObject:node];
	for (ORMQueryStep *step in node.steps) {
		for (ORMQueryNode *child in step.nodes) {
			[all addObjectsFromArray:[self subtreeOf:child]];
		}
	}
	return all;
}

#pragma mark Nodes

/* What the outline says of the node, given it. */
- (BOOL)apply:(ORMOutlineNode *)said to:(NSString *)nodeId line:(ORMOutlineLine *)line
{
	[_queries setProjected:said.projected ofNode:nodeId];
	if (said.label != nil) {
		[_queries setLabel:said.label ofNode:nodeId];
	}
	if (said.sort != ORMQueryUnsorted) {
		[_queries setSortOrder:said.sort ofNode:nodeId];
	}
	if (said.comparison == nil) {
		return YES;
	}
	NSString *value = said.value;
	if ([said.comparison isEqualToString:@"in"]) {
		/* One of a list: what is between its parentheses. */
		value = [value hasPrefix:@"("] && [value hasSuffix:@")"] ? [value substringWithRange:NSMakeRange(1, [value length] - 2)]
		                                                         : value;
	} else if ([value hasPrefix:@"'"] && [value hasSuffix:@"'"] && [value length] >= 2) {
		/* Quoted, a quote in it doubled: "'O''Brien'". */
		value = [[value substringWithRange:NSMakeRange(1, [value length] - 2)] stringByReplacingOccurrencesOfString:@"''"
		                                                                                                withString:@"'"];
	} else if ([value length] > 0 && [[NSCharacterSet letterCharacterSet] characterIsMember:[value characterAtIndex:0]]) {
		/* Another node, its designation: "Country2 <> Country1", "Moment3 =
		 * Previous". A value is quoted where it is not a number. */
		[_comparisons addObject:@[ nodeId, said.comparison, value, line ]];
		return YES;
	}
	NSString *why = nil;
	if (![_queries setCondition:said.comparison value:value ofNode:nodeId reason:&why]) {
		return [self fail:why ?: @"the condition cannot be set" line:line];
	}
	return YES;
}

#pragma mark Value nodes

/* "✓Length = Quantity2 - Quantity1 > 100": the value node, under the node,
 * and what the line says of it. */
- (BOOL)value:(ORMOutlineLine *)line of:(NSString *)nodeId
{
	ORMOutlineNode *said = [[ORMOutlineNode alloc] init];
	NSString *name = nil, *typeName = nil, *expression = nil;
	if (!ORMReadValueLine(line, &name, &typeName, &expression, said)) {
		return [self fail:@"a value is \"Name = expression\"" line:line];
	}
	ORMObjectType *type = typeName != nil ? [_editor.model objectTypeNamed:typeName] : nil;
	if (typeName != nil && type == nil) {
		return [self fail:[NSString stringWithFormat:@"no object type of the model is named %@", typeName] line:line];
	}
	NSString *why = nil;
	NSString *valueId = [_queries addValueNamed:name to:nodeId expression:expression type:type.identifier reason:&why];
	if (valueId == nil) {
		return [self fail:why ?: @"the value cannot be made" line:line];
	}
	[_queries setProjected:said.projected ofNode:valueId];
	if (said.sort != ORMQueryUnsorted) {
		[_queries setSortOrder:said.sort ofNode:valueId];
	}
	if (said.comparison == nil) {
		return YES;
	}
	NSString *value = said.value;
	if ([value hasPrefix:@"'"] && [value hasSuffix:@"'"] && [value length] >= 2) {
		value = [[value substringWithRange:NSMakeRange(1, [value length] - 2)] stringByReplacingOccurrencesOfString:@"''"
		                                                                                                withString:@"'"];
	} else if ([value length] > 0 && [[NSCharacterSet letterCharacterSet] characterIsMember:[value characterAtIndex:0]]) {
		/* Another node, by its designation: "Length < Length2". */
		[_comparisons addObject:@[ valueId, said.comparison, value, line ]];
		return YES;
	}
	if (![_queries setCondition:said.comparison value:value ofNode:valueId reason:&why]) {
		return [self fail:why ?: @"the condition cannot be set" line:line];
	}
	return YES;
}

#pragma mark Steps

/* The step the line's tokens read from the position, from the node: the
 * role it enters by, and what the outline says of each of its nodes. */
- (ORMRole *)readStep:(ORMOutlineLine *)line at:(NSUInteger)start from:(ORMQueryNode *)node nodes:(NSArray<ORMOutlineNode *> **)said
{
	NSArray *above = ORMNameWords(node.objectType.name);
	ORMRole *found = nil;
	NSArray *foundNodes = nil;
	for (ORMRole *entry in [ORMQuery rolesFrom:node.objectType]) {
		NSArray *roles = [ORMQuery nodeRolesFrom:entry];
		NSString *reading = [ORMQuery readingFrom:entry nodeRoles:roles];
		if ([reading length] == 0) {
			continue;
		}
		NSMutableArray *players = [NSMutableArray array];
		NSMutableArray *nodes = [NSMutableArray array];
		for (ORMRole *role in roles) {
			[players addObject:ORMNameWords(role.player.name)];
			[nodes addObject:[[ORMOutlineNode alloc] init]];
		}
		if (!ORMMatchParts(line.text, line.tokens, start, ORMReadingParts(reading, [roles count]), 0, players, above, nodes)) {
			continue;
		}
		/* The longest reading that matches: "has" is less than "has as
		 * owner". */
		if (found == nil || [reading length] > [[ORMQuery readingFrom:found nodeRoles:[ORMQuery nodeRolesFrom:found]] length]) {
			found = entry;
			foundNodes = nodes;
		}
	}
	*said = foundNodes;
	return found;
}

/* A step line and what is under it; the line after them. */
- (NSUInteger)step:(NSUInteger)index from:(NSString *)nodeId first:(BOOL)first
{
	ORMOutlineLine *line = [_lines objectAtIndex:index];
	NSUInteger at = 0;
	ORMNext(line.tokens, &at, @"+");
	if (ORMNext(line.tokens, &at, @"or")) {
		if (first) {
			[self fail:@"the first step is no alternative" line:line];
			return NSNotFound;
		}
		[_queries setCombinesWithOr:YES ofNode:nodeId];
	}
	ORMQueryOperator operatorKind = ORMQueryAnd;
	if (ORMNext(line.tokens, &at, @"not")) {
		operatorKind = ORMQueryNot;
	} else if (ORMNext(line.tokens, &at, @"maybe")) {
		operatorKind = ORMQueryMaybe;
	}
	ORMQuery *query = [self query];
	ORMQueryNode *node = nil;
	for (ORMQueryNode *each in [query nodes]) {
		node = [each.identifier isEqualToString:nodeId] ? each : node;
	}
	NSArray<ORMOutlineNode *> *said = nil;
	ORMRole *entry = [self readStep:line at:at from:node nodes:&said];
	if (entry == nil) {
		[self fail:[NSString stringWithFormat:@"no fact type of %@ reads so", node.objectType.name ?: @"it"] line:line];
		return NSNotFound;
	}
	NSString *why = nil;
	NSString *stepId = [_queries addStepTo:nodeId through:entry.identifier reason:&why];
	if (stepId == nil) {
		[self fail:why ?: @"the step cannot be made" line:line];
		return NSNotFound;
	}
	if (operatorKind != ORMQueryAnd) {
		[_queries setOperator:operatorKind ofStep:stepId];
	}
	query = [self query];
	NSMutableArray *children = [NSMutableArray array];
	for (ORMQueryNode *each in [query nodes]) {
		if ([each.step.identifier isEqualToString:stepId]) {
			[children addObject:each];
		}
	}
	for (NSUInteger i = 0; i < [children count] && i < [said count]; i++) {
		if (![self apply:[said objectAtIndex:i] to:[[children objectAtIndex:i] identifier] line:line]) {
			return NSNotFound;
		}
	}
	/* Under it: its aggregate, its nodes' steps. */
	NSUInteger next = index + 1;
	NSString *current = [[children firstObject] identifier];
	NSMutableArray *aggregates = [NSMutableArray array];
	while (next < [_lines count] && [[_lines objectAtIndex:next] depth] == line.depth + 1) {
		ORMOutlineLine *under = [_lines objectAtIndex:next];
		if (ORMIsAggregateLine(under)) {
			[aggregates addObject:under];
			next++;
		} else if ([under.text hasSuffix:@":"] && ![under.text hasPrefix:@"+ "]) {
			current = [self childNamed:under among:children];
			if (current == nil) {
				[self fail:@"the step has no such node" line:under];
				return NSNotFound;
			}
			next++;
		} else if ([under.text hasPrefix:@"+ "] || ORMIsValueLine(under)) {
			next = [self steps:next from:current];
			if (next == NSNotFound) {
				return NSNotFound;
			}
		} else {
			[self fail:@"neither a step, an aggregate, a value nor a node's name" line:under];
			return NSNotFound;
		}
	}
	for (ORMOutlineLine *aggregate in aggregates) {
		if (![self aggregate:aggregate ofStep:stepId]) {
			return NSNotFound;
		}
	}
	return next;
}

/* The step lines at the depth, from the node; the line after them. */
- (NSUInteger)steps:(NSUInteger)index from:(NSString *)nodeId
{
	NSUInteger depth = [[_lines objectAtIndex:index] depth];
	BOOL first = YES;
	while (index < [_lines count]) {
		ORMOutlineLine *line = [_lines objectAtIndex:index];
		/* A value node of the node: made once every step is. */
		if (line.depth == depth && ORMIsValueLine(line)) {
			[_values addObject:@[ nodeId, line ]];
			index++;
			continue;
		}
		if (line.depth != depth || ![line.text hasPrefix:@"+ "] || ORMIsAggregateLine(line)) {
			break;
		}
		index = [self step:index from:nodeId first:first];
		if (index == NSNotFound) {
			return NSNotFound;
		}
		first = NO;
	}
	return index;
}

#pragma mark Aggregates

/* The node of the designation among those given. */
- (ORMQueryNode *)designated:(NSString *)designation among:(NSArray<ORMQueryNode *> *)nodes
{
	for (ORMQueryNode *node in nodes) {
		if ([[node designation] isEqualToString:designation]) {
			return node;
		}
	}
	return nil;
}

/* "+ count(Language) for Branch > 1", "+ max(Salary) for Employee > avg(Salary) for Branch". */
- (BOOL)aggregate:(ORMOutlineLine *)line ofStep:(NSString *)stepId
{
	/* "+ count(Language) for Branch > 1": the group runs to the first
	 * comparison. */
	NSString *text = line.text;
	NSArray *tokens = line.tokens;
	NSUInteger at = 0, compared = 0;
	NSString *function = nil, *ofName = nil, *groupName = nil, *comparison = nil;
	if (ORMNext(tokens, &at, @"+") && ORMTakeAggregate(text, tokens, &at, &function, &ofName) && ORMNext(tokens, &at, @"for")) {
		for (NSUInteger i = at + 1; i + 1 < [tokens count] && comparison == nil; i++) {
			if (ORMIsComparison([tokens objectAtIndex:i])) {
				groupName = ORMSource(text, tokens, at, i);
				comparison = [[tokens objectAtIndex:i] text];
				compared = i + 1;
			}
		}
	}
	if (comparison == nil) {
		return [self fail:@"an aggregate is \"count(X) for Y > n\"" line:line];
	}
	/* Held while its nodes are walked: their links up are weak. */
	ORMQuery *query = [self query];
	ORMQueryStep *step = nil;
	for (ORMQueryNode *node in [query nodes]) {
		for (ORMQueryStep *each in node.steps) {
			step = [each.identifier isEqualToString:stepId] ? each : step;
		}
	}
	NSMutableArray *below = [NSMutableArray array];
	for (ORMQueryNode *child in step.nodes) {
		[below addObjectsFromArray:[self subtreeOf:child]];
	}
	NSMutableArray *above = [NSMutableArray array];
	for (ORMQueryNode *at = step.parent; at != nil; at = at.step.parent) {
		[above addObject:at];
	}
	ORMQueryNode *of = [self designated:ofName among:below];
	ORMQueryNode *group3 = [self designated:groupName among:above];
	if (of == nil || group3 == nil) {
		return [self fail:@"what it aggregates is not below the step, or what it is for not above it" line:line];
	}
	ORMQueryAggregate aggregate = (ORMQueryAggregate)[ORMAggregateNames() indexOfObject:function];
	/* Compared with another aggregate: "max(Rating) for Department". */
	NSUInteger restAt = compared;
	NSString *otherName = nil, *otherOf = nil;
	BOOL aggregated = ORMTakeAggregate(text, tokens, &restAt, &otherName, &otherOf) && ORMNext(tokens, &restAt, @"for")
		&& restAt < [tokens count];
	NSString *rest = ORMSource(text, tokens, compared, [tokens count]);
	NSString *why = nil;
	if (![_queries setAggregate:aggregate ofNode:of.identifier comparison:comparison value:aggregated ? @"0" : rest
	                     ofStep:stepId reason:&why]) {
		return [self fail:why ?: @"the aggregate cannot be set" line:line];
	}
	if (group3 != step.parent && ![_queries setGroupNode:group3.identifier ofStep:stepId reason:&why]) {
		return [self fail:why ?: @"the aggregate cannot be for that" line:line];
	}
	if (aggregated) {
		ORMQueryNode *otherGroup = [self designated:ORMSource(text, tokens, restAt, [tokens count]) among:above];
		if (otherGroup == nil || ![otherOf isEqualToString:ofName]) {
			return [self fail:@"an aggregate is compared with one of the same node, for a node above" line:line];
		}
		if (![_queries setComparedAggregate:(ORMQueryAggregate)[ORMAggregateNames() indexOfObject:otherName]
		                              group:otherGroup.identifier ofStep:stepId reason:&why]) {
			return [self fail:why ?: @"the aggregates cannot be compared" line:line];
		}
	}
	return YES;
}

/* The step's node the outline names: "Employee", or "Employee (2)" the
 * second of its type. nil where there is none. */
- (NSString *)childNamed:(ORMOutlineLine *)line among:(NSArray<ORMQueryNode *> *)children
{
	/* "Employee (2):": its name, the number in parentheses, the colon. */
	NSArray *tokens = line.tokens;
	NSUInteger end = [tokens count] - 1;
	NSUInteger which = 1;
	ORMOutlineToken *digits = end >= 3 ? [tokens objectAtIndex:end - 2] : nil;
	if (digits.kind == ORMOutlineWord && [[[tokens objectAtIndex:end - 3] text] isEqualToString:@"("]
	    && [[[tokens objectAtIndex:end - 1] text] isEqualToString:@")"]
	    && [digits.text rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
		which = (NSUInteger)[digits.text integerValue];
		end -= 3;
	}
	NSString *name = ORMSource(line.text, tokens, 0, end);
	NSUInteger seen = 0;
	for (ORMQueryNode *child in children) {
		if ([child.objectType.name isEqualToString:name] && ++seen == which) {
			return child.identifier;
		}
	}
	return nil;
}

#pragma mark The query

- (NSString *)addQueryNamed:(NSString *)name outline:(NSString *)text reason:(NSString **)reason
{
	_failure = nil;
	_comparisons = [NSMutableArray array];
	_values = [NSMutableArray array];
	NSMutableArray *lines = [NSMutableArray array];
	NSUInteger number = 0;
	for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
		number++;
		NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([trimmed length] == 0) {
			continue;
		}
		NSUInteger spaces = 0;
		while (spaces < [raw length] && [raw characterAtIndex:spaces] == ' ') {
			spaces++;
		}
		ORMOutlineLine *line = [[ORMOutlineLine alloc] init];
		line.number = number;
		line.depth = spaces / 2;
		line.text = trimmed;
		line.tokens = ORMOutlineLex(trimmed, YES);
		[lines addObject:line];
	}
	_lines = lines;
	/* What it is for. */
	_header = [self headerOf:[lines firstObject]];
	if (_header == nil) {
		if (reason != NULL) {
			*reason = _failure;
		}
		return nil;
	}
	name = name ?: _header.name;
	NSUInteger index = _header.line != nil ? 1 : 0;
	ORMOutlineLine *rootLine = index < [lines count] ? [lines objectAtIndex:index] : nil;
	if (rootLine == nil || rootLine.depth != 0) {
		if (reason != NULL) {
			*reason = @"An outline starts at an object type, unindented.";
		}
		return nil;
	}
	/* The root: the longest object type name it starts with, as a node. */
	NSString *rootText = [rootLine.text hasPrefix:@"✓"] ? [rootLine.text substringFromIndex:1] : rootLine.text;
	ORMObjectType *rootType = nil;
	ORMOutlineNode *rootSaid = nil;
	for (ORMObjectType *type in _editor.model.objectTypes) {
		if (![rootText hasPrefix:type.name ?: @"\n"] || [type.name length] <= [rootType.name length]) {
			continue;
		}
		NSUInteger at = 0;
		ORMOutlineNode *said = ORMTakeNode(rootLine.text, rootLine.tokens, &at, ORMNameWords(type.name), YES);
		if (said != nil && at == [rootLine.tokens count]) {
			rootType = type;
			rootSaid = said;
		}
	}
	if (rootType == nil) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"Line %lu, \"%@\": no object type of the model is named so.",
			                                     (unsigned long)rootLine.number, rootLine.text];
		}
		return nil;
	}
	BOOL done = [_editor group:@"Add Query from Outline" trying:^BOOL {
		return [self makeQueryNamed:name ?: [NSString stringWithFormat:@"%@ Query", rootType.name] root:rootType
		                       said:rootSaid line:rootLine];
	}];
	if (!done) {
		if (reason != NULL) {
			*reason = _failure ?: @"The outline cannot be read.";
		}
		return nil;
	}
	return _query;
}

/* What the first line says the query is for: a constraint, a
 * calculation, a derivation; a list where it says none of them, and no
 * line of its own. nil, and why, where it names what the model has not. */
- (ORMOutlineHeader *)headerOf:(ORMOutlineLine *)line
{
	ORMOutlineHeader *header = [[ORMOutlineHeader alloc] init];
	header.kind = ORMQueryList;
	NSString *text = line.text ?: @"";
	NSArray *tokens = line.tokens;
	NSUInteger n = [tokens count];
	BOOL closed = n >= 2 && [[[tokens objectAtIndex:n - 1] text] isEqualToString:@":"];
	/* "TotalSalary of each Branch is total(Salary) of:": what it is
	 * named, the type it is of each of, its function and what of. */
	NSString *calculatedName = nil, *function = nil, *calculatedOf = nil;
	NSUInteger each = 1;
	while (each + 1 < n && !([[[tokens objectAtIndex:each] text] isEqualToString:@"of"]
	                         && [[[tokens objectAtIndex:each + 1] text] isEqualToString:@"each"])) {
		each++;
	}
	if (closed && n >= 9 && each + 1 < n && [[[tokens objectAtIndex:n - 2] text] isEqualToString:@"of"]
	    && [[[tokens objectAtIndex:n - 3] text] isEqualToString:@")"]) {
		for (NSUInteger k = each + 2; k + 4 < n && function == nil; k++) {
			NSString *name = [[tokens objectAtIndex:k + 1] text];
			if ([[[tokens objectAtIndex:k] text] isEqualToString:@"is"] && k > each + 2
			    && ([name isEqualToString:@"value"] || [ORMAggregateNames() containsObject:name])
			    && [[[tokens objectAtIndex:k + 2] text] isEqualToString:@"("] && k + 3 < n - 3) {
				function = name;
				calculatedName = ORMSource(text, tokens, 0, each);
				calculatedOf = ORMSource(text, tokens, k + 3, n - 3);
			}
		}
	}
	/* "Derivation of \"Person comes from Country\":", a fact type's;
	 * "Derivation of Cost:", a subtype's. */
	NSString *derivedReading = nil, *subtypeName = nil;
	NSUInteger at = 0;
	if (closed && n >= 4 && ORMNext(tokens, &at, @"Derivation") && ORMNext(tokens, &at, @"of")) {
		ORMOutlineToken *what = [tokens objectAtIndex:at];
		if (what.kind == ORMOutlineReading && n == 4) {
			derivedReading = what.text;
		} else if (what.kind != ORMOutlineReading) {
			subtypeName = ORMSource(text, tokens, at, n - 1);
		}
	}
	if ([text isEqualToString:@"It is impossible that:"] || [text isEqualToString:@"It is forbidden that:"]) {
		header.kind = ORMQueryConstraint;
		header.deontic = [text isEqualToString:@"It is forbidden that:"];
	} else if (function != nil) {
		header.kind = ORMQueryCalculation;
		header.name = calculatedName;
		header.function = function;
		header.calculated = calculatedOf;
	} else if ([text isEqualToString:@"Derivation:"]) {
		header.kind = ORMQueryDerivation;
	} else if (subtypeName != nil) {
		header.kind = ORMQueryDerivation;
		header.subtype = [_editor.model objectTypeNamed:subtypeName];
		if (header.subtype == nil) {
			_failure = [NSString stringWithFormat:@"Line %lu, \"%@\": no object type of the model is named so.",
			                                      (unsigned long)line.number, text];
			return nil;
		}
	} else if (derivedReading != nil) {
		header.kind = ORMQueryDerivation;
		NSString *reading = derivedReading;
		for (ORMFactType *fact in _editor.model.factTypes) {
			if ([[[fact primaryReading] expandedText] isEqualToString:reading]) {
				header.derived = fact;
			}
		}
		if (header.derived == nil) {
			_failure = [NSString stringWithFormat:@"Line %lu, \"%@\": no fact type of the model reads so.",
			                                      (unsigned long)line.number, text];
			return nil;
		}
	} else {
		return header;
	}
	header.line = line;
	return header;
}

/* The query the lines say, from its root: what the root says, its steps,
 * the conditions comparing nodes, what the header says it is for. NO,
 * with why in _failure, where a line cannot be read. */
- (BOOL)makeQueryNamed:(NSString *)name root:(ORMObjectType *)rootType said:(ORMOutlineNode *)rootSaid
                  line:(ORMOutlineLine *)rootLine
{
	NSString *why = nil;
	_query = [_queries addQueryNamed:name from:rootType.identifier reason:&why];
	if (_query == nil) {
		return [self fail:why ?: @"the query cannot be made" line:rootLine];
	}
	NSString *root = [self query].root.identifier;
	if (![self apply:rootSaid to:root line:rootLine]) {
		return NO;
	}
	NSUInteger next = [_lines indexOfObjectIdenticalTo:rootLine] + 1;
	if (next < [_lines count]) {
		ORMOutlineLine *first = [_lines objectAtIndex:next];
		if (first.depth != 1 || !([first.text hasPrefix:@"+ "] || ORMIsValueLine(first))) {
			return [self fail:@"a step from the root is indented once, after \"+\"" line:first];
		}
		next = [self steps:next from:root];
		if (next == NSNotFound) {
			return NO;
		}
		if (next < [_lines count]) {
			return [self fail:@"it is under nothing it can be read under" line:[_lines objectAtIndex:next]];
		}
	}
	/* Value nodes, in order, now every step is made. */
	for (NSArray *value in _values) {
		if (![self value:[value lastObject] of:[value firstObject]]) {
			return NO;
		}
	}
	/* Conditions comparing nodes, now there are all of them. */
	for (NSArray *comparison in _comparisons) {
		ORMQueryNode *other = [self designated:[comparison objectAtIndex:2] among:[[self query] nodes]];
		if (other == nil
		    || ![_queries setCondition:[comparison objectAtIndex:1] toNode:other.identifier ofNode:[comparison firstObject]
		                        reason:&why]) {
			return [self fail:why ?: @"no node of the query is designated so" line:[comparison lastObject]];
		}
	}
	return [self makeQueryWhatItIsFor];
}

/* The query made what the header says: a constraint and its modality, a
 * calculation and what it calculates, a derivation and, where no other
 * query derives it already, its fact type. */
- (BOOL)makeQueryWhatItIsFor
{
	ORMOutlineHeader *header = _header;
	NSString *why = nil;
	if (header.kind != ORMQueryList && ![_queries setKind:header.kind ofQuery:_query reason:&why]) {
		return [self fail:why ?: @"the query cannot be one" line:header.line];
	}
	if (header.kind == ORMQueryConstraint && ![_queries setDeontic:header.deontic ofQuery:_query reason:&why]) {
		return [self fail:why ?: @"the modality cannot be set" line:header.line];
	}
	if (header.kind == ORMQueryCalculation) {
		NSArray *functions = @[ @"value", @"count", @"total", @"avg", @"max", @"min" ];
		ORMQueryNode *of = [self designated:header.calculated among:[[self query] nodes]];
		if (of == nil
		    || ![_queries setCalculation:(ORMQueryCalculationFunction)[functions indexOfObject:header.function]
		                          ofNode:of.identifier inQuery:_query reason:&why]) {
			return [self fail:why ?: @"what it calculates is no node of the query" line:header.line];
		}
	}
	/* A copy of a derivation pasted: one derivation to a fact type. */
	if (header.kind == ORMQueryDerivation && header.derived != nil
	    && [ORMQuery derivationOf:header.derived inModel:_editor.model] == nil
	    && ![_queries setDerivedFactType:header.derived.identifier ofQuery:_query reason:&why]) {
		return [self fail:why ?: @"the fact type cannot be derived so" line:header.line];
	}
	if (header.kind == ORMQueryDerivation && header.subtype != nil
	    && [ORMQuery derivationOfSubtype:header.subtype inModel:_editor.model] == nil
	    && ![_queries setDerivedSubtype:header.subtype.identifier ofQuery:_query reason:&why]) {
		return [self fail:why ?: @"the subtype cannot be derived so" line:header.line];
	}
	return YES;
}


@end
