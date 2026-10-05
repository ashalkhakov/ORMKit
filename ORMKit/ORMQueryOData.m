/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryOData.h"
#import "ORMQueryPlanner.h"
#import "ORMCursor.h"
#import "ORMCDModel+CoreData.h"
#import <CoreData/CoreData.h>
#import <ODataKit/ODataApply.h>
#import <ODataKit/ODataExpression.h>
#import <ODataKit/ODataPropertyMapper.h>
#import <ODataIncrementalStore/ODataQueryBuilder.h>
#import <ODataKit/ODataTransport.h>

static NSDictionary<NSString *, NSString *> *
ORMODataOperators(void)
{
	return @{ @"=": @"eq", @"<>": @"ne", @"<": @"lt", @"<=": @"le", @">": @"gt", @">=": @"ge" };
}

static BOOL
ORMIsNumber(NSString *text)
{
	NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
	double number = 0;
	return [scanner scanDouble:&number] && [scanner isAtEnd];
}

static NSError *
ORMODataError(NSString *text)
{
	return [NSError errorWithDomain:ORMQueryPlanErrorDomain code:2 userInfo:@{ NSLocalizedDescriptionKey: text }];
}

@interface ORMQueryODataJoin ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *entityName;
@property (nonatomic, readwrite, copy) NSString *collectionPath;
@property (nonatomic, readwrite, strong) ODataQueryOptions *options;
@property (nonatomic, readwrite, copy) NSArray<NSArray<NSArray<NSString *> *> *> *pairs;
/* Our side of each pair, as the filter says it (from a variable, where the
 * join is inside a lambda). */
@property (nonatomic, copy) NSArray<ODataExpression *> *ours;
@property (nonatomic, strong) ODataPropertyMapper *mapper;
/* A page join's: the joined plan's filter, and our parts' key paths (the
 * model's names), which the request selects. */
@property (nonatomic, strong) ODataExpression *joinedFilter;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *ourKeys;
/* What the joined objects must be of each object of the page that no
 * equality says (o1, the object, bound): checked on the answers; with it,
 * the joined objects are read whole enough for it (rowOptions), not
 * grouped. */
@property (nonatomic, strong) ORMPlanCondition *check;
@property (nonatomic, copy) NSString *outer;
@property (nonatomic, strong) NSEntityDescription *entity;
@property (nonatomic, strong) ODataQueryOptions *rowOptions;
/* The key paths of the object read the check looks at. */
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *outerKeys;
/* A join read whole, narrowed to each page's values: for each value,
 * @[ our path, the key of the entity it reaches or NSNull, their wire
 * path ]. nil where the page does not say them. */
@property (nonatomic, copy) NSArray<NSArray *> *pageScope;
@end

@implementation ORMQueryODataJoin

- (NSURL *)URLWithServiceRoot:(NSURL *)serviceRoot error:(NSError **)error
{
	ODataQueryBuilder *builder = [[ODataQueryBuilder alloc] initWithMapper:self.mapper serviceRoot:serviceRoot];
	return [builder URLForPath:self.collectionPath options:self.options error:error];
}

@end

/* A level of $select and $expand. */
@interface ORMODataLevel : NSObject
@property (nonatomic, strong) NSEntityDescription *entity;
@property (nonatomic, strong) NSMutableArray<NSString *> *select;
@property (nonatomic, strong) NSMutableArray<NSString *> *expandNames;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ORMODataLevel *> *expand;
/* An entity listed with no identifier: all of it. */
@property (nonatomic) BOOL all;
@end

@implementation ORMODataLevel

+ (instancetype)levelOf:(NSEntityDescription *)entity
{
	ORMODataLevel *level = [[self alloc] init];
	level.entity = entity;
	level.select = [NSMutableArray array];
	level.expandNames = [NSMutableArray array];
	level.expand = [NSMutableDictionary dictionary];
	return level;
}

- (ORMODataLevel *)expanding:(NSString *)name entity:(NSEntityDescription *)entity
{
	ORMODataLevel *level = [self.expand objectForKey:name];
	if (level == nil) {
		level = [ORMODataLevel levelOf:entity];
		[self.expand setObject:level forKey:name];
		[self.expandNames addObject:name];
	}
	return level;
}

@end

@interface ORMQueryODataCursor ()
- (instancetype)initWithRequest:(ORMQueryOData *)request transport:(id<ODataTransport>)transport serviceRoot:(NSURL *)root;
/* What the request's filter is narrowed by besides: a page's groups, for
 * a bag. */
@property (nonatomic, strong) ODataExpression *extraFilter;
- (void)scan:(NSUInteger)count
      offset:(NSUInteger)offset
       after:(NSArray *)last
  completion:(void (^)(NSArray *values, NSError *error))completion;
- (void)keep:(NSArray *)rows join:(ORMQueryODataJoin *)join completion:(void (^)(NSArray *kept, NSError *error))completion;
@end

#pragma mark Rows from the service

/* An entity as the service answers it: its JSON, and what it is. */
@interface ORMODataObject : NSObject
@property (nonatomic, strong) NSDictionary *json;
@property (nonatomic, strong) NSEntityDescription *entity;
@end

@implementation ORMODataObject
@end

static ORMODataObject *
ORMODataObjectOf(NSDictionary *json, NSEntityDescription *entity)
{
	ORMODataObject *object = [[ORMODataObject alloc] init];
	object.json = json;
	object.entity = entity;
	return object;
}

/* The plan's rows of an object the service answers, as the interpreter's
 * are a result set: a tuple for each way the object meets the conditions
 * that bind (some, maybe, and the and and or around them), a value per
 * column, evaluated on the JSON. What the plan asks besides, the request's
 * filter has asked; inside a some, everything is asked here, of what the
 * request expands for it (-neededPaths). */
static BOOL ORMJSONCompare(id left, NSString *comparison, id right);

@interface ORMODataRows : NSObject
- (instancetype)initWithPlan:(ORMQueryPlan *)plan read:(NSEntityDescription *)read mapper:(ODataPropertyMapper *)mapper;
/* The key paths from the object read that the rows look at. */
- (NSArray<NSArray<NSString *> *> *)neededPaths;
- (NSArray<NSArray *> *)rowsOf:(NSDictionary *)json;
/* Whether the condition holds of the object, the variables bound. */
- (BOOL)holds:(ORMPlanCondition *)condition object:(ORMODataObject *)read bindings:(NSDictionary *)bindings;
/* The key paths from the object read that the condition looks at, asked
 * whole; those from the variable, when named, instead. */
- (NSArray<NSArray<NSString *> *> *)pathsOf:(ORMPlanCondition *)condition from:(NSString *)variable;
/* The values at the path from an object the service answers. */
- (NSArray *)valuesAt:(ORMPlanPath *)path object:(ORMODataObject *)read bindings:(NSDictionary *)bindings;
/* The answers of the batch evaluated (ORMCursor.h), by name: a bag's rows,
 * a correlated join's objects (ORMODataObjects). */
@property (nonatomic, copy) NSDictionary<NSString *, id> *answers;
@end

@implementation ORMODataRows
{
	ORMQueryPlan *_plan;
	NSEntityDescription *_read;
	ODataPropertyMapper *_mapper;
	/* The variables the columns list from: only what binds them makes rows
	 * differ. */
	NSSet<NSString *> *_listed;
	/* A bag's rows by group, where a group is a value (an identifier), by
	 * the rows answered. */
	NSMapTable<NSArray *, NSDictionary *> *_bagGroups;
}

/* Whether one of the join's objects has the pairs' values and meets its
 * condition, the object read its plan's outer object. */
- (BOOL)matches:(ORMPlanCondition *)condition object:(ORMODataObject *)read bindings:(NSDictionary *)bindings
{
	NSArray *joined = condition.definition.name != nil ? [self.answers objectForKey:condition.definition.name] : nil;
	if (joined == nil) {
		/* The filter's. */
		return YES;
	}
	NSMutableArray *ours = [NSMutableArray array];
	for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
		[ours addObject:[[self valuesAt:[pair firstObject] object:read bindings:bindings] firstObject]];
	}
	NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bindings];
	if (condition.variable != nil) {
		[inner setObject:read forKey:condition.variable];
	}
	for (ORMODataObject *theirs in joined) {
		BOOL equal = YES;
		for (NSUInteger i = 0; i < [condition.pairs count] && equal; i++) {
			id our = [ours objectAtIndex:i];
			id their = [[self valuesAt:[[condition.pairs objectAtIndex:i] lastObject] object:theirs bindings:@{}] firstObject];
			equal = [our isKindOfClass:[ORMODataObject class]] ? [self object:our is:their] : ORMJSONCompare(our, @"=", their);
		}
		if (equal && (condition.plan.condition == nil || [self holds:condition.plan.condition object:theirs bindings:inner])) {
			return YES;
		}
	}
	return NO;
}

/* The aggregate's bag's rows of the group: those whose group column is
 * the value, or the object (by its key). */
- (NSArray<NSArray *> *)rowsOf:(ORMPlanValue *)value group:(id)group
{
	NSArray *rows = [self.answers objectForKey:value.bag.name];
	NSUInteger column = [[value.bag.plan.columns valueForKey:@"nodeId"] indexOfObject:value.groupColumn ?: @""];
	if (rows == nil || column == NSNotFound || group == nil || group == [NSNull null]) {
		return @[];
	}
	if ([group isKindOfClass:[ORMODataObject class]]) {
		NSMutableArray *found = [NSMutableArray array];
		for (NSArray *row in rows) {
			id theirs = [row objectAtIndex:column];
			if ([theirs isKindOfClass:[NSDictionary class]]
			    && [self object:ORMODataObjectOf(theirs, ((ORMODataObject *)group).entity) is:group]) {
				[found addObject:row];
			}
		}
		return found;
	}
	if (_bagGroups == nil) {
		_bagGroups = [NSMapTable weakToStrongObjectsMapTable];
	}
	NSDictionary *groups = [_bagGroups objectForKey:rows];
	if (groups == nil) {
		NSMutableDictionary *made = [NSMutableDictionary dictionary];
		for (NSArray *row in rows) {
			id theirs = [row objectAtIndex:column];
			if (![theirs conformsToProtocol:@protocol(NSCopying)] || theirs == [NSNull null]) {
				continue;
			}
			NSMutableArray *list = [made objectForKey:theirs];
			if (list == nil) {
				list = [NSMutableArray array];
				[made setObject:list forKey:theirs];
			}
			[list addObject:row];
		}
		groups = made;
		[_bagGroups setObject:groups forKey:rows];
	}
	return [groups objectForKey:group] ?: @[];
}

- (instancetype)initWithPlan:(ORMQueryPlan *)plan read:(NSEntityDescription *)read mapper:(ODataPropertyMapper *)mapper
{
	if ((self = [super init])) {
		_plan = plan;
		_read = read;
		_mapper = mapper;
		NSMutableSet *listed = [NSMutableSet set];
		for (ORMPlanColumn *column in plan.columns) {
			if (column.path.variable != nil) {
				[listed addObject:column.path.variable];
			}
		}
		_listed = listed;
	}
	return self;
}

/* Whether the condition binds a variable a column lists from. */
- (BOOL)bindsListed:(ORMPlanCondition *)condition
{
	if (condition == nil) {
		return NO;
	}
	if ((condition.kind == ORMPlanExists || condition.kind == ORMPlanMaybe) && condition.variable != nil
	    && [_listed containsObject:condition.variable]) {
		return YES;
	}
	for (ORMPlanCondition *operand in condition.operands) {
		if ([self bindsListed:operand]) {
			return YES;
		}
	}
	return condition.kind != ORMPlanNot && [self bindsListed:condition.operand];
}

- (NSString *)wireOf:(NSPropertyDescription *)property
{
	return [property isKindOfClass:[NSRelationshipDescription class]]
		? [_mapper propertyForRelationship:(NSRelationshipDescription *)property]
		: [_mapper propertyForAttribute:(NSAttributeDescription *)property];
}

#pragma mark What the rows read

/* The path's keys from the object read; nil for one from what the rows do
 * not bind (an enclosing plan's object). */
static NSArray *
ORMKeysFromRead(ORMPlanPath *path, NSDictionary<NSString *, NSArray *> *bound)
{
	NSArray *base = path.variable != nil ? [bound objectForKey:path.variable] : @[];
	return base != nil ? [base arrayByAddingObjectsFromArray:path.keys] : nil;
}

- (void)collect:(ORMPlanCondition *)condition bound:(NSDictionary *)bound into:(NSMutableArray *)paths top:(BOOL)top
{
	if (condition == nil) {
		return;
	}
	if (top && (condition.kind == ORMPlanAnd || condition.kind == ORMPlanOr)) {
		for (ORMPlanCondition *operand in condition.operands) {
			[self collect:operand bound:bound into:paths top:YES];
		}
		return;
	}
	BOOL binds = (condition.kind == ORMPlanExists || condition.kind == ORMPlanMaybe) && [self bindsListed:condition];
	if (top && !binds) {
		/* The filter's. */
		return;
	}
	void (^add)(ORMPlanPath *, NSDictionary *) = ^(ORMPlanPath *path, NSDictionary *in) {
		NSArray *keys = path != nil ? ORMKeysFromRead(path, in) : nil;
		if (keys != nil) {
			[paths addObject:keys];
		}
	};
	add(condition.path, bound);
	add(condition.otherPath, bound);
	add(condition.left.path, bound);
	add(condition.right.path, bound);
	add(condition.left.groupPath, bound);
	add(condition.right.groupPath, bound);
	if (condition.kind == ORMPlanMatches) {
		/* Our side of the pairs, and what the joined plan reads of the
		 * object read, its outer object. */
		for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
			add([pair firstObject], bound);
		}
		if (condition.variable != nil) {
			[paths addObjectsFromArray:[self pathsOf:condition.plan.condition from:condition.variable]];
		}
	}
	if (condition.kind == ORMPlanAmong) {
		NSArray *base = condition.otherPath != nil ? ORMKeysFromRead(condition.otherPath, bound) : @[];
		if (base != nil) {
			[paths addObject:[base arrayByAddingObjectsFromArray:condition.trail ?: @[]]];
		}
	}
	for (ORMPlanCondition *operand in condition.operands) {
		[self collect:operand bound:bound into:paths top:NO];
	}
	NSDictionary *inner = bound;
	if (condition.variable != nil && condition.kind != ORMPlanMatches) {
		NSArray *collection = ORMKeysFromRead(condition.path, bound);
		if (collection != nil) {
			NSMutableDictionary *more = [NSMutableDictionary dictionaryWithDictionary:bound];
			[more setObject:collection forKey:condition.variable];
			inner = more;
		}
	}
	add(condition.valuePath, inner);
	if (condition.kind != ORMPlanMatches && condition.operand != nil) {
		[self collect:condition.operand bound:inner into:paths top:NO];
	}
}

