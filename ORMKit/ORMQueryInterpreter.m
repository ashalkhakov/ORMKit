/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryInterpreter.h"
#import <CoreData/CoreData.h>

@interface ORMQueryResult ()
@property (nonatomic, readwrite, copy) NSArray *objects;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *columnTitles;
@property (nonatomic, readwrite, copy) NSArray<NSArray *> *rows;
@end

@implementation ORMQueryResult
@end

/* A predicate being made: its format, with %@ for each value, the values,
 * and whether the store can evaluate it (else it is evaluated on the
 * objects fetched). */
@interface ORMPredicatePart : NSObject
@property (nonatomic, copy) NSString *format;
@property (nonatomic, copy) NSArray *arguments;
@property (nonatomic) BOOL inStore;
@end

@implementation ORMPredicatePart

+ (instancetype)format:(NSString *)format arguments:(NSArray *)arguments inStore:(BOOL)inStore
{
	ORMPredicatePart *part = [[self alloc] init];
	part.format = format;
	part.arguments = arguments ?: @[];
	part.inStore = inStore;
	return part;
}

@end

static NSError *
ORMInterpreterError(NSString *text)
{
	return [NSError errorWithDomain:ORMQueryPlanErrorDomain code:3 userInfo:@{ NSLocalizedDescriptionKey: text }];
}

static NSDictionary<NSString *, NSString *> *
ORMPredicateOperators(void)
{
	return @{ @"=": @"==", @"<>": @"!=", @"<": @"<", @"<=": @"<=", @">": @">", @">=": @">=" };
}

/* A format with its values written in, to read: strings quoted. */
static NSString *
ORMDisplay(ORMPredicatePart *part)
{
	NSMutableString *text = [NSMutableString string];
	NSArray *pieces = [part.format componentsSeparatedByString:@"%@"];
	for (NSUInteger i = 0; i < [pieces count]; i++) {
		[text appendString:[pieces objectAtIndex:i]];
		if (i < [part.arguments count]) {
			id value = [part.arguments objectAtIndex:i];
			if ([value isKindOfClass:[NSString class]]) {
				[text appendFormat:@"\"%@\"", value];
			} else if ([value isKindOfClass:[NSArray class]]) {
				NSMutableArray *items = [NSMutableArray array];
				for (id item in value) {
					[items addObject:[item isKindOfClass:[NSString class]] ? [NSString stringWithFormat:@"\"%@\"", item]
					                                                       : [item description]];
				}
				[text appendFormat:@"{%@}", [items componentsJoinedByString:@", "]];
			} else if (value == [NSNull null]) {
				[text appendString:@"nil"];
			} else {
				[text appendString:[value description]];
			}
		}
	}
	return text;
}

@implementation ORMQueryInterpreter
{
	/* Where the lowering is: the entity read, and each variable bound. */
	NSEntityDescription *_read;
	NSMutableDictionary<NSString *, NSEntityDescription *> *_bound;
	/* How deep in subqueries: an IN through a to-many there is no SQL. */
	NSUInteger _depth;
	/* The context the plan runs in; nil when it is only described. */
	NSManagedObjectContext *_context;
	NSError *_error;
	/* The joins' programs, as described. */
	NSMutableArray<NSString *> *_joinLines;
	NSUInteger _joins;
}

- (instancetype)initWithModel:(NSManagedObjectModel *)model
{
	if ((self = [super init])) {
		_model = model;
	}
	return self;
}

- (void)fail:(NSString *)text
{
	if (_error == nil) {
		_error = ORMInterpreterError(text);
	}
}

- (NSEntityDescription *)entityNamed:(NSString *)name
{
	NSEntityDescription *entity = name != nil ? [[_model entitiesByName] objectForKey:name] : nil;
	if (entity == nil) {
		[self fail:[NSString stringWithFormat:@"The plan reads %@, which the model has no entity of.", name]];
	}
	return entity;
}

#pragma mark Paths and values

/* The key path, with its variable: "$x1.city.name", "SELF". */
- (NSString *)keyPath:(ORMPlanPath *)path
{
	NSMutableArray *parts = [NSMutableArray array];
	if (path.variable != nil) {
		[parts addObject:[@"$" stringByAppendingString:path.variable]];
	}
	[parts addObjectsFromArray:path.keys];
	return [parts count] > 0 ? [parts componentsJoinedByString:@"."] : @"SELF";
}

