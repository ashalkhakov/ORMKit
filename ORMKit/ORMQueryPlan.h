/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* A conceptual query planned against a mapped model: what to read, and what
 * must hold of it, in the model's entities and properties, said for no
 * store in particular. ORMQueryPlanner makes one from an ORMQuery; a
 * backend says it in its own terms: ORMQueryInterpreter runs it against a
 * Core Data store, in as many fetches as it takes, and ORMQueryOData sends
 * it as requests to the service ODataKit makes of the model.
 *
 *   read Employee
 *   where some city.branches as x1 has x1.nr = 52
 *   list self (nr)
 *
 * A plan is a program, as ConQuer-II's are: named sets first, each read by a
 * plan of its own and free to use the ones before it, then the set the
 * plan reads, whose conditions may use them all.
 *
 *   let join1 = read Branch where nr = 52
 *   read Employee
 *   where cityCityname = cityCityname, ... in join1
 *
 * A plan is data: it is written as a property list and read back
 * (-propertyList, +planWithPropertyList:error:), so it can be made where the
 * model is edited and run where the store is. Names are the Core Data
 * model's: entities, and properties along paths. */

@class ORMQueryPlan;

/* A set a plan names (ConQuer-II's named subquery): the objects its own plan
 * reads. Its parameters are what that plan names of the plans using it: the
 * object one of them reads (o1), or a variable bound where it is used; a
 * definition with none is the same set wherever it is used. */
@interface ORMPlanDefinition : NSObject <NSCopying>
+ (instancetype)definitionNamed:(NSString *)name plan:(ORMQueryPlan *)plan;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, strong) ORMQueryPlan *plan;
/* The variables its plan names that it does not bind itself, sorted. */
- (NSArray<NSString *> *)parameters;
@end

/* A step along a path: a property, by name, or a cast to a subentity, which
 * reading the subentity's own properties takes where a store asks for it
 * (OData). */
@interface ORMPlanStep : NSObject <NSCopying>
+ (instancetype)stepWithKey:(NSString *)key;
+ (instancetype)stepAsEntity:(NSString *)entityName;
/* One of the two is set. */
@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly, copy) NSString *entityName;
@end

/* An object or a value: reached from a variable a condition binds (nil: the
 * object read) through properties. */
@interface ORMPlanPath : NSObject <NSCopying>
+ (instancetype)pathFrom:(NSString *)variable steps:(NSArray<ORMPlanStep *> *)steps;
+ (instancetype)pathFrom:(NSString *)variable keys:(NSArray<NSString *> *)keys;
@property (nonatomic, readonly, copy) NSString *variable;
@property (nonatomic, readonly, copy) NSArray<ORMPlanStep *> *steps;
/* The properties, casts left out: "city.branches". */
@property (nonatomic, readonly, copy) NSArray<NSString *> *keys;
- (ORMPlanPath *)pathByAddingKey:(NSString *)key;
- (ORMPlanPath *)pathByAddingCast:(NSString *)entityName;
@end

@class ORMPlanCondition, ORMPlanDefinition;

/* A path's value, a constant, or an aggregate. A constant has its text as
 * the query has it, and the Core Data attribute type it is of ("Integer
 * 64", "String", "Boolean", "Date", ...), which a backend reads it as. */
@interface ORMPlanValue : NSObject <NSCopying>
+ (instancetype)valueAtPath:(ORMPlanPath *)path;
+ (instancetype)constant:(NSString *)text type:(NSString *)attributeType;
/* An aggregate of a bag the plan defines, as ConQuer-II's are (also
 * "value", the one value, and "distinct", how many values there are): the bag a
 * set whose rows are its tuples (the whole query, its aggregates left out,
 * listing the group node and the nodes from it down to the one aggregated;
 * each way they are bound once), function ("count", "sum", "average",
 * "max", "min") of the column for the node aggregated, over the tuples
 * whose column for the group node is what is at groupPath (its identifier,
 * where the column lists one); a count, of those with the column set.
 * "sum of Salary in bag1 where Branch is self.branchCode". */
