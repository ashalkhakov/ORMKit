/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagram.h"

/* Every change to an ORM model goes through an editor.
 *
 * It changes the NSXMLDocument in place, keeps up what NORMA keeps
 * denormalized beside the model (each object type's PlayedRoles, each fact
 * type's InternalConstraints, the _IsMandatory, _Multiplicity, _Name and
 * _ReferenceMode attributes, each reading's ExpandedData), and rebuilds the
 * projection (`model`) afterwards. Each operation is one undoable step:
 * undo restores the document as it was before.
 *
 * Elements are named by id. An operation that cannot be done returns nil
 * or NO and says why in `reason`, in words for the status line. */

/* An object type's default bounds for its name, in points, as NORMA sizes
 * them for its base font: a canvas measures with the real font and sets
 * them again. */
NSSize ORMDefaultObjectTypeSize(NSString *displayName, BOOL twoLines);
/* A fact type shape's bounds for so many roles, horizontal. */
NSSize ORMDefaultFactTypeSize(NSUInteger roles);
/* A role box, in points. */
extern const double ORMRoleBoxWidth;
extern const double ORMRoleBoxHeight;

/* As a point to place a new shape at: beside what it links to. */
extern const NSPoint ORMAutomaticPlacement;
BOOL ORMIsAutomaticPlacement(NSPoint point);

@interface ORMEditor : NSObject

/* A new, empty model as NORMA would start one, with one diagram. */
+ (NSXMLDocument *)newDocumentNamed:(NSString *)name;

/* undoManager may be nil: no undo. */
- (instancetype)initWithDocument:(NSXMLDocument *)document undoManager:(NSUndoManager *)undoManager;

@property (nonatomic, readonly, strong) NSXMLDocument *document;
/* The projection of the document as it is now. */
@property (nonatomic, readonly, strong) ORMModel *model;
/* Called after every change, undo and redo too. */
@property (nonatomic, copy) void (^changed)(void);
/* Whether the document differs from what was read. */
@property (nonatomic, readonly) BOOL hasChanges;

/* The document to write: what NORMA generates from the model (its
 * relational bridges, its model error list) dropped when the model has
 * changed, since they would describe what is gone; NORMA rebuilds them on
 * opening. */
- (NSXMLDocument *)documentForSaving;
/* The bytes of documentForSaving, laid out as the file was. */
- (NSData *)dataForSaving;

/* A change made of several operations, undone as one. */
- (void)group:(NSString *)name with:(void (^)(void))operations;

@end

@interface ORMEditor (ORMObjects)

/* A new entity type; with a reference mode, its identifying value type
 * and fact type too (Person(.id) makes Person_id and "Person has
 * Person_id"). Placed on the diagram when one is given. Its id. */
- (NSString *)addEntityTypeNamed:(NSString *)name
                   referenceMode:(NSString *)mode
                            kind:(ORMReferenceModeKind)kind
                       onDiagram:(NSString *)diagramId
                              at:(NSPoint)point
                          reason:(NSString **)reason;
- (NSString *)addValueTypeNamed:(NSString *)name
                       dataType:(NSString *)typeName
                      onDiagram:(NSString *)diagramId
                             at:(NSPoint)point
                         reason:(NSString **)reason;
/* Names an object type, fact type, constraint, diagram or role. Object
 * type names are unique in a model; a reference mode's value type is
 * renamed along with its entity type. */
- (BOOL)rename:(NSString *)elementId to:(NSString *)name reason:(NSString **)reason;
/* Gives an entity type a reference mode, replacing its identification,
 * or with a nil mode takes the reference mode away (its value type and
 * fact type stay, as plain ones). */
- (BOOL)setReferenceMode:(NSString *)mode
                    kind:(ORMReferenceModeKind)kind
                ofEntity:(NSString *)entityId
                  reason:(NSString **)reason;
/* For a value type, or an entity type's reference mode value type. */
- (BOOL)setDataType:(NSString *)typeName
             length:(NSInteger)length
              scale:(NSInteger)scale
                 of:(NSString *)objectTypeId
             reason:(NSString **)reason;
- (BOOL)setIndependent:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason;
- (BOOL)setPersonal:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason;
- (BOOL)setExternal:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason;
/* Turns an entity type into a value type, or back; refused while what it
 * plays or what identifies it would not fit. */
- (BOOL)setValueType:(BOOL)value of:(NSString *)objectTypeId reason:(NSString **)reason;
/* "{'M', 'F'}", "{1..10, 20}", "[0..100)": a value constraint on a value
 * type, an entity type's reference mode, or a role. Empty removes it. */
- (BOOL)setValueConstraint:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason;
/* Free text on an object type or fact type: NORMA's Definition and Note. */
- (BOOL)setDefinition:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason;
- (BOOL)setNote:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason;

@end

@interface ORMEditor (ORMFacts)

/* A fact type over the players, in order, read as the reading says
 * ("{0} was born in {1}"); one player makes a unary fact type. Its id. */
- (NSString *)addFactTypeWithPlayers:(NSArray<NSString *> *)objectTypeIds
                             reading:(NSString *)reading
                           onDiagram:(NSString *)diagramId
                                  at:(NSPoint)point
                              reason:(NSString **)reason;
/* A reading for the roles in this order. Its id. */
- (NSString *)addReading:(NSString *)text
                forRoles:(NSArray<NSString *> *)roleIds
                  reason:(NSString **)reason;
