# Architecture

ORMKit is an Object-Role Modeling (ORM2) toolkit for macOS and GNUstep: a
Foundation-only library that reads, edits, verbalizes and maps NORMA's `.orm`
files, a command line tool over it, and ORMDesigner, a document-based diagram
editor. It follows the shape of WorkflowKit (the XML document is the model)
and RDLKit (library, designer, tests, CI, AppImage).

```
ORMKit/            the library: Foundation and NSXML only
ORMKitTests/       its XCTest suite, with real NORMA files in Fixtures/
Tools/ormtool/     check, verbalize, normalize, draw as SVG, and map to and from Core Data from a shell
ORMDesigner/       the editor (AppKit): its windows and menu bar XIBs, springs and struts
ORMDesignerTests/  the editor driven through its window, headless
docs/              this, and COREDATA-MAPPING.md
.github/ .tools/ Scripts/   CI, the GNUstep docker image, AppImage packaging
Prototype/         the first single-window sketch (NU*), kept for reference
```

## The XML document is the model

A `.orm` file is parsed into an `NSXMLDocument` and stays one. Nothing
regenerates it: an edit changes the nodes it touches and leaves the rest,
which is how a model goes back to NORMA with everything NORMA keeps beside it
(its relational bridges, name generators, join paths, extension data) and
how an unchanged file is written back byte for byte (`ORMXML` writes NORMA's
layout: BOM, CRLF, tabs, `" />"`).

`ORMModel` is a read-only projection of the document into objects (object
types, fact types, roles, readings, constraints, value constraints, data
types, notes, diagrams and shapes), rebuilt after every change. Its objects
hold the element they were read from; their links to one another are weak
and the model holds them all.

`ORMEditor` is the editing session over one document: every change goes
through it, as one undoable step (undo restores a snapshot of the document).
The changes themselves are made by objects with one responsibility each:

- the parts of every session, reached through it: `objectTypeEditor`,
  `factTypeEditor`, `constraintEditor`, `diagramEditor` and `elementEditor`
  (names, definitions, notes, deletion);
- what a feature adds, made with a session and unknown to it:
  `ORMQueryEditor`, `ORMMappingEditor`, `ORMCoreDataImporter`,
  `ORMSentenceEditor` (the Fact Editor), `ORMJoinPathBuilder`.

Operations take ids and refuse with a reason in words (`NSString **reason`)
rather than an `NSError`, for the status line. After each change the
session's `ORMNormalizer` keeps up what NORMA keeps denormalized:

- each object type's `PlayedRoles` and each fact type's `InternalConstraints`;
- the derived attributes `_IsMandatory`, `_Multiplicity`, `_Name`, `_ReferenceMode`;
- each reading's `ExpandedData`, hyphen binding included;
- the implied disjunctive mandatory constraint NORMA gives each object type
  that is not independent and plays no mandatory role outside its own
  identification;
- preferred identifiers' back references, shapes whose subject is gone.

The rules were taken from what NORMA itself saved, and are checked against
it: normalizing a NORMA file changes nothing (`ORMEditorTests`,
`ormtool normalize` in CI), and the projection's mandatory, multiplicity,
name and reference mode agree with NORMA's own on every role and fact type.

### When the model changed

On saving a changed model, ORMKit drops what NORMA generates from it (the
abstraction and relational bridges, the model error list), since they would
describe a model that is gone; NORMA rebuilds them when it opens the file.

## The library

