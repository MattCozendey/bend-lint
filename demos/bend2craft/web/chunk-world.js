export const DEFAULT_CHUNK_SIZE = 16;

function validInteger(value) {
  return Number.isInteger(value);
}

function isLightOpaque(value) {
  const block = Number(value);
  return block !== 0 && block !== 7 && block !== 15 && block !== 21;
}

function materializeChunk(generated, cellCount) {
  // The chunk worker transfers exactly-sized bytes; adopt them instead of
  // copying. Any other shape (a Bend array, a list) is copied cell by cell.
  if (generated instanceof Uint8Array && generated.length === cellCount) return generated;
  const data = new Uint8Array(cellCount);
  if (Array.isArray(generated) || ArrayBuffer.isView(generated)) {
    for (let index = 0; index < cellCount; index += 1) {
      data[index] = Number(generated[index] ?? 0);
    }
    return data;
  }

  let node = generated;
  let index = 0;
  while (node?.$ === "Con" && index < cellCount) {
    data[index] = Number(node.head);
    node = node.tail;
    index += 1;
  }
  if (index !== cellCount || node?.$ !== "Nil") {
    throw new TypeError("generateChunk must return a fixed-size array or list");
  }
  return data;
}

function applyLightPatch(generated, chunks, chunkSize, maxY, indexOf, cellCoordinate = Number) {
  let node = generated;
  while (node?.$ === "Con") {
    const cell = node.head;
    const x = cellCoordinate(cell.x);
    const y = Number(cell.y);
    const z = cellCoordinate(cell.z);
    if (validInteger(x) && validInteger(y) && validInteger(z) && y >= 0 && y < maxY) {
      const chunkX = Math.floor(x / chunkSize);
      const chunkZ = Math.floor(z / chunkSize);
      const chunk = chunks.get(chunkKey(chunkX, chunkZ));
      if (chunk !== undefined) {
        const localX = x - chunkX * chunkSize;
        const localZ = z - chunkZ * chunkSize;
        chunk.light[indexOf(localX, y, localZ)] = Number(cell.light);
      }
    }
    node = node.tail;
  }
  if (node?.$ !== "Nil") throw new TypeError("generateLightCells must return a list");
}

export function chunkKey(chunkX, chunkZ) {
  return `${chunkX},${chunkZ}`;
}

// This module is the single owner of chunk storage order and of the local-to-
// world mapping. The greedy mesher runs both here on the main thread and inside
// the mesh worker, so a traversal that drifted between the two would make them
// disagree about which faces are hidden, with no error on either side.
export function chunkIndex(chunkSize, x, y, z) {
  return x + chunkSize * (z + chunkSize * y);
}

export function forEachBlockInChunk(chunk, chunkSize, maxY, callback) {
  const originX = chunk.chunkX * chunkSize;
  const originZ = chunk.chunkZ * chunkSize;
  for (let y = 0; y < maxY; y += 1) {
    for (let z = 0; z < chunkSize; z += 1) {
      for (let x = 0; x < chunkSize; x += 1) {
        callback(originX + x, y, originZ + z, chunk.data[chunkIndex(chunkSize, x, y, z)]);
      }
    }
  }
}

