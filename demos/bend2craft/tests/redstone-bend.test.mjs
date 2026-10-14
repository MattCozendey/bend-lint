import assert from "node:assert/strict";
import Redstone from "../world/redstone.bend";

const EMPTY = { $: "Nil" };
function list(values) {
  let node = EMPTY;
  for (let index = values.length - 1; index >= 0; index -= 1) {
    node = { $: "Con", head: values[index], tail: node };
  }
  return node;
}
function heads(node) {
  const values = [];
  for (let cursor = node; cursor?.$ === "Con"; cursor = cursor.tail) values.push(cursor.head);
  return values;
}

// --- the block contract -----------------------------------------------------
assert.equal(Number(Redstone.max_power()), 15);
assert.deepEqual(heads(Redstone.block_ids()), [28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]);

// --- a redstone block drives a line of dust down -----------------------------
function line(length, start = 1n) {
  let state = Redstone.empty();
  for (let index = 0n; index < BigInt(length); index += 1n) {
    state = Redstone.place_wire(state, start + index, 0n, 0n);
  }
  state = Redstone.place_power_block(state, start - 1n, 0n, 0n);
  return Redstone.tick(state, EMPTY);
}

const lineState = line(20);
assert.equal(Number(Redstone.wire_power(lineState, 1n, 0n, 0n)), 15, "dust next to the block is full power");
assert.equal(Number(Redstone.wire_power(lineState, 2n, 0n, 0n)), 14);
assert.equal(Number(Redstone.wire_power(lineState, 3n, 0n, 0n)), 13);
assert.equal(Number(Redstone.wire_power(lineState, 15n, 0n, 0n)), 1, "the fifteenth cell still carries a signal");
assert.equal(Number(Redstone.wire_power(lineState, 16n, 0n, 0n)), 0, "and the sixteenth is dark, as in vanilla");
assert.equal(Number(Redstone.wire_power(lineState, 20n, 0n, 0n)), 0);

// --- a column of dust is a direct connection ---------------------------------
// Vanilla: dust couples straight up and down and that connection does not lose a
// level, so a stack carries its signal unchanged and sideways branches off it
// decay from the stack's level.
let column = Redstone.place_wire(Redstone.empty(), 1n, 0n, 0n);
for (let level = 1n; level < 6n; level += 1n) column = Redstone.place_wire(column, 1n, level, 0n);
column = Redstone.place_power_block(column, 0n, 0n, 0n);
column = Redstone.place_wire(column, 2n, 3n, 0n);
const columnState = Redstone.tick(column, EMPTY);
assert.equal(Number(Redstone.wire_power(columnState, 1n, 0n, 0n)), 15);
assert.equal(Number(Redstone.wire_power(columnState, 1n, 1n, 0n)), 15, "the cell above keeps the level");
assert.equal(Number(Redstone.wire_power(columnState, 1n, 5n, 0n)), 15, "and so does the top of the stack");
assert.equal(Number(Redstone.wire_power(columnState, 2n, 3n, 0n)), 14, "a branch off the stack decays from it");

// A stack is a one-way lift only in the sense that the level is preserved, so a
// block at the top powers dust beside it as strongly as one at the bottom.
let lift = Redstone.place_wire(Redstone.empty(), 1n, 0n, 0n);
lift = Redstone.place_wire(lift, 1n, 1n, 0n);
lift = Redstone.place_power_block(lift, 0n, 0n, 0n);
const liftState = Redstone.tick(lift, EMPTY);
assert.equal(Number(Redstone.wire_power(liftState, 1n, 1n, 0n)), 15);

// Two stacks next to each other do not join: dust couples vertically and to the
// four cells around it, but two columns side by side at different heights are
// only joined where a cell is genuinely adjacent.
let columns = Redstone.place_wire(Redstone.empty(), 1n, 0n, 0n);
columns = Redstone.place_wire(columns, 1n, 1n, 0n);
columns = Redstone.place_wire(columns, 3n, 0n, 0n);
columns = Redstone.place_wire(columns, 3n, 1n, 0n);
columns = Redstone.place_power_block(columns, 0n, 0n, 0n);
const columnsState = Redstone.tick(columns, EMPTY);
assert.equal(Number(Redstone.wire_power(columnsState, 3n, 1n, 0n)), 0, "a gap between columns is still a gap");

