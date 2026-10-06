# Rules: queries as constraints and calculations

A conceptual query ([QUERIES.md](QUERIES.md)) can do more than list. This
covers two more uses:
- **A constraint:** a query whose answers are the violations.
- **A calculation:** a query that gives each object of a type a value.

Both are said in the model's terms, verbalized, checked against sample
populations, and run against a store or a service. Constraints also become
validation code.

Steps 1 to 6 are built ([Steps](#steps)); what is left is listed there and
under [Not here, for later](#not-here-for-later).

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
  some Branch that is headed by some Employee that earns some Salary2
  where Salary1 is greater than Salary2.* (Each node is introduced by
  "some"; the exact words are the phrase engine's, as for any query.)
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

- *The TotalSalary of each Branch is the total of Salary where that Branch
  employs some Employee that earns that Salary.*
- `Value`: *The HeadName of each Branch is the EmployeeName where that
  Branch is headed by some Employee that has that EmployeeName.*

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

Run the store or service check to catch the rest, or, later, the check at
commit (below). The generated comment says
which objects the rule depends on. The notes call such a constraint
"checked from Employee only".

## Steps

1. **Done: kinds in the file and the model.**
   - The file has `Kind`, `Modality`, `Function` and `Of`.
   - `ORMQuery` has `kind`, `isDeontic`, `calculationFunction` and
     `calculatedNode`.
   - `ORMQueryEditor` has `setKind:`, `setDeontic:` and `setCalculation:`.
     Leaving a kind drops what only it had, and a calculation whose node a
     step takes away is of none.
   - The outline's first line says what the query is for: "It is impossible
     that:", or "TotalSalary of each Branch is total(Salary) of:".
2. **Done: verbalization.**
   - A constraint is "It is impossible that" (or "It is forbidden that") and
     the query's formula, each node introduced by "some".
   - A calculation is "The TotalSalary of each Branch is the total of Salary
     where ...": the function in the words step aggregates already use,
     then the formula with the root and its node named.
3. **Done: constraints checked.**
   - `ORMRuleChecker` plans each constraint query against a mapping and runs
     it in a context, each row a violation ("Lives near work: Employee 21,
     EmployeeName Gus."). A rule whose plan has notes is listed as
     unchecked, not run.
   - `ORMPopulationChecker` runs the rules against its population's store,
     of the document's first mapping or the defaults. Its violations have
     `rule` set.
   - `ormtool check` prints the population's violations and what it did not
     check. It exits with 1 when an alethic constraint or rule is broken.
   - The Company sample has a deontic rule, "Lives near work", that Gus
     breaks. The fixture builder rejects only alethic violations.
4. **Done: calculations computed.**
   - A calculation's plan reads every object of the root's type, with no
     condition, and lists the object and a computed column: an
     `ORMPlanColumn` with a `value`, the bag lookup aggregates use.
   - Both evaluators compute it in rows, and read its bag for each batch,
     as they do a condition's.
   - The `value` function is the one value, and none where there is none or
     more than one.
   - `testCalculationsAreComputed` covers each branch's total salary and
     head's name, and each country's total. A salary two of its employees
     share counts for each.
   - A `Value` calculation is checked as a rule is. `ORMRuleChecker` runs
     its plan with the column counting the values ("distinct"), and each
     object with more than one is a violation ("Staff: Branch 7 has 3
     values."). It is reported in the population check and by
     `ormtool check`.
5. **Done: the designer.**
   - The Queries window has **Kind** (List, Constraint, Calculation),
     **Modality** for a constraint, and the **Function** and **of** node for
     a calculation. Each is an editor change, so it undoes.
   - The query list marks a rule "(rule)" and a calculation "(calculation)".
   - A rule's Results tab says how many violations the sample population
     has. A calculation's lists each object and its value.
   - The list marks a rule or value calculation the sample population breaks:
     "(rule, broken)".
6. **Done: validation code.**
   - `-[ORMQueryInterpreter predicateForPlan:reason:]` gives a plan's
     condition as one predicate needing no store, or says why it cannot.
     A bag's aggregate, a join, or what the interpreter checks in memory
     cannot be one predicate.
   - `ORMValidationGenerator` adds a check to the rule's root entity: the
     predicate, as text, not met by `self`. The check's comment says it is
     checked from that entity only.
   - A rule that is no one predicate is in the notes, with why.
   - `testRulesBecomeValidationCode` covers the predicate parsed back from
     its text, which holds of Gus and of no one else.

## Not here, for later

- **A calculation inside another query's conditions** ("branches whose
  TotalSalary is over a million"). That is a derived fact type, "Branch has
  TotalSalary", which is ConQuer-II's macros and NORMA's derivation rules:
  [DERIVATION.md](DERIVATION.md).
- **The service enforcing constraints** as it writes (ODataKit's service
  hooks).
- **Transition constraints**, about what may change into what. Dataphor has
  them; this does not.
- **Constraints checked at commit,** not only from the root object, so that
  a change anywhere on a rule's join path is seen. **Done** with
  derived-and-stored fact types: the generated `orm_prepareForSave:` brings
  their facts up to date, then checks each rule again for every root a
  change reaches ([DERIVATION.md](DERIVATION.md), step 6). What is left
  here: the same in the OData service, at the end of a change set. Dataphor compiles each
  database constraint into checks on the tables it reads, restricted to
  the rows a change touches. The literature calls this incremental
  integrity checking: Nicolas, "Logic for Improving Integrity Checking in
  Relational Data Bases" (1982); Ceri and Widom, "Deriving Production
  Rules for Constraint Maintenance" (VLDB 1990). Here:
  - **Which rules a save can break:** a rule depends on the entities its
    plan reads. That is the root and every relationship on its join paths,
    which the plan already names.
  - **Which objects to re-check:** follow the inverse relationships from
    each changed object back to the root entity. That is the same walk
    `among` does, where Q5 is said in SQL. Run the rule's plan only for
    those roots, as one more BindJoin-style scope: `nr IN` the affected
    roots.
  - **Where it hooks in:** a context method the generated code adds, called
    before saving, say
    `-[NSManagedObjectContext orm_validateRulesForSave:]`. It reads the
    context's inserted, updated and deleted objects and checks the affected
    roots. Core Data's will-save notification cannot refuse a save, so the
    app calls this in its own save path, as it calls
    `orm_validateConstraints:` today. Deletions matter too: deleting an
    Employee can break a rule about Branches.
  - **The same for the OData service:** at the end of a change set, through
    ODataKit's service hooks, before the transaction commits.
