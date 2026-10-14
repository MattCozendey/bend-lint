import assert from "node:assert/strict";
import Inventory from "../world/inventory.bend";

function slotsFromList(list, expected = 36) {
  const slots = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) slots.push(node.head);
  assert.equal(list?.$ === "Nil" || slots.length === expected, true);
  return slots;
}

function valuesFromList(list) {
  const values = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) values.push(Number(node.head));
  return values;
}

function listFrom(values) {
  let list = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index -= 1) list = { $: "Con", head: values[index], tail: list };
  return list;
}

const slots = slotsFromList(Inventory.create());
assert.equal(slots.length, 36);
assert.deepEqual(slots[0], { $: "Slot", item: 1, count: 32, durability: 0 });

const collected = Inventory.collect(Inventory.create(), 5, 1n);
assert.equal(collected.$, "InventoryResult");
assert.equal(collected.ok, true);
assert.deepEqual(slotsFromList(collected.slots)[4], { $: "Slot", item: 5, count: 9, durability: 0 });

const recipes = valuesFromList(Inventory.recipe_data());
assert.equal(recipes.length, 272);
assert.deepEqual(recipes.slice(0, 6), [5, 1, 0, 0, 8, 4]);
assert.deepEqual(recipes.slice(88, 94), [8, 2, 9, 2, 27, 1]);
assert.deepEqual(recipes.slice(96, 102), [20, 3, 0, 0, 28, 1]);
assert.deepEqual(recipes.slice(104, 110), [8, 2, 9, 1, 33, 1]);
assert.deepEqual(recipes.slice(152, 160), [8, 6, 20, 1, 38, 1, 0, 0]);
assert.deepEqual(recipes.slice(160, 168), [26, 3, 0, 0, 41, 1, 0, 0]);
assert.deepEqual(recipes.slice(168, 200), [
  12, 5, 0, 0, 44, 1, 0, 0,
  20, 8, 0, 0, 45, 1, 0, 0,
  20, 7, 0, 0, 46, 1, 0, 0,
  20, 4, 0, 0, 47, 1, 0, 0,
]);
// The tool kinds: a shovel and an axe are a head on a shaft, and the shears are
// two blades.
assert.deepEqual(recipes.slice(200, 272), [
  8, 1, 9, 2, 63, 1, 0, 0,
  31, 1, 9, 2, 64, 1, 0, 0,
  20, 1, 9, 2, 65, 1, 0, 0,
  16, 1, 9, 2, 66, 1, 0, 0,
  8, 3, 9, 2, 67, 1, 0, 0,
  31, 3, 9, 2, 68, 1, 0, 0,
  20, 3, 9, 2, 69, 1, 0, 0,
  16, 3, 9, 2, 70, 1, 0, 0,
  20, 2, 0, 0, 71, 1, 0, 0,
]);
assert.equal(Number(Inventory.weapon_damage(36)), 7);
assert.equal(Number(Inventory.weapon_damage(33)), 4);
assert.equal(Number(Inventory.weapon_damage(5)), 1);
assert.equal(Number(Inventory.hand_damage()), 4);
assert.equal(Number(Inventory.tool_max_durability(37)), 384);
assert.equal(Number(Inventory.tool_max_durability(38)), 336);

