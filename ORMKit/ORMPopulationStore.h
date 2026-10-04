/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"
#import "ORMCDModel.h"

@class NSManagedObjectContext, NSManagedObjectModel, NSManagedObject;

/* A model's sample population as Core Data objects: put in a store of the
 * mapped model as the mapping keeps each fact, by the traces it leaves
 * (ormkit.source), so conceptual queries run against it
 * (ORMQueryInterpreter) as they would against an application's store.
 *
 * - Each entity instance is an object of its most specific type's entity;
 *   a supertype's instance and its subtypes' are one object.
 * - Each fact is set where the mapping put it: an attribute or a
 *   relationship of a player's entity, an object of the fact type's own
 *   entity, the attributes of an absorbed object type. The facts that
 *   identify an entity instance (its reference mode's value, the parts of a
 *   composite identifier) are set as well, though NORMA keeps no fact
 *   instance for them.
 * - A sample need not be complete, so the store's model asks for nothing:
 *   every property is optional there, and nothing is unique. Checking the
 *   population against the constraints is ORMPopulationChecker's. */
@interface ORMPopulationStore : NSObject
- (instancetype)initWithModel:(ORMModel *)model coreData:(ORMCDModel *)coreData;
@property (nonatomic, readonly, strong) ORMModel *model;
@property (nonatomic, readonly, strong) ORMCDModel *coreData;

/* The model the store has: the mapped one, every property optional. What
 * an interpreter runs plans against the context with. */
@property (nonatomic, readonly, strong) NSManagedObjectModel *managedObjectModel;

/* A new context over a new in-memory store holding the population, saved;
 * nil, and why, when the store cannot be made or saved. */
- (NSManagedObjectContext *)newContextWithError:(NSError **)error;
/* What of the population the last context does not hold, and why: a fact
 * the mapping keeps nowhere, a value its attribute cannot take. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
/* The object an instance is in the last context; nil for a value, or an
 * instance of an object type absorbed into others. */
- (NSManagedObject *)objectForInstance:(NSString *)instanceId;
@end
