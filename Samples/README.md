# Samples

ORM2 models to open in ORMDesigner and query: our own models of the
schemas Terry Halpin's papers publish, with the papers' conceptual queries.
The schemas are the papers'; the files, their layout and their wording are
ORMKit's. `Tools/fixtures/halpin.m` builds them through ORMEditor and lays
each diagram out with `arrangeDiagram:`. Rebuild them after changing it, not
by hand.

- `Company.orm`, after Halpin, "Conceptual Queries" (1998), figure 1:
  employees, branches, cities, cars, languages. It adds the "owns" fact type,
  which ConQuer-II's Q5 asks about. Queries:
  - Q1 to Q5: the papers' queries.
  - Payroll: a total over a branch's employees.
  - Polyglots: a count.
- `University.orm`, after Bloesch and Halpin, "Conceptual Queries using
  ConQuer-II" (ER '97), figure 2: academics, professors and chairs, and
  degrees awarded by universities. Queries Q1 to Q3 are the paper's. Q3's
  `maybe` with a condition is not yet planned as the paper means it
  ([docs/QUERIES.md](../docs/QUERIES.md)).
- `UMLandORM.orm`, after Halpin and Bloesch, "Data modeling in UML and ORM:
  a comparison" (Journal of Database Management, 1999), one diagram per
  figure:
  - Writing (figure 1): an objectified fact type.
  - Room usage (figures 3 and 4): a ternary.
  - Students (figure 5): subset constraints.
  - Title and sex (figure 7).
  - Accounts (figure 8): co-reference. Figure 8's Person is called Customer
    here, since Person is already used by figure 1.

  Its queries are not the paper's:
  - Rooms lacking a facility: what the join-subset constraint of figures 3
    and 4 forbids.
  - Coauthored papers.

## Trying one

1. In ORMDesigner, choose **File ▸ Open Sample ▸ Company**. It opens as an
   untitled copy, so the sample itself stays unchanged.
2. Choose **Query ▸ Queries…** and pick Q2. The outline is ConQuer's. The
   tabs show the query in FORML, as an OData request, and as the plan with
   the Core Data fetches that run it.
3. To build a query of your own, select Employee on the diagram and choose
   **Query ▸ New Query from Selection**. Then:
   - Double-click "lives in City" in the list of fact types to add that
     step.
   - Pick City in the outline and add "is in State".
   - Tick what to list, set a condition, or change a step to `not`,
     `maybe` or a count.

   [docs/QUERIES.md](../docs/QUERIES.md) has the rest.

Clifford Heath's ActiveFacts models (MIT licensed) are under **File ▸ Open Sample ▸ ActiveFacts**.

## Not included

Figures 4 and 7's join-subset constraints are not drawn, because ORMKit
cannot yet author constraint join paths. Each is written instead as a
definition on the object type it constrains.
