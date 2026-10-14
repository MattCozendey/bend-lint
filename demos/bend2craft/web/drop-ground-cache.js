// Cells a dropped item comes to rest on. The game and the multiplayer server
// both settle drops, so the rule lives beside the cache that reads it.
export function isDropSolid(block) {
  return (block > 0 && block < 16) || block === 20;
}

export function createColumnHeightCache({ maxY, blockAt, isSolid }) {
  if (!Number.isInteger(maxY) || maxY <= 0) throw new RangeError("maxY must be positive");
  if (typeof blockAt !== "function" || typeof isSolid !== "function") throw new TypeError("column cache requires blockAt and isSolid");
  const columns = new Map();
  let hits = 0;
  let misses = 0;

  function key(x, z) {
    return `${x},${z}`;
  }

  function get(x, z) {
    const columnKey = key(x, z);
    const cached = columns.get(columnKey);
    if (cached !== undefined) {
      hits += 1;
      return cached;
    }
    misses += 1;
    let floorY = 0;
    for (let y = maxY - 1; y >= 0; y -= 1) {
      if (!isSolid(blockAt(x, y, z))) continue;
      floorY = y + 1;
      break;
    }
    columns.set(columnKey, floorY);
    return floorY;
  }

  return {
    get,
    invalidate(x, z) {
      columns.delete(key(x, z));
    },
    clear() {
      columns.clear();
    },
    stats() {
      return { hits, misses, size: columns.size };
    },
  };
}
