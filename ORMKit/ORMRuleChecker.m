/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMRuleChecker.h"
#import "ORMQueryPlanner.h"
#import "ORMQueryInterpreter.h"
#import "ORMCDModel+CoreData.h"
#import <CoreData/CoreData.h>

@interface ORMRuleViolation ()
@property (nonatomic, readwrite, strong) ORMQuery *rule;
@property (nonatomic, readwrite, copy) NSArray *values;
@property (nonatomic, readwrite, copy) NSString *text;
@end

@implementation ORMRuleViolation

- (NSString *)description
{
	return self.text;
}

@end

/* A value of a row as it is said: an identifier, a value, or the object. */
static NSString *
ORMRowValueText(id value)
{
	if (value == nil || value == [NSNull null]) {
		return @"none";
	}
	if ([value isKindOfClass:[NSManagedObject class]]) {
		return [NSString stringWithFormat:@"a %@", [[(NSManagedObject *)value entity] name]];
	}
	return [value description];
}

@implementation ORMRuleChecker
{
	ORMQueryPlanner *_planner;
	NSMutableArray<NSString *> *_unchecked;
}

- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	if ((self = [super init])) {
		_model = model;
		_planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:mapping];
		_coreData = _planner.coreData;
		NSMutableArray *rules = [NSMutableArray array];
		NSMutableArray *values = [NSMutableArray array];
		for (ORMQuery *query in [ORMQuery queriesInModel:model]) {
			if (query.kind == ORMQueryConstraint) {
				[rules addObject:query];
			} else if (query.kind == ORMQueryCalculation && query.calculationFunction == ORMCalculationValue) {
				[values addObject:query];
			}
		}
		_rules = rules;
		_valueCalculations = values;
		_unchecked = [NSMutableArray array];
	}
	return self;
}

- (NSArray<NSString *> *)unchecked
{
	return [_unchecked copy];
}

- (NSArray<ORMRuleViolation *> *)violationsInContext:(NSManagedObjectContext *)context
                                               limit:(NSUInteger)limit
                                               error:(NSError **)error
{
	[_unchecked removeAllObjects];
	NSMutableArray *violations = [NSMutableArray array];
	ORMQueryInterpreter *interpreter =
		[[ORMQueryInterpreter alloc] initWithModel:context.persistentStoreCoordinator.managedObjectModel];
	for (ORMQuery *rule in _rules) {
		ORMQueryPlan *plan = [_planner planForQuery:rule];
		if ([plan.notes count] > 0) {
			[_unchecked addObject:[NSString stringWithFormat:@"%@: %@", rule.name,
			                                                 [plan.notes componentsJoinedByString:@" "]]];
			continue;
		}
		__block ORMQueryResult *page = nil;
		__block NSError *failed = nil;
		[context performBlockAndWait:^{
			ORMQueryCursor *cursor = [interpreter cursorForPlan:plan inContext:context error:&failed];
			page = cursor != nil ? [cursor nextPage:MAX(limit, (NSUInteger)1) error:&failed] : nil;
		}];
		if (page == nil) {
			if (error != NULL) {
				*error = failed;
			}
			return nil;
		}
		/* A row for each: what the rule lists of it; a rule that lists
		 * nothing, its object read. */
		NSArray *rows = [page.columnTitles count] > 0 ? page.rows : nil;
		NSUInteger count = rows != nil ? [rows count] : [page.objects count];
		for (NSUInteger i = 0; i < count && i < limit; i++) {
			ORMRuleViolation *violation = [[ORMRuleViolation alloc] init];
			violation.rule = rule;
			NSMutableArray *parts = [NSMutableArray array];
			if (rows != nil) {
				NSArray *row = [rows objectAtIndex:i];
				violation.values = row;
				for (NSUInteger c = 0; c < [row count] && c < [page.columnTitles count]; c++) {
					[parts addObject:[NSString stringWithFormat:@"%@ %@", [page.columnTitles objectAtIndex:c],
					                                            ORMRowValueText([row objectAtIndex:c])]];
				}
			} else {
				violation.values = @[];
				[parts addObject:ORMRowValueText([page.objects objectAtIndex:i])];
			}
			violation.text = [NSString stringWithFormat:@"%@: %@.", rule.name, [parts componentsJoinedByString:@", "]];
			[violations addObject:violation];
		}
	}
	for (ORMQuery *calculation in _valueCalculations) {
		NSArray *found = [self moreThanOneValueOf:calculation inContext:context interpreter:interpreter limit:limit
		                                    error:error];
		if (found == nil) {
			return nil;
		}
		[violations addObjectsFromArray:found];
	}
	return violations;
}

/* The objects a value calculation finds more than one value for: its plan,
 * its column counting the values instead. */
- (NSArray<ORMRuleViolation *> *)moreThanOneValueOf:(ORMQuery *)calculation
                                          inContext:(NSManagedObjectContext *)context
                                        interpreter:(ORMQueryInterpreter *)interpreter
                                              limit:(NSUInteger)limit
                                              error:(NSError **)error
{
	ORMQueryPlan *plan = [_planner planForQuery:calculation];
	ORMPlanColumn *computed = [plan.columns lastObject];
	if ([plan.notes count] > 0 || computed.value == nil) {
		[_unchecked addObject:[NSString stringWithFormat:@"%@: %@", calculation.name,
		                                                 [plan.notes componentsJoinedByString:@" "] ?: @"?"]];
		return @[];
	}
	ORMPlanValue *value = computed.value;
	ORMPlanValue *count = [ORMPlanValue aggregate:@"distinct" of:value.column in:value.bag where:value.groupColumn
	                                           is:value.groupPath];
	NSMutableArray *columns = [NSMutableArray arrayWithArray:plan.columns];
	[columns replaceObjectAtIndex:[columns count] - 1
	                   withObject:[ORMPlanColumn columnTitled:computed.title node:computed.nodeId value:count]];
	ORMQueryPlan *counting = [ORMQueryPlan planReading:plan.entityName where:plan.condition columns:columns sorts:@[]
	                                             notes:@[] definitions:plan.definitions];
	__block ORMQueryResult *result = nil;
	__block NSError *failed = nil;
	[context performBlockAndWait:^{
		result = [interpreter executePlan:counting inContext:context error:&failed];
	}];
	if (result == nil) {
		if (error != NULL) {
			*error = failed;
		}
		return nil;
	}
	NSMutableArray *found = [NSMutableArray array];
	for (NSArray *row in result.rows) {
		NSNumber *values = [row lastObject];
		if (![values isKindOfClass:[NSNumber class]] || [values unsignedIntegerValue] < 2 || [found count] >= limit) {
			continue;
		}
		ORMRuleViolation *violation = [[ORMRuleViolation alloc] init];
		violation.rule = calculation;
		violation.values = row;
		violation.text = [NSString stringWithFormat:@"%@: %@ %@ has %@ values.", calculation.name,
		                                            [result.columnTitles firstObject], ORMRowValueText([row firstObject]),
		                                            values];
		[found addObject:violation];
	}
	return found;
}

@end
