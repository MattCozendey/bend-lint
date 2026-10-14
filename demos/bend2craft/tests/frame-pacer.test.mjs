import assert from "node:assert/strict";
import {
  DEFAULT_FPS_LIMIT,
  FPS_LIMIT_CHOICES,
  createFramePacer,
  framePeriodMs,
  measureDisplayCadenceMs,
  normalizeFpsLimit,
} from "../web/frame-pacer.js";

// The offered limits have to stay a closed, sorted set the menu can render as-is,
// and "no cap" has to be expressible. Zero is the uncapped marker because it is
// the one value that cannot collide with a real frame rate.
assert.deepEqual([...FPS_LIMIT_CHOICES], [0, 30, 60, 120, 144, 240]);
assert.equal(FPS_LIMIT_CHOICES[0], 0, "uncapped has to remain the first choice");
assert.equal(DEFAULT_FPS_LIMIT, 0, "the game must not cap the frame rate the player did not ask to cap");
for (let i = 1; i < FPS_LIMIT_CHOICES.length; i += 1) {
  assert.ok(FPS_LIMIT_CHOICES[i] > FPS_LIMIT_CHOICES[i - 1], "the limit list must ascend");
}

assert.equal(framePeriodMs(60), 1000 / 60);
assert.equal(framePeriodMs(120), 1000 / 120);
assert.equal(framePeriodMs(0), 0, "uncapped has no frame period");

// A stored preference is untrusted: localStorage is editable by hand and survives
// across builds, so anything that is not an offered limit has to resolve to the
// default rather than to a number the menu cannot show.
assert.equal(normalizeFpsLimit(60), 60);
assert.equal(normalizeFpsLimit("60"), 60, "a value stored as text must still be read as a number");
assert.equal(normalizeFpsLimit("nope"), DEFAULT_FPS_LIMIT);
assert.equal(normalizeFpsLimit(null), DEFAULT_FPS_LIMIT);
assert.equal(normalizeFpsLimit(-30), DEFAULT_FPS_LIMIT);
assert.equal(normalizeFpsLimit(61), DEFAULT_FPS_LIMIT, "a limit the menu does not offer is not a limit");
assert.equal(normalizeFpsLimit(Number.NaN), DEFAULT_FPS_LIMIT);

// --- uncapped: every callback draws ------------------------------------------
const uncapped = createFramePacer({ limit: 0 });
for (const now of [0, 8, 16, 25, 33, 41, 50]) {
  assert.equal(uncapped.shouldRender(now), true, "an uncapped pacer must never drop a frame");
}

// --- capped at 60: one draw per ~16.7 ms -------------------------------------
const sixty = createFramePacer({ limit: 60 });
const drawn = [];
// A 120 Hz display, 8.33 ms between callbacks. Only every other tick may draw.
let clock = 0;
for (let tick = 0; tick < 24; tick += 1) {
  clock = tick * (1000 / 120);
  if (sixty.shouldRender(clock)) drawn.push(Number(clock.toFixed(2)));
}
assert.ok(drawn.length > 0 && drawn.length < 24, `a 60 cap must drop callbacks, drew ${drawn.length}/24`);
// Gaps between consecutive draws must be at least the cap period, with a small
// tolerance: 120 Hz ticks land on 16.67 ms boundaries, so an exact comparison
// would starve the cap and never draw at all.
for (let i = 1; i < drawn.length; i += 1) {
  const gap = drawn[i] - drawn[i - 1];
  assert.ok(gap >= 1000 / 60 - 1, `draw gap ${gap}ms is shorter than the 60 FPS period`);
}
// And the achieved rate must land near the cap rather than merely under it.
const span = drawn[drawn.length - 1] - drawn[0];
const achieved = ((drawn.length - 1) / span) * 1000;
assert.ok(achieved <= 61, `a 60 cap must not exceed 60 FPS, achieved ${achieved.toFixed(1)}`);
assert.ok(achieved >= 55, `a 60 cap must not starve the frame rate, achieved ${achieved.toFixed(1)}`);

// A cap that divides the display cadence badly still has to hold. 144 FPS on a
// 120 Hz panel: the period is 6.94 ms, so some ticks fall just inside it.
const oneFortyFour = createFramePacer({ limit: 144 });
let drew = 0;
for (let tick = 0; tick < 120; tick += 1) {
  if (oneFortyFour.shouldRender(tick * (1000 / 120))) drew += 1;
}
const rate144 = (drew / 120) * 120;
assert.ok(rate144 <= 144, `a 144 cap must not exceed 144 FPS, achieved ${rate144}`);
assert.ok(rate144 >= 120, `a 144 cap above the display rate must not drop ticks, achieved ${rate144}`);

// --- the cap is a ceiling, never a floor -------------------------------------
// A renderer that cannot keep up must still draw every callback it is offered:
// the pacer bounds the frame rate from above and must not invent a minimum that
// silently drops frames the machine was going to render anyway.
const tooSlow = createFramePacer({ limit: 120 });
let slowDrew = 0;
for (let tick = 0; tick < 60; tick += 1) {
  if (tooSlow.shouldRender(tick * 40)) slowDrew += 1; // 25 FPS of offered frames
}
assert.equal(slowDrew, 60, "a cap must not drop a frame the display was already going to skip");

