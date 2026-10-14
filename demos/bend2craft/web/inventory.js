import { Inventory as InventoryDomain } from "./bend-modules.js";
import { redstoneBlockForItem } from "./redstone.js";

export const MAX_STACK = Number(InventoryDomain.max_stack());
export const HOTBAR_SIZE = 9;
export const INVENTORY_SIZE = Number(InventoryDomain.slot_count());

// A Bend Nat cannot be negative and the 2.0.32 JS lane refuses a negative one
// outright, so a cell below zero is spelled shifted into the positive half of
// the range. The domain addresses the same shifted cell on every read and
// write, so this is a spelling and not a second world. y is never shifted: the
// domain has no rows below zero. The value matches DOMAIN_CELL_OFFSET in
// web/game.js, and tests/inventory.test.mjs pins the two together.
export const DOMAIN_CELL_OFFSET = 1_000_000;

export function cellNat(value) {
  const whole = Math.trunc(Number(value));
  return BigInt(whole) + (whole < 0 ? BigInt(DOMAIN_CELL_OFFSET) : 0n);
}

export const BLOCK_INFO = Object.freeze({
  0: Object.freeze({ name: "air", color: "#8bbfdc" }),
  41: Object.freeze({ name: "bedrock", color: "#3d4350" }),
  1: Object.freeze({ name: "stone", color: "#7f8a91" }),
  2: Object.freeze({ name: "dirt", color: "#9b5c38" }),
  3: Object.freeze({ name: "grass", color: "#58ad42" }),
  4: Object.freeze({ name: "leaves", color: "#2e8c43" }),
  5: Object.freeze({ name: "wood", color: "#a66a3f" }),
  6: Object.freeze({ name: "sand", color: "#d9bd72" }),
  7: Object.freeze({ name: "water", color: "#4d9bd6" }),
  21: Object.freeze({ name: "lava", color: "#e56b2f" }),
  22: Object.freeze({ name: "cobblestone", color: "#777b7d" }),
  23: Object.freeze({ name: "obsidian", color: "#29233f" }),
  8: Object.freeze({ name: "coal ore", color: "#3d4148" }),
  9: Object.freeze({ name: "iron ore", color: "#b27b63" }),
  10: Object.freeze({ name: "diamond ore", color: "#4fd6d2" }),
  11: Object.freeze({ name: "furnace", color: "#5b5f66" }),
  12: Object.freeze({ name: "torch", color: "#f5b44c" }),
  13: Object.freeze({ name: "bed", color: "#c94f62" }),
  14: Object.freeze({ name: "closed door", color: "#8c5a38" }),
  15: Object.freeze({ name: "open door", color: "#b47a4d" }),
  16: Object.freeze({ name: "wheat crop", color: "#78b84a" }),
  17: Object.freeze({ name: "growing wheat", color: "#a3c64f" }),
  18: Object.freeze({ name: "ripe wheat", color: "#d5b83f" }),
  19: Object.freeze({ name: "mature wheat", color: "#f0c84b" }),
  20: Object.freeze({ name: "farmland", color: "#523d29" }),
  25: Object.freeze({ name: "glass", color: "#b5d9e8" }),
  26: Object.freeze({ name: "chest", color: "#9d6a3e" }),
  27: Object.freeze({ name: "crafting table", color: "#9d6a3e" }),
  // Redstone, from world/redstone.bend's block contract. A powered dust cell
  // renders brighter, so the wire's colour is read from its power level at draw
  // time; the entry here is the unpowered base tone.
  28: Object.freeze({ name: "redstone wire", color: "#8c2f2f" }),
  29: Object.freeze({ name: "redstone torch", color: "#d94a3a" }),
  30: Object.freeze({ name: "lever", color: "#9aa3a8" }),
  31: Object.freeze({ name: "redstone block", color: "#c0392b" }),
  32: Object.freeze({ name: "redstone lamp", color: "#b0764a" }),
  33: Object.freeze({ name: "redstone repeater", color: "#8d8f92" }),
  34: Object.freeze({ name: "redstone comparator", color: "#9a9c9f" }),
  35: Object.freeze({ name: "pressure plate", color: "#8a8f94" }),
  36: Object.freeze({ name: "activator rail", color: "#a5763a" }),
  37: Object.freeze({ name: "piston", color: "#9a8258" }),
  38: Object.freeze({ name: "piston head", color: "#8a7450" }),
  39: Object.freeze({ name: "sticky piston", color: "#7f9a52" }),
  40: Object.freeze({ name: "observer", color: "#6b6f76" }),
});

