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
 * A plan is data: it is written as a property list and read back
 * (-propertyList, +planWithPropertyList:error:), so it can be made where the
 * model is edited and run where the store is. Names are the Core Data
 * model's: entities, and properties along paths. */

@class ORMQueryPlan;

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

/* A path's value, or a constant: its text as the query has it, and the
 * Core Data attribute type it is of ("Integer 64", "String", "Boolean",
 * "Date", ...), which a backend reads it as. */
@interface ORMPlanValue : NSObject <NSCopying>
+ (instancetype)valueAtPath:(ORMPlanPath *)path;
+ (instancetype)constant:(NSString *)text type:(NSString *)attributeType;
@property (nonatomic, readonly, strong) ORMPlanPath *path;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSString *attributeType;
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
	 * object plan reads: a join on values no relationship makes (an object
	 * type absorbed into the entities that use it). In plan, variable (o1),
	 * where it is set, is the object this plan reads; plan may also name the
	 * variables bound where the match is. A plan that names neither is
	 * uncorrelated: one set of objects for every object of this one. */
	ORMPlanMatches,
};

@interface ORMPlanCondition : NSObject <NSCopying>
+ (instancetype)all:(NSArray<ORMPlanCondition *> *)operands;
+ (instancetype)any:(NSArray<ORMPlanCondition *> *)operands;
+ (instancetype)not:(ORMPlanCondition *)operand;
+ (instancetype)compare:(ORMPlanValue *)left comparison:(NSString *)comparison with:(ORMPlanValue *)right;
+ (instancetype)notNull:(ORMPlanPath *)path;
+ (instancetype)exists:(ORMPlanPath *)collection variable:(NSString *)variable where:(ORMPlanCondition *)condition;
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
@property (nonatomic, readonly, strong) ORMQueryPlan *plan;
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
/* The path to the column's value: the path, and the identifier's key. */
- (ORMPlanPath *)valuePath;
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
/* The entity whose objects are the results; nil when the query reads none. */
@property (nonatomic, readonly, copy) NSString *entityName;
/* What must hold of each; nil: nothing. */
@property (nonatomic, readonly, strong) ORMPlanCondition *condition;
@property (nonatomic, readonly, copy) NSArray<ORMPlanColumn *> *columns;
@property (nonatomic, readonly, copy) NSArray<ORMPlanSort *> *sorts;
/* What the query says that the plan leaves out. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;

/* The plan as a property list, and read back: nil, and why, for one that
 * is no plan, or names what no Core Data model can (a name that is no
 * identifier). */
- (id)propertyList;
+ (instancetype)planWithPropertyList:(id)propertyList error:(NSError **)error;

/* The plan to read: "read Employee\nwhere ...\nlist ...". */
- (NSString *)text;
@end

extern NSString * const ORMQueryPlanErrorDomain;
