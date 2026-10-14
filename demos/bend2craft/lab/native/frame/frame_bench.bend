import Base
import ../../../world/player.bend as Player
import ../../../world/world.bend as World
import ../../../native/voxel.bend as Voxel
import ../../../native/player.bend as PlayerProbe
import ../../../native/frame.bend as Probe

# ---------------------------------------------------------------------------
# The frame cost
#
# One frame is: the tick's events, the player transition through `Player.step`
# against a cached 2x2 collision region, the camera rebuilt from the resulting eye
# and yaw through the voxel probe's `Camera.look`, the render through the voxel
# probe's `render_size_at`, and the image fingerprint. Nothing here reimplements
# physics, camera or rendering; the only thing this file owns is the clock.
#
# Every timed phase wraps its workload in `IO.now` and places a forcing `IO.print`
# of the folded digest inside the timed region, so no phase can be dropped as dead
# code. `phase=clock` measures what that harness costs on its own, because at
# 0.2 ms a stage the clock's millisecond resolution is part of the answer.
# ---------------------------------------------------------------------------
def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

def region_of(value: Maybe<&1, PlayerProbe.Region>) -> IO(PlayerProbe.Region):
  match value:
    case Some{region}:
      IO.pure(PlayerProbe.Region, region)
    case None{}:
      IO.die(PlayerProbe.Region, 1, "frame-probe-bench: the benchmark region was refused")


# A phase's fold answers a hash and a render count as a pair. A product cannot be
# shared, so the `do` bind is consumed once and each projection takes the pair as
# its own parameter.



# A phase's fold answers a hash and a render count together. A product cannot be
# shared, so the pair is read through one def and the two projections are read from
# the record it builds.

type Folded is Data:
  Folded{hash: U32, renders: U32}

def folded_of(pair: U32 & U32) -> Folded:
  (hash, renders) = pair
  Folded{hash, renders}

def folded_hash(+f: Folded) -> U32:
  Folded{+hash, +renders} = f
  hash

def folded_renders(+f: Folded) -> U32:
  Folded{+hash, +renders} = f
  renders

def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "frame-probe-bench: " ++ message)

def size_of(depth: Nat) -> U32:
  U32.shln(1, depth)

def phase_line(name: String, +size: U32, +iterations: Nat, started: Nat,
  finished: Nat, +digest: U32) -> String:
  "phase=" ++ name ++ " size=" ++ U32.show(size) ++ " iterations="
    ++ Nat.show(iterations) ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
    ++ " digest=" ++ U32.show(digest)

# ---------------------------------------------------------------------------
# Folds
#
# A fold is N repetitions of one stage. The stage's output is folded into a hash,
# so the loop cannot be optimized away, and the hash is what the forcing print
# inside the timed region prints.
# ---------------------------------------------------------------------------
def clock.go(remaining: Nat, +total: U32, +hash: U32) -> IO(U32):
  match remaining:
    case 0n:
      IO.pure(U32, total)
    case 1n+p:
      do IO<U32>:
        +started : Nat <- IO.now()
        consumed : Unit <- IO.print("consume=clock:" ++ U32.show(hash))
        finished : Nat <- IO.now()
        clock.go(p, U32.add(total, U32.from_nat(Nat.sub(finished, started))),
          U32.add(hash, 1))

