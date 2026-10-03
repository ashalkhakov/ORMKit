/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* Object types: entity and value types, their reference modes and data
 * types, value constraints, the flags NORMA keeps on them, and subtyping.
 * Usually reached as an editor's objectTypeEditor. */
@interface ORMObjectTypeEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, weak) ORMEditor *editor;

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
/* The subtype fact type. Its id. */
- (NSString *)addSubtype:(NSString *)subtypeId of:(NSString *)supertypeId reason:(NSString **)reason;

@end
