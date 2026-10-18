/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQuery.h"
#import "ORMEditorPriv.h"
#import "ORMXML.h"
#import "ORMModelPriv.h"
#import "ORMQueryExpression.h"

#define Q ORMQueryNamespace

static NSArray<NSString *> *
ORMQueryComparisons(void)
{
	return @[ @"=", @"<>", @"<", @"<=", @">", @">=" ];
}

/* The text with each {n} replaced by the nth replacement; one past them,
 * or NSNull, leaves it as it is. */
static NSString *
ORMRewritePlaceholders(NSString *text, NSArray *replacements)
{
	NSMutableString *out = [NSMutableString string];
	NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
	[scanner setCharactersToBeSkipped:nil];
	while (![scanner isAtEnd]) {
		NSString *chunk = nil;
		if ([scanner scanUpToString:@"{" intoString:&chunk]) {
			[out appendString:chunk];
		}
		if ([scanner isAtEnd]) {
			break;
		}
		NSUInteger at = [scanner scanLocation];
		NSInteger index = 0;
		[scanner setScanLocation:at + 1];
		if ([scanner scanInteger:&index] && [scanner scanString:@"}" intoString:NULL] && index >= 0) {
			id replacement = (NSUInteger)index < [replacements count] ? [replacements objectAtIndex:(NSUInteger)index] : nil;
			[out appendString:[replacement isKindOfClass:[NSString class]]
			                      ? replacement : [text substringWithRange:NSMakeRange(at, [scanner scanLocation] - at)]];
		} else {
			[out appendString:@"{"];
			[scanner setScanLocation:at + 1];
		}
	}
	return out;
}

#pragma mark The projection

/* As the XML names them. */
static NSArray<NSString *> *
ORMQueryAggregateNames(void)
{
	return @[ @"Count", @"Total", @"Average", @"Maximum", @"Minimum" ];
}

@interface ORMQueryNode ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, strong) ORMObjectType *objectType;
@property (nonatomic, readwrite, strong) ORMRole *role;
@property (nonatomic, readwrite, weak) ORMQueryStep *step;
@property (nonatomic, readwrite) BOOL isProjected;
@property (nonatomic, readwrite, weak) ORMRole *derivedRole;
@property (nonatomic, readwrite, copy) NSString *comparison;
@property (nonatomic, readwrite, copy) NSString *value;
@property (nonatomic, readwrite, weak) ORMQueryNode *comparedNode;
@property (nonatomic, copy) NSString *comparedNodeId;
@property (nonatomic, readwrite, copy) NSString *label;
@property (nonatomic, readwrite, copy) NSArray<ORMQueryStep *> *steps;
@property (nonatomic, readwrite) BOOL combinesWithOr;
@property (nonatomic, readwrite) ORMQuerySort sortOrder;
@property (nonatomic, readwrite) BOOL isValue;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, strong) ORMQueryExpression *expression;
@property (nonatomic, readwrite, weak) ORMQueryNode *valueOf;
@property (nonatomic, readwrite, copy) NSArray<ORMQueryNode *> *values;
@end

@interface ORMQueryStep ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, strong) ORMFactType *factType;
@property (nonatomic, readwrite, strong) ORMRole *entryRole;
@property (nonatomic, readwrite, weak) ORMQueryNode *parent;
@property (nonatomic, readwrite) ORMQueryOperator operatorKind;
@property (nonatomic, readwrite, copy) NSArray<ORMQueryNode *> *nodes;
@property (nonatomic, readwrite, copy) NSString *countComparison;
@property (nonatomic, readwrite) NSUInteger countValue;
@property (nonatomic, readwrite) ORMQueryAggregate aggregate;
@property (nonatomic, readwrite, weak) ORMQueryNode *aggregateNode;
@property (nonatomic, copy) NSString *aggregateNodeId;
@property (nonatomic, readwrite, copy) NSString *aggregateValue;
@property (nonatomic, readwrite, weak) ORMQueryNode *groupNode;
@property (nonatomic, copy) NSString *groupNodeId;
@property (nonatomic, readwrite) BOOL comparesAggregates;
@property (nonatomic, readwrite) ORMQueryAggregate comparedAggregate;
@property (nonatomic, readwrite, weak) ORMQueryNode *comparedGroupNode;
@property (nonatomic, copy) NSString *comparedGroupNodeId;
@end

@interface ORMQuery ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, strong) ORMQueryNode *root;
@property (nonatomic, readwrite) BOOL isComplete;
@property (nonatomic, readwrite) ORMQueryKind kind;
@property (nonatomic, readwrite) BOOL isDeontic;
@property (nonatomic, readwrite) ORMQueryCalculationFunction calculationFunction;
@property (nonatomic, readwrite, weak) ORMQueryNode *calculatedNode;
@property (nonatomic, readwrite, weak) ORMFactType *derivedFactType;
@property (nonatomic, readwrite, weak) ORMObjectType *derivedSubtype;
/* What the stored query says, its object types, fact types and roles
 * looked up in the model. */
+ (ORMQuery *)queryOf:(ORMStoredQuery *)stored model:(ORMModel *)model;
- (ORMQueryNode *)nodeOf:(ORMQueryPart *)part type:(ORMObjectType *)type role:(ORMRole *)role model:(ORMModel *)model;
- (ORMQueryStep *)stepOf:(ORMQueryPart *)part parent:(ORMQueryNode *)parent model:(ORMModel *)model;
- (void)collect:(ORMQueryNode *)node into:(NSMutableArray *)nodes;
/* Each node's designation, by id; each designation's node, among the nodes
 * given, where it is one object. */
- (NSDictionary<NSString *, NSString *> *)designationsById;
- (NSDictionary<NSString *, NSString *> *)nodeIdsByDesignationAmong:(NSArray<ORMQueryNode *> *)nodes;
@end

/* The kinds and functions as the file names them. */
static NSArray<NSString *> *
ORMQueryKindNames(void)
{
	return @[ @"List", @"Constraint", @"Calculation", @"Derivation" ];
}

static NSArray<NSString *> *
ORMCalculationFunctionNames(void)
{
	return @[ @"Value", @"Count", @"Total", @"Average", @"Maximum", @"Minimum" ];
}

#pragma mark As the document keeps it

@interface ORMQueryPart ()
+ (instancetype)partOf:(NSXMLElement *)element;
@end

@interface ORMStoredQuery ()
- (void)readElement:(NSXMLElement *)element;
- (ORMQueryPart *)partWithId:(NSString *)identifier step:(BOOL)isStep;
@end

/* A node's or a step's attributes, as the file names them, with the
 * values they hold: in the order a change writes them. */
static NSArray<NSArray<NSString *> *> *
ORMQueryPartAttributes(void)
{
	return @[
		@[ @"ref", @"ref" ], @[ @"Role", @"roleId" ], @[ @"Projected", @"projected" ], @[ @"For", @"forRole" ],
		@[ @"Comparison", @"comparison" ], @[ @"Value", @"value" ], @[ @"CompareTo", @"compareTo" ],
		@[ @"Label", @"label" ], @[ @"Combine", @"combine" ], @[ @"Sort", @"sort" ], @[ @"Operator", @"operatorName" ],
		@[ @"Count", @"countComparison" ], @[ @"CountValue", @"countValueText" ], @[ @"Aggregate", @"aggregateName" ],
		@[ @"AggregateNode", @"aggregateNodeId" ], @[ @"GroupNode", @"groupNodeId" ],
		@[ @"CompareAggregate", @"compareAggregate" ], @[ @"CompareGroupNode", @"compareGroupNode" ],
		@[ @"Name", @"name" ], @[ @"Expression", @"expression" ]
	];
}

static NSArray<NSArray<NSString *> *> *
ORMStoredQueryAttributes(void)
{
	return @[ @[ @"Name", @"name" ], @[ @"Kind", @"kind" ], @[ @"Modality", @"modality" ], @[ @"Function", @"function" ],
		      @[ @"Of", @"of" ] ];
}

/* A value as ORMBoolAttribute reads it. */
static BOOL
ORMBoolValue(NSString *value, BOOL fallback)
{
	return value == nil ? fallback : ([value caseInsensitiveCompare:@"true"] == NSOrderedSame || [value isEqualToString:@"1"]);
}

@implementation ORMQueryPart
{
	__weak ORMQueryPart *_parent;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_parts = @[];
	}
	return self;
}

- (void)setParts:(NSArray<ORMQueryPart *> *)parts
{
	for (ORMQueryPart *part in _parts) {
		part->_parent = nil;
	}
	_parts = [parts copy] ?: @[];
	for (ORMQueryPart *part in _parts) {
		part->_parent = self;
	}
}

- (ORMQueryPart *)parent
{
	return _parent;
}

- (NSUInteger)index
{
	return [_parent.parts indexOfObjectIdenticalTo:self];
}

- (NSArray<ORMQueryPart *> *)steps
{
	NSMutableArray *steps = [NSMutableArray array];
	for (ORMQueryPart *part in _parts) {
		if (part.isStep) {
			[steps addObject:part];
		}
	}
	return steps;
}

- (NSArray<ORMQueryPart *> *)nodes
{
	NSMutableArray *nodes = [NSMutableArray array];
	for (ORMQueryPart *part in _parts) {
		if (!part.isStep && !part.isValue) {
			[nodes addObject:part];
		}
	}
	return nodes;
}

- (NSArray<ORMQueryPart *> *)values
{
	NSMutableArray *values = [NSMutableArray array];
	for (ORMQueryPart *part in _parts) {
		if (part.isValue) {
			[values addObject:part];
		}
	}
	return values;
}

- (void)addPart:(ORMQueryPart *)part
{
	[self insertPart:part atIndex:[_parts count]];
}

- (void)insertPart:(ORMQueryPart *)part atIndex:(NSUInteger)index
{
	[part detach];
	NSMutableArray *parts = [_parts mutableCopy];
	[parts insertObject:part atIndex:MIN(index, [parts count])];
	self.parts = parts;
}

- (void)detach
{
	if (_parent != nil) {
		_parent.parts = ORMWithout(_parent.parts, self);
	}
}

- (void)collect:(NSMutableArray *)into
{
	[into addObject:self];
	for (ORMQueryPart *part in _parts) {
		[part collect:into];
	}
}

- (NSArray<ORMQueryPart *> *)tree
{
	NSMutableArray *tree = [NSMutableArray array];
	[self collect:tree];
	return tree;
}

- (id)copyWithZone:(NSZone *)zone
{
	ORMQueryPart *copy = [[ORMQueryPart allocWithZone:zone] init];
	copy.identifier = self.identifier;
	copy.isStep = self.isStep;
	copy.isValue = self.isValue;
	for (NSArray *attribute in ORMQueryPartAttributes()) {
		[copy setValue:[self valueForKey:[attribute lastObject]] forKey:[attribute lastObject]];
	}
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMQueryPart *part in _parts) {
		[parts addObject:[part copy]];
	}
	copy.parts = parts;
	return copy;
}

+ (instancetype)partOf:(NSXMLElement *)element
{
	ORMQueryPart *part = [[ORMQueryPart alloc] init];
	part.identifier = ORMAttribute(element, @"id");
	part.isStep = [[element localName] isEqualToString:@"Step"];
	part.isValue = [[element localName] isEqualToString:@"Value"];
	for (NSArray *attribute in ORMQueryPartAttributes()) {
		[part setValue:ORMAttribute(element, [attribute firstObject]) forKey:[attribute lastObject]];
	}
	NSMutableArray *parts = [NSMutableArray array];
	for (NSXMLElement *child in part.isValue ? @[] : ORMChildren(element, Q, part.isStep ? @"Node" : @"Step")) {
		[parts addObject:[self partOf:child]];
	}
	/* A node's value nodes, after its steps. */
	for (NSXMLElement *child in part.isStep || part.isValue ? @[] : ORMChildren(element, Q, @"Value")) {
		[parts addObject:[self partOf:child]];
	}
	part.parts = parts;
	return part;
}

@end

@implementation ORMStoredQuery

- (void)reset
{
	[super reset];
	_kind = nil;
	_modality = nil;
	_function = nil;
	_of = nil;
	_root = nil;
}

- (void)readElement:(NSXMLElement *)element
{
	self.name = ORMAttribute(element, @"Name");
	self.kind = ORMAttribute(element, @"Kind");
	self.modality = ORMAttribute(element, @"Modality");
	self.function = ORMAttribute(element, @"Function");
	self.of = ORMAttribute(element, @"Of");
	NSXMLElement *root = ORMChild(element, Q, @"Node");
	self.root = root != nil ? [ORMQueryPart partOf:root] : nil;
}

- (id)copyWithZone:(NSZone *)zone
{
	ORMStoredQuery *copy = [[ORMStoredQuery allocWithZone:zone] init];
	copy.identifier = self.identifier;
	copy.name = self.name;
	copy.kind = self.kind;
	copy.modality = self.modality;
	copy.function = self.function;
	copy.of = self.of;
	copy.root = [self.root copy];
	return copy;
}

