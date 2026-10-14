import assert from "node:assert/strict";
import {
  VFX_CAPACITY,
  appendVfxQuads,
  createVfx,
  emitBlockDebris,
  emitDeathPuff,
  emitFlame,
  emitImpact,
  emitSmoke,
  emitSparkle,
  hexToRgb,
} from "../web/vfx.js";

// A scripted random source: every effect in this file has to be reproducible, or
// a visual bug can never be pinned down. The queue wraps around, so an emitter
// that reads more values than the script holds still gets a defined answer.
function scriptedRandom(values) {
  let index = 0;
  return () => {
    const value = values[index % values.length];
    index += 1;
    return value;
  };
}

// A short repeating script aliases against an emitter that draws many values per
// particle - a five-value cycle read at every tenth draw is the same value every
// time. Anything checking a spread of values wants a real generator instead.
function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };
}

const right = [1, 0, 0];
const up = [0, 1, 0];

// ---- capacity -------------------------------------------------------------
const vfx = createVfx({ random: scriptedRandom([0.5]) });
for (let index = 0; index < VFX_CAPACITY + 40; index += 1) {
  vfx.spawn({ x: index, y: 0, z: 0, life: 10, size: 0.2 });
}
assert.equal(vfx.count, VFX_CAPACITY, "the pool must never grow past its capacity");
// Overflow recycles the oldest slot rather than dropping the new effect: a mob
// that just caught fire is the most recent event and has to be the one seen.
assert.equal(vfx.particles[VFX_CAPACITY - 1].x, VFX_CAPACITY + 39);

vfx.clear();
assert.equal(vfx.count, 0, "clear must retire every particle");

// ---- integration ----------------------------------------------------------
const faller = createVfx({ random: scriptedRandom([0.5]) });
faller.spawn({
  x: 0, y: 10, z: 0, vx: 0, vy: 0, vz: 0,
  life: 1, size: 0.4, growth: 0.2, gravity: 20, drag: 0, alpha: 1,
});
faller.update(0.5);
const falling = faller.particles[0];
// The exact drop from rest under g=20 for half a second is g*t^2/2 = 2.5. The
// solver lands just short of it, by the first-order error of the substep, and
// this pins that error down instead of letting it grow unnoticed.
assert.ok(Math.abs(7.5 - falling.y) < 0.2, `expected y near 7.5, got ${falling.y}`);
assert.ok(Math.abs(falling.vy + 10) < 1e-9, `velocity must carry the force, got ${falling.vy}`);
assert.ok(Math.abs(falling.size - 0.5) < 1e-9, `size must grow with time, got ${falling.size}`);

// Within the substep budget, one long step and many short ones must land in the
// same place, or an effect would fall at a different rate on a fast machine
// than on a slow one.
const fallA = createVfx({ random: scriptedRandom([0.5]) });
const fallB = createVfx({ random: scriptedRandom([0.5]) });
for (const vfx of [fallA, fallB]) {
  vfx.spawn({ x: 0, y: 10, z: 0, life: 5, size: 1, gravity: 20, drag: 0 });
}
fallA.update(0.2);
for (let step = 0; step < 12; step += 1) fallB.update(1 / 60);
assert.equal(fallA.particles[0].y, fallB.particles[0].y,
  "one 0.2s step and twelve 1/60s steps must land in the same place");
// Substepping also buys real accuracy. The exact drop from rest under g=20 for
// one second is g*t^2/2 = 10, so a particle starting at y=10 ends at y=0. The
// solver lands short by the first-order error g*t*h/2, which is the whole
// reason the step is capped: this pins that bound rather than a loose guess.
const precise = createVfx({ random: scriptedRandom([0.5]) });
precise.spawn({ x: 0, y: 10, z: 0, life: 9, size: 1, gravity: 20, drag: 0 });
for (let step = 0; step < 60; step += 1) precise.update(1 / 60);
const fallError = Math.abs(precise.particles[0].y);
const firstOrderBound = (20 * 1 * (1 / 60)) / 2;
assert.ok(fallError <= firstOrderBound + 1e-9,
  `a 1s fall must stay within the g*t*h/2 error (${firstOrderBound}), got ${fallError}`);

