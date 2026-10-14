import Base
import ../world/inventory.bend as Inventory
import ./voxel.bend as Voxel
import ./frame.bend as Frame
import ./paint.bend as Paint
import ./bag.bend as Bag
import ./hud.bend as Hud
import ./tag.bend as Tag
import ./stores.bend as Stores
import ../world/furnace.bend as Furnace

# Screen: the inventory, the crafting table, the chest and the furnace, laid out as the game
# this one is modelled on lays out its own.
#
# A chest here holds nine slots, by `world/chest.bend`, where the original's holds
# twenty-seven: they are one row where its first row is. A furnace is the original's three
# slots, its flame and its arrow. What a click does to either is `native/stores.bend`'s.
#
# The crafting table is the same panel with the whole of the rules' grid on it, three by
# three from (30, 17) and its result at (124, 35), as the original's `crafting_table.png`
# has them; the right button on a crafting table opens it.
#
# The inventory's panel is 176 by 166 units: nine hotbar slots along the bottom, three rows of nine above
# them, and over those the four armour slots, the player's box, a crafting grid of two by two
# and the slot its result appears in. A slot is sixteen units inside an edge one unit wide,
# and slots are eighteen units apart. Those numbers are the original's, read off its
# `inventory.png`; a unit is a whole number of pixels when the window is at least 176 wide,
# and the panel is squeezed to the window when it is not.
#
# The pointer is the client's own. The window holds the mouse to turn the camera, so there is
# no system cursor to show: while the screen is open the same movement that would turn the
# view moves an arrow instead, and the buttons click what is under it.
#
# No rule of the inventory is decided here. A click on a slot is `Inventory.click`, what the
# grid would make is `Inventory.craft_preview` and taking it is `Inventory.craft_take`. This
# module owns where the slots are, which one the arrow is over, and what the screen looks
# like.
#
# What the original does and this does not: a stack is not dragged across slots, a number
# key does not swap with the hotbar, a click outside the panel does not throw the stack
# away, Shift on what the grid makes does not craft all it can, and nothing is worn in the
# armour slots.

# --- the layout --------------------------------------------------------------------

def wide() -> U32:
  176

def tall() -> U32:
  166

# `g` units as pixels in a window `size` across.
def px(+size: U32, +g: U32) -> U32:
  Bool.pick(U32, U32.is_ge(size, wide()), U32.mul(g, U32.div(size, wide())),
    U32.div(U32.mul(g, size), wide()))

# One unit, and never less than a pixel: what a digit's dot and the arrow are measured in.
def unit(+size: U32) -> U32:
  U32.max(px(size, 1), 1)

# The panel is in the middle of the window.
def left(+size: U32) -> U32:
  U32.div(U32.sub(size, px(size, wide())), 2)

def top(+size: U32) -> U32:
  U32.div(U32.sub(size, px(size, tall())), 2)

def at_x(+size: U32, +g: U32) -> U32:
  U32.add(left(size), px(size, g))

def at_y(+size: U32, +g: U32) -> U32:
  U32.add(top(size), px(size, g))

# How many pixels `len` units from `g` are: the difference of two places, so two boxes that
# meet in units meet in pixels.
def span(+size: U32, +g: U32, +len: U32) -> U32:
  U32.sub(px(size, U32.add(g, len)), px(size, g))

