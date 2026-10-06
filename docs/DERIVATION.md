# Derived fact types: queries that say what is so

A fact type is *derived* when its facts follow from others: "Person is a
grandparent of Person" from "Person is a parent of Person", taken twice.
Halpin marks one with an asterisk, and NORMA keeps its rule. Before this
work, ORMKit read NORMA's rule and verbalized it, but nothing ran it: a
query could not go through a derived fact type, the population checker
ignored one, and the Core Data mapping stored it like any other.

A conceptual query ([QUERIES.md](QUERIES.md)) is the rule. After the
constraints and calculations of [RULES.md](RULES.md), a query can be a
**derivation**: its rows are the facts of a fact type.

## The kinds

NORMA has two settings, and ORMKit keeps both:

- **Completeness:**
  - *Fully derived* (`*`): every fact is derived, and none is asserted.
  - *Partly derived* (`+`): the facts are those asserted, and those derived.
- **Storage:**
  - *Derived* (computed when asked): the facts are worked out wherever they
    are needed.
  - *Derived and stored* (`**`): the facts are worked out when the facts
    they follow from change, and kept. They are read like asserted ones.

Storage is a matter of implementation, but it is the modeller's to choose.
The rule is the same either way, and so is what a query through the fact
type answers.

## In the file

A derivation is a query of its own kind, naming the fact type it derives:

```xml
<ormq:Query id="_q3" Name="Grandparenthood" Kind="Derivation" Of="_isGrandparentOf">
  <ormq:Node id="_gp" ref="_Person"> ...          <!-- as any query -->
</ormq:Query>
```

- `Of` is the derived fact type. Its listed columns are the fact type's
  roles, in the fact type's order. Each column's object type is its role's
  player, and there is one column for each role the reading shows.
- The fact type says it is derived as NORMA says it, so that NORMA reads
  the model the same way:
  - a `DerivationRule`, fully derived and not stored unless the inspector
    says otherwise (NORMA leaves its defaults out:
    `DerivationCompleteness`, `DerivationStorage`);
  - an `InformalRule`, the query's verbalization. NORMA shows it as the
    rule, and keeps it.
- A fact type has at most one derivation. Removing the query leaves the
  fact type asserted, with no rule. A fact type with a derivation note of
  its own is not given a query: the query's words would replace the note.

NORMA's own rules, role paths with projections, are read as queries
(step 8), so both kinds run. Such a query is not in the document. NORMA's
rule stays the authority, and the designer shows it as NORMA's. A rule
reads as one when it is plain:
- one path, with no split, calculation or condition;
- no negation, value condition, correlation or outer join;
- one projected point for each role.

The path's root is the root node. Each role it joins by is a step from the
node the path is at, with a node for each of the fact type's other roles,
and the role it goes on by is where the path then is. The projected nodes
say which role each is (`For`): a projection need not be in outline order.
A hop through a link fact type is a step through it, whichever way NORMA
names it. CinemaTickets names the role the proxy stands for; WaiterTips
joins by the objectified role and goes on by the link fact type's.
Anything else is refused, with a note that says why.

## What they mean

A derivation's query plans as a list does. Its rows are the derived facts,
one for each distinct row; a row with a column missing derives nothing.

- **Fully derived:** asserted facts are an error, as NORMA has it. The
  checker says so, and the Population tab shows the derived facts read-only.
- **Partly derived:** asserted facts, and derived ones beside them. The table
  edits the asserted facts and shows the derived ones marked.
- **Derived and stored:** in a store, the facts are kept, as asserted ones
  are. They are written by the derivation when the facts it reads change:
  - in a sample population, ORMKit writes them, after a change and when
    making one up;
  - in a Core Data store, at save (below).

## Planning through one

A step through a derived fact type that is not stored has nothing in the
store to follow. Halpin calls derived fact types macros, and that is how
they are planned: before planning, the step is put as its derivation's
path (`-[ORMQuery expandedInModel:notes:]`), and what is left is an
ordinary query. Everything the planner and both backends do then holds:
columns past the step, sorting, not and maybe, OData.

