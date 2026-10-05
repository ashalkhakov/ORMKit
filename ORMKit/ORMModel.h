/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* An ORM2 model as NORMA saves it, read from the XML into objects.
 *
 * The NSXMLDocument is the model; these objects are a projection of it,
 * rebuilt after every change (ORMEditor does that), and never changed in
 * place. Each holds the element it was read from. Their links to one
 * another are weak and the ORMModel holds them all, so keep the model
 * alive while you use what it gave you. */

@class ORMModel, ORMObjectType, ORMFactType, ORMRole, ORMReadingOrder, ORMReading, ORMConstraint, ORMRoleSequence,
	ORMValueConstraint, ORMDataType, ORMModelNote, ORMDiagram;

/* What every projected element has. */
@interface ORMElement : NSObject
@property (nonatomic, readonly, strong) NSXMLElement *element;
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, weak) ORMModel *model;
/* What the element is called in the model; NORMA names constraints
 * (InternalUniquenessConstraint1) and the fact types it derives a name for. */
@property (nonatomic, readonly, copy) NSString *name;
@end

#pragma mark Object types

typedef NS_ENUM(NSInteger, ORMObjectTypeKind) {
	ORMEntityType,
	ORMValueType,
	/* An objectified fact type: an entity type nesting a fact type. */
	ORMObjectifiedType,
};

/* The kind of a reference mode, as NORMA's ReferenceModeKind has it: it
 * says how the identifying value type is named from the entity type's
 * name {0} and the mode {1}. */
typedef NS_ENUM(NSInteger, ORMReferenceModeKind) {
	ORMReferenceModeNone,
	/* {0}_{1}: Person(.id) is identified by Person_id. */
	ORMReferenceModePopular,
	/* {1}Value: Mass(kg:) is identified by kgValue. */
	ORMReferenceModeUnitBased,
	/* {1}: Country(.CountryCode) is identified by CountryCode. */
	ORMReferenceModeGeneral,
};

@interface ORMObjectType : ORMElement
@property (nonatomic, readonly) ORMObjectTypeKind kind;
@property (nonatomic, readonly) BOOL isEntity;
@property (nonatomic, readonly) BOOL isIndependent;
@property (nonatomic, readonly) BOOL isExternal;
/* Personal: referred to as who rather than which, in verbalizations. */
@property (nonatomic, readonly) BOOL isPersonal;
/* Implied by an objectification, as NORMA creates for a fact type it
 * objectifies implicitly. */
@property (nonatomic, readonly) BOOL isImplied;
/* The hidden value type NORMA gives a unary fact type's second role:
 * "Warehouse is enabled" is stored as a binary fact type whose other role
 * this plays. Never drawn or verbalized on its own. */
@property (nonatomic, readonly) BOOL isImplicitBooleanValue;

/* The roles it plays, in fact type order. */
@property (nonatomic, readonly, copy) NSArray<ORMRole *> *playedRoles;
/* The uniqueness constraint that identifies it; nil for a value type, or
 * an entity type that has none yet. */
@property (nonatomic, readonly, weak) ORMConstraint *preferredIdentifier;
/* The fact type it objectifies, when it is an objectified type. */
@property (nonatomic, readonly, weak) ORMFactType *nestedFactType;

/* Its reference mode, as Person(.id) shows "id"; nil when it has none.
 * NORMA derives it from the preferred identifier: a single role played by
 * a value type named by the mode's kind. */
@property (nonatomic, readonly, copy) NSString *referenceMode;
@property (nonatomic, readonly) ORMReferenceModeKind referenceModeKind;
/* The value type that holds the reference mode's values. */
@property (nonatomic, readonly, weak) ORMObjectType *referenceModeValueType;
/* The binary fact type the reference mode abbreviates. */
@property (nonatomic, readonly, weak) ORMFactType *referenceModeFactType;

/* For a value type: its conceptual data type, and that type's length and
 * scale where they apply (0: none given). */
@property (nonatomic, readonly, weak) ORMDataType *dataType;
@property (nonatomic, readonly) NSInteger dataTypeLength;
@property (nonatomic, readonly) NSInteger dataTypeScale;
/* For a value type, or an entity type through its reference mode's. */
@property (nonatomic, readonly, strong) ORMValueConstraint *valueConstraint;

/* Direct supertypes and subtypes, by the subtype fact types. */
@property (nonatomic, readonly, copy) NSArray<ORMObjectType *> *supertypes;
@property (nonatomic, readonly, copy) NSArray<ORMObjectType *> *subtypes;
/* The subtype facts that attach it to its supertypes. */
@property (nonatomic, readonly, copy) NSArray<ORMFactType *> *supertypeFacts;
/* The supertype it is identified as, having no identifier of its own: the
 * one its preferred identification path goes to (NORMA's
 * PreferredIdentificationPath), else its first. nil without supertypes. */
