import assert from "node:assert/strict";
import {
  DEFAULT_EFFECT_AMOUNT,
  GRAPHICS_EFFECTS,
  createDefaultGraphicsEffects,
  graphicsEffectByKey,
  graphicsEffectKeys,
  normalizeGraphicsEffects,
  resolveGraphicsEffects,
} from "../web/graphics-effects.js";

// The per-effect amounts are one contract with four readers: the settings layer
// stores them, the menu draws a control per key, the runtime scales the pipeline
// by them, and this file decides whether they are sane. A key the runtime does
// not read is a slider that does nothing, so the table and the runtime are held
// together from here.

// --- the table itself ---------------------------------------------------------
assert.ok(GRAPHICS_EFFECTS.length >= 8, "the menu needs a full set of effects to be worth opening");
assert.deepEqual(graphicsEffectKeys(), GRAPHICS_EFFECTS.map((effect) => effect.key),
  "the key list must be the table's own order, so the menu and the runtime agree on it");
assert.equal(new Set(graphicsEffectKeys()).size, GRAPHICS_EFFECTS.length, "effect keys must be unique");

for (const effect of GRAPHICS_EFFECTS) {
  assert.match(effect.key, /^[a-z][a-zA-Z]*$/, `${effect.key} must be a camelCase key the runtime can read`);
  assert.ok(effect.label.length > 0, `${effect.key} needs a label the menu can show`);
  assert.ok(Number.isFinite(effect.min) && Number.isFinite(effect.max), `${effect.key} needs numeric bounds`);
  assert.ok(effect.min >= 0, `${effect.key} must be able to switch the effect off`);
  assert.ok(effect.max <= 200, `${effect.key} cannot offer more than double the shipped look`);
  assert.ok(effect.max > effect.min, `${effect.key} needs a range`);
  assert.ok(Number.isFinite(effect.step) && effect.step > 0, `${effect.key} needs a step`);
  assert.ok(
    effect.amount >= effect.min && effect.amount <= effect.max,
    `${effect.key} ships an amount (${effect.amount}) its own slider cannot show`,
  );
  assert.equal(graphicsEffectByKey(effect.key), effect, `${effect.key} must be findable by its own key`);
}
assert.equal(graphicsEffectByKey("nope"), null, "an unknown key must answer null, not a wrong effect");

// --- the shipped default look -------------------------------------------------
// These are the tuned defaults, pinned so a later "just nudge it" edit is a
// deliberate diff against the picture the player was promised.
const defaults = createDefaultGraphicsEffects();
assert.deepEqual(Object.keys(defaults), graphicsEffectKeys(),
  "the default document must carry every effect, in the table's order");

assert.deepEqual(defaults, {
  // Budget-owned by the quality tier. Their default has to stay at 100%: the tier
  // already prices these per frame, so a default above it would quietly make the
  // shipped frame more expensive than the tier a player was given says it is.
  shadows: 100,
  clouds: 100,
  waterDetail: 100,
  renderScale: 100,
  // Look only, priced inside the composite, so these are free to tune.
  bloom: 130,
  godRays: 120,
  vignette: 85,
  grain: 75,
  aberration: 60,
  sharpen: 115,
  antiAliasing: 100,
  caustics: 115,
});

for (const key of ["shadows", "clouds", "waterDetail", "renderScale"]) {
  assert.equal(defaults[key], DEFAULT_EFFECT_AMOUNT,
    `${key} is budget, not taste: tuning its default changes what a frame costs`);
}
for (const key of ["antiAliasing", "renderScale"]) {
  assert.equal(graphicsEffectByKey(key).max, DEFAULT_EFFECT_AMOUNT,
    `${key} scales something already bounded by 1, so it cannot go above the shipped look`);
  assert.equal(defaults[key], DEFAULT_EFFECT_AMOUNT,
    `${key} has to stay pinned to the shipped look at 100`);
}

// --- normalising what was stored ---------------------------------------------
/** Every effect asked for zero, which is off for all of them but resolution. */
function allZeroDocument() {
  return Object.fromEntries(graphicsEffectKeys().map((key) => [key, 0]));
}

