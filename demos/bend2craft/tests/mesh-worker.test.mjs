import assert from "node:assert/strict";
import { buildChunkMeshBatch, buildChunkMeshes } from "../web/mesh-worker-core.js";

const chunks = [
  {
    key: "0,0",
    chunkX: 0,
    chunkZ: 0,
    data: Uint8Array.of(1),
    light: Uint8Array.of(15),
  },
  {
    key: "1,0",
    chunkX: 1,
    chunkZ: 0,
    data: Uint8Array.of(1),
    light: Uint8Array.of(15),
  },
];
const meshes = buildChunkMeshes({
  chunkSize: 1,
  maxY: 1,
  activeKeys: ["0,0", "1,0"],
  targets: ["0,0", "1,0"],
  chunks,
});

assert.equal(meshes.length, 2);
assert.deepEqual(meshes.map((mesh) => mesh.blockCount), [1, 1]);
assert.deepEqual(meshes.map((mesh) => mesh.quads.length), [5, 5]);
assert.equal(meshes[0].quads.some((quad) => quad.faceIndex === 2), false);
assert.equal(meshes[1].quads.some((quad) => quad.faceIndex === 3), false);
const batch = buildChunkMeshBatch({
  chunkSize: 1,
  maxY: 1,
  activeKeys: ["0,0", "1,0"],
  targets: ["0,0", "1,0"],
  chunks,
});
assert.equal(batch.blockCount, 2);
assert.equal(batch.quads.length, 6);

const isolated = buildChunkMeshes({
  chunkSize: 1,
  maxY: 1,
  activeKeys: ["4,-2"],
  targets: ["4,-2"],
  chunks: [{
    key: "4,-2",
    chunkX: 4,
    chunkZ: -2,
    data: Uint8Array.of(2),
    light: Uint8Array.of(11),
  }],
});
assert.equal(isolated[0].quads.length, 6);
assert.equal(isolated[0].quads[0].light, 0);
console.log("mesh worker core ok");