def input.go(remaining: Nat, +events: List<&2, Event>, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      input.go(p, events, fold_hash(hash, Probe.keys_mask(Probe.input(events))))

def tick.go(remaining: Nat, +state: Player.State, +region: PlayerProbe.Region,
  +events: List<&2, Event>, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      tick.go(p, Probe.tick(Probe.ready(state, events), Probe.tick_dt(), region), region,
        events, fold_hash(hash, F32.to_u32(F32.abs(Probe.player_x(state)))))

# The camera stage. The eye walks forward one tick's worth of motion per
# iteration, because a camera that never moves is a camera the compiler can fold.

def camera_read(+pose: Probe.Pose) -> U32:
  +eye : Voxel.Vec = Probe.eye_of(pose)
  U32.add(U32.add(F32.to_u32(F32.abs(Probe.eye_x(eye))),
    F32.to_u32(F32.abs(Probe.eye_y(eye)))),
    F32.to_u32(F32.abs(Probe.eye_z(eye))))

# The image build alone. Each image is handed to `Image.drop`, which consumes the
# whole quadtree, so the construction cannot be elided; the `drop` phase below
# measures what that release costs on its own, so the difference between the two
# ways of reading this is a measurement rather than a guess.

def release_and_count(+hash: U32, image: Image) -> U32:
  released : Unit = Image.drop(image)
  U32.add(hash, 1)

def render.go(remaining: Nat, +grid: Voxel.VoxelGrid, +camera: Voxel.Camera,
  +depth: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      render.go(p, grid, camera, depth,
        release_and_count(hash, Probe.render(grid, camera, depth)))

# The image build and the fold that reads it back, which is what a frame pays.

def paint.go(remaining: Nat, +grid: Voxel.VoxelGrid, +camera: Voxel.Camera,
  +depth: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      paint.go(p, grid, camera, depth,
        fold_hash(hash, Probe.fingerprint(Probe.render(grid, camera, depth))))

# A list of images built before the timed region, so the fingerprint and the
# release can be timed on their own. `Image` is affine, so the list holds each
# image exactly once.

def image_list.go(remaining: Nat, +grid: Voxel.VoxelGrid, +camera: Voxel.Camera,
  +depth: Nat) -> List<Image>:
  match remaining:
    case 0n:
      []
    case 1n+p:
      Probe.render(grid, camera, depth) <> image_list.go(p, grid, camera, depth)

def fingerprint.go(images: List<Image>, +hash: U32) -> U32:
  match images:
    case Nil{}:
      hash
    case image <> rest:
      fingerprint.go(rest, fold_hash(hash, Probe.fingerprint(image)))

def release.go(images: List<Image>, +hash: U32) -> U32:
  match images:
    case Nil{}:
      hash
    case image <> rest:
      release.go(rest, release_and_count(hash, image))

# ---------------------------------------------------------------------------
# The frame, as a fold
#
# `force` is the rendering policy: `True{}` redraws every tick, `False{}` redraws
# only when the pose moved. Both run the same input, the same tick and the same
# camera, so the only difference between their numbers is the render.
# ---------------------------------------------------------------------------
def frame.go(remaining: Nat, +state: Player.State, +events: List<&2, Event>,
  +region: PlayerProbe.Region, +grid: Voxel.VoxelGrid, +depth: Nat,
  +origin_x: Nat, +origin_z: Nat, +pose: Probe.Pose, +digest: U32,
  +hash: U32, +renders: U32, +force: Bool) -> U32 & U32:
  match remaining:
    case 0n:
      (hash, renders)
    case 1n+p:
      +next : Probe.Frame = Probe.frame(state, events, Probe.tick_dt(), region, grid,
        depth, origin_x, origin_z, pose, digest, force)
      +shown : Probe.Carried = Probe.carry(next)
      +drawn : U32 = Probe.draws_of(next)
      frame.go(p, Probe.carried_player(shown), events, region, grid, depth, origin_x,
        origin_z, Probe.carried_pose(shown), Probe.carried_digest(shown),
        fold_hash(hash, Probe.carried_digest(shown)), U32.add(renders, drawn), force)

def rebuild.go(remaining: Nat, +state: Player.State, +events: List<&2, Event>,
  +region: PlayerProbe.Region, +depth: Nat, +origin_x: Nat, +origin_z: Nat,
  +pose: Probe.Pose, +digest: U32, +hash: U32, +force: Bool) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +next : Probe.Frame = Probe.frame_rebuild(state, events, Probe.tick_dt(), region,
        Probe.chunk(), depth, origin_x, origin_z, pose, digest, force)
      +shown : Probe.Carried = Probe.carry(next)
      rebuild.go(p, Probe.carried_player(shown), events, region, depth, origin_x, origin_z,
        Probe.carried_pose(shown), Probe.carried_digest(shown),
        fold_hash(hash, Probe.carried_digest(shown)), force)

def sky.go(remaining: Nat, +state: Player.State, +events: List<&2, Event>,
  +region: PlayerProbe.Region, +depth: Nat, +origin_x: Nat, +origin_z: Nat,
  +pose: Probe.Pose, +digest: U32, +hash: U32, +force: Bool) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +next : Probe.Frame = Probe.frame_sky(state, events, Probe.tick_dt(), region,
        depth, origin_x, origin_z, pose, digest, force)
      +shown : Probe.Carried = Probe.carry(next)
      sky.go(p, Probe.carried_player(shown), events, region, depth, origin_x, origin_z,
        Probe.carried_pose(shown), Probe.carried_digest(shown),
        fold_hash(hash, Probe.carried_digest(shown)), force)

# The one-time cost a client amortizes: the bulk chunk, the nested grid and the
# multi-chunk collision region, all built from scratch. It is an `IO` fold because
# building the region is what refuses a grid the storage encoding cannot name, and
# that refusal is `IO.die`.

def bootstrap.go(remaining: Nat, +hash: U32) -> IO(U32 & U32):
  match remaining:
    case 0n:
      IO.pure(U32 & U32, (hash, 0))
    case 1n+p:
      do IO<U32 & U32>:
        region : PlayerProbe.Region <- region_of(Probe.region())
        +grid : Voxel.VoxelGrid = Probe.grid()
        +probe : U32 = Voxel.grid_at(grid, 8, 8, 8)
        bootstrap.go(p, fold_hash(hash, probe))

# ---------------------------------------------------------------------------
# The pacer
#
# `IO.sleep` takes whole milliseconds, so 60 FPS is targeted as a 16 ms budget and
# the overshoot is measured against 16.67 ms. The sleep is the budget minus what
# the frame actually took, which is what a client has to do.
# ---------------------------------------------------------------------------
# What is left of the frame budget. `ahead` is "this frame started before the
# budget ran out", which is the case that still has time to sleep.
# Milliseconds from now until the frame's deadline. `early` is "the deadline is
# still in front of us", which is the only case that sleeps at all.
def pace_ms.at(early: Bool, +deadline: Nat, now: Nat) -> U32:
  match early:
    case True{}:
      U32.from_nat(Nat.sub(deadline, now))
    case False{}:
      0

def pace_ms(+deadline: Nat, +now: Nat) -> U32:
  pace_ms.at(Nat.is_gt(deadline, now), deadline, now)

def pacer.pause(sleeping: Bool, +deadline: Nat, +now: Nat) -> IO(Unit):
  match sleeping:
    case True{}:
      IO.sleep(pace_ms(deadline, now))
    case False{}:
      IO.pure(Unit, Unit{})

# The achieved interval a client sees, with and without a sleep that targets 60
# FPS. `sky` picks the render the paced frame uses: the sky control is a frame
# that fits the budget, the raycast is one that does not, and the pair is what
# shows that pacing cannot rescue a frame that is already over budget.

def paced.at(sky: Bool, +carried: Probe.Carried, +region: PlayerProbe.Region,
  +grid: Voxel.VoxelGrid, depth: Nat, +origin_x: Nat, +origin_z: Nat) -> Probe.Frame:
  match sky:
    case True{}:
      Probe.frame_sky(Probe.carried_player(carried), Probe.idle_events(),
        Probe.tick_dt(), region, depth, origin_x, origin_z,
        Probe.carried_pose(carried), Probe.carried_digest(carried), True{})
    case False{}:
      Probe.frame(Probe.carried_player(carried), Probe.idle_events(), Probe.tick_dt(),
        region, grid, depth, origin_x, origin_z, Probe.carried_pose(carried),
        Probe.carried_digest(carried), True{})

def paced(sky: Bool, carried: Probe.Carried, +region: PlayerProbe.Region,
  +grid: Voxel.VoxelGrid, depth: Nat, +origin_x: Nat, +origin_z: Nat) -> Probe.Frame:
  paced.at(sky, carried, region, grid, depth, origin_x, origin_z)

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------
def clock_phase(+iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +total : U32 <- clock.go(iterations, 0, 2166136261)
    consumed : Unit <- IO.print("consume=clock:" ++ U32.show(total))
    finished : Nat <- IO.now()
    IO.print(phase_line("clock", 0, iterations, started, finished, total)
      ++ " regions=" ++ U32.show(total))

def input_phase(+iterations: Nat) -> IO(Unit):
  +events : List<&2, Event> = Probe.turn_events()
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = input.go(iterations, events, 2166136261)
    consumed : Unit <- IO.print("consume=input:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("input", 0, iterations, started, finished, digest))

def tick_phase(+iterations: Nat, +state: Player.State,
  +region: PlayerProbe.Region) -> IO(Unit):
  +events : List<&2, Event> = Probe.idle_events()
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = tick.go(iterations, state, region, events, 2166136261)
    consumed : Unit <- IO.print("consume=tick:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("tick", 0, iterations, started, finished, digest))

def render_phase(+depth: Nat, +iterations: Nat, +grid: Voxel.VoxelGrid,
  +camera: Voxel.Camera) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = render.go(iterations, grid, camera, depth, 2166136261)
    consumed : Unit <- IO.print("consume=render:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("render", size_of(depth), iterations, started, finished, digest))

def paint_phase(+depth: Nat, +iterations: Nat, +grid: Voxel.VoxelGrid,
  +camera: Voxel.Camera) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = paint.go(iterations, grid, camera, depth, 2166136261)
    consumed : Unit <- IO.print("consume=paint:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("render_fingerprint", size_of(depth), iterations, started, finished,
      digest))

# The fingerprint and the release, timed over images built before the window, so
# `render_fingerprint - fingerprint` and `render - drop` are two independent
# measurements of the same image construction.

def consume_phase(+depth: Nat, +iterations: Nat, +grid: Voxel.VoxelGrid,
  +camera: Voxel.Camera) -> IO(Unit):
  images : List<Image> = image_list.go(iterations, grid, camera, depth)
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = fingerprint.go(images, 2166136261)
    consumed : Unit <- IO.print("consume=fingerprint:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("fingerprint", size_of(depth), iterations, started, finished, digest))

def pinned_phase(+depth: Nat, +iterations: Nat, +grid: Voxel.VoxelGrid) -> IO(Unit):
  +camera : Voxel.Camera = Voxel.Camera.at(0.0)
  do IO<Unit>:
    started : Nat <- IO.now()
    +hash : U32 = paint.go(iterations, grid, camera, depth, 2166136261)
    consumed : Unit <- IO.print("consume=pinned:" ++ U32.show(hash))
    finished : Nat <- IO.now()
    IO.print(phase_line("render_pinned", size_of(depth), iterations, started, finished,
      hash))

def release_phase(+depth: Nat, +iterations: Nat, +grid: Voxel.VoxelGrid,
  +camera: Voxel.Camera) -> IO(Unit):
  images : List<Image> = image_list.go(iterations, grid, camera, depth)
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = release.go(images, 2166136261)
    consumed : Unit <- IO.print("consume=drop:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("drop", size_of(depth), iterations, started, finished, digest))

def frame_phase(+depth: Nat, +iterations: Nat, +state: Player.State,
  +region: PlayerProbe.Region, +grid: Voxel.VoxelGrid) -> IO(Unit):
  +events : List<&2, Event> = Probe.idle_events()
  +pose : Probe.Pose = Probe.pose(state, Probe.origin_x(), Probe.origin_z())
  do IO<Unit>:
    started : Nat <- IO.now()
    pair : U32 & U32 = frame.go(iterations, state, events, region, grid, depth,
      Probe.origin_x(), Probe.origin_z(), pose, 0, 2166136261, 0, True{})
    +folded : Folded = folded_of(pair)
    +hash : U32 = folded_hash(folded)
    +renders : U32 = folded_renders(folded)
    consumed : Unit <- IO.print("consume=frame:" ++ U32.show(hash))
    finished : Nat <- IO.now()
    IO.print(phase_line("frame", size_of(depth), iterations, started, finished, hash)
      ++ " renders=" ++ U32.show(renders))

def rebuild_phase(+depth: Nat, +iterations: Nat, +state: Player.State,
  +region: PlayerProbe.Region) -> IO(Unit):
  +events : List<&2, Event> = Probe.idle_events()
  +pose : Probe.Pose = Probe.pose(state, Probe.origin_x(), Probe.origin_z())
  do IO<Unit>:
    started : Nat <- IO.now()
    +hash : U32 = rebuild.go(iterations, state, events, region, depth, Probe.origin_x(),
      Probe.origin_z(), pose, 0, 2166136261, True{})
    consumed : Unit <- IO.print("consume=rebuild:" ++ U32.show(hash))
    finished : Nat <- IO.now()
    IO.print(phase_line("frame_rebuild", size_of(depth), iterations, started, finished, hash))

# The dirty frame: input and the player and the dirty test, and no render, because
# the pose did not move. `renders` has to come back 0 or the number is not a dirty
# frame at all.

def dirty_phase(+depth: Nat, +iterations: Nat, +state: Player.State,
  +region: PlayerProbe.Region, +grid: Voxel.VoxelGrid) -> IO(Unit):
  +events : List<&2, Event> = Probe.idle_events()
  +pose : Probe.Pose = Probe.pose(state, Probe.origin_x(), Probe.origin_z())
  do IO<Unit>:
    started : Nat <- IO.now()
    pair : U32 & U32 = frame.go(iterations, state, events, region, grid, depth,
      Probe.origin_x(), Probe.origin_z(), pose, 0, 2166136261, 0, False{})
    +folded : Folded = folded_of(pair)
    +hash : U32 = folded_hash(folded)
    +renders : U32 = folded_renders(folded)
    consumed : Unit <- IO.print("consume=dirty:" ++ U32.show(hash))
    finished : Nat <- IO.now()
    Unit <- require(U32.is_eq(renders, 0),
      "a settled idle frame rendered, so the dirty phase is not a dirty frame")
    IO.print(phase_line("frame_dirty", size_of(depth), iterations, started, finished, hash)
      ++ " renders=" ++ U32.show(renders))

def sky_frame_phase(+depth: Nat, +iterations: Nat, +state: Player.State,
  +region: PlayerProbe.Region) -> IO(Unit):
  +events : List<&2, Event> = Probe.idle_events()
  +pose : Probe.Pose = Probe.pose(state, Probe.origin_x(), Probe.origin_z())
  do IO<Unit>:
    started : Nat <- IO.now()
    +hash : U32 = sky.go(iterations, state, events, region, depth, Probe.origin_x(),
      Probe.origin_z(), pose, 0, 2166136261, True{})
    consumed : Unit <- IO.print("consume=sky:" ++ U32.show(hash))
    finished : Nat <- IO.now()
    IO.print(phase_line("frame_sky", size_of(depth), iterations, started, finished, hash))

def bootstrap_phase(+iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    pair : U32 & U32 <- bootstrap.go(iterations, 2166136261)
    +hash : U32 = folded_hash(folded_of(pair))
    consumed : Unit <- IO.print("consume=bootstrap:" ++ U32.show(hash))
    finished : Nat <- IO.now()
    IO.print(phase_line("bootstrap", 0, iterations, started, finished, hash))

# The achieved interval a client sees, with and without a sleep that targets 60 FPS.

def report_sky_control(solid: Bool) -> IO(Unit):
  require(solid, "the frame equals the sky control, so the render reads no blocks")

def settle_ticks() -> Nat:
  120n

def settle.go(remaining: Nat, +state: Player.State,
  +region: PlayerProbe.Region) -> Player.State:
  match remaining:
    case 0n:
      state
    case 1n+p:
      settle.go(p, Probe.tick(Probe.ready(state, []), Probe.tick_dt(), region), region)

def settle(iterations: Nat, +state: Player.State,
  +region: PlayerProbe.Region) -> Player.State:
  settle.go(iterations, state, region)

def pacer.go(remaining: Nat, +carried: Probe.Carried, +region: PlayerProbe.Region,
  +grid: Voxel.VoxelGrid, +depth: Nat, +origin_x: Nat, +origin_z: Nat,
  +target: Nat, +deadline: Nat, +sleeping: Bool, +sky: Bool) -> IO(Probe.Carried):
  match remaining:
    case 0n:
      IO.pure(Probe.Carried, carried)
    case 1n+p:
      do IO<Probe.Carried>:
        +slot : Nat = Nat.add(deadline, target)
        +now : Nat <- IO.now()
        Unit <- pacer.pause(sleeping, slot, now)
        +frame : Probe.Frame = paced(sky, carried, region, grid, depth, origin_x,
          origin_z)
        pacer.go(p, Probe.carry(frame), region, grid, depth, origin_x, origin_z, target,
          slot, sleeping, sky)

# One paced frame: the whole frame, timed on its own clock rather than as a sum of
# its stages, so the interval reported is the interval a client would see.

def pacer_phase(+name: String, +depth: Nat, +iterations: Nat, +state: Player.State,
  +region: PlayerProbe.Region, +grid: Voxel.VoxelGrid, +sleeping: Bool,
  +sky: Bool) -> IO(Unit):
  +carried : Probe.Carried = Probe.carried_seed(state, Probe.pose(state,
    Probe.origin_x(), Probe.origin_z()))
  +target : Nat = 16n
  do IO<Unit>:
    +start : Nat <- IO.now()
    final : Probe.Carried <- pacer.go(iterations, carried, region, grid, depth,
      Probe.origin_x(), Probe.origin_z(), target, start, sleeping, sky)
    +digest : U32 = Probe.carried_digest(final)
    finished : Nat <- IO.now()
    consumed : Unit <- IO.print("consume=pacer:" ++ U32.show(digest))
    IO.print(phase_line(name, size_of(depth), iterations, start, finished, digest)
      ++ " target_ms=" ++ Nat.show(target) ++ " sleep=" ++ Bool.show(sleeping))

# The camera stage, folded into something printable: the rebased eye and the basis
# it produced, so neither can be dropped as dead code.

def camera_tag.at(+pose: Probe.Pose) -> U32:
  +seen : U32 = camera_read(pose)
  +tilt : F32 = Probe.camera_forward_y(Probe.camera_of(pose))
  U32.add(seen, F32.to_u32(F32.abs(tilt)))


# The camera stage: the rebased eye and the basis it produced, both folded into one
# printable word so neither can be dropped as dead code.

def camera_tag(pose: Probe.Pose) -> U32:
  camera_tag.at(pose)

def camera.go(remaining: Nat, +state: Player.State, +origin_x: Nat, +origin_z: Nat,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      +moved : F32 = F32.add(Probe.player_x(state), 0.031)
      +next : Player.State = Player.state(moved, Probe.player_y(state),
        Probe.player_z(state), Probe.player_yaw(state), Probe.player_pitch(state), 0.0,
        True{}, 20.0, 20.0)
      +posed : Probe.Pose = Probe.pose(next, origin_x, origin_z)
      +seen : U32 = camera_tag(posed)
      camera.go(p, next, origin_x, origin_z, fold_hash(hash, seen))

# The camera folded into something printable, so the pose and the basis cannot be
# dropped as dead code.

def camera_phase(+iterations: Nat, +state: Player.State) -> IO(Unit):
  +origin_x : Nat = Probe.origin_x()
  +origin_z : Nat = Probe.origin_z()
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 = camera.go(iterations, state, origin_x, origin_z, 2166136261)
    consumed : Unit <- IO.print("consume=camera:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("camera", 0, iterations, started, finished, digest))

# ---------------------------------------------------------------------------
# What is measured has to agree with itself
#
# The two frame paths must produce the same pixels and the sky control must not,
# or the numbers below would be three different programs.
# ---------------------------------------------------------------------------
def check_paths(+depth: Nat, +state: Player.State, +region: PlayerProbe.Region,
  +grid: Voxel.VoxelGrid) -> IO(Unit):
  +events : List<&2, Event> = Probe.idle_events()
  +pose : Probe.Pose = Probe.pose(state, Probe.origin_x(), Probe.origin_z())
  +cached : Probe.Frame = Probe.frame(state, events, Probe.tick_dt(), region, grid,
    depth, Probe.origin_x(), Probe.origin_z(), pose, 0, True{})
  +camera : Voxel.Camera = Probe.camera_of(pose)
  +rebuilt : U32 = Probe.fingerprint(Probe.render_chunk(Probe.chunk(), pose, depth))
  +sky : U32 = Probe.fingerprint(Probe.render_sky(camera, depth))
  +digest : U32 = Probe.digest_of(cached)
  +agree : Bool = U32.is_eq(digest, rebuilt)
  +solid : Bool = U32.is_ne(digest, sky)
  do IO<Unit>:
    IO.print("agreement size=" ++ U32.show(size_of(depth)) ++ " cached=" ++ U32.show(digest)
      ++ " rebuilt=" ++ U32.show(rebuilt) ++ " sky=" ++ U32.show(sky))
    Unit <- require(agree,
      "the cached-grid frame and the rebuild-per-frame frame disagree")
    report_sky_control(solid)

# Split out because a `do` block takes one final term, and this is the second of
# two checks the same run has to make.

def run_phases(+state: Player.State, +region: PlayerProbe.Region,
  +grid: Voxel.VoxelGrid) -> IO(Unit):
  +camera : Voxel.Camera = Probe.camera_of(Probe.pose(state, Probe.origin_x(),
    Probe.origin_z()))
  do IO<Unit>:
    Unit <- check_paths(5n, state, region, grid)
    Unit <- check_paths(6n, state, region, grid)
    Unit <- check_paths(7n, state, region, grid)
    Unit <- clock_phase(2000n)
    Unit <- input_phase(4096n)
    Unit <- tick_phase(256n, state, region)
    Unit <- camera_phase(4096n, state)
    Unit <- render_phase(5n, 32n, grid, camera)
    Unit <- paint_phase(5n, 32n, grid, camera)
    Unit <- consume_phase(5n, 32n, grid, camera)
    Unit <- release_phase(5n, 32n, grid, camera)
    Unit <- render_phase(6n, 16n, grid, camera)
    Unit <- paint_phase(6n, 16n, grid, camera)
    Unit <- consume_phase(6n, 16n, grid, camera)
    Unit <- release_phase(6n, 16n, grid, camera)
    Unit <- render_phase(7n, 8n, grid, camera)
    Unit <- paint_phase(7n, 8n, grid, camera)
    Unit <- consume_phase(7n, 8n, grid, camera)
    Unit <- release_phase(7n, 8n, grid, camera)
    Unit <- pinned_phase(5n, 32n, grid)
    Unit <- pinned_phase(6n, 16n, grid)
    Unit <- pinned_phase(7n, 8n, grid)
    Unit <- frame_phase(5n, 32n, state, region, grid)
    Unit <- frame_phase(6n, 16n, state, region, grid)
    Unit <- frame_phase(7n, 8n, state, region, grid)
    Unit <- rebuild_phase(5n, 32n, state, region)
    Unit <- rebuild_phase(6n, 16n, state, region)
    Unit <- rebuild_phase(7n, 8n, state, region)
    Unit <- dirty_phase(5n, 64n, state, region, grid)
    Unit <- sky_frame_phase(5n, 32n, state, region)
    Unit <- sky_frame_phase(6n, 16n, state, region)
    Unit <- sky_frame_phase(7n, 8n, state, region)
    Unit <- sky_frame_phase(8n, 8n, state, region)
    Unit <- sky_frame_phase(9n, 4n, state, region)
    Unit <- sky_frame_phase(10n, 4n, state, region)
    Unit <- sky_frame_phase(11n, 2n, state, region)
    Unit <- pacer_phase("pacer_free", 5n, 60n, state, region, grid, False{}, True{})
    Unit <- pacer_phase("pacer_60", 5n, 60n, state, region, grid, True{}, True{})
    Unit <- pacer_phase("pacer_free_solid", 5n, 60n, state, region, grid, False{},
      False{})
    Unit <- pacer_phase("pacer_60_solid", 5n, 60n, state, region, grid, True{}, False{})
    Unit <- pacer_phase("pacer_free_solid64", 6n, 30n, state, region, grid, False{},
      False{})
    Unit <- pacer_phase("pacer_60_solid64", 6n, 30n, state, region, grid, True{}, False{})
    IO.print("frame-bench=pass")

def main() -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- region_of(Probe.region())
    Unit <- bootstrap_phase(16n)
    +grid : Voxel.VoxelGrid = Probe.grid()
    +state : Player.State = settle(settle_ticks(), Probe.initial_player(), region)
    run_phases(state, region, grid)
