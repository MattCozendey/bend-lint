#!/usr/bin/env bash
# The live client's pacing while the player walks, on whatever display DISPLAY names.
#
#   DISPLAY=:0 bash lab/native/client-probe/run-pace.sh --size=1024
#
# Runs lab/native/client-probe/pace_probe.bend for 900 frames and prints its line: the
# rate times one hundred, the frames that ran more than a millisecond past the tick, and
# the longest frame. Unlike run-fps.sh it starts no display of its own, because the
# display is part of what is being measured: under WSLg every presented frame crosses to
# the Windows host. THREADS sets the pool; empty is the runtime's default.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
RUN_DIR="$ROOT/scratchpad/client-probe/pace-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
THREADS="${THREADS:-}"

mkdir -p "$RUN_DIR/native"
BINARY="$RUN_DIR/pace_probe"
if [ "${BUILD:-1}" = 1 ]; then
  BEND_NO_TELEMETRY=1 "$BEND" "$SCRIPT_DIR/pace_probe.bend" -o "$BINARY" >/dev/null
fi
rm -f "$RUN_DIR/native/client-world.b2cw"
cd "$RUN_DIR"
if [ -n "$THREADS" ]; then
  "$BINARY" --threads "$THREADS" "$@" 2>&1 | grep -E 'pace_probe|rror|no display|fault'
else
  "$BINARY" "$@" 2>&1 | grep -E 'pace_probe|rror|no display|fault'
fi