- **"Employee reports to Employee"** derived as "Employee works for Branch
  that is headed by Employee": a step from an Employee through it to the
  one they report to becomes the two steps through Branch.
- **From the other role,** the derivation is turned around first: re-rooted
  at the column for the role the step enters by, each step on the way
  reversed ("Employee heads Branch that employs Employee").
- **The step's nodes** are the derivation's columns for the other roles,
  with what the query says of them and what the rule says, and their own
  steps go on from there. Where the query labels a node the rule labels
  too, the rule's nodes of that label take the query's. The derivation's
  other nodes are its own: fresh ids, its labels apart from the query's,
  and a label only one of its nodes has is dropped.
- **Not, maybe, a count** on the step go to the first step of the path.

Refused, with a note, and not run:
- a path that is not plain binary steps where it has to be turned around,
  or one that branches where the step has not, maybe or a count;
- a fact type NORMA derives by a rule that is not plain (above), or by
  its note alone;
- steps that meet with or on one side and not the other, where the side
  with or would take more than one: "A or (b and c)" has no way to be
  said yet;
- a derivation through itself, which ConQuer has no fixpoint for. Past 16
  rounds of expansion a query is taken to be one.

## Core Data, and keeping stored ones up to date

- **Derived, not stored:** nothing in the Core Data model. The mapping says
  so in a note, and queries derive it (above). The validation code leaves
  out constraints over it, with a note.
- **Derived and stored:** mapped as now, as attributes and relationships,
  and kept up to date when changes are saved.

**Saving is one step: derive, then check.** The stored facts are brought up
to date first, and the rules across fact types are checked after, against
the result. This is the commit-time check [RULES.md](RULES.md) plans,
extended: a rule can read a stored derived fact type, so the facts must be
right before the rules run. One hook does both, in the generated code:
`-[NSManagedObjectContext orm_prepareForSave:]`, called by the app before
`save:`, as `orm_validateConstraints:` is today (Core Data's will-save
notification cannot refuse a save). It works as follows:

1. **What a change can affect.** A derivation depends on the entities its
   plan reads: its root, and every relationship on its join paths. From the
   context's inserted, updated and deleted objects, follow the inverse
   relationships back to the root entity, as `among` does. Those roots are
   the ones whose derived facts may have changed. Deletions count too:
   deleting an Employee can change a Branch's head count.