- (ORMObjectType *)identifyingSupertype;

/* Free text: NORMA's Definition and Note. */
@property (nonatomic, readonly, copy) NSString *definitionText;
@property (nonatomic, readonly, copy) NSString *noteText;

/* "Person(.id)", "Mass(kg:)", "Name": how a diagram labels it. */
- (NSString *)displayName;
/* Whether it is the supertype's, at any depth. */
- (BOOL)isSubtypeOf:(ORMObjectType *)supertype;
/* Its supertypes, at any depth, nearest first. */
- (NSArray<ORMObjectType *> *)allSupertypes;
@end

#pragma mark Fact types

typedef NS_ENUM(NSInteger, ORMFactTypeKind) {
	ORMFactTypeOrdinary,
	/* Subtype to supertype: two meta roles, read "is a". */
	ORMFactTypeSubtype,
	/* A link fact type NORMA implies between an objectified fact type and
	 * the players of its roles. */
	ORMFactTypeImplied,
};

@interface ORMFactType : ORMElement
@property (nonatomic, readonly) ORMFactTypeKind kind;
/* Its roles in the order the fact type declares them: {0}, {1}, ... */
@property (nonatomic, readonly, copy) NSArray<ORMRole *> *roles;
@property (nonatomic, readonly, copy) NSArray<ORMReadingOrder *> *readingOrders;
/* The constraints that span only this fact type's roles. */
@property (nonatomic, readonly, copy) NSArray<ORMConstraint *> *internalConstraints;
/* The object type that objectifies it, when one does. */
@property (nonatomic, readonly, weak) ORMObjectType *objectifyingType;
/* For a link fact type, the objectified fact type it is implied by. */
@property (nonatomic, readonly, weak) ORMFactType *impliedByFactType;
/* Derived or semiderived: NORMA keeps the rule; ORMKit keeps it as XML. */
@property (nonatomic, readonly) BOOL isDerived;
/* For a subtype fact: whether the subtype is identified through the
 * supertype (true unless the subtype has its own identifier). */
@property (nonatomic, readonly) BOOL providesPreferredIdentifier;

/* The number of roles a reader sees: 1 for a unary fact type, though NORMA
 * stores it with a second, implicit role. */
- (NSUInteger)arity;
/* The roles a reader sees: without a unary's implicit boolean role. */
- (NSArray<ORMRole *> *)visibleRoles;
- (BOOL)isUnary;
/* The first reading of the first reading order: what NORMA shows. */
- (ORMReading *)primaryReading;
/* A reading starting at the role, and the order it reads the roles in;
 * nil when the fact type has none. */
- (ORMReadingOrder *)readingOrderStartingWithRole:(ORMRole *)role;
/* A reading order whose roles are exactly these in this order, or nil. */
- (ORMReadingOrder *)readingOrderForRoles:(NSArray<ORMRole *> *)roles;
/* The internal uniqueness constraints. */
- (NSArray<ORMConstraint *> *)uniquenessConstraints;
/* Whether an internal uniqueness constraint spans exactly these roles. */
- (BOOL)hasUniquenessOverRoles:(NSArray<ORMRole *> *)roles;
/* "PersonHasName": NORMA's derived name, from the primary reading. */
- (NSString *)derivedName;
@end

/* How many of the other roles' players one instance of a binary fact
 * type's role player may meet, as NORMA's _Multiplicity spells it from
 * the constraints: an indication for UML-minded readers. */
typedef NS_ENUM(NSInteger, ORMMultiplicity) {
	ORMMultiplicityUnspecified,
	ORMMultiplicityZeroToOne,
	ORMMultiplicityZeroToMany,
	ORMMultiplicityExactlyOne,
	ORMMultiplicityOneToMany,
	/* More than one uniqueness constraint on the other role. */
	ORMMultiplicityIndeterminate,
};

@interface ORMRole : ORMElement
@property (nonatomic, readonly, weak) ORMFactType *factType;
/* The object type that plays it; nil when none is attached yet. */
@property (nonatomic, readonly, weak) ORMObjectType *player;
/* Its place among the fact type's roles. */
@property (nonatomic, readonly) NSUInteger index;
/* A simple mandatory constraint covers it. */
@property (nonatomic, readonly) BOOL isMandatory;
/* An internal uniqueness constraint covers exactly this role. */
@property (nonatomic, readonly) BOOL isUnique;
@property (nonatomic, readonly, strong) ORMValueConstraint *valueConstraint;
/* For a subtype fact's roles. */
@property (nonatomic, readonly) BOOL isSubtypeMetaRole;
@property (nonatomic, readonly) BOOL isSupertypeMetaRole;
/* For a link fact type's role: the role of the objectified fact type it
 * stands for (NORMA's RoleProxy). */
