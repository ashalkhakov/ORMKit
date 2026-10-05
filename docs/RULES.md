# Rules: queries as constraints and calculations

A conceptual query ([QUERIES.md](QUERIES.md)) can do more than list. This
covers two more uses:
- **A constraint:** a query whose answers are the violations.
- **A calculation:** a query that gives each object of a type a value.

Both are said in the model's terms, verbalized, checked against sample
populations, and run against a store or a service. Constraints also become
validation code.

This is a design. Nothing in it is built yet.

## Why

ORM's graphical constraints cover a great deal, but not everything a domain
has. "No employee earns more than the head of their branch" is a rule over
a join path and a comparison. NORMA can keep it only as a note, in English;
Halpin calls these textual constraints. Today ORMKit has nowhere to put it
either. `ORMPopulationChecker` lists value comparisons and sequences across
fact types as unchecked, and `ORMValidationGenerator` notes join paths it
cannot check.

Dataphor puts such a rule in the database itself, as a constraint over an
expression that must hold (`create constraint ... not exists (...)`), and
checks it on every change. A conceptual query is that expression, in the
model's own terms.

A calculation is the other half: "a branch's total salary" is a value of a
Branch, defined by a query, not stored. Here it is computed where it is
asked for. Using one inside another query's conditions makes it a derived
fact type, which is parked (below).

## In the file

A query says what it is for. A plain query lists, as now:

```xml
<ormq:Query id="_q1" Name="Overpaid" Kind="Constraint" Modality="Alethic">
  <ormq:Node ...>                       <!-- as any query -->
</ormq:Query>

<ormq:Query id="_q2" Name="TotalSalary" Kind="Calculation" Function="Total" Of="_salaryNode">
  <ormq:Node id="_branchNode" ref="_Branch"> ...
</ormq:Query>
```

- `Kind`: `List` (left out, the default), `Constraint` or `Calculation`.
  `ORMQuery` gets a `kind`, and `ORMQueryEditor` a `setKind:...`, through the
  editor as every change is, so it undoes.
- A **constraint** has `Modality`: `Alethic` (left out, the default) or
  `Deontic`, as NORMA's constraints have.
