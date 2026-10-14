import Base
import ../world/inventory.bend as Inventory
import ../world/chest.bend as Chest
import ../world/furnace.bend as Furnace
import ./bag.bend as Bag
import ./stores.bend as Stores
import ./net.bend as Net

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "stores: " ++ message)

def none() -> Inventory.Slot:
  Inventory.make_slot(0, 0, 0)

def holds(slot: Inventory.Slot, want_item: U32, want_count: U32) -> Bool:
  Inventory.Slot{item, count, durability} = slot
  Bool.and(U32.is_eq(item, want_item), U32.is_eq(count, want_count))

def held_of(moved: Stores.Moved) -> Inventory.Slot:
  Stores.Moved{held, store} = moved
  held

def store_of(moved: Stores.Moved) -> Bag.Store:
  Stores.Moved{held, store} = moved
  store

# A chest at one cell, and the store looking at it.
def here() -> Bag.Store:
  Stores.aimed(Bag.stores(), 30n, 9n, 25n)

def shown(store: Bag.Store, +index: Nat) -> Inventory.Slot:
  Bag.held.of(Inventory.lookup(Stores.chest_shown(store), index))

# A stack on the arrow goes into a chest whole with the left button and one at a time with
# the right; an empty arrow takes a slot whole, or its larger half. The chest is the one at
# the cell the store looks at, and another cell's chest is another chest.
def a_chest_takes_and_gives() -> IO(Unit):
  do IO<Unit>:
    +put : Stores.Moved = Stores.chest_click(here(), Inventory.make_slot(1, 10, 0), 0n, False{})
    Unit <- check(Bool.and(holds(held_of(put), 0, 0), holds(shown(store_of(put), 0n), 1, 10)), "a left click did not put the whole stack in the chest")
    +one : Stores.Moved = Stores.chest_click(here(), Inventory.make_slot(1, 10, 0), 0n, True{})
    Unit <- check(Bool.and(holds(held_of(one), 1, 9), holds(shown(store_of(one), 0n), 1, 1)), "a right click did not put one item in the chest")
    +took : Stores.Moved = Stores.chest_click(store_of(put), none(), 0n, False{})
    Unit <- check(Bool.and(holds(held_of(took), 1, 10), holds(shown(store_of(took), 0n), 0, 0)), "a left click did not take the slot")
    +half : Stores.Moved = Stores.chest_click(store_of(put), none(), 0n, True{})
    Unit <- check(Bool.and(holds(held_of(half), 1, 5), holds(shown(store_of(half), 0n), 1, 5)), "a right click did not take half")
    Unit <- check(holds(held_of(Stores.chest_click(here(), none(), 3n, False{})), 0, 0), "an empty slot gave something")
    Unit <- check(holds(shown(Stores.aimed(store_of(put), 31n, 9n, 25n), 0n), 0, 0), "another cell's chest holds this one's stack")
    +tool : Stores.Moved = Stores.chest_click(here(), Inventory.make_slot(19, 1, 77), 0n, False{})
    check(U32.is_eq(Inventory.slot_durability(held_of(Stores.chest_click(store_of(tool), none(), 0n, False{}))), 77),
      "a tool did not come back out of the chest with its wear")

def furnace(store: Bag.Store) -> Furnace.Furnace:
  Stores.furnace_of(store)

def burning(f: Furnace.Furnace) -> Bool:
  Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn} = f
  U32.is_gt(burn, 0)

def made(f: Furnace.Furnace) -> U32:
  Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn} = f
  output_count

def ticks(remaining: Nat, +store: Bag.Store) -> Bag.Store:
  match remaining:
    case 0n:
      store
    case 1n+rest:
      ticks(rest, Bool.pick(Bag.Store, Stores.shared(store), Stores.roomed(store), Stores.ticked(store)))

# Sand smelts and coal burns: each is loaded by a click on its slot, and anything else is
# refused. Eight seconds of ticks make one glass, which a click on the third slot takes.
def a_furnace_smelts() -> IO(Unit):
  do IO<Unit>:
    +sand : Stores.Moved = Stores.furnace_click(here(), Inventory.make_slot(6, 5, 0), 0n, False{})
    Unit <- check(holds(held_of(sand), 0, 0), "sand was not loaded")
    Unit <- check(holds(held_of(Stores.furnace_click(here(), Inventory.make_slot(2, 5, 0), 0n, False{})), 2, 5), "dirt was loaded to smelt")
    Unit <- check(holds(held_of(Stores.furnace_click(here(), Inventory.make_slot(6, 5, 0), 1n, False{})), 6, 5), "sand was loaded as fuel")
    +coal : Stores.Moved = Stores.furnace_click(store_of(sand), Inventory.make_slot(14, 3, 0), 1n, True{})
    Unit <- check(holds(held_of(coal), 14, 2), "a right click did not load one coal")
    +early : Bag.Store = ticks(120n, store_of(coal))
    Unit <- check(Bool.and(burning(furnace(early)), U32.is_eq(made(furnace(early)), 0)), "two seconds in, the furnace is not burning or has already made something")
    +done : Bag.Store = ticks(480n, store_of(coal))
    Unit <- check(U32.is_eq(made(furnace(done)), 1), "eight seconds did not make one glass")
    +got : Stores.Moved = Stores.furnace_click(done, none(), 2n, False{})
    Unit <- check(holds(held_of(got), 40, 1), "the glass was not taken onto the arrow")
    Unit <- check(U32.is_eq(made(furnace(store_of(got))), 0), "the glass is still in the furnace")
    check(holds(held_of(Stores.furnace_click(done, Inventory.make_slot(1, 3, 0), 2n, False{})), 1, 3), "glass was taken onto an arrow carrying stone")

