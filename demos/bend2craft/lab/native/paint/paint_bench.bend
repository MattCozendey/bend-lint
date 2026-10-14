import Base
import ../../../world/world_state.bend as WorldState
import ../../../world/player.bend as Player
import ../../../native/player.bend as PlayerProbe
import ../../../native/face.bend as Face
import ../../../native/voxel.bend as Voxel
import ../../../native/frame.bend as Frame
import ../../../native/paint.bend as Paint
import ../../../native/bag.bend as Bag
import ../../../native/net.bend as Net
import ../../../native/sky.bend as Sky
import ../../../native/action.bend as Action
import ../../../native/play.bend as Play
import ../../../native/slabs.bend as Slabs

# The painter's frame cost at the client's own spawn camera, per window size.
#
# Two phases per size, one per painter, over the spawn chunk's faces, with the image
# read back through `Voxel.fingerprint` before it is released. The read-back is the same
# quadtree walk `window_show` performs, so the number is the draw plus the present's walk
# and leaves out only the X transfer. Every phase prints its digest inside the timed
# region, so no phase can be dropped as dead code, and the digest is what
# `lab/native/paint/run.sh` compares across thread counts.

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

def phase_line(name: String, +size: U32, +iterations: Nat, started: Nat,
  finished: Nat, +digest: U32) -> String:
  "phase=" ++ name ++ " size=" ++ U32.show(size)
    ++ " iterations=" ++ Nat.show(iterations)
    ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
    ++ " digest=" ++ U32.show(digest)

def scene_faces() -> List<&2, Face.Face>:
  Face.faces_from_chunk(WorldState.chunk(Frame.seed(), Frame.chunk_x(), Frame.chunk_z(),
    WorldState.empty()))

def spawn_pose() -> Frame.Pose:
  Frame.pose(PlayerProbe.create_player(25n, 25n, 9n), Frame.origin_x(), Frame.origin_z())

# `tiled` picks how the frame is divided: `paint_whole_at` paints it as one tile and
# `paint_tiles_at` as the client does. The two must print the same digest at every size,
# because they are the same spans in the same order and not two renderers.
def image_with(tiled: Bool, +faces: List<&2, Face.Face>, pose: Frame.Pose, +depth: Nat) -> Image:
  match tiled pose:
    case True{} Frame.Pose{eye, yaw, pitch}:
      Paint.paint_tiles_at(faces, eye, yaw, pitch, depth)
    case False{} Frame.Pose{eye, yaw, pitch}:
      Paint.paint_whole_at(faces, eye, yaw, pitch, depth)

def draw_step(tiled: Bool, +faces: List<&2, Face.Face>, pose: Frame.Pose, +depth: Nat,
  +hash: U32) -> U32:
  +image = image_with(tiled, faces, pose, depth)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  fold_hash(hash, digest)

