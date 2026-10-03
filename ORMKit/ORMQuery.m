/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQuery.h"
#import "ORMEditorPriv.h"
#import "ORMXML.h"
#import <objc/runtime.h>

#define Q ORMQueryNamespace

static NSArray<NSString *> *
ORMQueryComparisons(void)
{
	return @[ @"=", @"<>", @"<", @"<=", @">", @">=" ];
}

/* The text with each {n} given by the block: nil leaves it as it is. */
static NSString *
ORMRewritePlaceholders(NSString *text, NSString * (^replace)(NSUInteger index))
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
			NSString *replacement = replace((NSUInteger)index);
			[out appendString:replacement ?: [text substringWithRange:NSMakeRange(at, [scanner scanLocation] - at)]];
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
@property (nonatomic, readwrite, copy) NSString *comparison;
@property (nonatomic, readwrite, copy) NSString *value;
@property (nonatomic, readwrite, weak) ORMQueryNode *comparedNode;
@property (nonatomic, copy) NSString *comparedNodeId;
@property (nonatomic, readwrite, copy) NSString *label;
@property (nonatomic, readwrite, copy) NSArray<ORMQueryStep *> *steps;
@property (nonatomic, readwrite) BOOL combinesWithOr;
@property (nonatomic, readwrite) ORMQuerySort sortOrder;
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
@end

@interface ORMQuery ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, strong) ORMQueryNode *root;
@property (nonatomic, readwrite) BOOL isComplete;
@end

@implementation ORMQueryNode

- (BOOL)isNumeric
{
	ORMObjectType *type = self.objectType.kind == ORMValueType ? self.objectType
	                                                           : self.objectType.referenceModeValueType;
	return type.dataType.family == ORMDataTypeNumeric;
}

