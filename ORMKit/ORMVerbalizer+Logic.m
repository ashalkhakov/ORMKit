/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMVerbalizerPriv.h"
#import "ORMQuery.h"
#import "ORMReadingText.h"

/* What ORMLogic says, said in FORML: the constraints that span fact types
 * or follow join paths, and derivation rules.
 *
 * A formula is said as a chain of clauses from a head variable. Each
 * variable is introduced with its quantifier the first time ("some Lot",
 * "at most one Region") and named again after ("that Lot", or "Person2"
 * where variables of one type are numbered). A clause goes on from the
 * last object type it named as a relative clause when a reading starts
 * there ("...is of some LotType that tracks lot numbers"), from its
 * subject with "and" ("...is part of that Country and has that
 * RegionISOCode"), or else as a clause of its own. */

/* The state of one sentence: who has been named, how each is introduced,
 * which variables stand for the same instance. */
@interface ORMPhrase : NSObject
- (instancetype)initWithVerbalizer:(ORMVerbalizer *)verbalizer;
@property (nonatomic, weak) ORMVerbalizer *verbalizer;
/* The variable another stands for: a subset's superset columns are its
 * subset columns. */
- (void)alias:(ORMVariable *)variable to:(ORMVariable *)target;
- (ORMVariable *)canonical:(ORMVariable *)variable;
/* The quantifier a variable is introduced with; "some" when not set,
 * none for NSNull. */
- (void)introduce:(ORMVariable *)variable with:(id)quantifier;
- (BOOL)isMentioned:(ORMVariable *)variable;
- (void)mention:(ORMVariable *)variable;
/* Numbers the variables of a type where more than one is named and one
 * of them more than once: "Person1 is parent of some Person2". */
- (void)numberFormulas:(NSArray<ORMFormula *> *)formulas columns:(NSArray<ORMVariable *> *)columns;
- (NSString *)nameOf:(ORMVariable *)variable;
/* "Country and RegionISOCode", each named and counted as mentioned. */
- (void)list:(NSArray<ORMVariable *> *)variables into:(ORMSentenceBuilder *)b;
/* The formula from the head; when relative, the head was just named and
 * the first clause attaches to it ("a Person who ..."). */
- (void)say:(ORMFormula *)formula from:(ORMVariable *)head relative:(BOOL)relative into:(ORMSentenceBuilder *)b;
- (ORMSpokenTerm *)termFor:(ORMVariable *)variable;
@end

static void
ORMFlatten(ORMFormula *formula, NSMutableArray *parts)
{
	if (formula == nil) {
		return;
	}
	if (formula.kind == ORMFormulaAnd) {
		for (ORMFormula *child in formula.children) {
			ORMFlatten(child, parts);
		}
		return;
	}
	[parts addObject:formula];
}

static NSString *
ORMComparisonWords(NSString *name)
{
	NSString *key = [[name stringByReplacingOccurrencesOfString:@"_" withString:@""] lowercaseString];
	NSDictionary *words = @{ @"equal": @"is equal to", @"equals": @"is equal to", @"notequal": @"is not equal to",
	                         @"lessthan": @"is less than", @"lessthanorequal": @"is less than or equal to",
	                         @"greaterthan": @"is greater than", @"greaterthanorequal": @"is greater than or equal to",
	                         @"=": @"is", @"<>": @"is not", @"!=": @"is not", @"<": @"is less than",
	                         @"<=": @"is at most", @">": @"is greater than", @">=": @"is at least" };
	return [words objectForKey:key];
}

@implementation ORMPhrase
{
	NSMapTable *_aliases;
	NSMapTable *_quantifiers;
	NSHashTable *_mentioned;
	NSMapTable *_values;
}

- (instancetype)initWithVerbalizer:(ORMVerbalizer *)verbalizer
{
	if ((self = [super init])) {
		_verbalizer = verbalizer;
		_aliases = [NSMapTable strongToStrongObjectsMapTable];
		_quantifiers = [NSMapTable strongToStrongObjectsMapTable];
		_mentioned = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
		_values = [NSMapTable strongToStrongObjectsMapTable];
	}
	return self;
}

- (void)alias:(ORMVariable *)variable to:(ORMVariable *)target
{
	if (variable != nil && target != nil && variable != target) {
		[_aliases setObject:target forKey:variable];
	}
}

- (ORMVariable *)canonical:(ORMVariable *)variable
{
	ORMVariable *target = variable;
	for (NSUInteger hops = 0; [_aliases objectForKey:target] != nil && hops < 64; hops++) {
		target = [_aliases objectForKey:target];
	}
	return target;
}

- (void)introduce:(ORMVariable *)variable with:(id)quantifier
{
	[_quantifiers setObject:quantifier ?: [NSNull null] forKey:[self canonical:variable]];
}

