/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlan.h"

@class NSManagedObjectContext, NSManagedObjectModel, ORMQueryResult, ORMQueryCursor, ORMQueryOData;

/* What an app built from an ORM model runs, as data (docs/RUNTIME.md): the
 * tables ORMKit's generator writes beside the code it generates, a property
 * list in the app's resources (<Name>.ormplans), read by the driver.
 *
 *   {
 *     format = 1;
 *     model = Company;
 *     queries = { Reporting = { entity = Employee; ... }; };
 *     derivations = ( { text = "..."; root = Employee; plan = {...};
 *                       target = worksIn; kind = value;
 *                       backs = ( ( City, ( branches, employees ) ) ); } );
 *     rules = { Person = ( { constraint = "..."; text = "..."; keys = (...);
 *                            deontic = NO; check = {...}; } ); };
 *     ruleBacks = { Employee = ( ( City, ( branches, employees ) ) ); };
 *     joined = { Customer = { hub = CRMCustomer; members = ( { entity = ...;
 *                  via = ...; outer = YES; on = ( ( userId, userId ) );
 *                  holds = ( balance ); } ); properties = { balance =
 *                  ( balance, BillingAccount ); }; }; };
 *   }
 *
 * What a later format names and this one does not read is left as it
 * is. */

/* The format the tables are written in; a later one is refused. */
extern const NSUInteger ORMTablesFormat;

/* A derived and stored fact type kept up to date at save
 * (docs/DERIVATION.md): its plan reads the entity the property is of, its
 * first column that object, its second what is derived for it. */
@interface ORMStoredDerivation : NSObject
/* The fact type's reading, to say which. */
@property (nonatomic, readonly, copy) NSString *text;
/* The entity whose objects have the property. */
@property (nonatomic, readonly, copy) NSString *root;
@property (nonatomic, readonly, strong) ORMQueryPlan *plan;
/* The property it is kept in, and what it holds: "value", "object" (one,
 * or none where there are none or several), or "objects". */
@property (nonatomic, readonly, copy) NSString *target;
@property (nonatomic, readonly, copy) NSString *kind;
/* The ways back from a change to the objects it can affect: for each
 * entity the plan reads through, the inverse keys from there to the root,
 * @[ entity, @[ key, ... ] ]. */
@property (nonatomic, readonly, copy) NSArray<NSArray *> *backs;
+ (instancetype)derivationWithText:(NSString *)text
                              root:(NSString *)root
                              plan:(ORMQueryPlan *)plan
                            target:(NSString *)target
                              kind:(NSString *)kind
                             backs:(NSArray<NSArray *> *)backs;
@end

/* What a rule asks of an object (docs/RUNTIME.md), as a tree: a few kinds
 * the driver knows, and plans for the rest.
 *
 *   { present = key; }                 the property holds something: a
 *                                      to-many not empty, anything else set
 *   { true = key; }                    a unary's attribute is true
 *   { all = (...); } { any = (...); } { not = {...}; }
 *   { count = (...); atMost = 1; }     how many of the checks hold (or
 *                                      exactly = 1)
 *   { sets = (a, b); relation = disjoint; }   the related objects' sets
 *                                      (subset, equal)
 *   { ring = (acyclic, ...); key = k; }       each ring property of the
 *                                      relationship from the entity to itself
 *   { compare = (a, b); comparison = ">="; }  when both are set
 *   { within = key; ranges = ( { min = 0; max = 17; } ); }   when set; a
 *                                      bound left out is none, minOpen and
 *                                      maxOpen YES where it is not reached
 *   { plan = {...}; }                  the plan reads the object: its
 *                                      condition holds of it */
@interface ORMRuleCheck : NSObject
+ (instancetype)checkWithPropertyList:(id)list error:(NSError **)error;
- (id)propertyList;
/* "present", "true", "all", "any", "not", "count", "sets", "ring",
 * "compare", "within", "plan". */
@property (nonatomic, readonly, copy) NSString *kind;
@property (nonatomic, readonly, copy) NSArray<NSString *> *keys;
@property (nonatomic, readonly, copy) NSArray<ORMRuleCheck *> *operands;
/* count's bound, and whether it is exact; sets' relation, ring's
 * properties, compare's comparison. */
@property (nonatomic, readonly) NSUInteger number;
@property (nonatomic, readonly) BOOL exactly;
@property (nonatomic, readonly, copy) NSString *relation;
@property (nonatomic, readonly, copy) NSArray<NSString *> *properties;
@property (nonatomic, readonly, copy) NSString *comparison;
/* within's: each @{ min, minOpen, max, maxOpen }, numbers. */
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *ranges;
@property (nonatomic, readonly, strong) ORMQueryPlan *plan;
@end

