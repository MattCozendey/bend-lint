# levels: how much work the quadtree's filter asks for.
#
# Every node runs one keep per child over its own triangle list, so the
# filter's total step count is four times the sum of the list length over every
# node of the tree.  The leaves' share of that sum is work the per-pixel pass
# needs anyway; everything above the leaves is pure overhead, and it is the
# overhead that decides whether the tree is worth its depth.
#
# Prints the sum over all nodes, the sum over the leaves, and the node count.
# Serial on purpose: the counts must not depend on how the tree is scheduled.
import Base
import ../../src/geo.bend as Geo
import ../../src/rt.bend as Rt
import ../../src/raster.bend as Raster
import ../../src/ride.bend as Ride
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


def Len.tris(xs: List<&2, Rt.Tri>, +n: Nat) -> Nat:
  match xs:
    case []:
      n
    case _ <> rest:
      Len.tris(rest, Nat.add(n, 1n))


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


type Tally is Data:
  Tally{nodes: Nat, inc: Nat, leaves: Nat, linc: Nat, maxn: Nat}


def Tally.node(+t: Tally, +n: Nat) -> Tally:
  Tally{nodes, inc, leaves, linc, maxn} = t
  Tally{Nat.add(nodes, 1n), Nat.add(inc, n), leaves, linc,
    Bigger.max(U32.is_gt(U32.from_nat(n), U32.from_nat(maxn)), n, maxn)}


def Tally.leaf(+t: Tally, +n: Nat) -> Tally:
  Tally{nodes, inc, leaves, linc, maxn} = t
  Tally{Nat.add(nodes, 1n), Nat.add(inc, n), Nat.add(leaves, 1n),
    Nat.add(linc, n),
    Bigger.max(U32.is_gt(U32.from_nat(n), U32.from_nat(maxn)), n, maxn)}


def Main.walk(+d: Nat, +x: U32, +y: U32, +size: U32, +tris: List<&2, Rt.Tri>,
  +t: Tally) -> Tally:
  match d:
    case 0n:
      Tally.leaf(t, Len.tris(tris, 0n))
    case 1n+k:
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
      +t1 = Tally.node(t, Len.tris(tris, 0n))
      Main.walk(k, x1, y1, h, Raster.Tri.keep(tris, mx, my, rx, ry, []),
        Main.walk(k, x, y1, h, Raster.Tri.keep(tris, lx, my, mx, ry, []),
          Main.walk(k, x1, y, h, Raster.Tri.keep(tris, mx, ly, rx, my, []),
            Main.walk(k, x, y, h, Raster.Tri.keep(tris, lx, ly, mx, my, []),
              t1))))


def Main.scene(+s: F32) -> List<&2, Geo.WTri>:
  +cars = Carriage.Carriage.cars()
  List.append(&2, Geo.WTri,
    List.append(&2, Geo.WTri, World.World.emit(s, []), Inst.Inst.emit(s, [])),
    Carriage.Carriage.all(s, cars, []))


def Main.show(+d: Nat, +g: Nat, +t: Tally) -> String:
  Tally{nodes, inc, leaves, linc, maxn} = t
  "depth " ++ Nat.show(d) ++ " tris=" ++ Nat.show(g)
    ++ " nodes=" ++ Nat.show(nodes) ++ " sum|node|=" ++ Nat.show(inc)
    ++ " leaves=" ++ Nat.show(leaves) ++ " sum|leaf|=" ++ Nat.show(linc)
    ++ " keepsteps=" ++ Nat.show(Nat.mul(inc, 4n)) ++ " maxleaf="
    ++ Nat.show(maxn) ++ "\n"


def Main.go(+d: Nat, +s: F32) -> String:
  +w = U32.shln(1, d)
  +cam = Rt.VCam.ride(w, w, s, 4.6, 3.05, Ride.Ride.yaw(s, 0.0, False{}),
    (0.0 - 0.02 : F32))
  +ws = Main.scene(s)
  +tris = Rt.Tri.emit(ws, cam)
  +t = Main.walk(Raster.Nat.tile.levels(d), 0, 0, w, tris, Tally{0n, 0n, 0n, 0n, 0n})
  Main.show(d, Len.geo(ws, 0n), t)


def Main.run() -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 9)
    +s : F32 = 110.0
    IO.print(Main.go(U32.to_nat(depth), s))


def main() -> IO(Unit):
  Main.run()
