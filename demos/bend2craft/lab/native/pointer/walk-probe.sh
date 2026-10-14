#!/usr/bin/env bash
# The region following a walking player, in the client's own loop under Xvfb.
#
# Runs lab/native/pointer/walk_probe.bend from a scratch directory and holds a key down
# with xdotool for the whole run: `w` by default, which walks north from fifteen cells
# east of the spawn, toward the world's origin and past it, with `space` held too so the
# player hops what is in the way. The probe prints the player's window cell and the
# region's first chunk every tick; this prints each place the region was, in order, and
# where the player ended.
#
#   bash lab/native/pointer/walk-probe.sh          # north, across the origin
#   bash lab/native/pointer/walk-probe.sh s        # south
set -eu

KEY="${1:-w}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SCRATCH="$ROOT/scratchpad/pointer"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"

for tool in Xvfb xdotool; do
  command -v "$tool" >/dev/null 2>&1 || { printf '%s is required\n' "$tool" >&2; exit 1; }
done

mkdir -p "$SCRATCH/walk/native"
BINARY="$SCRATCH/walk_probe"
LOG="$SCRATCH/walk-$KEY.log"
BEND_NO_TELEMETRY=1 "$BEND" "$SCRIPT_DIR/walk_probe.bend" -o "$BINARY" >/dev/null

rm -f "$SCRATCH/display" "$SCRATCH/walk/native/client-world.b2cw"
# The abstract socket only: under WSL /tmp/.X11-unix is a read-only mount.
Xvfb -displayfd 3 -screen 0 640x480x24 -nolisten tcp -nolisten unix -listen local \
  3>"$SCRATCH/display" >"$SCRATCH/xvfb.log" 2>&1 &
XVFB_PID=$!
cleanup() {
  [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null || true
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

(cd "$SCRATCH/walk" && "$BINARY") >"$LOG" 2>&1 &
PROBE_PID=$!

WINDOW=
tries=0
while [ "$tries" -lt 100 ]; do
  WINDOW=$(xdotool search --name 'Bend2Craft native' 2>/dev/null | head -1 || true)
  [ -n "$WINDOW" ] && break
  sleep 0.1
  tries=$((tries + 1))
done
[ -n "$WINDOW" ] || { printf 'The probe window never appeared\n' >&2; cat "$LOG" >&2; exit 1; }
xdotool windowfocus --sync "$WINDOW" 2>/dev/null || true
sleep 1
xdotool keydown "$KEY"
xdotool keydown space

wait "$PROBE_PID" || true
PROBE_PID=
xdotool keyup "$KEY" 2>/dev/null || true
xdotool keyup space 2>/dev/null || true
printf 'start: %s\n' "$(grep -m1 '^cell=' "$LOG")"
printf 'homes:'
grep -E '^cell=' "$LOG" | sed -E 's/.* home=//' | uniq | tr '\n' ' '
printf '\nend:   %s\n' "$(grep '^cell=' "$LOG" | tail -1)"
printf 'ticks=%s\n' "$(grep -c '^cell=' "$LOG")"
grep -v '^cell=' "$LOG" | grep -i -E 'fault|error|refused' || true
