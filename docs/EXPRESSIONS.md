# Expressions: computed values in queries

A conceptual query ([QUERIES.md](QUERIES.md)) reaches values and compares
them; a rule says what must not be, a calculation aggregates a node, a
derivation says what facts follow ([RULES.md](RULES.md),
[DERIVATION.md](DERIVATION.md)). None of them can compute a value from
others: a trip's length from where it started and ended, a service's cost
less its discount, the litres per hundred kilometres between two fill-ups.
This is the design for that, in [steps](#steps); steps 1 and 2, value
nodes with arithmetic and aggregates, are built.

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
  pathed role, another calculated value or a constant. ORMKit reads them;
  it does not write role paths for queries yet (DERIVATION.md, for later).

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
| dates | `date(m)`, `days(d1, d2)`, `months(d1, d2)`, `addDays(d, n)`, `addMonths(d, n)`, `month(d)` (its first day), `today()` | moments and dates; `month` is the key for grouping by month |
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

### Computed facts (F)

A derivation's projections may name value nodes: "Trip was driven
Distance" is derived by a query listing each Trip and its `Length`. Not
stored, it is expanded into the query that goes through it, value node and
all; derived and stored, it is computed at save (DERIVATION.md, step 6),
as a stored derivation is today.

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

**For NORMA,** a derivation whose rule has value nodes is written, as
today, as the fact type's informal rule (its verbalization); the role path
with `CalculatedValue`s, and the `Function`s it names, is the "writing a
query back as NORMA's role path" DERIVATION.md defers, and would come with
it.

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
  answers. A listed value node is computed from what is read, as a
  calculation's column is, rather than by `$compute`; a grouped list by
  `$apply` (`groupby`, `aggregate`), with step 4.
- **Sorting by a value node** is noted, not done: the cursors page by
  key paths the store sorts by, which a computed value is not. It needs
  rows sorted in memory, with step 4's grouping.
- **Validation code:** a rule whose condition is one predicate with
  expressions is one predicate still (`NSExpression` in it); the driver
  asks it of the object. Aggregates in rules are bags, checked at save as
  rules over joins are.

### Typing, and what is refused

- An operand of the wrong kind (a date added to a quantity) is refused when
  the value node is set, with why.
- **Units are the modeller's to convert.** Whether two quantities are in
  the same unit depends on the data, not the query, so `Quantity2 −
  Quantity1` is not refused. A rule that compares distances converts them
  first (E), as the meter rule will; the words say what is compared.
- Division by zero, and a date out of range, give no value.

## Steps

1. **Value nodes with arithmetic** (A), done: the node in the model, the
   outline, the editor, the file; the logic and the words; planned and run
   (Core Data, OData `$filter`); listed and compared. Sorting by one is
   left for step 4. In Logbook: a trip's length and a fill-up's price per
   unit of volume (`TripLength`, `PricePerVolume`); the trip-ends-no-
   nearer rule within a unit (`TripEndsNoNearer`) turned out to need only
   a comparison of two nodes.
2. **Aggregates as value nodes** (B), done: the latest earlier, compared
   with. In Logbook: the fill-up before (`FillUpBefore`), fuel
   consumption per full tank (`FullTankConsumption`). The reading at a
   moment and the rate on a date are the same construct, and come with the
   reports (step 4) and conversion (step 5) that use them.
3. **Dates** (C): the date functions, durations. In Logbook: a trip's
   duration, when a reminder is next due, events while the vehicle is kept.
4. **Grouping** (D): aggregates for several nodes; grouped lists; OData
   `$apply`. In Logbook: the reports by month.
5. **Reference data** (E): a population an app is seeded with; the unit
   factors. Conversion is then steps and arithmetic. In Logbook: the meter
   rule across units, every report in the user's units and currency.
6. **Computed facts** (F): projections of value nodes; derived and stored
   ones computed at save. In Logbook: a service's cost stored, a trip's
   distance derived, a reminder's due distance and date.

Each step lands with its tests on both platforms and its part of
Logbook's model, as the earlier items did.

## Not here, for later

- Writing value nodes into NORMA's role paths (`CalculatedValue`,
  `Function`), with DERIVATION.md's writing of queries back as role paths.
- `latest(X by Y)` as sugar for "the one before".
- Units checked across joins, so that adding kilometres to miles is caught
  when the query is made.
- Window functions (a running total, a rank).
