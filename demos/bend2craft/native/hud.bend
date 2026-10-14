import Base
import ../world/inventory.bend as Inventory
import ./voxel.bend as Voxel
import ./paint.bend as Paint
import ./bag.bend as Bag

# What the client paints over the world: the hand and what it holds, the hotbar, the
# hearts and the food, and a crosshair.
#
# Everything here is rectangles of whole pixels, handed to the painter ahead of the scene:
# the painter lays down the nearest thing first and never writes a pixel twice, so what is
# handed over first is what stays on top. The layout is a function of the frame's
# size and nothing else, so the same hotbar is drawn at every window the selector offers,
# and the tests read it back out of a painted frame at the positions these defs give.

def white() -> U32:
  Voxel.rgb(255, 255, 255)

def frame_color() -> U32:
  Voxel.rgb(34, 34, 38)

def well_color() -> U32:
  Voxel.rgb(74, 74, 80)

def bar_color() -> U32:
  Voxel.rgb(84, 214, 92)

# One slot's edge, the gap between two slots, a slot's border and a digit's pixel. A
# twelfth of the frame per slot puts nine of them across about four fifths of it.
def edge(+size: U32) -> U32:
  U32.div(size, 12)

def gap(+size: U32) -> U32:
  U32.div(edge(size), 8)

def border(+size: U32) -> U32:
  U32.max(U32.div(edge(size), 12), 1)

def dot(+size: U32) -> U32:
  U32.max(U32.div(edge(size), 20), 1)

def step(+size: U32) -> U32:
  U32.add(edge(size), gap(size))

def bar_width(+size: U32) -> U32:
  U32.add(U32.mul(edge(size), 9), U32.mul(gap(size), 8))

def slot_x(+size: U32, +index: U32) -> U32:
  U32.add(U32.div(U32.sub(size, bar_width(size)), 2), U32.mul(index, step(size)))

def slot_y(+size: U32) -> U32:
  U32.sub(U32.sub(size, edge(size)), U32.mul(U32.add(gap(size), 1), 2))

# What an item looks like in a slot: a block item is its block's colour, and a tool is the
# colour of what it is made of.
def tool_color(+item: U32) -> U32:
  Bool.pick(U32, Bool.or(U32.is_eq(item, 19), U32.is_eq(item, 36)), Voxel.rgb(92, 220, 214),
    Bool.pick(U32, Bool.or(U32.is_eq(item, 18), U32.is_eq(item, 35)), Voxel.rgb(216, 216, 220),
      Bool.pick(U32, Bool.or(U32.is_eq(item, 17), U32.is_eq(item, 34)), Voxel.rgb(128, 128, 132),
        Bool.pick(U32, Bool.or(U32.is_eq(item, 11), U32.is_eq(item, 33)), Voxel.rgb(150, 108, 64),
          Voxel.rgb(200, 180, 120)))))

def item_color(+item: U32) -> U32:
  Bool.pick(U32, U32.is_ne(Inventory.placed_block(item), 0),
    Voxel.block_color(Inventory.placed_block(item)), tool_color(item))

