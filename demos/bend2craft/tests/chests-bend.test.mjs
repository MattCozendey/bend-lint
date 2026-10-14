import assert from "node:assert/strict";
import Chests from "../world/chests.bend";

function listLength(list) {
  let length = 0;
  for (let node = list; node?.$ === "Con"; node = node.tail) length += 1;
  return length;
}

const empty = Chests.empty();
const added = Chests.add(empty, 4n, 5n, 6n);
assert.equal(added.ok, true);
const found = Chests.at(added.world, 4n, 5n, 6n);
assert.equal(found.$, "ChestFound");
assert.equal(listLength(Chests.lookup_slots(found)), 9);
const replaced = Chests.set(added.world, 4n, 5n, 6n, Chests.empty());
assert.equal(Chests.at(replaced, 4n, 5n, 6n).$, "ChestFound");
const removed = Chests.remove(replaced, 4n, 5n, 6n);
assert.equal(removed.ok, true);
assert.equal(Chests.at(removed.world, 4n, 5n, 6n).$, "ChestMissing");
assert.equal(Chests.add(removed.world, 4n, 5n, 6n).ok, true);
assert.equal(Chests.add(added.world, 4n, 5n, 6n).ok, false);
console.log("bend chest containers ok");
