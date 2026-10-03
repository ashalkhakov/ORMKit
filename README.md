# ORMKit

Object-Role Modeling (ORM2) on macOS and Linux, in Objective-C: models in
NORMA's `.orm` format, their diagrams, their verbalization in FORML, and their
mapping to Core Data, kept in step both ways.

- **ORMKit** — the library. Foundation and NSXML only, ARC, Cocoa and GNUstep.
- **ORMDesigner** — a document-based diagram editor for `.orm` files.
- **ormtool** — the library from a shell.

LGPL 2.1.

## NORMA's files, as NORMA writes them

ORMDesigner opens what NORMA saves and saves what NORMA opens. The XML
document is the model: an edit changes what it touches and nothing else, so
NORMA's own data (relational bridges, join paths, extension data) goes back
with the file, and an unchanged file is written back byte for byte. What NORMA
derives and stores beside the model (played roles, internal constraint lists,
`_IsMandatory`, `_Multiplicity`, reading expansions, implied mandatory
constraints) is kept up after each edit by NORMA's own rules, checked against
files NORMA wrote.

## Editing

- Object types: entity and value types, reference modes (`.id`, `kg:`),
  data types, value constraints, independence.
- Fact types of any arity, unaries included, typed as NORMA's Fact Editor
  takes them: `Person(.id) was born in Country(.code)`; readings in either
  direction, hyphen binding (`includes first- StreetLine`).
- Constraints: internal and external uniqueness, preferred identifiers,
  mandatory and inclusive-or, exclusion and exclusive-or, subset, equality,
  frequency, ring, value comparison; alethic or deontic.
- Subtyping, objectification, model notes, any number of diagrams.
- Every change undoable.

## Verbalization

The selection is read out as NORMA's verbalization browser reads it:

> Each Product is identified by exactly one SKU.
> For each SKU, at most one Product is identified by that SKU.
> For each StreetLine1, StreetLine2 and StreetLine3, at most one Street includes that first StreetLine1 and includes that second StreetLine2 and includes that third StreetLine3.
> No ItemCategory may cycle back to itself via one or more traversals through ItemCategory is child of ItemCategory.

The whole model exports as HTML.

## Core Data

A model maps to one or more Core Data models (`.xcdatamodeld`): entity types to
entities, functional fact types to attributes and to-one relationships,
many-to-many fact types to to-many relationships, unaries to Booleans, longer
and objectified fact types to entities of their own, subtyping to entity
inheritance, identifiers and composite identifiers to uniqueness
constraints; what Core Data cannot enforce is reported and kept with the
entity. Synchronizing is a three-way merge: what changed in the ORM model is
written out, and what changed in Xcode comes back as the ORM change that
would have made it. See [docs/COREDATA-MAPPING.md](docs/COREDATA-MAPPING.md).

## Building

macOS:

```sh
xcodebuild -project ORMKit.xcodeproj -scheme ORMDesigner build
xcodebuild -project ORMKit.xcodeproj -scheme ORMKitTests test
```

GNUstep (clang, libobjc2, gnustep-2.0 runtime, tools-xctest):

```sh
. /path/to/GNUstep.sh
make -C ORMKit && make -C Tools/ormtool && make -C ORMDesigner
make -C ORMKitTests run-tests
xvfb-run -a make -C ORMDesignerTests run-tests
```

or in docker: `.tools/gnustep.sh make -C ORMKitTests run-tests`.

## ormtool

```sh
ormtool check model.orm
ormtool verbalize [--html] model.orm
ormtool normalize model.orm out.orm
ormtool coredata model.orm Out.xcdatamodeld [mapping name]
```