- (NSArray<NSArray<NSString *> *> *)pathsOf:(ORMPlanCondition *)condition from:(NSString *)variable
{
	NSMutableArray *paths = [NSMutableArray array];
	if (variable == nil) {
		[self collect:condition bound:@{} into:paths top:NO];
		return paths;
	}
	/* Each path from the variable, wherever it is. */
	NSMutableArray *pending = condition != nil ? [NSMutableArray arrayWithObject:condition] : [NSMutableArray array];
	while ([pending count] > 0) {
		ORMPlanCondition *at = [pending lastObject];
		[pending removeLastObject];
		for (ORMPlanPath *path in @[ at.path ?: [NSNull null], at.otherPath ?: [NSNull null], at.left.path ?: [NSNull null],
		                             at.right.path ?: [NSNull null], at.valuePath ?: [NSNull null],
		                             at.left.groupPath ?: [NSNull null], at.right.groupPath ?: [NSNull null] ]) {
			if ([path isKindOfClass:[ORMPlanPath class]] && [path.variable isEqualToString:variable]) {
				[paths addObject:path.keys];
			}
		}
		[pending addObjectsFromArray:at.operands ?: @[]];
		if (at.operand != nil) {
			[pending addObject:at.operand];
		}
	}
	return paths;
}

- (NSArray<NSArray<NSString *> *> *)neededPaths
{
	NSMutableArray *paths = [NSMutableArray array];
	[self collect:_plan.condition bound:@{} into:paths top:YES];
	return paths;
}

#pragma mark Evaluating

/* The values at the path: each member through a to-many; objects wrapped,
 * values as the JSON has them; NSNull where it reaches nothing. */
- (NSArray *)valuesAt:(ORMPlanPath *)path object:(ORMODataObject *)read bindings:(NSDictionary *)bindings
{
	id base = path.variable != nil ? [bindings objectForKey:path.variable] : read;
	if (base == nil) {
		return @[ [NSNull null] ];
	}
	NSArray *values = @[ base ];
	for (ORMPlanStep *step in path.steps) {
		NSMutableArray *next = [NSMutableArray array];
		for (id value in values) {
			if (![value isKindOfClass:[ORMODataObject class]]) {
				continue;
			}
			ORMODataObject *object = value;
			if (step.entityName != nil) {
				NSEntityDescription *cast = [[object.entity.managedObjectModel entitiesByName] objectForKey:step.entityName];
				[next addObject:ORMODataObjectOf(object.json, cast ?: object.entity)];
				continue;
			}
			NSPropertyDescription *property = [[object.entity propertiesByName] objectForKey:step.key];
			if (property == nil) {
				continue;
			}
			id json = [object.json objectForKey:[self wireOf:property]];
			if ([property isKindOfClass:[NSRelationshipDescription class]]) {
				NSEntityDescription *destination = ((NSRelationshipDescription *)property).destinationEntity;
				for (id member in [json isKindOfClass:[NSArray class]] ? json : (json != nil ? @[ json ] : @[])) {
					if ([member isKindOfClass:[NSDictionary class]]) {
						[next addObject:ORMODataObjectOf(member, destination)];
					}
				}
			} else {
				[next addObject:json ?: [NSNull null]];
			}
		}
		values = next;
	}
	return [values count] > 0 ? values : @[ [NSNull null] ];
}

- (NSArray *)membersAt:(ORMPlanPath *)path object:(ORMODataObject *)read bindings:(NSDictionary *)bindings
{
	NSMutableArray *members = [NSMutableArray array];
	for (id value in [self valuesAt:path object:read bindings:bindings]) {
		if (value != [NSNull null]) {
			[members addObject:value];
		}
	}
	return members;
}

/* A constant as JSON has its type: a number, a truth, or text. */
static id
ORMJSONConstant(ORMPlanValue *value)
{
	NSString *type = value.attributeType;
	NSString *text = value.text ?: @"";
	if ([type hasPrefix:@"Integer"] || [@[ @"Decimal", @"Double", @"Float" ] containsObject:type]) {
		NSScanner *scanner = [NSScanner scannerWithString:text];
		double number = 0;
		if ([scanner scanDouble:&number] && [scanner isAtEnd]) {
			return @(number);
		}
	}
	if ([type isEqualToString:@"Boolean"]) {
		return @([@[ @"true", @"yes", @"1" ] containsObject:[text lowercaseString]]);
	}
	return text;
}

static BOOL
ORMJSONCompare(id left, NSString *comparison, id right)
{
	if (left == nil || right == nil || left == [NSNull null] || right == [NSNull null]) {
		return [comparison isEqualToString:@"<>"] ? left != right : NO;
	}
	NSComparisonResult order;
	if ([left isKindOfClass:[NSNumber class]] && [right isKindOfClass:[NSNumber class]]) {
		order = [(NSNumber *)left compare:right];
	} else {
		order = [[left description] compare:[right description]];
	}
	if ([comparison isEqualToString:@"="]) {
		return order == NSOrderedSame;
	}
	if ([comparison isEqualToString:@"<>"]) {
		return order != NSOrderedSame;
	}
	if ([comparison isEqualToString:@"<"]) {
		return order == NSOrderedAscending;
	}
	if ([comparison isEqualToString:@"<="]) {
		return order != NSOrderedDescending;
	}
	if ([comparison isEqualToString:@">"]) {
		return order == NSOrderedDescending;
	}
	return [comparison isEqualToString:@">="] && order != NSOrderedAscending;
}

/* Two objects one: their keys equal. */
- (BOOL)object:(id)left is:(id)right
{
	if (![left isKindOfClass:[ORMODataObject class]] || ![right isKindOfClass:[ORMODataObject class]]) {
		return NO;
	}
	NSArray *key = [_mapper keyAttributesForEntity:((ORMODataObject *)left).entity];
	if ([key count] == 0) {
		return NO;
	}
	for (NSAttributeDescription *attribute in key) {
		NSString *wire = [_mapper propertyForAttribute:attribute];
		id ours = [((ORMODataObject *)left).json objectForKey:wire];
		id theirs = [((ORMODataObject *)right).json objectForKey:wire];
		if (ours == nil || ![ours isEqual:theirs]) {
			return NO;
		}
	}
	return YES;
}

- (id)firstAt:(ORMPlanValue *)value object:(ORMODataObject *)read bindings:(NSDictionary *)bindings
{
	if (value.bag != nil) {
		/* An aggregate of the bag's rows of the group. */
		id group = [[self valuesAt:value.groupPath object:read bindings:bindings] firstObject];
		NSUInteger column = [[value.bag.plan.columns valueForKey:@"nodeId"] indexOfObject:value.column ?: @""];
		NSMutableArray *values = [NSMutableArray array];
		NSUInteger set = 0;
		for (NSArray *row in [self rowsOf:value group:group]) {
			id each = column != NSNotFound ? [row objectAtIndex:column] : [NSNull null];
			set += each != [NSNull null];
			if ([each isKindOfClass:[NSNumber class]]) {
				[values addObject:each];
			}
		}
		if ([value.function isEqualToString:@"count"]) {
			return @(set);
		}
		if ([values count] == 0) {
			return [value.function isEqualToString:@"sum"] ? @0 : nil;
		}
		NSString *function = [@{ @"sum": @"@sum.self", @"average": @"@avg.self", @"max": @"@max.self",
		                         @"min": @"@min.self" } objectForKey:value.function];
		return [values valueForKeyPath:function];
	}
	return value.path != nil ? [[self valuesAt:value.path object:read bindings:bindings] firstObject] : ORMJSONConstant(value);
}

- (BOOL)holds:(ORMPlanCondition *)condition object:(ORMODataObject *)read bindings:(NSDictionary *)bindings
{
	switch (condition.kind) {
	case ORMPlanAnd:
		for (ORMPlanCondition *operand in condition.operands) {
			if (![self holds:operand object:read bindings:bindings]) {
				return NO;
			}
		}
		return YES;
	case ORMPlanOr:
		for (ORMPlanCondition *operand in condition.operands) {
			if ([self holds:operand object:read bindings:bindings]) {
				return YES;
			}
		}
		return NO;
	case ORMPlanNot:
		return ![self holds:condition.operand object:read bindings:bindings];
	case ORMPlanCompare:
		return ORMJSONCompare([self firstAt:condition.left object:read bindings:bindings], condition.comparison,
		                      [self firstAt:condition.right object:read bindings:bindings]);
	case ORMPlanNotNull:
		return [[self membersAt:condition.path object:read bindings:bindings] count] > 0;
	case ORMPlanExists:
	case ORMPlanCount:
	case ORMPlanAggregate: {
		NSMutableArray *kept = [NSMutableArray array];
		for (id member in [self membersAt:condition.path object:read bindings:bindings]) {
			NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bindings];
			if (condition.variable != nil) {
				[inner setObject:member forKey:condition.variable];
			}
			if (condition.operand == nil || [self holds:condition.operand object:read bindings:inner]) {
				if (condition.kind == ORMPlanExists) {
					return YES;
				}
				[kept addObject:condition.kind == ORMPlanAggregate
				                    ? ([[self valuesAt:condition.valuePath object:read bindings:inner] firstObject] ?: [NSNull null])
				                    : member];
			}
		}
		if (condition.kind == ORMPlanExists) {
			return NO;
		}
		if (condition.kind == ORMPlanCount) {
			return ORMJSONCompare(@([kept count]), condition.comparison, @(condition.number));
		}
		[kept removeObject:[NSNull null]];
		NSString *function = [@{ @"sum": @"@sum.self", @"average": @"@avg.self", @"max": @"@max.self",
		                         @"min": @"@min.self" } objectForKey:condition.function];
		id aggregate = [kept count] > 0 || [condition.function isEqualToString:@"sum"] ? [kept valueForKeyPath:function] : nil;
		return ORMJSONCompare(aggregate, condition.comparison, ORMJSONConstant(condition.constant));
	}
	case ORMPlanSame:
		return [self object:[[self valuesAt:condition.path object:read bindings:bindings] firstObject]
		                 is:[[self valuesAt:condition.otherPath object:read bindings:bindings] firstObject]];
	case ORMPlanAmong: {
		id base = condition.otherPath != nil ? [[self valuesAt:condition.otherPath object:read bindings:bindings] firstObject]
		                                     : read;
		NSArray *reached = [self valuesAt:[ORMPlanPath pathFrom:nil keys:condition.trail ?: @[]]
		                           object:[base isKindOfClass:[ORMODataObject class]] ? base : nil bindings:@{}];
		id value = [[self valuesAt:condition.path object:read bindings:bindings] firstObject];
		for (id each in reached) {
			if ([self object:each is:value]) {
				return YES;
			}
		}
		return NO;
	}
	case ORMPlanIsOf: {
		id value = [[self valuesAt:condition.path object:read bindings:bindings] firstObject];
		NSString *type = [value isKindOfClass:[ORMODataObject class]] ? [((ORMODataObject *)value).json objectForKey:@"@odata.type"]
		                                                              : nil;
		/* Without its type the service's answer says nothing more. */
		return type == nil || [type hasSuffix:[@"." stringByAppendingString:condition.entityName]];
	}
	case ORMPlanMatches:
		return [self matches:condition object:read bindings:bindings];
	case ORMPlanMaybe:
		/* Asking nothing. */
		return YES;
	}
	return NO;
}

/* The ways the condition holds: the variables it binds, added to those
 * bound. At the top, what does not bind is the filter's, and holds. */
- (NSArray<NSDictionary *> *)bindingsOf:(ORMPlanCondition *)condition object:(ORMODataObject *)read
                               bindings:(NSDictionary *)bindings top:(BOOL)top
{
	switch (condition.kind) {
	case ORMPlanAnd: {
		NSArray *ways = @[ bindings ];
		for (ORMPlanCondition *operand in condition.operands) {
			NSMutableArray *next = [NSMutableArray array];
			for (NSDictionary *way in ways) {
				[next addObjectsFromArray:[self bindingsOf:operand object:read bindings:way top:top]];
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
			[ways addObjectsFromArray:[self bindingsOf:operand object:read bindings:bindings top:top]];
		}
		return ways;
	}
	case ORMPlanExists:
	case ORMPlanMaybe: {
		if (top && ![self bindsListed:condition]) {
			/* Binds nothing listed: the filter's. */
			return @[ bindings ];
		}
		NSMutableArray *ways = [NSMutableArray array];
		for (id member in [self membersAt:condition.path object:read bindings:bindings]) {
			NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bindings];
			if (condition.variable != nil) {
				[inner setObject:member forKey:condition.variable];
			}
			if (condition.operand == nil) {
				[ways addObject:inner];
			} else {
				[ways addObjectsFromArray:[self bindingsOf:condition.operand object:read bindings:inner top:NO]];
			}
		}
		if (condition.kind == ORMPlanMaybe && [ways count] == 0) {
			return @[ bindings ];
		}
		if (condition.kind == ORMPlanExists && [ways count] == 0 && top) {
			/* The filter said there is one: what the answer lacks to say
			 * which is not this row's to leave out. */
			return @[ bindings ];
		}
		return ways;
	}
	default:
		return top || [self holds:condition object:read bindings:bindings] ? @[ bindings ] : @[];
	}
}