+ (instancetype)aggregate:(NSString *)function
                       of:(NSString *)column
                       in:(ORMPlanDefinition *)bag
                    where:(NSString *)groupColumn
                       is:(ORMPlanPath *)groupPath;
@property (nonatomic, readonly, strong) ORMPlanPath *path;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSString *attributeType;
/* An aggregate's: its function, its bag, and the columns (their nodes'
 * ids) it is of and grouped by, and where the group's object is. */
@property (nonatomic, readonly, copy) NSString *function;
@property (nonatomic, readonly, strong) ORMPlanDefinition *bag;
@property (nonatomic, readonly, copy) NSString *column;
@property (nonatomic, readonly, copy) NSString *groupColumn;
@property (nonatomic, readonly, strong) ORMPlanPath *groupPath;
@end

typedef NS_ENUM(NSInteger, ORMPlanConditionKind) {
	/* operands, all or any of them. */
	ORMPlanAnd,
	ORMPlanOr,
	/* operand does not hold. */
	ORMPlanNot,
	/* left comparison right: "=", "<>", "<", "<=", ">", ">=". */
	ORMPlanCompare,
	/* path reaches something: a relationship set, an attribute with a value. */
	ORMPlanNotNull,
	/* Some member of the collection at path, bound to variable, meets
	 * operand (nil: any member). */
	ORMPlanExists,
	/* The members of the collection at path meeting operand (nil: all of
	 * them), bound to variable, counted: count comparison number. */
	ORMPlanCount,
	/* function ("sum", "average", "max", "min") of the value at valuePath
	 * (from variable, each member of the collection at path meeting operand,
	 * nil: all) comparison constant. */
	ORMPlanAggregate,
	/* The object at path is of the entity, or of one of its subentities. */
	ORMPlanIsOf,
	/* The objects at path and otherPath are one. */
	ORMPlanSame,
	/* The object at path is among those the trail of keys reaches from the
	 * object read (otherPath, where it is another: an enclosing plan's, o1):
	 * a node met before, out of the scope it was met in. */
	ORMPlanAmong,
	/* The values at the pairs' paths, ours and theirs, equal those of some
	 * object of a set (definition, or an unnamed plan): a join on values no
	 * relationship makes (an object type absorbed into the entities that use
	 * it). In the set's plan, variable (o1), where it is set, is the object
	 * this plan reads; it may also name the variables bound where the match
	 * is. A set that names neither is uncorrelated: the same for every object
	 * of this one. */
	ORMPlanMatches,
	/* Maybe: each member of the collection at path (or the object a to-one
	 * reaches), bound to variable, that meets operand (nil: each); none, and
	 * the variable unbound, when none does. Asks nothing of the object
	 * read; what it binds is what the columns below it list (an outer
	 * join). */
	ORMPlanMaybe,
};

@interface ORMPlanCondition : NSObject <NSCopying>
+ (instancetype)all:(NSArray<ORMPlanCondition *> *)operands;
+ (instancetype)any:(NSArray<ORMPlanCondition *> *)operands;
+ (instancetype)not:(ORMPlanCondition *)operand;
+ (instancetype)compare:(ORMPlanValue *)left comparison:(NSString *)comparison with:(ORMPlanValue *)right;
+ (instancetype)notNull:(ORMPlanPath *)path;
+ (instancetype)exists:(ORMPlanPath *)collection variable:(NSString *)variable where:(ORMPlanCondition *)condition;
+ (instancetype)maybe:(ORMPlanPath *)collection variable:(NSString *)variable where:(ORMPlanCondition *)condition;
+ (instancetype)count:(ORMPlanPath *)collection variable:(NSString *)variable where:(ORMPlanCondition *)condition
           comparison:(NSString *)comparison number:(NSUInteger)number;
