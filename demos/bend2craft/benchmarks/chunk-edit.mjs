import { buildChunkMeshBatch } from "../web/mesh-worker-core.js";
import { buildTerrainVertexArrays } from "../web/terrain-vertex-builder.js";
import { mergeChunkQuads } from "../web/mesh-merge.js";

// Reproducible single-block-edit benchmark for the WebGPU terrain path. It
// measures the worker-side cost of rebuilding one chunk, with and without the
// whole-world vertex composition that the per-chunk mode removes. This is pure
// CPU work on the JavaScript target; it does not claim GPU acceleration.

const CHUNK_SIZE = 16;
const MAX_Y = 20;
const RENDER_DISTANCE = Number(process.env.RENDER_DISTANCE ?? 2);
const SPAN = RENDER_DISTANCE * 2 + 1;
const ITERATIONS = Number(process.env.EDIT_ITERATIONS ?? 40);
const TARGET_KEYS = [`${RENDER_DISTANCE},${RENDER_DISTANCE}`];

function indexOf(x, y, z) {
  return x + CHUNK_SIZE * (z + CHUNK_SIZE * y);
}

function chunkData(chunkX, chunkZ) {
  const cells = CHUNK_SIZE * CHUNK_SIZE * MAX_Y;
  const data = new Uint32Array(cells);
  const light = new Uint8Array(cells);
  for (let y = 0; y < MAX_Y; y += 1) {
    for (let z = 0; z < CHUNK_SIZE; z += 1) {
      for (let x = 0; x < CHUNK_SIZE; x += 1) {
        const column = (chunkX * CHUNK_SIZE + x) * 31 + (chunkZ * CHUNK_SIZE + z) * 17;
        const height = 6 + (column % 5);
        if (y <= height) {
          data[indexOf(x, y, z)] = y === height ? 3 : 2;
          light[indexOf(x, y, z)] = 15;
        }
      }
    }
  }
  return { chunkX, chunkZ, data, light };
}

const activeKeys = [];
const chunks = [];
for (let z = 0; z < SPAN; z += 1) {
  for (let x = 0; x < SPAN; x += 1) {
    const key = `${x},${z}`;
    activeKeys.push(key);
    chunks.push({ key, ...chunkData(x, z) });
  }
}

const initial = buildChunkMeshBatch({
  chunkSize: CHUNK_SIZE,
  maxY: MAX_Y,
  activeKeys,
  targets: activeKeys,
  chunks,
});
const existingMeshes = initial.meshes;
const residentQuads = existingMeshes.flatMap((mesh) => mesh.quads);

function measure(run) {
  const warmup = Math.max(1, Math.floor(ITERATIONS / 8));
  for (let index = 0; index < warmup; index += 1) run();
  const start = performance.now();
  let result = null;
  for (let index = 0; index < ITERATIONS; index += 1) result = run();
  return { ms: performance.now() - start, result };
}

// Before: the edit also composed one whole-world vertex array.
const before = measure(() => buildChunkMeshBatch({
  chunkSize: CHUNK_SIZE,
  maxY: MAX_Y,
  activeKeys,
  targets: TARGET_KEYS,
  chunks,
  existingMeshes,
  merge: false,
}));

// After: per-chunk mode publishes only the edited chunk's own arrays.
const after = measure(() => buildChunkMeshBatch({
  chunkSize: CHUNK_SIZE,
  maxY: MAX_Y,
  activeKeys,
  targets: TARGET_KEYS,
  chunks,
  existingMeshes,
  merge: false,
  perChunkOnly: true,
}));

// The greedy re-merge that the WebGL fallback still performs when it has to.
// This is not what the edit path used to do (it concatenated per chunk), so it
// is reported separately rather than as part of the before/after comparison.
const fullGreedyMerge = measure(() => {
  const merged = mergeChunkQuads(residentQuads);
  return buildTerrainVertexArrays(merged, 1);
});

const perEditBefore = before.ms / ITERATIONS;
const perEditAfter = after.ms / ITERATIONS;
const mergedFloats = before.result.vertexData.opaque.positions.length;

console.log(JSON.stringify({
  activeChunks: activeKeys.length,
  residentQuads: residentQuads.length,
  editedChunks: TARGET_KEYS.length,
  iterations: ITERATIONS,
  editMsBefore: Number(perEditBefore.toFixed(3)),
  editMsAfter: Number(perEditAfter.toFixed(3)),
  editMsSaved: Number((perEditBefore - perEditAfter).toFixed(3)),
  editSpeedup: Number((perEditBefore / Math.max(perEditAfter, 1e-9)).toFixed(2)),
  fullGreedyMergeMs: Number((fullGreedyMerge.ms / ITERATIONS).toFixed(3)),
  wholeWorldMergedFloats: mergedFloats,
  perChunkOnlyVertexData: after.result.vertexData,
  editedChunkVertices: after.result.meshes[0].vertexData.opaque.positions.length / 3,
}));
