/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryInterpreter.h"
#import "ORMCursor.h"
#import <CoreData/CoreData.h>

@interface ORMQueryResult ()
@property (nonatomic, readwrite, copy) NSArray *objects;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *columnTitles;
@property (nonatomic, readwrite, copy) NSArray<NSArray *> *rows;
@end

@implementation ORMQueryResult

+ (instancetype)resultWithObjects:(NSArray *)objects columnTitles:(NSArray<NSString *> *)titles rows:(NSArray<NSArray *> *)rows
{
	ORMQueryResult *result = [[self alloc] init];
	result.objects = objects;
	result.columnTitles = titles;
	result.rows = rows;
	return result;
}

@end

static NSError *
ORMInterpreterError(NSString *text)
{
	return [NSError errorWithDomain:ORMQueryPlanErrorDomain code:3 userInfo:@{ NSLocalizedDescriptionKey: text }];
}

static NSDictionary<NSString *, NSNumber *> *
ORMComparisonTypes(void)
{
	return @{ @"=": @(NSEqualToPredicateOperatorType), @"<>": @(NSNotEqualToPredicateOperatorType),
	          @"<": @(NSLessThanPredicateOperatorType), @"<=": @(NSLessThanOrEqualToPredicateOperatorType),
	          @">": @(NSGreaterThanPredicateOperatorType), @">=": @(NSGreaterThanOrEqualToPredicateOperatorType) };
}

static NSDictionary<NSString *, NSString *> *
ORMPredicateOperators(void)
{
	return @{ @"=": @"==", @"<>": @"!=", @"<": @"<", @"<=": @"<=", @">": @">", @">=": @">=" };
}

/* A predicate being made: its format, with %@ for each value, the values,
 * and whether the store can evaluate it (else each object it returns is
 * checked). */
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

