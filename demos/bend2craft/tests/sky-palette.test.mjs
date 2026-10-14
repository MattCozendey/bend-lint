import assert from "node:assert/strict";
import { SUN_ANGULAR_SPEED, skyPalette, sunDirection } from "../web/sky-palette.js";

const bright = skyPalette(1);
const dim = skyPalette(0.28);
assert.equal(bright.top.length, 3);
assert.equal(bright.horizon.length, 3);
assert.ok(bright.top.every((value) => value >= 0 && value <= 1));
assert.ok(bright.horizon.every((value) => value >= 0 && value <= 1));
assert.ok(bright.top[2] > dim.top[2]);
assert.ok(bright.cssTop.startsWith("rgb("));
assert.ok(bright.cssHorizon.startsWith("rgb("));
assert.notEqual(bright.cssTop, dim.cssTop);

const morningSun = sunDirection(0);
const noonSun = sunDirection(Math.PI / (2 * SUN_ANGULAR_SPEED));
const midnightSun = sunDirection(3 * Math.PI / (2 * SUN_ANGULAR_SPEED));
assert.ok(Math.abs(morningSun[1]) < 0.08);
assert.ok(noonSun[1] > 0.96);
assert.ok(midnightSun[1] < -0.96);
for (const direction of [morningSun, noonSun, midnightSun]) {
  assert.ok(Math.abs(Math.hypot(...direction) - 1) < 1e-12);
}
const timed = skyPalette(1, 0);
assert.deepEqual(timed.sunDirection, morningSun);
assert.ok(timed.sunColor[0] > timed.sunColor[2]);

console.log("sky palette ok");