/* The query's part of the id, and what kind it is. */
- (ORMQueryPart *)partWithId:(NSString *)identifier step:(BOOL)isStep
{
	for (ORMQueryPart *part in identifier != nil ? [self.root tree] : @[]) {
		if (part.isStep == isStep && [part.identifier isEqualToString:identifier]) {
			return part;
		}
	}
	return nil;
}

@end

@implementation ORMModel (ORMQueryReading)

- (void)readQueries
{
	NSMutableArray *queries = [NSMutableArray array];
	for (NSXMLElement *element in ORMChildren(ORMChild([self.document rootElement], Q, @"Queries"), Q, @"Query")) {
		ORMStoredQuery *query = [self element:[ORMStoredQuery class] for:element];
		[query readElement:element];
		[queries addObject:query];
		[self registerElement:query];
	}
	self.storedQueries = queries;
}

@end

/* The element's attributes as the object's values, where they differ. */
static void
ORMWriteValues(NSXMLElement *element, id object, NSArray<NSArray<NSString *> *> *attributes)
{
	for (NSArray *attribute in attributes) {
		NSString *value = [object valueForKey:[attribute lastObject]];
		NSString *was = ORMAttribute(element, [attribute firstObject]);
		if (value != was && ![value isEqualToString:was]) {
			ORMSetAttribute(element, [attribute firstObject], value);
		}
	}
}

/* The parent's children of the kind as the parts: one the parts do not
 * have goes, one they have stays where it is, a new one after them. */
static void
ORMWriteParts(NSXMLDocument *document, NSXMLElement *parent, NSArray<ORMQueryPart *> *parts, NSString *local)
{
	NSMutableDictionary *byId = [NSMutableDictionary dictionary];
	NSMutableArray *unnamed = [NSMutableArray array];
	for (ORMQueryPart *part in parts) {
		if (part.identifier != nil) {
			[byId setObject:part forKey:part.identifier];
		} else {
			[unnamed addObject:part];
		}
	}
	NSMutableDictionary *elements = [NSMutableDictionary dictionary];
	NSMutableArray *unnamedElements = [NSMutableArray array];
	for (NSXMLElement *child in ORMChildren(parent, Q, local)) {
		NSString *identifier = ORMAttribute(child, @"id");
		if (identifier != nil && [byId objectForKey:identifier] != nil && [elements objectForKey:identifier] == nil) {
			[elements setObject:child forKey:identifier];
		} else if (identifier == nil && [unnamedElements count] < [unnamed count]) {
			[unnamedElements addObject:child];
		} else {
			ORMDetach(child);
		}
	}
	for (ORMQueryPart *part in parts) {
		NSXMLElement *child = nil;
		if (part.identifier != nil) {
			child = [elements objectForKey:part.identifier];
		} else {
			NSUInteger index = [unnamed indexOfObjectIdenticalTo:part];
			child = index < [unnamedElements count] ? [unnamedElements objectAtIndex:index] : nil;
		}
		if (child == nil) {
			child = ORMNewElement(document, Q, local);
			if (part.identifier != nil) {
				ORMSetAttribute(child, @"id", part.identifier);
			}
			ORMAddChild(parent, child);
		}
		ORMWriteValues(child, part, ORMQueryPartAttributes());
		if (part.isStep) {
			ORMWriteParts(document, child, part.parts, @"Node");
		} else if (!part.isValue) {
			ORMWriteParts(document, child, [part steps], @"Step");
			ORMWriteParts(document, child, [part values], @"Value");
		}
	}
}

@implementation ORMNormaWriter (ORMQueries)

- (void)writeStoredQuery:(ORMStoredQuery *)query
{
	NSXMLDocument *document = [self.model.modelElement rootDocument];
	NSXMLElement *element = query.element;
	if (element == nil) {
		NSXMLElement *root = [document rootElement];
		NSXMLElement *container = ORMChild(root, Q, @"Queries");
		if (container == nil) {
			container = ORMNewElement(document, Q, @"Queries");
			ORMAddChild(root, container);
		}
		element = ORMNewElementWithId(document, Q, @"Query", query.identifier);
		ORMAddChild(container, element);
		query.element = element;
	}
	ORMWriteValues(element, query, ORMStoredQueryAttributes());
	ORMWriteParts(document, element, query.root != nil ? @[ query.root ] : @[], @"Node");
}

@end

@implementation ORMQueryNode

- (BOOL)isNumeric
{
	ORMObjectType *type = [self.objectType valueType];
	return [type.dataType isNumeric];
}

- (NSString *)designation
{
	if (self.isValue) {
		return self.name ?: @"?";
	}
	return [NSString stringWithFormat:@"%@%@", self.objectType.name ?: @"?", self.label ?: @""];
}

@end

@implementation ORMQueryStep

- (BOOL)isSubtyping
{
	return self.factType.kind == ORMFactTypeSubtype;
}

@end

@implementation ORMQuery

+ (NSArray<ORMQuery *> *)queriesInModel:(ORMModel *)model
{
	NSMutableArray *queries = [NSMutableArray array];
	for (ORMStoredQuery *stored in model.storedQueries) {
		ORMQuery *query = [self queryOf:stored model:model];
		if (query != nil) {
			[queries addObject:query];
		}
	}
	return queries;
}

+ (ORMQuery *)queryWithId:(NSString *)identifier inModel:(ORMModel *)model
{
	for (ORMQuery *query in [self queriesInModel:model]) {
		if ([query.identifier isEqualToString:identifier]) {
			return query;
		}
	}
	return nil;
}

+ (ORMQuery *)derivationOfSubtype:(ORMObjectType *)subtype inModel:(ORMModel *)model
{
	for (ORMQuery *query in [self queriesInModel:model]) {
		if (query.kind == ORMQueryDerivation && [query.derivedSubtype.identifier isEqualToString:subtype.identifier]) {
			return query;
		}
	}
	return nil;
}

+ (ORMQuery *)derivationOf:(ORMFactType *)factType inModel:(ORMModel *)model
{
	for (ORMQuery *query in [self queriesInModel:model]) {
		if (query.kind == ORMQueryDerivation && [query.derivedFactType.identifier isEqualToString:factType.identifier]) {
			return query;
		}
	}
	return nil;
}

/* A part of a query read from a rule, kept out of the model. */
static ORMQueryPart *
ORMRulePart(BOOL isStep, NSString *identifier)
{
	ORMQueryPart *part = [[ORMQueryPart alloc] init];
	part.isStep = isStep;
	part.identifier = identifier;
	return part;
}

/* The object type at a node of a query read from a rule. */
static ORMObjectType *
ORMRuleNodeType(ORMQueryPart *node, ORMModel *model)
{
	id element = [model elementWithId:node.roleId ?: node.ref];
	return [element isKindOfClass:[ORMRole class]] ? [(ORMRole *)element player] : element;
}

/* A step of a query read from a rule, entered by the role: a node for
 * each other role. */
static ORMQueryPart *
ORMRuleStep(ORMRole *entry, NSString *identifier)
{
	ORMQueryPart *step = ORMRulePart(YES, identifier);
	step.ref = entry.factType.identifier;
	step.roleId = entry.identifier;
	for (ORMRole *other in entry.factType.roles) {
		if (other == entry || other.player.isImplicitBooleanValue) {
			continue;
		}
		ORMQueryPart *node = ORMRulePart(NO, [NSString stringWithFormat:@"%@.%@", identifier, other.identifier]);
		node.roleId = other.identifier;
		[step addPart:node];
	}
	return step;
}

/* NORMA's rule for the fact type, as a derivation query: the path's root
 * its root node; each role it joins by a step from the node the path is
 * at, a node for each of the fact type's other roles, the one it goes on
 * by where the path then is; each projected node ticked, For the role it
 * is projected as. nil, and why, where the path is not plain. Ids are the
 * path's, so it reads the same each time. */
static ORMStoredQuery *
ORMRuleQuery(ORMFactType *fact, NSString **why)
{
	ORMDerivationRule *rule = [fact derivationRule];
	ORMRolePath *path = [rule.paths firstObject];
	if (rule == nil || [rule.paths count] == 0) {
		*why = @"it has no path";
		return nil;
	}
	if ([rule.paths count] > 1 || [path.subPaths count] > 0) {
		*why = @"its path splits";
		return nil;
	}
	if ([rule.calculations count] > 0 || [rule.conditions count] > 0) {
		*why = @"its path calculates";
		return nil;
	}
	if (path.rootObjectType == nil || path.rootIsNegated || path.rootValueConstraint != nil) {
		*why = @"its path's root is not an object type as such";
		return nil;
	}
	NSString *pathId = path.identifier ?: fact.identifier;
	ORMStoredQuery *query = [[ORMStoredQuery alloc] init];
	query.identifier = pathId;
	query.name = rule.pathName ?: fact.name;
	query.kind = @"Derivation";
	query.of = fact.identifier;
	ORMQueryPart *root = ORMRulePart(NO, path.rootId ?: [pathId stringByAppendingString:@".root"]);
	root.ref = path.rootObjectType.identifier;
	query.root = root;
	NSMutableDictionary<NSString *, ORMQueryPart *> *at = [NSMutableDictionary dictionary];
	ORMQueryPart *current = root;
	ORMQueryPart *step = nil;
	for (ORMPathedRole *pathed in path.pathedRoles) {
		ORMRole *role = pathed.role;
		if (role == nil || pathed.isNegated || pathed.valueConstraint != nil || pathed.correlatedWith != nil) {
			*why = @"its path says more of a role than which";
			return nil;
		}
		if (pathed.purpose == ORMPathOuterJoin) {
			*why = @"its path joins where nothing may";
			return nil;
		}
		if (pathed.purpose == ORMPathSameFactType) {
			/* Through a link fact type, NORMA names the role a proxy stands
			 * for (CinemaTickets), or joins by the objectified role and
			 * goes on by the link fact type's (WaiterTips): the step
			 * through the link fact type either way. */
			ORMQueryPart *node = nil;
			for (ORMQueryPart *each in [step nodes]) {
				ORMRole *at = [fact.model elementWithId:each.roleId];
				node = at == role || at.proxiedRole == role ? each : node;
			}
			ORMRole *entry = [fact.model elementWithId:step.roleId ?: @""];
			for (ORMRole *proxy in node == nil && current == [step parent] ? role.factType.roles : @[]) {
				if (proxy.proxiedRole != nil && proxy.proxiedRole == entry) {
					ORMQueryPart *from = [step parent];
					[step detach];
					step = ORMRuleStep(proxy, step.identifier);
					[from addPart:step];
					node = [[step nodes] firstObject];
				}
			}
			if (node == nil) {
				*why = @"its path goes on by a role of a fact type it is not in";
				return nil;
			}
			current = node;
		} else {
			if (![[ORMQuery rolesFrom:ORMRuleNodeType(current, fact.model)] containsObject:role]) {
				*why = @"its path joins by a role the object type there does not play";
				return nil;
			}
			step = ORMRuleStep(role, [pathed.identifier stringByAppendingString:@".step"]);
			[current addPart:step];
		}
		if (pathed.identifier != nil) {
			[at setObject:current forKey:pathed.identifier];
		}
	}
	for (ORMRole *role in [fact visibleRoles]) {
		ORMPathSource *source = [rule.projections objectForKey:role.identifier];
		ORMQueryPart *node = source.kind == ORMPathSourceRoot && source.root == path ? root
			: source.kind == ORMPathSourcePathedRole ? [at objectForKey:source.pathedRole.identifier ?: @""]
			: nil;
		if (node == nil || node.forRole != nil) {
			*why = @"it does not project one point of its path for each role";
			return nil;
		}
		node.projected = @"true";
		node.forRole = role.identifier;
	}
	return query;
}

/* What a derivation is read from: the model's query, or its fact type's
 * NORMA rule. */
static ORMStoredQuery *
ORMDerivationQuery(ORMFactType *fact, ORMModel *model, NSString **why)
{
	for (ORMStoredQuery *each in model.storedQueries) {
		if ([each.kind isEqualToString:@"Derivation"] && [each.of isEqualToString:fact.identifier]) {
			return each;
		}
	}
	return ORMRuleQuery(fact, why);
}

+ (NSArray<ORMQuery *> *)derivationsInModel:(ORMModel *)model
{
	NSMutableArray *derivations = [NSMutableArray array];
	NSMutableSet *derived = [NSMutableSet set];
	for (ORMQuery *query in [self queriesInModel:model]) {
		if (query.kind == ORMQueryDerivation && query.derivedFactType != nil) {
			[derivations addObject:query];
			[derived addObject:query.derivedFactType.identifier];
		}
	}
	for (ORMFactType *fact in model.factTypes) {
		NSString *why = nil;
		ORMStoredQuery *stored = fact.isDerived && ![derived containsObject:fact.identifier]
			&& [[fact derivationRule].paths count] > 0 ? ORMRuleQuery(fact, &why) : nil;
		if (stored != nil) {
			[derivations addObject:[self queryOf:stored model:model]];
		}
	}
	return derivations;
}

