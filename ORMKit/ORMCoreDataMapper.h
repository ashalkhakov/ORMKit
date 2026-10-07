/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataMapping.h"

/* An ORM model mapped to a Core Data model, by the rules of
 * docs/COREDATA-MAPPING.md and the mapping's options and overrides.
 *
 * Every entity, attribute and relationship it makes carries the id of the
 * ORM element it maps (ORMCDSourceKey): an entity its object type's (or the
 * fact type's, for a fact type mapped to an entity of its own), a property
 * the role at its far end -- the role of the other player, so a fact type's
 * two directions are told apart. What the mapping cannot express it says in
 * its report. */

typedef NS_ENUM(NSInteger, ORMMappingNoteKind) {
	/* An entity type made into attributes of what uses it. */
	ORMMappingAbsorbed,
	/* A constraint Core Data has no way to enforce. */
	ORMMappingUnenforced,
	/* Something mapped in a way the modeller should know of. */
	ORMMappingWarning,
	/* A derived fact type: left out, worked out by queries; or derived by
	 * Core Data (docs/DERIVATION.md). */
	ORMMappingDerived,
};

@interface ORMMappingNote : NSObject
@property (nonatomic, readonly) ORMMappingNoteKind kind;
@property (nonatomic, readonly, copy) NSString *text;
/* The ORM element it is about. */
@property (nonatomic, readonly, copy) NSString *elementId;
@end

@interface ORMCoreDataMapper : NSObject
- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
@property (nonatomic, readonly, strong) ORMModel *model;
@property (nonatomic, readonly, strong) ORMCoreDataMapping *mapping;

/* The Core Data model, made afresh each time. */
- (ORMCDModel *)map;
/* What the last map: made of what it could not map as is. */
@property (nonatomic, readonly, copy) NSArray<ORMMappingNote *> *notes;

/* How the rules map an object type, overrides aside. */
- (ORMObjectTypeMapping)automaticMappingOf:(ORMObjectType *)type;

/* Identifiers as Core Data wants them: "OrderLine", "orderLine". */
+ (NSString *)entityNameFor:(NSString *)name;
+ (NSString *)propertyNameFor:(NSString *)name;
+ (NSString *)pluralOf:(NSString *)name;
/* A name Core Data allows an entity or property: a letter or underscore,
 * then letters, digits and underscores (ASCII), 128 at most. */
+ (BOOL)isCoreDataName:(NSString *)name;
/* NORMA's data type as Core Data's attribute type. */
+ (NSString *)attributeTypeFor:(ORMDataType *)dataType;
@end