- (BOOL)isMentioned:(ORMVariable *)variable
{
	return [_mentioned containsObject:[self canonical:variable]];
}

- (void)mention:(ORMVariable *)variable
{
	[_mentioned addObject:[self canonical:variable]];
}

- (void)count:(ORMTerm *)term into:(NSCountedSet *)counts
{
	if (term.variable != nil) {
		[counts addObject:[NSValue valueWithNonretainedObject:[self canonical:term.variable]]];
	}
	for (ORMTerm *argument in term.arguments) {
		[self count:argument into:counts];
	}
	if (term.group != nil) {
		[self count:term.group into:counts];
	}
}

- (void)countFormula:(ORMFormula *)formula into:(NSCountedSet *)counts
{
	for (ORMTerm *term in [formula.terms allValues]) {
		[self count:term into:counts];
	}
	for (ORMTerm *term in formula.operands) {
		[self count:term into:counts];
	}
	if (formula.variable != nil) {
		[counts addObject:[NSValue valueWithNonretainedObject:[self canonical:formula.variable]]];
	}
	for (ORMFormula *child in formula.children) {
		[self countFormula:child into:counts];
	}
}

- (void)numberFormulas:(NSArray<ORMFormula *> *)formulas columns:(NSArray<ORMVariable *> *)columns
{
	NSCountedSet *counts = [[NSCountedSet alloc] init];
	NSMutableArray *variables = [NSMutableArray array];
	for (ORMVariable *column in columns) {
		[counts addObject:[NSValue valueWithNonretainedObject:[self canonical:column]]];
	}
	for (ORMFormula *formula in formulas) {
		[self countFormula:formula into:counts];
		for (ORMVariable *variable in [formula variables]) {
			ORMVariable *canonical = [self canonical:variable];
			if ([variables indexOfObjectIdenticalTo:canonical] == NSNotFound) {
				[variables addObject:canonical];
			}
		}
	}
	for (ORMVariable *column in columns) {
		ORMVariable *canonical = [self canonical:column];
		if ([variables indexOfObjectIdenticalTo:canonical] == NSNotFound) {
			[variables insertObject:canonical atIndex:0];
		}
	}
	/* By type: numbered when two or more and one is named again. */
	NSMutableArray *types = [NSMutableArray array];
	for (ORMVariable *variable in variables) {
		if (variable.objectType != nil && [types indexOfObjectIdenticalTo:variable.objectType] == NSNotFound) {
			[types addObject:variable.objectType];
		}
	}
	for (ORMObjectType *type in types) {
		NSMutableArray *same = [NSMutableArray array];
		BOOL again = NO;
		for (ORMVariable *variable in variables) {
			if (variable.objectType == type) {
				[same addObject:variable];
				again = again || [counts countForObject:[NSValue valueWithNonretainedObject:variable]] > 1;
			}
		}
		if ([same count] > 1 && again) {
			[ORMLogic numberVariables:same];
		} else {
			for (ORMVariable *variable in same) {
				variable.ordinal = 0;
			}
		}
	}
}

- (NSString *)nameOf:(ORMVariable *)variable
{
	ORMVariable *canonical = [self canonical:variable];
	NSString *name = canonical.objectType.name ?: @"?";
	return canonical.ordinal > 0 ? [NSString stringWithFormat:@"%@%lu", name, (unsigned long)canonical.ordinal] : name;
}

- (void)list:(NSArray<ORMVariable *> *)variables into:(ORMSentenceBuilder *)b
{
	NSMutableArray *distinct = [NSMutableArray array];
	for (ORMVariable *variable in variables) {
		ORMVariable *canonical = [self canonical:variable];
		if ([distinct indexOfObjectIdenticalTo:canonical] == NSNotFound) {
			[distinct addObject:canonical];
		}
	}
	for (NSUInteger i = 0; i < [distinct count]; i++) {
		ORMVariable *variable = [distinct objectAtIndex:i];
		if (i > 0) {
			[b keyword:i + 1 == [distinct count] ? @" and " : @", "];
		}
		[b objectType:[self nameOf:variable] id:variable.objectType.identifier];
		[self mention:variable];
	}
}

- (ORMSpokenTerm *)termFor:(ORMVariable *)variable
{
	ORMVariable *canonical = [self canonical:variable];
	NSString *name = [self nameOf:canonical];
	NSString *identifier = canonical.objectType.identifier;
	if ([self isMentioned:canonical]) {
		return ORMMakeTerm(canonical.ordinal > 0 ? nil : @"that", name, identifier);
	}
	[self mention:canonical];
	id quantifier = [_quantifiers objectForKey:canonical] ?: @"some";
	ORMSpokenTerm *term = ORMMakeTerm(quantifier == [NSNull null] ? nil : quantifier, name, identifier);
	ORMValueConstraint *values = [_values objectForKey:canonical];
	if (values != nil) {
		/* "has Gender 'M'": a value restriction names the value. */
		NSString *text = [values displayText];
		if ([values.ranges count] == 1 && [[[values.ranges firstObject] minValue]
		                                       isEqualToString:[[values.ranges firstObject] maxValue]]) {
			term.quantifier = nil;
			term.value = [text substringWithRange:NSMakeRange(1, [text length] - 2)];
		} else {
			term.value = [@"in " stringByAppendingString:text];
		}
	}
	return term;
}

