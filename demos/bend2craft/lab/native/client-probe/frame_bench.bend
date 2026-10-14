import Base
import ../../../world/player.bend as Player
import ../../../world/world_state.bend as WorldState
import ../../../native/player.bend as PlayerProbe
import ../../../native/face.bend as Face
import ../../../native/voxel.bend as Voxel
import ../../../native/frame.bend as Frame
import ../../../native/size.bend as Size
import ../../../native/client.bend as Client
import ../../../native/paint.bend as Paint
import ../../../native/play.bend as Play
import ../../../native/slabs.bend as Slabs

# ---------------------------------------------------------------------------
# The client's own frame cost
#
# One frame is what native/client.bend's loop does between two `Window.frame`
# calls: the input fold, the player transition, the bulk `WorldState.chunk`, the
# face render at the client's own tile edge and window size, and the release of
# the image. This file owns the clock and nothing else: every stage calls the
# client's or a probe's own def, so a phase can only be as wrong as the rule it
# calls. `native/frame-probe` already measures input, tick and render separately
# against the raycast renderer; what is added here is the tick and the face
# render together, at the size and tile edge the client actually ships.
#
# Every timed phase folds its output into a hash and prints it inside the timed
# region, so no phase can be dropped as dead code.
# ---------------------------------------------------------------------------

def fold_hash(+hash: U32, +value: U32) -> U32:
  U32.mul(U32.xor(hash, value), 16777619)

def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "client-bench: " ++ message)

# The size is passed in rather than read from the client, because a phase can render
# at a depth other than the client's own and a line claiming the client's size for a
# 64x64 render would be a lie in the middle of a table.
def size_at(depth: Nat) -> U32:
  U32.shln(1, depth)

def phase_line(name: String, +size: U32, +iterations: Nat, started: Nat,
  finished: Nat, +digest: U32) -> String:
  "phase=" ++ name ++ " size=" ++ U32.show(size)
    ++ " iterations=" ++ Nat.show(iterations)
    ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finished, started))
    ++ " digest=" ++ U32.show(digest)

# ---------------------------------------------------------------------------
# The state the phases share
#
# `Client` is `Data`, so the state is rebuilt per repetition rather than reused: the
# real loop hands each frame a fresh one, and a phase that threaded one state
# through every stage would be measuring a value the loop never reuses.
# ---------------------------------------------------------------------------

def region_of(value: Maybe<&1, PlayerProbe.Region>) -> IO(PlayerProbe.Region):
  match value:
    case Some{region}:
      IO.pure(PlayerProbe.Region, region)
    case None{}:
      IO.die(PlayerProbe.Region, 1, "the benchmark region was refused")

def player_of(value: Maybe<&1, Player.State>) -> IO(Player.State):
  match value:
    case Some{player}:
      IO.pure(Player.State, player)
    case None{}:
      IO.die(Player.State, 1, "the benchmark spawn was refused")

# The same state the client builds on start: the frame probe's seed and spawn, an
# empty edit log, the 2x2 collision region, and the world's faces extracted once.
def spawn_pose(player: Player.State) -> Frame.Pose:
  Frame.pose(player, Frame.origin_x(), Frame.origin_z())

# The size every benchmark here measures, and the tile edge it buckets faces into. They are
# the benchmark's and not the client's: the shipped painter draws 64-pixel tiles and takes
# its size from `--size`. The edge was chosen by measurement, one chunk and then the
# client's own region and camera, and that table and its reasoning are in
# `lab/native/2026-09-30-native-renderer-investigation.md` and `lab/native/face/README.md`.
# Below depth 8 an edge of 16 wins and from 8 up 32 does, so the edge follows the depth of
# the frame being built.
def window_width() -> U32:
  128

def frame_depth() -> Nat:
  7n

def tile_edge_at(depth: Nat) -> U32:
  Bool.pick(U32, Nat.is_lt(depth, 8n), 16, 32)

def tile_edge() -> U32:
  tile_edge_at(frame_depth())

# The harness builds the client the benchmarks measure, which is the default the
# client picks with no flag. Asking the client for it keeps one number in one place.
def benchmarked_size() -> Size.Size:
  Size.of_width(window_width())

def posed(+player: Player.State, region: PlayerProbe.Region) -> Play.Client:
  +edits = WorldState.empty()
  Play.Client{player, spawn_pose(player), 0, edits, region, Play.path(),
    Slabs.world_built(edits), benchmarked_size()}

def spawn_state(region: PlayerProbe.Region) -> IO(Play.Client):
  do IO<Play.Client>:
    player : Player.State <- player_of(PlayerProbe.checked_create_player(25n, 25n, 9n))
    IO.pure(Play.Client, posed(player, region))

def benchmark_region() -> IO(PlayerProbe.Region):
  region_of(PlayerProbe.checked_from_world_state(Frame.seed(), Frame.chunk_x(),
    Frame.chunk_z(), Frame.columns(), Frame.rows(), WorldState.empty()))

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

# The clock on its own, because at a tenth of a millisecond a stage the clock's
# millisecond resolution is part of the answer.
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

def pose_of(state: Play.Client) -> Frame.Pose:
  Play.Client{player, +pose, keys, edits, region, path, world, size} = state
  pose

def eye_z_of(state: Play.Client) -> F32:
  Frame.eye_z(Frame.eye_of(pose_of(state)))

# The client's own tick, so the input fold, the edge decisions and the player
# transition are the ones the client runs. The step and its fold come before the
# fold that calls them, because a def must be written before anything that calls it.
def tick_fold(next: Play.Client, +hash: U32) -> U32:
  +z = F32.abs(eye_z_of(next))
  fold_hash(hash, F32.to_u32(z))

