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
@property (nonatomic, readwrite, weak) ORMRole *derivedRole;
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
@end

/* The kinds and functions as the file names them. */
static NSArray<NSString *> *
ORMQueryKindNames(void)
{
	return @[ @"List", @"Constraint", @"Calculation", @"Derivation" ];
}

/* A fact type's derivation rule as NORMA keeps it, which a derivation
 * query writes (docs/DERIVATION.md); nil when it has none. */
static NSXMLElement *
ORMDerivationPathOf(NSXMLElement *fact)
{
	return ORMChild(ORMChild(fact, CORE, @"DerivationRule"), CORE, @"FactTypeDerivationPath");
}

/* Whether the rule is NORMA's own, a role path, rather than only words. */
static BOOL
ORMHasRolePath(NSXMLElement *fact)
{
	NSXMLElement *path = ORMDerivationPathOf(fact);
	return ORMChild(path, CORE, @"PathComponents") != nil || ORMChild(path, CORE, @"PathComponent") != nil
		|| ORMChild(ORMChild(fact, CORE, @"DerivationRule"), CORE, @"DerivationExpression") != nil;
}

/* The fact type's rule, in words only, made where it has none: NORMA reads
 * the fact type as derived, and shows the words, which the normalizer
 * keeps as the query's verbalization. */
static void
ORMEnsureDerivationRule(NSXMLDocument *document, NSXMLElement *fact, NSString *text)
{
	NSXMLElement *rule = ORMChild(fact, CORE, @"DerivationRule");
	if (rule == nil) {
		rule = ORMNewElement(document, CORE, @"DerivationRule");
		ORMInsertChild(fact, rule);
	}
	NSXMLElement *path = ORMChild(rule, CORE, @"FactTypeDerivationPath");
	if (path == nil) {
		path = ORMNewElementWithId(document, CORE, @"FactTypeDerivationPath", nil);
		[rule addChild:path];
	}
	NSXMLElement *informal = ORMChild(path, CORE, @"InformalRule");
	if (informal == nil) {
		informal = ORMNewElement(document, CORE, @"InformalRule");
		[path addChild:informal];
	}
	NSXMLElement *note = ORMChild(informal, CORE, @"DerivationNote");
	if (note == nil) {
		note = ORMNewElementWithId(document, CORE, @"DerivationNote", nil);
		[informal addChild:note];
		ORMSetChildText(document, note, CORE, @"Body", text);
	}
}

/* The rule a derivation query wrote, gone with it; NORMA's own stays. */
static void
ORMRemoveDerivationRule(NSXMLElement *fact)
{
	if (fact != nil && !ORMHasRolePath(fact)) {
		[ORMChild(fact, CORE, @"DerivationRule") detach];
	}
}

static NSArray<NSString *> *
ORMCalculationFunctionNames(void)
{
	return @[ @"Value", @"Count", @"Total", @"Average", @"Maximum", @"Minimum" ];
}

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

+ (ORMQuery *)derivationOf:(ORMFactType *)factType inModel:(ORMModel *)model
{
	for (ORMQuery *query in [self queriesInModel:model]) {
		if (query.kind == ORMQueryDerivation && [query.derivedFactType.identifier isEqualToString:factType.identifier]) {
			return query;
		}
	}
	return nil;
}

/* An element of a query read from a rule, kept out of the document. */
static NSXMLElement *
ORMRuleQueryElement(NSString *local, NSString *identifier)
{
	NSXMLElement *element = [[NSXMLElement alloc] initWithName:[@"q:" stringByAppendingString:local] URI:Q];
	ORMSetAttribute(element, @"id", identifier);
	return element;
}

/* The object type at a node of a query read from a rule. */
static ORMObjectType *
ORMRuleNodeType(NSXMLElement *node, ORMModel *model)
{
	id element = [model elementWithId:ORMAttribute(node, @"Role") ?: ORMRef(node)];
	return [element isKindOfClass:[ORMRole class]] ? [(ORMRole *)element player] : element;
}

/* A step of a query read from a rule, entered by the role: a node for
 * each other role. */