export const ITEM_IDS = Object.freeze({
  empty: 0,
  stone: 1,
  dirt: 2,
  grass: 3,
  leaves: 4,
  wood: 5,
  sand: 6,
  water: 7,
  planks: 8,
  sticks: 9,
  crafting_table: 10,
  wooden_pickaxe: 11,
  wool: 12,
  rotten_flesh: 13,
  coal: 14,
  raw_iron: 15,
  diamond: 16,
  stone_pickaxe: 17,
  iron_pickaxe: 18,
  diamond_pickaxe: 19,
  iron_ingot: 20,
  furnace: 21,
  torch: 22,
  bed: 23,
  door: 24,
  wheat_seeds: 25,
  wheat: 26,
  wooden_hoe: 27,
  empty_bucket: 28,
  water_bucket: 29,
  lava_bucket: 30,
  cobblestone: 31,
  obsidian: 32,
  wooden_sword: 33,
  stone_sword: 34,
  iron_sword: 35,
  diamond_sword: 36,
  bow: 37,
  shield: 38,
  arrow: 39,
  glass: 40,
  bread: 41,
  apple: 42,
  chest: 43,
  leather_helmet: 44,
  iron_chestplate: 45,
  iron_leggings: 46,
  iron_boots: 47,
  raw_porkchop: 48,
  raw_beef: 49,
  raw_chicken: 50,
  // Redstone items, continuing the id sequence in world/inventory.bend's block
  // contract. Piston head (38) has no item: it is placed and broken by the piston
  // itself, never carried, exactly as in vanilla.
  redstone: 51,
  redstone_torch: 52,
  lever: 53,
  redstone_block: 54,
  redstone_lamp: 55,
  redstone_repeater: 56,
  redstone_comparator: 57,
  pressure_plate: 58,
  activator_rail: 59,
  piston: 60,
  sticky_piston: 61,
  observer: 62,
});
const ITEM_NAMES = Object.freeze(Object.fromEntries(
  Object.entries(ITEM_IDS).map(([name, id]) => [id, name]),
));


