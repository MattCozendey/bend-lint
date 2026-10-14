import { buildChunkMeshBatch } from "../web/mesh-worker-core.js";

const chunkSize = 16;
const maxY = 20;
const radii = [2, 4, 6];
const indexOf = (x, y, z) => x + chunkSize * (z + chunkSize * y);

function makeWorkload(radius) {
  const activeKeys = [];
  const chunks = [];
  for (let chunkZ = -radius; chunkZ <= radius; chunkZ += 1) {
    for (let chunkX = -radius; chunkX <= radius; chunkX += 1) {
      const key = `${chunkX},${chunkZ}`;
      activeKeys.push(key);
      const data = new Uint8Array(chunkSize * chunkSize * maxY);
      const light = new Uint8Array(data.length).fill(15);
      for (let y = 0; y < maxY; y += 1) {
        for (let z = 0; z < chunkSize; z += 1) {
          for (let x = 0; x < chunkSize; x += 1) {
            const height = 7 + ((x * 3 + z * 5 + chunkX * 7 + chunkZ * 11) % 5 + 5) % 5;
            if (y < height) data[indexOf(x, y, z)] = y === height - 1 ? 3 : y < height - 3 ? 1 : 2;
          }
        }
      }
      chunks.push({ key, chunkX, chunkZ, data, light });
    }
  }
  return { activeKeys, chunks };
}

const rows = [];
for (const radius of radii) {
  const workload = makeWorkload(radius);
  const start = performance.now();
  const result = buildChunkMeshBatch({
    ...workload,
    targets: workload.activeKeys,
    chunkSize,
    maxY,
  });
  rows.push({
    renderDistance: radius,
    chunks: workload.activeKeys.length,
    cells: workload.chunks.length * chunkSize * chunkSize * maxY,
    blocks: result.blockCount,
    quads: result.quads.length,
    opaqueVertices: result.vertexData.opaque.positions.length / 3,
    ms: performance.now() - start,
  });
}
console.log(JSON.stringify(rows));