# A box of the panel, in units.
def box(+gx: U32, +gy: U32, +gw: U32, +gh: U32, color: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  Paint.rect(at_x(size, gx), at_y(size, gy), span(size, gx, gw), span(size, gy, gh), color, size,
    next)

# Which screen is open.
def inventory() -> U32:
  1

def table() -> U32:
  2

def chest() -> U32:
  3

def furnace() -> U32:
  4

# The slots, by number: 0 to 8 the hotbar, 9 to 35 the three rows above it, 36 to 44 the
# nine cells of the rules' crafting grid, row by row, 45 what the grid makes, 46 to 54 a
# chest's nine slots, and 55 to 57 a furnace's: what it smelts, its fuel and what it made.
# 58 is no slot. The crafting table shows all nine cells of the grid and the inventory the
# four at the top left, which is its grid of two by two.
def slots() -> U32:
  58

def nowhere() -> U32:
  58

def output() -> U32:
  45

def first_cell() -> U32:
  36

def first_chest() -> U32:
  46

def smelting() -> U32:
  55

def fuel() -> U32:
  56

def smelted() -> U32:
  57

def grid_index(+id: U32) -> Nat:
  U32.to_nat(U32.sub(id, 36))

def cell_col(+id: U32) -> U32:
  U32.mod(U32.sub(id, 36), 3)

def cell_row(+id: U32) -> U32:
  U32.div(U32.sub(id, 36), 3)

def crafts(+mode: U32) -> Bool:
  Bool.or(U32.is_eq(mode, inventory()), U32.is_eq(mode, table()))

# Whether a screen has a slot.
def present(+mode: U32, +id: U32) -> Bool:
  Bool.or(U32.is_lt(id, 36),
    Bool.or(
      Bool.and(crafts(mode),
        Bool.or(U32.is_eq(id, 45),
          Bool.and(Bool.and(U32.is_ge(id, 36), U32.is_lt(id, 45)),
            Bool.or(U32.is_eq(mode, table()), Bool.and(U32.is_lt(cell_col(id), 2), U32.is_lt(cell_row(id), 2)))))),
      Bool.or(
        Bool.and(U32.is_eq(mode, chest()), Bool.and(U32.is_ge(id, 46), U32.is_lt(id, 55))),
        Bool.and(U32.is_eq(mode, furnace()), Bool.and(U32.is_ge(id, 55), U32.is_lt(id, 58))))))

# Where a slot is on a screen's panel, in units. The bag's slots are in the same place on
# every screen. The inventory's grid starts at (98, 18) with its result at (154, 28), and
# the crafting table's at (30, 17) with its result at (124, 35). A chest's slots are a row
# from (8, 18), where the original's first row is. A furnace smelts at (56, 17), burns at
# (56, 53) and gives at (116, 35).
def slot_gx(+mode: U32, +id: U32) -> U32:
  Bool.pick(U32, U32.is_lt(id, 36), U32.add(8, U32.mul(18, U32.mod(id, 9))),
    Bool.pick(U32, U32.is_lt(id, 45),
      U32.add(Bool.pick(U32, U32.is_eq(mode, table()), 30, 98), U32.mul(18, cell_col(id))),
      Bool.pick(U32, U32.is_eq(id, 45), Bool.pick(U32, U32.is_eq(mode, table()), 124, 154),
        Bool.pick(U32, U32.is_lt(id, 55), U32.add(8, U32.mul(18, U32.sub(id, 46))),
          Bool.pick(U32, U32.is_eq(id, 57), 116, 56)))))

def slot_gy(+mode: U32, +id: U32) -> U32:
  Bool.pick(U32, U32.is_lt(id, 9), 142,
    Bool.pick(U32, U32.is_lt(id, 36), U32.add(84, U32.mul(18, U32.div(U32.sub(id, 9), 9))),
      Bool.pick(U32, U32.is_lt(id, 45),
        U32.add(Bool.pick(U32, U32.is_eq(mode, table()), 17, 18), U32.mul(18, cell_row(id))),
        Bool.pick(U32, U32.is_eq(id, 45), Bool.pick(U32, U32.is_eq(mode, table()), 35, 28),
          Bool.pick(U32, U32.is_lt(id, 55), 18,
            Bool.pick(U32, U32.is_eq(id, 55), 17, Bool.pick(U32, U32.is_eq(id, 56), 53, 35)))))))

# --- the arrow ---------------------------------------------------------------------

def over(+mode: U32, +id: U32, +x: U32, +y: U32, +size: U32) -> Bool:
  Bool.and(present(mode, id), Bool.and(
    Bool.and(U32.is_ge(x, at_x(size, slot_gx(mode, id))),
      U32.is_lt(x, U32.add(at_x(size, slot_gx(mode, id)), span(size, slot_gx(mode, id), 16)))),
    Bool.and(U32.is_ge(y, at_y(size, slot_gy(mode, id))),
      U32.is_lt(y, U32.add(at_y(size, slot_gy(mode, id)), span(size, slot_gy(mode, id), 16))))))

def hit.go(remaining: Nat, +mode: U32, +id: U32, +x: U32, +y: U32, +size: U32, +found: U32) -> U32:
  match remaining:
    case 0n:
      found
    case 1n+rest:
      hit.go(rest, mode, U32.add(id, 1), x, y, size, Bool.pick(U32, over(mode, id, x, y, size), id, found))

# The slot of a screen a point of the window is over, or `nowhere`.
def hit(+mode: U32, +x: F32, +y: F32, +size: U32) -> U32:
  hit.go(58n, mode, 0, F32.to_u32(F32.max(x, 0.0)), F32.to_u32(F32.max(y, 0.0)), size, nowhere())

def desk_x(desk: Bag.Desk) -> F32:
  Bag.Desk{open, x, y, held, grid} = desk
  x

def desk_y(desk: Bag.Desk) -> F32:
  Bag.Desk{open, x, y, held, grid} = desk
  y

def hover(+bag: Bag.Bag, +size: U32) -> U32:
  hit(Bag.mode_of(bag), desk_x(Bag.desk_of(bag)), desk_y(Bag.desk_of(bag)), size)

# The bag with the arrow on the middle of a slot: what a test, or a probe, points with.
def aimed(bag: Bag.Bag, +id: U32, +size: U32) -> Bag.Bag:
  Bag.Bag{slots, selected, Bag.Desk{+open, x, y, held, grid}, store} = bag
  Bag.Bag{slots, selected,
    Bag.Desk{open, U32.to_f32(U32.add(at_x(size, slot_gx(open, id)), U32.div(span(size, slot_gx(open, id), 16), 2))),
      U32.to_f32(U32.add(at_y(size, slot_gy(open, id)), U32.div(span(size, slot_gy(open, id), 16), 2))), held, grid}, store}

def held_within(+value: F32, +size: U32) -> F32:
  F32.max(0.0, F32.min(value, U32.to_f32(U32.sub(size, 1))))

def moved(bag: Bag.Bag, +dx: F32, +dy: F32, +size: U32) -> Bag.Bag:
  Bag.Bag{slots, selected, Bag.Desk{open, x, y, held, grid}, store} = bag
  Bag.Bag{slots, selected,
    Bag.Desk{open, held_within(F32.add(x, dx), size), held_within(F32.add(y, dy), size), held, grid}, store}

# --- opening and closing -----------------------------------------------------------

# The screen of the chest or the furnace at a cell of the world.
def opened_at(bag: Bag.Bag, mode: U32, x: Nat, y: Nat, z: Nat, +size: U32) -> Bag.Bag:
  Bag.Bag{slots, selected, Bag.Desk{open, ax, ay, held, grid}, store} = bag
  Bag.Bag{slots, selected,
    Bag.Desk{mode, U32.to_f32(U32.div(size, 2)), U32.to_f32(U32.div(size, 2)), held, grid},
    Stores.aimed(store, x, y, z)}

# A screen opened, with the arrow in the middle of the window.
def opened_as(bag: Bag.Bag, mode: U32, +size: U32) -> Bag.Bag:
  Bag.Bag{slots, selected, Bag.Desk{open, x, y, held, grid}, store} = bag
  Bag.Bag{slots, selected,
    Bag.Desk{mode, U32.to_f32(U32.div(size, 2)), U32.to_f32(U32.div(size, 2)), held, grid}, store}

def opened(bag: Bag.Bag, +size: U32) -> Bag.Bag:
  opened_as(bag, inventory(), size)

# A stack put back among the slots, and what of it found no room.
type Stowed is Data:
  Stowed{slots: List<&2, Inventory.Slot>, left: Inventory.Slot}

def first_free(slots: List<&2, Inventory.Slot>, +index: Nat) -> Nat:
  match slots:
    case Nil{}:
      Inventory.slot_count()
    case head <> rest:
      Bool.pick(Nat, U32.is_eq(Inventory.slot_count_value(head), 0), index,
        first_free(rest, Nat.add(index, 1n)))

# A tool keeps its wear, so it goes whole into the first empty slot or stays where it is.
def stow.whole(room: Bool, +slots: List<&2, Inventory.Slot>, +slot: Inventory.Slot) -> Stowed:
  match room:
    case True{}:
      Stowed{Inventory.replace_at(slots, first_free(slots, 0n), slot), Inventory.make_slot(0, 0, 0)}
    case False{}:
      Stowed{slots, slot}

def stow.added(added: Inventory.AddResult, +item: U32, +durability: U32) -> Stowed:
  Inventory.AddResult{slots, remaining} = added
  Stowed{slots, Inventory.stack(item, remaining, durability)}

def stow.at(stacks: Bool, +slots: List<&2, Inventory.Slot>, +slot: Inventory.Slot) -> Stowed:
  match stacks:
    case True{}:
      stow.added(Inventory.add_items(slots, Inventory.slot_item(slot), Inventory.slot_count_value(slot)),
        Inventory.slot_item(slot), Inventory.slot_durability(slot))
    case False{}:
      stow.whole(Nat.is_lt(first_free(slots, 0n), Inventory.slot_count()), slots, slot)

def stow(+slots: List<&2, Inventory.Slot>, +slot: Inventory.Slot) -> Stowed:
  stow.at(Inventory.stackable(Inventory.slot_item(slot)), slots, slot)

# The crafting grid emptied into the slots: the slots after, and the grid with what did not
# fit still in it.
type Cleared is Data:
  Cleared{slots: List<&2, Inventory.Slot>, grid: List<&2, Inventory.Slot>}

def stowed_slots(stowed: Stowed) -> List<&2, Inventory.Slot>:
  Stowed{slots, left} = stowed
  slots

def stowed_left(stowed: Stowed) -> Inventory.Slot:
  Stowed{slots, left} = stowed
  left

def clear.go(grid: List<&2, Inventory.Slot>, +slots: List<&2, Inventory.Slot>,
  +acc: List<&2, Inventory.Slot>) -> Cleared:
  match grid:
    case Nil{}:
      Cleared{slots, List.reverse(&2, Inventory.Slot, acc)}
    case +cell <> rest:
      clear.go(rest, stowed_slots(stow(slots, cell)), stowed_left(stow(slots, cell)) <> acc)

def cleared(+slots: List<&2, Inventory.Slot>, grid: List<&2, Inventory.Slot>) -> Cleared:
  clear.go(grid, slots, [])

def closed.grid(cleared: Cleared, +selected: Nat, +x: F32, +y: F32, held: Inventory.Slot,
  store: Bag.Store) -> Bag.Bag:
  Cleared{slots, grid} = cleared
  Bag.Bag{slots, selected, Bag.Desk{0, x, y, held, grid}, store}

def closed.held(stowed: Stowed, +selected: Nat, +x: F32, +y: F32,
  grid: List<&2, Inventory.Slot>, store: Bag.Store) -> Bag.Bag:
  Stowed{slots, left} = stowed
  closed.grid(cleared(slots, grid), selected, x, y, left, store)

# Closing puts what is on the arrow and in the grid back among the slots. What finds no room
# stays where it was, and is there when the screen opens again: nothing is thrown away.
def closed(bag: Bag.Bag) -> Bag.Bag:
  Bag.Bag{slots, selected, Bag.Desk{open, x, y, held, grid}, store} = bag
  closed.held(stow(slots, held), selected, x, y, grid, store)

# --- clicking ----------------------------------------------------------------------

def click.slot(clicked: Inventory.Clicked, +slots: List<&2, Inventory.Slot>, +id: Nat, +selected: Nat,
  mode: U32, +x: F32, +y: F32, grid: List<&2, Inventory.Slot>, store: Bag.Store) -> Bag.Bag:
  Inventory.Clicked{slot, held} = clicked
  Bag.Bag{Inventory.replace_at(slots, id, slot), selected, Bag.Desk{mode, x, y, held, grid}, store}

def click.cell(clicked: Inventory.Clicked, slots: List<&2, Inventory.Slot>, +id: Nat, +selected: Nat,
  mode: U32, +x: F32, +y: F32, +grid: List<&2, Inventory.Slot>, store: Bag.Store) -> Bag.Bag:
  Inventory.Clicked{slot, held} = clicked
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, Inventory.replace_at(grid, id, slot)}, store}

