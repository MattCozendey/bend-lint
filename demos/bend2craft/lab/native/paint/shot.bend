import Base
import ../../../world/world_state.bend as WorldState
import ../../../native/player.bend as PlayerProbe
import ../../../native/voxel.bend as Voxel
import ../../../native/frame.bend as Frame
import ../../../native/scenery.bend as Scenery
import ../../../native/sky.bend as Sky
import ../../../native/bag.bend as Bag
import ../../../native/hud.bend as Hud
import ../../../native/net.bend as Net
import ../../../native/paint.bend as Paint
import ../../../native/tag.bend as Tag
import ../../../native/screen.bend as Screen
import ../../../native/stores.bend as Stores
import ../../../world/inventory.bend as Inventory
import ../../../native/play.bend as Play
import ../../../native/slabs.bend as Slabs

# The client's frame as numbers, so a picture can be looked at without a window.
#
# Each view is painted the way `Play.image_at` paints it — the same faces, the same
# camera, the same overlay, the same hour — as one tile, and printed as a `view=` line
# followed by a line of its pixels, row by row. `lab/native/paint/shot.sh` turns each into a
# PNG.
#
# The first views are the benchmark's: the spawn, which is inside a house facing a wall, and
# open ground east of it looking each way. The rest are from above the trees, where a
# picture shows how far the world goes, and at other hours of the day.

def pixels_text(cells: List<&1, U32>, acc: String) -> String:
  match cells:
    case Nil{}:
      acc
    case +cell <> rest:
      pixels_text(rest, U32.show(cell) ++ " " ++ acc)

# The pixels last to first, so each is put in front of the text so far and the walk is a loop.
def frame_text(frame: Array<U32>) -> String:
  pixels_text(List.reverse(&1, U32, Array.to_list(~U32, frame)), "")

def frame_at(+world: Slabs.World, +eye: Voxel.Vec, +pose: Frame.Pose, +depth: Nat, +clock: U32,
  +others: List<&2, Net.Other>, things: List<&2, Net.Thing>, +bag: Bag.Bag) -> Array<U32>:
  Scenery.pixels_among(Slabs.w_groups(world), eye, Frame.yaw_of(pose), Frame.pitch_of(pose), depth,
    Paint.quads.after(
      Screen.quads(bag, U32.shln((1 : U32), depth), Hud.overlay(bag, U32.shln((1 : U32), depth), 20, 20)),
      Tag.quads(Play.labels(others, Slabs.w_home(world)), eye, Frame.yaw_of(pose), Frame.pitch_of(pose),
        depth, Paint.QNil{})),
    Play.region_shift(Frame.home_x(Slabs.w_home(world))),
    Play.region_shift(Frame.home_z(Slabs.w_home(world))), clock, clock,
    Play.bodies(others, things, Slabs.w_home(world)))

def frame_of(+world: Slabs.World, +pose: Frame.Pose, +depth: Nat, +clock: U32,
  others: List<&2, Net.Other>, things: List<&2, Net.Thing>) -> Array<U32>:
  frame_at(world, Frame.view_eye(Frame.eye_of(pose), Slabs.w_home(world)), pose, depth, clock, others,
    things, Bag.start())

# The inventory screen open over a view: a log in the crafting grid, which shows the planks
# it would make, and the arrow carrying the rest of the logs over a slot of the rows.
def with_grid(bag: Bag.Bag, grid: List<&2, Inventory.Slot>) -> Bag.Bag:
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, old}, store} = bag
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store}

def crafting() -> Bag.Bag:
  Screen.aimed(
    Screen.step(Screen.aimed(Screen.step(Screen.aimed(Screen.opened(Bag.start(), 512), 4, 512), 0, Frame.left_bit(), 0.0, 0.0, 512), 36, 512),
      0, Frame.right_bit(), 0.0, 0.0, 512),
    22, 512)

# The crafting table's screen with a stone pickaxe laid out on it.
def table_screen() -> Bag.Bag:
  with_grid(Screen.aimed(Screen.opened_as(Bag.start(), Screen.table(), 512), 45, 512),
    [Inventory.make_slot(1, 1, 0), Inventory.make_slot(1, 1, 0), Inventory.make_slot(1, 1, 0),
      Inventory.make_slot(0, 0, 0), Inventory.make_slot(9, 1, 0), Inventory.make_slot(0, 0, 0),
      Inventory.make_slot(0, 0, 0), Inventory.make_slot(9, 1, 0), Inventory.make_slot(0, 0, 0)])

