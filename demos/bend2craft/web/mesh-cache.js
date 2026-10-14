import { buildGreedyQuads } from "./greedy-mesh.js";
import { mergeChunkQuads } from "./mesh-merge.js";
import { buildTerrainVertexArrays } from "./terrain-vertex-builder.js";
import { concatFloat32Arrays } from "./vertex-buffer-compose.js";

export { mergeChunkQuads } from "./mesh-merge.js";

export function shouldPublishMeshSnapshot(rendererKind, pending, immediateDirty = false) {
  return immediateDirty || rendererKind !== "webgl" || !pending;
}

function chunkKey(chunkX, chunkZ) {
  return `${chunkX},${chunkZ}`;
}

function parseChunkKey(key) {
  return key.split(",").map(Number);
}

function markNeighborChunks(dirty, key) {
  const [chunkX, chunkZ] = parseChunkKey(key);
  for (const [dx, dz] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
    dirty.add(chunkKey(chunkX + dx, chunkZ + dz));
  }
}

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

export function createChunkMeshCache(world, buildQuads = buildGreedyQuads) {
  if (!world || typeof world.forEachActiveChunk !== "function" || typeof world.forEachChunkBlock !== "function") {
    throw new TypeError("mesh cache requires chunk iteration methods");
  }
  const meshes = new Map();
  const dirty = new Set();
  let rebuildCount = 0;

  function activeKeys() {
    const keys = new Set();
    world.forEachActiveChunk((chunkX, chunkZ) => keys.add(chunkKey(chunkX, chunkZ)));
    return keys;
  }

  function syncActiveChunks() {
    const active = activeKeys();
    const changed = [];
    for (const key of meshes.keys()) {
      if (!active.has(key)) {
        meshes.delete(key);
        changed.push(key);
      }
    }
    for (const key of active) {
      if (!meshes.has(key)) {
        dirty.add(key);
        changed.push(key);
      }
    }
    for (const key of changed) {
      // A chunk's border faces depend on the four horizontal neighbors. When
      // streaming changes the active set, rebuild those neighbors too or a
      // mesh built against an unloaded neighbor keeps stale seam faces.
      markNeighborChunks(dirty, key);
    }
    return active;
  }

  function invalidateChunk(chunkX, chunkZ) {
    const key = chunkKey(chunkX, chunkZ);
    dirty.add(key);
  }

  function invalidateBlock(x, z) {
    const [chunkX, chunkZ] = world.chunkCoordinates(x, z);
    const localX = ((x % world.chunkSize) + world.chunkSize) % world.chunkSize;
    const localZ = ((z % world.chunkSize) + world.chunkSize) % world.chunkSize;
    const chunkXs = [chunkX];
    const chunkZs = [chunkZ];
    if (localX === 0) chunkXs.push(chunkX - 1);
    if (localX === world.chunkSize - 1) chunkXs.push(chunkX + 1);
    if (localZ === 0) chunkZs.push(chunkZ - 1);
    if (localZ === world.chunkSize - 1) chunkZs.push(chunkZ + 1);
    for (const nextZ of chunkZs) {
      for (const nextX of chunkXs) invalidateChunk(nextX, nextZ);
    }
  }

  function rebuildDirty() {
    const active = syncActiveChunks();
    for (const key of [...dirty]) {
      dirty.delete(key);
      if (!active.has(key)) continue;
      const [chunkX, chunkZ] = parseChunkKey(key);
      meshes.set(key, buildQuads({
        forEachLoadedBlock: (callback) => world.forEachChunkBlock(chunkX, chunkZ, callback),
        blockAt: world.blockAt,
        isActive: world.isActive,
        lightAt: world.lightAt,
      }));
      rebuildCount += 1;
    }
  }

  function snapshot(merge = true) {
    const quads = [];
    let blockCount = 0;
    for (const mesh of meshes.values()) {
      blockCount += mesh.blockCount;
      quads.push(...mesh.quads);
    }
    return { blockCount, quads: merge ? mergeChunkQuads(quads) : quads, rebuildCount, dirtyChunks: dirty.size };
  }

  return {
    invalidateBlock,
    invalidateChunk,
    rebuildDirty,
    snapshot,
    get rebuildCount() { return rebuildCount; },
  };
}