- (NSArray<NSArray *> *)rowsOf:(NSDictionary *)json
{
	ORMODataObject *read = ORMODataObjectOf(json, _read);
	NSArray *ways = _plan.condition != nil ? [self bindingsOf:_plan.condition object:read bindings:@{} top:YES] : @[ @{} ];
	if ([ways count] == 0) {
		ways = @[ @{} ];
	}
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *way in ways) {
		NSArray *tuples = @[ @[] ];
		for (ORMPlanColumn *column in _plan.columns) {
			NSMutableArray *next = [NSMutableArray array];
			for (NSArray *tuple in tuples) {
				for (id value in [self valuesAt:[column valuePath] object:read bindings:way]) {
					[next addObject:[tuple arrayByAddingObject:[value isKindOfClass:[ORMODataObject class]]
					                                               ? ((ORMODataObject *)value).json : value]];
				}
			}
			tuples = next;
		}
		[rows addObjectsFromArray:tuples];
	}
	return rows;
}

@end

/* The request evaluates on the service's answers, a batch at a time. */
@interface ORMQueryOData () <ORMBatchEvaluator>
- (NSArray<NSArray<NSString *> *> *)columnWire;
- (ODataPropertyMapper *)mapper;
- (NSArray<NSArray *> *)rowsOf:(NSDictionary *)json;
- (NSEntityDescription *)readEntity;
- (BOOL)keeps:(NSDictionary *)json;
/* Whether the bag is read for each page's groups. */
- (BOOL)scopesBag:(NSString *)name;
/* The order pages are read in, and how one starts after the last (nil:
 * by offset); each part's wire path. */
- (ORMSeek *)seek;
- (NSArray<NSArray<NSString *> *> *)seekWire;
- (BOOL)rowsInOrder;
- (ODataExpression *)join:(ORMQueryODataJoin *)join filterFor:(NSArray<NSDictionary *> *)page error:(NSError **)error;
- (ODataExpression *)bag:(NSString *)name filterFor:(NSArray<NSDictionary *> *)page error:(NSError **)error;
@end

@implementation ORMQueryOData
{
	ORMCDModel *_coreData;
	NSManagedObjectModel *_managed;
	ODataPropertyMapper *_mapper;
	NSEntityDescription *_read;
	NSMutableArray<NSString *> *_notes;
	NSMutableArray<ORMQueryODataJoin *> *_joins;
	NSMutableArray<ORMQueryODataJoin *> *_pageJoins;
	/* Each column's wire path, its identifier's at the end. */
	NSMutableArray<NSArray<NSString *> *> *_columnWire;
	/* The first error a builder gave: the request is not made. */
	NSError *_error;
	ORMODataRows *_rows;
	/* The plan's conditions the filter cannot say, checked on the answers. */
	NSMutableArray<ORMPlanCondition *> *_checks;
	/* Each variable bound where the lowering is, to what it ranges over,
	 * and the name it is written as ($this in a count's filter). */
	NSMutableDictionary<NSString *, NSEntityDescription *> *_bound;
	NSMutableDictionary<NSString *, NSString *> *_written;
	/* How many lambdas and counts enclose where the lowering is: inside one,
	 * the object read is written $it. */
	NSUInteger _depth;
	NSUInteger _variables;
	NSMutableDictionary<NSString *, ORMQueryOData *> *_bags;
	/* A bag read for each page's groups: @[ the group's path here, its
	 * wire path in the bag ], by its name. */
	NSMutableDictionary<NSString *, NSArray *> *_bagScopes;
	NSMutableArray<ORMQueryODataJoin *> *_wholeJoins;
}

+ (instancetype)requestForQuery:(ORMQuery *)query
                          model:(ORMModel *)model
                        mapping:(ORMCoreDataMapping *)mapping
                          error:(NSError **)error
{
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:mapping];
	return [self requestForPlan:[planner planForQuery:query] coreData:planner.coreData error:error];
}

+ (instancetype)requestForPlan:(ORMQueryPlan *)plan coreData:(ORMCDModel *)coreData error:(NSError **)error
{
	ORMQueryOData *request = [[self alloc] init];
	request->_plan = plan;
	request->_coreData = coreData;
	request->_managed = [coreData managedObjectModel];
	request->_mapper = [[ODataPropertyMapper alloc] init];
	request->_notes = [NSMutableArray arrayWithArray:plan.notes ?: @[]];
	request->_joins = [NSMutableArray array];
	request->_pageJoins = [NSMutableArray array];
	request->_columnWire = [NSMutableArray array];
	request->_bound = [NSMutableDictionary dictionary];
	request->_written = [NSMutableDictionary dictionary];
	request->_checks = [NSMutableArray array];
	request->_bags = [NSMutableDictionary dictionary];
	request->_bagScopes = [NSMutableDictionary dictionary];
	request->_wholeJoins = [NSMutableArray array];
	[request lower];
	if (request->_error != nil) {
		if (error != NULL) {
			*error = request->_error;
		}
		return nil;
	}
	return request;
}

- (void)fail:(NSError *)error
{
	if (_error == nil) {
		_error = error ?: ORMODataError(@"The request could not be built.");
	}
}

- (void)note:(NSString *)text
{
	if (![_notes containsObject:text]) {
		[_notes addObject:text];
	}
}

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
}

- (NSArray<ORMQueryODataJoin *> *)joins
{
	return [_joins copy];
}

- (NSArray<ORMQueryODataJoin *> *)pageJoins
{
	return [_pageJoins copy];
}

- (NSArray<ORMQueryODataJoin *> *)wholeJoins
{
	return [_wholeJoins copy];
}

- (NSDictionary<NSString *, id> *)answers
{
	return _rows.answers;
}

- (void)setAnswers:(NSDictionary<NSString *, id> *)answers
{
	_rows.answers = answers;
}

/* Whether the join depends on each object read. */
- (BOOL)correlated:(ORMPlanCondition *)condition
{
	return condition.kind == ORMPlanMatches
	       && (condition.variable != nil || [[condition.plan.condition freeVariables] count] > 0);
}

/* A request reading whole each correlated join in the condition. */
- (void)requestWholeJoinsOf:(ORMPlanCondition *)condition
{
	if (condition == nil) {
		return;
	}
	for (ORMPlanCondition *operand in condition.operands) {
		[self requestWholeJoinsOf:operand];
	}
	[self requestWholeJoinsOf:condition.operand];
	NSString *name = condition.definition.name;
	if (![self correlated:condition] || name == nil || [[_wholeJoins valueForKey:@"name"] containsObject:name]) {
		return;
	}
	NSEntityDescription *theirEntity = [self entityNamed:condition.plan.entityName];
	ORMPlanCondition *joinedCondition = condition.plan.condition;
	NSArray *conjuncts = joinedCondition == nil ? @[]
		: (joinedCondition.kind == ORMPlanAnd ? joinedCondition.operands : @[ joinedCondition ]);
	NSMutableArray *rest = [NSMutableArray array];
	for (ORMPlanCondition *conjunct in conjuncts) {
		if ([[conjunct freeVariables] count] == 0) {
			[rest addObject:conjunct];
		}
	}
	ORMPlanCondition *reduced = [rest count] == 0 ? nil : ([rest count] == 1 ? [rest firstObject] : [ORMPlanCondition all:rest]);
	NSError *error = nil;
	ORMQueryOData *joined = [ORMQueryOData requestForPlan:[ORMQueryPlan planReading:condition.plan.entityName where:reduced
	                                                                        columns:@[] sorts:@[] notes:@[]]
	                                             coreData:_coreData error:&error];
	if (joined == nil || theirEntity == nil) {
		[self fail:error];
		return;
	}
	for (NSString *note in joined.notes) {
		[self note:note];
	}
	/* The joined objects with what the pairs and the condition read of
	 * them. */
	ORMODataRows *paths = [[ORMODataRows alloc] initWithPlan:nil read:theirEntity mapper:_mapper];
	NSMutableArray *read = [NSMutableArray arrayWithArray:[paths pathsOf:joinedCondition from:nil]];
	for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
		[read addObject:[pair lastObject].keys];
	}
	ORMODataLevel *level = [ORMODataLevel levelOf:theirEntity];
	[self need:read from:theirEntity into:level];
	ODataMutableQueryOptions *options = [[ODataMutableQueryOptions alloc] init];
	if (![self level:level into:options]) {
		return;
	}
	options.filter = joined.filter;
	ORMQueryODataJoin *join = [[ORMQueryODataJoin alloc] init];
	join.name = name;
	join.entityName = condition.plan.entityName;
	join.collectionPath = joined.collectionPath;
	join.options = options;
	join.mapper = _mapper;
	join.entity = theirEntity;
	join.outer = condition.variable;
	join.check = joinedCondition;
	/* Narrowed to each page's values, where they are the object read's:
	 * a part that is an entity, by its key. */
	NSMutableArray *scope = [NSMutableArray array];
	for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
		NSEntityDescription *end = nil;
		NSArray *theirs = [self wirePathFor:[pair lastObject].keys from:theirEntity entity:&end];
		if ([pair firstObject].variable != nil || theirs == nil) {
			scope = nil;
			break;
		}
		if (end == nil) {
			[scope addObject:@[ [pair firstObject], [NSNull null], theirs ]];
			continue;
		}
		for (NSString *key in [self keyOf:end]) {
			[scope addObject:@[ [pair firstObject], key, [theirs arrayByAddingObject:key] ]];
		}
	}
	join.pageScope = [scope count] > 0 ? scope : nil;
	[_wholeJoins addObject:join];
}

/* What narrows the join's objects to the page's values: theirs one of
 * the page's tuples. nil for a join read whole, or a page with none (no
 * error). */
- (ODataExpression *)join:(ORMQueryODataJoin *)join filterFor:(NSArray<NSDictionary *> *)page error:(NSError **)error
{
	NSMutableOrderedSet *tuples = [NSMutableOrderedSet orderedSet];
	for (NSDictionary *json in page) {
		ORMODataObject *read = ORMODataObjectOf(json, _read);
		NSMutableArray *tuple = [NSMutableArray array];
		for (NSArray *part in join.pageScope) {
			id value = [[_rows valuesAt:[part firstObject] object:read bindings:@{}] firstObject];
			if ([part objectAtIndex:1] != [NSNull null]) {
				value = [value isKindOfClass:[ORMODataObject class]]
					? [((ORMODataObject *)value).json objectForKey:[part objectAtIndex:1]] : nil;
			}
			if (value == nil || value == [NSNull null]) {
				/* Equal to none. */
				tuple = nil;
				break;
			}
			[tuple addObject:value];
		}
		if (tuple != nil) {
			[tuples addObject:tuple];
		}
	}
	ODataExpression *any = nil;
	for (NSArray *tuple in tuples) {
		ODataExpression *all = nil;
		for (NSUInteger i = 0; i < [tuple count]; i++) {
			ODataExpression *path = [ODataExpression memberPath:[[join.pageScope objectAtIndex:i] lastObject] of:nil error:error];
			ODataExpression *equal = path != nil ? [ODataExpression binary:@"eq" left:path
			                                                         right:[ODataExpression literalWithValue:[tuple objectAtIndex:i]]
			                                                         error:error]
			                                     : nil;
			all = equal == nil ? nil : (all != nil ? [ODataExpression binary:@"and" left:all right:equal error:error] : equal);
			if (all == nil) {
				return nil;
			}
		}
		any = any != nil ? [ODataExpression binary:@"or" left:any right:all error:error] : all;
		if (any == nil) {
			return nil;
		}
	}
	return any;
}

- (NSDictionary<NSString *, ORMQueryOData *> *)bags
{
	return [_bags copy];
}

/* The wire path of the bag's group column, where a page's groups say
 * which of its rows the page needs: the group reached through to-ones
 * from the object read, here and in the bag, by its identifier. */
- (NSArray<NSString *> *)wireOfGroup:(ORMPlanValue *)value in:(ORMQueryOData *)request
{
	NSUInteger index = [[value.bag.plan.columns valueForKey:@"nodeId"] indexOfObject:value.groupColumn ?: @""];
	ORMPlanColumn *column = index != NSNotFound ? [value.bag.plan.columns objectAtIndex:index] : nil;
	if (column == nil || column.path.variable != nil || column.identifierKey == nil || value.groupPath.variable != nil) {
		return nil;
	}
	NSEntityDescription *at = [self entityNamed:value.bag.plan.entityName];
	for (NSString *key in column.trail) {
		NSPropertyDescription *property = [[at propertiesByName] objectForKey:key];
		if (![property isKindOfClass:[NSRelationshipDescription class]] || [(NSRelationshipDescription *)property isToMany]) {
			return nil;
		}
		at = ((NSRelationshipDescription *)property).destinationEntity;
	}
	return [[request columnWire] objectAtIndex:index];
}

/* Each part of the seek's order, as a wire path; nil where one is not a
 * value a literal says as the service compares it (a date, a GUID). */
