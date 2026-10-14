import assert from "node:assert/strict";
import { buildChunkMeshes } from "../web/mesh-worker-core.js";
import { createAsyncChunkMeshCache, shouldPublishMeshSnapshot } from "../web/mesh-cache.js";

const active = new Map([["0,0", {
  chunkX: 0,
  chunkZ: 0,
  data: Uint8Array.of(1),
  light: Uint8Array.of(15),
}]]);
const jobs = [];
let readyCalls = 0;
const world = {
  chunkSize: 1,
  maxY: 1,
  forEachActiveChunk(callback) {
    for (const chunk of active.values()) callback(chunk.chunkX, chunk.chunkZ);
  },
  chunkCoordinates: (x, z) => [Math.floor(x), Math.floor(z)],
  forEachChunkBlock(_chunkX, _chunkZ, callback) { callback(0, 0, 0, 1); },
  blockAt: () => 1,
  isActive: () => true,
  lightAt: () => 15,
  getChunkData(chunkX, chunkZ) {
    const chunk = active.get(`${chunkX},${chunkZ}`);
    return chunk === undefined ? null : {
      chunkX: chunk.chunkX,
      chunkZ: chunk.chunkZ,
      data: chunk.data.slice(),
      light: chunk.light.slice(),
    };
  },
};
const cache = createAsyncChunkMeshCache(
  world,
  (job) => jobs.push(job),
  () => { readyCalls += 1; },
);

assert.equal(cache.rebuildDirty(), true);
assert.equal(cache.pending, true);
assert.equal(jobs.length, 1);
assert.equal(cache.snapshot().blockCount, 0);
const first = jobs[0];
const firstMeshes = buildChunkMeshes(first);
assert.equal(cache.applyBuild(first.id, firstMeshes), true);
assert.equal(cache.pending, false);
assert.equal(readyCalls, 1);
assert.equal(cache.snapshot(false).blockCount, 1);
assert.equal(cache.snapshot(false).chunks.length, 1);
assert.equal(cache.snapshot(false).chunks[0].key, "0,0");
assert.equal(cache.snapshot(false).chunks[0].vertexData.opaque.positions.length / 3, 36);
assert.equal(cache.rebuildCount, 1);

cache.invalidateChunk(0, 0);
assert.equal(cache.rebuildDirtySync(), true);
assert.equal(cache.snapshot(false).blockCount, 1);
cache.invalidateChunk(0, 0);
assert.equal(cache.rebuildDirty(), true);
assert.equal(cache.rebuildDirty(), false);
const second = jobs[1];
assert.equal(second.merge, false);
assert.equal(cache.applyBuild(second.id, buildChunkMeshes(second)), true);
assert.equal(cache.rebuildCount, 3);

function makeChunk(chunkX, chunkZ) {
  return { chunkX, chunkZ, data: Uint8Array.of(1), light: Uint8Array.of(15) };
}

const windowActive = new Map();
for (let chunkZ = -1; chunkZ <= 1; chunkZ += 1) {
  for (let chunkX = -1; chunkX <= 1; chunkX += 1) {
    windowActive.set(`${chunkX},${chunkZ}`, makeChunk(chunkX, chunkZ));
  }
}
const windowJobs = [];
const windowWorld = {
  chunkSize: 1,
  maxY: 1,
  forEachActiveChunk(callback) {
    for (const chunk of windowActive.values()) callback(chunk.chunkX, chunk.chunkZ);
  },
  chunkCoordinates: (x, z) => [Math.floor(x), Math.floor(z)],
  getChunkData(chunkX, chunkZ) {
    const chunk = windowActive.get(`${chunkX},${chunkZ}`);
    return chunk === undefined ? null : { ...chunk, data: chunk.data.slice(), light: chunk.light.slice() };
  },
};
const windowCache = createAsyncChunkMeshCache(windowWorld, (job) => windowJobs.push(job));
assert.equal(windowCache.rebuildDirty(), true);
assert.equal(windowCache.applyBuild(windowJobs[0].id, buildChunkMeshes(windowJobs[0])), true);
windowActive.set("2,0", makeChunk(2, 0));
assert.equal(windowCache.rebuildDirty(), true);
const progressiveJob = windowJobs[1];
assert.equal(progressiveJob.chunks.length, 7);
assert.equal(progressiveJob.chunks.some((chunk) => chunk.key === "-1,0"), false);
assert.equal(windowCache.applyBuild(progressiveJob.id, buildChunkMeshes(progressiveJob)), true);

const cappedJobs = [];
const cappedCache = createAsyncChunkMeshCache(
  windowWorld,
  (job) => cappedJobs.push(job),
  null,
  { maxTargetsPerJob: 2 },
);
assert.equal(cappedCache.rebuildDirty(), true);
assert.equal(cappedJobs[0].targets.length, 2);
assert.equal(cappedCache.applyBuild(cappedJobs[0].id, buildChunkMeshes(cappedJobs[0])), true);
assert.equal(cappedCache.rebuildDirty(), true);
assert.equal(cappedJobs[1].targets.length, 2);
assert.equal(cappedCache.applyBuild(cappedJobs[1].id, buildChunkMeshes(cappedJobs[1])), true);
assert.equal(shouldPublishMeshSnapshot("webgl", true, false), false);
assert.equal(shouldPublishMeshSnapshot("webgl", false, false), true);
assert.equal(shouldPublishMeshSnapshot("webgl", true, true), true);
assert.equal(shouldPublishMeshSnapshot("webgpu", true, false), true);
console.log("async mesh cache ok");
