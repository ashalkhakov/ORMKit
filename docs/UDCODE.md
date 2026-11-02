# ORM2 in UDCode

ORMKit ships a [UDCode](https://github.com/ashalkhakov/UDCodeKit) extension,
ORM2, which lets you edit NORMA's `.orm` models inside UDCode as part of a
project. The editor is ORMDesigner's (ORMDesignerKit), with the diagram,
inspector, model browser, Insert palette, Search, Issues, verbalization,
fact entry, populations, and the Queries and Core Data windows. ORMDesigner
remains its own app, built on the same framework.

## Installing it

Each ORMKit release attaches a package for each platform:

| UDCode on | Package |
|---|---|
| macOS, Apple silicon | `orm2-<version>-darwin-arm64.udcx` |
| macOS, Intel | `orm2-<version>-darwin-x64.udcx` |
| Linux (the AppImage), x86_64 | `orm2-<version>-linux-x64.udcx` |
| Linux, aarch64 | `orm2-<version>-linux-arm64.udcx` |
| Windows | `orm2-<version>-win32-x64.udcx` |

Install it with **UDCode > Extensions… > Install from Package…**, or from a
shell with `UDCode --install-extension orm2-<version>-<platform>.udcx`, then
start UDCode again. A package states which UDCode versions it is for
(`engines.udcode` in its `package.json`), and UDCode refuses one built for
another version or another platform.

## Using it

Opening a `.orm` file from the project navigator shows the model in a tab
of its own, and the editor's parts spread over UDCode's window the way an
Xcode editor's do:

| Part | Where it goes in UDCode |
|---|---|
| The diagram, its page and the alignment bar | The tab |
| The model browser and Search | The tab's Document Outline, on the diagram's left (O, S) |
| The inspector | The inspector pane's **Element** tab, after **File** |
| Verbalization, Fact Entry, Population | The bottom area, beside the debugger and the terminal (V, F, P) |
| The Insert palette | The **Library**: View > Show Library (⇧⌘L) |
| The model's issues | The Issues navigator, under the document; choosing one selects its element |
| The Model, Diagram, Core Data and Query menus | The **Editor** menu |

These parts are shown while the ORM tab is in front and go away when
another tab comes forward. ORMDesigner arranges the same parts in its own
window.

The model is stored as the document's text, NORMA's XML. Each change you
make in the editor is written back to that text, so the things UDCode does
for text files work here too:

- **Undo** and **Redo** are the document's own. Undoing restores the text
  and reads the model again, keeping the page, the selection and the
  inspected element where they still exist.
- **Saving** and the tab's unsaved dot are the document's.
- **Source control** shows what changed. Each change touches only the lines
  that differ. One exception is the first change to a file that NORMA
  saved: ORMKit drops what NORMA generates from the model (its relational
  bridge and its list of model errors), and NORMA regenerates both when it
  opens the file.
- **Open as text** shows the XML in a normal editor tab, using the XML
  mode's highlighting. Edits made there appear in the model tab the next
  time it is shown.

A file that is not a model (broken XML, say) opens with a message
explaining why, and offers to show it as text.

## How it is built

`UDCodeExtension/` contains the extension:

- **`ORM2Extension`**, its principal class. It declares the `orm` mode in
  `LanguageInfo.plist`, which borrows the XML mode's grammar. It provides
  the editor for documents of that mode and adds ORMDesignerKit's menus
  (`+[ORMModelViewController modelMenuItems]`) to UDCode's Editor menu.
- **`ORM2EditorViewController`**, the tab, loaded from `ORM2Editor.xib`. It
  holds an `ORMModelViewController` in its hosted mode
  (`-initHostedWithEditor:`), over an `ORMEditor` that has no undo manager
  of its own, because the text's undo manager is the undo. Hosted, the
  editor's view is the tool bar, the Document Outline and the diagram. The
  inspector, the panes under the diagram and the Insert palette become view
  controllers of their own, which the tab hands to UDCode through
  `UDEditorPanes`. The model's issues (`ORMIssueFinder`) become the
  document's diagnostics, placed at the line where their element's id
  appears.
  `modelChangeHandler` writes each change as one `applyEdits:` call, which
  undoes as a single step. When the text changes from outside the editor,
  the tab reads it again: immediately if the tab is showing, otherwise
  after a short delay.
- **`ORM2TextDiff`**, a Myers line diff. It produces the runs of lines that
  differ, each starting and ending on a line boundary, so an edit never
  splits a CRLF.

It builds against UDCode's SDK, the `udcodekit` archives attached to each
UDCode release, pinned by `UDCODEKIT_VERSION` in `.github/pins.env`. It
uses the same GNUstep stack as that UDCode release (`GNUSTEP_PATCHES_VERSION`)
and the same DiagramKit (`DIAGRAMKIT_VERSION`). At run time the extension
uses UDCode's own copies of these, because two copies of the same classes
cannot be loaded into one process. On GNUstep the top `GNUmakefile` builds
it only where the SDK is installed. On a Mac, `Makefile.apple` builds it
only where `.deps` contains `UDCodeKit.xcframework`.

`Scripts/udcx.sh <version> <directory>` packages it for the platform it runs
on:

- **The bundle carries what UDCode lacks.** On GNUstep, ORMDesignerKit is
  compiled into the bundle and its XIBs are among the bundle's resources.
  It can't be a framework inside the bundle there: gnustep-base finds a
  framework's resources from its DLL's folder, and Windows looks for the
  bundle's libraries only beside the bundle's DLL. Next to the binary go
  ORMKit's and ORMRuntime's libraries, ODataKit's (with OTelKit), and
  FreeCoreData's Core Data. On Linux each library gets an `$ORIGIN` runpath
  so the libraries find one another. On a Mac, all of these, ORMDesignerKit
  included, are frameworks in the bundle's `Contents/Frameworks`.
- **What UDCode has is left out:** GNUstep, DiagramKit, UDCodeKit and the
  system's libraries. The running UDCode's copies are used.
- **Licences:** ORMKit's own (LGPL 2.1, with its source at the release tag
  that package.json's `repository` points to), plus DMTabBar's and each
  carried library's, fetched from the release tag it is pinned to.
- **On a Mac** it is signed with `$CODESIGN_IDENTITY`. UDCode's hardened
  runtime loads only code signed by its own team, and the release
  workflows sign the package as they sign the apps, then notarize it.

The release workflows run that script through `.github/release/udcode.conf`
(gnustep-release-actions' `scripts/udcode-extension.sh`) and attach each
package to the release.

The tests in `UDCodeExtension/Tests` (`ORM2Tests`, run by `make check` and
by `make -f Makefile.apple check`) drive the tab through UDCode's own
document and text model. They check that:

- a model opens without its text changing;
- a change is one edit of the lines it changed, which undo and redo bring
  back;
- a text that is not a model says why, and becomes a model once one is
  written into it;
- the editor and the tab are in the responder chain;
- the line diff turns one text into the other.