- (NSArray<NSArray<NSString *> *> *)seekWire
{
	ORMSeek *seek = [self seekOrder];
	NSMutableArray *wires = [NSMutableArray array];
	NSArray *plain = @[ @(NSInteger16AttributeType), @(NSInteger32AttributeType), @(NSInteger64AttributeType),
	                    @(NSDecimalAttributeType), @(NSDoubleAttributeType), @(NSFloatAttributeType),
	                    @(NSStringAttributeType), @(NSBooleanAttributeType) ];
	for (NSArray *part in seek.order) {
		NSEntityDescription *at = _read;
		NSAttributeDescription *attribute = nil;
		for (NSString *key in [part firstObject]) {
			NSPropertyDescription *property = [[at propertiesByName] objectForKey:key];
			if ([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany]) {
				at = ((NSRelationshipDescription *)property).destinationEntity;
			} else {
				attribute = [property isKindOfClass:[NSAttributeDescription class]] ? (NSAttributeDescription *)property : nil;
			}
		}
		NSArray *wire = [self wirePathFor:[part firstObject] from:_read entity:NULL];
		if (attribute == nil || wire == nil || ![plain containsObject:@(attribute.attributeType)]) {
			return nil;
		}
		[wires addObject:wire];
	}
	return [wires count] > 0 ? wires : nil;
}

- (ORMSeek *)seekOrder
{
	if (_read == nil) {
		return nil;
	}
	NSMutableArray *sorts = [NSMutableArray array];
	for (ORMPlanSort *sort in _plan.sorts) {
		[sorts addObject:@[ sort.path.keys, @(sort.ascending) ]];
	}
	return [ORMSeek seekWithSorts:sorts key:[self keyNames]];
}

- (NSArray<NSString *> *)keyNames
{
	NSArray *key = [[_mapper keyAttributesForEntity:_read] valueForKey:@"name"];
	return [key sortedArrayUsingSelector:@selector(compare:)];
}

/* Whether equal rows come one after another, in the order pages are
 * read in. */
- (BOOL)rowsInOrder
{
	ORMSeek *seek = [self seek];
	NSMutableArray *order = [NSMutableArray array];
	for (NSArray *part in seek != nil ? seek.order : @[]) {
		[order addObject:[part firstObject]];
	}
	if (seek == nil) {
		for (ORMPlanSort *sort in _plan.sorts) {
			[order addObject:sort.path.keys];
		}
	}
	return [_plan rowsFollowOrder:order key:seek != nil ? [self keyNames] : nil];
}

- (ORMSeek *)seek
{
	return [self seekWire] != nil ? [self seekOrder] : nil;
}

- (BOOL)scopesBag:(NSString *)name
{
	return [_bagScopes objectForKey:name] != nil;
}

/* What narrows the bag to the page's groups: its group column one of
 * theirs. nil for a bag read whole, or a page with no group (no error). */
- (ODataExpression *)bag:(NSString *)name filterFor:(NSArray<NSDictionary *> *)page error:(NSError **)error
{
	NSArray *scope = [_bagScopes objectForKey:name];
	if (scope == nil) {
		return nil;
	}
	NSMutableOrderedSet *groups = [NSMutableOrderedSet orderedSet];
	for (NSDictionary *json in page) {
		for (id group in [_rows valuesAt:[scope firstObject] object:ORMODataObjectOf(json, _read) bindings:@{}]) {
			if (group != [NSNull null]) {
				[groups addObject:group];
			}
		}
	}
	ODataExpression *any = nil;
	for (id group in groups) {
		ODataExpression *path = [ODataExpression memberPath:[scope lastObject] of:nil error:error];
		ODataExpression *equal = path != nil ? [ODataExpression binary:@"eq" left:path
		                                                         right:[ODataExpression literalWithValue:group] error:error]
		                                     : nil;
		if (equal == nil) {
			return nil;
		}
		any = any != nil ? [ODataExpression binary:@"or" left:any right:equal error:error] : equal;
		if (any == nil) {
			return nil;
		}
	}
	return any;
}

/* A request for each bag an aggregate in the condition is of. */
- (void)requestBagsOf:(ORMPlanCondition *)condition
{
	if (condition == nil) {
		return;
	}
	for (ORMPlanValue *value in @[ condition.left ?: [NSNull null], condition.right ?: [NSNull null] ]) {
		ORMPlanDefinition *bag = [value isKindOfClass:[ORMPlanValue class]] ? value.bag : nil;
		if (bag == nil || [_bags objectForKey:bag.name] != nil) {
			continue;
		}
		NSError *error = nil;
		ORMQueryOData *request = [ORMQueryOData requestForPlan:bag.plan coreData:_coreData error:&error];
		if (request == nil) {
			[self fail:error];
			return;
		}
		for (NSString *note in request.notes) {
			[self note:[NSString stringWithFormat:@"%@: %@", bag.name, note]];
		}
		[_bags setObject:request forKey:bag.name];
		NSArray *wire = [self wireOfGroup:value in:request];
		if (wire != nil) {
			[_bagScopes setObject:@[ value.groupPath, wire ] forKey:bag.name];
		}
	}
	for (ORMPlanCondition *operand in condition.operands) {
		[self requestBagsOf:operand];
	}
	[self requestBagsOf:condition.operand];
}

- (BOOL)isComplete
{
	return _entityName != nil && [_notes count] == 0;
}

#pragma mark Names

- (NSString *)wireOf:(NSPropertyDescription *)property
{
	return [property isKindOfClass:[NSRelationshipDescription class]]
		? [_mapper propertyForRelationship:(NSRelationshipDescription *)property]
		: [_mapper propertyForAttribute:(NSAttributeDescription *)property];
}

/* The wire names of the attributes the service keys the entity by, in the
 * order of their names. */
- (NSArray<NSString *> *)keyOf:(NSEntityDescription *)entity
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *key = entity != nil ? [_mapper keyAttributesForEntity:entity] : @[];
	for (NSAttributeDescription *attribute in [key sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]]) {
		[names addObject:[_mapper propertyForAttribute:attribute]];
	}
	return names;
}

- (NSEntityDescription *)entityNamed:(NSString *)name
{
	NSEntityDescription *entity = name != nil ? [[_managed entitiesByName] objectForKey:name] : nil;
	if (entity == nil) {
		[self fail:ORMODataError([NSString stringWithFormat:@"The plan names %@, which the model has no entity of.", name])];
	}
	return entity;
}

#pragma mark Paths

/* The path as the filter says it, and the entity it reaches (nil: a value). */
- (ODataExpression *)expressionFor:(ORMPlanPath *)path entity:(NSEntityDescription **)reached
{
	NSError *error = nil;
	NSEntityDescription *at = path.variable != nil ? [_bound objectForKey:path.variable] : _read;
	ODataExpression *expression = nil;
	if (path.variable != nil) {
		expression = [ODataExpression variable:[_written objectForKey:path.variable] ?: path.variable error:&error];
	} else if (_depth > 0) {
		expression = [ODataExpression variable:@"$it" error:&error];
	}
	if ((path.variable != nil || _depth > 0) && expression == nil) {
		[self fail:error];
		return nil;
	}
	for (ORMPlanStep *step in path.steps) {
		if (step.entityName != nil) {
			at = [self entityNamed:step.entityName];
			NSString *type = at != nil ? [_mapper qualifiedTypeForEntity:at] : nil;
			expression = type != nil ? [ODataExpression cast:type of:expression error:&error] : nil;
		} else {
			NSPropertyDescription *property = [[at propertiesByName] objectForKey:step.key];
			if (property == nil) {
				[self fail:ORMODataError([NSString stringWithFormat:@"%@ has no property %@.", at.name ?: @"A value", step.key])];
				return nil;
			}
			expression = [ODataExpression member:[self wireOf:property] of:expression error:&error];
			at = [property isKindOfClass:[NSRelationshipDescription class]]
				? ((NSRelationshipDescription *)property).destinationEntity : nil;
		}
		if (expression == nil) {
			[self fail:error];
			return nil;
		}
	}
	if (reached != NULL) {
		*reached = at;
	}
	return expression ?: [ODataExpression variable:@"$it" error:NULL];
}

/* The wire names along a path from the object read, and the entity it
 * reaches. */
- (NSArray<NSString *> *)wirePathFor:(NSArray<NSString *> *)keys from:(NSEntityDescription *)start
                              entity:(NSEntityDescription **)reached
{
	NSMutableArray *names = [NSMutableArray array];
	NSEntityDescription *at = start;
	for (NSString *key in keys) {
		NSPropertyDescription *property = [[at propertiesByName] objectForKey:key];
		if (property == nil) {
			[self fail:ORMODataError([NSString stringWithFormat:@"%@ has no property %@.", at.name ?: @"A value", key])];
			return nil;
		}
		[names addObject:[self wireOf:property]];
		at = [property isKindOfClass:[NSRelationshipDescription class]] ? ((NSRelationshipDescription *)property).destinationEntity
		                                                                : nil;
	}
	if (reached != NULL) {
		*reached = at;
	}
	return names;
}

- (ODataExpression *)literal:(ORMPlanValue *)value
{
	NSString *type = value.attributeType;
	NSString *text = value.text ?: @"";
	if (([type hasPrefix:@"Integer"] || [@[ @"Decimal", @"Double", @"Float" ] containsObject:type]) && ORMIsNumber(text)) {
		ODataExpression *number = [ODataExpression literalWithText:text];
		if (number.kind == ODataExpressionLiteral) {
			return number;
		}
	}
	if ([type isEqualToString:@"Boolean"]) {
		NSString *lower = [text lowercaseString];
		if ([@[ @"true", @"yes", @"1" ] containsObject:lower]) {
			return [ODataExpression literalWithValue:@YES];
		}
		if ([@[ @"false", @"no", @"0" ] containsObject:lower]) {
			return [ODataExpression literalWithValue:@NO];
		}
	}
	if ([type isEqualToString:@"Date"]) {
		/* Read as one literal, and taken only if it is a date. */
		ODataExpression *date = [ODataExpression literalWithText:text];
		if (date.kind == ODataExpressionLiteral
		    && ([date.literalType isEqualToString:@"Edm.Date"] || [date.literalType isEqualToString:@"Edm.DateTimeOffset"])) {
			return date;
		}
	}
	return [ODataExpression literalWithValue:text];
}

- (ODataExpression *)value:(ORMPlanValue *)value
{
	return value.path != nil ? [self expressionFor:value.path entity:NULL] : [self literal:value];
}

#pragma mark Conditions

- (ODataExpression *)binary:(NSString *)op left:(ODataExpression *)left right:(ODataExpression *)right
{
	if (left == nil || right == nil) {
		return nil;
	}
	NSError *error = nil;
	ODataExpression *made = [ODataExpression binary:op left:left right:right error:&error];
	if (made == nil) {
		[self fail:error];
	}
	return made;
}

- (ODataExpression *)not:(ODataExpression *)operand
{
	if (operand == nil) {
		return nil;
	}
	NSError *error = nil;
	ODataExpression *made = [ODataExpression unary:@"not" operand:operand error:&error];
	if (made == nil) {
		[self fail:error];
	}
	return made;
}

- (ODataExpression *)all:(NSArray<ODataExpression *> *)parts connective:(NSString *)connective
{
	ODataExpression *combined = nil;
	for (ODataExpression *part in parts) {
		combined = combined != nil ? [self binary:connective left:combined right:part] : part;
	}
	return combined;
}

/* Two objects one: their keys equal. */
- (ODataExpression *)object:(ODataExpression *)left is:(ODataExpression *)right entity:(NSEntityDescription *)entity
{
	NSArray *key = [self keyOf:entity];
	if ([key count] == 0) {
		[self note:[NSString stringWithFormat:@"%@ has no key in OData: the mapping does not serve it.", entity.name]];
		return nil;
	}
	NSMutableArray *parts = [NSMutableArray array];
	for (NSString *name in key) {
		NSError *error = nil;
		ODataExpression *ours = [ODataExpression member:name of:left error:&error];
		ODataExpression *theirs = ours != nil ? [ODataExpression member:name of:right error:&error] : nil;
		if (theirs == nil) {
			[self fail:error];
			return nil;
		}
		[parts addObject:[self binary:@"eq" left:ours right:theirs]];
	}
	return [self all:parts connective:@"and"];
}

/* A lambda over the collection: any(), or any of its members, bound to the
 * variable, meeting the condition. */
- (ODataExpression *)any:(ORMPlanPath *)collection variable:(NSString *)variable where:(ORMPlanCondition *)condition
{
	NSEntityDescription *member = nil;
	ODataExpression *of = [self expressionFor:collection entity:&member];
	if (of == nil) {
		return nil;
	}
	ODataExpression *body = nil;
	if (condition != nil) {
		[_bound setObject:member forKey:variable];
		_depth++;
		body = [self lower:condition];
		_depth--;
		[_bound removeObjectForKey:variable];
		if (body == nil) {
			return nil;
		}
	}
	NSError *error = nil;
	ODataExpression *made = [ODataExpression lambda:@"any" of:of variable:body != nil ? variable : nil body:body error:&error];
	if (made == nil) {
		[self fail:error];
	}
	return made;
}

/* The object is among those the trail reaches from the object read: back
 * from it along the inverses, to $it, which a store says without a
 * subquery inside a subquery; else forward from $it. */
- (ODataExpression *)among:(ORMPlanPath *)path trail:(NSArray<NSString *> *)trail
{
	NSEntityDescription *entity = nil;
	ODataExpression *place = [self expressionFor:path entity:&entity];
	if (place == nil) {
		return nil;
	}
	NSMutableArray *inverses = [NSMutableArray array];
	NSEntityDescription *at = _read;
	BOOL back = entity != nil;
	for (NSString *key in trail) {
		NSRelationshipDescription *relationship = [[at relationshipsByName] objectForKey:key];
		if (relationship.inverseRelationship == nil) {
			back = NO;
			break;
		}
		[inverses insertObject:relationship.inverseRelationship atIndex:0];
		at = relationship.destinationEntity;
	}
	NSError *error = nil;
	ODataExpression *it = [ODataExpression variable:@"$it" error:&error];
	if (back) {
		return [self along:inverses from:place index:0 then:^ODataExpression *(ODataExpression *object) {
			return [self object:object is:it entity:self->_read];
		}];
	}
	NSMutableArray *properties = [NSMutableArray array];
	at = _read;
	for (NSString *key in trail) {
		NSPropertyDescription *property = [[at propertiesByName] objectForKey:key];
		if (property == nil) {
			[self fail:ORMODataError([NSString stringWithFormat:@"%@ has no property %@.", at.name, key])];
			return nil;
		}
		[properties addObject:property];
		at = [property isKindOfClass:[NSRelationshipDescription class]] ? ((NSRelationshipDescription *)property).destinationEntity
		                                                                : nil;
	}
	return [self along:properties from:it index:0 then:^ODataExpression *(ODataExpression *reached) {
		return entity != nil ? [self object:reached is:place entity:entity] : [self binary:@"eq" left:reached right:place];
	}];
}

