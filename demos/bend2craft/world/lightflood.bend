import Base

type Cell is Data:
  Cell{x: Nat, z: Nat, light: U32}

type Wall is Data:
  Wall{x: Nat, z: Nat}

type FloodState is Data:
  FloodState{queue: List<&2, Cell>, visited: List<&2, Cell>, walls: List<&2, Wall>}

type AddResult is Data:
  AddResult{queue: List<&2, Cell>, visited: List<&2, Cell>}

type Lookup is Data:
  Lit{light: U32}
  Dark{}

def max_light() -> U32:
  14

def make_cell(x: Nat, z: Nat, light: U32) -> Cell:
  Cell{x, z, light}

def source(+x: Nat, +z: Nat) -> Cell:
  make_cell(x, z, max_light())

def lava_source(+x: Nat, +z: Nat) -> Cell:
  make_cell(x, z, 15)

def sources(cell: Cell) -> List<&2, Cell>:
  Con{cell, Nil{}}

def empty_walls() -> List<&2, Wall>:
  Nil{}

def wall(+x: Nat, +z: Nat) -> List<&2, Wall>:
  Con{Wall{x, z}, Nil{}}

def wall_list(walls: List<&2, Wall>, +x: Nat, +z: Nat) -> List<&2, Wall>:
  Con{Wall{x, z}, walls}

def wall_at(walls: List<&2, Wall>, +x: Nat, +z: Nat) -> Bool:
  match walls:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Wall{+wx, +wz} = head
      +same = Bool.and(Nat.is_eq(wx, x), Nat.is_eq(wz, z))
      Bool.pick(Bool, same, True{}, wall_at(tail, x, z))

def visited_at(cells: List<&2, Cell>, +x: Nat, +z: Nat) -> Bool:
  match cells:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Cell{+cx, +cz, light} = head
      +same = Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cz, z))
      Bool.pick(Bool, same, True{}, visited_at(tail, x, z))

def light_at(cells: List<&2, Cell>, +x: Nat, +z: Nat) -> Lookup:
  match cells:
    case Nil{}:
      Dark{}
    case Con{+head, +tail}:
      Cell{+cx, +cz, +light} = head
      +same = Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cz, z))
      Bool.pick(Lookup, same, Lit{light}, light_at(tail, x, z))

def append_cell(queue: List<&2, Cell>, cell: Cell) -> List<&2, Cell>:
  match queue:
    case Nil{}:
      Con{cell, Nil{}}
    case Con{+head, +tail}:
      Con{head, append_cell(tail, cell)}

def add.finalize(
  queue: List<&2, Cell>, visited: List<&2, Cell>, +x: Nat, +z: Nat, +light: U32, valid: Bool
) -> AddResult:
  match valid:
    case False{}:
      AddResult{queue, visited}
    case True{}:
      +cell = make_cell(x, z, light)
      AddResult{append_cell(queue, cell), Con{cell, visited}}

def add(
  +queue: List<&2, Cell>, +visited: List<&2, Cell>, +walls: List<&2, Wall>,
  +x: Nat, +z: Nat, +light: U32
) -> AddResult:
  +inside = Bool.and(Nat.is_lt(x, 32n), Nat.is_lt(z, 32n))
  +valid = Bool.and(Bool.and(Bool.and(inside, U32.is_gt(light, 0)),
    Bool.not(wall_at(walls, x, z))), Bool.not(visited_at(visited, x, z)))
  add.finalize(queue, visited, x, z, light, valid)

def queue_of(result: AddResult) -> List<&2, Cell>:
  AddResult{queue, visited} = result
  queue

def visited_of(result: AddResult) -> List<&2, Cell>:
  AddResult{queue, visited} = result
  visited

def step(+queue: List<&2, Cell>, +visited: List<&2, Cell>, +walls: List<&2, Wall>) -> FloodState:
  match queue:
    case Nil{}:
      FloodState{Nil{}, visited, walls}
    case Con{+head, +tail}:
      Cell{+x, +z, +light} = head
      +next_light = Bool.pick(U32, U32.is_gt(light, 0), U32.sub(light, 1), 0)
      +right = add(tail, visited, walls, Nat.add(x, 1n), z, next_light)
      +left = add(queue_of(right), visited_of(right), walls, Nat.sub(x, 1n), z, next_light)
      +front = add(queue_of(left), visited_of(left), walls, x, Nat.add(z, 1n), next_light)
      +back = add(queue_of(front), visited_of(front), walls, x, Nat.sub(z, 1n), next_light)
      FloodState{queue_of(back), visited_of(back), walls}

def run.state(+remaining: Nat, state: FloodState) -> List<&2, Cell>:
  match remaining:
    case 0n:
      FloodState{queue, visited, walls} = state
      visited
    case 1n+p:
      FloodState{+queue, +visited, +walls} = state
      run.state(p, step(queue, visited, walls))

