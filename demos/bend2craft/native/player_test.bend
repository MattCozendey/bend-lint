import Base
import ../world/player.bend as Player
import ../world/world.bend as World
import ../world/world_state.bend as WorldState
import ./player.bend as Probe

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "player-probe: " ++ message)

def check(condition: Bool, message: String) -> IO(Unit):
  require(condition, message)

def drive(
  +remaining: Nat, state: Player.State, +keys: U32, +region: Probe.Region,
  +spawn_x: Nat, +spawn_z: Nat, +spawn_height: Nat
) -> Player.State:
  match remaining:
    case 0n:
      state
    case 1n+p:
      drive(p, Probe.step(state, keys, 0.016, region,
        spawn_x, spawn_z, spawn_height), keys, region, spawn_x, spawn_z, spawn_height)

def state_moved_forward(pair: Player.State & Player.State) -> Bool:
  (after, before) = pair
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded,
    +health, +hunger, +air, +fall, +poison} = after
  Player.State{+before_x, +before_y, +before_z, +before_yaw, +before_pitch,
    +before_velocity_y, +before_grounded, +before_health, +before_hunger,
    +before_air, +before_fall, +before_poison} = before
  F32.is_lt(z, before_z)

def player_clears_wall(state: Player.State, +wall_z: Nat) -> Bool:
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded,
    +health, +hunger, +air, +fall, +poison} = state
  +wall_end = F32.add(U32.to_f32(U32.from_nat(Probe.domain_cell(wall_z))), 1.0)
  +player_front = F32.sub(z, 0.29)
  Bool.and(F32.is_gt(player_front, wall_end),
    Bool.and(F32.is_gt(z, F32.add(wall_end, 0.25)),
      F32.is_lt(z, F32.add(wall_end, 0.5))))

def state_z_same(pair: Player.State & Player.State) -> Bool:
  (after, before) = pair
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded,
    +health, +hunger, +air, +fall, +poison} = after
  Player.State{+before_x, +before_y, +before_z, +before_yaw, +before_pitch,
    +before_velocity_y, +before_grounded, +before_health, +before_hunger,
    +before_air, +before_fall, +before_poison} = before
  F32.is_eq(z, before_z)

def player_x(state: Player.State) -> F32:
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded,
    +health, +hunger, +air, +fall, +poison} = state
  x

def player_z(state: Player.State) -> F32:
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded,
    +health, +hunger, +air, +fall, +poison} = state
  z

def verify_spawn(spawn: World.SpawnCell) -> IO(Unit):
  match spawn:
    case World.SpawnCell{+x, +z, +height}:
      +start_z = Nat.add(z, 1n)
      +chunk_x = Nat.div(x, World.chunk_size())
      +chunk_z = Nat.div(z, World.chunk_size())
      +wall = WorldState.set(WorldState.empty(), x, height, z, 1)
      +edits = WorldState.set(wall, x, Nat.sub(height, 1n), start_z, 1)
      +region = Probe.from_world_state(1337n, chunk_x, chunk_z, edits)
      +state = Probe.create_player(x, start_z, height)
      +moved = Probe.step(state, 1, 0.016, region, x, z, height)
      +stopped = drive(80n, moved, 1, region, x, z, height)
      +still_stopped = Probe.step(stopped, 1, 0.016, region, x, z, height)
      do IO<Unit>:
        Unit <- require(Nat.is_gt(z, 0n), "spawn must have a northward test cell")
        Unit <- require(state_moved_forward((moved, state)),
          "W did not move the player against the bulk world-state chunk")
        Unit <- require(player_clears_wall(stopped, z),
          "player clipped through the edited solid block")
        Unit <- require(state_z_same((still_stopped, stopped)),
          "the edited solid block did not stop continued W movement")
        IO.print("player-probe: W movement and solid collision passed")

# ---------------------------------------------------------------------------
# Chunk seam fixtures
#
# The region starts at world cell 0 and spans two chunks per axis, so the player
# starts inside chunk (1, 1) at cell (19, 19) and walks west (-x, strafe key 2)
# or north (-z, forward key 1) across the seams at x = 16 and z = 16. A flattened
# corridor makes every stop a wall or a region edge instead of generated
# terrain: stone at y = 8 with the cells above it cleared to air, so the player's
# feet rest at y = 9. Walking 80 ticks at 4.5 blocks per second covers 5.76
# blocks, which is past the seam and past the wall cell but short of the far end
# of the corridor.
# ---------------------------------------------------------------------------

