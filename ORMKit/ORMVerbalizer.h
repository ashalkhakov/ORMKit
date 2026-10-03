/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"

/* An ORM model read out in FORML, worded as Halpin words it: "Each Person
 * was born in exactly one Country."
 *
 * Every element verbalizes: object types (kind, reference scheme, data
 * type, possible values, subtyping and its definition, the fact types it
 * plays, examples), fact types (their readings, derivation rule, examples,
 * and every constraint on their roles, the absent ones too: "It is
 * possible that some Person speaks more than one Language"), and each
 * external constraint, join paths said as relative clauses ("...is of some
 * LotType that tracks lot numbers").
 *
 * Each sentence knows what it states, so it can be put to a domain expert
 * as a question: a constraint's statement carries its negation, the
 * counterexample it rules out ("It is impossible that the same Person was
 * born in more than one Country"), and a possibility names the role a
 * constraint would go on if the expert says it is not possible after all.
 * Sentences come as spans styled as NORMA styles them, so a browser can
 * colour them and link names back to elements. */

typedef NS_ENUM(NSInteger, ORMVerbalStyle) {
	ORMVerbalPlain,
	/* Each, at most one, if ... then: the quantifiers and logical words. */
	ORMVerbalKeyword,
	ORMVerbalObjectType,
	/* The words of a reading. */
	ORMVerbalPredicate,
	/* 'M', 18, true: values. */
	ORMVerbalValue,
	/* Free text a modeller wrote: definitions, notes. */
	ORMVerbalNote,
};

@interface ORMVerbalSpan : NSObject
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) ORMVerbalStyle style;
/* The element a name stands for, for linking; nil for other words. */
@property (nonatomic, readonly, copy) NSString *elementId;
+ (instancetype)spanWithText:(NSString *)text style:(ORMVerbalStyle)style elementId:(NSString *)elementId;
@end

typedef NS_ENUM(NSInteger, ORMVerbalKind) {
	/* What the model says: a reading, a constraint, a rule. */
	ORMVerbalStatement,
	/* What the model allows that a constraint would rule out: "It is
	 * possible that ...". */
	ORMVerbalPossibility,
	/* A statement said the other way: what it rules out. */
	ORMVerbalNegation,
	/* A fact or object of the sample population. */
	ORMVerbalExample,
	/* About an element rather than of the domain: its kind, data type,
	 * reference mode, notes, the fact types it plays. */
	ORMVerbalInformation,
};

@interface ORMVerbalSentence : NSObject
@property (nonatomic, readonly, copy) NSArray<ORMVerbalSpan *> *spans;
/* The element the sentence verbalizes. */
@property (nonatomic, readonly, copy) NSString *subjectId;
/* Indented under the one before: a fact type's constraints under its
 * reading. */
@property (nonatomic, readonly) NSUInteger level;
@property (nonatomic, readonly) ORMVerbalKind kind;
/* What the sentence states: the constraint, the fact type of a reading or
 * derivation rule. For a possibility, the role (or fact type) a
 * uniqueness constraint would go on to rule it out. */
@property (nonatomic, readonly, copy) NSString *sourceId;
/* A statement's negations: what it rules out, one per way it can fail
 * ("exactly one" fails by none and by more than one). */
@property (nonatomic, readonly, copy) NSArray<ORMVerbalSentence *> *negations;
- (NSString *)text;
@end

@interface ORMVerbalizer : NSObject
- (instancetype)initWithModel:(ORMModel *)model;
@property (nonatomic, readonly, strong) ORMModel *model;
/* Whether to say what is possible where a constraint is absent, as NORMA
 * does by default. */
@property (nonatomic) BOOL verbalizesPossibilities;
/* Whether to say each statement's negations after it (NO: they are kept
 * on the statement). */
@property (nonatomic) BOOL verbalizesNegations;
/* Whether to say the sample population (YES). */
@property (nonatomic) BOOL verbalizesExamples;

/* The sentences for an element: an object type, fact type, role (its
 * fact type), reading, constraint or shape (its subject). */
- (NSArray<ORMVerbalSentence *> *)sentencesForElement:(NSString *)elementId;
/* Every object type, fact type and external constraint, in that order. */
- (NSArray<ORMVerbalSentence *> *)sentencesForModel;

/* Sentences as text, a sentence a line, indented by level. */
+ (NSString *)plainTextOfSentences:(NSArray<ORMVerbalSentence *> *)sentences;
/* A standalone HTML page coloured as NORMA's report. */
+ (NSString *)HTMLOfSentences:(NSArray<ORMVerbalSentence *> *)sentences title:(NSString *)title;
@end