- (NSArray<ORMQueryNode *> *)derivedColumns
{
	NSArray *roles = [self.derivedFactType visibleRoles];
	NSArray *projected = [self projectedNodes];
	if ([roles count] == 0 || [projected count] != [roles count]) {
		return nil;
	}
	NSMutableArray *columns = [NSMutableArray array];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMQueryNode *column = nil;
		for (ORMQueryNode *node in projected) {
			ORMRole *role = node.derivedRole ?: [roles objectAtIndex:[projected indexOfObject:node]];
			column = role == [roles objectAtIndex:i] ? (column != nil ? (id)[NSNull null] : node) : column;
		}
		if (column == nil || (id)column == [NSNull null]) {
			return nil;
		}
		[columns addObject:column];
	}
	return columns;
}

#pragma mark Derived fact types expanded

/* What a step says beyond its fact type and role: how it goes on. */
static NSArray<NSString *> *
ORMStepQualifiers(void)
{
	return @[ @"operatorName", @"countComparison", @"countValueText", @"aggregateName", @"aggregateNodeId", @"groupNodeId", @"compareGroupNode",
	          @"compareAggregate" ];
}

/* The values that name another node of the query. */
static NSArray<NSString *> *
ORMNodeReferences(void)
{
	return @[ @"compareTo", @"compareGroupNode", @"groupNodeId", @"aggregateNodeId" ];
}

/* Every reference to a node of the tree, from one id to another. */
static void
ORMRenameNode(ORMQueryPart *tree, NSString *from, NSString *to)
{
	for (ORMQueryPart *part in [tree tree]) {
		for (NSString *key in ORMNodeReferences()) {
			if ([[part valueForKey:key] isEqualToString:from]) {
				[part setValue:to forKey:key];
			}
		}
		ORMQueryExpression *expression = part.expression != nil
			? [ORMQueryExpression expressionWithCanonicalText:part.expression reason:NULL] : nil;
		if ([[expression nodeIds] containsObject:from]) {
			part.expression = [[expression expressionRenaming:from to:to] canonicalText];
		}
	}
}

/* The derivation's tree re-rooted at the node: each step on the way up
 * reversed, the node above going under it. Only a plain binary step
 * reverses: nil and why otherwise. */
static ORMQueryPart *
ORMReroot(ORMQueryPart *target, ORMModel *model, NSString **why)
{
	NSMutableArray *path = [NSMutableArray array];
	for (ORMQueryPart *node = target; [node parent].isStep;) {
		ORMQueryPart *step = [node parent];
		ORMQueryPart *above = [step parent];
		BOOL plain = [[step nodes] count] == 1;
		for (NSString *key in ORMStepQualifiers()) {
			plain = plain && [step valueForKey:key] == nil;
		}
		if (!plain || [above.combine isEqualToString:@"Or"]) {
			*why = @"its rule goes there through a step that is not one plain binary step";
			return nil;
		}
		/* The roles as the rule has them, before any is turned around. */
		[path addObject:@[ node, step, above, node.roleId ?: @"", step.roleId ?: @"" ]];
		node = above;
	}
	for (NSArray *edge in path) {
		ORMQueryPart *node = [edge objectAtIndex:0];
		ORMQueryPart *step = [edge objectAtIndex:1];
		ORMQueryPart *above = [edge objectAtIndex:2];
		NSString *nodeRole = [edge objectAtIndex:3];
		NSString *aboveRole = [edge objectAtIndex:4];
		[above detach];
		[step detach];
		/* Taken from its step; one turned around already stays where the
		 * last turn put it. */
		if ([node parent] == step) {
			[node detach];
		}
		/* The same step the other way: entered by the node's role, the
		 * node above reached by the step's. */
		step.roleId = nodeRole;
		above.ref = nil;
		above.roleId = aboveRole;
		[step addPart:above];
		[node addPart:step];
	}
	if ([path count] > 0) {
		ORMRole *role = [model elementWithId:[[path firstObject] objectAtIndex:3]];
		target.roleId = nil;
		target.ref = role.player.identifier;
	}
	return target;
}

/* Where the role with the identifier is among the roles. */
static NSUInteger
ORMIndexOfRole(NSArray<ORMRole *> *roles, NSString *identifier)
{
	for (NSUInteger i = 0; i < [roles count]; i++) {
		if ([[[roles objectAtIndex:i] identifier] isEqualToString:identifier]) {
			return i;
		}
	}
	return NSNotFound;
}

/* How many of the tree's parts have the label. */
static NSUInteger
ORMLabelUses(ORMQueryPart *tree, NSString *label)
{
	NSUInteger uses = 0;
	for (ORMQueryPart *part in [tree tree]) {
		uses += [part.label isEqualToString:label] ? 1 : 0;
	}
	return uses;
}

/* The tree's label, wherever it is, another: the same object for both. */
static void
ORMRelabel(ORMQueryPart *tree, NSString *from, NSString *to)
{
	for (ORMQueryPart *part in [tree tree]) {
		if ([part.label isEqualToString:from]) {
			part.label = to;
		}
	}
}

/* A derivation's node become the query's: the query's label, the rule's
 * nodes of the same label with it; the rule's own label kept only where
 * another of its nodes is the same object by it. */
static void
ORMMergeLabel(ORMQueryPart *tree, ORMQueryPart *theirs, NSString *ours, ORMQueryPart *into)
{
	NSString *label = theirs.label;
	if ([ours length] > 0) {
		if (label != nil) {
			ORMRelabel(tree, label, ours);
		}
		into.label = ours;
	} else if (label != nil && ORMLabelUses(tree, label) < 2) {
		into.label = nil;
	} else {
		into.label = label;
	}
}

/* Whether the node's steps are alternatives. */
static BOOL
ORMCombinesWithOr(ORMQueryPart *node)
{
	return [node.combine isEqualToString:@"Or"];
}

/* The step through a derived fact type put as its derivation's path,
 * under the node it is from. nil when done; why otherwise. */
/* A derivation's tree made the query's own: fresh ids, its labels apart
 * from the query's, nothing it lists or sorts by but what the query's
 * nodes say. */
static void
ORMFreshen(ORMQueryPart *tree, NSString *name, NSUInteger round)
{
	for (ORMQueryPart *part in [tree tree]) {
		NSString *was = part.identifier;
		NSString *now = ORMNewId();
		part.identifier = now;
		if (was != nil) {
			ORMRenameNode(tree, was, now);
		}
		if ([part.label length] > 0) {
			part.label = [NSString stringWithFormat:@"%@ (%@ %lu)", part.label, name, (unsigned long)round];
		}
		if ([part.name length] > 0) {
			part.name = [NSString stringWithFormat:@"%@ (%@ %lu)", part.name, name, (unsigned long)round];
		}
		part.projected = nil;
		part.forRole = nil;
		part.sort = nil;
	}
}

/* A derived subtype's rule grafted on the node, an instance of its
 * supertype: what the rule says of its root, said of the node, and its
 * steps the node's. Why not, where not. */
static NSString *
ORMGraftSubtypeRule(ORMQueryPart *at, ORMObjectType *subtype, ORMStoredQuery *rule, NSString *name, NSUInteger round)
{
	ORMQueryPart *tree = [rule.root copy];
	ORMFreshen(tree, name, round);
	if ([[tree steps] count] > 0 && ORMCombinesWithOr(at) && [[at steps] count] > 0) {
		return [NSString stringWithFormat:@"%@ is met where steps are combined with or, which its rule's cannot be.",
		                                  subtype.name];
	}
	for (NSString *key in @[ @"comparison", @"value", @"compareTo" ]) {
		NSString *value = [tree valueForKey:key];
		if (value == nil) {
			continue;
		}
		if ([at valueForKey:key] != nil && ![[at valueForKey:key] isEqualToString:value]) {
			return [NSString stringWithFormat:@"%@ says more of its root than the query can take with it.", name];
		}
		[at setValue:value forKey:key];
	}
	ORMMergeLabel(tree, tree, at.label, at);
	ORMRenameNode(tree, tree.identifier, at.identifier);
	for (ORMQueryPart *step in [[tree steps] arrayByAddingObjectsFromArray:[tree values]]) {
		[step detach];
		[at addPart:step];
	}
	return nil;
}

/* "is Cost", from a node of its supertype, to a subtype derived by a
 * rule: no step, the same object, the subtype's rule and what the query
 * says of the subtype said of the node. Why not, where not. */
static NSString *
ORMExpandSubtypeStep(ORMQueryPart *step, ORMObjectType *subtype, ORMStoredQuery *rule, NSString *name,
                     NSUInteger round, ORMModel *model)
{
	ORMQueryPart *from = [step parent];
	ORMQueryPart *node = [[step nodes] firstObject];
	if (from == nil || node == nil) {
		return [NSString stringWithFormat:@"\"is %@\" is no step from a node.", subtype.name];
	}
	/* What the query says of the subtype's node, said of the same object. */
	for (NSString *key in @[ @"projected", @"comparison", @"value", @"compareTo", @"sort" ]) {
		NSString *value = [node valueForKey:key];
		if (value != nil && [from valueForKey:key] != nil && ![[from valueForKey:key] isEqualToString:value]) {
			return [NSString stringWithFormat:@"%@ and its supertype are said different things of.", subtype.name];
		}
		if (value != nil) {
			[from setValue:value forKey:key];
		}
	}
	if ([node.label length] > 0) {
		ORMMergeLabel(from, node, from.label, from);
	}
	ORMRenameNode(from, node.identifier, from.identifier);
	[step detach];
	for (ORMQueryPart *each in [[node steps] arrayByAddingObjectsFromArray:[node values]]) {
		[each detach];
		[from addPart:each];
	}
	return ORMGraftSubtypeRule(from, subtype, rule, name, round);
}

/* The subtype a part brings in that a rule derives and does not store: a
 * query's root of it, or a step to it from its supertype. */
static ORMObjectType *
ORMDerivedSubtypeOf(ORMQueryPart *part, ORMModel *model)
{
	ORMObjectType *type = nil;
	if (!part.isStep && [part parent] == nil) {
		type = [model elementWithId:part.ref];
	} else if (part.isStep) {
		ORMFactType *fact = [model elementWithId:part.ref];
		ORMRole *entry = [model elementWithId:part.roleId];
		if ([fact isKindOfClass:[ORMFactType class]] && fact.kind == ORMFactTypeSubtype && entry.isSupertypeMetaRole) {
			type = [[entry oppositeRole] player];
		}
	}
	ORMDerivationRule *rule = [type isKindOfClass:[ORMObjectType class]] ? [type derivationRule] : nil;
	return rule != nil && !rule.isStored ? type : nil;
}

