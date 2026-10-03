/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMVerbalizerPriv.h"
#import "ORMPath.h"
#import "ORMDiagram.h"
#import "ORMReadingText.h"
#import "ORMXML.h"

@implementation ORMVerbalSpan

+ (instancetype)spanWithText:(NSString *)text style:(ORMVerbalStyle)style elementId:(NSString *)elementId
{
	ORMVerbalSpan *span = [[self alloc] init];
	span.text = text;
	span.style = style;
	span.elementId = elementId;
	return span;
}

@end

@implementation ORMVerbalSentence

- (NSString *)text
{
	NSMutableString *text = [NSMutableString string];
	for (ORMVerbalSpan *span in self.spans) {
		[text appendString:span.text];
	}
	return text;
}

- (NSString *)description
{
	return [self text];
}

@end

@implementation ORMSpokenTerm
@end

NSString *
ORMArticle(NSString *name)
{
	NSString *first = [[name substringToIndex:MIN((NSUInteger)1, [name length])] lowercaseString];
	return [@"aeiou" rangeOfString:first].location != NSNotFound && [first length] > 0 ? @"an" : @"a";
}

ORMSpokenTerm *
ORMMakeTerm(NSString *quantifier, NSString *name, NSString *elementId)
{
	ORMSpokenTerm *term = [[ORMSpokenTerm alloc] init];
	term.quantifier = quantifier;
	term.name = name;
	term.elementId = elementId;
	return term;
}

@implementation ORMReadingUse
@end

@implementation ORMSentenceBuilder

- (instancetype)init
{
	if ((self = [super init])) {
		_spans = [NSMutableArray array];
	}
	return self;
}

- (void)add:(NSString *)text style:(ORMVerbalStyle)style id:(NSString *)elementId
{
	if ([text length] == 0) {
		return;
	}
	/* One space between words, whatever a reading's text has. */
	while ([text rangeOfString:@"  "].location != NSNotFound) {
		text = [text stringByReplacingOccurrencesOfString:@"  " withString:@" "];
	}
	if ([text hasPrefix:@" "] && [[[self.spans lastObject] text] hasSuffix:@" "]) {
		text = [text substringFromIndex:1];
	}
	if ([text length] == 0) {
		return;
	}
	ORMVerbalSpan *last = [self.spans lastObject];
	if (last != nil && last.style == style && elementId == nil && last.elementId == nil) {
		last.text = [last.text stringByAppendingString:text];
		return;
	}
	[self.spans addObject:[ORMVerbalSpan spanWithText:text style:style elementId:elementId]];
}

- (void)keyword:(NSString *)text
{
	[self add:text style:ORMVerbalKeyword id:nil];
}

- (void)predicate:(NSString *)text
{
	[self add:text style:ORMVerbalPredicate id:nil];
}

- (void)plain:(NSString *)text
{
	[self add:text style:ORMVerbalPlain id:nil];
}

- (void)value:(NSString *)text
{
	[self add:text style:ORMVerbalValue id:nil];
}

- (void)note:(NSString *)text
{
	[self add:text style:ORMVerbalNote id:nil];
}

- (void)objectType:(NSString *)name id:(NSString *)elementId
{
	[self add:name style:ORMVerbalObjectType id:elementId];
}

- (void)append:(NSArray<ORMVerbalSpan *> *)spans
{
	for (ORMVerbalSpan *span in spans) {
		[self add:span.text style:span.style id:span.elementId];
	}
}

- (BOOL)isEmpty
{
	return [self.spans count] == 0;
}

@end

static NSString *
ORMQuoted(NSString *value, BOOL quotes)
{
	NSScanner *scanner = [NSScanner scannerWithString:value];
	double number;
	if (!quotes || ([scanner scanDouble:&number] && [scanner isAtEnd])) {
		return value;
	}
	return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
}

/* "at most one", "at least 2 and at most 5", "exactly 3". */
static NSString *
ORMCardinalityText(ORMCardinality *cardinality)
{
	NSMutableArray *parts = [NSMutableArray array];
	for (NSArray<NSNumber *> *range in cardinality.ranges) {
		NSUInteger from = [[range firstObject] unsignedIntegerValue];
		NSUInteger to = [[range lastObject] unsignedIntegerValue];
		NSString *(^n)(NSUInteger) = ^NSString *(NSUInteger value) {
			return value == 1 ? @"one" : [NSString stringWithFormat:@"%lu", (unsigned long)value];
		};
		if (from == to) {
			[parts addObject:[@"exactly " stringByAppendingString:n(from)]];
		} else if (to == 0) {
			[parts addObject:[@"at least " stringByAppendingString:n(from)]];
		} else if (from == 0) {
			[parts addObject:[@"at most " stringByAppendingString:n(to)]];
		} else {
			[parts addObject:[NSString stringWithFormat:@"at least %@ and at most %@", n(from), n(to)]];
		}
	}
	return [parts componentsJoinedByString:@" or "];
}

static BOOL
ORMCardinalityIsOne(ORMCardinality *cardinality)
{
	NSArray *range = [cardinality.ranges lastObject];
	return [cardinality.ranges count] == 1 && [[range lastObject] unsignedIntegerValue] == 1;
}

@implementation ORMVerbalizer
{
	NSMutableArray<ORMVerbalSentence *> *_out;
	NSString *_subject;
	NSUInteger _level;
}

- (instancetype)initWithModel:(ORMModel *)model
{
	if ((self = [super init])) {
		_model = model;
		_verbalizesPossibilities = YES;
		_verbalizesExamples = YES;
	}
	return self;
}

#pragma mark Sentences

- (ORMVerbalSentence *)emit:(ORMSentenceBuilder *)builder
{
	return [self emit:builder modality:ORMAlethic];
}

- (ORMVerbalSentence *)emit:(ORMSentenceBuilder *)builder kind:(ORMVerbalKind)kind
{
	ORMVerbalSentence *sentence = [self emit:builder modality:ORMAlethic];
	sentence.kind = kind;
	return sentence;
}

/* The builder's spans as a sentence: capitalized, ended, with its
 * modality said (a deontic rule is what is obligatory, not what is
 * necessary), or nil when there is nothing. */
- (ORMVerbalSentence *)sentenceOf:(ORMSentenceBuilder *)builder prefix:(NSString *)prefix
{
	NSMutableArray *spans = builder.spans;
	if ([spans count] == 0) {
		return nil;
	}
	if (prefix != nil) {
		ORMVerbalSpan *first = [spans firstObject];
		if ([first.text length] > 0 && first.style != ORMVerbalObjectType) {
			first.text = [[[first.text substringToIndex:1] lowercaseString]
				stringByAppendingString:[first.text substringFromIndex:1]];
		}
		[spans insertObject:[ORMVerbalSpan spanWithText:prefix style:ORMVerbalKeyword elementId:nil] atIndex:0];
	}
	/* A sentence starts with a capital, unless it starts with a name. */
	ORMVerbalSpan *first = [spans firstObject];
	if ([first.text length] > 0 && first.style != ORMVerbalObjectType) {
		first.text = [[[first.text substringToIndex:1] uppercaseString] stringByAppendingString:[first.text
		                                                                                         substringFromIndex:1]];
	}
	ORMVerbalSpan *last = [spans lastObject];
	if (![last.text hasSuffix:@"."]) {
		[spans addObject:[ORMVerbalSpan spanWithText:@"." style:ORMVerbalPlain elementId:nil]];
	}
	ORMVerbalSentence *sentence = [[ORMVerbalSentence alloc] init];
	sentence.spans = spans;
	sentence.subjectId = _subject;
	sentence.level = _level;
	sentence.sourceId = self.source;
	sentence.negations = @[];
	return sentence;
}

