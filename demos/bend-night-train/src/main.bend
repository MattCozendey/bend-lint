# Main: the headless driver.
#
# Everything visual lives elsewhere -- the frame is a quadtree of tiles
# (raster.bend), the scene is built from the world/inst/carriage meshes, and
# the camera is ride.bend.  This module is the outside of that: take the
# frame's parameters from the environment, build the scene, run the renderer,
# print a digest, write a PPM.
#
# The image is written one row per File.write because the writer appends at the
# current offset (probed, not assumed).  Building the whole PPM as one string
# and writing it once would cost the square of the image: every row appended
# copies everything already there, which for 1024x1024 is gigabytes.
import Base
import ./color.bend as Color
import ./geo.bend as Geo
import ./raster.bend as Raster
import ./ride.bend as Ride
import ./shade.bend as Shade
import ./world.bend as World
import ./inst.bend as Inst
import ./carriage.bend as Carriage


# ---- environment -----------------------------------------------------
# One binary renders any frame at any size: recompiling between benchmark runs
# would put the compiler in the timing.
#
# Every let inside a `do` block carries its type: `+x = f(y)` alone fails to
# parse there, while `+x : T = f(y)` is accepted and is what the old driver
# (and this one) writes.
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


# An unset variable is None rather than a default, so the driver can tell "the
# caller wants the demo's own value" from "the caller pinned this one".
def Main.env.f32.opt.pick(r: Result<&1, &1, U32 & String, String>)
  -> IO(Maybe<&2, F32>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<&2, F32>, None{})
    case Done{value}:
      IO.pure(Maybe<&2, F32>, F32.read(value))


def Main.env.f32.opt(name: String) -> IO(Maybe<&2, F32>):
  do IO<Maybe<&2, F32>>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    Main.env.f32.opt.pick(r)


def Main.f32.or.else(m: Maybe<&2, F32>, +dflt: F32) -> F32:
  match m:
    case None{}:
      dflt
    case Some{v}:
      v


# ---- writing ---------------------------------------------------------
# File.write hands back the handle beside a Result, so the two are unpacked in
# a def of their own: a destructuring let is not a statement in a do block.
def Main.err.out(f: File) -> IO(File):
  do IO<File>:
    IO.print_err("bend-night-train: write failed\n")
    IO.pure(File, f)


def Main.wrote.r(f: File, r: Result<&1, &1, U32 & String, Unit>) -> IO(File):
  match r:
    case Fail{e}:
      Main.err.out(f)
    case Done{value}:
      IO.pure(File, f)


