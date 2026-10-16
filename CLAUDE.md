# ORMKit

Object-Role Modeling (ORM2) for GNUstep and Cocoa: a library (`ORMKit`) that
reads, edits, verbalizes and maps NORMA's `.orm` files to Core Data, a tool
(`Tools/ormtool`) and an editor (`ORMDesigner`). [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) has
the design and what is not done; [docs/COREDATA-MAPPING.md](docs/COREDATA-MAPPING.md) the mapping;
[docs/VERBALIZATION.md](docs/VERBALIZATION.md) the FORML templates; [docs/QUERIES.md](docs/QUERIES.md) the conceptual
queries; [docs/CURSORS.md](docs/CURSORS.md) how a plan is read, as a tree of cursors;
[docs/RULES.md](docs/RULES.md) queries as constraints and calculations;
[docs/DERIVATION.md](docs/DERIVATION.md) derived fact types, and keeping stored ones up to date;
[docs/RUNTIME.md](docs/RUNTIME.md) what apps run: plans as tables in resources, read by a small
driver library, with generated code kept to declarations;
[docs/POPULATIONS.md](docs/POPULATIONS.md) the sample populations they run on;
[docs/MODEL.md](docs/MODEL.md) the model as objects, and the XML as NORMA's.

## The objects are the model; the XML is for NORMA

`ORMModel` and its elements are the model: every change goes through
`ORMEditor` and its editors, which change the objects and record the undo.
The `.orm` XML is NORMA interop: read once when a file is opened, and
written from the model when it is saved, into the document read (the
carrier), so that what ORMKit does not model survives. Nothing else reads
or writes the XML; apps built from a model use neither
([docs/MODEL.md](docs/MODEL.md)).

Two invariants hold and are tested: an unchanged NORMA file is written back
byte for byte, and one read and written again with every element written
from the model is the same bytes. A change to what the writer
(`ORMNormaWriter`) writes is a change to what NORMA would write:
check it against the files in `ORMKitTests/Fixtures` (StockMate is NORMA's
own; PreventiveMaintenance was written by another tool and is not
authoritative).

ORMKit is Foundation only; CI rejects AppKit in it.

## Building

```sh
python3 .tools/genxcodeproj.py   # after adding a file to a GNUmakefile
xcodebuild -workspace ORMKit.xcworkspace -scheme ORMKitTests -destination 'platform=macOS' test
.tools/gnustep.sh make -C ORMRuntime && .tools/gnustep.sh make -C ORMKit
.tools/gnustep.sh make -C ORMKitTests run-tests
.tools/gnustep.sh make -C ORMDesignerTests run-tests
```

The Xcode project is generated from the GNUmakefiles' source lists; CI
fails when the committed one is stale. Never edit `project.pbxproj` by hand.

ORMKit depends on ODataKit ([docs/ODATA.md](docs/ODATA.md)) and, on GNUstep,
FreeCoreData under it. `.github/pins.env` names the exact releases it builds
on (with the GNUstep stack, GCDWebServer and Sparkle): on the Mac their
XCFrameworks are in `.deps/` (gnustep-release-actions' `scripts/deps.sh
apple`), and GNUstep links the installed libraries (`odatakit.make`). Move a
pin there; CI and the docker image both read it.

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
which this machine's GNUstep projects share; it publishes the patched stack as
releases, and `.github/pins.env` (`GNUSTEP_PATCHES_VERSION`) names the one
ORMKit builds on. If a bug here turns out to be GNUstep's, work there and read
its `CLAUDE.md` first.

## Testing

Build and test the familiar way: `make`, `make check` and `make install` on
GNUstep; `make -f Makefile.apple` and `make -f Makefile.apple check` on the
Mac. GNUstep builds and tests run in docker (`.tools/gnustep.sh make check`,
image `ormkit-gnustep` built from `.tools/gnustep.Dockerfile` on the releases
`.github/pins.env` names). Anything that draws needs `xvfb-run -a`.
`__FILE__` is relative under gnustep-make: fixtures are found against the
current directory when it is.

A fix to the stack, FreeCoreData or ODataKit not yet released can be tried in
the image by building it there over the installed one (`make && make install`
in a checkout of it); once released, move its pin.
