import Base
import ../world/inventory.bend as Inventory
import ./voxel.bend as Voxel
import ./frame.bend as Frame
import ./paint.bend as Paint
import ./bag.bend as Bag
import ./hud.bend as Hud
import ./screen.bend as Screen
import ./stores.bend as Stores
import ../world/furnace.bend as Furnace

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "screen: " ++ message)

# A window 512 across, where a unit of the panel is two pixels and the panel is in the
# middle with eighty pixels to each side.
def size() -> U32:
  512

# The slots are where the original's are: the hotbar along the bottom, three rows above it
# from the left, the grid's four cells at the top right and what they make beside them.
def the_slots_are_where_the_original_puts_them() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(1, 0), 8), U32.is_eq(Screen.slot_gy(1, 0), 142)), "the first hotbar slot is not at (8, 142)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(1, 8), 152), U32.is_eq(Screen.slot_gy(1, 8), 142)), "the last hotbar slot is not at (152, 142)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(1, 9), 8), U32.is_eq(Screen.slot_gy(1, 9), 84)), "the first slot of the rows is not at (8, 84)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(1, 35), 152), U32.is_eq(Screen.slot_gy(1, 35), 120)), "the last slot of the rows is not at (152, 120)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(1, 36), 98), U32.is_eq(Screen.slot_gy(1, 36), 18)), "the grid's first cell is not at (98, 18)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(1, 40), 116), U32.is_eq(Screen.slot_gy(1, 40), 36)), "the grid's last cell is not at (116, 36)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(1, 45), 154), U32.is_eq(Screen.slot_gy(1, 45), 28)), "what the grid makes is not at (154, 28)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(2, 36), 30), U32.is_eq(Screen.slot_gy(2, 36), 17)), "the crafting table's first cell is not at (30, 17)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(2, 44), 66), U32.is_eq(Screen.slot_gy(2, 44), 53)), "the crafting table's last cell is not at (66, 53)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(2, 45), 124), U32.is_eq(Screen.slot_gy(2, 45), 35)), "what the crafting table makes is not at (124, 35)")
    Unit <- check(Bool.and(Bool.not(Screen.present(1, 38)), Screen.present(2, 38)), "the third cell of the first row is in the inventory's grid, or not in the table's")
    Unit <- check(Nat.is_eq(Screen.grid_index(39), 3n), "the grid's second row is not the rules' second row")
    Unit <- check(U32.is_eq(Screen.px(size(), 18), 36), "a unit is not two pixels in a window twice the panel's width")
    Unit <- check(U32.is_eq(Screen.left(size()), 80), "the panel is not in the middle of the window")
    check(U32.is_eq(Screen.px(128, 176), 128), "a window narrower than the panel does not squeeze it to fit")

def open_bag() -> Bag.Bag:
  Screen.opened(Bag.start(), size())

def held_of(bag: Bag.Bag) -> Inventory.Slot:
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store} = bag
  held

def grid_of(bag: Bag.Bag) -> List<&2, Inventory.Slot>:
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store} = bag
  grid

def slot_of(bag: Bag.Bag, +index: Nat) -> Inventory.Slot:
  Bag.held.of(Inventory.lookup(Bag.slots_of(bag), index))

def holds(slot: Inventory.Slot, want_item: U32, want_count: U32) -> Bool:
  Inventory.Slot{item, count, durability} = slot
  Bool.and(U32.is_eq(item, want_item), U32.is_eq(count, want_count))

# The arrow is over the slot it was put on, and over nothing between two slots.
def the_arrow_finds_its_slot() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Screen.hover(Screen.aimed(open_bag(), 0, size()), size()), 0), "the arrow on the first hotbar slot is not over it")
    Unit <- check(U32.is_eq(Screen.hover(Screen.aimed(open_bag(), 22, size()), size()), 22), "the arrow on a slot of the rows is not over it")
    Unit <- check(U32.is_eq(Screen.hover(Screen.aimed(open_bag(), 45, size()), size()), 45), "the arrow on what the grid makes is not over it")
    Unit <- check(U32.is_eq(Screen.hover(open_bag(), size()), Screen.nowhere()), "the arrow in the middle of the window is over a slot")
    check(U32.is_eq(Screen.hit(1, U32.to_f32(U32.sub(Screen.at_x(size(), 8), 1)), U32.to_f32(Screen.at_y(size(), 142)), size()), Screen.nowhere()),
      "a pixel left of the first slot is in it")

def e() -> U32:
  Frame.key_bit(Screen.key())

