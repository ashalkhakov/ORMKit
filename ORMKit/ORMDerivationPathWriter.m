/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDerivationPathWriter.h"
#import "ORMXML.h"

#define CORE ORMCoreNamespace

/* The parameters of each function the path writer declares, by name; an
 * aggregate's one is its bag. */
static NSArray<NSString *> *
ORMParametersOf(NSString *function)
{
	static NSDictionary *parameters;
	if (parameters == nil) {
		NSArray *pair = @[ @"left", @"right" ];
		parameters = @{ @"add": pair, @"subtract": pair, @"multiply": pair, @"divide": pair, @"negate": @[ @"value" ],
			            @"abs": @[ @"value" ], @"round": @[ @"value", @"places" ], @"min": @[ @"first", @"second" ],
			            @"max": @[ @"first", @"second" ], @"coalesce": @[ @"first", @"second" ],
			            @"date": @[ @"moment" ], @"month": @[ @"moment" ], @"days": @[ @"from", @"to" ],
			            @"months": @[ @"from", @"to" ], @"minutes": @[ @"from", @"to" ],
			            @"addDays": @[ @"date", @"count" ], @"addMonths": @[ @"date", @"count" ], @"today": @[],
			            @"equals": pair, @"notEqual": pair, @"lessThan": pair, @"lessThanOrEqual": pair,
			            @"greaterThan": pair, @"greaterThanOrEqual": pair };
	}
	return [parameters objectForKey:function];
}

/* The boolean function of a comparison: "<" is lessThan. */
static NSString *
ORMComparisonFunction(NSString *comparison)
{
	NSDictionary *names = @{ @"=": @"equals", @"<>": @"notEqual", @"<": @"lessThan", @"<=": @"lessThanOrEqual",
		                     @">": @"greaterThan", @">=": @"greaterThanOrEqual" };
	return [names objectForKey:comparison ?: @""];
}

