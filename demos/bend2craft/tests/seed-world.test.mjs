import assert from "node:assert/strict";
import World from "../world/world.bend";
import { hashSeedText } from "../web/seed.js";

assert.equal(World.default_seed(), 1337n);

const cells = [
  [4n, 7n],
  [19n, 23n],
  [31n, 11n],
  [42n, 37n],
];
const first = cells.map(([x, z]) => Number(World.column_height(1337n, x, z)));
const repeat = cells.map(([x, z]) => Number(World.column_height(1337n, x, z)));
const other = cells.map(([x, z]) => Number(World.column_height(1338n, x, z)));

assert.deepEqual(first, repeat);
assert.notDeepEqual(first, other);
const spawn = World.spawn_cell(1337n);
assert.equal(World.tree_at(1337n, spawn.x, spawn.z), false);
assert.equal(Number(World.block(1337n, spawn.x, spawn.height, spawn.z)), 0);
// The spawn cell must have room to walk: the 3x3 neighborhood at feet and
// head height must be free, otherwise W only moves along walls/alleys.
const spawnSeeds = [1337n, 1n, 7n, 42n, 9999n];
for (const seed of spawnSeeds) {
  const cell = World.spawn_cell(seed);
  const sx = Number(cell.x);
  const sz = Number(cell.z);
  const sh = Number(cell.height);
  assert.ok(sx >= 1 && sx < 47 && sz >= 1 && sz < 47, `spawn has a 3x3 margin for seed ${seed}`);
  for (let dz = -1; dz <= 1; dz += 1) {
    for (let dx = -1; dx <= 1; dx += 1) {
      for (let dy = 0; dy <= 1; dy += 1) {
        assert.equal(
          Number(World.block(seed, BigInt(sx + dx), BigInt(sh + dy), BigInt(sz + dz))),
          0,
          `spawn area blocked at (${sx + dx},${sh + dy},${sz + dz}) for seed ${seed}`,
        );
      }
    }
  }
}
const textSeed = hashSeedText("collision-smoke");
assert.doesNotThrow(() => World.chunk(textSeed, 0n, 0n));
let lavaCells = 0;
for (let y = 1; y <= 3; y += 1) {
  for (let z = 0; z < 48; z += 1) {
    for (let x = 0; x < 48; x += 1) {
      if (!World.lava_at(1337n, BigInt(x), BigInt(y), BigInt(z))) continue;
      lavaCells += 1;
      assert.equal(Number(World.block(1337n, BigInt(x), BigInt(y), BigInt(z))), 21);
    }
  }
}
assert.ok(lavaCells > 0);
console.log(JSON.stringify({ seed: 1337, first, other }));