// --- the cap must not be able to freeze the loop -----------------------------
// A clock that jumps backwards (a tab restored from bfcache, a system clock
// adjustment) must not park the pacer for an unbounded time.
const backwards = createFramePacer({ limit: 60 });
assert.equal(backwards.shouldRender(0), true);
assert.equal(backwards.shouldRender(1), false, "one ms after a draw is still inside the cap");
assert.equal(backwards.shouldRender(-500), true, "a backwards clock must draw, not stall until it catches up");
assert.equal(backwards.shouldRender(-499), false, "the cap still applies after recovering from a backwards clock");

// --- the display cadence, learned from the frames the display actually grants --
// Uncapped, the target has to follow the panel. A 120 Hz ProMotion display grants
// ~8.33 ms frames and the controller has to aim at that, not at a fixed 16.7 ms
// that would leave it permanently "inside budget" while actually dropping half
// the frames.
const learning = createFramePacer({ limit: 0 });
for (let tick = 0; tick < 120; tick += 1) learning.shouldRender(tick * (1000 / 120));
const fastTarget = learning.targetFrameMs;
assert.ok(fastTarget < 12, `a 120 Hz display must be learned as a fast target, got ${fastTarget.toFixed(2)}ms`);
assert.ok(fastTarget > 5, `the learned target must stay a plausible vsync period, got ${fastTarget.toFixed(2)}ms`);

// The same pacer on a 60 Hz panel has to learn 60, not inherit the 120 figure.
const sixtyHz = createFramePacer({ limit: 0 });
for (let tick = 0; tick < 240; tick += 1) sixtyHz.shouldRender(tick * (1000 / 60));
const slowTarget = sixtyHz.targetFrameMs;
assert.ok(slowTarget > 14, `a 60 Hz display must be learned as a ~16.7 ms target, got ${slowTarget.toFixed(2)}ms`);

// A display that gets slower has to be relearned, or the controller would aim at
// a refresh rate the panel can no longer deliver and degrade quality forever.
const degrading = createFramePacer({ limit: 0 });
for (let tick = 0; tick < 120; tick += 1) degrading.shouldRender(tick * (1000 / 120));
const beforeDrop = degrading.targetFrameMs;
for (let tick = 0; tick < 600; tick += 1) degrading.shouldRender(tick * (1000 / 60));
assert.ok(
  degrading.targetFrameMs > beforeDrop * 1.5,
  `a panel that drops to 60 Hz must be relearned, went ${beforeDrop.toFixed(2)} -> ${degrading.targetFrameMs.toFixed(2)}`,
);

// One freak fast callback must not convince the pacer the display runs at 500 Hz.
// The last tick above landed at 119 * (1000/60); a sub-millisecond follow-up is
// a coalesced or double-fired callback, not a refresh rate.
const outlier = createFramePacer({ limit: 0 });
for (let tick = 0; tick < 120; tick += 1) outlier.shouldRender(tick * (1000 / 60));
const beforeOutlier = outlier.targetFrameMs;
outlier.shouldRender(119 * (1000 / 60) + 0.4);
assert.ok(
  outlier.targetFrameMs > beforeOutlier * 0.9,
  `a single fast outlier must not drag the target down, went ${beforeOutlier.toFixed(2)} -> ${outlier.targetFrameMs.toFixed(2)}`,
);

// A backwards clock is not cadence evidence either, and must not be learned as one.
const backwardsClock = createFramePacer({ limit: 0 });
for (let tick = 0; tick < 120; tick += 1) backwardsClock.shouldRender(tick * (1000 / 60));
const beforeBackwards = backwardsClock.targetFrameMs;
backwardsClock.shouldRender(0);
assert.ok(
  backwardsClock.targetFrameMs > beforeBackwards * 0.9,
  "a backwards clock must not become the learned ceiling",
);

// A startup probe is the only way to learn the ceiling on a machine that is
// already too slow for its own frames to show it.
const probed = createFramePacer({ limit: 0, ceilingMs: 1000 / 120 });
assert.ok(
  Math.abs(probed.targetFrameMs - 1000 / 120) < 0.001,
  "a probed ceiling must be adopted as the target",
);
// A probe result that is not a plausible refresh rate must be ignored outright,
// leaving the 60 Hz fallback rather than becoming the target.
for (const bad of [0, 0.4, -8, 4000, Number.NaN, null, undefined, "nope"]) {
  const seeded = createFramePacer({ limit: 0, ceilingMs: bad });
  assert.ok(
    Math.abs(seeded.targetFrameMs - 1000 / 60) < 0.001,
    `an implausible probe (${String(bad)}) must leave the 60 Hz fallback, got ${seeded.targetFrameMs}`,
  );
}
// A probe must never raise a ceiling that is already known, and must never
// override an active cap.
const probedCapped = createFramePacer({ limit: 30, ceilingMs: 1000 / 144 });
assert.ok(
  Math.abs(probedCapped.targetFrameMs - 1000 / 30) < 0.001,
  "a probe must not override the cap the player chose",
);
const probing = createFramePacer({ limit: 0, ceilingMs: 1000 / 60 });
probing.seedCeiling(1000 / 120);
assert.ok(
  Math.abs(probing.targetFrameMs - 1000 / 120) < 0.001,
  "a faster probe must be adopted",
);
probing.seedCeiling(1000 / 30);
assert.ok(
  Math.abs(probing.targetFrameMs - 1000 / 120) < 0.001,
  "a slower probe must not raise a ceiling already known",
);

