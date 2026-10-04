/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"

/* What NORMA keeps beyond the plain model, read as ORMModel reads the
 * rest: role paths (a constraint's join path, a fact type's or subtype's
 * derivation rule), the calculations and conditions on them, and sample
 * populations.
 *
 * A role path starts at an object type and walks role by role through
 * fact types: a role entered from the path's current object type joins
 * (PostInnerJoin), and the other roles of the same fact type lead on
 * (SameFactType). It may split into sub-paths that all hold (and), one
 * holds (or), or exactly one holds (xor), negated or not. Projections say
 * which point of the path stands for which role of what the path is for. */

@class ORMRolePath, ORMCalculation;

typedef NS_ENUM(NSInteger, ORMPathedRolePurpose) {
	/* The path's first role, entered without a join. */
	ORMPathStartRole,
	/* Another role of the fact type the path is in. */
	ORMPathSameFactType,
	/* A role of another fact type, joined on what the path is at. */
	ORMPathInnerJoin,
	/* As an inner join, but the path goes on when nothing joins. */
	ORMPathOuterJoin,
};

typedef NS_ENUM(NSInteger, ORMPathSplit) {
	ORMPathSplitAnd,
	ORMPathSplitOr,
	ORMPathSplitXor,
};

@interface ORMPathedRole : ORMElement
@property (nonatomic, readonly, weak) ORMRole *role;
@property (nonatomic, readonly) ORMPathedRolePurpose purpose;
/* The fact does not hold: "...that does not track lot numbers". */
@property (nonatomic, readonly) BOOL isNegated;
/* A condition on the value at this point of the path. */
@property (nonatomic, readonly, strong) ORMValueConstraint *valueConstraint;
/* Another point of the path the same instance is at. */
@property (nonatomic, readonly, weak) ORMPathedRole *correlatedWith;
@property (nonatomic, readonly, weak) ORMRolePath *path;
@end

@interface ORMRolePath : ORMElement
/* Where a lead path starts; nil for a sub-path, which goes on from its
 * parent. */
@property (nonatomic, readonly, weak) ORMObjectType *rootObjectType;
/* The id projections give the root by. */
@property (nonatomic, readonly, copy) NSString *rootId;
@property (nonatomic, readonly) BOOL rootIsNegated;
@property (nonatomic, readonly, strong) ORMValueConstraint *rootValueConstraint;
@property (nonatomic, readonly, copy) NSArray<ORMPathedRole *> *pathedRoles;
@property (nonatomic, readonly, copy) NSArray<ORMRolePath *> *subPaths;
@property (nonatomic, readonly) ORMPathSplit split;
@property (nonatomic, readonly) BOOL splitIsNegated;
@property (nonatomic, readonly, weak) ORMRolePath *parent;
/* The lead path this one is part of. */
- (ORMRolePath *)leadPath;
@end

typedef NS_ENUM(NSInteger, ORMPathSourceKind) {
	ORMPathSourceRoot,
	ORMPathSourcePathedRole,
	ORMPathSourceCalculation,
	ORMPathSourceConstant,
};

/* Where a value comes from: a path's root, a point of a path, a
 * calculation, or a constant. */
@interface ORMPathSource : NSObject
@property (nonatomic, readonly) ORMPathSourceKind kind;
@property (nonatomic, readonly, weak) ORMRolePath *root;
@property (nonatomic, readonly, weak) ORMPathedRole *pathedRole;
@property (nonatomic, readonly, weak) ORMCalculation *calculation;
@property (nonatomic, readonly, copy) NSString *constant;
/* The object type of the value: the root's, or the role's player. */
- (ORMObjectType *)objectType;
@end

