# Eldergrove Faire -- the art. Every pixel is painted by code: each shade
# function answers the colour of one pixel of one thing, or TR() where the
# thing is see-through. Coordinates are logical pixels (2x2 screen pixels).
import Base
import ./font.bend as F

# Helpers
# -------

def sel(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def TR() -> U32:
  16777216

def opaque(+c: U32) -> Bool:
  Bool.not(U32.is_eq(c, 16777216))

# first opaque of two layers
def over(+a: U32, +b: U32) -> U32:
  sel(opaque(a), a, b)

def hash(+x: U32, +y: U32) -> U32:
  +h = ((x * 374761393) + (y * 668265263) + 1442695041 : U32)
  +h2 = ((h .^. (h >> 13n)) * 1274126177 : U32)
  (h2 .^. (h2 >> 16n) : U32)

def neg(+a: U32) -> Bool:
  (a >= 2147483648 : U32)

def sabs(+a: U32) -> U32:
  sel(neg(a), (0 - a : U32), a)

# signed a < b for wrapped values
def slt(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

def sle(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) <= (b .^. 2147483648) : U32)

def between(+a: U32, +lo: U32, +hi: U32) -> Bool:
  sle(lo, a) && sle(a, hi)

# scale a colour by k/256
def shade(+c: U32, +k: U32) -> U32:
  +r = U32.min((((c >> 16n) .&. 255) * k >> 8n : U32), 255)
  +g = U32.min((((c >> 8n) .&. 255) * k >> 8n : U32), 255)
  +b = U32.min((((c .&. 255) * k) >> 8n : U32), 255)
  ((r << 16n) .|. (g << 8n) .|. b : U32)

# inside the ellipse (dx/rx)^2 + (dy/ry)^2 <= 1 (dx, dy signed)
def ell(+dx: U32, +dy: U32, +rx: U32, +ry: U32) -> Bool:
  ((dx * dx * ry * ry + dy * dy * rx * rx) <= (rx * rx * ry * ry) : U32)

def div3(+n: U32) -> U32:
  ((n * 43691) >> 17n : U32)

# a smooth-ish wave: 0..64..0 over a period of 256
def tri(+a: U32) -> U32:
  +m = (a .&. 255 : U32)
  sel((m < 128 : U32), (m >> 1n : U32), ((255 - m) >> 1n : U32))

# sine-like in -r..r (as wrapped) for an angle in 0..255
def wsin(+a: U32, +r: U32) -> U32:
  +m = (a .&. 127 : U32)
  +p = ((m * (128 - m) * r) >> 12n : U32)
  sel(((a .&. 128) > 0 : U32), (0 - p : U32), p)

def wcos(+a: U32, +r: U32) -> U32:
  wsin((a + 64 : U32), r)

# tile-local iso coordinates of screen offset (X, Y2 = 2*dy): u, v in 0..16
def iso_u(+X: U32, +Y: U32) -> U32:
  +s = (X + Y : U32)
  ((s >> 1n) .|. (s .&. 2147483648) : U32)

def iso_v(+X: U32, +Y: U32) -> U32:
  +s = (Y - X : U32)
  ((s >> 1n) .|. (s .&. 2147483648) : U32)

# Terrain
# -------

# a tuft of long grass in a 4 x 4 cell (x, y: position in the cell)
def Art.tuft(on: Bool, +x: U32, +y: U32) -> U32:
  match on:
    case True{}:
      +lite = U32.is_eq(y, 0) && U32.is_eq(x, 1) || U32.is_eq(y, 1) && (U32.is_eq(x, 0) || U32.is_eq(x, 2))
      +mid = U32.is_eq(y, 1) && U32.is_eq(x, 1) || U32.is_eq(y, 2) && (x < 3 : U32)
      +dark = U32.is_eq(y, 3) && (U32.is_eq(x, 1) || U32.is_eq(x, 2))
      sel(lite, 8047936, sel(mid, 5411896, sel(dark, 2980914, TR())))
    case False{}:
      TR()

def Art.grass(+n: U32, +edge: U32, +tip: Bool) -> U32:
  +f = (n .&. 255 : U32)
  +base = sel((f < 90 : U32), 5150266, sel((f < 200 : U32), 4626999, 5875263))
  +m = (n .&. 1023 : U32)
  +bloom = sel(U32.is_eq(m, 7), 15895224, sel(U32.is_eq(m, 19), 16179290,
    sel(U32.is_eq(m, 31), 16053480, sel(U32.is_eq(m, 43), 9086207, TR()))))
  +flower = sel(opaque(bloom), sel(tip, bloom, 3707946), TR())
  +blade = U32.is_eq((n .&. 28 : U32), 12) && ((n >> 10n .&. 3 : U32) < 3 : U32)
  over(flower, shade(sel(blade, sel(tip, 7324480, 3509046), base), edge))

def Art.wild(+n: U32, +edge: U32) -> U32:
  +f = (n .&. 255 : U32)
  +base = sel((f < 100 : U32), 3104300, sel((f < 210 : U32), 3828531, 2640419))
  +leaf = sel(U32.is_eq((f .&. 31 : U32), 5), 7031338, TR())
  over(leaf, shade(base, edge))

def Art.dirt(+n: U32, +edge: U32) -> U32:
  +f = (n .&. 255 : U32)
  shade(sel((f < 120 : U32), 10124874, sel((f < 220 : U32), 9138758, 11177304)),
    edge)

def Art.water(+wx: U32, +wy: U32, +t: U32) -> U32:
  +w1 = (((wx + (wy * 2) + (t >> 2n)) .&. 31) : U32)
  +w2 = (((wx * 3 + (0 - wy) * 2 + (t >> 3n)) .&. 63) : U32)
  +spark = U32.is_eq((hash((wx >> 1n : U32), (wy + (t >> 4n) : U32)) .&. 511 : U32), 3)
  sel(spark, 16119285, sel(U32.is_eq(w1, 0) || U32.is_eq(w2, 0), 7320038,
    sel((w1 < 12 : U32), 3108784, 2645916)))

# cobblestones laid on the iso grid
def Art.cobble(+u: U32, +v: U32, +seed: U32) -> U32:
  +off = sel(U32.is_eq(((v >> 2n) .&. 1 : U32), 1), 2, 0)
  +uu = (u + off : U32)
  +mortar = U32.is_eq((uu .&. 3 : U32), 0) || U32.is_eq((v .&. 3 : U32), 0)
  +c = (hash(((uu >> 2n) + seed * 7 : U32), ((v >> 2n) + seed : U32)) .&. 3 : U32)
  sel(mortar, 8155746, sel(U32.is_eq(c, 0), 12168597, sel(U32.is_eq(c, 1),
    11050116, sel(U32.is_eq(c, 2), 13155750, 12037249))))

def Art.cliff(+d: U32, +px: U32, +left: Bool, +wild: Bool) -> U32:
  +row = (d >> 2n : U32)
  +mortar = U32.is_eq((d .&. 3 : U32), 0)
    || U32.is_eq(((px + row * 3) .&. 7 : U32), 0)
  +stone = sel(wild, 7031342, 9076856)
  +c = sel(mortar, shade(stone, 170), stone)
  +turf = sel(wild, 3104300, 4626999)
  +root = U32.is_eq(d, 2) && ((((px * 5) + 3) .&. 7 : U32) < 2 : U32)
    || U32.is_eq(d, 3) && U32.is_eq((((px * 5) + 3) .&. 15 : U32), 0)
  sel(U32.is_eq(d, 0), shade(turf, 300), sel(U32.is_eq(d, 1), shade(turf, 150),
    sel(root, shade(turf, 120), sel(left, c, shade(c, 190)))))

# the ground block: top face (terrain, path, hover outline) and cliff faces
# dl/dr px down. wx, wy: world-screen position of the top vertex. Each stage
# dispatches with a match, so a pixel only pays for the branch it takes.
# Day and night, rain: a day lasts 2048 ticks (dusk from 1152, night from
# 1408, dawn from 1792); some days rain (the same test the park uses).
# Colours marked with bit 25 glow: night and rain leave them bright.
def E(+c: U32) -> U32:
  (c .|. 33554432 : U32)

def Art.night(+t: U32) -> U32:
  +p = (t .&. 2047 : U32)
  sel((p < 1152 : U32), 0, sel((p < 1408 : U32), (p - 1152 : U32), sel((p < 1792 : U32), 256, (2047 - p : U32))))

def Art.rain(+t: U32) -> Bool:
  ((hash((t >> 11n : U32), 99) .&. 7) < 2 : U32)

def Light.tint(+c: U32, +kr: U32, +kg: U32, +kb: U32) -> U32:
  (((((c >> 16n) .&. 255) * kr) >> 8n << 16n) .|. (((((c >> 8n) .&. 255) * kg) >> 8n) << 8n) .|. (((c .&. 255) * kb) >> 8n) : U32)

def Light.drop(+sx: U32, +sy: U32, +t: U32) -> Bool:
  +fall = (sy - t * 7 : U32)
  +col = (sx + (fall >> 2n) : U32)
  ((fall .&. 7) < 3 : U32) && U32.is_eq((hash(col, (fall >> 3n : U32)) .&. 31 : U32), 0)

def Light.go(on: Bool, +c: U32, +n: U32, +wet: Bool, +t: U32, +sx: U32, +sy: U32) -> U32:
  match on:
    case True{}:
      +glow = Bool.not(U32.is_eq((c .&. 33554432 : U32), 0))
      +k = sel(wet, 205, 256)
      +kr = (((256 - ((n * 160) >> 8n)) * k) >> 8n : U32)
      +kg = (((256 - ((n * 140) >> 8n)) * k) >> 8n : U32)
      +kb = (((256 - ((n * 70) >> 8n)) * k) >> 8n : U32)
      sel(wet && Light.drop(sx, sy, t), sel(Bool.not(U32.is_eq(n, 0)), 6320776, 11587808),
        sel(glow, (c .&. 16777215 : U32), Light.tint(c, kr, kg, kb)))
    case False{}:
      (c .&. 16777215 : U32)

# a world pixel under the sky of the moment
def Light.apply(+c: U32, +t: U32, +sx: U32, +sy: U32) -> U32:
  +n = Art.night(t)
  +wet = Art.rain(t)
  sel(opaque(c), Light.go(Bool.not(U32.is_eq(n, 0)) || wet, c, n, wet, t, sx, sy), c)

def Art.ground(+ter: U32, +n: U32, +edge: U32, +wx: U32, +wy: U32, +t: U32)
  -> U32:
  match ter:
    case 2:
      Art.water(wx, wy, t)
    case 1:
      Art.dirt(n, edge)
    case 4:
      Art.wild(n, edge)
    case _:
      +tuft = U32.is_eq((hash((wx >> 2n : U32), (wy >> 2n : U32)) .&. 31 : U32), 0)
      +fly = (Art.night(t) > 160 : U32) && U32.is_eq((hash(((wx >> 1n) + (t >> 5n) * 7 : U32), (wy >> 1n : U32)) .&. 1023 : U32), 0)
      sel(fly, E(13168752), over(Art.tuft(tuft, (wx .&. 3 : U32), (wy .&. 3 : U32)), Art.grass(n, edge, U32.is_eq((wy .&. 1 : U32), 0))))

def Art.flag(+u: U32, +v: U32, +seed: U32) -> U32:
  +off = sel(U32.is_eq(((v >> 3n) .&. 1 : U32), 1), 4, 0)
  +uu = (u + off : U32)
  +joint = U32.is_eq((uu .&. 7 : U32), 0) || U32.is_eq((v .&. 7 : U32), 0)
  +c = (hash(((uu >> 3n) + seed * 5 : U32), ((v >> 3n) + seed : U32)) .&. 3 : U32)
  sel(joint, 6970184, sel(U32.is_eq(c, 0), 10125936, sel(U32.is_eq(c, 1), 9468520, 10783352)))

def Art.open_edge(+nb: U32, +u: U32, +v: U32, +w: U32) -> Bool:
  (U32.is_eq((nb .&. 1 : U32), 0) && (u < w : U32)) || (U32.is_eq((nb .&. 2 : U32), 0) && (u + w > 15 : U32))
    || (U32.is_eq((nb .&. 4 : U32), 0) && (v < w : U32)) || (U32.is_eq((nb .&. 8 : U32), 0) && (v + w > 15 : U32))

def Art.planks(+u: U32, +v: U32, +nb: U32) -> U32:
  +along_u = Bool.not(U32.is_eq((nb .&. 3 : U32), 0)) || U32.is_eq((nb .&. 12 : U32), 0)
  +a = sel(along_u, v, u)
  +gap = U32.is_eq((sel(along_u, u, v) .&. 3 : U32), 3)
  +grain = U32.is_eq(((a * 7 + sel(along_u, u, v)) .&. 7 : U32), 0)
  sel(gap, 4221152, sel(grain, 8014378, 10119226))

def Art.paving(+obj: U32, +u: U32, +v: U32, +seed: U32, +nb: U32) -> U32:
  match obj:
    case 7:
      Art.flag(u, v, seed)
    case 8:
      Art.planks(u, v, nb)
    case _:
      sel(Art.open_edge(nb, u, v, 2), shade(Art.cobble(u, v, seed), 176), Art.cobble(u, v, seed))

# foam where water meets land (the edges whose neighbour is not water)
def Art.foam(+nb: U32, +u: U32, +v: U32, +t: U32, +c: U32) -> U32:
  +band = Art.open_edge(nb, u, v, 2)
  +edge = Art.open_edge(nb, u, v, 1)
  +ripple = U32.is_eq((((u + v + (t >> 3n)) >> 1n) .&. 1 : U32), 0)
  sel(edge, 14676463, sel(band && ripple, 10406879, c))

def Art.mess.go(on: Bool, +u: U32, +v: U32, +seed: U32, +nb: U32) -> U32:
  match on:
    case True{}:
      +cu = (u >> 2n : U32)
      +cv = (v >> 2n : U32)
      +hh = hash((cu * 4 + cv + seed * 16 : U32), (seed + 77 : U32))
      +lit = ((nb >> 8n) .&. 15 : U32)
      +sick = ((nb >> 12n) .&. 7 : U32)
      +fu = (u .&. 3 : U32)
      +fv = (v .&. 3 : U32)
      +ox = ((hh >> 4n) .&. 1 : U32)
      +oy = ((hh >> 5n) .&. 1 : U32)
      +scrap = ((hh .&. 15) < lit : U32) && between(fv, oy, (oy + 1 : U32)) && between(fu, ox, (ox + 1 : U32))
      +puddle = (((hh >> 12n) .&. 15) < sick * 2 : U32) && (fu < 3 : U32) && (fv < 3 : U32)
        && (U32.is_eq(fu, 1) || U32.is_eq(fv, 1))
      +pc = sel(U32.is_eq(fu, 1) && U32.is_eq(fv, 1), 12645472, 9412672)
      +kind = ((hh >> 8n) .&. 3 : U32)
      +sc = sel(U32.is_eq(kind, 0), 15263976, sel(U32.is_eq(kind, 1), 14207128,
        sel(U32.is_eq(kind, 2), 11552320, 5275848)))
      sel(puddle, pc, sel(scrap, sel(U32.is_eq(fv, oy), sc, shade(sc, 170)), TR()))
    case False{}:
      TR()

# Path furniture, drawn with the tile (x, y: its top vertex). A bin stands
# by the right-hand back edge, a bench along the left-hand back edge, a
# lamp at the back corner.
def Art.surface(paved: Bool, +ter: U32, +u: U32, +v: U32, +wx: U32, +wy: U32,
  +t: U32, +obj: U32, +nb: U32) -> U32:
  match paved:
    case True{}:
      +seed = ((wx - u + v) >> 4n : U32)
      over(Art.mess.go(Bool.not(U32.is_eq(((nb >> 8n) .&. 127 : U32), 0)), u, v, seed, nb),
        Art.paving(sel(U32.is_eq(ter, 2) && U32.is_eq(obj, 1), 8, obj), u, v, seed, nb))
    case False{}:
      +n = hash(wx, (wy >> 1n : U32))
      +edge = sel((u < 1 : U32) || (v < 1 : U32), 272, sel((u > 14 : U32) || (v > 14 : U32), 236, 256))
      +g = Art.ground(ter, n, edge, wx, wy, t)
      sel(U32.is_eq(ter, 2), Art.foam(nb, u, v, t, g), g)

def Art.top(outline: Bool, +ter: U32, +obj: U32, +u: U32, +v: U32, +wx: U32,
  +wy: U32, +t: U32, +nb: U32) -> U32:
  match outline:
    case True{}:
      16769126
    case False{}:
      Art.surface(U32.is_eq(obj, 1) || U32.is_eq(obj, 5) || U32.is_eq(obj, 7), ter, u, v, wx, wy, t, obj, nb)

# a flight of four steps down a face (d: rows below its top edge)
def Art.stairs(+d: U32, +left: Bool) -> U32:
  +tread = U32.is_eq((d .&. 1 : U32), 0)
  +c = sel(tread, 13287330, 9340018)
  sel(left, c, shade(c, 200))

def Art.face(stairs: Bool, +d: U32, +px: U32, +left: Bool, +wild: Bool) -> U32:
  match stairs:
    case True{}:
      Art.stairs(d, left)
    case False{}:
      Art.cliff(d, px, left, wild)

def Art.faces(onl: Bool, onr: Bool, +dl: U32, +dr: U32, +le: U32, +re: U32,
  +px: U32, +py: U32, +wild: Bool, +nb: U32) -> U32:
  match onl onr:
    case True{} _:
      Art.face(Bool.not(U32.is_eq((nb .&. 1048576 : U32), 0)), (py - le : U32), px, True{}, wild)
    case False{} True{}:
      Art.face(Bool.not(U32.is_eq((nb .&. 2097152 : U32), 0)), (py - re : U32), px, False{}, wild)
    case False{} False{}:
      TR()

def Art.block.go(top: Bool, +x: U32, +y: U32, +dl: U32, +dr: U32, +ter: U32,
  +obj: U32, +hov: U32, +wx: U32, +wy: U32, +t: U32, +px: U32, +py: U32,
  +u: U32, +v: U32, +nb: U32) -> U32:
  match top:
    case True{}:
      +outline = U32.is_eq(hov, 1) && ((u < 1 : U32) || (v < 1 : U32) || (u > 14 : U32) || (v > 14 : U32))
      Art.top(outline, ter, obj, u, v, (wx + (px - x) : U32), (wy + (py - y) : U32), t, nb)
    case False{}:
      +lx = (px - (x - 16) : U32)
      +le = (y + 8 + (lx >> 1n) : U32)
      +rx = (px - x : U32)
      +re = (y + 16 - (rx >> 1n) : U32)
      Art.faces((lx < 16 : U32) && (py >= le : U32) && (py < le + dl : U32),
        (rx < 16 : U32) && (py >= re : U32) && (py < re + dr : U32), dl, dr, le, re,
        px, py, U32.is_eq(ter, 4), nb)

# queue railings: posts at the corners and a rope 4 px up along each edge
# that joins nothing
def Art.rails.go(on: Bool, +x: U32, +y: U32, +nb: U32, +px: U32, +py: U32, +wood: Bool) -> U32:
  match on:
    case True{}:
      +X = (px - x : U32)
      +Y = ((py + 4 - y) * 2 : U32)
      +u = iso_u(X, Y)
      +v = iso_v(X, Y)
      +in = (u < 17 : U32) && (v < 17 : U32)
      +rope = in && Art.open_edge(nb, u, v, 1)
      +cx = sabs(X)
      +post = (U32.is_eq(X, 0) && (between((py - y : U32), (0 - 6 : U32), 0) && ((nb .&. 5 : U32) < 5 : U32)
          || between((py - y : U32), 10, 16) && ((nb .&. 10 : U32) < 10 : U32)))
        || U32.is_eq(cx, 16) && between((py - y : U32), 2, 8)
      +knob = post && (U32.is_eq((py - y : U32), (0 - 6 : U32)) || U32.is_eq((py - y : U32), 10)
        || U32.is_eq((py - y : U32), 2))
      sel(knob, 14725184, sel(post, 7031339, sel(rope, sel(wood, 9062442, sel(U32.is_eq(((u + v) .&. 1 : U32), 0), 8011680, 5582448)), TR())))
    case False{}:
      TR()

# a ride's entrance or exit arch on the path tile's edge toward the ride
# (nb bits 4-5: that edge, 6-7: 1 entrance, 2 exit): two posts and a banner,
# green in, red out
def Art.arch.go(on: Bool, +x: U32, +y: U32, +nb: U32, +px: U32, +py: U32) -> U32:
  match on:
    case True{}:
      +side = ((nb >> 4n) .&. 3 : U32)
      +kind = ((nb >> 6n) .&. 3 : U32)
      +X = (px - x : U32)
      +Y = (py - y : U32)
      +e = sel(U32.is_eq(side, 0), (0 - X : U32), sel(U32.is_eq(side, 1), (16 - X : U32),
        sel(U32.is_eq(side, 2), X, (X + 16 : U32))))
      +yb = sel(U32.is_eq(side, 1) || U32.is_eq(side, 3), (8 + (e >> 1n) : U32), (e >> 1n : U32))
      +rel = (Y - yb : U32)
      +post = (between(e, 1, 3) || between(e, 13, 15)) && between(rel, (0 - 20 : U32), 0)
      +knob = post && between(rel, (0 - 21 : U32), (0 - 20 : U32)) && (U32.is_eq(e, 2) || U32.is_eq(e, 14))
      +banner = between(e, 1, 15) && between(rel, (0 - 19 : U32), (0 - 13 : U32))
      +trim = banner && (U32.is_eq(rel, (0 - 19 : U32)) || U32.is_eq(rel, (0 - 13 : U32)))
      +mark = banner && (U32.is_eq(rel, (0 - 16 : U32)) && between(e, 6, 10)
        || U32.is_eq(rel, (0 - 17 : U32)) && between(e, 7, 9) && U32.is_eq(kind, 1)
        || U32.is_eq(rel, (0 - 15 : U32)) && between(e, 7, 9) && U32.is_eq(kind, 2))
      +col = sel(U32.is_eq(kind, 1), 3831360, 12595248)
      sel(knob, 14725184, sel(post, sel(U32.is_eq(e, 1) || U32.is_eq(e, 13), 8014378, 5125410),
        sel(trim, 14725184, sel(mark, 16316664, sel(banner, col, TR())))))
    case False{}:
      TR()

# Mess on a paved tile (nb bits 8-11: litter, 12-14: sick). The top is cut
# into 4 x 4 cells; each cell has a fixed rank, and the first `litter` ranks
# carry a scrap, the first `sick * 2` of another ranking a puddle.
def Art.bin(+X: U32, +Y: U32, +full: Bool, +t: U32, +broke: Bool) -> U32:
  +body = between(X, (0 - 2 : U32), 2) && between(Y, (0 - 7 : U32), 0)
  +rim = body && U32.is_eq(Y, (0 - 7 : U32))
  +band = body && (U32.is_eq(Y, (0 - 2 : U32)) || U32.is_eq(Y, (0 - 5 : U32)))
  +side = body && U32.is_eq(X, 2)
  +heap = full && (U32.is_eq(Y, (0 - 8 : U32)) && between(X, (0 - 2 : U32), 2)
    || U32.is_eq(Y, (0 - 9 : U32)) && between(X, (0 - 1 : U32), 1))
  +hc = sel(U32.is_eq(((X + Y) .&. 1 : U32), 0), 15263976, sel(U32.is_eq(X, 0), 12595248, 5275848))
  +fly = full && U32.is_eq(Y, (0 - 12 + (((t >> 3n) + X) .&. 1) : U32)) && (U32.is_eq(X, (0 - 2 : U32)) || U32.is_eq(X, 2))
  +dent = broke && (U32.is_eq(Y, (0 - 7 : U32)) || U32.is_eq(Y, (0 - 6 : U32)) && (X < 2 : U32))
  +c = sel(fly, 3158064, sel(heap, hc, sel(rim, 10514496, sel(band, 4862000, sel(side, 6044200, sel(body, 8016432, TR()))))))
  sel(dent, TR(), sel(broke && opaque(c), shade(c, 150), c))

def Art.bench(+X: U32, +Y: U32, +broke: Bool) -> U32:
  +yb = (8 - ((X + 16) >> 1n) : U32)
  +rel = (Y - yb : U32)
  +span = between(X, (0 - 6 : U32), 6)
  +seat = span && between(rel, (0 - 5 : U32), (0 - 4 : U32)) && Bool.not(broke && between(X, (0 - 1 : U32), 2))
  +back = span && (U32.is_eq(rel, (0 - 10 : U32)) || U32.is_eq(rel, (0 - 8 : U32))) && Bool.not(broke && slt(X, 0))
  +post = (U32.is_eq(X, (0 - 6 : U32)) || U32.is_eq(X, 5)) && between(rel, (0 - 10 : U32), (0 - 6 : U32))
  +leg = (U32.is_eq(X, (0 - 5 : U32)) || U32.is_eq(X, 5)) && between(rel, (0 - 3 : U32), (0 - 1 : U32))
  sel(seat, sel(U32.is_eq(rel, (0 - 5 : U32)), 11567184, 8016432), sel(back, 10514496,
    sel(post, 5125410, sel(leg, 3811866, TR()))))

def Art.lamp(+X: U32, +Y: U32, +t: U32, +broke: Bool) -> U32:
  +post = between(X, 0, 1) && between(Y, (0 - 18 : U32), 0)
  +foot = between(X, (0 - 1 : U32), 2) && between(Y, (0 - 1 : U32), 0)
  +box = between(X, (0 - 1 : U32), 2) && between(Y, (0 - 24 : U32), (0 - 19 : U32))
  +frame = box && (U32.is_eq(X, (0 - 1 : U32)) || U32.is_eq(X, 2) || U32.is_eq(Y, (0 - 24 : U32)) || U32.is_eq(Y, (0 - 19 : U32)))
  +cap = between(X, 0, 1) && U32.is_eq(Y, (0 - 25 : U32)) || U32.is_eq(Y, (0 - 26 : U32)) && U32.is_eq(X, 0)
  +flick = U32.is_eq((hash((t >> 3n : U32), 5) .&. 3 : U32), 0)
  +glow = sel(broke, sel(U32.is_eq(((X + Y) .&. 1 : U32), 0), 3750986, 5263440), E(sel(flick, 16771216, 16767072)))
  +arm = U32.is_eq(Y, (0 - 18 : U32)) && between(X, (0 - 1 : U32), 2)
  sel(cap || frame || arm, 2631720, sel(box, sel(U32.is_eq(Y, (0 - 22 : U32)) && U32.is_eq(X, 0) && Bool.not(broke), E(16777184), glow),
    sel(foot, 2631720, sel(post, sel(U32.is_eq(X, 0), 4210756, 2631720), TR()))))

def Art.prop(+k: U32, +full: Bool, +broke: Bool, +x: U32, +y: U32, +px: U32, +py: U32, +t: U32) -> U32:
  match k:
    case 1:
      Art.bin((px - (x + 8) : U32), (py - (y + 6) : U32), full, t, broke)
    case 2:
      Art.bench((px - (x - 7) : U32), (py - (y + 6) : U32), broke)
    case 3:
      Art.lamp((px - x : U32), (py - (y + 4) : U32), t, broke)
    case _:
      TR()

def Art.pool(on: Bool, +c: U32, +x: U32, +y: U32, +px: U32, +py: U32, +t: U32) -> U32:
  match on:
    case True{}:
      +lit = ell((px - x : U32), (py - (y + 7) : U32), 13, 7)
      +warm = ((U32.min((((c >> 16n) .&. 255) + 70 : U32), 255) << 16n) .|. (U32.min((((c >> 8n) .&. 255) + 45 : U32), 255) << 8n) .|. (c .&. 255) : U32)
      sel(lit && opaque(c), E(Light.tint(warm, (140 + (((256 - Art.night(t)) * 85) >> 8n) : U32), (130 + (((256 - Art.night(t)) * 85) >> 8n) : U32), 110)), c)
    case False{}:
      c

def Art.block.face(+x: U32, +y: U32, +dl: U32, +dr: U32, +ter: U32, +obj: U32,
  +hov: U32, +wx: U32, +wy: U32, +t: U32, +px: U32, +py: U32, +nb: U32) -> U32:
  +X = (px - x : U32)
  +Y = ((py - y) * 2 : U32)
  +u = iso_u(X, Y)
  +v = iso_v(X, Y)
  over(Art.prop(((nb >> 16n) .&. 3 : U32), Bool.not(U32.is_eq((nb .&. 262144 : U32), 0)),
    Bool.not(U32.is_eq((nb .&. 524288 : U32), 0)), x, y, px, py, t),
    over(Art.arch.go(Bool.not(U32.is_eq(((nb >> 6n) .&. 3 : U32), 0)), x, y, nb, px, py),
    over(Art.rails.go(U32.is_eq(obj, 7) || U32.is_eq(obj, 1) && U32.is_eq(ter, 2), x, y, nb, px, py, U32.is_eq(obj, 1)),
    Art.block.go((u < 16 : U32) && (v < 16 : U32), x, y, dl, dr, ter, obj, hov,
      wx, wy, t, px, py, u, v, nb))))

# Trees (anchored at the tile centre)
# -----------------------------------
# Leaves and caps are shaded as small lit volumes (light from the top
# left): a highlight rim, three body tones with dithered edges, a deep
# outline on the shadowed side, and a soft ground shadow under each tree.

def Art.block(+x: U32, +y: U32, +dl: U32, +dr: U32, +ter: U32, +obj: U32,
  +hov: U32, +wx: U32, +wy: U32, +t: U32, +px: U32, +py: U32, +nb: U32) -> U32:
  Art.pool(U32.is_eq(((nb >> 16n) .&. 3 : U32), 3) && U32.is_eq((nb .&. 524288 : U32), 0) && (Art.night(t) > 96 : U32),
    Art.block.face(x, y, dl, dr, ter, obj, hov, wx, wy, t, px, py, nb), x, y, px, py, t)

def Art.checker(+x: U32, +y: U32) -> Bool:
  U32.is_eq(((x + y) .&. 1 : U32), 0)

# a soft ground shadow: dark meadow tones, dithered
def Art.shadow(+dx: U32, +dy: U32, +rx: U32, +ry: U32) -> U32:
  +in = ell(dx, dy, rx, ry)
  +edge = in && Bool.not(ell(dx, dy, (rx - 2 : U32), U32.max((ry - 1 : U32), 1)))
  sel(in, sel(edge && Art.checker(dx, dy), TR(), sel(Art.checker(dx, dy), 3310120, 3574314)), TR())

# one clump of leaves of radius r centred at (cx, cy): 5 tones
def Art.leaf(+k: U32) -> U32:
  match k:
    case 0:
      8833118
    case 1:
      5938756
    case 2:
      4161332
    case 3:
      2908969
    case _:
      1786397

def Art.clump.go(in: Bool, +dx: U32, +dy: U32, +ex: U32, +ey: U32, +d2: U32, +r: U32,
  +n: U32) -> U32:
  match in:
    case True{}:
      +v = (ex + ey : U32)
      +h = (r >> 1n : U32)
      +q = (h >> 1n : U32)
      +rim = ((d2 + r + r) > (r * r) : U32)
      +dith = Art.checker(dx, dy)
      +tone = sel(slt(v, (0 - h - 1 : U32)), 1, sel(slt(v, (0 - h + 1 : U32)), sel(dith, 1, 2),
        sel(slt(v, q), 2, sel(slt(v, (q + 2 : U32)), sel(dith, 2, 3), 3))))
      +speck = U32.is_eq((hash((ex + n : U32), (ey * 7 + n : U32)) .&. 7 : U32), 0)
      +t2 = sel(speck, U32.min((tone + 1 : U32), 3), tone)
      Art.leaf(sel(rim && slt(0, v), 4, sel(rim && slt(v, (0 - q : U32)), 0, t2)))
    case False{}:
      TR()

# one clump of leaves of radius r centred at (cx, cy): 5 tones
def Art.clump(+dx: U32, +dy: U32, +cx: U32, +cy: U32, +r: U32, +n: U32) -> U32:
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  +d2 = (ex * ex + ey * ey : U32)
  Art.clump.go((d2 <= r * r : U32), dx, dy, ex, ey, d2, r, n)

def Art.bark(+dx: U32, +dy: U32) -> U32:
  sel(U32.is_eq(dx, (0 - 1 : U32)), 9068600, sel(U32.is_eq(dx, 1), 4862492,
    sel(U32.is_eq(((dy + 64) .&. 3 : U32), 0), 5913634, 7031339)))

def Art.oak(+dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  # the crown sways a pixel or two in the wind
  +sw = wsin(((t * 3) + n : U32), 2)
  +cx = (dx - sw : U32)
  +flare = sle((0 - 2 : U32), dy) && (sabs(dx) <= 2 : U32)
  +trunk = (sabs(dx) <= 1 : U32) && between(dy, (0 - 12 : U32), 0) || flare && sle(dy, 0)
  +k = (0 - dy - 9 : U32)
  +bl = (k <= 7 : U32) && U32.is_eq(dx, (0 - (k >> 1n) : U32))
  +br = (k <= 6 : U32) && U32.is_eq(dx, (k >> 1n : U32))
  +wood = sel(trunk, Art.bark(dx, dy), sel(bl || br, 5913634, TR()))
  +crown = over(Art.clump(cx, dy, 4, (0 - 11 : U32), 5, n), over(Art.clump(cx, dy, (0 - 3 : U32), (0 - 12 : U32), 5, n),
    over(Art.clump(cx, dy, 8, (0 - 12 : U32), 4, n), over(Art.clump(cx, dy, (0 - 8 : U32), (0 - 12 : U32), 4, n),
    over(Art.clump(cx, dy, 6, (0 - 17 : U32), 5, n), over(Art.clump(cx, dy, (0 - 6 : U32), (0 - 17 : U32), 5, n),
    over(Art.clump(cx, dy, 0, (0 - 16 : U32), 6, n), Art.clump(cx, dy, 0, (0 - 22 : U32), 6, n))))))))
  over(crown, over(wood, Art.shadow((dx - 1 : U32), (dy - 1 : U32), 10, 4)))

# a moonpine tier: serrated edges, moonlit from the left, frosted tips
def Art.pine_tier(+dx: U32, +dy: U32, +apex: U32, +h: U32, +w: U32, +n: U32) -> U32:
  +d = (dy - apex : U32)
  +ax = sabs(dx)
  +dw = (d * w : U32)
  +edge = ((ax + 1) * h >= dw : U32)
  +jag = U32.is_eq(((ax + d + n) .&. 1 : U32), 1) && edge
  +inside = (d < h : U32) && (ax * h <= dw : U32) && Bool.not(jag)
  +frost = (d + 1 >= h : U32) && U32.is_eq(((dx + n) .&. 1 : U32), 0)
    || (d < 1 : U32)
  +tone = sel(neg(dx), sel((ax * 2 * h > dw : U32), 6270621, 3834744), sel((ax * 3 * h < dw : U32), 3834744,
    sel(edge, 1522233, 2382419)))
  sel(inside, sel(frost, 14217193, tone), TR())

def Art.pine(+dx: U32, +dy: U32, +n: U32) -> U32:
  +trunk = (sabs(dx) <= 1 : U32) && between(dy, (0 - 6 : U32), 0)
  over(Art.pine_tier(dx, dy, (0 - 38 : U32), 10, 3, n),
    over(Art.pine_tier(dx, dy, (0 - 31 : U32), 11, 5, n),
      over(Art.pine_tier(dx, dy, (0 - 24 : U32), 12, 7, n),
        over(Art.pine_tier(dx, dy, (0 - 17 : U32), 12, 9, n),
          over(sel(trunk, Art.bark(dx, dy), TR()), Art.shadow((dx - 1 : U32), (dy - 1 : U32), 8, 3))))))

# a glowcap: domed cap with a highlight, glowing spots, gills beneath, and
# a fibrous stem with a skirt; sometimes a small one beside it
def Art.cap(+dx: U32, +dy: U32, +cy: U32, +rx: U32, +ry: U32, +n: U32, +t: U32) -> U32:
  +ey = (dy - cy : U32)
  +dome = ell(dx, ey, rx, ry) && sle(ey, 0)
  +gill = ell(dx, (ey - 1 : U32), (rx - 1 : U32), U32.max(div3(ry), 1)) && sle(0, ey)
  +gstripe = U32.is_eq((((dx + 64) >> 1n) .&. 1 : U32), 0)
  +hi = ell((dx + div3(rx) : U32), (ey + (ry >> 1n) + 1 : U32), U32.max((rx >> 2n : U32), 1), U32.max((ry >> 2n : U32), 1))
  +cellx = div3((dx + 66 : U32))
  +celly = div3((ey + 66 : U32))
  +spoton = U32.is_eq((hash((cellx + n : U32), celly) .&. 1 : U32), 0)
  +sx = ((dx + 66) - cellx * 3 : U32)
  +sy = ((ey + 66) - celly * 3 : U32)
  +spot = spoton && (sx >= 1 : U32) && (sy >= 1 : U32) && slt(ey, (0 - 1 : U32))
  +spotsh = spot && U32.is_eq(sx, 2) && U32.is_eq(sy, 2)
  +pulse = (tri(((t * 4) + n : U32)) > 32 : U32)
  +rimk = Bool.not(ell(dx, ey, (rx - 1 : U32), U32.max((ry - 1 : U32), 1)))
  +body = sel(slt(ey, (0 - div3((ry * 2 : U32)) : U32)), 16738906, sel(neg(dx), 14172218, 11546154))
  +capc = sel(hi, 16761008, sel(spotsh, 14207168, sel(spot, sel(pulse, 16776144, 16774378),
    sel(rimk && slt(0, dx), 9052192, body))))
  sel(dome, capc, sel(gill, sel(gstripe, 15259312, 13218956), TR()))

def Art.stem(+dx: U32, +dy: U32, +top: U32, +w: U32) -> U32:
  +bulge = sel(sle((0 - 2 : U32), dy), (w + 1 : U32), w)
  +in = (sabs(dx) <= bulge : U32) && between(dy, top, 0)
  +skirt = U32.is_eq(dy, (top + 3 : U32)) && (sabs(dx) <= (w + 1 : U32) : U32)
  +c = sel(U32.is_eq(sabs(dx), bulge) && slt(0, dx), 12100738, sel(U32.is_eq((dx .&. 1 : U32), 0), 14207140, 15787208))
  sel(skirt, 13218956, sel(in, c, TR()))

def Art.glowcap(+dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  +big = over(Art.cap(dx, dy, (0 - 12 : U32), 12, 9, n, t), Art.stem(dx, dy, (0 - 12 : U32), 2))
  +bx = (dx - 8 : U32)
  +by = (dy - 2 : U32)
  +baby = sel(U32.is_eq((n .&. 1 : U32), 1),
    over(Art.cap(bx, by, (0 - 5 : U32), 4, 3, (n + 5 : U32), t), Art.stem(bx, by, (0 - 5 : U32), 1)), TR())
  over(big, over(baby, Art.shadow((dx - 1 : U32), (dy - 1 : U32), 10, 4)))

# crystals: faceted spikes on a rocky base, their tips twinkling
def Art.spike(+dx: U32, +dy: U32, +ox: U32, +h: U32, +w: U32) -> U32:
  +ex = (dx - ox : U32)
  +ax = sabs(ex)
  +inside = (ax <= w : U32) && sle((0 - h + ax * 2 : U32), dy) && sle(dy, 0)
  +ridge = U32.is_eq(ex, 0)
  +tip = sle(dy, (0 - h + 3 : U32))
  +deep = sle((0 - 2 : U32), dy)
  sel(inside, sel(ridge && tip, 16777215, sel(ridge, 15523071, sel(deep, 5910672,
    sel(neg(ex), sel(U32.is_eq(ax, w), 11828479, 14203135), sel(U32.is_eq(ax, w), 5910672, 9066704))))), TR())

def Art.crystal(+dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  +glint = ((((t + n * 13) .&. 127) : U32) < 10 : U32)
  +star = glint && (U32.is_eq(dx, 0) && between(dy, (0 - 25 : U32), (0 - 19 : U32))
    || U32.is_eq(dy, (0 - 22 : U32)) && between(dx, (0 - 3 : U32), 3))
  +rocks = ell(dx, (dy - 1 : U32), 7, 3)
  +rockc = sel(Art.checker(dx, dy), 8026760, sel(neg(dx), 9079450, 5921384))
  over(sel(star, 16777215, TR()), over(Art.spike(dx, dy, 0, 21, 2),
    over(Art.spike(dx, dy, (0 - 5 : U32), 14, 2), over(Art.spike(dx, (dy - 1 : U32), 5, 12, 2),
      over(Art.spike(dx, (dy + 1 : U32), 2, 8, 1), sel(rocks, rockc, TR()))))))

# Scenery (tree tiles with variants 4 and up): statues of a knight, a dragon,
# a wizard and a griffin on plinths; a fountain; flower beds; castle walls
# and fences that join their neighbours (n: bit 1 i-1, 2 i+1, 4 j-1, 8 j+1)
def Art.box2(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +top: U32, +left: U32, +right: U32) -> U32:
  +ax = sabs(dx)
  +cy = (base - h : U32)
  +ontop = ((ax + 2 * sabs((dy - cy : U32))) <= r : U32)
  +lowtop = (cy + ((r - ax) >> 1n) : U32)
  +lowbot = (base + ((r - ax) >> 1n) : U32)
  +side = (ax <= r : U32) && sle(lowtop, dy) && sle(dy, lowbot)
  sel(ontop, top, sel(side, sel(neg(dx), left, right), TR()))

# The Lich's Crypt: a dark ride inside a mossy crypt, green light flickering
# in its windows while the riders are inside; their carts wait at the door
def Art.plinth(+dx: U32, +dy: U32) -> U32:
  Art.box2(dx, dy, 0, 7, 4, 11579568, 9474192, 7368816)

def Art.statue.fig(+k: U32, +dx: U32, +dy: U32, +t: U32) -> U32:
  match k:
    case 0:
      # a knight, sword raised
      +legs = (U32.is_eq(dx, (0 - 1 : U32)) || U32.is_eq(dx, 1)) && between(dy, (0 - 8 : U32), (0 - 5 : U32))
      +body = between(dx, (0 - 2 : U32), 2) && between(dy, (0 - 13 : U32), (0 - 9 : U32))
      +head = between(dx, (0 - 1 : U32), 1) && between(dy, (0 - 16 : U32), (0 - 14 : U32))
      +shield = between(dx, (0 - 4 : U32), (0 - 3 : U32)) && between(dy, (0 - 13 : U32), (0 - 9 : U32))
      +sword = U32.is_eq(dx, 3) && between(dy, (0 - 22 : U32), (0 - 11 : U32)) || U32.is_eq(dy, (0 - 13 : U32)) && between(dx, 2, 4)
      sel(sword, 13684944, sel(legs || body || head || shield, sel(neg(dx), 10132122, 8421512), TR()))
    case 1:
      # a coiled dragon, wings up, bronze gone green
      +coil = ell(dx, (dy + 7 : U32), 5, 2)
      +neck = between(dx, 1, 3) && between(dy, (0 - 14 : U32), (0 - 8 : U32))
      +head = between(dx, 2, 6) && between(dy, (0 - 17 : U32), (0 - 15 : U32))
      +wing = between(dx, (0 - 6 : U32), 0) && U32.is_eq(dy, (0 - 10 + (dx >> 1n) : U32)) || between(dx, (0 - 5 : U32), (0 - 1 : U32)) && U32.is_eq(dy, (0 - 11 + (dx >> 1n) : U32))
      sel(coil || neck || head, 5282906, sel(wing, 4225616, TR()))
    case 2:
      # a robed wizard with a staff, its crystal glowing
      +robe = between(dy, (0 - 13 : U32), (0 - 5 : U32)) && ((sabs(dx) * 3 + 2) <= (0 - dy) : U32)
      +head = between(dx, (0 - 1 : U32), 1) && between(dy, (0 - 16 : U32), (0 - 14 : U32))
      +hat = U32.is_eq(dy, (0 - 17 : U32)) && (sabs(dx) <= 2 : U32) || U32.is_eq(dy, (0 - 18 : U32)) && (sabs(dx) <= 1 : U32)
        || U32.is_eq(dx, 0) && between(dy, (0 - 20 : U32), (0 - 19 : U32))
      +staff = U32.is_eq(dx, 4) && between(dy, (0 - 19 : U32), (0 - 5 : U32))
      +gem = U32.is_eq(dx, 4) && between(dy, (0 - 21 : U32), (0 - 20 : U32))
      +pulse = U32.is_eq(((t >> 4n) .&. 1 : U32), 0)
      sel(gem, sel(pulse, 12640255, 6352127), sel(staff, 8421512, sel(robe || head || hat, sel(neg(dx), 10132122, 8421512), TR())))
    case _:
      # a gilded griffin, one foreleg raised
      +body = ell(dx, (dy + 9 : U32), 4, 2)
      +legs = (U32.is_eq(dx, (0 - 3 : U32)) || U32.is_eq(dx, 2)) && between(dy, (0 - 7 : U32), (0 - 5 : U32))
      +head = between(dx, 2, 5) && between(dy, (0 - 15 : U32), (0 - 11 : U32))
      +beak = U32.is_eq(dx, 6) && U32.is_eq(dy, (0 - 13 : U32))
      +wing = between(dx, (0 - 4 : U32), 1) && between(dy, (0 - 17 : U32), (0 - 11 : U32)) && sle((0 - 17 : U32), (dy - dx : U32))
      sel(beak, 12595248, sel(body || legs || head, 14725184, sel(wing, 12092939, TR())))

def Art.statue(+k: U32, +dx: U32, +dy: U32, +t: U32) -> U32:
  over(Art.statue.fig(k, dx, (dy + 4 : U32), t), Art.plinth(dx, dy))

def Art.fountain(+dx: U32, +dy: U32, +t: U32) -> U32:
  +rim = ell(dx, (dy + 2 : U32), 11, 6) && Bool.not(ell(dx, (dy + 2 : U32), 9, 5))
  +wall = Bool.not(ell(dx, (dy + 2 : U32), 11, 6)) && ell(dx, dy, 11, 6) && sle((0 - 2 : U32), dy)
  +water = ell(dx, (dy + 2 : U32), 9, 5)
  +ripple = water && U32.is_eq((((dx * dx + dy * dy * 4) + (t >> 1n)) .&. 15 : U32), 0)
  +col = (sabs(dx) <= 1 : U32) && between(dy, (0 - 12 : U32), (0 - 2 : U32))
  +bowl = ell(dx, (dy + 12 : U32), 4, 2)
  +s = (t .&. 15 : U32)
  +drop1 = U32.is_eq(dx, (0 - 3 - (s >> 2n) : U32)) && U32.is_eq(dy, (0 - 14 + ((s * s) >> 4n) : U32))
  +drop2 = U32.is_eq(dx, (3 + (s >> 2n) : U32)) && U32.is_eq(dy, (0 - 14 + ((s * s) >> 4n) : U32))
  +spout = U32.is_eq(dx, 0) && between(dy, (0 - 17 : U32), (0 - 13 : U32))
  sel(drop1 || drop2 || spout, 12640255, sel(bowl, 10132122, sel(col, sel(neg(dx), 11579568, 9474192),
    sel(ripple, 12640255, sel(water, 4221152, sel(rim, 11579568, sel(wall, 8421512, TR())))))))

def Art.flowers(+k: U32, +dx: U32, +dy: U32) -> U32:
  +d = (sabs(dx) + 2 * sabs(dy) : U32)
  +bed = (d <= 12 : U32)
  +edge = bed && (d >= 11 : U32)
  +h = hash((dx + 64 : U32), (dy + 64 : U32))
  +bloom = bed && Bool.not(edge) && U32.is_eq((h .&. 3 : U32), 0)
  +c = sel(U32.is_eq(k, 0), 14168128, sel(U32.is_eq(k, 1), 6320595, 16766282))
  sel(edge, 9062442, sel(bloom, sel(U32.is_eq(((h >> 4n) .&. 3 : U32), 0), 16316664, c), sel(bed, sel(U32.is_eq(((h >> 6n) .&. 1 : U32), 0), 3834938, 5214768), TR())))

# a run of wall or fence from the tile centre toward its edge: (gx, gy) the
# ground under the pixel along direction d (0 i-1, 1 i+1, 2 j-1, 3 j+1)
def Art.run.on(+n: U32, +d: U32, +dx: U32) -> Bool:
  +bit = sel(U32.is_eq(d, 0), 1, sel(U32.is_eq(d, 1), 2, sel(U32.is_eq(d, 2), 4, 8)))
  +pos = U32.is_eq(d, 1) || U32.is_eq(d, 2)
  +half = pos && between(dx, 0, 8) || Bool.not(pos) && between(dx, (0 - 8 : U32), 0)
  Bool.not(U32.is_eq((n .&. bit : U32), 0)) && half

def sar(+v: U32, +n: Nat) -> U32:
  sel(neg(v), (0 - ((0 - v) >> n) : U32), (v >> n : U32))

# a ride's phase and time into it (st: phase << 16 | ticks)
def Art.run.gy(+d: U32, +dx: U32) -> U32:
  sel(U32.is_eq(d, 0) || U32.is_eq(d, 1), sar(dx, 1n), (0 - sar(dx, 1n) : U32))

def Art.wall.part(+n: U32, +d: U32, +dx: U32, +dy: U32) -> U32:
  +gy = Art.run.gy(d, dx)
  +r = (dy - gy : U32)
  +on = Art.run.on(n, d, dx) && between(r, (0 - 11 : U32), 1)
  +crenel = between(r, (0 - 11 : U32), (0 - 10 : U32)) && U32.is_eq(((dx + 64) .&. 2 : U32), 0)
  +top = U32.is_eq(r, (0 - 9 : U32))
  +mortar = U32.is_eq(((r + 64) .&. 3 : U32), 0) || U32.is_eq(((dx + ((r + 64) >> 2n) * 2 + 64) .&. 3 : U32), 0)
  sel(on && Bool.not(between(r, (0 - 11 : U32), (0 - 10 : U32)) && Bool.not(crenel)),
    sel(top, 11579568, sel(mortar, 7368816, sel(U32.is_eq(d, 1) || U32.is_eq(d, 3), 9474192, 10132122))), TR())

def Art.wall(+n: U32, +dx: U32, +dy: U32) -> U32:
  +post = (sabs(dx) <= 2 : U32) && between(dy, (0 - 13 : U32), 1)
  +cap = (sabs(dx) <= 2 : U32) && between(dy, (0 - 14 : U32), (0 - 13 : U32))
  over(sel(cap, 11579568, sel(post, sel(neg(dx), 10132122, 8421512), TR())),
    over(Art.wall.part(n, 1, dx, dy), over(Art.wall.part(n, 3, dx, dy),
    over(Art.wall.part(n, 0, dx, dy), Art.wall.part(n, 2, dx, dy)))))

def Art.fence.part(+n: U32, +d: U32, +dx: U32, +dy: U32) -> U32:
  +gy = Art.run.gy(d, dx)
  +r = (dy - gy : U32)
  +on = Art.run.on(n, d, dx)
  +rail = on && (U32.is_eq(r, (0 - 3 : U32)) || U32.is_eq(r, (0 - 6 : U32)))
  +post = on && U32.is_eq(((dx + 64) .&. 3 : U32), 0) && between(r, (0 - 7 : U32), 0)
  sel(post, 7031338, sel(rail, 9062442, TR()))

def Art.fence(+n: U32, +dx: U32, +dy: U32) -> U32:
  +post = (sabs(dx) <= 1 : U32) && between(dy, (0 - 8 : U32), 0)
  over(sel(post, 5913120, TR()), over(Art.fence.part(n, 1, dx, dy), over(Art.fence.part(n, 3, dx, dy),
    over(Art.fence.part(n, 0, dx, dy), Art.fence.part(n, 2, dx, dy)))))

def Art.scenery(+v: U32, +dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  match v:
    case 8:
      Art.fountain(dx, dy, t)
    case 9:
      Art.flowers(0, dx, dy)
    case 10:
      Art.flowers(1, dx, dy)
    case 11:
      Art.flowers(2, dx, dy)
    case 12:
      Art.wall(n, dx, dy)
    case 13:
      Art.fence(n, dx, dy)
    case _:
      Art.statue((v - 4 : U32), dx, dy, t)

def Art.tree(+v: U32, +dx: U32, +dy: U32, +n: U32, +t: U32) -> U32:
  match v:
    case 0:
      Art.oak(dx, dy, n, t)
    case 1:
      Art.pine(dx, dy, n)
    case 2:
      Art.glowcap(dx, dy, n, t)
    case 3:
      Art.crystal(dx, dy, n, t)
    case _:
      Art.scenery(v, dx, dy, n, t)


def Art.cyl(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +c: U32) -> U32:
  +ry = (r >> 1n : U32)
  +body = (sabs(dx) <= r : U32) && between(dy, (base - h : U32), base)
  +bot = ell(dx, (dy - base : U32), r, U32.max(ry, 1))
  +topc = ell(dx, (dy - (base - h) : U32), r, U32.max(ry, 1))
  +k = sel(slt(dx, (0 - div3(r) : U32)), 290, sel(slt(div3(r), dx), 175, 230))
  sel(topc, shade(c, 320), sel(body || bot, shade(c, k), TR()))

# a cone with its base ellipse centred at (0, base)
def Art.cone(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +c: U32,
  +c2: U32) -> U32:
  +apex = (base - h : U32)
  +d = (dy - apex : U32)
  +inside = sle(apex, dy) && sle(dy, base) && ((sabs(dx) * h) <= (d * r) : U32)
  +rim = ell(dx, (dy - base : U32), r, U32.max((r >> 1n : U32), 1)) && sle(base, dy)
  +stripe = U32.is_eq(((div3((dx + 256 : U32)) >> 1n) .&. 1 : U32), 0)
  +k = sel(slt(dx, (0 - div3(r) : U32)), 290, sel(slt(div3(r), dx), 180, 235))
  sel(inside || rim, shade(sel(stripe, c, c2), k), TR())

# an iso box on (0, base): footprint diamond half-width r, height h
def Art.box(+dx: U32, +dy: U32, +base: U32, +r: U32, +h: U32, +top: U32,
  +left: U32, +right: U32) -> U32:
  +X = dx
  +Yt = ((dy - (base - h - (r >> 1n))) * 2 : U32)
  +tu = iso_u((X + r : U32), Yt)
  +tv = iso_v((X + r : U32), Yt)
  +ontop = (tu < r : U32) && (tv < r : U32)
  # side faces: below the top diamond's lower edges, above the bottom ones
  +ax = sabs(dx)
  +lowtop = (base - h + (r >> 1n) - (ax >> 1n) : U32)
  +lowbot = (base + (r >> 1n) - (ax >> 1n) : U32)
  +side = (ax <= r : U32) && sle(lowtop, dy) && sle(dy, lowbot)
  sel(ontop, top, sel(side, sel(neg(dx), left, right), TR()))

# Buildings and rides
# -------------------

def Art.gate(+dx: U32, +dy: U32, +t: U32) -> U32:
  +tl = Art.cyl((dx + 12 : U32), dy, 2, 5, 28, 11051168)
  +tr = Art.cyl((dx - 12 : U32), dy, 2, 5, 28, 11051168)
  +rl = Art.cone((dx + 12 : U32), dy, (0 - 26 : U32), 7, 13, 12073530, 10036266)
  +rr = Art.cone((dx - 12 : U32), dy, (0 - 26 : U32), 7, 13, 12073530, 10036266)
  +fl = (sabs((dx - 12 : U32)) <= 0 : U32) && between(dy, (0 - 46 : U32), (0 - 39 : U32))
  +flag = between((dx - 12 : U32), 1, 6) && between(dy, (0 - 46 : U32),
    ((0 - 43) + ((dx + (t >> 3n)) .&. 1) : U32))
  +wall = (sabs(dx) <= 9 : U32) && between(dy, (0 - 20 : U32), 3)
  +arch = (sabs(dx) <= 4 : U32) && between(dy, (0 - 10 : U32), 3)
    || (sabs(dx) <= 3 : U32) && between(dy, (0 - 12 : U32), 3)
  +battl = between(dy, (0 - 23 : U32), (0 - 21 : U32)) && (sabs(dx) <= 9 : U32)
    && U32.is_eq((((dx + 64) >> 1n) .&. 1 : U32), 0)
  +wallc = sel(arch, 3813162, sel(U32.is_eq((((dy + 64) >> 2n) .&. 1 : U32), 0), 10000032, 9210004))
  over(rl, over(rr, over(sel(fl, 5911040, sel(flag, 16766282, TR())),
    over(tl, over(tr, sel(wall || battl, wallc, TR()))))))

def Art.dragon(+dx: U32, +dy: U32, +a: U32) -> U32:
  +cx = wcos(a, 18)
  +cy = (wsin(a, 9) - 12 : U32)
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  +body = between(ex, (0 - 3 : U32), 2) && between(ey, (0 - 2 : U32), 0)
  +head = between(ex, 2, 4) && between(ey, (0 - 4 : U32), (0 - 2 : U32))
  +wing = between(ex, (0 - 1 : U32), 1) && U32.is_eq(ey, (0 - 3 : U32))
  +pole = U32.is_eq(ex, 0) && between(ey, (0 - 10 : U32), 6)
  +twist = U32.is_eq((((ey + 64) >> 1n) .&. 1 : U32), 0)
  sel(head, 4175450, sel(body, 3120973, sel(wing, 15253568, sel(pole, sel(twist, 14725184, 16250848), TR()))))

def Art.tunic(+k: U32) -> U32:
  match k:
    case 0:
      3830704
    case 1:
      10498096
    case 2:
      3181648
    case 3:
      9054256
    case 4:
      2129008
    case 5:
      12609552
    case 6:
      6316160
    case _:
      11546688

def Art.skin(+k: U32) -> U32:
  match k:
    case 0:
      16767148
    case 1:
      14851690
    case 2:
      10045514
    case _:
      15781004

# a thought's picture (k: thought * 8 + row, top first): nine 3-bit palette indices
def Art.trow(+k: U32) -> U32:
  match k:
    case 8:
      299520
    case 9:
      2991168
    case 10:
      23929992
    case 11:
      21570696
    case 12:
      2696289
    case 13:
      299780
    case 14:
      289
    case 16:
      4096
    case 17:
      41472
    case 18:
      336960
    case 19:
      2729096
    case 20:
      2696328
    case 21:
      2696328
    case 22:
      299584
    case 24:
      299584
    case 25:
      2696328
    case 26:
      21832913
    case 27:
      21570705
    case 28:
      21603985
    case 29:
      2729608
    case 30:
      299584
    case 32:
      38346752
    case 33:
      65536
    case 34:
      524288
    case 35:
      4195472
    case 36:
      38346768
    case 37:
      128
    case 38:
      1168
    case 40:
      299584
    case 41:
      2958536
    case 42:
      21603537
    case 43:
      21570705
    case 44:
      21608081
    case 45:
      2958536
    case 46:
      299584
    case 48:
      2359368
    case 49:
      23888529
    case 50:
      23663761
    case 51:
      21570705
    case 52:
      2696328
    case 53:
      336960
    case 54:
      41472
    case 56:
      299556
    case 57:
      2995296
    case 58:
      23667969
    case 59:
      23668881
    case 60:
      21577873
    case 61:
      3220616
    case 62:
      75797064
    case 64:
      19173961
    case 65:
      2995912
    case 66:
      341568
    case 67:
      41472
    case 68:
      370240
    case 69:
      2696328
    case 70:
      19173961
    case 72:
      1311040
    case 73:
      10488320
    case 74:
      1311040
    case 75:
      37376
    case 76:
      369728
    case 77:
      2696840
    case 78:
      21603473
    case 80:
      4096
    case 81:
      41472
    case 82:
      336960
    case 83:
      2696328
    case 84:
      3037896
    case 85:
      3070664
    case 86:
      3070664
    case _:
      0

# a thought's colours (k: thought * 8 + index): 1 the outline, then its own
def Art.tpal(+k: U32) -> U32:
  match k:
    case 10:
      10508332
    case 11:
      14192720
    case 12:
      15788248
    case 13:
      12103320
    case 18:
      3833824
    case 19:
      13165823
    case 26:
      8177744
    case 27:
      3037728
    case 34:
      4214960
    case 42:
      15229008
    case 43:
      5904400
    case 50:
      15219804
    case 51:
      16758984
    case 58:
      15251504
    case 59:
      16771216
    case 60:
      14690344
    case 66:
      14725184
    case 67:
      14216436
    case 74:
      9071162
    case 75:
      15261888
    case 77:
      5939244
    case 82:
      4094532
    case 83:
      12618320
    case 84:
      15781952
    case 85:
      4860948
    case _:
      3158080

# one pixel of a picture row (xi: 0..8, left first)
def Art.tcol(+row: U32, +xi: U32) -> U32:
  match xi:
    case 0:
      ((row >> 24n) .&. 7 : U32)
    case 1:
      ((row >> 21n) .&. 7 : U32)
    case 2:
      ((row >> 18n) .&. 7 : U32)
    case 3:
      ((row >> 15n) .&. 7 : U32)
    case 4:
      ((row >> 12n) .&. 7 : U32)
    case 5:
      ((row >> 9n) .&. 7 : U32)
    case 6:
      ((row >> 6n) .&. 7 : U32)
    case 7:
      ((row >> 3n) .&. 7 : U32)
    case _:
      (row .&. 7 : U32)

# a thought's picture (drawn by tools/genthoughts.py): x -4..4, r 0..6 from the top
def Art.thought(+m: U32, +x: U32, +r: U32) -> U32:
  +i = Art.tcol(Art.trow((m * 8 + r : U32)), (x + 4 : U32))
  sel(U32.is_eq(i, 0), TR(), Art.tpal((m * 8 + i : U32)))

# a thought bubble above the guest: 13 x 11, the picture in its middle
def Art.bubble.go(on: Bool, +m: U32, +dx: U32, +h: U32) -> U32:
  match on:
    case True{}:
      +ax = sabs(dx)
      +box = (ax <= 6 : U32) && between(h, 17, 27) && Bool.not(U32.is_eq(ax, 6) && (U32.is_eq(h, 17) || U32.is_eq(h, 27)))
      +rim = box && (U32.is_eq(ax, 6) || U32.is_eq(h, 17) || U32.is_eq(h, 27)
        || U32.is_eq(ax, 5) && (U32.is_eq(h, 18) || U32.is_eq(h, 26)))
      +tail = U32.is_eq(dx, 0) && U32.is_eq(h, 15) || U32.is_eq(dx, 1) && U32.is_eq(h, 16)
      +inpic = (ax <= 4 : U32) && between(h, 19, 25)
      +pic = sel(inpic, Art.thought(m, dx, (25 - h : U32)), TR())
      sel(rim || tail, 5263440, sel(box, over(pic, 16316664), TR()))
    case False{}:
      TR()

# what a guest carries in the leading hand (x: forward, y: up from the hand)
def Art.item(+it: U32, +x: U32, +y: U32) -> U32:
  match it:
    case 1:
      # a potion: glass bottle, cork
      +glass = between(x, 0, 1) && between(y, 0, 1)
      +neck = U32.is_eq(x, 0) && U32.is_eq(y, 2)
      sel(neck, 9138758, sel(glass, sel(U32.is_eq(x, 0) && U32.is_eq(y, 1), 14200063, 9844944), TR()))
    case 2:
      # a tankard of ale with its foam
      +mug = between(x, 0, 1) && between(y, 0, 1)
      +foam = between(x, 0, 1) && U32.is_eq(y, 2)
      +grip = U32.is_eq(x, 2) && U32.is_eq(y, 1)
      sel(foam, 16316656, sel(mug, 14721072, sel(grip, 9127187, TR())))
    case 3:
      # a wisp on a string, glowing and bobbing
      +string = U32.is_eq(x, 0) && between(y, 0, 5)
      +orb = ell(x, (y - 7 : U32), 1, 1)
      sel(orb, E(sel(U32.is_eq(x, 0) && U32.is_eq(y, 7), 16777215, 6352127)), sel(string, 12632256, TR()))
    case 4:
      # an enchanted ice: a wafer cone, a pink scoop
      +cone = U32.is_eq(x, 0) && between(y, 0, 1)
      +scoop = between(x, (0 - 1 : U32), 1) && between(y, 2, 3) && Bool.not(U32.is_eq(sabs(x), 1) && U32.is_eq(y, 3))
      sel(scoop, sel(U32.is_eq(y, 3), 10085546, 16758488), sel(cone, 14200928, TR()))
    case 9:
      # a Brownie's broom, bristles down
      +stick = U32.is_eq(x, 0) && between(y, (0 - 2 : U32), 4)
      +straw = between(x, (0 - 1 : U32), 1) && between(y, (0 - 4 : U32), (0 - 3 : U32))
      sel(straw, 14207064, sel(stick, 9127187, TR()))
    case 10:
      # a Tinker's hammer
      +haft = U32.is_eq(x, 0) && between(y, 0, 2)
      +head = between(x, (0 - 1 : U32), 1) && between(y, 3, 4)
      sel(head, 11053224, sel(haft, 9127187, TR()))
    case 11:
      # a Watch Knight's spear
      +shaft = U32.is_eq(x, 0) && between(y, (0 - 3 : U32), 8)
      +tip = U32.is_eq(x, 0) && between(y, 9, 10) || U32.is_eq(y, 9) && (sabs(x) <= 1 : U32)
      sel(tip, 14737632, sel(shaft, 7031339, TR()))
    case 13:
      # a pilgrim's staff
      +staff = U32.is_eq(x, 0) && between(y, (0 - 4 : U32), 9)
      sel(U32.is_eq(x, 0) && U32.is_eq(y, 10), 5914656, sel(staff, 9071162, TR()))
    case 12:
      # a Bard's lute
      +body = ell(x, y, 1, 1) || U32.is_eq(x, 1) && U32.is_eq(y, (0 - 1 : U32))
      +neck = U32.is_eq(x, 1) && between(y, 2, 4)
      sel(neck, 5913120, sel(body, sel(U32.is_eq(x, 0) && U32.is_eq(y, 0), 3811866, 13148232), TR()))
    case _:
      TR()

# a guest seen from the front (facing +x on screen: right, or mirrored) or
# the back. look bits: 0-2 folk (0 wizard, 1 knight, 2 elf, 3 dwarf,
# 4 halfling, 5 gnome, 6 orc, 7 commoner), 3 child, 4-6 tunic, 8-9 skin,
# 10 bearded, 11 straw hat, 12-13 facing, 14-15 outfit (0 adventurer,
# 1 noble with a cape, 2 merchant with a pack, 3 pilgrim with a cloak and
# staff), 16-17 item, 20-23 thought, 24 stepping, 25 sitting, 26 staff
# (27-28: which). Walking takes four frames: legs apart, passing (body up a
# pixel), apart the other way, passing. Smaller folk and children are
# shorter (sh rows), their hats and hair coming down with them.
def Art.hair(+k: U32) -> U32:
  match k:
    case 0:
      3811866
    case 1:
      6965290
    case 2:
      13146704
    case _:
      10107418

def Art.guest(+dx: U32, +dy: U32, +look: U32, +t: U32) -> U32:
  +folk = (look .&. 7 : U32)
  +child = Bool.not(U32.is_eq((look .&. 8 : U32), 0))
  +outfit = ((look >> 14n) .&. 3 : U32)
  +gnome = U32.is_eq(folk, 5)
  +orc = U32.is_eq(folk, 6)
  +face = ((look >> 12n) .&. 3 : U32)
  +left = U32.is_eq(face, 1) || U32.is_eq(face, 2)
  +backv = (face >= 2 : U32)
  +sit = Bool.not(U32.is_eq((look .&. 33554432 : U32), 0))
  +walk = Bool.not(U32.is_eq((look .&. 16777216 : U32), 0)) && Bool.not(sit)
  +staff = Bool.not(U32.is_eq((look .&. 67108864 : U32), 0))
  +sk = ((look >> 27n) .&. 3 : U32)
  +pilgrim = U32.is_eq(outfit, 3) && Bool.not(staff)
  +noble = U32.is_eq(outfit, 1) && Bool.not(staff)
  +it0 = ((look >> 16n) .&. 7 : U32)
  +it = sel(staff, (9 + sk : U32), sel(pilgrim && U32.is_eq(it0, 0), 13, it0))
  +fr = sel(walk, ((t >> 2n) .&. 3 : U32), 0)
  +bob = sel(U32.is_eq((fr .&. 1 : U32), 1), 1, 0)
  +h0 = (0 - dy + sel(sit, 2, 0) : U32)
  +h = (h0 - bob : U32)
  +x = sel(left, (0 - dx : U32), dx)
  +sh = U32.min((sel(U32.is_eq(folk, 3) || U32.is_eq(folk, 4), 2, sel(gnome, 3, 0)) + sel(child, 2, 0) : U32), 4)
  +uni = sel(U32.is_eq(sk, 0), 7031338, sel(U32.is_eq(sk, 1), 13660192, sel(U32.is_eq(sk, 2), 3166384, 11546704)))
  +tun = sel(staff, uni, sel(pilgrim, 9075296, sel(U32.is_eq(folk, 0), 5913248, Art.tunic(((look >> 4n) .&. 7 : U32)))))
  +skin = sel(orc, 7248448, Art.skin(((look >> 8n) .&. 3 : U32)))
  +hairc = sel(U32.is_eq(folk, 3), 11559978, sel(U32.is_eq(folk, 4), 7948832, sel(orc, 2105376,
    sel(U32.is_eq(folk, 7), Art.hair(((look >> 5n) .&. 3 : U32)), 6965290))))
  # legs: apart (frames 0, 2) or together (1, 3); the near leg is lighter;
  # halflings go barefoot
  +legtop = (2 - (sh >> 1n) + bob : U32)
  +apart = U32.is_eq((fr .&. 1 : U32), 0)
  +legs = between(h0, 0, legtop) && (apart && (U32.is_eq(x, (0 - 1 : U32)) || U32.is_eq(x, 1))
    || Bool.not(apart) && U32.is_eq(x, 0))
  +knees = U32.is_eq(h0, 3) && between(x, (0 - 1 : U32), 2) || U32.is_eq(h0, 2) && U32.is_eq(x, 2)
  +legat = sit && knees || Bool.not(sit) && legs
  +near = U32.is_eq(fr, 2) && slt(x, 0) || Bool.not(U32.is_eq(fr, 2)) && Bool.not(slt(x, 0))
  +legc = sel(U32.is_eq(folk, 4) && U32.is_eq(h0, 0), skin, sel(near || Bool.not(walk), 3811866, 2628880))
  +foot = U32.is_eq(h0, 0) && Bool.not(apart) && U32.is_eq(x, 1) && Bool.not(sit)
  # orcs are broad
  +bw = sel(orc && Bool.not(child), 3, 2)
  +lo = (3 - (sh >> 1n) : U32)
  +body = between(h, lo, (6 - sh : U32)) && (sabs(x) <= bw : U32)
  +belt = U32.is_eq(h, (4 - (sh >> 1n) : U32)) && (sabs(x) <= bw : U32)
  # the leading hand swings with the stride (or holds the item still)
  +hy = (4 - (sh >> 1n) : U32)
  +hx0 = (bw + 1 : U32)
  +hx = sel(opaque(Art.item(it, 0, 0)), hx0, sel(walk && U32.is_eq(fr, 2), (0 - hx0 : U32), hx0))
  +hand = U32.is_eq(x, hx) && U32.is_eq(h, hy) && (walk || Bool.not(U32.is_eq(it, 0)))
  +held = Art.item(it, (x - hx0 : U32), (h - hy - 1 : U32))
  +head = between(h, (7 - sh : U32), (9 - sh : U32)) && between(x, (0 - 1 : U32), 1)
  +eye = U32.is_eq(h, (8 - sh : U32)) && U32.is_eq(x, 1) && Bool.not(backv)
  +headc = sel(backv, hairc, skin)
  # hats and hair, on top of the head (row 10 - sh up)
  +r = (h + sh : U32)
  +pointy = (U32.is_eq(folk, 0) || gnome) && (U32.is_eq(r, 10) && between(x, (0 - 2 : U32), 2)
    || U32.is_eq(r, 11) && between(x, (0 - 1 : U32), 1)
    || U32.is_eq(r, 12) && between(x, (0 - 1 : U32), 0)
    || U32.is_eq(r, 13) && U32.is_eq(x, (0 - 1 : U32)))
  +star = U32.is_eq(folk, 0) && U32.is_eq(r, 11) && U32.is_eq(x, 0) && Bool.not(backv)
  +helm = U32.is_eq(folk, 1) && between(r, 8, 10) && between(x, (0 - 1 : U32), 1)
  +visor = U32.is_eq(folk, 1) && U32.is_eq(r, 8) && between(x, 0, 1) && Bool.not(backv)
  +plume = U32.is_eq(folk, 1) && between(r, 11, 12) && U32.is_eq(x, 0)
  +hooded = U32.is_eq(folk, 2) || pilgrim
  +hood = hooded && (between(r, 9, 10) && between(x, (0 - 1 : U32), 1)
    || U32.is_eq(x, (0 - 2 : U32)) && between(r, 7, 9) || backv && head)
  +ear = (U32.is_eq(folk, 2) || orc) && U32.is_eq(x, 2) && U32.is_eq(r, 8) && Bool.not(pilgrim)
  +cap = U32.is_eq(folk, 3) && between(r, 10, 11) && between(x, (0 - 1 : U32), 1)
  +straw = U32.is_eq(folk, 7) && Bool.not(U32.is_eq((look .&. 2048 : U32), 0))
    && (U32.is_eq(r, 10) && between(x, (0 - 2 : U32), 2) || U32.is_eq(r, 11) && between(x, (0 - 1 : U32), 1))
  +tuft = U32.is_eq(r, 10) && between(x, (0 - 1 : U32), 1) || U32.is_eq(r, 9) && U32.is_eq(x, (0 - 1 : U32))
  +hair = (U32.is_eq(folk, 4) || U32.is_eq(folk, 7)) && tuft
    || orc && (U32.is_eq(r, 10) && between(x, (0 - 1 : U32), 0) || U32.is_eq(r, 11) && U32.is_eq(x, (0 - 1 : U32)))
  +bearded = U32.is_eq(folk, 3) || gnome
    || (U32.is_eq(folk, 0) || U32.is_eq(folk, 7)) && Bool.not(U32.is_eq((look .&. 1024 : U32), 0)) && Bool.not(child)
  +beard = bearded && between(r, 7, 8) && between(x, (0 - 1 : U32), 1) && Bool.not(backv)
  +beardc = sel(gnome, 15263968, sel(U32.is_eq(folk, 0), 12632256, sel(U32.is_eq(folk, 3), 11559978, hairc)))
  +tusk = orc && U32.is_eq(r, 7) && U32.is_eq(x, 1) && Bool.not(backv)
  # a noble's cape and a merchant's pack, behind (or over the back)
  +behind = U32.is_eq(x, (0 - hx0 : U32))
  +cape = noble && (behind && between(h, (lo - 1 : U32), (7 - sh : U32)) || backv && body)
  +pack = U32.is_eq(outfit, 2) && Bool.not(staff) && between(h, (lo + 1 : U32), (6 - sh : U32))
    && (behind || backv && between(x, (0 - 1 : U32), 1))
  +bub = Art.bubble.go(Bool.not(U32.is_eq(((look >> 20n) .&. 15 : U32), 0)) && (h0 >= 15 : U32),
    ((look >> 20n) .&. 15 : U32), dx, h0)
  over(bub, over(held, sel(hand, skin, sel(star, 16766282, sel(pointy, sel(gnome, 13119536, 5913248),
    sel(visor, 3158064, sel(helm, 11581632, sel(plume, 13643824, sel(straw, 14200928,
    sel(hood, sel(pilgrim, 7039840, 3836474), sel(ear, skin,
    sel(cap, sel(staff, sel(U32.is_eq(sk, 0), 4880944, 9067056), 12595248),
    sel(hair, hairc, sel(tusk, 15263968, sel(eye, 2105376, sel(beard, beardc, sel(head, headc,
    sel(cape, sel(U32.is_eq(h, (lo - 1 : U32)), 14725184, 6957706), sel(pack, 8016432,
    sel(belt, sel(noble, 14725184, 4861466),
    sel(body, sel(backv && U32.is_eq(x, 0) && U32.is_eq(folk, 0), shade(tun, 200), tun),
    sel(legat, legc, sel(foot, legc, TR())))))))))))))))))))))))

# Riders
# ------
# An 8-bit rider code (bit 7 occupied, bits 0-2 folk, 3-4 tunic, 5-6 skin)
# turns back into the guest's look; a rider sits with its seat at (0, 0).

def Art.look_of(+code: U32) -> U32:
  ((code .&. 7) .|. (((code >> 3n) .&. 3) << 4n) .|. (((code >> 5n) .&. 3) << 8n) : U32)

def Art.rider.go(on: Bool, +dx: U32, +dy: U32, +code: U32) -> U32:
  match on:
    case True{}:
      Art.guest(dx, (dy - 3 : U32), Art.look_of(code), 0)
    case False{}:
      TR()

def Art.rider(+dx: U32, +dy: U32, +code: U32) -> U32:
  Art.rider.go(Bool.not(U32.is_eq((code .&. 128 : U32), 0)) && sle(dy, 0)
    && (sabs(dx) <= 3 : U32) && sle((0 - 14 : U32), dy), dx, dy, code)

def Art.cseat.go(near: Bool, +dx: U32, +dy: U32, +a: U32, +cx: U32, +cy: U32,
  +code: U32) -> U32:
  match near:
    case True{}:
      over(Art.rider((dx - cx : U32), (dy - cy + 2 : U32), code), Art.dragon(dx, dy, a))
    case False{}:
      TR()

# one dragon and its rider; pixels far from the seat skip the work
def Art.cseat(+dx: U32, +dy: U32, +a: U32, +code: U32) -> U32:
  +cx = wcos(a, 18)
  +cy = (wsin(a, 9) - 12 : U32)
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  Art.cseat.go((sabs(ex) <= 5 : U32) && between(ey, (0 - 16 : U32), 7), dx, dy, a, cx, cy, code)

def Art.front(+a: U32) -> Bool:
  Bool.not(neg(wsin(a, 9)))

def Art.byte(+w: U32, +i: U32) -> U32:
  match i:
    case 0:
      (w .&. 255 : U32)
    case 1:
      ((w >> 8n) .&. 255 : U32)
    case 2:
      ((w >> 16n) .&. 255 : U32)
    case _:
      (w >> 24n : U32)

def Art.code(+ra: U32, +rb: U32, +s: U32) -> U32:
  sel((s < 4 : U32), Art.byte(ra, s), Art.byte(rb, (s - 4 : U32)))

# UI
# --

# the carousel's turn while running: it speeds up, turns, slows down, and
# stops where it started (three turns in 448 ticks)
def Art.spin(+st: U32) -> U32:
  +ph = ((st >> 16n) .&. 3 : U32)
  +tm = U32.min((st .&. 65535 : U32), 447)
  +r = (448 - tm : U32)
  sel(U32.is_eq(ph, 1), sel((tm < 64 : U32), ((tm * tm) >> 6n : U32),
    sel((tm < 384 : U32), (64 + 2 * (tm - 64) : U32), (768 - ((r * r) >> 6n) : U32))), 0)

def Art.carousel(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +canopy = Art.cone(dx, dy, (0 - 30 : U32), 28, 16, 8077216, 15253568)
  +pole = (sabs(dx) <= 1 : U32) && between(dy, (0 - 32 : U32), (0 - 4 : U32))
  +top = ell(dx, (dy + 4 : U32), 26, 13)
  +side = ell(dx, dy, 26, 13) && sle((0 - 4 : U32), dy)
  +plank = U32.is_eq(((dx + dy * 2 + 256) .&. 7 : U32), 0)
  +flagp = U32.is_eq(dx, 0) && between(dy, (0 - 53 : U32), (0 - 46 : U32))
  +flag = between(dx, 1, 5) && between(dy, (0 - 53 : U32), (0 - 50 : U32))
  +a0 = Art.spin(st)
  +a1 = (a0 + 32 : U32)
  +a2 = (a0 + 64 : U32)
  +a3 = (a0 + 96 : U32)
  +a4 = (a0 + 128 : U32)
  +a5 = (a0 + 160 : U32)
  +a6 = (a0 + 192 : U32)
  +a7 = (a0 + 224 : U32)
  +c0 = Art.cseat(dx, dy, a0, Art.code(ra, rb, 0))
  +c1 = Art.cseat(dx, dy, a1, Art.code(ra, rb, 1))
  +c2 = Art.cseat(dx, dy, a2, Art.code(ra, rb, 2))
  +c3 = Art.cseat(dx, dy, a3, Art.code(ra, rb, 3))
  +c4 = Art.cseat(dx, dy, a4, Art.code(ra, rb, 4))
  +c5 = Art.cseat(dx, dy, a5, Art.code(ra, rb, 5))
  +c6 = Art.cseat(dx, dy, a6, Art.code(ra, rb, 6))
  +c7 = Art.cseat(dx, dy, a7, Art.code(ra, rb, 7))
  +f0 = Art.front(a0)
  +f1 = Art.front(a1)
  +f2 = Art.front(a2)
  +f3 = Art.front(a3)
  +f4 = Art.front(a4)
  +f5 = Art.front(a5)
  +f6 = Art.front(a6)
  +f7 = Art.front(a7)
  +fronts = over(sel(f0, c0, TR()), over(sel(f1, c1, TR()), over(sel(f2, c2, TR()),
    over(sel(f3, c3, TR()), over(sel(f4, c4, TR()), over(sel(f5, c5, TR()),
    over(sel(f6, c6, TR()), sel(f7, c7, TR()))))))))
  +backs = over(sel(f0, TR(), c0), over(sel(f1, TR(), c1), over(sel(f2, TR(), c2),
    over(sel(f3, TR(), c3), over(sel(f4, TR(), c4), over(sel(f5, TR(), c5),
    over(sel(f6, TR(), c6), sel(f7, TR(), c7))))))))
  +posts = U32.is_eq(((dx + 256) .&. 15 : U32), 0) && between(dy, (0 - 30 : U32), (0 - 6 : U32))
    && (sabs(dx) < 26 : U32)
  +m = ((dx + 256) .&. 7 : U32)
  +deep = sel(U32.is_eq(m, 0) || U32.is_eq(m, 7), 1, sel(U32.is_eq(m, 1) || U32.is_eq(m, 6), 3, 4))
  +rim0 = ell(dx, (dy + 30 : U32), 28, 14)
  +val = Bool.not(rim0) && ell(dx, (dy + 30 - deep : U32), 28, 14) && sle((0 - 30 : U32), dy)
  +lampy = Bool.not(rim0) && ell(dx, (dy + 29 : U32), 28, 14)
  +lamp = lampy && val && (U32.is_eq(m, 3) || U32.is_eq(m, 4))
  +lit = U32.is_eq(((((dx + 256) >> 3n) + (t >> 4n)) .&. 1 : U32), 0)
  +valc = sel(U32.is_eq((((dx + 256) >> 3n) .&. 1 : U32), 0), 8077216, 15253568)
  +valance = sel(lamp, sel(lit, E(16775360), 13148232), sel(val, sel(Bool.not(ell(dx, (dy + 31 - deep : U32), 28, 14)), shade(valc, 150), valc), TR()))
  over(valance, over(canopy, over(sel(flagp, 14737632, sel(flag, 13643824, TR())),
    over(fronts, over(sel(pole, 14725184, sel(posts, 14725184, TR())), over(backs,
      sel(top, sel(plank, 8014378, 11565637), sel(side, 7031338, TR()))))))))

def Art.sseat(+dx: U32, +dy: U32, +ringy: U32, +s: U32, +code: U32) -> U32:
  +a = (s * 32 + 16 : U32)
  +ex = (dx - wcos(a, 9) : U32)
  +ey = (dy - (ringy + wsin(a, 4)) : U32)
  Art.rider(ex, ey, sel((sabs(ex) <= 3 : U32) && between(ey, (0 - 14 : U32), 0), code, 0))

def Art.spire(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +base = Art.box(dx, dy, 0, 12, 5, 9602196, 8418172, 6708076)
  +tower = Art.cyl(dx, dy, (0 - 4 : U32), 5, 60, 7100042)
  +rune = (sabs(dx) <= 1 : U32) && U32.is_eq((((dy + 1024) + (t >> 1n)) .&. 15 : U32), 0)
  +orb = ell(dx, (dy + 70 : U32), 4, 4)
  +core = ell(dx, (dy + 71 : U32), 1, 1)
  # the ring rises slowly while running and drops back at the end
  +ph = U32.min((st .&. 65535 : U32), 511)
  +running = U32.is_eq(((st >> 16n) .&. 3 : U32), 1)
  +up = sel(running, sel((ph < 384 : U32), (div3(ph) >> 1n : U32), ((512 - ph) >> 1n : U32)), 0)
  +ringy = (0 - 8 - up : U32)
  +ring = ell(dx, (dy - ringy : U32), 10, 5) && Bool.not(ell(dx, (dy - ringy : U32), 6, 3))
  +ringside = ell(dx, (dy - ringy - 2 : U32), 10, 5) && Bool.not(ell(dx, (dy - ringy : U32), 10, 5))
    && sle(ringy, dy)
  +seat = ring && U32.is_eq(((dx + 64) .&. 3 : U32), 0)
  # the ring's far half passes behind the tower, its near half in front
  +far = slt(dy, ringy)
  +ringc = sel(seat, 12594224, sel(ring, 14198840, sel(ringside, 10122274, TR())))
  +front = sel(far, TR(), ringc)
  +back = sel(far, ringc, TR())
  +r0 = Art.sseat(dx, dy, ringy, 0, Art.code(ra, rb, 0))
  +r1 = Art.sseat(dx, dy, ringy, 1, Art.code(ra, rb, 1))
  +r2 = Art.sseat(dx, dy, ringy, 2, Art.code(ra, rb, 2))
  +r3 = Art.sseat(dx, dy, ringy, 3, Art.code(ra, rb, 3))
  +r4 = Art.sseat(dx, dy, ringy, 4, Art.code(ra, rb, 4))
  +r5 = Art.sseat(dx, dy, ringy, 5, Art.code(ra, rb, 5))
  +r6 = Art.sseat(dx, dy, ringy, 6, Art.code(ra, rb, 6))
  +r7 = Art.sseat(dx, dy, ringy, 7, Art.code(ra, rb, 7))
  +frontr = over(r0, over(r1, over(r2, over(r7, TR()))))
  +backr = over(r3, over(r4, over(r5, over(r6, TR()))))
  +glint = Bool.not(orb) && ell(dx, (dy + 70 : U32), 9, 8)
    && U32.is_eq((hash((dx + 64 : U32), ((dy + 128) + (t >> 3n) : U32)) .&. 31 : U32), 0)
  over(frontr, over(front, over(sel(core, E(16777215), sel(orb, E(12122367), sel(glint, E(15794175), TR()))),
    over(sel(rune && opaque(tower), 6287592, tower), over(backr, over(back, base))))))

def Art.potion(+dx: U32, +dy: U32, +t: U32) -> U32:
  +booth = Art.box(dx, dy, 0, 9, 9, 13144154, 10512954, 8015402)
  +awn = Art.box(dx, dy, (0 - 14 : U32), 11, 2, 4176048, 3316368, 2524016)
  +stripe = U32.is_eq(((((dx + dy * 2) + 256) >> 2n) .&. 1 : U32), 0)
  +awning = sel(opaque(awn), sel(stripe, awn, 15660784), TR())
  +post = (U32.is_eq(dx, (0 - 9 : U32)) || U32.is_eq(dx, 9)) && between(dy, (0 - 14 : U32), (0 - 4 : U32))
  +b1 = between(dx, (0 - 5 : U32), (0 - 4 : U32)) && between(dy, (0 - 14 : U32), (0 - 11 : U32))
  +b2 = between(dx, (0 - 1 : U32), 0) && between(dy, (0 - 15 : U32), (0 - 11 : U32))
  +b3 = between(dx, 3, 4) && between(dy, (0 - 14 : U32), (0 - 11 : U32))
  +sign = between(dx, (0 - 4 : U32), 4) && between(dy, (0 - 25 : U32), (0 - 20 : U32))
  +frame = sign && (U32.is_eq(sabs(dx), 4) || U32.is_eq(dy, (0 - 25 : U32)) || U32.is_eq(dy, (0 - 20 : U32)))
  +hang = U32.is_eq(sabs(dx), 3) && between(dy, (0 - 19 : U32), (0 - 17 : U32))
  +star = U32.is_eq(dx, 0) && between(dy, (0 - 24 : U32), (0 - 21 : U32))
    || between(dx, (0 - 1 : U32), 1) && U32.is_eq(dy, (0 - 23 : U32))
  +bub = U32.is_eq((hash((dx + 64 : U32), ((dy + 64 + (t >> 3n)) : U32)) .&. 31 : U32), 0)
    && between(dx, (0 - 2 : U32), 2) && between(dy, (0 - 30 : U32), (0 - 26 : U32))
  over(sel(bub, 12648447, TR()), over(sel(star, 16766282, sel(frame, 6961706, sel(sign, 6961312, sel(hang, 3813162, TR())))),
    over(awning, over(sel(b1, 14168128, sel(b2, 4176000, sel(b3, 4215008, TR()))),
      over(sel(post, 6961706, TR()), booth)))))

def Art.tavern(+dx: U32, +dy: U32, +t: U32) -> U32:
  +walls = Art.box(dx, dy, 0, 10, 11, 15259824, 15259824, 13154448)
  +beam = U32.is_eq(dx, 0) || U32.is_eq(sabs(dx), 10) || U32.is_eq(sabs(dx), 5)
  +wallc = sel(opaque(walls) && beam, 5913120, walls)
  +door = between(dx, (0 - 7 : U32), (0 - 4 : U32)) && between(dy, (0 - 7 : U32), 3)
    && sle((0 - 7 : U32), dy)
  # the thatched roof: a pyramid over the walls
  +ax = sabs(dx)
  +apex = (0 - 30 : U32)
  +upper = (apex + ((ax * 20) >> 4n) : U32)
  +lower = (0 - 11 + ((13 - ax) >> 1n) : U32)
  +roof = (ax <= 13 : U32) && sle(upper, dy) && sle(dy, lower)
  +thatch = U32.is_eq(((dy + ax + 256) .&. 3 : U32), 0)
  +roofc = sel(neg(dx), sel(thatch, 11045432, 13148232), sel(thatch, 8420896, 10122800))
  +chim = between(dx, 5, 7) && between(dy, (0 - 30 : U32), (0 - 20 : U32))
  +sm = (t .&. 63 : U32)
  +smoke = ell((dx - 6 : U32), (dy + 33 + (sm >> 2n) : U32), 2, 2)
    || ell((dx - 7 : U32), (dy + 38 + (sm >> 3n) : U32), 1, 1)
  +arm = between(dx, 9, 16) && U32.is_eq(dy, (0 - 17 : U32)) || U32.is_eq(dx, 10) && U32.is_eq(dy, (0 - 16 : U32))
  +chain = (U32.is_eq(dx, 12) || U32.is_eq(dx, 15)) && U32.is_eq(dy, (0 - 16 : U32))
  +board = between(dx, 11, 16) && between(dy, (0 - 15 : U32), (0 - 9 : U32))
  +edge = board && (U32.is_eq(dx, 11) || U32.is_eq(dx, 16) || U32.is_eq(dy, (0 - 15 : U32)) || U32.is_eq(dy, (0 - 9 : U32)))
  +mug = between(dx, 13, 14) && between(dy, (0 - 12 : U32), (0 - 11 : U32))
  +foam = between(dx, 13, 14) && U32.is_eq(dy, (0 - 13 : U32))
  +grip = U32.is_eq(dx, 15) && U32.is_eq(dy, (0 - 12 : U32))
  +signc = sel(edge, 5913120, sel(foam, 16316656, sel(mug, 14721072, sel(grip, 14721072, 9127187))))
  over(sel(arm || chain, 3158064, sel(board, signc, TR())),
    over(sel(smoke, 13421772, TR()), over(sel(chim, 8016192, TR()),
    sel(roof, roofc, sel(door, 5913120, wallc)))))

# The Privy: a narrow plank outhouse under a steep mossy shingle roof, a
# crescent moon cut in its door (lamplit from inside), a rain barrel beside
def Art.privy(+dx: U32, +dy: U32, +t: U32) -> U32:
  +ax = sabs(dx)
  +walls = Art.box(dx, dy, 0, 6, 16, 9474192, 11565120, 9067056)
  +plank = U32.is_eq(((dx + 258) .&. 3 : U32), 0)
  +wallc = sel(opaque(walls) && plank && Bool.not(U32.is_eq(dx, 0)), shade(walls, 170), walls)
  +ry = (dy + (ax >> 1n) : U32)
  +door = between(dx, (0 - 5 : U32), (0 - 2 : U32)) && between(ry, (0 - 9 : U32), 2)
  +moon = U32.is_eq(dx, (0 - 4 : U32)) && between(ry, (0 - 8 : U32), (0 - 6 : U32))
    || U32.is_eq(dx, (0 - 3 : U32)) && (U32.is_eq(ry, (0 - 8 : U32)) || U32.is_eq(ry, (0 - 6 : U32)))
  +knob = U32.is_eq(dx, (0 - 2 : U32)) && U32.is_eq(ry, (0 - 3 : U32))
  +upper = (0 - 27 + ((ax * 3) >> 1n) : U32)
  +lower = (0 - 13 + ((8 - ax) >> 1n) : U32)
  +roof = (ax <= 8 : U32) && sle(upper, dy) && sle(dy, lower)
  +row = U32.is_eq(((dy + 256) % 3 : U32), 0)
  +moss = U32.is_eq((hash((dx + 64 : U32), (dy + 64 : U32)) .&. 7 : U32), 0)
  +roofc = sel(moss, 7248464, sel(neg(dx), sel(row, 8275496, 10115636), sel(row, 6436382, 8012838)))
  +finial = U32.is_eq(dx, 0) && between(dy, (0 - 30 : U32), (0 - 27 : U32))
  +barrel = Art.cyl((dx - 9 : U32), dy, 2, 3, 6, 6965802)
  +hoop = opaque(barrel) && (U32.is_eq(dy, (0 - 1 : U32)) || U32.is_eq(dy, (0 - 3 : U32)))
  over(sel(finial, 14725184, sel(roof, roofc, TR())),
    over(sel(moon, 16767056, sel(knob, 14725184, sel(door, 4860948, TR()))),
    over(wallc, sel(hoop, 3158064, barrel))))

# The Healer's Tent: a round white tent under a green-striped roof, its flap
# open, a herb-leaf pennant on the pole
def Art.healer(+dx: U32, +dy: U32, +t: U32) -> U32:
  +walls = Art.cyl(dx, dy, 0, 9, 8, 15263960)
  +roof = Art.cone(dx, dy, (0 - 8 : U32), 11, 12, 15790312, 4889178)
  +door = between(dx, (0 - 4 : U32), 0) && between(dy, (0 - 7 : U32), 2) && sle(sabs((dx + 2 : U32)), (8 + dy : U32))
  +pole = U32.is_eq(dx, 0) && between(dy, (0 - 27 : U32), (0 - 19 : U32))
  +wave = (((t >> 3n) + dx) .&. 1 : U32)
  +leaf = between(dx, 1, 6) && (U32.is_eq(dy, (0 - 26 + wave : U32)) && between(dx, 2, 5)
    || U32.is_eq(dy, (0 - 25 + wave : U32)) || U32.is_eq(dy, (0 - 24 + wave : U32)) && between(dx, 2, 4))
  +vein = U32.is_eq(dy, (0 - 25 + wave : U32)) && between(dx, 2, 5)
  over(sel(vein, 3830352, sel(leaf, 6340682, sel(pole, 7031339, TR()))),
    over(roof, sel(door, 3825200, walls)))

# The Wisp Seller: a little cart, its wisps bobbing on strings above it
def Art.wisp1(+dx: U32, +dy: U32, +ox: U32, +top: U32, +c: U32, +t: U32, +ph: U32) -> U32:
  +bob = ((((t >> 4n) + ph) .&. 3) >> 1n : U32)
  +oy = (top - bob : U32)
  +orb = ell((dx - ox : U32), (dy - oy : U32), 2, 2)
  +core = U32.is_eq(dx, ox) && U32.is_eq(dy, oy)
  +string = U32.is_eq(dx, ox) && sle((oy + 2 : U32), dy) && sle(dy, (0 - 8 : U32))
  sel(core, E(16777215), sel(orb, E(c), sel(string, 12632256, TR())))

def Art.wisps(+dx: U32, +dy: U32, +t: U32) -> U32:
  +cart = Art.box(dx, dy, (0 - 2 : U32), 8, 6, 11567184, 9067056, 7031338)
  +wheel = ell((dx + 5 : U32), (dy - 1 : U32), 2, 2) || ell((dx - 5 : U32), (dy - 1 : U32), 2, 2)
  +hub = U32.is_eq(dx, (0 - 5 : U32)) && U32.is_eq(dy, 1) || U32.is_eq(dx, 5) && U32.is_eq(dy, 1)
  +w1 = Art.wisp1(dx, dy, (0 - 5 : U32), (0 - 20 : U32), 6352127, t, 0)
  +w2 = Art.wisp1(dx, dy, (0 - 1 : U32), (0 - 25 : U32), 16748760, t, 1)
  +w3 = Art.wisp1(dx, dy, 3, (0 - 21 : U32), 16766282, t, 2)
  +w4 = Art.wisp1(dx, dy, 6, (0 - 26 : U32), 12623103, t, 3)
  over(w1, over(w2, over(w3, over(w4, sel(hub, 14725184, sel(wheel, 3811866, cart))))))

# Enchanted Ices: a stall under a frosty striped awning, a great cone on its
# roof, sparkles of frost
def Art.ices(+dx: U32, +dy: U32, +t: U32) -> U32:
  +booth = Art.box(dx, dy, 0, 9, 9, 14737632, 11591910, 8434880)
  +awn = Art.box(dx, dy, (0 - 14 : U32), 11, 2, 12640255, 10534135, 8428530)
  +stripe = U32.is_eq(((((dx + dy * 2) + 256) >> 2n) .&. 1 : U32), 0)
  +awning = sel(opaque(awn), sel(stripe, awn, 16316664), TR())
  +cone = sle((0 - 26 : U32), dy) && sle(dy, (0 - 19 : U32)) && (sabs(dx) * 2 <= ((0 - 19) - dy : U32) : U32)
  +scoop = ell(dx, (dy + 28 : U32), 4, 3)
  +mint = ell((dx + 1 : U32), (dy + 31 : U32), 3, 2)
  +spark = U32.is_eq((hash((dx + 64 : U32), ((dy + 64) + (t >> 4n) : U32)) .&. 63 : U32), 0)
    && between(dx, (0 - 9 : U32), 9) && between(dy, (0 - 34 : U32), (0 - 16 : U32))
  +post = (U32.is_eq(dx, (0 - 9 : U32)) || U32.is_eq(dx, 9)) && between(dy, (0 - 14 : U32), (0 - 4 : U32))
  over(sel(spark, 16777215, TR()), over(sel(mint, 10085546, sel(scoop, 16758488, sel(cone, 14200928, TR()))),
    over(awning, over(sel(post, 7031338, TR()), booth))))

# signed shift right, for rotations
def Art.running(+st: U32) -> Bool:
  U32.is_eq(((st >> 16n) .&. 3 : U32), 1)

def Art.tm(+st: U32) -> U32:
  (st .&. 65535 : U32)

# A-frame legs from (+-w0, 0) up to a hub at height hy: w0 * (hy + dy) / hy
# wide at dy, given k = w0 * 256 / hy
def Art.leg(+dx: U32, +dy: U32, +hy: U32, +k: U32) -> Bool:
  +w = (((hy + dy) * k) >> 8n : U32)
  between(dy, (0 - hy : U32), 0) && (sabs((sabs(dx) - w : U32)) <= 1 : U32)

# The Wheel of Stars: a wheel on two A-frames, its rim twinkling gold and
# blue, eight gondolas hanging level as it turns twice
def Art.wheel.gon.go(near: Bool, +ex: U32, +ey: U32, +code: U32) -> U32:
  match near:
    case True{}:
      +hang = U32.is_eq(ex, 0) && between(ey, 0, 1)
      +canopy = U32.is_eq(ey, 2) && (sabs(ex) <= 3 : U32)
      +posts = U32.is_eq(sabs(ex), 3) && between(ey, 3, 9)
      +front = between(ey, 10, 13) && (sabs(ex) <= 3 : U32)
      +rider = Art.rider(ex, (ey - 12 : U32), code)
      over(sel(front, sel(U32.is_eq(ey, 10), 14725184, 4219088), sel(canopy, 14725184, sel(posts, 3166384, TR()))),
        over(rider, sel(hang, 3158064, TR())))
    case False{}:
      TR()

def Art.wheel.gon(+dx: U32, +dy: U32, +a: U32, +code: U32) -> U32:
  +ex = (dx - wcos(a, 30) : U32)
  +ey = (dy - (0 - 48 + wsin(a, 30)) : U32)
  Art.wheel.gon.go((sabs(ex) <= 4 : U32) && between(ey, (0 - 3 : U32), 14), ex, ey, code)

def Art.wheel(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +a0 = sel(Art.running(st), ((Art.tm(st) * 205) >> 8n : U32), 0)
  +hy = (dy + 48 : U32)
  +rim = ell(dx, hy, 32, 32) && Bool.not(ell(dx, hy, 29, 29))
  +inner = ell(dx, hy, 13, 13) && Bool.not(ell(dx, hy, 11, 11))
  +inr = ell(dx, hy, 29, 29)
  +spoke = inr && (U32.is_eq(dx, 0) || U32.is_eq(hy, 0) || U32.is_eq(sabs(dx), sabs(hy)))
  +hub = ell(dx, hy, 3, 3)
  +lit = U32.is_eq((((((dx + 64) >> 2n) + ((dy + 128) >> 2n)) + (t >> 4n)) .&. 1 : U32), 0)
  +legs = Art.leg(dx, dy, 48, 107)
  +base = over(Art.box((dx + 20 : U32), dy, 0, 4, 3, 9602196, 8418172, 6708076),
    Art.box((dx - 20 : U32), dy, 0, 4, 3, 9602196, 8418172, 6708076))
  +g0 = Art.wheel.gon(dx, dy, a0, Art.code(ra, rb, 0))
  +g1 = Art.wheel.gon(dx, dy, (a0 + 32 : U32), Art.code(ra, rb, 1))
  +g2 = Art.wheel.gon(dx, dy, (a0 + 64 : U32), Art.code(ra, rb, 2))
  +g3 = Art.wheel.gon(dx, dy, (a0 + 96 : U32), Art.code(ra, rb, 3))
  +g4 = Art.wheel.gon(dx, dy, (a0 + 128 : U32), Art.code(ra, rb, 4))
  +g5 = Art.wheel.gon(dx, dy, (a0 + 160 : U32), Art.code(ra, rb, 5))
  +g6 = Art.wheel.gon(dx, dy, (a0 + 192 : U32), Art.code(ra, rb, 6))
  +g7 = Art.wheel.gon(dx, dy, (a0 + 224 : U32), Art.code(ra, rb, 7))
  +gons = over(g0, over(g1, over(g2, over(g3, over(g4, over(g5, over(g6, g7)))))))
  +frame = sel(hub, sel(U32.is_eq(dx, 0) && U32.is_eq(hy, 0), 16777215, 14725184),
    sel(rim, sel(lit, E(16766282), E(6320595)), sel(legs, 5913120, sel(inner, 12092939, sel(spoke, 11053224, TR())))))
  over(gons, over(frame, base))

# The Griffin Swing: a griffin-headed ship on a long arm, swinging higher
# and higher and back to rest; eight riders along its deck
def Art.swing.hull(+ux: U32, +uy: U32, +t: U32) -> U32:
  +hull = ell(ux, uy, 18, 7) && sle(0, uy)
  +deck = U32.is_eq(uy, 0) && (sabs(ux) <= 18 : U32)
  +plank = U32.is_eq(((ux + 64) .&. 3 : U32), 0)
  +trim = U32.is_eq(uy, 1) && (sabs(ux) <= 17 : U32)
  +head = between(ux, 17, 21) && between(uy, (0 - 7 : U32), (0 - 1 : U32)) && Bool.not(U32.is_eq(ux, 21) && slt(uy, (0 - 5 : U32)))
  +beak = between(ux, 22, 23) && between(uy, (0 - 5 : U32), (0 - 4 : U32))
  +eye = U32.is_eq(ux, 20) && U32.is_eq(uy, (0 - 5 : U32))
  +crest = between(ux, 17, 19) && U32.is_eq(uy, (0 - 8 : U32))
  +tail = between(ux, (0 - 22 : U32), (0 - 18 : U32)) && between(uy, (0 - 6 : U32), (0 - 1 : U32))
    && sle((0 - 6 : U32), (uy - (ux + 18) : U32))
  sel(eye, 2105376, sel(beak, 14725184, sel(crest, 14725184, sel(head, 15263968, sel(tail, 12092939,
    sel(deck, 11567184, sel(trim, 14725184, sel(hull, sel(plank, 7027228, 9062442), TR()))))))))

def Art.swing.rider(+dx: U32, +dy: U32, +bx: U32, +by: U32, +c: U32, +s: U32, +ux: U32, +code: U32) -> U32:
  +rx = (bx + sar((ux * c : U32), 8n) : U32)
  +ry = (by + sar((ux * s : U32), 8n) : U32)
  Art.rider((dx - rx : U32), (dy - ry + 1 : U32), code)

def Art.swing(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +tm = Art.tm(st)
  +amp = sel(Art.running(st), U32.min(((U32.min(tm, (480 - tm : U32)) * 102) >> 8n : U32), 44), 0)
  +th = wsin((tm * 3 : U32), amp)
  +c = wcos(th, 256)
  +s = wsin(th, 256)
  +bx = wsin(th, 32)
  +by = (0 - 56 + wcos(th, 32) : U32)
  +ex = (dx - bx : U32)
  +ey = (dy - by : U32)
  +ux = sar(((ex * c) + (ey * s) : U32), 8n)
  +uy = sar(((ey * c) - (ex * s) : U32), 8n)
  +hull = Art.swing.hull(ux, uy, t)
  +front = sel(slt(0, uy), hull, TR())
  +r0 = Art.swing.rider(dx, dy, bx, by, c, s, (0 - 14 : U32), Art.code(ra, rb, 0))
  +r1 = Art.swing.rider(dx, dy, bx, by, c, s, (0 - 10 : U32), Art.code(ra, rb, 1))
  +r2 = Art.swing.rider(dx, dy, bx, by, c, s, (0 - 6 : U32), Art.code(ra, rb, 2))
  +r3 = Art.swing.rider(dx, dy, bx, by, c, s, (0 - 2 : U32), Art.code(ra, rb, 3))
  +r4 = Art.swing.rider(dx, dy, bx, by, c, s, 2, Art.code(ra, rb, 4))
  +r5 = Art.swing.rider(dx, dy, bx, by, c, s, 6, Art.code(ra, rb, 5))
  +r6 = Art.swing.rider(dx, dy, bx, by, c, s, 10, Art.code(ra, rb, 6))
  +r7 = Art.swing.rider(dx, dy, bx, by, c, s, 14, Art.code(ra, rb, 7))
  +riders = over(r0, over(r1, over(r2, over(r3, over(r4, over(r5, over(r6, r7)))))))
  # the arm from the pivot (0, -56) to the ship
  +px = dx
  +py = (dy + 56 : U32)
  +cross = ((px * (by + 56)) - (py * bx) : U32)
  +dot = ((px * bx) + (py * (by + 56)) : U32)
  +arm = (sabs(cross) <= 36 : U32) && sle(0, dot) && sle(dot, 1024)
  +pivot = ell(dx, (dy + 56 : U32), 2, 2)
  +legs = Art.leg(dx, dy, 56, 82)
  +bar = U32.is_eq(dy, (0 - 30 : U32)) && (sabs(dx) <= 9 : U32)
  +base = over(Art.box((dx + 18 : U32), dy, 0, 4, 3, 9602196, 8418172, 6708076),
    Art.box((dx - 18 : U32), dy, 0, 4, 3, 9602196, 8418172, 6708076))
  over(front, over(riders, over(hull, over(sel(pivot, 14725184, sel(arm, 6970184, TR())),
    over(sel(legs || bar, 5913120, TR()), base)))))

# The Wizard's Whirl: a bench between two star-topped pillars that swings
# ever wider until it goes right over, riders upside down at the top
def Art.whirl.rider(+dx: U32, +dy: U32, +rx: U32, +by: U32, +inv: Bool, +code: U32) -> U32:
  +ey = (dy - by : U32)
  Art.rider((dx - rx : U32), sel(inv, (0 - ey - 13 : U32), ey), code)

def Art.whirl(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +tm = Art.tm(st)
  +amp = sel(Art.running(st), U32.min((U32.min(tm, (420 - tm : U32)) * 2 : U32), 200), 0)
  +a = wsin((tm * 3 : U32), amp)
  +off = wcos(a, 14)
  +by = (0 - 32 + off : U32)
  +inv = neg(off)
  +bench = (sabs(dx) <= 12 : U32) && between((dy - by : U32), 0, 2)
  +rim = bench && U32.is_eq((dy - by : U32), sel(inv, 2, 0))
  +rod = U32.is_eq(sabs(dx), 12) && (between(dy, by, (0 - 32 : U32)) || between(dy, (0 - 32 : U32), by))
  +pl = Art.cyl((dx + 14 : U32), dy, 0, 3, 36, 6957706)
  +pr = Art.cyl((dx - 14 : U32), dy, 0, 3, 36, 6957706)
  +starl = U32.is_eq((sabs((dx + 14 : U32)) + sabs((dy + 40 : U32)) : U32), 2) || U32.is_eq(dx, (0 - 14 : U32)) && U32.is_eq(dy, (0 - 40 : U32))
  +starr = U32.is_eq((sabs((dx - 14 : U32)) + sabs((dy + 40 : U32)) : U32), 2) || U32.is_eq(dx, 14) && U32.is_eq(dy, (0 - 40 : U32))
  +axle = U32.is_eq(dy, (0 - 32 : U32)) && (sabs(dx) <= 13 : U32)
  +spark = Art.running(st) && ell(dx, (dy + 32 : U32), 20, 18) && Bool.not(ell(dx, (dy + 32 : U32), 16, 15))
    && U32.is_eq((hash((dx + 64 : U32), ((dy + 64) + (t >> 2n) : U32)) .&. 15 : U32), 0)
  +f0 = Art.whirl.rider(dx, dy, (0 - 9 : U32), by, inv, Art.code(ra, rb, 0))
  +f1 = Art.whirl.rider(dx, dy, (0 - 3 : U32), by, inv, Art.code(ra, rb, 1))
  +f2 = Art.whirl.rider(dx, dy, 3, by, inv, Art.code(ra, rb, 2))
  +f3 = Art.whirl.rider(dx, dy, 9, by, inv, Art.code(ra, rb, 3))
  +b0 = Art.whirl.rider(dx, dy, (0 - 6 : U32), (by - 2 : U32), inv, Art.code(ra, rb, 4))
  +b1 = Art.whirl.rider(dx, dy, 0, (by - 2 : U32), inv, Art.code(ra, rb, 5))
  +b2 = Art.whirl.rider(dx, dy, 6, (by - 2 : U32), inv, Art.code(ra, rb, 6))
  +base = Art.box(dx, dy, 0, 14, 3, 7035000, 5919584, 4870480)
  over(sel(spark, E(sel(U32.is_eq((t .&. 8 : U32), 0), 16777215, 12623103)), TR()),
    over(sel(rim, 14725184, sel(bench, 4860000, TR())), over(f0, over(f1, over(f2, over(f3,
    over(b0, over(b1, over(b2, over(sel(starl || starr, 16766282, sel(rod, 11053224, sel(axle, 14725184, TR()))),
    over(pl, over(pr, base))))))))))))

# The Dragon's Eyrie: a stone tower with a red dragon perched on top; the
# glass cabin rises around it, turns slowly at the top and comes down
def Art.eseat(+dx: U32, +dy: U32, +ringy: U32, +a: U32, +code: U32) -> U32:
  +ex = (dx - wcos(a, 9) : U32)
  +ey = (dy - (ringy + wsin(a, 4)) : U32)
  Art.rider(ex, ey, sel((sabs(ex) <= 3 : U32) && between(ey, (0 - 14 : U32), 0), code, 0))

def Art.eyrie(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +tm = U32.min(Art.tm(st), 599)
  +run = Art.running(st)
  +up = sel(run, sel((tm < 210 : U32), ((tm * 234) >> 10n : U32), sel((tm < 390 : U32), 48, (((599 - tm) * 234) >> 10n : U32))), 0)
  +ringy = (0 - 8 - up : U32)
  +rot = sel(run, (tm >> 1n : U32), 0)
  +tower = Art.cyl(dx, dy, (0 - 2 : U32), 6, 64, 9079446)
  +course = U32.is_eq(((dy + 1024) .&. 7 : U32), 0)
  +slit = U32.is_eq(dx, 0) && U32.is_eq(((dy + 1024) .&. 15 : U32), 4) && slt(dy, (0 - 10 : U32))
  +towerc = sel(opaque(tower) && slit, 2105376, sel(opaque(tower) && course, shade(tower, 180), tower))
  +cap = ell(dx, (dy + 68 : U32), 8, 4) || (sabs(dx) <= 8 : U32) && between(dy, (0 - 70 : U32), (0 - 67 : U32))
    && U32.is_eq(((dx + 64) .&. 3 : U32), 0)
  # the dragon, wings beating slowly
  +flap = ((t >> 4n) .&. 1 : U32)
  +body = ell(dx, (dy + 74 : U32), 4, 2)
  +neck = between(dx, 3, 5) && between(dy, (0 - 79 : U32), (0 - 75 : U32))
  +head = between(dx, 5, 8) && between(dy, (0 - 81 : U32), (0 - 79 : U32))
  +wing = between(sabs(dx), 3, 11) && U32.is_eq(dy, (0 - 77 - flap - ((sabs(dx) - 3) >> 1n) : U32))
    || between(sabs(dx), 4, 9) && U32.is_eq(dy, (0 - 76 - flap - ((sabs(dx) - 3) >> 1n) : U32))
  +deye = U32.is_eq(dx, 7) && U32.is_eq(dy, (0 - 80 : U32))
  +dragon = sel(deye, 16766282, sel(head || neck || body, 12595248, sel(wing, 9056288, TR())))
  +ring = ell(dx, (dy - ringy : U32), 12, 6) && Bool.not(ell(dx, (dy - ringy : U32), 7, 3))
  +glass = ring && U32.is_eq(((dx + 64) .&. 3 : U32), 1)
  +far = slt(dy, ringy)
  +ringc = sel(glass, 10538751, sel(ring, 4221088, TR()))
  +s0 = Art.eseat(dx, dy, ringy, (rot + 16 : U32), Art.code(ra, rb, 0))
  +s1 = Art.eseat(dx, dy, ringy, (rot + 48 : U32), Art.code(ra, rb, 1))
  +s2 = Art.eseat(dx, dy, ringy, (rot + 80 : U32), Art.code(ra, rb, 2))
  +s3 = Art.eseat(dx, dy, ringy, (rot + 112 : U32), Art.code(ra, rb, 3))
  +s4 = Art.eseat(dx, dy, ringy, (rot + 144 : U32), Art.code(ra, rb, 4))
  +s5 = Art.eseat(dx, dy, ringy, (rot + 176 : U32), Art.code(ra, rb, 5))
  +s6 = Art.eseat(dx, dy, ringy, (rot + 208 : U32), Art.code(ra, rb, 6))
  +s7 = Art.eseat(dx, dy, ringy, (rot + 240 : U32), Art.code(ra, rb, 7))
  +f0 = Art.front((rot + 16 : U32))
  +f1 = Art.front((rot + 48 : U32))
  +f2 = Art.front((rot + 80 : U32))
  +f3 = Art.front((rot + 112 : U32))
  +f4 = Art.front((rot + 144 : U32))
  +f5 = Art.front((rot + 176 : U32))
  +f6 = Art.front((rot + 208 : U32))
  +f7 = Art.front((rot + 240 : U32))
  +fronts = over(sel(f0, s0, TR()), over(sel(f1, s1, TR()), over(sel(f2, s2, TR()), over(sel(f3, s3, TR()),
    over(sel(f4, s4, TR()), over(sel(f5, s5, TR()), over(sel(f6, s6, TR()), sel(f7, s7, TR()))))))))
  +backs = over(sel(f0, TR(), s0), over(sel(f1, TR(), s1), over(sel(f2, TR(), s2), over(sel(f3, TR(), s3),
    over(sel(f4, TR(), s4), over(sel(f5, TR(), s5), over(sel(f6, TR(), s6), sel(f7, TR(), s7))))))))
  +base = Art.box(dx, dy, 0, 12, 4, 9602196, 8418172, 6708076)
  over(dragon, over(sel(far, TR(), ringc), over(fronts, over(sel(cap, 10132122, towerc),
    over(backs, over(sel(far, ringc, TR()), base))))))

# an iso box of any size on (0, base): top diamond half-width r, height h
def Art.cart(+dx: U32, +dy: U32, +cx: U32, +cy: U32, +c0: U32, +c1: U32, +c2: U32, +c3: U32) -> U32:
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  +body = between(ex, (0 - 9 : U32), 9) && between(ey, 0, 3)
  +trim = body && U32.is_eq(ey, 0)
  +r0 = Art.rider((ex + 6 : U32), (ey + 1 : U32), c0)
  +r1 = Art.rider((ex + 2 : U32), (ey + 1 : U32), c1)
  +r2 = Art.rider((ex - 2 : U32), (ey + 1 : U32), c2)
  +r3 = Art.rider((ex - 6 : U32), (ey + 1 : U32), c3)
  over(sel(trim, 12092939, sel(body, 5387882, TR())), over(r0, over(r1, over(r2, r3))))

def Art.crypt(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +ph = ((st >> 16n) .&. 3 : U32)
  +walls = Art.box2(dx, dy, 0, 26, 18, 7039866, 6316656, 4868698)
  +course = opaque(walls) && U32.is_eq(((dy + 1024) .&. 3 : U32), 0) && slt(dy, (0 - 2 : U32))
  +ax = sabs(dx)
  +upper = (0 - 44 + ((ax * 3) >> 2n) : U32)
  +lower = (0 - 18 + ((26 - ax) >> 1n) : U32)
  +roof = (ax <= 26 : U32) && sle(upper, dy) && sle(dy, lower)
  +slate = U32.is_eq(((dy + ax + 1024) .&. 3 : U32), 0)
  +moss = U32.is_eq((hash((dx + 64 : U32), (dy + 64 : U32)) .&. 7 : U32), 0)
  +roofc = sel(moss, 4880944, sel(neg(dx), sel(slate, 3815002, 4868698), sel(slate, 2894404, 3815002)))
  +spire = U32.is_eq(dx, 0) && between(dy, (0 - 54 : U32), (0 - 44 : U32))
  +orb = ell(dx, (dy + 56 : U32), 2, 2)
  +glow = Art.running(st) && Bool.not(U32.is_eq((hash((t >> 3n : U32), 3) .&. 3 : U32), 0))
  +win = (U32.is_eq(dx, (0 - 20 : U32)) || U32.is_eq(dx, 20) || U32.is_eq(dx, (0 - 6 : U32)) || U32.is_eq(dx, 6))
    && between((dy + 10 - ((26 - ax) >> 1n) : U32), 0, 3)
  +door = between(dx, (0 - 16 : U32), (0 - 10 : U32)) && between((dy - ((26 - ax) >> 1n) : U32), (0 - 10 : U32), 0)
    && sle((0 - 12 : U32), ((dy - ((26 - ax) >> 1n)) - sabs((dx + 13 : U32)) : U32))
  +torch = (U32.is_eq(dx, (0 - 18 : U32)) || U32.is_eq(dx, (0 - 8 : U32))) && between((dy - ((26 - ax) >> 1n) : U32), (0 - 8 : U32), (0 - 6 : U32))
  +flame = (U32.is_eq(dx, (0 - 18 : U32)) || U32.is_eq(dx, (0 - 8 : U32))) && U32.is_eq((dy - ((26 - ax) >> 1n) : U32), (0 - 9 - ((t >> 2n) .&. 1) : U32))
  +carts = sel(U32.is_eq(ph, 1), TR(),
    over(Art.cart(dx, dy, (0 - 8 : U32), 6, Art.code(ra, rb, 0), Art.code(ra, rb, 1), Art.code(ra, rb, 2), Art.code(ra, rb, 3)),
      Art.cart(dx, dy, 12, 11, Art.code(ra, rb, 4), Art.code(ra, rb, 5), Art.code(ra, rb, 6), Art.code(ra, rb, 7))))
  over(carts, over(sel(flame, E(7864234), sel(torch, 3811866, TR())),
    over(sel(orb, E(7864234), sel(spire, 2894404, sel(roof, roofc, TR()))),
    sel(door, sel(glow, E(3448136), 1579032), sel(win, sel(glow, E(7864234), 1579032), sel(course, shade(walls, 170), walls))))))

# The Golem Bumpers: stone golem cars bumping about an arena with a glowing
# grid; parked in a row between rides
def Art.golem.go(near: Bool, +ex: U32, +ey: U32, +code: U32, +hue: U32) -> U32:
  match near:
    case True{}:
      +car = ell(ex, ey, 5, 3)
      +top = ell(ex, (ey + 1 : U32), 4, 2)
      +eye = U32.is_eq(ey, 0) && U32.is_eq(sabs(ex), 2)
      over(sel(eye, E(hue), TR()), over(Art.rider(ex, (ey - 1 : U32), code), sel(top, 10132122, sel(car, 7039866, TR()))))
    case False{}:
      TR()

def Art.golem(+dx: U32, +dy: U32, +cx: U32, +cy: U32, +code: U32, +hue: U32) -> U32:
  +ex = (dx - cx : U32)
  +ey = (dy - cy : U32)
  Art.golem.go((sabs(ex) <= 5 : U32) && between(ey, (0 - 14 : U32), 3), ex, ey, code, hue)

def Art.bumpers(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +run = Art.running(st)
  +tm = Art.tm(st)
  +ax = sabs(dx)
  +d = (ax + 2 * sabs((dy + 2 : U32)) : U32)
  +floor = (d <= 26 : U32)
  +grid = floor && (U32.is_eq(((dx + dy * 2 + 1024) .&. 7 : U32), 0) || U32.is_eq(((dx - dy * 2 + 1024) .&. 7 : U32), 0))
  +rim = (d <= 30 : U32) && Bool.not(floor)
  +rimside = Bool.not(floor) && Bool.not(rim) && ((ax + 2 * sabs((dy + 0 : U32))) <= 30 : U32) && sle((0 - 2 : U32), dy)
  +post = (U32.is_eq(dx, 0) && between(dy, (0 - 24 : U32), (0 - 17 : U32)))
  +lamp = U32.is_eq(dx, 0) && U32.is_eq(dy, (0 - 25 : U32)) && Bool.not(U32.is_eq(Art.night(t), 0))
  +g0 = Art.golem(dx, dy, sel(run, wsin((tm * 3 : U32), 16), (0 - 15 : U32)), sel(run, (0 - 2 + wsin((tm * 2 + 20 : U32), 7) : U32), (0 - 2 : U32)), Art.code(ra, rb, 0), 7864234)
  +g1 = Art.golem(dx, dy, sel(run, wsin((tm * 2 + 90 : U32), 16), (0 - 5 : U32)), sel(run, (0 - 2 + wsin((tm * 3 + 60 : U32), 7) : U32), (0 - 7 : U32)), Art.code(ra, rb, 1), 16748640)
  +g2 = Art.golem(dx, dy, sel(run, wsin((tm * 4 + 30 : U32), 15), 5), sel(run, (0 - 2 + wsin((tm * 2 + 150 : U32), 7) : U32), (0 - 7 : U32)), Art.code(ra, rb, 2), 6352127)
  +g3 = Art.golem(dx, dy, sel(run, wsin((tm * 3 + 170 : U32), 15), 15), sel(run, (0 - 2 + wsin((tm * 4 + 10 : U32), 6) : U32), (0 - 2 : U32)), Art.code(ra, rb, 3), 16766282)
  +g4 = Art.golem(dx, dy, sel(run, wsin((tm * 2 + 200 : U32), 14), (0 - 15 : U32)), sel(run, (0 - 2 + wsin((tm * 3 + 100 : U32), 6) : U32), 4), Art.code(ra, rb, 4), 12623103)
  +g5 = Art.golem(dx, dy, sel(run, wsin((tm * 4 + 120 : U32), 14), (0 - 5 : U32)), sel(run, (0 - 2 + wsin((tm * 2 + 220 : U32), 6) : U32), 9), Art.code(ra, rb, 5), 7864234)
  +g6 = Art.golem(dx, dy, sel(run, wsin((tm * 3 + 60 : U32), 13), 5), sel(run, (0 - 2 + wsin((tm * 4 + 180 : U32), 5) : U32), 9), Art.code(ra, rb, 6), 16748640)
  +g7 = Art.golem(dx, dy, sel(run, wsin((tm * 2 + 240 : U32), 13), 15), sel(run, (0 - 2 + wsin((tm * 3 + 200 : U32), 5) : U32), 4), Art.code(ra, rb, 7), 6352127)
  +cars = over(g0, over(g1, over(g2, over(g3, over(g4, over(g5, over(g6, g7)))))))
  over(cars, over(sel(lamp, E(16766282), sel(post, 3158064, TR())),
    sel(rim, 9079446, sel(rimside, 6316656, sel(grid, sel(run, 5277842, 4216950), sel(floor, 3162714, TR()))))))

# The Hedge Labyrinth: hedges four pixels high on a two-tile square, a gilt
# statue in the heart of it; visitors walk the ring inside
def Art.maze.wall(+i: U32, +j: U32) -> Bool:
  +outer = U32.is_eq(i, 0) || U32.is_eq(j, 0) || U32.is_eq(i, 7) || U32.is_eq(j, 7)
  +gate = U32.is_eq(i, 7) && U32.is_eq(j, 3) || U32.is_eq(i, 0) && U32.is_eq(j, 4)
  +box = between(i, 2, 5) && between(j, 2, 5) && (U32.is_eq(i, 2) || U32.is_eq(i, 5) || U32.is_eq(j, 2) || U32.is_eq(j, 5))
  +gap = U32.is_eq(i, 5) && U32.is_eq(j, 4) || U32.is_eq(i, 3) && U32.is_eq(j, 2)
  (outer && Bool.not(gate)) || (box && Bool.not(gap)) || U32.is_eq(i, 1) && U32.is_eq(j, 5) || U32.is_eq(i, 6) && U32.is_eq(j, 2)

def Art.maze.at(+dx: U32, +dy: U32) -> Bool:
  +y2 = ((dy + 16) * 2 : U32)
  +u = iso_u(dx, y2)
  +v = iso_v(dx, y2)
  (u < 32 : U32) && (v < 32 : U32) && Art.maze.wall((u >> 2n : U32), (v >> 2n : U32))

# the ring corridor, cells (1..6, 1) (6, 1..6) (6..1, 6) (1, 6..1): 20 steps
def Art.maze.walker(+dx: U32, +dy: U32, +s: U32, +code: U32) -> U32:
  +k = sel((s >= 40 : U32), (s - 40 : U32), sel((s >= 20 : U32), (s - 20 : U32), s))
  +ci = sel((k < 5 : U32), (1 + k : U32), sel((k < 10 : U32), 6, sel((k < 15 : U32), (6 - (k - 10) : U32), 1)))
  +cj = sel((k < 5 : U32), 1, sel((k < 10 : U32), (1 + (k - 5) : U32), sel((k < 15 : U32), 6, (6 - (k - 15) : U32))))
  +u = (ci * 4 + 2 : U32)
  +v = (cj * 4 + 2 : U32)
  +wx = (u - v : U32)
  +wy = (((u + v) >> 1n) - 16 : U32)
  Art.rider((dx - wx : U32), (dy - wy : U32), code)

def Art.maze(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +tm = Art.tm(st)
  +y2 = ((dy + 16) * 2 : U32)
  +u = iso_u(dx, y2)
  +v = iso_v(dx, y2)
  +inside = (u < 32 : U32) && (v < 32 : U32)
  +w0 = Art.maze.at(dx, dy)
  +w1 = Art.maze.at(dx, (dy + 1 : U32))
  +w2 = Art.maze.at(dx, (dy + 2 : U32))
  +w3 = Art.maze.at(dx, (dy + 3 : U32))
  +w4 = Art.maze.at(dx, (dy + 4 : U32))
  +leafy = U32.is_eq((hash((dx + 64 : U32), (dy + 64 : U32)) .&. 3 : U32), 0)
  +hedge = sel(w4, sel(leafy, 7324480, 5275712), sel(w3 || w2 || w1, sel(leafy, 3834938, 3040816), TR()))
  +gravel = inside && Bool.not(w0)
  +statue = ell(dx, (dy + 2 : U32), 2, 1) || U32.is_eq(dx, 0) && between(dy, (0 - 8 : U32), (0 - 2 : U32))
    || ell(dx, (dy + 9 : U32), 1, 1)
  +step = (tm >> 5n : U32)
  +run = Art.running(st)
  +v0 = Art.maze.walker(dx, dy, sel(run, (step + 0 : U32), 0), Art.code(ra, rb, 0))
  +v1 = Art.maze.walker(dx, dy, sel(run, (step + 3 : U32), 1), Art.code(ra, rb, 1))
  +v2 = Art.maze.walker(dx, dy, sel(run, (step + 5 : U32), 2), Art.code(ra, rb, 2))
  +v3 = Art.maze.walker(dx, dy, sel(run, (step + 8 : U32), 3), Art.code(ra, rb, 3))
  +v4 = Art.maze.walker(dx, dy, sel(run, (step + 10 : U32), 4), Art.code(ra, rb, 4))
  +v5 = Art.maze.walker(dx, dy, sel(run, (step + 13 : U32), 5), Art.code(ra, rb, 5))
  +v6 = Art.maze.walker(dx, dy, sel(run, (step + 15 : U32), 6), Art.code(ra, rb, 6))
  +v7 = Art.maze.walker(dx, dy, sel(run, (step + 18 : U32), 7), Art.code(ra, rb, 7))
  +walkers = over(v0, over(v1, over(v2, over(v3, over(v4, over(v5, over(v6, v7)))))))
  over(sel(w4, hedge, TR()), over(walkers, over(hedge, sel(statue, 14725184, sel(gravel, 12628608, TR())))))

# The Mermaid Flume: a water channel on stilts around a lagoon rock where a
# mermaid sits; it climbs along the back and drops at the right with a
# splash; four logs of two riders
def Art.flume.h(+x: U32, +back: Bool) -> U32:
  sel(back, (4 + (((x + 26) * 69) >> 8n) : U32), 4)

def Art.flume.log(+dx: U32, +dy: U32, +a: U32, +ca: U32, +cb: U32) -> U32:
  +lx = wcos(a, 22)
  +ly0 = wsin(a, 11)
  +back = neg(ly0)
  +ly = (ly0 - Art.flume.h(lx, back) : U32)
  +ex = (dx - lx : U32)
  +ey = (dy - ly : U32)
  +log = ell(ex, ey, 5, 2)
  +end = log && U32.is_eq(sabs(ex), 5)
  over(Art.rider((ex + 2 : U32), (ey + 1 : U32), ca), over(Art.rider((ex - 2 : U32), (ey + 1 : U32), cb),
    sel(end, 9062442, sel(log, 11567184, TR()))))

def Art.flume(+dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  +run = Art.running(st)
  +a0 = sel(run, (Art.tm(st) * 2 : U32), 64)
  +back = slt(dy, 0)
  +h = Art.flume.h(dx, back)
  +cy = (dy + h : U32)
  +chan = ell(dx, cy, 26, 13) && Bool.not(ell(dx, cy, 18, 9))
  +water = ell(dx, cy, 25, 12) && Bool.not(ell(dx, cy, 19, 10))
  +ripple = water && U32.is_eq((((dx + dy * 2) + (t >> 2n) + 1024) .&. 7 : U32), 0)
  +side = Bool.not(chan) && (ell(dx, (cy - 2 : U32), 26, 13) && Bool.not(ell(dx, (cy - 2 : U32), 18, 9)))
  +lagoon = ell(dx, (dy + 2 : U32), 14, 7)
  +rock = ell(dx, (dy + 6 : U32), 6, 4)
  +tail = between(dx, 1, 4) && between(dy, (0 - 9 : U32), (0 - 7 : U32))
  +mbody = U32.is_eq(dx, 0) && between(dy, (0 - 13 : U32), (0 - 9 : U32))
  +hair = between(dx, (0 - 1 : U32), 0) && between(dy, (0 - 15 : U32), (0 - 12 : U32))
  +splash = run && ell((dx - 22 : U32), (dy + 3 : U32), 4, 5) && U32.is_eq((hash((dx + 64 : U32), ((dy + 64) + (t >> 2n) : U32)) .&. 1 : U32), 0)
  +l0 = Art.flume.log(dx, dy, a0, Art.code(ra, rb, 0), Art.code(ra, rb, 1))
  +l1 = Art.flume.log(dx, dy, (a0 + 64 : U32), Art.code(ra, rb, 2), Art.code(ra, rb, 3))
  +l2 = Art.flume.log(dx, dy, (a0 + 128 : U32), Art.code(ra, rb, 4), Art.code(ra, rb, 5))
  +l3 = Art.flume.log(dx, dy, (a0 + 192 : U32), Art.code(ra, rb, 6), Art.code(ra, rb, 7))
  +logs = over(l0, over(l1, over(l2, l3)))
  over(sel(splash, 16316664, TR()), over(logs, over(sel(ripple, 10538751, sel(water, 4221152, sel(chan, 9062442,
    sel(side, 7031338, TR())))), over(sel(hair, 14200928, sel(mbody, 15781004, sel(tail, 4889242, sel(rock, 9079446,
    sel(lagoon, 3108784, TR()))))), TR()))))

def Art.ride.go(+k: U32, +dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  match k:
    case 1:
      Art.carousel(dx, dy, t, ra, rb, st)
    case 2:
      Art.spire(dx, dy, t, ra, rb, st)
    case 3:
      Art.potion(dx, dy, t)
    case 4:
      Art.tavern(dx, dy, t)
    case 6:
      Art.privy(dx, dy, t)
    case 7:
      Art.healer(dx, dy, t)
    case 8:
      Art.wisps(dx, dy, t)
    case 9:
      Art.ices(dx, dy, t)
    case 10:
      Art.swing(dx, dy, t, ra, rb, st)
    case 11:
      Art.wheel(dx, dy, t, ra, rb, st)
    case 12:
      Art.crypt(dx, dy, t, ra, rb, st)
    case 13:
      Art.bumpers(dx, dy, t, ra, rb, st)
    case 14:
      Art.maze(dx, dy, t, ra, rb, st)
    case 17:
      Art.flume(dx, dy, t, ra, rb, st)
    case 15:
      Art.eyrie(dx, dy, t, ra, rb, st)
    case 16:
      Art.whirl(dx, dy, t, ra, rb, st)
    case _:
      TR()

# a blinking warning over a ride that can't run (no entrance or no exit)
def Art.warn(on: Bool, +dx: U32, +dy: U32, +t: U32) -> U32:
  match on:
    case True{}:
      +cy = (dy + 84 : U32)
      +disc = ell(dx, cy, 5, 5)
      +rim = disc && Bool.not(ell(dx, cy, 4, 4))
      +bang = U32.is_eq(dx, 0) && (between(dy, (0 - 87 : U32), (0 - 83 : U32)) || U32.is_eq(dy, (0 - 81 : U32)))
      +vis = Bool.not(U32.is_eq(((t >> 4n) .&. 3 : U32), 0))
      sel(vis && disc, sel(bang, 16777215, sel(rim, 8392720, 14163020)), TR())
    case False{}:
      TR()

# st: phase << 16 | ticks into it, bit 30 when the ride lacks a door
# A placement ghost (k: tool | ok << 8 | size << 9 | ride kind << 12 |
# demolished ride's kind << 16): the footprint tinted green (it can go) or red
# (it can't), and a ride's or tree's shape stippled in the same tint
def Art.tint(+c: U32, +ok: Bool) -> U32:
  +g = sel(ok, 6154320, 14163020)
  (((c .&. 16711422) >> 1n) + ((g .&. 16711422) >> 1n) : U32)

# a broken-down ride: a blinking wrench sign above it and smoke rising
def Art.broke(on: Bool, +dx: U32, +dy: U32, +t: U32) -> U32:
  match on:
    case True{}:
      +cy = (dy + 84 : U32)
      +disc = ell(dx, cy, 6, 6)
      +rim = disc && Bool.not(ell(dx, cy, 5, 5))
      +bar = (sabs((dx + cy : U32)) <= 0 : U32) && (sabs(dx) <= 3 : U32)
      +jaw = ell((dx - 3 : U32), (cy + 3 : U32), 2, 2) && Bool.not(U32.is_eq(dx, 4) && U32.is_eq(cy, (0 - 4 : U32)))
        && Bool.not(U32.is_eq(dx, 3) && U32.is_eq(cy, (0 - 3 : U32)))
      +vis = Bool.not(U32.is_eq(((t >> 4n) .&. 3 : U32), 0))
      +sm = (t .&. 63 : U32)
      +puff1 = ell((dx - 4 : U32), (dy + 36 + (sm >> 1n) : U32), 3, 2)
      +puff2 = ell((dx + 3 : U32), (dy + 50 + (((sm + 32) .&. 63) >> 1n) : U32), 2, 2)
      sel(vis && disc, sel(rim || bar || jaw, 3158064, 15237168), sel(puff1 || puff2, 10526880, TR()))
    case False{}:
      TR()

def Art.ride(+k: U32, +dx: U32, +dy: U32, +t: U32, +ra: U32, +rb: U32, +st: U32) -> U32:
  over(Art.broke(Bool.not(U32.is_eq((st .&. 536870912 : U32), 0)), dx, dy, t),
    over(Art.warn(Bool.not(U32.is_eq((st .&. 1073741824 : U32), 0)), dx, dy, t),
    Art.ride.go(k, dx, dy, t, ra, rb, st)))

# Coaster track
# -------------
# X, Y0 locate the pixel against the track plane; rails run along u (or v)

def Art.ghost(+k: U32, +px: U32, +py: U32, +x: U32, +y: U32, +t: U32) -> U32:
  +tool = (k .&. 255 : U32)
  +ok = Bool.not(U32.is_eq(((k >> 8n) .&. 1 : U32), 0))
  +size = ((k >> 9n) .&. 7 : U32)
  +rk = ((k >> 12n) .&. 31 : U32)
  +X = (px - x : U32)
  +Y = ((py - y) * 2 : U32)
  +u = iso_u(X, Y)
  +v = iso_v(X, Y)
  +w = (size * 16 : U32)
  +inside = (u < w : U32) && (v < w : U32)
  +edge = inside && ((u < 1 : U32) || (v < 1 : U32) || (u + 1 >= w : U32) || (v + 1 >= w : U32))
  +stip = U32.is_eq(((px + py + (t >> 3n)) .&. 1 : U32), 0)
  +col = sel(ok, 7324480, 14163020)
  +foot = sel(edge, sel(ok, 11534220, 16748688), sel(inside && stip, col, TR()))
  +dy = (size * 8 : U32)
  +shape = sel(Bool.not(U32.is_eq(rk, 0)), Art.ride(rk, (px - x : U32), (py - y - dy : U32), t, 0, 0, 0),
    sel(U32.is_eq(tool, 4), Art.tree(0, (px - x : U32), (py - y - 8 : U32), 1, t),
    sel((tool >= 41 : U32) && (tool <= 45 : U32), Art.tree(sel(U32.is_eq(tool, 41), 4, sel(U32.is_eq(tool, 42), 8,
      sel(U32.is_eq(tool, 43), 9, sel(U32.is_eq(tool, 44), 12, 13)))), (px - x : U32), (py - y - 8 : U32), 0, t),
    sel((tool >= 13 : U32) && (tool <= 15 : U32), Art.prop((tool - 12 : U32), False{}, False{}, x, y, px, py, t), TR()))))
  +shown = sel(opaque(shape) && stip, Art.tint(shape, ok), TR())
  over(shown, foot)

def Art.rails(+u: U32, +v: U32, +along_u: Bool, +kind: U32, +t: U32) -> U32:
  +a = sel(along_u, u, v)
  +c = sel(along_u, v, u)
  +ok = (u < 16 : U32) && (v < 16 : U32)
  +rail = between(c, 3, 4) || between(c, 11, 12)
  +tie = U32.is_eq((a .&. 3 : U32), 1) && between(c, 2, 13)
  +chain = U32.is_eq(kind, 6) && between(c, 7, 8) && ((((a + (t >> 1n)) .&. 3) < 2) : U32)
  +plat = U32.is_eq(kind, 5) && ((c < 2 : U32) || (c > 13 : U32))
  # brakes: a red and gold fin between the rails
  +fin = U32.is_eq(kind, 9) && between(c, 6, 9)
  sel(ok, sel(rail, 13120044, sel(chain, 4210752, sel(fin, sel(U32.is_eq((a .&. 2 : U32), 0), 12597547, 14329120),
    sel(tie, 7031339, sel(plat, sel(U32.is_eq((a .&. 3 : U32), 0), 8011834, 11041354), TR()))))), TR())

# a banked turn has a planked deck, its outer rail picked out in gold
def Art.turn(+u: U32, +v: U32, +cu: U32, +cv: U32, +bank: Bool) -> U32:
  +ok = (u < 16 : U32) && (v < 16 : U32)
  +eu = (u - cu : U32)
  +ev = (v - cv : U32)
  +d2 = (eu * eu + ev * ev : U32)
  +inner = between(d2, 9, 25)
  +outer = between(d2, 121, 169)
  +deck = between(d2, 26, 120)
  +tie = U32.is_eq(((u + v) .&. 3 : U32), 0)
  sel(ok, sel(inner, 13120044, sel(outer, sel(bank, 14329120, 13120044),
    sel(deck && tie, 7031339, sel(deck && bank, 9661500, TR())))), TR())

# a steep slope climbs two levels in one tile. Facing the camera it is
# solved like a gentle one; facing away, the view runs along its surface, so
# it shows as a rail over a band of timber.
def Art.steep(+kind: U32, +d: U32, +X: U32, +Y0: U32, +t: U32) -> U32:
  +up = U32.is_eq(kind, 12)
  +along_u = U32.is_eq((d .&. 1 : U32), 0)
  +face = (up && (d >= 2 : U32)) || (Bool.not(up) && (d < 2 : U32))
  +Yf = sel(up, (Y0 + 32 : U32), Y0)
  +fu = sel(along_u, ((Yf + X) >> 2n : U32), ((((Yf - X) >> 2n) + X) : U32))
  +fv = sel(along_u, ((((Yf + X) >> 2n) - X) : U32), ((Yf - X) >> 2n : U32))
  +Ye = sel(up, Y0, (Y0 - 32 : U32))
  +e = sel(along_u, (Ye + X : U32), (Ye - X : U32))
  +band = (e < 10 : U32) && (sabs(X) <= 12 : U32)
  +edge = sel((e < 2 : U32), 13120044, sel(U32.is_eq((X .&. 3 : U32), 0), 5913890, 7031339))
  sel(face, Art.rails(fu, fv, along_u, kind, t), sel(band, edge, TR()))

def Art.side_u(+d: U32) -> U32:
  match d:
    case 0:
      0
    case 1:
      0
    case 2:
      16
    case _:
      16

# where the track surface is, for one pixel: slopes solve the projection
def Art.track_top(+kind: U32, +d: U32, +X: U32, +Y0: U32, +t: U32) -> U32:
  +along_u = U32.is_eq((d .&. 1 : U32), 0)
  +up = U32.is_eq(kind, 1) || U32.is_eq(kind, 6)
  +steep = U32.is_eq(kind, 12) || U32.is_eq(kind, 13)
  +down = U32.is_eq(kind, 2)
  # slope rising toward +u or +v ("pos"), or toward -u / -v
  +rise_pos = (up && (d < 2 : U32)) || (down && (d >= 2 : U32))
  +slope = up || down
  +Ys = sel(up && (d >= 2 : U32), (Y0 + 16 : U32), sel(down && (d >= 2 : U32), (Y0 - 16 : U32), Y0))
  # rising toward +axis: the other coordinate is Ys; falling: divide by 3
  +n3 = sel(along_u, (Ys + X : U32), (Ys - X : U32))
  +q3 = sel((n3 < 48 : U32), div3(n3), 999)
  +su = sel(rise_pos, sel(along_u, (X + Ys : U32), Ys), sel(along_u, q3, (X + q3 : U32)))
  +sv = sel(rise_pos, sel(along_u, Ys, (Ys - X : U32)), sel(along_u, (q3 - X : U32), q3))
  +fu = iso_u(X, Y0)
  +fv = iso_v(X, Y0)
  +u = sel(slope, su, fu)
  +v = sel(slope, sv, fv)
  +left = U32.is_eq(kind, 3) || U32.is_eq(kind, 10)
  +turn = left || U32.is_eq(kind, 4) || U32.is_eq(kind, 11)
  +d2 = sel(left, ((d + 3) .&. 3 : U32), ((d + 1) .&. 3 : U32))
  # the turn's centre: the corner between its entry and exit sides
  +entry_u = sel(U32.is_eq(d, 0), 0, 16)
  +entry_v = sel(U32.is_eq(d, 1), 0, 16)
  +exit_u = sel(U32.is_eq(d2, 0), 16, 0)
  +exit_v = sel(U32.is_eq(d2, 1), 16, 0)
  +cu = sel(along_u, entry_u, exit_u)
  +cv = sel(along_u, exit_v, entry_v)
  sel(steep, Art.steep(kind, d, X, Y0, t),
    sel(turn, Art.turn(fu, fv, cu, cv, (kind >= 10 : U32)), Art.rails(u, v, along_u, kind, t)))

# a walkway deck zr levels above its tile's ground (top vertex at x, y):
# planks, a rail on each side with no deck or path to join (nb bits: 1 i-1,
# 2 i+1, 4 j-1, 8 j+1), and a post under its corners
def Art.deck(+x: U32, +y: U32, +zr: U32, +nb: U32, +px: U32, +py: U32) -> U32:
  +X = (px - x : U32)
  +dy = (py - y : U32)
  +Y0 = ((dy * 2) + zr * 16 : U32)
  +u = iso_u(X, Y0)
  +v = iso_v(X, Y0)
  +on = (u < 16 : U32) && (v < 16 : U32)
  +gap = U32.is_eq((u .&. 3 : U32), 3)
  +plank = sel(gap, 5913890, sel(U32.is_eq(((u >> 2n) .&. 1 : U32), 0), 10119226, 9136940))
  +Yr = (Y0 + 8 : U32)
  +ur = iso_u(X, Yr)
  +vr = iso_v(X, Yr)
  +inr = (ur < 16 : U32) && (vr < 16 : U32)
  +rail = inr && (U32.is_eq((nb .&. 1 : U32), 0) && U32.is_eq(ur, 0) || U32.is_eq((nb .&. 2 : U32), 0) && U32.is_eq(ur, 15)
    || U32.is_eq((nb .&. 4 : U32), 0) && U32.is_eq(vr, 0) || U32.is_eq((nb .&. 8 : U32), 0) && U32.is_eq(vr, 15))
  +drop = (zr * 8 : U32)
  +postr = between(X, 14, 16) && between(dy, (8 - drop : U32), 8)
  +postl = between(X, (0 - 16 : U32), (0 - 14 : U32)) && between(dy, (8 - drop : U32), 8)
  +postf = between(X, (0 - 1 : U32), 1) && between(dy, (16 - drop : U32), 16)
  sel(on, plank, sel(rail, 7031339, sel(postr || postl || postf, sel(U32.is_eq(X, 16) || U32.is_eq(X, 1) || U32.is_eq(X, (0 - 14 : U32)), 4209440, 5913890), TR())))

# the track's colours by coaster type: the Wyrm's red rails on timber; the
# Dwarven Minecart's iron rails on dark sleepers; the Griffin Flyer's blue
# rails on steel
def Art.recolor(+c: U32, +ty: U32) -> U32:
  +mine = U32.is_eq(ty, 1)
  +fly = U32.is_eq(ty, 2)
  +rail = U32.is_eq(c, 13120044)
  +tie = U32.is_eq(c, 7031339)
  +post = U32.is_eq(c, 8017200)
  +dark = U32.is_eq(c, 5913890)
  +brace = U32.is_eq(c, 6964776)
  sel(mine && rail, 9474192, sel(mine && tie, 5125166,
  sel(fly && rail, 5072841, sel(fly && tie, 8421504, sel(fly && post, 12632256,
  sel(fly && dark, 9474192, sel(fly && brace, 10526880, c)))))))

# a track piece on a tile whose ground top vertex is (x, y); zr levels up;
# code: kind | heading << 4 | coaster << 8 | type << 12 | broken << 16 |
# ghost << 17 | fits << 18
def Art.track(+x: U32, +y: U32, +code: U32, +zr: U32, +t: U32, +px: U32,
  +py: U32) -> U32:
  +kind = (code .&. 15 : U32)
  +d = ((code >> 4n) .&. 3 : U32)
  +X = (px - x : U32)
  +Y0 = (((py - y) * 2) + zr * 16 : U32)
  +sign = Art.broke(Bool.not(U32.is_eq(((code >> 16n) .&. 1 : U32), 0)), X, (py - y + zr * 8 - 54 : U32), t)
  +surf = Art.track_top(kind, d, X, Y0, t)
  +slope = sel(U32.is_eq(kind, 1) || U32.is_eq(kind, 6), 4, sel(U32.is_eq(kind, 12), 8,
    sel(U32.is_eq(kind, 2), (0 - 4 : U32), sel(U32.is_eq(kind, 13), (0 - 8 : U32), 0))))
  +stop = (y + 8 - zr * 8 - slope : U32)
  +post = (sabs(X) <= 1 : U32) && sle(stop, py) && sle(py, (y + 8 : U32))
    && (zr > 0 : U32)
  +brace = U32.is_eq(((py + 256 - y) .&. 7 : U32), 0) && (sabs(X) <= 3 : U32)
    && sle(stop, py) && sle(py, (y + 8 : U32)) && (zr > 0 : U32)
  +c = over(sign, Art.recolor(over(surf, sel(post, sel(U32.is_eq(X, 1), 5913890, 8017200), sel(brace, 6964776, TR()))),
    ((code >> 12n) .&. 3 : U32)))
  # a ghost (bit 17; bit 18 when it fits): tinted green or red, pulsing
  +ghost = Bool.not(U32.is_eq(((code >> 17n) .&. 1 : U32), 0))
  +fit = Bool.not(U32.is_eq(((code >> 18n) .&. 1 : U32), 0))
  +pulse = U32.is_eq(((t >> 4n) .&. 1 : U32), 0)
  +t1 = Art.tint(c, fit)
  sel(ghost, sel(opaque(c), sel(fit || pulse, Art.tint(t1, fit), t1), TR()), c)

# a coaster car centred at (0, 0) on the track, heading d
def Art.car_in(+X: U32, +Y: U32, +along_u: Bool) -> Bool:
  +u = iso_u(X, Y)
  +v = iso_v(X, Y)
  +a = sel(along_u, u, v)
  +c = sel(along_u, v, u)
  (sabs(a) <= 5 : U32) && (sabs(c) <= 3 : U32)

# lead: bit 0 the front car, bits 1-2 the coaster type (a Griffin Flyer's
# car hangs from its rails on a bar)
# one layer of a car (k levels up from its floor): along its travel, fa runs
# -5 (back) .. 5 (front); across it, c runs -3 .. 3
def Art.car_lay(+dx: U32, +dy: U32, +k: U32, +along_u: Bool, +fwd: Bool, +amin: U32, +amax: U32, +cmin: U32, +cmax: U32) -> Bool:
  +Y = ((dy + k) * 2 : U32)
  +u = iso_u(dx, Y)
  +v = iso_v(dx, Y)
  +a = sel(along_u, u, v)
  +c = sel(along_u, v, u)
  +fa = sel(fwd, a, (0 - a : U32))
  between(fa, amin, amax) && between(sabs(c), cmin, cmax)

# The cars. Every type has a floor-level chassis (bogies with wheels) unless
# it hangs; the Wyrm's cars have scales and a spine ridge, the front one a
# carved dragon head with glowing eyes and horns; the Minecart's are planked
# with iron bands and rivets, the front one carrying a lantern that glows at
# night; the Flyer's are gilded gondolas with blue wing fins and a stripe.
def Art.car_body(+dx: U32, +dy: U32, +d: U32, +front: Bool, +ty: U32, +rd: U32) -> U32:
  +along_u = U32.is_eq((d .&. 1 : U32), 0)
  +fwd = (d < 2 : U32)
  +topy = ((dy + 5) * 2 : U32)
  +ontop = Art.car_in(dx, topy, along_u)
  +low = Art.car_in(dx, (dy * 2 : U32), along_u) && Bool.not(Art.car_in(dx, ((dy + 1) * 2 : U32), along_u))
  +side = Art.car_in(dx, (dy * 2 : U32), along_u) || Art.car_in(dx, ((dy + 1) * 2 : U32), along_u)
    || Art.car_in(dx, ((dy + 2) * 2 : U32), along_u) || Art.car_in(dx, ((dy + 3) * 2 : U32), along_u)
    || Art.car_in(dx, ((dy + 4) * 2 : U32), along_u)
  +body = sel(U32.is_eq(ty, 1), sel(front, 10053171, 7359264),
    sel(U32.is_eq(ty, 2), sel(front, 14329120, 3368652), sel(front, 13120044, 4172373)))
  +wyrm = U32.is_eq(ty, 0)
  +mine = U32.is_eq(ty, 1)
  +fly = U32.is_eq(ty, 2)
  # where on the car a side pixel is, along its length (middle layer)
  +mu = iso_u(dx, ((dy + 2) * 2 : U32))
  +mv = iso_v(dx, ((dy + 2) * 2 : U32))
  +ma = sel(along_u, mu, mv)
  +fam = sel(fwd, ma, (0 - ma : U32))
  +wheel = low && Bool.not(fly) && (U32.is_eq(sabs(fam), 3) || U32.is_eq(sabs(fam), 4))
  +chassis = low && Bool.not(fly)
  +spine = wyrm && Art.car_lay(dx, dy, 5, along_u, fwd, (0 - 4 : U32), 3, 0, 0)
  +scale = wyrm && side && U32.is_eq(((dx + dy) .&. 1 : U32), 0)
  +band = mine && side && U32.is_eq(sabs(fam), 4)
  +rivet = band && U32.is_eq(((dy + 256) .&. 1 : U32), 0)
  +seam = mine && side && U32.is_eq((fam .&. 1 : U32), 0)
  +rim = mine && ontop && Bool.not(Art.car_lay(dx, dy, 5, along_u, fwd, (0 - 4 : U32), 4, 0, 2))
  +stripe = fly && Art.car_lay(dx, dy, 5, along_u, fwd, (0 - 5 : U32), 5, 0, 0)
  +fin = fly && (Art.car_lay(dx, dy, 3, along_u, fwd, (0 - 3 : U32), 1, 4, 5) || Art.car_lay(dx, dy, 2, along_u, fwd, (0 - 2 : U32), 0, 4, 4))
  # the Wyrm's head on the front car
  +jaw = wyrm && front && (Art.car_lay(dx, dy, 2, along_u, fwd, 6, 10, 0, 1) || Art.car_lay(dx, dy, 3, along_u, fwd, 6, 10, 0, 1))
  +head = wyrm && front && (Art.car_lay(dx, dy, 4, along_u, fwd, 6, 9, 0, 2) || Art.car_lay(dx, dy, 5, along_u, fwd, 6, 9, 0, 2)
    || Art.car_lay(dx, dy, 6, along_u, fwd, 6, 8, 0, 1))
  +eye = wyrm && front && Art.car_lay(dx, dy, 6, along_u, fwd, 8, 8, 1, 1)
  +horn = wyrm && front && (Art.car_lay(dx, dy, 7, along_u, fwd, 6, 6, 1, 1) || Art.car_lay(dx, dy, 8, along_u, fwd, 5, 5, 1, 1)
    || Art.car_lay(dx, dy, 9, along_u, fwd, 4, 4, 1, 1))
  # the Minecart's lantern on the front car
  +pole = mine && front && (Art.car_lay(dx, dy, 6, along_u, fwd, 5, 5, 0, 0) || Art.car_lay(dx, dy, 7, along_u, fwd, 5, 5, 0, 0)
    || Art.car_lay(dx, dy, 8, along_u, fwd, 5, 5, 0, 0))
  +lamp = mine && front && (Art.car_lay(dx, dy, 9, along_u, fwd, 5, 5, 0, 0) || Art.car_lay(dx, dy, 10, along_u, fwd, 5, 5, 0, 0))
  +sx = sel(along_u, 3, (0 - 3 : U32))
  +rfront = Art.rider((dx - sx : U32), (dy + 5 - 1 : U32), ((rd >> 8n) .&. 255 : U32))
  +rback = Art.rider((dx + sx : U32), (dy + 5 + 1 : U32), (rd .&. 255 : U32))
  +shell = sel(ontop, sel(spine, 8392720, sel(rim, 5125166, sel(stripe, 5072841, shade(body, 290)))),
    sel(side, sel(wheel, 1118481, sel(chassis, 3355443, sel(rivet, 11579568, sel(band, 7368816,
      shade(body, sel(neg(dx), sel(scale || seam, 170, 210), sel(scale || seam, 125, 160))))))), TR()))
  +extra = sel(eye, E(16766282), sel(horn, 15263976, sel(head, shade(body, sel(neg(dx), 230, 180)), sel(jaw, 14329120,
    sel(lamp, E(16768324), sel(pole, 4210752, sel(fin, 5072841, TR())))))))
  over(rfront, over(rback, over(extra, shell)))

# Adventurers
# -----------
# look: bits 0-1 class (wizard, knight, elf, dwarf), 4-6 tunic, 8-9 skin

def Art.car(+dx: U32, +dy: U32, +d: U32, +lead: U32, +rd: U32) -> U32:
  +ty = ((lead >> 1n) .&. 3 : U32)
  +front = U32.is_eq((lead .&. 1 : U32), 1)
  +hang = U32.is_eq(ty, 2) && (sabs(dx) <= 0 : U32) && between(dy, (0 - 16 : U32), (0 - 6 : U32))
  # the Flyer's bogie, riding the rail above its bar
  +bogie = U32.is_eq(ty, 2) && (sabs(dx) <= 2 : U32) && between(dy, (0 - 19 : U32), (0 - 17 : U32))
  sel(bogie, sel(U32.is_eq(sabs(dx), 2) && U32.is_eq(dy, (0 - 18 : U32)), 1118481, 4210752),
    sel(hang, 10526880, Art.car_body(dx, dy, d, front, ty, rd)))

def bitmask(+k: U32) -> U32:
  match k:
    case 0:
      1
    case 1:
      2
    case 2:
      4
    case 3:
      8
    case 4:
      16
    case 5:
      32
    case 6:
      64
    case 7:
      128
    case 8:
      256
    case 9:
      512
    case 10:
      1024
    case 11:
      2048
    case 12:
      4096
    case 13:
      8192
    case 14:
      16384
    case _:
      0

def glyph_on(+bits: U32, +dx: U32, +dy: U32) -> Bool:
  (dx < 3 : U32) && (dy < 5 : U32)
    && Bool.not(U32.is_eq((bits .&. bitmask((14 - (dy * 3 + dx) : U32)) : U32), 0))

def Art.glyph(+bits: U32, +dx: U32, +dy: U32, +col: U32) -> U32:
  +on = glyph_on(bits, dx, dy)
  +sh = glyph_on(bits, (dx - 1 : U32), (dy - 1 : U32))
  sel(on, col, sel(sh, 1052688, TR()))

def Art.dia(+cx: U32, +cy: U32) -> Bool:
  ((sabs(cx) + sabs(cy) * 2) <= 8 : U32)

def Art.icon_pic(+tool: U32, +cx: U32, +cy: U32, +t: U32) -> U32:
  match tool:
    case 1:
      sel(Art.dia(cx, cy), Art.cobble(((cx + 16) : U32), ((cy * 2 + 16) : U32), 3), TR())
    case 2:
      +tri_up = sle((0 - 6 : U32), cy) && sle(cy, 2) && ((sabs(cx) * 2) <= (cy + 6) : U32)
      sel(tri_up, 6337117, sel(Art.dia(cx, cy) && sle(2, cy), 4626999, TR()))
    case 3:
      +tri_dn = sle((0 - 6 : U32), cy) && sle(cy, 2) && ((sabs(cx) * 2) <= (2 - cy) : U32)
      sel(tri_dn, 11559978, sel(Art.dia(cx, cy) && sle(2, cy), 9138758, TR()))
    case 4:
      Art.glowcap(cx, (cy - 5 : U32), 5, t)
    case 5:
      Art.cone(cx, (cy + 2 : U32), 0, 8, 9, 8077216, 15253568)
    case 6:
      Art.cyl(cx, cy, 6, 3, 12, 7100042)
    case 7:
      +neck = (sabs(cx) <= 1 : U32) && between(cy, (0 - 7 : U32), (0 - 4 : U32))
      +flask = ell(cx, (cy - 1 : U32), 5, 5)
      sel(neck, 13154448, sel(flask, sel(sle(0, cy), 14168128, 12632319), TR()))
    case 8:
      +mug = between(cx, (0 - 4 : U32), 3) && between(cy, (0 - 4 : U32), 6)
      +foam = between(cx, (0 - 5 : U32), 4) && between(cy, (0 - 7 : U32), (0 - 5 : U32))
      +handle = between(cx, 4, 6) && between(cy, (0 - 2 : U32), 3)
        && Bool.not(U32.is_eq(cx, 5) && between(cy, (0 - 1 : U32), 2))
      +band = U32.is_eq(cy, 0) || U32.is_eq(cy, 4)
      sel(foam, 15790320, sel(mug, sel(band, 9138758, 13148232), sel(handle, 10512954, TR())))
    case 9:
      +x = (sabs((cx - cy : U32)) <= 1 : U32) || (sabs((cx + cy : U32)) <= 1 : U32)
      sel(x && (sabs(cx) <= 6 : U32), 14168128, TR())
    case 10:
      +wave = (sabs((cy - wsin((cx * 20 : U32), 5) : U32)) <= 1 : U32) && (sabs(cx) <= 8 : U32)
      sel(wave, 13120044, TR())
    case 11:
      +posts = (U32.is_eq(sabs(cx), 6) && between(cy, (0 - 5 : U32), 4))
      +rope = between(cx, (0 - 6 : U32), 6) && U32.is_eq(cy, (0 - 2 + (sabs(cx) >> 2n) : U32))
      sel(posts, 7031339, sel(rope, 8011680, sel(Art.dia(cx, (cy - 4 : U32)), 10125936, TR())))
    case 12:
      # a looking glass
      +rim = ell((cx + 2 : U32), (cy + 2 : U32), 5, 5) && Bool.not(ell((cx + 2 : U32), (cy + 2 : U32), 3, 3))
      +lens = ell((cx + 2 : U32), (cy + 2 : U32), 3, 3)
      +handle = between(cx, 2, 7) && (sabs((cx - cy : U32)) <= 1 : U32)
      +glint = U32.is_eq(cx, (0 - 3 : U32)) && U32.is_eq(cy, (0 - 3 : U32))
      sel(glint, 16777215, sel(rim, 14725184, sel(lens, 10538751, sel(handle, 9127187, TR()))))
    case 13:
      Art.bin(cx, (cy - 4 : U32), U32.is_eq(((t >> 5n) .&. 1 : U32), 1), t, False{})
    case 14:
      Art.bench((cx + 1 : U32), (cy + 4 : U32), False{})
    case 16:
      # the privy at half size
      Art.privy((cx * 2 : U32), (cy * 2 - 12 : U32), t)
    case 33:
      Art.ride.go(10, (cx * 3 : U32), (cy * 3 - 30 : U32), t, 0, 0, 0)
    case 34:
      Art.ride.go(11, (cx * 4 : U32), (cy * 4 - 44 : U32), t, 0, 0, 0)
    case 38:
      Art.ride.go(15, (cx * 4 : U32), (cy * 4 - 46 : U32), t, 0, 0, 0)
    case 35:
      Art.ride.go(12, (cx * 3 : U32), (cy * 3 - 22 : U32), t, 0, 0, 0)
    case 36:
      Art.ride.go(13, (cx * 3 : U32), (cy * 3 - 12 : U32), t, 0, 0, 0)
    case 37:
      Art.ride.go(14, (cx * 3 : U32), (cy * 3 - 8 : U32), t, 0, 0, 0)
    case 40:
      Art.ride.go(17, (cx * 3 : U32), (cy * 3 - 8 : U32), t, 0, 0, 0)
    case 39:
      Art.ride.go(16, (cx * 3 : U32), (cy * 3 - 28 : U32), t, 0, 0, 0)
    case 46:
      # a gold coin over a patch of land
      +coin = ell(cx, (cy + 2 : U32), 4, 4)
      +rim = coin && Bool.not(ell(cx, (cy + 2 : U32), 3, 3))
      +mark = U32.is_eq(cx, 0) && between(cy, (0 - 4 : U32), 0)
      sel(mark, 12092939, sel(rim, 12092939, sel(coin, 16766282, sel(Art.dia(cx, (cy - 4 : U32)), 4626999, TR()))))
    case 41:
      Art.scenery(4, cx, (cy + 7 : U32), 0, t)
    case 42:
      Art.scenery(8, cx, (cy + 6 : U32), 0, t)
    case 43:
      Art.scenery(9, cx, (cy + 2 : U32), 0, t)
    case 44:
      Art.scenery(12, cx, (cy + 6 : U32), 15, t)
    case 45:
      Art.scenery(13, cx, (cy + 4 : U32), 15, t)
    case 30:
      Art.healer((cx * 2 : U32), (cy * 2 - 8 : U32), t)
    case 31:
      Art.wisps((cx * 2 : U32), (cy * 2 - 6 : U32), t)
    case 32:
      Art.ices((cx * 2 : U32), (cy * 2 - 8 : U32), t)
    case 15:
      # a lantern hung from its hook
      +hook = U32.is_eq(cx, 0) && between(cy, (0 - 9 : U32), (0 - 8 : U32))
      +cap = between(cy, (0 - 7 : U32), (0 - 6 : U32)) && (sabs(cx) <= ((1 + (cy + 7) * 2) : U32) : U32)
      +box = (sabs(cx) <= 3 : U32) && between(cy, (0 - 5 : U32), 4)
      +bar = box && (U32.is_eq(sabs(cx), 3) || U32.is_eq(cy, (0 - 5 : U32)) || U32.is_eq(cy, 4) || U32.is_eq(cx, 0))
      +foot = U32.is_eq(cy, 5) && (sabs(cx) <= 1 : U32)
      +flick = U32.is_eq((hash((t >> 3n : U32), 5) .&. 3 : U32), 0)
      sel(hook || cap || bar || foot, 2631720, sel(box, sel(flick, 16771216, sel(U32.is_eq(cy, (0 - 3 : U32)) && U32.is_eq(sabs(cx), 2), 16777184, 16767072)), TR()))
    case 48:
      # a small bridge: a deck on two posts
      +deck = between(cy, (0 - 3 : U32), (0 - 1 : U32)) && (sabs(cx) <= 8 : U32)
      +post = (U32.is_eq(sabs(cx), 6) || U32.is_eq(sabs(cx), 5)) && between(cy, 0, 6)
      +rail = U32.is_eq(cy, (0 - 6 : U32)) && (sabs(cx) <= 8 : U32) || (U32.is_eq(sabs(cx), 8) && between(cy, (0 - 6 : U32), (0 - 3 : U32)))
      sel(deck, sel(U32.is_eq((cx .&. 3 : U32), 0), 5913890, 10119226), sel(post, 5913890, sel(rail, 7031339, TR())))
    case 47:
      # a blueprint: a blue sheet, its grid, a white coaster curve
      +sheet = (sabs(cx) <= 7 : U32) && between(cy, (0 - 7 : U32), 6)
      +grid = sheet && (U32.is_eq((cx .&. 3 : U32), 0) || U32.is_eq((cy .&. 3 : U32), 0))
      +cv = (cy + 3 - ((cx * cx) >> 3n) : U32)
      +curve = sheet && U32.is_eq(cv, 0)
      sel(curve, 16777215, sel(grid, 7442412, sel(sheet, 3368601, TR())))
    case _:
      TR()

# a category tab shows the picture of its first tool
def Art.cat_pic(+c: U32) -> U32:
  match c:
    case 20:
      1
    case 21:
      2
    case 22:
      4
    case 23:
      5
    case 24:
      6
    case 25:
      7
    case _:
      c
def Art.icon(+tool: U32, +on: U32, +dx: U32, +dy: U32, +t: U32) -> U32:
  +edge = U32.is_eq(dx, 0) || U32.is_eq(dy, 0) || U32.is_eq(dx, 21) || U32.is_eq(dy, 21)
  +cat = (tool >= 20 : U32) && (tool <= 25 : U32)
  +frame = sel(U32.is_eq(on, 1), 16766282, sel(cat, 9476272, 5917290))
  +fill = sel(U32.is_eq(on, 1), sel(cat, 4610170, 5917216), sel(cat, 3029592, 3025984))
  +cx = (dx - 11 : U32)
  +cy = (dy - 13 : U32)
  +pic = Art.icon_pic(Art.cat_pic(tool), cx, cy, t)
  # a locked tool: dim, with a padlock
  +locked = U32.is_eq(on, 2)
  +shackle = locked && (U32.is_eq(dy, 13) && between(dx, 16, 18) || (U32.is_eq(dx, 15) || U32.is_eq(dx, 19)) && between(dy, 14, 15))
  +body = locked && between(dx, 14, 20) && between(dy, 16, 20)
  sel(edge, sel(locked, 4210760, frame), sel(shackle, 11579568, sel(body, 14725184,
    sel(locked, shade(over(pic, fill), 110), over(pic, fill)))))

