import assert from "node:assert/strict";
import { Redstone, RedstoneClock as Clock, RedstoneGrid } from "../web/bend-modules.js";

const EMPTY = { $: "Nil" };
// The dust flood runs on a window the size of the circuit, and the array is the
// caller's own: the contract writes its reached marks into it in place. One buffer
// for the whole file, reset whenever the window moves, is what the browser does -
// the index is relative to the window's origin, so a mark left under one layout
// would otherwise be read as dust at a different cell under the next.
const buffer = { grid: new Uint32Array(64), key: null };
const windowFor = (core) => {
  const window = RedstoneGrid.flood_of_state(core);
  const cells = Number(RedstoneGrid.flood_cells(window));
  if (buffer.grid.length < cells) buffer.grid = new Uint32Array(cells);
  const key = `${window.ox},${window.oy},${window.oz},${window.width},${window.depth},${window.height}`;
  if (buffer.key !== key) {
    buffer.grid.fill(0);
    buffer.key = key;
  }
  return { window, grid: buffer.grid };
};

// Run `count` game ticks and hand back the settled core and timers.
function run(core, timers, count) {
  let state = core;
  let clock = timers;
  for (let tick = 0; tick < count; tick += 1) {
    const result = tickOnce(state, clock);
    state = Clock.tick_core(result);
    clock = Clock.tick_timers(result);
  }
  return [state, clock];
}

const tickOnce = (core, timers) => {
  const { window, grid } = windowFor(core);
  return Clock.tick(core, timers, window, grid).fst;
};

const repeaterOut = (timers, x = 5n, y = 0n, z = 0n) => Number(Clock.repeater_out(timers, x, y, z));
const comparatorOut = (timers, x = 5n, y = 0n, z = 0n) => Number(Clock.comparator_out(timers, x, y, z));

// --- direction arithmetic ----------------------------------------------------
// A repeater faces one of four ways; the cell behind it is the face turned
// around, and the two cells that lock it are on the other axis.
assert.equal(Number(Clock.back_dir(Clock.dir_east())), Clock.dir_west());
assert.equal(Number(Clock.back_dir(Clock.dir_west())), Clock.dir_east());
assert.equal(Number(Clock.back_dir(Clock.dir_south())), Clock.dir_north());
assert.equal(Number(Clock.back_dir(Clock.dir_north())), Clock.dir_south());
assert.equal(Number(Clock.front_x(Clock.dir_east(), 4n)), 5);
assert.equal(Number(Clock.front_x(Clock.dir_west(), 4n)), 3);
assert.equal(Number(Clock.front_z(Clock.dir_south(), 4n)), 5);
assert.equal(Number(Clock.front_z(Clock.dir_north(), 4n)), 3);
// Facing along x leaves x alone for the side cells and steps z, and the reverse.
assert.equal(Number(Clock.side_x(Clock.dir_east(), 4n, 0)), 4);
assert.equal(Number(Clock.side_z(Clock.dir_east(), 4n, 0)), 5);
assert.equal(Number(Clock.side_x(Clock.dir_south(), 4n, 0)), 5);
assert.equal(Number(Clock.side_z(Clock.dir_south(), 4n, 0)), 4);

assert.equal(Number(Clock.repeater_delay(0)), 2);
assert.equal(Number(Clock.repeater_delay(3)), 8);
assert.equal(Number(Clock.repeater_setting(9)), 3, "a setting past the top clamps");

// --- a repeater holds its input for the ticks its setting asks for ----------
// A repeater at (5, 0, 0) facing east, dust in front of it at (6, 0, 0) and a
// lever behind it at (4, 0, 0). The lever goes live on the second tick, so the
// output must go live `latency` ticks later: vanilla's four settings answer in
// two, four, six and eight game ticks.
function repeaterTrace(setting) {
  let core = Redstone.place_wire(Redstone.empty(), 6n, 0n, 0n);
  core = Redstone.place_lever(core, 4n, 0n, 0n, false);
  let timers = Clock.place_repeater(Clock.empty(), 5n, 0n, 0n, Clock.dir_east(), setting);
  const trace = [];
  for (let tick = 0; tick < 12; tick += 1) {
    if (tick === 1) core = Redstone.flip_lever(core, 4n, 0n, 0n);
    const result = tickOnce(core, timers);
    core = Clock.tick_core(result);
    timers = Clock.tick_timers(result);
    trace.push(repeaterOut(timers));
  }
  return trace;
}

