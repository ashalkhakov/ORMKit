/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* A Core Data model as Xcode's .xcdatamodel "contents" file has it: what an
 * ORM mapping produces, and what Xcode or ModelBuilder may have changed.
 *
 * Plain objects, not NSManagedObjectModel: they read and write the source
 * format on any platform, without Core Data, keep what Core Data's runtime
 * classes drop (Xcode's codegen settings, entity positions), and compare
 * cheaply, which is what keeping a mapping in step needs. Whatever the
 * contents hold that these do not model -- configurations, fetch requests,
 * attributes of Xcode's own -- is kept as XML and written back as read. */

/* The key in an element's userInfo naming the ORM element it maps. */
extern NSString * const ORMCDSourceKey;

@interface ORMCDProperty : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL optional;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *userInfo;
/* The ORM element it maps: userInfo's ormkit.source. */
@property (nonatomic, readonly, copy) NSString *source;
- (void)setSource:(NSString *)source;
/* Attributes of the XML element ORMKit does not model, kept as read. */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extraAttributes;
@end

@interface ORMCDAttribute : ORMCDProperty
/* Xcode's spelling: "String", "Integer 32", "Decimal", "Date", "Boolean",
 * "Binary", "UUID", "URI", "Double", "Float", "Integer 16", "Integer 64",
 * "Transformable". */
@property (nonatomic, copy) NSString *attributeType;
@property (nonatomic, copy) NSString *defaultValue;
/* For numbers and dates, bounds on the value; for strings, on its length. */
@property (nonatomic, copy) NSString *minValue;
@property (nonatomic, copy) NSString *maxValue;
@property (nonatomic, copy) NSString *regularExpression;
@property (nonatomic) BOOL allowsExternalStorage;
/* Derived by Core Data, which keeps it up to date at save: its expression,
 * a key path through one to-one ("city.name", Core Data goes no further) or
 * an aggregate over a to-many ("employees.@count"). nil for one set as any
 * other. */
@property (nonatomic, copy) NSString *derivation;
@end

@interface ORMCDRelationship : ORMCDProperty
@property (nonatomic, copy) NSString *destination;
@property (nonatomic, copy) NSString *inverseName;
@property (nonatomic) BOOL toMany;
@property (nonatomic) BOOL ordered;
/* 0: no bound. A to-one relationship has a maximum of 1. */
@property (nonatomic) NSUInteger minCount;
@property (nonatomic) NSUInteger maxCount;
/* "Nullify", "Cascade", "Deny", "No Action". */
@property (nonatomic, copy) NSString *deletionRule;
@end

@interface ORMCDEntity : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *parentName;
@property (nonatomic) BOOL isAbstract;
@property (nonatomic, copy) NSString *representedClassName;
/* Xcode's Codegen setting: "class", "category", or nil (manual). */
@property (nonatomic, copy) NSString *codeGenerationType;
@property (nonatomic, strong) NSMutableArray<ORMCDAttribute *> *attributes;
@property (nonatomic, strong) NSMutableArray<ORMCDRelationship *> *relationships;
/* Each a list of attribute (or to-one relationship) names, unique together. */
@property (nonatomic, strong) NSMutableArray<NSArray<NSString *> *> *uniquenessConstraints;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *userInfo;
@property (nonatomic, readonly, copy) NSString *source;
- (void)setSource:(NSString *)source;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extraAttributes;
/* Children of the XML element ORMKit does not model (fetched properties,
 * indexes, ...), kept as read. */
@property (nonatomic, copy) NSArray<NSXMLElement *> *extraElements;

- (ORMCDAttribute *)attributeNamed:(NSString *)name;
- (ORMCDRelationship *)relationshipNamed:(NSString *)name;
- (ORMCDProperty *)propertyNamed:(NSString *)name;
/* Every property, attributes first, each sorted by name, as Xcode writes them. */
- (NSArray<ORMCDProperty *> *)properties;
@end

@interface ORMCDModel : NSObject <NSCopying>
+ (instancetype)model;
/* nil with why when the text is not a data model's contents. */
+ (instancetype)modelWithContentsXML:(NSData *)data reason:(NSString **)reason;
/* The current version of an .xcdatamodeld, or a bare .xcdatamodel. */
+ (instancetype)modelAtPath:(NSString *)path reason:(NSString **)reason;

@property (nonatomic, strong) NSMutableArray<ORMCDEntity *> *entities;
/* Where Xcode's editor shows each entity: name -> {x, y, width, height}. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *positions;
/* The model element's attributes (tool versions and the like). */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *modelAttributes;
/* configuration, fetchRequest and whatever else the model holds. */
@property (nonatomic, copy) NSArray<NSXMLElement *> *extraElements;

- (ORMCDEntity *)entityNamed:(NSString *)name;
/* The entity, or the entity's property, whose source is the ORM element. */
- (ORMCDEntity *)entityWithSource:(NSString *)source;
- (NSArray<ORMCDEntity *> *)subentitiesOf:(NSString *)name;

/* The contents file, as Xcode writes it. */
- (NSData *)contentsXML;
/* Writes path (Name.xcdatamodeld) holding Name.xcdatamodel/contents and
 * .xccurrentversion, keeping other versions already there. */
- (BOOL)writeToPackage:(NSString *)path error:(NSError **)error;
@end
