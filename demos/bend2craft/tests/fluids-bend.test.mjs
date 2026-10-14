import assert from "node:assert/strict";
import Fluids from "../world/fluids.bend";

function listValues(list) {
  const values = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) values.push(node.head);
  return values;
}

function sampleList(values) {
  let list = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index -= 1) {
    list = { $: "Con", head: values[index], tail: list };
  }
  return list;
}

const openBelow = sampleList([
  Fluids.sample(2n, 2n, 2n, 0),
]);
const falling = listValues(Fluids.spread(Fluids.flow(2n, 3n, 2n, 8), openBelow));
assert.deepEqual(falling, [{ $: "Flow", x: 2n, y: 2n, z: 2n, level: 8, source: false, block: 7 }]);
const lavaFalling = listValues(Fluids.spread(Fluids.lava_flow(2n, 3n, 2n, 8), openBelow));
assert.deepEqual(lavaFalling, [{ $: "Flow", x: 2n, y: 2n, z: 2n, level: 8, source: false, block: 21 }]);

const blockedBelow = sampleList([
  Fluids.sample(2n, 2n, 2n, 1),
  Fluids.sample(1n, 3n, 2n, 0),
  Fluids.sample(3n, 3n, 2n, 0),
  Fluids.sample(2n, 3n, 1n, 0),
  Fluids.sample(2n, 3n, 3n, 0),
]);
const spread = listValues(Fluids.spread(Fluids.flow(2n, 3n, 2n, 3), blockedBelow));
assert.deepEqual(spread, [
  { $: "Flow", x: 1n, y: 3n, z: 2n, level: 2, source: false, block: 7 },
  { $: "Flow", x: 3n, y: 3n, z: 2n, level: 2, source: false, block: 7 },
  { $: "Flow", x: 2n, y: 3n, z: 1n, level: 2, source: false, block: 7 },
  { $: "Flow", x: 2n, y: 3n, z: 3n, level: 2, source: false, block: 7 },
]);

const dry = listValues(Fluids.spread(Fluids.flow(2n, 3n, 2n, 1), blockedBelow));
assert.deepEqual(dry, []);

let state = Fluids.seed(Fluids.empty(), 2n, 3n, 2n, 3);
const seeded = state;
state = Fluids.tick(state, blockedBelow);
const stateFlows = listValues(Fluids.state_flows(state));
assert.equal(stateFlows.length, 5);
assert.ok(stateFlows.some((value) => value.$ === "Flow"
  && value.x === 2n && value.y === 3n && value.z === 2n
  && Number(value.level) === 3));
const filled = listValues(Fluids.changes(seeded, state));
assert.equal(filled.length, 4);
assert.ok(filled.every((value) => value.block === 7));
state = Fluids.remove(state, 2n, 3n, 2n);
assert.ok(!listValues(Fluids.state_flows(state)).some((value) => (
  value.x === 2n && value.y === 3n && value.z === 2n
)));
const flowing = state;
state = Fluids.tick(state, blockedBelow);
assert.equal(listValues(Fluids.state_flows(state)).length, 0);
const drained = listValues(Fluids.changes(flowing, state));
assert.equal(drained.length, 4);
assert.ok(drained.every((value) => value.block === 0));

const lavaState = Fluids.seed_lava(Fluids.empty(), 2n, 3n, 2n, 8);
const lavaChanges = listValues(Fluids.changes(Fluids.empty(), lavaState));
assert.deepEqual(lavaChanges, [{ $: "Edit", x: 2n, y: 3n, z: 2n, block: 21 }]);
const lavaContactSamples = sampleList([
  Fluids.sample(1n, 3n, 2n, 7),
]);
const lavaReactions = listValues(Fluids.reactions(lavaState, lavaContactSamples));
assert.deepEqual(lavaReactions, [{ $: "Edit", x: 2n, y: 3n, z: 2n, block: 23 }]);
assert.equal(listValues(Fluids.state_flows(Fluids.react(lavaState, lavaContactSamples))).length, 0);
const flowingLavaState = {
  $: "State",
  flows: { $: "Con", head: Fluids.lava_flow(2n, 3n, 2n, 2), tail: { $: "Nil" } },
};
assert.deepEqual(listValues(Fluids.reactions(flowingLavaState, lavaContactSamples)), [
  { $: "Edit", x: 2n, y: 3n, z: 2n, block: 22 },
]);

