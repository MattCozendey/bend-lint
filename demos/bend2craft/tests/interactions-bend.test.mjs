import assert from "node:assert/strict";
import Inventory from "../world/inventory.bend";

function slots(list) {
  const result = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) result.push(node.head);
  return result;
}

assert.equal(typeof Inventory.mining_duration, "function");
const stoneDuration = Number(Inventory.mining_duration(11, 1));
const obsidianDuration = Number(Inventory.mining_duration(19, 23));
assert.ok(stoneDuration > 0);
assert.ok(obsidianDuration > stoneDuration);
assert.equal(Inventory.can_mine(0, 23), false);
assert.equal(Inventory.can_mine(17, 23), false);
assert.equal(Inventory.can_mine(19, 23), true);

// `InteractionResult` is inventory.bend's own type holding a `WorldState.Edit`.
// How the loader spells that nested field is its own business and has changed
// across pins (bare up to 2.0.28, `owner.Type` from 2.0.32); the bridge leaves
// an own-type result exactly as the loader built it, because the adapter hands
// the whole result back rather than the edit alone. So assert the fields the
// adapter reads, and the tag only up to its bare constructor name.
const bareTag = (tag) => tag.replace(/^[a-z][a-z0-9_-]*\./, "");
const editShape = (edit) => ({ ...edit, $: bareTag(edit.$) });
const mined = Inventory.mine_interaction(Inventory.create(), 0, 11, 2n, 1n, 2n);
assert.equal(mined.ok, true);
assert.deepEqual(editShape(mined.edit), { $: "Edit", x: 2n, y: 1n, z: 2n, block: 0 });
assert.equal(Number(slots(mined.slots)[5].item), 21);

const placed = Inventory.place_interaction(Inventory.create(), 0n, 1, 1, 3n, 1n, 4n, true, true, false);
assert.equal(placed.ok, true);
assert.deepEqual(editShape(placed.edit), { $: "Edit", x: 3n, y: 1n, z: 4n, block: 1 });
assert.equal(Number(slots(placed.slots)[0].count), 31);

const blocked = Inventory.place_interaction(Inventory.create(), 0n, 1, 1, 3n, 1n, 4n, true, true, true);
assert.equal(blocked.ok, false);
assert.deepEqual(editShape(blocked.edit), { $: "Edit", x: 3n, y: 1n, z: 4n, block: 1 });
assert.equal(Number(slots(blocked.slots)[0].count), 32);

let toolSlots = { $: "Nil" };
for (let index = 35; index >= 0; index -= 1) {
  toolSlots = {
    $: "Con",
    head: index === 0
      ? { $: "Slot", item: 17, count: 1, durability: 131 }
      : { $: "Slot", item: 0, count: 0, durability: 0 },
    tail: toolSlots,
  };
}
const atomicMine = Inventory.mine_interaction_at(toolSlots, 0n, 17, 1, 4n, 1n, 4n);
assert.equal(atomicMine.ok, true);
assert.equal(Number(slots(atomicMine.slots)[0].durability), 130);
assert.equal(Number(slots(atomicMine.slots)[1].item), 1);
assert.equal(Number(slots(atomicMine.slots)[1].count), 1);
console.log("bend interactions ok");
