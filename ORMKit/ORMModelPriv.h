/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagram.h"
#import "ORMPath.h"
#import "ORMCoreDataMapping.h"
#import "ORMNormaWriter.h"

@class ORMStoredQuery, ORMQueryPart;

/* What the reader, the editors and the writer set: the public classes are
 * read-only. */

@interface ORMElement ()
@property (nonatomic, readwrite, strong) NSXMLElement *element;
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, weak) ORMModel *model;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *definitionText;
@property (nonatomic, readwrite, copy) NSString *noteText;
- (instancetype)initWithElement:(NSXMLElement *)element model:(ORMModel *)model;
/* A new element, made by an editor: a new id, no XML element until the
 * writer makes it. */
- (instancetype)initWithModel:(ORMModel *)model;
/* Read again in place: every value as a new element's, then the element's. */
- (void)resetWithElement:(NSXMLElement *)element model:(ORMModel *)model;
/* Each class's values back to a new element's; a subclass calls super. */
- (void)reset;
@end

@interface ORMObjectType ()
@property (nonatomic, readwrite) ORMObjectTypeKind kind;
@property (nonatomic, readwrite, copy) NSString *defaultValue;
@property (nonatomic, readwrite) BOOL isIndependent;
@property (nonatomic, readwrite) BOOL isExternal;
@property (nonatomic, readwrite) BOOL isPersonal;
@property (nonatomic, readwrite) BOOL isImplied;
@property (nonatomic, readwrite) BOOL isImplicitBooleanValue;
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *playedRoles;
/* NORMA's implied mandatory constraints that say they are implied by it,
 * in the model's order: one, but for a file that has more. */
@property (nonatomic, readwrite, copy) NSArray<ORMConstraint *> *impliedMandatories;
@property (nonatomic, readwrite, weak) ORMConstraint *preferredIdentifier;
@property (nonatomic, readwrite, weak) ORMFactType *nestedFactType;
@property (nonatomic, readwrite, weak) ORMDataType *dataType;
@property (nonatomic, readwrite) NSInteger dataTypeLength;
@property (nonatomic, readwrite) NSInteger dataTypeScale;
@property (nonatomic, readwrite, copy) NSString *valuePattern;
/* What the file says, as against what is derived: its own value
 * constraint (valueConstraint is an entity type's reference mode's too),
 * and NORMA's _ReferenceMode, which settles how a value type's name reads. */
@property (nonatomic, readwrite, strong) ORMValueConstraint *ownValueConstraint;
@property (nonatomic, readwrite, copy) NSString *savedReferenceMode;
/* An objectified type's objectification's own id (its NestedPredicate's),
 * which its link fact types name. */
@property (nonatomic, readwrite, copy) NSString *objectificationId;
@end

@interface ORMFactType ()
@property (nonatomic, readwrite) ORMFactTypeKind kind;
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *roles;
@property (nonatomic, readwrite, copy) NSArray<ORMReadingOrder *> *readingOrders;
@property (nonatomic, readwrite, weak) ORMObjectType *objectifyingType;
@property (nonatomic, readwrite, weak) ORMFactType *impliedByFactType;
@property (nonatomic, readwrite, copy) NSArray<ORMFactType *> *linkFactTypes;
@property (nonatomic, readwrite) BOOL isDerived;
/* What the file says of it: PreferredIdentificationPath (nil where it
 * leaves it out, true by default for a subtype's first supertype), and
 * ProvidesPreferredIdentifier. */
@property (nonatomic, readwrite, strong) NSNumber *preferredIdentificationPath;
@property (nonatomic, readwrite) BOOL saysProvidesPreferredIdentifier;
/* A name given it (Name), nil where it has none; and the one NORMA keeps
 * derived from its readings (_Name), as it does for every ordinary fact
 * type, nil where it keeps none. Its name is the one given, else the
 * derived one. */
@property (nonatomic, readwrite, copy) NSString *explicitName;
@property (nonatomic, readwrite) BOOL isReferenceData;
/* A unary's reading as the last change left it (nil for another fact
 * type): when it is no longer that, its implicit type is named after it. */
@property (nonatomic, readwrite, copy) NSString *lastUnaryReading;
@property (nonatomic, readwrite, copy) NSString *savedDerivedName;
@end

