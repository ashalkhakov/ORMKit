/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryFetch.h"
#import "ORMQueryPlaces.h"

@interface ORMQueryColumn ()
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSString *nodeId;
@property (nonatomic, readwrite, copy) NSString *keyPath;
@property (nonatomic, readwrite, copy) NSString *identifierKeyPath;
@end

@implementation ORMQueryColumn
@end

@interface ORMQueryJoin ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *entityName;
@property (nonatomic, readwrite, copy) NSString *predicateFormat;
@property (nonatomic, readwrite, copy) NSArray<NSArray<NSString *> *> *pairs;
@end

@implementation ORMQueryJoin
@end

static NSDictionary<NSString *, NSString *> *
ORMPredicateOperators(void)
{
	return @{ @"=": @"==", @"<>": @"!=", @"<": @"<", @"<=": @"<=", @">": @">", @">=": @">=" };
}

/* A string constant as NSPredicate reads one. */
static NSString *
ORMPredicateString(NSString *text)
{
	NSString *escaped = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
		stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
	return [NSString stringWithFormat:@"\"%@\"", escaped];
}

static NSString *
ORMJoined(NSArray<NSString *> *parts, NSString *connective)
{
	if ([parts count] == 0) {
		return nil;
	}
	if ([parts count] == 1) {
		return [parts firstObject];
	}
	NSMutableArray *wrapped = [NSMutableArray array];
	for (NSString *part in parts) {
		[wrapped addObject:[NSString stringWithFormat:@"(%@)", part]];
	}
	return [wrapped componentsJoinedByString:[NSString stringWithFormat:@" %@ ", connective]];
}

@implementation ORMQueryFetch
{
	ORMQuery *_query;
	ORMCDModel *_coreData;
	ORMQueryPlaces *_places;
	NSMutableArray<NSString *> *_notes;
	NSMutableArray<ORMQueryColumn *> *_columns;
	NSUInteger _variables;
	NSString *_entityName;
	NSString *_predicateFormat;
	/* The entity fetched: the root's, or the subtype's the root must be. */
	ORMCDEntity *_fetched;
	/* Each node reached: its expression where it was reached ("SELF",
	 * "city", "$x1.city"), and its key path from the fetched object. */
	NSMutableDictionary<NSString *, NSString *> *_expressions;
	NSMutableDictionary<NSString *, NSString *> *_paths;
	/* The subqueries' variables open where the translation is. */
	NSMutableArray<NSString *> *_scope;
	NSMutableArray<ORMQueryJoin *> *_joins;
	NSMutableArray<NSSortDescriptor *> *_sorts;
	/* How many nots and alternatives enclose where the translation is: a
	 * join is made only where none does. */
	NSUInteger _guarded;
}

- (instancetype)initWithQuery:(ORMQuery *)query model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	ORMCDModel *coreData = [[[ORMCoreDataMapper alloc] initWithModel:model mapping:mapping] map];
	return [self initWithQuery:query coreData:coreData];
}

- (instancetype)initWithQuery:(ORMQuery *)query coreData:(ORMCDModel *)coreData
{
	if ((self = [super init])) {
		_query = query;
		_coreData = coreData;
		_notes = [NSMutableArray array];
		_columns = [NSMutableArray array];
		_expressions = [NSMutableDictionary dictionary];
		_paths = [NSMutableDictionary dictionary];
		_scope = [NSMutableArray array];
		_joins = [NSMutableArray array];
		_sorts = [NSMutableArray array];
		_places = [[ORMQueryPlaces alloc] initWithCoreData:coreData];
		[self translate];
	}
	return self;
}

- (NSString *)entityName
{
	return _entityName;
}

- (NSString *)predicateFormat
{
	return _predicateFormat;
}

- (NSArray<ORMQueryColumn *> *)columns
{
	return [_columns copy];
}

- (NSArray<NSSortDescriptor *> *)sortDescriptors
{
	return [_sorts copy];
}

/* Whether the key path from the fetched object reaches one object or value:
 * no to-many on the way. */
- (BOOL)reachesOne:(NSString *)keyPath
{
	ORMCDEntity *at = _fetched;
	for (NSString *key in [keyPath componentsSeparatedByString:@"."]) {
		if (at == nil || [key isEqualToString:@"self"]) {
			continue;
		}
		ORMCDProperty *property = nil;
		for (ORMCDEntity *e = at; e != nil && property == nil;
		     e = e.parentName != nil ? [_coreData entityNamed:e.parentName] : nil) {
			property = [e propertyNamed:key];
		}
		if ([property isKindOfClass:[ORMCDRelationship class]]) {
			if (((ORMCDRelationship *)property).toMany) {
				return NO;
			}
			at = [_coreData entityNamed:((ORMCDRelationship *)property).destination];
		} else {
			at = nil;
		}
	}
	return YES;
}