assert.equal(repeaterTrace(0).indexOf(15), 3, "setting one answers two ticks after the signal");
assert.equal(repeaterTrace(1).indexOf(15), 5, "setting two answers in four ticks");
assert.equal(repeaterTrace(2).indexOf(15), 7, "setting three answers in six ticks");
assert.equal(repeaterTrace(3).indexOf(15), 9, "setting four answers in eight ticks");
assert.deepEqual(repeaterTrace(0).slice(0, 3), [0, 0, 0], "and the output never moves early");

// The core settles after the timers run, so the dust in front reads full power
// in the same tick the repeater's output moves.
{
  let core = Redstone.place_wire(Redstone.empty(), 6n, 0n, 0n);
  core = Redstone.place_lever(core, 4n, 0n, 0n, false);
  const timers = Clock.place_repeater(Clock.empty(), 5n, 0n, 0n, Clock.dir_east(), 0);
  const [state, clock] = run(Redstone.flip_lever(core, 4n, 0n, 0n), timers, 4);
  assert.equal(repeaterOut(clock), 15, "the repeater is driving");
  assert.equal(Number(Redstone.wire_power(state, 6n, 0n, 0n)), 15, "and the dust in front reads it");
}

// Turning the lever off walks the signal back down the same delay.
{
  let core = Redstone.place_wire(Redstone.empty(), 6n, 0n, 0n);
  core = Redstone.place_lever(core, 4n, 0n, 0n, true);
  const timers = Clock.place_repeater(Clock.empty(), 5n, 0n, 0n, Clock.dir_east(), 0);
  const [held, heldTimers] = run(core, timers, 6);
  assert.equal(repeaterOut(heldTimers), 15, "held on, the repeater stays on");
  const [state, clock] = run(Redstone.flip_lever(held, 4n, 0n, 0n), heldTimers, 4);
  assert.equal(repeaterOut(clock), 0, "released, it goes off after the same delay");
  assert.equal(Number(Redstone.wire_power(state, 6n, 0n, 0n)), 0, "and the dust follows it down");
}

// --- a power on the side locks the repeater off ------------------------------
{
  let core = Redstone.place_wire(Redstone.empty(), 6n, 0n, 0n);
  core = Redstone.place_lever(core, 4n, 0n, 0n, true);
  core = Redstone.place_power_block(core, 5n, 0n, 1n);
  const timers = Clock.place_repeater(Clock.empty(), 5n, 0n, 0n, Clock.dir_east(), 0);
  const [state, clock] = run(core, timers, 8);
  assert.equal(repeaterOut(clock), 0, "a repeater powered from the side is held off");
  assert.equal(Number(Redstone.wire_power(state, 6n, 0n, 0n)), 0, "so it drives nothing");
}

// --- a repeater on a coordinate plane is not locked by itself ----------------
{
  // The side step off z = 0 saturates back onto the repeater's own cell, which
  // would otherwise read its own output and lock itself off for ever.
  let core = Redstone.place_wire(Redstone.empty(), 6n, 0n, 0n);
  core = Redstone.place_lever(core, 4n, 0n, 0n, false);
  const timers = Clock.place_repeater(Clock.empty(), 5n, 0n, 0n, Clock.dir_east(), 0);
  const [state, clock] = run(Redstone.flip_lever(core, 4n, 0n, 0n), timers, 4);
  assert.equal(repeaterOut(clock), 15, "a repeater standing on z = 0 still answers");
  assert.equal(Number(Redstone.wire_power(state, 6n, 0n, 0n)), 15);
}

// --- a comparator subtracts, and compares ------------------------------------
assert.equal(Clock.comparator_target(Clock.comparator_subtract(), 15, 0), 15, "no side passes the back through");
assert.equal(Clock.comparator_target(Clock.comparator_subtract(), 15, 5), 10, "subtract takes the difference");
assert.equal(Clock.comparator_target(Clock.comparator_subtract(), 5, 15), 0, "and never goes below zero");
assert.equal(Clock.comparator_target(Clock.comparator_compare(), 15, 10), 15, "compare passes when the back is stronger");
assert.equal(Clock.comparator_target(Clock.comparator_compare(), 10, 15), 0, "and blocks when a side is stronger");
assert.equal(Clock.comparator_target(Clock.comparator_compare(), 10, 10), 15, "an equal signal still passes");