static NSString *
ORMExpandStep(ORMQueryPart *step, ORMFactType *fact, ORMQuery *derivation, ORMStoredQuery *rule, NSUInteger round,
              ORMModel *model)
{
	NSString *what = [fact displayText];
	ORMQueryPart *from = [step parent];
	ORMQueryPart *tree = [rule.root copy];
	NSArray *all = [tree tree];
	/* Its columns, in the order the planner lists them: the fact type's
	 * roles. */
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMQueryPart *part in all) {
		if (!part.isStep && [part.projected isEqualToString:@"true"]) {
			[columns addObject:part];
		}
	}
	NSArray *roles = [fact visibleRoles];
	NSArray *ordered = [derivation derivedColumns];
	if (ordered == nil || [columns count] != [roles count]) {
		return [NSString stringWithFormat:@"\"%@\" is derived by %@, which does not list one of each of its roles.", what,
		                                  derivation.name];
	}
	/* In the order of the roles, as the query says. */
	NSMutableArray *byRole = [NSMutableArray array];
	for (ORMQueryNode *node in ordered) {
		for (ORMQueryPart *column in columns) {
			if ([column.identifier isEqualToString:node.identifier]) {
				[byRole addObject:column];
			}
		}
	}
	if ([byRole count] != [roles count]) {
		return [NSString stringWithFormat:@"\"%@\" is derived by %@, which does not list one of each of its roles.", what,
		                                  derivation.name];
	}
	columns = byRole;
	ORMFreshen(tree, derivation.name, round);
	NSUInteger entry = ORMIndexOfRole(roles, step.roleId);
	if (entry == NSNotFound) {
		return [NSString stringWithFormat:@"\"%@\" is gone through by a role it does not show.", what];
	}
	NSString *why = nil;
	ORMQueryPart *root = ORMReroot([columns objectAtIndex:entry], model, &why);
	if (root == nil) {
		return [NSString stringWithFormat:@"\"%@\" cannot be gone through from there: %@.", what, why];
	}
	/* The node the step is from is the column it enters by. Steps meet
	 * there: the rule's with the query's others, which an or keeps apart
	 * only where one side has but one. */
	NSArray *moved = [root steps];
	NSUInteger beside = [[from steps] count] - 1;
	if ([moved count] > 1 && ORMCombinesWithOr(from) != ORMCombinesWithOr(root)) {
		if (beside > 0) {
			return [NSString stringWithFormat:@"\"%@\" is gone through where steps are combined with or, and its rule "
			                                  @"has several steps there, combined otherwise.",
			                                  what];
		}
		from.combine = root.combine;
	}
	ORMMergeLabel(tree, root, from.label, from);
	for (NSString *key in @[ @"comparison", @"value", @"compareTo" ]) {
		NSString *value = [root valueForKey:key];
		if (value == nil) {
			continue;
		}
		if ([from valueForKey:key] != nil && ![[from valueForKey:key] isEqualToString:value]) {
			return [NSString stringWithFormat:@"\"%@\" says more of %@ than the query can take with it.", what,
			                                  [roles[entry] player].name];
		}
		[from setValue:value forKey:key];
	}
	ORMRenameNode(tree, root.identifier, from.identifier);
	/* The step's other nodes are the other columns: what the query says
	 * of each, with what the rule says. */
	for (ORMQueryPart *node in [step nodes]) {
		NSUInteger index = ORMIndexOfRole(roles, node.roleId);
		if (index == NSNotFound || index == entry) {
			continue;
		}
		ORMQueryPart *column = [columns objectAtIndex:index];
		NSArray *more = [node steps];
		NSArray *its = [column steps];
		if ([more count] > 0 && [its count] > 0 && (ORMCombinesWithOr(node) || ORMCombinesWithOr(column))
		    && !([more count] == 1 && [its count] == 1)) {
			return [NSString stringWithFormat:@"\"%@\" is gone through to %@, whose steps there are combined with or.",
			                                  what, [roles[index] player].name];
		}
		ORMMergeLabel(tree, column, node.label, column);
		for (NSArray *attribute in ORMQueryPartAttributes()) {
			NSString *key = [attribute lastObject];
			NSString *value = [node valueForKey:key];
			if (value == nil || [key isEqualToString:@"roleId"] || [key isEqualToString:@"label"]
			    || [key isEqualToString:@"combine"]) {
				continue;
			}
			NSString *theirs = [column valueForKey:key];
			if (theirs != nil && ![theirs isEqualToString:value]) {
				return [NSString stringWithFormat:@"\"%@\" says more of %@ than the query can take with it.", what,
				                                  [roles[index] player].name];
			}
			[column setValue:value forKey:key];
		}
		ORMRenameNode(tree, column.identifier, node.identifier);
		column.identifier = node.identifier;
		if ([its count] == 0) {
			column.combine = node.combine;
		}
		for (ORMQueryPart *each in [more arrayByAddingObjectsFromArray:[node values]]) {
			[column addPart:each];
		}
	}
	/* The rule's steps from the entry column go under the node, where the
	 * step was; the step's not, maybe or count with them, where there is
	 * one to carry it. */
	BOOL qualified = NO;
	for (NSString *key in ORMStepQualifiers()) {
		qualified = qualified || [step valueForKey:key] != nil;
	}
	if (qualified && [moved count] != 1) {
		return [NSString stringWithFormat:@"\"%@\" is gone through with not, maybe or a count, and its rule branches "
		                                  @"there.",
		                                  what];
	}
	NSUInteger at = [step index];
	for (ORMQueryPart *each in moved) {
		[each detach];
		for (NSString *key in qualified ? ORMStepQualifiers() : @[]) {
			[each setValue:[step valueForKey:key] forKey:key];
		}
		[from insertPart:each atIndex:at++];
	}
	/* And its value nodes, the node's now. */
	for (ORMQueryPart *each in [root values]) {
		[from addPart:each];
	}
	[step detach];
	return nil;
}

- (ORMQuery *)expandedInModel:(ORMModel *)model notes:(NSMutableArray<NSString *> *)notes
{
	ORMStoredQuery *stored = nil;
	for (ORMStoredQuery *each in model.storedQueries) {
		stored = [each.identifier isEqualToString:self.identifier] ? each : stored;
	}
	/* A query read from NORMA's rule is not in the model: read again. */
	if (stored == nil && self.kind == ORMQueryDerivation && self.derivedFactType != nil) {
		NSString *unread = nil;
		stored = ORMDerivationQuery(self.derivedFactType, model, &unread);
	}
	if (stored == nil) {
		return self;
	}
	ORMStoredQuery *copy = nil;
	for (NSUInteger round = 1;; round++) {
		ORMQueryPart *step = nil;
		ORMFactType *fact = nil;
		for (ORMQueryPart *each in [(copy ?: stored).root tree]) {
			ORMFactType *through = each.isStep ? [model elementWithId:each.ref] : nil;
			if ([through isKindOfClass:[ORMFactType class]] && through.isDerived && ![through derivationRule].isStored) {
				step = each;
				fact = through;
				break;
			}
		}
		/* A subtype a rule derives: its rule, where it is met. */
		ORMQueryPart *subtyped = nil;
		ORMObjectType *subtype = nil;
		for (ORMQueryPart *each in step == nil ? [(copy ?: stored).root tree] : @[]) {
			subtype = ORMDerivedSubtypeOf(each, model);
			if (subtype != nil) {
				subtyped = each;
				break;
			}
		}
		if (subtyped != nil) {
			ORMQuery *derivation = [ORMQuery derivationOfSubtype:subtype inModel:model];
			ORMStoredQuery *rule = nil;
			for (ORMStoredQuery *each in model.storedQueries) {
				rule = [each.identifier isEqualToString:derivation.identifier] ? each : rule;
			}
			NSString *why = nil;
			if ([subtype derivationRule].isPartial) {
				why = [NSString stringWithFormat:@"%@ is partly derived and not stored: queries do not go through it yet.",
				                                 subtype.name];
			} else if (rule == nil) {
				why = [NSString stringWithFormat:@"%@ is derived by its rule's words alone, which queries cannot run.",
				                                 subtype.name];
			} else if (round > 16) {
				why = [NSString stringWithFormat:@"%@ is derived through itself, which queries do not run.", subtype.name];
			}
			if (why == nil) {
				if (copy == nil) {
					copy = [stored copy];
					for (ORMQueryPart *each in [copy.root tree]) {
						subtyped = [each.identifier isEqualToString:subtyped.identifier] ? each : subtyped;
					}
				}
				if (subtyped.isStep) {
					why = ORMExpandSubtypeStep(subtyped, subtype, rule, derivation.name, round, model);
				} else {
					/* A query of the subtype: of its rule's root, the supertype. */
					copy.root.ref = rule.root.ref;
					why = ORMGraftSubtypeRule(copy.root, subtype, rule, derivation.name, round);
				}
			}
			if (why != nil) {
				[notes addObject:why];
				return nil;
			}
			continue;
		}
		if (step == nil) {
			break;
		}
		NSString *what = [fact displayText];
		NSString *unplain = nil;
		ORMStoredQuery *rule = ORMDerivationQuery(fact, model, &unplain);
		ORMQuery *derivation = rule != nil ? [ORMQuery queryOf:rule model:model] : nil;
		NSString *why = nil;
		if ([fact derivationRule].isPartial) {
			/* Its asserted facts and its derived ones: an or the expansion
			 * cannot say yet. */
			why = [NSString stringWithFormat:@"\"%@\" is partly derived and not stored: queries do not go through it yet.",
			                                 what];
		} else if (rule == nil) {
			why = [NSString stringWithFormat:@"\"%@\" is derived by NORMA's rule, which queries cannot run: %@.", what,
			                                 unplain ?: @"it has no path"];
		} else if (round > 16) {
			why = [NSString stringWithFormat:@"\"%@\" is derived through itself, which queries do not run.", what];
		}
		if (why == nil) {
			if (copy == nil) {
				copy = [stored copy];
				/* The step found again in the copy. */
				for (ORMQueryPart *each in [copy.root tree]) {
					step = [each.identifier isEqualToString:step.identifier] ? each : step;
				}
			}
			why = ORMExpandStep(step, fact, derivation, rule, round, model);
		}
		if (why != nil) {
			[notes addObject:why];
			return nil;
		}
	}
	return copy != nil ? [ORMQuery queryOf:copy model:model] : self;
}

+ (ORMQuery *)queryOf:(ORMStoredQuery *)stored model:(ORMModel *)model
{
	ORMQuery *query = [[ORMQuery alloc] init];
	query.identifier = stored.identifier;
	query.name = stored.name ?: @"Query";
	query.isComplete = YES;
	NSUInteger kind = [ORMQueryKindNames() indexOfObject:stored.kind ?: @"List"];
	query.kind = kind != NSNotFound ? (ORMQueryKind)kind : ORMQueryList;
	query.isDeontic = query.kind == ORMQueryConstraint && [stored.modality isEqualToString:@"Deontic"];
	NSUInteger function = [ORMCalculationFunctionNames() indexOfObject:stored.function ?: @"Value"];
	query.calculationFunction = function != NSNotFound ? (ORMQueryCalculationFunction)function : ORMCalculationValue;
	if (query.kind == ORMQueryDerivation) {
		id derived = [model elementWithId:stored.of];
		query.derivedFactType = [derived isKindOfClass:[ORMFactType class]] ? derived : nil;
		query.derivedSubtype = [derived isKindOfClass:[ORMObjectType class]] ? derived : nil;
	}
	ORMQueryPart *rootPart = stored.root;
	ORMObjectType *type = [model elementWithId:rootPart.ref];
	if (![type isKindOfClass:[ORMObjectType class]]) {
		query.isComplete = NO;
		return query;
	}
	query.root = [query nodeOf:rootPart type:type role:nil model:model];
	[query dropValuesUsingWhatIsGone];
	/* What a condition compares with, now every node is read. */
	NSArray *nodes = [query nodes];
	NSString *of = query.kind == ORMQueryCalculation ? stored.of : nil;
	for (ORMQueryNode *node in of != nil ? nodes : @[]) {
		if ([node.identifier isEqualToString:of]) {
			query.calculatedNode = node;
		}
	}
	for (ORMQueryNode *node in nodes) {
		for (ORMQueryNode *other in node.comparedNodeId != nil ? nodes : @[]) {
			if ([other.identifier isEqualToString:node.comparedNodeId]) {
				node.comparedNode = other;
			}
		}
		/* What each step aggregates: its own node unless it says; and for
		 * what, its parent unless it says. */
		for (ORMQueryStep *step in node.steps) {
			step.aggregateNode = [step.nodes firstObject];
			step.groupNode = step.parent;
			for (ORMQueryNode *other in nodes) {
				if ([other.identifier isEqualToString:step.aggregateNodeId ?: @""]) {
					step.aggregateNode = other;
				}
				if ([other.identifier isEqualToString:step.groupNodeId ?: @""]) {
					step.groupNode = other;
				}
				if ([other.identifier isEqualToString:step.comparedGroupNodeId ?: @""]) {
					step.comparedGroupNode = other;
				}
			}
			step.comparesAggregates = step.comparesAggregates && step.comparedGroupNode != nil;
		}
		/* What it was compared with is gone: so is the condition. */
		if (node.comparedNodeId != nil && node.comparedNode == nil) {
			node.comparison = nil;
			query.isComplete = NO;
		}
	}
	return query;
}

/* A value node uses only nodes before it, in outline order: one using a
 * node that is gone, or one after it, is left out. */
- (void)dropValuesUsingWhatIsGone
{
	NSMutableSet *before = [NSMutableSet set];
	for (ORMQueryNode *node in [self nodes]) {
		if (node.isValue) {
			BOOL known = YES;
			for (NSString *used in [node.expression nodeIds]) {
				known = known && [before containsObject:used];
			}
			if (!known) {
				node.valueOf.values = ORMWithout(node.valueOf.values, node);
				self.isComplete = NO;
				continue;
			}
		}
		[before addObject:node.identifier ?: @""];
	}
}

- (ORMQueryNode *)nodeOf:(ORMQueryPart *)part type:(ORMObjectType *)type role:(ORMRole *)role model:(ORMModel *)model
{
	ORMQueryNode *node = [[ORMQueryNode alloc] init];
	node.identifier = part.identifier;
	node.objectType = type;
	node.role = role;
	node.isProjected = ORMBoolValue(part.projected, NO);
	ORMRole *derived = [model elementWithId:part.forRole ?: @""];
	node.derivedRole = [derived isKindOfClass:[ORMRole class]] ? derived : nil;
	node.comparison = part.comparison;
	node.value = part.value;
	node.comparedNodeId = part.compareTo;
	node.label = [part.label length] > 0 ? part.label : nil;
	node.combinesWithOr = [part.combine isEqualToString:@"Or"];
	node.sortOrder = [part.sort isEqualToString:@"Ascending"] ? ORMQueryAscending
		: [part.sort isEqualToString:@"Descending"] ? ORMQueryDescending : ORMQueryUnsorted;
	NSMutableArray *steps = [NSMutableArray array];
	for (ORMQueryPart *stepPart in [part steps]) {
		ORMQueryStep *step = [self stepOf:stepPart parent:node model:model];
		if (step != nil) {
			[steps addObject:step];
		} else {
			self.isComplete = NO;
		}
	}
	node.steps = steps;
	NSMutableArray *values = [NSMutableArray array];
	for (ORMQueryPart *valuePart in [part values]) {
		ORMObjectType *valueType = [model elementWithId:valuePart.ref ?: @""];
		ORMQueryExpression *expression = valuePart.expression != nil
			? [ORMQueryExpression expressionWithCanonicalText:valuePart.expression reason:NULL] : nil;
		if (![valueType isKindOfClass:[ORMObjectType class]] || expression == nil || [valuePart.name length] == 0) {
			self.isComplete = NO;
			continue;
		}
		ORMQueryNode *value = [self nodeOf:valuePart type:valueType role:nil model:model];
		value.isValue = YES;
		value.name = valuePart.name;
		value.expression = expression;
		value.valueOf = node;
		[values addObject:value];
	}
	node.values = values;
	return node;
}

