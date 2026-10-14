import Base
import ./action.bend as Action
import ../world/digging.bend as Digging
import ./bag.bend as Bag
import ./body.bend as Body
import ./frame.bend as Frame
import ./hour.bend as Hour
import ./hud.bend as Hud
import ./save.bend as Migration
import ./net.bend as Net
import ./paint.bend as Paint
import ../world/player.bend as Player
import ./player.bend as PlayerProbe
import ./pointer.bend as Pointer
import ./scenery.bend as Scenery
import ./screen.bend as Screen
import ./size.bend as Size
import ./sky.bend as Sky
import ./slabs.bend as Slabs
import ./stash.bend as Stash
import ./stores.bend as Stores
import ./tag.bend as Tag
import ./debug.bend as Debug
import ../world/world.bend as World
import ../world/world_state.bend as WorldState

# The client alone: the player, the camera, the world it holds and the bag, one tick of them
# and one frame of them, and the save. It owns no game rule: the player transition is
# `Player.step`, the targeted cell is `Player.raycast`, the world is `WorldState.chunk`, the
# collision region and its storage guard are the player probe's, the camera and the input
# fold are the frame probe's, the image is the painter's, and the save format is the same
# `B2CW:1` the legacy importer reads and writes. What is here is the wiring, and only the
# wiring. A room's client is this one with `native/room.bend` in front of its tick and its
# view; the window is `native/client.bend`'s.

# The client is a few records, each the things that change together, so that a change to one
# of them lists that record's fields and not all of the client's.
#
# `Avatar` is who is playing: the rules' player state, the camera taken from it, and the keys
# held when the last tick ended, which is what this tick's key edges are against.
type Avatar is Data:
  Avatar{player: Player.State, pose: Frame.Pose, keys: U32}

# `Ground` is the world as the client holds it: the edit log, the collision region cut from
# it, the faces of the view region, where that region is, and what the last world update
# cost. `world_ms` is the F3 overlay's reading and nothing else: the tick writes it, the
# overlay reads it, and no rule turns on it. It lives here because it is a measurement of
# the world this record holds, not of the session.
type Ground is Data:
  Ground{edits: List<&2, WorldState.Edit>, region: PlayerProbe.Region, world: Slabs.World,
    home: Frame.Home, world_ms: U32}

# `Setup` is what the session was started with and the tick does not change. `hosted` says
# where the look comes from: `True` when `native/pointer.bend` is reading the pointer from the
# Windows host, `False` when the runtime's own grab is what measures it. `path` is where `T`
# saves, and `size` the window. `debug` is the one field the tick does change: F3 flips it.
type Setup is Data:
  Setup{hosted: Bool, path: String, size: Size.Size, debug: Bool}

# `clock` counts ticks from `Sky.clock_start`. It is the hour: the sky, the light and where
# the clouds have drifted to are rules on it, and nothing else reads it. It is not saved, so
# a session starts in the morning.
type Client is Data:
  Client{avatar: Avatar, ground: Ground, setup: Setup, bag: Bag.Bag, clock: U32, dig: Digging.Dig}

def avatar_of(client: Client) -> Avatar:
  Client{avatar, ground, setup, bag, clock, dig} = client
  avatar

def with_avatar(client: Client, avatar: Avatar) -> Client:
  Client{old, ground, setup, bag, clock, dig} = client
  Client{avatar, ground, setup, bag, clock, dig}

def ground_of(client: Client) -> Ground:
  Client{avatar, ground, setup, bag, clock, dig} = client
  ground

def with_ground(client: Client, ground: Ground) -> Client:
  Client{avatar, old, setup, bag, clock, dig} = client
  Client{avatar, ground, setup, bag, clock, dig}

def bag_of(client: Client) -> Bag.Bag:
  Client{avatar, ground, setup, bag, clock, dig} = client
  bag

def with_bag(client: Client, bag: Bag.Bag) -> Client:
  Client{avatar, ground, setup, old, clock, dig} = client
  Client{avatar, ground, setup, bag, clock, dig}

