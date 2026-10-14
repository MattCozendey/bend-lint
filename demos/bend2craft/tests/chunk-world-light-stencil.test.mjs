import assert from "node:assert/strict";
import { createChunkedWorld } from "../web/chunk-world.js";

// Which cells a block change relights. A light-neutral change (air and water)
// relights only the changed cell; anything else relights the whole stencil.
const SIZE = 4;
const MAX_Y = 4;
const cells = SIZE * SIZE * MAX_Y;
const patched = [];
const cellList = (list) => list.reduceRight((tail, [x, y, z]) => ({ $: "Con", head: { $: "Cell", x: BigInt(x), y: BigInt(y), z: BigInt(z) }, tail }), { $: "Nil" });
const world = createChunkedWorld({
  chunkSize: SIZE,
  maxY: MAX_Y,
  renderRadius: 0,
  initialEdits: "log",
  generateChunk: () => new Array(cells).fill(0),
  generateLightChunk: () => new Array(cells).fill(15),
  generateLightCells: (dirty) => {
    const seen = [];
    for (let node = dirty; node?.$ === "Con"; node = node.tail) seen.push([Number(node.head.x), Number(node.head.y), Number(node.head.z)]);
    patched.push(seen);
    return { $: "Nil" };
  },
  affectedLightCells: (x, y, z) => cellList([[x, y, z], [x + 1, y, z], [x, y, z + 1]]),
  affectedLightSelfCells: (x, y, z) => cellList([[x, y, z]]),
  lightNeutral: (previous, next) => (previous === 0 || previous === 7) && (next === 0 || next === 7),
  applyEdit: (edits, x, y, z, value) => `${edits}+${x},${y},${z}=${value}`,
});
world.loadAround(0, 0);

assert.equal(world.setBlock(1, 2, 1, 7), true);
assert.deepEqual(patched.at(-1), [[1, 2, 1]], "water only relights its own cell");
assert.equal(world.setBlocks([{ x: 1, y: 2, z: 1, value: 0 }, { x: 2, y: 2, z: 1, value: 7 }]), true);
assert.deepEqual(patched.at(-1), [[1, 2, 1], [2, 2, 1]]);
assert.equal(world.setBlock(0, 1, 0, 12), true);
assert.deepEqual(patched.at(-1), [[0, 1, 0], [1, 1, 0], [0, 1, 1]], "a torch relights the stencil");
// A batch with any non-neutral change takes the stencil for all of it.
assert.equal(world.setBlocks([{ x: 1, y: 3, z: 1, value: 7 }, { x: 2, y: 3, z: 2, value: 21 }]), true);
assert.equal(patched.at(-1).length, 6);

console.log("chunk world light stencil ok");