/* The entity the path reaches; nil for a value, or a path the model lacks. */
- (NSEntityDescription *)entityAt:(ORMPlanPath *)path
{
	NSEntityDescription *at = path.variable != nil ? [_bound objectForKey:path.variable] : _read;
	for (ORMPlanStep *step in path.steps) {
		if (step.entityName != nil) {
			at = [self entityNamed:step.entityName];
			continue;
		}
		NSPropertyDescription *property = [[at propertiesByName] objectForKey:step.key];
		if (property == nil) {
			[self fail:[NSString stringWithFormat:@"%@ has no property %@.", at.name ?: @"A value", step.key]];
			return nil;
		}
		at = [property isKindOfClass:[NSRelationshipDescription class]] ? ((NSRelationshipDescription *)property).destinationEntity
		                                                                : nil;
	}
	return at;
}

/* A constant as the attribute's type holds it. */
- (id)constant:(ORMPlanValue *)value
{
	NSString *type = value.attributeType;
	NSString *text = value.text ?: @"";
	NSScanner *scanner = [NSScanner scannerWithString:text];
	if ([type hasPrefix:@"Integer"]) {
		long long number = 0;
		if ([scanner scanLongLong:&number] && [scanner isAtEnd]) {
			return @(number);
		}
	} else if ([type isEqualToString:@"Decimal"]) {
		NSDecimal decimal;
		if ([scanner scanDecimal:&decimal] && [scanner isAtEnd]) {
			return [NSDecimalNumber decimalNumberWithDecimal:decimal];
		}
	} else if ([type isEqualToString:@"Double"] || [type isEqualToString:@"Float"]) {
		double number = 0;
		if ([scanner scanDouble:&number] && [scanner isAtEnd]) {
			return @(number);
		}
	} else if ([type isEqualToString:@"Boolean"]) {
		NSString *lower = [text lowercaseString];
		if ([@[ @"true", @"yes", @"1" ] containsObject:lower]) {
			return @YES;
		}
		if ([@[ @"false", @"no", @"0" ] containsObject:lower]) {
			return @NO;
		}
	} else if ([type isEqualToString:@"Date"]) {
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		formatter.dateFormat = @"yyyy-MM-dd";
		NSDate *date = [formatter dateFromString:text];
		if (date != nil) {
			return date;
		}
	}
	return text;
}

#pragma mark Lowering

static ORMPredicatePart *
ORMJoined(NSArray<ORMPredicatePart *> *parts, NSString *connective)
{
	if ([parts count] == 1) {
		return [parts firstObject];
	}
	NSMutableArray *formats = [NSMutableArray array];
	NSMutableArray *arguments = [NSMutableArray array];
	BOOL inStore = YES;
	for (ORMPredicatePart *part in parts) {
		[formats addObject:[NSString stringWithFormat:@"(%@)", part.format]];
		[arguments addObjectsFromArray:part.arguments];
		inStore = inStore && part.inStore;
	}
	return [ORMPredicatePart format:[formats componentsJoinedByString:[NSString stringWithFormat:@" %@ ", connective]]
	                      arguments:arguments inStore:inStore];
}

