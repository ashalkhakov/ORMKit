/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"
#import "ORMLogic.h"
#import "ORMQueryExpression.h"

/* Conceptual queries, after Bloesch and Halpin's ConQuer: a query is a path
 * through the model's fact types, an outline of object types joined by
 * the predicates they play in, with the ones to list ticked and conditions
 * on the way, so that it is said in the model's own terms and not in the
 * store's (Core Data's entities, attributes and key paths).
 *
 *   ✓Academic
 *     + was awarded ✓Degree in Year
 *       + has Rating > 5
 *
 * lists each academic, and the degrees, for the academics awarded a degree
 * that has a rating above 5. Each line is a step from the object type above
 * it through a fact type, to the object types playing its other roles;
 * moving through an object type is a conceptual join. A step may be "not"
 * (none such) or "maybe" (listed if there is one, the outer join), may
 * count ("count(Language) > 1": more than one), and a node's steps may be
 * alternatives (or) rather than all required (and).
 *
 * As logic a query is a relation, its ticked object types the columns: the
 * verbalizer says it in FORML (-[ORMVerbalizer sentenceForQuery:]) and
 * ORMQueryPlanner plans it against a mapped model, for ORMQueryInterpreter to
 * run against a Core Data store and ORMQueryOData to send to a service.
 *
 * Queries live in the .orm, in ORMKit's own namespace beside the mappings,
 * and every change to one goes through the editor, so it is undone with
 * the model. */

typedef NS_ENUM(NSInteger, ORMQueryOperator) {
	/* The step holds. */
	ORMQueryAnd,
	/* No such step: "not was awarded Degree". */
	ORMQueryNot,
	/* The step if there is one: listed, but nothing is left out for it. */
	ORMQueryMaybe,
};

/* What a step's aggregate condition computes over the objects its node
 * reaches for each one above it: ConQuer's count, total, avg, max, min. */
typedef NS_ENUM(NSInteger, ORMQueryAggregate) {
	ORMQueryCount,
	ORMQueryTotal,
	ORMQueryAverage,
	ORMQueryMaximum,
	ORMQueryMinimum,
};

/* What a query is for (docs/RULES.md): listing what it finds; a rule,
 * every row it finds a violation; or a value of each object of its root
 * type, computed from a node over its rows for that object. */
typedef NS_ENUM(NSInteger, ORMQueryKind) {
	ORMQueryList,
	ORMQueryConstraint,
	ORMQueryCalculation,
	/* Its rows are a fact type's facts (docs/DERIVATION.md). */
	ORMQueryDerivation,
};

/* What a calculation computes of its node's values: the one value, or an
 * aggregate of them. */
typedef NS_ENUM(NSInteger, ORMQueryCalculationFunction) {
	ORMCalculationValue,
	ORMCalculationCount,
	ORMCalculationTotal,
	ORMCalculationAverage,
	ORMCalculationMaximum,
	ORMCalculationMinimum,
};

typedef NS_ENUM(NSInteger, ORMQuerySort) {
	ORMQueryUnsorted,
	ORMQueryAscending,
	ORMQueryDescending,
};

@class ORMQueryStep;

/* An object type in the outline; or a value node (docs/EXPRESSIONS.md),
 * computed from other nodes rather than reached by a step: "Length =
 * Quantity2 - Quantity1", under the node it is computed for. */
@interface ORMQueryNode : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, strong) ORMObjectType *objectType;
/* The role it plays in the step above it; nil for the root. */
@property (nonatomic, readonly, strong) ORMRole *role;
@property (nonatomic, readonly, weak) ORMQueryStep *step;
/* Ticked: listed in the result. */
@property (nonatomic, readonly) BOOL isProjected;
/* A derivation's column: the role of its fact type it is, where the query
 * says (a NORMA rule's projections are not in outline order); nil for the
 * role at its place. */
@property (nonatomic, readonly, weak) ORMRole *derivedRole;
/* A condition on it: "=", "<>", "<", "<=", ">", ">=", and the value, as
 * typed (an entity's is its identifier's); or "in", one of a list ("in
 * ('Maintenance', 'Repair')"), the value the list. nil for none. */
@property (nonatomic, readonly, copy) NSString *comparison;
@property (nonatomic, readonly, copy) NSString *value;
/* The values it is compared with: the value; for "in", each of the list
 * the value is ("'Maintenance', 'Repair'", "4, 5"), unquoted. */
- (NSArray<NSString *> *)comparedValues;
/* A condition comparing it with another node instead of a value: "Country2
 * <> Country1". */