static ORMPredicatePart *
ORMJoined(NSArray<ORMPredicatePart *> *parts, NSString *connective)
{
	/* What asks nothing says nothing among others that ask something. */
	if ([connective isEqualToString:@"AND"] && [parts count] > 1) {
		NSMutableArray *asking = [NSMutableArray array];
		for (ORMPredicatePart *part in parts) {
			if (![part.format isEqualToString:@"TRUEPREDICATE"]) {
				[asking addObject:part];
			}
		}
		parts = [asking count] > 0 ? asking : @[ [parts firstObject] ];
	}
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

/* The objects a value holds: a collection's members, or the one object. */
static NSArray *
ORMMembers(id value)
{
	if (value == nil || value == [NSNull null]) {
		return @[];
	}
	if ([value isKindOfClass:[NSSet class]]) {
		return [value allObjects];
	}
	if ([value isKindOfClass:[NSOrderedSet class]]) {
		return [value array];
	}
	if ([value isKindOfClass:[NSArray class]]) {
		return value;
	}
	return @[ value ];
}

static BOOL
ORMCompare(id left, NSString *comparison, id right)
{
	NSNumber *type = [ORMComparisonTypes() objectForKey:comparison ?: @""];
	if (type == nil) {
		return NO;
	}
	NSPredicate *compare = [NSComparisonPredicate
		predicateWithLeftExpression:[NSExpression expressionForConstantValue:left == [NSNull null] ? nil : left]
		            rightExpression:[NSExpression expressionForConstantValue:right == [NSNull null] ? nil : right]
		                   modifier:NSDirectPredicateModifier
		                       type:(NSPredicateOperatorType)[type unsignedIntegerValue]
		                    options:0];
	@try {
		return [compare evaluateWithObject:nil];
	} @catch (NSException *exception) {
		return NO;
	}
}

@class ORMPlanRun;

@interface ORMQueryInterpreter ()
- (ORMPlanRun *)runOf:(ORMQueryPlan *)plan
             bindings:(NSDictionary<NSString *, id> *)bindings
                equal:(NSArray<NSArray *> *)equalities
            inContext:(NSManagedObjectContext *)context
                error:(NSError **)error;
@end

/* A plan being run: its fetch, what is checked of what the fetch returns,
 * and how far it has been read. Bound to the objects a correlated join's
 * plan names of the plan it is in. */
@interface ORMPlanRun : NSObject <ORMBatchEvaluator>
@property (nonatomic, weak) ORMQueryInterpreter *interpreter;
@property (nonatomic, strong) ORMQueryPlan *plan;
@property (nonatomic, strong) NSManagedObjectContext *context;
@property (nonatomic, copy) NSDictionary<NSString *, id> *bindings;
/* @[ their path, a value ]: what a probe asks of the objects read; with
 * an array of values, one of them. */
@property (nonatomic, copy) NSArray<NSArray *> *equalities;
@property (nonatomic, strong) NSEntityDescription *read;
@property (nonatomic, strong) NSPredicate *storePredicate;
@property (nonatomic, strong) ORMPredicatePart *storePart;
@property (nonatomic, copy) NSArray<ORMPlanCondition *> *checks;
@property (nonatomic, strong) ORMPredicatePart *checkPart;
@property (nonatomic, strong) NSMutableArray<NSString *> *joinLines;
@property (nonatomic, strong) NSError *error;
/* The answers of the batch being evaluated (ORMCursor.h). */
@property (nonatomic, copy) NSDictionary<NSString *, id> *answers;
- (BOOL)prepare;
/* The cursors reading it: its fetch, the bags read for each batch, and
 * its checks (docs/CURSORS.md). */
- (id<ORMCursor>)cursor;
/* Up to count more objects, read through its cursor at once; the answers
 * of the last batch read kept. */
- (NSArray *)next:(NSUInteger)count;
@property (nonatomic, readonly) BOOL atEnd;
- (NSString *)programText;
/* The rows of an object the plan reads: a tuple for each way its
 * conditions are met, a value per column. */
- (NSArray<NSArray *> *)rowsOf:(id)object;
@end

/* The plan's fetch, a batch at a time, in its order. */
@interface ORMStoreScan : NSObject <ORMCursor>
@property (nonatomic, weak) ORMPlanRun *run;
@end

@implementation ORMPlanRun
{
	NSMutableSet<NSString *> *_subqueryVariables;
	NSUInteger _depth;
	NSUInteger _joins;
	/* Each bag's tuples by group, by "bag/group column", read whole where
	 * no batch answers them. */
	NSMutableDictionary<NSString *, NSMapTable *> *_bags;
	NSArray<ORMPlanValue *> *_bagValues;
	id<ORMCursor> _cursor;
}

/* The aggregates of bags in the condition, each bag and group once. */
- (void)collectBags:(ORMPlanCondition *)condition into:(NSMutableArray *)bags
{
	if (condition == nil) {
		return;
	}
	for (ORMPlanValue *value in @[ condition.left ?: [NSNull null], condition.right ?: [NSNull null] ]) {
		if (![value isKindOfClass:[ORMPlanValue class]] || value.bag == nil) {
			continue;
		}
		BOOL known = NO;
		for (ORMPlanValue *each in bags) {
			known = known || (each.bag == value.bag && [each.groupColumn isEqualToString:value.groupColumn]);
		}
		if (!known) {
			[bags addObject:value];
		}
	}
	for (ORMPlanCondition *operand in condition.operands) {
		[self collectBags:operand into:bags];
	}
	[self collectBags:condition.operand into:bags];
}

- (ORMPlanColumn *)groupColumnOf:(ORMPlanValue *)value
{
	for (ORMPlanColumn *column in value.bag.plan.columns) {
		if ([column.nodeId isEqualToString:value.groupColumn ?: @""]) {
			return column;
		}
	}
	return nil;
}

/* Whether the bag can be run for a slice's groups: the group is reached
 * from the object read, here and in the bag. */
- (BOOL)scopes:(ORMPlanValue *)value
{
	ORMPlanColumn *group = [self groupColumnOf:value];
	return group != nil && group.path.variable == nil && value.groupPath.variable == nil;
}

static NSString *
ORMBagKey(ORMPlanValue *value)
{
	return [NSString stringWithFormat:@"%@/%@", value.bag.name, value.groupColumn];
}

- (id<ORMCursor>)cursor
{
	if (_cursor != nil || [self describing]) {
		return _cursor;
	}
	ORMStoreScan *scan = [[ORMStoreScan alloc] init];
	scan.run = self;
	id<ORMCursor> cursor = scan;
	__weak ORMPlanRun *weakSelf = self;
	for (ORMPlanValue *value in _bagValues) {
		/* For each batch, its groups' tuples; or all, once. */
		NSArray * (^scope)(ORMBatch *) = nil;
		if ([self scopes:value]) {
			scope = ^NSArray *(ORMBatch *batch) {
				ORMPlanRun *run = weakSelf;
				NSMutableOrderedSet *groups = [NSMutableOrderedSet orderedSet];
				for (id object in batch.objects) {
					id group = [run valueOf:value.groupPath object:object bindings:run.bindings];
					if (group != nil && group != [NSNull null]) {
						[groups addObject:group];
					}
				}
				return [groups array];
			};
		}
		cursor = [[ORMBindJoinCursor alloc] initWithInput:cursor name:ORMBagKey(value) scope:scope
		                                             read:^(NSArray *among, void (^done)(id, NSError *)) {
			                                             ORMPlanRun *run = weakSelf;
			                                             NSMapTable *groups = [run groupsOf:value among:among];
			                                             done(groups, run.error);
		                                             }];
	}
	_cursor = [[ORMFilterCursor alloc] initWithInput:cursor evaluator:self];
	return _cursor;
}

- (BOOL)keeps:(id)object
{
	for (ORMPlanCondition *check in self.checks) {
		if (![self holds:check object:object bindings:self.bindings] || self.error != nil) {
			return NO;
		}
	}
	return YES;
}

- (void)fail:(NSString *)text
{
	if (_error == nil) {
		_error = ORMInterpreterError(text);
	}
}

- (NSEntityDescription *)entityNamed:(NSString *)name
{
	NSEntityDescription *entity = name != nil ? [[self.interpreter.model entitiesByName] objectForKey:name] : nil;
	if (entity == nil) {
		[self fail:[NSString stringWithFormat:@"The plan reads %@, which the model has no entity of.", name]];
	}
	return entity;
}

- (BOOL)describing
{
	return self.context == nil;
}

#pragma mark Values

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

/* The value at the path, from the object read or a variable bound. */
- (id)valueOf:(ORMPlanPath *)path object:(id)object bindings:(NSDictionary *)bindings
{
	id base = path.variable != nil ? [bindings objectForKey:path.variable] : object;
	NSArray *keys = path.keys;
	if (base == nil || [keys count] == 0) {
		return base;
	}
	return [base valueForKeyPath:[keys componentsJoinedByString:@"."]];
}

#pragma mark Saying it to the store

/* The path in a predicate: a key path from the object fetched or a
 * subquery's variable; a variable bound outside the fetch, a value. */
- (NSString *)operand:(ORMPlanPath *)path arguments:(NSMutableArray *)arguments bound:(BOOL *)bound
{
	NSArray *keys = path.keys;
	if (bound != NULL) {
		*bound = NO;
	}
	if (path.variable != nil && [_subqueryVariables containsObject:path.variable]) {
		return [[@[ [@"$" stringByAppendingString:path.variable] ] arrayByAddingObjectsFromArray:keys]
			componentsJoinedByString:@"."];
	}
	if (path.variable != nil) {
		if (bound != NULL) {
			*bound = YES;
		}
		if ([self describing]) {
			return [[@[ path.variable ] arrayByAddingObjectsFromArray:keys] componentsJoinedByString:@"."];
		}
		if ([self.bindings objectForKey:path.variable] == nil) {
			[self fail:[NSString stringWithFormat:@"%@ is bound to nothing.", path.variable]];
			return @"nil";
		}
		[arguments addObject:[self valueOf:path object:nil bindings:self.bindings] ?: [NSNull null]];
		return @"%@";
	}
	return [keys count] > 0 ? [keys componentsJoinedByString:@"."] : @"SELF";
}

- (ORMPredicatePart *)lower:(ORMPlanCondition *)condition
{
	switch (condition.kind) {
	case ORMPlanAnd:
	case ORMPlanOr: {
		NSMutableArray *parts = [NSMutableArray array];
		for (ORMPlanCondition *operand in condition.operands) {
			[parts addObject:[self lower:operand]];
		}
		return ORMJoined(parts, condition.kind == ORMPlanAnd ? @"AND" : @"OR");
	}
	case ORMPlanNot: {
		ORMPredicatePart *operand = [self lower:condition.operand];
		return [ORMPredicatePart format:[NSString stringWithFormat:@"NOT (%@)", operand.format] arguments:operand.arguments
		                        inStore:operand.inStore];
	}
	case ORMPlanCompare: {
		if (condition.left.bag != nil || condition.right.bag != nil) {
			/* An aggregate of a bag: computed on the objects fetched. */
			NSString *text = [[condition description] stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
			return [ORMPredicatePart format:text arguments:nil inStore:NO];
		}
		NSMutableArray *arguments = [NSMutableArray array];
		NSString *(^side)(ORMPlanValue *) = ^NSString *(ORMPlanValue *value) {
			if (value.path != nil) {
				return [self operand:value.path arguments:arguments bound:NULL];
			}
			[arguments addObject:[self constant:value]];
			return @"%@";
		};
		NSString *left = side(condition.left);
		NSString *right = side(condition.right);
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ %@ %@", left,
		                                                           [ORMPredicateOperators() objectForKey:condition.comparison],
		                                                           right]
		                      arguments:arguments inStore:YES];
	}
	case ORMPlanNotNull: {
		NSMutableArray *arguments = [NSMutableArray array];
		NSString *path = [self operand:condition.path arguments:arguments bound:NULL];
		return [ORMPredicatePart format:[path stringByAppendingString:@" != nil"] arguments:arguments inStore:YES];
	}
	case ORMPlanExists:
	case ORMPlanCount:
	case ORMPlanAggregate:
		return [self collection:condition];
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
		NSMutableArray *arguments = [NSMutableArray array];
		BOOL bound = NO;
		NSString *path = [self operand:condition.path arguments:arguments bound:&bound];
		if (bound) {
			/* An object bound outside: asked here and now. */
			if ([self describing]) {
				return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ is a %@", path, condition.entityName]
				                      arguments:nil inStore:NO];
			}
			NSManagedObject *object = [arguments lastObject];
			BOOL is = [object isKindOfClass:[NSManagedObject class]] && [names containsObject:object.entity.name];
			return [ORMPredicatePart format:is ? @"TRUEPREDICATE" : @"FALSEPREDICATE" arguments:nil inStore:YES];
		}
		NSString *entity = [path isEqualToString:@"SELF"] ? @"entity.name" : [path stringByAppendingString:@".entity.name"];
		[arguments addObject:names];
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ IN %%@", entity] arguments:arguments inStore:YES];
	}
	case ORMPlanSame: {
		NSMutableArray *arguments = [NSMutableArray array];
		NSString *left = [self operand:condition.path arguments:arguments bound:NULL];
		NSString *right = [self operand:condition.otherPath arguments:arguments bound:NULL];
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ == %@", left, right] arguments:arguments inStore:YES];
	}
	case ORMPlanAmong:
		return [self among:condition];
	case ORMPlanMatches:
		return [self matches:condition];
	case ORMPlanMaybe:
		/* Asks nothing: what it binds is the rows'. */
		return [ORMPredicatePart format:@"TRUEPREDICATE" arguments:nil inStore:YES];
	}
	return [ORMPredicatePart format:@"FALSEPREDICATE" arguments:nil inStore:YES];
}

