// Pure presentation data for the first-person item and third-person person views.
// Positions use camera or character-local coordinates; +x is right and +y is up.

import { itemId } from "./inventory.js";

function deepFreeze(value) {
  if (value === null || typeof value !== "object" || Object.isFrozen(value)) return value;
  Object.freeze(value);
  for (const child of Object.values(value)) deepFreeze(child);
  return value;
}

const ITEM_DEFINITIONS = deepFreeze({
  stone: {
    name: "stone",
    category: "block",
    model: "cube",
    color: "#7f8a91",
    block: 1,
    dimensions: [0.62, 0.62, 0.62],
  },
  dirt: {
    name: "dirt",
    category: "block",
    model: "cube",
    color: "#9b5c38",
    block: 2,
    dimensions: [0.62, 0.62, 0.62],
  },
  grass: {
    name: "grass",
    category: "block",
    model: "cube",
    color: "#58ad42",
    block: 3,
    dimensions: [0.62, 0.62, 0.62],
  },
  leaves: {
    name: "leaves",
    category: "block",
    model: "cube",
    color: "#2e8c43",
    block: 4,
    dimensions: [0.62, 0.62, 0.62],
  },
  wood: {
    name: "wood",
    category: "block",
    model: "cube",
    color: "#a66a3f",
    block: 5,
    dimensions: [0.62, 0.62, 0.62],
  },
  sand: {
    name: "sand",
    category: "block",
    model: "cube",
    color: "#d9bd72",
    block: 6,
    dimensions: [0.62, 0.62, 0.62],
  },
  water: {
    name: "water",
    category: "block",
    model: "cube",
    color: "#4d9bd6",
    block: 7,
    dimensions: [0.62, 0.62, 0.62],
  },
  cobblestone: {
    name: "cobblestone",
    category: "block",
    model: "cube",
    color: "#777b7d",
    block: 22,
    dimensions: [0.62, 0.62, 0.62],
  },
  obsidian: {
    name: "obsidian",
    category: "block",
    model: "cube",
    color: "#29233f",
    block: 23,
    dimensions: [0.62, 0.62, 0.62],
  },
  furnace: {
    name: "furnace",
    category: "block",
    model: "cube",
    color: "#5b5f66",
    block: 11,
    dimensions: [0.62, 0.62, 0.62],
  },
  wooden_pickaxe: {
    name: "wooden pickaxe",
    category: "tool",
    model: "pickaxe",
    color: "#b77b48",
    block: null,
    dimensions: [0.78, 0.94, 0.16],
  },
  stone_pickaxe: {
    name: "stone pickaxe",
    category: "tool",
    model: "pickaxe",
    color: "#92999f",
    block: null,
    dimensions: [0.78, 0.94, 0.16],
  },
  iron_pickaxe: {
    name: "iron pickaxe",
    category: "tool",
    model: "pickaxe",
    color: "#d5d9dc",
    block: null,
    dimensions: [0.78, 0.94, 0.16],
  },
  diamond_pickaxe: {
    name: "diamond pickaxe",
    category: "tool",
    model: "pickaxe",
    color: "#5ee8e0",
    block: null,
    dimensions: [0.78, 0.94, 0.16],
  },
  wooden_hoe: {
    name: "wooden hoe",
    category: "tool",
    model: "hoe",
    color: "#b77b48",
    block: null,
    dimensions: [0.72, 0.9, 0.16],
  },
  torch: {
    name: "torch",
    category: "torch",
    model: "torch",
    color: "#f5b44c",
    block: 12,
    dimensions: [0.16, 0.54, 0.16],
  },
  bed: {
    name: "bed",
    category: "bed",
    model: "bed",
    color: "#c94f62",
    block: 13,
    dimensions: [0.86, 0.28, 1.55],
  },
  door: {
    name: "door",
    category: "door",
    model: "door",
    color: "#8c5a38",
    block: 14,
    dimensions: [0.14, 1.72, 0.84],
  },
  planks: {
    name: "wood planks",
    category: "item",
    model: "item",
    color: "#c28a4d",
    block: null,
    dimensions: [0.34, 0.34, 0.34],
  },
  sticks: {
    name: "sticks",
    category: "item",
    model: "item",
    color: "#d8a66a",
    block: null,
    dimensions: [0.12, 0.52, 0.12],
  },
  crafting_table: {
    name: "crafting table",
    category: "item",
    model: "item",
    color: "#9d6a3e",
    block: null,
    dimensions: [0.42, 0.42, 0.42],
  },
  wool: {
    name: "wool",
    category: "item",
    model: "item",
    color: "#ece8d8",
    block: null,
    dimensions: [0.34, 0.34, 0.34],
  },
  rotten_flesh: {
    name: "rotten flesh",
    category: "item",
    model: "item",
    color: "#8c4d45",
    block: null,
    dimensions: [0.28, 0.28, 0.28],
  },
  coal: {
    name: "coal",
    category: "item",
    model: "item",
    color: "#24262b",
    block: null,
    dimensions: [0.28, 0.28, 0.28],
  },
  raw_iron: {
    name: "raw iron",
    category: "item",
    model: "item",
    color: "#c28a6d",
    block: null,
    dimensions: [0.28, 0.28, 0.28],
  },
  diamond: {
    name: "diamond",
    category: "item",
    model: "item",
    color: "#68e4df",
    block: null,
    dimensions: [0.28, 0.28, 0.28],
  },
  iron_ingot: {
    name: "iron ingot",
    category: "item",
    model: "item",
    color: "#d9dde2",
    block: null,
    dimensions: [0.34, 0.18, 0.18],
  },
  wheat_seeds: {
    name: "wheat seeds",
    category: "item",
    model: "seeds",
    color: "#d5b63e",
    block: null,
    dimensions: [0.2, 0.12, 0.2],
  },
  wheat: {
    name: "wheat",
    category: "item",
    model: "wheat",
    color: "#f0c84b",
    block: null,
    dimensions: [0.2, 0.5, 0.2],
  },
});

