/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTables.h"

@class NSManagedObject;

/* The model's rules Core Data cannot enforce, checked from the tables
 * (docs/RUNTIME.md, docs/COREDATA-MAPPING.md): what the generated
 * orm_validateConstraints: and orm_deonticViolations call.
 *
 * Each violation is an NSError like Core Data's own: NSCocoaErrorDomain,
 * NSManagedObjectValidationError, the rule's text as its description, the
 * object and the first property under NSValidationObjectErrorKey and
 * NSValidationKeyErrorKey, the constraint's name under "ORMConstraint" and
 * the properties under "ORMKeys". */
@interface ORMValidator : NSObject
- (instancetype)initWithTables:(ORMTables *)tables;
@property (nonatomic, readonly, strong) ORMTables *tables;
/* The validator of the tables of the name (+[ORMTables tablesNamed:]),
 * made once; nil, and why, where there are none. */
+ (instancetype)validatorNamed:(NSString *)name error:(NSError **)error;

/* The rules of the object's entity, and its ancestors', it does not meet:
 * the alethic ones, or the deontic. */
- (NSArray<NSError *> *)violationsOf:(NSManagedObject *)object deontic:(BOOL)deontic;
/* NO, with the alethic violations in the error, where there are any. */
- (BOOL)validate:(NSManagedObject *)object error:(NSError **)error;
/* Whether the check holds of the object. */
- (BOOL)check:(ORMRuleCheck *)check holdsOf:(NSManagedObject *)object;

/* The violations as one error: the one, or an
 * NSValidationMultipleErrorsError with them under NSDetailedErrorsKey. YES
 * where there are none. */
+ (BOOL)report:(NSArray<NSError *> *)violations error:(NSError **)error;
@end
