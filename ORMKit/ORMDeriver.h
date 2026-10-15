/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"

@class ORMQuery, ORMInstance, ORMCoreDataMapping;

/* A derived fact: the player of each of its fact type's roles, by role id.
 * An ORMInstance of the sample population; or, for a value type's role
 * whose value no instance has, the value's text. */
@interface ORMDerivedFact : NSObject
@property (nonatomic, readonly, strong) ORMFactType *factType;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *players;
/* Whether each player is an instance of the population: a fact that can be
 * written as one. */
- (BOOL)isOfInstances;
@end

/* The model's derivations (docs/DERIVATION.md) run against its sample
 * population: each derivation query planned against the document's first
 * mapping (or the defaults), run over a store of the population
 * (ORMPopulationStore), and each row read back as a fact, its values
 * matched to the population's instances by what identifies them.
 *
 * A derivation that cannot be run (its plan has notes, its columns are not
 * its fact type's roles) is in -notes, and derives nothing. */
@interface ORMDeriver : NSObject
- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
/* The same, by the document's first mapping or the defaults. */
- (instancetype)initWithModel:(ORMModel *)model;
@property (nonatomic, readonly, strong) ORMModel *model;
/* The derived facts of each fact type a query derives, by its id, in the
 * order the rows came; each fact once. */
- (NSDictionary<NSString *, NSArray<ORMDerivedFact *> *> *)derivedFacts;
/* Why a derivation derived nothing, by the query's name. */
- (NSArray<NSString *> *)notes;
@end
