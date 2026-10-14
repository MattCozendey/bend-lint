import Base

type Sample is Data:
  Sample{x: Nat, y: Nat, z: Nat, block: U32}

type Cell is Data:
  Cell{x: Nat, y: Nat, z: Nat, age: U32}

type State is Data:
  State{cells: List<&2, Cell>}

type Edit is Data:
  Edit{x: Nat, y: Nat, z: Nat, block: U32}

def fire_block() -> U32:
  24

def max_cells() -> Nat:
  64n

def sample(x: Nat, y: Nat, z: Nat, block: U32) -> Sample:
  Sample{x, y, z, block}

def empty() -> State:
  State{Nil{}}

def state_cells(state: State) -> List<&2, Cell>:
  State{cells} = state
  cells

def sample_matches(sample: Sample, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Sample{+sx, +sy, +sz, block} = sample
  Bool.and(Bool.and(Nat.is_eq(sx, x), Nat.is_eq(sy, y)), Nat.is_eq(sz, z))

def sample_value(sample: Sample) -> U32:
  Sample{sx, sy, sz, +block} = sample
  block

# The first sample of (x, y, z), in one tail-recursive pass that stops there;
# an unsampled cell reads as stone.
def sample_block.go(samples: List<&2, Sample>, stop: Bool, +value: U32, +x: Nat, +y: Nat, +z: Nat) -> U32:
  match samples stop:
    case _ True{}:
      value
    case Nil{} False{}:
      1
    case Con{+head, tail} False{}:
      sample_block.go(tail, sample_matches(head, x, y, z), sample_value(head), x, y, z)

def sample_block(samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  sample_block.go(samples, False{}, 1, x, y, z)

def flammable(+block: U32) -> Bool:
  Bool.or(U32.is_eq(block, 4), U32.is_eq(block, 5))

def same_position(cell: Cell, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Cell{+cx, +cy, +cz, age} = cell
  Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))

def contains(cells: List<&2, Cell>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match cells:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Bool.or(same_position(head, x, y, z), contains(tail, x, y, z))

def append_unique(+cells: List<&2, Cell>, +candidate: Cell) -> List<&2, Cell>:
  Cell{+x, +y, +z, age} = candidate
  Bool.pick(List<&2, Cell>, contains(cells, x, y, z), cells, Con{candidate, cells})

def take(+remaining: Nat, +cells: List<&2, Cell>) -> List<&2, Cell>:
  match remaining:
    case 0n:
      Nil{}
    case 1n+p:
      match cells:
        case Nil{}:
          Nil{}
        case Con{+head, +tail}:
          Con{head, take(p, tail)}

def ignite(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+cells} = state
  State{take(max_cells(), append_unique(cells, Cell{x, y, z, 0}))}

def ignite_lava_at(
  +state: State, +samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat
) -> State:
  +right_flammable = flammable(sample_block(samples, Nat.add(x, 1n), y, z))
  +right_empty = U32.is_eq(sample_block(samples, Nat.add(x, 1n), Nat.add(y, 1n), z), 0)
  +left_flammable = flammable(sample_block(samples, Nat.sub(x, 1n), y, z))
  +left_empty = U32.is_eq(sample_block(samples, Nat.sub(x, 1n), Nat.add(y, 1n), z), 0)
  +front_flammable = flammable(sample_block(samples, x, y, Nat.add(z, 1n)))
  +front_empty = U32.is_eq(sample_block(samples, x, Nat.add(y, 1n), Nat.add(z, 1n)), 0)
  +back_flammable = flammable(sample_block(samples, x, y, Nat.sub(z, 1n)))
  +back_empty = U32.is_eq(sample_block(samples, x, Nat.add(y, 1n), Nat.sub(z, 1n)), 0)
  +right = Bool.and(right_flammable, right_empty)
  +left = Bool.and(left_flammable, left_empty)
  +front = Bool.and(front_flammable, front_empty)
  +back = Bool.and(back_flammable, back_empty)
  Bool.pick(State, right, ignite(state, Nat.add(x, 1n), Nat.add(y, 1n), z),
    Bool.pick(State, left, ignite(state, Nat.sub(x, 1n), Nat.add(y, 1n), z),
      Bool.pick(State, front, ignite(state, x, Nat.add(y, 1n), Nat.add(z, 1n)),
        Bool.pick(State, back, ignite(state, x, Nat.add(y, 1n), Nat.sub(z, 1n)), state))))

# Only lava cells look at their neighbours (a strict Bool.pick would run the
# eight-sample check for every sample).
def ignite_lava_entry(lava: Bool, +state: State, +all: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat) -> State:
  match lava:
    case True{}:
      ignite_lava_at(state, all, x, y, z)
    case False{}:
      state

def ignite_lava_entries(
  +remaining: List<&2, Sample>, +all: List<&2, Sample>, +state: State
) -> State:
  match remaining:
    case Nil{}:
      state
    case Con{+head, +tail}:
      Sample{+x, +y, +z, +block} = head
      ignite_lava_entries(tail, all, ignite_lava_entry(U32.is_eq(block, 21), state, all, x, y, z))

def ignite_lava(+state: State, +samples: List<&2, Sample>) -> State:
  ignite_lava_entries(samples, samples, state)

def support_near(+samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Bool.or(
    Bool.or(
      flammable(sample_block(samples, x, Nat.sub(y, 1n), z)),
      flammable(sample_block(samples, x, Nat.add(y, 1n), z))
    ),
    Bool.or(
      Bool.or(
        flammable(sample_block(samples, Nat.sub(x, 1n), y, z)),
        flammable(sample_block(samples, Nat.add(x, 1n), y, z))
      ),
      Bool.or(
        flammable(sample_block(samples, x, y, Nat.sub(z, 1n))),
        flammable(sample_block(samples, x, y, Nat.add(z, 1n)))
      )
    )
  )

def can_spread(+samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Bool.and(U32.is_eq(sample_block(samples, x, y, z), 0), support_near(samples, x, y, z))

def spread(cell: Cell, +samples: List<&2, Sample>) -> List<&2, Cell>:
  Cell{+x, +y, +z, age} = cell
  +east = Bool.pick(List<&2, Cell>, can_spread(samples, Nat.add(x, 1n), y, z), Con{Cell{Nat.add(x, 1n), y, z, 0}, Nil{}}, Nil{})
  +west = Bool.pick(List<&2, Cell>, can_spread(samples, Nat.sub(x, 1n), y, z), Con{Cell{Nat.sub(x, 1n), y, z, 0}, east}, east)
  +south = Bool.pick(List<&2, Cell>, can_spread(samples, x, y, Nat.add(z, 1n)), Con{Cell{x, y, Nat.add(z, 1n), 0}, west}, west)
  Bool.pick(List<&2, Cell>, can_spread(samples, x, y, Nat.sub(z, 1n)), Con{Cell{x, y, Nat.sub(z, 1n), 0}, south}, south)

def append_cells(+candidates: List<&2, Cell>, +cells: List<&2, Cell>) -> List<&2, Cell>:
  match candidates:
    case Nil{}:
      cells
    case Con{+head, +tail}:
      append_cells(tail, append_unique(cells, head))

def tick_entries(
  +remaining: List<&2, Cell>, +samples: List<&2, Sample>, +result: List<&2, Cell>
) -> List<&2, Cell>:
  match remaining:
    case Nil{}:
      result
    case Con{+head, +tail}:
      Cell{+x, +y, +z, +age} = head
      +alive = U32.is_lt(age, 7)
      +kept = Bool.pick(List<&2, Cell>, alive, Con{Cell{x, y, z, U32.add(age, 1)}, result}, result)
      +with_spread = append_cells(spread(head, samples), kept)
      tick_entries(tail, samples, with_spread)

def tick(+state: State, +samples: List<&2, Sample>) -> State:
  State{+cells} = state
  State{take(max_cells(), tick_entries(take(max_cells(), cells), samples, Nil{}))}

def removed_edits(+before: List<&2, Cell>, +after: List<&2, Cell>) -> List<&2, Edit>:
  match before:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Cell{+x, +y, +z, age} = head
      +rest = removed_edits(tail, after)
      Bool.pick(List<&2, Edit>, contains(after, x, y, z), rest, Con{Edit{x, y, z, 0}, rest})

def added_edits(+after: List<&2, Cell>, +before: List<&2, Cell>) -> List<&2, Edit>:
  match after:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Cell{+x, +y, +z, age} = head
      +rest = added_edits(tail, before)
      Bool.pick(List<&2, Edit>, contains(before, x, y, z), rest, Con{Edit{x, y, z, fire_block()}, rest})

def append_edits(edits: List<&2, Edit>, +tail: List<&2, Edit>) -> List<&2, Edit>:
  match edits:
    case Nil{}:
      tail
    case Con{+head, +rest}:
      Con{head, append_edits(rest, tail)}

def changes(+before: State, +after: State) -> List<&2, Edit>:
  State{+old_cells} = before
  State{+new_cells} = after
  append_edits(removed_edits(old_cells, new_cells), added_edits(new_cells, old_cells))