// The velocity decay is an exponential, so it composes exactly however the step
// is cut - including a step long enough to exhaust the substep budget, which is
// what stops a backgrounded tab from stalling the frame that has to catch up.
const dragged = createVfx({ random: scriptedRandom([0.5]) });
for (const steps of [[1], [0.5, 0.5], [0.25, 0.25, 0.25, 0.25], [30]]) {
  dragged.clear();
  dragged.spawn({ x: 0, y: 0, z: 0, vx: 4, vy: 0, vz: 0, life: 60, size: 1, drag: 2 });
  for (const step of steps) dragged.update(step);
  const total = steps.reduce((sum, step) => sum + step, 0);
  assert.ok(Math.abs(dragged.particles[0].vx - 4 * Math.exp(-2 * total)) < 1e-12,
    `drag must be exact for the velocity under steps ${JSON.stringify(steps)}`);
}
// Position is a left-endpoint sum over that decay, so it converges on the
// analytic integral 4/2 * (1 - e^-2T) from below, by the same first-order
// v*h/2 the fall above pays.
dragged.clear();
dragged.spawn({ x: 0, y: 0, z: 0, vx: 4, vy: 0, vz: 0, life: 60, size: 1, drag: 2 });
for (let step = 0; step < 60 * 10; step += 1) dragged.update(1 / 60);
const analytic = 2 * (1 - Math.exp(-20));
const driftError = analytic - dragged.particles[0].x;
assert.ok(driftError > 0 && driftError <= (4 * (1 / 60)) / 2 + 1e-9,
  `a damped drift must approach ${analytic} from below by at most v*h/2, got ${dragged.particles[0].x}`);

const retiring = createVfx({ random: scriptedRandom([0.5]) });
retiring.spawn({ x: 0, y: 0, z: 0, life: 0.2, size: 1 });
retiring.update(0.19);
assert.equal(retiring.count, 1, "a particle must survive while it still has life");
retiring.update(0.02);
assert.equal(retiring.count, 0, "an expired particle must be retired, not left invisible");
retiring.update(1);
assert.equal(retiring.count, 0, "retiring twice must not resurrect or double-free");

// A zero or negative step must not manufacture motion or retire anything.
const idle = createVfx({ random: scriptedRandom([0.5]) });
idle.spawn({ x: 3, y: 4, z: 5, vx: 1, life: 1, size: 1, drag: 3, gravity: 9 });
idle.update(0);
assert.deepEqual(
  [idle.particles[0].x, idle.particles[0].y, idle.particles[0].z],
  [3, 4, 5],
  "a zero-length step must not move anything",
);
assert.equal(idle.count, 1);

// ---- emitters -------------------------------------------------------------
// Flames read as fire: additive, rising, and short. Smoke is the opposite on
// every one of those axes, which is exactly what makes the two distinguishable
// when both are rising off the same body.
const fire = createVfx({ random: scriptedRandom([0.5]) });
emitFlame(fire, 1, 2, 3, 6);
assert.equal(fire.count, 6);
for (const particle of fire.particles) {
  assert.equal(particle.additive, true, "a flame must be additive or it reads as smoke");
  assert.ok(particle.vy > 0, "a flame must rise");
  assert.ok(particle.life <= particle.span && particle.life > 0);
  assert.ok(particle.r >= particle.b, "a flame must be redder than it is blue");
}
const smoke = createVfx({ random: scriptedRandom([0.5]) });
emitSmoke(smoke, 1, 2, 3, 6);
for (const particle of smoke.particles) {
  assert.equal(particle.additive, false, "smoke must blend, or it glows instead of covering");
  assert.ok(particle.vy > 0, "smoke must rise");
  assert.ok(particle.growth > 0, "smoke must spread as it thins");
  assert.ok(particle.life > fire.particles[0].life, "smoke must outlast the flame that fed it");
}
// Flame and smoke must actually differ, or emitting both is wasted work.
assert.notEqual(fire.particles[0].span, smoke.particles[0].span);

