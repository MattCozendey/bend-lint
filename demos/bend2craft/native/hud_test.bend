import Base
import ./voxel.bend as Voxel
import ./paint.bend as Paint
import ./bag.bend as Bag
import ./hud.bend as Hud

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "hud: " ++ message)

# The overlay is read back out of a painted frame, at the positions the layout gives: an
# empty world under it, so every pixel that is not sky is the overlay's.
def size() -> U32:
  256

def camera() -> Voxel.Camera:
  Voxel.Camera.look(Voxel.Vec{0.0, 0.0, 0.0}, 0.0, 0.0)

def pixel(read: Array<U32> & U32) -> U32:
  (pixels, value) = read
  value

def at(+bag: Bag.Bag, +x: U32, +y: U32) -> U32:
  pixel(Paint.frame_pixels_with([], camera(), Voxel.projection_half(8n),
    F32.mul(1.5, Voxel.projection_half(8n)), size(), 8n,
    Hud.overlay(bag, size(), 20, 20), False{})[U32.add(U32.mul(y, size()), x)])

# The middle of a slot's item. A block is drawn as a small block seen from a corner, and
# this is the middle of its top face, which is the block's own colour; a tool is a square
# and this is inside it; and in an empty slot it is the well.
def middle(+index: U32) -> U32:
  U32.add(Hud.slot_x(size(), index), U32.div(Hud.edge(size()), 2))

def middle_y() -> U32:
  U32.add(Hud.slot_y(size()), U32.div(U32.mul(Hud.edge(size()), 2), 5))

def holding(+slot: Nat) -> Bag.Bag:
  Bag.Bag{Bag.slots_of(Bag.start()), slot, Bag.shut(), Bag.stores()}

# The starting bag is stone, dirt, grass, leaves, wood, a diamond pickaxe and three empty
# slots, and each slot shows its item.
def slots_show_their_items() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at(holding(0n), middle(0), middle_y()), Voxel.block_color(1)),
      "the first slot does not show stone")
    Unit <- check(U32.is_eq(at(holding(0n), middle(1), middle_y()), Voxel.block_color(2)),
      "the second slot does not show dirt")
    Unit <- check(U32.is_eq(at(holding(0n), middle(5), middle_y()), Hud.tool_color(19)),
      "the sixth slot does not show the diamond pickaxe")
    check(U32.is_eq(at(holding(0n), middle(8), middle_y()), Hud.well_color()),
      "the ninth slot is empty and does not show the well")

# The slot in hand has a white border and the others a dark one, and it follows the
# selection.
def the_held_slot_is_marked() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at(holding(0n), Hud.slot_x(size(), 0), Hud.slot_y(size())), Hud.white()),
      "the slot in hand does not have a white border")
    Unit <- check(U32.is_eq(at(holding(0n), Hud.slot_x(size(), 3), Hud.slot_y(size())),
      Hud.frame_color()), "a slot not in hand does not have a dark border")
    check(U32.is_eq(at(holding(3n), Hud.slot_x(size(), 3), Hud.slot_y(size())), Hud.white()),
      "the border did not follow the selection")

# The hotbar is inside the frame and centred: as much room to its left as to its right,
# within a pixel.
def the_bar_is_centred() -> IO(Unit):
  +left = Hud.slot_x(size(), 0)
  +right = U32.sub(size(), U32.add(Hud.slot_x(size(), 8), Hud.edge(size())))
  do IO<Unit>:
    Unit <- check(U32.is_le(U32.add(Hud.slot_y(size()), Hud.edge(size())), size()),
      "the hotbar runs off the bottom of the frame")
    check(Bool.and(U32.is_le(left, U32.add(right, 1)), U32.is_le(right, U32.add(left, 1))),
      "the hotbar is not centred")

# The crosshair marks the middle of the frame, where the aim is.
def the_crosshair_is_at_the_centre() -> IO(Unit):
  check(U32.is_eq(at(holding(0n), 128, 128), Hud.white()), "the centre of the frame is not the crosshair")

