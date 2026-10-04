/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlan.h"

@class NSManagedObjectContext, NSManagedObjectModel;

/* What a plan read: the objects, and for each its row, a value per column
 * (NSNull for none; a set where a column is reached through a to-many). */
@interface ORMQueryResult : NSObject
@property (nonatomic, readonly, copy) NSArray *objects;
@property (nonatomic, readonly, copy) NSArray<NSString *> *columnTitles;
@property (nonatomic, readonly, copy) NSArray<NSArray *> *rows;
@end

/* A query plan (ORMQueryPlan.h) run against a Core Data store: the backend
 * for an application that holds the store itself (one that implements a
 * service with ODataKit, say), where ORMQueryOData is for one that calls
 * the service.
 *
 * A plan may take more than one fetch. Each matches in it (a join on values
 * no relationship makes) is fetched first, and its objects' values put in
 * its place. What the store can evaluate is the fetch request's predicate;
 * what it cannot (an aggregate of the members meeting conditions, which
 * Core Data's SQLite store does not compute) is evaluated on the objects
 * fetched. Values go into predicates as arguments, never as text.
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
 *   ... match [read Branch ...]           Branch fetched first; the parts equal to one
 *                                         of its objects' */
@interface ORMQueryInterpreter : NSObject
- (instancetype)initWithModel:(NSManagedObjectModel *)model;
@property (nonatomic, readonly, strong) NSManagedObjectModel *model;

/* The plan run in the context: nil, and why, when a fetch fails or the plan
 * names what the model does not have. */
- (ORMQueryResult *)executePlan:(ORMQueryPlan *)plan inContext:(NSManagedObjectContext *)context error:(NSError **)error;
/* What running it does, to read: each fetch, and what is kept of what it
 * fetches; nil, and why, for a plan the model cannot run. */
- (NSString *)programForPlan:(ORMQueryPlan *)plan error:(NSError **)error;
@end
