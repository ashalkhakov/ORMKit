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
/* A joined entity type's member's object (docs/JOINED-ENTITIES.md): no
 * path from the object read reaches it. */
@property (nonatomic) BOOL isJoined;
/* An object type absorbed into the entity: no object of its own, but its
 * parts, @[ the trace below the base ("/role"), the part's place ], in
 * the order the entity has them. nil for others. */
@property (nonatomic, copy) NSArray<NSArray *> *parts;
/* A value node's: what it computes, its paths as from where it is; no
 * path of its own. nil for others. */
@property (nonatomic, strong) ORMPlanValue *value;
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
	place.isJoined = self.isJoined;
	return place;
}

- (ORMPlannerPlace *)castTo:(ORMCDEntity *)entity
{
	ORMPlannerPlace *place = [[ORMPlannerPlace alloc] init];
	place.path = [self.path pathByAddingCast:entity.name];
	place.trail = self.trail;
	place.entity = entity;
	place.isJoined = self.isJoined;
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

/* All of them, an "all" among them merged in. */
static ORMPlanCondition *
ORMAllOf(NSArray<ORMPlanCondition *> *parts)
{
	NSMutableArray *flat = [NSMutableArray array];
	for (ORMPlanCondition *part in parts) {
		if (part.kind == ORMPlanAnd) {
			[flat addObjectsFromArray:part.operands];
		} else {
			[flat addObject:part];
		}
	}
	return [flat count] == 0 ? nil : ([flat count] == 1 ? [flat firstObject] : [ORMPlanCondition all:flat]);
}

static ORMPlanCondition *
ORMAnyOf(NSArray<ORMPlanCondition *> *parts)
{
	return [parts count] == 0 ? nil : ([parts count] == 1 ? [parts firstObject] : [ORMPlanCondition any:parts]);
}

/* Whether the condition holds of nothing: a not, and what is made of nots.
 * Through a to-one that is not set, it would hold, though the step is
 * not taken. */
static BOOL
ORMHoldsOfNothing(ORMPlanCondition *condition)
{
	switch (condition.kind) {
	case ORMPlanNot:
		return YES;
	case ORMPlanAnd:
		for (ORMPlanCondition *operand in condition.operands) {
			if (!ORMHoldsOfNothing(operand)) {
				return NO;
			}
		}
		return YES;
	case ORMPlanOr:
		for (ORMPlanCondition *operand in condition.operands) {
			if (ORMHoldsOfNothing(operand)) {
				return YES;
			}
		}
		return NO;
	default:
		return NO;
	}
}

/* A to-one step taken, with what is said beyond it: set, where that alone
 * would not say so. */
static ORMPlanCondition *
ORMThrough(ORMPlanPath *path, ORMPlanCondition *beyond)
{
	if (beyond == nil) {
		return [ORMPlanCondition notNull:path];
	}
	return ORMHoldsOfNothing(beyond) ? ORMAllOf(@[ [ORMPlanCondition notNull:path], beyond ]) : beyond;
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
	/* Planning a bag: the nodes it lists, its aggregates left out. nil
	 * planning the query. And the bags made, by "group node/node". */
	NSSet<NSString *> *_bagNodes;
	NSMutableDictionary<NSString *, ORMPlanDefinition *> *_bags;
	/* The bags being made around this planning, by "group node/node": an
	 * aggregate of one of them is left out of what it is made of. */
	NSSet<NSString *> *_bagging;
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
	if (place.value != nil) {
		/* Computed: where each path it reads is. */
		for (ORMPlanPath *path in [place.value paths]) {
			if (path.variable != nil && ![_scope containsObject:path.variable]) {
				return NO;
			}
		}
		return YES;
	}
	return place.path.variable == nil || [_scope containsObject:place.path.variable];
}

/* What is at a place reached before, as a value from here. */
- (ORMPlanValue *)valueOf:(ORMPlannerPlace *)place
{
	return place.value ?: [ORMPlanValue valueAtPath:[self pathOf:place]];
}

- (void)reach:(ORMQueryNode *)node place:(ORMPlannerPlace *)place
{
	place.level = _level;
	for (NSArray *part in place.parts) {
		((ORMPlannerPlace *)[part lastObject]).level = _level;
	}
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
	/* Steps through derived fact types put as their derivations' paths
	 * (docs/DERIVATION.md): an ordinary query after that. */
	NSMutableArray *expanding = [NSMutableArray array];
	ORMModel *model = query.root.objectType.model;
	ORMQuery *expanded = model != nil ? [query expandedInModel:model notes:expanding] : query;
	if (expanded == nil) {
		return [ORMQueryPlan planReading:nil where:nil columns:@[] sorts:@[] notes:expanding];
	}
	_query = expanded;
	_notes = [NSMutableArray array];
	_variables = 0;
	_scope = [NSMutableArray array];
	_reached = [NSMutableDictionary dictionary];
	_columns = [NSMutableArray array];
	_level = 0;
	_outerNames = [NSMutableArray array];
	_outers = 0;
	_definitions = [NSMutableArray array];
	_bags = [NSMutableDictionary dictionary];
	return [self planned];
}

/* The query planned, what is known of it so far set up. */
- (ORMQueryPlan *)planned
{
	ORMQuery *query = _query;
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
	if (!query.isComplete && _bagNodes == nil) {
		[self note:@"Something the query goes through is no longer in the model, and is left out."];
	}
	if (query.kind == ORMQueryCalculation && _bagNodes == nil) {
		return [self plannedCalculation:entity];
	}
	ORMPlanCondition *condition = [self conditionFor:root entity:entity
	                                              at:[ORMPlannerPlace variable:nil entity:_read trail:@[]] columns:YES];
	/* In the outline's order, whatever order they were planned in (a value
	 * node as soon as it can be). */
	NSArray *order = [query nodes];
	NSMutableArray *ordered = [NSMutableArray array];
	for (ORMQueryNode *node in order) {
		for (NSArray *column in _columns) {
			if ([column firstObject] == node) {
				[ordered addObject:column];
			}
		}
	}
	for (NSArray *column in _columns) {
		if ([ordered indexOfObjectIdenticalTo:column] == NSNotFound) {
			[ordered addObject:column];
		}
	}
	_columns = ordered;
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
		id identifier = [column objectAtIndex:2];
		NSString *title = [node designation];
		ORMQueryNode *above = node.step.parent;
		if ([titles countForObject:title] > 1 && above != nil) {
			title = [NSString stringWithFormat:@"%@ of %@", title, [above designation]];
		}
		if (place.value != nil) {
			[columns addObject:[ORMPlanColumn columnTitled:title node:node.identifier value:place.value]];
			continue;
		}
		ORMPlanColumn *planned = [ORMPlanColumn columnTitled:title node:node.identifier path:place.path
		                                               trail:[place.trail valueForKey:@"name"]
		                                          identifier:identifier != [NSNull null] ? [identifier name] : nil];
		/* An object no one attribute identifies: by the values that do; an
		 * absorbed one by its parts, given. */
		if ([column count] > 3) {
			planned.identifierParts = [column objectAtIndex:3];
		} else if (identifier == [NSNull null] && place.entity != nil) {
			planned.identifierParts = [_places identifyingPartsOf:node.objectType on:place.entity];
		}
		[columns addObject:planned];
	}
	if (_bagNodes != nil) {
		/* The sets it uses are the query's, defined before it. */
		return [ORMQueryPlan planReading:_read.name where:condition columns:columns sorts:@[] notes:@[]];
	}
	NSArray *rowSorts = [self rowSorts];
	ORMQueryPlan *plan = [ORMQueryPlan planReading:_read.name where:condition columns:columns
	                                         sorts:rowSorts != nil ? @[] : [self sorts] notes:_notes
	                                   definitions:_definitions];
	plan.rowSorts = rowSorts;
	return plan;
}

