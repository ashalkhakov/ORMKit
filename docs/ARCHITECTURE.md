# Architecture

ORMKit is an Object-Role Modeling (ORM2) toolkit for macOS and GNUstep: a
library with no AppKit that reads, edits, verbalizes and maps NORMA's `.orm`
files, a command line tool over it, and ORMDesigner, a document-based diagram
editor. It follows the shape of WorkflowKit (the XML document is the model)
and RDLKit (library, designer, tests, CI, AppImage).

```
ORMRuntime/        what apps run: plans and their driver; no ORM model, no NSXML (RUNTIME.md)
ORMKit/            the library: Foundation, NSXML, Core Data and ODataKit; no AppKit; links ORMRuntime
ORMKitTests/       its XCTest suite, with real NORMA files in Fixtures/
Tools/ormtool/     check, verbalize, normalize, draw as SVG, and map to and from Core Data from a shell
ORMDesigner/       the editor (AppKit): its windows and menu bar XIBs, springs and struts
ORMDesignerTests/  the editor driven through its window, headless
docs/              this, and the documents below
.github/ .tools/ Scripts/   CI, the GNUstep docker image, AppImage packaging
Prototype/         the first single-window sketch (NU*), kept for reference
```

The other documents:
- [COREDATA-MAPPING.md](COREDATA-MAPPING.md): the mapping to Core Data, both ways;
- [ODATA.md](ODATA.md): the model served with ODataKit, and queries as requests to it;
- [QUERIES.md](QUERIES.md): conceptual queries, their plans, and the two backends;
- [CURSORS.md](CURSORS.md): how a plan is read, as a tree of cursors;
- [RULES.md](RULES.md): queries as constraints and calculations;
- [RUNTIME.md](RUNTIME.md): what apps run: the model's plans as tables, and a small driver;
- [POPULATIONS.md](POPULATIONS.md): sample populations, made up and edited;
- [WINDOW.md](WINDOW.md): the designer's document window;
- [VERBALIZATION.md](VERBALIZATION.md): the FORML templates.

## The model, and NORMA's XML

