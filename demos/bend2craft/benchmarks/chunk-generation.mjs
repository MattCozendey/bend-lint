import WorldState from "../world/world_state.bend";
import Light from "../world/light.bend";
import { createSourceFieldCache } from "../web/chunk-worker-core.js";

// Chunk bootstrap cost as the chunk worker pays it: the bulk block export plus
// the chunk light, both for a fresh world and for a save with edits and light
// sources (torches near and far, a lava bucket). Reports per-chunk medians over
// a warm run so JIT warm-up does not dominate the numbers.
const seed = 1337n;
let edits = WorldState.empty();
edits = WorldState.set(edits, 20n, 12n, 20n, 12);
edits = WorldState.set(edits, 5n, 4n, 5n, 21);
edits = WorldState.set(edits, 200n, 12n, 200n, 12);
edits = WorldState.set(edits, 21n, 9n, 20n, 0);
const scenarios = [
  ["fresh", WorldState.empty()],
  ["edited", edits],
];
const chunks = [];
for (let z = 0; z < 4; z += 1) for (let x = 0; x < 4; x += 1) chunks.push([BigInt(x), BigInt(z)]);

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}

const rows = [];
for (const [name, scenarioEdits] of scenarios) {
  const sources = WorldState.light_sources(scenarioEdits);
  // Warm-up pass.
  for (const [cx, cz] of chunks.slice(0, 4)) {
    WorldState.chunk(seed, cx, cz, scenarioEdits);
    Light.chunk_with_edits(sources, scenarioEdits, seed, cx, cz);
  }
  const world = [];
  const light = [];
  for (const [cx, cz] of chunks) {
    let start = performance.now();
    WorldState.chunk(seed, cx, cz, scenarioEdits);
    world.push(performance.now() - start);
    start = performance.now();
    Light.chunk_with_edits(sources, scenarioEdits, seed, cx, cz);
    light.push(performance.now() - start);
  }
  rows.push({
    scenario: name,
    chunks: chunks.length,
    worldMedianMs: Number(median(world).toFixed(2)),
    worldMaxMs: Number(Math.max(...world).toFixed(2)),
    lightMedianMs: Number(median(light).toFixed(2)),
    lightMaxMs: Number(Math.max(...light).toFixed(2)),
  });
}
// The chunk worker's path: floods cached per source, then chunk_with_fields.
{
  const cache = createSourceFieldCache({
    flood: (source, bendSeed) => Light.source_fields_one(source, bendSeed),
    append: (fields, tail) => Light.append_fields(fields, tail),
  });
  const sources = WorldState.light_sources(edits);
  const lightFor = (cx, cz) => Light.chunk_with_fields(
    cache.fieldsFor(Light.relevant_sources(sources, cx, cz), seed), edits, seed, cx, cz,
  );
  for (const [cx, cz] of chunks) lightFor(cx, cz);
  const light = [];
  for (const [cx, cz] of chunks) {
    const start = performance.now();
    lightFor(cx, cz);
    light.push(performance.now() - start);
  }
  rows.push({
    scenario: "edited, cached floods (chunk worker)",
    chunks: chunks.length,
    lightMedianMs: Number(median(light).toFixed(2)),
    lightMaxMs: Number(Math.max(...light).toFixed(2)),
    floods: cache.floods,
  });
}
console.log(JSON.stringify(rows));
