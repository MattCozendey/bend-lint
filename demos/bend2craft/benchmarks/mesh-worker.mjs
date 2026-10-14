import { buildChunkMeshBatch } from "../web/mesh-worker-core.js";
import { buildGreedyQuads } from "../web/greedy-mesh.js";

const chunkSize = 16;
const maxY = 20;
const activeKeys = [];
const chunks = [];
const indexOf = (x, y, z) => x + chunkSize * (z + chunkSize * y);

for (let chunkZ = 0; chunkZ < 5; chunkZ += 1) {
  for (let chunkX = 0; chunkX < 5; chunkX += 1) {
    const key = `${chunkX},${chunkZ}`;
    activeKeys.push(key);
    const data = new Uint8Array(chunkSize * chunkSize * maxY);
    const light = new Uint8Array(data.length).fill(15);
    for (let y = 0; y < maxY; y += 1) {
      for (let z = 0; z < chunkSize; z += 1) {
        for (let x = 0; x < chunkSize; x += 1) {
          const height = 7 + ((x * 3 + z * 5 + chunkX * 7 + chunkZ * 11) % 5);
          if (y < height) data[indexOf(x, y, z)] = y === height - 1 ? 3 : y < height - 3 ? 1 : 2;
        }
      }
    }
    chunks.push({ key, chunkX, chunkZ, data, light });
  }
}

const start = performance.now();
const result = buildChunkMeshBatch({
  chunkSize,
  maxY,
  activeKeys,
  targets: activeKeys,
  chunks,
});
const elapsed = performance.now() - start;

const leafBlocks = new Map();
for (let y = 0; y < 4; y += 1) {
  for (let z = 0; z < 8; z += 1) {
    for (let x = 0; x < 8; x += 1) leafBlocks.set(`${x},${y},${z}`, 4);
  }
}
const leafStart = performance.now();
const leafQuads = buildGreedyQuads({
  forEachLoadedBlock(callback) {
    for (const [key, block] of leafBlocks) {
      const [x, y, z] = key.split(",").map(Number);
      callback(x, y, z, block);
    }
  },
  blockAt: (x, y, z) => leafBlocks.get(`${x},${y},${z}`) ?? 0,
  isActive: () => true,
});
const leafElapsed = performance.now() - leafStart;
console.log(JSON.stringify({
  chunks: result.meshes.length,
  cellsPerChunk: chunkSize * chunkSize * maxY,
  blocks: result.blockCount,
  quads: result.quads.length,
  opaqueVertices: result.vertexData.opaque.positions.length / 3,
  waterVertices: result.vertexData.water.positions.length / 3,
  leafQuads: leafQuads.quads.length,
  leafVertices: leafQuads.quads.length * 6,
  leafMs: leafElapsed,
  ms: elapsed,
}));