- (BOOL)setReadingText:(NSString *)text of:(NSString *)readingId reason:(NSString **)reason;
/* Another player for the role. */
- (BOOL)setPlayer:(NSString *)objectTypeId ofRole:(NSString *)roleId reason:(NSString **)reason;
/* Derived fact types keep their rule as NORMA's DerivationRule; ORMKit
 * edits only its free-text description. */
- (BOOL)setDerivationNote:(NSString *)text of:(NSString *)factTypeId reason:(NSString **)reason;

@end

@interface ORMEditor (ORMConstraints)

/* Internal when every role is in one fact type, external otherwise. An
 * internal one over a binary's single role makes its multiplicity "one".
 * Its id. */
- (NSString *)addUniquenessConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason;
/* A simple mandatory constraint on one role, or a disjunctive
 * (inclusive-or) one over several. Its id. */
- (NSString *)addMandatoryConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason;
/* The role mandatory or not: adds or removes its simple mandatory
 * constraint. */
- (BOOL)setMandatory:(BOOL)mandatory role:(NSString *)roleId reason:(NSString **)reason;
/* The single role unique or not: adds or removes the internal uniqueness
 * constraint over exactly it. */
- (BOOL)setUnique:(BOOL)unique role:(NSString *)roleId reason:(NSString **)reason;
/* max 0: no maximum. Its id. */
- (NSString *)addFrequencyConstraintOverRoles:(NSArray<NSString *> *)roleIds
                                          min:(NSUInteger)min
                                          max:(NSUInteger)max
                                       reason:(NSString **)reason;
- (NSString *)addRingConstraint:(ORMRingType)type
                       overRoles:(NSArray<NSString *> *)roleIds
                          reason:(NSString **)reason;
/* Subset (the first sequence's population is a subset of the second's),
 * equality and exclusion, over sequences of equal length. Its id. */
- (NSString *)addSetComparisonConstraint:(ORMConstraintKind)kind
                               sequences:(NSArray<NSArray<NSString *> *> *)roleIds
                                  reason:(NSString **)reason;
/* Exclusion and disjunctive mandatory over the same roles, linked. The
 * exclusion's id. */
- (NSString *)addExclusiveOrConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason;
- (NSString *)addValueComparisonConstraint:(NSString *)comparisonOperator
                                 overRoles:(NSArray<NSString *> *)roleIds
                                    reason:(NSString **)reason;
- (BOOL)setFrequencyMin:(NSUInteger)min max:(NSUInteger)max of:(NSString *)constraintId reason:(NSString **)reason;
- (BOOL)setRingType:(ORMRingType)type of:(NSString *)constraintId reason:(NSString **)reason;
- (BOOL)setModality:(ORMModality)modality of:(NSString *)constraintId reason:(NSString **)reason;
/* Makes the uniqueness constraint the preferred identifier of the entity
 * type its roles identify. */
- (BOOL)setPreferredIdentifier:(NSString *)constraintId reason:(NSString **)reason;

@end

@interface ORMEditor (ORMStructure)

/* The subtype fact type. Its id. */
- (NSString *)addSubtype:(NSString *)subtypeId of:(NSString *)supertypeId reason:(NSString **)reason;
/* An objectified type nesting the fact type, and the link fact types
 * NORMA implies for it. Its id. */
- (NSString *)objectifyFactType:(NSString *)factTypeId named:(NSString *)name reason:(NSString **)reason;
- (BOOL)unobjectifyFactType:(NSString *)factTypeId reason:(NSString **)reason;

- (NSString *)addNote:(NSString *)text
            attachedTo:(NSArray<NSString *> *)elementIds
             onDiagram:(NSString *)diagramId
                    at:(NSPoint)point
                reason:(NSString **)reason;
- (BOOL)setNoteText:(NSString *)text of:(NSString *)noteId reason:(NSString **)reason;

/* Deletes model elements and what cannot stand without them: an object
 * type takes the fact types it plays in, a fact type its readings and
 * the constraint arguments over its roles; a constraint left with too few
 * roles goes too. Shapes of what is deleted leave every diagram. Shapes
 * named here leave their diagram only. */
- (void)deleteElements:(NSArray<NSString *> *)elementIds;

@end

@interface ORMEditor (ORMDiagramEditing)

- (NSString *)addDiagramNamed:(NSString *)name;
/* A shape for the element at the point (its top left). Readings and
 * value constraints come with fact types and object types. Its id; the
 * existing shape's when the diagram already shows the element. */
- (NSString *)placeElement:(NSString *)elementId onDiagram:(NSString *)diagramId at:(NSPoint)point;
- (void)moveShapes:(NSArray<NSString *> *)shapeIds by:(NSSize)delta;
- (void)setBounds:(NSRect)bounds ofShape:(NSString *)shapeId;
/* A fact type shape's role boxes in a new order. */
- (BOOL)setRoleDisplayOrder:(NSArray<NSString *> *)roleIds ofShape:(NSString *)shapeId reason:(NSString **)reason;
- (void)setOrientation:(ORMFactTypeOrientation)orientation ofShape:(NSString *)shapeId;
/* Lays the diagram out from scratch: what it shows, placed by its links. */
- (void)arrangeDiagram:(NSString *)diagramId;

@end
