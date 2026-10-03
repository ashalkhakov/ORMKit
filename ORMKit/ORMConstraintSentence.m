/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMConstraintSentence.h"
#import "ORMFactSentence.h"
#import "ORMReadingText.h"

/* The quantifiers the verbalizer puts before a name, longest first. */
static NSString *const ORMQuantifierPattern =
	@"the same|more than one|at least \\d+ and at most \\d+|at most one|exactly one|at least one|at least \\d+"
	@"|at most \\d+|exactly \\d+|each|some|that|no|an|a";

@interface ORMSentenceFact ()
@property (nonatomic, readwrite, copy) NSString *reading;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *playerNames;
@end

@implementation ORMSentenceFact
@end

@interface ORMSentenceRole ()
@property (nonatomic, readwrite, weak) ORMRole *role;
@property (nonatomic, readwrite, strong) ORMSentenceFact *fact;
@property (nonatomic, readwrite) NSUInteger index;
@end

@implementation ORMSentenceRole

- (BOOL)isEqual:(id)other
{
	if (![other isKindOfClass:[ORMSentenceRole class]]) {
		return NO;
	}
	ORMSentenceRole *that = other;
	return self.role != nil ? self.role == that.role : (self.fact == that.fact && self.index == that.index);
}

- (NSUInteger)hash
{
	return self.role != nil ? [self.role hash] : [self.fact hash] ^ self.index;
}

@end

@interface ORMSentenceConstraint ()
@property (nonatomic, readwrite) ORMConstraintKind kind;
@property (nonatomic, readwrite, copy) NSArray<NSArray<ORMSentenceRole *> *> *sequences;
@property (nonatomic, readwrite) ORMRingType ringType;
@property (nonatomic, readwrite) BOOL isExclusiveOr;
@property (nonatomic, readwrite, copy) NSString *values;
@property (nonatomic, readwrite, copy) NSString *valuesOfObjectType;
@property (nonatomic, readwrite, strong) ORMSentenceRole *valuesOfRole;
@end

@implementation ORMSentenceConstraint
@end

static ORMSentenceConstraint *
ORMMakeConstraint(ORMConstraintKind kind, NSArray<NSArray<ORMSentenceRole *> *> *sequences)
{
	ORMSentenceConstraint *constraint = [[ORMSentenceConstraint alloc] init];
	constraint.kind = kind;
	constraint.sequences = sequences;
	return constraint;
}

/* A placeholder of a clause: its quantifier, the name as written
 * ("Person2"), and the role it stands for. */
@interface ORMSentenceTerm : NSObject
@property (nonatomic, copy) NSString *quantifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) ORMSentenceRole *role;
/* Left out: the clause goes on from its subject. */
@property (nonatomic) BOOL omitted;
@end

@implementation ORMSentenceTerm

/* "Person" for "Person2". */
- (NSString *)typeName
{
	NSString *name = self.name;
	NSUInteger end = [name length];
	while (end > 1 && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[name characterAtIndex:end - 1]]) {
		end--;
	}
	return [name substringToIndex:end];
}

@end

/* A clause matched to a fact type: its terms in the order the reading
 * names them. */
@interface ORMSentenceClause : NSObject
@property (nonatomic, weak) ORMFactType *factType;
@property (nonatomic, strong) ORMSentenceFact *fact;
@property (nonatomic, copy) NSArray<ORMSentenceTerm *> *terms;
@end

@implementation ORMSentenceClause

- (ORMSentenceTerm *)termQuantified:(NSString *)quantifier
{
	for (ORMSentenceTerm *term in self.terms) {
		if ([term.quantifier isEqualToString:quantifier]) {
			return term;
		}
	}
	return nil;
}

- (ORMSentenceTerm *)termNamed:(NSString *)name
{
	for (ORMSentenceTerm *term in self.terms) {
		if ([term.name isEqualToString:name] || (!term.omitted && [[term typeName] isEqualToString:name])) {
			return term;
		}
	}
	return nil;
}

- (NSArray<ORMSentenceTerm *> *)termsOtherThan:(ORMSentenceTerm *)term
{
	NSMutableArray *others = [NSMutableArray arrayWithArray:self.terms];
	[others removeObjectIdenticalTo:term];
	return others;
}

/* The same fact type, made or not. */
- (BOOL)isSameFactAs:(ORMSentenceClause *)other
{
	return self.factType != nil ? self.factType == other.factType : self.fact == other.fact;
}

@end

static NSString *
ORMTrimmed(NSString *text)
{
	return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* A literal as a pattern, any run of spaces matching any run. */
static NSString *
ORMLiteralPattern(NSString *literal)
{
	NSString *escaped = [NSRegularExpression escapedPatternForString:literal ?: @""];
	NSRegularExpression *spaces = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:NULL];
	return [spaces stringByReplacingMatchesInString:escaped options:0 range:NSMakeRange(0, [escaped length])
	                                   withTemplate:@"\\\\s+"];
}

/* The names a role's player may go by in a sentence: its own, a
 * subtype's (a subset's "that Ambassador represents" for a Diplomat's
 * role) or a supertype's (an exclusion's "that Employee is ceo" for a
 * Manager's), longest first, each optionally numbered. A reading naming
 * the player itself is preferred (see match:omit:). */
/* Whether one is a subtype of the other, at any depth. */
static BOOL
ORMRelatedTypes(ORMObjectType *a, ORMObjectType *b)
{
	if (a == nil || b == nil) {
		return NO;
	}
	for (NSArray *pair in @[ @[ a, b ], @[ b, a ] ]) {
		NSMutableArray *up = [NSMutableArray arrayWithArray:[[pair firstObject] supertypes] ?: @[]];
		while ([up count] > 0) {
			ORMObjectType *type = [up lastObject];
			[up removeLastObject];
			if (type == [pair lastObject]) {
				return YES;
			}
			[up addObjectsFromArray:type.supertypes];
		}
	}
	return NO;
}

static NSString *
ORMNamesPattern(ORMObjectType *player)
{
	/* Its whole family: what is compared with it may be a sibling
	 * subtype (an exclusion's "that Driver" for a Witness's role). */
	NSMutableArray *names = [NSMutableArray array];
	NSMutableArray *pending = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	if (player != nil) {
		[pending addObject:player];
	}
	while ([pending count] > 0) {
		ORMObjectType *type = [pending lastObject];
		[pending removeLastObject];
		NSValue *key = [NSValue valueWithNonretainedObject:type];
		if ([seen containsObject:key]) {
			continue;
		}
		[seen addObject:key];
		if (type.name != nil && ![names containsObject:type.name]) {
			[names addObject:type.name];
		}
		[pending addObjectsFromArray:type.subtypes];
		[pending addObjectsFromArray:type.supertypes];
	}
	[names sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		return [a length] > [b length] ? NSOrderedAscending : [a length] < [b length] ? NSOrderedDescending : NSOrderedSame;
	}];
	NSMutableArray *patterns = [NSMutableArray array];
	for (NSString *name in names) {
		[patterns addObject:ORMLiteralPattern(name)];
	}
	return [NSString stringWithFormat:@"(?:%@)(?:\\d+)?", [patterns count] > 0 ? [patterns componentsJoinedByString:@"|"] : @"\\?"];
}

