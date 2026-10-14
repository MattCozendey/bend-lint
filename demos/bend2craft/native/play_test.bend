import Base
import ../world/player.bend as Player
import ../world/world.bend as World
import ../world/world_state.bend as WorldState
import ./voxel.bend as Voxel
import ./player.bend as PlayerProbe
import ./frame.bend as Frame
import ./bag.bend as Bag
import ../world/inventory.bend as Inventory
import ./face.bend as Face
import ./save.bend as Migration
import ./net.bend as Net
import ../world/entities.bend as Entities
import ./size.bend as Size
import ./action.bend as Action
import ./hour.bend as Hour
import ./play.bend as Play
import ./room.bend as Room
import ./slabs.bend as Slabs

# The client's own contracts, headless. Every game rule it leans on is already
# pinned by the probe it comes from (`Player.step`, `Player.raycast`, the region
# storage guard, the camera basis, the face renderer, the `B2CW:1` codec), so what
# is left here is the wiring the client itself owns: the fold between the player's
# encoded window and stored cells, the key edges, the raycast-to-edit path, the
# tick's decisions, the frame it hands the window, and a save that survives a
# restart.

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "play: " ++ message)

# The last assertion of a check reads as the check's result rather than as a
# bound step, so both spellings exist and neither has to bind a value it ignores.
def check(condition: Bool, message: String) -> IO(Unit):
  require(condition, message)

# The tick folds the events in the order the runtime queued them. A press and a
# release of one key inside a single frame is a tap, and folding that pair backwards
# ends on the press: the key reads held with its one release already spent, so it
# sticks for the rest of the session. It is also what a held movement key becomes if
# auto-repeat ever delivers a release and the next press in the same frame.
def check_tap_released(folded: Play.Folded) -> IO(Unit):
  Play.Folded{+shared, closing} = folded
  +mask : U32 = Frame.keys_mask(Frame.input(shared))
  do IO<Unit>:
    Unit <- require(Bool.not(closing), "a key tap was read as a window close")
    check(U32.is_eq(mask, 0), "a tap inside one frame left the key held")

def tap_in_one_frame_releases() -> IO(Unit):
  check_tap_released(Play.share_events([Key{119, True{}}, Key{119, False{}}]))

# --- the raycast-to-edit path ------------------------------------------------

# What the player's own raycast hit, still in the encoded window. The client is
# the only thing that can cross back to stored cells, so the test reads the aim
# through the client, exactly as the client does.
type Aim is Data:
  Aim{hit: Bool, hit_x: Nat, hit_y: Nat, hit_z: Nat, place_x: Nat, place_y: Nat,
    place_z: Nat, has_place: Bool}

type Cells is Type:
  Cells{hit_x: Maybe<&1, Nat>, hit_z: Maybe<&1, Nat>}

type Spot is Type:
  Spot{x: Maybe<&1, Nat>, y: Nat, z: Maybe<&1, Nat>}

type Spawned is Data:
  Spawned{edits: List<&2, WorldState.Edit>, region: PlayerProbe.Region}

def missed() -> Aim:
  Aim{False{}, 0n, 0n, 0n, 0n, 0n, 0n, False{}}

def landed(hit_x: Nat, hit_y: Nat, hit_z: Nat, place_x: Nat, place_y: Nat,
  place_z: Nat, has_place: Bool) -> Aim:
  Aim{True{}, hit_x, hit_y, hit_z, place_x, place_y, place_z, has_place}

def aim_of(result: Player.RayResult) -> Aim:
  match result:
    case Player.NoHit{}:
      missed()
    case Player.Hit{hit_x, hit_y, hit_z, place_x, place_y, place_z, has_place}:
      landed(hit_x, hit_y, hit_z, place_x, place_y, place_z, has_place)

def reached(aim: Aim) -> Bool:
  Aim{hit, hit_x, hit_y, hit_z, place_x, place_y, place_z, has_place} = aim
  hit

def hit_cells(hit: Bool, +x: Nat, +z: Nat) -> Cells:
  match hit:
    case True{}:
      Cells{PlayerProbe.stored_cell(x), PlayerProbe.stored_cell(z)}
    case False{}:
      Cells{None{}, None{}}

def hit_of(aim: Aim) -> Cells:
  Aim{hit, hit_x, hit_y, hit_z, _, _, _, _} = aim
  hit_cells(hit, hit_x, hit_z)

def place_spot(has_place: Bool, +x: Nat, +y: Nat, +z: Nat) -> Spot:
  match has_place:
    case True{}:
      Spot{PlayerProbe.stored_cell(x), y, PlayerProbe.stored_cell(z)}
    case False{}:
      Spot{None{}, y, None{}}

def place_of(aim: Aim) -> Spot:
  Aim{hit, hit_x, hit_y, hit_z, place_x, place_y, place_z, has_place} = aim
  place_spot(has_place, place_x, place_y, place_z)

def hit_height(aim: Aim) -> Nat:
  Aim{hit, hit_x, hit_y, hit_z, _, _, _, _} = aim
  hit_y

def read_at(edits: List<&2, WorldState.Edit>, mx: Maybe<&1, Nat>, y: Nat,
  mz: Maybe<&1, Nat>) -> U32:
  match mx mz:
    case Some{sx} Some{sz}:
      WorldState.block(edits, Frame.seed(), sx, y, sz)
    case _ _:
      0