- (ORMVerbalSentence *)emit:(ORMSentenceBuilder *)builder modality:(ORMModality)modality
{
	ORMVerbalSentence *sentence = [self sentenceOf:builder prefix:modality == ORMDeontic ? @"It is obligatory that " : nil];
	if (sentence != nil) {
		[_out addObject:sentence];
	}
	return sentence;
}

- (void)negate:(ORMVerbalSentence *)statement with:(ORMSentenceBuilder *)builder modality:(ORMModality)modality
{
	if (statement == nil) {
		return;
	}
	ORMVerbalSentence *negation = [self sentenceOf:builder prefix:modality == ORMDeontic ? @"It is forbidden that "
	                                                                                      : @"It is impossible that "];
	if (negation == nil) {
		return;
	}
	negation.kind = ORMVerbalNegation;
	negation.sourceId = statement.sourceId;
	statement.negations = [statement.negations arrayByAddingObject:negation];
	if (self.verbalizesNegations) {
		[_out addObject:negation];
	}
}

#pragma mark Readings

- (ORMReadingUse *)use:(NSString *)text roles:(NSArray<ORMRole *> *)roles
{
	ORMReadingUse *use = [[ORMReadingUse alloc] init];
	use.text = text;
	use.roles = roles;
	return use;
}

/* A reading of the fact type that starts with the role, if it has one;
 * else its primary reading. Subtype facts read "{sub} is {super}". */
- (ORMReadingUse *)readingOf:(ORMFactType *)fact from:(ORMRole *)role
{
	if (fact.kind == ORMFactTypeSubtype && [fact.roles count] == 2) {
		ORMRole *sub = [fact.roles objectAtIndex:0];
		ORMRole *sup = [fact.roles objectAtIndex:1];
		ORMReadingUse *use = [self use:@"{0} is {1}" roles:role == sup ? @[ sup, sub ] : @[ sub, sup ]];
		use.isSubtype = YES;
		return use;
	}
	ORMReadingOrder *order = role != nil ? [fact readingOrderStartingWithRole:role] : nil;
	ORMReading *reading = order != nil ? [order.readings firstObject] : [fact primaryReading];
	if (reading == nil) {
		/* No reading at all: list the players. */
		NSMutableArray *parts = [NSMutableArray array];
		NSArray *roles = [fact visibleRoles];
		for (NSUInteger i = 0; i < [roles count]; i++) {
			[parts addObject:[NSString stringWithFormat:@"{%lu}", (unsigned long)i]];
		}
		return [self use:[parts componentsJoinedByString:@" ... "] roles:roles];
	}
	return [self use:reading.text roles:reading.readingOrder.roles];
}

- (BOOL)fact:(ORMFactType *)fact readsFrom:(ORMRole *)role
{
	if (role == nil) {
		return NO;
	}
	if (fact.kind == ORMFactTypeSubtype) {
		return YES;
	}
	ORMReadingOrder *order = [fact readingOrderStartingWithRole:role];
	ORMReading *reading = [order.readings firstObject];
	if (reading == nil) {
		return NO;
	}
	ORMReadingText *text = [ORMReadingText readingTextWithString:reading.text arity:[order.roles count] reason:NULL];
	ORMReadingPart *part = [text.parts firstObject];
	return text != nil && [text.frontText length] == 0 && [part.preBoundText length] == 0;
}

/* A reading with each role's term put in, hyphen-bound words around the
 * name after the quantifier: "at most one first Name". */
- (NSArray<ORMVerbalSpan *> *)clause:(ORMReadingUse *)use terms:(ORMSpokenTerm * (^)(ORMRole *role))term
{
	ORMSentenceBuilder *builder = [[ORMSentenceBuilder alloc] init];
	ORMReadingText *text = [ORMReadingText readingTextWithString:use.text arity:[use.roles count] reason:NULL];
	if (text == nil) {
		[builder predicate:use.text];
		return builder.spans;
	}
	[builder predicate:text.frontText];
	BOOL skippedSubject = NO;
	for (ORMReadingPart *part in text.parts) {
		ORMRole *role = part.roleIndex < [use.roles count] ? [use.roles objectAtIndex:part.roleIndex] : nil;
		ORMSpokenTerm *t = role != nil ? term(role) : ORMMakeTerm(nil, @"?", nil);
		if (t.name == nil) {
			skippedSubject = YES;
		} else {
			NSString *quantifier = t.quantifier;
			/* "Each Male is a Person": a subtype reading's "some" is "a". */
			if (use.isSubtype && [quantifier isEqualToString:@"some"]) {
				quantifier = ORMArticle(t.name);
			}
			if ([quantifier length] > 0) {
				[builder keyword:[quantifier stringByAppendingString:@" "]];
			}
			[builder predicate:part.preBoundText];
			[builder objectType:t.name id:t.elementId];
			if ([t.value length] > 0) {
				[builder plain:@" "];
				[builder value:t.value];
			}
			[builder predicate:part.postBoundText];
		}
		NSString *following = part.followingText;
		/* With the subject left out, the clause starts at its verb. */
		if (skippedSubject && [builder.spans count] == 0) {
			NSRange words = [following rangeOfCharacterFromSet:[[NSCharacterSet whitespaceCharacterSet] invertedSet]];
			following = words.location == NSNotFound ? @"" : [following substringFromIndex:words.location];
		}
		[builder predicate:following];
	}
	return builder.spans;
}

/* Names that tell apart the roles a sentence mentions: a ring's two
 * Persons are Person1 and Person2. */
- (NSMapTable *)namesFor:(NSArray<ORMRole *> *)roles
{
	NSMapTable *names = [NSMapTable strongToStrongObjectsMapTable];
	NSCountedSet *counts = [[NSCountedSet alloc] init];
	for (ORMRole *role in roles) {
		[counts addObject:role.player.name ?: @"?"];
	}
	NSMutableDictionary *seen = [NSMutableDictionary dictionary];
	for (ORMRole *role in roles) {
		NSString *name = role.player.name ?: @"?";
		if ([counts countForObject:name] > 1) {
			NSUInteger n = [[seen objectForKey:name] unsignedIntegerValue] + 1;
			[seen setObject:@(n) forKey:name];
			name = [NSString stringWithFormat:@"%@%lu", name, (unsigned long)n];
		}
		[names setObject:name forKey:role];
	}
	return names;
}

#pragma mark Object types