const crafted = Inventory.craft(collected.slots, 0n);
assert.equal(crafted.ok, true);
const craftedSlots = slotsFromList(crafted.slots);
assert.deepEqual(craftedSlots[4], { $: "Slot", item: 5, count: 8, durability: 0 });
assert.deepEqual(craftedSlots[5], { $: "Slot", item: 8, count: 4, durability: 0 });
assert.equal(Inventory.can_collect_block(5, 1n), true);
assert.equal(Inventory.can_collect_block(5, 0n), false);
assert.equal(Inventory.can_collect_block(7, 1n), false);
assert.equal(Inventory.can_place(5, true, true, false), true);
assert.equal(Inventory.can_place(8, true, true, false), false);
assert.equal(Inventory.can_place(5, false, true, false), false);
const wool = Inventory.pickup(Inventory.create(), 12, 2n);
assert.equal(wool.ok, true);
const woolSlot = slotsFromList(wool.slots).find((slot) => Number(slot.item) === 12);
assert.equal(woolSlot.count, 2);
assert.equal(Number(Inventory.tool_max_durability(11)), 59);
const toolUse = Inventory.use_tool(11, 59);
assert.equal(toolUse.valid, true);
assert.equal(Number(toolUse.durability), 58);
assert.equal(toolUse.broken, false);
const lastUse = Inventory.use_tool(11, 1);
assert.equal(lastUse.broken, true);
assert.equal(Inventory.can_mine(0, 1), false);
assert.equal(Inventory.can_mine(11, 1), true);
assert.equal(Inventory.can_mine(0, 2), true);
assert.equal(Number(Inventory.tool_max_durability(17)), 131);
assert.equal(Number(Inventory.tool_max_durability(18)), 250);
assert.equal(Number(Inventory.tool_max_durability(19)), 1561);
assert.equal(Number(Inventory.tool_max_durability(27)), 59);
assert.equal(Number(Inventory.food_value(13)), 4);
assert.equal(Number(Inventory.food_value(26)), 2);
assert.equal(Number(Inventory.food_value(41)), 5);
assert.equal(Number(Inventory.food_value(42)), 4);
assert.equal(Number(Inventory.food_value(14)), 0);
// Raw meat is what a farm animal leaves behind, so it has to be collectible and
// edible or the animal is a decoration.
assert.equal(Number(Inventory.food_value(48)), 3);
assert.equal(Number(Inventory.food_value(49)), 3);
assert.equal(Number(Inventory.food_value(50)), 2);
for (const item of [48, 49, 50]) {
  assert.equal(Inventory.pickup_item(item), true, `item ${item} must be collectible`);
  assert.equal(Inventory.is_placeable(item), false, `item ${item} is not a block`);
  assert.equal(Inventory.is_block_item(item), false, `item ${item} is not a block`);
}
assert.equal(Inventory.mine_drop(11, 1, 1n).valid, true);
assert.equal(Number(Inventory.mine_drop(11, 1, 1n).item), 1);
assert.equal(Inventory.mine_drop(0, 1, 1n).valid, false);
assert.equal(Inventory.mine_drop(11, 1, 0n).valid, false);
assert.equal(Number(Inventory.mine_drop(11, 8, 1n).item), 14);
assert.equal(Inventory.mine_drop(17, 10, 1n).valid, false);
assert.equal(Number(Inventory.mine_drop(18, 10, 1n).item), 16);
assert.equal(Number(Inventory.mine_drop(0, 11, 1n).item), 21);
assert.equal(Inventory.can_place(21, true, true, false), true);
assert.equal(Inventory.can_collect_block(22, 1n), true);
assert.equal(Inventory.can_collect_block(23, 1n), true);
assert.equal(Inventory.can_collect_block(25, 1n), true);
assert.equal(Inventory.can_collect_block(26, 1n), true);
assert.equal(Inventory.can_collect_block(27, 1n), true);
assert.equal(Number(Inventory.mine_drop(0, 22, 1n).item), 31);
assert.equal(Number(Inventory.mine_drop(0, 23, 1n).item), 32);
assert.equal(Number(Inventory.mine_drop(0, 25, 1n).item), 40);
assert.equal(Number(Inventory.mine_drop(0, 26, 1n).item), 43);
assert.equal(Number(Inventory.mine_drop(0, 27, 1n).item), 10);
assert.equal(Inventory.can_place(31, true, true, false), true);
assert.equal(Inventory.can_place(32, true, true, false), true);
assert.equal(Inventory.can_place(10, true, true, false), true);
assert.equal(Inventory.can_place(40, true, true, false), true);
assert.equal(Inventory.can_place(43, true, true, false), true);
assert.equal(Number(Inventory.mine_drop(0, 12, 1n).item), 22);
assert.equal(Inventory.can_place(22, true, true, false), true);
assert.equal(Inventory.can_collect_block(13, 1n), true);
assert.equal(Inventory.can_place(23, true, true, false), true);
assert.equal(Number(Inventory.mine_drop(0, 13, 1n).item), 23);
assert.equal(Inventory.can_collect_block(14, 1n), true);
assert.equal(Inventory.can_collect_block(15, 1n), true);
assert.equal(Inventory.can_place(24, true, true, false), true);
assert.equal(Number(Inventory.mine_drop(0, 14, 1n).item), 24);
const minedFurnace = Inventory.mine_collect(Inventory.create(), 0, 11, 1n);
assert.equal(minedFurnace.ok, true);
assert.equal(Number(slotsFromList(minedFurnace.slots)[5].item), 21);
assert.equal(Inventory.mine_collect(Inventory.create(), 0, 1, 1n).ok, false);
const placedStone = Inventory.place(Inventory.create(), 0n, 1, true, true, false);
assert.equal(placedStone.ok, true);
assert.equal(Number(slotsFromList(placedStone.slots)[0].count), 31);
assert.equal(Inventory.place(Inventory.create(), 0n, 1, true, true, true).ok, false);
const bucketInventory = Inventory.pickup(Inventory.create(), 28, 1n);
const bucketSlot = slotsFromList(bucketInventory.slots).findIndex((slot) => Number(slot.item) === 28);
const filledBucket = Inventory.fill_bucket_at(bucketInventory.slots, BigInt(bucketSlot));
assert.equal(filledBucket.ok, true);
assert.equal(Number(slotsFromList(filledBucket.slots)[bucketSlot].item), 29);
const emptiedBucket = Inventory.empty_bucket_at(filledBucket.slots, BigInt(bucketSlot));
assert.equal(emptiedBucket.ok, true);
assert.equal(Number(slotsFromList(emptiedBucket.slots)[bucketSlot].item), 28);
const filledLavaBucket = Inventory.fill_lava_bucket_at(bucketInventory.slots, BigInt(bucketSlot));
assert.equal(filledLavaBucket.ok, true);
assert.equal(Number(slotsFromList(filledLavaBucket.slots)[bucketSlot].item), 30);
const emptiedLavaBucket = Inventory.empty_lava_bucket_at(filledLavaBucket.slots, BigInt(bucketSlot));
assert.equal(emptiedLavaBucket.ok, true);
assert.equal(Number(slotsFromList(emptiedLavaBucket.slots)[bucketSlot].item), 28);
assert.equal(Inventory.pickup(Inventory.create(), 20, 1n).ok, true);
assert.equal(Inventory.pickup(Inventory.create(), 22, 1n).ok, true);
assert.equal(Inventory.pickup(Inventory.create(), 27, 1n).ok, true);
const toolInventory = Inventory.pickup(Inventory.create(), 11, 1n);
const toolIndex = slotsFromList(toolInventory.slots).findIndex((slot) => Number(slot.item) === 11);
const damagedTool = Inventory.use_tool_at(toolInventory.slots, BigInt(toolIndex));
assert.equal(damagedTool.ok, true);
assert.equal(Number(slotsFromList(damagedTool.slots)[toolIndex].durability), 58);

