import assert from "node:assert/strict";
import { Redstone, RedstoneMachines as Machines } from "../web/bend-modules.js";

const EMPTY = { $: "Nil" };
const EAST = Number(Machines.face_east());
const WEST = Number(Machines.face_west());
const NORTH = Number(Machines.face_north());
const UP = Number(Machines.face_up());

// One world fact: what is at these cells. The machines never read the world
// directly, so a test states it as the samples the adapter would have gathered.
function worldOf(cells) {
  let samples = EMPTY;
  for (const [key, block] of Object.entries(cells)) {
    const [x, y, z] = key.split(",").map((value) => BigInt(value));
    samples = { $: "Con", head: Redstone.sample(x, y, z, block), tail: samples };
  }
  return samples;
}

// One tick of the machines, and the state they decided on.
function tick(machines, world) {
  const stepped = Machines.step(machines, Redstone.no_emissions(), worldOf(world));
  return Machines.stepped_machines(stepped);
}

// One tick with the emissions this tick is allowed to read, which in the real loop
// are the previous tick's plus the machines' own from last time.
function tickWith(machines, emits, world) {
  const stepped = Machines.step(machines, emits, worldOf(world));
  return Machines.stepped_machines(stepped);
}

const withObserver = (x, y, z, face) =>
  Machines.place_observer(Machines.empty(), BigInt(x), BigInt(y), BigInt(z), face);

const firing = (machines, x, y, z) =>
  Machines.observer_is_firing(machines, BigInt(x), BigInt(y), BigInt(z));

// --- it is the only machine with no signal input ----------------------------
// The observer's whole contract is a difference, so the first thing to pin is that
// a signal arriving at it does nothing, and that only a change in front does.
assert.equal(Machines.observer_pulse(), 2n, "the pulse is two ticks, as in vanilla");
assert.equal(Machines.unobserved(), 65535, "and the unseen marker is not a block id");

// --- placing it does not fire it --------------------------------------------
// The rule that would bite hardest if it were wrong: an observer placed beside a
// block that was already there has seen no change, and firing on placement would
// make every observer a one-shot that fires the tick it is placed.
{
  const observer = withObserver(0, 0, 0, EAST);
  const after = tick(observer, { "1,0,0": 1 });
  assert.equal(firing(after, 0, 0, 0), false, "placing an observer beside stone does not fire it");
  const again = tick(after, { "1,0,0": 1 });
  assert.equal(firing(again, 0, 0, 0), false, "and it stays quiet while nothing changes");
}

// --- a change in front fires it, for exactly two ticks -----------------------
{
  let machines = withObserver(0, 0, 0, EAST);
  machines = tick(machines, { "1,0,0": 0 });
  assert.equal(firing(machines, 0, 0, 0), false, "the first tick only adopts what it sees");

  machines = tick(machines, { "1,0,0": 3 });
  assert.equal(firing(machines, 0, 0, 0), true, "a block appearing in front fires it");

  machines = tick(machines, { "1,0,0": 3 });
  assert.equal(firing(machines, 0, 0, 0), true, "and it is still firing on the second tick");

  machines = tick(machines, { "1,0,0": 3 });
  assert.equal(firing(machines, 0, 0, 0), false, "and it has stopped on the third");
}

// A block removed is as much a change as a block placed.
{
  let machines = withObserver(0, 0, 0, EAST);
  machines = tick(machines, { "1,0,0": 3 });
  assert.equal(firing(machines, 0, 0, 0), false, "it adopted the stone");
  machines = tick(machines, { "1,0,0": 0 });
  assert.equal(firing(machines, 0, 0, 0), true, "and the stone being removed fires it");
}

// Swapping one block for another is a change too, even though both are solid: the
// observer reads the block's identity, not whether the cell is occupied.
{
  let machines = withObserver(0, 0, 0, EAST);
  machines = tick(machines, { "1,0,0": 1 });
  machines = tick(machines, { "1,0,0": 2 });
  assert.equal(firing(machines, 0, 0, 0), true, "stone becoming dirt is a change");
}

