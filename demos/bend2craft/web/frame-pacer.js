// Frame pacing: the one place that decides whether an animation-frame callback
// is allowed to draw, and what frame budget the adaptive quality controller is
// measured against.
//
// Two things live here because they are the same fact seen from both ends. A cap
// ("60 FPS") is a promise about the interval between drawn frames, and "am I over
// budget" is a question about that same interval. Keeping them apart is how a
// 30 FPS cap ends up looking like a renderer that cannot keep up: the controller
// reads the capped 33.3 ms interval, compares it to a budget derived from an
// uncapped assumption, and degrades the picture at the exact frame rate the
// player asked for.
//
// The pacer is pure and browser-free so the pacing rules can be tested without a
// compositor, which is also the only place they can be tested exhaustively.

/** "No cap" is zero: the one value that cannot collide with a real frame rate. */
export const UNCAPPED_FPS = 0;

/**
 * The limits the menu offers, ascending, with uncapped first.
 *
 * The set is deliberately short. Every entry is a frame rate a display or GPU
 * actually runs at, so the menu never offers a number that is really a divisor of
 * another one and cannot be hit exactly.
 */
export const FPS_LIMIT_CHOICES = Object.freeze([UNCAPPED_FPS, 30, 60, 120, 144, 240]);

/** The game does not cap a frame rate the player never asked it to cap. */
export const DEFAULT_FPS_LIMIT = UNCAPPED_FPS;

/**
 * Below this an observed interval is a measurement artefact rather than a
 * display cadence: a coalesced or double-fired callback, or a timestamp from a
 * different clock. Real panels bottom out around 2 ms (500 Hz), and treating a
 * 0.4 ms frame as the ceiling would aim the quality controller at an impossible
 * target and degrade the picture forever.
 */
export const MIN_PLAUSIBLE_CADENCE_MS = 2;

/**
 * Above this the interval is not cadence either, but a stall: shader
 * compilation, a chunk burst, a tab that was hidden. A panel cannot refresh
 * slower than this, and a one-off stall must not become the new ceiling.
 */
export const MAX_PLAUSIBLE_CADENCE_MS = 100;

/**
 * How fast the learned ceiling is allowed to creep back up when the display gets
 * slower (a window dragged onto a 60 Hz monitor, or a thermal drop). Dropping is
 * instant because a faster cadence is unambiguous evidence; rising is eased so a
 * single slow frame cannot ratchet the target somewhere the renderer can never
 * satisfy, which would walk the quality ladder to the bottom and stay there.
 */
const CEILING_RELAXATION = 0.02;

/**
 * Slack when comparing against the cap period. Callback timestamps on a 120 Hz
 * panel land on 8.333 ms boundaries, so 60 FPS (16.667 ms) has to accept a frame
 * that is a floating-point hair short of its own period. Without it a 60 cap on
 * a 120 Hz display skips every tick and renders nothing.
 */
const CAP_TOLERANCE_MS = 0.5;

/** Frame period for a limit, in milliseconds. Uncapped has no period. */
export function framePeriodMs(fps) {
  const parsed = Number(fps);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  return 1000 / parsed;
}

/**
 * Resolve a stored value to an offered limit.
 *
 * A preference is untrusted: localStorage is hand-editable and survives across
 * builds, so a value the menu does not offer resolves to uncapped. That is the
 * safe direction - it restores the behaviour from before the cap existed rather
 * than pinning the game to a frame rate the player never chose and cannot undo.
 */
export function normalizeFpsLimit(value) {
  const parsed = Number(value);
  return FPS_LIMIT_CHOICES.includes(parsed) ? parsed : DEFAULT_FPS_LIMIT;
}