- (ORMQueryStep *)stepOf:(ORMQueryPart *)part parent:(ORMQueryNode *)parent model:(ORMModel *)model
{
	ORMFactType *fact = [model elementWithId:part.ref];
	ORMRole *entry = [model elementWithId:part.roleId];
	if (![fact isKindOfClass:[ORMFactType class]] || ![entry isKindOfClass:[ORMRole class]] || entry.factType != fact) {
		return nil;
	}
	ORMQueryStep *step = [[ORMQueryStep alloc] init];
	step.identifier = part.identifier;
	step.factType = fact;
	step.entryRole = entry;
	step.parent = parent;
	step.operatorKind = [part.operatorName isEqualToString:@"Not"] ? ORMQueryNot
		: [part.operatorName isEqualToString:@"Maybe"] ? ORMQueryMaybe : ORMQueryAnd;
	step.countComparison = part.countComparison;
	step.aggregateValue = part.countValueText;
	step.countValue = (NSUInteger)[step.aggregateValue integerValue];
	NSUInteger aggregate = [ORMQueryAggregateNames() indexOfObject:part.aggregateName ?: @"Count"];
	step.aggregate = aggregate != NSNotFound ? (ORMQueryAggregate)aggregate : ORMQueryCount;
	step.aggregateNodeId = part.aggregateNodeId;
	step.groupNodeId = part.groupNodeId;
	NSUInteger comparedIndex = part.compareAggregate != nil
		? [ORMQueryAggregateNames() indexOfObject:part.compareAggregate] : NSNotFound;
	step.comparesAggregates = comparedIndex != NSNotFound;
	step.comparedAggregate = comparedIndex != NSNotFound ? (ORMQueryAggregate)comparedIndex : ORMQueryCount;
	step.comparedGroupNodeId = part.compareGroupNode;
	NSMutableArray *nodes = [NSMutableArray array];
	for (ORMQueryPart *nodePart in [part nodes]) {
		ORMRole *role = [model elementWithId:nodePart.roleId];
		if (![role isKindOfClass:[ORMRole class]] || role.factType != fact || role == entry || role.player == nil) {
			self.isComplete = NO;
			continue;
		}
		ORMQueryNode *node = [self nodeOf:nodePart type:role.player role:role model:model];
		node.step = step;
		[nodes addObject:node];
	}
	step.nodes = nodes;
	return step;
}

+ (NSString *)nameOfAggregate:(ORMQueryAggregate)aggregate
{
	return [@[ @"count", @"total", @"avg", @"max", @"min" ] objectAtIndex:(NSUInteger)aggregate];
}

+ (NSArray<ORMRole *> *)rolesFrom:(ORMObjectType *)type
{
	NSMutableArray *roles = [NSMutableArray array];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:type];
	NSMutableSet *seen = [NSMutableSet set];
	while ([pending count] > 0) {
		ORMObjectType *at = [pending objectAtIndex:0];
		[pending removeObjectAtIndex:0];
		if ([seen containsObject:at.identifier]) {
			continue;
		}
		[seen addObject:at.identifier];
		for (ORMRole *role in at.playedRoles) {
			/* A link fact type is gone through as its objectified fact
			 * type's role: NORMA's paths do. */
			if ((role.factType.kind == ORMFactTypeImplied && ![role.factType isLinkFactType])
			    || role.player.isImplicitBooleanValue) {
				continue;
			}
			/* The reference scheme is how a condition names the instance
			 * ("Branch = 52"), not a step. */
			if (role.factType == at.referenceModeFactType) {
				continue;
			}
			/* A supertype's roles are its subtypes' too; its link to its
			 * other subtypes is not. */
			if (at != type && role.isSupertypeMetaRole) {
				continue;
			}
			[roles addObject:role];
		}
		[pending addObjectsFromArray:at.supertypes];
	}
	return roles;
}

#pragma mark Reading it

- (NSArray<ORMQueryNode *> *)nodes
{
	NSMutableArray *nodes = [NSMutableArray array];
	if (self.root != nil) {
		[self collect:self.root into:nodes];
	}
	return nodes;
}

- (void)collect:(ORMQueryNode *)node into:(NSMutableArray *)nodes
{
	[nodes addObject:node];
	for (ORMQueryStep *step in node.steps) {
		for (ORMQueryNode *child in step.nodes) {
			[self collect:child into:nodes];
		}
	}
	[nodes addObjectsFromArray:node.values];
}

- (ORMQueryNode *)firstOccurrenceOf:(ORMQueryNode *)node
{
	if (node.label == nil) {
		return node;
	}
	for (ORMQueryNode *other in [self nodes]) {
		if (other.objectType == node.objectType && [other.label isEqualToString:node.label]) {
			return other;
		}
	}
	return node;
}

- (NSArray<ORMQueryNode *> *)projectedNodes
{
	return [[self nodes] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ORMQueryNode *node,
	                                                                                        NSDictionary *bindings) {
		(void)bindings;
		return node.isProjected;
	}]];
}

+ (NSString *)readingOfStep:(ORMQueryStep *)step
{
	return [self readingFrom:step.entryRole nodeRoles:[step.nodes valueForKey:@"role"]];
}

+ (NSArray<ORMRole *> *)nodeRolesFrom:(ORMRole *)entry
{
	NSMutableArray *roles = [NSMutableArray array];
	for (ORMRole *role in entry.factType.roles) {
		if (role != entry && !role.player.isImplicitBooleanValue) {
			[roles addObject:role];
		}
	}
	return roles;
}

+ (NSString *)readingFrom:(ORMRole *)entry nodeRoles:(NSArray<ORMRole *> *)nodeRoles
{
	/* A subtype fact type reads as the model reads it, from the entry. */
	NSArray *roles = [entry.factType subtypeReadingRolesFrom:entry];
	NSString *text = roles != nil ? ORMSubtypeReadingText : nil;
	BOOL fromEntry = roles != nil;
	if (roles == nil) {
		ORMReadingOrder *start = [entry.factType readingOrderStartingWithRole:entry];
		ORMReadingOrder *chosen = [(ORMReading *)[start.readings firstObject] readsFromFirstRole] ? start : nil;
		ORMReadingOrder *order = chosen ?: [entry.factType.readingOrders firstObject];
		text = [[order.readings firstObject] text];
		roles = order.roles;
		fromEntry = chosen != nil;
	}
	if (text == nil) {
		return @"";
	}
	/* The entry is {0}, the nodes {1} on. */
	NSMutableArray *places = [NSMutableArray array];
	for (ORMRole *role in roles) {
		NSUInteger index = [nodeRoles indexOfObjectIdenticalTo:role];
		[places addObject:role == entry ? @"{0}"
		                  : index != NSNotFound ? [NSString stringWithFormat:@"{%lu}", (unsigned long)index + 1] : @""];
	}
	NSString *rewritten = ORMRewritePlaceholders(text, places);
	/* Read from the entry role: the node above is the subject. */
	if (fromEntry && [rewritten hasPrefix:@"{0}"]) {
		rewritten = [[rewritten substringFromIndex:3]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	}
	return rewritten;
}

- (NSString *)conditionText:(ORMQueryNode *)node
{
	if (node.comparison == nil) {
		return @"";
	}
	if (node.comparedNode != nil) {
		return [NSString stringWithFormat:@" %@ %@", node.comparison, [node.comparedNode designation]];
	}
	NSString *value = node.value ?: @"";
	if (![node isNumeric]) {
		/* Quoted, a quote in it doubled, as SQL does. */
		value = [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
	}
	return [NSString stringWithFormat:@" %@ %@", node.comparison, value];
}

- (NSString *)nodeText:(ORMQueryNode *)node
{
	NSString *sort = node.sortOrder == ORMQueryAscending ? @" ↑" : node.sortOrder == ORMQueryDescending ? @" ↓" : @"";
	/* A value node with what it computes: "Length = Quantity2 - Quantity1". */
	NSString *computed = node.isValue
		? [@" = " stringByAppendingString:[node.expression textWithDesignations:[self designationsById]]] : @"";
	return [NSString stringWithFormat:@"%@%@%@%@%@", node.isProjected ? @"✓" : @"", [node designation], computed,
	                                  [self conditionText:node], sort];
}

- (NSDictionary<NSString *, NSString *> *)designationsById
{
	NSMutableDictionary *designations = [NSMutableDictionary dictionary];
	for (ORMQueryNode *node in [self nodes]) {
		[designations setObject:[node designation] forKey:node.identifier ?: @""];
	}
	return designations;
}

- (NSDictionary<NSString *, NSString *> *)nodeIdsByDesignationAmong:(NSArray<ORMQueryNode *> *)nodes
{
	NSMutableDictionary *ids = [NSMutableDictionary dictionary];
	NSMutableSet *ambiguous = [NSMutableSet set];
	for (ORMQueryNode *node in nodes) {
		NSString *designation = [node designation];
		ORMQueryNode *first = [self firstOccurrenceOf:node];
		NSString *known = [ids objectForKey:designation];
		/* Two nodes of a designation are one object only by a label. */
		if (known != nil && ![known isEqualToString:first.identifier]) {
			[ambiguous addObject:designation];
		}
		if (known == nil) {
			[ids setObject:first.identifier forKey:designation];
		}
	}
	[ids removeObjectsForKeys:[ambiguous allObjects]];
	return ids;
}

+ (NSString *)nameOfCalculationFunction:(ORMQueryCalculationFunction)function
{
	NSArray *names = @[ @"value", @"count", @"total", @"avg", @"max", @"min" ];
	return (NSUInteger)function < [names count] ? [names objectAtIndex:(NSUInteger)function] : @"value";
}

/* A step's node as the outline names it, above its steps: its type's
 * name, and which of the step's nodes of that type it is where there are
 * several ("Employee (2)"). */
static NSString *
ORMOutlineNameOf(ORMQueryNode *node, ORMQueryStep *step)
{
	NSUInteger same = 0;
	NSUInteger which = 0;
	for (ORMQueryNode *each in step.nodes) {
		if (each.objectType == node.objectType) {
			same++;
			which = each == node ? same : which;
		}
	}
	NSString *name = node.objectType.name ?: @"?";
	return same > 1 ? [NSString stringWithFormat:@"%@ (%lu)", name, (unsigned long)which] : name;
}

- (NSString *)outlineText
{
	if (self.root == nil) {
		return @"";
	}
	NSMutableString *out = [NSMutableString string];
	if (self.kind == ORMQueryConstraint) {
		/* Its rows are what must not be. */
		[out appendString:self.isDeontic ? @"It is forbidden that:\n" : @"It is impossible that:\n"];
	} else if (self.kind == ORMQueryCalculation) {
		[out appendFormat:@"%@ of each %@ is %@(%@) of:\n", self.name, self.root.objectType.name ?: @"?",
		                  [ORMQuery nameOfCalculationFunction:self.calculationFunction],
		                  [self.calculatedNode designation] ?: @"?"];
	} else if (self.kind == ORMQueryDerivation && self.derivedFactType != nil) {
		[out appendFormat:@"Derivation of \"%@\":\n",
		                  [self.derivedFactType displayText]];
	} else if (self.kind == ORMQueryDerivation && self.derivedSubtype != nil) {
		/* A subtype by its name, unquoted: "Derivation of Cost:". */
		[out appendFormat:@"Derivation of %@:\n", self.derivedSubtype.name];
	} else if (self.kind == ORMQueryDerivation) {
		[out appendString:@"Derivation:\n"];
	}
	[out appendFormat:@"%@\n", [self nodeText:self.root]];
	[self outlineSteps:self.root indent:1 into:out];
	return out;
}

- (void)outlineSteps:(ORMQueryNode *)node indent:(NSUInteger)indent into:(NSMutableString *)out
{
	NSString *pad = [@"" stringByPaddingToLength:indent * 2 withString:@" " startingAtIndex:0];
	BOOL first = YES;
	for (ORMQueryStep *step in node.steps) {
		NSMutableArray *places = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"that %@", node.objectType.name]];
		for (ORMQueryNode *each in step.nodes) {
			[places addObject:[self nodeText:each]];
		}
		NSString *reading = ORMRewritePlaceholders([ORMQuery readingOfStep:step], places);
		NSString *operator = step.operatorKind == ORMQueryNot ? @"not " : step.operatorKind == ORMQueryMaybe ? @"maybe "
		                                                                                                       : @"";
		[out appendFormat:@"%@+ %@%@%@\n", pad, node.combinesWithOr && !first ? @"or " : @"", operator, reading];
		first = NO;
		if (step.countComparison != nil && step.aggregateNode != nil) {
			NSString *compared = step.comparesAggregates
				? [NSString stringWithFormat:@"%@(%@) for %@", [ORMQuery nameOfAggregate:step.comparedAggregate],
				                             [step.aggregateNode designation], [step.comparedGroupNode designation]]
				: step.aggregateValue ?: @"";
			[out appendFormat:@"%@  + %@(%@) for %@ %@ %@\n", pad, [ORMQuery nameOfAggregate:step.aggregate],
			                  [step.aggregateNode designation], [step.groupNode ?: node designation],
			                  step.countComparison, compared];
		}
		for (ORMQueryNode *child in step.nodes) {
			if ([child.steps count] == 0 && [child.values count] == 0) {
				continue;
			}
			if (child != [step.nodes firstObject]) {
				[out appendFormat:@"%@  %@:\n", pad, ORMOutlineNameOf(child, step)];
			}
			[self outlineSteps:child indent:indent + 1 into:out];
		}
	}
	/* Its value nodes, after its steps, without a "+". */
	for (ORMQueryNode *value in node.values) {
		[out appendFormat:@"%@%@\n", pad, [self nodeText:value]];
	}
}

