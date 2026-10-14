// Per-effect graphics amounts: one contract between the settings document, the
// options panel and the renderer.
//
// The presentation pipeline already had every one of these effects and priced
// them only indirectly, through the adaptive quality tier. The tier answers "how
// much can this machine afford"; it cannot answer "how much of this effect do I
// want", which is why a player who found the frame too soft had nothing to turn
// up. So the amounts here are the second lever, and the two do not overlap:
//
//   - The tier owns the budget. Cloud march steps, shadow filter taps, the shadow
//     map's size and the internal render resolution are priced per frame, so they
//     keep following the tier and their default amount stays at 100.
//   - The amounts own the look. Everything priced inside the composite shader is
//     already paid for by the time it runs, so turning one of those up costs
//     nothing and is free to tune.
//
// An amount is a percentage of the shipped value for that effect: 0 switches the
// effect off, 100 is the shipped look, 200 is double. Two effects are capped at
// 100 because they scale something already bounded by one - an anti-aliasing
// blend above 1 and a render scale above the tier's own would both overshoot
// rather than strengthen.
// Defaults are the tuned look, not the numbers the pipeline happened to ship
// with: the bloom, sunbeam, sharpening and caustic terms are turned up, and the
// vignette, grain and aberration that were stacking into visible murk at the frame
// edges are pulled back. The budget-owned four stay at 100 so the shipped frame
// costs what its tier says it costs. `tests/graphics-effects.test.mjs` pins all of
// it, and the before/after pictures that decided these numbers are in
// `lab/native/paint/README.md`'s workflow: capture the same poses, compare.

/** What "the shipped look" means: an amount of 100 multiplies nothing away. */
export const DEFAULT_EFFECT_AMOUNT = 100;
/** The largest amount on offer. Past double, a strength is not a preference. */
export const MAX_EFFECT_AMOUNT = 200;

export const GRAPHICS_EFFECTS = Object.freeze([
  // --- priced by the quality tier: the default amount stays at 100 -----------
  Object.freeze({
    key: "shadows",
    label: "Sun Shadows",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 10,
    amount: DEFAULT_EFFECT_AMOUNT,
    hint: "The single sun cascade. Turning it off also skips rendering it.",
  }),
  Object.freeze({
    key: "clouds",
    label: "Volumetric Clouds",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 10,
    amount: DEFAULT_EFFECT_AMOUNT,
    hint: "Density of the cloud march. Turning it off leaves a clear sky.",
  }),
  Object.freeze({
    key: "waterDetail",
    label: "Water Surface Detail",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 10,
    amount: DEFAULT_EFFECT_AMOUNT,
    hint: "Wave detail on the water surface.",
  }),
  Object.freeze({
    key: "renderScale",
    label: "Resolution Scale",
    min: 50,
    max: DEFAULT_EFFECT_AMOUNT,
    step: 5,
    amount: DEFAULT_EFFECT_AMOUNT,
    hint: "Internal render resolution, as a share of the canvas. Lowering it is the cheapest way to buy frames.",
  }),
  // --- priced inside the composite: free to turn up --------------------------
  Object.freeze({
    key: "bloom",
    label: "Bloom",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 5,
    amount: 130,
    hint: "Glow around the brightest highlights. Turning it off also skips the whole bloom chain.",
  }),
  Object.freeze({
    key: "godRays",
    label: "Sunbeams",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 5,
    amount: 120,
    hint: "Shafts of light through whatever the sun is behind.",
  }),
  Object.freeze({
    key: "caustics",
    label: "Water Caustics",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 5,
    amount: 115,
    hint: "Light patterns on surfaces under water.",
  }),
  Object.freeze({
    key: "sharpen",
    label: "Sharpening",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 5,
    amount: 115,
    hint: "Recovers the bite the softer samples lose.",
  }),
  Object.freeze({
    key: "vignette",
    label: "Vignette",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 5,
    amount: 85,
    hint: "Darkening towards the corners of the frame.",
  }),
  Object.freeze({
    key: "grain",
    label: "Film Grain",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 5,
    amount: 75,
    hint: "Noise in the shadows. Also breaks up banding in the sky.",
  }),
  Object.freeze({
    key: "aberration",
    label: "Chromatic Aberration",
    min: 0,
    max: MAX_EFFECT_AMOUNT,
    step: 5,
    amount: 60,
    hint: "Colour fringing at the edges of the frame.",
  }),
  Object.freeze({
    key: "antiAliasing",
    label: "Anti-aliasing",
    min: 0,
    max: DEFAULT_EFFECT_AMOUNT,
    step: 5,
    amount: DEFAULT_EFFECT_AMOUNT,
    hint: "Edge smoothing over the finished image.",
  }),
]);

/** The effect keys, in the table's own order. */
export function graphicsEffectKeys() {
  return GRAPHICS_EFFECTS.map((effect) => effect.key);
}

/** One effect by key, or null when this build does not have it. */
export function graphicsEffectByKey(key) {
  return GRAPHICS_EFFECTS.find((effect) => effect.key === key) ?? null;
}

/** The shipped look: every effect at the amount this build tuned it to. */
export function createDefaultGraphicsEffects() {
  const effects = {};
  for (const effect of GRAPHICS_EFFECTS) effects[effect.key] = effect.amount;
  return effects;
}

/**
 * The stored document, with every key this build knows and nothing else.
 *
 * A missing, unreadable or out-of-range amount falls back to the shipped value,
 * because a corrupted preference has to leave the player looking at the game as
 * built rather than at a half-applied look. Zero is a real value and survives:
 * turning an effect off is a decision, not a gap.
 *
 * Only a number counts as an amount. `Number(null)`, `Number(true)` and
 * `Number([])` are all 0 or 1, so a document that lost a value to corruption would
 * otherwise read as "switch this effect off" rather than as "ask for the default".
 */
export function normalizeGraphicsEffects(raw) {
  const source = raw !== null && typeof raw === "object" ? raw : {};
  const effects = {};
  for (const effect of GRAPHICS_EFFECTS) {
    const stored = source[effect.key];
    const parsed = typeof stored === "number" ? stored : Number.NaN;
    effects[effect.key] = Number.isFinite(parsed)
      ? Math.min(effect.max, Math.max(effect.min, Math.round(parsed)))
      : effect.amount;
  }
  return effects;
}

/**
 * The multipliers the renderer applies: a strength divided by the shipped look,
 * so an amount of 0 switches the effect off and an amount of the effect's maximum
 * doubles it.
 *
 * These are the player's dial alone. The tier's own numbers stay where they are
 * and the renderer multiplies the two - `tier.cloudSteps * effects.clouds` - so
 * turning the clouds down on a tier that already priced a thick march cannot
 * quietly raise the price of the tier below it, and turning them up cannot make a
 * frame cost more than the tier said it would.
 */
export function resolveGraphicsEffects(amounts) {
  const stored = normalizeGraphicsEffects(amounts);
  const resolved = {};
  for (const effect of GRAPHICS_EFFECTS) resolved[effect.key] = stored[effect.key] / DEFAULT_EFFECT_AMOUNT;
  return resolved;
}