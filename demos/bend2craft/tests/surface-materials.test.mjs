import assert from "node:assert/strict";
import {
  SURFACE_MATERIAL_FIRE,
  SURFACE_MATERIAL_LAVA,
  SURFACE_MATERIAL_WATER,
  movesSurfaceGeometry,
  surfaceMaterial,
} from "../web/surface-materials.js";

assert.equal(surfaceMaterial(7), SURFACE_MATERIAL_WATER);
assert.equal(surfaceMaterial(21), SURFACE_MATERIAL_LAVA);
assert.equal(surfaceMaterial(24), SURFACE_MATERIAL_FIRE);
assert.equal(surfaceMaterial(1), 11);
assert.equal(movesSurfaceGeometry(SURFACE_MATERIAL_WATER), true);
assert.equal(movesSurfaceGeometry(SURFACE_MATERIAL_LAVA), false);
assert.equal(movesSurfaceGeometry(SURFACE_MATERIAL_FIRE), false);
console.log("surface materials ok");
