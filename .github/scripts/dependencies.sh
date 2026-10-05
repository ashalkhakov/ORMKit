#! /usr/bin/env sh
#
# Build the GNUstep stack ORMKit needs, from source, into $INSTALL_PATH.
#
# This follows the recipe from the user's gnustep-build repository, which is
# the known-good one: it is what their Forgejo instance builds the whole
# GNUstep stack with. The four things that matter and that a Foundation-only
# CI script would leave out:
#
#   --with-layout=gnustep    the cohesive System/Local hierarchy, rather than
#                            the flattened bin/lib/share one. Everything that
#                            packages a GNUstep tree -- our AppImage scripts
#                            included -- assumes this shape.
#   --enable-objc-arc        ORMKit is ARC throughout.
#   CPPFLAGS/LDFLAGS         point the compiler at the prefix so configure
#                            actually detects the libobjc2 built a step
#                            earlier, instead of falling back silently.
#   standalone.conf          makes libs-base read its config from the prefix,
#                            so the tree can be moved -- which is precisely
#                            what mounting an AppImage does.
#
# ORMKit itself is Foundation only, but ORMDesigner draws through AppKit, so
# libs-gui and a graphics backend are required, and both test bundles are
# XCTest, so tools-xctest is too. libs-corebase from that recipe is not built
# here; nothing in ORMKit uses it.
#
# Fixes to GNUstep itself come from the shared gnustep-patches repository,
# cloned below and applied per project; they are written for upstream and
# held there until they can be sent. Everything else is built from master as
# it stands.
#
# Expects: CC, CXX, LIBRARY_COMBO, RUNTIME_VERSION, DEPS_PATH, INSTALL_PATH.
set -ex

mkdir -p "$DEPS_PATH"

