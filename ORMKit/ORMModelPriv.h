/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagram.h"

/* What the projection's builders set: the public classes are read-only. */

@interface ORMElement ()
@property (nonatomic, readwrite, strong) NSXMLElement *element;
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, weak) ORMModel *model;
@property (nonatomic, readwrite, copy) NSString *name;
- (instancetype)initWithElement:(NSXMLElement *)element model:(ORMModel *)model;
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
@property (nonatomic, readwrite, weak) ORMDataType *dataType;
@property (nonatomic, readwrite) NSInteger dataTypeLength;
@property (nonatomic, readwrite) NSInteger dataTypeScale;
@property (nonatomic, readwrite, strong) ORMValueConstraint *valueConstraint;
@property (nonatomic, readwrite, copy) NSArray<ORMObjectType *> *supertypes;
@property (nonatomic, readwrite, copy) NSArray<ORMObjectType *> *subtypes;
@property (nonatomic, readwrite, copy) NSArray<ORMFactType *> *supertypeFacts;
@property (nonatomic, readwrite, copy) NSString *definitionText;
@property (nonatomic, readwrite, copy) NSString *noteText;
@end

@interface ORMFactType ()
@property (nonatomic, readwrite) ORMFactTypeKind kind;
@property (nonatomic, readwrite, copy) NSArray<ORMRole *> *roles;
@property (nonatomic, readwrite, copy) NSArray<ORMReadingOrder *> *readingOrders;
@property (nonatomic, readwrite, copy) NSArray<ORMConstraint *> *internalConstraints;
@property (nonatomic, readwrite, weak) ORMObjectType *objectifyingType;
@property (nonatomic, readwrite, weak) ORMFactType *impliedByFactType;
@property (nonatomic, readwrite) BOOL isDerived;
@property (nonatomic, readwrite) BOOL providesPreferredIdentifier;
@end

@interface ORMRole ()
@property (nonatomic, readwrite, weak) ORMFactType *factType;
@property (nonatomic, readwrite, weak) ORMObjectType *player;
@property (nonatomic, readwrite) NSUInteger index;
@property (nonatomic, readwrite) BOOL isMandatory;
@property (nonatomic, readwrite) BOOL isUnique;
@property (nonatomic, readwrite, strong) ORMValueConstraint *valueConstraint;
@property (nonatomic, readwrite) BOOL isSubtypeMetaRole;
@property (nonatomic, readwrite) BOOL isSupertypeMetaRole;
@property (nonatomic, readwrite, weak) ORMRole *proxiedRole;
@property (nonatomic, readwrite, copy) NSArray<ORMConstraint *> *constraints;
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
@end

@interface ORMModel ()
/* Every projected element by id, and a way for the diagram to add its
 * shapes. */
- (void)registerElement:(ORMElement *)element;
/* What ORMPath reads beside the model: join paths, derivation rules,
 * populations, cardinalities, each a dictionary by owner id. */
@property (nonatomic, strong) NSMutableDictionary *extras;
@end

@interface ORMModel (ORMPathReading)
- (void)readPathsAndPopulations;
@end

/* The orm:ORMModel element of a document: its root, or the root's child. */
NSXMLElement *ORMModelElementOfDocument(NSXMLDocument *document);
