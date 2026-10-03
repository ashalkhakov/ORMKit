/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"

/* An ORM model read out as FORML sentences, as NORMA's verbalization
 * browser reads it: "Each Person was born in exactly one Country."
 *
 * Every element verbalizes: object types (kind, reference scheme, data
 * type, possible values, subtyping, definitions), fact types (their
 * readings and every constraint on their roles, the absent ones too: "It
 * is possible that some Person speaks more than one Language"), and each
 * external constraint. Sentences come as spans styled as NORMA styles
 * them, so a browser can colour them and link names back to elements. */

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

@interface ORMVerbalSentence : NSObject
@property (nonatomic, readonly, copy) NSArray<ORMVerbalSpan *> *spans;
/* The element the sentence verbalizes. */
@property (nonatomic, readonly, copy) NSString *subjectId;
/* Indented under the one before: a fact type's constraints under its
 * reading. */
@property (nonatomic, readonly) NSUInteger level;
- (NSString *)text;
@end

@interface ORMVerbalizer : NSObject
- (instancetype)initWithModel:(ORMModel *)model;
@property (nonatomic, readonly, strong) ORMModel *model;
/* Whether to say what is possible where a constraint is absent, as NORMA
 * does by default. */
@property (nonatomic) BOOL verbalizesPossibilities;

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
