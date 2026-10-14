import assert from "node:assert/strict";
import Dirty from "../world/light-dirty.bend";

function chunksFromList(list) {
  const result = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) {
    result.push([Number(node.head.x), Number(node.head.z)]);
  }
  return result;
}

assert.deepEqual(chunksFromList(Dirty.chunks(32n, 32n, 16n)).sort(), [
  [1, 1], [1, 2], [1, 3],
  [2, 1], [2, 2], [2, 3],
  [3, 1], [3, 2], [3, 3],
].sort());
assert.deepEqual(chunksFromList(Dirty.chunks(0n, 0n, 16n)).sort(), [
  [0, 0], [0, 1], [1, 0], [1, 1],
].sort());
const cells = [];
for (let node = Dirty.cells_radius(8n, 8n, 8n, 1n); node?.$ === "Con"; node = node.tail) {
  cells.push([Number(node.head.x), Number(node.head.y), Number(node.head.z)]);
}
assert.equal(cells.length, 7);
assert.ok(cells.some(([x, y, z]) => x === 8 && y === 8 && z === 8));
const columnCells = [];
for (let node = Dirty.cells_column(8n, 8n, 8n); node?.$ === "Con"; node = node.tail) {
  columnCells.push([Number(node.head.x), Number(node.head.y), Number(node.head.z)]);
}
assert.equal(columnCells.length, 64);
assert.deepEqual(columnCells[0], [8, 63, 8]);
assert.deepEqual(columnCells.at(-1), [8, 0, 8]);
// Air and water are both clear and dark to the light rules: a swap between
// them can only change the swapped cell's own light.
assert.equal(Dirty.light_neutral(0, 7), true);
assert.equal(Dirty.light_neutral(7, 0), true);
assert.equal(Dirty.light_neutral(7, 7), true);
assert.equal(Dirty.light_neutral(0, 1), false, "stone blocks light");
assert.equal(Dirty.light_neutral(0, 12), false, "a torch lights its surroundings");
assert.equal(Dirty.light_neutral(7, 21), false, "lava glows");
const self = [];
for (let node = Dirty.cells_self(8n, 3n, 9n); node?.$ === "Con"; node = node.tail) {
  self.push([Number(node.head.x), Number(node.head.y), Number(node.head.z)]);
}
assert.deepEqual(self, [[8, 3, 9]]);
console.log("bend light dirty chunks ok");
