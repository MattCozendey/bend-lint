import Base
import ../world/world.bend as World
import ../world/inventory.bend as Inventory
import ../world/chest.bend as Chest
import ../world/chests.bend as Chests
import ../world/furnace.bend as Furnace
import ../world/furnaces.bend as Furnaces
import ./bag.bend as Bag
import ./net.bend as Net

# Stores: what a click does to a chest or a furnace, with a stack on the arrow.
#
# The rules are `world/chest.bend`'s and `world/furnace.bend`'s, and they are the ones a
# multiplayer room applies: a chest takes a deposit and gives a withdrawal, and a furnace
# is loaded with something to smelt, loaded with fuel, or emptied of what it made. A screen
# has slots and an arrow, so each click here is one of those five, chosen by what the arrow
# carries:
#
# - on a chest's slot with an empty arrow, the left button withdraws the slot and the right
#   withdraws the larger half; with a stack on the arrow, the left deposits all of it and
#   the right deposits one. A deposit goes where the rule puts it — onto a stack of the same
#   item, then into the first empty slot — which is not always the slot under the arrow;
# - on a furnace's first two slots a stack is loaded, all of it or one, when the rule takes
#   it: something that smelts above, coal below. The rules have no way to take either back;
# - on a furnace's third slot what it made is taken, when the arrow is empty or carries the
#   same and has room.
#
# A refusal changes nothing, and each click leaves every item in exactly one place.
#
# In a room the chests and furnaces are the room's. The store is then a copy the room keeps
# current (`put`), and a click changes nothing here: it leaves a request in the store, which
# the session sends, and the arrow changes when the room answers (`answered`). One request
# waits at a time, and a click while one waits is dropped, so an answer is never matched to
# the wrong click. A furnace is loaded one item a request, which is the room's rule.

# What a click left: the stack on the arrow, and the world's chests and furnaces.
type Moved is Data:
  Moved{held: Inventory.Slot, store: Bag.Store}

# --- the store ---------------------------------------------------------------------

# The store with a screen's chest or furnace named: the cell it stands in.
def aimed(store: Bag.Store, x: Nat, y: Nat, z: Nat) -> Bag.Store:
  Bag.Store{chests, furnaces, ox, oy, oz, beat, ask} = store
  Bag.Store{chests, furnaces, x, y, z, beat, ask}

def chests_of(store: Bag.Store) -> Chests.World:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  chests

def furnaces_of(store: Bag.Store) -> Furnaces.World:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  furnaces

def found_slots(found: Chests.Lookup) -> List<&2, Chest.Slot>:
  match found:
    case Chests.ChestFound{slots}:
      slots
    case Chests.ChestMissing{}:
      Chest.empty()

# A chest nobody has opened has no entry, and is empty.
def chest_at(chests: Chests.World, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Chest.Slot>:
  found_slots(Chests.at(chests, x, y, z))

# The slots of the chest whose screen is open.
def chest_slots(store: Bag.Store) -> List<&2, Chest.Slot>:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  chest_at(chests, x, y, z)

def with_chest(store: Bag.Store, slots: List<&2, Chest.Slot>) -> Bag.Store:
  Bag.Store{chests, furnaces, +x, +y, +z, beat, ask} = store
  Bag.Store{Chests.set(chests, x, y, z, slots), furnaces, x, y, z, beat, ask}

def found_furnace(found: Furnaces.Lookup) -> Furnace.Furnace:
  match found:
    case Furnaces.FurnaceFound{furnace}:
      furnace
    case Furnaces.FurnaceMissing{}:
      Furnace.empty()

# The furnace whose screen is open.
def furnace_of(store: Bag.Store) -> Furnace.Furnace:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  found_furnace(Furnaces.at(furnaces, x, y, z))

def added_world(result: Furnaces.WorldResult) -> Furnaces.World:
  Furnaces.WorldResult{world, ok} = result
  world

# `Furnaces.set` only replaces a furnace that has an entry, so one is added first.
def with_furnace(store: Bag.Store, furnace: Furnace.Furnace) -> Bag.Store:
  Bag.Store{chests, furnaces, +x, +y, +z, beat, ask} = store
  Bag.Store{chests, Furnaces.set(added_world(Furnaces.add(furnaces, x, y, z)), x, y, z, furnace), x, y, z,
    beat, ask}

# --- a room's requests -------------------------------------------------------------

def ask_of(store: Bag.Store) -> Bag.Ask:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  ask

def shared(store: Bag.Store) -> Bool:
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{shared, line, kind, given}} = store
  shared