export const ITEM_INFO = Object.freeze({
  stone: Object.freeze({ name: "stone", color: BLOCK_INFO[1].color}),
  dirt: Object.freeze({ name: "dirt", color: BLOCK_INFO[2].color}),
  grass: Object.freeze({ name: "grass", color: BLOCK_INFO[3].color}),
  leaves: Object.freeze({ name: "leaves", color: BLOCK_INFO[4].color}),
  wood: Object.freeze({ name: "wood", color: BLOCK_INFO[5].color}),
  sand: Object.freeze({ name: "sand", color: BLOCK_INFO[6].color}),
  water: Object.freeze({ name: "water", color: BLOCK_INFO[7].color}),
  planks: Object.freeze({ name: "wood planks", color: "#c28a4d"}),
  sticks: Object.freeze({ name: "sticks", color: "#d8a66a"}),
  crafting_table: Object.freeze({ name: "crafting table", color: "#9d6a3e"}),
  wooden_pickaxe: Object.freeze({ name: "wooden pickaxe", color: "#b77b48"}),
  wool: Object.freeze({ name: "wool", color: "#ece8d8"}),
  rotten_flesh: Object.freeze({ name: "rotten flesh", color: "#8c4d45"}),
  coal: Object.freeze({ name: "coal", color: "#24262b"}),
  raw_iron: Object.freeze({ name: "raw iron", color: "#c28a6d"}),
  diamond: Object.freeze({ name: "diamond", color: "#68e4df"}),
  stone_pickaxe: Object.freeze({ name: "stone pickaxe", color: "#92999f"}),
  iron_pickaxe: Object.freeze({ name: "iron pickaxe", color: "#d5d9dc"}),
  diamond_pickaxe: Object.freeze({ name: "diamond pickaxe", color: "#5ee8e0"}),
  iron_ingot: Object.freeze({ name: "iron ingot", color: "#d9dde2"}),
  furnace: Object.freeze({ name: "furnace", color: "#5b5f66"}),
  torch: Object.freeze({ name: "torch", color: "#f5b44c"}),
  bed: Object.freeze({ name: "bed", color: "#c94f62"}),
  door: Object.freeze({ name: "door", color: "#8c5a38"}),
  wheat_seeds: Object.freeze({ name: "wheat seeds", color: "#d5b83f"}),
  wheat: Object.freeze({ name: "wheat", color: "#f0c84b"}),
  wooden_hoe: Object.freeze({ name: "wooden hoe", color: "#b77b48"}),
  empty_bucket: Object.freeze({ name: "empty bucket", color: "#b8c0c8"}),
  water_bucket: Object.freeze({ name: "water bucket", color: "#4d9bd6"}),
  lava_bucket: Object.freeze({ name: "lava bucket", color: "#e56b2f"}),
  cobblestone: Object.freeze({ name: "cobblestone", color: BLOCK_INFO[22].color}),
  obsidian: Object.freeze({ name: "obsidian", color: BLOCK_INFO[23].color}),
  // The redstone items, coloured from the block contract so a block and the
  // item that places it never disagree.
  redstone: Object.freeze({ name: "redstone dust", color: BLOCK_INFO[28].color}),
  redstone_torch: Object.freeze({ name: "redstone torch", color: BLOCK_INFO[29].color}),
  lever: Object.freeze({ name: "lever", color: BLOCK_INFO[30].color}),
  redstone_block: Object.freeze({ name: "redstone block", color: BLOCK_INFO[31].color}),
  redstone_lamp: Object.freeze({ name: "redstone lamp", color: BLOCK_INFO[32].color}),
  redstone_repeater: Object.freeze({ name: "redstone repeater", color: BLOCK_INFO[33].color}),
  redstone_comparator: Object.freeze({ name: "redstone comparator", color: BLOCK_INFO[34].color}),
  pressure_plate: Object.freeze({ name: "pressure plate", color: BLOCK_INFO[35].color}),
  activator_rail: Object.freeze({ name: "activator rail", color: BLOCK_INFO[36].color}),
  piston: Object.freeze({ name: "piston", color: BLOCK_INFO[37].color}),
  sticky_piston: Object.freeze({ name: "sticky piston", color: BLOCK_INFO[39].color}),
  observer: Object.freeze({ name: "observer", color: BLOCK_INFO[40].color}),
  wooden_sword: Object.freeze({ name: "wooden sword", color: "#b77b48"}),
  stone_sword: Object.freeze({ name: "stone sword", color: "#92999f"}),
  iron_sword: Object.freeze({ name: "iron sword", color: "#d5d9dc"}),
  diamond_sword: Object.freeze({ name: "diamond sword", color: "#5ee8e0"}),
  bow: Object.freeze({ name: "bow", color: "#8c5a38"}),
  shield: Object.freeze({ name: "shield", color: "#7f8a91"}),
  arrow: Object.freeze({ name: "arrow", color: "#d8cfc0"}),
  glass: Object.freeze({ name: "glass", color: "#b5d9e8"}),
  bread: Object.freeze({ name: "bread", color: "#d59b45"}),
  apple: Object.freeze({ name: "apple", color: "#c94a3f"}),
  chest: Object.freeze({ name: "chest", color: "#9d6a3e"}),
  leather_helmet: Object.freeze({ name: "leather helmet", color: "#9b5c38"}),
  iron_chestplate: Object.freeze({ name: "iron chestplate", color: "#c5cbcd"}),
  iron_leggings: Object.freeze({ name: "iron leggings", color: "#aeb7ba"}),
  iron_boots: Object.freeze({ name: "iron boots", color: "#92999f"}),
  // What a farm animal leaves behind. Raw, like the wheat and the apple: the
  // cooking recipes for a cooked meal are not part of this slice.
  raw_porkchop: Object.freeze({ name: "raw porkchop", color: "#e08a80"}),
  raw_beef: Object.freeze({ name: "raw beef", color: "#b4443c"}),
  raw_chicken: Object.freeze({ name: "raw chicken", color: "#e0cba6"}),
  // The tool kinds, coloured by their head: wood, stone, iron, diamond, and
  // iron for the shears. `world/inventory.bend` says which material each suits
  // and how long it lasts.
  wooden_shovel: Object.freeze({ name: "wooden shovel", color: "#b77b48"}),
  stone_shovel: Object.freeze({ name: "stone shovel", color: "#92999f"}),
  iron_shovel: Object.freeze({ name: "iron shovel", color: "#d5d9dc"}),
  diamond_shovel: Object.freeze({ name: "diamond shovel", color: "#5ee8e0"}),
  wooden_axe: Object.freeze({ name: "wooden axe", color: "#b77b48"}),
  stone_axe: Object.freeze({ name: "stone axe", color: "#92999f"}),
  iron_axe: Object.freeze({ name: "iron axe", color: "#d5d9dc"}),
  diamond_axe: Object.freeze({ name: "diamond axe", color: "#5ee8e0"}),
  shears: Object.freeze({ name: "shears", color: "#c3ccd4"}),
});