# --- a block, seen from a corner ---------------------------------------------------
#
# Three flat faces: the top in the block's own colour and the two sides in the shades
# `Voxel.shade_color` gives the sides that face along x and z. `cx`, `cy` is the middle of
# the block's near bottom edge, `w` half its width and `h` its height, all in pixels.
def cube(+cx: F32, +cy: F32, +w: F32, +h: F32, +color: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  +rise = F32.div(w, 2.0)
  +top = F32.sub(cy, h)
  Paint.quad(cx, F32.sub(top, rise), F32.add(cx, w), top, cx, F32.add(top, rise),
    F32.sub(cx, w), top, color, size,
    Paint.quad(F32.sub(cx, w), top, cx, F32.add(top, rise), cx, F32.add(cy, rise),
      F32.sub(cx, w), cy, Voxel.shade_color(color, 0), size,
      Paint.quad(cx, F32.add(top, rise), F32.add(cx, w), top, F32.add(cx, w), cy, cx,
        F32.add(cy, rise), Voxel.shade_color(color, 2), size, next)))

# What a slot shows for its item: a block as a small block, anything else as a square of
# its colour, and nothing for an empty slot.
def icon(full: Bool, block: Bool, +item: U32, +x: U32, +y: U32, +e: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match full block:
    case False{} _:
      next
    case True{} True{}:
      cube(F32.add(U32.to_f32(x), F32.div(U32.to_f32(e), 2.0)),
        F32.add(U32.to_f32(y), F32.mul(U32.to_f32(e), 0.70)), F32.mul(U32.to_f32(e), 0.28),
        F32.mul(U32.to_f32(e), 0.30), item_color(item), size, next)
    case True{} False{}:
      Paint.rect(U32.add(x, U32.div(e, 4)), U32.add(y, U32.div(e, 4)),
        U32.sub(e, U32.mul(U32.div(e, 4), 2)), U32.sub(e, U32.mul(U32.div(e, 4), 2)),
        item_color(item), size, next)

# --- digits ----------------------------------------------------------------------
#
# A digit is three dots wide and five high, as fifteen bits read left to right and top to
# bottom from the low bit.
def glyph(+digit: U32) -> U32:
  Bool.pick(U32, U32.is_eq(digit, 0), 31599,
    Bool.pick(U32, U32.is_eq(digit, 1), 29850,
      Bool.pick(U32, U32.is_eq(digit, 2), 29671,
        Bool.pick(U32, U32.is_eq(digit, 3), 31207,
          Bool.pick(U32, U32.is_eq(digit, 4), 18925,
            Bool.pick(U32, U32.is_eq(digit, 5), 31183,
              Bool.pick(U32, U32.is_eq(digit, 6), 31695,
                Bool.pick(U32, U32.is_eq(digit, 7), 18727,
                  Bool.pick(U32, U32.is_eq(digit, 8), 31727, 31215)))))))))

def lit(+mask: U32, index: Nat) -> Bool:
  U32.is_eq(U32.and(U32.shrn(mask, index), 1), 1)

def dot_at(on: Bool, +x: U32, +y: U32, +p: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match on:
    case True{}:
      Paint.rect(x, y, p, p, white(), size, next)
    case False{}:
      next

def digit.go(remaining: Nat, +index: U32, +mask: U32, +x: U32, +y: U32, +p: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match remaining:
    case 0n:
      next
    case 1n+r:
      dot_at(lit(mask, U32.to_nat(index)), U32.add(x, U32.mul(U32.mod(index, 3), p)),
        U32.add(y, U32.mul(U32.div(index, 3), p)), p, size,
        digit.go(r, U32.add(index, 1), mask, x, y, p, size, next))

def digit(+value: U32, +x: U32, +y: U32, +p: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  digit.go(15n, 0, glyph(value), x, y, p, size, next)

def tens(shown: Bool, +value: U32, +x: U32, +y: U32, +p: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match shown:
    case True{}:
      digit(value, x, y, p, size, next)
    case False{}:
      next

# A count of up to two digits, with its last dot at (`right`, `bottom`). One of anything is
# not counted, and a frame too small for a dot has no number.
def number(shown: Bool, +count: U32, +right: U32, +bottom: U32, +p: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match shown:
    case False{}:
      next
    case True{}:
      +y = U32.sub(bottom, U32.mul(5, p))
      +ones = U32.sub(right, U32.mul(3, p))
      tens(U32.is_ge(count, 10), U32.div(count, 10), U32.sub(ones, U32.mul(4, p)), y, p, size,
        digit(U32.mod(count, 10), ones, y, p, size, next))

# --- a slot ------------------------------------------------------------------------

# A tool's wear: a bar along the bottom of the well, as wide as the uses it has left.
def wear(+item: U32, +durability: U32, +x: U32, +y: U32, +well: U32, +p: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  +most = Inventory.tool_max_durability(item)
  Paint.rect(x, U32.sub(U32.add(y, well), p),
    Bool.pick(U32, U32.is_eq(most, 0), 0, U32.div(U32.mul(well, durability), U32.max(most, 1))),
    p, bar_color(), size, next)

# The border, the well, the item and its count, in that order so each is painted over the
# one before. The border of the slot in hand is white.
def slot(slot: Inventory.Slot, held: Bool, +x: U32, +y: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  Inventory.Slot{+item, +count, +durability} = slot
  +e = edge(size)
  +b = border(size)
  +p = dot(size)
  +well = U32.sub(e, U32.mul(b, 2))
  +full = U32.is_gt(count, 0)
  Paint.rect(x, y, e, e, Bool.pick(U32, held, white(), frame_color()), size,
    Paint.rect(U32.add(x, b), U32.add(y, b), well, well, well_color(), size,
      icon(full, U32.is_ne(Inventory.placed_block(item), 0), item, x, y, e, size,
        wear(Bool.pick(U32, full, item, 0), durability, U32.add(x, b), U32.add(y, b), well, p,
          size,
          number(Bool.and(U32.is_gt(count, 1), U32.is_ge(e, 10)), count,
            U32.sub(U32.add(x, e), U32.add(b, p)), U32.sub(U32.add(y, e), U32.add(b, p)), p,
            size, next)))))

def slots(remaining: Nat, list: List<&2, Inventory.Slot>, +index: U32, +selected: U32,
  +size: U32, next: Paint.Quads) -> Paint.Quads:
  match remaining list:
    case 1n+r head <> rest:
      slot(head, U32.is_eq(index, selected), slot_x(size, index), slot_y(size), size,
        slots(r, rest, U32.add(index, 1), selected, size, next))
    case _ _:
      next

# --- the crosshair -----------------------------------------------------------------
#
# Two bars through the middle of the frame: where a dig or a placement lands.
def crosshair(+size: U32, next: Paint.Quads) -> Paint.Quads:
  +c = U32.div(size, 2)
  +t = U32.max(U32.div(size, 256), 1)
  +arm = U32.max(U32.div(size, 64), 2)
  Paint.rect(U32.sub(c, arm), c, U32.add(U32.mul(arm, 2), t), t, white(), size,
    Paint.rect(c, U32.sub(c, arm), t, U32.add(U32.mul(arm, 2), t), white(), size, next))

# How far a dig has got, under the crosshair: a dark bar an eighth of the frame wide that
# fills with white, `amount` of it over 256. Nothing is drawn when no block is being dug.
def progress.at(shown: Bool, +amount: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match shown:
    case False{}:
      next
    case True{}:
      +wide = U32.max(U32.div(size, 8), 4)
      +tall = U32.max(U32.div(size, 128), 1)
      +x = U32.sub(U32.div(size, 2), U32.div(wide, 2))
      +y = U32.add(U32.div(size, 2), U32.mul(U32.max(U32.div(size, 64), 2), 2))
      Paint.rect(x, y, U32.div(U32.mul(wide, U32.min(amount, 256)), 256), tall, white(), size,
        Paint.rect(x, y, wide, tall, frame_color(), size, next))

def progress(+amount: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  progress.at(U32.is_gt(amount, 0), amount, size, next)

# --- hearts and food ---------------------------------------------------------------
#
# Ten of each above the hotbar, the hearts from its left end and the food from its right.
# A shape is five dots by five, read like a digit, and one is lit for every two points the
# player has.
def heart() -> U32:
  4685802

def morsel() -> U32:
  2342860

def empty_color() -> U32:
  Voxel.rgb(52, 44, 46)

def shape_dot(on: Bool, +x: U32, +y: U32, +p: U32, +color: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match on:
    case True{}:
      Paint.rect(x, y, p, p, color, size, next)
    case False{}:
      next

def shape(remaining: Nat, +index: U32, +mask: U32, +x: U32, +y: U32, +p: U32, +color: U32,
  +size: U32, next: Paint.Quads) -> Paint.Quads:
  match remaining:
    case 0n:
      next
    case 1n+r:
      shape_dot(lit(mask, U32.to_nat(index)), U32.add(x, U32.mul(U32.mod(index, 5), p)),
        U32.add(y, U32.mul(U32.div(index, 5), p)), p, color, size,
        shape(r, U32.add(index, 1), mask, x, y, p, color, size, next))

# A row of ten shapes stepping by `stride`, which is negative for a row that runs leftward.
def meter(remaining: Nat, +index: U32, +points: U32, +mask: U32, +x: U32, +forward: Bool,
  +y: U32, +p: U32, +color: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match remaining:
    case 0n:
      next
    case 1n+r:
      shape(25n, 0, mask,
        Bool.pick(U32, forward, U32.add(x, U32.mul(index, U32.mul(p, 6))),
          U32.sub(x, U32.mul(index, U32.mul(p, 6)))), y, p,
        Bool.pick(U32, U32.is_gt(points, U32.mul(index, 2)), color, empty_color()), size,
        meter(r, U32.add(index, 1), points, mask, x, forward, y, p, color, size, next))

# A meter's dot: a fourteenth of a slot, so ten shapes at six dots apiece are less than half
# the hotbar and the two rows do not meet in the middle.
def meter_dot(+size: U32) -> U32:
  U32.max(U32.div(edge(size), 14), 1)

def vitals(+health: U32, +food: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  +p = meter_dot(size)
  +y = U32.sub(slot_y(size), U32.mul(p, 7))
  meter(10n, 0, health, heart(), slot_x(size, 0), True{}, y, p, Voxel.rgb(222, 44, 52), size,
    meter(10n, 0, food, morsel(),
      U32.sub(U32.add(slot_x(size, 8), edge(size)), U32.mul(p, 5)), False{}, y, p,
      Voxel.rgb(196, 132, 62), size, next))

# --- the hand ----------------------------------------------------------------------
#
# The player's arm comes up from the bottom right of the frame, and what is in hand sits at
# the end of it: a block as a block, a tool as a handle with its head. All of it is a few
# flat quads in fractions of the frame, so it is the same hand at every window.
def skin() -> U32:
  Voxel.rgb(224, 172, 138)

def at(+size: U32, +fraction: F32) -> F32:
  F32.mul(U32.to_f32(size), fraction)

def arm(+size: U32, next: Paint.Quads) -> Paint.Quads:
  Paint.quad(at(size, 0.74), at(size, 1.0), at(size, 0.93), at(size, 1.0), at(size, 0.84),
    at(size, 0.70), at(size, 0.70), at(size, 0.74), skin(), size,
    Paint.quad(at(size, 0.93), at(size, 1.0), at(size, 0.98), at(size, 1.0), at(size, 0.88),
      at(size, 0.72), at(size, 0.84), at(size, 0.70), Voxel.shade_color(skin(), 0), size, next))

def tool(+item: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  Paint.quad(at(size, 0.74), at(size, 0.80), at(size, 0.78), at(size, 0.82), at(size, 0.66),
    at(size, 0.52), at(size, 0.63), at(size, 0.50), Voxel.rgb(122, 86, 50), size,
    Paint.quad(at(size, 0.55), at(size, 0.54), at(size, 0.60), at(size, 0.46), at(size, 0.74),
      at(size, 0.50), at(size, 0.72), at(size, 0.57), item_color(item), size, next))

def in_hand(full: Bool, block: Bool, +item: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match full block:
    case False{} _:
      next
    case True{} True{}:
      cube(at(size, 0.76), at(size, 0.76), at(size, 0.085), at(size, 0.10), item_color(item),
        size, next)
    case True{} False{}:
      tool(item, size, next)

def hand(held: Inventory.Slot, +size: U32, next: Paint.Quads) -> Paint.Quads:
  Inventory.Slot{+item, count, durability} = held
  arm(size, in_hand(U32.is_gt(count, 0), U32.is_ne(Inventory.placed_block(item), 0), item,
    size, next))

# The whole overlay for one frame. A frame too small for a slot border has none.
def overlay.at(room: Bool, +bag: Bag.Bag, +size: U32, +health: U32, +food: U32) -> Paint.Quads:
  match room:
    case True{}:
      # Built in the order a painter lays things down, each over the one before, and then
      # turned round: the frame is painted nearest first, so what is on top goes first.
      Paint.quads.rev(hand(Bag.held(bag), size, crosshair(size, vitals(health, food, size,
        slots(Bag.hotbar(), Bag.slots_of(bag), 0, U32.from_nat(Bag.selected_of(bag)), size,
          Paint.QNil{})))), Paint.QNil{})
    case False{}:
      Paint.QNil{}

# `health` and `food` are the player's, out of twenty.
def overlay(+bag: Bag.Bag, +size: U32, +health: U32, +food: U32) -> Paint.Quads:
  overlay.at(U32.is_ge(edge(size), 4), bag, size, health, food)
