import Base
import ./redstone.bend as Redstone

# ---------------------------------------------------------------------------
# Grid-backed dust flood
#
# `Redstone.flood_power` keeps the frontier and the reached cells as lists, so
# every claim scans two of them. That is quadratic in the size of the circuit, and
# it is what the fixed point pays once per pass: a 400-cell circuit spent 30 ms in
# the flood alone, and the browser runs the circuit on a 20Hz clock.
#
# This module floods the same cells through one array indexed by position, so a
# claim is a read and a write instead of two list scans. The window is the size of
# the circuit and no larger, taken from `Redstone.bounds`, and the caller hands the
# array in already built - the browser keeps one buffer per circuit and grows it
# when the circuit outgrows it, because sizing a buffer is cache management and
# running the flood over it is this contract's job.
#
# The window follows the circuit rather than the circuit fitting the window. A fixed
# window is a silent cliff: a dust cell one column past the edge reads as unpowered
# with nothing to say so, and the only sign is a circuit that stopped working where
# it worked before.
#
# One cell is one of three values, the same encoding `lightflood` uses:
#
#   0  nothing here
#   1  dust, not yet reached
#   2  dust, reached
#
# A cell at 0 is not a cell the signal can cross, so the same read answers both
# "is there dust here" and "has it been reached" - which is exactly the pair of
# scans the list flood spends per claim. The reached cells are still collected as a
# list, because that list is the power map the rest of the contract reads, and it
# is built once per cell rather than once per claim.
#
# The result is identical to `Redstone.flood_power`, cell for cell: the frontier
# is drained a whole level at a time and only a claimed cell spreads, so the first
# visit a cell gets is its strongest. tests/redstone-grid-bend.test.mjs checks the
# two agree on a set of circuits rather than taking that on trust.
# ---------------------------------------------------------------------------

# The window is a box in world coordinates, and the array is that box flattened.
# Positions stay absolute everywhere else - the reached list the core reads is in
# world coordinates - and only the index arithmetic subtracts the origin.
type Flood is Data:
  Flood{ox: Nat, oy: Nat, oz: Nat, width: Nat, depth: Nat, height: Nat}

# The dust's box, widened by one cell on every side. That margin is what lets a
# source sitting next to the dust queue itself: a source can only push into its six
# neighbours, so one cell of margin covers every source that could reach dust, and a
# source further out could not have reached it anyway. `Nat.sub` saturates, so a
# circuit against the origin keeps its zero edge.
def flood_of(bounds: Redstone.Bounds) -> Flood:
  Redstone.Bounds{+min_x, +min_y, +min_z, +max_x, +max_y, +max_z} = bounds
  +ox = Nat.sub(min_x, 1n)
  +oy = Nat.sub(min_y, 1n)
  +oz = Nat.sub(min_z, 1n)
  Flood{
    ox,
    oy,
    oz,
    (Nat.add(max_x, 2n) - ox : Nat),
    (Nat.add(max_z, 2n) - oz : Nat),
    (Nat.add(max_y, 2n) - oy : Nat)
  }

def flood_of_state(state: Redstone.State) -> Flood:
  flood_of(Redstone.bounds(state))

def flood_cells(window: Flood) -> Nat:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  (width * depth * height : Nat)

def flood.max_x(window: Flood) -> Nat:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  (ox + width - 1n : Nat)

def flood.max_y(window: Flood) -> Nat:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  (oy + height - 1n : Nat)

def flood.max_z(window: Flood) -> Nat:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  (oz + depth - 1n : Nat)

# Where a world position lands in the flattened array. Only ever called on a
# position `flood_fits` accepted, so the subtractions cannot saturate and wrap a
# position from one edge of the array onto another.
def flood_index(window: Flood, +x: Nat, +y: Nat, +z: Nat) -> Nat:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  (x - ox + width * ((z - oz + depth * (y - oy) : Nat) : Nat) : Nat)

# The array's own index type is U32, so the world-coordinate arithmetic above comes
# back as one.
def flood.slot(window: Flood, +x: Nat, +y: Nat, +z: Nat) -> U32:
  U32.from_nat(flood_index(window, x, y, z))

