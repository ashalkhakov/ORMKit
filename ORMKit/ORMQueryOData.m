/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryOData.h"
#import "ORMQueryPlaces.h"
#import "ORMCDModel+CoreData.h"
#import <CoreData/CoreData.h>
#import <ODataKit/ODataApply.h>
#import <ODataKit/ODataExpression.h>
#import <ODataKit/ODataPropertyMapper.h>
#import <ODataIncrementalStore/ODataQueryBuilder.h>

/* Where the translation stands: an object or a value, reached from a lambda's
 * variable (nil: from the object fetched, $it) through properties, each an
 * ORMCDProperty or, for a cast, the type's qualified name. The trail is the
 * same reached from the object fetched, through relationships, casts left
 * out. */
@interface ORMODataPlace : NSObject
@property (nonatomic, copy) NSString *variable;
@property (nonatomic, copy) NSArray *steps;
@property (nonatomic, copy) NSArray<ORMCDProperty *> *trail;
/* What is there: an object of the entity, or a value (nil). */
@property (nonatomic, strong) ORMCDEntity *entity;
@end

@implementation ORMODataPlace

+ (instancetype)variable:(NSString *)variable entity:(ORMCDEntity *)entity trail:(NSArray *)trail
{
	ORMODataPlace *place = [[self alloc] init];
	place.variable = variable;
	place.steps = @[];
	place.trail = trail ?: @[];
	place.entity = entity;
	return place;
}

/* On through a property; entity is where a relationship leads, nil for an
 * attribute. */
- (ORMODataPlace *)adding:(ORMCDProperty *)property entity:(ORMCDEntity *)entity
{
	ORMODataPlace *place = [[ORMODataPlace alloc] init];
	place.variable = self.variable;
	place.steps = [self.steps arrayByAddingObject:property];
	place.trail = [self.trail arrayByAddingObject:property];
	place.entity = entity;
	return place;
}

- (ORMODataPlace *)castTo:(NSString *)type entity:(ORMCDEntity *)entity
{
	ORMODataPlace *place = [[ORMODataPlace alloc] init];
	place.variable = self.variable;
	place.steps = [self.steps arrayByAddingObject:type];
	place.trail = self.trail;
	place.entity = entity;
	return place;
}

- (BOOL)isFetched
{
	return self.variable == nil && [self.steps count] == 0;
}

@end

@interface ORMQueryODataJoin ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *entityName;
@property (nonatomic, readwrite, copy) NSString *collectionPath;
@property (nonatomic, readwrite, strong) ODataQueryOptions *options;
@property (nonatomic, readwrite, copy) NSArray<NSArray<NSArray<NSString *> *> *> *pairs;
@end

@implementation ORMQueryODataJoin
{
	@public
	ODataPropertyMapper *_mapper;
}

- (NSURL *)URLWithServiceRoot:(NSURL *)serviceRoot error:(NSError **)error
{
	ODataQueryBuilder *builder = [[ODataQueryBuilder alloc] initWithMapper:_mapper serviceRoot:serviceRoot];
	return [builder URLForPath:self.collectionPath options:self.options error:error];
}

@end

/* A level of $select and $expand: what is selected there, and what is
 * expanded from it, each its own level. */
@interface ORMODataLevel : NSObject
@property (nonatomic, strong) ORMCDEntity *entity;
@property (nonatomic, strong) NSMutableArray<NSString *> *select;
@property (nonatomic, strong) NSMutableArray<NSString *> *expandNames;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ORMODataLevel *> *expand;
/* An entity listed that has no simple identifier: all of it. */
@property (nonatomic) BOOL all;
@end

@implementation ORMODataLevel

+ (instancetype)levelOf:(ORMCDEntity *)entity
{
	ORMODataLevel *level = [[self alloc] init];
	level.entity = entity;
	level.select = [NSMutableArray array];
	level.expandNames = [NSMutableArray array];
	level.expand = [NSMutableDictionary dictionary];
	return level;
}

- (ORMODataLevel *)expanding:(NSString *)name entity:(ORMCDEntity *)entity
{
	ORMODataLevel *level = [self.expand objectForKey:name];
	if (level == nil) {
		level = [ORMODataLevel levelOf:entity];
		[self.expand setObject:level forKey:name];
		[self.expandNames addObject:name];
	}
	return level;
}

- (void)selecting:(NSString *)name
{
	if (![self.select containsObject:name]) {
		[self.select addObject:name];
	}
}

@end

static NSDictionary<NSString *, NSString *> *
ORMODataOperators(void)
{
	return @{ @"=": @"eq", @"<>": @"ne", @"<": @"lt", @"<=": @"le", @">": @"gt", @">=": @"ge" };
}

static ODataExpression *
ORMAll(NSArray<ODataExpression *> *parts, NSString *connective)
{
	ODataExpression *combined = nil;
	for (ODataExpression *part in parts) {
		combined = combined != nil ? [ODataExpression binary:connective left:combined right:part] : part;
	}
	return combined;
}

static BOOL
ORMIsNumber(NSString *text)
{
	NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
	double number = 0;
	return [scanner scanDouble:&number] && [scanner isAtEnd];
}

static NSString *
ORMQueryTextOf(ODataQueryOptions *options)
{
	NSMutableArray *items = [NSMutableArray array];
	for (NSArray<NSString *> *item in [options queryItems]) {
		[items addObject:[item componentsJoinedByString:@"="]];
	}
	return [items componentsJoinedByString:@"&"];
}