/* What the results are listed in order of: each sorted node's column. */
- (void)sort
{
	for (ORMQueryNode *node in [_query nodes]) {
		if (node.sortOrder == ORMQueryUnsorted) {
			continue;
		}
		ORMQueryColumn *column = nil;
		for (ORMQueryColumn *each in _columns) {
			if ([each.nodeId isEqualToString:node.identifier]) {
				column = each;
			}
		}
		NSString *key = column.identifierKeyPath ?: column.keyPath;
		if (column == nil || [key isEqualToString:@"self"] || ![self reachesOne:key]) {
			[self note:[NSString stringWithFormat:@"%@ is sorted by, but %@.", [node designation],
			                                      column == nil ? @"not listed" : @"not one value for each result"]];
			continue;
		}
		[_sorts addObject:[NSSortDescriptor sortDescriptorWithKey:key ascending:node.sortOrder == ORMQueryAscending]];
	}
}

- (NSArray<ORMQueryJoin *> *)joins
{
	return [_joins copy];
}

- (NSPredicate *)predicateJoining:(NSDictionary<NSString *, NSArray *> *)joined
{
	NSMutableArray *conjuncts = [NSMutableArray arrayWithObject:[NSPredicate predicateWithFormat:_predicateFormat]];
	for (ORMQueryJoin *join in _joins) {
		NSMutableArray *alternatives = [NSMutableArray array];
		for (id object in [joined objectForKey:join.name]) {
			NSMutableArray *parts = [NSMutableArray array];
			for (NSArray *pair in join.pairs) {
				id value = [object valueForKeyPath:[pair lastObject]];
				[parts addObject:[NSComparisonPredicate
					predicateWithLeftExpression:[NSExpression expressionForKeyPath:[pair firstObject]]
					            rightExpression:[NSExpression expressionForConstantValue:value]
					                   modifier:NSDirectPredicateModifier
					                       type:NSEqualToPredicateOperatorType
					                    options:0]];
			}
			[alternatives addObject:[NSCompoundPredicate andPredicateWithSubpredicates:parts]];
		}
		[conjuncts addObject:[alternatives count] > 0 ? [NSCompoundPredicate orPredicateWithSubpredicates:alternatives]
		                                              : [NSPredicate predicateWithValue:NO]];
	}
	return [NSCompoundPredicate andPredicateWithSubpredicates:conjuncts];
}

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
}

- (BOOL)isComplete
{
	return _entityName != nil && [_notes count] == 0;
}

#pragma mark Where things are

- (NSString *)constant:(NSString *)value forAttribute:(ORMCDAttribute *)attribute
{
	NSArray *numeric = @[ @"Integer 16", @"Integer 32", @"Integer 64", @"Decimal", @"Double", @"Float" ];
	if ([numeric containsObject:attribute.attributeType]) {
		NSScanner *scanner = [NSScanner scannerWithString:value ?: @""];
		double number = 0;
		if ([scanner scanDouble:&number] && [scanner isAtEnd]) {
			return value;
		}
	}
	if ([attribute.attributeType isEqualToString:@"Boolean"]) {
		NSString *lower = [value lowercaseString];
		if ([@[ @"true", @"yes", @"1" ] containsObject:lower]) {
			return @"YES";
		}
		if ([@[ @"false", @"no", @"0" ] containsObject:lower]) {
			return @"NO";
		}
	}
	return ORMPredicateString(value);
}

- (NSString *)comparing:(NSString *)key node:(ORMQueryNode *)node attribute:(ORMCDAttribute *)attribute
{
	NSString *operator = [ORMPredicateOperators() objectForKey:node.comparison ?: @""];
	if (operator == nil) {
		return nil;
	}
	return [NSString stringWithFormat:@"%@ %@ %@", key, operator, [self constant:node.value forAttribute:attribute]];
}

- (void)note:(NSString *)text
{
	if (![_notes containsObject:text]) {
		[_notes addObject:text];
	}
}

- (NSString *)nextVariable
{
	_variables++;
	return [NSString stringWithFormat:@"$x%lu", (unsigned long)_variables];
}

- (NSString *)keyPath:(NSString *)path adding:(NSString *)key
{
	return [path length] > 0 ? [NSString stringWithFormat:@"%@.%@", path, key] : key;
}

- (void)column:(ORMQueryNode *)node keyPath:(NSString *)keyPath identifier:(NSString *)identifierKeyPath
{
	if (!node.isProjected) {
		return;
	}
	ORMQueryColumn *column = [[ORMQueryColumn alloc] init];
	column.title = node.objectType.name;
	column.nodeId = node.identifier;
	column.keyPath = [keyPath length] > 0 ? keyPath : @"self";
	column.identifierKeyPath = identifierKeyPath;
	[_columns addObject:column];
}

#pragma mark Correlating

/* The node is where the translation stands: what later nodes compare with
 * it, or are it, use. */
- (void)reached:(ORMQueryNode *)node expression:(NSString *)expression path:(NSString *)path
{
	[_expressions setObject:expression forKey:node.identifier];
	[_paths setObject:[path length] > 0 ? path : @"SELF" forKey:node.identifier];
}

- (BOOL)inScope:(NSString *)expression
{
	NSRegularExpression *variables = [NSRegularExpression regularExpressionWithPattern:@"\\$x[0-9]+" options:0
	                                                                              error:NULL];
	for (NSTextCheckingResult *match in [variables matchesInString:expression options:0
	                                                         range:NSMakeRange(0, [expression length])]) {
		if (![_scope containsObject:[expression substringWithRange:[match range]]]) {
			return NO;
		}
	}
	return YES;
}

