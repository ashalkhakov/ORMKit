/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* Two entity types that may be one (docs/JOINED-ENTITIES.md): each has a
 * one-to-one fact type with a value of the same name and data type
 * (userId, an external GUID), its identifier or an alternate one, as two
 * tables a process each keeps of the same customers have. */
@interface ORMMergeCandidate : NSObject
/* The one kept: whose value is its preferred identifier, where only one
 * of them is. */
@property (nonatomic, readonly, strong) ORMObjectType *kept;
/* The value's role, in the one-to-one fact type. */
@property (nonatomic, readonly, strong) ORMRole *keptRole;
@property (nonatomic, readonly, strong) ORMObjectType *absorbed;
@property (nonatomic, readonly, strong) ORMRole *absorbedRole;
/* "CRMCustomer and BillingAccount may be one entity type: both have
 * userId." */
- (NSString *)text;
@end

/* Makes one entity type of two that are one thing kept twice: the
 * conceptual model says there is one, and the Core Data mappings keep
 * both entities, as members of its join. */
@interface ORMEntityMerger : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, strong) ORMEditor *editor;

/* The model's candidates, each pair once. */
- (NSArray<ORMMergeCandidate *> *)candidates;

/* The absorbed type made one with the kept one, as one change, the
 * absorbed type's value role (in its one-to-one fact type) being the kept
 * one's:
 *   - the absorbed type's fact type of the value goes, and with it a value
 *     type nothing else plays;
 *   - the kept one's becomes an identifier (alternate, unless it is the
 *     preferred one);
 *   - every other role the absorbed type played is the kept one's;
 *   - the absorbed type goes;
 *   - in each Core Data mapping, the kept type maps as Joined: its entity
 *     the hub, the absorbed type's an outer member under its name, joined
 *     by the value, holding what it held, its value's attribute named as
 *     it was.
 * NO, and why, where they cannot be: not entity types, a subtype or
 * supertype, values of different data types, a fact type that is not one
 * to one, an absorbed type identified by several fact types. */
- (BOOL)merge:(NSString *)absorbedId
         into:(NSString *)keptId
     matching:(NSString *)absorbedRoleId
         with:(NSString *)keptRoleId
       reason:(NSString **)reason;
@end
