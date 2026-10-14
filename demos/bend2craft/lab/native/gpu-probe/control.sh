#!/usr/bin/env bash
# THROWAWAY SPIKE. The control for lab/native/gpu-probe: Bend's own reference rasterizer
# (vendor/bend/demos/app_slash_boss_3d, 1920x1200) on this machine, on the CPU pool and on the GPU, by its
# own headless probe (`SLASH_PROBE`). If the reference is slower on the GPU here, so is anything built the
# way it is. Microseconds a frame; `draw` is the rasterizer, `whole` is the frame.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SCRATCH="$ROOT/scratchpad/gpu-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
FRAMES="${FRAMES:-300}"

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
rm -f "$SCRATCH/slash" "$SCRATCH/slash.gpu"
BEND_NO_TELEMETRY=1 "$BEND" "$ROOT/vendor/bend/demos/app_slash_boss_3d/main.bend" -o "$SCRATCH/slash" >/dev/null

for gpu in off on off on; do
  printf -- '--gpu %s: ' "$gpu"
  # The demo's audio clips are not in this checkout and it says so for each; the frame line is the last.
  SLASH_PROBE="$FRAMES" "$SCRATCH/slash" --gpu "$gpu" 2>/dev/null | tail -1
done
