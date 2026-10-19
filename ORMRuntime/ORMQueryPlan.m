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

+ (instancetype)aggregate:(NSString *)function
                       of:(NSString *)column
                       in:(ORMPlanDefinition *)bag
                    where:(NSString *)groupColumn
                       is:(ORMPlanPath *)groupPath
                     also:(NSArray<NSString *> *)columns
                      are:(NSArray<ORMPlanValue *> *)values
{
	ORMPlanValue *value = [self aggregate:function of:column in:bag where:groupColumn is:groupPath];
	value->_alsoColumns = [columns count] > 0 ? [columns copy] : nil;
	value->_alsoValues = [columns count] > 0 ? [values copy] : nil;
	return value;
}

+ (instancetype)aggregate:(NSString *)function
                       of:(NSString *)column
                       in:(ORMPlanDefinition *)bag
                    where:(NSString *)groupColumn
                       is:(ORMPlanPath *)groupPath
                   window:(NSString *)windowColumn
               comparison:(NSString *)comparison
                     than:(ORMPlanValue *)than
{
	ORMPlanValue *value = [self aggregate:function of:column in:bag where:groupColumn is:groupPath];
	value->_windowColumn = [windowColumn copy];
	value->_windowComparison = [comparison copy];
	value->_windowValue = than;
	return value;
}

- (ORMPlanValue *)windowCopy
{
	ORMPlanValue *value = [ORMPlanValue aggregate:_function of:_column in:_bag where:_groupColumn is:_groupPath
	                                       window:_windowColumn comparison:_windowComparison than:_windowValue];
	value->_windowOtherComparison = _windowOtherComparison;
	value->_windowOtherValue = _windowOtherValue;
	value->_alsoColumns = _alsoColumns;
	value->_alsoValues = _alsoValues;
	value->_membersKey = _membersKey;
	return value;
}

- (instancetype)valueOfMembers:(NSString *)key
{
	ORMPlanValue *value = [self windowCopy];
	value->_membersKey = [key copy];
	return value;
}

- (instancetype)valueBoundedAlso:(NSString *)comparison than:(ORMPlanValue *)than
{
	ORMPlanValue *value = [self windowCopy];
	value->_windowOtherComparison = [comparison copy];
	value->_windowOtherValue = than;
	return value;
}

- (instancetype)valueAlso:(NSArray<NSString *> *)columns are:(NSArray<ORMPlanValue *> *)values
{
	ORMPlanValue *value = [self windowCopy];
	value->_alsoColumns = [columns count] > 0 ? [columns copy] : nil;
	value->_alsoValues = [columns count] > 0 ? [values copy] : nil;
	return value;
}

+ (instancetype)apply:(NSString *)function to:(NSArray<ORMPlanValue *> *)operands
{
	ORMPlanValue *value = [[self alloc] init];
	value->_function = [function copy];
	value->_operands = [operands copy] ?: @[];
	return value;
}

- (NSArray<ORMPlanPath *> *)paths
{
	NSMutableArray *paths = [NSMutableArray array];
	if (_path != nil) {
		[paths addObject:_path];
	}
	if (_groupPath != nil) {
		[paths addObject:_groupPath];
	}
	for (ORMPlanValue *operand in [(_operands ?: @[]) arrayByAddingObjectsFromArray:_alsoValues ?: @[]]) {
		[paths addObjectsFromArray:[operand paths]];
	}
	[paths addObjectsFromArray:[_windowValue paths] ?: @[]];
	[paths addObjectsFromArray:[_windowOtherValue paths] ?: @[]];
	return paths;
}