// --- the layout of the dust does not change the answer -----------------------
// A U of dust fed at one end, with both arms meeting at a tip. The flood drains
// its frontier a level at a time, so the power every cell reads must be the same
// however the player laid the dust down.
const U_CELLS = [[1, 0], [2, 0], [3, 0], [4, 0], [5, 0], [1, 1], [2, 1], [3, 1], [4, 1], [5, 1], [3, 2]];
function buildU(cells) {
  let state = Redstone.empty();
  for (const [x, z] of cells) state = Redstone.place_wire(state, BigInt(x), 0n, BigInt(z));
  return Redstone.place_power_block(state, 0n, 0n, 0n);
}
function uPowers(state) {
  return U_CELLS.map(([x, z]) => Number(Redstone.wire_power(state, BigInt(x), 0n, BigInt(z))));
}
const uExpected = [15, 14, 13, 12, 11, 14, 13, 12, 11, 10, 11];
assert.deepEqual(uPowers(Redstone.tick(buildU(U_CELLS), EMPTY)), uExpected);
assert.deepEqual(
  uPowers(Redstone.tick(buildU([...U_CELLS].reverse()), EMPTY)),
  uExpected,
  "the power map does not depend on the order the dust was placed",
);
assert.deepEqual(
  uPowers(Redstone.tick(buildU([U_CELLS[5], U_CELLS[0], U_CELLS[10], ...U_CELLS.slice(1, 5), ...U_CELLS.slice(6)]), EMPTY)),
  uExpected,
  "and neither on a column-first build order",
);

// --- dust that only touches diagonally never carries ------------------------
let diagonal = Redstone.place_wire(Redstone.empty(), 1n, 0n, 0n);
diagonal = Redstone.place_wire(diagonal, 2n, 0n, 1n);
diagonal = Redstone.place_power_block(diagonal, 0n, 0n, 0n);
const diagonalState = Redstone.tick(diagonal, EMPTY);
assert.equal(Number(Redstone.wire_power(diagonalState, 1n, 0n, 0n)), 15);
assert.equal(Number(Redstone.wire_power(diagonalState, 2n, 0n, 1n)), 0, "a diagonal is not a wire connection");

// --- a lever is a switch, and the circuit follows it -------------------------
let levered = Redstone.place_wire(Redstone.empty(), 1n, 0n, 0n);
levered = Redstone.place_lamp(levered, 2n, 0n, 0n);
levered = Redstone.place_lever(levered, 0n, 0n, 0n, false);
const off = Redstone.tick(levered, EMPTY);
assert.equal(Number(Redstone.wire_power(off, 1n, 0n, 0n)), 0);
assert.equal(Redstone.lamp_lit(off, 2n, 0n, 0n), false);

const engaged = Redstone.flip_lever(levered, 0n, 0n, 0n);
const on = Redstone.tick(engaged, EMPTY);
assert.equal(Number(Redstone.wire_power(on, 1n, 0n, 0n)), 15);
assert.equal(Redstone.lamp_lit(on, 2n, 0n, 0n), true, "dust pointing into the lamp lights it");

const back = Redstone.tick(Redstone.flip_lever(engaged, 0n, 0n, 0n), EMPTY);
assert.equal(Number(Redstone.wire_power(back, 1n, 0n, 0n)), 0, "turning the lever off clears the line");
assert.equal(Redstone.lamp_lit(back, 2n, 0n, 0n), false);

// --- a torch inverts the block it stands on ----------------------------------
// Torch on top of a cell, dust feeding that cell: the torch is driven dark.
let inverted = Redstone.place_wire(Redstone.empty(), 1n, 0n, 0n);
inverted = Redstone.place_torch(inverted, 2n, 1n, 0n);
inverted = Redstone.place_lamp(inverted, 3n, 1n, 0n);
inverted = Redstone.place_lever(inverted, 0n, 0n, 0n, false);
const torchIdle = Redstone.tick(inverted, EMPTY);
assert.equal(Redstone.torch_lit(torchIdle, 2n, 1n, 0n), true, "an unpowered torch burns");
assert.equal(Redstone.lamp_lit(torchIdle, 3n, 1n, 0n), true);