/* The expression compared with the node the query reached before: its own
 * expression where that is still in scope; else the objects its key path
 * reaches, which "=" asks the expression to be among. */
- (NSString *)relate:(NSString *)expression comparison:(NSString *)comparison to:(ORMQueryNode *)other
{
	NSString *reference = [_expressions objectForKey:other.identifier];
	NSString *operator = [ORMPredicateOperators() objectForKey:comparison ?: @""];
	if (reference == nil || operator == nil) {
		[self note:[NSString stringWithFormat:@"%@ is compared with %@ before the query reaches it.",
		                                      expression, [other designation]]];
		return nil;
	}
	if ([self inScope:reference]) {
		return [NSString stringWithFormat:@"%@ %@ %@", expression, operator, reference];
	}
	NSString *path = [_paths objectForKey:other.identifier];
	if (other.comparison != nil || [other.steps count] > 0) {
		[self note:[NSString stringWithFormat:@"%@ is taken as any %@ the path reaches, not only those meeting its "
		                                      @"conditions.",
		                                      [other designation], other.objectType.name]];
	}
	/* Among the objects the path reaches: back from the expression along
	 * the inverse relationships to the fetched object, which Core Data's
	 * store says in SQL as it does not "IN" a to-many inside a subquery. */
	NSString *among = [self back:expression along:path] ?: [NSString stringWithFormat:@"%@ IN %@", expression, path];
	if ([comparison isEqualToString:@"="]) {
		return among;
	}
	if ([comparison isEqualToString:@"<>"]) {
		return [NSString stringWithFormat:@"NOT (%@)", among];
	}
	[self note:[NSString stringWithFormat:@"%@ %@ %@ compares with many: only = and <> can.", expression, comparison,
	                                      [other designation]]];
	return nil;
}

/* "ANY $x2.isOwnedByEmployees == SELF": the expression reached from the
 * fetched object along the path, said as the fetched object reached back
 * from it. nil unless the path is relationships, each with an inverse. */
- (NSString *)back:(NSString *)expression along:(NSString *)path
{
	if ([path isEqualToString:@"SELF"]) {
		return nil;
	}
	NSMutableArray *inverses = [NSMutableArray array];
	ORMCDEntity *at = _fetched;
	for (NSString *key in [path componentsSeparatedByString:@"."]) {
		ORMCDRelationship *relationship = nil;
		for (ORMCDEntity *e = at; e != nil && relationship == nil;
		     e = e.parentName != nil ? [_coreData entityNamed:e.parentName] : nil) {
			relationship = [e relationshipNamed:key];
		}
		if (relationship == nil || [relationship.inverseName length] == 0) {
			return nil;
		}
		[inverses insertObject:relationship.inverseName atIndex:0];
		at = [_coreData entityNamed:relationship.destination];
	}
	return [NSString stringWithFormat:@"ANY %@.%@ == SELF", expression, [inverses componentsJoinedByString:@"."]];
}

/* Being the same as an earlier node of its label, and the comparison with
 * another node. */
- (NSArray<NSString *> *)correlationsOf:(ORMQueryNode *)node expression:(NSString *)expression
{
	NSMutableArray *parts = [NSMutableArray array];
	ORMQueryNode *first = [_query firstOccurrenceOf:node];
	if (first != node) {
		NSString *same = [self relate:expression comparison:@"=" to:first];
		if (same != nil) {
			[parts addObject:same];
		}
	}
	if (node.comparedNode != nil) {
		NSString *compared = [self relate:expression comparison:node.comparison to:node.comparedNode];
		if (compared != nil) {
			[parts addObject:compared];
		}
	}
	return parts;
}

#pragma mark Translating

- (void)translate
{
	ORMQueryNode *root = _query.root;
	ORMCDEntity *entity = root != nil ? [_places entityOf:root.objectType] : nil;
	if (entity == nil) {
		[self note:[NSString stringWithFormat:@"%@ is no entity, so there is nothing to fetch.",
		                                      root.objectType.name ?: @"The query's object type"]];
		_predicateFormat = @"FALSEPREDICATE";
		return;
	}
	/* Every result is of the subtype the root's required steps go down
	 * to: fetching its entity, its own properties are the fetched
	 * entity's (a store fetching the supertype knows none of them). */
	_fetched = entity;
	for (ORMQueryNode *at = root; at != nil && !at.combinesWithOr;) {
		ORMQueryNode *next = nil;
		for (ORMQueryStep *step in at.steps) {
			ORMQueryNode *sub = [step.nodes firstObject];
			ORMCDEntity *subEntity = sub != nil ? [_places entityOf:sub.objectType] : nil;
			if ([step isSubtyping] && step.operatorKind == ORMQueryAnd && step.entryRole.isSupertypeMetaRole
			    && subEntity != nil && subEntity != _fetched && [_places entity:subEntity inherits:_fetched]) {
				_fetched = subEntity;
				next = sub;
				break;
			}
		}
		at = next;
	}
	_entityName = _fetched.name;
	if (!_query.isComplete) {
		[self note:@"Something the query goes through is no longer in the model, and is left out."];
	}
	NSString *predicate = [self predicateFor:root entity:entity prefix:@"" path:@"" columns:YES];
	_predicateFormat = predicate ?: @"TRUEPREDICATE";
	[self sort];
}

