# Eldergrove Faire -- the park simulation. Pure: no IO, no drawing.
#
# Every change to a park goes through Park.step (time passing, building,
# coaster track edits), and LAWS.bend constrains it. The code is shaped so
# the laws stay provable: each field of the park is updated by its own
# function (so a proof about one field never has to look at the others),
# money only moves through ledger entries, and coaster trains only move by
# swapping with an empty neighbouring block.
import Base

# Utilities
# ---------

def sel(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def absd(+a: U32, +b: U32) -> U32:
  sel((a > b : U32), (a - b : U32), (b - a : U32))

def sub0(+a: U32, +b: U32) -> U32:
  sel((a > b : U32), (a - b : U32), 0)

def hash(+x: U32, +y: U32) -> U32:
  +h = ((x * 374761393) + (y * 668265263) + 1442695041 : U32)
  +h2 = ((h .^. (h >> 13n)) * 1274126177 : U32)
  (h2 .^. (h2 >> 16n) : U32)

def hash3(+x: U32, +y: U32, +z: U32) -> U32:
  hash(hash(x, y), z)

# a wrapped U32 read as signed: negative when the top bit is set
def neg(+a: U32) -> Bool:
  (a >= 2147483648 : U32)

# the stat clamp: the same test the stats law checks
def cl255(+x: U32) -> U32:
  sel(U32.is_le(x, 255), x, 255)

def imp(a: Bool, b: Bool) -> Bool:
  Bool.not(a) || b

def len32(-A: Data, +xs: +List<A>) -> U32:
  match xs:
    case []:
      0
    case h <> t:
      (1 + len32(A, t) : U32)

# Tiles and the map
# -----------------
# The map is 64 x 64 tiles, kept as a depth-6 quadtree so every lookup and
# update is 6 steps and the renderer can share it freely.

def TER_GRASS() -> U32:
  0

def TER_DIRT() -> U32:
  1

def TER_WATER() -> U32:
  2

def TER_WILD() -> U32:
  4

def OBJ_NONE() -> U32:
  0

def OBJ_PATH() -> U32:
  1

def OBJ_TREE() -> U32:
  2

def OBJ_RIDE() -> U32:
  3

def OBJ_GATE() -> U32:
  5

def OBJ_TRACK() -> U32:
  6

def OBJ_QUEUE() -> U32:
  7

def GATE_X() -> U32:
  32

def GATE_Y() -> U32:
  57

def NONE() -> U32:
  255

# h: height (8 px a level), ter: terrain, obj: what stands on it, a/b: its
# details (tree variant; ride index and 1 on the ride's anchor tile; track
# shape and height)
type Tile is Data:
  Tile{h: U32, ter: U32, obj: U32, a: U32, b: U32}

type Q is Data:
  QL{t: Tile}
  QN{a: Q, b: Q, c: Q, d: Q}

def Tile.h(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  h

def Tile.ter(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  ter

def Tile.obj(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  obj

def Tile.a(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  a

def Tile.b(t: Tile) -> U32:
  Tile{h, ter, obj, a, b} = t
  b

def Q.pick(bx: Bool, by: Bool, +a: Q, +b: Q, +c: Q, +d: Q) -> Q:
  match bx by:
    case False{} False{}:
      a
    case True{} False{}:
      b
    case False{} True{}:
      c
    case True{} True{}:
      d

def Q.place(bx: Bool, by: Bool, n: Q, a: Q, b: Q, c: Q, d: Q) -> Q:
  match bx by:
    case False{} False{}:
      QN{n, b, c, d}
    case True{} False{}:
      QN{a, n, c, d}
    case False{} True{}:
      QN{a, b, n, d}
    case True{} True{}:
      QN{a, b, c, n}

def Q.bit(+x: U32, +m: U32) -> Bool:
  Bool.not(U32.is_eq((x .&. m : U32), 0))

# (bx, by: this level's bits of x and y; descending into just the one child
# keeps lookups free of reference-count work on the other three)
def Q.find(+d: Nat, +q: Q, bx: Bool, by: Bool, +x: U32, +y: U32, +m: U32) -> Tile:
  match d q bx by:
    case _ QL{t} _ _:
      t
    case 0n QN{a, b, c, e} _ _:
      Tile{0, 0, 0, 0, 0}
    case 1n+p QN{a, b, c, e} False{} False{}:
      Q.find(p, a, Q.bit(x, (m >> 1n : U32)), Q.bit(y, (m >> 1n : U32)), x, y, (m >> 1n : U32))
    case 1n+p QN{a, b, c, e} True{} False{}:
      Q.find(p, b, Q.bit(x, (m >> 1n : U32)), Q.bit(y, (m >> 1n : U32)), x, y, (m >> 1n : U32))
    case 1n+p QN{a, b, c, e} False{} True{}:
      Q.find(p, c, Q.bit(x, (m >> 1n : U32)), Q.bit(y, (m >> 1n : U32)), x, y, (m >> 1n : U32))
    case 1n+p QN{a, b, c, e} True{} True{}:
      Q.find(p, e, Q.bit(x, (m >> 1n : U32)), Q.bit(y, (m >> 1n : U32)), x, y, (m >> 1n : U32))

def Q.get(+d: Nat, +q: Q, +x: U32, +y: U32, +m: U32) -> Tile:
  Q.find(d, q, Q.bit(x, m), Q.bit(y, m), x, y, m)

def Q.set(+d: Nat, +q: Q, +x: U32, +y: U32, +m: U32, t: Tile) -> Q:
  match d q:
    case _ QL{old}:
      QL{t}
    case 0n QN{a, b, c, e}:
      QN{a, b, c, e}
    case 1n+p QN{a, b, c, e}:
      +bx = Q.bit(x, m)
      +by = Q.bit(y, m)
      Q.place(bx, by, Q.set(p, Q.pick(bx, by, a, b, c, e), x, y,
        (m >> 1n : U32), t), a, b, c, e)

def inmap(+x: U32, +y: U32) -> Bool:
  ((x < 64) && (y < 64) : U32)

def Land.get.go(in: Bool, +q: Q, +x: U32, +y: U32) -> Tile:
  match in:
    case True{}:
      Q.get(6n, q, x, y, 32)
    case False{}:
      Tile{0, 4, 0, 0, 0}

def Land.get(+q: Q, +x: U32, +y: U32) -> Tile:
  Land.get.go(inmap(x, y), q, x, y)

def Land.set(+q: Q, +x: U32, +y: U32, t: Tile) -> Q:
  Q.set(6n, q, x, y, 32, t)

def Land.h(+q: Q, +x: U32, +y: U32) -> U32:
  Tile.h(Land.get(q, x, y))

def Land.obj(+q: Q, +x: U32, +y: U32) -> U32:
  Tile.obj(Land.get(q, x, y))

def Land.qn(+q: Q, +x: U32, +y: U32) -> U32:
  sel(U32.is_eq(Land.obj(q, x, y), 7), 1, 0)

# a ride or coaster track beside a queue marks the queue's front
def Land.rn(+q: Q, +x: U32, +y: U32) -> U32:
  +o = Land.obj(q, x, y)
  sel(U32.is_eq(o, 3) || U32.is_eq(o, 6), 1, 0)

# a queue's free end: a lone queue tile, or a line's last tile away from
# the ride (checked only when needed: stepping onto a queue from outside it)
def Land.qend(need: Bool, +q: Q, +x: U32, +y: U32) -> Bool:
  match need:
    case True{}:
      +x1 = (x + 1 : U32)
      +x0 = (x - 1 : U32)
      +y1 = (y + 1 : U32)
      +y0 = (y - 1 : U32)
      +n = (Land.qn(q, x1, y) + Land.qn(q, x0, y) + Land.qn(q, x, y1) + Land.qn(q, x, y0) : U32)
      +r = (Land.rn(q, x1, y) + Land.rn(q, x0, y) + Land.rn(q, x, y1) + Land.rn(q, x, y0) : U32)
      U32.is_eq(n, 0) || U32.is_eq(n, 1) && U32.is_eq(r, 0)
    case False{}:
      True{}

# Every queue tile's `a` is 1 at a free end, 0 elsewhere; worked out again
# after each build or track edit (they can change which tiles are ends)
def Land.fix.go(isq: Bool, +q: Q, +x: U32, +y: U32, +t: Tile) -> Q:
  match isq:
    case True{}:
      Tile{+h, +ter, obj, a, +b} = t
      Land.set(q, x, y, Tile{h, ter, 7, sel(Land.qend(True{}, q, x, y), 1, 0), b})
    case False{}:
      q

def Land.fix.row(+n: Nat, +x: U32, +y: U32, +q: Q) -> Q:
  match n:
    case 0n:
      q
    case 1n+m:
      +t = Land.get(q, x, y)
      Land.fix.row(m, (x + 1 : U32), y, Land.fix.go(U32.is_eq(Tile.obj(t), 7), q, x, y, t))

def Land.fix.rows(+n: Nat, +y: U32, +q: Q) -> Q:
  match n:
    case 0n:
      q
    case 1n+m:
      Land.fix.rows(m, (y + 1 : U32), Land.fix.row(64n, 0, y, q))

def Land.fix(+q: Q) -> Q:
  Land.fix.rows(64n, 0, q)

# a guest may step onto a path or the gate at the same height -- from a
# queue (fq) only at its free end (fe) -- and onto a queue tile only when
# heading for a ride (qok), from outside it only at its free end.
# 0: blocked, 1: path, 2: queue, 3: a queue's free end (a queue tile's `a`
# says so; see Land.fix), with the tile's height << 4 when it can be
# stepped on. Paths a level apart join by stairs; the rest must be level.
# a tile's walkway deck: its level, or 0
def Deck.of(+t: Tile) -> U32:
  ((Tile.a(t) >> 24n) .&. 15 : U32)

# the level a new deck on (x, y) takes: the level of a neighbouring deck or
# path that clears what is below (2 over a path, 3 over track), else just
# that clearance
def Deck.near(+q: Q, +x: U32, +y: U32, +base: U32) -> U32:
  +t = Land.get(q, x, y)
  +l = sel(Bool.not(U32.is_eq(Deck.of(t), 0)), Deck.of(t), sel(U32.is_eq(Tile.obj(t), 1), Tile.h(t), 0))
  sel((l >= base : U32) && inmap(x, y), l, 0)

def Deck.level(+q: Q, +x: U32, +y: U32) -> U32:
  +t = Land.get(q, x, y)
  +base = sel(U32.is_eq(Tile.obj(t), 6), (Tile.b(t) + 3 : U32), (Tile.h(t) + 2 : U32))
  +n = U32.max(U32.max(Deck.near(q, (x + 1 : U32), y, base), Deck.near(q, (x - 1 : U32), y, base)),
    U32.max(Deck.near(q, x, (y + 1 : U32), base), Deck.near(q, x, (y - 1 : U32), base)))
  sel((n > 0 : U32), n, base)

def Land.step.ground(+q: Q, +x: U32, +y: U32, +h: U32, +qok: Bool, +fq: Bool, +fe: Bool, +t: Tile) -> U32:
  +o = Tile.obj(t)
  +th = Tile.h(t)
  +isq = U32.is_eq(o, 7)
  +end = isq && U32.is_eq(Tile.a(t), 1)
  +path = U32.is_eq(o, 1)
  +level = U32.is_eq(th, h) || path && (U32.is_eq(th, (h + 1 : U32)) || U32.is_eq((th + 1 : U32), h))
  +ok = inmap(x, y) && level
    && ((path || U32.is_eq(o, 5)) && (Bool.not(fq) || fe)
      || qok && isq && (fq || end))
  sel(ok, (sel(isq, sel(end, 3, 2), 1) .|. (th << 4n) : U32), 0)

# Map generation: the starting land of Eldergrove
# -----------------------------------------------

def Land.step(+q: Q, +x: U32, +y: U32, +h: U32, +qok: Bool, +fq: Bool, +fe: Bool) -> U32:
  +t0 = Land.get(q, x, y)
  +dk = Deck.of(t0)
  +ondk = inmap(x, y) && Bool.not(U32.is_eq(dk, 0)) && U32.is_eq(dk, h) && (Bool.not(fq) || fe)
  sel(ondk, (9 .|. (dk << 4n) : U32), Land.step.ground(q, x, y, h, qok, fq, fe, t0))

# on the ground layer (code 9: 1 | 8 up on a deck)
def in_rect(+x: U32, +y: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> Bool:
  ((x >= x0) && (x <= x1) && (y >= y0) && (y <= y1) : U32)

def Gen.is_path(+x: U32, +y: U32) -> Bool:
  (U32.is_eq(x, 32) && (y >= 20) && (y <= 56) : U32)
    || (U32.is_eq(y, 36) && (x >= 12) && (x <= 52) : U32)
    || (U32.is_eq(y, 20) && (x >= 12) && (x <= 52) : U32)
    || (U32.is_eq(x, 12) && (y >= 20) && (y <= 36) : U32)
    || (U32.is_eq(x, 52) && (y >= 20) && (y <= 36) : U32)
    || (U32.is_eq(y, 46) && (x >= 26) && (x <= 38) : U32)
    || in_rect(x, y, 17, 37, 17, 37)

def Gen.wild(+x: U32, +y: U32) -> Bool:
  ((x < 6) || (y < 6) || (x > 57) || (y > 57) : U32)

def Gen.lake(+x: U32, +y: U32) -> Bool:
  +dx = absd(x, 22)
  +dy = absd(y, 27)
  ((dx * dx + dy * dy) < 22 : U32) || in_rect(x, y, 14, 42, 22, 45)

def Gen.hill(+x: U32, +y: U32) -> U32:
  +dx = absd(x, 44)
  +dy = absd(y, 12)
  +d2 = (dx * dx + dy * dy : U32)
  sel((d2 < 9 : U32), 4, sel((d2 < 25 : U32), 3, sel((d2 < 49 : U32), 2, 0)))

# places the first builds need free of trees
def Gen.clear(+x: U32, +y: U32) -> Bool:
  in_rect(x, y, 13, 37, 25, 45) || in_rect(x, y, 27, 21, 37, 50)
    || in_rect(x, y, 13, 21, 18, 35) || in_rect(x, y, 30, 55, 34, 58)

def Gen.near_path(+x: U32, +y: U32) -> Bool:
  Gen.is_path(x, y) || Gen.is_path((x + 1 : U32), y)
    || Gen.is_path((x - 1 : U32), y) || Gen.is_path(x, (y + 1 : U32))
    || Gen.is_path(x, (y - 1 : U32))

def Gen.tree(+x: U32, +y: U32, +h: U32, +r: U32) -> Tile:
  Tile{h, 0, 2, (r >> 8n .&. 3 : U32), 0}

def Gen.inner(+x: U32, +y: U32) -> Tile:
  +r = hash(x, y)
  +hh = Gen.hill(x, y)
  +h = sel(Gen.lake(x, y), 0, sel((hh > 0 : U32), hh, 1))
  +gate = U32.is_eq(x, GATE_X()) && U32.is_eq(y, GATE_Y())
  +tree = Bool.not(Gen.near_path(x, y)) && Bool.not(Gen.clear(x, y))
    && Bool.not(Gen.lake(x, y)) && U32.is_eq((r .&. 7 : U32), 0)
  +queue = in_rect(x, y, 34, 27, 34, 29) || in_rect(x, y, 33, 27, 33, 27)
    || in_rect(x, y, 31, 38, 31, 39) || in_rect(x, y, 33, 21, 33, 23)
    || in_rect(x, y, 49, 37, 49, 37) || in_rect(x, y, 13, 37, 16, 37)
  Bool.pick(Tile, gate, Tile{1, 1, 5, 0, 0},
    Bool.pick(Tile, queue, Tile{h, 1, 7, 0, 0},
    Bool.pick(Tile, Gen.lake(x, y), Tile{0, 2, 0, 0, 0},
      Bool.pick(Tile, Gen.is_path(x, y), Tile{h, 1, 1, 0, 0},
        Bool.pick(Tile, tree, Gen.tree(x, y, h, r), Tile{h, 0, 0, 0, 0})))))

def Gen.outer(+x: U32, +y: U32) -> Tile:
  +r = hash(x, y)
  +h = sel(U32.is_eq((r .&. 3 : U32), 0), 2, 1)
  +tree = Bool.not(U32.is_eq((r .&. 3 : U32), 3))
  Bool.pick(Tile, tree, Tile{h, 4, 2, (r >> 8n .&. 1 : U32), 0},
    Tile{h, 4, 0, 0, 0})

def Gen.tile(+x: U32, +y: U32) -> Tile:
  Bool.pick(Tile, Gen.wild(x, y) && Bool.not(U32.is_eq(x, GATE_X())
    && U32.is_eq(y, GATE_Y())), Gen.outer(x, y), Gen.inner(x, y))

def Q.build(+d: Nat, +x0: U32, +y0: U32) -> Q:
  match d:
    case 0n:
      QL{Gen.tile(x0, y0)}
    case 1n+p:
      +s = U32.shln(1, p)
      +x1 = (x0 + s : U32)
      +y1 = (y0 + s : U32)
      a b c e = Q.build(p, x0, y0) Q.build(p, x1, y0) Q.build(p, x0, y1)
        Q.build(p, x1, y1)
      QN{a, b, c, e}

# Rides
# -----
# kind: 0 demolished, 1 Dragon Carousel (2x2), 2 Arcane Spire, 3 Potion
# Stall, 4 Troll Tavern, 5 Wyrm Coaster (its station tile)

# kind 1 carousel, 2 spire, 3 potion stall, 4 tavern, 5 coaster (0: gone);
# x, y, w, h: footprint; open: 1 when open. The cycle: ph 0 loading, 1 running,
# 2 unloading, tm ticks into it (loading: since the first rider sat down).
# ent, ex: entrance (a queue tile) and exit (a path tile), packed i * 64 + j
# or NONE, and qlen: guests in its queue, all refreshed every tick. wmin,
# wmax: the loading waits. total, earned: customers and gold so far; born:
# the tick it was built. rate: its ratings, excitement | intensity << 10 |
# nausea << 20, each in hundredths (see Ride.rating).
type Ride is Data:
  Ride{kind: U32, x: U32, y: U32, w: U32, h: U32, price: U32, open: U32,
    ph: U32, tm: U32, ent: U32, ex: U32, qlen: U32, wmin: U32, wmax: U32,
    total: U32, earned: U32, born: U32, rate: U32, wear: U32}

# rides two tiles square: the carousel, swing, wheel, crypt, bumpers,
# labyrinth and flume; the rest take one tile
def Ride.size(+k: U32) -> U32:
  sel(U32.is_eq(k, 1) || (k >= 10 : U32) && (k <= 14 : U32) || U32.is_eq(k, 17), 2, 1)

def Ride.cost(+k: U32) -> U32:
  match k:
    case 1:
      900
    case 2:
      1200
    case 3:
      300
    case 4:
      400
    case 6:
      150
    case 7:
      350
    case 8:
      250
    case 9:
      300
    case 10:
      1400
    case 11:
      1100
    case 12:
      1500
    case 13:
      1000
    case 14:
      700
    case 15:
      1000
    case 16:
      1600
    case 17:
      1900
    case _:
      0

def Ride.fee(+k: U32) -> U32:
  match k:
    case 1:
      3
    case 2:
      4
    case 3:
      2
    case 4:
      4
    case 5:
      6
    case 7:
      2
    case 8:
      3
    case 9:
      2
    case 10:
      5
    case 11:
      3
    case 12:
      5
    case 13:
      4
    case 14:
      2
    case 15:
      3
    case 16:
      6
    case 17:
      6
    case _:
      0

def Ride.upkeep(+k: U32) -> U32:
  match k:
    case 1:
      25
    case 2:
      35
    case 3:
      10
    case 4:
      12
    case 5:
      60
    case 6:
      5
    case 7:
      10
    case 8:
      8
    case 9:
      10
    case 10:
      35
    case 11:
      30
    case 12:
      40
    case 13:
      30
    case 14:
      15
    case 15:
      25
    case 16:
      45
    case 17:
      50
    case _:
      0

# how long a ride runs; a shop's serving time
def Ride.duration(+k: U32) -> U32:
  match k:
    case 1:
      448
    case 2:
      512
    case 3:
      20
    case 4:
      40
    case 5:
      360
    case 6:
      40
    case 7:
      60
    case 8:
      20
    case 9:
      25
    case 10:
      480
    case 11:
      640
    case 12:
      560
    case 13:
      480
    case 14:
      720
    case 15:
      600
    case 16:
      420
    case 17:
      560
    case _:
      10

# Ratings, in hundredths: excitement (how much fun), intensity (how wild),
# nausea (how queasy it leaves you), packed E | I << 10 | N << 20
def Rate.pack(+e: U32, +i: U32, +n: U32) -> U32:
  (U32.min(e, 999) .|. (U32.min(i, 999) << 10n) .|. (U32.min(n, 999) << 20n) : U32)

def Rate.e(+r: U32) -> U32:
  (r .&. 1023 : U32)

def Rate.i(+r: U32) -> U32:
  ((r >> 10n) .&. 1023 : U32)

def Rate.n(+r: U32) -> U32:
  ((r >> 20n) .&. 1023 : U32)

# the fixed rides' ratings (the coaster's come from its track)
def Ride.rate0(+k: U32) -> U32:
  match k:
    case 1:
      Rate.pack(160, 60, 30)
    case 2:
      Rate.pack(260, 210, 130)
    case 10:
      Rate.pack(320, 380, 250)
    case 11:
      Rate.pack(190, 40, 20)
    case 12:
      Rate.pack(270, 120, 60)
    case 13:
      Rate.pack(230, 150, 50)
    case 14:
      Rate.pack(160, 20, 10)
    case 15:
      Rate.pack(180, 30, 30)
    case 16:
      Rate.pack(390, 460, 380)
    case 17:
      Rate.pack(310, 200, 90)
    case _:
      0

def Ride.shop(+k: U32) -> Bool:
  U32.is_eq(k, 3) || U32.is_eq(k, 4) || U32.is_eq(k, 6) || U32.is_eq(k, 7) || U32.is_eq(k, 8) || U32.is_eq(k, 9)

# which ride a building tool puts down (0: none): 5-8 the first four kinds,
# 16 the Privy (kind 6)
def Tool.kind(+tool: U32) -> U32:
  match tool:
    case 5:
      1
    case 6:
      2
    case 7:
      3
    case 8:
      4
    case 16:
      6
    case 30:
      7
    case 31:
      8
    case 32:
      9
    case 33:
      10
    case 34:
      11
    case 35:
      12
    case 36:
      13
    case 37:
      14
    case 38:
      15
    case 39:
      16
    case 40:
      17
    case _:
      0

# the rides that run in cycles
def Ride.cycles(+k: U32) -> Bool:
  U32.is_eq(k, 1) || U32.is_eq(k, 2) || (k >= 10 : U32) && (k <= 17 : U32)

# prices: 0..20 gold; the entry fee: 0..40
def Price.cap(+v: U32) -> U32:
  sel(U32.is_le(v, 20), v, 20)

def Fee.cap(+v: U32) -> U32:
  sel(U32.is_le(v, 40), v, 40)

# a new coaster, closed, its track's index kept in h
def Ride.coaster(+x: U32, +y: U32, +n: U32, +t: U32) -> Ride:
  Ride{5, x, y, 1, n, Price.cap(Ride.fee(5)), 0, 0, 0, NONE(), NONE(), 0, 60, 420, 0, 0, t, Ride.rate0(5), 255}

def Ride.ht(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  h

def Ride.new(+k: U32, +x: U32, +y: U32, +s: U32, +open: U32, +t: U32) -> Ride:
  Ride{k, x, y, s, s, Price.cap(Ride.fee(k)), open, 0, 0, NONE(), NONE(), 0, 60, 420, 0, 0, t, Ride.rate0(k), 255}

def Ride.fun(+k: U32) -> U32:
  match k:
    case 1:
      35
    case 2:
      45
    case 5:
      80
    case _:
      5

def Ride.thrill(+k: U32) -> U32:
  match k:
    case 1:
      8
    case 2:
      40
    case 5:
      55
    case _:
      0

def Ride.kind(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  kind

# open, standing, and (shops aside) with both an entrance and an exit
def Ride.is_open(r: Ride) -> Bool:
  Ride{+kind, x, y, w, h, price, open, ph, tm, +ent, +ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  U32.is_eq(open, 1) && Bool.not(U32.is_eq(kind, 0))
    && (Ride.shop(kind) || Bool.not(U32.is_eq(ent, NONE())) && Bool.not(U32.is_eq(ex, NONE())))

def Ride.price(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  price

def Ride.cx(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  x

def Ride.cy(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  y

def Ride.wd(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  w

def Ride.ph(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  ph

def Ride.tm(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  tm

def Ride.ent(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  ent

def Ride.ex(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  ex

def Ride.qlen(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  qlen

def Ride.wmin(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  wmin

def Ride.wmax(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  wmax

def Ride.total(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  total

def Ride.earned(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  earned

def Ride.born(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  born

def Ride.rate(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  rate

def Ride.open_flag(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  open

# distance from a tile to the nearest tile of the ride's footprint
def Ride.dist(r: Ride, +i: U32, +j: U32) -> U32:
  Ride{kind, +x, +y, +w, +h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  +ci = U32.min(U32.max(i, x), (x + w - 1 : U32))
  +cj = U32.min(U32.max(j, y), (y + h - 1 : U32))
  (absd(i, ci) + absd(j, cj) : U32)

# the i-th ride (stops there; past the end, a demolished nothing)
def Rides.get(+rs: +List<Ride>, +i: U32) -> Ride:
  match rs i:
    case Nil{} _:
      Ride{0, 0, 0, 1, 1, 0, 0, 0, 0, NONE(), NONE(), 0, 0, 0, 0, 0, 0, 0, 255}
    case Con{r, rest} 0:
      r
    case Con{r, rest} _:
      Rides.get(rest, (i - 1 : U32))

# Guests: the adventurers
# -----------------------
# x, y: position in 1/16 tile; dir: 0 +x, 1 +y, 2 -x, 3 -y; st: 0 walking,
# 1 riding (ride tgt, tmr ticks left), 2 heading home, 3 gone; tgt: the ride
# they want (NONE: none); tmr: ride time or patience; look: class/colours

type Guest is Data:
  Guest{id: U32, x: U32, y: U32, dir: U32, st: U32, tgt: U32, tmr: U32,
    cash: U32, hunger: U32, thirst: U32, energy: U32, nausea: U32, happy: U32,
    look: U32, mind: U32, bladder: U32}

# a guest's latest thought: code | ride << 8 | (tick / 16) << 16. Codes: 1
# "not paying that much for" the ride, 2 "waited too long for", 3 "was
# great", 4 "was too intense"
def Mind.make(+code: U32, +ride: U32, +t: U32) -> U32:
  (code .|. ((ride .&. 255) << 8n) .|. (((t >> 4n) .&. 65535) << 16n) : U32)

def Mind.code(+m: U32) -> U32:
  (m .&. 255 : U32)

def Mind.ride(+m: U32) -> U32:
  ((m >> 8n) .&. 255 : U32)

def Mind.when(+m: U32) -> U32:
  (m >> 16n : U32)

def Guest.clamp(g: Guest) -> Guest:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  Guest{id, x, y, dir, st, tgt, tmr, cash, cl255(hu), cl255(th), cl255(en),
    cl255(na), cl255(ha), lk, mind, cl255(bl)}

def Guest.ok(g: Guest) -> Bool:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  U32.is_le(hu, 255) && U32.is_le(th, 255) && U32.is_le(en, 255)
    && U32.is_le(na, 255) && U32.is_le(ha, 255)

def Guest.gone(g: Guest) -> Bool:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  U32.is_eq(st, 3)

# a new adventurer, their gold already less the entry fee (at most 40, and
# everyone brings at least 40)
# a new guest's look (see Art.guest): folk, tunic, skin from r's low bits;
# a child 1 in 4; beard and straw hat bits; the outfit
def Guest.look0(+r: U32) -> U32:
  +r2 = hash(r, 7)
  ((r .&. 1015) .|. sel(((r2 .&. 3) < 1 : U32), 8, 0) .|. (r2 .&. 3072) .|. (((r2 >> 12n) .&. 3) << 14n) : U32)

def Guest.raw(+id: U32, +t: U32, +fee: U32) -> Guest:
  +r = hash(id, t)
  Guest{id, (GATE_X() * 16 + 8 : U32), (GATE_Y() * 16 + 8 : U32),
    3, 0, NONE(), 0, (40 + (r .&. 127) - U32.min(fee, 40) : U32), (r >> 7n .&. 63 : U32),
    (r >> 13n .&. 63 : U32), (190 + (r >> 19n .&. 63) : U32), 0, 200, Guest.look0(r), 0, (r >> 26n : U32)}

def Guest.new(+id: U32, +t: U32, +fee: U32) -> Guest:
  Guest.clamp(Guest.raw(id, t, fee))

def dx_of(+d: U32) -> U32:
  match d:
    case 0:
      1
    case 2:
      4294967295
    case _:
      0

def dy_of(+d: U32) -> U32:
  match d:
    case 1:
      1
    case 3:
      4294967295
    case _:
      0

# how far from (tx, ty) a guest can get by walking on from tile (i, j),
# heading d, within n more steps (never turning straight back). A branch
# that dead-ends away from the target is worthless (99999), so guests stop
# walking into dead-end spurs. `ok`: whether (i, j) can be walked at all.
def Guest.arr(+i: U32, +j: U32, +tx: U32, +ty: U32, +lim: U32) -> Bool:
  ((absd(i, tx) + absd(j, ty)) <= lim : U32)

# (arr: (i, j) is already within lim of the target, so the search stops)
def Guest.reach(+n: Nat, ok: Bool, arr: Bool, +q: Q, +i: U32, +j: U32, +h: U32, +d: U32,
  +tx: U32, +ty: U32, +qok: Bool, +fq: Bool, +fe: Bool, +lim: U32) -> U32:
  match n ok arr:
    case _ False{} _:
      99999
    case _ True{} True{}:
      (absd(i, tx) + absd(j, ty) : U32)
    case 0n True{} False{}:
      (absd(i, tx) + absd(j, ty) : U32)
    case 1n+p True{} False{}:
      +back = ((d + 2) .&. 3 : U32)
      +i1 = (i + 1 : U32)
      +i0 = (i - 1 : U32)
      +j1 = (j + 1 : U32)
      +j0 = (j - 1 : U32)
      +c0 = Land.step(q, i1, j, h, qok, fq, fe)
      +r0 = Guest.reach(p, Bool.not(U32.is_eq(back, 0)) && Bool.not(U32.is_eq((c0 .&. 15 : U32), 0)),
        Guest.arr(i1, j, tx, ty, lim), q, i1, j, (c0 >> 4n : U32), 0, tx, ty, qok,
        U32.is_eq((c0 .&. 15 : U32), 2) || U32.is_eq((c0 .&. 15 : U32), 3), Bool.not(U32.is_eq((c0 .&. 15 : U32), 2)), lim)
      +c1 = Land.step(q, i, j1, h, qok, fq, fe)
      +r1 = Guest.reach(p, Bool.not(U32.is_eq(back, 1)) && Bool.not(U32.is_eq((c1 .&. 15 : U32), 0)),
        Guest.arr(i, j1, tx, ty, lim), q, i, j1, (c1 >> 4n : U32), 1, tx, ty, qok,
        U32.is_eq((c1 .&. 15 : U32), 2) || U32.is_eq((c1 .&. 15 : U32), 3), Bool.not(U32.is_eq((c1 .&. 15 : U32), 2)), lim)
      +c2 = Land.step(q, i0, j, h, qok, fq, fe)
      +r2 = Guest.reach(p, Bool.not(U32.is_eq(back, 2)) && Bool.not(U32.is_eq((c2 .&. 15 : U32), 0)),
        Guest.arr(i0, j, tx, ty, lim), q, i0, j, (c2 >> 4n : U32), 2, tx, ty, qok,
        U32.is_eq((c2 .&. 15 : U32), 2) || U32.is_eq((c2 .&. 15 : U32), 3), Bool.not(U32.is_eq((c2 .&. 15 : U32), 2)), lim)
      +c3 = Land.step(q, i, j0, h, qok, fq, fe)
      +r3 = Guest.reach(p, Bool.not(U32.is_eq(back, 3)) && Bool.not(U32.is_eq((c3 .&. 15 : U32), 0)),
        Guest.arr(i, j0, tx, ty, lim), q, i, j0, (c3 >> 4n : U32), 3, tx, ty, qok,
        U32.is_eq((c3 .&. 15 : U32), 2) || U32.is_eq((c3 .&. 15 : U32), 3), Bool.not(U32.is_eq((c3 .&. 15 : U32), 2)), lim)
      +best = U32.min(U32.min(r0, r1), U32.min(r2, r3))
      +d0 = (absd(i, tx) + absd(j, ty) : U32)
      sel((best < 99999 : U32), U32.min(d0, best), 99999)

# how much a guest likes stepping from tile (i, j) in direction d, heading
# for tile (tx, ty): lower is better; 99999 when it cannot step there
def Guest.score(+q: Q, +i: U32, +j: U32, +h: U32, +d: U32, +back: U32,
  +tx: U32, +ty: U32, +r: U32, +qok: Bool, +fq: Bool, +fe: Bool, +lim: U32) -> U32:
  +ni = (i + dx_of(d) : U32)
  +nj = (j + dy_of(d) : U32)
  +c = Land.step(q, ni, nj, h, qok, fq, fe)
  +code = (c .&. 15 : U32)
  +ok = Bool.not(U32.is_eq(code, 0))
  +v = Guest.reach(12n, ok, Guest.arr(ni, nj, tx, ty, lim), q, ni, nj, (c >> 4n : U32), d, tx, ty, qok,
    U32.is_eq(code, 2) || U32.is_eq(code, 3), Bool.not(U32.is_eq(code, 2)), lim)
  +pen = sel(U32.is_eq(d, back), 7, 0)
  +jit = (hash(r, d) .&. 7 : U32)
  sel(ok, sel((v >= 99999 : U32), (90000 + pen : U32), (v * 4 + pen + jit : U32)), 99999)

def best2(+da: U32, +sa: U32, +db: U32, +sb: U32) -> U32:
  sel((sb < sa : U32), db, da)

def min2(+sa: U32, +sb: U32) -> U32:
  U32.min(sa, sb)

# the direction to take at a tile centre (the current one if nothing works)
def Guest.choose(+q: Q, +i: U32, +j: U32, +h: U32, +dir: U32, +tx: U32,
  +ty: U32, +r: U32, +qok: Bool, +fq: Bool, +fe: Bool, +lim: U32) -> U32:
  +back = ((dir + 2) .&. 3 : U32)
  +s0 = Guest.score(q, i, j, h, 0, back, tx, ty, r, qok, fq, fe, lim)
  +s1 = Guest.score(q, i, j, h, 1, back, tx, ty, r, qok, fq, fe, lim)
  +s2 = Guest.score(q, i, j, h, 2, back, tx, ty, r, qok, fq, fe, lim)
  +s3 = Guest.score(q, i, j, h, 3, back, tx, ty, r, qok, fq, fe, lim)
  +d01 = best2(0, s0, 1, s1)
  +d23 = best2(2, s2, 3, s3)
  +best = best2(d01, min2(s0, s1), d23, min2(s2, s3))
  sel((min2(min2(s0, s1), min2(s2, s3)) < 99999 : U32), best, dir)

def Guest.can_step(+q: Q, +i: U32, +j: U32, +h: U32, +d: U32, +qok: Bool, +fq: Bool, +fe: Bool) -> Bool:
  Bool.not(U32.is_eq(Land.step(q, (i + dx_of(d) : U32), (j + dy_of(d) : U32), h, qok, fq, fe), 0))

# which ride a guest heads for: the best-scoring open one they can afford
# of the kind they want (0: any attraction)
def Guest.want_ok(+want: U32, +k: U32) -> Bool:
  match want:
    case 0:
      U32.is_eq(k, 1) || U32.is_eq(k, 2) || U32.is_eq(k, 5) || (k >= 10 : U32) && (k <= 17 : U32)
    case _:
      U32.is_eq(k, want)

def Ride.seats(+k: U32) -> U32:
  sel(U32.is_eq(k, 5), 6, sel(Ride.cycles(k), 8, 4))

# how much intensity a guest takes: children much less
def Guest.tol(+lk: U32) -> U32:
  +v = (((lk * 37) + (lk >> 4n)) : U32)
  sel(U32.is_eq((lk .&. 8 : U32), 0), (220 + (v .&. 511) : U32), (60 + (v .&. 127) : U32))

# a ride's effect on a rider's happiness: its excitement, less a penalty when
# it is wilder than they like
# what a ride is worth to a guest, in gold: its excitement, or for a potion
# or a meal how thirsty or hungry they are
def Guest.worth(+k: U32, +rate: U32, +hu: U32, +th: U32) -> U32:
  match k:
    case 3:
      (2 + th / 64 : U32)
    case 4:
      (3 + hu / 64 : U32)
    case 6:
      2
    case 7:
      3
    case 8:
      4
    case 9:
      (2 + th / 80 : U32)
    case _:
      (1 + Rate.e(rate) * 2 / 100 : U32)

# the best ride to head for (skipping ones too dear when `judge`, and the one
# they last refused to pay for)
def Guest.pick(+rs: +List<Ride>, +idx: U32, +want: U32, +i: U32, +j: U32,
  +cash: U32, +r: U32, +lk: U32, +hu: U32, +th: U32, +judge: Bool, +avoid: U32, +best: U32, +bs: U32) -> U32:
  match rs:
    case []:
      best
    case rd <> rest:
      +k = Ride.kind(rd)
      +ql = Ride.qlen(rd)
      +rate = Ride.rate(rd)
      +ok = Ride.is_open(rd) && Guest.want_ok(want, k)
        && U32.is_le(Ride.price(rd), cash) && (ql < Ride.seats(k) * 3 : U32)
        && (Rate.i(rate) <= Guest.tol(lk) + 100 : U32)
        && (Bool.not(judge) || U32.is_le(Ride.price(rd), Guest.worth(k, rate, hu, th)) && Bool.not(U32.is_eq(idx, avoid)))
      +s = sub0((Ride.dist(rd, i, j) + ql + (hash(r, idx) .&. 31 : U32) + 40 : U32), (Rate.e(rate) / 12 : U32))
      +take = ok && (s < bs : U32)
      Guest.pick(rest, (idx + 1 : U32), want, i, j, cash, r, lk, hu, th, judge, avoid,
        sel(take, idx, best), sel(take, s, bs))

# only a guest who needs a target, or stands at a tile centre about to step,
# pays for the search
# the choice | what they would have chosen, price aside << 8
def Guest.pick_if(need: Bool, +rs: +List<Ride>, +want: U32, +i: U32, +j: U32,
  +cash: U32, +r: U32, +lk: U32, +hu: U32, +th: U32, +avoid: U32) -> U32:
  match need:
    case True{}:
      (Guest.pick(rs, 0, want, i, j, cash, r, lk, hu, th, True{}, avoid, NONE(), 99999)
        .|. (Guest.pick(rs, 0, want, i, j, cash, r, lk, hu, th, False{}, NONE(), NONE(), 99999) << 8n) : U32)
    case False{}:
      (NONE() .|. (NONE() << 8n) : U32)

def Guest.steer(now: Bool, +q: Q, +i: U32, +j: U32, +h: U32, +dir: U32,
  +tx: U32, +ty: U32, +r: U32, +qok: Bool, +fq: Bool, +fe: Bool, +lim: U32) -> U32:
  match now:
    case True{}:
      Guest.choose(q, i, j, h, dir, tx, ty, r, qok, fq, fe, lim)
    case False{}:
      dir

def Guest.at_center(+x: U32, +y: U32) -> Bool:
  U32.is_eq((x .&. 15 : U32), 8) && U32.is_eq((y .&. 15 : U32), 8)

# Seats and boarding
# ------------------
# Every tick, one pass over the guests (Boards.plan) seats whoever is ready
# to board, in order, into free seats -- so no two guests ever share a seat
# and no ride is filled past its seats. The guest updates, the ticket sales
# and the riders drawn on the rides all read that one plan. A rider keeps
# their seat in `dir` (coaster: train id * 64 + seat).

def bit8(+n: U32) -> U32:
  match n:
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
    case _:
      256

def Seat.has(+f: U32, +b: U32) -> Bool:
  Bool.not(U32.is_eq((f .&. b : U32), 0))

type Board is Data:
  Board{gid: U32, ride: U32, seat: U32}

def Board.at(b: Board, +r: U32, +s: U32) -> Bool:
  Board{g, ride, seat} = b
  U32.is_eq(ride, r) && U32.is_eq(seat, s)

# whether the plan already gave seat s of ride r to someone
def Boards.taken(+bs: +List<Board>, +r: U32, +s: U32) -> Bool:
  match bs:
    case []:
      False{}
    case b <> rest:
      Board.at(b, r, s) || Boards.taken(rest, r, s)

# whether seat k is free of riders (m0: seats 0-31 held, m1: 32-63)
def Seat.open(+m0: U32, +m1: U32, +k: U32) -> Bool:
  U32.is_eq(((sel((k < 32 : U32), m0, m1) >> U32.to_nat((k .&. 31 : U32))) .&. 1 : U32), 0)

# seat k of ride r if no rider sits there, it is below cap, and the plan
# (acc) hasn't handed it out yet; else `rest`
def Seat.pick(+m0: U32, +m1: U32, +acc: +List<Board>, +r: U32, +cap: U32, +k: U32, +rest: U32) -> U32:
  sel(Seat.open(m0, m1, k) && (U32.is_lt(k, cap) && Bool.not(Boards.taken(acc, r, k))), k, rest)

# the seats from k on, lowest first
def Seat.scan(+n: Nat, +m0: U32, +m1: U32, +acc: +List<Board>, +r: U32, +cap: U32, +k: U32) -> U32:
  match n:
    case 0n:
      NONE()
    case 1n+p:
      Seat.pick(m0, m1, acc, r, cap, k, Seat.scan(p, m0, m1, acc, r, cap, (k + 1 : U32)))

# the lowest free seat of ride r below cap, or NONE
def Tab.at(+xs: +List<U32>, +i: U32) -> U32:
  match xs:
    case []:
      0
    case x <> rest:
      sel(U32.is_eq(i, 0), x, Tab.at(rest, (i - 1 : U32)))

# the seats taken on each ride (the coaster: on the train loading now)
def Seat.free(+occ: +List<U32>, +acc: +List<Board>, +r: U32, +cap: U32) -> U32:
  Seat.scan(U32.to_nat(U32.min(cap, 64)), Tab.at(occ, (r * 2 : U32)), Tab.at(occ, (r * 2 + 1 : U32)), acc, r, cap, 0)

# a ride's seats: a coaster's train, from its station word; else by kind
type Stn is Data:
  Stn{info: List<&2, U32>}

def Stn.at(s: Stn, +k: U32) -> U32:
  Stn{info} = s
  Tab.at(info, k)

def Ride.cap(r: Ride, +stn: Stn) -> U32:
  +r2 = r
  sel(U32.is_eq(Ride.kind(r2), 5), ((Stn.at(stn, Ride.ht(r2)) >> 13n) .&. 63 : U32), Ride.seats(Ride.kind(r2)))

# the coasters' stations, one word each: open | wait << 1 | the id of the
# train standing there << 16 (65535: none)
type Train is Data:
  Train{id: U32, prog: U32, speed: U32, wait: U32}

# a block: `len` pieces from piece `start`; st is 1 on the station block.
# Holding a train *is* the block's occupancy, so a block can never hold two.
type Slot is Data:
  Free{start: U32, len: U32, st: U32}
  Held{start: U32, len: U32, st: U32, t: Train}

def Stn.of(s: Slot, +acc: U32) -> U32:
  match s:
    case Free{a, n, st}:
      acc
    case Held{a, n, +st, t}:
      Train{+id, prog, speed, +wait} = t
      sel(U32.is_eq(st, 1), ((acc .&. 516097) .|. ((wait .&. 4095) << 1n) .|. ((id .&. 4095) << 20n) : U32), acc)

def Stn.find(+ss: +List<Slot>, +acc: U32) -> U32:
  match ss:
    case []:
      acc
    case s <> rest:
      Stn.find(rest, Stn.of(s, acc))

type Piece is Data:
  Piece{x: U32, y: U32, z: U32, kind: U32, dir: U32}

type Pose is Data:
  Pose{x: U32, y: U32, z: U32, dir: U32}

type Track is Data:
  Track{pieces: List<&2, Piece>, open: Bool, blocks: List<&2, Slot>,
    start: Pose, end: Pose, cfg: U32, stats: U32}

def Test.passed(+st: U32) -> Bool:
  U32.is_eq((st .&. 3 : U32), 2)

# a coaster's station word: open (tested) | the train standing there's wait
# << 1 | seats a train << 13 | that train's id << 20 (4095: none)
def Cfg.cars(+c: U32) -> U32:
  +v = ((c >> 8n) .&. 31 : U32)
  sel(U32.is_eq(v, 0), 3, v)

# the station platform: the leading station pieces
def Piece.kind(p: Piece) -> U32:
  Piece{x, y, z, kind, dir} = p
  kind

# A coaster's settings (its track's cfg): bits 0-1 its type (0 the Wyrm, a
# wooden coaster; 1 a Dwarven Minecart; 2 a Griffin Flyer, hanging below its
# rails), 2-4 how many trains (0: as many as fit), 5-7 the lift hill's speed
# step (speed 12 + 4 * step)
def Pieces.stations(+ps: +List<Piece>) -> U32:
  match ps:
    case []:
      0
    case p <> rest:
      +p2 = p
      sel(U32.is_eq(Piece.kind(p2), 5), (1 + Pieces.stations(rest) : U32), 0)

# cars a train: as set, but one a station piece at most, and 1 to 20
def Track.pieces(t: Track) -> +List<Piece>:
  Track{pieces, open, blocks, start, end, cfg, stats} = t
  pieces

def Track.cfg(t: Track) -> U32:
  Track{pieces, open, blocks, start, end, cfg, stats} = t
  cfg

def Track.cars(+t: Track) -> U32:
  U32.max(U32.min(U32.min(Cfg.cars(Track.cfg(t)), Pieces.stations(Track.pieces(t))), 20), 1)

# a block is long enough for a whole train (cars stand 300 apart, a piece
# is 256), and at least 4 pieces
def Track.stats(t: Track) -> U32:
  Track{pieces, open, blocks, start, end, cfg, stats} = t
  stats

def Track.blocks(t: Track) -> +List<Slot>:
  Track{pieces, open, blocks, start, end, cfg, stats} = t
  blocks

# Staff at work
# -------------
# Wages a month: Brownies 20, Tinkers 35, Watch Knights 30, Bards 25. Hired
# staff start at the gate; each has a post (a ride's tile, taken in turn)
# that they patrol around when they have nothing better to do.
def Track.open(t: Track) -> Bool:
  Track{pieces, open, blocks, start, end, cfg, stats} = t
  open

# a coaster only runs on a closed circuit
def Track.stn(+t: Track) -> U32:
  Stn.find(Track.blocks(t), (sel(Track.open(t) && Test.passed(Track.stats(t)), 1, 0)
    .|. ((Track.cars(t) * 2) << 13n) .|. (4095 << 20n) : U32))

def Tracks.stn(+ts: +List<Track>) -> +List<U32>:
  match ts:
    case []:
      []
    case t <> rest:
      Track.stn(t) <> Tracks.stn(rest)

def Stn.all(+ts: +List<Track>) -> Stn:
  Stn{Tracks.stn(ts)}

# a coaster's track by its index (an empty one past the end)
def Track.empty() -> Track:
  Track{[], False{}, [], Pose{0, 0, 0, 0}, Pose{0, 0, 0, 0}, 0, 0}

def Tracks.get(+ts: +List<Track>, +k: U32) -> Track:
  match ts:
    case []:
      Track.empty()
    case t <> rest:
      Bool.pick(Track, U32.is_eq(k, 0), t, Tracks.get(rest, (k - 1 : U32)))

def Tracks.set(+ts: +List<Track>, +k: U32, +t: Track) -> +List<Track>:
  match ts:
    case []:
      []
    case x <> rest:
      Bool.pick(Track, U32.is_eq(k, 0), t, x) <> Tracks.set(rest, (k - 1 : U32), t)

def Pieces.get(+ps: +List<Piece>, +i: U32) -> Piece:
  match ps:
    case []:
      Piece{0, 0, 0, 0, 0}
    case p <> rest:
      Bool.pick(Piece, U32.is_eq(i, 0), p, Pieces.get(rest, (i - 1 : U32)))

def Cfg.type(+c: U32) -> U32:
  (c .&. 3 : U32)

def Cfg.trains(+c: U32) -> U32:
  ((c >> 2n) .&. 7 : U32)

def Track.blen(+cars: U32) -> U32:
  U32.max(4, (cars * 300 / 256 + 2 : U32))

def Cfg.lift(+c: U32) -> U32:
  (12 + ((c >> 5n) .&. 7) * 4 : U32)

# top speed: minecarts are slower, flyers faster
def Cfg.top(+c: U32) -> U32:
  sel(U32.is_eq(Cfg.type(c), 1), 64, sel(U32.is_eq(Cfg.type(c), 2), 100, 90))

# a new coaster: a Wyrm, as many trains as fit, lift speed 20
def Cfg.new() -> U32:
  64

# how many blocks a track of n pieces makes (see Blocks.make), and how many
# trains fit (one in every third block)
def Blocks.count(+n: U32, +bl: U32) -> U32:
  sel((n < bl * 2 : U32), 1, ((n - bl * 2) / bl + 2 : U32))

def Track.most(+n: U32, +bl: U32) -> U32:
  ((Blocks.count(n, bl) + 2) / 3 : U32)

# a settings op: 16-18 the type, 20/21 one train fewer/more, 22/23 the lift
# slower/faster, 28/29 one car fewer/more (up to maxc)
def Cfg.set(+c: U32, +op: U32, +most: U32, +maxc: U32) -> U32:
  +w0 = Cfg.trains(c)
  +w = sel(U32.is_eq(w0, 0), most, U32.min(w0, most))
  +lv = ((c >> 5n) .&. 7 : U32)
  +ty = sel((op >= 16 : U32) && (op <= 18 : U32), (op - 16 : U32), Cfg.type(c))
  +w2 = sel(U32.is_eq(op, 20), U32.max(sub0(w, 1), 1),
    sel(U32.is_eq(op, 21), U32.min((w + 1 : U32), U32.min(most, 7)), w0))
  +lv2 = sel(U32.is_eq(op, 22), sub0(lv, 1), sel(U32.is_eq(op, 23), U32.min((lv + 1 : U32), 6), lv))
  +cs = U32.min(Cfg.cars(c), maxc)
  +cv = ((c >> 8n) .&. 31 : U32)
  +cv2 = sel(U32.is_eq(op, 28), U32.max(sub0(cs, 1), 1), sel(U32.is_eq(op, 29), U32.min((cs + 1 : U32), maxc), cv))
  (ty .|. (w2 << 2n) .|. (lv2 << 5n) .|. (cv2 << 8n) : U32)

# physics inside a block: lift hills pull at the coaster's lift speed, slopes
# accelerate, the station holds the train while it loads
def Train.adv(t: Train, +start: U32, +len: U32, +st: U32, +ps: +List<Piece>, +cfg: U32)
  -> Train:
  Train{id, +prog, +speed, +wait} = t
  +k = Piece.kind(Pieces.get(ps, (start + (prog >> 8n) : U32)))
  +hold = U32.is_eq(st, 1) && (wait > 0 : U32)
  +s1 = sel(U32.is_eq(k, 6), Cfg.lift(cfg), sel(U32.is_eq(k, 2), (speed + 3 : U32),
    sel(U32.is_eq(k, 1), sub0(speed, 3), sel(U32.is_eq(k, 13), (speed + 7 : U32),
    sel(U32.is_eq(k, 12), sub0(speed, 7), sel(U32.is_eq(k, 9), U32.min(sub0(speed, 1), 24),
      sub0(speed, 1)))))))
  +s2 = sel(hold, 0, U32.min(U32.max(s1, 10), Cfg.top(cfg)))
  +end = (len * 256 : U32)
  Train{id, U32.min((prog + s2 : U32), end), s2, sub0(wait, 1)}

def Slot.adv(s: Slot, +ps: +List<Piece>, +cfg: U32) -> Slot:
  match s:
    case Free{a, n, st}:
      Free{a, n, st}
    case Held{+a, +n, +st, t}:
      Held{a, n, st, Train.adv(t, a, n, st, ps, cfg)}

def Slots.adv(+ss: +List<Slot>, +ps: +List<Piece>, +cfg: U32) -> +List<Slot>:
  match ss:
    case []:
      []
    case s <> rest:
      Slot.adv(s, ps, cfg) <> Slots.adv(rest, ps, cfg)

def Train.ready(t: Train, +len: U32) -> Bool:
  Train{id, prog, speed, wait} = t
  (prog >= len * 256 : U32)

def Slot.cfst(+a: Slot, +b: Slot) -> Slot:
  match a b:
    case Held{sa, na, ta, t} Free{sb, nb, tb}:
      Bool.pick(Slot, Train.ready(t, na), Free{sa, na, ta}, a)
    case _ _:
      a

def Train.enter(t: Train, +len: U32, +st: U32) -> Train:
  Train{id, prog, speed, wait} = t
  Train{id, (prog - len * 256 : U32), speed, sel(U32.is_eq(st, 1), 150, 0)}

def Slot.csnd(+a: Slot, +b: Slot) -> Slot:
  match a b:
    case Held{sa, +na, ta, +t} Free{sb, +nb, +tb}:
      Bool.pick(Slot, Train.ready(t, na), Held{sb, nb, tb, Train.enter(t, na, tb)},
        b)
    case _ _:
      b

# one pass along the blocks, carrying the block just processed
def Slots.pass(+ss: +List<Slot>, +c: Slot) -> +List<Slot>:
  match ss:
    case []:
      [c]
    case b <> rest:
      Slot.cfst(c, b) <> Slots.pass(rest, Slot.csnd(c, b))

# the ring rotates by one each tick, so every pair of neighbours (the last
# and the first included) takes its turn
def Slots.rot(+ss: +List<Slot>) -> +List<Slot>:
  match ss:
    case []:
      []
    case s <> rest:
      List.append(&2, Slot, rest, [s])

def Blocks.step(+ss: +List<Slot>, +ps: +List<Piece>, +cfg: U32) -> +List<Slot>:
  match ss:
    case []:
      []
    case s <> rest:
      Slots.rot(Slots.pass(Slots.adv(rest, ps, cfg), Slot.adv(s, ps, cfg)))

# an open track runs its trains; a test run ends when its train comes round
# (or stalls), and the track closes again
def Test.testing(+st: U32) -> Bool:
  U32.is_eq((st .&. 3 : U32), 1)

def Test.live(+st: U32) -> Bool:
  Test.testing(st) || Test.passed(st)

def Test.fail(+st: U32) -> U32:
  ((st >> 2n) .&. 255 : U32)

def Blocks.pos(+ss: +List<Slot>) -> U32:
  match ss:
    case []:
      999
    case s <> rest:
      match s:
        case Free{a, n, st}:
          Blocks.pos(rest)
        case Held{+a, n, st, t}:
          Train{id, +prog, speed, wait} = t
          (a + (prog >> 8n) : U32)

# watching a test run: it passes when the train comes round to the station
# again, and fails when it reaches the piece it can't climb
def Test.watch(+bs: +List<Slot>, +st: U32) -> U32:
  +pos = U32.min(Blocks.pos(bs), 255)
  +fail = Test.fail(st)
  +last = ((st >> 10n) .&. 255 : U32)
  +left = Bool.not(U32.is_eq((st .&. 262144 : U32), 0)) || (pos > 0 : U32)
  +round = left && (pos < last : U32)
  +stuck = Bool.not(U32.is_eq(fail, 255)) && (pos >= fail : U32)
  +state = sel(stuck, 3, sel(round, 2, 1))
  sel(Test.testing(st), (state .|. (fail << 2n) .|. (pos << 10n) .|. sel(left, 262144, 0) : U32), st)

# a test run: the track opens with one empty train (guests can't board: the
# station counts as closed until the test passes)
def Pose.eq(a: Pose, b: Pose) -> Bool:
  Pose{ax, ay, az, ad} = a
  Pose{bx, by, bz, bd} = b
  U32.is_eq(ax, bx) && U32.is_eq(ay, by) && U32.is_eq(az, bz)
    && U32.is_eq(ad, bd)

# 1/256 of a piece per unit of progress
def Track.closed(t: Track) -> Bool:
  Track{pieces, open, blocks, start, end, cfg, stats} = t
  (len32(Piece, pieces) >= 4 : U32) && Pose.eq(start, end)

def Track.tick.go(open: Bool, +ps: +List<Piece>, +bs: +List<Slot>, +s: Pose,
  +e: Pose, +cfg: U32, +stats: U32) -> Track:
  match open:
    case True{}:
      +bs2 = Blocks.step(bs, ps, cfg)
      +st2 = Test.watch(bs2, stats)
      +shut = {Track{ps, False{}, [], s, e, cfg, stats} : Track}
      +keep = Bool.not(Test.testing(stats) && Bool.not(Test.testing(st2)))
      +on = (keep && Track.closed(shut)) && Test.live(st2)
      Track{ps, on, Bool.pick(+List<Slot>, on, bs2, []), s, e, cfg, st2}
    case False{}:
      Track{ps, False{}, bs, s, e, cfg, stats}

def Track.tick(t: Track) -> Track:
  Track{+pieces, open, blocks, start, end, +cfg, +stats} = t
  Track.tick.go(open, pieces, blocks, start, end, cfg, stats)

# The park
# --------

# The park's books and standing: fee: the entry fee; loan: gold owed;
# rating: the park rating (0..999); now, last: this month's and last month's
# gold by ledger kind (index kind - 1); hist: the guest count, sampled eight
# times a month, newest first (32 samples)
def Tracks.tick(+ts: +List<Track>) -> +List<Track>:
  match ts:
    case []:
      []
    case t <> rest:
      Track.tick(t) <> Tracks.tick(rest)

# a coaster ride keeps its track's index in its h

def Guest.id(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  id

def Guest.tgt(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  tgt

def Guest.dir(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  dir

def Guest.tmr(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  tmr

def Tab.zero.go(+n: Nat, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      Tab.zero.go(p, 0 <> acc)

def Tab.zero(+n: U32, +acc: +List<U32>) -> +List<U32>:
  Tab.zero.go(U32.to_nat(n), acc)

def Tab.or(+xs: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match xs:
    case []:
      []
    case x <> rest:
      sel(U32.is_eq(i, 0), (x .|. v : U32), x) <> Tab.or(rest, (i - 1 : U32), v)

def Occ.put(on: Bool, +tab: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match on:
    case True{}:
      Tab.or(tab, i, v)
    case False{}:
      tab

def Occ.add.go(riding: Bool, +dir: U32, +tgt: U32, +rs: +List<Ride>, +stn: Stn,
  +tab: +List<U32>) -> +List<U32>:
  match riding:
    case True{}:
      +rd = Rides.get(rs, tgt)
      +k = Ride.kind(rd)
      +on = Bool.not(U32.is_eq(k, 5)) || U32.is_eq((dir >> 6n : U32), (Stn.at(stn, Ride.ht(rd)) >> 20n : U32))
      Occ.put(on, tab, (tgt * 2 + ((dir .&. 63) >> 5n) : U32), (1 << U32.to_nat((dir .&. 31 : U32)) : U32))
    case False{}:
      tab

def Occ.add(g: Guest, +rs: +List<Ride>, +stn: Stn, +tab: +List<U32>) -> +List<U32>:
  Guest{id, x, y, +dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  Occ.add.go(U32.is_eq(st, 1), dir, tgt, rs, stn, tab)

def Occ.fill(+gs: +List<Guest>, +rs: +List<Ride>, +stn: Stn, +tab: +List<U32>)
  -> +List<U32>:
  match gs:
    case []:
      tab
    case g <> rest:
      Occ.fill(rest, rs, stn, Occ.add(g, rs, stn, tab))

def Occ.table(+gs: +List<Guest>, +rs: +List<Ride>, +stn: Stn) -> +List<U32>:
  Occ.fill(gs, rs, stn, Tab.zero((len32(Ride, rs) * 2 : U32), []))

def Board.bit(b: Board, +r: U32) -> U32:
  Board{g, ride, +seat} = b
  sel(U32.is_eq(ride, r), bit8(seat), 0)

def Boards.mask(+bs: +List<Board>, +r: U32, +acc: U32) -> U32:
  match bs:
    case []:
      acc
    case b <> rest:
      Boards.mask(rest, r, (acc .|. Board.bit(b, r) : U32))

def Board.is(b: Board, +id: U32) -> Bool:
  Board{g, ride, seat} = b
  U32.is_eq(g, id)

def Board.ride(b: Board) -> U32:
  Board{g, ride, seat} = b
  ride

def Board.seat(b: Board) -> U32:
  Board{g, ride, seat} = b
  seat

def Boards.has(+bs: +List<Board>, +id: U32) -> Bool:
  match bs:
    case []:
      False{}
    case b <> rest:
      Board.is(b, id) || Boards.has(rest, id)

def Boards.seat(+bs: +List<Board>, +id: U32) -> U32:
  match bs:
    case []:
      0
    case b <> rest:
      sel(Board.is(b, id), Board.seat(b), Boards.seat(rest, id))

# Queues, entrances and exits
# ---------------------------
# A queue tile beside a ride is its entrance: a ride with one boards only
# guests standing in its queue. Riders get off onto a path tile beside the
# ride (its exit). In a queue, a guest steps forward only when nobody is
# within half a tile ahead, so lines form single file.

def pk(+i: U32, +j: U32) -> U32:
  (i * 64 + j : U32)

# the n-th tile around a w x w footprint at (x, y), packed i * 64 + j
def Ride.cand(+x: U32, +y: U32, +w: U32, +n: U32) -> U32:
  match n:
    case 0:
      pk(x, (y - 1 : U32))
    case 1:
      pk((x + w : U32), y)
    case 2:
      pk(x, (y + w : U32))
    case 3:
      pk((x - 1 : U32), y)
    case 4:
      pk((x + w - 1 : U32), (y - 1 : U32))
    case 5:
      pk((x + w : U32), (y + w - 1 : U32))
    case 6:
      pk((x + w - 1 : U32), (y + w : U32))
    case _:
      pk((x - 1 : U32), (y + w - 1 : U32))

def Land.obj_at(+q: Q, +e: U32) -> U32:
  Land.obj(q, (e >> 6n : U32), (e .&. 63 : U32))

def Ride.is_at(+q: Q, +x: U32, +y: U32, +w: U32, +n: U32, +o: U32) -> Bool:
  U32.is_eq(Land.obj_at(q, Ride.cand(x, y, w, n)), o)

# the first tile around a w x w footprint holding object o, or NONE
def Ride.find(+q: Q, +x: U32, +y: U32, +w: U32, +o: U32) -> U32:
  sel(Ride.is_at(q, x, y, w, 0, o), Ride.cand(x, y, w, 0), sel(Ride.is_at(q, x, y, w, 1, o), Ride.cand(x, y, w, 1),
    sel(Ride.is_at(q, x, y, w, 2, o), Ride.cand(x, y, w, 2), sel(Ride.is_at(q, x, y, w, 3, o), Ride.cand(x, y, w, 3),
    sel(Ride.is_at(q, x, y, w, 4, o), Ride.cand(x, y, w, 4), sel(Ride.is_at(q, x, y, w, 5, o), Ride.cand(x, y, w, 5),
    sel(Ride.is_at(q, x, y, w, 6, o), Ride.cand(x, y, w, 6), sel(Ride.is_at(q, x, y, w, 7, o), Ride.cand(x, y, w, 7),
    NONE()))))))))

def Coaster.at.go(st: Bool, +q: Q, +x: U32, +y: U32, +o: U32) -> U32:
  match st:
    case True{}:
      Ride.find(q, x, y, 1, o)
    case False{}:
      NONE()

def Coaster.at(p: Piece, +q: Q, +o: U32) -> U32:
  Piece{+x, +y, z, +kind, dir} = p
  Coaster.at.go(U32.is_eq(kind, 5), q, x, y, o)

# the first tile holding object o beside any of the coaster's station pieces
def Coaster.near(+ps: +List<Piece>, +q: Q, +o: U32) -> U32:
  match ps:
    case []:
      NONE()
    case p <> rest:
      +here = Coaster.at(p, q, o)
      sel(U32.is_eq(here, NONE()), Coaster.near(rest, q, o), here)

# a ride's door: its entrance (o = 7, a queue tile) or its exit (o = 1, a
# path tile). Shops have neither; the coaster's are beside its station.
def Ride.door(+k: U32, +q: Q, +ps: +List<Piece>, +x: U32, +y: U32, +w: U32, +o: U32) -> U32:
  match k:
    case 0:
      NONE()
    case 3:
      NONE()
    case 4:
      NONE()
    case 5:
      Coaster.near(ps, q, o)
    case _:
      Ride.find(q, x, y, w, o)

# where queued guests stand, for the spacing rule: packed (x << 16) | y
# a queued guest: facing << 30 | x << 15 | y
def Queue.put(on: Bool, +x: U32, +y: U32, +d: U32, +acc: +List<U32>) -> +List<U32>:
  match on:
    case True{}:
      (((d .&. 3) << 30n) .|. (x << 15n) .|. y : U32) <> acc
    case False{}:
      acc

def Queue.add(g: Guest, +q: Q, +acc: +List<U32>) -> +List<U32>:
  Guest{id, +x, +y, +dir, +st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  Queue.put(U32.is_eq(st, 0) && U32.is_eq(Land.obj(q, (x >> 4n : U32), (y >> 4n : U32)), 7), x, y, dir, acc)

def Queue.list(+gs: +List<Guest>, +q: Q, +acc: +List<U32>) -> +List<U32>:
  match gs:
    case []:
      acc
    case g <> rest:
      Queue.list(rest, q, Queue.add(g, q, acc))

# someone in the queue within six units ahead (in direction d) of (x, y),
# not coming the other way (guests squeeze past those)
def QP.ahead(+p: U32, +x: U32, +y: U32, +d: U32) -> Bool:
  +px = ((p >> 15n) .&. 32767 : U32)
  +py = (p .&. 32767 : U32)
  +facing = Bool.not(U32.is_eq((p >> 30n : U32), ((d + 2) .&. 3 : U32)))
  +fx = sel(U32.is_eq(d, 0), (px - x : U32), sel(U32.is_eq(d, 2), (x - px : U32),
    sel(U32.is_eq(d, 1), (py - y : U32), (y - py : U32))))
  +sx = sel(U32.is_eq((d .&. 1 : U32), 0), (py - y : U32), (px - x : U32))
  ((fx - 1) < 6 : U32) && ((sx + 4) <= 8 : U32) && facing

# (hit carries the previous test, so the scan stops at the first match)
def Queue.blocked(+qs: +List<U32>, hit: Bool, +x: U32, +y: U32, +d: U32) -> Bool:
  match qs:
    case []:
      hit
    case p <> rest:
      match hit:
        case True{}:
          True{}
        case False{}:
          Queue.blocked(rest, QP.ahead(p, x, y, d), x, y, d)

def Queue.wait(check: Bool, +qs: +List<U32>, +x: U32, +y: U32, +d: U32) -> Bool:
  match check:
    case True{}:
      Queue.blocked(qs, False{}, x, y, d)
    case False{}:
      False{}

# whether a ride takes riders now: a cycling ride while loading; the coaster
# while a train stands in the station after its riders got off; shops always
# Wear: a ride's reliability (bits 0-7; 255 when new), whether it is broken
# down (bit 8), and how long it has stood broken (bits 16-31). A running
# ride wears a little now and then and may break down, the likelier the
# more worn; a breakdown lasts until repaired (REPAIR ticks of work), which
# restores some reliability, never past what the ride's age allows.
def Wear.rel(+w: U32) -> U32:
  (w .&. 255 : U32)

def Wear.broken(+w: U32) -> Bool:
  Bool.not(U32.is_eq((w .&. 256 : U32), 0))

def Wear.fix(+w: U32) -> U32:
  (w >> 16n : U32)

def REPAIR() -> U32:
  1800

def Wear.tick(+w: U32, +k: U32, +open: U32, +idx: U32, +t: U32, +born: U32, +boost: Bool) -> U32:
  +rel = Wear.rel(w)
  +brk = Wear.broken(w)
  +runs = U32.is_eq(open, 1) && (Ride.cycles(k) || U32.is_eq(k, 5))
  +due = runs && Bool.not(brk) && U32.is_eq(((t + idx * 13) .&. 63 : U32), 0)
  +roll = (hash((idx + 977 : U32), t) .&. 1023 : U32)
  +snap = due && (roll < ((255 - rel) >> 3n) : U32)
  +rel2 = sel(due && (roll >= 512 : U32), U32.max(sub0(rel, 1), 40), rel)
  +fixed = brk && (Wear.fix(w) >= REPAIR() : U32)
  +cap = U32.max(sub0(255, ((t - born) / 1200 : U32)), 120)
  +rel3 = sel(fixed, U32.min((rel + 60 : U32), cap), rel2)
  +brk2 = Bool.not(fixed) && (brk || snap)
  (rel3 .|. sel(brk2, 256, 0) .|. (sel(brk2 && brk, (Wear.fix(w) + sel(boost, 30, 1) : U32), 0) << 16n) : U32)

def Ride.wear(r: Ride) -> U32:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  wear

def Ride.loading.go(+k: U32, +ph: U32, +sid: U32, +sw: U32) -> Bool:
  match k:
    case 1:
      U32.is_eq(ph, 0)
    case 2:
      U32.is_eq(ph, 0)
    case 5:
      Bool.not(U32.is_eq(sid, 4095)) && (sw > 20 : U32) && (sw <= 100 : U32)
    case _:
      True{}

def Ride.loading(r: Ride, stn: Stn) -> Bool:
  Ride{+kind, x, y, w, +h, price, open, +ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, +wear} = r
  +info = Stn.at(stn, h)
  Bool.not(Wear.broken(wear)) && Ride.loading.go(kind, ph, (info >> 20n : U32), ((info >> 1n) .&. 4095 : U32))

# whether a rider gets off now: a cycling ride while unloading; a coaster
# rider when their own train is back in the station (and has stood long
# enough to unload), or the coaster closes; a shop's buyer when served; and
# anyone whose ride was demolished
def Ride.unloading.go(+k: U32, +ph: U32, +so: U32, +sid: U32, +sw: U32, +dir: U32,
  +tmr: U32) -> Bool:
  match k:
    case 0:
      True{}
    case 1:
      U32.is_eq(ph, 2)
    case 2:
      U32.is_eq(ph, 2)
    case 5:
      U32.is_eq(so, 0) || U32.is_eq((dir >> 6n : U32), sid) && (sw > 110 : U32) && (tmr < 2800 : U32)
    case _:
      (tmr <= 1 : U32)

def Ride.unloading(r: Ride, stn: Stn, +dir: U32, +tmr: U32) -> Bool:
  Ride{+kind, x, y, w, +h, price, open, +ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, +wear} = r
  +info = Stn.at(stn, h)
  Bool.not(Wear.broken(wear)) && Ride.unloading.go(kind, ph, (info .&. 1 : U32), (info >> 20n : U32), ((info >> 1n) .&. 4095 : U32), dir, tmr)

# standing where the ride is boarded: at its entrance (a shop: beside it)
def Ride.at_door(r: Ride, +i: U32, +j: U32) -> Bool:
  Ride{+kind, +x, +y, +w, +h, price, open, ph, tm, +ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  +ci = U32.min(U32.max(i, x), (x + w - 1 : U32))
  +cj = U32.min(U32.max(j, y), (y + h - 1 : U32))
  Ride.shop(kind) && U32.is_eq((absd(i, ci) + absd(j, cj) : U32), 1)
    || Bool.not(Ride.shop(kind)) && U32.is_eq(pk(i, j), ent)

def Guest.affords(+rd: Ride, +cash: U32) -> Bool:
  U32.is_le(Ride.price(rd), cash)

def Guest.at_ride(+rd: Ride, +st: U32, +tgt: U32, +x: U32, +y: U32) -> Bool:
  U32.is_eq(st, 0) && Bool.not(U32.is_eq(tgt, NONE())) && Guest.at_center(x, y)
    && Ride.is_open(rd) && Ride.at_door(rd, (x >> 4n : U32), (y >> 4n : U32))

def Guest.ready(+rd: Ride, +st: U32, +tgt: U32, +x: U32, +y: U32, +cash: U32) -> Bool:
  Guest.affords(rd, cash) && Guest.at_ride(rd, st, tgt, x, y)

# whether a walking guest boards (or buys at) their target ride now: it is
# loading, and they stand at its door, open, with the fare
def Guest.wants(g: Guest, +q: Q, +rs: +List<Ride>, +stn: Stn) -> Bool:
  Guest{id, +x, +y, dir, +st, +tgt, tmr, +cash, hu, th, en, na, ha, lk, mind, bl} = g
  +rd = Rides.get(rs, tgt)
  Ride.loading(rd, stn) && Guest.ready(rd, st, tgt, x, y, cash)

def Boards.put(+s: U32, +id: U32, +r: U32, +acc: +List<Board>) -> +List<Board>:
  Bool.pick(+List<Board>, U32.is_eq(s, NONE()), acc, Board{id, r, s} <> acc)

def Boards.try(want: Bool, +g: Guest, +occ: +List<U32>, +rs: +List<Ride>,
  +stn: Stn, +acc: +List<Board>) -> +List<Board>:
  match want:
    case True{}:
      +r = Guest.tgt(g)
      Boards.put(Seat.free(occ, acc, r, Ride.cap(Rides.get(rs, r), stn)), Guest.id(g), r, acc)
    case False{}:
      acc

def Boards.plan(+gs: +List<Guest>, +occ: +List<U32>, +q: Q, +rs: +List<Ride>,
  +stn: Stn, +acc: +List<Board>) -> +List<Board>:
  match gs:
    case []:
      acc
    case g <> rest:
      Boards.plan(rest, occ, q, rs, stn, Boards.try(Guest.wants(g, q, rs, stn), g, occ,
        rs, stn, acc))


def Guest.fee(g: Guest, +rs: +List<Ride>) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  Ride.price(Rides.get(rs, tgt))

# boarding: take the seat, pay, then the ride's effects
# gold after paying p (the guests who board can always afford it)
def Guest.pay(+cash: U32, +p: U32) -> U32:
  sel(U32.is_le(p, cash), (cash - p : U32), 0)

# how much intensity a guest enjoys (hundredths): set by their look, so the
# same adventurer always likes the same rides
def Ride.joy(+rate: U32, +lk: U32) -> U32:
  +over = sub0(Rate.i(rate), Guest.tol(lk))
  sub0((Rate.e(rate) / 10 : U32), (over / 6 : U32))

def Guest.board(g: Guest, +rs: +List<Ride>, +seat: U32, +stn: Stn) -> Guest:
  Guest{id, x, y, dir, st, +tgt, tmr, +cash, +hu, +th, en, +na, +ha, +lk, mind, +bl} = g
  +rd = Rides.get(rs, tgt)
  +k = Ride.kind(rd)
  +rate = Ride.rate(rd)
  +coaster = U32.is_eq(k, 5)
  +item = sel(U32.is_eq(k, 3), 65536, sel(U32.is_eq(k, 4), 131072, sel(U32.is_eq(k, 8), 196608,
    sel(U32.is_eq(k, 9), 262144, 0))))
  Guest{id, x, y, sel(coaster, ((Stn.at(stn, Ride.ht(rd)) >> 20n) * 64 + seat : U32), seat), 1, tgt,
    sel(coaster, 3000, Ride.duration(k)), Guest.pay(cash, Ride.price(rd)),
    sel(U32.is_eq(k, 4), sub0(hu, 160), sel(U32.is_eq(k, 9), sub0(hu, 60), hu)),
    sel(U32.is_eq(k, 3), sub0(th, 160), sel(U32.is_eq(k, 9), sub0(th, 80), th)), en,
    sel(U32.is_eq(k, 7), sub0(na, 150), na), (ha + Ride.joy(rate, lk) + sel(U32.is_eq(k, 8), 20, 0) : U32),
    ((lk .&. 4294508543) .|. item : U32), mind,
    sel(U32.is_eq(k, 6), 0, (bl + sel(U32.is_eq(k, 3), 40, sel(U32.is_eq(k, 4), 15, 0)) : U32))}

# a ride is over for this rider (see Ride.unloading)
def Guest.done(+tmr: U32, +dir: U32, +tgt: U32, +rs: +List<Ride>, +stn: Stn) -> Bool:
  Ride.unloading(Rides.get(rs, tgt), stn, dir, tmr)

# where a rider steps off: onto the exit tile at its edge by the ride, facing
# away (packed x << 16 | y << 4 | dir, in 1/16 tile)
def Guest.alight(+e: U32, +rx: U32, +ry: U32, +w: U32) -> U32:
  +ei = (e >> 6n : U32)
  +ej = (e .&. 63 : U32)
  +west = (ei < rx : U32)
  +east = (ei >= rx + w : U32)
  +north = (ej < ry : U32)
  +px = sel(west, (ei * 16 + 12 : U32), sel(east, (ei * 16 + 4 : U32), (ei * 16 + 8 : U32)))
  +py = sel(west || east, (ej * 16 + 8 : U32), sel(north, (ej * 16 + 12 : U32), (ej * 16 + 4 : U32)))
  +d = sel(west, 2, sel(east, 0, sel(north, 3, 1)))
  ((px << 16n) .|. (py << 4n) .|. d : U32)

# what a rider thinks of a ride as they get off: too intense, or great
def Guest.verdict(+rd: Ride, +tgt: U32, +lk: U32, +mind: U32, +t: U32) -> U32:
  +rate = Ride.rate(rd)
  +k = Ride.kind(rd)
  sel(Ride.shop(k) || U32.is_eq(k, 0), mind,
    sel((Rate.i(rate) > Guest.tol(lk) : U32), Mind.make(4, tgt, t),
      sel((Ride.joy(rate, lk) >= 14 : U32), Mind.make(3, tgt, t), mind)))

# getting off: at the ride's exit (a shop's buyers stay where they stand)
def Guest.off(done: Bool, +id: U32, +x: U32, +y: U32, +dir: U32, +tgt: U32, +tmr: U32,
  +cash: U32, +hu: U32, +th: U32, +en: U32, +na: U32, +ha: U32, +lk: U32, +mind: U32, +bl: U32, +q: Q,
  +rs: +List<Ride>, +t: U32) -> Guest:
  match done:
    case True{}:
      +rd = Rides.get(rs, tgt)
      +e = Ride.ex(rd)
      +out = Bool.not(U32.is_eq(e, NONE()))
      +a = Guest.alight(e, Ride.cx(rd), Ride.cy(rd), Ride.wd(rd))
      Guest{id, sel(out, (a >> 16n : U32), x), sel(out, ((a >> 4n) .&. 4095 : U32), y),
        sel(out, (a .&. 3 : U32), 0), 0, NONE(), 0, cash, hu, th, en, (na + (Rate.n(Ride.rate(rd)) * 3) / 4 : U32), ha, lk,
        Guest.verdict(rd, tgt, lk, mind, t), bl}
    case False{}:
      +stuck = Wear.broken(Ride.wear(Rides.get(rs, tgt)))
      Guest{id, x, y, dir, 1, tgt, sub0(tmr, 1), cash, hu, th, en, na,
        sel(stuck && U32.is_eq(((t + id) .&. 31 : U32), 0), sub0(ha, 1), ha), lk,
        sel(stuck && U32.is_eq(((t + id) .&. 511 : U32), 0), Mind.make(6, tgt, t), mind), bl}

def Guest.riding(g: Guest, +q: Q, +rs: +List<Ride>, +t: U32, +stn: Stn) -> Guest:
  Guest{+id, +x, +y, +dir, st, +tgt, +tmr, +cash, +hu, +th, +en, +na, +ha, +lk, +mind, bl} = g
  Guest.off(Guest.done(tmr, dir, tgt, rs, stn), id, x, y, dir, tgt, tmr, cash, hu, th,
    en, na, ha, lk, mind, bl, q, rs, t)

# needs drift a little every 16 ticks
def Guest.needs(g: Guest, +t: U32) -> Guest:
  Guest{+id, x, y, dir, st, tgt, tmr, cash, +hu, +th, +en, +na, +ha, lk, mind, +bl} = g
  +due = U32.is_eq(((t + id) .&. 15 : U32), 0)
  +bad = ((hu > 200) || (th > 200) || (na > 170) || (en < 40) || (bl > 220) : U32)
  +good = ((hu < 120) && (th < 120) && (na < 90) && (bl < 160) : U32)
  +ha2 = sel(bad, sub0(ha, 2), sel(good, (ha + 1 : U32), ha))
  Guest{id, x, y, dir, st, tgt, tmr, cash,
    sel(due, (hu + 1 : U32), hu), sel(due, (th + 2 : U32), th),
    sel(due, sub0(en, 1), en), sel(due, sub0(na, 1), na),
    sel(due, ha2, ha), lk, mind, sel(due, (bl + 1 : U32), bl)}

# walking: at a tile centre pick a target and a direction; move every
# other tick
def Guest.sick(+st: U32, +na: U32, +id: U32, +t: U32) -> Bool:
  (U32.is_eq(st, 0) || U32.is_eq(st, 2)) && (na > 95 : U32) && U32.is_eq((hash(id, t) .&. 511 : U32), 0)

# a guest finishing what they carry this tick (the same test Guest.walk uses)
def Stamp.now(+t: U32) -> U32:
  (((t >> 6n) .&. 127) .|. 128 : U32)

def Stamp.recent(+s: U32, +t: U32) -> Bool:
  U32.is_eq(s, Stamp.now(t)) || U32.is_eq(s, Stamp.now((t - 64 : U32)))

# scenery on a neighbouring tile (statues, fountains, flowers, walls)
def Scen.at(+q: Q, +i: U32, +j: U32) -> Bool:
  +t = Land.get(q, i, j)
  U32.is_eq(Tile.obj(t), 2) && (Tile.a(t) >= 4 : U32)

def Scen.near_if(now: Bool, +q: Q, +i: U32, +j: U32) -> Bool:
  match now:
    case True{}:
      Scen.at(q, (i + 1 : U32), j) || Scen.at(q, (i - 1 : U32), j) || Scen.at(q, i, (j + 1 : U32)) || Scen.at(q, i, (j - 1 : U32))
    case False{}:
      False{}

# up on a deck after this step: only a step into another tile can change it
def Guest.layer(cross: Bool, +ondeck: Bool, +q: Q, +x: U32, +y: U32, +h: U32, +qok: Bool, +fq: Bool, +fe: Bool) -> Bool:
  match cross:
    case True{}:
      Bool.not(U32.is_eq((Land.step(q, x, y, h, qok, fq, fe) .&. 8 : U32), 0))
    case False{}:
      ondeck

def Guest.walk(g: Guest, +q: Q, +rs: +List<Ride>, +t: U32, +qs: +List<U32>) -> Guest:
  Guest{+id, +x, +y, +dir, +st, +tgt, +tmr, +cash, +hu, +th, +en, +na, +ha,
    +lk, +mind, +bl} = g
  +i = (x >> 4n : U32)
  +j = (y >> 4n : U32)
  +here = Land.get(q, i, j)
  +ondeck = Bool.not(U32.is_eq((dir .&. 65536 : U32), 0)) && Bool.not(U32.is_eq(Deck.of(here), 0))
  +h = sel(ondeck, Deck.of(here), Tile.h(here))
  +r = hash3(id, t, x)
  +ctr = Guest.at_center(x, y)
  +onq = U32.is_eq(Tile.obj(here), 7)
  +home = U32.is_eq(st, 2)
  # mess underfoot (litter | sick << 8), and being sick oneself
  +dirt = sel(Bool.not(ondeck) && (U32.is_eq(Tile.obj(here), 1) || U32.is_eq(Tile.obj(here), 7)),
    ((Tile.b(here) .&. 255) + 3 * ((Tile.b(here) >> 8n) .&. 255) : U32), 0)
  +sick = Guest.sick(st, na, id, t)
  +grim = (dirt >= 2 : U32) && U32.is_eq(((t + id) .&. 63 : U32), 0)
  +filthy = (dirt >= 4 : U32) && U32.is_eq(((hash(id, t) >> 4n) .&. 255 : U32), 0)
  # a bench: a tired guest sits down; up again when rested
  +sit = ctr && Bool.not(ondeck) && U32.is_eq(st, 0) && U32.is_eq((Tile.a(here) .&. 271 : U32), 2) && U32.is_eq(Tile.obj(here), 1)
    && (en < 80 : U32)
  +sitting = U32.is_eq(st, 4)
  +rested = sitting && ((en >= 190 : U32) || U32.is_eq(tmr, 0))
  # decide to go home
  +tired = ((ha < 50) || (en < 30) || (cash < 2) : U32)
  +st2 = sel(sit, 4, sel(rested, 0, sel(ctr && U32.is_eq(st, 0) && tired, 2, st)))
  +athome = ctr && home && U32.is_eq(i, GATE_X()) && U32.is_eq(j, GATE_Y())
  +st3 = sel(athome, 3, st2)
  # targets: food, drink, or any attraction; patience runs out
  +whim = U32.is_eq(((lk >> 16n) .&. 7 : U32), 0) && (ha > 140 : U32) && U32.is_eq(((r >> 20n) .&. 15 : U32), 0)
  +want = sel((bl > 170 : U32), 6, sel((na > 80 : U32), 7, sel((hu > 150 : U32), 4, sel((th > 150 : U32), 3,
    sel(whim, sel(U32.is_eq(((r >> 24n) .&. 1 : U32), 0), 8, 9), 0)))))
  +needt = ctr && U32.is_eq(st2, 0) && U32.is_eq(tgt, NONE())
    && U32.is_eq((r .&. 3 : U32), 0)
  +avoid = sel(U32.is_eq(Mind.code(mind), 1), Mind.ride(mind), NONE())
  +picks = Guest.pick_if(needt, rs, want, i, j, cash, r, lk, hu, th, avoid)
  +pick = (picks .&. 255 : U32)
  +wish = (picks >> 8n : U32)
  # priced out: they wanted a ride but won't pay what it costs
  +dear = needt && U32.is_eq(pick, NONE()) && Bool.not(U32.is_eq(wish, NONE()))
  +giveup = U32.is_eq(tmr, 0) || Bool.not(U32.is_eq(st2, 0))
  # waited too long in a queue
  +fed_up = onq && U32.is_eq(tmr, 0) && Bool.not(U32.is_eq(tgt, NONE()))
  +mind2 = sel(dear, Mind.make(1, wish, t), sel(fed_up, Mind.make(2, tgt, t), sel(filthy, Mind.make(9, 255, t), mind)))
  +tgt2 = sel(needt, pick, sel(giveup, NONE(), tgt))
  +slow = onq && Bool.not(U32.is_eq(((t + id) .&. 3 : U32), 0))
  +tmr2 = sel(sit, 400, sel(needt, 1500, sel(slow, tmr, sub0(tmr, 1))))
  # steering
  +trd = Rides.get(rs, tgt2)
  # a ride with a queue is reached at its entrance, where its riders wait
  +ent = Ride.ent(trd)
  +queued = Bool.not(home) && Bool.not(U32.is_eq(tgt2, NONE())) && Bool.not(U32.is_eq(ent, NONE()))
  +tx = sel(home, GATE_X(), sel(U32.is_eq(tgt2, NONE()), i, sel(queued, (ent >> 6n : U32), Ride.cx(trd))))
  +ty = sel(home, GATE_Y(), sel(U32.is_eq(tgt2, NONE()), j, sel(queued, (ent .&. 63 : U32), Ride.cy(trd))))
  +lim = sel(queued, 0, 1)
  +there = queued && ctr && U32.is_eq(pk(i, j), ent)
  # only a guest bound for a ride with a queue may step into one
  +qok = onq || queued && U32.is_eq(st3, 0)
  +tick = U32.is_eq(((t + id) .&. 1 : U32), 0)
  # in a queue, a guest may step off only at its free end
  +fe = Bool.not(onq) || U32.is_eq(Tile.a(here), 1)
  +dir2 = Guest.steer(ctr && tick && Bool.not(there), q, i, j, h, (dir .&. 65535 : U32), tx, ty, r, qok, onq, fe, lim)
  +ahead = U32.is_eq(Land.obj(q, ((x + dx_of(dir2) * 8) >> 4n : U32), ((y + dy_of(dir2) * 8) >> 4n : U32)), 7)
  +go = tick
    && (Bool.not(ctr) || Guest.can_step(q, i, j, h, dir2, qok, onq, fe))
    && Bool.not(there)
    && Bool.not(U32.is_eq(st3, 3)) && Bool.not(U32.is_eq(st3, 4))
    && Bool.not(Queue.wait(tick && (onq || ahead) && Bool.not(U32.is_eq(tgt2, NONE())), qs, x, y, dir2))
  +x2 = sel(go, (x + dx_of(dir2) : U32), x)
  +y2 = sel(go, (y + dy_of(dir2) : U32), y)
  +finish = U32.is_eq(((r >> 8n) .&. 1023 : U32), 0)
  +lk2 = (sel(finish, (lk .&. 4277731327 : U32), (lk .&. 4278190079 : U32)) .|. sel(go, 16777216, 0) : U32)
  # a Bard playing nearby cheers them up
  +cheer = Stamp.recent(((Tile.b(here) >> 24n) .&. 255 : U32), t) && U32.is_eq(((t + id) .&. 31 : U32), 0)
  +pretty = Scen.near_if(ctr && U32.is_eq(((t + id) .&. 63 : U32), 0), q, i, j)
  +ha2 = (sub0(sub0(ha, sel(dear || fed_up, 6, 0)), sel(sick, 10, sel(grim, sel((dirt >= 6 : U32), 2, 1), 0)))
    + sel(cheer, 3, 0) + sel(pretty, 2, 0) : U32)
  +en2 = sel(sitting && U32.is_eq(((t + id) .&. 1 : U32), 0), (en + 1 : U32), en)
  +cross = Bool.not(U32.is_eq((x2 >> 4n : U32), i)) || Bool.not(U32.is_eq((y2 >> 4n : U32), j))
  +up = Guest.layer(cross, ondeck, q, (x2 >> 4n : U32), (y2 >> 4n : U32), h, qok, onq, fe)
  Guest{id, x2, y2, (dir2 .|. sel(up, 65536, 0) : U32), st3, tgt2, tmr2, cash, hu, th, en2, sel(sick, 60, na), ha2, lk2, mind2, bl}

def Guest.st(g: Guest) -> U32:
  Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  st

def Guest.move.go(riding: Bool, boards: Bool, +g: Guest, +q: Q,
  +rs: +List<Ride>, +t: U32, +plan: +List<Board>, +stn: Stn, +qs: +List<U32>) -> Guest:
  match riding boards:
    case True{} _:
      Guest.riding(g, q, rs, t, stn)
    case False{} True{}:
      Guest.board(g, rs, Boards.seat(plan, Guest.id(g)), stn)
    case False{} False{}:
      Guest.walk(g, q, rs, t, qs)

def Guest.move(+g: Guest, +q: Q, +rs: +List<Ride>, +t: U32, +plan: +List<Board>,
  +stn: Stn, +qs: +List<U32>) -> Guest:
  Guest.move.go(U32.is_eq(Guest.st(g), 1), Boards.has(plan, Guest.id(g)), g, q, rs, t,
    plan, stn, qs)

# a guest's whole tick; the final clamp keeps every stat in 0..255
def Guest.step(+g: Guest, +q: Q, +rs: +List<Ride>, +t: U32, +plan: +List<Board>,
  +stn: Stn, +qs: +List<U32>) -> Guest:
  Guest.clamp(Guest.needs(Guest.move(g, q, rs, t, plan, stn, qs), t))

def Guests.step(+gs: +List<Guest>, +q: Q, +rs: +List<Ride>, +t: U32,
  +plan: +List<Board>, +stn: Stn, +qs: +List<U32>) -> +List<Guest>:
  match gs:
    case []:
      []
    case g <> rest:
      Guest.step(g, q, rs, t, plan, stn, qs) <> Guests.step(rest, q, rs, t, plan, stn, qs)

def Guests.put(keep: Bool, g: Guest, +gs: +List<Guest>) -> +List<Guest>:
  match keep:
    case True{}:
      g <> gs
    case False{}:
      gs

# the guests still in the park, and the ones who just left
def Guests.stay(+gs: +List<Guest>) -> +List<Guest>:
  match gs:
    case []:
      []
    case g <> rest:
      Guests.put(Bool.not(Guest.gone(g)), g, Guests.stay(rest))

def Guests.left(+gs: +List<Guest>) -> +List<Guest>:
  match gs:
    case []:
      []
    case g <> rest:
      Guests.put(Guest.gone(g), g, Guests.left(rest))

def Guests.arrive(go: Bool, +id: U32, +t: U32, +fee: U32) -> +List<Guest>:
  match go:
    case True{}:
      [Guest.new(id, t, fee)]
    case False{}:
      []

def Rides.attractions(+rs: +List<Ride>) -> U32:
  match rs:
    case []:
      0
    case r <> rest:
      (sel(Ride.is_open(r), 1, 0) + Rides.attractions(rest) : U32)

# a new adventurer comes through the gate now and then: more rides and a
# better park rating draw more, a steep entry fee fewer
type Fin is Data:
  Fin{fee: U32, loan: U32, rating: U32, now: List<&2, U32>, last: List<&2, U32>,
    hist: List<&2, U32>, res: U32}

def Fin.fee(f: Fin) -> U32:
  Fin{fee, loan, rating, now, last, hist, res} = f
  fee

def Fin.rating(f: Fin) -> U32:
  Fin{fee, loan, rating, now, last, hist, res} = f
  rating

def Guests.come(+gs: +List<Guest>, +rs: +List<Ride>, +t: U32, +f: Fin) -> Bool:
  +base = U32.min((2 + Rides.attractions(rs) * 3 : U32), 24)
  +fee = Fin.fee(f)
  +rate = sub0((base * (200 + Fin.rating(f)) / 800 : U32), (fee * fee / 16 : U32))
  +roll = (hash(t, 77) .&. 255 : U32)
  # fewer come on a rainy day (the rain Art.rain draws)
  +wet = ((hash((t >> 11n : U32), 99) .&. 7) < 2 : U32)
  (roll < sel(wet, (rate >> 1n : U32), rate) : U32) && (len32(Guest, gs) < 1200 : U32)

def Guests.arrivals(+gs: +List<Guest>, +rs: +List<Ride>, +t: U32, +nid: U32, +f: Fin)
  -> +List<Guest>:
  Guests.arrive(Guests.come(gs, rs, t, f), nid, t, U32.min(Fin.fee(f), 40))

# Rides each tick: doors, queue lengths, the cycle, and the tallies
# -----------------------------------------------------------------

def Tab.add(+xs: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match xs:
    case []:
      []
    case x <> rest:
      sel(U32.is_eq(i, 0), (x + v : U32), x) <> Tab.add(rest, (i - 1 : U32), v)

def Qlen.put(on: Bool, +tab: +List<U32>, +i: U32) -> +List<U32>:
  match on:
    case True{}:
      Tab.add(tab, i, 1)
    case False{}:
      tab

def Qlen.add(g: Guest, +q: Q, +tab: +List<U32>) -> +List<U32>:
  Guest{id, +x, +y, dir, +st, +tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  Qlen.put(U32.is_eq(st, 0) && Bool.not(U32.is_eq(tgt, NONE()))
    && U32.is_eq(Land.obj(q, (x >> 4n : U32), (y >> 4n : U32)), 7), tab, tgt)

# guests standing in a queue, counted by the ride they want
def Qlen.fill(+gs: +List<Guest>, +q: Q, +tab: +List<U32>) -> +List<U32>:
  match gs:
    case []:
      tab
    case g <> rest:
      Qlen.fill(rest, q, Qlen.add(g, q, tab))

# counted every 16 ticks (then the rides keep their last count)
def Qlen.fill_if(now: Bool, +gs: +List<Guest>, +q: Q, +n: U32) -> +List<U32>:
  match now:
    case True{}:
      Qlen.fill(gs, q, Tab.zero(n, []))
    case False{}:
      []

def Seat.count(+m: U32) -> U32:
  ((m .&. 1) + ((m >> 1n) .&. 1) + ((m >> 2n) .&. 1) + ((m >> 3n) .&. 1)
    + ((m >> 4n) .&. 1) + ((m >> 5n) .&. 1) + ((m >> 6n) .&. 1) + ((m >> 7n) .&. 1) : U32)

def Boards.count(+bs: +List<Board>, +r: U32, +acc: U32) -> U32:
  match bs:
    case []:
      acc
    case b <> rest:
      Boards.count(rest, r, (acc + sel(U32.is_eq(Board.ride(b), r), 1, 0) : U32))

# the cycle: loading until full, or until the first rider has waited wmax
# (never before wmin); running for the ride's duration; unloading for half
# a second; then loading again
def Ride.next_ph(+ph: U32, +tm: U32, +go: Bool, +dur: U32) -> U32:
  match ph:
    case 0:
      sel(go, 1, 0)
    case 1:
      sel((tm + 1 >= dur : U32), 2, 1)
    case _:
      sel((tm + 1 >= 30 : U32), 0, 2)

def Ride.next_tm(+ph: U32, +ph2: U32, +tm: U32, +n: U32) -> U32:
  sel(Bool.not(U32.is_eq(ph, ph2)), 0,
    sel(U32.is_eq(ph, 0), sel((n > 0 : U32), U32.min((tm + 1 : U32), 60000), 0), (tm + 1 : U32)))

# a coaster's ratings come from its dry run, once it has passed a test
type Dry is Data:
  Dry{e: U32, i: U32, prev: U32, top: U32, drops: U32, run: U32, big: U32, gv: U32,
    gl: U32, neg: U32, air: U32, turns: U32, hi: U32, lo: U32, fail: U32}

def isqrt.go(+n: Nat, +e: U32, +r: U32, +b: U32) -> U32:
  match n:
    case 0n:
      r
    case 1n+m:
      +t = (r .|. b : U32)
      isqrt.go(m, e, sel((t * t <= e : U32), t, r), (b >> 1n : U32))

def isqrt(+e: U32) -> U32:
  isqrt.go(16n, e, 0, 32768)

# the dry run so far: energy, the piece index, the last piece's kind, top
# speed, drops, the current drop and the biggest (levels), vertical and
# lateral G and the worst negative G (hundredths), air time (tenths of a
# second), turns, highest and lowest level, and the stall piece (255: none)
def Piece.left(+k: U32) -> Bool:
  U32.is_eq(k, 3) || U32.is_eq(k, 10)

def Piece.right(+k: U32) -> Bool:
  U32.is_eq(k, 4) || U32.is_eq(k, 11)

def Piece.rise(+k: U32) -> U32:
  sel(U32.is_eq(k, 1) || U32.is_eq(k, 6), 1, sel(U32.is_eq(k, 12), 2, 0))

def Piece.drop(+k: U32) -> U32:
  sel(U32.is_eq(k, 2), 1, sel(U32.is_eq(k, 13), 2, 0))

def Dry.step(d: Dry, p: Piece, +cfg: U32) -> Dry:
  Dry{+e, +i, +prev, +top, +drops, +run, +big, +gv, +gl, +neg, +air, +turns, +hi, +lo, +fail} = d
  Piece{x, y, +z, +k, dir} = p
  +rise = Piece.rise(k)
  +drop = Piece.drop(k)
  +lift = U32.is_eq(k, 6)
  +lv = Cfg.lift(cfg)
  +e1 = sel(U32.is_eq(k, 5), U32.max(e, 100), sel(lift, U32.max(e, (lv * lv : U32)), e))
  +need = (rise * 381 : U32)
  +stall = (rise > 0 : U32) && Bool.not(lift) && (e1 < need : U32)
  +e2 = (sel(lift, e1, sel(stall, 100, (e1 - need : U32))) + drop * 381 : U32)
  +turn = Piece.left(k) || Piece.right(k)
  +bank = (k >= 10 : U32) && (k <= 11 : U32)
  +loss = sel(turn && Bool.not(bank), (e2 >> 4n : U32), sel(bank, ((e2 >> 5n) + (e2 >> 7n) : U32), (e2 >> 5n : U32)))
  +e3 = sel(U32.is_eq(k, 9), U32.min(e2, 400), U32.max(sub0(e2, (loss + 20 : U32)), 1))
  +v = isqrt(e3)
  +pdown = (Piece.drop(prev) > 0 : U32)
  +pup = (Piece.rise(prev) > 0 : U32)
  # the bottom of a drop pulls down, the top of a hill lifts off
  +valley = pdown && U32.is_eq(drop, 0)
  +gv2 = sel(valley, U32.max(gv, (100 + e2 * 100 / sel(U32.is_eq(prev, 13), 762, 1524) : U32)), gv)
  +crest = pup && (drop > 0 : U32)
  +c = sel(crest, (e2 * 100 / sel(U32.is_eq(k, 13) || U32.is_eq(prev, 12), 635, 1270) : U32), 0)
  +neg2 = sel((c > 100 : U32), U32.max(neg, (c - 100 : U32)), neg)
  +air2 = (air + sel((c > 100 : U32), (144 / U32.max(v, 1) : U32), 0) : U32)
  +gl2 = sel(turn, U32.max(gl, sel(bank, (e2 * 40 / 508 : U32), (e2 * 100 / 508 : U32))), gl)
  +run2 = sel((drop > 0 : U32), sel(pdown, (run + drop : U32), drop), 0)
  +z2 = ((z + rise) - drop : U32)
  Dry{e3, (i + 1 : U32), k, U32.max(top, v), (drops + sel((drop > 0 : U32) && Bool.not(pdown), 1, 0) : U32),
    run2, U32.max(big, run2), gv2, gl2, neg2, air2, (turns + sel(turn, 1, 0) : U32),
    U32.max(hi, U32.max(z, z2)), U32.min(lo, U32.min(z, z2)), sel(U32.is_eq(fail, 255) && stall, i, fail)}

def Dry.go(+ps: +List<Piece>, d: Dry, +cfg: U32) -> Dry:
  match ps:
    case []:
      d
    case p <> rest:
      Dry.go(rest, Dry.step(d, p, cfg), cfg)

def Dry.run(+ps: +List<Piece>, +cfg: U32) -> Dry:
  Dry.go(ps, Dry{0, 0, 5, 0, 0, 0, 0, 100, 0, 0, 0, 0, 0, 255, 255}, cfg)

def Dry.rate(d: Dry, +cfg: U32) -> U32:
  Dry{e, +n, prev, +top, +drops, run, +big, +gv, +gl, +neg, +air, +turns, +hi, +lo, fail} = d
  +ty = Cfg.type(cfg)
  +base = sel(U32.is_eq(ty, 1), 150, sel(U32.is_eq(ty, 2), 250, 200))
  +height = sub0(hi, lo)
  +int = (50 + top + (gv - 100) * 2 / 3 + gl * 2 / 3 + neg + big * 20 + height * 10 + sel(U32.is_eq(ty, 2), 60, 0)
    - sel(U32.is_eq(ty, 1), 40, 0) : U32)
  +exc0 = (base + top * 3 / 2 + drops * 25 + big * 30 + air * 8 + turns * 5 + n + height * 10 : U32)
  +exc = sel((int > 1000 : U32), (exc0 >> 1n : U32), exc0)
  +nau = (30 + gl / 2 + turns * 8 + air * 4 + (gv - 100) / 4 + sel(U32.is_eq(ty, 2), 80, 0) : U32)
  sel(U32.is_eq(n, 0), 0, Rate.pack(exc, int, nau))

# where the (single) test train is: the absolute piece it's on, or 999
def Ride.rating(+k: U32, +t: Track) -> U32:
  match k:
    case 5:
      sel(Test.passed(Track.stats(t)), Dry.rate(Dry.run(Track.pieces(t), Track.cfg(t)), Track.cfg(t)), 0)
    case _:
      Ride.rate0(k)

# Testing
# -------
# A coaster must pass a test run before it opens. A dry run over its pieces
# follows the train's energy: the station and the lift hill push it, climbs
# cost it, drops pay it back, and every piece takes a little in friction
# (turns more, banked ones less); brakes slow it to 20 km/h. It measures the
# ride (speed, drops, height, G-forces, air time) and finds the first piece
# a train can't climb. Energy is speed squared, speed in km/h; a level of
# height is worth 381 (1.5 m).

# stats: bits 0-1 the test (0 not tested, 1 testing, 2 passed, 3 failed);
# 2-9 the piece a train stalls on (255: none); 10-17 where the test train was
# last seen; bit 18 once it has left the station
def Test.failed(+st: U32) -> Bool:
  U32.is_eq((st .&. 3 : U32), 3)

# a track may carry trains: on its test run, or once it has passed
def Dry.top(d: Dry) -> U32:
  Dry{e, i, prev, top, drops, run, big, gv, gl, neg, air, turns, hi, lo, fail} = d
  top

def Dry.fail(d: Dry) -> U32:
  Dry{e, i, prev, top, drops, run, big, gv, gl, neg, air, turns, hi, lo, fail} = d
  fail

# excitement, intensity and nausea (hundredths): speed, drops, air and turns
# thrill; G-forces make it intense; turning and floating make it queasy; a
# ride too intense to enjoy loses half its excitement. Minecarts are tamer,
# flyers wilder.
# (trains: how many more trains to place)
def Blocks.make(+n: Nat, +start: U32, +total: U32, +k: U32, +trains: U32, +bl: U32) -> +List<Slot>:
  match n:
    case 0n:
      []
    case 1n+p:
      +left = (total - start : U32)
      +len = sel((left < bl * 2 : U32), left, bl)
      +st = sel(U32.is_eq(start, 0), 1, 0)
      +more = (start + len < total : U32)
      +train = U32.is_eq((k % 3 : U32), 0) && (trains > 0 : U32)
      +rest = Bool.pick(+List<Slot>, more,
        Blocks.make(p, (start + len : U32), total, (k + 1 : U32), sel(train, (trains - 1 : U32), trains), bl), [])
      Bool.pick(Slot, train, Held{start, len, st, Train{k, 0, 0, 60}},
        Free{start, len, st}) <> rest

def Track.test(t: Track) -> Track:
  Track{+ps, open, bs, +s, +e, +cfg, stats} = t
  +n = len32(Piece, ps)
  +shut = {Track{ps, False{}, [], s, e, cfg, 0} : Track}
  +st = (1 .|. (Dry.fail(Dry.run(ps, cfg)) << 2n) : U32)
  +on = (True{} && Track.closed(shut)) && Test.live(st)
  +bl = Track.blen(U32.max(U32.min(U32.min(Cfg.cars(cfg), Pieces.stations(ps)), 20), 1))
  Track{ps, on, Bool.pick(+List<Slot>, on, Blocks.make(U32.to_nat(n), 0, n, 0, 1, bl), []), s, e, cfg, st}

# a pre-built coaster comes tested (if its dry run passes)
def Track.pretest(t: Track) -> Track:
  Track{+ps, open, bs, +s, +e, +cfg, stats} = t
  +f = Dry.fail(Dry.run(ps, cfg))
  Track{ps, False{}, [], s, e, cfg, sel(U32.is_eq(f, 255), 2, (3 .|. (f << 2n) : U32))}

# Mess: litter and worse
# ----------------------
# A walking guest who finishes what they carry drops the wrapper -- into a
# bin with room if one stands on or beside their tile, else on the path;
# a very queasy guest is sick. The park keeps the mess as a list (packed
# kind << 30 | x << 15 | y, kind 0 litter, 1 sick), and each path tile's `b`
# counts what lies on it (litter | sick << 8), for drawing and for guests to
# mind. Mess goes only when a Brownie sweeps it up.

def Mess.at(+kind: U32, +x: U32, +y: U32) -> U32:
  ((kind << 30n) .|. ((x .&. 32767) << 15n) .|. (y .&. 32767) : U32)

def Mess.kind(+m: U32) -> U32:
  (m >> 30n : U32)

def Mess.x(+m: U32) -> U32:
  ((m >> 15n) .&. 32767 : U32)

def Mess.y(+m: U32) -> U32:
  (m .&. 32767 : U32)

# a guest being sick this tick (the same test Guest.walk uses)
def Guest.finish(+id: U32, +t: U32, +x: U32, +lk: U32) -> Bool:
  Bool.not(U32.is_eq(((lk >> 16n) .&. 7 : U32), 0)) && U32.is_eq(((hash3(id, t, x) >> 8n) .&. 1023 : U32), 0)

# a bin with room on or beside tile (i, j): its tile, or NONE
def Bin.room(+q: Q, +i: U32, +j: U32) -> U32:
  +t = Land.get(q, i, j)
  sel(U32.is_eq(Tile.obj(t), 1) && U32.is_eq((Tile.a(t) .&. 15 : U32), 1) && ((Tile.a(t) >> 4n) < 15 : U32),
    pk(i, j), NONE())

def Bin.near.go(on: Bool, +q: Q, +i: U32, +j: U32) -> U32:
  match on:
    case True{}:
      +a = Bin.room(q, i, j)
      +b = Bin.room(q, (i + 1 : U32), j)
      +c = Bin.room(q, (i - 1 : U32), j)
      +d = Bin.room(q, i, (j + 1 : U32))
      +e = Bin.room(q, i, (j - 1 : U32))
      sel(Bool.not(U32.is_eq(a, NONE())), a, sel(Bool.not(U32.is_eq(b, NONE())), b,
        sel(Bool.not(U32.is_eq(c, NONE())), c, sel(Bool.not(U32.is_eq(d, NONE())), d, e))))
    case False{}:
      NONE()

# a guest's mess event this tick: a drop (kind 0 or 1), something into a
# bin (kind 2, the bin's tile), or NONE
# a miserable guest at a tile centre may smash the furniture there, unless
# a Watch Knight has passed lately
def Vandal.smash(+q: Q, +x: U32, +y: U32, +ha: U32, +id: U32, +t: U32) -> Bool:
  +here = Land.get(q, (x >> 4n : U32), (y >> 4n : U32))
  +a = Tile.a(here)
  Guest.at_center(x, y) && (ha < 40 : U32) && U32.is_eq(Tile.obj(here), 1)
    && Bool.not(U32.is_eq((a .&. 15 : U32), 0)) && U32.is_eq((a .&. 256 : U32), 0)
    && Bool.not(Stamp.recent(((Tile.b(here) >> 16n) .&. 255 : U32), t))
    && U32.is_eq((hash3(id, t, y) .&. 255 : U32), 0)

def Mess.event(g: Guest, +plan: +List<Board>, +q: Q, +t: U32) -> U32:
  Guest{+id, +x, +y, dir, +st, tgt, tmr, cash, hu, th, en, +na, +ha, +lk, mind, bl} = g
  +walking = Bool.not(U32.is_eq(st, 1)) && Bool.not(Boards.has(plan, id))
  +finish = walking && Guest.finish(id, t, x, lk)
  +bin = Bin.near.go(finish, q, (x >> 4n : U32), (y >> 4n : U32))
  +jx = ((hash(id, t) .&. 7) - 3 : U32)
  +jy = (((hash(id, t) >> 3n) .&. 7) - 3 : U32)
  sel(walking && Guest.sick(st, na, id, t), Mess.at(1, (x + jx : U32), (y + jy : U32)),
    sel(finish, sel(U32.is_eq(((lk >> 16n) .&. 7 : U32), 3), NONE(),
      sel(U32.is_eq(bin, NONE()), Mess.at(0, (x + jx : U32), (y + jy : U32)), (2147483648 .|. bin : U32))),
      sel(walking && Vandal.smash(q, x, y, ha, id, t), (3221225472 .|. pk((x >> 4n : U32), (y >> 4n : U32)) : U32),
      NONE())))

def Mess.put(on: Bool, +m: U32, +ms: +List<U32>) -> +List<U32>:
  match on:
    case True{}:
      m <> ms
    case False{}:
      ms

def Mess.events(+gs: +List<Guest>, +plan: +List<Board>, +q: Q, +t: U32) -> +List<U32>:
  match gs:
    case []:
      []
    case g <> rest:
      +e = Mess.event(g, plan, q, t)
      Mess.put(Bool.not(U32.is_eq(e, NONE())), e, Mess.events(rest, plan, q, t))

# the tick's drops (none once the park holds 600 pieces of mess), and the
# bins that took something
def Mess.only(+es: +List<U32>, +drops: Bool) -> +List<U32>:
  match es:
    case []:
      []
    case e <> rest:
      +isdrop = (Mess.kind(e) < 2 : U32)
      Mess.put(drops && isdrop || Bool.not(drops) && Bool.not(isdrop), e, Mess.only(rest, drops))

# swept: a Brownie within half a tile of it
def Mess.drops(+es: +List<U32>, room: Bool) -> +List<U32>:
  match room:
    case True{}:
      Mess.only(es, True{})
    case False{}:
      []

type Staff is Data:
  Staff{id: U32, x: U32, y: U32, dir: U32, kind: U32, st: U32, tgt: U32, tmr: U32,
    zone: U32, look: U32}

# mess: litter and worse on the paths, each packed kind << 30 | x << 15 | y
# (x, y in 1/16 tile; kind 0 litter, 1 sick); staff: the park's staff
def Mess.sweeps(+m: U32, +ss: +List<Staff>) -> Bool:
  match ss:
    case []:
      False{}
    case s <> rest:
      Staff{id, +x, +y, dir, +kind, st, tgt, tmr, zone, look} = s
      +near = U32.is_eq(kind, 1) && ((absd(x, Mess.x(m)) + absd(y, Mess.y(m))) <= 12 : U32)
      near || Mess.sweeps(m, rest)

# the mess still lying about, and what was swept up (together, all of it)
def Mess.kept(+ms: +List<U32>, +ss: +List<Staff>) -> +List<U32>:
  match ms:
    case []:
      []
    case m <> rest:
      Mess.put(Bool.not(Mess.sweeps(m, ss)), m, Mess.kept(rest, ss))

def Mess.swept(+ms: +List<U32>, +ss: +List<Staff>) -> +List<U32>:
  match ms:
    case []:
      []
    case m <> rest:
      Mess.put(Mess.sweeps(m, ss), m, Mess.swept(rest, ss))

# the tiles' counts follow the list (+1 for a drop, -1 for a sweep)
def Mess.count.go(on: Bool, +q: Q, +i: U32, +j: U32, t: Tile) -> Q:
  match on:
    case True{}:
      Land.set(q, i, j, t)
    case False{}:
      q

def Mess.count(+q: Q, +m: U32, +up: Bool) -> Q:
  +i = (Mess.x(m) >> 4n : U32)
  +j = (Mess.y(m) >> 4n : U32)
  +t = Land.get(q, i, j)
  +o = Tile.obj(t)
  +b = Tile.b(t)
  +sh = sel(U32.is_eq(Mess.kind(m), 0), 0, 8)
  +c = sel(U32.is_eq(sh, 0), (b .&. 255 : U32), ((b >> 8n) .&. 255 : U32))
  +c2 = sel(up, U32.min((c + 1 : U32), 255), sub0(c, 1))
  +b2 = sel(U32.is_eq(sh, 0), ((b .&. 4294967040) .|. c2 : U32), ((b .&. 4294902015) .|. (c2 << 8n) : U32))
  +path = U32.is_eq(o, 1) || U32.is_eq(o, 5) || U32.is_eq(o, 7)
  Mess.count.go(path, q, i, j, Tile{Tile.h(t), Tile.ter(t), o, Tile.a(t), b2})

def Mess.mark(+ms: +List<U32>, +up: Bool, +q: Q) -> Q:
  match ms:
    case []:
      q
    case m <> rest:
      Mess.mark(rest, up, Mess.count(q, m, up))

# a bin that took something fills a little (fill: a's bits 4..7, 15 is full)
def Bin.take(+q: Q, +e: U32) -> Q:
  +i = ((e .&. 4095) >> 6n : U32)
  +j = (e .&. 63 : U32)
  +t = Land.get(q, i, j)
  +a = Tile.a(t)
  +smash = U32.is_eq((e >> 30n : U32), 3)
  Land.set(q, i, j, Tile{Tile.h(t), Tile.ter(t), Tile.obj(t),
    sel(smash, (a .|. 256 : U32), sel((((a >> 4n) .&. 15) < 15 : U32), (a + 16 : U32), a)), Tile.b(t)})

def Bin.fill(+es: +List<U32>, +q: Q) -> Q:
  match es:
    case []:
      q
    case e <> rest:
      Bin.fill(rest, Bin.take(q, e))

# Money: every change to the park's gold is a ledger entry
# ---------------------------------------------------------
# kind: 1 ride tickets, 2 upkeep, 3 construction, 4 refunds, 5 food, 6 drinks,
# 7 entry fees, 8 loans taken, 9 loans repaid, 10 loan interest, 11 staff wages,
# 12 research

def Fix.has(+xs: +List<U32>, +i: U32) -> Bool:
  match xs:
    case []:
      False{}
    case x <> rest:
      U32.is_eq(x, i) || Fix.has(rest, i)

# a Brownie at a tile centre empties the bins on and beside it and mends
# smashed furniture there
def Ride.tick(r: Ride, +idx: U32, +q: Q, +ts: +List<Track>, +occ: +List<U32>,
  +plan: +List<Board>, +qt: +List<U32>, +fresh: Bool, +t: U32, +fx: +List<U32>) -> Ride:
  Ride{+kind, +x, +y, +w, +h, +price, +open, +ph, +tm, ent, ex, +qlen, +wmin, +wmax, +total, +earned, +born, rate, +wear} = r
  +tk = Tracks.get(ts, h)
  +ps = Track.pieces(tk)
  +brk = Wear.broken(wear)
  +n = Seat.count((Tab.at(occ, (idx * 2 : U32)) .|. Boards.mask(plan, idx, 0) : U32))
  +nb = Boards.count(plan, idx, 0)
  +go = (n > 0 : U32) && (tm >= wmin : U32) && ((n >= Ride.seats(kind) : U32) || (tm >= wmax : U32))
  +ph2 = sel(Ride.cycles(kind), Ride.next_ph(ph, tm, go, Ride.duration(kind)), 0)
  Ride{kind, x, y, w, h, price, open, sel(brk, ph, ph2), sel(brk, tm, sel(Ride.cycles(kind), Ride.next_tm(ph, ph2, tm, n), 0)),
    Ride.door(kind, q, ps, x, y, w, 7), Ride.door(kind, q, ps, x, y, w, 1), sel(fresh, Tab.at(qt, idx), qlen),
    wmin, wmax, (total + nb : U32), (earned + nb * price : U32), born, Ride.rating(kind, tk),
    Wear.tick(wear, kind, open, idx, t, born, Fix.has(fx, idx))}

def Rides.tick(+rs: +List<Ride>, +idx: U32, +q: Q, +ts: +List<Track>, +occ: +List<U32>,
  +plan: +List<Board>, +qt: +List<U32>, +fresh: Bool, +t: U32, +fx: +List<U32>) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Ride.tick(r, idx, q, ts, occ, plan, qt, fresh, t, fx) <> Rides.tick(rest, (idx + 1 : U32), q, ts, occ, plan, qt, fresh, t, fx)

# The coaster's ratings from its track: turns and drops thrill, height
# thrills most, length adds a little; a track that isn't a circuit yet has
# none. Tally: turns | drops << 8 | pieces << 16, and heights lo | hi << 8.
type Txn is Data:
  Gain{kind: U32, amt: U32}
  Spend{kind: U32, amt: U32}

def Txn.apply(+cash: U32, t: Txn) -> U32:
  match t:
    case Gain{k, a}:
      (cash + a : U32)
    case Spend{k, a}:
      (cash - a : U32)

def Ledger.apply(+xs: +List<Txn>, +cash: U32) -> U32:
  match xs:
    case []:
      cash
    case t <> rest:
      Ledger.apply(rest, Txn.apply(cash, t))

def Ledger.put(keep: Bool, t: Txn, +xs: +List<Txn>) -> +List<Txn>:
  match keep:
    case True{}:
      t <> xs
    case False{}:
      xs

# what a sale counts as: the tavern sells food, the potion stall drinks
def Ride.cat(+k: U32) -> U32:
  match k:
    case 3:
      6
    case 4:
      5
    case 9:
      5
    case _:
      1

# a board is a sale: the price of its ride (the same Guest.fee its guest pays)
def Board.sale(b: Board, +rs: +List<Ride>) -> Txn:
  Board{g, +ride, seat} = b
  +rd = Rides.get(rs, ride)
  Gain{Ride.cat(Ride.kind(rd)), Ride.price(rd)}

def Ledger.sales(+plan: +List<Board>, +rs: +List<Ride>) -> +List<Txn>:
  match plan:
    case []:
      []
    case b <> rest:
      Board.sale(b, rs) <> Ledger.sales(rest, rs)

def Ledger.upkeep(+rs: +List<Ride>) -> +List<Txn>:
  match rs:
    case []:
      []
    case r <> rest:
      +k = Ride.kind(r)
      Ledger.put(Bool.not(U32.is_eq(k, 0)), Spend{2, Ride.upkeep(k)},
        Ledger.upkeep(rest))

def MONTH() -> U32:
  3600

# a tick's gold: sales, the arrivals' entry fees, and each month the rides'
# upkeep and the loan's interest (1/80 of it)
def Fin.loan(f: Fin) -> U32:
  Fin{fee, loan, rating, now, last, hist, res} = f
  loan

def Staff.wage(+k: U32) -> U32:
  match k:
    case 1:
      20
    case 2:
      35
    case 3:
      30
    case 4:
      25
    case _:
      0

def Staff.kind(s: Staff) -> U32:
  Staff{id, x, y, dir, kind, st, tgt, tmr, zone, look} = s
  kind

def Staff.wages(+ss: +List<Staff>) -> U32:
  match ss:
    case []:
      0
    case s <> rest:
      (Staff.wage(Staff.kind(s)) + Staff.wages(rest) : U32)

def Fin.res(f: Fin) -> U32:
  Fin{fee, loan, rating, now, last, hist, res} = f
  res

def Res.done(+r: U32) -> Bool:
  U32.is_eq((r .&. 8191 : U32), 8191)

def Res.funding(+r: U32) -> U32:
  ((r >> 24n) .&. 3 : U32)

def Res.cost(+r: U32) -> U32:
  +f = Res.funding(r)
  sel(Res.done(r), 0, sel(U32.is_eq(f, 1), 150, sel(U32.is_eq(f, 2), 400, 0)))

def Ledger.tick(+gs: +List<Guest>, +rs: +List<Ride>, +t: U32, +plan: +List<Board>,
  +narr: U32, +f: Fin, +ss: +List<Staff>) -> +List<Txn>:
  +monthly = U32.is_eq((t % MONTH() : U32), 0) && (t > 0 : U32)
  +fees = (narr * U32.min(Fin.fee(f), 40) : U32)
  +interest = (Fin.loan(f) / 80 : U32)
  Ledger.put(Bool.not(U32.is_eq(fees, 0)), Gain{7, fees},
    List.append(&2, Txn, Ledger.sales(plan, rs),
      Bool.pick(+List<Txn>, monthly,
        Ledger.put(Bool.not(U32.is_eq(interest, 0)), Spend{10, interest},
          Ledger.put(Bool.not(U32.is_eq(Res.cost(Fin.res(f)), 0)), Spend{12, Res.cost(Fin.res(f))},
          Ledger.put(Bool.not(U32.is_eq(Staff.wages(ss), 0)), Spend{11, Staff.wages(ss)}, Ledger.upkeep(rs)))), [])))

# The books: every ledger entry is added to this month's column
def Txn.book(t: Txn, +tab: +List<U32>) -> +List<U32>:
  match t:
    case Gain{+k, +a}:
      Tab.add(tab, (k - 1 : U32), a)
    case Spend{+k, +a}:
      Tab.add(tab, (k - 1 : U32), a)

def Fin.book_all(+xs: +List<Txn>, +tab: +List<U32>) -> +List<U32>:
  match xs:
    case []:
      tab
    case t <> rest:
      Fin.book_all(rest, Txn.book(t, tab))

def Fin.book(f: Fin, +xs: +List<Txn>) -> Fin:
  Fin{fee, loan, rating, +now, last, hist, res} = f
  Fin{fee, loan, rating, Fin.book_all(xs, now), last, hist, res}

# The park rating: happy guests and open rides raise it, queasy guests lower
# it (worked out every 64 ticks)
def Guests.happy_sum(+gs: +List<Guest>, +acc: U32) -> U32:
  match gs:
    case []:
      acc
    case g <> rest:
      Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, +ha, lk, mind, bl} = g
      Guests.happy_sum(rest, (acc + ha : U32))

def Guests.sick_sum(+gs: +List<Guest>, +acc: U32) -> U32:
  match gs:
    case []:
      acc
    case g <> rest:
      Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, +na, ha, lk, mind, bl} = g
      Guests.sick_sum(rest, (acc + na : U32))

# the park's rating: happy guests and attractions raise it; sick guests
# and mess on the paths (nm pieces) lower it
def Scen.count(+n: Nat, +k: U32, +q: Q, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      +t = Land.get(q, (k >> 6n : U32), (k .&. 63 : U32))
      Scen.count(m, (k + 1 : U32), q, (acc + sel(U32.is_eq(Tile.obj(t), 2) && (Tile.a(t) >= 4 : U32), 1, 0) : U32))

def Park.rate(+gs: +List<Guest>, +rs: +List<Ride>, +nm: U32, +sc: U32) -> U32:
  +n = len32(Guest, gs)
  +happy = sel(U32.is_eq(n, 0), 200, (Guests.happy_sum(gs, 0) / U32.max(n, 1) : U32))
  +sick = sel(U32.is_eq(n, 0), 0, (Guests.sick_sum(gs, 0) / U32.max(n, 1) : U32))
  U32.min(sub0(sub0((150 + happy * 2 + U32.min((Rides.attractions(rs) * 30 : U32), 240) + U32.min((sc * 3 : U32), 150) : U32), sick),
    (U32.min(nm, 300) >> 1n : U32)), 999)

def Park.rate_if(now: Bool, +gs: +List<Guest>, +rs: +List<Ride>, +nm: U32, +q: Q, +old: U32) -> U32:
  match now:
    case True{}:
      Park.rate(gs, rs, nm, Scen.count(4096n, 0, q, 0))
    case False{}:
      old

def Wins32.take(+n: Nat, +xs: +List<U32>) -> +List<U32>:
  match n xs:
    case 0n _:
      []
    case 1n+m Con{x, rest}:
      x <> Wins32.take(m, rest)
    case 1n+m Nil{}:
      []

def Fin.fresh(month: Bool, +now: +List<U32>) -> +List<U32>:
  match month:
    case True{}:
      Tab.zero(12, [])
    case False{}:
      now

def Fin.roll(month: Bool, +now: +List<U32>, +last: +List<U32>) -> +List<U32>:
  match month:
    case True{}:
      now
    case False{}:
      last

def Fin.sample(go: Bool, +gs: +List<Guest>, +hist: +List<U32>) -> +List<U32>:
  match go:
    case True{}:
      Wins32.take(32n, len32(Guest, gs) <> hist)
    case False{}:
      hist

# each tick: the rating now and then, the guest count sampled, and at a
# month's turn this month's column becomes last month's
# Research (the books' res): bits 0-12 what is unlocked (0 Healer's Tent,
# 1 Hedge Labyrinth, 2 Golem Bumpers, 3 Wisp Seller, 4 Wheel of Stars,
# 5 Enchanted Ices, 6 Griffin Swing, 7 Dragon's Eyrie, 8 Lich's Crypt,
# 9 Wizard's Whirl, 10 Mermaid Flume, 11 statues and fountains, 12 walls and
# fences), 16-23 progress toward the next, 24-25 funding (0 none, 1 steady,
# 2 lavish), 26-29 the scenario (0 sandbox), 30-31 its outcome (1 won,
# 2 lost). Each month steady funding costs 150 and moves research 96 of 256
# along, lavish 400 and 192.
def Res.next.go(+n: Nat, +k: U32, +r: U32) -> U32:
  match n:
    case 0n:
      13
    case 1n+m:
      sel(U32.is_eq(((r >> U32.to_nat(k)) .&. 1 : U32), 0), k, Res.next.go(m, (k + 1 : U32), r))

def Res.next(+r: U32) -> U32:
  Res.next.go(13n, 0, r)

def Res.tick(month: Bool, +r: U32) -> U32:
  match month:
    case True{}:
      +f = Res.funding(r)
      +p = (((r >> 16n) .&. 255) + sel(U32.is_eq(f, 1), 96, sel(U32.is_eq(f, 2), 192, 0)) : U32)
      +unlock = (p >= 256 : U32) && Bool.not(Res.done(r))
      +r2 = sel(unlock, (r .|. U32.shln(1, U32.to_nat(Res.next(r))) : U32), r)
      +p2 = sel(unlock, (p - 256 : U32), U32.min(p, 255))
      ((r2 .&. 4278255615) .|. (sel(Res.done(r2), 0, p2) << 16n) : U32)
    case False{}:
      r

# land at the park's edge can be bought: wild land beside land that isn't
def Land.wild(+q: Q, +x: U32, +y: U32) -> Bool:
  U32.is_eq(Tile.ter(Land.get(q, x, y)), 4) || Bool.not(inmap(x, y))

def Land.buyable(+q: Q, +x: U32, +y: U32) -> Bool:
  inmap(x, y) && U32.is_eq(Tile.ter(Land.get(q, x, y)), 4)
    && (Bool.not(Land.wild(q, (x + 1 : U32), y)) || Bool.not(Land.wild(q, (x - 1 : U32), y))
      || Bool.not(Land.wild(q, x, (y + 1 : U32))) || Bool.not(Land.wild(q, x, (y - 1 : U32))))

def Fin.tick(f: Fin, +t: U32, +gs: +List<Guest>, +rs: +List<Ride>, +nm: U32, +q: Q) -> Fin:
  Fin{fee, loan, +rating, +now, +last, +hist, +res} = f
  +month = U32.is_eq((t % MONTH() : U32), 0) && (t > 0 : U32)
  +sample = U32.is_eq((t % 450 : U32), 0)
  Fin{fee, loan, Park.rate_if(U32.is_eq((t .&. 63 : U32), 0), gs, rs, nm, q, rating),
    Fin.fresh(month, now), Fin.roll(month, now, last), Fin.sample(sample, gs, hist), Res.tick(month, res)}

# The Wyrm Coaster: track pieces and block sections
# -------------------------------------------------
# A piece stands on tile (x, y), entered at height z heading dir. kind: 0
# straight, 1 up, 2 down, 3 turn left, 4 turn right, 5 station, 6 lift hill,
# 9 brakes, 10 banked left, 11 banked right, 12 steep up, 13 steep down.
# Track ops 7 (take the last piece off) and 8 (open or close) are not
# pieces.

def Piece.adds(+op: U32) -> Bool:
  (op < 7 : U32) || (op >= 9 : U32) && (op < 14 : U32)

def Piece.cost(+k: U32) -> U32:
  sel(U32.is_eq(k, 0), 30, sel(U32.is_eq(k, 5) || U32.is_eq(k, 6) || (k >= 12 : U32), 60,
    sel((k >= 9 : U32), 50, 40)))

def Piece.exit(p: Piece) -> Pose:
  Piece{+x, +y, +z, +kind, +dir} = p
  +d2 = sel(Piece.left(kind), ((dir + 3) .&. 3 : U32),
    sel(Piece.right(kind), ((dir + 1) .&. 3 : U32), dir))
  +z2 = ((z + Piece.rise(kind)) - Piece.drop(kind) : U32)
  Pose{(x + dx_of(d2) : U32), (y + dy_of(d2) : U32), z2, d2}

def Slot.ready(s: Slot) -> Bool:
  match s:
    case Free{a, n, st}:
      False{}
    case Held{a, +n, st, t}:
      Train.ready(t, n)

# a train that reached the end of its block enters the next one if free:
# cfst is what becomes of the block it leaves, csnd of the block it enters
def Slot.count(s: Slot) -> Nat:
  match s:
    case Free{a, n, st}:
      0n
    case Held{a, n, st, t}:
      1n

def Blocks.trains(+ss: +List<Slot>) -> Nat:
  match ss:
    case []:
      0n
    case s <> rest:
      Nat.add(Slot.count(s), Blocks.trains(rest))

# blocks of 4 pieces; a train waits in every third block
def Track.safe(+t: Track) -> Bool:
  imp(Track.open(t), Track.closed(t))

def Fin.new() -> Fin:
  Fin{0, 0, 600, Tab.zero(12, []), Tab.zero(12, []), [], 8191}

def Fin.now(f: Fin) -> +List<U32>:
  Fin{fee, loan, rating, now, last, hist, res} = f
  now

def Fin.last(f: Fin) -> +List<U32>:
  Fin{fee, loan, rating, now, last, hist, res} = f
  last

def Fin.hist(f: Fin) -> +List<U32>:
  Fin{fee, loan, rating, now, last, hist, res} = f
  hist

# Staff: kind 1 Brownie (handyman), 2 Dwarven Tinker (mechanic), 3 Watch
# Knight (security), 4 Bard (entertainer); x, y in 1/16 tile; st: what they
# are doing; tgt: where they are headed (packed tile) or NONE; zone: their
# patrol area (x0 | y0 << 8 | x1 << 16 | y1 << 24), or NONE for everywhere
type Park is Data:
  Park{map: Q, guests: List<&2, Guest>, rides: List<&2, Ride>, track: List<&2, Track>,
    cash: U32, time: U32, nid: U32, fin: Fin, mess: List<&2, U32>, staff: List<&2, Staff>}

type Act is Data:
  Tick{}
  Build{tool: U32, x: U32, y: U32, v: U32}
  TrackOp{op: U32}
  RideOp{ride: U32, op: U32}
  ParkOp{op: U32}

# a step's results: the park after it, its gold, the guests who came and
# went, and the mess dropped and swept up
type Out is Data:
  Out{park: Park, ledger: List<&2, Txn>, arrived: List<&2, Guest>,
    departed: List<&2, Guest>, dropped: List<&2, U32>, swept: List<&2, U32>}

def Staff.count(+ss: +List<Staff>, +k: U32) -> U32:
  match ss:
    case []:
      0
    case s <> rest:
      (sel(U32.is_eq(Staff.kind(s), k), 1, 0) + Staff.count(rest, k) : U32)

def Staff.post(+rs: +List<Ride>, +n: U32) -> U32:
  +m = len32(Ride, rs)
  +r = Rides.get(rs, sel(U32.is_eq(m, 0), 0, (n % U32.max(m, 1) : U32)))
  sel(U32.is_eq(m, 0), pk(GATE_X(), (GATE_Y() - 2 : U32)), pk(Ride.cx(r), Ride.cy(r)))

def Staff.new(+k: U32, +t: U32, +n: U32, +post: U32) -> Staff:
  Staff{(t * 64 + n : U32), (GATE_X() * 16 + 8 : U32), (GATE_Y() * 16 + 8 : U32), 3, k, 0, NONE(), 0,
    post, hash(t, (n + 5 : U32))}

def Staff.fire(+ss: +List<Staff>, +k: U32) -> +List<Staff>:
  match ss:
    case []:
      []
    case s <> rest:
      Bool.pick(+List<Staff>, U32.is_eq(Staff.kind(s), k), rest, s <> Staff.fire(rest, k))

# park ops 21-24 hire one of kind 1-4 (at most 40 staff), 31-34 let one go
def Staff.op(+ss: +List<Staff>, +op: U32, +t: U32, +rs: +List<Ride>) -> +List<Staff>:
  +hire = (op >= 21 : U32) && (op <= 24 : U32) && (len32(Staff, ss) < 40 : U32)
  +fire = (op >= 31 : U32) && (op <= 34 : U32)
  +k = sel(hire, (op - 20 : U32), (op - 30 : U32))
  Bool.pick(+List<Staff>, hire,
    List.append(&2, Staff, ss, [Staff.new(k, t, len32(Staff, ss), Staff.post(rs, Staff.count(ss, k)))]),
    Bool.pick(+List<Staff>, fire, Staff.fire(ss, k), ss))

# the tile of the mess nearest to both the Brownie and their post (within 12
# tiles of the post, and scoring under 24), or NONE
def Mess.near(+ms: +List<U32>, +i: U32, +j: U32, +zone: U32, +best: U32, +bd: U32) -> U32:
  match ms:
    case []:
      sel((bd < 24 : U32), best, NONE())
    case m <> rest:
      +mi = (Mess.x(m) >> 4n : U32)
      +mj = (Mess.y(m) >> 4n : U32)
      +d = (absd(mi, i) + absd(mj, j) : U32)
      +zd = (absd(mi, (zone >> 6n : U32)) + absd(mj, (zone .&. 63 : U32)) : U32)
      +take = (d + zd < bd : U32) && (zd <= 12 : U32)
      Mess.near(rest, i, j, zone, sel(take, pk(mi, mj), best), sel(take, (d + zd : U32), bd))

# the nearest broken-down ride (its index), or NONE
def Rides.broken_near(+rs: +List<Ride>, +idx: U32, +i: U32, +j: U32, +best: U32, +bd: U32) -> U32:
  match rs:
    case []:
      best
    case r <> rest:
      +d = (absd(Ride.cx(r), i) + absd(Ride.cy(r), j) : U32)
      +take = Wear.broken(Ride.wear(r)) && (d < bd : U32)
      Rides.broken_near(rest, (idx + 1 : U32), i, j, sel(take, idx, best), sel(take, d, bd))

# where a Tinker works on a ride: its exit, else its entrance
def Ride.work_tile(r: Ride) -> U32:
  +r2 = r
  sel(U32.is_eq(Ride.ex(r2), NONE()), Ride.ent(r2), Ride.ex(r2))

# a staff member's next job at a tile centre: tgt | ride << 12 | st << 20
# (st 0 patrolling, 1 heading somewhere, 2 at work)
def Staff.job.go(+k: U32, +rs: +List<Ride>, +ms: +List<U32>, +i: U32, +j: U32, +here: U32, +zone: U32, +patrol: U32) -> U32:
  match k:
    case 1:
      +m = Mess.near(ms, i, j, zone, NONE(), 99999)
      sel(U32.is_eq(m, NONE()), patrol, (m .|. (255 << 12n) .|. (sel(U32.is_eq(m, here), 2, 1) << 20n) : U32))
    case 2:
      +r = Rides.broken_near(rs, 0, i, j, NONE(), 99999)
      +w = Ride.work_tile(Rides.get(rs, r))
      +ok = Bool.not(U32.is_eq(r, NONE())) && Bool.not(U32.is_eq(w, NONE()))
      sel(ok, ((w .&. 4095) .|. ((r .&. 255) << 12n) .|. (sel(U32.is_eq(w, here), 2, 1) << 20n) : U32), patrol)
    case _:
      patrol

def Staff.job(+k: U32, +rs: +List<Ride>, +ms: +List<U32>, +i: U32, +j: U32, +zone: U32) -> U32:
  +zd = (absd((zone >> 6n : U32), i) + absd((zone .&. 63 : U32), j) : U32)
  Staff.job.go(k, rs, ms, i, j, pk(i, j), zone,
    sel((zd > 6 : U32), (zone .|. (1 << 20n) : U32), (4095 .|. (255 << 12n) : U32)))

def Staff.job_if(now: Bool, +k: U32, +rs: +List<Ride>, +ms: +List<U32>, +i: U32, +j: U32, +zone: U32,
  +st: U32, +tgt: U32, +tmr: U32) -> U32:
  match now:
    case True{}:
      Staff.job(k, rs, ms, i, j, zone)
    case False{}:
      ((tgt .&. 4095) .|. ((tmr .&. 255) << 12n) .|. (st << 20n) : U32)

# a step: at a tile centre take the next job and pick a way; walk a pixel a
# tick along the paths (queues too); a Tinker at work stands still
def Staff.step(s: Staff, +q: Q, +rs: +List<Ride>, +ms: +List<U32>, +t: U32) -> Staff:
  Staff{+id, +x, +y, +dir, +kind, +st, +tgt, +tmr, +zone, +look} = s
  +i = (x >> 4n : U32)
  +j = (y >> 4n : U32)
  +here = Land.get(q, i, j)
  +h = Tile.h(here)
  +ctr = Guest.at_center(x, y)
  +onq = U32.is_eq(Tile.obj(here), 7)
  +fe = Bool.not(onq) || U32.is_eq(Tile.a(here), 1)
  +job = Staff.job_if(ctr, kind, rs, ms, i, j, zone, st, tgt, tmr)
  +tg = (job .&. 4095 : U32)
  +st2 = (job >> 20n : U32)
  +none = U32.is_eq(tg, 4095)
  +tx = sel(none, i, (tg >> 6n : U32))
  +ty = sel(none, j, (tg .&. 63 : U32))
  +work = U32.is_eq(st2, 2) && U32.is_eq(kind, 2)
  +dir2 = Guest.steer(ctr && Bool.not(work), q, i, j, h, dir, tx, ty, hash(id, t), True{}, onq, fe, 0)
  +go = Bool.not(work) && (Bool.not(ctr) || Guest.can_step(q, i, j, h, dir2, True{}, onq, fe))
  Staff{id, sel(go, (x + dx_of(dir2) : U32), x), sel(go, (y + dy_of(dir2) : U32), y), dir2, kind, st2,
    sel(none, NONE(), tg), ((job >> 12n) .&. 255 : U32), zone, look}

def Staff.steps(+ss: +List<Staff>, +q: Q, +rs: +List<Ride>, +ms: +List<U32>, +t: U32) -> +List<Staff>:
  match ss:
    case []:
      []
    case s <> rest:
      Staff.step(s, q, rs, ms, t) <> Staff.steps(rest, q, rs, ms, t)

# the rides Tinkers are working on
def Staff.fixing(+ss: +List<Staff>) -> +List<U32>:
  match ss:
    case []:
      []
    case s <> rest:
      Staff{id, x, y, dir, +kind, +st, tgt, +tmr, zone, look} = s
      Mess.put(U32.is_eq(kind, 2) && U32.is_eq(st, 2), tmr, Staff.fixing(rest))

def Tend.set(on: Bool, +q: Q, +i: U32, +j: U32, t: Tile) -> Q:
  match on:
    case True{}:
      Land.set(q, i, j, t)
    case False{}:
      q

def Tend.tile(+q: Q, +i: U32, +j: U32) -> Q:
  +t = Land.get(q, i, j)
  +a = Tile.a(t)
  +need = U32.is_eq(Tile.obj(t), 1) && Bool.not(U32.is_eq((a .&. 15 : U32), 0))
    && Bool.not(U32.is_eq(((a >> 4n) .&. 31 : U32), 0))
  Tend.set(need, q, i, j, Tile{Tile.h(t), Tile.ter(t), 1, (a .&. 15 : U32), Tile.b(t)})

def Tend.go(on: Bool, +q: Q, +i: U32, +j: U32) -> Q:
  match on:
    case True{}:
      Tend.tile(Tend.tile(Tend.tile(Tend.tile(Tend.tile(q, i, j), (i + 1 : U32), j), (i - 1 : U32), j),
        i, (j + 1 : U32)), i, (j - 1 : U32))
    case False{}:
      q

def Staff.tend(+ss: +List<Staff>, +q: Q) -> Q:
  match ss:
    case []:
      q
    case s <> rest:
      Staff{id, +x, +y, dir, +kind, st, tgt, tmr, zone, look} = s
      Staff.tend(rest, Tend.go(U32.is_eq(kind, 1) && Guest.at_center(x, y), q, (x >> 4n : U32), (y >> 4n : U32)))

# Watch Knights and Bards leave a mark on the paved tiles around them (tile
# b bits 16-23 and 24-31: the time, in 64-tick steps, with bit 7 set), which
# guests read: a Knight nearby keeps them from vandalism, a Bard cheers them
def Stamp.tile(+q: Q, +i: U32, +j: U32, +sh: Nat, +v: U32) -> Q:
  +t = Land.get(q, i, j)
  +o = Tile.obj(t)
  +paved = U32.is_eq(o, 1) || U32.is_eq(o, 5) || U32.is_eq(o, 7)
  +b = Tile.b(t)
  Tend.set(paved && inmap(i, j), q, i, j,
    Tile{Tile.h(t), Tile.ter(t), o, Tile.a(t), ((b .&. (4294967295 - (255 << sh))) .|. (v << sh) : U32)})

def Stamp.area(+n: Nat, +k: U32, +w: U32, +q: Q, +ci: U32, +cj: U32, +sh: Nat, +v: U32) -> Q:
  match n:
    case 0n:
      q
    case 1n+m:
      +r = (w >> 1n : U32)
      Stamp.area(m, (k + 1 : U32), w, Stamp.tile(q, (ci + (k % w) - r : U32), (cj + (k / w) - r : U32), sh, v),
        ci, cj, sh, v)

def Staff.stamp(+ss: +List<Staff>, +q: Q, +t: U32) -> Q:
  match ss:
    case []:
      q
    case s <> rest:
      Staff{id, +x, +y, dir, +kind, st, tgt, tmr, zone, look} = s
      +knight = U32.is_eq(kind, 3)
      +bard = U32.is_eq(kind, 4)
      +w = sel(knight, 5, 3)
      Staff.stamp(rest, Bool.pick(Q, knight || bard,
        Stamp.area(U32.to_nat((w * w : U32)), 0, w, q, (x >> 4n : U32), (y >> 4n : U32), Bool.pick(Nat, knight, 16n, 24n), Stamp.now(t)),
        q), t)

def Staff.stamp_if(now: Bool, +ss: +List<Staff>, +q: Q, +t: U32) -> Q:
  match now:
    case True{}:
      Staff.stamp(ss, q, t)
    case False{}:
      q

def Park.tick(p: Park) -> Out:
  Park{+map, +guests, +rides, +track, cash, +time, +nid, +fin, +mess, +staff} = p
  +stn = Stn.all(track)
  +occ = Occ.table(guests, rides, stn)
  +plan = Boards.plan(guests, occ, map, rides, stn, [])
  +moved = Guests.step(guests, map, rides, time, plan, stn, Queue.list(guests, map, []))
  +arr = Guests.arrivals(guests, rides, time, nid, fin)
  +led = Ledger.tick(guests, rides, time, plan, len32(Guest, arr), fin, staff)
  +evs = Mess.events(guests, plan, map, time)
  +drops = Mess.drops(evs, (len32(U32, mess) < 600 : U32))
  +swept = Mess.swept(mess, staff)
  +map1 = Mess.mark(swept, False{}, Mess.mark(drops, True{}, Bin.fill(Mess.only(evs, False{}), map)))
  +map2 = Staff.stamp_if(U32.is_eq((time .&. 63 : U32), 0), staff, Staff.tend(staff, map1), time)
  Out{Park{map2, List.append(&2, Guest, arr, Guests.stay(moved)),
    Rides.tick(rides, 0, map, track, occ, plan,
      Qlen.fill_if(U32.is_eq((time .&. 15 : U32), 0), guests, map, len32(Ride, rides)), U32.is_eq((time .&. 15 : U32), 0), time, Staff.fixing(staff)),
    Tracks.tick(track), Ledger.apply(led, cash), (time + 1 : U32),
    (nid + len32(Guest, arr) : U32), Fin.tick(fin, time, guests, rides, len32(U32, mess), map),
    List.append(&2, U32, drops, Mess.kept(mess, staff)), Staff.steps(staff, map, rides, mess, time)}, led, arr, Guests.left(moved), drops, swept}

# Building
# --------
# tool: 1 path, 2 raise land, 3 lower land, 4 tree (v: variant), 5..8 rides
# of kind 1..4, 9 demolish, 10 start the coaster (station facing v)

def Tile.free(+t: Tile, +h: U32) -> Bool:
  U32.is_eq(Tile.obj(t), 0) && U32.is_eq(Tile.h(t), h)
    && Bool.not(U32.is_eq(Tile.ter(t), 2)) && Bool.not(U32.is_eq(Tile.ter(t), 4))

def Land.free(+q: Q, +x: U32, +y: U32, +h: U32) -> Bool:
  inmap(x, y) && Tile.free(Land.get(q, x, y), h)

def Build.fits(+q: Q, +k: U32, +x: U32, +y: U32) -> Bool:
  +h = Land.h(q, x, y)
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  Land.free(q, x, y, h) && (U32.is_eq(Ride.size(k), 1) || (Land.free(q, x1, y, h)
    && Land.free(q, x, y1, h) && Land.free(q, x1, y1, h)))

def Build.cost(+tool: U32) -> U32:
  match tool:
    case 1:
      10
    case 2:
      20
    case 3:
      20
    case 4:
      15
    case 9:
      0
    case 10:
      40
    case 11:
      12
    case 13:
      20
    case 14:
      30
    case 15:
      25
    case 41:
      60
    case 42:
      120
    case 43:
      15
    case 44:
      25
    case 45:
      8
    case 46:
      60
    case 48:
      40
    case _:
      Ride.cost(Tool.kind(tool))

def Build.can_pay(+cash: U32, +cost: U32) -> Bool:
  Bool.not(neg(cash)) && (cash >= cost : U32)

# tools 13, 14, 15: a bin, a bench, a lamp, on a path without one
def Build.legal.go(+tool: U32, +q: Q, +trk: +List<Track>, +x: U32, +y: U32, +o: U32,
  +h: U32, +dry: Bool, +empty: Bool, +a: U32) -> Bool:
  match tool:
    case 1:
      empty
    case 2:
      empty && (h < 6 : U32)
    case 3:
      empty && ((h > 0 : U32) || dry)
    case 4:
      empty && dry
    case 9:
      U32.is_eq(o, 1) || U32.is_eq(o, 2) || U32.is_eq(o, 3) || U32.is_eq(o, 7) || Bool.not(U32.is_eq(((a >> 24n) .&. 15 : U32), 0))
    case 11:
      empty && dry
    case 13:
      U32.is_eq(o, 1) && U32.is_eq((a .&. 4278190095 : U32), 0)
    case 14:
      U32.is_eq(o, 1) && U32.is_eq((a .&. 4278190095 : U32), 0)
    case 15:
      U32.is_eq(o, 1) && U32.is_eq((a .&. 4278190095 : U32), 0)
    case 41:
      empty && dry
    case 42:
      empty && dry
    case 43:
      empty && dry
    case 44:
      empty && dry
    case 45:
      empty && dry
    case 46:
      Land.buyable(q, x, y)
    case 48:
      (U32.is_eq(o, 1) || U32.is_eq(o, 6)) && U32.is_eq(((a >> 24n) .&. 15 : U32), 0) && (Deck.level(q, x, y) <= 15 : U32)
    case 10:
      empty && dry
    case _:
      Bool.not(U32.is_eq(Tool.kind(tool), 0)) && Build.fits(q, Tool.kind(tool), x, y)

def Build.legal(+q: Q, +trk: +List<Track>, +tool: U32, +x: U32, +y: U32) -> Bool:
  +t = Land.get(q, x, y)
  +o = Tile.obj(t)
  +ter = Tile.ter(t)
  +h = Tile.h(t)
  +dry = Bool.not(U32.is_eq(ter, 2)) && Bool.not(U32.is_eq(ter, 4))
  +empty = U32.is_eq(o, 0) && Bool.not(U32.is_eq(ter, 4))
  Build.legal.go(tool, q, trk, x, y, o, h, dry, empty, Tile.a(t))

def Build.ok(+q: Q, +trk: +List<Track>, +cash: U32, +tool: U32, +x: U32, +y: U32)
  -> Bool:
  inmap(x, y) && Build.legal(q, trk, tool, x, y)
    && Build.can_pay(cash, Build.cost(tool))

# a demolished ride hands back half its price; paths and trees a little
def Build.refund(+q: Q, +rs: +List<Ride>, +x: U32, +y: U32) -> U32:
  +t = Land.get(q, x, y)
  sel(U32.is_eq(Tile.obj(t), 3),
    (Ride.cost(Ride.kind(Rides.get(rs, Tile.a(t)))) >> 1n : U32), 4)

def Build.ledger(ok: Bool, +q: Q, +rs: +List<Ride>, +tool: U32, +x: U32,
  +y: U32) -> +List<Txn>:
  match ok:
    case True{}:
      Bool.pick(+List<Txn>, U32.is_eq(tool, 9),
        [Gain{4, Build.refund(q, rs, x, y)}], [Spend{3, Build.cost(tool)}])
    case False{}:
      []

def Land.put(+q: Q, +x: U32, +y: U32, +obj: U32, +a: U32, +b: U32) -> Q:
  +t = Land.get(q, x, y)
  Land.set(q, x, y, Tile{Tile.h(t), Tile.ter(t), obj, a, b})

def Land.ride(+q: Q, +k: U32, +x: U32, +y: U32, +idx: U32) -> Q:
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  Bool.pick(Q, U32.is_eq(Ride.size(k), 1), Land.put(q, x, y, 3, idx, 1),
    Land.put(Land.put(Land.put(Land.put(q, x, y, 3, idx, 0), x1, y, 3, idx, 0),
      x, y1, 3, idx, 0), x1, y1, 3, idx, 1))

def Land.clear_ride(+q: Q, r: Ride) -> Q:
  Ride{kind, +x, +y, +w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  +one = Land.put(q, x, y, 0, 0, 0)
  Bool.pick(Q, U32.is_eq(w, 1), one,
    Land.put(Land.put(Land.put(one, x1, y, 0, 0, 0), x, y1, 0, 0, 0), x1, y1,
      0, 0, 0))

# demolishing: a ride goes whole; a path's furniture goes first, then the path
def Build.demolish(+q: Q, +rs: +List<Ride>, +x: U32, +y: U32) -> Q:
  +t = Land.get(q, x, y)
  +furn = U32.is_eq(Tile.obj(t), 1) && Bool.not(U32.is_eq((Tile.a(t) .&. 15 : U32), 0))
  Bool.pick(Q, U32.is_eq(Tile.obj(t), 3),
    Land.clear_ride(q, Rides.get(rs, Tile.a(t))),
    Bool.pick(Q, furn, Land.set(q, x, y, Tile{Tile.h(t), Tile.ter(t), 1, 0, Tile.b(t)}), Land.put(q, x, y, 0, 0, 0)))

def Build.land.go(+tool: U32, +q: Q, +rs: +List<Ride>, +x: U32, +y: U32,
  +v: U32, +h: U32, +ter: U32, +b: U32, +nt: U32) -> Q:
  match tool:
    case 1:
      Land.set(q, x, y, Tile{h, sel(U32.is_eq(ter, 2), 2, 1), 1, 0, 0})
    case 2:
      Land.set(q, x, y, Tile{sel(U32.is_eq(ter, 2), h, (h + 1 : U32)), 0, 0, 0, 0})
    case 3:
      Land.set(q, x, y, Tile{sub0(h, 1), sel(U32.is_eq(h, 0), 2, ter), 0, 0, 0})
    case 4:
      Land.set(q, x, y, Tile{h, ter, 2, (v .&. 3 : U32), 0})
    case 9:
      # a deck comes off before what it stands over
      +t = Land.get(q, x, y)
      Bool.pick(Q, Bool.not(U32.is_eq(Deck.of(t), 0)), Land.set(q, x, y, Tile{h, ter, Tile.obj(t), (Tile.a(t) .&. 16777215 : U32), b}),
        Build.demolish(q, rs, x, y))
    case 48:
      +t = Land.get(q, x, y)
      Land.set(q, x, y, Tile{h, ter, Tile.obj(t), ((Tile.a(t) .&. 16777215) .|. (Deck.level(q, x, y) << 24n) : U32), b})
    case 10:
      Land.set(q, x, y, Tile{h, ter, 6, ((5 + (v .&. 3) * 16) .|. (nt << 8n) : U32), h})
    case 11:
      Land.set(q, x, y, Tile{h, 1, 7, 0, 0})
    case 13:
      Land.set(q, x, y, Tile{h, ter, 1, 1, b})
    case 14:
      Land.set(q, x, y, Tile{h, ter, 1, 2, b})
    case 15:
      Land.set(q, x, y, Tile{h, ter, 1, 3, b})
    case 41:
      Land.set(q, x, y, Tile{h, ter, 2, (4 + (v .&. 3) : U32), 0})
    case 42:
      Land.set(q, x, y, Tile{h, ter, 2, 8, 0})
    case 43:
      Land.set(q, x, y, Tile{h, ter, 2, (9 + sel(U32.is_eq((v .&. 3 : U32), 3), 0, (v .&. 3 : U32)) : U32), 0})
    case 44:
      Land.set(q, x, y, Tile{h, ter, 2, 12, 0})
    case 45:
      Land.set(q, x, y, Tile{h, ter, 2, 13, 0})
    case 46:
      Land.set(q, x, y, Tile{h, 0, 0, 0, 0})
    case _:
      Land.ride(q, Tool.kind(tool), x, y, len32(Ride, rs))

def Build.land(+q: Q, +rs: +List<Ride>, +tool: U32, +x: U32, +y: U32,
  +v: U32, +nt: U32) -> Q:
  +t = Land.get(q, x, y)
  Build.land.go(tool, q, rs, x, y, v, Tile.h(t), Tile.ter(t), Tile.b(t), nt)

def Build.map(ok: Bool, +q: Q, +rs: +List<Ride>, +tool: U32, +x: U32, +y: U32,
  +v: U32, +nt: U32) -> Q:
  match ok:
    case True{}:
      Build.land(q, rs, tool, x, y, v, nt)
    case False{}:
      q

def Ride.killed(r: Ride) -> Ride:
  Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  Ride{0, x, y, w, h, price, 0, 0, 0, NONE(), NONE(), 0, wmin, wmax, total, earned, born, 0, 255}

def Rides.kill(+rs: +List<Ride>, +i: U32) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Bool.pick(Ride, U32.is_eq(i, 0), Ride.killed(r), r)
        <> Rides.kill(rest, (i - 1 : U32))

def Build.rides(ok: Bool, +q: Q, +rs: +List<Ride>, +tool: U32, +x: U32,
  +y: U32, +time: U32, +nt: U32) -> +List<Ride>:
  match ok:
    case True{}:
      +t = Land.get(q, x, y)
      +k = Tool.kind(tool)
      +s = Ride.size(k)
      Bool.pick(+List<Ride>, U32.is_eq(tool, 9) && U32.is_eq(Tile.obj(t), 3),
        Rides.kill(rs, Tile.a(t)),
        Bool.pick(+List<Ride>, Bool.not(U32.is_eq(k, 0)),
          List.append(&2, Ride, rs, [Ride.new(k, x, y, s, 1, time)]),
          Bool.pick(+List<Ride>, U32.is_eq(tool, 10),
            List.append(&2, Ride, rs, [Ride.coaster(x, y, nt, time)]),
            rs)))
    case False{}:
      rs

def Track.begin(+q: Q, +x: U32, +y: U32, +v: U32) -> Track:
  +h = Land.h(q, x, y)
  +pc = {Piece{x, y, h, 5, (v .&. 3 : U32)} : Piece}
  Track{[pc], False{}, [], Pose{x, y, h, (v .&. 3 : U32)}, Piece.exit(pc), Cfg.new(), 0}

def Build.track(ok: Bool, +q: Q, +trk: +List<Track>, +tool: U32, +x: U32, +y: U32,
  +v: U32) -> +List<Track>:
  match ok:
    case True{}:
      Bool.pick(+List<Track>, U32.is_eq(tool, 10), List.append(&2, Track, trk, [Track.begin(q, x, y, v)]), trk)
    case False{}:
      trk

def Park.build(p: Park, +tool: U32, +x: U32, +y: U32, +v: U32) -> Out:
  Park{+map, guests, +rides, +track, +cash, +time, nid, fin, mess, staff} = p
  +ok = Build.ok(map, track, cash, tool, x, y)
  +led = Build.ledger(ok, map, rides, tool, x, y)
  Out{Park{Land.fix(Build.map(ok, map, rides, tool, x, y, v, len32(Track, track))), guests,
    Build.rides(ok, map, rides, tool, x, y, time, len32(Track, track)), Build.track(ok, map, track, tool,
    x, y, v), Ledger.apply(led, cash), time, nid, fin, mess, staff}, led, [], [], [], []}

# Coaster track editing
# ---------------------
# op 0..6: add a piece of that kind at the end; 7: remove the last piece;
# 8: open or close the coaster

def Track.start(t: Track) -> Pose:
  Track{pieces, open, blocks, start, end, cfg, stats} = t
  start

def Track.end(t: Track) -> Pose:
  Track{pieces, open, blocks, start, end, cfg, stats} = t
  end

def Pose.x(p: Pose) -> U32:
  Pose{x, y, z, d} = p
  x

def Pose.y(p: Pose) -> U32:
  Pose{x, y, z, d} = p
  y

def Pose.z(p: Pose) -> U32:
  Pose{x, y, z, d} = p
  z

def Pose.d(p: Pose) -> U32:
  Pose{x, y, z, d} = p
  d

def Pieces.last(+ps: +List<Piece>) -> Piece:
  Pieces.get(ps, (len32(Piece, ps) - 1 : U32))

def Pieces.init(+ps: +List<Piece>) -> +List<Piece>:
  match ps:
    case []:
      []
    case p <> rest:
      Bool.pick(+List<Piece>, U32.is_eq(len32(Piece, rest), 0), [],
        p <> Pieces.init(rest))

def Piece.pose(p: Piece) -> Pose:
  Piece{x, y, z, kind, dir} = p
  Pose{x, y, z, dir}

def Track.room(+q: Q, +e: Pose, +op: U32) -> Bool:
  +x = Pose.x(e)
  +y = Pose.y(e)
  +z = Pose.z(e)
  +t = Land.get(q, x, y)
  +dr = Piece.drop(op)
  inmap(x, y) && U32.is_eq(Tile.obj(t), 0) && Bool.not(U32.is_eq(Tile.ter(t), 4))
    && (z >= dr : U32) && (Tile.h(t) + dr <= z : U32) && (z + Piece.rise(op) <= 12 : U32)

# A track op: code (bits 0-4) | coaster << 5 (11 bits) | piece << 16 (the
# piece a cut starts at)
def TrackOp.k(+op: U32) -> U32:
  ((op >> 5n) .&. 2047 : U32)

def TrackOp.idx(+op: U32) -> U32:
  (op >> 16n : U32)

# steep pieces only face the camera: climbs heading toward it (-u, -v),
# drops heading away (+u, +v)
def Piece.faces(+op: U32, +d: U32) -> Bool:
  (Bool.not(U32.is_eq(op, 12)) || (d >= 2 : U32)) && (Bool.not(U32.is_eq(op, 13)) || (d < 2 : U32))

# edits need the coaster shut, or on its test run (an edit ends the test);
# cutting (26: from a piece to the end; 27: the whole coaster) works any time
def TrackOp.ok(+q: Q, +trk: Track, +cash: U32, +op: U32) -> Bool:
  +n = len32(Piece, Track.pieces(trk))
  +shut = Bool.not(Track.open(trk)) || Test.testing(Track.stats(trk))
  +plat = Bool.not(U32.is_eq(op, 5)) || U32.is_eq(Piece.kind(Pieces.last(Track.pieces(trk))), 5)
  +add = Piece.adds(op) && shut && (n > 0 : U32) && (n < 250 : U32) && Bool.not(Track.closed(trk)) && plat
    && Piece.faces(op, Pose.d(Track.end(trk))) && Track.room(q, Track.end(trk), op) && Build.can_pay(cash, Piece.cost(op))
  +del = U32.is_eq(op, 7) && shut && (n > 1 : U32)
  +set = ((op >= 16 : U32) && (op < 24 : U32) || U32.is_eq(op, 28) || U32.is_eq(op, 29)) && shut
  +tst = (U32.is_eq(op, 24) || U32.is_eq(op, 25)) && shut && Track.closed(trk)
  +cut = U32.is_eq(op, 26) && (n > 1 : U32) || U32.is_eq(op, 27) && (n > 0 : U32)
  add || del || set || tst || cut || U32.is_eq(op, 8)

# where a cut starts: the whole coaster (27), else never the first station
# piece
def TrackOp.from(+op: U32, +ix: U32) -> U32:
  sel(U32.is_eq(op, 27), 0, U32.max(ix, 1))

def Pieces.refund(+ps: +List<Piece>, +i: U32, +from: U32) -> U32:
  match ps:
    case []:
      0
    case p <> rest:
      +p2 = p
      (sel((i >= from : U32), (Piece.cost(Piece.kind(p2)) >> 1n : U32), 0) + Pieces.refund(rest, (i + 1 : U32), from) : U32)

# half the price of every piece a cut takes off
def TrackOp.refund(+trk: Track, +op: U32, +ix: U32) -> U32:
  Pieces.refund(Track.pieces(trk), 0, TrackOp.from(op, ix))

def Pieces.take(+ps: +List<Piece>, +n: U32) -> +List<Piece>:
  match ps:
    case []:
      []
    case p <> rest:
      Bool.pick(+List<Piece>, U32.is_eq(n, 0), [], p <> Pieces.take(rest, (n - 1 : U32)))

def Pieces.drop(+ps: +List<Piece>, +n: U32) -> +List<Piece>:
  match ps:
    case []:
      []
    case p <> rest:
      Bool.pick(+List<Piece>, U32.is_eq(n, 0), p <> rest, Pieces.drop(rest, (n - 1 : U32)))

def Land.clear_pieces(+ps: +List<Piece>, +q: Q) -> Q:
  match ps:
    case []:
      q
    case p <> rest:
      Piece{+x, +y, z, kind, dir} = p
      Land.clear_pieces(rest, Land.put(q, x, y, 0, 0, 0))

# a cut: the pieces from `from` on come off; the track closes
def Track.cut(t: Track, +from: U32) -> Track:
  Track{+ps, open, bs, +s, +e, +cfg, stats} = t
  +n = len32(Piece, ps)
  +e2 = Bool.pick(Pose, U32.is_eq(from, 0), s, Bool.pick(Pose, (from >= n : U32), e, Piece.pose(Pieces.get(ps, from))))
  Track{Pieces.take(ps, from), False{}, [], s, e2, cfg, 0}

# after any change the check runs again at once: a closed circuit whose dry
# run passes goes straight onto a test run; anything else stays shut
def Track.recheck(+t: Track) -> Track:
  Bool.pick(Track, Track.closed(t) && U32.is_eq(Dry.fail(Dry.run(Track.pieces(t), Track.cfg(t))), 255), Track.test(t), t)

# a piece costs its price; taking one off gives half of its price back, and
# so does each piece a cut takes off
def TrackOp.ledger(ok: Bool, +op: U32, +last: U32, +refund: U32) -> +List<Txn>:
  match ok:
    case True{}:
      Bool.pick(+List<Txn>, Piece.adds(op), [Spend{3, Piece.cost(op)}],
        Bool.pick(+List<Txn>, U32.is_eq(op, 7), [Gain{4, (Piece.cost(last) >> 1n : U32)}],
        Bool.pick(+List<Txn>, U32.is_eq(op, 26) || U32.is_eq(op, 27), [Gain{4, refund}], [])))
    case False{}:
      []

def Piece.code(p: Piece) -> U32:
  Piece{x, y, z, kind, dir} = p
  (kind + dir * 16 : U32)

def TrackOp.map(ok: Bool, +q: Q, +trk: Track, +op: U32, +k: U32, +ix: U32) -> Q:
  match ok:
    case True{}:
      +e = Track.end(trk)
      +pc = {Piece{Pose.x(e), Pose.y(e), Pose.z(e), op, Pose.d(e)} : Piece}
      +last = Pieces.last(Track.pieces(trk))
      +lp = Piece.pose(last)
      Bool.pick(Q, Piece.adds(op),
        Land.put(q, Pose.x(e), Pose.y(e), 6, (Piece.code(pc) .|. (k << 8n) : U32), Pose.z(e)),
        Bool.pick(Q, U32.is_eq(op, 7), Land.put(q, Pose.x(lp), Pose.y(lp), 0, 0, 0),
        Bool.pick(Q, U32.is_eq(op, 26) || U32.is_eq(op, 27), Land.clear_pieces(Pieces.drop(Track.pieces(trk), TrackOp.from(op, ix)), q),
          q)))
    case False{}:
      q

# opening builds the blocks and puts the trains on; closing takes them off
def Track.toggle.go(open: Bool, +ps: +List<Piece>, bs: +List<Slot>, +s: Pose,
  +e: Pose, +cfg: U32, +stats: U32) -> Track:
  match open:
    case True{}:
      Track{ps, False{}, [], s, e, cfg, sel(Test.testing(stats), 0, stats)}
    case False{}:
      +n = len32(Piece, ps)
      +shut = {Track{ps, False{}, [], s, e, cfg, stats} : Track}
      +ok = (True{} && Track.closed(shut)) && Test.live(stats)
      +want = Cfg.trains(cfg)
      +bl = Track.blen(U32.max(U32.min(U32.min(Cfg.cars(cfg), Pieces.stations(ps)), 20), 1))
      Track{ps, ok, Bool.pick(+List<Slot>, ok, Blocks.make(U32.to_nat(n), 0, n, 0, sel(U32.is_eq(want, 0), 99, want), bl), []), s, e, cfg, stats}

def Track.toggle(t: Track) -> Track:
  Track{+ps, open, bs, +s, +e, +cfg, +stats} = t
  Track.toggle.go(open, ps, bs, s, e, cfg, stats)

# changing a setting closes the coaster (it is closed already: see TrackOp.ok)
def Track.setcfg(t: Track, +op: U32) -> Track:
  Track{+ps, open, bs, +s, +e, +cfg, +stats} = t
  +maxc = U32.max(U32.min(Pieces.stations(ps), 20), 1)
  +bl = Track.blen(U32.max(U32.min(Cfg.cars(cfg), maxc), 1))
  Track{ps, False{}, [], s, e, Cfg.set(cfg, op, Track.most(len32(Piece, ps), bl), maxc), 0}

# every coaster's type, two bits each (coaster k at bits 2k), for drawing
# every coaster's type, in order, for drawing
def Tracks.tylist(+ts: +List<Track>) -> +List<U32>:
  match ts:
    case []:
      []
    case t <> rest:
      +t2 = t
      Cfg.type(Track.cfg(t2)) <> Tracks.tylist(rest)

def Tracks.types(+ts: +List<Track>, +k: U32) -> U32:
  match ts:
    case []:
      0
    case t <> rest:
      +t2 = t
      ((Cfg.type(Track.cfg(t2)) << (U32.to_nat((k * 2 : U32)))) .|. Tracks.types(rest, (k + 1 : U32)) : U32)

def Track.edit(t: Track, +op: U32) -> Track:
  Track{+ps, open, bs, +s, +e, +cfg, +stats} = t
  +pc = {Piece{Pose.x(e), Pose.y(e), Pose.z(e), op, Pose.d(e)} : Piece}
  Bool.pick(Track, Piece.adds(op),
    Track{List.append(&2, Piece, ps, [pc]), False{}, [], s, Piece.exit(pc), cfg, 0},
    Track{Pieces.init(ps), False{}, [], s, Piece.pose(Pieces.last(ps)), cfg, 0})

def Track.op(+t: Track, +op: U32, +ix: U32, ok: Bool) -> Track:
  match ok:
    case True{}:
      Bool.pick(Track, U32.is_eq(op, 8), Track.toggle(t),
        Bool.pick(Track, U32.is_eq(op, 24), Track.test(t),
        Bool.pick(Track, U32.is_eq(op, 25), Track.pretest(t),
        Bool.pick(Track, U32.is_eq(op, 26) || U32.is_eq(op, 27), Track.recheck(Track.cut(t, TrackOp.from(op, ix))),
        Bool.pick(Track, (op >= 16 : U32), Track.recheck(Track.setcfg(t, op)), Track.recheck(Track.edit(t, op)))))))
    case False{}:
      t

# coaster k's ride opens (1) or closes (0), or goes with its demolished
# track (2)
def Rides.coaster(+rs: +List<Ride>, +k: U32, +open: U32) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Ride{+kind, x, y, w, +h, price, op, +ph, +tm, +ent, +ex, +qlen, wmin, wmax, total, earned, born, +rate, +wear} = r
      +hit = U32.is_eq(kind, 5) && U32.is_eq(h, k)
      +gone = hit && U32.is_eq(open, 2)
      Ride{sel(gone, 0, kind), x, y, w, h, price, sel(hit, sel(gone, 0, open), op), sel(gone, 0, ph), sel(gone, 0, tm),
        sel(gone, NONE(), ent), sel(gone, NONE(), ex), sel(gone, 0, qlen), wmin, wmax, total, earned, born, sel(gone, 0, rate), sel(gone, 255, wear)}
        <> Rides.coaster(rest, k, open)

def Park.track_op(p: Park, +op: U32) -> Out:
  Park{+map, guests, +rides, +track, +cash, time, nid, fin, mess, staff} = p
  +k = TrackOp.k(op)
  +code = (op .&. 31 : U32)
  +ix = TrackOp.idx(op)
  +trk = Tracks.get(track, k)
  +ok = TrackOp.ok(map, trk, cash, code) && (k < len32(Track, track) : U32)
  +led = TrackOp.ledger(ok, code, Piece.kind(Pieces.last(Track.pieces(trk))), TrackOp.refund(trk, code, ix))
  +trk2 = Track.op(trk, code, ix, ok)
  Out{Park{Land.fix(TrackOp.map(ok, map, trk, code, k, ix)), guests,
    Rides.coaster(rides, k, sel(ok && U32.is_eq(code, 27), 2, sel(Track.open(trk2) && Test.passed(Track.stats(trk2)), 1, 0))), Tracks.set(track, k, trk2),
    Ledger.apply(led, cash), time, nid, fin, mess, staff}, led, [], [], [], []}

# Ride settings (the ride window)
# -------------------------------
# op 0: open or close (the coaster opens through its track instead); 1, 2:
# price up, down; 3, 4: minimum wait up, down; 5, 6: maximum wait up, down

def MAX_PRICE() -> U32:
  20

def Ride.set(r: Ride, +op: U32) -> Ride:
  Ride{+kind, x, y, w, h, +price, +open, ph, tm, ent, ex, qlen, +wmin, +wmax, total, earned, born, rate, wear} = r
  +flip = U32.is_eq(op, 0) && Bool.not(U32.is_eq(kind, 5))
  +price2 = Price.cap(sel(U32.is_eq(op, 1), (price + 1 : U32), sel(U32.is_eq(op, 2), sub0(price, 1), price)))
  +wmin2 = sel(U32.is_eq(op, 3), U32.min((wmin + 30 : U32), wmax),
    sel(U32.is_eq(op, 4), sub0(wmin, 30), wmin))
  +wmax2 = sel(U32.is_eq(op, 5), U32.min((wmax + 60 : U32), 3600),
    sel(U32.is_eq(op, 6), U32.max(sub0(wmax, 60), wmin), wmax))
  Ride{kind, x, y, w, h, price2, sel(flip, sel(U32.is_eq(open, 1), 0, 1), open), ph, tm, ent, ex, qlen, wmin2, wmax2, total, earned, born, rate, wear}

def Rides.set(+rs: +List<Ride>, +i: U32, +op: U32) -> +List<Ride>:
  match rs:
    case []:
      []
    case r <> rest:
      Bool.pick(Ride, U32.is_eq(i, 0), Ride.set(r, op), r) <> Rides.set(rest, (i - 1 : U32), op)

def Park.ride_op(p: Park, +ride: U32, +op: U32) -> Out:
  Park{map, guests, +rides, track, cash, time, nid, fin, mess, staff} = p
  Out{Park{map, guests, Rides.set(rides, ride, op), track, cash, time, nid, fin, mess, staff}, [], [], [], [], []}

# Park settings (the park and finances windows)
# ---------------------------------------------
# op 0, 1: entry fee up, down (0..40); 2: borrow 1000 gold (owing at most
# 20000); 3: repay 1000 (with the gold in hand)

def Fin.set(f: Fin, +op: U32, +borrow: Bool, +repay: Bool) -> Fin:
  Fin{+fee, +loan, rating, now, last, hist, +res} = f
  Fin{Fee.cap(sel(U32.is_eq(op, 0), (fee + 1 : U32), sel(U32.is_eq(op, 1), sub0(fee, 1), fee))),
    sel(borrow, (loan + 1000 : U32), sel(repay, (loan - 1000 : U32), loan)), rating, now, last, hist,
    sel(U32.is_eq(op, 50), (res .|. 1073741824 : U32), sel(U32.is_eq(op, 51), (res .|. 2147483648 : U32),
    sel((op >= 40 : U32) && (op <= 42 : U32), ((res .&. 4244635647) .|. ((op - 40) << 24n) : U32), res)))}

def Park.park_op(p: Park, +op: U32) -> Out:
  Park{map, guests, +rides, track, +cash, +time, nid, +fin, mess, +staff} = p
  +loan = Fin.loan(fin)
  +borrow = U32.is_eq(op, 2) && (loan + 1000 <= 20000 : U32)
  +repay = U32.is_eq(op, 3) && (loan >= 1000 : U32) && Bool.not(neg(cash)) && (cash >= 1000 : U32)
  +led = Bool.pick(+List<Txn>, borrow, [Gain{8, 1000}], Bool.pick(+List<Txn>, repay, [Spend{9, 1000}], []))
  Out{Park{map, guests, rides, track, Ledger.apply(led, cash), time, nid, Fin.set(fin, op, borrow, repay), mess,
    Staff.op(staff, op, time, rides)}, led, [], [], [], []}

# every step's ledger goes into the books
def Out.book(o: Out) -> Out:
  Out{p, +l, ar, de, dr, sw} = o
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  Out{Park{map, guests, rides, track, cash, time, nid, Fin.book(fin, l), mess, staff}, l, ar, de, dr, sw}

def Park.step0(p: Park, a: Act) -> Out:
  match a:
    case Tick{}:
      Park.tick(p)
    case Build{tool, x, y, v}:
      Park.build(p, tool, x, y, v)
    case TrackOp{op}:
      Park.track_op(p, op)
    case RideOp{ride, op}:
      Park.ride_op(p, ride, op)
    case ParkOp{op}:
      Park.park_op(p, op)

# the one door every change comes through
def Park.step(p: Park, a: Act) -> Out:
  Out.book(Park.step0(p, a))

# a scenario's opening: gold, loan and research set before play begins
def Fin.setup(f: Fin, +loan: U32, +res: U32) -> Fin:
  Fin{fee, l, rating, now, last, hist, r} = f
  Fin{fee, loan, rating, now, last, hist, res}

def Park.setup(p: Park, +cash: U32, +loan: U32, +res: U32) -> Park:
  Park{map, guests, rides, track, c, time, nid, fin, mess, staff} = p
  Park{map, guests, rides, track, cash, time, nid, Fin.setup(fin, loan, res), mess, staff}

def Park.new() -> Park:
  Park{Land.fix(Q.build(6n, 0, 0)), [], [], [], 30000, 0, 1, Fin.new(), [], []}

def Out.park(o: Out) -> Park:
  Out{p, l, ar, de, dr, sw} = o
  p

def Out.ledger(o: Out) -> +List<Txn>:
  Out{p, l, ar, de, dr, sw} = o
  l

def Out.arrived(o: Out) -> +List<Guest>:
  Out{p, l, ar, de, dr, sw} = o
  ar

def Out.departed(o: Out) -> +List<Guest>:
  Out{p, l, ar, de, dr, sw} = o
  de

def Out.dropped(o: Out) -> +List<U32>:
  Out{p, l, ar, de, dr, sw} = o
  dr

def Out.swept(o: Out) -> +List<U32>:
  Out{p, l, ar, de, dr, sw} = o
  sw

def Park.run(acts: List<Act>, +p: Park) -> Park:
  match acts:
    case []:
      p
    case a <> rest:
      Park.run(rest, Out.park(Park.step(p, a)))

def Park.map(p: Park) -> Q:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  map

def Park.guests(p: Park) -> +List<Guest>:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  guests

def Park.track(p: Park) -> +List<Track>:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  track

def Park.cash(p: Park) -> U32:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  cash

def Park.time(p: Park) -> U32:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  time

def Park.rides(p: Park) -> +List<Ride>:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  rides

def Park.fin(p: Park) -> Fin:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  fin

def Park.mess(p: Park) -> +List<U32>:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  mess

def Park.staff(p: Park) -> +List<Staff>:
  Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  staff
