import assert from "node:assert/strict";
import { buildTerrainVertexArrays } from "../web/terrain-vertex-builder.js";
import { faceColorGrade } from "../web/material-lighting.js";
import { FACE_NORMALS } from "../web/greedy-mesh.js";
import {
  isFireMaterial,
  isLavaMaterial,
  isOpaqueMaterial,
  isWaterMaterial,
  waterDepth,
} from "../web/surface-materials.js";

const quad = {
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
  ao: [1, 1, 1, 1],
};
const opaque = buildTerrainVertexArrays([quad]).opaque;
assert.equal(opaque.positions.length, 18);
assert.equal(opaque.colors.length, 18);
// Lighting is no longer folded into the vertex colour: occlusion and block
// light travel in `lights`, the face normal in `normals`, so the fragment
// shader can light a surface from a real sun direction.
assert.equal(opaque.lights.length, 12);
assert.equal(opaque.normals.length, 18);
assert.equal(opaque.uvs.length, 12);
assert.equal(opaque.materials.length, 6);
assert.equal(opaque.tiles.length, 24);
assert.equal(opaque.quadCount, 1);
assert.deepEqual(Array.from(opaque.positions.slice(0, 3)), [0, 1, 0]);

// The colour channel carries the per-face grade and nothing else, so it must
// equal `faceColorGrade` for that face rather than a shaded colour.
for (const faceIndex of [0, 1, 2, 3, 4, 5]) {
  const built = buildTerrainVertexArrays([{ ...quad, faceIndex }]).opaque;
  const expected = faceColorGrade(faceIndex, quad.x, quad.z);
  assert.ok(
    Array.from(built.colors.slice(0, 3)).every((value, index) => Math.abs(value - expected[index]) < 1e-6),
    `face ${faceIndex} must carry the shared face grade contract`,
  );
  assert.ok(built.colors.every((value) => value > 0.5 && value < 1.5), "a grade is never a light term");
}

// The normal must match the face direction, or the surface cannot be lit.
for (const faceIndex of [0, 1, 2, 3, 4, 5]) {
  const built = buildTerrainVertexArrays([{ ...quad, faceIndex }]).opaque;
  assert.deepEqual(Array.from(built.normals.slice(0, 3)), FACE_NORMALS[faceIndex]);
}

// `lights` is (occlusion, block light 0..1) per corner. A quad emits six
// vertices in the order 0,1,2,0,2,3, so corner 0 appears twice.
const corners = [0.4, 0.6, 0.8, 0.4, 0.8, 1.0];
const occluded = buildTerrainVertexArrays([{ ...quad, ao: [0.4, 0.6, 0.8, 1.0], light: 8 }]).opaque;
assert.equal(occluded.lights.length, 12);
corners.forEach((expectedAo, index) => {
  assert.ok(
    Math.abs(occluded.lights[index * 2] - expectedAo) < 1e-6,
    `vertex ${index} must carry its own corner occlusion`,
  );
  assert.ok(Math.abs(occluded.lights[index * 2 + 1] - 8 / 15) < 1e-6, "block light is constant per quad");
});
const unlit = buildTerrainVertexArrays([{ ...quad, light: 0 }]).opaque;
assert.equal(unlit.lights[1], 0, "a zero light level must stay zero, not clamp to 1");
const missingAo = buildTerrainVertexArrays([{ ...quad, ao: undefined }]).opaque;
assert.equal(missingAo.lights[0], 1, "a missing occlusion value defaults to fully open");

// Occlusion and light must not leak into the colour any more.
const shaded = buildTerrainVertexArrays([{ ...quad, ao: [0.2, 0.2, 0.2, 0.2] }]).opaque;
const unoccluded = buildTerrainVertexArrays([quad]).opaque;
assert.deepEqual(Array.from(shaded.colors), Array.from(unoccluded.colors));

const grassTop = buildTerrainVertexArrays([{ ...quad, block: 3, faceIndex: 0 }]).opaque;
const grassSide = buildTerrainVertexArrays([{ ...quad, block: 3, faceIndex: 2 }]).opaque;
assert.ok(grassTop.tiles[1] < grassTop.tiles[3], "grass top keeps atlas rows top-to-bottom");
assert.ok(grassSide.tiles[1] > grassSide.tiles[3], "grass side flips atlas rows onto the vertical face");

const water = buildTerrainVertexArrays([{ ...quad, block: 7 }]).water;
assert.equal(water.quadCount, 1);
assert.equal(water.positions.length, 18);
assert.equal(water.normals.length, 18, "water carries a normal so the surface can be shaded per pixel");
assert.equal(buildTerrainVertexArrays([quad]).water.quadCount, 0);

// Water carries its sampled column depth inside the material band, so a deeper
// ocean can be tinted without a second vertex attribute.
const shallowWater = buildTerrainVertexArrays([{ ...quad, block: 7, waterDepthCells: 0 }]).water;
const deepWater = buildTerrainVertexArrays([{ ...quad, block: 7, waterDepthCells: 5 }]).water;
assert.equal(shallowWater.materials.length, 6);
assert.ok(isWaterMaterial(shallowWater.materials[0]), "shallow water must stay in the water band");
assert.ok(isWaterMaterial(deepWater.materials[0]), "deep water must stay in the water band");
assert.ok(waterDepth(deepWater.materials[0]) >= 0.99, "a full column must decode to near-full depth");
// The encoding must clamp below 1 so a full-depth quad can never encode 2.0,
// which is the lava band.
assert.ok(waterDepth(deepWater.materials[0]) < 1, "full depth must stay inside the water band");
assert.equal(waterDepth(shallowWater.materials[0]), 0, "a zero depth cell must decode to no depth");
assert.ok(waterDepth(deepWater.materials[0]) > waterDepth(shallowWater.materials[0]));
assert.ok(
  isWaterMaterial(deepWater.materials[0]) && !isLavaMaterial(deepWater.materials[0]) && !isFireMaterial(deepWater.materials[0]),
  "a deep water quad must not spill into the lava or fire band",
);

// Opaque terrain encodes `10 + block` and must never be routed to the fluid
// layer, whatever the fire band looks like.
const stone = buildTerrainVertexArrays([{ ...quad, block: 1 }]);
assert.equal(stone.opaque.quadCount, 1);
assert.equal(stone.water.quadCount, 0);
assert.equal(isOpaqueMaterial(stone.opaque.materials[0]), true);
assert.equal(isFireMaterial(stone.opaque.materials[0]), false, "stone must not match the fire band");

// The builder no longer takes a daylight argument: the mesh must be independent
// of the time of day so it does not have to be rebuilt as the sun moves.
assert.throws(() => buildTerrainVertexArrays("not an array"), TypeError);
assert.equal(buildTerrainVertexArrays.length, 1, "daylight is not a builder input any more");

console.log("terrain vertex builder ok");
