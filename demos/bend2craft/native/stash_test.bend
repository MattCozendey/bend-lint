import Base
import ../world/inventory.bend as Inventory
import ../world/furnace.bend as Furnace
import ./bag.bend as Bag
import ./stores.bend as Stores
import ./stash.bend as Stash

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "stash: " ++ message)

def holds(slot: Inventory.Slot, want_item: U32, want_count: U32, want_wear: U32) -> Bool:
  Inventory.Slot{item, count, durability} = slot
  Bool.and(U32.is_eq(item, want_item), Bool.and(U32.is_eq(count, want_count), U32.is_eq(durability, want_wear)))

def slot_of(bag: Bag.Bag, +index: Nat) -> Inventory.Slot:
  Bag.held.of(Inventory.lookup(Bag.slots_of(bag), index))

def store_after(moved: Stores.Moved) -> Bag.Store:
  Stores.Moved{held, store} = moved
  store

# A bag that is not the starting one: a worn pickaxe in the tenth slot, the fourth hotbar
# slot in hand, a chest west of the origin with ten stone in it, and a furnace with sand
# and coal that has burned for two seconds.
def ticks(remaining: Nat, +store: Bag.Store) -> Bag.Store:
  match remaining:
    case 0n:
      store
    case 1n+rest:
      ticks(rest, Stores.ticked(store))

def stores() -> Bag.Store:
  ticks(120n, store_after(Stores.furnace_click(
    store_after(Stores.furnace_click(
      Stores.aimed(store_after(Stores.chest_click(Stores.aimed(Bag.stores(), 94371839n, 9n, 25n), Inventory.make_slot(1, 10, 0), 0n, False{})),
        30n, 9n, 25n),
      Inventory.make_slot(6, 5, 0), 0n, False{})),
    Inventory.make_slot(14, 3, 0), 1n, False{})))

def packed() -> Bag.Bag:
  Bag.Bag{Inventory.replace_at(Bag.slots_of(Bag.start()), 9n, Inventory.make_slot(19, 1, 77)), 3n, Bag.shut(), stores()}

def chest_slot(bag: Bag.Bag, x: Nat, y: Nat, z: Nat) -> Inventory.Slot:
  Bag.held.of(Inventory.lookup(Stores.chest_shown(Stores.aimed(Bag.store_of(bag), x, y, z)), 0n))

def same_furnace(a: Furnace.Furnace, b: Furnace.Furnace) -> Bool:
  Furnace.Furnace{ai, aic, af, afc, ao, aoc, ap, ab} = a
  Furnace.Furnace{bi, bic, bf, bfc, bo, boc, bp, bb} = b
  Bool.and(Bool.and(Bool.and(U32.is_eq(ai, bi), U32.is_eq(aic, bic)), Bool.and(U32.is_eq(af, bf), U32.is_eq(afc, bfc))),
    Bool.and(Bool.and(U32.is_eq(ao, bo), U32.is_eq(aoc, boc)), Bool.and(U32.is_eq(ap, bp), U32.is_eq(ab, bb))))

def furnace_at(bag: Bag.Bag) -> Furnace.Furnace:
  Stores.furnace_of(Stores.aimed(Bag.store_of(bag), 30n, 9n, 25n))

# What is written is read back the same: every slot with its wear, the slot in hand, each
# chest at its cell and each furnace as far along as it was.
def a_stash_reads_back() -> IO(Unit):
  do IO<Unit>:
    +back : Bag.Bag = Stash.decode(Stash.encode(packed()), Bag.start())
    Unit <- check(holds(slot_of(back, 0n), 1, 32, 0), "the first slot did not read back")
    Unit <- check(holds(slot_of(back, 9n), 19, 1, 77), "a worn tool did not read back with its wear")
    Unit <- check(Nat.is_eq(Bag.selected_of(back), 3n), "the slot in hand did not read back")
    Unit <- check(holds(chest_slot(back, 94371839n, 9n, 25n), 1, 10, 0), "a chest west of the origin did not read back")
    Unit <- check(holds(chest_slot(back, 30n, 9n, 25n), 0, 0, 0), "a furnace's cell reads back as a chest")
    Unit <- check(same_furnace(furnace_at(back), furnace_at(packed())), "a furnace did not read back as far along as it was")
    check(Bool.not(Bag.is_open(back)), "a stash reads back with a screen open")

# Text that is not a stash is the fallback: nothing, another file's text, or a stash cut
# short of its slots.
def what_is_not_a_stash_is_refused() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(holds(slot_of(Stash.decode("", packed()), 9n), 19, 1, 77), "no text was read as a stash")
    Unit <- check(holds(slot_of(Stash.decode("B2CW:1\n1337\n", packed()), 9n), 19, 1, 77), "a world's save was read as a stash")
    Unit <- check(holds(slot_of(Stash.decode("B2CI:1\nP 0\nS 1 2 0\n", packed()), 9n), 19, 1, 77), "a stash of one slot was read")
    check(holds(slot_of(Stash.decode(Stash.encode(packed()) ++ "Q 1 2 3\nS x y z\n", Bag.start()), 9n), 19, 1, 77), "a line that is not a record spoiled the stash")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- a_stash_reads_back()
    Unit <- what_is_not_a_stash_is_refused()
    IO.print("stash: a round trip and what is not a stash passed")
