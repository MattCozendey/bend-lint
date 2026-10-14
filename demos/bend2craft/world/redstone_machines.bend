import Base
import ./redstone.bend as Redstone

# ---------------------------------------------------------------------------
# Redstone machines
#
# The blocks a circuit operates rather than carries signal through: a door that
# opens, a plate you stand on, a rail that reads, a piston that moves blocks.
#
# Two rules run through all of them.
#
# They are edge driven where vanilla is. A door toggles on the rising edge of a
# signal and a piston fires once, so each keeps the input it saw at the last tick
# and only acts when the input has just gone high. A lever held down must not
# open and close a door fifty times a second.
#
# They are the once-per-tick half, like the repeater counters in
# ./redstone_clock.bend. Keeping them out of the core's fixed point is what stops
# a piston from extending, retracting and extending again inside one tick.
#
# Every type is declared before anything that names it, because Bend binds names
# to the def above them.
# ---------------------------------------------------------------------------

# The world already has a door: block 14 closed, block 15 open. This module reuses
# those two ids rather than inventing a third, so `world/world.bend` and
# `web/inventory.js` stay the single block contract.
def closed_door_block() -> U32:
  14

def open_door_block() -> U32:
  15

# A world change this module wants applied. The browser applies the list; the
# decision is made entirely here.
type Edit is Data:
  Edit{x: Nat, y: Nat, z: Nat, block: U32}

def no_edits() -> List<&2, Edit>:
  Nil{}

def edit(x: Nat, y: Nat, z: Nat, block: U32) -> Edit:
  Edit{x, y, z, block}

def append_edits(+more: List<&2, Edit>, +acc: List<&2, Edit>) -> List<&2, Edit>:
  match more:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      append_edits(tail, Con{head, acc})

def edits_count(edits: List<&2, Edit>, +total: Nat) -> Nat:
  match edits:
    case Nil{}:
      total
    case Con{+head, +tail}:
      edits_count(tail, Nat.add(total, 1n))

# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------

# `seen` is the input this component was driven with last tick. It is what turns
# a level into an edge, and it is the only history any of them keeps.
type Door is Data:
  Door{x: Nat, y: Nat, z: Nat, open: Bool, seen: Bool}

# Pressed by weight, so unlike the door this one answers a level rather than an
# edge: standing on a plate is a steady state, not a pulse.
type Plate is Data:
  Plate{x: Nat, y: Nat, z: Nat, pressed: Bool}

type Rail is Data:
  Rail{x: Nat, y: Nat, z: Nat, powered: Bool}

type Piston is Data:
  Piston{x: Nat, y: Nat, z: Nat, face: U32, sticky: Bool, extended: Bool, seen: Bool}

# The one machine that does not read a signal at all. An observer watches the block
# in front of it and fires when that block *changes*, which is why its history is a
# block id rather than a level: it is the only component here whose input is a
# difference rather than a state.
#
# `seen` is that block id as of the last tick, and `out` counts the ticks of pulse
# still to come. Two, because vanilla's observer holds its output for two game
# ticks and that length is load bearing: it is what lets a pulse be caught by a
# slower reader downstream, and shortening it turns working circuits into ones that
# drop their pulse.
type Observer is Data:
  Observer{x: Nat, y: Nat, z: Nat, face: U32, seen: U32, out: Nat}

type Machines is Data:
  Machines{
    doors: List<&2, Door>,
    plates: List<&2, Plate>,
    rails: List<&2, Rail>,
    pistons: List<&2, Piston>,
    observers: List<&2, Observer>
  }

# What one piston decided this tick, and the world change that goes with it.
type PistonStep is Data:
  PistonStep{piston: Piston, edits: List<&2, Edit>}

def empty() -> Machines:
  Machines{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}

def state_doors(state: Machines) -> List<&2, Door>:
  Machines{doors, plates, rails, pistons, observers} = state
  doors

def state_plates(state: Machines) -> List<&2, Plate>:
  Machines{doors, plates, rails, pistons, observers} = state
  plates

def state_rails(state: Machines) -> List<&2, Rail>:
  Machines{doors, plates, rails, pistons, observers} = state
  rails

def state_pistons(state: Machines) -> List<&2, Piston>:
  Machines{doors, plates, rails, pistons, observers} = state
  pistons

def state_observers(state: Machines) -> List<&2, Observer>:
  Machines{doors, plates, rails, pistons, +observers} = state
  observers

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