/* "Each Person" to "each Person": a sentence's first word as a clause's. */
static NSString *
ORMLowerFirst(NSString *text)
{
	if ([text length] == 0) {
		return text;
	}
	return [[[text substringToIndex:1] lowercaseString] stringByAppendingString:[text substringFromIndex:1]];
}

static BOOL
ORMHasPrefix(NSString *text, NSString *prefix)
{
	return [text length] >= [prefix length]
		&& [[text substringToIndex:[prefix length]] caseInsensitiveCompare:prefix] == NSOrderedSame;
}

@implementation ORMConstraintSentence
{
	ORMModel *_model;
	NSMutableArray<ORMSentenceFact *> *_facts;
	NSMutableArray<ORMSentenceConstraint *> *_constraints;
	NSString *_reason;
}

#pragma mark Clauses

/* The pattern of a reading with each placeholder an optionally quantified,
 * optionally numbered name; without its first placeholder when omit is
 * set. The capture groups: a quantifier and a name a placeholder. */
- (NSString *)patternOf:(NSString *)text roles:(NSArray<ORMRole *> *)roles omit:(BOOL)omit
{
	ORMReadingText *reading = [ORMReadingText readingTextWithString:text arity:[roles count] reason:NULL];
	if (reading == nil || [reading.parts count] == 0) {
		return nil;
	}
	if (omit && [ORMTrimmed(reading.frontText) length] > 0) {
		return nil;
	}
	NSMutableString *pattern = [NSMutableString stringWithString:@"^\\s*"];
	[pattern appendString:ORMLiteralPattern(reading.frontText)];
	for (NSUInteger i = 0; i < [reading.parts count]; i++) {
		ORMReadingPart *part = [reading.parts objectAtIndex:i];
		if (i == 0 && omit) {
			NSString *following = [part.followingText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			[pattern appendString:ORMLiteralPattern(following)];
			if ([part.followingText hasSuffix:@" "]) {
				[pattern appendString:@"\\s+"];
			}
			continue;
		}
		ORMRole *role = part.roleIndex < [roles count] ? [roles objectAtIndex:part.roleIndex] : nil;
		[pattern appendFormat:@"(?:(?i:(%@))\\s+)?", ORMQuantifierPattern];
		[pattern appendString:ORMLiteralPattern(part.preBoundText)];
		[pattern appendFormat:@"(%@)", ORMNamesPattern(role.player)];
		[pattern appendString:ORMLiteralPattern(part.postBoundText)];
		[pattern appendString:ORMLiteralPattern(part.followingText)];
	}
	[pattern appendString:@"\\s*$"];
	return pattern;
}

/* A reading's pattern compiled, kept for the next sentence: what it is
 * depends only on the reading, its players' names and the omission. */
- (NSRegularExpression *)expressionOf:(NSString *)reading roles:(NSArray<ORMRole *> *)roles omit:(BOOL)omit
{
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [[NSCache alloc] init];
		[cache setCountLimit:1500];
	});
	NSMutableArray *key = [NSMutableArray arrayWithObjects:reading, @(omit), nil];
	for (ORMRole *role in roles) {
		/* The player's family names its pattern. */
		[key addObject:ORMNamesPattern(role.player)];
	}
	id expression = [cache objectForKey:key];
	if (expression == nil) {
		NSString *pattern = [self patternOf:reading roles:roles omit:omit];
		expression = pattern != nil ? [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL] : nil;
		[cache setObject:expression ?: [NSNull null] forKey:key];
	}
	return expression == [NSNull null] ? nil : expression;
}

/* The readings to match a clause against: each reading of each fact type,
 * and a subtype fact's "{0} is {1}" either way. */
- (NSArray<NSArray *> *)readings
{
	NSMutableArray *readings = [NSMutableArray array];
	for (ORMFactType *fact in _model.factTypes) {
		if (fact.kind == ORMFactTypeSubtype && [fact.roles count] == 2) {
			ORMRole *sub = [fact.roles objectAtIndex:0];
			ORMRole *sup = [fact.roles objectAtIndex:1];
			[readings addObject:@[ fact, @"{0} is {1}", @[ sub, sup ] ]];
			[readings addObject:@[ fact, @"{0} is {1}", @[ sup, sub ] ]];
			continue;
		}
		if (fact.kind != ORMFactTypeOrdinary) {
			continue;
		}
		if ([fact.readingOrders count] == 0) {
			/* No reading: the verbalizer lists the players. */
			NSArray *roles = [fact visibleRoles];
			NSMutableArray *places = [NSMutableArray array];
			for (NSUInteger i = 0; i < [roles count]; i++) {
				[places addObject:[NSString stringWithFormat:@"{%lu}", (unsigned long)i]];
			}
			[readings addObject:@[ fact, [places componentsJoinedByString:@" ... "], roles ]];
			continue;
		}
		for (ORMReadingOrder *order in fact.readingOrders) {
			for (ORMReading *reading in order.readings) {
				if (reading.text != nil) {
					[readings addObject:@[ fact, reading.text, order.roles ]];
				}
			}
		}
	}
	return readings;
}

- (NSArray<ORMSentenceClause *> *)match:(NSString *)text omit:(BOOL)omit
{
	/* The readings that name the players as they are come before those a
	 * subtype's name matched; only a tie among the best is ambiguous. */
	NSArray *all = [self allMatches:text omit:omit];
	NSInteger best = -1;
	NSMutableArray *clauses = [NSMutableArray array];
	for (ORMSentenceClause *clause in all) {
		NSInteger exact = 0;
		for (ORMSentenceTerm *term in clause.terms) {
			exact += [[term typeName] isEqualToString:term.role.role.player.name ?: @""] ? 1 : 0;
		}
		if (exact > best) {
			best = exact;
			[clauses removeAllObjects];
		}
		if (exact == best) {
			[clauses addObject:clause];
		}
	}
	NSMutableSet *facts = [NSMutableSet set];
	for (ORMSentenceClause *clause in clauses) {
		[facts addObject:[NSValue valueWithNonretainedObject:clause.factType]];
	}
	if ([facts count] > 1) {
		_isAmbiguous = YES;
	}
	return clauses;
}

