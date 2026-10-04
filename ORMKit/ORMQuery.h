/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"
#import "ORMLogic.h"

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

typedef NS_ENUM(NSInteger, ORMQuerySort) {
	ORMQueryUnsorted,
	ORMQueryAscending,
	ORMQueryDescending,
};

@class ORMQueryStep;

/* An object type in the outline. */
@interface ORMQueryNode : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, strong) ORMObjectType *objectType;
/* The role it plays in the step above it; nil for the root. */
@property (nonatomic, readonly, strong) ORMRole *role;
@property (nonatomic, readonly, weak) ORMQueryStep *step;
/* Ticked: listed in the result. */
@property (nonatomic, readonly) BOOL isProjected;
/* A condition on it: "=", "<>", "<", "<=", ">", ">=", and the value, as
 * typed (an entity's is its identifier's). nil for none. */
@property (nonatomic, readonly, copy) NSString *comparison;
@property (nonatomic, readonly, copy) NSString *value;
/* A condition comparing it with another node instead of a value: "Country2
 * <> Country1". */
@property (nonatomic, readonly, weak) ORMQueryNode *comparedNode;
/* ConQuer's subscript: nodes of one object type with the same label are the
 * same object ("lives in City1 ... lives in City1"). nil for none. */
@property (nonatomic, readonly, copy) NSString *label;
/* Its name and label: "City1". */
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

/* The model's queries, read from its document. */
+ (NSArray<ORMQuery *> *)queriesInModel:(ORMModel *)model;
+ (ORMQuery *)queryWithId:(NSString *)identifier inModel:(ORMModel *)model;
/* The roles a query can go on through from a node of the type: those it
 * and its supertypes play, its subtype links included, its reference mode
 * not (a condition on the node compares its identifier). */
+ (NSArray<ORMRole *> *)rolesFrom:(ORMObjectType *)type;

/* The node an occurrence is the same object as: the first of its object
 * type and label, in outline order; the node itself when it is that one, or
 * has no label. */
- (ORMQueryNode *)firstOccurrenceOf:(ORMQueryNode *)node;
/* Every node, depth first; the ticked ones. */
- (NSArray<ORMQueryNode *> *)nodes;
- (NSArray<ORMQueryNode *> *)projectedNodes;
/* ConQuer's outline, as above. */
- (NSString *)outlineText;
/* The query as a relation: its formula over a variable for each node, its
 * columns the ticked nodes', in outline order. */
- (ORMRelation *)relation;
/* The variable of each node in -relation, by node id. */
- (NSDictionary<NSString *, ORMVariable *> *)variablesOfRelation:(ORMRelation *)relation;
/* ConQuer's names for them: "count", "total", "avg", "max", "min". */
+ (NSString *)nameOfAggregate:(ORMQueryAggregate)aggregate;
/* What a step reads as from the node above: "was awarded {1} in {2}",
 * with {n} the step's nth node. */
+ (NSString *)readingOfStep:(ORMQueryStep *)step;
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
- (void)setSortOrder:(ORMQuerySort)order ofNode:(NSString *)nodeId;
/* comparison nil clears the count. */
- (BOOL)setCount:(NSString *)comparison
           value:(NSUInteger)value
          ofStep:(NSString *)stepId
          reason:(NSString **)reason;
@end