/* Where a node sorted by is computed, which no store sorts by: each sorted
 * node by its column, the rows sorted once read. nil where none is. */
- (NSArray<ORMPlanSort *> *)rowSorts
{
	NSMutableArray *sorted = [NSMutableArray array];
	BOOL computed = NO;
	for (ORMQueryNode *node in [_query nodes]) {
		if (node.sortOrder != ORMQueryUnsorted) {
			[sorted addObject:node];
			computed = computed || node.isValue;
		}
	}
	if (!computed) {
		return nil;
	}
	NSMutableArray *sorts = [NSMutableArray array];
	for (ORMQueryNode *node in sorted) {
		BOOL listed = NO;
		for (NSArray *column in _columns) {
			listed = listed || [[[column firstObject] identifier] isEqualToString:node.identifier];
		}
		if (!listed) {
			[self note:[NSString stringWithFormat:@"%@ is sorted by, but not listed.", [node designation]]];
			continue;
		}
		[sorts addObject:[ORMPlanSort sortByColumnOf:node.identifier ascending:node.sortOrder == ORMQueryAscending]];
	}
	return sorts;
}

/* A calculation (docs/RULES.md): every object of the root's type, and its
 * value, the function of the node's values over the query's bag for it. */
- (ORMQueryPlan *)plannedCalculation:(ORMCDEntity *)entity
{
	ORMQuery *query = _query;
	ORMQueryNode *root = query.root;
	_read = entity;
	ORMPlannerPlace *at = [ORMPlannerPlace variable:nil entity:entity trail:@[]];
	[self reach:root place:at];
	ORMCDAttribute *identifier = [_places identifierOf:root.objectType on:entity];
	NSMutableArray *columns = [NSMutableArray arrayWithObject:[ORMPlanColumn columnTitled:[root designation]
	                                                                                 node:root.identifier
	                                                                                 path:at.path
	                                                                                trail:@[]
	                                                                           identifier:identifier.name]];
	ORMQueryNode *node = query.calculatedNode;
	if (node == nil) {
		[self note:[NSString stringWithFormat:@"%@ says of no node what it computes.", query.name]];
	} else {
		NSArray *functions = @[ @"value", @"count", @"sum", @"average", @"max", @"min" ];
		ORMPlanValue *value = [self aggregate:[functions objectAtIndex:(NSUInteger)query.calculationFunction] of:node
		                                  for:root];
		if (value != nil) {
			[columns addObject:[ORMPlanColumn columnTitled:query.name node:node.identifier value:value]];
		}
	}
	return [ORMQueryPlan planReading:entity.name where:nil columns:columns sorts:@[] notes:_notes definitions:_definitions];
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
		id identifier = [column objectAtIndex:2];
		BOOL one = column != nil && (place.entity == nil || identifier != [NSNull null]);
		for (ORMCDProperty *property in place.trail) {
			one = one && !([property isKindOfClass:[ORMCDRelationship class]] && ((ORMCDRelationship *)property).toMany);
		}
		if (!one || place.isJoined) {
			[self note:[NSString stringWithFormat:@"%@ is sorted by, but %@.", [node designation],
			                                      column == nil ? @"not listed"
			                                      : place.isJoined ? @"it is a joined entity's, which a fetch does not sort by"
			                                                       : @"not one value for each result"]];
			continue;
		}
		ORMPlanPath *path = [place pathFromRead];
		if (place.entity != nil) {
			path = [path pathByAddingKey:[identifier name]];
		}
		[sorts addObject:[ORMPlanSort sortBy:path ascending:node.sortOrder == ORMQueryAscending]];
	}
	if ([sorts count] == 0) {
		[sorts addObjectsFromArray:[self defaultSorts]];
	}
	return sorts;
}

/* With no node sorted, the rows in their own order, as D4 reads a table
 * by its key: by each column, a value or an object by its identifier,
 * where each is reached from the object read through to-ones and the
 * object read is not listed itself (its key orders it anyway). Else none:
 * a backend orders by the key. */
- (NSArray<ORMPlanSort *> *)defaultSorts
{
	NSMutableArray *sorts = [NSMutableArray array];
	NSMutableArray *paths = [NSMutableArray array];
	for (NSArray *column in _columns) {
		ORMPlannerPlace *place = [column objectAtIndex:1];
		id identifier = [column objectAtIndex:2];
		if (place.value != nil) {
			/* Computed: what it is computed from orders it, or nothing. */
			continue;
		}
		if ([place isRead] || place.path.variable != nil || (place.entity != nil && identifier == [NSNull null])) {
			return @[];
		}
		for (ORMCDProperty *property in place.trail) {
			if ([property isKindOfClass:[ORMCDRelationship class]] && ((ORMCDRelationship *)property).toMany) {
				return @[];
			}
		}
		ORMPlanPath *path = [place pathFromRead];
		if (place.entity != nil) {
			path = [path pathByAddingKey:[identifier name]];
		}
		if (![paths containsObject:path.keys]) {
			[paths addObject:path.keys];
			[sorts addObject:[ORMPlanSort sortBy:path ascending:YES]];
		}
	}
	return sorts;
}