def click.made(crafted: Inventory.Crafted, slots: List<&2, Inventory.Slot>, +selected: Nat, mode: U32,
  +x: F32, +y: F32, store: Bag.Store) -> Bag.Bag:
  Inventory.Crafted{grid, held, ok} = crafted
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store}

def click.stored(moved: Stores.Moved, slots: List<&2, Inventory.Slot>, selected: Nat, mode: U32,
  x: F32, y: F32, grid: List<&2, Inventory.Slot>) -> Bag.Bag:
  Stores.Moved{held, store} = moved
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store}

# `kind` is what the arrow is over: 0 a slot of the bag, 1 a cell of the grid, 2 what the
# grid makes, 3 a slot of the chest, 4 a slot of the furnace, and anything else nothing.
def click.at(kind: Nat, +id: U32, right: Bool, bag: Bag.Bag) -> Bag.Bag:
  match kind:
    case 0n:
      Bag.Bag{+slots, selected, Bag.Desk{open, x, y, held, grid}, store} = bag
      click.slot(Inventory.click(Bag.held.of(Inventory.lookup(slots, U32.to_nat(id))), held, right),
        slots, U32.to_nat(id), selected, open, x, y, grid, store)
    case 1n:
      Bag.Bag{slots, selected, Bag.Desk{open, x, y, held, +grid}, store} = bag
      click.cell(Inventory.click(Bag.held.of(Inventory.lookup(grid, grid_index(id))), held, right),
        slots, grid_index(id), selected, open, x, y, grid, store)
    case 2n:
      Bag.Bag{slots, selected, Bag.Desk{open, x, y, held, grid}, store} = bag
      click.made(Inventory.craft_take(grid, held), slots, selected, open, x, y, store)
    case 3n:
      Bag.Bag{slots, selected, Bag.Desk{open, x, y, held, grid}, store} = bag
      click.stored(Stores.chest_click(store, held, U32.to_nat(U32.sub(id, 46)), right), slots, selected, open,
        x, y, grid)
    case 4n:
      Bag.Bag{slots, selected, Bag.Desk{open, x, y, held, grid}, store} = bag
      click.stored(Stores.furnace_click(store, held, U32.to_nat(U32.sub(id, 55)), right), slots, selected,
        open, x, y, grid)
    case _:
      bag

