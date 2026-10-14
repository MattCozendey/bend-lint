#!/usr/bin/env bash
# Render a clip of the night train and encode it.
#
# The renderer is slower than the demo's own 30 frames a second, so a clip is
# rendered off-line and played back at the rate it was shot at: NT_STEP is the
# milliseconds between frames on the *timeline*, and ffmpeg is told the same
# rate, so the train runs at its real 24.5 m/s however long the render takes.
#
#   tools/clip.sh [seconds] [outfile]
#
# Defaults: 10 seconds, out/night-train.mp4.  Depth and thread count come from
# NT_DEPTH (default 9, 512x512) and NT_THREADS (default 24); NT_S is where the
# clip starts on the track (default 110).
#
# Ten seconds at 512x512 is about 300 frames, a few minutes of rendering.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname "$here")
cd "$root"

SECONDS_WANTED=${1:-10}
OUT=${2:-out/night-train.mp4}
DEPTH=${NT_DEPTH:-9}
THREADS=${NT_THREADS:-24}
RATE=${NT_FPS:-30}
S0=${NT_S:-110}
HEAD=${NT_HEAD:-1}

make build >/dev/null

# NT_STEP is integer milliseconds and the frame time is the index times it, so
# the timeline is 1000/RATE ms per frame rounded down.  At 30 the clip runs 1%
# slow, which is under a frame of drift over the ~11-second consist that loops.
STEP=$(( 1000 / RATE ))
COUNT=$(( SECONDS_WANTED * RATE ))

frames() {
  local i
  for (( i = 0; i < COUNT; i++ )); do
    NT_VIEW=1 NT_FRAMES=1 NT_MS=$(( i * STEP )) NT_DEPTH="$DEPTH" NT_S="$S0" \
      NT_HEAD="$HEAD" ./out/night-train --threads "$THREADS" || return 1
    if (( i % RATE == 0 )); then
      printf 'clip: %d/%d frames\n' "$i" "$COUNT" >&2
    fi
  done
}

mkdir -p "$(dirname "$OUT")"
frames | ffmpeg -loglevel error -y -f image2pipe -framerate "$RATE" -i - \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -movflags +faststart "$OUT"
echo "clip: wrote $OUT, $COUNT frames at ${RATE}fps"
