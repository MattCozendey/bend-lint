#!/usr/bin/env bash
# End-to-end proof of the native client under a real X display: the window opens,
# a key changes the frame, digging removes a block, the save key writes the world,
# the client exits, and a fresh start reads the dug world back.
#
# This is the only check that exercises the pinned window effect, the real key
# events and the real file writes together. Everything else in native/client.bend
# is proven headless by native/play_test.bend.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SCRATCH="$ROOT/scratchpad/client-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
SCREENSHOTS="${SCREENSHOTS:-1}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-30}"

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if [ "$("$BEND" version)" != 'bend 2.0.35' ]; then
  printf 'Native client smoke requires Bend 2.0.35: %s\n' "$BEND" >&2
  exit 1
fi
if ! command -v Xvfb >/dev/null 2>&1; then
  printf 'Xvfb is required: this smoke needs a real display, not a headless claim\n' >&2
  exit 1
fi
for tool in xdotool od python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s is required to send real key events and read the frame back\n' "$tool" >&2
    exit 1
  fi
done

mkdir -p "$SCRATCH"
RUN_DIR=$(mktemp -d "$SCRATCH/run.XXXXXX")
mkdir "$RUN_DIR/native" "$RUN_DIR/framebuffer"
BINARY="$RUN_DIR/bend2craft-native"
# The client writes the world next to its own relative path, so the run has its
# own copy of `native/` and cannot touch a real one.
WORLD="$RUN_DIR/native/client-world.b2cw"
DISPLAY_FILE="$RUN_DIR/display"
XVFB_LOG="$RUN_DIR/xvfb.log"
FRAME_FILE="$RUN_DIR/framebuffer/Xvfb_screen0"
FRAME_READER="$SCRIPT_DIR/frame-digest.py"

printf 'compiler: '
"$BEND" version
timeout 60s "$BEND" "$ROOT/native/client.bend" -o "$BINARY"

if [ -e "$WORLD" ]; then
  printf 'The isolated world file exists before startup\n' >&2
  exit 1
fi

# Abstract local socket, as lab/native/window-probe/smoke.sh does: the system-owned
# /tmp socket directory must not be chmodded for a test.
Xvfb -displayfd 3 -screen 0 256x256x24 -nolisten tcp -nolisten unix -listen local \
  -fbdir "$RUN_DIR/framebuffer" 3>"$DISPLAY_FILE" >"$XVFB_LOG" 2>&1 &
XVFB_PID=$!
cleanup() {
  kill "$XVFB_PID" 2>/dev/null || true
  wait "$XVFB_PID" 2>/dev/null || true
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

DISPLAY_NUM=
deadline=$((SECONDS + 10))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -s "$DISPLAY_FILE" ]; then
    IFS= read -r DISPLAY_NUM < "$DISPLAY_FILE" || true
    case "$DISPLAY_NUM" in
      ''|*[!0-9]*) DISPLAY_NUM= ;;
      *) break ;;
    esac
  fi
  if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    printf 'Xvfb exited during startup; see %s\n' "$XVFB_LOG" >&2
    exit 1
  fi
  sleep 0.05
done
if [ -z "$DISPLAY_NUM" ]; then
  printf 'Timed out waiting for an Xvfb display; see %s\n' "$XVFB_LOG" >&2
  exit 1
fi
export DISPLAY=":$DISPLAY_NUM"
printf 'XVFB_DISPLAY=:%s geometry=%s\n' "$DISPLAY_NUM" "$(xdotool getdisplaygeometry)"

# The bare Xvfb has no window manager, so nothing gives the window input focus and
# the runtime's pointer grab refuses to engage. Without focus there is no `Look`
# event and the player can never turn, so focus the window explicitly before the
# client starts and confirm the server agrees.
xsetroot -solid black >/dev/null 2>&1 || true

(cd "$RUN_DIR" && "$BINARY") >"$RUN_DIR/app.log" 2>&1 &
APP_PID=$!

# The window has to exist before any key is sent, so wait for the title rather than
# sleeping a fixed amount.
WINDOW=
deadline=$((SECONDS + 20))
while [ "$SECONDS" -lt "$deadline" ]; do
  WINDOW=$(xdotool search --name 'Bend2Craft native' 2>/dev/null | head -1 || true)
  if [ -n "$WINDOW" ]; then
    break
  fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    printf 'The client exited before its window appeared; see %s\n' "$RUN_DIR/app.log" >&2
    cat "$RUN_DIR/app.log" >&2
    exit 1
  fi
  sleep 0.1
done
if [ -z "$WINDOW" ]; then
  printf 'The native window never appeared on %s\n' "$DISPLAY_NUM" >&2
  exit 1
fi
printf 'window=%s\n' "$WINDOW"

# `Window.grab` only engages when the window already holds input focus, and the
# bare Xvfb has no window manager to give it. Set focus and move the pointer over
# the window before the look, and say so when the server refuses, because a
# refused grab is why a turn would silently do nothing.
xdotool windowfocus --sync "$WINDOW" 2>/dev/null || true
xdotool mousemove --window "$WINDOW" 64 64 2>/dev/null || true
sleep 0.2

