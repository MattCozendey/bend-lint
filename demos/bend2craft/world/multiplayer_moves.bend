import Base
import ./player.bend as Player

# Server-validated player movement for multiplayer.
#
# Browsers simulate their own player (player.bend) and relay the pose. The
# server cannot re-run that physics without every client's input, so it checks
# each relayed pose against the last one it accepted: how far the player went,
# how far it rose, and whether it walked into a solid block. A pose that fails
# is not relayed, and the server sends the player back to its last good pose.
#
# Distance is paid from two token buckets, one horizontal and one for rising.
# They refill at a sustained rate and hold a short burst, so a lag spike that
# delivers several poses at once still passes, while an idle player does not
# bank a teleport. Falling is free: gravity is capped by the client physics and
# the solid check still stops a player from sinking through the floor.

type Budget is Data:
  Budget{horizontal: F32, rise: F32}

type Move is Data:
  Accepted{budget: Budget}
  Rejected{budget: Budget}

# Sprinting is 6.75 blocks/s; water currents and sprint-jumps add a little.
def horizontal_rate() -> F32:
  10.0

def horizontal_burst() -> F32:
  12.0

# A jump rises 1.23 blocks; pillaring and swimming rise slower than this.
def rise_rate() -> F32:
  4.0

def rise_burst() -> F32:
  3.0

# How close to the world spawn a respawn lands (the spawn cell's centre).
def spawn_radius() -> F32:
  1.0

# The sample heights inside the player's 1.8-block body: the legs and the head.
def legs_offset() -> F32:
  0.5

def head_offset() -> F32:
  1.5

def fresh() -> Budget:
  Budget{horizontal_burst(), rise_burst()}

def budget_horizontal(budget: Budget) -> F32:
  Budget{+horizontal, rise} = budget
  horizontal

def budget_rise(budget: Budget) -> F32:
  Budget{horizontal, +rise} = budget
  rise

# Refills both buckets for `elapsed` seconds of server time.
def refill(budget: Budget, +elapsed: F32) -> Budget:
  Budget{+horizontal, +rise} = budget
  +seconds = F32.max(0.0, elapsed)
  Budget{
    F32.min(horizontal_burst(), F32.add(horizontal, F32.mul(horizontal_rate(), seconds))),
    F32.min(rise_burst(), F32.add(rise, F32.mul(rise_rate(), seconds)))
  }

# Whether a body with these two sampled cells is inside a solid block.
def inside(+legs: U32, +head: U32) -> Bool:
  Bool.or(Player.solid(legs), Player.solid(head))

def at_spawn(+x: F32, +z: F32, +spawn_x: F32, +spawn_z: F32) -> Bool:
  Bool.and(
    F32.is_le(F32.abs(F32.sub(x, spawn_x)), spawn_radius()),
    F32.is_le(F32.abs(F32.sub(z, spawn_z)), spawn_radius())
  )

def horizontal_distance(+from_x: F32, +from_z: F32, +to_x: F32, +to_z: F32) -> F32:
  +dx = F32.sub(to_x, from_x)
  +dz = F32.sub(to_z, from_z)
  F32.sqrt(F32.add(F32.mul(dx, dx), F32.mul(dz, dz)))

def paid(budget: Budget, +horizontal: F32, +rise: F32) -> Budget:
  Budget{+left, +up} = budget
  Budget{F32.sub(left, horizontal), F32.sub(up, rise)}

def spend.pick(ok: Bool, +budget: Budget, +horizontal: F32, +rise: F32) -> Move:
  match ok:
    case True{}:
      Accepted{paid(budget, horizontal, rise)}
    case False{}:
      Rejected{budget}

def spend(+budget: Budget, +horizontal: F32, +rise: F32, +entering: Bool) -> Move:
  +affordable = Bool.and(F32.is_le(horizontal, budget_horizontal(budget)), F32.is_le(rise, budget_rise(budget)))
  spend.pick(Bool.and(affordable, Bool.not(entering)), budget, horizontal, rise)

def respawn(entering: Bool, budget: Budget, +elapsed: F32) -> Move:
  match entering:
    case True{}:
      Rejected{refill(budget, elapsed)}
    case False{}:
      Accepted{fresh()}

def step.pick(
  spawned: Bool, entering: Bool, budget: Budget, +elapsed: F32,
  +horizontal: F32, +rise: F32
) -> Move:
  match spawned:
    case True{}:
      respawn(entering, budget, elapsed)
    case False{}:
      spend(refill(budget, elapsed), horizontal, rise, entering)

# One relayed pose, from the last accepted pose (`from_*`) to the new one
# (`to_*`), `elapsed` seconds after the previous check. `from_legs`/`from_head`
# and `to_legs`/`to_head` are the blocks at the two sample heights of each
# pose's column. Entering solid ground is refused, but a player a block was
# placed on may walk out of it. A move onto the world spawn is a respawn and
# starts a fresh budget.
def step(
  budget: Budget, +elapsed: F32,
  +from_x: F32, +from_y: F32, +from_z: F32,
  +to_x: F32, +to_y: F32, +to_z: F32,
  +from_legs: U32, +from_head: U32, +to_legs: U32, +to_head: U32,
  +spawn_x: F32, +spawn_z: F32
) -> Move:
  step.pick(
    at_spawn(to_x, to_z, spawn_x, spawn_z),
    Bool.and(inside(to_legs, to_head), Bool.not(inside(from_legs, from_head))),
    budget, elapsed,
    horizontal_distance(from_x, from_z, to_x, to_z),
    F32.max(0.0, F32.sub(to_y, from_y))
  )

def accepted(move: Move) -> Bool:
  match move:
    case Accepted{budget}:
      True{}
    case Rejected{budget}:
      False{}

def move_budget(move: Move) -> Budget:
  match move:
    case Accepted{+budget}:
      budget
    case Rejected{+budget}:
      budget
