import assert from "node:assert/strict";
import { cameraMotion, waterWave } from "../web/visual-motion.js";

const idle = cameraMotion(2.0, {
  speed: 0,
  grounded: true,
  verticalVelocity: 0,
});
assert.deepEqual(idle, {
  bob: 0,
  sway: 0,
  roll: 0,
  stride: 0,
});

const walking = cameraMotion(0.25, {
  speed: 4.5,
  grounded: true,
  verticalVelocity: 0,
});
assert.ok(Math.abs(walking.bob) > 0.001);
assert.ok(Math.abs(walking.sway) > 0.001);
assert.ok(Math.abs(walking.roll) > 0.0001);
assert.equal(walking.stride, 1);

const airborne = cameraMotion(0.25, {
  speed: 4.5,
  grounded: false,
  verticalVelocity: 4,
});
assert.equal(airborne.bob, 0);
assert.equal(airborne.sway, 0);
assert.equal(airborne.roll, 0);
assert.equal(airborne.stride, 0);

const waveA = waterWave(3, 7, 1.25);
const waveB = waterWave(3, 7, 1.25);
assert.equal(waveA, waveB);
assert.notEqual(waveA, waterWave(3, 7, 2.25));
assert.ok(Math.abs(waveA) <= 0.06);
assert.ok(Math.abs(waterWave(-32, 48, 9)) <= 0.06);

console.log("visual motion ok");