# A chest that holds something is not dug; an empty one is, and its entry goes with it.
def a_full_chest_is_not_dug() -> IO(Unit):
  do IO<Unit>:
    +full : Bag.Store = store_of(Stores.chest_click(here(), Inventory.make_slot(1, 10, 0), 0n, False{}))
    Unit <- check(Stores.locked(full, 26, 30n, 9n, 25n), "a chest with a stack in it can be dug")
    Unit <- check(Bool.not(Stores.locked(full, 26, 31n, 9n, 25n)), "an empty chest cannot be dug")
    Unit <- check(Bool.not(Stores.locked(full, 1, 30n, 9n, 25n)), "a stone where a chest's entry is cannot be dug")
    check(holds(shown(Stores.forgot(full, 26, 30n, 9n, 25n), 0n), 0, 0), "a dug chest kept its entry")

# A room's chest: the store as the room says it is, with ten stone in the first slot.
def in_room() -> Bag.Store:
  Stores.put(Stores.roomed(here()), Net.Box{False{}, 30n, 9n, 25n, [1, 10, 0, 0, 0, 0]})

# In a room a click changes nothing and leaves a request; the arrow changes when the room
# answers, and by what the room says. A second click before the answer is dropped.
def a_room_is_asked() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(holds(shown(in_room(), 0n), 1, 10), "the room's word is not the chest's slots")
    +asked : Stores.Moved = Stores.chest_click(in_room(), none(), 0n, False{})
    Unit <- check(Bool.and(holds(held_of(asked), 0, 0), holds(shown(store_of(asked), 0n), 1, 10)), "a click on a room's chest moved the stack")
    Unit <- check(String.eq(Stores.line_of(store_of(asked)), "CW 30 9 25 0 64\n"), "a click on a room's chest did not ask for the slot")
    +pending : Bag.Store = Stores.sent(store_of(asked))
    Unit <- check(String.is_empty(Stores.line_of(pending)), "a request sent is still to send")
    Unit <- check(String.is_empty(Stores.line_of(store_of(Stores.chest_click(pending, none(), 0n, False{})))), "a second click asked again before the answer")
    +granted : Stores.Moved = Stores.answered(pending, none(), True{}, 1, 10, 0)
    Unit <- check(holds(held_of(granted), 1, 10), "the room's grant is not on the arrow")
    Unit <- check(Bool.not(Stores.waiting(store_of(granted))), "an answered request is still waiting")
    Unit <- check(holds(held_of(Stores.answered(pending, none(), False{}, 0, 0, 0)), 0, 0), "a refusal put something on the arrow")
    +giving : Stores.Moved = Stores.chest_click(in_room(), Inventory.make_slot(2, 8, 0), 3n, True{})
    Unit <- check(String.eq(Stores.line_of(store_of(giving)), "CD 30 9 25 2 1 0\n"), "a right click on a room's chest did not offer one")
    Unit <- check(holds(held_of(Stores.answered(Stores.sent(store_of(giving)), held_of(giving), True{}, 0, 0, 0)), 2, 7), "a deposit granted did not take one from the arrow")
    Unit <- check(String.is_empty(Stores.line_of(store_of(Stores.chest_click(in_room(), none(), 5n, False{})))), "an empty slot of a room's chest was asked for")
    Unit <- check(String.eq(Stores.line_of(store_of(Stores.furnace_click(in_room(), Inventory.make_slot(6, 5, 0), 0n, False{}))), "FI 30 9 25 6\n"), "sand on a room's furnace was not offered")
    Unit <- check(holds(shown(Stores.put(in_room(), Net.Box{False{}, 30n, 9n, 25n, []}), 0n), 0, 0), "a chest the room says is gone is still there")
    check(U32.is_eq(made(furnace(ticks(600n, Stores.put(in_room(), Net.Box{True{}, 30n, 9n, 25n, [6, 5, 14, 2, 0, 0, 0, 0]})))), 0), "a room's furnace was stepped by the client")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- a_chest_takes_and_gives()
    Unit <- a_furnace_smelts()
    Unit <- a_full_chest_is_not_dug()
    Unit <- a_room_is_asked()
    IO.print("stores: a chest, a furnace, digging them and a room passed")
