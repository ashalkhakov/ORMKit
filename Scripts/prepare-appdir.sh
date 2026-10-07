#!/bin/bash
# Assemble AppDir. Ported from UDQuakeTools' Scripts/prepare-appdir.sh, which
# is known to work; the differences from it are marked, and there are only two.
#
#   GNUSTEP_PREFIX=/path/to/gnustep ./Scripts/prepare-appdir.sh
#
# Exit immediately if a command exits with a non-zero status
set -e

WORKSPACE_DIR=$(pwd)
# DIFFERENCE: the prefix is built in the same job rather than unpacked into
# /opt, so it is passed in. The default keeps the original behaviour.
LOCAL_PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"

# 1. Recreate clean AppDir structural root
rm -rf AppDir
mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/lib
mkdir -p AppDir/usr/etc
mkdir -p AppDir/usr/local/bin

# 2. Source GNUstep environment once
. "${LOCAL_PREFIX}/System/Library/Makefiles/GNUstep.sh"

# 3. Install into the prefix.
# DIFFERENCE: UDQuakeTools installs its apps with DESTDIR and then migrates the
# bundles out of the nested prefix path. We ship a command line tool as well as
# an app, and that migration only handles .app bundles, so both go into the
# SYSTEM domain instead and arrive in AppDir with the wholesale copy at step 5.
make -C ORMRuntime
make -C ORMRuntime install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C ORMKit
make -C ORMKit install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C Tools/ormtool
make -C Tools/ormtool install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C ORMDesigner
make -C ORMDesigner install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM

if [ -d "${LOCAL_PREFIX}/System/Library/Themes" ]; then
mkdir -p AppDir/usr/System/Library/Themes
cp -Rp "${LOCAL_PREFIX}/System/Library/Themes/"* AppDir/usr/System/Library/Themes/
fi

# 4. Dynamically locate the background tools
for tool in gdnc gpbs make_services; do
FOUND_TOOL=$(find "${LOCAL_PREFIX}" -type f -name "$tool" 2>/dev/null | head -n 1 || true)
if [ -n "$FOUND_TOOL" ]; then
    cp -p "$FOUND_TOOL" AppDir/usr/lib/
    cp -p "$FOUND_TOOL" AppDir/usr/local/bin/
fi
done

# 5. Pull BOTH System and Local hierarchies into AppDir/usr/
if [ -d "${LOCAL_PREFIX}/System" ]; then
mkdir -p AppDir/usr/System
cp -Rp "${LOCAL_PREFIX}/System/"* AppDir/usr/System/
fi
if [ -d "${LOCAL_PREFIX}/Local" ]; then
mkdir -p AppDir/usr/Local
cp -Rp "${LOCAL_PREFIX}/Local/"* AppDir/usr/Local/
fi

# Bundle libobjc from the prefix base lib directory
for libobjc in "${LOCAL_PREFIX}"/lib/libobjc.so.*.*; do
if [ -f "$libobjc" ]; then
    soname=$(basename "$libobjc")
    cp -p "$libobjc" AppDir/usr/lib/
    ln -sf "$soname" "AppDir/usr/lib/${soname%.*}"
    ln -sf "$soname" AppDir/usr/lib/libobjc.so
fi
done

# Bundle libdispatch and its BlocksRuntime dependency safely
echo "=== Manually staging libdispatch and BlocksRuntime ==="
if ls "${LOCAL_PREFIX}/lib"/libdispatch.so* 1> /dev/null 2>&1; then
cp -p "${LOCAL_PREFIX}/lib"/libdispatch.so* AppDir/usr/lib/
cp -p "${LOCAL_PREFIX}/lib"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
elif ls "${LOCAL_PREFIX}/lib64"/libdispatch.so* 1> /dev/null 2>&1; then
cp -p "${LOCAL_PREFIX}/lib64"/libdispatch.so* AppDir/usr/lib/
cp -p "${LOCAL_PREFIX}/lib64"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
fi

# 6. Maintain versioned and unversioned fallback bundle linking
BACKEND_BUNDLE=$(find AppDir/usr -name "libgnustep-back-*.bundle" 2>/dev/null | head -n 1 || true)
if [ -n "$BACKEND_BUNDLE" ]; then
BUNDLE_DIR=$(dirname "$BACKEND_BUNDLE")
BUNDLE_NAME=$(basename "$BACKEND_BUNDLE")
ln -sfv "$BUNDLE_NAME" "$BUNDLE_DIR/libgnustep-back.bundle" || true
ln -sfv "$BUNDLE_NAME" "$BUNDLE_DIR/back.bundle" || true
fi

# --- BUNDLE FONTS FOR PORTABILITY ---
# A diagram is measured in its fonts, and what the host has installed decides
# where its shapes' text lands. See the README.
mkdir -p AppDir/usr/etc/fonts
cp Scripts/appimage/fonts.conf AppDir/usr/etc/fonts/fonts.conf
for dir in /usr/share/fonts/truetype/dejavu /usr/share/fonts/truetype/liberation \
           /usr/share/fonts/truetype/msttcorefonts; do
if [ -d "$dir" ]; then
    mkdir -p "AppDir/usr/share/fonts/truetype/$(basename "$dir")"
    cp -Rp "$dir"/* "AppDir/usr/share/fonts/truetype/$(basename "$dir")/"
fi
done

# Clean up residual folders
find AppDir -maxdepth 1 -type d ! -name "AppDir" ! -name "usr" -exec rm -rf {} + 2>/dev/null || true

echo "AppDir assembled:"
du -sh AppDir
find AppDir/usr -maxdepth 4 -name 'ORMDesigner.app' -o -maxdepth 4 -name ormtool
