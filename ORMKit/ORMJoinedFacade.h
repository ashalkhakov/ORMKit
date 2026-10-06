/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"
#import "ORMCDModel.h"

/* The generated code of a mapping's joined entity types
 * (docs/JOINED-ENTITIES.md), part of ORMValidationGenerator's files: a
 * class for each, the type's façade over its members' objects, and what
 * orm_prepareForSave: does for them.
 *
 *   Customer *ann = [Customer insertInContext:context];
 *   ann.userId = @1;          the hub's (CRMCustomer)
 *   ann.balance = @50;        BillingAccount's: its row made, joined by userId
 *   ann.balance = nil;        and let go of, where nothing else is kept there
 *
 * Each property is read from and written to the member that holds it, the
 * member's row found by what joins it, made where a value is set and there
 * is none (an outer member's), deleted where its last value goes. A value
 * the members are joined by, set on the hub, is set on theirs too. At save,
 * an object of the hub inserted, deleted or joined anew without the façade
 * gets its inner members' rows, loses its members' rows, or has them
 * joined again. The code needs Foundation and Core Data only. */
@interface ORMJoinedFacade : NSObject
/* prefix: the generated functions' (ORMValidationGenerator's name). */
- (instancetype)initWithModel:(ORMModel *)model coreData:(ORMCDModel *)coreData prefix:(NSString *)prefix;
/* No joined entity type: no code. */
- (BOOL)isEmpty;
/* The classes' interfaces. */
- (NSString *)header;
/* The functions and the classes. */
- (NSString *)implementation;
/* Statements for orm_prepareForSave:, where changed (the objects inserted,
 * updated and deleted) and violations are in scope. */
- (NSString *)saveStatements;
@end