const shapedGrid = listFrom([
  Inventory.make_slot(5, 1, 0),
  ...Array.from({ length: 8 }, () => Inventory.make_slot(0, 0, 0)),
]);
const shaped = Inventory.craft_grid(Inventory.create(), shapedGrid, 0n);
assert.equal(shaped.ok, true);
assert.equal(Number(slotsFromList(Inventory.grid_result_grid(shaped), 9)[0].item), 0);
assert.equal(Number(slotsFromList(Inventory.grid_result_slots(shaped)).find((slot) => Number(slot.item) === 8).count), 4);
const wrongShape = Inventory.craft_grid(Inventory.create(), listFrom([
  Inventory.make_slot(5, 1, 0),
  Inventory.make_slot(5, 1, 0),
  ...Array.from({ length: 7 }, () => Inventory.make_slot(0, 0, 0)),
]), 0n);
assert.equal(wrongShape.ok, false);
console.log("bend inventory ok");

// A hit does a sword's damage with a sword in hand and the hand's with anything else.
{
  const { Inventory: Rules } = await import("../web/bend-modules.js");
  assert.equal(Number(Rules.melee_damage(36)), 7, "a diamond sword hits for seven");
  assert.equal(Number(Rules.melee_damage(33)), 4, "a wooden sword hits for four");
  assert.equal(Number(Rules.melee_damage(19)), Number(Rules.hand_damage()), "a pickaxe hits like a hand");
  assert.equal(Number(Rules.melee_damage(0)), Number(Rules.hand_damage()), "an empty hand hits like a hand");
  console.log("melee damage ok");
}

