# ppm2png.py in.ppm out.png [scale] [x y w h]: a P6 PPM to PNG (optionally a
# crop, in source pixels), standard library only.
import sys, zlib, struct

data = open(sys.argv[1], 'rb').read()
parts = data.split(b'\n', 3)
W, H = map(int, parts[1].split())
px = parts[3]
scale = int(sys.argv[3]) if len(sys.argv) > 3 else 2
x0, y0, w, h = (map(int, sys.argv[4:8]) if len(sys.argv) > 7 else (0, 0, W, H))
rows = []
for y in range(y0, y0 + h):
    row = px[(y * W + x0) * 3:(y * W + x0 + w) * 3]
    wide = b''.join(row[x * 3:x * 3 + 3] * scale for x in range(w))
    for _ in range(scale):
        rows.append(b'\x00' + wide)
raw = b''.join(rows)

def chunk(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w * scale, h * scale, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b'')
open(sys.argv[2], 'wb').write(png)