- (void)verbalizeObjectType:(ORMObjectType *)type
{
	if (type.isImplicitBooleanValue) {
		return;
	}
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	if (type.kind == ORMObjectifiedType && type.nestedFactType != nil) {
		ORMReadingUse *use = [self readingOf:type.nestedFactType from:nil];
		[b objectType:type.name id:type.identifier];
		[b keyword:@" is where "];
		[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *role) {
			return ORMMakeTerm(nil, role.player.name, role.player.identifier);
		}]];
		[self emit:b];
		b = [[ORMSentenceBuilder alloc] init];
	}
	[b objectType:type.name id:type.identifier];
	[b keyword:type.kind == ORMValueType ? @" is a value type" : @" is an entity type"];
	[self emit:b kind:ORMVerbalInformation];

	if (type.isIndependent) {
		b = [[ORMSentenceBuilder alloc] init];
		[b objectType:type.name id:type.identifier];
		[b keyword:@" is independent"];
		[b plain:@" (it may have instances that play no other roles)"];
		[self emit:b];
	}
	if (type.isPersonal) {
		b = [[ORMSentenceBuilder alloc] init];
		[b plain:@"Uses personal pronouns"];
		[self emit:b kind:ORMVerbalInformation];
	}
	if (type.isExternal) {
		b = [[ORMSentenceBuilder alloc] init];
		[b objectType:type.name id:type.identifier];
		[b keyword:@" is external"];
		[b plain:@" (defined in another model)"];
		[self emit:b kind:ORMVerbalInformation];
	}

	for (ORMObjectType *supertype in type.supertypes) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Each "];
		[b objectType:type.name id:type.identifier];
		[b keyword:[NSString stringWithFormat:@" is %@ ", ORMArticle(supertype.name)]];
		[b objectType:supertype.name id:supertype.identifier];
		[self emit:b];
	}
	[self verbalizeDerivationOfSubtype:type];

	ORMConstraint *identifier = type.preferredIdentifier;
	if (identifier != nil && type.nestedFactType == nil) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Reference Scheme: "];
		NSArray *facts = [identifier factTypes];
		for (NSUInteger i = 0; i < [facts count]; i++) {
			if (i > 0) {
				[b keyword:@"; "];
			}
			ORMFactType *fact = [facts objectAtIndex:i];
			ORMRole *own = nil;
			for (ORMRole *role in fact.roles) {
				if (role.player == type && ![[identifier allRoles] containsObject:role]) {
					own = role;
				}
			}
			[b append:[self clause:[self readingOf:fact from:own] terms:^ORMSpokenTerm *(ORMRole *role) {
				return ORMMakeTerm(nil, role.player.name, role.player.identifier);
			}]];
		}
		[self emit:b kind:ORMVerbalInformation];
	} else if (type.isEntity && identifier == nil && [type.supertypes count] == 0 && type.nestedFactType == nil) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Reference Scheme: "];
		[b plain:@"none given"];
		[self emit:b kind:ORMVerbalInformation];
	}
	if (type.referenceMode != nil) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Reference Mode: "];
		NSString *mode = type.referenceModeKind == ORMReferenceModePopular ? [@"." stringByAppendingString:type.referenceMode]
			: type.referenceModeKind == ORMReferenceModeUnitBased ? [type.referenceMode stringByAppendingString:@":"]
			: type.referenceMode;
		[b plain:mode];
		[self emit:b kind:ORMVerbalInformation];
	}

	ORMObjectType *valueType = type.kind == ORMValueType ? type : type.referenceModeValueType;
	if (valueType.dataType != nil) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Portable data type: "];
		NSMutableString *data = [[valueType.dataType displayName] mutableCopy];
		if (valueType.dataTypeLength > 0 && valueType.dataTypeScale > 0) {
			[data appendFormat:@"(%ld, %ld)", (long)valueType.dataTypeLength, (long)valueType.dataTypeScale];
		} else if (valueType.dataTypeLength > 0) {
			[data appendFormat:@"(%ld)", (long)valueType.dataTypeLength];
		}
		[b plain:data];
		[self emit:b kind:ORMVerbalInformation];
	}
	if (type.valueConstraint != nil) {
		[self verbalizeValues:type.valueConstraint of:type role:nil];
	}
	if ([[type defaultValue] length] > 0) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"The default value of "];
		[b objectType:type.name id:type.identifier];
		[b keyword:@" is "];
		[b value:ORMQuoted([type defaultValue], type.valueConstraint == nil || [type.valueConstraint quotesValues])];
		[self emit:b kind:ORMVerbalInformation];
	}
	ORMCardinality *cardinality = [type cardinality];
	if (cardinality != nil) {
		/* "Each population of President contains at most one instance." */
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Each population of "];
		[b objectType:type.name id:type.identifier];
		[b keyword:@" contains "];
		[b keyword:ORMCardinalityText(cardinality)];
		[b keyword:ORMCardinalityIsOne(cardinality) ? @" instance" : @" instances"];
		[self emit:b];
	}
	[self verbalizeText:type.definitionText label:@"Informal Definition: "];
	[self verbalizeText:type.noteText label:@"Notes: "];
	[self verbalizeExamplesOfObjectType:type];

	/* What it plays, as NORMA lists it. */
	NSMutableArray *facts = [NSMutableArray array];
	for (ORMRole *role in type.playedRoles) {
		ORMFactType *fact = role.factType;
		if (fact.kind == ORMFactTypeOrdinary && [facts indexOfObjectIdenticalTo:fact] == NSNotFound) {
			[facts addObject:fact];
		}
	}
	if ([facts count] > 0) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Fact Types:"];
		[self emit:b kind:ORMVerbalInformation];
		ORMVerbalSentence *heading = [_out lastObject];
		/* A heading ends without a full stop. */
		if ([[[heading.spans lastObject] text] isEqualToString:@"."]) {
			heading.spans = [heading.spans subarrayWithRange:NSMakeRange(0, [heading.spans count] - 1)];
		}
		_level++;
		for (ORMFactType *fact in facts) {
			b = [[ORMSentenceBuilder alloc] init];
			[b append:[self clause:[self readingOf:fact from:nil] terms:^ORMSpokenTerm *(ORMRole *role) {
				return ORMMakeTerm(nil, role.player.name, role.player.identifier);
			}]];
			ORMVerbalSentence *line = [self emit:b kind:ORMVerbalInformation];
			line.sourceId = fact.identifier;
			if ([[[line.spans lastObject] text] isEqualToString:@"."]) {
				line.spans = [line.spans subarrayWithRange:NSMakeRange(0, [line.spans count] - 1)];
			}
		}
		_level--;
	}
}

/* "Examples: 'M', 'F'." */
- (void)verbalizeExamplesOfObjectType:(ORMObjectType *)type
{
	NSArray *instances = [type instances];
	if (!self.verbalizesExamples || [instances count] == 0) {
		return;
	}
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	[b keyword:@"Examples: "];
	for (NSUInteger i = 0; i < [instances count]; i++) {
		if (i > 0) {
			[b plain:@", "];
		}
		[b value:[[instances objectAtIndex:i] displayText]];
	}
	[self emit:b kind:ORMVerbalExample];
}

/* "Person 'Ann' was born in Country 'AU'." */
- (void)verbalizeExamplesOfFactType:(ORMFactType *)fact
{
	if (!self.verbalizesExamples) {
		return;
	}
	ORMReadingUse *use = [self readingOf:fact from:nil];
	for (ORMFactInstance *instance in [fact instances]) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *role) {
			ORMSpokenTerm *term = ORMMakeTerm(nil, role.player.name, role.player.identifier);
			term.value = [[instance.instancesByRole objectForKey:role.identifier] displayText] ?: @"?";
			return term;
		}]];
		[self emit:b kind:ORMVerbalExample].sourceId = instance.identifier;
	}
}

- (void)verbalizeText:(NSString *)text label:(NSString *)label
{
	if ([text length] == 0) {
		return;
	}
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	[b keyword:label];
	[b note:text];
	[self emit:b];
}

/* "The possible values of Age are 0 to 140." */
- (void)verbalizeValues:(ORMValueConstraint *)constraint of:(ORMObjectType *)type role:(ORMRole *)role
{
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	BOOL single = [constraint.ranges count] == 1
		&& [[[constraint.ranges firstObject] minValue] isEqualToString:[[constraint.ranges firstObject] maxValue]];
	[b keyword:single ? @"The possible value of " : @"The possible values of "];
	ORMObjectType *subject = role != nil ? role.player : type;
	[b objectType:subject.name id:subject.identifier];
	if (role != nil) {
		[b keyword:@" in the context of "];
		[b append:[self clause:[self readingOf:role.factType from:nil] terms:^ORMSpokenTerm *(ORMRole *r) {
			return ORMMakeTerm(nil, r.player.name, r.player.identifier);
		}]];
	}
	[b keyword:single ? @" is " : @" are "];
	for (NSUInteger i = 0; i < [constraint.ranges count]; i++) {
		if (i > 0) {
			[b plain:@", "];
		}
		[self appendRange:[constraint.ranges objectAtIndex:i] to:b];
	}
	[self emit:b];
}