/* An expression's constant as NORMA's Constant holds it: text unquoted. */
static NSString *
ORMConstantValue(NSString *constant)
{
	if ([constant length] >= 2 && [constant hasPrefix:@"'"] && [constant hasSuffix:@"'"]) {
		NSString *inner = [constant substringWithRange:NSMakeRange(1, [constant length] - 2)];
		return [inner stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
	}
	return constant ?: @"";
}

/* A source, as an element under the given container: [local, id] for a
 * PathRoot, PathedRole or CalculatedValue, [@"Constant", value, id]. */
static NSXMLElement *
ORMSourceElement(NSXMLDocument *document, NSArray<NSString *> *source)
{
	NSString *local = [source firstObject];
	if ([local isEqualToString:@"Constant"]) {
		NSXMLElement *constant = ORMNewElementWithId(document, CORE, @"Constant", [source objectAtIndex:2]);
		NSXMLElement *value = ORMNewElement(document, CORE, @"Value");
		[value setStringValue:[source objectAtIndex:1]];
		[constant addChild:value];
		return constant;
	}
	return ORMNewRef(document, CORE, local, [source objectAtIndex:1]);
}

@implementation ORMDerivationPathWriter
{
	NSXMLDocument *_document;
	ORMQuery *_query;
	NSString *_why;
	/* Where each node is: its source, by node id. */
	NSMutableDictionary<NSString *, NSArray<NSString *> *> *_sources;
	/* The nodes under a not or an alternative, by id: what is calculated
	 * of them would hold of the whole path. */
	NSMutableSet<NSString *> *_scoped;
	/* The roots and pathed roles of the nodes of each label, by the first
	 * one's id, in order. */
	NSMutableDictionary<NSString *, NSMutableArray *> *_unified;
	NSMutableArray<NSString *> *_unifiedOrder;
	NSMutableArray<NSXMLElement *> *_calculations;
	NSMutableArray<NSString *> *_conditions;
	NSMutableDictionary<NSString *, NSXMLElement *> *_functions;
	NSMutableArray<NSString *> *_functionOrder;
}

- (instancetype)initWithDocument:(NSXMLDocument *)document
{
	if ((self = [super init])) {
		_document = document;
		_functions = [NSMutableDictionary dictionary];
		_functionOrder = [NSMutableArray array];
	}
	return self;
}

- (NSArray<NSXMLElement *> *)functions
{
	NSMutableArray *functions = [NSMutableArray array];
	for (NSString *key in _functionOrder) {
		[functions addObject:[_functions objectForKey:key]];
	}
	return functions;
}

/* An id of the query's, the same each time. */
- (NSString *)idOf:(NSString *)what
{
	return ORMStableId([NSString stringWithFormat:@"%@/%@", _query.identifier ?: @"", what]);
}

- (void)refuse:(NSString *)why
{
	_why = _why ?: why;
}

#pragma mark Functions

/* The function's id, declared: an aggregate's parameter a bag. */
- (NSString *)function:(NSString *)name bag:(BOOL)bag
{
	NSString *key = bag ? [name stringByAppendingString:@"/bag"] : name;
	NSString *identifier = ORMStableId([@"ORMKit function " stringByAppendingString:key]);
	if ([_functions objectForKey:key] != nil) {
		return identifier;
	}
	NSXMLElement *function = ORMNewElementWithId(_document, CORE, @"Function", identifier);
	ORMSetAttribute(function, @"Name", name);
	NSString *comparison = nil;
	for (NSString *symbol in @[ @"=", @"<>", @"<", @"<=", @">", @">=" ]) {
		comparison = [ORMComparisonFunction(symbol) isEqualToString:name] ? symbol : comparison;
	}
	if (comparison != nil) {
		ORMSetAttribute(function, @"IsBoolean", @"true");
	}
	NSDictionary *symbols = @{ @"add": @"+", @"subtract": @"-", @"multiply": @"*", @"divide": @"/", @"negate": @"-" };
	NSString *symbol = bag ? nil : comparison ?: [symbols objectForKey:name];
	if (symbol != nil) {
		ORMSetAttribute(function, @"OperatorSymbol", symbol);
	}
	NSArray *names = bag ? @[ @"values" ] : ORMParametersOf(name);
	if ([names count] > 0) {
		NSXMLElement *parameters = ORMNewElement(_document, CORE, @"Parameters");
		for (NSString *parameterName in names) {
			NSXMLElement *parameter = ORMNewElementWithId(_document, CORE, @"Parameter",
			                                              [self parameter:parameterName of:key]);
			ORMSetAttribute(parameter, @"Name", parameterName);
			if (bag) {
				ORMSetAttribute(parameter, @"BagInput", @"true");
			}
			[parameters addChild:parameter];
		}
		[function addChild:parameters];
	}
	[_functions setObject:function forKey:key];
	[_functionOrder addObject:key];
	return identifier;
}

- (NSString *)parameter:(NSString *)name of:(NSString *)key
{
	return ORMStableId([NSString stringWithFormat:@"ORMKit function %@ parameter %@", key, name]);
}

#pragma mark The path

/* Whether a not of the step says no more than its fact type: nothing
 * goes on from its nodes, and nothing is said of them. */
- (BOOL)isPlain:(ORMQueryStep *)step
{
	BOOL plain = step.countComparison == nil;
	for (ORMQueryNode *node in step.nodes) {
		plain = plain && [node.steps count] == 0 && node.comparison == nil && [node.values count] == 0;
	}
	return plain;
}

/* The path's PathedRoles, made where it has none. */
- (NSXMLElement *)rolesOf:(NSXMLElement *)path
{
	NSXMLElement *roles = ORMChild(path, CORE, @"PathedRoles");
	if (roles == nil) {
		roles = ORMNewElement(_document, CORE, @"PathedRoles");
		[path addChild:roles];
	}
	return roles;
}

/* The path's SubPaths, made where it has none. */
- (NSXMLElement *)subPathsOf:(NSXMLElement *)path
{
	NSXMLElement *subPaths = ORMChild(path, CORE, @"SubPaths");
	if (subPaths == nil) {
		subPaths = ORMNewElement(_document, CORE, @"SubPaths");
		[path addChild:subPaths];
	}
	return subPaths;
}

- (NSXMLElement *)subPathOf:(NSXMLElement *)path named:(NSString *)what
{
	NSXMLElement *sub = ORMNewElementWithId(_document, CORE, @"SubPath", [self idOf:what]);
	[[self subPathsOf:path] addChild:sub];
	return sub;
}

/* A node's condition on a value, as a value restriction: "> 5" a range
 * from 5, open; "<>" the ranges either side. */
- (NSXMLElement *)restrictionOf:(ORMQueryNode *)node constraint:(NSString *)local
{
	NSString *value = node.value ?: @"";
	NSString *comparison = node.comparison;
	NSMutableArray *ranges = [NSMutableArray array];
	if ([comparison isEqualToString:@"="]) {
		[ranges addObject:@[ value, value, @"NotSet", @"NotSet" ]];
	} else if ([comparison isEqualToString:@"<"] || [comparison isEqualToString:@"<="]) {
		[ranges addObject:@[ @"", value, @"NotSet", [comparison isEqualToString:@"<"] ? @"Open" : @"Closed" ]];
	} else if ([comparison isEqualToString:@">"] || [comparison isEqualToString:@">="]) {
		[ranges addObject:@[ value, @"", [comparison isEqualToString:@">"] ? @"Open" : @"Closed", @"NotSet" ]];
	} else if ([comparison isEqualToString:@"<>"]) {
		[ranges addObject:@[ @"", value, @"NotSet", @"Open" ]];
		[ranges addObject:@[ value, @"", @"Open", @"NotSet" ]];
	} else {
		[self refuse:[NSString stringWithFormat:@"its path has no condition \"%@\"", comparison ?: @""]];
		return nil;
	}
	NSXMLElement *restriction = ORMNewElement(_document, CORE, @"ValueRestriction");
	NSXMLElement *constraint = ORMNewElementWithId(_document, CORE, local, [self idOf:[node.identifier stringByAppendingString:@"/values"]]);
	NSXMLElement *container = ORMNewElement(_document, CORE, @"ValueRanges");
	for (NSUInteger i = 0; i < [ranges count]; i++) {
		NSArray *range = [ranges objectAtIndex:i];
		NSXMLElement *element = ORMNewElementWithId(_document, CORE, @"ValueRange",
		                                            [self idOf:[NSString stringWithFormat:@"%@/range%lu", node.identifier, (unsigned long)i]]);
		ORMSetAttribute(element, @"MinValue", [range objectAtIndex:0]);
		ORMSetAttribute(element, @"MaxValue", [range objectAtIndex:1]);
		ORMSetAttribute(element, @"MinInclusion", [range objectAtIndex:2]);
		ORMSetAttribute(element, @"MaxInclusion", [range objectAtIndex:3]);
		[container addChild:element];
	}
	[constraint addChild:container];
	[restriction addChild:constraint];
	return restriction;
}

/* A node put at a root or pathed role: its source, its label's unifier,
 * its condition on a value. */
- (void)place:(ORMQueryNode *)node source:(NSArray *)source element:(NSXMLElement *)element scoped:(BOOL)scoped
{
	[_sources setObject:source forKey:node.identifier];
	if (scoped) {
		[_scoped addObject:node.identifier];
	}
	if (node.label != nil) {
		NSString *first = [_query firstOccurrenceOf:node].identifier;
		NSMutableArray *members = [_unified objectForKey:first];
		if (members == nil) {
			members = [NSMutableArray array];
			[_unified setObject:members forKey:first];
			[_unifiedOrder addObject:first];
		}
		[members addObject:source];
	}
	if (node.comparison != nil && node.comparedNode == nil) {
		BOOL root = [[source firstObject] isEqualToString:@"PathRoot"];
		NSXMLElement *restriction = [self restrictionOf:node constraint:root ? @"PathRootConditionValueConstraint"
		                                                                     : @"PathedRoleConditionValueConstraint"];
		if (restriction != nil) {
			[element addChild:restriction];
		}
	}
}

- (NSXMLElement *)pathedRole:(ORMRole *)role named:(NSString *)what purpose:(NSString *)purpose in:(NSXMLElement *)path
{
	if (role.proxiedRole != nil || role.factType.impliedByFactType != nil) {
		[self refuse:@"its path goes through an objectification's link fact type"];
	}
	NSXMLElement *pathed = ORMNewElementWithId(_document, CORE, @"PathedRole", [self idOf:what]);
	ORMSetAttribute(pathed, @"ref", role.identifier);
	ORMSetAttribute(pathed, @"Purpose", purpose);
	[[self rolesOf:path] addChild:pathed];
	return pathed;
}

/* A node's role in the step it is in, on the path. */
- (void)node:(ORMQueryNode *)node in:(NSXMLElement *)path scoped:(BOOL)scoped
{
	NSXMLElement *pathed = [self pathedRole:node.role named:node.identifier purpose:@"SameFactType" in:path];
	[self place:node source:@[ @"PathedRole", ORMAttribute(pathed, @"id") ] element:pathed scoped:scoped];
}

/* What goes on from a node, on the path it ends: its one step, or a
 * sub-path for each. */
- (void)goOnFrom:(ORMQueryNode *)node in:(NSXMLElement *)path scoped:(BOOL)scoped
{
	NSArray *steps = node.steps;
	if ([steps count] == 1) {
		[self step:[steps firstObject] in:path scoped:scoped];
		return;
	}
	BOOL alternatives = node.combinesWithOr && [steps count] > 1;
	if (alternatives) {
		ORMSetAttribute(path, @"SplitCombinationOperator", @"Or");
	}
	for (ORMQueryStep *step in steps) {
		NSXMLElement *sub = [self subPathOf:path named:[step.identifier stringByAppendingString:@"/sub"]];
		[self step:step in:sub scoped:scoped || alternatives];
	}
}

- (void)step:(ORMQueryStep *)step in:(NSXMLElement *)path scoped:(BOOL)scoped
{
	BOOL negated = step.operatorKind == ORMQueryNot;
	if (negated) {
		scoped = YES;
	}
	/* Not, of more than its fact type: the path's split negated, the step
	 * its one sub-path. */
	if (negated && ![self isPlain:step]) {
		ORMSetAttribute(path, @"SplitIsNegated", @"true");
		path = [self subPathOf:path named:[step.identifier stringByAppendingString:@"/not"]];
		negated = NO;
	}
	NSXMLElement *entry = [self pathedRole:step.entryRole named:step.identifier
	                               purpose:step.operatorKind == ORMQueryMaybe ? @"PostOuterJoin" : @"PostInnerJoin"
	                                    in:path];
	if (negated) {
		ORMSetAttribute(entry, @"IsNegated", @"true");
	}
	NSMutableArray *goingOn = [NSMutableArray array];
	for (ORMQueryNode *node in step.nodes) {
		if ([node.steps count] > 0) {
			[goingOn addObject:node];
		} else {
			[self node:node in:path scoped:scoped];
		}
	}
	if ([goingOn count] == 1) {
		[self node:[goingOn firstObject] in:path scoped:scoped];
		[self goOnFrom:[goingOn firstObject] in:path scoped:scoped];
		return;
	}
	for (ORMQueryNode *node in goingOn) {
		NSXMLElement *sub = [self subPathOf:path named:[node.identifier stringByAppendingString:@"/sub"]];
		[self node:node in:sub scoped:scoped];
		[self goOnFrom:node in:sub scoped:scoped];
	}
}

#pragma mark Calculations

/* Where a node used in a calculation is: refused where it is under a not
 * or an alternative, or not on the path. */
- (NSArray *)sourceOfNode:(ORMQueryNode *)node
{
	if (node == nil) {
		[self refuse:@"it calculates with a node it does not have"];
		return nil;
	}
	if (node.isValue) {
		return [self sourceOfValue:node];
	}
	if ([_scoped containsObject:node.identifier]) {
		[self refuse:@"it calculates with a node under a not or an alternative"];
		return nil;
	}
	NSArray *source = [_sources objectForKey:node.identifier];
	if (source == nil) {
		[self refuse:@"it calculates with a node not on its path"];
	}
	return source;
}

- (ORMQueryNode *)nodeWithId:(NSString *)identifier
{
	for (ORMQueryNode *node in [_query nodes]) {
		if ([node.identifier isEqualToString:identifier]) {
			return node;
		}
	}
	return nil;
}

/* A value node's source: the node or constant it is, else its
 * calculation. */
- (NSArray *)sourceOfValue:(ORMQueryNode *)value
{
	NSArray *had = [_sources objectForKey:value.identifier];
	if (had != nil) {
		return had;
	}
	if (value.valueOf != nil && [_scoped containsObject:value.valueOf.identifier]) {
		[self refuse:@"it calculates under a not or an alternative"];
		return nil;
	}
	NSArray *source = [self sourceOfExpression:value.expression named:value.identifier];
	if (source != nil) {
		[_sources setObject:source forKey:value.identifier];
	}
	return source;
}

- (NSArray *)sourceOfExpression:(ORMQueryExpression *)expression named:(NSString *)what
{
	switch (expression.kind) {
	case ORMQueryExpressionNode:
		return [self sourceOfNode:[self nodeWithId:expression.nodeId]];
	case ORMQueryExpressionConstant:
		return @[ @"Constant", ORMConstantValue(expression.constant), [self idOf:[what stringByAppendingString:@"/constant"]] ];
	case ORMQueryExpressionFunction: {
		NSMutableArray *inputs = [NSMutableArray array];
		for (NSUInteger i = 0; i < [expression.arguments count]; i++) {
			NSString *name = [NSString stringWithFormat:@"%@/%lu", what, (unsigned long)i];
			NSArray *input = [self sourceOfExpression:[expression.arguments objectAtIndex:i] named:name];
			if (input == nil) {
				return nil;
			}
			[inputs addObject:input];
		}
		if (ORMParametersOf(expression.function) == nil) {
			[self refuse:[NSString stringWithFormat:@"its path has no function %@", expression.function ?: @"?"]];
			return nil;
		}
		return [self calculate:expression.function bag:NO inputs:inputs context:nil named:what];
	}
	case ORMQueryExpressionAggregate: {
		NSArray *input = [self sourceOfNode:[self nodeWithId:[expression.nodeIds firstObject]]];
		NSMutableArray *context = [NSMutableArray array];
		for (NSString *group in expression.groups) {
			NSArray *source = [self sourceOfNode:[self nodeWithId:group]];
			if (source != nil && [[source firstObject] isEqualToString:@"CalculatedValue"]) {
				[self refuse:@"it aggregates for a calculated value"];
				return nil;
			}
			if (source != nil) {
				[context addObject:source];
			}
		}
		return input != nil ? [self calculate:expression.function bag:YES inputs:@[ input ] context:context named:what] : nil;
	}
	}
	return nil;
}

/* A calculated value, made: its function, an aggregate's context (every
 * instance where it has none), its inputs. */
- (NSArray *)calculate:(NSString *)function bag:(BOOL)bag inputs:(NSArray *)inputs context:(NSArray *)context named:(NSString *)what
{
	if (_why != nil) {
		return nil;
	}
	NSString *functionId = [self function:function bag:bag];
	NSString *key = bag ? [function stringByAppendingString:@"/bag"] : function;
	NSArray *parameters = bag ? @[ @"values" ] : ORMParametersOf(function);
	if ([parameters count] != [inputs count]) {
		[self refuse:[NSString stringWithFormat:@"%@ takes %lu values", function, (unsigned long)[parameters count]]];
		return nil;
	}
	NSString *identifier = [self idOf:[what stringByAppendingString:@"/calculation"]];
	NSXMLElement *calculation = ORMNewElementWithId(_document, CORE, @"CalculatedValue", identifier);
	[calculation addChild:ORMNewRef(_document, CORE, @"Function", functionId)];
	if (bag && [context count] > 0) {
		NSXMLElement *element = ORMNewElement(_document, CORE, @"AggregationContext");
		for (NSArray *source in context) {
			[element addChild:ORMSourceElement(_document, source)];
		}
		[calculation addChild:element];
	} else if (bag) {
		ORMSetAttribute(calculation, @"UniversalAggregationContext", @"true");
	}
	if ([inputs count] > 0) {
		NSXMLElement *container = ORMNewElement(_document, CORE, @"Inputs");
		for (NSUInteger i = 0; i < [inputs count]; i++) {
			NSXMLElement *input = ORMNewElementWithId(_document, CORE, @"Input",
			                                          [self idOf:[NSString stringWithFormat:@"%@/input%lu", what, (unsigned long)i]]);
			[input addChild:ORMNewRef(_document, CORE, @"Parameter", [self parameter:[parameters objectAtIndex:i] of:key])];
			NSXMLElement *source = ORMNewElement(_document, CORE, @"Source");
			[source addChild:ORMSourceElement(_document, [inputs objectAtIndex:i])];
			[input addChild:source];
			[container addChild:input];
		}
		[calculation addChild:container];
	}
	[_calculations addObject:calculation];
	return @[ @"CalculatedValue", identifier ];
}

/* A comparison that must hold: a boolean calculated value, a condition of
 * the path. */
- (void)condition:(NSString *)comparison of:(NSArray *)left with:(NSArray *)right named:(NSString *)what
{
	NSString *function = ORMComparisonFunction(comparison);
	if (function == nil) {
		[self refuse:[NSString stringWithFormat:@"its path has no condition \"%@\"", comparison ?: @""]];
		return;
	}
	if (left == nil || right == nil) {
		return;
	}
	NSArray *made = [self calculate:function bag:NO inputs:@[ left, right ] context:nil named:what];
	if (made != nil) {
		[_conditions addObject:[made lastObject]];
	}
}

/* What is calculated of the query: the conditions comparing nodes, value
 * nodes and aggregates, and each step's aggregate condition. */
- (void)calculateConditions
{
	for (ORMQueryNode *node in [_query nodes]) {
		if (node.comparedNode != nil && node.comparison != nil) {
			[self condition:node.comparison of:[self sourceOfNode:node] with:[self sourceOfNode:node.comparedNode]
			          named:[node.identifier stringByAppendingString:@"/compared"]];
		} else if (node.isValue && node.comparison != nil) {
			NSArray *constant = @[ @"Constant", node.value ?: @"", [self idOf:[node.identifier stringByAppendingString:@"/value"]] ];
			[self condition:node.comparison of:[self sourceOfValue:node] with:constant
			          named:[node.identifier stringByAppendingString:@"/compared"]];
		}
		for (ORMQueryStep *step in node.isValue ? @[] : node.steps) {
			if (step.countComparison == nil) {
				continue;
			}
			if ([_scoped containsObject:node.identifier] || step.operatorKind == ORMQueryNot) {
				[self refuse:@"it calculates under a not or an alternative"];
				return;
			}
			ORMQueryNode *of = step.aggregateNode ?: [step.nodes firstObject];
			ORMQueryNode *group = step.groupNode ?: step.parent;
			NSArray *source = [self sourceOfNode:of];
			NSArray *context = [self sourceOfNode:group];
			NSString *name = [ORMQuery nameOfAggregate:step.aggregate];
			NSArray *aggregate = source != nil && context != nil
				? [self calculate:name bag:YES inputs:@[ source ] context:@[ context ]
				            named:[step.identifier stringByAppendingString:@"/aggregate"]]
				: nil;
			NSArray *other = nil;
			if (step.comparesAggregates) {
				NSArray *compared = [self sourceOfNode:step.comparedGroupNode];
				other = source != nil && compared != nil
					? [self calculate:[ORMQuery nameOfAggregate:step.comparedAggregate] bag:YES inputs:@[ source ]
					          context:@[ compared ]
					            named:[step.identifier stringByAppendingString:@"/compared aggregate"]]
					: nil;
			} else {
				other = @[ @"Constant", step.aggregateValue ?: @"",
					       [self idOf:[step.identifier stringByAppendingString:@"/value"]] ];
			}
			[self condition:step.countComparison of:aggregate with:other
			          named:[step.identifier stringByAppendingString:@"/condition"]];
		}
	}
}

#pragma mark Writing

- (NSArray<NSXMLElement *> *)elementsOf:(ORMQuery *)query reason:(NSString **)reason
{
	_query = query;
	_why = nil;
	_sources = [NSMutableDictionary dictionary];
	_scoped = [NSMutableSet set];
	_unified = [NSMutableDictionary dictionary];
	_unifiedOrder = [NSMutableArray array];
	_calculations = [NSMutableArray array];
	_conditions = [NSMutableArray array];
	ORMQueryNode *root = query.root;
	ORMFactType *fact = query.derivedFactType;
	if (root == nil || root.objectType == nil || !query.isComplete) {
		[self refuse:@"the query is not complete"];
	}
	NSXMLElement *path = ORMNewElementWithId(_document, CORE, @"RolePath", [self idOf:@"path"]);
	if (_why == nil) {
		NSXMLElement *rootElement = ORMNewElementWithId(_document, CORE, @"RootObjectType", [self idOf:root.identifier]);
		ORMSetAttribute(rootElement, @"ref", root.objectType.identifier);
		[path addChild:rootElement];
		[self place:root source:@[ @"PathRoot", ORMAttribute(rootElement, @"id") ] element:rootElement scoped:NO];
		[self goOnFrom:root in:path scoped:NO];
	}
	/* What it projects: each role's node; a role of several values (a
	 * Money of an amount and a currency) a path cannot project. */
	NSMutableArray *projected = [NSMutableArray array];
	if (_why == nil && fact != nil) {
		NSArray *groups = [query derivedColumnGroups];
		NSArray *roles = [fact visibleRoles];
		if ([groups count] != [roles count]) {
			[self refuse:@"it does not tick a node for each role"];
		}
		for (NSUInteger i = 0; _why == nil && i < [roles count]; i++) {
			NSArray *group = [groups objectAtIndex:i];
			if ([group count] != 1) {
				[self refuse:@"a role of several values is projected from several nodes"];
				break;
			}
			NSArray *source = [self sourceOfNode:[group firstObject]];
			if (source != nil) {
				[projected addObject:@[ [roles objectAtIndex:i], source ]];
			}
		}
	}
	if (_why == nil) {
		[self calculateConditions];
	}
	if (_why != nil) {
		if (reason != NULL) {
			*reason = _why;
		}
		return nil;
	}
	if ([_unifiedOrder count] > 0) {
		NSXMLElement *unifiers = ORMNewElement(_document, CORE, @"ObjectUnifiers");
		for (NSString *first in _unifiedOrder) {
			NSArray *members = [_unified objectForKey:first];
			if ([members count] < 2) {
				continue;
			}
			NSXMLElement *unifier = ORMNewElementWithId(_document, CORE, @"ObjectUnifier",
			                                            [self idOf:[first stringByAppendingString:@"/unifier"]]);
			for (NSArray *member in members) {
				[unifier addChild:ORMSourceElement(_document, member)];
			}
			[unifiers addChild:unifier];
		}
		if ([[unifiers children] count] > 0) {
			[path addChild:unifiers];
		}
	}
	if ([_calculations count] > 0) {
		NSXMLElement *calculations = ORMNewElement(_document, CORE, @"CalculatedValues");
		for (NSXMLElement *calculation in _calculations) {
			[calculations addChild:calculation];
		}
		[path addChild:calculations];
	}
	if ([_conditions count] > 0) {
		NSXMLElement *conditions = ORMNewElement(_document, CORE, @"Conditions");
		for (NSString *condition in _conditions) {
			[conditions addChild:ORMNewRef(_document, CORE, @"CalculatedCondition", condition)];
		}
		[path addChild:conditions];
	}
	NSXMLElement *components = ORMNewElement(_document, CORE, @"PathComponents");
	[components addChild:path];
	if (fact == nil) {
		return @[ components ];
	}
	NSXMLElement *projections = ORMNewElement(_document, CORE, @"DerivationProjections");
	NSXMLElement *projection = ORMNewElementWithId(_document, CORE, @"DerivationProjection", [self idOf:@"projection"]);
	ORMSetAttribute(projection, @"ref", ORMAttribute(path, @"id"));
	for (NSArray *pair in projected) {
		ORMRole *role = [pair firstObject];
		NSXMLElement *roleProjection = ORMNewElementWithId(_document, CORE, @"RoleProjection",
		                                                   [self idOf:[@"projection/" stringByAppendingString:role.identifier]]);
		ORMSetAttribute(roleProjection, @"ref", role.identifier);
		NSXMLElement *source = ORMNewElement(_document, CORE, @"DerivationSource");
		[source addChild:ORMSourceElement(_document, [pair lastObject])];
		[roleProjection addChild:source];
		[projection addChild:roleProjection];
	}
	[projections addChild:projection];
	return @[ components, projections ];
}

@end