/* Whether a column lists from the variable. */
- (BOOL)lists:(NSString *)variable
{
	for (NSArray *column in _columns) {
		ORMPlannerPlace *place = [column objectAtIndex:1];
		if ([place.path.variable isEqualToString:variable]) {
			return YES;
		}
		for (ORMPlanPath *path in [place.value paths]) {
			if ([path.variable isEqualToString:variable]) {
				return YES;
			}
		}
	}
	return NO;
}

- (void)column:(ORMQueryNode *)node place:(ORMPlannerPlace *)place identifier:(ORMCDAttribute *)identifier
{
	if (_bagNodes != nil ? [_bagNodes containsObject:node.identifier] : node.isProjected) {
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
	if (place.parts != nil || reference.parts != nil) {
		return [self relateParts:place comparison:comparison to:reference node:other];
	}
	if (reference.value != nil && (reference.level != _level || ![self inScope:reference])) {
		[self note:[NSString stringWithFormat:@"%@ is compared with %@, which is computed where it is not one value.",
		                                      place.value ?: place.path, [other designation]]];
		return nil;
	}
	ORMPlanCondition *related = nil;
	if ([self inScope:reference]) {
		if (place.entity == nil) {
			return [ORMPlanCondition compare:[self valueOf:place] comparison:comparison with:[self valueOf:reference]];
		}
		if (!equality) {
			[self note:[NSString stringWithFormat:@"%@ %@ %@ compares objects: only = and <> can.", place.path, comparison,
			                                      [other designation]]];
			return nil;
		}
		related = [ORMPlanCondition same:place.path as:[self pathOf:reference]];
	} else {
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
		/* Among those meeting the earlier occurrence's conditions: they are
		 * of this very object, so they are asked of it here. */
		if (other.comparison != nil || [other.steps count] > 0) {
			ORMPlanCondition *again = place.entity != nil ? [self again:other at:place] : nil;
			if (again != nil) {
				related = [ORMPlanCondition all:@[ related, again ]];
			} else {
				[self note:[NSString stringWithFormat:@"%@ is taken as any %@ the path reaches, not only those meeting "
				                                      @"its conditions.",
				                                      [other designation], other.objectType.name]];
			}
		}
	}
	return [comparison isEqualToString:@"<>"] ? [ORMPlanCondition not:related] : related;
}

/* Two occurrences of an absorbed object type: the same where each of their
 * parts is, a value equal, an object the same one. */
- (ORMPlanCondition *)relateParts:(ORMPlannerPlace *)place
                       comparison:(NSString *)comparison
                               to:(ORMPlannerPlace *)reference
                             node:(ORMQueryNode *)other
{
	BOOL equality = [comparison isEqualToString:@"="] || [comparison isEqualToString:@"<>"];
	NSMutableArray *ours = [NSMutableArray array], *theirs = [NSMutableArray array];
	for (NSArray *part in place.parts) {
		[ours addObject:[part firstObject]];
	}
	for (NSArray *part in reference.parts) {
		[theirs addObject:[part firstObject]];
	}
	if (!equality || place.parts == nil || reference.parts == nil || ![ours isEqualToArray:theirs]) {
		[self note:[NSString stringWithFormat:@"%@ is absorbed: it is compared with %@ only by = or <>, part by part, "
		                                      @"where both are absorbed alike.",
		                                      other.objectType.name, [other designation]]];
		return nil;
	}
	if (![self inScope:reference]) {
		[self note:[NSString stringWithFormat:@"%@ is absorbed, and %@ is out of scope where it is met again: its parts "
		                                      @"are not compared.",
		                                      other.objectType.name, [other designation]]];
		return nil;
	}
	NSMutableArray *equal = [NSMutableArray array];
	for (NSUInteger i = 0; i < [place.parts count]; i++) {
		ORMPlannerPlace *mine = [[place.parts objectAtIndex:i] lastObject];
		ORMPlannerPlace *its = [[reference.parts objectAtIndex:i] lastObject];
		ORMPlanPath *there = [self pathOf:its];
		[equal addObject:mine.entity != nil ? [ORMPlanCondition same:mine.path as:there]
		                                    : [ORMPlanCondition compare:[ORMPlanValue valueAtPath:mine.path] comparison:@"="
		                                                           with:[ORMPlanValue valueAtPath:there]]];
	}
	ORMPlanCondition *related = ORMAllOf(equal);
	return [comparison isEqualToString:@"<>"] ? [ORMPlanCondition not:related] : related;
}

/* What the node and its steps require, asked of the object at the place:
 * the node met again there. What it reaches is reached where it was. */
- (ORMPlanCondition *)again:(ORMQueryNode *)node at:(ORMPlannerPlace *)place
{
	NSMutableDictionary *reached = [_reached mutableCopy];
	ORMPlanCondition *condition = [self conditionFor:node entity:place.entity at:place columns:NO];
	_reached = reached;
	return condition;
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
	/* A joined entity type's object reached at a member (a relationship's
	 * destination): it is the hub's row, which its steps go from. */
	ORMCDEntity *hub = entity != nil ? [_places entityOf:node.objectType] : nil;
	if (hub != nil && entity != hub
	    && [[entity.userInfo objectForKey:@"ormkit.joins"] isEqualToString:node.objectType.identifier]) {
		NSArray *hops = [_places joinsToHubFrom:entity];
		if (hops != nil) {
			NSArray *places = [self enter:hops];
			ORMPlanCondition *body = [self conditionFor:node entity:hub at:[places lastObject] columns:columns];
			return [self leave:hops places:places from:at where:body optional:NO];
		}
	}
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
	/* Its aggregates for what is reached already first: of the whole
	 * query, for this object, so that what its steps reach may be compared
	 * with them ("the one before"). */
	NSMutableArray *pending = [NSMutableArray array];
	for (ORMQueryNode *value in node.values) {
		if (value.expression.kind == ORMQueryExpressionAggregate && [self canPlan:value]) {
			ORMPlanCondition *condition = [self conditionForValue:value columns:columns];
			if (condition != nil) {
				[parts addObject:condition];
			}
		} else {
			[pending addObject:value];
		}
	}
	NSMutableArray *steps = [NSMutableArray array];
	for (ORMQueryStep *step in node.steps) {
		BOOL listed = columns && step.operatorKind != ORMQueryNot;
		ORMPlanCondition *condition = [self conditionForStep:step entity:entity at:at columns:listed];
		if (condition == nil) {
			continue;
		}
		[steps addObject:step.operatorKind == ORMQueryNot ? [ORMPlanCondition not:condition] : condition];
		/* Each value node as soon as what it uses is reached, so that the
		 * steps after may be compared with it; not among alternatives. */
		for (BOOL more = !node.combinesWithOr; more;) {
			more = NO;
			for (ORMQueryNode *value in [pending copy]) {
				if ([self canPlan:value]) {
					[pending removeObjectIdenticalTo:value];
					ORMPlanCondition *valued = [self conditionForValue:value columns:columns];
					if (valued != nil) {
						[steps addObject:valued];
					}
					more = YES;
				}
			}
		}
	}
	ORMPlanCondition *combined = node.combinesWithOr ? ORMAnyOf(steps) : ORMAllOf(steps);
	if (combined != nil) {
		[parts addObject:combined];
	}
	/* Its other value nodes, computed from what its steps reached, each
	 * once what it uses is ("Total = total(Amount) for Vehicle, Month",
	 * after Month); what never is, last, noted. */
	while ([pending count] > 0) {
		ORMQueryNode *next = [pending firstObject];
		for (ORMQueryNode *value in pending) {
			if ([self canPlan:value]) {
				next = value;
				break;
			}
		}
		[pending removeObjectIdenticalTo:next];
		ORMPlanCondition *condition = [self conditionForValue:next columns:columns];
		if (condition != nil) {
			[parts addObject:condition];
		}
	}
	return ORMAllOf(parts);
}

/* Whether what a value node uses is reached: an aggregate's groups (what
 * it aggregates is its bag's), arithmetic's every node; and the node it is
 * compared with. */
- (BOOL)canPlan:(ORMQueryNode *)value
{
	NSArray *used = value.expression.kind == ORMQueryExpressionAggregate ? value.expression.groups : [value.expression nodeIds];
	/* And what it is compared with. */
	if (value.comparedNode != nil) {
		used = [used arrayByAddingObject:value.comparedNode.identifier];
	}
	for (NSString *nodeId in used) {
		if ([_reached objectForKey:nodeId] == nil) {
			return NO;
		}
	}
	return YES;
}

#pragma mark Value nodes

/* Whether the place is reached from the object read through to-ones only. */
- (BOOL)throughToOnes:(ORMPlannerPlace *)place
{
	for (ORMCDProperty *property in place.trail) {
		if ([property isKindOfClass:[ORMCDRelationship class]] && ((ORMCDRelationship *)property).toMany) {
			return NO;
		}
	}
	return YES;
}

/* A value node (docs/EXPRESSIONS.md): what it computes, from the places of
 * the nodes it uses, listed and compared as any node. Nothing, noted, where
 * one of them is not one value where it is computed. */
- (ORMPlanCondition *)conditionForValue:(ORMQueryNode *)value columns:(BOOL)columns
{
	ORMPlanValue *computed = [self valueOfExpression:value.expression in:value];
	if (computed == nil) {
		return nil;
	}
	ORMPlannerPlace *place = [[ORMPlannerPlace alloc] init];
	place.value = computed;
	if (columns) {
		[self column:value place:place identifier:nil];
	}
	NSMutableArray *parts = [NSMutableArray arrayWithArray:[self correlationsOf:value place:place]];
	[self reach:value place:place];
	if (value.comparison != nil && value.comparedNode == nil) {
		ORMObjectType *type = [value.objectType valueType];
		NSString *attributeType = type.dataType != nil ? [ORMCoreDataMapper attributeTypeFor:type.dataType] : @"String";
		[parts addObject:[ORMPlanCondition compare:computed comparison:value.comparison
		                                      with:[ORMPlanValue constant:value.value ?: @"" type:attributeType]]];
	}
	return ORMAllOf(parts);
}

/* The expression as a plan's value: each node by what is at its place, an
 * entity by its identifier. nil, noted, where a node is not reached, or not
 * one value here. */
- (ORMPlanValue *)valueOfExpression:(ORMQueryExpression *)expression in:(ORMQueryNode *)value
{
	switch (expression.kind) {
	case ORMQueryExpressionConstant: {
		NSString *text = expression.constant ?: @"";
		if ([text hasPrefix:@"'"] && [text length] >= 2) {
			return [ORMPlanValue constant:[[text substringWithRange:NSMakeRange(1, [text length] - 2)]
			                                  stringByReplacingOccurrencesOfString:@"''" withString:@"'"]
			                         type:@"String"];
		}
		return [ORMPlanValue constant:text type:[text rangeOfString:@"."].location != NSNotFound ? @"Decimal" : @"Integer 64"];
	}
	case ORMQueryExpressionNode: {
		ORMQueryNode *used = nil;
		for (ORMQueryNode *each in [_query nodes]) {
			used = [each.identifier isEqualToString:expression.nodeId] ? each : used;
		}
		ORMPlannerPlace *place = [_reached objectForKey:expression.nodeId ?: @""];
		/* Bound where it is not in scope (a maybe's), but through to-ones
		 * only: one value from the object read. */
		if (place != nil && place.value == nil && ![self inScope:place] && place.level == _level && !place.isJoined
		    && [self throughToOnes:place]) {
			ORMPlannerPlace *read = [ORMPlannerPlace variable:nil entity:place.entity trail:place.trail];
			read.path = [place pathFromRead];
			read.level = place.level;
			place = read;
		}
		NSString *why = used == nil || place == nil ? @"which the query does not reach before it"
			: place.parts != nil ? @"which is absorbed, and has no one value"
			: place.level != _level || ![self inScope:place] ? @"which is not one value where it is computed" : nil;
		ORMCDAttribute *identifier = why == nil && place.entity != nil ? [_places identifierOf:used.objectType on:place.entity] : nil;
		if (why == nil && place.entity != nil && identifier == nil) {
			why = @"which has no one value to compute with";
		}
		if (why != nil) {
			[self note:[NSString stringWithFormat:@"%@ uses %@, %@.", [value designation], [used designation] ?: @"a node", why]];
			return nil;
		}
		if (place.value != nil) {
			return place.value;
		}
		ORMPlanPath *path = [self pathOf:place];
		return [ORMPlanValue valueAtPath:identifier != nil ? [path pathByAddingKey:identifier.name] : path];
	}
	case ORMQueryExpressionAggregate: {
		ORMQueryNode *of = nil;
		NSMutableDictionary *byId = [NSMutableDictionary dictionary];
		for (ORMQueryNode *each in [_query nodes]) {
			of = [each.identifier isEqualToString:[[expression.arguments firstObject] nodeId]] ? each : of;
			[byId setObject:each forKey:each.identifier ?: @""];
		}
		/* Grouped by the first node it is for that is no value node; the
		 * others matched ("for Vehicle, Month"). */
		ORMQueryNode *group = nil;
		NSMutableArray *others = [NSMutableArray array];
		for (NSString *groupId in expression.groups) {
			ORMQueryNode *each = [byId objectForKey:groupId];
			if (group == nil && each != nil && !each.isValue) {
				group = each;
			} else if (each != nil) {
				[others addObject:each];
			}
		}
		if (of == nil || group == nil) {
			[self note:[NSString stringWithFormat:@"%@ is for no node that is not computed, which it is grouped by.",
			                                      [value designation]]];
			return nil;
		}
		/* A bag's rows leave out the aggregates being made of them; others
		 * they may be compared with are theirs ("since the one before"). */
		if ([_bagging containsObject:[self bagKeyOf:of for:group also:others]]) {
			return nil;
		}
		NSDictionary *functions = @{ @"count": @"count", @"total": @"sum", @"avg": @"average", @"max": @"max", @"min": @"min" };
		return [self aggregate:[functions objectForKey:expression.function] of:of for:group also:others];
	}
	case ORMQueryExpressionFunction:
		break;
	}
	NSMutableArray *operands = [NSMutableArray array];
	for (ORMQueryExpression *argument in expression.arguments) {
		ORMPlanValue *operand = [self valueOfExpression:argument in:value];
		if (operand == nil) {
			return nil;
		}
		[operands addObject:operand];
	}
	return [ORMPlanValue apply:expression.function to:operands];
}

/* Whether the step's aggregate is a bag's: for another node than the one
 * above, or compared with another aggregate. */
- (BOOL)tallies:(ORMQueryStep *)step
{
	return step.countComparison != nil && step.aggregateNode != nil
	       && (step.groupNode != step.parent || step.comparesAggregates);
}

- (ORMPlanCondition *)conditionForStep:(ORMQueryStep *)step entity:(ORMCDEntity *)entity at:(ORMPlannerPlace *)at
                               columns:(BOOL)columns
{
	ORMPlanCondition *condition = [self plainConditionForStep:step entity:entity at:at columns:columns];
	if (![self tallies:step] || _bagNodes != nil) {
		/* A bag's: its aggregates left out. */
		return condition;
	}
	/* The aggregate, of the bag from the node it is for, compared with
	 * the value or with the other aggregate. */
	NSArray *functions = @[ @"count", @"sum", @"average", @"max", @"min" ];
	ORMPlanValue *left = [self aggregate:[functions objectAtIndex:(NSUInteger)step.aggregate] of:step.aggregateNode
	                                 for:step.groupNode];
	ORMPlanValue *right = nil;
	if (step.comparesAggregates) {
		right = [self aggregate:[functions objectAtIndex:(NSUInteger)step.comparedAggregate] of:step.aggregateNode
		                    for:step.comparedGroupNode];
	} else {
		ORMCDAttribute *attribute = step.aggregate != ORMQueryCount ? [self attributeAtEndOf:step.aggregateNode] : nil;
		right = [ORMPlanValue constant:step.aggregateValue ?: @""
		                          type:step.aggregate == ORMQueryCount ? @"Integer 64" : attribute.attributeType ?: @"Double"];
	}
	if (left == nil || right == nil) {
		return condition;
	}
	ORMPlanCondition *compared = [ORMPlanCondition compare:left comparison:step.countComparison with:right];
	return condition != nil ? ORMAllOf(@[ condition, compared ]) : compared;
}

/* The attribute a node's value is: its own, or its identifier's. */
- (ORMCDAttribute *)attributeAtEndOf:(ORMQueryNode *)node
{
	ORMQueryNode *above = node.step.parent;
	ORMCDEntity *entity = above != nil ? [_places entityOf:above.objectType] : nil;
	ORMCDProperty *property = entity != nil ? [_places propertyOf:entity source:[ORMQueryPlaces sourceOfRole:node.role]] : nil;
	if ([property isKindOfClass:[ORMCDAttribute class]]) {
		return (ORMCDAttribute *)property;
	}
	ORMCDEntity *own = [_places entityOf:node.objectType];
	return own != nil ? [_places identifierOf:node.objectType on:own] : nil;
}

/* An aggregate of the node for the group, a node above it, as ConQuer-II
 * says one: of a bag, the whole query planned again, its aggregates left
 * out, listing the group and the nodes from it down to the node; its rows
 * each way they are bound once. The aggregate's tuples are those whose
 * group is the object the group node is here. nil, noted, where that is
 * not to be said. */
- (ORMPlanValue *)aggregate:(NSString *)function of:(ORMQueryNode *)node for:(ORMQueryNode *)group
{
	return [self aggregate:function of:node for:group also:@[]];
}

/* A bag's key: what it is for, and of. */
- (NSString *)bagKeyOf:(ORMQueryNode *)node for:(ORMQueryNode *)group also:(NSArray<ORMQueryNode *> *)others
{
	NSMutableArray *groups = [NSMutableArray arrayWithObject:group.identifier ?: @""];
	for (ORMQueryNode *other in others) {
		[groups addObject:other.identifier ?: @""];
	}
	return [NSString stringWithFormat:@"%@/%@", [groups componentsJoinedByString:@","], node.identifier];
}

/* The same for several nodes: of the group's tuples, those whose columns
 * for the others are what those are here. */
- (ORMPlanValue *)aggregate:(NSString *)function
                         of:(ORMQueryNode *)node
                        for:(ORMQueryNode *)group
                       also:(NSArray<ORMQueryNode *> *)others
{
	NSMutableSet *nodes = [NSMutableSet setWithObject:group.identifier];
	ORMQueryNode *at = node;
	for (; at != nil && at != group; at = at.step.parent ?: at.valueOf) {
		[nodes addObject:at.identifier];
	}
	ORMPlannerPlace *place = [_reached objectForKey:group.identifier];
	if (at == nil || place == nil || ![self inScope:place] || place.parts != nil) {
		[self note:[NSString stringWithFormat:@"%@(%@) for %@: %@ is not %@.", function, [node designation],
		                                      [group designation], [group designation],
		                                      at == nil ? @"above it" : @"one object reached where it is asked"]];
		return nil;
	}
	/* Each other node's value here; listed by the bag. */
	NSMutableArray *alsoColumns = [NSMutableArray array];
	NSMutableArray *alsoValues = [NSMutableArray array];
	for (ORMQueryNode *other in others) {
		ORMPlannerPlace *there = [_reached objectForKey:other.identifier];
		if (there == nil || ![self inScope:there] || there.parts != nil) {
			[self note:[NSString stringWithFormat:@"%@(%@) for %@: %@ is not one value where it is asked.", function,
			                                      [node designation], [other designation], [other designation]]];
			return nil;
		}
		ORMCDAttribute *otherKey = there.entity != nil ? [_places identifierOf:other.objectType on:there.entity] : nil;
		ORMPlanValue *its = there.value ?: [ORMPlanValue valueAtPath:otherKey != nil ? [[self pathOf:there] pathByAddingKey:otherKey.name]
		                                                                             : [self pathOf:there]];
		[nodes addObject:other.identifier];
		[alsoColumns addObject:other.identifier];
		[alsoValues addObject:its];
	}
	NSString *key = [self bagKeyOf:node for:group also:others];
	ORMPlanDefinition *bag = [_bags objectForKey:key];
	if (bag == nil) {
		ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithCoreData:_coreData];
		planner->_query = _query;
		planner->_notes = [NSMutableArray array];
		planner->_variables = _variables;
		planner->_scope = [NSMutableArray array];
		planner->_reached = [NSMutableDictionary dictionary];
		planner->_columns = [NSMutableArray array];
		planner->_outerNames = [NSMutableArray array];
		planner->_outers = _outers;
		/* What it defines, the query's too, before it. */
		planner->_definitions = _definitions;
		planner->_bags = [NSMutableDictionary dictionary];
		planner->_bagNodes = nodes;
		planner->_bagging = [(_bagging ?: [NSSet set]) setByAddingObject:key];
		ORMQueryPlan *plan = [planner planned];
		_variables = planner->_variables;
		_outers = planner->_outers;
		bag = [self define:@"bag" plan:plan];
		[_bags setObject:bag forKey:key];
	}
	/* The group as its column has it: by its identifier, where it has one. */
	ORMPlanPath *groupPath = [self pathOf:place];
	ORMCDAttribute *identifier = place.entity != nil ? [_places identifierOf:group.objectType on:place.entity] : nil;
	if (identifier != nil) {
		groupPath = [groupPath pathByAddingKey:identifier.name];
	}
	return [ORMPlanValue aggregate:function of:node.identifier in:bag where:group.identifier is:groupPath also:alsoColumns
	                           are:alsoValues];
}