- (BOOL)usesBag
{
	if (_bag != nil) {
		return YES;
	}
	for (ORMPlanValue *operand in _operands) {
		if ([operand usesBag]) {
			return YES;
		}
	}
	return NO;
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
	if (_operands != nil) {
		return [NSString stringWithFormat:@"%@(%@)", _function, [[_operands valueForKey:@"description"] componentsJoinedByString:@", "]];
	}
	if (_bag != nil) {
		NSString *of = _column != nil ? [NSString stringWithFormat:@"%@ of %@", _function, ORMColumnTitle(_bag, _column)]
		                              : _function;
		NSMutableString *where = [NSMutableString stringWithFormat:@"%@ is %@", ORMColumnTitle(_bag, _groupColumn), _groupPath];
		for (NSUInteger i = 0; i < [_alsoColumns count]; i++) {
			[where appendFormat:@", %@ is %@", ORMColumnTitle(_bag, [_alsoColumns objectAtIndex:i]), [_alsoValues objectAtIndex:i]];
		}
		if (_windowColumn != nil) {
			[where appendFormat:@", %@ %@ %@", ORMColumnTitle(_bag, _windowColumn), _windowComparison, _windowValue];
		}
		if (_windowOtherComparison != nil) {
			[where appendFormat:@", %@ %@ %@", ORMColumnTitle(_bag, _windowColumn), _windowOtherComparison, _windowOtherValue];
		}
		return [NSString stringWithFormat:@"%@ in %@ where %@", of, _bag.name, where];
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
	for (ORMPlanPath *path in [([self.left paths] ?: @[]) arrayByAddingObjectsFromArray:[self.right paths] ?: @[]]) {
		ORMAddVariable(free, path);
	}
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

- (NSSet<NSString *> *)boundVariables
{
	NSMutableSet *bound = [NSMutableSet set];
	if ((self.kind == ORMPlanExists || self.kind == ORMPlanMaybe) && self.variable != nil) {
		[bound addObject:self.variable];
	}
	if (self.kind == ORMPlanMatches && self.boundVariable != nil) {
		[bound addObject:self.boundVariable];
	}
	for (ORMPlanCondition *operand in self.operands) {
		[bound unionSet:[operand boundVariables]];
	}
	if (self.operand != nil) {
		[bound unionSet:[self.operand boundVariables]];
	}
	return bound;
}

- (NSArray *)memberProbe
{
	if ((self.kind != ORMPlanExists && self.kind != ORMPlanCount && self.kind != ORMPlanAggregate && self.kind != ORMPlanMaybe)
	    || self.variable == nil || self.operand == nil || [self.path.steps count] == 0) {
		return nil;
	}
	NSArray *conjuncts = self.operand.kind == ORMPlanAnd ? self.operand.operands : @[ self.operand ];
	NSSet *bound = [self boundVariables];
	for (ORMPlanCondition *each in conjuncts) {
		if (each.kind != ORMPlanCompare || ![each.comparison isEqualToString:@"="] || each.left == nil || each.right == nil) {
			continue;
		}
		for (NSArray *sides in @[ @[ each.left, each.right ], @[ each.right, each.left ] ]) {
			ORMPlanPath *path = [(ORMPlanValue *)[sides firstObject] path];
			ORMPlanValue *theirs = [sides lastObject];
			ORMPlanStep *cast = [path.steps count] > 1 ? [path.steps objectAtIndex:[path.steps count] - 2] : nil;
			if (path == nil || ![path.variable isEqualToString:self.variable] || [path.keys count] != 1
			    || [(ORMPlanStep *)[path.steps lastObject] key] == nil || ([path.steps count] > 1 && cast.entityName == nil)) {
				continue;
			}
			BOOL invariant = YES;
			for (ORMPlanPath *used in [theirs paths]) {
				invariant = invariant && (used.variable == nil || ![bound containsObject:used.variable]);
			}
			if (invariant) {
				return @[ [path.keys firstObject], theirs, cast.entityName ?: (id)[NSNull null] ];
			}
		}
	}
	return nil;
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

+ (instancetype)sortByColumnOf:(NSString *)nodeId ascending:(BOOL)ascending
{
	ORMPlanSort *sort = [[self alloc] init];
	sort->_nodeId = [nodeId copy];
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
	return [NSString stringWithFormat:@"%@ %@", _path ?: (id)[@"column of " stringByAppendingString:_nodeId ?: @"?"],
	                                  _ascending ? @"ascending" : @"descending"];
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
			/* Computed of the object read: listed with it, or not at all; of
			 * what a variable is bound to, not of the object alone. */
			for (ORMPlanPath *path in [column.value paths]) {
				if (path.variable != nil && column.value.operands != nil) {
					return nil;
				}
			}
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

/* The path's trail, into trails when it has one. */
static void
ORMAddTrail(ORMPlanPath *path, NSDictionary *bound, NSMutableSet *trails)
{
	NSArray *trail = ORMTrailOf(path, bound);
	if ([trail count] > 0) {
		[trails addObject:trail];
	}
}

/* Trails in the order of their dotted names. */
static NSInteger
ORMCompareTrails(NSArray *a, NSArray *b, void *context)
{
	(void)context;
	return [[a componentsJoinedByString:@"."] compare:[b componentsJoinedByString:@"."]];
}

/* What the condition reads, into trails; NO where it reads what no path
 * says. */
static BOOL ORMCollectTrailsIn(ORMPlanCondition *condition, NSDictionary *bound, NSMutableSet *trails, BOOL bags);

static BOOL
ORMCollectTrails(ORMPlanCondition *condition, NSDictionary *bound, NSMutableSet *trails)
{
	return ORMCollectTrailsIn(condition, bound, trails, NO);
}

static BOOL
ORMCollectTrailsIn(ORMPlanCondition *condition, NSDictionary *bound, NSMutableSet *trails, BOOL bags)
{
	if (condition == nil) {
		return YES;
	}
	BOOL ok = YES;
	switch (condition.kind) {
	case ORMPlanAnd:
	case ORMPlanOr:
		for (ORMPlanCondition *operand in condition.operands) {
			ok = ORMCollectTrailsIn(operand, bound, trails, bags) && ok;
		}
		return ok;
	case ORMPlanNot:
		return ORMCollectTrailsIn(condition.operand, bound, trails, bags);
	case ORMPlanCompare:
		if (!bags && ([condition.left usesBag] || [condition.right usesBag])) {
			return NO;
		}
		for (ORMPlanPath *path in [([condition.left paths] ?: @[]) arrayByAddingObjectsFromArray:[condition.right paths] ?: @[]]) {
			ORMAddTrail(path, bound, trails);
		}
		return YES;
	case ORMPlanNotNull:
	case ORMPlanIsOf:
		ORMAddTrail(condition.path, bound, trails);
		return YES;
	case ORMPlanSame:
		ORMAddTrail(condition.path, bound, trails);
		ORMAddTrail(condition.otherPath, bound, trails);
		return YES;
	case ORMPlanAmong:
		ORMAddTrail(condition.path, bound, trails);
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
		return ORMCollectTrailsIn(condition.operand, inner, trails, bags);
	}
	case ORMPlanMatches:
		return NO;
	}
	return NO;
}

/* What the condition reads, as ORMCollectTrails, its bags' aggregates
 * read already (their group paths are what is compared). */
static BOOL
ORMCollectTrailsAllowingBags(ORMPlanCondition *condition, NSMutableSet *trails)
{
	return ORMCollectTrailsIn(condition, @{}, trails, YES);
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

/* The bags the value aggregates, its operands' too. */
static void
ORMBagValuesOf(ORMPlanValue *value, NSMutableArray *into)
{
	if (value.bag != nil) {
		[into addObject:value];
	}
	for (ORMPlanValue *operand in [(value.operands ?: @[]) arrayByAddingObjectsFromArray:value.alsoValues ?: @[]]) {
		ORMBagValuesOf(operand, into);
	}
	if (value.windowValue != nil) {
		ORMBagValuesOf(value.windowValue, into);
	}
	if (value.windowOtherValue != nil) {
		ORMBagValuesOf(value.windowOtherValue, into);
	}
}

static void
ORMBagValuesIn(ORMPlanCondition *condition, NSMutableArray *into)
{
	if (condition == nil) {
		return;
	}
	if (condition.left != nil) {
		ORMBagValuesOf(condition.left, into);
	}
	if (condition.right != nil) {
		ORMBagValuesOf(condition.right, into);
	}
	for (ORMPlanCondition *operand in condition.operands) {
		ORMBagValuesIn(operand, into);
	}
	ORMBagValuesIn(condition.operand, into);
}

/* Whether the aggregate's bag is of the object read itself: its plan
 * reads the same entity, grouped by the object it reads, here the object
 * read (by its identifier). Then what the bag reads is read from the
 * object too. */
- (BOOL)bagIsOfTheObjectRead:(ORMPlanValue *)value
{
	ORMPlanColumn *group = [value.bag.plan columnOfNode:value.groupColumn ?: @""];
	return [value.bag.plan.entityName isEqualToString:self.entityName] && group != nil && group.path.variable == nil
		&& [group.path.keys count] == 0 && value.groupPath.variable == nil && [value.groupPath.keys count] <= 1
		&& [value.alsoColumns count] == 0 && value.windowColumn == nil;
}

/* A window's trails from the object read: to its partition, and down to
 * the members and what its bag reads of each (a member changed changes
 * the window of every object of its partition); and what its bounds and
 * equalities read here. nil where its partition is not reached from the
 * object read, or its members are not named. */
- (NSArray<NSArray<NSString *> *> *)trailsOfWindow:(ORMPlanValue *)value
{
	NSArray *keys = value.groupPath.keys;
	NSArray *theirs = [value.bag.plan trailsFromRead];
	if (value.groupPath.variable != nil || [keys count] == 0 || value.membersKey == nil || theirs == nil) {
		return nil;
	}
	NSArray *partition = [keys subarrayWithRange:NSMakeRange(0, [keys count] - 1)];
	NSArray *down = [partition arrayByAddingObject:value.membersKey];
	NSArray *up = [[value.bag.plan columnOfNode:value.groupColumn ?: @""] path].keys;
	NSMutableArray *trails = [NSMutableArray arrayWithObjects:keys, down, nil];
	for (NSArray *trail in theirs) {
		/* Back up to the partition from a member: from the partition. */
		if ([up count] > 0 && [trail count] >= [up count] && [[trail subarrayWithRange:NSMakeRange(0, [up count])] isEqualToArray:up]) {
			NSArray *rest = [trail subarrayWithRange:NSMakeRange([up count], [trail count] - [up count])];
			if ([partition count] + [rest count] > 0) {
				[trails addObject:[partition arrayByAddingObjectsFromArray:rest]];
			}
			continue;
		}
		[trails addObject:[down arrayByAddingObjectsFromArray:trail]];
	}
	NSMutableArray *here = [NSMutableArray arrayWithArray:value.alsoValues ?: @[]];
	[here addObject:value.windowValue];
	if (value.windowOtherValue != nil) {
		[here addObject:value.windowOtherValue];
	}
	for (ORMPlanValue *each in here) {
		for (ORMPlanPath *path in [each paths]) {
			if (path.variable != nil) {
				return nil;
			}
			if ([path.keys count] > 0) {
				[trails addObject:path.keys];
			}
		}
	}
	return trails;
}

- (NSArray<NSArray<NSString *> *> *)trailsFromRead
{
	NSMutableSet *trails = [NSMutableSet set];
	/* Aggregates of bags of the object read: what each bag reads. */
	NSMutableArray *bagged = [NSMutableArray array];
	ORMBagValuesIn(self.condition, bagged);
	for (ORMPlanColumn *column in self.columns) {
		if (column.value != nil) {
			ORMBagValuesOf(column.value, bagged);
		}
	}
	NSMutableSet *bags = [NSMutableSet set];
	for (ORMPlanValue *value in bagged) {
		NSArray *theirs = value.windowColumn != nil ? [self trailsOfWindow:value]
			: [self bagIsOfTheObjectRead:value] ? [value.bag.plan trailsFromRead] : nil;
		if (theirs == nil) {
			return nil;
		}
		[trails addObjectsFromArray:theirs];
		[bags addObject:value.bag.name];
	}
	/* Sets it defines are those bags, or ones they define. */
	for (ORMPlanDefinition *definition in self.definitions) {
		if (![bags containsObject:definition.name] && ![definition.name hasPrefix:@"bag"]) {
			return nil;
		}
	}
	if (!ORMCollectTrailsAllowingBags(self.condition, trails)) {
		return nil;
	}
	NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
	ORMBindings(self.condition, @{}, bindings);
	for (ORMPlanColumn *column in self.columns) {
		if (column.value != nil) {
			/* Computed: what it is computed from; a bag's, above. */
			for (ORMPlanPath *path in [column.value paths]) {
				NSArray *trail = ORMTrailOf(path, bindings);
				if (trail == nil) {
					return nil;
				}
				if ([trail count] > 0) {
					[trails addObject:trail];
				}
			}
			continue;
		}
		NSArray *trail = [self trailOfColumn:column];
		if (trail == nil) {
			return nil;
		}
		if ([trail count] > 0) {
			[trails addObject:trail];
		}
	}
	return [[trails allObjects] sortedArrayUsingFunction:ORMCompareTrails context:NULL];
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
	if ([_rowSorts count] > 0) {
		/* By each column, its title. */
		NSMutableArray *by = [NSMutableArray array];
		for (NSArray *each in [self rowSortColumns]) {
			ORMPlanColumn *column = [_columns objectAtIndex:[[each firstObject] unsignedIntegerValue]];
			[by addObject:[NSString stringWithFormat:@"%@ %@", column.title, [[each lastObject] boolValue] ? @"ascending" : @"descending"]];
		}
		[lines addObject:[@"rows sorted by " stringByAppendingString:[by componentsJoinedByString:@", "]]];
	}
	return [lines componentsJoinedByString:@"\n"];
}

- (NSArray<NSArray *> *)rowSortColumns
{
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMPlanSort *sort in _rowSorts) {
		for (NSUInteger i = 0; i < [_columns count]; i++) {
			if ([[[_columns objectAtIndex:i] nodeId] isEqualToString:sort.nodeId ?: @""]) {
				[columns addObject:@[ @(i), @(sort.ascending) ]];
				break;
			}
		}
	}
	return columns;
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
	if (value.operands != nil) {
		NSMutableArray *operands = [NSMutableArray array];
		for (ORMPlanValue *operand in value.operands) {
			[operands addObject:ORMValueList(operand)];
		}
		return @{ @"apply": value.function, @"to": operands };
	}
	if (value.bag != nil) {
		NSMutableDictionary *list = [NSMutableDictionary dictionaryWithObjectsAndKeys:value.function, @"aggregate",
		                                                 value.bag.name, @"in", value.groupColumn ?: @"", @"where",
		                                                 ORMPathList(value.groupPath), @"is", nil];
		if (value.column != nil) {
			[list setObject:value.column forKey:@"of"];
		}
		if ([value.alsoColumns count] > 0) {
			NSMutableArray *values = [NSMutableArray array];
			for (ORMPlanValue *each in value.alsoValues) {
				[values addObject:ORMValueList(each)];
			}
			[list setObject:value.alsoColumns forKey:@"alsoWhere"];
			[list setObject:values forKey:@"alsoAre"];
		}
		if (value.windowColumn != nil) {
			[list setObject:value.windowColumn forKey:@"window"];
			[list setObject:value.windowComparison forKey:@"windowIs"];
			[list setObject:ORMValueList(value.windowValue) forKey:@"than"];
			if (value.membersKey != nil) {
				[list setObject:value.membersKey forKey:@"members"];
			}
		}
		if (value.windowOtherComparison != nil) {
			[list setObject:value.windowOtherComparison forKey:@"windowAlsoIs"];
			[list setObject:ORMValueList(value.windowOtherValue) forKey:@"alsoThan"];
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
	if ([_rowSorts count] > 0) {
		NSMutableArray *rowSorts = [NSMutableArray array];
		for (ORMPlanSort *sort in _rowSorts) {
			[rowSorts addObject:@{ @"column": sort.nodeId ?: @"", @"ascending": @(sort.ascending) }];
		}
		[list setObject:rowSorts forKey:@"rowSorts"];
	}
	[list setObject:_notes forKey:@"notes"];
	return list;
}

#pragma mark Computing

/* Whether a number is held whole: not a decimal, not a float or double. */
static BOOL
ORMIsWhole(NSNumber *number)
{
	if ([number isKindOfClass:[NSDecimalNumber class]]) {
		return NO;
	}
	const char *type = [number objCType];
	return type != NULL && strcmp(type, @encode(double)) != 0 && strcmp(type, @encode(float)) != 0;
}

static NSDecimalNumber *
ORMDecimalOf(NSNumber *number)
{
	return [number isKindOfClass:[NSDecimalNumber class]] ? (NSDecimalNumber *)number
		: [NSDecimalNumber decimalNumberWithDecimal:[number decimalValue]];
}

/* Two numbers' sum, difference, product or quotient (function's), in the
 * kind both are: nil for a division by zero. */
static NSNumber *
ORMArithmetic(NSString *function, NSNumber *a, NSNumber *b)
{
	BOOL divide = [function isEqualToString:@"divide"];
	if (divide && [b doubleValue] == 0) {
		return nil;
	}
	if ([a isKindOfClass:[NSDecimalNumber class]] || [b isKindOfClass:[NSDecimalNumber class]]) {
		NSDecimalNumber *x = ORMDecimalOf(a), *y = ORMDecimalOf(b);
		@try {
			if ([function isEqualToString:@"add"]) {
				return [x decimalNumberByAdding:y];
			}
			if ([function isEqualToString:@"subtract"]) {
				return [x decimalNumberBySubtracting:y];
			}
			if ([function isEqualToString:@"multiply"]) {
				return [x decimalNumberByMultiplyingBy:y];
			}
			return [x decimalNumberByDividingBy:y];
		} @catch (NSException *exception) {
			return nil;
		}
	}
	if (ORMIsWhole(a) && ORMIsWhole(b) && !divide) {
		long long x = [a longLongValue], y = [b longLongValue];
		return @([function isEqualToString:@"add"] ? x + y : [function isEqualToString:@"subtract"] ? x - y : x * y);
	}
	double x = [a doubleValue], y = [b doubleValue];
	return @([function isEqualToString:@"add"] ? x + y : [function isEqualToString:@"subtract"] ? x - y
	         : [function isEqualToString:@"multiply"] ? x * y : x / y);
}

/* The number rounded to the places, half away from zero. */
static NSNumber *
ORMRounded(NSNumber *number, NSInteger places)
{
	if (ORMIsWhole(number) && places >= 0) {
		return number;
	}
	NSDecimalNumberHandler *handler = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain
	                                                                                         scale:(short)places
	                                                                              raiseOnExactness:NO
	                                                                               raiseOnOverflow:NO
	                                                                              raiseOnUnderflow:NO
	                                                                           raiseOnDivideByZero:NO];
	NSDecimalNumber *rounded = [ORMDecimalOf(number) decimalNumberByRoundingAccordingToBehavior:handler];
	return [number isKindOfClass:[NSDecimalNumber class]] ? rounded : @([rounded doubleValue]);
}

/* The calendar dates are computed in: Gregorian, UTC, as the sample
 * populations' moments are. */
static NSCalendar *
ORMUTCCalendar(void)
{
	NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	return calendar;
}

/* The moment the date's day starts, in the calendar's time zone (GNUstep's
 * NSCalendar has no -startOfDayForDate:). */
static NSDate *
ORMStartOfDay(NSCalendar *calendar, NSDate *date)
{
	NSDateComponents *parts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
	return [calendar dateFromComponents:parts];
}

/* A moment: a date, or ISO 8601 text as a service answers with one; nil
 * for anything else. */
static NSDate *
ORMMomentOf(id value)
{
	if ([value isKindOfClass:[NSDate class]]) {
		return value;
	}
	if (![value isKindOfClass:[NSString class]]) {
		return nil;
	}
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	for (NSString *format in @[ @"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", @"yyyy-MM-dd'T'HH:mm:ssXXXXX", @"yyyy-MM-dd'T'HH:mm:ss.SSS",
	                            @"yyyy-MM-dd'T'HH:mm:ss", @"yyyy-MM-dd HH:mm:ss", @"yyyy-MM-dd" ]) {
		formatter.dateFormat = format;
		NSDate *date = [formatter dateFromString:value];
		if (date != nil) {
			return date;
		}
	}
	return nil;
}

/* A date function's value (docs/EXPRESSIONS.md), in UTC; nil where an
 * argument is not of its kind. */
static id
ORMDateFunction(NSString *function, NSArray *given)
{
	NSCalendar *calendar = ORMUTCCalendar();
	if ([function isEqualToString:@"today"]) {
		return ORMStartOfDay(calendar, [NSDate date]);
	}
	NSDate *first = ORMMomentOf([given firstObject]);
	if (first == nil) {
		return nil;
	}
	if ([function isEqualToString:@"date"]) {
		return ORMStartOfDay(calendar, first);
	}
	if ([function isEqualToString:@"month"]) {
		NSDateComponents *parts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:first];
		return [calendar dateFromComponents:parts];
	}
	id second = [given count] > 1 ? [given objectAtIndex:1] : nil;
	if ([function isEqualToString:@"addDays"] || [function isEqualToString:@"addMonths"]) {
		if (![second isKindOfClass:[NSNumber class]]) {
			return nil;
		}
		NSDateComponents *by = [[NSDateComponents alloc] init];
		if ([function isEqualToString:@"addDays"]) {
			by.day = [second integerValue];
		} else {
			by.month = [second integerValue];
		}
		return [calendar dateByAddingComponents:by toDate:first options:0];
	}
	NSDate *last = ORMMomentOf(second);
	if (last == nil) {
		return nil;
	}
	if ([function isEqualToString:@"minutes"]) {
		return @((long long)([last timeIntervalSinceDate:first] / 60));
	}
	if ([function isEqualToString:@"days"]) {
		NSDateComponents *span = [calendar components:NSCalendarUnitDay fromDate:ORMStartOfDay(calendar, first)
		                                       toDate:ORMStartOfDay(calendar, last) options:0];
		return @(span.day);
	}
	NSDateComponents *span = [calendar components:NSCalendarUnitMonth fromDate:first toDate:last options:0];
	return @(span.month);
}

id
ORMPlanApply(NSString *function, NSArray *values)
{
	NSMutableArray *given = [NSMutableArray array];
	for (id value in values) {
		[given addObject:value != nil ? value : [NSNull null]];
	}
	id first = [given count] > 0 ? [given objectAtIndex:0] : [NSNull null];
	id second = [given count] > 1 ? [given objectAtIndex:1] : [NSNull null];
	if ([function isEqualToString:@"coalesce"]) {
		id chosen = first != [NSNull null] ? first : second;
		return chosen != [NSNull null] ? chosen : nil;
	}
	if ([function isEqualToString:@"min"] || [function isEqualToString:@"max"]) {
		BOOL alike = NO;
		for (Class kind in @[ [NSNumber class], [NSString class], [NSDate class] ]) {
			alike = alike || ([first isKindOfClass:kind] && [second isKindOfClass:kind]);
		}
		if (!alike) {
			return nil;
		}
		NSComparisonResult order = [first compare:second];
		BOOL min = [function isEqualToString:@"min"];
		return (order == NSOrderedDescending) == min ? second : first;
	}
	if ([@[ @"date", @"days", @"months", @"minutes", @"addDays", @"addMonths", @"month", @"today" ] containsObject:function ?: @""]) {
		return ORMDateFunction(function, given);
	}
	for (id value in given) {
		if (![value isKindOfClass:[NSNumber class]]) {
			return nil;
		}
	}
	if ([function isEqualToString:@"negate"] && [given count] == 1) {
		return ORMArithmetic(@"subtract", @0, first);
	}
	if ([function isEqualToString:@"abs"] && [given count] == 1) {
		return [first doubleValue] < 0 ? ORMArithmetic(@"subtract", @0, first) : first;
	}
	if ([function isEqualToString:@"round"] && [given count] == 2) {
		return ORMRounded(first, [second integerValue]);
	}
	if ([given count] == 2 && [@[ @"add", @"subtract", @"multiply", @"divide" ] containsObject:function ?: @""]) {
		return ORMArithmetic(function, first, second);
	}
	return nil;
}

/* Reading back: each part checked, the first wrong one the error. */

/* The functions a value applies, and how many operands each takes. */
static NSDictionary<NSString *, NSNumber *> *
ORMPlanFunctionArities(void)
{
	return @{ @"add": @2, @"subtract": @2, @"multiply": @2, @"divide": @2, @"negate": @1, @"round": @2, @"abs": @1,
		      @"min": @2, @"max": @2, @"coalesce": @2, @"date": @1, @"days": @2, @"months": @2, @"minutes": @2,
		      @"addDays": @2, @"addMonths": @2, @"month": @1, @"today": @0 };
}

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
	if ([list isKindOfClass:[NSDictionary class]] && [list objectForKey:@"apply"] != nil) {
		id function = [list objectForKey:@"apply"];
		id to = [list objectForKey:@"to"];
		NSNumber *arity = [ORMPlanFunctionArities() objectForKey:[function isKindOfClass:[NSString class]] ? function : @""];
		if (arity == nil || ![to isKindOfClass:[NSArray class]] || [to count] != [arity unsignedIntegerValue]) {
			*error = ORMPlanError([NSString stringWithFormat:@"%@ is no function of %lu values.", function,
			                                                 (unsigned long)([to isKindOfClass:[NSArray class]] ? [to count] : 0)]);
			return nil;
		}
		NSMutableArray *operands = [NSMutableArray array];
		for (id each in to) {
			ORMPlanValue *operand = ORMReadValueIn(each, defined, error);
			if (operand == nil) {
				return nil;
			}
			[operands addObject:operand];
		}
		return [ORMPlanValue apply:function to:operands];
	}
	if ([list isKindOfClass:[NSDictionary class]] && [list objectForKey:@"aggregate"] != nil) {
		id function = [list objectForKey:@"aggregate"];
		/* As the interpreter reads them: also the one value, and how many
		 * values there are. */
		if (![@[ @"value", @"distinct", @"count", @"sum", @"average", @"max", @"min" ] containsObject:function]) {
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
		id alsoWhere = [list objectForKey:@"alsoWhere"] ?: @[];
		id alsoAre = [list objectForKey:@"alsoAre"] ?: @[];
		if (![alsoWhere isKindOfClass:[NSArray class]] || ![alsoAre isKindOfClass:[NSArray class]]
		    || [alsoWhere count] != [alsoAre count]) {
			*error = ORMPlanError(@"an aggregate's other groups are columns and their values, as many of each.");
			return nil;
		}
		NSMutableArray *values = [NSMutableArray array];
		for (id each in alsoAre) {
			ORMPlanValue *also = ORMReadValueIn(each, defined, error);
			if (also == nil) {
				return nil;
			}
			[values addObject:also];
		}
		id window = [list objectForKey:@"window"];
		if (window != nil) {
			id comparison = [list objectForKey:@"windowIs"];
			if (![window isKindOfClass:[NSString class]] || ![@[ @"<", @"<=", @">", @">=" ] containsObject:comparison ?: @""]) {
				*error = ORMPlanError(@"an aggregate's window is a column, compared (<, <=, >, >=) with a value.");
				return nil;
			}
			ORMPlanValue *than = ORMReadValueIn([list objectForKey:@"than"], defined, error);
			if (than == nil) {
				return nil;
			}
			ORMPlanValue *windowed = [ORMPlanValue aggregate:function of:of in:bag where:where is:is window:window
			                                      comparison:comparison than:than];
			if ([values count] > 0) {
				windowed = [windowed valueAlso:alsoWhere are:values];
			}
			id members = [list objectForKey:@"members"];
			if (members != nil && ![members isKindOfClass:[NSString class]]) {
				*error = ORMPlanError(@"a window's members are a key.");
				return nil;
			}
			if (members != nil) {
				windowed = [windowed valueOfMembers:members];
			}
			id other = [list objectForKey:@"windowAlsoIs"];
			if (other == nil) {
				return windowed;
			}
			if (![@[ @"<", @"<=", @">", @">=" ] containsObject:other]) {
				*error = ORMPlanError(@"an aggregate's window's other bound is compared with <, <=, > or >=.");
				return nil;
			}
			ORMPlanValue *otherThan = ORMReadValueIn([list objectForKey:@"alsoThan"], defined, error);
			return otherThan != nil ? [windowed valueBoundedAlso:other than:otherThan] : nil;
		}
		return [ORMPlanValue aggregate:function of:of in:bag where:where is:is also:alsoWhere are:values];
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
	NSMutableArray *rowSorts = [NSMutableArray array];
	for (id item in [list objectForKey:@"rowSorts"] ?: @[]) {
		id column = [item isKindOfClass:[NSDictionary class]] ? [item objectForKey:@"column"] : nil;
		if (![column isKindOfClass:[NSString class]]) {
			*reason = ORMPlanError(@"a row sort names its column's node.");
			return nil;
		}
		[rowSorts addObject:[ORMPlanSort sortByColumnOf:column ascending:[[item objectForKey:@"ascending"] boolValue]]];
	}
	ORMQueryPlan *plan = [self planReading:entity where:condition columns:columns sorts:sorts
	                                 notes:[list objectForKey:@"notes"] ?: @[] definitions:definitions];
	plan.rowSorts = rowSorts;
	return plan;
}

@end
