#!/bin/bash
# ormtool on the StockMate model, each command under a timeout where there
# is one: check, verbalize, normalize (back to the same file), forml and
# apply (the model's own listing applied to it changes nothing; a broken
# form makes check fail), coredata and
# import (round trip), sync (every entity both ways), svg (well-formed where xmllint is), and the Core Data
# model compiled where Xcode's momc is. make check runs it, on GNUstep and
# on the Mac, from the repository's root:
#
#   Scripts/ormtool-smoke.sh <ormtool>
set -euo pipefail
tool=$1
sample=ORMKitTests/Fixtures/StockMate.orm
out=$(mktemp -d)
run() {
  local limit=""
  command -v timeout > /dev/null && limit="timeout 120"
  $limit "$tool" "$@"
}
run check "$sample"
run verbalize "$sample" > "$out/stockmate.txt"
test -s "$out/stockmate.txt"
run normalize "$sample" "$out/normalized.orm"
cmp "$sample" "$out/normalized.orm"
run forml "$sample" > "$out/stockmate.forml"
grep -q '^# Products$' "$out/stockmate.forml"
run apply "$sample" "$out/stockmate.forml" "$out/applied.orm"
cmp "$sample" "$out/applied.orm"
# A form that breaks a rule of FORMS.md's definition: check fails, saying it.
{ cat "$out/stockmate.forml"; printf '\nQuery Broken:\nForm Broken:\nWarehouse\n  + has Name\n'; } > "$out/broken.forml"
run apply "$sample" "$out/broken.forml" "$out/broken.orm"
if run check "$out/broken.orm" > "$out/broken.txt"; then echo "ormtool-smoke: check passed a broken form"; exit 1; fi
grep -q '^form Broken: E6: Name: ' "$out/broken.txt"
run coredata "$sample" "$out/StockMate.xcdatamodeld"
test -s "$out/StockMate.xcdatamodeld/StockMate.xcdatamodel/contents"
run import "$out/StockMate.xcdatamodeld" "$out/imported.orm"
run check "$out/imported.orm"
run sync "$out/imported.orm" both
run coredata "$out/imported.orm" "$out/Synced.xcdatamodeld"
grep -rq 'key="ODataSync.direction" value="both"' "$out/Synced.xcdatamodeld"
run svg "$sample" "$out/diagrams/"
test -s "$out/diagrams/Products.svg"
if command -v xmllint > /dev/null; then xmllint --noout "$out"/diagrams/*.svg; fi
if command -v xcrun > /dev/null; then xcrun momc "$out/StockMate.xcdatamodeld" "$out/StockMate.momd"; fi
echo "ormtool-smoke: check, verbalize, normalize, forml, apply, coredata, import, sync, svg"
