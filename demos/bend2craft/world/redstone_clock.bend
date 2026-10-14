import Base
import ./redstone.bend as Redstone
import ./redstone_grid.bend as Grid

# ---------------------------------------------------------------------------
# Redstone time
#
# A repeater and a comparator are the only parts of a circuit that are not
# combinational: they latch their input, wait, and then change what they drive.
# That wait is the whole point - it is what stops a loop of dust and torches from
# settling, and what makes a clock oscillate at a rate the player chose.
#
# Both are advanced here, exactly once per `tick`, and then hand the core the
# cells they drove through `Redstone.tick`'s `outputs`. Keeping the counters out
# of the core's fixed point is what makes an oscillator advance one repetition
# per game tick rather than racing to the fuel bound.
# ---------------------------------------------------------------------------

# Directions, and only the four a repeater can face: 0 +x, 1 -x, 2 +z, 3 -z.
def dir_east() -> U32:
  0

def dir_west() -> U32:
  1

def dir_south() -> U32:
  2

def dir_north() -> U32:
  3

# Facing the other way along the same axis: 0 <-> 1 and 2 <-> 3, which is the low
# bit of the direction.
def back_dir(dir: U32) -> U32:
  (dir .^. 1 : U32)

def front_x(+dir: U32, +x: Nat) -> Nat:
  Bool.pick(Nat, U32.is_eq(dir, dir_east()), Nat.add(x, 1n),
    Bool.pick(Nat, U32.is_eq(dir, dir_west()), Nat.sub(x, 1n), x))

def front_z(+dir: U32, +z: Nat) -> Nat:
  Bool.pick(Nat, U32.is_eq(dir, dir_south()), Nat.add(z, 1n),
    Bool.pick(Nat, U32.is_eq(dir, dir_north()), Nat.sub(z, 1n), z))

def back_x(+dir: U32, +x: Nat) -> Nat:
  front_x(back_dir(dir), x)

def back_z(+dir: U32, +z: Nat) -> Nat:
  front_z(back_dir(dir), z)

# The two cells beside a repeater. A repeater facing along x is flanked by the
# z axis, and one facing along z by the x axis, so `dir > 1` picks which.
def side_x(+dir: U32, +x: Nat, +which: U32) -> Nat:
  Bool.pick(Nat, U32.is_gt(dir, 1),
    Bool.pick(Nat, U32.is_eq(which, 0), Nat.add(x, 1n), Nat.sub(x, 1n)), x)

def side_z(+dir: U32, +z: Nat, +which: U32) -> Nat:
  Bool.pick(Nat, U32.is_gt(dir, 1), z,
    Bool.pick(Nat, U32.is_eq(which, 0), Nat.add(z, 1n), Nat.sub(z, 1n)))

# ---------------------------------------------------------------------------
# Reading the circuit
# ---------------------------------------------------------------------------

