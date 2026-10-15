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
/* The source a step's node's role is traced by: its own id; a link fact
 * type's, what it stands for in the objectified fact type (from the
 * objectifying type, the role its proxy stands for; to it, the fact type's
 * entity, as from that role). */
+ (NSString *)sourceOfRole:(ORMRole *)role;
/* Where a joined entity type's member has the property traced to the
 * source (docs/JOINED-ENTITIES.md): the hops from the entity to it, each
 * @[ member entity, @[ @[ the name on the entity before, its own ], ... ],
 * @(outer) ]. nil where no member has it, or the member is not reached
 * from the entity. */
- (NSArray<NSArray *> *)joinsTo:(NSString *)source from:(ORMCDEntity *)entity;
/* The same, to the member itself. */
- (NSArray<NSArray *> *)joinsToMember:(ORMCDEntity *)member from:(ORMCDEntity *)entity;
/* From a member to its hub, the other way: the hops, as above. nil for
 * anything else. */
- (NSArray<NSArray *> *)joinsToHubFrom:(ORMCDEntity *)member;
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
/* An absorbed type's identifying values on the entity absorbing it under
 * the trace base: their key paths, in its identifier's order, a part
 * absorbed in turn by its own, an entity by its identifier. nil where one
 * is missing. */
- (NSArray<NSArray<NSString *> *> *)identifyingPartsOfAbsorbed:(ORMObjectType *)type
                                                          base:(NSString *)base
                                                            on:(ORMCDEntity *)entity;
/* The properties an absorbed object type's parts are on the entity: @[ the
 * trace below the base ("/role/role"), the property ], its own and its
 * ancestors'. */
- (NSArray<NSArray *> *)absorbedParts:(NSString *)base on:(ORMCDEntity *)entity;
@end
