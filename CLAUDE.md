# ORMKit

Object-Role Modeling (ORM2) for GNUstep and Cocoa: a library (`ORMKit`) that
reads, edits, verbalizes and maps NORMA's `.orm` files to Core Data, a tool
(`Tools/ormtool`) and an editor (`ORMDesigner`). `docs/ARCHITECTURE.md` has
the design and what is not done; `docs/COREDATA-MAPPING.md` the mapping;
`docs/VERBALIZATION.md` the FORML templates; `docs/QUERIES.md` the conceptual
queries.

## The XML document is the model

Never regenerate a `.orm` from objects. `ORMModel` is a read-only
projection rebuilt after each change; every change goes through `ORMEditor`,
which also keeps up NORMA's denormalized data. Two invariants hold and are
tested: an unchanged NORMA file is written back byte for byte, and
normalizing one changes nothing. A change to `-[ORMNormalizer normalize]` that
breaks the second is a change to what NORMA would write: check it against
the files in `ORMKitTests/Fixtures` (StockMate is NORMA's own;
PreventiveMaintenance was written by another tool and is not authoritative).

ORMKit is Foundation only; CI rejects AppKit in it.

## Building

```sh
python3 .tools/genxcodeproj.py   # after adding a file to a GNUmakefile
xcodebuild -workspace ORMKit.xcworkspace -scheme ORMKitTests -destination 'platform=macOS' test
.tools/gnustep.sh make -C ORMKit
.tools/gnustep.sh make -C ORMKitTests run-tests
.tools/gnustep.sh make -C ORMDesignerTests run-tests
```

The Xcode project is generated from the GNUmakefiles' source lists; CI
fails when the committed one is stale. Never edit `project.pbxproj` by hand.

ORMKit depends on ODataKit (`../ODataKit`, docs/ODATA.md): the workspace
builds its framework, and GNUstep links the installed one (`odatakit.make`).
CI pins it (`ODATAKIT_REF`) and FreeCoreData under it (`FREECOREDATA_REF`);
move the pins and the image together.

ORMDesigner's windows and menu bar are XIBs (`ORMDesigner/*.xib`), listed in
`ORMDesigner_RESOURCE_FILES` and the test bundle's: Xcode compiles them,
GNUstep reads them as they are. Springs and struts only (gnustep-gui has no
Auto Layout); check a hand edit with `xcrun ibtool --errors --compile`.
A key equivalent XML cannot carry (Backspace, Escape) is written as
Interface Builder writes it, `<string key="keyEquivalent" base64-UTF8="YES">`.
What differs by platform or comes from code (scroller autohiding on Apple
only, colours, the tool buttons) is set in each controller's
`-windowDidLoad`; a custom view sets itself up in `-awakeFromNib`.

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

The local image cannot be rebuilt from scratch on this machine (apt over
this network), and it lags CI when `GNUSTEP_PATCHES_REF` moves: a failure
only in docker may be a fix CI already has. The sources are still in
`/deps`, so patch them in place and commit the container as the image:
apply `../gnustep-patches/Scripts/apply-patches.sh` at the pinned ref to
`/deps/libs-base` and `/deps/libs-gui`, then `make && make install` each.
That is how SUBQUERY started parsing here (2026-10-03). FreeCoreData and
ODataKit are installed in the image the same way: `git archive` of
`../gnustep-coredata` and `../ODataKit` at the pinned commits into `/deps`,
`make && make install` (FreeCoreData's `Tools/momc` too), `docker commit`.
apt did work on 2026-10-04 (`libsqlite3-dev`).
