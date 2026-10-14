#!/usr/bin/env python3
"""Compare a rendered frame against a reference frame, by eye and by number.

Reads two images -- PNG via Pillow, binary/ASCII PPM (P6/P3) with the standard
library -- optionally forces both to a common size, and reports the numbers a
human can put in a README: mean absolute error (overall and per channel), RMS
error, MSE, PSNR in dB, and a per-region MAE grid so a mismatch in the sky can
be told apart from one in the ground.

With ``--outdir`` it also writes artifacts:

  side.png     labelled side-by-side: render on the left, reference on the right
  diff.png     absolute difference, contrast-stretched so small deltas show
  metrics.json machine-readable numbers (the same ones printed to stdout)

``--diff-out PATH`` writes one labelled triptych instead: reference | render |
amplified difference.  ``--json`` prints the metrics block to stdout as JSON
instead of the human report.

The error numbers are deliberately dumb and comparable, not perceptual.  All
means and fractions are over RGB values in 0..1 (multiply by 255 for 8-bit
steps).  See ``definitions`` in the metrics block for the exact formulas.

Usage::

  tools/compare.py --bend out/frame.ppm --ref out/reference.png \\
      --outdir out/compare --title "Bend | reference"
  tools/compare.py --bend out/frame.ppm --ref out/reference.png \\
      --size 512x512 --grid 4 --diff-out out/compare/triptych.png --json
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sys

try:
    import numpy as np
except ImportError:  # pragma: no cover - environment guard
    raise SystemExit("compare: numpy is required for the image metrics")

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - environment guard
    Image = ImageDraw = ImageFont = None

# Luma weights (Rec. 709).  Any pixel statistic described as "luminance" uses
# these, on 0..1 linear-ish sRGB values -- no gamma decoding is applied.
LUMA = np.array([0.2126, 0.7152, 0.0722])

DARK_LEVEL = 8 / 255.0      # "dark": luminance below this
HOT_LEVEL = 200 / 255.0     # "hot":  luminance above this
HIST_BINS = 16

DEFAULT_GRID = 4            # 4x4 per-region MAE grid

FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
)


def _read_ppm(path: pathlib.Path, data: bytes) -> np.ndarray:
    """Parse a P6 (binary) or P3 (ASCII) PPM into an HxWx3 float array 0..1."""
    magic = data[:2]
    pos = 2

    def next_token() -> bytes:
        nonlocal pos
        while True:
            while pos < len(data) and data[pos:pos + 1].isspace():
                pos += 1
            if pos < len(data) and data[pos:pos + 1] == b"#":
                while pos < len(data) and data[pos:pos + 1] not in (b"\n", b"\r"):
                    pos += 1
                continue
            break
        start = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        return data[start:pos]

    try:
        w = int(next_token())
        h = int(next_token())
        maxval = int(next_token())
    except ValueError:
        raise SystemExit(f"compare: {path}: malformed PPM header")
    if w <= 0 or h <= 0:
        raise SystemExit(f"compare: {path}: bad PPM dimensions {w}x{h}")
    if maxval != 255:
        raise SystemExit(f"compare: {path}: expected maxval 255, got {maxval}")

    if magic == b"P6":
        # Exactly one whitespace byte separates the header from pixel data.
        if pos < len(data) and data[pos:pos + 1] == b"\r":
            pos += 1
        if pos < len(data) and data[pos:pos + 1] == b"\n":
            pos += 1
        need = w * h * 3
        pix = data[pos:pos + need]
        if len(pix) != need:
            raise SystemExit(
                f"compare: {path}: {len(pix)} pixel bytes, expected {need}")
        arr = np.frombuffer(pix, dtype=np.uint8).reshape(h, w, 3)
    else:  # P3: whitespace-separated decimal samples
        vals = np.empty(w * h * 3, dtype=np.uint16)
        try:
            for i in range(vals.size):
                vals[i] = int(next_token())
        except (ValueError, IndexError):
            raise SystemExit(
                f"compare: {path}: fewer than {vals.size} P3 samples")
        arr = vals.reshape(h, w, 3)
    return arr.astype(np.float64) / 255.0


def load_rgb(path: pathlib.Path) -> np.ndarray:
    """Load PNG or PPM as an HxWx3 float array in 0..1."""
    if not path.is_file():
        raise SystemExit(f"compare: no such image: {path}")
    with open(path, "rb") as fh:
        magic = fh.read(2)
    if magic in (b"P3", b"P6"):
        return _read_ppm(path, path.read_bytes())
    if Image is None:
        raise SystemExit(
            f"compare: cannot read '{path}' without Pillow; convert it to PPM "
            "(P3/P6) with an existing tool and pass that instead")
    try:
        with Image.open(path) as im:
            return np.asarray(im.convert("RGB"), dtype=np.float64) / 255.0
    except OSError as exc:
        raise SystemExit(f"compare: cannot read '{path}': {exc}")


def to_image(rgb: np.ndarray) -> "Image.Image":
    """8-bit RGB PIL image from a 0..1 float array."""
    if Image is None:
        raise SystemExit("compare: writing PNG artifacts needs Pillow")
    arr = (np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def resize_rgb(rgb: np.ndarray, width: int, height: int) -> np.ndarray:
    """Lanczos-resize a 0..1 float array (needs Pillow)."""
    if Image is None:
        raise SystemExit(
            "compare: unifying image sizes needs Pillow (or pass same-size inputs)")
    im = to_image(rgb).resize((width, height), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255.0


def luminance(rgb: np.ndarray) -> np.ndarray:
    """Per-pixel luminance, HxW."""
    return rgb @ LUMA


def image_stats(rgb: np.ndarray) -> dict:
    """Per-image summary: channel means, luminance, dark/hot, histogram."""
    lum = luminance(rgb)
    counts, _ = np.histogram(lum, bins=HIST_BINS, range=(0.0, 1.0))
    hist = (counts / lum.size).tolist()
    return {
        "size": [int(rgb.shape[1]), int(rgb.shape[0])],
        "channel_mean": {
            "r": float(rgb[:, :, 0].mean()),
            "g": float(rgb[:, :, 1].mean()),
            "b": float(rgb[:, :, 2].mean()),
        },
        "luminance_mean": float(lum.mean()),
        "dark_fraction": float((lum < DARK_LEVEL).mean()),
        "hot_fraction": float((lum > HOT_LEVEL).mean()),
        "luminance_histogram": hist,
    }


def region_mae(bend: np.ndarray, ref: np.ndarray, grid: int) -> list[list[float]]:
    """MAE inside each cell of a grid x grid split (rows = y, top to bottom)."""
    diff = np.abs(bend - ref)
    h, w = diff.shape[:2]
    ys = np.linspace(0, h, grid + 1).round().astype(int)
    xs = np.linspace(0, w, grid + 1).round().astype(int)
    out: list[list[float]] = []
    for i in range(grid):
        row = []
        for j in range(grid):
            cell = diff[ys[i]:ys[i + 1], xs[j]:xs[j + 1]]
            row.append(float(cell.mean()) if cell.size else 0.0)
        out.append(row)
    return out


def compare_arrays(bend: np.ndarray, ref: np.ndarray, grid: int) -> dict:
    """Error metrics between two same-size float arrays."""
    diff = np.abs(bend - ref)
    mse = float((diff ** 2).mean())
    psnr = None if mse == 0.0 else float(10.0 * math.log10(1.0 / mse))
    return {
        "mae": float(diff.mean()),
        "mae_per_channel": {
            "r": float(diff[:, :, 0].mean()),
            "g": float(diff[:, :, 1].mean()),
            "b": float(diff[:, :, 2].mean()),
        },
        "rmse": float(math.sqrt(mse)),
        "mse": mse,
        "psnr_db": psnr,
        "max_abs_diff": float(diff.max()),
        "p999_abs_diff": float(np.percentile(diff, 99.9)),
        "changed_fraction_gt_4_255": float((diff.max(axis=2) > 4 / 255.0).mean()),
        "region_grid": [grid, grid],
        "region_mae": region_mae(bend, ref, grid),
    }


def font(size: int):
    for path in FONT_CANDIDATES:
        if pathlib.Path(path).is_file():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


def draw_side_by_side(bend: "Image.Image", ref: "Image.Image",
                      title: str | None) -> "Image.Image":
    """Left panel render, right panel reference, with captions and a title."""
    w = bend.width + ref.width
    h = max(bend.height, ref.height)
    fsize = max(14, min(28, h // 28))
    f = font(fsize)
    pad = 6
    title_h = (fsize + 2 * pad) if title else 0
    cap_h = fsize + pad

    canvas = Image.new("RGB", (w, title_h + cap_h + h), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    if title:
        d.text((pad, pad), title, fill=(235, 238, 245), font=f)
    d.text((pad, title_h + pad // 2), "render", fill=(150, 210, 255), font=f)
    d.text((bend.width + pad, title_h + pad // 2), "reference",
           fill=(255, 200, 150), font=f)
    canvas.paste(bend, (0, title_h + cap_h))
    canvas.paste(ref, (bend.width, title_h + cap_h))
    return canvas


def draw_diff(bend: np.ndarray, ref: np.ndarray) -> "Image.Image":
    """Absolute difference, stretched so that small deltas are visible."""
    diff = np.abs(bend - ref)
    # 99.9th percentile rather than max, so one hot pixel cannot flatten the
    # rest of the image; never below one 8-bit step.
    scale = max(float(np.percentile(diff, 99.9)), 1 / 255.0)
    stretched = np.clip(diff / scale, 0.0, 1.0)
    return to_image(stretched)


def draw_triptych(ref: "Image.Image", render: "Image.Image",
                  diff: "Image.Image", title: str | None) -> "Image.Image":
    """reference | render | amplified difference, captioned."""
    panels = (("reference", ref), ("render", render),
              ("amplified difference", diff))
    h = max(p.height for _, p in panels)
    w = sum(p.width for _, p in panels)
    fsize = max(14, min(28, h // 28))
    f = font(fsize)
    pad = 6
    title_h = (fsize + 2 * pad) if title else 0
    cap_h = fsize + pad

    canvas = Image.new("RGB", (w, title_h + cap_h + h), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    if title:
        d.text((pad, pad), title, fill=(235, 238, 245), font=f)
    x = 0
    for label, panel in panels:
        d.text((x + pad, title_h + pad // 2), label,
               fill=(200, 210, 225), font=f)
        canvas.paste(panel, (x, title_h + cap_h))
        x += panel.width
    return canvas


def parse_size(text: str) -> tuple[int, int]:
    m = re.fullmatch(r"(\d+)[xX](\d+)", text.strip())
    if not m:
        raise argparse.ArgumentTypeError("--size must be WxH, e.g. 512x512")
    w, h = int(m.group(1)), int(m.group(2))
    if w <= 0 or h <= 0:
        raise argparse.ArgumentTypeError("--size dimensions must be positive")
    return w, h


def fmt(x: float) -> str:
    return f"{x:.6f}"


def print_report(name: str, s: dict) -> None:
    print(f"[{name}] {s['size'][0]}x{s['size'][1]}  "
          f"lum={fmt(s['luminance_mean'])}  dark={fmt(s['dark_fraction'])}  "
          f"hot={fmt(s['hot_fraction'])}")
    cm = s["channel_mean"]
    print(f"[{name}] mean R={fmt(cm['r'])} G={fmt(cm['g'])} B={fmt(cm['b'])}")
    print(f"[{name}] luma histogram (16 bins over 0..1): "
          + " ".join(f"{v:.4f}" for v in s["luminance_histogram"]))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bend", required=True, help="rendered frame (PNG or PPM P6/P3)")
    ap.add_argument("--ref", required=True, help="reference frame (PNG or PPM P6/P3)")
    ap.add_argument("--outdir", default=None,
                    help="write side.png, diff.png and metrics.json here")
    ap.add_argument("--diff-out", default=None, metavar="PATH",
                    help="write a reference|render|difference triptych here")
    ap.add_argument("--size", type=parse_size, default=None, metavar="WxH",
                    help="resize both images to this common size (Lanczos)")
    ap.add_argument("--grid", type=int, default=DEFAULT_GRID, metavar="N",
                    help=f"per-region MAE grid is NxN (default {DEFAULT_GRID})")
    ap.add_argument("--title", default=None, help="title drawn on the artifacts")
    ap.add_argument("--json", action="store_true",
                    help="print the metrics block as JSON instead of the report")
    args = ap.parse_args(argv)

    if args.grid < 1:
        ap.error("--grid must be >= 1")

    bend_path, ref_path = pathlib.Path(args.bend), pathlib.Path(args.ref)
    bend_rgb = load_rgb(bend_path)
    ref_rgb = load_rgb(ref_path)

    notes: list[str] = []
    if args.size:
        tw, th = args.size
        if bend_rgb.shape[:2] != (th, tw):
            bend_rgb = resize_rgb(bend_rgb, tw, th)
        if ref_rgb.shape[:2] != (th, tw):
            ref_rgb = resize_rgb(ref_rgb, tw, th)
        notes.append(f"forced common size {tw}x{th} (Lanczos)")
        ref_original = None
    else:
        bh, bw = bend_rgb.shape[:2]
        rh, rw = ref_rgb.shape[:2]
        ref_original = [rw, rh]
        if (rh, rw) != (bh, bw):
            ref_rgb = resize_rgb(ref_rgb, bw, bh)
            notes.append(f"reference resized {rw}x{rh} -> {bw}x{bh} (Lanczos)")

    h, w = bend_rgb.shape[:2]
    if args.grid > min(h, w):
        ap.error(f"--grid {args.grid} is larger than the {w}x{h} image")

    bend_img = to_image(bend_rgb)
    ref_img = to_image(ref_rgb)

    bend_stats = image_stats(bend_rgb)
    ref_stats = image_stats(ref_rgb)
    if ref_original is not None:
        ref_stats["original_size"] = ref_original
        ref_stats["resized_to_bend"] = ref_original != [w, h]
    else:
        ref_stats["forced_size"] = [w, h]

    metrics = {
        "title": args.title,
        "bend": {"path": str(bend_path), **bend_stats},
        "reference": {"path": str(ref_path), **ref_stats},
        "comparison": compare_arrays(bend_rgb, ref_rgb, args.grid),
        "definitions": {
            "values": "all means and fractions are over RGB in 0..1 (or pixel counts); "
                      "MAE/RMSE/MSE are in 0..1 -- multiply by 255 for 8-bit steps",
            "mae_per_channel": "mean |bend-reference| separately for R, G, B in 0..1",
            "psnr_db": "10*log10(1/MSE) with a peak of 1.0; null when the images are identical",
            "region_mae": "MAE inside each cell of a grid x grid split; rows are y, top to bottom",
            "luminance": "Rec.709: 0.2126 R + 0.7152 G + 0.0722 B per pixel",
            "dark_fraction": f"fraction of pixels with luminance < {DARK_LEVEL:.8f} (8/255)",
            "hot_fraction": f"fraction of pixels with luminance > {HOT_LEVEL:.8f} (200/255)",
            "luminance_histogram": f"{HIST_BINS} bins over luminance 0..1, values are fractions summing to 1",
            "diff_png": "|bend - reference| per channel, divided by the 99.9th percentile of the difference (min one 8-bit step)",
        },
    }

    if args.outdir:
        outdir = pathlib.Path(args.outdir)
        outdir.mkdir(parents=True, exist_ok=True)
        draw_side_by_side(bend_img, ref_img, args.title).save(outdir / "side.png")
        draw_diff(bend_rgb, ref_rgb).save(outdir / "diff.png")
        (outdir / "metrics.json").write_text(
            json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if args.diff_out:
        diff_out = pathlib.Path(args.diff_out)
        diff_out.parent.mkdir(parents=True, exist_ok=True)
        draw_triptych(ref_img, bend_img, draw_diff(bend_rgb, ref_rgb),
                      args.title).save(diff_out)

    if args.json:
        print(json.dumps(metrics, indent=2, sort_keys=True))
        return 0

    c = metrics["comparison"]
    print(f"bend={bend_path}  ref={ref_path}")
    for note in notes:
        print(note)
    print_report("bend", bend_stats)
    print_report("reference", ref_stats)
    psnr = "inf" if c["psnr_db"] is None else f"{c['psnr_db']:.2f}"
    mc = c["mae_per_channel"]
    print(f"[compare] mae={fmt(c['mae'])} "
          f"(R={fmt(mc['r'])} G={fmt(mc['g'])} B={fmt(mc['b'])})  "
          f"rmse={fmt(c['rmse'])}  psnr={psnr} dB  "
          f"max={fmt(c['max_abs_diff'])}  p99.9={fmt(c['p999_abs_diff'])}  "
          f"changed(>4/255)={fmt(c['changed_fraction_gt_4_255'])}")
    print(f"[compare] region MAE {args.grid}x{args.grid} "
          f"(rows=y top->bottom, cols=x left->right):")
    for row in c["region_mae"]:
        print("    " + " ".join(f"{v:.6f}" for v in row))
    written = []
    if args.outdir:
        written += [str(pathlib.Path(args.outdir) / n)
                    for n in ("side.png", "diff.png", "metrics.json")]
    if args.diff_out:
        written.append(str(pathlib.Path(args.diff_out)))
    if written:
        print("wrote " + ", ".join(written))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