- (NSArray<ORMSentenceClause *> *)allMatches:(NSString *)text omit:(BOOL)omit
{
	NSMutableArray *clauses = [NSMutableArray array];
	NSRegularExpression *placeholders = [NSRegularExpression regularExpressionWithPattern:@"\\{\\d+\\}" options:0 error:NULL];
	for (NSArray *candidate in [self readings]) @autoreleasepool {
		ORMFactType *fact = [candidate objectAtIndex:0];
		NSString *reading = [candidate objectAtIndex:1];
		NSArray *roles = [candidate objectAtIndex:2];
		/* A reading whose own words the clause lacks cannot match it. */
		BOOL possible = YES;
		NSString *words = [placeholders stringByReplacingMatchesInString:reading options:0
		                                                           range:NSMakeRange(0, [reading length])
		                                                    withTemplate:@" "];
		for (NSString *word in [words componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
			if ([word length] > 0 && [word rangeOfString:@"-"].location == NSNotFound
			    && [text rangeOfString:word].location == NSNotFound) {
				possible = NO;
				break;
			}
		}
		if (!possible) {
			continue;
		}
		NSRegularExpression *expression = [self expressionOf:reading roles:roles omit:omit];
		if (expression == nil) {
			continue;
		}
		NSTextCheckingResult *result = [expression firstMatchInString:text options:0
		                                                       range:NSMakeRange(0, [text length])];
		if (result == nil) {
			continue;
		}
		ORMReadingText *parsed = [ORMReadingText readingTextWithString:reading arity:[roles count] reason:NULL];
		NSMutableArray *terms = [NSMutableArray array];
		NSUInteger group = 1;
		for (NSUInteger i = 0; i < [parsed.parts count]; i++) {
			ORMReadingPart *part = [parsed.parts objectAtIndex:i];
			ORMSentenceTerm *term = [[ORMSentenceTerm alloc] init];
			term.role = [[ORMSentenceRole alloc] init];
			term.role.role = [roles objectAtIndex:part.roleIndex];
			if (i == 0 && omit) {
				term.omitted = YES;
				term.name = term.role.role.player.name;
			} else {
				NSRange quantifier = [result rangeAtIndex:group];
				NSRange name = [result rangeAtIndex:group + 1];
				group += 2;
				term.quantifier = quantifier.location != NSNotFound
					? [[text substringWithRange:quantifier] lowercaseString] : nil;
				term.name = [text substringWithRange:name];
			}
			[terms addObject:term];
		}
		ORMSentenceClause *clause = [[ORMSentenceClause alloc] init];
		clause.factType = fact;
		clause.terms = terms;
		[clauses addObject:clause];
	}
	return clauses;
}

/* A clause the model has no reading for: a fact type to make. The word
 * after a quantifier, and a known object type's name, are object types;
 * the subject, when the clause leaves it out, comes first. */
- (ORMSentenceClause *)newClause:(NSString *)text subject:(NSString *)subject
{
	NSArray *words = [ORMTrimmed(text) componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
	NSRegularExpression *quantifier = [NSRegularExpression
		regularExpressionWithPattern:[NSString stringWithFormat:@"^(?i:(%@))$", ORMQuantifierPattern]
		                     options:0
		                       error:NULL];
	NSMutableArray *terms = [NSMutableArray array];
	NSMutableArray *reading = [NSMutableArray array];
	BOOL leftOut = subject != nil;
	for (NSUInteger i = 0; i < [words count]; i++) {
		/* A quantifier of up to six words, then a name. */
		NSString *found = nil;
		NSUInteger length = 0;
		for (NSUInteger n = MIN((NSUInteger)6, [words count] - i - 1); n >= 1 && found == nil; n--) {
			NSString *phrase = [[words subarrayWithRange:NSMakeRange(i, n)] componentsJoinedByString:@" "];
			if ([quantifier firstMatchInString:phrase options:0 range:NSMakeRange(0, [phrase length])] != nil) {
				found = [phrase lowercaseString];
				length = n;
			}
		}
		NSString *word = [words objectAtIndex:i + length];
		BOOL capitalized = [word length] > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[word characterAtIndex:0]];
		ORMSentenceTerm *probe = [[ORMSentenceTerm alloc] init];
		probe.name = word;
		BOOL known = [_model objectTypeNamed:word] != nil || [_model objectTypeNamed:[probe typeName]] != nil;
		if ((found != nil && capitalized) || (found == nil && (known || (i == 0 && capitalized)))) {
			ORMSentenceTerm *term = [[ORMSentenceTerm alloc] init];
			term.quantifier = found;
			term.name = word;
			[terms addObject:term];
			[reading addObject:[NSString stringWithFormat:@"{%lu}", (unsigned long)[terms count] - 1 + (leftOut ? 1 : 0)]];
			if (i == 0 && leftOut && [[term typeName] isEqualToString:subject]) {
				leftOut = NO;
				[reading replaceObjectAtIndex:[reading count] - 1 withObject:@"{0}"];
			}
			i += length;
			continue;
		}
		[reading addObject:[words objectAtIndex:i]];
	}
	if (leftOut) {
		ORMSentenceTerm *term = [[ORMSentenceTerm alloc] init];
		term.name = subject;
		term.omitted = YES;
		[terms insertObject:term atIndex:0];
		[reading insertObject:@"{0}" atIndex:0];
	}
	if ([terms count] == 0) {
		return nil;
	}
	NSMutableArray *players = [NSMutableArray array];
	for (ORMSentenceTerm *term in terms) {
		[players addObject:[term typeName]];
	}
	NSString *text2 = [reading componentsJoinedByString:@" "];
	/* One fact type a sentence: "Person1 is parent of Person2" twice is
	 * one fact type. */
	ORMSentenceFact *fact = nil;
	for (ORMSentenceFact *made in _facts) {
		if ([made.reading isEqualToString:text2] && [made.playerNames isEqualToArray:players]) {
			fact = made;
		}
	}
	if (fact == nil) {
		fact = [[ORMSentenceFact alloc] init];
		fact.reading = text2;
		fact.playerNames = players;
		[_facts addObject:fact];
	}
	for (NSUInteger i = 0; i < [terms count]; i++) {
		ORMSentenceTerm *term = [terms objectAtIndex:i];
		term.role = [[ORMSentenceRole alloc] init];
		term.role.fact = fact;
		term.role.index = i;
	}
	ORMSentenceClause *clause = [[ORMSentenceClause alloc] init];
	clause.fact = fact;
	clause.terms = terms;
	return clause;
}

/* A clause: of a reading the model has, else a fact type to make. With a
 * subject, the clause may leave it out ("...or has some Passport"). */
- (ORMSentenceClause *)clause:(NSString *)text subject:(NSString *)subject
{
	text = ORMTrimmed(text);
	NSArray *clauses = [self match:text omit:NO];
	if ([clauses count] == 0 && subject != nil) {
		/* Left out, the subject is the reading's first player, or its
		 * subtype or supertype ("Each Component ... or flattens" for an
		 * Absorption's role). */
		ORMSentenceTerm *probe = [[ORMSentenceTerm alloc] init];
		probe.name = subject;
		ORMObjectType *type = [_model objectTypeNamed:[probe typeName]];
		for (ORMSentenceClause *clause in [self match:text omit:YES]) {
			ORMSentenceTerm *first = [clause.terms firstObject];
			ORMObjectType *player = first.role.role.player;
			if (player == type || ORMRelatedTypes(player, type)) {
				first.name = subject;
				return clause;
			}
		}
	}
	if ([clauses count] > 0) {
		return [clauses firstObject];
	}
	return [self newClause:text subject:subject];
}

#pragma mark Templates

- (BOOL)fail:(NSString *)reason
{
	_reason = reason;
	return NO;
}

- (void)add:(ORMSentenceConstraint *)constraint
{
	[_constraints addObject:constraint];
}

/* "Each Person was born in exactly one Country", "Each Person smokes". */
- (BOOL)each:(NSString *)text
{
	/* A reading the model has; else alternatives; else a new fact type. */
	ORMSentenceClause *clause = [[self match:ORMLowerFirst(text) omit:NO] firstObject];
	if (clause == nil && [text rangeOfString:@" or "].location != NSNotFound) {
		return [self alternatives:text];
	}
	if (clause == nil) {
		clause = [self newClause:ORMLowerFirst(text) subject:nil];
	}
	ORMSentenceTerm *each = [clause termQuantified:@"each"];
	if (clause != nil && each != nil) {
		NSArray *others = [clause termsOtherThan:each];
		if ([others count] == 0) {
			[self add:ORMMakeConstraint(ORMMandatoryConstraint, @[ @[ each.role ] ])];
			return YES;
		}
		NSString *quantifier = [[others firstObject] quantifier];
		BOOL allSome = YES;
		for (ORMSentenceTerm *other in others) {
			allSome = allSome && ([other.quantifier isEqualToString:@"some"] || [other.quantifier isEqualToString:@"at least one"]);
		}
		if ([others count] == 1 && ([quantifier isEqualToString:@"exactly one"] || [quantifier isEqualToString:@"at most one"])) {
			[self add:ORMMakeConstraint(ORMUniquenessConstraint, @[ @[ each.role ] ])];
			if ([quantifier isEqualToString:@"exactly one"]) {
				[self add:ORMMakeConstraint(ORMMandatoryConstraint, @[ @[ each.role ] ])];
			}
			return YES;
		}
		if (allSome) {
			[self add:ORMMakeConstraint(ORMMandatoryConstraint, @[ @[ each.role ] ])];
			return YES;
		}
	}
	return [self alternatives:text];
}

/* "Each Visitor has some Passport or has some DriverLicence", with "but
 * not both" an exclusive-or. */
- (BOOL)alternatives:(NSString *)text
{
	BOOL exclusive = NO;
	if ([text hasSuffix:@" but not both"]) {
		exclusive = YES;
		text = [text substringToIndex:[text length] - [@" but not both" length]];
	}
	NSArray *parts = [text componentsSeparatedByString:@" or "];
	if ([parts count] < 2) {
		return [self fail:@"The sentence does not say what each instance does."];
	}
	ORMSentenceClause *first = [self clause:ORMLowerFirst([parts firstObject]) subject:nil];
	ORMSentenceTerm *each = [first termQuantified:@"each"];
	if (each == nil) {
		return [self fail:@"An alternative is not about \"each\" one."];
	}
	NSString *subject = [each typeName];
	NSMutableArray *roles = [NSMutableArray arrayWithObject:each.role];
	for (NSUInteger i = 1; i < [parts count]; i++) {
		ORMSentenceClause *clause = [self clause:[parts objectAtIndex:i] subject:subject];
		ORMSentenceTerm *term = [clause termNamed:subject];
		if (term == nil) {
			return [self fail:[NSString stringWithFormat:@"\"%@\" is not about %@.", [parts objectAtIndex:i], subject]];
		}
		[roles addObject:term.role];
	}
	ORMSentenceConstraint *constraint = ORMMakeConstraint(ORMMandatoryConstraint, @[ roles ]);
	constraint.isExclusiveOr = exclusive;
	[self add:constraint];
	return YES;
}

/* A ring's two roles in a clause: the two of one object type, Person1's
 * before Person2's, else in reading order. */
- (NSArray<ORMSentenceRole *> *)ringRoles:(ORMSentenceClause *)clause
{
	if ([clause.terms count] == 2) {
		return [clause.terms valueForKey:@"role"];
	}
	for (ORMSentenceTerm *term in clause.terms) {
		NSMutableArray *same = [NSMutableArray array];
		for (ORMSentenceTerm *other in clause.terms) {
			if ([[other typeName] isEqualToString:[term typeName]]) {
				[same addObject:other];
			}
		}
		if ([same count] == 2) {
			[same sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(ORMSentenceTerm *a, ORMSentenceTerm *b) {
				return [a.name compare:b.name];
			}];
			if ([[[same firstObject] name] isEqualToString:[[same lastObject] name]]) {
				/* Both unnumbered: as the reading has them. */
				same = [NSMutableArray arrayWithArray:[clause.terms filteredArrayUsingPredicate:
					[NSPredicate predicateWithBlock:^BOOL(ORMSentenceTerm *t, NSDictionary *bindings) {
						(void)bindings;
						return [[t typeName] isEqualToString:[term typeName]];
					}]]];
			}
			return [same valueForKey:@"role"];
		}
	}
	return nil;
}

/* "No Person smokes and drinks", "No Person wrote and reviewed the same
 * Book", "No Person is parent of itself", "No Person may cycle back...". */
- (BOOL)no:(NSString *)text
{
	NSString *cycle = @" may cycle back to itself via one or more traversals through ";
	NSRange through = [text rangeOfString:cycle];
	if (through.location != NSNotFound) {
		ORMSentenceClause *clause = [self clause:[text substringFromIndex:NSMaxRange(through)] subject:nil];
		NSArray *roles = [self ringRoles:clause];
		if (roles == nil) {
			return [self fail:@"A ring constraint is over two roles of one object type."];
		}
		ORMSentenceConstraint *ring = ORMMakeConstraint(ORMRingConstraint, @[ roles ]);
		ring.ringType = ORMRingAcyclic;
		[self add:ring];
		return YES;
	}
	NSRange itself = [[text stringByAppendingString:@" "] rangeOfString:@" itself "];
	if (itself.location != NSNotFound) {
		NSString *subject = [self leadingName:text];
		if (subject == nil) {
			return [self fail:@"Say what may not be related to itself."];
		}
		NSString *clauseText = [text stringByReplacingCharactersInRange:NSMakeRange(itself.location + 1, [@"itself" length])
		                                                     withString:subject];
		ORMSentenceClause *clause = [self clause:clauseText subject:nil];
		NSArray *roles = [self ringRoles:clause];
		if (roles == nil) {
			return [self fail:@"A ring constraint is over two roles of one object type."];
		}
		ORMSentenceConstraint *ring = ORMMakeConstraint(ORMRingConstraint, @[ roles ]);
		ring.ringType = ORMRingIrreflexive;
		[self add:ring];
		return YES;
	}
	NSRange same = [text rangeOfString:@" the same " options:NSBackwardsSearch];
	NSString *subject = [self leadingName:text];
	if (same.location != NSNotFound && subject != nil) {
		/* Whole binaries: "Person wrote and reviewed the same Book". */
		NSString *object = [text substringFromIndex:NSMaxRange(same)];
		NSString *verbs = [text substringWithRange:NSMakeRange([subject length], same.location - [subject length])];
		verbs = [verbs stringByReplacingOccurrencesOfString:@", " withString:@" and "];
		NSMutableArray *sequences = [NSMutableArray array];
		for (NSString *verb in [verbs componentsSeparatedByString:@" and "]) {
			NSString *clauseText = [NSString stringWithFormat:@"%@ %@ %@", subject, ORMTrimmed(verb), object];
			ORMSentenceClause *clause = [self clause:clauseText subject:nil];
			ORMSentenceTerm *a = [clause termNamed:subject];
			ORMSentenceTerm *b = [clause termNamed:object];
			if (a == nil || b == nil || a == b) {
				return [self fail:[NSString stringWithFormat:@"\"%@\" is not a fact type.", clauseText]];
			}
			[sequences addObject:@[ a.role, b.role ]];
		}
		[self add:ORMMakeConstraint(ORMExclusionConstraint, sequences)];
		return YES;
	}
	/* Single roles: "Person smokes and drinks". */
	NSArray *parts = [text componentsSeparatedByString:@" and "];
	if (subject == nil || [parts count] < 2) {
		return [self fail:@"Say what no instance does."];
	}
	NSMutableArray *sequences = [NSMutableArray array];
	for (NSUInteger i = 0; i < [parts count]; i++) {
		ORMSentenceClause *clause = [self clause:[parts objectAtIndex:i] subject:subject];
		ORMSentenceTerm *term = [clause termNamed:subject];
		if (term == nil) {
			return [self fail:[NSString stringWithFormat:@"\"%@\" is not about %@.", [parts objectAtIndex:i], subject]];
		}
		[sequences addObject:@[ term.role ]];
	}
	[self add:ORMMakeConstraint(ORMExclusionConstraint, sequences)];
	return YES;
}

/* The object type a text starts with: the longest name the model has,
 * else its first word. */
- (NSString *)leadingName:(NSString *)text
{
	NSString *best = nil;
	for (ORMObjectType *type in _model.objectTypes) {
		/* A unary's implicit value type ("Person smokes") is no subject. */
		if (type.isImplicitBooleanValue) {
			continue;
		}
		NSString *name = type.name;
		NSUInteger end = [name length];
		while (end < [text length] && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[text characterAtIndex:end]]) {
			end++;
		}
		if ([name length] > [best length] && [text hasPrefix:name]
		    && ([text length] == end || [text characterAtIndex:end] == ' ')) {
			best = [text substringToIndex:end];
		}
	}
	if (best == nil) {
		NSRange space = [text rangeOfString:@" "];
		best = space.location == NSNotFound ? text : [text substringToIndex:space.location];
	}
	return best;
}

