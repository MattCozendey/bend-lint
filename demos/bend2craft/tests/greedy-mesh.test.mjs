import assert from "node:assert/strict";
import {
  LEAF_FACE_INSET,
  buildGreedyQuads,
  quadCorners,
} from "../web/greedy-mesh.js";

function meshFor(entries, active = () => true) {
  const blocks = new Map(entries.map(([x, y, z, block]) => [`${x},${y},${z}`, block]));
  return buildGreedyQuads({
    forEachLoadedBlock(callback) {
      for (const [key, block] of blocks) {
        const [x, y, z] = key.split(",").map(Number);
        callback(x, y, z, block);
      }
    },
    blockAt: (x, y, z) => blocks.get(`${x},${y},${z}`) ?? 0,
    isActive: active,
  });
}

const flat = meshFor([
  [0, 0, 0, 1], [1, 0, 0, 1],
  [0, 0, 1, 1], [1, 0, 1, 1],
]);
assert.equal(flat.blockCount, 4);
assert.equal(flat.quads.length, 6);
const top = flat.quads.find((quad) => quad.faceIndex === 0);
assert.deepEqual(
  { width: top.width, height: top.height, block: top.block },
  { width: 2, height: 2, block: 1 },
);
assert.equal(top.ao.length, 4);
assert.ok(top.ao.every((value) => value >= 0 && value <= 1));
const occludedTop = meshFor([
  [-1, 0, 0, 2], [0, 0, -1, 2], [-1, 0, -1, 2], [0, 0, 0, 1],
  [-1, 1, 0, 1], [0, 1, -1, 1], [-1, 1, -1, 1],
]).quads.find((quad) => quad.faceIndex === 0 && quad.block === 1);
assert.ok(occludedTop.ao.some((value) => value < 1));
const canopyTop = meshFor([
  [0, 0, 0, 3], [1, 1, 0, 4],
]).quads.find((quad) => quad.faceIndex === 0 && quad.block === 3);
assert.ok(canopyTop.ao.some((value) => value < 0.8), "ground beneath a leaf canopy needs visible ambient occlusion");

const differentBlocks = meshFor([
  [0, 0, 0, 1], [1, 0, 0, 2],
  [0, 0, 1, 1], [1, 0, 1, 2],
]);
assert.equal(differentBlocks.blockCount, 4);
assert.equal(differentBlocks.quads.filter((quad) => quad.faceIndex === 0).length, 2);

const variantPatch = meshFor([
  [0, 0, 0, 22], [1, 0, 0, 22],
]);
assert.equal(
  variantPatch.quads.filter((quad) => quad.faceIndex === 0).length,
  2,
  "different deterministic texture variants must not be merged",
);

const aoPatch = meshFor([
  [0, 0, 0, 1], [1, 0, 0, 1], [0, 1, 1, 1],
]);
assert.equal(
  aoPatch.quads.filter((quad) => quad.faceIndex === 0 && quad.block === 1 && quad.y === 0).length,
  2,
  "different top-face ambient occlusion signatures must not be merged",
);

// The counterpart of the leaf exemption below, and the reason the terrain
// surface may not be vertex-animated: a flat grass plain collapses into a
// single quad with four corners, so a world-space field sampled at those
// corners can only tilt the quad. A large plain would then read as a few big
// facets rolling like swell instead of as ground rippling in the wind.
const grassPlain = [];
for (let x = 0; x < 8; x += 1) {
  for (let z = 0; z < 8; z += 1) grassPlain.push([x, 0, z, 3]);
}
const grassTops = meshFor(grassPlain).quads.filter((quad) => quad.faceIndex === 0 && quad.block === 3);
assert.equal(grassTops.length, 1, "a flat grass plain must merge into one quad");
assert.deepEqual(
  { width: grassTops[0].width, height: grassTops[0].height },
  { width: 8, height: 8 },
  "the merged grass quad carries four corners for the whole plain",
);

const leafPatch = meshFor([
  [0, 0, 0, 4], [1, 0, 0, 4],
  [0, 0, 1, 4], [1, 0, 1, 4],
]);
const leafTops = leafPatch.quads.filter((quad) => quad.faceIndex === 0 && quad.block === 4);
assert.equal(leafTops.length, 4, "leaf cells must not collapse into a giant merged canopy quad");
assert.ok(leafTops.every((quad) => quad.width === 1 && quad.height === 1));
const leafTopCorners = quadCorners(leafTops[0]);
assert.equal(leafTopCorners[0][0], LEAF_FACE_INSET);
assert.equal(leafTopCorners[0][2], LEAF_FACE_INSET);
assert.equal(leafTopCorners[2][0], 1 - LEAF_FACE_INSET);
const leafSideCorners = quadCorners(leafPatch.quads.find((quad) => quad.faceIndex === 2 && quad.block === 4));
assert.equal(leafSideCorners[0][1], LEAF_FACE_INSET);
assert.equal(leafSideCorners[2][1], 1 - LEAF_FACE_INSET);

const westFace = quadCorners({ faceIndex: 3, fixed: 0, u: 2, v: 3, width: 1, height: 1, block: 1 });
assert.deepEqual(westFace, [
  [0, 4, 3],
  [0, 4, 2],
  [0, 3, 2],
  [0, 3, 3],
], "west faces must keep a planar, consistently wound corner order");

const inactiveNeighbor = meshFor([[0, 0, 0, 1]], (x, z) => x === 0 && z === 0);
assert.equal(inactiveNeighbor.quads.length, 6);
const farmlandTop = quadCorners({ faceIndex: 0, fixed: 1, u: 0, v: 0, width: 1, height: 1, block: 20 });
assert.equal(farmlandTop[0][1], 15 / 16);
const waterTop = quadCorners({ faceIndex: 0, fixed: 1, u: 0, v: 0, width: 1, height: 1, block: 7 });
assert.equal(waterTop[0][1], 14 / 16);
const lavaTop = quadCorners({ faceIndex: 0, fixed: 1, u: 0, v: 0, width: 1, height: 1, block: 21 });
assert.equal(lavaTop[0][1], 14 / 16);

// Terrain under water keeps its top face; the water bottom stays culled.
const lakebed = meshFor([[0, 0, 0, 1], [0, 1, 0, 7]]);
const lakebedTop = lakebed.quads.filter((quad) => quad.faceIndex === 0 && quad.block === 1);
assert.equal(lakebedTop.length, 1);
assert.equal(lakebed.quads.filter((quad) => quad.faceIndex === 1 && quad.block === 7).length, 0);

// Water against water stays culled; only the upper surface renders.
const stackedWater = meshFor([[0, 1, 0, 7], [0, 2, 0, 7]]);
assert.equal(stackedWater.quads.filter((quad) => quad.faceIndex === 0 && quad.block === 7 && quad.fixed === 2).length, 0);
assert.equal(stackedWater.quads.filter((quad) => quad.faceIndex === 0 && quad.block === 7 && quad.fixed === 3).length, 1);
const stackedLava = meshFor([[0, 1, 0, 21], [0, 2, 0, 21]]);
assert.equal(stackedLava.quads.filter((quad) => quad.faceIndex === 0 && quad.block === 21 && quad.fixed === 2).length, 0);

// Opaque faces against water render instead of being culled.
const shoreline = meshFor([[0, 0, 0, 1], [1, 0, 0, 7]]);
assert.equal(shoreline.quads.filter((quad) => quad.faceIndex === 2 && quad.block === 1).length, 1);
console.log("greedy mesh ok");
