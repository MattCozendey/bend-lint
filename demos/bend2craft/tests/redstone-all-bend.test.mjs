import assert from "node:assert/strict";
import { Redstone, RedstoneAll as All, RedstoneGrid } from "../web/bend-modules.js";

const EMPTY = { $: "Nil" };
// The dust flood runs on a window the size of the circuit, and the array is the
// caller's own: the contract writes its reached marks into it in place. One buffer
// for the whole file, reset whenever the window moves, is what the browser does, so
// this is the real path rather than a fresh window per tick.
const buffer = { grid: new Uint32Array(64), key: null };
function windowFor(core) {
  const window = RedstoneGrid.flood_of_state(core);
  const cells = Number(RedstoneGrid.flood_cells(window));
  if (buffer.grid.length < cells) buffer.grid = new Uint32Array(cells);
  const key = `${window.ox},${window.oy},${window.oz},${window.width},${window.depth},${window.height}`;
  if (buffer.key !== key) {
    buffer.grid.fill(0);
    buffer.key = key;
  }
  return { window, grid: buffer.grid };
}
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

// The web ticker's whole loop: gather what the rules need to look at, tick once,
// then read the fresh states and the world edits back out. Nothing here reaches
// into a sub-module.
function run(circuit, samples = EMPTY) {
  const emits = Redstone.emits(All.circuit_core(circuit), EMPTY);
  const { window, grid } = windowFor(All.circuit_core(circuit));
  const stepped = All.tick(circuit, emits, samples, window, grid).fst;
  return {
    circuit: All.stepped_circuit(stepped),
    edits: heads(All.stepped_edits(stepped))
      .map((edit) => ({ x: Number(edit.x), y: Number(edit.y), z: Number(edit.z), block: Number(edit.block) }))
      .sort((a, b) => a.x - b.x || a.z - b.z),
  };
}

// --- the three halves are one circuit ---------------------------------------
// Lever at (1, 0, 0) -> dust at (2, 0, 0) -> repeater at (3, 0, 0) facing east
// -> lamp at (4, 0, 0). The repeater's delay has to survive the whole chain.
{
  let circuit = All.empty();
  circuit = All.place_lever(circuit, 1n, 0n, 0n, false);
  circuit = All.place_wire(circuit, 2n, 0n, 0n);
  circuit = All.place_repeater(circuit, 3n, 0n, 0n, All.dir_east(), 0);
  circuit = All.place_lamp(circuit, 4n, 0n, 0n);

  let result = run(circuit);
  circuit = result.circuit;
  assert.equal(All.lamp_lit(circuit, 4n, 0n, 0n), false, "the lamp starts dark");

  circuit = All.flip_lever(circuit, 1n, 0n, 0n);
  for (let tick = 1; tick <= 2; tick += 1) {
    result = run(circuit);
    circuit = result.circuit;
    assert.equal(Number(All.repeater_out(circuit, 3n, 0n, 0n)), 0, `the repeater is still waiting on tick ${tick}`);
    assert.equal(All.lamp_lit(circuit, 4n, 0n, 0n), false, `and the lamp stays dark on tick ${tick}`);
  }

  result = run(circuit);
  circuit = result.circuit;
  assert.equal(Number(All.repeater_out(circuit, 3n, 0n, 0n)), 15, "the repeater drives on the third tick");
  assert.equal(All.lamp_lit(circuit, 4n, 0n, 0n), true, "and the lamp past it lights");

  // Releasing walks the signal back down the same delay: the lever edge takes a
  // tick to reach the repeater's back, then the repeater's own delay follows.
  circuit = All.flip_lever(circuit, 1n, 0n, 0n);
  result = run(circuit);
  circuit = result.circuit;
  assert.equal(Number(All.repeater_out(circuit, 3n, 0n, 0n)), 15, "and holds on for the delay");
  for (let tick = 0; tick < 4; tick += 1) circuit = run(circuit).circuit;
  assert.equal(Number(All.repeater_out(circuit, 3n, 0n, 0n)), 0, "then drops");
  assert.equal(All.lamp_lit(circuit, 4n, 0n, 0n), false, "and the lamp goes out");
}

