/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"
#import "ORMCDModel.h"

/* A Core Data mapping of an ORM model, as the .orm file keeps it
 * (docs/COREDATA-MAPPING.md): where the .xcdatamodeld is, what of the model
 * it covers, how it maps, what the user renamed, and the model as last
 * written. Read from the document like the rest of the model; changed
 * through ORMEditor's Core Data operations, so every change is undoable. */

typedef NS_ENUM(NSInteger, ORMObjectTypeMapping) {
	/* As the rules decide: an entity, or absorbed where it can be. */
	ORMMapAutomatically,
	ORMMapAsEntity,
	/* Into the attributes of whatever it is the value of. */
	ORMMapAbsorbed,
	/* Left out, with every fact type it plays. */
	ORMMapIgnored,
};

typedef NS_ENUM(NSInteger, ORMMappingScope) {
	ORMScopeModel,
	/* The object types a diagram shows. */
	ORMScopeDiagram,
	/* Object types listed one by one. */
	ORMScopeObjectTypes,
};

@interface ORMCoreDataMapping : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *name;
/* The .xcdatamodeld, relative to the .orm file (or absolute). */
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) ORMMappingScope scope;
/* The diagram, or the object types, the scope names. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *scopeIds;

/* Reference modes as attributes (id, code), in uniqueness constraints. */
@property (nonatomic, readonly) BOOL materializesIdentifiers;
/* Subtypes' properties in their supertype's entity, not entities of their own. */
@property (nonatomic, readonly) BOOL flattensSubtypes;
/* Many-to-many fact types with value types as an entity for the value
 * (YES), or as a transformable attribute holding an array (NO). */
@property (nonatomic, readonly) BOOL valueSetsAsEntities;
/* Xcode's Codegen for the entities: "class", "category", or nil. */
@property (nonatomic, readonly, copy) NSString *codeGenerationType;

/* Names the user gave: ORM element id (an entity's or a property's
 * source) -> name. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *nameOverrides;
/* Object type id -> how it maps, where the user decided. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *objectTypeMappings;
/* ORM elements the mapping leaves out: a role (the property made for it
 * is not made) or a fact type. */
@property (nonatomic, readonly, copy) NSSet<NSString *> *excludedSources;
/* Elements of the Core Data model that are not the ORM model's and stay:
 * "Entity" or "Entity.property". */
@property (nonatomic, readonly, copy) NSSet<NSString *> *keptElements;
/* The Core Data model as last written; nil before the first sync. */
@property (nonatomic, readonly, strong) ORMCDModel *baseline;

/* The element it is read from. */
@property (nonatomic, readonly, strong) NSXMLElement *element;

/* The mappings a document keeps. */
+ (NSArray<ORMCoreDataMapping *> *)mappingsOfDocument:(NSXMLDocument *)document;
+ (ORMCoreDataMapping *)mappingWithId:(NSString *)identifier inDocument:(NSXMLDocument *)document;
/* A mapping that is not in any document: the defaults, for a model with
 * no mapping yet, or ormtool. */
+ (instancetype)defaultMappingNamed:(NSString *)name;

- (ORMObjectTypeMapping)mappingOfObjectType:(NSString *)objectTypeId;
/* The path made absolute against the .orm file's directory. */
- (NSString *)resolvedPathRelativeTo:(NSString *)documentPath;
@end