- (NSString *)designation
{
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

+ (NSXMLElement *)containerIn:(NSXMLDocument *)document
{
	return ORMChild([document rootElement], Q, @"Queries");
}

+ (NSArray<ORMQuery *> *)queriesInModel:(ORMModel *)model
{
	NSMutableArray *queries = [NSMutableArray array];
	NSXMLDocument *document = [model.modelElement rootDocument];
	for (NSXMLElement *element in ORMChildren([self containerIn:document], Q, @"Query")) {
		ORMQuery *query = [self queryOf:element model:model];
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

+ (ORMQuery *)queryOf:(NSXMLElement *)element model:(ORMModel *)model
{
	ORMQuery *query = [[ORMQuery alloc] init];
	query.identifier = ORMAttribute(element, @"id");
	query.name = ORMAttribute(element, @"Name") ?: @"Query";
	query.isComplete = YES;
	NSXMLElement *rootElement = ORMChild(element, Q, @"Node");
	ORMObjectType *type = [model elementWithId:ORMRef(rootElement)];
	if (![type isKindOfClass:[ORMObjectType class]]) {
		query.isComplete = NO;
		return query;
	}
	query.root = [query nodeOf:rootElement type:type role:nil model:model];
	/* What a condition compares with, now every node is read. */
	NSArray *nodes = [query nodes];
	for (ORMQueryNode *node in nodes) {
		for (ORMQueryNode *other in node.comparedNodeId != nil ? nodes : @[]) {
			if ([other.identifier isEqualToString:node.comparedNodeId]) {
				node.comparedNode = other;
			}
		}
		/* What each step aggregates: its own node unless it says. */
		for (ORMQueryStep *step in node.steps) {
			step.aggregateNode = [step.nodes firstObject];
			for (ORMQueryNode *other in step.aggregateNodeId != nil ? nodes : @[]) {
				if ([other.identifier isEqualToString:step.aggregateNodeId]) {
					step.aggregateNode = other;
				}
			}
		}
		/* What it was compared with is gone: so is the condition. */
		if (node.comparedNodeId != nil && node.comparedNode == nil) {
			node.comparison = nil;
			query.isComplete = NO;
		}
	}
	return query;
}

- (ORMQueryNode *)nodeOf:(NSXMLElement *)element type:(ORMObjectType *)type role:(ORMRole *)role model:(ORMModel *)model
{
	ORMQueryNode *node = [[ORMQueryNode alloc] init];
	node.identifier = ORMAttribute(element, @"id");
	node.objectType = type;
	node.role = role;
	node.isProjected = ORMBoolAttribute(element, @"Projected", NO);
	node.comparison = ORMAttribute(element, @"Comparison");
	node.value = ORMAttribute(element, @"Value");
	node.comparedNodeId = ORMAttribute(element, @"CompareTo");
	node.label = [ORMAttribute(element, @"Label") length] > 0 ? ORMAttribute(element, @"Label") : nil;
	node.combinesWithOr = [ORMAttribute(element, @"Combine") isEqualToString:@"Or"];
	NSString *sort = ORMAttribute(element, @"Sort");
	node.sortOrder = [sort isEqualToString:@"Ascending"] ? ORMQueryAscending
		: [sort isEqualToString:@"Descending"] ? ORMQueryDescending : ORMQueryUnsorted;
	NSMutableArray *steps = [NSMutableArray array];
	for (NSXMLElement *stepElement in ORMChildren(element, Q, @"Step")) {
		ORMQueryStep *step = [self stepOf:stepElement parent:node model:model];
		if (step != nil) {
			[steps addObject:step];
		} else {
			self.isComplete = NO;
		}
	}
	node.steps = steps;
	return node;
}

- (ORMQueryStep *)stepOf:(NSXMLElement *)element parent:(ORMQueryNode *)parent model:(ORMModel *)model
{
	ORMFactType *fact = [model elementWithId:ORMRef(element)];
	ORMRole *entry = [model elementWithId:ORMAttribute(element, @"Role")];
	if (![fact isKindOfClass:[ORMFactType class]] || ![entry isKindOfClass:[ORMRole class]] || entry.factType != fact) {
		return nil;
	}
	ORMQueryStep *step = [[ORMQueryStep alloc] init];
	step.identifier = ORMAttribute(element, @"id");
	step.factType = fact;
	step.entryRole = entry;
	step.parent = parent;
	NSString *operator = ORMAttribute(element, @"Operator");
	step.operatorKind = [operator isEqualToString:@"Not"] ? ORMQueryNot
		: [operator isEqualToString:@"Maybe"] ? ORMQueryMaybe : ORMQueryAnd;
	step.countComparison = ORMAttribute(element, @"Count");
	step.aggregateValue = ORMAttribute(element, @"CountValue");
	step.countValue = (NSUInteger)[step.aggregateValue integerValue];
	NSUInteger aggregate = [ORMQueryAggregateNames() indexOfObject:ORMAttribute(element, @"Aggregate") ?: @"Count"];
	step.aggregate = aggregate != NSNotFound ? (ORMQueryAggregate)aggregate : ORMQueryCount;
	step.aggregateNodeId = ORMAttribute(element, @"AggregateNode");
	NSMutableArray *nodes = [NSMutableArray array];
	for (NSXMLElement *nodeElement in ORMChildren(element, Q, @"Node")) {
		ORMRole *role = [model elementWithId:ORMAttribute(nodeElement, @"Role")];
		if (![role isKindOfClass:[ORMRole class]] || role.factType != fact || role == entry || role.player == nil) {
			self.isComplete = NO;
			continue;
		}
		ORMQueryNode *node = [self nodeOf:nodeElement type:role.player role:role model:model];
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
			if (role.factType.kind == ORMFactTypeImplied || role.player.isImplicitBooleanValue) {
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
	NSArray *nodeRoles = [step.nodes valueForKey:@"role"];
	NSString * (^place)(ORMRole *) = ^NSString *(ORMRole *role) {
		if (role == step.entryRole) {
			return @"{0}";
		}
		NSUInteger index = [nodeRoles indexOfObjectIdenticalTo:role];
		return index != NSNotFound ? [NSString stringWithFormat:@"{%lu}", (unsigned long)index + 1] : @"";
	};
	if ([step isSubtyping]) {
		return @"is {1}";
	}
	ORMReadingOrder *chosen = nil;
	for (ORMReadingOrder *order in step.factType.readingOrders) {
		if ([order.roles firstObject] == step.entryRole && [order.readings count] > 0
		    && [[[order.readings firstObject] text] hasPrefix:@"{0}"]) {
			chosen = order;
			break;
		}
	}
	ORMReadingOrder *order = chosen ?: [step.factType.readingOrders firstObject];
	NSString *text = [[order.readings firstObject] text];
	if (text == nil) {
		return @"";
	}
	NSString *rewritten = ORMRewritePlaceholders(text, ^NSString *(NSUInteger index) {
		return index < [order.roles count] ? place([order.roles objectAtIndex:index]) : nil;
	});
	/* Read from the entry role: the node above is the subject. */
	if (chosen != nil && [rewritten hasPrefix:@"{0}"]) {
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
		value = [NSString stringWithFormat:@"'%@'", value];
	}
	return [NSString stringWithFormat:@" %@ %@", node.comparison, value];
}

- (NSString *)nodeText:(ORMQueryNode *)node
{
	NSString *sort = node.sortOrder == ORMQueryAscending ? @" ↑" : node.sortOrder == ORMQueryDescending ? @" ↓" : @"";
	return [NSString stringWithFormat:@"%@%@%@%@", node.isProjected ? @"✓" : @"", [node designation],
	                                  [self conditionText:node], sort];
}

- (NSString *)outlineText
{
	if (self.root == nil) {
		return @"";
	}
	NSMutableString *out = [NSMutableString stringWithFormat:@"%@\n", [self nodeText:self.root]];
	[self outlineSteps:self.root indent:1 into:out];
	return out;
}

- (void)outlineSteps:(ORMQueryNode *)node indent:(NSUInteger)indent into:(NSMutableString *)out
{
	NSString *pad = [@"" stringByPaddingToLength:indent * 2 withString:@" " startingAtIndex:0];
	BOOL first = YES;
	for (ORMQueryStep *step in node.steps) {
		NSString *reading = ORMRewritePlaceholders([ORMQuery readingOfStep:step], ^NSString *(NSUInteger index) {
			if (index == 0) {
				return [NSString stringWithFormat:@"that %@", node.objectType.name];
			}
			return index <= [step.nodes count] ? [self nodeText:[step.nodes objectAtIndex:index - 1]] : nil;
		});
		NSString *operator = step.operatorKind == ORMQueryNot ? @"not " : step.operatorKind == ORMQueryMaybe ? @"maybe "
		                                                                                                       : @"";
		[out appendFormat:@"%@+ %@%@%@\n", pad, node.combinesWithOr && !first ? @"or " : @"", operator, reading];
		first = NO;
		if (step.countComparison != nil && step.aggregateNode != nil) {
			[out appendFormat:@"%@  + %@(%@) for %@ %@ %@\n", pad, [ORMQuery nameOfAggregate:step.aggregate],
			                  [step.aggregateNode designation], [node designation], step.countComparison,
			                  step.aggregateValue ?: @""];
		}
		for (ORMQueryNode *child in step.nodes) {
			if ([child.steps count] == 0) {
				continue;
			}
			if (child != [step.nodes firstObject]) {
				[out appendFormat:@"%@  %@:\n", pad, child.objectType.name];
			}
			[self outlineSteps:child indent:indent + 1 into:out];
		}
	}
}

#pragma mark As logic

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
		[variables setObject:variable forKey:node.identifier];
	}
	ORMFormula *formula = [self formulaOf:self.root variables:variables];
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMQueryNode *node in [self projectedNodes]) {
		[columns addObject:[variables objectForKey:node.identifier]];
	}
	if ([columns count] == 0) {
		[columns addObject:[variables objectForKey:self.root.identifier]];
	}
	ORMRelation *relation = [ORMRelation relationWithFormula:formula columns:columns];
	objc_setAssociatedObject(relation, @selector(variablesOfRelation:), variables, OBJC_ASSOCIATION_RETAIN);
	return relation;
}

- (NSDictionary<NSString *, ORMVariable *> *)variablesOfRelation:(ORMRelation *)relation
{
	return objc_getAssociatedObject(relation, @selector(variablesOfRelation:));
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
		NSString *function = [@[ @"count", @"total", @"average", @"maximum", @"minimum" ]
			objectAtIndex:(NSUInteger)step.aggregate];
		ORMTerm *aggregate = [ORMTerm termWithFunction:function
		                                     arguments:@[ [ORMTerm termWithVariable:[variables
		                                                                                objectForKey:step.aggregateNode
		                                                                                                 .identifier]] ]
		                                     aggregate:YES];
		[conjuncts addObject:[ORMFormula compare:step.countComparison
		                                operands:@[ aggregate, [ORMTerm termWithConstant:step.aggregateValue ?: @""] ]]];
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


- (NSXMLElement *)queriesContainer
{
	NSXMLElement *root = [_editor.document rootElement];
	NSXMLElement *container = ORMChild(root, Q, @"Queries");
	if (container == nil) {
		container = ORMNewElement(_editor.document, Q, @"Queries");
		[root addChild:container];
	}
	return container;
}

/* The query's element of that name and id. */
- (NSXMLElement *)queryElement:(NSString *)identifier named:(NSString *)local
{
	if (identifier == nil) {
		return nil;
	}
	for (NSXMLElement *element in ORMDescendants(ORMChild([_editor.document rootElement], Q, @"Queries"), Q, local)) {
		if ([ORMAttribute(element, @"id") isEqualToString:identifier]) {
			return element;
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
	__block NSString *created = nil;
	[_editor change:@"Add Query" with:^{
		NSXMLElement *query = ORMNewElementWithId(_editor.document, Q, @"Query", nil);
		ORMSetAttribute(query, @"Name", [name length] > 0 ? name : [NSString stringWithFormat:@"%@ Query", type.name]);
		NSXMLElement *root = ORMNewElementWithId(_editor.document, Q, @"Node", nil);
		ORMSetAttribute(root, @"ref", type.identifier);
		ORMSetBoolAttribute(root, @"Projected", YES, NO);
		[query addChild:root];
		[[self queriesContainer] addChild:query];
		created = ORMAttribute(query, @"id");
	}];
	return created;
}

- (void)removeQuery:(NSString *)queryId
{
	NSXMLElement *query = [self queryElement:queryId named:@"Query"];
	if (query == nil) {
		return;
	}
	[_editor change:@"Remove Query" with:^{
		NSXMLElement *container = (NSXMLElement *)[query parent];
		[query detach];
		ORMPruneIfEmpty(container);
	}];
}

- (BOOL)renameQuery:(NSString *)queryId to:(NSString *)name reason:(NSString **)reason
{
	NSXMLElement *query = [self queryElement:queryId named:@"Query"];
	if (query == nil || [name length] == 0) {
		if (reason != NULL) {
			*reason = query == nil ? @"There is no such query." : @"A query needs a name.";
		}
		return NO;
	}
	if (![ORMAttribute(query, @"Name") isEqualToString:name]) {
		[_editor change:@"Rename Query" with:^{
			ORMSetAttribute(query, @"Name", name);
		}];
	}
	return YES;
}

/* The object type of a node: its own, or its role's player. */
- (ORMObjectType *)typeOfQueryNode:(NSXMLElement *)node
{
	NSString *roleId = ORMAttribute(node, @"Role");
	if (roleId != nil) {
		ORMRole *role = [_editor.model elementWithId:roleId];
		return [role isKindOfClass:[ORMRole class]] ? role.player : nil;
	}
	ORMObjectType *type = [_editor.model elementWithId:ORMRef(node)];
	return [type isKindOfClass:[ORMObjectType class]] ? type : nil;
}

- (NSString *)addStepTo:(NSString *)nodeId through:(NSString *)roleId reason:(NSString **)reason
{
	NSXMLElement *node = [self queryElement:nodeId named:@"Node"];
	ORMObjectType *type = [self typeOfQueryNode:node];
	ORMRole *entry = [_editor.model elementWithId:roleId];
	if (node == nil || type == nil || ![entry isKindOfClass:[ORMRole class]]) {
		if (reason != NULL) {
			*reason = @"A step goes from a node of a query through a role.";
		}
		return nil;
	}
	if (![[ORMQuery rolesFrom:type] containsObject:entry]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"%@ does not play that role.", type.name];
		}
		return nil;
	}
	NSArray *others = [entry.factType.roles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(
		ORMRole *role, NSDictionary *bindings) {
		(void)bindings;
		return role != entry && !role.player.isImplicitBooleanValue;
	}]];
	__block NSString *created = nil;
	[_editor change:@"Add Query Step" with:^{
		NSXMLElement *step = ORMNewElementWithId(_editor.document, Q, @"Step", nil);
		ORMSetAttribute(step, @"ref", entry.factType.identifier);
		ORMSetAttribute(step, @"Role", entry.identifier);
		for (ORMRole *role in others) {
			NSXMLElement *child = ORMNewElementWithId(_editor.document, Q, @"Node", nil);
			ORMSetAttribute(child, @"Role", role.identifier);
			[step addChild:child];
		}
		[node addChild:step];
		created = ORMAttribute(step, @"id");
	}];
	return created;
}

- (void)removeStep:(NSString *)stepId
{
	NSXMLElement *step = [self queryElement:stepId named:@"Step"];
	if (step == nil) {
		return;
	}
	[_editor change:@"Remove Query Step" with:^{
		[step detach];
	}];
}

- (void)setProjected:(BOOL)projected ofNode:(NSString *)nodeId
{
	NSXMLElement *node = [self queryElement:nodeId named:@"Node"];
	if (node == nil || ORMBoolAttribute(node, @"Projected", NO) == projected) {
		return;
	}
	[_editor change:projected ? @"List in Query" : @"Do Not List in Query" with:^{
		ORMSetBoolAttribute(node, @"Projected", projected, NO);
	}];
}

- (BOOL)setCondition:(NSString *)comparison value:(NSString *)value ofNode:(NSString *)nodeId reason:(NSString **)reason
{
	NSXMLElement *node = [self queryElement:nodeId named:@"Node"];
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
	[_editor change:@"Set Query Condition" with:^{
		ORMSetAttribute(node, @"Comparison", comparison);
		ORMSetAttribute(node, @"Value", comparison != nil ? (value ?: @"") : nil);
		ORMSetAttribute(node, @"CompareTo", nil);
	}];
	return YES;
}

/* The query element a node element is in. */
- (NSXMLElement *)queryOfNode:(NSXMLElement *)node
{
	NSXMLNode *at = node;
	while (at != nil && !(ORMIs(at, Q, @"Query"))) {
		at = [at parent];
	}
	return (NSXMLElement *)at;
}

- (BOOL)setCondition:(NSString *)comparison
              toNode:(NSString *)otherNodeId
              ofNode:(NSString *)nodeId
              reason:(NSString **)reason
{
	NSXMLElement *node = [self queryElement:nodeId named:@"Node"];
	NSXMLElement *other = [self queryElement:otherNodeId named:@"Node"];
	if (node == nil || other == nil || node == other || [self queryOfNode:node] != [self queryOfNode:other]) {
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
	[_editor change:@"Set Query Condition" with:^{
		ORMSetAttribute(node, @"Comparison", comparison);
		ORMSetAttribute(node, @"Value", nil);
		ORMSetAttribute(node, @"CompareTo", otherNodeId);
	}];
	return YES;
}

- (void)setLabel:(NSString *)label ofNode:(NSString *)nodeId
{
	NSXMLElement *node = [self queryElement:nodeId named:@"Node"];
	NSString *value = [label length] > 0 ? label : nil;
	if (node == nil || [ORMAttribute(node, @"Label") ?: @"" isEqualToString:value ?: @""]) {
		return;
	}
	[_editor change:@"Set Query Label" with:^{
		ORMSetAttribute(node, @"Label", value);
	}];
}

- (void)setCombinesWithOr:(BOOL)flag ofNode:(NSString *)nodeId
{
	NSXMLElement *node = [self queryElement:nodeId named:@"Node"];
	if (node == nil || [ORMAttribute(node, @"Combine") isEqualToString:@"Or"] == flag) {
		return;
	}
	[_editor change:@"Set Query Alternatives" with:^{
		ORMSetAttribute(node, @"Combine", flag ? @"Or" : nil);
	}];
}

- (void)setOperator:(ORMQueryOperator)operatorKind ofStep:(NSString *)stepId
{
	NSXMLElement *step = [self queryElement:stepId named:@"Step"];
	NSString *value = operatorKind == ORMQueryNot ? @"Not" : operatorKind == ORMQueryMaybe ? @"Maybe" : nil;
	if (step == nil || [ORMAttribute(step, @"Operator") ?: @"" isEqualToString:value ?: @""]) {
		return;
	}
	[_editor change:@"Set Query Operator" with:^{
		ORMSetAttribute(step, @"Operator", value);
	}];
}

- (BOOL)setCount:(NSString *)comparison
           value:(NSUInteger)value
          ofStep:(NSString *)stepId
          reason:(NSString **)reason
{
	NSXMLElement *step = [self queryElement:stepId named:@"Step"];
	if (step == nil || (comparison != nil && ![ORMQueryComparisons() containsObject:comparison])) {
		if (reason != NULL) {
			*reason = step == nil ? @"There is no such step."
			                      : [NSString stringWithFormat:@"A count compares with %@.",
			                                                   [ORMQueryComparisons() componentsJoinedByString:@", "]];
		}
		return NO;
	}
	[_editor change:@"Set Query Count" with:^{
		ORMSetAttribute(step, @"Count", comparison);
		ORMSetAttribute(step, @"CountValue",
		                comparison != nil ? [NSString stringWithFormat:@"%lu", (unsigned long)value] : nil);
		ORMSetAttribute(step, @"Aggregate", nil);
		ORMSetAttribute(step, @"AggregateNode", nil);
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
	NSXMLElement *step = [self queryElement:stepId named:@"Step"];
	NSXMLElement *node = nodeId != nil ? [self queryElement:nodeId named:@"Node"] : nil;
	/* The node is one of the step's or below them. */
	BOOL below = node == nil;
	for (NSXMLNode *at = [node parent]; at != nil && !below; at = [at parent]) {
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
	ORMObjectType *valued = type.kind == ORMValueType ? type : type.referenceModeValueType;
	if ((aggregate == ORMQueryTotal || aggregate == ORMQueryAverage) && type != nil
	    && valued.dataType.family != ORMDataTypeNumeric) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"A total or an average is of numbers; %@ is not one.", type.name];
		}
		return NO;
	}
	[_editor change:@"Set Query Aggregate" with:^{
		ORMSetAttribute(step, @"Count", comparison);
		ORMSetAttribute(step, @"CountValue", comparison != nil ? (value ?: @"") : nil);
		ORMSetAttribute(step, @"Aggregate", comparison != nil && aggregate != ORMQueryCount
		                                        ? [ORMQueryAggregateNames() objectAtIndex:(NSUInteger)aggregate] : nil);
		ORMSetAttribute(step, @"AggregateNode", comparison != nil ? nodeId : nil);
	}];
	return YES;
}

- (void)setSortOrder:(ORMQuerySort)order ofNode:(NSString *)nodeId
{
	NSXMLElement *node = [self queryElement:nodeId named:@"Node"];
	NSString *value = order == ORMQueryAscending ? @"Ascending" : order == ORMQueryDescending ? @"Descending" : nil;
	if (node == nil || [ORMAttribute(node, @"Sort") ?: @"" isEqualToString:value ?: @""]) {
		return;
	}
	[_editor change:@"Set Query Sort" with:^{
		ORMSetAttribute(node, @"Sort", value);
	}];
}

@end