static NSString *
ORMRequestLine(NSString *path, ODataQueryOptions *options)
{
	NSString *query = ORMQueryTextOf(options);
	return [NSString stringWithFormat:@"GET %@%@%@\n", path, [query length] > 0 ? @"?" : @"", query];
}

@implementation ORMQueryOData
{
	ORMQuery *_query;
	ORMCDModel *_coreData;
	ORMQueryPlaces *_places;
	/* The model as Core Data has it, and ODataKit's names for it. */
	NSManagedObjectModel *_managed;
	ODataPropertyMapper *_mapper;
	/* Each mapped property, as Core Data describes it. */
	NSMapTable<ORMCDProperty *, NSPropertyDescription *> *_described;
	NSMutableArray<NSString *> *_notes;
	ORMCDEntity *_fetched;
	NSString *_entityName;
	NSString *_collectionPath;
	ODataExpression *_filter;
	ODataQueryOptions *_options;
	NSUInteger _variables;
	/* The lambdas' variables open where the translation is. */
	NSMutableArray<NSString *> *_scope;
	/* Each node reached: where. */
	NSMutableDictionary<NSString *, ORMODataPlace *> *_reached;
	/* The ticked nodes: where, and the identifier they are listed by. */
	NSMutableArray<NSArray *> *_columns;
	NSMutableArray<ORMQueryODataJoin *> *_joins;
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
		_places = [[ORMQueryPlaces alloc] initWithCoreData:coreData];
		_managed = [coreData managedObjectModel];
		_mapper = [[ODataPropertyMapper alloc] init];
		_described = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
		                                   valueOptions:NSPointerFunctionsStrongMemory];
		for (ORMCDEntity *entity in coreData.entities) {
			NSEntityDescription *described = [[_managed entitiesByName] objectForKey:entity.name];
			for (ORMCDProperty *property in [entity properties]) {
				NSPropertyDescription *same = [[described propertiesByName] objectForKey:property.name];
				if (same != nil) {
					[_described setObject:same forKey:property];
				}
			}
		}
		_notes = [NSMutableArray array];
		_scope = [NSMutableArray array];
		_reached = [NSMutableDictionary dictionary];
		_columns = [NSMutableArray array];
		_joins = [NSMutableArray array];
		[self translate];
	}
	return self;
}

- (NSString *)entityName
{
	return _entityName;
}

- (NSString *)collectionPath
{
	return _collectionPath;
}

- (ODataExpression *)filter
{
	return _filter;
}

- (ODataQueryOptions *)options
{
	return _options;
}

- (NSArray<ORMQueryODataJoin *> *)joins
{
	return [_joins copy];
}

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
}

- (BOOL)isComplete
{
	return _entityName != nil && [_notes count] == 0;
}

- (NSString *)queryText
{
	return ORMQueryTextOf(_options);
}

- (NSURL *)URLWithServiceRoot:(NSURL *)serviceRoot error:(NSError **)error
{
	if (_collectionPath == nil) {
		return nil;
	}
	ODataQueryBuilder *builder = [[ODataQueryBuilder alloc] initWithMapper:_mapper serviceRoot:serviceRoot];
	return [builder URLForPath:_collectionPath options:_options error:error];
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
		NSMutableArray *parts = [NSMutableArray array];
		for (ORMQueryODataJoin *join in _joins) {
			NSMutableArray *pairs = [NSMutableArray array];
			for (NSArray *pair in join.pairs) {
				[pairs addObject:[NSString stringWithFormat:@"%@ eq %@.%@", [[pair firstObject] componentsJoinedByString:@"/"],
				                                            join.name, [[pair lastObject] componentsJoinedByString:@"/"]]];
			}
			[parts addObject:[pairs componentsJoinedByString:@" and "]];
		}
		[text appendFormat:@"then, with the parts of one row of each (or of any, with or): %@\n",
		                   [parts componentsJoinedByString:@"; "]];
	}
	[text appendString:ORMRequestLine(_collectionPath, _options)];
	return text;
}

#pragma mark Names

/* Every name is ODataKit's: its property mapper's, of the model as Core
 * Data describes it. */
- (NSEntityDescription *)described:(ORMCDEntity *)entity
{
	return entity != nil ? [[_managed entitiesByName] objectForKey:entity.name] : nil;
}

- (NSString *)wire:(ORMCDProperty *)property
{
	NSPropertyDescription *described = [_described objectForKey:property];
	if ([described isKindOfClass:[NSAttributeDescription class]]) {
		return [_mapper propertyForAttribute:(NSAttributeDescription *)described];
	}
	if ([described isKindOfClass:[NSRelationshipDescription class]]) {
		return [_mapper propertyForRelationship:(NSRelationshipDescription *)described];
	}
	return [_mapper wireName:property.name];
}

- (NSArray<NSString *> *)wirePath:(NSArray *)properties
{
	NSMutableArray *path = [NSMutableArray array];
	for (id step in properties) {
		[path addObject:[step isKindOfClass:[NSString class]] ? step : [self wire:step]];
	}
	return path;
}

/* The wire names of the attributes the service keys the entity by, in the
 * order of their names. */
- (NSArray<NSString *> *)keyOf:(ORMCDEntity *)entity
{
	NSEntityDescription *described = [self described:entity];
	NSMutableArray *names = [NSMutableArray array];
	NSArray *key = described != nil ? [_mapper keyAttributesForEntity:described] : @[];
	for (NSAttributeDescription *attribute in [key sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]]) {
		[names addObject:[_mapper propertyForAttribute:attribute]];
	}
	return names;
}

