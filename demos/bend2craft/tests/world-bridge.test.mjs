import assert from "node:assert/strict";
import World from "../world/world.bend";

const width = Number(World.width());
const depth = Number(World.depth());
const maxY = Number(World.max_y());
const chunkSize = Number(World.chunk_size());
const seaLevel = Number(World.sea_level());
assert.equal(width, 48);
assert.equal(depth, 48);
assert.equal(maxY, 64);
assert.equal(chunkSize, 16);
assert.equal(seaLevel, 7);
assert.equal(Number(World.biome_at(1337n, 40n, 40n)), 0);
const spawn = World.spawn_cell(1337n);
assert.ok(spawn.x >= 0n && spawn.x < width, "spawn should remain inside the world");
assert.ok(spawn.z >= 0n && spawn.z < depth, "spawn should remain inside the world");
assert.equal(World.spawn_clear(1337n, spawn.x, spawn.z), true, "spawn contract should return a validated clearing");
for (let dz = -7n; dz <= 7n; dz += 1n) {
  for (let dx = -7n; dx <= 7n; dx += 1n) {
    assert.equal(
      World.tree_at(1337n, spawn.x + dx, spawn.z + dz),
      false,
      `spawn must keep a broad tree-free clearing at ${spawn.x},${spawn.z}`,
    );
  }
}
for (const seed of [0n, 1n, 42n, 9999n, 123456n]) {
  const candidate = World.spawn_cell(seed);
  assert.equal(World.spawn_clear(seed, candidate.x, candidate.z), true, `seed ${seed} should produce a validated spawn`);
}
const generatedChunk = World.chunk(1337n, 2n, 2n);
assert.equal(Array.isArray(generatedChunk), true);
assert.equal(generatedChunk.length, 16384);
const chunkIndex = (x, y, z) => x + chunkSize * (z + chunkSize * y);
assert.equal(Number(generatedChunk[chunkIndex(3, 7, 3)]), Number(World.block(1337n, 35n, 7n, 35n)));
assert.equal(Number(generatedChunk[chunkIndex(0, 0, 0)]), Number(World.block(1337n, 32n, 0n, 32n)));

let grass = 0;
let leaves = 0;
let wood = 0;
let sand = 0;
let water = 0;
let coalOre = 0;
let ironOre = 0;
let diamondOre = 0;
const heights = new Set();
for (let y = 0; y < maxY; y += 1) {
  for (let z = 0; z < depth; z += 1) {
    for (let x = 0; x < width; x += 1) {
      const block = Number(World.block(1337n, BigInt(x), BigInt(y), BigInt(z)));
      if (block === 3) grass += 1;
      if (block === 4) leaves += 1;
      if (block === 5) wood += 1;
      if (block === 6) sand += 1;
      if (block === 7) water += 1;
      if (block === 8) coalOre += 1;
      if (block === 9) ironOre += 1;
      if (block === 10) diamondOre += 1;
    }
  }
}
for (let z = 0; z < depth; z += 1) {
  for (let x = 0; x < width; x += 1) {
    heights.add(Number(World.column_height(1337n, BigInt(x), BigInt(z))));
  }
}
assert.ok(grass > 0);
assert.ok(wood > 0);
assert.ok(leaves > 0);
let shorelineFound = false;
for (let z = 1; z < depth - 1 && !shorelineFound; z += 1) {
  for (let x = 1; x < width - 1; x += 1) {
    const h = Number(World.column_height(1337n, BigInt(x), BigInt(z)));
    const lowerNeighbor = [World.column_height(1337n, BigInt(x - 1), BigInt(z)), World.column_height(1337n, BigInt(x + 1), BigInt(z)), World.column_height(1337n, BigInt(x), BigInt(z - 1)), World.column_height(1337n, BigInt(x), BigInt(z + 1))]
      .some((neighbor) => Number(neighbor) < h);
    if (h === seaLevel + 1 && lowerNeighbor) {
      assert.equal(Number(World.block(1337n, BigInt(x), BigInt(h - 1), BigInt(z))), 6);
      shorelineFound = true;
      break;
    }
  }
}
assert.equal(shorelineFound, true, "world generation should create a sand shoreline beside lower water");
assert.ok(sand > 0);
assert.ok(water > 0);
assert.ok(coalOre > 0);
assert.ok(ironOre > 0);
assert.ok(diamondOre > 0);
assert.ok(heights.size >= 3);
const heightList = [...heights];
assert.ok(Math.max(...heightList) - Math.min(...heightList) <= 4);

let farTree = null;
for (let z = 48; z < 80 && farTree === null; z += 1) {
  for (let x = 48; x < 80; x += 1) {
    const bx = BigInt(x);
    const bz = BigInt(z);
    const isolated = !World.tree_at(1337n, bx - 1n, bz)
      && !World.tree_at(1337n, bx + 1n, bz)
      && !World.tree_at(1337n, bx, bz - 1n)
      && !World.tree_at(1337n, bx, bz + 1n);
    if (World.tree_at(1337n, bx, bz) && isolated) {
      farTree = { x: bx, z: bz };
      break;
    }
  }
}
assert.notEqual(farTree, null);
const treeX = farTree.x;
const treeZ = farTree.z;
const treeGround = World.column_height(1337n, treeX, treeZ);
assert.equal(
  Number(World.block(1337n, treeX + 1n, treeGround + 2n, treeZ + 1n)),
  4,
  "the lower canopy should form a full supporting crown",
);
assert.equal(
  Number(World.block(1337n, treeX + 1n, treeGround + 3n, treeZ + 1n)),
  0,
  "the upper canopy must not remain a solid 3x3 slab",
);
assert.equal(
  Number(World.block(1337n, treeX + 1n, treeGround + 3n, treeZ)),
  4,
  "the upper canopy should retain an arm",
);
assert.equal(
  Number(World.block(1337n, treeX, treeGround + 3n, treeZ)),
  4,
  "the upper canopy should retain its center",
);
const biomes = new Set();
for (let z = 96; z < 256; z += 16) {
  for (let x = 96; x < 256; x += 16) biomes.add(Number(World.biome_at(1337n, BigInt(x), BigInt(z))));
}
assert.ok(biomes.size >= 3);
console.log(JSON.stringify({ width, depth, maxY, chunkSize, seaLevel, grass, wood, leaves, sand, water, coalOre, ironOre, diamondOre, heights: heights.size }));