# The screen's key opens it and closes it, on the press and not while it is held; escape
# closes it; and the pointer moves the arrow only while it is open, and never off the window.
def the_key_opens_and_closes() -> IO(Unit):
  do IO<Unit>:
    +opened : Bag.Bag = Screen.step(Bag.start(), 0, e(), 0.0, 0.0, size())
    Unit <- check(Bag.is_open(opened), "the screen's key did not open it")
    Unit <- check(Bag.is_open(Screen.step(opened, e(), e(), 0.0, 0.0, size())), "a key still held closed the screen")
    Unit <- check(Bool.not(Bag.is_open(Screen.step(opened, 0, e(), 0.0, 0.0, size()))), "the screen's key did not close it")
    Unit <- check(Bool.not(Bag.is_open(Screen.step(opened, 0, Frame.key_bit(27), 0.0, 0.0, size()))), "escape did not close the screen")
    Unit <- check(Bool.not(Bag.is_open(Screen.step(Bag.start(), 0, Frame.left_bit(), 0.0, 0.0, size()))), "a click opened the screen")
    Unit <- check(F32.is_eq(Screen.desk_x(Bag.desk_of(Screen.step(opened, 0, 0, 10.0, 0.0, size()))), 266.0), "ten pixels of pointer did not move the arrow ten pixels")
    Unit <- check(F32.is_eq(Screen.desk_x(Bag.desk_of(Screen.step(opened, 0, 0, 9000.0, 0.0, size()))), 511.0), "the arrow left the window")
    check(F32.is_eq(Screen.desk_x(Bag.desk_of(Screen.step(Bag.start(), 0, 0, 10.0, 0.0, size()))), 0.0), "the pointer moved the arrow of a shut screen")

def left_on(bag: Bag.Bag, +id: U32) -> Bag.Bag:
  Screen.step(Screen.aimed(bag, id, size()), 0, Frame.left_bit(), 0.0, 0.0, size())

def right_on(bag: Bag.Bag, +id: U32) -> Bag.Bag:
  Screen.step(Screen.aimed(bag, id, size()), 0, Frame.right_bit(), 0.0, 0.0, size())

# The starting bag's first slot is thirty-two stone. A left click takes it onto the arrow,
# a second puts it down in another slot, and a right click takes half.
def a_click_moves_a_stack() -> IO(Unit):
  do IO<Unit>:
    +taken : Bag.Bag = left_on(open_bag(), 0)
    Unit <- check(Bool.and(holds(held_of(taken), 1, 32), holds(slot_of(taken, 0n), 0, 0)), "a left click did not take the stack onto the arrow")
    +put : Bag.Bag = left_on(taken, 20)
    Unit <- check(Bool.and(holds(held_of(put), 0, 0), holds(slot_of(put, 20n), 1, 32)), "a second click did not put the stack down")
    +halved : Bag.Bag = right_on(open_bag(), 0)
    Unit <- check(Bool.and(holds(held_of(halved), 1, 16), holds(slot_of(halved, 0n), 1, 16)), "a right click did not take half")
    Unit <- check(holds(held_of(left_on(open_bag(), 30)), 0, 0), "a click on an empty slot put something on the arrow")
    check(holds(slot_of(Screen.step(Screen.aimed(open_bag(), 0, size()), Frame.left_bit(), Frame.left_bit(), 0.0, 0.0, size()), 0n), 1, 32),
      "a button still held clicked again")

# The fifth slot is eight logs. One log in the grid's first cell would make four planks;
# taking them spends the log and puts them on the arrow.
def the_grid_crafts() -> IO(Unit):
  do IO<Unit>:
    +holding : Bag.Bag = left_on(open_bag(), 4)
    +placed : Bag.Bag = right_on(holding, 36)
    Unit <- check(Bool.and(holds(held_of(placed), 5, 7), holds(Bag.held.of(Inventory.lookup(grid_of(placed), 0n)), 5, 1)), "a right click did not put one log in the grid")
    Unit <- check(holds(Inventory.craft_preview(grid_of(placed)), 8, 4), "a log in the grid does not show four planks")
    Unit <- check(holds(held_of(left_on(placed, 45)), 5, 7), "planks were taken onto an arrow that carries logs")
    +freed : Bag.Bag = left_on(placed, 4)
    +made : Bag.Bag = left_on(freed, 45)
    Unit <- check(holds(held_of(made), 8, 4), "the planks are not on the arrow")
    check(holds(Bag.held.of(Inventory.lookup(grid_of(made), 0n)), 0, 0), "the log was not spent")

