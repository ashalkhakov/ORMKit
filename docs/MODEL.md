# The model first: objects edited, XML for NORMA

Until now the `.orm` XML document was the model. Every change edited the
XML, and `ORMModel` was a read-only projection of it, rebuilt after each
change. Each top-level edit did three passes over the whole model:
- a copy of the whole document, kept for undo;
- the normalizer, which built a projection of its own to keep NORMA's
  denormalized data up;
- the rebuilt projection.

So every edit cost the size of the model, and a run of edits was
quadratic: an import from Core Data, the query tests' setUp, the Fact
Editor's sentences. The projection's objects also lost their identity on
each change, and their weak links went nil under callers that held one
across an edit.

Now the objects are the model. Editors change them, and undo restores them.
The XML is what NORMA reads and writes: it is read once when a file is
opened, and written when it is saved. ORMKit's own data (queries, Core Data
mappings) is saved in the same file, as now. Apps built from a model never
see either ([RUNTIME.md](RUNTIME.md)).

## What stays

- **An unchanged NORMA file is written back byte for byte.**
- **NORMA reads what ORMKit writes.** Everything NORMA keeps that ORMKit
  does not model (the relational and abstraction bridges, name generators,
  extension data, model errors) survives, as it does now.
- **Normalizing a NORMA file changes nothing.** This becomes: a NORMA file
  read and written again, every element written from the model, is the
  same bytes.
- **Every change goes through an editor**, as one undoable step that
  refuses with a reason in words.

## The parts

- **`ORMModel` and its elements**, made mutable inside ORMKit. Read-only
  properties outside ORMKit, as now; the editors set them through a
  private interface. The model holds its elements; links up and across
  are weak, as now, but the model lives as long as the document, so they
  stay valid. Each element keeps its identifier for ever. A derived value
  cached on an element (`familyNames`, `words`) is cleared when what it is
  made of changes.
- **The NORMA reader** (`ORMNormaReader`): the XML into a model, what
  `-[ORMModel readDocument:]` does now. Each element remembers the XML
  element it came from. The document is kept as the **carrier**: what
  ORMKit does not model is found there when writing.
- **The NORMA writer** (`ORMNormaWriter`): the model into the carrier. For
  each element changed, made or deleted since the last write, it updates,
  inserts or detaches its XML element. It then writes the denormalized
  data NORMA keeps beside the model, from the model rather than from a
  second projection: played roles, internal constraints, `_IsMandatory`,
  `_Multiplicity`, `_Name`, `_ReferenceMode`, expanded readings, implied
  mandatories. That is what `ORMNormalizer` does now, with what it reads
  turned around. An unchanged model writes nothing, so the file is the same
  bytes.
- **Change tracking.** An element set through the private interface is
  marked changed. The model keeps the elements made, changed and deleted
  since the last write, for the writer.
- **Undo.** Each editor operation records what it changed: an element's
  values before, an element made, an element deleted with where it was.
  Undo puts those back, and redo does them again. An operation touches a
  few elements, so neither the step nor its undo costs the size of the
  model. Groups (`group:with:`, `group:trying:`) collect their steps' records
  into one, and roll back by undoing them.
- **ORMKit's own data** (queries, Core Data mappings, sample populations,
  diagrams' shapes) is model too. Its objects are edited the same way and
  written to their namespaces by the writer. `ORMQuery`, which today reads
  and edits XML directly, gets a query model of its own.

## The checks

- **Byte for byte**: every NORMA fixture read and written unchanged gives
  the same bytes (as now).
- **Full rewrite**: every fixture read, every element marked changed, and
  written, gives the same bytes. This proves the writer says everything
  the model holds as NORMA does, not merely that it writes nothing.
- **Agreement**: during the migration, after every edit in every test, the
  model is compared with one read afresh from the written XML. They must
  agree element for element. This catches a change the writer does not
  carry, or one the editor makes to the XML and not to the model.
- **Undo**: in the editor tests, every operation undone gives a model, and
  its written XML, equal to before it.

## Steps

Each step keeps every test passing.