static NSXMLElement *
ORMRuleStep(ORMRole *entry, NSString *identifier)
{
	NSXMLElement *step = ORMRuleQueryElement(@"Step", identifier);
	ORMSetAttribute(step, @"ref", entry.factType.identifier);
	ORMSetAttribute(step, @"Role", entry.identifier);
	for (ORMRole *other in entry.factType.roles) {
		if (other == entry || other.player.isImplicitBooleanValue) {
			continue;
		}
		NSXMLElement *node = ORMRuleQueryElement(@"Node", [NSString stringWithFormat:@"%@.%@", identifier, other.identifier]);
		ORMSetAttribute(node, @"Role", other.identifier);
		[step addChild:node];
	}
	return step;
}

/* NORMA's rule for the fact type, as a derivation query's element: the
 * path's root its root node; each role it joins by a step from the node the
 * path is at, a node for each of the fact type's other roles, the one it
 * goes on by where the path then is; each projected node ticked, For the
 * role it is projected as. nil, and why, where the path is not plain. Ids
 * are the path's, so it reads the same each time. */
static NSXMLElement *
ORMRuleElement(ORMFactType *fact, NSString **why)
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
	NSString *pathId = ORMAttribute([path element], @"id") ?: fact.identifier;
	NSXMLElement *query = ORMRuleQueryElement(@"Query", pathId);
	/* RolePath in PathComponents in FactTypeDerivationPath, which names it. */
	NSXMLElement *owner = (NSXMLElement *)[[[path element] parent] parent];
	ORMSetAttribute(query, @"Name", [ORMAttribute(owner, @"Name") length] > 0 ? ORMAttribute(owner, @"Name") : fact.name);
	ORMSetAttribute(query, @"Kind", @"Derivation");
	ORMSetAttribute(query, @"Of", fact.identifier);
	NSXMLElement *root = ORMRuleQueryElement(@"Node", path.rootId ?: [pathId stringByAppendingString:@".root"]);
	ORMSetAttribute(root, @"ref", path.rootObjectType.identifier);
	[query addChild:root];
	NSMutableDictionary<NSString *, NSXMLElement *> *at = [NSMutableDictionary dictionary];
	NSXMLElement *current = root;
	NSXMLElement *step = nil;
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
			NSXMLElement *node = nil;
			for (NSXMLElement *each in ORMChildren(step, Q, @"Node")) {
				ORMRole *at = [fact.model elementWithId:ORMAttribute(each, @"Role")];
				node = at == role || at.proxiedRole == role ? each : node;
			}
			ORMRole *entry = [fact.model elementWithId:ORMAttribute(step, @"Role") ?: @""];
			for (ORMRole *proxy in node == nil && current == [step parent] ? role.factType.roles : @[]) {
				if (proxy.proxiedRole != nil && proxy.proxiedRole == entry) {
					NSXMLElement *from = (NSXMLElement *)[step parent];
					[step detach];
					step = ORMRuleStep(proxy, ORMAttribute(step, @"id"));
					[from addChild:step];
					node = ORMChildren(step, Q, @"Node").firstObject;
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
			step = ORMRuleStep(role, [ORMAttribute([pathed element], @"id") stringByAppendingString:@".step"]);
			[current addChild:step];
		}
		NSString *pathedId = ORMAttribute([pathed element], @"id");
		if (pathedId != nil) {
			[at setObject:current forKey:pathedId];
		}
	}
	for (ORMRole *role in [fact visibleRoles]) {
		ORMPathSource *source = [rule.projections objectForKey:role.identifier];
		NSXMLElement *node = source.kind == ORMPathSourceRoot && source.root == path ? root
			: source.kind == ORMPathSourcePathedRole ? [at objectForKey:ORMAttribute([source.pathedRole element], @"id") ?: @""]
			: nil;
		if (node == nil || ORMAttribute(node, @"For") != nil) {
			*why = @"it does not project one point of its path for each role";
			return nil;
		}
		ORMSetAttribute(node, @"Projected", @"true");
		ORMSetAttribute(node, @"For", role.identifier);
	}
	return query;
}

/* The element a derivation is read from: the document's query, or its
 * fact type's NORMA rule. */
