import Base
import ../world/player.bend as Player
import ../world/world.bend as World
import ../world/world_state.bend as WorldState

type Region is Data:
  Region{
    blocks: List<&2, List<&2, U32>>,
    origin_x: Nat,
    origin_y: Nat,
    origin_z: Nat,
    width: Nat,
    height: Nat,
    depth: Nat
  }

def share_blocks(blocks: List<&1, U32>) -> List<&2, U32>:
  match blocks:
    case Nil{}:
      []
    case +block <> rest:
      block <> share_blocks(rest)

# The encoded cell of stored cell 0, the middle of the movement window.
def window_middle() -> Nat:
  32768n

def domain_cell(+stored_cell: Nat) -> Nat:
  # Folds a stored world cell onto the player's movement window, so world cell
  # 0 and world cell negative_origin() both land on 32768. Every stored cell at
  # or above negative_origin()/2 is read as a negative coordinate, which is the
  # right answer for an encoded negative cell and the wrong one for a chunk
  # coordinate that storage can no longer name. `player_cell_is_sound` and
  # `chunk_grid_is_sound` are the guards for that, and the `checked_` entry
  # points below are the only ones that apply them.
  +negative = Nat.is_ge(stored_cell, Nat.div(World.negative_origin(), 2n))
  Bool.pick(Nat, negative,
    Nat.sub(window_middle(), Nat.sub(World.negative_origin(), stored_cell)),
    Nat.add(window_middle(), stored_cell))

# ---------------------------------------------------------------------------
# Storage guard
#
# A Region is one box of encoded cells, and an encoded cell is
# `stored cell + 32768`, so the encodable world is [-32768, 32768] and the
# encoded space is [0, 65536]. Refusing a cell the encoding cannot name is the
# difference between a wall at the region edge and a player standing in
# terrain 94 million cells away.
# ---------------------------------------------------------------------------

def movement_window() -> Nat:
  65536n

# The first stored cell `domain_cell` reads as a negative coordinate. A chunk
# coordinate is never negative, so a stored cell at or above this limit is a
# positive world cell the decode answers with a negative one.
def positive_cell_limit() -> Nat:
  Nat.div(World.negative_origin(), 2n)

# The inverse of `domain_cell`. The player and the raycast speak the encoded window while
# `WorldState` edits and the renderer speak stored cells, so an edit has to come back across
# that fold or it lands in the wrong cell. A cell the encoding cannot name is refused, which
# is the same bound the region guard uses.
def stored_cell.within(inside: Bool, +cell: Nat) -> Maybe<&1, Nat>:
  match inside:
    case True{}:
      Some{cell}
    case False{}:
      None{}

def stored_cell(+domain: Nat) -> Maybe<&1, Nat>:
  Bool.pick(Maybe<&1, Nat>, Nat.is_ge(domain, window_middle()),
    stored_cell.within(Nat.is_lt(Nat.sub(domain, window_middle()), positive_cell_limit()),
      Nat.sub(domain, window_middle())),
    stored_cell.within(Nat.is_lt(Nat.sub(window_middle(), domain), positive_cell_limit()),
      Nat.sub(World.negative_origin(), Nat.sub(window_middle(), domain))))

# Storage spells a negative cell as negative_origin() + cell, so a stored cell
# at or above negative_origin() is a second spelling of a cell the positive
# reading already named, and the decode saturates onto world cell -32768.
def player_cell_is_sound(+stored_cell: Nat) -> Bool:
  Bool.and(Nat.is_lt(stored_cell, World.negative_origin()),
    Nat.is_le(domain_cell(stored_cell), movement_window()))

# A region has to fit the window whole, not only at its first cell, and its
# first cell is a chunk coordinate, which is never negative.
def chunk_grid_is_sound(+chunk: Nat, +chunks: Nat) -> Bool:
  +size = World.chunk_size()
  +stored = Nat.mul(chunk, size)
  Bool.and(Nat.is_lt(stored, positive_cell_limit()),
    Nat.is_le(Nat.add(domain_cell(stored), Nat.mul(chunks, size)), movement_window()))

# A grid of chunks is bounded so a mistyped size cannot ask for an unbounded
# allocation: 16 chunks is 81920 cells, the largest grid the probe composes.
def grid_is_sound(+columns: Nat, +rows: Nat) -> Bool:
  Bool.and(Nat.is_gt(columns, 0n),
    Bool.and(Nat.is_gt(rows, 0n), Nat.is_le(Nat.mul(columns, rows), 16n)))

# The region a client builds: a bounded grid whose first cell the encoding
# names and whose whole span fits the movement window.
def region_is_sound(+chunk_x: Nat, +chunk_z: Nat, +columns: Nat, +rows: Nat) -> Bool:
  Bool.and(grid_is_sound(columns, rows),
    Bool.and(chunk_grid_is_sound(chunk_x, columns), chunk_grid_is_sound(chunk_z, rows)))