def size_of(client: Client) -> Size.Size:
  Client{avatar, ground, Setup{hosted, path, size, debug}, bag, clock, dig} = client
  size

def path_of(client: Client) -> String:
  Client{avatar, ground, Setup{hosted, path, size, debug}, bag, clock, dig} = client
  path

def hosting(client: Client, hosted: Bool) -> Client:
  Client{avatar, ground, Setup{old, path, size, debug}, bag, clock, dig} = client
  Client{avatar, ground, Setup{hosted, path, size, debug}, bag, clock, dig}

def player_of(client: Client) -> Player.State:
  Client{Avatar{player, pose, keys}, ground, setup, bag, clock, dig} = client
  player

def with_player(client: Client, player: Player.State) -> Client:
  Client{Avatar{old, pose, keys}, ground, setup, bag, clock, dig} = client
  Client{Avatar{player, pose, keys}, ground, setup, bag, clock, dig}

def pose_of(client: Client) -> Frame.Pose:
  Client{Avatar{player, pose, keys}, ground, setup, bag, clock, dig} = client
  pose

def keys_of(client: Client) -> U32:
  Client{Avatar{player, pose, keys}, ground, setup, bag, clock, dig} = client
  keys

def edits_of(client: Client) -> List<&2, WorldState.Edit>:
  Client{avatar, Ground{edits, region, world, home, world_ms}, setup, bag, clock, dig} = client
  edits

def region_of(client: Client) -> PlayerProbe.Region:
  Client{avatar, Ground{edits, region, world, home, world_ms}, setup, bag, clock, dig} = client
  region

def world_of(client: Client) -> Slabs.World:
  Client{avatar, Ground{edits, region, world, home, world_ms}, setup, bag, clock, dig} = client
  world

def home_of(client: Client) -> Frame.Home:
  Client{avatar, Ground{edits, region, world, home, world_ms}, setup, bag, clock, dig} = client
  home

def path() -> String:
  "native/client-world.b2cw"

# --- persistence -------------------------------------------------------------

def snapshot_edits(snapshot: Migration.Snapshot) -> List<&2, WorldState.Edit>:
  Migration.Snapshot{seed, edits} = snapshot
  edits

def saved_edits(maybe: Maybe<&2, Migration.Snapshot>) -> List<&2, WorldState.Edit>:
  match maybe:
    case Some{snapshot}:
      snapshot_edits(snapshot)
    case None{}:
      WorldState.empty()

def edits_from(text: String) -> List<&2, WorldState.Edit>:
  saved_edits(Migration.decode(text))

def load_text.done(pair: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (file, result) = pair
  match result:
    case Fail{error}:
      do IO<String>:
        shut : Unit <- File.close(file)
        return ""
    case Done{text}:
      do IO<String>:
        shut : Unit <- File.close(file)
        return text

def load_text(result: Result<&1, &1, U32 & String, File>, read_size: U32) -> IO(String):
  match result:
    case Fail{error}:
      IO.pure(String, "")
    case Done{file}:
      do IO<String>:
        read : File & Result<&1, &1, U32 & String, String> <- File.read(file, read_size)
        load_text.done(read)

def load_cap() -> Nat:
  262144n

def load_text.at(path: String) -> IO(String):
  do IO<String>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    load_text(opened, U32.from_nat(load_cap()))

def save_text.done(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (file, result) = pair
  match result:
    case Done{unit}:
      do IO<Unit>:
        shut : Unit <- File.close(file)
        IO.print("native-client: world saved")
    case Fail{error}:
      do IO<Unit>:
        shut : Unit <- File.close(file)
        IO.die(Unit, 1, "native-client: the world could not be written")

def save_text(file: File, text: String) -> IO(Unit):
  do IO<Unit>:
    written : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, text)
    save_text.done(written)

def save_text.at(path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "w"))
    save_text(file, text)

# How far the region's first cell is from the world's, along one axis: what a cell of the
# region is added to for its place in the world, which is where the clouds are.
def region_shift(home_chunk: Nat) -> F32:
  F32.from_nat(Nat.mul(home_chunk, World.chunk_size()))

