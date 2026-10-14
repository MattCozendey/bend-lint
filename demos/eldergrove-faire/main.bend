# Eldergrove Faire -- a high-fantasy theme park, built in Bend.
#
#   bend main.bend -o park && ./park          play
#   ./park --shot out.ppm 900 [tool]          headless: 900 ticks, one frame
#
# A frame is a list of drawables in front-to-back order; the quadtree
# rasterizer filters it down cell by cell (in parallel) and each pixel takes
# the first opaque colour.
import Base
import ./core.bend as C
import ./art.bend as A
import ./font.bend as F
import ./sound.bend as Z
import ./save.bend as S

def sel(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def B() -> U32:
  4096

# Drawables
# ---------

type Dr is Data:
  DBlock{x: U32, y: U32, dl: U32, dr: U32, ter: U32, obj: U32, hov: U32,
    wx: U32, wy: U32, nb: U32}
  DTree{x: U32, y: U32, v: U32, n: U32}
  DRide{x: U32, y: U32, k: U32, ra: U32, rb: U32, st: U32, i: U32}
  DGate{x: U32, y: U32}
  DTrack{x: U32, y: U32, code: U32, zr: U32}
  DGuest{x: U32, y: U32, look: U32, ph: U32}
  DCar{x: U32, y: U32, d: U32, lead: U32, rd: U32}
  DGlyph{x: U32, y: U32, bits: U32, col: U32}
  DRect{x: U32, y: U32, w: U32, h: U32, col: U32}
  DIcon{x: U32, y: U32, tool: U32, on: U32}
  DGhost{x: U32, y: U32, k: U32}
  DDeck{x: U32, y: U32, zr: U32, nb: U32}

def ov(+x0: U32, +y0: U32, +x1: U32, +y1: U32, +bx: U32, +by: U32, +s: U32)
  -> Bool:
  ((x1 > bx) && (x0 < bx + s) && (y1 > by) && (y0 < by + s) : U32)

# Zoom: 0 normal, 1 close (twice as big), 2 far (half as big). World
# drawables live in world-screen pixels; a screen square or pixel is mapped
# into that space (the art itself never changes). The zoom rides in the top
# two bits of the frame's t.
def Zm.w(+p: U32, +z: U32) -> U32:
  +o = (p - B() : U32)
  (B() + sel(U32.is_eq(z, 1), (o >> 1n : U32), sel(U32.is_eq(z, 2), (o << 1n : U32), o)) : U32)

def Zm.s(+s: U32, +z: U32) -> U32:
  sel(U32.is_eq(z, 1), U32.max((s >> 1n : U32), 1), sel(U32.is_eq(z, 2), (s << 1n : U32), s))

def Zm.z(+t: U32) -> U32:
  (t >> 30n : U32)

def Dr.hits.go(d: Dr, +bx0: U32, +by0: U32, +s0: U32, +bx: U32, +by: U32, +s: U32) -> Bool:
  match d:
    case DBlock{+x, +y, +dl, +dr, ter, obj, hov, wx, wy, +nb}:
      +top = sel(U32.is_eq(((nb >> 6n) .&. 3 : U32), 0) && U32.is_eq(((nb >> 16n) .&. 3 : U32), 0), 7, 30)
      ov((x - 16 : U32), (y - top : U32), (x + 17 : U32), (y + 17 + U32.max(dl, dr) : U32), bx, by, s)
    case DTree{+x, +y, v, n}:
      ov((x - 13 : U32), (y - 40 : U32), (x + 14 : U32), (y + 6 : U32), bx, by, s)
    case DRide{+x, +y, k, ra, rb, st, i}:
      ov((x - 46 : U32), (y - 92 : U32), (x + 47 : U32), (y + 16 : U32), bx, by, s)
    case DGate{+x, +y}:
      ov((x - 20 : U32), (y - 48 : U32), (x + 20 : U32), (y + 6 : U32), bx, by, s)
    case DTrack{+x, +y, +code, +zr}:
      ov((x - 16 : U32), (y - zr * 8 - sel(U32.is_eq(((code >> 16n) .&. 1 : U32), 0), sel(U32.is_eq((code .&. 15 : U32), 12), 22, 12), 46) : U32), (x + 17 : U32), (y + 17 : U32), bx, by, s)
    case DGuest{+x, +y, +look, ph}:
      +top = sel(U32.is_eq(((look >> 20n) .&. 15 : U32), 0), 15, 29)
      ov((x - 7 : U32), (y - top : U32), (x + 8 : U32), (y + 1 : U32), bx, by, s)
    case DCar{+x, +y, d, lead, rd}:
      ov((x - 10 : U32), (y - 19 : U32), (x + 11 : U32), (y + 6 : U32), bx, by, s)
    case DGhost{+x, +y, k}:
      ov((x - 40 : U32), (y - 96 : U32), (x + 41 : U32), (y + 40 : U32), bx, by, s)
    case DDeck{+x, +y, +zr, nb}:
      ov((x - 17 : U32), (y - zr * 8 - 8 : U32), (x + 18 : U32), (y + 18 : U32), bx, by, s)
    case DGlyph{+x, +y, bits, col}:
      ov(x, y, (x + 4 : U32), (y + 6 : U32), bx0, by0, s0)
    case DRect{+x, +y, +w, +h, col}:
      ov(x, y, (x + w : U32), (y + h : U32), bx0, by0, s0)
    case DIcon{+x, +y, tool, on}:
      ov(x, y, (x + 22 : U32), (y + 22 : U32), bx0, by0, s0)

def Dr.hits(d: Dr, +bx: U32, +by: U32, +s: U32, +t: U32) -> Bool:
  +z = Zm.z(t)
  Dr.hits.go(d, bx, by, s, Zm.w(bx, z), Zm.w(by, z), Zm.s(s, z))

def Dr.shade.go(d: Dr, +sx: U32, +sy: U32, +px: U32, +py: U32, +t: U32) -> U32:
  match d:
    case DBlock{x, y, dl, dr, ter, obj, hov, wx, wy, nb}:
      A.Light.apply(A.Art.block(x, y, dl, dr, ter, obj, hov, wx, wy, t, px, py, nb), t, sx, sy)
    case DTree{x, y, v, n}:
      A.Light.apply(A.Art.tree(v, (px - x : U32), (py - y : U32), n, t), t, sx, sy)
    case DRide{x, y, k, ra, rb, st, i}:
      A.Light.apply(A.Art.ride(k, (px - x : U32), (py - y : U32), t, ra, rb, st), t, sx, sy)
    case DGate{x, y}:
      A.Light.apply(A.Art.gate((px - x : U32), (py - y : U32), t), t, sx, sy)
    case DTrack{x, y, code, zr}:
      A.Light.apply(A.Art.track(x, y, code, zr, t, px, py), t, sx, sy)
    case DGuest{x, y, look, ph}:
      A.Light.apply(A.Art.guest((px - x : U32), (py - y : U32), look, ph), t, sx, sy)
    case DCar{x, y, d, lead, rd}:
      A.Light.apply(A.Art.car((px - x : U32), (py - y : U32), d, lead, rd), t, sx, sy)
    case DGhost{x, y, k}:
      A.Art.ghost(k, px, py, x, y, t)
    case DDeck{x, y, zr, nb}:
      A.Light.apply(A.Art.deck(x, y, zr, nb, px, py), t, sx, sy)
    case DGlyph{x, y, bits, col}:
      A.Art.glyph(bits, (sx - x : U32), (sy - y : U32), col)
    case DRect{x, y, w, h, col}:
      col
    case DIcon{x, y, tool, on}:
      A.Art.icon(tool, on, (sx - x : U32), (sy - y : U32), t)

# The rasterizer
# --------------

# The rasterizer
# --------------
# The frame is cut into 64-px cells and 16-px tiles, as Bend's shader guide
# prescribes. Each cell cuts the frame's list once for itself and each tile
# cuts its cell's list; the tile's pixels then walk that short list in
# straight-line code (no forks below the tile). A list handed down the tree
# is only ever matched, so every read is a borrow, not a reference count;
# a kept entry is copied from its fields, so no entry is shared between
# cores; and each list has one last consumer (R.fin) that frees it.

def Dr.shade(d: Dr, +px: U32, +py: U32, +tz: U32) -> U32:
  +z = Zm.z(tz)
  Dr.shade.go(d, px, py, Zm.w(px, z), Zm.w(py, z), (tz .&. 1073741823 : U32))

def SKY() -> U32:
  1714237

def Dr.shade_if(hit: Bool, d: Dr, +px: U32, +py: U32, +t: U32) -> U32:
  match hit:
    case True{}:
      Dr.shade(d, px, py, t)
    case False{}:
      A.TR()

# front-to-back: the first opaque sample wins; `done` stops the walk
def first(+xs: +List<Dr>, done: Bool, +c: U32, +px: U32, +py: U32, +t: U32)
  -> U32:
  match xs done:
    case _ True{}:
      c
    case Nil{} False{}:
      SKY()
    case Con{+d, rest} False{}:
      +c2 = Dr.shade_if(Dr.hits(d, px, py, 1, t), d, px, py, t)
      first(rest, A.opaque(c2), c2, px, py, t)

# a fresh copy from the fields, so no drawable is shared between lists
def Dr.cp(d: Dr) -> Dr:
  match d:
    case DBlock{x, y, dl, dr, ter, obj, hov, wx, wy, nb}:
      DBlock{x, y, dl, dr, ter, obj, hov, wx, wy, nb}
    case DTree{x, y, v, n}:
      DTree{x, y, v, n}
    case DRide{x, y, k, ra, rb, st, i}:
      DRide{x, y, k, ra, rb, st, i}
    case DGate{x, y}:
      DGate{x, y}
    case DTrack{x, y, code, zr}:
      DTrack{x, y, code, zr}
    case DGuest{x, y, look, ph}:
      DGuest{x, y, look, ph}
    case DCar{x, y, d, lead, rd}:
      DCar{x, y, d, lead, rd}
    case DGlyph{x, y, bits, col}:
      DGlyph{x, y, bits, col}
    case DRect{x, y, w, h, col}:
      DRect{x, y, w, h, col}
    case DIcon{x, y, tool, on}:
      DIcon{x, y, tool, on}
    case DGhost{x, y, k}:
      DGhost{x, y, k}
    case DDeck{x, y, zr, nb}:
      DDeck{x, y, zr, nb}

def cut.put(keep: Bool, d: Dr, xs: +List<Dr>) -> +List<Dr>:
  match keep:
    case True{}:
      Dr.cp(d) <> xs
    case False{}:
      xs

# the entries that reach the square (bx, by, s), in order
def cut(xs: +List<Dr>, +bx: U32, +by: U32, +s: U32, +t: U32) -> +List<Dr>:
  match xs:
    case []:
      []
    case +d <> rest:
      cut.put(Dr.hits(d, bx, by, s, t), d, cut(rest, bx, by, s, t))

def empty(+xs: +List<Dr>) -> Bool:
  match xs:
    case []:
      True{}
    case d <> rest:
      False{}

# a square wholly inside a solid rectangle at the front of its list
def Dr.solid(d: Dr, +x0: U32, +y0: U32, +s: U32) -> U32:
  match d:
    case DRect{+x, +y, +w, +h, col}:
      sel(((x <= x0) && (y <= y0) && (x0 + s <= x + w) && (y0 + s <= y + h) : U32), col, A.TR())
    case _:
      A.TR()

def solid(+xs: +List<Dr>, +x0: U32, +y0: U32, +s: U32) -> U32:
  match xs:
    case []:
      SKY()
    case d <> rest:
      Dr.solid(d, x0, y0, s)

# the list's last consumer: walks it after the readers, then answers img
def R.fin(img: Image, xs: +List<Dr>) -> Image:
  match xs:
    case []:
      img
    case d <> rest:
      R.fin(img, rest)

def R.px4(same: Bool, +c0: U32, +c1: U32, +c2: U32, +c3: U32) -> Image:
  match same:
    case True{}:
      Pix{c0}
    case False{}:
      Qua{Pix{c0}, Pix{c1}, Pix{c2}, Pix{c3}}

# at half resolution (t bit 29) one sample stands for the 2 x 2 block
def R.b2.full(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  +c0 = first(xs, False{}, 0, x, y, t)
  +c1 = first(xs, False{}, 0, x1, y, t)
  +c2 = first(xs, False{}, 0, x, y1, t)
  +c3 = first(xs, False{}, 0, x1, y1, t)
  R.px4(U32.is_eq(c0, c1) && U32.is_eq(c0, c2) && U32.is_eq(c0, c3), c0, c1, c2, c3)

def R.b2.go(lo: Bool, +xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  match lo:
    case True{}:
      Pix{first(xs, False{}, 0, x, y, t)}
    case False{}:
      R.b2.full(xs, x, y, t)

def R.b2(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  R.b2.go(Bool.not(U32.is_eq((t .&. 536870912 : U32), 0)), xs, x, y, t)

def R.b4(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  Qua{R.b2(xs, x, y, t), R.b2(xs, (x + 2 : U32), y, t), R.b2(xs, x, (y + 2 : U32), t),
    R.b2(xs, (x + 2 : U32), (y + 2 : U32), t)}

def R.b8(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  Qua{R.b4(xs, x, y, t), R.b4(xs, (x + 4 : U32), y, t), R.b4(xs, x, (y + 4 : U32), t),
    R.b4(xs, (x + 4 : U32), (y + 4 : U32), t)}

def R.b16(+xs: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  Qua{R.b8(xs, x, y, t), R.b8(xs, (x + 8 : U32), y, t), R.b8(xs, x, (y + 8 : U32), t),
    R.b8(xs, (x + 8 : U32), (y + 8 : U32), t)}

# a 16-px tile: one colour when empty or under a solid panel, else pixels
def R.tile.go(skip: Bool, +fc: U32, +xs: +List<Dr>, +x: U32, +y: U32, +t: U32)
  -> Image:
  match skip:
    case True{}:
      R.fin(Pix{fc}, xs)
    case False{}:
      R.fin(R.b16(xs, x, y, t), xs)

# the interface (text, panels, icons) is always drawn at full resolution
def Dr.ui(d: Dr) -> Bool:
  match d:
    case DGlyph{x, y, bits, col}:
      True{}
    case DRect{x, y, w, h, col}:
      True{}
    case DIcon{x, y, tool, on}:
      True{}
    case _:
      False{}

def Tile.ui(+xs: +List<Dr>) -> Bool:
  match xs:
    case []:
      False{}
    case d <> rest:
      Dr.ui(Dr.cp(d)) || Tile.ui(rest)

def R.tile(+cl: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  +xs = cut(cl, x, y, 16, t)
  +fc = solid(xs, x, y, 16)
  +t2 = sel(Tile.ui(xs), (t .&. 3758096383 : U32), t)
  R.tile.go(A.opaque(fc), fc, xs, x, y, t2)

def R.quad(+cl: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  +x1 = (x + 16 : U32)
  +y1 = (y + 16 : U32)
  a b c e = R.tile(cl, x, y, t) R.tile(cl, x1, y, t) R.tile(cl, x, y1, t)
    R.tile(cl, x1, y1, t)
  Qua{a, b, c, e}

# a 64-px cell: four 32-px quads of four tiles, all cut from the cell's list
def R.cell(none: Bool, +cl: +List<Dr>, +x: U32, +y: U32, +t: U32) -> Image:
  match none:
    case True{}:
      R.fin(Pix{SKY()}, cl)
    case False{}:
      +x1 = (x + 32 : U32)
      +y1 = (y + 32 : U32)
      a b c e = R.quad(cl, x, y, t) R.quad(cl, x1, y, t) R.quad(cl, x, y1, t)
        R.quad(cl, x1, y1, t)
      R.fin(Qua{a, b, c, e}, cl)

def R.off(+y: U32) -> Bool:
  (y >= B() + 320 : U32)

# the frame's tree down to the cells (64 << d px); squares below the view
# answer sky before any cut
def R.root(+d: Nat, off: Bool, +g: +List<Dr>, +x: U32, +y: U32, +t: U32)
  -> Image:
  match d off:
    case _ True{}:
      Pix{SKY()}
    case 0n False{}:
      +cl = cut(g, x, y, 64, t)
      R.cell(empty(cl), cl, x, y, t)
    case 1n+p False{}:
      +s = U32.shln(64, p)
      +x1 = (x + s : U32)
      +y1 = (y + s : U32)
      a b c e = R.root(p, R.off(y), g, x, y, t) R.root(p, R.off(y), g, x1, y, t)
        R.root(p, R.off(y1), g, x, y1, t) R.root(p, R.off(y1), g, x1, y1, t)
      Qua{a, b, c, e}

def R.frame(+g: +List<Dr>, +t: U32) -> Image:
  R.fin(R.root(3n, False{}, g, B(), B(), t), g)

def pick_at(+q: C.Q, +mx: U32, +my: U32, +camx: U32, +camy: U32, +h: U32)
  -> U32:
  +a = ((mx + camx) - 1280 : U32)
  +b = (((my + camy + 8 * h) - 512) * 2 : U32)
  +u = A.iso_u(a, b)
  +v = A.iso_v(a, b)
  +i = (u >> 4n : U32)
  +j = (v >> 4n : U32)
  +ok = C.inmap(i, j) && U32.is_eq(C.Land.h(q, i, j), h)
  sel(ok, (i * 64 + j : U32), 99999)

def pick.go(+n: Nat, +q: C.Q, +mx: U32, +my: U32, +camx: U32, +camy: U32,
  +h: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +c = pick_at(q, mx, my, camx, camy, h)
      pick.go(p, q, mx, my, camx, camy, (h - 1 : U32),
        sel(U32.is_eq(acc, 99999), c, acc))

type UI is Data:
  UI{camx: U32, camy: U32, keys: U32, mx: U32, my: U32, mdown: U32,
    tool: U32, var: U32, speed: U32, msg: U32, frame: U32, income: U32,
    last: U32, io: U32, fps: U32, tl: Nat, opt: U32, fol: U32}

# The view at a zoom: the world-screen rectangle it shows (it stays centred on
# the normal view's centre)
def View.z(+var: U32) -> U32:
  ((var >> 18n) .&. 3 : U32)

def View.w(+z: U32) -> U32:
  sel(U32.is_eq(z, 1), 256, sel(U32.is_eq(z, 2), 1024, 512))

def View.h(+z: U32) -> U32:
  sel(U32.is_eq(z, 1), 160, sel(U32.is_eq(z, 2), 640, 320))

def View.x(+camx: U32, +z: U32) -> U32:
  sel(U32.is_eq(z, 1), (camx + 128 : U32), sel(U32.is_eq(z, 2), (camx - 256 : U32), camx))

def View.y(+camy: U32, +z: U32) -> U32:
  sel(U32.is_eq(z, 1), (camy + 80 : U32), sel(U32.is_eq(z, 2), (camy - 160 : U32), camy))

# a screen position (0..511) in world-screen pixels from the view's corner
def View.m(+m: U32, +z: U32) -> U32:
  sel(U32.is_eq(z, 1), (m >> 1n : U32), sel(U32.is_eq(z, 2), (m << 1n : U32), m))

# zooming in and out, one step: far, normal, close
def View.zoom(+var: U32, +inw: Bool) -> U32:
  +z = View.z(var)
  +z2 = sel(inw, sel(U32.is_eq(z, 2), 0, 1), sel(U32.is_eq(z, 1), 0, 2))
  ((var .&. 4294180863) .|. (z2 << 18n) : U32)

def pick(+q: C.Q, +ui: UI) -> U32:
  UI{camx, camy, keys, mx, my, md, tool, +var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = ui
  +z = View.z(var)
  sel((my < 290 : U32) && (my > 12 : U32),
    pick.go(8n, q, View.m(mx, z), View.m(my, z), View.x(camx, z), View.y(camy, z), 7, 99999), 99999)

type Dyn is Data:
  Dyn{k: U32, d: Dr}

def Dyn.le(a: Dyn, b: Dyn) -> Bool:
  Dyn{ka, da} = a
  Dyn{kb, db} = b
  (ka <= kb : U32)

def scr_x(+i: U32, +j: U32, +camx: U32) -> U32:
  ((B() + 1280 + 16 * i) - (16 * j + camx) : U32)

def scr_y(+i: U32, +j: U32, +h: U32, +camy: U32) -> U32:
  ((B() + 512 + 8 * i + 8 * j) - (8 * h + camy) : U32)

# Riders
# ------
# A rider is drawn from an 8-bit code: bit 7 occupied, bits 0-1 class, 2-4
# tunic, 5-6 skin -- the same person, in the same outfit, as on the paths.

def rider_code(+lk: U32) -> U32:
  (128 .|. (lk .&. 7) .|. (((lk >> 4n) .&. 3) << 3n) .|. (((lk >> 8n) .&. 3) << 5n) : U32)

def byte_at(+n: U32) -> U32:
  match n:
    case 0:
      1
    case 1:
      256
    case 2:
      65536
    case _:
      16777216

# one pass per frame files every rider's code under their ride (seats 0-3
# in ra, 4-7 in rb) or, on the coaster, under their train (lo, hi)
type RT is Data:
  RT{ra: List<&2, U32>, rb: List<&2, U32>, lo: List<&2, U32>, hi: List<&2, U32>, tw: List<&2, U32>,
    o0: List<&2, U32>, o1: List<&2, U32>}

def RT.or(on: Bool, +t: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match on:
    case True{}:
      C.Tab.or(t, i, v)
    case False{}:
      t

def RT.add4(+t: +List<U32>, +i: U32, +seat: U32, +code: U32, +hi: Bool) -> +List<U32>:
  +base = sel(hi, 4, 0)
  +inr = (seat >= base : U32) && (seat < base + 4 : U32)
  RT.or(inr, t, i, (code * byte_at((seat - base : U32)) : U32))

def RT.add.go(on: Bool, coaster: Bool, +dir: U32, +tgt: U32, +lk: U32, +co: U32, t: RT) -> RT:
  match on coaster:
    case True{} False{}:
      RT{+ra, +rb, +lo, +hi, tw, o0, o1} = t
      RT{RT.add4(ra, tgt, (dir .&. 7 : U32), rider_code(lk), False{}),
        RT.add4(rb, tgt, (dir .&. 7 : U32), rider_code(lk), True{}), lo, hi, tw, o0, o1}
    case True{} True{}:
      RT{+ra, +rb, +lo, +hi, tw, +o0, +o1} = t
      +i = (co * 64 + (dir >> 6n) : U32)
      +s = (dir .&. 63 : U32)
      +b = (1 << U32.to_nat((s .&. 31 : U32)) : U32)
      RT{ra, rb, RT.add4(lo, i, s, rider_code(lk), False{}), RT.add4(hi, i, s, rider_code(lk), True{}), tw,
        RT.or((s < 32 : U32), o0, i, b), RT.or((s >= 32 : U32), o1, i, b)}
    case False{} _:
      t

def RT.add(g: C.Guest, +rs: +List<C.Ride>, t: RT) -> RT:
  C.Guest{id, x, y, +dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, +lk, mind, bl} = g
  +r = C.Rides.get(rs, tgt)
  RT.add.go(U32.is_eq(st, 1), U32.is_eq(C.Ride.kind(r), 5), dir, tgt, lk, C.Ride.ht(r), t)

def RT.fill(+gs: +List<C.Guest>, +rs: +List<C.Ride>, t: RT) -> RT:
  match gs:
    case []:
      t
    case g <> rest:
      RT.fill(rest, rs, RT.add(g, rs, t))

def RT.of(+gs: +List<C.Guest>, +rs: +List<C.Ride>, +tw: +List<U32>, +nt: U32) -> RT:
  +n = C.len32(C.Ride, rs)
  RT.fill(gs, rs, RT{C.Tab.zero(n, []), C.Tab.zero(n, []), C.Tab.zero(U32.max((nt * 64 : U32), 64), []), C.Tab.zero(U32.max((nt * 64 : U32), 64), []), tw,
    C.Tab.zero(U32.max((nt * 64 : U32), 64), []), C.Tab.zero(U32.max((nt * 64 : U32), 64), [])})

def RT.o0(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi, tw, o0, o1} = t
  o0

def RT.o1(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi, tw, o0, o1} = t
  o1

def RT.tw(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi, tw, o0, o1} = t
  tw

def RT.ra(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi, tw, o0, o1} = t
  ra

def RT.rb(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi, tw, o0, o1} = t
  rb

def RT.lo(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi, tw, o0, o1} = t
  lo

def RT.hi(t: RT) -> +List<U32>:
  RT{ra, rb, lo, hi, tw, o0, o1} = t
  hi

# what a ride shows: its phase and time into it, and bit 30 when it can't run
# for want of an entrance or an exit
def ride_st(r: C.Ride) -> U32:
  +r2 = r
  +k = C.Ride.kind(r2)
  +broken = Bool.not(C.Ride.shop(k)) && Bool.not(U32.is_eq(k, 0))
    && (U32.is_eq(C.Ride.ent(r2), C.NONE()) || U32.is_eq(C.Ride.ex(r2), C.NONE()))
  ((C.Ride.ph(r2) << 16n) .|. U32.min(C.Ride.tm(r2), 65535) .|. sel(broken, 1073741824, 0)
    .|. sel(C.Wear.broken(C.Ride.wear(r2)), 536870912, 0) : U32)

# the coaster's first station tile, while the coaster is broken down
def Rides.kind_at(+rs: +List<C.Ride>, +k: U32, +i: U32) -> U32:
  match rs:
    case []:
      C.NONE()
    case r <> rest:
      sel(U32.is_eq(C.Ride.kind(r), k), i, Rides.kind_at(rest, k, (i + 1 : U32)))

# a ride's window: open or closed, price, riders and queue, the loading
# waits (cycling rides), and its record so far
def Coaster.down(+rs: +List<C.Ride>, +i: U32, +j: U32) -> Bool:
  match rs:
    case []:
      False{}
    case c <> rest:
      +c2 = c
      (U32.is_eq(C.Ride.kind(c2), 5) && C.Wear.broken(C.Ride.wear(c2))
        && U32.is_eq(C.Ride.cx(c2), i) && U32.is_eq(C.Ride.cy(c2), j)) || Coaster.down(rest, i, j)

# the ride of coaster k (its station), or NONE
def Coaster.ride(+rs: +List<C.Ride>, +k: U32, +i: U32) -> U32:
  match rs:
    case []:
      C.NONE()
    case r <> rest:
      +r2 = r
      sel(U32.is_eq(C.Ride.kind(r2), 5) && U32.is_eq(C.Ride.ht(r2), k), i,
        Coaster.ride(rest, k, (i + 1 : U32)))

def Scen.same(+q: C.Q, +i: U32, +j: U32, +a: U32) -> Bool:
  +t = C.Land.get(q, i, j)
  U32.is_eq(C.Tile.obj(t), 2) && U32.is_eq(C.Tile.a(t), a)

# a tree's variation, or which neighbours a wall or fence joins
def Scen.n(joins: Bool, +q: C.Q, +i: U32, +j: U32, +a: U32) -> U32:
  match joins:
    case True{}:
      (sel(Scen.same(q, (i - 1 : U32), j, a), 1, 0) .|. sel(Scen.same(q, (i + 1 : U32), j, a), 2, 0)
        .|. sel(Scen.same(q, i, (j - 1 : U32), a), 4, 0) .|. sel(Scen.same(q, i, (j + 1 : U32), a), 8, 0) : U32)
    case False{}:
      A.hash(i, j)

def obj_dr.go(+obj: U32, +a: U32, +b: U32, +h: U32, +i: U32, +j: U32,
  +sx: U32, +sy: U32, +k: U32, +st: U32, +rt: RT, +rs: +List<C.Ride>, +q: C.Q) -> +List<Dr>:
  match obj:
    case 2:
      [DTree{sx, (sy + 8 : U32), a, Scen.n(U32.is_eq(a, 12) || U32.is_eq(a, 13), q, i, j, a)}]
    case 5:
      [DGate{sx, (sy + 8 : U32)}]
    case 3:
      Bool.pick(+List<Dr>, U32.is_eq(b, 1),
        [DRide{sx, sel(U32.is_eq(C.Ride.size(k), 2), sy, (sy + 8 : U32)), k,
          C.Tab.at(RT.ra(rt), a), C.Tab.at(RT.rb(rt), a), st, a}], [])
    case 6:
      +ty = C.Tab.at(RT.tw(rt), ((a >> 8n) .&. 2047 : U32))
      [DTrack{sx, sy, ((a .&. 255) .|. (ty << 12n) .|. sel(Coaster.down(rs, i, j), 65536, 0) : U32), (b - h : U32)}]
    case _:
      []

def Deck.joins(+q: C.Q, +i: U32, +j: U32, +l: U32) -> Bool:
  +t = C.Land.get(q, i, j)
  U32.is_eq(C.Deck.of(t), l) || U32.is_eq(C.Tile.obj(t), 1) && U32.is_eq(C.Tile.h(t), l)

# (a match: the neighbours are only looked at on a tile that has a deck)
def Deck.dr.go(on: Bool, +l: U32, +q: C.Q, +i: U32, +j: U32, +h: U32, +sx: U32, +sy: U32, +acc: +List<Dr>) -> +List<Dr>:
  match on:
    case True{}:
      +nb = (sel(Deck.joins(q, (i - 1 : U32), j, l), 1, 0) .|. sel(Deck.joins(q, (i + 1 : U32), j, l), 2, 0)
        .|. sel(Deck.joins(q, i, (j - 1 : U32), l), 4, 0) .|. sel(Deck.joins(q, i, (j + 1 : U32), l), 8, 0) : U32)
      DDeck{sx, sy, (l - h : U32), nb} <> acc
    case False{}:
      acc

def Deck.dr(+l: U32, +q: C.Q, +i: U32, +j: U32, +h: U32, +sx: U32, +sy: U32, +acc: +List<Dr>) -> +List<Dr>:
  Deck.dr.go(Bool.not(U32.is_eq(l, 0)), l, q, i, j, h, sx, sy, acc)

def obj_dr(+t: C.Tile, +i: U32, +j: U32, +sx: U32, +sy: U32,
  +rs: +List<C.Ride>, +rt: RT, +q: C.Q) -> +List<Dr>:
  C.Tile{+h, ter, +obj, +a, +b} = t
  +rd = C.Rides.get(rs, a)
  +l = ((a >> 24n) .&. 15 : U32)
  Deck.dr(l, q, i, j, h, sx, sy, obj_dr.go(obj, a, b, h, i, j, sx, sy, C.Ride.kind(rd), ride_st(rd), rt, rs, q))

# which neighbours a path or queue joins (paths, queues, the gate, rides),
# or which neighbours of water are water: bit 1 i-1, 2 i+1, 4 j-1, 8 j+1
# mode 1: a path, joined by paths, rides, the gate, queues and track;
# 2: water's edge; 3: inside a queue line, open only along the line and to
# its ride; 4: a queue's free end, open to paths as well
def joins(+mode: U32, +q: C.Q, +i: U32, +j: U32) -> Bool:
  +t = C.Land.get(q, i, j)
  +o = C.Tile.obj(t)
  +water = U32.is_eq(C.Tile.ter(t), 2) || Bool.not(C.inmap(i, j))
  +line = U32.is_eq(o, 7) || U32.is_eq(o, 3)
  +path = line || U32.is_eq(o, 1) || U32.is_eq(o, 5) || U32.is_eq(o, 6)
  U32.is_eq(mode, 2) && water || U32.is_eq(mode, 3) && line
    || (U32.is_eq(mode, 1) || U32.is_eq(mode, 4)) && path

def nb.go(+mode: U32, +q: C.Q, +i: U32, +j: U32) -> U32:
  match mode:
    case 0:
      15
    case _:
      (sel(joins(mode, q, (i - 1 : U32), j), 1, 0) + sel(joins(mode, q, (i + 1 : U32), j), 2, 0)
        + sel(joins(mode, q, i, (j - 1 : U32)), 4, 0) + sel(joins(mode, q, i, (j + 1 : U32)), 8, 0) : U32)

def nbmask(+q: C.Q, +i: U32, +j: U32, +obj: U32, +ter: U32, +a: U32) -> U32:
  +qm = sel(U32.is_eq(obj, 7), sel(U32.is_eq(a, 1), 4, 3), 0)
  nb.go(sel(U32.is_eq(obj, 1), 1, sel((qm > 0 : U32), qm, sel(U32.is_eq(ter, 2), 2, 0))), q, i, j)

# Entrance and exit arches: each ride's door tiles, packed tile << 4 | 1
# (entrance) or 2 (exit)
# Entrance and exit arches, worked out once a frame: each ride's door tiles,
# packed tile << 8 | side << 4 | kind (1 entrance, 2 exit). The side is the
# door tile's edge toward the ride: 0 i-1, 1 i+1, 2 j-1, 3 j+1.
def Door.side(+e: U32, +x: U32, +y: U32, +w: U32) -> U32:
  +ei = (e >> 6n : U32)
  +ej = (e .&. 63 : U32)
  sel((ei < x : U32), 1, sel((ei >= x + w : U32), 0, sel((ej < y : U32), 3, 2)))

# the coaster's doors stand beside one of its station pieces
def Coaster.side(+ps: +List<C.Piece>, +e: U32) -> U32:
  match ps:
    case []:
      0
    case p <> rest:
      C.Piece{+x, +y, z, +kind, dir} = p
      +ei = (e >> 6n : U32)
      +ej = (e .&. 63 : U32)
      +st = U32.is_eq(kind, 5)
      sel(st && U32.is_eq(x, (ei + 1 : U32)) && U32.is_eq(y, ej), 1,
        sel(st && U32.is_eq(x, (ei - 1 : U32)) && U32.is_eq(y, ej), 0,
        sel(st && U32.is_eq(y, (ej + 1 : U32)) && U32.is_eq(x, ei), 3,
        sel(st && U32.is_eq(y, (ej - 1 : U32)) && U32.is_eq(x, ei), 2, Coaster.side(rest, e)))))

def Arches.put(+e: U32, +side: U32, +k: U32, +acc: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(e, C.NONE()), acc, ((e << 8n) .|. (side << 4n) .|. k : U32) <> acc)

def Arches.side.go(co: Bool, +r: C.Ride, +ts: +List<C.Track>, +e: U32) -> U32:
  match co:
    case True{}:
      Coaster.side(C.Track.pieces(C.Tracks.get(ts, C.Ride.ht(r))), e)
    case False{}:
      Door.side(e, C.Ride.cx(r), C.Ride.cy(r), C.Ride.wd(r))

def Arches.side(+r: C.Ride, +ts: +List<C.Track>, +e: U32) -> U32:
  Arches.side.go(U32.is_eq(C.Ride.kind(r), 5), r, ts, e)

def Arches.of(+rs: +List<C.Ride>, +ps: +List<C.Track>) -> +List<U32>:
  match rs:
    case []:
      []
    case r <> rest:
      +r2 = r
      +en = C.Ride.ent(r2)
      +ex = C.Ride.ex(r2)
      Arches.put(en, Arches.side(r2, ps, en), 1, Arches.put(ex, Arches.side(r2, ps, ex), 2, Arches.of(rest, ps)))

# the arch on tile e: side << 4 | kind, or 0
def Arches.find(+ar: +List<U32>, +e: U32) -> U32:
  match ar:
    case []:
      0
    case a <> rest:
      sel(U32.is_eq((a >> 8n : U32), e), (a .&. 255 : U32), Arches.find(rest, e))

# only paths and queues carry arches
def Arches.find_if(on: Bool, +ar: +List<U32>, +e: U32) -> U32:
  match on:
    case True{}:
      Arches.find(ar, e)
    case False{}:
      0

def face(+h: U32, +nh: U32, +edge: Bool) -> U32:
  sel(edge, (h * 8 + 6 : U32), sel((h > nh : U32), ((h - nh) * 8 : U32), 0))

# stairs down from a path to the path in front (nb bit 20: toward j+1, the
# left face; bit 21: toward i+1, the right face)
def Stairs.down(+q: C.Q, +i: U32, +j: U32, +h: U32) -> Bool:
  +t = C.Land.get(q, i, j)
  U32.is_eq(C.Tile.obj(t), 1) && U32.is_eq((C.Tile.h(t) + 1 : U32), h)

def Stairs.flags(path: Bool, +q: C.Q, +i: U32, +j: U32, +h: U32) -> U32:
  match path:
    case True{}:
      (sel(Stairs.down(q, i, (j + 1 : U32), h), 1048576, 0) .|. sel(Stairs.down(q, (i + 1 : U32), j, h), 2097152, 0) : U32)
    case False{}:
      0

def push_tile(+q: C.Q, +rs: +List<C.Ride>, +gs: RT, +ar: +List<U32>, +i: U32, +j: U32,
  +camx: U32, +camy: U32, +hov: U32, +acc: +List<Dr>) -> +List<Dr>:
  +t = C.Land.get(q, i, j)
  +ak = Arches.find_if(U32.is_eq(C.Tile.obj(t), 1) || U32.is_eq(C.Tile.obj(t), 7), ar, (i * 64 + j : U32))
  +arch = (((ak .&. 15) << 6n) .|. (((ak >> 4n) .&. 3) << 4n) : U32)
  +h = C.Tile.h(t)
  +sx = scr_x(i, j, camx)
  +sy = scr_y(i, j, h, camy)
  +dl = face(h, C.Land.h(q, i, (j + 1 : U32)), U32.is_eq(j, 63))
  +dr = face(h, C.Land.h(q, (i + 1 : U32), j), U32.is_eq(i, 63))
  +o = C.Tile.obj(t)
  +mb = C.Tile.b(t)
  +ta = C.Tile.a(t)
  +paved = U32.is_eq(o, 1) || U32.is_eq(o, 5) || U32.is_eq(o, 7)
  +messb = sel(paved, ((U32.min((mb .&. 255 : U32), 15) << 8n) .|. (U32.min(((mb >> 8n) .&. 255 : U32), 7) << 12n) : U32), 0)
  +furn = sel(U32.is_eq(o, 1), (((ta .&. 3) << 16n) .|. sel(U32.is_eq(((ta >> 4n) .&. 15 : U32), 15), 262144, 0)
    .|. sel(Bool.not(U32.is_eq((ta .&. 256 : U32), 0)), 524288, 0) : U32), 0)
  +stairs = Stairs.flags(U32.is_eq(o, 1), q, i, j, h)
  +blk = {DBlock{sx, sy, dl, dr, C.Tile.ter(t), C.Tile.obj(t),
    sel(U32.is_eq(hov, (i * 64 + j : U32)), 1, 0), (16 * i - 16 * j : U32),
    (8 * i + 8 * j : U32), (nbmask(q, i, j, C.Tile.obj(t), C.Tile.ter(t), C.Tile.a(t)) .|. arch .|. messb .|. furn .|. stairs : U32)} : Dr}
  List.append(&2, Dr, obj_dr(t, i, j, sx, sy, rs, gs, q), blk <> acc)

def row(+n: Nat, +i: U32, +k: U32, +q: C.Q, +rs: +List<C.Ride>, +gs: RT, +ar: +List<U32>,
  +camx: U32, +camy: U32, +hov: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      row(p, (i + 1 : U32), k, q, rs, gs, ar, camx, camy, hov,
        push_tile(q, rs, gs, ar, i, (k - i : U32), camx, camy, hov, acc))

def Dyn.key(a: Dyn) -> U32:
  Dyn{k, d} = a
  k

def heads(+ds: +List<Dyn>, +k: U32) -> Bool:
  match ds:
    case []:
      False{}
    case d <> rest:
      U32.is_eq(Dyn.key(d), k)

def Dyn.dr(a: Dyn) -> Dr:
  Dyn{k, d} = a
  d

type DP is Data:
  DP{ds: List<&2, Dyn>, acc: List<&2, Dr>}

# move the dynamic things standing on diagonal k into the frame
def take(+ds: +List<Dyn>, go: Bool, +k: U32, +acc: +List<Dr>) -> DP:
  match ds go:
    case Con{d, rest} True{}:
      take(rest, heads(rest, k), k, Dyn.dr(d) <> acc)
    case _ _:
      DP{ds, acc}

def DP.ds(p: DP) -> +List<Dyn>:
  DP{ds, acc} = p
  ds

def DP.acc(p: DP) -> +List<Dr>:
  DP{ds, acc} = p
  acc

def diag_rows(+k: U32, +camx: U32, +camy: U32, +vw: U32, +vh: U32) -> U32:
  +sy0 = ((B() + 512 + 8 * k) - camy : U32)
  +vis = (sy0 + 80 > B() : U32) && (sy0 < B() + vh + 150 : U32)
  +lo0 = C.sub0(((camx + 16 * k + 2048 - 1320) >> 5n : U32), 64)
  +hi0 = C.sub0(((camx + 16 * k + 2048 + vw + 40 - 1280) >> 5n : U32), 64)
  +lo = U32.max(lo0, C.sub0(k, 63))
  +hi = U32.min(U32.min(hi0, k), 63)
  sel(vis && (hi >= lo : U32), ((hi - lo + 1) * 256 + lo : U32), 0)

def diags(+n: Nat, +k: U32, +q: C.Q, +rs: +List<C.Ride>, +gs: RT, +ar: +List<U32>,
  +camx: U32, +camy: U32, +vw: U32, +vh: U32, +hov: U32, +ds: +List<Dyn>, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +r = diag_rows(k, camx, camy, vw, vh)
      +acc2 = row(U32.to_nat((r >> 8n : U32)), (r .&. 255 : U32), k, q, rs, gs, ar,
        camx, camy, hov, acc)
      +dp = take(ds, heads(ds, k), k, acc2)
      diags(p, (k + 1 : U32), q, rs, gs, ar, camx, camy, vw, vh, hov, DP.ds(dp), DP.acc(dp))

# guests on screen, keyed by their diagonal
def shopping(+st: U32, +tgt: U32, +rs: +List<C.Ride>) -> Bool:
  +k = C.Ride.kind(C.Rides.get(rs, tgt))
  U32.is_eq(st, 1) && (U32.is_eq(k, 3) || U32.is_eq(k, 4) || U32.is_eq(k, 8) || U32.is_eq(k, 9))

def Stair.side(+q: C.Q, +i: U32, +j: U32, +h: U32, +d: U32) -> U32:
  +t = C.Land.get(q, i, j)
  +ok = U32.is_eq(C.Tile.obj(t), 1)
  +th = C.Tile.h(t)
  sel(ok && U32.is_eq(th, (h + 1 : U32)), (d >> 1n : U32), sel(ok && U32.is_eq((th + 1 : U32), h), (0 - (d >> 1n) : U32), 0))

def Stair.dz(+q: C.Q, +x: U32, +y: U32, +h: U32) -> U32:
  +i = (x >> 4n : U32)
  +j = (y >> 4n : U32)
  +fx = (x .&. 15 : U32)
  +fy = (y .&. 15 : U32)
  +on = U32.is_eq(C.Land.obj(q, i, j), 1)
  +hx = (fx >= 8 : U32)
  +hy = (fy >= 8 : U32)
  # one look toward the nearer edge on each axis
  +ox = Stair.side(q, sel(hx, (i + 1 : U32), (i - 1 : U32)), j, h, sel(hx, (fx - 8 : U32), (8 - fx : U32)))
  +oy = Stair.side(q, i, sel(hy, (j + 1 : U32), (j - 1 : U32)), h, sel(hy, (fy - 8 : U32), (8 - fy : U32)))
  sel(on, (ox + oy : U32), 0)

def guest_dyn(+g: C.Guest, +q: C.Q, +rs: +List<C.Ride>, +camx: U32, +camy: U32,
  +vw: U32, +vh: U32, +t: U32, +acc: +List<Dyn>) -> +List<Dyn>:
  C.Guest{+id, +x, +y, +dir, +st, +tgt, tmr, cash, +hu, +th, +en, +na, +ha, +lk, +mind, bl} = g
  +i = (x >> 4n : U32)
  +j = (y >> 4n : U32)
  +tl = C.Land.get(q, i, j)
  +up = Bool.not(U32.is_eq((dir .&. 65536 : U32), 0)) && Bool.not(U32.is_eq(C.Deck.of(tl), 0))
  +h = sel(up, C.Deck.of(tl), C.Tile.h(tl))
  +sit = U32.is_eq(st, 4)
  +right = U32.is_eq((id .&. 1 : U32), 1)
  +sx = sel(sit, (scr_x(i, j, camx) - 7 + sel(right, 3, (0 - 3 : U32)) : U32), ((B() + 1280 + x) - (y + camx) : U32))
  +sy = sel(sit, (scr_y(i, j, h, camy) + 6 - sel(right, 5, 2) : U32), ((B() + 512 + ((x + y) >> 1n)) - (8 * h + sel(up, 0, Stair.dz(q, x, y, h)) + camy) : U32))
  +walker = U32.is_eq(st, 0) || U32.is_eq(st, 2) || sit || shopping(st, tgt, rs)
  +vis = (sx + 8 > B() : U32) && (sx < B() + vw + 8 : U32) && (sy + 4 > B() : U32)
    && (sy < B() + vh + 28 : U32) && walker
  # the drawn look: outfit, carried item, stepping (bits 0-9, 16-17, 24),
  # facing (12-13), and now and then a thought (20-22)
  +mood = sel((na > 120 : U32), 3, sel((bl > 180 : U32), 10, sel((hu > 170 : U32), 1, sel((th > 170 : U32), 2,
    sel((en < 50 : U32), 4, sel((ha < 70 : U32), 5, sel((ha > 215 : U32), 6, 0)))))))
  +think = U32.is_eq((((t + id * 37) >> 6n) .&. 15 : U32), 0)
  # a fresh thought (the last three seconds) shows in the bubble first
  +code = C.Mind.code(mind)
  +fresh = Bool.not(U32.is_eq(code, 0)) && ((((t >> 4n) - C.Mind.when(mind)) .&. 65535) < 12 : U32)
  +evicon = sel(U32.is_eq(code, 1), 7, sel(U32.is_eq(code, 2), 8, sel(U32.is_eq(code, 3), 6, sel(U32.is_eq(code, 9), 9, sel(U32.is_eq(code, 6), 5, 3)))))
  +keep = sel(U32.is_eq(st, 1), 511999, 17288191)
  +look = ((lk .&. keep) .|. (sel(sit, 0, (dir .&. 3 : U32)) << 12n) .|. (sel(fresh, evicon, sel(think, mood, 0)) << 20n)
    .|. sel(sit, 33554432, 0) : U32)
  Bool.pick(+List<Dyn>, vis, Dyn{(i + j : U32), DGuest{sx, sy, look, (t + id : U32)}} <> acc, acc)

def guests_dyn(+gs: +List<C.Guest>, +q: C.Q, +rs: +List<C.Ride>, +camx: U32,
  +camy: U32, +vw: U32, +vh: U32, +t: U32, +acc: +List<Dyn>) -> +List<Dyn>:
  match gs:
    case []:
      acc
    case g <> rest:
      guests_dyn(rest, q, rs, camx, camy, vw, vh, t, guest_dyn(g, q, rs, camx, camy, vw, vh, t, acc))

# a point along the coaster: world position (1/16 tile) and height (px)
def ash8(+v: U32) -> U32:
  sel(A.neg(v), ((v >> 8n) .|. 4278190080 : U32), (v >> 8n : U32))

def entry_u(+x: U32, +d: U32) -> U32:
  (16 * x + sel(U32.is_eq(d, 0), 0, sel(U32.is_eq(d, 2), 16, 8)) : U32)

def entry_v(+y: U32, +d: U32) -> U32:
  (16 * y + sel(U32.is_eq(d, 1), 0, sel(U32.is_eq(d, 3), 16, 8)) : U32)

def exit_u(+x: U32, +d: U32) -> U32:
  (16 * x + sel(U32.is_eq(d, 0), 16, sel(U32.is_eq(d, 2), 0, 8)) : U32)

def exit_v(+y: U32, +d: U32) -> U32:
  (16 * y + sel(U32.is_eq(d, 1), 16, sel(U32.is_eq(d, 3), 0, 8)) : U32)

def car_dyn(+pc: C.Piece, +f: U32, +lead: U32, +camx: U32, +camy: U32, +rd: U32,
  +acc: +List<Dyn>) -> +List<Dyn>:
  C.Piece{+x, +y, +z, +kind, +d} = pc
  +d2 = C.Pose.d(C.Piece.exit(pc))
  +u0 = entry_u(x, d)
  +v0 = entry_v(y, d)
  +u = (u0 + ash8(((exit_u(x, d2) - u0) * f : U32)) : U32)
  +v = (v0 + ash8(((exit_v(y, d2) - v0) * f : U32)) : U32)
  +dz = ((C.Piece.rise(kind) - C.Piece.drop(kind)) * 8 : U32)
  +zp = ((z * 8 + ash8((dz * f : U32))) - sel(U32.is_eq((lead >> 1n : U32), 2), 13, 0) : U32)
  +sx = ((B() + 1280 + u) - (v + camx) : U32)
  +sy = ((B() + 512 + ((u + v) >> 1n)) - (zp + camy) : U32)
  Dyn{((u >> 4n) + (v >> 4n) : U32), DCar{sx, sy, sel((f > 128 : U32), d2, d), lead, rd}} <> acc

# who sits in seat s of a train: their look (lo, hi: seats 0-7; a seat past
# 7 borrows the look of seat s mod 8, or a default), or 0 when empty
def Car.seat(+lo: U32, +hi: U32, +o0: U32, +o1: U32, +s: U32) -> U32:
  +taken = Bool.not(U32.is_eq(((sel((s < 32 : U32), o0, o1) >> U32.to_nat((s .&. 31 : U32))) .&. 1 : U32), 0))
  +s8 = (s .&. 7 : U32)
  +w = sel((s8 < 4 : U32), lo, hi)
  +b = ((w >> U32.to_nat(((s8 .&. 3) * 8 : U32))) .&. 255 : U32)
  sel(taken, sel(U32.is_eq(b, 0), 137, b), 0)

# a car's two riders: front seat << 8 | back seat
def Car.riders(+lo: U32, +hi: U32, +o0: U32, +o1: U32, +car: U32) -> U32:
  ((Car.seat(lo, hi, o0, o1, (car * 2 + 1 : U32)) << 8n) .|. Car.seat(lo, hi, o0, o1, (car * 2 : U32)) : U32)

def cars_of(+n: Nat, +ps: +List<C.Piece>, +total: U32, +pos: U32, +lead: U32,
  +camx: U32, +camy: U32, +car: U32, +lo: U32, +hi: U32, +o0: U32, +o1: U32, +acc: +List<Dyn>)
  -> +List<Dyn>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +q = (pos % total : U32)
      +rd = Car.riders(lo, hi, o0, o1, car)
      cars_of(p, ps, total, ((pos + total - 300) : U32), (lead .&. 6 : U32), camx, camy, (car + 1 : U32),
        lo, hi, o0, o1, car_dyn(C.Pieces.get(ps, (q >> 8n : U32)), (q .&. 255 : U32), lead, camx,
          camy, rd, acc))

def trains_one(+s: C.Slot, +ps: +List<C.Piece>, +total: U32, +camx: U32,
  +camy: U32, +rt: RT, +k: U32, +ty: U32, +cars: U32, +acc: +List<Dyn>) -> +List<Dyn>:
  match s:
    case C.Free{a, n, st}:
      acc
    case C.Held{+a, n, st, t}:
      C.Train{+id, prog, sp, w} = t
      +i = (k * 64 + id : U32)
      cars_of(U32.to_nat(cars), ps, total, (a * 256 + prog : U32), (1 .|. (ty << 1n) : U32), camx, camy, 0,
        C.Tab.at(RT.lo(rt), i), C.Tab.at(RT.hi(rt), i), C.Tab.at(RT.o0(rt), i), C.Tab.at(RT.o1(rt), i), acc)

# Text and the HUD
# ----------------

def trains_dyn(+ss: +List<C.Slot>, +ps: +List<C.Piece>, +total: U32, +camx: U32,
  +camy: U32, +rt: RT, +k: U32, +ty: U32, +cars: U32, +acc: +List<Dyn>) -> +List<Dyn>:
  match ss:
    case []:
      acc
    case s <> rest:
      trains_dyn(rest, ps, total, camx, camy, rt, k, ty, cars,
        trains_one(s, ps, total, camx, camy, rt, k, ty, cars, acc))

def trains_all(+ts: +List<C.Track>, +camx: U32, +camy: U32, +rt: RT, +k: U32,
  +acc: +List<Dyn>) -> +List<Dyn>:
  match ts:
    case []:
      acc
    case t <> rest:
      C.Track{+ps, open, +bs, st, en, +cfg, stats} = t
      +total = (C.len32(C.Piece, ps) * 256 : U32)
      trains_all(rest, camx, camy, rt, (k + 1 : U32),
        trains_dyn(bs, ps, U32.max(total, 1), camx, camy, rt, k, C.Cfg.type(cfg),
          U32.max(U32.min(U32.min(C.Cfg.cars(cfg), C.Pieces.stations(ps)), 20), 1), acc))

def text(s: String, +x: U32, +y: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{c}, rest}:
      DGlyph{x, y, F.Font.glyph(c), col} <> text(rest, (x + 4 : U32), y, col, acc)

def money(+c: U32) -> String:
  Bool.pick(String, A.neg(c), "*-" ++ U32.show((0 - c : U32)), "*" ++ U32.show(c))

def Cat.name(+c: U32) -> String:
  match c:
    case 0:
      "PATHS AND FURNITURE  (1)"
    case 1:
      "SHAPE THE LAND  (2)"
    case 2:
      "SCENERY  (3)"
    case 3:
      "GENTLE RIDES  (4)"
    case 4:
      "THRILL RIDES  (5)"
    case _:
      "SHOPS AND STALLS  (6)"

def tool_name(+t: U32) -> String:
  match t:
    case 1:
      "PATH  10*"
    case 2:
      "RAISE LAND  20*"
    case 3:
      "LOWER LAND  20*"
    case 4:
      "ENCHANTED TREE  15*   R: KIND"
    case 5:
      "DRAGON CAROUSEL  900*"
    case 6:
      "ARCANE SPIRE  1200*"
    case 7:
      "POTION STALL  300*"
    case 8:
      "TROLL TAVERN  400*"
    case 9:
      "DEMOLISH  (X)"
    case 10:
      "WYRM COASTER  40* A PIECE"
    case 11:
      "QUEUE LINE  12*  (U)"
    case 13:
      "LITTER BIN  20*  HOLDS 15"
    case 14:
      "BENCH  30*  TIRED GUESTS REST"
    case 15:
      "LANTERN  25*"
    case 16:
      "PRIVY  150*  GUESTS NEED ONE"
    case 20:
      Cat.name(0)
    case 21:
      Cat.name(1)
    case 22:
      Cat.name(2)
    case 23:
      Cat.name(3)
    case 24:
      Cat.name(4)
    case 25:
      Cat.name(5)
    case 30:
      "HEALER'S TENT  350*  CURES QUEASY GUESTS"
    case 31:
      "WISP SELLER  250*"
    case 32:
      "ENCHANTED ICES  300*"
    case 33:
      "GRIFFIN SWING  1400*"
    case 34:
      "WHEEL OF STARS  1100*"
    case 38:
      "DRAGON'S EYRIE  1000*"
    case 39:
      "WIZARD'S WHIRL  1600*"
    case 35:
      "LICH'S CRYPT  1500*"
    case 36:
      "GOLEM BUMPERS  1000*"
    case 37:
      "HEDGE LABYRINTH  700*"
    case 40:
      "MERMAID FLUME  1900*"
    case 41:
      "STATUE  60*  R: KNIGHT, DRAGON, WIZARD, GRIFFIN"
    case 42:
      "FOUNTAIN  120*"
    case 43:
      "FLOWER BED  15*  R: COLOUR"
    case 44:
      "CASTLE WALL  25*"
    case 45:
      "FENCE  8*"
    case 46:
      "BUY LAND  60*  AT THE PARK'S EDGE"
    case 48:
      "WALKWAY BRIDGE  40*  OVER A PATH OR TRACK, LEVEL WITH THE PATHS BESIDE IT"
    case 47:
      "TRACK DESIGNS: PICK ONE, THEN CLICK TO BUILD IT (R TURNS IT)"
    case _:
      "INSPECT (I): CLICK A RIDE OR A GUEST"

def ride_name(+k: U32) -> String:
  match k:
    case 1:
      "DRAGON CAROUSEL"
    case 2:
      "ARCANE SPIRE"
    case 3:
      "POTION STALL"
    case 4:
      "TROLL TAVERN"
    case 5:
      "WYRM COASTER"
    case 6:
      "PRIVY"
    case 7:
      "HEALER'S TENT"
    case 8:
      "WISP SELLER"
    case 9:
      "ENCHANTED ICES"
    case 10:
      "GRIFFIN SWING"
    case 11:
      "WHEEL OF STARS"
    case 12:
      "LICH'S CRYPT"
    case 13:
      "GOLEM BUMPERS"
    case 14:
      "HEDGE LABYRINTH"
    case 15:
      "DRAGON'S EYRIE"
    case 16:
      "WIZARD'S WHIRL"
    case 17:
      "MERMAID FLUME"
    case _:
      "RUINS"

def Award.text(+k: U32) -> String:
  match k:
    case 0:
      "AWARD: THE TIDIEST PARK IN THE REALM"
    case 1:
      "AWARD: THE MOST BEAUTIFUL PARK"
    case 2:
      "AWARD: THE HAPPIEST GUESTS"
    case 3:
      "AWARD: THE BEST STAFFED PARK"
    case _:
      "AWARD: THE MOST THRILLING PARK"

def msg_text(+m: U32) -> String:
  match m:
    case 1:
      "BUILT!"
    case 2:
      "YOU CAN'T BUILD THAT THERE"
    case 3:
      "SAVED  (ELDERGROVE.SAV)"
    case 4:
      "SAVE LOADED"
    case 5:
      "NO SAVE FOUND"
    case 6:
      "THE COASTER OPENS!"
    case 7:
      "THE COASTER CLOSES"
    case 8:
      "BORROWED 1000 GOLD"
    case 9:
      "REPAID 1000 GOLD"
    case 10:
      "THE BANK SAYS NO"
    case 11:
      "MUSIC ON  (M)"
    case 12:
      "MUSIC OFF  (M)"
    case 13:
      "SOUNDS ON  (N)"
    case 14:
      "SOUNDS OFF  (N)"
    case 15:
      "TEST THE COASTER BEFORE IT OPENS"
    case 16:
      "TEST RUN: AN EMPTY TRAIN GOES ROUND"
    case 17:
      "TEST PASSED! THE COASTER CAN OPEN"
    case 18:
      "TEST FAILED: SEE ITS BUILD WINDOW"
    case 19:
      "FINISH THE TRACK FIRST"
    case 20:
      "TRACK REMOVED: THE COASTER IS OFF UNTIL IT IS A CIRCUIT AGAIN"
    case 21:
      "COASTER DEMOLISHED"
    case 22:
      "TRACK REMOVED: IT STILL CHECKS OUT, TEST RUN STARTED"
    case 23:
      "DESIGN SAVED (DESIGNS.SAV)"
    case 24:
      "ONLY A FINISHED CIRCUIT CAN BE SAVED AS A DESIGN"
    case 25:
      "DESIGN BUILT: ITS TEST RUN HAS STARTED"
    case 26:
      "THE DESIGN DOESN'T FIT THERE"
    case _:
      Bool.pick(String, (m >= 131 : U32) && (m <= 135 : U32), Award.text((m - 131 : U32)),
      Bool.pick(String, (m >= 100 : U32) && (m < 110 : U32), "THE " ++ ride_name((m - 100 : U32)) ++ " BROKE DOWN!",
        Bool.pick(String, (m >= 110 : U32) && (m < 120 : U32), "THE " ++ ride_name((m - 110 : U32)) ++ " IS FIXED", "")))

def Cat.tool.go(+code: U32) -> U32:
  match code:
    case 0:
      1
    case 1:
      11
    case 2:
      13
    case 3:
      14
    case 4:
      15
    case 5:
      48
    case 8:
      2
    case 9:
      3
    case 10:
      46
    case 16:
      4
    case 17:
      41
    case 18:
      42
    case 19:
      43
    case 20:
      44
    case 21:
      45
    case 24:
      5
    case 25:
      34
    case 26:
      37
    case 27:
      38
    case 28:
      36
    case 29:
      35
    case 32:
      6
    case 33:
      33
    case 34:
      39
    case 35:
      40
    case 36:
      10
    case 37:
      47
    case 40:
      7
    case 41:
      8
    case 42:
      16
    case 43:
      30
    case 44:
      31
    case 45:
      32
    case _:
      0

def Cat.tool(+c: U32, +k: U32) -> U32:
  Cat.tool.go((c * 8 + k : U32))

def Cat.len(+c: U32) -> U32:
  match c:
    case 0:
      6
    case 1:
      3
    case 2:
      6
    case 3:
      6
    case 4:
      6
    case 5:
      6
    case _:
      0

def Cat.of(+t: U32) -> U32:
  match t:
    case 1:
      0
    case 11:
      0
    case 13:
      0
    case 14:
      0
    case 15:
      0
    case 2:
      1
    case 3:
      1
    case 46:
      1
    case 4:
      2
    case 41:
      2
    case 42:
      2
    case 43:
      2
    case 44:
      2
    case 45:
      2
    case 5:
      3
    case 34:
      3
    case 35:
      3
    case 36:
      3
    case 37:
      3
    case 38:
      3
    case 40:
      4
    case 6:
      4
    case 33:
      4
    case 39:
      4
    case 10:
      4
    case 7:
      5
    case 8:
      5
    case 16:
      5
    case 30:
      5
    case 31:
      5
    case 32:
      5
    case _:
      99

def Cat.pos(+t: U32) -> U32:
  match t:
    case 11:
      1
    case 13:
      2
    case 14:
      3
    case 15:
      4
    case 3:
      1
    case 46:
      2
    case 41:
      1
    case 42:
      2
    case 43:
      3
    case 44:
      4
    case 45:
      5
    case 34:
      1
    case 37:
      2
    case 38:
      3
    case 36:
      4
    case 35:
      5
    case 33:
      1
    case 39:
      2
    case 40:
      3
    case 10:
      4
    case 8:
      1
    case 16:
      2
    case 30:
      3
    case 31:
      4
    case 32:
      5
    case _:
      0

def UI.cat(+var: U32) -> U32:
  ((var >> 20n) .&. 7 : U32)

def set_cat(+var: U32, +c: U32) -> U32:
  ((var .&. 4287627263) .|. ((c .&. 7) << 20n) : U32)

# the key for category c pressed with `tool` in hand: its first tool, or
# the next one when that category is already open
def Cat.key(+c: U32, +cur: U32, +tool: U32) -> U32:
  +n = U32.max(Cat.len(c), 1)
  +same = U32.is_eq(c, cur) && U32.is_eq(Cat.of(tool), c)
  Cat.tool(c, sel(same, ((Cat.pos(tool) + 1) % n : U32), 0))

# what the toolbar has at (lx, ly): 0 nothing, a tool, or 20 + a category
def bar_item(+lx: U32, +ly: U32, +c: U32) -> U32:
  +row = (ly >= 294 : U32) && (ly < 316 : U32)
  +ci = ((lx - 60) / 24 : U32)
  +ti = ((lx - 212) / 24 : U32)
  +incat = (ci < 6 : U32) && (((lx - 60) % 24) < 22 : U32)
  +intool = (ti < Cat.len(c) : U32) && (((lx - 212) % 24) < 22 : U32)
  sel(Bool.not(row), 0, sel((lx >= 4 : U32) && (lx < 26 : U32), 12,
    sel((lx >= 28 : U32) && (lx < 50 : U32), 9, sel(incat, (20 + ci : U32),
    sel(intool, Cat.tool(c, ti), 0)))))

def cat_icons(+n: Nat, +k: U32, +c: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      cat_icons(p, (k + 1 : U32), c,
        DIcon{(B() + 60 + k * 24 : U32), (B() + 294 : U32), (20 + k : U32), sel(U32.is_eq(k, c), 1, 0)} <> acc)

def Res.bit(+t: U32) -> U32:
  match t:
    case 30:
      0
    case 37:
      1
    case 36:
      2
    case 31:
      3
    case 34:
      4
    case 32:
      5
    case 33:
      6
    case 38:
      7
    case 35:
      8
    case 39:
      9
    case 40:
      10
    case 41:
      11
    case 42:
      11
    case 44:
      12
    case 45:
      12
    case _:
      99

def Res.open(+r: U32, +t: U32) -> Bool:
  +b = Res.bit(t)
  U32.is_eq(b, 99) || Bool.not(U32.is_eq(((r >> U32.to_nat(U32.min(b, 31))) .&. 1 : U32), 0))

def tool_icons(+n: Nat, +k: U32, +c: U32, +tool: U32, +res: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +tk = Cat.tool(c, k)
      tool_icons(p, (k + 1 : U32), c, tool, res,
        DIcon{(B() + 212 + k * 24 : U32), (B() + 294 : U32), tk, sel(Bool.not(Res.open(res, tk)), 2, sel(U32.is_eq(tk, tool), 1, 0))} <> acc)

def toolbar(+tool: U32, +c: U32, +res: U32, +acc: +List<Dr>) -> +List<Dr>:
  DIcon{(B() + 4 : U32), (B() + 294 : U32), 12, sel(U32.is_eq(tool, 12), 1, 0)}
    <> DIcon{(B() + 28 : U32), (B() + 294 : U32), 9, sel(U32.is_eq(tool, 9), 1, 0)}
    <> DRect{(B() + 54 : U32), (B() + 295 : U32), 1, 20, 5917290}
    <> DRect{(B() + 206 : U32), (B() + 295 : U32), 1, 20, 5917290}
    <> cat_icons(6n, 0, c, tool_icons(U32.to_nat(Cat.len(c)), 0, c, tool, res, acc))

def happy_avg(+gs: +List<C.Guest>, +sum: U32, +n: U32) -> U32:
  match gs:
    case []:
      sel(U32.is_eq(n, 0), 0, (sum * 100 / (n * 255) : U32))
    case g <> rest:
      C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
      happy_avg(rest, (sum + ha : U32), (n + 1 : U32))

def riders(+gs: +List<C.Guest>, +idx: U32) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, x, y, dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
      (sel(U32.is_eq(st, 1) && U32.is_eq(tgt, idx), 1, 0) + riders(rest, idx) : U32)

def ride_state(r: C.Ride) -> String:
  +r2 = r
  +k = C.Ride.kind(r2)
  +ph = C.Ride.ph(r2)
  Bool.pick(String, C.Wear.broken(C.Ride.wear(r2)), "  BROKEN DOWN!",
  Bool.pick(String, C.Ride.shop(k), "",
    Bool.pick(String, U32.is_eq(C.Ride.ent(r2), C.NONE()), "  NEEDS AN ENTRANCE (QUEUE)",
    Bool.pick(String, U32.is_eq(C.Ride.ex(r2), C.NONE()), "  NEEDS AN EXIT (PATH)",
    Bool.pick(String, Bool.not(C.Ride.cycles(k)), "",
    Bool.pick(String, U32.is_eq(ph, 0), "  LOADING",
    Bool.pick(String, U32.is_eq(ph, 1), "  RUNNING", "  UNLOADING")))))))

def str_bytes(s: String) -> +List<U32>:
  match s:
    case SNil{}:
      []
    case SCon{Chr{c}, rest}:
      c <> str_bytes(rest)

def Coaster.tname(+ty: U32) -> String:
  match ty:
    case 1:
      "DWARVEN MINECART"
    case 2:
      "GRIFFIN FLYER"
    case _:
      "WYRM COASTER"

# a coaster's name: its type and number
def Coaster.name(+ts: +List<C.Track>, +k: U32) -> String:
  Coaster.tname(C.Cfg.type(C.Track.cfg(C.Tracks.get(ts, k)))) ++ " " ++ U32.show((k + 1 : U32))

def hover_info(+p: C.Park, +hov: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{+map, +guests, +rides, +track, cash, time, nid, fin, mess, staff} = p
  +i = (hov >> 6n : U32)
  +j = (hov .&. 63 : U32)
  +t = C.Land.get(map, i, j)
  +o = C.Tile.obj(t)
  +idx = sel(U32.is_eq(o, 3), C.Tile.a(t), sel(U32.is_eq(o, 6), Coaster.ride(rides, ((C.Tile.a(t) >> 8n) .&. 2047 : U32), 0), C.NONE()))
  +isride = Bool.not(U32.is_eq(idx, C.NONE())) && (hov < 99999 : U32)
  +rd = C.Rides.get(rides, idx)
  +k = C.Ride.kind(rd)
  +tk = C.Tracks.get(track, C.Ride.ht(rd))
  +st = C.Track.stats(tk)
  +name = Bool.pick(String, U32.is_eq(k, 5), Coaster.name(track, C.Ride.ht(rd)), ride_name(k))
  +test = Bool.pick(String, Bool.not(U32.is_eq(k, 5)), "", Bool.pick(String, C.Test.passed(st), "",
    Bool.pick(String, C.Test.testing(st), "  TESTING", Bool.pick(String, C.Test.failed(st), "  TEST FAILED", "  NOT TESTED"))))
  +line = name ++ Bool.pick(String, C.Ride.shop(k), "  CUSTOMERS " ++ U32.show(C.Ride.total(rd)),
      "  RIDERS " ++ U32.show(riders(guests, idx)) ++ "  QUEUE " ++ U32.show(C.Ride.qlen(rd)))
    ++ "  PRICE *" ++ U32.show(C.Ride.price(rd)) ++ test ++ ride_state(rd)
  +w = (C.len32(U32, str_bytes(line)) * 4 + 8 : U32)
  Bool.pick(+List<Dr>, isride,
    text(line, (B() + 256 - (w >> 1n) + 4 : U32), (B() + 17 : U32), 16777215,
      DRect{(B() + 256 - (w >> 1n) : U32), (B() + 15 : U32), w, 10, 2763330} <> acc), acc)

def coaster_help(+tool: U32, +acc: +List<Dr>) -> +List<Dr>:
  Bool.pick(+List<Dr>, U32.is_eq(tool, 10),
    text("CLICK TO PLACE A STATION - ITS CONSTRUCTION WINDOW OPENS TO LAY THE TRACK",
      (B() + 4 : U32), (B() + 274 : U32), 12648447, acc), acc)

def T(s: String, +x: U32, +y: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  text(s, (B() + x : U32), (B() + y : U32), col, acc)

def R(+x: U32, +y: U32, +w: U32, +h: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  DRect{(B() + x : U32), (B() + y : U32), w, h, col} <> acc

def button(label: String, +x: U32, +y: U32, +w: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(label, (x + 2 : U32), (y + 2 : U32), 16777215, R(x, y, w, 9, col, acc))

def Speed.name(+l: U32) -> String:
  match l:
    case 0:
      "PAUSED"
    case 1:
      "1/4"
    case 2:
      "1/2"
    case 3:
      ">"
    case 4:
      ">>"
    case _:
      ">>>"

# sim ticks this frame: a quarter ticks every fourth frame, half every other
def hud(+p: C.Park, +ui: UI, +hov: U32) -> +List<Dr>:
  C.Park{map, +guests, rides, track, +cash, +time, nid, fin, mess, staff} = p
  UI{camx, camy, keys, +mx, +my, md, +tool, +var, +sp, +msg, fr, +inc, last, io, +fps, tl, opt, fol} = ui
  +day = ((time / 120) % 30 + 1 : U32)
  +month = (time / 3600 + 1 : U32)
  +spd = (sp .&. 15 : U32)
  +top = text(money(cash), (B() + 4 : U32), (B() + 3 : U32), 16766282,
    text("GUESTS " ++ U32.show(C.len32(C.Guest, guests)), (B() + 72 : U32), (B() + 3 : U32), 15261888,
    text("HAPPY " ++ U32.show(happy_avg(guests, 0, 0)) ++ "%", (B() + 140 : U32), (B() + 3 : U32), 11468718,
    text("ELDERGROVE FAIRE", (B() + 212 : U32), (B() + 3 : U32), 13674751,
    text("MONTH " ++ U32.show(month) ++ " DAY " ++ U32.show(day), (B() + 300 : U32), (B() + 3 : U32), 15261888,
    text(Speed.name(spd), (B() + 474 : U32), (B() + 3 : U32), 16766282,
    text(msg_text(msg), (B() + 324 : U32), (B() + 301 : U32), 16766282,
    text("INCOME " ++ money(inc), (B() + 410 : U32), (B() + 3 : U32), 11468718,
    text(Bool.pick(String, U32.is_eq(fol, 0), "", "FOLLOWING  (A CAMERA KEY LETS GO)"), (B() + 190 : U32), (B() + 28 : U32), 16766282,
    text(Bool.pick(String, U32.is_eq(fps, 0), "", U32.show(fps) ++ " FPS"), (B() + 4 : U32), (B() + 14 : U32), 8421504,
    button("OPTIONS", 414, 305, 46, 5913248, button("STAFF", 414, 294, 46, 5913248, button("PARK", 462, 294, 46, 5913248, button("FINANCES", 462, 305, 46, 5913248, []))))))))))))))
  +bars = {DRect{B(), B(), 512, 11, 1973802} <> DRect{B(), (B() + 11 : U32), 512, 1, 13148232}
    <> DRect{B(), (B() + 291 : U32), 512, 1, 13148232}
    <> DRect{B(), (B() + 292 : U32), 512, 28, 1973802} <> [] : +List<Dr>}
  +tip = bar_item(mx, my, UI.cat(var))
  +shown = sel(U32.is_eq(tip, 0), tool, tip)
  +name = Bool.pick(String, Res.open(C.Fin.res(C.Park.fin(p)), shown), tool_name(shown), "LOCKED: RESEARCH IT IN THE PARK WINDOW")
  +strip = T(name, 5, 284, sel(U32.is_eq(tip, 0), 16777215, 16766282),
    R(2, 282, (C.len32(U32, str_bytes(name)) * 4 + 6 : U32), 9, 1973802,
    toolbar(tool, UI.cat(var), C.Fin.res(C.Park.fin(p)), coaster_help(tool, hover_info(p, hov, bars)))))
  List.append(&2, Dr, top, strip)

# Windows
# -------
# kind 1: a ride's window (arg: the ride). The first window in the list is
# the one in front; x, y: its top-left corner in screen pixels.

type Win is Data:
  Win{kind: U32, x: U32, y: U32, arg: U32}

# drag: 1 while the front window is being dragged, gx, gy: where it was grabbed
type WM is Data:
  WM{wins: List<&2, Win>, drag: U32, gx: U32, gy: U32}

def WM.new() -> WM:
  WM{[], 0, 0, 0}

def Win.w(+k: U32) -> U32:
  match k:
    case 1:
      196
    case 8:
      232
    case 9:
      320
    case 10:
      260
    case 2:
      200
    case 3:
      224
    case _:
      210

def Win.h(+k: U32) -> U32:
  match k:
    case 1:
      154
    case 2:
      176
    case 3:
      157
    case 5:
      114
    case 6:
      124
    case 7:
      76
    case 8:
      138
    case 9:
      198
    case 10:
      124
    case _:
      144

def Win.hit(w: Win, +mx: U32, +my: U32) -> Bool:
  Win{+k, +x, +y, a} = w
  (mx >= x : U32) && (mx < x + Win.w(k) : U32) && (my >= y : U32) && (my < y + Win.h(k) : U32)

# the front-most window under the mouse (its place in the list), or NONE
def Wins.at(+ws: +List<Win>, +mx: U32, +my: U32, +i: U32) -> U32:
  match ws:
    case []:
      C.NONE()
    case w <> rest:
      sel(Win.hit(w, mx, my), i, Wins.at(rest, mx, my, (i + 1 : U32)))

def Wins.get(+ws: +List<Win>, +i: U32) -> Win:
  match ws i:
    case Nil{} _:
      Win{0, 0, 0, 0}
    case Con{w, rest} 0:
      w
    case Con{w, rest} _:
      Wins.get(rest, (i - 1 : U32))

def Wins.drop(+ws: +List<Win>, +i: U32) -> +List<Win>:
  match ws:
    case []:
      []
    case w <> rest:
      Bool.pick(+List<Win>, U32.is_eq(i, 0), rest, w <> Wins.drop(rest, (i - 1 : U32)))

# bring window i to the front
def Wins.front(+ws: +List<Win>, +i: U32) -> +List<Win>:
  Wins.get(ws, i) <> Wins.drop(ws, i)

def Win.is(w: Win, +k: U32, +a: U32) -> Bool:
  Win{+wk, x, y, +wa} = w
  U32.is_eq(wk, k) && U32.is_eq(wa, a)

def Wins.find(+ws: +List<Win>, +k: U32, +a: U32, +i: U32) -> U32:
  match ws:
    case []:
      C.NONE()
    case w <> rest:
      sel(Win.is(w, k, a), i, Wins.find(rest, k, a, (i + 1 : U32)))

def Wins.take(+n: Nat, +ws: +List<Win>) -> +List<Win>:
  match n ws:
    case 0n _:
      []
    case 1n+m Con{w, rest}:
      w <> Wins.take(m, rest)
    case 1n+m Nil{}:
      []

# open a window (or bring it to the front if it is open); four at most
def Wins.open(+ws: +List<Win>, +k: U32, +a: U32, +x: U32, +y: U32) -> +List<Win>:
  +i = Wins.find(ws, k, a, 0)
  Bool.pick(+List<Win>, U32.is_eq(i, C.NONE()), Win{k, x, y, a} <> Wins.take(3n, ws), Wins.front(ws, i))

def Win.moved(w: Win, +x: U32, +y: U32) -> Win:
  Win{k, ox, oy, a} = w
  Win{k, x, y, a}

def WM.drag(m: WM) -> U32:
  WM{ws, d, x, y} = m
  d

def WM.gx(m: WM) -> U32:
  WM{ws, d, x, y} = m
  x

def WM.gy(m: WM) -> U32:
  WM{ws, d, x, y} = m
  y

def WM.wins(m: WM) -> +List<Win>:
  WM{ws, d, gx, gy} = m
  ws

# Drawing windows (screen coordinates; front-most items first)

def window_box(title: String, +x: U32, +y: U32, +w: U32, +h: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(title, (x + 4 : U32), (y + 2 : U32), 16766282,
  T("X", (x + w - 7 : U32), (y + 2 : U32), 16777215,
  R((x + w - 10 : U32), (y + 1 : U32), 9, 8, 10498096,
  R((x + 1 : U32), (y + 1 : U32), (w - 2 : U32), 8, 4863024,
  R((x + 1 : U32), (y + 10 : U32), (w - 2 : U32), (h - 11 : U32), 2763330,
  R(x, y, w, h, 13148232, R((x + 3 : U32), (y + 3 : U32), w, h, 1052688, acc)))))))

def pm(+x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  button("-", x, y, 11, 5913248, button("+", (x + 14 : U32), y, 11, 5913248, acc))

# ticks as seconds with a tenth: 90 -> "1.5S"
def secs(+t: U32) -> String:
  U32.show((t / 60 : U32)) ++ "." ++ U32.show(((t % 60) / 6 : U32)) ++ "S"

def ride_waits(+wmin: U32, +wmax: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  T("MIN WAIT " ++ secs(wmin), (x + 6 : U32), (y + 52 : U32), 15261888, pm((x + 96 : U32), (y + 50 : U32),
  T("MAX WAIT " ++ secs(wmax), (x + 6 : U32), (y + 64 : U32), 15261888, pm((x + 96 : U32), (y + 62 : U32), acc))))

# hundredths as "4.19"
def cents(+v: U32) -> String:
  +c = (v % 100 : U32)
  U32.show((v / 100 : U32)) ++ Bool.pick(String, (c < 10 : U32), ".0", ".") ++ U32.show(c)

def rate_word(+v: U32) -> String:
  Bool.pick(String, (v < 200 : U32), "LOW", Bool.pick(String, (v < 400 : U32), "MEDIUM",
    Bool.pick(String, (v < 600 : U32), "HIGH", Bool.pick(String, (v < 750 : U32), "VERY HIGH", "EXTREME"))))

def rate_line(label: String, +v: U32, +x: U32, +y: U32, +col: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(label, (x + 6 : U32), y, 15261888, T(cents(v) ++ "  " ++ rate_word(v), (x + 70 : U32), y, col, acc))

# excitement, intensity and nausea (shops have none; an unfinished coaster
# has none yet)
def ride_rates(+k: U32, +r: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  Bool.pick(+List<Dr>, C.Ride.shop(k), acc,
    Bool.pick(+List<Dr>, U32.is_eq(r, 0), T("RATINGS: AFTER A TEST RUN", (x + 6 : U32), (y + 118 : U32), 15261888, acc),
      rate_line("EXCITEMENT", C.Rate.e(r), x, (y + 116 : U32), 16766282,
      rate_line("INTENSITY", C.Rate.i(r), x, (y + 128 : U32), 16750480,
      rate_line("NAUSEA", C.Rate.n(r), x, (y + 140 : U32), 9498256, acc)))))

# tenths as a decimal: 45 -> "4.5"
def tenths(+v: U32) -> String:
  U32.show((v / 10 : U32)) ++ "." ++ U32.show((v % 10 : U32))

# what a coaster's test found (the dry run of its track), or why there is
# nothing yet: three lines in the ride window
def Piece.name(+k: U32) -> String:
  match k:
    case 0:
      "STRAIGHT"
    case 1:
      "GENTLE UP"
    case 2:
      "GENTLE DOWN"
    case 3:
      "TURN LEFT"
    case 4:
      "TURN RIGHT"
    case 5:
      "STATION"
    case 6:
      "LIFT HILL"
    case 9:
      "BRAKES"
    case 10:
      "BANKED LEFT"
    case 11:
      "BANKED RIGHT"
    case 12:
      "STEEP UP"
    case _:
      "STEEP DOWN"

# the button under (lx, ly): 300 + its track op, or 0
def Coaster.stats_go(+t: C.Track, d: C.Dry, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Dry{e, +n, prev, +top, +drops, run, +big, +gv, +gl, +neg, +air, turns, +hi, +lo, fail} = d
  +st = C.Track.stats(t)
  +ps = C.Track.pieces(t)
  +f = C.Test.fail(st)
  +l1 = Bool.pick(String, C.Test.passed(st), "SPEED " ++ U32.show(top) ++ "KM/H  LENGTH " ++ U32.show((n * 4 : U32))
      ++ "M  HEIGHT " ++ tenths((C.sub0(hi, lo) * 15 : U32)) ++ "M",
    Bool.pick(String, C.Test.testing(st), "TESTING: AN EMPTY TRAIN GOES ROUND",
    Bool.pick(String, C.Test.failed(st), "TEST FAILED: STALLS ON PIECE " ++ U32.show((f + 1 : U32)),
    Bool.pick(String, C.Track.closed(t), "NOT TESTED: PRESS TEST", "TRACK NOT FINISHED: PRESS BUILD"))))
  +l2 = Bool.pick(String, C.Test.passed(st), "DROPS " ++ U32.show(drops) ++ ", BIGGEST " ++ tenths((big * 15 : U32))
      ++ "M   AIR TIME " ++ tenths(air) ++ "S",
    Bool.pick(String, C.Test.failed(st), "(" ++ Piece.name(C.Piece.kind(C.Pieces.get(ps, f))) ++ "): TOO SLOW TO CLIMB IT", ""))
  +l3 = Bool.pick(String, C.Test.passed(st), "G " ++ cents(gv) ++ " DOWN  " ++ cents(gl) ++ " SIDEWAYS"
      ++ Bool.pick(String, (neg > 0 : U32), "  -" ++ cents(neg) ++ " UP", ""),
    Bool.pick(String, C.Test.failed(st), "ADD A LIFT HILL OR A BIGGER DROP BEFORE IT", ""))
  +col = sel(C.Test.failed(st), 16748688, sel(C.Test.passed(st), 12648447, 16766282))
  T(l1, (x + 6 : U32), (y + 51 : U32), col, T(l2, (x + 6 : U32), (y + 60 : U32), col,
    T(l3, (x + 6 : U32), (y + 69 : U32), col, acc)))

def Coaster.stats_dr(+t: C.Track, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  Coaster.stats_go(t, C.Dry.run(C.Track.pieces(t), C.Track.cfg(t)), x, y, acc)

def ride_win(+p: C.Park, +x: U32, +y: U32, +idx: U32, +o: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{map, +guests, +rides, +track, cash, +time, nid, fin, mess, staff} = p
  +rd = C.Rides.get(rides, idx)
  +k = C.Ride.kind(rd)
  +open = U32.is_eq(C.Ride.open_flag(rd), 1)
  +age = ((time - C.Ride.born(rd)) / 3600 : U32)
  +title = Bool.pick(String, U32.is_eq(k, 5), Coaster.name(track, C.Ride.ht(rd)), ride_name(k))
  +frame = ride_rates(k, C.Ride.rate(rd), x, y, window_box(title, x, y, 196, 154, acc))
  +waits = Bool.pick(+List<Dr>, C.Ride.cycles(k), ride_waits(C.Ride.wmin(rd), C.Ride.wmax(rd), x, y, frame), frame)
  +tk = C.Tracks.get(track, C.Ride.ht(rd))
  +waits2 = button("FOLLOW", (x + 150 : U32), (y + 38 : U32), 40, 5913248, waits)
  +armed = U32.is_eq((o >> 19n : U32), (idx + 1 : U32))
  +demo = Bool.pick(+List<Dr>, U32.is_eq(k, 5), button(Bool.pick(String, armed, "SURE? CLICK", "DEMOLISH"), (x + 140 : U32), (y + 88 : U32), 50,
    sel(armed, 14163020, 10498096), waits2), waits2)
  +build = Bool.pick(+List<Dr>, U32.is_eq(k, 5), button("BUILD", (x + 150 : U32), (y + 14 : U32), 40, 5913248,
    button("TEST", (x + 150 : U32), (y + 26 : U32), 40, sel(C.Track.closed(tk) && Bool.not(C.Track.open(tk)), 3831360, 5263440),
      Coaster.stats_dr(tk, x, y, demo))), waits2)
  button(Bool.pick(String, open, "OPEN", "CLOSED"), (x + 6 : U32), (y + 14 : U32), 44,
    sel(open, 3831360, 10498096),
  T(ride_state(rd), (x + 50 : U32), (y + 16 : U32), 12648447,
  T("PRICE *" ++ U32.show(C.Ride.price(rd)), (x + 6 : U32), (y + 28 : U32), 16766282,
  pm((x + 96 : U32), (y + 26 : U32),
  T("RIDERS " ++ U32.show(riders(guests, idx))
    ++ Bool.pick(String, U32.is_eq(k, 5), " (" ++ U32.show((C.Track.cars(C.Tracks.get(track, C.Ride.ht(rd))) * 2 : U32)) ++ " A TRAIN)", "/" ++ U32.show(C.Ride.seats(k)))
    ++ "   IN QUEUE " ++ U32.show(C.Ride.qlen(rd)), (x + 6 : U32), (y + 40 : U32), 15261888,
  T("CUSTOMERS " ++ U32.show(C.Ride.total(rd)), (x + 6 : U32), (y + 78 : U32), 15261888,
  T("INCOME *" ++ U32.show(C.Ride.earned(rd)), (x + 6 : U32), (y + 90 : U32), 11468718,
  T("AGE " ++ U32.show(age) ++ Bool.pick(String, U32.is_eq(age, 1), " MONTH", " MONTHS"),
    (x + 6 : U32), (y + 102 : U32), 15261888,
  T(Bool.pick(String, C.Ride.shop(k), "", "RELIABILITY " ++ U32.show((C.Wear.rel(C.Ride.wear(rd)) * 100 / 255 : U32)) ++ "%"),
    (x + 96 : U32), (y + 102 : U32), sel((C.Wear.rel(C.Ride.wear(rd)) < 150 : U32), 16748688, 15261888), build)))))))))

# Guests' names: from their id and class, always the same
def name_first(+n: U32) -> String:
  match n:
    case 0:
      "ALDRIC"
    case 1:
      "BRYNN"
    case 2:
      "CEDRIC"
    case 3:
      "DAGNY"
    case 4:
      "EIRA"
    case 5:
      "FENWICK"
    case 6:
      "GWEN"
    case 7:
      "HALVARD"
    case 8:
      "ISOLDE"
    case 9:
      "KESTREL"
    case 10:
      "LIORA"
    case 11:
      "MERRICK"
    case 12:
      "NESSA"
    case 13:
      "ORIN"
    case 14:
      "PELL"
    case 15:
      "QUILLON"
    case 16:
      "ROWAN"
    case 17:
      "SAOIRSE"
    case 18:
      "TAMSIN"
    case 19:
      "ULRIC"
    case 20:
      "VESNA"
    case 21:
      "WREN"
    case 22:
      "YSOLDE"
    case _:
      "BRAM"

def name_place(+n: U32) -> String:
  match n:
    case 0:
      "THORNWALL"
    case 1:
      "ASHFORD"
    case 2:
      "MIREFEN"
    case 3:
      "HOLLOWMERE"
    case 4:
      "STONEBRIDGE"
    case 5:
      "WYVERN HILL"
    case 6:
      "OAKHOLLOW"
    case 7:
      "DUNMORROW"
    case 8:
      "BRIARWOOD"
    case 9:
      "COLDHARBOR"
    case 10:
      "FERNDALE"
    case 11:
      "GREYMOOR"
    case 12:
      "HIGHCRAG"
    case 13:
      "MOSSGATE"
    case 14:
      "RAVENSKEEP"
    case _:
      "SILVERBROOK"

def name_epithet(+n: U32) -> String:
  match n:
    case 0:
      "WISE"
    case 1:
      "WANDERER"
    case 2:
      "STARGAZER"
    case 3:
      "UNHURRIED"
    case 4:
      "RED"
    case 5:
      "MUMBLER"
    case 6:
      "LEARNED"
    case _:
      "PATIENT"

def name_clan(+n: U32) -> String:
  match n:
    case 0:
      "IRONBEARD"
    case 1:
      "STONEFIST"
    case 2:
      "COPPERHELM"
    case 3:
      "DEEPDELVER"
    case 4:
      "ANVILSON"
    case 5:
      "GRIMBRAID"
    case 6:
      "OREHAND"
    case _:
      "FLINTBROW"

# halflings, gnomes and commoners go by family names, orcs by epithets
def name_halfling(+n: U32) -> String:
  match n:
    case 0:
      "BRAMBLEFOOT"
    case 1:
      "HOLLOWAY"
    case 2:
      "PUDDLEBY"
    case 3:
      "MOSSBANK"
    case 4:
      "APPLEDORE"
    case 5:
      "FERNWICK"
    case 6:
      "HONEYCOMB"
    case _:
      "TUMBLEDOWN"

def name_gnome(+n: U32) -> String:
  match n:
    case 0:
      "TINKERTOP"
    case 1:
      "WHISTLEPIPE"
    case 2:
      "SPROCKETT"
    case 3:
      "BUTTONBRIGHT"
    case 4:
      "GLIMMERWICK"
    case 5:
      "FIZZLEPOP"
    case 6:
      "COPPERKNOB"
    case _:
      "DAPPLEGLEAM"

def name_orc(+n: U32) -> String:
  match n:
    case 0:
      "BOLD"
    case 1:
      "LOUD"
    case 2:
      "HUNGRY"
    case 3:
      "GENTLE"
    case 4:
      "TUSKED"
    case 5:
      "GRUMBLER"
    case 6:
      "UNBOWED"
    case _:
      "MIGHTY"

def name_trade(+n: U32) -> String:
  match n:
    case 0:
      "MILLER"
    case 1:
      "COOPER"
    case 2:
      "THATCHER"
    case 3:
      "FLETCHER"
    case 4:
      "TANNER"
    case 5:
      "WEAVER"
    case 6:
      "CHANDLER"
    case _:
      "BREWER"

def guest_name.go(+folk: U32, +h: U32, first: String) -> String:
  match folk:
    case 0:
      first ++ " THE " ++ name_epithet(((h >> 8n) .&. 7 : U32))
    case 1:
      Bool.pick(String, U32.is_eq((h .&. 32 : U32), 0), "SIR ", "DAME ") ++ first ++ " OF " ++ name_place(((h >> 12n) .&. 15 : U32))
    case 2:
      first ++ " OF " ++ name_place(((h >> 16n) .&. 15 : U32))
    case 3:
      first ++ " " ++ name_clan(((h >> 20n) .&. 7 : U32))
    case 4:
      first ++ " " ++ name_halfling(((h >> 20n) .&. 7 : U32))
    case 5:
      first ++ " " ++ name_gnome(((h >> 20n) .&. 7 : U32))
    case 6:
      first ++ " THE " ++ name_orc(((h >> 20n) .&. 7 : U32))
    case _:
      first ++ " " ++ name_trade(((h >> 20n) .&. 7 : U32))

# nobles, pilgrims and children say so first
def name_title(+lk: U32, +h: U32) -> String:
  +outfit = ((lk >> 14n) .&. 3 : U32)
  Bool.pick(String, Bool.not(U32.is_eq((lk .&. 8 : U32), 0)), "YOUNG ",
    Bool.pick(String, U32.is_eq(outfit, 1) && Bool.not(U32.is_eq((lk .&. 7 : U32), 1)),
      Bool.pick(String, U32.is_eq((h .&. 32 : U32), 0), "LORD ", "LADY "),
    Bool.pick(String, U32.is_eq(outfit, 3), "PILGRIM ", "")))

def guest_name(+id: U32, +lk: U32) -> String:
  +h = C.hash(id, 91)
  name_title(lk, h) ++ guest_name.go((lk .&. 7 : U32), h, name_first((h % 24 : U32)))

# the guest with this id (a nobody with id NONE when they have left)
def Guests.find(+gs: +List<C.Guest>, +id: U32) -> C.Guest:
  match gs:
    case []:
      C.Guest{C.NONE(), 0, 0, 0, 3, C.NONE(), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
    case g <> rest:
      Bool.pick(C.Guest, U32.is_eq(C.Guest.id(g), id), g, Guests.find(rest, id))

def the_ride(+rs: +List<C.Ride>, +i: U32) -> String:
  "THE " ++ ride_name(C.Ride.kind(C.Rides.get(rs, i)))

# what a guest is doing
def activity(+st: U32, +tgt: U32, +onq: Bool, +rs: +List<C.Ride>) -> String:
  +shop = C.Ride.shop(C.Ride.kind(C.Rides.get(rs, tgt)))
  +privy = U32.is_eq(C.Ride.kind(C.Rides.get(rs, tgt)), 6)
  Bool.pick(String, U32.is_eq(st, 1), Bool.pick(String, privy, "VISITING ", Bool.pick(String, shop, "BUYING AT ", "RIDING ")) ++ the_ride(rs, tgt),
    Bool.pick(String, U32.is_eq(st, 2), "HEADING HOME", Bool.pick(String, U32.is_eq(st, 4), "RESTING ON A BENCH",
      Bool.pick(String, U32.is_eq(tgt, C.NONE()), "WANDERING",
        Bool.pick(String, onq, "QUEUING FOR ", "HEADING FOR ") ++ the_ride(rs, tgt)))))

def event_text(+code: U32, nm: String) -> String:
  match code:
    case 1:
      "NOT PAYING THAT FOR " ++ nm
    case 2:
      "WAITED TOO LONG FOR " ++ nm
    case 3:
      nm ++ " WAS GREAT!"
    case 9:
      "THIS PATH IS FILTHY"
    case 6:
      "STUCK ON " ++ nm ++ "!"
    case _:
      nm ++ " WAS TOO INTENSE"

def opt(on: Bool, s: String, +rest: +List<String>) -> +List<String>:
  Bool.pick(+List<String>, on, s <> rest, rest)

# thoughts: the latest (for a month), then how they feel
def thoughts(+mind: U32, +t: U32, +hu: U32, +th: U32, +na: U32, +en: U32, +ha: U32,
  +bl: U32, +rs: +List<C.Ride>) -> +List<String>:
  +code = C.Mind.code(mind)
  +recent = Bool.not(U32.is_eq(code, 0)) && ((((t >> 4n) - C.Mind.when(mind)) .&. 65535) < 225 : U32)
  opt(recent, event_text(code, the_ride(rs, C.Mind.ride(mind))),
  opt((bl > 180 : U32), "I NEED THE PRIVY", opt((hu > 170 : U32), "I'M HUNGRY", opt((th > 170 : U32), "I'M THIRSTY",
  opt((na > 120 : U32), "I FEEL SICK", opt((en < 50 : U32), "I'M TIRED",
  opt((ha < 70 : U32), "I'M NOT HAVING FUN", opt((ha > 215 : U32), "WHAT A WONDERFUL PARK!", []))))))))

def lines(+n: Nat, +xs: +List<String>, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n xs:
    case 0n _:
      acc
    case 1n+m Nil{}:
      acc
    case 1n+m Con{s, rest}:
      T(s, x, y, 16777215, lines(m, rest, x, (y + 10 : U32), acc))

def need_bar(label: String, +v: U32, +col: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(label, (x + 6 : U32), y, 15261888,
  R((x + 70 : U32), y, U32.max((U32.min(v, 255) * 100 / 255 : U32), 1), 5, col,
  R((x + 70 : U32), y, 100, 5, 4210752, acc)))

def carrying(+lk: U32) -> String:
  +it = ((lk >> 16n) .&. 7 : U32)
  Bool.pick(String, U32.is_eq(it, 1), "A POTION", Bool.pick(String, U32.is_eq(it, 2), "A TANKARD OF ALE",
    Bool.pick(String, U32.is_eq(it, 3), "A WISP", Bool.pick(String, U32.is_eq(it, 4), "AN ENCHANTED ICE", "NOTHING"))))

def guest_win.go(g: C.Guest, +p: C.Park, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Guest{+id, +gx, +gy, dir, +st, +tgt, tmr, +cash, +hu, +th, +en, +na, +ha, +lk, +mind, +bl} = g
  C.Park{map, guests, +rides, track, cash0, +time, nid, fin, mess, staff} = p
  +gone = U32.is_eq(id, C.NONE())
  +onq = U32.is_eq(C.Land.obj(map, (gx >> 4n : U32), (gy >> 4n : U32)), 7)
  +frame = window_box(Bool.pick(String, gone, "AN ADVENTURER", guest_name(id, lk)), x, y, 210, 144, acc)
  Bool.pick(+List<Dr>, gone, T("HAS LEFT THE PARK", (x + 6 : U32), (y + 16 : U32), 12648447, frame),
    T(activity(st, tgt, onq, rides), (x + 6 : U32), (y + 15 : U32), 12648447,
    lines(3n, thoughts(mind, time, hu, th, na, en, ha, bl, rides), (x + 6 : U32), (y + 28 : U32),
    need_bar("HAPPINESS", ha, 7324480, x, (y + 62 : U32),
    need_bar("ENERGY", en, 16766282, x, (y + 72 : U32),
    need_bar("HUNGER", hu, 14168128, x, (y + 82 : U32),
    need_bar("THIRST", th, 4227327, x, (y + 92 : U32),
    need_bar("NAUSEA", na, 9498256, x, (y + 102 : U32),
    need_bar("PRIVY", bl, 12620880, x, (y + 112 : U32),
    T("GOLD *" ++ U32.show(cash) ++ "   CARRYING " ++ carrying(lk), (x + 6 : U32), (y + 128 : U32), 16766282,
      button("FOLLOW", (x + 166 : U32), (y + 126 : U32), 38, 5913248, frame)))))))))))

def guest_win(+p: C.Park, +x: U32, +y: U32, +gid: U32, +acc: +List<Dr>) -> +List<Dr>:
  guest_win.go(Guests.find(C.Park.guests(p), gid), p, x, y, acc)

# the guest count over the last four months: 32 bars, newest on the right
def graph(+hs: +List<U32>, +i: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  match hs:
    case []:
      acc
    case v <> rest:
      +h = U32.max(U32.min((v * 50 / 700 : U32), 50), 1)
      graph(rest, (i + 1 : U32), x, y,
        R((x + (31 - i) * 5 : U32), (y + 50 - h : U32), 4, h, 7324480, acc))

# the park: its rating, guests, entry fee, and the guest count graph
# research as the interface sees it: which tool needs which discovery
def Res.name(+k: U32) -> String:
  match k:
    case 0:
      "HEALER'S TENT"
    case 1:
      "HEDGE LABYRINTH"
    case 2:
      "GOLEM BUMPERS"
    case 3:
      "WISP SELLER"
    case 4:
      "WHEEL OF STARS"
    case 5:
      "ENCHANTED ICES"
    case 6:
      "GRIFFIN SWING"
    case 7:
      "DRAGON'S EYRIE"
    case 8:
      "LICH'S CRYPT"
    case 9:
      "WIZARD'S WHIRL"
    case 10:
      "MERMAID FLUME"
    case 11:
      "STATUES AND FOUNTAINS"
    case _:
      "WALLS AND FENCES"

def res_rows(+r: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  +f = C.Res.funding(r)
  +pr = ((r >> 16n) .&. 255 : U32)
  +done = C.Res.done(r)
  T("RESEARCH", (x + 6 : U32), (y + 128 : U32), 16766282,
  button("NONE", (x + 70 : U32), (y + 126 : U32), 30, sel(U32.is_eq(f, 0), 3831360, 5913248),
  button("STEADY", (x + 104 : U32), (y + 126 : U32), 40, sel(U32.is_eq(f, 1), 3831360, 5913248),
  button("LAVISH", (x + 148 : U32), (y + 126 : U32), 40, sel(U32.is_eq(f, 2), 3831360, 5913248),
  T(Bool.pick(String, done, "EVERYTHING IS RESEARCHED",
      "NEXT: " ++ Res.name(C.Res.next(r)) ++ "  " ++ U32.show((pr * 100 / 256 : U32)) ++ "%   *"
      ++ U32.show(sel(U32.is_eq(f, 1), 150, sel(U32.is_eq(f, 2), 400, 0))) ++ "/MONTH"),
    (x + 6 : U32), (y + 140 : U32), 12648447,
  R((x + 6 : U32), (y + 152 : U32), U32.max(((pr * 188) >> 8n : U32), 1), 5, 7324480,
  R((x + 6 : U32), (y + 152 : U32), 188, 5, 4210752, acc)))))))

def Scn.name(+k: U32) -> String:
  match k:
    case 1:
      "MISTY HOLLOW"
    case 2:
      "THE DRAGON'S DEBT"
    case 3:
      "THE GRAND TOURNEY"
    case _:
      "THE ELDERGROVE FAIRE"

def Scn.goal(+k: U32) -> String:
  match k:
    case 1:
      "400 GUESTS AND RATING 600 BY MONTH 8"
    case 2:
      "REPAY THE LOAN, 300 GUESTS, BY MONTH 12"
    case 3:
      "RATING 850 AND 650 GUESTS BY MONTH 10"
    case _:
      "NO GOALS: BUILD AS YOU LIKE"

def park_win(+p: C.Park, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{map, +guests, +rides, track, cash, time, nid, +fin, mess, staff} = p
  +rating = C.Fin.rating(fin)
  +k = ((C.Fin.res(fin) >> 26n) .&. 15 : U32)
  +st = (C.Fin.res(fin) >> 30n : U32)
  +frame = T(Bool.pick(String, U32.is_eq(k, 0), "SANDBOX", "GOAL: " ++ Scn.goal(k)), (x + 6 : U32), (y + 162 : U32),
    sel(U32.is_eq(st, 1), 7324480, sel(U32.is_eq(st, 2), 16748688, 16766282)),
    res_rows(C.Fin.res(fin), x, y, window_box(Scn.name(k), x, y, 200, 176, acc)))
  T("PARK RATING " ++ U32.show(rating), (x + 6 : U32), (y + 15 : U32), 16766282,
  R((x + 96 : U32), (y + 15 : U32), U32.max((rating / 10 : U32), 1), 5, sel((rating < 400 : U32), 14163020, 7324480),
  R((x + 96 : U32), (y + 15 : U32), 100, 5, 4210752,
  T("GUESTS " ++ U32.show(C.len32(C.Guest, guests)) ++ "   HAPPY " ++ U32.show(happy_avg(guests, 0, 0)) ++ "%",
    (x + 6 : U32), (y + 28 : U32), 15261888,
  T("ENTRY FEE *" ++ U32.show(C.Fin.fee(fin)), (x + 6 : U32), (y + 42 : U32), 16766282,
  pm((x + 110 : U32), (y + 40 : U32),
  T("GUESTS, LAST FOUR MONTHS", (x + 6 : U32), (y + 58 : U32), 12648447,
  graph(C.Fin.hist(fin), 0, (x + 20 : U32), (y + 70 : U32),
  R((x + 18 : U32), (y + 70 : U32), 164, 52, 1973802, frame)))))))))

def fin_at(+xs: +List<U32>, +i: U32) -> U32:
  C.Tab.at(xs, i)

def fin_amt(+spend: Bool, +v: U32) -> String:
  Bool.pick(String, spend && (v > 0 : U32), "-*", "*") ++ U32.show(v)

# a row of the books: this month and last month (spend rows show a minus)
def fin_row(label: String, +i: U32, +spend: Bool, +now: +List<U32>, +last: +List<U32>, +x: U32, +y: U32,
  +acc: +List<Dr>) -> +List<Dr>:
  +col = sel(spend, 16750480, 11468718)
  T(label, (x + 6 : U32), y, 15261888,
  T(fin_amt(spend, fin_at(now, i)), (x + 110 : U32), y, col,
  T(fin_amt(spend, fin_at(last, i)), (x + 168 : U32), y, col, acc)))

# takings less costs (loans themselves aside)
def profit(+xs: +List<U32>) -> U32:
  (fin_at(xs, 0) + fin_at(xs, 3) + fin_at(xs, 4) + fin_at(xs, 5) + fin_at(xs, 6)
    - fin_at(xs, 1) - fin_at(xs, 2) - fin_at(xs, 9) - fin_at(xs, 10) : U32)

def fin_win(+p: C.Park, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{map, guests, rides, track, cash, time, nid, +fin, mess, staff} = p
  +now = C.Fin.now(fin)
  +last = C.Fin.last(fin)
  +frame = window_box("FINANCES", x, y, 224, 157, acc)
  T("THIS MONTH", (x + 110 : U32), (y + 14 : U32), 12648447,
  T("LAST MONTH", (x + 168 : U32), (y + 14 : U32), 12648447,
  fin_row("RIDE TICKETS", 0, False{}, now, last, x, (y + 26 : U32),
  fin_row("FOOD", 4, False{}, now, last, x, (y + 35 : U32),
  fin_row("DRINKS", 5, False{}, now, last, x, (y + 44 : U32),
  fin_row("ENTRY FEES", 6, False{}, now, last, x, (y + 53 : U32),
  fin_row("RIDE UPKEEP", 1, True{}, now, last, x, (y + 62 : U32),
  fin_row("CONSTRUCTION", 2, True{}, now, last, x, (y + 71 : U32),
  fin_row("REFUNDS", 3, False{}, now, last, x, (y + 80 : U32),
  fin_row("LOAN INTEREST", 9, True{}, now, last, x, (y + 89 : U32),
  fin_row("STAFF WAGES", 10, True{}, now, last, x, (y + 98 : U32),
  T("PROFIT", (x + 6 : U32), (y + 111 : U32), 16766282,
  T(money(profit(now)), (x + 110 : U32), (y + 111 : U32), 16766282,
  T(money(profit(last)), (x + 168 : U32), (y + 111 : U32), 16766282,
  R((x + 6 : U32), (y + 108 : U32), 212, 1, 8421504,
  T("LOAN *" ++ U32.show(C.Fin.loan(fin)), (x + 6 : U32), (y + 127 : U32), 16750480,
  T("INTEREST 1/80 A MONTH", (x + 6 : U32), (y + 141 : U32), 8421504,
  button("BORROW 1000", (x + 100 : U32), (y + 125 : U32), 54, 5913248,
  button("REPAY 1000", (x + 160 : U32), (y + 125 : U32), 54, 5913248, frame)))))))))))))))))))

def staff_row(name: String, desc: String, +k: U32, +ss: +List<C.Staff>, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(name ++ "  " ++ U32.show(C.Staff.count(ss, k)), (x + 6 : U32), y, 16766282,
  T(desc, (x + 6 : U32), (y + 9 : U32), 11579568,
  T("*" ++ U32.show(C.Staff.wage(k)) ++ "/MONTH", (x + 124 : U32), y, 16750480,
  pm((x + 178 : U32), (y - 2 : U32), button("FOLLOW", (x + 176 : U32), (y + 8 : U32), 28, 5913248, acc)))))

def staff_win(+p: C.Park, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  +ss = C.Park.staff(p)
  +frame = window_box("STAFF", x, y, 210, 114, acc)
  staff_row("BROWNIES", "SWEEP, EMPTY BINS, MEND THINGS", 1, ss, x, (y + 16 : U32),
  staff_row("DWARVEN TINKERS", "REPAIR RIDES THAT BREAK DOWN", 2, ss, x, (y + 38 : U32),
  staff_row("WATCH KNIGHTS", "KEEP VANDALS FROM SMASHING", 3, ss, x, (y + 60 : U32),
  staff_row("BARDS", "PLAY TO CHEER GUESTS UP", 4, ss, x, (y + 82 : U32),
  T("WAGES *" ++ U32.show(C.Staff.wages(ss)) ++ " A MONTH   STAFF " ++ U32.show(C.len32(C.Staff, ss)) ++ "/40",
    (x + 6 : U32), (y + 102 : U32), 12648447, frame)))))

def Opt.vol(+o: U32, +sh: Nat) -> U32:
  (3 - ((o >> sh) .&. 3) : U32)

# a click in the options window (codes 1000 + ...)
def opt_button(label: String, on: Bool, +x: U32, +y: U32, +w: U32, +acc: +List<Dr>) -> +List<Dr>:
  button(label, x, y, w, sel(on, 3831360, 5913248), acc)

def vol_bar(+v: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  DRect{x, y, U32.max((v * 14 : U32), 1), 5, 7324480} <> DRect{x, y, 42, 5, 4210752} <> acc

def opts_win(+o: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  +s = (o .&. 3 : U32)
  +whole = Bool.not(U32.is_eq((o .&. 4 : U32), 0))
  +dyn = U32.is_eq((o .&. 8 : U32), 0)
  +lo = Bool.not(U32.is_eq((o .&. 256 : U32), 0))
  +frame = button("KEYS", (x + 70 : U32), (y + 110 : U32), 60, 5913248,
    button("MAIN MENU", (x + 6 : U32), (y + 110 : U32), 60, 10498096, window_box("OPTIONS", x, y, 210, 124, acc)))
  T("WINDOW SIZE", (x + 6 : U32), (y + 16 : U32), 16766282,
  opt_button("1024X640", U32.is_eq(s, 0), (x + 6 : U32), (y + 26 : U32), 60,
  opt_button("1280X800", U32.is_eq(s, 1), (x + 70 : U32), (y + 26 : U32), 60,
  opt_button("1600X1000", U32.is_eq(s, 2), (x + 134 : U32), (y + 26 : U32), 70,
  T("PIXELS", (x + 6 : U32), (y + 40 : U32), 16766282,
  opt_button("STRETCH TO FIT", Bool.not(whole), (x + 6 : U32), (y + 50 : U32), 96,
  opt_button("WHOLE PIXELS", whole, (x + 106 : U32), (y + 50 : U32), 98,
  T("DYNAMIC RESOLUTION", (x + 6 : U32), (y + 65 : U32), 16766282,
  opt_button(Bool.pick(String, dyn, "ON", "OFF"), dyn, (x + 164 : U32), (y + 63 : U32), 40,
  T(Bool.pick(String, lo, "DRAWING AT HALF SIZE: UNDER 22 FPS", "DRAWING AT FULL SIZE"), (x + 6 : U32), (y + 75 : U32), 11579568,
  T("MUSIC VOLUME", (x + 6 : U32), (y + 88 : U32), 16766282, pm((x + 130 : U32), (y + 86 : U32),
  vol_bar(Opt.vol(o, 4n), (B() + x + 160 : U32), (B() + y + 88 : U32),
  T("EFFECTS VOLUME", (x + 6 : U32), (y + 100 : U32), 16766282, pm((x + 130 : U32), (y + 98 : U32),
  vol_bar(Opt.vol(o, 6n), (B() + x + 160 : U32), (B() + y + 100 : U32), frame))))))))))))))))

# dynamic resolution: when frames stay under 22 a second for two samples
# (about three seconds), draw at half resolution until half resolution holds
# 45 or more for ten samples, then go back to full
def Scn.of(+p: C.Park) -> U32:
  ((C.Fin.res(C.Park.fin(p)) >> 26n) .&. 15 : U32)

def Scn.status(+p: C.Park) -> U32:
  (C.Fin.res(C.Park.fin(p)) >> 30n : U32)

def Scn.award(+k: U32) -> String:
  match k:
    case 1:
      "THE SILVER LANTERN"
    case 2:
      "THE DRAGON'S SEAL"
    case _:
      "THE GOLDEN GRIFFIN"

def goal_win(+p: C.Park, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  +k = Scn.of(p)
  +won = U32.is_eq(Scn.status(p), 1)
  +frame = window_box(Bool.pick(String, won, "SCENARIO COMPLETE!", "THE SCENARIO IS LOST"), x, y, 210, 76, acc)
  T(Scn.name(k), (x + 6 : U32), (y + 16 : U32), 16766282,
  T(Scn.goal(k), (x + 6 : U32), (y + 28 : U32), 15261888,
  T(Bool.pick(String, won, "AWARDED " ++ Scn.award(k) ++ "!", "THE DEADLINE HAS PASSED."), (x + 6 : U32), (y + 44 : U32),
    sel(won, 7324480, 16748688),
  T("PLAY ON AS LONG AS YOU LIKE.", (x + 6 : U32), (y + 60 : U32), 11579568, frame))))

def Cons.op(+i: U32) -> U32:
  match i:
    case 0:
      0
    case 1:
      3
    case 2:
      4
    case 3:
      9
    case 4:
      1
    case 5:
      2
    case 6:
      12
    case 7:
      13
    case 8:
      10
    case 9:
      11
    case 10:
      6
    case 11:
      5
    case 12:
      7
    case 13:
      24
    case _:
      99

def Piece.label(+k: U32) -> String:
  match k:
    case 0:
      "STRAIGHT T"
    case 1:
      "GENTLE UP Y"
    case 2:
      "GENTLE DN B"
    case 3:
      "TURN LEFT G"
    case 4:
      "TURN RIGHT H"
    case 5:
      "STATION Z"
    case 6:
      "LIFT HILL L"
    case 7:
      "UNDO BKSP"
    case 24:
      "TEST RUN"
    case 9:
      "BRAKES J"
    case 10:
      "BANK LEFT Q"
    case 11:
      "BANK RIGHT E"
    case 12:
      "STEEP UP C"
    case _:
      "STEEP DN V"

def Cons.btn(+i: U32, +x: U32, +y: U32, +pv: U32, +q: C.Q, +trk: C.Track, +cash: U32,
  +acc: +List<Dr>) -> +List<Dr>:
  +op = Cons.op(i)
  +bx = (x + 6 + (i .&. 3) * 56 : U32)
  +by = (y + 26 + (i >> 2n) * 12 : U32)
  +fits = C.TrackOp.ok(q, trk, cash, op)
  +col = sel(U32.is_eq(op, 7), sel(fits, 10498096, 5263440), sel(U32.is_eq(op, 24), sel(fits, 3831360, 5263440),
    sel(fits, 5913248, 6045746)))
  +glow = U32.is_eq(op, pv)
  button(Piece.label(op), bx, by, 52, col,
    Bool.pick(+List<Dr>, glow, R(C.sub0(bx, 1), C.sub0(by, 1), 54, 11, 16766282, acc), acc))

def Cons.btns(+n: Nat, +i: U32, +x: U32, +y: U32, +pv: U32, +q: C.Q, +trk: C.Track, +cash: U32,
  +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+m:
      Cons.btn(i, x, y, pv, q, trk, cash, Cons.btns(m, (i + 1 : U32), x, y, pv, q, trk, cash, acc))

def lvls(+n: U32) -> String:
  U32.show(n) ++ Bool.pick(String, U32.is_eq(n, 1), " LEVEL", " LEVELS")

# how far the end of the track is from its start: tiles, then height
def Cons.home(+e: C.Pose, +s: C.Pose) -> String:
  +dist = (C.absd(C.Pose.x(e), C.Pose.x(s)) + C.absd(C.Pose.y(e), C.Pose.y(s)) : U32)
  +ez = C.Pose.z(e)
  +sz = C.Pose.z(s)
  "BACK TO THE STATION: " ++ U32.show(dist) ++ Bool.pick(String, U32.is_eq(dist, 1), " TILE", " TILES")
    ++ Bool.pick(String, U32.is_eq(ez, sz), ", SAME HEIGHT",
      Bool.pick(String, (ez > sz : U32), ", " ++ lvls((ez - sz : U32)) ++ " DOWN", ", " ++ lvls((sz - ez : U32)) ++ " UP"))

def sel_str(b: Bool, x: String, y: String) -> String:
  Bool.pick(String, b, x, y)

def Cons.type_btn(+ty: U32, +cur: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  +bx = (x + 62 + ty * 56 : U32)
  +by = (y + 76 : U32)
  button(sel_str(U32.is_eq(ty, 1), "MINECART", sel_str(U32.is_eq(ty, 2), "FLYER", "WYRM")), bx, by, 52, 5913248,
    Bool.pick(+List<Dr>, U32.is_eq(ty, cur), R(C.sub0(bx, 1), C.sub0(by, 1), 54, 11, 16766282, acc), acc))

def cons_win(+p: C.Park, +x: U32, +y: U32, +a: U32, +v: U32, +acc: +List<Dr>) -> +List<Dr>:
  C.Park{+map, guests, rides, +track, +cash, time, nid, fin, mess, staff} = p
  +trk = C.Tracks.get(track, a)
  +pv = ((v >> 24n) .&. 15 : U32)
  +n = C.len32(C.Piece, C.Track.pieces(trk))
  +e = C.Track.end(trk)
  +z = C.Pose.z(e)
  +z2 = ((z + C.Piece.rise(pv)) - C.Piece.drop(pv) : U32)
  +open = C.Track.open(trk)
  +closed = C.Track.closed(trk)
  +fits = C.TrackOp.ok(map, trk, cash, pv)
  +cost = C.Piece.cost(pv)
  +last = C.Piece.kind(C.Pieces.last(C.Track.pieces(trk)))
  +tst = C.Track.stats(trk)
  +testing = C.Test.testing(tst)
  +state = Bool.pick(String, open && testing, "TESTING", Bool.pick(String, open, "OPEN",
    Bool.pick(String, closed && C.Test.passed(tst), "TESTED", Bool.pick(String, closed && C.Test.failed(tst), "TEST FAILED",
    Bool.pick(String, closed, "CIRCUIT COMPLETE", "BUILDING")))))
  +why = Bool.pick(String, open && testing, "THE TEST TRAIN IS GOING ROUND...",
    Bool.pick(String, open, "CLOSE THE RIDE TO CHANGE ITS TRACK",
    Bool.pick(String, closed && C.Test.passed(tst), "TESTED: OPEN IT FROM ITS RIDE WINDOW",
    Bool.pick(String, closed && C.Test.failed(tst), "PIECE " ++ U32.show((C.Test.fail(tst) + 1 : U32)) ++ " IS TOO STEEP FOR ITS SPEED: SEE RED",
    Bool.pick(String, closed, "DONE: PRESS TEST RUN",
    Bool.pick(String, Bool.not(C.Build.can_pay(cash, cost)), "NOT ENOUGH GOLD FOR THIS PIECE",
    Bool.pick(String, U32.is_eq(pv, 5) && Bool.not(U32.is_eq(last, 5)), "A STATION ONLY EXTENDS THE PLATFORM",
    Bool.pick(String, Bool.not(C.Piece.faces(pv, C.Pose.d(e))), "STEEP CLIMBS HEAD TOWARD YOU, STEEP DROPS AWAY",
    Bool.pick(String, Bool.not(fits), "NO ROOM: LAND, SCENERY, WATER'S EDGE OR TOO HIGH",
      Cons.home(e, C.Track.start(trk)))))))))))
  +near = (C.absd(C.Pose.x(e), C.Pose.x(C.Track.start(trk))) + C.absd(C.Pose.y(e), C.Pose.y(C.Track.start(trk))) <= 3 : U32)
  +cfg = C.Track.cfg(trk)
  +ty = C.Cfg.type(cfg)
  +most = C.Track.most(n, C.Track.blen(C.Track.cars(trk)))
  +want = C.Cfg.trains(cfg)
  +trains = sel(U32.is_eq(want, 0), most, U32.min(want, most))
  +box = window_box(Coaster.name(track, a) ++ ": BUILD TRACK", x, y, 232, 138, acc)
  +set = T("TYPE", (x + 6 : U32), (y + 78 : U32), 15261888,
    Cons.type_btn(0, ty, x, y, Cons.type_btn(1, ty, x, y, Cons.type_btn(2, ty, x, y,
    T("TRAINS " ++ U32.show(trains), (x + 6 : U32), (y + 90 : U32), 15261888, pm((x + 44 : U32), (y + 88 : U32),
    T("CARS " ++ U32.show(C.Track.cars(trk)), (x + 78 : U32), (y + 90 : U32), 15261888, pm((x + 110 : U32), (y + 88 : U32),
    T("LIFT " ++ U32.show(C.Cfg.lift(cfg)), (x + 144 : U32), (y + 90 : U32), 15261888, pm((x + 176 : U32), (y + 88 : U32),
      box))))))))))
  T("PIECES " ++ U32.show(n) ++ "   HEIGHT " ++ U32.show(z), (x + 6 : U32), (y + 14 : U32), 15261888,
  T(state, (x + 150 : U32), (y + 14 : U32), sel(open && Bool.not(testing), 3831360, sel(closed && C.Test.failed(tst), 16748688,
    sel(closed || testing, 16766282, 16777215))),
  T(Bool.pick(String, open || closed, "", "NEXT: " ++ Piece.name(pv) ++ "  *" ++ U32.show(cost)
      ++ "  HEIGHT " ++ U32.show(z) ++ " TO " ++ U32.show(z2)),
    (x + 6 : U32), (y + 102 : U32), sel(fits, 12648384, 16748688),
  T(why, (x + 6 : U32), (y + 114 : U32), sel(closed && C.Test.failed(tst), 16748688,
    sel(fits && near && Bool.not(closed), 16766282, sel(fits || closed, 15261888, 16748688))),
  T("HOVER A PIECE TO PREVIEW IT, CLICK OR PRESS ITS KEY", (x + 6 : U32), (y + 126 : U32), 9474192,
    button("SAVE AS A DESIGN", (x + 118 : U32), (y + 62 : U32), 108, sel(closed, 5913248, 5263440),
      Cons.btns(14n, 0, x, y, pv, map, trk, cash, set)))))))

def keys_line(label: String, what: String, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  T(label, x, y, 16766282, T(what, (x + 46 : U32), y, 15261888, acc))

# every control on one page
def keys_win(+x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  +c = (x + 6 : U32)
  keys_line("CAMERA", "WASD OR ARROWS MOVE, PAGE UP/DOWN OR WHEEL ZOOM", c, (y + 16 : U32),
  keys_line("TOOLS", "1-6 OPEN A TAB (AGAIN FOR ITS NEXT TOOL)", c, (y + 28 : U32),
  keys_line("", "I INSPECT, X DEMOLISH, U QUEUE LINE, R TURN OR NEXT KIND", c, (y + 37 : U32),
  keys_line("", "RIGHT CLICK INSPECTS WITH ANY TOOL", c, (y + 46 : U32),
  keys_line("WINDOWS", "P PARK, F FINANCES, K STAFF, O OPTIONS", c, (y + 58 : U32),
  keys_line("", "ESC CLOSES THE FRONT WINDOW (WITH NONE OPEN, QUITS)", c, (y + 67 : U32),
  keys_line("TIME", "SPACE PAUSES, + AND - CHANGE THE SPEED", c, (y + 79 : U32),
  keys_line("SOUND", "M MUSIC ON OR OFF, N SOUNDS ON OR OFF", c, (y + 91 : U32),
  keys_line("SAVING", "F5 SAVES, F9 LOADS", c, (y + 103 : U32),
  keys_line("COASTERS", "WHILE A CONSTRUCTION WINDOW IS OPEN:", c, (y + 115 : U32),
  keys_line("", "T STRAIGHT, G/H TURN LEFT/RIGHT, Q/E BANKED TURN", c, (y + 124 : U32),
  keys_line("", "Y/B GENTLE UP/DOWN, C/V STEEP UP/DOWN", c, (y + 133 : U32),
  keys_line("", "L LIFT HILL, J BRAKES, Z STATION, BACKSPACE UNDO", c, (y + 142 : U32),
  keys_line("FOLLOW", "FOLLOW IN A RIDE, GUEST OR STAFF WINDOW,", c, (y + 154 : U32),
  keys_line("", "ANY CAMERA KEY LETS GO", c, (y + 163 : U32),
  keys_line("MOUSE", "CLICK TO BUILD, DRAG PATHS AND LAND, DRAG A WINDOW", c, (y + 175 : U32),
  keys_line("", "BY ITS TITLE BAR, THE X CLOSES IT", c, (y + 184 : U32),
    window_box("KEYS", x, y, 320, 198, acc))))))))))))))))))

def Words.take(+ws: +List<U32>, +n: U32) -> +List<U32>:
  match ws:
    case []:
      []
    case w <> rest:
      Bool.pick(+List<U32>, U32.is_eq(n, 0), [], w <> Words.take(rest, (n - 1 : U32)))

def Words.drop(+ws: +List<U32>, +n: U32) -> +List<U32>:
  match ws:
    case []:
      []
    case w <> rest:
      Bool.pick(+List<U32>, U32.is_eq(n, 0), w <> rest, Words.drop(rest, (n - 1 : U32)))

def Lib.slot(+ds: +List<U32>, +i: U32) -> +List<U32>:
  Words.take(Words.drop(ds, (i * 256 : U32)), 256)

# a new design goes in the next slot; with all eight full, the oldest goes
def Design.virt(+ks: +List<U32>, +n: U32, +e: C.Pose) -> +List<C.Piece>:
  match ks:
    case []:
      []
    case kd <> rest:
      +pc = {C.Piece{C.Pose.x(e), C.Pose.y(e), C.Pose.z(e), kd, C.Pose.d(e)} : C.Piece}
      Bool.pick(+List<C.Piece>, U32.is_eq(n, 0), [], pc <> Design.virt(rest, (n - 1 : U32), C.Piece.exit(pc)))

def Design.rate(+w: +List<U32>) -> U32:
  +n = C.Tab.at(w, 0)
  +cfg = C.Tab.at(w, 1)
  +st = {C.Piece{32, 32, 6, 5, 0} : C.Piece}
  +ps = {st <> Design.virt(Words.drop(w, 2), n, C.Piece.exit(st)) : +List<C.Piece>}
  C.Dry.rate(C.Dry.run(ps, cfg), cfg)

# laying a design's pieces from pose e: the total price, or NONE if any
# piece has no room (or a steep piece would face away)
def designs_row(+ds: +List<U32>, +i: U32, +sel_i: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  +w = Lib.slot(ds, i)
  +n = C.Tab.at(w, 0)
  +r = Design.rate(w)
  +yy = (y + 16 + i * 12 : U32)
  +on = U32.is_eq(i, sel_i)
  +line = U32.show((i + 1 : U32)) ++ "  " ++ Bool.pick(String, U32.is_eq(n, 0), "EMPTY",
    Coaster.tname(C.Cfg.type(C.Tab.at(w, 1))) ++ "  " ++ U32.show((n + 1 : U32)) ++ " PIECES   EXC " ++ cents(C.Rate.e(r))
      ++ "  INT " ++ cents(C.Rate.i(r)))
  T(line, (x + 8 : U32), (yy + 2 : U32), sel(U32.is_eq(n, 0), 9474192, sel(on, 16766282, 15261888)),
    Bool.pick(+List<Dr>, on, R((x + 4 : U32), yy, 252, 10, 4863024, acc), acc))

def designs_rows(+n: Nat, +i: U32, +ds: +List<U32>, +sel_i: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+m:
      designs_row(ds, i, sel_i, x, y, designs_rows(m, (i + 1 : U32), ds, sel_i, x, y, acc))

def designs_win(+ds: +List<U32>, +v: U32, +x: U32, +y: U32, +acc: +List<Dr>) -> +List<Dr>:
  T("SAVE FROM A BUILD WINDOW. PICK, CLICK TO BUILD, R TURNS", (x + 6 : U32), (y + 114 : U32), 9474192,
    designs_rows(8n, 0, ds, ((v >> 28n) .&. 7 : U32), x, y, window_box("TRACK DESIGNS", x, y, 260, 124, acc)))

def win_dr.go(+k: U32, +x: U32, +y: U32, +a: U32, +p: C.Park, +o: U32, +v: U32, +ds: +List<U32>, +acc: +List<Dr>) -> +List<Dr>:
  match k:
    case 1:
      ride_win(p, x, y, a, o, acc)
    case 2:
      park_win(p, x, y, acc)
    case 3:
      fin_win(p, x, y, acc)
    case 4:
      guest_win(p, x, y, a, acc)
    case 5:
      staff_win(p, x, y, acc)
    case 6:
      opts_win(o, x, y, acc)
    case 7:
      goal_win(p, x, y, acc)
    case 8:
      cons_win(p, x, y, a, v, acc)
    case 9:
      keys_win(x, y, acc)
    case 10:
      designs_win(ds, v, x, y, acc)
    case _:
      acc

def wins_dr(+ws: +List<Win>, +p: C.Park, +o: U32, +v: U32, +ds: +List<U32>, +acc: +List<Dr>) -> +List<Dr>:
  match ws:
    case []:
      acc
    case w <> rest:
      Win{+k, +x, +y, +a} = w
      win_dr.go(k, x, y, a, p, o, v, ds, wins_dr(rest, p, o, v, ds, acc))

# Clicking in windows: 0 nothing, 1 close, 2 drag, 100 + op: a ride setting

def in_box(+lx: U32, +ly: U32, +x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  (lx >= x : U32) && (lx < x + w : U32) && (ly >= y : U32) && (ly < y + h : U32)

def ride_click(+lx: U32, +ly: U32) -> U32:
  sel(in_box(lx, ly, 6, 14, 44, 9), 100, sel(in_box(lx, ly, 150, 14, 40, 9), 400, sel(in_box(lx, ly, 150, 26, 40, 9), 107,
  sel(in_box(lx, ly, 150, 38, 40, 9), 520, sel(in_box(lx, ly, 140, 88, 50, 9), 109,
  sel(in_box(lx, ly, 96, 26, 11, 9), 102, sel(in_box(lx, ly, 110, 26, 11, 9), 101,
  sel(in_box(lx, ly, 96, 50, 11, 9), 104, sel(in_box(lx, ly, 110, 50, 11, 9), 103,
  sel(in_box(lx, ly, 96, 62, 11, 9), 106, sel(in_box(lx, ly, 110, 62, 11, 9), 105, 0)))))))))))

def park_click(+lx: U32, +ly: U32) -> U32:
  sel(in_box(lx, ly, 110, 40, 11, 9), 201, sel(in_box(lx, ly, 124, 40, 11, 9), 200,
  sel(in_box(lx, ly, 70, 126, 30, 9), 240, sel(in_box(lx, ly, 104, 126, 40, 9), 241,
  sel(in_box(lx, ly, 148, 126, 40, 9), 242, 0)))))

def fin_click(+lx: U32, +ly: U32) -> U32:
  sel(in_box(lx, ly, 100, 125, 54, 9), 202, sel(in_box(lx, ly, 160, 125, 54, 9), 203, 0))

# staff on screen, drawn as people in uniform (look bit 26, kind - 1 in
# bits 27-28): Brownies small and bearded, Tinkers dwarves, Knights in
# armour, Bards hooded
def Staff.cls(+k: U32) -> U32:
  match k:
    case 1:
      3
    case 2:
      3
    case 3:
      1
    case _:
      2

def staff_dyn(+ss: +List<C.Staff>, +q: C.Q, +camx: U32, +camy: U32, +vw: U32, +vh: U32, +t: U32,
  +acc: +List<Dyn>) -> +List<Dyn>:
  match ss:
    case []:
      acc
    case s <> rest:
      C.Staff{+id, +x, +y, +dir, +kind, +st, tgt, tmr, zone, +look} = s
      +i = (x >> 4n : U32)
      +j = (y >> 4n : U32)
      +h = C.Land.h(q, i, j)
      +sx = ((B() + 1280 + x) - (y + camx) : U32)
      +sy = ((B() + 512 + ((x + y) >> 1n)) - (8 * h + Stair.dz(q, x, y, h) + camy) : U32)
      +vis = (sx + 8 > B() : U32) && (sx < B() + vw + 8 : U32) && (sy + 4 > B() : U32) && (sy < B() + vh + 28 : U32)
      +working = U32.is_eq(kind, 2) && U32.is_eq(st, 2)
      +lk = (Staff.cls(kind) .|. ((look .&. 3) << 8n) .|. ((dir .&. 3) << 12n) .|. sel(working, 0, 16777216)
        .|. 67108864 .|. (((kind - 1) .&. 3) << 27n) : U32)
      staff_dyn(rest, q, camx, camy, vw, vh, t,
        Bool.pick(+List<Dyn>, vis, Dyn{(i + j : U32), DGuest{sx, sy, lk, (t + id : U32)}} <> acc, acc))

# the staff window: hire (+) or let go (-) each kind, and the wage bill
def staff_click(+lx: U32, +ly: U32) -> U32:
  +r = sel((ly >= 14 : U32), ((ly - 14) / 22 : U32), 9)
  +y0 = (14 + r * 22 : U32)
  sel((r < 4 : U32) && in_box(lx, ly, 178, y0, 11, 9), (231 + r : U32),
    sel((r < 4 : U32) && in_box(lx, ly, 192, y0, 11, 9), (221 + r : U32),
    sel((r < 4 : U32) && in_box(lx, ly, 176, (y0 + 10 : U32), 28, 9), (510 + r : U32), 0)))

# Options (UI opt): bits 0-1 window size (1024 x 640, 1280 x 800,
# 1600 x 1000), 2 whole pixels (else stretched to fit), 3 dynamic
# resolution off, 4-5 and 6-7 how much quieter the music and the effects
# are (0 loudest .. 3 silent), 8 drawing at half resolution now, 9-13 how
# long it has, 14 the window wants resizing
def UI.opt(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  opt

def UI.with_opt(u: UI, +o: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, o, fol}

def Opt.w(+o: U32) -> U32:
  +s = (o .&. 3 : U32)
  sel(U32.is_eq(s, 1), 1280, sel(U32.is_eq(s, 2), 1600, 1024))

def Opt.h(+o: U32) -> U32:
  +s = (o .&. 3 : U32)
  sel(U32.is_eq(s, 1), 800, sel(U32.is_eq(s, 2), 1000, 640))

def Opt.click(+o: U32, +code: U32) -> U32:
  +size = (code >= 1000 : U32) && (code <= 1002 : U32)
  +mode = (code >= 1010 : U32) && (code <= 1011 : U32)
  +mq = ((o >> 4n) .&. 3 : U32)
  +fq = ((o >> 6n) .&. 3 : U32)
  +mq2 = sel(U32.is_eq(code, 1030), U32.min((mq + 1 : U32), 3), sel(U32.is_eq(code, 1031), C.sub0(mq, 1), mq))
  +fq2 = sel(U32.is_eq(code, 1032), U32.min((fq + 1 : U32), 3), sel(U32.is_eq(code, 1033), C.sub0(fq, 1), fq))
  +o1 = sel(size, ((o .&. 4294967292) .|. (code - 1000) .|. 16384 : U32),
    sel(mode, ((o .&. 4294967291) .|. ((code - 1010) << 2n) .|. 16384 : U32),
    sel(U32.is_eq(code, 1020), (o .^. 8 : U32), o)))
  ((o1 .&. 4294967055) .|. (mq2 << 4n) .|. (fq2 << 6n) .|. sel(U32.is_eq(code, 1040), 262144, 0) : U32)

def opts_click(+lx: U32, +ly: U32) -> U32:
  sel(in_box(lx, ly, 6, 26, 60, 9), 1000, sel(in_box(lx, ly, 70, 26, 60, 9), 1001,
  sel(in_box(lx, ly, 134, 26, 70, 9), 1002,
  sel(in_box(lx, ly, 6, 50, 96, 9), 1010, sel(in_box(lx, ly, 106, 50, 98, 9), 1011,
  sel(in_box(lx, ly, 164, 63, 40, 9), 1020,
  sel(in_box(lx, ly, 130, 86, 11, 9), 1030, sel(in_box(lx, ly, 144, 86, 11, 9), 1031,
  sel(in_box(lx, ly, 130, 98, 11, 9), 1032, sel(in_box(lx, ly, 144, 98, 11, 9), 1033,
  sel(in_box(lx, ly, 6, 110, 60, 9), 1040, sel(in_box(lx, ly, 70, 110, 60, 9), 1041, 0))))))))))))

def Opt.dyn(+o: U32, +f: U32) -> U32:
  +dyn = U32.is_eq((o .&. 8 : U32), 0)
  +lo = Bool.not(U32.is_eq((o .&. 256 : U32), 0))
  +cnt = ((o >> 9n) .&. 31 : U32)
  +slow = (f < 22 : U32) && (f > 0 : U32)
  +fast = (f >= 45 : U32)
  +cnt1 = sel(lo, sel(fast, (cnt + 1 : U32), 0), sel(slow, (cnt + 1 : U32), 0))
  +flip = lo && (cnt1 >= 10 : U32) || Bool.not(lo) && (cnt1 >= 2 : U32)
  +lo2 = dyn && (flip && Bool.not(lo) || Bool.not(flip) && lo)
  +cnt2 = sel(flip, 0, U32.min(cnt1, 31))
  ((o .&. 4294951167) .|. sel(lo2, 256, 0) .|. (cnt2 << 9n) : U32)

# Scenarios (the books' res bits 26-29; 0 sandbox) and their goals
def Scn.deadline(+k: U32) -> U32:
  match k:
    case 1:
      8
    case 2:
      12
    case 3:
      10
    case _:
      0

def Goal.met(+k: U32, +p: C.Park) -> Bool:
  +n = C.len32(C.Guest, C.Park.guests(p))
  +rating = C.Fin.rating(C.Park.fin(p))
  +loan = C.Fin.loan(C.Park.fin(p))
  U32.is_eq(k, 1) && (n >= 400 : U32) && (rating >= 600 : U32)
    || U32.is_eq(k, 2) && U32.is_eq(loan, 0) && (n >= 300 : U32)
    || U32.is_eq(k, 3) && (rating >= 850 : U32) && (n >= 650 : U32)

# the park op a running scenario calls for now: 50 won, 51 lost, 0 none
def Goal.op(+p: C.Park) -> U32:
  +k = Scn.of(p)
  +run = Bool.not(U32.is_eq(k, 0)) && U32.is_eq(Scn.status(p), 0)
  +late = (C.Park.time(p) >= Scn.deadline(k) * 3600 : U32)
  sel(run && Goal.met(k, p), 50, sel(run && late, 51, 0))

def hollow_acts() -> List<C.Act>:
  [C.Build{5, 33, 30, 0}, C.Build{7, 33, 44, 0}, C.Build{16, 33, 50, 0}, C.ParkOp{21}]

# a scenario's park: its land and rides, gold, loan and research (steady
# funding; the Dragon's Debt starts with three shops researched)
type Game is Data:
  Game{park: C.Park, ui: UI, wm: WM, snd: Z.Snd, ds: List<&2, U32>}

def Game.park(g: Game) -> C.Park:
  Game{p, ui, wm, snd, ds} = g
  p

# Placing things: a ghost of what the tool would build under the mouse, green
# where it can go and red where it can't (k: tool | ok << 8 | size << 9 |
# ride kind << 12), and its cost beside the mouse
def UI.new() -> UI:
  UI{930, 880, 0, 0, 0, 0, 12, 0, 2, 0, 0, 0, 99999, 4, 0, 0n, 0, 0}

def coaster_acts() -> List<C.Act>:
  [C.Build{10, 16, 38, 0}, C.TrackOp{5}, C.TrackOp{5}, C.TrackOp{6},
   C.TrackOp{6}, C.TrackOp{6}, C.TrackOp{0}, C.TrackOp{4}, C.TrackOp{2},
   C.TrackOp{2}, C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{4}, C.TrackOp{0},
   C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{0},
   C.TrackOp{2}, C.TrackOp{4}, C.TrackOp{0}, C.TrackOp{0}, C.TrackOp{0},
   C.TrackOp{0}, C.TrackOp{4}, C.TrackOp{25}, C.TrackOp{8}]

# a patch cleared for a second coaster at (40, 56)
def clear2_acts() -> List<C.Act>:
  [C.Build{9, 38, 54, 0}, C.Build{9, 39, 54, 0}, C.Build{9, 40, 54, 0}, C.Build{9, 41, 54, 0}, C.Build{9, 42, 54, 0},
   C.Build{9, 43, 54, 0}, C.Build{9, 44, 54, 0}, C.Build{9, 45, 54, 0}, C.Build{9, 46, 54, 0}, C.Build{9, 47, 54, 0},
   C.Build{9, 38, 55, 0}, C.Build{9, 39, 55, 0}, C.Build{9, 40, 55, 0}, C.Build{9, 41, 55, 0}, C.Build{9, 42, 55, 0},
   C.Build{9, 43, 55, 0}, C.Build{9, 44, 55, 0}, C.Build{9, 45, 55, 0}, C.Build{9, 46, 55, 0}, C.Build{9, 47, 55, 0},
   C.Build{9, 38, 56, 0}, C.Build{9, 39, 56, 0}, C.Build{9, 40, 56, 0}, C.Build{9, 41, 56, 0}, C.Build{9, 42, 56, 0},
   C.Build{9, 43, 56, 0}, C.Build{9, 44, 56, 0}, C.Build{9, 45, 56, 0}, C.Build{9, 46, 56, 0}, C.Build{9, 47, 56, 0},
   C.Build{9, 38, 57, 0}, C.Build{9, 39, 57, 0}, C.Build{9, 40, 57, 0}, C.Build{9, 41, 57, 0}, C.Build{9, 42, 57, 0},
   C.Build{9, 43, 57, 0}, C.Build{9, 44, 57, 0}, C.Build{9, 45, 57, 0}, C.Build{9, 46, 57, 0}, C.Build{9, 47, 57, 0},
   C.Build{9, 38, 58, 0}, C.Build{9, 39, 58, 0}, C.Build{9, 40, 58, 0}, C.Build{9, 41, 58, 0}, C.Build{9, 42, 58, 0},
   C.Build{9, 43, 58, 0}, C.Build{9, 44, 58, 0}, C.Build{9, 45, 58, 0}, C.Build{9, 46, 58, 0}, C.Build{9, 47, 58, 0}]

# a small second loop for the save test, on that patch: a lift hill, a steep
# drop, banked turns and brakes; a Dwarven Minecart with its lift one step
# faster, pre-tested
def loop2_acts() -> List<C.Act>:
  List.append(&1, C.Act, clear2_acts(), [C.Build{10, 40, 56, 0}, C.TrackOp{37}, C.TrackOp{38}, C.TrackOp{38}, C.TrackOp{45},
   C.TrackOp{43}, C.TrackOp{43}, C.TrackOp{41}, C.TrackOp{32}, C.TrackOp{32},
   C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{43}, C.TrackOp{43}, C.TrackOp{49},
   C.TrackOp{55}, C.TrackOp{57}, C.TrackOp{40}])

# the same loop two pieces short of closing, for pictures of the
# construction window
def demo_acts() -> List<C.Act>:
  List.append(&1, C.Act, clear2_acts(), [C.Build{10, 40, 56, 0}, C.TrackOp{37}, C.TrackOp{38}, C.TrackOp{38}, C.TrackOp{45},
   C.TrackOp{43}, C.TrackOp{43}, C.TrackOp{41}, C.TrackOp{32}, C.TrackOp{32},
   C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{49}])

def track_report(+ts: +List<C.Track>, +k: U32) -> String:
  match ts:
    case []:
      ""
    case t <> rest:
      +t2 = t
      " [coaster " ++ U32.show(k) ++ ": " ++ U32.show(C.len32(C.Piece, C.Track.pieces(t2)))
        ++ " pieces, closed " ++ Bool.show(C.Track.closed(t2)) ++ ", open " ++ Bool.show(C.Track.open(t2))
        ++ ", trains " ++ U32.show(U32.from_nat(C.Blocks.trains(C.Track.blocks(t2)))) ++ ", settings " ++ U32.show(C.Track.cfg(t2)) ++ "]" ++ track_report(rest, (k + 1 : U32))

def start_acts() -> List<C.Act>:
  [C.Build{5, 33, 30, 0}, C.Build{6, 31, 40, 0}, C.Build{7, 33, 44, 0},
   C.Build{8, 31, 48, 0}, C.Build{7, 13, 26, 0}, C.Build{6, 33, 24, 0},
   C.Build{8, 51, 30, 0}, C.Build{5, 47, 37, 0},
   C.Build{14, 32, 53, 0}, C.Build{13, 32, 52, 0}, C.Build{15, 32, 50, 0},
   C.Build{15, 32, 34, 0}, C.Build{14, 24, 36, 0}, C.Build{13, 26, 36, 0},
   C.Build{15, 28, 36, 0}, C.Build{14, 30, 46, 0}, C.Build{13, 34, 46, 0},
   C.Build{16, 33, 50, 0}, C.Build{16, 13, 31, 0}, C.Build{30, 33, 47, 0}, C.Build{32, 31, 37, 0}, C.Build{31, 35, 37, 0},
   C.Build{34, 33, 38, 0}, C.Build{11, 34, 37, 0},
   C.Build{41, 31, 33, 0}, C.Build{41, 33, 33, 2}, C.Build{43, 31, 35, 0}, C.Build{43, 33, 35, 2},
   C.Build{42, 29, 38, 0}, C.Build{44, 35, 22, 0}, C.Build{44, 36, 22, 0}, C.Build{44, 37, 22, 0},
   C.Build{44, 37, 23, 0}, C.Build{45, 27, 25, 0}, C.Build{45, 27, 26, 0}, C.Build{45, 27, 27, 0},
   C.Build{2, 44, 19, 0}, C.Build{9, 44, 19, 0}, C.Build{1, 44, 19, 0}, C.Build{9, 44, 18, 0},
   C.Build{1, 44, 18, 0}, C.Build{9, 44, 17, 0}, C.Build{1, 44, 17, 0}, C.Build{9, 44, 16, 0},
   C.Build{1, 44, 16, 0}, C.Build{9, 44, 15, 0}, C.Build{1, 44, 15, 0}, C.Build{9, 44, 14, 0},
   C.Build{1, 44, 14, 0}, C.Build{9, 44, 13, 0}, C.Build{41, 44, 13, 3},
   C.Build{9, 22, 21, 0}, C.Build{1, 22, 21, 0}, C.Build{9, 22, 22, 0}, C.Build{1, 22, 22, 0},
   C.Build{9, 22, 23, 0}, C.Build{1, 22, 23, 0}, C.Build{9, 22, 24, 0}, C.Build{1, 22, 24, 0},
   C.Build{9, 22, 25, 0}, C.Build{1, 22, 25, 0}, C.Build{9, 22, 26, 0}, C.Build{1, 22, 26, 0},
   C.Build{9, 22, 27, 0}, C.Build{1, 22, 27, 0}, C.Build{9, 22, 28, 0}, C.Build{1, 22, 28, 0},
   C.Build{9, 22, 29, 0}, C.Build{1, 22, 29, 0}, C.Build{9, 22, 30, 0}, C.Build{1, 22, 30, 0},
   C.Build{9, 22, 31, 0}, C.Build{1, 22, 31, 0}, C.Build{9, 22, 32, 0}, C.Build{1, 22, 32, 0},
   C.Build{9, 22, 33, 0}, C.Build{1, 22, 33, 0}, C.Build{9, 22, 34, 0}, C.Build{1, 22, 34, 0},
   C.Build{9, 22, 35, 0}, C.Build{1, 22, 35, 0},
   C.ParkOp{21}, C.ParkOp{21}, C.ParkOp{22}, C.ParkOp{23}, C.ParkOp{24}]

def Lib.empty() -> List<&2, U32>:
  C.Tab.zero(2048, [])

def Game.new() -> Game:
  +p0 = C.Park.run(start_acts(), C.Park.new())
  +p1 = C.Park.run(coaster_acts(), p0)
  Game{p1, UI.new(), WM.new(), Z.Snd.new(), Lib.empty()}

# The app
# -------

def Scn.park(+k: U32) -> C.Park:
  match k:
    case 1:
      C.Park.setup(C.Park.run(hollow_acts(), C.Park.new()), 12000, 0, ((1 << 26n) .|. (1 << 24n) : U32))
    case 2:
      C.Park.setup(Game.park(Game.new()), 2000, 15000, (41 .|. (2 << 26n) .|. (1 << 24n) : U32))
    case 3:
      C.Park.setup(Game.park(Game.new()), 20000, 0, ((3 << 26n) .|. (1 << 24n) : U32))
    case _:
      Game.park(Game.new())

def Scn.swap(ask: Bool, +req: U32, +p: C.Park) -> C.Park:
  match ask:
    case True{}:
      Scn.park((req - 1 : U32))
    case False{}:
      p

# Awards, each new month: the first the park earns (0 none)
def Award.thrills(+rs: +List<C.Ride>) -> U32:
  match rs:
    case []:
      0
    case r <> rest:
      +k = C.Ride.kind(r)
      (sel(U32.is_eq(k, 2) || U32.is_eq(k, 5) || U32.is_eq(k, 10) || U32.is_eq(k, 16) || U32.is_eq(k, 17), 1, 0) + Award.thrills(rest) : U32)

def Award.pick(now: Bool, +p: C.Park) -> U32:
  match now:
    case True{}:
      +n = C.len32(C.Guest, C.Park.guests(p))
      +tidy = (C.len32(U32, C.Park.mess(p)) < 15 : U32) && (n >= 150 : U32)
      +pretty = (C.Scen.count(4096n, 0, C.Park.map(p), 0) >= 20 : U32)
      +happy = (happy_avg(C.Park.guests(p), 0, 0) >= 75 : U32) && (n >= 200 : U32)
      +staffed = (C.len32(C.Staff, C.Park.staff(p)) >= 8 : U32)
      +thrill = (Award.thrills(C.Park.rides(p)) >= 4 : U32)
      sel(tidy, 131, sel(pretty, 132, sel(happy, 133, sel(staffed, 134, sel(thrill, 135, 0)))))
    case False{}:
      0

# The main menu (UI opt bit 18), over the park; a choice asks (bits 15-17)
# for a new park, which the next step builds
def menu_btn(label: String, sub: String, +y: U32, +hot: Bool, +acc: +List<Dr>) -> +List<Dr>:
  T(label, 122, (y + 2 : U32), sel(hot, 16766282, 16777215),
  T(sub, 122, (y + 13 : U32), 11579568,
  R(116, y, 280, 11, sel(hot, 6957706, 4863024), acc)))

def menu_hot(+mx: U32, +my: U32, +y: U32) -> Bool:
  in_box(mx, my, 116, y, 280, 11)

def menu_dr(+mx: U32, +my: U32) -> +List<Dr>:
  T("ELDERGROVE FAIRE", 222, 50, 16766282,
  T("A FAIRE OF WONDERS, BUILT BY YOU", 190, 60, 12648447,
  menu_btn("SANDBOX: THE ELDERGROVE FAIRE", "EVERY RIDE, NO GOALS", 76, menu_hot(mx, my, 76),
  menu_btn("SCENARIO: MISTY HOLLOW", "AN EMPTY VALE. " ++ Scn.goal(1), 104, menu_hot(mx, my, 104),
  menu_btn("SCENARIO: THE DRAGON'S DEBT", "15000 OWED. " ++ Scn.goal(2), 132, menu_hot(mx, my, 132),
  menu_btn("SCENARIO: THE GRAND TOURNEY", Scn.goal(3), 160, menu_hot(mx, my, 160),
  menu_btn("LOAD THE SAVED PARK", "F9 IN THE PARK DOES THE SAME", 188, menu_hot(mx, my, 188),
  menu_btn("QUIT", "", 216, menu_hot(mx, my, 216),
  R(106, 40, 300, 200, 2763330, R(104, 38, 304, 204, 13148232, R(108, 43, 304, 204, 1052688, [])))))))))))

type EV is Data:
  EV{ui: UI, wm: WM, acts: List<&2, C.Act>, quit: Bool}

# the camera: the arrows, or W A S D
def on_menu(+lx: U32, +ly: U32, +down: Bool, +ui: UI, +wm: WM) -> EV:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, +io, fps, tl, +opt, fol} = ui
  +k = sel(menu_hot(lx, ly, 76), 1, sel(menu_hot(lx, ly, 104), 2, sel(menu_hot(lx, ly, 132), 3,
    sel(menu_hot(lx, ly, 160), 4, sel(menu_hot(lx, ly, 188), 5, sel(menu_hot(lx, ly, 216), 6, 0))))))
  +pick = down && (k >= 1 : U32) && (k <= 4 : U32)
  +load = down && U32.is_eq(k, 5)
  +opt2 = sel(pick, ((opt .&. 4294705151) .|. (k << 15n) : U32), sel(load, (opt .&. 4294705151 : U32), opt))
  EV{UI{cx, cy, keys, lx, ly, md, tool, var, sp, msg, fr, inc, last, sel(load, 2, io), fps, tl, opt2, fol}, wm, [],
    down && U32.is_eq(k, 6)}

def Menu.on(+ui: UI) -> Bool:
  Bool.not(U32.is_eq((UI.opt(ui) .&. 262144 : U32), 0))

# the scenario's outcome
def cons_click(+lx: U32, +ly: U32) -> U32:
  +col = ((lx - 6) / 56 : U32)
  +row = ((ly - 26) / 12 : U32)
  +on = (lx >= 6 : U32) && (ly >= 26 : U32) && (col < 4 : U32) && (row < 4 : U32)
    && (((lx - 6) % 56) < 52 : U32) && (((ly - 26) % 12) < 9 : U32)
  +op = Cons.op((row * 4 + col : U32))
  sel(on && (op < 99 : U32), (300 + op : U32),
    sel(in_box(lx, ly, 62, 76, 52, 9), 316, sel(in_box(lx, ly, 118, 76, 52, 9), 317, sel(in_box(lx, ly, 174, 76, 52, 9), 318,
    sel(in_box(lx, ly, 44, 88, 11, 9), 320, sel(in_box(lx, ly, 58, 88, 11, 9), 321,
    sel(in_box(lx, ly, 110, 88, 11, 9), 328, sel(in_box(lx, ly, 124, 88, 11, 9), 329,
    sel(in_box(lx, ly, 176, 88, 11, 9), 322, sel(in_box(lx, ly, 190, 88, 11, 9), 323,
    sel(in_box(lx, ly, 118, 62, 108, 9), 330, 0)))))))))))

# a piece code (not undo) becomes the previewed piece
def designs_click(+lx: U32, +ly: U32) -> U32:
  +r = ((ly - 16) / 12 : U32)
  sel((ly >= 16 : U32) && (r < 8 : U32) && (lx >= 4 : U32) && (lx < 256 : U32), (600 + r : U32), 0)

def win_code(+k: U32, +lx: U32, +ly: U32) -> U32:
  sel((ly < 10 : U32) && (lx + 10 >= Win.w(k) : U32), 1, sel((ly < 10 : U32), 2,
    sel(U32.is_eq(k, 1), ride_click(lx, ly), sel(U32.is_eq(k, 2), park_click(lx, ly),
      sel(U32.is_eq(k, 3), fin_click(lx, ly), sel(U32.is_eq(k, 5), staff_click(lx, ly),
      sel(U32.is_eq(k, 6), opts_click(lx, ly), sel(U32.is_eq(k, 8), cons_click(lx, ly),
      sel(U32.is_eq(k, 4) && in_box(lx, ly, 166, 126, 38, 9), 500, sel(U32.is_eq(k, 10), designs_click(lx, ly), 0))))))))))

# the act a window button asks for
def ride_act(+p: C.Park, +idx: U32, +op: U32) -> C.Act:
  +k = C.Ride.kind(C.Rides.get(C.Park.rides(p), idx))
  +h = C.Ride.ht(C.Rides.get(C.Park.rides(p), idx))
  Bool.pick(C.Act, U32.is_eq(op, 0) && U32.is_eq(k, 5), C.TrackOp{(h * 32 + 8 : U32)},
    Bool.pick(C.Act, U32.is_eq(op, 7) && U32.is_eq(k, 5), C.TrackOp{(h * 32 + 24 : U32)}, C.RideOp{idx, op}))

def UI.with_var(u: UI, +v: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, mx, my, md, tool, v, sp, msg, fr, inc, last, io, fps, tl, opt, fol}

# The construction window
# ------------------------
# Piece buttons in four rows; hovering one previews it as a ghost at the end
# of the track (UI var bits 24-27), a click or its key builds it.

def Cons.preview(+v: U32, +code: U32) -> U32:
  +piece = (code >= 300 : U32) && (code < 314 : U32) && Bool.not(U32.is_eq(code, 307))
  sel(piece, ((v .&. 4043309055) .|. ((code - 300) << 24n) : U32), v)

def Win.kind(w: Win) -> U32:
  Win{k, x, y, a} = w
  k

def Wins.kind_first(+ws: +List<Win>, +k: U32, +i: U32) -> U32:
  match ws:
    case []:
      C.NONE()
    case w <> rest:
      sel(U32.is_eq(Win.kind(w), k), i, Wins.kind_first(rest, k, (i + 1 : U32)))

# the next piece, as a ghost at the end of the track of the front-most
# construction window: green where it fits, red where it doesn't
def Cons.ghost.go(on: Bool, +p: C.Park, +k: U32, +pv: U32, +vx: U32, +vy: U32, +acc: +List<Dr>) -> +List<Dr>:
  match on:
    case True{}:
      C.Park{+map, guests, rides, +track, +cash, time, nid, fin, mess, staff} = p
      +trk = C.Tracks.get(track, k)
      +e = C.Track.end(trk)
      +i = C.Pose.x(e)
      +j = C.Pose.y(e)
      +h = C.Land.h(map, i, j)
      +fits = C.TrackOp.ok(map, trk, cash, pv)
      +code = ((pv + C.Pose.d(e) * 16) .|. (C.Cfg.type(C.Track.cfg(trk)) << 12n) .|. 131072 .|. sel(fits, 262144, 0) : U32)
      +show = Bool.not(C.Track.open(trk)) && Bool.not(C.Track.closed(trk)) && C.inmap(i, j)
      +bad = Bool.not(C.Track.open(trk)) && C.Test.failed(C.Track.stats(trk))
      +fp = C.Pieces.get(C.Track.pieces(trk), C.Test.fail(C.Track.stats(trk)))
      +fpo = C.Piece.pose(fp)
      +fx = C.Pose.x(fpo)
      +fy = C.Pose.y(fpo)
      +fz = C.Pose.z(fpo)
      +fk = C.Piece.kind(fp)
      +fd = C.Pose.d(fpo)
      +fh = C.Land.h(map, fx, fy)
      +fcode = ((fk + fd * 16) .|. (C.Cfg.type(C.Track.cfg(trk)) << 12n) .|. 65536 .|. 131072 : U32)
      Bool.pick(+List<Dr>, bad, DTrack{scr_x(fx, fy, vx), scr_y(fx, fy, fh, vy), fcode, (fz - fh : U32)} <> acc,
        Bool.pick(+List<Dr>, show, DTrack{scr_x(i, j, vx), scr_y(i, j, h, vy), code, (C.Pose.z(e) - h : U32)} <> acc, acc))
    case False{}:
      acc

def Win.arg(w: Win) -> U32:
  Win{k, x, y, a} = w
  a

# a click in window i: it comes to the front, then its close box, title bar
# (drag) or buttons act
def Cons.ghost(+p: C.Park, +ws: +List<Win>, +v: U32, +vx: U32, +vy: U32, +acc: +List<Dr>) -> +List<Dr>:
  +ci = Wins.kind_first(ws, 8, 0)
  Cons.ghost.go(Bool.not(U32.is_eq(ci, C.NONE())), p, Win.arg(Wins.get(ws, ci)), ((v >> 24n) .&. 15 : U32), vx, vy, acc)

# Speed levels (UI sp bits 0-3): 0 paused, 1 a quarter, 2 half (the
# default), 3 normal, 4 double, 5 triple; bits 4-7 keep the level a pause
# returns to
def Speed.ticks(+sp: U32, +fr: U32) -> U32:
  +l = (sp .&. 15 : U32)
  sel(U32.is_eq(l, 1), sel(U32.is_eq((fr .&. 3 : U32), 0), 1, 0), sel(U32.is_eq(l, 2), sel(U32.is_eq((fr .&. 1 : U32), 0), 1, 0),
    sel((l >= 3 : U32), (l - 2 : U32), 0)))

# Space pauses and resumes; + and - step between a quarter and triple
def Speed.key(+sp: U32, +c: U32) -> U32:
  +l = (sp .&. 15 : U32)
  +back = ((sp >> 4n) .&. 15 : U32)
  +resume = sel(U32.is_eq(back, 0), 2, back)
  +pause = U32.is_eq(c, 32)
  +up = U32.is_eq(c, 61) || U32.is_eq(c, 43)
  +dn = U32.is_eq(c, 45)
  sel(pause, sel(U32.is_eq(l, 0), resume, (l << 4n : U32)),
    sel(up, U32.min((sel(U32.is_eq(l, 0), resume, l) + 1 : U32), 5),
    sel(dn, U32.max(C.sub0(sel(U32.is_eq(l, 0), resume, l), 1), 1), sp)))

def win_act(+p: C.Park, +arg: U32, +code: U32) -> +List<C.Act>:
  Bool.pick(+List<C.Act>, (code >= 400 : U32), [],
    Bool.pick(+List<C.Act>, (code >= 330 : U32), [],
    Bool.pick(+List<C.Act>, (code >= 300 : U32), [C.TrackOp{(arg * 32 + code - 300 : U32)}],
    Bool.pick(+List<C.Act>, (code >= 200 : U32), [C.ParkOp{(code - 200 : U32)}],
    Bool.pick(+List<C.Act>, (code >= 100 : U32), [ride_act(p, arg, (code - 100 : U32))], [])))))

# a ride setting; opening the coaster goes through its track
def Dyn.is_below(+d: Dyn, +k: U32) -> Bool:
  (Dyn.key(d) < k : U32)

def dyn_put(keep: Bool, +d: Dyn, +xs: +List<Dyn>) -> +List<Dyn>:
  match keep:
    case True{}:
      d <> xs
    case False{}:
      xs

# the dynamic things on diagonals below k, and from k on (order kept)
def dyn_below(+ds: +List<Dyn>, +k: U32) -> +List<Dyn>:
  match ds:
    case []:
      []
    case d <> rest:
      dyn_put(Dyn.is_below(d, k), d, dyn_below(rest, k))

def dyn_from(+ds: +List<Dyn>, +k: U32) -> +List<Dyn>:
  match ds:
    case []:
      []
    case d <> rest:
      dyn_put(Bool.not(Dyn.is_below(d, k)), d, dyn_from(rest, k))

def ghost_k(+tool: U32, +ok: Bool, +q: C.Q, +rs: +List<C.Ride>, +i: U32, +j: U32) -> U32:
  +t = C.Land.get(q, i, j)
  +rk = C.Tool.kind(tool)
  # demolishing a ride shows its whole footprint
  +dk = sel(U32.is_eq(tool, 9) && U32.is_eq(C.Tile.obj(t), 3), C.Ride.kind(C.Rides.get(rs, C.Tile.a(t))), 0)
  +size = sel(Bool.not(U32.is_eq(rk, 0)), C.Ride.size(rk), sel(Bool.not(U32.is_eq(dk, 0)), C.Ride.size(dk), 1))
  (tool .|. (sel(ok, 1, 0) << 8n) .|. (size << 9n) .|. (rk << 12n) .|. (dk << 17n) : U32)

def ghost_on(+tool: U32, +hov: U32, +overwin: Bool) -> Bool:
  ((tool >= 1 : U32) && (tool <= 16 : U32) || (tool >= 30 : U32) && (tool <= 46 : U32) || U32.is_eq(tool, 48)) && Bool.not(U32.is_eq(tool, 12)) && (hov < 99999 : U32) && Bool.not(overwin)

def ghost_dr(+p: C.Park, +tool: U32, +hov: U32, +vx: U32, +vy: U32, +overwin: Bool) -> +List<Dr>:
  C.Park{+map, guests, +rides, +track, +cash, time, nid, fin, mess, staff} = p
  +i = (hov >> 6n : U32)
  +j = (hov .&. 63 : U32)
  +h = C.Land.h(map, i, j)
  +ok = C.Build.ok(map, track, cash, tool, i, j) && Res.open(C.Fin.res(fin), tool)
  Bool.pick(+List<Dr>, ghost_on(tool, hov, overwin),
    [DGhost{scr_x(i, j, vx), scr_y(i, j, h, vy), ghost_k(tool, ok, map, rides, i, j)}], [])

def Cut.ghost(+ps: +List<C.Piece>, +n: U32, +from: U32, +ty: U32, +q: C.Q, +vx: U32, +vy: U32, +acc: +List<Dr>) -> +List<Dr>:
  match ps:
    case []:
      acc
    case p <> rest:
      C.Piece{+x, +y, +z, +kind, +dir} = p
      +h = C.Land.h(q, x, y)
      Cut.ghost(rest, (n + 1 : U32), from, ty, q, vx, vy,
        Bool.pick(+List<Dr>, (n >= from : U32), DTrack{scr_x(x, y, vx), scr_y(x, y, h, vy), ((kind + dir * 16) .|. (ty << 12n) .|. 131072 : U32), (z - h : U32)} <> acc, acc))

def Pieces.at(+ps: +List<C.Piece>, +i: U32, +j: U32, +n: U32) -> U32:
  match ps:
    case []:
      C.NONE()
    case p <> rest:
      C.Piece{+x, +y, z, kind, dir} = p
      sel(U32.is_eq(x, i) && U32.is_eq(y, j), n, Pieces.at(rest, i, j, (n + 1 : U32)))

# a cut: demolishing coaster track on (i, j) takes that piece and every one
# after it (op 26 | coaster << 5 | piece << 16), or NONE off the track
def Cut.op(+p: C.Park, +i: U32, +j: U32) -> U32:
  +t = C.Land.get(C.Park.map(p), i, j)
  +k = ((C.Tile.a(t) >> 8n) .&. 2047 : U32)
  +ix = Pieces.at(C.Track.pieces(C.Tracks.get(C.Park.track(p), k)), i, j, 0)
  +deck = Bool.not(U32.is_eq(((C.Tile.a(t) >> 24n) .&. 15 : U32), 0))
  sel(U32.is_eq(C.Tile.obj(t), 6) && Bool.not(deck) && Bool.not(U32.is_eq(ix, C.NONE())), (26 .|. (k << 5n) .|. (U32.max(ix, 1) << 16n) : U32), C.NONE())

def Cut.ghosts(+p: C.Park, +tool: U32, +hov: U32, +vx: U32, +vy: U32, +on: Bool, +acc: +List<Dr>) -> +List<Dr>:
  +op = sel(U32.is_eq(tool, 9) && on, Cut.op(p, (hov >> 6n : U32), (hov .&. 63 : U32)), C.NONE())
  +t = C.Tracks.get(C.Park.track(p), C.TrackOp.k(op))
  Bool.pick(+List<Dr>, U32.is_eq(op, C.NONE()), acc,
    Cut.ghost(C.Track.pieces(t), 0, C.TrackOp.idx(op), C.Cfg.type(C.Track.cfg(t)), C.Park.map(p), vx, vy, acc))

def ghost_cost(+p: C.Park, +tool: U32, +hov: U32, +mx: U32, +my: U32, +overwin: Bool,
  +acc: +List<Dr>) -> +List<Dr>:
  C.Park{+map, guests, rides, +track, +cash, time, nid, fin, mess, staff} = p
  +cut = sel(U32.is_eq(tool, 9) && (hov < 99999 : U32), Cut.op(p, (hov >> 6n : U32), (hov .&. 63 : U32)), C.NONE())
  +iscut = Bool.not(U32.is_eq(cut, C.NONE()))
  +ct = C.Tracks.get(track, C.TrackOp.k(cut))
  +ok = C.Build.ok(map, track, cash, tool, (hov >> 6n : U32), (hov .&. 63 : U32)) || iscut && C.TrackOp.ok(map, ct, cash, 26)
  +cost = C.Build.cost(tool)
  +label = Bool.pick(String, iscut, "REMOVE TRACK +*" ++ U32.show(C.TrackOp.refund(ct, 26, C.TrackOp.idx(cut))),
    Bool.pick(String, U32.is_eq(tool, 9), "DEMOLISH", "*" ++ U32.show(cost)))
  Bool.pick(+List<Dr>, ghost_on(tool, hov, overwin) && Bool.not(U32.is_eq(tool, 10)),
    T(label, (mx + 9 : U32), C.sub0(my, 10), sel(ok, 12648384, 16748688),
      R((mx + 7 : U32), C.sub0(my, 12), (C.len32(U32, str_bytes(label)) * 4 + 4 : U32), 9, 1973802, acc)), acc)

# the park as drawn: the map, rides, guests, staff and trains, front-most
# first
def world(+p: C.Park, +ui: UI) -> +List<Dr>:
  C.Park{+map, +guests, +rides, +track, cash, +time, nid, fin, mess, +staff} = p
  UI{+camx, +camy, keys, mx, my, md, tool, +var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = ui
  +hov = pick(map, ui)
  +z = View.z(var)
  +vx = View.x(camx, z)
  +vy = View.y(camy, z)
  +vw = View.w(z)
  +vh = View.h(z)
  +rt = RT.of(guests, rides, C.Tracks.tylist(track), C.len32(C.Track, track))
  +dyn = trains_all(track, vx, vy, rt, 0,
    guests_dyn(guests, map, rides, vx, vy, vw, vh, time, staff_dyn(staff, map, vx, vy, vw, vh, time, [])))
  +sorted = List.sort(~Dyn, ~Dyn.le, dyn)
  +ar = Arches.of(rides, track)
  # the back and front halves of the map are built in parallel
  hi lo = diags(63n, 64, map, rides, rt, ar, vx, vy, vw, vh, hov, dyn_from(sorted, 64), [])
    diags(64n, 0, map, rides, rt, ar, vx, vy, vw, vh, hov, dyn_below(sorted, 64), [])
  List.append(&2, Dr, hi, lo)

# Picking: what a click lands on is what is drawn there, front-most first:
# 1 | guest id << 3, 4 | staff id << 3, 2 | ride << 3, 3 the ground, track
# or a coaster car under the mouse (look at the tile), 0 scenery or nothing
def Pick.code(d: Dr, +time: U32) -> U32:
  match d:
    case DGuest{x, y, +look, +ph}:
      +id = (ph - time : U32)
      sel(Bool.not(U32.is_eq((look .&. 67108864 : U32), 0)), (4 .|. (id << 3n) : U32), (1 .|. (id << 3n) : U32))
    case DRide{x, y, k, ra, rb, st, +i}:
      (2 .|. (i << 3n) : U32)
    case DBlock{x, y, dl, dr, ter, obj, hov, wx, wy, nb}:
      3
    case DTrack{x, y, code, zr}:
      3
    case DCar{x, y, dd, lead, rd}:
      3
    case _:
      0

# (the walk goes on past the front-most hit: it only runs on a click)
def Pick.walk(+xs: +List<Dr>, +px: U32, +py: U32, +t: U32, +time: U32) -> U32:
  match xs:
    case []:
      0
    case +d <> rest:
      sel(A.opaque(Dr.shade_if(Dr.hits(d, px, py, 1, t), d, px, py, t)), Pick.code(d, time), Pick.walk(rest, px, py, t, time))

def UI.var(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  var

def Pick.under(+p: C.Park, +ui: UI, +lx: U32, +ly: U32) -> U32:
  +time = C.Park.time(p)
  Pick.walk(world(p, ui), (B() + lx : U32), (B() + ly : U32), ((time .&. 536870911) .|. (View.z(UI.var(ui)) << 30n) : U32), time)

def Design.start(+q: C.Q, +x: U32, +y: U32, +v: U32) -> C.Piece:
  {C.Piece{x, y, C.Land.h(q, x, y), 5, (v .&. 3 : U32)} : C.Piece}

# slot s built at (x, y) heading v: does all of it fit, and can the park pay?
def Design.walk(+ks: +List<U32>, +n: U32, +q: C.Q, +e: C.Pose, +ok: Bool, +cost: U32) -> U32:
  match ks:
    case []:
      sel(ok, cost, C.NONE())
    case kd <> rest:
      +pc = {C.Piece{C.Pose.x(e), C.Pose.y(e), C.Pose.z(e), kd, C.Pose.d(e)} : C.Piece}
      +room = C.Track.room(q, e, kd) && C.Piece.faces(kd, C.Pose.d(e))
      sel(U32.is_eq(n, 0), sel(ok, cost, C.NONE()), Design.walk(rest, (n - 1 : U32), q, C.Piece.exit(pc), ok && room, (cost + C.Piece.cost(kd) : U32)))

def Design.fits(+p: C.Park, +w: +List<U32>, +x: U32, +y: U32, +v: U32) -> Bool:
  +n = C.Tab.at(w, 0)
  +q = C.Park.map(p)
  +cost = Design.walk(Words.drop(w, 2), n, q, C.Piece.exit(Design.start(q, x, y, v)), True{}, 0)
  (n > 0 : U32) && C.Build.ok(q, C.Park.track(p), C.Park.cash(p), 10, x, y) && Bool.not(U32.is_eq(cost, C.NONE()))
    && (C.Park.cash(p) >= cost + C.Build.cost(10) : U32)

def Design.ghosts(+ks: +List<U32>, +n: U32, +q: C.Q, +e: C.Pose, +code: U32, +vx: U32, +vy: U32, +acc: +List<Dr>) -> +List<Dr>:
  match ks:
    case []:
      acc
    case kd <> rest:
      +pc = {C.Piece{C.Pose.x(e), C.Pose.y(e), C.Pose.z(e), kd, C.Pose.d(e)} : C.Piece}
      +h = C.Land.h(q, C.Pose.x(e), C.Pose.y(e))
      +dr = {DTrack{scr_x(C.Pose.x(e), C.Pose.y(e), vx), scr_y(C.Pose.x(e), C.Pose.y(e), h, vy), ((kd + C.Pose.d(e) * 16) .|. code : U32), (C.Pose.z(e) - h : U32)} : Dr}
      Bool.pick(+List<Dr>, U32.is_eq(n, 0), acc, Design.ghosts(rest, (n - 1 : U32), q, C.Piece.exit(pc), code, vx, vy, dr <> acc))

# with the design tool, the chosen design (UI var bits 28-30) as one ghost at
# the tile under the mouse, green if all of it fits
def Design.ghost(+p: C.Park, +ds: +List<U32>, +tool: U32, +var: U32, +hov: U32, +vx: U32, +vy: U32, +on: Bool, +acc: +List<Dr>) -> +List<Dr>:
  +show = U32.is_eq(tool, 47) && on && (hov < 99999 : U32)
  +w = Lib.slot(ds, ((var >> 28n) .&. 7 : U32))
  +x = (hov >> 6n : U32)
  +y = (hov .&. 63 : U32)
  +v = (var .&. 3 : U32)
  +q = C.Park.map(p)
  +fits = Design.fits(p, w, x, y, v)
  +code = ((C.Cfg.type(C.Tab.at(w, 1)) << 12n) .|. 131072 .|. sel(fits, 262144, 0) : U32)
  +st = Design.start(q, x, y, v)
  +h = C.Land.h(q, x, y)
  Bool.pick(+List<Dr>, show && (C.Tab.at(w, 0) > 0 : U32),
    Design.ghosts(Words.drop(w, 2), C.Tab.at(w, 0), q, C.Piece.exit(st), code, vx, vy,
      DTrack{scr_x(x, y, vx), scr_y(x, y, h, vy), ((5 + v * 16) .|. code : U32), 0} <> acc), acc)

def scene(+g: Game) -> +List<Dr>:
  Game{+p, +ui, +wm, snd, +ds} = g
  C.Park{+map, +guests, +rides, +track, cash, +time, nid, fin, mess, staff} = p
  UI{+camx, +camy, keys, +mx, +my, md, +tool, +var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = ui
  +hov = pick(map, ui)
  +z = View.z(var)
  +vx = View.x(camx, z)
  +vy = View.y(camy, z)
  +vw = View.w(z)
  +vh = View.h(z)
  +overwin = Bool.not(U32.is_eq(Wins.at(WM.wins(wm), mx, my, 0), C.NONE())) || Bool.not(U32.is_eq((UI.opt(ui) .&. 262144 : U32), 0))
  +ghost = Design.ghost(p, ds, tool, var, hov, vx, vy, Bool.not(overwin), Cut.ghosts(p, tool, hov, vx, vy, Bool.not(overwin), Cons.ghost(p, WM.wins(wm), var, vx, vy, ghost_dr(p, tool, hov, vx, vy, overwin))))
  +front = ghost_cost(p, tool, hov, mx, my, overwin, wins_dr(WM.wins(wm), p, UI.opt(ui), var, ds,
    Bool.pick(+List<Dr>, Menu.on(ui), menu_dr(mx, my), hud(p, ui, hov))))
  List.append(&2, Dr, front, List.append(&2, Dr, ghost, world(p, ui)))

def Game.zoom(g: Game) -> U32:
  Game{p, ui, wm, snd, ds} = g
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = ui
  View.z(var)

def Game.lo(g: Game) -> Bool:
  Game{p, ui, wm, snd, ds} = g
  Bool.not(U32.is_eq((UI.opt(ui) .&. 256 : U32), 0))

def frame(+g: Game) -> Image:
  R.frame(scene(g), ((C.Park.time(Game.park(g)) .&. 536870911) .|. (Game.zoom(g) << 30n)
    .|. sel(Game.lo(g), 536870912, 0) : U32))

def u32s(+n: U32) -> String:
  U32.show(n)

def key_bit(+c: U32) -> U32:
  match c:
    case 63232:
      1
    case 63233:
      2
    case 63234:
      4
    case 63235:
      8
    case 119:
      1
    case 115:
      2
    case 97:
      4
    case 100:
      8
    case _:
      0

# the coaster tool's keys (WASD is the camera): T ahead, Y up, B down, G left,
# H right, L lift hill
def track_op(+c: U32) -> U32:
  match c:
    case 116:
      0
    case 121:
      1
    case 98:
      2
    case 103:
      3
    case 104:
      4
    case 108:
      6
    case 122:
      5
    case 106:
      9
    case 113:
      10
    case 101:
      11
    case 99:
      12
    case 118:
      13
    case 127:
      7
    case 8:
      7
    case _:
      99

def paint_tool(+t: U32) -> Bool:
  (t < 5 : U32) || U32.is_eq(t, 9) || U32.is_eq(t, 48)

# the piece of a track standing on tile (i, j), or NONE
def build_act(+p: C.Park, +ui: UI) -> +List<C.Act>:
  UI{camx, camy, keys, mx, my, md, +tool, +var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = ui
  +hov = pick(C.Park.map(p), ui)
  +cut = sel(U32.is_eq(tool, 9) && (hov < 99999 : U32), Cut.op(p, (hov >> 6n : U32), (hov .&. 63 : U32)), C.NONE())
  Bool.pick(+List<C.Act>, (hov < 99999 : U32),
    [Bool.pick(C.Act, Bool.not(U32.is_eq(cut, C.NONE())), C.TrackOp{cut}, C.Build{tool, (hov >> 6n : U32), (hov .&. 63 : U32), var})], [])

def on_key(+c: U32, +down: Bool, +ui: UI, +wm: WM, +q: C.Q) -> EV:
  UI{cx, cy, +keys, mx, my, md, +tool, +var, +sp, +msg, fr, inc, last, +io, fps, tl, opt, fol} = ui
  WM{+ws, +dg, +gx, +gy} = wm
  # Esc closes the front window; with none open, it quits
  +esc = down && U32.is_eq(c, 27)
  +haswin = Bool.not(U32.is_eq(C.len32(Win, ws), 0))
  +kb = key_bit(c)
  +keys2 = sel(down, (keys .|. kb : U32), (keys .&. (4294967295 - kb) : U32))
  +digit = (c >= 49 : U32) && (c <= 54 : U32) && down
  +dc = (c - 49 : U32)
  +tool2 = sel(digit, Cat.key(dc, UI.cat(var), tool), sel(down && U32.is_eq(c, 117), 11,
    sel(down && U32.is_eq(c, 105), 12, sel(down && U32.is_eq(c, 120), 9, tool))))
  # M: music on or off (var bit 16); N: effects on or off (bit 17); Page Up
  # / Page Down: zoom (bits 18-19)
  +var1 = (sel(down && U32.is_eq(c, 114), (var + 1 : U32), var)
    .^. sel(down && U32.is_eq(c, 109), 65536, 0) .^. sel(down && U32.is_eq(c, 110), 131072, 0) : U32)
  +var1b = sel(digit, set_cat(var1, dc), sel(down && U32.is_eq(c, 117), set_cat(var1, 0), var1))
  +op = track_op(c)
  +ci = Wins.kind_first(ws, 8, 0)
  +tact = down && Bool.not(U32.is_eq(ci, C.NONE())) && (op < 99 : U32)
  +ck = Win.arg(Wins.get(ws, ci))
  +var1c = Cons.preview(var1b, sel(tact, (300 + track_op(c) : U32), 0))
  +var2 = sel(down && U32.is_eq(c, 63276), View.zoom(var1c, True{}),
    sel(down && U32.is_eq(c, 63277), View.zoom(var1c, False{}), var1c))
  +sp2 = Speed.key(sp, sel(down, c, 0))
  +io2 = sel(down && U32.is_eq(c, 63240), 1, sel(down && U32.is_eq(c, 63244), 2, io))
  +msg2 = sel(down && U32.is_eq(c, 109), sel(U32.is_eq((var2 .&. 65536 : U32), 0), 11, 12),
    sel(down && U32.is_eq(c, 110), sel(U32.is_eq((var2 .&. 131072 : U32), 0), 13, 14), msg))
  EV{UI{cx, cy, keys2, mx, my, md, tool2, var2, sp2, msg2, fr, inc, last, io2, fps, tl, opt, fol},
    WM{Bool.pick(+List<Win>, esc && haswin, Wins.drop(ws, 0),
      Bool.pick(+List<Win>, down && U32.is_eq(c, 112), Wins.open(ws, 2, 0, 150, 40),
      Bool.pick(+List<Win>, down && U32.is_eq(c, 102), Wins.open(ws, 3, 0, 140, 30),
      Bool.pick(+List<Win>, down && U32.is_eq(c, 107), Wins.open(ws, 5, 0, 160, 50),
      Bool.pick(+List<Win>, down && U32.is_eq(c, 111), Wins.open(ws, 6, 0, 150, 60), ws))))), dg, gx, gy},
    Bool.pick(+List<C.Act>, tact, [C.TrackOp{((ck << 5n) .|. op : U32)}], []),
    esc && Bool.not(haswin)}

def UI.with_last(u: UI, +l: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, l, io, fps, tl, opt, fol}

# the front window, moved to (x, y), kept on the screen
def Wins.drag(+ws: +List<Win>, +x: U32, +y: U32) -> +List<Win>:
  match ws:
    case []:
      []
    case w <> rest:
      +k = Win.kind(w)
      Win.moved(w, U32.min(x, (510 - Win.w(k) : U32)), U32.min(U32.max(y, 12), (290 - Win.h(k) : U32))) <> rest

def Win.x(w: Win) -> U32:
  Win{k, x, y, a} = w
  x

def Win.y(w: Win) -> U32:
  Win{k, x, y, a} = w
  y

def on_move(+x: U32, +y: U32, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  UI{cx, cy, keys, mx, my, +md, +tool, var, sp, msg, fr, inc, +last, io, fps, tl, opt, fol} = ui
  WM{+ws, +dg, +gx, +gy} = wm
  +q = C.Park.map(p)
  +lx = (x >> 1n : U32)
  +ly = (y >> 1n : U32)
  +dragging = U32.is_eq(dg, 1)
  +wi = Wins.at(ws, lx, ly, 0)
  +w = Wins.get(ws, wi)
  +hcode = sel(U32.is_eq(wi, C.NONE()) || Bool.not(U32.is_eq(Win.kind(w), 8)), 0,
    cons_click((lx - Win.x(w) : U32), (ly - Win.y(w) : U32)))
  +ui2 = {UI{cx, cy, keys, lx, ly, md, tool, Cons.preview(var, hcode), sp, msg, fr, inc, last, io, fps, tl, opt, fol} : UI}
  +hov = pick(q, ui2)
  +paint = U32.is_eq(md, 1) && paint_tool(tool) && Bool.not(U32.is_eq(hov, last))
    && (hov < 99999 : U32) && Bool.not(dragging)
  EV{UI.with_last(ui2, sel(paint, hov, last)),
    WM{Bool.pick(+List<Win>, dragging, Wins.drag(ws, (lx - gx : U32), (ly - gy : U32)), ws), dg, gx, gy},
    Bool.pick(+List<C.Act>, paint, build_act(p, ui2), []), False{}}

# a guest or staff member on a stair tile walks up or down it: drawn height
# blended across the tile edge toward a path a level up or down (pixels to
# add to 8 * h, maybe negative)
def UI.with_tool(u: UI, +t: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, mx, my, md, t, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol}

# the ride on a tile (a ride's tile, or any coaster track), or NONE
def ride_at(+p: C.Park, +hov: U32) -> U32:
  +t = C.Land.get(C.Park.map(p), (hov >> 6n : U32), (hov .&. 63 : U32))
  +o = C.Tile.obj(t)
  sel((hov >= 99999 : U32), C.NONE(), sel(U32.is_eq(o, 3), C.Tile.a(t),
    sel(U32.is_eq(o, 6), Coaster.ride(C.Park.rides(p), ((C.Tile.a(t) >> 8n) .&. 2047 : U32), 0), C.NONE())))

# inspecting: a ride's window opens beside the mouse
def open_at(+ws: +List<Win>, +p: C.Park, +hov: U32, +lx: U32, +ly: U32) -> +List<Win>:
  +idx = ride_at(p, hov)
  Bool.pick(+List<Win>, U32.is_eq(idx, C.NONE()), ws,
    Wins.open(ws, 1, idx, U32.min((lx + 12 : U32), 312), U32.min(U32.max(C.sub0(ly, 30), 14), 136)))

# a click on the map or the toolbar. The inspect tool (or the right button,
# with any tool) opens a ride's window; other tools build.
# the walking guest nearest the mouse (within 7 px), or NONE
def Guests.near(+gs: +List<C.Guest>, +q: C.Q, +camx: U32, +camy: U32, +lx: U32, +ly: U32,
  +best: U32, +bd: U32) -> U32:
  match gs:
    case []:
      best
    case g <> rest:
      C.Guest{+id, +x, +y, dir, +st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
      +h = C.Land.h(q, (x >> 4n : U32), (y >> 4n : U32))
      +sx = ((1280 + x) - (y + camx) : U32)
      +sy = ((512 + ((x + y) >> 1n)) - (8 * h + camy + 6) : U32)
      +d = (C.absd(sx, lx) + C.absd(sy, ly) : U32)
      +take = (U32.is_eq(st, 0) || U32.is_eq(st, 2) || U32.is_eq(st, 4)) && (d < bd : U32)
      Guests.near(rest, q, camx, camy, lx, ly, sel(take, id, best), sel(take, d, bd))

# inspecting: a guest under the mouse opens their window, else a ride's
def inspect_at(+ws: +List<Win>, +p: C.Park, +hov: U32, +lx: U32, +ly: U32, +ui: UI) -> +List<Win>:
  +pk = Pick.under(p, ui, lx, ly)
  +kind = (pk .&. 7 : U32)
  +id = (pk >> 3n : U32)
  +wx = U32.min((lx + 12 : U32), 300)
  +wy = U32.min(U32.max(C.sub0(ly, 30), 14), 156)
  Bool.pick(+List<Win>, U32.is_eq(kind, 1), Wins.open(ws, 4, id, wx, wy),
    Bool.pick(+List<Win>, U32.is_eq(kind, 2), Wins.open(ws, 1, id, U32.min((lx + 12 : U32), 312), U32.min(U32.max(C.sub0(ly, 30), 14), 136)),
    Bool.pick(+List<Win>, U32.is_eq(kind, 4), Wins.open(ws, 5, 0, 160, 50),
    Bool.pick(+List<Win>, U32.is_eq(kind, 3), open_at(ws, p, hov, lx, ly), ws))))

# (a match, so the world is only built for picking on an inspect click)
def inspect_if(on: Bool, +ws: +List<Win>, +p: C.Park, +hov: U32, +lx: U32, +ly: U32, +ui: UI) -> +List<Win>:
  match on:
    case True{}:
      inspect_at(ws, p, hov, lx, ly, ui)
    case False{}:
      ws

def UI.io(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  io

def UI.with_io(u: UI, +o: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, o, fps, tl, opt, fol}

def on_map(+lx: U32, +ly: U32, +button: U32, +down: Bool, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  UI{+cx, +cy, keys, mx, my, md, +tool, +var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = ui
  +q = C.Park.map(p)
  +bar = (ly >= 292 : U32)
  +item = bar_item(lx, ly, UI.cat(var))
  +pickc = down && bar && (item >= 20 : U32) && (item <= 25 : U32)
  +pickt = down && bar && (item > 0 : U32) && Bool.not(pickc)
  +var1 = sel(pickc, set_cat(var, (item - 20 : U32)), var)
  +var2 = sel(down && U32.is_eq(button, 5), View.zoom(var1, True{}), sel(down && U32.is_eq(button, 6), View.zoom(var1, False{}), var1))
  +ui2 = {UI{cx, cy, keys, lx, ly, sel(down && U32.is_eq(button, 0), 1, 0), tool, var2, sp, msg, fr, inc, 99999, io, fps, tl, opt, fol} : UI}
  +click = down && Bool.not(bar)
  +wheel = U32.is_eq(button, 5) || U32.is_eq(button, 6)
  +inspect = click && Bool.not(wheel) && (U32.is_eq(tool, 12) || Bool.not(U32.is_eq(button, 0)))
  +build0 = click && Bool.not(inspect) && Bool.not(wheel) && Res.open(C.Fin.res(C.Park.fin(p)), tool)
  +design = build0 && U32.is_eq(tool, 47)
  +build = build0 && Bool.not(design)
  +hov = pick(q, ui2)
  +ui3 = UI.with_tool(UI.with_last(ui2, sel(build, hov, 99999)), sel(pickt, item, sel(pickc, Cat.tool((item - 20 : U32), 0), tool)))
  +ws = WM.wins(wm)
  +parkb = down && in_box(lx, ly, 462, 294, 46, 9)
  +finb = down && in_box(lx, ly, 462, 305, 46, 9)
  +staffb = down && in_box(lx, ly, 414, 294, 46, 9)
  +optb = down && in_box(lx, ly, 414, 305, 46, 9)
  +ws2 = Bool.pick(+List<Win>, parkb, Wins.open(ws, 2, 0, 150, 40),
    Bool.pick(+List<Win>, finb, Wins.open(ws, 3, 0, 140, 30),
    Bool.pick(+List<Win>, staffb, Wins.open(ws, 5, 0, 160, 50),
    Bool.pick(+List<Win>, optb, Wins.open(ws, 6, 0, 150, 60),
    Bool.pick(+List<Win>, pickt && U32.is_eq(item, 47), Wins.open(ws, 10, 0, 120, 40), ws)))))
  EV{UI.with_io(ui3, sel(design, (5 .|. (hov << 4n) : U32), UI.io(ui3))), WM{inspect_if(inspect, ws2, p, hov, lx, ly, ui2), 0, 0, 0},
    Bool.pick(+List<C.Act>, build, build_act(p, ui2), []), False{}}

def UI.at(u: UI, +x: U32, +y: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, x, y, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol}

def UI.cx(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  cx

def UI.cy(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  cy

def UI.fol(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  fol

def UI.with_fol(u: UI, +f: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, f}

# the camera that centres world point (x, y) (sixteenths of a tile) at
# height h: camx << 16 | camy
def Staff.next.go(+ss: +List<C.Staff>, +k: U32, +after: U32, +first: U32) -> U32:
  match ss:
    case []:
      first
    case s <> rest:
      C.Staff{+id, x, y, dir, +kind, st, tgt, tmr, zone, look} = s
      +mine = U32.is_eq(kind, k)
      sel(mine && (id > after : U32), id, Staff.next.go(rest, k, after, sel(mine && U32.is_eq(first, C.NONE()), id, first)))

def Staff.next(+ss: +List<C.Staff>, +k: U32, +after: U32) -> U32:
  Staff.next.go(ss, k, after, C.NONE())

def UI.tool(u: UI) -> U32:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  tool

def on_win(+wi: U32, +lx: U32, +ly: U32, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  +ws = Wins.front(WM.wins(wm), wi)
  +w = Wins.get(ws, 0)
  +wx = Win.x(w)
  +wy = Win.y(w)
  +code = win_code(Win.kind(w), (lx - wx : U32), (ly - wy : U32))
  +rd = C.Rides.get(C.Park.rides(p), Win.arg(w))
  +build = U32.is_eq(code, 400) && U32.is_eq(Win.kind(w), 1) && U32.is_eq(C.Ride.kind(rd), 5)
  +ws2 = Bool.pick(+List<Win>, build, Wins.open(ws, 8, C.Ride.ht(rd), 16, 30),
    Bool.pick(+List<Win>, U32.is_eq(code, 1041), Wins.open(ws, 9, 0, 96, 24), ws))
  +cur = UI.fol(ui)
  +staffk = (code >= 510 : U32) && (code < 514 : U32)
  +sid = Staff.next(C.Park.staff(p), (code - 509 : U32), sel(U32.is_eq((cur .&. 3 : U32), 2), (cur >> 2n : U32), 0))
  +fol2 = sel(U32.is_eq(code, 500), (1 .|. (Win.arg(w) << 2n) : U32), sel(U32.is_eq(code, 520), (3 .|. (Win.arg(w) << 2n) : U32),
    sel(staffk && Bool.not(U32.is_eq(sid, C.NONE())), (2 .|. (sid << 2n) : U32), cur)))
  +demo = U32.is_eq(code, 109) && U32.is_eq(Win.kind(w), 1) && U32.is_eq(C.Ride.kind(rd), 5)
  +fire = demo && U32.is_eq((UI.opt(ui) >> 19n : U32), (Win.arg(w) + 1 : U32))
  +opt2 = ((Opt.click(UI.opt(ui), code) .&. 524287) .|. sel(demo && Bool.not(fire), ((Win.arg(w) + 1) << 19n : U32), 0) : U32)
  +pickd = (code >= 600 : U32) && (code < 608 : U32)
  +var2 = sel(pickd, ((UI.var(ui) .&. 2415919103) .|. ((code - 600) << 28n) : U32), Cons.preview(UI.var(ui), code))
  +u1 = UI.with_fol(UI.with_var(UI.with_opt(UI.at(ui, lx, ly), opt2), var2), fol2)
  +u2 = UI.with_io(u1, sel(U32.is_eq(code, 330), (3 .|. (Win.arg(w) << 4n) : U32), UI.io(u1)))
  EV{UI.with_tool(u2, sel(pickd, 47, UI.tool(u2))),
    WM{Bool.pick(+List<Win>, U32.is_eq(code, 1) || fire, Wins.drop(ws2, 0), ws2), sel(U32.is_eq(code, 2), 1, 0),
      (lx - wx : U32), (ly - wy : U32)},
    Bool.pick(+List<C.Act>, fire, [C.TrackOp{(27 .|. (C.Ride.ht(rd) << 5n) : U32)}], Bool.pick(+List<C.Act>, demo, [], win_act(p, Win.arg(w), code))),
    False{}}

def on_mouse.go(inwin: Bool, +wi: U32, +lx: U32, +ly: U32, +button: U32, +down: Bool, +ui: UI,
  +wm: WM, +p: C.Park) -> EV:
  match inwin:
    case True{}:
      on_win(wi, lx, ly, ui, wm, p)
    case False{}:
      on_map(lx, ly, button, down, ui, wm, p)

def on_mouse.menu(menu: Bool, +x: U32, +y: U32, +button: U32, +down: Bool, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  match menu:
    case True{}:
      on_menu((x >> 1n : U32), (y >> 1n : U32), down, ui, wm)
    case False{}:
      +lx = (x >> 1n : U32)
      +ly = (y >> 1n : U32)
      +wi = Wins.at(WM.wins(wm), lx, ly, 0)
      on_mouse.go(down && Bool.not(U32.is_eq(wi, C.NONE())), wi, lx, ly, button, down, ui, wm, p)

def on_mouse(+x: U32, +y: U32, +button: U32, +down: Bool, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  on_mouse.menu(Menu.on(ui), x, y, button, down, ui, wm, p)

def on_event(e: Event, +ui: UI, +wm: WM, +p: C.Park) -> EV:
  match e:
    case Key{c, d}:
      on_key(c, d, ui, wm, C.Park.map(p))
    case Move{x, y}:
      on_move(x, y, ui, wm, p)
    case Mouse{x, y, b, d}:
      on_mouse(x, y, b, d, ui, wm, p)
    case Close{}:
      EV{ui, wm, [], True{}}

def EV.ui(e: EV) -> UI:
  EV{ui, wm, acts, quit} = e
  ui

def EV.wm(e: EV) -> WM:
  EV{ui, wm, acts, quit} = e
  wm

def EV.acts(e: EV) -> +List<C.Act>:
  EV{ui, wm, acts, quit} = e
  acts

def EV.quit(e: EV) -> Bool:
  EV{ui, wm, acts, quit} = e
  quit

def on_events(es: List<Event>, +ui: UI, +wm: WM, +p: C.Park, +acts: +List<C.Act>, quit: Bool)
  -> EV:
  match es:
    case []:
      EV{ui, wm, acts, quit}
    case e <> rest:
      +r = on_event(e, ui, wm, p)
      on_events(rest, EV.ui(r), EV.wm(r), p, List.append(&2, C.Act, acts, EV.acts(r)),
        quit || EV.quit(r))

# gold earned: the Gain entries of a ledger
def gains1(t: C.Txn) -> U32:
  match t:
    case C.Gain{+k, a}:
      sel(U32.is_eq(k, 1) || U32.is_eq(k, 5) || U32.is_eq(k, 6) || U32.is_eq(k, 7), a, 0)
    case C.Spend{k, a}:
      0

def gains(+xs: +List<C.Txn>) -> U32:
  match xs:
    case []:
      0
    case t <> rest:
      (gains(rest) + gains1(t) : U32)

type Res is Data:
  Res{park: C.Park, msg: U32, inc: U32}

def Res.park(r: Res) -> C.Park:
  Res{p, m, i} = r
  p

def Res.msg(r: Res) -> U32:
  Res{p, m, i} = r
  m

def Res.inc(r: Res) -> U32:
  Res{p, m, i} = r
  i

def paid(+o: C.Out) -> Bool:
  Bool.not(U32.is_eq(C.len32(C.Txn, C.Out.ledger(o)), 0))

def act_msg(+a: C.Act, +o: C.Out) -> U32:
  match a:
    case C.Tick{}:
      0
    case C.Build{t, x, y, v}:
      sel(paid(o), 1, 2)
    case C.TrackOp{+op}:
      +t = C.Tracks.get(C.Park.track(C.Out.park(o)), C.TrackOp.k(op))
      +c = (op .&. 31 : U32)
      sel(U32.is_eq(c, 8), sel(C.Track.open(t), 6, sel(Bool.not(C.Track.closed(t)), 19,
        sel(C.Test.passed(C.Track.stats(t)), 7, 15))),
        sel(U32.is_eq(c, 24), sel(C.Track.open(t), 16, 19), sel(U32.is_eq(c, 26), sel(paid(o), sel(C.Track.open(t), 22, 20), 2),
        sel(U32.is_eq(c, 27), sel(paid(o), 21, 2), sel(paid(o), 0, 2)))))
    case C.RideOp{r, op}:
      0
    case C.ParkOp{+op}:
      sel(U32.is_eq(op, 2), sel(paid(o), 8, 10), sel(U32.is_eq(op, 3), sel(paid(o), 9, 10), 0))

def apply(+acts: +List<C.Act>, +p: C.Park, +msg: U32, +inc: U32) -> Res:
  match acts:
    case []:
      Res{p, msg, inc}
    case a <> rest:
      +o = C.Park.step(p, a)
      +m = act_msg(a, o)
      apply(rest, C.Out.park(o), sel(U32.is_eq(m, 0), msg, m),
        (inc + gains(C.Out.ledger(o)) : U32))

def ticks(+n: Nat, +p: C.Park, +inc: U32) -> Res:
  match n:
    case 0n:
      Res{p, 0, inc}
    case 1n+k:
      +o = C.Park.step(p, C.Tick{})
      ticks(k, C.Out.park(o), (inc + gains(C.Out.ledger(o)) : U32))

def cam(+keys: U32, +v: U32, +minus: U32, +plus: U32, +step: U32, +lo: U32, +hi: U32) -> U32:
  +m = Bool.not(U32.is_eq((keys .&. minus : U32), 0))
  +pl = Bool.not(U32.is_eq((keys .&. plus : U32), 0))
  U32.min(U32.max(sel(m, (v - step : U32), sel(pl, (v + step : U32), v)), lo), hi)

# Sound events: what changed this frame, for the synthesizer (see Z.Snd.cue)
def Rides.started(+a: +List<C.Ride>, +b: +List<C.Ride>) -> U32:
  match a b:
    case Con{r0, ra} Con{r1, rb}:
      +k = C.Ride.kind(r1)
      +go = Bool.not(U32.is_eq(C.Ride.ph(r0), 1)) && U32.is_eq(C.Ride.ph(r1), 1)
      (sel(go, sel(U32.is_eq(k, 1), 2, sel(U32.is_eq(k, 2), 4, 0)), 0) .|. Rides.started(ra, rb) : U32)
    case _ _:
      0

# a ride that broke down (100 + its kind) or was repaired (110 + kind)
# between two ticks, or 0
def Rides.broke(+a: +List<C.Ride>, +b: +List<C.Ride>) -> U32:
  match a b:
    case Con{r0, ra} Con{r1, rb}:
      +k = C.Ride.kind(r1)
      +w0 = C.Wear.broken(C.Ride.wear(r0))
      +w1 = C.Wear.broken(C.Ride.wear(r1))
      +code = sel(Bool.not(w0) && w1, (100 + k : U32), sel(w0 && Bool.not(w1), (110 + k : U32), 0))
      sel(U32.is_eq(code, 0), Rides.broke(ra, rb), code)
    case _ _:
      0

# the coasters: the fastest train (0..255) | a train on a lift hill << 8 |
# the fastest train's coaster type << 9 | a train of an open coaster going
# down a drop fast << 11 | how loud its riders scream (0-63) << 12
def Snd.slot(sl: C.Slot, +ps: +List<C.Piece>, +ty: U32, +serve: Bool, +acc: U32) -> U32:
  match sl:
    case C.Free{a, n, st}:
      acc
    case C.Held{+a, n, st, t}:
      C.Train{id, +prog, +speed, wait} = t
      +k = C.Piece.kind(C.Pieces.get(ps, (a + (prog >> 8n) : U32)))
      +roar = U32.min((speed * 255 / 90 : U32), 255)
      +lift = U32.is_eq(k, 6) && (speed > 0 : U32)
      +louder = (roar > (acc .&. 255) : U32)
      +drop = serve && (U32.is_eq(k, 2) || U32.is_eq(k, 13)) && (speed >= 45 : U32)
      +vol = U32.min((speed * 63 / 100 : U32), 63)
      +old = ((acc >> 12n) .&. 63 : U32)
      (U32.max((acc .&. 255 : U32), roar) .|. (acc .&. 256) .|. sel(lift, 256, 0)
        .|. sel(louder, (ty << 9n : U32), (acc .&. 1536 : U32)) .|. (acc .&. 2048) .|. sel(drop, 2048, 0)
        .|. (sel(drop, U32.max(old, vol), old) << 12n) : U32)

def Snd.slots(+ss: +List<C.Slot>, +ps: +List<C.Piece>, +ty: U32, +serve: Bool, +acc: U32) -> U32:
  match ss:
    case []:
      acc
    case sl <> rest:
      Snd.slots(rest, ps, ty, serve, Snd.slot(sl, ps, ty, serve, acc))

# the second sound word (see Z.Snd.cue)
def Snd.w2(+tr: U32) -> U32:
  (((tr >> 9n) .&. 3) .|. (((tr >> 11n) .&. 1) << 2n) .|. (((tr >> 12n) .&. 63) << 3n) : U32)

def Snd.tracks(+ts: +List<C.Track>, +acc: U32) -> U32:
  match ts:
    case []:
      acc
    case t <> rest:
      C.Track{+ps, open, +ss, st, en, +cfg, +stats} = t
      Snd.tracks(rest, Snd.slots(ss, ps, C.Cfg.type(cfg), open && C.Test.passed(stats), acc))

def snd_word(+p0: C.Park, +p1: C.Park, +inc0: U32, +inc1: U32, +msg0: U32, +msg1: U32,
  +clicked: Bool, +var: U32) -> U32:
  C.Park{m0, g0, +rs0, t0, c0, +time0, n0, f0, mess, staff} = p0
  C.Park{m1, +gs1, +rs1, +tr1, c1, +time1, n1, f1, mess, staff} = p1
  +fresh = Bool.not(U32.is_eq(msg1, msg0))
  +coin = (inc1 > inc0 : U32) || fresh && (U32.is_eq(msg1, 8) || U32.is_eq(msg1, 9))
  +thud = fresh && U32.is_eq(msg1, 1)
  +buzz = fresh && (U32.is_eq(msg1, 2) || U32.is_eq(msg1, 10))
  +go = Rides.started(rs0, rs1)
  +bell = Bool.not(U32.is_eq((go .&. 2 : U32), 0)) || fresh && U32.is_eq(msg1, 6)
  +whoosh = Bool.not(U32.is_eq((go .&. 4 : U32), 0))
  +chime = Bool.not(U32.is_eq((time0 / 3600 : U32), (time1 / 3600 : U32)))
  +crowd = U32.min((C.len32(C.Guest, gs1) / 3 : U32), 255)
  +tr = Snd.tracks(tr1, 0)
  (sel(coin, 1, 0) .|. sel(clicked, 2, 0) .|. sel(thud, 4, 0) .|. sel(buzz, 8, 0) .|. sel(bell, 16, 0)
    .|. sel(whoosh, 32, 0) .|. sel(chime, 64, 0) .|. (crowd << 8n) .|. ((tr .&. 255) << 16n)
    .|. (((tr >> 8n) .&. 1) << 24n) .|. (((var >> 16n) .&. 3) << 25n) : U32)

def UI.said(u: UI, +m: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, +msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, mx, my, md, tool, var, sp, sel(U32.is_eq(m, 0), msg, m), fr, inc, last, io, fps, tl, opt, fol}

# 17 when a coaster's test run passed this step, 18 when one failed, else 0
def Tracks.tested(+a: +List<C.Track>, +b: +List<C.Track>) -> U32:
  match a b:
    case Con{x, xs} Con{y, ys}:
      +s0 = C.Track.stats(x)
      +s1 = C.Track.stats(y)
      +was = C.Test.testing(s0) && Bool.not(C.Test.testing(s1))
      sel(was && C.Test.passed(s1), 17, sel(was && C.Test.failed(s1), 18, Tracks.tested(xs, ys)))
    case _ _:
      0

def Follow.cam(+x: U32, +y: U32, +h: U32, +up: U32) -> U32:
  ((((1024 + x) - y) << 16n) .|. (((356 + ((x + y) >> 1n)) - (8 * h + up)) .&. 65535) : U32)

# the next staff member of a kind after id `after` (or the first), or NONE
def Follow.staff(+ss: +List<C.Staff>, +id: U32, +q: C.Q) -> U32:
  match ss:
    case []:
      C.NONE()
    case s <> rest:
      C.Staff{+sid, +x, +y, dir, kind, st, tgt, tmr, zone, look} = s
      +h = C.Land.h(q, (x >> 4n : U32), (y >> 4n : U32))
      sel(U32.is_eq(sid, id), Follow.cam(x, y, h, (6 + Stair.dz(q, x, y, h) : U32)), Follow.staff(rest, id, q))

def Follow.guest(g: C.Guest, +q: C.Q) -> U32:
  C.Guest{+id, +x, +y, +dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  +tl = C.Land.get(q, (x >> 4n : U32), (y >> 4n : U32))
  +up = Bool.not(U32.is_eq((dir .&. 65536 : U32), 0)) && Bool.not(U32.is_eq(C.Deck.of(tl), 0))
  +h = sel(up, C.Deck.of(tl), C.Tile.h(tl))
  sel(U32.is_eq(id, C.NONE()), C.NONE(), Follow.cam(x, y, h, (6 + sel(up, 0, Stair.dz(q, x, y, h)) : U32)))

# the place of the train with the lowest id (piece * 256 + progress), or
# NONE: the block list turns every tick, so "the first train in the list"
# changes from tick to tick
def Blocks.first(+ss: +List<C.Slot>, +bid: U32, +bq: U32) -> U32:
  match ss:
    case []:
      bq
    case s <> rest:
      match s:
        case C.Free{a, n, st}:
          Blocks.first(rest, bid, bq)
        case C.Held{+a, n, st, t}:
          C.Train{+id, +prog, sp, w} = t
          Blocks.first(rest, sel((id < bid : U32), id, bid), sel((id < bid : U32), (a * 256 + prog : U32), bq))

# the lead train's place on its track (piece * 256 + progress), or NONE
def Blocks.lead(+ss: +List<C.Slot>) -> U32:
  match ss:
    case []:
      C.NONE()
    case s <> rest:
      match s:
        case C.Free{a, n, st}:
          Blocks.lead(rest)
        case C.Held{+a, n, st, t}:
          C.Train{id, +prog, sp, w} = t
          (a * 256 + prog : U32)

def Follow.dr(d: Dr) -> U32:
  match d:
    case DCar{+x, +y, dd, lead, rd}:
      ((((x - B()) + 1024 - 1280) << 16n) .|. (((y - B()) - 150 - 6) .&. 65535) : U32)
    case _:
      C.NONE()

def Follow.dyn(+ds: +List<Dyn>) -> U32:
  match ds:
    case []:
      C.NONE()
    case d <> rest:
      Follow.dr(Dyn.dr(d))

# a running coaster: its lead car, drawn with the camera at 0, 0
def Follow.car(on: Bool, +ps: +List<C.Piece>, +q: U32) -> U32:
  match on:
    case True{}:
      +total = U32.max((C.len32(C.Piece, ps) * 256 : U32), 1)
      +w = (q % total : U32)
      Follow.dyn(car_dyn(C.Pieces.get(ps, (w >> 8n : U32)), (w .&. 255 : U32), 1, 0, 0, 0, []))
    case False{}:
      C.NONE()

def Follow.ride(+p: C.Park, +idx: U32) -> U32:
  +r = C.Rides.get(C.Park.rides(p), idx)
  +t = C.Tracks.get(C.Park.track(p), C.Ride.ht(r))
  +lead = Blocks.first(C.Track.blocks(t), C.NONE(), C.NONE())
  +coaster = U32.is_eq(C.Ride.kind(r), 5) && C.Track.open(t) && Bool.not(U32.is_eq(lead, C.NONE()))
  +mid = Follow.cam((C.Ride.cx(r) * 16 + C.Ride.wd(r) * 8 : U32), (C.Ride.cy(r) * 16 + C.Ride.wd(r) * 8 : U32),
    C.Land.h(C.Park.map(p), C.Ride.cx(r), C.Ride.cy(r)), 16)
  +car = Follow.car(coaster, C.Track.pieces(t), lead)
  sel((idx >= C.len32(C.Ride, C.Park.rides(p)) : U32), C.NONE(), sel(coaster && Bool.not(U32.is_eq(car, C.NONE())), car, mid))

def Follow.go(+k: U32, +p: C.Park, +id: U32) -> U32:
  match k:
    case 1:
      Follow.guest(Guests.find(C.Park.guests(p), id), C.Park.map(p))
    case 2:
      Follow.staff(C.Park.staff(p), id, C.Park.map(p))
    case 3:
      Follow.ride(p, id)
    case _:
      C.NONE()

# where the camera goes to follow `fol`, or NONE when there is nothing to follow
def Follow.at(+p: C.Park, +fol: U32) -> U32:
  Follow.go((fol .&. 3 : U32), p, (fol >> 2n : U32))

def step_game.go(+p: C.Park, +ui: UI, +wm: WM, +acts: +List<C.Act>, quit: Bool,
  snd: Z.Snd, +clicked: Bool, ds: List<&2, U32>) -> Maybe<Game>:
  UI{+cx, +cy, +keys, mx, my, md, tool, +var, +sp, +msg, +fr, +inc, last, io, fps, tl, +opt, +fol} = ui
  +req = ((opt >> 15n) .&. 7 : U32)
  +p0 = Scn.swap((req > 0 : U32), req, p)
  +r1 = apply(acts, p0, msg, inc)
  +r20 = ticks(U32.to_nat(Speed.ticks(sp, fr)), Res.park(r1), Res.inc(r1))
  +gop = Goal.op(Res.park(r20))
  +r2 = {Res{C.Park.run(Bool.pick(List<C.Act>, (gop > 0 : U32), [C.ParkOp{gop}], []), Res.park(r20)), Res.msg(r20), Res.inc(r20)} : Res}
  +time = C.Park.time(Res.park(r2))
  +newmonth = U32.is_eq((time % 3600 : U32), 0)
  +m2 = sel(U32.is_eq((fr .&. 255 : U32), 0), 0, Res.msg(r1))
  +step = sel(U32.is_eq(View.z(var), 1), 4, sel(U32.is_eq(View.z(var), 2), 16, 8))
  +nt0 = C.len32(C.Track, C.Park.track(p0))
  +nt1 = C.len32(C.Track, C.Park.track(Res.park(r2)))
  +fresh = (nt1 > nt0 : U32)
  +fw = sel(U32.is_eq(keys, 0), fol, 0)
  +tgt = Follow.at(Res.park(r2), fw)
  +on = Bool.not(U32.is_eq(fw, 0)) && Bool.not(U32.is_eq(tgt, C.NONE()))
  +ui2 = {UI{sel(on, U32.min(U32.max((tgt >> 16n : U32), 260), 2000), cam(keys, cx, 4, 8, step, 260, 2000)),
    sel(on, U32.min(U32.max((tgt .&. 65535 : U32), 170), 1500), cam(keys, cy, 1, 2, step, 170, 1500)), keys, mx, my, md, sel(fresh, 12, tool),
    var, sp, sel(U32.is_eq(Res.msg(r1), msg), m2, Res.msg(r1)), (fr + 1 : U32),
    sel(newmonth, 0, Res.inc(r2)), last, io, fps, tl,
    sel((req > 0 : U32), (opt .&. 4294705151 .&. 4294737919 : U32), opt), sel(on && (req < 1 : U32), fw, 0)} : UI}
  +bk = Rides.broke(C.Park.rides(p), C.Park.rides(Res.park(r2)))
  +word = (snd_word(p, Res.park(r2), inc, Res.inc(r2), msg, Res.msg(r1), clicked, var)
    .|. (Opt.vol(opt, 4n) << 27n) .|. (Opt.vol(opt, 6n) << 29n)
    .|. sel(A.Art.rain(C.Park.time(Res.park(r2))), 2147483648, 0)
    .|. sel((bk >= 100 : U32) && (bk < 110 : U32), 8, sel((bk >= 110 : U32), 16, 0)) : U32)
  +award = Award.pick(newmonth && (time > 0 : U32), Res.park(r2))
  # a new coaster opens its construction window; a new park closes them all
  +ws0 = Bool.pick(+List<Win>, (req > 0 : U32), [], WM.wins(wm))
  +ws1 = Bool.pick(+List<Win>, fresh, Wins.open(ws0, 8, (nt1 - 1 : U32), 16, 30), ws0)
  +wm2 = {WM{Bool.pick(+List<Win>, (gop > 0 : U32), Wins.open(ws1, 7, 0, 150, 90), ws1), WM.drag(wm), WM.gx(wm), WM.gy(wm)} : WM}
  +tmsg = Tracks.tested(C.Park.track(p0), C.Park.track(Res.park(r2)))
  Bool.pick(Maybe<Game>, quit, None{}, Some{Game{Res.park(r2), UI.said(ui2, sel((award > 0 : U32), award, sel((tmsg > 0 : U32), tmsg, bk))), wm2,
    Z.Snd.cue(snd, (word .|. sel((gop > 0 : U32) || (award > 0 : U32) || U32.is_eq(tmsg, 17), 16, 0) : U32),
      Snd.w2(Snd.tracks(C.Park.track(Res.park(r2)), 0))), ds}})

def step_game(+g: Game, events: List<Event>) -> Maybe<Game>:
  Game{+p, +ui, +wm, snd, ds} = g
  +ev = on_events(events, ui, wm, p, [], False{})
  # a click: an act, a window opened or closed, or another tool
  +clicked = Bool.not(U32.is_eq(C.len32(C.Act, EV.acts(ev)), 0))
    || Bool.not(U32.is_eq(C.len32(Win, WM.wins(EV.wm(ev))), C.len32(Win, WM.wins(wm))))
    || Bool.not(U32.is_eq(UI.tool(EV.ui(ev)), UI.tool(ui)))
  step_game.go(p, EV.ui(ev), EV.wm(ev), EV.acts(ev), EV.quit(ev), snd, clicked, ds)

# The starting park
# -----------------

def view(g: Game) -> Game & Image:
  +g2 = g
  (g2, frame(g2))

def UI.clock(u: UI, +now: Nat) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, +fr, inc, last, io, +fps, +tl, +opt, fol} = u
  +due = U32.is_eq((fr .&. 31 : U32), 0)
  +dt = U32.from_nat(Nat.sub(now, tl))
  +f = (32000 / U32.max(dt, 1) : U32)
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io,
    sel(due, f, fps), Bool.pick(Nat, due, now, tl), sel(due, Opt.dyn(opt, f), opt), fol}

def Game.clock(g: Game, +now: Nat) -> Game:
  Game{p, ui, wm, snd, ds} = g
  Game{p, UI.clock(ui, now), wm, snd, ds}

def Game.clock_m(m: Maybe<Game>, +now: Nat) -> Maybe<Game>:
  match m:
    case None{}:
      None{}
    case Some{g}:
      Some{Game.clock(g, now)}

def Game.fps(g: Game) -> U32:
  Game{p, ui, wm, snd, ds} = g
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = ui
  sel(U32.is_eq((fr .&. 127 : U32), 1), fps, 0)

def Game.say.go(quiet: Bool, +f: U32, g: Game) -> IO(Maybe<Game>):
  match quiet:
    case True{}:
      IO.pure(Maybe<Game>, Some{g})
    case False{}:
      do IO<Maybe<Game>>:
        IO.print("fps " ++ U32.show(f))
        return Some{g}

def Game.say(+f: U32, m: Maybe<Game>) -> IO(Maybe<Game>):
  match m:
    case None{}:
      IO.pure(Maybe<Game>, None{})
    case Some{g}:
      Game.say.go(U32.is_eq(f, 0), f, g)

def Game.report(m: Maybe<Game>) -> IO(Maybe<Game>):
  match m:
    case None{}:
      IO.pure(Maybe<Game>, None{})
    case Some{+g}:
      Game.say(Game.fps(g), Some{g})

# Saving and loading (F5 / F9)
# ----------------------------

def UI.done(u: UI, +m: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{cx, cy, keys, mx, my, md, tool, var, sp, m, fr, inc, last, 0, fps, tl, opt, fol}

def Game.done(g: Game, +m: U32) -> Game:
  Game{p, ui, wm, snd, ds} = g
  Game{p, UI.done(ui, m), wm, snd, ds}

def Game.io(g: Game) -> U32:
  Game{p, ui, wm, snd, ds} = g
  UI.io(ui)

# Track designs
# -------------
# The library: eight slots of 256 values, filled in order. A slot: the
# number of pieces after the station (0 empty), the coaster's settings,
# then each piece's kind. Every value fits a byte, so the file is the list.
def DESIGN_PATH() -> String:
  "designs.sav"

def Words.pad(+ws: +List<U32>, +n: U32) -> +List<U32>:
  Words.take(List.append(&2, U32, ws, C.Tab.zero(n, [])), n)

# filled slots (they fill in order)
def Lib.count(+n: Nat, +ds: +List<U32>, +i: U32) -> U32:
  match n:
    case 0n:
      i
    case 1n+m:
      sel(U32.is_eq(C.Tab.at(ds, (i * 256 : U32)), 0), i, Lib.count(m, ds, (i + 1 : U32)))

def Lib.add(+ds: +List<U32>, +d: +List<U32>) -> +List<U32>:
  +n = Lib.count(8n, ds, 0)
  +pd = Words.pad(d, 256)
  Bool.pick(+List<U32>, (n < 8 : U32),
    List.append(&2, U32, Words.take(ds, (n * 256 : U32)), List.append(&2, U32, pd, Words.drop(ds, ((n + 1) * 256 : U32)))),
    List.append(&2, U32, Words.drop(ds, 256), pd))

def Pieces.kinds(+ps: +List<C.Piece>) -> +List<U32>:
  match ps:
    case []:
      []
    case p <> rest:
      +p2 = p
      C.Piece.kind(p2) <> Pieces.kinds(rest)

def Words.tail(+ws: +List<U32>) -> +List<U32>:
  match ws:
    case []:
      []
    case w <> rest:
      rest

# a finished coaster as a design: pieces after the station, settings, kinds
def Design.of(+t: C.Track) -> +List<U32>:
  +ks = Words.tail(Pieces.kinds(C.Track.pieces(t)))
  C.len32(U32, ks) <> C.Track.cfg(t) <> ks

# a design's kinds laid from a pose: the pieces they make (for ratings)
def Design.reps(+n: Nat, +op: U32) -> List<C.Act>:
  match n:
    case 0n:
      []
    case 1n+m:
      C.TrackOp{op} <> Design.reps(m, op)

def Design.pieces(+ks: +List<U32>, +n: U32, +k: U32) -> List<C.Act>:
  match ks:
    case []:
      []
    case kd <> rest:
      Bool.pick(List<C.Act>, U32.is_eq(n, 0), [], C.TrackOp{(kd .|. (k << 5n) : U32)} <> Design.pieces(rest, (n - 1 : U32), k))

# building a design is plain acts: the station, its type and lift speed,
# then each piece (the last one closes the circuit, and the re-check starts
# its test run)
def Design.acts(+w: +List<U32>, +x: U32, +y: U32, +v: U32, +k: U32) -> List<C.Act>:
  +n = C.Tab.at(w, 0)
  +cfg = C.Tab.at(w, 1)
  +ty = C.Cfg.type(cfg)
  +ls = ((cfg >> 5n) .&. 7 : U32)
  +k5 = (k << 5n : U32)
  C.Build{10, x, y, v} <> List.append(&1, C.Act, Bool.pick(List<C.Act>, (ty > 0 : U32), [C.TrackOp{(16 + ty + k5 : U32)}], []),
    List.append(&1, C.Act, Design.reps(U32.to_nat(C.sub0(ls, 2)), (23 + k5 : U32)),
    List.append(&1, C.Act, Design.reps(U32.to_nat(C.sub0(2, ls)), (22 + k5 : U32)), Design.pieces(Words.drop(w, 2), n, k))))

def Game.ds(g: Game) -> +List<U32>:
  Game{p, ui, wm, snd, ds} = g
  ds

def Game.with_ds(g: Game, +d: +List<U32>, +m: U32) -> Game:
  Game{p, ui, wm, snd, ds} = g
  Game{p, UI.done(ui, m), wm, snd, d}

def design.saved(r: File & Result<&1, &1, U32 & String, Unit>, +lib: +List<U32>, g: Game) -> IO(Maybe<Game>):
  (f, res) = r
  do IO<Maybe<Game>>:
    File.close(f)
    return Some{Game.with_ds(g, lib, 23)}

def design.write(r: Result<&1, &1, U32 & String, File>, +lib: +List<U32>, g: Game) -> IO(Maybe<Game>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<Game>, Some{Game.done(g, 24)})
    case Done{f}:
      do IO<Maybe<Game>>:
        w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, lib)
        design.saved(w, lib, g)

def design.save.go(ok: Bool, +k: U32, g: Game) -> IO(Maybe<Game>):
  match ok:
    case True{}:
      +g2 = g
      +lib = Lib.add(Game.ds(g2), Design.of(C.Tracks.get(C.Park.track(Game.park(g2)), k)))
      do IO<Maybe<Game>>:
        r : Result<&1, &1, U32 & String, File> <- File.open(DESIGN_PATH(), "w")
        design.write(r, lib, g2)
    case False{}:
      IO.pure(Maybe<Game>, Some{Game.done(g, 24)})

def design.save(+k: U32, g: Game) -> IO(Maybe<Game>):
  +g2 = g
  design.save.go(C.Track.closed(C.Tracks.get(C.Park.track(Game.park(g2)), k)), k, g2)

def design.got(res: Result<&1, &1, U32 & String, List<&2, U32>>, g: Game) -> Maybe<Game>:
  match res:
    case Fail{e}:
      Some{Game.done(g, 0)}
    case Done{bs}:
      +bs2 = bs
      +g2 = g
      Some{Bool.pick(Game, U32.is_eq(C.len32(U32, bs2), 2048), Game.with_ds(g2, bs2, 0), Game.done(g2, 0))}

def design.read(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, g: Game) -> IO(Maybe<Game>):
  (f, res) = r
  do IO<Maybe<Game>>:
    File.close(f)
    return design.got(res, g)

def design.load(r: Result<&1, &1, U32 & String, File>, g: Game) -> IO(Maybe<Game>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<Game>, Some{Game.done(g, 0)})
    case Done{f}:
      do IO<Maybe<Game>>:
        rd : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 2048)
        design.read(rd, g)

# building the chosen design at tile hov (if it all fits)
def design.build(+hov: U32, g: Game) -> Game:
  Game{+p, +ui, wm, snd, +ds} = g
  +var = UI.var(ui)
  +w = Lib.slot(ds, ((var >> 28n) .&. 7 : U32))
  +x = (hov >> 6n : U32)
  +y = (hov .&. 63 : U32)
  +v = (var .&. 3 : U32)
  +fits = Design.fits(p, w, x, y, v)
  Game{Bool.pick(C.Park, fits, C.Park.run(Design.acts(w, x, y, v, C.len32(C.Track, C.Park.track(p))), p), p),
    UI.done(ui, sel(fits, 25, 26)), wm, snd, ds}

def SAVE_PATH() -> String:
  "eldergrove.sav"

def save.put(r: File & Result<&1, &1, U32 & String, Unit>, g: Game) -> IO(Maybe<Game>):
  (f, res) = r
  do IO<Maybe<Game>>:
    File.close(f)
    return Some{Game.done(g, 3)}

def save.with(r: Result<&1, &1, U32 & String, File>, +g: Game) -> IO(Maybe<Game>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<Game>, Some{Game.done(g, 5)})
    case Done{f}:
      do IO<Maybe<Game>>:
        w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, S.Save.file(Game.park(g)))
        save.put(w, g)

def load.got(m: Maybe<&2, C.Park>, g: Game) -> Maybe<Game>:
  match m:
    case None{}:
      Some{Game.done(g, 5)}
    case Some{p}:
      Game{old, ui, wm, snd, ds} = g
      Some{Game{p, UI.done(ui, 4), WM.new(), snd, ds}}

def load.bytes(res: Result<&1, &1, U32 & String, List<&2, U32>>, g: Game)
  -> Maybe<Game>:
  match res:
    case Fail{e}:
      Some{Game.done(g, 5)}
    case Done{bs}:
      load.got(S.Load.file(bs), g)

def load.read(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, g: Game)
  -> IO(Maybe<Game>):
  (f, res) = r
  do IO<Maybe<Game>>:
    File.close(f)
    return load.bytes(res, g)

def load.sized.go(res: Result<&1, &1, U32 & String, U32>, f: File, g: Game)
  -> IO(Maybe<Game>):
  match res:
    case Fail{e}:
      do IO<Maybe<Game>>:
        File.close(f)
        return Some{Game.done(g, 5)}
    case Done{n}:
      do IO<Maybe<Game>>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, n)
        load.read(r, g)

def load.sized(r: File & Result<&1, &1, U32 & String, U32>, g: Game) -> IO(Maybe<Game>):
  (f, res) = r
  load.sized.go(res, f, g)

def load.with(r: Result<&1, &1, U32 & String, File>, g: Game) -> IO(Maybe<Game>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<Game>, Some{Game.done(g, 5)})
    case Done{f}:
      do IO<Maybe<Game>>:
        z : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
        load.sized(z, g)

def Game.do_io(+w: U32, +arg: U32, g: Game) -> IO(Maybe<Game>):
  match w:
    case 1:
      do IO<Maybe<Game>>:
        r : Result<&1, &1, U32 & String, File> <- File.open(SAVE_PATH(), "w")
        save.with(r, g)
    case 2:
      do IO<Maybe<Game>>:
        r : Result<&1, &1, U32 & String, File> <- File.open(SAVE_PATH(), "r")
        load.with(r, g)
    case 3:
      design.save(arg, g)
    case 4:
      do IO<Maybe<Game>>:
        r : Result<&1, &1, U32 & String, File> <- File.open(DESIGN_PATH(), "r")
        design.load(r, g)
    case 5:
      IO.pure(Maybe<Game>, Some{design.build(arg, g)})
    case _:
      IO.pure(Maybe<Game>, Some{g})

def Game.io_m(m: Maybe<Game>) -> IO(Maybe<Game>):
  match m:
    case None{}:
      IO.pure(Maybe<Game>, None{})
    case Some{+g}:
      Game.do_io((Game.io(g) .&. 15 : U32), (Game.io(g) >> 4n : U32), g)

def tick(events: List<Event>, g: Game) -> IO(Maybe<Game>):
  +g2 = g
  do IO<Maybe<Game>>:
    now : Nat <- IO.now()
    m : Maybe<Game> <- Game.io_m(Game.clock_m(step_game(g2, events), now))
    return m

# headless screenshots: sample the frame at logical resolution into a PPM

def sample(+d: Nat, img: Image, +x: U32, +y: U32) -> U32:
  match d img:
    case _ Pix{c}:
      c
    case 0n Qua{a, b, c, e}:
      0
    case 1n+p Qua{a, b, c, e}:
      +m = U32.shln(1, p)
      +bx = Bool.not(U32.is_eq((x .&. m : U32), 0))
      +by = Bool.not(U32.is_eq((y .&. m : U32), 0))
      sample(p, Bool.pick(Image, by, Bool.pick(Image, bx, e, c), Bool.pick(Image, bx, b, a)), x, y)

def bytes(+n: Nat, +img: Image, +i: U32, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +x = (i .&. 511 : U32)
      +y = (i >> 9n : U32)
      +c = sample(9n, img, x, y)
      bytes(p, img, (i - 1 : U32),
        ((c >> 16n) .&. 255 : U32) <> ((c >> 8n) .&. 255 : U32) <> (c .&. 255 : U32) <> acc)

def arg_nat(s: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(s), 600n)

def arg_or(s: String, +d: U32) -> U32:
  Maybe.default(&2, U32, U32.read(s), d)

def arg_u32(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 1)

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, res) = r
  File.close(f)

def shot.write(path: String, +px: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f,
      List.append(&2, U32, str_bytes("P6\n512 320\n255\n"), px))
    close_pair(r)

def UI.cam(u: UI, +x: U32, +y: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  UI{x, y, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol}

# win: a window to show (kind * 256 + arg; 0 for none)
def UI.zoomed(u: UI, +z: U32) -> UI:
  UI{cx, cy, keys, mx, my, md, +tool, +var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = u
  +c = Cat.of(tool)
  UI{cx, cy, keys, mx, my, md, tool, set_cat(((var .&. 4294180863) .|. ((z .&. 3) << 18n) : U32), sel((c < 99 : U32), c, 0)),
    sp, msg, fr, inc, last, io, fps, tl, opt, fol}

# win: a window to show (kind * 256 + arg; 0 for none); z: the zoom
def shot.go(g: Game, path: String, n: Nat, +tool: U32, +cx: U32, +cy: U32, +win: U32, +z: U32) -> IO(Unit):
  Game{+p, ui, wm, snd, ds} = g
  +p2 = Res.park(ticks(n, p, 0))
  +wk = ((win >> 8n) .&. 15 : U32)
  +ws = Bool.pick(+List<Win>, U32.is_eq(win, 0), [], [Win{wk, sel(U32.is_eq(wk, 8), 16, sel(U32.is_eq(wk, 9) || U32.is_eq(wk, 10), 96, 300)), 40, (win .&. 255 : U32)}])
  +u0 = ui
  +u1 = UI.with_var(u0, Cons.preview(UI.var(u0), sel(U32.is_eq(wk, 8), (300 + (win >> 12n) : U32), 0)))
  # tool 99: follow the starter coaster (ride 14) instead
  +fol = sel(U32.is_eq(tool, 99), (3 .|. (14 << 2n) : U32), 0)
  +tg = Follow.at(p2, fol)
  +on = Bool.not(U32.is_eq(fol, 0)) && Bool.not(U32.is_eq(tg, C.NONE()))
  +g2 = {Game{p2, UI.with_fol(UI.zoomed(UI.cam(UI.with_tool(UI.at(u1, 256, 150), sel(on, 12, tool)),
    sel(on, (tg >> 16n : U32), cx), sel(on, (tg .&. 65535 : U32), cy)), z), fol), WM{ws, 0, 0, 0}, snd, ds} : Game}
  shot.write(path, bytes(163840n, frame(g2), 163839, []))

def Game.with(g: Game, acts: List<C.Act>) -> Game:
  Game{+p, +ui, wm, snd, ds} = g
  Game{C.Park.run(acts, p), ui, wm, snd, ds}

def ctest.bad() -> List<C.Act>:
  List.append(&1, C.Act, clear2_acts(), [C.Build{10, 40, 56, 0}, C.TrackOp{37}, C.TrackOp{33}, C.TrackOp{34}, C.TrackOp{43},
   C.TrackOp{43}, C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{32},
   C.TrackOp{43}, C.TrackOp{43}, C.TrackOp{56}])

# run until coaster 1's test ends (in steps of 50 ticks, at most n steps)
def shot.acts(b: Bool) -> List<C.Act>:
  match b:
    case True{}:
      ctest.bad()
    case False{}:
      demo_acts()

def shot.lib(g: Game) -> Game:
  +g2 = Game.with(g, loop2_acts())
  +lib = Lib.add(Lib.add(Lib.empty(), Design.of(C.Tracks.get(C.Park.track(Game.park(g2)), 1))),
    Design.of(C.Tracks.get(C.Park.track(Game.park(g2)), 0)))
  Game.with_ds(g2, lib, 0)

def bridge_acts() -> List<C.Act>:
  List.append(&1, C.Act, clear2_acts(), [C.Build{2, 39, 56, 0}, C.Build{2, 39, 56, 0}, C.Build{2, 41, 56, 0}, C.Build{2, 41, 56, 0},
   C.Build{2, 38, 56, 0}, C.Build{2, 38, 56, 0}, C.Build{2, 42, 56, 0}, C.Build{2, 42, 56, 0},
   C.Build{1, 38, 56, 0}, C.Build{1, 39, 56, 0}, C.Build{1, 41, 56, 0}, C.Build{1, 42, 56, 0},
   C.Build{1, 40, 54, 0}, C.Build{1, 40, 55, 0}, C.Build{1, 40, 56, 0}, C.Build{1, 40, 57, 0},
   C.Build{1, 40, 58, 0}, C.Build{48, 40, 56, 0}])

def long_acts() -> List<C.Act>:
  List.append(&1, C.Act, clear2_acts(), [C.Build{10, 40, 56, 0}, C.TrackOp{37}, C.TrackOp{37}, C.TrackOp{37}, C.TrackOp{37},
   C.TrackOp{37}, C.TrackOp{36}, C.TrackOp{36}, C.TrackOp{32}, C.TrackOp{32},
   C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{36},
   C.TrackOp{36}, C.TrackOp{61}, C.TrackOp{61}, C.TrackOp{57}, C.TrackOp{40}])

# the park a shot pictures: window kinds 8 (an unfinished coaster, or a failed
# test with piece 15), 10 (the designs, as does the design tool), 11 (a
# walkway) and 12 (a long train) bring their own
def shot.game(+wk: U32, +tool: U32, +win: U32) -> Game:
  match wk:
    case 8:
      Game.with(Game.new(), shot.acts(U32.is_eq((win >> 12n : U32), 15)))
    case 10:
      shot.lib(Game.new())
    case 11:
      Game.with(Game.new(), bridge_acts())
    case 12:
      Game.with(Game.new(), long_acts())
    case _:
      Bool.pick(Game, U32.is_eq(tool, 47), shot.lib(Game.new()), Game.new())

def shot(path: String, n: Nat, +tool: U32, +cx: U32, +cy: U32, +win: U32, +z: U32) -> IO(Unit):
  shot.go(shot.game(((win >> 8n) .&. 15 : U32), tool, win), path, n, tool, cx, cy, win, z)

# the designs window pictured with the save test's second loop as a design
def is_shot(+args: +List<String>) -> Bool:
  match args:
    case []:
      False{}
    case a <> rest:
      String.eq(a, "--shot")

def nth(+args: +List<String>, +i: U32) -> String:
  match args:
    case []:
      ""
    case a <> rest:
      Bool.pick(String, U32.is_eq(i, 0), a, nth(rest, (i - 1 : U32)))

# headless timing: n frames of simulation plus rendering
def bench.one(+mode: U32, +g: Game) -> U32:
  match mode:
    case 0:
      (sample(9n, frame(g), 200, 150) .&. 1 : U32)
    case 1:
      0
    case _:
      C.len32(Dr, scene(g))

def bench.loop(+n: Nat, +mode: U32, +g: Game) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      +g2 = Maybe.default(&1, Game, step_game(g, []), g)
      (bench.one(mode, g2) + bench.loop(p, mode, g2) : U32)

# benches run at normal speed (one tick a frame)
def Game.with_sp(g: Game, +l: U32) -> Game:
  Game{p, ui, wm, snd, ds} = g
  UI{cx, cy, keys, mx, my, md, tool, var, sp, msg, fr, inc, last, io, fps, tl, opt, fol} = ui
  Game{p, UI{cx, cy, keys, mx, my, md, tool, var, l, msg, fr, inc, last, io, fps, tl, opt, fol}, wm, snd, ds}

def bench.go(g: Game, +n: Nat, +mode: U32) -> IO(Unit):
  +g2 = Game.with_sp(g, 3)
  do IO<Unit>:
    t0 : Nat <- IO.now()
    r : U32 = bench.loop(n, mode, g2)
    t1 : Nat <- IO.now()
    IO.print(Nat.show(n) ++ " frames in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms (" ++ U32.show(r) ++ "), guests " ++ U32.show(C.len32(C.Guest, C.Park.guests(Game.park(g2)))))

# stress testing: a crowd of n extra adventurers at the gate
def crowd.go(+n: Nat, +id: U32, +t: U32, +acc: +List<C.Guest>) -> +List<C.Guest>:
  match n:
    case 0n:
      acc
    case 1n+k:
      crowd.go(k, (id + 1 : U32), t, C.Guest.new(id, (t + id * 7 : U32), 0) <> acc)

def crowd(g: Game, +n: U32) -> Game:
  Game{p, ui, wm, snd, ds} = g
  C.Park{map, guests, rides, track, cash, +time, +nid, fin, mess, staff} = p
  Game{C.Park{map, crowd.go(U32.to_nat(n), nid, time, guests), rides, track, cash, time,
    (nid + n : U32), fin, mess, staff}, ui, wm, snd, ds}

# --scen K MONTHS: play scenario K a month at a time, reporting its state
def scen.line(+p: C.Park) -> String:
  +r = C.Fin.res(C.Park.fin(p))
  "month " ++ U32.show((C.Park.time(p) / 3600 : U32)) ++ ": guests " ++ U32.show(C.len32(C.Guest, C.Park.guests(p)))
    ++ ", rating " ++ U32.show(C.Fin.rating(C.Park.fin(p))) ++ ", gold " ++ U32.show(C.Park.cash(p))
    ++ ", loan " ++ U32.show(C.Fin.loan(C.Park.fin(p))) ++ ", researched " ++ U32.show((r .&. 8191 : U32))
    ++ ", progress " ++ U32.show(((r >> 16n) .&. 255 : U32)) ++ ", status " ++ U32.show(Scn.status(p))

# --coastertest: the second loop, then one that climbs straight out of its
# station with no lift, each sent on a test run; how each test ended
def ctest.good() -> List<C.Act>:
  List.append(&1, C.Act, clear2_acts(), [C.Build{10, 40, 56, 0}, C.TrackOp{37}, C.TrackOp{38}, C.TrackOp{38}, C.TrackOp{45},
   C.TrackOp{43}, C.TrackOp{43}, C.TrackOp{41}, C.TrackOp{32}, C.TrackOp{32},
   C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{43}, C.TrackOp{43}, C.TrackOp{56}])

def ctest.run(+n: Nat, +p: C.Park, +t: U32) -> String:
  match n:
    case 0n:
      "still testing after " ++ U32.show(t) ++ " ticks"
    case 1n+m:
      +st = C.Track.stats(C.Tracks.get(C.Park.track(p), 1))
      Bool.pick(String, C.Test.testing(st),
        ctest.run(m, Res.park(ticks(50n, p, 0)), (t + 50 : U32)),
        Bool.pick(String, C.Test.passed(st), "PASSED", Bool.pick(String, C.Test.failed(st),
          "FAILED at piece " ++ U32.show(C.Test.fail(st)), "not tested")) ++ " after about " ++ U32.show(t) ++ " ticks"
          ++ ", rating " ++ U32.show(C.Ride.rate(C.Rides.get(C.Park.rides(p), Coaster.ride(C.Park.rides(p), 1, 0))))
          ++ ", open " ++ Bool.show(C.Track.open(C.Tracks.get(C.Park.track(p), 1))))

def ctest.state(+p: C.Park, +k: U32) -> String:
  +t = C.Tracks.get(C.Park.track(p), k)
  "pieces " ++ U32.show(C.len32(C.Piece, C.Track.pieces(t))) ++ ", open " ++ Bool.show(C.Track.open(t))
    ++ ", test state " ++ U32.show((C.Track.stats(t) .&. 3 : U32)) ++ ", gold " ++ U32.show(C.Park.cash(p))
    ++ ", ride kind " ++ U32.show(C.Ride.kind(C.Rides.get(C.Park.rides(p), (C.len32(C.Ride, C.Park.rides(p)) - 1 : U32))))

# the loop without its test op: closing the circuit starts a test by itself
def ctest.closing() -> List<C.Act>:
  List.append(&1, C.Act, clear2_acts(), [C.Build{10, 40, 56, 0}, C.TrackOp{37}, C.TrackOp{38}, C.TrackOp{38}, C.TrackOp{45},
   C.TrackOp{43}, C.TrackOp{43}, C.TrackOp{41}, C.TrackOp{32}, C.TrackOp{32},
   C.TrackOp{32}, C.TrackOp{32}, C.TrackOp{43}, C.TrackOp{43}])

# sixteen more coasters' stations on the cleared patch
def ctest.many() -> List<C.Act>:
  List.append(&1, C.Act, clear2_acts(), [C.Build{10, 38, 54, 0}, C.Build{10, 39, 54, 0}, C.Build{10, 40, 54, 0}, C.Build{10, 41, 54, 0}, C.Build{10, 42, 54, 0}, C.Build{10, 43, 54, 0}, C.Build{10, 44, 54, 0}, C.Build{10, 45, 54, 0}, C.Build{10, 38, 55, 0}, C.Build{10, 39, 55, 0}, C.Build{10, 40, 55, 0}, C.Build{10, 41, 55, 0}, C.Build{10, 42, 55, 0}, C.Build{10, 43, 55, 0}, C.Build{10, 44, 55, 0}, C.Build{10, 45, 55, 0}])

# a design saved from the loop, built back where the loop stood (after
# demolishing it)
def ctest.design(+p: C.Park, +w: +List<U32>) -> String:
  +fits = Design.fits(p, w, 40, 56, 0)
  +p2 = C.Park.run(Design.acts(w, 40, 56, 0, C.len32(C.Track, C.Park.track(p))), p)
  "fits " ++ Bool.show(fits) ++ ", " ++ U32.show(C.Tab.at(w, 0)) ++ " pieces after the station, rating "
    ++ U32.show(Design.rate(w)) ++ "; built: " ++ ctest.state(p2, 2)

# a walkway: raised paths at x 38-39 and 41-42 (two levels up), a ground
# path along x = 40 under them, a deck at (40, 56) between
def btest.go() -> IO(Unit):
  +p = C.Park.run(bridge_acts(), Game.park(Game.new()))
  +q = C.Park.map(p)
  +g = C.Land.h(q, 40, 55)
  +hi = C.Land.h(q, 39, 56)
  do IO<Unit>:
    IO.print("ground " ++ U32.show(g) ++ ", raised paths " ++ U32.show(hi) ++ ", deck level " ++ U32.show(C.Deck.of(C.Land.get(q, 40, 56))))
    IO.print("from the raised path onto the deck: " ++ U32.show(C.Land.step(q, 40, 56, hi, False{}, False{}, True{}))
      ++ " (9 | level << 4: up on the deck)")
    IO.print("from the ground path under it: " ++ U32.show(C.Land.step(q, 40, 56, g, False{}, False{}, True{}))
      ++ " (1 | height << 4: the path below)")
    IO.print("off the deck to the far raised path: " ++ U32.show(C.Land.step(q, 41, 56, hi, False{}, False{}, True{})))

# a flat loop with a six-piece station, its trains set to five cars
def ctest.long(+p: C.Park) -> String:
  +t = C.Tracks.get(C.Park.track(p), 1)
  "cars " ++ U32.show(C.Track.cars(t)) ++ ", seats a train (station word) " ++ U32.show(((C.Track.stn(t) >> 13n) .&. 63 : U32))
    ++ ", trains " ++ U32.show(U32.from_nat(C.Blocks.trains(C.Track.blocks(t)))) ++ ", open " ++ Bool.show(C.Track.open(t))

def ctest.go2() -> IO(Unit):
  do IO<Unit>:
    IO.print("long station: " ++ ctest.long(C.Park.run(long_acts(), Game.park(Game.new()))))
    IO.print("one train set: " ++ ctest.long(C.Park.run([C.TrackOp{40}, C.TrackOp{52}, C.TrackOp{52}, C.TrackOp{57}, C.TrackOp{40}], C.Park.run(long_acts(), Game.park(Game.new())))))

def ctest.go() -> IO(Unit):
  do IO<Unit>:
    IO.print("closing the circuit: " ++ ctest.state(C.Park.run(ctest.closing(), Game.park(Game.new())), 1))
    IO.print("tested loop: " ++ ctest.state(Res.park(ticks(1500n, C.Park.run(ctest.good(), Game.park(Game.new())), 0)), 1))
    IO.print("cut at piece 5: " ++ ctest.state(C.Park.run([C.TrackOp{(26 .|. 32 .|. (5 << 16n) : U32)}], Res.park(ticks(1500n, C.Park.run(ctest.good(), Game.park(Game.new())), 0))), 1))
    IO.print("demolished: " ++ ctest.state(C.Park.run([C.TrackOp{59}], Res.park(ticks(1500n, C.Park.run(ctest.good(), Game.park(Game.new())), 0))), 1))
    IO.print("design: " ++ ctest.design(C.Park.run([C.TrackOp{59}], Res.park(ticks(1500n, C.Park.run(ctest.good(), Game.park(Game.new())), 0))),
      Lib.slot(Lib.add(Lib.empty(), Design.of(C.Tracks.get(C.Park.track(Res.park(ticks(1500n, C.Park.run(ctest.good(), Game.park(Game.new())), 0))), 1))), 0)))
    ctest.go2()
    IO.print("coasters after sixteen more stations: " ++ U32.show(C.len32(C.Track, C.Park.track(C.Park.run(ctest.many(), Game.park(Game.new()))))))
    IO.print("with a lift hill: " ++ ctest.run(80n, C.Park.run(ctest.good(), Game.park(Game.new())), 0))
    IO.print("no lift hill: " ++ ctest.run(80n, C.Park.run(ctest.bad(), Game.park(Game.new())), 0))
    IO.print("starter coaster: rating " ++ U32.show(C.Ride.rate(C.Rides.get(C.Park.rides(Game.park(Game.new())), 14)))
      ++ ", stats " ++ U32.show(C.Track.stats(C.Tracks.get(C.Park.track(Game.park(Game.new())), 0))))

def scen.run(+n: Nat, +p: C.Park) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      +p1 = Res.park(ticks(3600n, p, 0))
      +op = Goal.op(p1)
      +p2 = C.Park.run(Bool.pick(List<C.Act>, (op > 0 : U32), [C.ParkOp{op}], []), p1)
      do IO<Unit>:
        IO.print(scen.line(p2))
        scen.run(m, p2)

def warm(g: Game, +n: Nat) -> Game:
  Game{+p, +ui, wm, snd, ds} = g
  Game{Res.park(ticks(n, p, 0)), ui, wm, snd, ds}

def is_bench(+args: +List<String>) -> Bool:
  match args:
    case []:
      False{}
    case a <> rest:
      String.eq(a, "--bench")

# The window effects (win_frame.c): Base's Linux window with a parallel
# blit, and a native Windows window (win/winplat.c)
def Win.open(title: String, width: U32, height: U32) ->
  IO(Result<&1, &1, U32 & String, Window>):
  import "./win_frame.c"
  import "./win_open.js"

def Win.close(window: Window) -> IO(Unit):
  import "./win_frame.c"
  import "./win_close.js"

def Win.frame(window: Window, image: Image) ->
  IO(Window & Image & List<Event>):
  import "./win_frame.c"
  import "./win_frame.js"

# The frame loop, pipelined: while Win.frame fills and shows frame n on a
# helper thread, a forked computation steps the game and draws frame n+1 on
# the worker pool (from the input of frame n-1: one frame of latency).
type Nx is Type:
  Nx{m: Maybe<Game>, img: Image}

def Loop.nx(m: Maybe<Game>) -> Nx:
  match m:
    case None{}:
      Nx{None{}, Pix{0}}
    case Some{g}:
      +g2 = g
      Nx{Some{g2}, frame(g2)}

def Loop.pure.go(u: Unit, +g: Game, evs: List<Event>) -> Nx:
  match u:
    case Unit{}:
      Loop.nx(step_game(g, evs))

# the next frame: drop the frame before last, step the game, draw it
def Loop.pure(old: Image, +g: Game, evs: List<Event>) -> Nx:
  Loop.pure.go(Image.drop(old), g, evs)

def Loop.compute(old: Image, g: Game, evs: List<Event>) -> IO(Nx):
  IO.bind(Unit, Nx, IO.pure(Unit, Unit{}), u => IO.pure(Nx, Loop.pure(old, g, evs)))

# the next samples, and the game with the synthesizer's state after them
def Game.sound.go(pr: Z.Snd & List<&2, F32>, p: C.Park, ui: UI, wm: WM, ds: List<&2, U32>) -> Game & List<&2, F32>:
  (s2, xs) = pr
  (Game{p, ui, wm, s2, ds}, xs)

def Game.sound(g: Game) -> Game & List<&2, F32>:
  Game{p, ui, wm, snd, ds} = g
  Game.sound.go(Z.Snd.render(snd), p, ui, wm, ds)

def Game.heard(g: Game, +q: U32) -> Game:
  Game{p, ui, wm, snd, ds} = g
  Game{p, ui, wm, Z.Snd.heard(snd, q), ds}

def Loop.heard(r: Audio & U32, window: Window, g: Game, img: Image, events: List<Event>,
  shown: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  (au, q) = r
  rest(window, au, Game.heard(g, q), img, events, shown)

def Loop.play(pr: Game & List<&2, F32>, window: Window, au: Audio, img: Image, events: List<Event>,
  shown: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  (g, xs) = pr
  do IO<Unit>:
    r : Audio & U32 <- Z.Snd.write(au, xs)
    Loop.heard(r, window, g, img, events, shown, rest)

def Loop.again(m: Maybe<Game>, window: Window, au: Audio, shown: Image, events: List<Event>,
  img: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  match m:
    case None{}:
      Win.close(window)
    case Some{g}:
      Loop.play(Game.sound(g), window, au, img, events, shown, rest)

# Win.config: a new window size or pixel mode for the native window
def Win.config(window: Window, w: U32, h: U32, mode: U32) -> IO(Window):
  import "./win_frame.c"
  import "./win_config.js"

def Game.opt(g: Game) -> U32:
  Game{p, ui, wm, snd, ds} = g
  UI.opt(ui)

def Game.configured(g: Game) -> Game:
  Game{p, +ui, wm, snd, ds} = g
  Game{p, UI.with_opt(ui, (UI.opt(ui) .&. 4294950911 : U32)), wm, snd, ds}

def Loop.config.go(dirty: Bool, g: Game, window: Window, au: Audio, shown: Image, events: List<Event>,
  img: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  match dirty:
    case True{}:
      +g2 = g
      +o = Game.opt(g2)
      do IO<Unit>:
        w2 : Window <- Win.config(window, Opt.w(o), Opt.h(o), ((o >> 2n) .&. 1 : U32))
        Loop.again(Some{Game.configured(g2)}, w2, au, shown, events, img, rest)
    case False{}:
      Loop.again(Some{g}, window, au, shown, events, img, rest)

def Loop.config(m: Maybe<Game>, window: Window, au: Audio, shown: Image, events: List<Event>,
  img: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  match m:
    case None{}:
      Win.close(window)
    case Some{g}:
      +g2 = g
      Loop.config.go(Bool.not(U32.is_eq((Game.opt(g2) .&. 16384 : U32), 0)), g2, window, au, shown, events, img, rest)

def Loop.after.go(m: Maybe<Game>, window: Window, au: Audio, shown: Image, events: List<Event>,
  img: Image, rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit))
  -> IO(Unit):
  match m:
    case None{}:
      Win.close(window)
    case Some{g}:
      do IO<Unit>:
        now : Nat <- IO.now()
        m2 : Maybe<Game> <- Game.io_m(Game.clock_m(Some{g}, now))
        Loop.config(m2, window, au, shown, events, img, rest)

def Loop.after(shown: Window & Image & List<Event>, nx: Nx, au: Audio,
  rest: Window -> Audio -> Game -> Image -> List<Event> -> Image -> IO(Unit)) -> IO(Unit):
  (window, simg, events) = shown
  Nx{m, img} = nx
  Loop.after.go(m, window, au, simg, events, img, rest)

def Loop.go(fuel: Nat, window: Window, au: Audio, g: Game, img: Image, evs: List<Event>,
  old: Image) -> IO(Unit):
  match fuel:
    case 0n:
      Win.close(window)
    case 1n+f:
      do IO<Unit>:
        chan : Chan(Nx) <- IO.fork(Nx, Loop.compute(old, g, evs))
        shown : Window & Image & List<Event> <- Win.frame(window, img)
        nx : Nx <- IO.join(Nx, chan)
        Loop.after(shown, nx, au, w => a => g2 => i2 => e2 => o2 => Loop.go(f, w, a, g2, i2, e2, o2))

# PARK_OPT=n starts with those options (see UI opt), for testing
def env_opt(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Fail{e}:
      0
    case Done{s}:
      (arg_u32(s) .|. 16384 : U32)

def Game.with_opt(g: Game, +o: U32) -> Game:
  Game{p, ui, wm, snd, ds} = g
  Game{p, UI.with_opt(ui, o), wm, snd, ds}

def Loop.start(g: Game) -> IO(Unit):
  +g2 = g
  do IO<Unit>:
    window : Window <- IO.try(Window, Win.open("Eldergrove Faire", 1024, 640))
    au : Audio <- Z.Snd.open(22050)
    Loop.go(U32.to_nat(4294967295), window, au, g2, frame(g2), [], Pix{0})

def Loop.run(g: Game) -> IO(Unit):
  do IO<Unit>:
    env : Result<&1, &1, U32 & String, String> <- IO.get_env("PARK_OPT")
    Loop.start(Game.with_opt(g, (env_opt(env) .|. 262144 : U32)))

def is_arg(+args: +List<String>, s: String) -> Bool:
  match args:
    case []:
      False{}
    case a <> rest:
      String.eq(a, s)

def wav.write(path: String, +bytes: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, bytes)
    close_pair(r)

def run.live(wav: Bool, +args: +List<String>) -> IO(Unit):
  match wav:
    case True{}:
      wav.write(nth(args, 1), Z.Wav.file((arg_or(nth(args, 2), 10) * 22050 : U32)))
    case False{}:
      Loop.run(Bool.pick(Game, is_arg(args, "--live"),
        warm(crowd(Game.new(), arg_or(nth(args, 1), 0)), arg_nat(nth(args, 2))), Game.new()))

def run(go: Bool, +args: +List<String>) -> IO(Unit):
  match go:
    case True{}:
      shot(nth(args, 1), arg_nat(nth(args, 2)), arg_u32(nth(args, 3)),
        arg_or(nth(args, 4), 930), arg_or(nth(args, 5), 880), arg_or(nth(args, 6), 0), arg_or(nth(args, 7), 0))
    case False{}:
      run.live(is_arg(args, "--wav"), args)

def share(xs: List<String>) -> +List<String>:
  match xs:
    case []:
      []
    case +h <> t:
      h <> share(t)

# a save/load check on a real park: save to disk, load back, compare
def words_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{x, xs} Con{y, ys}:
      U32.is_eq(x, y) && words_eq(xs, ys)
    case _ _:
      False{}

def heading(+gs: +List<C.Guest>, +idx: U32) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, x, y, dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
      (sel(U32.is_eq(st, 0) && U32.is_eq(tgt, idx), 1, 0) + heading(rest, idx) : U32)

def ride_report(+rs: +List<C.Ride>, +gs: +List<C.Guest>, +i: U32) -> String:
  match rs:
    case []:
      ""
    case r <> rest:
      " [" ++ U32.show(i) ++ " k" ++ U32.show(C.Ride.kind(r)) ++ " open" ++ Bool.show(C.Ride.is_open(r))
        ++ " riding " ++ U32.show(riders(gs, i)) ++ " heading " ++ U32.show(heading(gs, i))
        ++ " ph" ++ U32.show(C.Ride.ph(r)) ++ " q" ++ U32.show(C.Ride.qlen(r)) ++ " total " ++ U32.show(C.Ride.total(r)) ++ " rel " ++ U32.show(C.Wear.rel(C.Ride.wear(r)))
        ++ ride_state(r) ++ "]"
        ++ ride_report(rest, gs, (i + 1 : U32))

def savetest.cmp(m: Maybe<&2, C.Park>, +p: C.Park) -> String:
  match m:
    case None{}:
      "load FAILED"
    case Some{q}:
      Bool.pick(String, words_eq(S.save(q), S.save(p)), "round trip OK: "
        ++ U32.show(C.len32(U32, S.save(p))) ++ " words, "
        ++ U32.show(C.len32(C.Guest, C.Park.guests(p))) ++ " guests; riding now: carousel "
        ++ U32.show(riders(C.Park.guests(p), 0)) ++ ", spire " ++ U32.show(riders(C.Park.guests(p), 1))
        ++ ", gold " ++ U32.show(C.Park.cash(p)) ++ track_report(C.Park.track(p), 0) ++ ride_report(C.Park.rides(p), C.Park.guests(p), 0),
        "round trip MISMATCH")

def savetest.res(res: Result<&1, &1, U32 & String, List<&2, U32>>, +p: C.Park) -> String:
  match res:
    case Fail{e}:
      "read FAILED"
    case Done{bs}:
      savetest.cmp(S.Load.file(bs), p)

def staff_list(+ss: +List<C.Staff>) -> String:
  match ss:
    case []:
      ""
    case s <> rest:
      C.Staff{id, +x, +y, dir, +kind, +st, +tgt, tmr, zone, look} = s
      " k" ++ U32.show(kind) ++ "@" ++ U32.show(x) ++ "," ++ U32.show(y) ++ " st" ++ U32.show(st) ++ staff_list(rest)

# smashed furniture on the map
def smashed(+n: Nat, +k: U32, +q: C.Q, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      +t = C.Land.get(q, (k >> 6n : U32), (k .&. 63 : U32))
      smashed(m, (k + 1 : U32), q, (acc + sel(U32.is_eq(C.Tile.obj(t), 1) && Bool.not(U32.is_eq((C.Tile.a(t) .&. 256 : U32), 0)), 1, 0) : U32))

# the litter and sickness the paved tiles count (litter | sick << 16)
def mess_sum(+n: Nat, +k: U32, +q: C.Q, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      +t = C.Land.get(q, (k >> 6n : U32), (k .&. 63 : U32))
      +o = C.Tile.obj(t)
      +b = C.Tile.b(t)
      +paved = U32.is_eq(o, 1) || U32.is_eq(o, 5) || U32.is_eq(o, 7)
      mess_sum(m, (k + 1 : U32), q, (acc + sel(paved, ((b .&. 255) + (((b >> 8n) .&. 255) << 16n) : U32), 0) : U32))

def max_na(+gs: +List<C.Guest>) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, +na, ha, lk, mind, bl} = g
      U32.max(na, max_na(rest))

def max_bl(+gs: +List<C.Guest>) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, +bl} = g
      U32.max(bl, max_bl(rest))

def minds9(+gs: +List<C.Guest>) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, +mind, bl} = g
      (sel(U32.is_eq(C.Mind.code(mind), 9), 1, 0) + minds9(rest) : U32)

# guests by state: walking | riding << 8 | leaving << 16 | resting << 24 (each to 255)
def states(+gs: +List<C.Guest>) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, x, y, dir, +st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
      (sel(U32.is_eq(st, 4), 16777216, sel(U32.is_eq(st, 2), 65536, sel(U32.is_eq(st, 1), 256, sel(U32.is_eq(st, 0), 1, 0)))) + states(rest) : U32)

def savetest.read(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, +p: C.Park)
  -> IO(Unit):
  (f, res) = r
  +ms = mess_sum(4096n, 0, C.Park.map(p), 0)
  do IO<Unit>:
    File.close(f)
    IO.print(savetest.res(res, p))
    IO.print("mess " ++ U32.show(C.len32(U32, C.Park.mess(p))) ++ ", on tiles: litter " ++ U32.show((ms .&. 65535 : U32))
      ++ ", sick " ++ U32.show((ms >> 16n : U32)) ++ ", filthy minds " ++ U32.show(minds9(C.Park.guests(p))))
    IO.print("states (walk ride leave rest) " ++ U32.show((states(C.Park.guests(p)) .&. 255 : U32)) ++ " "
      ++ U32.show(((states(C.Park.guests(p)) >> 8n) .&. 255 : U32)) ++ " " ++ U32.show(((states(C.Park.guests(p)) >> 16n) .&. 255 : U32))
      ++ " " ++ U32.show((states(C.Park.guests(p)) >> 24n : U32)) ++ ", happy " ++ U32.show(happy_avg(C.Park.guests(p), 0, 0))
      ++ ", peak nausea " ++ U32.show(max_na(C.Park.guests(p))) ++ ", peak bladder " ++ U32.show(max_bl(C.Park.guests(p))))
    IO.print("staff " ++ U32.show(C.len32(C.Staff, C.Park.staff(p))) ++ ", wages " ++ U32.show(C.Staff.wages(C.Park.staff(p)))
      ++ ", smashed " ++ U32.show(smashed(4096n, 0, C.Park.map(p), 0)) ++ staff_list(C.Park.staff(p)))

def savetest.go(+p: C.Park) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open("savetest.sav", "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, S.Save.file(p))
    close_pair(w)
    g : File <- IO.try(File, File.open("savetest.sav", "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(g, 16000000)
    savetest.read(r, p)

def start.test(test: Bool, +args: +List<String>) -> IO(Unit):
  match test:
    case True{}:
      savetest.go(Game.park(warm(Game.with(Game.new(), loop2_acts()), arg_nat(nth(args, 1)))))
    case False{}:
      run(is_shot(args), args)

# UI test: feed clicks and keys through step_game and report what changed.
# The default camera puts the carousel's tile at screen (398, 136); its
# window opens at (312, 106), so price + is at (427, 136).
def ui.step(g: Game, es: List<Event>) -> Game:
  +g2 = g
  Maybe.default(&1, Game, step_game(g2, es), g2)

def ui.click(+x: U32, +y: U32, +b: U32) -> List<Event>:
  [Mouse{(x * 2 : U32), (y * 2 : U32), b, True{}}, Mouse{(x * 2 : U32), (y * 2 : U32), b, False{}}]

def ui.report(g: Game) -> String:
  Game{+p, +ui, +wm, snd, ds} = g
  +r0 = C.Rides.get(C.Park.rides(p), 0)
  "windows " ++ U32.show(C.len32(Win, WM.wins(wm))) ++ " (front kind " ++ U32.show(Win.kind(Wins.get(WM.wins(wm), 0))) ++ "), carousel price " ++ U32.show(C.Ride.price(r0))
    ++ ", open " ++ U32.show(C.Ride.open_flag(r0)) ++ ", max wait " ++ U32.show(C.Ride.wmax(r0))
    ++ ", fee " ++ U32.show(C.Fin.fee(C.Park.fin(p))) ++ ", loan " ++ U32.show(C.Fin.loan(C.Park.fin(p)))
    ++ ", gold " ++ U32.show(C.Park.cash(p)) ++ ", tool " ++ U32.show(UI.tool(ui)) ++ " (tab " ++ U32.show(UI.cat(UI.var(ui))) ++ ")"
    ++ ", scenario " ++ U32.show(Scn.of(p)) ++ ", menu " ++ Bool.show(Menu.on(ui))
    ++ ", follow " ++ U32.show(UI.fol(ui)) ++ " camera " ++ U32.show(UI.cx(ui)) ++ "," ++ U32.show(UI.cy(ui))
    ++ ", coasters " ++ U32.show(C.len32(C.Track, C.Park.track(p))) ++ " (last: "
    ++ U32.show(C.len32(C.Piece, C.Track.pieces(C.Tracks.get(C.Park.track(p), (C.len32(C.Track, C.Park.track(p)) - 1 : U32))))) ++ " pieces, settings "
    ++ U32.show(C.Track.cfg(C.Tracks.get(C.Park.track(p), (C.len32(C.Track, C.Park.track(p)) - 1 : U32)))) ++ ")"

# each stage: what it did, then the game after it
def ui.s1(g: Game) -> Game:
  ui.step(g, ui.click(398, 136, 0))

def ui.s2(g: Game) -> Game:
  ui.step(ui.step(g, ui.click(427, 136, 0)), ui.click(427, 136, 0))

def ui.s3(g: Game) -> Game:
  ui.step(ui.step(g, ui.click(318, 124, 0)), ui.click(427, 172, 0))

def ui.s4(g: Game) -> Game:
  ui.step(g, [Key{27, True{}}])

# F opens the finances window at (140, 30): BORROW 1000 at (240, 155)
def ui.s5(g: Game) -> Game:
  ui.step(ui.step(g, [Key{102, True{}}]), ui.click(245, 158, 0))

# the PARK button, then entry fee + twice at (150 + 124, 40 + 40)
def ui.s6(g: Game) -> Game:
  ui.step(ui.step(ui.step(g, ui.click(470, 297, 0)), ui.click(278, 84, 0)), ui.click(278, 84, 0))

# where the first walking guest on screen stands (x << 16 | y, screen px)
def ui.guest_at(+gs: +List<C.Guest>, +q: C.Q, +cx: U32, +cy: U32) -> U32:
  match gs:
    case []:
      0
    case g <> rest:
      C.Guest{id, +x, +y, dir, +st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
      +h = C.Land.h(q, (x >> 4n : U32), (y >> 4n : U32))
      +sx = ((1280 + x) - (y + cx) : U32)
      +sy = ((512 + ((x + y) >> 1n)) - (8 * h + cy + 6) : U32)
      +ok = U32.is_eq(st, 0) && (sx > 20 : U32) && (sx < 490 : U32) && (sy > 20 : U32) && (sy < 280 : U32)
      sel(ok, ((sx << 16n) .|. sy : U32), ui.guest_at(rest, q, cx, cy))

# clicking the first walking guest on screen opens their window
def ui.s7(g: Game) -> Game:
  +g2 = g
  +pos = ui.guest_at(C.Park.guests(Game.park(g2)), C.Park.map(Game.park(g2)), 930, 880)
  ui.step(g2, ui.click((pos >> 16n : U32), (pos .&. 65535 : U32), 0))

# the GENTLE RIDES tab, then its second tool (a ride: tool codes past 20
# used to be read as tabs)
def ui.s8(g: Game) -> Game:
  ui.step(ui.step(g, ui.click(143, 305, 0)), ui.click(247, 305, 0))

# key 1 twice: the paths tab's path, then its queue line
def ui.s9(g: Game) -> Game:
  ui.step(g, [Key{49, True{}}, Key{49, False{}}, Key{49, True{}}, Key{49, False{}}])

def Game.look(g: Game, +tool: U32, +cx: U32, +cy: U32) -> Game:
  Game{p, ui, wm, snd, ds} = g
  Game{p, UI.with_tool(UI.cam(ui, cx, cy), tool), wm, snd, ds}

# a new coaster on the cleared patch: its station tile (40, 56) sits at
# (256, 150) on screen with this camera; its construction window opens
def ui.s10(g: Game) -> Game:
  ui.step(Game.look(Game.with(g, clear2_acts()), 10, 768, 1122), ui.click(256, 158, 0))

# T lays a straight, the TURN RIGHT button a turn, Backspace takes it off;
# then the FLYER button
def ui.s11(g: Game) -> Game:
  ui.step(ui.step(ui.step(ui.step(g, [Key{116, True{}}, Key{116, False{}}]), ui.click(144, 60, 0)), [Key{8, True{}}, Key{8, False{}}]),
    ui.click(200, 110, 0))

# K opens the staff window at (160, 50); FOLLOW on the Brownies row, then
# two more steps as the camera follows
def ui.s12(g: Game) -> Game:
  ui.step(ui.step(ui.step(g, [Key{107, True{}}, Key{107, False{}}]), ui.click(346, 78, 0)), [])

# W (a camera key) lets go
def ui.s13(g: Game) -> Game:
  ui.step(ui.step(g, [Key{119, True{}}]), [Key{119, False{}}])

# the main menu, then Misty Hollow
def ui.s14(g: Game) -> Game:
  ui.step(Game.with_opt(g, 262144), ui.click(200, 108, 0))

def ui.next(+k: U32, g: Game) -> Game:
  match k:
    case 1:
      ui.s2(g)
    case 2:
      ui.s3(g)
    case 3:
      ui.s4(g)
    case 4:
      ui.s5(g)
    case 5:
      ui.s6(g)
    case 6:
      ui.s7(warm(ui.step(g, [Key{27, True{}}, Key{27, True{}}]), 1500n))
    case 7:
      ui.s8(ui.step(g, [Key{27, True{}}]))
    case 8:
      ui.s9(g)
    case 9:
      ui.s10(g)
    case 10:
      ui.s11(g)
    case 11:
      ui.s12(g)
    case 12:
      ui.s13(g)
    case 13:
      ui.s14(g)
    case _:
      g

# stages: 1 inspect the carousel, 2 price + twice, 3 close it and max wait +,
# 4 Esc, 5 F and borrow, 6 PARK and entry fee + twice, 7 a guest's window,
# 8 the rides tab and the coaster tool, 9 key 1 twice, 10 a new coaster,
# 11 its construction window, 12 follow a Brownie, 13 let go, 14 the main menu
def ui.run(+n: Nat, +k: U32, +g: Game) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      do IO<Unit>:
        IO.print("after stage " ++ U32.show(k) ++ ": " ++ ui.report(g))
        ui.run(m, (k + 1 : U32), ui.next(k, g))

def ui.test() -> IO(Unit):
  ui.run(14n, 1, ui.s1(Game.new()))

# --people out.ppm: every folk (columns) as adults facing front and back,
# as children, and in the three outfits, at close zoom, to check the art
def people.dr(+n: Nat, +k: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+m:
      +c = (k .&. 7 : U32)
      +rw = (k >> 3n : U32)
      +look = (c .|. (((c + rw) .&. 7) << 4n) .|. (((c + rw) .&. 3) << 8n) .|. 3072
        .|. sel(U32.is_eq(rw, 1), 12288, 0) .|. sel(U32.is_eq(rw, 2), 8, 0)
        .|. sel(U32.is_eq(rw, 3), ((((c % 3) + 1) << 14n) : U32), 0) : U32)
      people.dr(m, (k + 1 : U32), DGuest{(B() + 14 + c * 30 : U32), (B() + 34 + rw * 36 : U32), look, 0} <> acc)

def rides.dr(+n: Nat, +k: U32, +ks: +List<U32>, +tm: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n ks:
    case 1n+m Con{kind, rest}:
      +col = (k .&. 3 : U32)
      +rw = (k >> 2n : U32)
      +ra = (137 .|. (178 << 8n) .|. (212 << 16n) .|. (231 << 24n) : U32)
      +rb = (140 .|. (190 << 8n) .|. (163 << 16n) .|. (254 << 24n) : U32)
      rides.dr(m, (k + 1 : U32), rest, tm,
        DRide{(B() + 64 + col * 128 : U32), (B() + 118 + rw * 150 : U32), kind, ra, rb, ((1 << 16n) .|. tm : U32), 0} <> acc)
    case _ _:
      acc

def rides_shot(path: String, +tm: U32) -> IO(Unit):
  shot.write(path, bytes(163840n, R.frame(rides.dr(8n, 0, [10, 11, 15, 16, 12, 13, 14, 17], tm, [DRect{B(), B(), 512, 320, 5214768}]), (tm .&. 65535 : U32)), 163839, []))

# every track piece in its four headings, raised a level: a sheet for
# checking the art (`./park --pieces out.ppm`)
def pieces.kind(+i: U32) -> U32:
  sel((i < 7 : U32), i, (i + 2 : U32))

def pieces.dr(+n: Nat, +i: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+m:
      +x = (B() + 36 + (i .&. 7) * 62 : U32)
      +y = (B() + 40 + (i >> 3n) * 50 : U32)
      pieces.dr(m, (i + 1 : U32), DTrack{x, y, (pieces.kind((i >> 2n : U32)) + (i .&. 3) * 16 : U32), 1} <> acc)

# each coaster type's front car on a straight in its four headings, with
# riders (`./park --cars out.ppm`)
def cars.dr(+n: Nat, +i: U32, +acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+m:
      +ty = (i >> 2n : U32)
      +d = (i .&. 3 : U32)
      +x = (B() + 60 + d * 110 : U32)
      +y = (B() + 60 + ty * 90 : U32)
      +rd = (137 .|. (178 << 8n) : U32)
      cars.dr(m, (i + 1 : U32), DCar{x, (y + sel(U32.is_eq(ty, 2), 13, 0) : U32), d, (1 .|. (ty << 1n) : U32), rd}
        <> DTrack{x, y, (d * 16 + (ty << 12n) : U32), 1} <> acc)

def cars_shot(path: String) -> IO(Unit):
  shot.write(path, bytes(163840n, R.frame(cars.dr(12n, 0, [DRect{B(), B(), 512, 320, 5214768}]), 64), 163839, []))

def pieces_shot(path: String) -> IO(Unit):
  shot.write(path, bytes(163840n, R.frame(pieces.dr(48n, 0, [DRect{B(), B(), 512, 320, 5214768}]), 64), 163839, []))

def people_shot(path: String) -> IO(Unit):
  shot.write(path, bytes(163840n, R.frame(people.dr(32n, 0, [DRect{B(), B(), 512, 320, 5214768}]), 1073741824), 163839, []))

def start.go(bench: Bool, +args: +List<String>) -> IO(Unit):
  match bench:
    case True{}:
      bench.go(warm(crowd(Game.new(), arg_or(nth(args, 4), 0)), arg_nat(nth(args, 2))),
        arg_nat(nth(args, 1)), arg_or(nth(args, 3), 0))
    case False{}:
      Bool.pick(IO(Unit), is_arg(args, "--uitest"), ui.test(),
        Bool.pick(IO(Unit), is_arg(args, "--people"), people_shot(nth(args, 1)),
        Bool.pick(IO(Unit), is_arg(args, "--pieces"), pieces_shot(nth(args, 1)),
        Bool.pick(IO(Unit), is_arg(args, "--cars"), cars_shot(nth(args, 1)),
        Bool.pick(IO(Unit), is_arg(args, "--coastertest"), ctest.go(),
        Bool.pick(IO(Unit), is_arg(args, "--bridgetest"), btest.go(),
        Bool.pick(IO(Unit), is_arg(args, "--rides"), rides_shot(nth(args, 1), arg_u32(nth(args, 2))),
        Bool.pick(IO(Unit), is_arg(args, "--scen"), scen.run(arg_nat(nth(args, 2)), Scn.park(arg_u32(nth(args, 1)))),
          start.test(is_arg(args, "--savetest"), args)))))))))

def start(+args: +List<String>) -> IO(Unit):
  start.go(is_bench(args), args)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(share(args))