const torchDriven = Redstone.tick(Redstone.flip_lever(inverted, 0n, 0n, 0n), EMPTY);
assert.equal(Redstone.torch_lit(torchDriven, 2n, 1n, 0n), false, "powering the support turns the torch off");
assert.equal(Redstone.lamp_lit(torchDriven, 3n, 1n, 0n), false, "and the lamp it fed goes dark");

// --- a torch powers the block it stands on and the four around it ------------
let torchFace = Redstone.place_torch(Redstone.empty(), 5n, 1n, 5n);
torchFace = Redstone.place_wire(torchFace, 4n, 1n, 5n);
torchFace = Redstone.place_wire(torchFace, 6n, 1n, 5n);
const torchFacing = Redstone.tick(torchFace, EMPTY);
assert.equal(Number(Redstone.wire_power(torchFacing, 4n, 1n, 5n)), 15, "dust beside a lit torch is full power");
assert.equal(Number(Redstone.wire_power(torchFacing, 6n, 1n, 5n)), 15);
const torchBelow = Redstone.tick(Redstone.place_wire(torchFace, 5n, 0n, 5n), EMPTY);
assert.equal(Number(Redstone.wire_power(torchBelow, 5n, 0n, 5n)), 15, "a torch powers the block it stands on");
assert.equal(Redstone.torch_lit(torchBelow, 5n, 1n, 5n), true, "and dust under it does not turn it off");

// --- a torch driven faster than it can answer burns out ----------------------
// A torch flips whenever something drives its support. Pulsing that support
// every tick is what a fast oscillator does, and vanilla burns a torch that
// cannot keep up; the streak counter latches the same verdict. The pulse comes
// in through `outputs`, the same seam a repeater will drive, so this is the
// repeater's burnout, not a special case.
const pulsed0 = Redstone.place_torch(Redstone.empty(), 5n, 1n, 5n);
const pulse = list([Redstone.emit(5n, 0n, 5n)]);
let pulsed = pulsed0;
for (let tick = 0; tick < 40; tick += 1) {
  pulsed = Redstone.tick(pulsed, tick % 2 === 0 ? pulse : EMPTY);
  // The limit is eight ticks spent flipping without settling, so the ninth flip
  // is the one that kills it.
  assert.equal(
    Redstone.torch_burnt(pulsed, 5n, 1n, 5n),
    tick >= 9,
    `burnout latches on the ninth flip, not on tick ${tick}`,
  );
}
assert.equal(Redstone.torch_burnt(pulsed, 5n, 1n, 5n), true, "a torch flipped every tick burns out");
assert.equal(Redstone.torch_lit(pulsed, 5n, 1n, 5n), false, "and stays dark however hard the circuit drives it");
pulsed = Redstone.tick(pulsed, EMPTY);
assert.equal(Redstone.torch_lit(pulsed, 5n, 1n, 5n), false, "a burnt torch does not recover on its own");

// --- an explicit output drives the same path a repeater would ----------------
// `outputs` names the cells a delayed component drove, not where it sits, so a
// repeater in front of this dust hands the same list the torch would.
const driven = Redstone.tick(Redstone.place_wire(Redstone.empty(), 9n, 0n, 0n), list([Redstone.emit(9n, 0n, 0n)]));
assert.equal(Number(Redstone.wire_power(driven, 9n, 0n, 0n)), 15, "a component output feeds the same dust flood");

// --- a break clears the cached power ----------------------------------------
const cleared = Redstone.tick(Redstone.remove_at(lineState, 1n, 0n, 0n), EMPTY);
assert.equal(Number(Redstone.wire_power(cleared, 1n, 0n, 0n)), 0);
assert.equal(Number(Redstone.wire_power(cleared, 2n, 0n, 0n)), 0, "the rest of the line is orphaned");

console.log("bend redstone ok");
