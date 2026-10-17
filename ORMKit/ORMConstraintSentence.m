/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMConstraintSentence.h"
#import "ORMSentenceEditor.h"
#import "ORMFactSentence.h"
#import "ORMJoinPathBuilder.h"
#import "ORMReadingText.h"
#import "ORMXML.h"

/* The quantifiers the verbalizer puts before a name, tried in this order:
 * '#' is a number, a space one space; letters in any case. */
static const char *const ORMQuantifiers[] = {
	"the same", "more than one", "at least # and at most #", "at most one", "exactly one", "at least one",
	"at least #", "at most #", "exactly #", "each", "some", "that", "no", "an", "a", NULL
};

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

@interface ORMSentencePath ()
@property (nonatomic, readwrite, copy) NSArray<NSArray<ORMSentenceRole *> *> *atomRoles;
@property (nonatomic, readwrite, copy) NSArray<NSArray<NSString *> *> *atomVariables;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *columns;
@end

@implementation ORMSentencePath
@end

@interface ORMSentenceConstraint ()
@property (nonatomic, readwrite, copy) NSArray *paths;
@property (nonatomic, readwrite) ORMConstraintKind kind;
@property (nonatomic, readwrite, copy) NSArray<NSArray<ORMSentenceRole *> *> *sequences;
@property (nonatomic, readwrite) ORMRingType ringType;
@property (nonatomic, readwrite) BOOL isExclusiveOr;
@property (nonatomic, readwrite, copy) NSString *values;
@property (nonatomic, readwrite, copy) NSString *valuesOfObjectType;
@property (nonatomic, readwrite, strong) ORMSentenceRole *valuesOfRole;
@property (nonatomic, readwrite, copy) NSString *comparisonOperator;
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
/* How much of the text the clause took, in a chain. */
@property (nonatomic) NSUInteger consumed;
/* The reading ends at its last placeholder: a relative clause can go on
 * from that term ("...some LotType that tracks lot numbers"). */
@property (nonatomic) BOOL endsWithTerm;
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

/* The names a role's player may go by in a sentence: its own, a
 * subtype's (a subset's "that Ambassador represents" for a Diplomat's
 * role) or a supertype's (an exclusion's "that Employee is ceo" for a
 * Manager's), longest first, each optionally numbered. A reading naming
 * the player itself is preferred (see match:omit:). */
/* The start of a word ending the text, nothing but whitespace before it
 * from end on; NSNotFound where there is none. */
static NSUInteger
ORMWordBefore(NSString *text, NSUInteger end)
{
	NSUInteger start = end;
	while (start > 0 && !ORMIsWhitespace([text characterAtIndex:start - 1])) {
		start--;
	}
	return start < end ? start : NSNotFound;
}

/* Where " and X is not Y" ends the text, X and Y single words; NSNotFound
 * where it does not. */
static NSUInteger
ORMAndIsNotAt(NSString *text)
{
	NSUInteger y = ORMWordBefore(text, [text length]);
	if (y == NSNotFound || y < [@" is not " length]
	    || ![[text substringWithRange:NSMakeRange(y - 8, 8)] isEqualToString:@" is not "]) {
		return NSNotFound;
	}
	NSUInteger x = ORMWordBefore(text, y - 8);
	if (x == NSNotFound || x < [@" and " length] || ![[text substringWithRange:NSMakeRange(x - 5, 5)] isEqualToString:@" and "]) {
		return NSNotFound;
	}
	return x - 5;
}

/* The text after the prefix, split at the last place the separator is
 * found with something on both sides: @[ before, after ]; nil where it is
 * not ("above 0 to below 100" by "above " and " to below "). */
static NSArray<NSString *> *
ORMSplitAfter(NSString *text, NSString *prefix, NSString *separator)
{
	/* -hasPrefix: is NO for the empty string on Apple. */
	if ([prefix length] > 0 && ![text hasPrefix:prefix]) {
		return nil;
	}
	NSString *rest = [text substringFromIndex:[prefix length]];
	if (separator == nil) {
		return [rest length] > 0 ? @[ rest ] : nil;
	}
	/* The last place with something after it, as a greedy match takes. */
	NSRange within = NSMakeRange(0, [rest length]);
	for (;;) {
		NSRange at = [rest rangeOfString:separator options:NSBackwardsSearch range:within];
		if (at.location == NSNotFound || at.location == 0) {
			return nil;
		}
		if (NSMaxRange(at) < [rest length]) {
			return @[ [rest substringToIndex:at.location], [rest substringFromIndex:NSMaxRange(at)] ];
		}
		within = NSMakeRange(0, NSMaxRange(at) - 1);
	}
}

/* "The possible values of X [in the context of C] are L": @[ X, C or
 * NSNull, L ], X as short as the rest lets it be; nil where it does not
 * read so. */
