// The Bend world is defined over natural numbers, while the browser world is
// signed. This module is the one owner of the mapping for the main thread and
// every worker.
//
// A non-negative coordinate is stored as itself. A negative one is stored at
// NEGATIVE_ORIGIN + x. NEGATIVE_ORIGIN is 45 * 2^21: a multiple of every period
// in the terrain formulas (the 24/18/48/40/32 triangle waves, their 2x and 3x
// phases, and the 4096-cell hash at 1, 4 and 32 block scales), so the terrain
// just below zero is the continuation of the terrain just above it instead of
// an unrelated region. Only the features anchored at the origin (the spawn
// plains, the village) stay on the positive side. `World.negative_origin()`
// holds the same constant for Bend, and a test pins the two together. The
// encoding is unambiguous while |x| stays below NEGATIVE_ORIGIN / 2 (~47M).
//
// Saves written before this change stored a negative coordinate in chunk
// LEGACY_GENERATION_CHUNK_OFFSET + |chunk|, which cut the terrain along x = 0
// and z = 0; `migrateLegacyEdits` rewrites those edits on load.
export const NEGATIVE_ORIGIN = 94_371_840;
export const LEGACY_GENERATION_CHUNK_OFFSET = 1_000_000;

export function storageCoordinate(value, chunkSize = 16) {
  void chunkSize;
  return value >= 0 ? value : value + NEGATIVE_ORIGIN;
}

export function generationChunkCoordinate(chunk, chunkSize = 16) {
  return chunk >= 0 ? chunk : chunk + NEGATIVE_ORIGIN / chunkSize;
}

/** The signed world coordinate of a stored (Bend) coordinate. */
export function worldCoordinate(stored) {
  const value = Number(stored);
  return value >= NEGATIVE_ORIGIN / 2 ? value - NEGATIVE_ORIGIN : value;
}

export function isLegacyNegativeCoordinate(stored, chunkSize = 16) {
  const value = Number(stored);
  return value >= LEGACY_GENERATION_CHUNK_OFFSET * chunkSize
    && value < 2 * LEGACY_GENERATION_CHUNK_OFFSET * chunkSize;
}

/** Re-encode a coordinate written by the legacy mapping; others pass through. */
export function migrateLegacyCoordinate(stored, chunkSize = 16) {
  if (!isLegacyNegativeCoordinate(stored, chunkSize)) return Number(stored);
  const value = Number(stored);
  const storedChunk = Math.floor(value / chunkSize);
  const local = value - storedChunk * chunkSize;
  const chunk = -(storedChunk - LEGACY_GENERATION_CHUNK_OFFSET);
  return storageCoordinate(chunk * chunkSize + local, chunkSize);
}

/**
 * Rewrite a saved Bend edit list (`{ $: "Con", head: Edit, tail }`) from the
 * legacy negative mapping. Returns the same list when nothing needed moving,
 * so a current save is untouched.
 */
export function migrateLegacyEdits(edits, chunkSize = 16) {
  const heads = [];
  let changed = false;
  let node = edits;
  for (; node?.$ === "Con"; node = node.tail) {
    const edit = node.head;
    const x = migrateLegacyCoordinate(edit.x, chunkSize);
    const z = migrateLegacyCoordinate(edit.z, chunkSize);
    if (x !== Number(edit.x) || z !== Number(edit.z)) {
      changed = true;
      heads.push({ ...edit, x: BigInt(x), z: BigInt(z) });
    } else {
      heads.push(edit);
    }
  }
  if (!changed) return edits;
  let list = node;
  for (let index = heads.length - 1; index >= 0; index -= 1) list = { $: "Con", head: heads[index], tail: list };
  return list;
}

/**
 * The stored coordinate to hand Bend when it will step outward from `value`
 * (the light dirty-cell stencils add and subtract a radius). Bend's `Nat.sub`
 * stops at zero, so a positive coordinate near the origin is aliased above
 * NEGATIVE_ORIGIN, where both sides of zero are reachable; `canonicalCells`
 * maps the results back.
 */
export function stencilCoordinate(value) {
  return value + NEGATIVE_ORIGIN;
}

/** Re-encode a Bend list of `{ x, y, z }` cells to the canonical storage form. */
export function canonicalCells(cells, chunkSize = 16) {
  const heads = [];
  let node = cells;
  for (; node?.$ === "Con"; node = node.tail) {
    const cell = node.head;
    heads.push({
      ...cell,
      x: BigInt(storageCoordinate(worldCoordinate(cell.x), chunkSize)),
      z: BigInt(storageCoordinate(worldCoordinate(cell.z), chunkSize)),
    });
  }
  let list = node;
  for (let index = heads.length - 1; index >= 0; index -= 1) list = { $: "Con", head: heads[index], tail: list };
  return list;
}
