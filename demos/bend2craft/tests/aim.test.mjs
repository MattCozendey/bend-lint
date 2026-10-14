import assert from "node:assert/strict";
import { bodyBox, firstAimedMob, mobBox, rayHitBox } from "../web/aim.js";
import { MOB_KINDS } from "../web/mob-kinds.js";

// Every kind carries its own hitbox height, so a brute can be shot in the head
// and a chicken can be hit at all instead of sharing the pig's box.
for (const entry of MOB_KINDS) {
  assert.equal(mobBox({ kind: entry.kind, x: 0, y: 0, z: -3 }).maxY, entry.height,
    `the ${entry.id} hitbox`);
}
// Zombies stand taller than pigs, so their hitbox is taller.
assert.equal(mobBox({ kind: 1, x: 0, y: 0, z: -3 }).maxY, 1.2);
assert.equal(mobBox({ kind: 2, x: 0, y: 0, z: -3 }).maxY, 1.9);

// Aiming down at a pig from eye height hits; aiming past it misses.
const pig = bodyBox(0, 0, -3, 1.2);
assert.ok(rayHitBox([0, 1.6, 0], [0, -0.2, -1], pig, 8) !== null);
assert.equal(rayHitBox([0, 1.6, 0], [0, 0, 1], pig, 8), null);
assert.equal(rayHitBox([0, 1.6, 0], [0, -0.2, -1], pig, 1), null);

// A level eye ray meets the taller zombie box but sails over the pig.
const zombie = bodyBox(0, 0, -3, 1.9);
assert.ok(rayHitBox([0, 1.6, 0], [0, 0, -1], zombie, 8) !== null);
assert.equal(rayHitBox([0, 1.6, 0], [0, 0, -1], pig, 8), null);

// Facing away along an axis still resolves through slab swapping.
assert.ok(rayHitBox([0, 1.6, -3], [0, -0.2, 1], bodyBox(0, 0, 3, 1.2), 8) !== null);

// Primary-click combat selects the closest mob actually under the crosshair.
const aimedMobs = [
  { kind: 1, x: 0, y: 0, z: -5, alive: true },
  { kind: 2, x: 0, y: 0, z: -2, alive: true },
  { kind: 2, x: 0, y: 0, z: 3, alive: true },
];
assert.equal(firstAimedMob([0, 1.6, 0], [0, 0, -1], aimedMobs, 4)?.z, -2);
assert.equal(firstAimedMob([0, 1.6, 0], [1, 0, 0], aimedMobs, 4), null);
assert.equal(firstAimedMob([0, 1.6, 0], [0, -0.1, -1], [{ ...aimedMobs[0], kind: 2 }], 6)?.z, -5);
console.log("aim ok");