# `Player.collides` floors the position into cells, so a player outside the
# encoded window or below the world floor would read a cell nothing else names.
def player_position_is_sound(state: Player.State) -> Bool:
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded,
    +health, +hunger, +air, +fall, +poison} = state
  +window = U32.to_f32(U32.from_nat(movement_window()))
  +ceiling = U32.to_f32(U32.from_nat(Nat.add(World.max_y(), 2n)))
  Bool.and(
    Bool.and(Bool.and(F32.is_ge(x, 0.0), F32.is_le(x, window)),
      Bool.and(F32.is_ge(z, 0.0), F32.is_le(z, window))),
    Bool.and(F32.is_ge(y, 0.0), F32.is_le(y, ceiling))
  )

def region_is_refused(value: Maybe<&1, Region>) -> Bool:
  Maybe.is_none(&1, Region, value)

def player_is_refused(value: Maybe<&1, Player.State>) -> Bool:
  Maybe.is_none(&1, Player.State, value)

# ---------------------------------------------------------------------------
# Region materialization
#
# The region keeps one flat list in the region's cell order, so a cell moves from
# local_x + size * (local_z + size * y) inside its bulk chunk export to
# (base_x + local_x) + width * ((base_z + local_z) + depth * y) inside the
# region. Composing the grid is one bulk `WorldState.chunk` call per chunk and
# one cell copy per cell; the cell rule is never asked for a single cell. That flat
# list is cut into y-planes on the way out, which is the shape `Player.region_block`
# indexes, and the cut copies no cell: a plane is a slice of the list.
# ---------------------------------------------------------------------------

# Every cell of a `columns` x `rows` chunk grid.
def region_cells(+columns: Nat, +rows: Nat) -> Nat:
  +size = World.chunk_size()
  Nat.mul(Nat.mul(columns, size), Nat.mul(rows, Nat.mul(size, World.max_y())))

# Where the n-th cell of a bulk chunk export belongs in the region.
def chunk_target_index(
  +width: U32, +depth: U32, +base_x: U32, +base_z: U32, +n: U32
) -> U32:
  +size = U32.from_nat(World.chunk_size())
  +local_x = U32.mod(n, size)
  +local_z = U32.mod(U32.div(n, size), size)
  +y = U32.div(n, U32.mul(size, size))
  U32.add(U32.add(base_x, local_x),
    U32.mul(width, U32.add(U32.add(base_z, local_z), U32.mul(depth, y))))

# Array.new(U32, d, 0) holds 2^d cells, so d is one more than the floor log2 of
# `cells - 1`: the depth whose 2^d cells cover the region.
def region_depth(+cells: Nat) -> Nat:
  Nat.add(U32.log2(U32.sub(U32.from_nat(cells), 1)), 1n)

# A chunk export is read once, in its own cell order, so the copy is a walk
# rather than a random read of the borrowed array. The off-diagonal cases only
# exist so the walk is total.
def copy_chunk.go(
  +remaining: Nat, source: List<&2, U32>, region: Array<U32>,
  +width: U32, +depth: U32, +base_x: U32, +base_z: U32, +n: U32
) -> Array<U32>:
  match remaining, source:
    case 0n, Nil{}:
      region
    case 0n, Con{_, _}:
      region
    case 1n+p, Nil{}:
      region
    case 1n+p, Con{+block, tail}:
      copy_chunk.go(p, tail,
        Array.set(U32, region, chunk_target_index(width, depth, base_x, base_z, n), block),
        width, depth, base_x, base_z, U32.add(n, 1))

def copy_chunk(
  +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +base_x: U32, +base_z: U32,
  +width: U32, +depth: U32, edits: List<&2, WorldState.Edit>, region: Array<U32>
) -> Array<U32>:
  copy_chunk.go(region_cells(1n, 1n),
    share_blocks(Array.to_list(~U32, WorldState.chunk(seed, chunk_x, chunk_z, edits))),
    region, width, depth, base_x, base_z, 0)

# The chunk of the movement window that holds world chunk 0. The window is 32768 cells
# either side of the origin, so it is 2048 chunks in.
def window_origin_chunk() -> Nat:
  Nat.div(window_middle(), World.chunk_size())

# A chunk of the movement window as storage spells it. The window counts chunks from its
# own first one, so a window chunk is always a plain number and a run of them is
# consecutive across the world's origin. Storage does not: a chunk before the origin is
# spelled from `negative_origin`, as its cells are, so the chunk just west of chunk 0 is
# nowhere near 0. A grid is laid out in window chunks and each one is spelled on its way
# to `WorldState.chunk`.
def stored_chunk(+window: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(window, window_origin_chunk()),
    Nat.sub(window, window_origin_chunk()),
    Nat.sub(Nat.add(Nat.div(World.negative_origin(), World.chunk_size()), window),
      window_origin_chunk()))

