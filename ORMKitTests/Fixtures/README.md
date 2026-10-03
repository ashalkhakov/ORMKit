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
