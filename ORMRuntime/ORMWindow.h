/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* The order of two values: a backend's (Core Data's values compare
 * themselves; a service's JSON is compared as it is read). */
typedef NSComparisonResult (*ORMWindowOrder)(id left, id right);

/* One group's tuples for an aggregate over a window (docs/QUERIES.md,
 * decorrelation): sorted by the window's column once, with the aggregate
 * of every run of them from either end, so that "the tuples whose column
 * is below this one's" is a binary search, not a pass over the group for
 * each object asking. */
@interface ORMWindow : NSObject
/* The function ("count", "sum", "average", "max", "min") of the value
 * column, over the tuples by the key column: those without a key left
 * out, as no comparison holds of them. */
+ (instancetype)windowOf:(NSArray<NSArray *> *)tuples
                     key:(NSUInteger)keyColumn
                   value:(NSUInteger)valueColumn
                function:(NSString *)function
                   order:(ORMWindowOrder)order;
/* The aggregate of the tuples whose key compares ("<", "<=", ">", ">=")
 * with the value; a count or a sum of none is 0, the others nil. */
- (id)aggregateWhereKey:(NSString *)comparison than:(id)value;
@end

/* Values in their own order: -compare:, nothing before anything. */
NSComparisonResult ORMWindowCompare(id left, id right);