/* Some, a count or an aggregate of a collection's members. A collection
 * bound outside the fetch is no subquery the SQLite store reads, and an
 * aggregate of some members none it computes: those are checked on the
 * objects fetched. */
- (ORMPredicatePart *)collection:(ORMPlanCondition *)condition
{
	NSMutableArray *arguments = [NSMutableArray array];
	BOOL bound = NO;
	NSString *collection = [self operand:condition.path arguments:arguments bound:&bound];
	if (bound && ![self describing]) {
		/* A constant collection: its text is only to read. */
		[arguments removeAllObjects];
		collection = [[@[ condition.path.variable ] arrayByAddingObjectsFromArray:condition.path.keys]
			componentsJoinedByString:@"."];
	}
	ORMPredicatePart *body = nil;
	if (condition.operand != nil) {
		[_subqueryVariables addObject:condition.variable];
		_depth++;
		body = [self lower:condition.operand];
		_depth--;
		[_subqueryVariables removeObject:condition.variable];
		[arguments addObjectsFromArray:body.arguments];
	}
	NSString *over = body != nil ? [NSString stringWithFormat:@"SUBQUERY(%@, $%@, %@)", collection, condition.variable,
	                                                          body.format]
	                             : collection;
	BOOL nested = condition.path.variable != nil && [_subqueryVariables containsObject:condition.path.variable];
	if (body == nil && ([condition.path.keys count] > 1 || nested) && condition.kind != ORMPlanAggregate) {
		/* The SQLite store counts no key path through more than one
		 * relationship ("a.b.@count"), nor one from a subquery's variable
		 * ("$x.b.@count"); a subquery over it, it does. */
		over = [NSString stringWithFormat:@"SUBQUERY(%@, $%@, TRUEPREDICATE)", collection,
		                                  condition.variable ?: [NSString stringWithFormat:@"c%lu", (unsigned long)_depth]];
	}
	BOOL inStore = !bound && (body == nil || body.inStore);
	if (condition.kind == ORMPlanAggregate) {
		NSString *function = [@{ @"sum": @"@sum", @"average": @"@avg", @"max": @"@max", @"min": @"@min" }
			objectForKey:condition.function];
		[arguments addObject:[self constant:condition.constant]];
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@.%@.%@ %@ %%@", over, function,
		                                                           [condition.valuePath.keys componentsJoinedByString:@"."],
		                                                           [ORMPredicateOperators() objectForKey:condition.comparison]]
		                      arguments:arguments inStore:inStore && body == nil];
	}
	NSString *comparison = condition.kind == ORMPlanExists ? @">" : [ORMPredicateOperators() objectForKey:condition.comparison];
	[arguments addObject:condition.kind == ORMPlanExists ? @0 : @(condition.number)];
	return [ORMPredicatePart format:[NSString stringWithFormat:@"%@.@count %@ %%@", over, comparison] arguments:arguments
	                        inStore:inStore];
}