/* The fact formula's variable for the role. */
- (ORMVariable *)variableOf:(ORMFormula *)fact role:(ORMRole *)role
{
	ORMVariable *variable = [[fact.terms objectForKey:role.identifier] variable];
	return variable != nil ? [self canonical:variable] : nil;
}

/* The role of the fact formula the variable plays, if any. */
- (ORMRole *)roleOf:(ORMVariable *)variable in:(ORMFormula *)fact
{
	if (variable == nil || fact.kind != ORMFormulaFact) {
		return nil;
	}
	for (ORMRole *role in fact.factType.roles) {
		if ([self variableOf:fact role:role] == variable) {
			return role;
		}
	}
	return nil;
}

/* The variable a clause ends with, when it ends at a name: what a
 * relative clause can go on from. */
- (ORMVariable *)tailOf:(ORMReadingUse *)use in:(ORMFormula *)fact
{
	ORMReadingText *text = [ORMReadingText readingTextWithString:use.text arity:[use.roles count] reason:NULL];
	ORMReadingPart *last = [text.parts lastObject];
	if (last == nil || [[last.followingText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
	                       length] > 0 || [last.postBoundText length] > 0 || last.roleIndex >= [use.roles count]) {
		return nil;
	}
	return [self variableOf:fact role:[use.roles objectAtIndex:last.roleIndex]];
}

- (NSString *)pronounFor:(ORMVariable *)variable
{
	return [self canonical:variable].objectType.isPersonal ? @"who" : @"that";
}

/* A fact formula said from the role, the variable there left out when
 * omit is set: the clause goes on from it. */
- (void)sayFact:(ORMFormula *)fact from:(ORMRole *)role omit:(ORMVariable *)omit into:(ORMSentenceBuilder *)b
           tail:(ORMVariable **)tail
{
	ORMVerbalizer *verbalizer = self.verbalizer;
	ORMReadingUse *use = [verbalizer readingOf:fact.factType from:role];
	if (fact.isOptional) {
		[b keyword:@"possibly "];
	}
	NSArray *spans = [verbalizer clause:use terms:^ORMSpokenTerm *(ORMRole *r) {
		ORMTerm *term = [fact.terms objectForKey:r.identifier];
		if (term.variable == nil) {
			ORMSpokenTerm *constant = ORMMakeTerm(nil, r.player.name, r.player.identifier);
			constant.value = term.constant;
			return constant;
		}
		ORMVariable *variable = [self canonical:term.variable];
		if (omit != nil && variable == omit && r == role) {
			return ORMMakeTerm(nil, nil, nil);
		}
		return [self termFor:variable];
	}];
	[b append:spans];
	if (tail != NULL) {
		*tail = [self tailOf:use in:fact];
	}
}

- (void)sayTerm:(ORMTerm *)term into:(ORMSentenceBuilder *)b
{
	if (term.variable != nil) {
		ORMSpokenTerm *spoken = [self termFor:term.variable];
		if ([spoken.quantifier length] > 0) {
			[b keyword:[spoken.quantifier stringByAppendingString:@" "]];
		}
		[b objectType:spoken.name id:spoken.elementId];
	} else if (term.constant != nil) {
		[b value:term.constant];
	} else {
		/* count(x): how many there are. */
		NSString *function = [term.functionName isEqualToString:@"count"] ? @"number" : term.functionName;
		[b keyword:[NSString stringWithFormat:@"the %@ of ", function ?: @"?"]];
		for (NSUInteger i = 0; i < [term.arguments count]; i++) {
			if (i > 0) {
				[b keyword:@" and "];
			}
			[self sayTerm:[term.arguments objectAtIndex:i] into:b];
		}
		if (term.group != nil) {
			[b keyword:@" for "];
			[self sayTerm:term.group into:b];
		}
	}
}

/* Anything but a fact: a negation, a choice, a comparison. */
- (void)sayOther:(ORMFormula *)formula into:(ORMSentenceBuilder *)b
{
	switch (formula.kind) {
	case ORMFormulaNot:
		[b keyword:@"it is not true that "];
		[self say:[formula.children firstObject] from:nil relative:NO into:b];
		break;
	case ORMFormulaOr:
	case ORMFormulaXor: {
		BOOL xor = formula.kind == ORMFormulaXor;
		if (xor && [formula.children count] > 2) {
			[b keyword:@"exactly one of the following holds: "];
		} else if ([formula.children count] > 1) {
			[b keyword:@"either "];
		}
		for (NSUInteger i = 0; i < [formula.children count]; i++) {
			if (i > 0) {
				[b keyword:xor && [formula.children count] > 2 ? @"; " : @" or "];
			}
			[self say:[formula.children objectAtIndex:i] from:nil relative:NO into:b];
		}
		if (xor && [formula.children count] == 2) {
			[b keyword:@" but not both"];
		}
		break;
	}
	case ORMFormulaComparison: {
		NSString *words = ORMComparisonWords(formula.comparison);
		if (words != nil && [formula.operands count] == 2) {
			[self sayTerm:[formula.operands firstObject] into:b];
			[b keyword:[NSString stringWithFormat:@" %@ ", words]];
			[self sayTerm:[formula.operands lastObject] into:b];
		} else {
			[self sayTerm:[ORMTerm termWithFunction:formula.comparison arguments:formula.operands aggregate:NO] into:b];
			[b keyword:@" holds"];
		}
		break;
	}
	case ORMFormulaIdentity:
		[self sayTerm:[formula.operands firstObject] into:b];
		[b keyword:@" is "];
		[self sayTerm:[formula.operands lastObject] into:b];
		break;
	case ORMFormulaValueIn: {
		ORMSpokenTerm *spoken = [self termFor:formula.variable];
		[b keyword:spoken.quantifier ? [spoken.quantifier stringByAppendingString:@" "] : @""];
		[b objectType:spoken.name id:spoken.elementId];
		[b keyword:@" is in "];
		[b value:[formula.values displayText]];
		break;
	}
	default:
		[self say:formula from:nil relative:NO into:b];
		break;
	}
}

- (void)say:(ORMFormula *)formula from:(ORMVariable *)head relative:(BOOL)relative into:(ORMSentenceBuilder *)b
{
	NSMutableArray *pending = [NSMutableArray array];
	ORMFlatten(formula, pending);
	/* Value restrictions name the value where the variable is
	 * introduced. */
	for (ORMFormula *part in [pending copy]) {
		if (part.kind == ORMFormulaValueIn && ![self isMentioned:part.variable]) {
			BOOL inFact = NO;
			for (ORMFormula *other in pending) {
				inFact = inFact || [self roleOf:[self canonical:part.variable] in:other] != nil;
			}
			if (inFact) {
				[_values setObject:part.values forKey:[self canonical:part.variable]];
				[pending removeObjectIdenticalTo:part];
			}
		}
	}
	ORMVariable *subject = head != nil ? [self canonical:head] : nil;
	ORMVariable *tail = nil;
	BOOL first = YES;
	BOOL nested = NO;
	while ([pending count] > 0) {
		ORMFormula *next = nil;
		ORMRole *from = nil;
		ORMVariable *omit = nil;
		NSString *joiner = first ? @"" : @" and ";
		/* On from where the last clause ended. */
		for (ORMFormula *part in pending) {
			ORMRole *role = [self roleOf:tail in:part];
			if (next == nil && role != nil && [self.verbalizer fact:part.factType readsFrom:role]) {
				next = part;
				from = role;
				omit = tail;
				joiner = [NSString stringWithFormat:@" %@ ", [self pronounFor:tail]];
			}
		}
		/* On from the subject. */
		for (ORMFormula *part in pending) {
			ORMRole *role = [self roleOf:subject in:part];
			if (next == nil && role != nil && [self.verbalizer fact:part.factType readsFrom:role]) {
				next = part;
				from = role;
				if (first && relative) {
					omit = subject;
					joiner = [NSString stringWithFormat:@" %@ ", [self pronounFor:subject]];
				} else if (!first && !nested) {
					omit = subject;
				}
			}
		}
		/* About something already named. */
		for (ORMFormula *part in pending) {
			if (next != nil || part.kind != ORMFormulaFact) {
				continue;
			}
			for (ORMRole *role in part.factType.roles) {
				ORMVariable *variable = [self variableOf:part role:role];
				if (variable != nil && [self isMentioned:variable]) {
					next = part;
					if (from == nil && [self.verbalizer fact:part.factType readsFrom:role]) {
						from = role;
					}
				}
			}
		}
		if (next == nil) {
			next = [pending firstObject];
		}
		if (first && relative && omit == nil) {
			/* No reading goes on from what was just named. */
			joiner = @" where ";
		}
		[pending removeObjectIdenticalTo:next];
		[b keyword:joiner];
		if (next.kind == ORMFormulaFact) {
			ORMVariable *ended = nil;
			[self sayFact:next from:from omit:omit into:b tail:&ended];
			if (omit != nil && omit == tail) {
				nested = YES;
			}
			tail = ended;
		} else {
			[self sayOther:next into:b];
			tail = nil;
		}
		first = NO;
	}
}

@end

@implementation ORMVerbalizer (ORMLogicVerbalizing)

- (ORMPhrase *)phrase
{
	return [[ORMPhrase alloc] initWithVerbalizer:self];
}

/* The variable the formula is about first: the first column it has. */
- (ORMVariable *)headOf:(ORMRelation *)relation phrase:(ORMPhrase *)phrase
{
	NSArray *variables = [relation.formula variables];
	for (ORMVariable *column in relation.columns) {
		for (ORMVariable *variable in variables) {
			if ([phrase canonical:variable] == [phrase canonical:column]) {
				return column;
			}
		}
	}
	return [variables firstObject];
}

/* The relations of a constraint's sequences, every one's columns made the
 * first's. */
- (NSArray<ORMRelation *> *)relationsOf:(ORMConstraint *)constraint phrase:(ORMPhrase *)phrase
{
	NSMutableArray *relations = [NSMutableArray array];
	for (ORMRoleSequence *sequence in constraint.roleSequences) {
		ORMRelation *relation = [ORMLogic relationForSequence:sequence];
		ORMRelation *first = [relations firstObject];
		for (NSUInteger i = 0; first != nil && i < MIN([first.columns count], [relation.columns count]); i++) {
			[phrase alias:[relation.columns objectAtIndex:i] to:[first.columns objectAtIndex:i]];
		}
		[relations addObject:relation];
	}
	return relations;
}

/* The formula without the facts another already says of the same
 * variables: a superset that repeats its subset's fact need not. */
- (ORMFormula *)formula:(ORMFormula *)formula without:(ORMFormula *)said phrase:(ORMPhrase *)phrase
{
	NSMutableArray *parts = [NSMutableArray array];
	ORMFlatten(formula, parts);
	NSMutableArray *kept = [NSMutableArray array];
	for (ORMFormula *part in parts) {
		BOOL repeated = NO;
		for (ORMFormula *other in [said facts]) {
			if (part.kind != ORMFormulaFact || other.factType != part.factType) {
				continue;
			}
			BOOL same = YES;
			for (ORMRole *role in part.factType.roles) {
				ORMVariable *mine = [part variableForRole:role];
				ORMVariable *theirs = [other variableForRole:role];
				if ((mine == nil) != (theirs == nil) || (mine != nil && [phrase canonical:mine] != [phrase canonical:theirs])) {
					same = NO;
				}
			}
			repeated = repeated || same;
		}
		/* Left out only when what it names is still named: else the
		 * superset would not say which instances it compares ("then that
		 * Lot is of that LotType that tracks lot numbers"). */
		if (repeated) {
			for (ORMVariable *variable in [part variables]) {
				BOOL elsewhere = NO;
				for (ORMFormula *other in parts) {
					if (other == part) {
						continue;
					}
					for (ORMVariable *named in [other variables]) {
						elsewhere = elsewhere || [phrase canonical:named] == [phrase canonical:variable];
					}
				}
				repeated = repeated && elsewhere;
			}
		}
		if (!repeated) {
			[kept addObject:part];
		}
	}
	return [ORMFormula combine:ORMFormulaAnd children:kept];
}

#pragma mark External uniqueness

/* "For each Country and RegionISOCode, at most one Region is part of that
 * Country and has that RegionISOCode." */
- (void)verbalizeExternalUniquenessByLogic:(ORMConstraint *)constraint
{
	ORMRoleSequence *sequence = [constraint.roleSequences firstObject];
	ORMSentenceBuilder *(^build)(BOOL) = ^ORMSentenceBuilder *(BOOL negative) {
		ORMPhrase *phrase = [self phrase];
		ORMRelation *relation = [ORMLogic relationForSequence:sequence];
		ORMVariable *joined = nil;
		for (ORMVariable *variable in [relation.formula variables]) {
			if (joined == nil && [relation.columns indexOfObjectIdenticalTo:variable] == NSNotFound) {
				joined = variable;
			}
		}
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		if (joined == nil) {
			return (ORMSentenceBuilder *)nil;
		}
		[phrase numberFormulas:@[ relation.formula ] columns:negative ? @[] : relation.columns];
		if (negative) {
			/* "It is impossible that more than one Region is part of the
			 * same Country and has the same RegionISOCode." */
			for (ORMVariable *column in relation.columns) {
				[phrase introduce:column with:@"the same"];
			}
			[phrase introduce:joined with:@"more than one"];
		} else {
			[b keyword:@"For each "];
			[phrase list:relation.columns into:b];
			[b plain:@", "];
			[phrase introduce:joined with:@"at most one"];
		}
		[phrase say:relation.formula from:joined relative:NO into:b];
		return b;
	};
	ORMSentenceBuilder *positive = build(NO);
	if (positive == nil) {
		/* Nothing joins them: say it of the combination. */
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		ORMPhrase *phrase = [self phrase];
		ORMRelation *relation = [ORMLogic relationForSequence:sequence];
		[phrase numberFormulas:@[] columns:relation.columns];
		[b keyword:@"For each "];
		[phrase list:relation.columns into:b];
		[b plain:@", "];
		[b keyword:@"that combination occurs at most once"];
		[self emit:b modality:constraint.modality];
		return;
	}
	ORMVerbalSentence *statement = [self emit:positive modality:constraint.modality];
	[self negate:statement with:build(YES) modality:constraint.modality];
}

#pragma mark Set comparison

/* "If some Lot has some LotNumber and is of some LotType then that LotType
 * tracks lot numbers." */
- (void)verbalizeSubsetByLogic:(ORMConstraint *)constraint
{
	if ([constraint.roleSequences count] < 2) {
		return;
	}
	ORMSentenceBuilder *(^build)(BOOL) = ^ORMSentenceBuilder *(BOOL negative) {
		ORMPhrase *phrase = [self phrase];
		NSArray *relations = [self relationsOf:constraint phrase:phrase];
		ORMRelation *subset = [relations objectAtIndex:0];
		ORMRelation *superset = [relations objectAtIndex:1];
		ORMFormula *rest = [self formula:superset.formula without:subset.formula phrase:phrase];
		[phrase numberFormulas:@[ subset.formula, rest ] columns:@[]];
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		if (!negative) {
			[b keyword:@"if "];
		}
		[phrase say:subset.formula from:[self headOf:subset phrase:phrase] relative:NO into:b];
		[b keyword:negative ? @" and it is not true that " : @" then "];
		ORMRelation *restRelation = superset;
		ORMVariable *head = nil;
		for (ORMVariable *column in restRelation.columns) {
			for (ORMFormula *fact in [rest facts]) {
				for (ORMRole *role in fact.factType.roles) {
					if (head == nil && [phrase canonical:[fact variableForRole:role]] == [phrase canonical:column]) {
						head = column;
					}
				}
			}
		}
		[phrase say:rest from:head relative:NO into:b];
		return b;
	};
	ORMVerbalSentence *statement = [self emit:build(NO) modality:constraint.modality];
	[self negate:statement with:build(YES) modality:constraint.modality];
}

/* "For each Address and Region, that Address is in that Region if and
 * only if that Address is in some Country and that Region is part of that
 * Country." */
- (void)verbalizeEqualityByLogic:(ORMConstraint *)constraint
{
	ORMPhrase *probe = [self phrase];
	NSArray *all = [self relationsOf:constraint phrase:probe];
	for (NSUInteger i = 1; i < [all count]; i++) {
		ORMPhrase *phrase = [self phrase];
		NSArray *relations = [self relationsOf:constraint phrase:phrase];
		ORMRelation *first = [relations firstObject];
		ORMRelation *other = [relations objectAtIndex:i];
		[phrase numberFormulas:@[ first.formula, other.formula ] columns:first.columns];
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:@"For each "];
		[phrase list:first.columns into:b];
		[b plain:@", "];
		[phrase say:first.formula from:[self headOf:first phrase:phrase] relative:NO into:b];
		[b keyword:@" if and only if "];
		[phrase say:other.formula from:[self headOf:other phrase:phrase] relative:NO into:b];
		[self emit:b modality:constraint.modality];
	}
}