@interface ORMRole ()
@property (nonatomic, readwrite, weak) ORMFactType *factType;
@property (nonatomic, readwrite, weak) ORMObjectType *player;
@property (nonatomic, readwrite) NSUInteger index;
@property (nonatomic, readwrite, strong) ORMValueConstraint *valueConstraint;
@property (nonatomic, readwrite) BOOL isSubtypeMetaRole;
@property (nonatomic, readwrite) BOOL isSupertypeMetaRole;
@property (nonatomic, readwrite, weak) ORMRole *proxiedRole;
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *proxies;
@property (nonatomic, readwrite, copy) NSArray<ORMConstraint *> *constraints;
/* The sample population's role instances under it, in the file's order. */
@property (nonatomic, readwrite, copy) NSArray<ORMRoleInstance *> *roleInstances;
@end

@interface ORMReadingOrder ()
@property (nonatomic, readwrite, weak) ORMFactType *factType;
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *roles;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *unresolvedRoleIds;
@property (nonatomic, readwrite, copy) NSArray<ORMReading *> *readings;
@end

@interface ORMReading ()
@property (nonatomic, readwrite, weak) ORMReadingOrder *readingOrder;
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *words;
@property (nonatomic, readwrite, strong) ORMReadingText *parsedText;
@end

@interface ORMRoleSequence ()
/* The constraint it is a sequence of. */
@property (nonatomic, readwrite, weak) ORMConstraint *constraint;
/* Set, a role kept keeps its use's id, one added is given one. */
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *roles;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *roleUseIds;
/* Both as read. */
- (void)setRoles:(NSArray<ORMRole *> *)roles useIds:(NSArray<NSString *> *)useIds;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *unresolvedRoleIds;
@property (nonatomic, readwrite) BOOL hasJoinPath;
@end

@interface ORMConstraint ()
@property (nonatomic, readwrite) ORMConstraintKind kind;
@property (nonatomic, readwrite) ORMModality modality;
@property (nonatomic, readwrite, copy) NSArray<ORMRoleSequence *> *roleSequences;
@property (nonatomic, readwrite) BOOL isInternal;
@property (nonatomic, readwrite) BOOL isSimple;
@property (nonatomic, readwrite) BOOL isImplied;
@property (nonatomic, readwrite, weak) ORMObjectType *preferredIdentifierFor;
@property (nonatomic, readwrite, weak) ORMConstraint *exclusiveOrPartner;
@property (nonatomic, readwrite) NSUInteger minFrequency;
@property (nonatomic, readwrite) NSUInteger maxFrequency;
@property (nonatomic, readwrite) ORMRingType ringType;
@property (nonatomic, readwrite, copy) NSString *comparisonOperator;
/* For NORMA's implied inclusive-or: the object type it is implied by
 * (ImpliedByObjectType), by id as the file names it. */
@property (nonatomic, readwrite, copy) NSString *impliedByObjectTypeId;
@end

@interface ORMValueRange ()
@property (nonatomic, readwrite, weak) ORMValueConstraint *constraint;
@property (nonatomic, readwrite, copy) NSString *minValue;
@property (nonatomic, readwrite, copy) NSString *maxValue;
@property (nonatomic, readwrite) ORMRangeInclusion minInclusion;
@property (nonatomic, readwrite) ORMRangeInclusion maxInclusion;
@end

@interface ORMValueConstraint ()
@property (nonatomic, readwrite, copy) NSArray<ORMValueRange *> *ranges;
/* The object type or role it is the value constraint of. */
@property (nonatomic, readwrite, weak) ORMElement *owner;
@end

@interface ORMDataType ()
@property (nonatomic, readwrite, copy) NSString *typeName;
@end

@interface ORMModelNote ()
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, copy) NSArray<ORMElement *> *referencedElements;
@end

@interface ORMShape ()
@property (nonatomic, readwrite) ORMShapeKind kind;
@property (nonatomic, readwrite) NSRect bounds;
/* The bounds the file has, as they are: the reader's. */
- (void)setBoundsAsRead:(NSRect)bounds;
@property (nonatomic, readwrite, weak) id subject;
@property (nonatomic, readwrite, copy) NSString *subjectId;
@property (nonatomic, readwrite, weak) ORMDiagram *diagram;
@property (nonatomic, readwrite, weak) ORMShape *parent;
@property (nonatomic, readwrite, copy) NSArray<ORMShape *> *relativeShapes;
@property (nonatomic, readwrite) BOOL isExpanded;
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *roleDisplayOrder;
@property (nonatomic, readwrite) ORMFactTypeOrientation orientation;
@property (nonatomic, readwrite) BOOL constraintsBelow;
@property (nonatomic, readwrite) BOOL expandsReferenceMode;
@end