let manyFlows = Fluids.empty();
for (let index = 0; index < 40; index += 1) {
  manyFlows = Fluids.seed(manyFlows, BigInt(index), 1n, 1n, 8);
}
manyFlows = Fluids.remove(manyFlows, 39n, 1n, 1n);
assert.equal(listValues(Fluids.state_flows(manyFlows)).length, 39);
const currentFlows = { $: "Con", head: Fluids.flow(2n, 1n, 3n, 8), tail: { $: "Nil" } };
const current = Fluids.current(currentFlows, 3.5, 1.1, 3.0);
assert.ok(Number(Fluids.current_x(current)) > 0);
assert.ok(Math.abs(Number(Fluids.current_z(current))) < 0.01);

// --- a pool holds still instead of ratcheting itself away ---------------------
// A pool is a source and the rings around it, each ring one level weaker than
// the ring inside it. Every cell has a stronger neighbour, so all of them are
// still fed and the pool neither shrinks nor changes shape. Taking the level a
// neighbour offered instead of the cell's own ratcheted the whole pool down a
// step per tick until it drained.
// A pool on a flat floor: a stone floor at y = -1 and open air above it, with
// the sample window the browser gathers (the cell below each flow, the four
// beside it, and the cell above it).
const POOL = 17;
const floorCells = new Map();
for (let z = 0; z < POOL; z += 1) {
  for (let x = 0; x < POOL; x += 1) {
    floorCells.set(`${x},-1,${z}`, 1);
    for (let y = 0; y < 3; y += 1) floorCells.set(`${x},${y},${z}`, 0);
  }
}
floorCells.set("8,0,8", 7);

function windowOf(flows) {
  const seen = new Map();
  for (const flow of flows) {
    for (const [dx, dy, dz] of [[0, -1, 0], [0, 1, 0], [-1, 0, 0], [1, 0, 0], [0, 0, -1], [0, 0, 1]]) {
      const x = Number(flow.x) + dx;
      const y = Number(flow.y) + dy;
      const z = Number(flow.z) + dz;
      if (y < 0 || x < 0 || z < 0) continue;
      const sampleKey = `${x},${y},${z}`;
      if (!seen.has(sampleKey)) seen.set(sampleKey, floorCells.has(sampleKey) ? floorCells.get(sampleKey) : 1);
    }
  }
  return sampleList([...seen].map(([sampleKey, block]) => {
    const [x, y, z] = sampleKey.split(",").map(Number);
    return Fluids.sample(BigInt(x), BigInt(y), BigInt(z), block);
  }));
}

function step(current) {
  const flows = listValues(Fluids.state_flows(current));
  const next = Fluids.tick(current, windowOf(flows));
  for (const edit of listValues(Fluids.changes(current, next))) {
    const cellKey = `${Number(edit.x)},${Number(edit.y)},${Number(edit.z)}`;
    if (Number(edit.block) === 0) floorCells.delete(cellKey);
    else floorCells.set(cellKey, Number(edit.block));
  }
  return next;
}

let pool = Fluids.seed(Fluids.empty(), 8n, 0n, 8n, 8);
for (let pass = 0; pass < 9; pass += 1) pool = step(pool);
const steady = listValues(Fluids.state_flows(pool))
  .map((flow) => `${Number(flow.x)},${Number(flow.y)},${Number(flow.z)}:${Number(flow.level)}`)
  .sort();
assert.ok(steady.length > 20, `the pool should have spread, got ${steady.length} cells`);
const beforeSteady = Fluids.changes(pool, Fluids.tick(pool, windowOf(listValues(Fluids.state_flows(pool)))));
assert.deepEqual(
  listValues(beforeSteady),
  [],
  "a pool that has reached its full width tells the world nothing on the next tick",
);
const afterSteady = listValues(Fluids.state_flows(step(pool)))
  .map((flow) => `${Number(flow.x)},${Number(flow.y)},${Number(flow.z)}:${Number(flow.level)}`)
  .sort();
assert.deepEqual(afterSteady, steady, "a settled pool keeps its shape and its levels");

// --- a flow with nothing feeding it dries up ----------------------------------
// The other half of the same rule: a stray flow with no source, no stronger
// neighbour and no water above it has nothing holding it there, and the world
// must be told to clear the cell.
const stray = { $: "State", flows: { $: "Con", head: Fluids.flow(5n, 0n, 5n, 3), tail: { $: "Nil" } } };
const straySamples = sampleList([
  Fluids.sample(4n, 0n, 5n, 0),
  Fluids.sample(6n, 0n, 5n, 0),
  Fluids.sample(5n, 0n, 4n, 0),
  Fluids.sample(5n, 0n, 6n, 0),
]);
const strayAfter = Fluids.tick(stray, straySamples);
assert.ok(
  !listValues(Fluids.state_flows(strayAfter)).some((flow) => (
    flow.x === 5n && flow.y === 0n && flow.z === 5n
  )),
  "an unfed flow is gone from the field",
);
const strayCleared = listValues(Fluids.changes(stray, strayAfter))
  .filter((edit) => edit.x === 5n && edit.y === 0n && edit.z === 5n);