#pragma mark As logic

/* An expression as a term: a node's variable, a constant, a function. */
static ORMTerm *
ORMTermOfExpression(ORMQueryExpression *expression, NSDictionary *variables)
{
	switch (expression.kind) {
	case ORMQueryExpressionNode: {
		ORMVariable *variable = [variables objectForKey:expression.nodeId ?: @""];
		return variable != nil ? [ORMTerm termWithVariable:variable] : [ORMTerm termWithConstant:@"?"];
	}
	case ORMQueryExpressionConstant:
		return [ORMTerm termWithConstant:expression.constant ?: @""];
	case ORMQueryExpressionFunction:
		break;
	}
	NSMutableArray *arguments = [NSMutableArray array];
	for (ORMQueryExpression *argument in expression.arguments) {
		[arguments addObject:ORMTermOfExpression(argument, variables)];
	}
	return [ORMTerm termWithFunction:expression.function arguments:arguments aggregate:NO];
}

- (ORMRelation *)relation
{
	if (self.root == nil) {
		return nil;
	}
	/* A variable for each node, but one for each label of an object type:
	 * those nodes are the same object. */
	NSMutableDictionary *variables = [NSMutableDictionary dictionary];
	for (ORMQueryNode *node in [self nodes]) {
		ORMQueryNode *first = [self firstOccurrenceOf:node];
		ORMVariable *variable = [variables objectForKey:first.identifier] ?: [ORMVariable variableOf:node.objectType];
		if (node.isValue) {
			variable.name = node.name;
		}
		[variables setObject:variable forKey:node.identifier];
	}
	ORMFormula *formula = [self formulaOf:self.root variables:variables];
	/* A derivation's in the order of its fact type's roles. */
	NSArray *listed = (self.kind == ORMQueryDerivation ? [self derivedColumns] : nil) ?: [self projectedNodes];
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMQueryNode *node in listed) {
		[columns addObject:[variables objectForKey:node.identifier]];
	}
	if ([columns count] == 0) {
		[columns addObject:[variables objectForKey:self.root.identifier]];
	}
	return [ORMRelation relationWithFormula:formula columns:columns variables:variables];
}

- (ORMFormula *)conditionOf:(ORMQueryNode *)node variables:(NSDictionary *)variables
{
	if (node.comparison == nil) {
		return nil;
	}
	if (node.comparedNode != nil) {
		return [ORMFormula compare:node.comparison
		                  operands:@[ [ORMTerm termWithVariable:[variables objectForKey:node.identifier]],
		                              [ORMTerm termWithVariable:[variables objectForKey:node.comparedNode.identifier]] ]];
	}
	/* A value as FORML writes one: text quoted, numbers not. */
	NSString *value = [node isNumeric] ? node.value ?: @"" : [NSString stringWithFormat:@"'%@'", node.value ?: @""];
	return [ORMFormula compare:node.comparison
	                  operands:@[ [ORMTerm termWithVariable:[variables objectForKey:node.identifier]],
	                              [ORMTerm termWithConstant:value] ]];
}

- (ORMFormula *)formulaOf:(ORMQueryNode *)node variables:(NSDictionary *)variables
{
	NSMutableArray *conjuncts = [NSMutableArray array];
	ORMFormula *condition = [self conditionOf:node variables:variables];
	if (condition != nil) {
		[conjuncts addObject:condition];
	}
	NSMutableArray *steps = [NSMutableArray array];
	for (ORMQueryStep *step in node.steps) {
		[steps addObject:[self formulaOfStep:step variables:variables]];
	}
	if (node.combinesWithOr && [steps count] > 1) {
		[conjuncts addObject:[ORMFormula combine:ORMFormulaOr children:steps]];
	} else {
		[conjuncts addObjectsFromArray:steps];
	}
	/* Each value node is its expression's value: "Length = subtract(Quantity2,
	 * Quantity1)", then its own condition. */
	for (ORMQueryNode *value in node.values) {
		[conjuncts addObject:[ORMFormula compare:@"="
		                                operands:@[ [ORMTerm termWithVariable:[variables objectForKey:value.identifier]],
		                                            ORMTermOfExpression(value.expression, variables) ]]];
		ORMFormula *valueCondition = [self conditionOf:value variables:variables];
		if (valueCondition != nil) {
			[conjuncts addObject:valueCondition];
		}
	}
	return [conjuncts count] == 1 ? [conjuncts firstObject] : [ORMFormula combine:ORMFormulaAnd children:conjuncts];
}

- (ORMFormula *)formulaOfStep:(ORMQueryStep *)step variables:(NSDictionary *)variables
{
	NSMutableDictionary *terms = [NSMutableDictionary dictionary];
	[terms setObject:[ORMTerm termWithVariable:[variables objectForKey:step.parent.identifier]]
	          forKey:step.entryRole.identifier];
	for (ORMQueryNode *node in step.nodes) {
		[terms setObject:[ORMTerm termWithVariable:[variables objectForKey:node.identifier]] forKey:node.role.identifier];
	}
	ORMFormula *atom = step.operatorKind == ORMQueryMaybe ? [ORMFormula optionalFact:step.factType terms:terms]
	                                                      : [ORMFormula fact:step.factType terms:terms];
	NSMutableArray *conjuncts = [NSMutableArray arrayWithObject:atom];
	for (ORMQueryNode *node in step.nodes) {
		ORMFormula *inner = [self formulaOf:node variables:variables];
		if (inner != nil && !(inner.kind == ORMFormulaAnd && [inner.children count] == 0)) {
			[conjuncts addObject:inner];
		}
	}
	if (step.countComparison != nil && step.aggregateNode != nil) {
		NSArray *functions = @[ @"count", @"total", @"average", @"maximum", @"minimum" ];
		ORMTerm *argument = [ORMTerm termWithVariable:[variables objectForKey:step.aggregateNode.identifier]];
		/* "for that Employee" only where it is for another than the node
		 * above, or compared with another aggregate. */
		BOOL grouped = step.groupNode != step.parent || step.comparesAggregates;
		ORMTerm *aggregate = [ORMTerm termWithFunction:[functions objectAtIndex:(NSUInteger)step.aggregate]
		                                     arguments:@[ argument ] aggregate:YES
		                                         group:grouped ? [ORMTerm termWithVariable:[variables objectForKey:
		                                                                                     step.groupNode.identifier]]
		                                                       : nil];
		ORMTerm *other = step.comparesAggregates
			? [ORMTerm termWithFunction:[functions objectAtIndex:(NSUInteger)step.comparedAggregate] arguments:@[ argument ]
			                  aggregate:YES
			                      group:[ORMTerm termWithVariable:[variables objectForKey:step.comparedGroupNode.identifier]]]
			: [ORMTerm termWithConstant:step.aggregateValue ?: @""];
		[conjuncts addObject:[ORMFormula compare:step.countComparison operands:@[ aggregate, other ]]];
	}
	ORMFormula *formula = [conjuncts count] == 1 ? atom : [ORMFormula combine:ORMFormulaAnd children:conjuncts];
	return step.operatorKind == ORMQueryNot ? [ORMFormula not:formula] : formula;
}

@end

#pragma mark Editing

@implementation ORMQueryEditor

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

- (ORMStoredQuery *)query:(NSString *)identifier
{
	for (ORMStoredQuery *query in identifier != nil ? _editor.model.storedQueries : @[]) {
		if ([query.identifier isEqualToString:identifier]) {
			return query;
		}
	}
	return nil;
}

/* The node or the step of the id, in whichever query has it. */
- (ORMQueryPart *)part:(NSString *)identifier step:(BOOL)isStep
{
	for (ORMStoredQuery *query in identifier != nil ? _editor.model.storedQueries : @[]) {
		ORMQueryPart *part = [query partWithId:identifier step:isStep];
		if (part != nil) {
			return part;
		}
	}
	return nil;
}

/* The query a part is in. */
- (ORMStoredQuery *)queryOfPart:(ORMQueryPart *)part
{
	ORMQueryPart *top = part;
	while ([top parent] != nil) {
		top = [top parent];
	}
	for (ORMStoredQuery *query in part != nil ? _editor.model.storedQueries : @[]) {
		if (query.root == top) {
			return query;
		}
	}
	return nil;
}

- (NSString *)addQueryNamed:(NSString *)name from:(NSString *)objectTypeId reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	if (![type isKindOfClass:[ORMObjectType class]]) {
		if (reason != NULL) {
			*reason = @"A query starts at an object type.";
		}
		return nil;
	}
	ORMStoredQuery *query = [[ORMStoredQuery alloc] initWithModel:_editor.model];
	query.name = [name length] > 0 ? name : [NSString stringWithFormat:@"%@ Query", type.name];
	ORMQueryPart *root = [[ORMQueryPart alloc] init];
	root.identifier = ORMNewId();
	root.ref = type.identifier;
	root.projected = @"true";
	query.root = root;
	[_editor modelChange:@"Add Query" with:^{
		[self->_editor.model addElement:query];
		[self->_editor wrote:query];
	}];
	return query.identifier;
}

/* The fact type a derivation is of. */
- (ORMFactType *)derivedFactTypeOf:(ORMStoredQuery *)query
{
	ORMFactType *derived = [query.kind isEqualToString:@"Derivation"] ? [_editor.model elementWithId:query.of] : nil;
	return [derived isKindOfClass:[ORMFactType class]] ? derived : nil;
}

- (void)removeQuery:(NSString *)queryId
{
	ORMStoredQuery *query = [self query:queryId];
	if (query == nil) {
		return;
	}
	ORMFactType *derived = [self derivedFactTypeOf:query];
	[_editor modelChange:@"Remove Query" with:^{
		[self->_editor.model removeElement:query];
		[self->_editor deleted:query];
		/* What it derived is asserted again. */
		[self->_editor.factTypeEditor removeQueryRuleOf:derived];
	}];
}

- (BOOL)renameQuery:(NSString *)queryId to:(NSString *)name reason:(NSString **)reason
{
	ORMStoredQuery *query = [self query:queryId];
	if (query == nil || [name length] == 0) {
		if (reason != NULL) {
			*reason = query == nil ? @"There is no such query." : @"A query needs a name.";
		}
		return NO;
	}
	if (![query.name isEqualToString:name]) {
		[_editor modelChange:@"Rename Query" with:^{
			query.name = name;
			[self->_editor wrote:query];
		}];
	}
	return YES;
}

- (BOOL)setKind:(ORMQueryKind)kind ofQuery:(NSString *)queryId reason:(NSString **)reason
{
	ORMStoredQuery *query = [self query:queryId];
	if (query == nil || (NSUInteger)kind >= [ORMQueryKindNames() count]) {
		if (reason != NULL) {
			*reason = query == nil ? @"There is no such query." : @"A query lists, is a constraint, or is a calculation.";
		}
		return NO;
	}
	NSString *name = kind == ORMQueryList ? nil : [ORMQueryKindNames() objectAtIndex:(NSUInteger)kind];
	if ([query.kind ?: @"List" isEqualToString:name ?: @"List"]) {
		return YES;
	}
	NSArray *titles = @[ @"Make Query a List", @"Make Query a Constraint", @"Make Query a Calculation",
		              @"Make Query a Derivation" ];
	ORMFactType *derived = [self derivedFactTypeOf:query];
	[_editor modelChange:[titles objectAtIndex:(NSUInteger)kind] with:^{
		query.kind = name;
		/* What only the kind it was had: a calculation's node and a
		 * derivation's fact type are both Of. */
		if (kind != ORMQueryConstraint) {
			query.modality = nil;
		}
		query.function = nil;
		query.of = nil;
		[self->_editor wrote:query];
		/* No longer a derivation: the fact type is asserted again. */
		[self->_editor.factTypeEditor removeQueryRuleOf:derived];
	}];
	return YES;
}

