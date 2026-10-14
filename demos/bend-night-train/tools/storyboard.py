#!/usr/bin/env python3
"""Render a moving shot of the night train and assemble it into video.

The Bend binary renders one frame per run and writes out/frame.ppm; this
drives it along the track and stitches the result.  A square frame is all the
renderer produces today, so the storyboard is square too.

  python3 tools/storyboard.py --frames 72 --depth 9 --ds 2.0

Writes out/storyboard.mp4 (the video) and out/storyboard.gif (a small loop
that embeds in a chat message).
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image


def render(binary, env, workdir):
    subprocess.run([binary], env=env, cwd=workdir, check=True,
                   stdout=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", default="out/night-train")
    ap.add_argument("--depth", default="9")
    ap.add_argument("--frames", type=int, default=72)
    ap.add_argument("--s0", type=float, default=0.0)
    ap.add_argument("--ds", type=float, default=2.0)
    ap.add_argument("--yaw", default=None, help="pin the head (else the demo's auto-look)")
    ap.add_argument("--pitch", default=None, help="pin the head (else the demo's own pitch)")
    ap.add_argument("--threads", default="16")
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--gif-width", type=int, default=360)
    ap.add_argument("--mp4", default="out/storyboard.mp4")
    ap.add_argument("--gif", default="out/storyboard.gif")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    binary = os.path.abspath(args.binary)
    tmp = tempfile.mkdtemp(prefix="storyboard-")
    try:
        frames = []
        for i in range(args.frames):
            env = dict(os.environ)
            env.update({
                "NT_DEPTH": args.depth,
                "NT_S": f"{args.s0 + i * args.ds:.4f}",
                "NT_PPM": "1",
            })
            # The camera is the demo's own ride unless the head is pinned, the
            # same convention the other drivers use.
            if args.yaw is not None:
                env["NT_YAW"] = args.yaw
            if args.pitch is not None:
                env["NT_PITCH"] = args.pitch
            render(binary, env, root)
            frame = os.path.join(tmp, f"{i:04d}.png")
            Image.open(os.path.join(root, "out", "frame.ppm")).save(frame)
            frames.append(frame)
            print(f"\rframe {i + 1}/{args.frames}", end="", file=sys.stderr)
        print(file=sys.stderr)

        images = [Image.open(f).convert("RGB") for f in frames]
        w, h = images[0].size
        gif_w = args.gif_width
        gif_h = max(1, round(h * gif_w / w))
        small = [im.resize((gif_w, gif_h), Image.LANCZOS) for im in images]
        small[0].save(args.gif, save_all=True, append_images=small[1:],
                      duration=round(1000 / args.fps), loop=0, optimize=True)
        print(f"{args.gif}: {os.path.getsize(args.gif) / 1e6:.1f} MB, "
              f"{gif_w}x{gif_h}, {len(small)} frames")

        if shutil.which("ffmpeg"):
            os.makedirs(os.path.dirname(os.path.abspath(args.mp4)), exist_ok=True)
            subprocess.run([
                "ffmpeg", "-y", "-loglevel", "error",
                "-framerate", str(args.fps), "-i", os.path.join(tmp, "%04d.png"),
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                args.mp4,
            ], check=True)
            print(f"{args.mp4}: {os.path.getsize(args.mp4) / 1e6:.1f} MB, "
                  f"{w}x{h}, {len(images)} frames")
        else:
            print("ffmpeg not found: no mp4", file=sys.stderr)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