/* What the node and its steps require of the object at the prefix ("",
 * "$x1." or "degree."), its key path from the fetched object as path. */
- (NSString *)predicateFor:(ORMQueryNode *)node
                    entity:(ORMCDEntity *)entity
                    prefix:(NSString *)prefix
                      path:(NSString *)path
                   columns:(BOOL)columns
{
	NSMutableArray *parts = [NSMutableArray array];
	ORMCDAttribute *identifier = [_places identifierOf:node.objectType on:entity];
	if (columns) {
		[self column:node keyPath:path identifier:identifier != nil ? [self keyPath:path adding:identifier.name] : nil];
	}
	NSString *expression = [prefix length] > 0 ? [prefix substringToIndex:[prefix length] - 1] : @"SELF";
	NSArray *correlations = [self correlationsOf:node expression:expression];
	[self reached:node expression:expression path:path];
	[parts addObjectsFromArray:correlations];
	if (node.comparison != nil && node.comparedNode == nil) {
		if (identifier != nil) {
			NSString *condition = [self comparing:[prefix stringByAppendingString:identifier.name] node:node
			                            attribute:identifier];
			if (condition != nil) {
				[parts addObject:condition];
			}
		} else {
			[self note:[NSString stringWithFormat:@"%@ has no simple identifier to compare with %@.",
			                                      node.objectType.name, node.value ?: @""]];
		}
	}
	NSMutableArray *steps = [NSMutableArray array];
	for (ORMQueryStep *step in node.steps) {
		BOOL listed = columns && step.operatorKind != ORMQueryNot;
		BOOL guarded = step.operatorKind != ORMQueryAnd || (node.combinesWithOr && [node.steps count] > 1);
		_guarded += guarded ? 1 : 0;
		NSString *predicate = [self predicateForStep:step entity:entity prefix:prefix path:path columns:listed];
		_guarded -= guarded ? 1 : 0;
		if (step.operatorKind == ORMQueryMaybe) {
			continue;
		}
		if (predicate == nil) {
			continue;
		}
		[steps addObject:step.operatorKind == ORMQueryNot ? [NSString stringWithFormat:@"NOT (%@)", predicate]
		                                                  : predicate];
	}
	NSString *combined = ORMJoined(steps, node.combinesWithOr ? @"OR" : @"AND");
	if (combined != nil) {
		[parts addObject:combined];
	}
	return ORMJoined(parts, @"AND");
}

- (NSString *)predicateForStep:(ORMQueryStep *)step
                        entity:(ORMCDEntity *)entity
                        prefix:(NSString *)prefix
                          path:(NSString *)path
                       columns:(BOOL)columns
{
	if ([step isSubtyping]) {
		return [self subtypeStep:step entity:entity prefix:prefix path:path columns:columns];
	}
	if ([step.nodes count] == 0) {
		/* A unary: its attribute is true. */
		for (ORMRole *role in step.factType.roles) {
			ORMCDProperty *property = role != step.entryRole ? [_places propertyOf:entity source:role.identifier] : nil;
			if ([property isKindOfClass:[ORMCDAttribute class]]) {
				return [NSString stringWithFormat:@"%@%@ == YES", prefix, property.name];
			}
		}
		[self note:[NSString stringWithFormat:@"\"%@\" maps to no attribute of %@.",
		                                      [[step.factType primaryReading] expandedText] ?: step.factType.name,
		                                      entity.name]];
		return nil;
	}
	if ([step.nodes count] == 1) {
		ORMQueryNode *node = [step.nodes firstObject];
		ORMCDProperty *property = [_places propertyOf:entity source:node.role.identifier];
		if (property != nil) {
			return [self binaryStep:step node:node property:property prefix:prefix path:path columns:columns];
		}
		/* Absorbed: its parts are the entity's own properties. */
		if ([[_places absorbedParts:node.role.identifier on:entity] count] > 0) {
			return [self absorbed:node base:node.role.identifier entity:entity prefix:prefix path:path
			              columns:columns];
		}
	}
	return [self entityStep:step entity:entity prefix:prefix path:path columns:columns];
}

#pragma mark Absorbed object types

/* An object type absorbed into the entity as properties whose traces start
 * with the base: a step to one of its parts is that property; a step on to
 * another entity that absorbs it too is a join. */
