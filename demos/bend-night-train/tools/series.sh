#!/usr/bin/env bash
# Render a comparison series: for each position along the track, the Bend
# frame, the original WebGL frame at the matching frozen camera, and the
# metrics between them.
#
# Both cameras are pinned exactly as the compare target in the Makefile pins
# them, so the frames are comparable and the numbers mean something.
#
#   tools/series.sh [outdir] [s ...]
#
# Defaults: out/series, positions 0 110 150 320, depth 10 (1024x1024).
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname "$here")
cd "$root"

OUT=${1:-out/series}
shift || true
POS=${*:-"0 110 150 320"}
DEPTH=${NT_DEPTH:-10}
THREADS=${NT_THREADS:-8}

mkdir -p "$OUT"
make build >/dev/null
for S in $POS; do
  NT_DEPTH="$DEPTH" NT_PPM=1 NT_S="$S" NT_YAW=0.0 NT_PITCH=-0.02 \
    ./out/night-train --threads "$THREADS" >/dev/null
  python3 tools/ppm2png.py out/frame.ppm "$OUT/bend_s$S.png" >/dev/null
  python3 tools/render_reference.py --out "$OUT/ref_s$S.png" \
    --size "$((1 << DEPTH))" --s "$S" --lean 1 --yaw 0 --pitch -0.02 >/dev/null
  mkdir -p "$OUT/s$S"
  python3 tools/compare.py --bend "$OUT/bend_s$S.png" --ref "$OUT/ref_s$S.png" \
    --outdir "$OUT/s$S" --title "Bend | reference  s=$S" | grep '\[compare\]'
done
echo "wrote $OUT"
