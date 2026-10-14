# Spike 1: can a tiled "drawable list" rasterizer push an isometric map at
# a playable frame rate? Every visible tile becomes a drawable; the frame is
# a quadtree whose nodes filter the list down to what overlaps them.
import Base

type Dr is Data:
  DTile{x: U32, y: U32, ter: U32}
  DTree{x: U32, y: U32, kind: U32}

type S is Data:
  S{cam: U32, frame: U32, t0: Nat}

def sel(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def absd(+a: U32, +b: U32) -> U32:
  sel((a > b : U32), (a - b : U32), (b - a : U32))

def hash(+x: U32, +y: U32) -> U32:
  +h = ((x * 374761393) + (y * 668265263) : U32)
  +h2 = ((h .^. (h >> 13n)) * 1274126177 : U32)
  (h2 .^. (h2 >> 16n) : U32)

# bounding boxes: [x0, x1) x [y0, y1)
def Dr.hits_box(d: Dr, +bx: U32, +by: U32, +s: U32) -> Bool:
  match d:
    case DTile{x, y, ter}:
      +x = x
      +y = y
      ((x + 16 > bx) && (x < bx + s + 16) && (y + 16 > by) && (y < by + s) : U32)
    case DTree{x, y, kind}:
      +x = x
      +y = y
      ((x + 8 > bx) && (x < bx + s + 8) && (y + 2 > by) && (y < by + s + 24) : U32)

def TRANSP() -> U32:
  16777216

def grass(+px: U32, +py: U32) -> U32:
  +n = (hash(px, py) .&. 7 : U32)
  sel((n < 2 : U32), 3902766, sel((n < 6 : U32), 4631357, 5358924))

def Dr.shade(d: Dr, +px: U32, +py: U32) -> U32:
  match d:
    case DTile{x, y, ter}:
      +x = x
      +y = y
      +dx = absd(px, x)
      +dy = absd(py, (y + 8 : U32))
      sel(((dx + dy * 2) <= 16 : U32), sel(U32.is_eq(ter, 1), 12626544, grass(px, py)), TRANSP())
    case DTree{x, y, kind}:
      +x = x
      +y = y
      +dx = absd(px, x)
      +dy = absd(py, (y - 14 : U32))
      +trunk = ((py + 6 > y) && (py < y + 2) && (dx < 2) : U32)
      +crown = ((dx * dx + dy * dy) < 64 : U32)
      sel(trunk, 6045995, sel(crown, sel(U32.is_eq((hash(px, py) .&. 3 : U32), 0), 9055202, 7349173), TRANSP()))

# front-to-back: the first opaque sample wins; `done` stops the walk
def first(+xs: +List<Dr>, done: Bool, +c: U32, +px: U32, +py: U32) -> U32:
  match xs done:
    case _ True{}:
      c
    case Nil{} False{}:
      1581366
    case Con{d, rest} False{}:
      +c2 = Dr.shade(d, px, py)
      first(rest, Bool.not(U32.is_eq(c2, TRANSP())), c2, px, py)

def put(keep: Bool, +d: Dr, xs: +List<Dr>) -> +List<Dr>:
  match keep:
    case True{}:
      d <> xs
    case False{}:
      xs

def filt(+xs: +List<Dr>, +bx: U32, +by: U32, +s: U32) -> +List<Dr>:
  match xs:
    case []:
      []
    case d <> rest:
      put(Dr.hits_box(d, bx, by, s), d, filt(rest, bx, by, s))

def draw(+d: Nat, +xs: +List<Dr>, +x0: U32, +y0: U32) -> Image:
  match d xs:
    case _ Nil{}:
      Pix{1581366}
    case 0n Con{h, t}:
      Pix{first(h <> t, False{}, 0, x0, y0)}
    case 1n+e Con{h, t}:
      +xs = {h <> t : +List<Dr>}
      +s = U32.shln(1, e)
      +x1 = (x0 + s : U32)
      +y1 = (y0 + s : U32)
      a b c k = draw(e, filt(xs, x0, y0, s), x0, y0) draw(e, filt(xs, x1, y0, s), x1, y0) draw(e, filt(xs, x0, y1, s), x0, y1) draw(e, filt(xs, x1, y1, s), x1, y1)
      Qua{a, b, c, k}

# world: 64x64 tiles; tile (i,j) top vertex at wx = 1024 + 16(i-j), wy = 8(i+j)
def ter_at(+i: U32, +j: U32) -> U32:
  sel(U32.is_eq(i, 20) || U32.is_eq(j, 30), 1, sel(U32.is_eq((hash(i, j) .&. 7 : U32), 0), 2, 0))

def push_obj(tree: Bool, +sx: U32, +sy: U32, +t: U32, acc: +List<Dr>) -> +List<Dr>:
  match tree:
    case True{}:
      DTree{sx, (sy + 8 : U32), 0} <> DTile{sx, sy, 0} <> acc
    case False{}:
      DTile{sx, sy, t} <> acc

def push_vis(vis: Bool, +sx: U32, +sy: U32, +t: U32, acc: +List<Dr>) -> +List<Dr>:
  match vis:
    case True{}:
      push_obj(U32.is_eq(t, 2), sx, sy, t, acc)
    case False{}:
      acc

def push_tile(+i: U32, +j: U32, +cam: U32, acc: +List<Dr>) -> +List<Dr>:
  +sx = ((1024 + 16 * i + 4096) - (16 * j + cam) : U32)
  +sy = ((8 * i + 8 * j + 4096) - 200 : U32)
  +vis = ((sx + 16 > 4096) && (sx < 4096 + 512 + 16) && (sy + 16 > 4096) && (sy < 4096 + 320 + 24) : U32)
  push_vis(vis, sx, sy, ter_at(i, j), acc)

# back-to-front accumulation (consing) yields a front-to-back list
def row(+n: Nat, +i: U32, +cam: U32, acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      row(p, i, cam, push_tile(i, U32.from_nat(p), cam, acc))

def rows(+n: Nat, +cam: U32, acc: +List<Dr>) -> +List<Dr>:
  match n:
    case 0n:
      acc
    case 1n+p:
      rows(p, cam, row(64n, U32.from_nat(p), cam, acc))

def scene(+cam: U32) -> +List<Dr>:
  rows(64n, cam, [])

def view(s: S) -> S & Image:
  S{+cam, frame, t0} = s
  (S{cam, frame, t0}, draw(9n, scene(cam), 4096, 4096))

def report(due: Bool, +now: Nat, t0: Nat) -> IO(Nat):
  match due:
    case True{}:
      do IO<Nat>:
        IO.print("64 frames in " ++ Nat.show(Nat.sub(now, t0)) ++ " ms")
        return now
    case False{}:
      IO.pure(Nat, t0)

def quit(events: List<Event>) -> Bool:
  match events:
    case []:
      False{}
    case e <> rest:
      match e:
        case Close{}:
          True{}
        case Key{k, d}:
          U32.is_eq(k, 27) || quit(rest)
        case _:
          quit(rest)

def step(stop: Bool, s: S) -> IO(Maybe<S>):
  match stop:
    case True{}:
      IO.pure(Maybe<S>, None{})
    case False{}:
      S{cam, frame, t0} = s
      +f = (frame + 1 : U32)
      do IO<Maybe<S>>:
        now : Nat <- IO.now()
        t1 : Nat <- report(U32.is_eq((f .&. 63 : U32), 0), now, t0)
        return Some{S{(cam + 2 : U32), f, t1}}

def tick(events: List<Event>, s: S) -> IO(Maybe<S>):
  step(quit(events), s)

def main() -> IO(Unit):
  App.run(~S, ~App{view, tick}, "Spike", 1024, 640, S{0, 0, 0n})
