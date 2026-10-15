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
$image has not been built yet. It is a local image:

    docker build -f .tools/gnustep.Dockerfile -t $image .

That unpacks the releases .github/pins.env names, the ones CI builds on.
MSG
  exit 1
fi

exec docker run --rm -t -v "$root":/src -w /src "$image" \
  sh -c '. /opt/gnustep/System/Library/Makefiles/GNUstep.sh; xvfb-run -a "$@"' -- "$@"
