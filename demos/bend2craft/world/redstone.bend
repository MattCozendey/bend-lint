import Base

# ---------------------------------------------------------------------------
# Redstone core
#
# Redstone is the only part of the sandbox whose rules are cyclic, so the
# contract is split the way vanilla splits it:
#
#   `resolve`  the pure combinational part - sources, dust, torches, lamps.
#              It is iterated to a fixed point under a fuel bound.
#   `advance`  the once-per-tick part - repeater and comparator delay
#              counters, door and piston edges. It runs exactly once per
#              `tick`, so an oscillator advances one repetition per game tick
#              instead of racing inside the fixed point. It lives in
#              ./redstone_clock.bend and ./redstone_machines.bend.
#
# Every power level is a U32 in 0..15, and 0 is both "unpowered" and "not
# reached yet": a wire the flood visited always holds at least 1, so the
# `done` list doubles as the visited set and the power map, the way
# `world/lightflood.bend` reuses its `visited` list.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Block IDs
#
# The world block contract lives in world/world.bend and stops at 27. This
# slice extends it, and `block_ids` is the ordered list the browser adapter
# walks to name, colour and bind the blocks, so the two stay in step through
# one explicit list.
# ---------------------------------------------------------------------------

def wire_block() -> U32:
  28

def torch_block() -> U32:
  29

def lever_block() -> U32:
  30

def power_block() -> U32:
  31

def lamp_block() -> U32:
  32

def repeater_block() -> U32:
  33

def comparator_block() -> U32:
  34

def plate_block() -> U32:
  35

def rail_block() -> U32:
  36

def piston_block() -> U32:
  37

def head_block() -> U32:
  38

def sticky_piston_block() -> U32:
  39

# The observer watches the block in front of it. It is the one component with no
# signal input, and the only reason it needs a block id of its own is that the
# adapter has to be able to tell an observer cell from an empty one when the player
# breaks it.
def observer_block() -> U32:
  40

def block_ids() -> List<U32>:
  28 <> 29 <> 30 <> 31 <> 32 <> 33 <> 34 <> 35 <> 36 <> 37 <> 38 <> 39 <> 40 <> Nil{}

# ---------------------------------------------------------------------------
# Shared vocabulary
# ---------------------------------------------------------------------------

def max_power() -> U32:
  15

# `U32.sub` wraps, so power decay needs the saturating form world/world.bend
# already uses for coordinates.
def sat_sub32(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_lt(a, b), 0, (a - b : U32))

def max_power32(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), a, b)

# `Bool` has no `is_eq`; it orders through `Cmp`.
def same_bool(+a: Bool, +b: Bool) -> Bool:
  Cmp.is_eq(Bool.cmp(a, b))

# The world block at a position. Only the cells a redstone rule has to reason
# about are ever sampled, so the browser sends a short list, not a chunk.
type Sample is Data:
  Sample{x: Nat, y: Nat, z: Nat, block: U32}

def sample(x: Nat, y: Nat, z: Nat, block: U32) -> Sample:
  Sample{x, y, z, block}

def same_cell(cell: Sample, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Sample{+cx, +cy, +cz, block} = cell
  Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))

def sample_block(samples: List<&2, Sample>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  match samples:
    case Nil{}:
      0
    case Con{+head, +tail}:
      Sample{+sx, +sy, +sz, +block} = head
      +same = Bool.and(Bool.and(Nat.is_eq(sx, x), Nat.is_eq(sy, y)), Nat.is_eq(sz, z))
      Bool.pick(U32, same, block, sample_block(tail, x, y, z))

# A cell that hands out power this tick. Sources build one entry per neighbouring
# cell they can reach, so a power query is a scan of a list whose length is
# bounded by the circuit's source count rather than by the number of wires: that
# is what keeps a tick linear in the components, not quadratic.
#
# `strong` is the vanilla strong/weak split. A redstone block, a lever, a lit
# torch and a repeater output power dust directly, so the dust they touch is
# pinned to 15. Powered dust does not: it only reaches the blocks around it, or
# every dust cell next to a powered one would read 15 instead of 14.
#
# `level` is the strength, not just its presence, because a repeater reads the
# signal on its back as a number: dust at 14 in front of it must read 14, not
# "powered".
#
# `source` names who emitted it. A torch powers the block it stands on, which is
# also the cell it watches, so without an origin a torch would read its own
# emission, go dark, drop the emission and oscillate. `emits_power_others_at` is
# how a torch answers "is anything but me powering my support?".
type Emission is Data:
  Powered{x: Nat, y: Nat, z: Nat, source: Nat, strong: Bool, level: U32}

# Source zero belongs to anything that never checks: redstone blocks, levers, the
# outputs repeaters hand in and powered dust. Torches are numbered from one.
def emit_level(x: Nat, y: Nat, z: Nat, source: Nat, strong: Bool, level: U32) -> Emission:
  Powered{x, y, z, source, strong, level}

def emit_from(x: Nat, y: Nat, z: Nat, source: Nat, strong: Bool) -> Emission:
  emit_level(x, y, z, source, strong, max_power())

def emit(x: Nat, y: Nat, z: Nat) -> Emission:
  emit_from(x, y, z, 0n, True{})

def same_emit(cell: Emission, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Powered{+cx, +cy, +cz, source, strong, level} = cell
  Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))