def kind_of(+id: U32) -> Nat:
  U32.to_nat(Bool.pick(U32, U32.is_lt(id, 36), 0,
    Bool.pick(U32, U32.is_lt(id, 45), 1,
      Bool.pick(U32, U32.is_eq(id, 45), 2,
        Bool.pick(U32, U32.is_lt(id, 55), 3, Bool.pick(U32, U32.is_lt(id, 58), 4, 5))))))

# --- a quick move ------------------------------------------------------------------
#
# Shift and the left button send a stack where the original sends it, without the arrow
# carrying it: from a chest or a furnace into the bag and from the bag into them, and with
# neither open between the hotbar and the rows above it. A stack out of the crafting grid
# goes to the bag. What finds no room stays where it was, or on the arrow when it had to be
# withdrawn to be moved. It is a move of an empty arrow: carrying something, Shift changes
# nothing about a click.

def front.go(remaining: Nat, list: List<&2, Inventory.Slot>, acc: List<&2, Inventory.Slot>) -> List<&2, Inventory.Slot>:
  match remaining list:
    case 1n+r head <> rest:
      front.go(r, rest, head <> acc)
    case _ _:
      List.reverse(&2, Inventory.Slot, acc)

# The hotbar's nine slots, and the twenty-seven above them.
def hotbar_of(slots: List<&2, Inventory.Slot>) -> List<&2, Inventory.Slot>:
  front.go(9n, slots, [])

def rows_of.go(remaining: Nat, list: List<&2, Inventory.Slot>) -> List<&2, Inventory.Slot>:
  match remaining list:
    case 1n+r head <> rest:
      rows_of.go(r, rest)
    case _ rest:
      rest

