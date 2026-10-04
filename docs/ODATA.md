# Serving the model: OData through ODataKit

An ORM model describes the domain an application keeps. Mapped to Core Data
(COREDATA-MAPPING.md) it is a store. [ODataKit](../../ODataKit) serves any
Core Data store as an OData 4.01 service: `$metadata` written from the model,
queries, inserts, updates, `$batch`. A mapping's Core Data model is ready for
it, so one ORM model gives the backend and the database together.

ODataKit takes what Core Data cannot say from each element's `userInfo`
(ODataKit's `docs/how-it-works.md` lists the keys). A Core Data mapping writes
them unless it is told not to (`ServeOData="false"` on the mapping element,
`-[ORMMappingEditor setServesOData:ofMapping:]`). `ORMODataAnnotator` writes them
after the rest of the mapping is made:

| ORM | `userInfo` | OData |
| --- | --- | --- |
| an entity, not a subentity | `OData.entitySet`: the plural of its name | the entity set; a subentity's objects are in its root's set, as a derived type |
| an entity, in the mapping's namespace (`ODataNamespace`, `Default` unless set) | `OData.type`: `Default.Employee` | its type's name, which a cast to a subtype names; ODataKit's mapper knows it without `$metadata` |
| the preferred identifier, when each of its roles is a required attribute (a reference mode, an absorbed identifier's parts, a value entity's value) | `OData.key` = `YES` on each attribute | the key |
| any other identifier (one with roles of entity types, an objectification's, a fact type's entity) | a surrogate: an Integer 64 attribute `id`, required, with `OData.key` and `OData.computed` | a key the service numbers on insert (one more than the largest); `Core.Computed`, so clients never send it |
| an object type's definition; a value type's, on the attributes it is the value of | `OData.description` | `Core.Description` |
| a value list | `OData.annotations` `{"Validation.AllowedValues": [...]}` | `Validation.AllowedValues` |
| an open bound of a single numeric range | `OData.annotations`: `Validation.Minimum` / `Maximum` with `@Validation.Exclusive` | an exclusive bound |

Ranges and patterns that Core Data holds already (`minValue`, `maxValue`,
`regularExpression`) are not repeated: ODataKit reads them from the model as
`Validation.Minimum`, `Maximum` and `Pattern`.

A surrogate is named `id` (or `id2` and so on, if that name is taken); an
override on the source `<object type id>.key` renames it. The mapping notes
each one. ODataKit's service fills it in on insert. An application that
writes to the store directly, not through the service, must set it itself.

What a user writes in Xcode under any other key, their own `OData.entitySet`
for instance, is kept on synchronization: only `ormkit.` entries belong to
the mapping.

## Import

Importing a Core Data model that ODataKit serves reads the annotations back:

- an attribute with `OData.key` alone is the reference mode;
- several are the preferred identifier, an external uniqueness;
- a surrogate (`OData.key` and `OData.computed`, an integer) is no fact type,
  and its name is kept as an override;
- an entity with a key of its own takes no other identifier from its
  uniqueness constraints;
- `OData.description` is the definition.

The import's mapping serves OData if the model had keys, and not otherwise,
so a plain Core Data model maps back as it came.

## Verified

A harness mapped StockMate and the ActiveFacts Insurance model and compiled
each with `momc`. It then served them with `ODataService` over SQLite on
macOS:

- every entity set answers;
- `$metadata` has the keys, the AllowedValues and Core.Computed;
- two posts to a surrogate-keyed set got the ids 1 and 2.

## Queries as requests

`ORMQueryOData` says a conceptual query (QUERIES.md) as the request an
application, a report or another service sends to the service. Every
Core Data ↔ OData rule is ODataKit's, and none is copied here:
- **Names:** wire names, entity sets, collection paths, type names and keys
  come from ODataKit's `ODataPropertyMapper`. It reads the model as Core
  Data describes it, built in memory from the mapped model
  (`-[ORMCDModel managedObjectModel]`).
- **The request:** built as ODataKit's typed tree (`ODataExpression`,
  `ODataAggregate`, `ODataQueryOptions`). Values are typed literals, which
  ODataKit quotes. An aggregate is built from its path and method, each
  checked to be an OData identifier (`+[ODataExpression aggregateOf:aggregate:]`).
