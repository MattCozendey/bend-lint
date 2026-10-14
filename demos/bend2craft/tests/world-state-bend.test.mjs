import assert from "node:assert/strict";
import State from "../world/world_state.bend";

const empty = State.empty();
const edited = State.set(empty, 40n, 8n, 40n, 0);
assert.notEqual(edited, empty);
assert.equal(Number(State.block(edited, 1337n, 40n, 8n, 40n)), 0);
assert.equal(Number(State.block(empty, 1337n, 40n, 8n, 40n)), 3);
const torchEdits = State.set(empty, 40n, 8n, 40n, 12);
assert.equal(torchEdits.$, "Con");
assert.equal(State.torches(torchEdits).$, "Con");
const lavaEdits = State.set(empty, 40n, 8n, 40n, 21);
assert.equal(State.torches(lavaEdits).$, "Nil");
assert.equal(State.light_sources(lavaEdits).$, "Con");

// Long logs: every whole-list walk runs as a loop, so a world with tens of
// thousands of edits still loads (a non-tail walk overflowed past ~15,000).
const LONG = 60000;
let long = { $: "Nil" };
for (let index = LONG - 1; index >= 0; index -= 1) {
  long = { $: "Con", head: State.make_edit(BigInt(index % 512), BigInt(1 + ((index >> 9) % 18)), BigInt(((index >> 13) % 512) + 3), index % 7 === 0 ? 12 : 1), tail: long };
}
const extended = State.set(long, 999n, 9n, 999n, 3);
assert.equal(Number(State.block(extended, 1337n, 999n, 9n, 999n)), 3);
assert.equal(Number(State.block(extended, 1337n, 5n, 1n, 3n)), 1);
assert.ok(State.light_sources(long).$ === "Con");
assert.ok(State.torches(long).$ === "Con");
const replaced = State.set(long, 5n, 1n, 3n, 0);
assert.equal(Number(State.block(replaced, 1337n, 5n, 1n, 3n)), 0);
let length = 0;
for (let node = replaced; node.$ === "Con"; node = node.tail) length += 1;
assert.equal(length, LONG, "replacing keeps one entry per cell");

// set_many is `set` applied in order, in one pass.
const list = (items) => items.reduceRight((tail, head) => ({ $: "Con", head, tail }), { $: "Nil" });
const cells = (edits) => {
  const values = new Map();
  for (let node = edits; node.$ === "Con"; node = node.tail) {
    const key = `${node.head.x},${node.head.y},${node.head.z}`;
    if (!values.has(key)) values.set(key, Number(node.head.block));
  }
  return values;
};
let random = 7;
const next = (limit) => {
  random = (random * 1103515245 + 12345) % 2147483648;
  return random % limit;
};
for (let round = 0; round < 30; round += 1) {
  let base = { $: "Nil" };
  for (let index = 0; index < next(40); index += 1) base = State.set(base, BigInt(next(6)), BigInt(next(4)), BigInt(next(6)), next(28));
  const batch = Array.from({ length: next(20) }, () => State.make_edit(BigInt(next(8)), BigInt(next(5)), BigInt(next(8)), next(28)));
  let sequential = base;
  for (const edit of batch) sequential = State.set(sequential, edit.x, edit.y, edit.z, edit.block);
  const once = State.set_many(base, list(batch));
  assert.deepEqual([...cells(once)].sort(), [...cells(sequential)].sort(), `round ${round}`);
  let count = 0;
  for (let node = once; node.$ === "Con"; node = node.tail) count += 1;
  assert.equal(count, cells(sequential).size, "one entry per cell");
}
// An empty batch leaves the log as it was, checked cell by cell and by length
// rather than by reference: the JS lane rebuilds a returned list instead of
// handing the same object back (v2.0.28 did, v2.0.32 does not), and a 60,000
// entry cons list is far too deep for assert's recursive comparison.
const count = (edits) => {
  let total = 0;
  for (let node = edits; node.$ === "Con"; node = node.tail) total += 1;
  return total;
};
const untouched = State.set_many(long, { $: "Nil" });
assert.equal(count(untouched), LONG, "an empty batch adds no entry");
assert.deepEqual([...cells(untouched)].sort(), [...cells(long)].sort(), "an empty batch changes no cell");
const bulk = State.set_many(long, list([State.make_edit(5n, 1n, 3n, 22), State.make_edit(1000n, 9n, 1000n, 25)]));
assert.equal(Number(State.block(bulk, 1337n, 5n, 1n, 3n)), 22);
assert.equal(Number(State.block(bulk, 1337n, 1000n, 9n, 1000n)), 25);

console.log("bend world state ok");