static NSArray *
ORMValuesForm(NSString *text)
{
	NSString *rest = nil;
	for (NSString *prefix in @[ @"The possible values of ", @"The possible value of " ]) {
		rest = rest ?: ([text hasPrefix:prefix] ? [text substringFromIndex:[prefix length]] : nil);
	}
	for (NSUInteger end = 1; rest != nil && end < [rest length]; end++) {
		NSString *after = [rest substringFromIndex:end];
		NSString *context = @" in the context of ";
		if ([after hasPrefix:context]) {
			/* The context as long as it can be. */
			NSString *tail = [after substringFromIndex:[context length]];
			for (NSUInteger at = [tail length]; at-- > 1;) {
				for (NSString *verb in @[ @" are ", @" is " ]) {
					if ([tail length] > at + [verb length] && [[tail substringFromIndex:at] hasPrefix:verb]) {
						return @[ [rest substringToIndex:end], [tail substringToIndex:at],
							      [tail substringFromIndex:at + [verb length]] ];
					}
				}
			}
		}
		for (NSString *verb in @[ @" are ", @" is " ]) {
			if ([after length] > [verb length] && [after hasPrefix:verb]) {
				return @[ [rest substringToIndex:end], [NSNull null], [after substringFromIndex:[verb length]] ];
			}
		}
	}
	return nil;
}

/* The text with each run of whitespace one space. */
static NSString *
ORMSingleSpaced(NSString *text)
{
	NSMutableString *out = [NSMutableString string];
	BOOL spaced = NO;
	for (NSUInteger i = 0; i < [text length]; i++) {
		unichar c = [text characterAtIndex:i];
		if (ORMIsWhitespace(c)) {
			if (!spaced) {
				[out appendString:@" "];
			}
			spaced = YES;
			continue;
		}
		spaced = NO;
		[out appendFormat:@"%C", c];
	}
	return out;
}

#pragma mark Matching a reading, in C

/* A reading as its clauses are matched (what a regular expression did
 * before, compiled for each one): literal characters, any run of
 * whitespace matching any run, and for each placeholder an optional
 * quantifier and one of its player's names, optionally numbered. Matched
 * over a clause's characters, trying what comes first first and going back
 * where what follows fails, as the expression did. */
typedef NS_ENUM(uint8_t, ORMAtomKind) {
	ORMAtomCharacter,
	/* One or more whitespace characters. */
	ORMAtomSpaces,
	/* A placeholder's quantifier, maybe, and whitespace after it. */
	ORMAtomQuantifier,
	/* A placeholder's name, and a number maybe. */
	ORMAtomName,
	/* The end: of the text, or of a clause a connector follows. */
	ORMAtomEnd,
};

typedef struct {
	ORMAtomKind kind;
	unichar character;
	/* A quantifier's or a name's placeholder: its part's index. */
	NSUInteger part;
} ORMAtom;

/* A placeholder's names, as characters. */
typedef struct {
	NSUInteger count;
	unichar **names;
	NSUInteger *lengths;
} ORMNameSet;

typedef struct {
	const ORMAtom *atoms;
	const unichar *text;
	NSUInteger length;
	/* A clause of a chain: it may end where a connector follows. */
	BOOL prefix;
	const ORMNameSet *names;
	/* Each part's quantifier and name, where the match took them. */
	NSRange *quantifiers;
	NSRange *namesTaken;
} ORMMatch;

static BOOL
ORMIsDigit(unichar c)
{
	return c >= '0' && c <= '9';
}

static NSUInteger
ORMSpacesAt(const unichar *text, NSUInteger length, NSUInteger at)
{
	NSUInteger end = at;
	while (end < length && ORMIsWhitespace(text[end])) {
		end++;
	}
	return end - at;
}

/* Where the quantifier form may end, matched at the place: the ends a
 * number's digits leave, most digits first, into ends; how many. */
static NSUInteger
ORMQuantifierEnds(const char *form, const unichar *text, NSUInteger length, NSUInteger at, NSUInteger *ends,
                  NSUInteger room)
{
	if (room == 0) {
		return 0;
	}
	if (*form == '\0') {
		ends[0] = at;
		return 1;
	}
	if (*form == '#') {
		NSUInteger digits = 0;
		while (at + digits < length && ORMIsDigit(text[at + digits])) {
			digits++;
		}
		NSUInteger found = 0;
		for (NSUInteger taken = digits; taken >= 1 && found < room; taken--) {
			found += ORMQuantifierEnds(form + 1, text, length, at + taken, ends + found, room - found);
		}
		return found;
	}
	if (at >= length) {
		return 0;
	}
	unichar c = text[at];
	if (*form == ' ' ? c != ' ' : (c >= 128 || tolower((int)c) != *form)) {
		return 0;
	}
	return ORMQuantifierEnds(form + 1, text, length, at + 1, ends, room);
}

/* Whether the phrase is a quantifier, whole. */
static BOOL
ORMIsQuantifier(NSString *phrase)
{
	NSUInteger length = [phrase length];
	unichar *text = malloc(sizeof(unichar) * (length + 1));
	[phrase getCharacters:text range:NSMakeRange(0, length)];
	BOOL whole = NO;
	for (NSUInteger q = 0; ORMQuantifiers[q] != NULL && !whole; q++) {
		NSUInteger ends[16];
		NSUInteger count = ORMQuantifierEnds(ORMQuantifiers[q], text, length, 0, ends, 16);
		for (NSUInteger i = 0; i < count; i++) {
			whole = whole || ends[i] == length;
		}
	}
	free(text);
	return whole;
}

/* Whether a clause of a chain may end here: whitespace, then a connector
 * and whitespace; or nothing but whitespace. */
static BOOL
ORMEndsClause(const unichar *text, NSUInteger length, NSUInteger at)
{
	NSUInteger spaces = ORMSpacesAt(text, length, at);
	if (at + spaces == length) {
		return YES;
	}
	if (spaces == 0) {
		return NO;
	}
	NSUInteger word = at + spaces;
	for (NSString *connector in @[ @"and", @"that", @"who" ]) {
		NSUInteger n = [connector length];
		BOOL same = word + n < length && ORMIsWhitespace(text[word + n]);
		for (NSUInteger i = 0; same && i < n; i++) {
			same = text[word + i] == [connector characterAtIndex:i];
		}
		if (same) {
			return YES;
		}
	}
	return NO;
}

