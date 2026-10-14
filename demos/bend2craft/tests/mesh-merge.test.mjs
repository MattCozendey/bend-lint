import assert from "node:assert/strict";
import { mergeChunkQuads } from "../web/mesh-merge.js";

const base = {
  faceIndex: 0,
  fixed: 1,
  u: 0,
  v: 0,
  width: 1,
  height: 1,
  block: 1,
  x: 0,
  y: 0,
  z: 0,
  light: 15,
  tile: 1,
  ao: [1, 1, 1, 1],
};
const adjacent = { ...base, u: 1, x: 1 };
const differentAo = { ...adjacent, ao: [0.55, 0.7, 0.7, 0.55] };
const differentVariant = { ...adjacent, tile: 36 };
const nearAo = { ...adjacent, ao: [0.9, 0.9, 0.9, 0.9] };
const leaf = { ...base, block: 4, tile: 4 };
const adjacentLeaf = { ...leaf, u: 1, x: 1 };

assert.equal(mergeChunkQuads([base, differentAo]).length, 2, "AO changes must split a merged face");
assert.equal(mergeChunkQuads([base, differentVariant]).length, 2, "texture variants must split a merged face");
assert.equal(mergeChunkQuads([base, nearAo]).length, 1, "small AO differences may merge to protect fill rate");
assert.equal(mergeChunkQuads([leaf, adjacentLeaf]).length, 2, "leaf cells must not merge across chunk boundaries");
assert.equal(mergeChunkQuads([base, adjacent]).length, 1, "matching flat faces should still merge");

console.log("mesh merge ok");