def door_present(doors: List<&2, Door>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match doors:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Door{+dx, +dy, +dz, open, seen} = head
      +same = Bool.and(Bool.and(Nat.is_eq(dx, x), Nat.is_eq(dy, y)), Nat.is_eq(dz, z))
      Bool.or(same, door_present(tail, x, y, z))

def place_door(+state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Machines:
  Machines{+doors, +plates, +rails, +pistons, +observers} = state
  Bool.pick(Machines, door_present(doors, x, y, z), state,
    Machines{Con{Door{x, y, z, False{}, False{}}, doors}, plates, rails, pistons, observers})

def plate_present(plates: List<&2, Plate>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match plates:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Plate{+px, +py, +pz, pressed} = head
      +same = Bool.and(Bool.and(Nat.is_eq(px, x), Nat.is_eq(py, y)), Nat.is_eq(pz, z))
      Bool.or(same, plate_present(tail, x, y, z))

def place_plate(+state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Machines:
  Machines{+doors, +plates, +rails, +pistons, +observers} = state
  Bool.pick(Machines, plate_present(plates, x, y, z), state,
    Machines{doors, Con{Plate{x, y, z, False{}}, plates}, rails, pistons, observers})

def rail_present(rails: List<&2, Rail>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match rails:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Rail{+rx, +ry, +rz, powered} = head
      +same = Bool.and(Bool.and(Nat.is_eq(rx, x), Nat.is_eq(ry, y)), Nat.is_eq(rz, z))
      Bool.or(same, rail_present(tail, x, y, z))

def place_rail(+state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Machines:
  Machines{+doors, +plates, +rails, +pistons, +observers} = state
  Bool.pick(Machines, rail_present(rails, x, y, z), state,
    Machines{doors, plates, Con{Rail{x, y, z, False{}}, rails}, pistons, observers})

def piston_present(pistons: List<&2, Piston>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match pistons:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Piston{+px, +py, +pz, face, sticky, extended, seen} = head
      +same = Bool.and(Bool.and(Nat.is_eq(px, x), Nat.is_eq(py, y)), Nat.is_eq(pz, z))
      Bool.or(same, piston_present(tail, x, y, z))

def place_piston(+state: Machines, +x: Nat, +y: Nat, +z: Nat, +face: U32, +sticky: Bool) -> Machines:
  Machines{+doors, +plates, +rails, +pistons, +observers} = state
  Bool.pick(Machines, piston_present(pistons, x, y, z), state,
    Machines{doors, plates, rails, Con{Piston{x, y, z, face, sticky, False{}, False{}}, pistons}, observers})

def drop_doors(doors: List<&2, Door>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Door>:
  match doors:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Door{+dx, +dy, +dz, open, seen} = head
      +same = Bool.and(Bool.and(Nat.is_eq(dx, x), Nat.is_eq(dy, y)), Nat.is_eq(dz, z))
      Bool.pick(List<&2, Door>, same, tail, Con{head, drop_doors(tail, x, y, z)})

def drop_plates(plates: List<&2, Plate>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Plate>:
  match plates:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Plate{+px, +py, +pz, pressed} = head
      +same = Bool.and(Bool.and(Nat.is_eq(px, x), Nat.is_eq(py, y)), Nat.is_eq(pz, z))
      Bool.pick(List<&2, Plate>, same, tail, Con{head, drop_plates(tail, x, y, z)})

def drop_rails(rails: List<&2, Rail>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Rail>:
  match rails:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Rail{+rx, +ry, +rz, powered} = head
      +same = Bool.and(Bool.and(Nat.is_eq(rx, x), Nat.is_eq(ry, y)), Nat.is_eq(rz, z))
      Bool.pick(List<&2, Rail>, same, tail, Con{head, drop_rails(tail, x, y, z)})

def drop_pistons(pistons: List<&2, Piston>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Piston>:
  match pistons:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Piston{+px, +py, +pz, face, sticky, extended, seen} = head
      +same = Bool.and(Bool.and(Nat.is_eq(px, x), Nat.is_eq(py, y)), Nat.is_eq(pz, z))
      Bool.pick(List<&2, Piston>, same, tail, Con{head, drop_pistons(tail, x, y, z)})

def drop_observers(observers: List<&2, Observer>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Observer>:
  match observers:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Observer{+ox, +oy, +oz, face, seen, out} = head
      +same = Bool.and(Bool.and(Nat.is_eq(ox, x), Nat.is_eq(oy, y)), Nat.is_eq(oz, z))
      Bool.pick(List<&2, Observer>, same, drop_observers(tail, x, y, z), Con{head, drop_observers(tail, x, y, z)})

def tail_keep(observers: List<&2, Observer>, +x: Nat, +y: Nat, +z: Nat) -> List<&2, Observer>:
  drop_observers(observers, x, y, z)

def drop_machines(+state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Machines:
  Machines{+doors, +plates, +rails, +pistons, +observers} = state
  Machines{
    drop_doors(doors, x, y, z),
    drop_plates(plates, x, y, z),
    drop_rails(rails, x, y, z),
    drop_pistons(pistons, x, y, z),
    drop_observers(observers, x, y, z)
  }

# ---------------------------------------------------------------------------
# Edge input
# ---------------------------------------------------------------------------

# "The signal has just gone high", answered from the two values a component
# already keeps, so no machine has to remember anything about itself.
def rising(+now: Bool, +seen: Bool) -> Bool:
  Bool.and(now, Bool.not(seen))

# ---------------------------------------------------------------------------
# Reading the result
# ---------------------------------------------------------------------------

def door_open(door: Door) -> Bool:
  Door{x, y, z, +open, seen} = door
  open

def door_block(door: Door) -> U32:
  Bool.pick(U32, door_open(door), open_door_block(), closed_door_block())

def door_at.list(doors: List<&2, Door>, +x: Nat, +y: Nat, +z: Nat) -> Door:
  match doors:
    case Nil{}:
      Door{x, y, z, False{}, False{}}
    case Con{+head, +tail}:
      Door{+dx, +dy, +dz, open, seen} = head
      +same = Bool.and(Bool.and(Nat.is_eq(dx, x), Nat.is_eq(dy, y)), Nat.is_eq(dz, z))
      Bool.pick(Door, same, head, door_at.list(tail, x, y, z))

def door_at(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Door:
  door_at.list(state_doors(state), x, y, z)

def door_is_open(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  door_open(door_at(state, x, y, z))

def plate_pressed(plate: Plate) -> Bool:
  Plate{x, y, z, +pressed} = plate
  pressed

def plate_at.list(plates: List<&2, Plate>, +x: Nat, +y: Nat, +z: Nat) -> Plate:
  match plates:
    case Nil{}:
      Plate{x, y, z, False{}}
    case Con{+head, +tail}:
      Plate{+px, +py, +pz, pressed} = head
      +same = Bool.and(Bool.and(Nat.is_eq(px, x), Nat.is_eq(py, y)), Nat.is_eq(pz, z))
      Bool.pick(Plate, same, head, plate_at.list(tail, x, y, z))

def plate_at(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Plate:
  plate_at.list(state_plates(state), x, y, z)

def plate_is_pressed(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  plate_pressed(plate_at(state, x, y, z))

def rail_powered(rail: Rail) -> Bool:
  Rail{x, y, z, +powered} = rail
  powered

def rail_at.list(rails: List<&2, Rail>, +x: Nat, +y: Nat, +z: Nat) -> Rail:
  match rails:
    case Nil{}:
      Rail{x, y, z, False{}}
    case Con{+head, +tail}:
      Rail{+rx, +ry, +rz, powered} = head
      +same = Bool.and(Bool.and(Nat.is_eq(rx, x), Nat.is_eq(ry, y)), Nat.is_eq(rz, z))
      Bool.pick(Rail, same, head, rail_at.list(tail, x, y, z))

def rail_at(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Rail:
  rail_at.list(state_rails(state), x, y, z)

def rail_is_powered(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  rail_powered(rail_at(state, x, y, z))

def piston_extended(piston: Piston) -> Bool:
  Piston{x, y, z, face, sticky, +extended, seen} = piston
  extended

def piston_at.list(pistons: List<&2, Piston>, +x: Nat, +y: Nat, +z: Nat) -> Piston:
  match pistons:
    case Nil{}:
      Piston{x, y, z, 0, False{}, False{}, False{}}
    case Con{+head, +tail}:
      Piston{+px, +py, +pz, face, sticky, extended, seen} = head
      +same = Bool.and(Bool.and(Nat.is_eq(px, x), Nat.is_eq(py, y)), Nat.is_eq(pz, z))
      Bool.pick(Piston, same, head, piston_at.list(tail, x, y, z))

def piston_at(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Piston:
  piston_at.list(state_pistons(state), x, y, z)

def piston_is_extended(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  piston_extended(piston_at(state, x, y, z))

# ---------------------------------------------------------------------------
# Door
# ---------------------------------------------------------------------------

# Only a rising edge toggles, so holding the power shut leaves the door where it
# went, and a second pulse moves it again.
def door_step(door: Door, +powered: Bool) -> Door:
  Door{+x, +y, +z, +open, +seen} = door
  +moved = rising(powered, seen)
  Door{x, y, z, Bool.pick(Bool, moved, Bool.not(open), open), powered}

def advance_doors(doors: List<&2, Door>, +emits: List<&2, Redstone.Emission>) -> List<&2, Door>:
  match doors:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Door{+x, +y, +z, open, seen} = head
      +powered = U32.is_gt(Redstone.emits_power_at(emits, x, y, z), 0)
      +rest = advance_doors(tail, emits)
      Con{door_step(Door{x, y, z, open, seen}, powered), rest}

# ---------------------------------------------------------------------------
# Pressure plate
# ---------------------------------------------------------------------------

# Air, water and lava carry no weight. A mob or the player standing on a plate is
# reported by the browser as a sample, because the plate asks about the world and
# not about the circuit.
def carries_weight(+block: U32) -> Bool:
  Bool.not(Redstone.airish(block))

def advance_plates(
  plates: List<&2, Plate>, +samples: List<&2, Redstone.Sample>, +emits: List<&2, Redstone.Emission>
) -> List<&2, Plate>:
  match plates:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Plate{+x, +y, +z, pressed} = head
      +weight = carries_weight(Redstone.sample_block(samples, x, Nat.add(y, 1n), z))
      +powered = U32.is_gt(Redstone.emits_power_at(emits, x, y, z), 0)
      +want = Bool.or(weight, powered)
      +rest = advance_plates(tail, samples, emits)
      Con{Plate{x, y, z, want}, rest}

# A pressed plate drives the block above it strongly, which is what a dust line
# running over a plate reads.
def plate_outputs(plates: List<&2, Plate>, +acc: List<&2, Redstone.Emission>) -> List<&2, Redstone.Emission>:
  match plates:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Plate{+x, +y, +z, +pressed} = head
      Bool.pick(List<&2, Redstone.Emission>, pressed,
        plate_outputs(tail, Redstone.append_emits(
          Redstone.emits_one(Redstone.emit_from(x, Nat.add(y, 1n), z, 0n, True{})), acc)),
        plate_outputs(tail, acc))

# ---------------------------------------------------------------------------
# Activator rail
# ---------------------------------------------------------------------------

# There are no minecarts in this slice, so the rail has no cart to detect. What it
# keeps is the half a circuit actually reads: a powered rail drives the block it
# sits under with power one, the vanilla activator behaviour. The cart input is
# the missing piece and is not faked here.
def rail_output(rail: Rail) -> U32:
  Bool.pick(U32, rail_powered(rail), 1, 0)

def advance_rails(rails: List<&2, Rail>, +emits: List<&2, Redstone.Emission>) -> List<&2, Rail>:
  match rails:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Rail{+x, +y, +z, powered} = head
      +want = U32.is_gt(Redstone.emits_power_at(emits, x, y, z), 0)
      +rest = advance_rails(tail, emits)
      Con{Rail{x, y, z, want}, rest}

# Power one, not fifteen: a rail is a weak source, and a comparator reading a
# powered rail sees 1 rather than a full signal.
def rail_outputs(rails: List<&2, Rail>, +acc: List<&2, Redstone.Emission>) -> List<&2, Redstone.Emission>:
  match rails:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Rail{+x, +y, +z, powered} = head
      +level = rail_output(Rail{x, y, z, powered})
      Bool.pick(List<&2, Redstone.Emission>, U32.is_gt(level, 0),
        rail_outputs(tail, Redstone.append_emits(
          Redstone.emits_one(Redstone.emit_level(x, Nat.add(y, 1n), z, 0n, False{}, level)), acc)),
        rail_outputs(tail, acc))

# ---------------------------------------------------------------------------
# Piston
# ---------------------------------------------------------------------------

# Six faces: the four a repeater has, plus up and down.
def face_east() -> U32:
  0

def face_west() -> U32:
  1

def face_south() -> U32:
  2

def face_north() -> U32:
  3

def face_up() -> U32:
  4

def face_down() -> U32:
  5

# How many cells a piston shoves. Vanilla shoves up to twelve, which would need a
# twelve-entry face; this slice states the shorter rule and refuses a push it
# cannot finish, which is how a piston says no.
def push_limit() -> Nat:
  2n

def push_x(+face: U32, +x: Nat, +steps: Nat) -> Nat:
  Bool.pick(Nat, U32.is_eq(face, face_east()), Nat.add(x, steps),
    Bool.pick(Nat, U32.is_eq(face, face_west()), Nat.sub(x, steps), x))

def push_z(+face: U32, +z: Nat, +steps: Nat) -> Nat:
  Bool.pick(Nat, U32.is_eq(face, face_south()), Nat.add(z, steps),
    Bool.pick(Nat, U32.is_eq(face, face_north()), Nat.sub(z, steps), z))

def push_y(+face: U32, +y: Nat, +steps: Nat) -> Nat:
  Bool.pick(Nat, U32.is_eq(face, face_up()), Nat.add(y, steps),
    Bool.pick(Nat, U32.is_eq(face, face_down()), Nat.sub(y, steps), y))

# A piston base sits at P, its head at P+face, the block it shoves at P+2*face,
# and with a two-cell push the cell it needs free beyond that is P+3*face.
def head_x(+face: U32, +x: Nat) -> Nat:
  push_x(face, x, 1n)

def head_y(+face: U32, +y: Nat) -> Nat:
  push_y(face, y, 1n)

def head_z(+face: U32, +z: Nat) -> Nat:
  push_z(face, z, 1n)

def tip_x(+face: U32, +x: Nat) -> Nat:
  push_x(face, x, 2n)

def tip_y(+face: U32, +y: Nat) -> Nat:
  push_y(face, y, 2n)

def tip_z(+face: U32, +z: Nat) -> Nat:
  push_z(face, z, 2n)

def far_x(+face: U32, +x: Nat) -> Nat:
  push_x(face, x, 3n)

def far_y(+face: U32, +y: Nat) -> Nat:
  push_y(face, y, 3n)

def far_z(+face: U32, +z: Nat) -> Nat:
  push_z(face, z, 3n)

# A block a piston may not shove: its own base or head. There is no bedrock in
# this world, so the piston's own parts are the whole list.
def immovable(+block: U32) -> Bool:
  Bool.or(
    Bool.or(U32.is_eq(block, Redstone.piston_block()), U32.is_eq(block, Redstone.sticky_piston_block())),
    U32.is_eq(block, Redstone.head_block()))

def pushable(+block: U32) -> Bool:
  Bool.not(immovable(block))

# Air, water and lava are shoved out of the way; anything else is carried.
def carried(+block: U32) -> Bool:
  Bool.and(pushable(block), Bool.not(Redstone.airish(block)))

def piston_is_sticky(piston: Piston) -> Bool:
  Piston{x, y, z, face, +sticky, extended, seen} = piston
  sticky

def piston_block_id(piston: Piston) -> U32:
  Bool.pick(U32, piston_is_sticky(piston), Redstone.sticky_piston_block(), Redstone.piston_block())

# Whether a step along the face actually left the starting cell. `Nat.sub`
# saturates at zero, so a piston facing away from the origin has its head, tip
# and far cells collapse onto itself; a piston must not extend into its own cell.
def stepped_away(+face: U32, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Bool.or(
    Bool.or(Nat.is_ne(head_x(face, x), x), Nat.is_ne(head_y(face, y), y)),
    Nat.is_ne(head_z(face, z), z))

# Extending needs the head cell empty, the cell it shoves free or movable, and
# the destination cell beyond empty. The far cell is where a carried block lands,
# and this two-cell push has nowhere further to put it, so it must be free. A
# piston that cannot finish its push refuses the whole extension, which is what
# vanilla does and why a piston does not nudge a long line along.
def can_extend(+samples: List<&2, Redstone.Sample>, +face: U32, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  +head = Redstone.sample_block(samples, head_x(face, x), head_y(face, y), head_z(face, z))
  +tip = Redstone.sample_block(samples, tip_x(face, x), tip_y(face, y), tip_z(face, z))
  +far = Redstone.sample_block(samples, far_x(face, x), far_y(face, y), far_z(face, z))
  Bool.and(
    stepped_away(face, x, y, z),
    Bool.and(
      Bool.and(Redstone.airish(head), Bool.or(Redstone.airish(tip), pushable(tip))),
      Redstone.airish(far)))

# The world change for extending: shove the line along by one and put the head in
# the vacated cell. The base cell is already a piston, so it does not move. If the
# tip held a block it is carried to the far cell, and the head goes in the tip cell.
def extend_edits(+samples: List<&2, Redstone.Sample>, +piston: Piston) -> List<&2, Edit>:
  Piston{+x, +y, +z, +face, sticky, extended, seen} = piston
  +tip = Redstone.sample_block(samples, tip_x(face, x), tip_y(face, y), tip_z(face, z))
  Bool.pick(List<&2, Edit>, carried(tip),
    Con{edit(far_x(face, x), far_y(face, y), far_z(face, z), tip),
      Con{edit(tip_x(face, x), tip_y(face, y), tip_z(face, z), Redstone.head_block()),
        Con{edit(head_x(face, x), head_y(face, y), head_z(face, z), Redstone.head_block()), Nil{}}}},
    Con{edit(head_x(face, x), head_y(face, y), head_z(face, z), Redstone.head_block()), Nil{}})

# Retracting takes the head away and leaves a base in its place. A sticky piston
# also drags the block that was pushed into the far cell on its way back, because
# that is the cell directly in front of the extended head.
def retract_edits(+samples: List<&2, Redstone.Sample>, +piston: Piston) -> List<&2, Edit>:
  Piston{+x, +y, +z, +face, +sticky, extended, seen} = piston
  +far = Redstone.sample_block(samples, far_x(face, x), far_y(face, y), far_z(face, z))
  +grab = Bool.and(sticky, carried(far))
  +left = Bool.pick(U32, grab, far, Redstone.air_block())
  append_edits(
    Con{edit(tip_x(face, x), tip_y(face, y), tip_z(face, z), piston_block_id(piston)), Nil{}},
    Con{edit(head_x(face, x), head_y(face, y), head_z(face, z), left), Nil{}})

# Decide, then do. A rising edge extends when the push line clears and is
# otherwise refused outright; the falling edge retracts; and a piston already in
# the state it is being asked for does nothing, so holding the power fires it once.
def piston_step(
  piston: Piston, +powered: Bool, +samples: List<&2, Redstone.Sample>
) -> PistonStep:
  Piston{+x, +y, +z, +face, +sticky, +extended, +seen} = piston
  +fired = rising(powered, seen)
  +fits = can_extend(samples, face, x, y, z)
  +held = Bool.or(fired, powered)
  Bool.pick(PistonStep, Bool.and(fired, Bool.not(extended)),
    Bool.pick(PistonStep, fits,
      PistonStep{Piston{x, y, z, face, sticky, True{}, held}, extend_edits(samples, piston)},
      PistonStep{Piston{x, y, z, face, sticky, False{}, held}, no_edits()}),
    Bool.pick(PistonStep, Bool.and(Bool.not(fired), extended),
      PistonStep{Piston{x, y, z, face, sticky, False{}, held}, retract_edits(samples, piston)},
      PistonStep{Piston{x, y, z, face, sticky, extended, held}, no_edits()}))

def step_piston(piston: Piston, +powered: Bool, +samples: List<&2, Redstone.Sample>) -> PistonStep:
  piston_step(piston, powered, samples)

def step_piston_piston(step: PistonStep) -> Piston:
  PistonStep{piston, edits} = step
  piston

def step_piston_edits(step: PistonStep) -> List<&2, Edit>:
  PistonStep{piston, +edits} = step
  edits
# ---------------------------------------------------------------------------
# Observer
#
# The only component here with no signal input. It reads the block in front of it
# and fires when that block's id differs from the id it saw last tick.
#
# Two rules are vanilla's and both are load bearing.
#
# It adopts its first sight without firing. Placing an observer beside a block that
# was already there is not a change, and an observer that fired on placement would
# make every observer a one-shot. `unobserved` marks "has not seen anything yet" and
# it is a block id no world block has, so the first tick reads as a first
# observation rather than as a change away from nothing.
#
# The pulse is two ticks. One would be swallowed by anything slower than the
# observer, and the two-tick hold is what a circuit is built around.
# ---------------------------------------------------------------------------

# Block ids are small and this is not one of them, so it can only ever mean "no
# observation yet". See world/world.bend for the block contract.
def unobserved() -> U32:
  65535

# How many ticks the observer holds its output. Vanilla is two.
def observer_pulse() -> Nat:
  2n

def observer_present(observers: List<&2, Observer>, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  match observers:
    case Nil{}:
      False{}
    case Con{+head, +tail}:
      Observer{+ox, +oy, +oz, face, seen, out} = head
      +same = Bool.and(Bool.and(Nat.is_eq(ox, x), Nat.is_eq(oy, y)), Nat.is_eq(oz, z))
      Bool.or(same, observer_present(tail, x, y, z))

def place_observer(
  +state: Machines, +x: Nat, +y: Nat, +z: Nat, +face: U32
) -> Machines:
  Machines{+doors, +plates, +rails, +pistons, +observers} = state
  Bool.pick(Machines, observer_present(observers, x, y, z), state,
    Machines{
      doors, plates, rails, pistons,
      Con{Observer{x, y, z, face, unobserved(), 0n}, observers}})

def observer_at.list(observers: List<&2, Observer>, +x: Nat, +y: Nat, +z: Nat) -> Observer:
  match observers:
    case Nil{}:
      Observer{x, y, z, 0, unobserved(), 0n}
    case Con{+head, +tail}:
      Observer{+ox, +oy, +oz, face, seen, out} = head
      +same = Bool.and(Bool.and(Nat.is_eq(ox, x), Nat.is_eq(oy, y)), Nat.is_eq(oz, z))
      Bool.pick(Observer, same, head, observer_at.list(tail, x, y, z))

def observer_at(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Observer:
  observer_at.list(state_observers(state), x, y, z)

def observer_firing(observer: Observer) -> Bool:
  Observer{x, y, z, face, seen, +out} = observer
  Nat.is_gt(out, 0n)

def observer_is_firing(state: Machines, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  observer_firing(observer_at(state, x, y, z))

# The cell in front is the head cell of a piston facing the same way, so the face
# arithmetic is the piston's and cannot disagree with it.
def observer_front_x(observer: Observer) -> Nat:
  Observer{+x, +y, +z, +face, seen, out} = observer
  head_x(face, x)

def observer_front_y(observer: Observer) -> Nat:
  Observer{+x, +y, +z, +face, seen, out} = observer
  head_y(face, y)

def observer_front_z(observer: Observer) -> Nat:
  Observer{+x, +y, +z, +face, seen, out} = observer
  head_z(face, z)

# The front cell is the observer's own cell when the face steps off a coordinate
# plane and `Nat.sub` saturates. An observer does not watch itself, so such a front
# cell is not observed at all and the observer holds no state about it - otherwise
# it would see its own block appearing and fire on placement, forever.
def observer_watchable(observer: Observer) -> Bool:
  Observer{+x, +y, +z, face, seen, out} = observer
  stepped_away(face, x, y, z)

def watch_block(
  +samples: List<&2, Redstone.Sample>, +x: Nat, +y: Nat, +z: Nat, watchable: Bool
) -> U32:
  Bool.pick(U32, watchable, Redstone.sample_block(samples, x, y, z), unobserved())

def observer_step(observer: Observer, +samples: List<&2, Redstone.Sample>) -> Observer:
  Observer{+x, +y, +z, +face, +seen, +out} = observer
  +now = watch_block(
    samples, observer_front_x(observer), observer_front_y(observer), observer_front_z(observer),
    observer_watchable(observer))
  +first = U32.is_eq(seen, unobserved())
  +changed = Bool.and(Bool.not(first), U32.is_ne(now, seen))
  # `out` is read as "still to emit, counting this tick", and the emissions are read
  # off the state this def returns, so a change that sets it to the full pulse
  # length emits on the tick that saw the change and on the one after: two ticks,
  # which is what vanilla holds and what a slower reader downstream needs.
  +held = Bool.pick(Nat, Nat.is_gt(out, 0n), Nat.sub(out, 1n), 0n)
  Observer{
    x,
    y,
    z,
    face,
    # What it saw is what is in front of it now, every tick. Keeping the old value
    # instead would compare each tick against the same stale id and fire forever.
    # When the front cell is not watchable `now` is the unseen marker again, so the
    # observer goes back to holding no state and adopts without firing if it is ever
    # given a cell it can watch.
    now,
    Bool.pick(Nat, changed, observer_pulse(), held)
  }

def advance_observers(
  observers: List<&2, Observer>, +samples: List<&2, Redstone.Sample>
) -> List<&2, Observer>:
  match observers:
    case Nil{}:
      Nil{}
    case Con{+head, +tail}:
      Con{observer_step(head, samples), advance_observers(tail, samples)}

# A block-shaped source, the same shape as a redstone block or an engaged lever:
# six strong neighbours. An observer is a solid block while it fires, so dust
# touching any side of it is powered, and it does not invert, so it needs no
# torch's self-exclusion and carries source id zero - the id the core reserves for
# anything that never checks itself.
def observer_outputs(
  observers: List<&2, Observer>, +acc: List<&2, Redstone.Emission>
) -> List<&2, Redstone.Emission>:
  match observers:
    case Nil{}:
      acc
    case Con{+head, +tail}:
      Observer{+x, +y, +z, face, seen, out} = head
      Bool.pick(List<&2, Redstone.Emission>, Nat.is_gt(out, 0n),
        observer_outputs(tail, Redstone.append_emits(Redstone.cube_emits(x, y, z), acc)),
        observer_outputs(tail, acc))


# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

# The machine list and the edits it wants, kept together because a piston is the
# only component that changes the world rather than just carrying signal.
type Stepped is Data:
  Stepped{machines: Machines, edits: List<&2, Edit>}

def stepped_machines(state: Stepped) -> Machines:
  Stepped{machines, +edits} = state
  machines

def stepped_edits(state: Stepped) -> List<&2, Edit>:
  Stepped{+machines, edits} = state
  edits

# What every machine drives this tick, so a dust line or a torch sitting on one
# sees it. Plates and rails are the only two that emit, because a door and a
# piston are read by the player and by the physics, not by the circuit.
def outputs(state: Machines) -> List<&2, Redstone.Emission>:
  Machines{+doors, +plates, +rails, +pistons, +observers} = state
  observer_outputs(observers, rail_outputs(rails, plate_outputs(plates, Nil{})))

# The piston list and the edits they asked for, threaded together because a piston
# is the only component that changes the world rather than just carrying signal.
type PistonRun is Data:
  PistonRun{pistons: List<&2, Piston>, edits: List<&2, Edit>}

def piston_run_pistons(run: PistonRun) -> List<&2, Piston>:
  PistonRun{pistons, edits} = run
  pistons

def piston_run_edits(run: PistonRun) -> List<&2, Edit>:
  PistonRun{+pistons, +edits} = run
  edits

def advance_pistons(
  pistons: List<&2, Piston>, +emits: List<&2, Redstone.Emission>, +samples: List<&2, Redstone.Sample>,
  +acc: List<&2, Edit>, +rest: List<&2, Piston>
) -> PistonRun:
  match pistons:
    case Nil{}:
      PistonRun{rest, acc}
    case Con{+head, +tail}:
      Piston{+x, +y, +z, face, sticky, extended, seen} = head
      +powered = U32.is_gt(Redstone.emits_power_at(emits, x, y, z), 0)
      +step = step_piston(Piston{x, y, z, face, sticky, extended, seen}, powered, samples)
      +next = advance_pistons(tail, emits, samples,
        append_edits(step_piston_edits(step), acc), Con{step_piston_piston(step), rest})
      PistonRun{piston_run_pistons(next), piston_run_edits(next)}

# One game tick of the machines. The circuit is read first - the emissions the
# components drove this tick - and the piston edits come back to the caller to
# apply, because moving a block is a world change, not a circuit fact.
def step(+state: Machines, +emits: List<&2, Redstone.Emission>, +samples: List<&2, Redstone.Sample>) -> Stepped:
  Machines{+doors, +plates, +rails, +pistons, +observers} = state
  +next_doors = advance_doors(doors, emits)
  +next_plates = advance_plates(plates, samples, emits)
  +next_rails = advance_rails(rails, emits)
  +run = advance_pistons(pistons, emits, samples, Nil{}, Nil{})
  +next_observers = advance_observers(observers, samples)
  Stepped{
    Machines{next_doors, next_plates, next_rails, piston_run_pistons(run), next_observers},
    piston_run_edits(run)}
