/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagram.h"
#import "ORMPath.h"

/* What the projection's builders set: the public classes are read-only. */

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
/* Each class's derived values (worked out from what was read, by
 * -[ORMModel derive]) forgotten, caches too; a subclass calls super. */
- (void)forgetDerivedValues;
@end

@interface ORMObjectType ()
@property (nonatomic, readwrite) ORMObjectTypeKind kind;
@property (nonatomic, readwrite) BOOL isIndependent;
@property (nonatomic, readwrite) BOOL isExternal;
@property (nonatomic, readwrite) BOOL isPersonal;
@property (nonatomic, readwrite) BOOL isImplied;
@property (nonatomic, readwrite) BOOL isImplicitBooleanValue;
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *playedRoles;
@property (nonatomic, readwrite, weak) ORMConstraint *preferredIdentifier;
@property (nonatomic, readwrite, weak) ORMFactType *nestedFactType;
@property (nonatomic, readwrite, copy) NSString *referenceMode;
@property (nonatomic, readwrite) ORMReferenceModeKind referenceModeKind;
@property (nonatomic, readwrite, weak) ORMObjectType *referenceModeValueType;
@property (nonatomic, readwrite, weak) ORMFactType *referenceModeFactType;
@property (nonatomic, readwrite, weak) ORMRole *referenceModeRole;
@property (nonatomic, readwrite, weak) ORMDataType *dataType;
@property (nonatomic, readwrite) NSInteger dataTypeLength;
@property (nonatomic, readwrite) NSInteger dataTypeScale;
@property (nonatomic, readwrite, strong) ORMValueConstraint *valueConstraint;
@property (nonatomic, readwrite, copy) NSArray<ORMObjectType *> *supertypes;
@property (nonatomic, readwrite, copy) NSArray<ORMObjectType *> *subtypes;
@property (nonatomic, readwrite, copy) NSArray<ORMFactType *> *supertypeFacts;
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
@property (nonatomic, readwrite, copy) NSArray<ORMConstraint *> *internalConstraints;
@property (nonatomic, readwrite, weak) ORMObjectType *objectifyingType;
@property (nonatomic, readwrite, weak) ORMFactType *impliedByFactType;
@property (nonatomic, readwrite, copy) NSArray<ORMFactType *> *linkFactTypes;
@property (nonatomic, readwrite) BOOL isDerived;
@property (nonatomic, readwrite) BOOL providesPreferredIdentifier;
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
@property (nonatomic, readwrite, copy) NSString *savedDerivedName;
@end

@interface ORMRole ()
@property (nonatomic, readwrite, weak) ORMFactType *factType;
@property (nonatomic, readwrite, weak) ORMObjectType *player;
@property (nonatomic, readwrite) NSUInteger index;
@property (nonatomic, readwrite) BOOL isMandatory;
@property (nonatomic, readwrite) BOOL isUnique;
@property (nonatomic, readwrite) BOOL isAlethicMandatory;
@property (nonatomic, readwrite) BOOL isAlethicUnique;
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
@property (nonatomic, readwrite, copy) NSArray<ORMReading *> *readings;
@end

@interface ORMReading ()
@property (nonatomic, readwrite, weak) ORMReadingOrder *readingOrder;
@property (nonatomic, readwrite, copy) NSString *text;
@end

@interface ORMRoleSequence ()
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *roles;
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
@property (nonatomic, readwrite, weak) ORMObjectType *valueType;
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
/* Every projected element by id, and a way for the diagram to add its
 * shapes. */
- (void)registerElement:(ORMElement *)element;
/* The element read from xml: when the model is read again, the one read
 * before for its id, if of the class, reset; else a new one. */
- (id)element:(Class)elementClass for:(NSXMLElement *)xml;
/* The document read again into the same model: an element whose id is
 * still there is the same object, with its values read anew. */
- (void)readDocumentAgain:(NSXMLDocument *)document;
/* Every derived value worked out again from what each element holds:
 * played roles, subtyping, internal constraints, a role's constraints and
 * flags, reference modes, link fact types, proxies' players. No XML. */
- (void)derive;
/* Whether the diagrams have been read: they are read when first asked for. */
@property (nonatomic, readonly) BOOL diagramsRead;
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
@end

@interface ORMModel (ORMPathReading)
- (void)readPathsAndPopulations;
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
@end

@interface ORMModel (ORMPopulations)
/* What the population's elements come to: each role instance's player,
 * each fact's instances by role, the unary facts NORMA keeps on their
 * players. Part of -derive. */
- (void)derivePopulations;
/* An element of the sample population taken into the model, or out of it,
 * inside a model change: listed with its type, its fact type or its role,
 * and registered. */
- (void)addPopulationElement:(ORMElement *)element;
- (void)removePopulationElement:(ORMElement *)element;
@end
