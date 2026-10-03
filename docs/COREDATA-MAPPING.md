# Mapping ORM2 to Core Data, both ways

ORMKit maps a conceptual ORM2 model to one or more Core Data models and keeps
them in step as either side changes. This document is the design: what maps to
what, where the mapping's state lives, and how a change made on the Core Data
side finds its way back into the ORM model.

Core Data sits at the logical level, like a relational schema, but it is an
object graph rather than tables: objects have identity of their own,
references are relationships with inverses, and there are no foreign keys or
composite keys. So the mapping is neither Halpin's Rmap (no columns, no
foreign keys) nor a UML class mapping (no multivalued attributes, no
association classes), but borrows from both: Rmap's grouping of functional
fact types around the object type they are functional on, and the UML
mapping's treatment of identity and of many-to-many fact types.

## What maps to what

| ORM2 | Core Data |
| --- | --- |
| Entity type | Entity |
| Entity type identified by a reference mode and playing nothing else of its own (`Weight(kg:)`, played only in "Product has Weight") | absorbed: an attribute where it is used (`Product.weight`, Decimal) |
| Value type | the type of the attributes it is the value of |
| Reference mode (`Product(.Id)`) | an attribute (`id`), mandatory, in a uniqueness constraint |
| Binary fact type, functional on an entity type `A`, other role played by a value type | attribute of `A`; optional unless `A`'s role is mandatory |
| Binary fact type between two entity types | a relationship and its inverse; to-one on the side whose role is unique |
| Many-to-many binary fact type between entity types | to-many relationships both ways |
| Many-to-many binary fact type with a value type (`Person speaks Language`) | an entity for the value type, related to-many both ways |
| Unary fact type (`Person smokes`) | Boolean attribute, not optional, default NO: absent means false |
| Fact type of three or more roles, or an objectified fact type | an entity of its own, with a to-one relationship (or attribute) per role, and a uniqueness constraint over the roles its uniqueness constraint spans |
| Subtyping | entity inheritance (`parentEntity`); the supertype abstract when its subtypes cover it (an inclusive-or over the subtype facts) |
| Internal uniqueness on a single role (the "one" side) | to-one; with a value type opposite, a uniqueness constraint on the attribute |
| External uniqueness, composite identifiers | a uniqueness constraint over the attributes involved |
| Simple mandatory | `optional="NO"` |
| Frequency on a single role | `minCount` / `maxCount` |
| Value constraint (numbers, dates) | `minValueString` / `maxValueString` |
| Value constraint (a list of text values) | `regularExpressionString` (`^(?:M|F)$`) |
| Text data type length | `maxValueString` (Core Data's string bounds are lengths) |
| Ring, exclusion, subset, equality, value comparison, frequency over several roles, deontic rules | not expressible: kept on the entity as `userInfo` entries holding their FORML verbalization, and listed in the mapping's report as unenforced |

Data types:

| NORMA | Core Data |
| --- | --- |
| Text: Fixed / Variable / Large Length | String (length as max) |
| Numeric: Signed Small / Signed / Signed Large Integer | Integer 16 / 32 / 64 |
| Numeric: Unsigned Tiny / Small / Integer / Large | Integer 16 / 32 / 64 / 64, minimum 0 |
| Numeric: Auto Counter | Integer 64 (`userInfo` `ormkit.autoCounter`) |
| Numeric: Single / Double / Floating Point | Float / Double / Double |
| Numeric: Decimal, Money | Decimal |
| Temporal: Date, Time, Date & Time, Auto Timestamp | Date |
| Logical: True or False, Yes or No | Boolean |
| Raw Data (all) | Binary Data; Picture with external storage |
| Other: Row ID, Object ID | UUID |
| Unspecified | String, reported |

## Names

Entities are named after their object types, made into identifiers
(`Order Line` becomes `OrderLine`). Attributes and relationships take, in
order of preference:

1. the role's name, when the modeller gave it one (NORMA's role Name);
2. the name of the object type at the other end, lower camel case
   (`Product has Barcode` gives `barcode`; the reference mode gives its
   mode: `id`, `code`);
