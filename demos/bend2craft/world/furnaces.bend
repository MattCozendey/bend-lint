import Base
import ./furnace.bend as Furnace

type Entry is Data:
  Entry{x: Nat, y: Nat, z: Nat, furnace: Furnace.Furnace}

type World is Data:
  World{entries: List<&2, Entry>}

type Lookup is Data:
  FurnaceFound{furnace: Furnace.Furnace}
  FurnaceMissing{}

type WorldResult is Data:
  WorldResult{world: World, ok: Bool}

type RemoveResult is Data:
  RemoveResult{entries: List<&2, Entry>, removed: Bool}

def removed_entries(state: RemoveResult) -> List<&2, Entry>:
  RemoveResult{entries, removed} = state
  entries

def was_removed(state: RemoveResult) -> Bool:
  RemoveResult{entries, removed} = state
  removed

def empty() -> World:
  World{Nil{}}

def make_entry(x: Nat, y: Nat, z: Nat, furnace: Furnace.Furnace) -> Entry:
  Entry{x, y, z, furnace}

def entries(state: World) -> List<&2, Entry>:
  World{entries} = state
  entries

def same_position(entry: Entry, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Entry{+ex, +ey, +ez, furnace} = entry
  Bool.and(Bool.and(Nat.is_eq(ex, x), Nat.is_eq(ey, y)), Nat.is_eq(ez, z))

def at.entries(entries: List<&2, Entry>, +x: Nat, +y: Nat, +z: Nat) -> Lookup:
  match entries:
    case Nil{}:
      FurnaceMissing{}
    case Con{+head, +tail}:
      Entry{+ex, +ey, +ez, +furnace} = head
      +same = Bool.and(Bool.and(Nat.is_eq(ex, x), Nat.is_eq(ey, y)), Nat.is_eq(ez, z))
      Bool.pick(Lookup, same, FurnaceFound{furnace}, at.entries(tail, x, y, z))

def at(+state: World, +x: Nat, +y: Nat, +z: Nat) -> Lookup:
  World{+stored} = state
  at.entries(stored, x, y, z)

def add.finalize(+state: World, stored: List<&2, Entry>, +x: Nat, +y: Nat, +z: Nat, found: Lookup) -> WorldResult:
  match found:
    case FurnaceFound{furnace}:
      WorldResult{state, False{}}
    case FurnaceMissing{}:
      WorldResult{World{make_entry(x, y, z, Furnace.empty()) <> stored}, True{}}

def add(+state: World, +x: Nat, +y: Nat, +z: Nat) -> WorldResult:
  World{+stored} = state
  +found = at(state, x, y, z)
  add.finalize(state, stored, x, y, z, found)

def replace_entries(
  entries: List<&2, Entry>, +x: Nat, +y: Nat, +z: Nat, +replacement: Furnace.Furnace
) -> List<&2, Entry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Entry{+ex, +ey, +ez, +furnace} = head
      +same = Bool.and(Bool.and(Nat.is_eq(ex, x), Nat.is_eq(ey, y)), Nat.is_eq(ez, z))
      +updated = make_entry(ex, ey, ez, replacement)
      Con{Bool.pick(Entry, same, updated, head), replace_entries(tail, x, y, z, replacement)}

def set(+state: World, +x: Nat, +y: Nat, +z: Nat, replacement: Furnace.Furnace) -> World:
  World{+stored} = state
  World{replace_entries(stored, x, y, z, replacement)}

def remove_entries.choose(
  +same: Bool, tail: List<&2, Entry>, head: Entry, +rest: RemoveResult
) -> RemoveResult:
  match same:
    case True{}:
      RemoveResult{tail, True{}}
    case False{}:
      RemoveResult{Con{head, removed_entries(rest)}, was_removed(rest)}

def remove_entries(entries: List<&2, Entry>, +x: Nat, +y: Nat, +z: Nat) -> RemoveResult:
  match entries:
    case Nil{}:
      RemoveResult{Nil{}, False{}}
    case Con{+head, +tail}:
      +same = same_position(head, x, y, z)
      +rest = remove_entries(tail, x, y, z)
      remove_entries.choose(same, tail, head, rest)

def remove(+state: World, +x: Nat, +y: Nat, +z: Nat) -> WorldResult:
  World{+stored} = state
  +result = remove_entries(stored, x, y, z)
  WorldResult{World{removed_entries(result)}, was_removed(result)}

def tick_entries(entries: List<&2, Entry>) -> List<&2, Entry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Entry{+x, +y, +z, +furnace} = head
      +step = Furnace.tick(furnace)
      Con{Entry{x, y, z, Furnace.step_furnace(step)}, tick_entries(tail)}

def tick_world(+state: World) -> World:
  World{+stored} = state
  World{tick_entries(stored)}