# How far the movement window's first cell is from the world's origin. The player's own
# coordinates count from the window's first cell and a room's from the world's origin, which
# is the cell of world chunk 0.
def window_origin() -> F32:
  F32.from_nat(Nat.mul(PlayerProbe.window_origin_chunk(), World.chunk_size()))

# A room's other players as the painter takes them: where each stands in the region's own
# cells. `shift_x` and `shift_z` are the region's first cell in the world's coordinates.
def bodies.go(others: List<&2, Net.Other>, +shift_x: F32, +shift_z: F32,
  +acc: List<&2, Body.Body>) -> List<&2, Body.Body>:
  match others:
    case Nil{}:
      acc
    case Net.Other{id, name, Net.Place{x, y, z, yaw, pitch}, seen} <> rest:
      bodies.go(rest, shift_x, shift_z,
        Bool.pick(List<&2, Body.Body>, seen,
          Body.Body{Body.player_kind(), F32.sub(x, shift_x), y, F32.sub(z, shift_z), yaw} <> acc, acc))

# What the room simulates, the same way: a thing's kind is already the painter's.
def things.go(things: List<&2, Net.Thing>, +shift_x: F32, +shift_z: F32,
  acc: List<&2, Body.Body>) -> List<&2, Body.Body>:
  match things:
    case Nil{}:
      acc
    case Net.Thing{id, kind, count, x, y, z, yaw} <> rest:
      things.go(rest, shift_x, shift_z,
        Body.Body{kind, F32.sub(x, shift_x), y, F32.sub(z, shift_z), yaw} <> acc)

def bodies.at(others: List<&2, Net.Other>, things: List<&2, Net.Thing>, +shift_x: F32,
  +shift_z: F32) -> List<&2, Body.Body>:
  things.go(things, shift_x, shift_z, bodies.go(others, shift_x, shift_z, []))

def bodies(others: List<&2, Net.Other>, things: List<&2, Net.Thing>,
  home: Frame.Home) -> List<&2, Body.Body>:
  Frame.Home{hx, hz} = home
  bodies.at(others, things, F32.sub(region_shift(hx), window_origin()),
    F32.sub(region_shift(hz), window_origin()))

# How far over a player's feet its name is written: a little clear of its hair.
def tag_height() -> F32:
  2.2

# The names of the room's other players, each over where its player's head is in the
# region's cells. A player the room has not placed has nowhere to be named.
def labels.go(others: List<&2, Net.Other>, +shift_x: F32, +shift_z: F32,
  +acc: List<&2, Tag.Label>) -> List<&2, Tag.Label>:
  match others:
    case Nil{}:
      acc
    case Net.Other{id, name, Net.Place{x, y, z, yaw, pitch}, seen} <> rest:
      labels.go(rest, shift_x, shift_z,
        Bool.pick(List<&2, Tag.Label>, seen,
          Tag.Label{name, F32.sub(x, shift_x), F32.add(y, tag_height()), F32.sub(z, shift_z)} <> acc, acc))

def labels(others: List<&2, Net.Other>, home: Frame.Home) -> List<&2, Tag.Label>:
  Frame.Home{hx, hz} = home
  labels.go(others, F32.sub(region_shift(hx), window_origin()),
    F32.sub(region_shift(hz), window_origin()), [])

