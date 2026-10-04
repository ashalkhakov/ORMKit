# Conceptual queries

ORMKit's queries follow ConQuer, Bloesch and Halpin's conceptual query
language (Halpin, "Conceptual Queries", *Database Newsletter* 26:2, 1998;
Bloesch and Halpin, "Conceptual Queries using ConQuer-II", ER '97). A query
is written in the model's terms: its object types and the fact types they play
in. It never mentions the store's entities, attributes or key paths. A query
stays valid when the mapping changes (an object type absorbed, a subtype
flattened, a fact type made many-to-many); only the requests made from it
change.

A query is planned against a mapping (`ORMQueryPlanner`): what to read, and
what must hold of it, in the mapped model's entities and properties, said for
no store in particular (`ORMQueryPlan`). Two backends say the plan in their
own terms:

| Who asks | Backend | What it makes |
| --- | --- | --- |
| an application that holds the store, such as one implementing a service with ODataKit | `ORMQueryInterpreter` | fetches against Core Data, as many as the plan takes, and what is kept of what they return |
| an application, report or service that calls the API | `ORMQueryOData` (ODATA.md) | requests to the service ODataKit makes of the model |

A plan is public data: it is written as a property list and read back. So it
can be made where the model is edited and run where the store is.

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
In the logic, a label makes the nodes one variable. In the plan, the later
occurrence is compared with the earlier one. Inside a `SUBQUERY`,
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

On GNUstep, evaluating a subquery's bare key paths in memory needs
gnustep-patches' `predicate-subquery` as revised on 2026-10-03. With it,
they mean the fetched object's paths; before it, GNUstep evaluated them
against the member.

## FORML

A query is also logic. The query is a relation: a variable for each node, and
the ticked ones as its columns. The verbalizer says it as it says derivation
rules (`-[ORMVerbalizer sentencesForQuery:]`):

> List each Employee where that Employee lives in some City that is location
> of some Branch and that Branch is 52.

## Plans

`ORMQueryPlanner` makes the plan. Each step follows the property the mapping
traced to the step's fact type (see COREDATA-MAPPING.md, "Traces"). Every
ORM-level decision is made here, once, for both backends: scopes, correlation,
subtypes, aggregate paths, and joins. Its text (`-[ORMQueryPlan text]`):

| ORM | The plan |
| --- | --- |
| the root object type | `read Employee`; a subtype the root's required steps go down to, if any |
| a step to a value | `x1.rating > 5` |
| a step through a to-one | a path: `degree.rating > 5` |
| a step through a to-many, or an objectified fact type's entity | `some cars as x1 has ...` |
| a unary | `isRetired = true` |
| a subtype | `x1 is a Professor`, and a cast to read it as one |
| not, or, maybe | `not (...)`, `... or ...`; maybe asks nothing |
| count(X) > n | `number of cars > 1`, or `number of cars as x2 having ... > 1` |
| total, avg, max, min | `sum of x1.salary.usd over employees as x1 > 1000000`, with `having ...` where the steps below narrow the members |
| a label met again, in scope | `x1.city is city` |
| a label met again, out of scope | `x2 is among ownsCars`: among what the trail reaches from the object read |
| a node compared with another | `not (x1.country is country)` |
| a step to a part of an absorbed object type | the absorbing entity's property: `cityCityname` |
| a step through an absorbed object type to an entity that absorbs it too | `... match [read Branch; where nr = 52]`: a plan of its own (below) |
| the ticked object types | `list self (nr), employee.cars (regnr)`: paths from the object read, an entity by its identifier |
| a sorted listed node | `order by nr descending`, through to-ones |

Reading the subtype matters. A store fetching Academic has none of
Professor's properties, so `chair.name = 'Informatics'` holds only of a
Professor. When every result must be a professor, Professor is what is read.

## The interpreter: running a plan against Core Data

Some plans cannot be one fetch request, so `ORMQueryInterpreter` runs them
(`-executePlan:inContext:error:`). It returns the objects, and a row for each
with a value per column.
- **Joins:** each `match` is fetched first, wherever it is, even inside a
  `not`, an `or` or a subquery. Its objects' values go into the predicate in
  its place.
- **What the SQLite store can say** becomes the fetch's predicate.
- **What it cannot say** is evaluated on the objects it returns, an aggregate
  of the members meeting conditions for instance.

Values go into predicates as arguments, never as text. `-programForPlan:error:`
says what it will do:

```
fetch Branch where employees.@sum.salary.usd > 1000000
sorted by nr descending
```

| The plan | Core Data |
| --- | --- |
| a path | a key path; from a variable: `$x1.city` |
| `some C as x1 has ...` | `SUBQUERY(C, $x1, ...).@count > 0` |
| `number of C ... > n` | `C.@count > n`, `SUBQUERY(...).@count > n` |
| `sum of x1.v over C` | `C.@sum.v`; with `having`, on the objects fetched (`keep those where ...`) |
| `is a Professor` | `entity.name IN {Professor and its subentities}` |
| `is` | `==` |
| `is among` a trail | `ANY $x2.isOwnedByEmployees == SELF`: back along the inverses, which the SQLite store says in SQL |
| `match [...]` | that plan fetched first: `join1: fetch Branch where nr == 52` |

## Joins through absorbed object types

By default the mapping absorbs a value-like composite, such as City or Address,
into the entities that use it, and its parts become their attributes. Going
through it is then a join on those parts' values, as the paper's SQL S1 joins
Employee and Branch on city name, state code and country. No relationship
connects the two entities, so the plan holds a plan of the joined entity:

```
✓Employee                        read Employee
  + lives in City                where cityCityname = cityCityname, cityStateStatecode = ...,
    + is location of Branch = 52   cityStateCountry = cityStateCountry match [read Branch; where nr = 52]
```

The interpreter fetches branch 52 first, then the employees whose parts equal
one of its objects'. ODataKit's service has no `$root`, so the OData backend
also makes the join a request of its own. The query is the same however City
is mapped. As an entity it is a relationship and one fetch; absorbed, it is
two. This is ConQuer's semantic stability.

## Examples, from the paper

The tests (`ORMQueryTests.m`) build the paper's Figure 1 schema and these
queries, and check each plan. The interpreter runs them against a SQLite
store on both platforms; ODataKit's service is checked on macOS. Both return
the same rows.

```
Q1 ✓Employee                        read Employee
     + lives in City                where some city.branches as x1 has x1.nr = 52
       + is location of Branch = 52

Q2 ✓Employee                        read Employee
     + drives Car                   where some cars and branch is set
     + works for ✓Branch            list self (nr), branch (nr)

Q3 ✓USbranch                        read USbranch
     + not achieved Rank = 1        where not (some uSbranchAchievedRankInYears as x1 has
         in Year < 1998               (x1.rank.nr = 1 and x1.year.ad < 1998))
     + is Branch                      and employee.employeeName is set
       + is headed by Employee
         + has ✓EmployeeName
         + maybe drives ✓Car

Q5 ✓Employee                        read Employee
     + owns Car1                    where some ownsCars and not (number of cars as x2
     + not drives Car1                having x2 is among ownsCars > 1)
       + count(Car1) > 1
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
through it are left out, and the plan notes it.

`ormtool query model.orm [name] [mapping]` prints each query's outline, its
FORML, its OData request, its plan, and how the interpreter runs it.

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

The FORML, the OData request, and the plan with how the interpreter runs it
(from the document's first mapping, or the defaults) follow every change, each
in a tab. Changes undo with the model.

## Not done yet

- **Correlation with conditions:** a label met again out of scope whose
  earlier occurrence had conditions of its own takes any object its path
  reaches, not only those meeting them. Noted. Where no inverse leads back,
  the interpreter evaluates `IN` on the objects fetched.
- **Aggregates beyond a step's own group:**
  - grouped by something other than the node above (ConQuer-II's for-clauses,
    `max(Rating) for Employee > avg(Rating) for Department`);
  - compared with another aggregate;
  - narrowed by the conditions under the step, in OData. ODataKit's service
    aggregates no filtered collection, so this case is noted there; the
    interpreter evaluates it on the objects it fetches.
- **Rows:** the interpreter returns a row per object, a column reached
  through a to-many holding every related object. ConQuer's relation, a row
  per binding of the ticked nodes that meets the conditions, would be the
  next step.
- **Correlated joins:** a plan in a `match` reads from no variable of the
  plan that holds it, so it is run once.
- **Queries as derived fact types** that other queries use (ConQuer-II's
  macros); **reading a query back from its outline text**; inferring the path
  between two object types picked at once (ActiveQuery's point-to-point
  queries).
