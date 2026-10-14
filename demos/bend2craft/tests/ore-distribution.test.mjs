import assert from "node:assert/strict";
import World from "../world/world.bend";

// Ores are placed where vanilla places them: each one in the band of the column
// it generates in, at the density vanilla's ore table gives it, and in veins
// rather than as one block per hash. The bands and the densities below are read
// off https://minecraft.wiki/w/Ore_(feature) (Java 1.18+), which is the table
// the game models:
//
//   ore     band (layers above bedrock)   vein   tries/chunk   blocks/chunk
//   coal    0..192                        17     20            ~280
//   iron    -64..72                        9     10            ~60
//   diamond -64..16                        4     7             ~20
//
// This world's rock is shallow (a column is five to eighteen cells tall, sea
// level 7), so a vanilla band is taken as a fraction of the column: diamond in
// the bottom quarter, and coal and iron through the whole column. The densities
// are vanilla's per rock cell, which is what a digger feels: about 1.7% coal,
// 0.4% iron and 0.13% diamond.
//
// The sample is the fast per-chunk path over eight chunks by eight, and every
// block it reads is compared with `World.block` by tests/world-block-chunk.test.mjs.

const CHUNK = Number(World.chunk_size());
const MAX_Y = Number(World.max_y());
const SEED = 1337n;
const COAL = 8;
const IRON = 9;
const DIAMOND = 10;

const bands = new Map([
  [COAL, "whole column"],
  [IRON, "whole column"],
  [DIAMOND, "bottom quarter"],
]);

const counts = new Map();
const rockCells = { total: 0, byOre: new Map() };
let bandViolations = 0;
let nearSurfaceCoal = 0;
let nearSurfaceIron = 0;

for (let cz = 0; cz < 8; cz += 1) {
  for (let cx = 0; cx < 8; cx += 1) {
    const chunk = World.chunk(SEED, BigInt(cx), BigInt(cz));
    for (let lz = 0; lz < CHUNK; lz += 1) {
      for (let lx = 0; lx < CHUNK; lx += 1) {
        const wx = cx * CHUNK + lx;
        const wz = cz * CHUNK + lz;
        const height = Number(World.column_height(SEED, BigInt(wx), BigInt(wz)));
        for (let y = 1; y < height - 3; y += 1) {
          const block = Number(chunk[lx + CHUNK * (lz + CHUNK * y)]);
          rockCells.total += 1;
          if (block !== COAL && block !== IRON && block !== DIAMOND) continue;
          counts.set(block, (counts.get(block) || 0) + 1);
          // The band: the cell must sit where the ore generates, measured from
          // the floor of the column. Diamond is the only one with a band of its
          // own, and a diamond above the bottom quarter of the rock is a bug.
          if (block === DIAMOND && y * 4 > height) bandViolations += 1;
          // The top two rock cells are "close to the surface".
          if (y >= height - 5) {
            if (block === COAL) nearSurfaceCoal += 1;
            if (block === IRON) nearSurfaceIron += 1;
          }
        }
      }
    }
  }
}

const share = (ore) => (counts.get(ore) || 0) / rockCells.total;
const within = (value, target, tolerance, what) => {
  assert.ok(
    value > target * (1 - tolerance) && value < target * (1 + tolerance),
    `${what}: ${(value * 100).toFixed(3)}% of the rock, wanted ${(target * 100).toFixed(2)}% +/- ${tolerance * 100}%`,
  );
};

assert.ok(rockCells.total > 50000, `the sample must cover the rock of many chunks, got ${rockCells.total} cells`);
assert.equal(bandViolations, 0, `${bandViolations} diamond cells sit above the bottom quarter of their column`);
assert.ok((counts.get(DIAMOND) || 0) > 40, `the sample must hold diamond, got ${counts.get(DIAMOND) || 0}`);
assert.ok((counts.get(IRON) || 0) > 40, `the sample must hold iron, got ${counts.get(IRON) || 0}`);
assert.ok((counts.get(COAL) || 0) > 200, `the sample must hold coal, got ${counts.get(COAL) || 0}`);

within(share(COAL), 0.017, 0.35, "coal");
within(share(IRON), 0.0037, 0.5, "iron");
within(share(DIAMOND), 0.0013, 0.7, "diamond");
assert.ok(share(DIAMOND) < share(IRON), "diamond is rarer than iron");
assert.ok(share(IRON) < share(COAL), "iron is rarer than coal");

// Coal and iron generate through the whole column, so a digger meets both a
// cell or two under the surface.
assert.ok(nearSurfaceCoal > 20, `coal close to the surface, got ${nearSurfaceCoal}`);
assert.ok(nearSurfaceIron > 3, `iron close to the surface, got ${nearSurfaceIron}`);

// A vein is several blocks, so most ore cells have an ore beside them. One hash
// per cell with no vein shares almost none. The neighbours are read from the
// world, so a vein that straddles a chunk edge still counts.
{
  let withNeighbour = 0;
  let total = 0;
  for (const [cx, cz] of [[0, 0], [0, 3], [1, 7], [3, 1], [6, 6], [7, 1]]) {
    for (let lz = 0; lz < CHUNK; lz += 1) {
      for (let lx = 0; lx < CHUNK; lx += 1) {
        for (let y = 1; y < 20; y += 1) {
          const block = Number(World.block(SEED, BigInt(cx * CHUNK + lx), BigInt(y), BigInt(cz * CHUNK + lz)));
          if (block !== COAL && block !== IRON && block !== DIAMOND) continue;
          total += 1;
          const near = (dx, dy, dz) => {
            const other = Number(World.block(
              SEED,
              BigInt(cx * CHUNK + lx + dx),
              BigInt(y + dy),
              BigInt(cz * CHUNK + lz + dz),
            ));
            return other === COAL || other === IRON || other === DIAMOND;
          };
          if (near(-1, 0, 0) || near(1, 0, 0) || near(0, -1, 0) || near(0, 1, 0)) withNeighbour += 1;
        }
      }
    }
  }
  assert.ok(total > 60, `the clumping sample must hold ore, got ${total}`);
  assert.ok(
    withNeighbour / total > 0.5,
    `ore must come in veins: only ${withNeighbour} of ${total} cells have an ore beside them`,
  );
}

console.log(
  `ore distribution ok (rock ${rockCells.total} cells: coal ${(share(COAL) * 100).toFixed(2)}%, `
    + `iron ${(share(IRON) * 100).toFixed(2)}%, diamond ${(share(DIAMOND) * 100).toFixed(2)}%; `
    + `bands ${[...bands].map(([ore, band]) => `${ore}:${band}`).join(", ")})`,
);
