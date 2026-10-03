/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMVerbalizer.h"
#import "ORMDiagram.h"
#import "ORMReadingText.h"
#import "ORMXML.h"

@interface ORMVerbalSpan ()
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite) ORMVerbalStyle style;
@property (nonatomic, readwrite, copy) NSString *elementId;
@end

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

@interface ORMVerbalSentence ()
@property (nonatomic, readwrite, copy) NSArray<ORMVerbalSpan *> *spans;
@property (nonatomic, readwrite, copy) NSString *subjectId;
@property (nonatomic, readwrite) NSUInteger level;
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

/* What a placeholder becomes: a quantifier and a name. A nil name leaves
 * the role out, as "Each Person has some Name or was born in ..." leaves
 * Person out of its second clause. */
@interface ORMSpokenTerm : NSObject
@property (nonatomic, copy) NSString *quantifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *elementId;
@end

@implementation ORMSpokenTerm
@end

static ORMSpokenTerm *
ORMMakeTerm(NSString *quantifier, NSString *name, NSString *elementId)
{
	ORMSpokenTerm *term = [[ORMSpokenTerm alloc] init];
	term.quantifier = quantifier;
	term.name = name;
	term.elementId = elementId;
	return term;
}

/* A reading to verbalize with: its text and the roles its placeholders
 * stand for. Subtype facts have none in the file; they get these. */
@interface ORMReadingUse : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<ORMRole *> *roles;
@end

@implementation ORMReadingUse
@end

/* A sentence being put together. */
@interface ORMSentenceBuilder : NSObject
@property (nonatomic, strong) NSMutableArray<ORMVerbalSpan *> *spans;
- (void)keyword:(NSString *)text;
- (void)predicate:(NSString *)text;
- (void)plain:(NSString *)text;
- (void)value:(NSString *)text;
- (void)note:(NSString *)text;
- (void)objectType:(NSString *)name id:(NSString *)elementId;
- (void)append:(NSArray<ORMVerbalSpan *> *)spans;
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

@end

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
	}
	return self;
}

#pragma mark Sentences

- (void)emit:(ORMSentenceBuilder *)builder
{
	[self emit:builder modality:ORMAlethic];
}

/* Ends the sentence and adds it, capitalized, with its modality said:
 * a deontic rule is what is obligatory, not what is necessary. */
