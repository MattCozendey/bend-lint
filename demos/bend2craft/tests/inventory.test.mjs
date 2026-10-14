import assert from "node:assert/strict";
import {
  createInventory,
  selectedItem,
  shapedRecipePattern,
  collect,
  consume,
  HOTBAR_SIZE,
  INVENTORY_SIZE,
  MAX_STACK,
  BLOCK_INFO,
  ITEM_INFO,
  RECIPES,
  blockForItem,
  canCraft,
  cellNat,
  collectItem,
  countItem,
  craft,
  craftGrid,
  DOMAIN_CELL_OFFSET,
  foodValue,
  handDamage,
  isPlaceable,
  itemColor,
  itemId,
  itemName,
  moveItem,
  mineDrop,
  miningDuration,
  placeItem,
  toolMaxDurability,
  tradeInventory,
  useTool,
  weaponDamage,
} from "../web/inventory.js";

const inventory = createInventory();
assert.equal(HOTBAR_SIZE, 9);
assert.equal(inventory.length, INVENTORY_SIZE);
assert.equal(inventory.length, 36);
assert.deepEqual(selectedItem(inventory, 0), { block: 1, count: 32 });
assert.equal(consume(inventory, 0), true);
assert.equal(selectedItem(inventory, 0).count, 31);
assert.equal(collect(inventory, 5), true);
assert.deepEqual(selectedItem(inventory, 4), { block: 5, count: 9 });
assert.deepEqual(selectedItem(inventory, 5), { block: 0, count: 0 });
assert.equal(consume(inventory, 8), false);

const overflow = createInventory();
assert.equal(collect(overflow, 5, MAX_STACK - 8), true);
assert.equal(selectedItem(overflow, 4).count, MAX_STACK);
assert.equal(collect(overflow, 5), true);
assert.deepEqual(selectedItem(overflow, 5), { block: 5, count: 1 });

const full = createInventory();
full.forEach((slot) => {
  slot.block = 1;
  slot.count = MAX_STACK;
});
const fullBefore = full.map((slot) => ({ ...slot }));
assert.equal(collect(full, 5), false);
assert.deepEqual(full, fullBefore);

const materials = createInventory();
assert.equal(collect(materials, 6), true);
assert.equal(itemId(selectedItem(materials, 5)), "sand");
assert.equal(blockForItem(selectedItem(materials, 5)), 6);
assert.equal(isPlaceable(selectedItem(materials, 5)), true);
assert.equal(collect(materials, 7), false);
assert.equal(collectItem(materials, "water"), false);

const moved = createInventory();
assert.equal(moveItem(moved, 4, 9), true);
assert.deepEqual(selectedItem(moved, 4), { block: 0, count: 0 });
assert.deepEqual(selectedItem(moved, 9), { block: 5, count: 8 });

assert.equal(BLOCK_INFO[6].name, "sand");
assert.equal(BLOCK_INFO[7].name, "water");
assert.equal(BLOCK_INFO[21].name, "lava");
assert.equal(BLOCK_INFO[22].name, "cobblestone");
assert.equal(BLOCK_INFO[23].name, "obsidian");
assert.equal(BLOCK_INFO[8].name, "coal ore");
assert.equal(BLOCK_INFO[10].name, "diamond ore");
assert.equal(blockForItem("water"), null);
assert.equal(foodValue("rotten_flesh"), 4);
assert.equal(blockForItem("furnace"), 11);
assert.equal(blockForItem("torch"), 12);
assert.equal(blockForItem("bed"), 13);
assert.equal(itemId({ item: "lava_bucket", count: 1 }), "lava_bucket");
assert.equal(blockForItem("cobblestone"), 22);
assert.equal(blockForItem("obsidian"), 23);
assert.equal(blockForItem("door"), 14);
assert.equal(blockForItem("crafting_table"), 27);
assert.equal(blockForItem("glass"), 25);
assert.equal(blockForItem("chest"), 26);
assert.equal(foodValue("bread"), 5);
assert.equal(foodValue("apple"), 4);
// A farm animal has to be worth striking: its meat is a real, edible item.
assert.equal(foodValue("raw_porkchop"), 3);
assert.equal(foodValue("raw_beef"), 3);
assert.equal(foodValue("raw_chicken"), 2);
for (const name of ["raw_porkchop", "raw_beef", "raw_chicken"]) {
  assert.equal(blockForItem(name), null);
}
assert.equal(toolMaxDurability("stone_pickaxe"), 131);
assert.ok(miningDuration("wooden_pickaxe", 1) > 0);
assert.ok(miningDuration("diamond_pickaxe", 23) > miningDuration("wooden_pickaxe", 1));
assert.equal(miningDuration(null, 23), 0);
assert.deepEqual(mineDrop("wooden_pickaxe", 8), { item: 14, amount: 1, valid: true });
assert.deepEqual(mineDrop("stone_pickaxe", 10), { item: 16, amount: 1, valid: false });
const placeInventory = createInventory();
assert.equal(placeItem(placeInventory, 0, selectedItem(placeInventory, 0), true, true, false), true);
assert.equal(selectedItem(placeInventory, 0).count, 31);
assert.equal(placeItem(placeInventory, 0, selectedItem(placeInventory, 0), true, true, true), false);