- (BOOL)setDerivedFactType:(NSString *)factTypeId ofQuery:(NSString *)queryId reason:(NSString **)reason
{
	ORMStoredQuery *query = [self query:queryId];
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
	ORMQuery *other = [fact isKindOfClass:[ORMFactType class]] ? [ORMQuery derivationOf:fact inModel:_editor.model] : nil;
	NSString *why = nil;
	if (query == nil) {
		why = @"There is no such query.";
	} else if (![query.kind isEqualToString:@"Derivation"]) {
		why = @"Only a derivation derives a fact type.";
	} else if (![fact isKindOfClass:[ORMFactType class]] || fact.kind != ORMFactTypeOrdinary) {
		why = @"A derivation derives a fact type.";
	} else if (other != nil && ![other.identifier isEqualToString:queryId]) {
		why = [NSString stringWithFormat:@"%@ derives it already.", other.name];
	} else if ([_editor.model.derivationRules objectForKey:fact.identifier].hasRolePath
	           || [_editor.model.derivationRules objectForKey:fact.identifier].hasExpression) {
		why = @"It has NORMA's own derivation rule.";
	} else if (other == nil && [_editor.model.derivationRules objectForKey:fact.identifier] != nil) {
		/* A note of its own, which the query's words would replace. */
		why = @"It has a derivation note of its own: clear it first.";
	}
	if (why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return NO;
	}
	if ([query.of isEqualToString:factTypeId]) {
		return YES;
	}
	ORMFactType *was = [self derivedFactTypeOf:query];
	NSString *name = query.name ?: @"";
	[_editor modelChange:@"Set Derived Fact Type" with:^{
		[self->_editor.factTypeEditor removeQueryRuleOf:was];
		query.of = factTypeId;
		[self->_editor wrote:query];
		[self->_editor.factTypeEditor setQueryRuleOf:fact words:name];
	}];
	return YES;
}

- (BOOL)setDerivedSubtype:(NSString *)objectTypeId ofQuery:(NSString *)queryId reason:(NSString **)reason
{
	ORMStoredQuery *query = [self query:queryId];
	ORMObjectType *subtype = [_editor.model elementWithId:objectTypeId];
	ORMObjectType *root = query != nil ? [_editor.model elementWithId:query.root.ref] : nil;
	ORMQuery *other = [subtype isKindOfClass:[ORMObjectType class]]
		? [ORMQuery derivationOfSubtype:subtype inModel:_editor.model] : nil;
	ORMDerivationRule *rule = [_editor.model.derivationRules objectForKey:objectTypeId];
	NSString *why = nil;
	if (query == nil) {
		why = @"There is no such query.";
	} else if (![query.kind isEqualToString:@"Derivation"]) {
		why = @"Only a derivation derives a subtype.";
	} else if (![subtype isKindOfClass:[ORMObjectType class]] || ![root isKindOfClass:[ORMObjectType class]]
	           || ![subtype isSubtypeOf:root]) {
		why = @"A derivation of a subtype reads one of its supertypes.";
	} else if (other != nil && ![other.identifier isEqualToString:queryId]) {
		why = [NSString stringWithFormat:@"%@ derives it already.", other.name];
	} else if (rule.hasRolePath || rule.hasExpression) {
		why = @"It has NORMA's own derivation rule.";
	}
	if (why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return NO;
	}
	if ([query.of isEqualToString:objectTypeId]) {
		return YES;
	}
	NSString *name = query.name ?: @"";
	[_editor modelChange:@"Set Derived Subtype" with:^{
		query.of = objectTypeId;
		[self->_editor wrote:query];
		/* NORMA's rule, in the modeller's words where it has them. */
		if (rule == nil) {
			[self->_editor.objectTypeEditor setDerivationNote:name ofSubtype:objectTypeId reason:NULL];
		}
	}];
	return YES;
}

- (BOOL)setDeontic:(BOOL)deontic ofQuery:(NSString *)queryId reason:(NSString **)reason
{
	ORMStoredQuery *query = [self query:queryId];
	if (query == nil || ![query.kind isEqualToString:@"Constraint"]) {
		if (reason != NULL) {
			*reason = query == nil ? @"There is no such query." : @"Only a constraint is alethic or deontic.";
		}
		return NO;
	}
	if ([query.modality isEqualToString:@"Deontic"] != deontic) {
		[_editor modelChange:deontic ? @"Make Constraint Deontic" : @"Make Constraint Alethic" with:^{
			query.modality = deontic ? @"Deontic" : nil;
			[self->_editor wrote:query];
		}];
	}
	return YES;
}

- (BOOL)setCalculation:(ORMQueryCalculationFunction)function
                ofNode:(NSString *)nodeId
               inQuery:(NSString *)queryId
                reason:(NSString **)reason
{
	ORMStoredQuery *query = [self query:queryId];
	ORMQueryPart *node = [query partWithId:nodeId step:NO];
	BOOL below = node != nil && node != query.root;
	if (query == nil || ![query.kind isEqualToString:@"Calculation"] || !below
	    || (NSUInteger)function >= [ORMCalculationFunctionNames() count]) {
		if (reason != NULL) {
			*reason = query == nil ? @"There is no such query."
				: (![query.kind isEqualToString:@"Calculation"]
				       ? @"Only a calculation computes a value."
				       : (!below ? @"A calculation is of a node below its object type." : @"There is no such function."));
		}
		return NO;
	}
	NSString *name = [ORMCalculationFunctionNames() objectAtIndex:(NSUInteger)function];
	if ([query.function isEqualToString:name] && [query.of isEqualToString:nodeId]) {
		return YES;
	}
	[_editor modelChange:@"Set Calculation" with:^{
		query.function = name;
		query.of = nodeId;
		[self->_editor wrote:query];
	}];
	return YES;
}

/* The object type of a node: its own, or its role's player. */
- (ORMObjectType *)typeOfQueryNode:(ORMQueryPart *)node
{
	if (node.roleId != nil) {
		ORMRole *role = [_editor.model elementWithId:node.roleId];
		return [role isKindOfClass:[ORMRole class]] ? role.player : nil;
	}
	ORMObjectType *type = [_editor.model elementWithId:node.ref];
	return [type isKindOfClass:[ORMObjectType class]] ? type : nil;
}

- (NSString *)addStepTo:(NSString *)nodeId through:(NSString *)roleId reason:(NSString **)reason
{
	ORMQueryPart *node = [self part:nodeId step:NO];
	ORMObjectType *type = [self typeOfQueryNode:node];
	ORMRole *entry = [_editor.model elementWithId:roleId];
	if (node == nil || node.isValue || type == nil || ![entry isKindOfClass:[ORMRole class]]) {
		if (reason != NULL) {
			*reason = node.isValue ? @"A value node is computed: no step goes from it."
			                       : @"A step goes from a node of a query through a role.";
		}
		return nil;
	}
	if (![[ORMQuery rolesFrom:type] containsObject:entry]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"%@ does not play that role.", type.name];
		}
		return nil;
	}
	ORMQueryPart *step = [[ORMQueryPart alloc] init];
	step.isStep = YES;
	step.identifier = ORMNewId();
	step.ref = entry.factType.identifier;
	step.roleId = entry.identifier;
	for (ORMRole *role in entry.factType.roles) {
		if (role != entry && !role.player.isImplicitBooleanValue) {
			ORMQueryPart *child = [[ORMQueryPart alloc] init];
			child.identifier = ORMNewId();
			child.roleId = role.identifier;
			[step addPart:child];
		}
	}
	ORMStoredQuery *query = [self queryOfPart:node];
	[_editor modelChange:@"Add Query Step" with:^{
		[node addPart:step];
		[self->_editor wrote:query];
	}];
	return step.identifier;
}

- (void)removeStep:(NSString *)stepId
{
	ORMQueryPart *step = [self part:stepId step:YES];
	if (step == nil) {
		return;
	}
	/* A calculation of a node the step takes away is of none. */
	ORMStoredQuery *query = [self queryOfPart:step];
	BOOL takesOf = NO;
	for (ORMQueryPart *node in query.of != nil ? [step tree] : @[]) {
		takesOf = takesOf || (!node.isStep && [node.identifier isEqualToString:query.of]);
	}
	NSArray *using = [self valuesIn:query using:[step tree]];
	[_editor modelChange:@"Remove Query Step" with:^{
		[step detach];
		for (ORMQueryPart *value in using) {
			[value detach];
		}
		if (takesOf) {
			query.of = nil;
		}
		[self->_editor wrote:query];
	}];
}

/* The query's value nodes that use one of the parts, or a value node that
 * does, outside them. */
- (NSArray<ORMQueryPart *> *)valuesIn:(ORMStoredQuery *)query using:(NSArray<ORMQueryPart *> *)parts
{
	NSMutableSet *gone = [NSMutableSet set];
	for (ORMQueryPart *part in parts) {
		[gone addObject:part.identifier ?: @""];
	}
	NSMutableArray *using = [NSMutableArray array];
	for (BOOL more = YES; more;) {
		more = NO;
		for (ORMQueryPart *part in [query.root tree]) {
			if (!part.isValue || [gone containsObject:part.identifier ?: @""]) {
				continue;
			}
			ORMQueryExpression *expression = [ORMQueryExpression expressionWithCanonicalText:part.expression reason:NULL];
			for (NSString *used in [expression nodeIds]) {
				if ([gone containsObject:used] && ![using containsObject:part]) {
					[using addObject:part];
					[gone addObject:part.identifier ?: @""];
					more = YES;
				}
			}
		}
	}
	return using;
}

/* A change to a part of a query. */
- (void)change:(NSString *)name part:(ORMQueryPart *)part with:(void (^)(void))change
{
	ORMStoredQuery *query = [self queryOfPart:part];
	[_editor modelChange:name with:^{
		change();
		[self->_editor wrote:query];
	}];
}

- (void)setProjected:(BOOL)projected ofNode:(NSString *)nodeId
{
	ORMQueryPart *node = [self part:nodeId step:NO];
	if (node == nil || ORMBoolValue(node.projected, NO) == projected) {
		return;
	}
	[self change:projected ? @"List in Query" : @"Do Not List in Query" part:node with:^{
		node.projected = projected ? @"true" : nil;
	}];
}

- (BOOL)setCondition:(NSString *)comparison value:(NSString *)value ofNode:(NSString *)nodeId reason:(NSString **)reason
{
	ORMQueryPart *node = [self part:nodeId step:NO];
	if (node == nil) {
		if (reason != NULL) {
			*reason = @"There is no such node.";
		}
		return NO;
	}
	if (comparison != nil && ![ORMQueryComparisons() containsObject:comparison]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"A condition compares with %@.",
			                                     [ORMQueryComparisons() componentsJoinedByString:@", "]];
		}
		return NO;
	}
	[self change:@"Set Query Condition" part:node with:^{
		node.comparison = comparison;
		node.value = comparison != nil ? (value ?: @"") : nil;
		node.compareTo = nil;
	}];
	return YES;
}

- (BOOL)setCondition:(NSString *)comparison
              toNode:(NSString *)otherNodeId
              ofNode:(NSString *)nodeId
              reason:(NSString **)reason
{
	ORMQueryPart *node = [self part:nodeId step:NO];
	ORMQueryPart *other = [self part:otherNodeId step:NO];
	if (node == nil || other == nil || node == other || [self queryOfPart:node] != [self queryOfPart:other]) {
		if (reason != NULL) {
			*reason = @"A condition compares a node with another of the same query.";
		}
		return NO;
	}
	if (![ORMQueryComparisons() containsObject:comparison ?: @""]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"A condition compares with %@.",
			                                     [ORMQueryComparisons() componentsJoinedByString:@", "]];
		}
		return NO;
	}
	ORMObjectType *type = [self typeOfQueryNode:node];
	ORMObjectType *otherType = [self typeOfQueryNode:other];
	if (type == nil || type != otherType) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"%@ is compared with another %@.", type.name, type.name];
		}
		return NO;
	}
	[self change:@"Set Query Condition" part:node with:^{
		node.comparison = comparison;
		node.value = nil;
		node.compareTo = otherNodeId;
	}];
	return YES;
}

- (void)setLabel:(NSString *)label ofNode:(NSString *)nodeId
{
	ORMQueryPart *node = [self part:nodeId step:NO];
	NSString *value = [label length] > 0 ? label : nil;
	if (node == nil || [node.label ?: @"" isEqualToString:value ?: @""]) {
		return;
	}
	[self change:@"Set Query Label" part:node with:^{
		node.label = value;
	}];
}

- (void)setCombinesWithOr:(BOOL)flag ofNode:(NSString *)nodeId
{
	ORMQueryPart *node = [self part:nodeId step:NO];
	if (node == nil || [node.combine isEqualToString:@"Or"] == flag) {
		return;
	}
	[self change:@"Set Query Alternatives" part:node with:^{
		node.combine = flag ? @"Or" : nil;
	}];
}

- (void)setOperator:(ORMQueryOperator)operatorKind ofStep:(NSString *)stepId
{
	ORMQueryPart *step = [self part:stepId step:YES];
	NSString *value = operatorKind == ORMQueryNot ? @"Not" : operatorKind == ORMQueryMaybe ? @"Maybe" : nil;
	if (step == nil || [step.operatorName ?: @"" isEqualToString:value ?: @""]) {
		return;
	}
	[self change:@"Set Query Operator" part:step with:^{
		step.operatorName = value;
	}];
}

