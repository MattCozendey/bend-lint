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

def add.finalize(
  queue: List<&2, Cell>, visited: List<&2, Cell>, +x: Nat, +z: Nat, +light: U32, valid: Bool
) -> AddResult:
  match valid:
    case False{}:
      AddResult{queue, visited}
    case True{}:
      +cell = make_cell(x, z, light)
      AddResult{Con{cell, queue}, Con{cell, visited}}

def add(
  +queue: List<&2, Cell>, +visited: List<&2, Cell>, +walls: List<&2, Wall>,
  +x: Nat, +z: Nat, +light: U32
) -> AddResult:
  +inside = Bool.and(Nat.is_lt(x, 8n), Nat.is_lt(z, 8n))
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