/* Where the entity's objects are read from: its set, cast where it is a
 * derived type there. */
- (NSString *)collectionPathOf:(ORMCDEntity *)entity
{
	return [_mapper collectionPathForEntity:[self described:entity]];
}

- (NSString *)typeNameOf:(ORMCDEntity *)entity
{
	return [_mapper qualifiedTypeForEntity:[self described:entity]];
}

#pragma mark Expressions

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

- (BOOL)inScope:(ORMODataPlace *)place
{
	return place.variable == nil || [_scope containsObject:place.variable];
}

/* What the place says: from its variable, or from $it, written as such
 * inside a lambda, where it is not the variable's. */
- (ODataExpression *)expression:(ORMODataPlace *)place
{
	ODataExpression *at = place.variable != nil ? [ODataExpression variable:place.variable]
		: ([_scope count] > 0 ? [ODataExpression variable:@"$it"] : nil);
	for (id step in place.steps) {
		at = [step isKindOfClass:[NSString class]] ? [ODataExpression cast:step of:at]
		                                          : [ODataExpression member:[self wire:step] of:at];
	}
	return at ?: [ODataExpression variable:@"$it"];
}

- (ODataExpression *)literal:(NSString *)value forAttribute:(ORMCDAttribute *)attribute
{
	NSString *type = attribute.attributeType;
	if (([type hasPrefix:@"Integer"] || [@[ @"Decimal", @"Double", @"Float" ] containsObject:type]) && ORMIsNumber(value)) {
		ODataExpression *number = [ODataExpression literalWithText:value];
		if (number != nil) {
			return number;
		}
	}
	if ([type isEqualToString:@"Boolean"]) {
		NSString *lower = [value lowercaseString];
		if ([@[ @"true", @"yes", @"1" ] containsObject:lower]) {
			return [ODataExpression literalWithValue:@YES];
		}
		if ([@[ @"false", @"no", @"0" ] containsObject:lower]) {
			return [ODataExpression literalWithValue:@NO];
		}
	}
	if ([type isEqualToString:@"Date"]) {
		/* Read as one literal, and taken only if it is a date: anything
		 * else the condition says is a string, quoted by ODataKit. */
		ODataExpression *date = [ODataExpression literalWithText:value ?: @""];
		if (date.kind == ODataExpressionLiteral
		    && ([date.literalType isEqualToString:@"Edm.Date"] || [date.literalType isEqualToString:@"Edm.DateTimeOffset"])) {
			return date;
		}
	}
	return [ODataExpression literalWithValue:value ?: @""];
}

- (ODataExpression *)isNotNull:(ORMODataPlace *)place
{
	return [ODataExpression binary:@"ne" left:[self expression:place] right:[ODataExpression literalWithValue:[NSNull null]]];
}

/* Two objects the same: their keys equal. nil when the entity has none. */
- (ODataExpression *)object:(ODataExpression *)left is:(ODataExpression *)right entity:(ORMCDEntity *)entity
{
	NSArray *key = [self keyOf:entity];
	if ([key count] == 0) {
		[self note:[NSString stringWithFormat:@"%@ has no key in OData: the mapping does not serve it.", entity.name]];
		return nil;
	}
	NSMutableArray *parts = [NSMutableArray array];
	for (NSString *name in key) {
		[parts addObject:[ODataExpression binary:@"eq" left:[ODataExpression member:name of:left]
		                                    right:[ODataExpression member:name of:right]]];
	}
	return ORMAll(parts, @"and");
}

#pragma mark Columns

- (void)column:(ORMQueryNode *)node place:(ORMODataPlace *)place identifier:(ORMCDAttribute *)identifier
{
	if (node.isProjected) {
		[_columns addObject:@[ node, place, identifier ?: [NSNull null] ]];
	}
}

/* $select and $expand: each listed node's identifier, or its value, at the
 * level its trail expands to; the key wherever nothing else is. */
- (void)selectInto:(ODataMutableQueryOptions *)options
{
	ORMODataLevel *top = [ORMODataLevel levelOf:_fetched];
	for (NSArray *column in _columns) {
		ORMODataPlace *place = [column objectAtIndex:1];
		id identifier = [column lastObject];
		ORMODataLevel *level = top;
		NSArray *trail = place.trail;
		NSUInteger end = place.entity != nil ? [trail count] : [trail count] - 1;
		for (NSUInteger i = 0; i < end; i++) {
			ORMCDRelationship *relationship = [trail objectAtIndex:i];
			level = [level expanding:[self wire:relationship] entity:[_coreData entityNamed:relationship.destination]];
		}
		if (place.entity == nil) {
			[level selecting:[self wire:[trail lastObject]]];
		} else if (identifier != [NSNull null]) {
			[level selecting:[self wire:identifier]];
		} else {
			level.all = YES;
		}
	}
	[self level:top into:options];
}