def read_hit(edits: List<&2, WorldState.Edit>, cells: Cells, y: Nat) -> U32:
  Cells{hit_x, hit_z} = cells
  read_at(edits, hit_x, y, hit_z)

def read_spot(edits: List<&2, WorldState.Edit>, spot: Spot) -> U32:
  Spot{x, y, z} = spot
  read_at(edits, x, y, z)

# A dig has to empty the cell the player is looking at, and that cell has to have
# been solid: a dig that hit sky would otherwise pass a "the cell is empty now"
# check.
def dug_solid(+after: List<&2, WorldState.Edit>, +aim: Aim,
  +before: List<&2, WorldState.Edit>) -> Bool:
  +was = read_hit(before, hit_of(aim), hit_height(aim))
  now = read_hit(after, hit_of(aim), hit_height(aim))
  Bool.and(U32.is_eq(now, 0), Bool.not(U32.is_eq(was, 0)))

# Building puts the block in hand in the cell the hit face opens onto and leaves the cell
# it hit alone. It used to empty the hit cell too, which is the block beside, below or
# behind the new one vanishing whenever a block was placed.
def built_beside(+after: List<&2, WorldState.Edit>, +aim: Aim,
  +before: List<&2, WorldState.Edit>) -> Bool:
  now = read_spot(after, place_of(aim))
  +was = read_hit(before, hit_of(aim), hit_height(aim))
  kept = read_hit(after, hit_of(aim), hit_height(aim))
  Bool.and(U32.is_eq(now, 1), Bool.and(U32.is_ne(was, 0), U32.is_eq(kept, was)))

# The pickaxe is in the sixth slot of the starting bag, and by the rules it is what breaks
# stone.
def pickaxe_in_hand() -> Bag.Bag:
  Bag.Bag{Bag.slots_of(Bag.start()), 5n, Bag.shut(), Bag.stores()}

# The client's spawn pose, pitched down so the ray lands on the ground under the
# player. `Player.direction` points up for a positive pitch, so looking down is
# negative.
def spawn_pose() -> Frame.Pose:
  Frame.Pose{Voxel.Vec{9.5, 10.62, 9.5}, 0.0, F32.neg(1.0)}

def region_of(maybe: Maybe<&1, PlayerProbe.Region>) -> IO(PlayerProbe.Region):
  match maybe:
    case Some{region}:
      IO.pure(PlayerProbe.Region, region)
    case None{}:
      IO.die(PlayerProbe.Region, 1, "the spawn region was refused")

def spawned(edits: List<&2, WorldState.Edit>, region: PlayerProbe.Region) -> Spawned:
  Spawned{edits, region}

def spawn_world() -> IO(Spawned):
  do IO<Spawned>:
    +edits : List<&2, WorldState.Edit> <- IO.pure(List<&2, WorldState.Edit>, WorldState.empty())
    region : PlayerProbe.Region <- region_of(PlayerProbe.checked_from_world_state(
      Frame.seed(), Frame.chunk_x(), Frame.chunk_z(), Frame.columns(), Frame.rows(), edits))
    IO.pure(Spawned, spawned(edits, region))

def aimed_at(region: PlayerProbe.Region) -> Aim:
  aim_of(Action.aimed(spawn_pose(), region))

def check_targeting(spawned: Spawned) -> IO(Unit):
  Spawned{+edits, +region} = spawned
  +aim : Aim = aimed_at(region)
  dug = Action.turn_edits(Action.acted(edits, pickaxe_in_hand(), spawn_pose(), region,
    Frame.initial_player(), True{}, False{}, 128))
  +built : Action.Turn = Action.acted(edits, Bag.start(), spawn_pose(), region,
    Frame.initial_player(), False{}, True{}, 128)
  do IO<Unit>:
    Unit <- require(reached(aim), "the spawn pose did not reach the ground")
    Unit <- require(dug_solid(dug, aim, edits),
      "digging did not empty the cell the player is looking at")
    Unit <- require(built_beside(Action.turn_edits(built), aim, edits),
      "building did not put the stone in hand beside the hit cell and leave that cell alone")
    check(U32.is_eq(Inventory.count(Bag.slots_of(Action.turn_bag(built)), 1), 31),
      "building did not spend one stone from the bag")

def verify_targeting() -> IO(Unit):
  do IO<Unit>:
    spawned : Spawned <- spawn_world()
    check_targeting(spawned)

# --- the tick ----------------------------------------------------------------

type Peek is Data:
  Peek{eye_z: F32, edits: List<&2, WorldState.Edit>}

# The tick answers with `Nothing` to leave, which is how `App.loop` ends, so the tally
# holds one answer per case. A `Maybe` of a client is linear, so the record is linear
# too and each field is read exactly once.
type Tally is Type:
  Tally{before: Peek, after: Peek, released: Maybe<&1, Play.Client>,
    escaped: Maybe<&1, Play.Client>, closed: Maybe<&1, Play.Client>}

type Two is Data:
  Two{first: U32, second: U32}

# The client's entry point takes the size the selector chose. The tests below are about the
# tick, the frame, the dig and the save rather than about the selector (`native/size_test.bend`),
# so they all start at the shipped size through this one helper.
def started() -> IO(Play.Client):
  Play.start(Size.size_128())

