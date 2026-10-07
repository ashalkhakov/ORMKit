# Joined entities: one entity type, several tables

Several processes often keep facts about the same thing, each in its own
table: a CRM's customers by user id, billing's accounts by the same user
id, a newsletter's subscribers by an external user id (a GUID). The thing
is one entity type, Customer, and the tables are how it is stored. Dataphor's
D4 says so directly: Customer = CRMCustomer join BillingAccount join
Subscriber, each join inner or outer on what correlates them. Updates go
through the join to the tables.

ORMKit keeps that distinction:
- The conceptual model has one entity type. It is identified by its
  preferred identifier (user id), and the GUID is an alternate one.
- The Core Data mapping says the entity type is a **join** of several
  entities, its *members*.

Queries, the sample population, generated code and reverse engineering all
take the join from the mapping.

## In the mapping

The type maps `As="Joined"`, and its members are listed under it:

```xml
<ormcd:ObjectTypeMapping ref="_Customer" As="Joined">
  <ormcd:Member id="_m1" Name="CRMCustomer" By="_UserId's uniqueness" />
  <ormcd:Member id="_m2" Name="BillingAccount" By="_UserId's uniqueness" Outer="true">
    <ormcd:Holds ref="_role" />
  </ormcd:Member>
  <ormcd:Member id="_m3" Name="Subscriber" By="_Guid's uniqueness" Via="_m1" Outer="true">
    <ormcd:Holds ref="_role" />
  </ormcd:Member>
</ormcd:ObjectTypeMapping>
```

- **The first member is the hub.** It is inner: every instance has a row
  there. A node of the type reads it, and the type's facts that no member
  holds are kept there.
- **`By`** is the identifier a member correlates by: the preferred
  identifier, or an alternate one. An alternate identifier is a uniqueness
  constraint over the far roles of the type's one-to-one fact types, as
  Customer has Guid. The member has that identifier's attributes.
- **`Via`** is the member it joins to, the hub when not given. That member
  must have the identifier too, either because it correlates by it or
  because it holds its fact types. Subscriber joins CRMCustomer by Guid
  because CRMCustomer keeps the Guid; nothing need keep both ids
  everywhere.
- **`Outer`**: not every instance has a row. An inner member's row exists
  for each instance.
- **`Holds`**: the properties the member has, by their traces: a binary
  fact type's far role (the role played by the other end), a unary's
  implicit role, `fact id.role id` for the inverse of an n-ary or
  objectified fact type's relationship. What no member holds is the
  hub's.

## In the Core Data model

Each member is an entity. The hub's source is the type's id, and each
other member's is its own id. A member's copy of a correlating attribute is
traced `member id/role id`, so a source is still on one entity. Members have
no relationships to each other: the tables never had them. An existing
store is read as it is.

The mapping notes what it cannot make:
- a `By` that is not an identifier of the type;
- a `Via` that does not have the identifier;
- a mandatory role held by an outer member, which makes the member inner
  in effect: it is noted and treated as inner.

## Queries

A node of the type is at the hub. A step to a property another member
holds goes first to that member's row, by its correlation. The plan does
this with a join that binds the matched row, where the join through an
absorbed type only checks that a row exists:

```
let member1 = read BillingAccount
read CRMCustomer
where some x1 in member1 with userId = userId has x1.balance > 100
list self (userId), x1.balance
```

- A step is *some* row; under maybe, *maybe*, the row or none; under not,
  no row. An outer member is no different: the step asks for its row.
- A member reached via another goes through that one first: one join for
  each hop (the hub, then Subscriber by Guid).
