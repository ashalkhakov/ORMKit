# Sample populations

A sample population is a model's example facts: Ann (Person 1) was born in
Australia. NORMA keeps one in the `.orm` file, and so does ORMKit, in NORMA's
format. Conceptual queries ([QUERIES.md](QUERIES.md)) run against it: it is
put in a Core Data store of the mapping, and the query interpreter reads that
store as it would an application's.

## As NORMA keeps it

- **Instances.**
  - A value type's instances are `ValueTypeInstance`s with their `Value`.
    Numbers and moments also get an `InvariantValue`.
  - An entity type's instances are `EntityTypeInstance`s, identified by the
    instances that play its preferred identifier's roles: its reference
    mode's value, or the parts of a composite identifier.
  - A subtype's instances are `EntityTypeSubtypeInstance`s, each pointing at
    the supertype instance it is.
  - An objectifying type's instances point at the fact they are
    (`ObjectifiedInstance`).
- **Facts.** A `FactTypeInstance` comes after everything else its fact type
  has. Each instance playing a role is a role instance under that role, and
  a fact or an entity instance refers to those role instances. A unary's
  fact also plays its implicit boolean role with the value "True".
- **Identifying facts.** The facts that identify an entity instance, such as
  "Person has Person_id", have no `FactTypeInstance` of their own: they are
  the instance's identity.

`ORMModel` reads all of this (`ORMInstance`, `ORMFactInstance`, in
`ORMPath.h`), and `ORMEditor` writes it:

| | |
| --- | --- |
| `ORMSamplePopulation` | instances and facts to add: values, entities by what identifies them, subtype and objectifying instances, facts by the instance playing each role |
| `ORMPopulationEditor` | adds a sample population as one undoable change, reusing the values and identities the model has; removes the whole population |
| `ORMPopulationChecker` | what a population breaks, constraint by constraint |
| `ORMPopulationGenerator` | a population made up to meet the constraints |
| `ORMPopulationStore` | the population as Core Data objects, in a temporary store of the mapping |

A file with a population still round-trips byte for byte, and normalizes
to itself.

## Checking

`ORMPopulationChecker` reports what NORMA would report about a population:
- a fact that lacks a role's player;
- uniqueness, internal and external (external over binaries joined on the
  instance they are about);
- simple and disjunctive mandatory constraints, which apply to entity
  types;
- frequency;
- every kind of ring constraint;
- subset, equality and exclusion between sequences that are each in one
  fact type;
- values outside a value constraint, the type's own or a role's;
- an objectified fact without its objectifying instance.

It also runs the model's constraint queries against the population, in a
store of the document's first mapping, each row a violation
([RULES.md](RULES.md)). The generator knows nothing of them: a generated
population meets the graphical constraints, not necessarily the rules.

The structural constraints of subtype and link fact types are not checked.
Value comparisons, and sequences that span fact types, are listed as
unchecked.

## Making one up

`ORMPopulationGenerator` makes the same population each time for the same
model:

1. **Values.** Values come from a value constraint where there is one.
   Otherwise they come from the data type: numbers counted up, days,
   UUIDs, "Name 1", within the type's length.
2. **Entity instances.** Each entity type with an identifier gets `size`
   instances, 5 by default, or fewer when its identifying values run out.
   Types are made after the types that identify them. A subtype takes a
   share of its supertype's instances, and sibling subtypes take shares
   that don't overlap.
3. **Facts.** Facts are added one at a time, and each is kept only if it
   keeps the uniqueness (internal and external), frequency, ring, subset
   and exclusion constraints:
   1. so that every instance plays its mandatory roles;
   2. then more, leaving some optional roles unplayed.

   A fact type is filled after the fact types its facts must be a subset
   of, and after the objectified fact types its players are. An
   objectified fact type's facts each get an objectifying instance.
4. **Repairs.** Disjunctive mandatory constraints are then covered, and
   facts outside a subset or equality are trimmed.