@property (nonatomic, readonly, weak) ORMRole *proxiedRole;
/* Every constraint that has the role in one of its sequences. */
@property (nonatomic, readonly, copy) NSArray<ORMConstraint *> *constraints;

/* The other role of a binary fact type; nil otherwise. */
- (ORMRole *)oppositeRole;
/* NORMA's _Multiplicity: what the constraints on the opposite role say
 * about how many of this role's players each opposite player meets. */
- (ORMMultiplicity)multiplicity;
@end

@interface ORMReadingOrder : ORMElement
@property (nonatomic, readonly, weak) ORMFactType *factType;
/* The roles in the order its readings place them: {0} is the first. */
@property (nonatomic, readonly, copy) NSArray<ORMRole *> *roles;
@property (nonatomic, readonly, copy) NSArray<ORMReading *> *readings;
@end

@interface ORMReading : ORMElement
@property (nonatomic, readonly, weak) ORMReadingOrder *readingOrder;
/* As NORMA keeps it: "{0} was born in {1}". */
@property (nonatomic, readonly, copy) NSString *text;
/* The reading with each placeholder replaced by its role player's name:
 * "Person was born in Country". */
- (NSString *)expandedText;
@end

#pragma mark Constraints

typedef NS_ENUM(NSInteger, ORMConstraintKind) {
	ORMUniquenessConstraint,
	ORMMandatoryConstraint,
	ORMFrequencyConstraint,
	ORMRingConstraint,
	ORMSubsetConstraint,
	ORMEqualityConstraint,
	ORMExclusionConstraint,
	ORMValueComparisonConstraint,
};

/* Ring constraint types, as bits: NORMA's combined types (AcyclicTransitive,
 * PurelyReflexive, ...) are their ORs. */
typedef NS_OPTIONS(NSUInteger, ORMRingType) {
	ORMRingReflexive = 1 << 0,
	ORMRingIrreflexive = 1 << 1,
	ORMRingSymmetric = 1 << 2,
	ORMRingAsymmetric = 1 << 3,
	ORMRingAntisymmetric = 1 << 4,
	ORMRingTransitive = 1 << 5,
	ORMRingIntransitive = 1 << 6,
	ORMRingStronglyIntransitive = 1 << 7,
	ORMRingAcyclic = 1 << 8,
	/* Each instance relates only to itself. */
	ORMRingPurelyReflexive = 1 << 9,
};

typedef NS_ENUM(NSInteger, ORMModality) {
	ORMAlethic,
	ORMDeontic,
};

/* A set comparison or other constraint argument: a sequence of roles,
 * with the join path NORMA may keep for it left in the XML. */
@interface ORMRoleSequence : ORMElement
@property (nonatomic, readonly, copy) NSArray<ORMRole *> *roles;
/* NORMA keeps a join path for a sequence whose roles are not in one fact
 * type; ORMKit reads that it has one, not what it says. */
@property (nonatomic, readonly) BOOL hasJoinPath;
@end

@interface ORMConstraint : ORMElement
@property (nonatomic, readonly) ORMConstraintKind kind;
@property (nonatomic, readonly) ORMModality modality;
/* Its arguments. Single-sequence constraints (uniqueness, mandatory,
 * frequency, ring, value comparison) have one. */
@property (nonatomic, readonly, copy) NSArray<ORMRoleSequence *> *roleSequences;
/* Uniqueness: whether it spans the roles of one fact type. */
@property (nonatomic, readonly) BOOL isInternal;
/* Mandatory: a simple one covers one role; a disjunctive (inclusive-or)
 * one several. */
@property (nonatomic, readonly) BOOL isSimple;
/* Mandatory: implied by NORMA (an objectification's), not drawn. */
@property (nonatomic, readonly) BOOL isImplied;
/* Uniqueness: the entity type it is the preferred identifier of. */
@property (nonatomic, readonly, weak) ORMObjectType *preferredIdentifierFor;
/* Exclusion with a disjunctive mandatory over the same roles is
 * exclusive-or; each names the other. */
@property (nonatomic, readonly, weak) ORMConstraint *exclusiveOrPartner;
/* Frequency: occurs at least min (>= 1) and at most max (0: no maximum)
 * times. */
@property (nonatomic, readonly) NSUInteger minFrequency;
@property (nonatomic, readonly) NSUInteger maxFrequency;
/* Ring. */
@property (nonatomic, readonly) ORMRingType ringType;
/* Value comparison: "LessThan", "GreaterThanOrEqual", ... as NORMA spells it. */
@property (nonatomic, readonly, copy) NSString *comparisonOperator;

