import Base
import ../world/inventory.bend as Inventory
import ../world/chest.bend as Chest
import ../world/chests.bend as Chests
import ../world/furnace.bend as Furnace
import ../world/furnaces.bend as Furnaces
import ./bag.bend as Bag
import ./stores.bend as Stores

# Stash: the bag and the world's chests and furnaces, as text beside the world's save.
#
# `B2CW:1` is the world's seed and its edit log and nothing else (`native/save.bend`), and it
# is a format the browser's and the room's snapshots migrate into, so what a player carries
# is not put in it. It goes in a file of its own, `B2CI:1`, one record a line, every field a
# whole number:
#
#   B2CI:1
#   P <selected>                                    the hotbar slot in hand
#   S <item> <count> <durability>                   a slot of the bag, in order, thirty-six
#   C <x> <y> <z> <item> <count> <durability> ...   a chest: its cell, then its slots
#   F <x> <y> <z> <eight numbers>                   a furnace: its cell, then its fields in order
#
# A cell is spelled as storage spells it, like an edit's. A file that does not start with
# the header, or does not hold thirty-six slots, is no stash: the client starts with the
# bag it always started with. A line that is not one of these is skipped.
#
# What is on the arrow and in the crafting grid is not written: a save is taken of the bag
# as closing the screen leaves it.

def header() -> String:
  "B2CI:1"

# --- writing -----------------------------------------------------------------------

def triple(+item: U32, +count: U32, +durability: U32) -> String:
  U32.show(item) ++ " " ++ U32.show(count) ++ " " ++ U32.show(durability)

def cell(+x: Nat, +y: Nat, +z: Nat) -> String:
  Nat.show(x) ++ " " ++ Nat.show(y) ++ " " ++ Nat.show(z)

def slot_lines(slots: List<&2, Inventory.Slot>, acc: String) -> String:
  match slots:
    case Nil{}:
      acc
    case Inventory.Slot{item, count, durability} <> rest:
      slot_lines(rest, acc ++ "S " ++ triple(item, count, durability) ++ "\n")

def chest_fields(slots: List<&2, Chest.Slot>, acc: String) -> String:
  match slots:
    case Nil{}:
      acc
    case Chest.Slot{item, count, durability} <> rest:
      chest_fields(rest, acc ++ " " ++ triple(item, count, durability))

def chest_lines(entries: List<&2, Chests.Entry>, acc: String) -> String:
  match entries:
    case Nil{}:
      acc
    case Chests.Entry{x, y, z, slots} <> rest:
      chest_lines(rest, acc ++ "C " ++ cell(x, y, z) ++ chest_fields(slots, "") ++ "\n")

def furnace_fields(furnace: Furnace.Furnace) -> String:
  Furnace.Furnace{input, input_count, fuel, fuel_count, output, output_count, progress, burn} = furnace
  U32.show(input) ++ " " ++ U32.show(input_count) ++ " " ++ U32.show(fuel) ++ " " ++ U32.show(fuel_count)
    ++ " " ++ U32.show(output) ++ " " ++ U32.show(output_count) ++ " " ++ U32.show(progress) ++ " "
    ++ U32.show(burn)

def furnace_lines(entries: List<&2, Furnaces.Entry>, acc: String) -> String:
  match entries:
    case Nil{}:
      acc
    case Furnaces.Entry{x, y, z, furnace} <> rest:
      furnace_lines(rest, acc ++ "F " ++ cell(x, y, z) ++ " " ++ furnace_fields(furnace) ++ "\n")

def encode(bag: Bag.Bag) -> String:
  Bag.Bag{slots, selected, desk, Bag.Store{chests, furnaces, x, y, z, beat, ask}} = bag
  header() ++ "\n" ++ "P " ++ Nat.show(selected) ++ "\n" ++ slot_lines(slots, "")
    ++ chest_lines(Chests.entries(chests), "") ++ furnace_lines(Furnaces.entries(furnaces), "")

# --- reading -----------------------------------------------------------------------

# A line's fields as numbers, and whether every one of them was one.
type Read is Data:
  Read{values: List<&2, U32>, whole: Bool}

def read.one(value: Maybe<&2, U32>, read: Read) -> Read:
  match value:
    case Some{number}:
      Read{values, whole} = read
      Read{number <> values, whole}
    case None{}:
      Read{values, whole} = read
      Read{values, False{}}

def read.go(words: List<&2, String>, read: Read) -> Read:
  match words:
    case Nil{}:
      read
    case word <> rest:
      read.go(rest, read.one(U32.read(word), read))

def read.turned(read: Read) -> List<&2, U32>:
  Read{values, whole} = read
  match whole:
    case True{}:
      List.reverse(&2, U32, values)
    case False{}:
      []

# The numbers of a line's fields, in order, or none when one of them is not a number.
def numbers(words: List<&2, String>) -> List<&2, U32>:
  read.turned(read.go(words, Read{[], True{}}))