/** A usable frame target, or null when the value cannot be one. */
function usableTarget(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

export function createFramePacer({ limit = DEFAULT_FPS_LIMIT, ceilingMs = null } = {}) {
  let capped = normalizeFpsLimit(limit);
  // `lastDrawn` is negative infinity rather than 0 so the first callback always
  // draws, whatever the clock reads at boot.
  let lastDrawn = Number.NEGATIVE_INFINITY;
  let lastCallback = null;
  // The display's cadence, learned from the intervals the compositor actually
  // granted. Seeded from a startup probe when one is available, because before
  // the probe the only frames on record are the slow ones from world bootstrap.
  let ceiling = null;

  /** Adopt a cadence only if it could be a real refresh interval. */
  function adoptCeiling(value) {
    const candidate = usableTarget(value);
    if (candidate === null) return;
    if (candidate < MIN_PLAUSIBLE_CADENCE_MS || candidate > MAX_PLAUSIBLE_CADENCE_MS) return;
    if (ceiling === null || candidate < ceiling) ceiling = candidate;
  }

  function learnCadence(intervalMs) {
    // Only uncapped ticks reveal the display: while capped, the interval between
    // callbacks is how fast the renderer happens to be going, not what the panel
    // can do, and learning from it would aim the controller at its own backlog.
    if (capped !== UNCAPPED_FPS) return;
    // A non-positive interval means the clock moved backwards, and one outside
    // the plausible range is a stall or a coalesced callback. Neither is cadence.
    if (!Number.isFinite(intervalMs)) return;
    if (intervalMs < MIN_PLAUSIBLE_CADENCE_MS || intervalMs > MAX_PLAUSIBLE_CADENCE_MS) return;
    if (ceiling === null || intervalMs < ceiling) ceiling = intervalMs;
    else ceiling += (intervalMs - ceiling) * CEILING_RELAXATION;
  }

  adoptCeiling(ceilingMs);

  return {
    get limit() {
      return capped;
    },
    get periodMs() {
      return framePeriodMs(capped);
    },
    /**
     * The period the renderer is being asked to hit. With a cap that is the cap:
     * the renderer is on budget whenever it meets the limit, and misses it only
     * when it genuinely cannot keep up. Without one it is the learned display
     * cadence, falling back to 60 Hz until enough frames have been seen to tell.
     */
    get targetFrameMs() {
      if (capped !== UNCAPPED_FPS) return framePeriodMs(capped);
      return ceiling ?? 1000 / 60;
    },
    /** The learned display cadence, or null when nothing plausible has been seen. */
    get ceilingMs() {
      return ceiling;
    },
    /** Adopt a measured cadence without disturbing the cap or the last draw. */
    seedCeiling(value) {
      adoptCeiling(value);
    },
    setLimit(value) {
      capped = normalizeFpsLimit(value);
      // The new period starts now, not one period from the last draw: otherwise
      // every nudge of the slider costs a full cap period of frozen frame.
      lastDrawn = Number.NEGATIVE_INFINITY;
      return capped;
    },
    /**
     * Consume one animation-frame callback and report whether it may draw.
     *
     * The cap is a ceiling and never a floor. A renderer already slower than the
     * limit is offered fewer callbacks than it would like, and dropping those
     * would invent frame drops the machine was not going to take.
     */
    shouldRender(nowMs) {
      const now = Number(nowMs);
      const usable = Number.isFinite(now) ? now : lastCallback ?? 0;
      if (lastCallback !== null) learnCadence(usable - lastCallback);
      lastCallback = usable;
      if (capped === UNCAPPED_FPS) {
        lastDrawn = usable;
        return true;
      }
      // A clock that went backwards cannot be compared against a period; draw
      // rather than stall the loop for an unbounded time.
      if (usable - lastDrawn < 0) {
        lastDrawn = usable;
        return true;
      }
      if (usable - lastDrawn < this.periodMs - CAP_TOLERANCE_MS) return false;
      lastDrawn = usable;
      return true;
    },
  };
}

/**
 * Measure the display's refresh cadence from an empty animation-frame loop.
 *
 * The game cannot infer the ceiling from its own frames: if the renderer is
 * already too slow, every interval on record is slow, and a controller aiming at
 * that "ceiling" concludes it is comfortably on budget while dropping half its
 * frames. An empty loop has no work to do, so whatever cadence it sees is the
 * display's, and a few frames of it are cheaper than a permanently soft picture.
 *
 * Returns the median interval in milliseconds, or null when the caller has no
 * animation frames to offer.
 */
export function measureDisplayCadenceMs({ frames = 10 } = {}) {
  return new Promise((resolve) => {
    if (typeof globalThis.requestAnimationFrame !== "function") {
      resolve(null);
      return;
    }
    const count = Math.max(3, Math.trunc(Number(frames) || 0));
    const intervals = [];
    let previous = null;
    const finish = () => {
      const usable = intervals.filter((value) => value >= MIN_PLAUSIBLE_CADENCE_MS
        && value <= MAX_PLAUSIBLE_CADENCE_MS);
      if (usable.length === 0) {
        resolve(null);
        return;
      }
      // The median, not the minimum: one coalesced callback at half a millisecond
      // would otherwise report a cadence no display has.
      usable.sort((a, b) => a - b);
      resolve(usable[Math.floor(usable.length / 2)]);
    };
    const tick = (now) => {
      if (previous !== null) intervals.push(now - previous);
      previous = now;
      if (intervals.length >= count) {
        finish();
        return;
      }
      globalThis.requestAnimationFrame(tick);
    };
    globalThis.requestAnimationFrame(tick);
  });
}