- A node of the type reached at a member, the destination of a
  relationship (Topic's subscribers), goes back to the hub first. Its
  steps go from there, as any node of the type's do.
- `ORMPlanMatches` has a `boundVariable`, its `operand` asked of the row,
  and `isOptional`. The interpreter reads the member's rows for each batch
  of the objects read, where the join's values are theirs, or probes for
  each object. The OData backend reads them for each page as it reads a
  correlated join's, with what the condition and the columns read of them,
  and binds them as it makes the rows.
- A query is not sorted by a member's value: no fetch of the hub sorts by
  it. The plan says so in a note.

## The sample population

The population store writes each instance into the hub, into each inner
member, and into each outer member it has a fact for there (with the
members it joins through). A relationship to the type whose destination is
a member (Topic's customers) is to the instance's row there. Each row gets
its correlating values from the row it joins to, once the facts are
placed. The deriver and the checker read rows back through the hub, as a
query does.

## Updates through the join

An app has none of ORMKit at run time, only ORMRuntime and the model's
tables ([RUNTIME.md](RUNTIME.md)). For each joined type, the validation
files (`<Name>Validation.h/.m`, ORMJoinedFacade) declare a class, the
type's façade over the member objects, on ORMRuntime's `ORMJoinedObject`.
Its properties are `@dynamic`: `ORMJoinedObject` reads where each is
kept from the type's table, `joined` in `<Name>.ormplans`, which is also
what `orm_prepareForSave:` runs for the type.

```objc
Customer *ann = [Customer insertInContext:context];
ann.userId = @1;           // the hub's (CRMCustomer)
ann.balance = @50;         // BillingAccount's: its row made, joined by userId
ann.balance = nil;         // and deleted, as it keeps nothing else
```

- `+allInContext:` lists them, one for each of the hub's objects;
  `+insertInContext:` makes one; `-object` is the hub's object;
  `-rowIn:` is its row in a member; `-delete` deletes every row.
- Each property reads from and writes to the member that holds it. The
  row is found by what joins it: a fetch, pending changes included.
- Setting a value with no row there makes the row, with the values that
  join it, and the rows it joins through. A value that makes the row
  empty (nil, or an empty set), where no other member joins to it,
  deletes an outer member's row.
- Setting a value the members are joined by (a user id, a GUID) sets it
  on every row joined by it, down the via chain. Setting it to nil lets go
  of those rows: each is deleted, with the rows joined through it, as it
  is no longer the instance's.
- A value set in a member before the values that join it (a balance
  before the user id) has no row to go to: the setter raises
  `NSInternalInconsistencyException`, as a programming error. Set the
  values it is joined by first.
- `orm_prepareForSave:` covers hub objects changed without the class:
  - an inserted one gets its inner members' rows (a violation where it has
    no value to join them by);
  - a deleted one's rows are deleted, found by its values before the
    change and by those it had when deleted;
  - an updated one's rows, found by its values before the change, are
    joined again, or let go of where a value joining them is now nil.
- What the hook cannot see, it leaves:
  - a hub object inserted and deleted before the save is in none of the
    context's sets: rows made for it through the class stay. `-delete`
    deletes them;
  - a hub object re-keyed twice before a save, first through the class
    and then without it: its rows have the value in between, which
    neither the hub's saved values nor its current ones find. Re-key
    through the class, or save in between.
- A correlating value is unique in each member: the mapper gives the
  member a uniqueness constraint on it, which Core Data checks. A
  mandatory role held by an outer member makes it inner (the mapper says
  so).

The code is the same over the SQLite store and over ODataKit's
incremental store, so a client of the OData service updates through the
join too. The service serves each member as its own entity set, as the
store has it, keyed by its correlating values.

## Reverse engineering

The importer makes an entity type of each entity, as before. It then
notes the pairs that may be one (`ORMEntityMerger -candidates`): two
entity types, neither a subtype or supertype, each with a one-to-one fact
type of a value with the same name and data type. The name is a popular
reference mode's mode (`userId`), or the value type's name (`Guid`). The
kept one of a pair is the one whose value identifies it, where only one
does.

**Merge Entity Types** (`-merge:into:matching:with:reason:`) makes one
entity type of two, as one change, given the value roles they match by:
- the absorbed one's fact type of the value goes, with its value type
  where nothing else plays it;
- the kept one's becomes an identifier (alternate, unless it is the
  preferred one);
- the absorbed one's reference mode, where it is another value, becomes a
  plain fact type;
- every other role the absorbed one played is the kept one's. A mandatory
  one is no longer mandatory, since not every one of the kept type has a
  row there; the member says its rows have it (`Holds Required="true"`);
- the absorbed one goes;
- in each mapping, the kept one maps as Joined. Its entity is the hub, and
  the absorbed one's is an outer member under its old name, holding its
  old properties under their old names. It joins to the member that
  holds the kept one's value, where an earlier merge put it there (a GUID
  that came with billing's accounts), else to the hub. Its value's attribute keeps its
  old name and optionality (`OptionalBy="true"` where rows need not have
  it, as a table read back may).

The mapping then writes back the entities it was read from: merging
changes the conceptual model, not the store. Refused, with the reason:
two types that are not plain entity types, values of different data
types, a fact type that is not one to one, an absorbed type identified by
several fact types.

## In the designer

- **Model > Merge Entity Types**, with two entity types selected, merges
  them by a value both have one to one: the model's candidate where there
  is one, else any pair of such values of one data type. With several, an
  alert asks which; the status line says what became of the absorbed one.
- In the Core Data window, an object type's mapping can be **Joined**.
  Choosing it for a type that has no members makes its entity the hub;
  for one mapped otherwise since, it brings back the members it had.
  Selecting a joined type says where it is kept, naming the value types
  each member is correlated by: "CRMCustomer is kept in CRMCustomer;
  BillingAccount (outer, by CRMCustomer_userId)" for the types an import
  made.

## Steps

1. The mapping: `ORMMapJoined`, members read and written, and
   `ORMMappingEditor` to set them.
2. The mapper: member entities, correlating attributes, held properties,
   traces, notes.
3. Plans: the binding join, in the interpreter and the OData backend. The
   planner joins members.
4. The population store writes members.
5. Generated code: the façade, and the checks across members at save.
6. Reverse engineering: candidates, and Merge Entity Types in ORMKit.
7. The designer: the merge command, and the members in the mapping
   inspector.

## Not here, for later

- Members that correlate by an identifier the hub does not have, and that
  no `Via` chain reaches.
- A join on something other than an identifier, e.g. a date range.
- A member that is a subtype's table (a subtype is its own entity type
  already).
