import assert from "node:assert/strict";
import { dropAmount, findShiftTarget, slotKey, transferAmount } from "../web/inventory-ux.js";

assert.equal(transferAmount(0, 0), 0);
assert.equal(transferAmount(5, 0), 5);
assert.equal(transferAmount(5, 2), 3);
assert.equal(transferAmount(6, 2), 3);
assert.equal(transferAmount(1, 2), 1);
assert.equal(dropAmount(0, false), 0);
assert.equal(dropAmount(5, false), 1);
assert.equal(dropAmount(5, true), 5);
assert.equal(slotKey({ block: 5, count: 2 }), "block:5");
assert.equal(slotKey({ item: "wool", count: 1 }), "item:wool");
assert.equal(slotKey({ block: 0, count: 0 }), null);

const inventory = [
  { block: 1, count: 32 },
  { block: 5, count: 64 },
  { block: 0, count: 0 },
  { item: "wool", count: 2 },
  { block: 0, count: 0 },
  { block: 0, count: 0 },
  { block: 0, count: 0 },
  { block: 0, count: 0 },
  { block: 0, count: 0 },
  { block: 5, count: 4 },
  { block: 0, count: 0 },
];
assert.equal(findShiftTarget(inventory, 0, 9), 10, "hotbar item should move to first main empty slot");
assert.equal(findShiftTarget(inventory, 9, 9), 2, "main item should move to a hotbar empty slot when no stack has room");
const mainInventory = inventory.map((slot) => ({ ...slot }));
mainInventory[10] = { item: "wool", count: 2 };
assert.equal(findShiftTarget(mainInventory, 10, 9), 3, "main item should merge into a matching hotbar stack first");
assert.equal(findShiftTarget(inventory, 2, 9), -1, "empty slots cannot be shift-moved");
console.log("inventory ux ok");