/* What the step's property is traced by, on the entity it starts from: a
 * unary's implicit role, a binary's far role, an n-ary or objectified fact
 * type's inverse. nil for a subtype link. */
- (NSString *)sourceOfStep:(ORMQueryStep *)step
{
	if ([step isSubtyping]) {
		return nil;
	}
	if ([step.nodes count] == 0) {
		for (ORMRole *role in step.factType.roles) {
			if (role != step.entryRole) {
				return [ORMQueryPlaces sourceOfRole:role];
			}
		}
		return nil;
	}
	if ([step.nodes count] == 1) {
		return [ORMQueryPlaces sourceOfRole:[(ORMQueryNode *)[step.nodes firstObject] role]];
	}
	return [step.factType.identifier stringByAppendingFormat:@".%@", step.entryRole.identifier];
}

/* Through a joined entity type's members to the one that has the step's
 * property: each hop a join that binds its row, by the values that
 * correlate it; the step planned from the last. Maybe: or none. */
- (ORMPlanCondition *)throughMembers:(NSArray<NSArray *> *)hops step:(ORMQueryStep *)step at:(ORMPlannerPlace *)at
                             columns:(BOOL)columns
{
	NSArray *places = [self enter:hops];
	ORMPlannerPlace *last = [places lastObject];
	ORMPlanCondition *body = [self plainConditionForStep:step entity:last.entity at:last columns:columns];
	return [self leave:hops places:places from:at where:body optional:step.operatorKind == ORMQueryMaybe];
}

