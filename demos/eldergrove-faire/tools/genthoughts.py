# genthoughts.py: the guests' thought pictures (9 x 7 pixel art) as Bend
# tables for art.bend, and a preview image. Each picture is rows of palette
# indices: '.' see-through, '1' the dark outline, '2'-'7' its own colours.
# Usage: python3 tools/genthoughts.py [preview.png] -> writes tools/thoughts.bend.txt
import sys, struct, zlib

OUT = 0x303040
ICONS = {
  # 1 hungry: a drumstick, the meat top left and the bone bottom right
  1: (["..1111...",
       ".133221..",
       "13322221.",
       "12222221.",
       ".12222141",
       "..11114.4",
       "......441"],
      {2: 0xA0582C, 3: 0xD89050, 4: 0xF0E8D8, 5: 0xB8AE98}),
  # 2 thirsty: a drop of water
  2: (["....1....",
       "...121...",
       "..12221..",
       ".1232221.",
       ".1222221.",
       ".1222221.",
       "..11111.."],
      {2: 0x3A7FE0, 3: 0xC8E4FF}),
  # 3 queasy: a green face with a wobbly mouth
  3: (["..11111..",
       ".1222221.",
       "123222321",
       "122222221",
       "122323221",
       ".1232321.",
       "..11111.."],
      {2: 0x7CC850, 3: 0x2E5A20}),
  # 4 tired: Z z
  4: (["22222....",
       "...2.....",
       "..2......",
       ".2...222.",
       "22222..2.",
       "......2..",
       ".....222."],
      {2: 0x4050B0}),
  # 5 cross: a red face, frowning, brows down
  5: (["..11111..",
       ".1322231.",
       "122322321",
       "122222221",
       "122333221",
       ".1322231.",
       "..11111.."],
      {2: 0xE86050, 3: 0x5A1810}),
  # 6 delighted: a heart
  6: ([".11...11.",
       "1331.1221",
       "132212221",
       "122222221",
       ".1222221.",
       "..12221..",
       "...121..."],
      {2: 0xE83C5C, 3: 0xFFB8C8}),
  # 7 too dear: a gold coin with a red stroke through it
  7: (["..1111.44",
       ".1333214.",
       "1322224.1",
       "132224221",
       "12224.221",
       ".1422221.",
       "44111111."],
      {2: 0xE8B830, 3: 0xFFE890, 4: 0xE02828}),
  # 9 filthy: green stink rising off a heap of rubbish
  9: (["..5...5..",
       ".5...5...",
       "..5...5..",
       "...111...",
       "..13221..",
       ".1222321.",
       "122322221"],
      {2: 0x8A6A3A, 3: 0xE8E0C0, 5: 0x5AA02C}),
  # 10 needs the privy: a little outhouse with a moon on its door
  10: (["....1....",
        "...121...",
        "..12221..",
        ".1222221.",
        ".1345531.",
        ".1355531.",
        ".1355531."],
       {2: 0x3E7A44, 3: 0xC08A50, 4: 0xF0D040, 5: 0x4A2C14}),
  # 8 waited too long: an hourglass, the sand nearly run through
  8: (["111111111",
       ".1333331.",
       "..12331..",
       "...121...",
       "..13231..",
       ".1222221.",
       "111111111"],
      {2: 0xE0B040, 3: 0xD8ECF4}),
}

rows_out = []
rows_out.append("# a thought's picture (k: thought * 8 + row, top first): nine 3-bit palette indices")
rows_out.append("def Art.trow(+k: U32) -> U32:")
rows_out.append("  match k:")
for m, (rows, pal) in sorted(ICONS.items()):
    assert len(rows) == 7, m
    for r, row in enumerate(rows):
        assert len(row) == 9, (m, r, row)
        bits = 0
        for c in row:
            v = 0 if c == '.' else int(c)
            bits = bits * 8 + v
        rows_out.append(f"    case {m * 8 + r}:")
        rows_out.append(f"      {bits}")
rows_out.append("    case _:")
rows_out.append("      0")
rows_out.append("")
rows_out.append("# a thought's colours (k: thought * 8 + index): 1 the outline, then its own")
rows_out.append("def Art.tpal(+k: U32) -> U32:")
rows_out.append("  match k:")
for m, (rows, pal) in sorted(ICONS.items()):
    for i, col in sorted(pal.items()):
        rows_out.append(f"    case {m * 8 + i}:")
        rows_out.append(f"      {col}")
rows_out.append("    case _:")
rows_out.append(f"      {OUT}")
open('tools/thoughts.bend.txt', 'w', newline='\n').write('\n'.join(rows_out) + '\n')

if len(sys.argv) > 1:
    S = 10
    W = (9 + 2) * len(ICONS) * S
    H = (7 + 2) * S
    img = [[(0x70, 0xA0, 0x50)] * W for _ in range(H)]
    for k, m in enumerate(sorted(ICONS)):
        rows, pal = ICONS[m]
        ox = (k * 11 + 1) * S
        for y in range(9):
            for x in range(11):
                for dy in range(S):
                    for dx in range(S):
                        img[y * S + dy][k * 11 * S + x * S + dx] = (0xF8, 0xF8, 0xF8)
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                if ch == '.':
                    continue
                col = OUT if ch == '1' else pal[int(ch)]
                rgb = ((col >> 16) & 255, (col >> 8) & 255, col & 255)
                for dy in range(S):
                    for dx in range(S):
                        img[(r + 1) * S + dy][ox + c * S + dx] = rgb
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    raw = b''.join(b'\x00' + bytes(v for px in row for v in px) for row in img)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b'')
    open(sys.argv[1], 'wb').write(png)
print('ok')