export function createChunkedWorld({
  chunkSize = DEFAULT_CHUNK_SIZE,
  maxY,
  renderRadius = 2,
  loadBudget = Infinity,
  generateChunk,
  generateLightChunk = null,
  generateLightCells = null,
  affectedLightChunks = null,
  affectedLightCells = null,
  affectedLightColumnCells = null,
  // A change the light rules cannot see past its own cell (air and water):
  // `lightNeutral(previous, next)` says which, and `affectedLightSelfCells`
  // is that one-cell stencil (world/light-dirty.bend).
  affectedLightSelfCells = null,
  lightNeutral = null,
  invalidateLightFields = null,
  // Maps a coordinate in a light patch back to the signed world coordinate
  // (the light rules run on stored coordinates).
  lightCellCoordinate = Number,
  requestChunk = null,
  generateBlock,
  initialEdits = null,
  applyEdit = null,
  // Optional batch form of applyEdit: (edits, changes) => edits with every
  // change applied in order, in one pass (WorldState.set_many).
  applyEdits = null,
}) {
  if (!validInteger(chunkSize) || chunkSize < 1) {
    throw new RangeError("chunkSize must be a positive integer");
  }
  if (!validInteger(maxY) || maxY < 1) {
    throw new RangeError("maxY must be a positive integer");
  }
  if (!validInteger(renderRadius) || renderRadius < 0) {
    throw new RangeError("renderRadius must be a non-negative integer");
  }
  if (!(loadBudget === Infinity || (validInteger(loadBudget) && loadBudget > 0))) {
    throw new RangeError("loadBudget must be a positive integer or Infinity");
  }
  if (typeof generateChunk !== "function" && typeof generateBlock !== "function") {
    throw new TypeError("generateChunk or generateBlock must be a function");
  }

  const chunks = new Map();
  const pendingRequests = new Set();
  // Shared-world cells that arrived while their chunk was in flight: the reply
  // was generated from an older log, so they are written over it on arrival.
  const lateCells = new Map();
  const pinnedKeys = new Set();
  let loadVersion = 0;
  let edits = initialEdits;
  const legacyEdits = new Map();
  let activeKeys = new Set();
  let lastLightDirtyCells = { $: "Nil" };

  const indexOf = (x, y, z) => chunkIndex(chunkSize, x, y, z);

  function inside(x, y, z) {
    return validInteger(x) && validInteger(y) && validInteger(z) && y >= 0 && y < maxY;
  }

  function chunkCoordinates(x, z) {
    return [Math.floor(x / chunkSize), Math.floor(z / chunkSize)];
  }

  function localCoordinates(x, y, z) {
    const [chunkX, chunkZ] = chunkCoordinates(x, z);
    return {
      chunkX,
      chunkZ,
      localX: x - chunkX * chunkSize,
      localY: y,
      localZ: z - chunkZ * chunkSize,
    };
  }

  function buildChunk(chunkX, chunkZ) {
    const key = chunkKey(chunkX, chunkZ);
    const cellCount = chunkSize * chunkSize * maxY;
    let data;
    if (typeof generateChunk === "function") {
      data = materializeChunk(generateChunk(chunkX, chunkZ, edits), cellCount);
    } else {
      data = new Uint8Array(cellCount);
      for (let y = 0; y < maxY; y += 1) {
        for (let z = 0; z < chunkSize; z += 1) {
          for (let x = 0; x < chunkSize; x += 1) {
            const globalX = chunkX * chunkSize + x;
            const globalZ = chunkZ * chunkSize + z;
            data[indexOf(x, y, z)] = Number(generateBlock(globalX, y, globalZ));
          }
        }
      }
    }
    let light = new Uint8Array(cellCount);
    light.fill(15);
    if (typeof generateLightChunk === "function") {
      light = materializeChunk(generateLightChunk(chunkX, chunkZ, edits), cellCount);
    }
    if (typeof applyEdit !== "function") {
      const chunkEdits = legacyEdits.get(key);
      if (chunkEdits !== undefined) {
        for (const [index, value] of chunkEdits) data[index] = value;
      }
    }
    return { chunkX, chunkZ, data, light };
  }

  function getChunk(chunkX, chunkZ) {
    const key = chunkKey(chunkX, chunkZ);
    let chunk = chunks.get(key);
    if (chunk === undefined) {
      chunk = buildChunk(chunkX, chunkZ);
      chunks.set(key, chunk);
    }
    return chunk;
  }

  function loadAround(x, z, radius = renderRadius, budget = loadBudget) {
    const [centerX, centerZ] = chunkCoordinates(x, z);
    const candidates = [];
    const nextKeys = new Set();
    for (let chunkZ = centerZ - radius; chunkZ <= centerZ + radius; chunkZ += 1) {
      for (let chunkX = centerX - radius; chunkX <= centerX + radius; chunkX += 1) {
        const key = chunkKey(chunkX, chunkZ);
        candidates.push({ key, distance: (chunkX - centerX) ** 2 + (chunkZ - centerZ) ** 2 });
        nextKeys.add(key);
      }
    }
    candidates.sort((a, b) => a.distance - b.distance || a.key.localeCompare(b.key));

    const pinnedCandidates = [...pinnedKeys]
      .filter((key) => !nextKeys.has(key))
      .map((key) => ({ key, distance: -1 }));
    const loadCandidates = [...pinnedCandidates, ...candidates];
    let loaded = 0;
    for (const { key } of loadCandidates) {
      if (chunks.has(key)) continue;
      if (pendingRequests.has(key)) continue;
      if (loaded >= budget) break;
      const [chunkX, chunkZ] = key.split(",").map(Number);
      if (typeof requestChunk === "function") {
        pendingRequests.add(key);
        requestChunk(chunkX, chunkZ, edits, loadVersion);
      } else {
        getChunk(chunkX, chunkZ);
      }
      loaded += 1;
    }
    const readyKeys = new Set([...nextKeys].filter((key) => chunks.has(key)));
    const centerReady = chunks.has(chunkKey(centerX, centerZ));
    const retainedKeys = new Set([...activeKeys].filter((key) => chunks.has(key)));
    // Keep the last complete render window until the destination center chunk
    // is hydrated. Evicting it as soon as a request starts produces a blank
    // frame (and also pauses fixed-step movement) during every async swap.
    const nextActiveKeys = centerReady ? readyKeys : retainedKeys;

    let changed = nextActiveKeys.size !== activeKeys.size;
    if (!changed) {
      for (const key of nextActiveKeys) {
        if (!activeKeys.has(key)) {
          changed = true;
          break;
        }
      }
    }
    activeKeys = nextActiveKeys;
    for (const key of chunks.keys()) {
      if (!activeKeys.has(key) && !pinnedKeys.has(key)) chunks.delete(key);
    }
    const pendingRender = [...nextKeys].filter((key) => !chunks.has(key)).length;
    const pendingPinned = [...pinnedKeys].filter((key) => !chunks.has(key)).length;
    return {
      center: [centerX, centerZ],
      activeChunks: activeKeys.size,
      changed,
      pendingChunks: pendingRender + pendingPinned,
    };
  }

  function pinChunk(chunkX, chunkZ) {
    if (!validInteger(chunkX) || !validInteger(chunkZ)) return false;
    pinnedKeys.add(chunkKey(chunkX, chunkZ));
    return true;
  }

  function unpinChunk(chunkX, chunkZ) {
    const key = chunkKey(chunkX, chunkZ);
    pinnedKeys.delete(key);
    if (!activeKeys.has(key)) chunks.delete(key);
    return true;
  }

  function hydrateChunk(chunkX, chunkZ, generated, generatedLight, version = loadVersion) {
    if (version !== loadVersion) return false;
    const cellCount = chunkSize * chunkSize * maxY;
    const key = chunkKey(chunkX, chunkZ);
    chunks.set(key, {
      chunkX,
      chunkZ,
      data: materializeChunk(generated, cellCount),
      light: materializeChunk(generatedLight, cellCount),
    });
    pendingRequests.delete(key);
    const late = lateCells.get(key);
    if (late !== undefined) {
      lateCells.delete(key);
      writeBlocks([...late.values()], true);
    }
    return true;
  }

  function blockAt(x, y, z) {
    if (!validInteger(x) || !validInteger(y) || !validInteger(z) || y < 0 || y >= maxY) return 0;
    const { chunkX, chunkZ, localX, localY, localZ } = localCoordinates(x, y, z);
    const chunk = chunks.get(chunkKey(chunkX, chunkZ));
    if (chunk === undefined) return 0;
    return chunk.data[indexOf(localX, localY, localZ)];
  }

  function isLoaded(x, z) {
    if (!validInteger(x) || !validInteger(z)) return false;
    const [chunkX, chunkZ] = chunkCoordinates(x, z);
    return chunks.has(chunkKey(chunkX, chunkZ));
  }

  function isActive(x, z) {
    if (!validInteger(x) || !validInteger(z)) return false;
    const [chunkX, chunkZ] = chunkCoordinates(x, z);
    return activeKeys.has(chunkKey(chunkX, chunkZ));
  }

  function applyBlock(x, y, z, value, logged = false) {
    const { chunkX, chunkZ, localX, localY, localZ } = localCoordinates(x, y, z);
    const chunk = getChunk(chunkX, chunkZ);
    const index = indexOf(localX, localY, localZ);
    const previousBlock = chunk.data[index];
    const key = chunkKey(chunkX, chunkZ);
    if (logged) {
      // The caller folds the whole batch into the log at once.
    } else if (typeof applyEdit === "function") {
      edits = applyEdit(edits, x, y, z, value);
    } else {
      let chunkEdits = legacyEdits.get(key);
      if (chunkEdits === undefined) {
        chunkEdits = new Map();
        legacyEdits.set(key, chunkEdits);
      }
      chunkEdits.set(index, value);
    }
    chunk.data[index] = value;
    return { x, y, z, value, previousBlock: Number(previousBlock) };
  }

  function mergeLightCells(changes, sampler = affectedLightCells) {
    const cells = new Map();
    if (typeof sampler !== "function") return { $: "Nil" };
    for (const change of changes) {
      let node = sampler(change.x, change.y, change.z);
      while (node?.$ === "Con") {
        const cell = node.head;
        const key = `${cell.x},${cell.y},${cell.z}`;
        cells.set(key, cell);
        node = node.tail;
      }
    }
    let list = { $: "Nil" };
    for (const cell of [...cells.values()].reverse()) list = { $: "Con", head: cell, tail: list };
    return list;
  }

  function refreshLight(changes) {
    let lightRelevant = false;
    let opacityChanged = false;
    for (const change of changes) {
      if (typeof invalidateLightFields === "function") {
        invalidateLightFields(change.x, change.y, change.z, change.previousBlock, change.value);
      }
      const blockOpacityChanged = isLightOpaque(change.previousBlock) !== isLightOpaque(change.value);
      opacityChanged = opacityChanged || blockOpacityChanged;
      lightRelevant = lightRelevant
        || change.previousBlock === 12
        || change.value === 12
        || change.previousBlock === 7
        || change.value === 7
        || change.previousBlock === 21
        || change.value === 21
        || blockOpacityChanged;
    }
    if (typeof generateLightChunk !== "function" || !lightRelevant) {
      lastLightDirtyCells = { $: "Nil" };
      return;
    }
    const cellCount = chunkSize * chunkSize * maxY;
    const neutral = typeof lightNeutral === "function" && typeof affectedLightSelfCells === "function"
      && changes.every((change) => lightNeutral(Number(change.previousBlock), Number(change.value)));
    const dirtyCellSampler = neutral
      ? affectedLightSelfCells
      : opacityChanged && typeof affectedLightColumnCells === "function"
        ? affectedLightColumnCells
        : affectedLightCells;
    if (typeof generateLightCells === "function" && typeof dirtyCellSampler === "function") {
      lastLightDirtyCells = mergeLightCells(changes, dirtyCellSampler);
      applyLightPatch(generateLightCells(lastLightDirtyCells, edits), chunks, chunkSize, maxY, indexOf, lightCellCoordinate);
      return;
    }
    lastLightDirtyCells = { $: "Nil" };
    if (typeof affectedLightChunks === "function") {
      const seen = new Set();
      for (const change of changes) {
        let node = affectedLightChunks(change.x, change.z, chunkSize);
        while (node?.$ === "Con") {
          const nextChunkX = Number(node.head.x);
          const nextChunkZ = Number(node.head.z);
          const nextKey = chunkKey(nextChunkX, nextChunkZ);
          if (!seen.has(nextKey)) {
            seen.add(nextKey);
            const neighbor = chunks.get(nextKey);
            if (neighbor !== undefined) {
              neighbor.light = materializeChunk(
                generateLightChunk(neighbor.chunkX, neighbor.chunkZ, edits),
                cellCount,
              );
            }
          }
          node = node.tail;
        }
      }
      return;
    }
    const seen = new Set();
    for (const change of changes) {
      const [chunkX, chunkZ] = chunkCoordinates(change.x, change.z);
      const centerKey = chunkKey(chunkX, chunkZ);
      if (seen.has(centerKey)) continue;
      seen.add(centerKey);
      for (const neighbor of chunks.values()) {
        if (Math.abs(neighbor.chunkX - chunkX) > 1 || Math.abs(neighbor.chunkZ - chunkZ) > 1) continue;
        neighbor.light = materializeChunk(
          generateLightChunk(neighbor.chunkX, neighbor.chunkZ, edits),
          cellCount,
        );
      }
    }
  }

  function validBatch(batch) {
    if (!Array.isArray(batch) || batch.length === 0) return false;
    return batch.every((change) => inside(change?.x, change?.y, change?.z)
      && Number.isInteger(change?.value) && change.value >= 0 && change.value <= 255);
  }

  // Writes the cells and relights them. `logged` means the log already holds
  // the batch (a merged remote log), so only the chunk data changes.
  function writeBlocks(batch, logged) {
    const batched = !logged && typeof applyEdits === "function" && batch.length > 1;
    const changes = batch.map((change) => applyBlock(change.x, change.y, change.z, change.value, logged || batched));
    if (batched) edits = applyEdits(edits, batch);
    refreshLight(changes);
  }

  function setBlocks(batch) {
    if (!validBatch(batch)) return false;
    writeBlocks(batch, false);
    return true;
  }

  function setBlock(x, y, z, value) {
    return setBlocks([{ x, y, z, value }]);
  }


  function lightAt(x, y, z) {
    if (!validInteger(x) || !validInteger(y) || !validInteger(z) || y < 0 || y >= maxY) return 0;
    const { chunkX, chunkZ, localX, localY, localZ } = localCoordinates(x, y, z);
    const chunk = chunks.get(chunkKey(chunkX, chunkZ));
    if (chunk === undefined) return 0;
    return chunk.light[indexOf(localX, localY, localZ)];
  }

  function forEachLoadedBlock(callback) {
    forEachActiveChunk((chunkX, chunkZ) => {
      forEachChunkBlock(chunkX, chunkZ, callback);
    });
  }

  function forEachActiveChunk(callback) {
    for (const key of activeKeys) {
      const chunk = chunks.get(key);
      if (chunk === undefined) continue;
      callback(chunk.chunkX, chunk.chunkZ);
    }
  }

  function forEachPinnedChunk(callback) {
    for (const key of pinnedKeys) {
      const chunk = chunks.get(key);
      if (chunk === undefined) continue;
      callback(chunk.chunkX, chunk.chunkZ);
    }
  }

  function forEachChunkBlock(chunkX, chunkZ, callback) {
    const chunk = chunks.get(chunkKey(chunkX, chunkZ));
    if (chunk === undefined) return;
    forEachBlockInChunk(chunk, chunkSize, maxY, callback);
  }

  function getChunkData(chunkX, chunkZ) {
    const chunk = chunks.get(chunkKey(chunkX, chunkZ));
    if (chunk === undefined) return null;
    return {
      chunkX: chunk.chunkX,
      chunkZ: chunk.chunkZ,
      data: chunk.data.slice(),
      light: chunk.light.slice(),
    };
  }

  function replaceEdits(nextEdits) {
    if (typeof applyEdit !== "function") return false;
    edits = nextEdits;
    loadVersion += 1;
    pendingRequests.clear();
    lateCells.clear();
    chunks.clear();
    activeKeys = new Set();
    return true;
  }

  // Adopts an edit log that already contains a batch from elsewhere (the
  // multiplayer server). `changes` are the batch's cells inside loaded chunks,
  // written and relit here; `unloaded` are its other cells. Those of chunks in
  // flight are written over the reply when it lands (it was generated from an
  // older log), so a chunk edited every tick still loads; later requests read
  // the merged log.
  function mergeEdits(nextEdits, changes = [], unloaded = []) {
    if (!Array.isArray(changes) || !Array.isArray(unloaded)) {
      throw new TypeError("mergeEdits changes and unloaded must be arrays");
    }
    if (changes.length > 0 && !validBatch(changes)) return false;
    // The light patch reads the log, so the merged log is in place first.
    edits = nextEdits;
    if (changes.length > 0) writeBlocks(changes, true);
    for (const cell of unloaded) {
      if (!validBatch([cell])) continue;
      const [chunkX, chunkZ] = chunkCoordinates(cell.x, cell.z);
      const key = chunkKey(chunkX, chunkZ);
      if (!pendingRequests.has(key)) continue;
      let late = lateCells.get(key);
      if (late === undefined) {
        late = new Map();
        lateCells.set(key, late);
      }
      // The last value of a cell wins.
      const cellKey = `${cell.x},${cell.y},${cell.z}`;
      late.delete(cellKey);
      late.set(cellKey, { x: cell.x, y: cell.y, z: cell.z, value: cell.value });
    }
    return true;
  }

  function patchEdits(nextEdits, changes = []) {
    if (!Array.isArray(changes)) throw new TypeError("patchEdits changes must be an array");
    if (changes.length > 0 && !setBlocks(changes)) return false;
    edits = nextEdits;
    loadVersion += 1;
    pendingRequests.clear();
    lateCells.clear();
    return true;
  }

  return {
    chunkSize,
    maxY,
    inside,
    chunkCoordinates,
    isActive,
    isLoaded,
    blockAt,
    lightAt,
    setBlock,
    setBlocks,
    loadAround,
    getEdits: () => edits,
    getLightDirtyCells: () => lastLightDirtyCells,
    replaceEdits,
    patchEdits,
    mergeEdits,
    hydrateChunk,
    pinChunk,
    unpinChunk,
    forEachLoadedBlock,
    forEachActiveChunk,
    forEachPinnedChunk,
    forEachChunkBlock,
    getChunkData,
    activeChunkCount: () => activeKeys.size,
    pinnedChunkCount: () => pinnedKeys.size,
    pendingChunkCount: () => pendingRequests.size,
  };
}