- (ORMPredicatePart *)lower:(ORMPlanCondition *)condition
{
	switch (condition.kind) {
	case ORMPlanAnd:
	case ORMPlanOr: {
		NSMutableArray *parts = [NSMutableArray array];
		for (ORMPlanCondition *operand in condition.operands) {
			ORMPredicatePart *part = [self lower:operand];
			if (part == nil) {
				return nil;
			}
			[parts addObject:part];
		}
		return ORMJoined(parts, condition.kind == ORMPlanAnd ? @"AND" : @"OR");
	}
	case ORMPlanNot: {
		ORMPredicatePart *operand = [self lower:condition.operand];
		return operand != nil ? [ORMPredicatePart format:[NSString stringWithFormat:@"NOT (%@)", operand.format]
		                                       arguments:operand.arguments inStore:operand.inStore]
		                      : nil;
	}
	case ORMPlanCompare: {
		NSString *op = [ORMPredicateOperators() objectForKey:condition.comparison];
		NSMutableArray *arguments = [NSMutableArray array];
		NSString *(^side)(ORMPlanValue *) = ^NSString *(ORMPlanValue *value) {
			if (value.path != nil) {
				[self entityAt:value.path];
				return [self keyPath:value.path];
			}
			[arguments addObject:[self constant:value]];
			return @"%@";
		};
		NSString *left = side(condition.left);
		NSString *right = side(condition.right);
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ %@ %@", left, op, right] arguments:arguments
		                        inStore:YES];
	}
	case ORMPlanNotNull:
		[self entityAt:condition.path];
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ != nil", [self keyPath:condition.path]] arguments:nil
		                        inStore:YES];
	case ORMPlanExists:
	case ORMPlanCount: {
		NSString *collection = [self keyPath:condition.path];
		NSEntityDescription *member = [self entityAt:condition.path];
		NSString *comparison = condition.kind == ORMPlanExists ? @"> %@" : [NSString stringWithFormat:@"%@ %%@",
		                                                                       [ORMPredicateOperators() objectForKey:condition.comparison]];
		NSNumber *number = condition.kind == ORMPlanExists ? @0 : @(condition.number);
		if (condition.operand == nil) {
			return [ORMPredicatePart format:[NSString stringWithFormat:@"%@.@count %@", collection, comparison]
			                      arguments:@[ number ] inStore:YES];
		}
		ORMPredicatePart *body = [self within:condition.variable over:member lower:condition.operand];
		if (body == nil) {
			return nil;
		}
		return [ORMPredicatePart format:[NSString stringWithFormat:@"SUBQUERY(%@, $%@, %@).@count %@", collection,
		                                                           condition.variable, body.format, comparison]
		                      arguments:[body.arguments arrayByAddingObject:number] inStore:body.inStore];
	}
	case ORMPlanAggregate: {
		NSString *collection = [self keyPath:condition.path];
		NSEntityDescription *member = [self entityAt:condition.path];
		NSString *function = [@{ @"sum": @"@sum", @"average": @"@avg", @"max": @"@max", @"min": @"@min" }
			objectForKey:condition.function];
		NSString *value = [condition.valuePath.keys componentsJoinedByString:@"."];
		NSString *op = [ORMPredicateOperators() objectForKey:condition.comparison];
		id constant = [self constant:condition.constant];
		if (condition.operand == nil) {
			return [ORMPredicatePart format:[NSString stringWithFormat:@"%@.%@.%@ %@ %%@", collection, function, value, op]
			                      arguments:@[ constant ] inStore:YES];
		}
		/* Of the members meeting conditions: Core Data's store aggregates no
		 * subquery, so the objects fetched are asked. */
		ORMPredicatePart *body = [self within:condition.variable over:member lower:condition.operand];
		if (body == nil) {
			return nil;
		}
		return [ORMPredicatePart format:[NSString stringWithFormat:@"SUBQUERY(%@, $%@, %@).%@.%@ %@ %%@", collection,
		                                                           condition.variable, body.format, function, value, op]
		                      arguments:[body.arguments arrayByAddingObject:constant] inStore:NO];
	}
	case ORMPlanIsOf: {
		NSEntityDescription *target = [self entityNamed:condition.entityName];
		NSMutableArray *names = [NSMutableArray array];
		for (NSMutableArray *pending = target != nil ? [NSMutableArray arrayWithObject:target] : [NSMutableArray array];
		     [pending count] > 0;) {
			NSEntityDescription *at = [pending objectAtIndex:0];
			[pending removeObjectAtIndex:0];
			[names addObject:at.name];
			[pending addObjectsFromArray:at.subentities ?: @[]];
		}
		[self entityAt:condition.path];
		NSString *path = [self keyPath:condition.path];
		NSString *entity = [path isEqualToString:@"SELF"] ? @"entity.name" : [path stringByAppendingString:@".entity.name"];
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ IN %%@", entity] arguments:@[ names ] inStore:YES];
	}
	case ORMPlanSame:
		[self entityAt:condition.path];
		[self entityAt:condition.otherPath];
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ == %@", [self keyPath:condition.path],
		                                                           [self keyPath:condition.otherPath]]
		                      arguments:nil inStore:YES];
	case ORMPlanAmong:
		return [self among:condition];
	case ORMPlanMatches:
		return [self matches:condition];
	}
	return nil;
}

/* The condition on the members of a collection, the variable bound. */
- (ORMPredicatePart *)within:(NSString *)variable over:(NSEntityDescription *)member lower:(ORMPlanCondition *)condition
{
	if (member == nil) {
		[self fail:[NSString stringWithFormat:@"%@ ranges over no entity.", variable]];
		return nil;
	}
	[_bound setObject:member forKey:variable];
	_depth++;
	ORMPredicatePart *body = [self lower:condition];
	_depth--;
	[_bound removeObjectForKey:variable];
	return body;
}

/* Among what the trail reaches from the object read: from the object back
 * along the inverses to it, which the SQLite store says in SQL; else IN the
 * trail, which it does not inside a subquery, so evaluated on the objects. */