assert.deepEqual(strayCleared, [{ $: "Edit", x: 5n, y: 0n, z: 5n, block: 0 }], "and the world is told to clear it");
assert.equal(
  listValues(Fluids.state_flows(Fluids.tick(strayAfter, straySamples))).length,
  0,
  "the cells it reached dry up on the next tick",
);

// --- every flow is advanced, not the first sixty-four ------------------------
// `tick` used to bound its work at 64 flows and drop the rest, so a field wider
// than that lost cells every tick and the world cleared them.
let wide = Fluids.empty();
const wideCells = new Map();
for (let z = 0; z < 12; z += 1) {
  for (let x = 0; x < 12; x += 1) {
    wideCells.set(`${x},-1,${z}`, 1);
    for (let y = 0; y < 3; y += 1) wideCells.set(`${x},${y},${z}`, 0);
  }
}
for (let index = 0; index < 100; index += 1) {
  const x = index % 10;
  const z = Math.floor(index / 10);
  wideCells.set(`${x},0,${z}`, 7);
  wide = Fluids.seed(wide, BigInt(x), 0n, BigInt(z), 8);
}
const wideFlows = listValues(Fluids.state_flows(wide));
assert.ok(wideFlows.length > 64, "the wide field must be past the old 64-flow bound");
const wideSamples = new Map();
for (const flow of wideFlows) {
  for (const [dx, dy, dz] of [[0, -1, 0], [0, 1, 0], [-1, 0, 0], [1, 0, 0], [0, 0, -1], [0, 0, 1]]) {
    const x = Number(flow.x) + dx;
    const y = Number(flow.y) + dy;
    const z = Number(flow.z) + dz;
    if (y < 0 || x < 0 || z < 0) continue;
    const sampleKey = `${x},${y},${z}`;
    if (!wideSamples.has(sampleKey)) wideSamples.set(sampleKey, wideCells.has(sampleKey) ? wideCells.get(sampleKey) : 1);
  }
}
const wideSampleList = sampleList([...wideSamples].map(([sampleKey, block]) => {
  const [x, y, z] = sampleKey.split(",").map(Number);
  return Fluids.sample(BigInt(x), BigInt(y), BigInt(z), block);
}));
const wideAfter = Fluids.tick(wide, wideSampleList);
const wideAfterKeys = new Set(listValues(Fluids.state_flows(wideAfter)).map((entry) => `${entry.x},${entry.y},${entry.z}`));
const dropped = wideFlows.filter((entry) => !wideAfterKeys.has(`${entry.x},${entry.y},${entry.z}`));
assert.deepEqual(dropped, [], "a tick must not drop flows it did not get to");

// --- a falling column feeds what it lands on ----------------------------------
// Water that has fallen onto a floor spreads there, so the cell it landed in is
// fed by the water above it even when nothing stronger stands beside it.
const fallingInto = { $: "State", flows: {
  $: "Con",
  head: Fluids.flow(5n, 2n, 5n, 8),
  tail: {
    $: "Con",
    head: Fluids.flow(5n, 1n, 5n, 8),
    tail: { $: "Nil" },
  },
} };
const landedSamples = sampleList([
  Fluids.sample(5n, 1n, 5n, 7),
  Fluids.sample(5n, 2n, 5n, 7),
  Fluids.sample(5n, 0n, 5n, 1),
  Fluids.sample(5n, 1n, 4n, 0),
  Fluids.sample(5n, 1n, 6n, 0),
  Fluids.sample(4n, 1n, 5n, 0),
  Fluids.sample(6n, 1n, 5n, 0),
]);
const landed = listValues(Fluids.state_flows(Fluids.tick(fallingInto, landedSamples)));
assert.ok(
  landed.some((flow) => flow.x === 5n && flow.y === 1n && flow.z === 5n),
  "the cell a column lands in stays",
);
assert.ok(
  landed.some((flow) => flow.x === 5n && flow.y === 1n && flow.z === 4n),
  "and spreads there",
);

console.log("bend fluids ok");