| | |
| --- | --- |
| `ORMXML` | namespaces, element helpers, ids (`_` + GUID), inches to points, NORMA's serialization |
| `ORMModel`, `ORMDiagram` | the projection |
| `ORMDiagramPainter` | ORM2 notation and its geometry, drawn onto any `ORMDrawingSurface`: the editor's AppKit view, `ORMSVGSurface` |
| `ORMEditor` | the editing session: every change as an undoable step, saving |
| `ORMObjectTypeEditor`, `ORMFactTypeEditor`, `ORMConstraintEditor`, `ORMDiagramEditor`, `ORMElementEditor` | the session's parts: each kind of element edited |
| `ORMNormalizer` | NORMA's denormalized data, kept up after each change |
| `ORMReadingText` | readings taken apart: placeholders, front text, hyphen-bound text |
| `ORMValueConstraintParser` | `{'M', 'F'}`, `[0..100)`, `{18..}` |
| `ORMFactSentence` | NORMA's Fact Editor: `Person(.id) was born in Country(.code)` |
| `ORMConstraintSentence` | constraints as the verbalizer says them, read back: `Each Person was born in exactly one Country.` |
| `ORMSentenceEditor` | what the Fact Editor takes: either kind of sentence, made into the model |
| `ORMJoinPathBuilder` | join paths written as NORMA keeps them, from logic: the fact types walked and the variables playing their roles |
| `ORMPath` | NORMA's role paths (join paths, derivation rules), calculations, sample populations, cardinality |
| `ORMLogic` | sequences, join paths and derivations as logic: variables, fact atoms, and/or/xor/not |
| `ORMVerbalizer` (+ `Logic`) | FORML in Halpin's wording as styled spans, each a statement, possibility, negation or example of something (VERBALIZATION.md); plain text and HTML |
| `ORMCDModel` | a Core Data model's `contents`, read and written as Xcode does |
| `ORMCoreDataMapping`, `ORMCoreDataMapper`, `ORMCoreDataSync`, `ORMMappingEditor` | the mapping, both ways (COREDATA-MAPPING.md) |
| `ORMCoreDataImporter` | a Core Data model brought into ORM, with a mapping back to it |
| `ORMQuery`, `ORMQueryEditor` | conceptual queries after ConQuer, as logic (QUERIES.md) |
| `ORMQueryPlanner`, `ORMQueryPlan` | a query planned against a mapping: public, a property list |
| `ORMQueryInterpreter`, `ORMQueryOData` | a plan's two backends: run against a Core Data store, or sent to ODataKit's service |
| `ORMCoreDataValidation` | the constraints Core Data cannot enforce, as an Objective-C category on each entity's class |

ORMKit has no AppKit and no Core Data: the Core Data side is Xcode's source
format, so mapping works the same on both platforms, and Apple's `momc` (in
the tests, on a Mac) is the judge of what it writes.

