/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"

@class ORMQuery;

/* What a sample population breaks: a constraint, and how. */
@interface ORMPopulationViolation : NSObject
/* The constraint broken; nil for a fact that lacks a role's player, or a
 * rule's violation. */
@property (nonatomic, readonly, strong) ORMConstraint *constraint;
/* The constraint query broken (docs/RULES.md), for a rule's violation. */
@property (nonatomic, readonly, strong) ORMQuery *rule;
/* The fact type it is about: the incomplete fact's, or the constraint's
 * first. */
@property (nonatomic, readonly, strong) ORMFactType *factType;
/* "Employee 7 has no EmployeeName.": what is wrong, of which instances. */
@property (nonatomic, readonly, copy) NSString *text;
@end

/* A model's sample population checked against its constraints, as NORMA
 * checks one: each fact complete; uniqueness, internal and external (over
 * binaries joined on the instance they are about); mandatory, simple and
 * disjunctive; frequency; ring; subset, equality and exclusion between
 * sequences each in one fact type; the values a value constraint allows.
 * The facts that identify an entity instance count as facts of their fact
 * types. What it cannot check (a value comparison, a sequence across fact
 * types) is in -unchecked.
 *
 * The model's constraint queries are checked too: run against a store of
 * the population (ORMPopulationStore), of the document's first mapping or
 * the defaults, each row a violation (ORMRuleChecker); and its value
 * calculations, an object with more than one value a violation. */
@interface ORMPopulationChecker : NSObject
- (instancetype)initWithModel:(ORMModel *)model;
@property (nonatomic, readonly, strong) ORMModel *model;
/* Each violation, deontic ones too, in the model's order of constraints. */
- (NSArray<ORMPopulationViolation *> *)violations;
/* The constraints it did not check, and why. */
- (NSArray<NSString *> *)unchecked;
@end