const emptyInventory = () => {
  const result = createInventory();
  result.forEach((slot) => {
    delete slot.item;
    slot.block = 0;
    slot.count = 0;
  });
  return result;
};

assert.deepEqual(RECIPES.map((recipe) => recipe.id), [
  "planks", "sticks", "crafting_table", "wooden_pickaxe",
  "stone_pickaxe", "iron_pickaxe", "diamond_pickaxe", "furnace",
  "torch", "bed", "door", "wooden_hoe", "empty_bucket",
  "wooden_sword", "stone_sword", "iron_sword", "diamond_sword",
  "bow", "arrow", "shield", "bread", "leather_helmet",
  "iron_chestplate", "iron_leggings", "iron_boots",
  "wooden_shovel", "stone_shovel", "iron_shovel", "diamond_shovel",
  "wooden_axe", "stone_axe", "iron_axe", "diamond_axe", "shears",
]);
assert.deepEqual(RECIPES[0].ingredients, [{ item: "wood", count: 1 }]);
assert.deepEqual(RECIPES[0].output, { item: "planks", count: 4 });
assert.deepEqual(RECIPES[9].ingredients, [{ item: "wool", count: 3 }, { item: "planks", count: 3 }]);
assert.deepEqual(RECIPES[9].output, { item: "bed", count: 1 });
assert.deepEqual(RECIPES[10].ingredients, [{ item: "planks", count: 6 }]);
assert.deepEqual(RECIPES[10].output, { item: "door", count: 1 });
assert.deepEqual(RECIPES[11].ingredients, [{ item: "planks", count: 2 }, { item: "sticks", count: 2 }]);
assert.deepEqual(RECIPES[11].output, { item: "wooden_hoe", count: 1 });
assert.deepEqual(RECIPES[12].ingredients, [{ item: "iron_ingot", count: 3 }]);
assert.deepEqual(RECIPES[12].output, { item: "empty_bucket", count: 1 });
assert.deepEqual(shapedRecipePattern("planks"), [5, 0, 0, 0, 0, 0, 0, 0, 0]);
const shapedInventory = createInventory();
const shapedGrid = shapedRecipePattern("planks").map((item) => item === 5
  ? { block: 5, count: 1 }
  : { block: 0, count: 0 });
const shapedCraft = craftGrid(shapedInventory, shapedGrid, "planks");
assert.equal(shapedCraft.ok, true);
assert.equal(countItem(shapedInventory, "planks"), 4);
assert.equal(shapedCraft.grid[0].count, 0);
assert.deepEqual(RECIPES[21].ingredients, [{ item: "wool", count: 5 }]);
assert.deepEqual(RECIPES[21].output, { item: "leather_helmet", count: 1 });

const planks = createInventory();
assert.equal(canCraft(planks, "planks"), true);
assert.equal(craft(planks, "planks"), true);
assert.equal(countItem(planks, "wood"), 7);
assert.equal(countItem(planks, "planks"), 4);
assert.equal(craft(planks, "planks"), true);
assert.equal(countItem(planks, "planks"), 8);
assert.deepEqual(selectedItem(planks, 5), { item: "planks", count: 8 });
assert.equal(itemName(selectedItem(planks, 5)), "wood planks");
assert.equal(itemColor(selectedItem(planks, 5)), "#c28a4d");

const failedCraft = emptyInventory();
const failedCraftBefore = failedCraft.map((slot) => ({ ...slot }));
assert.equal(canCraft(failedCraft, "planks"), false);
assert.equal(craft(failedCraft, "planks"), false);
assert.deepEqual(failedCraft, failedCraftBefore);
assert.equal(craft(failedCraft, "unknown_recipe"), false);

const bedInventory = emptyInventory();
assert.equal(collectItem(bedInventory, "wool", 3), true);
assert.equal(collectItem(bedInventory, "wood"), true);
assert.equal(craft(bedInventory, "planks"), true);
assert.equal(craft(bedInventory, "bed"), true);
assert.equal(countItem(bedInventory, "bed"), 1);
const doorInventory = emptyInventory();
assert.equal(collectItem(doorInventory, "wood", 2), true);
assert.equal(craft(doorInventory, "planks"), true);
assert.equal(craft(doorInventory, "planks"), true);
assert.equal(craft(doorInventory, "door"), true);
assert.equal(countItem(doorInventory, "door"), 1);

const tableInventory = emptyInventory();
assert.equal(collectItem(tableInventory, "wood"), true);
assert.equal(craft(tableInventory, "planks"), true);
assert.equal(craft(tableInventory, "crafting_table"), true);
const tableSlot = tableInventory.find((slot) => itemId(slot) === "crafting_table");
assert.equal(isPlaceable(tableSlot), true);
assert.equal(blockForItem(tableSlot), 27);
assert.equal(collectItem(tableInventory, "glass"), true);
assert.equal(collectItem(tableInventory, "chest"), true);
assert.equal(isPlaceable(tableInventory.find((slot) => itemId(slot) === "glass")), true);
assert.equal(isPlaceable(tableInventory.find((slot) => itemId(slot) === "chest")), true);