/* "No Person wrote and reviewed the same Book", or "For each Person and
 * Book, at most one of the following holds: ...". */
- (void)verbalizeExclusionByLogic:(ORMConstraint *)constraint
{
	BOOL exclusiveOr = constraint.exclusiveOrPartner != nil;
	NSArray *sequences = constraint.roleSequences;
	/* Each sequence a whole binary read "{0} verb {1}" from the same
	 * first player: the verbs coordinated. */
	NSMutableArray *verbs = [NSMutableArray array];
	ORMRole *firstRole = nil;
	ORMRole *secondRole = nil;
	for (ORMRoleSequence *sequence in sequences) {
		NSArray *roles = sequence.roles;
		ORMRole *a = [roles firstObject];
		ORMRole *c = [roles lastObject];
		if ([roles count] != 2 || a.factType != c.factType || [[a.factType visibleRoles] count] != 2) {
			break;
		}
		ORMReadingOrder *order = [a.factType readingOrderStartingWithRole:a];
		ORMReading *reading = [order.readings firstObject];
		NSString *text = reading.text;
		if (![text hasPrefix:@"{0} "] || ![text hasSuffix:@" {1}"] || [text rangeOfString:@"-"].location != NSNotFound
		    || (firstRole != nil && (a.player != firstRole.player || c.player != secondRole.player))) {
			break;
		}
		firstRole = firstRole ?: a;
		secondRole = secondRole ?: c;
		[verbs addObject:[text substringWithRange:NSMakeRange(4, [text length] - 8)]];
	}
	if (!exclusiveOr && [verbs count] == [sequences count]) {
		ORMSentenceBuilder *(^build)(NSString *) = ^ORMSentenceBuilder *(NSString *quantifier) {
			ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
			[b keyword:[quantifier stringByAppendingString:@" "]];
			[b objectType:firstRole.player.name id:firstRole.player.identifier];
			[b plain:@" "];
			for (NSUInteger i = 0; i < [verbs count]; i++) {
				if (i > 0) {
					[b keyword:i + 1 == [verbs count] ? @" and " : @", "];
				}
				[b predicate:[verbs objectAtIndex:i]];
			}
			[b keyword:@" the same "];
			[b objectType:secondRole.player.name id:secondRole.player.identifier];
			return b;
		};
		ORMVerbalSentence *statement = [self emit:build(@"no") modality:constraint.modality];
		[self negate:statement with:build(@"the same") modality:constraint.modality];
		return;
	}
	ORMSentenceBuilder *(^build)(BOOL) = ^ORMSentenceBuilder *(BOOL negative) {
		ORMPhrase *phrase = [self phrase];
		NSArray *relations = [self relationsOf:constraint phrase:phrase];
		ORMRelation *first = [relations firstObject];
		NSMutableArray *formulas = [NSMutableArray array];
		for (ORMRelation *relation in relations) {
			[formulas addObject:relation.formula];
		}
		[phrase numberFormulas:formulas columns:negative ? @[] : first.columns];
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		if (!negative) {
			[b keyword:@"For each "];
			[phrase list:first.columns into:b];
			[b plain:@", "];
			[b keyword:exclusiveOr ? @"exactly one of the following holds: " : @"at most one of the following holds: "];
		}
		for (NSUInteger i = 0; i < [relations count]; i++) {
			ORMRelation *relation = [relations objectAtIndex:i];
			if (i > 0) {
				[b keyword:negative ? @" and " : @"; "];
			}
			[phrase say:relation.formula from:[self headOf:relation phrase:phrase] relative:NO into:b];
		}
		return b;
	};
	ORMVerbalSentence *statement = [self emit:build(NO) modality:constraint.modality];
	if (!exclusiveOr) {
		[self negate:statement with:build(YES) modality:constraint.modality];
	}
}