/* A place for each hop's row, its variable in scope until left. */
- (NSArray<ORMPlannerPlace *> *)enter:(NSArray<NSArray *> *)hops
{
	NSMutableArray *places = [NSMutableArray array];
	for (NSArray *hop in hops) {
		NSString *variable = [self nextVariable];
		[_scope addObject:variable];
		ORMPlannerPlace *place = [ORMPlannerPlace variable:variable entity:[hop firstObject] trail:@[]];
		place.isJoined = YES;
		[places addObject:place];
	}
	return places;
}

/* The hops' places out of scope; each a join that binds its row, by the
 * values that correlate it with the row before, around what is planned
 * from the last. */
- (ORMPlanCondition *)leave:(NSArray<NSArray *> *)hops
                     places:(NSArray<ORMPlannerPlace *> *)places
                       from:(ORMPlannerPlace *)at
                      where:(ORMPlanCondition *)body
                   optional:(BOOL)optional
{
	for (NSUInteger i = [hops count]; i-- > 0;) {
		[_scope removeLastObject];
		NSArray *hop = [hops objectAtIndex:i];
		ORMCDEntity *member = [hop firstObject];
		ORMPlannerPlace *before = i > 0 ? [places objectAtIndex:i - 1] : at;
		NSMutableArray *pairs = [NSMutableArray array];
		for (NSArray *names in [hop objectAtIndex:1]) {
			[pairs addObject:@[ [before.path pathByAddingKey:[names firstObject]],
				                [ORMPlanPath pathFrom:nil keys:@[ [names lastObject] ]] ]];
		}
		ORMPlanDefinition *rows = [self define:@"member"
		                                  plan:[ORMQueryPlan planReading:member.name where:nil columns:@[] sorts:@[] notes:@[]]];
		body = [ORMPlanCondition matchesDefinition:rows
		                                     pairs:pairs
		                                   binding:[[places objectAtIndex:i] path].variable
		                                     where:body
		                                  optional:optional];
	}
	return body;
}