# The strongest signal reaching a cell. This is what a repeater or a comparator
# reads as its input, and why the level is carried rather than a flag.
#
# The tail is folded once into `rest` and then chosen between: evaluating the
# recursive call inside both arms of a `Bool.pick` would walk the list twice per
# cell, which is exponential in the list length.
def emits_power_at(emits: List<&2, Emission>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  match emits:
    case Nil{}:
      0
    case Con{+head, +tail}:
      Powered{+cx, +cy, +cz, source, strong, +level} = head
      +same = Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))
      +rest = emits_power_at(tail, x, y, z)
      Bool.pick(U32, same, max_power32(level, rest), rest)

def emits_power_others_at(emits: List<&2, Emission>, +x: Nat, +y: Nat, +z: Nat, +source: Nat) -> U32:
  match emits:
    case Nil{}:
      0
    case Con{+head, +tail}:
      Powered{+cx, +cy, +cz, +from, strong, +level} = head
      +same = Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))
      +mine = Bool.and(same, Bool.not(Nat.is_eq(from, source)))
      +rest = emits_power_others_at(tail, x, y, z, source)
      Bool.pick(U32, mine, max_power32(level, rest), rest)

# Any power at a cell: what a torch or a lamp answers to.
def emits_at(emits: List<&2, Emission>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  U32.is_gt(emits_power_at(emits, x, y, z), 0)

# Power that reaches dust directly, which is what seeds the flood at 15.
def emits_strong_at(emits: List<&2, Emission>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match emits:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Powered{+cx, +cy, +cz, +from, +strong, level} = head
      +same = Bool.and(Bool.and(Nat.is_eq(cx, x), Nat.is_eq(cy, y)), Nat.is_eq(cz, z))
      Bool.or(Bool.and(same, strong), emits_strong_at(tail, x, y, z))

# A block-shaped source (redstone block, engaged lever) powers all six
# neighbours, strongly.
def cube_emits(+x: Nat, +y: Nat, +z: Nat) -> List<&2, Emission>:
  emit(Nat.add(x, 1n), y, z) <>
  emit(Nat.sub(x, 1n), y, z) <>
  emit(x, Nat.add(y, 1n), z) <>
  emit(x, Nat.sub(y, 1n), z) <>
  emit(x, y, Nat.add(z, 1n)) <>
  emit(x, y, Nat.sub(z, 1n)) <>
  Nil{}

# A redstone torch powers the four cells around it and the block it stands on,
# strongly.
def torch_emits(+x: Nat, +y: Nat, +z: Nat, +source: Nat) -> List<&2, Emission>:
  emit_from(x, Nat.sub(y, 1n), z, source, True{}) <>
  emit_from(Nat.add(x, 1n), y, z, source, True{}) <>
  emit_from(Nat.sub(x, 1n), y, z, source, True{}) <>
  emit_from(x, y, Nat.add(z, 1n), source, True{}) <>
  emit_from(x, y, Nat.sub(z, 1n), source, True{}) <>
  Nil{}

def append_emits(+more: List<&2, Emission>, +acc: List<&2, Emission>) -> List<&2, Emission>:
  match more:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      append_emits(tail, Con{head, acc})
# of the state because the browser renders the dust at that brightness.
type Wire is Data:
  Wire{x: Nat, y: Nat, z: Nat, power: U32}

# A redstone torch stands on the block below it and inverts that block's power.
# `prev` is the state it held when the tick started, so `advance` can tell a
# flip from a settle once per tick rather than once per resolve pass. `streak`
# counts consecutive ticks spent flipping without settling and latches `burnt`:
# a torch driven faster than it can answer dies and stays dark, which is the
# vanilla burnout that stops a too-fast oscillator.
type Torch is Data:
  Torch{x: Nat, y: Nat, z: Nat, lit: Bool, prev: Bool, streak: U32, burnt: Bool}

type Lever is Data:
  Lever{x: Nat, y: Nat, z: Nat, on: Bool}

# A redstone block: a source that never turns off.
type Spot is Data:
  Spot{x: Nat, y: Nat, z: Nat}

type Lamp is Data:
  Lamp{x: Nat, y: Nat, z: Nat, lit: Bool}

type State is Data:
  State{wires: List<&2, Wire>, torches: List<&2, Torch>, levers: List<&2, Lever>, spots: List<&2, Spot>, lamps: List<&2, Lamp>}


# Powered dust reaches the six cells around it, weakly: the block it stands on,
# the block above it, and the four around it. Weak, because a dust cell must not
# reset its neighbour to full power - that is the 15, 14, 13 decay the flood
# computes, and it is why `emits_strong_at` is what seeds it.
# `Nat.sub` saturates at zero, so on a coordinate plane the cell "below" or
# "behind" collapses onto the cell itself. A dust cell emitting into its own
# cell would read as powering whatever stands on it - a torch would see its own
# support lit and go dark - so an emission that does not leave the cell is
# dropped. The playable world starts at zero on every axis, so those are exactly
# the neighbours that do not exist.
def no_emissions() -> List<&2, Emission>:
  Nil{}

# Air, water and lava: the three blocks a piston, a rail or a plate treats as
# empty. Everything else in this world is solid.
def air_block() -> U32:
  0

def water_block() -> U32:
  7

def lava_block() -> U32:
  21

def airish(+block: U32) -> Bool:
  Bool.or(
    Bool.or(U32.is_eq(block, air_block()), U32.is_eq(block, water_block())),
    U32.is_eq(block, lava_block()))

def emits_one(cell: Emission) -> List<&2, Emission>:
  Con{cell, Nil{}}

# One dust emission, dropped when stepping the coordinate did not move it. The
# level is the cell's own power, so a repeater reading 14 in front of a 14-wire
# sees 14.
def emit_neighbour(+x: Nat, +y: Nat, +z: Nat, +from: Nat, +to: Nat, +level: U32) -> List<&2, Emission>:
  Bool.pick(List<&2, Emission>, Nat.is_eq(from, to), no_emissions(),
    Con{emit_level(x, y, z, 0n, False{}, level), no_emissions()})

def dust_emits(+x: Nat, +y: Nat, +z: Nat, +power: U32) -> List<&2, Emission>:
  append_emits(emit_neighbour(x, Nat.sub(y, 1n), z, y, Nat.sub(y, 1n), power),
    append_emits(emit_neighbour(x, y, Nat.sub(z, 1n), z, Nat.sub(z, 1n), power),
      append_emits(emits_one(emit_level(Nat.add(x, 1n), y, z, 0n, False{}, power)),
        append_emits(emits_one(emit_level(x, Nat.add(y, 1n), z, 0n, False{}, power)),
          append_emits(emit_neighbour(Nat.sub(x, 1n), y, z, x, Nat.sub(x, 1n), power),
            append_emits(emits_one(emit_level(x, y, Nat.add(z, 1n), 0n, False{}, power)), no_emissions()))))))

def wire_emits(wires: List<&2, Wire>, +acc: List<&2, Emission>) -> List<&2, Emission>:
  match wires:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Wire{+x, +y, +z, +power} = head
      wire_emits(tail, Bool.pick(List<&2, Emission>, U32.is_gt(power, 0),
        append_emits(dust_emits(x, y, z, power), acc), acc))

# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------

# A dust cell. `power` is the cached result of the last resolve, and it is part

def empty() -> State:
  State{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}

def state_wires(state: State) -> List<&2, Wire>:
  State{wires, torches, levers, spots, lamps} = state
  wires

def state_torches(state: State) -> List<&2, Torch>:
  State{wires, torches, levers, spots, lamps} = state
  torches

def state_levers(state: State) -> List<&2, Lever>:
  State{wires, torches, levers, spots, lamps} = state
  levers

def state_spots(state: State) -> List<&2, Spot>:
  State{wires, torches, levers, spots, lamps} = state
  spots

def state_lamps(state: State) -> List<&2, Lamp>:
  State{wires, torches, levers, spots, lamps} = state
  lamps

# ---------------------------------------------------------------------------
# Position lookup and placement
# ---------------------------------------------------------------------------

def wire_at(wires: List<&2, Wire>, +x: Nat, +y: Nat, +z: Nat) -> U32:
  match wires:
    case Nil{}:
      0
    case Con{+head, +tail}:
      Wire{+wx, +wy, +wz, +power} = head
      +same = Bool.and(Bool.and(Nat.is_eq(wx, x), Nat.is_eq(wy, y)), Nat.is_eq(wz, z))
      Bool.pick(U32, same, power, wire_at(tail, x, y, z))

# ---------------------------------------------------------------------------
# The dust's extent
#
# The array-backed flood in ./redstone_grid.bend needs to know how big a window to
# flood, and a fixed window silently drops a circuit that reaches past it - a dust
# cell one column beyond the edge reads as unpowered with nothing to say so. So the
# window follows the dust instead of the other way round, and the extent is a
# question about the circuit, which is why it is answered here.
#
# The box is over the dust only. A source that can reach dust is by definition
# within one cell of it, so ./redstone_grid.bend widens this box by one before
# turning it into a window; a source further out could not have reached dust in the
# first place.
# ---------------------------------------------------------------------------

type Bounds is Data:
  Bounds{min_x: Nat, min_y: Nat, min_z: Nat, max_x: Nat, max_y: Nat, max_z: Nat}

# An empty circuit, so folding nothing into it leaves a one-cell box rather than
# an undefined one. Every field is zero, which is also how a box that has not been
# seeded yet is told apart from a real one - see `bounds.blank`.
def bounds.empty() -> Bounds:
  Bounds{0n, 0n, 0n, 0n, 0n, 0n}

def bounds.blank(+bounds: Bounds) -> Bool:
  Bounds{+min_x, +min_y, +min_z, +max_x, +max_y, +max_z} = bounds
  Bool.and(
    Bool.and(
      Bool.and(Nat.is_eq(min_x, 0n), Nat.is_eq(min_y, 0n)),
      Nat.is_eq(min_z, 0n)),
    Bool.and(
      Bool.and(Nat.is_eq(max_x, 0n), Nat.is_eq(max_y, 0n)),
      Nat.is_eq(max_z, 0n)))

# The first dust cell defines the box rather than widening it. Folding from an
# all-zero box would pin the minimum at zero, and a circuit a thousand blocks out
# would then flood a window a thousand blocks wide to hold a dozen cells. A real
# one-cell box at the origin is indistinguishable from an unseeded one, and seeding
# it with the origin again is the same box, so the two cases do not need telling
# apart.
def bounds.seed(+x: Nat, +y: Nat, +z: Nat, +bounds: Bounds) -> Bounds:
  Bool.pick(Bounds, bounds.blank(bounds), Bounds{x, y, z, x, y, z}, bounds)

def bounds.at(
  +x: Nat, +y: Nat, +z: Nat, +bounds: Bounds
) -> Bounds:
  Bounds{+min_x, +min_y, +min_z, +max_x, +max_y, +max_z} = bounds
  Bounds{
    Bool.pick(Nat, Nat.is_lt(x, min_x), x, min_x),
    Bool.pick(Nat, Nat.is_lt(y, min_y), y, min_y),
    Bool.pick(Nat, Nat.is_lt(z, min_z), z, min_z),
    Bool.pick(Nat, Nat.is_gt(x, max_x), x, max_x),
    Bool.pick(Nat, Nat.is_gt(y, max_y), y, max_y),
    Bool.pick(Nat, Nat.is_gt(z, max_z), z, max_z)
  }

def bounds.go(wires: List<&2, Wire>, +bounds: Bounds) -> Bounds:
  match wires:
    case Nil{}:
      bounds
    case Con{+head, +tail}:
      Wire{+x, +y, +z, +power} = head
      bounds.go(tail, bounds.at(x, y, z, bounds.seed(x, y, z, bounds)))

def bounds(state: State) -> Bounds:
  bounds.go(state_wires(state), bounds.empty())


def wire_present(wires: List<&2, Wire>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match wires:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Wire{+wx, +wy, +wz, power} = head
      +same = Bool.and(Bool.and(Nat.is_eq(wx, x), Nat.is_eq(wy, y)), Nat.is_eq(wz, z))
      Bool.or(same, wire_present(tail, x, y, z))

def drop_wires(wires: List<&2, Wire>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Wire>:
  match wires:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Wire{+wx, +wy, +wz, power} = head
      +same = Bool.and(Bool.and(Nat.is_eq(wx, x), Nat.is_eq(wy, y)), Nat.is_eq(wz, z))
      Bool.pick(List<&2, Wire>, same, tail, Con{head, drop_wires(tail, x, y, z)})

def place_wire(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  Bool.pick(State, wire_present(wires, x, y, z), state,
    State{Con{Wire{x, y, z, 0}, wires}, torches, levers, spots, lamps})

def lever_present(levers: List<&2, Lever>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match levers:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Lever{+lx, +ly, +lz, on} = head
      +same = Bool.and(Bool.and(Nat.is_eq(lx, x), Nat.is_eq(ly, y)), Nat.is_eq(lz, z))
      Bool.or(same, lever_present(tail, x, y, z))

def place_lever(+state: State, +x: Nat, +y: Nat, +z: Nat, +on: Bool) -> State:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  Bool.pick(State, lever_present(levers, x, y, z), state,
    State{wires, torches, Con{Lever{x, y, z, on}, levers}, spots, lamps})

def flip_lever_at(levers: List<&2, Lever>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Lever>:
  match levers:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Lever{+lx, +ly, +lz, +on} = head
      +same = Bool.and(Bool.and(Nat.is_eq(lx, x), Nat.is_eq(ly, y)), Nat.is_eq(lz, z))
      Bool.pick(List<&2, Lever>, same, Con{Lever{lx, ly, lz, Bool.not(on)}, tail}, Con{head, flip_lever_at(tail, x, y, z)})

def flip_lever(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  Bool.pick(State, lever_present(levers, x, y, z), State{wires, torches, flip_lever_at(levers, x, y, z), spots, lamps}, state)

def spot_present(spots: List<&2, Spot>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match spots:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Spot{+sx, +sy, +sz} = head
      +same = Bool.and(Bool.and(Nat.is_eq(sx, x), Nat.is_eq(sy, y)), Nat.is_eq(sz, z))
      Bool.or(same, spot_present(tail, x, y, z))

def place_power_block(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  Bool.pick(State, spot_present(spots, x, y, z), state,
    State{wires, torches, levers, Con{Spot{x, y, z}, spots}, lamps})

def lamp_present(lamps: List<&2, Lamp>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match lamps:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Lamp{+lx, +ly, +lz, lit} = head
      +same = Bool.and(Bool.and(Nat.is_eq(lx, x), Nat.is_eq(ly, y)), Nat.is_eq(lz, z))
      Bool.or(same, lamp_present(tail, x, y, z))

def place_lamp(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  Bool.pick(State, lamp_present(lamps, x, y, z), state,
    State{wires, torches, levers, spots, Con{Lamp{x, y, z, False{}}, lamps}})

def torch_present(torches: List<&2, Torch>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match torches:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Torch{+tx, +ty, +tz, lit, prev, streak, burnt} = head
      +same = Bool.and(Bool.and(Nat.is_eq(tx, x), Nat.is_eq(ty, y)), Nat.is_eq(tz, z))
      Bool.or(same, torch_present(tail, x, y, z))

def place_torch(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  Bool.pick(State, torch_present(torches, x, y, z), state,
    State{wires, Con{Torch{x, y, z, True{}, True{}, 0, False{}}, torches}, levers, spots, lamps})

# Breaking any redstone component removes it and its cached power.
def drop_torches(torches: List<&2, Torch>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Torch>:
  match torches:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Torch{+tx, +ty, +tz, lit, prev, streak, burnt} = head
      +same = Bool.and(Bool.and(Nat.is_eq(tx, x), Nat.is_eq(ty, y)), Nat.is_eq(tz, z))
      Bool.pick(List<&2, Torch>, same, tail, Con{head, drop_torches(tail, x, y, z)})

def drop_levers(levers: List<&2, Lever>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Lever>:
  match levers:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Lever{+lx, +ly, +lz, on} = head
      +same = Bool.and(Bool.and(Nat.is_eq(lx, x), Nat.is_eq(ly, y)), Nat.is_eq(lz, z))
      Bool.pick(List<&2, Lever>, same, tail, Con{head, drop_levers(tail, x, y, z)})

def drop_spots(spots: List<&2, Spot>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Spot>:
  match spots:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Spot{+sx, +sy, +sz} = head
      +same = Bool.and(Bool.and(Nat.is_eq(sx, x), Nat.is_eq(sy, y)), Nat.is_eq(sz, z))
      Bool.pick(List<&2, Spot>, same, tail, Con{head, drop_spots(tail, x, y, z)})

def drop_lamps(lamps: List<&2, Lamp>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Lamp>:
  match lamps:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Lamp{+lx, +ly, +lz, lit} = head
      +same = Bool.and(Bool.and(Nat.is_eq(lx, x), Nat.is_eq(ly, y)), Nat.is_eq(lz, z))
      Bool.pick(List<&2, Lamp>, same, tail, Con{head, drop_lamps(tail, x, y, z)})

def remove_at(+state: State, +x: Nat, +y: Nat, +z: Nat) -> State:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  State{
    drop_wires(wires, x, y, z),
    drop_torches(torches, x, y, z),
    drop_levers(levers, x, y, z),
    drop_spots(spots, x, y, z),
    drop_lamps(lamps, x, y, z)
  }

# ---------------------------------------------------------------------------
# Source collection
# ---------------------------------------------------------------------------

def spot_emits(spots: List<&2, Spot>, acc: List<&2, Emission>) -> List<&2, Emission>:
  match spots:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Spot{+x, +y, +z} = head
      spot_emits(tail, append_emits(cube_emits(x, y, z), acc))

def lever_emits(levers: List<&2, Lever>, +acc: List<&2, Emission>) -> List<&2, Emission>:
  match levers:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Lever{+x, +y, +z, +on} = head
      Bool.pick(List<&2, Emission>, on, lever_emits(tail, append_emits(cube_emits(x, y, z), acc)),
        lever_emits(tail, acc))

def torch_emits_at(torches: List<&2, Torch>, +source: Nat, +acc: List<&2, Emission>) -> List<&2, Emission>:
  match torches:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Torch{+x, +y, +z, +lit, prev, streak, burnt} = head
      Bool.pick(List<&2, Emission>, lit,
        torch_emits_at(tail, Nat.add(source, 1n), append_emits(torch_emits(x, y, z, source), acc)),
        torch_emits_at(tail, Nat.add(source, 1n), acc))

# Every cell a component hands full power to this tick. `outputs` carries the
# cells that components with their own delay counters - repeaters, comparators,
# rails - drove, so this module never has to know how they decided.
def emits(state: State, outputs: List<&2, Emission>) -> List<&2, Emission>:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  append_emits(outputs, torch_emits_at(torches, 1n, lever_emits(levers, spot_emits(spots, Nil{}))))

# ---------------------------------------------------------------------------
# Dust flood
#
# Vanilla rules, in two phases. A dust cell touching a source is pinned to 15;
# every other cell takes the strongest signal a neighbour hands it, minus one,
# so a line of dust away from a redstone block reads 15, 14, 13, ...
#
# The frontier is processed a whole level at a time, so the first visit a cell
# gets is always its highest level regardless of the order the wires were
# placed in. That is what makes `resolve` deterministic.
# ---------------------------------------------------------------------------

type Flow is Data:
  Flow{x: Nat, y: Nat, z: Nat, level: U32}

# `dust` is every cell that actually holds wire, so the flood stops at a gap
# instead of walking the whole plane. `done` is the reached cells, which double
# as the power map: a reached cell always holds at least 1, so "not in done" is
# also "not reached". `hit` records whether the last claim landed, and the flood
# only spreads from a cell that did - spreading from a cell the signal never
# reached is what turns a line of dust into an unbounded fan-out.
type Flooding is Type:
  Flooding{front: List<&2, Flow>, next: List<&2, Flow>, done: List<&2, Wire>, dust: List<&2, Wire>, hit: Bool}

def push_flow.at(
  front: List<&2, Flow>, +next: List<&2, Flow>, done: List<&2, Wire>, dust: List<&2, Wire>, hit: Bool,
  +x: Nat, +y: Nat, +z: Nat, +level: U32, live: Bool
) -> Flooding:
  match live:
    case False{}:
      Flooding{front, next, done, dust, hit}
    case True{}:
      Flooding{front, Con{Flow{x, y, z, level}, next}, done, dust, hit}

def push_flow(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  Flooding{front, next, done, dust, hit} = flooding
  push_flow.at(front, next, done, dust, hit, x, y, z, level, U32.is_gt(level, 0))

# Dust couples to the four cells around it, losing one per step.
def push_four(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  right = push_flow(flooding, Nat.add(x, 1n), y, z, level)
  left = push_flow(right, Nat.sub(x, 1n), y, z, level)
  front_step = push_flow(left, x, y, Nat.add(z, 1n), level)
  push_flow(front_step, x, y, Nat.sub(z, 1n), level)

# Dust also couples straight up and down, and that connection is direct: the cell
# above takes the level unchanged, so a vertical column is all the same power and
# a stack of dust is a way to carry a signal upstairs. This is what lets a
# repeater and a torch close a loop into a clock - the torch's power reaches the
# repeater's back through the dust stacked under it.
def push_up(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  below = push_flow(flooding, x, Nat.add(y, 1n), z, level)
  push_flow(below, x, Nat.sub(y, 1n), z, level)

# Record a cell's final power. A cell already holding power was reached by an
# equal or stronger level first, because the frontier is drained a whole level
# at a time, so it keeps what it has and the answer does not depend on the order
# the wires were placed in. A cell with no wire is not a cell the signal can
# cross, so it is never claimed.
def claim.at(
  front: List<&2, Flow>, +next: List<&2, Flow>, +done: List<&2, Wire>, dust: List<&2, Wire>,
  +x: Nat, +y: Nat, +z: Nat, +level: U32, open: Bool
) -> Flooding:
  match open:
    case False{}:
      Flooding{front, next, done, dust, False{}}
    case True{}:
      Flooding{front, next, Con{Wire{x, y, z, level}, done}, dust, True{}}

def flood.claim(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  Flooding{front, next, +done, +dust, hit} = flooding
  claim.at(front, next, done, dust, x, y, z, level,
    Bool.and(wire_present(dust, x, y, z), U32.is_eq(wire_at(done, x, y, z), 0)))

# Hand the four neighbours one level less and the two vertical ones the level
# unchanged, but only from a cell the signal actually reached.
def flood.spread(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +level: U32) -> Flooding:
  Flooding{front, +next, done, dust, hit} = flooding
  match hit:
    case False{}:
      Flooding{front, next, done, dust, hit}
    case True{}:
      sideways = push_four(Flooding{front, next, done, dust, hit}, x, y, z, sat_sub32(level, 1))
      push_up(sideways, x, y, z, level)

# A queue entry carries the level for the cell it names, so a cell a source
# touched and a cell the signal reached by decay travel the same path.
def flood.level(front: List<&2, Flow>, flooding: Flooding) -> Flooding:
  match front:
    case Nil{}:
      flooding
    case Con{+head, tail}:
      Flow{+x, +y, +z, +level} = head
      taken = flood.claim(flooding, x, y, z, level)
      spread = flood.spread(taken, x, y, z, level)
      flood.level(tail, spread)

# Drain the level that was collected, keeping what the level after it collects,
# so the queue stays a queue instead of growing for the whole tick.
def flood.turn(flooding: Flooding) -> Flooding:
  Flooding{front, +next, done, dust, hit} = flooding
  flood.level(next, Flooding{next, Nil{}, done, dust, hit})

# Phase one: queue every dust cell a source reaches at full power. Seeding only
# queues; `flood.level` stays the single place a power level is ever set.
def seed_cell(flooding: Flooding, +x: Nat, +y: Nat, +z: Nat, +reached: Bool) -> Flooding:
  match reached:
    case False{}:
      flooding
    case True{}:
      push_flow(flooding, x, y, z, max_power())

def flood.seed(wires: List<&2, Wire>, +emits: List<&2, Emission>, flooding: Flooding) -> Flooding:
  match wires:
    case Nil{}:
      flooding
    case Con{+head, tail}:
      Wire{+x, +y, +z, power} = head
      flood.seed(tail, emits, seed_cell(flooding, x, y, z, emits_strong_at(emits, x, y, z)))

# The fuel bounds how many cells deep the frontier may be drained, not how
# strong a signal is: sideways steps lose a level and stop at zero, so a chain
# away from a redstone block dies on its own after fifteen cells. A vertical
# step is direct and keeps its level, so a column of dust stacked twenty high
# needs twenty turns - and a circuit with no vertical dust never needs more than
# sixteen. The bound has to exceed the longest path in the dust graph, and the
# visited check means the frontier stops growing long before it is reached; a
# circuit deeper than this is truncated, which the caller can see.
def flood_level() -> Nat:
  256n

def flood.run(+remaining: Nat, flooding: Flooding) -> List<&2, Wire>:
  match remaining:
    case 0n:
      Flooding{front, next, done, dust, hit} = flooding
      done
    case 1n+p:
      flood.run(p, flood.turn(flooding))

def flood_power(+wires: List<&2, Wire>, emits: List<&2, Emission>) -> List<&2, Wire>:
  flood.run(flood_level(), flood.seed(wires, emits, Flooding{Nil{}, Nil{}, Nil{}, wires, False{}}))

# ---------------------------------------------------------------------------
# Resolve: the combinational fixed point
#
# One pass recomputes dust, torches and lamps from the emissions the current
# component states produce, and reports whether anything moved. A circuit is
# cyclic - a torch inverts the dust that powers it - so the pass repeats until
# it settles or the fuel runs out. Fuel, not a fixed point, is the termination
# guarantee: a circuit that never settles is a bug the caller can see, not a
# loop the checker has to trust.
# ---------------------------------------------------------------------------

type Rebuilt is Data:
  Rebuilt{wires: List<&2, Wire>, changed: Bool}

type Resolved is Data:
  Resolved{state: State, changed: Bool}

def rebuilt.wires(rebuilt: Rebuilt) -> List<&2, Wire>:
  Rebuilt{wires, changed} = rebuilt
  wires

def rebuilt.changed(rebuilt: Rebuilt) -> Bool:
  Rebuilt{wires, changed} = rebuilt
  changed

def resolved.changed(resolved: Resolved) -> Bool:
  Resolved{state, changed} = resolved
  changed

def resolved.state(resolved: Resolved) -> State:
  Resolved{state, changed} = resolved
  state

# Read the fresh power back onto the stored cells, so the browser keeps seeing
# the dust in the order the player laid it.
def rebuild.go(wires: List<&2, Wire>, +done: List<&2, Wire>, +acc: List<&2, Wire>, changed: Bool) -> Rebuilt:
  match wires:
    case Nil{}:
      Rebuilt{acc, changed}
    case Con{+head, +tail}:
      Wire{+x, +y, +z, +power} = head
      +fresh = wire_at(done, x, y, z)
      +rest = rebuild.go(tail, done, Con{Wire{x, y, z, fresh}, acc}, Bool.or(changed, U32.is_ne(fresh, power)))
      Rebuilt{rebuilt.wires(rest), rebuilt.changed(rest)}

def reverse_wires(wires: List<&2, Wire>, acc: List<&2, Wire>) -> List<&2, Wire>:
  match wires:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      reverse_wires(tail, Con{head, acc})

def rebuild.wires(wires: List<&2, Wire>, done: List<&2, Wire>) -> Rebuilt:
  +flipped = rebuild.go(wires, done, Nil{}, False{})
  Rebuilt{reverse_wires(rebuilt.wires(flipped), Nil{}), rebuilt.changed(flipped)}

# A torch inverts the power reaching the block it stands on, ignoring its own
# emission to that same block, and a burnt one stays dark however hard the
# circuit drives it.
def rebuild.torches(torches: List<&2, Torch>, +source: Nat, +emits: List<&2, Emission>) -> List<&2, Torch>:
  match torches:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Torch{+x, +y, +z, +lit, +prev, +streak, +burnt} = head
      +target = Bool.not(U32.is_gt(emits_power_others_at(emits, x, Nat.sub(y, 1n), z, source), 0))
      +want = Bool.pick(Bool, burnt, False{}, target)
      +rest = rebuild.torches(tail, Nat.add(source, 1n), emits)
      Bool.pick(List<&2, Torch>, same_bool(lit, want), Con{head, rest},
        Con{Torch{x, y, z, want, prev, streak, burnt}, rest})

# A lamp answers to a source in any of the six cells around it and to dust
# pointing into any of the four around it, never to the dust it stands on.
def lamp_on(lamps: List<&2, Lamp>, +x: Nat, +y: Nat, +z: Nat, +emits: List<&2, Emission>, +wires: List<&2, Wire>) -> Bool:
  Bool.or(emits_at(emits, x, y, z),
    Bool.or(U32.is_gt(wire_at(wires, Nat.add(x, 1n), y, z), 0),
    Bool.or(U32.is_gt(wire_at(wires, Nat.sub(x, 1n), y, z), 0),
    Bool.or(U32.is_gt(wire_at(wires, x, y, Nat.add(z, 1n)), 0),
      U32.is_gt(wire_at(wires, x, y, Nat.sub(z, 1n)), 0)))))

def rebuild.lamps(lamps: List<&2, Lamp>, +emits: List<&2, Emission>, +wires: List<&2, Wire>) -> List<&2, Lamp>:
  match lamps:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Lamp{+x, +y, +z, +lit} = head
      +want = lamp_on(lamps, x, y, z, emits, wires)
      +rest = rebuild.lamps(tail, emits, wires)
      Bool.pick(List<&2, Lamp>, same_bool(lit, want), Con{head, rest}, Con{Lamp{x, y, z, want}, rest})

# One pass of the fixed point.
#
# The flood is seeded from the strong emissions alone, so a wire's own weak
# output never short-circuits the decay. The fresh powers are then folded back
# in as weak emissions, and only the torches and lamps read those - so a circuit
# settles in one direction per pass, never in one step.
# One pass of the fixed point, with the reached cells already computed.
#
# Splitting the flood out is what lets ./redstone_grid.bend swap the quadratic
# list flood for the linear array one without duplicating any of the rules: the
# reached cells are all this pass needs from a flood, and both floods answer in
# the same shape. `resolve.once` is the list flood's own entry point.
def resolve.once_with(
  +state: State, +outputs: List<&2, Emission>, +reached: List<&2, Wire>
) -> Resolved:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  +strong = emits(state, outputs)
  +fresh = rebuild.wires(wires, reached)
  +all = wire_emits(rebuilt.wires(fresh), strong)
  +next_torches = rebuild.torches(torches, 1n, all)
  +next_lamps = rebuild.lamps(lamps, all, rebuilt.wires(fresh))
  Resolved{State{rebuilt.wires(fresh), next_torches, levers, spots, next_lamps}, rebuilt.changed(fresh)}

def resolve.once(+state: State, +outputs: List<&2, Emission>) -> Resolved:
  resolve.once_with(state, outputs, flood_power(state_wires(state), emits(state, outputs)))

# Eight passes settle every chain this contract can express: an inverter needs
# two (dust, then torch), a torch pair four, and an oscillator is held apart by
# the repeater delay the fixed point never sees.
def resolve_fuel() -> Nat:
  8n

# The fixed point, one pass at a time, repeated until a pass reports no change.
#
# `stop` is the selector this shape needs, and the reason is a measurement rather
# than taste. Choosing between two arms of a `Bool.pick` passes both arms as
# already-built arguments, so on the JavaScript target the recursive call in the
# arm that was not taken is evaluated anyway: a settled 200-cell circuit spent all
# eight passes - 99 ms of floods - because every pass re-entered the fixed point
# whatever the answer said. Matching on a parameter is the form the emitted
# JavaScript short-circuits, and a settled circuit now costs one pass. An unstable
# circuit still runs to the fuel bound, which is what the bound is for.
#
# Termination: the recursive call hands on `p`, the smaller part of the `1n+p` it
# matched, so the fuel bounds the loop.
def resolve.at(
  +remaining: Nat, +state: State, +outputs: List<&2, Emission>, stop: Bool
) -> State:
  match remaining:
    case 0n:
      state
    case 1n+p:
      match stop:
        case True{}:
          state
        case False{}:
          +once = resolve.once(state, outputs)
          resolve.at(p, resolved.state(once), outputs, Bool.not(resolved.changed(once)))

# The entry point, and it takes the fuel and nothing else. `stop` stays internal
# because a caller that omitted it from JavaScript would hand the match an
# `undefined` and get back a state with every wire dropped - a silent wrong answer
# rather than an error, which is the kind of trap a three-argument signature does
# not have.
def resolve(+remaining: Nat, +state: State, +outputs: List<&2, Emission>) -> State:
  resolve.at(remaining, state, outputs, False{})

# ---------------------------------------------------------------------------
# Tick
#
# `advance` runs once per game tick and `resolve` then settles the result, in
# that order. Keeping the streak counters out of `resolve` is what makes an
# oscillator advance one repetition per tick instead of running at the speed of
# the fixed point.
# ---------------------------------------------------------------------------

# A torch that has flipped on this many ticks running has burnt out.
def burnout_limit() -> U32:
  8

def advance_torch(torch: Torch) -> Torch:
  Torch{+x, +y, +z, +lit, +prev, +streak, +burnt} = torch
  +settled = same_bool(lit, prev)
  +count = Bool.pick(U32, settled, 0, U32.add(streak, 1))
  +hot = U32.is_gt(count, burnout_limit())
  Torch{x, y, z, lit, lit, count, Bool.or(burnt, hot)}

def advance_torches(torches: List<&2, Torch>) -> List<&2, Torch>:
  match torches:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Con{advance_torch(head), advance_torches(tail)}

def with_torches(+state: State, +torches: List<&2, Torch>) -> State:
  State{+wires, old_torches, +levers, +spots, +lamps} = state
  State{wires, torches, levers, spots, lamps}

# The part of a tick that does not settle: the torch streak counters, which is
# what makes a torch burn out and what keeps an oscillator advancing one repetition
# per tick instead of running at the speed of the fixed point.
#
# Split out because the settle step has two implementations - the list flood in
# `resolve` below and the array flood in ./redstone_grid.bend - and both need the
# same advanced state. Only the settle differs, so only the settle is swapped.
def advance(+state: State) -> State:
  State{+wires, +torches, +levers, +spots, +lamps} = state
  State{wires, advance_torches(torches), levers, spots, lamps}

# One game tick of the core circuit, settling with the list flood. `outputs` are
# the cells that components with their own delay counters drove this tick.
#
# This is the reference path: ./redstone_grid.bend settles the same circuit with
# the array flood and must agree with it cell for cell, which
# tests/redstone-grid-bend.test.mjs checks. The game uses the grid one, because
# this flood is quadratic in the size of the circuit.
def tick(+state: State, +outputs: List<&2, Emission>) -> State:
  resolve(resolve_fuel(), advance(state), outputs)

# ---------------------------------------------------------------------------
# Reading the result
# ---------------------------------------------------------------------------

def wire_power(state: State, +x: Nat, +y: Nat, +z: Nat) -> U32:
  wire_at(state_wires(state), x, y, z)

def torch_at.list(torches: List<&2, Torch>, +x: Nat, +y: Nat, +z: Nat) -> Torch:
  match torches:
    case Nil{}:
      Torch{x, y, z, False{}, False{}, 0, True{}}
    case Con{+head, +tail}:
      Torch{+tx, +ty, +tz, lit, prev, streak, burnt} = head
      +same = Bool.and(Bool.and(Nat.is_eq(tx, x), Nat.is_eq(ty, y)), Nat.is_eq(tz, z))
      Bool.pick(Torch, same, head, torch_at.list(tail, x, y, z))

# A cell with no torch reads as dark and burnt, so a missing component is a
# safe answer rather than a special case at every call site.
def torch_at(state: State, +x: Nat, +y: Nat, +z: Nat) -> Torch:
  torch_at.list(state_torches(state), x, y, z)

def torch_lit.of(torch: Torch) -> Bool:
  Torch{x, y, z, lit, prev, streak, burnt} = torch
  lit

def torch_lit(state: State, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  torch_lit.of(torch_at(state, x, y, z))

def torch_burnt.of(torch: Torch) -> Bool:
  Torch{x, y, z, lit, prev, streak, burnt} = torch
  burnt

def torch_burnt(state: State, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  torch_burnt.of(torch_at(state, x, y, z))

def lamp_at.list(lamps: List<&2, Lamp>, +x: Nat, +y: Nat, +z: Nat) -> Lamp:
  match lamps:
    case Nil{}:
      Lamp{x, y, z, False{}}
    case Con{+head, +tail}:
      Lamp{+lx, +ly, +lz, lit} = head
      +same = Bool.and(Bool.and(Nat.is_eq(lx, x), Nat.is_eq(ly, y)), Nat.is_eq(lz, z))
      Bool.pick(Lamp, same, head, lamp_at.list(tail, x, y, z))

def lamp_at(state: State, +x: Nat, +y: Nat, +z: Nat) -> Lamp:
  lamp_at.list(state_lamps(state), x, y, z)

def lamp_lit.of(lamp: Lamp) -> Bool:
  Lamp{x, y, z, lit} = lamp
  lit

def lamp_lit(state: State, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  lamp_lit.of(lamp_at(state, x, y, z))