def peek(+state: Play.Client) -> Peek:
  Peek{Frame.eye_z(Frame.eye_of(Play.pose_of(state))), Play.edits_of(state)}

def eye_z_of(peeked: Peek) -> F32:
  Peek{eye_z, edits} = peeked
  eye_z

def edits_of(+peeked: Peek) -> List<&2, WorldState.Edit>:
  Peek{eye_z, edits} = peeked
  edits

def aim_of_state(+state: Play.Client) -> Aim:
  aim_of(Action.aimed(Play.pose_of(state), Play.region_of(state)))

# The tick's own answer, read through the same question the loop asks, so the test and
# the loop cannot disagree about when the client stops.
def still_open(maybe: Maybe<&1, Play.Client>) -> Bool:
  Bool.not(Maybe.is_none(&1, Play.Client, maybe))

def client_or_die(maybe: Maybe<&1, Play.Client>) -> IO(Play.Client):
  match maybe:
    case Some{state}:
      IO.pure(Play.Client, state)
    case None{}:
      IO.die(Play.Client, 1, "the tick closed the client unexpectedly")

# A `Maybe` of a client is linear, so it can only be unwrapped once. These unwraps are
# also the assertions: a tick that quit instead of acting fails here rather than
# quietly writing nothing.
# A block comes away when the dig key has been held on it long enough, so a test digs by
# holding: the sixth slot's pickaxe is taken in hand and the key goes down, and the ticks
# that follow carry no event until the edit log grows, when the key is let go so that the
# block behind is not dug as well.
def log_length(state: Play.Client) -> Nat:
  List.length(&2, WorldState.Edit, edits_of(peek(state)))

def held.go(fuel: Nat, +before: Nat, +state: Play.Client) -> IO(Play.Client):
  match fuel:
    case 0n:
      IO.pure(Play.Client, state)
    case 1n+rest:
      do IO<Play.Client>:
        next : Maybe<&1, Play.Client> <- Play.tick.events(
          Bool.pick(List<&1, Event>, Nat.is_ne(log_length(state), before), [Key{Frame.dig_code(), False{}}], []), state)
        alive : Play.Client <- client_or_die(next)
        held.go(rest, before, alive)

def dig_held.from(+before: Nat, state: Play.Client) -> IO(Maybe<&1, Play.Client>):
  do IO<Maybe<&1, Play.Client>>:
    pressed : Maybe<&1, Play.Client> <- Play.tick.events([Key{54, True{}}, Key{Frame.dig_code(), True{}}], state)
    down : Play.Client <- client_or_die(pressed)
    held : Play.Client <- held.go(90n, before, down)
    return Some{held}

def dig_held(+state: Play.Client) -> IO(Maybe<&1, Play.Client>):
  dig_held.from(log_length(state), state)

def dug_or_die(maybe: Maybe<&1, Play.Client>) -> IO(Play.Client):
  match maybe:
    case Some{state}:
      IO.pure(Play.Client, state)
    case None{}:
      IO.die(Play.Client, 1, "the dig tick closed the client")

def saved_or_die(maybe: Maybe<&1, Play.Client>) -> IO(Play.Client):
  match maybe:
    case Some{state}:
      IO.pure(Play.Client, state)
    case None{}:
      IO.die(Play.Client, 1, "the save tick closed the client")

def require_closed(going: Bool) -> IO(Unit):
  match going:
    case True{}:
      IO.die(Unit, 1, "the tick kept the client running")
    case False{}:
      IO.pure(Unit, Unit{})

def expect_closed(maybe: Maybe<&1, Play.Client>) -> IO(Unit):
  require_closed(still_open(maybe))

def image_of(pair: Play.Client & Image) -> U32:
  (state, image) = pair
  Voxel.fingerprint(image)

def frame_of(state: Play.Client) -> U32:
  drawn = Play.view(state)
  image_of(drawn)

def two(first: U32, second: U32) -> Two:
  Two{first, second}

# One state has to render the same frame every time, which is the seam the
# window's per-frame `App.run` loop depends on.
def two_frames() -> IO(Two):
  do IO<Two>:
    +state : Play.Client <- started()
    first : U32 <- IO.pure(U32, frame_of(state))
    second : U32 <- IO.pure(U32, frame_of(state))
    IO.pure(Two, two(first, second))

def same_frame(frames: Two) -> IO(Unit):
  Two{first, second} = frames
  check(U32.is_eq(first, second),
    "the client rendered two different frames for one state")

def verify_frame() -> IO(Unit):
  do IO<Unit>:
    frames : Two <- two_frames()
    same_frame(frames)

# W walks toward the yaw 0 heading, which `Player.direction` puts at -z. Escape and
# the window manager's own close both end the loop, because the app stops when the
# tick hands back nothing.
# W walks toward the yaw 0 heading, which `Player.direction` puts at -z. Escape and
# the window manager's own close both end the loop.
def tally(before: Peek, after: Peek, released: Maybe<&1, Play.Client>,
  escaped: Maybe<&1, Play.Client>, closed: Maybe<&1, Play.Client>) -> Tally:
  Tally{before, after, released, escaped, closed}

