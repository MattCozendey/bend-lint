import Base
import ../world/inventory.bend as Inventory
import ../world/world_state.bend as WorldState
import ../world/chests.bend as Chests
import ../world/furnaces.bend as Furnaces

# The native client's inventory: the slots the rules in `world/inventory.bend` act on, and
# which hotbar slot is in the player's hand.
#
# No rule is decided here. Mining is `Inventory.mine_interaction_at` and placing is
# `Inventory.place_interaction`, which are the same two calls the browser makes, so what a
# hand can break, what a block drops, what a tool wears and what an item places are the
# rules' answers on both targets. This module owns only what the rules leave to a client:
# which slot is selected, and how the number keys move it.
#
# `desk` is what the screens add to those (`native/screen.bend`): which one is open — 0 for
# none, 1 the inventory, 2 the crafting table, 3 a chest, 4 a furnace — where its arrow is in
# the window, the stack the arrow carries, and the crafting grid. They are the bag's because they hold items: a stack on the arrow or in the grid is
# in neither of the slots it came from and went to, and it must not be lost between two
# ticks.
type Desk is Data:
  Desk{mode: U32, x: F32, y: F32, held: Inventory.Slot, grid: List<&2, Inventory.Slot>}

# `store` is the world's chests and furnaces, by the cell each stands in, the cell of the
# one whose screen is open, and a count of ticks that paces the furnaces. They ride with the
# bag because everything that happens to them happens together with it: an item leaves a
# slot and enters a chest in one transition, and it must be in exactly one of them after.
#
# `ask` is what a room adds. A room's chests and furnaces are the room's: the store is then
# a copy the room keeps current, and a click is a request, answered a moment later. `shared`
# says the client is in a room; `line` is a request not yet sent; `kind` is the request
# waiting for its answer — 0 none, 1 a withdrawal, 2 a deposit, 3 a furnace loaded, 4 a
# furnace emptied — and `given` how many items the arrow parts with when it is granted.
type Ask is Data:
  Ask{shared: Bool, line: String, kind: U32, given: U32}

type Store is Data:
  Store{chests: Chests.World, furnaces: Furnaces.World, x: Nat, y: Nat, z: Nat, beat: U32, ask: Ask}

def idle() -> Ask:
  Ask{False{}, "", 0, 0}

type Bag is Data:
  Bag{slots: List<&2, Inventory.Slot>, selected: Nat, desk: Desk, store: Store}

# A world with no chest and no furnace in it.
def stores() -> Store:
  Store{Chests.empty(), Furnaces.empty(), 0n, 0n, 0n, 0, idle()}

def store_of(bag: Bag) -> Store:
  Bag{slots, selected, desk, store} = bag
  store

def with_store(bag: Bag, store: Store) -> Bag:
  Bag{slots, selected, desk, old} = bag
  Bag{slots, selected, desk, store}

# A screen that is shut, with nothing on its arrow or in its grid.
def shut() -> Desk:
  Desk{0, 0.0, 0.0, Inventory.make_slot(0, 0, 0), Inventory.empty_grid()}

def desk_of(bag: Bag) -> Desk:
  Bag{slots, selected, desk, store} = bag
  desk

def mode_of(bag: Bag) -> U32:
  Bag{slots, selected, Desk{mode, x, y, held, grid}, store} = bag
  mode

def is_open(bag: Bag) -> Bool:
  U32.is_ne(mode_of(bag), 0)

# The bag with other slots, and everything else as it was.
def with_slots(bag: Bag, slots: List<&2, Inventory.Slot>) -> Bag:
  Bag{old, selected, desk, store} = bag
  Bag{slots, selected, desk, store}

# The first nine slots are the hotbar, and the number keys pick among them.
def hotbar() -> Nat:
  9n

# The rules' own starting inventory, with a diamond pickaxe, a crafting table and a chest in
# the first three empty slots.
#
# `Inventory.create` is five stacks of terrain and no tool, and by the rules a bare hand
# cannot break stone. A tool is made on a crafting table, and by the rules a crafting table
# is itself nine planks in a grid of three by three, which is a crafting table's grid: the
# inventory's own grid of two by two cannot make the first one. So the bag starts with one.
# It starts with a chest because the rules have no recipe that makes one; a furnace is eight
# stone round the edge of the table's grid.
# The pickaxe is older than the screens and is what the digging tests dig with; it can go
# once they make their own.
def start() -> Bag:
  Bag{Inventory.replace_at(Inventory.replace_at(
      Inventory.replace_at(Inventory.create(), 5n,
        Inventory.make_slot(19, 1, Inventory.tool_max_durability(19))),
      6n, Inventory.make_slot(10, 1, 0)), 7n, Inventory.make_slot(43, 1, 0)), 0n, shut(), stores()}

def slots_of(bag: Bag) -> List<&2, Inventory.Slot>:
  Bag{slots, selected, desk, store} = bag
  slots

def selected_of(bag: Bag) -> Nat:
  Bag{slots, selected, desk, store} = bag
  selected

def held.of(found: Inventory.Lookup) -> Inventory.Slot:
  match found:
    case Inventory.Found{slot}:
      slot
    case Inventory.Missing{}:
      Inventory.make_slot(0, 0, 0)

# The slot in the player's hand.
def held(bag: Bag) -> Inventory.Slot:
  Bag{slots, selected, desk, store} = bag
  held.of(Inventory.lookup(slots, selected))

def held_item(bag: Bag) -> U32:
  Inventory.slot_item(held(bag))

# --- selecting -------------------------------------------------------------------
#
# The keys `1` to `9` arrive as their characters, 49 to 57, and a press selects that slot.
# A release selects nothing, and neither does any other key.
def select.key(+code: U32, down: Bool, +selected: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(down, Bool.and(U32.is_ge(code, 49), U32.is_le(code, 57))),
    U32.to_nat(U32.sub(code, 49)), selected)

def select.event(event: Event, +selected: Nat) -> Nat:
  match event:
    case Key{code, down}:
      select.key(code, down, selected)
    case _:
      selected

def select(events: List<&2, Event>, +selected: Nat) -> Nat:
  match events:
    case Nil{}:
      selected
    case +event <> rest:
      select(rest, select.event(event, selected))

def selecting(bag: Bag, events: List<&2, Event>) -> Bag:
  Bag{slots, selected, desk, store} = bag
  Bag{slots, select(events, selected), desk, store}

# --- acting ----------------------------------------------------------------------
#
# Both answers are the rules' `InteractionResult`: the edit to make, the slots after it, and
# whether it happened. A refused action hands the slots back unchanged.

# Mining the block at a stored cell with what is in hand.
def mined(+bag: Bag, +block: U32, +x: Nat, +y: Nat, +z: Nat) -> Inventory.InteractionResult:
  Inventory.mine_interaction_at(slots_of(bag), selected_of(bag), held_item(bag), block, x, y, z)

# Placing what is in hand at a stored cell. An item that places no block is refused by
# saying its target is not empty, which is the one refusal the rule has room for.
def placed(+bag: Bag, +x: Nat, +y: Nat, +z: Nat, target_empty: Bool,
  overlaps_player: Bool) -> Inventory.InteractionResult:
  +item = held_item(bag)
  Inventory.place_interaction(slots_of(bag), selected_of(bag), item,
    Inventory.placed_block(item), x, y, z,
    Bool.and(target_empty, U32.is_ne(Inventory.placed_block(item), 0)), True{},
    overlaps_player)