- (void)emit:(ORMSentenceBuilder *)builder modality:(ORMModality)modality
{
	NSMutableArray *spans = builder.spans;
	if ([spans count] == 0) {
		return;
	}
	if (modality == ORMDeontic) {
		ORMVerbalSpan *first = [spans firstObject];
		if ([first.text length] > 0) {
			first.text = [[[first.text substringToIndex:1] lowercaseString]
				stringByAppendingString:[first.text substringFromIndex:1]];
		}
		[spans insertObject:[ORMVerbalSpan spanWithText:@"It is obligatory that " style:ORMVerbalKeyword elementId:nil]
		            atIndex:0];
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
	[_out addObject:sentence];
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
		if (role == sup) {
			return [self use:@"{0} is {1}" roles:@[ sup, sub ]];
		}
		return [self use:@"{0} is {1}" roles:@[ sub, sup ]];
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
			if ([t.quantifier length] > 0) {
				[builder keyword:[t.quantifier stringByAppendingString:@" "]];
			}
			[builder predicate:part.preBoundText];
			[builder objectType:t.name id:t.elementId];
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
	[self emit:b];

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
		[self emit:b];
	}
	if (type.isExternal) {
		b = [[ORMSentenceBuilder alloc] init];
		[b objectType:type.name id:type.identifier];
		[b keyword:@" is external"];
		[b plain:@" (defined in another model)"];
		[self emit:b];
	}

	for (ORMObjectType *supertype in type.supertypes) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Each "];
		[b objectType:type.name id:type.identifier];
		[b keyword:@" is an instance of "];
		[b objectType:supertype.name id:supertype.identifier];
		[self emit:b];
	}

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
		[self emit:b];
	} else if (type.isEntity && identifier == nil && [type.supertypes count] == 0 && type.nestedFactType == nil) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Reference Scheme: "];
		[b plain:@"none given"];
		[self emit:b];
	}
	if (type.referenceMode != nil) {
		b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Reference Mode: "];
		NSString *mode = type.referenceModeKind == ORMReferenceModePopular ? [@"." stringByAppendingString:type.referenceMode]
			: type.referenceModeKind == ORMReferenceModeUnitBased ? [type.referenceMode stringByAppendingString:@":"]
			: type.referenceMode;
		[b plain:mode];
		[self emit:b];
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
		[self emit:b];
	}
	if (type.valueConstraint != nil) {
		[self verbalizeValues:type.valueConstraint of:type role:nil];
	}
	[self verbalizeText:type.definitionText label:@"Informal Definition: "];
	[self verbalizeText:type.noteText label:@"Notes: "];
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
	if (fact.kind == ORMFactTypeSubtype) {
		ORMObjectType *sub = [[fact.roles firstObject] player];
		ORMObjectType *sup = [[fact.roles lastObject] player];
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"Each "];
		[b objectType:sub.name id:sub.identifier];
		[b keyword:@" is an instance of "];
		[b objectType:sup.name id:sup.identifier];
		[self emit:b];
		if (!fact.providesPreferredIdentifier) {
			b = [[ORMSentenceBuilder alloc] init];
			[b objectType:sub.name id:sub.identifier];
			[b plain:@" has its own reference scheme, not that of "];
			[b objectType:sup.name id:sup.identifier];
			[self emit:b];
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
	if (fact.isDerived) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"This fact type is derived"];
		NSXMLElement *rule = ORMChild(fact.element, ORMCoreNamespace, @"DerivationRule");
		NSString *note = ORMChildText(ORMChild(rule, ORMCoreNamespace, @"DerivationNote"), ORMCoreNamespace, @"Text");
		[self emit:b];
		[self verbalizeText:note label:@"Derivation Note: "];
	}

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
	_level--;
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
		ORMModality modality = ORMAlethic;
		for (ORMConstraint *constraint in role.constraints) {
			if ([fact.internalConstraints containsObject:constraint] && [[constraint allRoles] count] == 1) {
				modality = MAX(modality, constraint.modality);
			}
		}
		NSString *otherQuantifier = nil;
		if (role.isUnique && role.isMandatory) {
			otherQuantifier = @"exactly one";
		} else if (role.isUnique) {
			otherQuantifier = @"at most one";
		} else if (role.isMandatory) {
			otherQuantifier = @"some";
		}
		if (otherQuantifier != nil) {
			ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
			if (!fromRole) {
				/* No reading starts with the role: say it from its side. */
				[b keyword:@"For each "];
				[b objectType:role.player.name id:role.player.identifier];
				[b plain:@", "];
			}
			NSString *quantifier = otherQuantifier;
			[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
				if (r == role) {
					return ORMMakeTerm(fromRole ? @"each" : @"that", r.player.name, r.player.identifier);
				}
				return ORMMakeTerm(quantifier, r.player.name, r.player.identifier);
			}]];
			[self emit:b modality:modality];
		}
		if (!role.isUnique && self.verbalizesPossibilities && other != nil && !spanning) {
			ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
			[b keyword:@"It is possible that "];
			[b append:[self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
				return ORMMakeTerm(r == role ? @"some" : @"more than one", r.player.name, r.player.identifier);
			}]];
			[self emit:b];
		}
	}
	if (spanning) {
		/* Many to many. */
		if (self.verbalizesPossibilities) {
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
			[self emit:b];
		}
		[self verbalizeSpanningUniqueness:fact roles:roles];
	}
}

- (void)verbalizeSpanningUniqueness:(ORMFactType *)fact roles:(NSArray<ORMRole *> *)roles
{
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
	[self emit:b];
}

