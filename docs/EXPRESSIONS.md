# Expressions: computed values in queries

A conceptual query ([QUERIES.md](QUERIES.md)) reaches values and compares
them; a rule says what must not be, a calculation aggregates a node, a
derivation says what facts follow ([RULES.md](RULES.md),
[DERIVATION.md](DERIVATION.md)). None of them can compute a value from
others: a trip's length from where it started and ended, a service's cost
less its discount, the litres per hundred kilometres between two fill-ups.
This is the design for that, in [steps](#steps), all six built: value
nodes with arithmetic, aggregates, dates and grouping, reference data, and
computed facts.

## What needs it

Logbook's conceptual schema ([CSDP.md, step 3](../../LogBook/docs/CSDP.md))
works out 24 things that are not stored. Each needs one or more of:

| | What | Needs |
| --- | --- | --- |
| A | arithmetic between values | a trip's length (end − start); a service's cost (sum of items − discount); price per litre (cost ÷ volume); consumption (volume ÷ distance × 100) |
| B | an aggregate as a value, and the one it picks | the fill-up before this one (the latest earlier); the vehicle's reading at a moment (the latest at or before); the rate on a date (the latest on or before) |
| C | dates and moments | a trip's duration; days in a period; when a schedule's next reminder is due (a date + months); the date of a moment |
| D | grouping by a computed key | costs by month; consumption by month; each month against the one before |
| E | conversion | a distance or volume in the user's unit (fixed factors); money in the preferred currency (the rate on its date) |
| F | a computed value as a fact | "Trip was driven Distance" derived; "Service cost Money" derived and stored; the reminder's due distance derived and stored |

And for the rules: "a trip ends no nearer than it started" and "the meter
goes up" compare distances across units (A, E); "events fall while the
vehicle is kept" compares a moment with a date (C).

## What there is to build on

- **Queries** reach values through steps, compare a node with a constant or
  another node of its type, and aggregate a node's bag for a group node
  (count, total, average, maximum, minimum), compared with a value or with
  another aggregate.
- **Calculations** give each object of a type one value: a function of a
  node's bag ([RULES.md](RULES.md#a-calculation)). They are the nearest
  thing to a computed value, but per root object only and not usable inside
  another query.
- **Derivations** derive fact types and subtypes, expanded before planning
  (macros), or stored and kept up to date at save.
- **Logic** (`ORMLogic`) already has function terms (`ORMTerm` with a
  `functionName`, its arguments, aggregate or not), which NORMA's own
  calculated values read into.
- **Plans** carry computed values (`ORMPlanValue`: a path, a constant, an
  aggregate of a bag), which both evaluators compute and the cursors page.
- **The backends:** Core Data's `NSExpression` has the arithmetic functions
  (`add:to:`, `from:subtract:`, `multiply:by:`, `divide:by:`, on GNUstep
  with the patched base); ODataKit filters with arithmetic, and has
  `$compute` and `$apply` grouping and aggregation, in the store where it
  can and in memory where it must.
- **NORMA** keeps calculations in its role paths: a `CalculatedValue` names
  a `Function` the model defines (a name, an operator symbol, parameters,
  "bag input" for an aggregate) and binds each parameter to a path root, a
  pathed role, another calculated value or a constant. ORMKit reads them,
  and writes a derivation query's value nodes so (DERIVATION.md, step 9).

## The design

### One new kind of node: a value

A query's node today is an object type reached by a step. A **value
node** is computed instead: a name, and an expression over other nodes of
the query and constants. In the outline it is a line of its own, `=`
after its name, under the node it is computed for:

```
✓Trip
  + started at Distance1
    + has Quantity1
  + ended at Distance2
    + has Quantity2
  ✓Length = Quantity2 − Quantity1
```

A value node is used as any value node is: listed (✓), compared
(`Length > 100`, `Length < Length2`), sorted by, aggregated
(`total(Length) for Vehicle`), and named by a calculation (`Of`) or a
derivation's projection.

Why a node and not a condition's expression: it can then be everything a
node is, in every place a node goes, with no second set of rules. ConQuer
lists computed columns the same way.

**Its object type** is a value type the result is of: given
(`Length: Distance = ...`) or inferred from the expression (a difference of
two quantities is a quantity; of two moments a duration; a quotient of
amounts a factor). It must be a value type of the model, so that it can be
compared and projected onto a fact type's role (F).

### Expressions

The grammar is small, and each function is one NORMA has or could define,
by name:

| Kind | Written | Meaning |
| --- | --- | --- |
| arithmetic | `a + b`, `a − b`, `a × b` (or `*`), `a ÷ b` (or `/`), `−a`, parentheses | numbers; `÷` by zero is no value |
| numbers | `round(a, n)`, `abs(a)`, `min(a, b)`, `max(a, b)` | |
| dates | `date(m)`, `days(d1, d2)`, `months(d1, d2)`, `minutes(m1, m2)`, `addDays(d, n)`, `addMonths(d, n)`, `month(d)` (its first day), `today()` | moments and dates, in UTC; whole days, months and minutes from the first to the second; `month` is the key for grouping by month |
| dates in a zone | `dateIn(m, z)`, `monthIn(m, z)`, `todayIn(z)` | the day (the month's first day) a moment is on, today, where the time zone named z (an IANA name, `Asia/Almaty`) is; the date as every date is, midnight UTC of that day; a zone of no name, or one no zone has, is UTC |
| choice | `a ?? b` | a, or b where a has no value |
| aggregate | `total(X) for Y` … as today | a value per Y, now usable as a node |

An operand is a node of the query by its designation (`Quantity2`,
`Moment1`, a value node's name) or a constant. Every function takes values
and gives a value; none reaches further into the model than the nodes it
names. Joins stay steps: converting a distance is a step to its unit's
factor and a product, not a function that knows about units (E, below).

**Nothing is a value** where an operand is none, as a missing value
compares in a condition today: `Quantity2 − Quantity1` of a trip with no
end distance is no value, so `Length > 100` does not hold and `Length` is
listed empty.

### "The one before": aggregates as values

An aggregate written as a value node is per its group node, as a
calculation is per its root: `Previous = max(Moment2) for FillUp1`, where
`Moment2` is under a step to the vehicle's other fill-ups with
`Moment2 < Moment1`. The node it picks is then reached by a label:

```
✓FillUp1
  + was at Moment1
  + is of Vehicle
    + Record is of that Vehicle
      + is FillUp2
        + was at Moment2 < Moment1
  Previous = max(Moment2) for FillUp1
  + is of Vehicle
    + Record is of that Vehicle
      + is ✓FillUp3
        + was at Moment3 = Previous
```

That is "the latest earlier", B's every case: the fill-up before, the
reading at a moment, the rate on or before a date. It needs no new
construct beyond the value node: the aggregate is today's, the comparison
today's. A convenience, `latest(FillUp2 by Moment2)`, may come later as
sugar for exactly this.

As built:
- **An aggregate is a value node's whole expression**, `max(Moment2) for
  FillUp1`, never part of another: arithmetic uses it by its name
  (`Consumption = Litres1 / (Odometer1 - Previous) * 100`). It is for the
  node it is under or one above, of a node below that; a total or an
  average of numbers; a count of the value type it is given (`Count:
  Number = count(X) for Y`), the others of the type of what they
  aggregate. In the file, the expression the same way:
  `Expression="max(#_m2) for #_f1"`.
- **Its bag** is today's, the whole query again listing the group and the
  nodes down to the one aggregated, but for the aggregates being made of
  it: one that depends on another computes that one in its own bag ("the
  litres since the fill-up before": a total of the fill-ups after a
  maximum), and none depends on itself.
- **Planned before the node's steps**, which may then be compared with it
  (`Moment3 = Previous`); arithmetic value nodes after them.
- Said as a step's aggregate is: "Previous is the maximum of Moment2 for
  FillUp1".

### Grouping

A list whose listed nodes include an aggregate value node is grouped by
the other listed nodes, as SQL's `GROUP BY` is:

```
✓Vehicle
  + Record is of that Vehicle
    + is Cost
      + was at Moment
      + cost Money
        + has Amount
  ✓Month = month(date(Moment))
  ✓Total = total(Amount) for Vehicle, Month
```

`for Vehicle, Month`: an aggregate's group may now be several nodes,
value nodes among them. This is ConQuer-II's for-clause, widened by one.

As built, the aggregate goes where each of its groups is one value: under
the cost, beside `Month`, not under the vehicle, where a vehicle's costs
are many:

```
✓Vehicle
  + Cost is of that Vehicle
    + was at Moment
    + cost Amount
    ✓Month = month(Moment)
    ✓Total = total(Amount) for Vehicle, Month ↓
```

- **Grouped by its first node that is not computed** (the node it is
  under or one above, over what it aggregates), as an aggregate for one
  node is, its bag run for each slice of that node's objects; of the
  tuples for it, those whose columns for the other nodes are what those
  are here ("where Vehicle is id, Month is month(x1.moment)").
- **The rows** are one for each vehicle and month: a row is a tuple of
  what is listed, and equal ones are given once, as always.
- **Planned once its groups are reached**: an aggregate for nodes reached
  already before the node's steps, one for a value node after it.
- **Through OData**, the bag read and the tuples matched on the answers,
  as for one node: for several groups, one a value node, the service does
  not aggregate it (it groups by paths, not by values computed).

**Sorting by a value node** sorts the rows once all are read: no store
sorts by a value computed. Where any node sorted by is computed, each
sorted node is by its column, in memory (`-[ORMQueryPlan rowSorts]`),
paged from there; else the store sorts, and pages by seek, as before.

### Conversion is reference data and arithmetic

Fixed factors (1 mi = 1.609344 km) are facts of the model's, not code: a
fact type "DistanceUnit is worth Factor km", with a population every store
starts with. A conversion is a step to the factor and a product:

```
  + was at Distance
    + has Quantity
    + is in DistanceUnit
      + is worth Factor
  Kilometres = Quantity × Factor
```

The population is reference data: what an app's store is seeded with, as
the sample population is a model's ([POPULATIONS.md](POPULATIONS.md)),
marked so that the generated app seeds it and no user edits it.

Money is the same with the rate on the record's date, found as "the one
before" is (B): the latest rate on or before. Neither needs a function that
knows about units or currencies.

As built:
- **The mark** is the fact type's (`isReferenceData`), kept in ORMKit's
  namespace; its facts are those of the model's population. In a schema's
  text, a line after the fact type for each fact, its players as the
  population table names them, by commas (a value quoted for a comma, a
  parenthesis or a quote; a player of several values in parentheses):

  ```
  DistanceUnit is worth Factor km
  Each DistanceUnit is worth exactly one Factor km.
  Reference data: km, 1
  Reference data: mi, 1.609344
  ```
- **Seeded** from the tables ([RUNTIME.md](RUNTIME.md#the-tables)): each
  object found by its key or inserted, its reference values set again, so
  that a user's change is put right and an update's new factors arrive.
  "No user edits it" is that, for now: nothing refuses the edit itself.
- **Conversion** is a step to the factor and a product, as above. A value
  node compared with another that its node computes is planned as soon as
  what it uses is reached, between the node's steps, so that a node its
  later steps reach may be compared with it ("the meter goes up", across
  units: `Km2 = Quantity2 * Factor2 < Km1`).
- **Money** converts at the rate on or before the record's day: rates
  users enter, not reference data, found as "the one before" is, an
  aggregate of the rates' dates and then of the rate on it; a record
  already in the currency, which has no rate, as it is:

  ```
      + cost Money
        + has Amount
        + is in Currency1
          + maybe was worth Factor1 in Currency2 on Date1 <= Day
          + maybe was worth Factor2 in Currency2 on Date2 = RateDay
      Day: Date = date(Moment)
      RateDay = max(Date1) for Record
      Rate = max(Factor2) for Record
      Converted = Amount * coalesce(Rate, 1)
      ✓Total = total(Converted) for Vehicle, Month
  ```

  Where a mapping absorbs a currency as its code
  (`AbsorbIdentifierTypes`), the steps from it to its rates, a fact type
  kept as an entity of its own, are joins on the code: each rate whose
  base is the code, bound, optional for a maybe.
- **One set for each aggregate.** A bag plans only the value nodes it
  needs: those it lists, those with a condition, those compared with, and
  what those use; the others, aggregates among them, are not in it. Bags
  are shared by every planning, nested ones too, kept by the aggregate
  and by which of the aggregates it uses are being made around it; and a
  set planned the same twice (a join's members) is defined once. Logbook's
  `CostsByMonth` went from 47 sets to 4: a bag for each of its three
  aggregates, and the rates' members.

### Computed facts (F)

A derivation's projections may name value nodes: "Trip was driven
Distance" is derived by a query listing each Trip and its `Length`. Not
stored, it is expanded into the query that goes through it, value node and
all; derived and stored, it is computed at save (DERIVATION.md, step 6),
as a stored derivation is today.

As built:
- **A ticked value node is a role's column**, of the role's player's
  value type (`derivedColumns`):

  ```
  Derivation of "Trip lasted Minutes":
  ✓Trip
    + was at Moment1
    + ended at Moment2
    ✓Minutes: Minutes = minutes(Moment1, Moment2)
  ```

  Said "that Trip lasted Minutes if and only if ... and Minutes is the
  number of minutes from Moment1 to Moment2".
- **Gone through**, the step's node is the value node, with what the query
  says of it (`+ lasted ✓Minutes > 60`). No step starts from a role its
  rule computes, nor goes on from one: there is no object there.
- **Stored**, the population's facts are made from the rule's rows (a
  value no instance has, as a new one), and the save hook sets the
  attribute to the computed column's value, for each object a change
  reaches.
- **A role played by a type identified by several values** (Money, an
  amount and a currency) takes a ticked node for each part, found by its
  type: a computed amount, and the currency the rule reaches. Said "that
  Service cost the Money of Amount and Currency"; in the population, the
  Money made of its parts where it is none yet; at save, each part's
  property set (DERIVATION.md, step 6). A node of the player itself
  still does for the role, as before.
- **Partly derived and stored** ones are worked out too, where the rule
  derives something (Logbook's service cost: its items less its
  discount; any other record keeps the cost entered).
- **The outline writes a value node's type** where it is not the one taken
  from the first node it uses, so that it reads back.

### In the file

A value node is a child of the node it is computed for, beside its steps,
with its name, its value type (`ref`) and its expression, each node by
its id:

```xml
<ormq:Value id="_v1" ref="_Distance" Name="Length" Projected="true"
            Expression="subtract(#_q2, #_q1)" Comparison="&gt;" Value="100"/>
```

The expression is the outline's with node ids for designations and
functions by name (`add`, `subtract`, `multiply`, `divide`, `negate`,
`round`, `abs`, `min`, `max`, `coalesce`; the date functions with step
3); a constant is a number or quoted text (`'a''b'`). One attribute
rather than nested elements: a rename of a node rewrites it, and nothing
else reads it. A value node is listed, compared and sorted with the
attributes a node has (`Projected`, `Comparison`, `Value`, `CompareTo`,
`Sort`). An aggregate value node will keep today's attributes
(`Aggregate`, `Of`, its group nodes).

**For NORMA,** a derivation whose rule has value nodes is written as the
fact type's informal rule (its verbalization), and as its role path: each
value node a `CalculatedValue` of a `Function` the model declares, a
computed role projected from it (DERIVATION.md, step 9).

### Logic and words

A value node is a variable bound by a function term: `Length =
subtract(Quantity2, Quantity1)`. Verbalized as Halpin says calculations:

> List each Trip and Length where that Trip started at some Distance1 that
> has some Quantity1 and ended at some Distance2 that has some Quantity2,
> and Length is Quantity2 minus Quantity1.

Each function has its words (`minus`, `times`, `divided by`, `the date of`,
`the number of days from ... to ...`, `the first day of the month of`).

### Planning and running

- **The plan** gets an applied value: `ORMPlanValue` with a function
  and its operand values (paths, constants, other applied values;
  aggregates with step 2), `subtract(endedAtKilometres, kilometres)`. A
  condition compares two values, as now; a column lists one. Each operand
  is a node's place where the value node is computed (an entity by its
  identifier); one not reached, out of scope, or absorbed is noted, and
  the value node left out. A node a maybe reaches through to-ones is one
  value from the object read, so it may be used outside the maybe: no
  value where there is none.
- **Core Data:** a condition with a computed value is checked on the
  objects fetched, as an aggregate's is, and a column computed for each
  row; both by `ORMPlanApply`, which the OData runner shares. Saying the
  arithmetic in the fetch's predicate, where FreeCoreData's SQLite store
  can as Apple's does, is for later.
- **OData:** arithmetic in `$filter` where OData has it (`add`, `sub`,
  `mul`, a minus); a division, a rounding or a choice is checked on the
  answers. A listed value node of the object read's own values, in that
  arithmetic, is computed by the service (`$compute`); others from what
  is read. A bag of a member's own attribute is aggregated by the service
  (`$apply`), a value for each group ([ODATA.md](ODATA.md)).
- **Sorting by a value node** sorts the rows in memory, once read
  ([Grouping](#grouping)).
- **Validation code:** a rule with a computed value is no one predicate;
  where it needs no store (no bag, no join), the driver asks its plan of
  the object in memory, with the evaluator the interpreter checks fetched
  objects with. Aggregates in rules are bags, checked at save as
  rules over joins are.

### Typing, and what is refused

- An operand of the wrong kind (a date added to a quantity) is refused when
  the value node is set, with why: each function says what kind each
  argument is, a number or a moment, and what it gives
  (`+[ORMQueryExpression functionKinds]`); a value node of a kind its value
  type is not is refused too. Quoted text is a date where one is wanted
  (`days('2026-01-01', today())`).
- **Units are the modeller's to convert.** Whether two quantities are in
  the same unit depends on the data, not the query, so `Quantity2 −
  Quantity1` is not refused. A rule that compares distances converts them
  first (E), as the meter rule will; the words say what is compared.
- Division by zero, and a date out of range, give no value.

## Steps

1. **Value nodes with arithmetic** (A), done: the node in the model, the
   outline, the editor, the file; the logic and the words; planned and run
   (Core Data, OData `$filter`); listed and compared; sorted (step 4). In Logbook: a trip's length and a fill-up's price per
   unit of volume (`TripLength`, `PricePerVolume`); the trip-ends-no-
   nearer rule within a unit (`TripEndsNoNearer`) turned out to need only
   a comparison of two nodes.
2. **Aggregates as value nodes** (B), done: the latest earlier, compared
   with. In Logbook: the fill-up before (`FillUpBefore`), fuel
   consumption per full tank (`FullTankConsumption`). The reading at a
   moment and the rate on a date are the same construct, and come with the
   reports (step 4) and conversion (step 5) that use them.
3. **Dates** (C), done: the date functions, durations, in UTC, as the
   sample populations' moments are; through OData, the answers' moments
   read as ISO 8601 text, and dates computed checked on the answers. In
   Logbook: a trip's duration (`TripDuration`), when a reminder is next due
   by date (`ReminderNextDue`), events while the vehicle is kept
   (`EventsWhileKept`, checked by the generated validation in memory).
4. **Grouping** (D), done: aggregates for several nodes; grouped lists;
   sorting by a value node. OData `$apply` is for later: the bag's tuples
   are matched on the answers. In Logbook: costs by vehicle, month and
   currency (`CostsByMonth`).
5. **Reference data** (E), done: a population an app is seeded with; the
   unit factors. Conversion is then steps and arithmetic. In Logbook: the
   unit factors, the meter rule and the trip rule across units, a trip's
   length in its driver's unit; costs by month in the owner's currency,
   each at the rate on or before its day.
6. **Computed facts** (F), done: projections of value nodes; derived and
   stored ones computed at save. In Logbook: how long a trip lasted
   ("Trip lasted Minutes"); a service's cost, Money of two values, partly
   derived and stored (`ServiceCost`).

Each step lands with its tests on both platforms and its part of
Logbook's model, as the earlier items did.

## Not here, for later

- `latest(X by Y)` as sugar for "the one before".
- Units checked across joins, so that adding kilometres to miles is caught
  when the query is made.
- Window functions (a running total, a rank).
- OData `$apply` with several groups, a computed one among them
  (`compute(...)/groupby(...)`), and aggregates through paths the service
  follows; computing in the store where FreeCoreData's SQLite store can,
  as Apple's does.
- Profiling the runtime: how long a plan takes as the store grows, bags
  run whole where their group is not reached from the object read, rows
  sorted in memory.
