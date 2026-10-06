# Derived fact types: queries that say what is so

A fact type is *derived* when its facts follow from others: "Person is a
grandparent of Person" from "Person is a parent of Person", taken twice.
Halpin marks one with an asterisk, and NORMA keeps its rule. ORMKit reads
NORMA's rule and verbalizes it, but nothing runs it: a query cannot go
through a derived fact type, the population checker ignores one, and the
Core Data mapping stores it like any other.

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
  - a `DerivationRule` with `DerivationCompleteness` and `DerivationStorage`;
  - an `InformalRule`, the query's verbalization. NORMA shows it as the
    rule, and keeps it.
- A fact type has at most one derivation. Removing the query leaves the
  fact type asserted, with no rule.

NORMA's own rules, role paths with projections, are read as now. Step 8
turns them into queries, so that both kinds run.

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
  steps go on from there. The derivation's other nodes are its own: fresh
  ids, its labels apart from the query's.
- **Not, maybe, a count** on the step go to the first step of the path.

Refused, with a note, and not run:
- a path that is not plain binary steps where it has to be turned around,
  or one that branches where the step has not, maybe or a count;
- a fact type NORMA derives by its own rule (step 8);
- a derivation through itself, which ConQuer has no fixpoint for.

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
populations do it after each change (step 3).

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
   orm_prepareForSave:]` in the generated code (`ORMValidationGenerator`),
   self-contained: plain Objective-C, nothing of ORMKit at run time.
   - Each plan says the key paths it reads from its root
     (`-[ORMQueryPlan trailsFromRead]`). The generator turns each into the
     inverse relationships back to the root, and the hook walks those from
     each changed object (inserted, updated, deleted) to the roots it can
     affect.
   - A stored derivation the generated code can work out is a plain chain
     of steps, to-one or to-many, ending at a value or at objects. It is
     worked out along the chain for each affected root, and set where it
     differs. One with conditions on the way, or partly derived, is in the
     generator's notes. One Core Data derives itself (step 5) is left to
     it.
   - Then each constraint query is checked again, with
     `orm_collectViolations:`, for every root a change, a derived one
     included, reaches. An alethic violation refuses the save.
   - Tested by building the generated code with clang and loading it
     (macOS): a city renamed, its branches' employees work in the new name.
   - Apps that cannot generate code ahead of time run the same derivations
     and rules through ORMKit (`ORMDeriver`, `ORMRuleChecker`). The OData
     service's change sets are for later, through ODataKit's hooks.
7. **The designer:** the inspector, the Queries window's kind, and the
   checks on the derivation's columns.
8. **NORMA's rules as queries:** a role path with projections is read into
   a derivation query, so NORMA's rules run too. For path-shaped queries, the
   role path is written back.

## Not here, for later

- Recursive derivations (a fixpoint).
- Subtype derivation rules ("each Grandparent is a Person who ..."), which
  NORMA keeps the same way. The same query kind would do, with `Of` a
  subtype.