- (void)appendRange:(ORMValueRange *)range to:(ORMSentenceBuilder *)b
{
	BOOL quotes = range.constraint == nil || [range.constraint quotesValues];
	NSString *min = range.minValue;
	NSString *max = range.maxValue;
	if ([min isEqualToString:max]) {
		[b value:ORMQuoted(min, quotes)];
		return;
	}
	if ([min length] > 0 && [max length] > 0) {
		if (range.minInclusion == ORMRangeOpen) {
			[b keyword:@"above "];
		}
		[b value:ORMQuoted(min, quotes)];
		[b keyword:range.maxInclusion == ORMRangeOpen ? @" to below " : @" to "];
		[b value:ORMQuoted(max, quotes)];
	} else if ([min length] > 0) {
		[b keyword:range.minInclusion == ORMRangeOpen ? @"above " : @"at least "];
		[b value:ORMQuoted(min, quotes)];
	} else {
		[b keyword:range.maxInclusion == ORMRangeOpen ? @"below " : @"at most "];
		[b value:ORMQuoted(max, quotes)];
	}
}

#pragma mark Fact types

- (void)verbalizeFactType:(ORMFactType *)fact
{
	if (fact.kind == ORMFactTypeImplied) {
		return;
	}
	self.source = fact.identifier;
	if (fact.kind == ORMFactTypeSubtype) {
		ORMObjectType *sub = [[fact.roles firstObject] player];
		ORMObjectType *sup = [[fact.roles lastObject] player];
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Each "];
		[b objectType:sub.name id:sub.identifier];
		[b keyword:[NSString stringWithFormat:@" is %@ ", ORMArticle(sup.name)]];
		[b objectType:sup.name id:sup.identifier];
		[self emit:b];
		if (!fact.providesPreferredIdentifier) {
			b = [[ORMSentenceBuilder alloc] init];
			[b objectType:sub.name id:sub.identifier];
			[b plain:@" has its own reference scheme, not that of "];
			[b objectType:sup.name id:sup.identifier];
			[self emit:b kind:ORMVerbalInformation];
		}
		return;
	}

	/* The readings. */
	for (ORMReadingOrder *order in fact.readingOrders) {
		for (ORMReading *reading in order.readings) {
			ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
			[b append:[self clause:[self use:reading.text roles:order.roles] terms:^ORMSpokenTerm *(ORMRole *role) {
				return ORMMakeTerm(nil, role.player.name, role.player.identifier);
			}]];
			[self emit:b];
		}
	}
	[self verbalizeDerivationOfFactType:fact];

	_level++;
	if (fact.objectifyingType != nil) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b objectType:fact.objectifyingType.name id:fact.objectifyingType.identifier];
		[b keyword:@" is where "];
		[b append:[self clause:[self readingOf:fact from:nil] terms:^ORMSpokenTerm *(ORMRole *role) {
			return ORMMakeTerm(nil, role.player.name, role.player.identifier);
		}]];
		[self emit:b];
	}
	NSArray *roles = [fact visibleRoles];
	if ([roles count] == 2) {
		[self verbalizeBinary:fact];
	} else if ([roles count] == 1) {
		[self verbalizeUnary:fact];
	} else {
		[self verbalizeNary:fact];
	}
	for (ORMRole *role in roles) {
		if (role.valueConstraint != nil) {
			self.source = role.valueConstraint.identifier;
			[self verbalizeValues:role.valueConstraint of:nil role:role];
		}
	}
	/* Frequency and ring constraints over this fact type's roles alone. */
	for (ORMConstraint *constraint in self.model.constraints) {
		if ((constraint.kind == ORMFrequencyConstraint || constraint.kind == ORMRingConstraint)
		    && [[constraint factTypes] isEqualToArray:@[ fact ]]) {
			[self verbalizeConstraint:constraint];
		}
	}
	self.source = fact.identifier;
	[self verbalizeExamplesOfFactType:fact];
	_level--;
}

/* The internal constraint of a kind on the role alone. */
- (ORMConstraint *)constraint:(ORMConstraintKind)kind onlyOn:(ORMRole *)role
{
	for (ORMConstraint *constraint in role.constraints) {
		if (constraint.kind == kind && [[constraint allRoles] count] == 1 && [constraint factTypes].count == 1
		    && (kind != ORMMandatoryConstraint || constraint.isSimple)) {
			return constraint;
		}
	}
	return nil;
}

/* The last negation attached says what the constraint rules out. */
- (void)negate:(ORMVerbalSentence *)statement with:(ORMSentenceBuilder *)builder
      modality:(ORMModality)modality source:(ORMConstraint *)constraint
{
	[self negate:statement with:builder modality:modality];
	[[statement.negations lastObject] setSourceId:constraint.identifier];
}

/* The internal uniqueness and simple mandatory constraints of a binary,
 * one role at a time: what each player may and must do. */
- (void)verbalizeBinary:(ORMFactType *)fact
{
	NSArray *roles = [fact visibleRoles];
	BOOL spanning = [fact hasUniquenessOverRoles:roles];
	for (ORMRole *role in roles) {
		ORMRole *other = [role oppositeRole];
		ORMReadingUse *use = [self readingOf:fact from:role];
		BOOL fromRole = [use.roles firstObject] == role;
		ORMConstraint *unique = role.isUnique ? [self constraint:ORMUniquenessConstraint onlyOn:role] : nil;
		ORMConstraint *mandatory = role.isMandatory ? [self constraint:ORMMandatoryConstraint onlyOn:role] : nil;
		/* "exactly one" says both, when both are of one modality; else
		 * each is said as what it is ("It is obligatory that each Person
		 * was born in some Country" beside "...at most one Country"). */
		NSMutableArray *statements = [NSMutableArray array];
		if (role.isUnique && role.isMandatory && unique.modality == mandatory.modality) {
			[statements addObject:@[ @"exactly one", @[ unique ?: [NSNull null], mandatory ?: [NSNull null] ] ]];
		} else {
			if (role.isUnique) {
				[statements addObject:@[ @"at most one", @[ unique ?: [NSNull null], [NSNull null] ] ]];
			}
			if (role.isMandatory) {
				[statements addObject:@[ @"some", @[ [NSNull null], mandatory ?: [NSNull null] ] ]];
			}
		}
		for (NSArray *said in statements) {
			NSString *quantifier = [said firstObject];
			ORMConstraint *saidUnique = [[said lastObject] firstObject] == [NSNull null] ? nil : [[said lastObject] firstObject];
			ORMConstraint *saidMandatory = [[said lastObject] lastObject] == [NSNull null] ? nil : [[said lastObject] lastObject];
			BOOL saysUnique = [quantifier isEqualToString:@"exactly one"] || [quantifier isEqualToString:@"at most one"];
			BOOL saysMandatory = [quantifier isEqualToString:@"exactly one"] || [quantifier isEqualToString:@"some"];
			ORMModality modality = saysUnique ? saidUnique.modality : saidMandatory.modality;
			self.source = (saidUnique ?: saidMandatory).identifier;
			ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
			if (!fromRole) {
				/* No reading starts with the role: say it from its side. */
				[b keyword:@"For each "];
				[b objectType:role.player.name id:role.player.identifier];
				[b plain:@", "];
			}
			[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
				if (r == role) {
					return ORMMakeTerm(fromRole ? @"each" : @"that", r.player.name, r.player.identifier);
				}
				return ORMMakeTerm(quantifier, r.player.name, r.player.identifier);
			}]];
			ORMVerbalSentence *statement = [self emit:b modality:modality];
			if (saysUnique) {
				/* "It is impossible that the same Person was born in more
				 * than one Country." */
				b = [[ORMSentenceBuilder alloc] init];
				[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
					return ORMMakeTerm(r == role ? @"the same" : @"more than one", r.player.name, r.player.identifier);
				}]];
				[self negate:statement with:b modality:saidUnique.modality source:saidUnique];
			}
			if (saysMandatory) {
				[self negate:statement with:[self noneOf:@[ role ] use:@[ use ]] modality:saidMandatory.modality
				      source:saidMandatory];
			}
		}
		if (!role.isUnique && self.verbalizesPossibilities && other != nil && !spanning) {
			self.source = role.identifier;
			ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
			[b keyword:@"It is possible that "];
			[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
				return ORMMakeTerm(r == role ? @"some" : @"more than one", r.player.name, r.player.identifier);
			}]];
			[self emit:b kind:ORMVerbalPossibility];
		}
	}
	if (spanning) {
		/* Many to many. */
		if (self.verbalizesPossibilities) {
			self.source = fact.identifier;
			ORMRole *first = [roles firstObject];
			ORMRole *second = [roles lastObject];
			ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
			[b keyword:@"It is possible that "];
			[b append:[self clause:[self readingOf:fact from:first] terms:^ORMSpokenTerm *(ORMRole *r) {
				return ORMMakeTerm(r == first ? @"the same" : @"more than one", r.player.name, r.player.identifier);
			}]];
			[b keyword:@" and that "];
			[b append:[self clause:[self readingOf:fact from:second] terms:^ORMSpokenTerm *(ORMRole *r) {
				return ORMMakeTerm(r == second ? @"the same" : @"more than one", r.player.name, r.player.identifier);
			}]];
			[self emit:b kind:ORMVerbalPossibility];
		}
		[self verbalizeSpanningUniqueness:fact roles:roles];
	}
}