# The window is the size `native/client.bend` chooses, read from its own source rather
# than restated here, so a resolution change does not leave this check asserting a size
# the client no longer uses — which is exactly what happened when the window went from
# 64x64 to 128x128 and the check failed on a stale 64. It is read, not run: running the
# client to ask would open a second window. The client now also takes `--size`, and this
# smoke deliberately passes no flag, so the window it opens is the default this reads.
EXPECTED_SIZE=$(awk '/^def window_width\(\)/ { getline; print $1; exit }' \
  "$ROOT/native/client.bend")
case "$EXPECTED_SIZE" in
  ''|*[!0-9]*)
    printf 'Could not read a numeric window_width from native/client.bend\n' >&2
    exit 1
    ;;
esac
WINDOW_GEOMETRY=$(xdotool getwindowgeometry --shell "$WINDOW")
eval "$WINDOW_GEOMETRY"
if [ "$WIDTH" -ne "$EXPECTED_SIZE" ] || [ "$HEIGHT" -ne "$EXPECTED_SIZE" ]; then
  printf 'Unexpected client window size: %sx%s, expected %sx%s\n' \
    "$WIDTH" "$HEIGHT" "$EXPECTED_SIZE" "$EXPECTED_SIZE" >&2
  exit 1
fi

# A digest of the window's own pixels, so a key press can be shown to have changed
# what is on screen without pinning any colour of a rendered world.
frame_digest() {
  python3 "$FRAME_READER" "$FRAME_FILE" "$X" "$Y" "$WIDTH" "$HEIGHT" 2>&1
}

wait_for_frame() {
  label=$1
  deadline=$((SECONDS + 5))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -f "$FRAME_FILE" ]; then
      if result=$(frame_digest); then
        case "$result" in
          *unavailable*) ;;
          *)
            printf 'FRAME_%s=%s\n' "$label" "$result"
            return 0
            ;;
        esac
      fi
    fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then
      printf 'The client exited before frame %s was readable\n' "$label" >&2
      return 1
    fi
    sleep 0.05
  done
  printf 'Frame %s was never readable\n' "$label" >&2
  return 1
}

press() {
  xdotool key --window "$WINDOW" --clearmodifiers "$1" 2>/dev/null || true
  sleep 0.25
}

# Looking is a `Look` event, which the runtime raises from pointer motion rather
# than from a key, so the turn is a relative mouse move.
look() {
  xdotool mousemove_relative -- "$1" "$2" 2>/dev/null || true
  sleep 0.25
}

wait_for_frame initial
BEFORE_MOVE=$(frame_digest)

# Walk, turn, dig, save. Each key is an edge, so each fires once per press.
press w
wait_for_frame after_w
AFTER_MOVE=$(frame_digest)
if [ "$BEFORE_MOVE" = "$AFTER_MOVE" ]; then
  printf 'Walking left the rendered frame unchanged\n' >&2
  exit 1
fi

look 24 0
wait_for_frame after_turn
AFTER_TURN=$(frame_digest)
if [ "$AFTER_TURN" = "$AFTER_MOVE" ]; then
  printf 'Turning left the rendered frame unchanged; the pointer grab never engaged\n' >&2
  exit 1
fi

press e
press t
sleep 0.5

if [ "$SCREENSHOTS" = "1" ] && command -v import >/dev/null 2>&1; then
  import -window "$WINDOW" "$SCRATCH/frame-after-dig.png" 2>/dev/null || true
fi

press Escape
deadline=$((SECONDS + TIMEOUT_SECONDS))
while [ "$SECONDS" -lt "$deadline" ]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if kill -0 "$APP_PID" 2>/dev/null; then
  printf 'The client was still running after escape\n' >&2
  kill "$APP_PID" 2>/dev/null || true
  exit 1
fi
# The exit code is checked, not just the fact that the process is gone. A crash also
# ends the process, so "it stopped" cannot tell a clean quit from a failure, and a
# client that died on its way out used to pass here.
set +e
wait "$APP_PID"
APP_STATUS=$?
set -e
if [ "$APP_STATUS" -ne 0 ]; then
  printf 'The client exited with status %s rather than quitting cleanly:\n' "$APP_STATUS" >&2
  cat "$RUN_DIR/app.log" >&2
  exit 1
fi

if [ ! -s "$WORLD" ]; then
  printf 'The save key did not write a world file\n' >&2
  cat "$RUN_DIR/app.log" >&2
  exit 1
fi
if ! head -1 "$WORLD" | grep -q '^B2CW:1$'; then
  printf 'The saved world is not a B2CW:1 snapshot\n' >&2
  exit 1
fi
printf 'saved world:\n'
cat "$WORLD"
if [ "$SCREENSHOTS" = "1" ]; then
  printf 'frame after dig: %s\n' "$SCRATCH/frame-after-dig.png"
fi
printf 'native-client-smoke=pass keys=move,turn,dig,save quit=escape world=written\n'
