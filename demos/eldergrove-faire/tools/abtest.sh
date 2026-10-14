#!/bin/bash
# tools/abtest.sh [rev] [bench args...]: build git rev (default HEAD) beside
# the working tree and run the same benchmark on both, interleaved
cd "$(dirname "$0")/.."
REV=${1:-HEAD}; shift
ARGS=${@:-121 1500 0 700}
export PATH="$HOME/.bend/bin:$PATH" BEND_NO_TELEMETRY=1
OLD=$HOME/.park-ab
rm -rf "$OLD" && mkdir -p "$OLD"
git archive "$REV" | tar -x -C "$OLD"
(cd "$OLD" && bend main.bend -o park >/dev/null 2>&1) || { echo "old build failed"; exit 1; }
for i in 1 2 3; do
  echo -n "old: "; "$OLD/park" --bench $ARGS
  echo -n "new: "; ./park --bench $ARGS
done