# The frame with a room's other players, mobs, villagers and dropped items in it, at the
# room's hour. `Paint` draws the window, under the overlay `Hud` makes of the bag and
# `Tag` makes of the players' names; `Face` still answers the pointer's ray and is what
# `native/paint_test.bend` holds the painter against. `clock` is the client's own ticks,
# which is where the clouds are, and `hour` the clock the sun is read from.
#
# `debug` is the diagnostics overlay's lines, already empty when F3 is off, so "the overlay
# is showing" is the same fact as "there is anything to draw" and needs no second flag.
def image_among(+world: Slabs.World, +pose: Frame.Pose, +depth: Nat, +bag: Bag.Bag, +health: U32,
  +food: U32, +clock: U32, +hour: U32, +others: List<&2, Net.Other>,
  things: List<&2, Net.Thing>, +mining: U32, debug: List<&2, String>) -> Image:
  +eye = Frame.view_eye(Frame.eye_of(pose), Slabs.w_home(world))
  +p : U32 = U32.shln((1 : U32), depth)
  Scenery.paint_among(Slabs.w_groups(world), eye, Frame.yaw_of(pose), Frame.pitch_of(pose), depth,
    Paint.quads.after(
      Screen.quads(bag, p,
        Debug.quads(debug, p, p,
          Hud.progress(mining, p,
            Hud.overlay(bag, p, health, food)))),
      Tag.quads(labels(others, Slabs.w_home(world)), eye, Frame.yaw_of(pose), Frame.pitch_of(pose), depth,
        Paint.QNil{})),
    region_shift(Frame.home_x(Slabs.w_home(world))),
    region_shift(Frame.home_z(Slabs.w_home(world))), clock, hour,
    bodies(others, things, Slabs.w_home(world)))

def image_at(+world: Slabs.World, +pose: Frame.Pose, +depth: Nat, bag: Bag.Bag, +health: U32,
  +food: U32, +clock: U32) -> Image:
  image_among(world, pose, depth, bag, health, food, clock, clock, [], [], 0, [])

# The frame at the hour a session starts, which is the one the benchmark prices.
def image_at_depth(+world: Slabs.World, +pose: Frame.Pose, +depth: Nat, bag: Bag.Bag, +health: U32,
  +food: U32) -> Image:
  image_at(world, pose, depth, bag, health, food, Sky.clock_start())

# The player's health and hunger as whole points, which is what the overlay counts in.
def points(+value: F32) -> U32:
  F32.to_u32(F32.ceil(F32.max(value, 0.0)))

def image_of(+world: Slabs.World, +pose: Frame.Pose, size: Size.Size, bag: Bag.Bag,
  player: Player.State, +clock: U32, +hour: U32, others: List<&2, Net.Other>,
  things: List<&2, Net.Thing>, mining: U32, debug: List<&2, String>) -> Image:
  Player.State{x, y, z, yaw, pitch, velocity_y, grounded, health, hunger, air, fall,
    poison} = player
  image_among(world, pose, Size.depth_of(size), bag, points(health), points(hunger), clock, hour,
    others, things, mining, debug)

# The client's frame with what else is in a room's world in it, at the room's hour.
#
# The world's own update happens in the tick now, not here: `Slabs.world_for` builds a
# chunk when one has come into view, and a viewer is a pure function of the state, so a
# build here could not be timed and the one number a player asking "why did it stutter"
# wants is exactly that. The tick measures it into `Ground.world_ms` and this reads it.
def view_among(state: Client, others: List<&2, Net.Other>, hour: Hour.Hour,
  things: List<&2, Net.Thing>) -> Client & Image:
  Client{Avatar{+player, +pose, keys}, Ground{+edits, region, +world, +home, +world_ms},
    Setup{+hosted, path, +size, +debug}, +bag, +clock, +dig} = state
  (Client{Avatar{player, pose, keys}, Ground{edits, region, world, home, world_ms},
      Setup{hosted, path, size, debug}, bag, clock, dig},
    image_of(world, pose, size, bag, player, clock, Hour.hour.clock(hour, clock), others, things,
      Digging.progress(dig), Debug.lines(debug, player, home, world_ms, size, clock)))
def view(state: Client) -> Client & Image:
  view_among(state, [], Hour.Unheard{}, [])

# --- the collision region ------------------------------------------------------
#
# What the player collides with and aims through: two chunks by two around the player,
# placed by `Frame.den_for` so the player is always at least six cells inside it. It is
# smaller than the view region because the player only touches what is near, and it is
# rebuilt whole whenever the edit log changes: at two by two that is under half what three
# by three cost. It is built from the edit log, so it has to be built again when the log
# changes, or a dug block stays in the way after it has left the frame.
def den_start() -> Frame.Home:
  Frame.den_for(Frame.Home{0n, 0n}, Frame.initial_player())