/* The rest of the atoms matched from the place: where the match ends, or
 * NSNotFound. */
static NSUInteger
ORMMatchAtoms(ORMMatch *match, NSUInteger atom, NSUInteger at)
{
	const ORMAtom *a = &match->atoms[atom];
	const unichar *text = match->text;
	NSUInteger length = match->length;
	switch (a->kind) {
	case ORMAtomCharacter:
		return at < length && text[at] == a->character ? ORMMatchAtoms(match, atom + 1, at + 1) : NSNotFound;
	case ORMAtomSpaces: {
		NSUInteger spaces = ORMSpacesAt(text, length, at);
		for (NSUInteger taken = spaces; taken >= 1; taken--) {
			NSUInteger end = ORMMatchAtoms(match, atom + 1, at + taken);
			if (end != NSNotFound) {
				return end;
			}
		}
		return NSNotFound;
	}
	case ORMAtomQuantifier:
		for (NSUInteger q = 0; ORMQuantifiers[q] != NULL; q++) {
			NSUInteger ends[16];
			NSUInteger count = ORMQuantifierEnds(ORMQuantifiers[q], text, length, at, ends, 16);
			for (NSUInteger i = 0; i < count; i++) {
				NSUInteger spaces = ORMSpacesAt(text, length, ends[i]);
				for (NSUInteger taken = spaces; taken >= 1; taken--) {
					match->quantifiers[a->part] = NSMakeRange(at, ends[i] - at);
					NSUInteger end = ORMMatchAtoms(match, atom + 1, ends[i] + taken);
					if (end != NSNotFound) {
						return end;
					}
				}
			}
		}
		match->quantifiers[a->part] = NSMakeRange(NSNotFound, 0);
		return ORMMatchAtoms(match, atom + 1, at);
	case ORMAtomName: {
		const ORMNameSet *names = &match->names[a->part];
		for (NSUInteger n = 0; n < names->count; n++) {
			NSUInteger name = names->lengths[n];
			if (at + name > length || memcmp(text + at, names->names[n], name * sizeof(unichar)) != 0) {
				continue;
			}
			NSUInteger digits = 0;
			while (at + name + digits < length && ORMIsDigit(text[at + name + digits])) {
				digits++;
			}
			for (NSUInteger taken = digits + 1; taken-- > 0;) {
				match->namesTaken[a->part] = NSMakeRange(at, name + taken);
				NSUInteger end = ORMMatchAtoms(match, atom + 1, at + name + taken);
				if (end != NSNotFound) {
					return end;
				}
			}
		}
		return NSNotFound;
	}
	case ORMAtomEnd:
		if (match->prefix) {
			return ORMEndsClause(text, length, at) ? at : NSNotFound;
		}
		return at + ORMSpacesAt(text, length, at) == length ? length : NSNotFound;
	}
	return NSNotFound;
}

/* A literal's atoms: its characters, each run of whitespace one atom. */
static void
ORMAddLiteral(NSMutableData *atoms, NSString *literal)
{
	NSUInteger length = [literal length];
	for (NSUInteger i = 0; i < length; i++) {
		unichar c = [literal characterAtIndex:i];
		ORMAtom atom = { ORMIsWhitespace(c) ? ORMAtomSpaces : ORMAtomCharacter, c, 0 };
		while (atom.kind == ORMAtomSpaces && i + 1 < length && ORMIsWhitespace([literal characterAtIndex:i + 1])) {
			i++;
		}
		[atoms appendBytes:&atom length:sizeof(atom)];
	}
}

static void
ORMAddAtom(NSMutableData *atoms, ORMAtomKind kind, NSUInteger part)
{
	ORMAtom atom = { kind, 0, part };
	[atoms appendBytes:&atom length:sizeof(atom)];
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
	/* Matching a clause at the start of a chain, not the whole text. */
	BOOL _prefixMode;
	ORMModel *_model;
	NSMutableArray<ORMSentenceFact *> *_facts;
	NSMutableArray<ORMSentenceConstraint *> *_constraints;
	NSString *_reason;
}

#pragma mark Clauses

/* The names the player may go by in a sentence: its family's
 * (ORMObjectType's familyNames); "?" for a placeholder of no player. */
static NSArray<NSString *> *
ORMNamesOf(ORMObjectType *player)
{
	return [player.familyNames count] > 0 ? player.familyNames : @[ @"?" ];
}

/* A reading's atoms: each placeholder an optionally quantified,
 * optionally numbered name, the first left out when omit is set; nil for
 * one that cannot be matched so. */
- (NSData *)atomsOf:(ORMReadingText *)reading omit:(BOOL)omit
{
	if ([reading.parts count] == 0 || (omit && [ORMTrimmed(reading.frontText) length] > 0)) {
		return nil;
	}
	NSMutableData *atoms = [NSMutableData data];
	ORMAddLiteral(atoms, reading.frontText);
	for (NSUInteger i = 0; i < [reading.parts count]; i++) {
		ORMReadingPart *part = [reading.parts objectAtIndex:i];
		if (i == 0 && omit) {
			ORMAddLiteral(atoms, [part.followingText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]);
			if ([part.followingText hasSuffix:@" "]) {
				ORMAddAtom(atoms, ORMAtomSpaces, 0);
			}
			continue;
		}
		ORMAddAtom(atoms, ORMAtomQuantifier, i);
		ORMAddLiteral(atoms, part.preBoundText);
		ORMAddAtom(atoms, ORMAtomName, i);
		ORMAddLiteral(atoms, part.postBoundText);
		ORMAddLiteral(atoms, part.followingText);
	}
	ORMAddAtom(atoms, ORMAtomEnd, 0);
	return atoms;
}