# The signal standing at a cell: the strongest thing reaching it, or the power
# of the dust sitting in it. A repeater latches this on its back and a
# comparator reads it twice, once on the back and once on each side.
def signal_at(emits: List<&2, Redstone.Emission>, wires: List<&2, Redstone.Wire>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  +reached = Redstone.emits_power_at(emits, x, y, z)
  +own = Redstone.wire_at(wires, x, y, z)
  Redstone.max_power32(reached, own)

# Redstone works in window-local, non-negative cells, the same window
# `world/lightflood.bend` floods. `Nat.sub` saturates at zero, so a step off a
# coordinate plane lands back on the cell it started from - and a repeater whose
# "back" or "side" resolved to itself would read its own output and lock itself
# off. A step that did not move the cell is a neighbour that does not exist, and
# reads as no signal.
def off_itself(+from_x: Nat, +from_z: Nat, +to_x: Nat, +to_z: Nat) -> Bool:
  Bool.or(Bool.not(Nat.is_eq(from_x, to_x)), Bool.not(Nat.is_eq(from_z, to_z)))

def back_signal(
  emits: List<&2, Redstone.Emission>, wires: List<&2, Redstone.Wire>,
  +dir: U32, +x: Nat, +y: Nat, +z: Nat
) -> U32:
  +bx = back_x(dir, x)
  +bz = back_z(dir, z)
  Bool.pick(U32, off_itself(x, z, bx, bz), signal_at(emits, wires, bx, y, bz), 0)

def side_signal(
  emits: List<&2, Redstone.Emission>, wires: List<&2, Redstone.Wire>,
  +dir: U32, +x: Nat, +y: Nat, +z: Nat, +which: U32
) -> U32:
  +sx = side_x(dir, x, which)
  +sz = side_z(dir, z, which)
  Bool.pick(U32, off_itself(x, z, sx, sz), signal_at(emits, wires, sx, y, sz), 0)

# ---------------------------------------------------------------------------
# Repeater
# ---------------------------------------------------------------------------

# The four settings hold a signal for two, four, six and eight ticks, which is
# the latency from a change to the output: exactly vanilla's four repeaters.
def repeater_delay(+setting: U32) -> U32:
  U32.add(2, (setting * 2 : U32))

def max_setting() -> U32:
  3

def repeater_setting(+setting: U32) -> U32:
  Bool.pick(U32, U32.is_gt(setting, max_setting()), max_setting(), setting)

# `input` is the signal latched on the back, `wait` the ticks still to run and
# `out` what the repeater currently drives. Being powered from the side is not
# stored: it is read fresh every tick, so a lock cannot go stale.
type Repeater is Data:
  Repeater{x: Nat, y: Nat, z: Nat, dir: U32, setting: U32, input: U32, wait: U32, out: U32}

def repeater(x: Nat, y: Nat, z: Nat, dir: U32, setting: U32) -> Repeater:
  Repeater{x, y, z, dir, repeater_setting(setting), 0, 0, 0}

type RStep is Data:
  RStep{input: U32, wait: U32, out: U32}

def rstep.input(step: RStep) -> U32:
  RStep{input, wait, out} = step
  input

def rstep.wait(step: RStep) -> U32:
  RStep{input, wait, out} = step
  wait

def rstep.out(step: RStep) -> U32:
  RStep{input, wait, out} = step
  out

# The output moves on the tick the counter lands on zero, and only then. That is
# what makes a settled circuit stable: a repeater whose wait has run out holds
# what it drove, and a comparator that has never seen a signal stays off instead
# of comparing zero against zero and reporting full power.
def repeater.land(+input: U32, +wait: U32, +out: U32) -> RStep:
  +next = Redstone.sat_sub32(wait, 1)
  Bool.pick(RStep, U32.is_eq(next, 0), RStep{input, 0, input}, RStep{input, next, out})

# A changed input restarts the wait without touching the output, which is what
# makes the delay real.
def repeater.settle(
  +want: U32, +delay: U32, +input: U32, +wait: U32, +out: U32, +moved: Bool, +counting: Bool
) -> RStep:
  match moved:
    case True{}:
      RStep{want, delay, out}
    case False{}:
      match counting:
        case True{}:
          repeater.land(input, wait, out)
        case False{}:
          RStep{input, wait, out}

def repeater.timing(
  +want: U32, +moved: Bool, +delay: U32, +input: U32, +wait: U32, +out: U32, +locked: Bool
) -> RStep:
  match locked:
    case True{}:
      RStep{input, wait, 0}
    case False{}:
      repeater.settle(want, delay, input, wait, out, moved, U32.is_gt(wait, 0))

def repeater_step(repeater: Repeater, +back: U32, +side: U32) -> Repeater:
  Repeater{x, y, z, +dir, +setting, +input, +wait, +out} = repeater
  +want = Bool.pick(U32, U32.is_gt(back, 0), Redstone.max_power(), 0)
  +step = repeater.timing(want, U32.is_ne(want, input), repeater_delay(setting), input, wait, out,
    U32.is_gt(side, 0))
  Repeater{x, y, z, dir, setting, rstep.input(step), rstep.wait(step), rstep.out(step)}

def advance_repeaters(
  repeaters: List<&2, Repeater>, +emits: List<&2, Redstone.Emission>, +wires: List<&2, Redstone.Wire>
) -> List<&2, Repeater>:
  match repeaters:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Repeater{+x, +y, +z, +dir, setting, input, wait, out} = head
      +back = back_signal(emits, wires, dir, x, y, z)
      +left = side_signal(emits, wires, dir, x, y, z, 0)
      +right = side_signal(emits, wires, dir, x, y, z, 1)
      +side = Redstone.max_power32(left, right)
      +rest = advance_repeaters(tail, emits, wires)
      Con{repeater_step(Repeater{x, y, z, dir, setting, input, wait, out}, back, side), rest}

# ---------------------------------------------------------------------------
# Comparator
# ---------------------------------------------------------------------------

def comparator_subtract() -> U32:
  0

def comparator_compare() -> U32:
  1

# A comparator answers in two ticks, and in either mode, so one wait covers both.
def comparator_delay() -> U32:
  2

# Mode 0 hands back the back signal minus the stronger side; mode 1 hands back
# full power when the back is at least as strong as both sides.
def comparator_target(+mode: U32, +back: U32, +side: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mode, comparator_subtract()), Redstone.sat_sub32(back, side),
    Bool.pick(U32, U32.is_ge(back, side), Redstone.max_power(), 0))

