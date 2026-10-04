/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlanner.h"
#import "ORMQueryPlaces.h"

/* Where the planning stands: an object or a value, as a plan path (from a
 * variable, or from the object read), and the same reached from the object
 * read, as the mapped properties it went through. */
@interface ORMPlannerPlace : NSObject
@property (nonatomic, strong) ORMPlanPath *path;
@property (nonatomic, copy) NSArray<ORMCDProperty *> *trail;
/* An object of the entity; nil for a value. */
@property (nonatomic, strong) ORMCDEntity *entity;
/* The plan it was reached in: 0 the query's, 1 a join's in it, ... */
@property (nonatomic) NSUInteger level;
@end

@implementation ORMPlannerPlace

+ (instancetype)variable:(NSString *)variable entity:(ORMCDEntity *)entity trail:(NSArray *)trail
{
	ORMPlannerPlace *place = [[self alloc] init];
	place.path = [ORMPlanPath pathFrom:variable keys:@[]];
	place.trail = trail ?: @[];
	place.entity = entity;
	return place;
}

- (ORMPlannerPlace *)adding:(ORMCDProperty *)property entity:(ORMCDEntity *)entity
{
	ORMPlannerPlace *place = [[ORMPlannerPlace alloc] init];
	place.path = [self.path pathByAddingKey:property.name];
	place.trail = [self.trail arrayByAddingObject:property];
	place.entity = entity;
	return place;
}

- (ORMPlannerPlace *)castTo:(ORMCDEntity *)entity
{
	ORMPlannerPlace *place = [[ORMPlannerPlace alloc] init];
	place.path = [self.path pathByAddingCast:entity.name];
	place.trail = self.trail;
	place.entity = entity;
	return place;
}

- (BOOL)isRead
{
	return self.path.variable == nil && [self.path.steps count] == 0;
}

/* The trail's names: a path from the object read. */
- (ORMPlanPath *)pathFromRead
{
	return [ORMPlanPath pathFrom:nil keys:[self.trail valueForKey:@"name"]];
}

@end

static ORMPlanCondition *
ORMAllOf(NSArray<ORMPlanCondition *> *parts)
{
	return [parts count] == 0 ? nil : ([parts count] == 1 ? [parts firstObject] : [ORMPlanCondition all:parts]);
}

static ORMPlanCondition *
ORMAnyOf(NSArray<ORMPlanCondition *> *parts)
{
	return [parts count] == 0 ? nil : ([parts count] == 1 ? [parts firstObject] : [ORMPlanCondition any:parts]);
}

@implementation ORMQueryPlanner
{
	ORMQueryPlaces *_places;
	/* The query being planned, and what is known of it so far. */
	ORMQuery *_query;
	ORMCDEntity *_read;
	NSMutableArray<NSString *> *_notes;
	NSUInteger _variables;
	/* The variables bound where the planning is. */
	NSMutableArray<NSString *> *_scope;
	NSMutableDictionary<NSString *, ORMPlannerPlace *> *_reached;
	NSMutableArray<NSArray *> *_columns;
	/* How deep in joins the planning is, and what each enclosing plan's
	 * object read is called inside the ones in it: o1, o2. */
	NSUInteger _level;
	NSMutableArray<NSString *> *_outerNames;
	NSUInteger _outers;
	/* The sets the plan names, in the order they are made: one made inside
	 * another's planning comes before it. */
	NSMutableArray<ORMPlanDefinition *> *_definitions;
}

- (instancetype)initWithCoreData:(ORMCDModel *)coreData
{
	if ((self = [super init])) {
		_coreData = coreData;
		_places = [[ORMQueryPlaces alloc] initWithCoreData:coreData];
	}
	return self;
}

- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	return [self initWithCoreData:[[[ORMCoreDataMapper alloc] initWithModel:model mapping:mapping] map]];
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
	return [NSString stringWithFormat:@"x%lu", (unsigned long)_variables];
}

- (BOOL)inScope:(ORMPlannerPlace *)place
{
	return place.path.variable == nil || [_scope containsObject:place.path.variable];
}

