import assert from "node:assert/strict";
import Fire from "../world/fire.bend";

function listValues(list) {
  const values = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) values.push(node.head);
  return values;
}

function samples(values) {
  let list = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index -= 1) {
    list = { $: "Con", head: values[index], tail: list };
  }
  return list;
}

const openFire = samples([
  Fire.sample(3n, 3n, 2n, 0),
  Fire.sample(4n, 3n, 2n, 5),
]);
const state = Fire.ignite(Fire.empty(), 2n, 3n, 2n);
const next = Fire.tick(state, openFire);
const cells = listValues(Fire.state_cells(next));
assert.equal(cells.length, 2);
assert.ok(cells.some((cell) => cell.x === 2n && Number(cell.age) === 1));
assert.ok(cells.some((cell) => cell.x === 3n && Number(cell.age) === 0));
const added = listValues(Fire.changes(Fire.empty(), state));
assert.deepEqual(added, [{ $: "Edit", x: 2n, y: 3n, z: 2n, block: 24 }]);
const lavaSamples = samples([
  Fire.sample(2n, 3n, 2n, 21),
  Fire.sample(3n, 3n, 2n, 5),
  Fire.sample(3n, 4n, 2n, 0),
]);
const lavaIgnited = Fire.ignite_lava(Fire.empty(), lavaSamples);
assert.ok(listValues(Fire.state_cells(lavaIgnited)).some((cell) => (
  cell.x === 3n && cell.y === 4n && cell.z === 2n
)));

// A lava cell inside a large neighbourhood (a pool the simulation samples):
// only the lava looks at its neighbours, the first sample of a cell wins, and
// a flammable block next to water does not catch.
const pool = [Fire.sample(40n, 3n, 40n, 21), Fire.sample(41n, 3n, 40n, 5), Fire.sample(41n, 4n, 40n, 0)];
for (let x = 0n; x < 20n; x += 1n) {
  for (let z = 0n; z < 20n; z += 1n) pool.push(Fire.sample(x, 3n, z, 7), Fire.sample(x, 4n, z, 0));
}
pool.push(Fire.sample(0n, 3n, 0n, 5), Fire.sample(41n, 3n, 40n, 1));
const poolIgnited = listValues(Fire.state_cells(Fire.ignite_lava(Fire.empty(), samples(pool))));
assert.deepEqual(poolIgnited.map((cell) => [cell.x, cell.y, cell.z]), [[41n, 4n, 40n]]);
assert.equal(Fire.sample_block(samples(pool), 41n, 3n, 40n), 5, "the first sample of a cell wins");
assert.equal(Fire.sample_block(samples(pool), 99n, 3n, 99n), 1, "an unsampled cell reads as stone");

let dying = state;
const blocked = samples([Fire.sample(2n, 3n, 2n, 1)]);
for (let index = 0; index < 8; index += 1) dying = Fire.tick(dying, blocked);
assert.equal(listValues(Fire.state_cells(dying)).length, 0);
const removed = listValues(Fire.changes(state, dying));
assert.deepEqual(removed, [{ $: "Edit", x: 2n, y: 3n, z: 2n, block: 0 }]);
console.log("bend fire ok");