/* Among what the trail reaches from the object read, or from an object
 * bound: from the object back along the inverses to it, which the SQLite
 * store says in SQL; else IN the trail, which it does not inside a
 * subquery. */
- (ORMPredicatePart *)among:(ORMPlanCondition *)condition
{
	NSMutableArray *arguments = [NSMutableArray array];
	BOOL bound = NO;
	NSString *path = [self operand:condition.path arguments:arguments bound:&bound];
	NSEntityDescription *at = self.read;
	if (condition.otherPath.variable != nil) {
		at = nil;
	}
	NSMutableArray *inverses = [NSMutableArray array];
	NSString *target = @"SELF";
	if (condition.otherPath != nil) {
		target = [self operand:condition.otherPath arguments:arguments bound:NULL];
	}
	BOOL back = !bound;
	/* The inverses, from where the trail starts: the entity read, or
	 * whatever the bound object's entity is. */
	if (at == nil && ![self describing]) {
		id base = [self.bindings objectForKey:condition.otherPath.variable];
		at = [base isKindOfClass:[NSManagedObject class]] ? ((NSManagedObject *)base).entity : nil;
	}
	NSUInteger toMany = 0;
	for (NSString *key in condition.trail) {
		NSRelationshipDescription *relationship = [[at relationshipsByName] objectForKey:key];
		if (relationship.inverseRelationship == nil) {
			back = NO;
			break;
		}
		[inverses insertObject:relationship.inverseRelationship.name atIndex:0];
		toMany += [relationship.inverseRelationship isToMany] ? 1 : 0;
		at = relationship.destinationEntity;
	}
	/* The SQLite store takes no ANY through more than one to-many
	 * relationship: checked on the objects fetched instead. */
	if (toMany > 1) {
		back = NO;
	}
	if (back && [inverses count] > 0) {
		return [ORMPredicatePart format:[NSString stringWithFormat:@"ANY %@.%@ == %@", path,
		                                                           [inverses componentsJoinedByString:@"."], target]
		                      arguments:arguments inStore:YES];
	}
	NSString *trail = [condition.trail count] > 0 ? [condition.trail componentsJoinedByString:@"."] : @"SELF";
	return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ IN %@", path, trail] arguments:arguments
	                        inStore:!bound && condition.otherPath == nil && _depth == 0];
}

/* A join: said in the predicate where its plan is the store's entirely,
 * reads from nothing of this one, and finds few enough objects; else each
 * object is probed. */
- (ORMPredicatePart *)matches:(ORMPlanCondition *)condition
{
	_joins++;
	NSString *name = condition.definition.name ?: [NSString stringWithFormat:@"join%lu", (unsigned long)_joins];
	NSMutableSet *free = [NSMutableSet setWithSet:[condition.plan.condition freeVariables] ?: [NSSet set]];
	if (condition.variable != nil) {
		[free removeObject:condition.variable];
	}
	BOOL correlated = condition.variable != nil || [free count] > 0;
	NSMutableArray *ours = [NSMutableArray array];
	NSMutableArray *ourArguments = [NSMutableArray array];
	BOOL oursBound = NO;
	for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
		BOOL bound = NO;
		NSMutableArray *arguments = [NSMutableArray array];
		[ours addObject:[self operand:[pair firstObject] arguments:arguments bound:&bound]];
		[ourArguments addObject:arguments];
		oursBound = oursBound || bound;
	}
	ORMPlanRun *joined = nil;
	if (!correlated) {
		joined = [self.interpreter runOf:condition.plan bindings:@{} equal:@[] inContext:self.context error:NULL];
	}
	if ([self describing]) {
		ORMPlanRun *described = joined ?: [self.interpreter runOf:condition.plan
		                                                 bindings:@{} equal:@[] inContext:nil error:NULL];
		NSString *program = [described programText] ?: @"";
		[self.joinLines addObject:[NSString stringWithFormat:@"%@%@: %@", name,
		                                                     correlated ? [NSString stringWithFormat:@", for each (%@ is this)",
		                                                                                             condition.variable ?: @"it"]
		                                                                : @"",
		                                                     [program stringByReplacingOccurrencesOfString:@"\n"
		                                                                                        withString:@"\n  "]]];
		NSMutableArray *parts = [NSMutableArray array];
		for (NSUInteger i = 0; i < [ours count]; i++) {
			[parts addObject:[NSString stringWithFormat:@"%@ == %@.%@", [ours objectAtIndex:i], name,
			                                            [[[condition.pairs objectAtIndex:i] lastObject] description]]];
		}
		return [ORMPredicatePart format:[NSString stringWithFormat:@"%@ for one of %@", [parts componentsJoinedByString:@" AND "],
		                                                           name]
		                      arguments:nil inStore:!correlated && !oursBound && [joined.checks count] == 0];
	}
	/* Fetched once: an uncorrelated plan the store says, of few objects. */
	if (joined != nil && [joined.checks count] == 0 && !oursBound) {
		NSFetchRequest *count = [NSFetchRequest fetchRequestWithEntityName:condition.plan.entityName];
		count.predicate = joined.storePredicate;
		NSError *error = nil;
		NSUInteger found = [self.context countForFetchRequest:count error:&error];
		if (found != NSNotFound && found <= self.interpreter.joinPrefetchLimit) {
			NSArray *objects = [joined next:found + 1];
			if (joined.error != nil) {
				self.error = joined.error;
				return nil;
			}
			NSMutableArray *alternatives = [NSMutableArray array];
			for (id object in objects) {
				NSMutableArray *parts = [NSMutableArray array];
				NSMutableArray *arguments = [NSMutableArray array];
				for (NSUInteger i = 0; i < [ours count]; i++) {
					NSString *theirs = [[[[condition.pairs objectAtIndex:i] lastObject] keys] componentsJoinedByString:@"."];
					[parts addObject:[NSString stringWithFormat:@"%@ == %%@", [ours objectAtIndex:i]]];
					[arguments addObject:[object valueForKeyPath:theirs] ?: [NSNull null]];
				}
				[alternatives addObject:[ORMPredicatePart format:[parts componentsJoinedByString:@" AND "]
				                                       arguments:arguments inStore:YES]];
			}
			return [alternatives count] > 0 ? ORMJoined(alternatives, @"OR")
			                                : [ORMPredicatePart format:@"FALSEPREDICATE" arguments:nil inStore:YES];
		}
	}
	/* Probed, object by object (ORMPlanRun -holds:). */
	return [ORMPredicatePart format:[NSString stringWithFormat:@"probe %@", name] arguments:nil inStore:NO];
}

