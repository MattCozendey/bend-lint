import Base
import ./world.bend as World

type Chunk is Data:
  Chunk{x: Nat, z: Nat}

type Cell is Data:
  Cell{x: Nat, y: Nat, z: Nat}

def distance_component(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(a, b), Nat.sub(a, b), Nat.sub(b, a))

def coordinate(+center: Nat, +offset: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(offset, 0n), Nat.sub(center, 1n),
    Bool.pick(Nat, Nat.is_eq(offset, 1n), center, Nat.add(center, 1n)))

def contains_chunk(chunks: List<&2, Chunk>, +x: Nat, +z: Nat) -> Bool:
  match chunks:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Chunk{+cx, +cz} = head
      +same = Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cz, z))
      Bool.pick(Bool, same, True{}, contains_chunk(tail, x, z))

def row(
  +remaining: Nat, +center_x: Nat, +center_z: Nat, +offset_z: Nat,
  +chunk_size: Nat, +chunks: List<&2, Chunk>
) -> List<&2, Chunk>:
  match remaining:
    case 0n:
      chunks
    case 1n+p:
      +offset_x = Nat.sub(3n, remaining)
      +chunk_x = coordinate(center_x, offset_x)
      +chunk_z = coordinate(center_z, offset_z)
      +valid = Bool.not(contains_chunk(chunks, chunk_x, chunk_z))
      +next = Bool.pick(List<&2, Chunk>, valid, Con{Chunk{chunk_x, chunk_z}, chunks}, chunks)
      row(p, center_x, center_z, offset_z, chunk_size, next)

def rows(
  +remaining: Nat, +center_x: Nat, +center_z: Nat, +chunk_size: Nat,
  +chunks: List<&2, Chunk>
) -> List<&2, Chunk>:
  match remaining:
    case 0n:
      chunks
    case 1n+p:
      +offset_z = Nat.sub(3n, remaining)
      +row_result = row(3n, center_x, center_z, offset_z, chunk_size, chunks)
      rows(p, center_x, center_z, chunk_size, row_result)

def chunks(+x: Nat, +z: Nat, +chunk_size: Nat) -> List<&2, Chunk>:
  +center_x = Nat.div(x, chunk_size)
  +center_z = Nat.div(z, chunk_size)
  rows(3n, center_x, center_z, chunk_size, Nil{})

def cells.fill(
  +remaining: Nat, +index: Nat, +x: Nat, +y: Nat, +z: Nat, +radius: Nat,
  +side: Nat, +cells: List<&2, Cell>
) -> List<&2, Cell>:
  match remaining:
    case 0n:
      cells
    case 1n+p:
      +local_x = Nat.mod(index, side)
      +column = Nat.mul(side, side)
      +local_y = Nat.div(index, column)
      +inside = Nat.mod(index, column)
      +local_z = Nat.div(inside, side)
      +global_x = Nat.add(Nat.sub(x, radius), local_x)
      +global_y = Nat.add(Nat.sub(y, radius), local_y)
      +global_z = Nat.add(Nat.sub(z, radius), local_z)
      +distance = Nat.add(
        Nat.add(distance_component(global_x, x), distance_component(global_y, y)),
        distance_component(global_z, z)
      )
      +valid = Bool.and(Nat.is_le(distance, radius), Nat.is_lt(global_y, World.max_y()))
      +next = Bool.pick(List<&2, Cell>, valid, Con{Cell{global_x, global_y, global_z}, cells}, cells)
      cells.fill(p, Nat.add(index, 1n), x, y, z, radius, side, next)

def cells_radius(+x: Nat, +y: Nat, +z: Nat, +radius: Nat) -> List<&2, Cell>:
  +side = Nat.add(Nat.mul(radius, 2n), 1n)
  cells.fill(Nat.mul(Nat.mul(side, side), side), 0n, x, y, z, radius, side, Nil{})

def cells(+x: Nat, +y: Nat, +z: Nat) -> List<&2, Cell>:
  cells_radius(x, y, z, 14n)

def cells_plane.fill(
  +remaining: Nat, +index: Nat, +x: Nat, +y: Nat, +z: Nat, +radius: Nat,
  +side: Nat, +cells: List<&2, Cell>
) -> List<&2, Cell>:
  match remaining:
    case 0n:
      cells
    case 1n+p:
      +local_x = Nat.mod(index, side)
      +local_z = Nat.div(index, side)
      +global_x = Nat.add(Nat.sub(x, radius), local_x)
      +global_z = Nat.add(Nat.sub(z, radius), local_z)
      +distance = Nat.add(distance_component(global_x, x), distance_component(global_z, z))
      +valid = Bool.and(Nat.is_le(distance, radius), Nat.is_lt(y, World.max_y()))
      +next = Bool.pick(List<&2, Cell>, valid, Con{Cell{global_x, y, global_z}, cells}, cells)
      cells_plane.fill(p, Nat.add(index, 1n), x, y, z, radius, side, next)

def cells_plane.radius(+x: Nat, +y: Nat, +z: Nat, +radius: Nat) -> List<&2, Cell>:
  +side = Nat.add(Nat.mul(radius, 2n), 1n)
  cells_plane.fill(Nat.mul(side, side), 0n, x, y, z, radius, side, Nil{})

def cells_plane(+x: Nat, +y: Nat, +z: Nat) -> List<&2, Cell>:
  cells_plane.radius(x, y, z, 14n)

def cells_column.fill(
  +remaining: Nat, +x: Nat, +y: Nat, +z: Nat, cells: List<&2, Cell>
) -> List<&2, Cell>:
  match remaining:
    case 0n:
      cells
    case 1n+p:
      cells_column.fill(p, x, Nat.add(y, 1n), z, Con{Cell{x, y, z}, cells})

def cells_column(+x: Nat, +y: Nat, +z: Nat) -> List<&2, Cell>:
  cells_column.fill(World.max_y(), x, 0n, z, Nil{})

# Air and water are both clear and dark to the light rules (light.bend treats
# them alike), so swapping one for the other changes no light but the swapped
# cell's own ambient: its stencil is the cell alone.
def clear_and_dark(+block: U32) -> Bool:
  Bool.or(U32.is_eq(block, 0), U32.is_eq(block, 7))

def light_neutral(+previous: U32, +next: U32) -> Bool:
  Bool.and(clear_and_dark(previous), clear_and_dark(next))

def cells_self(+x: Nat, +y: Nat, +z: Nat) -> List<&2, Cell>:
  Con{Cell{x, y, z}, Nil{}}