- (BOOL)setCount:(NSString *)comparison
           value:(NSUInteger)value
          ofStep:(NSString *)stepId
          reason:(NSString **)reason
{
	ORMQueryPart *step = [self part:stepId step:YES];
	if (step == nil || (comparison != nil && ![ORMQueryComparisons() containsObject:comparison])) {
		if (reason != NULL) {
			*reason = step == nil ? @"There is no such step."
			                      : [NSString stringWithFormat:@"A count compares with %@.",
			                                                   [ORMQueryComparisons() componentsJoinedByString:@", "]];
		}
		return NO;
	}
	[self change:@"Set Query Count" part:step with:^{
		step.countComparison = comparison;
		step.countValueText = comparison != nil ? [NSString stringWithFormat:@"%lu", (unsigned long)value] : nil;
		step.aggregateName = nil;
		step.aggregateNodeId = nil;
		if (comparison == nil) {
			step.groupNodeId = nil;
			step.compareAggregate = nil;
			step.compareGroupNode = nil;
		}
	}];
	return YES;
}

- (BOOL)setAggregate:(ORMQueryAggregate)aggregate
              ofNode:(NSString *)nodeId
          comparison:(NSString *)comparison
               value:(NSString *)value
              ofStep:(NSString *)stepId
              reason:(NSString **)reason
{
	ORMQueryPart *step = [self part:stepId step:YES];
	ORMQueryPart *node = nodeId != nil ? [self part:nodeId step:NO] : nil;
	/* The node is one of the step's or below them. */
	BOOL below = node == nil;
	for (ORMQueryPart *at = [node parent]; at != nil && !below; at = [at parent]) {
		below = at == step;
	}
	if (step == nil || !below || (comparison != nil && ![ORMQueryComparisons() containsObject:comparison])) {
		if (reason != NULL) {
			*reason = step == nil ? @"There is no such step."
				: !below ? @"An aggregate is of a node the step reaches."
				         : [NSString stringWithFormat:@"An aggregate compares with %@.",
				                                      [ORMQueryComparisons() componentsJoinedByString:@", "]];
		}
		return NO;
	}
	ORMObjectType *type = node != nil ? [self typeOfQueryNode:node] : nil;
	ORMObjectType *valued = [type valueType];
	if ((aggregate == ORMQueryTotal || aggregate == ORMQueryAverage) && type != nil
	    && ![valued.dataType isNumeric]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"A total or an average is of numbers; %@ is not one.", type.name];
		}
		return NO;
	}
	[self change:@"Set Query Aggregate" part:step with:^{
		step.countComparison = comparison;
		step.countValueText = comparison != nil ? (value ?: @"") : nil;
		step.aggregateName = comparison != nil && aggregate != ORMQueryCount
			? [ORMQueryAggregateNames() objectAtIndex:(NSUInteger)aggregate] : nil;
		step.aggregateNodeId = comparison != nil ? nodeId : nil;
	}];
	return YES;
}

/* Whether the node is the step's parent or above it. */
static BOOL
ORMIsAbove(ORMQueryPart *node, ORMQueryPart *step)
{
	for (ORMQueryPart *at = [step parent]; at != nil; at = [at parent]) {
		if (at == node) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)setGroupNode:(NSString *)nodeId ofStep:(NSString *)stepId reason:(NSString **)reason
{
	ORMQueryPart *step = [self part:stepId step:YES];
	ORMQueryPart *node = nodeId != nil ? [self part:nodeId step:NO] : nil;
	if (step == nil || (nodeId != nil && (node == nil || !ORMIsAbove(node, step)))) {
		if (reason != NULL) {
			*reason = step == nil ? @"There is no such step." : @"An aggregate is for a node above its step.";
		}
		return NO;
	}
	/* The parent is the default: said by nothing. */
	NSString *value = node != nil && node != [step parent] ? nodeId : nil;
	if ([step.groupNodeId ?: @"" isEqualToString:value ?: @""]) {
		return YES;
	}
	[self change:@"Set Query Aggregate Group" part:step with:^{
		step.groupNodeId = value;
	}];
	return YES;
}

- (BOOL)setComparedAggregate:(ORMQueryAggregate)aggregate
                       group:(NSString *)nodeId
                      ofStep:(NSString *)stepId
                      reason:(NSString **)reason
{
	ORMQueryPart *step = [self part:stepId step:YES];
	ORMQueryPart *node = nodeId != nil ? [self part:nodeId step:NO] : nil;
	if (step == nil || step.countComparison == nil || (nodeId != nil && (node == nil || !ORMIsAbove(node, step)))) {
		if (reason != NULL) {
			*reason = step == nil ? @"There is no such step."
				: step.countComparison == nil ? @"The step has no aggregate to compare."
				                    : @"The aggregate compared with is for a node above the step.";
		}
		return NO;
	}
	[self change:@"Set Query Compared Aggregate" part:step with:^{
		step.compareAggregate = nodeId != nil ? [ORMQueryAggregateNames() objectAtIndex:(NSUInteger)aggregate] : nil;
		step.compareGroupNode = nodeId;
	}];
	return YES;
}

- (void)setSortOrder:(ORMQuerySort)order ofNode:(NSString *)nodeId
{
	ORMQueryPart *node = [self part:nodeId step:NO];
	NSString *value = order == ORMQueryAscending ? @"Ascending" : order == ORMQueryDescending ? @"Descending" : nil;
	if (node == nil || [node.sort ?: @"" isEqualToString:value ?: @""]) {
		return;
	}
	[self change:@"Set Query Sort" part:node with:^{
		node.sort = value;
	}];
}

#pragma mark Value nodes

/* What a function does not take, in the expression: an operand of
 * arithmetic that is not a number; nil where each is. */
static ORMQueryExpression *
ORMNotANumberIn(ORMQueryExpression *expression, NSSet *numeric)
{
	if (expression.kind != ORMQueryExpressionFunction) {
		return nil;
	}
	BOOL any = [expression.function isEqualToString:@"coalesce"] || [expression.function isEqualToString:@"min"]
		|| [expression.function isEqualToString:@"max"];
	for (ORMQueryExpression *argument in expression.arguments) {
		ORMQueryExpression *inner = ORMNotANumberIn(argument, numeric);
		if (inner != nil) {
			return inner;
		}
		if (!any && ![argument isNumericGivenNumericNodes:numeric]) {
			return argument;
		}
	}
	return nil;
}

/* Whether the name is one a value node can have: a word, as an expression
 * names a node. */
static BOOL
ORMIsValueName(NSString *name)
{
	ORMQueryExpression *read = [ORMQueryExpression expressionWithText:name designations:@{ name ?: @"": @"_" } reason:NULL];
	return [name length] > 0 && read.kind == ORMQueryExpressionNode;
}

/* The expression said, read among the query's nodes before the point (the
 * first n of its nodes), and the value type it is of: the one given, or the
 * first node it uses'. nil and why where it is none, uses a node not
 * before it, does arithmetic of what is not a number, or is of a type that
 * is no value type. */
- (ORMQueryExpression *)expression:(NSString *)text
                           inQuery:(ORMQuery *)view
                            before:(NSUInteger)end
                              type:(ORMObjectType **)type
                            reason:(NSString **)reason
{
	NSArray *nodes = [view nodes];
	NSArray *before = [nodes subarrayWithRange:NSMakeRange(0, MIN(end, [nodes count]))];
	NSString *why = nil;
	ORMQueryExpression *expression = [ORMQueryExpression expressionWithText:text
	                                                           designations:[view nodeIdsByDesignationAmong:before]
	                                                                 reason:&why];
	NSMutableSet *numeric = [NSMutableSet set];
	NSMutableDictionary *byId = [NSMutableDictionary dictionary];
	for (ORMQueryNode *node in before) {
		[byId setObject:node forKey:node.identifier ?: @""];
		if ([node isNumeric]) {
			[numeric addObject:node.identifier ?: @""];
		}
	}
	ORMQueryExpression *odd = expression != nil ? ORMNotANumberIn(expression, numeric) : nil;
	ORMQueryNode *first = [byId objectForKey:[[expression nodeIds] firstObject] ?: @""];
	ORMObjectType *of = *type ?: [first.objectType valueType];
	if (expression == nil) {
		why = [NSString stringWithFormat:@"\"%@\" is no value: %@.", text ?: @"", why];
	} else if (odd != nil) {
		why = [NSString stringWithFormat:@"%@ is not a number, and arithmetic is of numbers.",
		                                 [odd textWithDesignations:[view designationsById]]];
	} else if (of == nil || of.kind != ORMValueType) {
		why = of == nil ? @"A value node is of a value type: name one." : [NSString stringWithFormat:@"%@ is no value type.", of.name];
	} else if ([expression isNumericGivenNumericNodes:numeric] && ![of.dataType isNumeric]) {
		why = [NSString stringWithFormat:@"It computes a number, and %@ is not one.", of.name];
	}
	if (why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return nil;
	}
	*type = of;
	return expression;
}

- (NSString *)addValueNamed:(NSString *)name
                         to:(NSString *)nodeId
                 expression:(NSString *)text
                       type:(NSString *)valueTypeId
                     reason:(NSString **)reason
{
	ORMQueryPart *node = [self part:nodeId step:NO];
	ORMStoredQuery *query = [self queryOfPart:node];
	ORMQuery *view = query != nil ? [ORMQuery queryOf:query model:_editor.model] : nil;
	ORMObjectType *type = valueTypeId != nil ? [_editor.model elementWithId:valueTypeId] : nil;
	NSString *why = nil;
	if (node == nil || node.isValue || view == nil) {
		why = node.isValue ? @"A value node is under a node a step reaches, or the root." : @"There is no such node.";
	} else if (!ORMIsValueName(name) || [[ORMQueryExpression functionArities] objectForKey:name] != nil) {
		why = [NSString stringWithFormat:@"\"%@\" is no name for a value: a word, not a function's.", name ?: @""];
	} else if ([[view designationsById] allKeysForObject:name].count > 0) {
		why = [NSString stringWithFormat:@"A node of the query is %@ already.", name];
	} else if (valueTypeId != nil && ![type isKindOfClass:[ORMObjectType class]]) {
		why = @"There is no such value type.";
	}
	ORMQueryExpression *expression = nil;
	if (why == nil) {
		/* After what the node's steps reach and its value nodes. */
		ORMQueryNode *under = nil;
		for (ORMQueryNode *each in [view nodes]) {
			under = [each.identifier isEqualToString:nodeId] ? each : under;
		}
		NSMutableArray *subtree = [NSMutableArray array];
		[view collect:under into:subtree];
		NSUInteger end = [[view nodes] indexOfObjectIdenticalTo:under] + [subtree count];
		expression = [self expression:text inQuery:view before:end type:&type reason:&why];
	}
	if (why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return nil;
	}
	ORMQueryPart *value = [[ORMQueryPart alloc] init];
	value.isValue = YES;
	value.identifier = ORMNewId();
	value.name = name;
	value.expression = [expression canonicalText];
	value.ref = type.identifier;
	[_editor modelChange:@"Add Query Value" with:^{
		[node addPart:value];
		[self->_editor wrote:query];
	}];
	return value.identifier;
}

- (BOOL)setExpression:(NSString *)text ofValue:(NSString *)valueId reason:(NSString **)reason
{
	ORMQueryPart *value = [self part:valueId step:NO];
	ORMStoredQuery *query = [self queryOfPart:value];
	ORMQuery *view = query != nil && value.isValue ? [ORMQuery queryOf:query model:_editor.model] : nil;
	ORMObjectType *type = [_editor.model elementWithId:value.ref ?: @""];
	NSUInteger end = NSNotFound;
	NSArray *nodes = [view nodes];
	for (NSUInteger i = 0; i < [nodes count]; i++) {
		end = [[[nodes objectAtIndex:i] identifier] isEqualToString:valueId] ? i : end;
	}
	NSString *why = view == nil || end == NSNotFound ? @"There is no such value node." : nil;
	ORMQueryExpression *expression = why == nil ? [self expression:text inQuery:view before:end type:&type reason:&why] : nil;
	if (expression == nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return NO;
	}
	NSString *canonical = [expression canonicalText];
	if (![canonical isEqualToString:value.expression]) {
		[self change:@"Set Query Value" part:value with:^{
			value.expression = canonical;
		}];
	}
	return YES;
}

- (BOOL)removeValue:(NSString *)valueId reason:(NSString **)reason
{
	ORMQueryPart *value = [self part:valueId step:NO];
	ORMStoredQuery *query = [self queryOfPart:value];
	NSString *why = query == nil || !value.isValue ? @"There is no such value node." : nil;
	for (ORMQueryPart *part in why == nil ? [query.root tree] : @[]) {
		ORMQueryExpression *expression = part.isValue && part != value
			? [ORMQueryExpression expressionWithCanonicalText:part.expression reason:NULL] : nil;
		BOOL uses = [[expression nodeIds] containsObject:valueId];
		for (NSString *key in ORMNodeReferences()) {
			uses = uses || [[part valueForKey:key] isEqualToString:valueId];
		}
		if (uses) {
			why = [NSString stringWithFormat:@"%@ is used by another node of the query.", value.name];
			break;
		}
	}
	if (why == nil && [query.of isEqualToString:valueId]) {
		why = [NSString stringWithFormat:@"%@ is what the query calculates.", value.name];
	}
	if (why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return NO;
	}
	[self change:@"Remove Query Value" part:value with:^{
		[value detach];
	}];
	return YES;
}

@end
