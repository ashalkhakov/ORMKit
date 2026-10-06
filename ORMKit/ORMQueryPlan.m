/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlan.h"

NSString * const ORMQueryPlanErrorDomain = @"ORMQueryPlanErrorDomain";

/* A name a Core Data model can have, or a variable a plan binds: a letter
 * or underscore, then letters, digits and underscores. */
static BOOL
ORMPlanIsName(id name)
{
	if (![name isKindOfClass:[NSString class]] || [name length] == 0 || [name length] > 128) {
		return NO;
	}
	NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:
		@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"];
	NSMutableCharacterSet *rest = [letters mutableCopy];
	[rest addCharactersInString:@"0123456789"];
	return [letters characterIsMember:[name characterAtIndex:0]] && [[name stringByTrimmingCharactersInSet:rest] length] == 0;
}

static NSArray *
ORMPlanComparisons(void)
{
	return @[ @"=", @"<>", @"<", @"<=", @">", @">=" ];
}

static NSArray *
ORMPlanFunctions(void)
{
	return @[ @"sum", @"average", @"max", @"min" ];
}

static NSArray *
ORMPlanKindNames(void)
{
	return @[ @"all", @"any", @"not", @"compare", @"notNull", @"exists", @"count", @"aggregate", @"isOf", @"same", @"among",
	          @"matches", @"maybe" ];
}

#pragma mark Steps and paths

@implementation ORMPlanStep

+ (instancetype)stepWithKey:(NSString *)key
{
	ORMPlanStep *step = [[self alloc] init];
	step->_key = [key copy];
	return step;
}

+ (instancetype)stepAsEntity:(NSString *)entityName
{
	ORMPlanStep *step = [[self alloc] init];
	step->_entityName = [entityName copy];
	return step;
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[ORMPlanStep class]] && [[self description] isEqualToString:[other description]];
}

- (NSUInteger)hash
{
	return [[self description] hash];
}

- (NSString *)description
{
	return _key != nil ? _key : [NSString stringWithFormat:@"(%@)", _entityName];
}

@end

@implementation ORMPlanPath

+ (instancetype)pathFrom:(NSString *)variable steps:(NSArray<ORMPlanStep *> *)steps
{
	ORMPlanPath *path = [[self alloc] init];
	path->_variable = [variable copy];
	path->_steps = [steps copy] ?: @[];
	return path;
}

+ (instancetype)pathFrom:(NSString *)variable keys:(NSArray<NSString *> *)keys
{
	NSMutableArray *steps = [NSMutableArray array];
	for (NSString *key in keys) {
		[steps addObject:[ORMPlanStep stepWithKey:key]];
	}
	return [self pathFrom:variable steps:steps];
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

- (NSArray<NSString *> *)keys
{
	NSMutableArray *keys = [NSMutableArray array];
	for (ORMPlanStep *step in _steps) {
		if (step.key != nil) {
			[keys addObject:step.key];
		}
	}
	return keys;
}

- (ORMPlanPath *)pathByAddingKey:(NSString *)key
{
	return [ORMPlanPath pathFrom:_variable steps:[_steps arrayByAddingObject:[ORMPlanStep stepWithKey:key]]];
}

- (ORMPlanPath *)pathByAddingCast:(NSString *)entityName
{
	return [ORMPlanPath pathFrom:_variable steps:[_steps arrayByAddingObject:[ORMPlanStep stepAsEntity:entityName]]];
}

- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[ORMPlanPath class]] && [[self description] isEqualToString:[other description]];
}

- (NSUInteger)hash
{
	return [[self description] hash];
}

- (NSString *)description
{
	NSMutableArray *parts = [NSMutableArray array];
	if (_variable != nil) {
		[parts addObject:_variable];
	}
	for (ORMPlanStep *step in _steps) {
		[parts addObject:[step description]];
	}
	return [parts count] > 0 ? [parts componentsJoinedByString:@"."] : @"self";
}

@end

@implementation ORMPlanValue

+ (instancetype)valueAtPath:(ORMPlanPath *)path
{
	ORMPlanValue *value = [[self alloc] init];
	value->_path = path;
	return value;
}

+ (instancetype)constant:(NSString *)text type:(NSString *)attributeType
{
	ORMPlanValue *value = [[self alloc] init];
	value->_text = [text copy] ?: @"";
	value->_attributeType = [attributeType copy] ?: @"String";
	return value;
}

+ (instancetype)aggregate:(NSString *)function
                       of:(NSString *)column
                       in:(ORMPlanDefinition *)bag
                    where:(NSString *)groupColumn
                       is:(ORMPlanPath *)groupPath
{
	ORMPlanValue *value = [[self alloc] init];
	value->_function = [function copy];
	value->_column = [column copy];
	value->_bag = bag;
	value->_groupColumn = [groupColumn copy];
	value->_groupPath = groupPath;
	return value;
}

/* A bag's column's title, by its node. */
static NSString *
ORMColumnTitle(ORMPlanDefinition *bag, NSString *nodeId)
{
	for (ORMPlanColumn *column in bag.plan.columns) {
		if ([column.nodeId isEqualToString:nodeId ?: @""]) {
			return column.title;
		}
	}
	return nodeId;
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

- (NSString *)description
{
	if (_path != nil) {
		return [_path description];
	}
	if (_bag != nil) {
		NSString *of = _column != nil ? [NSString stringWithFormat:@"%@ of %@", _function, ORMColumnTitle(_bag, _column)]
		                              : _function;
		return [NSString stringWithFormat:@"%@ in %@ where %@ is %@", of, _bag.name, ORMColumnTitle(_bag, _groupColumn),
		                                  _groupPath];
	}
	BOOL quoted = [_attributeType isEqualToString:@"String"] || [_attributeType isEqualToString:@"Date"];
	return quoted ? [NSString stringWithFormat:@"'%@'", [_text stringByReplacingOccurrencesOfString:@"'" withString:@"''"]]
	              : _text;
}

@end

#pragma mark Conditions

@interface ORMPlanCondition ()
@property (nonatomic, readwrite) ORMPlanConditionKind kind;
@property (nonatomic, readwrite, copy) NSArray<ORMPlanCondition *> *operands;
@property (nonatomic, readwrite, strong) ORMPlanCondition *operand;
@property (nonatomic, readwrite, strong) ORMPlanValue *left;
@property (nonatomic, readwrite, strong) ORMPlanValue *right;
@property (nonatomic, readwrite, copy) NSString *comparison;
@property (nonatomic, readwrite, strong) ORMPlanPath *path;
@property (nonatomic, readwrite, strong) ORMPlanPath *otherPath;
@property (nonatomic, readwrite, copy) NSString *variable;
@property (nonatomic, readwrite) NSUInteger number;
@property (nonatomic, readwrite, copy) NSString *function;
@property (nonatomic, readwrite, strong) ORMPlanPath *valuePath;
@property (nonatomic, readwrite, strong) ORMPlanValue *constant;
@property (nonatomic, readwrite, copy) NSString *entityName;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *trail;
@property (nonatomic, readwrite, strong) ORMQueryPlan *plan;
@property (nonatomic, readwrite, strong) ORMPlanDefinition *definition;
@property (nonatomic, readwrite, copy) NSArray<NSArray<ORMPlanPath *> *> *pairs;
@property (nonatomic, readwrite, copy) NSString *boundVariable;
@property (nonatomic, readwrite) BOOL isOptional;
@end

@implementation ORMPlanCondition
{
	ORMQueryPlan *_plan;
}

@synthesize definition = _definition;

- (ORMQueryPlan *)plan
{
	return _definition != nil ? _definition.plan : _plan;
}

- (void)setPlan:(ORMQueryPlan *)plan
{
	_plan = plan;
}

+ (instancetype)ofKind:(ORMPlanConditionKind)kind
{
	ORMPlanCondition *condition = [[self alloc] init];
	condition.kind = kind;
	return condition;
}

+ (instancetype)all:(NSArray<ORMPlanCondition *> *)operands
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanAnd];
	condition.operands = operands;
	return condition;
}