- (NSString *)absorbed:(ORMQueryNode *)node
                  base:(NSString *)base
                entity:(ORMCDEntity *)entity
                prefix:(NSString *)prefix
                  path:(NSString *)path
               columns:(BOOL)columns
{
	NSArray *parts = [_places absorbedParts:base on:entity];
	if (node.comparison != nil || node.label != nil) {
		[self note:[NSString stringWithFormat:@"%@ is absorbed: it has no one value to compare or correlate.",
		                                      node.objectType.name]];
	}
	if (columns && node.isProjected) {
		[self column:node keyPath:[self keyPath:path adding:[(ORMCDProperty *)[[parts firstObject] lastObject] name]]
		  identifier:nil];
	}
	NSMutableArray *conditions = [NSMutableArray array];
	for (ORMQueryStep *step in node.steps) {
		ORMQueryNode *next = [step.nodes firstObject];
		if ([step.nodes count] != 1 || step.operatorKind == ORMQueryMaybe) {
			continue;
		}
		NSString *partBase = [base stringByAppendingFormat:@"/%@", next.role.identifier];
		ORMCDProperty *part = [_places propertyOf:entity source:partBase];
		NSString *condition = nil;
		_guarded += step.operatorKind == ORMQueryNot ? 1 : 0;
		if (part != nil) {
			condition = [self binaryStep:step node:next property:part prefix:prefix path:path columns:columns];
		} else if ([[_places absorbedParts:partBase on:entity] count] > 0) {
			condition = [self absorbed:next base:partBase entity:entity prefix:prefix path:path columns:columns];
		} else {
			condition = [self join:step node:next from:base entity:entity prefix:prefix];
		}
		_guarded -= step.operatorKind == ORMQueryNot ? 1 : 0;
		if (condition != nil) {
			[conditions addObject:step.operatorKind == ORMQueryNot ? [NSString stringWithFormat:@"NOT (%@)", condition]
			                                                       : condition];
		}
	}
	if ([conditions count] == 0) {
		/* Played: its parts are there. */
		return [NSString stringWithFormat:@"%@%@ != nil", prefix,
		                                  [(ORMCDProperty *)[[parts firstObject] lastObject] name]];
	}
	return ORMJoined(conditions, @"AND");
}

/* Through an absorbed object type to an entity that absorbs it too: the
 * entity is fetched first, and its parts' values are what the fetched
 * object's must equal. */
- (NSString *)join:(ORMQueryStep *)step
              node:(ORMQueryNode *)node
              from:(NSString *)base
            entity:(ORMCDEntity *)entity
            prefix:(NSString *)prefix
{
	ORMCDEntity *joined = [_places entityOf:node.objectType];
	NSString *joinedBase = step.entryRole.identifier;
	NSArray *ours = [_places absorbedParts:base on:entity];
	NSArray *theirs = joined != nil ? [_places absorbedParts:joinedBase on:joined] : @[];
	NSMutableArray *pairs = [NSMutableArray array];
	for (NSArray *part in ours) {
		for (NSArray *their in theirs) {
			if ([[part firstObject] isEqualToString:[their firstObject]]) {
				[pairs addObject:@[ [prefix stringByAppendingString:[(ORMCDProperty *)[part lastObject] name]],
				                    [(ORMCDProperty *)[their lastObject] name] ]];
			}
		}
	}
	NSString *what = [[step.factType primaryReading] expandedText] ?: step.factType.name;
	if (joined == nil || [pairs count] == 0 || [pairs count] != [ours count]) {
		[self note:[NSString stringWithFormat:@"\"%@\" joins on parts %@ does not have as %@ does.", what,
		                                      joined.name ?: node.objectType.name, entity.name]];
		return nil;
	}
	if (_guarded > 0 || [_scope count] > 0) {
		[self note:[NSString stringWithFormat:@"\"%@\" joins %@ with %@ inside a not, an or or a subquery, "
		                                      @"which takes nested fetches: not made yet.",
		                                      what, entity.name, joined.name]];
		return nil;
	}
	/* What the joined objects must be, said from them. */
	NSMutableArray *scope = _scope;
	_scope = [NSMutableArray array];
	NSString *predicate = [self predicateFor:node entity:joined prefix:@"" path:@"" columns:NO];
	_scope = scope;
	ORMQueryJoin *join = [[ORMQueryJoin alloc] init];
	join.name = [NSString stringWithFormat:@"join%lu", (unsigned long)[_joins count] + 1];
	join.entityName = joined.name;
	join.predicateFormat = predicate ?: @"TRUEPREDICATE";
	join.pairs = pairs;
	[_joins addObject:join];
	return nil;
}

- (NSString *)counted:(NSString *)subquery step:(ORMQueryStep *)step
{
	NSString *operator = step != nil ? [ORMPredicateOperators() objectForKey:step.countComparison ?: @""] : nil;
	if (operator != nil) {
		return [NSString stringWithFormat:@"%@.@count %@ %lu", subquery, operator, (unsigned long)step.countValue];
	}
	return [subquery stringByAppendingString:@".@count > 0"];
}

/* The key path from an object of the entity at the node to the target, one
 * of the nodes below it: through to-ones, to an attribute or an entity's
 * identifier. nil when there is no such path. */
- (NSString *)keyPathFrom:(ORMQueryNode *)node entity:(ORMCDEntity *)entity to:(ORMQueryNode *)target
{
	if (node == target) {
		ORMCDAttribute *identifier = entity != nil ? [_places identifierOf:node.objectType on:entity] : nil;
		return identifier != nil ? identifier.name : nil;
	}
	for (ORMQueryStep *step in node.steps) {
		for (ORMQueryNode *next in step.nodes) {
			ORMCDProperty *property = [_places propertyOf:entity source:next.role.identifier];
			if ([property isKindOfClass:[ORMCDAttribute class]] && next == target) {
				return property.name;
			}
			if ([property isKindOfClass:[ORMCDRelationship class]] && !((ORMCDRelationship *)property).toMany) {
				NSString *rest = [self keyPathFrom:next
				                            entity:[_coreData entityNamed:((ORMCDRelationship *)property).destination]
				                                to:target];
				if (rest != nil) {
					return [NSString stringWithFormat:@"%@.%@", property.name, rest];
				}
			}
		}
	}
	return nil;
}

