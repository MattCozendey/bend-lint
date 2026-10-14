import Base

type Plot is Data:
  Plot{x: Nat, y: Nat, z: Nat, moisture: U32}

type Water is Data:
  Water{x: Nat, z: Nat}

type State is Data:
  State{plots: List<&2, Plot>}

type FarmResult is Data:
  FarmResult{state: State, ok: Bool}

def empty() -> State:
  State{Nil{}}

def entries(state: State) -> List<&2, Plot>:
  State{plots} = state
  plots

def same_plot(plot: Plot, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Plot{+px, +py, +pz, moisture} = plot
  Bool.and(Bool.and(Nat.is_eq(px, x), Nat.is_eq(py, y)), Nat.is_eq(pz, z))

def contains(plots: List<&2, Plot>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match plots:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Bool.or(same_plot(head, x, y, z), contains(tail, x, y, z))

def add(+state: State, +x: Nat, +y: Nat, +z: Nat) -> FarmResult:
  State{+stored} = state
  Bool.pick(FarmResult, contains(stored, x, y, z), FarmResult{state, True{}},
    FarmResult{State{Con{Plot{x, y, z, 0}, stored}}, True{}})

def remove_entries(plots: List<&2, Plot>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Plot>:
  match plots:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Bool.pick(List<&2, Plot>, same_plot(head, x, y, z), tail,
        Con{head, remove_entries(tail, x, y, z)})

def remove(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+stored} = state
  State{remove_entries(stored, x, y, z)}

def moisture_at_entries(plots: List<&2, Plot>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  match plots:
    case Nil{}:
      0
    case Con{+head, +tail}:
      Plot{+px, +py, +pz, +moisture} = head
      Bool.pick(U32, Bool.and(Bool.and(Nat.is_eq(px, x), Nat.is_eq(py, y)), Nat.is_eq(pz, z)), moisture,
        moisture_at_entries(tail, x, y, z))

def moisture_at(state: State, +x: Nat, +y: Nat, +z: Nat) -> U32:
  moisture_at_entries(entries(state), x, y, z)

def axis_distance(+left: Nat, +right: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(left, right), Nat.sub(left, right), Nat.sub(right, left))

def water_near_entries(+px: Nat, +pz: Nat, +waters: List<&2, Water>) -> Bool:
  match waters:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Water{+wx, +wz} = head
      +close_x = Nat.is_lt(axis_distance(px, wx), 5n)
      +close_z = Nat.is_lt(axis_distance(pz, wz), 5n)
      Bool.or(Bool.and(close_x, close_z), water_near_entries(px, pz, tail))

def water_near(+plot: Plot, +waters: List<&2, Water>) -> Bool:
  Plot{+px, +py, +pz, moisture} = plot
  water_near_entries(px, pz, waters)

def tick_plot(+plot: Plot, +waters: List<&2, Water>) -> Plot:
  Plot{+x, +y, +z, +moisture} = plot
  +near = water_near(plot, waters)
  +next = Bool.pick(U32, near, 7, Bool.pick(U32, U32.is_gt(moisture, 0), U32.sub(moisture, 1), 0))
  Plot{x, y, z, next}

def tick_entries(plots: List<&2, Plot>, +waters: List<&2, Water>) -> List<&2, Plot>:
  match plots:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Con{tick_plot(head, waters), tick_entries(tail, waters)}

def tick(+state: State, +waters: List<&2, Water>) -> State:
  State{+stored} = state
  State{tick_entries(stored, waters)}
