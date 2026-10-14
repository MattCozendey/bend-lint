// Procedural sound schedules. Pure data so the mix can be tested;
// the browser adapter in main.js turns schedules into WebAudio notes.
//
// A note is [frequency, duration, wave, gain, startOffset]. Without the offset
// every note in a kind fires at the same instant, which is right for a two-tone
// chime and wrong for anything that has to unfold - a fire that crackles, a
// footstep that lands. The offset is what spreads those notes out.

export const TONES = Object.freeze({
  click: Object.freeze([[660, 0.05, "square", 0.05]]),
  break: Object.freeze([[170, 0.09, "sawtooth", 0.08]]),
  place: Object.freeze([[240, 0.07, "square", 0.07]]),
  hurt: Object.freeze([[110, 0.18, "sawtooth", 0.1]]),
  eat: Object.freeze([[520, 0.07, "sine", 0.09], [680, 0.09, "sine", 0.09]]),
  death: Object.freeze([[220, 0.5, "sawtooth", 0.1]]),
  splash: Object.freeze([[392, 0.12, "triangle", 0.08], [523, 0.16, "triangle", 0.08]]),
  step: Object.freeze([[140, 0.05, "triangle", 0.035]]),
  land: Object.freeze([[90, 0.1, "triangle", 0.07]]),
  oink: Object.freeze([[320, 0.08, "square", 0.06], [260, 0.1, "square", 0.06]]),
  groan: Object.freeze([[85, 0.28, "sawtooth", 0.08]]),
  // One voice per farm animal. A cow that squeals like a pig is the same mistake
  // as a brute drawn as a pig: the player is told the wrong thing about what is
  // standing in front of them.
  baa: Object.freeze([[300, 0.22, "sawtooth", 0.07], [268, 0.2, "sawtooth", 0.05]]),
  moo: Object.freeze([[118, 0.34, "sawtooth", 0.08], [96, 0.3, "sawtooth", 0.05]]),
  cluck: Object.freeze([[520, 0.05, "square", 0.05], [430, 0.06, "square", 0.045]]),
  pop: Object.freeze([[500, 0.06, "sine", 0.07]]),
  // Fire is a low roar with three short crackles scattered over it. All four
  // notes at once would just be a chord, and a chord is a beep; the offsets are
  // the whole difference between a fire and a click.
  burn: Object.freeze([
    [130, 0.55, "sawtooth", 0.04],
    [186, 0.5, "sawtooth", 0.028],
    [430, 0.05, "square", 0.03, 0.02],
    [610, 0.04, "square", 0.024, 0.11],
    [520, 0.06, "square", 0.02, 0.23],
  ]),
  ambient: Object.freeze([[196, 1.2, "sine", 0.012], [247, 1.4, "sine", 0.008]]),
});

export function toneSchedule(kind) {
  return TONES[kind] ?? TONES.click;
}
