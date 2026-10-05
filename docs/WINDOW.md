# The document window

How ORMDesigner's document window is laid out, after the redesign asked for
on 2026-10-05, and the steps to get there. It follows RDLDesigner's window
(`../RDLKit/RDLDesigner`), so the two designers look and work alike.

## Layout

```
┌───────────────────────────────────────────────────────────────────────┐
│ align: ⇤ ⇥ ⤒ ⤓ ↔ ↕  distribute: ⋯ ⋮                         − zoom + │  top bar
├──────────────┬──────────────────────────────────────────┬─────────────┤
│ (O)(I)(S)(!) │                                          │             │
│ ──────────── │                 canvas                   │  inspector  │
│  navigator   │                                          │             │
│  tab         ├──────────────────────────────────────────┤             │
│              │ (V)(F)(P)                     [page ▾] + │             │
│              │  Verbalization / Fact entry / Population │             │
└──────────────┴──────────────────────────────────────────┴─────────────┘
```

- **Left: the navigator.** A `DMTabBar` of lettered badges over a tab view
  with no tabs of its own, as RDLDesigner's left pane is. Each tab is an
  `NSView` subclass with its own XIB, installed into a host view.
  - **Outline (O):** the model browser, its filter and + menu, as now.
  - **Insert (I):** everything that can be put on the diagram: entity and
    value types, fact types, subtyping, role connectors, every constraint
    kind, notes.
    - Choosing one arms the canvas's tool, as the toolbar's buttons do now.
      The next click on the canvas places it.
    - Rows can also be dragged onto the canvas, and dropping one places it
      there.
  - **Search (S):** searches the verbalization text, like Xcode's find
    navigator. Hits are grouped by the element whose sentence they are in.
    Choosing one selects that element.
  - **Issues (!):** what is wrong, like Xcode's issue navigator. Choosing an
    issue selects its element on the canvas and in the inspector. It lists:
    - the sample population's violations (`ORMPopulationChecker`),
      graphical constraints and constraint queries alike;
    - the first mapping's notes on what Core Data does not enforce or
      cannot hold (`ORMMappingNote`);
    - readings that do not read.

    It is refreshed after each change, a moment later, as RDLDesigner's
    problems pane is.
- **Top bar:** NORMA's alignment buttons for the shapes selected: align left
  edges, right edges, tops, bottoms, horizontal centres and vertical
  centres; distribute horizontally and vertically. Each is one change,
  undone as one. The zoom buttons stay. The tools leave for Insert.
- **Below the canvas:** a tab bar with the page popup and + on its right.
  The page tabs go, and the popup chooses the page.
  - **Verbalization (V)** and **Fact entry (F)**, as now.
  - **Population (P):** the selected fact type's or object type's
    population as a table, a column a role. Rows can be added and removed,
    and a value edited in place. Each edit is an `ORMPopulationEditor`
    change, so it undoes; the instances a fact names are found or made by
    their identifying values. The checker's violations for that fact type
    show under the table.
- **Right: the inspector,** as now.

## Steps

1. **Done: the navigator.**
   - `DMTabBar` is copied from RDLDesigner (MIT, see
     `ORMDesigner/ThirdParty/README.md`).
   - The window has the navigator's tab view, with the Outline tab holding
     the browser.
   - The Insert palette is `ORMInsertPalette`, with its own XIB.
     - Choosing a row arms the canvas tool, through `-[ORMCanvasView
       useTool:]`.
     - The canvas's tool selects its row.
     - An entity type, value type or note row dragged onto the canvas is
       placed where it is dropped, through `-placeTool:at:`.
   - The toolbar's tool buttons are gone; the menus' tool items stay.
2. **Done: Issues and Search.**
   - `ORMIssueFinder` (ORMKit) lists, errors first:
     - NORMA's basic model errors: no reference scheme, no uniqueness
       constraint, no reading;
     - readings that do not read, as NORMA finds them in a file: placeholders
       that are not the roles', an order that leaves out a role or names
       another fact type's, two fact types read the same way; and, as a
       warning, a reading with no words but its players;
     - the population's violations, its rules too;
     - the first mapping's warnings and what Core Data does not enforce.
   - `ORMIssuesView` shows them, coloured by severity with a count under
     them. They are found again half a second after the last change.
   - `ORMSearchNavigator` searches the verbalization, grouped by element.
   - Choosing an issue or a sentence shows its element, on the page that
     shows it. A rule's id opens the Queries window on that rule.
3. **Done: alignment.**
   - `-[ORMDiagramEditor alignShapes:as:reason:]` lines up the shapes
     selected, each moving with what it carries, as one change:
     - edges to the outermost shape's;
     - centres to the first shape selected;
     - three or more spaced evenly, across or down.
   - The top bar has **Align:** Left, Centre, Right, Top, Middle, Bottom, and
     **Space:** Across, Down.
4. **Done: the lower tabs.**
   - Verbalization, Fact entry and Population are tabs on the bar under the
     canvas, with a `DMTabBar` of V, F and P.
   - The page popup and + stay on the bar's right; the page tabs are gone.
   - "New Fact Type…" opens the Fact entry tab.
   - `ORMPopulationView` is the Population tab, the selection's population
     as a table:
     - + starts a row, which is added once each of its cells is named;
     - editing a fact's cell names that player anew;
     - − removes the selected rows.
   - What it refuses, or the checker's violations for that fact type, show
     under the table. Each edit is one `ORMPopulationEditor` change.

On the canvas, as in NORMA:
- the first click on a fact type's role box selects the fact type, and the
  next click selects the role;
- what is selected is dragged together;
- a drag on nothing draws a band, as the Finder does, and selects what it
  touches; with Shift or Command, it adds to the selection instead;
- Space-drag or a middle-button drag pans the drawing, as in drawing
  programs, and so do the scroll wheel and trackpad. The HIG names no pan
  gesture, and Command-click is its "add to the selection", so Command
  stays that.

Then **paths by clicking role boxes** on the canvas, for the Queries window.
This is done: see **Build from the diagram** in [QUERIES.md](QUERIES.md).
