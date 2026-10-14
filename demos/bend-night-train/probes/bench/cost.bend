# cost: how much work one frame's tile tree asks for.
#
# The frame time is the per-pixel pass, and the per-pixel pass is one walk of
# its tile's triangle list per pixel.  So the number that predicts it is
# sum over leaves of |triangles in leaf| * TILE*TILE, together with the same
# for sprites.  This walks the renderer's own tree build (Raster.Tri.keep,
# Raster.Spr.keep, Tile.side) without shading, and prints those counts beside
# the scene's own triangle total, so a scene whose triangles land in the sky
# -- where nothing can see them -- is visible as a gap.
#
# Serial on purpose: the counts must not depend on how the tree is scheduled.
import Base
import ../../src/geo.bend as Geo
import ../../src/rt.bend as Rt
import ../../src/raster.bend as Raster
import ../../src/ride.bend as Ride
import ../../src/shade.bend as Shade
import ../../src/world.bend as World
import ../../src/inst.bend as Inst
import ../../src/carriage.bend as Carriage


def Main.env.u32.maybe(m: Maybe<&2, U32>, +dflt: U32) -> IO(U32):
  match m:
    case None{}:
      IO.pure(U32, dflt)
    case Some{v}:
      IO.pure(U32, v)


def Main.env.u32.pick(r: Result<&1, &1, U32 & String, String>, +dflt: U32)
  -> IO(U32):
  match r:
    case Fail{e}:
      IO.pure(U32, dflt)
    case Done{value}:
      Main.env.u32.maybe(U32.read(value), dflt)


def Main.env.u32(name: String, +dflt: U32) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    Main.env.u32.pick(r, dflt)


# ---- counting --------------------------------------------------------
# List.length is non-tail, so the count is folded in.
def Len.tris(xs: List<&2, Rt.Tri>, +n: Nat) -> Nat:
  match xs:
    case []:
      n
    case _ <> rest:
      Len.tris(rest, Nat.add(n, 1n))


def Len.sprs(xs: List<&2, Rt.Spr>, +n: Nat) -> Nat:
  match xs:
    case []:
      n
    case _ <> rest:
      Len.sprs(rest, Nat.add(n, 1n))


def Len.geo(xs: List<&2, Geo.WTri>, +n: Nat) -> Nat:
  match xs:
    case []:
      n
    case _ <> rest:
      Len.geo(rest, Nat.add(n, 1n))


def Bigger.max(yes: Bool, +a: Nat, +b: Nat) -> Nat:
  match yes:
    case True{}:
      a
    case False{}:
      b


type Acc is Data:
  Acc{leaves: Nat, pairs: Nat, maxn: Nat, spairs: Nat, smax: Nat, nodes: Nat,
    inc: Nat}


# Every node runs one keep per child over its own list, so the filter's work is
# four times the sum of |node| over every node of the tree, leaves included.
def Acc.node(+a: Acc, +n: Nat) -> Acc:
  Acc{leaves, pairs, maxn, spairs, smax, nodes, inc} = a
  Acc{leaves, pairs, maxn, spairs, smax, Nat.add(nodes, 1n), Nat.add(inc, n)}


def Acc.tile(+a: Acc, +n: Nat, +m: Nat) -> Acc:
  Acc{leaves, pairs, maxn, spairs, smax, nodes, inc} = a
  +side = Raster.Tile.side()
  +px = Nat.mul(side, side)
  Acc{Nat.add(leaves, 1n), Nat.add(pairs, Nat.mul(n, px)),
    Bigger.max(U32.is_gt(U32.from_nat(n), U32.from_nat(maxn)), n, maxn),
    Nat.add(spairs, Nat.mul(m, px)),
    Bigger.max(U32.is_gt(U32.from_nat(m), U32.from_nat(smax)), m, smax),
    Nat.add(nodes, 1n), Nat.add(inc, n)}