# The player's feet rest on top of the block at y = 8.
def floor_height() -> Nat:
  9n

def start_cell() -> Nat:
  19n

# Two cells past the seam, so the player reaches it inside the corridor.
def wall_cell() -> Nat:
  14n

# The first chunk boundary of each axis, which is where the neighbouring chunk
# the player walks into starts.
def seam_cell() -> Nat:
  World.chunk_size()

def clear_above.go(
  +remaining: Nat, edits: List<&2, WorldState.Edit>, +x: Nat, +y: Nat, +z: Nat
) -> List<&2, WorldState.Edit>:
  match remaining:
    case 0n:
      edits
    case 1n+p:
      clear_above.go(p, WorldState.set(edits, x, y, z, 0), x, Nat.add(y, 1n), z)

def flatten_column(edits: List<&2, WorldState.Edit>, +x: Nat, +z: Nat) -> List<&2, WorldState.Edit>:
  +floored = WorldState.set(edits, x, Nat.sub(floor_height(), 1n), z, 1)
  clear_above.go(Nat.sub(World.max_y(), floor_height()), floored, x, floor_height(), z)

def flatten.row(
  +x_count: Nat, edits: List<&2, WorldState.Edit>, +x: Nat, +z: Nat, +z_count: Nat
) -> List<&2, WorldState.Edit>:
  match x_count:
    case 0n:
      edits
    case 1n+p:
      flatten.row(p, flatten_column(edits, x, z), Nat.add(x, 1n), z, z_count)

def flatten.rect(
  +z_count: Nat, edits: List<&2, WorldState.Edit>, +x: Nat, +x_count: Nat, +z: Nat
) -> List<&2, WorldState.Edit>:
  match z_count:
    case 0n:
      edits
    case 1n+p:
      flatten.rect(p, flatten.row(x_count, edits, x, z, z_count),
        x, x_count, Nat.add(z, 1n))

# Two corridors along the walk axes, both crossing a chunk seam, from x = 11 to
# x = 20 and from z = 11 to z = 20.
def seam_corridor(edits: List<&2, WorldState.Edit>) -> List<&2, WorldState.Edit>:
  flatten.rect(10n, flatten.rect(10n, edits, 11n, 10n, 18n), 18n, 3n, 11n)

# A solid block in the neighbouring chunk, past the seam the player walks over.
def seam_wall(edits: List<&2, WorldState.Edit>) -> List<&2, WorldState.Edit>:
  WorldState.set(edits, wall_cell(), floor_height(), start_cell(), 1)

# A world cell as the player addresses it, which is what Player.State carries.
def encoded(+world_cell: Nat) -> F32:
  U32.to_f32(U32.from_nat(Probe.domain_cell(world_cell)))

# The player's box reaches 0.3 in front of its feet, so a walk has crossed a
# seam once that leading edge is past it.
def has_crossed(+position: F32, +seam: Nat) -> Bool:
  F32.is_lt(F32.sub(position, 0.29), encoded(seam))

def stopped_before_wall(state: Player.State, +wall_x: Nat) -> Bool:
  +x = player_x(state)
  +wall_face = F32.add(encoded(wall_x), 1.0)
  Bool.and(F32.is_gt(x, wall_face), F32.is_le(x, F32.add(wall_face, 0.4)))

def verify_seam(+region: Probe.Region) -> IO(Unit):
  +start = Probe.create_player(start_cell(), start_cell(), floor_height())
  +west = drive(80n, start, 2, region, start_cell(), start_cell(), floor_height())
  +north = drive(80n, start, 1, region, start_cell(), start_cell(), floor_height())
  do IO<Unit>:
    Unit <- require(has_crossed(player_x(west), seam_cell()),
      "the west walk stopped at x=" ++ F32.show(player_x(west))
        ++ " at the x chunk seam instead of crossing it")
    Unit <- require(has_crossed(player_z(north), seam_cell()),
      "the north walk stopped at z=" ++ F32.show(player_z(north))
        ++ " at the z chunk seam instead of crossing it")
    IO.print("player-probe: chunk seam crossing passed")

