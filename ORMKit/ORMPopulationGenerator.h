/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPopulationEditor.h"

/* A sample population made up to meet the model's constraints, to try
 * queries on when the model has none of its own. The same model always
 * makes the same one.
 *
 * - Values come from a value constraint where there is one, else by data
 *   type: numbers, days, "Name 1", within the type's length.
 * - Each entity type with an identifier has -size instances (fewer when its
 *   identifying values run out), made after the types identifying them; a
 *   subtype is a share of its supertype's, sibling subtypes' shares apart.
 * - Facts are added one at a time, each kept only when it keeps the
 *   uniqueness, frequency, ring, subset and exclusion constraints: first so
 *   that every instance plays its mandatory roles, then more, leaving some
 *   optional roles unplayed. A fact type is filled after those its facts
 *   must be a subset of.
 *
 * What it does not make (an objectified fact type's instances, derived
 * facts) or cannot make meet a constraint is in -notes. */
@interface ORMPopulationGenerator : NSObject
- (instancetype)initWithModel:(ORMModel *)model;
@property (nonatomic, readonly, strong) ORMModel *model;
/* How many instances of each entity type: 5 by default. */
@property (nonatomic) NSUInteger size;
/* The population made, for -[ORMPopulationEditor addPopulation:reason:]. */
- (ORMSamplePopulation *)population;
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
@end