- (void)reach:(ORMQueryNode *)node place:(ORMPlannerPlace *)place
{
	place.level = _level;
	[_reached setObject:place forKey:node.identifier];
}

/* A place reached before, as a path from here: one an enclosing plan read
 * is from its object, which is a variable here. */
- (ORMPlanPath *)pathOf:(ORMPlannerPlace *)place
{
	if (place.level < _level && place.path.variable == nil) {
		return [ORMPlanPath pathFrom:[_outerNames objectAtIndex:place.level] steps:place.path.steps];
	}
	return place.path;
}

- (ORMCDEntity *)destinationOf:(ORMCDRelationship *)relationship
{
	return [_coreData entityNamed:relationship.destination];
}

#pragma mark Planning

- (ORMQueryPlan *)planForQuery:(ORMQuery *)query
{
	_query = query;
	_notes = [NSMutableArray array];
	_variables = 0;
	_scope = [NSMutableArray array];
	_reached = [NSMutableDictionary dictionary];
	_columns = [NSMutableArray array];
	_level = 0;
	_outerNames = [NSMutableArray array];
	_outers = 0;
	_definitions = [NSMutableArray array];
	ORMQueryNode *root = query.root;
	ORMCDEntity *entity = root != nil ? [_places entityOf:root.objectType] : nil;
	if (entity == nil) {
		[self note:[NSString stringWithFormat:@"%@ is no entity, so there is nothing to read.",
		                                      root.objectType.name ?: @"The query's object type"]];
		return [ORMQueryPlan planReading:nil where:nil columns:@[] sorts:@[] notes:_notes];
	}
	/* Every result is of the subtype the root's required steps go down to:
	 * read as one, its own properties are there. */
	_read = entity;
	for (ORMQueryNode *at = root; at != nil && !at.combinesWithOr;) {
		ORMQueryNode *next = nil;
		for (ORMQueryStep *step in at.steps) {
			ORMQueryNode *sub = [step.nodes firstObject];
			ORMCDEntity *subEntity = sub != nil ? [_places entityOf:sub.objectType] : nil;
			if ([step isSubtyping] && step.operatorKind == ORMQueryAnd && step.entryRole.isSupertypeMetaRole
			    && subEntity != nil && subEntity != _read && [_places entity:subEntity inherits:_read]) {
				_read = subEntity;
				next = sub;
				break;
			}
		}
		at = next;
	}
	if (!query.isComplete) {
		[self note:@"Something the query goes through is no longer in the model, and is left out."];
	}
	ORMPlanCondition *condition = [self conditionFor:root entity:entity
	                                              at:[ORMPlannerPlace variable:nil entity:_read trail:@[]] columns:YES];
	/* Each column titled by its node, with its label ("Employee2"); two
	 * still the same say whose they are ("EmployeeName of Employee2"). */
	NSCountedSet *titles = [[NSCountedSet alloc] init];
	for (NSArray *column in _columns) {
		[titles addObject:[[column firstObject] designation]];
	}
	NSMutableArray *columns = [NSMutableArray array];
	for (NSArray *column in _columns) {
		ORMQueryNode *node = [column firstObject];
		ORMPlannerPlace *place = [column objectAtIndex:1];
		id identifier = [column lastObject];
		NSString *title = [node designation];
		ORMQueryNode *above = node.step.parent;
		if ([titles countForObject:title] > 1 && above != nil) {
			title = [NSString stringWithFormat:@"%@ of %@", title, [above designation]];
		}
		[columns addObject:[ORMPlanColumn columnTitled:title node:node.identifier path:place.path
		                                         trail:[place.trail valueForKey:@"name"]
		                                    identifier:identifier != [NSNull null] ? [identifier name] : nil]];
	}
	return [ORMQueryPlan planReading:_read.name where:condition columns:columns sorts:[self sorts] notes:_notes
	                     definitions:_definitions];
}

