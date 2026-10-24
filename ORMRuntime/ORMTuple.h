/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* A row: its values, as the plan's columns list them, and a hash of them
 * made once. An NSArray's hash is its count, so a set of rows of one width
 * keeps them in one bucket and compares each new row with all before it;
 * a tuple's mixes its values' hashes. Rows are made tuples where they are
 * made (a plan run's -rowsOf:, a service's rows), and kept as they are,
 * in sets and maps too; the rows a page gives are their values. */
@interface ORMTuple : NSArray
+ (instancetype)tupleWithValues:(NSArray *)values;
/* Its values, as the plain array an app is given: a tuple equals only
 * another tuple (its hash is not an NSArray's). */
- (NSArray *)values;
@end