/* What a mandatory role (or an inclusive-or over roles of one player)
 * rules out: "some Person was born in no Country", or "for some Person,
 * no Country is the birthplace of that Person" when a reading does not
 * start with the role. */
- (ORMSentenceBuilder *)noneOf:(NSArray<ORMRole *> *)roles use:(NSArray<ORMReadingUse *> *)uses
{
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	BOOL fromRoles = YES;
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		if ([[[uses objectAtIndex:i] roles] firstObject] != role || ![self fact:role.factType readsFrom:role]) {
			fromRoles = NO;
		}
	}
	ORMObjectType *player = [[roles firstObject] player];
	if (!fromRoles) {
		[b keyword:@"for some "];
		[b objectType:player.name id:player.identifier];
		[b plain:@", "];
	}
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		if (i > 0) {
			[b keyword:@" and "];
		}
		BOOL first = i == 0;
		[b append:[self clause:[uses objectAtIndex:i] terms:^ORMSpokenTerm *(ORMRole *r) {
			if (r == role) {
				if (!fromRoles) {
					return ORMMakeTerm(@"that", r.player.name, r.player.identifier);
				}
				return first ? ORMMakeTerm(@"some", r.player.name, r.player.identifier) : ORMMakeTerm(nil, nil, nil);
			}
			return ORMMakeTerm(@"no", r.player.name, r.player.identifier);
		}]];
	}
	return b;
}

- (void)verbalizeSpanningUniqueness:(ORMFactType *)fact roles:(NSArray<ORMRole *> *)roles
{
	ORMConstraint *constraint = nil;
	for (ORMConstraint *each in [fact uniquenessConstraints]) {
		if ([[each allRoles] count] == [roles count]) {
			constraint = each;
		}
	}
	self.source = constraint.identifier;
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	[b keyword:@"In each population of "];
	[b append:[self clause:[self readingOf:fact from:nil] terms:^ORMSpokenTerm *(ORMRole *r) {
		return ORMMakeTerm(nil, r.player.name, r.player.identifier);
	}]];
	[b keyword:@", each "];
	NSMapTable *names = [self namesFor:roles];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		if (i > 0) {
			[b plain:@", "];
		}
		[b objectType:[names objectForKey:role] id:role.player.identifier];
	}
	[b keyword:@" combination occurs at most once"];
	ORMVerbalSentence *statement = [self emit:b modality:constraint.modality];
	b = [[ORMSentenceBuilder alloc] init];
	[b append:[self clause:[self readingOf:fact from:nil] terms:^ORMSpokenTerm *(ORMRole *r) {
		return ORMMakeTerm(@"the same", r.player.name, r.player.identifier);
	}]];
	[b keyword:@" more than once"];
	[self negate:statement with:b modality:constraint.modality];
}

- (void)verbalizeUnary:(ORMFactType *)fact
{
	ORMRole *role = [[fact visibleRoles] firstObject];
	if (role.isMandatory) {
		self.source = [self constraint:ORMMandatoryConstraint onlyOn:role].identifier;
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b append:[self clause:[self readingOf:fact from:role] terms:^ORMSpokenTerm *(ORMRole *r) {
			return ORMMakeTerm(@"each", r.player.name, r.player.identifier);
		}]];
		[self emit:b];
	}
	ORMCardinality *cardinality = [role cardinality];
	if (cardinality != nil) {
		/* "At most one Politician is president." */
		self.source = cardinality.identifier;
		NSString *quantifier = ORMCardinalityText(cardinality);
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b append:[self clause:[self readingOf:fact from:role] terms:^ORMSpokenTerm *(ORMRole *r) {
			return ORMMakeTerm(quantifier, r.player.name, r.player.identifier);
		}]];
		[self emit:b];
	}
}

/* Ternaries and up: each uniqueness constraint as "For each A and B, that
 * A ... that B ... at most one C", each mandatory role as "Each A ... some
 * B ... some C". */
- (void)verbalizeNary:(ORMFactType *)fact
{
	NSArray *roles = [fact visibleRoles];
	for (ORMConstraint *constraint in [fact uniquenessConstraints]) {
		NSArray *covered = [constraint allRoles];
		if ([covered count] == [roles count]) {
			[self verbalizeSpanningUniqueness:fact roles:roles];
			continue;
		}
		self.source = constraint.identifier;
		NSMapTable *names = [self namesFor:roles];
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"For each "];
		for (NSUInteger i = 0; i < [covered count]; i++) {
			ORMRole *role = [covered objectAtIndex:i];
			if (i > 0) {
				[b keyword:i + 1 == [covered count] ? @" and " : @", "];
			}
			[b objectType:[names objectForKey:role] id:role.player.identifier];
		}
		[b plain:@", "];
		ORMReadingUse *use = [self readingOf:fact from:[covered firstObject]];
		[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
			BOOL inside = [covered containsObject:r];
			return ORMMakeTerm(inside ? @"that" : @"at most one", [names objectForKey:r], r.player.identifier);
		}]];
		ORMVerbalSentence *statement = [self emit:b modality:constraint.modality];
		if ([roles count] - [covered count] == 1) {
			/* "It is impossible that the same Person played the same Sport
			 * for more than one Country." */
			b = [[ORMSentenceBuilder alloc] init];
			[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
				return ORMMakeTerm([covered containsObject:r] ? @"the same" : @"more than one", r.player.name,
				                   r.player.identifier);
			}]];
			[self negate:statement with:b modality:constraint.modality];
		}
	}
	for (ORMRole *role in roles) {
		if (!role.isMandatory) {
			continue;
		}
		ORMConstraint *mandatory = [self constraint:ORMMandatoryConstraint onlyOn:role];
		self.source = mandatory.identifier;
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		ORMReadingUse *use = [self readingOf:fact from:role];
		BOOL fromRole = [use.roles firstObject] == role;
		if (!fromRole) {
			[b keyword:@"For each "];
			[b objectType:role.player.name id:role.player.identifier];
			[b plain:@", "];
		}
		[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
			if (r == role) {
				return ORMMakeTerm(fromRole ? @"each" : @"that", r.player.name, r.player.identifier);
			}
			return ORMMakeTerm(@"some", r.player.name, r.player.identifier);
		}]];
		[self emit:b modality:mandatory.modality];
	}
}

#pragma mark Constraints

/* The clause of a binary fact type read from the role's opposite, as an
 * external constraint uses it: "Person was born in that Country". */
