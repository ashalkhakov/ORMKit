/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDiagram.h"

@class ORMObjectTypeEditor, ORMFactTypeEditor, ORMConstraintEditor, ORMDiagramEditor, ORMElementEditor;

/* Every change to an ORM model goes through an editor: the editing
 * session over one document.
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

/* The document without ORMKit's own elements, for a NORMA that does not
 * know them: what "Save a Copy for NORMA" writes. */
- (NSXMLDocument *)documentForNorma;

/* A change made of several operations, undone as one. */
- (void)group:(NSString *)name with:(void (^)(void))operations;

/* The editing itself, each kind of element by an object of its own; each
 * makes its changes through this editor, as undoable steps of it. */
@property (nonatomic, readonly, strong) ORMObjectTypeEditor *objectTypeEditor;
@property (nonatomic, readonly, strong) ORMFactTypeEditor *factTypeEditor;
@property (nonatomic, readonly, strong) ORMConstraintEditor *constraintEditor;
@property (nonatomic, readonly, strong) ORMDiagramEditor *diagramEditor;
@property (nonatomic, readonly, strong) ORMElementEditor *elementEditor;

@end

/* Its parts, so that holding an editor is enough to edit with. */
#import "ORMObjectTypeEditor.h"
#import "ORMFactTypeEditor.h"
#import "ORMConstraintEditor.h"
#import "ORMDiagramEditor.h"
#import "ORMElementEditor.h"
