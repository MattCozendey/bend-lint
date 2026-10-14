import assert from "node:assert/strict";
import { Redstone, RedstoneMachines as Machines } from "../web/bend-modules.js";

const EMPTY = { $: "Nil" };
function list(values) {
  let node = EMPTY;
  for (let index = values.length - 1; index >= 0; index -= 1) {
    node = { $: "Con", head: values[index], tail: node };
  }
  return node;
}
const heads = (node) => {
  const out = [];
  for (let cursor = node; cursor?.$ === "Con"; cursor = cursor.tail) out.push(cursor.head);
  return out;
};
const plain = (edit) => ({ x: Number(edit.x), y: Number(edit.y), z: Number(edit.z), block: Number(edit.block) });
// The edits are a set the browser applies wholesale; nothing downstream depends on
// their order, so assertions compare them sorted.
const cells = (edits) => edits.map(plain).sort((a, b) => a.x - b.x || a.z - b.z || a.block - b.block);

// Drive the machines against a fixed circuit. `outputs` names the cells a
// component drove, so "powered" means a drive landing on the machine's own cell.
const powerAt = (x, y = 0n, z = 0n) => list([Redstone.emit(x, y, z)]);
const powered = powerAt(1n);
const dark = EMPTY;
function run(machines, emits, samples = EMPTY) {
  const stepped = Machines.step(machines, emits, samples);
  return [Machines.stepped_machines(stepped), heads(Machines.stepped_edits(stepped))];
}

// --- the door is edge driven, not level driven -------------------------------
{
  let machines = Machines.place_door(Machines.empty(), 1n, 0n, 0n);
  const [closed] = run(machines, dark);
  assert.equal(Machines.door_is_open(closed, 1n, 0n, 0n), false, "a door starts shut");

  // Held on for several ticks it must open once and stay open.
  let state = closed;
  for (let tick = 0; tick < 5; tick += 1) [state] = run(state, powered);
  assert.equal(Machines.door_is_open(state, 1n, 0n, 0n), true, "one rising edge opens it");

  [state] = run(state, powered);
  assert.equal(Machines.door_is_open(state, 1n, 0n, 0n), true, "power held on does not close it again");

  [state] = run(state, dark);
  assert.equal(Machines.door_is_open(state, 1n, 0n, 0n), true, "and it stays open while unpowered");

  // Dropping and re-applying the power is a new rising edge, so it moves again.
  [state] = run(state, powered);
  assert.equal(Machines.door_is_open(state, 1n, 0n, 0n), false, "a second rising edge closes it");
}

// The block id follows the state, and matches the ids the world already uses.
{
  let machines = Machines.place_door(Machines.empty(), 1n, 0n, 0n);
  const door = Machines.door_at(machines, 1n, 0n, 0n);
  assert.equal(Number(Machines.door_block(door)), 14, "closed is the world's existing block 14");
  const [opened] = run(machines, powered);
  assert.equal(Number(Machines.door_block(Machines.door_at(opened, 1n, 0n, 0n))), 15, "open is 15");
  assert.equal(Number(Machines.closed_door_block()), 14);
  assert.equal(Number(Machines.open_door_block()), 15);
}

// A cell with no door reads as shut rather than throwing the question away.
assert.equal(Machines.door_is_open(Machines.empty(), 9n, 9n, 9n), false);
assert.equal(Machines.plate_is_pressed(Machines.empty(), 9n, 9n, 9n), false);
assert.equal(Machines.rail_is_powered(Machines.empty(), 9n, 9n, 9n), false);
assert.equal(Machines.piston_is_extended(Machines.empty(), 9n, 9n, 9n), false);

// --- the plate answers a level, not an edge ---------------------------------
{
  let machines = Machines.place_plate(Machines.empty(), 1n, 0n, 0n);
  const standing = list([Redstone.sample(1n, 1n, 0n, 1)]);
  const [pressed] = run(machines, dark, standing);
  assert.equal(Machines.plate_is_pressed(pressed, 1n, 0n, 0n), true, "weight presses it");

  const [stillPressed] = run(pressed, dark, standing);
  assert.equal(Machines.plate_is_pressed(stillPressed, 1n, 0n, 0n), true, "and it stays pressed while stood on");

  const [released] = run(stillPressed, dark, EMPTY);
  assert.equal(Machines.plate_is_pressed(released, 1n, 0n, 0n), false, "stepping off releases it");
}

// Water and lava are not heavy enough to hold a plate down.
for (const [block, label] of [[0, "air"], [7, "water"], [21, "lava"]]) {
  const machines = Machines.place_plate(Machines.empty(), 1n, 0n, 0n);
  const [state] = run(machines, dark, list([Redstone.sample(1n, 1n, 0n, block)]));
  assert.equal(Machines.plate_is_pressed(state, 1n, 0n, 0n), false, `${label} does not press a plate`);
}