`ORMLogic` follows the meaning Franconi and Halpin give ORM in *ORM Abstract
Syntax and Semantics* (normative specification and glossary,
<https://gitlab.com/orm-syntax-and-semantics/orm-syntax-and-semantics-docs>):
a join path is their path expression `P.i ➤ [P.j ⋈ PATH]`, an external
uniqueness constraint a uniqueness over its fact types joined on their
common player. Where ORMKit's formulas and the specification's could
disagree, the specification is right.

## The editor

`ORMDocument` (NSDocument) holds an editor on its undo manager.
`ORMWindowController` lays out the window in code: the model browser, the
diagram with NORMA's Fact Editor and the verbalization of the selection
below it, the inspector, tools across the top. `ORMCanvasView` draws through
`ORMRenderer` (plain functions of the projection, in diagram points) and
turns gestures into editor operations, one per gesture. `ORMInspectorView`
is built from rows that know where their value lives and which operation
sets it. `ORMCoreDataController` is the mappings window.

GNUstep differences are kept to names (`ORMDesignerCompat.h`, force-included
on GNUstep only) and a few `#if defined(__APPLE__)` guards, each with its
reason in place.

## Status

Working and tested on both platforms:

- reading and writing NORMA files, byte for byte when unchanged;
- the projection of every construct NORMA files hold (subtypes,
  objectification, unaries, all constraint kinds, value constraints, data
  types, notes, diagrams and shapes);
- editing: object types, reference modes, data types, value constraints,
  fact types and readings, every constraint kind, subtyping,
  objectification, notes, diagrams, deletion with its cascade, undo;
- verbalization of object types, fact types and every constraint kind;
- the Core Data mapping and three-way synchronization, import from Core
  Data, and validation code for what Core Data cannot enforce;
- the mapping annotated for ODataKit to serve: entity sets, keys
  (surrogates where needed), descriptions, validation terms; conceptual
  queries as requests to that service (ODATA.md);
- ORMDesigner: opening NORMA's diagrams, selecting, moving, the tools, the
  fact editor, the inspector, verbalization, PDF/PNG/HTML export, the Core
  Data window, the query builder.

Not done yet:

- **Diagram editing**: copy and paste; dragging constraint connectors;
  role name, value constraint and frequency shapes placed for new elements;
  a layered layout (WorkflowKit's `WKDLayout` is the one to port) instead
  of the grid-and-spiral `arrangeDiagram:`; printing across pages.
- **NORMA features kept but not edited**: derivation rules (only their
  free-text note), constraint join paths, sample populations, NORMA's model
  error checks.
- **Verbalization**: wording checked against NORMA's report only by eye.
- **Core Data**: per-relationship deletion rule overrides; watching the
  `.xcdatamodeld` for changes; validating with FreeCoreData's `momc` in the
  GNUstep job, and a live `NSManagedObjectModel` preview with FreeCoreData;
  validation code for what needs a fetch (uniqueness across objects,
  frequencies over several roles) and for set comparisons through join
  paths; class names that clash with the SDK's (`Comment` and `Component`
  are Carbon types, so a class of that name does not compile).

### Assumptions to check against NORMA

These follow NORMA's schema and its files as far as they could be read, but
were not opened in NORMA itself:

1. NORMA rebuilds the relational bridges and model errors ORMKit drops from
   a changed model.
2. NORMA tolerates the `ormcd:CoreDataMappings` element at the root; if it
   does not, **Save a Copy for NORMA** writes the file without it.

Settled by NORMA's own files: the 29 ActiveFacts examples (NORMA builds of
2008 to 2015) and StockMate (a recent one) all round-trip byte for byte and
normalize to themselves. They show the link fact types of an
objectification (`ImpliedFact`, `RoleProxy`), custom reference mode kinds
(`orm:Kind`), `PostBoundText` and `FrontText`, and what changed between
NORMA versions, which ORMKit keeps as each file has it:

- reference mode value types named by the model's `ReferenceModeKind`
  format strings (`{0}_{1}` now, `{0} {1}` before: "Person Name");
- `ExpandedData` on readings only in files that have it;
- subtype fact roles as `SubtypeMetaRole`/`SupertypeMetaRole`, named so in
  `PlayedRoles` too, and subtype facts named "XIsASubtypeOfY";
- fact type names written four ways: player names without punctuation
  (now), each word capitalized ("PersonHasPersonId"), as they are
  ("JoinTypeHasJoinType_name"), or with the reading's words lowercased
  after their first letter ("ObjectTypeIsValuetype");
- implied mandatory constraints only in files that have them;
- implicit boolean value types renamed only when their reading changes
  ("Person isDead" stands);
- what comes before the root element (no XML declaration, a blank line)
  and after it, as the file has it.

NORMA's own samples, metamodels and test suites (`Fixtures/NORMA`) were
checked the same way; see the fixtures' README for what they hold.

Implied mandatory constraints and `_Multiplicity` follow NORMA's own rules
(`ObjectType.ValidateIsIndependent`, `Role.GetMultiplicityValue`, read in
NORMA's source as reference): roles opposite the preferred identifier
(through a link fact type's proxy) and of fully derived fact types say
nothing; any other alethic mandatory constraint, inclusive-or too, rules
the implied one out.

### GNUstep

Two GNUstep faults found here, worked around in place, both belonging in
`../gnustep-patches`:

- gnustep-gui: an `NSScrollView` that autohides its scrollers, around a
  document view that resizes with it, recurses without end in `-tile`.
  ORMDesigner does not autohide on GNUstep.
- gnustep-base: `-[NSXMLDocument copyWithZone:]` gives the copy a URI
  without its terminating NUL, so copying the copy reads past the buffer
  (AddressSanitizer, in `xmlCopyDoc`). `ORMCopyDocument` copies the root
  element into a new document on GNUstep instead.
- gnustep-base (milder): a root element made with a namespace and then given
  that namespace's declaration ends up pointing at a freed namespace; new
  documents are parsed from text rather than built node by node.
