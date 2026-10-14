#!/usr/bin/env bash
# The client's look under Xvfb, on either pointer.
#
#   bash lab/native/pointer/look-probe.sh display
#       Runs lab/native/pointer/look_probe.bend from a scratch directory, where the host
#       script is not found, so the client keeps the runtime's own grab. The pointer is then
#       moved with relative XTest motion: eight steps of +10 px, a pause, eight of -10 px.
#       On a real X server each step is one `Look`, so the yaw must rise by 80 px of turn
#       and come back.
#
#   bash lab/native/pointer/look-probe.sh host
#       Runs the same probe from the repository root, so under WSL the client starts
#       native/pointer-host.ps1 and reads the Windows pointer. Nothing here moves the
#       mouse: lab/native/pointer/host-probe.ps1 is the Windows half that does.
#
# Either way the output is the pointer the client chose and every yaw it held, in
# ten-thousandths of a radian, in order and without repeats.
set -eu

MODE="${1:-display}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SCRATCH="$ROOT/scratchpad/pointer"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"

for tool in Xvfb xdotool; do
  command -v "$tool" >/dev/null 2>&1 || { printf '%s is required\n' "$tool" >&2; exit 1; }
done

mkdir -p "$SCRATCH/run/native"
BINARY="$SCRATCH/look_probe"
LOG="$SCRATCH/look-$MODE.log"
if [ "${BUILD:-1}" = 1 ]; then
  BEND_NO_TELEMETRY=1 "$BEND" "$SCRIPT_DIR/look_probe.bend" -o "$BINARY" >/dev/null
fi
[ "$MODE" = build ] && exit 0

rm -f "$SCRATCH/display"
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

if [ "$MODE" = host ]; then
  (cd "$ROOT" && "$BINARY" --threads 1) >"$LOG" 2>&1 &
else
  (cd "$SCRATCH/run" && "$BINARY" --threads 1) >"$LOG" 2>&1 &
fi
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

if [ "$MODE" = display ]; then
  sleep 1
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
fi

wait "$PROBE_PID" || true
PROBE_PID=
grep -E '^pointer=' "$LOG" || printf 'the probe did not say which pointer it chose\n'
printf 'yaw:'
grep -E '^yaw=' "$LOG" | uniq | sed -E 's/^yaw=//' | tr '\n' ' '
printf '\nframes=%s\n' "$(grep -c '^yaw=' "$LOG")"