def rows_of(slots: List<&2, Inventory.Slot>) -> List<&2, Inventory.Slot>:
  rows_of.go(9n, slots)

def quick.joined(stowed: Stowed, +id: Nat, +hot: Bool, +other: List<&2, Inventory.Slot>, selected: Nat,
  desk: Bag.Desk, store: Bag.Store) -> Bag.Bag:
  Stowed{+part, left} = stowed
  Bag.Bag{Inventory.replace_at(
      Bool.pick(List<&2, Inventory.Slot>, hot, List.append(&2, Inventory.Slot, other, part),
        List.append(&2, Inventory.Slot, part, other)), id, left), selected, desk, store}

# A stack sent from one half of the bag to the other: `emptied` is the slots without it.
def quick.halves(+hot: Bool, +emptied: List<&2, Inventory.Slot>, +slot: Inventory.Slot, +id: Nat,
  selected: Nat, desk: Bag.Desk, store: Bag.Store) -> Bag.Bag:
  quick.joined(
    stow(Bool.pick(List<&2, Inventory.Slot>, hot, rows_of(emptied), hotbar_of(emptied)), slot),
    id, hot, Bool.pick(List<&2, Inventory.Slot>, hot, hotbar_of(emptied), rows_of(emptied)), selected, desk,
    store)

def moved_held(moved: Stores.Moved) -> Inventory.Slot:
  Stores.Moved{held, store} = moved
  held

def moved_store(moved: Stores.Moved) -> Bag.Store:
  Stores.Moved{held, store} = moved
  store

# What a store left of a stack goes back to the slot the stack came from.
def quick.kept(moved: Stores.Moved, +slots: List<&2, Inventory.Slot>, +id: Nat, selected: Nat,
  desk: Bag.Desk) -> Bag.Bag:
  Stores.Moved{held, store} = moved
  Bag.Bag{Inventory.replace_at(slots, id, held), selected, desk, store}

# A furnace is offered a stack to smelt, and what it did not take as fuel.
def quick.fed(+first: Stores.Moved) -> Stores.Moved:
  Stores.furnace_click(moved_store(first), moved_held(first), 1n, False{})

def quick.slot(mode: Nat, +slots: List<&2, Inventory.Slot>, +id: Nat, selected: Nat, desk: Bag.Desk,
  +store: Bag.Store) -> Bag.Bag:
  match mode:
    case 3n:
      quick.kept(Stores.chest_click(store, Bag.held.of(Inventory.lookup(slots, id)), 0n, False{}), slots, id,
        selected, desk)
    case 4n:
      quick.kept(quick.fed(Stores.furnace_click(store, Bag.held.of(Inventory.lookup(slots, id)), 0n, False{})),
        slots, id, selected, desk)
    case _:
      quick.halves(Nat.is_lt(id, 9n), Inventory.replace_at(slots, id, Inventory.make_slot(0, 0, 0)),
        Bag.held.of(Inventory.lookup(slots, id)), id, selected, desk, store)

# What came out of a chest or a furnace goes into the bag, and what the bag has no room for
# is on the arrow.
def quick.took(stowed: Stowed, selected: Nat, mode: U32, x: F32, y: F32, grid: List<&2, Inventory.Slot>,
  store: Bag.Store) -> Bag.Bag:
  Stowed{slots, left} = stowed
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, left, grid}, store}

def quick.out(+moved: Stores.Moved, +slots: List<&2, Inventory.Slot>, selected: Nat, mode: U32, x: F32,
  y: F32, grid: List<&2, Inventory.Slot>) -> Bag.Bag:
  quick.took(stow(slots, moved_held(moved)), selected, mode, x, y, grid, moved_store(moved))

# A stack of the crafting grid goes into the bag, and what finds no room stays in its cell.
def quick.cell(stowed: Stowed, +id: Nat, selected: Nat, mode: U32, x: F32, y: F32, held: Inventory.Slot,
  grid: List<&2, Inventory.Slot>, store: Bag.Store) -> Bag.Bag:
  Stowed{slots, left} = stowed
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, Inventory.replace_at(grid, id, left)}, store}

def quick.at(kind: Nat, +id: U32, bag: Bag.Bag) -> Bag.Bag:
  match kind:
    case 0n:
      Bag.Bag{slots, selected, Bag.Desk{+mode, x, y, held, grid}, store} = bag
      quick.slot(U32.to_nat(mode), slots, U32.to_nat(id), selected, Bag.Desk{mode, x, y, held, grid}, store)
    case 1n:
      Bag.Bag{+slots, selected, Bag.Desk{mode, x, y, held, +grid}, store} = bag
      quick.cell(stow(slots, Bag.held.of(Inventory.lookup(grid, grid_index(id)))), grid_index(id), selected,
        mode, x, y, held, grid, store)
    case 3n:
      Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store} = bag
      quick.out(Stores.chest_click(store, held, U32.to_nat(U32.sub(id, 46)), False{}), slots, selected, mode, x,
        y, grid)
    case 4n:
      Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store} = bag
      quick.out(Stores.furnace_click(store, held, 2n, False{}), slots, selected, mode, x, y, grid)
    case _:
      bag