The model is objects: `ORMModel` and its object types, fact types, roles,
readings, constraints, value constraints, data types, notes, diagrams and
shapes, edited through `ORMEditor`. The `.orm` XML is how NORMA keeps it:
read once into the objects, and written from them on saving, into the
document read, so that what NORMA keeps beside the model (its relational
bridges, name generators, join paths, extension data) goes back with it,
and an unchanged file is written back byte for byte (`ORMXML` writes
NORMA's layout: BOM, CRLF, tabs, `" />"`). [MODEL.md](MODEL.md) has the
design, and the steps that bring ORMKit there.

`ORMEditor` is the editing session over one document: every change goes
through it, as one undoable step (undo puts back the elements of the
document it touched, and reads the model again). The changes themselves
are made by objects with one responsibility each:

- the parts of every session, reached through it: `objectTypeEditor`,
  `factTypeEditor`, `constraintEditor`, `diagramEditor` and `elementEditor`
  (names, definitions, notes, deletion);
- what a feature adds, made with a session and unknown to it:
  `ORMQueryEditor`, `ORMMappingEditor`, `ORMCoreDataImporter`,
  `ORMSentenceEditor` (the Fact Editor), `ORMJoinPathBuilder`.

Operations take ids and refuse with a reason in words (`NSString **reason`)
rather than an `NSError`, for the status line. Each changes the model's
objects; the model is derived again, and `ORMNormaWriter` writes what
changed into the document, with what NORMA keeps denormalized beside it:

- each object type's `PlayedRoles` and each fact type's `InternalConstraints`;
- the derived attributes `_IsMandatory`, `_Multiplicity`, `_Name`, `_ReferenceMode`;
- each reading's `ExpandedData`, hyphen binding included;
- the implied disjunctive mandatory constraint NORMA gives each object type
  that is not independent and plays no mandatory role outside its own
  identification;
- preferred identifiers' back references, shapes whose subject is gone.

The rules were taken from what NORMA itself saved, and are checked against
it: every NORMA fixture written again from the model is the same bytes
(`ORMWriterTests`), and the model's mandatory, multiplicity, name and
reference mode agree with NORMA's own on every role and fact type. In
tests, `ORMNormalizer` works the same data out from the XML after every
change, as a check that the writer left it nothing to do.

### When the model changed

On saving a changed model, ORMKit drops what NORMA generates from it (the
abstraction and relational bridges, the model error list), since they would
describe a model that is gone; NORMA rebuilds them when it opens the file.

## The library

| | |
| --- | --- |
| `ORMXML` | namespaces, element helpers, ids (`_` + GUID), inches to points, NORMA's serialization |
| `ORMModel`, `ORMDiagram` | the model: every element, read once from the XML |
| `ORMNormaWriter` | the model written into the document as NORMA writes it |
| `ORMDiagramPainter` | ORM2 notation and its geometry, drawn onto any `ORMDrawingSurface`: the editor's AppKit view, `ORMSVGSurface` |
| `ORMEditor` | the editing session: every change as an undoable step, saving |
| `ORMObjectTypeEditor`, `ORMFactTypeEditor`, `ORMConstraintEditor`, `ORMDiagramEditor`, `ORMElementEditor` | the session's parts: each kind of element edited |
| `ORMNormalizer` | in tests, NORMA's denormalized data worked out from the XML: the writer's check |
| `ORMReadingText` | readings taken apart: placeholders, front text, hyphen-bound text |
| `ORMValueConstraintParser` | `{'M', 'F'}`, `[0..100)`, `{18..}` |
| `ORMFactSentence` | NORMA's Fact Editor: `Person(.id) was born in Country(.code)` |
| `ORMConstraintSentence` | constraints as the verbalizer says them, read back: `Each Person was born in exactly one Country.` |
| `ORMSentenceEditor` | what the Fact Editor takes: either kind of sentence, made into the model |
| `ORMJoinPathBuilder` | join paths written as NORMA keeps them, from logic: the fact types walked and the variables playing their roles |
| `ORMPath` | NORMA's role paths (join paths, derivation rules), calculations, sample populations, cardinality |
| `ORMLogic` | sequences, join paths and derivations as logic: variables, fact atoms, and/or/xor/not |
| `ORMVerbalizer` (+ `Logic`) | FORML in Halpin's wording as styled spans, each a statement, possibility, negation or example of something ([VERBALIZATION.md](VERBALIZATION.md)); plain text and HTML |
| `ORMCDModel` | a Core Data model's `contents`, read and written as Xcode does |
| `ORMCoreDataMapping`, `ORMCoreDataMapper`, `ORMCoreDataSync`, `ORMMappingEditor` | the mapping, both ways ([COREDATA-MAPPING.md](COREDATA-MAPPING.md)) |
| `ORMCoreDataImporter` | a Core Data model brought into ORM, with a mapping back to it |
| `ORMQuery`, `ORMQueryEditor` | conceptual queries after ConQuer, as logic ([QUERIES.md](QUERIES.md)) |
| `ORMQueryPlanner` | a query planned against a mapping |
| `ORMQueryPlan` (ORMRuntime) | a plan: public, a property list |
| `ORMQueryInterpreter`, `ORMQueryOData` (ORMRuntime) | a plan's two backends: run against a Core Data store, or sent to ODataKit's service |
| `ORMTables`, `ORMSaveHook`, `ORMValidator`, `ORMJoinedObject` (ORMRuntime) | what an app runs: the model's tables, and their driver ([RUNTIME.md](RUNTIME.md)) |
| `ORMPopulationEditor`, `ORMPopulationChecker`, `ORMPopulationGenerator`, `ORMPopulationStore` | sample populations: written as NORMA keeps them, checked, made up, and put in a Core Data store for queries ([POPULATIONS.md](POPULATIONS.md)) |
| `ORMCursor` (ORMRuntime) | the cursors a plan is read through, page by page, and keyset paging ([CURSORS.md](CURSORS.md)) |
| `ORMRuleChecker` | queries that are rules: constraints and calculations, checked on a population ([RULES.md](RULES.md)) |
| `ORMIssueFinder` | what is wrong with a model, as the designer's Issues navigator lists it |
| `ORMODataAnnotator` | the mapping's annotations for ODataKit: keys, descriptions, validation terms ([ODATA.md](ODATA.md)) |
| `ORMCoreDataValidation` | the constraints Core Data cannot enforce, as an Objective-C category on each entity's class |

ORMKit has no AppKit. The mapping writes Core Data's source format, as
Xcode does, so it works the same on both platforms, and `momc` (Apple's on a
Mac, FreeCoreData's on GNUstep) is the judge of what it writes. Core Data
itself is linked for what runs: queries against a store, and sample
populations put in one (FreeCoreData on GNUstep). ODataKit is linked for
queries sent to a service.

`ORMLogic` follows the meaning Franconi and Halpin give ORM in *ORM Abstract
Syntax and Semantics* (normative specification and glossary,
<https://gitlab.com/orm-syntax-and-semantics/orm-syntax-and-semantics-docs>):
a join path is their path expression `P.i ➤ [P.j ⋈ PATH]`, an external
uniqueness constraint a uniqueness over its fact types joined on their
common player. Where ORMKit's formulas and the specification's could
disagree, the specification is right.

## The editor

`ORMDocument` (NSDocument) holds an editor on its undo manager.
`ORMWindowController` runs the document window (`ORMDocumentWindow.xib`,
[WINDOW.md](WINDOW.md)): a navigator on the left (the model browser,
`ORMInsertPalette`, `ORMSearchNavigator`, `ORMIssuesView`, each an
`ORMPane` with its own XIB), alignment across the top, the diagram, tabs
under it (the verbalization, NORMA's Fact Editor, `ORMPopulationView`), and
the inspector. `ORMQueryController` is the Queries window. `ORMCanvasView` draws through
`ORMRenderer` (plain functions of the model, in diagram points) and
turns gestures into editor operations, one per gesture. `ORMInspectorView`
is built from rows that know where their value lives and which operation
sets it. `ORMCoreDataController` is the mappings window.

GNUstep differences are kept to names (`ORMDesignerCompat.h`, force-included
on GNUstep only) and a few `#if defined(__APPLE__)` guards, each with its
reason in place.

## Status

Working and tested on both platforms:

- reading and writing NORMA files, byte for byte when unchanged;
- the model of every construct NORMA files hold (subtypes,
  objectification, unaries, all constraint kinds, value constraints, data
  types, notes, diagrams and shapes);
- editing: object types, reference modes, data types, value constraints,
  fact types and readings, every constraint kind, subtyping,
  objectification, notes, diagrams, deletion with its cascade, undo;
- verbalization of object types, fact types and every constraint kind;
- the Core Data mapping and three-way synchronization, and import from
  Core Data;
- the mapping annotated for ODataKit to serve: entity sets, keys
  (surrogates where needed), descriptions, validation terms;
- conceptual queries after ConQuer ([QUERIES.md](QUERIES.md)): planned
  against the mapping, run against a Core Data store a page at a time, or
  sent to the OData service ([ODATA.md](ODATA.md)); read back from their
  outlines;
- queries as rules: constraints and calculations, checked on a population
  ([RULES.md](RULES.md));
- derived fact types ([DERIVATION.md](DERIVATION.md)): queries as their
  rules, NORMA's role-path rules read as queries, queries through them,
  and stored ones kept up to date at save;
- entity types kept in several entities ([JOINED-ENTITIES.md](JOINED-ENTITIES.md)):
  the mapping's members, queries that join them, the sample population
  stored in them, a façade class, and Merge Entity Types for imported
  tables;
- sample populations ([POPULATIONS.md](POPULATIONS.md)): edited, checked
  against the constraints, made up, and put in a store for queries;
- what apps run ([RUNTIME.md](RUNTIME.md)): ORMRuntime, a small library with
  no ORM model, reading the model's tables (`<Name>.ormplans`) of rules,
  stored derivations, joined types and queries; the generated code is
  declarations and calls into it;
- ORMDesigner: opening NORMA's diagrams, selecting, moving, the tools, the
  fact editor, the inspector, verbalization, PDF/PNG/HTML export, the Core
  Data window, the query builder, the Population tab, the Issues
  navigator, and updating itself (Sparkle, on macOS);
- building, testing, installing and releasing as gnustep-release-actions'
  repositories do: `make`, `make check`, `make install` on GNUstep,
  `Makefile.apple` on the Mac, the AppImage.

Not done yet:

- **Diagram editing**: copy and paste; dragging constraint connectors;
  role name, value constraint and frequency shapes placed for new elements;
  a layered layout (WorkflowKit's `WKDLayout` is the one to port) instead
  of the grid-and-spiral `arrangeDiagram:`; printing across pages.
- **NORMA features kept but not edited**: NORMA's derivation role paths
  (read and run as queries, not written back as paths), constraint join
  paths, most of NORMA's model error checks (the Issues navigator has the
  basic ones, and readings that do not read). Unary facts kept on their
  player are read, not written ([POPULATIONS.md](POPULATIONS.md#not-done-yet)).
- **Queries, rules, derivations**: each document's "not done" list. In
  short: a join within a join over OData, rules enforced by the OData
  service at the end of a change set, recursive and subtype derivations,
  typed rows for a query's results.
- **Verbalization**: wording checked against NORMA's report only by eye.
- **Core Data**: per-relationship deletion rule overrides; watching the
  `.xcdatamodeld` for changes; a live `NSManagedObjectModel` preview with
  FreeCoreData; rules for what needs a fetch (uniqueness across objects,
  frequencies over several roles) and for set comparisons through join
  paths; class names that clash with the SDK's (`Comment` and
  `Component` are Carbon types, so a class of that name does not compile).

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