- (void)level:(ORMODataLevel *)level into:(ODataMutableQueryOptions *)options
{
	if (!level.all) {
		NSMutableArray *select = [NSMutableArray array];
		for (NSString *name in [self keyOf:level.entity]) {
			[select addObject:[ODataSelectItem itemWithPath:@[ name ]]];
		}
		NSMutableArray *names = [NSMutableArray array];
		for (ODataSelectItem *item in select) {
			[names addObject:[item.path firstObject]];
		}
		for (NSString *name in level.select) {
			if (![names containsObject:name]) {
				[select addObject:[ODataSelectItem itemWithPath:@[ name ]]];
			}
		}
		options.select = select;
	}
	NSMutableArray *expand = [NSMutableArray array];
	for (NSString *name in level.expandNames) {
		ODataMutableQueryOptions *inner = [[ODataMutableQueryOptions alloc] init];
		[self level:[level.expand objectForKey:name] into:inner];
		[expand addObject:[ODataExpandItem itemWithPath:@[ name ] options:inner]];
	}
	options.expand = expand;
}

/* What the results are listed in order of: each sorted node's column,
 * through to-ones only. */
- (NSArray<ODataOrderItem *> *)orderItems
{
	NSMutableArray *items = [NSMutableArray array];
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
		ORMODataPlace *place = [column objectAtIndex:1];
		id identifier = [column lastObject];
		NSMutableArray *path = [NSMutableArray arrayWithArray:place.trail ?: @[]];
		if (place.entity != nil && identifier != [NSNull null]) {
			[path addObject:identifier];
		}
		BOOL one = column != nil && (place.entity == nil || identifier != [NSNull null]);
		for (ORMCDProperty *property in place.trail) {
			one = one && !([property isKindOfClass:[ORMCDRelationship class]] && ((ORMCDRelationship *)property).toMany);
		}
		if (!one) {
			[self note:[NSString stringWithFormat:@"%@ is sorted by, but %@.", [node designation],
			                                      column == nil ? @"not listed" : @"not one value for each result"]];
			continue;
		}
		[items addObject:[ODataOrderItem itemWithExpression:[ODataExpression memberPath:[self wirePath:path] of:nil]
		                                         descending:node.sortOrder == ORMQueryDescending]];
	}
	return items;
}

#pragma mark Correlating

- (void)reached:(ORMQueryNode *)node place:(ORMODataPlace *)place
{
	[_reached setObject:place forKey:node.identifier];
}

/* The place compared with the node reached before: directly where that is
 * still in scope; else whether it is among what the node's trail reaches
 * from the object fetched, said from it back along the inverses. */
- (ODataExpression *)relate:(ORMODataPlace *)place comparison:(NSString *)comparison to:(ORMQueryNode *)other
{
	ORMODataPlace *reference = [_reached objectForKey:other.identifier];
	NSString *operator = [ORMODataOperators() objectForKey:comparison ?: @""];
	if (reference == nil || operator == nil) {
		[self note:[NSString stringWithFormat:@"%@ is compared with %@ before the query reaches it.",
		                                      [self describe:place], [other designation]]];
		return nil;
	}
	BOOL equality = [operator isEqualToString:@"eq"] || [operator isEqualToString:@"ne"];
	if ([self inScope:reference]) {
		if (place.entity == nil) {
			return [ODataExpression binary:operator left:[self expression:place] right:[self expression:reference]];
		}
		if (!equality) {
			[self note:[NSString stringWithFormat:@"%@ %@ %@ compares objects: only = and <> can.", [self describe:place],
			                                      comparison, [other designation]]];
			return nil;
		}
		ODataExpression *same = [self object:[self expression:place] is:[self expression:reference] entity:place.entity];
		return same != nil && [operator isEqualToString:@"ne"] ? [ODataExpression unary:@"not" operand:same] : same;
	}
	if (other.comparison != nil || [other.steps count] > 0) {
		[self note:[NSString stringWithFormat:@"%@ is taken as any %@ the path reaches, not only those meeting its "
		                                      @"conditions.",
		                                      [other designation], other.objectType.name]];
	}
	if (!equality) {
		[self note:[NSString stringWithFormat:@"%@ %@ %@ compares with many: only = and <> can.", [self describe:place],
		                                      comparison, [other designation]]];
		return nil;
	}
	ODataExpression *among = [self among:place trail:reference.trail];
	if (among == nil) {
		return nil;
	}
	return [operator isEqualToString:@"ne"] ? [ODataExpression unary:@"not" operand:among] : among;
}

- (NSString *)describe:(ORMODataPlace *)place
{
	return [[self expression:place] description];
}

/* The place among what the trail reaches from the object fetched: back from
 * the place along the inverse relationships, to the object fetched, which a
 * store says without a subquery inside a subquery; else forward from it. */
- (ODataExpression *)among:(ORMODataPlace *)place trail:(NSArray<ORMCDProperty *> *)trail
{
	NSMutableArray *inverses = [NSMutableArray array];
	ORMCDEntity *at = _fetched;
	BOOL back = place.entity != nil;
	for (ORMCDProperty *property in trail) {
		ORMCDRelationship *relationship = [property isKindOfClass:[ORMCDRelationship class]] ? (ORMCDRelationship *)property : nil;
		ORMCDRelationship *inverse = nil;
		if (relationship != nil && [relationship.inverseName length] > 0) {
			inverse = (ORMCDRelationship *)[_places property:relationship.inverseName
			                                             of:[_coreData entityNamed:relationship.destination]];
		}
		if (inverse == nil) {
			back = NO;
			break;
		}
		[inverses insertObject:inverse atIndex:0];
		at = [_coreData entityNamed:relationship.destination];
	}
	if (back) {
		return [self along:inverses from:[self expression:place] index:0
		              then:^ODataExpression *(ODataExpression *object) {
			return [self object:object is:[ODataExpression variable:@"$it"] entity:self->_fetched];
		}];
	}
	ODataExpression *value = [self expression:place];
	return [self along:trail from:[ODataExpression variable:@"$it"] index:0
	              then:^ODataExpression *(ODataExpression *reached) {
		return place.entity != nil ? [self object:reached is:value entity:place.entity]
		                           : [ODataExpression binary:@"eq" left:reached right:value];
	}];
}