def verify_neighbour_wall(+region: Probe.Region) -> IO(Unit):
  +start = Probe.create_player(start_cell(), start_cell(), floor_height())
  +west = drive(80n, start, 2, region, start_cell(), start_cell(), floor_height())
  do IO<Unit>:
    Unit <- require(has_crossed(player_x(west), seam_cell()),
      "the west walk never reached the edited block in the neighbouring chunk")
    Unit <- require(stopped_before_wall(west, wall_cell()),
      "the player stopped at x=" ++ F32.show(player_x(west))
        ++ " instead of against the edited solid block in the neighbouring chunk")
    IO.print("player-probe: neighbouring chunk collision passed")

# ---------------------------------------------------------------------------
# Storage guard
#
# `domain_cell` folds a stored cell onto the player's movement window, so two
# different stored cells can land on the same player cell. The boundary has to
# refuse those cells instead of addressing a world cell nothing else names.
# ---------------------------------------------------------------------------

# A chunk coordinate whose stored cell (5900000 * 16 = 94400000) is at or above
# negative_origin(), so the decode cannot name it: it lands on the same player
# cell as stored cell 0.
def ambiguous_chunk() -> Nat:
  5900000n

# A chunk coordinate whose stored cell (2949120 * 16 = 47185920) is the first
# one the decode reads as a negative coordinate, and saturates onto world cell
# -32768 instead.
def aliasing_chunk() -> Nat:
  2949120n

# A chunk coordinate the encoding names, whose 32-cell region would still run
# past the movement window (2047 * 16 = 32752, and 32752 + 32 > 32768).
def beyond_window_chunk() -> Nat:
  2047n

def verify_storage_guard(+region: Probe.Region) -> IO(Unit):
  +ambiguous = ambiguous_chunk()
  +aliasing = aliasing_chunk()
  +beyond = beyond_window_chunk()
  do IO<Unit>:
    Unit <- require(Nat.is_eq(
        Probe.domain_cell(Nat.mul(ambiguous, World.chunk_size())),
        Probe.domain_cell(0n)),
      "the fixture no longer aliases two stored cells onto one player cell")
    Unit <- require(Nat.is_eq(Probe.domain_cell(Nat.mul(aliasing, World.chunk_size())), 0n),
      "the fixture no longer decodes a positive stored cell as a negative one")
    Unit <- require(Probe.region_is_refused(
        Probe.checked_from_world_state(1337n, ambiguous, 0n, 2n, 2n, WorldState.empty())),
      "a chunk coordinate that storage cannot name was accepted")
    Unit <- require(Probe.region_is_refused(
        Probe.checked_from_world_state(1337n, aliasing, 0n, 2n, 2n, WorldState.empty())),
      "a chunk coordinate the decode reads as a negative cell was accepted")
    Unit <- require(Probe.region_is_refused(
        Probe.checked_from_world_state(1337n, beyond, 0n, 2n, 2n, WorldState.empty())),
      "a region that runs past the movement window was accepted")
    Unit <- require(Probe.player_is_refused(
        Probe.checked_create_player(Nat.mul(ambiguous, World.chunk_size()), 0n, floor_height())),
      "a player on an unnameable stored cell was accepted")
    Unit <- require(Probe.player_is_refused(
        Probe.checked_create_player(40000n, 0n, floor_height())),
      "a player past the movement window was accepted")
    Unit <- require(Probe.player_is_refused(
        Probe.checked_step(Player.state_full(F32.neg(1.0), 9.05, 19.5, 0.0, F32.neg(0.18), 0.0,
          True{}, 20.0, 20.0, 10.0, 0.0, 0.0), 0, 0.016, region,
        start_cell(), start_cell(), floor_height())),
      "a player position outside the movement window was accepted")
    Unit <- require(Probe.player_is_refused(
        Probe.checked_step(Player.state_full(19.5, F32.neg(3.0), 19.5, 0.0, F32.neg(0.18), 0.0,
          True{}, 20.0, 20.0, 10.0, 0.0, 0.0), 0, 0.016, region,
        start_cell(), start_cell(), floor_height())),
      "a player position below the world floor was accepted")
    Unit <- require(Bool.not(Probe.region_is_refused(
        Probe.checked_from_world_state(1337n, 0n, 0n, 2n, 2n, WorldState.empty()))),
      "a sound chunk grid was refused")
    Unit <- require(Bool.not(Probe.player_is_refused(
        Probe.checked_create_player(start_cell(), start_cell(), floor_height()))),
      "a sound player cell was refused")
    IO.print("player-probe: storage guard refusal passed")