@interface ORMDiagram ()
@property (nonatomic, readwrite, copy) NSArray<ORMShape *> *shapes;
@property (nonatomic, readwrite) BOOL isCompleteView;
@property (nonatomic, readwrite, copy) NSString *baseFontName;
@property (nonatomic, readwrite) double baseFontSize;
/* Reads the diagram's shapes, registering each with the model. */
- (void)readShapes;
/* A new shape in the model, inside a model change: on the diagram, or on
 * its parent (a reading on its fact type); and one taken away, with the
 * shapes placed on it. */
- (void)addShape:(ORMShape *)shape;
- (void)removeShape:(ORMShape *)shape;
@end

@interface ORMModel ()
/* Every element by id, and a way for the diagram to add its
 * shapes. */
- (void)registerElement:(ORMElement *)element;
/* The element read from xml: when the model is read again, the one read
 * before for its id, if of the class, reset; else a new one. */
- (id)element:(Class)elementClass for:(NSXMLElement *)xml;
/* The document read again into the same model: an element whose id is
 * still there is the same object, with its values read anew. */
- (void)readDocumentAgain:(NSXMLDocument *)document;
/* Whether the element is in the model: the links to it are kept up. */
- (BOOL)holds:(ORMElement *)element;
/* "InternalUniquenessConstraint8": the prefix and a number above every
 * one a name of the model has had with it since it was read. */
- (NSString *)nextNameWithPrefix:(NSString *)prefix;
/* A new diagram in the model, after the others. */
- (void)addDiagram:(ORMDiagram *)diagram;
/* A new element taken into the model: registered, and listed where its
 * kind is (data types, object types, fact types, constraints, notes). */
- (void)addElement:(ORMElement *)element;
/* An element gone from the model: unlisted and unregistered, with what it
 * holds (a value constraint's ranges, a fact type's roles and readings, a
 * constraint's sequences, a value type's value constraint). */
- (void)removeElement:(ORMElement *)element;
/* How each kind of reference mode names its value type ("{0}_{1}"), by
 * kind ("Popular"); the model's custom reference modes, name to kind. */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *referenceModeFormats;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *customReferenceModes;
/* What ORMPath reads beside the model: join paths, derivation rules,
 * populations, cardinalities, each a dictionary by owner id. */
@property (nonatomic, strong) NSMutableDictionary *extras;
@property (nonatomic, readwrite, copy) NSArray<ORMCoreDataMapping *> *coreDataMappings;
/* The queries the document keeps, in order. */
@property (nonatomic, copy) NSArray<ORMStoredQuery *> *storedQueries;
/* While a change is made: the ids of the elements it took out, and the
 * object types whose links it changed (the roles they play, those roles'
 * constraints). */
@property (nonatomic, strong) NSMutableSet<NSString *> *removedIds;
@property (nonatomic, strong) NSHashTable<ORMObjectType *> *relinkedTypes;
/* Whether a reading of the file has NORMA's <orm:ExpandedData>. */
@property (nonatomic) BOOL readingsHaveExpandedData;
@end

@interface ORMModel (ORMPathReading)
- (void)readPathsAndPopulations;
@end

@interface ORMModel (ORMCoreDataMappingReading)
- (void)readCoreDataMappings;
@end

/* What a mapping's element has, as it has it (ORMCoreDataMapping.m): its
 * public values are worked out from these. */
@interface ORMMappingMember : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
/* By and Via as written, nil where not. */
@property (nonatomic, copy) NSString *correlationId;
@property (nonatomic, copy) NSString *viaId;
@property (nonatomic) BOOL isOuter;
@property (nonatomic) BOOL correlationIsOptional;
@property (nonatomic, copy) NSArray<NSString *> *heldRoleIds;
@property (nonatomic, copy) NSArray<NSString *> *requiredRoleIds;
@end

/* An object type's <ObjectTypeMapping>: a joined type's members, and a
 * transformable's class and transformer, stay when it is mapped
 * otherwise. */
@interface ORMMappingOption : NSObject
@property (nonatomic, copy) NSString *objectTypeId;
@property (nonatomic) ORMObjectTypeMapping how;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *transformerName;
@property (nonatomic, copy) NSArray<ORMMappingMember *> *members;
@end

