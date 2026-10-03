/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"
#import "ORMCoreDataMapper.h"

/* Keeping an ORM model and a Core Data model in step: the mappings the
 * document keeps, edited through the editor, and the three-way merge that
 * synchronizes one (docs/COREDATA-MAPPING.md). */

@interface ORMEditor (ORMCoreDataMappings)
/* A new mapping, of the whole model, to the .xcdatamodeld at the path. Its id. */
- (NSString *)addCoreDataMappingNamed:(NSString *)name path:(NSString *)path;
- (void)removeCoreDataMapping:(NSString *)mappingId;
- (BOOL)setPath:(NSString *)path ofMapping:(NSString *)mappingId reason:(NSString **)reason;
- (void)setScope:(ORMMappingScope)scope ids:(NSArray<NSString *> *)ids ofMapping:(NSString *)mappingId;
- (void)setMaterializesIdentifiers:(BOOL)flag ofMapping:(NSString *)mappingId;
- (void)setFlattensSubtypes:(BOOL)flag ofMapping:(NSString *)mappingId;
- (void)setValueSetsAsEntities:(BOOL)flag ofMapping:(NSString *)mappingId;
- (void)setAbsorbsIdentifierTypes:(BOOL)flag ofMapping:(NSString *)mappingId;
/* The value type maps as a Transformable attribute of the class (NSString
 * when nil), stored by the value transformer (NSSecureUnarchiveFromData
 * when nil). */
- (void)setTransformableClass:(NSString *)className
                  transformer:(NSString *)transformerName
                 ofObjectType:(NSString *)objectTypeId
                    inMapping:(NSString *)mappingId;
/* nil: no override, the rules' name. */
- (void)setName:(NSString *)name forSource:(NSString *)sourceId inMapping:(NSString *)mappingId;
- (void)setMapping:(ORMObjectTypeMapping)how ofObjectType:(NSString *)objectTypeId inMapping:(NSString *)mappingId;
- (void)setExcluded:(BOOL)excluded source:(NSString *)sourceId inMapping:(NSString *)mappingId;
- (void)setKept:(BOOL)kept element:(NSString *)path inMapping:(NSString *)mappingId;
- (void)setBaseline:(ORMCDModel *)model ofMapping:(NSString *)mappingId;
/* The document without ORMKit's own elements, for a NORMA that does not
 * know them: what "Save a Copy for NORMA" writes. */
- (NSXMLDocument *)documentForNorma;
@end

typedef NS_ENUM(NSInteger, ORMSyncChangeKind) {
	ORMSyncRenameEntity,
	ORMSyncRenameProperty,
	ORMSyncOptionality,
	ORMSyncCardinality,
	ORMSyncAttributeType,
	ORMSyncValueBounds,
	ORMSyncAddEntity,
	ORMSyncAddAttribute,
	ORMSyncAddRelationship,
	ORMSyncDeleteEntity,
	ORMSyncDeleteProperty,
	ORMSyncAddUniqueness,
	ORMSyncRemoveUniqueness,
};

/* How a change made on the Core Data side comes back into the ORM model. */
typedef NS_ENUM(NSInteger, ORMSyncAction) {
	/* Into the ORM model: a constraint, a fact type, an object type. */
	ORMSyncApplyToModel,
	/* Into the mapping only: a name override, an exclusion, a kept element. */
	ORMSyncApplyToMapping,
	/* Not at all: the next write puts back what the ORM model says. */
	ORMSyncDiscard,
};

@interface ORMSyncChange : NSObject
@property (nonatomic, readonly) ORMSyncChangeKind kind;
/* What changed, in words: "Product.barcode was made optional". */
@property (nonatomic, readonly, copy) NSString *text;
/* "Entity" or "Entity.property". */
@property (nonatomic, readonly, copy) NSString *path;
/* What the default does, and what else may be chosen. */
@property (nonatomic) ORMSyncAction action;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *possibleActions;
/* The ORM element the ORM side changed too, when it did: a conflict. */
@property (nonatomic, readonly) BOOL conflicts;
@end

@interface ORMCoreDataSync : NSObject
/* theirs: the .xcdatamodeld as it is now; nil when there is none yet. */
- (instancetype)initWithEditor:(ORMEditor *)editor mapping:(NSString *)mappingId theirs:(ORMCDModel *)theirs;

/* What the ORM model maps to now. */
@property (nonatomic, readonly, strong) ORMCDModel *ours;
/* The changes found on the Core Data side, each with its action. */
@property (nonatomic, readonly, copy) NSArray<ORMSyncChange *> *changes;
@property (nonatomic, readonly, copy) NSArray<ORMMappingNote *> *notes;

/* Applies the changes' actions to the ORM model and the mapping, as one
 * undoable step, and returns the Core Data model to write: the ORM model's
 * mapping, with what Core Data has and ORM does not kept from theirs. The
 * mapping's baseline becomes it. */
- (ORMCDModel *)apply;
@end