- (void)verbalizeUnary:(ORMFactType *)fact
{
	ORMRole *role = [[fact visibleRoles] firstObject];
	if (role.isMandatory) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b append:[self clause:[self readingOf:fact from:role] terms:^ORMSpokenTerm *(ORMRole *r) {
			return ORMMakeTerm(@"each", r.player.name, r.player.identifier);
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
		[b append:[self clause:[self readingOf:fact from:[covered firstObject]] terms:^ORMSpokenTerm *(ORMRole *r) {
			BOOL inside = [covered containsObject:r];
			return ORMMakeTerm(inside ? @"that" : @"at most one", [names objectForKey:r], r.player.identifier);
		}]];
		[self emit:b modality:constraint.modality];
	}
	for (ORMRole *role in roles) {
		if (!role.isMandatory) {
			continue;
		}
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
		[self emit:b];
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
	switch (constraint.kind) {
	case ORMUniquenessConstraint:
		if (!constraint.isInternal) {
			[self verbalizeExternalUniqueness:constraint];
		} else if (constraint.preferredIdentifierFor != nil) {
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
	case ORMEqualityConstraint:
		[self verbalizeSetComparison:constraint];
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

- (void)verbalizeExternalUniqueness:(ORMConstraint *)constraint
{
	NSArray *roles = [constraint allRoles];
	ORMObjectType *joined = [self commonOppositePlayer:roles];
	NSMapTable *names = [self namesFor:roles];
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	[b keyword:@"For each "];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		if (i > 0) {
			[b keyword:i + 1 == [roles count] ? @" and " : @", "];
		}
		[b objectType:[names objectForKey:role] id:role.player.identifier];
	}
	[b plain:@", "];
	if (joined == nil) {
		/* Not over binaries sharing a player: say it of the combination. */
		[b keyword:@"that combination occurs at most once"];
		[self emit:b modality:constraint.modality];
		return;
	}
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		ORMRole *opposite = [role oppositeRole];
		if (i > 0) {
			[b keyword:@" and "];
		}
		BOOL first = i == 0;
		/* Later clauses leave the joined player out when they start with
		 * it, and name it again when they do not. */
		BOOL startsWithJoined = [[[self readingOf:role.factType from:opposite] roles] firstObject] == opposite;
		[b append:[self clauseOf:role from:opposite terms:^ORMSpokenTerm *(ORMRole *r) {
			if (r == opposite) {
				if (first) {
					return ORMMakeTerm(@"at most one", joined.name, joined.identifier);
				}
				return startsWithJoined ? ORMMakeTerm(nil, nil, nil) : ORMMakeTerm(@"that", joined.name, joined.identifier);
			}
			return ORMMakeTerm(@"that", [names objectForKey:r], r.player.identifier);
		}]];
	}
	[self emit:b modality:constraint.modality];
	if (constraint.preferredIdentifierFor != nil) {
		[self verbalizeIdentification:constraint];
	}
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
	[self emit:b];
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
		BOOL fromRole = [use.roles firstObject] == role;
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
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	[self appendAlternatives:[constraint allRoles] joiner:@" or " quantifier:@"each" to:b];
	[self emit:b modality:constraint.modality];
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
		BOOL fromRole = [use.roles firstObject] == role;
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
	ORMObjectType *player = first.player;
	return [self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
		if (r == first) {
			return ORMMakeTerm(nil, a, player.identifier);
		}
		if (r == second) {
			return ORMMakeTerm(quantifier, c, player.identifier);
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
	NSString *name = player.name ?: @"?";
	NSString *v1 = [name stringByAppendingString:@"1"];
	NSString *v2 = [name stringByAppendingString:@"2"];
	NSString *v3 = [name stringByAppendingString:@"3"];
	ORMRingType type = constraint.ringType;
	ORMModality modality = constraint.modality;

	if (type & ORMRingIrreflexive) {
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"No "];
		[b append:[self ringClause:constraint from:name to:name quantifier:@"the same"]];
		[self emit:b modality:modality];
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
		[self emit:b modality:modality];
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

/* Each sequence's clause about the shared variables: in a subset or
 * equality the roles at one place across sequences stand for the same
 * instance. */
- (NSArray<ORMVerbalSpan *> *)sequenceClause:(ORMRoleSequence *)sequence
                                       names:(NSArray<NSString *> *)names
                                   quantifier:(NSString *)quantifier
                                       others:(NSString *)others
{
	ORMRole *start = [sequence.roles firstObject];
	ORMReadingUse *use = [self readingOf:start.factType from:start];
	return [self clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
		NSUInteger place = [sequence.roles indexOfObjectIdenticalTo:r];
		if (place != NSNotFound) {
			return ORMMakeTerm(quantifier, [names objectAtIndex:place], r.player.identifier);
		}
		return ORMMakeTerm(others, r.player.name, r.player.identifier);
	}];
}

- (NSArray<NSString *> *)variablesFor:(ORMRoleSequence *)sequence
{
	NSMapTable *names = [self namesFor:sequence.roles];
	NSMutableArray *variables = [NSMutableArray array];
	for (ORMRole *role in sequence.roles) {
		[variables addObject:[names objectForKey:role]];
	}
	return variables;
}

- (void)verbalizeSetComparison:(ORMConstraint *)constraint
{
	if ([constraint.roleSequences count] < 2) {
		return;
	}
	ORMRoleSequence *first = [constraint.roleSequences objectAtIndex:0];
	NSArray *names = [self variablesFor:first];
	if (constraint.kind == ORMSubsetConstraint) {
		ORMRoleSequence *second = [constraint.roleSequences objectAtIndex:1];
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"If "];
		[b append:[self sequenceClause:first names:names quantifier:@"some" others:@"some"]];
		[b keyword:@" then "];
		[b append:[self sequenceClause:second names:names quantifier:@"that" others:@"some"]];
		[self emit:b modality:constraint.modality];
		return;
	}
	/* Equality: each pair of sequences holds together or not at all. */
	for (NSUInteger i = 1; i < [constraint.roleSequences count]; i++) {
		ORMRoleSequence *other = [constraint.roleSequences objectAtIndex:i];
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b append:[self sequenceClause:first names:names quantifier:@"some" others:@"some"]];
		[b keyword:@" if and only if "];
		[b append:[self sequenceClause:other names:names quantifier:@"that" others:@"some"]];
		[self emit:b modality:constraint.modality];
	}
}

- (void)verbalizeExclusion:(ORMConstraint *)constraint
{
	NSArray *sequences = constraint.roleSequences;
	if ([sequences count] < 2) {
		return;
	}
	BOOL exclusiveOr = constraint.exclusiveOrPartner != nil;
	BOOL singleRoles = YES;
	for (ORMRoleSequence *sequence in sequences) {
		if ([sequence.roles count] != 1) {
			singleRoles = NO;
		}
	}
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	if (singleRoles && [sequences count] == 2 && !exclusiveOr) {
		/* "No Person smokes and drinks." */
		NSMutableArray *roles = [NSMutableArray array];
		for (ORMRoleSequence *sequence in sequences) {
			[roles addObject:[sequence.roles firstObject]];
		}
		[b keyword:@"No "];
		[self appendAlternatives:roles joiner:@" and " quantifier:nil to:b];
		[self emit:b modality:constraint.modality];
		return;
	}
	ORMRoleSequence *first = [sequences firstObject];
	NSArray *names = [self variablesFor:first];
	[b keyword:@"For each "];
	for (NSUInteger i = 0; i < [names count]; i++) {
		if (i > 0) {
			[b keyword:i + 1 == [names count] ? @" and " : @", "];
		}
		[b objectType:[names objectAtIndex:i] id:[[first.roles objectAtIndex:i] player].identifier];
	}
	[b plain:@", "];
	[b keyword:exclusiveOr ? @"exactly one of the following holds: " : @"at most one of the following holds: "];
	for (NSUInteger i = 0; i < [sequences count]; i++) {
		if (i > 0) {
			[b plain:@"; "];
		}
		[b append:[self sequenceClause:[sequences objectAtIndex:i] names:names quantifier:@"that" others:@"some"]];
	}
	[self emit:b modality:constraint.modality];
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
	[self emit:b modality:constraint.modality];
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
