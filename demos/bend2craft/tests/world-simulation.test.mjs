import assert from "node:assert/strict";
import Simulation from "../world/simulation.bend";
import { createWorldSimulation, restoreSimulationState } from "../web/world-simulation.js";

// A small flat world: stone below y = 5, grass at y = 5, air above.
function flatWorld() {
  const cells = new Map();
  const pins = new Set();
  const writes = [];
  const base = (y) => (y < 5 ? 1 : y === 5 ? 3 : 0);
  return {
    writes,
    pins,
    blockAt: (x, y, z) => cells.get(`${x},${y},${z}`) ?? base(y),
    inside: (x, y, z) => Number.isInteger(x) && Number.isInteger(y) && Number.isInteger(z) && y >= 0 && y < 20,
    isActive: () => true,
    setBlocks(changes) {
      for (const change of changes) {
        cells.set(`${change.x},${change.y},${change.z}`, change.value);
        writes.push(change);
      }
    },
    pinChunk: (x, z) => pins.add(`${x},${z}`),
    unpinChunk: (x, z) => pins.delete(`${x},${z}`),
  };
}

const world = flatWorld();
const sim = createWorldSimulation({ seed: 1337n, chunkSize: 16, world });
sim.pinStored();
assert.ok(world.pins.size >= 1, "the village chunk is pinned");

// Farming: till grass, plant, grow, harvest.
assert.equal(sim.till(40, 5, 40), true);
assert.equal(world.blockAt(40, 5, 40), 20);
assert.equal(sim.till(40, 4, 40), false, "stone does not till");
assert.ok(world.pins.has("2,2"), "a plot pins its chunk");
assert.equal(sim.plant(40, 6, 40), true);
assert.equal(world.blockAt(40, 6, 40), 16);
assert.equal(sim.plant(40, 6, 40), false, "one crop per cell");
assert.equal(sim.plant(41, 6, 41), false, "seeds need farmland below");
assert.deepEqual(sim.cropViews().map((crop) => [crop.x, crop.y, crop.z]), [[40, 6, 40]]);
assert.equal(sim.harvest(40, 6, 40).ok, false, "a young crop does not harvest");

// Water: a source spreads over ticks; a bucket takes the source back.
assert.equal(sim.seedFluid(7, 30, 6, 30), true);
assert.equal(world.blockAt(30, 6, 30), 7);
assert.equal(sim.seedFluid(7, 30, 6, 30), false, "only into air");
let spread = 0;
for (let step = 0; step < 6; step += 1) spread += sim.tick().filter((change) => change.value === 7).length;
assert.ok(spread > 0, "water flows to neighbouring cells");
assert.equal(sim.removeFluid(30, 6, 30), 7);
assert.equal(world.blockAt(30, 6, 30), 0);
assert.equal(sim.removeFluid(30, 4, 30), 0, "stone holds no fluid");

// Crops grow with ticks on hydrated farmland until they can be harvested.
const farm = flatWorld();
const field = createWorldSimulation({ seed: 1337n, chunkSize: 16, world: farm });
field.till(10, 5, 10);
field.plant(10, 6, 10);
assert.equal(field.seedFluid(7, 12, 6, 10), true, "water beside the field hydrates it");
let ripe = false;
for (let step = 0; step < 4000 && !ripe; step += 1) {
  field.tick();
  field.syncBlocks();
  ripe = farm.blockAt(10, 6, 10) === 19;
}
assert.ok(ripe, "the crop ripens");
const refused = field.harvest(10, 6, 10, () => false);
assert.equal(refused.ok, false);
assert.equal(refused.refused, true, "no room: the crop stays");
assert.equal(farm.blockAt(10, 6, 10), 19);
const harvested = field.harvest(10, 6, 10);
assert.equal(harvested.ok, true);
assert.equal(harvested.wheat, 1);
assert.equal(farm.blockAt(10, 6, 10), 0);
assert.deepEqual(field.cropViews(), []);

// Mining a crop or plot forgets it.
field.plant(10, 6, 10);
field.blockChanged(10, 6, 10, 16, 0);
assert.deepEqual(field.cropViews(), []);
field.blockChanged(10, 5, 10, 20, 0);
assert.deepEqual(field.farmlandViews(), []);

// Fire burns out on its own.
assert.equal(sim.ignite(50, 6, 50), true);
assert.equal(world.blockAt(50, 6, 50), 24);
let burnedOut = false;
for (let step = 0; step < 400 && !burnedOut; step += 1) {
  sim.tick();
  burnedOut = world.blockAt(50, 6, 50) === 0;
}
assert.ok(burnedOut, "fire burns out");

// The state round-trips through a save.
const restored = restoreSimulationState(JSON.parse(JSON.stringify(field.state(), (_k, v) => (typeof v === "bigint" ? { __big: String(v) } : v)), (_k, v) => (v && typeof v === "object" && typeof v.__big === "string" ? BigInt(v.__big) : v)));
assert.equal(Number(Simulation.time(restored.simulation)), Number(Simulation.time(field.simulation)));

console.log("world simulation ok");
