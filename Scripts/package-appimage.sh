#!/bin/bash
# Turn AppDir into an AppImage. Ported from UDQuakeTools'
# Scripts/package-appimage.sh.
#
#   APP_VERSION=1.2.3 ./Scripts/package-appimage.sh
set -euo pipefail

WORKSPACE_DIR=$(pwd)
LOCAL_PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"
# Where Scripts/install-linuxdeploy.sh puts it: somewhere the job can write.
LINUXDEPLOY="${LINUXDEPLOY:-${LINUXDEPLOY_DIR:-${RUNNER_TEMP:-/tmp}/linuxdeploy}/AppRun}"

# 1. Copy tracked AppImage metadata/runtime assets into AppDir.
"${WORKSPACE_DIR}/Scripts/appimage/install-assets.sh" "${WORKSPACE_DIR}" "AppDir"

# 2. Gather executable inputs for linuxdeploy.
mapfile -t ELF_BINS < <("${WORKSPACE_DIR}/Scripts/appimage/collect-elf-binaries.sh" "AppDir")
ELF_ARGS=()
for bin in "${ELF_BINS[@]}"; do
    ELF_ARGS+=(--executable "$bin")
done

# 3. Run the linuxdeploy process.
export OUTPUT="ORMKit-Linux-${APP_VERSION:-dev}-$(uname -m).AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_VALIDATE=1
export LDAI_RUNTIME_FILE="${LDAI_RUNTIME_FILE:-/tmp/appimage-runtime/runtime-x86_64}"

LD_LIBRARY_PATH="${LOCAL_PREFIX}/System/Library/Libraries:${LOCAL_PREFIX}/Local/Library/Libraries:${WORKSPACE_DIR}/AppDir/usr/lib:${LD_LIBRARY_PATH:-}" \
    "$LINUXDEPLOY" --appdir AppDir "${ELF_ARGS[@]}" --output appimage

echo "built $OUTPUT"
