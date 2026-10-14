import assert from "node:assert/strict";
import {
  canPatchHiddenTerrain,
  quadContainsCell,
} from "../web/terrain-edit-visibility.js";

const mergedTop = {
  faceIndex: 0,
  fixed: 1,
  u: 0,
  v: 0,
  width: 4,
  height: 4,
  x: 0,
  y: 0,
  z: 0,
};
const singleTop = { ...mergedTop, width: 1, height: 1 };
assert.equal(quadContainsCell(mergedTop, 2, 0, 2), true);
assert.equal(canPatchHiddenTerrain([mergedTop], [[2, 0, 2]]), false);
assert.equal(canPatchHiddenTerrain([singleTop], [[2, 0, 2]]), true);
assert.equal(canPatchHiddenTerrain([mergedTop], [[8, 0, 8]]), true);

console.log("terrain edit visibility ok");