What it cannot make keep a constraint is in its `notes`. Every model it is
tested on gets a population that is written, read back and put in a store,
and most break nothing: the samples, StockMate, WorkMate, and 24 of the 29
ActiveFacts models. The rest are listed under [Not done yet](#not-done-yet).

## In a store

`ORMPopulationStore` builds the mapping's model in memory and puts the
population in a SQLite store of it, in a temporary file removed when the
store is closed. It finds each fact's place by the traces the mapping leaves
([COREDATA-MAPPING.md](COREDATA-MAPPING.md#traces)).

The store is SQLite, not an in-memory store, because of key paths through
more than one to-many relationship. SQLite flattens them as the
interpreter's plans mean it; an in-memory store compares nested sets, and
some queries silently find the wrong rows.

- **Objects.** Each entity instance is one object of its most specific
  type's entity, and a supertype's instance and its subtypes' are the same
  object. An objectifying type the mapping folds into a player is that
  player's object.
- **Facts.** A fact is set where the mapping keeps it:
  - an attribute or relationship of a player's entity;
  - an object of the fact type's own entity (an objectified fact's is its
    objectifying instance's object);
  - the attributes an absorbed object type's parts became, followed role by
    role from the instance playing it.
- **Values.** Values are converted to the attribute's type in the store.
- **Optionality.** A sample need not be complete, so every property is
  optional in the store's model and nothing is unique there. Checking is
  the checker's job.

What the store does not hold, such as a fact the mapping keeps nowhere or a
value its attribute cannot take, is in `notes`.

The company of Halpin's "Conceptual Queries", written as a sample
population, answers the paper's queries with the same rows as the store the
query tests build by hand. Each sample in [Samples/](../Samples/README.md)
has a population, and the tests check what each of its queries finds.

## In the designer

- **Query ▸ Make Up a Sample Population** replaces the model's population
  with a made-up one, as one change that can be undone. So does the Results
  tab's button.
- **The Results tab** in the Queries window runs the query against the
  population: the first 200 rows, a column for each node the query lists.
  Below the rows it says how many there are and what the store left out.

A query whose conditions name values (Q1's branch 52) finds nothing in a
made-up population whose branches are numbered 1 to 5. That is the right
answer, not a fault.

## Editing by hand

The designer's Population tab, under the canvas, shows the selected fact
type's or object type's population as a table, a column for each role
([WINDOW.md](WINDOW.md)). `ORMPopulationEditor` makes each edit one change:
- `addFactOf:named:` adds a fact, its players named as the table shows them:
  - a value type's value;
  - an entity type's reference mode value, the instance so identified
    found or made;
  - an entity type identified by several values: those values, in its
    preferred identifier's order and separated by commas, as in `1, 101`.
    A part that is itself named this way goes in parentheses, as in
    `(1, 101), 3`, and a value with a comma, parenthesis or quote goes in
    quotes, as in `'A, east'`. `nameOf:` writes this form and the editor
    reads it back;
  - a subtype's, through its supertype.
- `setPlayer:ofRole:inFact:` names a player anew, replacing the fact.
- `renameInstance:to:` (and `role:to:`, for one part) renames an instance:
  - a value in place;
  - an entity by the value or values identifying it. The instance keeps its
    facts and is identified by the new value, found or made. A value that
    then identifies nothing is removed.
- **What the model has already is refused, with why.** This covers an
  instance named as one it has ("There is already a Person 1."), a fact
  with the same players, a player edit that makes a fact another's twin,
  and a rename to another instance's name. A refused new row stays, as
  typed, to be put right or removed.
- `removeFact:` removes a fact. It is refused while an objectifying instance
  is that fact.
- `addInstanceOf:named:` and `removeInstance:` add and remove an object
  type's instances. For a type identified by several values, the table has
  a column for each (`compositeRolesOf:`), and `addInstanceOf:namedByRole:`
  adds the row once each is named. Removal is refused while the instance plays in a fact or
  identifies another.

## Derived fact types

A fact type a query derives ([DERIVATION.md](DERIVATION.md)) has its facts
worked out from the rest of the population (`ORMDeriver`).
- The checker checks constraints on them as on asserted facts. It reports an
  asserted fact of a fully derived fact type, and stored facts the rule no
  longer agrees with.
- A stored one's facts are written into the population: each edit of the
  population brings them up to date in the same change
  (`bringStoredDerivationsUpToDate:`), and so does making up a population.
- An objectifying type its fact identifies (CinemaTickets' Session) has
  its fact's table in the Population tab: each row is a fact of the fact
  type it objectifies, and its instance. A row added adds both.
- An objectifying type with an identifier of its own (Orienteering's Entry,
  by its ID) is added with the fact it objectifies, both at once
  (`-addInstanceOf:named:objectifying:reason:`): each is the other, so
  either alone is refused. Its Population tab has the identifier's columns,
  then a column for each role of the fact; changing a fact's player there
  is refused (remove the row and add it again).
- A unary fact NORMA keeps on its player, an `EntityTypeUnaryRoleInstance`
  under the instance, is read as a fact of the unary fact type.
- The Population tab shows a derived fact type's facts, read only, after any
  asserted ones; a fully derived one takes none by hand.

The generator sizes and shapes the population for what must be played:
- a type with a role that every instance of another type must play with it
  (each Company run by a CEO) has at least as many instances as that type.
  A supertype has enough for each subtype's share to have that many;
- a type whose roles are exclusive (each Content the text of a Comment or of
  a Paragraph, not both) has one for each partner of each;
- an instance that ends up playing nothing, where it must play one of
  several roles, is left out;
- the facts that identify instances (an Employee by the Company it works for
  and its number) count for the subset constraints on others ("CEO runs
  Company" only where the CEO works for it);
- a transitive ring is kept by making no chains of two;
- a symmetric ring across two types (Girl going out with Boy) is kept by
  making no facts, where none are mandatory.

## Not done yet

- **The generator's limits:**
  - a fact whose players must agree with several other fact types at once
    (Diplomacy's ambassadors, from the country they represent to the one
    they serve in, one for each pair) is looked for among a few hundred
    candidates, not worked out from those facts;
  - sibling subtypes' shares are each a fixed part of the supertype's
    instances, grown for what one subtype needs but not balanced among
    several (the ActiveFacts Metamodel's eight kinds of Shape);
  - external uniqueness over more than binaries;
  - value comparisons;
  - derived fact types, which it leaves out.
- **Unary facts kept on their player** (`EntityTypeUnaryRoleInstance`, as
  newer NORMA versions write them) are read, but not written or removed
  one by one: ORMKit writes a unary fact as a fact instance.
- **The checker's limits:** value comparisons, and sequences that need a
  join path.
- **Populations in OData:** posting a population to a running ODataKit
  service, so the OData request can be tried against it as well.
