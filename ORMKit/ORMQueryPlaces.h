/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQuery.h"
#import "ORMCDModel.h"

/* Where a query's object types and fact types are in a mapped Core Data
 * model, by the traces the mapping leaves (ormkit.source): what the planner
 * (ORMQueryPlanner) looks up. */
@interface ORMQueryPlaces : NSObject
- (instancetype)initWithCoreData:(ORMCDModel *)coreData;
@property (nonatomic, readonly, strong) ORMCDModel *coreData;

/* The entity an object type's instances are: its own, or its nearest
 * supertype's when it was flattened into it. */
- (ORMCDEntity *)entityOf:(ORMObjectType *)type;
- (BOOL)entity:(ORMCDEntity *)entity inherits:(ORMCDEntity *)ancestor;
- (ORMCDEntity *)parentOf:(ORMCDEntity *)entity;
/* The property traced to the source, if the entity has it (its own or an
 * ancestor's). */
- (ORMCDProperty *)propertyOf:(ORMCDEntity *)entity source:(NSString *)source;
/* The property of the name, its own or an ancestor's. */
- (ORMCDProperty *)property:(NSString *)name of:(ORMCDEntity *)entity;
/* The entity's name and its subentities', at any depth. */
- (NSArray<NSString *> *)namesOf:(ORMCDEntity *)entity;
/* An entity's simple identifier attribute: its reference mode's value. */
- (ORMCDAttribute *)identifierOf:(ORMObjectType *)type on:(ORMCDEntity *)entity;
/* What identifies an object of the entity when no one attribute does: the
 * key paths to the values of its preferred identifier's parts, in order,
 * through the to-ones to a part that is an entity ("degreecode",
 * "university.code"). nil where one attribute does, or a part is not
 * found. */
- (NSArray<NSArray<NSString *> *> *)identifyingPartsOf:(ORMObjectType *)type on:(ORMCDEntity *)entity;
/* The properties an absorbed object type's parts are on the entity: @[ the
 * trace below the base ("/role/role"), the property ], its own and its
 * ancestors'. */
- (NSArray<NSArray *> *)absorbedParts:(NSString *)base on:(ORMCDEntity *)entity;
@end