/* "If some Person smokes then that Person is cancer prone"; and the ring
 * forms: symmetric, asymmetric, antisymmetric, transitive, intransitive,
 * reflexive. */
- (BOOL)ifThen:(NSString *)text
{
	NSRange then = [text rangeOfString:@" then "];
	if (then.location == NSNotFound) {
		return [self fail:@"An \"if\" needs a \"then\"."];
	}
	NSString *left = [text substringToIndex:then.location];
	NSString *right = [text substringFromIndex:NSMaxRange(then)];
	BOOL impossible = ORMHasPrefix(right, @"it is impossible that ");
	if (impossible) {
		right = [right substringFromIndex:[@"it is impossible that " length]];
	}
	if ([right rangeOfString:@" is indirectly related to "].location != NSNotFound
	    && [right hasSuffix:@" by repeatedly applying this fact type"]) {
		ORMSentenceClause *clause = [self clause:left subject:nil];
		NSArray *roles = [self ringRoles:clause];
		if (roles == nil) {
			return [self fail:@"A ring constraint is over two roles of one object type."];
		}
		ORMSentenceConstraint *ring = ORMMakeConstraint(ORMRingConstraint, @[ roles ]);
		ring.ringType = ORMRingStronglyIntransitive;
		[self add:ring];
		return YES;
	}
	BOOL antisymmetric = NO;
	NSRegularExpression *isNot = [NSRegularExpression regularExpressionWithPattern:@" and (\\S+) is not (\\S+)$" options:0
	                                                                         error:NULL];
	NSTextCheckingResult *notSame = [isNot firstMatchInString:left options:0 range:NSMakeRange(0, [left length])];
	if (notSame != nil) {
		antisymmetric = YES;
		left = [left substringToIndex:notSame.range.location];
	}
	NSArray *lefts = [left componentsSeparatedByString:@" and "];
	ORMSentenceClause *first = [self clause:[lefts firstObject] subject:nil];
	ORMSentenceClause *second = [lefts count] > 1 ? [self clause:[lefts objectAtIndex:1] subject:nil] : nil;
	BOOL reflexive = [right hasSuffix:@" itself"];
	if (reflexive) {
		NSString *subject = [self leadingName:right];
		right = [[right substringToIndex:[right length] - [@"itself" length]] stringByAppendingString:subject];
	}
	ORMSentenceClause *conclusion = [self clause:right subject:nil];
	if (first == nil || conclusion == nil) {
		return [self fail:@"The clauses are not fact types."];
	}
	/* A ring: every clause of one fact type, over two roles of one type. */
	NSArray *ringRoles = [self ringRoles:first];
	if (ringRoles != nil && [first isSameFactAs:conclusion] && (second == nil || [second isSameFactAs:first])) {
		ORMRingType type = 0;
		if (reflexive) {
			type = ORMRingReflexive;
		} else if (second != nil) {
			type = impossible ? ORMRingIntransitive : ORMRingTransitive;
		} else if (antisymmetric) {
			type = ORMRingAntisymmetric;
		} else {
			type = impossible ? ORMRingAsymmetric : ORMRingSymmetric;
		}
		ORMSentenceConstraint *ring = ORMMakeConstraint(ORMRingConstraint, @[ ringRoles ]);
		ring.ringType = type;
		[self add:ring];
		return YES;
	}
	if (second != nil || impossible) {
		return [self fail:@"Only a subset of one fact type's roles is understood after \"if\"."];
	}
	/* A subset: the roles the conclusion names again ("that Person"), in
	 * the order the condition named them. */
	NSMutableArray *subset = [NSMutableArray array];
	NSMutableArray *superset = [NSMutableArray array];
	for (ORMSentenceTerm *term in first.terms) {
		ORMSentenceTerm *again = nil;
		for (ORMSentenceTerm *other in conclusion.terms) {
			BOOL named = [other.quantifier isEqualToString:@"that"] || (other.quantifier == nil && ![other.name isEqualToString:[other typeName]]);
			if (named && [other.name isEqualToString:term.name]) {
				again = other;
			}
		}
		if (again != nil) {
			[subset addObject:term.role];
			[superset addObject:again.role];
		}
	}
	if ([subset count] == 0) {
		return [self fail:@"The \"then\" does not name again what the \"if\" introduced."];
	}
	[self add:ORMMakeConstraint(ORMSubsetConstraint, @[ subset, superset ])];
	return YES;
}

