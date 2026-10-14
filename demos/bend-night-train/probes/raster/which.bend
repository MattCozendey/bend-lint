# which: render the frozen camera with one mesh group at a time.
#
# The left of the frame disagrees with the reference by a whole picture: mine is
# saturated white where the reference is a dark carriage.  The shader was probed
# directly and returns the reference's own values for a hand-made near wall, a
# near window and the ballast, so the defect is in what the renderer feeds the
# shader, not in the shading.  This narrows that down to the geometry: the world,
# the instanced traffic, or the consist is rendered alone and written out.
#
#   NT_STAGE 0 whole scene, 1 world+inst, 2 world only, 3 inst only,
#   4 carriage only, 5 empty
import Base
import ../../src/main.bend as M
import ../../src/geo.bend as Geo
import ../../src/raster.bend as Raster
import ../../src/ride.bend as Ride
import ../../src/shade.bend as Shade
import ../../src/world.bend as World
import ../../src/inst.bend as Inst
import ../../src/carriage.bend as Carriage


def Which.scene(stage: U32, car: U32, +s: F32) -> List<&2, Geo.WTri>:
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
    case 3:
      Inst.Inst.emit(s, [])
    case 4:
      Carriage.Carriage.all(s, Carriage.Carriage.cars(), [])
    case 6:
      Carriage.Carriage.emit(car, s, Carriage.Carriage.cars(), [])
    case _:
      []


def Which.run() -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- M.Main.env.u32("NT_DEPTH", 9)
    stage : U32 <- M.Main.env.u32("NT_STAGE", 0)
    +stg : U32 = stage
    +d : Nat = U32.to_nat(depth)
    +s : F32 = 110.0
    +t : F32 = 0.0
    +mo : Bool = False{}
    cars : U32 <- M.Main.env.u32("NT_CAR", 5)
    +ws : List<&2, Geo.WTri> = Which.scene(stg, cars, s)
    +lts : Shade.Lights = Ride.Ride.lights(s)
    +fr : Raster.Frame = Raster.Raster.frame(d, s, Ride.Ride.side(t, mo),
      Ride.Ride.hgt(t, mo), 0.0, (0.0 - 0.02 : F32), [], ws, lts, [], t, True{})
    IO.print(U32.show(Raster.Raster.digest(d, fr)) ++ "\n")
    M.Main.save.maybe(True{}, d, fr, "out/probe.ppm")


def main() -> IO(Unit):
  Which.run()
