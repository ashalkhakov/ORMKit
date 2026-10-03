# A GNUstep box to reproduce the Linux build locally, so a portability bug can
# be found in a minute here instead of a round trip through CI.
#
# Build it once -- this compiles libobjc2, libdispatch, gnustep-make, base, gui,
# back and tools-xctest from source, so it takes the better part of an hour:
#
#   docker build -f .tools/gnustep.Dockerfile -t ormkit-gnustep .
#
# After that the image is cached and running the suites is quick:
#
#   .tools/gnustep.sh make -C ORMKitTests run-tests
#   .tools/gnustep.sh make -C ORMDesignerTests run-tests
#
# The stack is the same one the workflow builds, from the same script, so what
# fails here fails there.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Retry, and stop apt pipelining requests, which is what proxies mangle. The
# install is split in two so a failure does not re-download the lot.
#
# Not built successfully on this machine: its network path corrupts plain HTTP
# from ports.ubuntu.com -- a 178 kB package arriving as 42 MB, reported as
# "File has unexpected size" -- and drops HTTPS to the same host entirely, so
# apt sees "Ign:" for every InRelease and ends up with no package lists. On a
# network that does neither, this builds as written. If yours does, point apt
# at a mirror you trust by editing /etc/apt/sources.list.d/ubuntu.sources here.
RUN printf '%s\n' \
      'Acquire::Retries "5";' \
      'Acquire::http::Pipeline-Depth "0";' \
      'Acquire::http::No-Cache "true";' \
      'Acquire::BrokenProxy "true";' \
    > /etc/apt/apt.conf.d/99-retries

RUN apt-get -q -y update && apt-get -q -y install \
      clang lld cmake make git pkg-config xvfb

RUN apt-get -q -y install \
      libgnutls28-dev libffi-dev libicu-dev libxml2-dev libxslt1-dev libssl-dev \
      libavahi-client-dev zlib1g-dev gnutls-bin libcurl4-gnutls-dev libgmp-dev \
      libcairo2-dev libjpeg-dev libtiff-dev libpng-dev libicns-dev \
      libpthread-workqueue-dev \
      libxt-dev libxmu-dev libxft-dev libxrandr-dev libxfixes-dev libxcursor-dev \
    && rm -rf /var/lib/apt/lists/*

# The gnustep-2.0 runtime wants ld.gold or lld; 24.04 ships lld.
RUN update-alternatives --install /usr/bin/ld ld /usr/bin/ld.lld 10

ENV CC=clang CXX=clang++ \
    LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0 \
    DEPS_PATH=/deps INSTALL_PATH=/gnustep

# Only the script is copied, and that is now enough. It used to apply patches
# named relative to the checkout, out of Patches/, which was never COPYed here
# -- so `git apply` could not have found them and this image was quietly built
# against a pristine gnustep-base and gui, unlike CI's. The script clones the
# shared gnustep-patches repository instead, so the image gets the same patched
# stack the workflow does. That needs git (installed above) and network access
# during `docker build`, which this already required to clone GNUstep itself.
#
# Set GNUSTEP_PATCHES_REF to pin to a commit; the default follows the shared
# repository's default branch, as a local reproduction box should.
COPY .github/scripts/dependencies.sh /tmp/dependencies.sh
RUN sh /tmp/dependencies.sh && rm -rf /deps

ENV LD_LIBRARY_PATH=/gnustep/lib
WORKDIR /src