+ (instancetype)any:(NSArray<ORMPlanCondition *> *)operands
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanOr];
	condition.operands = operands;
	return condition;
}

+ (instancetype)not:(ORMPlanCondition *)operand
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanNot];
	condition.operand = operand;
	return condition;
}

+ (instancetype)compare:(ORMPlanValue *)left comparison:(NSString *)comparison with:(ORMPlanValue *)right
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanCompare];
	condition.left = left;
	condition.comparison = comparison;
	condition.right = right;
	return condition;
}

+ (instancetype)notNull:(ORMPlanPath *)path
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanNotNull];
	condition.path = path;
	return condition;
}

+ (instancetype)exists:(ORMPlanPath *)collection variable:(NSString *)variable where:(ORMPlanCondition *)operand
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanExists];
	condition.path = collection;
	condition.variable = variable;
	condition.operand = operand;
	return condition;
}

+ (instancetype)maybe:(ORMPlanPath *)collection variable:(NSString *)variable where:(ORMPlanCondition *)operand
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanMaybe];
	condition.path = collection;
	condition.variable = variable;
	condition.operand = operand;
	return condition;
}

+ (instancetype)count:(ORMPlanPath *)collection variable:(NSString *)variable where:(ORMPlanCondition *)operand
           comparison:(NSString *)comparison number:(NSUInteger)number
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanCount];
	condition.path = collection;
	condition.variable = variable;
	condition.operand = operand;
	condition.comparison = comparison;
	condition.number = number;
	return condition;
}

+ (instancetype)aggregate:(NSString *)function
                       of:(ORMPlanPath *)valuePath
                     over:(ORMPlanPath *)collection
                 variable:(NSString *)variable
                    where:(ORMPlanCondition *)operand
               comparison:(NSString *)comparison
                 constant:(ORMPlanValue *)constant
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanAggregate];
	condition.function = function;
	condition.valuePath = valuePath;
	condition.path = collection;
	condition.variable = variable;
	condition.operand = operand;
	condition.comparison = comparison;
	condition.constant = constant;
	return condition;
}

+ (instancetype)isOf:(ORMPlanPath *)path entity:(NSString *)entityName
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanIsOf];
	condition.path = path;
	condition.entityName = entityName;
	return condition;
}

+ (instancetype)same:(ORMPlanPath *)path as:(ORMPlanPath *)otherPath
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanSame];
	condition.path = path;
	condition.otherPath = otherPath;
	return condition;
}

+ (instancetype)among:(ORMPlanPath *)path trail:(NSArray<NSString *> *)keys
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanAmong];
	condition.path = path;
	condition.trail = keys;
	return condition;
}

+ (instancetype)matches:(ORMQueryPlan *)plan pairs:(NSArray<NSArray<ORMPlanPath *> *> *)pairs
{
	return [self matches:plan pairs:pairs outer:nil];
}

+ (instancetype)matches:(ORMQueryPlan *)plan pairs:(NSArray<NSArray<ORMPlanPath *> *> *)pairs outer:(NSString *)variable
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanMatches];
	condition.plan = plan;
	condition.pairs = pairs;
	condition.variable = variable;
	return condition;
}

+ (instancetype)matchesDefinition:(ORMPlanDefinition *)definition
                            pairs:(NSArray<NSArray<ORMPlanPath *> *> *)pairs
                            outer:(NSString *)variable
{
	ORMPlanCondition *condition = [self ofKind:ORMPlanMatches];
	condition.definition = definition;
	condition.pairs = pairs;
	condition.variable = variable;
	return condition;
}

+ (instancetype)matchesDefinition:(ORMPlanDefinition *)definition
                            pairs:(NSArray<NSArray<ORMPlanPath *> *> *)pairs
                          binding:(NSString *)variable
                            where:(ORMPlanCondition *)condition
                         optional:(BOOL)optional
{
	ORMPlanCondition *matches = [self matchesDefinition:definition pairs:pairs outer:nil];
	matches.boundVariable = variable;
	matches.operand = condition;
	matches.isOptional = optional;
	return matches;
}

+ (instancetype)among:(ORMPlanPath *)path trail:(NSArray<NSString *> *)keys from:(ORMPlanPath *)base
{
	ORMPlanCondition *condition = [self among:path trail:keys];
	condition.otherPath = base;
	return condition;
}

static void
ORMAddVariable(NSMutableSet *set, ORMPlanPath *path)
{
	if (path.variable != nil) {
		[set addObject:path.variable];
	}
}

