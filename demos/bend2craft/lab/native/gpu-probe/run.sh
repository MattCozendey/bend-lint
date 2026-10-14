#!/usr/bin/env bash
# THROWAWAY SPIKE. Builds lab/native/gpu-probe/device_probe.bend to a native executable and runs it
# with --gpu off and --gpu on. It prints the power state first, because on a laptop battery power and
# Low Power Mode change clocks and a number without them is not a number about the machine.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SCRATCH="$ROOT/scratchpad/gpu-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi

if command -v pmset >/dev/null 2>&1; then
  printf 'power: '
  pmset -g batt | head -2 | tr '\n' ' '
  printf '| lowpowermode=%s\n' "$(pmset -g | awk '/lowpowermode/ { print $2 }')"
fi
printf 'compiler: '
BEND_NO_TELEMETRY=1 "$BEND" version

mkdir -p "$SCRATCH"
# `device_probe` is the straightforward leaf; `filtered_8` gives each 8-pixel leaf its own short list; `opt3_hostdeal`
# adds a 4x4 walk and has the host deal the polygons down to the leaves (the same picture); `opt4_planes` adds
# coverage by half-planes (about 0.08% of pixels, on polygon edges, differ).
for probe in device_probe filtered_8 opt3_hostdeal opt4_planes; do
  rm -f "$SCRATCH/$probe" "$SCRATCH/$probe.gpu"
  BEND_NO_TELEMETRY=1 "$BEND" "$SCRIPT_DIR/$probe.bend" -o "$SCRATCH/$probe" >/dev/null
  for gpu in off on; do
    printf '=== %s --gpu %s\n' "$probe" "$gpu"
    "$SCRATCH/$probe" --gpu "$gpu" | grep -E 'compare|iterations=10 ' | sed -E 's/ iterations=10//; s/ digest=.*//'
  done
done