def walk_ticks() -> IO(Tally):
  do IO<Tally>:
    +state : Play.Client <- started()
    walked : Maybe<&1, Play.Client> <- Play.tick.events([Key{119, True{}}], state)
    walked_state : Play.Client <- client_or_die(walked)
    released : Maybe<&1, Play.Client> <- Play.tick.events([Key{119, False{}}], state)
    escaped : Maybe<&1, Play.Client> <- Play.tick.events([Key{27, True{}}], state)
    closed : Maybe<&1, Play.Client> <- Play.tick.events([Close{}], state)
    IO.pure(Tally, tally(peek(state), peek(walked_state), released, escaped, closed))

def check_tick(tally_value: Tally) -> IO(Unit):
  Tally{before, after, released, escaped, closed} = tally_value
  do IO<Unit>:
    Unit <- require(F32.is_lt(eye_z_of(after), eye_z_of(before)),
      "W did not move the player toward the yaw 0 heading")
    Unit <- require(still_open(released),
      "the tick closed the client while it was still open")
    Unit <- expect_closed(escaped)
    expect_closed(closed)

def verify_tick() -> IO(Unit):
  do IO<Unit>:
    walked : Tally <- walk_ticks()
    check_tick(walked)

# --- persistence -------------------------------------------------------------

type Saved is Data:
  Saved{aim: Aim, before: Peek, kept: Peek}

def saved(aim: Aim, before: Peek, kept: Peek) -> Saved:
  Saved{aim, before, kept}

# Looking down before digging, because the raycast reaches 8.05 cells and the spawn
# pose's own pitch of -0.18 puts flat ground about 9.3 cells away, just out of reach.
# The old spawn sat inside a village, so a wall happened to be within reach and the
# save test passed by accident; at the world's own spawn cell there is nothing to hit
# until the player looks down, which is what a player does anyway.
def looked_down(state: Play.Client) -> IO(Play.Client):
  do IO<Play.Client>:
    looked : Maybe<&1, Play.Client> <- Play.tick.events(
      [Look{0.0, F32.neg(40.0)}], state)
    client_or_die(looked)

# One dig and one save, in that order, so the file has to carry the dig. A tick that
# stopped the client early fails here rather than quietly writing nothing. The aim is
# read from the state that has already looked down, so the cell the dig names and the
# cell the assertions check are the same one.
def dig_then_save(+state: Play.Client, +aim: Aim) -> IO(Saved):
  do IO<Saved>:
    dug : Maybe<&1, Play.Client> <- dig_held(state)
    dug_state : Play.Client <- dug_or_die(dug)
    written : Maybe<&1, Play.Client> <- Play.tick.events(
      [Key{Frame.save_code(), True{}}], dug_state)
    written_state : Play.Client <- saved_or_die(written)
    IO.pure(Saved, saved(aim, peek(state), peek(written_state)))

# The client starts on whatever its save file holds, so the test writes an empty
# snapshot first. Without this the second run of the test would start on the world
# the first run dug, and the dig below would have nothing solid left to remove.
def empty_world() -> IO(Unit):
  do IO<Unit>:
    Unit <- Play.save_text.at(Play.stash_path(Play.path()), "")
    Play.save_text.at(Play.path(),
      Migration.encode(Migration.Snapshot{Frame.seed(), WorldState.empty()}))

# A save that survives a restart: the file the client wrote decodes back to the
# same edits, and a fresh client starts on the world that was dug rather than on a
# new one.
def check_save(saved_value: Saved) -> IO(Unit):
  Saved{+aim, +before, +kept} = saved_value
  do IO<Unit>:
    text : String <- Play.load_text.at(Play.path())
    reloaded : List<&2, WorldState.Edit> <- IO.pure(List<&2, WorldState.Edit>,
      Play.edits_from(text))
    restarted : Play.Client <- started()
    Unit <- require(dug_solid(edits_of(kept), aim, edits_of(before)),
      "the saved world did not carry the dug cell")
    Unit <- require(dug_solid(reloaded, aim, edits_of(before)),
      "the saved file did not decode back to the dug cell")
    check(dug_solid(edits_of(peek(restarted)), aim, edits_of(before)),
      "the restarted client did not load the saved world")

def verify_save() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    +state : Play.Client <- started()
    +aimed_state : Play.Client <- looked_down(state)
    +aim : Aim <- IO.pure(Aim, aim_of_state(aimed_state))
    Unit <- require(reached(aim),
      "the spawn pose still reaches nothing after looking down")
    saved : Saved <- dig_then_save(aimed_state, aim)
    check_save(saved)

# --- the world's cache --------------------------------------------------------
#
# The client extracts the view region's faces once and keeps them, so a frame's world
# has to follow the edit log and nothing else. Two failures are possible and both are
# silent in a frame rate: a cache that never invalidates draws the pre-dig world for
# the rest of the session, and a cache that always invalidates is the per-frame
# extraction this replaced, which costs more than the rest of the frame put together.
# The first is caught by the faces and the frame changing after a dig; the second by a
# state that did not move handing back the very same faces.