def Main.file.of(fr: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  (f, r) = fr
  Main.wrote.r(f, r)


# The countdown writes the image's top row first: the tree's `y` grows
# downward from the top of the screen, so row y is (width - 1) - k.
def Main.rows(+i: Nat, +d: Nat, +w: U32, +fr: Raster.Frame, f: File)
  -> IO(Unit):
  match i:
    case 0n:
      File.close(f)
    case 1n+k:
      do IO<Unit>:
        fr2 : File & Result<&1, &1, U32 & String, Unit> <-
          File.write(f, Raster.Raster.text.row(d, fr,
            U32.sub(U32.sub(w, 1), U32.from_nat(k))))
        g : File <- Main.file.of(fr2)
        Main.rows(k, d, w, fr, g)


def Main.header(f: File, +w: U32, +d: Nat, +fr: Raster.Frame) -> IO(Unit):
  do IO<Unit>:
    fr2 : File & Result<&1, &1, U32 & String, Unit> <-
      File.write(f, "P3\n" ++ U32.show(w) ++ " " ++ U32.show(w) ++ "\n255\n")
    g : File <- Main.file.of(fr2)
    Main.rows(U32.to_nat(w), d, w, fr, g)


# The open is its own def, and the width is computed at the call: a do block
# inside a match arm does not parse, and a do block wants a bind before a let.
def Main.save(+d: Nat, +fr: Raster.Frame, path: String, +w: U32) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    Main.header(f, w, d, fr)


def Main.save.maybe(write: Bool, +d: Nat, +fr: Raster.Frame, path: String)
  -> IO(Unit):
  match write:
    case True{}:
      Main.save(d, fr, path, U32.shln(1, d))
    case False{}:
      IO.pure(Unit, Unit{})


# ---- the scene -------------------------------------------------------
# The world comes back in two soups, and the split is the reference's own: its
# ground is a sheet wound face-down, so WebGL culls it and the demo's lower
# half is the sky's haze rather than grass.  The rasteriser culls it too, which
# it can only do where the camera is known -- so the ground travels on its own
# until Raster.frame.  The track is not in it: the demo draws the track with
# culling disabled, so both of its faces are wanted.
def Main.ground(+s: F32) -> List<&2, Geo.WTri>:
  World.World.ground(s, [])


# The rest of the world: the track on top of the ballast, the instanced
# scenery, then the consist.  The consist is built once, not once per car:
# `cars()` rebuilds the four carriage meshes every call.
def Main.tris(+s: F32) -> List<&2, Geo.WTri>:
  +cars = Carriage.Carriage.cars()
  a b c = World.World.track(s, []) Inst.Inst.emit(s, [])
    Carriage.Carriage.all(s, cars, [])
  List.append(&2, Geo.WTri, List.append(&2, Geo.WTri, a, b), c)


# The same scene, as the chunk list the chunked driver wants: the track's four
# ribbons, the eleven instanced kinds, the consist's five runs.  Each piece is
# built by its own branch of the fork, and the three groups are concatenated in
# the order Main.tris concatenates its soups, so the flattened chunks are the
# serial triangle list triangle for triangle.
def Main.tris.chunks(+s: F32) -> List<&2, List<&2, Geo.WTri>>:
  +cars = Carriage.Carriage.cars()
  a b c = World.World.chunks(s) Inst.Inst.chunks(s)
    Carriage.Carriage.chunks(s, cars)
  List.concat(&2, List<&2, Geo.WTri>, [a, b, c])


def Main.ground.chunks(+s: F32) -> List<&2, List<&2, Geo.WTri>>:
  World.World.ground.chunks(s)


# ---- the live view ---------------------------------------------------
# The demo's own ride, one frame per call, written to stdout as a P3 PPM with
# no separator between frames.  That is the stream ffplay's image2pipe demuxer
# reads, so the renderer can be watched while it runs:
#
#   NT_MS=0 NT_FRAMES=300 NT_STEP=33 ./out/night-train --threads 24 \
#     | ffplay -f image2pipe -framerate 30 -i -
#
# The frame's time is given in milliseconds and `s` advances at the reference's
# own 24.5 m/s (its "Обычная" speed), so a driver that feeds the wall clock
# gets the train at its real speed and a driver that feeds a fixed step gets a
# clip that plays back at that step.  tools/live.sh does the first and
# tools/clip.sh the second.
# The camera is the demo's own ride, but the same pinning the still comparison
# uses (NT_YAW/NT_PITCH/NT_MOTION) applies here too: with the head pinned the
# clip is comparable frame for frame with the reference's.
def View.frame.at(+ms: U32, +d: Nat, +s0: F32, +head: Bool, +mo: Bool,
  +yaw0: Maybe<&2, F32>, +pitch0: Maybe<&2, F32>) -> Raster.Frame:
  # a def body, unlike a do block, wants its bindings without a type annotation
  +t = (U32.to_f32(ms) * 0.001 : F32)
  +s = (s0 + 24.5 * t : F32)
  +yaw = Main.f32.or.else(yaw0, Ride.Ride.yaw(s, t, mo))
  +pitch = Main.f32.or.else(pitch0, Ride.Ride.pitch(t, mo))
  Raster.Raster.frame.chunks(d, s, Ride.Ride.side(t, mo),
    Ride.Ride.hgt(t, mo), yaw, pitch, Main.ground.chunks(s), Main.tris.chunks(s),
    Ride.Ride.lights(s), [], t, head)


# One frame's rows, top row first: the tree's `y` grows downward from the top
# of the screen, so row y is (width - 1) - k.
def View.rows(+i: Nat, +d: Nat, +w: U32, +fr: Raster.Frame) -> IO(Unit):
  match i:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        Raster.Raster.emit.row(d, fr, U32.sub(U32.sub(w, 1), U32.from_nat(k)))
        View.rows(k, d, w, fr)


def View.go(+i: Nat, +ms: U32, +step: U32, +d: Nat, +s0: F32, +head: Bool,
  +mo: Bool, +yaw0: Maybe<&2, F32>, +pitch0: Maybe<&2, F32>) -> IO(Unit):
  match i:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        +w : U32 = U32.shln(1, d)
        +fr : Raster.Frame = View.frame.at(ms, d, s0, head, mo, yaw0, pitch0)
        IO.write("P3\n" ++ U32.show(w) ++ " " ++ U32.show(w) ++ "\n255\n")
        View.rows(U32.to_nat(w), d, w, fr)
        View.go(k, U32.add(ms, step), step, d, s0, head, mo, yaw0, pitch0)


def View.run() -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 9)
    frames : U32 <- Main.env.u32("NT_FRAMES", 60)
    first : U32 <- Main.env.u32("NT_MS", 0)
    step : U32 <- Main.env.u32("NT_STEP", 33)
    s0 : F32 <- Main.env.f32("NT_S", 110.0)
    head : U32 <- Main.env.u32("NT_HEAD", 1)
    motion : U32 <- Main.env.u32("NT_MOTION", 1)
    yaw0 : Maybe<&2, F32> <- Main.env.f32.opt("NT_YAW")
    pitch0 : Maybe<&2, F32> <- Main.env.f32.opt("NT_PITCH")
    View.go(U32.to_nat(frames), first, step, U32.to_nat(depth), s0,
      U32.is_eq(head, 1), U32.is_eq(motion, 1), yaw0, pitch0)


