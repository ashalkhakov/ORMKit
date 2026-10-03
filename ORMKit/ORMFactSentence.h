/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* A fact type as NORMA's Fact Editor takes it, typed in a line:
 *
 *   Person(.id) was born in Country(.code)
 *   Person has Name()                          Name is a value type
 *   Mass(kg:) ... / ... Person weighs Mass     a unit-based reference mode
 *   [Order Line] is for Product                a name of several words
 *   Person smokes                              a unary
 *   Person was born in Country / Country is birthplace of Person
 *                                              a second reading, roles by name
 *
 * An object type is a name the model already has, a bracketed name, a name
 * followed by parentheses, or a capitalized word; the rest is the reading.
 * What the model does not have yet is made: an entity type, with the
 * reference mode the parentheses give, or a value type for "()". */

@interface ORMFactSentencePlayer : NSObject
@property (nonatomic, readonly, copy) NSString *name;
/* "id" for (.id), "kg" for (kg:), "Code" for (Code); nil without one. */
@property (nonatomic, readonly, copy) NSString *referenceMode;
@property (nonatomic, readonly) ORMReferenceModeKind referenceModeKind;
/* Name(): a value type. */
@property (nonatomic, readonly) BOOL isValueType;
@end

@interface ORMFactSentence : NSObject
/* nil with why when the line is not a fact type. */
+ (instancetype)sentenceWithString:(NSString *)text model:(ORMModel *)model reason:(NSString **)reason;
/* In the order of the first reading, each object type once. */
@property (nonatomic, readonly, copy) NSArray<ORMFactSentencePlayer *> *players;
/* "{0} was born in {1}", then any others, with the placeholders numbered by
 * the players' order; each with the role order it reads. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *readings;
@property (nonatomic, readonly, copy) NSArray<NSArray<NSNumber *> *> *readingOrders;
@end