# The tick takes a `List<&1, Event>`, which is linear, so the fold cannot carry one
# across iterations; it carries the two `Event` values instead, which are `Data`, and
# builds the list per iteration. That list is the shape the runtime hands the client,
# so the fold being timed is the client's own.
#
# The tick answers with `Nothing` to leave, which is how `App.loop` ends, so a tick that
# keeps running has to be unwrapped here. The unwrap is a `match`, not a clamp: a tick
# that quit mid-benchmark is a different program than the one that ships, and the
# benchmark would quietly go on timing the wrong thing.
def client_or_die(maybe: Maybe<&1, Play.Client>) -> IO(Play.Client):
  match maybe:
    case Some{state}:
      IO.pure(Play.Client, state)
    case None{}:
      IO.die(Play.Client, 1, "frame-bench: the client stopped during a tick it should have kept running")

def tick_step(+state: Play.Client, +first: Event, +second: Event, +hash: U32) -> IO(U32):
  do IO<U32>:
    answer : Maybe<&1, Play.Client> <- Play.tick.events([first, second], state)
    +next : Play.Client <- client_or_die(answer)
    IO.pure(U32, tick_fold(next, hash))

# The state is built once, outside the fold, and handed to every iteration. It used to
# be built per iteration, which was free while the world was extracted inside the render
# and is not free now that the client extracts it once on start: a per-iteration spawn
# would have timed the world build inside the tick and reported a tick that does not
# exist. `Client` is `Data`, so one state serves every iteration.
def tick.go(remaining: Nat, +state: Play.Client, +first: Event, +second: Event,
  +hash: U32) -> IO(U32):
  match remaining:
    case 0n:
      IO.pure(U32, hash)
    case 1n+p:
      do IO<U32>:
        +next : U32 <- tick_step(state, first, second, hash)
        tick.go(p, state, first, second, next)

# The bulk world build on its own. The client materialises the whole view region on
# every frame, and the browser-path constitution says a client builds its world once and
# then only renders it, so this phase is what a cached region would save. It is timed
# separately because the two costs have different fixes.

# The client's per-frame world cost: the whole view region, not one chunk. The phase
# used to build a single chunk, which understated the client's own work by the region
# factor the moment the client rendered more than one. `List.length` is the observer
# because it traverses the list the client just built, so the generation cannot be
# elided; folding the cell values would double-count, since reading them is the
# renderer's cost and is measured by the render phases.
def region_cells(chunks: List<&2, List<&2, U32>>) -> U32:
  match chunks:
    case Nil{}:
      0
    case +cells <> rest:
      U32.add(U32.from_nat(List.length(&2, U32, cells)), region_cells(rest))

