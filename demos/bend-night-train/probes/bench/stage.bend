# stage: where a frame's time goes, one stage at a time.
#
# A frame is three jobs: build the geometry, project it into the tile tree, and
# shade a pixel per pixel.  Only the last one grows with the frame's depth, so
# timing a run with the geometry switched off separates the fixed cost from the
# per-pixel one.  NT_STAGE picks how much scene is built:
#
#   0  the whole scene            (world + instanced + consist)
#   1  no consist
#   2  world only
#   3  nothing: sky and stars over an empty tile tree
#
# Prints the digest, so a stage that silently renders nothing is visible.
import Base
import ../../src/color.bend as Color
import ../../src/geo.bend as Geo
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


def Main.env.f32.maybe(m: Maybe<&2, F32>, +dflt: F32) -> IO(F32):
  match m:
    case None{}:
      IO.pure(F32, dflt)
    case Some{v}:
      IO.pure(F32, v)


def Main.env.f32.pick(r: Result<&1, &1, U32 & String, String>, +dflt: F32)
  -> IO(F32):
  match r:
    case Fail{e}:
      IO.pure(F32, dflt)
    case Done{value}:
      Main.env.f32.maybe(F32.read(value), dflt)


def Main.env.f32(name: String, +dflt: F32) -> IO(F32):
  do IO<F32>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    Main.env.f32.pick(r, dflt)


def Main.scene(stage: U32, +s: F32) -> List<&2, Geo.WTri>:
  match stage:
    case 0:
      +cars = Carriage.Carriage.cars()
      a b c = World.World.track(s, []) Inst.Inst.emit(s, []) Carriage.Carriage.all(s, cars, [])
      List.append(&2, Geo.WTri, List.append(&2, Geo.WTri, a, b), c)
    case 1:
      a b = World.World.track(s, []) Inst.Inst.emit(s, [])
      List.append(&2, Geo.WTri, a, b)
    case 2:
      World.World.track(s, [])
    case _:
      []


# The ground is the one part of the world Raster.frame culls, so it travels on
# its own list.  Stages 0-2 are the ones that build the world.
def Main.ground(stage: U32, +s: F32) -> List<&2, Geo.WTri>:
  match stage:
    case 0:
      World.World.ground(s, [])
    case 1:
      World.World.ground(s, [])
    case 2:
      World.World.ground(s, [])
    case _:
      []


# Stage 4: the same whole scene, but kept as a chunk list end to end -- the
# three generators are independent, so their chunk lists are built in parallel
# and concatenated into the track, instanced and carriage chunks, and the
# projection later splits the 24 chunks itself once the ground's four come
# alongside from Main.ground.chunks.  The other stages build the serial soup
# and go through Raster.frame.
def Main.chunks(stage: U32, +s: F32) -> List<&2, List<&2, Geo.WTri>>:
  match stage:
    case 4:
      w i c = World.World.chunks(s) Inst.Inst.chunks(s)
        Carriage.Carriage.chunks(s, Carriage.Carriage.cars())
      List.concat(&2, List<&2, Geo.WTri>, [w, i, c])
    case _:
      []


def Main.ground.chunks(stage: U32, +s: F32) -> List<&2, List<&2, Geo.WTri>>:
  match stage:
    case 4:
      World.World.ground.chunks(s)
    case _:
      []


# A match can only scrutinise a parameter, so the stage's choice of frame entry
# point is passed in as a Bool; only the selected branch is evaluated.  The
# unselected scene list is the empty one the other generator returns for this
# stage, so no work is done twice.
def Main.frame.pick(chunked: Bool, +d: Nat, +s: F32, +side: F32, +hgt: F32,
  +yaw: F32, +pitch: F32, +gcs: List<&2, List<&2, Geo.WTri>>,
  +cs: List<&2, List<&2, Geo.WTri>>, +gs: List<&2, Geo.WTri>,
  +ws: List<&2, Geo.WTri>, +lts: Shade.Lights, +t: F32, +head: Bool)
  -> Raster.Frame:
  match chunked:
    case True{}:
      Raster.Raster.frame.chunks(d, s, side, hgt, yaw, pitch, gcs, cs, lts, [],
        t, head)
    case False{}:
      Raster.Raster.frame(d, s, side, hgt, yaw, pitch, gs, ws, lts, [], t, head)


def Main.run() -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 10)
    stage : U32 <- Main.env.u32("NT_STAGE", 0)
    s0 : F32 <- Main.env.f32("NT_S", 110.0)
    t0 : F32 <- Main.env.f32("NT_T", 0.0)
    +s : F32 = s0
    +t : F32 = t0
    +stg : U32 = stage
    +d : Nat = U32.to_nat(depth)
    +mo : Bool = True{}
    +is4 : Bool = U32.is_eq(stg, 4)
    +side : F32 = Ride.Ride.side(t, mo)
    +yaw : F32 = Ride.Ride.yaw(s, t, mo)
    +pitch : F32 = Ride.Ride.pitch(t, mo)
    +ws : List<&2, Geo.WTri> = Main.scene(stg, s)
    +gs : List<&2, Geo.WTri> = Main.ground(stg, s)
    +cs : List<&2, List<&2, Geo.WTri>> = Main.chunks(stg, s)
    +gcs : List<&2, List<&2, Geo.WTri>> = Main.ground.chunks(stg, s)
    +lts : Shade.Lights = Ride.Ride.lights(s)
    +fr : Raster.Frame = Main.frame.pick(is4, d, s, side, Ride.Ride.hgt(t, mo),
      yaw, pitch, gcs, cs, gs, ws, lts, t, True{})
    IO.print(U32.show(Raster.Raster.digest(d, fr)) ++ "\n")


def main() -> IO(Unit):
  Main.run()