# GNUstep's own fixes are not kept here any more: several projects on this
# machine build the same stack and each used to carry its own copies, which
# drifted and outlived the merges upstream. They live in one repository now,
# and this fetches it.
#
# GNUSTEP_PATCHES_REF should name a commit, not a branch: it is what pins the
# build, and the workflows fold it into the cache key so that changing a
# patch invalidates the cached prefix. A branch name builds whatever is on it
# that day and the cache will not notice.
GNUSTEP_PATCHES_URL=${GNUSTEP_PATCHES_URL:-https://github.com/ashalkhakov/gnustep-patches.git}
GNUSTEP_PATCHES_REF=${GNUSTEP_PATCHES_REF:-7539fc686a72250574fff6c17e1c92eb024ddc33}
GNUSTEP_PATCHES_DIR="$DEPS_PATH/gnustep-patches"

install_gnustep_patches() {
    echo "::group::GNUstep patches"
    if [ ! -d "$GNUSTEP_PATCHES_DIR" ]; then
        git clone -q "$GNUSTEP_PATCHES_URL" "$GNUSTEP_PATCHES_DIR"
        (cd "$GNUSTEP_PATCHES_DIR" && git checkout -q "$GNUSTEP_PATCHES_REF")
    fi
    (cd "$GNUSTEP_PATCHES_DIR" && git log --oneline -1)
    echo "::endgroup::"
}

# Applies every patch that repository carries for one upstream project, with
# no fuzz, and skips one that is already present -- which is what a fix looks
# like between the day it is merged upstream and the day it is deleted there.
apply_gnustep_patches() {
    "$GNUSTEP_PATCHES_DIR/Scripts/apply-patches.sh" "$1" "$(pwd)"
}

# With --with-layout=gnustep this is where tools-make puts the makefiles.
GNUSTEP_SH="$INSTALL_PATH/System/Library/Makefiles/GNUstep.sh"

# libobjc2 and libdispatch are installed by cmake into $INSTALL_PATH/lib, which
# under this layout is *not* one of the GNUstep library roots -- those are under
# System/Library/Libraries. Nothing would add it to the loader path otherwise,
# and configure would decide the runtime is missing.
export LD_LIBRARY_PATH="$INSTALL_PATH/lib:${LD_LIBRARY_PATH:-}"
export C_INCLUDE_PATH="$INSTALL_PATH/include:${C_INCLUDE_PATH:-}"
export CPLUS_INCLUDE_PATH="$INSTALL_PATH/include:${CPLUS_INCLUDE_PATH:-}"

install_libobjc2() {
    echo "::group::libobjc2"
    cd "$DEPS_PATH"
    git clone -q --recursive https://github.com/gnustep/libobjc2.git
    cd libobjc2
    mkdir -p build && cd build
    cmake -DTESTS=off \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DGNUSTEP_INSTALL_TYPE=NONE \
          -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL_PATH" \
          -DCMAKE_C_COMPILER="$CC" \
          -DCMAKE_CXX_COMPILER="$CXX" \
          ../
    make install
    echo "::endgroup::"
}

install_libdispatch() {
    echo "::group::libdispatch"
    cd "$DEPS_PATH"
    git clone -q https://github.com/swiftlang/swift-corelibs-libdispatch.git libdispatch
    mkdir -p libdispatch/build && cd libdispatch/build
    # -Wno-error=void-pointer-to-int-cast works around a -Werror build failure
    # in queue.c; taken from libs-gui's script.
    cmake -DBUILD_TESTING=off \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL_PATH" \
          -DCMAKE_C_FLAGS="-Wno-error=void-pointer-to-int-cast" \
          -DINSTALL_PRIVATE_HEADERS=1 \
          -DBlocksRuntime_INCLUDE_DIR="$INSTALL_PATH/include" \
          -DBlocksRuntime_LIBRARIES="$INSTALL_PATH/lib/libobjc.so" \
          ../
    make install
    echo "::endgroup::"
}

install_tools_make() {
    echo "::group::GNUstep Make"
    cd "$DEPS_PATH"
    git clone -q -b ${TOOLS_MAKE_BRANCH:-master} https://github.com/gnustep/tools-make.git
    cd tools-make
    ./configure --prefix="$INSTALL_PATH" \
                --with-layout=gnustep \
                --with-library-combo="$LIBRARY_COMBO" \
                --with-runtime-abi="$RUNTIME_VERSION" \
                --enable-objc-arc \
                CPPFLAGS="-I$INSTALL_PATH/include" \
                LDFLAGS="-L$INSTALL_PATH/lib -Wl,-rpath,$INSTALL_PATH/lib" \
                CC="$CC" CXX="$CXX" || cat config.log
    make install
    . "$GNUSTEP_SH"
    gnustep-config --objc-flags
    echo "::endgroup::"
}

install_libs_base() {
    echo "::group::GNUstep Base"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_BASE_BRANCH:-master} https://github.com/gnustep/libs-base.git
    cd libs-base
    # Among them: the SAX handler libxml2 is handed unzeroed, and the
    # reserved-prefix namespace an "xmlns:foo" attribute manufactures, whose
    # teardown corrupts the heap -- both of which ORMKit's XML writing hits.
    apply_gnustep_patches libs-base
    # The reference recipe names $PREFIX/etc/GNUstep.conf here. This
    # gnustep-make writes it to $PREFIX/etc/GNUstep/GNUstep.conf instead, and
    # when the named file does not exist libs-base falls back to the built-in
    # standalone.conf defaults, which put every root at ./ relative to it --
    # so gnustep-gui looks for the backend in $PREFIX/etc and reports
    #
    #   Did not find correct version of backend (libgnustep-back-032.bundle)
    #   NSApplication.m:306 Assertion failed ... Unable to find backend back
    #
    # while the bundle sits in Local/Library/Bundles. Ask gnustep-make where
    # it actually put the file rather than naming a path.
    ./configure --prefix="$INSTALL_PATH" \
                --with-config-file="$(gnustep-config --variable=GNUSTEP_CONFIG_FILE)" \
                --with-default-config=standalone.conf || cat config.log
    make
    make install
    echo "::endgroup::"
}