def waiting(store: Bag.Store) -> Bool:
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{shared, line, kind, given}} = store
  U32.is_ne(kind, 0)

# The store with a request left in it for the session to send.
def asking(store: Bag.Store, line: String, kind: U32, given: U32) -> Bag.Store:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{True{}, line, kind, given}}

def line_of(store: Bag.Store) -> String:
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{shared, line, kind, given}} = store
  line

# The store once its request is on its way: the line is gone and the answer is awaited.
def sent(store: Bag.Store) -> Bag.Store:
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{shared, line, kind, given}} = store
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{shared, "", kind, given}}

def answered.held(kind: Nat, +ok: Bool, +held: Inventory.Slot, +given: U32, +item: U32, +amount: U32,
  +durability: U32) -> Inventory.Slot:
  match kind:
    case 1n:
      Bool.pick(Inventory.Slot, ok, Inventory.stack(item, amount, durability), held)
    case 2n:
      Bool.pick(Inventory.Slot, ok,
        Inventory.stack(Inventory.slot_item(held), U32.sub(Inventory.slot_count_value(held), U32.min(given, Inventory.slot_count_value(held))),
          Inventory.slot_durability(held)), held)
    case 3n:
      Bool.pick(Inventory.Slot, ok,
        Inventory.stack(Inventory.slot_item(held), U32.sub(Inventory.slot_count_value(held), U32.min(given, Inventory.slot_count_value(held))),
          Inventory.slot_durability(held)), held)
    case 4n:
      Bool.pick(Inventory.Slot, ok, Inventory.make_slot(item, U32.add(amount, Inventory.slot_count_value(held)), 0), held)
    case _:
      held

# The room's answer to the request that was waiting: the arrow as the room's word leaves it,
# and nothing waiting any more.
def answered(store: Bag.Store, held: Inventory.Slot, ok: Bool, item: U32, amount: U32, durability: U32) -> Moved:
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{shared, line, kind, given}} = store
  Moved{answered.held(U32.to_nat(kind), ok, held, given, item, amount, durability),
    Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{shared, line, 0, 0}}}

# --- what a room says a cell holds -------------------------------------------------

def put.slots(values: List<&2, U32>, acc: List<&2, Chest.Slot>) -> List<&2, Chest.Slot>:
  match values:
    case item <> count <> durability <> rest:
      put.slots(rest, Chest.make_slot(item, count, durability) <> acc)
    case _:
      List.reverse(&2, Chest.Slot, acc)

def chests_gone(result: Chests.WorldResult) -> Chests.World:
  Chests.WorldResult{world, ok} = result
  world

def furnaces_gone(result: Furnaces.WorldResult) -> Furnaces.World:
  Furnaces.WorldResult{world, ok} = result
  world

def put.chest(gone: Bool, +chests: Chests.World, +x: Nat, +y: Nat, +z: Nat, values: List<&2, U32>) -> Chests.World:
  match gone:
    case True{}:
      chests_gone(Chests.remove(chests, x, y, z))
    case False{}:
      Chests.set(chests, x, y, z, put.slots(values, []))

def put.furnace(values: List<&2, U32>, +furnaces: Furnaces.World, +x: Nat, +y: Nat, +z: Nat) -> Furnaces.World:
  match values:
    case a <> b <> c <> d <> e <> f <> g <> h <> Nil{}:
      Furnaces.set(furnaces_gone(Furnaces.add(furnaces, x, y, z)), x, y, z, Furnace.Furnace{a, b, c, d, e, f, g, h})
    case _:
      furnaces_gone(Furnaces.remove(furnaces, x, y, z))

