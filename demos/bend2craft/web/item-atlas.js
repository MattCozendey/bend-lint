import { TEXTURE_PASS } from "../assets/generated/textures/fallback-style.js";

export { TEXTURE_PASS };
export const ITEM_ATLAS_COLUMNS = 5;
// Every item id owns a cell, including the armour, the three raw meats and the
// nine tools, so the sheet has to reach id 71. At eleven rows the tool kinds
// landed outside it and were drawn as nothing.
export const ITEM_ATLAS_ROWS = 15;
export const ITEM_ATLAS_TILE_SIZE = 16;
export const ITEM_ATLAS_WIDTH = ITEM_ATLAS_COLUMNS * ITEM_ATLAS_TILE_SIZE;
export const ITEM_ATLAS_HEIGHT = ITEM_ATLAS_ROWS * ITEM_ATLAS_TILE_SIZE;
export const ITEM_TEXTURE_GRID_SIZE = TEXTURE_PASS.itemGridSize;
export const ITEM_TEXTURE_SIZE = 32;

const GLYPH_COLORS = new Set(["b", "a", "s", "h"]);

const TEXTURE_SPECS = [
  {
    name: "empty",
    label: "Empty",
    kind: "empty",
    colors: { base: "#8bbfdc", accent: "#8bbfdc", shadow: "#8bbfdc", highlight: "#8bbfdc" },
    pattern: [
      "........",
      "........",
      "........",
      "........",
      "........",
      "........",
      "........",
      "........",
    ],
  },
  {
    name: "stone",
    label: "Stone",
    kind: "block",
    colors: { base: "#7f8a91", accent: "#aeb7ba", shadow: "#4e585e", highlight: "#d1d6d6" },
    pattern: [
      "ssssssss",
      "sbbbbbbs",
      "bbhbbbbb",
      "bbbbabbs",
      "bbbbsbbb",
      "bbbbbhab",
      "sbbsbbbs",
      "ssssssss",
    ],
  },
  {
    name: "dirt",
    label: "Dirt",
    kind: "block",
    colors: { base: "#9b5c38", accent: "#c27b4c", shadow: "#613b29", highlight: "#d6965c" },
    pattern: [
      "ssssssss",
      "sbbbbbbs",
      "bbabbbbs",
      "bbsbbbbb",
      "bbbbbbab",
      "bbbsbbbb",
      "sbbbbbbs",
      "ssssssss",
    ],
  },
  {
    name: "grass",
    label: "Grass",
    kind: "block",
    colors: { base: "#58ad42", accent: "#9b5c38", shadow: "#276a35", highlight: "#8bd35d" },
    pattern: [
      "hhhhhhhh",
      "hhbhabhh",
      "aaaaaaaa",
      "aaaaaaaa",
      "aaabaaaa",
      "aaaaasaa",
      "aaaaaaaa",
      "ssssssss",
    ],
  },
  {
    name: "leaves",
    label: "Leaves",
    kind: "block",
    colors: { base: "#2e8c43", accent: "#58b95a", shadow: "#1c5b32", highlight: "#8bd35d" },
    pattern: [
      ".ssssss.",
      "sbabbbas",
      "sbbhbbbs",
      "bbabbbbs",
      "bbbbsbbb",
      "sbbababs",
      "sbbaabbs",
      ".ssssss.",
    ],
  },
  {
    name: "wood",
    label: "Wood",
    kind: "block",
    colors: { base: "#a66a3f", accent: "#c99058", shadow: "#633b29", highlight: "#e0a96f" },
    pattern: [
      "ssssssss",
      "sbbbbbbs",
      "sbbsbbbs",
      "sbbbbbbs",
      "sbbsbbbs",
      "sbbbbbbs",
      "sbbhbbbs",
      "ssssssss",
    ],
  },
  {
    name: "sand",
    label: "Sand",
    kind: "block",
    colors: { base: "#d9bd72", accent: "#f0d994", shadow: "#a4864e", highlight: "#fff0b4" },
    pattern: [
      "ssssssss",
      "sbbbbbbs",
      "bbhbbbbb",
      "bbbbabbs",
      "bbbbsbbb",
      "bbbbbhab",
      "sbbbbbbs",
      "ssssssss",
    ],
  },
  {
    name: "water",
    label: "Water",
    kind: "liquid",
    colors: { base: "#4d9bd6", accent: "#86c8f0", shadow: "#2869a5", highlight: "#c3ebff" },
    pattern: [
      "ssssssss",
      "bbbbbbbb",
      "bbahbbba",
      "bbbbbbbb",
      "bbhbbbbb",
      "babbbbab",
      "bbbbbbbb",
      "ssssssss",
    ],
  },
  {
    name: "planks",
    label: "Wood Planks",
    kind: "material",
    colors: { base: "#c28a4d", accent: "#e0b16c", shadow: "#704628", highlight: "#f2ce8d" },
    pattern: [
      "ssssssss",
      "bbbbbbbb",
      "ssssssss",
      "bbbbbbbb",
      "bbbbhbbb",
      "ssssssss",
      "bbbbbbbb",
      "ssssssss",
    ],
  },
  {
    name: "sticks",
    label: "Sticks",
    kind: "material",
    colors: { base: "#b77b48", accent: "#e1b278", shadow: "#6d452b", highlight: "#f1d09b" },
    pattern: [
      "..ab....",
      "...ab...",
      "....ab..",
      ".....ab.",
      ".ab.....",
      "..ab....",
      "...ab...",
      "........",
    ],
  },
  {
    name: "crafting_table",
    label: "Crafting Table",
    kind: "placeable",
    colors: { base: "#9d6a3e", accent: "#d09a5e", shadow: "#5b3927", highlight: "#f0c37e" },
    pattern: [
      "ssssssss",
      "saaaaaas",
      "sahhaaas",
      "saabbbas",
      "sbbbbbas",
      "sbbasbbs",
      "saaaaaas",
      "ssssssss",
    ],
  },
  {
    name: "wooden_pickaxe",
    label: "Wooden Pickaxe",
    kind: "tool",
    colors: { base: "#b77b48", accent: "#d9a369", shadow: "#63402a", highlight: "#f0c68a" },
    pattern: [
      "..ssssss........",
      ".sshhhhss.......",
      "sshhhha.........",
      ".shhhhha........",
      "..bb............",
      "...bb...........",
      "....bb..........",
      "....bb..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
    ],
  },
  {
    name: "wool",
    label: "Wool",
    kind: "material",
    colors: { base: "#ece8d8", accent: "#fffdf2", shadow: "#aaa89e", highlight: "#ffffff" },
    pattern: [
      "..ssss..",
      ".sbbbbs.",
      "sbhbbhbs",
      "sbbbbbbs",
      "sbbaabbs",
      ".sbbbbs.",
      "..ssss..",
      "........",
    ],
  },
  {
    name: "rotten_flesh",
    label: "Rotten Flesh",
    kind: "food",
    colors: { base: "#8c4d45", accent: "#b86a56", shadow: "#4e2f35", highlight: "#d88a65" },
    pattern: [
      "........",
      "..ss....",
      ".sbbas..",
      "sbbbaabs",
      "sbbaabss",
      ".sbbbbs.",
      "..ss....",
      "........",
    ],
  },
  {
    name: "coal",
    label: "Coal",
    kind: "material",
    colors: { base: "#24262b", accent: "#454b54", shadow: "#101216", highlight: "#737b84" },
    pattern: [
      "........",
      "..ssss..",
      ".sbbbs..",
      "sbbabbs.",
      "sbbbbbs.",
      ".sbbbs..",
      "..ssss..",
      "........",
    ],
  },
  {
    name: "raw_iron",
    label: "Raw Iron",
    kind: "material",
    colors: { base: "#c28a6d", accent: "#e0ae8c", shadow: "#744f46", highlight: "#f2ceb0" },
    pattern: [
      "........",
      "...ss...",
      "..sbbss.",
      ".sbbabbs",
      "sbbbbbbs",
      ".sbbbbs.",
      "..ss....",
      "........",
    ],
  },
  {
    name: "diamond",
    label: "Diamond",
    kind: "material",
    colors: { base: "#68e4df", accent: "#b9ffff", shadow: "#249da8", highlight: "#efffff" },
    pattern: [
      "...hh...",
      "..hbbh..",
      ".hbaabh.",
      "hbbaabbh",
      "bbaaaabb",
      ".hbaabh.",
      "..hbbh..",
      "...ss...",
    ],
  },
  {
    name: "stone_pickaxe",
    label: "Stone Pickaxe",
    kind: "tool",
    colors: { base: "#92999f", accent: "#c5cbcd", shadow: "#4e585e", highlight: "#edf0ef" },
    pattern: [
      "..ssssss........",
      ".sshhhhss.......",
      "sshhhha.........",
      ".shhhhha........",
      "..bb............",
      "...bb...........",
      "....bb..........",
      "....bb..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
    ],
  },
  {
    name: "iron_pickaxe",
    label: "Iron Pickaxe",
    kind: "tool",
    colors: { base: "#d5d9dc", accent: "#f2f4f4", shadow: "#7a838a", highlight: "#ffffff" },
    pattern: [
      "..ssssss........",
      ".sshhhhss.......",
      "sshhhha.........",
      ".shhhhha........",
      "..bb............",
      "...bb...........",
      "....bb..........",
      "....bb..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
    ],
  },
  {
    name: "diamond_pickaxe",
    label: "Diamond Pickaxe",
    kind: "tool",
    colors: { base: "#5ee8e0", accent: "#b9ffff", shadow: "#249da8", highlight: "#efffff" },
    pattern: [
      "..ssssss........",
      ".sshhhhss.......",
      "sshhhha.........",
      ".shhhhha........",
      "..bb............",
      "...bb...........",
      "....bb..........",
      "....bb..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
    ],
  },
  {
    name: "iron_ingot",
    label: "Iron Ingot",
    kind: "material",
    colors: { base: "#d9dde2", accent: "#f4f6f6", shadow: "#7c858d", highlight: "#ffffff" },
    pattern: [
      "........",
      "..ssss..",
      ".sbbbbs.",
      "sbhbbhbs",
      "sbbbbbbs",
      ".saaaabs",
      ".ssssss.",
      "........",
    ],
  },
  {
    name: "furnace",
    label: "Furnace",
    kind: "placeable",
    colors: { base: "#5b5f66", accent: "#858b91", shadow: "#24272c", highlight: "#b9bec0" },
    pattern: [
      "ssssssss",
      "sbbbbbbs",
      "sbssssbs",
      "sbaaaabs",
      "sbaaaabs",
      "sbbbbbbs",
      "sbbhhbbs",
      "ssssssss",
    ],
  },
  {
    name: "torch",
    label: "Torch",
    kind: "placeable",
    colors: { base: "#8c5a38", accent: "#f5b44c", shadow: "#4d3024", highlight: "#fff0a0" },
    pattern: [
      ".......h........",
      "......haa.......",
      ".....haaaa......",
      ".....aaaaa......",
      "......aaa.......",
      ".......a........",
      ".......b........",
      ".......b........",
      "......bb........",
      ".......b........",
      ".......b........",
      ".......b........",
      "......sb........",
      "......ss........",
      "................",
      "................",
    ],
  },
  {
    name: "bed",
    label: "Bed",
    kind: "placeable",
    colors: { base: "#c94f62", accent: "#f27b86", shadow: "#673844", highlight: "#ffb0a8" },
    pattern: [
      "ssaaaaaaaaaaaass",
      "saaaaaaaaaaaaaas",
      "saaabbbbbbbbaaas",
      "saaabbbbbbbbaaas",
      "sbbbbbbbbbbbbbbs",
      "bbbbbbbbbbbbbbbb",
      "ssbbssssbbssbbbb",
      "ssbbssssbbssbbbb",
      "................",
      "................",
      "................",
      "................",
      "................",
      "................",
      "................",
      "................",
    ],
  },
  {
    name: "door",
    label: "Door",
    kind: "placeable",
    colors: { base: "#8c5a38", accent: "#b47a4d", shadow: "#4d3024", highlight: "#d9a16b" },
    pattern: [
      "ssssssssssssssss",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "sbbbbbbbbbbbbbbs",
      "ssssssssssssssss",
    ],
  },
  {
    name: "wheat_seeds",
    label: "Wheat Seeds",
    kind: "food",
    colors: { base: "#b8993c", accent: "#e3c85a", shadow: "#67552a", highlight: "#fff0a0" },
    pattern: [
      "........",
      "..a.....",
      ".....a..",
      "...b....",
      "......a.",
      ".a......",
      "....b...",
      "........",
    ],
  },
  {
    name: "wheat",
    label: "Wheat",
    kind: "food",
    colors: { base: "#c79d35", accent: "#f4d45a", shadow: "#715326", highlight: "#fff09a" },
    pattern: [
      "...a....",
      "..aaa...",
      "...a....",
      "..a.....",
      "...b....",
      "...b....",
      "..bb....",
      "...b....",
    ],
  },
  {
    name: "wooden_hoe",
    label: "Wooden Hoe",
    kind: "tool",
    colors: { base: "#b77b48", accent: "#d9a16b", shadow: "#5d3927", highlight: "#f0c18b" },
    pattern: [
      "...aa...........",
      "..aaaa..........",
      "...aaa..........",
      ".....b..........",
      ".....b..........",
      "....bb..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
      "................",
    ],
  },
  {
    name: "wooden_sword",
    label: "Wooden Sword",
    kind: "weapon",
    colors: { base: "#b77b48", accent: "#d9a16b", shadow: "#5d3927", highlight: "#f0c18b" },
    pattern: [
      "......aa",
      ".....aaa",
      "....aaa.",
      "...aaa..",
      "..aaa...",
      ".ssaa...",
      ".hbb....",
      "..bb....",
    ],
  },
  {
    name: "stone_sword",
    label: "Stone Sword",
    kind: "weapon",
    colors: { base: "#92999f", accent: "#b9c0c6", shadow: "#4c5257", highlight: "#dde3e8" },
    pattern: [
      "......aa",
      ".....aaa",
      "....aaa.",
      "...aaa..",
      "..aaa...",
      ".ssaa...",
      ".hbb....",
      "..bb....",
    ],
  },
  {
    name: "iron_sword",
    label: "Iron Sword",
    kind: "weapon",
    colors: { base: "#d5d9dc", accent: "#f2f5f7", shadow: "#7d848a", highlight: "#ffffff" },
    pattern: [
      "......aa",
      ".....aaa",
      "....aaa.",
      "...aaa..",
      "..aaa...",
      ".ssaa...",
      ".hbb....",
      "..bb....",
    ],
  },
  {
    name: "diamond_sword",
    label: "Diamond Sword",
    kind: "weapon",
    colors: { base: "#5ee8e0", accent: "#a5f5f0", shadow: "#2a9d97", highlight: "#d8fffc" },
    pattern: [
      "......aa",
      ".....aaa",
      "....aaa.",
      "...aaa..",
      "..aaa...",
      ".ssaa...",
      ".hbb....",
      "..bb....",
    ],
  },
  {
    name: "bow",
    label: "Bow",
    kind: "weapon",
    colors: { base: "#8c5a38", accent: "#b47a4d", shadow: "#4a2d1a", highlight: "#d9a06b" },
    pattern: [
      ".aa.....",
      "..aba..s",
      "...ab..s",
      "...ab..s",
      "...ab..s",
      "...ab..s",
      "..aba..s",
      ".aa.....",
    ],
  },
  {
    name: "arrow",
    label: "Arrow",
    kind: "ammo",
    colors: { base: "#d8cfc0", accent: "#fff6e6", shadow: "#8a8172", highlight: "#ffffff" },
    pattern: [
      "......aa",
      ".....aa.",
      "....aa..",
      "...aa...",
      "..ab....",
      ".hb.....",
      "hb......",
      "b.......",
    ],
  },
  {
    name: "shield",
    label: "Shield",
    kind: "armor",
    colors: { base: "#7f8a91", accent: "#aab4ba", shadow: "#3f464b", highlight: "#d5dde2" },
    pattern: [
      ".ssssss.",
      "sabbbbba",
      "sabbhbba",
      "sabbhbba",
      ".abbbba.",
      "..abbba.",
      "...aba..",
      "....a...",
    ],
  },
  {
    name: "glass",
    label: "Glass",
    kind: "block",
    colors: { base: "#b5d9e8", accent: "#e8f6fc", shadow: "#6fa3bd", highlight: "#ffffff" },
    pattern: [
      "ssssssss",
      "sbbbbbbs",
      "sbbaabbs",
      "sbaaaabs",
      "sbaaaabs",
      "sbbaabbs",
      "sbbbbbbs",
      "ssssssss",
    ],
  },
  {
    name: "bread",
    label: "Bread",
    kind: "food",
    colors: { base: "#d59b45", accent: "#f2c979", shadow: "#8f5a2c", highlight: "#ffe4a3" },
    pattern: [
      "........",
      "..aaaa..",
      ".abbbba.",
      "abbbbbba",
      "abbbhbba",
      ".abbbba.",
      "..ssss..",
      "........",
    ],
  },
  {
    name: "apple",
    label: "Apple",
    kind: "food",
    colors: { base: "#c94a3f", accent: "#f07052", shadow: "#7c2418", highlight: "#ffb36a" },
    pattern: [
      "...s....",
      "..saa...",
      ".aabbaa.",
      "aabbbbaa",
      "aabbbbaa",
      ".aabbaa.",
      "..aaaa..",
      "........",
    ],
  },
  {
    name: "chest",
    label: "Chest",
    kind: "placeable",
    colors: { base: "#9d6a3e", accent: "#cf9560", shadow: "#5c3a22", highlight: "#e8b878" },
    pattern: [
      "ssssssss",
      "saaaaaas",
      "sabbbbas",
      "sbbbbbbs",
      "sbbbbbbs",
      "sabbbbas",
      "saaaaaas",
      "ssssssss",
    ],
  },
  {
    name: "leather_helmet",
    label: "Leather Helmet",
    kind: "armor",
    colors: { base: "#9b5c38", accent: "#c27b4c", shadow: "#613b29", highlight: "#d6965c" },
    pattern: [
      "..ssss..",
      ".saaabs.",
      "sbbbbbbs",
      "sbbbbbbs",
      "sbbbbbbs",
      "sbbbbbbs",
      ".sbbbbbs",
      "..ssss..",
    ],
  },
  {
    name: "iron_chestplate",
    label: "Iron Chestplate",
    kind: "armor",
    colors: { base: "#c5cbcd", accent: "#edf0ef", shadow: "#4e585e", highlight: "#ffffff" },
    pattern: [
      "s......s",
      "sbbbbbbs",
      "sbaaaabs",
      "sbbbbbbs",
      "sbbbbbbs",
      "sbbbbbbs",
      "sbbbbbbs",
      ".ssssss.",
    ],
  },
  {
    name: "iron_leggings",
    label: "Iron Leggings",
    kind: "armor",
    colors: { base: "#aeb7ba", accent: "#edf0ef", shadow: "#4e585e", highlight: "#ffffff" },
    pattern: [
      ".ssssss.",
      "sbbbbbbs",
      "sbbbbbbs",
      "sbbbbbbs",
      "sbbbbsbs",
      "sbbbbsbs",
      "sbbbbsbs",
      ".ssssss.",
    ],
  },
  {
    name: "iron_boots",
    label: "Iron Boots",
    kind: "armor",
    colors: { base: "#92999f", accent: "#edf0ef", shadow: "#4e585e", highlight: "#ffffff" },
    pattern: [
      "........",
      "sbb..bbs",
      "sbb..bbs",
      "sbb..bbs",
      "sbb..bbs",
      "sbbbbbbs",
      "sbbbbbbs",
      ".ssssss.",
    ],
  },
  // Raw meat: the same cut in three colours, with a bone on the pork so the
  // three read apart in a 16px cell.
  {
    name: "raw_porkchop",
    label: "Raw Porkchop",
    kind: "meat",
    colors: { base: "#e08a80", accent: "#f4b6ad", shadow: "#9c534e", highlight: "#ffe0da" },
    pattern: [
      "........",
      ".s.s....",
      "sbb.s...",
      "sbbbb.s.",
      "sbbbbbbs",
      ".sbbbbb.",
      "..sbb...",
      "...s....",
    ],
  },
  {
    name: "raw_beef",
    label: "Raw Beef",
    kind: "meat",
    colors: { base: "#b4443c", accent: "#d9736a", shadow: "#74251f", highlight: "#f0a49c" },
    pattern: [
      "........",
      "........",
      ".sbbb...",
      "sbbbbb..",
      "sbbbbbb.",
      "sbbbbbb.",
      ".sbbbb..",
      "..ss....",
    ],
  },
  {
    name: "raw_chicken",
    label: "Raw Chicken",
    kind: "meat",
    colors: { base: "#e0cba6", accent: "#f3e6cb", shadow: "#9c8763", highlight: "#fff8ea" },
    pattern: [
      "........",
      "..s.s...",
      "..sss...",
      "sbbbbb..",
      "sbbbbbb.",
      "sbbbbbb.",
      ".sbbbb..",
      "..ss....",
    ],
  },

  {
    name: "wooden_shovel",
    label: "Wooden Shovel",
    kind: "tool",
    colors: { base: "#b77b48", accent: "#d9a369", shadow: "#63402a", highlight: "#f0c68a" },
    pattern: [
      "....ss..........",
      "....ss..........",
      "....ss..........",
      "..ssssss........",
      ".sshhhhss.......",
      "sshhhha.........",
      ".shhhhha........",
      "....b...........",
      "....b...........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
    ],
  },
  {
    name: "stone_shovel",
    label: "Stone Shovel",
    kind: "tool",
    colors: { base: "#92999f", accent: "#c5cbcd", shadow: "#4e585e", highlight: "#edf0ef" },
    pattern: [
      "....ss..........",
      "....ss..........",
      "....ss..........",
      "..ssssss........",
      ".sshhhhss.......",
      "sshhhha.........",
      ".shhhhha........",
      "....b...........",
      "....b...........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
    ],
  },
  {
    name: "iron_shovel",
    label: "Iron Shovel",
    kind: "tool",
    colors: { base: "#d5d9dc", accent: "#f2f4f4", shadow: "#7a838a", highlight: "#ffffff" },
    pattern: [
      "....ss..........",
      "....ss..........",
      "....ss..........",
      "..ssssss........",
      ".sshhhhss.......",
      "sshhhha.........",
      ".shhhhha........",
      "....b...........",
      "....b...........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
    ],
  },
  {
    name: "diamond_shovel",
    label: "Diamond Shovel",
    kind: "tool",
    colors: { base: "#5ee8e0", accent: "#a9f4ef", shadow: "#2f8f88", highlight: "#d6fffb" },
    pattern: [
      "....ss..........",
      "....ss..........",
      "....ss..........",
      "..ssssss........",
      ".sshhhhss.......",
      "sshhhha.........",
      ".shhhhha........",
      "....b...........",
      "....b...........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....b..........",
      ".....h..........",
    ],
  },
  {
    name: "wooden_axe",
    label: "Wooden Axe",
    kind: "tool",
    colors: { base: "#b77b48", accent: "#d9a369", shadow: "#63402a", highlight: "#f0c68a" },
    pattern: [
      "..ssss..........",
      "..sshh..........",
      "..sshh..........",
      "..sshh..........",
      "..ssshh.........",
      "...ssshh........",
      "....ssshh.......",
      ".....ssshh......",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......h.........",
    ],
  },
  {
    name: "stone_axe",
    label: "Stone Axe",
    kind: "tool",
    colors: { base: "#92999f", accent: "#c5cbcd", shadow: "#4e585e", highlight: "#edf0ef" },
    pattern: [
      "..ssss..........",
      "..sshh..........",
      "..sshh..........",
      "..sshh..........",
      "..ssshh.........",
      "...ssshh........",
      "....ssshh.......",
      ".....ssshh......",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......h.........",
    ],
  },
  {
    name: "iron_axe",
    label: "Iron Axe",
    kind: "tool",
    colors: { base: "#d5d9dc", accent: "#f2f4f4", shadow: "#7a838a", highlight: "#ffffff" },
    pattern: [
      "..ssss..........",
      "..sshh..........",
      "..sshh..........",
      "..sshh..........",
      "..ssshh.........",
      "...ssshh........",
      "....ssshh.......",
      ".....ssshh......",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......h.........",
    ],
  },
  {
    name: "diamond_axe",
    label: "Diamond Axe",
    kind: "tool",
    colors: { base: "#5ee8e0", accent: "#a9f4ef", shadow: "#2f8f88", highlight: "#d6fffb" },
    pattern: [
      "..ssss..........",
      "..sshh..........",
      "..sshh..........",
      "..sshh..........",
      "..ssshh.........",
      "...ssshh........",
      "....ssshh.......",
      ".....ssshh......",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......bb........",
      "......h.........",
    ],
  },
  {
    name: "shears",
    label: "Shears",
    kind: "tool",
    colors: { base: "#c3ccd4", accent: "#eef2f5", shadow: "#7d868d", highlight: "#ffffff" },
    pattern: [
      "....aaa.........",
      "...abbba........",
      "..abb...ba......",
      "..ab.....ba.....",
      ".ab.......ba....",
      ".ab.......ba....",
      ".ab.......ba....",
      "..a.......ba....",
      "..........ba....",
      "..........ba....",
      ".........baa....",
      ".........baa....",
      "........baa.....",
      "........ba......",
      ".......ba.......",
      ".......a........",
    ],
  },];