def collision_region(+edits: List<&2, WorldState.Edit>, den: Frame.Home) ->
  Maybe<&1, PlayerProbe.Region>:
  Frame.Home{x, z} = den
  PlayerProbe.checked_window_region(Frame.seed(), x, z, 2n, 2n, edits)

# Where a region is: its first window chunk on each axis.
def den_of(region: PlayerProbe.Region) -> Frame.Home:
  PlayerProbe.Region{blocks, origin_x, origin_y, origin_z, width, height, depth} = region
  Frame.Home{Nat.div(origin_x, World.chunk_size()), Nat.div(origin_z, World.chunk_size())}

def region_or(maybe: Maybe<&1, PlayerProbe.Region>, old: PlayerProbe.Region) ->
  PlayerProbe.Region:
  match maybe:
    case Some{region}:
      region
    case None{}:
      old

# A region the storage encoding cannot name is refused, and the old one stands: that is
# the far edge of the world, and the player meets it as a wall.
def region_for(unchanged: Bool, old: PlayerProbe.Region,
  +edits: List<&2, WorldState.Edit>, den: Frame.Home) -> PlayerProbe.Region:
  match unchanged:
    case True{}:
      old
    case False{}:
      region_or(collision_region(edits, den), old)

# The region for the player the tick just moved: the same one while the log is the same
# and the player is still well inside it.
def region_after(+old: PlayerProbe.Region, +before: List<&2, WorldState.Edit>,
  +after: List<&2, WorldState.Edit>, +den: Frame.Home) -> PlayerProbe.Region:
  region_for(Bool.and(Slabs.same_edits(before, after), Frame.same_home(den_of(old), den)), old,
    after, den)

# What the player carries and the world's chests and furnaces are saved beside the world,
# in a file of their own (`native/stash.bend`): the world's is a format other saves migrate
# into, and a bag is not part of it.
def stash_path(path: String) -> String:
  path ++ ".bag"

# `T` writes the world and the bag, each to a file of its own. The client carries on as it
# was: the bag is saved as it would be closed, and not closed.
def tick.saved(saving: Bool, +client: Client) -> IO(Maybe<Client>):
  match saving:
    case True{}:
      do IO<Maybe<Client>>:
        written : Unit <- save_text.at(path_of(client),
          Migration.encode(Migration.Snapshot{Frame.seed(), edits_of(client)}))
        stashed : Unit <- save_text.at(stash_path(path_of(client)), Stash.encode(Screen.closed(bag_of(client))))
        return Some{client}
    case False{}:
      IO.pure(Maybe<Client>, Some{client})

# What the tick decided, applied to the client it made: the client answers `None` to leave,
# which is how `App.loop` ends, and otherwise is saved first when the player asked.
def tick.finish(client: Client, saving: Bool, quitting: Bool) -> IO(Maybe<Client>):
  match quitting:
    case True{}:
      IO.pure(Maybe<Client>, None{})
    case False{}:
      tick.saved(saving, client)

# Where the staged step left the player, with the keys the tick ended on.
def moved(staged: Frame.Staged, mask: U32) -> Avatar:
  Frame.Staged{player, pose, changed} = staged
  Avatar{player, pose, mask}

# `App` hands the tick a `List<&1, Event>` and the frame probe folds a
# `List<&2, Event>`. This is the whole bridge: one pass that shares each event
# into a shared list and notes the window close, so the tick keeps the frame
# probe's input rule instead of a second copy of it.

type Folded is Data:
  Folded{events: List<&2, Event>, closing: Bool}

def is_close(event: Event) -> Bool:
  match event:
    case Close{}:
      True{}
    case _:
      False{}

# A close anywhere in the tick's events quits, and it is noticed in the same pass
# that shares them.
def closer(seen: Bool, event: Event) -> Bool:
  Bool.or(seen, is_close(event))

