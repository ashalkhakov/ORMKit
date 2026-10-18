/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryExpression.h"

@interface ORMQueryExpression ()
@property (nonatomic, readwrite) ORMQueryExpressionKind kind;
@property (nonatomic, readwrite, copy) NSString *nodeId;
@property (nonatomic, readwrite, copy) NSString *constant;
@property (nonatomic, readwrite, copy) NSString *function;
@property (nonatomic, readwrite, copy) NSArray<ORMQueryExpression *> *arguments;
@end

/* Reading one, a character at a time: the text, where it is, the
 * designations (nil: as the file keeps it, nodes by id), and why it stopped. */
typedef struct {
	__unsafe_unretained NSString *text;
	NSUInteger at;
	__unsafe_unretained NSDictionary *designations;
	__unsafe_unretained NSString *failure;
} ORMExpressionReader;

static BOOL
ORMIsNameStart(unichar c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c > 127;
}

static BOOL
ORMIsNamePart(unichar c)
{
	return ORMIsNameStart(c) || (c >= '0' && c <= '9');
}

static unichar
ORMPeek(ORMExpressionReader *r)
{
	while (r->at < [r->text length] && [r->text characterAtIndex:r->at] == ' ') {
		r->at++;
	}
	return r->at < [r->text length] ? [r->text characterAtIndex:r->at] : 0;
}

static ORMQueryExpression *ORMReadSum(ORMExpressionReader *r);

static ORMQueryExpression *
ORMFail(ORMExpressionReader *r, NSString *why)
{
	if (r->failure == nil) {
		r->failure = why;
	}
	return nil;
}

/* A function's arguments, after its "(": up to its ")". */
static NSArray *
ORMReadArguments(ORMExpressionReader *r)
{
	NSMutableArray *arguments = [NSMutableArray array];
	if (ORMPeek(r) == ')') {
		r->at++;
		return arguments;
	}
	while (YES) {
		ORMQueryExpression *argument = ORMReadSum(r);
		if (argument == nil) {
			return nil;
		}
		[arguments addObject:argument];
		unichar c = ORMPeek(r);
		r->at++;
		if (c == ')') {
			return arguments;
		}
		if (c != ',') {
			ORMFail(r, @"a function's arguments are separated by commas and end with \")\"");
			return nil;
		}
	}
}

static ORMQueryExpression *
ORMReadPrimary(ORMExpressionReader *r)
{
	unichar c = ORMPeek(r);
	NSString *text = r->text;
	NSUInteger length = [text length];
	if (c == '(') {
		r->at++;
		ORMQueryExpression *inner = ORMReadSum(r);
		if (inner == nil) {
			return nil;
		}
		if (ORMPeek(r) != ')') {
			return ORMFail(r, @"a \"(\" without its \")\"");
		}
		r->at++;
		return inner;
	}
	if ((c >= '0' && c <= '9') || c == '.') {
		NSUInteger start = r->at;
		while (r->at < length && ([text characterAtIndex:r->at] == '.'
		                          || ([text characterAtIndex:r->at] >= '0' && [text characterAtIndex:r->at] <= '9'))) {
			r->at++;
		}
		return [ORMQueryExpression constant:[text substringWithRange:NSMakeRange(start, r->at - start)]];
	}
	if (c == '\'') {
		NSUInteger start = r->at;
		r->at++;
		while (r->at < length) {
			if ([text characterAtIndex:r->at] == '\'') {
				if (r->at + 1 < length && [text characterAtIndex:r->at + 1] == '\'') {
					r->at += 2;
					continue;
				}
				r->at++;
				return [ORMQueryExpression constant:[text substringWithRange:NSMakeRange(start, r->at - start)]];
			}
			r->at++;
		}
		return ORMFail(r, @"text that is not closed with \"'\"");
	}
	if (c == '#' && r->designations == nil) {
		NSUInteger start = ++r->at;
		while (r->at < length && [text characterAtIndex:r->at] != ',' && [text characterAtIndex:r->at] != ')'
		       && [text characterAtIndex:r->at] != ' ') {
			r->at++;
		}
		return [ORMQueryExpression node:[text substringWithRange:NSMakeRange(start, r->at - start)]];
	}
	if (ORMIsNameStart(c)) {
		NSUInteger start = r->at;
		while (r->at < length && ORMIsNamePart([text characterAtIndex:r->at])) {
			r->at++;
		}
		NSString *name = [text substringWithRange:NSMakeRange(start, r->at - start)];
		if (ORMPeek(r) == '(') {
			r->at++;
			NSNumber *arity = [[ORMQueryExpression functionArities] objectForKey:name];
			if (arity == nil) {
				return ORMFail(r, [NSString stringWithFormat:@"there is no function %@", name]);
			}
			NSArray *arguments = ORMReadArguments(r);
			if (arguments == nil) {
				return nil;
			}
			if ([arguments count] != [arity unsignedIntegerValue]) {
				return ORMFail(r, [NSString stringWithFormat:@"%@ takes %@ argument%@", name, arity,
				                                             [arity unsignedIntegerValue] == 1 ? @"" : @"s"]);
			}
			return [ORMQueryExpression function:name arguments:arguments];
		}
		NSString *nodeId = [r->designations objectForKey:name];
		if (nodeId == nil) {
			return ORMFail(r, [NSString stringWithFormat:@"no node of the query is designated %@", name]);
		}
		return [ORMQueryExpression node:nodeId];
	}
	return ORMFail(r, c == 0 ? @"it ends where a value is wanted" : [NSString stringWithFormat:@"\"%C\" is not a value", c]);
}