@property (nonatomic, readonly, weak) ORMQueryNode *comparedNode;
/* ConQuer's subscript: nodes of one object type with the same label are the
 * same object ("lives in City1 ... lives in City1"). nil for none. */
@property (nonatomic, readonly, copy) NSString *label;
/* A value node's: its name, what it computes, and the node it is under
 * (its objectType the value type it is of; no role, no step). */
@property (nonatomic, readonly) BOOL isValue;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, strong) ORMQueryExpression *expression;
@property (nonatomic, readonly, weak) ORMQueryNode *valueOf;
/* The value nodes under it, in order. */
@property (nonatomic, readonly, copy) NSArray<ORMQueryNode *> *values;
/* Its name and label: "City1"; a value node's name. */
- (NSString *)designation;
/* Its steps, each from it; alternatives when combinesWithOr. */
@property (nonatomic, readonly, copy) NSArray<ORMQueryStep *> *steps;
@property (nonatomic, readonly) BOOL combinesWithOr;
/* The order the results are listed in, by it. */
@property (nonatomic, readonly) ORMQuerySort sortOrder;
/* Whether its value is a number, so its condition is not quoted. */
- (BOOL)isNumeric;
@end

/* A fact type, entered by the role the node above plays. */
@interface ORMQueryStep : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, strong) ORMFactType *factType;
@property (nonatomic, readonly, strong) ORMRole *entryRole;
@property (nonatomic, readonly, weak) ORMQueryNode *parent;
@property (nonatomic, readonly) ORMQueryOperator operatorKind;
/* The object types playing its other roles, in the fact type's order. */
@property (nonatomic, readonly, copy) NSArray<ORMQueryNode *> *nodes;
/* An aggregate condition, for each node above: "count(Language) > 1",
 * "total(Salary) > 1000000". Its comparison nil for none. The node is one
 * of the step's, or below them; the step's first node by default. */
@property (nonatomic, readonly) ORMQueryAggregate aggregate;
@property (nonatomic, readonly, weak) ORMQueryNode *aggregateNode;
@property (nonatomic, readonly, copy) NSString *countComparison;
@property (nonatomic, readonly, copy) NSString *aggregateValue;
/* The value as a whole number, for a count. */
@property (nonatomic, readonly) NSUInteger countValue;
/* What the aggregate is for (ConQuer-II's for-clause): a node above the
 * step, its parent unless it says; "count(Language) for Branch" counts the
 * languages of all a branch's employees. */
@property (nonatomic, readonly, weak) ORMQueryNode *groupNode;
/* An aggregate the step's is compared with, rather than a value: of the
 * same node, for another node above ("max(Rating) for Employee >
 * avg(Rating) for Department"). comparesAggregates NO for none. */
@property (nonatomic, readonly) BOOL comparesAggregates;
@property (nonatomic, readonly) ORMQueryAggregate comparedAggregate;
@property (nonatomic, readonly, weak) ORMQueryNode *comparedGroupNode;
/* Through a subtype link: "is Professor". */
- (BOOL)isSubtyping;
@end

@interface ORMQuery : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, strong) ORMQueryNode *root;
/* NO when something it went through is no longer in the model: the steps
 * that did are left out. */
@property (nonatomic, readonly) BOOL isComplete;
/* What it is for. A constraint's rows are its violations: alethic, or
 * deontic (a rule to be told of, not enforced). A calculation's value for
 * each object of the root's type is the function of calculatedNode's
 * values over its rows for that object (nil node: none yet). */
@property (nonatomic, readonly) ORMQueryKind kind;
@property (nonatomic, readonly) BOOL isDeontic;
@property (nonatomic, readonly) ORMQueryCalculationFunction calculationFunction;
@property (nonatomic, readonly, weak) ORMQueryNode *calculatedNode;
/* A derivation's fact type: its listed columns are that fact type's roles,
 * in its order (nil: none yet). */
@property (nonatomic, readonly, weak) ORMFactType *derivedFactType;
/* A derivation's subtype: its rows are the instances of its root's type
 * that are of the subtype (nil: it derives a fact type, or none yet). */
@property (nonatomic, readonly, weak) ORMObjectType *derivedSubtype;
/* "value", "count", "total", "avg", "max", "min". */
+ (NSString *)nameOfCalculationFunction:(ORMQueryCalculationFunction)function;

