/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataMapper.h"

@class ORMTables;

/* What Core Data cannot enforce, as code: a category on each entity's class
 * that checks the ORM constraints its model leaves out, for the class's own
 * validation methods to call.
 *
 *   - (BOOL)validateForInsert:(NSError **)error
 *   {
 *       return [super validateForInsert:error] && [self orm_validateConstraints:error];
 *   }
 *
 * Xcode generates the classes (Codegen "class" or "category") or the user
 * writes them; their validation goes in a category of the user's own, and
 * this one sits beside it, regenerated with the model.
 *
 *   ORM                                  checked
 *   inclusive-or (disjunctive mandatory) at least one of the properties set
 *   mandatory loosened for Core Data     the relationship set
 *   exclusion, exclusive-or              at most (exactly) one set; or the
 *                                        related objects disjoint
 *   subset, equality                     one set only where the other is; or
 *                                        the related objects a subset (equal)
 *   ring                                 each ring property, over the
 *                                        relationship from the entity to itself
 *   value comparison                     the two values compared, when both set
 *   value constraint Core Data cannot    the value within one of the ranges
 *   hold (several ranges, open bounds)
 *   a constraint query (docs/RULES.md)   its plan's condition, one predicate,
 *                                        not met by self: checked from the
 *                                        entity it reads only
 *
 * Alethic constraints make orm_validateConstraints: fail; deontic ones,
 * rules to be told of rather than enforced, are what orm_deonticViolations
 * returns. Each violation is an NSError in NSCocoaErrorDomain with
 * NSManagedObjectValidationError, the constraint's verbalization as its
 * description, the object and the first property as NSValidationObjectErrorKey
 * and NSValidationKeyErrorKey, and the constraint's name under "ORMConstraint";
 * several make an NSValidationMultipleErrorsError, as Core Data's own do.
 *
 * What it cannot check from one object (uniqueness across objects,
 * frequencies over several roles, set comparisons through join paths) is
 * listed in the notes and in a comment in the code. */

@interface ORMValidationGenerator : NSObject
/* The Core Data model the mapper made of the ORM model, and the mapper's
 * notes. Name: the files' ("Shop" makes ShopValidation.h and .m). */
- (instancetype)initWithModel:(ORMModel *)model
                     coreData:(ORMCDModel *)coreData
                        notes:(NSArray<ORMMappingNote *> *)notes
                         name:(NSString *)name;
/* Maps the mapping's model and generates for it. */
- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping name:(NSString *)name;
/* For the Core Data model the mapping wrote (a synchronization's, with what
 * was kept from the Core Data side), the mapper's notes made afresh. */
- (instancetype)initWithModel:(ORMModel *)model
                      mapping:(ORMCoreDataMapping *)mapping
                     coreData:(ORMCDModel *)coreData
                         name:(NSString *)name;

/* File name -> contents: <Name>Validation.h and <Name>Validation.m, and
 * <Name>.ormplans, the tables the code's checks and save hook run
 * (docs/RUNTIME.md), where there are any: the app adds it to its
 * resources, and links ORMRuntime. */
- (NSDictionary<NSString *, NSString *> *)files;
/* The tables the code runs: each entity's rules, and the stored
 * derivations, in the order they are worked out. */
- (ORMTables *)tables;
/* The constraints no code checks, and why. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
/* How many constraints the code checks. */
@property (nonatomic, readonly) NSUInteger ruleCount;

/* Writes the files into the directory, made if need be. */
- (BOOL)writeToDirectory:(NSString *)directory error:(NSError **)error;
@end