static NSXMLElement *
ORMDerivationElement(ORMFactType *fact, ORMModel *model, NSString **why)
{
	for (NSXMLElement *each in ORMChildren([ORMQuery containerIn:[model.modelElement rootDocument]], Q, @"Query")) {
		if ([ORMAttribute(each, @"Kind") isEqualToString:@"Derivation"]
		    && [ORMAttribute(each, @"Of") isEqualToString:fact.identifier]) {
			return each;
		}
	}
	return ORMRuleElement(fact, why);
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
		NSXMLElement *element = fact.isDerived && ![derived containsObject:fact.identifier]
			&& [[fact derivationRule].paths count] > 0 ? ORMRuleElement(fact, &why) : nil;
		if (element != nil) {
			[derivations addObject:[self queryOf:element model:model]];
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
	return @[ @"Operator", @"Count", @"CountValue", @"Aggregate", @"AggregateNode", @"GroupNode", @"CompareGroupNode",
	          @"CompareAggregate" ];
}

/* The nodes and steps of a tree, depth first. */
static void
ORMQueryTree(NSXMLElement *element, NSMutableArray<NSXMLElement *> *into)
{
	[into addObject:element];
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind
		    && ([[child localName] isEqualToString:@"Node"] || [[child localName] isEqualToString:@"Step"])) {
			ORMQueryTree((NSXMLElement *)child, into);
		}
	}
}

/* The attributes that name another node of the query. */
static NSArray<NSString *> *
ORMNodeReferences(void)
{
	return @[ @"CompareTo", @"CompareGroupNode", @"GroupNode", @"AggregateNode" ];
}

/* Every reference to a node of the tree, from one id to another. */
static void
ORMRenameNode(NSXMLElement *tree, NSString *from, NSString *to)
{
	NSMutableArray *all = [NSMutableArray array];
	ORMQueryTree(tree, all);
	for (NSXMLElement *element in all) {
		for (NSString *name in ORMNodeReferences()) {
			if ([ORMAttribute(element, name) isEqualToString:from]) {
				ORMSetAttribute(element, name, to);
			}
		}
	}
}

/* The derivation's tree re-rooted at the node: each step on the way up
 * reversed, the node above going under it. Only a plain binary step
 * reverses: nil and why otherwise. */
static NSXMLElement *
ORMReroot(NSXMLElement *target, ORMModel *model, NSString **why)
{
	NSMutableArray *path = [NSMutableArray array];
	for (NSXMLElement *node = target; [[[node parent] localName] isEqualToString:@"Step"];) {
		NSXMLElement *step = (NSXMLElement *)[node parent];
		NSXMLElement *above = (NSXMLElement *)[step parent];
		NSUInteger nodes = [ORMChildren(step, Q, @"Node") count];
		BOOL plain = nodes == 1;
		for (NSString *name in ORMStepQualifiers()) {
			plain = plain && ORMAttribute(step, name) == nil;
		}
		if (!plain || [ORMAttribute(above, @"Combine") isEqualToString:@"Or"]) {
			*why = @"its rule goes there through a step that is not one plain binary step";
			return nil;
		}
		/* The roles as the rule has them, before any is turned around. */
		[path addObject:@[ node, step, above, ORMAttribute(node, @"Role") ?: @"", ORMAttribute(step, @"Role") ?: @"" ]];
		node = above;
	}
	for (NSArray *edge in path) {
		NSXMLElement *node = [edge objectAtIndex:0];
		NSXMLElement *step = [edge objectAtIndex:1];
		NSXMLElement *above = [edge objectAtIndex:2];
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
		ORMSetAttribute(step, @"Role", nodeRole);
		ORMSetAttribute(above, @"ref", nil);
		ORMSetAttribute(above, @"Role", aboveRole);
		[step addChild:above];
		[node addChild:step];
	}
	if ([path count] > 0) {
		ORMRole *role = [model elementWithId:[[path firstObject] objectAtIndex:3]];
		ORMSetAttribute(target, @"Role", nil);
		ORMSetAttribute(target, @"ref", role.player.identifier);
	}
	return target;
}

/* The step through a derived fact type put as its derivation's path,
 * under the node it is from. nil when done; why otherwise. */