/* A set named in the plan, its plan reading the entity. */
- (ORMPlanDefinition *)define:(NSString *)prefix plan:(ORMQueryPlan *)plan
{
	ORMPlanDefinition *definition = [ORMPlanDefinition definitionNamed:[NSString stringWithFormat:@"%@%lu", prefix,
	                                                                                               (unsigned long)[_definitions count] + 1]
	                                                              plan:plan];
	[_definitions addObject:definition];
	return definition;
}

/* Each sorted node's column, by its identifier or value, through to-ones. */
- (NSArray<ORMPlanSort *> *)sorts
{
	NSMutableArray *sorts = [NSMutableArray array];
	for (ORMQueryNode *node in [_query nodes]) {
		if (node.sortOrder == ORMQueryUnsorted) {
			continue;
		}
		NSArray *column = nil;
		for (NSArray *each in _columns) {
			if ([[[each firstObject] identifier] isEqualToString:node.identifier]) {
				column = each;
			}
		}
		ORMPlannerPlace *place = [column objectAtIndex:1];
		id identifier = [column lastObject];
		BOOL one = column != nil && (place.entity == nil || identifier != [NSNull null]);
		for (ORMCDProperty *property in place.trail) {
			one = one && !([property isKindOfClass:[ORMCDRelationship class]] && ((ORMCDRelationship *)property).toMany);
		}
		if (!one) {
			[self note:[NSString stringWithFormat:@"%@ is sorted by, but %@.", [node designation],
			                                      column == nil ? @"not listed" : @"not one value for each result"]];
			continue;
		}
		ORMPlanPath *path = [place pathFromRead];
		if (place.entity != nil) {
			path = [path pathByAddingKey:[identifier name]];
		}
		[sorts addObject:[ORMPlanSort sortBy:path ascending:node.sortOrder == ORMQueryAscending]];
	}
	return sorts;
}

- (void)column:(ORMQueryNode *)node place:(ORMPlannerPlace *)place identifier:(ORMCDAttribute *)identifier
{
	if (node.isProjected) {
		[_columns addObject:@[ node, place, identifier ?: [NSNull null] ]];
	}
}

- (ORMPlanValue *)constant:(NSString *)text attribute:(ORMCDAttribute *)attribute
{
	return [ORMPlanValue constant:text type:attribute.attributeType ?: @"String"];
}

#pragma mark Correlating

/* The place compared with the node reached before: directly, where that is
 * still in scope; else among what its trail reaches from the object read. */
- (ORMPlanCondition *)relate:(ORMPlannerPlace *)place comparison:(NSString *)comparison to:(ORMQueryNode *)other
{
	ORMPlannerPlace *reference = [_reached objectForKey:other.identifier];
	BOOL known = [@[ @"=", @"<>", @"<", @"<=", @">", @">=" ] containsObject:comparison ?: @""];
	if (reference == nil || !known) {
		[self note:[NSString stringWithFormat:@"%@ is compared with %@ before the query reaches it.", place.path,
		                                      [other designation]]];
		return nil;
	}
	if (reference.level > _level) {
		[self note:[NSString stringWithFormat:@"%@ is compared with %@, which is reached in a join below it.", place.path,
		                                      [other designation]]];
		return nil;
	}
	BOOL equality = [comparison isEqualToString:@"="] || [comparison isEqualToString:@"<>"];
	ORMPlanCondition *related = nil;
	if ([self inScope:reference]) {
		if (place.entity == nil) {
			return [ORMPlanCondition compare:[ORMPlanValue valueAtPath:place.path] comparison:comparison
			                            with:[ORMPlanValue valueAtPath:[self pathOf:reference]]];
		}
		if (!equality) {
			[self note:[NSString stringWithFormat:@"%@ %@ %@ compares objects: only = and <> can.", place.path, comparison,
			                                      [other designation]]];
			return nil;
		}
		related = [ORMPlanCondition same:place.path as:[self pathOf:reference]];
	} else {
		if (other.comparison != nil || [other.steps count] > 0) {
			[self note:[NSString stringWithFormat:@"%@ is taken as any %@ the path reaches, not only those meeting its "
			                                      @"conditions.",
			                                      [other designation], other.objectType.name]];
		}
		if (!equality) {
			[self note:[NSString stringWithFormat:@"%@ %@ %@ compares with many: only = and <> can.", place.path,
			                                      comparison, [other designation]]];
			return nil;
		}
		/* The trail is from the object read where the node was reached:
		 * an enclosing plan's, here a variable. */
		ORMPlanPath *base = reference.level < _level
			? [ORMPlanPath pathFrom:[_outerNames objectAtIndex:reference.level] keys:@[]] : nil;
		related = [ORMPlanCondition among:place.path trail:[reference.trail valueForKey:@"name"] from:base];
	}
	return [comparison isEqualToString:@"<>"] ? [ORMPlanCondition not:related] : related;
}

