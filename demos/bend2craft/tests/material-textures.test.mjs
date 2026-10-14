import assert from "node:assert/strict";
import {
  MATERIAL_PAINTERS,
  MaterialSurface,
  createRandom,
  fbm,
  gradientNoise,
  hexToRgb,
  materialSeed,
  paintMaterial,
  worley,
} from "../web/material-textures.js";
import { ATLAS_TEXTURES } from "../web/texture-atlas.js";

// Tileable noise: the lattice wraps at its period, so a tile sampled at an
// integer frequency has no seam. This is the property every ground material
// depends on, because the same tile is repeated across every block.
for (const [x, y] of [[0.3, 0.7], [2.9, 1.1], [3.5, 0.25]]) {
  const a = gradientNoise(x, y, 4, 4, 17);
  assert.ok(Math.abs(a - gradientNoise(x + 4, y, 4, 4, 17)) < 1e-9, "gradient noise must wrap along x");
  assert.ok(Math.abs(a - gradientNoise(x, y + 4, 4, 4, 17)) < 1e-9, "gradient noise must wrap along y");
  assert.ok(Math.abs(gradientNoise(x, y, 6, 2, 3) - gradientNoise(x + 6, y + 2, 6, 2, 3)) < 1e-9, "anisotropic periods must wrap independently");
}
for (let index = 0; index < 400; index += 1) {
  const value = gradientNoise(index * 0.173, index * 0.311, 8, 8, 5);
  assert.ok(value >= -1 && value <= 1, `gradient noise left -1..1: ${value}`);
}
assert.ok(Math.abs(fbm(0.02, 0.4, 3, 3, 5, 9) - fbm(1.02, 0.4, 3, 3, 5, 9)) < 1e-9, "fbm must tile over one unit");
assert.ok(Math.abs(fbm(0.4, 0.02, 3, 5, 4, 9) - fbm(0.4, 1.02, 3, 5, 4, 9)) < 1e-9, "fbm must tile over one unit in v");

// Worley must be deterministic and tile, since a stone at the tile edge has to
// be the same stone on the other side of the seam.
const cellA = worley(0.01, 0.5, 4, 11, {});
const cellB = worley(1.01, 0.5, 4, 11, {});
assert.ok(Math.abs(cellA.f1 - cellB.f1) < 1e-9 && cellA.id === cellB.id, "worley must wrap");
assert.ok(cellA.f2 >= cellA.f1, "the second-nearest feature cannot be nearer than the nearest");

const randomA = createRandom(5);
const randomB = createRandom(5);
for (let index = 0; index < 10; index += 1) {
  const value = randomA();
  assert.equal(value, randomB(), "the scatter stream must be deterministic");
  assert.ok(value >= 0 && value < 1);
}
assert.equal(materialSeed("stone"), materialSeed("stone"));
assert.notEqual(materialSeed("stone"), materialSeed("stone_variant"));
assert.deepEqual([...hexToRgb("#ff8000")], [1, 128 / 255, 0]);
assert.throws(() => hexToRgb("red"), /Invalid palette colour/);

// The baked relief must be lit from the upper left. A raised disc has to come
// out brighter on its upper-left flank than on its lower-right one; this was
// inverted once, which turned every pebble into a crater and every
// cobblestone into a dent.
const surface = new MaterialSurface(32);
surface.each((x, y, u, v, index) => {
  const distance = Math.hypot(x + 0.5 - 16, y + 0.5 - 16);
  surface.set(index, [0.5, 0.5, 0.5], distance < 8 ? Math.sqrt(1 - (distance / 8) ** 2) : 0);
});
surface.emboss(0.8, 0);
const upperLeft = surface.color[(11 * 32 + 11) * 3];
const lowerRight = surface.color[(20 * 32 + 20) * 3];
assert.ok(upperLeft > 0.5 && lowerRight < 0.5, `the upper-left flank must be lit (${upperLeft} vs ${lowerRight})`);

// Strokes wrap across the edge of a tileable surface and clamp on a
// non-tileable one.
const wrapping = new MaterialSurface(16);
wrapping.stroke(14, 8, 18, 8, 2, 2, (t, across, out) => { out[0] = 1; out[1] = 1; out[2] = 1; return out; }, () => 1);
assert.ok(wrapping.color[(8 * 16 + 1) * 3] > 0.5, "a stroke crossing the edge must continue on the other side");
const clamped = new MaterialSurface(16);
clamped.wrapX = false;
clamped.stroke(14, 8, 18, 8, 2, 2, (t, across, out) => { out[0] = 1; out[1] = 1; out[2] = 1; return out; }, () => 1);
assert.equal(clamped.color[(8 * 16 + 1) * 3], 0, "a stroke must not wrap on a non-tileable surface");

// Every painter the atlas names is deterministic, fills the tile, stays in
// range and depends on its seed.
const usedPainters = new Set(ATLAS_TEXTURES.map((texture) => texture.painter));
for (const name of Object.keys(MATERIAL_PAINTERS)) {
  assert.ok(usedPainters.has(name), `painter ${name} is registered but no atlas tile uses it`);
}
for (const texture of ATLAS_TEXTURES.filter((entry, index, list) => list.findIndex((other) => other.painter === entry.painter) === index)) {
  const options = { opacity: texture.opacity, options: texture.options };
  const first = paintMaterial(texture.painter, 32, texture.seed, texture.palette, options);
  const second = paintMaterial(texture.painter, 32, texture.seed, texture.palette, options);
  assert.equal(first.length, 32 * 32 * 4);
  assert.deepEqual(first, second, `${texture.painter} must be deterministic`);
  const reseeded = paintMaterial(texture.painter, 32, texture.seed + 1, texture.palette, options);
  assert.notDeepEqual(first, reseeded, `${texture.painter} must depend on its seed`);
  const alpha = Math.round(texture.opacity * 255);
  for (let index = 3; index < first.length; index += 4) assert.equal(first[index], alpha);
}

assert.throws(() => paintMaterial("marble", 16, 1, {}), /Unknown material painter/);
assert.throws(() => paintMaterial("stone", 16, 1, { base: "#808080" }), /needs palette colour/);

console.log("material textures ok");
