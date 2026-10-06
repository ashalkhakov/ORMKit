/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#if __has_include(<ORMRuntime/ORMRuntime.h>)
#import <ORMRuntime/ORMRuntime.h>
#else
#import "ORMRuntime.h"
#endif
#import "ORMQuery.h"
#import "ORMCoreDataMapper.h"

/* OData requests (ORMRuntime's ORMQueryOData) of what ORMKit has: a plan of
 * the mapped model, or a query, planned first. */
@interface ORMQueryOData (ORMKit)
/* nil, and why, when a name the plan reaches is one ODataKit refuses. */
+ (instancetype)requestForPlan:(ORMQueryPlan *)plan coreData:(ORMCDModel *)coreData error:(NSError **)error;
/* Planned through the mapping (the defaults for nil) first. */
+ (instancetype)requestForQuery:(ORMQuery *)query
                          model:(ORMModel *)model
                        mapping:(ORMCoreDataMapping *)mapping
                          error:(NSError **)error;
@end