/* Being the same as an earlier node of its label, and the comparison with
 * another node. */
- (NSArray<ORMPlanCondition *> *)correlationsOf:(ORMQueryNode *)node place:(ORMPlannerPlace *)place
{
	NSMutableArray *parts = [NSMutableArray array];
	ORMQueryNode *first = [_query firstOccurrenceOf:node];
	if (first != node) {
		ORMPlanCondition *same = [self relate:place comparison:@"=" to:first];
		if (same != nil) {
			[parts addObject:same];
		}
	}
	if (node.comparedNode != nil) {
		ORMPlanCondition *compared = [self relate:place comparison:node.comparison to:node.comparedNode];
		if (compared != nil) {
			[parts addObject:compared];
		}
	}
	return parts;
}

#pragma mark Nodes and steps

/* What the node and its steps require of the object at the place. */
- (ORMPlanCondition *)conditionFor:(ORMQueryNode *)node entity:(ORMCDEntity *)entity at:(ORMPlannerPlace *)at
                           columns:(BOOL)columns
{
	NSMutableArray *parts = [NSMutableArray array];
	ORMCDAttribute *identifier = [_places identifierOf:node.objectType on:entity];
	if (columns) {
		[self column:node place:at identifier:identifier];
	}
	NSArray *correlations = [self correlationsOf:node place:at];
	[self reach:node place:at];
	[parts addObjectsFromArray:correlations];
	if (node.comparison != nil && node.comparedNode == nil) {
		if (identifier != nil) {
			[parts addObject:[ORMPlanCondition compare:[ORMPlanValue valueAtPath:[at.path pathByAddingKey:identifier.name]]
			                                comparison:node.comparison
			                                      with:[self constant:node.value attribute:identifier]]];
		} else {
			[self note:[NSString stringWithFormat:@"%@ has no simple identifier to compare with %@.",
			                                      node.objectType.name, node.value ?: @""]];
		}
	}
	NSMutableArray *steps = [NSMutableArray array];
	for (ORMQueryStep *step in node.steps) {
		BOOL listed = columns && step.operatorKind != ORMQueryNot;
		ORMPlanCondition *condition = [self conditionForStep:step entity:entity at:at columns:listed];
		if (step.operatorKind == ORMQueryMaybe || condition == nil) {
			continue;
		}
		[steps addObject:step.operatorKind == ORMQueryNot ? [ORMPlanCondition not:condition] : condition];
	}
	ORMPlanCondition *combined = node.combinesWithOr ? ORMAnyOf(steps) : ORMAllOf(steps);
	if (combined != nil) {
		[parts addObject:combined];
	}
	return ORMAllOf(parts);
}

