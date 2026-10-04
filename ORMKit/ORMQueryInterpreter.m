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
@interface ORMPlanRun : NSObject
@property (nonatomic, weak) ORMQueryInterpreter *interpreter;
@property (nonatomic, strong) ORMQueryPlan *plan;
@property (nonatomic, strong) NSManagedObjectContext *context;
@property (nonatomic, copy) NSDictionary<NSString *, id> *bindings;
/* @[ their path, a value ]: what a probe asks of the objects read. */
@property (nonatomic, copy) NSArray<NSArray *> *equalities;
@property (nonatomic, strong) NSEntityDescription *read;
@property (nonatomic, strong) NSPredicate *storePredicate;
@property (nonatomic, strong) ORMPredicatePart *storePart;
@property (nonatomic, copy) NSArray<ORMPlanCondition *> *checks;
@property (nonatomic, strong) ORMPredicatePart *checkPart;
@property (nonatomic, strong) NSMutableArray<NSString *> *joinLines;
@property (nonatomic, strong) NSError *error;
- (BOOL)prepare;
- (NSArray *)next:(NSUInteger)count;
@property (nonatomic, readonly) BOOL atEnd;
- (NSString *)programText;
@end

@implementation ORMPlanRun
{
	NSMutableSet<NSString *> *_subqueryVariables;
	NSUInteger _depth;
	NSUInteger _joins;
	NSUInteger _offset;
	NSMutableArray *_buffer;
	BOOL _fetchedAll;
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
	NSString *name = [NSString stringWithFormat:@"join%lu", (unsigned long)_joins];
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
		id left = condition.left.path != nil ? [self valueOf:condition.left.path object:object bindings:bindings]
		                                     : [self constant:condition.left];
		id right = condition.right.path != nil ? [self valueOf:condition.right.path object:object bindings:bindings]
		                                       : [self constant:condition.right];
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

#pragma mark Running

- (BOOL)prepare
{
	_subqueryVariables = [NSMutableSet set];
	_buffer = [NSMutableArray array];
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
		[inStore addObject:[ORMPredicatePart format:[NSString stringWithFormat:@"%@ == %%@", theirs]
		                                  arguments:@[ [equality lastObject] ] inStore:YES]];
	}
	self.checks = checked;
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
	return _fetchedAll && [_buffer count] == 0;
}

/* Up to count more objects the plan reads: fetched a slice at a time, in
 * its order, each checked as it comes. */
- (NSArray *)next:(NSUInteger)count
{
	NSMutableArray *found = [NSMutableArray array];
	NSUInteger slice = MAX(count, (NSUInteger)32);
	while ([found count] < count && self.error == nil) {
		if ([_buffer count] == 0) {
			if (_fetchedAll) {
				break;
			}
			NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:self.plan.entityName];
			fetch.predicate = self.storePredicate;
			NSMutableArray *sorts = [NSMutableArray array];
			for (ORMPlanSort *sort in self.plan.sorts) {
				[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:[sort.path.keys componentsJoinedByString:@"."]
				                                               ascending:sort.ascending]];
			}
			fetch.sortDescriptors = sorts;
			fetch.fetchOffset = _offset;
			fetch.fetchLimit = slice;
			NSError *error = nil;
			NSArray *objects = [self.context executeFetchRequest:fetch error:&error];
			if (objects == nil) {
				self.error = error ?: ORMInterpreterError(@"A fetch failed.");
				break;
			}
			_offset += [objects count];
			_fetchedAll = [objects count] < slice;
			[_buffer addObjectsFromArray:objects];
			continue;
		}
		id object = [_buffer firstObject];
		[_buffer removeObjectAtIndex:0];
		BOOL holds = YES;
		for (ORMPlanCondition *check in self.checks) {
			if (![self holds:check object:object bindings:self.bindings]) {
				holds = NO;
				break;
			}
		}
		if (holds && self.error == nil) {
			[found addObject:object];
		}
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

#pragma mark The cursor

@interface ORMQueryCursor ()
@property (nonatomic, strong) ORMPlanRun *run;
@end

@implementation ORMQueryCursor

- (BOOL)atEnd
{
	return self.run.atEnd;
}

- (ORMQueryResult *)nextPage:(NSUInteger)size error:(NSError **)error
{
	NSArray *objects = [self.run next:size];
	if (self.run.error != nil) {
		if (error != NULL) {
			*error = self.run.error;
		}
		return nil;
	}
	NSMutableArray *rows = [NSMutableArray array];
	for (id object in objects) {
		NSMutableArray *row = [NSMutableArray array];
		for (ORMPlanColumn *column in self.run.plan.columns) {
			NSArray *keys = [column valuePath].keys;
			id value = [keys count] > 0 ? [object valueForKeyPath:[keys componentsJoinedByString:@"."]] : object;
			[row addObject:value ?: [NSNull null]];
		}
		[rows addObject:row];
	}
	ORMQueryResult *result = [[ORMQueryResult alloc] init];
	result.objects = objects;
	result.columnTitles = [self.run.plan.columns valueForKey:@"title"];
	result.rows = rows;
	return result;
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
