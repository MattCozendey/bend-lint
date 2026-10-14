import assert from "node:assert/strict";
import { createAudioMixer, getAudioMixer, resetAudioMixer } from "../web/audio.js";

// A recording stand-in for WebAudio. The mixer has to route the ambient tone to
// the ambience bus and everything else to the effects bus, so the fake records
// the graph rather than pretending the calls did nothing.
function fakeContextClass() {
  const log = [];
  class FakeAudioContext {
    constructor() {
      this.currentTime = 1;
      this.state = "running";
      this.destination = { name: "destination" };
      this.closed = false;
      log.push(this.destination);
    }
    createGain() {
      const node = {
        name: "gain",
        gain: { value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} },
        connections: [],
        connect(target) { this.connections.push(target); },
      };
      log.push(node);
      return node;
    }
    createOscillator() {
      const oscillator = {
        type: "",
        frequency: { setValueAtTime() {} },
        connections: [],
        connect(target) { this.connections.push(target); },
        start(at) { this.startedAt = at; },
        stop(at) { this.stoppedAt = at; },
      };
      log.push(oscillator);
      return oscillator;
    }
    resume() {}
    close() { this.closed = true; }
  }
  FakeAudioContext.log = log;
  return FakeAudioContext;
}

const FakeAudioContext = fakeContextClass();
const mixer = createAudioMixer({ AudioContextCtor: FakeAudioContext });

// Default volumes have to be a sane listening level, not the old hardcoded 0.18.
const defaults = mixer.volumes;
assert.ok(defaults.master > 0 && defaults.master <= 1);
assert.ok(defaults.music > 0 && defaults.music <= 1);
assert.ok(defaults.effects > 0 && defaults.effects <= 1);

assert.equal(mixer.ensure(), true);
assert.equal(mixer.play("click"), true);
assert.equal(mixer.play("click"), false, "rapid duplicate sounds should be throttled");
mixer.destroy();

// The graph has to be master -> {music, effects} -> destination, because that is
// the only shape where a player can turn the ambience down without touching the
// footsteps. A single bus cannot express the setting the menu now offers.
const Ctx = fakeContextClass();
const routed = createAudioMixer({ AudioContextCtor: Ctx, minInterval: 0 });
assert.equal(routed.ensure(), true);
// The first three gains are master, then music, then effects.
const [master, music, effects] = Ctx.log.filter((entry) => entry?.name === "gain");
assert.ok(master !== undefined && music !== undefined && effects !== undefined,
  "the mixer must build a master and two buses");
assert.deepEqual(music.connections, [master], "ambience must reach the master");
assert.deepEqual(effects.connections, [master], "effects must reach the master");
assert.deepEqual(master.connections, [Ctx.log[0]],
  "the master must reach the destination and nothing else");

// setVolumes has to reach the live nodes, and has to survive a partial update by
// keeping the buses it was not given.
const live = createAudioMixer({ AudioContextCtor: Ctx, minInterval: 0 });
live.ensure();
assert.deepEqual(live.setVolumes({ master: 0.5 }), { master: 0.5, music: defaults.music, effects: defaults.effects },
  "a partial update must not reset the other buses");
assert.deepEqual(live.setVolumes({ master: 4, music: -2, effects: 0.25 }),
  { master: 1, music: 0, effects: 0.25 }, "out-of-range volumes must clamp");
// A junk value has to leave the level that is already playing alone rather than
// snapping it to the default, which would be audible as a jump.
const before = live.volumes;
assert.deepEqual(live.setVolumes({ master: "loud" }), before,
  "a non-numeric volume must leave the current level alone");
assert.deepEqual(live.volumes, before,
  "the reported volumes must match what was applied");

// A muted master or a muted bus must not schedule anything, or the game pays for
// oscillators nobody can hear and the throttler marks the sound as played.
const muted = createAudioMixer({ AudioContextCtor: Ctx, minInterval: 0 });
muted.ensure();
muted.setVolumes({ master: 0 });
assert.equal(muted.play("click"), false, "a muted master must silence everything");
muted.setVolumes({ master: 1, effects: 0 });
assert.equal(muted.play("break"), false, "a muted effects bus must silence effects");
assert.equal(muted.play("ambient"), true, "a muted effects bus must not silence ambience");

// The menu and the game have to end up on the same graph, or the volume a player
// dials in is not the volume they get.
resetAudioMixer();
const shared = getAudioMixer({ AudioContextCtor: Ctx });
assert.equal(getAudioMixer(), shared, "the mixer must be shared between menu and game");
shared.destroy();
resetAudioMixer();
assert.notEqual(getAudioMixer({ AudioContextCtor: Ctx }), shared, "a reset must drop the shared instance");

// A context that cannot be constructed is not a crash: the game still runs silent.
assert.equal(createAudioMixer({ AudioContextCtor: undefined }).ensure(), false);
assert.equal(createAudioMixer({ AudioContextCtor: undefined }).play("click"), false);

// A schedule's optional start offset has to reach the oscillator, or a sound
// that needs to unfold over time plays as one simultaneous chord. The stop has
// to move with the start, or a delayed note is cut off the instant it begins.
const TimedCtx = fakeContextClass();
const timed = createAudioMixer({ AudioContextCtor: TimedCtx, minInterval: 0 });
timed.ensure();
timed.play("burn");
const fired = TimedCtx.log.filter((entry) => typeof entry?.startedAt === "number");
assert.ok(fired.length >= 3, `the fire schedule should schedule several notes, got ${fired.length}`);
assert.ok(new Set(fired.map((entry) => entry.startedAt)).size > 1,
  "the fire crackle notes must not all start at the same instant");
for (const entry of fired) {
  assert.ok(entry.stoppedAt > entry.startedAt,
    "a delayed note must still be given its full duration after its start");
}
assert.ok(fired.some((entry) => entry.startedAt > 1),
  "at least one note must start after the context clock, which the fake pins at 1");
timed.destroy();

console.log("audio mixer ok");