- (NSArray<ORMVerbalSpan *> *)clauseOf:(ORMRole *)role
                                  from:(ORMRole *)start
                                 terms:(ORMSpokenTerm * (^)(ORMRole *r))terms
{
	return [self clause:[self readingOf:role.factType from:start] terms:terms];
}

- (void)verbalizeConstraint:(ORMConstraint *)constraint
{
	self.source = constraint.identifier;
	switch (constraint.kind) {
	case ORMUniquenessConstraint:
		if (!constraint.isInternal) {
			[self verbalizeExternalUniquenessByLogic:constraint];
		}
		if (constraint.preferredIdentifierFor != nil) {
			[self verbalizeIdentification:constraint];
		}
		break;
	case ORMMandatoryConstraint:
		if (!constraint.isSimple && !constraint.isImplied && constraint.exclusiveOrPartner == nil) {
			[self verbalizeDisjunctiveMandatory:constraint];
		}
		break;
	case ORMFrequencyConstraint:
		[self verbalizeFrequency:constraint];
		break;
	case ORMRingConstraint:
		[self verbalizeRing:constraint];
		break;
	case ORMExclusionConstraint:
		[self verbalizeExclusion:constraint];
		break;
	case ORMSubsetConstraint:
		[self verbalizeSubsetByLogic:constraint];
		break;
	case ORMEqualityConstraint:
		[self verbalizeEqualityByLogic:constraint];
		break;
	case ORMValueComparisonConstraint:
		[self verbalizeValueComparison:constraint];
		break;
	}
}

/* The object type every role's opposite is played by, as an external
 * constraint over roles of binaries joins them; nil when there is none. */
- (ORMObjectType *)commonOppositePlayer:(NSArray<ORMRole *> *)roles
{
	ORMObjectType *common = nil;
	for (ORMRole *role in roles) {
		ORMObjectType *player = [role oppositeRole].player;
		if (player == nil || (common != nil && player != common)) {
			return nil;
		}
		common = player;
	}
	return common;
}

- (void)verbalizeIdentification:(ORMConstraint *)constraint
{
	ORMObjectType *identified = constraint.preferredIdentifierFor;
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	[b keyword:@"This association with "];
	NSMutableArray *players = [NSMutableArray array];
	for (ORMRole *role in [constraint allRoles]) {
		if (role.player != nil && [players indexOfObjectIdenticalTo:role.player] == NSNotFound) {
			[players addObject:role.player];
		}
	}
	for (NSUInteger i = 0; i < [players count]; i++) {
		if (i > 0) {
			[b plain:i + 1 == [players count] ? @" and " : @", "];
		}
		ORMObjectType *player = [players objectAtIndex:i];
		[b objectType:player.name id:player.identifier];
	}
	[b keyword:@" provides the preferred identification scheme for "];
	[b objectType:identified.name id:identified.identifier];
	[self emit:b kind:ORMVerbalInformation];
}

/* Clauses joined by a word, each about the shared player, which only the
 * first names: "Each Person has some Name or was born in some Country". */
- (void)appendAlternatives:(NSArray<ORMRole *> *)roles
                    joiner:(NSString *)joiner
                 quantifier:(NSString *)quantifier
                        to:(ORMSentenceBuilder *)b
{
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		ORMReadingUse *use = [self readingOf:role.factType from:role];
		BOOL fromRole = [use.roles firstObject] == role && [self fact:role.factType readsFrom:role];
		if (i > 0) {
			[b keyword:joiner];
		}
		BOOL first = i == 0;
		[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
			if (r == role) {
				if (first) {
					return ORMMakeTerm(quantifier, r.player.name, r.player.identifier);
				}
				return fromRole ? ORMMakeTerm(nil, nil, nil) : ORMMakeTerm(@"that", r.player.name, r.player.identifier);
			}
			return ORMMakeTerm(@"some", r.player.name, r.player.identifier);
		}]];
	}
}

- (void)verbalizeDisjunctiveMandatory:(ORMConstraint *)constraint
{
	NSArray *roles = [constraint allRoles];
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	[self appendAlternatives:roles joiner:@" or " quantifier:@"each" to:b];
	ORMVerbalSentence *statement = [self emit:b modality:constraint.modality];
	/* "It is impossible that some Visitor has no Passport and has no
	 * DriverLicence." */
	NSMutableArray *uses = [NSMutableArray array];
	for (ORMRole *role in roles) {
		[uses addObject:[self readingOf:role.factType from:role]];
	}
	[self negate:statement with:[self noneOf:roles use:uses] modality:constraint.modality];
}

- (NSString *)frequencyText:(ORMConstraint *)constraint
{
	if (constraint.maxFrequency == constraint.minFrequency) {
		return [NSString stringWithFormat:@"exactly %lu", (unsigned long)constraint.minFrequency];
	}
	if (constraint.maxFrequency == 0) {
		return [NSString stringWithFormat:@"at least %lu", (unsigned long)constraint.minFrequency];
	}
	if (constraint.minFrequency <= 1) {
		return [NSString stringWithFormat:@"at most %lu", (unsigned long)constraint.maxFrequency];
	}
	return [NSString stringWithFormat:@"at least %lu and at most %lu", (unsigned long)constraint.minFrequency,
	        (unsigned long)constraint.maxFrequency];
}

- (void)verbalizeFrequency:(ORMConstraint *)constraint
{
	NSArray *roles = [constraint allRoles];
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	NSString *times = [self frequencyText:constraint];
	ORMRole *role = [roles firstObject];
	if ([roles count] == 1 && [role oppositeRole] != nil) {
		/* "Each Person that has some PhoneNr has at least 2 and at most 5
		 * PhoneNr." */
		ORMReadingUse *use = [self readingOf:role.factType from:role];
		BOOL fromRole = [use.roles firstObject] == role && [self fact:role.factType readsFrom:role];
		[b keyword:@"Each "];
		[b objectType:role.player.name id:role.player.identifier];
		[b keyword:@" that "];
		[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
			return r == role ? (fromRole ? ORMMakeTerm(nil, nil, nil) : ORMMakeTerm(@"that", r.player.name, r.player.identifier))
			                 : ORMMakeTerm(@"some", r.player.name, r.player.identifier);
		}]];
		[b plain:@" "];
		[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
			return r == role ? (fromRole ? ORMMakeTerm(nil, nil, nil) : ORMMakeTerm(@"that", r.player.name, r.player.identifier))
			                 : ORMMakeTerm(times, r.player.name, r.player.identifier);
		}]];
		[self emit:b modality:constraint.modality];
		return;
	}
	NSMapTable *names = [self namesFor:roles];
	[b keyword:@"Each "];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *r = [roles objectAtIndex:i];
		if (i > 0) {
			[b plain:@", "];
		}
		[b objectType:[names objectForKey:r] id:r.player.identifier];
	}
	[b keyword:[roles count] > 1 ? @" combination" : @""];
	[b keyword:@" that occurs in the population of "];
	[b append:[self clause:[self readingOf:role.factType from:nil] terms:^ORMSpokenTerm *(ORMRole *r) {
		return ORMMakeTerm(nil, r.player.name, r.player.identifier);
	}]];
	[b keyword:[NSString stringWithFormat:@" occurs there %@ times", times]];
	[self emit:b modality:constraint.modality];
}

/* The ring fact type read with the variables for its two roles: "Person1
 * is parent of Person2". */
- (NSArray<ORMVerbalSpan *> *)ringClause:(ORMConstraint *)constraint
                                    from:(NSString *)a
                                      to:(NSString *)c
                              quantifier:(NSString *)quantifier
{
	NSArray *roles = [constraint allRoles];
	ORMRole *first = [roles firstObject];
	ORMRole *second = [roles lastObject];
	ORMReadingUse *use = [self readingOf:first.factType from:first];
	return [self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
		if (r == first) {
			return ORMMakeTerm(nil, a, first.player.identifier);
		}
		if (r == second) {
			return ORMMakeTerm(quantifier, c, second.player.identifier);
		}
		return ORMMakeTerm(@"some", r.player.name, r.player.identifier);
	}];
}

