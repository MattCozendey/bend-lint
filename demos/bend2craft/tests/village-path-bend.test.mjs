import assert from "node:assert/strict";
import Path from "../world/village_path.bend";

const grid = Path.grid(1337n, 9n, 17n, 19n, 28n, 26n);
function listLength(list) {
  let length = 0;
  for (let node = list; node?.$ === "Con"; node = node.tail) length += 1;
  return length;
}
assert.equal(listLength(grid), 26, "pathfinding grid stores one bitmask per row");
const aroundWall = Path.next(grid, 26n, 27n, 20n, 27n, 17n, 19n, 28n, 26n);
assert.equal(aroundWall.found, true);
assert.equal(Number(aroundWall.x), 26);
assert.equal(Number(aroundWall.z), 26);
const blockedTarget = Path.next(grid, 26n, 27n, 21n, 27n, 17n, 19n, 28n, 26n);
assert.equal(blockedTarget.found, false);
const same = Path.next(grid, 26n, 27n, 26n, 27n, 17n, 19n, 28n, 26n);
assert.equal(same.found, true);
assert.equal(Number(same.x), 26);
assert.equal(Number(same.z), 27);
console.log("bend village path ok");