function refinePattern(pattern) {
  if (!Array.isArray(pattern)) return pattern;
  if (pattern.length === ITEM_TEXTURE_GRID_SIZE) return pattern;
  if (pattern.length !== 8 || pattern.some((row) => typeof row !== "string" || row.length !== 8)) {
    throw new TypeError("Item texture patterns must have eight or sixteen cells per side.");
  }
  const refined = [];
  for (let row = 0; row < pattern.length; row += 1) {
    const source = pattern[row];
    for (let subrow = 0; subrow < 2; subrow += 1) {
      let refinedRow = "";
      for (let column = 0; column < source.length; column += 1) {
        const glyph = source[column];
        if (glyph === ".") {
          refinedRow += "..";
          continue;
        }
        const detail = (row * 11 + column * 7 + subrow * 3) % 9;
        const first = subrow === 0 && detail === 0 && glyph !== "h" ? "h" : glyph;
        const second = subrow === 1 && detail === 3 && glyph !== "s" ? "s" : glyph;
        refinedRow += `${first}${second}`;
      }
      refined.push(refinedRow);
    }
  }
  return refined;
}

function freezePattern(pattern) {
  const refined = refinePattern(pattern);
  if (!Array.isArray(refined) || refined.length !== ITEM_TEXTURE_GRID_SIZE) {
    throw new TypeError("Item texture patterns must have sixteen rows.");
  }
  for (const row of refined) {
    if (typeof row !== "string" || row.length !== ITEM_TEXTURE_GRID_SIZE) {
      throw new TypeError("Item texture pattern rows must have sixteen cells.");
    }
    for (const glyph of row) {
      if (glyph !== "." && !GLYPH_COLORS.has(glyph)) {
        throw new TypeError(`Unknown item texture glyph: ${glyph}`);
      }
    }
  }
  return Object.freeze([...refined]);
}