/* The model's queries, read from its document. */
+ (NSArray<ORMQuery *> *)queriesInModel:(ORMModel *)model;
+ (ORMQuery *)queryWithId:(NSString *)identifier inModel:(ORMModel *)model;
/* The derivation of the fact type, if a query derives it. */
+ (ORMQuery *)derivationOf:(ORMFactType *)factType inModel:(ORMModel *)model;
/* The derivation of the subtype, if a query derives it. */
+ (ORMQuery *)derivationOfSubtype:(ORMObjectType *)subtype inModel:(ORMModel *)model;
/* The model's derivations: its derivation queries, and the rules NORMA
 * keeps as a role path, read as queries where one is plain (one path, no
 * split, calculation, condition, negation or outer join, each role
 * projected), for fact types no query derives. Such a query is not in the
 * document: its id is the rule's path's. */
+ (NSArray<ORMQuery *> *)derivationsInModel:(ORMModel *)model;
/* A derivation's ticked nodes, in the order of its fact type's roles: each
 * the role its node says it is, else the one at its place; nil when they
 * are not one of each role. */
- (NSArray<ORMQueryNode *> *)derivedColumns;
/* The same, a role's columns each: one, or for a role played by a type
 * identified by several values (Money: an amount and a currency), a
 * ticked node for each, in its identifier's order, of each part's type.
 * nil where they are not that. */
- (NSArray<NSArray<ORMQueryNode *> *> *)derivedColumnGroups;
/* The roles of the player's identifier where it is identified by several
 * values, in order; nil otherwise. */
+ (NSArray<ORMRole *> *)partRolesOf:(ORMObjectType *)player;
/* The query as the planner plans it (docs/DERIVATION.md): each step through
 * a derived fact type that is not stored put as its derivation's path, the
 * derivation's columns for the step's roles the step's nodes. The query
 * itself where there is none; nil, and why in notes, where a step cannot
 * be expanded (a rule NORMA keeps as a path that is not plain, a
 * derivation through itself, a path that is not plain). */
- (ORMQuery *)expandedInModel:(ORMModel *)model notes:(NSMutableArray<NSString *> *)notes;
/* The roles a query can go on through from a node of the type: those it
 * and its supertypes play, its subtype links included, its reference mode
 * not (a condition on the node compares its identifier). */
+ (NSArray<ORMRole *> *)rolesFrom:(ORMObjectType *)type;

/* The node an occurrence is the same object as: the first of its object
 * type and label, in outline order; the node itself when it is that one, or
 * has no label. */
- (ORMQueryNode *)firstOccurrenceOf:(ORMQueryNode *)node;
/* Every node, depth first, each node's value nodes after what its steps
 * reach; the ticked ones. */
- (NSArray<ORMQueryNode *> *)nodes;
- (NSArray<ORMQueryNode *> *)projectedNodes;
/* ConQuer's outline, as above. */
- (NSString *)outlineText;
/* The query as a relation: its formula over a variable for each node (its
 * variables, by node id), its columns the ticked nodes', in outline order. */
- (ORMRelation *)relation;
/* ConQuer's names for them: "count", "total", "avg", "max", "min". */
+ (NSString *)nameOfAggregate:(ORMQueryAggregate)aggregate;
/* What a step reads as from the node above: "was awarded {1} in {2}",
 * with {n} the step's nth node. */
+ (NSString *)readingOfStep:(ORMQueryStep *)step;
/* The same of a step not made: entered by the role, a node for each of the
 * others but an implicit Boolean's, in the fact type's order. */
+ (NSString *)readingFrom:(ORMRole *)entry nodeRoles:(NSArray<ORMRole *> *)nodeRoles;
+ (NSArray<ORMRole *> *)nodeRolesFrom:(ORMRole *)entry;
@end

/* A document's queries, edited: each change through the editor, undone with
 * the model. */
@interface ORMQueryEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, strong) ORMEditor *editor;

/* A query starting at the object type, which is ticked. Its id. */
- (NSString *)addQueryNamed:(NSString *)name from:(NSString *)objectTypeId reason:(NSString **)reason;
- (void)removeQuery:(NSString *)queryId;
- (BOOL)renameQuery:(NSString *)queryId to:(NSString *)name reason:(NSString **)reason;
/* What the query is for. Leaving a kind drops what was only its (a
 * constraint's modality, a calculation's function and node). */
- (BOOL)setKind:(ORMQueryKind)kind ofQuery:(NSString *)queryId reason:(NSString **)reason;
/* The fact type a derivation derives, written for NORMA too as the fact
 * type's DerivationRule (docs/DERIVATION.md): its words the query's, which
 * a note the fact type has gives way to; whether it is partly derived and
 * stored stays. NO for a query of another kind, a fact type another query
 * derives, or one with NORMA's own rule. */