function valuesFromList(list) {
  const values = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) values.push(Number(node.head));
  if (list?.$ !== "Nil" && values.length === 0) throw new TypeError("Bend inventory list is invalid");
  return values;
}

const recipeValues = valuesFromList(InventoryDomain.recipe_data());
const RECIPE_IDS = [
  "planks",
  "sticks",
  "crafting_table",
  "wooden_pickaxe",
  "stone_pickaxe",
  "iron_pickaxe",
  "diamond_pickaxe",
  "furnace",
  "torch",
  "bed",
  "door",
  "wooden_hoe",
  "empty_bucket",
  "wooden_sword",
  "stone_sword",
  "iron_sword",
  "diamond_sword",
  "bow",
  "arrow",
  "shield",
  "bread",
  "leather_helmet",
  "iron_chestplate",
  "iron_leggings",
  "iron_boots",
  "wooden_shovel",
  "stone_shovel",
  "iron_shovel",
  "diamond_shovel",
  "wooden_axe",
  "stone_axe",
  "iron_axe",
  "diamond_axe",
  "shears",
];
export const RECIPES = Object.freeze(RECIPE_IDS.map((id, recipeIndex) => {
  const offset = recipeIndex * 8;
  const ingredients = [];
  for (let index = 0; index < 2; index += 1) {
    const item = recipeValues[offset + index * 2];
    const count = recipeValues[offset + index * 2 + 1];
    if (item !== 0 && count !== 0) ingredients.push({ item: ITEM_NAMES[item], count });
  }
  return Object.freeze({
    id,
    name: ITEM_INFO[id].name[0].toUpperCase() + ITEM_INFO[id].name.slice(1),
    ingredients: Object.freeze(ingredients),
    output: Object.freeze({ item: ITEM_NAMES[recipeValues[offset + 4]], count: recipeValues[offset + 5] }),
  });
}));

// Every item that wears: the mining tools, the sword and the bow, and armour.
// The contract says how long each lasts (`Inventory.tool_max_durability`), so the
// slot only needs to know which items carry a wear figure at all.
const TOOL_IDS = new Set([
  11, 17, 18, 19, 27, 33, 34, 35, 36, 37, 38, 44, 45, 46, 47,
  63, 64, 65, 66, 67, 68, 69, 70, 71,
]);

const DOMAIN_STATES = new WeakMap();

function numericItem(value) {
  const id = itemId(value);
  return id === null ? 0 : ITEM_IDS[id] ?? 0;
}

function slotView(item, count, durability, previous, durabilityByItem) {
  const name = ITEM_NAMES[item] ?? "empty";
  if (item === 0 || count === 0) return { block: 0, count: 0 };
  const block = blockForItemNumber(item);
  const view = block === null ? { item: name, count } : { block, count };
  if (TOOL_IDS.has(item)) {
    view.durabilityMax = Number(InventoryDomain.tool_max_durability(item));
    view.durability = durability || previous?.durability || durabilityByItem?.get(name) || view.durabilityMax;
  }
  return view;
}

function viewFromDomain(list, previous = [], durabilityByItem = null, expectedLength = INVENTORY_SIZE) {
  const view = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) {
    const slot = node.head;
    view.push(slotView(Number(slot.item), Number(slot.count), Number(slot.durability), previous[view.length], durabilityByItem));
  }
  if (view.length !== expectedLength) throw new TypeError("Bend inventory returned an invalid slot count");
  return view;
}

function domainFromView(inventory) {
  let list = { $: "Nil" };
  for (let index = inventory.length - 1; index >= 0; index -= 1) {
    const slot = inventory[index] ?? { block: 0, count: 0 };
    const item = numericItem(slot);
    const maxDurability = Number(InventoryDomain.tool_max_durability(item));
    const durability = Number.isFinite(slot.durability) ? Number(slot.durability) : maxDurability;
    list = {
      $: "Con",
      head: { $: "Slot", item, count: Number(slot.count) || 0, durability },
      tail: list,
    };
  }
  return list;
}

function stateFor(inventory) {
  const state = domainFromView(inventory);
  DOMAIN_STATES.set(inventory, state);
  return state;
}