- (NSSet<NSString *> *)freeVariables
{
	NSMutableSet *free = [NSMutableSet set];
	for (ORMPlanCondition *operand in self.operands) {
		[free unionSet:[operand freeVariables]];
	}
	ORMAddVariable(free, self.path);
	ORMAddVariable(free, self.otherPath);
	ORMAddVariable(free, self.left.path);
	ORMAddVariable(free, self.right.path);
	ORMAddVariable(free, self.left.groupPath);
	ORMAddVariable(free, self.right.groupPath);
	for (NSArray *pair in self.pairs) {
		ORMAddVariable(free, [pair firstObject]);
	}
	if (self.kind == ORMPlanMatches) {
		/* The plan's own: what it names of this one, but its outer name. */
		NSMutableSet *inner = [NSMutableSet setWithSet:[self.plan.condition freeVariables] ?: [NSSet set]];
		if (self.variable != nil) {
			[inner removeObject:self.variable];
		}
		[free unionSet:inner];
		/* What is asked of the object it binds. */
		NSMutableSet *bound = [NSMutableSet setWithSet:[self.operand freeVariables] ?: [NSSet set]];
		if (self.boundVariable != nil) {
			[bound removeObject:self.boundVariable];
		}
		[free unionSet:bound];
		return free;
	}
	if (self.operand != nil) {
		NSMutableSet *inner = [NSMutableSet setWithSet:[self.operand freeVariables]];
		ORMAddVariable(inner, self.valuePath);
		if (self.kind != ORMPlanNot && self.variable != nil) {
			[inner removeObject:self.variable];
		}
		[free unionSet:inner];
	}
	return free;
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

- (BOOL)isCompound
{
	return self.kind == ORMPlanAnd || self.kind == ORMPlanOr;
}

- (NSString *)wrapped
{
	return [self isCompound] ? [NSString stringWithFormat:@"(%@)", self] : [self description];
}

- (NSString *)description
{
	switch (self.kind) {
	case ORMPlanAnd:
	case ORMPlanOr: {
		NSMutableArray *parts = [NSMutableArray array];
		for (ORMPlanCondition *operand in self.operands) {
			[parts addObject:[operand wrapped]];
		}
		return [parts componentsJoinedByString:self.kind == ORMPlanAnd ? @" and " : @" or "];
	}
	case ORMPlanNot:
		return [NSString stringWithFormat:@"not (%@)", self.operand];
	case ORMPlanCompare:
		return [NSString stringWithFormat:@"%@ %@ %@", self.left, self.comparison, self.right];
	case ORMPlanNotNull:
		return [NSString stringWithFormat:@"%@ is set", self.path];
	case ORMPlanExists:
		return self.operand != nil ? [NSString stringWithFormat:@"some %@ as %@ has %@", self.path, self.variable,
		                                                       [self.operand wrapped]]
		                           : [NSString stringWithFormat:@"some %@", self.path];
	case ORMPlanMaybe:
		return self.operand != nil ? [NSString stringWithFormat:@"maybe %@ as %@ has %@", self.path, self.variable,
		                                                       [self.operand wrapped]]
		                           : [NSString stringWithFormat:@"maybe %@ as %@", self.path, self.variable];
	case ORMPlanCount:
		return self.operand != nil ? [NSString stringWithFormat:@"number of %@ as %@ having %@ %@ %lu", self.path,
		                                                       self.variable, [self.operand wrapped], self.comparison,
		                                                       (unsigned long)self.number]
		                           : [NSString stringWithFormat:@"number of %@ %@ %lu", self.path, self.comparison,
		                                                       (unsigned long)self.number];
	case ORMPlanAggregate:
		return [NSString stringWithFormat:@"%@ of %@ over %@ as %@%@ %@ %@", self.function, self.valuePath, self.path,
		                                  self.variable,
		                                  self.operand != nil ? [@" having " stringByAppendingString:[self.operand wrapped]] : @"",
		                                  self.comparison, self.constant];
	case ORMPlanIsOf:
		return [NSString stringWithFormat:@"%@ is a %@", self.path, self.entityName];
	case ORMPlanSame:
		return [NSString stringWithFormat:@"%@ is %@", self.path, self.otherPath];
	case ORMPlanAmong: {
		NSMutableArray *trail = [NSMutableArray array];
		if (self.otherPath != nil) {
			[trail addObject:[self.otherPath description]];
		}
		[trail addObjectsFromArray:self.trail ?: @[]];
		return [NSString stringWithFormat:@"%@ is among %@", self.path,
		                                  [trail count] > 0 ? [trail componentsJoinedByString:@"."] : @"self"];
	}
	case ORMPlanMatches: {
		NSMutableArray *pairs = [NSMutableArray array];
		for (NSArray *pair in self.pairs) {
			[pairs addObject:[NSString stringWithFormat:@"%@ = %@", [pair firstObject], [pair lastObject]]];
		}
		if (self.boundVariable != nil) {
			return [NSString stringWithFormat:@"%@ %@ in %@ with %@%@", self.isOptional ? @"maybe" : @"some",
			                                  self.boundVariable, self.definition.name ?: @"[a plan]",
			                                  [pairs componentsJoinedByString:@", "],
			                                  self.operand != nil ? [@" has " stringByAppendingString:[self.operand wrapped]]
			                                                      : @""];
		}
		if (self.definition != nil) {
			return [NSString stringWithFormat:@"%@ in %@%@", [pairs componentsJoinedByString:@", "], self.definition.name,
			                                  self.variable != nil ? [NSString stringWithFormat:@" (%@ is this)", self.variable]
			                                                       : @""];
		}
		return [NSString stringWithFormat:@"%@ match [%@%@]", [pairs componentsJoinedByString:@", "],
		                                  self.variable != nil ? [NSString stringWithFormat:@"%@ is this; ", self.variable] : @"",
		                                  [[[self.plan text] componentsSeparatedByString:@"\n"] componentsJoinedByString:@"; "]];
	}
	}
	return @"";
}

@end

#pragma mark Definitions

@implementation ORMPlanDefinition

+ (instancetype)definitionNamed:(NSString *)name plan:(ORMQueryPlan *)plan
{
	ORMPlanDefinition *definition = [[self alloc] init];
	definition->_name = [name copy];
	definition->_plan = plan;
	return definition;
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

- (NSArray<NSString *> *)parameters
{
	NSSet *free = [_plan.condition freeVariables] ?: [NSSet set];
	return [[free allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

/* "let join1 = read Branch where nr = 52"; with its parameters,
 * "let join1(o1) = ...". */
- (NSString *)description
{
	NSArray *parameters = [self parameters];
	return [NSString stringWithFormat:@"let %@%@ = %@", _name,
	                                  [parameters count] > 0 ? [NSString stringWithFormat:@"(%@)",
	                                                                                      [parameters componentsJoinedByString:@", "]]
	                                                         : @"",
	                                  [[[_plan text] componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "]];
}

@end

#pragma mark Columns, sorts, plans

@implementation ORMPlanColumn

+ (instancetype)columnTitled:(NSString *)title
                        node:(NSString *)nodeId
                        path:(ORMPlanPath *)path
                       trail:(NSArray<NSString *> *)trail
                  identifier:(NSString *)identifierKey
{
	ORMPlanColumn *column = [[self alloc] init];
	column->_title = [title copy];
	column->_nodeId = [nodeId copy];
	column->_path = path;
	column->_trail = [trail copy] ?: path.keys;
	column->_identifierKey = [identifierKey copy];
	return column;
}

+ (instancetype)columnTitled:(NSString *)title node:(NSString *)nodeId path:(ORMPlanPath *)path
                  identifier:(NSString *)identifierKey
{
	return [self columnTitled:title node:nodeId path:path trail:path.keys identifier:identifierKey];
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

+ (instancetype)columnTitled:(NSString *)title node:(NSString *)nodeId value:(ORMPlanValue *)value
{
	ORMPlanColumn *column = [[self alloc] init];
	column->_title = [title copy];
	column->_nodeId = [nodeId copy];
	column->_value = value;
	return column;
}

- (ORMPlanPath *)valuePath
{
	if (_value != nil) {
		return nil;
	}
	return _identifierKey != nil ? [_path pathByAddingKey:_identifierKey] : _path;
}

- (id)valueOf:(id)object at:(id (^)(id object, NSArray<NSString *> *keys))valueAt
{
	if ([_identifierParts count] == 0 || object == nil || object == [NSNull null]) {
		return object;
	}
	NSMutableArray *values = [NSMutableArray array];
	for (NSArray *keys in _identifierParts) {
		[values addObject:valueAt(object, keys) ?: [NSNull null]];
	}
	return values;
}

- (NSString *)description
{
	if (_value != nil) {
		return [_value description];
	}
	if ([_identifierParts count] > 0) {
		NSMutableArray *parts = [NSMutableArray array];
		for (NSArray *keys in _identifierParts) {
			[parts addObject:[keys componentsJoinedByString:@"."]];
		}
		return [NSString stringWithFormat:@"%@ (%@)", _path, [parts componentsJoinedByString:@", "]];
	}
	return _identifierKey != nil ? [NSString stringWithFormat:@"%@ (%@)", _path, _identifierKey] : [_path description];
}

@end

@implementation ORMPlanSort

+ (instancetype)sortBy:(ORMPlanPath *)path ascending:(BOOL)ascending
{
	ORMPlanSort *sort = [[self alloc] init];
	sort->_path = path;
	sort->_ascending = ascending;
	return sort;
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ %@", _path, _ascending ? @"ascending" : @"descending"];
}

@end

@interface ORMQueryPlan ()
/* The definitions visible: those of the plans it is in, by name. */
+ (instancetype)readPlan:(id)list defined:(NSDictionary<NSString *, ORMPlanDefinition *> *)defined
                   error:(NSError **)reason;
@end

@implementation ORMQueryPlan

/* Each column's value as a key path from the object read; nil where one
 * is a variable's. */
- (NSArray<NSArray<NSString *> *> *)listedPaths
{
	NSMutableArray *listed = [NSMutableArray array];
	for (ORMPlanColumn *column in self.columns) {
		if (column.value != nil) {
			/* Computed of the object read: listed with it, or not at all. */
			continue;
		}
		if (column.path.variable != nil) {
			return nil;
		}
		NSArray *keys = column.trail ?: @[];
		NSArray *path = column.identifierKey != nil ? [keys arrayByAddingObject:column.identifierKey] : keys;
		if (![listed containsObject:path]) {
			[listed addObject:path];
		}
	}
	return listed;
}

static BOOL
ORMHasPrefix(NSArray *path, NSArray *prefix)
{
	return [path count] >= [prefix count] && [[path subarrayWithRange:NSMakeRange(0, [prefix count])] isEqualToArray:prefix];
}

- (BOOL)rowsFollowOrder:(NSArray<NSArray<NSString *> *> *)order key:(NSArray<NSString *> *)key
{
	NSArray *listed = [self listedPaths];
	if ([listed count] == 0) {
		return NO;
	}
	/* The objects the rows list by their identifiers: @[ trail, identifier ]. */
	NSMutableArray *identified = [NSMutableArray array];
	for (ORMPlanColumn *column in self.columns) {
		if (column.identifierKey != nil) {
			[identified addObject:@[ column.trail ?: @[], column.identifierKey ]];
		}
	}
	/* Whether a path is a function of the rows: listed, or reached from a
	 * listed object through to-ones. */
	BOOL (^byRows)(NSArray *) = ^BOOL(NSArray *path) {
		if ([listed containsObject:path]) {
			return YES;
		}
		for (NSArray *object in identified) {
			if (ORMHasPrefix(path, [object firstObject]) && [path count] > [[object firstObject] count]) {
				return YES;
			}
		}
		return NO;
	};
	NSMutableArray *prefix = [NSMutableArray array];
	for (NSArray *part in order) {
		if (!byRows(part)) {
			/* The rows do not say where they are in the order. */
			return NO;
		}
		[prefix addObject:part];
		/* Whether the prefix determines every column: each in it, reached
		 * from an object it identifies, or the whole key in it. */
		BOOL whole = [key count] > 0;
		for (NSString *each in key) {
			whole = whole && [prefix containsObject:@[ each ]];
		}
		BOOL determined = YES;
		for (NSArray *path in listed) {
			BOOL one = whole || [prefix containsObject:path];
			for (NSArray *object in identified) {
				NSArray *identifier = [[object firstObject] arrayByAddingObject:[object lastObject]];
				one = one || ([prefix containsObject:identifier] && ORMHasPrefix(path, [object firstObject]));
			}
			determined = determined && one;
		}
		if (determined) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)ordersItsRows
{
	NSMutableArray *order = [NSMutableArray array];
	for (ORMPlanSort *sort in self.sorts) {
		[order addObject:sort.path.keys];
	}
	return [self rowsFollowOrder:order key:nil];
}

/* The keys a path reads from the object read: its variable's collection's
 * first. nil where its variable is bound nowhere this walk sees. */
static NSArray<NSString *> *
ORMTrailOf(ORMPlanPath *path, NSDictionary<NSString *, NSArray *> *bound)
{
	if (path == nil) {
		return nil;
	}
	if (path.variable == nil) {
		return path.keys;
	}
	NSArray *base = [bound objectForKey:path.variable];
	return base != nil ? [base arrayByAddingObjectsFromArray:path.keys] : nil;
}

/* What the condition reads, into trails; NO where it reads what no path
 * says. */
static BOOL
ORMCollectTrails(ORMPlanCondition *condition, NSDictionary *bound, NSMutableSet *trails)
{
	if (condition == nil) {
		return YES;
	}
	BOOL ok = YES;
	void (^add)(ORMPlanPath *) = ^(ORMPlanPath *path) {
		NSArray *trail = ORMTrailOf(path, bound);
		if (path != nil && trail == nil) {
			return;
		}
		if ([trail count] > 0) {
			[trails addObject:trail];
		}
	};
	switch (condition.kind) {
	case ORMPlanAnd:
	case ORMPlanOr:
		for (ORMPlanCondition *operand in condition.operands) {
			ok = ORMCollectTrails(operand, bound, trails) && ok;
		}
		return ok;
	case ORMPlanNot:
		return ORMCollectTrails(condition.operand, bound, trails);
	case ORMPlanCompare:
		if (condition.left.bag != nil || condition.right.bag != nil) {
			return NO;
		}
		add(condition.left.path);
		add(condition.right.path);
		return YES;
	case ORMPlanNotNull:
	case ORMPlanIsOf:
		add(condition.path);
		return YES;
	case ORMPlanSame:
		add(condition.path);
		add(condition.otherPath);
		return YES;
	case ORMPlanAmong:
		add(condition.path);
		return YES;
	case ORMPlanExists:
	case ORMPlanCount:
	case ORMPlanAggregate:
	case ORMPlanMaybe: {
		NSArray *collection = ORMTrailOf(condition.path, bound);
		if (collection == nil) {
			return NO;
		}
		[trails addObject:collection];
		NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bound];
		if (condition.variable != nil) {
			[inner setObject:collection forKey:condition.variable];
		}
		if (condition.valuePath != nil) {
			NSArray *value = ORMTrailOf(condition.valuePath, inner);
			if ([value count] > 0) {
				[trails addObject:value];
			}
		}
		return ORMCollectTrails(condition.operand, inner, trails);
	}
	case ORMPlanMatches:
		return NO;
	}
	return NO;
}

/* The variables bound where the condition binds them, to their trails. */
static void
ORMBindings(ORMPlanCondition *condition, NSDictionary *bound, NSMutableDictionary *all)
{
	if (condition == nil) {
		return;
	}
	NSMutableDictionary *inner = [NSMutableDictionary dictionaryWithDictionary:bound];
	if (condition.variable != nil && condition.kind != ORMPlanMatches) {
		NSArray *collection = ORMTrailOf(condition.path, bound);
		if (collection != nil) {
			[inner setObject:collection forKey:condition.variable];
			[all setObject:collection forKey:condition.variable];
		}
	}
	for (ORMPlanCondition *operand in condition.operands) {
		ORMBindings(operand, inner, all);
	}
	ORMBindings(condition.operand, inner, all);
}

- (NSArray<NSArray<NSString *> *> *)trailsFromRead
{
	NSMutableSet *trails = [NSMutableSet set];
	if (!ORMCollectTrails(self.condition, @{}, trails) || [self.definitions count] > 0) {
		return nil;
	}
	for (ORMPlanColumn *column in self.columns) {
		if (column.value != nil) {
			return nil;
		}
		NSArray *trail = [self trailOfColumn:column];
		if (trail == nil) {
			return nil;
		}
		if ([trail count] > 0) {
			[trails addObject:trail];
		}
	}
	return [[trails allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		return [[a componentsJoinedByString:@"."] compare:[b componentsJoinedByString:@"."]];
	}];
}

- (ORMPlanColumn *)columnOfNode:(NSString *)nodeId
{
	for (ORMPlanColumn *column in self.columns) {
		if ([column.nodeId isEqualToString:nodeId]) {
			return column;
		}
	}
	return nil;
}

- (NSArray<NSString *> *)trailOfColumn:(ORMPlanColumn *)column
{
	if (column.value != nil || column.path == nil) {
		return nil;
	}
	NSMutableDictionary *bound = [NSMutableDictionary dictionary];
	ORMBindings(self.condition, @{}, bound);
	return ORMTrailOf(column.path, bound);
}

- (BOOL)listsTheObjectRead
{
	for (ORMPlanColumn *column in self.columns) {
		if (column.value == nil && column.path.variable == nil && [column.path.keys count] == 0) {
			return YES;
		}
	}
	return NO;
}

+ (instancetype)planReading:(NSString *)entityName
                      where:(ORMPlanCondition *)condition
                    columns:(NSArray<ORMPlanColumn *> *)columns
                      sorts:(NSArray<ORMPlanSort *> *)sorts
                      notes:(NSArray<NSString *> *)notes
{
	return [self planReading:entityName where:condition columns:columns sorts:sorts notes:notes definitions:@[]];
}

+ (instancetype)planReading:(NSString *)entityName
                      where:(ORMPlanCondition *)condition
                    columns:(NSArray<ORMPlanColumn *> *)columns
                      sorts:(NSArray<ORMPlanSort *> *)sorts
                      notes:(NSArray<NSString *> *)notes
                definitions:(NSArray<ORMPlanDefinition *> *)definitions
{
	ORMQueryPlan *plan = [[self alloc] init];
	plan->_definitions = [definitions copy] ?: @[];
	plan->_entityName = [entityName copy];
	plan->_condition = condition;
	plan->_columns = [columns copy] ?: @[];
	plan->_sorts = [sorts copy] ?: @[];
	plan->_notes = [notes copy] ?: @[];
	return plan;
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return self;
}

- (NSString *)text
{
	if (_entityName == nil) {
		return @"read nothing";
	}
	NSMutableArray *lines = [NSMutableArray arrayWithArray:[_definitions valueForKey:@"description"]];
	[lines addObject:[@"read " stringByAppendingString:_entityName]];
	if (_condition != nil) {
		[lines addObject:[@"where " stringByAppendingString:[_condition description]]];
	}
	if ([_columns count] > 0) {
		[lines addObject:[@"list " stringByAppendingString:[[_columns valueForKey:@"description"] componentsJoinedByString:@", "]]];
	}
	if ([_sorts count] > 0) {
		[lines addObject:[@"order by " stringByAppendingString:[[_sorts valueForKey:@"description"] componentsJoinedByString:@", "]]];
	}
	return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)description
{
	return [self text];
}

#pragma mark Property lists

static id
ORMPathList(ORMPlanPath *path)
{
	NSMutableArray *steps = [NSMutableArray array];
	for (ORMPlanStep *step in path.steps) {
		[steps addObject:step.key != nil ? @{ @"key": step.key } : @{ @"as": step.entityName }];
	}
	NSMutableDictionary *list = [NSMutableDictionary dictionaryWithObject:steps forKey:@"steps"];
	if (path.variable != nil) {
		[list setObject:path.variable forKey:@"variable"];
	}
	return list;
}

static id ORMConditionList(ORMPlanCondition *condition);

static id
ORMValueList(ORMPlanValue *value)
{
	if (value.bag != nil) {
		NSMutableDictionary *list = [NSMutableDictionary dictionaryWithObjectsAndKeys:value.function, @"aggregate",
		                                                 value.bag.name, @"in", value.groupColumn ?: @"", @"where",
		                                                 ORMPathList(value.groupPath), @"is", nil];
		if (value.column != nil) {
			[list setObject:value.column forKey:@"of"];
		}
		return list;
	}
	return value.path != nil ? @{ @"path": ORMPathList(value.path) }
	                         : @{ @"constant": value.text, @"type": value.attributeType };
}

static id
ORMConditionList(ORMPlanCondition *condition)
{
	NSMutableDictionary *list = [NSMutableDictionary dictionary];
	[list setObject:[ORMPlanKindNames() objectAtIndex:(NSUInteger)condition.kind] forKey:@"kind"];
	if (condition.operands != nil) {
		NSMutableArray *operands = [NSMutableArray array];
		for (ORMPlanCondition *operand in condition.operands) {
			[operands addObject:ORMConditionList(operand)];
		}
		[list setObject:operands forKey:@"operands"];
	}
	if (condition.operand != nil) {
		[list setObject:ORMConditionList(condition.operand) forKey:@"operand"];
	}
	if (condition.left != nil) {
		[list setObject:ORMValueList(condition.left) forKey:@"left"];
	}
	if (condition.right != nil) {
		[list setObject:ORMValueList(condition.right) forKey:@"right"];
	}
	if (condition.comparison != nil) {
		[list setObject:condition.comparison forKey:@"comparison"];
	}
	if (condition.path != nil) {
		[list setObject:ORMPathList(condition.path) forKey:@"path"];
	}
	if (condition.otherPath != nil) {
		[list setObject:ORMPathList(condition.otherPath) forKey:@"otherPath"];
	}
	if (condition.variable != nil) {
		[list setObject:condition.variable forKey:@"variable"];
	}
	if (condition.kind == ORMPlanCount) {
		[list setObject:@(condition.number) forKey:@"number"];
	}
	if (condition.function != nil) {
		[list setObject:condition.function forKey:@"function"];
	}
	if (condition.valuePath != nil) {
		[list setObject:ORMPathList(condition.valuePath) forKey:@"valuePath"];
	}
	if (condition.constant != nil) {
		[list setObject:ORMValueList(condition.constant) forKey:@"constant"];
	}
	if (condition.entityName != nil) {
		[list setObject:condition.entityName forKey:@"entity"];
	}
	if (condition.trail != nil) {
		[list setObject:condition.trail forKey:@"trail"];
	}
	if (condition.definition != nil) {
		[list setObject:condition.definition.name forKey:@"definition"];
	} else if (condition.plan != nil) {
		[list setObject:[condition.plan propertyList] forKey:@"plan"];
	}
	if (condition.pairs != nil) {
		NSMutableArray *pairs = [NSMutableArray array];
		for (NSArray *pair in condition.pairs) {
			[pairs addObject:@[ ORMPathList([pair firstObject]), ORMPathList([pair lastObject]) ]];
		}
		[list setObject:pairs forKey:@"pairs"];
	}
	if (condition.boundVariable != nil) {
		[list setObject:condition.boundVariable forKey:@"binding"];
	}
	if (condition.isOptional) {
		[list setObject:@YES forKey:@"optional"];
	}
	return list;
}

- (id)propertyList
{
	NSMutableDictionary *list = [NSMutableDictionary dictionary];
	if ([_definitions count] > 0) {
		NSMutableArray *definitions = [NSMutableArray array];
		for (ORMPlanDefinition *definition in _definitions) {
			[definitions addObject:@{ @"name": definition.name, @"plan": [definition.plan propertyList] }];
		}
		[list setObject:definitions forKey:@"definitions"];
	}
	if (_entityName != nil) {
		[list setObject:_entityName forKey:@"entity"];
	}
	if (_condition != nil) {
		[list setObject:ORMConditionList(_condition) forKey:@"condition"];
	}
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMPlanColumn *column in _columns) {
		if (column.value != nil) {
			[columns addObject:@{ @"title": column.title ?: @"", @"node": column.nodeId ?: @"",
			                      @"value": ORMValueList(column.value) }];
			continue;
		}
		NSMutableDictionary *item = [NSMutableDictionary dictionaryWithObjectsAndKeys:column.title ?: @"", @"title",
		                                                 column.nodeId ?: @"", @"node", ORMPathList(column.path), @"path",
		                                                 column.trail, @"trail", nil];
		if (column.identifierKey != nil) {
			[item setObject:column.identifierKey forKey:@"identifier"];
		}
		if ([column.identifierParts count] > 0) {
			[item setObject:column.identifierParts forKey:@"identifierParts"];
		}
		[columns addObject:item];
	}
	[list setObject:columns forKey:@"columns"];
	NSMutableArray *sorts = [NSMutableArray array];
	for (ORMPlanSort *sort in _sorts) {
		[sorts addObject:@{ @"path": ORMPathList(sort.path), @"ascending": @(sort.ascending) }];
	}
	[list setObject:sorts forKey:@"sorts"];
	[list setObject:_notes forKey:@"notes"];
	return list;
}

/* Reading back: each part checked, the first wrong one the error. */

static NSError *
ORMPlanError(NSString *text)
{
	return [NSError errorWithDomain:ORMQueryPlanErrorDomain code:1
	                       userInfo:@{ NSLocalizedDescriptionKey: [@"Not a query plan: " stringByAppendingString:text] }];
}

static ORMPlanPath *
ORMReadPath(id list, NSError **error)
{
	if (![list isKindOfClass:[NSDictionary class]] || ![[list objectForKey:@"steps"] isKindOfClass:[NSArray class]]) {
		*error = ORMPlanError(@"a path is a dictionary with steps.");
		return nil;
	}
	id variable = [list objectForKey:@"variable"];
	if (variable != nil && !ORMPlanIsName(variable)) {
		*error = ORMPlanError([NSString stringWithFormat:@"%@ is no variable's name.", variable]);
		return nil;
	}
	NSMutableArray *steps = [NSMutableArray array];
	for (id step in [list objectForKey:@"steps"]) {
		id key = [step isKindOfClass:[NSDictionary class]] ? [step objectForKey:@"key"] : nil;
		id as = [step isKindOfClass:[NSDictionary class]] ? [step objectForKey:@"as"] : nil;
		if (ORMPlanIsName(key)) {
			[steps addObject:[ORMPlanStep stepWithKey:key]];
		} else if (ORMPlanIsName(as)) {
			[steps addObject:[ORMPlanStep stepAsEntity:as]];
		} else {
			*error = ORMPlanError([NSString stringWithFormat:@"%@ is no property's or entity's name.", key ?: as ?: step]);
			return nil;
		}
	}
	return [ORMPlanPath pathFrom:variable steps:steps];
}

static ORMPlanCondition *ORMReadCondition(id list, NSDictionary<NSString *, ORMPlanDefinition *> *defined, NSError **error);

/* A value that may be an aggregate, its bag reading the sets defined. */
static ORMPlanValue *
ORMReadValueIn(id list, NSDictionary<NSString *, ORMPlanDefinition *> *defined, NSError **error)
{
	if ([list isKindOfClass:[NSDictionary class]] && [list objectForKey:@"aggregate"] != nil) {
		id function = [list objectForKey:@"aggregate"];
		if (![@[ @"count", @"sum", @"average", @"max", @"min" ] containsObject:function]) {
			*error = ORMPlanError([NSString stringWithFormat:@"%@ is no aggregate function.", function]);
			return nil;
		}
		id name = [list objectForKey:@"in"];
		ORMPlanDefinition *bag = [name isKindOfClass:[NSString class]] ? [defined objectForKey:name] : nil;
		if (bag == nil) {
			*error = ORMPlanError([NSString stringWithFormat:@"%@ is no bag defined before it is used.", name]);
			return nil;
		}
		id of = [list objectForKey:@"of"];
		id where = [list objectForKey:@"where"];
		ORMPlanPath *is = ORMReadPath([list objectForKey:@"is"], error);
		if (is == nil || (of != nil && ![of isKindOfClass:[NSString class]]) || ![where isKindOfClass:[NSString class]]) {
			if (*error == nil) {
				*error = ORMPlanError(@"an aggregate names its bag's columns.");
			}
			return nil;
		}
		return [ORMPlanValue aggregate:function of:of in:bag where:where is:is];
	}
	return ORMReadValue(list, error);
}

static ORMPlanValue *
ORMReadValue(id list, NSError **error)
{
	if (![list isKindOfClass:[NSDictionary class]]) {
		*error = ORMPlanError(@"a value is a dictionary.");
		return nil;
	}
	if ([list objectForKey:@"path"] != nil) {
		ORMPlanPath *path = ORMReadPath([list objectForKey:@"path"], error);
		return path != nil ? [ORMPlanValue valueAtPath:path] : nil;
	}
	id text = [list objectForKey:@"constant"];
	id type = [list objectForKey:@"type"];
	if (![text isKindOfClass:[NSString class]] || ![type isKindOfClass:[NSString class]]) {
		*error = ORMPlanError(@"a constant has its text and its type.");
		return nil;
	}
	return [ORMPlanValue constant:text type:type];
}

static ORMPlanCondition *
ORMReadCondition(id list, NSDictionary<NSString *, ORMPlanDefinition *> *defined, NSError **error)
{
	if (![list isKindOfClass:[NSDictionary class]]) {
		*error = ORMPlanError(@"a condition is a dictionary.");
		return nil;
	}
	NSUInteger kind = [ORMPlanKindNames() indexOfObject:[list objectForKey:@"kind"] ?: @""];
	if (kind == NSNotFound) {
		*error = ORMPlanError([NSString stringWithFormat:@"%@ is no kind of condition.", [list objectForKey:@"kind"]]);
		return nil;
	}
	ORMPlanCondition *condition = [ORMPlanCondition ofKind:(ORMPlanConditionKind)kind];
	if ([list objectForKey:@"operands"] != nil) {
		NSMutableArray *operands = [NSMutableArray array];
		for (id each in [list objectForKey:@"operands"]) {
			ORMPlanCondition *operand = ORMReadCondition(each, defined, error);
			if (operand == nil) {
				return nil;
			}
			[operands addObject:operand];
		}
		condition.operands = operands;
	}
#define ORM_READ(key, reader, property) \
	if ([list objectForKey:key] != nil) { \
		id read = reader([list objectForKey:key], error); \
		if (read == nil) { \
			return nil; \
		} \
		condition.property = read; \
	}
	if ([list objectForKey:@"operand"] != nil) {
		condition.operand = ORMReadCondition([list objectForKey:@"operand"], defined, error);
		if (condition.operand == nil) {
			return nil;
		}
	}
	for (NSString *side in @[ @"left", @"right" ]) {
		if ([list objectForKey:side] != nil) {
			ORMPlanValue *value = ORMReadValueIn([list objectForKey:side], defined, error);
			if (value == nil) {
				return nil;
			}
			[condition setValue:value forKey:side];
		}
	}
	ORM_READ(@"path", ORMReadPath, path)
	ORM_READ(@"otherPath", ORMReadPath, otherPath)
	ORM_READ(@"valuePath", ORMReadPath, valuePath)
	ORM_READ(@"constant", ORMReadValue, constant)
#undef ORM_READ
	id comparison = [list objectForKey:@"comparison"];
	if (comparison != nil && ![ORMPlanComparisons() containsObject:comparison]) {
		*error = ORMPlanError([NSString stringWithFormat:@"%@ is no comparison.", comparison]);
		return nil;
	}
	condition.comparison = comparison;
	id function = [list objectForKey:@"function"];
	if (function != nil && ![ORMPlanFunctions() containsObject:function]) {
		*error = ORMPlanError([NSString stringWithFormat:@"%@ is no aggregate function.", function]);
		return nil;
	}
	condition.function = function;
	id variable = [list objectForKey:@"variable"];
	if (variable != nil && !ORMPlanIsName(variable)) {
		*error = ORMPlanError([NSString stringWithFormat:@"%@ is no variable's name.", variable]);
		return nil;
	}
	condition.variable = variable;
	condition.number = [[list objectForKey:@"number"] unsignedIntegerValue];
	id entity = [list objectForKey:@"entity"];
	if (entity != nil && !ORMPlanIsName(entity)) {
		*error = ORMPlanError([NSString stringWithFormat:@"%@ is no entity's name.", entity]);
		return nil;
	}
	condition.entityName = entity;
	id trail = [list objectForKey:@"trail"];
	if (trail != nil) {
		for (id key in [trail isKindOfClass:[NSArray class]] ? trail : @[ @"" ]) {
			if (!ORMPlanIsName(key)) {
				*error = ORMPlanError([NSString stringWithFormat:@"%@ is no property's name.", key]);
				return nil;
			}
		}
		condition.trail = trail;
	}
	id definition = [list objectForKey:@"definition"];
	if (definition != nil) {
		condition.definition = [definition isKindOfClass:[NSString class]] ? [defined objectForKey:definition] : nil;
		if (condition.definition == nil) {
			*error = ORMPlanError([NSString stringWithFormat:@"%@ is no set defined before it is used.", definition]);
			return nil;
		}
	} else if ([list objectForKey:@"plan"] != nil) {
		condition.plan = [ORMQueryPlan readPlan:[list objectForKey:@"plan"] defined:defined error:error];
		if (condition.plan == nil) {
			return nil;
		}
	}
	if ([list objectForKey:@"pairs"] != nil) {
		NSMutableArray *pairs = [NSMutableArray array];
		for (id pair in [list objectForKey:@"pairs"]) {
			if (![pair isKindOfClass:[NSArray class]] || [pair count] != 2) {
				*error = ORMPlanError(@"a pair is two paths.");
				return nil;
			}
			ORMPlanPath *ours = ORMReadPath([pair firstObject], error);
			ORMPlanPath *theirs = ours != nil ? ORMReadPath([pair lastObject], error) : nil;
			if (theirs == nil) {
				return nil;
			}
			[pairs addObject:@[ ours, theirs ]];
		}
		condition.pairs = pairs;
	}
	id binding = [list objectForKey:@"binding"];
	if (binding != nil && !ORMPlanIsName(binding)) {
		*error = ORMPlanError([NSString stringWithFormat:@"%@ is no variable's name.", binding]);
		return nil;
	}
	condition.boundVariable = binding;
	condition.isOptional = [[list objectForKey:@"optional"] boolValue];
	return condition;
}

+ (instancetype)planWithPropertyList:(id)list error:(NSError **)error
{
	NSError *failure = nil;
	ORMQueryPlan *plan = [self readPlan:list defined:@{} error:&failure];
	if (plan == nil && error != NULL) {
		*error = failure ?: ORMPlanError(@"it could not be read.");
	}
	return plan;
}

+ (instancetype)readPlan:(id)list defined:(NSDictionary<NSString *, ORMPlanDefinition *> *)defined
                   error:(NSError **)reason
{
	if (![list isKindOfClass:[NSDictionary class]]) {
		*reason = ORMPlanError(@"a plan is a dictionary.");
		return nil;
	}
	/* Its sets, each seeing those before it. */
	NSMutableDictionary *visible = [NSMutableDictionary dictionaryWithDictionary:defined];
	NSMutableArray *definitions = [NSMutableArray array];
	id definitionList = [list objectForKey:@"definitions"];
	if (definitionList != nil && ![definitionList isKindOfClass:[NSArray class]]) {
		*reason = ORMPlanError(@"its definitions are a list.");
		return nil;
	}
	for (id item in definitionList ?: @[]) {
		id name = [item isKindOfClass:[NSDictionary class]] ? [item objectForKey:@"name"] : nil;
		if (!ORMPlanIsName(name) || [visible objectForKey:name] != nil) {
			*reason = ORMPlanError([NSString stringWithFormat:@"%@ is no name of a set, or one defined twice.", name ?: item]);
			return nil;
		}
		ORMQueryPlan *body = [self readPlan:[item objectForKey:@"plan"] defined:visible error:reason];
		if (body == nil) {
			return nil;
		}
		ORMPlanDefinition *definition = [ORMPlanDefinition definitionNamed:name plan:body];
		[definitions addObject:definition];
		[visible setObject:definition forKey:name];
	}
	id entity = [list objectForKey:@"entity"];
	if (entity != nil && !ORMPlanIsName(entity)) {
		*reason = ORMPlanError([NSString stringWithFormat:@"%@ is no entity's name.", entity]);
		return nil;
	}
	ORMPlanCondition *condition = nil;
	if ([list objectForKey:@"condition"] != nil) {
		condition = ORMReadCondition([list objectForKey:@"condition"], visible, reason);
		if (condition == nil) {
			return nil;
		}
	}
	NSMutableArray *columns = [NSMutableArray array];
	for (id item in [list objectForKey:@"columns"] ?: @[]) {
		if ([item isKindOfClass:[NSDictionary class]] && [item objectForKey:@"value"] != nil) {
			ORMPlanValue *value = ORMReadValueIn([item objectForKey:@"value"], visible, reason);
			if (value == nil) {
				return nil;
			}
			[columns addObject:[ORMPlanColumn columnTitled:[item objectForKey:@"title"] node:[item objectForKey:@"node"]
			                                         value:value]];
			continue;
		}
		ORMPlanPath *path = [item isKindOfClass:[NSDictionary class]] ? ORMReadPath([item objectForKey:@"path"], reason) : nil;
		id identifier = [item isKindOfClass:[NSDictionary class]] ? [item objectForKey:@"identifier"] : nil;
		if (path == nil || (identifier != nil && !ORMPlanIsName(identifier))) {
			if (path != nil || *reason == nil) {
				*reason = ORMPlanError(@"a column has a path, and an identifier's name.");
			}
			return nil;
		}
		id trail = [item objectForKey:@"trail"];
		for (id key in [trail isKindOfClass:[NSArray class]] ? trail : @[]) {
			if (!ORMPlanIsName(key)) {
				*reason = ORMPlanError([NSString stringWithFormat:@"%@ is no property's name.", key]);
				return nil;
			}
		}
		ORMPlanColumn *read = [ORMPlanColumn columnTitled:[item objectForKey:@"title"] node:[item objectForKey:@"node"] path:path
		                                            trail:[trail isKindOfClass:[NSArray class]] ? trail : nil
		                                       identifier:identifier];
		id parts = [item objectForKey:@"identifierParts"];
		for (id keys in [parts isKindOfClass:[NSArray class]] ? parts : @[]) {
			for (id key in [keys isKindOfClass:[NSArray class]] ? keys : @[ [NSNull null] ]) {
				if (!ORMPlanIsName(key)) {
					*reason = ORMPlanError(@"a column's identifying parts are key paths of names.");
					return nil;
				}
			}
		}
		read.identifierParts = [parts isKindOfClass:[NSArray class]] ? parts : nil;
		[columns addObject:read];
	}
	NSMutableArray *sorts = [NSMutableArray array];
	for (id item in [list objectForKey:@"sorts"] ?: @[]) {
		ORMPlanPath *path = [item isKindOfClass:[NSDictionary class]] ? ORMReadPath([item objectForKey:@"path"], reason) : nil;
		if (path == nil) {
			if (*reason == nil) {
				*reason = ORMPlanError(@"a sort has a path.");
			}
			return nil;
		}
		[sorts addObject:[ORMPlanSort sortBy:path ascending:[[item objectForKey:@"ascending"] boolValue]]];
	}
	return [self planReading:entity where:condition columns:columns sorts:sorts notes:[list objectForKey:@"notes"] ?: @[]
	             definitions:definitions];
}

@end