# What one `Play.view` produced: a digest of the exposed faces the world holds, whether
# the world it returned already names the state's own edit log, and the frame it drew.
#
# The faces are digested rather than counted. A dig removes the faces the block exposed and
# exposes the faces it was hiding, and a block with three of each leaves the count where it
# was: that is the block under the spawn pose in the real world, and a count said the cache
# had not invalidated when it had.
def faces_digest(faces: List<&2, Face.Face>, +hash: U32) -> U32:
  match faces:
    case Nil{}:
      hash
    case Face.Face{x, y, z, dir, block} <> rest:
      faces_digest(rest, U32.mul(U32.xor(U32.mul(U32.xor(U32.mul(U32.xor(U32.mul(U32.xor(
        U32.mul(U32.xor(hash, x), 16777619), y), 16777619), z), 16777619),
        U32.from_nat(dir)), 16777619), block), 16777619))

type Viewed is Data:
  Viewed{faces: U32, matched: Bool, frame: U32}

type Cache is Data:
  Cache{before: Viewed, again: Viewed, after: Viewed}

# `Play.view` answers a pair, and a pair can only be taken apart by a def that takes
# it as a parameter, which is what `viewed` is: the client's own draw step, with the
# assertions read off what it handed back.
def viewed.of(+next: Play.Client, image: Image) -> Viewed:
  Viewed{faces_digest(Slabs.w_faces(Play.world_of(next)), 2166136261),
    Slabs.same_edits(Slabs.w_edits(Play.world_of(next)), Play.edits_of(next)),
    Voxel.fingerprint(image)}

def viewed(drawn: Play.Client & Image) -> Viewed:
  (next, image) = drawn
  viewed.of(next, image)

def cache_views() -> IO(Cache):
  do IO<Cache>:
    +state : Play.Client <- started()
    +before : Viewed = viewed(Play.view(state))
    +again : Viewed = viewed(Play.view(state))
    +looked : Play.Client <- looked_down(state)
    dug : Maybe<&1, Play.Client> <- dig_held(looked)
    dug_state : Play.Client <- dug_or_die(dug)
    IO.pure(Cache, Cache{before, again, viewed(Play.view(dug_state))})
def check_stable(before: Viewed, again: Viewed) -> IO(Unit):
  Viewed{faces, matched, frame} = before
  Viewed{again_faces, again_matched, again_frame} = again
  do IO<Unit>:
    Unit <- require(matched,
      "the world a frame was handed did not name the state's own edit log")
    Unit <- require(Bool.and(U32.is_eq(faces, again_faces), U32.is_eq(frame, again_frame)),
      "a state that did not move drew a different frame: the world cache is not stable")
    check(again_matched, "the world's edit log drifted from the state's")

def check_refreshed(before: Viewed, after: Viewed) -> IO(Unit):
  Viewed{faces, matched, frame} = before
  Viewed{after_faces, after_matched, after_frame} = after
  do IO<Unit>:
    Unit <- require(after_matched,
      "the world a frame was handed did not name the state's own edit log")
    Unit <- require(U32.is_ne(faces, after_faces),
      "the dig did not reach the world: the cache never invalidated")
    check(U32.is_ne(frame, after_frame),
      "the dig did not reach the frame: the world's faces were rebuilt but not used")

def check_cache(cache: Cache) -> IO(Unit):
  Cache{+before, +again, +after} = cache
  do IO<Unit>:
    Unit <- check_stable(before, again)
    check_refreshed(before, after)

def verify_cache() -> IO(Unit):
  do IO<Unit>:
    # The same reason `verify_save` writes an empty snapshot first: the client starts
    # on whatever its save holds, and the run before this one left a dug world there.
    Unit <- empty_world()
    cache : Cache <- cache_views()
    check_cache(cache)

# --- the collision region follows the edits -----------------------------------
#
# The player collides with, and aims through, the region the client carries. A dig that
# changed the edit log and left that region alone took the block out of the picture and
# left it in the way: the player walked into something the frame no longer showed, and the
# next dig hit the same cell again. So after a dig the aim has to land on another cell.
def same_cell(a: Aim, b: Aim) -> Bool:
  Aim{_, ax, ay, az, _, _, _, _} = a
  Aim{_, bx, by, bz, _, _, _, _} = b
  Bool.and(Nat.is_eq(ax, bx), Bool.and(Nat.is_eq(ay, by), Nat.is_eq(az, bz)))

type Digs is Data:
  Digs{before: Aim, after: Aim}

def dig_aims() -> IO(Digs):
  do IO<Digs>:
    +state : Play.Client <- started()
    dug : Maybe<&1, Play.Client> <- dig_held(state)
    dug_state : Play.Client <- dug_or_die(dug)
    return Digs{aim_of_state(state), aim_of_state(dug_state)}

def check_digs(digs: Digs) -> IO(Unit):
  Digs{+before, after} = digs
  do IO<Unit>:
    Unit <- require(reached(before), "the spawn pose aims at nothing, so there is no dig to test")
    check(Bool.not(same_cell(before, after)),
      "the dug cell is still in the collision region: the player would walk into a block the frame no longer shows")

def verify_region_follows_dig() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    digs : Digs <- dig_aims()
    check_digs(digs)

