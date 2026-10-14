import assert from "node:assert/strict";
import { RedstoneAll as All, Redstone } from "../web/bend-modules.js";
import {
  createRedstone,
  tickRedstone,
  wirePowerAt,
  torchLitAt,
  lampLitAt,
  pistonExtendedAt,
  wireColor,
} from "../web/redstone.js";

const EMPTY = { $: "Nil" };
function list(values) {
  let node = EMPTY;
  for (let index = values.length - 1; index >= 0; index -= 1) {
    node = { $: "Con", head: values[index], tail: node };
  }
  return node;
}

// A world the adapter can read: a plain function from cell to block id, with the
// origin reachable so nothing is "inside" by accident.
function world(blocks = {}) {
  return {
    blockAt: (x, y, z) => blocks[`${x},${y},${z}`] ?? 0,
    inside: (x, y, z) => x >= 0 && y >= 0 && z >= 0 && x < 64 && y < 32 && z < 64,
  };
}
const place = (blocks, x, y, z, id) => ({ ...blocks, [`${x},${y},${z}`]: id });

// --- the adapter is a pass-through, not a second implementation -------------
{
  const state = createRedstone();
  assert.equal(state.ids.wire, 28);
  assert.equal(state.ids.head, 38);
  assert.equal(state.ids.stickyPiston, 39);

  // A circuit placed through the contract is visible through the adapter.
  state.circuit = All.place_lamp(state.circuit, 3n, 0n, 0n);
  state.circuit = All.place_lever(state.circuit, 1n, 0n, 0n, true);
  state.circuit = All.place_wire(state.circuit, 2n, 0n, 0n);
  const view = world();
  for (let tick = 0; tick < 2; tick += 1) tickRedstone(state, view.blockAt, view.inside);

  assert.equal(lampLitAt(state, 3, 0, 0), true, "the adapter reports the lamp the contract lit");
  assert.equal(wirePowerAt(state, 2, 0, 0), 15, "and the dust the contract powered");
  assert.equal(wirePowerAt(state, 9, 9, 9), 0, "and nothing where there is no circuit");

  // The adapter's answer equals the contract's answer, cell for cell.
  for (let x = 0; x < 6; x += 1) {
    assert.equal(
      wirePowerAt(state, x, 0, 0),
      Number(All.wire_power(state.circuit, BigInt(x), 0n, 0n)),
      `the adapter must not invent a power level at ${x}`,
    );
  }
}

// --- a torch the adapter reads back -----------------------------------------
{
  const state = createRedstone();
  state.circuit = All.place_torch(state.circuit, 2n, 1n, 0n);
  const view = world();
  tickRedstone(state, view.blockAt, view.inside);
  assert.equal(torchLitAt(state, 2, 1, 0), true, "an unpowered torch is lit");
  assert.equal(torchLitAt(state, 9, 9, 9), false, "and a cell with no torch is not");
}

// --- the adapter applies the world edits the machines asked for -------------
{
  const state = createRedstone();
  state.circuit = All.place_piston(state.circuit, 5n, 0n, 0n, All.face_east(), false);
  state.circuit = All.place_lever(state.circuit, 4n, 0n, 0n, false);
  state.circuit = All.flip_lever(state.circuit, 4n, 0n, 0n);
  const view = world();
  const edits = tickRedstone(state, view.blockAt, view.inside);

  assert.deepEqual(edits, [{ x: 6, y: 0, z: 0, value: 38 }], "the piston edit reaches the caller in Bend's own shape");
  assert.equal(pistonExtendedAt(state, 5, 0, 0), true, "and the piston is out");
}

// --- the samples the adapter gathers are the ones the rules ask about -------
// A pressure plate reads the cell above it, so a block there must press it. The
// adapter is the thing that supplies that fact, so this is where a wiring mistake
// between the two halves would show.
{
  const state = createRedstone();
  state.circuit = All.place_plate(state.circuit, 1n, 0n, 0n);
  const standing = world(place({}, 1, 1, 0, 1));
  tickRedstone(state, standing.blockAt, standing.inside);
  assert.equal(All.plate_is_pressed(state.circuit, 1n, 0n, 0n), true,
    "the adapter sampled the cell above the plate, so weight registers");

  const clear = world();
  const state2 = createRedstone();
  state2.circuit = All.place_plate(state2.circuit, 1n, 0n, 0n);
  tickRedstone(state2, clear.blockAt, clear.inside);
  assert.equal(All.plate_is_pressed(state2.circuit, 1n, 0n, 0n), false,
    "and an empty cell above it does not");
}

// A cell the world says is outside is not sampled, so a plate near the edge
// never reads a block that is not there.
{
  const state = createRedstone();
  state.circuit = All.place_plate(state.circuit, 0n, 0n, 0n);
  const edge = {
    blockAt: () => 1,
    inside: (x, y, z) => x >= 2,
  };
  const edits = tickRedstone(state, edge.blockAt, edge.inside);
  assert.deepEqual(edits, [], "nothing outside the world is sampled");
  assert.equal(All.plate_is_pressed(state.circuit, 0n, 0n, 0n), false,
    "so a plate on the edge is not pressed by a block that does not exist");
}

// --- the renderer reads the level, and the adapter only paints it -----------
{
  const state = createRedstone();
  let circuit = state.circuit;
  for (let index = 0n; index < 4n; index += 1n) circuit = All.place_wire(circuit, 1n + index, 0n, 0n);
  circuit = All.place_power_block(circuit, 0n, 0n, 0n);
  state.circuit = circuit;
  const view = world();
  tickRedstone(state, view.blockAt, view.inside);

  assert.equal(wirePowerAt(state, 1, 0, 0), 15);
  assert.equal(wirePowerAt(state, 4, 0, 0), 12, "the decay reaches the renderer unchanged");
  const lit = wireColor(state, state.ids, "#8c2f2f", "#ff4a3a", 1, 0, 0);
  const dim = wireColor(state, state.ids, "#8c2f2f", "#ff4a3a", 4, 0, 0);
  assert.equal(lit.power, 15);
  assert.equal(dim.power, 12);
  assert.notEqual(lit.color, dim.color, "a brighter cell really does paint brighter");
}

// --- a saved circuit comes back ---------------------------------------------
{
  const first = createRedstone();
  first.circuit = All.place_wire(first.circuit, 1n, 0n, 0n);
  first.circuit = All.place_power_block(first.circuit, 0n, 0n, 0n);
  const view = world();
  for (let tick = 0; tick < 2; tick += 1) tickRedstone(first, view.blockAt, view.inside);
  const before = wirePowerAt(first, 1, 0, 0);

  const restored = createRedstone(first.circuit);
  assert.equal(wirePowerAt(restored, 1, 0, 0), before, "a restored circuit answers the same");
  assert.equal(restored.ids.wire, 28, "and still knows its block ids");
}

// A circuit object of the wrong shape is refused rather than half-read.
{
  const bad = createRedstone({ $: "NotACircuit" });
  assert.equal(All.circuit_core(bad.circuit).wires?.$ ?? "Con", "Nil", "a bad save falls back to an empty circuit");
}

console.log("redstone adapter ok");