function freezeTexture(spec, id) {
  const colors = Object.freeze({ ...spec.colors });
  const pattern = freezePattern(spec.pattern);
  const tile = Object.freeze({
    column: id % ITEM_ATLAS_COLUMNS,
    row: Math.floor(id / ITEM_ATLAS_COLUMNS),
  });
  return Object.freeze({
    id,
    name: spec.name,
    label: spec.label,
    kind: spec.kind,
    color: colors.base,
    baseColor: colors.base,
    accentColor: colors.accent,
    shadowColor: colors.shadow,
    highlightColor: colors.highlight,
    colors,
    pattern,
    pass: TEXTURE_PASS.id,
    tile,
  });
}

export const ITEM_TEXTURES = Object.freeze(TEXTURE_SPECS.map(freezeTexture));
export const ITEM_TEXTURES_BY_ID = Object.freeze(
  Object.fromEntries(ITEM_TEXTURES.map((texture) => [texture.id, texture])),
);
export const ITEM_TEXTURES_BY_NAME = Object.freeze(
  Object.fromEntries(ITEM_TEXTURES.map((texture) => [texture.name, texture])),
);

function hasOwn(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function numericId(value) {
  if (typeof value === "bigint") {
    if (value < 0n || value >= BigInt(ITEM_TEXTURES.length)) return null;
    return Number(value);
  }
  if (!Number.isInteger(value) || value < 0 || value >= ITEM_TEXTURES.length) return null;
  return value;
}

/** Resolve an item ID from a canonical name, numeric ID, or item-like object. */
export function itemTextureId(value) {
  const numeric = numericId(value);
  if (numeric !== null) return numeric;
  if (typeof value === "string") return hasOwn(ITEM_TEXTURES_BY_NAME, value) ? ITEM_TEXTURES_BY_NAME[value].id : null;
  if (value === null || typeof value !== "object") return null;
  if (hasOwn(value, "name")) return itemTextureId(value.name);
  if (hasOwn(value, "item")) return itemTextureId(value.item);
  if (hasOwn(value, "id")) return itemTextureId(value.id);
  return null;
}

/** Return the immutable descriptor for an item, or null for an unknown item. */
export function itemTexture(value) {
  const id = itemTextureId(value);
  return id === null ? null : ITEM_TEXTURES[id];
}

/** Return the atlas tile for an item, or null for an unknown item. */
export function itemTextureTile(value) {
  return itemTexture(value)?.tile ?? null;
}

/**
 * Return WebGL-ready UVs in bottom-left quad order:
 * [u0, vTop, u1, vTop, u1, vBottom, u0, vBottom].
 * The optional inset is measured in source-tile pixels.
 */
export function itemTextureUV(value, options = {}) {
  const tile = itemTextureTile(value);
  if (tile === null) return null;
  const tileSize = Number(options.tileSize ?? ITEM_ATLAS_TILE_SIZE);
  const insetPixels = Number(options.inset ?? 0.5);
  if (!Number.isFinite(tileSize) || tileSize <= 0) throw new RangeError("tileSize must be positive.");
  if (!Number.isFinite(insetPixels) || insetPixels < 0 || insetPixels * 2 >= tileSize) {
    throw new RangeError("inset must be non-negative and smaller than half the tile size.");
  }
  const inset = insetPixels / tileSize;
  const u0 = (tile.column + inset) / ITEM_ATLAS_COLUMNS;
  const u1 = (tile.column + 1 - inset) / ITEM_ATLAS_COLUMNS;
  const vTop = 1 - (tile.row + inset) / ITEM_ATLAS_ROWS;
  const vBottom = 1 - (tile.row + 1 - inset) / ITEM_ATLAS_ROWS;
  return Object.freeze([u0, vTop, u1, vTop, u1, vBottom, u0, vBottom]);
}

function validContext(context) {
  if (context === null || typeof context !== "object" || typeof context.fillRect !== "function") {
    throw new TypeError("A 2D canvas context with fillRect is required.");
  }
  return context;
}

function textureSize(value, label = "size") {
  const size = Number(value);
  if (!Number.isInteger(size) || size <= 0) throw new RangeError(`${label} must be a positive integer.`);
  return size;
}

function drawPattern(context, texture, size, offsetX, offsetY, options) {
  const pixelSize = size / ITEM_TEXTURE_GRID_SIZE;
  const palette = {
    b: texture.baseColor,
    a: texture.accentColor,
    s: texture.shadowColor,
    h: texture.highlightColor,
  };
  for (let row = 0; row < ITEM_TEXTURE_GRID_SIZE; row += 1) {
    for (let column = 0; column < ITEM_TEXTURE_GRID_SIZE; column += 1) {
      const glyph = texture.pattern[row][column];
      if (glyph === ".") continue;
      context.fillStyle = palette[glyph];
      context.fillRect(
        offsetX + column * pixelSize,
        offsetY + row * pixelSize,
        pixelSize,
        pixelSize,
      );
    }
  }
  if (options.outline !== undefined) {
    if (typeof context.strokeRect !== "function") throw new TypeError("The context must support strokeRect for outlines.");
    context.strokeStyle = String(options.outline);
    context.strokeRect(offsetX, offsetY, size, size);
  }
}

function drawItemEdge(context, texture, size, offsetX, offsetY) {
  if (texture.kind === "empty") return;
  const previousAlpha = context.globalAlpha;
  context.globalAlpha = TEXTURE_PASS.edgeHighlightAlpha;
  context.fillStyle = texture.highlightColor;
  context.fillRect(offsetX, offsetY, size, 1);
  context.fillRect(offsetX, offsetY + 1, 1, Math.max(0, size - 2));
  context.globalAlpha = TEXTURE_PASS.edgeShadowAlpha;
  context.fillStyle = texture.shadowColor;
  context.fillRect(offsetX, offsetY + size - 1, size, 1);
  context.fillRect(offsetX + size - 1, offsetY + 1, 1, Math.max(0, size - 2));
  context.globalAlpha = previousAlpha;
}

function drawWithState(context, texture, size, offsetX, offsetY, options) {
  const previousSmoothing = context.imageSmoothingEnabled;
  const previousFillStyle = context.fillStyle;
  const previousStrokeStyle = context.strokeStyle;
  const previousGlobalAlpha = context.globalAlpha;
  const clear = options.clear ?? true;
  try {
    context.imageSmoothingEnabled = false;
    if (clear) {
      if (typeof context.clearRect !== "function") throw new TypeError("The context must support clearRect when clear is enabled.");
      context.clearRect(offsetX, offsetY, size, size);
    }
    if (options.background !== undefined) {
      context.fillStyle = String(options.background);
      context.fillRect(offsetX, offsetY, size, size);
    }
    drawPattern(context, texture, size, offsetX, offsetY, options);
    drawItemEdge(context, texture, size, offsetX, offsetY);
  } finally {
    context.imageSmoothingEnabled = previousSmoothing;
    context.fillStyle = previousFillStyle;
    context.strokeStyle = previousStrokeStyle;
    context.globalAlpha = previousGlobalAlpha;
  }
}

/** Draw one deterministic pixel-art item into an existing 2D context. */
export function drawItemTexture(context, value, options = {}) {
  const texture = itemTexture(value);
  if (texture === null) throw new RangeError("Unknown item texture.");
  validContext(context);
  const size = textureSize(options.size ?? ITEM_TEXTURE_SIZE);
  const offsetX = Number(options.x ?? 0);
  const offsetY = Number(options.y ?? 0);
  if (!Number.isFinite(offsetX) || !Number.isFinite(offsetY)) throw new RangeError("x and y must be finite.");
  drawWithState(context, texture, size, offsetX, offsetY, options);
  return context;
}

/** Create a canvas containing one deterministic item texture. */
export function createItemTextureCanvas(value, options = {}) {
  const texture = itemTexture(value);
  if (texture === null) throw new RangeError("Unknown item texture.");
  const size = textureSize(options.size ?? ITEM_TEXTURE_SIZE);
  const documentRef = options.document ?? globalThis.document;
  if (documentRef === null || typeof documentRef?.createElement !== "function") {
    throw new Error("A document with canvas support is required to create an item texture canvas.");
  }
  const canvas = documentRef.createElement("canvas");
  if (canvas === null || typeof canvas.getContext !== "function") {
    throw new Error("The document did not create a canvas element.");
  }
  canvas.width = size;
  canvas.height = size;
  const context = canvas.getContext("2d");
  if (context === null) throw new Error("2D canvas is required to create an item texture.");
  drawItemTexture(context, texture, { ...options, size, x: 0, y: 0, clear: true });
  return canvas;
}

/** Draw the complete item atlas into an existing 2D context. */
export function drawItemTextureAtlas(context, options = {}) {
  validContext(context);
  const tileSize = textureSize(options.tileSize ?? ITEM_ATLAS_TILE_SIZE, "tileSize");
  const width = ITEM_ATLAS_COLUMNS * tileSize;
  const height = ITEM_ATLAS_ROWS * tileSize;
  if (options.clear ?? true) {
    if (typeof context.clearRect !== "function") throw new TypeError("The context must support clearRect when clear is enabled.");
    context.clearRect(0, 0, width, height);
  }
  if (options.background !== undefined) {
    context.fillStyle = String(options.background);
    context.fillRect(0, 0, width, height);
  }
  for (const texture of ITEM_TEXTURES) {
    drawWithState(
      context,
      texture,
      tileSize,
      texture.tile.column * tileSize,
      texture.tile.row * tileSize,
      { ...options, clear: false, background: undefined },
    );
  }
  return context;
}

/** Create a canvas containing all 25 item textures in a 5 by 5 atlas. */
export function createItemTextureAtlasCanvas(options = {}) {
  const tileSize = textureSize(options.tileSize ?? ITEM_ATLAS_TILE_SIZE, "tileSize");
  const documentRef = options.document ?? globalThis.document;
  if (documentRef === null || typeof documentRef?.createElement !== "function") {
    throw new Error("A document with canvas support is required to create an item atlas canvas.");
  }
  const canvas = documentRef.createElement("canvas");
  if (canvas === null || typeof canvas.getContext !== "function") {
    throw new Error("The document did not create a canvas element.");
  }
  canvas.width = ITEM_ATLAS_COLUMNS * tileSize;
  canvas.height = ITEM_ATLAS_ROWS * tileSize;
  const context = canvas.getContext("2d");
  if (context === null) throw new Error("2D canvas is required to create an item atlas.");
  drawItemTextureAtlas(context, { ...options, tileSize, clear: true });
  return canvas;
}