/* The reading matched to the text, from its start: where the match ends,
 * and each part's quantifier and name; NSNotFound where it does not. */
- (NSUInteger)match:(ORMReadingText *)reading
              roles:(NSArray<ORMRole *> *)roles
               omit:(BOOL)omit
               text:(const unichar *)text
             length:(NSUInteger)length
        quantifiers:(NSRange *)quantifiers
              names:(NSRange *)names
{
	/* Kept while C reads its bytes. */
	NSData *atoms __attribute__((objc_precise_lifetime)) = [self atomsOf:reading omit:omit];
	if (atoms == nil) {
		return NSNotFound;
	}
	NSUInteger parts = [reading.parts count];
	ORMNameSet *sets = calloc(parts, sizeof(ORMNameSet));
	for (NSUInteger i = 0; i < parts; i++) {
		ORMReadingPart *part = [reading.parts objectAtIndex:i];
		ORMRole *role = part.roleIndex < [roles count] ? [roles objectAtIndex:part.roleIndex] : nil;
		NSArray *each = ORMNamesOf(role.player);
		sets[i].count = [each count];
		sets[i].names = calloc([each count], sizeof(unichar *));
		sets[i].lengths = calloc([each count], sizeof(NSUInteger));
		for (NSUInteger n = 0; n < [each count]; n++) {
			NSString *name = [each objectAtIndex:n];
			sets[i].lengths[n] = [name length];
			sets[i].names[n] = malloc(sizeof(unichar) * ([name length] + 1));
			[name getCharacters:sets[i].names[n] range:NSMakeRange(0, [name length])];
		}
	}
	ORMMatch match = { [atoms bytes], text, length, _prefixMode, sets, quantifiers, names };
	/* From its start, whitespace before it left out. */
	NSUInteger end = ORMMatchAtoms(&match, 0, ORMSpacesAt(text, length, 0));
	for (NSUInteger i = 0; i < parts; i++) {
		for (NSUInteger n = 0; n < sets[i].count; n++) {
			free(sets[i].names[n]);
		}
		free(sets[i].names);
		free(sets[i].lengths);
	}
	free(sets);
	return end;
}

/* The readings to match a clause against: each reading of each fact type,
 * and a subtype fact's "{0} is {1}" either way. */
