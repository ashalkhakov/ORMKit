# ORMKit

Object-Role Modeling (ORM2) for GNUstep and Cocoa: a library (`ORMKit`) that
reads, edits, verbalizes and maps NORMA's `.orm` files to Core Data, a tool
(`Tools/ormtool`) and an editor (`ORMDesigner`). `docs/ARCHITECTURE.md` has
the design and what is not done; `docs/COREDATA-MAPPING.md` the mapping;
`docs/VERBALIZATION.md` the FORML templates.

## The XML document is the model

Never regenerate a `.orm` from objects. `ORMModel` is a read-only
projection rebuilt after each change; every change goes through `ORMEditor`,
which also keeps up NORMA's denormalized data. Two invariants hold and are
tested: an unchanged NORMA file is written back byte for byte, and
normalizing one changes nothing. A change to `-[ORMEditor normalize]` that
breaks the second is a change to what NORMA would write: check it against
the files in `ORMKitTests/Fixtures` (StockMate is NORMA's own;
PreventiveMaintenance was written by another tool and is not authoritative).

ORMKit is Foundation only; CI rejects AppKit in it.

## Building

```sh
python3 .tools/genxcodeproj.py   # after adding a file to a GNUmakefile
xcodebuild -project ORMKit.xcodeproj -scheme ORMKitTests -destination 'platform=macOS' test
.tools/gnustep.sh make -C ORMKit
.tools/gnustep.sh make -C ORMKitTests run-tests
.tools/gnustep.sh make -C ORMDesignerTests run-tests
```

The Xcode project is generated from the GNUmakefiles' source lists; CI
fails when the committed one is stale. Never edit `project.pbxproj` by hand.

## GNUstep patches live elsewhere

Fixes to GNUstep itself are not kept here. They live in `../gnustep-patches`,
which this machine's GNUstep projects share; `.github/scripts/dependencies.sh`
applies them at the commit pinned by `GNUSTEP_PATCHES_REF`. If a bug here
turns out to be GNUstep's, work there and read its `CLAUDE.md` first.

## Testing

GNUstep builds and tests run in docker (`.tools/gnustep.sh`, image
`ormkit-gnustep` built from `.tools/gnustep.Dockerfile`; RDLKit's
`rdlkit-gnustep` is the same stack). Anything that draws needs `xvfb-run -a`.
`__FILE__` is relative under gnustep-make: fixtures are found against the
current directory when it is.