+ (instancetype)aggregate:(NSString *)function
                       of:(ORMPlanPath *)valuePath
                     over:(ORMPlanPath *)collection
                 variable:(NSString *)variable
                    where:(ORMPlanCondition *)condition
               comparison:(NSString *)comparison
                 constant:(ORMPlanValue *)constant;
+ (instancetype)isOf:(ORMPlanPath *)path entity:(NSString *)entityName;
+ (instancetype)same:(ORMPlanPath *)path as:(ORMPlanPath *)otherPath;
+ (instancetype)among:(ORMPlanPath *)path trail:(NSArray<NSString *> *)keys;
/* The trail from another object than the one read: an enclosing plan's. */
+ (instancetype)among:(ORMPlanPath *)path trail:(NSArray<NSString *> *)keys from:(ORMPlanPath *)base;
/* Each pair: @[ our path, their path, from the object plan reads ]. */
+ (instancetype)matches:(ORMQueryPlan *)plan pairs:(NSArray<NSArray<ORMPlanPath *> *> *)pairs;
/* The same, plan naming the object this one reads as outer. */
+ (instancetype)matches:(ORMQueryPlan *)plan pairs:(NSArray<NSArray<ORMPlanPath *> *> *)pairs outer:(NSString *)variable;
/* The same of a set the plan defines, by its name. */
+ (instancetype)matchesDefinition:(ORMPlanDefinition *)definition
                            pairs:(NSArray<NSArray<ORMPlanPath *> *> *)pairs
                            outer:(NSString *)variable;
/* The variables the condition names that it does not bind itself: those
 * bound around it, or an enclosing plan's object. */
- (NSSet<NSString *> *)freeVariables;

@property (nonatomic, readonly) ORMPlanConditionKind kind;
@property (nonatomic, readonly, copy) NSArray<ORMPlanCondition *> *operands;
/* Not's, and the condition on the members of Exists, Count, Aggregate. */
@property (nonatomic, readonly, strong) ORMPlanCondition *operand;
@property (nonatomic, readonly, strong) ORMPlanValue *left;
@property (nonatomic, readonly, strong) ORMPlanValue *right;
@property (nonatomic, readonly, copy) NSString *comparison;
@property (nonatomic, readonly, strong) ORMPlanPath *path;
@property (nonatomic, readonly, strong) ORMPlanPath *otherPath;
@property (nonatomic, readonly, copy) NSString *variable;
@property (nonatomic, readonly) NSUInteger number;
@property (nonatomic, readonly, copy) NSString *function;
@property (nonatomic, readonly, strong) ORMPlanPath *valuePath;
@property (nonatomic, readonly, strong) ORMPlanValue *constant;
@property (nonatomic, readonly, copy) NSString *entityName;
@property (nonatomic, readonly, copy) NSArray<NSString *> *trail;
/* Matches': the set's plan, its definition's where it is one. */
@property (nonatomic, readonly, strong) ORMQueryPlan *plan;
@property (nonatomic, readonly, strong) ORMPlanDefinition *definition;
@property (nonatomic, readonly, copy) NSArray<NSArray<ORMPlanPath *> *> *pairs;
@end

/* A ticked node: its title, the query node, and where it is: from the
 * variable its node is bound to where a condition binds it (x1, a member
 * meeting the conditions), else from the object read, through what a row
 * takes each of (a maybe's to-many: none, one, or each); and the same as a
 * trail of keys from the object read. An entity's by its identifier's key,
 * where it has one. */
@interface ORMPlanColumn : NSObject <NSCopying>
+ (instancetype)columnTitled:(NSString *)title
                        node:(NSString *)nodeId
                        path:(ORMPlanPath *)path
                       trail:(NSArray<NSString *> *)trail
                  identifier:(NSString *)identifierKey;
/* A column from the object read: its trail is its path's keys. */
+ (instancetype)columnTitled:(NSString *)title node:(NSString *)nodeId path:(ORMPlanPath *)path
                  identifier:(NSString *)identifierKey;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *nodeId;
