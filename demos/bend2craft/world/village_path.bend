import Base
import ./world.bend as World

type Point is Data:
  Point{x: Nat, z: Nat}

type Node is Data:
  Node{x: Nat, z: Nat, first_x: Nat, first_z: Nat, root: Bool}

type Search is Data:
  Search{queue: List<&2, Node>, visited: List<&2, Point>}

type PathResult is Data:
  PathResult{x: Nat, z: Nat, found: Bool}

def make_search(queue: List<&2, Node>, points: List<&2, Point>) -> Search:
  Search{queue, points}

def result_x(result: PathResult) -> Nat:
  PathResult{x, z, found} = result
  x

def result_z(result: PathResult) -> Nat:
  PathResult{x, z, found} = result
  z

def result_found(result: PathResult) -> Bool:
  PathResult{x, z, found} = result
  found

def target_x(+current: F32, +path: PathResult) -> F32:
  Bool.pick(F32, result_found(path), F32.add(U32.to_f32(U32.from_nat(result_x(path))), F32.div(1.0, 2.0)), current)

def target_z(+current: F32, +path: PathResult) -> F32:
  Bool.pick(F32, result_found(path), F32.add(U32.to_f32(U32.from_nat(result_z(path))), F32.div(1.0, 2.0)), current)

def point_equal(point: Point, +x: Nat, +z: Nat) -> Bool:
  Point{+point_x, +point_z} = point
  Bool.and(Nat.is_eq(point_x, x), Nat.is_eq(point_z, z))

def visited(+points: List<&2, Point>, +x: Nat, +z: Nat) -> Bool:
  match points:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Bool.or(point_equal(head, x, z), visited(tail, x, z))

def append_node(+queue: List<&2, Node>, +node: Node) -> List<&2, Node>:
  match queue:
    case Nil{}:
      Con{node, Nil{}}
    case Con{+head, +tail}:
      Con{head, append_node(tail, node)}

def list_at(+index: Nat, +values: List<&2, U32>) -> U32:
  match index values:
    case 0n Nil{}:
      0
    case 0n Con{+head, +tail}:
      head
    case 1n+p Nil{}:
      0
    case 1n+p Con{+head, +tail}:
      list_at(p, tail)

def grid_walkable(
  grid: List<&2, U32>, +x: Nat, +z: Nat, +min_x: Nat, +min_z: Nat, +width: Nat, +depth: Nat
) -> Bool:
  +inside = Bool.and(
    Bool.and(Nat.is_ge(x, min_x), Nat.is_lt(x, Nat.add(min_x, width))),
    Bool.and(Nat.is_ge(z, min_z), Nat.is_lt(z, Nat.add(min_z, depth)))
  )
  +local_x = Nat.sub(x, min_x)
  +local_z = Nat.sub(z, min_z)
  +row = list_at(local_z, grid)
  +bit = U32.shln(1, local_x)
  Bool.and(inside, U32.is_ne(U32.and(row, bit), 0))

def grid.row(
  +remaining: Nat, +local_x: Nat, +seed: Nat, +y: Nat,
  +x: Nat, +z: Nat, +mask: U32
) -> U32:
  match remaining:
    case 0n:
      mask
    case 1n+p:
      +feet = World.block(seed, x, y, z)
      +head = World.block(seed, x, Nat.add(y, 1n), z)
      +feet_open = Bool.or(Bool.or(U32.is_eq(feet, 0), U32.is_eq(feet, 13)), Bool.or(U32.is_eq(feet, 14), U32.is_eq(feet, 15)))
      +head_open = Bool.or(U32.is_eq(head, 0), Bool.or(U32.is_eq(head, 14), U32.is_eq(head, 15)))
      +open = Bool.and(feet_open, head_open)
      +bit = U32.shln(1, local_x)
      +next_mask = Bool.pick(U32, open, U32.or(mask, bit), mask)
      grid.row(p, Nat.add(local_x, 1n), seed, y, Nat.add(x, 1n), z, next_mask)

def grid.fill(
  +remaining_rows: Nat, +row: Nat, +seed: Nat, +y: Nat,
  +min_x: Nat, +min_z: Nat, +width: Nat, +rows: List<&2, U32>
) -> List<&2, U32>:
  match remaining_rows:
    case 0n:
      rows
    case 1n+p:
      +mask = grid.row(width, 0n, seed, y, min_x, Nat.add(min_z, row), 0)
      grid.fill(p, Nat.sub(row, 1n), seed, y, min_x, min_z, width, Con{mask, rows})

def grid(+seed: Nat, +y: Nat, +min_x: Nat, +min_z: Nat, +width: Nat, +depth: Nat) -> List<&2, U32>:
  grid.fill(depth, Nat.sub(depth, 1n), seed, y, min_x, min_z, width, Nil{})