def run(+sources: List<&2, Cell>, walls: List<&2, Wall>, +remaining: Nat) -> List<&2, Cell>:
  run.state(remaining, FloodState{sources, sources, walls})

# ---------------------------------------------------------------------------
# Grid-backed flood
#
# `run` keeps the flood as lists, so every step scans the visited list and the
# wall list and appends to the queue: quadratic in the lit area (~50 ms per
# torch on the JavaScript target). `run_grid` floods the same 32 x 32 window
# with one array holding each cell's state (0 open, 1 wall, 2 reached) and
# walks the frontier level by level. Because every step lowers the light by
# one, the level order is exactly the FIFO order of `run`, so the returned
# visited list is the same list, in the same order.
# ---------------------------------------------------------------------------

type Front is Data:
  Front{x: U32, z: U32, light: U32}

type Flooding is Type:
  Flooding{grid: Array<U32>, next: List<&2, Front>, cells: List<&2, Cell>}

def grid.index(+x: U32, +z: U32) -> U32:
  (x + z * 32 : U32)

def grid.sat_sub(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_lt(a, b), 0, (a - b : U32))

def grid.claim.if(
  +x: U32, +z: U32, +light: U32, grid: Array<U32>,
  next: List<&2, Front>, cells: List<&2, Cell>, open: Bool
) -> Flooding:
  match open:
    case False{}:
      Flooding{grid, next, cells}
    case True{}:
      claimed = grid[grid.index(x, z)] <- 2
      Flooding{claimed, Con{Front{x, z, light}, next}, Con{make_cell(U32.to_nat(x), U32.to_nat(z), light), cells}}

def grid.claim(
  +x: U32, +z: U32, +light: U32, next: List<&2, Front>, cells: List<&2, Cell>,
  read: Array<U32> & U32
) -> Flooding:
  (grid, state) = read
  grid.claim.if(x, z, light, grid, next, cells, U32.is_eq(state, 0))

def grid.add.if(
  +x: U32, +z: U32, +light: U32, grid: Array<U32>,
  next: List<&2, Front>, cells: List<&2, Cell>, valid: Bool
) -> Flooding:
  match valid:
    case False{}:
      Flooding{grid, next, cells}
    case True{}:
      grid.claim(x, z, light, next, cells, Array.get(U32, grid, grid.index(x, z)))

# The same admission test as `add`: inside the window, still lit, and neither
# a wall nor already reached.
def grid.add(+x: U32, +z: U32, +light: U32, flooding: Flooding) -> Flooding:
  Flooding{grid, next, cells} = flooding
  +inside = Bool.and(U32.is_lt(x, 32), U32.is_lt(z, 32))
  grid.add.if(x, z, light, grid, next, cells, Bool.and(inside, U32.is_gt(light, 0)))

# One queue step of `run`: right, left, front, back, with `Nat.sub` saturation.
def grid.visit(+cell: Front, flooding: Flooding) -> Flooding:
  Front{+x, +z, +light} = cell
  +next_light = Bool.pick(U32, U32.is_gt(light, 0), (light - 1 : U32), 0)
  right = grid.add((x + 1 : U32), z, next_light, flooding)
  left = grid.add(grid.sat_sub(x, 1), z, next_light, right)
  front = grid.add(x, (z + 1 : U32), next_light, left)
  grid.add(x, grid.sat_sub(z, 1), next_light, front)

def grid.level(front: List<&2, Front>, flooding: Flooding) -> Flooding:
  match front:
    case Nil{}:
      flooding
    case Con{+head, tail}:
      grid.level(tail, grid.visit(head, flooding))

def grid.reverse(list: List<&2, Front>, acc: List<&2, Front>) -> List<&2, Front>:
  match list:
    case Nil{}:
      acc
    case Con{+head, tail}:
      grid.reverse(tail, Con{head, acc})

def grid.cells(flooding: Flooding) -> List<&2, Cell>:
  Flooding{grid, next, cells} = flooding
  cells

# Visit the pending frontier in discovery order, collecting the next one.
def grid.advance(flooding: Flooding) -> Flooding:
  Flooding{grid, next, cells} = flooding
  grid.level(grid.reverse(next, Nil{}), Flooding{grid, Nil{}, cells})

def grid.run(+remaining: Nat, flooding: Flooding) -> List<&2, Cell>:
  match remaining:
    case 0n:
      grid.cells(flooding)
    case 1n+p:
      grid.run(p, grid.advance(flooding))

# `walls` is the 32 x 32 window, index x + 32 z, 1 for a wall and 0 for open.
# Light drops one per step, so 16 levels cover even a lava source.
def run_grid(+source: Cell, walls: Array<U32>) -> List<&2, Cell>:
  Cell{+x, +z, +light} = source
  +x32 = U32.from_nat(x)
  +z32 = U32.from_nat(z)
  claimed = walls[grid.index(x32, z32)] <- 2
  grid.run(16n, Flooding{claimed, Con{Front{x32, z32, light}, Nil{}}, Con{source, Nil{}}})