#pragma mark Checking the objects fetched

/* A value of the object read: a path's, a constant, or an aggregate of a
 * bag over the ways it holds. */
- (id)value:(ORMPlanValue *)value object:(id)object bindings:(NSDictionary *)bindings
{
	if (value.path != nil) {
		return [self valueOf:value.path object:object bindings:bindings];
	}
	if (value.bag == nil) {
		return [self constant:value];
	}
	NSMapTable *groups = [self groupsOf:value];
	if (groups == nil) {
		return nil;
	}
	id group = [self valueOf:value.groupPath object:object bindings:bindings];
	NSUInteger column = [[value.bag.plan.columns valueForKey:@"nodeId"] indexOfObject:value.column ?: @""];
	NSMutableArray *values = [NSMutableArray array];
	for (NSArray *tuple in group != nil ? [groups objectForKey:group] : nil) {
		id each = column != NSNotFound ? [tuple objectAtIndex:column] : nil;
		if (each != nil && each != [NSNull null]) {
			[values addObject:each];
		}
	}
	if ([value.function isEqualToString:@"count"]) {
		return @([values count]);
	}
	if ([values count] == 0) {
		return [value.function isEqualToString:@"sum"] ? @0 : nil;
	}
	NSString *function = [@{ @"sum": @"@sum.self", @"average": @"@avg.self", @"max": @"@max.self",
	                         @"min": @"@min.self" } objectForKey:value.function];
	return [values valueForKeyPath:function];
}

/* The aggregate's bag's tuples by its group: the batch's answer; where
 * none is given, all of them, run once. */
- (NSMapTable *)groupsOf:(ORMPlanValue *)value
{
	NSString *key = ORMBagKey(value);
	NSMapTable *groups = [self.answers objectForKey:key] ?: [_bags objectForKey:key];
	if (groups == nil) {
		groups = [self groupsOf:value among:nil];
		if (groups != nil) {
			if (_bags == nil) {
				_bags = [NSMutableDictionary dictionary];
			}
			[_bags setObject:groups forKey:key];
		}
	}
	return groups;
}

/* The bag run, for the groups among those given (all, for nil): its
 * tuples by group, each once. */
- (NSMapTable *)groupsOf:(ORMPlanValue *)value among:(NSArray *)among
{
	ORMPlanColumn *group = [self groupColumnOf:value];
	NSUInteger column = [value.bag.plan.columns indexOfObject:group];
	if (group == nil || column == NSNotFound) {
		[self fail:[NSString stringWithFormat:@"%@ lists no %@.", value.bag.name, value.groupColumn]];
		return nil;
	}
	NSMapTable *groups = [NSMapTable strongToStrongObjectsMapTable];
	if (among != nil && [among count] == 0) {
		return groups;
	}
	NSError *error = nil;
	ORMPlanRun *run = [self.interpreter runOf:value.bag.plan bindings:@{}
	                                    equal:among != nil ? @[ @[ [group valuePath], among ] ] : @[]
	                                inContext:self.context error:&error];
	NSMutableSet *given = [NSMutableSet set];
	while (run != nil && !run.atEnd) {
		NSArray *objects = [run next:256];
		if (run.error != nil) {
			error = run.error;
			run = nil;
			break;
		}
		for (id object in objects) {
			for (NSArray *tuple in [run rowsOf:object]) {
				if ([given containsObject:tuple]) {
					continue;
				}
				[given addObject:tuple];
				id each = [tuple objectAtIndex:column];
				NSMutableArray *tuples = [groups objectForKey:each];
				if (tuples == nil) {
					tuples = [NSMutableArray array];
					[groups setObject:tuples forKey:each];
				}
				[tuples addObject:tuple];
			}
		}
	}
	if (run == nil) {
		[self fail:[NSString stringWithFormat:@"%@ could not be run: %@", value.bag.name, error.localizedDescription]];
		return nil;
	}
	return groups;
}

