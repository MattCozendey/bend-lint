import assert from "node:assert/strict";
import Light from "../world/light.bend";
import World from "../world/world.bend";

assert.equal(Number(Light.max_light()), 15);
const emptySources = { $: "Nil" };
assert.equal(Number(Light.block(emptySources, 1337n, 40n, 15n, 40n)), 15);
assert.equal(Number(Light.block(emptySources, 1337n, 40n, 1n, 40n)), 0);

const chunk = Light.chunk(emptySources, 1337n, 2n, 2n);
assert.equal(Array.isArray(chunk), true);
assert.equal(chunk.length, World.chunk(1337n, 2n, 2n).length);
const index = 3 + 16 * (3 + 16 * 15);
assert.equal(Number(chunk[index]), 15);
const source = Light.source(20n, 2n, 38n);
const sources = { $: "Con", head: source, tail: { $: "Nil" } };
assert.equal(Number(Light.block(sources, 1337n, 20n, 2n, 38n)), 14);
assert.equal(Number(Light.block(sources, 1337n, 21n, 2n, 38n)), 0);
const lavaSource = Light.lava_source(20n, 2n, 38n);
const lavaSources = { $: "Con", head: lavaSource, tail: { $: "Nil" } };
assert.equal(Number(Light.block(lavaSources, 1337n, 20n, 2n, 38n)), 15);
assert.equal(Number(Light.block(lavaSources, 1337n, 21n, 2n, 38n)), 0);
const crossChunkSource = { $: "Con", head: Light.source(20n, 15n, 38n), tail: { $: "Nil" } };
const crossChunkFields = Light.source_fields(crossChunkSource, 1337n);
assert.ok(Number(Light.field_light(crossChunkFields, 32n, 15n, 38n, 0)) > 0);
const mixedSources = {
  $: "Con",
  head: Light.source(20n, 15n, 38n),
  tail: { $: "Con", head: Light.source(100n, 15n, 100n), tail: { $: "Nil" } },
};
const localSources = Light.source_fields_chunk(mixedSources, 1337n, 1n, 2n);
assert.ok(Number(Light.field_light(localSources, 20n, 15n, 38n, 0)) > 0);
assert.equal(Number(Light.field_light(localSources, 100n, 15n, 100n, 0)), 0);
const dirtyCells = { $: "Con", head: { $: "Cell", x: 20n, y: 15n, z: 38n }, tail: { $: "Nil" } };
const patch = Light.patch(crossChunkSource, 1337n, dirtyCells);
assert.equal(patch.$, "Con");
const fullLight = Light.chunk(crossChunkSource, 1337n, 1n, 2n);
assert.equal(Number(patch.head.light), Number(fullLight[4 + 16 * (6 + 16 * 15)]));
assert.ok(Number(patch.head.light) >= 14);
const cachedPatch = Light.patch_fields(Light.source_fields_one(Light.source(20n, 15n, 38n), 1337n), 1337n, dirtyCells);
assert.equal(Number(cachedPatch.head.light), Number(patch.head.light));
const mixedPatch = Light.patch(mixedSources, 1337n, dirtyCells);
const mixedFull = Light.chunk(mixedSources, 1337n, 1n, 2n);
assert.equal(Number(mixedPatch.head.light), Number(mixedFull[4 + 16 * (6 + 16 * 15)]));

const surfaceRemoval = {
  $: "Con",
  head: { $: "Edit", x: 38n, y: 7n, z: 22n, block: 0 },
  tail: { $: "Nil" },
};
const surfaceIndex = 6 + 16 * (6 + 16 * 7);
const surfaceBefore = Light.chunk(emptySources, 1337n, 2n, 1n);
const surfaceAfter = Light.chunk_with_edits(emptySources, surfaceRemoval, 1337n, 2n, 1n);
assert.equal(Number(surfaceBefore[surfaceIndex]), 0);
assert.equal(Number(surfaceAfter[surfaceIndex]), 15);
const surfacePatch = Light.patch_fields_with_edits(
  { $: "Nil" },
  surfaceRemoval,
  1337n,
  { $: "Con", head: { $: "Cell", x: 38n, y: 7n, z: 22n }, tail: { $: "Nil" } },
);
assert.equal(Number(surfacePatch.head.light), 15);
console.log("bend light ok");