// --- an explicit cap overrides whatever the display is doing ------------------
// The target is what the quality controller measures against. With a cap set,
// the cap is the target: the renderer is on budget by construction whenever it
// meets the cap, and only misses it when it genuinely cannot keep up.
const cappedTarget = createFramePacer({ limit: 30 });
assert.ok(Math.abs(cappedTarget.targetFrameMs - 1000 / 30) < 0.001,
  "a 30 cap must target 33.3 ms regardless of the display");

// Changing the cap has to take effect without rebuilding the pacer.
cappedTarget.setLimit(120);
assert.equal(cappedTarget.limit, 120);
assert.ok(Math.abs(cappedTarget.targetFrameMs - 1000 / 120) < 0.001,
  "a new cap must become the target immediately");
// And the first callback after a change has to draw, or the loop stalls for a
// whole cap period every time the player moves the slider.
assert.equal(cappedTarget.shouldRender(0), true, "the first tick after a cap change must draw");

cappedTarget.setLimit(60);
assert.equal(cappedTarget.shouldRender(0), true, "the first tick after a cap change must draw");

// The learned cadence survives a cap being lifted, so switching back to uncapped
// does not have to relearn the panel from scratch.
const relearned = createFramePacer({ limit: 0 });
for (let tick = 0; tick < 120; tick += 1) relearned.shouldRender(tick * (1000 / 120));
const learned = relearned.targetFrameMs;
relearned.setLimit(60);
relearned.setLimit(0);
assert.ok(Math.abs(relearned.targetFrameMs - learned) < 0.001,
  "lifting the cap must not throw away the learned display cadence");

// A nonsense limit must not produce a period that stops the loop.
for (const bad of [Number.NaN, -1, 0.5, 1e9, "abc", null, undefined]) {
  const pacer = createFramePacer({ limit: bad });
  assert.equal(Number.isFinite(pacer.targetFrameMs), true, `limit ${String(bad)} must yield a usable target`);
  assert.equal(pacer.shouldRender(0), true, `limit ${String(bad)} must not block the first frame`);
}

// --- the startup cadence probe ------------------------------------------------
// The game seeds its ceiling from an empty animation-frame loop, so the probe has
// to resolve on a stubbed rAF and report the cadence it was given.
function stubRaf(intervalMs, { coalesce = [] } = {}) {
  const original = globalThis.requestAnimationFrame;
  const pending = new Map();
  let nextHandle = 1;
  let virtualNow = 0;
  globalThis.requestAnimationFrame = (cb) => {
    const handle = nextHandle;
    nextHandle += 1;
    pending.set(handle, cb);
    return handle;
  };
  return {
    async run() {
      // Drive the queue the way a compositor would: one callback per frame, with
      // the timestamp advancing by the display cadence.
      const result = measureDisplayCadenceMs({ frames: 8 });
      for (let step = 0; pending.size > 0; step += 1) {
        virtualNow += coalesce.includes(step) ? intervalMs / 20 : intervalMs;
        for (const [handle, cb] of [...pending]) {
          pending.delete(handle);
          cb(virtualNow);
        }
        if (step > 200) break;
      }
      return result;
    },
    restore() {
      globalThis.requestAnimationFrame = original;
    },
  };
}

const stub120 = stubRaf(1000 / 120);
const measured120 = await stub120.run();
stub120.restore();
assert.ok(
  Math.abs(measured120 - 1000 / 120) < 0.001,
  `the probe must report the cadence it was driven at, got ${measured120}`,
);

const stub60 = stubRaf(1000 / 60, { coalesce: [2] });
const measured60 = await stub60.run();
stub60.restore();
assert.ok(
  Math.abs(measured60 - 1000 / 60) < 0.001,
  `a coalesced callback must not drag the probe off the real cadence, got ${measured60}`,
);

// Without animation frames there is nothing to measure, and the probe has to say
// so rather than resolve with a number the controller would trust.
const savedRaf = globalThis.requestAnimationFrame;
globalThis.requestAnimationFrame = undefined;
assert.equal(await measureDisplayCadenceMs(), null, "no rAF must resolve to null, not a guess");
globalThis.requestAnimationFrame = savedRaf;

console.log("frame pacer ok");