# ---- driver ----------------------------------------------------------
def Main.frame(+path: String) -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 10)
    ppm : U32 <- Main.env.u32("NT_PPM", 1)
    s0 : F32 <- Main.env.f32("NT_S", 110.0)
    t0 : F32 <- Main.env.f32("NT_T", 0.0)
    head : U32 <- Main.env.u32("NT_HEAD", 1)
    motion : U32 <- Main.env.u32("NT_MOTION", 1)
    yaw0 : Maybe<&2, F32> <- Main.env.f32.opt("NT_YAW")
    pitch0 : Maybe<&2, F32> <- Main.env.f32.opt("NT_PITCH")
    # a value bound by `<-` is linear, so the two that are read more than once
    # are duplicated into a `+` binder before use
    +s : F32 = s0
    +t : F32 = t0
    +mo : Bool = U32.is_eq(motion, 1)
    +d : Nat = U32.to_nat(depth)
    +side : F32 = Ride.Ride.side(t, mo)
    # NT_YAW/NT_PITCH pin the head; without them the demo's auto-look decides
    # the yaw and the converged pitch (0.012) is used.
    +yaw : F32 = Main.f32.or.else(yaw0, Ride.Ride.yaw(s, t, mo))
    +pitch : F32 = Main.f32.or.else(pitch0, Ride.Ride.pitch(t, mo))
    +gcs : List<&2, List<&2, Geo.WTri>> = Main.ground.chunks(s)
    +wcs : List<&2, List<&2, Geo.WTri>> = Main.tris.chunks(s)
    +lts : Shade.Lights = Ride.Ride.lights(s)
    +fr : Raster.Frame = Raster.Raster.frame.chunks(d, s, side,
      Ride.Ride.hgt(t, mo), yaw, pitch, gcs, wcs, lts, [], t,
      U32.is_eq(head, 1))
    IO.print(U32.show(Raster.Raster.digest(d, fr)) ++ "\n")
    Main.save.maybe(U32.is_eq(ppm, 1), d, fr, path)


def Main.pick.view(view: Bool, path: String) -> IO(Unit):
  match view:
    case True{}:
      View.run()
    case False{}:
      Main.frame(path)


def main() -> IO(Unit):
  do IO<Unit>:
    view : U32 <- Main.env.u32("NT_VIEW", 0)
    Main.pick.view(U32.is_eq(view, 1), "out/frame.ppm")