- A **calculation** has:
  - its object type, which is the query's root;
  - `Of`, the node whose values it is computed from;
  - `Function`, one of `Count`, `Total`, `Average`, `Maximum` or `Minimum`
    (the query aggregates' names), or `Value` for the node's one value.

**Save a Copy for NORMA** leaves them out, as it leaves out queries.

## What they mean

### A constraint

**The rows are the violations.** Every object the query finds breaks the
rule, and the rule holds when the query finds none. "Overpaid":

```
✓Employee
  + earns Salary1
  + works for Branch
    + is headed by Employee
      + earns Salary2
  Salary1 > Salary2
```

The ticked nodes say which objects a violation is about, and what is
reported. Ticking nothing reports the object read.

**Read as logic** it is the negation of the query's relation closed
existentially:
- alethic: `¬∃x̄ φ(x̄)`;
- deontic: `O ¬∃x̄ φ(x̄)`.

It is the same relation `-[ORMQuery relation]` gives the verbalizer and the
planner now.

**FORML** puts that negation in front of the query's sentence, as Halpin
does for the negative forms of constraints ([VERBALIZATION.md](VERBALIZATION.md)):

- *It is impossible that some Employee earns some Salary1 and works for
  some Branch that is headed by some Employee who earns some Salary2 where
  Salary1 is greater than Salary2.*
- Deontic: *It is forbidden that ...*.

### A calculation

**Its value for each object** x of the root type is the function of the Of
node's values over the query's rows with the root bound to x.
- The rows are projected onto the nodes from the root down to Of, each
  binding once. This is exactly the bag of an aggregate for the root
  ([QUERIES.md](QUERIES.md#aggregates-of-a-bag)): a salary is counted once
  for each employee who earns it, however many ways the query reaches it.
- Every object of the type has a value. With no rows, a count or total is 0
  and the rest are nothing.
- `Value` is the Of node's one value. Where there are several, the
  calculation has none for that object, and the check says so.

**FORML**:

- *The TotalSalary of each Branch is the total of the Salaries that are
  earned by some Employee who works for that Branch.*
- `Value`: *The HeadName of each Branch is the EmployeeName of the
  Employee who heads that Branch.*

## Planning and running

Neither needs a new kind of plan.

- **A constraint's plan is the query's plan.** Running it finds the
  violations, and the cursors read it a page at a time like any query
  ([CURSORS.md](CURSORS.md)). "Are there any?" asks for a page of one.
- **A calculation's plan** reads the root's entity with no condition, and
  lists the object and a computed column:

  ```
  let bag1 = read Branch where some employees as x1 has x1.salary is set
             list self (nr), x1 (nr), x1.salary.usd
  read Branch
  list self (nr), total of Salary in bag1 where Branch is nr
  ```

  `ORMPlanColumn` gains a computed value, an `ORMPlanValue` (the bag lookup
  aggregates already use), beside its path. Both evaluators already compute
  that value; a column now asks them for it. The bag is read for each batch
  of branches, only for theirs. Everything the cursors do already applies.

## Where they are checked

| where | constraints | calculations |
|---|---|---|
| **sample populations** | `ORMPopulationChecker` runs each constraint against the population's store (`ORMPopulationStore`, the document's first mapping or the default). Each row is a violation, with the query's verbalization and the row's values. A constraint the planner cannot plan is in `-unchecked`, with its notes. | `Value` calculations with more than one value are reported. |
| **a store** | `ORMRuleChecker` (new): each constraint's plan run by the interpreter, the first violations of each. It can check a whole store on demand, a nightly check say. | the interpreter computes the column |
| **a service** | the same requests to the OData service. The client checks; the service itself does not enforce them yet. | the same, the bag read per page |
| **validation code** | `ORMValidationGenerator` adds a check to the root entity's category: the plan's condition evaluated on `self` as an `NSPredicate`, for a constraint whose condition the store can say. Others (a bag, a probed join) are noted, as join paths are today. | none |
| **ormtool** | `ormtool check model.orm` checks the sample population against the constraints too, and says which are violated. | `ormtool query` prints the values |
| **the designer** | **Kind** in the Queries window. A constraint's Results tab lists its violations in the sample population, and the window's list marks a violated constraint. | the Results tab lists each object and its value |

**Validation code checks from one object,** when that object is inserted or
updated. A change to another object on the join path (the head's salary
rising) is not seen there. Dataphor checks database-wide constraints at
commit; the code here is per object, as Core Data's validation is.

Run the store or service check to catch the rest. The generated comment says
which objects the rule depends on. The notes call such a constraint
"checked from Employee only".

## Steps

1. **Kinds in the file and the model:** `Kind`, `Modality`, `Function`, `Of`;
   `ORMQuery` properties; editor setters with undo; the outline text says
   them; the XML round-trips.
2. **Verbalization:** "It is impossible / forbidden that ..." for
   constraints, and "The ... of each ... is ..." for calculations, with tests
   against the FORML forms above.
3. **Constraints checked:** `ORMPopulationChecker` over the population
   store, `ORMRuleChecker` for a store, and `ormtool check`. A sample's
   constraint goes in `Samples/` with a population that breaks it and one
   that does not.
4. **Calculations computed:** computed plan columns, in both evaluators and
   both backends, and in `ormtool query`.
5. **The designer:** Kind, Modality, Function and Of in the Queries window;
   violations and values in the Results tab.
6. **Validation code** for constraints whose condition the store can say.

## Not here, for later

- **A calculation inside another query's conditions** ("branches whose
  TotalSalary is over a million"). That is a derived fact type, "Branch has
  TotalSalary", which is ConQuer-II's macros and NORMA's derivation rules.
  It needs its own design.
- **The service enforcing constraints** as it writes (ODataKit's service
  hooks).
- **Transition constraints**, about what may change into what. Dataphor has
  them; this does not.
