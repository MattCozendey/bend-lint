import assert from "node:assert/strict";
import {
  DEFAULT_CHUNK_SIZE,
  createChunkedWorld,
} from "../web/chunk-world.js";

assert.equal(DEFAULT_CHUNK_SIZE, 16);

let bulkCalls = 0;
const bulkWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 3,
  renderRadius: 1,
  generateChunk: () => {
    bulkCalls += 1;
    const chunk = new Array(4 * 4 * 3).fill(0);
    chunk[0] = 1;
    return chunk;
  },
});
bulkWorld.loadAround(6, 6);
assert.equal(bulkCalls, 9);
assert.equal(bulkWorld.blockAt(0, 0, 0), 1);
assert.equal(bulkWorld.blockAt(0, 1, 0), 0);

const fartherWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 1,
  renderRadius: 2,
  generateChunk: () => new Array(4 * 4).fill(0),
});
assert.equal(fartherWorld.loadAround(0, 0).activeChunks, 25);
assert.equal(fartherWorld.isActive(8, 0), true);
assert.equal(fartherWorld.isActive(12, 0), false);

let budgetCalls = 0;
const budgetWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 3,
  renderRadius: 1,
  loadBudget: 1,
  generateChunk: () => {
    budgetCalls += 1;
    return new Array(4 * 4 * 3).fill(0);
  },
});
const budgetFirst = budgetWorld.loadAround(6, 6);
assert.equal(budgetFirst.activeChunks, 1);
assert.equal(budgetFirst.pendingChunks, 8);
assert.equal(budgetWorld.blockAt(9, 0, 9), 0);
assert.equal(budgetCalls, 1);
for (let index = 0; index < 8; index += 1) budgetWorld.loadAround(6, 6);
assert.equal(budgetWorld.activeChunkCount(), 9);
assert.equal(budgetCalls, 9);

const asyncRequests = [];
const asyncWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 3,
  renderRadius: 0,
  requestChunk: (...request) => asyncRequests.push(request),
  generateChunk: () => new Array(4 * 4 * 3).fill(0),
});
const asyncFirst = asyncWorld.loadAround(0, 0);
assert.equal(asyncFirst.pendingChunks, 1);
assert.equal(asyncWorld.pendingChunkCount(), 1);
asyncWorld.hydrateChunk(0, 0, new Array(4 * 4 * 3).fill(0), new Array(4 * 4 * 3).fill(15), asyncRequests[0][3]);
assert.equal(asyncWorld.pendingChunkCount(), 0);

const swapRequests = [];
const swapWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 2,
  renderRadius: 0,
  requestChunk: (...request) => swapRequests.push(request),
  generateChunk: () => new Array(4 * 4 * 2).fill(0),
});
const swapFirst = swapWorld.loadAround(0, 0);
assert.equal(swapFirst.activeChunks, 0);
assert.equal(swapWorld.hydrateChunk(
  0,
  0,
  [1, ...new Array(4 * 4 * 2 - 1).fill(0)],
  new Array(4 * 4 * 2).fill(15),
  swapRequests[0][3],
), true);
assert.equal(swapWorld.loadAround(0, 0).activeChunks, 1);
const swapDestination = swapWorld.loadAround(4, 0);
assert.equal(swapDestination.pendingChunks, 1);
assert.equal(swapDestination.activeChunks, 1);
assert.equal(swapWorld.blockAt(0, 0, 0), 1);
assert.equal(swapWorld.hydrateChunk(
  1,
  0,
  [2, ...new Array(4 * 4 * 2 - 1).fill(0)],
  new Array(4 * 4 * 2).fill(15),
  swapRequests[1][3],
), true);
assert.equal(swapWorld.loadAround(4, 0).activeChunks, 1);
assert.equal(swapWorld.blockAt(0, 0, 0), 0);
assert.equal(swapWorld.blockAt(4, 0, 0), 2);

