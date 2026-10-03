# Conceptual queries

ORMKit's queries follow ConQuer, Bloesch and Halpin's conceptual query
language (Halpin, "Conceptual Queries", *Database Newsletter* 26:2, 1998;
Bloesch and Halpin, "Conceptual Queries using ConQuer-II", ER '97). A query
is written in the model's terms: its object types and the fact types they play
in. It never mentions the store's entities, attributes or key paths. A query
stays valid when the mapping changes (an object type absorbed, a subtype
flattened, a fact type made many-to-many); only the fetch request made from it
changes.

## Outline

A query is an outline. It starts at an object type. Each line below an object
type is a **step**: a fact type, entered by the role that object type plays,
leading to the object types that play its other roles. Ticked object types are
listed in the result. A condition compares a value, or an entity's identifier:

```
✓Employee
  + lives in City
    + is location of Branch = 52
```

lists each employee who lives in the city where branch 52 is. The query moves
through City, which is a conceptual join. Nothing in it says how a city is
identified (a name, a state, a country).

| In the outline | Meaning |
| --- | --- |
| `✓X` | X is listed |
| `X = v`, `<>`, `<`, `<=`, `>`, `>=` | a condition on X's value, or on its identifier |
| `+ not ...` | there is no such step |
| `+ maybe ...` | the step if there is one: listed, but leaves nothing out (the outer join) |
| `+ count(X) for Y > n` | how many X each Y has, compared |
| `+ or ...` | the node's steps are alternatives, not all required |
| `+ is Professor` | a subtype link, from the supertype or from the subtype |

A step reads from the role it enters by: "is location of" is the inverse
reading of "Branch is located in City". When a fact type has no reading that
starts with that role, the step uses another reading, with "that X" in
place of the role.

## FORML

A query is also logic. The query is a relation: a variable for each node, and
the ticked ones as its columns. The verbalizer says it as it says derivation
rules (`-[ORMVerbalizer sentencesForQuery:]`):

> List each Employee where that Employee lives in some City that is location
> of some Branch and that Branch is 52.

## Core Data

`ORMQueryFetch` turns a query into a fetch request through a mapping. Each
step follows the property the mapping traced to the step's fact type (see
COREDATA-MAPPING.md, "Traces"):

| ORM | Core Data |
| --- | --- |
| the root object type | the entity fetched; a subtype the root's required steps go down to, if any |
| a step to a value | its attribute: `rating > 5` |
| a step through a to-one | a key path: `degree.rating > 5` |
| a step through a to-many, or through an objectified fact type's entity | `SUBQUERY(cars, $x1, ...).@count > 0` |
| a unary | `isRetired == YES` |
| a subtype | `entity.name IN {"Professor"}` |
| not | `NOT (...)` |
| maybe | nothing |
| count(X) > n | `cars.@count > 1`, or `SUBQUERY(...).@count > 1` |
| a condition on an entity | on its identifier: `city.branches.nr`, `code == "UQ"` |

Fetching the subtype matters. A store fetching Academic has none of
Professor's properties, so `chair.name == "Informatics"` is only valid on a
request for Professor. When every result must be a professor, Professor is
what is fetched.

The ticked object types become key paths from each fetched object, with the
identifier's key path beside them for display (`employee.cars.regnr`). Through
a to-many, such a key path reaches every related object, not only those that
meet the conditions: a fetch request returns objects, not the rows ConQuer
lists.

## Examples, from the paper

The tests (`ORMQueryTests.m`) build the paper's Figure 1 schema and these
queries. The tests check them against key-value coding. They were also run
against Core Data's SQLite store on macOS.

```
Q1 ✓Employee                        SUBQUERY(city.branches, $x1, $x1.nr == 52).@count > 0
     + lives in City
       + is location of Branch = 52

Q2 ✓Employee                        (cars.@count > 0) AND (branch != nil)
     + drives Car
     + works for ✓Branch

Q3 ✓USbranch                        fetches USbranch:
     + not achieved Rank = 1          (NOT (SUBQUERY(uSbranchAchievedRankInYears, $x1,
         in Year < 1998                 ($x1.rank.nr == 1) AND ($x1.year.ad < 1998)).@count > 0))
     + is Branch                       AND (employee.employeeName != nil)
       + is headed by Employee
         + has ✓EmployeeName
         + maybe drives ✓Car
```

## Where queries live

Queries live in the `.orm`, in ORMKit's own namespace, beside the Core Data
mappings. Every change goes through the editor (`ORMQueryEditor`), so
a query is undone with the model. **Save a Copy for NORMA** leaves them out:

```xml
<ormq:Queries xmlns:ormq="http://schemas.ormkit.org/2026-10/Queries">
  <ormq:Query id="_..." Name="Q1">
    <ormq:Node id="_..." ref="_Employee" Projected="true">
      <ormq:Step id="_..." ref="_lives in" Role="_Employee's role">
        <ormq:Node id="_..." Role="_City's role">
          <ormq:Step ... Operator="Not" Count=">" CountValue="1"> ...
```

If a fact type the query uses is deleted, the query is incomplete: the steps
through it are left out, and the fetch says so.

`ormtool query model.orm [name] [mapping]` prints each query's outline, its
FORML and its fetch request.

## In the designer

**Query ▸ Queries…** (⌥⌘Y) opens the document's queries. **New Query from
Selection** (⇧⌥⌘Y) starts one at the object type selected on the diagram. As
in ConQuer's ActiveQuery:
- you pick a node in the outline;
- the fact types its object type plays in are listed, each read from that
  role ("lives in City", "is headed by Employee");
- double-clicking one adds the step.

Under the outline:
- the selected object type: whether it is listed, its condition, and whether
  its steps are alternatives;
- the selected step: and, not or maybe, and its count.

The FORML and the Core Data fetch request (from the document's first
mapping, or the defaults) follow every change. Changes undo with the model.

## Not done yet

- **Correlation:** ConQuer-II's Q4 and Q5 (`lives in City1 ... lives in
  City1`, `Country2 <> Country1`, `count(Car1)`) refer back to an object
  already in the query. The outline has no labels for that yet.
- **Joins through an absorbed object type:** with City absorbed into Employee
  and Branch, Q1 joins on City's parts, which are attributes of two entities
  that no relationship connects. A predicate cannot say that. It takes a
  second fetch, which is not made yet. Until then the fetch notes it, and
  mapping City as an entity makes the query work.
- **Aggregates other than count**, grouped by something other than the node
  above (ConQuer-II's for-clauses); sorting.
- **Queries as derived fact types** that other queries use (ConQuer-II's
  macros); **reading a query back from its outline text**; inferring the path
  between two object types picked at once (ActiveQuery's point-to-point
  queries).
