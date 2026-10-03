/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"
#import "ORMObjectTypeEditor.h"
#import "ORMFactTypeEditor.h"
#import "ORMConstraintEditor.h"
#import "ORMDiagramEditor.h"
#import "ORMElementEditor.h"
#import "ORMModelPriv.h"
#import "ORMXML.h"

#define CORE ORMCoreNamespace
#define DIAGRAM ORMDiagramNamespace

/* What the editors share: the session's own document, worked on by every
 * editor of its parts. */
@interface ORMEditor ()

/* One undoable step: the document as it was is what undo restores. Inside
 * a group, or another change, it joins the step being made, and the
 * projection is rebuilt after it so the next operation sees its result. */
- (void)change:(NSString *)name with:(void (^)(void))change;

/* The element with the id, made since the projection was built or not. */
- (NSXMLElement *)xml:(NSString *)elementId;
/* A section of the orm:ORMModel element (Objects, Facts, Constraints,
 * DataTypes, ...), made when missing. */
- (NSXMLElement *)section:(NSString *)local;
/* "InternalUniquenessConstraint7": the prefix and the next number no
 * constraint of the model has. */
- (NSString *)nextName:(NSString *)prefix;
/* An object type name no object type has: the name, or the name and a
 * number. */
- (NSString *)uniqueObjectTypeName:(NSString *)name;
/* The data type element of the model for the type name, made when the
 * model has none. Its id. */
- (NSString *)dataTypeIdNamed:(NSString *)typeName;

/* The ids' roles, refused with why when one is not a role. */
- (NSArray<ORMRole *> *)rolesWithIds:(NSArray<NSString *> *)roleIds reason:(NSString **)reason;
/* <orm:RoleSequence> holding <orm:Role id ref/> for the roles. */
- (NSXMLElement *)newRoleSequence:(NSArray<NSString *> *)roleIds withId:(BOOL)withId;
/* A new constraint element of the kind named, in Constraints. */
- (NSXMLElement *)newConstraint:(NSString *)local named:(NSString *)prefix;

/* Whether readings get NORMA's <orm:ExpandedData>: as the file had it
 * when opened (older NORMA did not write it). */
@property (nonatomic, readonly) BOOL writesExpandedData;
/* Whether implied mandatory constraints are kept up: as the file had them
 * (older NORMA did not write them). */
@property (nonatomic, readonly) BOOL writesImpliedMandatories;

@end

/* NORMA's denormalized data (each object type's PlayedRoles, each fact
 * type's InternalConstraints, _IsMandatory, _Multiplicity, _Name,
 * _ReferenceMode, readings' ExpandedData, implied mandatories), kept up
 * from the model after each change, as the version of NORMA that wrote the
 * file keeps it. */
@interface ORMNormalizer : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly) BOOL writesExpandedData;
@property (nonatomic, readonly) BOOL writesImpliedMandatories;
/* The unary readings as a change starts: an implicit boolean value type is
 * renamed only when its reading was changed. */
- (void)rememberUnaryReadings;
- (void)normalize;
@end

@interface ORMDiagramEditor ()
- (NSXMLElement *)newShape:(NSString *)local subject:(NSString *)subjectId bounds:(NSRect)bounds;
- (NSXMLElement *)shapesOf:(NSXMLElement *)diagram;
/* Where a new shape for the element goes when no point is given: beside
 * the shapes it links to. */
- (NSPoint)placeFor:(NSString *)elementId onDiagram:(NSString *)diagramId;
/* Places what a new fact type needs on the diagram: the fact type, and
 * its players when not shown. */
- (void)showFactType:(NSString *)factTypeId onDiagram:(NSString *)diagramId at:(NSPoint)point;
/* Removes every shape of the elements, on every diagram. */
- (void)removeShapesOfSubjects:(NSSet<NSString *> *)subjectIds;
@end

/* Builders the editors share; each only makes XML, inside a change. */
@interface ORMObjectTypeEditor ()
- (NSXMLElement *)newValueTypeNamed:(NSString *)name dataType:(NSString *)typeName;
/* The reference mode value type's name for the entity type: "Person_id". */
- (NSString *)valueTypeNameFor:(NSString *)entity mode:(NSString *)mode kind:(ORMReferenceModeKind)kind;
/* Refuses a name another object type (but the one named) has, or none. */
- (BOOL)checkName:(NSString *)name except:(NSString *)elementId reason:(NSString **)reason;
@end

@interface ORMFactTypeEditor ()
/* A new <orm:Fact> over the players with one reading for its first roles;
 * the new roles' ids are added to roleIds. */
- (NSXMLElement *)newFactWithPlayers:(NSArray<NSString *> *)playerIds
                             reading:(NSString *)reading
                               roles:(NSMutableArray *)roleIds;
- (NSXMLElement *)appendReading:(NSString *)text to:(NSXMLElement *)fact roles:(NSArray<NSString *> *)roleIds;
@end

@interface ORMConstraintEditor ()
- (NSXMLElement *)newInternalUniqueness:(NSArray<NSString *> *)roleIds;
- (NSXMLElement *)newSimpleMandatory:(NSString *)roleId;
@end

