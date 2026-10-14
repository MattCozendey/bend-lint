// The multiplayer server's view of the terrain: chunks around players, mobs
// and simulated cells, made by Bend's bulk chunk export (WorldState.chunk) and
// patched with every accepted edit. Mobs, fluids, fire, crops and villagers
// all read the world through it, so the server never loops over World.block
// per cell.
import { World, WorldState } from "../web/bend-modules.js";
import { chunkIndex } from "../web/chunk-world.js";
import { generationChunkCoordinate, worldCoordinate } from "../web/world-coordinates.js";

export const CHUNK_SIZE = Number(World.chunk_size());
export const MAX_Y = Number(World.max_y());

function listItems(list) {
  const items = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) items.push(node.head);
  return items;
}

/**
 * @param {object} options
 * @param {bigint} options.seed
 * @param {() => object} options.edits  the room's current Bend edit log
 */
export function createWorldCache({ seed, edits }) {
  const chunks = new Map();
  let generated = 0;

  const chunkOf = (value) => Math.floor(value / CHUNK_SIZE);

  function chunkData(chunkX, chunkZ) {
    const key = `${chunkX},${chunkZ}`;
    let data = chunks.get(key);
    if (data === undefined) {
      const blocks = WorldState.chunk(
        seed,
        BigInt(generationChunkCoordinate(chunkX, CHUNK_SIZE)),
        BigInt(generationChunkCoordinate(chunkZ, CHUNK_SIZE)),
        edits(),
      );
      data = Uint8Array.from(Array.isArray(blocks) || ArrayBuffer.isView(blocks) ? blocks : listItems(blocks), Number);
      chunks.set(key, data);
      generated += 1;
    }
    return data;
  }

  function inside(x, y, z) {
    return Number.isInteger(x) && Number.isInteger(y) && Number.isInteger(z) && y >= 0 && y < MAX_Y;
  }

  function blockAt(x, y, z) {
    if (!inside(x, y, z)) return 0;
    const chunkX = chunkOf(x);
    const chunkZ = chunkOf(z);
    return chunkData(chunkX, chunkZ)[chunkIndex(CHUNK_SIZE, x - chunkX * CHUNK_SIZE, y, z - chunkZ * CHUNK_SIZE)];
  }

  /** Writes a cell of a cached chunk; returns the block it held (0 when not cached). */
  function write(x, y, z, value) {
    if (!inside(x, y, z)) return 0;
    const chunkX = chunkOf(x);
    const chunkZ = chunkOf(z);
    const data = chunks.get(`${chunkX},${chunkZ}`);
    if (data === undefined) return null;
    const index = chunkIndex(CHUNK_SIZE, x - chunkX * CHUNK_SIZE, y, z - chunkZ * CHUNK_SIZE);
    const previous = data[index];
    data[index] = value;
    return previous;
  }

  /**
   * Accepted wire edits (stored coordinates). Returns the changes in signed
   * world coordinates with the block each cell held before, when it was known.
   */
  function applyEdits(wireEdits) {
    const changes = [];
    for (const [storedX, y, storedZ, value] of wireEdits) {
      const x = worldCoordinate(storedX);
      const z = worldCoordinate(storedZ);
      changes.push({ x, y, z, value, previous: write(x, y, z, value) });
    }
    return changes;
  }

  /** Drops chunks farther than `radius` chunks from every anchor { x, z }. */
  function evict(anchors, radius = 5) {
    const centres = anchors.map(({ x, z }) => [chunkOf(x), chunkOf(z)]);
    for (const key of chunks.keys()) {
      const [chunkX, chunkZ] = key.split(",").map(Number);
      if (!centres.some(([cx, cz]) => Math.abs(cx - chunkX) <= radius && Math.abs(cz - chunkZ) <= radius)) chunks.delete(key);
    }
  }

  return {
    blockAt,
    inside,
    write,
    applyEdits,
    evict,
    isCached: (x, z) => chunks.has(`${chunkOf(x)},${chunkOf(z)}`),
    size: () => chunks.size,
    generated: () => generated,
  };
}
