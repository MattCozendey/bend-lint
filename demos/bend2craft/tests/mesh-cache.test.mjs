import assert from "node:assert/strict";
import { buildGreedyQuads } from "../web/greedy-mesh.js";
import { createChunkMeshCache } from "../web/mesh-cache.js";

const chunks = new Map([
  ["0,0", [[1, 0, 0, 1]]],
  ["1,0", [[2, 0, 0, 1]]],
]);
const world = {
  chunkSize: 2,
  chunkCoordinates: (x, z) => [Math.floor(x / 2), Math.floor(z / 2)],
  forEachActiveChunk(callback) {
    for (const key of chunks.keys()) {
      const [x, z] = key.split(",").map(Number);
      callback(x, z);
    }
  },
  forEachChunkBlock(chunkX, chunkZ, callback) {
    for (const entry of chunks.get(`${chunkX},${chunkZ}`) ?? []) callback(...entry);
  },
  blockAt(x, y, z) {
    for (const entries of chunks.values()) {
      for (const [bx, by, bz, block] of entries) {
        if (bx === x && by === y && bz === z) return block;
      }
    }
    return 0;
  },
  isActive(x, z) {
    return chunks.has(`${Math.floor(x / 2)},${Math.floor(z / 2)}`);
  },
};

const cache = createChunkMeshCache(world, buildGreedyQuads);
cache.rebuildDirty();
assert.equal(cache.snapshot().blockCount, 2);
assert.equal(cache.snapshot().quads.length, 6);
assert.equal(cache.rebuildCount, 2);

cache.invalidateBlock(0, 0);
cache.rebuildDirty();
assert.equal(cache.rebuildCount, 3);

cache.invalidateBlock(1, 0);
cache.rebuildDirty();
assert.equal(cache.rebuildCount, 5);

chunks.set("0,1", [[0, 0, 2, 1]]);
cache.rebuildDirty();
assert.equal(cache.rebuildCount, 7);

chunks.delete("1,0");
cache.rebuildDirty();
assert.equal(cache.rebuildCount, 8);

const boundaryChunks = new Map([["0,0", [[0, 0, 0, 1]]]]);
const boundaryWorld = {
  chunkSize: 1,
  chunkCoordinates: (x, z) => [Math.floor(x), Math.floor(z)],
  forEachActiveChunk(callback) {
    for (const key of boundaryChunks.keys()) {
      const [x, z] = key.split(",").map(Number);
      callback(x, z);
    }
  },
  forEachChunkBlock(chunkX, chunkZ, callback) {
    for (const entry of boundaryChunks.get(`${chunkX},${chunkZ}`) ?? []) callback(...entry);
  },
  blockAt(x, y, z) {
    for (const entries of boundaryChunks.values()) {
      for (const [bx, by, bz, block] of entries) {
        if (bx === x && by === y && bz === z) return block;
      }
    }
    return 0;
  },
  isActive(x, z) {
    return boundaryChunks.has(`${Math.floor(x)},${Math.floor(z)}`);
  },
};
const boundaryCache = createChunkMeshCache(boundaryWorld, buildGreedyQuads);
boundaryCache.rebuildDirty();
assert.equal(boundaryCache.snapshot().quads.length, 6);
boundaryChunks.set("1,0", [[1, 0, 0, 1]]);
boundaryCache.rebuildDirty();
assert.equal(boundaryCache.snapshot(false).quads.length, 10);
console.log("mesh cache ok");