def region_of(value: Maybe<&1, Probe.Region>) -> IO(Probe.Region):
  match value:
    case Some{region}:
      IO.pure(Probe.Region, region)
    case None{}:
      IO.die(Probe.Region, 1, "player-probe: the seam region was refused")

# The grid a client builds: two chunks per axis, so the player crosses a seam
# on x and on z without walking into the edge of the region.
def seam_region(edits: List<&2, WorldState.Edit>) -> IO(Probe.Region):
  region_of(Probe.checked_from_world_state(1337n, 0n, 0n, 2n, 2n, edits))

def is_cell(value: Maybe<&1, Nat>, expected: Nat) -> Bool:
  match value:
    case Some{cell}:
      Nat.is_eq(cell, expected)
    case None{}:
      False{}

def is_refused(value: Maybe<&1, Nat>) -> Bool:
  Maybe.is_none(&1, Nat, value)

# `stored_cell` is the inverse of `domain_cell`: the player's encoded window folded back to
# the cells `WorldState` and the renderer speak, and a cell the encoding cannot name is
# refused, which is the same bound the region guard uses.
def verify_stored_cell() -> IO(Unit):
  do IO<Unit>:
    Unit <- require(is_cell(Probe.stored_cell(32768n), 0n),
      "the encoded world origin did not decode to stored cell 0")
    Unit <- require(is_cell(Probe.stored_cell(32784n), 16n),
      "an encoded cell did not decode to its stored cell")
    Unit <- require(is_cell(Probe.stored_cell(32767n), Nat.sub(World.negative_origin(), 1n)),
      "an encoded cell below the window did not decode to a negative stored cell")
    Unit <- require(is_cell(Probe.stored_cell(0n), Nat.sub(World.negative_origin(), 32768n)),
      "the low end of the encoded window did not decode to the far negative cell")
    Unit <- require(is_cell(Probe.stored_cell(Probe.domain_cell(25n)), 25n),
      "domain_cell and stored_cell are not inverse on a positive cell")
    Unit <- require(is_cell(Probe.stored_cell(Probe.domain_cell(Nat.sub(World.negative_origin(), 7n))),
        Nat.sub(World.negative_origin(), 7n)),
      "domain_cell and stored_cell are not inverse on a negative cell")
    Unit <- require(is_refused(Probe.stored_cell(Nat.add(32768n, Probe.positive_cell_limit()))),
      "a cell past the storage limit was accepted")
    check(is_refused(Probe.stored_cell(100000000n)),
      "a cell far outside the movement window was accepted")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- verify_stored_cell()
    Unit <- require(Nat.is_eq(Probe.domain_cell(0n), 32768n),
      "positive world origin was not mapped to player coordinates")
    Unit <- require(Nat.is_eq(Probe.domain_cell(Nat.sub(World.negative_origin(), 1n)), 32767n),
      "negative world cell was not mapped to player coordinates")
    Unit <- verify_spawn(World.spawn_cell(1337n))
    +open_region : Probe.Region <- seam_region(seam_corridor(WorldState.empty()))
    +wall_region : Probe.Region <- seam_region(seam_wall(seam_corridor(WorldState.empty())))
    Unit <- verify_seam(open_region)
    Unit <- verify_neighbour_wall(wall_region)
    Unit <- verify_storage_guard(wall_region)
    IO.print("player-probe: all assertions passed")

#|player-probe: W movement and solid collision passed
#|player-probe: chunk seam crossing passed
#|player-probe: neighbouring chunk collision passed
#|player-probe: storage guard refusal passed
#|player-probe: all assertions passed