/* Whether the condition holds of the object read, the variables bound. */
- (BOOL)holds:(ORMPlanCondition *)condition object:(id)object bindings:(NSDictionary *)bindings
{
	switch (condition.kind) {
	case ORMPlanAnd:
		for (ORMPlanCondition *operand in condition.operands) {
			if (![self holds:operand object:object bindings:bindings]) {
				return NO;
			}
		}
		return YES;
	case ORMPlanOr:
		for (ORMPlanCondition *operand in condition.operands) {
			if ([self holds:operand object:object bindings:bindings]) {
				return YES;
			}
		}
		return NO;
	case ORMPlanNot:
		return ![self holds:condition.operand object:object bindings:bindings];
	case ORMPlanCompare: {
		id left = [self value:condition.left object:object bindings:bindings];
		id right = [self value:condition.right object:object bindings:bindings];
		return ORMCompare(left, condition.comparison, right);
	}
	case ORMPlanNotNull: {
		id value = [self valueOf:condition.path object:object bindings:bindings];
		return value != nil && value != [NSNull null];
	}
	case ORMPlanExists:
	case ORMPlanCount:
	case ORMPlanAggregate: {
		NSMutableArray *members = [NSMutableArray array];
		for (id member in ORMMembers([self valueOf:condition.path object:object bindings:bindings])) {
			NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bindings];
			if (condition.variable != nil) {
				[inner setObject:member forKey:condition.variable];
			}
			if (condition.operand == nil || [self holds:condition.operand object:object bindings:inner]) {
				if (condition.kind == ORMPlanExists) {
					return YES;
				}
				[members addObject:condition.kind == ORMPlanAggregate
				                       ? ([self valueOf:condition.valuePath object:object bindings:inner] ?: [NSNull null])
				                       : member];
			}
		}
		if (condition.kind == ORMPlanExists) {
			return NO;
		}
		if (condition.kind == ORMPlanCount) {
			return ORMCompare(@([members count]), condition.comparison, @(condition.number));
		}
		NSString *function = [@{ @"sum": @"@sum.self", @"average": @"@avg.self", @"max": @"@max.self",
		                         @"min": @"@min.self" } objectForKey:condition.function];
		[members removeObject:[NSNull null]];
		id aggregate = [members count] > 0 || [condition.function isEqualToString:@"sum"]
			? [members valueForKeyPath:function] : nil;
		return ORMCompare(aggregate, condition.comparison, [self constant:condition.constant]);
	}
	case ORMPlanIsOf: {
		id value = [self valueOf:condition.path object:object bindings:bindings];
		NSEntityDescription *entity = [value isKindOfClass:[NSManagedObject class]] ? ((NSManagedObject *)value).entity : nil;
		for (; entity != nil; entity = entity.superentity) {
			if ([entity.name isEqualToString:condition.entityName]) {
				return YES;
			}
		}
		return NO;
	}
	case ORMPlanSame: {
		id left = [self valueOf:condition.path object:object bindings:bindings];
		id right = [self valueOf:condition.otherPath object:object bindings:bindings];
		return left != nil && [left isEqual:right];
	}
	case ORMPlanAmong: {
		id base = condition.otherPath != nil ? [self valueOf:condition.otherPath object:object bindings:bindings] : object;
		NSArray *reached = base != nil ? @[ base ] : @[];
		for (NSString *key in condition.trail) {
			NSMutableArray *next = [NSMutableArray array];
			for (id at in reached) {
				[next addObjectsFromArray:ORMMembers([at valueForKey:key])];
			}
			reached = next;
		}
		id value = [self valueOf:condition.path object:object bindings:bindings];
		return value != nil && [reached containsObject:value];
	}
	case ORMPlanMaybe:
		return YES;
	case ORMPlanMatches: {
		/* A probe: the joined plan, its parts equal to this object's, the
		 * objects it names bound; one object found is enough. */
		NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bindings];
		if (condition.variable != nil && object != nil) {
			[inner setObject:object forKey:condition.variable];
		}
		NSMutableArray *equalities = [NSMutableArray array];
		for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
			[equalities addObject:@[ [pair lastObject],
			                         [self valueOf:[pair firstObject] object:object bindings:bindings] ?: [NSNull null] ]];
		}
		NSError *error = nil;
		ORMPlanRun *probe = [self.interpreter runOf:condition.plan bindings:inner equal:equalities inContext:self.context
		                                      error:&error];
		NSArray *found = probe != nil ? [probe next:1] : nil;
		if (probe == nil || probe.error != nil) {
			self.error = probe.error ?: error;
			return NO;
		}
		return [found count] > 0;
	}
	}
	return NO;
}

#pragma mark Rows

/* The ways the condition holds of the object: the variables it binds (each
 * member that meets a some's conditions, each alternative of an or), added
 * to those bound; none when it does not hold. */
- (NSArray<NSDictionary *> *)bindingsOf:(ORMPlanCondition *)condition object:(id)object bindings:(NSDictionary *)bindings
{
	switch (condition.kind) {
	case ORMPlanAnd: {
		NSArray *ways = @[ bindings ];
		for (ORMPlanCondition *operand in condition.operands) {
			NSMutableArray *next = [NSMutableArray array];
			for (NSDictionary *way in ways) {
				[next addObjectsFromArray:[self bindingsOf:operand object:object bindings:way]];
			}
			if ([next count] == 0) {
				return @[];
			}
			ways = next;
		}
		return ways;
	}
	case ORMPlanOr: {
		NSMutableArray *ways = [NSMutableArray array];
		for (ORMPlanCondition *operand in condition.operands) {
			[ways addObjectsFromArray:[self bindingsOf:operand object:object bindings:bindings]];
		}
		return ways;
	}
	case ORMPlanExists: {
		NSMutableArray *ways = [NSMutableArray array];
		for (id member in ORMMembers([self valueOf:condition.path object:object bindings:bindings])) {
			NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bindings];
			if (condition.variable != nil) {
				[inner setObject:member forKey:condition.variable];
			}
			if (condition.operand == nil) {
				[ways addObject:inner];
			} else {
				[ways addObjectsFromArray:[self bindingsOf:condition.operand object:object bindings:inner]];
			}
		}
		return ways;
	}
	case ORMPlanMaybe: {
		/* Each member meeting the conditions, or one way with none. */
		NSMutableArray *ways = [NSMutableArray array];
		for (id member in ORMMembers([self valueOf:condition.path object:object bindings:bindings])) {
			NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bindings];
			[inner setObject:member forKey:condition.variable];
			if (condition.operand == nil) {
				[ways addObject:inner];
			} else {
				[ways addObjectsFromArray:[self bindingsOf:condition.operand object:object bindings:inner]];
			}
		}
		return [ways count] > 0 ? ways : @[ bindings ];
	}
	default:
		return [self holds:condition object:object bindings:bindings] ? @[ bindings ] : @[];
	}
}

