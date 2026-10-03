/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* A reading's text taken apart: "{0} includes first- {1}" is the role at
 * place 0, " includes ", then "first " bound to the role at place 1.
 *
 * NORMA's hyphen binding: a word ending in a hyphen before a placeholder
 * ("first- {1}") binds the text from it to the placeholder to the role
 * player that follows, and a word starting with one after a placeholder
 * ("{0} -old") binds back to the one before. A bound text goes with its
 * player wherever a verbalization puts it: "first Name", not "Name". */

@interface ORMReadingPart : NSObject
/* The placeholder's number: the place in the reading order's roles. */
@property (nonatomic, readonly) NSUInteger roleIndex;
@property (nonatomic, readonly, copy) NSString *preBoundText;
@property (nonatomic, readonly, copy) NSString *postBoundText;
/* The text between this placeholder (and its post-bound text) and the
 * next (and its pre-bound text). */
@property (nonatomic, readonly, copy) NSString *followingText;
@end

@interface ORMReadingText : NSObject
/* nil with why when the text is not a reading for so many roles: every
 * placeholder {0}..{arity-1} exactly once. */
+ (instancetype)readingTextWithString:(NSString *)text arity:(NSUInteger)arity reason:(NSString **)reason;

/* The text before the first placeholder (and its pre-bound text). */
@property (nonatomic, readonly, copy) NSString *frontText;
/* In the order the placeholders appear. */
@property (nonatomic, readonly, copy) NSArray<ORMReadingPart *> *parts;

/* The reading with each placeholder's player name put in, through a
 * block that formats the name with its bound texts: the verbalizer marks
 * names up, a plain expansion just joins them. */
- (NSString *)expandWithNames:(NSString * (^)(NSUInteger roleIndex, NSString *preBound, NSString *postBound))name;

/* "Person was born in Country": the placeholders in a sentence the user
 * typed, found by the object type names it contains, each name once, in
 * the order given. nil with why when a name is missing, or there is no
 * text between them to read as a predicate. */
+ (NSString *)readingFromSentence:(NSString *)sentence
                       withNames:(NSArray<NSString *> *)names
                          reason:(NSString **)reason;
@end