- (ORMPlanCondition *)conditionForStep:(ORMQueryStep *)step entity:(ORMCDEntity *)entity at:(ORMPlannerPlace *)at
                               columns:(BOOL)columns
{
	if ([step isSubtyping]) {
		return [self subtypeStep:step entity:entity at:at columns:columns];
	}
	if ([step.nodes count] == 0) {
		/* A unary: its attribute is true. */
		for (ORMRole *role in step.factType.roles) {
			ORMCDProperty *property = role != step.entryRole ? [_places propertyOf:entity source:role.identifier] : nil;
			if ([property isKindOfClass:[ORMCDAttribute class]]) {
				return [ORMPlanCondition compare:[ORMPlanValue valueAtPath:[at.path pathByAddingKey:property.name]]
				                      comparison:@"=" with:[ORMPlanValue constant:@"true" type:@"Boolean"]];
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
			return [self binaryStep:step node:node property:property at:at columns:columns];
		}
		if ([[_places absorbedParts:node.role.identifier on:entity] count] > 0) {
			return [self absorbed:node base:node.role.identifier entity:entity at:at columns:columns];
		}
	}
	return [self entityStep:step entity:entity at:at columns:columns];
}

/* Through a binary to an attribute or a relationship of the entity. */
- (ORMPlanCondition *)binaryStep:(ORMQueryStep *)step
                            node:(ORMQueryNode *)node
                        property:(ORMCDProperty *)property
                              at:(ORMPlannerPlace *)at
                         columns:(BOOL)columns
{
	if ([property isKindOfClass:[ORMCDAttribute class]]) {
		ORMCDAttribute *attribute = (ORMCDAttribute *)property;
		ORMPlannerPlace *value = [at adding:attribute entity:nil];
		if (columns) {
			[self column:node place:value identifier:nil];
		}
		if ([node.steps count] > 0) {
			[self note:[NSString stringWithFormat:@"%@ is an attribute: what is said of it further is left out.",
			                                      node.objectType.name]];
		}
		if (step != nil && step.countComparison != nil) {
			[self note:[NSString stringWithFormat:@"%@ is one attribute: it is not counted.", node.objectType.name]];
		}
		NSMutableArray *parts = [NSMutableArray arrayWithArray:[self correlationsOf:node place:value]];
		[self reach:node place:value];
		if (node.comparison != nil && node.comparedNode == nil) {
			[parts addObject:[ORMPlanCondition compare:[ORMPlanValue valueAtPath:value.path] comparison:node.comparison
			                                      with:[self constant:node.value attribute:attribute]]];
		}
		return ORMAllOf(parts) ?: [ORMPlanCondition notNull:value.path];
	}
	ORMCDRelationship *relationship = (ORMCDRelationship *)property;
	ORMCDEntity *destination = [self destinationOf:relationship];
	ORMPlannerPlace *reached = [at adding:relationship entity:destination];
	if (!relationship.toMany) {
		if (step != nil && step.countComparison != nil) {
			[self note:[NSString stringWithFormat:@"%@ is one at most: it is not counted.", node.objectType.name]];
		}
		/* Through nothing, no condition holds: the condition says it is set. */
		return [self conditionFor:node entity:destination at:reached columns:columns] ?: [ORMPlanCondition notNull:reached.path];
	}
	if (step != nil && step.operatorKind == ORMQueryMaybe) {
		/* Maybe: nothing required, nothing bound; what it lists is each
		 * object the path reaches, or none (an outer join). */
		return [self conditionFor:node entity:destination at:reached columns:columns];
	}
	NSString *variable = [self nextVariable];
	[_scope addObject:variable];
	ORMPlanCondition *body = [self conditionFor:node entity:destination
	                                         at:[ORMPlannerPlace variable:variable entity:destination trail:reached.trail]
	                                    columns:columns];
	[_scope removeLastObject];
	return [self aggregated:reached.path variable:variable body:body member:destination through:nil from:node step:step];
}

/* Through a fact type that is an entity of its own: to it, and on from it
 * to the other roles' players. */
- (ORMPlanCondition *)entityStep:(ORMQueryStep *)step entity:(ORMCDEntity *)entity at:(ORMPlannerPlace *)at
                         columns:(BOOL)columns
{
	ORMFactType *fact = step.factType;
	NSString *back = [fact.identifier stringByAppendingFormat:@".%@", step.entryRole.identifier];
	ORMCDProperty *property = [_places propertyOf:entity source:back];
	ORMCDRelationship *relationship = [property isKindOfClass:[ORMCDRelationship class]] ? (ORMCDRelationship *)property
	                                                                                      : nil;
	ORMCDEntity *factEntity = relationship != nil ? [self destinationOf:relationship] : nil;
	if (factEntity == nil) {
		ORMQueryNode *node = [step.nodes count] == 1 ? [step.nodes firstObject] : nil;
		if (node != nil && node.objectType.kind == ORMEntityType && [_places entityOf:node.objectType] == nil) {
			[self note:[NSString stringWithFormat:@"%@ is absorbed into what uses it, and \"%@\" joins on nothing %@ has. "
			                                      @"Map %@ as an entity to query through it.",
			                                      node.objectType.name, [[fact primaryReading] expandedText] ?: fact.name,
			                                      entity.name, node.objectType.name]];
		} else {
			[self note:[NSString stringWithFormat:@"\"%@\" maps to nothing %@ reaches.",
			                                      [[fact primaryReading] expandedText] ?: fact.name, entity.name]];
		}
		return nil;
	}
	ORMPlannerPlace *reached = [at adding:relationship entity:factEntity];
	NSString *variable = relationship.toMany && step.operatorKind != ORMQueryMaybe ? [self nextVariable] : nil;
	ORMPlannerPlace *inner = variable != nil ? [ORMPlannerPlace variable:variable entity:factEntity trail:reached.trail]
	                                         : reached;
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
		ORMPlanCondition *part = [self binaryStep:nil node:node property:rolePlace at:inner columns:columns];
		/* The role is played: a mandatory one says nothing more. */
		if (part != nil && (node.comparison != nil || [node.steps count] > 0 || node.label != nil)) {
			[parts addObject:part];
		}
	}
	if (variable != nil) {
		[_scope removeLastObject];
	}
	ORMPlanCondition *body = ORMAllOf(parts);
	if (variable == nil) {
		return body ?: [ORMPlanCondition notNull:reached.path];
	}
	ORMQueryNode *start = nil;
	ORMCDProperty *firstHop = nil;
	for (ORMQueryNode *node in step.nodes) {
		for (ORMQueryNode *above = step.aggregateNode; above != nil && start == nil; above = above.step.parent) {
			if (above == node) {
				start = node;
				firstHop = [_places propertyOf:factEntity source:node.role.identifier];
			}
		}
	}
	return [self aggregated:reached.path variable:variable body:body member:factEntity through:firstHop from:start step:step];
}