# --- the region follows the player --------------------------------------------
#
# A player who has walked past the middle chunk's margin has the region moved to their
# chunk by the tick: the collision region is rebuilt there at once, and the faces follow on
# the next view. A region that stayed behind is the invisible wall at the edge of the
# picture.
def walked_east(state: Play.Client) -> Play.Client:
  Play.with_player(state, PlayerProbe.create_player(60n, 25n, 9n))

type Moved is Data:
  Moved{home: Frame.Home, region_x: Nat, world: Frame.Home}

def region_x(region: PlayerProbe.Region) -> Nat:
  PlayerProbe.Region{blocks, origin_x, origin_y, origin_z, width, height, depth} = region
  origin_x

def moved_in(+next: Play.Client) -> Moved:
  Moved{Play.home_of(next), region_x(Play.region_of(next)), Slabs.w_home(Play.world_of(next))}

def moved_of(drawn: Play.Client & Image) -> Moved:
  (next, image) = drawn
  moved_in(next)

def moved_views() -> IO(Moved):
  do IO<Moved>:
    +state : Play.Client <- started()
    ticked : Maybe<&1, Play.Client> <- Play.tick.events([], walked_east(state))
    moved : Play.Client <- client_or_die(ticked)
    return moved_of(Play.view(moved))

def check_moved(moved: Moved) -> IO(Unit):
  Moved{home, region_x, world} = moved
  do IO<Unit>:
    # World cell 60 is in world chunk 3, and the region is five chunks with the player's in
    # the middle, so it starts at world chunk 1: window chunk 2049.
    Unit <- require(Frame.same_home(home, Frame.Home{2049n, 2047n}),
      "a player at cell 60 did not move the region to world chunk 1")
    # The collision region is two chunks by two with the player in its middle sixteen
    # cells: for a player at world cell 60 it starts at world cell 48.
    Unit <- require(Nat.is_eq(region_x, PlayerProbe.domain_cell(48n)),
      "the collision region did not follow the player to world cell 48")
    check(Frame.same_home(world, Frame.Home{2049n, 2047n}),
      "the faces were not rebuilt for the region's new place")

def verify_region_follows_player() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    moved : Moved <- moved_views()
    check_moved(moved)

# West of the world's origin the same thing has to happen, and that is the side storage
# spells differently: the chunk before chunk 0 is not chunk -1 but one counted from
# `World.negative_origin`. A region that stopped at the origin left the world ending
# twenty-five cells from the spawn.
def walked_west(state: Play.Client) -> Play.Client:
  Play.with_player(state, PlayerProbe.create_player(Nat.sub(World.negative_origin(), 11n), 25n, 9n))

type West is Data:
  West{home: Frame.Home, region_x: Nat, faces: U32, ground: U32, ruled: U32}

# The block the collision region holds one cell west of the origin, at the height of the
# world's own column there, beside what the cell rule says it is.
def west_at(home: Frame.Home, region: PlayerProbe.Region, world: Slabs.World) -> West:
  PlayerProbe.Region{blocks, +origin_x, origin_y, origin_z, width, height, depth} = region
  West{home, origin_x, Face.face_total(Slabs.w_faces(world)),
    Player.region_block(blocks, origin_x, origin_y, origin_z, width, height, depth,
      32767n, 3n, 32793n),
    World.block(Frame.seed(), Nat.sub(World.negative_origin(), 1n), 3n, 25n)}

def west_in(+next: Play.Client) -> West:
  west_at(Play.home_of(next), Play.region_of(next), Play.world_of(next))

def west_of(drawn: Play.Client & Image) -> West:
  (next, image) = drawn
  west_in(next)

def west_views() -> IO(West):
  do IO<West>:
    +state : Play.Client <- started()
    ticked : Maybe<&1, Play.Client> <- Play.tick.events([], walked_west(state))
    moved : Play.Client <- client_or_die(ticked)
    return west_of(Play.view(moved))

def check_west(west: West) -> IO(Unit):
  West{home, region_x, faces, +ground, ruled} = west
  do IO<Unit>:
    Unit <- require(Frame.same_home(home, Frame.Home{2045n, 2047n}),
      "a player eleven cells west of the origin did not move the region past it")
    Unit <- require(Nat.is_eq(region_x, 32736n),
      "the collision region did not follow the player west of the origin")
    Unit <- require(U32.is_gt(faces, 1000),
      "the region west of the origin has almost no faces: it was not generated")
    Unit <- require(U32.is_ne(ground, 0),
      "the collision region has no ground one cell west of the origin")
    check(U32.is_eq(ground, ruled),
      "the collision region west of the origin does not hold the world's own block")

def verify_region_follows_west() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    west : West <- west_views()
    check_west(west)

# --- a slab is its own chunk ----------------------------------------------------
#
# The view region's faces are kept per chunk. A region that moves one chunk over keeps the
# twenty slabs still in view and builds the five new ones one frame at a time, so the frame
# after the move holds twenty-one slabs and the fifth all twenty-five. An edit rebuilds the
# one slab it is in and leaves the others as they were.
def slab_count(world: Slabs.World) -> U32:
  U32.from_nat(List.length(&2, Slabs.Slab, Slabs.w_slabs(world)))

def moved_east() -> Frame.Home:
  Frame.Home{Nat.add(Frame.home_x(Frame.home_start()), 1n), Frame.home_z(Frame.home_start())}

