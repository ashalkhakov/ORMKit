/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlan.h"

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
 *   }
 *
 * What a table of a later step names (rules, joined types) and this one
 * does not read is left as it is. */

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

@interface ORMTables : NSObject
+ (instancetype)tablesOfModel:(NSString *)model
                      queries:(NSDictionary<NSString *, ORMQueryPlan *> *)queries
                  derivations:(NSArray<ORMStoredDerivation *> *)derivations;
@property (nonatomic, readonly, copy) NSString *model;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, ORMQueryPlan *> *queries;
/* In the order they run: each after those whose facts it reads. */
@property (nonatomic, readonly, copy) NSArray<ORMStoredDerivation *> *derivations;

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