@interface ORMCoreDataMapping ()
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite, copy) NSString *validationPath;
@property (nonatomic, readwrite) ORMMappingScope scope;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *scopeIds;
@property (nonatomic, readwrite) BOOL materializesIdentifiers;
@property (nonatomic, readwrite) BOOL servesOData;
@property (nonatomic, readwrite, copy) NSString *odataNamespace;
@property (nonatomic, readwrite) ORMSyncDirection syncDirection;
@property (nonatomic, readwrite, copy) NSString *syncConflicts;
/* <Sync> elements, in the order of the document: [source id, direction
 * name, conflicts or ""]. */
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *syncs;
@property (nonatomic, readwrite) ORMMappingStyle style;
/* Set for the mapping, nil for the style's. */
@property (nonatomic, copy) NSNumber *flattensSubtypesSet;
@property (nonatomic, copy) NSNumber *absorbsIdentifierTypesSet;
@property (nonatomic, readwrite) BOOL valueSetsAsEntities;
@property (nonatomic, readwrite, copy) NSString *codeGenerationType;
/* In the order of the document: [source id, name] pairs, options,
 * excluded source ids, kept element paths. */
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *overrides;
@property (nonatomic, copy) NSArray<ORMMappingOption *> *options;
@property (nonatomic, copy) NSArray<NSString *> *excluded;
@property (nonatomic, copy) NSArray<NSString *> *kept;
/* The baseline's contents, as kept. */
@property (nonatomic, copy) NSString *baselineXML;
/* Every value a new mapping's, by the name; every value as the element
 * has it. */
- (void)resetNamed:(NSString *)name;
- (void)readElement:(NSXMLElement *)element;
- (ORMMappingOption *)optionFor:(NSString *)objectTypeId;
- (ORMMappingMember *)memberWithId:(NSString *)memberId;
@end

/* A node or a step of a query as the document keeps it (ORMQuery.m), each
 * value as written, nil where it is not: a node's object type (ref, the
 * root's) or role, a step's fact type (ref) and entry role. ORMQuery is
 * what it says, read from these. */
@interface ORMQueryPart : NSObject <NSCopying>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) BOOL isStep;
/* A value node (ormq:Value), under the node it is computed for: its name,
 * and its expression as the file keeps it (docs/EXPRESSIONS.md); ref its
 * value type. */
@property (nonatomic) BOOL isValue;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *expression;
@property (nonatomic, copy) NSString *ref;
@property (nonatomic, copy) NSString *roleId;
@property (nonatomic, copy) NSString *projected;
@property (nonatomic, copy) NSString *forRole;
@property (nonatomic, copy) NSString *comparison;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *compareTo;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *combine;
@property (nonatomic, copy) NSString *sort;
@property (nonatomic, copy) NSString *operatorName;
@property (nonatomic, copy) NSString *countComparison;
@property (nonatomic, copy) NSString *countValueText;
@property (nonatomic, copy) NSString *aggregateName;
@property (nonatomic, copy) NSString *aggregateNodeId;
@property (nonatomic, copy) NSString *groupNodeId;
@property (nonatomic, copy) NSString *compareAggregate;
@property (nonatomic, copy) NSString *compareGroupNode;
/* A node's steps, a step's nodes, in order. */
@property (nonatomic, copy) NSArray<ORMQueryPart *> *parts;
/* The part it is in; nil for a root, and for one taken out. */
- (ORMQueryPart *)parent;
- (NSUInteger)index;
- (NSArray<ORMQueryPart *> *)steps;
- (NSArray<ORMQueryPart *> *)nodes;
/* A node's value nodes. */
- (NSArray<ORMQueryPart *> *)values;
- (void)addPart:(ORMQueryPart *)part;
- (void)insertPart:(ORMQueryPart *)part atIndex:(NSUInteger)index;
- (void)detach;
/* The part and those below it, depth first. */
- (NSArray<ORMQueryPart *> *)tree;
@end

/* A query as the document keeps it: its name (nil where it has none),
 * kind, modality, function and what it is of, as written; its root node. */
@interface ORMStoredQuery : ORMElement <NSCopying>
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *modality;
@property (nonatomic, copy) NSString *function;
@property (nonatomic, copy) NSString *of;
@property (nonatomic, strong) ORMQueryPart *root;
@end

@interface ORMModel (ORMQueryReading)
- (void)readQueries;
@end

@interface ORMNormaWriter (ORMDerivations)
/* The derivation rule of the fact type or subtype of the id written: a
 * derivation query's path with it. */