# The world after `frames` more views of the moved region.
def after_frames(frames: Nat, +world: Slabs.World) -> Slabs.World:
  match frames:
    case 0n:
      world
    case 1n+rest:
      after_frames(rest, Slabs.world_for(world, WorldState.empty(), moved_east()))

def slabs_arrive_one_a_frame() -> IO(Unit):
  +start : Slabs.World = Slabs.world_built(WorldState.empty(), Frame.home_start())
  +first : Slabs.World = after_frames(1n, start)
  +second : Slabs.World = after_frames(1n, first)
  +fifth : Slabs.World = after_frames(3n, second)
  do IO<Unit>:
    Unit <- require(U32.is_eq(slab_count(start), 25), "the starting world is not twenty-five slabs")
    Unit <- require(U32.is_eq(slab_count(first), 21),
      "the frame after a move did not keep twenty slabs and build one")
    Unit <- require(U32.is_eq(slab_count(second), 22), "the second frame did not build one more slab")
    Unit <- require(U32.is_eq(slab_count(fifth), 25), "the fifth frame did not finish the region")
    check(U32.is_eq(slab_count(after_frames(1n, fifth)), 25),
      "a finished region changed on a frame nothing moved")

# The moved region, once it has all its slabs, is the region built there from nothing.
def a_moved_region_is_the_built_one() -> IO(Unit):
  +built : Slabs.World = Slabs.world_built(WorldState.empty(), moved_east())
  +moved : Slabs.World = after_frames(5n,
    Slabs.world_built(WorldState.empty(), Frame.home_start()))
  check(U32.is_eq(Face.face_total(Slabs.w_faces(moved)), Face.face_total(Slabs.w_faces(built))),
    "a region reached by moving does not hold the faces of the region built there")

def verify_slabs() -> IO(Unit):
  do IO<Unit>:
    Unit <- slabs_arrive_one_a_frame()
    a_moved_region_is_the_built_one()

# --- the bag follows the actions ----------------------------------------------
#
# A dig through the tick lands what the block drops in the bag, and the number key that
# picked the pickaxe moved the selection.
def bag_of(state: Play.Client) -> Bag.Bag:
  Play.bag_of(state)

type Bags is Data:
  Bags{before: Bag.Bag, after: Bag.Bag}

def dig_bags() -> IO(Bags):
  do IO<Bags>:
    +state : Play.Client <- started()
    +looked : Play.Client <- looked_down(state)
    dug : Maybe<&1, Play.Client> <- dig_held(looked)
    dug_state : Play.Client <- dug_or_die(dug)
    return Bags{bag_of(looked), bag_of(dug_state)}

# Everything in the bag, counted: whatever the block drops, the total goes up by one.
def held_total(slots: List<&2, Inventory.Slot>, +total: U32) -> U32:
  match slots:
    case Nil{}:
      total
    case slot <> rest:
      held_total(rest, U32.add(total, Inventory.slot_count_value(slot)))

def stacks(bag: Bag.Bag) -> U32:
  held_total(Bag.slots_of(bag), 0)

def check_bags(bags: Bags) -> IO(Unit):
  Bags{+before, +after} = bags
  do IO<Unit>:
    Unit <- require(Nat.is_eq(Bag.selected_of(after), 5n),
      "pressing 6 did not put the sixth slot in hand")
    check(U32.is_eq(stacks(after), U32.add(stacks(before), 1)),
      "the dug block did not land in the bag")

def verify_bag_follows_dig() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    bags : Bags <- dig_bags()
    check_bags(bags)

# --- the inventory screen ------------------------------------------------------
#
# `E` opens the screen. While it is open the player neither walks nor digs: a click is the
# screen's, a walk key moves nobody, and escape closes the screen and not the client, even
# while it is still held on the tick after.
def screen_open(maybe: Maybe<&1, Play.Client>) -> IO(Play.Client):
  match maybe:
    case Some{state}:
      IO.pure(Play.Client, state)
    case None{}:
      IO.die(Play.Client, 1, "client: a tick with the screen open closed the client")

