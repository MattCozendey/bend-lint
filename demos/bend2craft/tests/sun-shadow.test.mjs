import assert from "node:assert/strict";
import {
  SHADOW_DEPTH_RANGE,
  SHADOW_FADE_END,
  SHADOW_FADE_START,
  SHADOW_GUARANTEED_RADIUS,
  SHADOW_MAP_SIZE,
  SHADOW_RADIUS,
  SHADOW_SAMPLING_GLSL,
  fitSunShadowMatrix,
} from "../web/webgl-shadow.js";
import { normalize, transformPoint } from "../web/gl-matrix.js";
import { SHADOW_MAX_TAPS } from "../web/webgl-shaders.js";

assert.ok(SHADOW_MAX_TAPS >= 4, "the shadow filter needs a real tap budget");
assert.ok(SHADOW_FADE_START < SHADOW_FADE_END, "the cascade fade must run outward");
assert.ok(
  Math.abs(SHADOW_GUARANTEED_RADIUS - SHADOW_RADIUS / Math.SQRT2) < 1e-9,
  "the guaranteed radius must be the inscribed circle of the light-space square",
);
assert.ok(SHADOW_GUARANTEED_RADIUS < SHADOW_RADIUS, "the guaranteed radius is never the full one");
assert.ok(SHADOW_FADE_END <= 1, "the cascade fade must finish inside the map");
assert.ok(SHADOW_RADIUS > 0 && SHADOW_DEPTH_RANGE > 0);

// The fitted matrix must place the world point at the centre of the map.
for (const [name, sun] of [
  ["noon", normalize([0.1, 0.99, 0.05])],
  ["low", normalize([0.8, 0.53, 0.27])],
  ["west", normalize([-0.95, 0.3, 0.05])],
  ["straight down", normalize([0, 1, 0.0001])],
]) {
  const centre = [12.5, 9, -30.25];
  const matrix = fitSunShadowMatrix(sun, centre, { radius: SHADOW_RADIUS, mapSize: SHADOW_MAP_SIZE });
  assert.equal(matrix.length, 16);
  // Clip space: the centre must land on z in front of the far plane.
  const clip = transformPoint(matrix, centre);
  assert.ok(clip[3] > 0, `${name}: the centre must be in front of the light, got w=${clip[3]}`);
  const ndcZ = clip[2] / clip[3];
  assert.ok(ndcZ > -1 && ndcZ < 1, `${name}: the centre must be inside the depth range, got ${ndcZ}`);
  // The cascade covers a square in light space, which is rotated in world space,
  // so only the inscribed circle is guaranteed for every sun direction. Test
  // that circle, not the full radius: asserting the corners of a world-aligned
  // square would be asserting a guarantee the projection does not make.
  for (const [dx, dz] of [[-1, -1], [1, -1], [-1, 1], [1, 1], [0, 0]]) {
    const point = [
      centre[0] + dx * SHADOW_GUARANTEED_RADIUS,
      centre[1],
      centre[2] + dz * SHADOW_GUARANTEED_RADIUS,
    ];
    const projected = transformPoint(matrix, point);
    const x = projected[0] / projected[3];
    const y = projected[1] / projected[3];
    assert.ok(x >= -1.001 && x <= 1.001, `${name}: corner ${dx},${dz} fell outside on x (${x})`);
    assert.ok(y >= -1.001 && y <= 1.001, `${name}: corner ${dx},${dz} fell outside on y (${y})`);
  }
}

// Texel snapping: the same centre must always produce the same matrix, or the
// shadow edges crawl as the player walks.
const sun = normalize([0.6, 0.7, 0.39]);
const a = fitSunShadowMatrix(sun, [3.14159, 9, -2.71828]);
const b = fitSunShadowMatrix(sun, [3.14159, 9, -2.71828]);
assert.deepEqual(Array.from(a), Array.from(b), "the fit must be deterministic");

// Texel snapping is what stops the shadows from shimmering as the player walks:
// the projected shadow-map position of a point that moves with the camera must
// advance in whole texels, never continuously. The depth axis is deliberately
// *not* quantised, so this compares the projected x/y rather than the matrix.
const texelWorld = (SHADOW_RADIUS * 2) / SHADOW_MAP_SIZE;
const texelNdc = 1 / SHADOW_MAP_SIZE;
// The probe is a *fixed* world point: as the camera walks, where that point
// lands in the shadow map must only ever move in whole texels. A point carried
// along with the camera would always sit under the same texel and prove nothing.
const probePoint = [10.37, 9, 9.09];
const projected = [];
const samples = 64;
for (let step = 0; step <= samples; step += 1) {
  const offset = (step / samples) * texelWorld * 4;
  const matrix = fitSunShadowMatrix(sun, [10 + offset, 9, 10]);
  const clip = transformPoint(matrix, probePoint);
  projected.push([clip[0] / clip[3], clip[1] / clip[3]]);
}
// Snapping does not put a point *on* the grid, it makes the point's texel stay
// the same texel. So the property to check is that consecutive projections
// differ by a whole number of texels: the fractional part must not drift.
for (let step = 1; step < projected.length; step += 1) {
  for (let axis = 0; axis < 2; axis += 1) {
    const steps = (projected[step][axis] - projected[step - 1][axis]) / texelNdc;
    assert.ok(
      Math.abs(steps - Math.round(steps)) < 1e-3,
      `the projection drifted by ${steps} texels between frames on axis ${axis}`,
    );
  }
}
// Without snapping the drift would be continuous, so a long walk must still only
// ever step in whole texels. Sanity-check that the sweep really does move.
const totalSteps = (projected[projected.length - 1][0] - projected[0][0]) / texelNdc;
assert.ok(totalSteps > 0, "the sweep must actually move the projection");
// Over four texels of travel the projection must advance about four texels, not
// crawl: this is the property that separates snapping from no snapping at all.
const travelledX = Math.abs(projected[0][0] - projected[samples][0]) / texelNdc;
assert.ok(
  travelledX >= 3 && travelledX <= 5,
  `four texels of travel should move the projection about four texels, got ${travelledX}`,
);

// A sun straight overhead is the degenerate case for the eye axis: the fit must
// still produce a usable matrix instead of a NaN.
const overhead = fitSunShadowMatrix(normalize([0, 1, 0.0000001]), [0, 9, 0]);
for (const value of overhead) {
  assert.ok(Number.isFinite(value), "an overhead sun must not produce NaN in the light matrix");
}

// The sampling GLSL must declare every uniform the terrain shader feeds it, and
// must use a constant loop bound so GLSL ES 1.00 accepts it.
for (const uniform of [
  "uShadowMap",
  "uShadowDisk",
  "uLightViewProjection",
  "uShadowTexelSize",
  "uShadowRadius",
  "uShadowFade",
  "uShadowStrength",
  "uShadowTaps",
  "uShadowFloor",
]) {
  assert.match(
    SHADOW_SAMPLING_GLSL,
    new RegExp(`uniform\\s+\\w+\\s+${uniform}\\s*;`),
    `the shadow GLSL must declare ${uniform}`,
  );
}
assert.match(SHADOW_SAMPLING_GLSL, /for \(int index = 0; index < SHADOW_MAX_TAPS; index\+\+\)/);
assert.match(SHADOW_SAMPLING_GLSL, /if \(index >= taps\) break;/);
assert.match(SHADOW_SAMPLING_GLSL, /uShadowStrength <= 0\.0\) return 1\.0/, "an unused cascade must cost nothing");
assert.match(SHADOW_SAMPLING_GLSL, /uShadowFloor/, "a fully shadowed surface must still catch some light");

console.log("sun shadow ok");
