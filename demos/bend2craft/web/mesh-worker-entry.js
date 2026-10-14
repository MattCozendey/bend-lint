import { buildChunkMeshBatch, meshBatchTransferables } from "./mesh-worker-core.js";

self.onmessage = (event) => {
  const {
    id,
    chunkSize,
    maxY,
    activeKeys,
    targets,
    chunks,
    existingMeshes,
    merge,
    perChunkOnly,
  } = event.data;
  try {
    const result = buildChunkMeshBatch({
      chunkSize,
      maxY,
      activeKeys,
      targets,
      chunks,
      existingMeshes,
      merge,
      perChunkOnly,
    });
    // Vertex arrays are handed over rather than structured-cloned.
    self.postMessage({ id, ...result }, meshBatchTransferables(result));
  } catch (error) {
    self.postMessage({ id, error: String(error?.stack ?? error) });
  }
};
