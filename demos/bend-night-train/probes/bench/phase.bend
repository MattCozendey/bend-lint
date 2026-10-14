# phase: split one frame's time into its three sequential phases.
#
# The renderer is three jobs with very different parallel shapes: the scene
# generators run before the renderer is entered at all, the projection is one
# pass over the whole soup, and the tile tree is the only part that is written
# as a parallel recursion.  Timing the whole frame cannot say which of the
# three refuses to scale, so each phase is forced on its own and the wall clock
# is read off the process.
#
#   0  the scene generators only          (fold the world-space soup)
#   1  scene generators + projection      (fold the screen-space soup)
#   2  the whole frame                    (the renderer's digest)
#
# The folds are pure sums: they force every vertex without shading anything.
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


def Main.sum.geo(ts: List<&2, Geo.WTri>, +acc: F32) -> F32:
  match ts:
    case []:
      acc
    case t <> rest:
      Geo.WTri{a, b, c} = t
      Geo.WVtx{+ax, ay, az, nx, ny, nz, ac, ad, ae, af} = a
      Main.sum.geo(rest, (((((acc + ax) + ay) + az) + ac) : F32))


def Main.sum.rt(ts: List<&2, Rt.Tri>, +acc: F32) -> F32:
  match ts:
    case []:
      acc
    case t <> rest:
      Rt.Tri{a, b, c, bx0, by0, bx1, by1} = t
      Rt.Vtx{at1, +sx, sy, iw} = a
      Main.sum.rt(rest, ((acc + sx) + iw : F32))


def Main.scene(+s: F32) -> List<&2, Geo.WTri>:
  +cars = Carriage.Carriage.cars()
  List.append(&2, Geo.WTri,
    List.append(&2, Geo.WTri, World.World.emit(s, []), Inst.Inst.emit(s, [])),
    Carriage.Carriage.all(s, cars, []))


# Only the selected phase is built: the other two arms are never forced, so the
# number printed is that phase's own cost and not the sum of all three.
def Main.phase(+ph: U32, +d: Nat, +s: F32, +ws: List<&2, Geo.WTri>,
  +cam: Rt.VCam) -> F32:
  match ph:
    case 0:
      Main.sum.geo(ws, 0.0)
    case 1:
      Main.sum.rt(Rt.Tri.emit(ws, cam), 0.0)
    case _:
      U32.to_f32(Raster.Raster.digest(d,
        Raster.Raster.frame(d, s, 4.6, 3.05, Ride.Ride.yaw(s, 0.0, False{}),
          (0.0 - 0.02 : F32), [], ws, Ride.Ride.lights(s), [], 0.0, True{})))


def Main.go(+ph: U32, +d: Nat, +s: F32) -> F32:
  +w = U32.shln(1, d)
  +cam = Rt.VCam.ride(w, w, s, 4.6, 3.05, Ride.Ride.yaw(s, 0.0, False{}),
    (0.0 - 0.02 : F32))
  Main.phase(ph, d, s, Main.scene(s), cam)


def Main.run() -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 9)
    ph : U32 <- Main.env.u32("NT_PHASE", 2)
    +s : F32 = 110.0
    IO.print(F32.show(Main.go(ph, U32.to_nat(depth), s)) ++ "\n")


def main() -> IO(Unit):
  Main.run()