#pragma mark Derivation

/* Halpin's marks: * derived, ** derived and stored, + semiderived, ++
 * semiderived and stored. */
static NSString *
ORMDerivationMark(ORMDerivationRule *rule)
{
	if (rule.isPartial) {
		return rule.isStored ? @"++" : @"+";
	}
	return rule.isStored ? @"**" : @"*";
}

/* "* Person1 is grandparent of Person2 if and only if Person1 is parent
 * of some Person3 who is parent of Person2." */
/* A query: what it lists, and the path that gets there. */
- (void)verbalizeQuery:(ORMQuery *)query
{
	ORMRelation *relation = [query relation];
	if (relation == nil) {
		return;
	}
	NSDictionary *variables = [query variablesOfRelation:relation];
	ORMVariable *root = [variables objectForKey:query.root.identifier];
	ORMPhrase *phrase = [self phrase];
	[phrase numberFormulas:@[ relation.formula ] columns:relation.columns];
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	if (query.kind == ORMQueryConstraint) {
		/* Its rows must not be: "It is impossible that some Employee ...",
		 * each node introduced by "some" (docs/RULES.md). */
		[b keyword:query.isDeontic ? @"It is forbidden that " : @"It is impossible that "];
		[phrase say:relation.formula from:root relative:NO into:b];
		/* The modality is in the words already. */
		[self emit:b];
		return;
	}
	if (query.kind == ORMQueryCalculation) {
		/* "The TotalSalary of each Branch is the total of Salary where that
		 * Branch employs some Employee and that Employee earns that Salary." */
		ORMVariable *of = query.calculatedNode != nil ? [variables objectForKey:query.calculatedNode.identifier] : nil;
		[b keyword:@"The "];
		[b plain:query.name ?: @"value"];
		[b keyword:@" of each "];
		[phrase list:@[ root ] into:b];
		if (of == nil) {
			[b keyword:@" is not said yet"];
			[self emit:b];
			return;
		}
		NSArray *words = @[ @"the ", @"the number of ", @"the total of ", @"the average of ", @"the maximum of ",
		                    @"the minimum of " ];
		[b keyword:@" is "];
		[b keyword:[words objectAtIndex:(NSUInteger)query.calculationFunction]];
		[phrase list:@[ of ] into:b];
		[b keyword:@" where "];
		[phrase say:relation.formula from:root relative:NO into:b];
		[self emit:b];
		return;
	}
	[b keyword:@"List each "];
	[phrase list:relation.columns into:b];
	if ([query.root.steps count] > 0 || query.root.comparison != nil) {
		[b keyword:@" where "];
		[phrase say:relation.formula from:root relative:NO into:b];
	}
	/* The order: "in ascending order of EmployeeName, then ...". */
	BOOL first = YES;
	for (ORMQueryNode *node in [query nodes]) {
		if (node.sortOrder == ORMQueryUnsorted) {
			continue;
		}
		[b keyword:first ? @" in " : @", then "];
		[b keyword:node.sortOrder == ORMQueryAscending ? @"ascending order of " : @"descending order of "];
		ORMSpokenTerm *term = [phrase termFor:[variables objectForKey:node.identifier]];
		[b objectType:term.name id:term.elementId];
		first = NO;
	}
	[self emit:b];
}