- (ORMPlanCondition *)plainConditionForStep:(ORMQueryStep *)step entity:(ORMCDEntity *)entity at:(ORMPlannerPlace *)at
                                    columns:(BOOL)columns
{
	/* A property another member of the entity's join has. */
	NSString *held = [self sourceOfStep:step];
	if (held != nil && entity != nil && [_places propertyOf:entity source:held] == nil) {
		NSArray *hops = [_places joinsTo:held from:entity];
		if (hops != nil) {
			return [self throughMembers:hops step:step at:at columns:columns];
		}
	}
	if ([step isSubtyping]) {
		return [self subtypeStep:step entity:entity at:at columns:columns];
	}
	if ([step.nodes count] == 0) {
		/* A unary: its attribute is true. */
		for (ORMRole *role in step.factType.roles) {
			ORMCDProperty *property = role != step.entryRole ? [_places propertyOf:entity source:[ORMQueryPlaces sourceOfRole:role]] : nil;
			if ([property isKindOfClass:[ORMCDAttribute class]]) {
				return [ORMPlanCondition compare:[ORMPlanValue valueAtPath:[at.path pathByAddingKey:property.name]]
				                      comparison:@"=" with:[ORMPlanValue constant:@"true" type:@"Boolean"]];
			}
		}
		[self note:[NSString stringWithFormat:@"\"%@\" maps to no attribute of %@.",
		                                      [step.factType displayText],
		                                      entity.name]];
		return nil;
	}
	if ([step.nodes count] == 1) {
		ORMQueryNode *node = [step.nodes firstObject];
		ORMCDProperty *property = [_places propertyOf:entity source:[ORMQueryPlaces sourceOfRole:node.role]];
		if (property != nil) {
			return [self binaryStep:step node:node property:property at:at columns:columns];
		}
		if ([[_places absorbedParts:node.role.identifier on:entity] count] > 0) {
			ORMPlanCondition *absorbed = [self absorbed:node base:node.role.identifier entity:entity at:at columns:columns];
			/* Maybe: its parts are the object's own, reached and listed as
			 * they are (nothing where there is none); nothing asked. */
			if (step.operatorKind == ORMQueryMaybe) {
				if ([self asksSomethingBelow:node]) {
					[self note:[NSString stringWithFormat:@"%@ is absorbed: what is said of it under a maybe is not asked.",
					                                      node.objectType.name]];
				}
				return nil;
			}
			return absorbed;
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
	return [self binaryStep:step node:node property:property at:at columns:columns value:NO];
}

/* The same; with value, the place is the attribute's value itself (a
 * variable a maybe binds to it), not the object it is of. Its conditions
 * only: nil for none. */
- (ORMPlanCondition *)binaryStep:(ORMQueryStep *)step
                            node:(ORMQueryNode *)node
                        property:(ORMCDProperty *)property
                              at:(ORMPlannerPlace *)at
                         columns:(BOOL)columns
                           value:(BOOL)isValue
{
	if (isValue) {
		if (columns) {
			[self column:node place:at identifier:nil];
		}
		NSMutableArray *parts = [NSMutableArray arrayWithArray:[self correlationsOf:node place:at]];
		[self reach:node place:at];
		if (node.comparison != nil && node.comparedNode == nil) {
			[parts addObject:[ORMPlanCondition compare:[ORMPlanValue valueAtPath:at.path] comparison:node.comparison
			                                      with:[self constant:node.value attribute:(ORMCDAttribute *)property]]];
		}
		return ORMAllOf(parts);
	}
	if ([property isKindOfClass:[ORMCDAttribute class]]) {
		ORMCDAttribute *attribute = (ORMCDAttribute *)property;
		ORMPlannerPlace *value = [at adding:attribute entity:nil];
		if (step != nil && step.operatorKind == ORMQueryMaybe) {
			/* Maybe: the value, bound, where it meets its conditions. */
			NSString *variable = [self nextVariable];
			[_scope addObject:variable];
			ORMPlanCondition *body = [self binaryStep:nil node:node property:attribute
			                                       at:[ORMPlannerPlace variable:variable entity:nil trail:value.trail]
			                                  columns:columns value:YES];
			[_scope removeLastObject];
			return [ORMPlanCondition maybe:value.path variable:variable where:body];
		}
		if (columns) {
			[self column:node place:value identifier:nil];
		}
		/* An object type absorbed as its identifier's value (a currency, as
		 * its code): its steps to a fact type kept as an entity of its own
		 * are joins on that value; others are left out. */
		NSMutableArray *joined = [NSMutableArray array];
		for (ORMQueryStep *further in node.steps) {
			ORMPlanCondition *join = [self stepFromValue:further at:value columns:columns && further.operatorKind != ORMQueryNot];
			if (join == nil) {
				[self note:[NSString stringWithFormat:@"%@ is an attribute: what is said of it further is left out.",
				                                      node.objectType.name]];
				continue;
			}
			[joined addObject:further.operatorKind == ORMQueryNot ? [ORMPlanCondition not:join] : join];
		}
		if (step != nil && step.countComparison != nil && ![self tallies:step]) {
			[self note:[NSString stringWithFormat:@"%@ is one attribute: it is not counted.", node.objectType.name]];
		}
		NSMutableArray *parts = [NSMutableArray arrayWithArray:[self correlationsOf:node place:value]];
		[self reach:node place:value];
		if (node.comparison != nil && node.comparedNode == nil) {
			[parts addObject:[ORMPlanCondition compare:[ORMPlanValue valueAtPath:value.path] comparison:node.comparison
			                                      with:[self constant:node.value attribute:attribute]]];
		}
		if ([joined count] > 0) {
			[parts insertObject:[ORMPlanCondition notNull:value.path] atIndex:0];
			[parts addObjectsFromArray:node.combinesWithOr ? @[ ORMAnyOf(joined) ] : joined];
		}
		return ORMAllOf(parts) ?: [ORMPlanCondition notNull:value.path];
	}
	ORMCDRelationship *relationship = (ORMCDRelationship *)property;
	ORMCDEntity *destination = [self destinationOf:relationship];
	ORMPlannerPlace *reached = [at adding:relationship entity:destination];
	if (step != nil && step.operatorKind == ORMQueryMaybe) {
		/* Maybe: each object the path reaches that meets the conditions
		 * below, bound; or none, nothing required (an outer join). */
		NSString *variable = [self nextVariable];
		[_scope addObject:variable];
		ORMPlanCondition *body = [self conditionFor:node entity:destination
		                                         at:[ORMPlannerPlace variable:variable entity:destination trail:reached.trail]
		                                    columns:columns];
		[_scope removeLastObject];
		return [ORMPlanCondition maybe:reached.path variable:variable where:body];
	}
	if (!relationship.toMany) {
		if (step != nil && step.countComparison != nil && ![self tallies:step]) {
			[self note:[NSString stringWithFormat:@"%@ is one at most: it is not counted.", node.objectType.name]];
		}
		/* Through nothing, no condition holds: the condition says it is set,
		 * or it is said beside one that holds of nothing (a not). */
		return ORMThrough(reached.path, [self conditionFor:node entity:destination at:reached columns:columns]);
	}
	NSString *variable = [self nextVariable];
	[_scope addObject:variable];
	ORMPlanCondition *body = [self conditionFor:node entity:destination
	                                         at:[ORMPlannerPlace variable:variable entity:destination trail:reached.trail]
	                                    columns:columns];
	[_scope removeLastObject];
	return [self aggregated:reached.path variable:variable body:body member:destination through:nil from:node step:step];
}

/* A step from a value (an object type absorbed as its identifier's) to a
 * fact type kept as an entity of its own: each of its objects whose
 * entry role's attribute is the value, bound, its other roles' players
 * planned from it; a maybe's optional. nil where the fact type is no
 * entity, or keeps the entry role in no attribute. */
- (ORMPlanCondition *)stepFromValue:(ORMQueryStep *)step at:(ORMPlannerPlace *)value columns:(BOOL)columns
{
	ORMCDEntity *factEntity = [_coreData entityWithSource:step.factType.identifier];
	ORMCDProperty *entry = factEntity != nil ? [_places propertyOf:factEntity source:[ORMQueryPlaces sourceOfRole:step.entryRole]]
	                                         : nil;
	if (![entry isKindOfClass:[ORMCDAttribute class]] || step.countComparison != nil) {
		return nil;
	}
	NSString *variable = [self nextVariable];
	[_scope addObject:variable];
	ORMPlannerPlace *inner = [ORMPlannerPlace variable:variable entity:factEntity trail:@[]];
	inner.isJoined = YES;
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMQueryNode *node in step.nodes) {
		ORMCDProperty *rolePlace = [_places propertyOf:factEntity source:[ORMQueryPlaces sourceOfRole:node.role]];
		if (rolePlace == nil) {
			[self note:[NSString stringWithFormat:@"%@'s role in \"%@\" maps to nothing.", node.objectType.name,
			                                      [step.factType displayText]]];
			continue;
		}
		ORMPlanCondition *part = [self binaryStep:nil node:node property:rolePlace at:inner columns:columns];
		if (part != nil && (node.comparison != nil || [node.steps count] > 0 || node.label != nil || node.comparedNode != nil)) {
			[parts addObject:part];
		}
	}
	[_scope removeLastObject];
	ORMPlanDefinition *rows = [self define:@"member"
	                                  plan:[ORMQueryPlan planReading:factEntity.name where:nil columns:@[] sorts:@[] notes:@[]]];
	return [ORMPlanCondition matchesDefinition:rows
	                                     pairs:@[ @[ value.path, [ORMPlanPath pathFrom:nil keys:@[ entry.name ]] ] ]
	                                   binding:variable
	                                     where:ORMAllOf(parts)
	                                  optional:step.operatorKind == ORMQueryMaybe];
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
			                                      node.objectType.name, [fact displayText],
			                                      entity.name, node.objectType.name]];
		} else {
			[self note:[NSString stringWithFormat:@"\"%@\" maps to nothing %@ reaches.",
			                                      [fact displayText], entity.name]];
		}
		return nil;
	}
	ORMPlannerPlace *reached = [at adding:relationship entity:factEntity];
	BOOL maybe = step.operatorKind == ORMQueryMaybe;
	NSString *variable = relationship.toMany || maybe ? [self nextVariable] : nil;
	ORMPlannerPlace *inner = variable != nil ? [ORMPlannerPlace variable:variable entity:factEntity trail:reached.trail]
	                                         : reached;
	if (variable != nil) {
		[_scope addObject:variable];
	}
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMQueryNode *node in step.nodes) {
		ORMCDProperty *rolePlace = [_places propertyOf:factEntity source:[ORMQueryPlaces sourceOfRole:node.role]];
		if (rolePlace == nil) {
			[self note:[NSString stringWithFormat:@"%@'s role in \"%@\" maps to nothing.", node.objectType.name,
			                                      [fact displayText]]];
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
	if (maybe) {
		return [ORMPlanCondition maybe:reached.path variable:variable where:body];
	}
	if (variable == nil) {
		return ORMThrough(reached.path, body);
	}
	ORMQueryNode *start = nil;
	ORMCDProperty *firstHop = nil;
	for (ORMQueryNode *node in step.nodes) {
		for (ORMQueryNode *above = step.aggregateNode; above != nil && start == nil; above = above.step.parent) {
			if (above == node) {
				start = node;
				firstHop = [_places propertyOf:factEntity source:[ORMQueryPlaces sourceOfRole:node.role]];
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
	ORMPlanCondition *exists = [ORMPlanCondition exists:collection variable:body != nil || [self lists:variable] ? variable : nil
	                                              where:body];
	if (step == nil || step.countComparison == nil || [self tallies:step]) {
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

/* Whether the node, or one below it, has a condition: a comparison, a not,
 * an alternative, a count; a label alone asks nothing. */
- (BOOL)asksSomethingBelow:(ORMQueryNode *)node
{
	if (node.comparison != nil || node.combinesWithOr) {
		return YES;
	}
	for (ORMQueryStep *step in node.steps) {
		if (step.operatorKind == ORMQueryNot || step.countComparison != nil) {
			return YES;
		}
		for (ORMQueryNode *next in step.nodes) {
			if ([self asksSomethingBelow:next]) {
				return YES;
			}
		}
	}
	return NO;
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
			ORMCDProperty *property = [_places propertyOf:entity source:[ORMQueryPlaces sourceOfRole:next.role]];
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
	if (node.comparison != nil && node.comparedNode == nil) {
		[self note:[NSString stringWithFormat:@"%@ is absorbed: it has no one value to compare with %@.",
		                                      node.objectType.name, node.value ?: @""]];
	}
	if (columns && node.isProjected) {
		/* By its identifying values, all of them, as an entity no one
		 * attribute identifies is listed. */
		NSArray *identifying = [_places identifyingPartsOfAbsorbed:node.objectType base:base on:entity];
		if (identifying != nil && _bagNodes == nil) {
			[_columns addObject:@[ node, at, [NSNull null], identifying ]];
		} else {
			[self column:node place:[at adding:firstPart entity:nil] identifier:nil];
		}
	}
	/* Where it is, as its parts are: what another occurrence is compared
	 * with, part by part. */
	NSMutableArray *partPlaces = [NSMutableArray array];
	for (NSArray *part in [parts sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		     return [[(ORMCDProperty *)[a lastObject] name] compare:[(ORMCDProperty *)[b lastObject] name]];
	     }]) {
		ORMCDProperty *property = [part lastObject];
		ORMCDEntity *reached = [property isKindOfClass:[ORMCDRelationship class]]
			? [self destinationOf:(ORMCDRelationship *)property] : nil;
		[partPlaces addObject:@[ [part firstObject], [at adding:property entity:reached] ]];
	}
	ORMPlannerPlace *place = [ORMPlannerPlace variable:at.path.variable entity:nil trail:at.trail];
	place.path = at.path;
	place.parts = partPlaces;
	NSMutableArray *conditions = [NSMutableArray arrayWithArray:[self correlationsOf:node place:place]];
	[self reach:node place:place];
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
	NSString *what = [step.factType displayText];
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
