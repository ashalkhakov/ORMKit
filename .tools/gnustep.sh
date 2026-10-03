#!/bin/sh
# Run a command inside the GNUstep image, with this checkout mounted.
#
#   .tools/gnustep.sh make -C ORMKitTests run-tests
#
# The image is not on any registry -- it is built locally from
# gnustep.Dockerfile, which compiles the whole GNUstep stack from source and
# takes the better part of an hour the first time. It is cached after that.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
image=ormkit-gnustep

if ! docker image inspect "$image" >/dev/null 2>&1; then
  cat >&2 <<MSG
$image has not been built yet. It is a local image, not one to pull:

    docker build -f .tools/gnustep.Dockerfile -t $image .

That compiles libobjc2, libdispatch, gnustep-make, base, gui, back and
tools-xctest from source, so expect it to take a while. Afterwards this
script is fast.
MSG
  exit 1
fi

exec docker run --rm -t -v "$root":/src -w /src "$image" \
  sh -c '. /gnustep/System/Library/Makefiles/GNUstep.sh; xvfb-run -a "$@"' -- "$@"