- (void)verbalizeDerivationOfFactType:(ORMFactType *)fact
{
	ORMDerivationRule *rule = [fact derivationRule];
	if (rule == nil) {
		if (fact.isDerived) {
			ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
			[b keyword:@"This fact type is derived"];
			[self emit:b];
		}
		return;
	}
	NSString *mark = ORMDerivationMark(rule);
	ORMRelation *relation = [rule.paths count] > 0 ? [ORMLogic relationForDerivation:rule of:fact] : nil;
	if (relation != nil && !relation.isIncomplete) {
		ORMPhrase *phrase = [self phrase];
		[phrase numberFormulas:@[ relation.formula ] columns:relation.columns];
		NSArray *roles = [fact visibleRoles];
		BOOL numbered = YES;
		for (ORMVariable *column in relation.columns) {
			numbered = numbered && column.ordinal > 0;
		}
		ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
		[b keyword:[mark stringByAppendingString:@" "]];
		if (!numbered) {
			[b keyword:@"For each "];
			[phrase list:relation.columns into:b];
			[b plain:@", "];
		} else {
			for (ORMVariable *column in relation.columns) {
				[phrase mention:column];
			}
		}
		[b append:[self clause:[self readingOf:fact from:nil] terms:^ORMSpokenTerm *(ORMRole *role) {
			NSUInteger index = [roles indexOfObjectIdenticalTo:role];
			if (index == NSNotFound || index >= [relation.columns count]) {
				return ORMMakeTerm(nil, role.player.name, role.player.identifier);
			}
			return [phrase termFor:[relation.columns objectAtIndex:index]];
		}]];
		[b keyword:rule.isPartial ? @" if " : @" if and only if "];
		[phrase say:relation.formula from:[relation.columns firstObject] relative:NO into:b];
		[self emit:b];
		if ([rule.informalText length] > 0) {
			b = [[ORMSentenceBuilder alloc] init];
			[b keyword:@"Derivation Note: "];
			[b note:rule.informalText];
			[self emit:b kind:ORMVerbalInformation];
		}
		return;
	}
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	[b keyword:[mark stringByAppendingString:@" "]];
	if ([rule.informalText length] > 0) {
		[b note:rule.informalText];
	} else {
		[b keyword:@"This fact type is derived"];
	}
	[self emit:b];
}

