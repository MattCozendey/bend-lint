#!/usr/bin/env python3
"""Stack a rendered clip and a reference clip frame by frame, with captions.

The two clips are the same camera at the same instants, so frame *i* of one is
the frame to compare with frame *i* of the other.  This reads both, draws the
same labelled side-by-side `tools/compare.py` writes for a still, and writes
the stack as a numbered PNG sequence -- which is what ffmpeg then encodes:

  tools/video_frames.py --bend-dir out/video/bend --ref-dir out/video/ref \\
      --out-dir out/video/stack --count 200 --title "Bend | reference"

Frames are `%04d` inside each directory and start at 0.  The render side may be
a P3 PPM -- the live view writes ASCII PPM -- and the reference a PNG; both go
through `compare.load_rgb`, so neither has to be converted first.

Usage::

  tools/video_frames.py --bend-dir DIR --ref-dir DIR --out-dir DIR --count N
"""

from __future__ import annotations

import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import compare  # noqa: E402  (needs the sys.path line above)


def frame_path(directory: pathlib.Path, stem: str, i: int) -> pathlib.Path:
    """`<directory>/<stem>_%04d.<ext>` -- the first existing candidate."""
    for ext in (".png", ".ppm"):
        path = directory / ("%s_%04d%s" % (stem, i, ext))
        if path.is_file():
            return path
    raise SystemExit("video_frames: no frame %d in %s" % (i, directory))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bend-dir", required=True, help="rendered frames")
    ap.add_argument("--ref-dir", required=True, help="reference frames")
    ap.add_argument("--out-dir", required=True, help="stacked frames go here")
    ap.add_argument("--count", type=int, required=True, help="frames to stack")
    ap.add_argument("--title", default=None, help="caption drawn on every frame")
    ap.add_argument("--start", type=int, default=0, help="first frame index")
    args = ap.parse_args(argv)

    if args.count <= 0:
        ap.error("--count must be positive")

    bend_dir = pathlib.Path(args.bend_dir)
    ref_dir = pathlib.Path(args.ref_dir)
    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for k in range(args.count):
        i = args.start + k
        bend = compare.load_rgb(frame_path(bend_dir, "bend", i))
        ref = compare.load_rgb(frame_path(ref_dir, "ref", i))
        if bend.shape != ref.shape:
            raise SystemExit(
                "video_frames: frame %d is %s but the reference is %s"
                % (i, bend.shape[:2], ref.shape[:2]))
        stack = compare.draw_side_by_side(compare.to_image(bend),
                                         compare.to_image(ref), args.title)
        stack.save(out_dir / ("stack_%04d.png" % i))
        if k % 25 == 0:
            print("video_frames: %d/%d" % (k, args.count), file=sys.stderr)

    print("video_frames: wrote %d frames to %s" % (args.count, out_dir),
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
