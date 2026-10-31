# A GNUstep box to reproduce the Linux build locally, so a portability bug can
# be found in a minute here instead of a round trip through CI.
#
#   docker build -f .tools/gnustep.Dockerfile -t ormkit-gnustep .
#   .tools/gnustep.sh make check
#
# What it builds on is what CI builds on: the releases .github/pins.env names
# (the GNUstep stack, FreeCoreData, GCDWebServer, ODataKit, DiagramKit), each an archive
# unpacked at /, on the Ubuntu they are built for, with the packages the
# stack lists beside it. To try a fix of one of them before it is released,
# install a build of it over this image's.
FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
# Through caching proxies that answer with stale indexes: no pipelining, no
# proxy caches, retries.
RUN printf 'Acquire::http::No-Cache "true";\nAcquire::BrokenProxy "true";\nAcquire::http::Pipeline-Depth "0";\nAcquire::Retries "5";\n' \
      > /etc/apt/apt.conf.d/99-retries
COPY .github/pins.env /tmp/pins.env
RUN set -e; \
    apt-get update; apt-get install -y --no-install-recommends ca-certificates curl xz-utils; \
    for name in GNUSTEP_PATCHES FREECOREDATA GCDWEBSERVER ODATAKIT DIAGRAMKIT; do \
      version=$(sed -n "s/^${name}_VERSION=//p" /tmp/pins.env); \
      repo=$(echo "$name" | tr 'A-Z_' 'a-z-'); \
      curl -fsSL --retry 5 --retry-all-errors -o /tmp/release.tar.xz \
        "https://github.com/ashalkhakov/$repo/releases/download/v$version/$repo-$version-ubuntu22.04-$(uname -m).tar.xz"; \
      tar -C / -xJf /tmp/release.tar.xz; rm /tmp/release.tar.xz; \
    done; \
    grep -v '^#' /opt/gnustep/share/gnustep-patches/packages-ubuntu.txt \
      | xargs apt-get install -y --no-install-recommends libsqlite3-dev; \
    update-alternatives --install /usr/bin/ld ld /usr/bin/ld.gold 10; \
    rm -rf /var/lib/apt/lists/*
ENV CC=clang CXX=clang++ LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0 \
    LD_LIBRARY_PATH=/opt/gnustep/lib
WORKDIR /src