# Inside the window or not. The far test is `le` against the last index, not `lt`
# against a size: the outer ring of the window is exactly where a source beside
# the dust sits, so excluding it would drop a legitimate seed and the circuit would
# quietly lose power at its edge.
def flood_fits(window: Flood, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  Bool.and(
    Bool.and(
      Bool.and(Nat.is_ge(x, ox), Nat.is_le(x, flood.max_x(window))),
      Bool.and(Nat.is_ge(y, oy), Nat.is_le(y, flood.max_y(window)))),
    Bool.and(Nat.is_ge(z, oz), Nat.is_le(z, flood.max_z(window))))

# A step that would leave the window stays put, so a dust cell on the edge does not
# wrap onto the next row of the array. `Nat.sub` saturates at the low edge for the
# same reason it saturates everywhere else in this contract.
def flood.step_x(window: Flood, +x: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(x, flood.max_x(window)), x, Nat.add(x, 1n))

def flood.step_back_x(window: Flood, +x: Nat) -> Nat:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  Bool.pick(Nat, Nat.is_le(x, ox), x, Nat.sub(x, 1n))

def flood.step_y(window: Flood, +y: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(y, flood.max_y(window)), y, Nat.add(y, 1n))

def flood.step_back_y(window: Flood, +y: Nat) -> Nat:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  Bool.pick(Nat, Nat.is_le(y, oy), y, Nat.sub(y, 1n))

def flood.step_z(window: Flood, +z: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(z, flood.max_z(window)), z, Nat.add(z, 1n))

def flood.step_back_z(window: Flood, +z: Nat) -> Nat:
  Flood{+ox, +oy, +oz, +width, +depth, +height} = window
  Bool.pick(Nat, Nat.is_le(z, oz), z, Nat.sub(z, 1n))

def open_cell() -> U32:
  0

def dust_cell() -> U32:
  1

def reached_cell() -> U32:
  2

type Front is Data:
  Front{x: Nat, y: Nat, z: Nat, level: U32}

# `hit` records whether the last claim landed. Only a claimed cell spreads, and
# that is what keeps the frontier proportional to the circuit rather than to the
# window.
type Flooding is Type:
  Flooding{
    grid: Array<U32>,
    window: Flood,
    next: List<&2, Front>,
    done: List<&2, Redstone.Wire>,
    hit: Bool
  }

# ---------------------------------------------------------------------------
# Seeding
# ---------------------------------------------------------------------------

# Mark every dust cell, so a claim can tell dust from empty with one read.
#
# There is no separate reset between passes or between ticks, and none is needed:
# `mark_dust` rewrites every live cell to 1 on every pass, so a cell that has just
# been claimed is armed again next time, and a cell that stopped holding dust reads
# as 2 or 0, neither of which is 1, so it is never claimed. That is what lets the
# buffer be the caller's own, kept for the whole life of the circuit.
def mark_dust.at(
  +window: Flood, grid: Array<U32>, +x: Nat, +y: Nat, +z: Nat, inside: Bool
) -> Array<U32>:
  match inside:
    case False{}:
      grid
    case True{}:
      grid[flood.slot(window, x, y, z)] <- dust_cell()

def mark_dust(
  wires: List<&2, Redstone.Wire>, +window: Flood, grid: Array<U32>
) -> Array<U32>:
  match wires:
    case Nil{}:
      grid
    case Con{+head, +tail}:
      Redstone.Wire{+x, +y, +z, +power} = head
      mark_dust(
        tail, window, mark_dust.at(window, grid, x, y, z, flood_fits(window, x, y, z)))

def seed.push(
  +next: List<&2, Front>, +x: Nat, +y: Nat, +z: Nat, inside: Bool
) -> List<&2, Front>:
  match inside:
    case False{}:
      next
    case True{}:
      Con{Front{x, y, z, Redstone.max_power()}, next}

# Queue every dust cell a strong source reaches, at full power. Seeding only
# queues, so the drain below is the single place a power level is set and a directly
# powered cell travels the same path as one the signal reached by decay.
def seed.at(
  grid: Array<U32>, +window: Flood, +next: List<&2, Front>, +done: List<&2, Redstone.Wire>, hit: Bool,
  +x: Nat, +y: Nat, +z: Nat, reached: Bool
) -> Flooding:
  match reached:
    case False{}:
      Flooding{grid, window, next, done, hit}
    case True{}:
      Flooding{grid, window, seed.push(next, x, y, z, flood_fits(window, x, y, z)), done, hit}

def seed(
  wires: List<&2, Redstone.Wire>, +emits: List<&2, Redstone.Emission>, flooding: Flooding
) -> Flooding:
  match wires:
    case Nil{}:
      flooding
    case Con{+head, +tail}:
      Redstone.Wire{+x, +y, +z, +power} = head
      Flooding{grid, +window, +next, +done, hit} = flooding
      +reached_by_source = Redstone.emits_strong_at(emits, x, y, z)
      queued = seed.at(grid, window, next, done, hit, x, y, z, reached_by_source)
      seed(tail, emits, queued)

# ---------------------------------------------------------------------------
# The drain
# ---------------------------------------------------------------------------

def push_flow.at(
  window: Flood, grid: Array<U32>, +next: List<&2, Front>,
  done: List<&2, Redstone.Wire>, hit: Bool,
  +x: Nat, +y: Nat, +z: Nat, +level: U32, live: Bool
) -> Flooding:
  match live:
    case False{}:
      Flooding{grid, window, next, done, hit}
    case True{}:
      Flooding{grid, window, Con{Front{x, y, z, level}, next}, done, hit}

def push_flow(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  Flooding{grid, +window, +next, done, hit} = flooding
  push_flow.at(window, grid, next, done, hit, x, y, z, level, U32.is_gt(level, 0))

# Sideways steps lose a level; the two vertical ones are a direct connection and
# keep theirs, exactly as in the list flood.
def push_four(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  Flooding{grid, +window, +next, +done, +hit} = flooding
  right = push_flow(flooding, flood.step_x(window, x), y, z, level)
  left = push_flow(right, flood.step_back_x(window, x), y, z, level)
  front_step = push_flow(left, x, y, flood.step_z(window, z), level)
  push_flow(front_step, x, y, flood.step_back_z(window, z), level)

def push_up(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  Flooding{grid, +window, +next, +done, +hit} = flooding
  above = push_flow(flooding, x, flood.step_y(window, y), z, level)
  push_flow(above, x, flood.step_back_y(window, y), z, level)

# The one read and one write that replace the list flood's two scans: a cell at 1
# is dust the signal has not reached, and claiming it writes 2 and records the
# power. The read hands the array back beside the value, the same shape
# `lightflood.bend` uses, so the array is still owned for the write.
def claim.write(
  +window: Flood, grid: Array<U32>, +next: List<&2, Front>, +done: List<&2, Redstone.Wire>,
  +x: Nat, +y: Nat, +z: Nat, +level: U32, open: Bool
) -> Flooding:
  match open:
    case False{}:
      Flooding{grid, window, next, done, False{}}
    case True{}:
      claimed = grid[flood.slot(window, x, y, z)] <- reached_cell()
      Flooding{claimed, window, next, Con{Redstone.Wire{x, y, z, level}, done}, True{}}

def claim.at(
  +window: Flood, +next: List<&2, Front>, +done: List<&2, Redstone.Wire>,
  +x: Nat, +y: Nat, +z: Nat, +level: U32, read: Array<U32> & U32
) -> Flooding:
  (grid, state) = read
  claim.write(window, grid, next, done, x, y, z, level, U32.is_eq(state, dust_cell()))

def claim(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  Flooding{grid, +window, +next, +done, hit} = flooding
  claim.at(
    window, next, done, x, y, z, level, grid[flood.slot(window, x, y, z)])

# Only a claimed cell spreads. Spreading from a cell the signal never reached is
# what turns a line of dust into an unbounded fan-out.
def spread.at(
  flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32, hit: Bool
) -> Flooding:
  match hit:
    case False{}:
      flooding
    case True{}:
      push_up(push_four(flooding, x, y, z, Redstone.sat_sub32(level, 1)), x, y, z, level)

def spread(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  Flooding{grid, window, next, done, +hit} = flooding
  spread.at(Flooding{grid, window, next, done, hit}, x, y, z, level, hit)

def visit(+front_cell: Front, flooding: Flooding) -> Flooding:
  Front{+x, +y, +z, +level} = front_cell
  spread(claim(flooding, x, y, z, level), x, y, z, level)

# Drain the level that was collected into a fresh accumulator, so the queue stays a
# queue instead of growing for the whole tick.
def level_of(front: List<&2, Front>, flooding: Flooding) -> Flooding:
  match front:
    case Nil{}:
      flooding
    case Con{+head, tail}:
      level_of(tail, visit(head, flooding))

def turn(flooding: Flooding) -> Flooding:
  Flooding{grid, window, +next, done, hit} = flooding
  level_of(next, Flooding{grid, window, Nil{}, done, hit})

# Drain the frontier a level at a time and hand the flooding back, reached cells and
# all, so a caller that wants to settle a pass can keep the same window.
def drain(+remaining: Nat, flooding: Flooding) -> Flooding:
  match remaining:
    case 0n:
      flooding
    case 1n+p:
      drain(p, turn(flooding))

# Sixteen levels cover a horizontal chain away from a redstone block; a vertical
# step keeps its level, so a column needs its own height in turns. The bound has to
# exceed the longest path in the dust graph, and the claim check means the frontier
# stops growing long before it is reached.
def flood_level() -> Nat:
  256n

def drained(flooding: Flooding) -> List<&2, Redstone.Wire> & Array<U32>:
  Flooding{grid, +window, +next, +done, +hit} = flooding
  (done, grid)

# The whole flood: mark the dust, queue the sources, drain the frontier. The result
# is the reached cells with their power, in the same shape the list flood returns,
# so `Redstone.rebuild.wires` consumes either without knowing which ran.
#
# The array is consumed here, as an `Array` must be: one owner, one use. A caller
# that needs to flood again hands the array back in - it is the caller's own array,
# updated in place, so a browser reuses one buffer for the whole circuit.
def flood_power(
  +wires: List<&2, Redstone.Wire>, emits: List<&2, Redstone.Emission>,
  +window: Flood, grid: Array<U32>
) -> List<&2, Redstone.Wire> & Array<U32>:
  drained(
    drain(
      flood_level(),
      seed(wires, emits, Flooding{mark_dust(wires, window, grid), window, Nil{}, Nil{}, False{}})))

# ---------------------------------------------------------------------------
# The fixed point, on the grid
#
# Same order, same fuel, same settle rule as `Redstone.resolve` - only the flood
# differs. The pass itself is the core's (`Redstone.resolve.once_with`), so no
# redstone rule is restated here: this module swaps a quadratic walk for a linear
# one and leaves every decision where it was.
#
# Measured on the JavaScript target with a 400-cell circuit, one tick of the
# circuit: 342 ms before the settle rule was fixed, 86 ms after it, and the flood
# itself 36 ms against 0.9 ms here.
# ---------------------------------------------------------------------------

# The window is a `Type`'s field and never leaves: it rides inside `Flooding` for
# the whole fixed point, and each pass re-marks the dust into the same array before
# re-queuing the sources. There is no window per pass and no window rebuilt per
# tick.
#
# `Pass` is that carrier, and the settle flag rides *beside* it because a `Bool`
# inside a `Type` could not be read back out to steer the next iteration. The shape
# of the loop below is then forced by three rules the language does not bend: a
# computed pair can be passed on but not taken apart, a value bound by a
# destructuring let is the only thing a later `match` may scrutinise, and two defs
# may not call each other. So `resolve_grid.at` matches the fuel - a parameter, and
# before any destructuring - and forwards the carrier untouched, and the one
# recursive def is that fuel loop. Opening the carrier is `pass.armed`'s job, and
# it hands the pair to `pass.settle` unopened in turn.
type Pass is Type:
  Pass{flooding: Flooding, state: Redstone.State, outputs: List<&2, Redstone.Emission>}

# The window comes back beside the settled state, because a caller that floods
# again has to be able to name the array it passed in. In JavaScript it is the same
# object throughout, so a browser simply ignores the second element.
def pass.flooding(pass: Pass) -> Flooding:
  Pass{flooding, +state, +outputs} = pass
  flooding

# A `Pass` is a `Type`, so it has one owner and one use, and this def is the only
# one that can open it. It hands on the reached cells, the array and the window
# together, because a pair this def built could not be taken apart - the language
# lets a computed pair be passed on, not opened, so the pieces travel as one value
# from here to `pass.settle`.
def ready.widen(
  carried: List<&2, Redstone.Wire> & Array<U32>, window: Flood
) -> List<&2, Redstone.Wire> & Array<U32> & Flood:
  (done, grid) = carried
  (done, grid, window)

def pass.ready(pass: Pass) -> List<&2, Redstone.Wire> & Array<U32> & Flood:
  Pass{flooding, +state, +outputs} = pass
  Flooding{grid, +window, +next, +done, +hit} = flooding
  ready.widen(drained(drain(flood_level(), Flooding{grid, window, next, done, hit})), window)

def grid_of(flooding: Flooding) -> Array<U32>:
  Flooding{grid, +window, +next, +done, +hit} = flooding
  grid

def pass.settled(carried: Pass & Redstone.State & List<&2, Redstone.Emission> & Bool)
-> Redstone.State & Array<U32>:
  (pass, state, outputs, stop) = carried
  (state, grid_of(drain(flood_level(), pass.flooding(pass))))

# One pass: drain the frontier, hand the reached cells to the core's own pass, and
# re-arm the window for the next one. The core owns every redstone rule here; this
# only chooses which flood the pass reads.
def pass.rearm(
  +state: Redstone.State, +outputs: List<&2, Redstone.Emission>, +window: Flood,
  +done: List<&2, Redstone.Wire>, grid: Array<U32>
) -> Pass & Redstone.State & List<&2, Redstone.Emission> & Bool:
  +settled = Redstone.resolve.once_with(state, outputs, done)
  +next: Redstone.State = Redstone.resolved.state(settled)
  +wires: List<&2, Redstone.Wire> = Redstone.state_wires(next)
  +emits: List<&2, Redstone.Emission> = Redstone.emits(next, outputs)
  rearmed = seed(wires, emits, Flooding{mark_dust(wires, window, grid), window, Nil{}, Nil{}, False{}})
  (Pass{rearmed, next, outputs}, next, outputs, Bool.not(Redstone.resolved.changed(settled)))

def pass.settle(
  +state: Redstone.State, +outputs: List<&2, Redstone.Emission>,
  ready: List<&2, Redstone.Wire> & Array<U32> & Flood
) -> Pass & Redstone.State & List<&2, Redstone.Emission> & Bool:
  (done, grid, window) = ready
  pass.rearm(state, outputs, window, done, grid)

# Read the settle flag. A circuit that has not moved is handed straight back, so
# the loop keeps its shape and its fuel while the work stops: a settled circuit
# pays a few tuple constructions, not a few floods.
def pass.armed(carried: Pass & Redstone.State & List<&2, Redstone.Emission> & Bool)
-> Pass & Redstone.State & List<&2, Redstone.Emission> & Bool:
  (pass, state, outputs, stop) = carried
  match stop:
    case True{}:
      (pass, state, outputs, True{})
    case False{}:
      pass.settle(state, outputs, pass.ready(pass))

def resolve_grid.at(
  +remaining: Nat,
  carried: Pass & Redstone.State & List<&2, Redstone.Emission> & Bool
) -> Redstone.State & Array<U32>:
  match remaining:
    case 0n:
      pass.settled(carried)
    case 1n+p:
      resolve_grid.at(p, pass.armed(carried))

# The window is derived from the circuit it has to flood, so a circuit of any size
# settles. The array is the caller's own, threaded back out beside the result.
def resolve_grid(
  +state: Redstone.State, +outputs: List<&2, Redstone.Emission>,
  +window: Flood, grid: Array<U32>
) -> Redstone.State & Array<U32>:
  +wires: List<&2, Redstone.Wire> = Redstone.state_wires(state)
  +emits: List<&2, Redstone.Emission> = Redstone.emits(state, outputs)
  resolve_grid.at(
    Redstone.resolve_fuel(),
    (Pass{seed(wires, emits, Flooding{mark_dust(wires, window, grid), window, Nil{}, Nil{}, False{}}),
          state, outputs},
     state, outputs, False{}))

# One game tick of the core circuit, settling on the array flood.
def tick(
  +state: Redstone.State, +outputs: List<&2, Redstone.Emission>,
  +window: Flood, grid: Array<U32>
) -> Redstone.State & Array<U32>:
  resolve_grid(Redstone.advance(state), outputs, window, grid)
