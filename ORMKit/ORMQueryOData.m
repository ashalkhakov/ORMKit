/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryOData.h"
#import "ORMQueryPlanner.h"
#import "ORMCDModel+CoreData.h"
#import <CoreData/CoreData.h>
#import <ODataKit/ODataApply.h>
#import <ODataKit/ODataExpression.h>
#import <ODataKit/ODataPropertyMapper.h>
#import <ODataIncrementalStore/ODataQueryBuilder.h>

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

@implementation ORMQueryOData
{
	ORMCDModel *_coreData;
	NSManagedObjectModel *_managed;
	ODataPropertyMapper *_mapper;
	NSEntityDescription *_read;
	NSMutableArray<NSString *> *_notes;
	NSMutableArray<ORMQueryODataJoin *> *_joins;
	/* The first error a builder gave: the request is not made. */
	NSError *_error;
	/* Each variable bound where the lowering is, to what it ranges over,
	 * and the name it is written as ($this in a count's filter). */
	NSMutableDictionary<NSString *, NSEntityDescription *> *_bound;
	NSMutableDictionary<NSString *, NSString *> *_written;
	/* How many lambdas and counts enclose where the lowering is: inside one,
	 * the object read is written $it. */
	NSUInteger _depth;
	NSUInteger _variables;
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
	request->_bound = [NSMutableDictionary dictionary];
	request->_written = [NSMutableDictionary dictionary];
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
			ODataExpression *part = [self lower:operand];
			if (part == nil) {
				return nil;
			}
			[parts addObject:part];
		}
		return [self all:parts connective:condition.kind == ORMPlanAnd ? @"and" : @"or"];
	}
	case ORMPlanNot:
		return [self not:[self lower:condition.operand]];
	case ORMPlanCompare:
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
	join.name = [NSString stringWithFormat:@"join%lu", (unsigned long)[_joins count] + 1];
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

#pragma mark The request

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
	if ([[self keyOf:_read] count] == 0) {
		[self note:[NSString stringWithFormat:@"%@ has no key in OData, so the service does not serve it: map it with "
		                                      @"ServeOData.", _read.name]];
	}
	_filter = _plan.condition != nil ? [self lower:_plan.condition] : nil;
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
		NSArray *keys = column.path.keys;
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
		if (at != nil) {
			NSPropertyDescription *identifier = column.identifierKey != nil
				? [[at propertiesByName] objectForKey:column.identifierKey] : nil;
			if (identifier != nil) {
				[level.select addObject:[self wireOf:identifier]];
			} else {
				level.all = YES;
			}
		}
	}
	return [self level:top into:options];
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
	for (ORMQueryODataJoin *join in _joins) {
		[text appendFormat:@"%@: %@", join.name, ORMRequestLine(join.collectionPath, join.options)];
	}
	if ([_joins count] > 0) {
		[text appendString:@"then, each @join its rows' parts:\n"];
	}
	[text appendString:ORMRequestLine(_collectionPath, _options)];
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
