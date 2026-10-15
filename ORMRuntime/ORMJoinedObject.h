/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTables.h"

@class NSManagedObject, NSManagedObjectContext;

/* An entity type kept in several entities, joined on its identifiers
 * (docs/JOINED-ENTITIES.md): what its façade class is. Each property is
 * read from and written to the entity that holds it, the row there made
 * where a value is set, and let go of where its last one goes.
 *
 * The generated class declares its properties, typed, and leaves them to
 * this one (@dynamic), which reads where each is kept from the model's
 * tables; it names the tables:
 *
 *   @interface Customer : ORMJoinedObject
 *   @property (nonatomic, strong) NSNumber *balance;
 *   @end
 *
 *   @implementation Customer
 *   @dynamic balance;
 *   + (NSString *)tablesName { return @"Customers"; }
 *   @end
 *
 * The type's table is the class's name's. */
@interface ORMJoinedObject : NSObject
/* The tables' name (+[ORMTables tablesNamed:]): the subclass's to say. */
+ (NSString *)tablesName;
/* The type's table; raises where the tables have none. */
+ (ORMJoinedType *)joinedType;

/* One for each of the hub's objects. */
+ (NSArray *)allInContext:(NSManagedObjectContext *)context;
/* A new one: its rows in the inner members are made when it is saved, by
 * the values it is joined by. */
+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

- (instancetype)initWithObject:(NSManagedObject *)object;
/* Its object in the hub, the entity every one has a row in. */
@property (nonatomic, readonly, strong) NSManagedObject *object;
/* Its row in a member, or the hub; nil where it has none. */
- (NSManagedObject *)rowIn:(NSString *)entityName;
/* Deletes its rows, the hub's and the members'. */
- (void)delete;

/* A property's value, kept in the entity. */
- (id)valueForKey:(NSString *)key in:(NSString *)entityName;
/* A property set, the row made where there is none and the value is
 * something; let go of, where an outer member's keeps nothing else and
 * nothing joins to it. A value the members are joined by is set on theirs
 * too; set to nil, it lets go of their rows. Raises
 * NSInternalInconsistencyException where a value is set before those it
 * is joined by: a programming error. */
- (void)setValue:(id)value forKey:(NSString *)key in:(NSString *)entityName;

/* What saving does for the type's hub objects among those changed: a new
 * one's rows in its inner members made (a violation where it has no value
 * to join them by), a deleted one's rows deleted, a changed one's joined
 * again. */
+ (void)prepareType:(ORMJoinedType *)type
            changed:(NSSet *)changed
         violations:(NSMutableArray<NSError *> *)violations;
@end