// A powered plate is a source, so dust running over it reads full power.
{
  let machines = Machines.place_plate(Machines.empty(), 1n, 0n, 0n);
  const [pressed] = run(machines, dark, list([Redstone.sample(1n, 1n, 0n, 5)]));
  const emits = Machines.outputs(pressed);
  assert.equal(Redstone.emits_power_at(emits, 1n, 1n, 0n), 15, "a pressed plate drives the block above it");
  const [released] = run(pressed, dark, EMPTY);
  assert.equal(Redstone.emits_power_at(Machines.outputs(released), 1n, 1n, 0n), 0, "and stops when released");
}

// --- the rail drives power one, not fifteen ----------------------------------
{
  let machines = Machines.place_rail(Machines.empty(), 1n, 0n, 0n);
  const [on] = run(machines, powered);
  assert.equal(Machines.rail_is_powered(on, 1n, 0n, 0n), true);
  const emits = Machines.outputs(on);
  assert.equal(Redstone.emits_power_at(emits, 1n, 1n, 0n), 1, "an activator rail drives power one");
  const [off] = run(on, dark);
  assert.equal(Redstone.emits_power_at(Machines.outputs(off), 1n, 1n, 0n), 0, "and nothing when unpowered");
}

// A door and a piston drive nothing into the circuit: they are read by the
// player and the physics, not by dust.
{
  let machines = Machines.place_door(Machines.empty(), 1n, 0n, 0n);
  machines = Machines.place_piston(machines, 4n, 0n, 0n, Machines.face_east(), false);
  const [opened] = run(machines, powered);
  assert.equal(Machines.door_is_open(opened, 1n, 0n, 0n), true);
  assert.deepEqual(heads(Machines.outputs(opened)), [], "neither emits into the circuit");
}

// --- the piston -------------------------------------------------------------
// A piston at (4, 0, 0) facing east: head at (5, 0, 0), shoves (6, 0, 0) into
// (7, 0, 0), which is the far cell for a two-cell push.
const pistonPower = powerAt(4n);
function pistonRun(machines, emits, samples, ticks = 1) {
  let state = machines;
  let edits = [];
  for (let tick = 0; tick < ticks; tick += 1) {
    const next = run(state, emits, samples);
    [state, edits] = next;
  }
  return [state, cells(edits)];
}

{
  let machines = Machines.place_piston(Machines.empty(), 4n, 0n, 0n, Machines.face_east(), false);

  // Nothing to push: the head and the two cells beyond are air.
  const [extended, edits] = pistonRun(machines, pistonPower, EMPTY);
  assert.equal(Machines.piston_is_extended(extended, 4n, 0n, 0n), true, "a rising edge extends it");
  assert.deepEqual(edits, [{ x: 5, y: 0, z: 0, block: 38 }], "and leaves a piston head in the cell ahead");

  // Holding the power fires it once, not once per tick.
  const [, heldEdits] = pistonRun(extended, pistonPower, EMPTY, 4);
  assert.deepEqual(heldEdits, [], "holding the power does not fire it again");

  // Releasing retracts.
  const [retracted, retractEdits] = pistonRun(extended, dark, EMPTY);
  assert.equal(Machines.piston_is_extended(retracted, 4n, 0n, 0n), false, "the falling edge retracts it");
  assert.deepEqual(retractEdits, [
    { x: 5, y: 0, z: 0, block: 0 },
    { x: 6, y: 0, z: 0, block: 37 },
  ], "the head is removed and a base is left where it was");
}

// A block in front is carried along, and air behind it is left air.
{
  const block = (x, id) => list([Redstone.sample(BigInt(x), 0n, 0n, id)]);
  const machines = Machines.place_piston(Machines.empty(), 4n, 0n, 0n, Machines.face_east(), false);
  const [, edits] = pistonRun(machines, pistonPower, block(6, 5));
  assert.deepEqual(edits, [
    { x: 5, y: 0, z: 0, block: 38 },
    { x: 6, y: 0, z: 0, block: 38 },
    { x: 7, y: 0, z: 0, block: 5 },
  ], "the block is carried, and both head cells are filled");
}

// A piston refuses rather than shoving what it can: a wall at the far cell means
// no extension at all, not a partial push.
{
  const block = (x, id) => list([Redstone.sample(BigInt(x), 0n, 0n, id)]);
  const machines = Machines.place_piston(Machines.empty(), 4n, 0n, 0n, Machines.face_east(), false);
  const [state, edits] = pistonRun(machines, pistonPower, block(7, 1));
  assert.equal(Machines.piston_is_extended(state, 4n, 0n, 0n), false, "a blocked push line refuses the whole extension");
  assert.deepEqual(edits, [], "and changes nothing");
}

// A piston cannot shove another piston.
{
  const samples = list([Redstone.sample(6n, 0n, 0n, Redstone.piston_block())]);
  const machines = Machines.place_piston(Machines.empty(), 4n, 0n, 0n, Machines.face_east(), false);
  const [state] = pistonRun(machines, pistonPower, samples);
  assert.equal(Machines.piston_is_extended(state, 4n, 0n, 0n), false, "a piston in the way stops it");
  assert.equal(Machines.immovable(Redstone.piston_block()), true);
  assert.equal(Machines.immovable(Redstone.head_block()), true);
  assert.equal(Machines.immovable(1), false);
}

