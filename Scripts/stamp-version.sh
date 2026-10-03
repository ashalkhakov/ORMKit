#!/bin/bash
# Write a version into everything the About panel reads, so a packaged build
# says which build it is.
#
#   ./Scripts/stamp-version.sh 1.2.3
#
# No number in the repository is maintained by hand: the version comes from the
# tag, or from the run number and the commit for an unreleased build -- the
# same value the AppImage and the macOS archives are named after. What is in
# the tree is 0.0.0-dev, which is what a build from a working copy is.
#
# Two files, four keys and two build settings:
#   * ORMDesigner-Info.plist is the bundle's plist on BOTH platforms.
#     gnustep-make looks for <App>-Info.plist and merges it into the
#     Info-gnustep.plist it generates, so ApplicationRelease and FullVersionID
#     -- which GSInfoPanel shows -- live here beside CFBundleShortVersionString
#     and CFBundleVersion.
#   * project.pbxproj MARKETING_VERSION / CURRENT_PROJECT_VERSION -- Xcode
#     builds with GENERATE_INFOPLIST_FILE, so on macOS these are what actually
#     land in the built bundle, whatever the plist file says.
#
# Two forms of the version go in, because Apple parses some of these keys and
# GNUstep does not:
#
#   display -- the version as given, less any leading "v". The GNUstep About
#     panel shows this, and it can say anything: "0.0.0-229-18df32a" identifies
#     a build in a way a release number cannot.
#   numeric -- the leading dotted number of that, and nothing else. Xcode
#     compiles CURRENT_PROJECT_VERSION into a generated <Target>_vers.c as a
#     double, so the tag v0.1.0 arrived there as (double)v0.1.0 and the
#     framework failed to build with "use of undeclared identifier 'v0'".
#     CFBundleShortVersionString and CFBundleVersion are Apple's as well, and
#     are documented as period-separated integers.
set -euo pipefail

version=${1:-}
if [ -z "$version" ]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi

display=${version#v}
numeric=$(printf '%s' "$display" | sed -n 's/^\([0-9][0-9.]*\).*/\1/p' | sed 's/\.$//')
if [ -z "$numeric" ]; then
    echo "$0: '$version' has no leading number; using 0.0.0 where Apple needs one" >&2
    numeric=0.0.0
fi

root=$(cd "$(dirname "$0")/.." && pwd)
plist="$root/ORMDesigner/ORMDesigner-Info.plist"
project="$root/ORMKit.xcodeproj/project.pbxproj"

# PlistBuddy is not on Linux and neither is xcodebuild: both files are edited
# the one way that works on either host.
python3 - "$plist" "$project" "$display" "$numeric" <<'PY'
import re, sys
plist, project, display, numeric = sys.argv[1:5]

text = open(plist).read()
values = {
    # GNUstep's About panel: free-form, and the more it says the better.
    "ApplicationRelease": display,
    "FullVersionID": display,
    # Apple's: periods and integers, or the framework does not compile.
    "CFBundleShortVersionString": numeric,
    "CFBundleVersion": numeric,
}
for key, value in values.items():
    text, n = re.subn(r"(<key>%s</key>\s*<string>)[^<]*(</string>)" % key,
                      lambda m: m.group(1) + value + m.group(2), text)
    if n != 1:
        raise SystemExit("%s: expected one %s, found %d" % (plist, key, n))
open(plist, "w").write(text)

text = open(project).read()
for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
    text, n = re.subn(r"(\b%s = )[^;]*(;)" % key,
                      lambda m: m.group(1) + numeric + m.group(2), text)
    if n == 0:
        raise SystemExit("%s: no %s to stamp" % (project, key))
open(project, "w").write(text)
PY

echo "stamped $display, and $numeric where Apple parses it"
grep -n -A1 "ApplicationRelease\|FullVersionID\|CFBundleShortVersionString\|CFBundleVersion" \
     "$plist" | grep string
grep -m 1 -n "MARKETING_VERSION" "$project"