/* "For each Country, at most one Person is president of that Country";
 * "For each Person and Sport, that Person played that Sport for at most
 * one Country"; external uniqueness; "at most one of the following
 * holds". */
- (BOOL)forEach:(NSString *)text
{
	/* The names listed: the longest run, up to a comma, of names the
	 * model has ("City, Street, Country, Region and PostalCode"). */
	NSString *head = nil;
	NSString *rest = nil;
	NSRange search = NSMakeRange(0, [text length]);
	for (NSRange comma = [text rangeOfString:@", " options:0 range:search]; comma.location != NSNotFound;
	     comma = [text rangeOfString:@", " options:0 range:search]) {
		NSString *candidate = [text substringToIndex:comma.location];
		BOOL known = YES;
		for (NSString *name in [[candidate stringByReplacingOccurrencesOfString:@" and " withString:@", "]
		                           componentsSeparatedByString:@", "]) {
			ORMSentenceTerm *probe = [[ORMSentenceTerm alloc] init];
			probe.name = name;
			known = known && ([_model objectTypeNamed:name] != nil || [_model objectTypeNamed:[probe typeName]] != nil);
		}
		if (known || head == nil) {
			head = candidate;
			rest = [text substringFromIndex:NSMaxRange(comma)];
		}
		search = NSMakeRange(NSMaxRange(comma), [text length] - NSMaxRange(comma));
	}
	if (head == nil) {
		return [self fail:@"\"For each\" needs a comma after what it lists."];
	}
	NSArray *names = [[head stringByReplacingOccurrencesOfString:@" and " withString:@", "] componentsSeparatedByString:@", "];
	BOOL exactlyOneHolds = ORMHasPrefix(rest, @"exactly one of the following holds: ");
	if (exactlyOneHolds || ORMHasPrefix(rest, @"at most one of the following holds: ")) {
		NSString *list = [rest substringFromIndex:[exactlyOneHolds ? @"exactly one of the following holds: "
		                                                             : @"at most one of the following holds: " length]];
		NSMutableArray *sequences = [NSMutableArray array];
		for (NSString *part in [list componentsSeparatedByString:@"; "]) {
			ORMSentenceClause *clause = [self clause:part subject:nil];
			NSMutableArray *roles = [NSMutableArray array];
			for (NSString *name in names) {
				ORMSentenceTerm *term = [clause termNamed:name];
				if (term == nil) {
					return [self fail:[NSString stringWithFormat:@"\"%@\" does not name %@.", part, name]];
				}
				[roles addObject:term.role];
			}
			[sequences addObject:roles];
		}
		if (exactlyOneHolds) {
			NSMutableArray *roles = [NSMutableArray array];
			for (NSArray *sequence in sequences) {
				if ([sequence count] != 1) {
					return [self fail:@"Exactly one of several holds only for single roles."];
				}
				[roles addObject:[sequence firstObject]];
			}
			ORMSentenceConstraint *constraint = ORMMakeConstraint(ORMMandatoryConstraint, @[ roles ]);
			constraint.isExclusiveOr = YES;
			[self add:constraint];
		} else {
			[self add:ORMMakeConstraint(ORMExclusionConstraint, sequences)];
		}
		return YES;
	}
	/* Equality: "For each Patient, that Patient had some SystolicBP if and
	 * only if that Patient had some DiastolicBP". */
	NSRange iff = [rest rangeOfString:@" if and only if "];
	if (iff.location != NSNotFound) {
		NSMutableArray *sequences = [NSMutableArray array];
		for (NSString *part in @[ [rest substringToIndex:iff.location], [rest substringFromIndex:NSMaxRange(iff)] ]) {
			ORMSentenceClause *clause = [self clause:part subject:nil];
			NSMutableArray *roles = [NSMutableArray array];
			for (NSString *name in names) {
				ORMSentenceTerm *term = [clause termNamed:name];
				if (term == nil) {
					return [self fail:[NSString stringWithFormat:@"\"%@\" does not name %@.", part, name]];
				}
				[roles addObject:term.role];
			}
			[sequences addObject:roles];
		}
		[self add:ORMMakeConstraint(ORMEqualityConstraint, sequences)];
		return YES;
	}
	/* One fact type: the roles named "that" are the constrained ones. A
	 * fact type the model lacks is made, unless this reads as external
	 * uniqueness ("at most one Region is ... and ..."). */
	ORMSentenceClause *clause = [[self match:ORMTrimmed(rest) omit:NO] firstObject];
	if (clause == nil && !ORMHasPrefix(rest, @"at most one ")) {
		clause = [self newClause:rest subject:nil];
	}
	if (clause != nil) {
		NSMutableArray *named = [NSMutableArray array];
		NSMutableArray *others = [NSMutableArray array];
		for (ORMSentenceTerm *term in clause.terms) {
			BOOL listed = [names containsObject:term.name];
			if (listed && ([term.quantifier isEqualToString:@"that"] || term.quantifier == nil)) {
				[named addObject:term];
			} else {
				[others addObject:term];
			}
		}
		if ([named count] > 0 && [others count] > 0) {
			NSString *quantifier = [[others firstObject] quantifier];
			NSArray *roles = [named valueForKey:@"role"];
			if ([others count] == 1 && [quantifier isEqualToString:@"at most one"]) {
				[self add:ORMMakeConstraint(ORMUniquenessConstraint, @[ roles ])];
				return YES;
			}
			if ([others count] == 1 && [quantifier isEqualToString:@"exactly one"] && [roles count] == 1) {
				[self add:ORMMakeConstraint(ORMUniquenessConstraint, @[ roles ])];
				[self add:ORMMakeConstraint(ORMMandatoryConstraint, @[ roles ])];
				return YES;
			}
			if ([roles count] == 1) {
				BOOL allSome = YES;
				for (ORMSentenceTerm *other in others) {
					allSome = allSome && [other.quantifier isEqualToString:@"some"];
				}
				if (allSome) {
					[self add:ORMMakeConstraint(ORMMandatoryConstraint, @[ roles ])];
					return YES;
				}
			}
		}
	}
	/* External uniqueness: "at most one Region is part of that Country and
	 * has that RegionISOCode". */
	if (!ORMHasPrefix(rest, @"at most one ")) {
		return [self fail:@"Only uniqueness is understood after \"For each\"."];
	}
	NSString *joinedName = [self leadingName:[rest substringFromIndex:[@"at most one " length]]];
	NSMutableArray *roles = [NSMutableArray array];
	for (NSString *part in [rest componentsSeparatedByString:@" and "]) {
		ORMSentenceClause *each = [self clause:part subject:joinedName];
		ORMSentenceTerm *joined = [each termNamed:joinedName];
		if (joined == nil) {
			return [self fail:[NSString stringWithFormat:@"\"%@\" is not about %@.", part, joinedName]];
		}
		NSArray *others = [each termsOtherThan:joined];
		for (ORMSentenceTerm *term in others) {
			if ([names containsObject:term.name]) {
				[roles addObject:term.role];
			}
		}
		/* A unary ("...and is board meeting"): its implicit role. */
		if ([others count] == 0 && [each.factType isUnary]) {
			for (ORMRole *role in each.factType.roles) {
				if (role.player.isImplicitBooleanValue) {
					ORMSentenceRole *implicit = [[ORMSentenceRole alloc] init];
					implicit.role = role;
					[roles addObject:implicit];
				}
			}
		}
	}
	if ([roles count] < 2) {
		return [self fail:@"An external uniqueness constraint spans two roles or more."];
	}
	[self add:ORMMakeConstraint(ORMUniquenessConstraint, @[ roles ])];
	return YES;
}