// A shovel, an axe and shears, each at the four tiers, and what they are for.
// Every rule here is the contract's: the tool table, the tier it reaches, how
// fast it works on the material it suits, how slow it is on one it does not,
// and how long it lasts.
{
  const { Inventory: Rules } = await import("../web/bend-modules.js");
  const SHOVEL = 63;
  const AXE = 67;
  const SHEARS = 71;

  // Dirt is a shovel's material and wood is an axe's, and neither tool is a
  // wasted swing on the other's.
  const dirt = 2;
  const wood = 5;
  const stone = 1;
  const dirtByHand = Number(Rules.mining_duration(0, dirt));
  const dirtByWoodenShovel = Number(Rules.mining_duration(SHOVEL, dirt));
  const dirtByWoodenAxe = Number(Rules.mining_duration(AXE, dirt));
  assert.ok(dirtByWoodenShovel < dirtByHand, `a wooden shovel digs dirt faster than a hand, got ${dirtByWoodenShovel} against ${dirtByHand}`);
  assert.ok(dirtByWoodenAxe > dirtByHand, `an axe on dirt is worse than a hand, got ${dirtByWoodenAxe} against ${dirtByHand}`);

  const woodByHand = Number(Rules.mining_duration(0, wood));
  const woodByWoodenAxe = Number(Rules.mining_duration(AXE, wood));
  const woodByWoodenShovel = Number(Rules.mining_duration(SHOVEL, wood));
  assert.ok(woodByWoodenAxe < woodByHand, `a wooden axe chops wood faster than a hand, got ${woodByWoodenAxe} against ${woodByHand}`);
  assert.ok(woodByWoodenShovel > woodByHand, `a shovel on wood is worse than a hand, got ${woodByWoodenShovel} against ${woodByHand}`);

  // Leaves are a pair of shears' work, and fast work at that.
  const leaves = 4;
  const leavesByHand = Number(Rules.mining_duration(0, leaves));
  const leavesByShears = Number(Rules.mining_duration(SHEARS, leaves));
  assert.ok(leavesByShears < leavesByHand * 0.5, `shears cut leaves fast, got ${leavesByShears} against ${leavesByHand}`);
  // A tool that cannot break what is in front of it is refused outright, so the
  // wrong-tool case is asked on dirt, which anything can dig.
  assert.ok(Number(Rules.mining_duration(SHEARS, dirt)) > dirtByHand, "shears on dirt are worse than a hand");

  // The tiers: a better tool digs the same material faster, and the tool that
  // suits a material still cannot mine what the material's rule says it cannot.
  assert.ok(
    Number(Rules.mining_duration(SHOVEL + 3, dirt)) < Number(Rules.mining_duration(SHOVEL, dirt)),
    "a diamond shovel digs dirt faster than a wooden one",
  );
  assert.ok(
    Number(Rules.mining_duration(AXE + 3, wood)) < Number(Rules.mining_duration(AXE, wood)),
    "a diamond axe chops wood faster than a wooden one",
  );
  assert.equal(Rules.can_mine(SHOVEL, 1), false, "no shovel breaks stone");
  assert.equal(Rules.can_mine(AXE, 1), false, "no axe breaks stone");
  assert.equal(Rules.can_mine(SHEARS, 1), false, "shears break no stone");
  assert.equal(Rules.can_mine(SHOVEL, 2), true, "a shovel digs dirt");
  assert.equal(Rules.can_mine(AXE, 5), true, "an axe chops wood");
  assert.equal(Rules.can_mine(SHEARS, 4), true, "shears cut leaves");

  // Durability, per tier, and the tool wears while it is used.
  assert.equal(Number(Rules.tool_max_durability(SHOVEL)), 59);
  assert.equal(Number(Rules.tool_max_durability(SHOVEL + 1)), 131);
  assert.equal(Number(Rules.tool_max_durability(SHOVEL + 2)), 250);
  assert.equal(Number(Rules.tool_max_durability(SHOVEL + 3)), 1561);
  assert.equal(Number(Rules.tool_max_durability(AXE + 3)), 1561);
  assert.equal(Number(Rules.tool_max_durability(SHEARS)), 238);
  const worn = Rules.use_tool(SHOVEL, 59);
  assert.equal(Number(worn.durability), 58, "a shovel loses one use");
  assert.equal(worn.broken, false);
  const spent = Rules.use_tool(SHEARS, 1);
  assert.equal(Number(spent.durability), 0);
  assert.equal(spent.broken, true, "the last use breaks it");
  assert.equal(Rules.use_tool(0, 0).valid, false, "a hand wears nothing");
  assert.equal(Rules.use_tool(SHOVEL, 0).valid, false, "a tool with no uses left cannot be used");

  // They are items a player can hold and craft, and they place nothing.
  assert.equal(Number(Rules.tool_level(SHOVEL)), 0, "a shovel is not a pickaxe tier");
  assert.equal(Rules.placed_block(SHOVEL), 0);
  assert.equal(Rules.placed_block(AXE), 0);
  assert.equal(Rules.placed_block(SHEARS), 0);
  assert.equal(Rules.pickup_item(SHOVEL), true, "a shovel can be picked up");
  assert.equal(Rules.pickup_item(AXE), true);
  assert.equal(Rules.pickup_item(SHEARS), true);
  console.log("tool tiers ok");
}

