/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryFetch.h"

@interface ORMQueryColumn ()
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSString *nodeId;
@property (nonatomic, readwrite, copy) NSString *keyPath;
@property (nonatomic, readwrite, copy) NSString *identifierKeyPath;
@end

@implementation ORMQueryColumn
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
	NSMutableDictionary<NSString *, NSArray *> *_bySource;
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
		_bySource = [NSMutableDictionary dictionary];
		for (ORMCDEntity *entity in coreData.entities) {
			for (ORMCDProperty *property in [entity properties]) {
				if (property.source != nil) {
					[_bySource setObject:@[ entity, property ] forKey:property.source];
				}
			}
		}
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

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
}

- (BOOL)isComplete
{
	return _entityName != nil && [_notes count] == 0;
}

#pragma mark Where things are

/* The entity an object type's instances are: its own, or its nearest
 * supertype's when it was flattened into it. */
- (ORMCDEntity *)entityOf:(ORMObjectType *)type
{
	NSMutableArray *pending = [NSMutableArray arrayWithObject:type];
	while ([pending count] > 0) {
		ORMObjectType *at = [pending objectAtIndex:0];
		[pending removeObjectAtIndex:0];
		ORMCDEntity *entity = [_coreData entityWithSource:at.identifier];
		if (entity != nil) {
			return entity;
		}
		[pending addObjectsFromArray:at.supertypes];
	}
	return nil;
}

- (BOOL)entity:(ORMCDEntity *)entity inherits:(ORMCDEntity *)ancestor
{
	for (ORMCDEntity *at = entity; at != nil; at = at.parentName != nil ? [_coreData entityNamed:at.parentName] : nil) {
		if (at == ancestor) {
			return YES;
		}
	}
	return NO;
}

/* The property traced to the source, if the entity has it (its own or an
 * ancestor's). */
- (ORMCDProperty *)propertyOf:(ORMCDEntity *)entity source:(NSString *)source
{
	NSArray *place = source != nil ? [_bySource objectForKey:source] : nil;
	if (place == nil || entity == nil || ![self entity:entity inherits:[place firstObject]]) {
		return nil;
	}
	return [place lastObject];
}

- (NSArray<NSString *> *)namesOf:(ORMCDEntity *)entity
{
	NSMutableArray *names = [NSMutableArray arrayWithObject:entity.name];
	for (NSUInteger i = 0; i < [names count]; i++) {
		for (ORMCDEntity *sub in [_coreData subentitiesOf:[names objectAtIndex:i]]) {
			[names addObject:sub.name];
		}
	}
	return names;
}

/* An entity's simple identifier attribute: its reference mode's value. */
- (ORMCDAttribute *)identifierOf:(ORMObjectType *)type on:(ORMCDEntity *)entity
{
	for (ORMRole *role in type.referenceModeFactType.roles) {
		if (role.player == type.referenceModeValueType) {
			ORMCDProperty *property = [self propertyOf:entity source:role.identifier];
			return [property isKindOfClass:[ORMCDAttribute class]] ? (ORMCDAttribute *)property : nil;
		}
	}
	/* A subtype is identified as its supertype is. */
	if (type.preferredIdentifier == nil) {
		for (ORMObjectType *supertype in type.supertypes) {
			ORMCDAttribute *identifier = [self identifierOf:supertype on:entity];
			if (identifier != nil) {
				return identifier;
			}
		}
	}
	return nil;
}

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
	ORMCDEntity *entity = root != nil ? [self entityOf:root.objectType] : nil;
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
			ORMCDEntity *subEntity = sub != nil ? [self entityOf:sub.objectType] : nil;
			if ([step isSubtyping] && step.operatorKind == ORMQueryAnd && step.entryRole.isSupertypeMetaRole
			    && subEntity != nil && subEntity != _fetched && [self entity:subEntity inherits:_fetched]) {
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
	ORMCDAttribute *identifier = [self identifierOf:node.objectType on:entity];
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
		NSString *predicate = [self predicateForStep:step entity:entity prefix:prefix path:path columns:listed];
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
			ORMCDProperty *property = role != step.entryRole ? [self propertyOf:entity source:role.identifier] : nil;
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
		ORMCDProperty *property = [self propertyOf:entity source:node.role.identifier];
		if (property != nil) {
			return [self binaryStep:step node:node property:property prefix:prefix path:path columns:columns];
		}
	}
	return [self entityStep:step entity:entity prefix:prefix path:path columns:columns];
}

- (NSString *)counted:(NSString *)subquery step:(ORMQueryStep *)step
{
	NSString *operator = step != nil ? [ORMPredicateOperators() objectForKey:step.countComparison ?: @""] : nil;
	if (operator != nil) {
		return [NSString stringWithFormat:@"%@.@count %@ %lu", subquery, operator, (unsigned long)step.countValue];
	}
	return [subquery stringByAppendingString:@".@count > 0"];
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
	return [self counted:subquery step:step];
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
	ORMCDProperty *property = [self propertyOf:entity source:back];
	ORMCDRelationship *relationship = [property isKindOfClass:[ORMCDRelationship class]] ? (ORMCDRelationship *)property
	                                                                                      : nil;
	ORMCDEntity *factEntity = relationship != nil ? [_coreData entityNamed:relationship.destination] : nil;
	if (factEntity == nil) {
		ORMQueryNode *node = [step.nodes count] == 1 ? [step.nodes firstObject] : nil;
		if (node != nil && node.objectType.kind == ORMEntityType && [self entityOf:node.objectType] == nil) {
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
		ORMCDProperty *rolePlace = [self propertyOf:factEntity source:node.role.identifier];
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
	NSString *subquery = inner != nil ? [NSString stringWithFormat:@"SUBQUERY(%@%@, %@, %@)", prefix, relationship.name,
	                                                               variable, inner]
	                                  : [prefix stringByAppendingString:relationship.name];
	return [self counted:subquery step:step];
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
	ORMCDEntity *target = [self entityOf:node.objectType];
	NSString *test = nil;
	if (step.entryRole.isSupertypeMetaRole && [prefix length] == 0 && target != nil
	    && [self entity:_fetched inherits:target]) {
		/* What is fetched is one. */
	} else if (step.entryRole.isSupertypeMetaRole) {
		if (target == nil || target == entity || ![self entity:target inherits:entity]) {
			[self note:[NSString stringWithFormat:@"%@ is no entity of its own, so being one is not tested.",
			                                      node.objectType.name]];
		} else {
			NSMutableArray *names = [NSMutableArray array];
			for (NSString *name in [self namesOf:target]) {
				[names addObject:ORMPredicateString(name)];
			}
			test = [NSString stringWithFormat:@"%@entity.name IN {%@}", prefix, [names componentsJoinedByString:@", "]];
		}
	}
	NSString *inner = [self predicateFor:node entity:target ?: entity prefix:prefix path:path columns:columns];
	return ORMJoined([NSArray arrayWithObjects:test ?: inner, test != nil ? inner : nil, nil], @"AND");
}

#pragma mark Source

- (NSString *)objectiveCSource
{
	if (_entityName == nil) {
		return @"";
	}
	NSString *format = [[[_predicateFormat stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
		stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]
		stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"/* %@ */\n", [_query.name stringByReplacingOccurrencesOfString:@"*/" withString:@"* /"]];
	[out appendFormat:@"NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@\"%@\"];\n", _entityName];
	if (![_predicateFormat isEqualToString:@"TRUEPREDICATE"]) {
		[out appendFormat:@"request.predicate = [NSPredicate predicateWithFormat:@\"%@\"];\n", format];
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
