/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryOData+ORMKit.h"
#import "ORMQueryPlanner.h"
#import "ORMCDModel+CoreData.h"

@implementation ORMQueryOData (ORMKit)

+ (instancetype)requestForPlan:(ORMQueryPlan *)plan coreData:(ORMCDModel *)coreData error:(NSError **)error
{
	return [self requestForPlan:plan model:[coreData managedObjectModel] error:error];
}

+ (instancetype)requestForQuery:(ORMQuery *)query
                          model:(ORMModel *)model
                        mapping:(ORMCoreDataMapping *)mapping
                          error:(NSError **)error
{
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:mapping];
	return [self requestForPlan:[planner planForQuery:query] coreData:planner.coreData error:error];
}

@end
