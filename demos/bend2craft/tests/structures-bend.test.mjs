import assert from "node:assert/strict";
import Structures from "../world/structures.bend";
import World from "../world/world.bend";

const seed = 1337n;
const villageBase = World.column_height(seed, Structures.village_origin_x(seed), Structures.village_origin_z(seed));
const blocks = [];
for (let y = 0; y < Number(World.max_y()); y += 1) {
  for (let z = 0; z < Number(World.depth()); z += 1) {
    for (let x = 0; x < Number(World.width()); x += 1) {
      const block = Number(Structures.block(seed, BigInt(x), BigInt(y), BigInt(z), villageBase));
      if (block !== 0) blocks.push([x, y, z, block]);
    }
  }
}
assert.ok(blocks.length > 0);
assert.ok(blocks.some(([, , , block]) => block === 11));
assert.ok(blocks.some(([, , , block]) => block === 5));
assert.equal(Number(Structures.block(seed, 27n, 9n, 29n, villageBase)), 13);
assert.equal(Number(Structures.block(seed, 25n, 9n, 23n, villageBase)), 14);
assert.ok(blocks.every(([x, y, z]) => x >= 0 && x < Number(World.width()) && z >= 0 && z < Number(World.depth()) && y >= 0 && y < Number(World.max_y())));
assert.equal(Number(Structures.block(seed, 0n, 0n, 0n, villageBase)), 0);
console.log(JSON.stringify({ structureBlocks: blocks.length }));