/* A rule an entity's objects are checked by: the constraint's name, what
 * it says, the properties it is about, whether it is an obligation to be
 * told of (deontic) rather than enforced, and its check, which a valid
 * object meets. */
@interface ORMRule : NSObject
+ (instancetype)ruleNamed:(NSString *)constraint
                     text:(NSString *)text
                     keys:(NSArray<NSString *> *)keys
                  deontic:(BOOL)deontic
                    check:(ORMRuleCheck *)check;
@property (nonatomic, readonly, copy) NSString *constraint;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSArray<NSString *> *keys;
@property (nonatomic, readonly) BOOL deontic;
@property (nonatomic, readonly, strong) ORMRuleCheck *check;
/* How far the check sees, to read. */
@property (nonatomic, copy) NSString *remark;
@end

/* An entity type kept in several entities (docs/JOINED-ENTITIES.md), as
 * its façade class runs it: its hub, the entity every one has a row in;
 * its members, each after the one it joins to:
 * @{ entity, via, outer, on: @[ @[ via's key, its own ] ], holds: @[ key ] };
 * and the class's properties, by name: @[ key, entity ]. */
@interface ORMJoinedType : NSObject
+ (instancetype)typeWithHub:(NSString *)hub
                    members:(NSArray<NSDictionary *> *)members
                 properties:(NSDictionary<NSString *, NSArray<NSString *> *> *)properties;
@property (nonatomic, readonly, copy) NSString *hub;
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *members;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSArray<NSString *> *> *properties;
/* The member that is the entity, or nil. */
- (NSDictionary *)member:(NSString *)entity;
@end

@interface ORMTables : NSObject
+ (instancetype)tablesOfModel:(NSString *)model
                      queries:(NSDictionary<NSString *, ORMQueryPlan *> *)queries
                  derivations:(NSArray<ORMStoredDerivation *> *)derivations;
/* The same, with rules. */
+ (instancetype)tablesOfModel:(NSString *)model
                      queries:(NSDictionary<NSString *, ORMQueryPlan *> *)queries
                  derivations:(NSArray<ORMStoredDerivation *> *)derivations
                        rules:(NSDictionary<NSString *, NSArray<ORMRule *> *> *)rules
                    ruleBacks:(NSDictionary<NSString *, NSArray<NSArray *> *> *)ruleBacks;
/* Each entity's rules, by its name; a subentity's objects meet its
 * ancestors' too. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSArray<ORMRule *> *> *rules;
/* The entities whose rules are checked again at save for each object a
 * change reaches, and the ways back to them (as a derivation's). */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSArray<NSArray *> *> *ruleBacks;
/* The joined entity types, by the name of their façade class. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, ORMJoinedType *> *joined;
/* The same tables, with these joined types. */
- (ORMTables *)tablesWithJoined:(NSDictionary<NSString *, ORMJoinedType *> *)joined;
@property (nonatomic, readonly, copy) NSString *model;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, ORMQueryPlan *> *queries;
/* In the order they run: each after those whose facts it reads. */
@property (nonatomic, readonly, copy) NSArray<ORMStoredDerivation *> *derivations;

/* The query of the name run against the context's store, every page;
 * a cursor over it, a page at a time; or as requests to the service of the
 * model (ORMQueryOData.h). nil, and why, where the tables have no query of
 * the name, or it cannot be run there. */
- (ORMQueryResult *)runQuery:(NSString *)name inContext:(NSManagedObjectContext *)context error:(NSError **)error;
- (ORMQueryCursor *)cursorForQuery:(NSString *)name inContext:(NSManagedObjectContext *)context error:(NSError **)error;
- (ORMQueryOData *)requestForQuery:(NSString *)name model:(NSManagedObjectModel *)model error:(NSError **)error;

/* As a property list, and read back: nil, and why, for one of a later
 * format, or with a part that is not what it says. */
- (id)propertyList;
+ (instancetype)tablesWithPropertyList:(id)list error:(NSError **)error;

/* The tables of the model: those registered under its name, else
 * <name>.ormplans in the main bundle or a framework or bundle loaded,
 * read once. nil, and why, where there are none or they cannot be read. */
+ (instancetype)tablesNamed:(NSString *)name error:(NSError **)error;
/* Tables to be found by name, where they come from elsewhere than a
 * bundle's resources: a test's, a download. nil unregisters. */
+ (void)registerTables:(ORMTables *)tables named:(NSString *)name;
@end
