import assert from "node:assert/strict";
import { Inventory as InventoryDomain } from "../web/bend-modules.js";
import {
  BLOCK_INFO,
  ITEM_IDS,
  blockForItem,
  canCollectBlock,
  itemId,
  itemNameFromId,
} from "../web/inventory.js";

// The browser's blockForItem/itemId are a view over the Bend contract, not a
// second source of truth. `Inventory.placed_block` and `Inventory.mining_item`
// own the item <-> block mapping; a drift in the browser view would let the
// game place a different block than the contract says an item places.
//
// Redstone items answer 0 from `Inventory.placed_block` by design:
// `world/redstone.bend` owns the ids they place, and web/inventory.js has to
// route through that rather than invent its own table.

// Every diggable block yields the item the contract names for it.
for (let block = 0; block <= 40; block += 1) {
  if (!canCollectBlock(block, 1)) continue;
  const contract = itemNameFromId(Number(InventoryDomain.mining_item(block)));
  assert.equal(itemId(block), contract, `block ${block} reads as ${itemId(block)} but drops ${contract}`);
}

// Every item names the block the contract names for it. Redstone items return
// 0 from placed_block, so a placed redstone block must be inside redstone's
// own id range.
for (const [name, id] of Object.entries(ITEM_IDS)) {
  const placed = Number(InventoryDomain.placed_block(id));
  const block = blockForItem(name);
  if (placed !== 0) {
    assert.equal(block, placed, `${name} places ${block}, contract says ${placed}`);
  } else if (id >= 51 && id <= 62) {
    assert.ok(block !== null && block >= 28 && block <= 40, `${name} places ${block}, not a redstone block`);
  } else {
    assert.equal(block, null, `${name} is not placeable, view places ${block}`);
  }
}

console.log("inventory bend contract ok");