static ORMQueryExpression *
ORMReadUnary(ORMExpressionReader *r)
{
	unichar c = ORMPeek(r);
	if (c == '-' || c == 0x2212) {
		r->at++;
		ORMQueryExpression *operand = ORMReadUnary(r);
		return operand != nil ? [ORMQueryExpression function:@"negate" arguments:@[ operand ]] : nil;
	}
	return ORMReadPrimary(r);
}

static ORMQueryExpression *
ORMReadProduct(ORMExpressionReader *r)
{
	ORMQueryExpression *left = ORMReadUnary(r);
	while (left != nil) {
		unichar c = ORMPeek(r);
		NSString *function = c == '*' || c == 0x00D7 ? @"multiply" : c == '/' || c == 0x00F7 ? @"divide" : nil;
		if (function == nil) {
			break;
		}
		r->at++;
		ORMQueryExpression *right = ORMReadUnary(r);
		left = right != nil ? [ORMQueryExpression function:function arguments:@[ left, right ]] : nil;
	}
	return left;
}

static ORMQueryExpression *
ORMReadSum(ORMExpressionReader *r)
{
	ORMQueryExpression *left = ORMReadProduct(r);
	while (left != nil) {
		unichar c = ORMPeek(r);
		NSString *function = c == '+' ? @"add" : c == '-' || c == 0x2212 ? @"subtract" : nil;
		if (function == nil) {
			break;
		}
		r->at++;
		ORMQueryExpression *right = ORMReadProduct(r);
		left = right != nil ? [ORMQueryExpression function:function arguments:@[ left, right ]] : nil;
	}
	return left;
}

/* How tightly each infix function binds, said: sums, then products, then a
 * leading minus; 4 for what is said as a function or a value. */
static NSInteger
ORMPrecedence(ORMQueryExpression *expression)
{
	if (expression.kind != ORMQueryExpressionFunction) {
		return 4;
	}
	NSDictionary *precedence = @{ @"add": @1, @"subtract": @1, @"multiply": @2, @"divide": @2, @"negate": @3 };
	return [[precedence objectForKey:expression.function] integerValue] ?: 4;
}

@implementation ORMQueryExpression

+ (instancetype)node:(NSString *)nodeId
{
	ORMQueryExpression *expression = [[self alloc] init];
	expression.kind = ORMQueryExpressionNode;
	expression.nodeId = nodeId;
	return expression;
}

+ (instancetype)constant:(NSString *)text
{
	ORMQueryExpression *expression = [[self alloc] init];
	expression.kind = ORMQueryExpressionConstant;
	expression.constant = text;
	return expression;
}

+ (instancetype)function:(NSString *)name arguments:(NSArray<ORMQueryExpression *> *)arguments
{
	ORMQueryExpression *expression = [[self alloc] init];
	expression.kind = ORMQueryExpressionFunction;
	expression.function = name;
	expression.arguments = arguments ?: @[];
	return expression;
}

+ (NSDictionary<NSString *, NSNumber *> *)functionArities
{
	return @{ @"add": @2, @"subtract": @2, @"multiply": @2, @"divide": @2, @"negate": @1, @"round": @2, @"abs": @1,
		      @"min": @2, @"max": @2, @"coalesce": @2 };
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[ORMQueryExpression class]] && [[self canonicalText] isEqualToString:[other canonicalText]];
}

- (NSUInteger)hash
{
	return [[self canonicalText] hash];
}

+ (instancetype)read:(NSString *)text designations:(NSDictionary *)designations reason:(NSString **)reason
{
	ORMExpressionReader r = { text ?: @"", 0, designations, nil };
	ORMQueryExpression *expression = ORMReadSum(&r);
	if (expression != nil && ORMPeek(&r) != 0) {
		expression = ORMFail(&r, [NSString stringWithFormat:@"\"%@\" is more than the value says",
		                                                    [r.text substringFromIndex:r.at]]);
	}
	if (expression == nil && reason != NULL) {
		*reason = r.failure ?: @"it is no value";
	}
	return expression;
}

+ (instancetype)expressionWithCanonicalText:(NSString *)text reason:(NSString **)reason
{
	return [self read:text designations:nil reason:reason];
}