// A click is a transition on two stacks: the slot's and the cursor's.
{
  const { Inventory: Rules } = await import("../web/bend-modules.js");
  const slot = (item, count, durability = 0) => Rules.make_slot(item, count, durability);
  const seen = (state) => [
    [Number(state.slot.item), Number(state.slot.count)],
    [Number(state.held.item), Number(state.held.count)],
  ];
  const left = (a, b) => seen(Rules.click(a, b, false));
  const right = (a, b) => seen(Rules.click(a, b, true));
  assert.deepEqual(left(slot(1, 32), slot(0, 0)), [[0, 0], [1, 32]], "a left click takes the whole stack");
  assert.deepEqual(left(slot(0, 0), slot(1, 32)), [[1, 32], [0, 0]], "and puts the whole stack down");
  assert.deepEqual(left(slot(1, 60), slot(1, 10)), [[1, 64], [1, 6]], "onto the same item it tops the slot up");
  assert.deepEqual(left(slot(1, 5), slot(2, 7)), [[2, 7], [1, 5]], "onto another item it swaps");
  assert.deepEqual(left(slot(19, 1, 100), slot(19, 1, 50)), [[19, 1], [19, 1]], "two tools are never one stack");
  assert.equal(Number(Rules.click(slot(19, 1, 100), slot(19, 1, 50), false).slot.durability), 50, "they swap, each with its own wear");
  assert.deepEqual(right(slot(1, 7), slot(0, 0)), [[1, 3], [1, 4]], "a right click takes the larger half");
  assert.deepEqual(right(slot(1, 1), slot(0, 0)), [[0, 0], [1, 1]], "half of one is the one");
  assert.deepEqual(right(slot(0, 0), slot(1, 5)), [[1, 1], [1, 4]], "and puts one down");
  assert.deepEqual(right(slot(1, 3), slot(1, 1)), [[1, 4], [0, 0]], "the last one empties the cursor");
  assert.deepEqual(right(slot(1, 64), slot(1, 5)), [[1, 64], [1, 5]], "a full stack takes no more");
  assert.deepEqual(right(slot(2, 3), slot(1, 5)), [[1, 5], [2, 3]], "onto another item it swaps");
  assert.deepEqual(right(slot(0, 0), slot(0, 0)), [[0, 0], [0, 0]], "nothing onto nothing is nothing");

  // A grid shows what it would make, and taking it spends one of each ingredient.
  const grid = (...cells) => cells.reduceRight((tail, head) => Rules.cons_slot(head, tail), { $: "Nil" });
  const none = slot(0, 0);
  const logs = grid(slot(5, 3), none, none, none, none, none, none, none, none);
  assert.equal(Number(Rules.craft_index(logs)), 0, "one log is the first recipe");
  assert.equal(Number(Rules.craft_index(Rules.empty_grid())), 25, "an empty grid is no recipe");
  assert.equal(Number(Rules.craft_preview(logs).item), 8, "a log would make planks");
  assert.equal(Number(Rules.craft_preview(logs).count), 4, "four of them");
  assert.equal(Number(Rules.craft_preview(Rules.empty_grid()).count), 0, "an empty grid would make nothing");
  const taken = Rules.craft_take(logs, none);
  assert.equal(taken.ok, true);
  assert.deepEqual([Number(taken.held.item), Number(taken.held.count)], [8, 4], "the planks are on the cursor");
  assert.equal(Number(taken.grid.head.count), 2, "and one log is spent");
  const again = Rules.craft_take(taken.grid, taken.held);
  assert.equal(Number(again.held.count), 8, "a second take joins the first");
  const blocked = Rules.craft_take(logs, slot(1, 5));
  assert.equal(blocked.ok, false, "a cursor holding something else takes nothing");
  assert.equal(Number(blocked.grid.head.count), 3, "and nothing is spent");
  assert.equal(Rules.craft_take(logs, slot(8, 62)).ok, false, "a stack with no room for the result takes nothing");
  assert.equal(Rules.craft_take(Rules.empty_grid(), none).ok, false, "an empty grid makes nothing");
  console.log("clicks and grid crafting ok");
}