/* Along the properties from the expression, a lambda for each to-many. */
- (ODataExpression *)along:(NSArray<NSPropertyDescription *> *)properties
                      from:(ODataExpression *)from
                     index:(NSUInteger)index
                      then:(ODataExpression * (^)(ODataExpression *reached))then
{
	if (index == [properties count]) {
		return then(from);
	}
	NSPropertyDescription *property = [properties objectAtIndex:index];
	NSError *error = nil;
	ODataExpression *next = [ODataExpression member:[self wireOf:property] of:from error:&error];
	if (next == nil) {
		[self fail:error];
		return nil;
	}
	if ([property isKindOfClass:[NSRelationshipDescription class]] && [(NSRelationshipDescription *)property isToMany]) {
		_variables++;
		NSString *variable = [NSString stringWithFormat:@"y%lu", (unsigned long)_variables];
		ODataExpression *member = [ODataExpression variable:variable error:&error];
		ODataExpression *body = member != nil ? [self along:properties from:member index:index + 1 then:then] : nil;
		ODataExpression *made = body != nil ? [ODataExpression lambda:@"any" of:next variable:variable body:body error:&error] : nil;
		if (made == nil) {
			[self fail:error];
		}
		return made;
	}
	return [self along:properties from:next index:index + 1 then:then];
}

- (ODataExpression *)lower:(ORMPlanCondition *)condition
{
	switch (condition.kind) {
	case ORMPlanAnd:
	case ORMPlanOr: {
		NSMutableArray *parts = [NSMutableArray array];
		for (ORMPlanCondition *operand in condition.operands) {
			if (operand.kind == ORMPlanMaybe && condition.kind == ORMPlanAnd) {
				/* Asks nothing beside what the others ask. */
				continue;
			}
			ODataExpression *part = [self lower:operand];
			if (part == nil) {
				return nil;
			}
			[parts addObject:part];
		}
		if ([parts count] == 0) {
			return [ODataExpression literalWithValue:@YES];
		}
		return [self all:parts connective:condition.kind == ORMPlanAnd ? @"and" : @"or"];
	}
	case ORMPlanNot:
		return [self not:[self lower:condition.operand]];
	case ORMPlanCompare:
		if (condition.left.bag != nil || condition.right.bag != nil) {
			/* Checked on the answers where it is a condition of its own;
			 * inside another, said by nothing. */
			[self note:[NSString stringWithFormat:@"%@ is not asked of the service.", condition]];
			return [ODataExpression literalWithValue:@YES];
		}
		return [self binary:[ORMODataOperators() objectForKey:condition.comparison] left:[self value:condition.left]
		              right:[self value:condition.right]];
	case ORMPlanNotNull:
		return [self binary:@"ne" left:[self expressionFor:condition.path entity:NULL]
		              right:[ODataExpression literalWithValue:[NSNull null]]];
	case ORMPlanExists:
		return [self any:condition.path variable:condition.variable where:condition.operand];
	case ORMPlanCount:
		return [self count:condition];
	case ORMPlanAggregate:
		return [self aggregate:condition];
	case ORMPlanIsOf: {
		NSEntityDescription *target = [self entityNamed:condition.entityName];
		NSString *type = target != nil ? [_mapper qualifiedTypeForEntity:target] : nil;
		NSError *error = nil;
		ODataExpression *name = type != nil ? [ODataExpression cast:type of:nil error:&error] : nil;
		BOOL read = condition.path.variable == nil && [condition.path.steps count] == 0 && _depth == 0;
		ODataExpression *object = read ? nil : [self expressionFor:condition.path entity:NULL];
		if (name == nil || (!read && object == nil)) {
			[self fail:error];
			return nil;
		}
		ODataExpression *made = [ODataExpression call:@"isof" arguments:read ? @[ name ] : @[ object, name ] error:&error];
		if (made == nil) {
			[self fail:error];
		}
		return made;
	}
	case ORMPlanSame: {
		NSEntityDescription *entity = nil;
		ODataExpression *left = [self expressionFor:condition.path entity:&entity];
		ODataExpression *right = [self expressionFor:condition.otherPath entity:NULL];
		return left != nil && right != nil ? [self object:left is:right entity:entity] : nil;
	}
	case ORMPlanAmong:
		return [self among:condition.path trail:condition.trail];
	case ORMPlanMatches:
		return [self matches:condition];
	case ORMPlanMaybe:
		/* Asks nothing of the objects read. */
		return [ODataExpression literalWithValue:@YES];
	}
	return nil;
}

/* A count: of all the members, the collection's; of those meeting a
 * condition, some or none as a lambda, else $count($filter=...) with the
 * member written $this. */
- (ODataExpression *)count:(ORMPlanCondition *)condition
{
	NSString *op = [ORMODataOperators() objectForKey:condition.comparison];
	NSUInteger n = condition.number;
	NSEntityDescription *member = nil;
	ODataExpression *of = [self expressionFor:condition.path entity:&member];
	if (of == nil) {
		return nil;
	}
	ODataExpression *number = [ODataExpression literalWithValue:@(n)];
	if (condition.operand == nil) {
		return [self binary:op left:[ODataExpression countOf:of] right:number];
	}
	BOOL some = ([op isEqualToString:@"gt"] && n == 0) || ([op isEqualToString:@"ge"] && n == 1)
		|| ([op isEqualToString:@"ne"] && n == 0);
	BOOL none = ([op isEqualToString:@"eq"] && n == 0) || ([op isEqualToString:@"lt"] && n == 1)
		|| ([op isEqualToString:@"le"] && n == 0);
	if (some || none) {
		ODataExpression *any = [self any:condition.path variable:condition.variable where:condition.operand];
		return some ? any : [self not:any];
	}
	[_bound setObject:member forKey:condition.variable];
	[_written setObject:@"$this" forKey:condition.variable];
	_depth++;
	ODataExpression *filter = [self lower:condition.operand];
	_depth--;
	[_written removeObjectForKey:condition.variable];
	[_bound removeObjectForKey:condition.variable];
	return filter != nil ? [self binary:op left:[ODataExpression countOf:of filter:filter] right:number] : nil;
}

- (ODataExpression *)aggregate:(ORMPlanCondition *)condition
{
	NSEntityDescription *member = nil;
	ODataExpression *of = [self expressionFor:condition.path entity:&member];
	if (of == nil) {
		return nil;
	}
	if (condition.operand != nil) {
		[self note:[NSString stringWithFormat:@"%@ of %@ is over every member of %@, not only those meeting the conditions "
		                                      @"below it: OData aggregates no filtered collection.",
		                                      condition.function, condition.valuePath, condition.path]];
	}
	NSArray *wire = [self wirePathFor:condition.valuePath.keys from:member entity:NULL];
	if (wire == nil) {
		return nil;
	}
	NSError *error = nil;
	ODataAggregate *aggregate = [ODataAggregate aggregateOfPath:wire method:condition.function alias:@"value" error:&error];
	ODataExpression *made = aggregate != nil ? [ODataExpression aggregateOf:of aggregate:aggregate error:&error] : nil;
	if (made == nil) {
		[self fail:error];
		return nil;
	}
	return [self binary:[ORMODataOperators() objectForKey:condition.comparison] left:made
	              right:[self literal:condition.constant]];
}

/* A join: the plan as a request of its own, made first, and in its place
 * an alias -filterJoining: puts the rows it answers in. */
- (ODataExpression *)matches:(ORMPlanCondition *)condition
{
	NSMutableSet *free = [NSMutableSet setWithSet:[condition.plan.condition freeVariables] ?: [NSSet set]];
	if (condition.variable != nil || [free count] > 0) {
		/* Correlated: the joined objects depend on each object this one
		 * reads, which a request made first cannot know. */
		[self note:[NSString stringWithFormat:@"The join with %@ depends on each %@ read, which takes a request for each: "
		                                      @"not made, and the join left out.",
		                                      condition.plan.entityName, _read.name]];
		return [ODataExpression literalWithValue:@YES];
	}
	NSError *error = nil;
	ORMQueryOData *joined = [ORMQueryOData requestForPlan:condition.plan coreData:_coreData error:&error];
	if (joined == nil) {
		[self fail:error];
		return nil;
	}
	for (NSString *note in joined.notes) {
		[self note:note];
	}
	NSEntityDescription *theirEntity = [self entityNamed:condition.plan.entityName];
	NSMutableArray *pairs = [NSMutableArray array];
	NSMutableArray *ours = [NSMutableArray array];
	NSMutableArray *select = [NSMutableArray array];
	NSMutableArray *expand = [NSMutableArray array];
	for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
		NSEntityDescription *ourEntity = nil;
		ODataExpression *our = [self expressionFor:[pair firstObject] entity:&ourEntity];
		NSEntityDescription *reached = nil;
		NSArray *theirs = [self wirePathFor:[[pair lastObject] keys] from:theirEntity entity:&reached];
		if (our == nil || theirs == nil) {
			return nil;
		}
		if (reached == nil) {
			[ours addObject:our];
			[pairs addObject:@[ [our memberPath] ?: @[ [our description] ], theirs ]];
			ODataSelectItem *item = [ODataSelectItem itemWithPath:theirs error:&error];
			if (item == nil) {
				[self fail:error];
				return nil;
			}
			[select addObject:item];
			continue;
		}
		/* A part that is an entity: compared by its key. */
		ODataMutableQueryOptions *keyOptions = [[ODataMutableQueryOptions alloc] init];
		NSMutableArray *keySelect = [NSMutableArray array];
		for (NSString *key in [self keyOf:reached]) {
			ODataExpression *ourKey = [ODataExpression member:key of:our error:&error];
			ODataSelectItem *item = ourKey != nil ? [ODataSelectItem itemWithPath:@[ key ] error:&error] : nil;
			if (item == nil) {
				[self fail:error];
				return nil;
			}
			[ours addObject:ourKey];
			[pairs addObject:@[ [ourKey memberPath] ?: @[ [ourKey description] ], [theirs arrayByAddingObject:key] ]];
			[keySelect addObject:item];
		}
		keyOptions.select = keySelect;
		ODataExpandItem *item = [ODataExpandItem itemWithPath:theirs options:keyOptions error:&error];
		if (item == nil) {
			[self fail:error];
			return nil;
		}
		[expand addObject:item];
	}
	ODataMutableQueryOptions *options = [[ODataMutableQueryOptions alloc] init];
	options.filter = joined.filter;
	options.select = select;
	options.expand = expand;
	ORMQueryODataJoin *join = [[ORMQueryODataJoin alloc] init];
	join.name = condition.definition.name ?: [NSString stringWithFormat:@"join%lu", (unsigned long)[_joins count] + 1];
	join.entityName = condition.plan.entityName;
	join.collectionPath = joined.collectionPath;
	join.options = options;
	join.pairs = pairs;
	join.ours = ours;
	join.mapper = _mapper;
	[_joins addObject:join];
	ODataExpression *alias = [ODataExpression alias:join.name error:&error];
	if (alias == nil) {
		[self fail:error];
	}
	return alias;
}

#pragma mark Joins page by page

/* A join among the plan's conditions as a request for each page: its plan
 * without what it says of the object read, which must be its parts'
 * equality with the joined objects' (more pairs); NO for another. */