/* "In each population of Person speaks Language, each Person, Language
 * combination occurs at most once." */
- (BOOL)population:(NSString *)text
{
	NSRange each = [text rangeOfString:@", each "];
	if (each.location == NSNotFound || ![text hasSuffix:@" combination occurs at most once"]) {
		return [self fail:@"Say which combination occurs at most once."];
	}
	ORMSentenceClause *clause = [self clause:[text substringToIndex:each.location] subject:nil];
	if (clause == nil) {
		return [self fail:@"No fact type reads so."];
	}
	[self add:ORMMakeConstraint(ORMUniquenessConstraint, @[ [clause.terms valueForKey:@"role"] ])];
	return YES;
}

/* "The possible values of Gender are 'M', 'F'": the verbalizer's ranges
 * ("0 to 140", "at least 18", "above 0 to below 100") as the editor's. */
- (BOOL)values:(NSString *)text
{
	NSRegularExpression *form = [NSRegularExpression
		regularExpressionWithPattern:@"^The possible values? of (.+?)(?: in the context of (.+))? (?:are|is) (.+)$"
		                     options:0
		                       error:NULL];
	NSTextCheckingResult *result = [form firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
	if (result == nil) {
		return [self fail:@"Say \"The possible values of X are ...\"."];
	}
	NSString *name = [text substringWithRange:[result rangeAtIndex:1]];
	NSString *list = [text substringWithRange:[result rangeAtIndex:3]];
	/* Items between commas outside quotes. */
	NSMutableArray *items = [NSMutableArray array];
	NSMutableString *item = [NSMutableString string];
	BOOL quoted = NO;
	for (NSUInteger i = 0; i < [list length]; i++) {
		unichar c = [list characterAtIndex:i];
		if (c == '\'') {
			quoted = !quoted;
		}
		if (c == ',' && !quoted) {
			[items addObject:ORMTrimmed(item)];
			[item setString:@""];
			continue;
		}
		[item appendFormat:@"%C", c];
	}
	[items addObject:ORMTrimmed(item)];
	NSMutableArray *ranges = [NSMutableArray array];
	BOOL bracketed = NO;
	for (NSString *each in items) {
		NSString *range = each;
		NSArray *forms = @[ @[ @"^above (.+) to below (.+)$", @"(%@..%@)" ], @[ @"^above (.+) to (.+)$", @"(%@..%@]" ],
		                    @[ @"^(.+) to below (.+)$", @"[%@..%@)" ], @[ @"^(.+) to (.+)$", @"%@..%@" ],
		                    @[ @"^at least (.+)$", @"%@.." ], @[ @"^above (.+)$", @"(%@.." ],
		                    @[ @"^at most (.+)$", @"..%@" ], @[ @"^below (.+)$", @"..%@)" ] ];
		for (NSArray *pair in forms) {
			NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:[pair firstObject]
			                                                                             options:0
			                                                                               error:NULL];
			NSTextCheckingResult *match = [expression firstMatchInString:each options:0 range:NSMakeRange(0, [each length])];
			if (match != nil) {
				NSString *a = [each substringWithRange:[match rangeAtIndex:1]];
				NSString *b = [match numberOfRanges] > 2 ? [each substringWithRange:[match rangeAtIndex:2]] : nil;
				range = b != nil ? [NSString stringWithFormat:[pair lastObject], a, b]
				                 : [NSString stringWithFormat:[pair lastObject], a];
				bracketed = bracketed || [range hasPrefix:@"("] || [range hasPrefix:@"["] || [range hasSuffix:@")"];
				break;
			}
		}
		[ranges addObject:range];
	}
	/* A value constraint: its values say so, not its kind. */
	ORMSentenceConstraint *constraint = ORMMakeConstraint(ORMValueComparisonConstraint, @[]);
	constraint.values = [ranges count] == 1 && bracketed
		? [ranges firstObject] : [NSString stringWithFormat:@"{%@}", [ranges componentsJoinedByString:@", "]];
	if ([result rangeAtIndex:2].location != NSNotFound) {
		ORMSentenceClause *clause = [self clause:[text substringWithRange:[result rangeAtIndex:2]] subject:nil];
		ORMSentenceTerm *term = [clause termNamed:name];
		if (term == nil) {
			return [self fail:[NSString stringWithFormat:@"%@ plays no role there.", name]];
		}
		constraint.valuesOfRole = term.role;
	} else {
		constraint.valuesOfObjectType = name;
	}
	[self add:constraint];
	return YES;
}