def table_bag() -> Bag.Bag:
  Screen.opened_as(Bag.start(), Screen.table(), size())

# The crafting table shows the whole grid. Three stone over a column of two sticks is a
# pickaxe, which the inventory's grid has no room for: here it is made and taken. The
# starting bag has no sticks, so the grid is laid out by hand.
def stick() -> Inventory.Slot:
  Inventory.make_slot(9, 1, 0)

def stone() -> Inventory.Slot:
  Inventory.make_slot(1, 1, 0)

def pick_grid() -> List<&2, Inventory.Slot>:
  [stone(), stone(), stone(), Screen.empty(), stick(), Screen.empty(), Screen.empty(), stick(), Screen.empty()]

def with_grid(bag: Bag.Bag, grid: List<&2, Inventory.Slot>) -> Bag.Bag:
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, old}, store} = bag
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store}

def the_table_crafts_three_by_three() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(U32.is_eq(Screen.hover(Screen.aimed(table_bag(), 44, size()), size()), 44), "the arrow on the table's last cell is not over it")
    Unit <- check(U32.is_eq(Screen.hover(Screen.aimed(Screen.aimed(table_bag(), 44, size()), 0, size()), size()), 0), "the arrow on the table's hotbar is not over it")
    +laid : Bag.Bag = with_grid(table_bag(), pick_grid())
    Unit <- check(holds(Inventory.craft_preview(grid_of(laid)), 17, 1), "three stone over two sticks do not show a stone pickaxe")
    +made : Bag.Bag = left_on(laid, 45)
    Unit <- check(holds(held_of(made), 17, 1), "the pickaxe is not on the arrow")
    Unit <- check(U32.is_eq(Inventory.slot_durability(held_of(made)), Inventory.tool_max_durability(17)), "the pickaxe was not made whole")
    +put : Bag.Bag = right_on(left_on(table_bag(), 0), 38)
    check(holds(Bag.held.of(Inventory.lookup(grid_of(put), 2n)), 1, 1), "a click on the table's third cell did not put a stone in it")

def chest_bag() -> Bag.Bag:
  Screen.opened_at(Bag.start(), Screen.chest(), 30n, 9n, 25n, size())

def in_chest(bag: Bag.Bag, +index: Nat) -> Inventory.Slot:
  Bag.held.of(Inventory.lookup(Stores.chest_shown(Bag.store_of(bag)), index))

# A chest's screen is the bag's slots under a row of nine. A stack carried from the bag goes
# into the chest and stays there when the screen is closed, at the cell the chest stands in.
def a_chest_keeps_what_it_is_given() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(3, 46), 8), U32.is_eq(Screen.slot_gy(3, 46), 18)), "the chest's first slot is not at (8, 18)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(3, 54), 152), U32.is_eq(Screen.slot_gy(3, 54), 18)), "the chest's last slot is not at (152, 18)")
    Unit <- check(Bool.and(Screen.present(3, 46), Bool.and(Bool.not(Screen.present(3, 36)), Bool.not(Screen.present(1, 46)))), "a chest's screen has a crafting grid, or the inventory a chest")
    +given : Bag.Bag = left_on(left_on(chest_bag(), 0), 46)
    Unit <- check(Bool.and(holds(held_of(given), 0, 0), holds(in_chest(given, 0n), 1, 32)), "the stone did not go into the chest")
    +shut : Bag.Bag = Screen.closed(given)
    Unit <- check(holds(slot_of(shut, 0n), 0, 0), "closing took the stone back out of the chest")
    +again : Bag.Bag = Screen.opened_at(shut, Screen.chest(), 30n, 9n, 25n, size())
    Unit <- check(holds(held_of(right_on(again, 46)), 1, 16), "the chest opened again does not give half its stone")
    check(holds(in_chest(Screen.opened_at(shut, Screen.chest(), 31n, 9n, 25n, size()), 0n), 0, 0), "the chest beside it holds the same stone")

def smelter() -> Bag.Bag:
  Screen.opened_at(
    Bag.with_slots(Bag.start(), Inventory.replace_at(Inventory.replace_at(Bag.slots_of(Bag.start()), 0n,
      Inventory.make_slot(6, 5, 0)), 1n, Inventory.make_slot(14, 3, 0))),
    Screen.furnace(), 30n, 9n, 25n, size())

def furnace_of(bag: Bag.Bag) -> Furnace.Furnace:
  Stores.furnace_of(Bag.store_of(bag))