+ (instancetype)expressionWithText:(NSString *)text
                      designations:(NSDictionary<NSString *, NSString *> *)nodeIds
                            reason:(NSString **)reason
{
	return [self read:text designations:nodeIds ?: @{} reason:reason];
}

- (NSString *)canonicalText
{
	switch (self.kind) {
	case ORMQueryExpressionNode:
		return [@"#" stringByAppendingString:self.nodeId ?: @""];
	case ORMQueryExpressionConstant:
		return self.constant ?: @"";
	case ORMQueryExpressionFunction: {
		NSMutableArray *arguments = [NSMutableArray array];
		for (ORMQueryExpression *argument in self.arguments) {
			[arguments addObject:[argument canonicalText]];
		}
		return [NSString stringWithFormat:@"%@(%@)", self.function, [arguments componentsJoinedByString:@", "]];
	}
	}
	return @"";
}

/* The argument said, in parentheses where it binds less tightly than its
 * place wants: the right of a "-" or "/" also where it binds as tightly. */
static NSString *
ORMSaidIn(ORMQueryExpression *argument, NSInteger place, BOOL right, NSDictionary *designations)
{
	NSString *said = [argument textWithDesignations:designations];
	NSInteger own = ORMPrecedence(argument);
	return own < place || (right && own == place && place < 3) ? [NSString stringWithFormat:@"(%@)", said] : said;
}

- (NSString *)textWithDesignations:(NSDictionary<NSString *, NSString *> *)designations
{
	switch (self.kind) {
	case ORMQueryExpressionNode:
		return [designations objectForKey:self.nodeId ?: @""] ?: @"?";
	case ORMQueryExpressionConstant:
		return self.constant ?: @"";
	case ORMQueryExpressionFunction:
		break;
	}
	NSDictionary *symbols = @{ @"add": @"+", @"subtract": @"-", @"multiply": @"*", @"divide": @"/" };
	NSString *symbol = [symbols objectForKey:self.function];
	NSInteger place = ORMPrecedence(self);
	if (symbol != nil && [self.arguments count] == 2) {
		/* "-" and "/" are not associative: the right side bracketed where it
		 * binds as tightly ("a - (b - c)"); "+" and "*" are. */
		BOOL strict = [self.function isEqualToString:@"subtract"] || [self.function isEqualToString:@"divide"];
		return [NSString stringWithFormat:@"%@ %@ %@", ORMSaidIn([self.arguments firstObject], place, NO, designations), symbol,
		                                  ORMSaidIn([self.arguments lastObject], place, strict, designations)];
	}
	if ([self.function isEqualToString:@"negate"] && [self.arguments count] == 1) {
		return [@"-" stringByAppendingString:ORMSaidIn([self.arguments firstObject], place, NO, designations)];
	}
	NSMutableArray *arguments = [NSMutableArray array];
	for (ORMQueryExpression *argument in self.arguments) {
		[arguments addObject:[argument textWithDesignations:designations]];
	}
	return [NSString stringWithFormat:@"%@(%@)", self.function, [arguments componentsJoinedByString:@", "]];
}

- (void)collectNodeIds:(NSMutableOrderedSet *)into
{
	if (self.kind == ORMQueryExpressionNode && self.nodeId != nil) {
		[into addObject:self.nodeId];
	}
	for (ORMQueryExpression *argument in self.arguments) {
		[argument collectNodeIds:into];
	}
}

- (NSArray<NSString *> *)nodeIds
{
	NSMutableOrderedSet *ids = [NSMutableOrderedSet orderedSet];
	[self collectNodeIds:ids];
	return [ids array];
}

- (ORMQueryExpression *)expressionRenaming:(NSString *)from to:(NSString *)to
{
	switch (self.kind) {
	case ORMQueryExpressionNode:
		return [self.nodeId isEqualToString:from] ? [ORMQueryExpression node:to] : self;
	case ORMQueryExpressionConstant:
		return self;
	case ORMQueryExpressionFunction: {
		NSMutableArray *arguments = [NSMutableArray array];
		for (ORMQueryExpression *argument in self.arguments) {
			[arguments addObject:[argument expressionRenaming:from to:to]];
		}
		return [ORMQueryExpression function:self.function arguments:arguments];
	}
	}
	return self;
}

- (BOOL)isNumericGivenNumericNodes:(NSSet<NSString *> *)numeric
{
	switch (self.kind) {
	case ORMQueryExpressionNode:
		return [numeric containsObject:self.nodeId ?: @""];
	case ORMQueryExpressionConstant:
		return ![self.constant hasPrefix:@"'"];
	case ORMQueryExpressionFunction:
		if ([self.function isEqualToString:@"coalesce"] || [self.function isEqualToString:@"min"]
		    || [self.function isEqualToString:@"max"]) {
			return [[self.arguments firstObject] isNumericGivenNumericNodes:numeric];
		}
		return YES;
	}
	return NO;
}

@end