def put.at(furnace: Bool, +values: List<&2, U32>, +bx: Nat, +by: Nat, +bz: Nat, store: Bag.Store) -> Bag.Store:
  match furnace:
    case False{}:
      Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
      Bag.Store{put.chest(List.is_empty(&2, U32, values), chests, bx, by, bz, values), furnaces, x, y, z, beat, ask}
    case True{}:
      Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
      Bag.Store{chests, put.furnace(values, furnaces, bx, by, bz), x, y, z, beat, ask}

# The store with one cell as the room says it is: a chest's slots or a furnace's numbers,
# or the cell with neither when the room names none. The open screen's cell is untouched.
def put(store: Bag.Store, box: Net.Box) -> Bag.Store:
  Net.Box{furnace, bx, by, bz, values} = box
  put.at(furnace, values, bx, by, bz, store)

def cell_x(store: Bag.Store) -> Nat:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  x

def cell_y(store: Bag.Store) -> Nat:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  y

def cell_z(store: Bag.Store) -> Nat:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  z

# --- a chest -----------------------------------------------------------------------

def chest_count(slots: List<&2, Chest.Slot>, index: Nat) -> U32:
  match slots:
    case Nil{}:
      0
    case head <> rest:
      match index:
        case 0n:
          Chest.slot_count_value(head)
        case 1n+below:
          chest_count(rest, below)

def withdrawn(result: Chest.WithdrawResult, +store: Bag.Store) -> Moved:
  Chest.WithdrawResult{slots, item, amount, durability, ok} = result
  match ok:
    case True{}:
      Moved{Inventory.stack(item, amount, durability), with_chest(store, slots)}
    case False{}:
      Moved{Inventory.make_slot(0, 0, 0), store}

def deposited(result: Chest.DepositResult, +store: Bag.Store, +item: U32, +count: U32, +given: U32,
  +durability: U32) -> Moved:
  Chest.DepositResult{slots, ok} = result
  match ok:
    case True{}:
      Moved{Inventory.stack(item, U32.sub(count, given), durability), with_chest(store, slots)}
    case False{}:
      Moved{Inventory.stack(item, count, durability), store}

# In a room: a withdrawal of a slot that holds something, or a deposit of what the arrow
# carries, asked of the room. Nothing is asked for an empty slot.
def chest_ask.at(carrying: Bool, +store: Bag.Store, +item: U32, +count: U32, +durability: U32,
  +index: Nat, +right: Bool) -> Moved:
  match carrying:
    case False{}:
      Moved{Inventory.make_slot(0, 0, 0),
        Bool.pick(Bag.Store, U32.is_gt(chest_count(chest_slots(store), index), 0),
          asking(store, Net.withdraw_line(cell_x(store), cell_y(store), cell_z(store), index,
              Bool.pick(U32, right, U32.div(U32.add(chest_count(chest_slots(store), index), 1), 2), Chest.max_stack())),
            1, 0),
          store)}
    case True{}:
      Moved{Inventory.make_slot(item, count, durability),
        asking(store, Net.deposit_line(cell_x(store), cell_y(store), cell_z(store), item,
            Bool.pick(U32, right, 1, count), durability),
          2, Bool.pick(U32, right, 1, count))}

def chest_click.at(carrying: Bool, +store: Bag.Store, +item: U32, +count: U32, +durability: U32,
  +index: Nat, +right: Bool) -> Moved:
  match carrying:
    case False{}:
      withdrawn(Chest.withdraw(chest_slots(store), index,
          Bool.pick(U32, right, U32.div(U32.add(chest_count(chest_slots(store), index), 1), 2), Chest.max_stack())),
        store)
    case True{}:
      deposited(Chest.deposit(chest_slots(store), item, Bool.pick(U32, right, 1, count), durability),
        store, item, count, Bool.pick(U32, right, 1, count), durability)

# `mine` is whether the chest is the client's own: 0 it is, 1 it is a room's and a request
# can be made, 2 it is a room's and one is already waiting.
def chest_click.own(mine: Nat, +carrying: Bool, +store: Bag.Store, +item: U32, +count: U32,
  +durability: U32, +index: Nat, +right: Bool) -> Moved:
  match mine:
    case 0n:
      chest_click.at(carrying, store, item, count, durability, index, right)
    case 1n:
      chest_ask.at(carrying, store, item, count, durability, index, right)
    case _:
      Moved{Inventory.make_slot(item, count, durability), store}

