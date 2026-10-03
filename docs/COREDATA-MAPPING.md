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
| Fact type of three or more roles, or an objectified fact type | an entity of its own, with a to-one relationship (or attribute) per role, and a uniqueness constraint over the roles each of its uniqueness constraints spans; a role unique by itself is one to one instead, its inverse to-one |
| Subtyping | entity inheritance (`parentEntity`); the supertype abstract when its subtypes cover it (an inclusive-or over the subtype facts) |
| Internal uniqueness on a single role (the "one" side) | to-one; with a value type opposite, a uniqueness constraint on the attribute |
| External uniqueness, composite identifiers | a uniqueness constraint over the attributes involved |
| Simple mandatory | `optional="NO"` |
| Frequency on a single role | `minCount` / `maxCount` |
| Value constraint (numbers, dates) | `minValueString` / `maxValueString` |
| Value constraint (a list of text values) | `regularExpressionString` (`^(?:M|F)$`) |
| Text data type length | `maxValueString` (Core Data's string bounds are lengths) |
| Ring, exclusion, subset, equality, value comparison, frequency over several roles, deontic rules | not expressible: kept on the entity as `userInfo` entries holding their FORML verbalization, and listed in the mapping's report as unenforced |

A value type that plays a role of its own (a unary about the value, "Some
String is long", or a fact type functional on the value with another
value at the far end) is an entity keyed by the value, a unique `value`
attribute, as Rmap gives it a table keyed by the value. A value type of a
class of its own (an e-mail address, a URL) can be mapped as a
Transformable attribute of that class, with the value transformer that
stores it (`NSSecureUnarchiveFromData` unless another is named).

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

## Styles: what the store is for

There is often more than one good logical model of a conceptual one, and
which is better depends on what the store is for. A mapping has a style
that sets the defaults; its options and each object type's own mapping
(Entity, Absorbed, Transformable, Ignored) decide over them.

| Style | What is absorbed | For |
| --- | --- | --- |
| Application (default) | values; value-like entity types into what uses them; objectifications one to one with a player folded into it | an app's own store |
| Relational | as Rmap groups tables: identifier-only types absorbed, subtypes flattened, a composite reference scheme absorbed where one fact type refers to it | a schema as a relational designer would draw it |
| Entities | values only | reports and analysis over things in their own right |

A **value-like** entity type is one with nothing to it but the values that
identify it, several of them (an Address: street, city, postal code,
region, country): its preferred identifier, or in the Application style
an alternate key beside a generated id. It is absorbed where it is used,
its values properties of the entity that refers to it
(`Warehouse.addressCity`, `addressStreetFirstStreetLine`), a to-one
relationship where a value is an entity. An Address kept as an entity
makes a join of every order's address; absorbed, it is part of the
order. Core Data's composite attributes would hold it as one; FreeCoreData
has none yet, so it is flattened (or, mapped Transformable, a class of
its own).

An **objectification one to one with a player** (Death: Person is dead) is
folded into the player: the objectified fact type maps as it would
without one, and the objectification's fact types are the player's, made
optional unless every player plays the role.

An analytical (star schema) style, facts and dimensions, is for later.

## Rmap, adapted

Halpin's Rmap groups fact types into relational tables. The mapping
follows its grouping where Core Data and a relational schema agree, and
departs from it where Core Data has more to say:

| Rmap | Core Data |
| --- | --- |
| A table per entity type with functional fact types, its columns those fact types | an entity, its attributes and to-one relationships those fact types |
| A table per fact type of a compound uniqueness (many-to-many) | to-many relationships both ways; an entity for an objectified one or one of three roles or more |
| Subtypes absorbed into the supertype's table (or kept separate) | an entity inheritance tree (one SQLite table, as Rmap's absorption), or flattened |
| An entity type with nothing but its identifier is no table: its identifier is a column wherever it is used | an entity, with its identity and its relationships; absorbed in the Relational style or when asked |
| A compositely identified type with nothing else: its identifying columns spread into the tables that refer to it | absorbed, its values properties of the entity that refers to it |
| A nesting one to one with a player: folded into the player's table | folded into the player's entity |
| A value type with a role of its own is a table keyed by the value | an entity keyed by the value |

In the Relational style the mapping makes of Clifford Heath's 28 models
every table his ActiveFacts makes, but for the types his CQL marks
`[separate]` or `[static]`, a modeller's choice that is the per-type
Entity mapping here (a test compares them). It does not absorb an entity
type whose identifier is generated (an auto counter cannot be supplied by
what refers to it), nor flatten a subtype identified its own way, nor
absorb a composite more than one fact type refers to.

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
- optionally, a directory for its validation code (below), also relative;
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

## Validation code: what Core Data cannot enforce