/* What the step asks of the collection: some member meeting the body, or
 * a count or aggregate of those that do. */
- (ORMPlanCondition *)aggregated:(ORMPlanPath *)collection
                        variable:(NSString *)variable
                            body:(ORMPlanCondition *)body
                          member:(ORMCDEntity *)member
                         through:(ORMCDProperty *)firstHop
                            from:(ORMQueryNode *)start
                            step:(ORMQueryStep *)step
{
	ORMPlanCondition *exists = [ORMPlanCondition exists:collection variable:body != nil ? variable : nil where:body];
	if (step == nil || step.countComparison == nil) {
		return exists;
	}
	if (step.aggregate == ORMQueryCount) {
		return [ORMPlanCondition count:collection variable:body != nil ? variable : nil where:body
		                    comparison:step.countComparison number:step.countValue];
	}
	/* From the member, or from where its first hop leads. */
	ORMCDEntity *startEntity = firstHop == nil ? member
		: ([firstHop isKindOfClass:[ORMCDRelationship class]] ? [self destinationOf:(ORMCDRelationship *)firstHop] : nil);
	NSArray *rest = startEntity != nil ? [self pathFrom:start entity:startEntity to:step.aggregateNode] : nil;
	if (rest == nil && firstHop != nil && start == step.aggregateNode) {
		rest = @[];
	}
	NSArray *path = rest != nil ? (firstHop != nil ? [@[ firstHop ] arrayByAddingObjectsFromArray:rest] : rest) : nil;
	ORMCDProperty *last = [path lastObject];
	if (![last isKindOfClass:[ORMCDAttribute class]]) {
		[self note:[NSString stringWithFormat:@"%@(%@) is of nothing one path reaches from %@.",
		                                      [ORMQuery nameOfAggregate:step.aggregate], [step.aggregateNode designation],
		                                      collection]];
		return exists;
	}
	NSString *function = [@[ @"", @"sum", @"average", @"max", @"min" ] objectAtIndex:(NSUInteger)step.aggregate];
	/* Of the members meeting conditions only where the steps below ask more
	 * than that the path is there (whose values the aggregate takes anyway). */
	BOOL narrowed = [self narrows:start] || (start != step.aggregateNode && [self narrows:step.aggregateNode]);
	return [ORMPlanCondition aggregate:function
	                                of:[ORMPlanPath pathFrom:variable keys:[path valueForKey:@"name"]]
	                              over:collection
	                          variable:variable
	                             where:narrowed ? body : nil
	                        comparison:step.countComparison
	                          constant:[ORMPlanValue constant:step.aggregateValue ?: @""
	                                                     type:((ORMCDAttribute *)last).attributeType]];
}