type Comparator is Data:
  Comparator{x: Nat, y: Nat, z: Nat, dir: U32, mode: U32, back: U32, side: U32, wait: U32, out: U32}

def comparator(x: Nat, y: Nat, z: Nat, dir: U32, mode: U32) -> Comparator:
  Comparator{x, y, z, dir, mode, 0, 0, 0, 0}

type CStep is Data:
  CStep{back: U32, side: U32, wait: U32, out: U32}

def cstep.back(step: CStep) -> U32:
  CStep{back, side, wait, out} = step
  back

def cstep.side(step: CStep) -> U32:
  CStep{back, side, wait, out} = step
  side

def cstep.wait(step: CStep) -> U32:
  CStep{back, side, wait, out} = step
  wait

def cstep.out(step: CStep) -> U32:
  CStep{back, side, wait, out} = step
  out

# The back and both sides are latched together, so a comparator holds its answer
# while the wait runs instead of chasing a moving signal, and answers only on the
# tick the counter lands - the same rule as the repeater.
def comparator.land(+mode: U32, +back: U32, +side: U32, +wait: U32, +out: U32) -> CStep:
  +next = Redstone.sat_sub32(wait, 1)
  Bool.pick(CStep, U32.is_eq(next, 0), CStep{back, side, 0, comparator_target(mode, back, side)},
    CStep{back, side, next, out})

def comparator.timing(
  +back: U32, +side: U32, +mode: U32, +delay: U32, +wait: U32, +out: U32, +moved: Bool, +counting: Bool
) -> CStep:
  match moved:
    case True{}:
      CStep{back, side, delay, out}
    case False{}:
      match counting:
        case True{}:
          comparator.land(mode, back, side, wait, out)
        case False{}:
          CStep{back, side, wait, out}

def comparator_step(comparator: Comparator, +back: U32, +side: U32) -> Comparator:
  Comparator{x, y, z, +dir, +mode, +latched_back, +latched_side, +wait, +out} = comparator
  +step = comparator.timing(back, side, mode, comparator_delay(), wait, out,
    Bool.or(U32.is_ne(back, latched_back), U32.is_ne(side, latched_side)), U32.is_gt(wait, 0))
  Comparator{x, y, z, dir, mode, cstep.back(step), cstep.side(step), cstep.wait(step), cstep.out(step)}

def advance_comparators(
  comparators: List<&2, Comparator>, +emits: List<&2, Redstone.Emission>, +wires: List<&2, Redstone.Wire>
) -> List<&2, Comparator>:
  match comparators:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Comparator{+x, +y, +z, +dir, +mode, +back, +side, wait, out} = head
      +seen_back = back_signal(emits, wires, dir, x, y, z)
      +left = side_signal(emits, wires, dir, x, y, z, 0)
      +right = side_signal(emits, wires, dir, x, y, z, 1)
      +seen_side = Redstone.max_power32(left, right)
      +rest = advance_comparators(tail, emits, wires)
      Con{comparator_step(Comparator{x, y, z, dir, mode, back, side, wait, out}, seen_back, seen_side), rest}

# ---------------------------------------------------------------------------
# The timed state, and what it drives
# ---------------------------------------------------------------------------

type Timers is Data:
  Timers{repeaters: List<&2, Repeater>, comparators: List<&2, Comparator>}

