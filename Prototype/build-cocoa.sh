#!/bin/sh
# macOS / Cocoa build. No extra packages.
set -e
cd "$(dirname "$0")"
clang -fobjc-arc -fobjc-runtime=macosx \
      -framework Foundation -framework AppKit \
      -Wall -o NativeUML \
      main.m NUModel.m NUDiagramView.m NUAppDelegate.m
echo "built ./NativeUML"