/* Along the properties from the expression, a lambda for each to-many; the
 * block says what holds of what is reached. */
- (ODataExpression *)along:(NSArray<ORMCDProperty *> *)properties
                      from:(ODataExpression *)from
                     index:(NSUInteger)index
                      then:(ODataExpression * (^)(ODataExpression *reached))then
{
	if (index == [properties count]) {
		return then(from);
	}
	ORMCDProperty *property = [properties objectAtIndex:index];
	ODataExpression *next = [ODataExpression member:[self wire:property] of:from];
	if ([property isKindOfClass:[ORMCDRelationship class]] && ((ORMCDRelationship *)property).toMany) {
		NSString *variable = [self nextVariable];
		ODataExpression *body = [self along:properties from:[ODataExpression variable:variable] index:index + 1 then:then];
		return body != nil ? [ODataExpression lambda:@"any" of:next variable:variable body:body] : nil;
	}
	return [self along:properties from:next index:index + 1 then:then];
}

/* Being the same as an earlier node of its label, and the comparison with
 * another node. */
- (NSArray<ODataExpression *> *)correlationsOf:(ORMQueryNode *)node place:(ORMODataPlace *)place
{
	NSMutableArray *parts = [NSMutableArray array];
	ORMQueryNode *first = [_query firstOccurrenceOf:node];
	if (first != node) {
		ODataExpression *same = [self relate:place comparison:@"=" to:first];
		if (same != nil) {
			[parts addObject:same];
		}
	}
	if (node.comparedNode != nil) {
		ODataExpression *compared = [self relate:place comparison:node.comparison to:node.comparedNode];
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
		[self note:[NSString stringWithFormat:@"%@ is no entity, so there is nothing to ask for.",
		                                      root.objectType.name ?: @"The query's object type"]];
		_options = [[ODataMutableQueryOptions alloc] init];
		return;
	}
	/* Every result is of the subtype the root's required steps go down to:
	 * asked for as such, its own properties are there. */
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
	_collectionPath = [self collectionPathOf:_fetched];
	if ([[self keyOf:_fetched] count] == 0) {
		[self note:[NSString stringWithFormat:@"%@ has no key in OData, so the service does not serve it: map it "
		                                      @"with ServeOData.", _fetched.name]];
	}
	if (!_query.isComplete) {
		[self note:@"Something the query goes through is no longer in the model, and is left out."];
	}
	_filter = [self filterFor:root entity:entity at:[ORMODataPlace variable:nil entity:_fetched trail:@[]] columns:YES];
	ODataMutableQueryOptions *options = [[ODataMutableQueryOptions alloc] init];
	options.filter = _filter;
	[self selectInto:options];
	options.orderBy = [self orderItems];
	_options = options;
}

/* What the node and its steps require of the object at the place. */
- (ODataExpression *)filterFor:(ORMQueryNode *)node entity:(ORMCDEntity *)entity at:(ORMODataPlace *)at columns:(BOOL)columns
{
	NSMutableArray *parts = [NSMutableArray array];
	ORMCDAttribute *identifier = [_places identifierOf:node.objectType on:entity];
	if (columns) {
		[self column:node place:at identifier:identifier];
	}
	NSArray *correlations = [self correlationsOf:node place:at];
	[self reached:node place:at];
	[parts addObjectsFromArray:correlations];
	if (node.comparison != nil && node.comparedNode == nil) {
		NSString *operator = [ORMODataOperators() objectForKey:node.comparison];
		if (identifier != nil && operator != nil) {
			[parts addObject:[ODataExpression binary:operator left:[self expression:[at adding:identifier entity:nil]]
			                                   right:[self literal:node.value forAttribute:identifier]]];
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
		ODataExpression *filter = [self filterForStep:step entity:entity at:at columns:listed];
		_guarded -= guarded ? 1 : 0;
		if (step.operatorKind == ORMQueryMaybe || filter == nil) {
			continue;
		}
		[steps addObject:step.operatorKind == ORMQueryNot ? [ODataExpression unary:@"not" operand:filter] : filter];
	}
	ODataExpression *combined = ORMAll(steps, node.combinesWithOr ? @"or" : @"and");
	if (combined != nil) {
		[parts addObject:combined];
	}
	return ORMAll(parts, @"and");
}

- (ODataExpression *)filterForStep:(ORMQueryStep *)step entity:(ORMCDEntity *)entity at:(ORMODataPlace *)at
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
				return [ODataExpression binary:@"eq" left:[self expression:[at adding:property entity:nil]]
				                         right:[ODataExpression literalWithValue:@YES]];
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

#pragma mark Absorbed object types

- (ODataExpression *)absorbed:(ORMQueryNode *)node
                         base:(NSString *)base
                       entity:(ORMCDEntity *)entity
                           at:(ORMODataPlace *)at
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
		ODataExpression *condition = nil;
		_guarded += step.operatorKind == ORMQueryNot ? 1 : 0;
		if (part != nil) {
			condition = [self binaryStep:step node:next property:part at:at columns:columns];
		} else if ([[_places absorbedParts:partBase on:entity] count] > 0) {
			condition = [self absorbed:next base:partBase entity:entity at:at columns:columns];
		} else {
			condition = [self join:step node:next from:base entity:entity at:at];
		}
		_guarded -= step.operatorKind == ORMQueryNot ? 1 : 0;
		if (condition != nil) {
			[conditions addObject:step.operatorKind == ORMQueryNot ? [ODataExpression unary:@"not" operand:condition]
			                                                       : condition];
		}
	}
	if ([conditions count] == 0) {
		/* Played: its parts are there. */
		return [self isNotNull:[at adding:firstPart entity:nil]];
	}
	return ORMAll(conditions, @"and");
}

