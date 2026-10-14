import assert from "node:assert/strict";
import {
  DOWNGRADE_BUDGET_MS,
  PANIC_BUDGET_MS,
  UPGRADE_BUDGET_MS,
  VISUAL_QUALITY_TIERS,
  clampVisualQuality,
  createVisualQualityController,
  parseVisualQuality,
  visualQualityTierByName,
} from "../web/visual-quality.js";

assert.ok(VISUAL_QUALITY_TIERS.length >= 3, "there must be a ladder to walk down");
assert.equal(VISUAL_QUALITY_TIERS[0].name, "minimal");
assert.equal(VISUAL_QUALITY_TIERS[VISUAL_QUALITY_TIERS.length - 1].name, "ultra");

// The ladder must be monotone: a cheaper tier may never do more work than a
// dearer one, or "stepping down" would not be a step down.
const costKeys = ["cloudSteps", "cloudLightSteps", "shadowTaps", "bloomMips", "godraySteps"];
for (let index = 1; index < VISUAL_QUALITY_TIERS.length; index += 1) {
  for (const key of costKeys) {
    const previous = VISUAL_QUALITY_TIERS[index - 1][key];
    const current = VISUAL_QUALITY_TIERS[index][key];
    assert.ok(
      current >= previous,
      `${key} must not fall going from ${VISUAL_QUALITY_TIERS[index - 1].name} to ${VISUAL_QUALITY_TIERS[index].name}`,
    );
  }
}
// The top tier has to be worth the name, and the bottom tier must still be a
// real render rather than a stub.
assert.ok(VISUAL_QUALITY_TIERS[0].cloudSteps >= 4, "the cheapest tier still marches the cloud deck");
assert.ok(VISUAL_QUALITY_TIERS[0].shadowTaps >= 4, "the cheapest tier still filters the shadow map");
assert.ok(VISUAL_QUALITY_TIERS[VISUAL_QUALITY_TIERS.length - 1].cloudSteps >= 16, "ultra must be a real march");

assert.equal(clampVisualQuality(-5), 0);
assert.equal(clampVisualQuality(99), VISUAL_QUALITY_TIERS.length - 1);
assert.equal(clampVisualQuality("nope"), 3, "a non-numeric level falls back to the default");
// A tier *name* has to resolve to its own index, not to the default. This is the
// form every pin arrives in (a URL parameter, a stored preference), and a name
// that fell through to NaN silently ran the default tier instead.
for (const tier of VISUAL_QUALITY_TIERS) {
  assert.equal(clampVisualQuality(tier.name), VISUAL_QUALITY_TIERS.indexOf(tier), `${tier.name} must resolve to its own index`);
  assert.equal(clampVisualQuality(tier.name.toUpperCase()), VISUAL_QUALITY_TIERS.indexOf(tier), "a name match is case insensitive");
  assert.equal(clampVisualQuality(` ${tier.name} `), VISUAL_QUALITY_TIERS.indexOf(tier), "a name match tolerates whitespace");
  // A pin is the only way to reach a tier with adaptation off, so the round trip
  // through the parser has to land on exactly that tier.
  assert.equal(clampVisualQuality(parseVisualQuality(tier.name)), VISUAL_QUALITY_TIERS.indexOf(tier));
}
assert.equal(visualQualityTierByName("ultra")?.name, "ultra");
assert.equal(visualQualityTierByName("ULTRA")?.name, "ultra");
assert.equal(visualQualityTierByName("nope"), null);
assert.equal(parseVisualQuality("minimal"), "minimal");
assert.equal(parseVisualQuality("0"), "minimal");
assert.equal(parseVisualQuality("3"), "high");
assert.equal(parseVisualQuality(null), null);
assert.equal(parseVisualQuality(undefined), null);
assert.equal(parseVisualQuality("nope"), null);