/* Whether what is below the node asks more of it than that it is there:
 * a condition, a label, a not, an alternative, a count. */
- (BOOL)narrows:(ORMQueryNode *)node
{
	if (node == nil) {
		return NO;
	}
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

/* The properties from an object of the entity at the node to the target,
 * one of the nodes below it: through to-ones, to an attribute or an
 * entity's identifier. nil when there is no such path. */
- (NSArray<ORMCDProperty *> *)pathFrom:(ORMQueryNode *)node entity:(ORMCDEntity *)entity to:(ORMQueryNode *)target
{
	if (node == target) {
		ORMCDAttribute *identifier = entity != nil ? [_places identifierOf:node.objectType on:entity] : nil;
		return identifier != nil ? @[ identifier ] : nil;
	}
	for (ORMQueryStep *step in node.steps) {
		for (ORMQueryNode *next in step.nodes) {
			ORMCDProperty *property = [_places propertyOf:entity source:next.role.identifier];
			if ([property isKindOfClass:[ORMCDAttribute class]] && next == target) {
				return @[ property ];
			}
			if ([property isKindOfClass:[ORMCDRelationship class]] && !((ORMCDRelationship *)property).toMany) {
				NSArray *rest = [self pathFrom:next entity:[self destinationOf:(ORMCDRelationship *)property] to:target];
				if (rest != nil) {
					return [@[ property ] arrayByAddingObjectsFromArray:rest];
				}
			}
		}
	}
	return nil;
}

/* To a subtype: the object is of its entity, and read as one; to a
 * supertype: it is one. */
- (ORMPlanCondition *)subtypeStep:(ORMQueryStep *)step entity:(ORMCDEntity *)entity at:(ORMPlannerPlace *)at
                          columns:(BOOL)columns
{
	ORMQueryNode *node = [step.nodes firstObject];
	if (node == nil) {
		return nil;
	}
	ORMCDEntity *target = [_places entityOf:node.objectType];
	ORMPlanCondition *test = nil;
	ORMPlannerPlace *place = at;
	if (step.entryRole.isSupertypeMetaRole && [at isRead] && target != nil && [_places entity:_read inherits:target]) {
		/* What is read is one. */
	} else if (step.entryRole.isSupertypeMetaRole) {
		if (target == nil || target == entity || ![_places entity:target inherits:entity]) {
			[self note:[NSString stringWithFormat:@"%@ is no entity of its own, so being one is not tested.",
			                                      node.objectType.name]];
		} else {
			test = [ORMPlanCondition isOf:at.path entity:target.name];
			place = [at castTo:target];
		}
	}
	ORMPlanCondition *inner = [self conditionFor:node entity:target ?: entity at:place columns:columns];
	return ORMAllOf([NSArray arrayWithObjects:test ?: inner, test != nil ? inner : nil, nil]);
}

#pragma mark Absorbed object types

/* An object type absorbed into the entity as properties whose traces start
 * with the base: a step to one of its parts is that property; a step on to
 * another entity that absorbs it too is a join. */
- (ORMPlanCondition *)absorbed:(ORMQueryNode *)node
                          base:(NSString *)base
                        entity:(ORMCDEntity *)entity
                            at:(ORMPlannerPlace *)at
                       columns:(BOOL)columns
{
	NSArray *parts = [_places absorbedParts:base on:entity];
	ORMCDProperty *firstPart = [[parts firstObject] lastObject];
	if (node.comparison != nil || node.label != nil) {
		[self note:[NSString stringWithFormat:@"%@ is absorbed: it has no one value to compare or correlate.",
		                                      node.objectType.name]];
	}
	if (columns && node.isProjected) {
		[self column:node place:[at adding:firstPart entity:nil] identifier:nil];
	}
	NSMutableArray *conditions = [NSMutableArray array];
	for (ORMQueryStep *step in node.steps) {
		ORMQueryNode *next = [step.nodes firstObject];
		if ([step.nodes count] != 1 || step.operatorKind == ORMQueryMaybe) {
			continue;
		}
		NSString *partBase = [base stringByAppendingFormat:@"/%@", next.role.identifier];
		ORMCDProperty *part = [_places propertyOf:entity source:partBase];
		ORMPlanCondition *condition = nil;
		if (part != nil) {
			condition = [self binaryStep:step node:next property:part at:at columns:columns];
		} else if ([[_places absorbedParts:partBase on:entity] count] > 0) {
			condition = [self absorbed:next base:partBase entity:entity at:at columns:columns];
		} else {
			condition = [self join:step node:next from:base entity:entity at:at];
		}
		if (condition != nil) {
			[conditions addObject:step.operatorKind == ORMQueryNot ? [ORMPlanCondition not:condition] : condition];
		}
	}
	if ([conditions count] == 0) {
		/* Played: its parts are there. */
		return [ORMPlanCondition notNull:[at.path pathByAddingKey:firstPart.name]];
	}
	return ORMAllOf(conditions);
}

/* Through an absorbed object type to an entity that absorbs it too: a plan
 * of that entity, whose parts' values are what the place's must equal. */
- (ORMPlanCondition *)join:(ORMQueryStep *)step
                      node:(ORMQueryNode *)node
                      from:(NSString *)base
                    entity:(ORMCDEntity *)entity
                        at:(ORMPlannerPlace *)at
{
	ORMCDEntity *joined = [_places entityOf:node.objectType];
	NSArray *ours = [_places absorbedParts:base on:entity];
	NSArray *theirs = joined != nil ? [_places absorbedParts:step.entryRole.identifier on:joined] : @[];
	NSMutableArray *pairs = [NSMutableArray array];
	for (NSArray *part in ours) {
		for (NSArray *their in theirs) {
			if ([[part firstObject] isEqualToString:[their firstObject]]) {
				[pairs addObject:@[ [at.path pathByAddingKey:[(ORMCDProperty *)[part lastObject] name]],
				                    [ORMPlanPath pathFrom:nil keys:@[ [(ORMCDProperty *)[their lastObject] name] ]] ]];
			}
		}
	}
	NSString *what = [[step.factType primaryReading] expandedText] ?: step.factType.name;
	if (joined == nil || [pairs count] == 0 || [pairs count] != [ours count]) {
		[self note:[NSString stringWithFormat:@"\"%@\" joins on parts %@ does not have as %@ does.", what,
		                                      joined.name ?: node.objectType.name, entity.name]];
		return nil;
	}
	/* What the joined objects must be, planned from them: a plan of its
	 * own, in which what this one reached is still there, its object read
	 * a variable (o1), and its variables in scope: a correlated join. */
	ORMCDEntity *read = _read;
	_outers++;
	NSString *outer = [NSString stringWithFormat:@"o%lu", (unsigned long)_outers];
	[_outerNames addObject:outer];
	_level++;
	_read = joined;
	ORMPlanCondition *condition = [self conditionFor:node entity:joined
	                                              at:[ORMPlannerPlace variable:nil entity:joined trail:@[]] columns:NO];
	_read = read;
	_level--;
	[_outerNames removeLastObject];
	ORMQueryPlan *plan = [ORMQueryPlan planReading:joined.name where:condition columns:@[] sorts:@[] notes:@[]];
	BOOL correlated = [[condition freeVariables] containsObject:outer];
	return [ORMPlanCondition matchesDefinition:[self define:@"join" plan:plan] pairs:pairs outer:correlated ? outer : nil];
}

@end
