import assert from "node:assert/strict";
import Chest from "../world/chest.bend";

function slotsFromList(list) {
  const slots = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) slots.push(node.head);
  assert.equal(slots.length, 9);
  return slots;
}

const empty = Chest.empty();
assert.equal(slotsFromList(empty).every((slot) => Number(slot.item) === 0 && Number(slot.count) === 0), true);

const deposited = Chest.deposit(empty, 5, 12, 0);
assert.equal(deposited.ok, true);
assert.equal(Number(slotsFromList(Chest.deposit_slots(deposited))[0].item), 5);
assert.equal(Number(slotsFromList(Chest.deposit_slots(deposited))[0].count), 12);

const withdrawn = Chest.withdraw(Chest.deposit_slots(deposited), 0n, 5);
assert.equal(withdrawn.ok, true);
assert.equal(Number(withdrawn.item), 5);
assert.equal(Number(withdrawn.amount), 5);
assert.equal(Number(slotsFromList(Chest.withdraw_slots(withdrawn))[0].count), 7);

const tool = Chest.deposit(empty, 11, 1, 42);
assert.equal(tool.ok, true);
assert.equal(Number(slotsFromList(Chest.deposit_slots(tool))[0].durability), 42);
const invalid = Chest.withdraw(Chest.deposit_slots(tool), 0n, 0);
assert.equal(invalid.ok, false);

console.log("bend chest ok");