const FIRST_PERSON_POSES = deepFreeze({
  block: {
    reference: "camera",
    side: "right",
    position: [0.42, -0.28, -0.72],
    rotation: [-0.32, 0.24, -0.16],
    scale: [1, 1, 1],
  },
  tool: {
    reference: "camera",
    side: "right",
    position: [0.42, -0.22, -0.7],
    rotation: [-0.86, 0.18, -0.7],
    scale: [0.82, 0.82, 0.82],
  },
  torch: {
    reference: "camera",
    side: "right",
    position: [0.38, -0.2, -0.64],
    rotation: [-0.18, 0.08, -0.12],
    scale: [0.9, 0.9, 0.9],
  },
  bed: {
    reference: "camera",
    side: "right",
    position: [0.4, -0.24, -0.68],
    rotation: [-0.46, 0.36, -0.2],
    scale: [0.5, 0.5, 0.5],
  },
  door: {
    reference: "camera",
    side: "right",
    position: [0.42, -0.16, -0.72],
    rotation: [-0.34, 0.28, -0.16],
    scale: [0.48, 0.48, 0.48],
  },
  item: {
    reference: "camera",
    side: "right",
    position: [0.4, -0.26, -0.7],
    rotation: [-0.28, 0.2, -0.14],
    scale: [0.9, 0.9, 0.9],
  },
});

const THIRD_PERSON_POSES = deepFreeze({
  block: {
    reference: "character",
    side: "right",
    position: [0.39, 1.08, 0.04],
    rotation: [0.1, 0.1, -0.2],
    scale: [0.74, 0.74, 0.74],
  },
  tool: {
    reference: "character",
    side: "right",
    position: [0.39, 1.08, 0.04],
    rotation: [0.18, 0.08, -0.92],
    scale: [0.78, 0.78, 0.78],
  },
  torch: {
    reference: "character",
    side: "right",
    position: [0.39, 1.08, 0.04],
    rotation: [0, 0, -0.08],
    scale: [0.76, 0.76, 0.76],
  },
  bed: {
    reference: "character",
    side: "right",
    position: [0.39, 1.08, 0.04],
    rotation: [0.1, 0.28, -0.34],
    scale: [0.32, 0.32, 0.32],
  },
  door: {
    reference: "character",
    side: "right",
    position: [0.39, 1.08, 0.04],
    rotation: [0.08, 0.18, -0.16],
    scale: [0.34, 0.34, 0.34],
  },
  item: {
    reference: "character",
    side: "right",
    position: [0.39, 1.08, 0.04],
    rotation: [0.08, 0.1, -0.12],
    scale: [0.62, 0.62, 0.62],
  },
});

