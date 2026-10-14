import Base
import ./chest.bend as Chest

type Entry is Data:
  Entry{x: Nat, y: Nat, z: Nat, slots: List<&2, Chest.Slot>}

type World is Data:
  World{entries: List<&2, Entry>}

type Lookup is Data:
  ChestFound{slots: List<&2, Chest.Slot>}
  ChestMissing{}

type WorldResult is Data:
  WorldResult{world: World, ok: Bool}

type RemoveResult is Data:
  RemoveResult{entries: List<&2, Entry>, removed: Bool}

def empty() -> World:
  World{Nil{}}

def make_entry(x: Nat, y: Nat, z: Nat, slots: List<&2, Chest.Slot>) -> Entry:
  Entry{x, y, z, slots}

def entries(state: World) -> List<&2, Entry>:
  World{+entries} = state
  entries

def lookup_slots(state: Lookup) -> List<&2, Chest.Slot>:
  match state:
    case ChestFound{+slots}:
      slots
    case ChestMissing{}:
      Nil{}

def same_position(entry: Entry, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Entry{+ex, +ey, +ez, slots} = entry
  Bool.and(Bool.and(Nat.is_eq(ex, x), Nat.is_eq(ey, y)), Nat.is_eq(ez, z))

def at.entries(entries: List<&2, Entry>, +x: Nat, +y: Nat, +z: Nat) -> Lookup:
  match entries:
    case Nil{}:
      ChestMissing{}
    case Con{+head, +tail}:
      Entry{+ex, +ey, +ez, +slots} = head
      +same = Bool.and(Bool.and(Nat.is_eq(ex, x), Nat.is_eq(ey, y)), Nat.is_eq(ez, z))
      Bool.pick(Lookup, same, ChestFound{slots}, at.entries(tail, x, y, z))

def at(state: World, +x: Nat, +y: Nat, +z: Nat) -> Lookup:
  World{+stored} = state
  at.entries(stored, x, y, z)

def add.finalize(
  state: World, stored: List<&2, Entry>, +x: Nat, +y: Nat, +z: Nat, found: Lookup
) -> WorldResult:
  match found:
    case ChestFound{slots}:
      WorldResult{state, False{}}
    case ChestMissing{}:
      WorldResult{World{Con{make_entry(x, y, z, Chest.empty()), stored}}, True{}}

def add(+state: World, +x: Nat, +y: Nat, +z: Nat) -> WorldResult:
  World{+stored} = state
  +found = at.entries(stored, x, y, z)
  add.finalize(state, stored, x, y, z, found)

def remove_entries_entries(state: RemoveResult) -> List<&2, Entry>:
  RemoveResult{+entries, removed} = state
  entries

def remove_removed(state: RemoveResult) -> Bool:
  RemoveResult{entries, +removed} = state
  removed

def remove_entries.choose(
  +same: Bool, tail: List<&2, Entry>, head: Entry, +rest: RemoveResult
) -> RemoveResult:
  match same:
    case True{}:
      RemoveResult{tail, True{}}
    case False{}:
      RemoveResult{Con{head, remove_entries_entries(rest)}, remove_removed(rest)}

def remove_entries(entries: List<&2, Entry>, +x: Nat, +y: Nat, +z: Nat) -> RemoveResult:
  match entries:
    case Nil{}:
      RemoveResult{Nil{}, False{}}
    case Con{+head, +tail}:
      +same = same_position(head, x, y, z)
      +rest = remove_entries(tail, x, y, z)
      remove_entries.choose(same, tail, head, rest)

def remove(state: World, +x: Nat, +y: Nat, +z: Nat) -> WorldResult:
  World{+stored} = state
  +result = remove_entries(stored, x, y, z)
  WorldResult{World{remove_entries_entries(result)}, remove_removed(result)}

def set.finalize(
  result: WorldResult, +x: Nat, +y: Nat, +z: Nat,
  replacement: List<&2, Chest.Slot>
) -> World:
  WorldResult{+world, removed} = result
  World{+stored} = world
  World{Con{make_entry(x, y, z, replacement), stored}}

def set(
  state: World, +x: Nat, +y: Nat, +z: Nat, replacement: List<&2, Chest.Slot>
) -> World:
  +removed = remove(state, x, y, z)
  set.finalize(removed, x, y, z, replacement)