static NSString *
ORMExpandStep(NSXMLElement *step, ORMFactType *fact, ORMQuery *derivation, NSXMLElement *rule, NSUInteger round,
              ORMModel *model)
{
	NSString *what = [[fact primaryReading] expandedText] ?: fact.name;
	NSXMLElement *from = (NSXMLElement *)[step parent];
	NSXMLElement *tree = [ORMChild(rule, Q, @"Node") copy];
	NSMutableArray *all = [NSMutableArray array];
	ORMQueryTree(tree, all);
	/* Its columns, in the order the planner lists them: the fact type's
	 * roles. */
	NSMutableArray *columns = [NSMutableArray array];
	for (NSXMLElement *element in all) {
		if ([[element localName] isEqualToString:@"Node"] && [ORMAttribute(element, @"Projected") isEqualToString:@"true"]) {
			[columns addObject:element];
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
		for (NSXMLElement *column in columns) {
			if ([ORMAttribute(column, @"id") isEqualToString:node.identifier]) {
				[byRole addObject:column];
			}
		}
	}
	if ([byRole count] != [roles count]) {
		return [NSString stringWithFormat:@"\"%@\" is derived by %@, which does not list one of each of its roles.", what,
		                                  derivation.name];
	}
	columns = byRole;
	/* Its own: fresh ids, its labels apart from the query's, nothing it
	 * lists or sorts by but what the step's nodes say. */
	for (NSXMLElement *element in all) {
		NSString *was = ORMAttribute(element, @"id");
		NSString *now = ORMNewId();
		ORMSetAttribute(element, @"id", now);
		if (was != nil) {
			ORMRenameNode(tree, was, now);
		}
		NSString *label = ORMAttribute(element, @"Label");
		if ([label length] > 0) {
			ORMSetAttribute(element, @"Label", [NSString stringWithFormat:@"%@ (%@ %lu)", label, derivation.name,
			                                                              (unsigned long)round]);
		}
		ORMSetAttribute(element, @"Projected", nil);
		ORMSetAttribute(element, @"For", nil);
		ORMSetAttribute(element, @"Sort", nil);
	}
	NSUInteger entry = [roles indexOfObjectPassingTest:^BOOL(ORMRole *role, NSUInteger i, BOOL *stop) {
		(void)i;
		(void)stop;
		return [role.identifier isEqualToString:ORMAttribute(step, @"Role")];
	}];
	if (entry == NSNotFound) {
		return [NSString stringWithFormat:@"\"%@\" is gone through by a role it does not show.", what];
	}
	NSString *why = nil;
	NSXMLElement *root = ORMReroot([columns objectAtIndex:entry], model, &why);
	if (root == nil) {
		return [NSString stringWithFormat:@"\"%@\" cannot be gone through from there: %@.", what, why];
	}
	/* The node the step is from is the column it enters by. */
	for (NSString *name in @[ @"Comparison", @"Value", @"CompareTo", @"Label" ]) {
		NSString *value = ORMAttribute(root, name);
		if (value == nil) {
			continue;
		}
		if (ORMAttribute(from, name) != nil && ![ORMAttribute(from, name) isEqualToString:value]) {
			return [NSString stringWithFormat:@"\"%@\" says more of %@ than the query can take with it.", what,
			                                  [roles[entry] player].name];
		}
		ORMSetAttribute(from, name, value);
	}
	ORMRenameNode(tree, ORMAttribute(root, @"id"), ORMAttribute(from, @"id"));
	/* The step's other nodes are the other columns: what the query says
	 * of each, with what the rule says. */
	for (NSXMLElement *node in ORMChildren(step, Q, @"Node")) {
		NSUInteger index = [roles indexOfObjectPassingTest:^BOOL(ORMRole *role, NSUInteger i, BOOL *stop) {
			(void)i;
			(void)stop;
			return [role.identifier isEqualToString:ORMAttribute(node, @"Role")];
		}];
		if (index == NSNotFound || index == entry) {
			continue;
		}
		NSXMLElement *column = [columns objectAtIndex:index];
		for (NSXMLNode *attribute in [node attributes]) {
			NSString *name = [attribute name];
			if ([name isEqualToString:@"id"] || [name isEqualToString:@"Role"]) {
				continue;
			}
			NSString *theirs = ORMAttribute(column, name);
			if (theirs != nil && ![theirs isEqualToString:[attribute stringValue]]) {
				return [NSString stringWithFormat:@"\"%@\" says more of %@ than the query can take with it.", what,
				                                  [roles[index] player].name];
			}
			ORMSetAttribute(column, name, [attribute stringValue]);
		}
		ORMRenameNode(tree, ORMAttribute(column, @"id"), ORMAttribute(node, @"id"));
		ORMSetAttribute(column, @"id", ORMAttribute(node, @"id"));
		for (NSXMLElement *more in ORMChildren(node, Q, @"Step")) {
			[more detach];
			[column addChild:more];
		}
	}
	/* The rule's steps from the entry column go under the node, where the
	 * step was; the step's not, maybe or count with them, where there is
	 * one to carry it. */
	NSArray *moved = ORMChildren(root, Q, @"Step");
	BOOL qualified = NO;
	for (NSString *name in ORMStepQualifiers()) {
		qualified = qualified || ORMAttribute(step, name) != nil;
	}
	if (qualified && [moved count] != 1) {
		return [NSString stringWithFormat:@"\"%@\" is gone through with not, maybe or a count, and its rule branches "
		                                  @"there.",
		                                  what];
	}
	NSUInteger at = [step index];
	for (NSXMLElement *each in moved) {
		[each detach];
		for (NSString *name in qualified ? ORMStepQualifiers() : @[]) {
			ORMSetAttribute(each, name, ORMAttribute(step, name));
		}
		[from insertChild:each atIndex:at++];
	}
	[step detach];
	return nil;
}

- (ORMQuery *)expandedInModel:(ORMModel *)model notes:(NSMutableArray<NSString *> *)notes
{
	NSXMLElement *element = nil;
	for (NSXMLElement *each in ORMChildren([ORMQuery containerIn:[model.modelElement rootDocument]], Q, @"Query")) {
		element = [ORMAttribute(each, @"id") isEqualToString:self.identifier] ? each : element;
	}
	if (element == nil) {
		return self;
	}
	NSXMLElement *copy = nil;
	for (NSUInteger round = 1;; round++) {
		NSMutableArray *all = [NSMutableArray array];
		ORMQueryTree(ORMChild(copy ?: element, Q, @"Node") ?: element, all);
		NSXMLElement *step = nil;
		ORMFactType *fact = nil;
		for (NSXMLElement *each in all) {
			ORMFactType *through = [[each localName] isEqualToString:@"Step"] ? [model elementWithId:ORMRef(each)] : nil;
			if ([through isKindOfClass:[ORMFactType class]] && through.isDerived && ![through derivationRule].isStored) {
				step = each;
				fact = through;
				break;
			}
		}
		if (step == nil) {
			break;
		}
		NSString *what = [[fact primaryReading] expandedText] ?: fact.name;
		NSString *unplain = nil;
		NSXMLElement *rule = ORMDerivationElement(fact, model, &unplain);
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
				copy = [element copy];
				/* The step found again in the copy. */
				NSMutableArray *copied = [NSMutableArray array];
				ORMQueryTree(ORMChild(copy, Q, @"Node"), copied);
				for (NSXMLElement *each in copied) {
					step = [ORMAttribute(each, @"id") isEqualToString:ORMAttribute(step, @"id")] ? each : step;
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

+ (ORMQuery *)queryOf:(NSXMLElement *)element model:(ORMModel *)model
{
	ORMQuery *query = [[ORMQuery alloc] init];
	query.identifier = ORMAttribute(element, @"id");
	query.name = ORMAttribute(element, @"Name") ?: @"Query";
	query.isComplete = YES;
	NSUInteger kind = [ORMQueryKindNames() indexOfObject:ORMAttribute(element, @"Kind") ?: @"List"];
	query.kind = kind != NSNotFound ? (ORMQueryKind)kind : ORMQueryList;
	query.isDeontic = query.kind == ORMQueryConstraint && [ORMAttribute(element, @"Modality") isEqualToString:@"Deontic"];
	NSUInteger function = [ORMCalculationFunctionNames() indexOfObject:ORMAttribute(element, @"Function") ?: @"Value"];
	query.calculationFunction = function != NSNotFound ? (ORMQueryCalculationFunction)function : ORMCalculationValue;
	if (query.kind == ORMQueryDerivation) {
		ORMFactType *derived = [model elementWithId:ORMAttribute(element, @"Of")];
		query.derivedFactType = [derived isKindOfClass:[ORMFactType class]] ? derived : nil;
	}
	NSXMLElement *rootElement = ORMChild(element, Q, @"Node");
	ORMObjectType *type = [model elementWithId:ORMRef(rootElement)];
	if (![type isKindOfClass:[ORMObjectType class]]) {
		query.isComplete = NO;
		return query;
	}
	query.root = [query nodeOf:rootElement type:type role:nil model:model];
	/* What a condition compares with, now every node is read. */
	NSArray *nodes = [query nodes];
	NSString *of = query.kind == ORMQueryCalculation ? ORMAttribute(element, @"Of") : nil;
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

- (ORMQueryNode *)nodeOf:(NSXMLElement *)element type:(ORMObjectType *)type role:(ORMRole *)role model:(ORMModel *)model
{
	ORMQueryNode *node = [[ORMQueryNode alloc] init];
	node.identifier = ORMAttribute(element, @"id");
	node.objectType = type;
	node.role = role;
	node.isProjected = ORMBoolAttribute(element, @"Projected", NO);
	ORMRole *derived = [model elementWithId:ORMAttribute(element, @"For") ?: @""];
	node.derivedRole = [derived isKindOfClass:[ORMRole class]] ? derived : nil;
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
	step.groupNodeId = ORMAttribute(element, @"GroupNode");
	NSString *compared = ORMAttribute(element, @"CompareAggregate");
	NSUInteger comparedIndex = compared != nil ? [ORMQueryAggregateNames() indexOfObject:compared] : NSNotFound;
	step.comparesAggregates = comparedIndex != NSNotFound;
	step.comparedAggregate = comparedIndex != NSNotFound ? (ORMQueryAggregate)comparedIndex : ORMQueryCount;
	step.comparedGroupNodeId = ORMAttribute(element, @"CompareGroupNode");
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
			/* A link fact type is gone through as its objectified fact
			 * type's role: NORMA's paths do. */
			BOOL link = NO;
			for (ORMRole *other in role.factType.roles) {
				link = link || other.proxiedRole != nil;
			}
			if ((role.factType.kind == ORMFactTypeImplied && !link) || role.player.isImplicitBooleanValue) {
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

+ (NSString *)nameOfCalculationFunction:(ORMQueryCalculationFunction)function
{
	NSArray *names = @[ @"value", @"count", @"total", @"avg", @"max", @"min" ];
	return (NSUInteger)function < [names count] ? [names objectAtIndex:(NSUInteger)function] : @"value";
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
			NSString *compared = step.comparesAggregates
				? [NSString stringWithFormat:@"%@(%@) for %@", [ORMQuery nameOfAggregate:step.comparedAggregate],
				                             [step.aggregateNode designation], [step.comparedGroupNode designation]]
				: step.aggregateValue ?: @"";
			[out appendFormat:@"%@  + %@(%@) for %@ %@ %@\n", pad, [ORMQuery nameOfAggregate:step.aggregate],
			                  [step.aggregateNode designation], [step.groupNode ?: node designation],
			                  step.countComparison, compared];
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
	NSXMLElement *derived = [ORMAttribute(query, @"Kind") isEqualToString:@"Derivation"]
		? [_editor xml:ORMAttribute(query, @"Of")] : nil;
	[_editor change:@"Remove Query" with:^{
		NSXMLElement *container = (NSXMLElement *)[query parent];
		[query detach];
		ORMPruneIfEmpty(container);
		/* What it derived is asserted again. */
		ORMRemoveDerivationRule(derived);
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

- (BOOL)setKind:(ORMQueryKind)kind ofQuery:(NSString *)queryId reason:(NSString **)reason
{
	NSXMLElement *query = [self queryElement:queryId named:@"Query"];
	if (query == nil || (NSUInteger)kind >= [ORMQueryKindNames() count]) {
		if (reason != NULL) {
			*reason = query == nil ? @"There is no such query." : @"A query lists, is a constraint, or is a calculation.";
		}
		return NO;
	}
	NSString *name = kind == ORMQueryList ? nil : [ORMQueryKindNames() objectAtIndex:(NSUInteger)kind];
	if ([ORMAttribute(query, @"Kind") ?: @"List" isEqualToString:name ?: @"List"]) {
		return YES;
	}
	NSArray *titles = @[ @"Make Query a List", @"Make Query a Constraint", @"Make Query a Calculation",
		              @"Make Query a Derivation" ];
	NSXMLElement *derived = [ORMAttribute(query, @"Kind") isEqualToString:@"Derivation"]
		? [_editor xml:ORMAttribute(query, @"Of")] : nil;
	[_editor change:[titles objectAtIndex:(NSUInteger)kind] with:^{
		ORMSetAttribute(query, @"Kind", name);
		/* What only the kind it was had: a calculation's node and a
		 * derivation's fact type are both Of. */
		if (kind != ORMQueryConstraint) {
			ORMSetAttribute(query, @"Modality", nil);
		}
		ORMSetAttribute(query, @"Function", nil);
		ORMSetAttribute(query, @"Of", nil);
		/* No longer a derivation: the fact type is asserted again. */
		ORMRemoveDerivationRule(derived);
	}];
	return YES;
}

- (BOOL)setDerivedFactType:(NSString *)factTypeId ofQuery:(NSString *)queryId reason:(NSString **)reason
{
	NSXMLElement *query = [self queryElement:queryId named:@"Query"];
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
	ORMQuery *other = [fact isKindOfClass:[ORMFactType class]] ? [ORMQuery derivationOf:fact inModel:_editor.model] : nil;
	NSString *why = nil;
	if (query == nil) {
		why = @"There is no such query.";
	} else if (![ORMAttribute(query, @"Kind") isEqualToString:@"Derivation"]) {
		why = @"Only a derivation derives a fact type.";
	} else if (![fact isKindOfClass:[ORMFactType class]] || fact.kind != ORMFactTypeOrdinary) {
		why = @"A derivation derives a fact type.";
	} else if (other != nil && ![other.identifier isEqualToString:queryId]) {
		why = [NSString stringWithFormat:@"%@ derives it already.", other.name];
	} else if (ORMHasRolePath(fact.element)) {
		why = @"It has NORMA's own derivation rule.";
	}
	if (why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return NO;
	}
	if ([ORMAttribute(query, @"Of") isEqualToString:factTypeId]) {
		return YES;
	}
	NSXMLElement *was = [_editor xml:ORMAttribute(query, @"Of")];
	NSString *name = ORMAttribute(query, @"Name") ?: @"";
	[_editor change:@"Set Derived Fact Type" with:^{
		ORMRemoveDerivationRule(was);
		ORMSetAttribute(query, @"Of", factTypeId);
		ORMEnsureDerivationRule(self->_editor.document, fact.element, name);
	}];
	return YES;
}

- (BOOL)setDeontic:(BOOL)deontic ofQuery:(NSString *)queryId reason:(NSString **)reason
{
	NSXMLElement *query = [self queryElement:queryId named:@"Query"];
	if (query == nil || ![ORMAttribute(query, @"Kind") isEqualToString:@"Constraint"]) {
		if (reason != NULL) {
			*reason = query == nil ? @"There is no such query." : @"Only a constraint is alethic or deontic.";
		}
		return NO;
	}
	if ([ORMAttribute(query, @"Modality") isEqualToString:@"Deontic"] != deontic) {
		[_editor change:deontic ? @"Make Constraint Deontic" : @"Make Constraint Alethic" with:^{
			ORMSetAttribute(query, @"Modality", deontic ? @"Deontic" : nil);
		}];
	}
	return YES;
}

- (BOOL)setCalculation:(ORMQueryCalculationFunction)function
                ofNode:(NSString *)nodeId
               inQuery:(NSString *)queryId
                reason:(NSString **)reason
{
	NSXMLElement *query = [self queryElement:queryId named:@"Query"];
	NSXMLElement *root = ORMChild(query, Q, @"Node");
	BOOL below = NO;
	for (NSXMLElement *node in ORMDescendants(root, Q, @"Node")) {
		below = below || (node != root && [ORMAttribute(node, @"id") isEqualToString:nodeId]);
	}
	if (query == nil || ![ORMAttribute(query, @"Kind") isEqualToString:@"Calculation"] || !below
	    || (NSUInteger)function >= [ORMCalculationFunctionNames() count]) {
		if (reason != NULL) {
			*reason = query == nil ? @"There is no such query."
				: (![ORMAttribute(query, @"Kind") isEqualToString:@"Calculation"]
				       ? @"Only a calculation computes a value."
				       : (!below ? @"A calculation is of a node below its object type." : @"There is no such function."));
		}
		return NO;
	}
	NSString *name = [ORMCalculationFunctionNames() objectAtIndex:(NSUInteger)function];
	if ([ORMAttribute(query, @"Function") isEqualToString:name] && [ORMAttribute(query, @"Of") isEqualToString:nodeId]) {
		return YES;
	}
	[_editor change:@"Set Calculation" with:^{
		ORMSetAttribute(query, @"Function", name);
		ORMSetAttribute(query, @"Of", nodeId);
	}];
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
	/* A calculation of a node the step takes away is of none. */
	NSXMLElement *query = (NSXMLElement *)[step parent];
	while (query != nil && ![[query localName] isEqualToString:@"Query"]) {
		query = (NSXMLElement *)[query parent];
	}
	NSString *of = ORMAttribute(query, @"Of");
	BOOL takesOf = NO;
	for (NSXMLElement *node in of != nil ? ORMDescendants(step, Q, @"Node") : @[]) {
		takesOf = takesOf || [ORMAttribute(node, @"id") isEqualToString:of];
	}
	[_editor change:@"Remove Query Step" with:^{
		[step detach];
		if (takesOf) {
			ORMSetAttribute(query, @"Of", nil);
		}
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
		if (comparison == nil) {
			ORMSetAttribute(step, @"GroupNode", nil);
			ORMSetAttribute(step, @"CompareAggregate", nil);
			ORMSetAttribute(step, @"CompareGroupNode", nil);
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

/* Whether the node element is the step's parent or above it. */
static BOOL
ORMIsAbove(NSXMLElement *node, NSXMLElement *step)
{
	for (NSXMLNode *at = [step parent]; at != nil; at = [at parent]) {
		if (at == node) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)setGroupNode:(NSString *)nodeId ofStep:(NSString *)stepId reason:(NSString **)reason
{
	NSXMLElement *step = [self queryElement:stepId named:@"Step"];
	NSXMLElement *node = nodeId != nil ? [self queryElement:nodeId named:@"Node"] : nil;
	if (step == nil || (nodeId != nil && (node == nil || !ORMIsAbove(node, step)))) {
		if (reason != NULL) {
			*reason = step == nil ? @"There is no such step." : @"An aggregate is for a node above its step.";
		}
		return NO;
	}
	/* The parent is the default: said by nothing. */
	NSString *value = node != nil && node != (NSXMLElement *)[step parent] ? nodeId : nil;
	if ([ORMAttribute(step, @"GroupNode") ?: @"" isEqualToString:value ?: @""]) {
		return YES;
	}
	[_editor change:@"Set Query Aggregate Group" with:^{
		ORMSetAttribute(step, @"GroupNode", value);
	}];
	return YES;
}

- (BOOL)setComparedAggregate:(ORMQueryAggregate)aggregate
                       group:(NSString *)nodeId
                      ofStep:(NSString *)stepId
                      reason:(NSString **)reason
{
	NSXMLElement *step = [self queryElement:stepId named:@"Step"];
	NSXMLElement *node = nodeId != nil ? [self queryElement:nodeId named:@"Node"] : nil;
	if (step == nil || ORMAttribute(step, @"Count") == nil || (nodeId != nil && (node == nil || !ORMIsAbove(node, step)))) {
		if (reason != NULL) {
			*reason = step == nil ? @"There is no such step."
				: ORMAttribute(step, @"Count") == nil ? @"The step has no aggregate to compare."
				                                      : @"The aggregate compared with is for a node above the step.";
		}
		return NO;
	}
	[_editor change:@"Set Query Compared Aggregate" with:^{
		ORMSetAttribute(step, @"CompareAggregate",
		                nodeId != nil ? [ORMQueryAggregateNames() objectAtIndex:(NSUInteger)aggregate] : nil);
		ORMSetAttribute(step, @"CompareGroupNode", nodeId);
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
