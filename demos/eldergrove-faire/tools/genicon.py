"""The Windows icon (win/eldergrove.ico): a castle with a pennant on a hill,
drawn as 32 x 32 pixel art from shapes, outlined, and scaled to the icon
sizes Windows asks for. Pure Python (zlib only).

usage: python tools/genicon.py [out.ico] [preview.png]
"""
import struct
import sys
import zlib

N = 32
SKY_TOP, SKY_LOW = (52, 66, 120), (27, 34, 62)
STAR = (255, 236, 170)
GRASS, GRASS_LIT = (62, 150, 74), (104, 190, 96)
STONE, STONE_DK = (214, 206, 190), (150, 140, 128)
ROOF, ROOF_DK = (138, 72, 176), (92, 44, 134)
GLOW = (255, 214, 110)
WOOD = (96, 60, 36)
POLE = (90, 74, 58)
GOLD = (242, 186, 64)
INK = (24, 22, 40)


def blank():
    return [[None] * N for _ in range(N)]


def rect(g, x0, y0, x1, y1, c):
    for y in range(max(0, y0), min(N, y1 + 1)):
        for x in range(max(0, x0), min(N, x1 + 1)):
            g[y][x] = c


def roof(g, apex_x, apex_y, base_y, x0, x1):
    # a cone: lit on the left half, shaded on the right
    for y in range(apex_y, base_y + 1):
        t = (y - apex_y) / max(1, base_y - apex_y)
        lo = apex_x - t * (apex_x - x0)
        hi = apex_x + t * (x1 - apex_x)
        for x in range(int(round(lo)), int(round(hi)) + 1):
            g[y][x] = ROOF if x <= apex_x else ROOF_DK


def tower(g, x0, x1, top, bottom, apex_y):
    rect(g, x0, top, x1, bottom, STONE)
    rect(g, x1 - 1, top, x1, bottom, STONE_DK)
    roof(g, (x0 + x1) // 2, apex_y, top, x0 - 1, x1 + 1)


def castle():
    g = blank()
    tower(g, 6, 10, 18, 27, 11)
    tower(g, 21, 25, 18, 27, 11)
    rect(g, 10, 21, 21, 27, STONE)      # the curtain wall
    for x in (11, 13, 18, 20):          # its crenels
        rect(g, x, 20, x, 20, STONE)
    tower(g, 12, 19, 12, 27, 3)
    rect(g, 15, 15, 16, 18, GLOW)       # the keep's window
    rect(g, 14, 23, 17, 27, WOOD)       # the gate
    g[23][14] = g[23][17] = STONE
    rect(g, 8, 20, 8, 21, GLOW)
    rect(g, 23, 20, 23, 21, GLOW)
    rect(g, 15, 0, 15, 3, POLE)         # the pennant
    for i, w in enumerate((4, 3, 2, 1)):
        rect(g, 16, i, 16 + w - 1, i, GOLD)
    return g


def lower(g, dy):
    return [[None] * N for _ in range(dy)] + g[:N - dy]


def outline(g):
    out = [row[:] for row in g]
    for y in range(N):
        for x in range(N):
            if g[y][x] is None and any(
                    0 <= y + dy < N and 0 <= x + dx < N and g[y + dy][x + dx] is not None
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = INK
    return out


def scene():
    obj = outline(lower(castle(), 2))
    img = []
    for y in range(N):
        row = []
        for x in range(N):
            # a rounded tile of night sky with a few stars and a hill
            cx = min(x, N - 1 - x)
            cy = min(y, N - 1 - y)
            if cx < 4 and cy < 4 and (4 - cx) ** 2 + (4 - cy) ** 2 > 18:
                row.append((0, 0, 0, 0))
                continue
            t = y / (N - 1)
            c = tuple(int(SKY_TOP[i] + t * (SKY_LOW[i] - SKY_TOP[i])) for i in range(3))
            if (x, y) in ((4, 5), (26, 4), (27, 12), (7, 10), (22, 8)):
                c = STAR
            hill = ((x - 15.5) / 21) ** 2 + ((y - 34) / 9.5) ** 2
            if hill <= 1:
                c = GRASS_LIT if hill > 0.8 else GRASS
            if obj[y][x] is not None:
                c = obj[y][x]
            row.append(c + (255,))
        img.append(row)
    return img


def scale(img, k):
    return [[img[y // k][x // k] for x in range(len(img) * k)] for y in range(len(img) * k)]


def halve(img):
    n = len(img) // 2
    out = []
    for y in range(n):
        row = []
        for x in range(n):
            px = [img[2 * y + dy][2 * x + dx] for dy in (0, 1) for dx in (0, 1)]
            a = sum(p[3] for p in px)
            if a == 0:
                row.append((0, 0, 0, 0))
            else:
                row.append(tuple(sum(p[i] * p[3] for p in px) // a for i in range(3)) + (a // 4,))
        out.append(row)
    return out


def png(img):
    n = len(img)
    raw = b"".join(b"\0" + bytes(v for p in row for v in p) for row in img)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def ico(images):
    head = struct.pack("<HHH", 0, 1, len(images))
    at = 6 + 16 * len(images)
    entries, blobs = b"", b""
    for img in images:
        data = png(img)
        n = len(img)
        entries += struct.pack("<BBBBHHII", n % 256, n % 256, 0, 0, 1, 32, len(data), at + len(blobs))
        blobs += data
    return head + entries + blobs


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "win/eldergrove.ico"
    base = scene()
    sizes = [halve(base), base, scale(base, 2), scale(base, 8)]
    with open(out, "wb") as f:
        f.write(ico(sizes))
    if len(sys.argv) > 2:
        with open(sys.argv[2], "wb") as f:
            f.write(png(scale(base, 8)))
    print("wrote", out)


if __name__ == "__main__":
    main()