export function createAsyncChunkMeshCache(world, requestBuild, onReady = null, options = {}) {
  if (!world || typeof world.forEachActiveChunk !== "function"
    || typeof world.getChunkData !== "function") {
    throw new TypeError("async mesh cache requires chunk iteration and data methods");
  }
  if (typeof requestBuild !== "function") {
    throw new TypeError("async mesh cache requires a build request function");
  }
  if (onReady !== null && typeof onReady !== "function") {
    throw new TypeError("async mesh cache ready callback must be a function");
  }
  const maxTargetsPerJob = options.maxTargetsPerJob ?? Infinity;
  if (maxTargetsPerJob !== Infinity && (!Number.isInteger(maxTargetsPerJob) || maxTargetsPerJob < 1)) {
    throw new RangeError("maxTargetsPerJob must be a positive integer");
  }
  // The WebGPU backend publishes one vertex buffer per chunk, so it never reads
  // the merged snapshot. Skipping that composition removes the whole-world
  // rebuild that used to run on every mined or placed block.
  const perChunkOnly = options.perChunkOnly === true;

  const meshes = new Map();
  const dirty = new Set();
  let rebuildCount = 0;
  let nextJobId = 0;
  let pendingJobId = null;
  let pendingActiveKeys = null;
  let mergeDirty = true;
  let mergedQuads = [];
  let mergedBlockCount = 0;
  let mergedVertexData = null;
  let hasMergedSnapshot = false;
  let preferFastRebuild = false;
  let editEpoch = 0;
  let pendingEpoch = null;

  function activeKeys() {
    const keys = new Set();
    world.forEachActiveChunk((chunkX, chunkZ) => keys.add(chunkKey(chunkX, chunkZ)));
    return keys;
  }

  function syncActiveChunks() {
    const active = activeKeys();
    const changed = [];
    for (const key of meshes.keys()) {
      if (!active.has(key)) {
        meshes.delete(key);
        changed.push(key);
      }
    }
    for (const key of active) {
      if (!meshes.has(key)) {
        dirty.add(key);
        changed.push(key);
      }
    }
    for (const key of changed) markNeighborChunks(dirty, key);
    return active;
  }

  function invalidateChunk(chunkX, chunkZ) {
    dirty.add(chunkKey(chunkX, chunkZ));
    preferFastRebuild = true;
  }

  function invalidateBlock(x, z) {
    editEpoch += 1;
    const [chunkX, chunkZ] = world.chunkCoordinates(x, z);
    const localX = ((x % world.chunkSize) + world.chunkSize) % world.chunkSize;
    const localZ = ((z % world.chunkSize) + world.chunkSize) % world.chunkSize;
    const chunkXs = [chunkX];
    const chunkZs = [chunkZ];
    if (localX === 0) chunkXs.push(chunkX - 1);
    if (localX === world.chunkSize - 1) chunkXs.push(chunkX + 1);
    if (localZ === 0) chunkZs.push(chunkZ - 1);
    if (localZ === world.chunkSize - 1) chunkZs.push(chunkZ + 1);
    for (const nextZ of chunkZs) {
      for (const nextX of chunkXs) invalidateChunk(nextX, nextZ);
    }
  }

  function rebuildDirty() {
    const active = syncActiveChunks();
    if (pendingJobId !== null) return false;
    const candidates = [...dirty].filter((key) => active.has(key));
    for (const key of dirty) {
      if (!active.has(key)) dirty.delete(key);
    }
    const targets = maxTargetsPerJob === Infinity
      ? candidates
      : candidates.slice(0, maxTargetsPerJob);
    if (targets.length === 0 && !mergeDirty) return false;

    for (const key of targets) dirty.delete(key);
    // Mesh targets only sample their 3x3 horizontal neighborhood. Sending
    // every active chunk on each progressive hydration copies and transfers
    // the whole render window repeatedly while it is still growing.
    const requiredKeys = new Set();
    for (const key of targets) {
      const [chunkX, chunkZ] = parseChunkKey(key);
      for (let dz = -1; dz <= 1; dz += 1) {
        for (let dx = -1; dx <= 1; dx += 1) {
          requiredKeys.add(chunkKey(chunkX + dx, chunkZ + dz));
        }
      }
    }
    const chunks = [];
    for (const key of requiredKeys) {
      if (!active.has(key)) continue;
      const [chunkX, chunkZ] = parseChunkKey(key);
      const chunk = world.getChunkData(chunkX, chunkZ);
      if (chunk !== null) chunks.push({ key, ...chunk });
    }
    // Only the merged (non per-chunk) mode composes the other chunks' meshes in
    // the worker. In per-chunk mode shipping them would structured-clone every
    // resident mesh on every job for nothing.
    const existingMeshes = perChunkOnly
      ? []
      : [...meshes.values()].filter((mesh) => active.has(mesh.key));
    const id = nextJobId += 1;
    const merge = !preferFastRebuild;
    preferFastRebuild = false;
    pendingJobId = id;
    pendingEpoch = editEpoch;
    pendingActiveKeys = [...active];
    mergeDirty = false;
    try {
      requestBuild({
        id,
        chunkSize: world.chunkSize,
        maxY: world.maxY,
        activeKeys: [...active],
        targets,
        chunks,
        existingMeshes,
        merge,
        perChunkOnly,
      });
    } catch (error) {
      pendingJobId = null;
      pendingEpoch = null;
      pendingActiveKeys = null;
      for (const key of targets) dirty.add(key);
      mergeDirty = true;
      throw error;
    }
    return true;
  }

  function rebuildDirtySync() {
    const active = syncActiveChunks();
    const targets = [...dirty].filter((key) => active.has(key));
    for (const key of dirty) {
      if (!active.has(key)) dirty.delete(key);
    }
    if (targets.length === 0 && !mergeDirty) return false;

    for (const key of targets) {
      dirty.delete(key);
      const [chunkX, chunkZ] = parseChunkKey(key);
      const mesh = buildGreedyQuads({
        forEachLoadedBlock: (callback) => world.forEachChunkBlock(chunkX, chunkZ, callback),
        blockAt: world.blockAt,
        isActive: world.isActive,
        lightAt: world.lightAt,
      });
      meshes.set(key, {
        key,
        chunkX,
        chunkZ,
        ...mesh,
        vertexData: buildTerrainVertexArrays(mesh.quads),
      });
      rebuildCount += 1;
    }

    const quads = [];
    let blockCount = 0;
    for (const mesh of meshes.values()) {
      if (!active.has(mesh.key)) continue;
      blockCount += mesh.blockCount;
      quads.push(...mesh.quads);
    }
    mergedQuads = quads;
    mergedBlockCount = blockCount;
    mergedVertexData = perChunkOnly
      ? null
      : composeVertexData([...meshes.values()].filter((mesh) => active.has(mesh.key)));
    hasMergedSnapshot = !perChunkOnly;
    mergeDirty = false;
    preferFastRebuild = false;
    return true;
  }

  function applyBuild(id, result) {
    if (id !== pendingJobId) return false;
    const builtMeshes = Array.isArray(result) ? result : result?.meshes;
    if (!Array.isArray(builtMeshes)) return false;
    const stale = pendingEpoch !== editEpoch;
    const aggregate = Array.isArray(result)
      ? {
        activeKeys: pendingActiveKeys,
        blockCount: builtMeshes.reduce((sum, mesh) => sum + mesh.blockCount, 0),
        quads: mergeChunkQuads(builtMeshes.flatMap((mesh) => mesh.quads)),
        vertexData: null,
      }
      : result;
    pendingJobId = null;
    pendingEpoch = null;
    const requestedActiveKeys = pendingActiveKeys;
    pendingActiveKeys = null;
    if (stale) {
      mergeDirty = true;
      if (onReady !== null) onReady();
      return true;
    }
    const active = syncActiveChunks();
    for (const mesh of builtMeshes) {
      if (!active.has(mesh.key)) continue;
      meshes.set(mesh.key, mesh);
      dirty.delete(mesh.key);
      rebuildCount += 1;
    }
    if (perChunkOnly) {
      // Nothing downstream reads the merged arrays in this mode, so leave them
      // unset instead of rebuilding them once per edit.
      mergedQuads = [];
      mergedBlockCount = 0;
      mergedVertexData = null;
      hasMergedSnapshot = false;
      mergeDirty = false;
      if (onReady !== null) onReady();
      return true;
    }
    const currentActiveKeys = [...active].sort();
    const builtActiveKeys = Array.isArray(aggregate.activeKeys) ? [...aggregate.activeKeys].sort() : [];
    const activeMatches = currentActiveKeys.length === builtActiveKeys.length
      && currentActiveKeys.every((key, index) => key === builtActiveKeys[index])
      && requestedActiveKeys !== null;
    if (activeMatches && Array.isArray(aggregate.quads)) {
      mergedQuads = aggregate.quads;
      mergedBlockCount = Number(aggregate.blockCount ?? 0);
      mergedVertexData = aggregate.vertexData ?? null;
      hasMergedSnapshot = true;
      mergeDirty = false;
    } else {
      mergeDirty = true;
    }
    if (onReady !== null) onReady();
    return true;
  }

  function snapshot(merge = true) {
    const quads = [];
    let blockCount = 0;
    const active = activeKeys();
    const chunks = [];
    for (const mesh of meshes.values()) {
      if (!active.has(mesh.key)) continue;
      blockCount += mesh.blockCount;
      // Per-chunk consumers read `chunks`; flattening every quad each publish
      // would cost O(resident quads) for an array nothing reads.
      if (!perChunkOnly) quads.push(...mesh.quads);
      chunks.push({
        key: mesh.key,
        chunkX: mesh.chunkX,
        chunkZ: mesh.chunkZ,
        vertexData: mesh.vertexData ?? buildTerrainVertexArrays(mesh.quads),
      });
    }
    return {
      blockCount: hasMergedSnapshot ? mergedBlockCount : blockCount,
      quads: hasMergedSnapshot ? mergedQuads : [],
      vertexData: hasMergedSnapshot ? mergedVertexData : null,
      chunks,
      rebuildCount,
      dirtyChunks: dirty.size + (mergeDirty ? 1 : 0) + (pendingJobId === null ? 0 : 1),
    };
  }

  return {
    invalidateBlock,
    invalidateChunk,
    rebuildDirty,
    rebuildDirtySync,
    applyBuild,
    snapshot,
    get rebuildCount() { return rebuildCount; },
    get pending() { return pendingJobId !== null; },
  };
}