- (void)writeDerivationOf:(NSString *)identifier;
@end

@interface ORMNormaWriter (ORMQueries)
/* A query's element, made where it has none, its values as the model's. */
- (void)writeStoredQuery:(ORMStoredQuery *)query;
@end

@interface ORMNormaWriter (ORMCoreDataMappings)
/* A mapping's element, made where it has none, its values as the model's. */
- (void)writeCoreDataMapping:(ORMCoreDataMapping *)mapping;
@end

/* Where two models read differ, the first place found, in words; nil when
 * they agree element for element (docs/MODEL.md, the agreement check). */
NSString *ORMModelDisagreement(ORMModel *model, ORMModel *other);

/* The array without the object (the same object, not an equal one);
 * the array itself where it is not there. */
NSArray *ORMWithout(NSArray *array, id object);

/* What NORMA keeps beside the model, as it writes it (ORMNormalizer.m):
 * a list of <prefix:local ref/> children made to name exactly the
 * targets, [local name, id] pairs, those listed keeping their place; a
 * multiplicity's name; an element as a comparable value; a reading's
 * <orm:ExpandedData>. */
void ORMSyncRefs(NSXMLDocument *document, NSXMLElement *container, NSArray<NSArray *> *targets);
NSString *ORMMultiplicityName(ORMMultiplicity multiplicity);
NSArray *ORMShapeOf(NSXMLElement *element);
NSXMLElement *ORMExpandedData(NSXMLDocument *document, NSString *text, NSUInteger arity);

/* NORMA's range inclusion of the name: Open, Closed, else NotSet. */
ORMRangeInclusion ORMInclusionNamed(NSString *name);

/* The orm:ORMModel element of a document: its root, or the root's child. */
NSXMLElement *ORMModelElementOfDocument(NSXMLDocument *document);

/* The sample population, as the file has it: each instance and fact what
 * it names, by id; what that comes to (instancesByRole, a role instance's
 * player) derived. */
@interface ORMInstance ()
@property (nonatomic, readwrite, weak) ORMObjectType *objectType;
@property (nonatomic, readwrite, copy) NSString *value;
/* ValueTypeInstance, EntityTypeInstance or EntityTypeSubtypeInstance. */
@property (nonatomic, readwrite, copy) NSString *elementName;
/* A number's or moment's culture-invariant form, beside its value. */
@property (nonatomic, readwrite, copy) NSString *invariantValue;
/* The role instances that identify an entity instance, by id, and the
 * supertype instance a subtype instance is. */
@property (nonatomic, readwrite, copy) NSArray<NSString *> *identifyingRoleInstances;
@property (nonatomic, readwrite, copy) NSString *supertypeInstanceId;
@property (nonatomic, readwrite, copy) NSString *objectifiedInstanceId;
/* The unary roles it plays, NORMA keeping those facts on it, by role id. */
@property (nonatomic, readwrite, copy) NSArray<NSString *> *unaryRoleIds;
@end

@interface ORMRoleInstance ()
/* EntityTypeRoleInstance or FactTypeRoleInstance. */
@property (nonatomic, readwrite, copy) NSString *elementName;
@property (nonatomic, readwrite, weak) ORMRole *role;
@property (nonatomic, readwrite, copy) NSString *instanceId;
@end

@interface ORMFactInstance ()
@property (nonatomic, readwrite, weak) ORMFactType *factType;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *roleInstanceIds;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, ORMInstance *> *instancesByRole;
@property (nonatomic, readwrite) BOOL isKeptOnPlayer;
@end

@interface ORMModel (ORMPopulations)
/* What the population's elements come to: each role instance's player,
 * each fact's instances by role, the unary facts NORMA keeps on their
 * players. Worked out when read, and after a change to a population. */
- (void)derivePopulations;
/* Whether it has a sample population: instances, role or fact instances. */
- (BOOL)hasPopulation;
/* An element of the sample population taken into the model, or out of it,
 * inside a model change: listed with its type, its fact type or its role,
 * and registered. */
- (void)addPopulationElement:(ORMElement *)element;
- (void)removePopulationElement:(ORMElement *)element;
@end

