#!/usr/bin/env bash
# What the runtime's pointer grab delivers on a real X server.
#
# Runs lab/native/pointer/census.bend under Xvfb, focuses its window, and moves the
# pointer with relative XTest motion: eight steps of +10 px in x, one every 100 ms, then
# a pause, then eight of -10 px. The census prints one line per frame, so the `Look`
# lines are exactly what a client receives for a known amount of mouse travel.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SCRATCH="$ROOT/scratchpad/pointer"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"

for tool in Xvfb xdotool; do
  command -v "$tool" >/dev/null 2>&1 || { printf '%s is required\n' "$tool" >&2; exit 1; }
done

mkdir -p "$SCRATCH"
BINARY="$SCRATCH/census"
BEND_NO_TELEMETRY=1 "$BEND" "$SCRIPT_DIR/census.bend" -o "$BINARY" >/dev/null

rm -f "$SCRATCH/display"
# The abstract socket only: under WSL /tmp/.X11-unix is a read-only mount.
Xvfb -displayfd 3 -screen 0 640x480x24 -nolisten tcp -nolisten unix -listen local 3>"$SCRATCH/display" \
  >"$SCRATCH/xvfb.log" 2>&1 &
XVFB_PID=$!
cleanup() {
  [ -n "${CENSUS_PID:-}" ] && kill "$CENSUS_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

DISPLAY_NUM=
tries=0
while [ "$tries" -lt 100 ]; do
  if [ -s "$SCRATCH/display" ]; then
    IFS= read -r DISPLAY_NUM < "$SCRATCH/display" || true
    [ -n "$DISPLAY_NUM" ] && break
  fi
  sleep 0.1
  tries=$((tries + 1))
done
[ -n "$DISPLAY_NUM" ] || { printf 'Timed out waiting for an Xvfb display\n' >&2; exit 1; }
export DISPLAY=":$DISPLAY_NUM"

"$BINARY" --threads 1 >"$SCRATCH/census.log" 2>&1 &
CENSUS_PID=$!

WINDOW=
tries=0
while [ "$tries" -lt 100 ]; do
  WINDOW=$(xdotool search --name 'Bend2Craft pointer census' 2>/dev/null | head -1 || true)
  [ -n "$WINDOW" ] && break
  sleep 0.1
  tries=$((tries + 1))
done
[ -n "$WINDOW" ] || { printf 'The census window never appeared\n' >&2; cat "$SCRATCH/census.log" >&2; exit 1; }
xdotool windowfocus --sync "$WINDOW" 2>/dev/null || true
sleep 0.5

step=0
while [ "$step" -lt 8 ]; do
  xdotool mousemove_relative -- 10 0
  sleep 0.1
  step=$((step + 1))
done
sleep 0.5
step=0
while [ "$step" -lt 8 ]; do
  xdotool mousemove_relative -- -10 0
  sleep 0.1
  step=$((step + 1))
done

wait "$CENSUS_PID" || true
CENSUS_PID=
grep -E 'Look|Move' "$SCRATCH/census.log" || printf 'no pointer event reached the census\n'
printf 'frames=%s\n' "$(grep -c '^frame=' "$SCRATCH/census.log")"