#pragma mark The sentence

+ (instancetype)sentenceWithString:(NSString *)input model:(ORMModel *)model reason:(NSString **)reason
{
	ORMConstraintSentence *sentence = [[self alloc] init];
	sentence->_model = model;
	sentence->_facts = [NSMutableArray array];
	sentence->_constraints = [NSMutableArray array];
	NSString *text = ORMTrimmed(input ?: @"");
	while ([text hasSuffix:@"."]) {
		text = ORMTrimmed([text substringToIndex:[text length] - 1]);
	}
	NSRegularExpression *spaces = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:NULL];
	text = [spaces stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, [text length]) withTemplate:@" "];
	if (ORMHasPrefix(text, @"It is obligatory that ")) {
		sentence->_modality = ORMDeontic;
		text = [text substringFromIndex:[@"It is obligatory that " length]];
		text = [[[text substringToIndex:MIN((NSUInteger)1, [text length])] uppercaseString]
			stringByAppendingString:[text substringFromIndex:MIN((NSUInteger)1, [text length])]];
	}
	BOOL understood = NO;
	if (ORMHasPrefix(text, @"The possible value")) {
		understood = [sentence values:text];
	} else if (ORMHasPrefix(text, @"In each population of ")) {
		understood = [sentence population:[text substringFromIndex:[@"In each population of " length]]];
	} else if (ORMHasPrefix(text, @"For each ")) {
		understood = [sentence forEach:[text substringFromIndex:[@"For each " length]]];
	} else if (ORMHasPrefix(text, @"No ")) {
		understood = [sentence no:[text substringFromIndex:[@"No " length]]];
	} else if (ORMHasPrefix(text, @"If ")) {
		understood = [sentence ifThen:[text substringFromIndex:[@"If " length]]];
	} else if (ORMHasPrefix(text, @"Each ") || [text rangeOfString:@" each "].location != NSNotFound) {
		/* "Tickets for each Booking are ...": a reading with text first. */
		understood = [sentence each:text];
	} else {
		sentence->_reason = @"A constraint starts \"Each\", \"For each\", \"No\", \"If\", \"In each population of\" "
		                    @"or \"The possible values of\".";
	}
	if (!understood || [sentence->_constraints count] == 0) {
		if (reason != NULL) {
			*reason = sentence->_reason ?: @"The sentence says no constraint.";
		}
		return nil;
	}
	return sentence;
}

