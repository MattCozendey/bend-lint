import { buildGreedyQuads } from "./greedy-mesh.js";
import { mergeChunkQuads } from "./mesh-merge.js";
import { concatFloat32Arrays } from "./vertex-buffer-compose.js";
import { buildTerrainVertexArrays } from "./terrain-vertex-builder.js";
import { chunkIndex, chunkKey, forEachBlockInChunk } from "./chunk-world.js";
export { mergeChunkQuads } from "./mesh-merge.js";

function composeVertexData(meshes) {
  const opaque = [];
  const water = [];
  let opaqueQuadCount = 0;
  let waterQuadCount = 0;
  for (const mesh of meshes) {
    const vertexData = mesh.vertexData ?? buildTerrainVertexArrays(mesh.quads);
    opaque.push(vertexData.opaque);
    water.push(vertexData.water);
    opaqueQuadCount += vertexData.opaque.quadCount;
    waterQuadCount += vertexData.water.quadCount;
  }
  const composeLayer = (layers, quadCount) => ({
    positions: concatFloat32Arrays(...layers.map((layer) => layer.positions)),
    colors: concatFloat32Arrays(...layers.map((layer) => layer.colors)),
    lights: concatFloat32Arrays(...layers.map((layer) => layer.lights)),
    normals: concatFloat32Arrays(...layers.map((layer) => layer.normals)),
    uvs: concatFloat32Arrays(...layers.map((layer) => layer.uvs)),
    materials: concatFloat32Arrays(...layers.map((layer) => layer.materials)),
    tiles: concatFloat32Arrays(...layers.map((layer) => layer.tiles)),
    quadCount,
  });
  return {
    opaque: composeLayer(opaque, opaqueQuadCount),
    water: composeLayer(water, waterQuadCount),
  };
}
export function buildChunkMeshes({
  chunkSize,
  maxY,
  activeKeys,
  targets,
  chunks,
}) {
  if (!Number.isInteger(chunkSize) || chunkSize < 1 || !Number.isInteger(maxY) || maxY < 1) {
    throw new RangeError("mesh worker dimensions must be positive integers");
  }
  if (!Array.isArray(activeKeys) || !Array.isArray(targets) || !Array.isArray(chunks)) {
    throw new TypeError("mesh worker inputs must be arrays");
  }

  const active = new Set(activeKeys);
  const byKey = new Map(chunks.map((chunk) => [chunk.key ?? chunkKey(chunk.chunkX, chunk.chunkZ), chunk]));
  const indexOf = (x, y, z) => chunkIndex(chunkSize, x, y, z);

  function chunkAt(x, z) {
    const chunkX = Math.floor(x / chunkSize);
    const chunkZ = Math.floor(z / chunkSize);
    return byKey.get(chunkKey(chunkX, chunkZ));
  }

  function blockAt(x, y, z) {
    if (!Number.isInteger(y) || y < 0 || y >= maxY) return 0;
    const chunk = chunkAt(x, z);
    if (chunk === undefined) return 0;
    const localX = x - chunk.chunkX * chunkSize;
    const localZ = z - chunk.chunkZ * chunkSize;
    return Number(chunk.data[indexOf(localX, y, localZ)] ?? 0);
  }

  function lightAt(x, y, z) {
    if (!Number.isInteger(y) || y < 0 || y >= maxY) return 0;
    const chunk = chunkAt(x, z);
    if (chunk === undefined) return 0;
    const localX = x - chunk.chunkX * chunkSize;
    const localZ = z - chunk.chunkZ * chunkSize;
    return Number(chunk.light[indexOf(localX, y, localZ)] ?? 0);
  }

  const meshes = [];
  for (const key of targets) {
    const chunk = byKey.get(key);
    if (chunk === undefined || !active.has(key)) continue;
    const mesh = buildGreedyQuads({
      forEachLoadedBlock(callback) {
        forEachBlockInChunk(chunk, chunkSize, maxY, callback);
      },
      blockAt,
      isActive: (x, z) => active.has(chunkKey(Math.floor(x / chunkSize), Math.floor(z / chunkSize))),
      lightAt,
    });
    meshes.push({
      key,
      chunkX: chunk.chunkX,
      chunkZ: chunk.chunkZ,
      ...mesh,
      vertexData: buildTerrainVertexArrays(mesh.quads),
    });
  }
  return meshes;
}

export function buildChunkMeshBatch({
  existingMeshes = [],
  merge = true,
  perChunkOnly = false,
  ...options
}) {
  const meshes = buildChunkMeshes(options);
  const activeKeys = [...new Set(options.activeKeys)];
  const active = new Set(activeKeys);
  // Per-chunk backends upload one buffer per chunk, so composing a single
  // whole-world vertex array would be a global rebuild on every block edit.
  // They only read each mesh's vertex data and block count, so the quad
  // objects are not sent back either.
  if (perChunkOnly) {
    const slim = meshes.map((mesh) => ({ ...mesh, quads: [] }));
    return { meshes: slim, blockCount: null, quads: null, vertexData: null, activeKeys, perChunkOnly: true };
  }
  const byKey = new Map(existingMeshes.map((mesh) => [mesh.key, mesh]));
  for (const mesh of meshes) byKey.set(mesh.key, mesh);
  const allMeshes = [...byKey.values()].filter((mesh) => active.has(mesh.key));
  const quads = [];
  let blockCount = 0;
  for (const mesh of allMeshes) {
    blockCount += mesh.blockCount;
    quads.push(...mesh.quads);
  }
  const mergedQuads = merge ? mergeChunkQuads(quads) : quads;
  return {
    meshes,
    blockCount,
    quads: mergedQuads,
    vertexData: merge
      ? buildTerrainVertexArrays(mergedQuads)
      : composeVertexData(allMeshes),
    activeKeys,
    perChunkOnly: false,
  };
}

function layerBuffers(layer, into) {
  if (layer === null || layer === undefined) return;
  for (const name of ["positions", "colors", "lights", "normals", "uvs", "materials", "tiles"]) {
    const array = layer[name];
    if (ArrayBuffer.isView(array) && !into.includes(array.buffer)) into.push(array.buffer);
  }
}

/** The ArrayBuffers of a batch result that can be transferred, each once. */
export function meshBatchTransferables(result) {
  const buffers = [];
  for (const mesh of result?.meshes ?? []) {
    layerBuffers(mesh.vertexData?.opaque, buffers);
    layerBuffers(mesh.vertexData?.water, buffers);
  }
  layerBuffers(result?.vertexData?.opaque, buffers);
  layerBuffers(result?.vertexData?.water, buffers);
  return buffers;
}
