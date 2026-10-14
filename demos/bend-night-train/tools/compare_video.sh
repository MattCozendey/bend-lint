#!/usr/bin/env bash
# Record the same ride twice -- the Bend renderer and the original WebGL demo --
# and stack the two clips into one video, frame against frame.
#
#   tools/compare_video.sh [outfile]
#
# Both cameras ride the demo's own trajectory: s = NT_START + 24.5*t, head
# pinned (yaw 0, pitch -0.02), sway off.  That is the same camera the still
# comparison uses (see the compare target in the Makefile), so a frame of the
# video and out/compare/bend.png are the same picture.
#
# The renderer is slower than real time, so the clip is shot off-line and
# played back at the rate it was shot at: NT_MS advances on the timeline, not
# on the wall clock.
#
# Defaults: 512x512 (depth 9), 8 seconds, 25 fps, 24 threads, start at s=110.
# NT_DEPTH / NT_START / NT_RATE / NT_SECONDS / NT_THREADS / NT_WORK override.
# Alongside the mp4 the script writes a poster frame, `<outfile>-poster.png`,
# and an animated GIF, `<outfile>.gif`.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname "$here")
cd "$root"

OUT=${1:-assets/video/compare-512.mp4}
DEPTH=${NT_DEPTH:-9}
RATE=${NT_RATE:-25}
SECONDS_WANTED=${NT_SECONDS:-8}
THREADS=${NT_THREADS:-24}
S0=${NT_START:-110}
WORK=${NT_WORK:-out/video}
SIZE=$(( 1 << DEPTH ))

# A whole number of milliseconds per frame is what keeps the two timelines
# identical: at 25 fps a frame is 40 ms, while 24 fps would round to 41 and
# put the render three metres behind the reference by the end of the clip.
STEP=$(( 1000 / RATE ))
COUNT=$(( SECONDS_WANTED * RATE ))
if (( STEP * RATE != 1000 )); then
  echo "compare_video: NT_RATE=$RATE is not a whole number of ms per frame" >&2
  exit 2
fi

make build >/dev/null

rm -rf "$WORK/bend" "$WORK/ref" "$WORK/stack"
mkdir -p "$WORK/bend" "$WORK/ref" "$WORK/stack"

# One process per frame: the renderer is single-shot, and the live view is the
# path being shown, not a special build.
for (( i = 0; i < COUNT; i++ )); do
  f=$(printf '%s/bend/bend_%04d.ppm' "$WORK" "$i")
  NT_VIEW=1 NT_FRAMES=1 NT_MS=$(( i * STEP )) NT_DEPTH="$DEPTH" NT_S="$S0" \
    NT_YAW=0.0 NT_PITCH=-0.02 NT_MOTION=0 NT_HEAD=1 \
    ./out/night-train --threads "$THREADS" > "$f"
  if (( i % 25 == 0 )); then
    printf 'compare_video: bend %d/%d\n' "$i" "$COUNT" >&2
  fi
done

# The reference rides the same trajectory in one browser session: s advances by
# the same 24.5 m/s, t by 1/RATE, so frame i is the same instant on both sides.
python3 tools/render_reference.py --out "$WORK/ref/ref_%04d.png" \
  --frames "$COUNT" --fps "$RATE" --speed 24.5 --size "$SIZE" \
  --s "$S0" --lean 1 --yaw 0.0 --pitch -0.02 --no-motion

python3 tools/video_frames.py --bend-dir "$WORK/bend" --ref-dir "$WORK/ref" \
  --out-dir "$WORK/stack" --count "$COUNT" \
  --title "Bend 2 rasteriser | WebGL reference  -  same camera, ${SIZE}x${SIZE}"

mkdir -p "$(dirname "$OUT")"
ffmpeg -loglevel error -y -framerate "$RATE" -i "$WORK/stack/stack_%04d.png" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$OUT"

POSTER="${OUT%.*}-poster.png"
cp "$(printf '%s/stack/stack_%04d.png' "$WORK" "$(( COUNT / 2 ))")" "$POSTER"

# GIF is a poor codec for a dark, grainy night scene, so the settings are a
# compromise measured against the frames: half the frame rate, 720 px wide,
# one 128-colour palette for the whole clip (stats_mode=diff, bayer dither).
# Eight seconds lands at ~7.8 MB; sharper costs megabytes, not kilobytes.
GIF="${OUT%.*}.gif"
ffmpeg -loglevel error -y -i "$OUT" \
  -vf "fps=12.5,scale=720:-2:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
  -loop 0 "$GIF"

echo "compare_video: wrote $OUT, $POSTER and $GIF ($COUNT frames at ${RATE}fps)"