# The accumulator is prepended, so it comes out backwards and is reversed once at the
# end. Sharing is one way: the events arrive as a `List<&1, Event>` and the fold reads
# them as a `List<&2, Event>`, and each head is shared into the accumulator on the way.
#
# The order has to survive the pass because the fold reads it. `Window.frame` can hand
# a tick a press and the release of the same key together, and folding that pair
# backwards ends on the press: the key reads held with its release already spent, so
# it sticks for the rest of the session.
def share_events.go(events: List<&1, Event>, acc: List<&2, Event>, closing: Bool) -> Folded:
  match events:
    case Nil{}:
      Folded{List.reverse(&2, Event, acc), closing}
    case +h <> t:
      share_events.go(t, h <> acc, closer(closing, h))

def share_events(events: List<&1, Event>) -> Folded:
  share_events.go(events, Nil{}, False{})

# Out of a room the furnaces step here; in one they are the room's, and the store says so
# before the screen reads it.
def bag_ticked(roomed: Bool, +bag: Bag.Bag) -> Bag.Bag:
  match roomed:
    case True{}:
      Bag.with_store(bag, Stores.roomed(Bag.store_of(bag)))
    case False{}:
      Bag.with_store(bag, Stores.ticked(Bag.store_of(bag)))

# The turn with the screens' own tick applied to its bag, and the furnaces stepped.
def screened(turn: Action.Turn, +previous: U32, +mask: U32, +dx: F32, +dy: F32, +size: U32,
  roomed: Bool) -> Action.Turn:
  Action.Turn{edits, bag} = turn
  Action.Turn{edits, Screen.step(bag_ticked(roomed, bag), previous, mask, dx, dy, size)}

# The mask is read off that fold for the edge decisions, and the player transition
# and the pose come from the probe's own `advance`, so no rule is asked twice.
#
# `text` is what the host's pointer wrote since the last frame. `Pointer.events` decides what
# the fold reads: the host's one `Look` in place of the display's pointer events when the
# pointer is hosted, and the display's own events when it is not.
def tick.folded(folded: Folded, text: String, client: Client, +guarded: Bool,
  +roomed: Bool) -> IO(Maybe<Client>):
  Folded{shared, closing} = folded
  Client{Avatar{+player, +pose, +keys}, Ground{+edits, +region, world, +home, world_ms},
    Setup{+hosted, path, +size, debug}, +bag, +clock, dig} = client
  +heard : List<&2, Event> = Pointer.events(hosted, text, shared)
  # With the inventory screen open the player stands still and looks nowhere: the same
  # events move the screen's arrow and click its slots instead, and the body is stepped
  # with nothing held. The mask is still folded from every event, because the screen reads
  # its keys and buttons as edges of it, and so does the tick after the screen closes.
  +screen = Bag.is_open(bag)
  +folded_keys : Frame.Keys = Frame.input_from(heard, keys)
  +events : List<&2, Event> = Bool.pick(List<&2, Event>, screen, [], heard)
  # Seeded with `keys`, the mask the previous tick ended with. `Window.frame` hands a
  # tick only the events that arrived during that frame, so a frame with no key event
  # is the ordinary frame of a held key: folding from zero made movement ride X11's
  # auto-repeat instead of the loop, and made the action edges below fire on every
  # repeat rather than once per press. See `Frame.input_from`.
  +mask : U32 = Frame.keys_mask(folded_keys)
  +staged : Frame.Staged = Frame.advance_holding(player, events, Bool.pick(U32, screen, 0, keys),
    Frame.tick_dt(), region, Frame.origin_x(), Frame.origin_z(), pose)
  # The number keys pick the slot before the action reads it, so a slot chosen and used in
  # the same frame is the one used.
  #
  # `guarded` is a room's mob under the crosshair: the dig key is then a hit on it, which
  # the session sends, and the block behind it is left alone.
  #
  # A block comes away when the dig button has been held on it for as long as the rules say
  # it takes with what is in hand, and not on the press.
  +mined : Digging.Mined = Action.mining(Bool.and(Frame.digging(mask), Bool.and(Bool.not(guarded), Bool.not(screen))), dig, pose,
    region, player, edits, Bag.held_item(Bag.selecting(bag, events)))
  # The screen's own tick comes after the action reads the bag, so the press that opens
  # the screen acts on nothing and the click that the screen takes digs nothing.
  +acts : Action.Turn = screened(Action.acted(edits, Bag.selecting(bag, events), pose, region, player,
      Digging.mined_breaks(mined),
      Bool.and(Frame.wants_place(keys, mask), Bool.not(screen)), Size.width_of(size)),
    keys, mask, Frame.look_dx(folded_keys), Frame.look_dy(folded_keys), Size.width_of(size), roomed)
  # Both regions follow the player the tick just moved. The collision region is rebuilt
  # here when the log changed or the player left its middle; the faces are rebuilt by
  # `tick.world`, which is where the clock is.
  # F3 flips the overlay, and it is read whatever else the tick decided: the overlay is a
  # diagnostic, so it stays available with the screen open and while the player is falling.
  +shown : Bool = Bool.pick(Bool, debug, Bool.not(Frame.wants_debug(keys, mask)),
    Frame.wants_debug(keys, mask))
  tick.finish(
    Client{moved(staged, mask),
      Ground{Action.turn_edits(acts),
        region_after(region, edits, Action.turn_edits(acts),
          Frame.den_for(den_of(region), Frame.staged_player(staged))),
        world, Frame.home_for(home, Frame.staged_player(staged)), world_ms},
      Setup{hosted, path, size, shown}, Action.turn_bag(acts), U32.add(clock, 1), Digging.mined_dig(mined)},
    Bool.and(Frame.wants_save(keys, mask), Bool.not(screen)), Frame.quitting_from(closing, keys, mask, screen))

