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

Production code is generated: an app has no ORMKit at run time. For a
joined type, the generated code gets a class of its own, the type's façade
over the member objects:

- `+[PFXCustomer customersInContext:]` lists them, and `+insertInContext:`
  makes one, with a row in the hub and in each inner member.
- Each property reads from and writes to the member that holds it. The
  member row is fetched by correlation once, and kept.
- Setting a property of an outer member with no row makes the row, with the
  correlating values. When the last of its properties is set to nil and it
  has no relationships, the row is deleted.
- Setting a correlating value (a user id changed) sets it on every member
  that has it. `-delete` deletes every row.
- `orm_prepareForSave:` checks what spans members: a mandatory role held by
  an outer member, and uniqueness of the correlating values in each member.

The façade works the same over the SQLite store and over ODataKit's
incremental store, so a client of the OData service updates through the
join too. The service serves each member as its own entity set, as the
store has it.

## Reverse engineering

The importer makes an entity type of each entity, as before, and then
looks for entities that may be one. A candidate pair is two entities each
unique on an attribute of the same name and type (`userId`, or a GUID
`externalUserId`). Unique means the identifier, or an attribute with a
uniqueness constraint. Each candidate is a note of the import.

**Merge Entity Types** makes one entity type of two, given the attributes
they correlate by:
- the second one's correlating fact type is removed;
- the first one's becomes an identifier (alternate unless it is the
  preferred one already);
- every other role the second one played is played by the first one;
- the second one is removed;
- in each mapping, the first one maps as Joined, with its own entity as
  the hub and the second one's as an outer member that holds the second
  one's roles, under its old name.

The mapping then writes back the same entities: merging changes the
conceptual model, not the store. The designer has the command for two
selected entity types. It asks for the correlating attributes and lists
the import's candidates.

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
