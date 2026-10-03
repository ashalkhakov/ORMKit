#!/bin/bash
# Put the AppImage's own metadata into AppDir: the launcher, the desktop entry
# and the icon. linuxdeploy insists on all three.
set -euo pipefail
workspace_dir=${1:-$(pwd)}
appdir=${2:-AppDir}

mkdir -p "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps"

install -m 0755 "$workspace_dir/Scripts/appimage/AppRun" "$appdir/AppRun"
install -m 0644 "$workspace_dir/Scripts/appimage/ORMDesigner.desktop" "$appdir/ormdesigner.desktop"
install -m 0644 "$workspace_dir/Scripts/appimage/ORMDesigner.desktop" \
        "$appdir/usr/share/applications/ormdesigner.desktop"
# The app's own icon, under the name the desktop entry asks for. One file: the
# icon in the About panel, on GNUstep's windows and in the launcher is the same
# picture, and cannot drift from itself.
install -m 0644 "$workspace_dir/ORMDesigner/ORMDesigner.png" "$appdir/ormdesigner.png"
install -m 0644 "$workspace_dir/ORMDesigner/ORMDesigner.png" \
        "$appdir/usr/share/icons/hicolor/256x256/apps/ormdesigner.png"

# The opener, under both names GNUstep asks for: "open" is what the
# GSUnknownFileTool default names, "xdg-open" is NSWorkspace's built-in
# fallback. Both go in the bundle's GNUstep tools directory, which
# [NSTask launchPathForTool:] searches before $PATH, and in usr/bin for
# anything that goes through $PATH instead.
mkdir -p "$appdir/usr/System/Tools" "$appdir/usr/bin"
for name in open xdg-open; do
    install -m 0755 "$workspace_dir/Scripts/appimage/open" "$appdir/usr/System/Tools/$name"
    install -m 0755 "$workspace_dir/Scripts/appimage/open" "$appdir/usr/bin/$name"
done
