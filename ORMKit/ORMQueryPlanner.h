/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#if __has_include(<ORMRuntime/ORMRuntime.h>)
#import <ORMRuntime/ORMRuntime.h>
#else
#import "ORMRuntime.h"
#endif
#import "ORMQuery.h"
#import "ORMCoreDataMapper.h"

/* A conceptual query planned through a mapping: its steps as the mapped
 * model's relationships and attributes, by the traces the mapping leaves, so
 * the query keeps its meaning when the mapping changes and only the plan is
 * made again.
 *
 *   ORM                                   the plan
 *   the root object type                  the entity read; a subtype the
 *                                         root's required steps go down to
 *   a step to a value                     compare(value, constant)
 *   a step through a to-one               a path: degree.rating
 *   a step through a to-many, or an       exists(awardeds as x1, ...)
 *     objectified fact type's entity
 *   a unary                               compare(isRetired, true)
 *   a subtype                             isOf, and a cast to read it as one
 *   not, or, maybe                        not, any; maybe: nothing required
 *   count(X) > n                          count(collection as x, ..., > n)
 *   total(X) > n, avg, max, min           aggregate(sum of x.salary.usd ...)
 *   a node met again                      same, in scope; among its trail,
 *                                         out of it
 *   an absorbed object type joined        matches(a plan of the entity that
 *                                         absorbs it too, on the parts)
 *   the ticked object types               columns, from the object read
 *
 * What the mapping cannot say (a step whose fact type maps to nothing, a
 * condition on a composite identifier) is left out and noted in the plan. */
@interface ORMQueryPlanner : NSObject
- (instancetype)initWithCoreData:(ORMCDModel *)coreData;
/* Through the mapping (the defaults for nil). */
- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
@property (nonatomic, readonly, strong) ORMCDModel *coreData;
- (ORMQueryPlan *)planForQuery:(ORMQuery *)query;
@end