// A block hit throws debris outward from the cell centre and lets it fall; it
// must not be a symmetric puff sitting still on the surface.
const debris = createVfx({ random: scriptedRandom([0, 0.5, 1, 0.25, 0.75]) });
emitBlockDebris(debris, 8, 9, 10, [0.5, 0.5, 0.5], 12);
assert.equal(debris.count, 12);
for (const particle of debris.particles) {
  assert.equal(particle.additive, false);
  assert.ok(particle.gravity > 0, "debris must fall");
  assert.ok(Math.abs(particle.x - 8) <= 0.6 && Math.abs(particle.z - 10) <= 0.6,
    "debris must stay recognisably at the block it came from");
}
// Debris carries the colour of the block it came from, varied per particle so
// the burst is not a flat card of one colour. The ratios must survive that
// variation exactly; only the brightness moves.
for (const particle of debris.particles) {
  assert.equal(particle.g, particle.r, "a neutral block must give neutral debris");
  assert.equal(particle.b, particle.r, "a neutral block must give neutral debris");
  assert.ok(particle.r >= 0.5 * 0.72 && particle.r <= 0.5 * 1.16,
    `debris brightness must stay in the documented band, got ${particle.r}`);
}
// A coloured block keeps its hue through the same path.
const dyed = createVfx({ random: scriptedRandom([0.5]) });
emitBlockDebris(dyed, 0, 0, 0, [0.8, 0.2, 0.1], 1);
assert.ok(dyed.particles[0].r > dyed.particles[0].g * 2,
  "a red block must throw redder debris than green");
assert.ok(dyed.particles[0].g > dyed.particles[0].b,
  "the block's hue order must survive the shading");

// An impact spark is small, fast and bright: the opposite of debris.
const impact = createVfx({ random: scriptedRandom([0.5]) });
emitImpact(impact, 0, 0, 0, [1, 0.9, 0.6], 8);
for (const particle of impact.particles) {
  assert.equal(particle.additive, true, "a hit spark must be additive to read as a flash");
  assert.ok(particle.size < 0.2, "a hit spark must be smaller than debris");
}
assert.ok(impact.particles[0].span < debris.particles[0].span, "a spark must be shorter-lived than debris");

const death = createVfx({ random: scriptedRandom([0.5]) });
emitDeathPuff(death, 1, 1, 1, [0.4, 0.6, 0.4], 16);
assert.equal(death.count, 16);
assert.ok(death.particles[0].span > impact.particles[0].span, "a death puff must linger past a hit spark");
// Long enough to actually be seen. A puff gone in half a second lands between
// two frames of attention and the mob just blinks out.
assert.ok(death.particles.every((p) => p.life >= 0.9),
  "a death puff must last long enough to read, not just exist");

const sparkle = createVfx({ random: scriptedRandom([0.5]) });
emitSparkle(sparkle, 2, 2, 2, [1, 1, 1], 5);
assert.equal(sparkle.count, 5);
for (const particle of sparkle.particles) {
  assert.ok(particle.vy > 0, "a pickup sparkle must drift toward the player");
}

// The spread is the radius of the disc a particle lands in, and it is not
// cosmetic: a particle spawned inside a mob is behind the mob's own front faces,
// so the depth test discards it. The caller's spread has to reach the emitter.
const tight = createVfx({ random: scriptedRandom([0.9]) });
emitFlame(tight, 0, 0, 0, 24, 0.05);
const tightReach = Math.max(...tight.particles.map((p) => Math.hypot(p.x, p.z)));
const wide = createVfx({ random: scriptedRandom([0.9]) });
emitFlame(wide, 0, 0, 0, 24, 0.5);
const wideReach = Math.max(...wide.particles.map((p) => Math.hypot(p.x, p.z)));
assert.ok(wideReach > tightReach,
  `a wider spread must reach further out: ${wideReach} vs ${tightReach}`);
