#!/bin/bash
# Imports, checked before the tests (make check, on GNUstep and on the Mac),
# from the repository's root:
#   * no macOS-only framework: CoreGraphics, Cocoa's umbrella and QuartzCore
#     compile on a Mac and break the GNUstep build;
#   * ORMKit has no AppKit: what draws belongs in ORMDesigner.
set -euo pipefail
if grep -rn "CoreGraphics\|<Cocoa/Cocoa.h>\|QuartzCore" \
     --include="*.h" --include="*.m" ORMKit ORMDesigner Tools ORMKitTests ORMDesignerTests; then
  echo "check-imports: a macOS-only framework is imported; GNUstep has no such header"
  exit 1
fi
if grep -rnE '^[[:space:]]*(#[[:space:]]*(import|include)|@import)[[:space:]]*[<"]?([^>"]*/)?(AppKit|Cocoa|Quartz)\b|^[[:space:]]*#[[:space:]]*(import|include)[[:space:]]*"[^"]*ORMDesigner/' \
     --include="*.h" --include="*.m" ORMKit; then
  echo "check-imports: ORMKit has no AppKit; what draws belongs in ORMDesigner"
  exit 1
fi
echo "check-imports: no macOS-only imports, no AppKit in ORMKit"