def loads(f: Furnace.Furnace, want_input: U32, want_fuel: U32) -> Bool:
  Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn} = f
  Bool.and(U32.is_eq(input_count, want_input), U32.is_eq(fuel_count, want_fuel))

# A furnace's screen has the original's three slots. Sand goes in the first and coal in the
# second, each by a click with it on the arrow.
def a_furnace_is_loaded() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(4, 55), 56), U32.is_eq(Screen.slot_gy(4, 55), 17)), "what a furnace smelts is not at (56, 17)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(4, 56), 56), U32.is_eq(Screen.slot_gy(4, 56), 53)), "a furnace's fuel is not at (56, 53)")
    Unit <- check(Bool.and(U32.is_eq(Screen.slot_gx(4, 57), 116), U32.is_eq(Screen.slot_gy(4, 57), 35)), "what a furnace made is not at (116, 35)")
    Unit <- check(Bool.and(Screen.present(4, 57), Bool.not(Screen.present(4, 45))), "a furnace's screen has a crafting result, or no third slot")
    +loaded : Bag.Bag = right_on(left_on(left_on(left_on(smelter(), 0), 55), 1), 56)
    Unit <- check(loads(furnace_of(loaded), 5, 1), "five sand and one coal are not in the furnace")
    check(holds(held_of(loaded), 14, 2), "two coal are not left on the arrow")

def ticks(remaining: Nat, +store: Bag.Store) -> Bag.Store:
  match remaining:
    case 0n:
      store
    case 1n+rest:
      ticks(rest, Stores.ticked(store))

def lit.at(+loaded: Bag.Bag) -> Bag.Bag:
  Bag.with_store(loaded, ticks(60n, Bag.store_of(loaded)))

# The furnace's screen a second after sand and coal went in.
def lit_bag() -> Bag.Bag:
  lit.at(right_on(left_on(left_on(left_on(smelter(), 0), 55), 1), 56))

def total.go(slots: List<&2, Inventory.Slot>, +total: U32) -> U32:
  match slots:
    case Nil{}:
      total
    case slot <> rest:
      total.go(rest, U32.add(total, Inventory.slot_count_value(slot)))

def total(bag: Bag.Bag) -> U32:
  total.go(Bag.slots_of(bag), 0)

def shift_on(bag: Bag.Bag, +id: U32) -> Bag.Bag:
  Screen.step(Screen.aimed(bag, id, size()), Frame.shift_bit(), U32.or(Frame.shift_bit(), Frame.left_bit()), 0.0, 0.0, size())

# Shift and the left button send a stack without carrying it: between the hotbar and the
# rows in the inventory, into an open chest and back out of it, and into a furnace's two
# slots by what each takes.
def shift_sends_a_stack() -> IO(Unit):
  do IO<Unit>:
    +up : Bag.Bag = shift_on(open_bag(), 0)
    Unit <- check(Bool.and(holds(slot_of(up, 0n), 0, 0), holds(slot_of(up, 9n), 1, 32)), "shift did not send the hotbar's stone to the rows")
    Unit <- check(holds(held_of(up), 0, 0), "a quick move left something on the arrow")
    +down : Bag.Bag = shift_on(up, 9)
    Unit <- check(Bool.and(holds(slot_of(down, 9n), 0, 0), holds(slot_of(down, 0n), 1, 32)), "shift did not send the stone back to the hotbar")
    Unit <- check(U32.is_eq(Inventory.slot_durability(slot_of(shift_on(open_bag(), 5), 9n)), Inventory.tool_max_durability(19)), "a tool sent to the rows lost its wear")
    +stored : Bag.Bag = shift_on(chest_bag(), 0)
    Unit <- check(Bool.and(holds(slot_of(stored, 0n), 0, 0), holds(in_chest(stored, 0n), 1, 32)), "shift did not send the stone into the chest")
    +fetched : Bag.Bag = shift_on(stored, 46)
    Unit <- check(Bool.and(holds(in_chest(fetched, 0n), 0, 0), U32.is_eq(total(fetched), total(Bag.start()))), "shift did not fetch the stone out of the chest")
    +fed : Bag.Bag = shift_on(shift_on(smelter(), 0), 1)
    Unit <- check(loads(furnace_of(fed), 5, 3), "shift did not load the sand to smelt and the coal to burn")
    check(holds(held_of(shift_on(left_on(open_bag(), 0), 1)), 2, 24), "shift with a stack on the arrow was not a plain click")

