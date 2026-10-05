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
		for (ORMQuery *query in [ORMQuery queriesInModel:model]) {
			if (query.kind == ORMQueryConstraint) {
				[rules addObject:query];
			}
		}
		_rules = rules;
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
	return violations;
}

@end
