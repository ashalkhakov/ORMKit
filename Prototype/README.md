# NativeORM

Editable **Object-Role Modeling (ORM2)** diagrams drawn by a native
Objective-C + ARC AppKit program. Cocoa and GNUstep. No PlantUML, no NORMA, no Java.

## Notation (what the view draws)

| Mark | Meaning |
| --- | --- |
| Solid ellipse | entity type  (`Note(.id)`) |
| Dashed ellipse | value type (`Title`) |
| `(.ref)` | reference mode |
| `!` | independent object type |
| `{…}` under a value type | value constraint |
| Joined boxes | fact type / predicate (unary, binary, ternary) |
| Reading under the boxes | `… has …`  or a name such as `contains` |
| Bar over a role | internal uniqueness constraint |
| Bar over every role | spanning uniqueness (n-ary key) |
| • on the line at the ellipse | mandatory role |
| `{min..max}` by a role | frequency constraint |
| `ir` / `as` / `ac` / … badge | ring constraint on a fact type |
| Dashed lines to a **U** circle | external uniqueness |
| Dashed lines to **SS** | subset |
| Dashed lines to **=** | equality |
| Dashed lines to **X** | exclusion |
| Thick arrow | subtype → supertype |

## MiniNotes seed

- Entity types: Application, Notebook(.id), Note(.id), Window
- Value types: Title, Body, Instant, NoteId
- Facts: is editing / contains / has / was created at / was modified at / displays / has selected / is tagged with / is archived / is pinned / references
- Constraints: external U (Notebook+Title), exclusion (archived ⊗ pinned), subset (displays ⊆ editing), frequency, irreflexive ring

## Edit

| | |
| --- | --- |
| Move | drag an ellipse or a role-box strip |
| Members | inspector: name, kind, reference mode, constraints |
| UC / mandatory | select a **role box**, tick the two checkboxes |
| Unary / binary / ternary | toolbar, then click object types in reading order |
| Ext U / Exclude | click roles, then **Commit** or Return |
| Subset / Equal | click two roles |
| Ring / Freq | click a fact or role, then use the inspector |
| Subtype | click subtype, then supertype |
| Move a U/SS/=/X mark | drag the circle |
| Delete | select, press Delete |
| Persist | Save → `*.nativorm` |
| Text | **Verbalize** writes the FORML-style fact sentences |

## Build

```bash
./build-cocoa.sh && ./NativeUML
```

GNUstep: `clang -fobjc-arc` + libobjc2, then `make` with the GNUmakefile.