def chunk_step(+edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  fold_hash(hash, region_cells(Client.region_chunks(Frame.seed(), edits)))

def chunk.go(remaining: Nat, +edits: List<&2, WorldState.Edit>, +hash: U32) -> IO(U32):
  match remaining:
    case 0n:
      IO.pure(U32, hash)
    case 1n+p:
      chunk.go(p, edits, chunk_step(edits, hash))

# The client's own frame, called rather than restated. The bench used to inline
# `Face.render_size_at_with_tile_size` over a single chunk, which stopped being what the
# client does the moment the client rendered a region, and a benchmark that measures a
# different program than the one that ships is worse than no benchmark.
def render_with(world: Slabs.World, +pose: Frame.Pose) -> Image:
  Play.image_of(world, pose, benchmarked_size())

# The image is read back before it is released, because a build whose result nothing
# observes is elidable and a phase that measured an elided build would report the cost
# of nothing. The read is a full quadtree walk, and the client pays it too:
# `Window.frame` calls `window_show`, which walks the same tree with `window_fill` into
# the X pixmap before `XPutImage`. So the fingerprint is a fair stand-in for the
# present step, and the only thing it leaves out is the X transfer.
# The world a render phase draws. The build is inside the matched arm and not an
# argument to it: a `Bool`-guarded call whose argument is built before the call
# measures the cold path in the warm row, which is how this read 8.45 ms against
# `render_64`'s 6.05 for the same call.
def render_world(cold: Bool, +edits: List<&2, WorldState.Edit>, carried: Slabs.World) -> Slabs.World:
  match cold:
    case True{}:
      Slabs.world_built(edits)
    case False{}:
      carried

def render_step(cold: Bool, +edits: List<&2, WorldState.Edit>, world: Slabs.World,
  +pose: Frame.Pose, +hash: U32) -> U32:
  +next = render_world(cold, edits, world)
  +image = render_with(next, pose)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  fold_hash(hash, digest)

def render.go(remaining: Nat, +edits: List<&2, WorldState.Edit>,
  +world: Slabs.World, +pose: Frame.Pose, +cold: Bool, +hash: U32) -> IO(U32):
  match remaining:
    case 0n:
      IO.pure(U32, hash)
    case 1n+p:
      render.go(p, edits, world, pose, cold,
        render_step(cold, edits, world, pose, hash))

def render_phase(+label: String, +iterations: Nat,
  +edits: List<&2, WorldState.Edit>, +world: Slabs.World, +pose: Frame.Pose,
  +cold: Bool) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- render.go(iterations, edits, world, pose, cold, 2166136261)
    consumed : Unit <- IO.print("consume=" ++ label ++ ":" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line(label, window_width(), iterations, started, finished, digest))

# Face extraction on its own: the world cells turned into the exposed-face list, with
# the list observed so the walk cannot be elided. This is the phase that says where
# the render's fixed cost lives, and it is resolution-independent, so anything it
# reports is cost the client pays at every window size including the smallest.
def extract_with(+edits: List<&2, WorldState.Edit>) -> List<&2, Face.Face>:
  Face.faces_from_chunk(WorldState.chunk(Frame.seed(), Frame.chunk_x(),
    Frame.chunk_z(), edits))

def face_total(faces: List<&2, Face.Face>) -> U32:
  match faces:
    case Nil{}:
      0
    case +face <> rest:
      U32.add(1, face_total(rest))

def extract_step(+edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  fold_hash(hash, face_total(extract_with(edits)))

def extract.go(remaining: Nat, +edits: List<&2, WorldState.Edit>, +hash: U32) -> IO(U32):
  match remaining:
    case 0n:
      IO.pure(U32, hash)
    case 1n+p:
      extract.go(p, edits, extract_step(edits, hash))

def extract_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- extract.go(iterations, edits, 2166136261)
    consumed : Unit <- IO.print("consume=extract:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("extract", window_width(), iterations, started, finished, digest))

# ---------------------------------------------------------------------------
# Where the render's own time goes
#
# `render` is one number for four costs that have four different fixes, so it cannot
# tell anyone which one to attack. These phases split the shipped render at the
# client's own camera, region and tile edge:
#
#   faces    the region materialised and walked into exposed faces
#   project  the above, plus every face projected and clipped into a screen box
#   grid     the above, plus the scatter into the tile grid `bucket_all` builds
#   render   all of it, plus the quadtree fold and the read-back
#
# `render - grid` is therefore the image fold and the read-back, and it is the only
# per-pixel term in the table. Each phase folds its own output, so no phase can be
# elided and no phase can borrow another's work.
#
# `project` is the one phase that is not the shipping call: `bucket_all` projects
# each face and scatters it in the same pass, and there is no way to stop between
# the two. It is here to separate the per-face arithmetic from the per-tile
# placement, and both halves are also measured on their own in the table.
# ---------------------------------------------------------------------------

def region_faces(edits: List<&2, WorldState.Edit>) -> List<&2, Face.Face>:
  Face.faces_from_chunks(Client.region_chunks(Frame.seed(), edits),
    Frame.view_columns(), Frame.view_rows())

def screen_hash(screens: List<&2, Face.Screen>, +hash: U32) -> U32:
  match screens:
    case Nil{}:
      hash
    case +screen <> rest:
      screen_hash(rest, fold_hash(hash, Face.s_depth_key(screen)))

def bucket_hash(bucket: List<&2, Face.Screen>, +hash: U32) -> U32:
  match bucket:
    case Nil{}:
      hash
    case +screen <> rest:
      bucket_hash(rest, fold_hash(hash, Face.s_depth_key(screen)))

def row_hash(+row: List<&2, List<&2, Face.Screen>>, +hash: U32) -> U32:
  match row:
    case Nil{}:
      hash
    case +bucket <> rest:
      row_hash(rest, bucket_hash(bucket, hash))

def grid_hash(+rows: List<&2, List<&2, List<&2, Face.Screen>>>, +hash: U32) -> U32:
  match rows:
    case Nil{}:
      hash
    case +row <> rest:
      grid_hash(rest, row_hash(row, hash))

# The camera and the projection constants the render entry derives, restated once
# here so a phase that stops early is still projecting the frame the client draws.
def camera_of(+pose: Frame.Pose) -> Voxel.Camera:
  Voxel.Camera.look(Frame.eye_of(pose), Frame.yaw_of(pose), Frame.pitch_of(pose))

def half_at(depth: Nat) -> F32:
  Voxel.projection_half(depth)

def focal_at(depth: Nat) -> F32:
  F32.mul(1.5, half_at(depth))

def faces_step(+edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  fold_hash(hash, face_total(Face.faces_from_chunks(Client.region_chunks(Frame.seed(), edits),
    Frame.view_columns(), Frame.view_rows())))

def faces.go(remaining: Nat, +edits: List<&2, WorldState.Edit>, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      faces.go(p, edits, faces_step(edits, hash))

def project_screens(edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera,
  +half: F32, +focal: F32, +size: U32) -> List<&2, Face.Screen>:
  Face.project_screens(region_faces(edits), Face.cam_eye(camera), Face.cam_right(camera),
    Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)

def project_step(+edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +hash: U32) -> U32:
  screen_hash(project_screens(edits, camera, half, focal, size), hash)

def project.go(remaining: Nat, +edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera,
  +half: F32, +focal: F32, +size: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      project.go(p, edits, camera, half, focal, size, project_step(edits, camera, half,
        focal, size, hash))

def grid_with(+edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +edge: U32) -> Face.Tiles:
  +across = Face.tiles_across(size, edge)
  +empty : List<&2, List<&2, List<&2, Face.Screen>>> = Face.empty_grid(across)
  Face.Tiles{Face.bucket_all(region_faces(edits), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal,
    size, across, edge, empty), size, edge, camera, half, focal}

def grid_step(+edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +edge: U32, +hash: U32) -> U32:
  +tiles : Face.Tiles = grid_with(edits, camera, half, focal, size, edge)
  grid_hash(Face.tiles_rows(tiles), hash)

def grid.go(remaining: Nat, +edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera,
  +half: F32, +focal: F32, +size: U32, +edge: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      grid.go(p, edits, camera, half, focal, size, edge, grid_step(edits, camera, half,
        focal, size, edge, hash))

# A stage phase: the same `go` shape, timed and folded, at the client's own window.
def faces_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, faces.go(iterations, edits, 2166136261))
    consumed : Unit <- IO.print("consume=faces:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("faces", window_width(), iterations, started, finished, digest))

def project_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera,
  +size: U32) -> IO(Unit):
  do IO<Unit>:
    +half : F32 = half_at(frame_depth())
    +focal : F32 = focal_at(frame_depth())
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, project.go(iterations, edits, camera, half, focal, size, 2166136261))
    consumed : Unit <- IO.print("consume=project:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("project", size, iterations, started, finished, digest))

def grid_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera,
  +size: U32) -> IO(Unit):
  do IO<Unit>:
    +half : F32 = half_at(frame_depth())
    +focal : F32 = focal_at(frame_depth())
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, grid.go(iterations, edits, camera, half, focal, size,
      tile_edge(), 2166136261))
    consumed : Unit <- IO.print("consume=grid:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("grid", size, iterations, started, finished, digest))

# `render - grid` is the per-pixel term. It is itself two costs with two different
# shapes, so `pixel` walks the same tile grid directly and never builds a quadtree,
# and `image` builds the quadtree and reads it back the way `window_show` does.
# `image - pixel` is then the tree and the read-back alone, and `pixel` is the
# candidate walk.
def pixel_row(+tiles: Face.Tiles, remaining: Nat, +px: U32, +py: U32, +size: U32,
  +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+r:
      +next = (px + 1 : U32)
      pixel_row(tiles, r, next, py, size, fold_hash(hash, Face.face_pixel_color(tiles, px, py)))

def pixel_walk(+tiles: Face.Tiles, rows_left: Nat, +py: U32, +size: U32, +hash: U32) -> U32:
  match rows_left:
    case 0n:
      hash
    case 1n+r:
      +next = (py + 1 : U32)
      pixel_walk(tiles, r, next, size, pixel_row(tiles, U32.to_nat(size), 0, py, size, hash))

def pixel.go(remaining: Nat, +tiles: Face.Tiles, +size: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      pixel.go(p, tiles, size, pixel_walk(tiles, U32.to_nat(size), 0, size, hash))

def image_step(+tiles: Face.Tiles, +depth: Nat, +hash: U32) -> U32:
  +image = Face.render_size_tiles(tiles, depth)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  fold_hash(hash, digest)

def image.go(remaining: Nat, +tiles: Face.Tiles, +depth: Nat, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      image.go(p, tiles, depth, image_step(tiles, depth, hash))

def pixel_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>,
  +camera: Voxel.Camera, +size: U32) -> IO(Unit):
  do IO<Unit>:
    +tiles : Face.Tiles = grid_with(edits, camera, half_at(frame_depth()),
      focal_at(frame_depth()), size, tile_edge())
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, pixel.go(iterations, tiles, size, 2166136261))
    consumed : Unit <- IO.print("consume=pixel:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("pixel", size, iterations, started, finished, digest))

def step_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>,
  +camera: Voxel.Camera, +size: U32) -> IO(Unit):
  do IO<Unit>:
    +tiles : Face.Tiles = grid_with(edits, camera, half_at(frame_depth()),
      focal_at(frame_depth()), size, tile_edge())
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, Face.step.go(iterations, tiles, size, 2166136261))
    consumed : Unit <- IO.print("consume=step:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("step", size, iterations, started, finished, digest))

def bare_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>,
  +camera: Voxel.Camera, +size: U32) -> IO(Unit):
  do IO<Unit>:
    +tiles : Face.Tiles = grid_with(edits, camera, half_at(frame_depth()),
      focal_at(frame_depth()), size, tile_edge())
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, Face.step_bare.go2(iterations, tiles, size, 2166136261))
    consumed : Unit <- IO.print("consume=bare:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("bare", size, iterations, started, finished, digest))

def one_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>,
  +camera: Voxel.Camera, +size: U32) -> IO(Unit):
  do IO<Unit>:
    +tiles : Face.Tiles = grid_with(edits, camera, half_at(frame_depth()),
      focal_at(frame_depth()), size, tile_edge())
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, Face.one.go(iterations, tiles, size, 2166136261))
    consumed : Unit <- IO.print("consume=one:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("one", size, iterations, started, finished, digest))

# The row-major builder at a chosen tile edge, for comparison against the scatter.
# Row-major fills one tile row at a time, so it needs no random access into the grid
# at all — every placement is a cons — at the price of one box test per face per row.
# That trade is the only thing standing between the shipping builder and a smaller
# tile edge, so it is measured rather than modelled. Both phases build the grid inside
# the timed loop, exactly as `grid` does, so the three are like for like.
def grid_rm_with(+edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +edge: U32) -> Face.Tiles:
  +across = Face.tiles_across(size, edge)
  +screens = Face.project_screens(region_faces(edits), Face.cam_eye(camera),
    Face.cam_right(camera), Face.cam_up(camera), Face.cam_forward(camera), half, focal, size)
  Face.Tiles{Face.row_major_rows(U32.to_nat(across), 0, across, edge, screens),
    size, edge, camera, half, focal}

def grid_rm_step(+edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera, +half: F32,
  +focal: F32, +size: U32, +edge: U32, +hash: U32) -> U32:
  grid_hash(Face.tiles_rows(grid_rm_with(edits, camera, half, focal, size, edge)), hash)

def grid_rm.go(remaining: Nat, +edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera,
  +half: F32, +focal: F32, +size: U32, +edge: U32, +hash: U32) -> U32:
  match remaining:
    case 0n:
      hash
    case 1n+p:
      grid_rm.go(p, edits, camera, half, focal, size, edge,
        grid_rm_step(edits, camera, half, focal, size, edge, hash))

def grid_rm_phase(+label: String, +iterations: Nat, +edits: List<&2, WorldState.Edit>,
  +camera: Voxel.Camera, +size: U32, +edge: U32) -> IO(Unit):
  do IO<Unit>:
    +half : F32 = half_at(frame_depth())
    +focal : F32 = focal_at(frame_depth())
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, grid_rm.go(iterations, edits, camera, half, focal, size,
      edge, 2166136261))
    consumed : Unit <- IO.print("consume=" ++ label ++ ":" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line(label, size, iterations, started, finished, digest))

def image_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>,
  +camera: Voxel.Camera, +size: U32) -> IO(Unit):
  do IO<Unit>:
    +tiles : Face.Tiles = grid_with(edits, camera, half_at(frame_depth()),
      focal_at(frame_depth()), size, tile_edge())
    started : Nat <- IO.now()
    +digest : U32 <- IO.pure(U32, image.go(iterations, tiles, frame_depth(), 2166136261))
    consumed : Unit <- IO.print("consume=image:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("image", size, iterations, started, finished, digest))

# What the client's own view actually contains, printed once per run: the face
# count, how many survive clipping, and how many candidates the per-pixel walk is
# charged. The cost model is measured here rather than assumed from the tile edge.
def screen_count(screens: List<&2, Face.Screen>) -> U32:
  match screens:
    case Nil{}:
      0
    case +screen <> rest:
      U32.add(1, screen_count(rest))

# The pixels every face's conservative box covers, which is the work a rasteriser
# would do instead of the per-pixel bucket walk. Clamped to the frame, because a
# face crossing the near plane is given the full 16-bit range as its box and its
# 65536-square area is not work any renderer does.
# The area a rasteriser would have to touch: every live face's box, clamped to the
# frame the way the bucketing clamps it.
#
# This has to skip the dead faces, and it has to do it with the liveness flag rather
# than a comparison. A dead face has `x0 > x1` after clipping, so `min(x1, last) -
# min(x0, last)` underflows to about four billion, and one such term wraps the whole
# sum. Summing the dead faces in reported 3,094,159 against a true 390,799, which is
# 7.9x too high and the exact factor by which it beat the walk — the reason this line
# once said a rasteriser could not win.
def clip_area(screens: List<&2, Face.Screen>, +size: U32) -> U32:
  match screens:
    case Nil{}:
      0
    case +s <> rest:
      +last = U32.sub(size, 1)
      +c = Face.clip_screen(s, size)
      +w = U32.add(U32.sub(U32.min(Face.s_x1(c), last), U32.min(Face.s_x0(c), last)), 1)
      +h = U32.add(U32.sub(U32.min(Face.s_y1(c), last), U32.min(Face.s_y0(c), last)), 1)
      +area = Bool.pick(U32, Face.s_alive(c), U32.mul(w, h), 0)
      U32.add(area, clip_area(rest, size))

# How many faces fall back to the full 16-bit box, which is what a face with any
# corner behind the eye gets. Those faces are in every tile's bucket, so at edge 2,
# where a bucket holds only the faces whose box contains the pixel, they are the floor
# of the per-pixel candidate count. This says whether that floor is worth attacking.
def full_frame_count(screens: List<&2, Face.Screen>, +full: U32) -> U32:
  match screens:
    case Nil{}:
      0
    case +s <> rest:
      full_frame_count(rest,
        U32.add(Bool.pick(U32, Bool.and(U32.is_eq(Face.s_x0(s), 0),
          U32.is_eq(Face.s_x1(s), 65535)), 1, 0), full))

def edge_facts(edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera, +size: U32,
  +edge: U32) -> String:
  +tiles : Face.Tiles = grid_with(edits, camera, half_at(frame_depth()),
    focal_at(frame_depth()), size, edge)
  +across = Face.tiles_across(size, edge)
  " " ++ U32.show(edge) ++ "t" ++ U32.show(U32.mul(across, across))
    ++ "c" ++ U32.show(Face.candidate_count(size, tiles))

def edges_facts(+index: Nat, +edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera,
  +size: U32, +acc: String) -> String:
  match index:
    case 0n:
      acc
    case 1n+r:
      edges_facts(r, edits, camera, size,
        acc ++ edge_facts(edits, camera, size, (U32.shln(1, index) : U32)))

# The field of view is a lever on the frame with a price the player sees. `focal` is
# `scale * half` and the vertical angle is `2 * atan(1 / scale)`, so the shipping 1.5 is
# 67.4 degrees and 3.0 is 36.9. A face's projected box scales with the focal length, and
# the walk's step count is the sum of the boxes, so each scale's step count follows from
# one grid. This reports step counts, not times; the time follows from the ~25 ns a list
# step is measured at, and the builder is untouched by the field of view.
def focal_facts(edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera, +size: U32,
  +scale: F32) -> String:
  +half = half_at(frame_depth())
  +focal = F32.mul(scale, half)
  +tiles : Face.Tiles = grid_with(edits, camera, half, focal, size, tile_edge())
  " " ++ F32.show(scale) ++ "f" ++ U32.show(Face.candidate_count(size, tiles))

def facts_line(+edits: List<&2, WorldState.Edit>, +camera: Voxel.Camera, +size: U32) -> String:
  +half = half_at(frame_depth())
  +focal = focal_at(frame_depth())
  +edge = tile_edge()
  +count = face_total(region_faces(edits))
  +live = screen_count(project_screens(edits, camera, half, focal, size))
  +area = clip_area(project_screens(edits, camera, half, focal, size), size)
  +wide = full_frame_count(project_screens(edits, camera, half, focal, size), 0)
  +counted = Face.quad_area_of(region_faces(edits), camera, half, focal, size)
  +tiles : Face.Tiles = grid_with(edits, camera, half, focal, size, edge)
  +across = Face.tiles_across(size, edge)
  "facts=faces:" ++ U32.show(count) ++ " screens:" ++ U32.show(live)
    ++ " boxarea:" ++ U32.show(area)
    ++ " quadarea:" ++ U32.show(Face.counted_pixels(counted))
    ++ " behind:" ++ Bool.show(Face.counted_behind(counted))
    ++ " pixels:" ++ U32.show(U32.mul(size, size))
    ++ " fullframe:" ++ U32.show(wide)
    ++ " candidates:" ++ U32.show(Face.candidate_count(size, tiles))
    ++ " tiles:" ++ U32.show(U32.mul(across, across))
    ++ " edge:" ++ U32.show(edge)
    ++ " by_edge[" ++ edges_facts(4n, edits, camera, size, "") ++ "]"
    ++ " by_focal[" ++ focal_facts(edits, camera, size, 0.25)
    ++ focal_facts(edits, camera, size, 1.0)
    ++ focal_facts(edits, camera, size, 1.5)
    ++ focal_facts(edits, camera, size, 2.0)
    ++ focal_facts(edits, camera, size, 2.5)
    ++ focal_facts(edits, camera, size, 3.0)
    ++ focal_facts(edits, camera, size, 6.0)
    ++ focal_facts(edits, camera, size, 24.0) ++ "]"

# The render at a smaller window, at the same camera and tile edge, so the size the
# client can actually hold at 60 Hz is measured rather than extrapolated from the
# pixel count. The pose is the client's own spawn pose in every case; only the frame
# depth changes.
def render_at_with(world: Slabs.World, +pose: Frame.Pose, depth: Nat) -> Image:
  Play.image_at_depth(world, pose, depth)

def render_at_step(world: Slabs.World, +pose: Frame.Pose, depth: Nat,
  +hash: U32) -> U32:
  +image = render_at_with(world, pose, depth)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  fold_hash(hash, digest)

def render_at.go(remaining: Nat, +world: Slabs.World, +pose: Frame.Pose,
  +depth: Nat, +hash: U32) -> IO(U32):
  match remaining:
    case 0n:
      IO.pure(U32, hash)
    case 1n+p:
      do IO<U32>:
        +next : U32 <- IO.pure(U32, render_at_step(world, pose, depth, hash))
        render_at.go(p, world, pose, depth, next)

def render_at_phase(+label: String, +iterations: Nat,
  +world: Slabs.World, +pose: Frame.Pose, +depth: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- render_at.go(iterations, world, pose, depth, 2166136261)
    consumed : Unit <- IO.print("consume=" ++ label ++ ":" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line(label, size_at(depth), iterations, started, finished, digest))

# The render alone, with no fingerprint.
#
# `render_at_phase` fingerprints the image, which is a full walk of the quadtree and at 512
# is most of the phase: the live client's `view` hands the image to `App.loop` and never reads
# it back, so a number that includes the read-back is not the number the 16.67 ms cap is
# judged on. `Image.drop` keeps the render from being optimised away without walking it.
# One pixel down the left spine. Reading it is what stops the render being optimised away:
# with only `Image.drop` on an unread image the whole fill is dead code and the phase reads
# 0.00 ms at every size, which is what the first version of this measured. It is also
# exactly the read the runtime does to present a frame.
def render_only.top(image: Image) -> U32:
  match image:
    case Pix{color}:
      color
    case Qua{tl, tr, bl, br}:
      render_only.top(tl)

def render_only.with(image: Image, +hash: U32) -> U32:
  fold_hash(hash, render_only.top(image))

def render_only.go(remaining: Nat, +world: Slabs.World, +pose: Frame.Pose,
  +depth: Nat) -> IO(Unit):
  match remaining:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        used : U32 <- IO.pure(U32, render_only.with(render_at_with(world, pose, depth),
          2166136261))
        render_only.go(p, world, pose, depth)

# The painter's two halves, so the frame's cost can be attributed rather than guessed at.
# `draw_*` is the whole thing; `sky_*` is the pre-fill alone and `fold_*` is the quadtree
# alone. At 1024 the pre-fill and the fold are each a million operations and the fill is
# not, so which of the three to attack is the whole question and it is cheaper to measure
# than to reason about.
def sky_of(read: Array<U32> & U32) -> Array<U32>:
  (frame, _) = read
  frame

def sky_value(read: Array<U32> & U32) -> U32:
  (_, +value) = read
  value

def sky_only.go(remaining: Nat, +size: U32, read: Array<U32> & U32) -> IO(U32):
  match remaining:
    case 0n:
      IO.pure(U32, sky_value(read))
    case 1n+p:
      do IO<U32>:
        filled : Array<U32> = Paint.sky.rows(U32.to_nat(size), 0, size, sky_of(read))
        sky_only.go(p, size, filled[0])

def sky_only.printed(+label: String, +size: U32, +iterations: Nat, +started: Nat,
  +finished: Nat) -> IO(Unit):
  IO.print(phase_line(label, size, iterations, started, finished, 0))

def sky_only.clocked(+label: String, +size: U32, +iterations: Nat, +started: Nat,
  +finished: Nat) -> IO(Unit):
  sky_only.printed(label, size, iterations, started, finished)

def sky_only.after(+label: String, +size: U32, +iterations: Nat, +started: Nat,
  +used: U32) -> IO(Unit):
  do IO<Unit>:
    finished : Nat <- IO.now()
    sky_only.clocked(label, size, iterations, started, finished)

def sky_only.timed(+label: String, +iterations: Nat, +depth: Nat, +size: U32,
  read: Array<U32> & U32, started: Nat) -> IO(Unit):
  do IO<Unit>:
    used : U32 <- sky_only.go(iterations, size, read)
    sky_only.after(label, size, iterations, started, used)

def sky_only.start(+label: String, +iterations: Nat, +depth: Nat, +size: U32,
  read: Array<U32> & U32) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    sky_only.timed(label, iterations, depth, size, read, started)

def sky_only_phase(+label: String, +iterations: Nat, +depth: Nat, +size: U32) -> IO(Unit):
  sky_only.start(label, iterations, depth, size, Array.new(U32, Paint.slots_of(depth), 0)[0])


# Every fill is forced by being consumed: each iteration's array is destructured by the next
# iteration's `sky_of`, and the last one is read by the base case. Passing the filled array
# forward without ever reading it leaves the whole pass as dead code and the phase reads
# 0.00 ms — which is what both `draw_*` and this first measured.








# `filled[0]` reads a pixel, which is what forces the pre-fill to have happened; without it
# the whole pass is dead code and the phase reads 0.00 ms, exactly as `draw_*` did.

def render_only_phase(+label: String, +iterations: Nat,
  +world: Slabs.World, +pose: Frame.Pose, +depth: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    done : Unit <- render_only.go(iterations, world, pose, depth)
    finished : Nat <- IO.now()
    IO.print(phase_line(label, size_at(depth), iterations, started, finished, 0))





# The whole frame: the tick, then the render, in the order the loop runs them. This
# is the number the 16.7 ms budget is judged on.
#
# The world is read out of the tick's own answer and put through the client's
# invalidation, which is exactly what the next `view` does, so a frame that follows a
# dig pays for the extraction and a frame that follows a step does not. `frame_cold`
# forces the extraction every iteration instead, so the cost of a world edit is
# measured rather than assumed away.
def client_edits(state: Play.Client) -> List<&2, WorldState.Edit>:
  Play.Client{player, pose, keys, edits, region, path, world, size} = state
  edits

def client_world(state: Play.Client) -> Slabs.World:
  Play.Client{player, pose, keys, edits, region, path, +world, size} = state
  world

def frame_world(cold: Bool, +carried: Slabs.World,
  +edits: List<&2, WorldState.Edit>) -> Slabs.World:
  match cold:
    case True{}:
      Slabs.world_built(edits)
    case False{}:
      carried

def frame_fold(next: Play.Client, world: Slabs.World, +pose: Frame.Pose, +hash: U32) -> U32:
  +z = F32.abs(eye_z_of(next))
  +image = render_with(world, pose)
  +digest : U32 = Voxel.fingerprint(image)
  released : Unit = Image.drop(image)
  fold_hash(fold_hash(hash, F32.to_u32(z)), digest)

def frame_step(+state: Play.Client, +first: Event, +second: Event,
  +edits: List<&2, WorldState.Edit>, +pose: Frame.Pose, +cold: Bool, +hash: U32) -> IO(U32):
  do IO<U32>:
    answer : Maybe<&1, Play.Client> <- Play.tick.events([first, second], state)
    +next : Play.Client <- client_or_die(answer)
    +world : Slabs.World = frame_world(cold,
      Slabs.world_for(client_world(next), client_edits(next)), edits)
    IO.pure(U32, frame_fold(next, world, pose, hash))

def frame.go(remaining: Nat, +state: Play.Client, +first: Event, +second: Event,
  +edits: List<&2, WorldState.Edit>, +pose: Frame.Pose, +cold: Bool, +hash: U32) -> IO(U32):
  match remaining:
    case 0n:
      IO.pure(U32, hash)
    case 1n+p:
      do IO<U32>:
        +next : U32 <- frame_step(state, first, second, edits, pose, cold, hash)
        frame.go(p, state, first, second, edits, pose, cold, next)

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

def clock_phase(+iterations: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +total : U32 <- clock.go(iterations, 0, 2166136261)
    consumed : Unit <- IO.print("consume=clock:" ++ U32.show(total))
    finished : Nat <- IO.now()
    IO.print(phase_line("clock", window_width(), iterations, started, finished, total))

def tick_phase(+label: String, +iterations: Nat, +state: Play.Client,
  +first: Event, +second: Event) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- tick.go(iterations, state, first, second, 2166136261)
    consumed : Unit <- IO.print("consume=" ++ label ++ ":" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line(label, window_width(), iterations, started, finished, digest))

def chunk_phase(+iterations: Nat, +edits: List<&2, WorldState.Edit>) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- chunk.go(iterations, edits, 2166136261)
    consumed : Unit <- IO.print("consume=region:" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line("region", window_width(), iterations, started, finished, digest))

def frame_phase(+label: String, +iterations: Nat, +state: Play.Client,
  +first: Event, +second: Event, +edits: List<&2, WorldState.Edit>,
  +pose: Frame.Pose, +cold: Bool) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +digest : U32 <- frame.go(iterations, state, first, second, edits, pose, cold, 2166136261)
    consumed : Unit <- IO.print("consume=" ++ label ++ ":" ++ U32.show(digest))
    finished : Nat <- IO.now()
    IO.print(phase_line(label, window_width(), iterations, started, finished, digest))

# The events a held movement key produces, and the events a look produces. Both are
# the client's real codes, in the shape the runtime hands the tick, so the client's
# own input fold is part of what the tick phase measures. A pair is a product and
# cannot be shared, so the two sets are passed on as four events.
#
# The action keys are deliberately not in a timed phase. Save is the one that reaches
# the filesystem — `tick.finish` takes `wants_save` through to `save_text.at`, so a
# timed press would measure the disk. A dig does not: it only extends the edit log, and
# the world is written when the player saves. (This line used to claim dig reached the
# filesystem too, which is why the dig frame had no timed phase at all; the dig path is
# covered by native/play_test.bend, and `frame_edited` measures it as a phase, because
# the phase forces the rebuild the dig causes without pressing the key.)
# The edit and save paths are covered by native/play_test.bend
# instead, and this file only times the two things a frame pays every tick.
type Events is Data:
  Events{first: Event, second: Event}

def held_events() -> Events:
  Events{Key{119, True{}}, Key{119, False{}}}

def look_events() -> Events:
  Events{Look{24.0, 0.0}, Key{Frame.dig_code(), False{}}}

def first_of(events: Events) -> Event:
  Events{first, second} = events
  first

def second_of(events: Events) -> Event:
  Events{first, second} = events
  second

def run_events(+state: Play.Client, +edits: List<&2, WorldState.Edit>,
  +pose: Frame.Pose, +world: Slabs.World, +held_first: Event, +held_second: Event,
  +action_first: Event, +action_second: Event) -> IO(Unit):
  do IO<Unit>:
    Unit <- clock_phase(7n)
    Unit <- tick_phase("tick_held", 200n, state, held_first, held_second)
    Unit <- tick_phase("tick_look", 200n, state, action_first, action_second)
    Unit <- chunk_phase(20n, edits)
    Unit <- extract_phase(40n, edits)
    +camera : Voxel.Camera = camera_of(pose)
    Unit <- faces_phase(40n, edits)
    Unit <- project_phase(40n, edits, camera, window_width())
    Unit <- grid_phase(20n, edits, camera, window_width())
    # The scatter builder against the row-major one at the shipping edge and at edge 8.
    # The walk is cheaper at a smaller edge and the scatter builder is dearer, and only
    # the walk is parallel; row-major removes the builder's random access entirely, so
    # if it is cheap enough here the smaller edge becomes worth taking. It is not.
    Unit <- grid_rm_phase("grid_rm16", 20n, edits, camera, window_width(), 16)
    Unit <- grid_rm_phase("grid_rm8", 20n, edits, camera, window_width(), 8)
    Unit <- pixel_phase(20n, edits, camera, window_width())
    # The walk cost probe: `bare` is the list iteration with nothing but the step,
    # `step` adds the seven-field destructure a pattern forces, `pixel` is the shipped
    # walk, and `one` is the same walk with the two halves of the box test folded into
    # one `Bool.and` and so one call in the reject path instead of two. All four visit
    # the same 695,808 candidates.
    Unit <- bare_phase(20n, edits, camera, window_width())
    Unit <- step_phase(20n, edits, camera, window_width())
    Unit <- one_phase(20n, edits, camera, window_width())
    Unit <- image_phase(20n, edits, camera, window_width())
    Unit <- render_phase("render", 20n, edits, world, pose, False{})
    Unit <- render_phase("render_cold", 20n, edits, world, pose, True{})
    # The sizes the resolution question is actually about, measured at the client's own
    # camera and region rather than extrapolated from a pixel count. The depth is an
    # exponent, so the renderer is square and a power of two: 512 is the largest
    # expressible step below the next order of magnitude.
    Unit <- render_at_phase("render_512", 2n, world, pose, 9n)
    Unit <- render_at_phase("render_256", 3n, world, pose, 8n)
    Unit <- render_at_phase("render_128", 10n, world, pose, 7n)
    Unit <- render_at_phase("render_64", 40n, world, pose, 6n)
    Unit <- render_at_phase("render_32", 100n, world, pose, 5n)
    # The same sizes without the fingerprint, which is the per-frame cost the window's
    # 16.67 ms tick is actually judged on.
    Unit <- render_only_phase("draw_512", 10n, world, pose, 9n)
    Unit <- render_only_phase("draw_256", 20n, world, pose, 8n)
    Unit <- render_only_phase("draw_128", 40n, world, pose, 7n)
    Unit <- render_only_phase("draw_64", 80n, world, pose, 6n)
    Unit <- render_only_phase("draw_32", 160n, world, pose, 5n)
    Unit <- render_only_phase("draw_1024", 4n, world, pose, 10n)
    Unit <- sky_only_phase("sky_1024", 4n, 10n, 1024)
    Unit <- sky_only_phase("sky_512", 10n, 9n, 512)
    Unit <- sky_only_phase("sky_256", 20n, 8n, 256)
    Unit <- frame_phase("frame_held", 20n, state, held_first, held_second, edits, pose, False{})
    Unit <- frame_phase("frame_look", 20n, state, action_first, action_second, edits, pose, False{})
    Unit <- frame_phase("frame_edited", 20n, state, held_first, held_second, edits, pose, True{})
    # The region dump runs after every timed phase, not among them. It builds a grid
    # per focal scale and per tile edge, and the allocation churn is enough to move the
    # phases that follow it by several percent, so a diagnostic that perturbs the thing
    # it measures has to run once the measuring is done.
    IO.print(facts_line(edits, camera, window_width()))
    IO.print("client-bench=pass size=" ++ U32.show(window_width())
      ++ " tile=" ++ U32.show(tile_edge())
      ++ " budget_ms=" ++ U32.show(U32.from_nat(Nat.div(1000n, 60n))))

def run_all(+state: Play.Client, +edits: List<&2, WorldState.Edit>, +pose: Frame.Pose,
  +world: Slabs.World, +held: Events, +action: Events) -> IO(Unit):
  +held_first : Event = first_of(held)
  +held_second : Event = second_of(held)
  +action_first : Event = first_of(action)
  +action_second : Event = second_of(action)
  run_events(state, edits, pose, world, held_first, held_second, action_first,
    action_second)

def run_phases(+state: Play.Client) -> IO(Unit):
  +pose : Frame.Pose = pose_of(state)
  +edits : List<&2, WorldState.Edit> = WorldState.empty()
  +world : Slabs.World = Slabs.world_built(edits)
  +held : Events = held_events()
  +action : Events = look_events()
  run_all(state, edits, pose, world, held, action)

def main() -> IO(Unit):
  do IO<Unit>:
    +region : PlayerProbe.Region <- benchmark_region()
    +state : Play.Client <- spawn_state(region)
    run_phases(state)