// The same rules through the whole tick, driving a comparator at (5, 0, 0)
// facing east: the back is (4, 0, 0) and the sides are (5, 0, 1) and (5, 0, 0).
// `side_signal` drops the side that did not move, so only (5, 0, 1) counts.
function comparatorRun(back, side, mode) {
  let core = Redstone.empty();
  if (back > 0) core = Redstone.place_power_block(core, 4n, 0n, 0n);
  if (side > 0) core = Redstone.place_power_block(core, 5n, 0n, 1n);
  const timers = Clock.place_comparator(Clock.empty(), 5n, 0n, 0n, Clock.dir_east(), mode);
  return comparatorOut(run(core, timers, 8)[1]);
}

assert.equal(comparatorRun(15, 0, Clock.comparator_subtract()), 15, "nothing on the side passes through");
assert.equal(comparatorRun(15, 0, Clock.comparator_compare()), 15);
assert.equal(comparatorRun(15, 15, Clock.comparator_subtract()), 0, "an equal side cancels the back");
assert.equal(comparatorRun(15, 15, Clock.comparator_compare()), 15, "but compare mode lets it through");
assert.equal(comparatorRun(0, 0, Clock.comparator_compare()), 0, "nothing in, nothing out");

// --- a pulse train through the delay ----------------------------------------
// A lever toggled every twelve ticks, fed through a one-tick repeater: the
// output must be the input shifted by the repeater's latency, and nothing else.
// The period is wider than the longest delay so every setting still passes the
// whole pulse - a delay longer than the pulse would flatten it, which is a real
// consequence and not something to paper over here.
function pulseTrain(setting, period, ticks) {
  let core = Redstone.place_wire(Redstone.empty(), 6n, 0n, 0n);
  core = Redstone.place_lever(core, 4n, 0n, 0n, false);
  let timers = Clock.place_repeater(Clock.empty(), 5n, 0n, 0n, Clock.dir_east(), setting);
  let engaged = false;
  const trace = [];
  for (let tick = 0; tick < ticks; tick += 1) {
    const high = Math.floor(tick / period) % 2 === 1;
    if (high !== engaged) {
      core = Redstone.flip_lever(core, 4n, 0n, 0n);
      engaged = high;
    }
    const result = tickOnce(core, timers);
    core = Clock.tick_core(result);
    timers = Clock.tick_timers(result);
    trace.push([high ? 1 : 0, repeaterOut(timers)]);
  }
  return trace;
}

for (const [setting, latency] of [[0, 2], [1, 4], [3, 8]]) {
  const train = pulseTrain(setting, 12, 48);
  const shifted = train.map(([input], index) => (index - latency >= 0 ? train[index - latency][0] : 0));
  assert.deepEqual(
    train.map(([, output]) => (output ? 1 : 0)),
    shifted,
    `setting ${setting} shifts the input by exactly ${latency} ticks`,
  );
}

// A setting changes when the train arrives and nothing about its shape: the
// slower train's first rising edge is later, and its pulse is the same width.
const riseOf = (setting) => {
  const trace = pulseTrain(setting, 12, 48).map(([, output]) => output);
  return trace.findIndex((level, index) => level === 15 && trace[index - 1] === 0);
};
assert.equal(riseOf(0), 14, "the fastest setting answers on the first edge");
assert.equal(riseOf(3), 20, "the slowest answers six ticks later");
assert.deepEqual(
  pulseTrain(3, 12, 48).map(([, output]) => (output ? 1 : 0)).filter((level, index, all) => level === 1 && all[index - 1] === 0).length,
  pulseTrain(0, 12, 48).map(([, output]) => (output ? 1 : 0)).filter((level, index, all) => level === 1 && all[index - 1] === 0).length,
  "and both settings emit the same number of rising edges",
);

// A torch driven faster than it can answer burns out, and one driven slower
// does not - which is the rule a clock's rate is chosen against. The drive
// arrives through `outputs`, the same seam a comparator hands its own output to
// the core, so no part of this is a test-only path.
function torchUnderDrive(period) {
  const core = Redstone.place_torch(Redstone.empty(), 5n, 1n, 5n);
  const pulse = { $: "Con", head: Redstone.emit(5n, 0n, 5n), tail: { $: "Nil" } };
  const off = { $: "Nil" };
  let state = core;
  let burnt = false;
  for (let tick = 0; tick < 40; tick += 1) {
    state = Redstone.tick(state, Math.floor(tick / period) % 2 === 1 ? pulse : off);
    burnt = burnt || Redstone.torch_burnt(state, 5n, 1n, 5n);
  }
  return burnt;
}
assert.equal(torchUnderDrive(1), true, "driven every tick, the torch burns out");
assert.equal(torchUnderDrive(2), false, "driven every other tick, it survives");
assert.equal(torchUnderDrive(4), false, "and so does one driven every fourth");

