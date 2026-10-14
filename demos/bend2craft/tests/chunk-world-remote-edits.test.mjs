import assert from "node:assert/strict";
import { createChunkedWorld } from "../web/chunk-world.js";

// A shared-world batch arrives with an edit log that already contains it. The
// world adopts the log and writes the cells of loaded chunks. Cells of chunks
// still in flight are kept and written over the reply when it lands, so a
// chunk next to flowing water (a batch every tick) still finishes loading.
const SIZE = 4;
const MAX_Y = 2;
const cells = SIZE * SIZE * MAX_Y;
const requests = [];
const world = createChunkedWorld({
  chunkSize: SIZE,
  maxY: MAX_Y,
  renderRadius: 1,
  loadBudget: 1,
  initialEdits: "log-0",
  generateChunk: () => new Array(cells).fill(1),
  requestChunk: (chunkX, chunkZ, edits, version) => requests.push({ chunkX, chunkZ, edits, version }),
  applyEdit: (edits, x, y, z, value) => `${edits}+${x},${y},${z}=${value}`,
});

const filled = () => new Uint8Array(cells).fill(1);
const lights = () => new Uint8Array(cells).fill(15);

// Hydrate the center chunk, leave two neighbours in flight.
world.loadAround(1, 1);
assert.equal(requests.length, 1);
assert.equal(world.hydrateChunk(0, 0, filled(), lights(), requests[0].version), true);
world.loadAround(1, 1);
world.loadAround(1, 1);
const inFlight = requests.slice(1);
assert.equal(inFlight.length, 2);
assert.equal(world.isLoaded(1, 1), true);
assert.equal(world.isLoaded(inFlight[0].chunkX * SIZE, inFlight[0].chunkZ * SIZE), false);

// One cell in the loaded chunk and one in the first in-flight chunk.
const touched = inFlight[0];
const remoteX = touched.chunkX * SIZE + 1;
const remoteZ = touched.chunkZ * SIZE + 1;
assert.equal(world.mergeEdits("log-1", [{ x: 2, y: 0, z: 2, value: 0 }], [{ x: remoteX, y: 1, z: remoteZ, value: 7 }]), true);
assert.equal(world.getEdits(), "log-1");
assert.equal(world.blockAt(2, 0, 2), 0);
// More batches while it is still in flight: the last value of a cell wins.
assert.equal(world.mergeEdits("log-2", [], [{ x: remoteX, y: 1, z: remoteZ, value: 0 }]), true);
assert.equal(world.mergeEdits("log-3", [], [{ x: remoteX, y: 0, z: remoteZ, value: 5 }]), true);

// The reply was generated from an older log; it lands with the late cells
// written on top, and nothing is requested again.
const before = requests.length;
assert.equal(world.hydrateChunk(touched.chunkX, touched.chunkZ, filled(), lights(), touched.version), true);
assert.equal(world.blockAt(remoteX, 0, remoteZ), 5);
assert.equal(world.blockAt(remoteX, 1, remoteZ), 0);
assert.equal(world.blockAt(remoteX + 1, 0, remoteZ), 1, "the rest of the reply is kept");
const other = inFlight[1];
assert.equal(world.hydrateChunk(other.chunkX, other.chunkZ, filled(), lights(), other.version), true);
world.loadAround(1, 1);
assert.equal(requests.slice(before).some((r) => r.chunkX === touched.chunkX && r.chunkZ === touched.chunkZ), false);
assert.equal(world.getEdits(), "log-3", "late cells are already in the log");

// Invalid cells refuse the whole merge and keep the old log.
assert.equal(world.mergeEdits("log-4", [{ x: 0, y: MAX_Y, z: 0, value: 1 }]), false);
assert.equal(world.getEdits(), "log-3");
// A batch with no loaded cells only adopts the log.
assert.equal(world.mergeEdits("log-5", []), true);
assert.equal(world.getEdits(), "log-5");

// A batch goes to applyEdits once instead of applyEdit per cell.
const logged = [];
const batchWorld = createChunkedWorld({
  chunkSize: SIZE,
  maxY: MAX_Y,
  renderRadius: 0,
  initialEdits: "log",
  generateChunk: () => new Array(cells).fill(1),
  applyEdit: (edits, x, y, z, value) => { logged.push("one"); return `${edits}+${x},${y},${z}=${value}`; },
  applyEdits: (edits, changes) => { logged.push(`batch:${changes.length}`); return `${edits}+${changes.length}`; },
});
batchWorld.loadAround(0, 0);
assert.equal(batchWorld.setBlocks([{ x: 0, y: 0, z: 0, value: 0 }, { x: 1, y: 0, z: 0, value: 0 }]), true);
assert.deepEqual(logged, ["batch:2"]);
assert.equal(batchWorld.getEdits(), "log+2");
assert.equal(batchWorld.blockAt(1, 0, 0), 0);
assert.equal(batchWorld.setBlock(2, 0, 0, 0), true);
assert.deepEqual(logged, ["batch:2", "one"], "a single edit keeps applyEdit");

console.log("chunk world remote edits ok");