// --- a machine driven through the whole chain -------------------------------
// A pressure plate drives a dust line, which drives a lamp, and the world's edits
// the machines want come back to the caller in the same tick.
{
  let circuit = All.empty();
  circuit = All.place_plate(circuit, 1n, 0n, 0n);
  circuit = All.place_wire(circuit, 1n, 1n, 0n);
  circuit = All.place_lamp(circuit, 2n, 1n, 0n);

  const standing = list([Redstone.sample(1n, 1n, 0n, 1)]);
  let result = run(circuit, standing);
  circuit = result.circuit;
  assert.equal(All.plate_is_pressed(circuit, 1n, 0n, 0n), true, "weight presses the plate");
  assert.equal(Number(All.wire_power(circuit, 1n, 1n, 0n)), 15, "the dust above it is powered through the entry point");
  assert.equal(All.lamp_lit(circuit, 2n, 1n, 0n), true, "and it lights the lamp");

  result = run(circuit, EMPTY);
  circuit = result.circuit;
  assert.equal(All.plate_is_pressed(circuit, 1n, 0n, 0n), false, "stepping off releases it");
  assert.equal(All.lamp_lit(circuit, 2n, 1n, 0n), false, "and the lamp goes out");
}

// --- a piston fired through the entry point returns its edits ---------------
{
  let circuit = All.empty();
  circuit = All.place_lever(circuit, 4n, 0n, 0n, false);
  circuit = All.place_piston(circuit, 5n, 0n, 0n, All.face_east(), false);
  circuit = All.flip_lever(circuit, 4n, 0n, 0n);

  const result = run(circuit);
  assert.deepEqual(result.edits, [{ x: 6, y: 0, z: 0, block: 38 }], "exactly the extension edit");
  assert.equal(All.piston_is_extended(result.circuit, 5n, 0n, 0n), true, "and the piston is out");
}

// --- a self-sustaining clock through the entry point ------------------------
{
  let circuit = All.empty();
  circuit = All.place_wire(circuit, 4n, 1n, 0n);
  circuit = All.place_wire(circuit, 3n, 1n, 0n);
  circuit = All.place_wire(circuit, 3n, 0n, 0n);
  circuit = All.place_wire(circuit, 5n, 0n, 0n);
  circuit = All.place_torch(circuit, 5n, 1n, 0n);
  circuit = All.place_repeater(circuit, 4n, 0n, 0n, All.dir_east(), 0);

  const trace = [];
  let state = circuit;
  for (let tick = 0; tick < 24; tick += 1) {
    const stepped = run(state);
    state = stepped.circuit;
    trace.push(Number(All.repeater_out(state, 4n, 0n, 0n)) ? 1 : 0);
  }
  const edges = [];
  for (let index = 1; index < trace.length; index += 1) {
    if (trace[index] === 1 && trace[index - 1] === 0) edges.push(index);
  }
  assert.ok(edges.length >= 3, "the clock keeps pulsing through the entry point");
  assert.deepEqual([...new Set(edges.slice(1).map((edge, i) => edge - edges[i]))], [7],
    "at the same rate the clock module measured");
}

// --- an empty circuit changes nothing ---------------------------------------
{
  const result = run(All.empty());
  assert.deepEqual(result.edits, [], "an empty circuit wants no world change");
  assert.equal(All.door_is_open(result.circuit, 0n, 0n, 0n), false);
  assert.equal(All.piston_is_extended(result.circuit, 0n, 0n, 0n), false);
  assert.equal(Number(All.wire_power(result.circuit, 0n, 0n, 0n)), 0);
  assert.equal(Number(All.repeater_out(result.circuit, 0n, 0n, 0n)), 0);
}

// --- a break clears the whole circuit ---------------------------------------
{
  // Lever at (0, 0, 0) powers (1, 0, 0); dust runs (1, 0, 0) -> (2, 0, 0); the
  // repeater at (3, 0, 0) reads its back at (2, 0, 0), which only the dust feeds.
  // Break that dust and the repeater's input is orphaned.
  let circuit = All.empty();
  circuit = All.place_lever(circuit, 0n, 0n, 0n, false);
  circuit = All.place_wire(circuit, 1n, 0n, 0n);
  circuit = All.place_wire(circuit, 2n, 0n, 0n);
  circuit = All.place_repeater(circuit, 3n, 0n, 0n, All.dir_east(), 0);
  circuit = All.place_lamp(circuit, 4n, 0n, 0n);
  circuit = All.flip_lever(circuit, 0n, 0n, 0n);
  for (let tick = 0; tick < 5; tick += 1) circuit = run(circuit).circuit;
  assert.equal(All.lamp_lit(circuit, 4n, 0n, 0n), true, "the circuit is lit");

  // Breaking the dust orphans the repeater's input, and the latched repeater
  // lets go after its own delay.
  circuit = All.remove_at(circuit, 2n, 0n, 0n);
  for (let tick = 0; tick < 4; tick += 1) circuit = run(circuit).circuit;
  assert.equal(All.lamp_lit(circuit, 4n, 0n, 0n), false, "the circuit clears once the repeater lets go");
}

console.log("bend redstone all ok");