install_libs_gui() {
    echo "::group::GNUstep GUI"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_GUI_BRANCH:-master} https://github.com/gnustep/libs-gui.git
    cd libs-gui
    # Among them: GSPDFPrintOperation overriding -_print with a single-sheet
    # copy of GSEPSPrintOperation's, so PDF output ignores -knowsPageRange:
    # and comes out upside down. Patched here, not worked around in ORMKit: a
    # workaround and the patch together would correct it twice.
    apply_gnustep_patches libs-gui
    ./configure --prefix="$INSTALL_PATH" || cat config.log
    make install
    echo "::endgroup::"
}

# Without a backend nothing draws, and the PDF backend draws. Cairo rather
# than the X11 one because it is what actually uses fontconfig, and so what
# produces PDF-quality output headlessly.
install_libs_back() {
    echo "::group::GNUstep Back (cairo)"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_BACK_BRANCH:-master} https://github.com/gnustep/libs-back.git
    cd libs-back
    ./configure --prefix="$INSTALL_PATH" --enable-graphics=cairo || cat config.log
    make install
    # gnustep-gui asks for the backend by version -- libgnustep-back-032.bundle
    # -- and master's gui and back do not always agree on it, which reports as
    #
    #   Did not find correct version of backend (libgnustep-back-032.bundle)
    #   NSApplication.m:306 Assertion failed ... Unable to find backend back
    #
    # UDQuakeTools' prepare-appdir.sh handles this with fallback symlinks. The
    # same links are made here rather than there, because the test suites run
    # against this prefix directly and need them too; AppDir gets them with the
    # wholesale copy, and prepare-appdir.sh still makes them itself.
    bundle=$(find "$INSTALL_PATH" -name 'libgnustep-back-*.bundle' | head -n 1)
    if [ -n "$bundle" ]; then
        dir=$(dirname "$bundle")
        name=$(basename "$bundle")
        ln -sfv "$name" "$dir/libgnustep-back.bundle"
        ln -sfv "$name" "$dir/back.bundle"
    fi
    echo "::endgroup::"
}

# The look users expect on Linux. It is a theme bundle that gnustep-gui
# dlopens at runtime, so it has to be inside the image and it has to be
# selected -- AppRun does the selecting. Built here rather than shipped
# prebuilt because a theme links against the same gui it will be loaded into.
install_eau_theme() {
    echo "::group::Eau theme"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q --depth 1 https://github.com/gershwin-desktop/gershwin-eau-theme.git Eau
    cd Eau
    # The theme uses blocks, and nothing in a theme bundle's link line pulls
    # the runtime in on its own. BlocksRuntime is only a separate library when
    # libdispatch built its own; ours is told to use libobjc's, so ask for it
    # only if it is there.
    ldflags="-L$INSTALL_PATH/lib -Wl,-rpath,$INSTALL_PATH/lib -ldispatch"
    if [ -e "$INSTALL_PATH/lib/libBlocksRuntime.so" ]; then
        ldflags="$ldflags -lBlocksRuntime"
    fi
    make ADDITIONAL_LDFLAGS="$ldflags"
    make install
    echo "::endgroup::"
}

install_tools_xctest() {
    echo "::group::tools-xctest"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q https://github.com/gnustep/tools-xctest.git
    cd tools-xctest
    make install
    echo "::endgroup::"
}

# Order matters: the runtime is built before tools-make, because configuring
# tools-make with --with-runtime-abi=gnustep-2.0 probes for it, and libdispatch
# needs BlocksRuntime from it. Everything after that needs GNUstep.sh, which
# tools-make installs.
install_gnustep_patches
install_libobjc2
install_libdispatch
install_tools_make
install_libs_base
install_libs_gui
install_libs_back
install_eau_theme
install_tools_xctest

echo "=== the prefix ==="
find "$INSTALL_PATH" -maxdepth 3 -type d | sort
