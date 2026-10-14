#!/usr/bin/env python3
"""Read one RGB pixel from an Xvfb -fbdir XWD framebuffer."""

import struct
import sys
from pathlib import Path


def unavailable(message):
    print(f"FRAME_READBACK=unavailable ({message})")
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
        red_mask, green_mask, blue_mask = values[14:17]
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
                "masks": (red_mask, green_mask, blue_mask),
                "ncolors": ncolors,
            }
    return None


def channel(pixel, mask):
    if mask == 0:
        return 0
    shift = (mask & -mask).bit_length() - 1
    maximum = mask >> shift
    value = (pixel & mask) >> shift
    return round(value * 255 / maximum)


def main():
    if len(sys.argv) != 5:
        return unavailable("usage: frame-pixel.py XWD_FILE X Y EXPECTED_RGB_HEX")

    path = Path(sys.argv[1])
    try:
        data = path.read_bytes()
    except OSError as error:
        return unavailable(str(error))

    header = header_for(data)
    if header is None:
        return unavailable("not a supported XWD framebuffer")

    try:
        x, y = int(sys.argv[2]), int(sys.argv[3])
        expected = tuple(
            int(sys.argv[4][index : index + 2], 16) for index in (0, 2, 4)
        )
    except ValueError:
        return unavailable("invalid pixel coordinates or expected RGB")

    if not (0 <= x < header["width"] and 0 <= y < header["height"]):
        return unavailable("pixel is outside the framebuffer")

    pixel_offset = (
        header["header_size"]
        + header["ncolors"] * 12
        + y * header["bytes_per_line"]
        + x * (header["bits_per_pixel"] // 8)
    )
    pixel_size = header["bits_per_pixel"] // 8
    byte_order = "little" if header["byte_order"] == 0 else "big"
    pixel = int.from_bytes(data[pixel_offset : pixel_offset + pixel_size], byte_order)
    rgb = tuple(channel(pixel, mask) for mask in header["masks"])

    actual_text = "".join(f"{component:02x}" for component in rgb)
    expected_text = "".join(f"{component:02x}" for component in expected)
    print(f"FRAME_PIXEL=({x},{y}) #{actual_text} expected=#{expected_text}")
    return 0 if rgb == expected else 1


if __name__ == "__main__":
    sys.exit(main())