Core Data checks optionality, counts, bounds, patterns and single-entity
uniqueness. The rest of the model's constraints the mapping reports as not
enforced, and generates as code: `<Name>Validation.h` and `.m`, a category
`(ORMValidation)` on each entity's class that has something to check.

Xcode usually generates the classes (Codegen "class" or "category"), and the
user adds validation in a category of their own. The generated category sits
beside it. It is regenerated with the model, so it is never edited:

```objc
@implementation Person (Validation)
- (BOOL)validateForInsert:(NSError **)error
{
    return [super validateForInsert:error] && [self orm_validateConstraints:error];
}
- (BOOL)validateForUpdate:(NSError **)error
{
    return [super validateForUpdate:error] && [self orm_validateConstraints:error];
}
@end
```

| ORM2 | Checked |
| --- | --- |
| inclusive-or (disjunctive mandatory) | at least one of the properties is set (a unary's attribute is true; a to-many is not empty) |
| mandatory loosened for Core Data (`ormkit.mandatory`) | the relationship is set |
| exclusion; exclusive-or | at most one of the properties is set (exactly one); over pairs of roles, the related objects are disjoint |
| subset; equality | the first is set only where the second is (both or neither); over pairs of roles, the related objects are a subset (equal) |
| ring | each of its properties (irreflexive, asymmetric, acyclic, intransitive, ...) over the entity's relationship to itself |
| value comparison | the two attributes compared, when both are set |
| value constraint with several ranges or open bounds, on a number | the value is within one of the ranges |

A violation is an `NSError` like Core Data's own: `NSCocoaErrorDomain`,
`NSManagedObjectValidationError`, with the constraint's verbalization as its
description. The object and the first property are under
`NSValidationObjectErrorKey` and `NSValidationKeyErrorKey`, and the constraint's
name under `ORMConstraint`. Several violations make an
`NSValidationMultipleErrorsError`, with the violations under
`NSDetailedErrorsKey`.

Deontic constraints are obligations to be told of, not enforced. They do not
make `orm_validateConstraints:` fail; `orm_deonticViolations` returns them.

A subentity with rules of its own checks its parent's too.

What one object cannot check is listed in the notes and in a comment at the
top of the `.m`:
- uniqueness across objects, which needs a fetch;
- frequencies over several roles;
- set comparisons through join paths;
- constraints over the roles of n-ary fact types.

The directory is the mapping's `ValidationPath`. **Synchronize** writes the
code there, generated from the model it has just written, so the names are
the ones in the `.xcdatamodeld`. `ormtool coredata` writes it as well, and
`ormtool validation model.orm dir/` writes the code alone.

## Import: from Core Data to ORM

An existing Core Data model can be brought into ORM
(`-[ORMEditor importCoreDataModel:path:notes:reason:]`, `ormtool import`, and
**Core Data ▸ Import Core Data Model…** in the designer). It is reverse
engineering: from the logical model back to the conceptual one. Halpin and
Bloesch's comparison of UML class diagrams with ORM (JDM 1999) gives the
correspondences: a class is an entity type; an attribute is a fact type; an
association is a fact type; multiplicities are uniqueness and mandatory
constraints; an association class is an objectification.

| Core Data | ORM2 |
| --- | --- |
| entity | entity type of the same name |
| parent entity | supertype; an abstract one is covered by its subtypes (an inclusive-or over the subtyping roles) |
| required attribute, unique by itself | the reference mode: `Customer(.email)`, the value type taking the attribute's data type and length |
| uniqueness over several properties | an external uniqueness constraint; the preferred identifier when the entity has none |
| required Boolean attribute | a unary: `isActive` is "Customer is active" |
| other attribute | "Entity has Value", functional, mandatory unless optional; a value type of the attribute's name and type is reused |
| Transformable attribute | a value type mapped as Transformable, of the attribute's class and transformer |
| min, max, pattern | a value constraint on the role |
| relationship and its inverse | a binary fact type, unique on each to-one side, mandatory where required, a frequency for other counts; a name ending in the destination's is read hyphen-bound ("Order has billing- Address") |
| required to-one loosened for Core Data (`ormkit.mandatory` in its `userInfo`) | mandatory |
| entity of to-one relationships only (two or more), unique together | an objectified fact type over what it joins, named as the entity; required attributes that its other uniqueness constraints span are roles of the fact type too; its other attributes are the objectification's own fact types |

The import makes a mapping in the **Entities** style, so nothing is absorbed,
and gives it the imported model as its baseline. Where the rules would name an
element differently, the Core Data name is kept as an override. Mapping the
result gives back the model it came from. The tests check this for StockMate
and the ActiveFacts examples: each is mapped, imported and mapped again. What
ORM cannot say (deletion rules, fetch requests, configurations, ordering) stays
in the baseline, and the import lists it in its notes, along with entities that
have nothing to identify them by.

The whole import is one undoable step, on a diagram named after the model (or
on a new model's only diagram, while that is empty), arranged automatically.

