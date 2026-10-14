import { WorldState, Light, Villagers } from "./bend-modules.js";
import { createSourceFieldCache, packChunkCells } from "./chunk-worker-core.js";
import { generationChunkCoordinate as generationChunkCoordinateFor } from "./world-coordinates.js";

// One flood per light source for the lifetime of the worker. A flood only
// depends on the seed and the source, while every chunk inside its reach asks
// for it again as the player moves.
const sourceFields = createSourceFieldCache({
  flood: (source, seed) => Light.source_fields_one(source, seed),
  append: (fields, tail) => Light.append_fields(fields, tail),
});

self.postMessage({ workerReady: true });
self.onmessage = (event) => {
  const message = event.data;
  if (message.type === "pathGrid") {
    try {
      const grid = Villagers.path_grid(BigInt(message.seed), message.edits);
      self.postMessage({ type: "pathGrid", requestId: message.requestId, grid });
    } catch (error) {
      self.postMessage({
        type: "pathGrid",
        requestId: message.requestId,
        error: String(error?.stack ?? error),
      });
    }
    return;
  }

  const { id, version, seed, chunkX, chunkZ, edits, cellCount } = message;
  try {
    // A Bend Nat cannot be negative and the 2.0.32 JS lane refuses one outright,
    // so a chunk below the origin is generated under a positive coordinate. The
    // fallback covers a caller that omits generationChunkX/Z and must use the
    // same mapping the main thread uses, or the worker would generate a
    // different chunk than the main thread asked for. Negating was never a
    // mapping: it produced another negative and the same refusal.
    const generationChunkX = message.generationChunkX ?? generationChunkCoordinate(chunkX);
    const generationChunkZ = message.generationChunkZ ?? generationChunkCoordinate(chunkZ);
    const bendSeed = BigInt(seed);
    const bendChunkX = BigInt(generationChunkX);
    const bendChunkZ = BigInt(generationChunkZ);
    const blocks = WorldState.chunk(bendSeed, bendChunkX, bendChunkZ, edits);
    const relevant = Light.relevant_sources(WorldState.light_sources(edits), bendChunkX, bendChunkZ);
    const fields = sourceFields.fieldsFor(relevant, bendSeed);
    const lights = Light.chunk_with_fields(fields, edits, bendSeed, bendChunkX, bendChunkZ);
    // Bend hands back a power-of-two array of numbers. The main thread only
    // needs the chunk's cells as bytes, and transferring them avoids a
    // structured clone of two 8192-slot arrays per chunk.
    const packedBlocks = packChunkCells(blocks, cellCount ?? blocks.length);
    const packedLights = packChunkCells(lights, cellCount ?? lights.length);
    self.postMessage(
      { id, version, chunkX, chunkZ, blocks: packedBlocks, lights: packedLights },
      [packedBlocks.buffer, packedLights.buffer],
    );
  } catch (error) {
    self.postMessage({ id, version, chunkX, chunkZ, error: String(error?.stack ?? error) });
  }
};