def check_screen(+opened: Play.Client, +clicked: Play.Client, +walked: Play.Client,
  +escaped: Play.Client, +after: Play.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- check(Bag.is_open(bag_of(opened)), "E did not open the inventory screen")
    Unit <- check(Bag.is_open(bag_of(clicked)), "a click closed the screen")
    Unit <- check(List.is_empty(&2, WorldState.Edit, edits_of(peek(clicked))), "a click with the screen open dug a block")
    Unit <- check(F32.is_eq(eye_z_of(peek(walked)), eye_z_of(peek(opened))), "the player walked with the screen open")
    Unit <- check(Bool.not(Bag.is_open(bag_of(escaped))), "escape did not close the screen")
    check(Bool.not(Bag.is_open(bag_of(after))), "the screen reopened on its own")

def verify_screen() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    fresh : Play.Client <- started()
    looked : Play.Client <- looked_down(fresh)
    a : Maybe<&1, Play.Client> <- Play.tick.events([Key{101, True{}}], looked)
    +opened : Play.Client <- screen_open(a)
    b : Maybe<&1, Play.Client> <- Play.tick.events([Key{101, False{}}, Mouse{0, 0, 0, True{}}], opened)
    clicked : Play.Client <- screen_open(b)
    c : Maybe<&1, Play.Client> <- Play.tick.events([Key{119, True{}}], opened)
    walked : Play.Client <- screen_open(c)
    d : Maybe<&1, Play.Client> <- Play.tick.events([Key{101, False{}}, Key{27, True{}}], opened)
    +escaped : Play.Client <- screen_open(d)
    e : Maybe<&1, Play.Client> <- Play.tick.events([], escaped)
    after : Play.Client <- screen_open(e)
    check_screen(opened, clicked, walked, escaped, after)

def used_in(roomed: Bool, state: Play.Client) -> IO(Maybe<&1, Play.Client>):
  match roomed:
    case True{}:
      Play.tick.room([Key{Frame.place_code(), True{}}], state, False{}, True{})
    case False{}:
      Play.tick.events([Key{Frame.place_code(), True{}}], state)

# The place key on a block that has a screen opens it and places nothing. The block is put
# where the player is looking, as a room would put it. Each opens in a room as out of one.
def block_at.cells(cells: Cells, y: Nat, block: U32) -> List<&2, WorldState.Edit>:
  Cells{hit_x, hit_z} = cells
  match hit_x hit_z:
    case Some{x} Some{z}:
      [WorldState.make_edit(x, y, z, block)]
    case _ _:
      []

def block_at(+aim: Aim, block: U32) -> List<&2, WorldState.Edit>:
  block_at.cells(hit_of(aim), hit_height(aim), block)

def used_on(+block: U32, +want: U32, roomed: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    fresh : Play.Client <- started()
    +looked : Play.Client <- looked_down(fresh)
    used : Maybe<&1, Play.Client> <- used_in(roomed, Room.absorbed(looked, block_at(aim_of_state(looked), block)))
    +opened : Play.Client <- screen_open(used)
    Unit <- check(U32.is_eq(Bag.mode_of(bag_of(opened)), want), "the place key on block " ++ U32.show(block) ++ " did not leave screen " ++ U32.show(want) ++ " open")
    check(Bool.or(U32.is_eq(want, 0), Nat.is_eq(List.length(&2, WorldState.Edit, edits_of(peek(opened))), 1n)),
      "the place key on a block with a screen placed a block")

def verify_table() -> IO(Unit):
  do IO<Unit>:
    Unit <- used_on(World.crafting_table_block(), 2, False{})
    Unit <- used_on(26, 3, False{})
    Unit <- used_on(11, 4, False{})
    Unit <- used_on(World.crafting_table_block(), 2, True{})
    Unit <- used_on(26, 3, True{})
    used_on(1, 0, False{})

# The save key writes the bag beside the world, and a client started after it carries what
# the one that saved carried: the block the dig put in the bag is still there.
def check_kept(+saved: Play.Client, +again: Play.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_gt(stacks(bag_of(saved)), stacks(Bag.start())), "the dig put nothing in the bag")
    check(U32.is_eq(stacks(bag_of(again)), stacks(bag_of(saved))), "a client started after a save does not carry what was saved")

def verify_bag_is_saved() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    fresh : Play.Client <- started()
    looked : Play.Client <- looked_down(fresh)
    dug : Maybe<&1, Play.Client> <- dig_held(looked)
    dug_state : Play.Client <- dug_or_die(dug)
    written : Maybe<&1, Play.Client> <- Play.tick.events([Key{Frame.save_code(), True{}}], dug_state)
    +saved : Play.Client <- saved_or_die(written)
    +again : Play.Client <- started()
    Unit <- check_kept(saved, again)
    empty_world()

# A press digs nothing: the block is still there a tick later, and gone once the key has
# been held as long as the rules say stone takes a diamond pickaxe.
def check_takes_time(+pressed: Play.Client, +held: Play.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- check(List.is_empty(&2, WorldState.Edit, edits_of(peek(pressed))), "one tick of the dig key took a block away")
    check(Nat.is_eq(log_length(held), 1n), "holding the dig key did not take exactly one block away")

def verify_digging_takes_time() -> IO(Unit):
  do IO<Unit>:
    Unit <- empty_world()
    fresh : Play.Client <- started()
    +looked : Play.Client <- looked_down(fresh)
    one : Maybe<&1, Play.Client> <- Play.tick.events([Key{54, True{}}, Key{Frame.dig_code(), True{}}], looked)
    +pressed : Play.Client <- client_or_die(one)
    dug : Maybe<&1, Play.Client> <- dig_held(looked)
    +held : Play.Client <- dug_or_die(dug)
    check_takes_time(pressed, held)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- tap_in_one_frame_releases()
    Unit <- verify_targeting()
    Unit <- verify_tick()
    Unit <- verify_frame()
    Unit <- verify_cache()
    Unit <- verify_region_follows_dig()
    Unit <- verify_region_follows_player()
    Unit <- verify_region_follows_west()
    Unit <- verify_slabs()
    Unit <- verify_bag_follows_dig()
    Unit <- verify_save()
    Unit <- verify_screen()
    Unit <- verify_table()
    Unit <- verify_bag_is_saved()
    Unit <- verify_digging_takes_time()
    IO.print("play: fold, targeting, tick, frame, world cache, save, the inventory screen and digging passed")

#|play: fold, targeting, tick, frame, world cache, save, the inventory screen and digging passed