const pickaxeInventory = emptyInventory();
assert.equal(collectItem(pickaxeInventory, "wood", 2), true);
assert.equal(craft(pickaxeInventory, "planks"), true);
assert.equal(craft(pickaxeInventory, "planks"), true);
assert.equal(craft(pickaxeInventory, "sticks"), true);
assert.equal(craft(pickaxeInventory, "wooden_pickaxe"), true);
assert.equal(countItem(pickaxeInventory, "wooden_pickaxe"), 1);
assert.equal(countItem(pickaxeInventory, "planks"), 3);
assert.equal(countItem(pickaxeInventory, "sticks"), 2);
const pickaxeSlot = pickaxeInventory.findIndex((slot) => itemId(slot) === "wooden_pickaxe");
pickaxeInventory[pickaxeSlot].durability = 42;
assert.equal(moveItem(pickaxeInventory, pickaxeSlot, 10), true);
assert.equal(selectedItem(pickaxeInventory, 10).durability, 42);
assert.equal(useTool(pickaxeInventory, 10), true);
assert.equal(selectedItem(pickaxeInventory, 10).durability, 41);
assert.equal(collectItem(pickaxeInventory, "stone"), true);
assert.equal(selectedItem(pickaxeInventory, 10).durability, 41);
const tierInventory = emptyInventory();
assert.equal(collectItem(tierInventory, "stone", 3), true);
assert.equal(collectItem(tierInventory, "wood"), true);
assert.equal(craft(tierInventory, "planks"), true);
assert.equal(craft(tierInventory, "sticks"), true);
assert.equal(craft(tierInventory, "stone_pickaxe"), true);
assert.equal(countItem(tierInventory, "stone_pickaxe"), 1);
assert.equal(collectItem(tierInventory, "iron_ingot", 3), true);
assert.equal(craft(tierInventory, "iron_pickaxe"), true);
assert.equal(countItem(tierInventory, "iron_pickaxe"), 1);
assert.equal(collectItem(tierInventory, "iron_ingot"), true);
assert.equal(collectItem(tierInventory, "furnace"), true);
assert.equal(countItem(tierInventory, "furnace"), 1);

const swordInventory = emptyInventory();
assert.equal(collectItem(swordInventory, "wood", 2), true);
assert.equal(craft(swordInventory, "planks"), true);
assert.equal(craft(swordInventory, "planks"), true);
assert.equal(craft(swordInventory, "sticks"), true);
assert.equal(craft(swordInventory, "wooden_sword"), true);
assert.equal(countItem(swordInventory, "wooden_sword"), 1);
assert.equal(weaponDamage("wooden_sword"), 4);
assert.equal(weaponDamage("stone_sword"), 5);
assert.equal(weaponDamage("iron_sword"), 6);
assert.equal(weaponDamage("diamond_sword"), 7);
assert.equal(weaponDamage("bow"), 6);
assert.equal(weaponDamage("wood"), 1);
assert.equal(handDamage(), 4);
assert.equal(toolMaxDurability("bow"), 384);
assert.equal(toolMaxDurability("shield"), 336);
const bowInventory = emptyInventory();
assert.equal(collectItem(bowInventory, "wood", 3), true);
assert.equal(craft(bowInventory, "planks"), true);
assert.equal(craft(bowInventory, "planks"), true);
assert.equal(craft(bowInventory, "planks"), true);
assert.equal(craft(bowInventory, "sticks"), true);
assert.equal(collectItem(bowInventory, "wool", 3), true);
assert.equal(craft(bowInventory, "bow"), true);
assert.equal(countItem(bowInventory, "bow"), 1);
const tradeInventoryState = emptyInventory();
assert.equal(collectItem(tradeInventoryState, "rotten_flesh", 4), true);
assert.equal(tradeInventory(tradeInventoryState, 13, 4, 20, 1), true);
assert.equal(countItem(tradeInventoryState, "rotten_flesh"), 0);
assert.equal(countItem(tradeInventoryState, "iron_ingot"), 1);

// A Bend Nat cannot be negative and the 2.0.32 JS lane refuses one outright, so
// a cell below zero is spelled shifted into the positive range. The placement
// path in web/game.js carries its own copy of this rule, and the two must stay
// the same shift or one of them addresses a cell the other does not.
assert.equal(DOMAIN_CELL_OFFSET, 1_000_000);
assert.equal(cellNat(0), 0n, "a cell on the origin is its own spelling");
assert.equal(cellNat(40), 40n, "a positive cell is never shifted");
assert.equal(cellNat(-40), BigInt(DOMAIN_CELL_OFFSET - 40));
assert.equal(cellNat(-1), BigInt(DOMAIN_CELL_OFFSET - 1));
assert.equal(cellNat(1_000_040), 1_000_040n, "the shifted range is never shifted twice");
for (const value of [-1_000_000, -1, 0, 1, 1_000_000]) {
  assert.ok(cellNat(value) >= 0n, `cellNat(${value}) must be a Nat`);
}
console.log("inventory ok");
