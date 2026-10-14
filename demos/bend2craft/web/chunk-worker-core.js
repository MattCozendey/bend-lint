// Pure helpers for the chunk worker, kept out of the worker entry so they can
// be tested without a Worker global.

function sourceKey(source, seed) {
  return `${seed}:${source.x},${source.y},${source.z},${source.block}`;
}

/**
 * Caches the light field of each source. A torch flood depends only on the
 * seed and the source (its walls are generated terrain), so the worker computes
 * it once instead of once per chunk inside its reach. `flood` and `append` are
 * the Bend `Light.source_fields_one` and `Light.append_fields` contracts.
 */
export function createSourceFieldCache({ flood, append, limit = 512 }) {
  if (typeof flood !== "function" || typeof append !== "function") {
    throw new TypeError("source field cache requires flood and append functions");
  }
  if (!Number.isInteger(limit) || limit < 1) throw new RangeError("limit must be a positive integer");
  const cache = new Map();
  let floods = 0;

  function fieldsOf(source, seed) {
    const key = sourceKey(source, seed);
    let fields = cache.get(key);
    if (fields === undefined) {
      fields = flood(source, seed);
      floods += 1;
      if (cache.size >= limit) cache.delete(cache.keys().next().value);
    } else {
      // Refresh recency so the sources near the player survive eviction.
      cache.delete(key);
    }
    cache.set(key, fields);
    return fields;
  }

  // Appends the fields of a Bend list of sources, preserving its order.
  function fieldsFor(sources, seed) {
    const ordered = [];
    for (let node = sources; node?.$ === "Con"; node = node.tail) ordered.push(node.head);
    let fields = { $: "Nil" };
    for (let index = ordered.length - 1; index >= 0; index -= 1) {
      fields = append(fieldsOf(ordered[index], seed), fields);
    }
    return fields;
  }

  return {
    fieldsFor,
    get size() { return cache.size; },
    get floods() { return floods; },
  };
}

/** Copies the first `cellCount` cells of a Bend array into transferable bytes. */
export function packChunkCells(values, cellCount = values?.length) {
  if (!Array.isArray(values) && !ArrayBuffer.isView(values)) {
    throw new TypeError("chunk cells must be an array");
  }
  if (!Number.isInteger(cellCount) || cellCount < 0 || cellCount > values.length) {
    throw new RangeError("cellCount must fit inside the generated array");
  }
  const packed = new Uint8Array(cellCount);
  for (let index = 0; index < cellCount; index += 1) packed[index] = Number(values[index] ?? 0);
  return packed;
}
