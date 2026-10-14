#!/usr/bin/env python3
"""Digest a rectangle of an Xvfb -fbdir XWD framebuffer.

usage: frame-digest.py XWD_FILE X Y WIDTH HEIGHT

Prints `FRAME_DIGEST=xxxxxxxx` over the FNV-1a hash of the rectangle's pixels, so
two frames of the same window can be compared without pinning any colour. The XWD
header parsing is the same as native/window-probe/frame-pixel.py's, done here in a
few lines because a digest only needs the pixel stride.

Exit 0 on a readable framebuffer, 2 when it cannot be read.
"""

import struct
import sys
from pathlib import Path


def unavailable(message):
    print(f"FRAME_DIGEST=unavailable ({message})")
    return 2


def header_for(data):
    if len(data) < 100:
        return None
    for byte_order in ("<", ">"):
        values = struct.unpack(f"{byte_order}25I", data[:100])
        header_size, version = values[:2]
        depth, width, height = values[3:6]
        server_byte_order = values[7]
        bits_per_pixel, bytes_per_line = values[11:13]
        ncolors = values[19]
        if (
            version == 7
            and 100 <= header_size <= len(data)
            and 0 < width <= 16384
            and 0 < height <= 16384
            and depth > 0
            and bits_per_pixel in (8, 16, 24, 32)
            and bytes_per_line >= width * bits_per_pixel // 8
            and server_byte_order in (0, 1)
            and ncolors <= 65536
            and header_size + ncolors * 12 + bytes_per_line * height <= len(data)
        ):
            return {
                "header_size": header_size,
                "width": width,
                "height": height,
                "byte_order": server_byte_order,
                "bits_per_pixel": bits_per_pixel,
                "bytes_per_line": bytes_per_line,
                "ncolors": ncolors,
            }
    return None


def main():
    if len(sys.argv) != 6:
        return unavailable("usage: frame-digest.py XWD_FILE X Y WIDTH HEIGHT")
    try:
        x, y, width, height = (int(value) for value in sys.argv[2:6])
    except ValueError:
        return unavailable("invalid rectangle")
    try:
        data = Path(sys.argv[1]).read_bytes()
    except OSError as error:
        return unavailable(str(error))

    header = header_for(data)
    if header is None:
        return unavailable("not a supported XWD framebuffer")
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        return unavailable("empty rectangle")
    if x + width > header["width"] or y + height > header["height"]:
        return unavailable("rectangle is outside the framebuffer")

    pixel_size = header["bits_per_pixel"] // 8
    digest = 2166136261
    start = header["header_size"] + header["ncolors"] * 12
    for row in range(y, y + height):
        offset = start + row * header["bytes_per_line"] + x * pixel_size
        for _ in range(width):
            pixel = int.from_bytes(data[offset : offset + pixel_size], "little")
            digest = ((digest ^ pixel) * 16777619) & 0xFFFFFFFF
            offset += pixel_size
    print(f"FRAME_DIGEST={digest:08x} rect=({x},{y},{width},{height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
