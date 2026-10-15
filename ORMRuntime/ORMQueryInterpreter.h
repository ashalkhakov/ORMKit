/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlan.h"

@class NSManagedObject, NSManagedObjectContext, NSManagedObjectModel;

/* What a plan read, or a page of it: the objects, and the rows they make,
 * a result set: a tuple for each way an object meets the plan's conditions
 * (each member a some binds, each alternative of an or), a value per
 * column, each value of a column a maybe reaches (or NSNull, none), and no
 * tuple twice, across pages too. */
@interface ORMQueryResult : NSObject
@property (nonatomic, readonly, copy) NSArray *objects;
@property (nonatomic, readonly, copy) NSArray<NSString *> *columnTitles;
@property (nonatomic, readonly, copy) NSArray<NSArray *> *rows;
+ (instancetype)resultWithObjects:(NSArray *)objects columnTitles:(NSArray<NSString *> *)titles rows:(NSArray<NSArray *> *)rows;
@end

/* A plan being read, a page at a time: each page fetches what it needs and
 * no more, so a plan whose objects are many, or slow to check, is read as
 * far as the caller asks and no further. Use it on the context's queue. */
@interface ORMQueryCursor : NSObject
/* Up to size more of the plan's objects, in its order: fewer only at the
 * end, none after it; nil, and why, when a fetch fails. */
- (ORMQueryResult *)nextPage:(NSUInteger)size error:(NSError **)error;
@property (nonatomic, readonly) BOOL atEnd;
@end

/* A query plan (ORMQueryPlan.h) run against a Core Data store: the backend
 * for an application that holds the store itself (one that implements a
 * service with ODataKit, say), where ORMQueryOData is for one that calls
 * the service.
 *
 * A plan may take more than one fetch, and is read incrementally:
 * - What the store can evaluate is the fetch's predicate, its values as
 *   arguments, never as text; the fetch is read in slices, in the plan's
 *   order.
 * - The rest (an aggregate of the members meeting conditions, which Core
 *   Data's SQLite store does not compute; a subquery over objects bound
 *   outside the fetch) is evaluated on each slice as it comes.
 * - A join (matches) is said in the predicate when its plan is the store's
 *   to say entirely, reads from nothing of this one, and finds few objects
 *   (joinPrefetchLimit): they are fetched once, and their values put in
 *   its place. Otherwise, where the join's parts are the object read's, the
 *   joined objects with a batch's parts are read once for the batch (what
 *   depends on each object left out), and which of them each object
 *   matches is asked of them with it bound (a correlated join). Else each
 *   object is probed: the joined plan run with its values, until one is
 *   found.
 *
 *   the plan                              Core Data
 *   a path                                a key path; from a variable: $x1.city
 *   some collection as x1 has ...         SUBQUERY(collection, $x1, ...).@count > 0
 *   number of ... having ... op n         SUBQUERY(...).@count op n; collection.@count
 *   sum of x1.salary.usd over employees   employees.@sum.salary.usd
 *   is a Professor                        entity.name IN {Professor, its subentities}
 *   is (the same object)                  ==
 *   is among a trail                      ANY $x2.inverse... == SELF, back along the
 *                                         inverses (what the store says in SQL)
 *   ... match [read Branch ...]           Branch fetched first, or read for each
 *                                         batch, or probed for each object */
@interface ORMQueryInterpreter : NSObject
- (instancetype)initWithModel:(NSManagedObjectModel *)model;
@property (nonatomic, readonly, strong) NSManagedObjectModel *model;
/* The most objects an uncorrelated join is fetched for, to be said in the
 * predicate; more, and it is read for each batch instead. 1000 by default. */
@property (nonatomic) NSUInteger joinPrefetchLimit;

/* The plan read in the context, a page at a time: nil, and why, when the
 * plan names what the model does not have, or a join cannot be fetched. */
- (ORMQueryCursor *)cursorForPlan:(ORMQueryPlan *)plan inContext:(NSManagedObjectContext *)context error:(NSError **)error;
/* Every page of it. */
- (ORMQueryResult *)executePlan:(ORMQueryPlan *)plan inContext:(NSManagedObjectContext *)context error:(NSError **)error;
/* The plan of the objects given, not fetched: each asked as it is in its
 * context, changes not yet saved and all, kept where the plan's condition
 * holds of it, with its rows. What a hook before a save runs
 * (docs/RUNTIME.md). A join it probes is read from the store; nil, and
 * why, for one that aggregates a set it defines. */
- (ORMQueryResult *)executePlan:(ORMQueryPlan *)plan
                      ofObjects:(NSArray<NSManagedObject *> *)objects
                      inContext:(NSManagedObjectContext *)context
                          error:(NSError **)error;
/* What reading it does, to read: each fetch, and what is checked of what
 * it returns; nil, and why, for a plan the model cannot run. */
- (NSString *)programForPlan:(ORMQueryPlan *)plan error:(NSError **)error;
/* The plan's condition as one predicate over the object read, needing no
 * store: what an object can be asked in memory (-evaluateWithObject:), as
 * validation code asks it of itself. TRUEPREDICATE for no condition. nil,
 * and why, where part of it is no predicate: an aggregate of a bag, a join
 * fetched or probed, a subquery the interpreter checks in memory. */
- (NSPredicate *)predicateForPlan:(ORMQueryPlan *)plan reason:(NSString **)reason;
/* The same as predicate format text, its values written in as literals
 * ("nr == 52 AND name == \"Ann\"", nil as nil): what generated code parses
 * with +predicateWithFormat:, on any platform, without printing a predicate
 * (GNUstep prints nil as <null>, which it does not read back). */
- (NSString *)predicateTextForPlan:(ORMQueryPlan *)plan reason:(NSString **)reason;
@end
