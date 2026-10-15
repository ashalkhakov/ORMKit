/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"
#import "ORMCDModel.h"

@class ORMJoinedType;

/* The generated code of a mapping's joined entity types
 * (docs/JOINED-ENTITIES.md), part of ORMValidationGenerator's files: a
 * class for each, the type's façade over its members' objects, on
 * ORMRuntime's ORMJoinedObject, and the type's table, which it runs
 * (docs/RUNTIME.md).
 *
 *   Customer *ann = [Customer insertInContext:context];
 *   ann.userId = @1;          the hub's (CRMCustomer)
 *   ann.balance = @50;        BillingAccount's: its row made, joined by userId
 *   ann.balance = nil;        and let go of, where nothing else is kept there
 *
 * The class declares its properties, typed, and leaves them to
 * ORMJoinedObject, which reads where each is kept from the table. */
@interface ORMJoinedFacade : NSObject
/* name: the tables' (ORMValidationGenerator's name). */
- (instancetype)initWithModel:(ORMModel *)model coreData:(ORMCDModel *)coreData name:(NSString *)name;
/* No joined entity type: no code. */
- (BOOL)isEmpty;
/* The classes' interfaces. */
- (NSString *)header;
/* The classes: their properties the table's, and the tables' name. */
- (NSString *)implementation;
/* Each type's table, by its class's name. */
- (NSDictionary<NSString *, ORMJoinedType *> *)types;
@end
