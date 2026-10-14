#!/usr/bin/env python3
"""Convert a binary-free PPM (P3) frame into a PNG.

Bend has no image library and the File effect writes text, so the renderer
emits plain PPM.  This turns it into something a browser and a chat client
can display.

  python3 tools/ppm2png.py out/frame.ppm out/frame.png
"""

import struct
import sys
import zlib


def read_ppm(path):
    data = open(path, "rb").read()
    fields = data.split(b"\n", 3)
    if fields[0].strip() != b"P3":
        raise SystemExit(f"{path}: not a P3 PPM")
    w, h = map(int, fields[1].split())
    if int(fields[2]) != 255:
        raise SystemExit(f"{path}: expected maxval 255")
    vals = [int(v) for v in fields[3].split()]
    if len(vals) != w * h * 3:
        raise SystemExit(f"{path}: {len(vals)} samples, expected {w * h * 3}")
    return w, h, vals


def write_png(path, w, h, vals):
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type: none
        raw += bytes(vals[y * w * 3:(y + 1) * w * 3])

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += chunk(b"IEND", b"")
    open(path, "wb").write(out)


def stats(w, h, vals):
    n = len(vals)
    mean = sum(vals) / n
    dark = sum(1 for v in vals if v < 24) / n
    hot = sum(1 for v in vals if v > 230) / n
    return (f"{w}x{h}  mean={mean:6.1f}  dark={dark * 100:5.1f}%  "
            f"hot={hot * 100:4.1f}%")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    w, h, vals = read_ppm(src)
    write_png(dst, w, h, vals)
    print(f"{src} -> {dst}  {stats(w, h, vals)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