let pinnedCalls = 0;
const pinnedWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 3,
  renderRadius: 0,
  generateChunk: () => {
    pinnedCalls += 1;
    return new Array(4 * 4 * 3).fill(0);
  },
});
pinnedWorld.pinChunk(5, 5);
pinnedWorld.loadAround(6, 6);
assert.equal(pinnedWorld.pinnedChunkCount(), 1);
pinnedWorld.loadAround(30, 30);
assert.equal(pinnedWorld.activeChunkCount(), 1);
let pinnedSeen = [];
pinnedWorld.forEachPinnedChunk((x, z) => pinnedSeen.push(`${x},${z}`));
assert.deepEqual(pinnedSeen, ["5,5"]);
assert.ok(pinnedCalls >= 2);
pinnedWorld.unpinChunk(5, 5);
assert.equal(pinnedWorld.pinnedChunkCount(), 0);

let list = { $: "Nil" };
for (let index = 4 * 4 * 3 - 1; index >= 0; index -= 1) {
  list = { $: "Con", head: index === 0 ? 7 : 0, tail: list };
}
const listWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 3,
  generateChunk: () => list,
});
listWorld.loadAround(6, 6);
assert.equal(listWorld.blockAt(0, 0, 0), 7);
assert.equal(listWorld.blockAt(1, 0, 0), 0);

const generated = [];
const world = createChunkedWorld({
  chunkSize: 4,
  maxY: 3,
  renderRadius: 1,
  generateBlock: (x, y, z) => {
    generated.push(`${x},${y},${z}`);
    return y === 0 ? 1 : 0;
  },
});

assert.deepEqual(world.chunkCoordinates(0, 0), [0, 0]);
assert.deepEqual(world.chunkCoordinates(7, 8), [1, 2]);
assert.equal(world.inside(0, 0, 0), true);
assert.equal(world.inside(-1, 0, 0), true);
assert.equal(world.inside(0, 3, 0), false);

const firstLoad = world.loadAround(6, 6);
assert.equal(firstLoad.activeChunks, 9);
assert.equal(world.activeChunkCount(), 9);
assert.equal(world.blockAt(0, 0, 0), 1);
assert.equal(world.blockAt(4, 0, 0), 1);
assert.equal(world.isActive(0, 0), true);
assert.equal(world.isActive(12, 0), false);
assert.equal(generated.length, 9 * 4 * 4 * 3);
assert.equal(world.loadAround(6, 6).changed, false);

assert.equal(world.setBlock(5, 1, 2, 9), true);
assert.equal(world.blockAt(5, 1, 2), 9);
world.loadAround(30, 30);
assert.equal(world.activeChunkCount(), 9);
world.loadAround(6, 6);
assert.equal(world.blockAt(5, 1, 2), 9);
assert.equal(world.setBlock(-1, 1, 2, 9), true);
assert.equal(world.blockAt(-1, 1, 2), 9);
const patchedEdits = {
  $: "Con",
  head: { $: "Edit", x: 5n, y: 1n, z: 2n, block: 12 },
  tail: { $: "Nil" },
};
const generatedBeforePatch = generated.length;
assert.equal(world.patchEdits(patchedEdits, [{ x: 5, y: 1, z: 2, value: 12 }]), true);
assert.equal(world.activeChunkCount(), 9);
assert.equal(world.blockAt(5, 1, 2), 12);
assert.equal(generated.length, generatedBeforePatch);