# The host's pointer is read once per tick, hosted or not: an unopened host has nothing to
# say, so the read is what keeps this one code path. `guarded` is a room's mob under the
# crosshair, and `roomed` says the client is in a room, where the world's chests and furnaces
# are the room's.
# The client's world update, and the clock that measures it.
#
# This used to happen in `view`, which cannot be timed: `App`'s view is a pure function of
# the state, and the only clock in the program is an effect. Moving the build here costs
# nothing - the tick already runs before the view every frame, and the world's home is
# already the one the tick just moved - and it buys the one reading that answers "why did
# it stutter": a frame that built a chunk is dearer than one that did not, and that
# difference is invisible until it is on screen. A client that is leaving is handed back
# untouched, because there is no frame left to draw.
def world.timed(+client: Client) -> IO(Client):
  Client{avatar, ground, setup, bag, clock, dig} = client
  Ground{edits, region, world, home, world_ms} = ground
  do IO<Client>:
    started : Nat <- IO.now()
    next : Slabs.World = Slabs.world_for(world, edits, home)
    finished : Nat <- IO.now()
    IO.pure(Client, Client{avatar,
      Ground{edits, region, next, home, U32.from_nat(Nat.sub(finished, started))},
      setup, bag, clock, dig})

def tick.world(answer: Maybe<&1, Client>) -> IO(Maybe<Client>):
  match answer:
    case Some{client}:
      do IO<Maybe<Client>>:
        timed : Client <- world.timed(client)
        IO.pure(Maybe<Client>, Some{timed})
    case None{}:
      IO.pure(Maybe<Client>, None{})

def tick.room(events: List<&1, Event>, client: Client, guarded: Bool, roomed: Bool) -> IO(Maybe<Client>):
  do IO<Maybe<Client>>:
    text : String <- Pointer.host_read()
    answer : Maybe<&1, Client> <- tick.folded(share_events(events), text, client, guarded, roomed)
    tick.world(answer)

def tick.events(events: List<&1, Event>, client: Client) -> IO(Maybe<Client>):
  tick.room(events, client, False{}, False{})

# --- start -------------------------------------------------------------------

def start.readied(player: Player.State, +pose: Frame.Pose, +region: PlayerProbe.Region,
  +edits: List<&2, WorldState.Edit>, +path: String, +size: Size.Size) -> IO(Client):
  # The world is built once here, from the edits the save carried, and every later
  # frame reads it back unless the tick changed the log. The bag is the one saved beside
  # the world, or the starting one when there is none.
  +world : Slabs.World = Slabs.world_built(edits, Frame.home_start())
  do IO<Client>:
    stash : String <- load_text.at(stash_path(path))
    return Client{Avatar{player, pose, 0}, Ground{edits, region, world, Frame.home_start(), 0},
      Setup{False{}, path, size, False{}}, Stash.decode(stash, Bag.start()), Sky.clock_start(), Digging.resting()}