const PERSON_PARTS = deepFreeze([
  {
    name: "head",
    model: "cube",
    position: [0, 1.62, 0],
    rotation: [0, 0, 0],
    dimensions: [0.38, 0.38, 0.38],
    color: "#e3ab84",
  },
  {
    name: "torso",
    model: "cube",
    position: [0, 1.14, 0],
    rotation: [0, 0, 0],
    dimensions: [0.5, 0.72, 0.3],
    color: "#3e6ea8",
  },
  {
    name: "left_arm",
    model: "cube",
    position: [-0.36, 1.14, 0],
    rotation: [0, 0, 0],
    dimensions: [0.18, 0.68, 0.18],
    color: "#3e6ea8",
  },
  {
    name: "right_arm",
    model: "cube",
    position: [0.36, 1.14, 0],
    rotation: [0, 0, 0],
    dimensions: [0.18, 0.68, 0.18],
    color: "#3e6ea8",
  },
  {
    name: "left_leg",
    model: "cube",
    position: [-0.14, 0.48, 0],
    rotation: [0, 0, 0],
    dimensions: [0.2, 0.8, 0.2],
    color: "#344968",
  },
  {
    name: "right_leg",
    model: "cube",
    position: [0.14, 0.48, 0],
    rotation: [0, 0, 0],
    dimensions: [0.2, 0.8, 0.2],
    color: "#344968",
  },
]);

const EMPTY_DESCRIPTOR = Object.freeze({
  visible: false,
  item: null,
  name: "empty hand",
  category: "empty",
  model: "none",
  color: null,
  block: null,
  count: 0,
  dimensions: null,
  pose: null,
});

function copyPose(template) {
  return {
    reference: template.reference,
    side: template.side,
    position: [...template.position],
    rotation: [...template.rotation],
    scale: [...template.scale],
  };
}

function normalizedSelection(value) {
  let item = null;
  let count = 1;

  if (typeof value === "string") {
    item = value;
  } else if (typeof value === "number") {
    item = itemId(value);
  } else if (value !== null && typeof value === "object") {
    if (typeof value.item === "string") item = value.item;
    else if (Number.isInteger(value.block)) item = itemId(value.block);
    if (Object.prototype.hasOwnProperty.call(value, "count")) count = Number(value.count);
  }

  if (item === "empty" || item === null || !Number.isFinite(count) || count <= 0) {
    return null;
  }

  const normalizedCount = Math.trunc(count);
  if (normalizedCount <= 0) return null;

  const definition = ITEM_DEFINITIONS[item];
  return definition === undefined
    ? null
    : { item, count: normalizedCount, definition };
}

function descriptorFor(value, poses) {
  const selection = normalizedSelection(value);
  if (selection === null) return { ...EMPTY_DESCRIPTOR };

  const { item, count, definition } = selection;
  return {
    visible: true,
    item,
    name: definition.name,
    category: definition.category,
    model: definition.model,
    color: definition.color,
    block: definition.block,
    count,
    dimensions: [...definition.dimensions],
    pose: copyPose(poses[definition.category]),
  };
}

/** Return a deterministic first-person descriptor for the selected inventory item. */
export function heldItemPose(selectedItem) {
  return descriptorFor(selectedItem, FIRST_PERSON_POSES);
}

/** Return a deterministic, simple third-person person descriptor with a right-hand item. */
export function characterRenderDescriptor(selectedItem) {
  return {
    kind: "person",
    type: "person",
    model: "humanoid",
    origin: "feet",
    parts: PERSON_PARTS.map((part) => ({
      name: part.name,
      model: part.model,
      position: [...part.position],
      rotation: [...part.rotation],
      dimensions: [...part.dimensions],
      color: part.color,
    })),
    heldItem: descriptorFor(selectedItem, THIRD_PERSON_POSES),
  };
}