let lightCalls = 0;
let dirtyCalls = 0;
let lightPatchCalls = 0;
const lightInvalidations = [];
const lightWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 3,
  renderRadius: 1,
  generateChunk: () => new Array(4 * 4 * 3).fill(0),
  generateLightChunk: () => {
    lightCalls += 1;
    return new Array(4 * 4 * 3).fill(lightCalls);
  },
  affectedLightCells: () => {
    dirtyCalls += 1;
    return { $: "Con", head: { $: "Cell", x: 5n, y: 1n, z: 2n }, tail: { $: "Nil" } };
  },
  generateLightCells: () => {
    lightPatchCalls += 1;
    return { $: "Con", head: { $: "LightCell", x: 5n, y: 1n, z: 2n, light: 18 }, tail: { $: "Nil" } };
  },
  invalidateLightFields: (...values) => lightInvalidations.push(values),
});
lightWorld.loadAround(6, 6);
assert.equal(lightCalls, 9);
const beforeLight = lightWorld.lightAt(5, 1, 2);
assert.ok(beforeLight > 0 && beforeLight < 18);
assert.equal(lightWorld.setBlock(5, 1, 2, 12), true);
assert.equal(lightCalls, 9);
assert.equal(dirtyCalls, 1);
assert.equal(lightPatchCalls, 1);
assert.deepEqual(lightInvalidations[0], [5, 1, 2, 0, 12]);
assert.equal(lightWorld.getLightDirtyCells().$, "Con");
assert.ok(lightWorld.lightAt(5, 1, 2) > beforeLight);
assert.equal(lightWorld.setBlock(5, 1, 3, 2), true);
assert.equal(lightCalls, 9);
assert.equal(dirtyCalls, 2);
assert.equal(lightPatchCalls, 2);
assert.equal(lightInvalidations.length, 2);
assert.deepEqual(lightInvalidations[1], [5, 1, 3, 0, 2]);
assert.equal(lightWorld.setBlock(5, 1, 2, 0), true);
assert.equal(lightCalls, 9);
assert.equal(dirtyCalls, 3);
assert.equal(lightPatchCalls, 3);
assert.deepEqual(lightInvalidations[2], [5, 1, 2, 12, 0]);
assert.equal(lightWorld.setBlock(5, 1, 1, 7), true);
assert.equal(dirtyCalls, 4);
assert.equal(lightPatchCalls, 4);
assert.deepEqual(lightInvalidations[3], [5, 1, 1, 0, 7]);
assert.equal(lightWorld.setBlock(5, 1, 1, 0), true);
assert.equal(dirtyCalls, 5);
assert.equal(lightPatchCalls, 5);
const patchBeforeBatch = lightPatchCalls;
assert.equal(lightWorld.setBlocks([
  { x: 5, y: 1, z: 0, value: 7 },
  { x: 5, y: 1, z: 1, value: 7 },
]), true);
assert.equal(lightPatchCalls, patchBeforeBatch + 1);
assert.equal(lightWorld.blockAt(5, 1, 0), 7);
assert.equal(lightWorld.blockAt(5, 1, 1), 7);
assert.equal(lightWorld.setBlock(5, 1, 2, 21), true);
assert.equal(lightPatchCalls, patchBeforeBatch + 2);
const opaquePatchBefore = lightPatchCalls;
const opaqueDirtyBefore = dirtyCalls;
const opaqueInvalidationsBefore = lightInvalidations.length;
assert.equal(lightWorld.setBlock(5, 1, 3, 0), true);
assert.equal(lightPatchCalls, opaquePatchBefore + 1);
assert.equal(dirtyCalls, opaqueDirtyBefore + 1);
assert.equal(lightInvalidations.length, opaqueInvalidationsBefore + 1);
assert.deepEqual(lightInvalidations.at(-1), [5, 1, 3, 2, 0]);
assert.equal(lightWorld.lightAt(5, 1, 2), 18);

let columnLightCalls = 0;
let planeLightCalls = 0;
const columnLightWorld = createChunkedWorld({
  chunkSize: 4,
  maxY: 3,
  renderRadius: 0,
  generateChunk: () => new Array(4 * 4 * 3).fill(0),
  generateLightChunk: () => new Array(4 * 4 * 3).fill(15),
  affectedLightCells: () => {
    planeLightCalls += 1;
    return { $: "Con", head: { $: "Cell", x: 5n, y: 1n, z: 2n }, tail: { $: "Nil" } };
  },
  affectedLightColumnCells: () => {
    columnLightCalls += 1;
    return { $: "Con", head: { $: "Cell", x: 5n, y: 1n, z: 2n }, tail: { $: "Nil" } };
  },
  generateLightCells: () => ({
    $: "Con",
    head: { $: "LightCell", x: 5n, y: 1n, z: 2n, light: 18 },
    tail: { $: "Nil" },
  }),
});
columnLightWorld.loadAround(6, 6);
assert.equal(columnLightWorld.setBlock(5, 1, 2, 2), true);
assert.equal(columnLightCalls, 1);
assert.equal(planeLightCalls, 0);
assert.equal(columnLightWorld.lightAt(5, 1, 2), 18);

let loadedBlocks = 0;
world.forEachLoadedBlock((x, y, z, block) => {
  assert.ok(x >= 0 && y >= 0 && z >= 0);
  if (block !== 0) loadedBlocks += 1;
});
assert.equal(loadedBlocks, 9 * 4 * 4 + 1);
console.log(JSON.stringify({ activeChunks: world.activeChunkCount(), loadedBlocks }));
