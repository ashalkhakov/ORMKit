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
  degrees awarded by universities. It adds "Academic has AcademicName",
  which the paper does not have. Queries Q1 to Q3 are the paper's. Q3's
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

## Populations

Each sample has a sample population to run its queries on, kept in the file
as NORMA keeps one ([docs/POPULATIONS.md](../docs/POPULATIONS.md)). Each
keeps its model's constraints. The queries list a name beside each employee
or academic, and a facility's name beside its code, where the papers list
only the identifiers. That makes a row easy to check against the data.

- **Company:** seven employees in four cities of three countries, four
  branches (two of them US branches), three cars, two languages. The papers
  give no data; this is the company ORMKit's query tests ask about, made so
  that each query finds something:

  | Query | finds |
  | --- | --- |
  | Q1 | employees 1 and 3 |
  | Q2 | employees 1, 3 and 4 |
  | Q3 | US branch 102 |
  | Q4 | employee 2 (Bea), who supervises employee 10 (Fay) |
  | Q5 | employees 1 and 4 |
  | Payroll | branches 52 and 7 |
  | Polyglots | employee 1 |

  Its Core Data mapping keeps City an entity of its own. Under the default
  mapping City is absorbed into Employee and Branch as its name, state and
  country, and Q4 compares two employees' cities part by part instead; it
  finds the same employee.
- **University:** five academics, two of them professors, with degrees from
  UQ, MIT and ANU. Also ours:
  - Q1 finds academics 430 (Cara Diaz), 715 (Ana Lima) and 720 (Ben Cho);
  - Q2 finds 720 (Ben Cho), who holds the Informatics chair and has no
    degree from UQ;
  - Q3 lists all five.
- **UMLandORM:**
  - **Figures 4 and 7:** the paper's own populations. Rooms 10, 20 and 33,
    their facilities, and who uses them when; and which titles determine
    which sex. "Rooms lacking a facility" finds none, since the paper's data
    keeps the join-subset constraint that query is about.
  - **Writing:** a few writings of our own. "Coauthored papers" finds paper
    1, written by Terry and Anthony.

To try a query on the population, open the Queries window's **Results**
tab, or run `ormtool query Samples/Company.orm Q4`, which prints every stage
from the outline to the rows. **Make Up a Population** replaces the population with one generated
to meet the constraints, and undoing brings the sample's back.

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

The menu also lists StockMate, a warehouse stock model that NORMA wrote
(`ORMKitTests/Fixtures/StockMate.orm`), bundled with its author's leave.
Clifford Heath's ActiveFacts models (MIT licensed) are under **File ▸ Open
Sample ▸ ActiveFacts**.

## Not included

Figures 4 and 7's join-subset constraints are not drawn, because ORMKit
cannot yet author constraint join paths. Each is written instead as a
definition on the object type it constrains.
