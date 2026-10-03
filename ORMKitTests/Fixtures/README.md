# Fixtures

- `StockMate.orm`, `StockMate.CoRef.orm`: written by NORMA itself, from the
  PnP.StockMate schema project. They are the reference for what NORMA
  writes: the tests require them to round-trip byte for byte and to
  normalize to themselves, and check ORMKit's derived data against NORMA's.
  `StockMate.CoRef.orm` has no `ORM2` root wrapper and no diagrams.
- `ActiveFacts/*.orm`: Clifford Heath's examples
  (<https://github.com/cjheath/activefacts-examples>, commit 49b397c, MIT
  licensed: `ActiveFacts/LICENSE.txt`), written by NORMA builds of 2008 to
  2015. Authoritative like StockMate, for the NORMA that wrote them: the
  tests require each to round-trip byte for byte, to normalize to itself,
  to agree with ORMKit's derived data, and to map to a Core Data model
  `momc` accepts. Objectification, subtyping several ways, rings, join
  paths, a derivation rule, sample populations, a 187-fact-type metamodel.
  `ActiveFacts/sql/` holds the SQL Server tables ActiveFacts made of them
  (same repository, same license): what Rmap makes, for the mapping's Rmap
  mode to be checked against.
- `NORMA/`: files from NORMA's own repository
  (<https://github.com/ormsolutions/NORMA>, commit c458441), unchanged,
  under the Common Public License 1.0 (`NORMA/LICENSE.txt`, `NORMA/CPL.txt`).
  Only data files are taken; none of NORMA's code is in ORMKit.
  - `GenerationSamples/`, `Documentation/`: NORMA's sample models (with
    their `.CoRef` exports) and metamodels, including OIAL. They read,
    round-trip and normalize to themselves, except `SampleModel.CoRef.orm`
    (an export whose PlayedRoles name roles it left out, which normalizing
    rightly removes) and `OIAL.orm` (multiplicities on binaries without
    uniqueness that NORMA no longer gives).
  - `TestSample/`: NORMA's test suites as NORMA builds of 2006 and 2007
    wrote them: for each test the model it loads (`.Load.orm`), the model
    the test leaves (`.Compare.orm`), and the model errors NORMA reported
    (`.Report.xml`), for model validation to be checked against. They read
    and round-trip byte for byte; their derived data is in forms NORMA has
    since dropped, so they are not normalized. The tests in the 2006-01
    pre-release schema are left out.
- `PreventiveMaintenance.orm`: written by another tool in NORMA's format (no
  byte-order mark, no indentation). Readable, but not authoritative about
  NORMA's derived data; the tests map it to Core Data and verbalize it.
- `WorkMate.orm`: written by ORMKit. Reverse-engineered from the WorkMate
  project's SQL Server schema (13 tables) by `Tools/fixtures/workmate.m`,
  which builds it through ORMEditor: reference modes, unaries for bit
  columns, external uniqueness for composite unique indexes, a value
  constraint for a check constraint, an acyclic ring, role names, hyphen
  binding, three diagrams laid out by `arrangeDiagram:`. Not NORMA's, so not
  a reference for NORMA's layout; the tests check ORMKit reads its own files
  back unchanged, and map and verbalize it.