// A change during the pulse restarts it rather than being swallowed, which is what
// makes an observer usable as a clock.
{
  let machines = withObserver(0, 0, 0, EAST);
  machines = tick(machines, { "1,0,0": 0 });
  machines = tick(machines, { "1,0,0": 1 });
  assert.equal(firing(machines, 0, 0, 0), true, "the first change fired it");
  machines = tick(machines, { "1,0,0": 2 });
  assert.equal(firing(machines, 0, 0, 0), true, "a change during the pulse keeps it firing");
  machines = tick(machines, { "1,0,0": 2 });
  assert.equal(firing(machines, 0, 0, 0), true, "and the restart holds it for its own two ticks");
  machines = tick(machines, { "1,0,0": 2 });
  assert.equal(firing(machines, 0, 0, 0), false, "before it finally stops");
}

// --- it watches the cell in front, on every face -----------------------------
// The face is the only thing that says which cell it watches, so a wrong face is a
// silent observer: it sits there looking at empty air forever.
for (const [name, face, dx, dy, dz] of [
  ["east", EAST, 1, 0, 0],
  ["west", WEST, -1, 0, 0],
  ["north", NORTH, 0, 0, -1],
  ["up", UP, 0, 1, 0],
]) {
  let machines = withObserver(10, 10, 10, face);
  machines = tick(machines, {});
  const front = `${10 + dx},${10 + dy},${10 + dz}`;
  const beside = `${10 - dx},${10 - dy},${10 - dz}`;
  machines = tick(machines, { [front]: 1 });
  assert.equal(firing(machines, 10, 10, 10), true, `a change in front fires an observer facing ${name}`);
  let other = withObserver(10, 10, 10, face);
  other = tick(other, {});
  other = tick(other, { [beside]: 1 });
  assert.equal(firing(other, 10, 10, 10), false, `and a change behind does not, facing ${name}`);
}

// --- it does not watch itself -----------------------------------------------
// `Nat.sub` saturates at zero, so an observer at the origin facing west, down or
// north has its "cell in front" fold back onto its own cell. If it watched that it
// would see its own block appear and fire on placement, forever.
for (const [name, face] of [["west at the origin", WEST], ["north at the origin", NORTH]]) {
  let machines = withObserver(0, 0, 0, face);
  machines = tick(machines, { "0,0,0": 40 });
  assert.equal(firing(machines, 0, 0, 0), false, `an observer facing ${name} does not watch itself`);
  machines = tick(machines, { "0,0,0": 41 });
  assert.equal(firing(machines, 0, 0, 0), false, "and stays quiet however its own cell changes");
}

// --- it is a strong source while it fires ------------------------------------
// An observer is a solid block while it pulses, so it powers its six neighbours
// the way a redstone block does - full strength, not the weak reading a
// repeater's neighbour gets. Its own cell carries nothing, which is the same
// convention every other source in this contract follows.
//
// It sits away from the origin because `Nat.sub` saturates: a source on a
// coordinate plane emits into its own cell for every neighbour that steps off
// that plane, which is the same thing a redstone block does there and is pinned
// on its own below.
{
  let machines = withObserver(10, 10, 10, EAST);
  machines = tick(machines, { "11,10,10": 0 });
  machines = tick(machines, { "11,10,10": 1 });
  const emits = Machines.outputs(machines);
  const at = (x, y, z) => Number(Redstone.emits_power_at(emits, BigInt(x), BigInt(y), BigInt(z)));
  assert.equal(at(11, 10, 10), 15, "the cell it faces is fully powered");
  assert.equal(at(9, 10, 10), 15, "and the cell behind it");
  assert.equal(at(10, 10, 11), 15, "and both sides");
  assert.equal(at(10, 10, 9), 15);
  assert.equal(at(10, 11, 10), 15, "and above");
  assert.equal(at(10, 9, 10), 15, "and below");
  assert.equal(at(10, 10, 10), 0, "but not its own cell, as with every other source here");
  assert.equal(at(12, 10, 10), 0, "and nothing two cells away");

  // The pulse is the tick that saw the change and the one after it, so it takes two
  // more ticks with nothing happening before the output is gone.
  const second = tick(machines, { "11,10,10": 1 });
  assert.equal(Number(Redstone.emits_power_at(Machines.outputs(second), 11n, 10n, 10n)), 15,
    "the second tick of the pulse still carries the signal");
  const quiet = tick(second, { "11,10,10": 1 });
  assert.equal(Number(Redstone.emits_power_at(Machines.outputs(quiet), 11n, 10n, 10n)), 0,
    "and nothing at all once the pulse is over");
}