assert.ok(tightReach <= 0.05 + 1e-9, "a tight spread must stay inside the radius it was given");
assert.ok(wideReach > 0.4, `a mob-sized spread must clear the body, got ${wideReach}`);
const smokeSpread = createVfx({ random: scriptedRandom([0.9]) });
emitSmoke(smokeSpread, 0, 0, 0, 24, 0.5);
assert.ok(Math.max(...smokeSpread.particles.map((p) => Math.hypot(p.x, p.z))) > 0.4,
  "smoke has to take a spread too, or it is emitted inside the body as well");

// A mob on fire has to read as a mob on fire from across a field, so the plume
// has to climb the body rather than sit in a ring around its waist. `height`
// distributes the emission up the body; without it the fire is a hoop.
const climbing = createVfx({ random: seededRandom(1337) });
emitFlame(climbing, 0, 10, 0, 60, 0.5, 1.9);
const heights = climbing.particles.map((p) => p.y - 10);
assert.ok(Math.min(...heights) >= 0, "no flame may start below the body");
assert.ok(Math.max(...heights) > 1.9 * 0.5,
  `flames must reach up the body, max was ${Math.max(...heights)}`);
assert.ok(Math.max(...heights) <= 1.9 + 0.1,
  `no flame may start above the body, max was ${Math.max(...heights)}`);
// A flame has to visibly climb, or the fire is a static decal. Buoyancy is set
// against drag, so the climb is terminal velocity times the remaining life, not
// the launch speed: a fast launch decays into a slow steady rise.
const rise = climbing.particles.map((p) => p.vy * p.life);
assert.ok(Math.max(...rise) > 0.8,
  `the fastest flame must climb a visible distance, it manages ${Math.max(...rise)}`);
// The plume has to be denser low down and thin out with height, or it reads as a
// uniform sleeve rather than as fire feeding on fuel.
const low = heights.filter((h) => h < 1.9 * 0.4).length;
const high = heights.filter((h) => h > 1.9 * 0.8).length;
assert.ok(low > high, `flames must concentrate low, got ${low} low and ${high} high`);
// A flame that is too small to resolve at any distance is not a visual effect.
assert.ok(climbing.particles.every((p) => p.size >= 0.2),
  "flames must be large enough to read against a body");
assert.ok(climbing.particles.every((p) => p.alpha >= 0.8),
  "flames must be opaque enough to read against a body");

// An emitter asked for zero particles must be a no-op, not a source of NaNs.
const none = createVfx({ random: scriptedRandom([0.5]) });
emitFlame(none, 0, 0, 0, 0);
emitBlockDebris(none, 0, 0, 0, [1, 1, 1], 0);
assert.equal(none.count, 0);

// The same seed must replay the same effect exactly, or a flicker is unreportable.
const replayA = createVfx({ random: scriptedRandom([0.1, 0.9, 0.35, 0.65, 0.5, 0.2, 0.8]) });
const replayB = createVfx({ random: scriptedRandom([0.1, 0.9, 0.35, 0.65, 0.5, 0.2, 0.8]) });
emitBlockDebris(replayA, 4, 5, 6, [0.2, 0.4, 0.6], 9);
emitBlockDebris(replayB, 4, 5, 6, [0.2, 0.4, 0.6], 9);
assert.deepEqual(
  replayA.particles.map((p) => [p.x, p.y, p.z, p.vx, p.vy, p.vz, p.size, p.r]),
  replayB.particles.map((p) => [p.x, p.y, p.z, p.vx, p.vy, p.vz, p.size, p.r]),
);