def owner(+store: Bag.Store) -> Nat:
  U32.to_nat(Bool.pick(U32, shared(store), Bool.pick(U32, waiting(store), 2, 1), 0))


# One click on slot `index` of the open chest.
def chest_click(+store: Bag.Store, held: Inventory.Slot, +index: Nat, +right: Bool) -> Moved:
  Inventory.Slot{+item, +count, +durability} = held
  chest_click.own(owner(store), U32.is_gt(count, 0), store, item, count, durability, index, right)

def chest_shown.go(slots: List<&2, Chest.Slot>, acc: List<&2, Inventory.Slot>) -> List<&2, Inventory.Slot>:
  match slots:
    case Nil{}:
      List.reverse(&2, Inventory.Slot, acc)
    case Chest.Slot{item, count, durability} <> rest:
      chest_shown.go(rest, Inventory.make_slot(item, count, durability) <> acc)

# The open chest's slots as a screen draws them.
def chest_shown(store: Bag.Store) -> List<&2, Inventory.Slot>:
  chest_shown.go(chest_slots(store), [])

# --- a furnace ---------------------------------------------------------------------

def loaded(result: Furnace.FurnaceResult, +store: Bag.Store, +item: U32, +count: U32, +given: U32,
  +durability: U32) -> Moved:
  Furnace.FurnaceResult{furnace, ok} = result
  match ok:
    case True{}:
      Moved{Inventory.stack(item, U32.sub(count, given), durability), with_furnace(store, furnace)}
    case False{}:
      Moved{Inventory.stack(item, count, durability), store}

def taken.at(joins: Bool, +store: Bag.Store, furnace: Furnace.Furnace, +item: U32, +amount: U32,
  +held: Inventory.Slot) -> Moved:
  match joins:
    case True{}:
      Moved{Inventory.make_slot(item, U32.add(amount, Inventory.slot_count_value(held)), 0),
        with_furnace(store, furnace)}
    case False{}:
      Moved{held, store}

def taken(result: Furnace.TransferResult, +store: Bag.Store, +held: Inventory.Slot) -> Moved:
  Furnace.TransferResult{furnace, +item, +amount, ok} = result
  taken.at(Bool.and(ok,
      Bool.or(U32.is_eq(Inventory.slot_count_value(held), 0),
        Bool.and(U32.is_eq(Inventory.slot_item(held), item),
          U32.is_le(U32.add(Inventory.slot_count_value(held), amount), Inventory.max_stack())))),
    store, furnace, item, amount, held)

def furnace_click.at(which: Nat, +store: Bag.Store, +held: Inventory.Slot, +given: U32) -> Moved:
  match which:
    case 0n:
      loaded(Furnace.load_input(furnace_of(store), Inventory.slot_item(held), U32.to_nat(given)), store,
        Inventory.slot_item(held), Inventory.slot_count_value(held), given, Inventory.slot_durability(held))
    case 1n:
      loaded(Furnace.load_fuel(furnace_of(store), Inventory.slot_item(held), U32.to_nat(given)), store,
        Inventory.slot_item(held), Inventory.slot_count_value(held), given, Inventory.slot_durability(held))
    case _:
      taken(Furnace.take_output(furnace_of(store)), store, held)

def made_item(furnace: Furnace.Furnace) -> U32:
  Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn} = furnace
  output

def made_count(furnace: Furnace.Furnace) -> U32:
  Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn} = furnace
  output_count

