#!/bin/bash
# ormtool on the StockMate model, each command under a timeout where there
# is one: check, verbalize, normalize (back to the same file), forml and
# apply (the model's own listing applied to it changes nothing), coredata and
# import (round trip), svg (well-formed where xmllint is), and the Core Data
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
run coredata "$sample" "$out/StockMate.xcdatamodeld"
test -s "$out/StockMate.xcdatamodeld/StockMate.xcdatamodel/contents"
run import "$out/StockMate.xcdatamodeld" "$out/imported.orm"
run check "$out/imported.orm"
run svg "$sample" "$out/diagrams/"
test -s "$out/diagrams/Products.svg"
if command -v xmllint > /dev/null; then xmllint --noout "$out"/diagrams/*.svg; fi
if command -v xcrun > /dev/null; then xcrun momc "$out/StockMate.xcdatamodeld" "$out/StockMate.momd"; fi
echo "ormtool-smoke: check, verbalize, normalize, forml, apply, coredata, import, svg"