- (BOOL)pageJoin:(ORMPlanCondition *)condition
{
	NSString *outer = condition.variable;
	NSMutableArray *ours = [NSMutableArray array];
	NSMutableArray *theirs = [NSMutableArray array];
	for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
		if ([pair firstObject].variable != nil || [pair lastObject].variable != nil) {
			return NO;
		}
		[ours addObject:[pair firstObject].keys];
		[theirs addObject:[pair lastObject].keys];
	}
	ORMPlanCondition *joinedCondition = condition.plan.condition;
	NSArray *conjuncts = joinedCondition == nil ? @[]
		: (joinedCondition.kind == ORMPlanAnd ? joinedCondition.operands : @[ joinedCondition ]);
	NSMutableArray *rest = [NSMutableArray array];
	NSMutableArray *checks = [NSMutableArray array];
	for (ORMPlanCondition *conjunct in conjuncts) {
		NSSet *free = [conjunct freeVariables];
		if ([free count] == 0) {
			[rest addObject:conjunct];
			continue;
		}
		if (outer == nil || ![free isEqualToSet:[NSSet setWithObject:outer]]) {
			return NO;
		}
		BOOL equality = conjunct.kind == ORMPlanSame
			|| (conjunct.kind == ORMPlanCompare && [conjunct.comparison isEqualToString:@"="] && conjunct.left.path != nil
			    && conjunct.right.path != nil);
		if (!equality) {
			/* Checked on the answers, the object of the page bound. */
			[checks addObject:conjunct];
			continue;
		}
		ORMPlanPath *a = conjunct.kind == ORMPlanSame ? conjunct.path : conjunct.left.path;
		ORMPlanPath *b = conjunct.kind == ORMPlanSame ? conjunct.otherPath : conjunct.right.path;
		ORMPlanPath *outside = [a.variable isEqualToString:outer] ? a : b;
		ORMPlanPath *inside = outside == a ? b : a;
		if (inside.variable != nil || ![outside.variable isEqualToString:outer]) {
			return NO;
		}
		[ours addObject:outside.keys];
		[theirs addObject:inside.keys];
	}
	ORMPlanCondition *reduced = [rest count] == 0 ? nil : ([rest count] == 1 ? [rest firstObject] : [ORMPlanCondition all:rest]);
	NSError *error = nil;
	ORMQueryOData *joined = [ORMQueryOData requestForPlan:[ORMQueryPlan planReading:condition.plan.entityName where:reduced
	                                                                        columns:@[] sorts:@[] notes:@[]]
	                                             coreData:_coreData error:&error];
	if (joined == nil) {
		[self fail:error];
		return NO;
	}
	for (NSString *note in joined.notes) {
		[self note:note];
	}
	/* The parts as wire paths, an entity's by its key. */
	NSEntityDescription *theirEntity = [self entityNamed:condition.plan.entityName];
	NSMutableArray *ourKeys = [NSMutableArray array];
	NSMutableArray *pairs = [NSMutableArray array];
	for (NSUInteger i = 0; i < [ours count]; i++) {
		NSEntityDescription *ourEnd = nil, *theirEnd = nil;
		NSArray *ourWire = [self wirePathFor:[ours objectAtIndex:i] from:_read entity:&ourEnd];
		NSArray *theirWire = [self wirePathFor:[theirs objectAtIndex:i] from:theirEntity entity:&theirEnd];
		if (ourWire == nil || theirWire == nil) {
			return NO;
		}
		if (ourEnd == nil) {
			[ourKeys addObject:[ours objectAtIndex:i]];
			[pairs addObject:@[ ourWire, theirWire ]];
			continue;
		}
		NSArray *key = [[_mapper keyAttributesForEntity:ourEnd]
			sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
		for (NSAttributeDescription *attribute in key) {
			NSString *wire = [_mapper propertyForAttribute:attribute];
			[ourKeys addObject:[[ours objectAtIndex:i] arrayByAddingObject:attribute.name]];
			[pairs addObject:@[ [ourWire arrayByAddingObject:wire], [theirWire arrayByAddingObject:wire] ]];
		}
	}
	ORMQueryODataJoin *join = [[ORMQueryODataJoin alloc] init];
	join.name = [NSString stringWithFormat:@"page%lu", (unsigned long)[_pageJoins count] + 1];
	join.entityName = condition.plan.entityName;
	join.collectionPath = joined.collectionPath;
	join.options = joined.options;
	join.joinedFilter = joined.filter;
	join.pairs = pairs;
	join.ourKeys = ourKeys;
	join.mapper = _mapper;
	join.entity = theirEntity;
	if ([checks count] > 0) {
		ORMPlanCondition *check = [checks count] == 1 ? [checks firstObject] : [ORMPlanCondition all:checks];
		ORMODataRows *paths = [[ORMODataRows alloc] initWithPlan:nil read:theirEntity mapper:_mapper];
		/* The joined objects with what the pairs and the check read of them. */
		ORMODataLevel *level = [ORMODataLevel levelOf:theirEntity];
		NSMutableArray *read = [NSMutableArray arrayWithArray:[paths pathsOf:check from:nil]];
		for (NSArray<ORMPlanPath *> *pair in condition.pairs) {
			[read addObject:[pair lastObject].keys];
		}
		[self need:read from:theirEntity into:level];
		ODataMutableQueryOptions *rowOptions = [[ODataMutableQueryOptions alloc] init];
		if (![self level:level into:rowOptions]) {
			return NO;
		}
		join.check = check;
		join.outer = outer;
		join.rowOptions = rowOptions;
		join.outerKeys = [paths pathsOf:check from:outer];
	}
	[_pageJoins addObject:join];
	return YES;
}

#pragma mark The request

/* Whether the condition is one the filter cannot say, but the answers can
 * be checked by: an aggregate of a bag, or of the members meeting
 * conditions (which ODataKit's service does not compute). */
- (BOOL)checked:(ORMPlanCondition *)condition
{
	if (condition == nil) {
		return NO;
	}
	if (condition.kind == ORMPlanCompare) {
		return condition.left.bag != nil || condition.right.bag != nil;
	}
	if (condition.kind == ORMPlanAggregate && condition.operand != nil) {
		return YES;
	}
	if (condition.kind == ORMPlanMatches) {
		return [self correlated:condition];
	}
	for (ORMPlanCondition *operand in condition.operands) {
		if ([self checked:operand]) {
			return YES;
		}
	}
	return [self checked:condition.operand];
}

/* What the filter can say of a condition it cannot say whole: the parts it
 * cannot dropped where that only widens what it asks (an and, a some's
 * conditions); nil where nothing is left, or under a not or an or. */
- (ORMPlanCondition *)weakened:(ORMPlanCondition *)condition
{
	if (![self checked:condition]) {
		return condition;
	}
	if (condition.kind == ORMPlanAnd) {
		NSMutableArray *parts = [NSMutableArray array];
		for (ORMPlanCondition *operand in condition.operands) {
			ORMPlanCondition *part = [self weakened:operand];
			if (part != nil) {
				[parts addObject:part];
			}
		}
		return [parts count] == 0 ? nil : ([parts count] == 1 ? [parts firstObject] : [ORMPlanCondition all:parts]);
	}
	if (condition.kind == ORMPlanExists) {
		ORMPlanCondition *body = [self weakened:condition.operand];
		return [ORMPlanCondition exists:condition.path variable:body != nil ? condition.variable : nil where:body];
	}
	return nil;
}

/* Whether the service's answer meets the checks. */
- (BOOL)keeps:(NSDictionary *)json
{
	for (ORMPlanCondition *check in _checks) {
		if (![_rows holds:check object:ORMODataObjectOf(json, _read) bindings:@{}]) {
			return NO;
		}
	}
	return YES;
}

- (void)lower
{
	if (_plan.entityName == nil) {
		return;
	}
	_read = [self entityNamed:_plan.entityName];
	if (_read == nil) {
		return;
	}
	_entityName = _plan.entityName;
	_collectionPath = [_mapper collectionPathForEntity:_read];
	_rows = [[ORMODataRows alloc] initWithPlan:_plan read:_read mapper:_mapper];
	[self requestBagsOf:_plan.condition];
	if ([[self keyOf:_read] count] == 0) {
		[self note:[NSString stringWithFormat:@"%@ has no key in OData, so the service does not serve it: map it with "
		                                      @"ServeOData.", _read.name]];
	}
	/* The joins among the plan's conditions, asked for page by page; the
	 * rest in the filter. */
	ORMPlanCondition *condition = _plan.condition;
	NSArray *conjuncts = condition == nil ? @[] : (condition.kind == ORMPlanAnd ? condition.operands : @[ condition ]);
	NSMutableArray *kept = [NSMutableArray array];
	for (ORMPlanCondition *conjunct in conjuncts) {
		if (conjunct.kind == ORMPlanMaybe || (conjunct.kind == ORMPlanMatches && [self pageJoin:conjunct])) {
			continue;
		}
		if ([self checked:conjunct]) {
			/* What the filter cannot say: checked on the answers, the
			 * filter asking what it can of it. */
			[_checks addObject:conjunct];
			[self requestWholeJoinsOf:conjunct];
			ORMPlanCondition *weaker = [self weakened:conjunct];
			if (weaker != nil) {
				[kept addObject:weaker];
			}
			continue;
		}
		if (_error != nil) {
			return;
		}
		[kept addObject:conjunct];
	}
	ORMPlanCondition *rest = [kept count] == 0 ? nil : ([kept count] == 1 ? [kept firstObject] : [ORMPlanCondition all:kept]);
	_filter = rest != nil ? [self lower:rest] : nil;
	if (_error != nil) {
		return;
	}
	ODataMutableQueryOptions *options = [[ODataMutableQueryOptions alloc] init];
	options.filter = _filter;
	if (![self selectInto:options] || ![self orderInto:options]) {
		return;
	}
	_options = options;
}

/* $select and $expand: each column's identifier, or its value, at the level
 * its path expands to; the key wherever nothing else is. */
- (BOOL)selectInto:(ODataMutableQueryOptions *)options
{
	ORMODataLevel *top = [ORMODataLevel levelOf:_read];
	for (ORMPlanColumn *column in _plan.columns) {
		ORMODataLevel *level = top;
		NSEntityDescription *at = _read;
		NSArray *keys = column.trail;
		for (NSUInteger i = 0; i < [keys count]; i++) {
			NSPropertyDescription *property = [[at propertiesByName] objectForKey:[keys objectAtIndex:i]];
			if (property == nil) {
				[self fail:ORMODataError([NSString stringWithFormat:@"%@ has no property %@.", at.name, [keys objectAtIndex:i]])];
				return NO;
			}
			if ([property isKindOfClass:[NSRelationshipDescription class]]) {
				at = ((NSRelationshipDescription *)property).destinationEntity;
				level = [level expanding:[self wireOf:property] entity:at];
			} else if (i + 1 == [keys count]) {
				[level.select addObject:[self wireOf:property]];
				at = nil;
			}
		}
		NSMutableArray *wire = [NSMutableArray arrayWithArray:[self wirePathFor:keys from:_read entity:NULL] ?: @[]];
		if (at != nil) {
			NSPropertyDescription *identifier = column.identifierKey != nil
				? [[at propertiesByName] objectForKey:column.identifierKey] : nil;
			if (identifier != nil) {
				[level.select addObject:[self wireOf:identifier]];
				[wire addObject:[self wireOf:identifier]];
			} else {
				level.all = YES;
			}
		}
		[_columnWire addObject:wire];
	}
	/* What the page joins compare and check, and what the rows look at. */
	NSMutableArray *read = [NSMutableArray arrayWithArray:[_rows neededPaths]];
	for (ORMPlanCondition *check in _checks) {
		[read addObjectsFromArray:[_rows pathsOf:check from:nil]];
	}
	for (ORMQueryODataJoin *join in _pageJoins) {
		[read addObjectsFromArray:join.ourKeys];
		[read addObjectsFromArray:join.outerKeys ?: @[]];
	}
	[self need:read from:_read into:top];
	return [self level:top into:options];
}

/* Each key path selected, or expanded, at its level. */
- (void)need:(NSArray<NSArray<NSString *> *> *)paths from:(NSEntityDescription *)entity into:(ORMODataLevel *)top
{
	for (NSArray<NSString *> *keys in paths) {
		ORMODataLevel *level = top;
		NSEntityDescription *at = entity;
		for (NSUInteger i = 0; i < [keys count]; i++) {
			NSPropertyDescription *property = [[at propertiesByName] objectForKey:[keys objectAtIndex:i]];
			if ([property isKindOfClass:[NSRelationshipDescription class]]) {
				at = ((NSRelationshipDescription *)property).destinationEntity;
				level = [level expanding:[self wireOf:property] entity:at];
			} else if (property != nil && ![level.select containsObject:[self wireOf:property]]) {
				[level.select addObject:[self wireOf:property]];
			}
		}
	}
}

- (BOOL)level:(ORMODataLevel *)level into:(ODataMutableQueryOptions *)options
{
	NSError *error = nil;
	if (!level.all) {
		NSMutableArray *names = [NSMutableArray arrayWithArray:[self keyOf:level.entity]];
		for (NSString *name in level.select) {
			if (![names containsObject:name]) {
				[names addObject:name];
			}
		}
		NSMutableArray *select = [NSMutableArray array];
		for (NSString *name in names) {
			ODataSelectItem *item = [ODataSelectItem itemWithPath:@[ name ] error:&error];
			if (item == nil) {
				[self fail:error];
				return NO;
			}
			[select addObject:item];
		}
		options.select = select;
	}
	NSMutableArray *expand = [NSMutableArray array];
	for (NSString *name in level.expandNames) {
		ODataMutableQueryOptions *inner = [[ODataMutableQueryOptions alloc] init];
		if (![self level:[level.expand objectForKey:name] into:inner]) {
			return NO;
		}
		ODataExpandItem *item = [ODataExpandItem itemWithPath:@[ name ] options:inner error:&error];
		if (item == nil) {
			[self fail:error];
			return NO;
		}
		[expand addObject:item];
	}
	options.expand = expand;
	return YES;
}

- (BOOL)orderInto:(ODataMutableQueryOptions *)options
{
	NSMutableArray *items = [NSMutableArray array];
	for (ORMPlanSort *sort in _plan.sorts) {
		NSArray *wire = [self wirePathFor:sort.path.keys from:_read entity:NULL];
		NSError *error = nil;
		ODataExpression *path = wire != nil ? [ODataExpression memberPath:wire of:nil error:&error] : nil;
		ODataOrderItem *item = path != nil ? [ODataOrderItem itemWithExpression:path descending:!sort.ascending] : nil;
		if (item == nil) {
			[self fail:error];
			return NO;
		}
		[items addObject:item];
	}
	options.orderBy = items;
	return YES;
}

- (NSString *)queryText
{
	NSMutableArray *items = [NSMutableArray array];
	for (NSArray<NSString *> *item in [_options queryItemsWithError:NULL] ?: @[]) {
		[items addObject:[item componentsJoinedByString:@"="]];
	}
	return [items componentsJoinedByString:@"&"];
}

static NSString *
ORMRequestLine(NSString *path, ODataQueryOptions *options)
{
	NSMutableArray *items = [NSMutableArray array];
	for (NSArray<NSString *> *item in [options queryItemsWithError:NULL] ?: @[]) {
		[items addObject:[item componentsJoinedByString:@"="]];
	}
	NSString *query = [items componentsJoinedByString:@"&"];
	return [NSString stringWithFormat:@"GET %@%@%@\n", path, [query length] > 0 ? @"?" : @"", query];
}