/* A part's wire paths: an attribute's own; a relationship's, through to its
 * destination's key. */
- (NSArray<NSArray<NSString *> *> *)partPaths:(ORMCDProperty *)part
{
	if (![part isKindOfClass:[ORMCDRelationship class]]) {
		return @[ @[ [self wire:part] ] ];
	}
	NSMutableArray *paths = [NSMutableArray array];
	ORMCDEntity *destination = [_coreData entityNamed:((ORMCDRelationship *)part).destination];
	for (NSString *name in [self keyOf:destination]) {
		[paths addObject:@[ [self wire:part], name ]];
	}
	return paths;
}

/* Through an absorbed object type to an entity that absorbs it too: the
 * joined entity is asked for first, and its parts' values are what the
 * results' must equal. */
- (ODataExpression *)join:(ORMQueryStep *)step
                     node:(ORMQueryNode *)node
                     from:(NSString *)base
                   entity:(ORMCDEntity *)entity
                       at:(ORMODataPlace *)at
{
	ORMCDEntity *joined = [_places entityOf:node.objectType];
	NSArray *ours = [_places absorbedParts:base on:entity];
	NSArray *theirs = joined != nil ? [_places absorbedParts:step.entryRole.identifier on:joined] : @[];
	NSMutableArray *pairs = [NSMutableArray array];
	NSMutableArray *selected = [NSMutableArray array];
	NSMutableArray *expanded = [NSMutableArray array];
	NSUInteger matched = 0;
	for (NSArray *part in ours) {
		for (NSArray *their in theirs) {
			if (![[part firstObject] isEqualToString:[their firstObject]]) {
				continue;
			}
			matched++;
			NSArray *ourPaths = [self partPaths:[part lastObject]];
			NSArray *theirPaths = [self partPaths:[their lastObject]];
			for (NSUInteger i = 0; i < [ourPaths count] && i < [theirPaths count]; i++) {
				NSArray *mine = [[self wirePath:at.steps] arrayByAddingObjectsFromArray:[ourPaths objectAtIndex:i]];
				[pairs addObject:@[ mine, [theirPaths objectAtIndex:i] ]];
			}
			ORMCDProperty *property = [their lastObject];
			if ([property isKindOfClass:[ORMCDRelationship class]]) {
				ODataMutableQueryOptions *key = [[ODataMutableQueryOptions alloc] init];
				NSMutableArray *keySelect = [NSMutableArray array];
				for (NSArray *path in theirPaths) {
					[keySelect addObject:[ODataSelectItem itemWithPath:@[ [path lastObject] ]]];
				}
				key.select = keySelect;
				[expanded addObject:[ODataExpandItem itemWithPath:@[ [self wire:property] ] options:key]];
			} else {
				[selected addObject:[ODataSelectItem itemWithPath:@[ [self wire:property] ]]];
			}
		}
	}
	NSString *what = [[step.factType primaryReading] expandedText] ?: step.factType.name;
	if (joined == nil || matched == 0 || matched != [ours count]) {
		[self note:[NSString stringWithFormat:@"\"%@\" joins on parts %@ does not have as %@ does.", what,
		                                      joined.name ?: node.objectType.name, entity.name]];
		return nil;
	}
	if (_guarded > 0 || [_scope count] > 0) {
		[self note:[NSString stringWithFormat:@"\"%@\" joins %@ with %@ inside a not, an or or a lambda, which takes "
		                                      @"a request for each: not made yet.",
		                                      what, entity.name, joined.name]];
		return nil;
	}
	/* What the joined objects must be, said from them. */
	NSMutableDictionary *reached = _reached;
	_reached = [NSMutableDictionary dictionary];
	ORMCDEntity *fetched = _fetched;
	_fetched = joined;
	ODataExpression *filter = [self filterFor:node entity:joined at:[ORMODataPlace variable:nil entity:joined trail:@[]]
	                                  columns:NO];
	_fetched = fetched;
	_reached = reached;
	ODataMutableQueryOptions *options = [[ODataMutableQueryOptions alloc] init];
	options.filter = filter;
	options.select = selected;
	options.expand = expanded;
	ORMQueryODataJoin *join = [[ORMQueryODataJoin alloc] init];
	join.name = [NSString stringWithFormat:@"join%lu", (unsigned long)[_joins count] + 1];
	join.entityName = joined.name;
	join.collectionPath = [self collectionPathOf:joined];
	join->_mapper = _mapper;
	join.options = options;
	join.pairs = pairs;
	[_joins addObject:join];
	return nil;
}

