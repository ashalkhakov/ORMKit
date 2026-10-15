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
	/* A value type as a Transformable attribute of a class of its own (a
	 * kind of string with more to it: an e-mail address, a URL), with the
	 * value transformer that stores it. */
	ORMMapTransformable,
	/* An entity type kept in several entities, joined on its identifiers:
	 * its members (docs/JOINED-ENTITIES.md). */
	ORMMapJoined,
};

/* An entity of a joined entity type: the first is the hub, which every
 * instance has a row in. */
@interface ORMJoinMember : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
/* Its entity's name. */
@property (nonatomic, readonly, copy) NSString *name;
/* The identifier it correlates by: a uniqueness constraint's id, the
 * preferred identifier's where it says none. */
@property (nonatomic, readonly, copy) NSString *correlationId;
/* The member it joins to; nil for the hub. */
@property (nonatomic, readonly, copy) NSString *viaId;
/* Not every instance has a row. */
@property (nonatomic, readonly) BOOL isOuter;
/* Its rows need not have what joins them (OptionalBy="true"), as a store
 * read back may have it: a row without is no instance's. */
@property (nonatomic, readonly) BOOL correlationIsOptional;
/* The roles whose properties it has: each the far role, as a property's
 * trace is. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *heldRoleIds;
/* Those its rows always have, though not every instance has a row: the
 * properties required in its entity (Holds Required="true"). */
@property (nonatomic, readonly, copy) NSArray<NSString *> *requiredRoleIds;
@end

/* What the Core Data model is for, which sets how the conceptual model
 * becomes a logical one where there is more than one good way; the
 * options and each object type's own mapping still decide over it. */
typedef NS_ENUM(NSInteger, ORMMappingStyle) {
	/* An application's store: what is no more than values (an Address,
	 * a Row, one with a generated id and an alternate key too) absorbed
	 * into what uses it, objectifications one to one with a player
	 * folded into it, everything with an identity of its own an entity. */
	ORMStyleApplication,
	/* Rmap's grouping, as ActiveFacts makes tables: subtypes flattened,
	 * identifier-only types absorbed, a type with a composite reference
	 * scheme absorbed where one fact type refers to it. */
	ORMStyleRelational,
	/* Every entity type an entity, nothing absorbed but values: for
	 * reports and analysis over things in their own right. */
	ORMStyleEntities,
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
/* Where the validation code goes (ORMCoreDataValidation.h), a directory
 * relative to the .orm file (or absolute); nil for none. */
@property (nonatomic, readonly, copy) NSString *validationPath;
@property (nonatomic, readonly) ORMMappingScope scope;
@property (nonatomic, readonly) ORMMappingStyle style;
/* The diagram, or the object types, the scope names. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *scopeIds;

/* Reference modes as attributes (id, code), in uniqueness constraints. */
@property (nonatomic, readonly) BOOL materializesIdentifiers;
/* userInfo for ODataKit to serve the model by: entity sets, keys (a
 * surrogate where the identifier is not of attributes), descriptions and
 * validation terms. ORMODataAnnotator.h. */
@property (nonatomic, readonly) BOOL servesOData;
/* The namespace of the service's types (ODataService's namespaceName):
 * OData.type is in it. "Default" unless set. */
@property (nonatomic, readonly, copy) NSString *odataNamespace;
/* Subtypes' properties in their supertype's entity, not entities of their
 * own. The style's unless set. */
@property (nonatomic, readonly) BOOL flattensSubtypes;
/* Rmap's grouping: an entity type with nothing but its identifier (no
 * fact type functional on it, no subtyping, not independent) is absorbed
 * as attributes wherever it is used, as Rmap leaves it out of the tables. */
@property (nonatomic, readonly) BOOL absorbsIdentifierTypes;
/* Value-like entity types absorbed into what uses them, and
 * objectifications one to one with a player folded into it: not in the
 * Entities style. */
@property (nonatomic, readonly) BOOL absorbsValueLikeTypes;
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
/* A Transformable value type's class and value transformer, by its id:
 * @[ class, transformer ]. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSArray<NSString *> *> *transformables;
/* A joined entity type's members, in order, by its id. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSArray<ORMJoinMember *> *> *joins;
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
- (NSString *)resolvedValidationPathRelativeTo:(NSString *)documentPath;
@end