function applyResult(inventory, result) {
  const durabilityByItem = new Map(
    inventory
      .filter((item) => item?.durability)
      .map((item) => [itemId(item), item.durability]),
  );
  DOMAIN_STATES.set(inventory, result.slots);
  const next = viewFromDomain(result.slots, inventory, durabilityByItem);
  inventory.splice(0, inventory.length, ...next);
  return result.ok;
}

export function toDomain(inventory) {
  return stateFor(inventory);
}

export function applyDomainResult(inventory, result) {
  return applyResult(inventory, result);
}

export function tradeInventory(inventory, costItem, costAmount, rewardItem, rewardAmount) {
  return applyResult(inventory, InventoryDomain.trade(
    stateFor(inventory),
    Number(costItem),
    Number(costAmount),
    Number(rewardItem),
    Number(rewardAmount),
  ));
}

export function createInventory() {
  const domainState = InventoryDomain.create();
  const inventory = viewFromDomain(domainState);
  DOMAIN_STATES.set(inventory, domainState);
  return inventory;
}

export function selectedItem(inventory, slot) {
  return Array.isArray(inventory) && Number.isInteger(slot) && slot >= 0 && slot < inventory.length
    ? inventory[slot]
    : null;
}

export function itemId(value) {
  if (typeof value === "number") {
    const item = Number(InventoryDomain.mining_item(value));
    return item === 0 ? null : ITEM_NAMES[item] ?? null;
  }
  if (typeof value === "string") return ITEM_INFO[value] === undefined ? null : value;
  if (value === null || typeof value !== "object") return null;
  if (typeof value.item === "string") return ITEM_INFO[value.item] === undefined ? null : value.item;
  if (Number.isInteger(value.block)) return itemId(value.block);
  return null;
}

export function itemName(value) {
  const id = itemId(value);
  return id === null ? "empty" : ITEM_INFO[id].name;
}

export function itemNameFromId(id) {
  const name = ITEM_NAMES[Number(id)];
  return name === undefined ? null : name;
}

export function itemColor(value) {
  const id = itemId(value);
  return id === null ? BLOCK_INFO[0].color : ITEM_INFO[id].color;
}

function blockForItemNumber(item) {
  const placed = Number(InventoryDomain.placed_block(item));
  if (placed !== 0) return placed;
  return redstoneBlockForItem(item);
}

export function blockForItem(value) {
  const id = itemId(value);
  if (id === null) return null;
  return blockForItemNumber(ITEM_IDS[id]);
}

export function isPlaceable(value) {
  return blockForItem(value) !== null;
}

export function canCollectBlock(block, y) {
  return InventoryDomain.can_collect_block(block, BigInt(y));
}

export function canPlaceBlock(item, targetEmpty, inside, overlapsPlayer) {
  const id = itemId(item);
  return id !== null && InventoryDomain.can_place(
    ITEM_IDS[id],
    Boolean(targetEmpty),
    Boolean(inside),
    Boolean(overlapsPlayer),
  );
}

export function canMine(item, block) {
  return InventoryDomain.can_mine(numericItem(item), block);
}

export function miningDuration(item, block) {
  return Number(InventoryDomain.mining_duration(numericItem(item), Number(block)));
}

export function mineDrop(item, block, y = 1) {
  const id = itemId(item);
  if (id === null) return { item: 0, amount: 0, valid: false };
  const result = InventoryDomain.mine_drop(ITEM_IDS[id], block, BigInt(y));
  return {
    item: Number(result.item),
    amount: Number(result.amount),
    valid: result.valid,
  };
}

export function mineAndCollect(inventory, item, block, y = 1) {
  return applyResult(inventory, InventoryDomain.mine_collect(
    stateFor(inventory),
    numericItem(item),
    Number(block),
    BigInt(y),
  ));
}

export function placeItem(inventory, slot, item, targetEmpty, inside, overlapsPlayer) {
  return applyResult(inventory, InventoryDomain.place(
    stateFor(inventory),
    BigInt(slot),
    numericItem(item),
    Boolean(targetEmpty),
    Boolean(inside),
    Boolean(overlapsPlayer),
  ));
}

export function fillBucket(inventory, slot) {
  return applyResult(inventory, InventoryDomain.fill_bucket_at(stateFor(inventory), BigInt(slot)));
}

export function emptyBucket(inventory, slot) {
  return applyResult(inventory, InventoryDomain.empty_bucket_at(stateFor(inventory), BigInt(slot)));
}

