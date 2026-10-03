/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* A constraint as the verbalizer says it, typed in a line, turned back
 * into the constraint: what the verbalizer writes, this reads.
 *
 *   Each Person was born in exactly one Country.
 *   For each Country, at most one Person is president of that Country.
 *   Each Person smokes.
 *   In each population of Person speaks Language, each Person, Language
 *     combination occurs at most once.
 *   For each Person and Sport, that Person played that Sport for at most
 *     one Country.
 *   For each Country and RegionISOCode, at most one Region is part of that
 *     Country and has that RegionISOCode.
 *   Each Visitor has some Passport or has some DriverLicence.
 *   Each Person is male or is female but not both.
 *   No Person smokes and drinks.
 *   No Person wrote and reviewed the same Book.
 *   If some Person smokes then that Person is cancer prone.
 *   No Person is parent of itself.
 *   No Person may cycle back to itself via one or more traversals through
 *     Person is parent of Person.
 *   If Person1 is parent of Person2 then Person2 is parent of Person1.
 *   The possible values of Gender are 'M', 'F'.
 *   It is obligatory that each Person was born in some Country.
 *
 * Each clause is matched against the model's readings, an object type's
 * name optionally numbered (Person1) and quantified ("each", "some",
 * "that", "at most one", ...). A clause no reading matches is a fact type
 * the model does not have yet, as in NORMA: the word after a quantifier
 * is an object type, the rest the reading ("each Person was born in
 * exactly one Country" is "{0} was born in {1}"). */

@class ORMSentenceTerm, ORMSentenceFact;

/* A fact type a sentence speaks of that the model does not have. */
@interface ORMSentenceFact : NSObject
/* "{0} was born in {1}". */
@property (nonatomic, readonly, copy) NSString *reading;
/* The object type of each placeholder, by name. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *playerNames;
@end

/* A role a constraint is over: one the model has, or the place of one in
 * a fact type to be made. */
@interface ORMSentenceRole : NSObject
@property (nonatomic, readonly, weak) ORMRole *role;
@property (nonatomic, readonly, strong) ORMSentenceFact *fact;
@property (nonatomic, readonly) NSUInteger index;
@end

/* A sequence over a join path: the fact types its clauses name (each
 * atom's roles and the variable playing each, by name: "Lot",
 * "Country1"), and the variables the sequence's roles are. */
@interface ORMSentencePath : NSObject
@property (nonatomic, readonly, copy) NSArray<NSArray<ORMSentenceRole *> *> *atomRoles;
@property (nonatomic, readonly, copy) NSArray<NSArray<NSString *> *> *atomVariables;
@property (nonatomic, readonly, copy) NSArray<NSString *> *columns;
@end

@interface ORMSentenceConstraint : NSObject
@property (nonatomic, readonly) ORMConstraintKind kind;
/* The role sequences: one for an internal constraint, several for set
 * comparisons and exclusion. */
@property (nonatomic, readonly, copy) NSArray<NSArray<ORMSentenceRole *> *> *sequences;
/* For each sequence, its join path, or NSNull for a sequence within one
 * fact type; nil when no sequence has one. */
@property (nonatomic, readonly, copy) NSArray *paths;
@property (nonatomic, readonly) ORMRingType ringType;
@property (nonatomic, readonly) BOOL isExclusiveOr;
/* A value constraint, when set (its kind then means nothing): "{'M',
 * 'F'}", and what it is on (an object type's name, or a role). */
@property (nonatomic, readonly, copy) NSString *values;
@property (nonatomic, readonly, copy) NSString *valuesOfObjectType;
@property (nonatomic, readonly, strong) ORMSentenceRole *valuesOfRole;
@end

@interface ORMConstraintSentence : NSObject
/* nil with why when the line is no constraint the verbalizer says. */
+ (instancetype)sentenceWithString:(NSString *)text model:(ORMModel *)model reason:(NSString **)reason;
/* What the sentence says, one or more constraints ("exactly one" is a
 * uniqueness and a mandatory constraint). */
@property (nonatomic, readonly, copy) NSArray<ORMSentenceConstraint *> *constraints;
@property (nonatomic, readonly) ORMModality modality;
/* A clause read as more than one fact type does (two fact types read
 * "Person has Name"): the first was taken. */
@property (nonatomic, readonly) BOOL isAmbiguous;
/* Fact types (and their object types) to make first. */
@property (nonatomic, readonly, copy) NSArray<ORMSentenceFact *> *factTypes;
@end

@interface ORMEditor (ORMConstraintSentences)
/* Makes what the sentence says, as one step: the object types and fact
 * types it names that the model lacks (placed on the diagram), then its
 * constraints. A sentence that is no constraint is taken as a fact type,
 * as the Fact Editor takes it. The ids of what was made. */
- (NSArray<NSString *> *)addFromSentence:(NSString *)text
                               onDiagram:(NSString *)diagramId
                                      at:(NSPoint)point
                                  reason:(NSString **)reason;
@end
