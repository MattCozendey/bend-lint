import assert from "node:assert/strict";
import World from "../world/world.bend";

// The per-cell rule and the fast per-chunk path must carve one world: a sampled
// cross-check over three chunks, including cave rows, is what says so.
//
// The one documented difference is lava: `World.block` reports the generated
// lava pockets (`World.lava_at`), while the chunk path leaves those cells to the
// fluid simulation, which places lava as it flows. Every other block id must be
// the same answer from both paths.
const chunkSize = Number(World.chunk_size());
const maxY = Number(World.max_y());
const LAVA = 21;
let compared = 0;
let caves = 0;
let lavaCells = 0;
for (const [cx, cz] of [[0, 0], [2, 2], [5, 9]]) {
  const chunk = World.chunk(1337n, BigInt(cx), BigInt(cz));
  assert.equal(chunk.length, chunkSize * chunkSize * maxY);
  for (let lz = 0; lz < chunkSize; lz += 1) {
    for (let lx = 0; lx < chunkSize; lx += 1) {
      const wx = cx * chunkSize + lx;
      const wz = cz * chunkSize + lz;
      for (let y = 0; y < 32; y += 1) {
        const fromChunk = Number(chunk[lx + chunkSize * (lz + chunkSize * y)]);
        const fromBlock = Number(World.block(1337n, BigInt(wx), BigInt(y), BigInt(wz)));
        if (fromBlock === LAVA && fromChunk !== LAVA) {
          lavaCells += 1;
          continue;
        }
        assert.equal(fromChunk, fromBlock, `cell ${wx},${y},${wz}: chunk ${fromChunk}, block ${fromBlock}`);
        compared += 1;
        if (fromBlock === 0 && y > 1 && y < Number(World.column_height(1337n, BigInt(wx), BigInt(wz))) - 2) caves += 1;
      }
    }
  }
}
assert.ok(compared > 20000, `the cross-check must cover thousands of cells, did ${compared}`);
assert.ok(caves > 0, "the sampled region must contain cave air");
console.log(`world block/chunk agreement ok (${compared} cells, ${caves} cave cells, ${lavaCells} lava cells left to the simulation)`);