def Main.walk(+d: Nat, +x: U32, +y: U32, +size: U32, +tris: List<&2, Rt.Tri>,
  +ss: List<&2, Rt.Spr>, +a: Acc) -> Acc:
  match d:
    case 0n:
      Acc.tile(a, Len.tris(tris, 0n), Len.sprs(ss, 0n))
    case 1n+k:
      +a1 = Acc.node(a, Len.tris(tris, 0n))
      +h = U32.shrn(size, 1n)
      +x1 = U32.add(x, h)
      +y1 = U32.add(y, h)
      +x2 = U32.add(x, size)
      +y2 = U32.add(y, size)
      +lx = U32.to_f32(x)
      +ly = U32.to_f32(y)
      +mx = U32.to_f32(x1)
      +my = U32.to_f32(y1)
      +rx = U32.to_f32(x2)
      +ry = U32.to_f32(y2)
      Main.walk(k, x1, y1, h, Raster.Tri.keep(tris, mx, my, rx, ry, []),
        Raster.Spr.keep(ss, mx, my, rx, ry, []),
        Main.walk(k, x, y1, h, Raster.Tri.keep(tris, lx, my, mx, ry, []),
          Raster.Spr.keep(ss, lx, my, mx, ry, []),
          Main.walk(k, x1, y, h, Raster.Tri.keep(tris, mx, ly, rx, my, []),
            Raster.Spr.keep(ss, mx, ly, rx, my, []),
            Main.walk(k, x, y, h, Raster.Tri.keep(tris, lx, ly, mx, my, []),
              Raster.Spr.keep(ss, lx, ly, mx, my, []),
              Acc.node(a, Len.tris(tris, 0n))))))


def Main.scene(stage: U32, +s: F32) -> List<&2, Geo.WTri>:
  match stage:
    case 0:
      +cars = Carriage.Carriage.cars()
      a b c = World.World.emit(s, []) Inst.Inst.emit(s, [])
        Carriage.Carriage.all(s, cars, [])
      List.append(&2, Geo.WTri, List.append(&2, Geo.WTri, a, b), c)
    case 1:
      a b = World.World.emit(s, []) Inst.Inst.emit(s, [])
      List.append(&2, Geo.WTri, a, b)
    case 2:
      World.World.emit(s, [])
    case _:
      []


def Main.show(label: String, +g: Nat, +a: Acc) -> String:
  Acc{leaves, pairs, maxn, spairs, smax, nodes, inc} = a
  label ++ " tris=" ++ Nat.show(g) ++ " leaves=" ++ Nat.show(leaves)
    ++ " nodes=" ++ Nat.show(nodes) ++ " inc=" ++ Nat.show(inc)
    ++ " keepsteps=" ++ Nat.show(Nat.mul(inc, 4n)) ++ " pairs="
    ++ Nat.show(pairs) ++ " max=" ++ Nat.show(maxn) ++ " smax="
    ++ Nat.show(smax) ++ "\n"


def Main.stage(+st: U32, +d: Nat, +s: F32) -> String:
  +w = U32.shln(1, d)
  +cam = Rt.VCam.ride(w, w, s, 4.6, 3.05, Ride.Ride.yaw(s, 0.0, False{}),
    (0.0 - 0.02 : F32))
  +ws = Main.scene(st, s)
  +tris = Rt.Tri.emit(ws, cam)
  +sprs = Shade.Stars.list(cam, 0.0)
  Main.show("stage" ++ U32.show(st) ++ " d" ++ Nat.show(d),
    Len.geo(ws, 0n),
    Main.walk(Raster.Nat.tile.levels(d), 0, 0, w, tris, sprs, Acc{0n, 0n, 0n, 0n, 0n, 0n, 0n}))


def Main.run() -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 9)
    +d : Nat = U32.to_nat(depth)
    +s : F32 = 110.0
    IO.print(Main.stage(3, d, s) ++ Main.stage(2, d, s) ++ Main.stage(1, d, s)
      ++ Main.stage(0, d, s))


def main() -> IO(Unit):
  Main.run()
