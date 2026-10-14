import assert from "node:assert/strict";
import {
  DAY_LENGTH,
  DAY_SKY,
  NIGHT_SKY,
  advanceTime,
  brightness,
  dayCount,
  isDay,
  skyColor,
} from "../web/daynight.js";

assert.equal(DAY_LENGTH, 600);

// Sunrise (0) and noon (0.25) are day; sunset edge (0.5) and midnight are night.
assert.equal(isDay(0), true);
assert.equal(isDay(0.25), true);
assert.equal(isDay(0.49), true);
assert.equal(isDay(0.5), false);
assert.equal(isDay(0.75), false);
assert.equal(isDay(0.99), false);

// Anchor colors are exact so the sky is deterministic.
assert.deepEqual(skyColor(0.25), [...DAY_SKY]);
assert.deepEqual(skyColor(0.75), [...NIGHT_SKY]);
const sunrise = skyColor(0);
assert.ok(sunrise[0] > sunrise[2], "sunrise is warm");

// Blocks are fully lit at noon and dim at midnight.
assert.equal(brightness(0.25), 1);
assert.ok(brightness(0.75) < 0.5);
assert.ok(brightness(0) > 0.5 && brightness(0) <= 1);
for (const t of [0, 0.1, 0.25, 0.5, 0.75, 0.99]) {
  const b = brightness(t);
  assert.ok(b >= 0.3 && b <= 1, `brightness(${t}) in range`);
}

// Time wraps around midnight and days are counted from zero.
assert.ok(Math.abs(advanceTime(0.9, 120) - 0.1) < 1e-9);
assert.equal(dayCount(0), 1);
assert.equal(dayCount(599), 1);
assert.equal(dayCount(600), 2);
assert.equal(dayCount(1500), 3);

console.log("daynight ok");