- (NSArray<ORMSentenceConstraint *> *)constraints
{
	return [_constraints copy];
}

- (NSArray<ORMSentenceFact *> *)factTypes
{
	/* Only the fact types a constraint is over. */
	NSMutableArray *used = [NSMutableArray array];
	for (ORMSentenceConstraint *constraint in _constraints) {
		NSMutableArray *roles = [NSMutableArray array];
		for (NSArray *sequence in constraint.sequences) {
			[roles addObjectsFromArray:sequence];
		}
		if (constraint.valuesOfRole != nil) {
			[roles addObject:constraint.valuesOfRole];
		}
		for (ORMSentenceRole *role in roles) {
			if (role.fact != nil && [used indexOfObjectIdenticalTo:role.fact] == NSNotFound) {
				[used addObject:role.fact];
			}
		}
	}
	return used;
}

@end

@implementation ORMEditor (ORMConstraintSentences)

- (NSArray<NSString *> *)addFromSentence:(NSString *)text
                               onDiagram:(NSString *)diagramId
                                      at:(NSPoint)point
                                  reason:(NSString **)reason
{
	NSString *why = nil;
	ORMConstraintSentence *sentence = [ORMConstraintSentence sentenceWithString:text model:self.model reason:&why];
	NSString *trimmed = ORMTrimmed(text ?: @"");
	BOOL constraintLike = NO;
	for (NSString *lead in @[ @"Each ", @"For each ", @"No ", @"If ", @"In each population of ", @"The possible value",
	                          @"It is obligatory that " ]) {
		constraintLike = constraintLike || ORMHasPrefix(trimmed, lead);
	}
	if (sentence == nil && constraintLike) {
		if (reason != NULL) {
			*reason = why;
		}
		return nil;
	}
	if (sentence == nil) {
		/* Not a constraint: perhaps a fact type, as the Fact Editor takes it. */
		NSString *factWhy = nil;
		NSString *fact = [self addFactTypeFromSentence:text onDiagram:diagramId at:point reason:&factWhy];
		if (fact != nil) {
			return @[ fact ];
		}
		if (reason != NULL) {
			*reason = why;
		}
		return nil;
	}
	NSMutableArray *made = [NSMutableArray array];
	__block NSString *failure = nil;
	[self group:@"Add from Sentence" with:^{
		/* The fact types first, and the object types they need. */
		NSMapTable *factIds = [NSMapTable strongToStrongObjectsMapTable];
		for (ORMSentenceFact *fact in sentence.factTypes) {
			NSMutableArray *players = [NSMutableArray array];
			for (NSString *name in fact.playerNames) {
				NSString *identifier = [[self.model objectTypeNamed:name] identifier];
				if (identifier == nil) {
					identifier = [self addEntityTypeNamed:name referenceMode:nil kind:ORMReferenceModeNone
					                            onDiagram:diagramId at:ORMAutomaticPlacement reason:&failure];
					if (identifier == nil) {
						return;
					}
					[made addObject:identifier];
				}
				[players addObject:identifier];
			}
			NSString *factId = [self addFactTypeWithPlayers:players reading:fact.reading onDiagram:diagramId
			                                             at:point reason:&failure];
			if (factId == nil) {
				return;
			}
			[made addObject:factId];
			[factIds setObject:factId forKey:fact];
		}
		NSString *(^roleId)(ORMSentenceRole *) = ^NSString *(ORMSentenceRole *role) {
			if (role.role != nil) {
				return role.role.identifier;
			}
			ORMFactType *fact = [self.model elementWithId:[factIds objectForKey:role.fact]];
			NSArray *roles = [fact visibleRoles];
			return role.index < [roles count] ? [[roles objectAtIndex:role.index] identifier] : nil;
		};
		for (ORMSentenceConstraint *constraint in sentence.constraints) {
			NSMutableArray *sequences = [NSMutableArray array];
			for (NSArray *sequence in constraint.sequences) {
				NSMutableArray *ids = [NSMutableArray array];
				for (ORMSentenceRole *role in sequence) {
					NSString *identifier = roleId(role);
					if (identifier != nil) {
						[ids addObject:identifier];
					}
				}
				[sequences addObject:ids];
			}
			NSArray *first = [sequences firstObject];
			NSString *created = nil;
			if (constraint.values != nil) {
				NSString *target = constraint.valuesOfRole != nil ? roleId(constraint.valuesOfRole)
					: [[self.model objectTypeNamed:constraint.valuesOfObjectType] identifier];
				if (target == nil && constraint.valuesOfRole == nil) {
					/* Values belong to a value type: text when they are
					 * quoted, numbers when not. */
					BOOL text = [constraint.values rangeOfString:@"'"].location != NSNotFound;
					target = [self addValueTypeNamed:constraint.valuesOfObjectType
					                        dataType:text ? @"VariableLengthTextDataType" : @"DecimalNumericDataType"
					                       onDiagram:diagramId
					                              at:ORMAutomaticPlacement
					                          reason:&failure];
					if (target != nil) {
						[made addObject:target];
					}
				}
				if (target == nil || ![self setValueConstraint:constraint.values of:target reason:&failure]) {
					failure = failure ?: [NSString stringWithFormat:@"No object type is named %@.",
					                                                constraint.valuesOfObjectType];
					return;
				}
				continue;
			}
			/* What the model says already is not said twice. */
			if ([first count] == 1 && [sequences count] == 1) {
				ORMRole *role = [self.model elementWithId:[first firstObject]];
				if ((constraint.kind == ORMUniquenessConstraint && role.isUnique)
				    || (constraint.kind == ORMMandatoryConstraint && !constraint.isExclusiveOr && role.isMandatory)) {
					continue;
				}
			}
			switch (constraint.kind) {
			case ORMUniquenessConstraint:
				created = [self addUniquenessConstraintOverRoles:first reason:&failure];
				break;
			case ORMMandatoryConstraint:
				created = constraint.isExclusiveOr ? [self addExclusiveOrConstraintOverRoles:first reason:&failure]
				                                   : [self addMandatoryConstraintOverRoles:first reason:&failure];
				break;
			case ORMRingConstraint:
				created = [self addRingConstraint:constraint.ringType overRoles:first reason:&failure];
				break;
			case ORMSubsetConstraint:
			case ORMEqualityConstraint:
			case ORMExclusionConstraint:
				created = [self addSetComparisonConstraint:constraint.kind sequences:sequences reason:&failure];
				break;
			default:
				failure = @"That kind of constraint cannot be added from a sentence yet.";
				break;
			}
			if (created == nil) {
				return;
			}
			if (sentence.modality == ORMDeontic) {
				[self setModality:ORMDeontic of:created reason:NULL];
			}
			[made addObject:created];
		}
	}];
	if (failure != nil) {
		if (reason != NULL) {
			*reason = failure;
		}
		/* What was made before the failure stays undoable as the step. */
	}
	return [made count] > 0 ? made : (failure == nil ? @[] : nil);
}

@end