# A chest's screen with half the stone moved into it.
def chest_screen() -> Bag.Bag:
  Screen.aimed(
    Screen.step(Screen.aimed(Screen.step(Screen.aimed(Screen.opened_at(Bag.start(), Screen.chest(), 30n, 9n, 25n, 512), 0, 512),
        0, Frame.right_bit(), 0.0, 0.0, 512), 48, 512),
      0, Frame.left_bit(), 0.0, 0.0, 512),
    13, 512)

def ticks(remaining: Nat, +store: Bag.Store) -> Bag.Store:
  match remaining:
    case 0n:
      store
    case 1n+rest:
      ticks(rest, Stores.ticked(store))

def burning.at(+loaded: Bag.Bag) -> Bag.Bag:
  Screen.aimed(Bag.with_store(loaded, ticks(660n, Bag.store_of(loaded))), 57, 512)

# A furnace's screen eleven seconds after sand and coal went in: one glass made, the second
# on its way.
def furnace_screen() -> Bag.Bag:
  burning.at(
    Screen.step(Screen.aimed(
      Screen.step(Screen.aimed(
        Screen.step(Screen.aimed(
          Screen.step(Screen.aimed(Screen.opened_at(Bag.with_slots(Bag.start(),
              Inventory.replace_at(Inventory.replace_at(Bag.slots_of(Bag.start()), 2n, Inventory.make_slot(6, 12, 0)),
                3n, Inventory.make_slot(14, 9, 0))), Screen.furnace(), 30n, 9n, 25n, 512), 2, 512),
            0, Frame.left_bit(), 0.0, 0.0, 512), 55, 512),
          0, Frame.left_bit(), 0.0, 0.0, 512), 3, 512),
        0, Frame.left_bit(), 0.0, 0.0, 512), 56, 512),
      0, Frame.left_bit(), 0.0, 0.0, 512))

def shot_screen(name: String, +world: Slabs.World, +pose: Frame.Pose, +clock: U32, bag: Bag.Bag) -> IO(Unit):
  do IO<Unit>:
    head : Unit <- IO.print("view=" ++ name ++ " size=512")
    IO.print(frame_text(frame_at(world, Frame.view_eye(Frame.eye_of(pose), Slabs.w_home(world)), pose, 9n,
      clock, [], [], bag)))

# A view with a room's other players in it, and what the room simulates, where the room
# would say they stand.
def shot_among(name: String, +world: Slabs.World, +pose: Frame.Pose, +clock: U32,
  others: List<&2, Net.Other>, things: List<&2, Net.Thing>) -> IO(Unit):
  do IO<Unit>:
    head : Unit <- IO.print("view=" ++ name ++ " size=512")
    IO.print(frame_text(frame_of(world, pose, 9n, clock, others, things)))

def shot(name: String, +world: Slabs.World, +pose: Frame.Pose, +clock: U32) -> IO(Unit):
  shot_among(name, world, pose, clock, [], [])

# One of each thing a room simulates, east of the outdoor camera and turned every way: the
# six kinds of mob, a villager of each robe, and three items on the ground.
def creatures() -> List<&2, Net.Thing>:
  [Net.Thing{0, 1, 1, 60.5, 9.0, 40.0, 1.5708}, Net.Thing{0, 2, 1, 61.5, 9.0, 43.5, 4.7124},
    Net.Thing{0, 3, 1, 63.5, 9.0, 38.5, 0.7854}, Net.Thing{0, 4, 1, 65.5, 9.0, 42.5, 4.7124},
    Net.Thing{0, 5, 1, 67.5, 9.0, 39.5, 3.1416}, Net.Thing{0, 6, 1, 59.5, 9.0, 42.5, 2.3562},
    Net.Thing{0, 11, 1, 64.5, 9.0, 45.0, 0.0}, Net.Thing{0, 12, 1, 69.5, 9.0, 41.5, 0.0},
    Net.Thing{0, 1001, 1, 59.5, 9.0, 41.0, 0.0}, Net.Thing{0, 1002, 1, 60.0, 9.0, 41.6, 0.0},
    Net.Thing{0, 1005, 1, 60.6, 9.0, 41.2, 0.0}]