def push(
  state: Search, grid: List<&2, U32>, +x: Nat, +z: Nat,
  +first_x: Nat, +first_z: Nat, +root: Bool,
  +min_x: Nat, +min_z: Nat, +width: Nat, +depth: Nat
) -> Search:
  Search{+queue, +points} = state
  +can = Bool.and(
    Bool.and(
      Bool.and(Nat.is_ge(x, min_x), Nat.is_lt(x, Nat.add(min_x, width))),
      Bool.and(Nat.is_ge(z, min_z), Nat.is_lt(z, Nat.add(min_z, depth)))
    ),
    Bool.and(Bool.not(visited(points, x, z)), grid_walkable(grid, x, z, min_x, min_z, width, depth))
  )
  +next_first_x = Bool.pick(Nat, root, x, first_x)
  +next_first_z = Bool.pick(Nat, root, z, first_z)
  Search{
    Bool.pick(List<&2, Node>, can, append_node(queue, Node{x, z, next_first_x, next_first_z, False{}}), queue),
    Bool.pick(List<&2, Point>, can, Con{Point{x, z}, points}, points)
  }

def search_state(
  +remaining: Nat, state: Search, +grid: List<&2, U32>,
  +target_x: Nat, +target_z: Nat,
  +min_x: Nat, +min_z: Nat, +width: Nat, +depth: Nat
) -> PathResult:
  match remaining:
    case 0n:
      PathResult{0n, 0n, False{}}
    case 1n+p:
      Search{+queue, +points} = state
      match queue:
        case Nil{}:
          PathResult{0n, 0n, False{}}
        case Con{+node, +tail}:
          Node{+x, +z, +first_x, +first_z, +root} = node
          +found = Bool.and(Nat.is_eq(x, target_x), Nat.is_eq(z, target_z))
          +base = make_search(tail, points)
          +left = push(base, grid, Nat.sub(x, 1n), z, first_x, first_z, root, min_x, min_z, width, depth)
          +right = push(left, grid, Nat.add(x, 1n), z, first_x, first_z, root, min_x, min_z, width, depth)
          +back = push(right, grid, x, Nat.sub(z, 1n), first_x, first_z, root, min_x, min_z, width, depth)
          +forward = push(back, grid, x, Nat.add(z, 1n), first_x, first_z, root, min_x, min_z, width, depth)
          Bool.pick(PathResult, found, PathResult{first_x, first_z, True{}},
            search_state(p, forward, grid, target_x, target_z, min_x, min_z, width, depth))

def adjacent_candidate(
  +start_x: Nat, +start_z: Nat, +target_x: Nat, +target_z: Nat
) -> PathResult:
  +same = Bool.and(Nat.is_eq(start_x, target_x), Nat.is_eq(start_z, target_z))
  +right = Bool.and(
    Nat.is_eq(target_x, Nat.add(start_x, 1n)),
    Nat.is_eq(target_z, start_z)
  )
  +left = Bool.and(
    Nat.is_eq(target_x, Nat.sub(start_x, 1n)),
    Nat.is_eq(target_z, start_z)
  )
  +forward = Bool.and(
    Nat.is_eq(target_x, start_x),
    Nat.is_eq(target_z, Nat.add(start_z, 1n))
  )
  +back = Bool.and(
    Nat.is_eq(target_x, start_x),
    Nat.is_eq(target_z, Nat.sub(start_z, 1n))
  )
  +candidate = Bool.or(Bool.or(same, right), Bool.or(left, Bool.or(forward, back)))
  Bool.pick(PathResult, candidate, PathResult{target_x, target_z, True{}}, PathResult{0n, 0n, False{}})

def resolve_candidate(
  grid: List<&2, U32>, candidate: PathResult,
  target_x: Nat, target_z: Nat, min_x: Nat, min_z: Nat, width: Nat, depth: Nat,
  +start_x: Nat, +start_z: Nat
) -> PathResult:
  PathResult{candidate_x, candidate_z, candidate_found} = candidate
  match candidate_found:
    case True{}:
      walkable = grid_walkable(grid, candidate_x, candidate_z, min_x, min_z, width, depth)
      Bool.pick(PathResult, walkable, PathResult{target_x, target_z, True{}}, PathResult{0n, 0n, False{}})
    case False{}:
      +initial = make_search(
        Con{Node{start_x, start_z, start_x, start_z, True{}}, Nil{}},
        Con{Point{start_x, start_z}, Nil{}}
      )
      search_state(256n, initial, grid, target_x, target_z, min_x, min_z, width, depth)

def next(
  grid: List<&2, U32>, +start_x: Nat, +start_z: Nat, +target_x: Nat, +target_z: Nat,
  +min_x: Nat, +min_z: Nat, +width: Nat, +depth: Nat
) -> PathResult:
  +candidate = adjacent_candidate(start_x, start_z, target_x, target_z)
  resolve_candidate(grid, candidate, target_x, target_z, min_x, min_z, width, depth, start_x, start_z)
