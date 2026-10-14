"""Turn the output of shot.bend into one PNG per view: shot.py <dump> <out-dir> [label].

The dump is a `view=<name> size=<n>` line followed by a line of `n * n` pixels, each a
24-bit `0xRRGGBB` number. Only the standard library is used, so it runs where Pillow is
not installed.
"""
import struct
import sys
import zlib


def png(path, size, pixels):
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for value in pixels[y * size:(y + 1) * size]:
            rows += bytes(((value >> 16) & 255, (value >> 8) & 255, value & 255))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(bytes(rows), 6)))
        out.write(chunk(b"IEND", b""))


def main():
    dump, out_dir = sys.argv[1], sys.argv[2]
    label = sys.argv[3] if len(sys.argv) > 3 else ""
    name, size = None, 0
    written = 0
    with open(dump, encoding="utf-8") as lines:
        for line in lines:
            if line.startswith("view="):
                fields = dict(part.split("=") for part in line.split())
                name, size = fields["view"], int(fields["size"])
            elif name:
                pixels = [int(word) for word in line.split()]
                if len(pixels) != size * size:
                    sys.exit(f"{name}: {len(pixels)} pixels, wanted {size * size}")
                png(f"{out_dir}/{label}{name}.png", size, pixels)
                written += 1
                name = None
    print(f"wrote {written} views to {out_dir}")


main()