/* The values at the path: from its variable, bound or not (none, if not),
 * or the object read; each member where it goes through a to-many, or
 * none where it reaches nothing. */
- (NSArray *)valuesAt:(ORMPlanPath *)path object:(id)object bindings:(NSDictionary *)bindings
{
	id base = path.variable != nil ? [bindings objectForKey:path.variable] : object;
	if (base == nil) {
		return @[ [NSNull null] ];
	}
	NSArray *values = @[ base ];
	for (NSString *key in path.keys) {
		NSMutableArray *next = [NSMutableArray array];
		for (id value in values) {
			[next addObjectsFromArray:ORMMembers([value valueForKey:key])];
		}
		values = next;
	}
	return [values count] > 0 ? values : @[ [NSNull null] ];
}

- (NSArray<NSArray *> *)rowsOf:(id)object
{
	NSArray *ways = self.plan.condition != nil ? [self bindingsOf:self.plan.condition object:object bindings:self.bindings]
	                                           : @[ self.bindings ];
	if ([ways count] == 0) {
		/* What the store said holds and the objects do not (a nil it
		 * reads otherwise): the object's own row, unbound. */
		ways = @[ self.bindings ];
	}
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *way in ways) {
		NSArray *tuples = @[ @[] ];
		for (ORMPlanColumn *column in self.plan.columns) {
			NSArray *values = [self valuesAt:[column valuePath] object:object bindings:way];
			NSMutableArray *next = [NSMutableArray array];
			for (NSArray *tuple in tuples) {
				for (id value in values) {
					[next addObject:[tuple arrayByAddingObject:value]];
				}
			}
			tuples = next;
		}
		[rows addObjectsFromArray:tuples];
	}
	return rows;
}

#pragma mark Running

- (BOOL)prepare
{
	_subqueryVariables = [NSMutableSet set];
	self.joinLines = [NSMutableArray array];
	self.read = [self entityNamed:self.plan.entityName];
	if (self.read == nil) {
		return NO;
	}
	NSMutableArray *inStore = [NSMutableArray array];
	NSMutableArray *checked = [NSMutableArray array];
	NSMutableArray *checkedParts = [NSMutableArray array];
	ORMPlanCondition *condition = self.plan.condition;
	NSArray *conjuncts = condition == nil ? @[] : (condition.kind == ORMPlanAnd ? condition.operands : @[ condition ]);
	for (ORMPlanCondition *conjunct in conjuncts) {
		ORMPredicatePart *part = [self lower:conjunct];
		if (self.error != nil || part == nil) {
			return NO;
		}
		if (part.inStore) {
			[inStore addObject:part];
		} else {
			[checked addObject:conjunct];
			[checkedParts addObject:part];
		}
	}
	/* What a probe asks of the objects read. */
	for (NSArray *equality in self.equalities) {
		NSString *theirs = [[[equality firstObject] keys] componentsJoinedByString:@"."];
		BOOL among = [[equality lastObject] isKindOfClass:[NSArray class]];
		[inStore addObject:[ORMPredicatePart format:[NSString stringWithFormat:among ? @"%@ IN %%@" : @"%@ == %%@", theirs]
		                                  arguments:@[ [equality lastObject] ] inStore:YES]];
	}
	self.checks = checked;
	/* The bags the checks aggregate, each run for a slice's groups where
	 * the slice's objects say which they are; else once, whole. */
	NSMutableArray *bags = [NSMutableArray array];
	for (ORMPlanCondition *check in checked) {
		[self collectBags:check into:bags];
	}
	_bagValues = bags;
	for (ORMPlanValue *value in bags) {
		ORMPlanColumn *group = [self groupColumnOf:value];
		[self.joinLines addObject:[self scopes:value]
		                              ? [NSString stringWithFormat:@"%@: run for each slice, where %@ is among the slice's %@",
		                                                           value.bag.name, [group valuePath], value.groupPath]
		                              : [NSString stringWithFormat:@"%@: run once, whole", value.bag.name]];
	}
	self.checkPart = [checkedParts count] > 0 ? ORMJoined(checkedParts, @"AND") : nil;
	self.storePart = [inStore count] > 0 ? ORMJoined(inStore, @"AND") : nil;
	if (self.storePart != nil && ![self describing]) {
		@try {
			self.storePredicate = [NSPredicate predicateWithFormat:self.storePart.format argumentArray:self.storePart.arguments];
		} @catch (NSException *exception) {
			[self fail:[NSString stringWithFormat:@"The predicate %@ is none: %@", self.storePart.format, exception.reason]];
			return NO;
		}
	}
	return YES;
}

- (BOOL)atEnd
{
	return self.cursor == nil || self.cursor.atEnd;
}

- (NSArray *)next:(NSUInteger)count
{
	NSMutableArray *found = [NSMutableArray array];
	while ([found count] < count && self.error == nil && ![self atEnd]) {
		NSError *error = nil;
		ORMBatch *batch = ORMNextNow(self.cursor, count - [found count], &error);
		if (batch == nil) {
			[self fail:error.localizedDescription ?: @"A fetch failed."];
			break;
		}
		[found addObjectsFromArray:batch.objects];
		self.answers = batch.answers;
	}
	return found;
}

