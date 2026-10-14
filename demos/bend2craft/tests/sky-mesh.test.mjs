import assert from "node:assert/strict";
import { SKY_RADIUS, skyBodies, starPosition } from "../web/sky-mesh.js";

assert.equal(SKY_RADIUS, 22);
assert.deepEqual(starPosition(7, SKY_RADIUS), starPosition(7, SKY_RADIUS));
for (const i of [0, 1, 42, 129]) {
  assert.ok(starPosition(i, SKY_RADIUS)[1] > 0);
}

const eye = [24, 14, 24];
// Noon carries the sun but no stars; midnight carries stars and the moon.
const noon = skyBodies(eye, 0.25);
assert.ok(noon.length >= 1);
assert.ok(noon.every((b) => b.size < 5));
const midnight = skyBodies(eye, 0.75);
assert.ok(midnight.length > noon.length + 100);
const sun = noon.find((b) => b.size > 1);
assert.deepEqual(sun.color, [1, 0.85, 0.4]);
const moon = midnight.find((b) => b.size > 1);
assert.deepEqual(moon.color, [0.85, 0.9, 1]);
// Every body stays within the fog-free range around the eye.
for (const body of [...noon, ...midnight]) {
  const dist = Math.hypot(body.center[0] - eye[0], body.center[1] - eye[1], body.center[2] - eye[2]);
  assert.ok(dist <= SKY_RADIUS + 1, "sky body inside fog-free range");
}
console.log("sky mesh ok");