def empty() -> Timers:
  Timers{Nil{}, Nil{}}

def timers_repeaters(state: Timers) -> List<&2, Repeater>:
  Timers{repeaters, comparators} = state
  repeaters

def timers_comparators(state: Timers) -> List<&2, Comparator>:
  Timers{repeaters, comparators} = state
  comparators

def repeater_present(repeaters: List<&2, Repeater>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match repeaters:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Repeater{+rx, +ry, +rz, dir, setting, input, wait, out} = head
      +same = Bool.and(Bool.and(Nat.is_eq(rx, x), Nat.is_eq(ry, y)), Nat.is_eq(rz, z))
      Bool.or(same, repeater_present(tail, x, y, z))

def place_repeater(+state: Timers, +x: Nat, +y: Nat, +z: Nat, +dir: U32, +setting: U32) -> Timers:
  Timers{+repeaters, +comparators} = state
  Bool.pick(Timers, repeater_present(repeaters, x, y, z), state,
    Timers{Con{repeater(x, y, z, dir, setting), repeaters}, comparators})

def comparator_present(comparators: List<&2, Comparator>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match comparators:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Comparator{+cx, +cy, +cz, dir, mode, back, side, wait, out} = head
      +same = Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))
      Bool.or(same, comparator_present(tail, x, y, z))

def place_comparator(+state: Timers, +x: Nat, +y: Nat, +z: Nat, +dir: U32, +mode: U32) -> Timers:
  Timers{+repeaters, +comparators} = state
  Bool.pick(Timers, comparator_present(comparators, x, y, z), state,
    Timers{repeaters, Con{comparator(x, y, z, dir, mode), comparators}})

# A timed component drives the cell it faces, strongly, so the dust there reads
# its full output rather than the decay. A component on a coordinate plane faces
# no cell, so it drives nothing - the same rule as `side_signal`.
def front_emission(+x: Nat, +y: Nat, +z: Nat, +dir: U32, +out: U32) -> List<&2, Redstone.Emission>:
  +fx = front_x(dir, x)
  +fz = front_z(dir, z)
  Bool.pick(List<&2, Redstone.Emission>, off_itself(x, z, fx, fz),
    Redstone.emits_one(Redstone.emit_level(fx, y, fz, 0n, True{}, out)),
    Redstone.no_emissions())

def repeater_outputs(repeaters: List<&2, Repeater>, +acc: List<&2, Redstone.Emission>) -> List<&2, Redstone.Emission>:
  match repeaters:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Repeater{+x, +y, +z, +dir, setting, input, wait, +out} = head
      Bool.pick(List<&2, Redstone.Emission>, U32.is_gt(out, 0),
        repeater_outputs(tail, Redstone.append_emits(front_emission(x, y, z, dir, out), acc)),
        repeater_outputs(tail, acc))

def comparator_outputs(comparators: List<&2, Comparator>, +acc: List<&2, Redstone.Emission>) -> List<&2, Redstone.Emission>:
  match comparators:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Comparator{+x, +y, +z, +dir, mode, back, side, wait, +out} = head
      Bool.pick(List<&2, Redstone.Emission>, U32.is_gt(out, 0),
        comparator_outputs(tail, Redstone.append_emits(front_emission(x, y, z, dir, out), acc)),
        comparator_outputs(tail, acc))

def outputs(state: Timers) -> List<&2, Redstone.Emission>:
  Timers{+repeaters, +comparators} = state
  comparator_outputs(comparators, repeater_outputs(repeaters, Nil{}))

# ---------------------------------------------------------------------------
# Reading the result
#
# A cell with no component reads as driving nothing, so a missing repeater is a
# safe answer rather than a special case at every call site.
# ---------------------------------------------------------------------------

# The four small U32 discriminators in this module are read with nested picks
# rather than a match, the way world/inventory.bend reads item ids.
def repeater_field.pick(+which: U32, +input: U32, +wait: U32, +out: U32) -> U32:
  Bool.pick(U32, U32.is_eq(which, 0), input,
    Bool.pick(U32, U32.is_eq(which, 1), wait, out))