def carrying(bag: Bag.Bag) -> Bool:
  Bag.Bag{slots, selected, Bag.Desk{mode, x, y, held, grid}, store} = bag
  U32.is_gt(Inventory.slot_count_value(held), 0)

# In a room a chest's or a furnace's screen asks the room for each move, one at a time and
# through the arrow, so a quick move there is a plain click.
def asks(+bag: Bag.Bag) -> Bool:
  Bool.and(Stores.shared(Bag.store_of(bag)),
    Bool.or(U32.is_eq(Bag.mode_of(bag), chest()), U32.is_eq(Bag.mode_of(bag), furnace())))

# A furnace gives from its third slot only: a quick move on the other two is a plain click.
def quick_kind(+id: U32) -> Nat:
  U32.to_nat(Bool.pick(U32, U32.is_lt(id, 36), 0,
    Bool.pick(U32, U32.is_lt(id, 45), 1,
      Bool.pick(U32, U32.is_eq(id, 45), 2,
        Bool.pick(U32, U32.is_lt(id, 55), 3, Bool.pick(U32, U32.is_eq(id, 57), 4, 5))))))

def clicked.at(quick: Bool, +id: U32, right: Bool, bag: Bag.Bag) -> Bag.Bag:
  match quick:
    case True{}:
      quick.at(quick_kind(id), id, bag)
    case False{}:
      click.at(kind_of(id), id, right, bag)

# One click where the arrow is. With Shift held, the left button and an empty arrow, it is a
# quick move of the stack under the arrow; on what the grid makes, and otherwise, a click.
def clicked(+bag: Bag.Bag, +right: Bool, shift: Bool, +size: U32) -> Bag.Bag:
  clicked.at(Bool.and(Bool.and(Bool.and(shift, Bool.not(right)), Bool.not(asks(bag))),
      Bool.and(Bool.not(carrying(bag)), Nat.is_ne(quick_kind(hover(bag, size)), 2n))),
    hover(bag, size), right, bag)

# --- a tick ------------------------------------------------------------------------

# A key or a button that went down this tick: held now, and not in the tick before.
def pressed(+previous: U32, +mask: U32, +bit: U32) -> Bool:
  Bool.and(U32.is_eq(U32.and(mask, bit), bit), U32.is_eq(U32.and(previous, bit), 0))

# The key that opens the screen and closes it.
def key() -> U32:
  101

def step.clicking(left: Bool, right: Bool, shift: Bool, bag: Bag.Bag, +size: U32) -> Bag.Bag:
  match left right:
    case True{} _:
      clicked(bag, False{}, shift, size)
    case False{} True{}:
      clicked(bag, True{}, shift, size)
    case False{} False{}:
      bag

def step.open(closing: Bool, left: Bool, right: Bool, shift: Bool, bag: Bag.Bag, +size: U32) -> Bag.Bag:
  match closing:
    case True{}:
      closed(bag)
    case False{}:
      step.clicking(left, right, shift, bag, size)

def step.shut(opening: Bool, bag: Bag.Bag, +size: U32) -> Bag.Bag:
  match opening:
    case True{}:
      opened(bag, size)
    case False{}:
      bag

def step.at(open: Bool, +toggled: Bool, escaped: Bool, left: Bool, right: Bool, shift: Bool,
  bag: Bag.Bag, +dx: F32, +dy: F32, +size: U32) -> Bag.Bag:
  match open:
    case True{}:
      step.open(Bool.or(toggled, escaped), left, right, shift, moved(bag, dx, dy, size), size)
    case False{}:
      step.shut(toggled, bag, size)

# The bag after one tick of the screen. `previous` is the held keys the tick started with
# and `mask` the ones it ended with, so a key is read as the edge it is and a held key does
# nothing twice; `dx` and `dy` are how far the pointer moved, in pixels.
#
# Shut, the screen's key opens it. Open, the pointer moves the arrow, the screen's key or
# escape closes it, and a button clicks what the arrow is over.
def step(+bag: Bag.Bag, +previous: U32, +mask: U32, +dx: F32, +dy: F32, +size: U32) -> Bag.Bag:
  step.at(Bag.is_open(bag), pressed(previous, mask, Frame.key_bit(key())),
    pressed(previous, mask, Frame.key_bit(27)), pressed(previous, mask, Frame.left_bit()),
    pressed(previous, mask, Frame.right_bit()),
    U32.is_eq(U32.and(mask, Frame.shift_bit()), Frame.shift_bit()), bag, dx, dy, size)

# --- the picture -------------------------------------------------------------------

def panel_color() -> U32:
  Voxel.rgb(198, 198, 198)

def shadow_color() -> U32:
  Voxel.rgb(85, 85, 85)

def well_color() -> U32:
  Voxel.rgb(139, 139, 139)

def lit_color() -> U32:
  Voxel.rgb(184, 184, 184)

def edge_color() -> U32:
  Voxel.rgb(55, 55, 55)

def text_color() -> U32:
  Voxel.rgb(64, 64, 64)

def black() -> U32:
  Voxel.rgb(0, 0, 0)