// ---- colours --------------------------------------------------------------
assert.deepEqual(hexToRgb("#ff8000"), [1, 0.5019607843137255, 0]);
assert.deepEqual(hexToRgb("f80"), [1, 0.5333333333333333, 0]);
assert.deepEqual(hexToRgb("#FFF"), [1, 1, 1], "hex parsing must be case-insensitive");
assert.deepEqual(hexToRgb("nonsense"), [1, 1, 1], "an unparseable colour must stay visible, not go black");

// ---- vertex emission ------------------------------------------------------
// The batch is the terrain program's own layout, so a particle rides the same
// buffers as everything else instead of needing a second pipeline.
function emptyBatch() {
  return { positions: [], colors: [], lights: [], normals: [], uvs: [], tiles: [] };
}

const drawn = createVfx({ random: scriptedRandom([0.5]) });
drawn.spawn({
  x: 1, y: 2, z: 3, life: 1, size: 0.5,
  r: 0.9, g: 0.4, b: 0.1, alpha: 0.8, additive: true,
});
const batch = emptyBatch();
assert.equal(appendVfxQuads(batch, drawn.particles, right, up), 6, "one particle is two triangles");
assert.equal(batch.positions.length, 18);
assert.equal(batch.colors.length, 18);
assert.equal(batch.lights.length, 12);
assert.equal(batch.normals.length, 18);
assert.equal(batch.uvs.length, 12);
assert.equal(batch.tiles.length, 24);

// Half a 0.5-wide quad spans 0.25 either side of its centre along the camera
// basis, which is what makes it face the player without a model matrix.
assert.deepEqual(
  [batch.positions[0], batch.positions[1], batch.positions[2]],
  [0.75, 1.75, 3],
  "the first corner must be centre - right*half - up*half",
);
assert.deepEqual(
  [batch.positions[3], batch.positions[4], batch.positions[5]],
  [1.25, 1.75, 3],
  "the quad must widen along the camera right vector",
);
assert.deepEqual(
  [batch.positions[6], batch.positions[7], batch.positions[8]],
  [1.25, 2.25, 3],
  "the quad must rise along the camera up vector",
);
assert.deepEqual([batch.positions[9], batch.positions[10], batch.positions[11]],
  [batch.positions[0], batch.positions[1], batch.positions[2]],
  "the second triangle must reuse the first and fourth corners");

// alpha and the additive flag ride the light attribute, which is unused for a
// particle; a tile rect of all zeros keeps the batch off the mining sentinel.
assert.deepEqual([batch.lights[0], batch.lights[1]], [0.8, 1]);
assert.deepEqual([batch.tiles[0], batch.tiles[1], batch.tiles[2], batch.tiles[3]], [0, 0, 1, 1]);
assert.deepEqual([batch.uvs[0], batch.uvs[1]], [0, 0], "uv must span the unit square for the radial falloff");

// Fade is resolved on the CPU from the remaining life, so a dying particle
// cannot go invisible while still being drawn.
const fading = createVfx({ random: scriptedRandom([0.5]) });
fading.spawn({ x: 0, y: 0, z: 0, life: 4, size: 1, r: 1, g: 1, b: 1, alpha: 0.8 });
fading.update(3);const fadeBatch = emptyBatch();
appendVfxQuads(fadeBatch, fading.particles, right, up);
assert.ok(Math.abs(fadeBatch.lights[0] - 0.2) < 1e-9,
  `three quarters through a 4s life must be at a fifth of the peak alpha, got ${fadeBatch.lights[0]}`);

const manyBatch = emptyBatch();
const many = createVfx({ random: scriptedRandom([0.5]) });
for (let index = 0; index < 3; index += 1) {
  many.spawn({ x: index, y: 0, z: 0, life: 1, size: 1 });
}
assert.equal(appendVfxQuads(manyBatch, many.particles, right, up), 18);
assert.equal(appendVfxQuads(emptyBatch(), [], right, up), 0, "an empty pool must draw nothing");

console.log("vfx ok");
