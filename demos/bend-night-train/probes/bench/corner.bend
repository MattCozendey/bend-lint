# corner: what is in the top-left leaf's triangle list.
#
# The leaf at the frame's top-left corner holds 104,363 of the scene's 164,622
# triangles -- more than half the scene, in one 8x8 tile, which is 36% of the
# whole per-pixel pass.  The corner is empty sky, so either those triangles
# really reach it, or only their screen bounding boxes do.  This counts both,
# and how far the boxes run.
#
# The filter is an intersection test, so filtering straight to the leaf's box
# gives the list the tree would hand that leaf: keep(keep(ts, [0,16]), [0,8])
# == keep(ts, [0,8]).
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


type Stat is Data:
  Stat{n: Nat, off: Nat, wide: Nat, hits: Nat, maxext: F32, maxw: F32}


def Bigger.nat(yes: Bool, +a: Nat, +b: Nat) -> Nat:
  match yes:
    case True{}:
      a
    case False{}:
      b


def Bigger.f32(yes: Bool, +a: F32, +b: F32) -> F32:
  match yes:
    case True{}:
      a
    case False{}:
      b


def Main.covers.hit(h: Raster.Hit) -> Bool:
  match h:
    case Raster.Miss{}:
      False{}
    case Raster.Hit{q1, q2, q3, hiw}:
      True{}


def Main.covers(+fx: F32, +fy: F32, +ax: F32, +ay: F32, +aiw: F32, +bx: F32,
  +by: F32, +biw: F32, +cx: F32, +cy: F32, +ciw: F32) -> Bool:
  Main.covers.hit(Raster.Tri.hit(fx, fy, ax, ay, aiw, bx, by, biw, cx, cy, ciw))


def Main.take(+s: Stat, t: Rt.Tri, +w: F32, +fx: F32, +fy: F32) -> Stat:
  Stat{n, off, wide, hits, maxext, maxw} = s
  Rt.Tri{a, b, c, +bx0, +by0, +bx1, +by1} = t
  Rt.Vtx{at1, +sx1, +sy1, +iw1} = a
  Rt.Vtx{at2, +sx2, +sy2, +iw2} = b
  Rt.Vtx{at3, +sx3, +sy3, +iw3} = c
  +ext = F32.max(F32.max(F32.abs(bx0), F32.abs(bx1)),
    F32.max(F32.abs(by0), F32.abs(by1)))
  +bw = F32.sub(bx1, bx0)
  +leaves = Bool.or(F32.is_lt(bx0, 0.0),
    Bool.or(F32.is_gt(bx1, w), Bool.or(F32.is_lt(by0, 0.0), F32.is_gt(by1, w))))
  +huge = F32.is_gt(bw, 1000.0)
  Stat{Nat.add(n, 1n), Bigger.nat(leaves, Nat.add(off, 1n), off),
    Bigger.nat(huge, Nat.add(wide, 1n), wide),
    Bigger.nat(Main.covers(fx, fy, sx1, sy1, iw1, sx2, sy2, iw2, sx3, sy3, iw3),
      Nat.add(hits, 1n), hits),
    Bigger.f32(F32.is_gt(ext, maxext), ext, maxext),
    Bigger.f32(F32.is_gt(bw, maxw), bw, maxw)}


def Main.go(ts: List<&2, Rt.Tri>, +s: Stat, +w: F32, +fx: F32, +fy: F32) -> Stat:
  match ts:
    case []:
      s
    case t <> rest:
      Main.go(rest, Main.take(s, t, w, fx, fy), w, fx, fy)


def Main.count(ts: List<&2, Rt.Tri>, +n: Nat) -> Nat:
  match ts:
    case []:
      n
    case _ <> rest:
      Main.count(rest, Nat.add(n, 1n))


def Main.show(+s: Stat) -> String:
  Stat{n, off, wide, hits, maxext, maxw} = s
  "corner tris=" ++ Nat.show(n) ++ " box-off-frame=" ++ Nat.show(off)
    ++ " box>1000px=" ++ Nat.show(wide) ++ " cover(4.5,4.5)=" ++ Nat.show(hits)
    ++ " maxExtent=" ++ F32.show(maxext) ++ " maxWidth=" ++ F32.show(maxw)
    ++ "\n"


def Main.scene(+s: F32) -> List<&2, Geo.WTri>:
  +cars = Carriage.Carriage.cars()
  List.append(&2, Geo.WTri,
    List.append(&2, Geo.WTri, World.World.emit(s, []), Inst.Inst.emit(s, [])),
    Carriage.Carriage.all(s, cars, []))


def Main.go.depth(+d: Nat, +s: F32) -> String:
  +w = U32.shln(1, d)
  +cam = Rt.VCam.ride(w, w, s, 4.6, 3.05, Ride.Ride.yaw(s, 0.0, False{}),
    (0.0 - 0.02 : F32))
  +fw = U32.to_f32(w)
  +tris = Rt.Tri.emit(Main.scene(s), cam)
  +leaf = Raster.Tri.keep(tris, 0.0, 0.0, 8.0, 8.0, [])
  "all=" ++ Nat.show(Main.count(tris, 0n)) ++ " "
    ++ Main.show(Main.go(leaf, Stat{0n, 0n, 0n, 0n, 0.0, 0.0}, fw, 4.5, 4.5))


def Main.run() -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 9)
    +s : F32 = 110.0
    IO.print(Main.go.depth(U32.to_nat(depth), s))


def main() -> IO(Unit):
  Main.run()