@interface ORMPathedRole ()
@property (nonatomic, readwrite, weak) ORMRole *role;
@property (nonatomic, readwrite) ORMPathedRolePurpose purpose;
@property (nonatomic, readwrite) BOOL isNegated;
@property (nonatomic, readwrite, strong) ORMValueConstraint *valueConstraint;
@property (nonatomic, readwrite, weak) ORMPathedRole *correlatedWith;
@property (nonatomic, readwrite, copy) NSString *unifierId;
@property (nonatomic, readwrite, weak) ORMRolePath *path;
@end

@interface ORMRolePath ()
@property (nonatomic, readwrite, weak) ORMObjectType *rootObjectType;
@property (nonatomic, readwrite, copy) NSString *rootId;
@property (nonatomic, readwrite) BOOL rootIsNegated;
@property (nonatomic, readwrite, strong) ORMValueConstraint *rootValueConstraint;
@property (nonatomic, readwrite, copy) NSString *rootUnifierId;
@property (nonatomic, readwrite, copy) NSArray<ORMPathedRole *> *pathedRoles;
@property (nonatomic, readwrite, copy) NSArray<ORMRolePath *> *subPaths;
@property (nonatomic, readwrite) ORMPathSplit split;
@property (nonatomic, readwrite) BOOL splitIsNegated;
@property (nonatomic, readwrite, weak) ORMRolePath *parent;
@end

@interface ORMPathSource ()
@property (nonatomic, readwrite) ORMPathSourceKind kind;
@property (nonatomic, readwrite, weak) ORMRolePath *root;
@property (nonatomic, readwrite, weak) ORMPathedRole *pathedRole;
@property (nonatomic, readwrite, weak) ORMCalculation *calculation;
@property (nonatomic, readwrite, copy) NSString *constant;
/* Resolved once every element is read: what the source element names. */
@property (nonatomic, copy) NSString *reference;
@end

@interface ORMCalculation ()
@property (nonatomic, readwrite, copy) NSString *functionName;
@property (nonatomic, readwrite) BOOL isBoolean;
@property (nonatomic, readwrite, copy) NSArray<ORMPathSource *> *inputs;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *parameterNames;
@property (nonatomic, readwrite, copy) NSArray<ORMPathSource *> *aggregationContext;
@property (nonatomic, readwrite) BOOL isAggregate;
@end

@interface ORMRolePathOwner ()
@property (nonatomic, readwrite, copy) NSArray<ORMRolePath *> *paths;
@property (nonatomic, readwrite, copy) NSArray<ORMCalculation *> *calculations;
@property (nonatomic, readwrite, copy) NSArray<ORMCalculation *> *conditions;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, ORMPathSource *> *projections;
/* The ids of its projection element (JoinPathProjection,
 * DerivationProjection) and of each target's (by the target's id). */
@property (nonatomic, readwrite, copy) NSString *projectionId;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *projectionIds;
@end

@interface ORMModel (ORMJoinPaths)
/* A sequence's join path, inside a model change: registered with its role
 * paths and pathed roles. */
- (void)setJoinPath:(ORMRolePathOwner *)joinPath ofSequence:(ORMRoleSequence *)sequence;
@end

/* A derivation rule as the file has it: beside what it says, the ids of
 * its path (FactTypeDerivationPath) and its informal note, nil where it
 * has none, and whether it has more than words: NORMA's role path, or an
 * older DerivationExpression. */
@interface ORMDerivationRule ()
@property (nonatomic, readwrite) BOOL isPartial;
@property (nonatomic, readwrite) BOOL isStored;
@property (nonatomic, readwrite, copy) NSString *informalText;
@property (nonatomic, readwrite) BOOL isSubtypeRule;
@property (nonatomic, readwrite, copy) NSString *pathId;
/* The path's own name, where it has one: a query read from the rule is
 * called by it. */
@property (nonatomic, readwrite, copy) NSString *pathName;
@property (nonatomic, readwrite, copy) NSString *noteId;
@property (nonatomic, readwrite) BOOL hasRolePath;
@property (nonatomic, readwrite) BOOL hasExpression;
@end

@interface ORMModel (ORMDerivationRules)
/* Each fact type's and subtype's derivation rule, by its id. */
- (NSDictionary<NSString *, ORMDerivationRule *> *)derivationRules;
/* A fact type's rule set, or taken away (nil), inside a model change; the
 * fact type derived while it has one with a path or an expression. */
- (void)setDerivationRule:(ORMDerivationRule *)rule ofFactType:(ORMFactType *)fact;
/* A subtype's, likewise. */
- (void)setDerivationRule:(ORMDerivationRule *)rule ofSubtype:(ORMObjectType *)type;
@end