- (ORMPredicatePart *)among:(ORMPlanCondition *)condition
{
	[self entityAt:condition.path];
	NSString *path = [self keyPath:condition.path];
	NSMutableArray *inverses = [NSMutableArray array];
	NSEntityDescription *at = _read;
	BOOL back = YES;
	for (NSString *key in condition.trail) {
		NSRelationshipDescription *relationship = [[at relationshipsByName] objectForKey:key];
		if (relationship.inverseRelationship == nil) {
			back = NO;
			break;
		}
		[inverses insertObject:relationship.inverseRelationship.name atIndex:0];
		at = relationship.destinationEntity;
	}
	if (back && [inverses count] > 0) {
		return [ORMPredicatePart format:[NSString stringWithFormat:@"ANY %@.%@ == SELF", path,
		                                                           [inverses componentsJoinedByString:@"."]]
		                      arguments:nil inStore:YES];
	}
	NSString *trail = [condition.trail count] > 0 ? [condition.trail componentsJoinedByString:@"."] : @"SELF";
	return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ IN %@", path, trail] arguments:nil inStore:_depth == 0];
}

/* A join: the plan run first, and its objects' values the parts must equal,
 * one object's or another's. Described, its place says so. */
- (ORMPredicatePart *)matches:(ORMPlanCondition *)condition
{
	_joins++;
	NSString *name = [NSString stringWithFormat:@"join%lu", (unsigned long)_joins];
	NSMutableArray *ours = [NSMutableArray array];
	for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
		[self entityAt:[pair firstObject]];
		[ours addObject:[self keyPath:[pair firstObject]]];
	}
	ORMQueryInterpreter *inner = [[ORMQueryInterpreter alloc] initWithModel:_model];
	if (_context == nil) {
		NSError *error = nil;
		NSString *program = [inner programForPlan:condition.plan error:&error];
		if (program == nil) {
			[self fail:[error localizedDescription]];
			return nil;
		}
		[_joinLines addObject:[NSString stringWithFormat:@"%@: %@", name,
		                                                 [program stringByReplacingOccurrencesOfString:@"\n" withString:@"\n  "]]];
		NSMutableArray *parts = [NSMutableArray array];
		for (NSUInteger i = 0; i < [ours count]; i++) {
			[parts addObject:[NSString stringWithFormat:@"%@ == %@.%@", [ours objectAtIndex:i], name,
			                                            [[[condition.pairs objectAtIndex:i] lastObject] description]]];
		}
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ for one of %@", [parts componentsJoinedByString:@" AND "],
		                                                           name]
		                      arguments:nil inStore:YES];
	}
	NSError *error = nil;
	ORMQueryResult *joined = [inner executePlan:condition.plan inContext:_context error:&error];
	if (joined == nil) {
		[self fail:[error localizedDescription]];
		return nil;
	}
	NSMutableArray *alternatives = [NSMutableArray array];
	for (id object in joined.objects) {
		NSMutableArray *parts = [NSMutableArray array];
		NSMutableArray *arguments = [NSMutableArray array];
		for (NSUInteger i = 0; i < [ours count]; i++) {
			NSString *theirs = [[[[condition.pairs objectAtIndex:i] lastObject] keys] componentsJoinedByString:@"."];
			[parts addObject:[NSString stringWithFormat:@"%@ == %%@", [ours objectAtIndex:i]]];
			[arguments addObject:[object valueForKeyPath:theirs] ?: [NSNull null]];
		}
		[alternatives addObject:[ORMPredicatePart format:[parts componentsJoinedByString:@" AND "] arguments:arguments
		                                         inStore:YES]];
	}
	return [alternatives count] > 0 ? ORMJoined(alternatives, @"OR")
	                                : [ORMPredicatePart format:@"FALSEPREDICATE" arguments:nil inStore:YES];
}

/* The condition as what the store evaluates and what is evaluated on the
 * objects it gives: each of its conjuncts one or the other. */
- (NSArray<ORMPredicatePart *> *)split:(ORMPlanCondition *)condition
{
	if (condition == nil) {
		return @[];
	}
	NSArray *conjuncts = condition.kind == ORMPlanAnd ? condition.operands : @[ condition ];
	NSMutableArray *inStore = [NSMutableArray array];
	NSMutableArray *onObjects = [NSMutableArray array];
	for (ORMPlanCondition *conjunct in conjuncts) {
		ORMPredicatePart *part = [self lower:conjunct];
		if (part == nil) {
			return nil;
		}
		[part.inStore ? inStore : onObjects addObject:part];
	}
	return @[ [inStore count] > 0 ? ORMJoined(inStore, @"AND") : [NSNull null],
	          [onObjects count] > 0 ? ORMJoined(onObjects, @"AND") : [NSNull null] ];
}