2. **Derive, for those roots only.** Run the derivation's plan with one more
   scope (`nr IN` the affected roots, as a BindJoin's), and compare its rows
   with the stored facts of those roots. Insert the facts that appeared, and
   delete those that went. An attribute is set, and a relationship row is
   made or removed.
3. **In order.** Derivations that read other stored derivations run after
   them, in dependency order. A recursive one is refused (above), so the
   order exists. The objects step 2 changed are changes too, and widen what
   later derivations affect.
4. **Then check the rules** for the roots the changes, the derived ones
   included, can break, as RULES.md describes. If one is broken, the save is
   refused with why, and nothing is saved.

Where Core Data can say the rule itself, it does instead: a key path
through one to-one relationship becomes an `NSDerivedAttributeDescription`
(`city.cityname`). Core Data, and FreeCoreData, compute those at save on
their own. The hook skips them, and rules read their saved values.

The OData service does the same at the end of a change set, through
ODataKit's service hooks, before the transaction commits. Sample
populations do it after each change, all of them at once: every stored
derivation is derived again, round after round, until a round changes
nothing. One that reads another sees, a round later, what that one stored.
That takes the place of the dependency order of step 3.

## The designer

- The inspector of a fact type says whether it is derived (fully or
  partly) and stored, and names its derivation query.
- The Queries window's Kind has **Derivation**, with the fact type it
  derives. Its columns are checked against that fact type's roles as it is
  built.
- On the diagram, the fact type's reading has NORMA's marks: `*`, `**`,
  `+`, `++`.

## Steps

1. **Done: the kind, in the file and the model.** `ORMQueryDerivation`, `Of` a
   fact type, and the editor's setters. `ORMFactType` knows its derivation.
   The fact type's NORMA `DerivationRule` is written with the query: its
   completeness, storage and verbalization. The diagram shows the marks.
2. **Done: verbalization.** "\* Each Person is a grandparent of each Person ...
   derived as follows: ...", and NORMA's wording for partly derived and
   stored ones.
3. **Done: populations.** `ORMDeriver` runs each derivation against a store of
   the population and matches each row's values back to the population's
   instances. The derived facts computed from the sample population:
   the checker checks constraints over them, and reports asserted facts of a
   fully derived fact type. The Population tab shows them. Stored ones are
   written into the sample population, after a change and when making one up.
4. **Done: queries through derived fact types,** expanded into their
   derivations' paths before planning.
5. **Done: Core Data.** Unstored ones are left out, with notes. Stored ones
   are mapped as now, and `NSDerivedAttributeDescription` is used where it
   can say the rule: a key path through one to-one relationship, which is
   as far as Core Data goes ("currently unsupported (too many steps)"
   beyond). Partly derived ones not stored are mapped for their asserted
   facts; queries do not go through them yet (an or of the two).
6. **Done: saving, derive then check.** `-[NSManagedObjectContext
   orm_prepareForSave:]` in the generated code (`ORMValidationGenerator`).
   The derivations are tables, not code ([RUNTIME.md](RUNTIME.md)):
   `<Name>.ormplans`, run by ORMRuntime's `ORMSaveHook`, which the hook
   calls.
   - Each plan says the key paths it reads from its root
     (`-[ORMQueryPlan trailsFromRead]`). The generator turns each into the
     inverse relationships back to the root, and the driver walks those
     from each changed object (inserted, updated, deleted) to the roots it
     can affect.
   - A stored derivation is its plan, from the object the property is of,
     listing that object and what is derived, both as objects. The driver
     asks it of each affected root in memory
     (`-[ORMQueryInterpreter executePlan:ofObjects:inContext:error:]`), so
     unsaved changes count, and sets the property where it differs.
     Conditions, nots and counts on the way are the plan's. One partly
     derived, or one whose plan reads a set it defines, is in the
     generator's notes. One Core Data derives itself (step 5) is left to
     it.
   - Then each constraint query is checked again by the driver
     (`-[ORMSaveHook checkInContext:changed:violations:]`), for every root
     a change, a derived one included, reaches. An alethic violation
     refuses the save.
   - Tested through the driver, on both platforms, and by building the
     generated code with clang and loading it (macOS): a city renamed, its
     branches' employees work in the new name.
   - Apps that cannot generate code ahead of time run the same derivations
     and rules through ORMKit (`ORMDeriver`, `ORMRuleChecker`). The OData
     service's change sets are for later, through ODataKit's hooks.
7. **Done: the designer.** The Queries window's Kind has Derivation, and
   Of then offers the fact types the query's listed nodes play the roles of,
   in order. A derived fact type's inspector says what derives it (the
   query, NORMA's rule or its note), and has Partly Derived and Stored. A
   query's words are its own there: the normalizer keeps them.
8. **Done: NORMA's rules as queries.** A plain role path with projections
   is read as a derivation query (`+[ORMQuery derivationsInModel:]`).
   Expansion, ORMDeriver, the Core Data mapping and the save hook take it
   as they take the document's. A derivation's columns are matched to roles
   by node (`-derivedColumns`, `-[ORMQueryPlan columnOfNode:]`), not by
   place. Queries go through link fact types, so a path from an objectifying
   type reaches its fact's players. ORMDeriver matches a composite
   identifier part by part, an objectified fact's players included.
   CinemaTickets' "Session has Seat" is the test.

## Not here, for later

- Writing a query back as NORMA's role path, so that NORMA runs a
  path-shaped derivation too. NORMA reads the informal rule meanwhile.
- Recursive derivations (a fixpoint).
- Subtype derivation rules ("each Grandparent is a Person who ..."), which
  NORMA keeps the same way. The same query kind would do, with `Of` a
  subtype.