- (ODataExpression *)filterJoining:(NSDictionary<NSString *, NSArray<NSDictionary *> *> *)joined
{
	NSMutableArray *conjuncts = [NSMutableArray array];
	if (_filter != nil) {
		[conjuncts addObject:_filter];
	}
	for (ORMQueryODataJoin *join in _joins) {
		NSMutableArray *alternatives = [NSMutableArray array];
		for (NSDictionary *row in [joined objectForKey:join.name]) {
			NSMutableArray *parts = [NSMutableArray array];
			for (NSArray *pair in join.pairs) {
				id value = row;
				for (NSString *name in [pair lastObject]) {
					value = [value isKindOfClass:[NSDictionary class]] ? [value objectForKey:name] : nil;
				}
				[parts addObject:[ODataExpression binary:@"eq" left:[ODataExpression memberPath:[pair firstObject] of:nil]
				                                    right:[ODataExpression literalWithValue:value ?: [NSNull null]]]];
			}
			[alternatives addObject:ORMAll(parts, @"and")];
		}
		[conjuncts addObject:[alternatives count] > 0 ? ORMAll(alternatives, @"or")
		                                              : [ODataExpression literalWithValue:@NO]];
	}
	return ORMAll(conjuncts, @"and") ?: [ODataExpression literalWithValue:@YES];
}

#pragma mark Steps

/* The step's count or aggregate over the collection, whose members the
 * lambda's variable is, of which the body says what it says. */
- (ODataExpression *)aggregated:(ORMODataPlace *)collection
                       variable:(NSString *)variable
                           body:(ODataExpression *)body
                         member:(ORMCDEntity *)member
                        through:(ORMCDProperty *)firstHop
                           from:(ORMQueryNode *)start
                           step:(ORMQueryStep *)step
{
	ODataExpression *of = [self expression:collection];
	ODataExpression *any = [ODataExpression lambda:@"any" of:of variable:body != nil ? variable : nil body:body];
	NSString *operator = step != nil ? [ORMODataOperators() objectForKey:step.countComparison ?: @""] : nil;
	if (operator == nil) {
		return any;
	}
	if (step.aggregate == ORMQueryCount) {
		NSUInteger n = step.countValue;
		ODataExpression *count = [ODataExpression binary:operator left:[ODataExpression countOf:of]
		                                           right:[ODataExpression literalWithValue:@(n)]];
		if (body == nil) {
			return count;
		}
		/* OData counts a collection, not the members meeting conditions: but
		 * "more than none" is some, and "none" is not any. */
		BOOL some = ([operator isEqualToString:@"gt"] && n == 0) || ([operator isEqualToString:@"ge"] && n == 1)
			|| ([operator isEqualToString:@"ne"] && n == 0);
		BOOL none = ([operator isEqualToString:@"eq"] && n == 0) || ([operator isEqualToString:@"lt"] && n == 1)
			|| ([operator isEqualToString:@"le"] && n == 0);
		if (some) {
			return any;
		}
		if (none) {
			return [ODataExpression unary:@"not" operand:any];
		}
		[self note:[NSString stringWithFormat:@"count(%@) is of every %@, not only those meeting the conditions below "
		                                      @"it: OData counts no filtered collection.",
		                                      [step.aggregateNode designation], start.objectType.name]];
		return count;
	}
	/* From the member, or from where its first hop leads. */
	ORMCDEntity *startEntity = firstHop == nil ? member
		: ([firstHop isKindOfClass:[ORMCDRelationship class]]
		       ? [_coreData entityNamed:((ORMCDRelationship *)firstHop).destination] : nil);
	NSArray *rest = startEntity != nil ? [self pathFrom:start entity:startEntity to:step.aggregateNode] : nil;
	if (rest == nil && firstHop != nil && start == step.aggregateNode) {
		rest = @[];
	}
	NSArray *path = rest != nil ? (firstHop != nil ? [@[ firstHop ] arrayByAddingObjectsFromArray:rest] : rest) : nil;
	if ([path count] == 0) {
		[self note:[NSString stringWithFormat:@"%@(%@) is of nothing one path reaches from %@.",
		                                      [ORMQuery nameOfAggregate:step.aggregate], [step.aggregateNode designation],
		                                      [of description]]];
		return any;
	}
	if ([self narrows:start] || (start != step.aggregateNode && [self narrows:step.aggregateNode])) {
		[self note:[NSString stringWithFormat:@"%@(%@) is over every %@, not only those meeting the conditions below "
		                                      @"it: OData aggregates no filtered collection.",
		                                      [ORMQuery nameOfAggregate:step.aggregate], [step.aggregateNode designation],
		                                      start.objectType.name]];
	}
	NSString *method = [@[ @"$count", @"sum", @"average", @"max", @"min" ] objectAtIndex:(NSUInteger)step.aggregate];
	NSArray *wirePath = [self wirePath:path];
	ODataExpression *aggregate = [ODataExpression aggregateOf:of aggregate:[ODataAggregate aggregateOfPath:wirePath method:method
	                                                                                                   alias:@"value"]];
	if (aggregate == nil) {
		[self note:[NSString stringWithFormat:@"%@ with %@ is no aggregate OData has.", [wirePath componentsJoinedByString:@"/"],
		                                      method]];
		return any;
	}
	NSString *value = step.aggregateValue ?: @"";
	ODataExpression *literal = ORMIsNumber(value) ? [ODataExpression literalWithText:value] : nil;
	return [ODataExpression binary:operator left:aggregate right:literal ?: [ODataExpression literalWithValue:value]];
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
				NSArray *rest = [self pathFrom:next entity:[_coreData entityNamed:((ORMCDRelationship *)property).destination]
				                            to:target];
				if (rest != nil) {
					return [@[ property ] arrayByAddingObjectsFromArray:rest];
				}
			}
		}
	}
	return nil;
}

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

