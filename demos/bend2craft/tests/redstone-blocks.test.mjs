import assert from "node:assert/strict";
import Redstone from "../world/redstone.bend";
import {
  BLOCK_INFO,
  ITEM_INFO,
  ITEM_IDS,
  blockForItem,
  itemId,
} from "../web/inventory.js";

const EMPTY = { $: "Nil" };
function heads(node) {
  const out = [];
  for (let cursor = node; cursor?.$ === "Con"; cursor = cursor.tail) out.push(cursor.head);
  return out;
}

const ids = heads(Redstone.block_ids()).map(Number);

// --- the one block contract, held by three files ----------------------------
// world/redstone.bend owns the ids, web/inventory.js names and colours them, and
// an item exists for each one a player can carry. A drift in any of the three is
// a bug the player would see as an unnameable or unplaceable block, so it is
// checked here rather than discovered in game.
assert.deepEqual(ids, [28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]);

for (const id of ids) {
  const info = BLOCK_INFO[id];
  assert.ok(info, `block ${id} has no entry in BLOCK_INFO`);
  assert.equal(typeof info.name, "string");
  assert.ok(info.name.length > 0, `block ${id} has no name`);
  assert.match(info.color, /^#[0-9a-f]{6}$/i, `block ${id} has no colour`);
}

// A piston head is placed by a piston, so it is named and coloured but has no
// item: the player can never hold it, and breaking one must drop nothing.
assert.equal(itemId(38), null, "a piston head drops no item");
assert.equal(blockForItem("redstone"), 28);
assert.equal(ITEM_IDS.redstone, 51);

// Every other redstone block round-trips through an item a player can hold.
for (const id of ids) {
  if (id === 38) continue;
  const item = itemId(id);
  assert.equal(typeof item, "string", `block ${id} drops no item`);
  assert.equal(blockForItem(item), id, `item ${item} does not place block ${id}`);
  const info = ITEM_INFO[item];
  assert.ok(info, `item ${item} has no entry in ITEM_INFO`);
  // The item is coloured from the block contract, so a block and the item that
  // places it never disagree on the surface.
  assert.equal(info.color, BLOCK_INFO[id].color, `item ${item} and block ${id} differ in colour`);
}

// The adapter's two directions agree.
assert.equal(blockForItem("redstone_block"), 31);
assert.equal(itemId(31), "redstone_block");
assert.equal(itemId(38), null, "a piston head has no item to give");

// --- the door reuses the ids the world already had --------------------------
// world/redstone_machines.bend drives blocks 14 and 15 rather than inventing a
// third, so a redstone door and the door item are the same thing.
assert.equal(BLOCK_INFO[14].name, "closed door");
assert.equal(BLOCK_INFO[15].name, "open door");
assert.equal(itemId(14), "door");
assert.equal(itemId(15), "door");
assert.equal(blockForItem("door"), 14);

// --- nothing above collides with the ids the world already used -------------
// The redstone slice starts at 28, so every pre-existing block keeps its id. A
// silent renumber here would corrupt every saved world and every chunk test.
for (let id = 0; id < 28; id += 1) {
  if (id === 24) continue; // fire is a simulation state, never a placed block
  assert.ok(BLOCK_INFO[id], `pre-existing block ${id} lost its entry`);
}
assert.equal(BLOCK_INFO[24], undefined, "fire is a simulation state, not a placed block");

console.log("redstone block contract ok");