@property (nonatomic, readonly, strong) ORMPlanPath *path;
@property (nonatomic, readonly, copy) NSArray<NSString *> *trail;
@property (nonatomic, readonly, copy) NSString *identifierKey;
/* An entity's column where no one attribute identifies it: the key paths,
 * from the column's object, to the values that do, in its reference
 * scheme's order. A row then has those values, as a list, not the object.
 * Set once, as the planner makes the column. */
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *identifierParts;
/* The column's value from the object at its value path: the object, or the
 * list of its identifying parts' values (NSNull where one is missing). */
- (id)valueOf:(id)object at:(id (^)(id object, NSArray<NSString *> *keys))valueAt;
/* The path to the column's value: the path, and the identifier's key; nil
 * for a computed column. */
- (ORMPlanPath *)valuePath;
/* A column computed for each object read, not read from a path: a
 * calculation's value (docs/RULES.md), an aggregate of a bag the plan
 * defines. */
+ (instancetype)columnTitled:(NSString *)title node:(NSString *)nodeId value:(ORMPlanValue *)value;
@property (nonatomic, readonly, strong) ORMPlanValue *value;
@end

@interface ORMPlanSort : NSObject <NSCopying>
+ (instancetype)sortBy:(ORMPlanPath *)path ascending:(BOOL)ascending;
@property (nonatomic, readonly, strong) ORMPlanPath *path;
@property (nonatomic, readonly) BOOL ascending;
@end

@interface ORMQueryPlan : NSObject <NSCopying>
+ (instancetype)planReading:(NSString *)entityName
                      where:(ORMPlanCondition *)condition
                    columns:(NSArray<ORMPlanColumn *> *)columns
                      sorts:(NSArray<ORMPlanSort *> *)sorts
                      notes:(NSArray<NSString *> *)notes;
/* The same, after the sets it defines, in order: each may use those before. */
+ (instancetype)planReading:(NSString *)entityName
                      where:(ORMPlanCondition *)condition
                    columns:(NSArray<ORMPlanColumn *> *)columns
                      sorts:(NSArray<ORMPlanSort *> *)sorts
                      notes:(NSArray<NSString *> *)notes
                definitions:(NSArray<ORMPlanDefinition *> *)definitions;
/* The sets it names, in order. */
@property (nonatomic, readonly, copy) NSArray<ORMPlanDefinition *> *definitions;
/* The entity whose objects are the results; nil when the query reads none. */
@property (nonatomic, readonly, copy) NSString *entityName;
/* What must hold of each; nil: nothing. */
@property (nonatomic, readonly, strong) ORMPlanCondition *condition;
@property (nonatomic, readonly, copy) NSArray<ORMPlanColumn *> *columns;
/* Whether a column lists the object read itself: then no row of one
 * object is another's. */
- (BOOL)listsTheObjectRead;
/* Whether equal rows are of objects read one after another, the objects
 * in the order (each part a key path from the object read; the key's
 * parts last, when it is given): a prefix of the order determines the
 * rows, and they it. A listed object's identifier determines what is
 * reached from it through to-ones; the whole key, everything. */
- (BOOL)rowsFollowOrder:(NSArray<NSArray<NSString *> *> *)order key:(NSArray<NSString *> *)key;
/* The same for its sorts, no key. */
- (BOOL)ordersItsRows;
@property (nonatomic, readonly, copy) NSArray<ORMPlanSort *> *sorts;
/* What the query says that the plan leaves out. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;

/* The plan as a property list, and read back: nil, and why, for one that
 * is no plan, names what no Core Data model can (a name that is no
 * identifier), or uses a set it does not define before. */
- (id)propertyList;
+ (instancetype)planWithPropertyList:(id)propertyList error:(NSError **)error;

/* The plan to read: "let join1 = ...\nread Employee\nwhere ...\nlist ...". */
- (NSString *)text;
@end

extern NSString * const ORMQueryPlanErrorDomain;
