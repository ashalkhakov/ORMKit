/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQuery.h"
#import "ORMCoreDataMapping.h"

@class NSManagedObjectContext, NSManagedObjectModel;

/* A row a constraint query found: what breaks the rule. */
@interface ORMRuleViolation : NSObject
@property (nonatomic, readonly, strong) ORMQuery *rule;
/* The row: a value for each column the rule lists. */
@property (nonatomic, readonly, copy) NSArray *values;
/* "Lives near work: Employee 21." */
@property (nonatomic, readonly, copy) NSString *text;
@end

/* A model's constraint queries (docs/RULES.md) checked against a store of
 * a mapping of it: each planned, its plan run by the interpreter, and each
 * row it finds a violation. A rule the planner cannot say whole (its plan
 * has notes) is not run: it could find what does not break it.
 *
 * A value calculation is checked too: an object it finds more than one
 * value for breaks it ("HeadName: Branch 7 has 2 values."). */
@interface ORMRuleChecker : NSObject
/* The mapping's model, or the defaults for nil. */
- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
@property (nonatomic, readonly, strong) ORMModel *model;
/* The Core Data model the rules are planned against: what a store to check
 * must be of. */
@property (nonatomic, readonly, strong) ORMCDModel *coreData;
/* The model's constraint queries, and its value calculations. */
@property (nonatomic, readonly, copy) NSArray<ORMQuery *> *rules;
@property (nonatomic, readonly, copy) NSArray<ORMQuery *> *valueCalculations;
/* Up to limit violations of each rule in the context, deontic ones too,
 * the rules in the model's order; nil, and why, when a plan cannot run.
 * Runs on the context's queue. */
- (NSArray<ORMRuleViolation *> *)violationsInContext:(NSManagedObjectContext *)context
                                               limit:(NSUInteger)limit
                                               error:(NSError **)error;
/* The rules not run, and why: after -violationsInContext:limit:error:. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *unchecked;
@end