// A pinned controller must not adapt, or a `?graphics=` override would be
// silently undone by the very next frame.
const pinned = createVisualQualityController({ initial: 0, auto: false });
for (let frame = 0; frame < 200; frame += 1) pinned.sample(400);
assert.equal(pinned.level, 0, "auto:false must pin the level");
assert.equal(pinned.tier.name, "minimal");
assert.equal(pinned.auto, false);

// The controller starts high and walks down under load.
const adaptive = createVisualQualityController({ initial: VISUAL_QUALITY_TIERS.length - 1 });
const startLevel = adaptive.level;
for (let frame = 0; frame < 400; frame += 1) adaptive.sample(120);
assert.ok(adaptive.level < startLevel, "a sustained 120 ms frame time must step the tier down");
assert.equal(adaptive.auto, true);

// A single catastrophic frame must drop several tiers at once. Climbing one step
// per settle window would leave the game unplayable for seconds.
const panicking = createVisualQualityController({ initial: VISUAL_QUALITY_TIERS.length - 1 });
panicking.sample(PANIC_BUDGET_MS * 2);
assert.ok(
  panicking.level <= VISUAL_QUALITY_TIERS.length - 1 - 3,
  "a panic frame must drop more than one tier",
);

// It must recover once there is headroom again, and never overshoot the ladder.
const recovering = createVisualQualityController({ initial: 1 });
for (let frame = 0; frame < 4000; frame += 1) recovering.sample(2);
assert.equal(recovering.tier.name, "ultra", "sustained headroom must climb back to the top tier");
for (let frame = 0; frame < 4000; frame += 1) recovering.sample(1000);
assert.equal(recovering.tier.name, "minimal", "sustained load must fall back to the bottom tier");

// A bad sample must not produce a NaN level or a torn timer.
const robust = createVisualQualityController({ initial: 2 });
for (const bad of [Number.NaN, 0, -1, Number.POSITIVE_INFINITY, undefined]) robust.sample(bad);
assert.ok(Number.isInteger(robust.level));
assert.ok(robust.level >= 0 && robust.level < VISUAL_QUALITY_TIERS.length);
assert.ok(robust.smoothedFrameMs > 0, "a smoothed frame time is always reported");

// The hysteresis band must be real: a frame time between the two budgets must
// not move the level, or the controller oscillates and the image visibly flickers.
const steady = createVisualQualityController({ initial: 2 });
const middle = (DOWNGRADE_BUDGET_MS + UPGRADE_BUDGET_MS) / 2;
for (let frame = 0; frame < 600; frame += 1) steady.sample(middle);
assert.equal(steady.level, 2, "a frame time inside the hysteresis band must hold the tier");

// --- cadence-aware budgets ----------------------------------------------------
// The absolute budgets above are measured against a ~60 Hz assumption. On a 120 Hz
// ProMotion panel the compositor quantises the observed interval to 8.33 ms when
// the renderer keeps up and 16.7 ms when it misses every other vsync, so a
// renderer stuck at 16.7 ms looks like it is comfortably inside a 26 ms budget.
// Measured on an M1 Pro at 3024x1890: auto settled on `medium` at a 15.84 ms
// smoothed interval and never stepped down, while `low` reached 105 FPS.
//
// A frame time only means "over budget" relative to a target period, so the
// controller has to be told the target rather than assume one.
const FAST = 1000 / 120; // a 120 Hz panel
const cadenceAware = createVisualQualityController({
  initial: VISUAL_QUALITY_TIERS.length - 1,
  targetFrameMs: FAST,
});
// A renderer missing every other vsync on a 120 Hz panel: 16.7 ms against an
// 8.33 ms target. Under the absolute budget this is "fine"; against the cadence
// it is a 100% overrun.
for (let frame = 0; frame < 2000; frame += 1) cadenceAware.sample(1000 / 60);
assert.ok(
  cadenceAware.level < VISUAL_QUALITY_TIERS.length - 1,
  "missing every other vsync on a 120 Hz panel must step the tier down",
);
assert.ok(
  cadenceAware.level <= 1,
  `auto must walk down until the renderer fits the display, stopped at ${cadenceAware.tier.name}`,
);

