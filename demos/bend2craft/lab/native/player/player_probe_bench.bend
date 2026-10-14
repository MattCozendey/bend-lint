import Base
import ../../../world/player.bend as Player
import ../../../world/world_state.bend as WorldState
import ../../../native/player.bend as Probe

def repetitions() -> Nat:
  32n

def spawn_x() -> Nat:
  25n

def spawn_z() -> Nat:
  16n

def spawn_height() -> Nat:
  9n

# The baseline the plan recorded: one bulk chunk and its one-chunk region
# rebuilt on every tick, then 32 ticks of idle movement.
def every_tick.go(+remaining: Nat, state: Player.State) -> Player.State:
  match remaining:
    case 0n:
      state
    case 1n+p:
      every_tick.go(p, Probe.step(state, 0, 0.016,
        Probe.from_world_state(1337n, 1n, 1n, WorldState.empty()),
        spawn_x(), spawn_z(), spawn_height()))

def every_tick(state: Player.State) -> Player.State:
  every_tick.go(repetitions(), state)

# 32 ticks against a region that was materialized before the ticks started.
def ticks(+remaining: Nat, state: Player.State, +region: Probe.Region) -> Player.State:
  match remaining:
    case 0n:
      state
    case 1n+p:
      ticks(p, Probe.step(state, 0, 0.016, region,
        spawn_x(), spawn_z(), spawn_height()), region)

def region_of(value: Maybe<&1, Probe.Region>) -> IO(Probe.Region):
  match value:
    case Some{region}:
      IO.pure(Probe.Region, region)
    case None{}:
      IO.die(Probe.Region, 1, "player-probe-bench: the benchmark region was refused")

def one_chunk_region() -> IO(Probe.Region):
  region_of(Probe.checked_from_world_state(1337n, 1n, 1n, 1n, 1n, WorldState.empty()))

# The multi-chunk contract: two chunks per axis, so the player can cross a
# chunk seam instead of walking into the edge of one chunk.
def four_chunk_region() -> IO(Probe.Region):
  region_of(Probe.checked_from_world_state(1337n, 1n, 1n, 2n, 2n, WorldState.empty()))

def y_changed(pair: Player.State & Player.State) -> Bool:
  (after, before) = pair
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded,
    +health, +hunger, +air, +fall, +poison} = after
  Player.State{+before_x, +before_y, +before_z, +before_yaw, +before_pitch,
    +before_velocity_y, +before_grounded, +before_health, +before_hunger,
    +before_air, +before_fall, +before_poison} = before
  F32.is_ne(y, before_y)

def state_summary(state: Player.State) -> String:
  Player.State{+x, +y, +z, +yaw, +pitch, +velocity_y, +grounded,
    +health, +hunger, +air, +fall, +poison} = state
  "x=" ++ F32.show(x) ++ ",y=" ++ F32.show(y) ++ ",vy=" ++ F32.show(velocity_y)
    ++ ",hunger=" ++ F32.show(hunger)

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "player-probe-bench: " ++ message)

def report(+name: String, +reps: Nat, +elapsed: Nat,
  +result: Player.State, before: Player.State
) -> IO(Unit):
  do IO<Unit>:
    Unit <- require(y_changed((result, before)),
      "the timed ticks must produce different final Y")
    IO.print("phase=" ++ name ++ " repetitions=" ++ Nat.show(reps)
      ++ " elapsed_ms=" ++ Nat.show(elapsed) ++ " state=" ++ state_summary(result))

# One untimed pass over every phase, so the medians below are steady state
# rather than first-touch allocation in a fresh process.
def warmup(+state: Player.State) -> IO(Unit):
  do IO<Unit>:
    +single : Probe.Region <- one_chunk_region()
    +grid : Probe.Region <- four_chunk_region()
    +rebuilt : Player.State = every_tick(state)
    +single_ticks : Player.State = ticks(repetitions(), state, single)
    +grid_ticks : Player.State = ticks(repetitions(), state, grid)
    IO.print("player-probe-bench: warmup rebuilt=" ++ state_summary(rebuilt)
      ++ " single=" ++ state_summary(single_ticks)
      ++ " grid=" ++ state_summary(grid_ticks))

# The recorded baseline: one bulk chunk and its one-chunk region on every tick.
def phase_one_chunk_every_tick(+state: Player.State) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +result : Player.State = every_tick(state)
    finished : Nat <- IO.now()
    report("one_chunk_every_tick", repetitions(), Nat.sub(finished, started), result, state)

# One bulk chunk and its region materialized once, then 32 ticks: the collision
# cost of a 16 x 20 x 16 region on its own.
def phase_one_chunk_cached(+state: Player.State) -> IO(Unit):
  do IO<Unit>:
    +region : Probe.Region <- one_chunk_region()
    started : Nat <- IO.now()
    +result : Player.State = ticks(repetitions(), state, region)
    finished : Nat <- IO.now()
    report("one_chunk_cached", repetitions(), Nat.sub(finished, started), result, state)

# The full frame of the multi-chunk contract: materializing a 2 x 2 chunk
# region from four bulk exports, then 32 ticks against it.
def phase_four_chunk_frame(+state: Player.State) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +region : Probe.Region <- four_chunk_region()
    +result : Player.State = ticks(repetitions(), state, region)
    finished : Nat <- IO.now()
    report("four_chunk_frame", repetitions(), Nat.sub(finished, started), result, state)

# The streaming cost on its own: materializing the same 2 x 2 region, with no
# tick inside the timed window.
def phase_four_chunk_materialize(+state: Player.State) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    +region : Probe.Region <- four_chunk_region()
    finished : Nat <- IO.now()
    +result : Player.State = ticks(1n, state, region)
    report("four_chunk_materialize", 1n, Nat.sub(finished, started), result, state)

def main() -> IO(Unit):
  do IO<Unit>:
    +state : Player.State = Probe.create_player(spawn_x(), spawn_z(), spawn_height())
    Unit <- warmup(state)
    Unit <- phase_one_chunk_every_tick(state)
    Unit <- phase_one_chunk_cached(state)
    Unit <- phase_four_chunk_frame(state)
    Unit <- phase_four_chunk_materialize(state)
    IO.print("player-probe-bench: done")