/* Whether what is below the node asks more of it than that it is there:
 * a condition, a label, a not, an alternative, a count. */
- (BOOL)narrows:(ORMQueryNode *)node
{
	if (node.comparison != nil || node.label != nil || node.combinesWithOr) {
		return YES;
	}
	for (ORMQueryStep *step in node.steps) {
		if (step.operatorKind != ORMQueryAnd || step.countComparison != nil) {
			return YES;
		}
		for (ORMQueryNode *next in step.nodes) {
			if ([self narrows:next]) {
				return YES;
			}
		}
	}
	return NO;
}

/* The step's aggregate over the objects of the collection ("employees"),
 * each of the member entity: "employees.@sum.salary.usd > 1000000". Over
 * them all: Core Data's store aggregates no subquery, so conditions below
 * the step do not narrow it, and are noted. */
- (NSString *)aggregated:(NSString *)subquery
              collection:(NSString *)collection
                  member:(ORMCDEntity *)member
                 through:(NSString *)firstHop
                    from:(ORMQueryNode *)start
                    step:(ORMQueryStep *)step
{
	if (step == nil || step.countComparison == nil || step.aggregate == ORMQueryCount) {
		return [self counted:subquery step:step];
	}
	NSString *function = [@[ @"@count", @"@sum", @"@avg", @"@max", @"@min" ] objectAtIndex:(NSUInteger)step.aggregate];
	/* From the member, or from where its first hop leads. */
	ORMCDProperty *hop = firstHop != nil ? [member propertyNamed:firstHop] : nil;
	ORMCDEntity *startEntity = [hop isKindOfClass:[ORMCDRelationship class]]
		? [_coreData entityNamed:((ORMCDRelationship *)hop).destination] : (hop == nil ? member : nil);
	NSString *rest = startEntity != nil ? [self keyPathFrom:start entity:startEntity to:step.aggregateNode] : nil;
	if (rest == nil && firstHop != nil && start == step.aggregateNode) {
		rest = @"";
	}
	NSString *path = firstHop != nil ? ([rest length] > 0 ? [NSString stringWithFormat:@"%@.%@", firstHop, rest] : firstHop)
	                                 : rest;
	NSString *operator = [ORMPredicateOperators() objectForKey:step.countComparison];
	if (path == nil || operator == nil) {
		[self note:[NSString stringWithFormat:@"%@(%@) is of nothing one key path reaches from %@.",
		                                      [ORMQuery nameOfAggregate:step.aggregate],
		                                      [step.aggregateNode designation], collection]];
		return [self counted:subquery step:nil];
	}
	if ([self narrows:start] || (start != step.aggregateNode && [self narrows:step.aggregateNode])) {
		[self note:[NSString stringWithFormat:@"%@(%@) is over every %@, not only those meeting the conditions below "
		                                      @"it: Core Data aggregates no subquery.",
		                                      [ORMQuery nameOfAggregate:step.aggregate],
		                                      [step.aggregateNode designation], start.objectType.name]];
	}
	NSString *value = step.aggregateValue ?: @"";
	NSScanner *scanner = [NSScanner scannerWithString:value];
	double number = 0;
	BOOL numeric = [scanner scanDouble:&number] && [scanner isAtEnd];
	return [NSString stringWithFormat:@"%@.%@.%@ %@ %@", collection, function, path, operator,
	                                  numeric ? value : ORMPredicateString(value)];
}

/* Through a binary to an attribute or a relationship of the entity. */
- (NSString *)binaryStep:(ORMQueryStep *)step
                    node:(ORMQueryNode *)node
                property:(ORMCDProperty *)property
                  prefix:(NSString *)prefix
                    path:(NSString *)path
                 columns:(BOOL)columns
{
	NSString *key = [prefix stringByAppendingString:property.name];
	NSString *nodePath = [self keyPath:path adding:property.name];
	if ([property isKindOfClass:[ORMCDAttribute class]]) {
		ORMCDAttribute *attribute = (ORMCDAttribute *)property;
		if (columns) {
			[self column:node keyPath:nodePath identifier:nil];
		}
		if ([node.steps count] > 0) {
			[self note:[NSString stringWithFormat:@"%@ is an attribute: what is said of it further is left out.",
			                                      node.objectType.name]];
		}
		if (step != nil && step.countComparison != nil) {
			[self note:[NSString stringWithFormat:@"%@ is one attribute: it is not counted.", node.objectType.name]];
		}
		NSMutableArray *parts = [NSMutableArray arrayWithArray:[self correlationsOf:node expression:key]];
		[self reached:node expression:key path:nodePath];
		NSString *condition = node.comparison != nil && node.comparedNode == nil
			? [self comparing:key node:node attribute:attribute] : nil;
		if (condition != nil) {
			[parts addObject:condition];
		}
		return ORMJoined(parts, @"AND") ?: [NSString stringWithFormat:@"%@ != nil", key];
	}
	ORMCDRelationship *relationship = (ORMCDRelationship *)property;
	ORMCDEntity *destination = [_coreData entityNamed:relationship.destination];
	if (!relationship.toMany) {
		if (step != nil && step.countComparison != nil) {
			[self note:[NSString stringWithFormat:@"%@ is one at most: it is not counted.", node.objectType.name]];
		}
		NSString *inner = [self predicateFor:node entity:destination prefix:[key stringByAppendingString:@"."]
		                                path:nodePath
		                             columns:columns];
		/* A key path through nothing meets no condition: the condition
		 * says the relationship is set. */
		return inner ?: [NSString stringWithFormat:@"%@ != nil", key];
	}
	NSString *variable = [self nextVariable];
	[_scope addObject:variable];
	NSString *inner = [self predicateFor:node entity:destination prefix:[variable stringByAppendingString:@"."]
	                                path:nodePath
	                             columns:columns];
	[_scope removeLastObject];
	/* Nothing asked of them: how many there are. */
	NSString *subquery = inner != nil ? [NSString stringWithFormat:@"SUBQUERY(%@, %@, %@)", key, variable, inner] : key;
	return [self aggregated:subquery collection:key member:destination through:nil from:node step:step];
}

