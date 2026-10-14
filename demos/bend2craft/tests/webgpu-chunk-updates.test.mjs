import assert from "node:assert/strict";
import {
  TERRAIN_VERTEX_STRIDE_BYTES,
  classifyChunkUpdate,
  packTerrainLayer,
  packedLayerBounds,
} from "../web/webgpu-chunk-buffers.js";
import { emptyBounds, isEmptyBounds, mergeBounds } from "../web/chunk-frustum.js";
import { buildChunkMeshBatch } from "../web/mesh-worker-core.js";

// The WebGPU backend uploads one buffer per chunk, so an edit must be able to
// replace a single chunk and leave the rest of the resident set untouched.
assert.equal(classifyChunkUpdate(null, ["a", "b"]), "resync", "the first publish is a resync");
assert.equal(classifyChunkUpdate(["a", "b"], ["a", "b"]), "edit");
assert.equal(classifyChunkUpdate(["a", "b"], ["a", "b", "c"]), "resync", "a new chunk is a resync");
assert.equal(classifyChunkUpdate(["a", "b", "c"], ["a", "b"]), "resync", "a retired chunk is a resync");
assert.equal(classifyChunkUpdate([], []), "edit", "an empty resident set with nothing incoming is an edit");
assert.equal(classifyChunkUpdate(null, []), "resync");

// Key comparison must not depend on ordering, because streaming reorders the
// resident map on every snapshot.
assert.equal(classifyChunkUpdate(["a", "b"], ["b", "a"]), "edit");
assert.equal(classifyChunkUpdate(["1,1", "2,2"], ["2,2", "1,1"]), "edit");

function layer(vertexCount, base = 0) {
  const positions = new Float32Array(vertexCount * 3);
  const colors = new Float32Array(vertexCount * 3);
  const lights = new Float32Array(vertexCount * 2);
  const normals = new Float32Array(vertexCount * 3);
  const uvs = new Float32Array(vertexCount * 2);
  const materials = new Float32Array(vertexCount);
  const tiles = new Float32Array(vertexCount * 4);
  for (let vertex = 0; vertex < vertexCount; vertex += 1) {
    positions[vertex * 3] = base + vertex;
    positions[vertex * 3 + 1] = 0;
    positions[vertex * 3 + 2] = 0;
    colors[vertex * 3] = 1;
    colors[vertex * 3 + 1] = 1;
    colors[vertex * 3 + 2] = 1;
    lights[vertex * 2] = 1;
    lights[vertex * 2 + 1] = 1;
    normals[vertex * 3 + 1] = 1;
    materials[vertex] = 10;
    tiles[vertex * 4] = 0;
  }
  return { positions, colors, lights, normals, uvs, materials, tiles, quadCount: vertexCount / 6 };
}

const packed = packTerrainLayer(layer(12, 4));
assert.equal(packed.vertexCount, 12);
assert.equal(packed.strideBytes, TERRAIN_VERTEX_STRIDE_BYTES);
assert.deepEqual(
  packedLayerBounds(packed, emptyBounds),
  { minX: 4, minY: 0, minZ: 0, maxX: 15, maxY: 0, maxZ: 0 },
);
assert.equal(isEmptyBounds(packedLayerBounds(packTerrainLayer(null), emptyBounds)), true);
assert.equal(isEmptyBounds(packedLayerBounds(packTerrainLayer(layer(0)), emptyBounds)), true);

// A chunk that carries only water still has a box the culler can use.
const waterOnly = packTerrainLayer(layer(6, 100));
const merged = mergeBounds(
  packedLayerBounds(packTerrainLayer(null), emptyBounds),
  packedLayerBounds(waterOnly, emptyBounds),
);
assert.deepEqual(merged, { minX: 100, minY: 0, minZ: 0, maxX: 105, maxY: 0, maxZ: 0 });

// Per-chunk presentation must not compose a whole-world vertex array. The
// merged composition is the global rebuild this phase removes, so the batch
// must report its absence instead of silently building it.
const CHUNK_SIZE = 4;
const MAX_Y = 4;
function chunkData(chunkX, chunkZ, top = 1) {
  const data = new Uint32Array(CHUNK_SIZE * CHUNK_SIZE * MAX_Y);
  for (let z = 0; z < CHUNK_SIZE; z += 1) {
    for (let x = 0; x < CHUNK_SIZE; x += 1) {
      data[x + CHUNK_SIZE * (z + CHUNK_SIZE * top)] = 1;
    }
  }
  return { chunkX, chunkZ, data, light: new Uint8Array(data.length) };
}
const activeKeys = ["0,0", "1,0", "0,1", "1,1"];
const chunks = [
  { key: "0,0", ...chunkData(0, 0) },
  { key: "1,0", ...chunkData(1, 0) },
  { key: "0,1", ...chunkData(0, 1) },
  { key: "1,1", ...chunkData(1, 1) },
];
const existingMeshes = buildChunkMeshBatch({
  chunkSize: CHUNK_SIZE,
  maxY: MAX_Y,
  activeKeys,
  targets: activeKeys,
  chunks,
}).meshes;

function batch(targets, options = {}) {
  return buildChunkMeshBatch({
    chunkSize: CHUNK_SIZE,
    maxY: MAX_Y,
    activeKeys,
    targets,
    chunks,
    existingMeshes,
    ...options,
  });
}

const edit = batch(["1,1"], { perChunkOnly: true });
assert.deepEqual(edit.meshes.map((mesh) => mesh.key), ["1,1"], "only the dirty chunk is rebuilt");
assert.equal(edit.vertexData, null, "per-chunk mode must not compose a whole-world vertex array");
assert.equal(edit.quads, null, "per-chunk mode must not concatenate every chunk's quads");
assert.ok(edit.meshes[0].vertexData !== null, "the rebuilt chunk still carries its own vertex arrays");
assert.ok(edit.meshes[0].vertexData.opaque.positions.length > 0);
assert.deepEqual([...edit.activeKeys].sort(), [...activeKeys].sort());

// The WebGL fallback still needs the merged buffers, so the default is unchanged.
const mergedBatch = batch(["1,1"]);
assert.ok(Array.isArray(mergedBatch.quads), "the default path must keep the merged quads");
assert.ok(mergedBatch.vertexData !== null, "the default path must keep the merged vertex arrays");
assert.ok(mergedBatch.vertexData.opaque.positions.length > edit.meshes[0].vertexData.opaque.positions.length);

// Rebuilding the same chunk twice with identical input must be deterministic,
// so an edit that changes nothing still reuses the same buffer source.
const first = batch(["1,1"], { perChunkOnly: true });
const second = batch(["1,1"], { perChunkOnly: true });
assert.equal(
  first.meshes[0].vertexData.opaque.positions.length,
  second.meshes[0].vertexData.opaque.positions.length,
);

console.log("webgpu chunk updates ok");
