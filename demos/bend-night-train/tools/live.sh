#!/usr/bin/env bash
# Watch the night train from the renderer, as it renders.
#
# Frames go to stdout as PPM and straight into ffplay's image2pipe demuxer.  A
# process per frame, not a loop in one: the runtime reclaims a frame's transient
# tens of megabytes at exit, and in a loop that reclaim costs more than the
# frame itself.
#
# Each frame is stamped with the wall clock, so the train moves at the
# reference's own 24.5 m/s whatever rate the renderer manages -- frames are
# dropped when the renderer cannot keep up, never slowed down.  Quit with `q`
# in the player window, or Ctrl-C here.  For a clip that plays back smoothly
# instead, see tools/clip.sh.
#
#   tools/live.sh [depth] [threads]
#
# Environment: NT_S (start of the track, default 110), NT_HEAD (1 = headlight),
# NT_FPS (the rate ffplay is told to expect, default 30).
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname "$here")
cd "$root"

DEPTH=${1:-${NT_DEPTH:-8}}
THREADS=${2:-${NT_THREADS:-24}}
S0=${NT_S:-110}
HEAD=${NT_HEAD:-1}
FPS=${NT_FPS:-30}

make build >/dev/null

# The clock the frames are stamped with, in milliseconds since before the first
# one.  The stamp is read before the frame starts, so a slow frame shows the
# train where it was when the frame began rather than where it would have been
# had the frame been fast.  ISO-8601 date arithmetic is not POSIX, but the
# nanoseconds from `date +%s%N` are, and the rest is integer division.
start=$(date +%s%N)

frames() {
  while :; do
    local ms
    ms=$(( ($(date +%s%N) - start) / 1000000 ))
    NT_VIEW=1 NT_FRAMES=1 NT_MS="$ms" NT_DEPTH="$DEPTH" NT_S="$S0" NT_HEAD="$HEAD" \
      ./out/night-train --threads "$THREADS" || break
  done
}

# The player exiting closes the pipe, the producer's next write fails and the
# loop breaks: that, not a signal, is how `q` stops the renderer.
frames | ffplay -loglevel error -f image2pipe -framerate "$FPS" -i - || true
