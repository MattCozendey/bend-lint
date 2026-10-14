#!/usr/bin/env bash
# The live client's presented frame rate.
#
# Runs `lab/native/client-probe/fps_probe.bend` under a real X display. The probe is the
# client — its own `start`, `view`, `tick`, window size and tile edge — driven through
# the prelude's own `App.loop` with a fixed frame countdown, and timed. Nothing in
# `native/client.bend` is modified; see the probe's header for why a probe is the right
# place for this.
#
# `App.loop`'s countdown is the frame count: the prelude decrements it once per
# `App.step`, and one `App.step` is one `Window.frame`, which is one `XPutImage`. So
# frames divided by elapsed wall time is the presented rate, measured rather than
# inferred. The runtime's `window_pace` sleeps every one of those frames to the next
# 16.67 ms tick, so 60.00 is the ceiling and anything below it is a frame that overran
# the tick.
#
# This probe deliberately does *not* drive input. A synthetic-key driver was built here
# to count the dig frame live, and it cannot give a trustworthy number: each `xdotool`
# invocation is a Python process sharing the client's four cores, so the driver's own cost
# lands inside the measurement. Sixteen digs at thirty frames read 58.39 FPS with two
# processes per press and 53.16 with one per stream, while the same probe reading no
# input reads 60.00 — so the number moves with the driver, not with the client. And the
# dig frame needs no live confirmation: `frame_edited` measures 16.25 ms against a
# 16.67 ms tick with a *forced* cold rebuild every iteration, and `window_pace` sleeps
# any frame shorter than the tick, so a sub-tick frame presents at the ceiling by
# construction. The harness median plus the quoted pacing code is stronger evidence than
# a live run the driver contaminates.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SCRATCH="$ROOT/scratchpad/client-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
# The runtime defaults `--threads` to the CPU count, which is how the shipping client
# is launched. Set to a number to compare against an explicit pool.
CLIENT_THREADS="${CLIENT_THREADS:-}"
# The window the probe opens, passed straight through to the client's own `--size` selector,
# so a resolution can be measured live instead of only in the harness. Empty means the
# client's default, which is the size the benchmarks measure.
PROBE_ARGS="${*:-}"
TICKS_PER_SECOND=60

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if ! command -v Xvfb >/dev/null 2>&1; then
  printf 'Xvfb is required: the presented rate needs a real display\n' >&2
  exit 1
fi
if ! command -v xdotool >/dev/null 2>&1; then
  printf 'xdotool is required: the bare Xvfb has no window manager\n' >&2
  exit 1
fi

RUN_DIR="$SCRATCH/fps-probe"
BINARY="$RUN_DIR/fps_probe"
mkdir -p "$RUN_DIR"
# The client saves to the relative path `native/client-world.b2cw`, so it resolves against
# its own working directory. The probe runs from the scratch folder rather than the
# repository root, so that folder needs a `native/` of its own or the save key fails with
# "No such file or directory" and takes the client down with it.
mkdir -p "$RUN_DIR/native"
WORLD_FILE="$RUN_DIR/native/client-world.b2cw"
printf 'compiler: '
"$BEND" version
printf 'target: the client loop, a fixed frame countdown, under Xvfb%s\n' \
  "${PROBE_ARGS:+ ($PROBE_ARGS)}"

timeout 180s "$BEND" "$SCRIPT_DIR/fps_probe.bend" -o "$BINARY" >/dev/null

# The client writes its world next to its own relative path, so a probe must not touch
# the repository's world file.
rm -f "$WORLD_FILE"

Xvfb -displayfd 3 -screen 0 256x256x24 -nolisten tcp -nolisten unix -listen local \
  -fbdir "$RUN_DIR" 3>"$RUN_DIR/display" >"$RUN_DIR/xvfb.log" 2>&1 &
XVFB_PID=$!
cleanup() {
  [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

DISPLAY_NUM=
deadline=$((SECONDS + 20))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -s "$RUN_DIR/display" ]; then
    IFS= read -r DISPLAY_NUM < "$RUN_DIR/display" || true
    case "$DISPLAY_NUM" in
      ''|*[!0-9]*) DISPLAY_NUM= ;;
    esac
    [ -n "$DISPLAY_NUM" ] && break
  fi
  kill -0 "$XVFB_PID" 2>/dev/null || { printf 'Xvfb exited; see %s\n' "$RUN_DIR/xvfb.log" >&2; exit 1; }
  sleep 0.1
done
[ -n "$DISPLAY_NUM" ] || { printf 'Timed out waiting for an Xvfb display\n' >&2; exit 1; }
export DISPLAY=":$DISPLAY_NUM"
printf 'XVFB_DISPLAY=:%s\n' "$DISPLAY_NUM"

# The bare Xvfb has no window manager, so nothing focuses the window and the runtime's
# pointer grab has nothing to hold. Without it a real player could never turn, so the
# window is focused before the probe starts. The probe is about frame cost, not input,
# but a grab that fails is a difference between this run and a player's.
xsetroot -solid black >/dev/null 2>&1 || true

if [ -n "$CLIENT_THREADS" ]; then
  (cd "$RUN_DIR" && "$BINARY" --threads "$CLIENT_THREADS" $PROBE_ARGS) >"$RUN_DIR/probe.log" 2>&1 &
else
  (cd "$RUN_DIR" && "$BINARY" $PROBE_ARGS) >"$RUN_DIR/probe.log" 2>&1 &
fi
PROBE_PID=$!

WINDOW=
deadline=$((SECONDS + 25))
while [ "$SECONDS" -lt "$deadline" ]; do
  WINDOW=$(xdotool search --name 'Bend2Craft native' 2>/dev/null | head -1 || true)
  [ -n "$WINDOW" ] && break
  kill -0 "$PROBE_PID" 2>/dev/null || {
    printf 'The probe exited before its window appeared; see %s\n' "$RUN_DIR/probe.log" >&2
    cat "$RUN_DIR/probe.log" >&2
    exit 1
  }
  sleep 0.1
done
[ -n "$WINDOW" ] || { printf 'The native window never appeared\n' >&2; exit 1; }
xdotool windowfocus --sync "$WINDOW" 2>/dev/null || true
printf 'window=%s launch_threads=%s\n' "$WINDOW" "${CLIENT_THREADS:-default}"

# The probe prints its own line and exits when the countdown runs out.
deadline=$((SECONDS + 120))
while [ "$SECONDS" -lt "$deadline" ]; do
  kill -0 "$PROBE_PID" 2>/dev/null || break
  sleep 0.5
done
if kill -0 "$PROBE_PID" 2>/dev/null; then
  printf 'The probe did not finish its frame countdown; see %s\n' "$RUN_DIR/probe.log" >&2
  cat "$RUN_DIR/probe.log" >&2
  exit 1
fi
wait "$PROBE_PID" || {
  printf 'The probe failed; see %s\n' "$RUN_DIR/probe.log" >&2
  cat "$RUN_DIR/probe.log" >&2
  exit 1
}

LINE=$(grep -E '^fps_probe ' "$RUN_DIR/probe.log" || true)
[ -n "$LINE" ] || {
  printf 'The probe printed no frame count; see %s\n' "$RUN_DIR/probe.log" >&2
  cat "$RUN_DIR/probe.log" >&2
  exit 1
}
printf '%s\n' "$LINE"
printf 'pace_ceiling_fps=%s\n' "$TICKS_PER_SECOND"
printf 'native-fps-probe=pass\n'