3. when that collides on the entity, the reading's words with the other
   object type's name (`Person was born in Country` and `Person lives in
   Country` give `wasBornInCountry` and `livesInCountry`).

To-many sides are pluralized (`products`). Names Core Data reserves
(`description`, `entity`, `objectID`, ...) get a suffix. A name the user
changes on either side is kept as an override and survives regeneration.

## Mappings and where they live

A model may have several Core Data mappings: an app's full model, a sync
subset, a read-only cache. Each mapping has

- a name and the path of its `.xcdatamodeld`, relative to the `.orm` file;
- a scope: the whole model, a diagram's object types, or a list;
- options: whether identifiers are materialized as attributes, whether
  subtypes are separate entities or flattened into their supertype, whether
  many-to-many value facts get an entity or a transformable attribute;
- overrides: per element, a name, or how an object type maps (entity,
  absorbed, ignored);
- the **baseline**: the Core Data model as last written, with every element
  traced to the ORM element it came from.

They are saved in the `.orm` file itself, as a top-level element in ORMKit's
own namespace beside NORMA's bridges:

```xml
<ormcd:CoreDataMappings xmlns:ormcd="http://schemas.ormkit.org/2026-10/CoreDataBridge">
  <ormcd:Mapping id="_..." Name="App" Path="App/Model.xcdatamodeld" Scope="Model">
    <ormcd:Override ref="_role id" Name="title" />
    <ormcd:ObjectTypeMapping ref="_object type id" As="Entity" />
    <ormcd:Baseline> ... the model's contents XML ... </ormcd:Baseline>
  </ormcd:Mapping>
</ormcd:CoreDataMappings>
```

so a model and its mappings are one document to open, save, undo and version.
**Save a Copy for NORMA** writes the file without it, for a NORMA that does
not know the namespace.

## Traces

Every entity, attribute and relationship written carries the id of the ORM
element it came from in its `userInfo` (`ormkit.source`): the object type for
an entity, the role for an attribute or relationship (the role played by the
other end, so a fact type's two directions are told apart). The traces travel
with the `.xcdatamodeld`, so an element renamed in Xcode is still recognized
as the one the mapping made.

## Keeping the two in step

Synchronizing a mapping is a three-way merge between

- **base**: the baseline, as last written;
- **ours**: what the ORM model maps to now;
- **theirs**: the `.xcdatamodeld` on disk, as Xcode or ModelBuilder left it.

Changes from base to ours are the modeller's, in the ORM model: they are
written out. Changes from base to theirs were made on the Core Data side, and
each is turned back into the ORM change that would have produced it:

| Changed in Core Data | Becomes in ORM |
| --- | --- |
| entity, attribute or relationship renamed | a name override; for an entity, optionally renaming the object type |
| attribute made optional or required | the role's simple mandatory constraint removed or added |
| attribute's type changed | the value type's data type, when it is the attribute's own; an override otherwise |
| attribute added | a value type (reused by name) and a binary fact type "E has V", functional on E |
| relationship added (with inverse) | a binary fact type between the two entity types, unique on each to-one side |
| relationship made to-many or to-one | the uniqueness constraint on the role added or removed |
| entity added | an entity type, and its attributes and relationships as above |
| element deleted | the fact type or object type deleted, or excluded from the mapping (the user chooses; excluding is the default) |
| uniqueness constraint added or removed | an internal or external uniqueness constraint |
| min, max or pattern changed | the value constraint |

What Core Data has and ORM does not (fetch requests, configurations, indexes,
code generation settings, entity positions in Xcode's editor, `userInfo`
entries of the user's own) is kept from theirs: regeneration never loses it.

When the same element changed on both sides, the ORM model wins unless the
user picks otherwise; every proposed change is listed before anything is
applied, and applying is one undoable step in the ORM document.