/* A function applied along a path: "count", "sum", "add", "greaterThan". */
@interface ORMCalculation : ORMElement
@property (nonatomic, readonly, copy) NSString *functionName;
/* A condition: true or false, not a value. */
@property (nonatomic, readonly) BOOL isBoolean;
@property (nonatomic, readonly, copy) NSArray<ORMPathSource *> *inputs;
@property (nonatomic, readonly, copy) NSArray<NSString *> *parameterNames;
/* Aggregates: over what each group is counted. */
@property (nonatomic, readonly, copy) NSArray<ORMPathSource *> *aggregationContext;
@property (nonatomic, readonly) BOOL isAggregate;
@end

/* What owns role paths: a join path or a derivation rule. */
@interface ORMRolePathOwner : ORMElement
@property (nonatomic, readonly, copy) NSArray<ORMRolePath *> *paths;
@property (nonatomic, readonly, copy) NSArray<ORMCalculation *> *calculations;
/* Boolean calculations that must hold for the path to. */
@property (nonatomic, readonly, copy) NSArray<ORMCalculation *> *conditions;
/* What each target is projected from: a join path's targets are the ids of
 * its constraint sequence's role uses; a derivation rule's are fact type
 * role ids. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, ORMPathSource *> *projections;
@end

@interface ORMDerivationRule : ORMRolePathOwner
/* Partly derived: some instances are asserted, others derived. */
@property (nonatomic, readonly) BOOL isPartial;
/* Derived instances are stored once derived. */
@property (nonatomic, readonly) BOOL isStored;
/* The modeller's own words, where there is no path or beside it. */
@property (nonatomic, readonly, copy) NSString *informalText;
/* A subtype's rule (each instance is by definition one) rather than a
 * fact type's. */
@property (nonatomic, readonly) BOOL isSubtypeRule;
@end

@class ORMFactInstance;

/* An instance of the sample population. */
@interface ORMInstance : ORMElement
@property (nonatomic, readonly, weak) ORMObjectType *objectType;
/* A value type instance's value, as the file has it; nil for an entity's. */
@property (nonatomic, readonly, copy) NSString *value;
/* An entity instance's identifying instances, by the role of its preferred
 * identifier each plays (the role's id): its reference mode's value, or the
 * parts of a composite identifier. */
- (NSDictionary<NSString *, ORMInstance *> *)identifyingInstancesByRole;
/* A subtype instance's supertype instance, which it is; nil for others. */
- (ORMInstance *)supertypeInstance;
/* An objectifying type's instance's fact, which it is; nil for others. */
- (ORMFactInstance *)objectifiedInstance;
/* A value type instance's value; an entity instance's identifying values,
 * joined: what a sample shows. */
- (NSString *)displayText;
@end

@interface ORMFactInstance : ORMElement
@property (nonatomic, readonly, weak) ORMFactType *factType;
/* The instance playing each role, by role id. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, ORMInstance *> *instancesByRole;
@end

/* Cardinality: how many instances there may be. */
@interface ORMCardinality : ORMElement
/* (from, to) pairs; to 0 means no upper bound. */
@property (nonatomic, readonly, copy) NSArray<NSArray<NSNumber *> *> *ranges;
@end

@interface ORMRoleSequence (ORMPaths)
/* NORMA's join path for a sequence over several fact types; nil without. */
- (ORMRolePathOwner *)joinPath;
/* The ids of the sequence's role uses (<orm:Role id ref/>), one a role:
 * what a join path's projections name. */
- (NSArray<NSString *> *)roleUseIds;
@end

@interface ORMFactType (ORMPaths)
- (ORMDerivationRule *)derivationRule;
- (NSArray<ORMFactInstance *> *)instances;
@end

@interface ORMObjectType (ORMPaths)
/* A subtype's derivation rule. */
- (ORMDerivationRule *)derivationRule;
- (NSArray<ORMInstance *> *)instances;
- (ORMCardinality *)cardinality;
- (NSString *)defaultValue;
@end

@interface ORMRole (ORMPaths)
/* A unary role's cardinality: how many instances may play it. */
- (ORMCardinality *)cardinality;
@end