# What has been read so far: the bag's slots, last first, the slot in hand, the chests and
# furnaces, and whether the file began as a stash does.
type Loading is Data:
  Loading{slots: List<&2, Inventory.Slot>, selected: Nat, store: Bag.Store, headed: Bool}

def chest_slots(values: List<&2, U32>, acc: List<&2, Chest.Slot>) -> List<&2, Chest.Slot>:
  match values:
    case item <> count <> durability <> rest:
      chest_slots(rest, Chest.make_slot(item, count, durability) <> acc)
    case _:
      List.reverse(&2, Chest.Slot, acc)

def with.slot(values: List<&2, U32>, loading: Loading) -> Loading:
  match values:
    case item <> count <> durability <> Nil{}:
      Loading{slots, selected, store, headed} = loading
      Loading{Inventory.make_slot(item, count, durability) <> slots, selected, store, headed}
    case _:
      Loading{slots, selected, store, headed} = loading
      Loading{slots, selected, store, headed}

def with.hand(values: List<&2, U32>, loading: Loading) -> Loading:
  match values:
    case hand <> Nil{}:
      Loading{slots, selected, store, headed} = loading
      Loading{slots, U32.to_nat(hand), store, headed}
    case _:
      Loading{slots, selected, store, headed} = loading
      Loading{slots, selected, store, headed}

def with.chest(values: List<&2, U32>, loading: Loading) -> Loading:
  match values:
    case x <> y <> z <> rest:
      Loading{slots, selected, store, headed} = loading
      Loading{slots, selected,
        Stores.with_chest(Stores.aimed(store, U32.to_nat(x), U32.to_nat(y), U32.to_nat(z)), chest_slots(rest, [])),
        headed}
    case _:
      Loading{slots, selected, store, headed} = loading
      Loading{slots, selected, store, headed}

def with.furnace(values: List<&2, U32>, loading: Loading) -> Loading:
  match values:
    case x <> y <> z <> a <> b <> c <> d <> e <> f <> g <> h <> Nil{}:
      Loading{slots, selected, store, headed} = loading
      Loading{slots, selected,
        Stores.with_furnace(Stores.aimed(store, U32.to_nat(x), U32.to_nat(y), U32.to_nat(z)),
          Furnace.Furnace{a, b, c, d, e, f, g, h}),
        headed}
    case _:
      Loading{slots, selected, store, headed} = loading
      Loading{slots, selected, store, headed}

def with.header(loading: Loading) -> Loading:
  Loading{slots, selected, store, headed} = loading
  Loading{slots, selected, store, True{}}

def with.tagged(header: Bool, slot: Bool, hand: Bool, chest: Bool, furnace: Bool,
  fields: List<&2, String>, loading: Loading) -> Loading:
  match header slot hand chest furnace:
    case True{} _ _ _ _:
      with.header(loading)
    case False{} True{} _ _ _:
      with.slot(numbers(fields), loading)
    case False{} False{} True{} _ _:
      with.hand(numbers(fields), loading)
    case False{} False{} False{} True{} _:
      with.chest(numbers(fields), loading)
    case False{} False{} False{} False{} True{}:
      with.furnace(numbers(fields), loading)
    case False{} False{} False{} False{} False{}:
      loading

def with.words(words: List<&2, String>, loading: Loading) -> Loading:
  match words:
    case Nil{}:
      loading
    case +tag <> fields:
      with.tagged(String.eq(tag, header()), String.eq(tag, "S"), String.eq(tag, "P"), String.eq(tag, "C"),
        String.eq(tag, "F"), fields, loading)

def load.go(lines: List<&2, String>, loading: Loading) -> Loading:
  match lines:
    case Nil{}:
      loading
    case line <> rest:
      load.go(rest, with.words(String.split(line, Chr{32}), loading))

def loaded.at(sound: Bool, slots: List<&2, Inventory.Slot>, +selected: Nat, store: Bag.Store,
  fallback: Bag.Bag) -> Bag.Bag:
  match sound:
    case True{}:
      Bag.Bag{List.reverse(&2, Inventory.Slot, slots), Bool.pick(Nat, Nat.is_lt(selected, Bag.hotbar()), selected, 0n),
        Bag.shut(), Stores.aimed(store, 0n, 0n, 0n)}
    case False{}:
      fallback

def loaded(loading: Loading, fallback: Bag.Bag) -> Bag.Bag:
  Loading{+slots, selected, store, headed} = loading
  loaded.at(Bool.and(headed, Nat.is_eq(List.length(&2, Inventory.Slot, slots), Inventory.slot_count())),
    slots, selected, store, fallback)

# The bag a stash's text holds, or `fallback` when the text is not a stash.
def decode(text: String, fallback: Bag.Bag) -> Bag.Bag:
  loaded(load.go(String.split(text, Chr{10}), Loading{[], 0n, Bag.stores(), False{}}), fallback)
