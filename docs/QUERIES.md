# Conceptual queries

ORMKit's queries follow ConQuer, Bloesch and Halpin's conceptual query
language (Halpin, "Conceptual Queries", *Database Newsletter* 26:2, 1998;
Bloesch and Halpin, "Conceptual Queries using ConQuer-II", ER '97). A query
is written in the model's terms: its object types and the fact types they play
in. It never mentions the store's entities, attributes or key paths. A query
stays valid when the mapping changes (an object type absorbed, a subtype
flattened, a fact type made many-to-many); only the requests made from it
change.

A query becomes two requests. One is an OData request to the service ODataKit
makes of the mapping (`ORMQueryOData`, ODATA.md), which an application, a
report or another service sends. The other is a Core Data fetch request
(`ORMQueryFetch`) for an application that holds the store itself.

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
| `+ total(Salary) for Branch > 1000000` | an aggregate (count, total, avg, max, min) of a node the step reaches, for each object above it |
| `✓Branch ↓` | the results in descending (↑ ascending) order of that node |
| `+ or ...` | the node's steps are alternatives, not all required |
| `+ is Professor` | a subtype link, from the supertype or from the subtype |
| `City1` | a label: nodes of one object type with the same label are the same object |
| `Country2 <> Country1` | a condition comparing two nodes of the same object type |

A step reads from the role it enters by: "is location of" is the inverse
reading of "Branch is located in City". When a fact type has no reading that
starts with that role, the step uses another reading, with "that X" in
place of the role.

## Correlation

ConQuer-II correlates by subscript. In the paper's Q4, "who supervises an
employee who lives in the same city as the supervisor but was born in a
different country?":

```
✓Employee1
  + lives in City1
  + was born in Country1
  + supervises Employee2
    + lives in City1
    + was born in Country2 <> Country1
```

Both occurrences of City1 are one city. Country2 is compared with Country1.
In the logic, a label makes the nodes one variable. In a fetch request,
the later occurrence is compared with the earlier one. Inside a `SUBQUERY`,
a bare key path is the fetched object's, and `$x1` the member:

```
(city != nil) AND (country != nil)
AND (SUBQUERY(employees, $x1, ($x1.city == city) AND ($x1.country != country)).@count > 0)
```

When the earlier occurrence is out of scope (it is the member of a subquery
already closed), the later one must be among the objects that node's key
path reaches. Core Data's SQLite store does not translate `$x IN
ownsCars` inside a subquery correctly. So the condition is said the other
way round: from the member back along the inverse relationships to the
fetched object. Q5, "who owns a car, and does not drive more than one of
those cars?":

```
✓Employee
  + owns Car1
  + not drives Car1
    + count(Car1) for Employee > 1

(ownsCars.@count > 0)
AND (NOT (SUBQUERY(cars, $x2, ANY $x2.isOwnedByEmployees == SELF).@count > 1))
```

Q4 and Q5 were checked against Core Data's SQLite store on macOS. On GNUstep,
the in-memory evaluation of a subquery's bare key paths is the fetched
object's only with gnustep-patches' `predicate-subquery` as revised on
2026-10-03. Before that revision, GNUstep evaluated them against the member.

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
| total, avg, max, min | `employees.@sum.salary.usd > 1000000`: over every object the step reaches |
| a sorted listed node | a sort descriptor on its identifier or value, through to-ones |
| a condition on an entity | on its identifier: `city.branches.nr`, `code == "UQ"` |
| a label met again, in scope | `$x1.city == city` |
| a label met again, out of scope | `ANY $x2.isOwnedByEmployees == SELF` |
| a node compared with another | `$x1.country != country` |
| a step to a part of an absorbed object type | the absorbing entity's property: `cityCityname == "Brisbane"` |
| a step through an absorbed object type to an entity that absorbs it too | a join: a second fetch (below) |

Fetching the subtype matters. A store fetching Academic has none of
Professor's properties, so `chair.name == "Informatics"` is only valid on a
request for Professor. When every result must be a professor, Professor is
what is fetched.

The ticked object types become key paths from each fetched object, with the
identifier's key path beside them for display (`employee.cars.regnr`). Through
a to-many, such a key path reaches every related object, not only those that
meet the conditions: a fetch request returns objects, not the rows ConQuer
lists.

## Joins through absorbed object types

By default the mapping absorbs a value-like composite (City, Address) into
the entities that use it: its parts become their attributes. Going through
it is then a join on those parts' values, as the paper's SQL S1 joins
Employee and Branch on city name, state code and country. No relationship
connects the two entities. A predicate cannot fetch one entity inside
another's request. Nor can a subquery range over fetched objects in Core
Data's SQLite store ("Unsupported subquery collection expression type").
So the request is two fetches:

```
✓Employee                        join1: Branch where nr == 52
  + lives in City                Employee where cityCityname != nil
    + is location of Branch = 52   AND (cityCityname == join1's AND cityStateStatecode == join1's
                                        AND cityStateCountry == join1's, for one of join1)
```

`ORMQueryFetch.joins` lists the fetches to make first. Each has its entity,
its predicate, and the pairs of key paths whose values must be equal.
`-predicateJoining:` builds the request's predicate from the objects they
found, and `objectiveCSource` writes the same thing as code. A join is made
only where the absorbed object type is reached directly from the fetched
object, not inside a `not`, an `or` or a subquery, which would need fetches
within fetches. Those are noted.

The query is the same whichever way City is mapped. Mapped as an entity, it
is a relationship and one fetch (`SUBQUERY(city.branches, $x1, $x1.nr ==
52)`); absorbed, it is two. This is ConQuer's semantic stability. Both were
run against Core Data's SQLite store.

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
FORML, its OData request and its fetch request.

## In the designer

**Query ▸ Queries…** (⌥⌘Y) opens the document's queries. **New Query from
Selection** (⇧⌥⌘Y) starts one at the object type selected on the diagram. As
in ConQuer's ActiveQuery:
- you pick a node in the outline;
- the fact types its object type plays in are listed, each read from that
  role ("lives in City", "is headed by Employee");
- double-clicking one adds the step.

Under the outline:
- the selected object type: whether it is listed, its condition, its label,
  and whether its steps are alternatives. A condition's value that names
  another labelled node of the same type ("Country1") compares the two;
- the selected step: and, not or maybe, and its count.

The FORML, the OData request and the Core Data fetch request (from the
document's first mapping, or the defaults) follow every change, each in a
tab. Changes undo with the model.

## Not done yet

- **Correlation beyond relationships:** a label met again out of scope,
  where the earlier occurrence ends in an attribute, is said as `IN` (which
  Core Data's SQLite store may not translate). The same goes for a label
  whose earlier occurrence had conditions of its own: any object its path
  reaches is taken, not only those meeting them. Both cases are noted.
- **Joins inside a `not`, an `or` or a subquery,** through an absorbed
  object type. These need nested fetches.
- **Aggregates beyond a step's own group:**
  - grouped by something other than the node above (ConQuer-II's for-clauses,
    `max(Rating) for Employee > avg(Rating) for Department`);
  - compared with another aggregate;
  - narrowed by the conditions under the step. Core Data's store aggregates
    no subquery, so this case is noted.
- **Queries as derived fact types** that other queries use (ConQuer-II's
  macros); **reading a query back from its outline text**; inferring the path
  between two object types picked at once (ActiveQuery's point-to-point
  queries).