/* Through a fact type that is an entity of its own (an objectification,
 * or a fact type of more than two roles): from the entity to it, and on
 * from it to the other roles' players. */
- (NSString *)entityStep:(ORMQueryStep *)step
                  entity:(ORMCDEntity *)entity
                  prefix:(NSString *)prefix
                    path:(NSString *)path
                 columns:(BOOL)columns
{
	ORMFactType *fact = step.factType;
	NSString *back = [fact.identifier stringByAppendingFormat:@".%@", step.entryRole.identifier];
	ORMCDProperty *property = [_places propertyOf:entity source:back];
	ORMCDRelationship *relationship = [property isKindOfClass:[ORMCDRelationship class]] ? (ORMCDRelationship *)property
	                                                                                      : nil;
	ORMCDEntity *factEntity = relationship != nil ? [_coreData entityNamed:relationship.destination] : nil;
	if (factEntity == nil) {
		ORMQueryNode *node = [step.nodes count] == 1 ? [step.nodes firstObject] : nil;
		if (node != nil && node.objectType.kind == ORMEntityType && [_places entityOf:node.objectType] == nil) {
			/* Its parts are attributes of each entity that uses it: the
			 * join is on their values, across entities no relationship
			 * connects. */
			[self note:[NSString stringWithFormat:@"%@ is absorbed into what uses it, so going through it joins on "
			                                      @"its parts, which takes a second fetch: not made yet. Map %@ as "
			                                      @"an entity to query through it.",
			                                      node.objectType.name, node.objectType.name]];
		} else {
			[self note:[NSString stringWithFormat:@"\"%@\" maps to nothing %@ reaches.",
			                                      [[fact primaryReading] expandedText] ?: fact.name, entity.name]];
		}
		return nil;
	}
	NSString *variable = relationship.toMany ? [self nextVariable] : nil;
	NSString *innerPrefix = variable != nil ? [variable stringByAppendingString:@"."]
	                                        : [prefix stringByAppendingFormat:@"%@.", relationship.name];
	NSString *factPath = [self keyPath:path adding:relationship.name];
	if (variable != nil) {
		[_scope addObject:variable];
	}
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMQueryNode *node in step.nodes) {
		ORMCDProperty *rolePlace = [_places propertyOf:factEntity source:node.role.identifier];
		if (rolePlace == nil) {
			[self note:[NSString stringWithFormat:@"%@'s role in \"%@\" maps to nothing.", node.objectType.name,
			                                      [[fact primaryReading] expandedText] ?: fact.name]];
			continue;
		}
		/* Counted, the fact type's entity is; not each role in it. */
		NSString *part = [self binaryStep:nil node:node property:rolePlace prefix:innerPrefix path:factPath
		                          columns:columns];
		/* The role is played: a mandatory one says nothing more. */
		if (part != nil && (node.comparison != nil || [node.steps count] > 0 || node.label != nil)) {
			[parts addObject:part];
		}
	}
	if (variable != nil) {
		[_scope removeLastObject];
	}
	NSString *inner = ORMJoined(parts, @"AND");
	if (variable == nil) {
		return inner ?: [NSString stringWithFormat:@"%@%@ != nil", prefix, relationship.name];
	}
	NSString *collection = [prefix stringByAppendingString:relationship.name];
	NSString *subquery = inner != nil ? [NSString stringWithFormat:@"SUBQUERY(%@, %@, %@)", collection, variable, inner]
	                                  : collection;
	/* Through the role of the fact type's entity the aggregated node is
	 * at, or below. */
	ORMQueryNode *start = nil;
	NSString *firstHop = nil;
	for (ORMQueryNode *node in step.nodes) {
		for (ORMQueryNode *at = step.aggregateNode; at != nil && start == nil; at = at.step.parent) {
			if (at == node) {
				start = node;
				firstHop = [[_places propertyOf:factEntity source:node.role.identifier] name];
			}
		}
	}
	return [self aggregated:subquery collection:collection member:factEntity through:firstHop from:start step:step];
}

