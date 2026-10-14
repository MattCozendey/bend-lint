# Galperin's billiards: a wall, a stationary unit mass, and an incoming mass.
# Positions are contact coordinates: subtract the small block's width from
# the large block's physical left edge, so the blocks touch when x == y.
import Base

type State is Data:
  State{x: F32, y: F32, v: F32, w: F32, mass: F32, time: F32, count: U32, wall: Bool}

def initial(mass: F32) -> State:
  State{1.0, 3.0, 0.0, (0.0 - 1.0 : F32), mass, 0.0, 0, False{}}

def finished(s: State) -> Bool:
  State{x, y, +v, w, mass, time, count, wall} = s
  (v >= 0.0 : F32) && (v <= w : F32)

def wall_time(leftward: Bool, x: F32, v: F32) -> F32:
  match leftward:
    case True{}:
      F32.max(0.0, (0.0 - x / v : F32))
    case False{}:
      1.0e30

def block_time(closing: Bool, x: F32, y: F32, v: F32, w: F32) -> F32:
  match closing:
    case True{}:
      F32.max(0.0, ((y - x) / (v - w) : F32))
    case False{}:
      1.0e30

# Momentum and kinetic energy determine these two post-impact velocities.
def impact(at_wall: Bool, s: State, +dt: F32) -> State:
  match at_wall:
    case True{}:
      State{x, y, v, +w, mass, time, count, wall} = s
      State{0.0, (y + w * dt : F32), (0.0 - v : F32), w,
        mass, (time + dt : F32), (count + 1 : U32), True{}}
    case False{}:
      State{x, y, +v, +w, +mass, time, count, wall} = s
      +contact = F32.max(0.0, (x + v * dt : F32))
      +denom = (1.0 + mass : F32)
      small = (((1.0 - mass) * v + 2.0 * mass * w) / denom : F32)
      large = ((2.0 * v + (mass - 1.0) * w) / denom : F32)
      State{contact, contact, small, large, mass,
        (time + dt : F32), (count + 1 : U32), False{}}

def next_active(done: Bool, +s: State) -> State:
  match done:
    case True{}:
      s
    case False{}:
      State{+x, +y, +v, +w, mass, time, count, wall} = s
      +tw = wall_time((v < 0.0 : F32), x, v)
      +tb = block_time((v > w : F32), x, y, v, w)
      impact((tw < tb : F32), s, F32.min(tw, tb))

def next(+s: State) -> State:
  next_active(finished(s), s)

# Fuel bounds computation even for inputs beyond the supported mass range.
def run_loop(fuel: Nat, done: Bool, +s: State) -> State:
  match fuel:
    case 0n:
      s
    case 1n+rest:
      match done:
        case True{}:
          s
        case False{}:
          +following = next(s)
          run_loop(rest, finished(following), following)

def run(fuel: Nat, +s: State) -> State:
  run_loop(fuel, finished(s), s)

def collisions(s: State) -> U32:
  State{x, y, v, w, mass, time, count, wall} = s
  count

def energy(s: State) -> F32:
  State{x, y, +v, +w, mass, time, count, wall} = s
  (0.5 * (v * v + mass * w * w) : F32)