/* Every role of every sequence, without repeats. */
- (NSArray<ORMRole *> *)allRoles;
/* The fact types its roles belong to, without repeats, in order. */
- (NSArray<ORMFactType *> *)factTypes;
/* Whether the constraint is drawn on its own shape (external constraints,
 * frequency, ring) rather than on the fact type's roles. */
- (BOOL)isExternal;
/* NORMA's names for the ring types it supports, and back. */
+ (NSString *)nameOfRingType:(ORMRingType)type;
+ (ORMRingType)ringTypeNamed:(NSString *)name;
@end

#pragma mark Values and data types

typedef NS_ENUM(NSInteger, ORMRangeInclusion) {
	ORMRangeInclusionNotSet,
	ORMRangeOpen,
	ORMRangeClosed,
};

@interface ORMValueRange : ORMElement
@property (nonatomic, readonly, weak) ORMValueConstraint *constraint;
/* Empty when the range has no such bound; equal for a single value. */
@property (nonatomic, readonly, copy) NSString *minValue;
@property (nonatomic, readonly, copy) NSString *maxValue;
@property (nonatomic, readonly) ORMRangeInclusion minInclusion;
@property (nonatomic, readonly) ORMRangeInclusion maxInclusion;
/* "'a'", "1..10", "(0..100]": how a diagram shows it. */
- (NSString *)displayText;
@end

@interface ORMValueConstraint : ORMElement
@property (nonatomic, readonly, copy) NSArray<ORMValueRange *> *ranges;
/* The value type whose values it constrains: its own, a role player's, or
 * an entity type's reference mode's. Its data type says how values read:
 * text quoted, numbers, dates and truth values not. */
@property (nonatomic, readonly, weak) ORMObjectType *valueType;
/* Whether values are written in quotes. */
- (BOOL)quotesValues;
/* "{'M', 'F'}", "{1..10}". */
- (NSString *)displayText;
@end

/* NORMA's conceptual data types, grouped as NORMA groups them. */
typedef NS_ENUM(NSInteger, ORMDataTypeFamily) {
	ORMDataTypeUnspecified,
	ORMDataTypeText,
	ORMDataTypeNumeric,
	ORMDataTypeTemporal,
	ORMDataTypeLogical,
	ORMDataTypeRawData,
	ORMDataTypeOther,
};

@interface ORMDataType : ORMElement
/* The element's local name: "VariableLengthTextDataType". */
@property (nonatomic, readonly, copy) NSString *typeName;
@property (nonatomic, readonly) ORMDataTypeFamily family;
/* "Text: Variable Length", as NORMA's property grid lists it. */
- (NSString *)displayName;
/* Every data type NORMA has, by element name, in its menu order. */
+ (NSArray<NSString *> *)allTypeNames;
+ (NSString *)displayNameOfTypeNamed:(NSString *)typeName;
@end

@interface ORMModelNote : ORMElement
@property (nonatomic, readonly, copy) NSString *text;
/* The elements the note is attached to. */
@property (nonatomic, readonly, copy) NSArray<ORMElement *> *referencedElements;
@end

#pragma mark The model

@interface ORMModel : NSObject
/* The projection of a document; nil with why when it holds no ORM model. */
+ (instancetype)modelOfDocument:(NSXMLDocument *)document reason:(NSString **)reason;

@property (nonatomic, readonly, strong) NSXMLDocument *document;
/* The orm:ORMModel element. */
@property (nonatomic, readonly, strong) NSXMLElement *modelElement;
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *name;

/* In file order. */
@property (nonatomic, readonly, copy) NSArray<ORMObjectType *> *objectTypes;
/* Every fact type, subtype and implied ones too. */
@property (nonatomic, readonly, copy) NSArray<ORMFactType *> *factTypes;
@property (nonatomic, readonly, copy) NSArray<ORMConstraint *> *constraints;
@property (nonatomic, readonly, copy) NSArray<ORMDataType *> *dataTypes;
@property (nonatomic, readonly, copy) NSArray<ORMModelNote *> *notes;
@property (nonatomic, readonly, copy) NSArray<ORMDiagram *> *diagrams;

/* Any projected element by id: object types, fact types, roles, readings,
 * constraints, shapes. */
- (id)elementWithId:(NSString *)identifier;
- (ORMObjectType *)objectTypeNamed:(NSString *)name;
/* Object types a modeller works with: no implicit boolean value types. */
- (NSArray<ORMObjectType *> *)visibleObjectTypes;
/* Fact types and constraints a modeller works with: no subtype or implied
 * fact types, no implied constraints. */
- (NSArray<ORMFactType *> *)ordinaryFactTypes;
- (NSArray<ORMConstraint *> *)externalConstraints;
@end