0. **The model's API made whole** (done). What other code worked out for
   the model is the model's own, made once where it is asked often:
   - fact types: `displayText`, `readingFromRole:`, `subtype`, `supertype`,
     `implicitRole`, `isBinary`, `linkFactTypes`, `isLinkFactType`;
   - readings: `parsedText`, `words`, `readsFromFirstRole`;
   - object types: `family`, `familyNames`, `isCompatibleWith:`,
     `identifiedType`, `valueType`, `referenceModeRole`;
   - roles: `proxies`;
   - every element: `definitionText`, `noteText`;
   - the model: `objectTypeNamed:` from a table.

   `isMandatory` and `isUnique` count deontic constraints, as NORMA's
   `_IsMandatory` does; the Core Data mapper maps by `isAlethicMandatory`
   and `isAlethicUnique`, a deontic rule being the app's to check.
1. **The writer, and the full-rewrite check** (done). `ORMNormaWriter`
   writes each kind of element from the model: object types, fact types,
   roles, readings, constraints, value ranges, notes, diagrams and shapes.
   Every NORMA fixture rewrites to the same bytes (`ORMWriterTests`).
   Nothing uses it yet. Values read as numbers (shape bounds, font sizes)
   are compared as read, so NORMA's digits stay. Gaps found on the way:
   a fact type's own `Name` is not told apart from NORMA's derived `_Name`;
   a sequence's role that does not resolve is not in the model, so the
   writer keeps it; role uses' ids are the XML's. Populations, derivation
   rules, queries and mappings come with their editors (step 3).
2. **A model that lasts** (done). The editor keeps one model. An operation
   not yet moved over still edits the XML, and the model is read again
   into the same objects (`-[ORMModel readDocumentAgain:]`): an element
   whose id is still there is the same object, each class resetting its
   values first (`-reset`). The agreement check runs in tests
   (`ORMEditor.checksAgreement`, `ORMModelDisagreement`), after every
   change, undo and redo; it also catches a reset that misses a value. It
   costs the macOS suite about a tenth more.
3. **The editors, one domain at a time**: object types, fact types and
   readings, constraints, element names and deletion, diagrams and shapes,
   populations, Core Data mappings, queries. Each operation changes the
   model and records its undo. Saving writes through the writer.

   NORMA's model is done. The model tells what is read from what is
   derived (`-[ORMModel derive]`: played roles, subtyping, internal
   constraints, roles' flags, reference modes, fact type names, preferred
   identifiers' owners). An operation runs in `-[ORMEditor
   modelChange:with:]`: it changes elements and says which (`-wrote:`,
   `-deleted:`); the model keeps NORMA's implied mandatories, unaries'
   implicit names and shapes of what is gone as the normalizer does, is
   derived, and the elements are written. Groups edit the XML only where
   a step does. Moved: object types, fact types and readings,
   objectification, constraints, names, definitions and notes, deletion,
   diagrams and shapes. A document built by all of them is the same
   bytes as the XML editors wrote; the agreement check runs on each.

   Core Data mappings are edited in the document still, but the model
   does not read them, so they leave it as it is
   (`-documentChange:with:`). Still edited in the XML, and read again
   after: sample populations, queries, derivation rules and join paths,
   all ORMKit's own data or ORMPath's, which need model classes first
   (role instances, for populations; a query model, for queries).

   The Core Data import round trip takes 6.6 s on macOS, from 16.3: it
   reads the model once.

   Undo still restores the document as it was, and the model is read
   again: the normalizer still edits the XML after each operation. Undo
   records replace that when the normalizer goes (step 4).
4. **The normalizer goes**, its rules now the writer's.
5. **The XML leaves the rest of ORMKit.** `ORMElement.element` becomes the
   writer's private business. Code that reads XML outside the reader and the
   writer moves to the model (the audit of such places is in the PR).
6. **Measure**: the Core Data import round trip, the query tests' setUp, the
   Fact Editor.

## Not here

- Concurrent editing, and saving while editing.
- An undo history kept across documents being closed and opened again.