- (BOOL)setDerivedFactType:(NSString *)factTypeId ofQuery:(NSString *)queryId reason:(NSString **)reason;
/* The subtype a derivation derives: each instance of the query's root
 * type that it finds is one. Its root is a supertype of it. The subtype
 * keeps its rule's words, or is given the query's name for them, as
 * NORMA's SubtypeDerivationRule. NO for a query of another kind, a type no
 * supertype of the root, one another query derives, or one with NORMA's own
 * path. */
- (BOOL)setDerivedSubtype:(NSString *)objectTypeId ofQuery:(NSString *)queryId reason:(NSString **)reason;
/* A constraint's modality; NO for a query of another kind. */
- (BOOL)setDeontic:(BOOL)deontic ofQuery:(NSString *)queryId reason:(NSString **)reason;
/* A calculation's function, of a node of the query below its root; NO for
 * a query of another kind or a node not below the root. */
- (BOOL)setCalculation:(ORMQueryCalculationFunction)function
                ofNode:(NSString *)nodeId
               inQuery:(NSString *)queryId
                reason:(NSString **)reason;
/* A step from the node through the role its object type (or a supertype)
 * plays, with a node for each other role. Its id. */
- (NSString *)addStepTo:(NSString *)nodeId through:(NSString *)roleId reason:(NSString **)reason;
- (void)removeStep:(NSString *)stepId;
- (void)setProjected:(BOOL)projected ofNode:(NSString *)nodeId;
/* comparison nil clears the condition. */
- (BOOL)setCondition:(NSString *)comparison value:(NSString *)value ofNode:(NSString *)nodeId reason:(NSString **)reason;
/* A condition comparing the node with another of the query, of the same
 * object type. */
- (BOOL)setCondition:(NSString *)comparison
              toNode:(NSString *)otherNodeId
              ofNode:(NSString *)nodeId
              reason:(NSString **)reason;
/* nil or empty takes the label away. */
- (void)setLabel:(NSString *)label ofNode:(NSString *)nodeId;
- (void)setCombinesWithOr:(BOOL)flag ofNode:(NSString *)nodeId;
- (void)setOperator:(ORMQueryOperator)operatorKind ofStep:(NSString *)stepId;
/* An aggregate of the node (nil: the step's first), one of the step's or
 * below them; comparison nil clears it. A total or average is of numbers. */
- (BOOL)setAggregate:(ORMQueryAggregate)aggregate
              ofNode:(NSString *)nodeId
          comparison:(NSString *)comparison
               value:(NSString *)value
              ofStep:(NSString *)stepId
              reason:(NSString **)reason;
/* What the step's aggregate is for: the node, the step's parent or one
 * above it; nil for the parent. */
- (BOOL)setGroupNode:(NSString *)nodeId ofStep:(NSString *)stepId reason:(NSString **)reason;
/* The aggregate the step's is compared with, of the same node, for a node
 * the step's parent or above it; nil takes it away (the value again). */
- (BOOL)setComparedAggregate:(ORMQueryAggregate)aggregate
                       group:(NSString *)nodeId
                      ofStep:(NSString *)stepId
                      reason:(NSString **)reason;
- (void)setSortOrder:(ORMQuerySort)order ofNode:(NSString *)nodeId;
/* A value node under the node, computed by the expression as the outline
 * says it (each node by its designation: "Quantity2 - Quantity1"), of the
 * value type (nil: the first node it uses' type). Listed, compared and
 * sorted as any node is, by the methods above. Its id; nil, and why, for a
 * name a node of the query has, an expression that is none or names a node
 * not before it, arithmetic of what is not a number, or a type that is no
 * value type. */
- (NSString *)addValueNamed:(NSString *)name
                         to:(NSString *)nodeId
                 expression:(NSString *)expression
                       type:(NSString *)valueTypeId
                     reason:(NSString **)reason;
/* What it computes, said again; NO and why as above. */
- (BOOL)setExpression:(NSString *)expression ofValue:(NSString *)valueId reason:(NSString **)reason;
/* NO, and why, while another node uses it. */
- (BOOL)removeValue:(NSString *)valueId reason:(NSString **)reason;
/* comparison nil clears the count. */
- (BOOL)setCount:(NSString *)comparison
           value:(NSUInteger)value
          ofStep:(NSString *)stepId
          reason:(NSString **)reason;
@end