- (NSString *)requestText
{
	if (_collectionPath == nil) {
		return @"";
	}
	NSMutableString *text = [NSMutableString string];
	for (NSString *name in [[_bags allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSString *bag = [[_bags objectForKey:name] requestText];
		NSArray *scope = [_bagScopes objectForKey:name];
		if (scope != nil) {
			[text appendFormat:@"%@, for each page, where %@ is one of the page's %@:\n%@", name,
			                   [[scope lastObject] componentsJoinedByString:@"/"], [scope firstObject], bag];
		} else {
			[text appendFormat:@"%@, read whole:\n%@", name, bag];
		}
	}
	for (ORMQueryODataJoin *join in _wholeJoins) {
		if (join.pageScope != nil) {
			NSMutableArray *parts = [NSMutableArray array];
			for (NSArray *part in join.pageScope) {
				[parts addObject:[[part lastObject] componentsJoinedByString:@"/"]];
			}
			[text appendFormat:@"%@, for each page, where %@ are one of the page's: %@", join.name,
			                   [parts componentsJoinedByString:@", "], ORMRequestLine(join.collectionPath, join.options)];
		} else {
			[text appendFormat:@"%@, read whole: %@", join.name, ORMRequestLine(join.collectionPath, join.options)];
		}
	}
	for (ORMQueryODataJoin *join in _joins) {
		[text appendFormat:@"%@: %@", join.name, ORMRequestLine(join.collectionPath, join.options)];
	}
	if ([_joins count] > 0) {
		[text appendString:@"then, each @join its rows' parts:\n"];
	}
	[text appendString:ORMRequestLine(_collectionPath, _options)];
	ORMSeek *seek = [self seek];
	[text appendString:seek != nil ? [NSString stringWithFormat:@"  in pages ordered by %@, each after the last one's\n",
	                                                           [seek orderText]]
	                               : @"  in pages by $skip\n"];
	for (ORMQueryODataJoin *join in _pageJoins) {
		NSMutableArray *pairs = [NSMutableArray array];
		for (NSArray *pair in join.pairs) {
			[pairs addObject:[NSString stringWithFormat:@"%@ = %@", [[pair firstObject] componentsJoinedByString:@"/"],
			                                            [[pair lastObject] componentsJoinedByString:@"/"]]];
		}
		[text appendFormat:@"and for each page, %@: %@  grouped by %@, of the page's values\n", join.name,
		                   ORMRequestLine(join.collectionPath, join.options), [pairs componentsJoinedByString:@", "]];
	}
	return text;
}

- (NSURL *)URLWithServiceRoot:(NSURL *)serviceRoot error:(NSError **)error
{
	if (_collectionPath == nil) {
		return nil;
	}
	ODataQueryBuilder *builder = [[ODataQueryBuilder alloc] initWithMapper:_mapper serviceRoot:serviceRoot];
	return [builder URLForPath:_collectionPath options:_options error:error];
}

- (ODataExpression *)filterJoining:(NSDictionary<NSString *, NSArray<NSDictionary *> *> *)joined error:(NSError **)error
{
	NSMutableDictionary *values = [NSMutableDictionary dictionary];
	for (ORMQueryODataJoin *join in _joins) {
		NSMutableArray *alternatives = [NSMutableArray array];
		for (NSDictionary *row in [joined objectForKey:join.name]) {
			ODataExpression *parts = nil;
			for (NSUInteger i = 0; i < [join.pairs count]; i++) {
				id value = row;
				for (NSString *name in [[join.pairs objectAtIndex:i] lastObject]) {
					value = [value isKindOfClass:[NSDictionary class]] ? [value objectForKey:name] : nil;
				}
				ODataExpression *equal = [ODataExpression binary:@"eq" left:[join.ours objectAtIndex:i]
				                                           right:[ODataExpression literalWithValue:value ?: [NSNull null]]
				                                           error:error];
				parts = parts != nil ? [ODataExpression binary:@"and" left:parts right:equal error:error] : equal;
				if (parts == nil) {
					return nil;
				}
			}
			[alternatives addObject:parts];
		}
		ODataExpression *any = nil;
		for (ODataExpression *alternative in alternatives) {
			any = any != nil ? [ODataExpression binary:@"or" left:any right:alternative error:error] : alternative;
			if (any == nil) {
				return nil;
			}
		}
		[values setObject:any ?: [ODataExpression literalWithValue:@NO] forKey:[@"@" stringByAppendingString:join.name]];
	}
	return [_filter expressionReplacing:values];
}

- (NSArray<NSArray *> *)rowsOf:(NSDictionary *)json
{
	return [_rows rowsOf:json];
}

- (NSEntityDescription *)readEntity
{
	return _read;
}

- (NSArray<NSArray<NSString *> *> *)columnWire
{
	return [_columnWire copy];
}

- (ODataPropertyMapper *)mapper
{
	return _mapper;
}

- (ORMQueryODataCursor *)cursorWithTransport:(id<ODataTransport>)transport serviceRoot:(NSURL *)serviceRoot
{
	return _collectionPath != nil ? [[ORMQueryODataCursor alloc] initWithRequest:self transport:transport serviceRoot:serviceRoot]
	                              : nil;
}

- (NSURL *)URLJoining:(NSDictionary<NSString *, NSArray<NSDictionary *> *> *)joined
          serviceRoot:(NSURL *)serviceRoot
                error:(NSError **)error
{
	ODataExpression *filter = [self filterJoining:joined error:error];
	if (filter == nil && _filter != nil) {
		return nil;
	}
	ODataMutableQueryOptions *options = [_options mutableCopy];
	options.filter = filter;
	ODataQueryBuilder *builder = [[ODataQueryBuilder alloc] initWithMapper:_mapper serviceRoot:serviceRoot];
	return [builder URLForPath:_collectionPath options:options error:error];
}

@end

#pragma mark The cursor

/* An exchange's end, as a block. */
@interface ORMODataCall : NSObject
@property (nonatomic, copy) void (^done)(ODataExchange *exchange);
@end

@implementation ORMODataCall

- (void)exchangeDidFinish:(ODataExchange *)exchange
{
	void (^done)(ODataExchange *) = self.done;
	self.done = nil;
	if (done != nil) {
		done(exchange);
	}
}

@end

/* The values at a wire path of an entity as JSON: each one, through
 * arrays (an expanded to-many). */
static NSArray *
ORMJSONValues(id json, NSArray<NSString *> *path)
{
	NSArray *values = @[ json ?: [NSNull null] ];
	for (NSString *name in path) {
		NSMutableArray *next = [NSMutableArray array];
		for (id value in values) {
			id member = [value isKindOfClass:[NSDictionary class]] ? [value objectForKey:name] : nil;
			if ([member isKindOfClass:[NSArray class]]) {
				[next addObjectsFromArray:member];
			} else {
				[next addObject:member ?: [NSNull null]];
			}
		}
		values = next;
	}
	return [values count] > 0 ? values : @[ [NSNull null] ];
}

/* The request's objects, a page at a time: the cursors' leaf. */
@interface ORMODataScan : NSObject <ORMCursor>
@property (nonatomic, weak) ORMQueryODataCursor *cursor;
@property (nonatomic, strong) ORMQueryOData *request;
@end

/* The input's objects a page join keeps (docs/CURSORS.md: SemiJoin). */
@interface ORMODataSemiJoin : NSObject <ORMCursor>
@property (nonatomic, strong) id<ORMCursor> input;
@property (nonatomic, strong) ORMQueryODataJoin *join;
@property (nonatomic, weak) ORMQueryODataCursor *cursor;
@end

@implementation ORMQueryODataCursor
{
	ORMQueryOData *_request;
	id<ODataTransport> _transport;
	NSURL *_root;
	ODataPropertyMapper *_mapper;
	/* The request's options, its joins' rows put in, once fetched. */
	ODataQueryOptions *_options;
	/* Pages of what the cursors read (docs/CURSORS.md). */
	ORMPageReader *_reader;
}

- (instancetype)initWithRequest:(ORMQueryOData *)request transport:(id<ODataTransport>)transport serviceRoot:(NSURL *)root
{
	if ((self = [super init])) {
		_request = request;
		_transport = transport;
		_root = root;
		_mapper = [request mapper];
	}
	return self;
}

- (BOOL)atEnd
{
	return _reader != nil && _reader.atEnd;
}

/* A GET of the URL: its value, and its next link. */
- (void)get:(NSURL *)url completion:(void (^)(NSArray *values, NSURL *next, NSError *error))completion
{
	ORMODataCall *call = [[ORMODataCall alloc] init];
	call.done = ^(ODataExchange *exchange) {
		NSInteger status = [exchange.URLResponse isKindOfClass:[NSHTTPURLResponse class]]
			? ((NSHTTPURLResponse *)exchange.URLResponse).statusCode : 0;
		id json = exchange.data != nil ? [NSJSONSerialization JSONObjectWithData:exchange.data options:0 error:NULL] : nil;
		if (exchange.error != nil || status != 200 || ![json isKindOfClass:[NSDictionary class]]) {
			NSString *body = exchange.data != nil ? [[NSString alloc] initWithData:exchange.data encoding:NSUTF8StringEncoding] : @"";
			completion(nil, nil, exchange.error ?: [NSError errorWithDomain:ORMQueryPlanErrorDomain code:4
			                                                        userInfo:@{ NSLocalizedDescriptionKey:
			                                                                        [NSString stringWithFormat:@"%@ answered %ld: %@",
			                                                                                                   url, (long)status, body] }]);
			return;
		}
		NSString *next = [json objectForKey:@"@odata.nextLink"];
		completion([json objectForKey:@"value"] ?: @[], [next isKindOfClass:[NSString class]] ? [NSURL URLWithString:next] : nil,
		           nil);
	};
	ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:[NSURLRequest requestWithURL:url] target:call
	                                                          action:@selector(exchangeDidFinish:)];
	[_transport startExchange:exchange];
}

- (NSURL *)URLFor:(NSString *)path options:(ODataQueryOptions *)options error:(NSError **)error
{
	ODataQueryBuilder *builder = [[ODataQueryBuilder alloc] initWithMapper:_mapper serviceRoot:_root];
	return [builder URLForPath:path options:options error:error];
}

/* Every row of a URL, its next links followed. */
- (void)all:(NSURL *)url into:(NSMutableArray *)rows completion:(void (^)(NSError *error))completion
{
	[self get:url completion:^(NSArray *values, NSURL *next, NSError *error) {
		if (error != nil) {
			completion(error);
			return;
		}
		[rows addObjectsFromArray:values];
		if (next != nil) {
			[self all:next into:rows completion:completion];
		} else {
			completion(nil);
		}
	}];
}

/* The request's joins made first, once: their rows put in its filter. */
- (void)prepare:(void (^)(NSError *error))completion
{
	if (_options != nil) {
		completion(nil);
		return;
	}
	NSArray *joins = _request.joins;
	NSMutableDictionary *joined = [NSMutableDictionary dictionary];
	__block NSUInteger index = 0;
	__block void (^step)(void) = nil;
	__weak ORMQueryODataCursor *weakSelf = self;
	void (^finish)(void) = ^{
		ORMQueryODataCursor *strongSelf = weakSelf;
		NSError *error = nil;
		ODataMutableQueryOptions *options = [strongSelf->_request.options mutableCopy];
		if ([joins count] > 0) {
			options.filter = [strongSelf->_request filterJoining:joined error:&error];
			if (options.filter == nil) {
				completion(error);
				return;
			}
		}
		if (strongSelf.extraFilter != nil) {
			options.filter = options.filter != nil
				? [ODataExpression binary:@"and" left:options.filter right:strongSelf.extraFilter error:&error]
				: strongSelf.extraFilter;
			if (options.filter == nil) {
				completion(error);
				return;
			}
		}
		strongSelf->_options = options;
		completion(nil);
	};
	step = ^{
		if (index == [joins count]) {
			finish();
			step = nil;
			return;
		}
		ORMQueryODataJoin *join = [joins objectAtIndex:index];
		NSError *error = nil;
		NSURL *url = [join URLWithServiceRoot:self->_root error:&error];
		if (url == nil) {
			step = nil;
			completion(error);
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		[self all:url into:rows completion:^(NSError *fetched) {
			if (fetched != nil) {
				step = nil;
				completion(fetched);
				return;
			}
			[joined setObject:rows forKey:join.name];
			index++;
			step();
		}];
	};
	step();
}

/* A page of the request's objects: in the seek's order, after the last
 * page's last object (its values in that order); without them, after the
 * offset. */
- (void)scan:(NSUInteger)count
      offset:(NSUInteger)offset
       after:(NSArray *)last
  completion:(void (^)(NSArray *values, NSError *error))completion
{
	[self prepare:^(NSError *unprepared) {
		if (unprepared != nil) {
			completion(nil, unprepared);
			return;
		}
		ODataMutableQueryOptions *options = [self->_options mutableCopy];
		options.top = @(count);
		NSError *error = nil;
		ORMSeek *seek = [self->_request seek];
		NSArray *wires = [self->_request seekWire];
		if (seek != nil) {
			/* In a total order: the sorts, then the key. */
			NSMutableArray *order = [NSMutableArray array];
			for (NSUInteger i = 0; i < [seek.order count]; i++) {
				ODataExpression *path = [ODataExpression memberPath:[wires objectAtIndex:i] of:nil error:&error];
				ODataOrderItem *item = path != nil ? [ODataOrderItem itemWithExpression:path
				                                                             descending:![[[seek.order objectAtIndex:i] lastObject] boolValue]]
				                                   : nil;
				if (item == nil) {
					completion(nil, error);
					return;
				}
				[order addObject:item];
			}
			options.orderBy = order;
		}
		NSArray *after = seek != nil && last != nil ? [seek after:last] : nil;
		if (after != nil) {
			/* After the last one read: (a gt x) or (a eq x and b gt y) ... */
			ODataExpression *any = nil;
			for (NSArray *all in after) {
				ODataExpression *conjunction = nil;
				for (NSArray *part in all) {
					NSUInteger index = [seek.order indexOfObjectPassingTest:^BOOL(NSArray *each, NSUInteger i, BOOL *stop) {
						(void)i;
						(void)stop;
						return [[each firstObject] isEqualToArray:[part firstObject]];
					}];
					NSString *op = [@{ @"=": @"eq", @">": @"gt", @"<": @"lt" } objectForKey:[part objectAtIndex:1]];
					ODataExpression *path = [ODataExpression memberPath:[wires objectAtIndex:index] of:nil error:&error];
					ODataExpression *compared = path != nil ? [ODataExpression binary:op left:path
					                                                            right:[ODataExpression literalWithValue:[part lastObject]]
					                                                            error:&error]
					                                        : nil;
					conjunction = compared == nil ? nil
						: (conjunction != nil ? [ODataExpression binary:@"and" left:conjunction right:compared error:&error] : compared);
					if (conjunction == nil) {
						completion(nil, error);
						return;
					}
				}
				any = any != nil ? [ODataExpression binary:@"or" left:any right:conjunction error:&error] : conjunction;
				if (any == nil) {
					completion(nil, error);
					return;
				}
			}
			options.filter = options.filter != nil ? [ODataExpression binary:@"and" left:options.filter right:any error:&error]
			                                       : any;
			if (options.filter == nil) {
				completion(nil, error);
				return;
			}
		} else {
			options.skip = @(offset);
		}
		NSURL *url = [self URLFor:self->_request.collectionPath options:options error:&error];
		if (url == nil) {
			completion(nil, error);
			return;
		}
		[self get:url completion:^(NSArray *values, NSURL *next, NSError *fetched) {
			completion(values, fetched);
		}];
	}];
}

/* A correlated join's objects: those with the page's values, or (no page)
 * all of them. */
- (void)readJoin:(ORMQueryODataJoin *)join
            page:(NSArray<NSDictionary *> *)page
      completion:(void (^)(NSArray *objects, NSError *error))completion
{
	NSError *error = nil;
	ODataMutableQueryOptions *options = [join.options mutableCopy];
	if (page != nil) {
		ODataExpression *narrowed = [_request join:join filterFor:page error:&error];
		if (narrowed == nil) {
			/* None of the page's values: none of them. */
			completion(error == nil ? @[] : nil, error);
			return;
		}
		options.filter = options.filter != nil ? [ODataExpression binary:@"and" left:options.filter right:narrowed error:&error]
		                                       : narrowed;
		if (options.filter == nil) {
			completion(nil, error);
			return;
		}
	}
	NSURL *url = [self URLFor:join.collectionPath options:options error:&error];
	if (url == nil) {
		completion(nil, error);
		return;
	}
	NSMutableArray *found = [NSMutableArray array];
	[self all:url into:found completion:^(NSError *fetched) {
		if (fetched != nil) {
			completion(nil, fetched);
			return;
		}
		NSMutableArray *objects = [NSMutableArray array];
		for (NSDictionary *json in found) {
			[objects addObject:ORMODataObjectOf(json, join.entity)];
		}
		completion(objects, nil);
	}];
}

/* A bag's rows: those of the page's groups, or (no page) all of them. */
- (void)readBag:(NSString *)name
           page:(NSArray<NSDictionary *> *)page
     completion:(void (^)(NSArray *rows, NSError *error))completion
{
	ORMQueryODataCursor *cursor = [[_request.bags objectForKey:name] cursorWithTransport:_transport serviceRoot:_root];
	if (cursor == nil) {
		completion(nil, ORMODataError([NSString stringWithFormat:@"%@ is read from nothing the service serves.", name]));
		return;
	}
	if (page != nil) {
		NSError *error = nil;
		cursor.extraFilter = [_request bag:name filterFor:page error:&error];
		if (cursor.extraFilter == nil) {
			/* No group: none of its rows. */
			completion(error == nil ? @[] : nil, error);
			return;
		}
	}
	NSMutableArray *rows = [NSMutableArray array];
	__block void (^more)(void) = nil;
	more = ^{
		[cursor nextPage:256 completion:^(ORMQueryResult *read, NSError *error) {
			if (read == nil) {
				more = nil;
				completion(nil, error);
				return;
			}
			[rows addObjectsFromArray:read.rows];
			if (![cursor atEnd]) {
				more();
				return;
			}
			completion(rows, nil);
			more = nil;
		}];
	};
	more();
}

/* The rows of the page that a page join keeps: one request for the joined
 * objects' parts, grouped, among the page's values. */
- (void)keep:(NSArray *)rows join:(ORMQueryODataJoin *)join completion:(void (^)(NSArray *kept, NSError *error))completion
{
	NSMutableOrderedSet *tuples = [NSMutableOrderedSet orderedSet];
	for (NSDictionary *row in rows) {
		NSMutableArray *tuple = [NSMutableArray array];
		for (NSArray *pair in join.pairs) {
			[tuple addObject:[ORMJSONValues(row, [pair firstObject]) firstObject]];
		}
		[tuples addObject:tuple];
	}
	if ([tuples count] == 0) {
		completion(@[], nil);
		return;
	}
	NSError *error = nil;
	ODataExpression *any = nil;
	for (NSArray *tuple in tuples) {
		ODataExpression *all = nil;
		for (NSUInteger i = 0; i < [join.pairs count] && error == nil; i++) {
			ODataExpression *path = [ODataExpression memberPath:[[join.pairs objectAtIndex:i] lastObject] of:nil error:&error];
			ODataExpression *equal = path != nil ? [ODataExpression binary:@"eq" left:path
			                                                         right:[ODataExpression literalWithValue:[tuple objectAtIndex:i]]
			                                                         error:&error]
			                                     : nil;
			all = all != nil && equal != nil ? [ODataExpression binary:@"and" left:all right:equal error:&error] : equal;
		}
		any = any != nil && all != nil ? [ODataExpression binary:@"or" left:any right:all error:&error] : all;
	}
	ODataExpression *filter = join.joinedFilter != nil && any != nil
		? [ODataExpression binary:@"and" left:join.joinedFilter right:any error:&error] : any;
	if (join.check != nil) {
		[self keep:rows join:join filter:filter completion:completion];
		return;
	}
	NSMutableArray *paths = [NSMutableArray array];
	for (NSArray *pair in join.pairs) {
		[paths addObject:[pair lastObject]];
	}
	ODataApplyTransformation *keep = filter != nil ? [ODataApplyTransformation filterWithExpression:filter] : nil;
	ODataApplyTransformation *group = keep != nil ? [ODataApplyTransformation groupByPaths:paths aggregates:@[] error:&error] : nil;
	if (group == nil) {
		completion(nil, error);
		return;
	}
	ODataMutableQueryOptions *options = [[ODataMutableQueryOptions alloc] init];
	options.apply = @[ keep, group ];
	NSURL *url = [self URLFor:join.collectionPath options:options error:&error];
	if (url == nil) {
		completion(nil, error);
		return;
	}
	NSMutableArray *found = [NSMutableArray array];
	[self all:url into:found completion:^(NSError *fetched) {
		if (fetched != nil) {
			completion(nil, fetched);
			return;
		}
		NSMutableSet *theirs = [NSMutableSet set];
		for (NSDictionary *row in found) {
			NSMutableArray *tuple = [NSMutableArray array];
			for (NSArray *pair in join.pairs) {
				[tuple addObject:[ORMJSONValues(row, [pair lastObject]) firstObject]];
			}
			[theirs addObject:tuple];
		}
		NSMutableArray *kept = [NSMutableArray array];
		for (NSDictionary *row in rows) {
			NSMutableArray *tuple = [NSMutableArray array];
			for (NSArray *pair in join.pairs) {
				[tuple addObject:[ORMJSONValues(row, [pair firstObject]) firstObject]];
			}
			if ([theirs containsObject:tuple]) {
				[kept addObject:row];
			}
		}
		completion(kept, nil);
	}];
}

/* The rows a page join with a check keeps: the joined objects among the
 * page's values read whole enough, and each row kept where one of them
 * has its values and meets the check, the row's object bound. */
- (void)keep:(NSArray *)rows join:(ORMQueryODataJoin *)join filter:(ODataExpression *)filter
  completion:(void (^)(NSArray *kept, NSError *error))completion
{
	ODataMutableQueryOptions *options = [join.rowOptions mutableCopy];
	options.filter = filter;
	NSError *error = nil;
	NSURL *url = [self URLFor:join.collectionPath options:options error:&error];
	if (url == nil) {
		completion(nil, error);
		return;
	}
	NSMutableArray *found = [NSMutableArray array];
	[self all:url into:found completion:^(NSError *fetched) {
		if (fetched != nil) {
			completion(nil, fetched);
			return;
		}
		ORMODataRows *checker = [[ORMODataRows alloc] initWithPlan:nil read:join.entity mapper:self->_mapper];
		NSEntityDescription *read = [self->_request readEntity];
		NSMutableArray *kept = [NSMutableArray array];
		for (NSDictionary *row in rows) {
			NSMutableArray *ours = [NSMutableArray array];
			for (NSArray *pair in join.pairs) {
				[ours addObject:[ORMJSONValues(row, [pair firstObject]) firstObject]];
			}
			ORMODataObject *object = ORMODataObjectOf(row, read);
			for (NSDictionary *theirs in found) {
				NSMutableArray *tuple = [NSMutableArray array];
				for (NSArray *pair in join.pairs) {
					[tuple addObject:[ORMJSONValues(theirs, [pair lastObject]) firstObject]];
				}
				if ([tuple isEqualToArray:ours]
				    && [checker holds:join.check object:ORMODataObjectOf(theirs, join.entity) bindings:@{ join.outer: object }]) {
					[kept addObject:row];
					break;
				}
			}
		}
		completion(kept, nil);
	}];
}

/* The cursors reading the request: its objects a page at a time, the
 * page joins' semijoins, each bag and correlated join read for each batch
 * (or once, whole), and its checks (docs/CURSORS.md). */
- (id<ORMCursor>)cursor
{
	__weak ORMQueryODataCursor *weakSelf = self;
	ORMODataScan *scan = [[ORMODataScan alloc] init];
	scan.cursor = self;
	scan.request = _request;
	id<ORMCursor> cursor = scan;
	for (ORMQueryODataJoin *join in _request.pageJoins) {
		ORMODataSemiJoin *semi = [[ORMODataSemiJoin alloc] init];
		semi.input = cursor;
		semi.join = join;
		semi.cursor = self;
		cursor = semi;
	}
	NSArray * (^objects)(ORMBatch *) = ^NSArray *(ORMBatch *batch) {
		return batch.objects;
	};
	for (NSString *name in [[_request.bags allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		cursor = [[ORMBindJoinCursor alloc] initWithInput:cursor name:name
		                                            scope:[_request scopesBag:name] ? objects : nil
		                                             read:^(NSArray *page, void (^done)(id, NSError *)) {
			                                             [weakSelf readBag:name page:page completion:done];
		                                             }];
	}
	for (ORMQueryODataJoin *join in _request.wholeJoins) {
		cursor = [[ORMBindJoinCursor alloc] initWithInput:cursor name:join.name
		                                            scope:join.pageScope != nil ? objects : nil
		                                             read:^(NSArray *page, void (^done)(id, NSError *)) {
			                                             [weakSelf readJoin:join page:page completion:done];
		                                             }];
	}
	return [[ORMFilterCursor alloc] initWithInput:cursor evaluator:_request];
}

- (void)nextPage:(NSUInteger)size completion:(void (^)(ORMQueryResult *page, NSError *error))completion
{
	if (_reader == nil) {
		_reader = [[ORMPageReader alloc] initWithInput:[self cursor] evaluator:_request
		                                  columnTitles:[_request.plan.columns valueForKey:@"title"]];
		_reader.objectsApart = [_request.plan listsTheObjectRead];
		_reader.rowsInOrder = [_request rowsInOrder];
	}
	[_reader nextPage:size completion:completion];
}

@end

@implementation ORMODataScan
{
	NSUInteger _offset;
	BOOL _atEnd;
	/* The last object's values in the seek's order; nil, by offset. */
	NSArray *_last;
	BOOL _byOffset;
}

- (BOOL)atEnd
{
	return _atEnd;
}

- (void)next:(NSUInteger)count completion:(void (^)(ORMBatch *batch, NSError *error))completion
{
	if (_atEnd || count == 0) {
		completion([ORMBatch batchWithObjects:@[] answers:@{}], nil);
		return;
	}
	ORMQueryOData *request = self.request;
	ORMSeek *seek = [request seek];
	if (_last != nil && [seek after:_last] == nil) {
		/* A value of the last is null: read on by offset. */
		_byOffset = YES;
	}
	[self.cursor scan:count offset:_offset after:_byOffset ? nil : _last completion:^(NSArray *values, NSError *error) {
		if (values == nil) {
			completion(nil, error);
			return;
		}
		self->_offset += [values count];
		self->_atEnd = [values count] < count;
		if (seek != nil && [values count] > 0) {
			NSArray *wires = [request seekWire];
			NSMutableArray *last = [NSMutableArray array];
			for (NSArray *wire in wires) {
				[last addObject:[ORMJSONValues([values lastObject], wire) firstObject] ?: [NSNull null]];
			}
			self->_last = last;
		}
		completion([ORMBatch batchWithObjects:values answers:@{}], nil);
	}];
}

@end

@implementation ORMODataSemiJoin

- (BOOL)atEnd
{
	return self.input.atEnd;
}

- (void)next:(NSUInteger)count completion:(void (^)(ORMBatch *batch, NSError *error))completion
{
	[self.input next:count completion:^(ORMBatch *batch, NSError *error) {
		if (batch == nil || [batch.objects count] == 0) {
			completion(batch, error);
			return;
		}
		[self.cursor keep:batch.objects join:self.join completion:^(NSArray *kept, NSError *failed) {
			completion(kept != nil ? [batch batchWithObjects:kept] : nil, failed);
		}];
	}];
}

@end
