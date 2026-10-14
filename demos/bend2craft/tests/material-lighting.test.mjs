import assert from "node:assert/strict";
import { TERRAIN_FACE_SHADES, litEntityFaceColor, litFaceColor } from "../web/material-lighting.js";

assert.deepEqual(TERRAIN_FACE_SHADES, [1, 0.68, 0.9, 0.82, 0.96, 0.74]);
assert.ok(Math.min(...TERRAIN_FACE_SHADES) >= 0.68, "voxel faces should retain readable color in ambient daylight");

const top = litFaceColor(0, 1, 15, 1);
const bottom = litFaceColor(1, 1, 15, 1);
const side = litFaceColor(2, 0.8, 8, 0.9);
assert.ok(top[0] > top[2]);
assert.ok(bottom[2] > bottom[0]);
assert.ok(side.every((value) => value >= 0 && value <= 1));
assert.ok(litFaceColor(2, 0.3, 0, 1).every((value) => value < 0.4));
assert.deepEqual(litFaceColor(0, 1, 15, 1), litFaceColor(0, 1, 15, 1));
const nightEntity = litEntityFaceColor([1, 0.8, 0.6], 2, 0.05, 1);
const dayEntity = litEntityFaceColor([1, 0.8, 0.6], 2, 1, 1);
assert.ok(nightEntity.every((value) => value > 0));
assert.ok(dayEntity[0] > nightEntity[0]);
assert.ok(nightEntity.every((value) => value <= 1));
console.log("material lighting ok");
