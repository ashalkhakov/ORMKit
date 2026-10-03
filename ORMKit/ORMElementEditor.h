/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* What any element has: a name, a definition and a note, model notes
 * attached to it, and deletion with what cannot stand without it. Usually
 * reached as an editor's elementEditor. */
@interface ORMElementEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, weak) ORMEditor *editor;

/* Names an object type, fact type, constraint, diagram or role. Object
 * type names are unique in a model; a reference mode's value type is
 * renamed along with its entity type. */
- (BOOL)rename:(NSString *)elementId to:(NSString *)name reason:(NSString **)reason;
/* Free text on an object type or fact type: NORMA's Definition and Note. */
- (BOOL)setDefinition:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason;
- (BOOL)setNote:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason;
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
