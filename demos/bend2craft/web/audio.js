import { toneSchedule } from "./sfx.js";

// The ambient tone is the only long-form sound in the game, so it is the one that
// belongs on its own bus: a player who wants the world audible but the music gone
// needs somewhere to turn it down that is not the master.
const MUSIC_KINDS = new Set(["ambient"]);

function clampVolume(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(0, Math.min(1, parsed));
}

/**
 * Two-bus mixer: everything goes through a master, then splits into ambience and
 * effects. Volumes are live, so a slider can be moved while the game is running
 * and be heard immediately.
 */
export function createAudioMixer({ AudioContextCtor = globalThis.AudioContext, minInterval = 0.06 } = {}) {
  let context = null;
  let master = null;
  let music = null;
  let effects = null;
  const lastPlayed = new Map();
  let volumes = { master: 0.7, music: 0.7, effects: 0.9 };

  function applyVolumes() {
    if (master === null) return;
    // A gain of exactly 0 is legal but exponential ramps cannot reach it, so the
    // mute is handled by the master value itself rather than by skipping audio.
    master.gain.value = volumes.master;
    music.gain.value = volumes.music;
    effects.gain.value = volumes.effects;
  }

  function ensure() {
    if (context !== null) {
      if (context.state === "suspended") context.resume?.();
      return true;
    }
    if (typeof AudioContextCtor !== "function") return false;
    context = new AudioContextCtor();
    master = context.createGain();
    music = context.createGain();
    effects = context.createGain();
    music.connect(master);
    effects.connect(master);
    master.connect(context.destination);
    applyVolumes();
    context.resume?.();
    return true;
  }

  function play(kind) {
    if (!ensure()) return false;
    if (volumes.master <= 0) return false;
    const bus = MUSIC_KINDS.has(kind) ? music : effects;
    if (bus.gain.value <= 0) return false;
    const now = Number(context.currentTime ?? 0);
    if (now - (lastPlayed.get(kind) ?? -Infinity) < minInterval) return false;
    lastPlayed.set(kind, now);
    for (const [frequency, duration, type, volume, offset = 0] of toneSchedule(kind)) {
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      // The offset is what spreads a schedule out in time. Both the envelope and
      // the stop have to move with the start, or a delayed note begins already
      // silent and is cut off the instant it is scheduled.
      const start = now + offset;
      oscillator.type = type;
      oscillator.frequency.setValueAtTime(frequency, start);
      gain.gain.setValueAtTime(volume, start);
      gain.gain.exponentialRampToValueAtTime(0.001, start + duration);
      oscillator.connect(gain);
      gain.connect(bus);
      oscillator.start(start);
      oscillator.stop(start + duration);
    }
    return true;
  }

  function setVolumes(next = {}) {
    volumes = {
      master: clampVolume(next.master, volumes.master),
      music: clampVolume(next.music, volumes.music),
      effects: clampVolume(next.effects, volumes.effects),
    };
    applyVolumes();
    return { ...volumes };
  }

  function destroy() {
    context?.close?.();
    context = null;
    master = null;
    music = null;
    effects = null;
    lastPlayed.clear();
  }

  return Object.freeze({
    ensure,
    play,
    setVolumes,
    get volumes() {
      return { ...volumes };
    },
    destroy,
  });
}

// The menu and the game both need the same mixer, or the volume a player sets in
// the menu would be heard on a different graph than the one the game plays.
// Browsers cap the number of live AudioContexts, so a second one is not free.
let shared = null;

export function getAudioMixer(options = {}) {
  if (shared === null) shared = createAudioMixer(options);
  return shared;
}

/** Test seam: drops the shared instance so a case can install its own. */
export function resetAudioMixer() {
  shared?.destroy();
  shared = null;
}