// --- a self-sustaining clock -------------------------------------------------
// Repeater at (4, 0, 0) facing east, so its front is (5, 0, 0) and its back is
// (3, 0, 0). A torch stands on the repeater's front, so the repeater's output
// drives the torch's support and turns it off. The torch's own power reaches the
// repeater's back down a column of dust: torch -> (4, 1, 0) -> (3, 1, 0) ->
// (3, 0, 0), where the last hop is the direct vertical dust connection. One
// inversion and one delay, so the loop repeats for ever.
function buildClock(setting) {
  let core = Redstone.place_wire(Redstone.empty(), 4n, 1n, 0n);
  core = Redstone.place_wire(core, 3n, 1n, 0n);
  core = Redstone.place_wire(core, 3n, 0n, 0n);
  core = Redstone.place_wire(core, 5n, 0n, 0n);
  core = Redstone.place_torch(core, 5n, 1n, 0n);
  return [core, Clock.place_repeater(Clock.empty(), 4n, 0n, 0n, Clock.dir_east(), setting)];
}

function clockRun(setting, ticks) {
  let [core, timers] = buildClock(setting);
  const trace = [];
  for (let tick = 0; tick < ticks; tick += 1) {
    const result = tickOnce(core, timers);
    core = Clock.tick_core(result);
    timers = Clock.tick_timers(result);
    trace.push(repeaterOut(timers, 4n, 0n, 0n) ? 1 : 0);
  }
  return { trace, core };
}

const rising = (trace) => {
  const edges = [];
  for (let index = 1; index < trace.length; index += 1) {
    if (trace[index] === 1 && trace[index - 1] === 0) edges.push(index);
  }
  return edges;
};

for (const [setting, latency] of [[0, 2], [1, 4], [2, 6], [3, 8]]) {
  const { trace, core } = clockRun(setting, 80);
  const edges = rising(trace);
  assert.ok(edges.length >= 4, `setting ${setting} keeps pulsing rather than latching off`);
  assert.equal(edges[0], latency + 1, `setting ${setting} first pulses one tick after its latency`);
  const periods = edges.slice(1).map((edge, index) => edge - edges[index]);
  assert.deepEqual(
    [...new Set(periods)],
    [2 * latency + 3],
    `setting ${setting} repeats every ${2 * latency + 3} ticks`,
  );
  assert.equal(
    Redstone.torch_burnt(core, 5n, 1n, 0n),
    false,
    `setting ${setting} flips the torch slower than it can answer, so it never burns out`,
  );
}

// The loop is genuinely closed: shutting off the repeater's output by breaking
// the dust column stops the clock, which is what makes this a circuit and not a
// pair of components that happen to sit near each other.
{
  let [core, timers] = buildClock(0);
  const result = tickOnce(Redstone.remove_at(core, 3n, 1n, 0n), timers);
  let broken = Clock.tick_core(result);
  let brokenTimers = Clock.tick_timers(result);
  let powered = false;
  for (let tick = 0; tick < 20; tick += 1) {
    const next = tickOnce(broken, brokenTimers);
    broken = Clock.tick_core(next);
    brokenTimers = Clock.tick_timers(next);
    powered = powered || repeaterOut(brokenTimers, 4n, 0n, 0n) === 15;
  }
  assert.equal(powered, false, "break the dust column and the clock stops");
}

// Minecraft's 1-torch clock with a 1-tick repeater repeats every four ticks,
// because a torch there flips inside the same tick the repeater's output moves.
// This contract advances the timers once per tick and settles the core after
// them, so a torch's flip is read on the following tick and the period measures
// `2 * latency + 3`. That is the price of a circuit that advances one game tick
// at a time instead of cascading within a tick, and it is pinned here so the
// difference cannot drift unnoticed.
assert.equal(2 * Number(Clock.repeater_delay(0)) + 3, 7, "documented period for the one-tick clock");

console.log("bend redstone clock ok");