# `chunk_x` and `chunk_z` are window chunks.
def copy_grid.go(
  +remaining: Nat, +index: Nat, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +columns: Nat,
  +edits: List<&2, WorldState.Edit>, region: Array<U32>, +width: U32, +depth: U32
) -> Array<U32>:
  match remaining:
    case 0n:
      region
    case 1n+p:
      +local_x = Nat.mod(index, columns)
      +local_z = Nat.div(index, columns)
      copied = copy_chunk(seed, stored_chunk(Nat.add(chunk_x, local_x)),
        stored_chunk(Nat.add(chunk_z, local_z)),
        U32.mul(U32.from_nat(local_x), U32.from_nat(World.chunk_size())),
        U32.mul(U32.from_nat(local_z), U32.from_nat(World.chunk_size())),
        width, depth, edits, region)
      copy_grid.go(p, Nat.add(index, 1n), seed, chunk_x, chunk_z, columns, edits,
        copied, width, depth)

# One flat cell list split into y-planes, which is the shape `Player.region_block`
# reads. The region's cell order is x-major within a z-row and z-rows stacked by y, so
# the plane at height y is exactly the `width * depth` cells that share that y, and a
# plane boundary is every `width * depth` cells in the flat list.
#
# The slices are taken front to back and consed onto the front of the accumulator,
# which leaves them in reverse; the reverse is the one pass that puts plane 0 at the
# head, where `plane_at` counts from. The player probe's own extraction walks forward
# and reverses for the same reason.
def plane_blocks(remaining: Nat, +source: List<&2, U32>, +per_plane: Nat,
  acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match remaining:
    case 0n:
      List.reverse(&2, List<&2, U32>, acc)
    case 1n+p:
      plane_blocks(p, List.drop(&2, U32, source, per_plane), per_plane,
        List.take(&2, U32, source, per_plane) <> acc)

# The first `remaining` cells of the region's list, shared. One loop that carries what it
# has taken, rather than `List.take` under `share_blocks`: each of those recurses once per
# cell before it returns anything, and a region of three chunks by three is 46,080 cells,
# which is deeper than the JS lane's stack.
def shared_cells(remaining: Nat, blocks: List<&1, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match remaining blocks:
    case 1n+r +block <> rest:
      shared_cells(r, rest, block <> acc)
    case _ _:
      List.reverse(&2, U32, acc)

def region_planes(+cells: Nat, +height: Nat, region: Array<U32>) ->
  List<&2, List<&2, U32>>:
  plane_blocks(height, shared_cells(cells, Array.to_list(~U32, region), []),
    Nat.div(cells, height), [])

# A `columns` x `rows` grid of bulk chunks whose first chunk is window chunk
# (chunk_x, chunk_z). Requires a grid the window holds; the checked entry points below are
# the ones to call.
def window_grid(
  +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +columns: Nat, +rows: Nat,
  edits: List<&2, WorldState.Edit>
) -> Region:
  +size = World.chunk_size()
  +width = Nat.mul(columns, size)
  +depth = Nat.mul(rows, size)
  +cells = region_cells(columns, rows)
  filled = copy_grid.go(Nat.mul(columns, rows), 0n, seed, chunk_x, chunk_z, columns,
    edits, Array.new(U32, region_depth(cells), 0), U32.from_nat(width), U32.from_nat(depth))
  Region{region_planes(cells, World.max_y(), filled), Nat.mul(chunk_x, size), 0n,
    Nat.mul(chunk_z, size), width, World.max_y(), depth}

# The same grid named by its first chunk as storage spells it, at or after the origin.
def region_grid(
  +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +columns: Nat, +rows: Nat,
  edits: List<&2, WorldState.Edit>
) -> Region:
  window_grid(seed, Nat.add(window_origin_chunk(), chunk_x),
    Nat.add(window_origin_chunk(), chunk_z), columns, rows, edits)

# One bulk export already sits in the region's cell order, so a one-chunk region
# is the export itself: no cell is copied. It is split into planes on the way in,
# because that is the shape `Player.region_block` reads.
def from_bulk(chunk: Array<U32>, +chunk_x: Nat, +chunk_z: Nat) -> Region:
  +size = World.chunk_size()
  Region{region_planes(Nat.mul(Nat.mul(size, size), World.max_y()), World.max_y(), chunk),
    domain_cell(Nat.mul(chunk_x, size)), 0n, domain_cell(Nat.mul(chunk_z, size)),
    size, World.max_y(), size}

def from_world_state(
  +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, edits: List<&2, WorldState.Edit>
) -> Region:
  from_bulk(WorldState.chunk(seed, chunk_x, chunk_z, edits), chunk_x, chunk_z)

# A collision region spanning several bulk chunks, so the player crosses x and
# z chunk boundaries instead of walking into the edge of one chunk. The whole
# grid is materialized from bulk chunk exports; a grid the storage encoding
# cannot name, or one that runs past the movement window, is refused.
def checked_from_world_state.at(
  +sound: Bool, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +columns: Nat, +rows: Nat,
  edits: List<&2, WorldState.Edit>
) -> Maybe<&1, Region>:
  match sound:
    case True{}:
      Some{region_grid(seed, chunk_x, chunk_z, columns, rows, edits)}
    case False{}:
      None{}

def checked_from_world_state(
  +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +columns: Nat, +rows: Nat,
  edits: List<&2, WorldState.Edit>
) -> Maybe<&1, Region>:
  checked_from_world_state.at(region_is_sound(chunk_x, chunk_z, columns, rows),
    seed, chunk_x, chunk_z, columns, rows, edits)

# A grid anywhere in the movement window, on either side of the origin, named by its first
# window chunk. This is the region a client that follows the player builds: a grid that
# would run past the window's last chunk is refused.
def window_is_sound(+chunk: Nat, +chunks: Nat) -> Bool:
  Nat.is_le(Nat.mul(Nat.add(chunk, chunks), World.chunk_size()), movement_window())

def checked_window_region.at(
  +sound: Bool, +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +columns: Nat, +rows: Nat,
  edits: List<&2, WorldState.Edit>
) -> Maybe<&1, Region>:
  match sound:
    case True{}:
      Some{window_grid(seed, chunk_x, chunk_z, columns, rows, edits)}
    case False{}:
      None{}

def checked_window_region(
  +seed: Nat, +chunk_x: Nat, +chunk_z: Nat, +columns: Nat, +rows: Nat,
  edits: List<&2, WorldState.Edit>
) -> Maybe<&1, Region>:
  checked_window_region.at(Bool.and(grid_is_sound(columns, rows),
      Bool.and(window_is_sound(chunk_x, columns), window_is_sound(chunk_z, rows))),
    seed, chunk_x, chunk_z, columns, rows, edits)

def create_player(+world_x: Nat, +world_z: Nat, +spawn_height: Nat) -> Player.State:
  Player.create(domain_cell(world_x), domain_cell(world_z), spawn_height)

def step(
  +state: Player.State, +keys: U32, +dt: F32, +region: Region,
  +world_spawn_x: Nat, +world_spawn_z: Nat, +spawn_height: Nat
) -> Player.State:
  Region{+blocks, +origin_x, +origin_y, +origin_z, +width, +height, +depth} = region
  Player.step(state, keys, dt, blocks, origin_x, origin_y, origin_z,
    width, height, depth,
    domain_cell(world_spawn_x), domain_cell(world_spawn_z), spawn_height)

# A player placed on cells the encoding names and the movement window holds.
def checked_create_player.at(
  +sound: Bool, candidate: Player.State, +world_x: Nat, +world_z: Nat, +spawn_height: Nat
) -> Maybe<&1, Player.State>:
  match sound:
    case True{}:
      Some{candidate}
    case False{}:
      None{}

def checked_create_player(
  +world_x: Nat, +world_z: Nat, +spawn_height: Nat
) -> Maybe<&1, Player.State>:
  +candidate = create_player(world_x, world_z, spawn_height)
  +sound = Bool.and(player_cell_is_sound(world_x), player_cell_is_sound(world_z))
  checked_create_player.at(Bool.and(sound, player_position_is_sound(candidate)),
    candidate, world_x, world_z, spawn_height)

# One tick for a player that is inside the movement window and above the world
# floor; anything else is refused instead of colliding against a cell the
# region never named.
def checked_step.at(
  +sound: Bool, state: Player.State, keys: U32, dt: F32, region: Region,
  +world_spawn_x: Nat, +world_spawn_z: Nat, +spawn_height: Nat
) -> Maybe<&1, Player.State>:
  match sound:
    case True{}:
      Some{step(state, keys, dt, region, world_spawn_x, world_spawn_z, spawn_height)}
    case False{}:
      None{}

def checked_step(
  +state: Player.State, +keys: U32, +dt: F32, +region: Region,
  +world_spawn_x: Nat, +world_spawn_z: Nat, +spawn_height: Nat
) -> Maybe<&1, Player.State>:
  +sound = Bool.and(player_position_is_sound(state),
    Bool.and(player_cell_is_sound(world_spawn_x), player_cell_is_sound(world_spawn_z)))
  checked_step.at(sound, state, keys, dt, region, world_spawn_x, world_spawn_z, spawn_height)
