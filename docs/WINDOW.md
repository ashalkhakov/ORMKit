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
2. **Issues and Search.**
3. **Alignment:** `-[ORMDiagramEditor alignShapes:how:]` and
   `distributeShapes:`, and their buttons.
4. **The lower tabs:**
   - Verbalization and Fact entry as tabs, the page popup alone.
   - Population, with `ORMPopulationEditor` editing single facts and values.
     Today it replaces a whole population at once.

Then **paths by clicking role boxes** on the canvas, for the Queries window:
see [QUERIES.md](QUERIES.md).