# Four players east of the outdoor camera, in the world's own coordinates as a room sends
# them: one close and facing the camera, one side on, one with its back turned, and one far
# enough for the air to show.
def others() -> List<&2, Net.Other>:
  [Net.Other{1, "Ana", Net.Place{60.5, 9.0, 41.5, 4.7124, 0.0}, True{}}, Net.Other{2, "Bia", Net.Place{63.5, 9.0, 44.0, 0.0, 0.0}, True{}},
    Net.Other{3, "Caio", Net.Place{67.5, 9.0, 39.5, 1.5708, 0.0}, True{}}, Net.Other{4, "Duda", Net.Place{86.5, 9.0, 42.5, 4.7124, 0.0}, True{}}]

def spawn_pose() -> Frame.Pose:
  Frame.pose(PlayerProbe.create_player(25n, 25n, 9n), Frame.origin_x(), Frame.origin_z())

def outdoor_pose(+yaw: F32, +pitch: F32) -> Frame.Pose:
  Frame.Pose{Voxel.Vec{40.5, 10.62, 25.5}, yaw, pitch}

# From above the trees, which is where a picture shows how far the world goes.
def high_pose(+yaw: F32, +pitch: F32) -> Frame.Pose:
  Frame.Pose{Voxel.Vec{40.5, 17.5, 25.5}, yaw, pitch}

def morning() -> U32:
  Sky.clock_start()

def main() -> IO(Unit):
  do IO<Unit>:
    +world : Slabs.World = Slabs.world_built(WorldState.empty(), Frame.home_start())
    +outside : Slabs.World = Slabs.world_built(WorldState.empty(), Frame.Home{2048n, 2047n})
    a : Unit <- shot("spawn", world, spawn_pose(), morning())
    b : Unit <- shot("north", outside, outdoor_pose(0.0, 0.0), morning())
    c : Unit <- shot("east", outside, outdoor_pose(1.5708, 0.0), morning())
    d : Unit <- shot("south", outside, outdoor_pose(3.1416, 0.0), morning())
    e : Unit <- shot("west", outside, outdoor_pose(4.7124, 0.0), morning())
    f : Unit <- shot("down", outside, outdoor_pose(0.7854, F32.neg(0.6)), morning())
    g : Unit <- shot("up", outside, outdoor_pose(0.7854, 0.5), morning())
    h : Unit <- shot("vista", outside, high_pose(0.7854, F32.neg(0.32)), morning())
    i : Unit <- shot("lake", outside, high_pose(5.4, F32.neg(0.3)), morning())
    j : Unit <- shot("noon", outside, high_pose(3.1416, 0.75), 10800)
    k : Unit <- shot("sunset", outside, high_pose(4.7124, F32.neg(0.05)), 20600)
    l : Unit <- shot("dusk", outside, high_pose(5.4, F32.neg(0.2)), 22300)
    m : Unit <- shot("night", outside, high_pose(5.4, 0.1), 31000)
    n : Unit <- shot("dawn", outside, high_pose(1.5708, F32.neg(0.05)), 500)
    o : Unit <- shot_among("players", outside, outdoor_pose(1.5708, 0.0), morning(), others(), [])
    p : Unit <- shot_among("players-night", outside, outdoor_pose(1.5708, 0.0), 31000, others(), [])
    q : Unit <- shot_among("creatures", outside, outdoor_pose(1.5708, 0.0), morning(), [], creatures())
    r : Unit <- shot_screen("inventory", outside, outdoor_pose(1.5708, 0.0), morning(), crafting())
    s : Unit <- shot_screen("inventory-empty", outside, outdoor_pose(1.5708, 0.0), morning(), Screen.opened(Bag.start(), 512))
    t : Unit <- shot_screen("table", outside, outdoor_pose(1.5708, 0.0), morning(), table_screen())
    u : Unit <- shot_screen("chest", outside, outdoor_pose(1.5708, 0.0), morning(), chest_screen())
    v : Unit <- shot_screen("furnace", outside, outdoor_pose(1.5708, 0.0), morning(), furnace_screen())
    IO.print("shot=done")
