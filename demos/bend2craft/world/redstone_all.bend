import Base
import ./redstone.bend as Redstone
import ./redstone_clock.bend as Clock
import ./redstone_machines.bend as Machines
import ./redstone_grid.bend as Grid

# ---------------------------------------------------------------------------
# Redstone entry point
#
# The three redstone contracts are separate because they are separate concerns:
# the combinational core, the timed components, and the machines. This module is
# the one the browser ticker calls, so the web layer has a single seam and the
# per-tick order lives here rather than in JavaScript.
#
# The order within a tick is the whole design, and it matches the order each
# module documents:
#
#   1. The machines read the circuit as it stands and decide (door, plate, rail,
#      piston) - this is where the world changes a piston wants to make.
#   2. The timed components (repeater, comparator) read the circuit and run their
#      counters once.
#   3. The core settles the dust, torches and lamps against everything the timed
#      components and the machines drove this tick.
#
# Nothing here decides a redstone rule; every call delegates. The web layer's job
# is to gather the world samples, call `tick`, and apply the edits and the fresh
# component states it gets back.
# ---------------------------------------------------------------------------

type Circuit is Data:
  Circuit{core: Redstone.State, timers: Clock.Timers, machines: Machines.Machines}

type Stepped is Data:
  Stepped{circuit: Circuit, edits: List<&2, Machines.Edit>}

def empty() -> Circuit:
  Circuit{Redstone.empty(), Clock.empty(), Machines.empty()}

def circuit_core(state: Circuit) -> Redstone.State:
  Circuit{core, timers, machines} = state
  core

def circuit_timers(state: Circuit) -> Clock.Timers:
  Circuit{core, +timers, machines} = state
  timers

def circuit_machines(state: Circuit) -> Machines.Machines:
  Circuit{core, timers, +machines} = state
  machines

def stepped_circuit(state: Stepped) -> Circuit:
  Stepped{+circuit, edits} = state
  circuit

def stepped_edits(state: Stepped) -> List<&2, Machines.Edit>:
  Stepped{circuit, +edits} = state
  edits

# ---------------------------------------------------------------------------
# Placement and reading, re-exposed
#
# The browser places blocks and reads component state through this one module, so
# it never reaches into the three sub-contracts to do so. Each is a direct pass
# through; no rule lives here.
# ---------------------------------------------------------------------------

def place_lever(+state: Circuit, +x: Nat, +y: Nat, +z: Nat, +on: Bool) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{Redstone.place_lever(core, x, y, z, on), timers, machines}

def flip_lever(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{Redstone.flip_lever(core, x, y, z), timers, machines}

def place_wire(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{Redstone.place_wire(core, x, y, z), timers, machines}

def place_torch(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{Redstone.place_torch(core, x, y, z), timers, machines}

def place_power_block(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{Redstone.place_power_block(core, x, y, z), timers, machines}

def place_lamp(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{Redstone.place_lamp(core, x, y, z), timers, machines}

def place_repeater(
  +state: Circuit, +x: Nat, +y: Nat, +z: Nat, +dir: U32, +setting: U32
) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{core, Clock.place_repeater(timers, x, y, z, dir, setting), machines}

def place_comparator(
  +state: Circuit, +x: Nat, +y: Nat, +z: Nat, +dir: U32, +mode: U32
) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{core, Clock.place_comparator(timers, x, y, z, dir, mode), machines}

def place_door(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{core, timers, Machines.place_door(machines, x, y, z)}

def place_plate(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{core, timers, Machines.place_plate(machines, x, y, z)}

def place_rail(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{core, timers, Machines.place_rail(machines, x, y, z)}

def place_piston(
  +state: Circuit, +x: Nat, +y: Nat, +z: Nat, +face: U32, +sticky: Bool
) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{core, timers, Machines.place_piston(machines, x, y, z, face, sticky)}

def place_observer(
  +state: Circuit, +x: Nat, +y: Nat, +z: Nat, +face: U32
) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{core, timers, Machines.place_observer(machines, x, y, z, face)}

def remove_at(+state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Circuit:
  Circuit{+core, +timers, +machines} = state
  Circuit{
    Redstone.remove_at(core, x, y, z),
    timers,
    Machines.drop_machines(machines, x, y, z)
  }

# Reading the result, all through this module.
def wire_power(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> U32:
  Redstone.wire_power(circuit_core(state), x, y, z)

def torch_lit(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Redstone.torch_lit(circuit_core(state), x, y, z)

def lamp_lit(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Redstone.lamp_lit(circuit_core(state), x, y, z)

def repeater_out(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> U32:
  Clock.repeater_out(circuit_timers(state), x, y, z)

def comparator_out(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> U32:
  Clock.comparator_out(circuit_timers(state), x, y, z)

def door_is_open(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Machines.door_is_open(circuit_machines(state), x, y, z)

def plate_is_pressed(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Machines.plate_is_pressed(circuit_machines(state), x, y, z)

def rail_is_powered(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Machines.rail_is_powered(circuit_machines(state), x, y, z)

def piston_is_extended(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Machines.piston_is_extended(circuit_machines(state), x, y, z)

def observer_is_firing(state: Circuit, +x: Nat, +y: Nat, +z: Nat) -> Bool:
  Machines.observer_is_firing(circuit_machines(state), x, y, z)

def face_east() -> U32:
  Machines.face_east()

def dir_east() -> U32:
  Clock.dir_east()

# Pack the settled core and the window it settled with into the result. The tick
# pair arrives as a parameter because a pair this def built could not be taken
# apart - the language lets a computed pair be passed on, not opened.
def tick.of(
  +step: Clock.Tick, +machines: Machines.Machines, +edits: List<&2, Machines.Edit>, used: Array<U32>
) -> Stepped & Array<U32>:
  (Stepped{Circuit{Clock.tick_core(step), Clock.tick_timers(step), machines}, edits}, used)

def tick.pack(
  +machines: Machines.Machines, +edits: List<&2, Machines.Edit>, carried: Clock.Tick & Array<U32>
) -> Stepped & Array<U32>:
  (step, used) = carried
  tick.of(step, machines, edits, used)

# One game tick. `emits` is the circuit's emissions from the end of the last tick
# and `samples` is the handful of world blocks a redstone rule needs to look at -
# what is above a pressure plate, what is in front of a piston. Both are gathered
# by the browser, because gathering the world is the adapter's job and deciding
# what it means is this contract's.
#
# `window` is the caller's dust-flood array, and it comes back out beside the
# result because the language gives an array exactly one owner: a browser holds a
# single `Uint32Array` for the whole circuit and passes the same object in on every
# tick, so the second element is the array it already has.
def tick(
  +state: Circuit, +emits: List<&2, Redstone.Emission>, +samples: List<&2, Redstone.Sample>,
  window: Grid.Flood, grid: Array<U32>
) -> Stepped & Array<U32>:
  Circuit{+core, +timers, +machines} = state

  # The machines read the circuit as it stood at the top of the tick and decide.
  # Their emissions are known immediately, so they join what the timed components
  # will read on this same tick.
  +machines_step = Machines.step(machines, emits, samples)
  +next_machines = Machines.stepped_machines(machines_step)
  +edits = Machines.stepped_edits(machines_step)

  # The timed components read the core against the machines' fresh emissions, and
  # `Clock.tick` settles the dust, torches and lamps together with their counters
  # - the per-tick order this contract is built around.
  +with_machines = Redstone.append_emits(Machines.outputs(next_machines), emits)
  tick.pack(
    next_machines,
    edits,
    Clock.tick_with(core, timers, with_machines, window, grid))