def repeater_field.at2(
  repeaters: List<&2, Repeater>, +x: Nat, +y: Nat, +z: Nat, +which: U32
) -> U32:
  match repeaters:
    case Nil{}:
      0
    case Con{+head, +tail}:
      Repeater{+rx, +ry, +rz, dir, setting, +input, +wait, +out} = head
      +same = Bool.and(Bool.and(Nat.is_eq(rx, x), Nat.is_eq(ry, y)), Nat.is_eq(rz, z))
      Bool.pick(U32, same, repeater_field.pick(which, input, wait, out),
        repeater_field.at2(tail, x, y, z, which))

def repeater_out(state: Timers, +x: Nat, +y: Nat, +z: Nat) -> U32:
  repeater_field.at2(timers_repeaters(state), x, y, z, 2)

def repeater_wait(state: Timers, +x: Nat, +y: Nat, +z: Nat) -> U32:
  repeater_field.at2(timers_repeaters(state), x, y, z, 1)

def repeater_input(state: Timers, +x: Nat, +y: Nat, +z: Nat) -> U32:
  repeater_field.at2(timers_repeaters(state), x, y, z, 0)

def comparator_out.at(comparators: List<&2, Comparator>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  match comparators:
    case Nil{}:
      0
    case Con{+head, +tail}:
      Comparator{+cx, +cy, +cz, dir, mode, back, side, wait, +out} = head
      +same = Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))
      Bool.pick(U32, same, out, comparator_out.at(tail, x, y, z))

def comparator_out(state: Timers, +x: Nat, +y: Nat, +z: Nat) -> U32:
  comparator_out.at(timers_comparators(state), x, y, z)

# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

# One game tick. The timed components read the circuit as it stands, run their
# counters once, and hand the core the cells they drove; the core then settles
# the dust, torches and lamps against those.
type Tick is Data:
  Tick{core: Redstone.State, timers: Timers, wires: List<&2, Redstone.Wire>}

def tick_core(result: Tick) -> Redstone.State:
  Tick{core, timers, wires} = result
  core

def tick_timers(result: Tick) -> Timers:
  Tick{core, timers, wires} = result
  timers

def tick_wires(result: Tick) -> List<&2, Redstone.Wire>:
  Tick{core, timers, +wires} = result
  wires

# The tick, with cells driven by something outside the timed components - the
# machines, in ./redstone_all.bend. `extra` is what the repeaters and comparators
# read, so a plate or a rail that went live this tick is in front of them exactly
# as it is for the dust.
#
# The core settles on the array flood from ./redstone_grid.bend, which is the same
# fixed point as `Redstone.tick` and the reason the game can run a circuit of a few
# hundred cells on a 20Hz clock. The window is the caller's array, threaded back out
# beside the result; in JavaScript it is the same object throughout the tick, so a
# browser holds one `Uint32Array` and ignores the second element.
# The settled core and the window it settled with, packed as the tick. The pair
# arrives as a parameter because a pair this def built could not be taken apart.
def tick.of(
  +next: Redstone.State, +stepped: Timers, used: Array<U32>
) -> Tick & Array<U32>:
  +wires: List<&2, Redstone.Wire> = Redstone.state_wires(next)
  (Tick{next, stepped, wires}, used)

def tick.settled(
  +core: Redstone.State, +stepped: Timers,
  carried: Redstone.State & Array<U32>
) -> Tick & Array<U32>:
  (next, used) = carried
  tick.of(next, stepped, used)

def tick_with(
  +core: Redstone.State, +timers: Timers, +extra: List<&2, Redstone.Emission>,
  window: Grid.Flood, grid: Array<U32>
) -> Tick & Array<U32>:
  +wires: List<&2, Redstone.Wire> = Redstone.state_wires(core)
  +seen: List<&2, Redstone.Emission> = Redstone.emits(core, Redstone.append_emits(extra, outputs(timers)))
  +stepped: Timers = Timers{
    advance_repeaters(timers_repeaters(timers), seen, wires),
    advance_comparators(timers_comparators(timers), seen, wires)
  }
  tick.settled(core, stepped, Grid.tick(core, Redstone.append_emits(extra, outputs(stepped)), window, grid))

def tick(
  +core: Redstone.State, +timers: Timers, window: Grid.Flood, grid: Array<U32>
) -> Tick & Array<U32>:
  tick_with(core, timers, Redstone.no_emissions(), window, grid)