- (void)verbalizeRing:(ORMConstraint *)constraint
{
	NSArray *roles = [constraint allRoles];
	if ([roles count] != 2) {
		return;
	}
	ORMObjectType *player = [[roles firstObject] player];
	ORMObjectType *other = [[roles lastObject] player];
	NSString *name = player.name ?: @"?";
	/* The two roles' players, numbered when they are one type (a ring
	 * may join subtypes of one type: Girl is going out with Boy). */
	BOOL one = other == player || other == nil;
	NSString *v1 = one ? [name stringByAppendingString:@"1"] : name;
	NSString *v2 = one ? [name stringByAppendingString:@"2"] : (other.name ?: @"?");
	NSString *v3 = [name stringByAppendingString:@"3"];
	ORMRingType type = constraint.ringType;
	ORMModality modality = constraint.modality;

	if (type & ORMRingIrreflexive) {
		/* "No Person is parent of itself." */
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"No "];
		[b append:[self ringClause:constraint from:name to:@"itself" quantifier:nil]];
		ORMVerbalSentence *statement = [self emit:b modality:modality];
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"some "];
		[b append:[self ringClause:constraint from:name to:@"itself" quantifier:nil]];
		[self negate:statement with:b modality:modality];
	}
	if (type & ORMRingPurelyReflexive) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"If "];
		[b append:[self ringClause:constraint from:v1 to:v2 quantifier:nil]];
		[b keyword:@" then "];
		[b objectType:v1 id:player.identifier];
		[b keyword:@" is "];
		[b objectType:v2 id:player.identifier];
		[self emit:b modality:modality];
	}
	if (type & ORMRingReflexive) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"If "];
		[b append:[self ringClause:constraint from:v1 to:v2 quantifier:@"some"]];
		[b keyword:@" then "];
		[b append:[self ringClause:constraint from:v1 to:@"itself" quantifier:nil]];
		[self emit:b modality:modality];
	}
	if (type & ORMRingSymmetric) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"If "];
		[b append:[self ringClause:constraint from:v1 to:v2 quantifier:nil]];
		[b keyword:@" then "];
		[b append:[self ringClause:constraint from:v2 to:v1 quantifier:nil]];
		[self emit:b modality:modality];
	}
	if (type & (ORMRingAsymmetric | ORMRingAntisymmetric)) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"If "];
		[b append:[self ringClause:constraint from:v1 to:v2 quantifier:nil]];
		if (type & ORMRingAntisymmetric) {
			[b keyword:@" and "];
			[b objectType:v1 id:player.identifier];
			[b keyword:@" is not "];
			[b objectType:v2 id:player.identifier];
		}
		[b keyword:@" then it is impossible that "];
		[b append:[self ringClause:constraint from:v2 to:v1 quantifier:nil]];
		ORMVerbalSentence *statement = [self emit:b modality:modality];
		b = [[ORMSentenceBuilder alloc] init];
		[b append:[self ringClause:constraint from:v1 to:v2 quantifier:nil]];
		if (type & ORMRingAntisymmetric) {
			[b keyword:@" and "];
			[b objectType:v1 id:player.identifier];
			[b keyword:@" is not "];
			[b objectType:v2 id:player.identifier];
		}
		[b keyword:@" and "];
		[b append:[self ringClause:constraint from:v2 to:v1 quantifier:nil]];
		[self negate:statement with:b modality:modality];
	}
	if (type & ORMRingTransitive) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"If "];
		[b append:[self ringClause:constraint from:v1 to:v2 quantifier:nil]];
		[b keyword:@" and "];
		[b append:[self ringClause:constraint from:v2 to:v3 quantifier:nil]];
		[b keyword:@" then "];
		[b append:[self ringClause:constraint from:v1 to:v3 quantifier:nil]];
		[self emit:b modality:modality];
	}
	if (type & ORMRingIntransitive) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"If "];
		[b append:[self ringClause:constraint from:v1 to:v2 quantifier:nil]];
		[b keyword:@" and "];
		[b append:[self ringClause:constraint from:v2 to:v3 quantifier:nil]];
		[b keyword:@" then it is impossible that "];
		[b append:[self ringClause:constraint from:v1 to:v3 quantifier:nil]];
		[self emit:b modality:modality];
	}
	if (type & ORMRingStronglyIntransitive) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"If "];
		[b append:[self ringClause:constraint from:v1 to:v2 quantifier:@"some"]];
		[b keyword:@" then it is impossible that "];
		[b objectType:v1 id:player.identifier];
		[b keyword:@" is indirectly related to "];
		[b objectType:v2 id:player.identifier];
		[b keyword:@" by repeatedly applying this fact type"];
		[self emit:b modality:modality];
	}
	if (type & ORMRingAcyclic) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"No "];
		[b objectType:name id:player.identifier];
		[b keyword:@" may cycle back to itself via one or more traversals through "];
		[b append:[self ringClause:constraint from:name to:name quantifier:nil]];
		[self emit:b modality:modality];
	}
}

- (void)verbalizeExclusion:(ORMConstraint *)constraint
{
	NSArray *sequences = constraint.roleSequences;
	if ([sequences count] < 2) {
		return;
	}
	BOOL exclusiveOr = constraint.exclusiveOrPartner != nil;
	NSMutableArray *roles = [NSMutableArray array];
	ORMObjectType *player = nil;
	BOOL singleRoles = YES;
	for (ORMRoleSequence *sequence in sequences) {
		ORMRole *role = [sequence.roles firstObject];
		if ([sequence.roles count] != 1 || (player != nil && role.player != player)) {
			singleRoles = NO;
		}
		player = role.player;
		if (role != nil) {
			[roles addObject:role];
		}
	}
	if (!singleRoles || ([sequences count] > 2)) {
		[self verbalizeExclusionByLogic:constraint];
		return;
	}
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	if (exclusiveOr) {
		/* "Each Person is male or is female but not both." */
		[self appendAlternatives:roles joiner:@" or " quantifier:@"each" to:b];
		[b keyword:@" but not both"];
	} else {
		/* "No Person smokes and drinks." */
		[b keyword:@"No "];
		[self appendAlternatives:roles joiner:@" and " quantifier:nil to:b];
	}
	ORMVerbalSentence *statement = [self emit:b modality:constraint.modality];
	b = [[ORMSentenceBuilder alloc] init];
	[self appendAlternatives:roles joiner:@" and " quantifier:@"some" to:b];
	[self negate:statement with:b modality:constraint.modality];
}

