import assert from "node:assert/strict";
import {
  MOB_TILES,
  appendLimb,
  appendMobModel,
  appendTexturedBox,
  createModelArrays,
  facingYaw,
} from "../web/mob-mesh.js";

assert.deepEqual(MOB_TILES, { pigFace: 21, pigSkin: 22, zombieFace: 23, zombieSkin: 24 });
// Compass dir 2 (+x) faces +x; dir 0 faces -z.
assert.ok(Math.abs(facingYaw(0)) < 1e-9);
assert.ok(Math.abs(facingYaw(2) + Math.PI / 2) < 1e-9);

function flatTiles(tile) {
  return { top: tile, bottom: tile, front: tile, back: tile, left: tile, right: tile };
}

// One box emits 12 triangles with positions, colors and uvs in range.
const box = createModelArrays();
appendTexturedBox(box, 0, 1, 0, 1, 1, 1, 0, flatTiles(21), 1);
assert.equal(box.positions.length, 36 * 3);
assert.equal(box.colors.length, 36 * 3);
assert.equal(box.uvs.length, 36 * 2);
assert.ok(box.positions.every((v) => Number.isFinite(v)));
assert.ok(box.uvs.every((v) => v >= 0 && v <= 1));
assert.ok(box.colors.every((c) => c >= 0 && c <= 1));
// Top faces are brightest.
const topColors = box.colors.slice(0, 6 * 3);
assert.ok(Math.max(...topColors) === 1);

// Limbs hang below their pivot and swing toward local -Z (forward).
const limb = createModelArrays();
appendLimb(limb, 0, 1, 0, 0.2, 0.5, 0.2, 0, 0, 0, 22, 1);
const limbYs = limb.positions.filter((_, i) => i % 3 === 1);
assert.ok(Math.max(...limbYs) <= 1.0 + 1e-9);
assert.ok(Math.min(...limbYs) >= 0.5 - 1e-9);
const swung = createModelArrays();
appendLimb(swung, 0, 1, 0, 0.2, 0.5, 0.2, Math.PI / 2, 0, 0, 22, 1);
const swungZs = swung.positions.filter((_, i) => i % 3 === 2);
assert.ok(Math.min(...swungZs) < -0.4);

// Pigs stand on their feet, face their heading and flash on hurt.
const pig = { kind: 1, x: 8.5, y: 1.05, z: 8.5, dir: 2, moving: true, hurtTimer: 0 };
const mesh = createModelArrays();
appendMobModel(mesh, pig, 1, 0);
assert.ok(mesh.positions.length > 300);
const ys = mesh.positions.filter((_, i) => i % 3 === 1);
assert.ok(Math.min(...ys) >= 1.05 - 1e-9);
assert.ok(Math.max(...ys) <= 1.05 + 1.45);
const xs = mesh.positions.filter((_, i) => i % 3 === 0);
assert.ok(Math.max(...xs) > 8.5 + 0.5, "head leads toward +x");
// A hurt pig renders with a hot white tint.
const hurt = { ...pig, hurtTimer: 0.2 };
const flash = createModelArrays();
appendMobModel(flash, hurt, 1, 0);
const calm = createModelArrays();
appendMobModel(calm, pig, 1, 0);
const flashMax = Math.max(...flash.colors);
const calmMax = Math.max(...calm.colors);
assert.ok(flashMax > calmMax);
// Zombies fit their taller hitbox.
const zombie = { kind: 2, x: 0, y: 5, z: 0, dir: 0, moving: false, hurtTimer: 0 };
const zmesh = createModelArrays();
appendMobModel(zmesh, zombie, 1, 0);
const zys = zmesh.positions.filter((_, i) => i % 3 === 1);
assert.ok(Math.max(...zys) <= 5 + 2.05);
assert.ok(Math.min(...zys) >= 5 - 1e-9);
console.log("mob mesh ok");