- **Names that are no identifiers** never reach a request. The mapping
  doesn't use a name override Core Data can't hold (`+isCoreDataName:`),
  and notes it. ODataKit's builders refuse any other name: one in the
  model's `OData.property`, say. The refusal is noted, and no request is
  written (`testANameThatIsNoIdentifierIsRefused`).
- **The URL:** written by ODataKit's `ODataQueryBuilder`
  (`-URLWithServiceRoot:error:`). Where the API lacks something, ODataKit
  is changed, not worked around here.

| ORM | OData |
| --- | --- |
| the root object type | its entity set; a subtype the root's steps require is a cast: `Branches/Default.USbranch` |
| a step to a value, through a to-one | `Degree/Rating gt 5` |
| a step through a to-many | `Awardeds/any(x1:x1/Degree/Rating gt 5)` |
| a node met again out of the lambda it was met in | back from it along the inverses to `$it`, by key: `x2/IsOwnedByEmployees/any(x3:x3/Nr eq $it/Nr)` |
| objects compared, in scope | by key: `x1/City/Id eq $it/City/Id` |
| a subtype | `isof(x1,Default.Professor)`, and a cast to read its properties |
| `count(X) > n`, nothing asked of X | `Languages/$count gt 1` |
| a count with conditions | `any` for some, `not any` for none; otherwise the members meeting them, counted (OData 4.01), the member `$this` and the outer object still `$it`: `Cars/$count($filter=$this/IsOwnedByEmployees/any(x3:x3/Nr eq $it/Nr)) gt 1` |
| `total(X) > n` and the other aggregates | `Employees/aggregate(Salary/Usd with sum) gt 1000000` |
| the ticked object types | `$select` (each level's key, and what is listed), `$expand` for what is reached |
| the order | `$orderby=Nr desc` |

The paper's queries (QUERIES.md):

```
Q1  Employees?$filter=City/Branches/any(x1:x1/Nr eq 52)&$select=Nr
Q2  Employees?$filter=Cars/any() and Branch ne null&$select=Nr&$expand=Branch($select=Nr)
Q3  Branches/Default.USbranch?$filter=not USbranchAchievedRankInYears/any(x1:x1/Rank/Nr eq 1
      and x1/Year/Ad lt 1998) and Employee/EmployeeName ne null&$select=Nr
      &$expand=Employee($select=Nr,EmployeeName;$expand=Cars($select=Regnr))
Q4  Employees?$filter=City ne null and Country ne null and Employees/any(x1:x1/City/Id eq $it/City/Id
      and not (x1/Country/Name eq $it/Country/Name))&$select=Nr
Q5  Employees?$filter=OwnsCars/any() and not (Cars/$count($filter=$this/IsOwnedByEmployees/any(x3:x3/Nr
      eq $it/Nr)) gt 1)&$select=Nr
Pay Branches?$filter=Employees/aggregate(Salary/Usd with sum) gt 1000000&$orderby=Nr desc&$select=Nr
```

An object type absorbed into others (City, when it is not an entity) is
joined on its parts' values. The service has no `$root`, so the join is a
request made first:

```
join1: GET Branches?$filter=Nr eq 52&$select=CityCityname,CityStateStatecode&$expand=CityStateCountry($select=Name)
GET Employees?$filter=CityCityname ne null and (CityCityname eq 'Brisbane' and ...)
```

`-filterJoining:` makes the second request's filter from the rows the first
returns. A part that is an entity is compared by its key.

`testTheServiceAnswersTheQueries` (macOS) serves the mapped model with
`ODataService` over SQLite and checks the rows that Q1 to Q5, the payroll query
and a count return. The Query window has an OData tab, and `ormtool query`
prints the request.

## Building with ODataKit

ORMKit links ODataKit's `ODataKit` and `ODataIncrementalStore` libraries (the
query builder is the client's). The tests also link `ODataService`.
- **Xcode:** build through `ORMKit.xcworkspace`, which holds
  `../ODataKit/ODataKit.xcodeproj` beside this project.
- **GNUstep:** link an installed ODataKit, over FreeCoreData, or a built
  checkout (`make ODATAKIT=../ODataKit`, `odatakit.make`).
- **CI:** pins both, as `ODATAKIT_REF` and `FREECOREDATA_REF`.

## Not done yet

- `$expand` of what a to-many step reaches lists every related object, not
  only those meeting the step's conditions. `$expand=X($filter=...)` would
  say it, where the conditions do not refer to `$it`.
- The service test runs on macOS only. On GNUstep it needs FreeCoreData's
  `momc` to compile the model.
