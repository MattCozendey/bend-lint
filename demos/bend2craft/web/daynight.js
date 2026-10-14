// Pure day/night cycle helpers. Time is a fraction of a full day:
// 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight.
// Dependency-free and testable without a browser.

export const DAY_LENGTH = 600;
export const DAY_SKY = Object.freeze([0.44, 0.68, 0.95]);
export const NIGHT_SKY = Object.freeze([0.02, 0.03, 0.09]);
export const SUNRISE_SKY = Object.freeze([0.98, 0.55, 0.35]);

const SKY_KEYS = [
  [0, SUNRISE_SKY],
  [0.08, [0.55, 0.72, 0.95]],
  [0.25, DAY_SKY],
  [0.42, [0.5, 0.62, 0.9]],
  [0.5, [0.95, 0.45, 0.3]],
  [0.58, [0.08, 0.1, 0.22]],
  [0.75, NIGHT_SKY],
  [0.92, [0.06, 0.08, 0.2]],
  [1, SUNRISE_SKY],
];

function lerp(a, b, t) {
  return a + (b - a) * t;
}

export function advanceTime(time, dt) {
  const next = time + dt / DAY_LENGTH;
  return next >= 1 ? next % 1 : next;
}

export function dayCount(elapsedSeconds) {
  return Math.floor(elapsedSeconds / DAY_LENGTH) + 1;
}

export function isDay(time) {
  return time >= 0 && time < 0.5;
}

export function skyColor(time) {
  const t = ((time % 1) + 1) % 1;
  for (let i = 0; i < SKY_KEYS.length - 1; i += 1) {
    const [t0, c0] = SKY_KEYS[i];
    const [t1, c1] = SKY_KEYS[i + 1];
    if (t >= t0 && t <= t1) {
      if (t === t0) return [...c0];
      if (t === t1) return [...c1];
      const f = (t - t0) / (t1 - t0);
      return [lerp(c0[0], c1[0], f), lerp(c0[1], c1[1], f), lerp(c0[2], c1[2], f)];
    }
  }
  return [...NIGHT_SKY];
}

export function brightness(time) {
  const t = ((time % 1) + 1) % 1;
  // Full light through the day, smooth dip to a dim (never pitch black) night.
  if (t < 0.42) return 1;
  if (t < 0.58) {
    const f = (t - 0.42) / 0.16;
    return lerp(1, 0.32, smooth(f));
  }
  if (t < 0.92) return 0.32;
  const f = (t - 0.92) / 0.08;
  return lerp(0.32, 1, smooth(f));
}

function smooth(t) {
  return t * t * (3 - 2 * t);
}