- (void)begin:(ORMQueryPlan *)plan context:(NSManagedObjectContext *)context
{
	_error = nil;
	_context = context;
	_bound = [NSMutableDictionary dictionary];
	_joinLines = [NSMutableArray array];
	_depth = 0;
	_joins = 0;
	_read = [self entityNamed:plan.entityName];
}

static NSPredicate *
ORMPredicate(id part, NSError **error)
{
	if (part == [NSNull null]) {
		return nil;
	}
	@try {
		return [NSPredicate predicateWithFormat:((ORMPredicatePart *)part).format
		                          argumentArray:((ORMPredicatePart *)part).arguments];
	} @catch (NSException *exception) {
		if (error != NULL) {
			*error = ORMInterpreterError([NSString stringWithFormat:@"The predicate %@ is none: %@",
			                                                        ((ORMPredicatePart *)part).format, exception.reason]);
		}
		return nil;
	}
}

#pragma mark Running

- (ORMQueryResult *)executePlan:(ORMQueryPlan *)plan inContext:(NSManagedObjectContext *)context error:(NSError **)error
{
	[self begin:plan context:context];
	NSArray *split = _read != nil ? [self split:plan.condition] : nil;
	if (_error != nil || split == nil) {
		if (error != NULL) {
			*error = _error ?: ORMInterpreterError(@"The plan could not be run.");
		}
		return nil;
	}
	id inStore = [split count] > 0 ? [split firstObject] : [NSNull null];
	id onObjects = [split count] > 1 ? [split lastObject] : [NSNull null];
	NSPredicate *storePredicate = ORMPredicate(inStore, error);
	NSPredicate *objectPredicate = ORMPredicate(onObjects, error);
	if ((inStore != [NSNull null] && storePredicate == nil) || (onObjects != [NSNull null] && objectPredicate == nil)) {
		return nil;
	}
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:plan.entityName];
	fetch.predicate = storePredicate;
	NSMutableArray *sorts = [NSMutableArray array];
	for (ORMPlanSort *sort in plan.sorts) {
		[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:[sort.path.keys componentsJoinedByString:@"."]
		                                               ascending:sort.ascending]];
	}
	fetch.sortDescriptors = sorts;
	NSArray *objects = [context executeFetchRequest:fetch error:error];
	if (objects == nil) {
		return nil;
	}
	if (objectPredicate != nil) {
		objects = [objects filteredArrayUsingPredicate:objectPredicate];
	}
	NSMutableArray *rows = [NSMutableArray array];
	for (id object in objects) {
		NSMutableArray *row = [NSMutableArray array];
		for (ORMPlanColumn *column in plan.columns) {
			NSArray *keys = [column valuePath].keys;
			id value = [keys count] > 0 ? [object valueForKeyPath:[keys componentsJoinedByString:@"."]] : object;
			[row addObject:value ?: [NSNull null]];
		}
		[rows addObject:row];
	}
	ORMQueryResult *result = [[ORMQueryResult alloc] init];
	result.objects = objects;
	result.columnTitles = [plan.columns valueForKey:@"title"];
	result.rows = rows;
	return result;
}

- (NSString *)programForPlan:(ORMQueryPlan *)plan error:(NSError **)error
{
	[self begin:plan context:nil];
	NSArray *split = _read != nil ? [self split:plan.condition] : nil;
	if (_error != nil || split == nil) {
		if (error != NULL) {
			*error = _error ?: ORMInterpreterError(@"The plan could not be described.");
		}
		return nil;
	}
	NSMutableArray *lines = [NSMutableArray arrayWithArray:_joinLines];
	id inStore = [split count] > 0 ? [split firstObject] : [NSNull null];
	id onObjects = [split count] > 1 ? [split lastObject] : [NSNull null];
	[lines addObject:inStore != [NSNull null] ? [NSString stringWithFormat:@"fetch %@ where %@", plan.entityName,
	                                                                       ORMDisplay(inStore)]
	                                          : [@"fetch every " stringByAppendingString:plan.entityName]];
	if (onObjects != [NSNull null]) {
		[lines addObject:[@"keep those where " stringByAppendingString:ORMDisplay(onObjects)]];
	}
	if ([plan.sorts count] > 0) {
		[lines addObject:[@"sorted by " stringByAppendingString:[[plan.sorts valueForKey:@"description"]
		                                                            componentsJoinedByString:@", "]]];
	}
	return [lines componentsJoinedByString:@"\n"];
}

@end