# A frame too small to draw a slot has no overlay at all, so it is all sky.
def a_small_frame_has_no_overlay() -> IO(Unit):
  check(U32.is_eq(Voxel.fingerprint(Paint.image.of(Paint.tiles_frame_with([], camera(),
      Voxel.projection_half(5n), F32.mul(1.5, Voxel.projection_half(5n)), 32, 5n, 5n,
      Hud.overlay(holding(0n), 32, 20, 20), False{}))),
    Voxel.fingerprint(Paint.image.of(Paint.tiles_frame_at([], camera(),
      Voxel.projection_half(5n), F32.mul(1.5, Voxel.projection_half(5n)), 32, 5n, 5n)))),
    "a 32x32 frame drew an overlay it has no room for")

# The overlay is painted the same in tiles as in one tile.
def the_overlay_survives_the_tiles() -> IO(Unit):
  check(U32.is_eq(Voxel.fingerprint(Paint.image.of(Paint.tiles_frame_with([], camera(),
      Voxel.projection_half(9n), F32.mul(1.5, Voxel.projection_half(9n)), 512, 9n, 6n,
      Hud.overlay(holding(2n), 512, 20, 20), False{}))),
    Voxel.fingerprint(Paint.image.of(Paint.tiles_frame_with([], camera(),
      Voxel.projection_half(9n), F32.mul(1.5, Voxel.projection_half(9n)), 512, 9n, 9n,
      Hud.overlay(holding(2n), 512, 20, 20), False{})))),
    "the overlay in 64-pixel tiles is not the overlay in one tile")

# The hand is in the lower right of the frame, and what it holds is drawn over it: a block
# in hand shows the block's colour there, and an empty hand shows the arm.
def the_hand_holds_the_item() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(at(holding(0n), 194, 160), Voxel.block_color(1)),
      "stone in hand is not drawn at the end of the arm")
    Unit <- check(U32.is_eq(at(holding(8n), 202, 205), Hud.skin()),
      "an empty hand does not show the arm")
    check(U32.is_eq(at(holding(0n), 202, 205), Hud.skin()),
      "the arm is not drawn under what it holds")

# A heart is lit for every two points of health, from the left.
def hearts_count_the_health(+bag: Bag.Bag, +health: U32, +x: U32, +y: U32) -> U32:
  pixel(Paint.frame_pixels_with([], camera(), Voxel.projection_half(8n),
    F32.mul(1.5, Voxel.projection_half(8n)), size(), 8n,
    Hud.overlay(bag, size(), health, 20), False{})[U32.add(U32.mul(y, size()), x)])

def heart_dot() -> U32:
  Hud.meter_dot(size())

def heart_x(+index: U32) -> U32:
  U32.add(U32.add(Hud.slot_x(size(), 0), U32.mul(index, U32.mul(heart_dot(), 6))),
    U32.mul(heart_dot(), 2))

def heart_y() -> U32:
  U32.add(U32.sub(Hud.slot_y(size()), U32.mul(heart_dot(), 7)), U32.mul(heart_dot(), 2))

def hearts_follow_the_health() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(hearts_count_the_health(holding(0n), 20, heart_x(9), heart_y()),
      Voxel.rgb(222, 44, 52)), "the tenth heart is not lit at full health")
    Unit <- check(U32.is_eq(hearts_count_the_health(holding(0n), 6, heart_x(2), heart_y()),
      Voxel.rgb(222, 44, 52)), "the third heart is not lit at six points")
    check(U32.is_eq(hearts_count_the_health(holding(0n), 6, heart_x(3), heart_y()),
      Hud.empty_color()), "the fourth heart is lit at six points")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- slots_show_their_items()
    Unit <- the_held_slot_is_marked()
    Unit <- the_bar_is_centred()
    Unit <- the_crosshair_is_at_the_centre()
    Unit <- the_hand_holds_the_item()
    Unit <- hearts_follow_the_health()
    Unit <- a_small_frame_has_no_overlay()
    Unit <- the_overlay_survives_the_tiles()
    IO.print("hud: slots, the held slot, the layout, the crosshair and the tiles passed")