def start.placed(+player: Player.State, region: PlayerProbe.Region,
  +edits: List<&2, WorldState.Edit>, +path: String, +size: Size.Size) -> IO(Client):
  pose = Frame.pose(player, Frame.origin_x(), Frame.origin_z())
  start.readied(player, pose, region, edits, path, size)

def start.spawned(maybe: Maybe<&1, Player.State>, region: PlayerProbe.Region,
  +edits: List<&2, WorldState.Edit>, +path: String, +size: Size.Size) -> IO(Client):
  match maybe:
    case Some{player}:
      start.placed(player, region, edits, path, size)
    case None{}:
      IO.die(Client, 1, "native-client: the spawn cell was refused")

# The spawn cell is a world rule, not a client choice, and this is the measured reason
# the client cannot ask for it yet.
#
# `World.spawn_cell` answers (25, 16, 9) for seed 1337. The region the client loads
# starts at chunk (1, 1), so that cell is local (9, 0): the minimum z edge. A camera at
# yaw 0 looks toward -z with zero rows of world in front of it, so the frame comes out
# all sky, and a dig ray leaves the region before it reaches anything, which fails the
# client's own save test on the cell it dug.
#
# Using it needs the region origin moved to chunk (0, 0), so the whole 48x48 world is
# loaded and the spawn cell has terrain on every side. That origin is also what the
# camera's eye is rebased onto, so moving it invalidates the frame probe's single-chunk
# render fixtures, which compare a one-chunk ray render against a sky control. Three
# chunks per axis at origin (0, 0) also built a 46,080-cell collision region and the
# machine stack overflowed, so the view region and the collision region have to be
# sized apart. That is the remaining work, and it is a region change, not a spawn swap.
def start.player(region: PlayerProbe.Region, +edits: List<&2, WorldState.Edit>,
  +path: String, +size: Size.Size) -> IO(Client):
  maybe = PlayerProbe.checked_create_player(25n, 25n, 9n)
  start.spawned(maybe, region, edits, path, size)

def start.region(maybe: Maybe<&1, PlayerProbe.Region>, +edits: List<&2, WorldState.Edit>,
  +path: String, +size: Size.Size) -> IO(Client):
  match maybe:
    case Some{region}:
      start.player(region, edits, path, size)
    case None{}:
      IO.die(Client, 1, "native-client: the collision region was refused")

def start.grid(+edits: List<&2, WorldState.Edit>, +size: Size.Size) -> IO(Client):
  region = collision_region(edits, den_start())
  start.region(region, edits, path(), size)

def start.edits_of(text: String, +size: Size.Size) -> IO(Client):
  edits = edits_from(text)
  start.grid(edits, size)

# A save that does not fit the read cap is refused rather than truncated. A
# truncated snapshot fails to decode, which would silently start a new world over
# a real one.
def oversized(cap: Nat, text: String) -> Bool:
  Nat.is_ge(String.length(text), cap)

def start.whole(too_large: Bool, text: String, +size: Size.Size) -> IO(Client):
  match too_large:
    case True{}:
      IO.die(Client, 1, "native-client: the saved world is too large to read")
    case False{}:
      start.edits_of(text, size)

def start.fits(+text: String, +size: Size.Size) -> IO(Client):
  start.whole(oversized(load_cap(), text), text, size)

def start(+size: Size.Size) -> IO(Client):
  do IO<Client>:
    text : String <- load_text.at(path())
    start.fits(text, size)

# `App.loop` is the prelude's own frame loop and it ends when the tick hands back no
# client, so the quit needs no fuel and no flag of its own: the client answers `Nothing`
# to leave. The client opens the window itself rather than through `App.run` only so
# the grab can be taken first; everything after that is the prelude's.
def app() -> App<Client>:
  App{view, tick.events}