# Closing puts what the arrow carries and what is in the grid back among the slots: nothing
# is lost, and a tool comes back with its wear.
def closing_puts_everything_back() -> IO(Unit):
  do IO<Unit>:
    +scattered : Bag.Bag = right_on(left_on(open_bag(), 4), 36)
    +shut : Bag.Bag = Screen.closed(scattered)
    Unit <- check(Bool.not(Bag.is_open(shut)), "a closed screen is open")
    Unit <- check(U32.is_eq(total(shut), total(Bag.start())), "closing lost or made an item")
    Unit <- check(Bool.and(holds(held_of(shut), 0, 0), holds(Bag.held.of(Inventory.lookup(grid_of(shut), 0n)), 0, 0)), "closing left a stack on the arrow or in the grid")
    +tool : Bag.Bag = Screen.closed(left_on(open_bag(), 5))
    check(U32.is_eq(Inventory.slot_durability(slot_of(tool, 5n)), Inventory.tool_max_durability(19)), "the pickaxe did not come back whole to the first empty slot")

def pixel(read: Array<U32> & U32) -> U32:
  (frame, cell) = read
  cell

def at(+bag: Bag.Bag, +x: U32, +y: U32) -> U32:
  pixel(Paint.frame_pixels_with([], Voxel.Camera.look(Voxel.Vec{0.0, 0.0, 0.0}, 0.0, 0.0),
    256.0, 384.0, size(), 9n, Screen.quads(bag, size(), Paint.QNil{}), False{})[U32.add(U32.mul(y, size()), x)])

# The picture: the panel's own grey between the slots, a slot's darker well, the well under
# the arrow lighter, and nothing at all when the screen is shut.
def the_screen_is_painted() -> IO(Unit):
  do IO<Unit>:
    +bag : Bag.Bag = Screen.aimed(open_bag(), 30, size())
    Unit <- check(U32.is_eq(at(bag, Screen.at_x(size(), 88), Screen.at_y(size(), 76)), Screen.panel_color()), "between the slots is not the panel")
    Unit <- check(U32.is_eq(at(bag, U32.add(Screen.at_x(size(), Screen.slot_gx(1, 31)), 1), U32.add(Screen.at_y(size(), Screen.slot_gy(1, 31)), 1)), Screen.well_color()), "an empty slot is not a well")
    Unit <- check(U32.is_eq(at(bag, U32.add(Screen.at_x(size(), Screen.slot_gx(1, 30)), 1), U32.add(Screen.at_y(size(), Screen.slot_gy(1, 30)), 1)), Screen.lit_color()), "the slot under the arrow is not lit")
    Unit <- check(U32.is_eq(at(bag, U32.sub(Screen.at_x(size(), Screen.slot_gx(1, 31)), 1), Screen.at_y(size(), Screen.slot_gy(1, 31))), Screen.edge_color()), "a slot has no dark edge on its left")
    Unit <- check(U32.is_eq(at(bag, Screen.at_x(size(), 40), Screen.at_y(size(), 40)), Screen.black()), "the player's box is not black")
    Unit <- check(U32.is_ne(at(Bag.start(), Screen.at_x(size(), 88), Screen.at_y(size(), 76)), Screen.panel_color()), "a shut screen is painted")
    Unit <- check(U32.is_eq(at(chest_bag(), U32.add(Screen.at_x(size(), 8), 1), U32.add(Screen.at_y(size(), 18), 1)), Screen.well_color()), "a chest's first slot is not a well")
    Unit <- check(U32.is_eq(at(smelter(), U32.add(Screen.at_x(size(), 60), 0), Screen.at_y(size(), 42)), Screen.well_color()), "a cold furnace has a lit flame")
    check(U32.is_eq(at(lit_bag(), Screen.at_x(size(), 60), Screen.at_y(size(), 42)), Screen.flame_color()), "a burning furnace has no flame")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- the_slots_are_where_the_original_puts_them()
    Unit <- the_arrow_finds_its_slot()
    Unit <- the_key_opens_and_closes()
    Unit <- a_click_moves_a_stack()
    Unit <- the_grid_crafts()
    Unit <- the_table_crafts_three_by_three()
    Unit <- a_chest_keeps_what_it_is_given()
    Unit <- a_furnace_is_loaded()
    Unit <- shift_sends_a_stack()
    Unit <- closing_puts_everything_back()
    Unit <- the_screen_is_painted()
    IO.print("screen: the layout, the arrow, the key, clicks, the grid, the crafting table, a chest, a furnace, quick moves, closing and the picture passed")