def dot_at(on: Bool, +x: U32, +y: U32, +p: U32, color: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match on:
    case True{}:
      Paint.rect(x, y, p, p, color, size, next)
    case False{}:
      next

def dots(remaining: Nat, +index: U32, +mask: U32, +x: U32, +y: U32, +p: U32, +color: U32,
  +size: U32, next: Paint.Quads) -> Paint.Quads:
  match remaining:
    case 0n:
      next
    case 1n+r:
      dot_at(Hud.lit(mask, U32.to_nat(index)), U32.add(x, U32.mul(U32.mod(index, 3), p)),
        U32.add(y, U32.mul(U32.div(index, 3), p)), p, color, size,
        dots(r, U32.add(index, 1), mask, x, y, p, color, size, next))

# Words in `Tag`'s letters, in one colour, from a pixel of the window.
def words(name: String, +x: U32, +y: U32, +p: U32, +color: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match name:
    case SNil{}:
      next
    case SCon{head, tail}:
      dots(15n, 0, Tag.glyph_of(Char.to_u32(head)), x, y, p, color, size,
        words(tail, U32.add(x, U32.mul(4, p)), y, p, color, size, next))

# What a slot holds, drawn from a pixel of the window in a square `e` across: the count over
# the wear over the item, which is the order they are seen in.
def stack_at(slot: Inventory.Slot, +x: U32, +y: U32, +e: U32, +p: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  Inventory.Slot{+item, +count, +durability} = slot
  Hud.number(Bool.and(U32.is_gt(count, 1), U32.is_ge(e, 10)), count, U32.add(x, e), U32.add(y, e), p,
    size,
    Hud.wear(Bool.pick(U32, U32.is_gt(count, 0), item, 0), durability, x, y, e, p, size,
      Hud.icon(U32.is_gt(count, 0), U32.is_ne(Inventory.placed_block(item), 0), item, x, y, e, size,
        next)))

# A slot at a place of the panel: what it holds, its well — lighter under the arrow — and
# the edge the original gives a slot, dark above and to the left and white below and right.
def well(slot: Inventory.Slot, +gx: U32, +gy: U32, lit: Bool, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  stack_at(slot, at_x(size, gx), at_y(size, gy), span(size, gx, 16), unit(size), size,
    box(gx, gy, 16, 16, Bool.pick(U32, lit, lit_color(), well_color()), size,
      box(U32.sub(gx, 1), U32.sub(gy, 1), 17, 1, edge_color(), size,
        box(U32.sub(gx, 1), gy, 1, 16, edge_color(), size,
          box(U32.sub(gx, 1), U32.add(gy, 16), 18, 1, Hud.white(), size,
            box(U32.add(gx, 16), U32.sub(gy, 1), 1, 17, Hud.white(), size, next))))))

def cell(shown: Bool, slot: Inventory.Slot, +mode: U32, +id: U32, +under: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match shown:
    case True{}:
      well(slot, slot_gx(mode, id), slot_gy(mode, id), U32.is_eq(id, under), size, next)
    case False{}:
      next

def cells(list: List<&2, Inventory.Slot>, +mode: U32, +id: U32, +under: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match list:
    case Nil{}:
      next
    case head <> rest:
      cell(present(mode, id), head, mode, id, under, size,
        cells(rest, mode, U32.add(id, 1), under, size, next))

def empty() -> Inventory.Slot:
  Inventory.make_slot(0, 0, 0)

# The arrow from a grid to what it makes, with its tail at a place of the panel.
def makes(+gx: U32, +gy: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  box(gx, U32.add(gy, 5), 9, 3, well_color(), size,
    Paint.quad(U32.to_f32(at_x(size, U32.add(gx, 9))), U32.to_f32(at_y(size, U32.add(gy, 1))),
      U32.to_f32(at_x(size, U32.add(gx, 16))),
      F32.add(U32.to_f32(at_y(size, U32.add(gy, 6))), F32.div(U32.to_f32(span(size, gy, 1)), 2.0)),
      U32.to_f32(at_x(size, U32.add(gx, 9))), U32.to_f32(at_y(size, U32.add(gy, 12))),
      U32.to_f32(at_x(size, U32.add(gx, 9))), U32.to_f32(at_y(size, U32.add(gy, 12))), well_color(), size,
      next))

# The grid's cells a screen shows, then what the grid makes.
def bench(+grid: List<&2, Inventory.Slot>, +mode: U32, +under: U32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  cells(grid, mode, first_cell(), under, size,
    cell(present(mode, output()), Inventory.craft_preview(grid), mode, output(), under, size, next))

def flame_color() -> U32:
  Voxel.rgb(232, 126, 32)

# A furnace's three slots, the flame between the first two — lit while it burns — and the
# arrow to what it makes, which fills as the smelting goes.
def hearth(f: Furnace.Furnace, +under: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  Furnace.Furnace{input, input_count, burns, fuel_count, made, made_count, +progress, burn} = f
  cell(True{}, Inventory.stack(input, input_count, 0), furnace(), smelting(), under, size,
    cell(True{}, Inventory.stack(burns, fuel_count, 0), furnace(), fuel(), under, size,
      cell(True{}, Inventory.stack(made, made_count, 0), furnace(), smelted(), under, size,
        box(57, 37, 13, 13, Bool.pick(U32, U32.is_gt(burn, 0), flame_color(), well_color()), size,
          box(79, 39, U32.div(U32.mul(U32.min(progress, Furnace.smelt_time()), 22), Furnace.smelt_time()), 3,
            Hud.white(), size,
            makes(79, 34, size, next))))))

# What a chest's or a furnace's screen shows above the bag's slots.
def stored(mode: Nat, +store: Bag.Store, +under: U32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match mode:
    case 3n:
      cells(Stores.chest_shown(store), chest(), first_chest(), under, size, next)
    case 4n:
      hearth(Stores.furnace_of(store), under, size, next)
    case _:
      next

# What is on a panel and is not a slot. The inventory has the word over its grid, the arrow
# to what it makes, the four armour slots and the player's box; the other three have their
# name and the word over the bag's rows, and the crafting table its arrow.
def furniture(mode: Nat, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match mode:
    case 1n:
      words("Crafting", at_x(size, 97), at_y(size, 8), unit(size), text_color(), size,
        makes(135, 29, size,
          well(empty(), 8, 8, False{}, size,
            well(empty(), 8, 26, False{}, size,
              well(empty(), 8, 44, False{}, size,
                well(empty(), 8, 62, False{}, size,
                  box(26, 8, 49, 70, black(), size, next)))))))
    case 2n:
      words("Crafting", at_x(size, 28), at_y(size, 6), unit(size), text_color(), size,
        words("Inventory", at_x(size, 8), at_y(size, 73), unit(size), text_color(), size,
          makes(90, 35, size, next)))
    case 3n:
      words("Chest", at_x(size, 8), at_y(size, 6), unit(size), text_color(), size,
        words("Inventory", at_x(size, 8), at_y(size, 73), unit(size), text_color(), size, next))
    case _:
      words("Furnace", at_x(size, 74), at_y(size, 6), unit(size), text_color(), size,
        words("Inventory", at_x(size, 8), at_y(size, 73), unit(size), text_color(), size, next))

# The panel itself: a light bevel above and to the left, a dark one below and to the right,
# inside a black line.
def panel(+size: U32, next: Paint.Quads) -> Paint.Quads:
  box(1, 1, 174, 2, Hud.white(), size,
    box(1, 3, 2, 162, Hud.white(), size,
      box(1, 163, 174, 2, shadow_color(), size,
        box(173, 3, 2, 160, shadow_color(), size,
          box(1, 1, 174, 164, panel_color(), size,
            box(0, 0, 176, 166, black(), size, next))))))

# The arrow, with what it carries: a white wedge inside a black one, its tip at the point.
def arrow(+x: F32, +y: F32, +u: F32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  Paint.quad(x, y, x, F32.add(y, F32.mul(11.0, u)), F32.add(x, F32.mul(8.0, u)), F32.add(y, F32.mul(8.0, u)),
    F32.add(x, F32.mul(8.0, u)), F32.add(y, F32.mul(8.0, u)), Hud.white(), size,
    Paint.quad(F32.sub(x, u), F32.sub(y, F32.mul(2.0, u)), F32.sub(x, u), F32.add(y, F32.mul(14.0, u)),
      F32.add(x, F32.mul(11.0, u)), F32.add(y, F32.mul(9.0, u)), F32.add(x, F32.mul(11.0, u)),
      F32.add(y, F32.mul(9.0, u)), black(), size, next))

def carried.at(carrying: Bool, held: Inventory.Slot, +x: F32, +y: F32, +size: U32,
  next: Paint.Quads) -> Paint.Quads:
  match carrying:
    case False{}:
      arrow(x, y, U32.to_f32(unit(size)), size, next)
    case True{}:
      stack_at(held, F32.to_u32(F32.max(F32.sub(x, U32.to_f32(U32.div(span(size, 0, 16), 2))), 0.0)),
        F32.to_u32(F32.max(F32.sub(y, U32.to_f32(U32.div(span(size, 0, 16), 2))), 0.0)), span(size, 0, 16),
        unit(size), size, next)

# What the arrow carries is drawn in its place; with nothing on it, the arrow itself.
def carried(+held: Inventory.Slot, +x: F32, +y: F32, +size: U32, next: Paint.Quads) -> Paint.Quads:
  carried.at(U32.is_gt(Inventory.slot_count_value(held), 0), held, x, y, size, next)

def drawn(open: Bool, +bag: Bag.Bag, +size: U32, next: Paint.Quads) -> Paint.Quads:
  match open:
    case False{}:
      next
    case True{}:
      Bag.Bag{slots, selected, Bag.Desk{+mode, +x, +y, held, +grid}, store} = bag
      carried(held, x, y, size,
        cells(slots, mode, 0, hover(bag, size), size,
          bench(grid, mode, hover(bag, size), size,
            stored(U32.to_nat(mode), store, hover(bag, size), size,
              furniture(U32.to_nat(mode), size, panel(size, next))))))

# The screen's polygons, nearest first, ahead of `next`: nothing when it is shut.
def quads(+bag: Bag.Bag, +size: U32, next: Paint.Quads) -> Paint.Quads:
  drawn(Bag.is_open(bag), bag, size, next)