# In a room: one item of what the arrow carries offered to the furnace, or what it made
# asked for when the arrow could take it.
def furnace_ask(which: Nat, +store: Bag.Store, +held: Inventory.Slot) -> Moved:
  match which:
    case 2n:
      Moved{held, Bool.pick(Bag.Store,
        Bool.and(U32.is_gt(made_count(furnace_of(store)), 0),
          Bool.or(U32.is_eq(Inventory.slot_count_value(held), 0),
            Bool.and(U32.is_eq(Inventory.slot_item(held), made_item(furnace_of(store))),
              U32.is_le(U32.add(Inventory.slot_count_value(held), made_count(furnace_of(store))), Inventory.max_stack())))),
        asking(store, Net.furnace_line(2n, cell_x(store), cell_y(store), cell_z(store), 0), 4, 0), store)}
    case 1n:
      Moved{held, Bool.pick(Bag.Store, U32.is_gt(Inventory.slot_count_value(held), 0),
        asking(store, Net.furnace_line(1n, cell_x(store), cell_y(store), cell_z(store), Inventory.slot_item(held)), 3, 1),
        store)}
    case _:
      Moved{held, Bool.pick(Bag.Store, U32.is_gt(Inventory.slot_count_value(held), 0),
        asking(store, Net.furnace_line(0n, cell_x(store), cell_y(store), cell_z(store), Inventory.slot_item(held)), 3, 1),
        store)}

def furnace_click.own(mine: Nat, which: Nat, +store: Bag.Store, +held: Inventory.Slot, right: Bool) -> Moved:
  match mine:
    case 0n:
      furnace_click.at(which, store, held,
        Bool.pick(U32, right, U32.min(Inventory.slot_count_value(held), 1), Inventory.slot_count_value(held)))
    case 1n:
      furnace_ask(which, store, held)
    case _:
      Moved{held, store}

# One click on the open furnace: `which` is 0 for what it smelts, 1 for its fuel and 2 for
# what it made.
def furnace_click(+store: Bag.Store, +held: Inventory.Slot, which: Nat, right: Bool) -> Moved:
  furnace_click.own(owner(store), which, store, held, right)

# --- time --------------------------------------------------------------------------

# A furnace's rule counts in steps, and a step is a second: sixty of the client's ticks.
def beat_ticks() -> U32:
  60

def ticked.at(due: Bool, store: Bag.Store) -> Bag.Store:
  match due:
    case True{}:
      Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
      Bag.Store{chests, Furnaces.tick_world(furnaces), x, y, z, 0, Bag.idle()}
    case False{}:
      Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
      Bag.Store{chests, furnaces, x, y, z, U32.add(beat, 1), Bag.idle()}

def beat_of(store: Bag.Store) -> U32:
  Bag.Store{chests, furnaces, x, y, z, beat, ask} = store
  beat

# The store one client tick on, out of a room: every furnace steps once a second, open or
# not, and nothing is being asked of anyone.
def ticked(+store: Bag.Store) -> Bag.Store:
  ticked.at(U32.is_ge(U32.add(beat_of(store), 1), beat_ticks()), store)

# The store one tick on in a room: the room steps the furnaces and says what they became,
# so nothing moves here. The store is marked as the room's.
def roomed(store: Bag.Store) -> Bag.Store:
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{shared, line, kind, given}} = store
  Bag.Store{chests, furnaces, x, y, z, beat, Bag.Ask{True{}, line, kind, given}}

# --- digging -----------------------------------------------------------------------

def any_held(slots: List<&2, Chest.Slot>) -> Bool:
  match slots:
    case Nil{}:
      False{}
    case head <> rest:
      Bool.or(U32.is_gt(Chest.slot_count_value(head), 0), any_held(rest))

# A chest that still holds something cannot be dug: it is emptied first, as in the browser.
def locked(store: Bag.Store, +block: U32, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Bool.and(U32.is_eq(block, World.chest_block()), any_held(chest_at(chests_of(store), x, y, z)))

def chests_without(result: Chests.WorldResult) -> Chests.World:
  Chests.WorldResult{world, ok} = result
  world

# The store after a block was dug: a chest's or a furnace's entry goes with its block.
def forgot(store: Bag.Store, +block: U32, +x: Nat, +y: Nat, +z: Nat) -> Bag.Store:
  Bag.Store{+chests, +furnaces, ox, oy, oz, beat, ask} = store
  Bag.Store{
    Bool.pick(Chests.World, U32.is_eq(block, World.chest_block()), chests_without(Chests.remove(chests, x, y, z)), chests),
    Bool.pick(Furnaces.World, U32.is_eq(block, World.furnace_block()), added_world(Furnaces.remove(furnaces, x, y, z)), furnaces),
    ox, oy, oz, beat, ask}