/* Through a binary to an attribute or a relationship of the entity. */
- (ODataExpression *)binaryStep:(ORMQueryStep *)step
                           node:(ORMQueryNode *)node
                       property:(ORMCDProperty *)property
                             at:(ORMODataPlace *)at
                        columns:(BOOL)columns
{
	if ([property isKindOfClass:[ORMCDAttribute class]]) {
		ORMCDAttribute *attribute = (ORMCDAttribute *)property;
		ORMODataPlace *value = [at adding:attribute entity:nil];
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
		[self reached:node place:value];
		NSString *operator = [ORMODataOperators() objectForKey:node.comparison ?: @""];
		if (operator != nil && node.comparedNode == nil) {
			[parts addObject:[ODataExpression binary:operator left:[self expression:value]
			                                   right:[self literal:node.value forAttribute:attribute]]];
		}
		return ORMAll(parts, @"and") ?: [self isNotNull:value];
	}
	ORMCDRelationship *relationship = (ORMCDRelationship *)property;
	ORMCDEntity *destination = [_coreData entityNamed:relationship.destination];
	ORMODataPlace *reached = [at adding:relationship entity:destination];
	if (!relationship.toMany) {
		if (step != nil && step.countComparison != nil) {
			[self note:[NSString stringWithFormat:@"%@ is one at most: it is not counted.", node.objectType.name]];
		}
		/* Through nothing, no condition holds: the condition says it is set. */
		return [self filterFor:node entity:destination at:reached columns:columns] ?: [self isNotNull:reached];
	}
	NSString *variable = [self nextVariable];
	[_scope addObject:variable];
	ODataExpression *body = [self filterFor:node entity:destination
	                                     at:[ORMODataPlace variable:variable entity:destination trail:reached.trail]
	                                columns:columns];
	[_scope removeLastObject];
	return [self aggregated:reached variable:variable body:body member:destination through:nil from:node step:step];
}

/* Through a fact type that is an entity of its own: to it, and on from it
 * to the other roles' players. */
- (ODataExpression *)entityStep:(ORMQueryStep *)step entity:(ORMCDEntity *)entity at:(ORMODataPlace *)at
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
			[self note:[NSString stringWithFormat:@"%@ is absorbed into what uses it, so going through it joins on "
			                                      @"its parts, which takes a second request: not made yet. Map %@ as "
			                                      @"an entity to query through it.",
			                                      node.objectType.name, node.objectType.name]];
		} else {
			[self note:[NSString stringWithFormat:@"\"%@\" maps to nothing %@ reaches.",
			                                      [[fact primaryReading] expandedText] ?: fact.name, entity.name]];
		}
		return nil;
	}
	ORMODataPlace *reached = [at adding:relationship entity:factEntity];
	NSString *variable = relationship.toMany ? [self nextVariable] : nil;
	ORMODataPlace *inner = variable != nil ? [ORMODataPlace variable:variable entity:factEntity trail:reached.trail] : reached;
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
		ODataExpression *part = [self binaryStep:nil node:node property:rolePlace at:inner columns:columns];
		/* The role is played: a mandatory one says nothing more. */
		if (part != nil && (node.comparison != nil || [node.steps count] > 0 || node.label != nil)) {
			[parts addObject:part];
		}
	}
	if (variable != nil) {
		[_scope removeLastObject];
	}
	ODataExpression *body = ORMAll(parts, @"and");
	if (variable == nil) {
		return body ?: [self isNotNull:reached];
	}
	ORMQueryNode *start = nil;
	ORMCDProperty *firstHop = nil;
	for (ORMQueryNode *node in step.nodes) {
		for (ORMQueryNode *at = step.aggregateNode; at != nil && start == nil; at = at.step.parent) {
			if (at == node) {
				start = node;
				firstHop = [_places propertyOf:factEntity source:node.role.identifier];
			}
		}
	}
	return [self aggregated:reached variable:variable body:body member:factEntity through:firstHop from:start step:step];
}

/* To a subtype: the object is of its type, and is read as one; to a
 * supertype: it is one. */
- (ODataExpression *)subtypeStep:(ORMQueryStep *)step entity:(ORMCDEntity *)entity at:(ORMODataPlace *)at
                         columns:(BOOL)columns
{
	ORMQueryNode *node = [step.nodes firstObject];
	if (node == nil) {
		return nil;
	}
	ORMCDEntity *target = [_places entityOf:node.objectType];
	ODataExpression *test = nil;
	ORMODataPlace *place = at;
	if (step.entryRole.isSupertypeMetaRole && [at isFetched] && target != nil && [_places entity:_fetched inherits:target]) {
		/* What is asked for is one. */
	} else if (step.entryRole.isSupertypeMetaRole) {
		if (target == nil || target == entity || ![_places entity:target inherits:entity]) {
			[self note:[NSString stringWithFormat:@"%@ is no entity of its own, so being one is not tested.",
			                                      node.objectType.name]];
		} else {
			NSString *type = [self typeNameOf:target];
			ODataExpression *name = [ODataExpression cast:type of:nil];
			test = [ODataExpression call:@"isof" arguments:[at isFetched] && [_scope count] == 0
				? @[ name ] : @[ [self expression:at], name ]];
			place = [at castTo:type entity:target];
		}
	}
	ODataExpression *inner = [self filterFor:node entity:target ?: entity at:place columns:columns];
	return ORMAll([NSArray arrayWithObjects:test ?: inner, test != nil ? inner : nil, nil], @"and");
}

@end
