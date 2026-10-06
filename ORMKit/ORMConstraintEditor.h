/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* Constraints of every kind, over roles by id, and preferred identifiers.
 * Usually reached as an editor's constraintEditor.
 *
 * A constraint drawn as a shape of its own (external uniqueness and
 * mandatory, set comparisons, ring, frequency, value comparison) is shown,
 * as it is added, on every diagram that shows all its fact types, in the
 * same change: one undo takes both, as NORMA shows one it adds. */
@interface ORMConstraintEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, weak) ORMEditor *editor;

/* Internal when every role is in one fact type, external otherwise. An
 * internal one over a binary's single role makes its multiplicity "one".
 * Its id. */
- (NSString *)addUniquenessConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason;
/* A simple mandatory constraint on one role, or a disjunctive
 * (inclusive-or) one over several. Its id. */
- (NSString *)addMandatoryConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason;
/* The role mandatory or not: adds or removes its simple mandatory
 * constraint. */
- (BOOL)setMandatory:(BOOL)mandatory role:(NSString *)roleId reason:(NSString **)reason;
/* The single role unique or not: adds or removes the internal uniqueness
 * constraint over exactly it. */
- (BOOL)setUnique:(BOOL)unique role:(NSString *)roleId reason:(NSString **)reason;
/* max 0: no maximum. Its id. */
- (NSString *)addFrequencyConstraintOverRoles:(NSArray<NSString *> *)roleIds
                                          min:(NSUInteger)min
                                          max:(NSUInteger)max
                                       reason:(NSString **)reason;
- (NSString *)addRingConstraint:(ORMRingType)type
                       overRoles:(NSArray<NSString *> *)roleIds
                          reason:(NSString **)reason;
/* Subset (the first sequence's population is a subset of the second's),
 * equality and exclusion, over sequences of equal length. Its id. */
- (NSString *)addSetComparisonConstraint:(ORMConstraintKind)kind
                               sequences:(NSArray<NSArray<NSString *> *> *)roleIds
                                  reason:(NSString **)reason;
/* Exclusion and disjunctive mandatory over the same roles, linked. The
 * exclusion's id. */
- (NSString *)addExclusiveOrConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason;
- (NSString *)addValueComparisonConstraint:(NSString *)comparisonOperator
                                 overRoles:(NSArray<NSString *> *)roleIds
                                    reason:(NSString **)reason;
- (BOOL)setFrequencyMin:(NSUInteger)min max:(NSUInteger)max of:(NSString *)constraintId reason:(NSString **)reason;
- (BOOL)setRingType:(ORMRingType)type of:(NSString *)constraintId reason:(NSString **)reason;
- (BOOL)setModality:(ORMModality)modality of:(NSString *)constraintId reason:(NSString **)reason;
/* Makes the uniqueness constraint the preferred identifier of the entity
 * type its roles identify. */
- (BOOL)setPreferredIdentifier:(NSString *)constraintId reason:(NSString **)reason;

@end
