/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* A join path described as logic, for the editor to write as NORMA keeps
 * it: the fact types it walks, each a map from its roles to the variables
 * that play them, and the variables the constraint's roles are, in order.
 *
 *   "that Address is in some Country and that Region is part of that
 *    Country", columns Address and Region:
 *   atoms  { isIn.address: A, isIn.country: C }, { partOf.region: R, partOf.country: C }
 *   columns A, R
 *
 * The path starts at the first column's variable and walks the atoms as a
 * tree, a fact type entered from a variable it has (PostInnerJoin), its
 * other roles stepped through (SameFactType); where it branches, sub-paths
 * go on from the branch. An atom whose roles all lead back to variables
 * the path has met (a cycle) cannot be walked so, and is refused. */
@interface ORMJoinPathSpec : NSObject
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *atoms;
@property (nonatomic, copy) NSArray<NSString *> *columns;
+ (instancetype)specWithAtoms:(NSArray<NSDictionary<NSString *, NSString *> *> *)atoms columns:(NSArray<NSString *> *)columns;
@end

/* Writes join paths as NORMA keeps them, for constraints over them. */
@interface ORMJoinPathBuilder : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, strong) ORMEditor *editor;

/* A set comparison constraint (subset, equality, exclusion) whose
 * sequences may be join paths: a spec of one atom is a plain sequence of
 * the columns' roles, a spec of more a sequence of the roles where the
 * columns are played, with the path. Its id. */
- (NSString *)addSetComparisonConstraint:(ORMConstraintKind)kind
                               joinPaths:(NSArray<ORMJoinPathSpec *> *)specs
                                  reason:(NSString **)reason;
@end