- (NSString *)programText
{
	NSMutableArray *lines = [NSMutableArray arrayWithArray:self.joinLines];
	[lines addObject:self.storePart != nil ? [NSString stringWithFormat:@"fetch %@ where %@", self.plan.entityName,
	                                                                    ORMDisplay(self.storePart)]
	                                       : [@"fetch every " stringByAppendingString:self.plan.entityName]];
	if (self.checkPart != nil) {
		[lines addObject:[@"keep those where " stringByAppendingString:ORMDisplay(self.checkPart)]];
	}
	if ([self.plan.sorts count] > 0) {
		[lines addObject:[@"sorted by " stringByAppendingString:[[self.plan.sorts valueForKey:@"description"]
		                                                            componentsJoinedByString:@", "]]];
	}
	return [lines componentsJoinedByString:@"\n"];
}

@end

@implementation ORMStoreScan
{
	NSUInteger _offset;
	BOOL _atEnd;
}

- (BOOL)atEnd
{
	return _atEnd;
}

- (void)next:(NSUInteger)count completion:(void (^)(ORMBatch *batch, NSError *error))completion
{
	ORMPlanRun *run = self.run;
	if (_atEnd || count == 0) {
		completion([ORMBatch batchWithObjects:@[] answers:@{}], nil);
		return;
	}
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:run.plan.entityName];
	fetch.predicate = run.storePredicate;
	NSMutableArray *sorts = [NSMutableArray array];
	for (ORMPlanSort *sort in run.plan.sorts) {
		[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:[sort.path.keys componentsJoinedByString:@"."]
		                                               ascending:sort.ascending]];
	}
	fetch.sortDescriptors = sorts;
	fetch.fetchOffset = _offset;
	fetch.fetchLimit = count;
	NSError *error = nil;
	NSArray *objects = [run.context executeFetchRequest:fetch error:&error];
	if (objects == nil) {
		completion(nil, error ?: ORMInterpreterError(@"A fetch failed."));
		return;
	}
	_offset += [objects count];
	_atEnd = [objects count] < count;
	completion([ORMBatch batchWithObjects:objects answers:@{}], nil);
}

@end

#pragma mark The cursor

@interface ORMQueryCursor ()
@property (nonatomic, strong) ORMPlanRun *run;
@property (nonatomic, strong) ORMPageReader *reader;
@end

@implementation ORMQueryCursor

- (BOOL)atEnd
{
	return self.run.atEnd;
}

- (ORMQueryResult *)nextPage:(NSUInteger)size error:(NSError **)error
{
	if (self.reader == nil) {
		self.reader = [[ORMPageReader alloc] initWithInput:[self.run cursor] evaluator:self.run
		                                      columnTitles:[self.run.plan.columns valueForKey:@"title"]];
	}
	__block ORMQueryResult *page = nil;
	__block NSError *failed = nil;
	__block BOOL answered = NO;
	[self.reader nextPage:size completion:^(ORMQueryResult *result, NSError *why) {
		page = result;
		failed = why;
		answered = YES;
	}];
	if (!answered) {
		failed = ORMInterpreterError(@"The store answered later than it was asked.");
	}
	if (page == nil || self.run.error != nil) {
		if (error != NULL) {
			*error = self.run.error ?: failed;
		}
		return nil;
	}
	return page;
}

@end

#pragma mark The interpreter

@implementation ORMQueryInterpreter

- (instancetype)initWithModel:(NSManagedObjectModel *)model
{
	if ((self = [super init])) {
		_model = model;
		_joinPrefetchLimit = 1000;
	}
	return self;
}

- (ORMPlanRun *)runOf:(ORMQueryPlan *)plan
             bindings:(NSDictionary<NSString *, id> *)bindings
                equal:(NSArray<NSArray *> *)equalities
            inContext:(NSManagedObjectContext *)context
                error:(NSError **)error
{
	ORMPlanRun *run = [[ORMPlanRun alloc] init];
	run.interpreter = self;
	run.plan = plan;
	run.context = context;
	run.bindings = bindings ?: @{};
	run.equalities = equalities ?: @[];
	if (![run prepare]) {
		if (error != NULL) {
			*error = run.error ?: ORMInterpreterError(@"The plan could not be run.");
		}
		return nil;
	}
	return run;
}

- (ORMQueryCursor *)cursorForPlan:(ORMQueryPlan *)plan inContext:(NSManagedObjectContext *)context error:(NSError **)error
{
	ORMPlanRun *run = [self runOf:plan bindings:@{} equal:@[] inContext:context error:error];
	if (run == nil) {
		return nil;
	}
	ORMQueryCursor *cursor = [[ORMQueryCursor alloc] init];
	cursor.run = run;
	return cursor;
}

- (ORMQueryResult *)executePlan:(ORMQueryPlan *)plan inContext:(NSManagedObjectContext *)context error:(NSError **)error
{
	ORMQueryCursor *cursor = [self cursorForPlan:plan inContext:context error:error];
	if (cursor == nil) {
		return nil;
	}
	NSMutableArray *objects = [NSMutableArray array];
	NSMutableArray *rows = [NSMutableArray array];
	while (![cursor atEnd]) {
		ORMQueryResult *page = [cursor nextPage:256 error:error];
		if (page == nil) {
			return nil;
		}
		if ([page.objects count] == 0) {
			break;
		}
		[objects addObjectsFromArray:page.objects];
		[rows addObjectsFromArray:page.rows];
	}
	ORMQueryResult *result = [[ORMQueryResult alloc] init];
	result.objects = objects;
	result.columnTitles = [plan.columns valueForKey:@"title"];
	result.rows = rows;
	return result;
}

- (NSString *)programForPlan:(ORMQueryPlan *)plan error:(NSError **)error
{
	ORMPlanRun *run = [self runOf:plan bindings:@{} equal:@[] inContext:nil error:error];
	return run != nil ? [run programText] : nil;
}

@end