// The saturation a source on a coordinate plane has, which is the core's rule and
// not the observer's: the three neighbours that would step off the plane all land
// on the source's own cell.
{
  let machines = withObserver(0, 5, 0, EAST);
  machines = tick(machines, { "1,5,0": 0 });
  machines = tick(machines, { "1,5,0": 1 });
  const emits = Machines.outputs(machines);
  const at = (x, y, z) => Number(Redstone.emits_power_at(emits, BigInt(x), BigInt(y), BigInt(z)));
  assert.equal(at(1, 5, 0), 15, "the cell it faces is powered");
  assert.equal(at(0, 6, 0), 15, "and above it");
  assert.equal(at(0, 5, 1), 15, "and beside it");
  assert.equal(at(0, 5, 0), 15,
    "and the neighbours that would step off the x and z planes saturate onto its own cell");
}

// A signal arriving at an observer changes nothing: it has no input to read.
{
  let machines = withObserver(0, 0, 0, EAST);
  machines = tick(machines, { "1,0,0": 1 });
  const powered = Redstone.emits_one(Redstone.emit(0, 0, 0));
  const stepped = Machines.step(machines, powered, worldOf({ "1,0,0": 1 }));
  const after = Machines.stepped_machines(stepped);
  assert.equal(firing(after, 0, 0, 0), false, "powering an observer does not fire it");
}

// --- placement, removal and reads --------------------------------------------
{
  let machines = withObserver(4, 5, 6, EAST);
  assert.equal(Machines.observer_is_firing(machines, 4n, 5n, 6n), false, "a fresh observer is quiet");

  // Placing twice at the same cell is one observer, not two, or the cell would
  // carry two independent pulses.
  const twice = Machines.place_observer(machines, 4n, 5n, 6n, WEST);
  machines = tick(twice, { "3,5,6": 1 });
  machines = tick(twice, { "3,5,6": 1 });
  assert.equal(firing(machines, 4, 5, 6), false, "the second placement did not add a second observer");

  const dropped = Machines.drop_machines(machines, 4n, 5n, 6n);
  assert.equal(Machines.state_observers(dropped).$ ?? "Nil", "Nil", "breaking it removes the observer");
  const afterBreak = tick(dropped, { "3,5,6": 2 });
  assert.equal(firing(afterBreak, 4, 5, 6), false, "and a broken observer is not a machine any more");
}

// A cell that never held an observer reads as quiet rather than as an error.
assert.equal(Machines.observer_is_firing(Machines.empty(), 99n, 99n, 99n), false);

// --- it drives something ------------------------------------------------------
// The point of the component: a block changing in front of it puts power on a
// circuit, through the same path any other source uses.
//
// A piston sits where the observer's pulse reaches it, and both need a tick to arm
// before either acts - the observer to adopt what it sees, the piston because it
// is edge driven. The piston then reads the pulse on the tick after the observer
// produced it, which is the one-tick lag every machine in this contract has and
// the reason a block update in vanilla is scheduled rather than immediate.
{
  // The observer at (1,5,1) faces north, so it watches a cell the piston is not in
  // and powers the piston at (2,5,1) to its east. It is off the origin because a
  // north face at z=0 has its front cell saturate back onto the observer, which is
  // the case pinned separately above.
  let machines = withObserver(1, 5, 1, NORTH);
  machines = Machines.place_piston(machines, 2n, 5n, 1n, EAST, false);

  machines = tick(machines, { "1,5,0": 0 });
  assert.equal(firing(machines, 1, 5, 1), false, "the observer adopted what it sees and the piston armed");

  // The block in front of the observer changes.
  const pulsing = tick(machines, { "1,5,0": 5 });
  assert.equal(firing(pulsing, 1, 5, 1), true, "so the observer pulses");
  assert.equal(Machines.piston_is_extended(pulsing, 2n, 5n, 1n), false,
    "and the piston has not moved yet, because the pulse is not an emission until the tick ends");

  // The next tick reads that pulse.
  const fired = tickWith(pulsing, Machines.outputs(pulsing), { "1,5,0": 5 });
  assert.equal(Machines.piston_is_extended(fired, 2n, 5n, 1n), true,
    "and on the next tick the observer's pulse has extended the piston");
}

console.log("bend redstone observer ok");