/* To a subtype: the object is of its entity; to a supertype: it is. */
- (NSString *)subtypeStep:(ORMQueryStep *)step
                   entity:(ORMCDEntity *)entity
                   prefix:(NSString *)prefix
                     path:(NSString *)path
                  columns:(BOOL)columns
{
	ORMQueryNode *node = [step.nodes firstObject];
	if (node == nil) {
		return nil;
	}
	ORMCDEntity *target = [_places entityOf:node.objectType];
	NSString *test = nil;
	if (step.entryRole.isSupertypeMetaRole && [prefix length] == 0 && target != nil
	    && [_places entity:_fetched inherits:target]) {
		/* What is fetched is one. */
	} else if (step.entryRole.isSupertypeMetaRole) {
		if (target == nil || target == entity || ![_places entity:target inherits:entity]) {
			[self note:[NSString stringWithFormat:@"%@ is no entity of its own, so being one is not tested.",
			                                      node.objectType.name]];
		} else {
			NSMutableArray *names = [NSMutableArray array];
			for (NSString *name in [_places namesOf:target]) {
				[names addObject:ORMPredicateString(name)];
			}
			test = [NSString stringWithFormat:@"%@entity.name IN {%@}", prefix, [names componentsJoinedByString:@", "]];
		}
	}
	NSString *inner = [self predicateFor:node entity:target ?: entity prefix:prefix path:path columns:columns];
	return ORMJoined([NSArray arrayWithObjects:test ?: inner, test != nil ? inner : nil, nil], @"AND");
}

#pragma mark Source

/* A format string as an Objective-C literal. */
static NSString *
ORMSourceLiteral(NSString *format)
{
	return [[[format stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
		stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]
		stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
}

- (NSString *)objectiveCSource
{
	if (_entityName == nil) {
		return @"";
	}
	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"/* %@ */\n", [_query.name stringByReplacingOccurrencesOfString:@"*/" withString:@"* /"]];
	/* The joined objects first: their parts are what the request matches. */
	for (ORMQueryJoin *join in _joins) {
		[out appendFormat:@"NSFetchRequest *%@ = [NSFetchRequest fetchRequestWithEntityName:@\"%@\"];\n", join.name,
		                  join.entityName];
		if (![join.predicateFormat isEqualToString:@"TRUEPREDICATE"]) {
			[out appendFormat:@"%@.predicate = [NSPredicate predicateWithFormat:@\"%@\"];\n", join.name,
			                  ORMSourceLiteral(join.predicateFormat)];
		}
		NSMutableArray *formats = [NSMutableArray array];
		NSMutableArray *values = [NSMutableArray array];
		for (NSArray *pair in join.pairs) {
			[formats addObject:[NSString stringWithFormat:@"%@ == %%@", ORMSourceLiteral([pair firstObject])]];
			[values addObject:[NSString stringWithFormat:@"[object valueForKeyPath:@\"%@\"]", [pair lastObject]]];
		}
		[out appendFormat:@"NSMutableArray *%@Matches = [NSMutableArray array];\n"
		                  @"for (NSManagedObject *object in [context executeFetchRequest:%@ error:NULL]) {\n"
		                  @"    [%@Matches addObject:[NSPredicate predicateWithFormat:@\"%@\", %@]];\n"
		                  @"}\n",
		                  join.name, join.name, join.name,
		                  [formats componentsJoinedByString:@" AND "],
		                  [values componentsJoinedByString:@", "]];
	}
	[out appendFormat:@"NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@\"%@\"];\n", _entityName];
	NSString *own = [NSString stringWithFormat:@"[NSPredicate predicateWithFormat:@\"%@\"]", ORMSourceLiteral(_predicateFormat)];
	if ([_joins count] > 0) {
		NSMutableArray *conjuncts = [NSMutableArray arrayWithObject:own];
		for (ORMQueryJoin *join in _joins) {
			[conjuncts addObject:[NSString stringWithFormat:@"[NSCompoundPredicate orPredicateWithSubpredicates:%@Matches]",
			                                                join.name]];
		}
		[out appendFormat:@"request.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[\n    %@ ]];\n",
		                  [conjuncts componentsJoinedByString:@",\n    "]];
	} else if (![_predicateFormat isEqualToString:@"TRUEPREDICATE"]) {
		[out appendFormat:@"request.predicate = %@;\n", own];
	}
	if ([_sorts count] > 0) {
		NSMutableArray *sorts = [NSMutableArray array];
		for (NSSortDescriptor *sort in _sorts) {
			[sorts addObject:[NSString stringWithFormat:@"[NSSortDescriptor sortDescriptorWithKey:@\"%@\" ascending:%@]",
			                                            [sort key], [sort ascending] ? @"YES" : @"NO"]];
		}
		[out appendFormat:@"request.sortDescriptors = @[ %@ ];\n", [sorts componentsJoinedByString:@", "]];
	}
	if ([_columns count] > 0) {
		[out appendString:@"/* Listed, from each object fetched:\n"];
		for (ORMQueryColumn *column in _columns) {
			[out appendFormat:@" *   %@: [object valueForKeyPath:@\"%@\"]\n", column.title,
			                  column.identifierKeyPath ?: column.keyPath];
		}
		[out appendString:@" */\n"];
	}
	return out;
}

@end