- (void)verbalizeValueComparison:(ORMConstraint *)constraint
{
	NSArray *roles = [constraint allRoles];
	if ([roles count] != 2) {
		return;
	}
	NSDictionary *words = @{ @"Equal": @"is equal to", @"NotEqual": @"is not equal to", @"LessThan": @"is less than",
	                         @"LessThanOrEqual": @"is less than or equal to", @"GreaterThan": @"is greater than",
	                         @"GreaterThanOrEqual": @"is greater than or equal to" };
	ORMRole *a = [roles firstObject];
	ORMRole *c = [roles lastObject];
	ORMObjectType *joined = [self commonOppositePlayer:roles];
	NSMapTable *names = [self namesFor:roles];
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	if (joined != nil) {
		[b keyword:@"For each "];
		[b objectType:joined.name id:joined.identifier];
		[b plain:@", "];
	}
	[b keyword:@"if "];
	for (ORMRole *role in @[ a, c ]) {
		if (role == c) {
			[b keyword:@" and "];
		}
		ORMRole *opposite = [role oppositeRole];
		[b append:[self clauseOf:role from:opposite terms:^ORMSpokenTerm *(ORMRole *r) {
			if (r == role) {
				return ORMMakeTerm(@"some", [names objectForKey:r], r.player.identifier);
			}
			return ORMMakeTerm(@"that", r.player.name, r.player.identifier);
		}]];
	}
	[b keyword:@" then "];
	[b objectType:[names objectForKey:a] id:a.player.identifier];
	[b keyword:[NSString stringWithFormat:@" %@ ", [words objectForKey:constraint.comparisonOperator] ?: @"compares to"]];
	[b objectType:[names objectForKey:c] id:c.player.identifier];
	ORMVerbalSentence *statement = [self emit:b modality:constraint.modality];
	/* "It is impossible that some Project starts on some Date1 and ends
	 * on some Date2 and Date1 is greater than Date2." */
	NSDictionary *opposites = @{ @"Equal": @"NotEqual", @"NotEqual": @"Equal", @"LessThan": @"GreaterThanOrEqual",
	                             @"LessThanOrEqual": @"GreaterThan", @"GreaterThan": @"LessThanOrEqual",
	                             @"GreaterThanOrEqual": @"LessThan" };
	NSString *opposite = [words objectForKey:[opposites objectForKey:constraint.comparisonOperator] ?: @""];
	if (opposite != nil && joined != nil) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"some "];
		[b objectType:joined.name id:joined.identifier];
		for (ORMRole *role in @[ a, c ]) {
			[b keyword:role == a ? @" " : @" and "];
			ORMRole *near = [role oppositeRole];
			BOOL starts = [[[self readingOf:role.factType from:near] roles] firstObject] == near
				&& [self fact:role.factType readsFrom:near];
			[b append:[self clauseOf:role from:near terms:^ORMSpokenTerm *(ORMRole *r) {
				if (r == role) {
					return ORMMakeTerm(@"some", [names objectForKey:r], r.player.identifier);
				}
				return starts ? ORMMakeTerm(nil, nil, nil) : ORMMakeTerm(@"that", r.player.name, r.player.identifier);
			}]];
		}
		[b keyword:@" and "];
		[b objectType:[names objectForKey:a] id:a.player.identifier];
		[b keyword:[NSString stringWithFormat:@" %@ ", opposite]];
		[b objectType:[names objectForKey:c] id:c.player.identifier];
		[self negate:statement with:b modality:constraint.modality];
	}
}

#pragma mark Entry points

- (NSArray<ORMVerbalSentence *> *)sentencesForElement:(NSString *)elementId
{
	_out = [NSMutableArray array];
	_level = 0;
	id element = [self.model elementWithId:elementId];
	if ([element isKindOfClass:[ORMShape class]]) {
		element = [(ORMShape *)element subject];
	}
	if ([element isKindOfClass:[ORMRole class]]) {
		element = [(ORMRole *)element factType];
	} else if ([element isKindOfClass:[ORMReading class]]) {
		element = [[(ORMReading *)element readingOrder] factType];
	} else if ([element isKindOfClass:[ORMReadingOrder class]]) {
		element = [(ORMReadingOrder *)element factType];
	} else if ([element isKindOfClass:[ORMValueConstraint class]]) {
		element = nil;
	}
	_subject = [element identifier];
	if ([element isKindOfClass:[ORMObjectType class]]) {
		[self verbalizeObjectType:element];
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		[self verbalizeFactType:element];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		ORMConstraint *constraint = element;
		if ([constraint isExternal] || constraint.kind == ORMUniquenessConstraint) {
			[self verbalizeConstraint:constraint];
		}
		if ([_out count] == 0) {
			/* An internal constraint is said with its fact type. */
			[self verbalizeFactType:[[constraint factTypes] firstObject]];
		}
		if (constraint.exclusiveOrPartner != nil && constraint.kind == ORMMandatoryConstraint) {
			[self verbalizeConstraint:constraint.exclusiveOrPartner];
		}
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		[self verbalizeText:[(ORMModelNote *)element text] label:@"Note: "];
	}
	NSArray *result = _out;
	_out = nil;
	return result;
}

- (NSArray<ORMVerbalSentence *> *)sentencesForQuery:(ORMQuery *)query
{
	_out = [NSMutableArray array];
	_level = 0;
	[self verbalizeQuery:query];
	return _out;
}

- (NSArray<ORMVerbalSentence *> *)sentencesForModel
{
	NSMutableArray *all = [NSMutableArray array];
	NSArray *types = [[self.model visibleObjectTypes] sortedArrayUsingComparator:^NSComparisonResult(ORMObjectType *a,
	                                                                                                  ORMObjectType *b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	for (ORMObjectType *type in types) {
		[all addObjectsFromArray:[self sentencesForElement:type.identifier]];
	}
	for (ORMFactType *fact in self.model.factTypes) {
		if (fact.kind == ORMFactTypeOrdinary) {
			[all addObjectsFromArray:[self sentencesForElement:fact.identifier]];
		}
	}
	for (ORMConstraint *constraint in [self.model externalConstraints]) {
		/* Frequency and ring constraints within one fact type were said
		 * with it. */
		if ((constraint.kind == ORMFrequencyConstraint || constraint.kind == ORMRingConstraint)
		    && [[constraint factTypes] count] == 1) {
			continue;
		}
		if (constraint.kind == ORMMandatoryConstraint && constraint.exclusiveOrPartner != nil) {
			continue;
		}
		[all addObjectsFromArray:[self sentencesForElement:constraint.identifier]];
	}
	return all;
}

#pragma mark Output

+ (NSString *)plainTextOfSentences:(NSArray<ORMVerbalSentence *> *)sentences
{
	NSMutableString *text = [NSMutableString string];
	for (ORMVerbalSentence *sentence in sentences) {
		for (NSUInteger i = 0; i < sentence.level; i++) {
			[text appendString:@"    "];
		}
		[text appendString:[sentence text]];
		[text appendString:@"\n"];
	}
	return text;
}

static NSString *
ORMEscapeHTML(NSString *text)
{
	NSString *escaped = [text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
	escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
	return [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
}

+ (NSString *)HTMLOfSentences:(NSArray<ORMVerbalSentence *> *)sentences title:(NSString *)title
{
	NSMutableString *html = [NSMutableString string];
	[html appendFormat:@"<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>%@</title>\n", ORMEscapeHTML(title ?: @"")];
	[html appendString:@"<style>\n"
	                   @"body { font-family: Tahoma, Verdana, sans-serif; font-size: 10pt; color: #000; background: #fff; }\n"
	                   @"p { margin: 0 0 2px 0; }\n"
	                   @".keyword { color: #0000ff; }\n"
	                   @".objectType { color: #800080; }\n"
	                   @".predicate { color: #006400; }\n"
	                   @".value { color: #8b0000; }\n"
	                   @".note { color: #000; font-style: italic; }\n"
	                   @"@media (prefers-color-scheme: dark) { body { color: #ddd; background: #1e1e1e; }\n"
	                   @"  .keyword { color: #6fa8ff; } .objectType { color: #e08ae0; } .predicate { color: #7ccf7c; }\n"
	                   @"  .value { color: #f0a070; } .note { color: #ddd; } }\n"
	                   @"</style></head><body>\n"];
	NSArray *classes = @[ @"", @"keyword", @"objectType", @"predicate", @"value", @"note" ];
	for (ORMVerbalSentence *sentence in sentences) {
		[html appendFormat:@"<p style=\"margin-left: %lupx\">", (unsigned long)sentence.level * 24];
		for (ORMVerbalSpan *span in sentence.spans) {
			NSString *class = [classes objectAtIndex:span.style];
			if ([class length] == 0) {
				[html appendString:ORMEscapeHTML(span.text)];
			} else {
				[html appendFormat:@"<span class=\"%@\">%@</span>", class, ORMEscapeHTML(span.text)];
			}
		}
		[html appendString:@"</p>\n"];
	}
	[html appendString:@"</body></html>\n"];
	return html;
}

@end