export function fillLavaBucket(inventory, slot) {
  return applyResult(inventory, InventoryDomain.fill_lava_bucket_at(stateFor(inventory), BigInt(slot)));
}

export function emptyLavaBucket(inventory, slot) {
  return applyResult(inventory, InventoryDomain.empty_lava_bucket_at(stateFor(inventory), BigInt(slot)));
}

export function mineInteraction(inventory, slot, item, block, x, y, z) {
  const result = InventoryDomain.mine_interaction_at(
    stateFor(inventory),
    BigInt(slot),
    numericItem(item),
    Number(block),
    BigInt(x),
    BigInt(y),
    BigInt(z),
  );
  applyResult(inventory, result);
  return result;
}

export function placeInteraction(inventory, slot, item, block, x, y, z, targetEmpty, inside, overlapsPlayer) {
  const result = InventoryDomain.place_interaction(
    stateFor(inventory),
    BigInt(slot),
    numericItem(item),
    Number(block),
    cellNat(x),
    BigInt(Math.trunc(Number(y))),
    cellNat(z),
    Boolean(targetEmpty),
    Boolean(inside),
    Boolean(overlapsPlayer),
  );
  applyResult(inventory, result);
  return result;
}

export function toolMaxDurability(item) {
  return Number(InventoryDomain.tool_max_durability(numericItem(item)));
}

export function weaponDamage(item) {
  return Number(InventoryDomain.weapon_damage(numericItem(item)));
}

export function handDamage() {
  return Number(InventoryDomain.hand_damage());
}

export function foodValue(item) {
  return Number(InventoryDomain.food_value(numericItem(item)));
}

export function useTool(inventory, slot) {
  return applyResult(inventory, InventoryDomain.use_tool_at(stateFor(inventory), BigInt(slot)));
}

export function countItem(inventory, value) {
  const id = itemId(value);
  return id === null ? 0 : Number(InventoryDomain.count(stateFor(inventory), ITEM_IDS[id]));
}

export function collectItem(inventory, value, amount = 1) {
  const id = itemId(value);
  if (id === null) return false;
  return applyResult(inventory, InventoryDomain.pickup(stateFor(inventory), ITEM_IDS[id], BigInt(amount)));
}

export function collect(inventory, block, amount = 1) {
  return collectItem(inventory, itemId(block), amount);
}

export function consume(inventory, slot, amount = 1) {
  return applyResult(inventory, InventoryDomain.consume(stateFor(inventory), BigInt(slot), BigInt(amount)));
}

export function moveItem(inventory, fromSlot, toSlot, amount = null) {
  const source = selectedItem(inventory, fromSlot);
  const requested = amount === null ? source?.count ?? 0 : amount;
  return applyResult(inventory, InventoryDomain.move(stateFor(inventory), BigInt(fromSlot), BigInt(toSlot), BigInt(requested)));
}

export function getRecipe(recipeId) {
  if (typeof recipeId !== "string") return null;
  const normalizedId = recipeId.replaceAll("-", "_");
  return RECIPES.find((recipe) => recipe.id === normalizedId) ?? null;
}

function recipeIndex(recipeId) {
  const recipe = getRecipe(recipeId);
  return recipe === null ? -1 : RECIPES.indexOf(recipe);
}

export function shapedRecipePattern(recipeId) {
  const index = recipeIndex(recipeId);
  if (index === -1) return null;
  return valuesFromList(InventoryDomain.shape_pattern(BigInt(index)));
}

export function craftGrid(inventory, grid, recipeId) {
  const index = recipeIndex(recipeId);
  if (index === -1 || !Array.isArray(grid) || grid.length !== 9) {
    return { ok: false, grid: Array.isArray(grid) ? grid : [] };
  }
  const result = InventoryDomain.craft_grid(
    stateFor(inventory),
    domainFromView(grid),
    BigInt(index),
  );
  applyResult(inventory, result);
  return {
    ok: Boolean(result.ok),
    grid: viewFromDomain(result.grid, grid, null, 9),
    output: Number(result.output),
    amount: Number(result.amount),
  };
}

export function canCraft(inventory, recipeId) {
  const index = recipeIndex(recipeId);
  return index !== -1 && InventoryDomain.craft(stateFor(inventory), BigInt(index)).ok;
}

export function craft(inventory, recipeId) {
  const index = recipeIndex(recipeId);
  return index !== -1 && applyResult(inventory, InventoryDomain.craft(stateFor(inventory), BigInt(index)));
}
