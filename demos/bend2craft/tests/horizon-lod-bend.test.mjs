import assert from "node:assert/strict";
import Horizon from "../world/horizon.bend";
import World from "../world/world.bend";
import WorldState from "../world/world_state.bend";

// The LOD sampler must describe the same surface the streamed chunks show, so
// the far rings line up with the near terrain: ground height, sand or grass,
// sea water, and the top of the tree canopy.
const MAX_Y = Number(World.max_y());
const SIZE = 16;

function decode(value) {
  const encoded = Number(value);
  return {
    ground: encoded & 0xff,
    surface: (encoded >>> 8) & 0xff,
    canopy: (encoded >>> 16) & 0xff,
    water: ((encoded >>> 24) & 1) === 1,
  };
}

function pointList(points) {
  let list = { $: "Nil" };
  for (let index = points.length - 1; index >= 0; index -= 1) {
    list = { $: "Con", head: { $: "SurfacePoint", x: BigInt(points[index][0]), z: BigInt(points[index][1]) }, tail: list };
  }
  return list;
}

let checkedCanopy = 0;
let checkedWater = 0;
for (const seed of [1337n, 42n]) {
  for (const [chunkX, chunkZ] of [[3, 3], [5, 2], [6, 6], [1000001, 1000002]]) {
    const blocks = WorldState.chunk(seed, BigInt(chunkX), BigInt(chunkZ), WorldState.empty());
    const points = [];
    for (let z = 0; z < SIZE; z += 1) for (let x = 0; x < SIZE; x += 1) points.push([chunkX * SIZE + x, chunkZ * SIZE + z]);
    const samples = Horizon.lod_points(seed, BigInt(points.length), pointList(points));
    points.forEach(([x, z], index) => {
      const sample = decode(samples[index]);
      const localX = x - chunkX * SIZE;
      const localZ = z - chunkZ * SIZE;
      const at = (y) => Number(blocks[localX + SIZE * (localZ + SIZE * y)]);
      const height = Number(World.column_height(seed, BigInt(x), BigInt(z)));
      assert.equal(sample.ground, height, `ground at ${x},${z}`);
      assert.equal(sample.water, World.water_at(seed, BigInt(x), World.sea_level(), BigInt(z)), `water at ${x},${z}`);
      assert.equal(sample.surface, Number(World.terrain_block(seed, BigInt(x), BigInt(height - 1), BigInt(z))), `surface at ${x},${z}`);
      let topLeaf = -1;
      for (let y = MAX_Y - 1; y >= 0; y -= 1) {
        if (at(y) === 4) {
          topLeaf = y;
          break;
        }
      }
      assert.equal(sample.canopy, topLeaf < 0 ? 0 : topLeaf + 1, `canopy at ${x},${z}`);
      if (sample.canopy > 0) checkedCanopy += 1;
      if (sample.water) checkedWater += 1;
    });
  }
}
assert.ok(checkedCanopy > 0, "the fixture must cover canopy columns");

// Water columns are covered too (the spawn plains have a shoreline).
const shore = [];
for (let z = 0; z < 48; z += 1) for (let x = 0; x < 48; x += 1) shore.push([x, z]);
const shoreSamples = Horizon.lod_points(1337n, BigInt(shore.length), pointList(shore));
shore.forEach(([x, z], index) => {
  const sample = decode(shoreSamples[index]);
  assert.equal(sample.water, World.water_at(1337n, BigInt(x), World.sea_level(), BigInt(z)));
  if (sample.water) checkedWater += 1;
});
assert.ok(checkedWater > 0, "the fixture must cover water columns");
console.log(`horizon lod sampler ok (${checkedCanopy} canopy, ${checkedWater} water columns)`);