- (NSArray<NSArray *> *)readings
{
	NSMutableArray *readings = [NSMutableArray array];
	for (ORMFactType *fact in _model.factTypes) {
		if ([fact subtypeReadingRolesFrom:nil] != nil) {
			for (ORMRole *role in fact.roles) {
				[readings addObject:@[ fact, ORMSubtypeReadingText, [fact subtypeReadingRolesFrom:role] ]];
			}
			continue;
		}
		/* An objectification's link fact types read too ("...is involved
		 * in some Service"). */
		if (fact.kind != ORMFactTypeOrdinary && fact.kind != ORMFactTypeImplied) {
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
					[readings addObject:@[ fact, reading.text, order.roles, reading ]];
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
	NSUInteger length = [text length];
	unichar *chars = malloc(sizeof(unichar) * (length + 1));
	[text getCharacters:chars range:NSMakeRange(0, length)];
	for (NSArray *candidate in [self readings]) @autoreleasepool {
		ORMFactType *fact = [candidate objectAtIndex:0];
		NSString *reading = [candidate objectAtIndex:1];
		NSArray *roles = [candidate objectAtIndex:2];
		/* A reading whose own words the clause lacks cannot match it. */
		BOOL possible = YES;
		NSArray *words = [candidate count] > 3 ? [(ORMReading *)[candidate objectAtIndex:3] words]
		                                       : [ORMReadingText wordsOf:reading];
		for (NSString *word in words) {
			if ([word rangeOfString:@"-"].location == NSNotFound && [text rangeOfString:word].location == NSNotFound) {
				possible = NO;
				break;
			}
		}
		if (!possible) {
			continue;
		}
		ORMReadingText *parsed = [candidate count] > 3 ? [(ORMReading *)[candidate objectAtIndex:3] parsedText]
		                                               : [ORMReadingText readingTextWithString:reading arity:[roles count]
		                                                                                reason:NULL];
		NSUInteger parts = [parsed.parts count];
		NSRange *quantifiers = calloc(parts + 1, sizeof(NSRange));
		NSRange *names = calloc(parts + 1, sizeof(NSRange));
		NSUInteger end = parsed != nil ? [self match:parsed roles:roles omit:omit text:chars length:length
		                                 quantifiers:quantifiers
		                                       names:names]
		                               : NSNotFound;
		if (end != NSNotFound) {
			NSMutableArray *terms = [NSMutableArray array];
			for (NSUInteger i = 0; i < parts; i++) {
				ORMReadingPart *part = [parsed.parts objectAtIndex:i];
				ORMSentenceTerm *term = [[ORMSentenceTerm alloc] init];
				term.role = [[ORMSentenceRole alloc] init];
				term.role.role = [roles objectAtIndex:part.roleIndex];
				if (i == 0 && omit) {
					term.omitted = YES;
					term.name = term.role.role.player.name;
				} else {
					term.quantifier = quantifiers[i].location != NSNotFound
						? [[text substringWithRange:quantifiers[i]] lowercaseString] : nil;
					term.name = [text substringWithRange:names[i]];
				}
				[terms addObject:term];
			}
			ORMSentenceClause *clause = [[ORMSentenceClause alloc] init];
			clause.factType = fact;
			clause.terms = terms;
			clause.consumed = end;
			ORMReadingPart *last = [parsed.parts lastObject];
			clause.endsWithTerm = [ORMTrimmed(last.followingText) length] == 0 && [last.postBoundText length] == 0;
			[clauses addObject:clause];
		}
		free(quantifiers);
		free(names);
	}
	free(chars);
	return clauses;
}

/* A clause the model has no reading for: a fact type to make. The word
 * after a quantifier, and a known object type's name, are object types;
 * the subject, when the clause leaves it out, comes first. */
- (ORMSentenceClause *)newClause:(NSString *)text subject:(NSString *)subject
{
	NSArray *words = [ORMTrimmed(text) componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
	NSMutableArray *terms = [NSMutableArray array];
	NSMutableArray *reading = [NSMutableArray array];
	BOOL leftOut = subject != nil;
	for (NSUInteger i = 0; i < [words count]; i++) {
		/* A quantifier of up to six words, then a name. */
		NSString *found = nil;
		NSUInteger length = 0;
		for (NSUInteger n = MIN((NSUInteger)6, [words count] - i - 1); n >= 1 && found == nil; n--) {
			NSString *phrase = [[words subarrayWithRange:NSMakeRange(i, n)] componentsJoinedByString:@" "];
			if (ORMIsQuantifier(phrase)) {
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
			if ([player isCompatibleWith:type]) {
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

#pragma mark Chains

/* A side of a constraint as clauses: each the longest reading that
 * matches where the text goes on, joined by "that"/"who" (going on from
 * the object type the clause ended with) or "and" (a new clause, or going
 * on from the first's subject). Its terms' names are its variables: "some
 * Lot" ... "that Lot" is one Lot. nil when it does not read so. */
- (NSArray<ORMSentenceClause *> *)chain:(NSString *)text
{
	NSMutableArray *chain = [NSMutableArray array];
	NSString *rest = ORMTrimmed(text);
	NSString *head = nil;
	NSString *tail = nil;
	NSString *connector = nil;
	_prefixMode = YES;
	while ([rest length] > 0) {
		NSMutableArray *candidates = [NSMutableArray array];
		if (connector == nil || [connector isEqualToString:@"and"]) {
			[candidates addObjectsFromArray:[self match:rest omit:NO]];
		}
		NSString *subject = [connector isEqualToString:@"that"] ? tail : [connector isEqualToString:@"and"] ? head : nil;
		if (subject != nil) {
			ORMSentenceTerm *probe = [[ORMSentenceTerm alloc] init];
			probe.name = subject;
			ORMObjectType *type = [_model objectTypeNamed:[probe typeName]];
			for (ORMSentenceClause *clause in [self match:rest omit:YES]) {
				ORMSentenceTerm *first = [clause.terms firstObject];
				ORMObjectType *player = first.role.role.player;
				if ([player isCompatibleWith:type]) {
					first.name = subject;
					[candidates addObject:clause];
				}
			}
		}
		ORMSentenceClause *best = nil;
		for (ORMSentenceClause *clause in candidates) {
			if (best == nil || clause.consumed > best.consumed) {
				best = clause;
			}
		}
		if (best == nil) {
			_prefixMode = NO;
			return nil;
		}
		[chain addObject:best];
		if (head == nil) {
			head = [[best.terms firstObject] name];
		}
		tail = best.endsWithTerm ? [[best.terms lastObject] name] : nil;
		rest = ORMTrimmed([rest substringFromIndex:best.consumed]);
		if ([rest length] == 0) {
			break;
		}
		if (ORMHasPrefix(rest, @"that ") || ORMHasPrefix(rest, @"who ")) {
			if (tail == nil) {
				_prefixMode = NO;
				return nil;
			}
			connector = @"that";
			rest = [rest substringFromIndex:[rest rangeOfString:@" "].location + 1];
		} else if (ORMHasPrefix(rest, @"and ")) {
			connector = @"and";
			rest = [rest substringFromIndex:4];
		} else {
			_prefixMode = NO;
			return nil;
		}
	}
	_prefixMode = NO;
	return [chain count] > 0 ? chain : nil;
}

/* The variables a chain names, in the order it names them. */
static NSArray<NSString *> *
ORMChainVariables(NSArray<ORMSentenceClause *> *chain)
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMSentenceClause *clause in chain) {
		for (ORMSentenceTerm *term in clause.terms) {
			if (term.name != nil && ![names containsObject:term.name]) {
				[names addObject:term.name];
			}
		}
	}
	return names;
}

/* A sequence of a chain: the role where each column is first played; and
 * its path when the chain is of more than one clause. */
- (NSArray<ORMSentenceRole *> *)rolesOf:(NSArray<ORMSentenceClause *> *)chain columns:(NSArray<NSString *> *)columns
{
	NSMutableArray *roles = [NSMutableArray array];
	for (NSString *column in columns) {
		ORMSentenceRole *found = nil;
		for (ORMSentenceClause *clause in chain) {
			for (ORMSentenceTerm *term in clause.terms) {
				if (found == nil && [term.name isEqualToString:column]) {
					found = term.role;
				}
			}
		}
		if (found == nil) {
			return nil;
		}
		[roles addObject:found];
	}
	return roles;
}

- (id)pathOf:(NSArray<ORMSentenceClause *> *)chain columns:(NSArray<NSString *> *)columns
{
	if ([chain count] < 2) {
		return [NSNull null];
	}
	ORMSentencePath *path = [[ORMSentencePath alloc] init];
	NSMutableArray *roles = [NSMutableArray array];
	NSMutableArray *variables = [NSMutableArray array];
	for (ORMSentenceClause *clause in chain) {
		[roles addObject:[clause.terms valueForKey:@"role"]];
		[variables addObject:[clause.terms valueForKey:@"name"]];
	}
	path.atomRoles = roles;
	path.atomVariables = variables;
	path.columns = columns;
	return path;
}

/* A set comparison over chains, each a sequence of the columns. */
- (BOOL)compare:(ORMConstraintKind)kind chains:(NSArray<NSArray *> *)chains columns:(NSArray<NSString *> *)columns
{
	NSMutableArray *sequences = [NSMutableArray array];
	NSMutableArray *paths = [NSMutableArray array];
	BOOL joined = NO;
	for (NSArray *chain in chains) {
		NSArray *roles = [self rolesOf:chain columns:columns];
		if (roles == nil) {
			return [self fail:@"A side of the comparison does not name all it compares."];
		}
		[sequences addObject:roles];
		id path = [self pathOf:chain columns:columns];
		joined = joined || path != [NSNull null];
		[paths addObject:path];
	}
	ORMSentenceConstraint *constraint = ORMMakeConstraint(kind, sequences);
	constraint.paths = joined ? paths : nil;
	[self add:constraint];
	return YES;
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
	NSUInteger notSame = ORMAndIsNotAt(left);
	if (notSame != NSNotFound) {
		antisymmetric = YES;
		left = [left substringToIndex:notSame];
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
	/* Over join paths: each side a chain of clauses. */
	NSArray *leftChain = impossible ? nil : [self chain:left];
	NSArray *rightChain = impossible ? nil : [self chain:right];
	if (leftChain != nil && rightChain != nil && ([leftChain count] > 1 || [rightChain count] > 1)) {
		NSArray *introduced = ORMChainVariables(leftChain);
		NSMutableArray *columns = [NSMutableArray array];
		for (NSString *name in introduced) {
			if ([ORMChainVariables(rightChain) containsObject:name]) {
				[columns addObject:name];
			}
		}
		/* The verbalizer leaves out of the "then" only facts whose
		 * instances it names otherwise, so it names every column. */
		NSArray *superset = rightChain;
		[columns removeAllObjects];
		for (NSString *name in introduced) {
			if ([ORMChainVariables(superset) containsObject:name]) {
				[columns addObject:name];
			}
		}
		if ([columns count] == 0) {
			return [self fail:@"The \"then\" does not name again what the \"if\" introduced."];
		}
		return [self compare:ORMSubsetConstraint chains:@[ leftChain, superset ] columns:columns];
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
	if (ORMHasPrefix(rest, @"if ")) {
		return [self comparison:[rest substringFromIndex:[@"if " length]]];
	}
	BOOL exactlyOneHolds = ORMHasPrefix(rest, @"exactly one of the following holds: ");
	if (exactlyOneHolds || ORMHasPrefix(rest, @"at most one of the following holds: ")) {
		NSString *list = [rest substringFromIndex:[exactlyOneHolds ? @"exactly one of the following holds: "
		                                                             : @"at most one of the following holds: " length]];
		NSMutableArray *chains = [NSMutableArray array];
		NSMutableArray *sequences = [NSMutableArray array];
		for (NSString *part in [list componentsSeparatedByString:@"; "]) {
			NSArray *chain = [self chain:part];
			NSArray *roles = chain != nil ? [self rolesOf:chain columns:names] : nil;
			if (roles == nil) {
				return [self fail:[NSString stringWithFormat:@"\"%@\" does not name all of %@.", part,
				                                             [names componentsJoinedByString:@", "]]];
			}
			[chains addObject:chain];
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
			return [self compare:ORMExclusionConstraint chains:chains columns:names];
		}
		return YES;
	}
	/* Equality: "For each Patient, that Patient had some SystolicBP if and
	 * only if that Patient had some DiastolicBP". */
	NSRange iff = [rest rangeOfString:@" if and only if "];
	if (iff.location != NSNotFound) {
		NSMutableArray *chains = [NSMutableArray array];
		for (NSString *part in @[ [rest substringToIndex:iff.location], [rest substringFromIndex:NSMaxRange(iff)] ]) {
			NSArray *chain = [self chain:part];
			if (chain == nil) {
				return [self fail:[NSString stringWithFormat:@"\"%@\" is not of fact types the model has.", part]];
			}
			[chains addObject:chain];
		}
		return [self compare:ORMEqualityConstraint chains:chains columns:names];
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
		if ([others count] == 0 && [each.factType isUnary] && [each.factType implicitRole] != nil) {
			ORMSentenceRole *implicit = [[ORMSentenceRole alloc] init];
			implicit.role = [each.factType implicitRole];
			[roles addObject:implicit];
		}
	}
	if ([roles count] < 2) {
		return [self fail:@"An external uniqueness constraint spans two roles or more."];
	}
	[self add:ORMMakeConstraint(ORMUniquenessConstraint, @[ roles ])];
	return YES;
}

/* A value comparison, after "For each Project, if ": "that Project starts
 * on some Date1 and that Project ends on some Date2 then Date1 is less than
 * or equal to Date2". The values compared are the roles named "some". */
- (BOOL)comparison:(NSString *)text
{
	NSRange then = [text rangeOfString:@" then " options:NSBackwardsSearch];
	if (then.location == NSNotFound) {
		return [self fail:@"An \"if\" needs a \"then\"."];
	}
	NSString *condition = [text substringToIndex:then.location];
	NSString *comparison = [text substringFromIndex:NSMaxRange(then)];
	/* Longest first: "is less than or equal to" before "is less than". */
	NSArray *operators = @[ @[ @"is less than or equal to", @"LessThanOrEqual" ],
	                        @[ @"is greater than or equal to", @"GreaterThanOrEqual" ],
	                        @[ @"is not equal to", @"NotEqual" ], @[ @"is equal to", @"Equal" ],
	                        @[ @"is less than", @"LessThan" ], @[ @"is greater than", @"GreaterThan" ] ];
	NSString *operator = nil;
	NSArray *compared = nil;
	for (NSArray *pair in operators) {
		NSRange at = [comparison rangeOfString:[NSString stringWithFormat:@" %@ ", [pair firstObject]]];
		if (at.location != NSNotFound) {
			operator = [pair lastObject];
			compared = @[ ORMTrimmed([comparison substringToIndex:at.location]),
			              ORMTrimmed([comparison substringFromIndex:NSMaxRange(at)]) ];
			break;
		}
	}
	if (operator == nil) {
		return [self fail:@"Compare with \"is less than\", \"is equal to\", \"is greater than or equal to\", ..."];
	}
	NSMutableArray *clauses = [NSMutableArray array];
	for (NSString *part in [condition componentsSeparatedByString:@" and "]) {
		ORMSentenceClause *clause = [[self match:ORMTrimmed(part) omit:NO] firstObject];
		if (clause == nil) {
			return [self fail:[NSString stringWithFormat:@"\"%@\" is not a fact type the model has.", part]];
		}
		[clauses addObject:clause];
	}
	NSMutableArray *roles = [NSMutableArray array];
	for (NSString *name in compared) {
		ORMSentenceRole *role = nil;
		for (ORMSentenceClause *clause in clauses) {
			for (ORMSentenceTerm *term in clause.terms) {
				if ([term.quantifier isEqualToString:@"some"] && [term.name isEqualToString:name]) {
					role = term.role;
				}
			}
		}
		if (role == nil) {
			return [self fail:[NSString stringWithFormat:@"No \"some %@\" before the \"then\".", name]];
		}
		[roles addObject:role];
	}
	ORMSentenceConstraint *constraint = ORMMakeConstraint(ORMValueComparisonConstraint, @[ roles ]);
	constraint.comparisonOperator = operator;
	[self add:constraint];
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
	NSArray *form = ORMValuesForm(text);
	if (form == nil) {
		return [self fail:@"Say \"The possible values of X are ...\"."];
	}
	NSString *name = [form objectAtIndex:0];
	NSString *context = [form objectAtIndex:1] != [NSNull null] ? [form objectAtIndex:1] : nil;
	NSString *list = [form objectAtIndex:2];
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
		/* @[ before, between (none: one bound), what it is in the editor's
		 * words ], the first that reads. */
		NSArray *forms = @[ @[ @"above ", @" to below ", @"(%@..%@)" ], @[ @"above ", @" to ", @"(%@..%@]" ],
		                    @[ @"", @" to below ", @"[%@..%@)" ], @[ @"", @" to ", @"%@..%@" ],
		                    @[ @"at least ", [NSNull null], @"%@.." ], @[ @"above ", [NSNull null], @"(%@.." ],
		                    @[ @"at most ", [NSNull null], @"..%@" ], @[ @"below ", [NSNull null], @"..%@)" ] ];
		for (NSArray *pair in forms) {
			id between = [pair objectAtIndex:1];
			NSArray *match = ORMSplitAfter(each, [pair firstObject], between != [NSNull null] ? between : nil);
			if (match != nil) {
				NSString *a = [match firstObject];
				NSString *b = [match count] > 1 ? [match lastObject] : nil;
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
	if (context != nil) {
		ORMSentenceClause *clause = [self clause:context subject:nil];
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
	text = ORMSingleSpaced(text);
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

@implementation ORMSentenceEditor

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}


- (NSArray<NSString *> *)addFromSentence:(NSString *)text
                               onDiagram:(NSString *)diagramId
                                      at:(NSPoint)point
                                  reason:(NSString **)reason
{
	NSString *why = nil;
	NSArray *statement = [self addStatement:text onDiagram:diagramId at:point reason:&why];
	if (statement != nil || why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return statement;
	}
	ORMConstraintSentence *sentence = [ORMConstraintSentence sentenceWithString:text model:_editor.model reason:&why];
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
	[_editor group:@"Add from Sentence" with:^{
		/* The fact types first, and the object types they need. */
		NSMapTable *factIds = [NSMapTable strongToStrongObjectsMapTable];
		for (ORMSentenceFact *fact in sentence.factTypes) {
			NSMutableArray *players = [NSMutableArray array];
			for (NSString *name in fact.playerNames) {
				NSString *identifier = [[_editor.model objectTypeNamed:name] identifier];
				if (identifier == nil) {
					identifier = [_editor.objectTypeEditor addEntityTypeNamed:name referenceMode:nil kind:ORMReferenceModeNone
					                            onDiagram:diagramId at:ORMAutomaticPlacement reason:&failure];
					if (identifier == nil) {
						return;
					}
					[made addObject:identifier];
				}
				[players addObject:identifier];
			}
			NSString *factId = [_editor.factTypeEditor addFactTypeWithPlayers:players reading:fact.reading onDiagram:diagramId
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
			ORMFactType *fact = [_editor.model elementWithId:[factIds objectForKey:role.fact]];
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
					: [[_editor.model objectTypeNamed:constraint.valuesOfObjectType] identifier];
				if (target == nil && constraint.valuesOfRole == nil) {
					/* Values belong to a value type: text when they are
					 * quoted, numbers when not. */
					BOOL text = [constraint.values rangeOfString:@"'"].location != NSNotFound;
					target = [_editor.objectTypeEditor addValueTypeNamed:constraint.valuesOfObjectType
					                        dataType:text ? @"VariableLengthTextDataType" : @"DecimalNumericDataType"
					                       onDiagram:diagramId
					                              at:ORMAutomaticPlacement
					                          reason:&failure];
					if (target != nil) {
						[made addObject:target];
					}
				}
				if (target == nil || ![_editor.objectTypeEditor setValueConstraint:constraint.values of:target reason:&failure]) {
					failure = failure ?: [NSString stringWithFormat:@"No object type is named %@.",
					                                                constraint.valuesOfObjectType];
					return;
				}
				continue;
			}
			/* What the model says already is not said twice. */
			if ([first count] == 1 && [sequences count] == 1) {
				ORMRole *role = [_editor.model elementWithId:[first firstObject]];
				if ((constraint.kind == ORMUniquenessConstraint && role.isUnique)
				    || (constraint.kind == ORMMandatoryConstraint && !constraint.isExclusiveOr && role.isMandatory)) {
					continue;
				}
			}
			switch (constraint.kind) {
			case ORMUniquenessConstraint:
				created = [_editor.constraintEditor addUniquenessConstraintOverRoles:first reason:&failure];
				break;
			case ORMMandatoryConstraint:
				created = constraint.isExclusiveOr ? [_editor.constraintEditor addExclusiveOrConstraintOverRoles:first reason:&failure]
				                                   : [_editor.constraintEditor addMandatoryConstraintOverRoles:first reason:&failure];
				break;
			case ORMRingConstraint:
				created = [_editor.constraintEditor addRingConstraint:constraint.ringType overRoles:first reason:&failure];
				break;
			case ORMValueComparisonConstraint:
				created = [_editor.constraintEditor addValueComparisonConstraint:constraint.comparisonOperator overRoles:first
				                                                          reason:&failure];
				break;
			case ORMSubsetConstraint:
			case ORMEqualityConstraint:
			case ORMExclusionConstraint:
				if (constraint.paths == nil) {
					created = [_editor.constraintEditor addSetComparisonConstraint:constraint.kind sequences:sequences reason:&failure];
					break;
				}
				{
					/* Over join paths: each sequence a path's atoms, or a
					 * plain one as an atom of its own. */
					NSMutableArray *specs = [NSMutableArray array];
					for (NSUInteger i = 0; i < [sequences count]; i++) {
						id path = [constraint.paths objectAtIndex:i];
						if (path == [NSNull null]) {
							NSMutableDictionary *atom = [NSMutableDictionary dictionary];
							NSMutableArray *columns = [NSMutableArray array];
							for (NSString *role in [sequences objectAtIndex:i]) {
								NSString *column = [NSString stringWithFormat:@"column %lu", (unsigned long)[columns count]];
								[atom setObject:column forKey:role];
								[columns addObject:column];
							}
							[specs addObject:[ORMJoinPathSpec specWithAtoms:@[ atom ] columns:columns]];
							continue;
						}
						ORMSentencePath *sentencePath = path;
						NSMutableArray *atoms = [NSMutableArray array];
						for (NSUInteger a = 0; a < [sentencePath.atomRoles count]; a++) {
							NSMutableDictionary *atom = [NSMutableDictionary dictionary];
							NSArray *roles = [sentencePath.atomRoles objectAtIndex:a];
							NSArray *variables = [sentencePath.atomVariables objectAtIndex:a];
							for (NSUInteger r = 0; r < [roles count]; r++) {
								NSString *identifier = roleId([roles objectAtIndex:r]);
								if (identifier != nil) {
									[atom setObject:[variables objectAtIndex:r] forKey:identifier];
								}
							}
							[atoms addObject:atom];
						}
						[specs addObject:[ORMJoinPathSpec specWithAtoms:atoms columns:sentencePath.columns]];
					}
					created = [[[ORMJoinPathBuilder alloc] initWithEditor:_editor] addSetComparisonConstraint:constraint.kind joinPaths:specs reason:&failure];
				}
				break;
			default:
				failure = @"That kind of constraint cannot be added from a sentence yet.";
				break;
			}
			if (created == nil) {
				return;
			}
			if (sentence.modality == ORMDeontic) {
				[_editor.constraintEditor setModality:ORMDeontic of:created reason:NULL];
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
