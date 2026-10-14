// World-time to daylight: 0.28 at the darkest night, 1 at noon. The game and
// the multiplayer server both read it (the server decides when monsters spawn
// and burn), so the formula lives in one place.

// How fast the day turns, in radians a second: a day is 2*PI / DAY_RATE seconds.
export const DAY_RATE = 0.08;

export function daylightForTime(time) {
  return 0.28 + 0.72 * (0.5 + 0.5 * Math.sin(Number(time) * DAY_RATE));
}

// How far round its day a world-time is, in radians from 0 up to a whole turn: 0 is the
// morning the clock starts on and a quarter turn is noon. The native client's sky is a rule
// on this angle (native/sky.bend), which is how its noon is the browsers' noon.
export function dayTurn(time) {
  const turn = (Number(time) * DAY_RATE) % (2 * Math.PI);
  return turn < 0 ? turn + 2 * Math.PI : turn;
}

// Below this, night monsters spawn.
export const NIGHT_DAYLIGHT = 0.4;
