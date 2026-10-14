#!/usr/bin/env bash
# The client's frame from twenty-two cameras, hours and screens, as PNG files a person can look at.
#
#   bash lab/native/paint/shot.sh [label]
#
# Writes scratchpad/shots/<label><view>.png for the spawn and for open ground looking
# north, east, south, west, down and up. A label keeps two runs side by side, which is how
# a change to the picture is judged: the frame before and the frame after.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
OUT="$ROOT/scratchpad/shots"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
LABEL="${1:-}"

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi

mkdir -p "$OUT"
BEND_NO_TELEMETRY=1 "$BEND" "$SCRIPT_DIR/shot.bend" -o "$OUT/shot" >/dev/null
"$OUT/shot" --gpu off > "$OUT/shot.txt"
python3 "$SCRIPT_DIR/shot.py" "$OUT/shot.txt" "$OUT" "$LABEL"
rm -f "$OUT/shot.txt"
