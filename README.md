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

ORMKit links [ODataKit](https://github.com/ashalkhakov/ODataKit) ([docs/ODATA.md](docs/ODATA.md)),
and on GNUstep [FreeCoreData](https://github.com/ashalkhakov/FreeCoreData) under it;
`.github/pins.env` names the exact releases it builds on, with the GNUstep
stack and Sparkle (ORMDesigner's updates on macOS).

macOS, with ODataKit's XCFrameworks and Sparkle's in `.deps/`
(gnustep-release-actions' `scripts/deps.sh apple` fetches them by those
versions):

```sh
make -f Makefile.apple && make -f Makefile.apple check
make -f Makefile.apple install DESTDIR=out
```

or open `ORMKit.xcworkspace` (`python3 .tools/genxcodeproj.py` writes it).

GNUstep (clang, libobjc2, gnustep-2.0 runtime, tools-xctest), with those
releases installed (`scripts/deps.sh linux` unpacks them into `/opt/gnustep`):

```sh
. /path/to/GNUstep.sh
make && make check && make install
```

or in docker, in an image that has them: `.tools/gnustep.sh make check`.

One workflow, `.github/workflows/build.yml`, runs the same on every push and
`v*` tag, by gnustep-release-actions' workflows (the same as every
repository's), and packages what was installed: ORMDesigner for macOS, and an
AppImage with ORMDesigner and `ormtool`
(`./ORMKit-*.AppImage ormtool check model.orm`). A tag releases them:
ORMDesigner signed and notarized with the Sparkle appcast its Check for
Updates… reads, the AppImage with its update information.

## ormtool

```sh
ormtool check model.orm
ormtool verbalize [--html] model.orm
ormtool normalize model.orm out.orm
ormtool coredata model.orm Out.xcdatamodeld [mapping name]
ormtool svg [--dark] model.orm [out.svg | dir/] [diagram name]
ormtool import Model.xcdatamodeld [model.orm]
ormtool validation model.orm dir/ [mapping name]
ormtool query model.orm [query name] [mapping name]
ormtool build schema.forml model.orm
```

`build` makes a new model from its sentences, a line each, as the
verbalizer says them ([docs/VERBALIZATION.md](docs/VERBALIZATION.md)), with
each line it cannot read, and why, on standard error.

`svg` draws a diagram as the editor does: the first (or the named one) to
standard output or a file, or every diagram into a directory, a file each.
`import` brings a Core Data model into ORM: into the `.orm` when it exists,
else into a new model, with what ORM cannot say on standard error.
`validation` writes code that checks the constraints Core Data cannot enforce:
a category on each entity's class, called from its `validateForInsert:` and
`validateForUpdate:`. `query` prints a conceptual query ([docs/QUERIES.md](docs/QUERIES.md)) as
ConQuer's outline, in FORML, as a request to the OData service ODataKit makes
of the mapping, as its plan with the fetches that run it, and as the rows it
finds in the model's sample population.

[Samples/](Samples/README.md) has models to start from: the schemas of
Halpin's papers on conceptual queries and on UML and ORM, with the papers'
queries. Queries run on a model's sample population, kept in the `.orm` as
NORMA keeps it, or made up to meet the constraints
([docs/POPULATIONS.md](docs/POPULATIONS.md)).

## License

LGPL 2.1 (`LICENSE`). The test fixtures in `ORMKitTests/Fixtures/ActiveFacts`
are Clifford Heath's ActiveFacts examples, under the MIT license
(`ORMKitTests/Fixtures/ActiveFacts/LICENSE.txt`); those in
`ORMKitTests/Fixtures/NORMA` are NORMA's sample and test models, under the
Common Public License 1.0 (`ORMKitTests/Fixtures/NORMA/LICENSE.txt`). Neither
is part of the library. The models in `Samples/` are ORMKit's own, of
schemas Halpin's papers publish; StockMate, which ORMDesigner also bundles,
is its author's, used with their leave. ORMDesigner's tab bars are Daniele
Margutti's DMTabBar, under the MIT license
(`ORMDesigner/ThirdParty/DMTabBar/LICENSE-DMTabBar.txt`, also in the app).
