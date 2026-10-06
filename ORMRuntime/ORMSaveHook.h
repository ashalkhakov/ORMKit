/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTables.h"

@class NSManagedObjectContext;

/* What a context does before it saves (docs/DERIVATION.md, docs/RUNTIME.md),
 * by the model's tables: the generated -orm_prepareForSave: calls it.
 *
 * For each stored derivation, in the tables' order: the objects of its root
 * entity a change can reach (those changed, and those each changed object
 * reaches back along its ways back), each asked its plan as it is in the
 * context, unsaved changes and all, and its property set where what is
 * derived differs. An object whose property is set is a change too, which
 * the derivations after it, and the rules, see. */
@interface ORMSaveHook : NSObject
- (instancetype)initWithTables:(ORMTables *)tables;
@property (nonatomic, readonly, strong) ORMTables *tables;

/* The derivations brought up to date for what changed; the objects whose
 * properties were set added to it. NO, and why, where a plan cannot be
 * run against the context's model. */
- (BOOL)deriveInContext:(NSManagedObjectContext *)context changed:(NSMutableSet *)changed error:(NSError **)error;

/* The objects of the entity a change can affect: those changed, and those
 * each changed object of an entity in backs reaches walking back:
 * @[ entity, @[ key, ... ] ]. */
+ (NSSet *)rootsOf:(NSString *)entityName
             backs:(NSArray<NSArray *> *)backs
           changed:(NSSet *)changed
         inContext:(NSManagedObjectContext *)context;
@end