/* "Each Male is by definition a Person who is of Gender 'M'." */
- (void)verbalizeDerivationOfSubtype:(ORMObjectType *)type
{
	ORMDerivationRule *rule = [type derivationRule];
	if (rule == nil) {
		return;
	}
	ORMRelation *relation = [rule.paths count] > 0 ? [ORMLogic relationForDerivation:rule of:type] : nil;
	ORMVariable *root = [relation.columns firstObject];
	ORMSentenceBuilder *b = [[ORMSentenceBuilder alloc] init];
	if (root != nil && !relation.isIncomplete) {
		ORMPhrase *phrase = [self phrase];
		[phrase numberFormulas:@[ relation.formula ] columns:@[]];
		[phrase mention:root];
		if (rule.isPartial) {
			/* "Each Person who ... is a Male." */
			[b keyword:@"Each "];
			[b objectType:[phrase nameOf:root] id:root.objectType.identifier];
			[phrase say:relation.formula from:root relative:YES into:b];
			[b keyword:[NSString stringWithFormat:@" is %@ ", ORMArticle(type.name)]];
			[b objectType:type.name id:type.identifier];
		} else {
			[b keyword:@"Each "];
			[b objectType:type.name id:type.identifier];
			[b keyword:[NSString stringWithFormat:@" is by definition %@ ", ORMArticle(root.objectType.name)]];
			[b objectType:[phrase nameOf:root] id:root.objectType.identifier];
			[phrase say:relation.formula from:root relative:YES into:b];
		}
		[self emit:b];
		return;
	}
	[b keyword:@"Each "];
	[b objectType:type.name id:type.identifier];
	[b keyword:@" is by definition "];
	[b note:[rule.informalText length] > 0 ? rule.informalText : @"derived"];
	[self emit:b];
}

@end