// A sticky piston drags the block back on the way in.
{
  const block = (x, id) => list([Redstone.sample(BigInt(x), 0n, 0n, id)]);
  let machines = Machines.place_piston(Machines.empty(), 4n, 0n, 0n, Machines.face_east(), true);
  const [extended] = pistonRun(machines, pistonPower, block(6, 5));
  assert.equal(Machines.piston_is_extended(extended, 4n, 0n, 0n), true);
  const [, retractEdits] = pistonRun(extended, dark, block(7, 5));
  assert.deepEqual(retractEdits, [
    { x: 5, y: 0, z: 0, block: 5 },
    { x: 6, y: 0, z: 0, block: 39 },
  ], "a sticky piston pulls the block back and leaves a sticky base");
}

// A plain piston leaves the block where it was pushed.
{
  const block = (x, id) => list([Redstone.sample(BigInt(x), 0n, 0n, id)]);
  let machines = Machines.place_piston(Machines.empty(), 4n, 0n, 0n, Machines.face_east(), false);
  const [extended] = pistonRun(machines, pistonPower, block(6, 5));
  const [, retractEdits] = pistonRun(extended, dark, block(7, 5));
  assert.deepEqual(retractEdits, [
    { x: 5, y: 0, z: 0, block: 0 },
    { x: 6, y: 0, z: 0, block: 37 },
  ], "a plain piston leaves the pushed block alone");
}

// Every face maps to its own three cells, and the push line follows the face.
// The piston sits at (4, 4, 4) so all six faces have room to step. The faces that
// run off the origin are covered by the origin-plane case below.
for (const [face, label, head, tip, far] of [
  [Machines.face_east(), "east", [5, 4, 4], [6, 4, 4], [7, 4, 4]],
  [Machines.face_west(), "west", [3, 4, 4], [2, 4, 4], [1, 4, 4]],
  [Machines.face_south(), "south", [4, 4, 5], [4, 4, 6], [4, 4, 7]],
  [Machines.face_north(), "north", [4, 4, 3], [4, 4, 2], [4, 4, 1]],
  [Machines.face_up(), "up", [4, 5, 4], [4, 6, 4], [4, 7, 4]],
  [Machines.face_down(), "down", [4, 3, 4], [4, 2, 4], [4, 1, 4]],
]) {
  const samples = list([Redstone.sample(BigInt(tip[0]), BigInt(tip[1]), BigInt(tip[2]), 5)]);
  const machines = Machines.place_piston(Machines.empty(), 4n, 4n, 4n, face, false);
  const [, edits] = pistonRun(machines, powerAt(4n, 4n, 4n), samples);
  assert.deepEqual(
    edits,
    cells([
      { x: head[0], y: head[1], z: head[2], block: 38 },
      { x: tip[0], y: tip[1], z: tip[2], block: 38 },
      { x: far[0], y: far[1], z: far[2], block: 5 },
    ]),
    `a piston facing ${label} pushes along its own axis`,
  );
}

// A piston facing away from the origin: `Nat.sub` saturates at zero, so its head
// cell is its own cell. It must refuse rather than extend into itself.
for (const [face, label] of [
  [Machines.face_west(), "west"],
  [Machines.face_north(), "north"],
  [Machines.face_down(), "down"],
]) {
  const machines = Machines.place_piston(Machines.empty(), 0n, 0n, 0n, face, false);
  const [state, edits] = pistonRun(machines, powerAt(0n), EMPTY);
  assert.equal(Machines.piston_is_extended(state, 0n, 0n, 0n), false, `a ${label} piston on the origin refuses`);
  assert.deepEqual(edits, [], `a ${label} piston on the origin shoves nothing`);
}

// --- breaking a machine removes it -------------------------------------------
{
  let machines = Machines.place_door(Machines.empty(), 1n, 0n, 0n);
  machines = Machines.place_plate(machines, 2n, 0n, 0n);
  machines = Machines.place_rail(machines, 3n, 0n, 0n);
  machines = Machines.place_piston(machines, 4n, 0n, 0n, Machines.face_east(), false);
  const [state] = run(Machines.drop_machines(machines, 2n, 0n, 0n), dark);
  assert.equal(Machines.plate_is_pressed(state, 2n, 0n, 0n), false, "the plate is gone");
  assert.equal(Machines.door_is_open(state, 1n, 0n, 0n), false, "the door is gone");
  assert.equal(Machines.rail_is_powered(state, 3n, 0n, 0n), false, "the rail is gone");
  assert.equal(Machines.piston_is_extended(state, 4n, 0n, 0n), false, "the piston is gone");
}

// Placing twice does not stack a second copy.
{
  let machines = Machines.place_door(Machines.empty(), 1n, 0n, 0n);
  machines = Machines.place_door(machines, 1n, 0n, 0n);
  const [state] = run(machines, powered);
  assert.equal(Machines.door_is_open(state, 1n, 0n, 0n), true);
  // One door, not two: the second placement was refused, so one rising edge moved it.
  const [again] = run(state, dark);
  assert.equal(Machines.door_is_open(again, 1n, 0n, 0n), true);
}

console.log("bend redstone machines ok");