// Once the renderer fits, it has to hold the tier rather than keep degrading: the
// ladder is a one-way ratchet unless the frame time comes back under the target.
const fitting = createVisualQualityController({ initial: 1, targetFrameMs: FAST });
for (let frame = 0; frame < 4000; frame += 1) fitting.sample(FAST * 0.8);
assert.equal(fitting.level, 1, "a renderer comfortably inside the cadence must hold its tier");

// Real headroom has to be able to climb back, so a scene that got cheap again
// recovers its detail instead of staying degraded forever.
const climbing = createVisualQualityController({ initial: 1, targetFrameMs: FAST });
for (let frame = 0; frame < 200; frame += 1) climbing.sample(1000 / 60);
assert.ok(climbing.level < 1, "the precondition must degrade before this recovery check means anything");
for (let frame = 0; frame < 6000; frame += 1) climbing.sample(FAST * 0.5);
assert.ok(climbing.level > 1, "sustained headroom on a fast panel must climb the ladder again");

// The cadence target must not create a second, tighter dead band. A renderer
// oscillating around the target has to settle on one side of it rather than
// hunting between two tiers forever.
const straddling = createVisualQualityController({ initial: 2, targetFrameMs: FAST });
for (let frame = 0; frame < 6000; frame += 1) straddling.sample(FAST * (1 + (frame % 2 === 0 ? 0.1 : -0.1)));
assert.equal(
  straddling.level, 2,
  "jitter around the target must not walk the tier, the band still has to absorb it",
);

// A cap changes what "on budget" means, and the controller has to accept it: with
// a 30 FPS cap a 33.3 ms frame is exactly on target, not an overrun. Without this
// the cap would make the controller panic down to `minimal` and the player would
// get the worst picture at the frame rate they asked for.
const capped = createVisualQualityController({ initial: 2, targetFrameMs: 1000 / 30 });
for (let frame = 0; frame < 4000; frame += 1) capped.sample(1000 / 30);
assert.equal(capped.level, 2, "a frame at exactly the cap period is on budget, not an overrun");
for (let frame = 0; frame < 4000; frame += 1) capped.sample(1000 / 15);
assert.ok(capped.level < 2, "missing the cap it was given must still degrade");

// The target is live: the game re-reads it as the display cadence is learned, and
// a controller pinned to a stale target would keep aiming at a refresh rate the
// panel no longer runs at.
const liveTarget = createVisualQualityController({ initial: 2, targetFrameMs: FAST });
assert.equal(liveTarget.targetFrameMs, FAST);
liveTarget.setTargetFrameMs(1000 / 60);
assert.equal(liveTarget.targetFrameMs, 1000 / 60);

// A nonsensical target must not stop the ladder or produce NaN comparisons.
const badTarget = createVisualQualityController({ initial: 2, targetFrameMs: Number.NaN });
for (const bad of [0, -1, Number.POSITIVE_INFINITY, Number.NaN, null, undefined, "60"]) {
  badTarget.setTargetFrameMs(bad);
  for (let frame = 0; frame < 50; frame += 1) badTarget.sample(1000 / 30);
  assert.ok(Number.isInteger(badTarget.level), `target ${String(bad)} produced a non-integer level`);
  assert.ok(badTarget.level >= 0 && badTarget.level < VISUAL_QUALITY_TIERS.length,
    `target ${String(bad)} pushed the level off the ladder`);
}

// Without an explicit target the controller keeps the absolute budgets, so the
// behaviour that predates the cadence target is unchanged.
const noTarget = createVisualQualityController({ initial: 2 });
assert.ok(noTarget.targetFrameMs > 0, "a controller with no target still reports a usable one");
for (let frame = 0; frame < 600; frame += 1) noTarget.sample((DOWNGRADE_BUDGET_MS + UPGRADE_BUDGET_MS) / 2);
assert.equal(noTarget.level, 2, "the absolute hysteresis band must still hold without a cadence target");

console.log("visual quality ok");
