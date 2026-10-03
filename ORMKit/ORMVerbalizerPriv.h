/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMVerbalizer.h"
#import "ORMLogic.h"

/* What the verbalizer's parts share. */

@interface ORMVerbalSpan ()
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite) ORMVerbalStyle style;
@property (nonatomic, readwrite, copy) NSString *elementId;
@end

@interface ORMVerbalSentence ()
@property (nonatomic, readwrite, copy) NSArray<ORMVerbalSpan *> *spans;
@property (nonatomic, readwrite, copy) NSString *subjectId;
@property (nonatomic, readwrite) NSUInteger level;
@property (nonatomic, readwrite) ORMVerbalKind kind;
@property (nonatomic, readwrite, copy) NSString *sourceId;
@property (nonatomic, readwrite, copy) NSArray<ORMVerbalSentence *> *negations;
@end

/* What a placeholder becomes: a quantifier, a name, and a value after it
 * ("Gender 'M'"). A nil name leaves the role out, as "Each Person has
 * some Name or was born in ..." leaves Person out of its second clause. */
@interface ORMSpokenTerm : NSObject
@property (nonatomic, copy) NSString *quantifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *elementId;
@property (nonatomic, copy) NSString *value;
@end

ORMSpokenTerm *ORMMakeTerm(NSString *quantifier, NSString *name, NSString *elementId);
/* "a" or "an", as the name starts. */
NSString *ORMArticle(NSString *name);

/* A reading to verbalize with: its text and the roles its placeholders
 * stand for. Subtype facts have none in the file; they get "{0} is {1}",
 * and a quantifier "some" before the far type reads "a"/"an". */
@interface ORMReadingUse : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<ORMRole *> *roles;
@property (nonatomic) BOOL isSubtype;
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
- (BOOL)isEmpty;
@end

@interface ORMVerbalizer ()
/* The constraint or fact type the sentences being made state. */
@property (nonatomic, copy) NSString *source;

/* Ends the sentence and adds it, capitalized and with its modality said;
 * returned for negations to be attached to. */
- (ORMVerbalSentence *)emit:(ORMSentenceBuilder *)builder;
- (ORMVerbalSentence *)emit:(ORMSentenceBuilder *)builder modality:(ORMModality)modality;
- (ORMVerbalSentence *)emit:(ORMSentenceBuilder *)builder kind:(ORMVerbalKind)kind;
/* Attaches "It is impossible that ..." ("It is forbidden that ..." for a
 * deontic rule) to the statement, and says it too when negations are
 * said. Nothing when the statement is nil. */
- (void)negate:(ORMVerbalSentence *)statement with:(ORMSentenceBuilder *)builder modality:(ORMModality)modality;

- (ORMReadingUse *)use:(NSString *)text roles:(NSArray<ORMRole *> *)roles;
/* A reading of the fact type that starts with the role, if it has one;
 * else its primary reading. */
- (ORMReadingUse *)readingOf:(ORMFactType *)fact from:(ORMRole *)role;
/* Whether a reading of the fact type starts with the role, with no text
 * before it: then a clause about the role's player can leave it out. */
- (BOOL)fact:(ORMFactType *)fact readsFrom:(ORMRole *)role;
/* A reading with each role's term put in. */
- (NSArray<ORMVerbalSpan *> *)clause:(ORMReadingUse *)use terms:(ORMSpokenTerm * (^)(ORMRole *role))term;
@end

/* Logic: constraints over join paths and several fact types, derivation
 * rules (ORMVerbalizer+Logic.m). */
@interface ORMVerbalizer (ORMLogicVerbalizing)
- (void)verbalizeExternalUniquenessByLogic:(ORMConstraint *)constraint;
- (void)verbalizeSubsetByLogic:(ORMConstraint *)constraint;
- (void)verbalizeEqualityByLogic:(ORMConstraint *)constraint;
- (void)verbalizeExclusionByLogic:(ORMConstraint *)constraint;
- (void)verbalizeDerivationOfFactType:(ORMFactType *)fact;
- (void)verbalizeDerivationOfSubtype:(ORMObjectType *)type;
@end