def draw.go(remaining: Nat, +tiled: Bool, +faces: List<&2, Face.Face>, +pose: Frame.Pose,
  +depth: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      draw.go(p, tiled, faces, pose, depth, draw_step(tiled, faces, pose, depth, hash))

def draw_phase(+label: String, +iterations: Nat, +tiled: Bool, +faces: List<&2, Face.Face>,
  +pose: Frame.Pose, +depth: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, draw.go(iterations, tiled, faces, pose, depth, 2166136261))
    consumed : Unit <- IO.print("consume=" ++ label ++ ":" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line(label, U32.shln(1, depth), iterations, started, finished, digest))

# The client's own frame: its view region's faces, held as the client holds them, drawn
# through `Play.image_at_depth` from the spawn pose, under the starting bag's hotbar. This is the row the frame budget is
# judged on, because the region is nine chunks and the phases above are one.
def client_step(+world: Slabs.World, +pose: Frame.Pose, +depth: Nat, +hash: U32) -> U32:
  +image = Play.image_at_depth(world, pose, depth, Bag.start(), 20, 20)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  fold_hash(hash, digest)

def client.go(remaining: Nat, +world: Slabs.World, +pose: Frame.Pose, +depth: Nat,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      client.go(p, world, pose, depth, client_step(world, pose, depth, hash))

def client_phase(+iterations: Nat, +world: Slabs.World, +pose: Frame.Pose,
  +depth: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, client.go(iterations, world, pose, depth, 2166136261))
    consumed : Unit <- IO.print("consume=client:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("client", U32.shln(1, depth), iterations, started, finished, digest))

# The same frame from outside. The spawn is inside a village house facing a wall, which is
# the cheapest frame the client draws: one near face covers the window. These stand the
# player on open ground fifteen cells east of the spawn, in the region the client would have
# moved there, and look along each of the four ways and down across the terrain, which is
# where a frame has the most faces to resolve.
def outdoor_pose(+yaw: F32, +pitch: F32) -> Frame.Pose:
  Frame.Pose{Voxel.Vec{40.5, 10.62, 25.5}, yaw, pitch}

def outdoor_phase(+label: String, +iterations: Nat, +world: Slabs.World, +yaw: F32,
  +pitch: F32, +depth: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, client.go(iterations, world, outdoor_pose(yaw, pitch), depth,
      2166136261))
    consumed : Unit <- IO.print("consume=" ++ label ++ ":" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line(label, U32.shln(1, depth), iterations, started, finished, digest))

# The same frame with a room's other players in it: eight of them, east of the outdoor camera
# from three cells off to forty, each facing another way. This is what a full room costs
# over the `east` row, which is the same camera with nobody there.
def crowd() -> List<&2, Net.Other>:
  [Net.Other{1, "Ana", Net.Place{59.5, 9.0, 41.5, 4.7124, 0.0}, True{}}, Net.Other{2, "Bia", Net.Place{61.5, 9.0, 43.5, 0.0, 0.0}, True{}},
    Net.Other{3, "Caio", Net.Place{63.5, 9.0, 39.5, 1.5708, 0.0}, True{}}, Net.Other{4, "Duda", Net.Place{66.5, 9.0, 42.5, 3.1416, 0.0}, True{}},
    Net.Other{5, "Eva", Net.Place{70.5, 9.0, 40.5, 0.7854, 0.0}, True{}}, Net.Other{6, "Fabio", Net.Place{76.5, 9.0, 44.5, 2.3562, 0.0}, True{}},
    Net.Other{7, "Gil", Net.Place{84.5, 9.0, 38.5, 5.4978, 0.0}, True{}}, Net.Other{8, "Helena", Net.Place{96.5, 9.0, 41.5, 4.7124, 0.0}, True{}}]

# What a room simulates, as much of it as a view is likely to hold: forty things east of
# the camera in rows of eight, the kinds taken in turn.
def herd.go(remaining: Nat, +index: U32, acc: List<&2, Net.Thing>) -> List<&2, Net.Thing>:
  match remaining:
    case 0n:
      acc
    case 1n+rest:
      herd.go(rest, U32.add(index, 1),
        Net.Thing{0, U32.add(U32.mod(index, 6), 1), 1, F32.add(59.5, F32.mul(U32.to_f32(U32.div(index, 8)), 4.0)), 9.0,
          F32.add(34.5, F32.mul(U32.to_f32(U32.mod(index, 8)), 2.0)), F32.mul(U32.to_f32(index), 0.7)} <> acc)

def herd() -> List<&2, Net.Thing>:
  herd.go(40n, 0, [])

def scene_step(+world: Slabs.World, +pose: Frame.Pose, +depth: Nat, +hash: U32,
  others: List<&2, Net.Other>, things: List<&2, Net.Thing>) -> U32:
  +image = Play.image_among(world, pose, depth, Bag.start(), 20, 20, Sky.clock_start(), Sky.clock_start(), others, things, 0)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  fold_hash(hash, digest)

def herd.steps(remaining: Nat, +world: Slabs.World, +pose: Frame.Pose, +depth: Nat,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      herd.steps(p, world, pose, depth, scene_step(world, pose, depth, hash, [], herd()))

def herd_phase(+iterations: Nat, +world: Slabs.World, +depth: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, herd.steps(iterations, world, outdoor_pose(1.5708, 0.0), depth,
      2166136261))
    consumed : Unit <- IO.print("consume=herd:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("herd", U32.shln(1, depth), iterations, started, finished, digest))

def crowd_step(+world: Slabs.World, +pose: Frame.Pose, +depth: Nat, +hash: U32) -> U32:
  +image = Play.image_among(world, pose, depth, Bag.start(), 20, 20, Sky.clock_start(), Sky.clock_start(), crowd(), [], 0)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  fold_hash(hash, digest)

def crowd.go(remaining: Nat, +world: Slabs.World, +pose: Frame.Pose, +depth: Nat,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      crowd.go(p, world, pose, depth, crowd_step(world, pose, depth, hash))

def crowd_phase(+iterations: Nat, +world: Slabs.World, +depth: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, crowd.go(iterations, world, outdoor_pose(1.5708, 0.0), depth,
      2166136261))
    consumed : Unit <- IO.print("consume=crowd:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("crowd", U32.shln(1, depth), iterations, started, finished, digest))

# The cold path: the view region's chunks generated and their exposed faces extracted, which
# the client pays once at start and once per edit.
def build.go(remaining: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      build.go(p, fold_hash(hash,
        Face.face_total(Slabs.w_faces(Slabs.world_built(WorldState.empty(), Frame.home_start())))))

def build_phase(+iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, build.go(iterations, 2166136261))
    consumed : Unit <- IO.print("consume=build:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("build", 0, iterations, started, finished, digest))

# What an edit costs the frame after it: the one slab the edit is in rebuilt, and the region
# merged again. Each draw starts from the world as it was before the edit, so every one
# pays for the slab.
def one_edit() -> List<&2, WorldState.Edit>:
  WorldState.set(WorldState.empty(), 25n, 9n, 25n, 0)

def slab.go(remaining: Nat, +world: Slabs.World, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      slab.go(p, world, fold_hash(hash,
        Face.face_total(Slabs.w_faces(Slabs.world_for(world, one_edit(), Frame.home_start())))))

def slab_phase(+iterations: Nat, +world: Slabs.World) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, slab.go(iterations, world, 2166136261))
    consumed : Unit <- IO.print("consume=slab:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("slab", 0, iterations, started, finished, digest))

# The other half of an edit: the collision region rebuilt from the edit log.
def hit_mark(result: Player.RayResult) -> U32:
  match result:
    case Player.NoHit{}:
      1
    case Player.Hit{hit_x, hit_y, hit_z, place_x, place_y, place_z, has_place}:
      U32.from_nat(hit_y)

def collided(maybe: Maybe<&1, PlayerProbe.Region>, +pose: Frame.Pose) -> U32:
  match maybe:
    case Some{region}:
      hit_mark(Action.aimed(pose, region))
    case None{}:
      0

def collide.go(remaining: Nat, +pose: Frame.Pose, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      collide.go(p, pose, fold_hash(hash,
        collided(Play.collision_region(WorldState.empty(), Play.den_start()), pose)))

def collide_phase(+iterations: Nat, +pose: Frame.Pose) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, collide.go(iterations, pose, 2166136261))
    consumed : Unit <- IO.print("consume=collide:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("collide", 0, iterations, started, finished, digest))

def main() -> IO(Unit):
  do IO<Unit>:
    +faces : List<&2, Face.Face> = scene_faces()
    +pose : Frame.Pose = spawn_pose()
    warm : Unit <- draw_phase("warm", 4n, True{}, faces, pose, 7n)
    a : Unit <- draw_phase("whole", 40n, False{}, faces, pose, 5n)
    b : Unit <- draw_phase("whole", 40n, False{}, faces, pose, 6n)
    c : Unit <- draw_phase("whole", 40n, False{}, faces, pose, 7n)
    d : Unit <- draw_phase("whole", 40n, False{}, faces, pose, 8n)
    e : Unit <- draw_phase("whole", 40n, False{}, faces, pose, 9n)
    f : Unit <- draw_phase("whole", 40n, False{}, faces, pose, 10n)
    g : Unit <- draw_phase("tiles", 40n, True{}, faces, pose, 5n)
    h : Unit <- draw_phase("tiles", 40n, True{}, faces, pose, 6n)
    i : Unit <- draw_phase("tiles", 40n, True{}, faces, pose, 7n)
    j : Unit <- draw_phase("tiles", 40n, True{}, faces, pose, 8n)
    k : Unit <- draw_phase("tiles", 40n, True{}, faces, pose, 9n)
    l : Unit <- draw_phase("tiles", 40n, True{}, faces, pose, 10n)
    +world : Slabs.World = Slabs.world_built(WorldState.empty(), Frame.home_start())
    said : Unit <- IO.print("client-faces=" ++ U32.show(Face.face_total(Slabs.w_faces(world))))
    m : Unit <- client_phase(40n, world, pose, 5n)
    n : Unit <- client_phase(40n, world, pose, 6n)
    o : Unit <- client_phase(40n, world, pose, 7n)
    p : Unit <- client_phase(40n, world, pose, 8n)
    q : Unit <- client_phase(40n, world, pose, 9n)
    r : Unit <- client_phase(40n, world, pose, 10n)
    +outside : Slabs.World = Slabs.world_built(WorldState.empty(), Frame.Home{2048n, 2047n})
    oa : Unit <- outdoor_phase("north", 40n, outside, 0.0, 0.0, 10n)
    ob : Unit <- outdoor_phase("east", 40n, outside, 1.5708, 0.0, 10n)
    oc : Unit <- outdoor_phase("south", 40n, outside, 3.1416, 0.0, 10n)
    od : Unit <- outdoor_phase("west", 40n, outside, 4.7124, 0.0, 10n)
    oe : Unit <- outdoor_phase("down", 40n, outside, 0.7854, F32.neg(0.6), 10n)
    of : Unit <- outdoor_phase("up", 40n, outside, 0.7854, 0.5, 10n)
    og : Unit <- crowd_phase(40n, outside, 10n)
    oh : Unit <- herd_phase(40n, outside, 10n)
    # The same views at 32x32, where there are almost no pixels: what is left is the part of
    # a frame that does not shrink with the window, the walk, the sort and the projection.
    sa : Unit <- outdoor_phase("north", 40n, outside, 0.0, 0.0, 5n)
    sb : Unit <- outdoor_phase("east", 40n, outside, 1.5708, 0.0, 5n)
    sc : Unit <- outdoor_phase("south", 40n, outside, 3.1416, 0.0, 5n)
    sd : Unit <- outdoor_phase("west", 40n, outside, 4.7124, 0.0, 5n)
    se : Unit <- outdoor_phase("down", 40n, outside, 0.7854, F32.neg(0.6), 5n)
    sf : Unit <- outdoor_phase("up", 40n, outside, 0.7854, 0.5, 5n)
    sg : Unit <- crowd_phase(40n, outside, 5n)
    sh : Unit <- herd_phase(40n, outside, 5n)
    s : Unit <- build_phase(10n)
    sl : Unit <- slab_phase(20n, world)
    t : Unit <- collide_phase(10n, pose)
    IO.print("paint-bench=done")