assert.deepEqual(normalizeGraphicsEffects(undefined), defaults, "a document without effects gets the defaults");
assert.deepEqual(normalizeGraphicsEffects(null), defaults);
assert.deepEqual(normalizeGraphicsEffects({}), defaults);
assert.deepEqual(normalizeGraphicsEffects({ bloom: 140 }), { ...defaults, bloom: 140 },
  "one stored amount must not reset the others");
assert.deepEqual(
  normalizeGraphicsEffects(allZeroDocument()),
  { ...allZeroDocument(), renderScale: graphicsEffectByKey("renderScale").min },
  "an effect the player switched off has to stay off",
);
assert.equal(normalizeGraphicsEffects({ bloom: 1e9 }).bloom, 200, "an absurd amount clamps to the maximum");
assert.equal(normalizeGraphicsEffects({ bloom: -40 }).bloom, 0, "a negative amount clamps to off");
for (const bad of ["high", null, NaN, {}, [], true]) {
  assert.equal(normalizeGraphicsEffects({ bloom: bad }).bloom, defaults.bloom,
    `a stored bloom of ${String(bad)} must fall back to the shipped look`);
}
assert.deepEqual(Object.keys(normalizeGraphicsEffects({ nonsense: 50, bloom: 120 })), graphicsEffectKeys(),
  "an effect this build does not know must not survive into the document the runtime reads");

// --- what the runtime multiplies by ------------------------------------------
// The resolution is the player's dial alone: a multiplier in 0..1 that the
// renderer multiplies into the tier's own numbers, so the two levers cannot
// quietly price the same frame twice.
const shipped = resolveGraphicsEffects(defaults);
for (const key of graphicsEffectKeys()) {
  const effect = graphicsEffectByKey(key);
  assert.ok(Number.isFinite(shipped[key]), `${key} resolved to ${String(shipped[key])}`);
  assert.ok(shipped[key] >= 0 && shipped[key] <= effect.max / 100,
    `${key} resolved to ${shipped[key]}, outside the 0..${effect.max / 100} its own slider can ask for`);
}
// The tuned look must not change what a frame costs.
for (const key of ["shadows", "clouds", "waterDetail", "renderScale"]) {
  assert.equal(shipped[key], 1, `${key} is priced by the tier; the default look must leave it alone`);
}
assert.ok(shipped.bloom > 1 && shipped.godRays > 1 && shipped.sharpen > 1 && shipped.caustics > 1,
  "the shipped look turns the cheap composite effects up");
assert.ok(shipped.vignette < 1 && shipped.grain < 1 && shipped.aberration < 1,
  "the shipped look pulls the murk back");
assert.equal(shipped.renderScale, 1, "the shipped look renders at the tier's own resolution");

const allZero = allZeroDocument();
const off = resolveGraphicsEffects(allZero);
for (const key of graphicsEffectKeys()) {
  assert.equal(off[key], key === "renderScale" ? 0.5 : 0,
    `${key} at 0 has to switch the effect off, not merely weaken it`);
}
// Resolution is the exception, and it has to be: 0 is not a render target, so
// its slider stops at half the canvas rather than pretending to switch anything off.
assert.equal(normalizeGraphicsEffects(allZero).renderScale, graphicsEffectByKey("renderScale").min);
assert.equal(resolveGraphicsEffects({ ...defaults, clouds: 200 }).clouds, 2);
assert.equal(resolveGraphicsEffects({ ...defaults, renderScale: 50 }).renderScale, 0.5,
  "resolution is bounded above by the tier and below by the player's own slider");
// A partial document is what a build upgrade hands the runtime.
const partial = resolveGraphicsEffects({ bloom: 200 });
for (const key of graphicsEffectKeys()) {
  assert.ok(Number.isFinite(partial[key]), `${key} must survive a document that never stored it`);
}
assert.equal(partial.bloom, 2);
assert.equal(partial.vignette, defaults.vignette / 100);

console.log("graphics effects ok");