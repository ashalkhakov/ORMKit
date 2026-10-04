# Conceptual queries

ORMKit's queries follow ConQuer, Bloesch and Halpin's conceptual query
language (Halpin, "Conceptual Queries", *Database Newsletter* 26:2, 1998;
Bloesch and Halpin, "Conceptual Queries using ConQuer-II", ER '97). A query
is written in the model's terms: its object types and the fact types they play
in. It never mentions the store's entities, attributes or key paths. A query
stays valid when the mapping changes (an object type absorbed, a subtype
flattened, a fact type made many-to-many); only the requests made from it
change.

## From a query to rows

A query goes through three stages. The middle one, the plan, is where all
the ORM-to-Core-Data thinking happens, once, for both backends.

```
conceptual query  --ORMQueryPlanner-->  plan  --ORMQueryInterpreter-->  Core Data fetches  --> rows
(ORM terms)         (+ a mapping)       (entities,                        (and checks on
                                         properties)  --ORMQueryOData-->   what they return)
                                                                          OData requests
```

1. **The query**, in the model's terms: start at an object type, follow
   fact types, tick what to list, add conditions. It never mentions
   entities, attributes or key paths. The same query is also logic, which is
   how FORML reads it out.
2. **The plan** (`ORMQueryPlanner` → `ORMQueryPlan`): the same query said in
   the mapped Core Data model's entities and relationships, for no store in
   particular. This is where the mapping is consulted: which property each
   fact type became, whether City is an entity or absorbed into Employee,
   whether a subtype has its own entity. It decides scopes, correlation and
   joins.
3. **A backend** says the plan in its store's terms:

   | Who asks | Backend | What it makes |
   | --- | --- | --- |
   | an application that holds the store, such as one implementing a service with ODataKit | `ORMQueryInterpreter` | Core Data fetches, as many as the plan takes, and checks on what they return |
   | an application, report or service that calls the API | `ORMQueryOData` ([ODATA.md](ODATA.md)) | requests to the service ODataKit makes of the model |

A plan is public data: it is written as a property list and read back. So
it can be made where the model is edited and run where the store is.

`ormtool query model.orm Q4` prints every stage. Here is the paper's Q4 on
[Samples/Company.orm](../Samples/Company.orm): who supervises an employee
who lives in the same city but was born in a different country? Names
added.

**1. The query**, as ConQuer's outline. Labels (`City1`) say "the same
city":

```
✓Employee1
  + lives in City1
  + was born in Country1
  + supervises ✓Employee2
    + lives in City1
    + was born in Country2 <> Country1
    + has ✓EmployeeName
  + has ✓EmployeeName
```

**The same query in FORML**, read out of its logic:

> List each Employee1, Employee2, EmployeeName1 and EmployeeName2 where
> Employee1 lives in some City and was born in some Country1 and supervises
> Employee2 that lives in that City and ... Country2 is not Country1.

**2. The plan.** Each step became the property the mapping made of its fact
type. "Supervises" is to-many, so it became `some employees as x1`, with x1
standing for each supervised employee. The second "City1" became a
comparison with the first: `x1.city is city`.

```
read Employee
where city is set and country is set
  and some employees as x1 has (x1.city is city and not (x1.country is country)
                                and x1.employeeName is set)
  and employeeName is set
list self (nr), x1 (nr), x1.employeeName, employeeName
```

**3a. Core Data.** The interpreter says the plan as a fetch request. Here it
is one fetch; a plan can take several:

```
fetch Employee where (city != nil) AND (country != nil)
  AND (SUBQUERY(employees, $x1, ($x1.city == city) AND (NOT ($x1.country == country))
                                AND ($x1.employeeName != nil)).@count > 0)
  AND (employeeName != nil)
```

**3b. OData.** The same plan as a request to the service:

```
GET Employees?$filter=City ne null and Country ne null
  and Employees/any(x1:x1/City/Id eq $it/City/Id and not (x1/Country/Name eq $it/Country/Name)
                    and x1/EmployeeName ne null) and EmployeeName ne null
  &$select=Nr,EmployeeName&$expand=Employees($select=Nr,EmployeeName)
```

**Rows**, from the sample's population, one per way the conditions are met:

| Employee1 | Employee2 | EmployeeName of Employee2 | EmployeeName of Employee1 |
| --- | --- | --- | --- |
| 2 | 10 | Fay | Bea |

Bea (2) lives in Sydney, was born in Australia, and supervises Fay (10), who
also lives in Sydney but was born in the UK.

The rest of this document covers each stage: the outline's notation
([Outline](#outline), [Correlation](#correlation)), the logic
([FORML](#forml)), the plan ([Plans](#plans)), the interpreter
([The interpreter](#the-interpreter-running-a-plan-against-core-data)), and
joins that no relationship makes
([Joins through absorbed object types](#joins-through-absorbed-object-types)).

## The plan, as Query-by-Example

A plan is close to Query-by-Example (QbE): it names entities and their
properties, binds example variables, and lists what is marked for output.
Q4's plan as QbE skeletons, with `P.` marking what is printed and `_c`, `_k`
the example elements that join the rows:

```
Employee | nr      | city | country | employeeName | supervisor
         | P._e1   | _c   | _k1     | P._n1        |
         | P._e2   | _c   | _k2     | P._n2        | _e1

condition: _k2 <> _k1
```

| QbE | The plan |
| --- | --- |
| a skeleton row for the entity read, with `P.` | `read Employee` ... `list` |
| a row joined by an example element | `some employees as x1 has ...` |
| an example element used twice | `x1.city is city` |
| a constant in a cell | `x1.nr = 52` |
| a `¬` row | `not (...)` |
| `CNT.`, `SUM.` in a condition box | `number of ... > n`, `sum of ... > n` |

The plan keeps something QbE flattens away: the **tree**. Every plan has one
entity it reads, and each condition sits in a scope:
- under `some ... as x1`, x1 is each member;
- under `not`, nothing inside is bound outside it;
- under `number of`, members are counted per object read.

Both backends are trees of the same shape. A Core Data fetch is one entity
and a predicate whose `SUBQUERY(...)` nest; an OData request is one entity
set and a `$filter` whose `any(x1: ...)` lambdas nest. From QbE's flat rows
those scopes would have to be worked out again: which row is the root,
which joins are to-many, how far a `¬` reaches. That is exactly where
correlation (Q4, Q5) gets subtle. The ConQuer outline already has them, so
the plan carries them through.

In QbE terms, the plan is QbE with its scopes kept: one skeleton row per
`read` and per `some`, nested as the outline nests them.

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
traced to the step's fact type (see [COREDATA-MAPPING.md, "Traces"](COREDATA-MAPPING.md#traces)). Every
ORM-level decision is made here, once, for both backends: scopes, correlation,
subtypes, aggregate paths, and joins.

A plan is a program, as a ConQuer-II query is: a sequence of named sets
(`ORMPlanDefinition`), each read by a plan of its own and free to use the
sets before it, then the set the plan reads. Its conditions may use any of
them. A set with parameters depends on the plan using it: on its object read
(`o1`), or on what is bound where it is used.

```
let join1 = read Branch where nr = 52
read Employee
where cityCityname = cityCityname, ... in join1
```

Its text (`-[ORMQueryPlan text]`):

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
| a step through an absorbed object type to an entity that absorbs it too | `... in join1`, a set the plan defines: `let join1 = read Branch where nr = 52` (below) |
| the ticked object types | `list self (nr), employee.cars (regnr)`: paths from the object read, an entity by its identifier |
| a sorted listed node | `order by nr descending`, through to-ones |

Reading the subtype matters. A store fetching Academic has none of
Professor's properties, so `chair.name = 'Informatics'` holds only of a
Professor. When every result must be a professor, Professor is what is read.

## The interpreter: running a plan against Core Data

Some plans cannot be one fetch request, so `ORMQueryInterpreter` runs them.
It reads incrementally: `-cursorForPlan:inContext:error:` gives a cursor whose
`-nextPage:error:` returns the next objects and the rows they make.

The rows are a result set: a sequence of tuples, a value per ticked node, and
no tuple twice, across pages too.
- **A tuple per way the conditions are met.** A node reached through a `some`
  lists the members that meet its conditions, and only those. "Who speaks
  Latin, and the language" lists Latin, not every language they speak.
- **Each alternative of an `or`.** A node one alternative binds is empty in
  the tuples of another.
- **Each value of a `maybe`.** A maybe step binds nothing, so its node lists
  every object its path reaches, or none: an outer join. A query whose objects are many, or slow to check, is read only as far
as the caller asks. `-executePlan:inContext:error:` reads every page.
- **What the SQLite store can say** becomes the fetch's predicate. The fetch
  is read in slices (`fetchOffset`, `fetchLimit`), in the plan's order.
- **What it cannot say** is checked on each slice as it comes:
  - an aggregate of the members meeting conditions;
  - a subquery over objects bound outside the fetch.

  The interpreter evaluates the plan's own conditions there, by key-value
  coding.
- **Joins:** a join with a set (`in join1`) is said in the predicate when
  three things hold:
  - its plan is the store's to say entirely;
  - it reads from nothing of this plan;
  - it finds few objects (`joinPrefetchLimit`, 1000).

  Then they are fetched once, and their values put in its place, wherever the
  join is, inside a `not`, an `or` or a subquery too. Otherwise each object
  is probed: the joined plan is run with that object's values, and stops at
  the first object found. A join over a large table never loads the table.
- **Correlated joins:** a joined plan may name what the plan it is in reached:
  - its object read, as a parameter (`o1`) the join binds;
  - the variables bound where the join is.

  Such a join is probed for each object, with those bound.

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
| `... in join1` | the set fetched first: `join1: fetch Branch where nr == 52` |

## Joins through absorbed object types

By default the mapping absorbs a value-like composite, such as City or Address,
into the entities that use it, and its parts become their attributes. Going
through it is then a join on those parts' values, as the paper's SQL S1 joins
Employee and Branch on city name, state code and country. No relationship
connects the two entities, so the plan defines the joined set and compares
the parts with its objects':

```
✓Employee                        let join1 = read Branch where nr = 52
  + lives in City                read Employee
    + is location of Branch = 52 where cityCityname = cityCityname, cityStateStatecode = ...,
                                   cityStateCountry = cityStateCountry in join1
```

The interpreter fetches branch 52 first, then the employees whose parts equal
one of its objects'. Where the joined plan meets a node of this one again, as
in "who heads a branch in the city they live in", the join depends on each
employee:

```
let join1(o1) = read Branch where employee is o1
read Employee
where cityCityname = cityCityname, ... in join1 (o1 is this)
```

The interpreter probes each employee, with `o1` bound to it. ODataKit's service has no `$root`, so the OData backend
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

The Results tab runs the query against the model's sample population, in a
store of the mapping, and shows its rows. **Make Up a Population** (or
**Query ▸ Make Up a Sample Population**) gives a model without one a
population that meets its constraints ([POPULATIONS.md](POPULATIONS.md)).

## Not done yet

- **Correlating an absorbed object type:** an object type absorbed into the
  entities that use it (City, under the default mapping) has no one value to
  compare, so a label on it is dropped, with a note. Company's Q4 needs City
  as an entity, which the sample's mapping makes it; comparing all of an
  absorbed type's parts would lift this.
- **Correlation with conditions:** a label met again out of scope whose
  earlier occurrence had conditions of its own takes any object its path
  reaches, not only those meeting them. Noted. Where no inverse leads back,
  the interpreter evaluates `IN` on the objects fetched.
- **Conditions under a `maybe`:** ConQuer-II's Q3 (in
  [Samples/University.orm](../Samples/University.orm)) lists each degree
  rated above 5 where there is one. The planner lists each degree and drops
  the condition: the columns under a `maybe` should take only the members
  meeting it.
- **Aggregates beyond a step's own group:**
  - grouped by something other than the node above (ConQuer-II's for-clauses,
    `max(Rating) for Employee > avg(Rating) for Department`);
  - compared with another aggregate;
  - narrowed by the conditions under the step, in OData. ODataKit's service
    aggregates no filtered collection, so this case is noted there; the
    interpreter evaluates it on the objects it fetches.
- **Rows from the service:** the OData cursor's rows are the columns'
  values as the entities come, each value of an expanded to-many, not only
  the members a `some` binds. The interpreter's are a result set.
- **Correlated joins in OData:** they need a request for each object, which
  is not made. Noted, and the join left out of the request; the interpreter
  probes them.
- **Queries as derived fact types** that other queries use (ConQuer-II's
  macros); **reading a query back from its outline text**; inferring the path
  between two object types picked at once (ActiveQuery's point-to-point
  queries).
