import { TEXTURE_PASS } from "../assets/generated/textures/fallback-style.js";
import { MATERIAL_PAINTERS, materialSeed, paintMaterial } from "./material-textures.js";

export { TEXTURE_PASS };
export const ATLAS_COLUMNS = 8;
export const ATLAS_ROWS = 8;
// A block face is 30-60 screen pixels at the distances a player usually stands
// at, and several hundred when the player walks up to a wall. A 64-texel tile was
// already magnified past 1:1 up close, so every material read as a soft smear
// rather than as stone, bark or grass. 128 texels keeps real material structure
// (individual stones, blades, fibres) resolvable at arm's length, and the whole
// padded atlas is 2048x2048, 16 MB of RGBA, which every WebGL target accepts.
export const ATLAS_TILE_SIZE = 128;
// Mip levels average 2x2 texels, so a tile with no padding blends into its
// neighbour as soon as the surface is minified. Padding has to survive the
// averaging, so a certified level needs both a non-zero padding and an interior
// of at least two texels. A 64-texel gutter with a 128-texel tile reaches that
// at level 6; level 7 would leave a single texel with no padding, which is one
// pixel of the whole cell and nothing left to keep separate.
export const ATLAS_TILE_GUTTER = 64;
export const ATLAS_TILE_STRIDE = ATLAS_TILE_SIZE + 2 * ATLAS_TILE_GUTTER;
export const ATLAS_MIPMAP_SAFE_LEVELS = Object.freeze([1, 2, 3, 4, 5, 6]);
export const ATLAS_CAPACITY = ATLAS_COLUMNS * ATLAS_ROWS;
export const ATLAS_WIDTH = ATLAS_COLUMNS * ATLAS_TILE_STRIDE;
export const ATLAS_HEIGHT = ATLAS_ROWS * ATLAS_TILE_STRIDE;

/**
 * Geometry of a tile's padded cell at one mip level. Texels are discrete, so
 * both the interior and the gutter are floored: that keeps the reported cell
 * from claiming texels the level does not have, which is what makes a level
 * correctly report itself as unprobeable once it is too small to certify.
 */
export function atlasMipLevelGeometry(gutter, tileSize, level) {
  const factor = 2 ** level;
  const interior = Math.max(1, Math.floor(tileSize / factor));
  const padding = Math.max(0, Math.floor(gutter / factor));
  return { interior, padding, size: interior + 2 * padding, factor };
}

/**
 * Reference mip level, produced by repeated 2x2 box averaging on the CPU.
 *
 * WebGL builds its chain with the driver's `generateMipmap`. WebGPU has no
 * equivalent, so the renderer has to write each level itself, and a hand-written
 * downsample can be subtly wrong in a way that only shows up as a washed-out
 * scene. This reference is the definition of a correct chain, computed a
 * completely different way, so comparing against it can actually fail.
 */
export function atlasBoxDownsample(size, pixels, level) {
  let current = pixels;
  let currentSize = Math.max(1, Math.trunc(Number(size) || 0));
  for (let step = 0; step < Math.max(0, Math.trunc(Number(level) || 0)); step += 1) {
    const nextSize = Math.max(1, currentSize >> 1);
    const next = new Uint8Array(nextSize * nextSize * 4);
    for (let y = 0; y < nextSize; y += 1) {
      for (let x = 0; x < nextSize; x += 1) {
        for (let channel = 0; channel < 4; channel += 1) {
          let sum = 0;
          let count = 0;
          for (let dy = 0; dy < 2; dy += 1) {
            for (let dx = 0; dx < 2; dx += 1) {
              const sx = Math.min(currentSize - 1, x * 2 + dx);
              const sy = Math.min(currentSize - 1, y * 2 + dy);
              sum += current[(sy * currentSize + sx) * 4 + channel];
              count += 1;
            }
          }
          next[(y * nextSize + x) * 4 + channel] = Math.round(sum / count);
        }
      }
    }
    current = next;
    currentSize = nextSize;
  }
  return { size: currentSize, pixels: current };
}

/** Top-left pixel of a tile's padded cell inside the atlas. */
export function atlasCellOrigin(tile) {
  const id = Math.max(0, Math.min(ATLAS_CAPACITY - 1, Math.trunc(Number(tile)) || 0));
  return { x: (id % ATLAS_COLUMNS) * ATLAS_TILE_STRIDE, y: Math.floor(id / ATLAS_COLUMNS) * ATLAS_TILE_STRIDE };
}

/** Inner UV rect of a tile, inset by the gutter so filtering stays inside it. */
export function atlasTileUV(tile) {
  const { x, y } = atlasCellOrigin(tile);
  return [
    (x + ATLAS_TILE_GUTTER) / ATLAS_WIDTH,
    (y + ATLAS_TILE_GUTTER) / ATLAS_HEIGHT,
    (x + ATLAS_TILE_GUTTER + ATLAS_TILE_SIZE) / ATLAS_WIDTH,
    (y + ATLAS_TILE_GUTTER + ATLAS_TILE_SIZE) / ATLAS_HEIGHT,
  ];
}

/**
 * Default per-channel tolerance for a mip readback comparison. Mip filtering
 * and the RGBA8 round trip both round, so an exact match is not expected; two
 * levels is well below any visible material difference.
 */
export const ATLAS_MIPMAP_TOLERANCE = 2;

/**
 * Foreign Tile Contamination verdict. `observed` is a cell read back from the
 * full atlas at one mip level, and `reference` is the same cell read back from
 * an isolated copy of that tile alone. If any texel differs beyond the
 * tolerance, another tile's material reached into this one, which is exactly
 * the defect the gutter exists to prevent.
 */
export function foreignTileContamination(observed, reference, tolerance = ATLAS_MIPMAP_TOLERANCE) {
  if (observed === null || observed === undefined) return true;
  if (reference === null || reference === undefined) return true;
  const observedSize = Number(observed.size);
  const referenceSize = Number(reference.size);
  if (!Number.isInteger(observedSize) || observedSize < 1) return true;
  if (observedSize !== referenceSize) return true;
  const observedPixels = observed.pixels;
  const referencePixels = reference.pixels;
  const count = observedSize * observedSize * 4;
  if (!observedPixels || !referencePixels) return true;
  if (observedPixels.length < count || referencePixels.length < count) return true;
  for (let index = 0; index < count; index += 1) {
    if (Math.abs(observedPixels[index] - referencePixels[index]) > tolerance) return true;
  }
  return false;
}

/** Largest per-channel difference between two same-sized RGBA readbacks. */
export function maxChannelDelta(observed, reference) {
  const count = observed.length;
  let worst = 0;
  for (let index = 0; index < count; index += 1) {
    const delta = Math.abs(observed[index] - reference[index]);
    if (delta > worst) worst = delta;
  }
  return worst;
}

/**
 * Certify that every mip level the renderer can select matches the isolated
 * tile. An unprobed or unusable level is treated as unsafe, so adding a level
 * without measuring it can never silently enable mipmaps.
 */
export function isAtlasMipmapSafe(pairs, tolerance = ATLAS_MIPMAP_TOLERANCE) {
  if (!Array.isArray(pairs) || pairs.length === 0) return false;
  return pairs.every((pair) => foreignTileContamination(pair?.observed, pair?.reference, tolerance) === false);
}

const ATLAS_TINT_BLOCKS = Object.freeze({
  21: 3,
  22: 5,
  36: 22,
  37: 23,
});

/**
 * The procedural high-definition pass. It replaces the authored 16x16 pixel
 * patterns for terrain and entity tiles; the item atlas keeps the pixel pass in
 * `TEXTURE_PASS`, because item icons are drawn as deliberate pixel art.
 */
export const ATLAS_TEXTURE_PASS = Object.freeze({
  id: "procedural-hd-pass-v1",
  source: "material-painters",
  tileSize: ATLAS_TILE_SIZE,
});

// Shared palettes. A texture that embeds another material (an ore in stone,
// turf over soil) reuses that material's palette and seed, so the stone around
// a coal seam is exactly the stone next to it and a grass side's soil is exactly
// the dirt block below it.
const STONE_PALETTE = Object.freeze({ base: "#7d8183", light: "#a4a8a7", dark: "#54585a", crack: "#3a3e40" });
const DIRT_PALETTE = Object.freeze({
  base: "#6e4f37", light: "#8d6a4b", dark: "#472f20",
  pebble: "#6c6358", pebbleLight: "#877e70", pebbleDark: "#453e36",
});
const GRASS_PALETTE = Object.freeze({
  deep: "#2a4a1f", dark: "#3c6a2c", base: "#52863a", light: "#6d9f47", tip: "#8cb85b", dry: "#a7a35c",
});
const PLANK_PALETTE = Object.freeze({
  wood: "#9a6a3c", woodDark: "#4f341d", woodLight: "#c08a55", seam: "#2a1a0e",
  iron: "#5d6164", ironDark: "#2c2e30", ironLight: "#a5aaad",
});
const DOOR_PALETTE = Object.freeze({
  wood: "#8f633d", woodDark: "#4f3320", woodLight: "#b3804f", seam: "#2e1e13",
  glass: "#9fc9d6", glassDark: "#5f8fa0", glassLight: "#e2f4f8",
  iron: "#5a5d60", ironDark: "#2a2c2e", ironLight: "#9da2a5",
  void: "#120d0a", voidLight: "#3a2c22",
});
const STONE_SEED = materialSeed("stone");
const DIRT_SEED = materialSeed("dirt");
const ORE_OPTIONS = Object.freeze({ stone: STONE_PALETTE, stoneSeed: STONE_SEED });

function crop(stage, palette) {
  return { painter: "crop", options: { stage }, palette };
}

// One descriptor per atlas tile, in block-id order for tiles 0-29. `painter`
// names an entry in MATERIAL_PAINTERS; `palette` holds the colours it reads.
const BLOCK_TEXTURE_SPECS = [
  { painter: "sand", palette: { base: "#dfe9ee", light: "#f7fbfc", dark: "#b9cbd4", speckLight: "#ffffff", speckDark: "#a9bcc6" } },
  { painter: "stone", palette: STONE_PALETTE },
  { painter: "dirt", palette: DIRT_PALETTE },
  { painter: "grass_side", palette: GRASS_PALETTE, options: { soil: DIRT_PALETTE, soilSeed: DIRT_SEED } },
  { painter: "leaves", palette: { deep: "#0f2a14", dark: "#1f4a22", base: "#2f6b2e", light: "#4f8f3c", vein: "#1c3f1d" } },
  { painter: "bark", palette: { deep: "#24180f", dark: "#43301f", base: "#5f4430", light: "#7e5e42" } },
  { painter: "sand", palette: { base: "#d6c08a", light: "#ead9a9", dark: "#b59b64", speckLight: "#f6edd4", speckDark: "#8a744f" } },
  { painter: "water", palette: { deep: "#1d5a82", base: "#2f7fa8", light: "#72bcd3" }, opacity: 0.78 },
  { painter: "ore", palette: { ore: "#2c2d30", oreLight: "#666a70", oreDark: "#111214", rim: "#3a3d3f", glint: "#a9afb5" }, options: { ...ORE_OPTIONS, clusters: 5, facets: 5, scale: 1.1 } },
  { painter: "ore", palette: { ore: "#c99b74", oreLight: "#ecc9a5", oreDark: "#8a5a38", rim: "#5b5250", glint: "#fff0dc" }, options: { ...ORE_OPTIONS, clusters: 4 } },
  { painter: "ore", palette: { ore: "#3fcfd0", oreLight: "#b8fff8", oreDark: "#127b86", rim: "#2c4b52", glint: "#ffffff" }, options: { ...ORE_OPTIONS, clusters: 3, facets: 6, scale: 0.9 } },
  {
    painter: "furnace",
    palette: {
      base: "#7a7e80", light: "#a0a4a4", dark: "#4d5153", mortar: "#323638",
      void: "#140f0d", iron: "#3d4144", ember: "#e0641c", emberDark: "#6a1d0a", emberHot: "#ffc45a",
    },
  },
  {
    painter: "torch",
    palette: {
      wall: "#4a3a2c", wallDark: "#2a2019", glow: "#ffb35a",
      wood: "#7a5230", woodDark: "#3e2715", woodLight: "#a8784a",
      flame: "#ff9a2a", flameEdge: "#d2401a", flameHot: "#ffd65c", flameCore: "#fff6d8",
    },
  },
  {
    painter: "bed",
    palette: {
      cloth: "#b3363f", clothDark: "#6e1d24", clothLight: "#d9585c", pillow: "#f2eee6", pillowDark: "#b9b2a6",
      wood: "#8c5f3a", woodDark: "#4a2f1b", woodLight: "#b07b4d", shadow: "#1d1410",
    },
  },
  { painter: "door", palette: DOOR_PALETTE, options: { open: false } },
  { painter: "door", palette: DOOR_PALETTE, options: { open: true } },
  crop(0, {
    soil: "#3a2a1c", gap: "#30441f", stalk: "#4f8a32", stalkDark: "#2c5520", stalkLight: "#80bd4e",
    grain: "#7aa83e", grainDark: "#4a7026", grainLight: "#a5cf62",
  }),
  crop(1, {
    soil: "#3a2a1c", gap: "#374a21", stalk: "#62983a", stalkDark: "#355e22", stalkLight: "#9ccb58",
    grain: "#8cb246", grainDark: "#5a7a2a", grainLight: "#bddb70",
  }),
  crop(2, {
    soil: "#3a2a1c", gap: "#4d4c22", stalk: "#9ea43e", stalkDark: "#5f6a24", stalkLight: "#cfd064",
    grain: "#c3b14a", grainDark: "#7d6f2a", grainLight: "#e6d77c",
  }),
  crop(3, {
    soil: "#3a2a1c", gap: "#5c4b24", stalk: "#c29c3c", stalkDark: "#7a5e22", stalkLight: "#e4c66a",
    grain: "#dab34f", grainDark: "#9c7a2c", grainLight: "#f6de8c",
  }),
  { painter: "farmland", palette: { base: "#4a3322", light: "#69492f", dark: "#2a1b11" } },
  { painter: "grass_top", palette: GRASS_PALETTE },
  { painter: "wood_rings", palette: { ring: "#6e4a2a", dark: "#9a7045", base: "#b8895a", light: "#d2a877", bark: "#5f4430", barkDark: "#2c1e13" } },
  { painter: "lava", palette: { crust: "#2a0a04", dark: "#8a1f08", base: "#e0561a", hot: "#ffaa30", white: "#fff0a0" } },
  { painter: "fire", palette: { smoke: "#3a0e06", dark: "#a0260c", base: "#ef6a1e", hot: "#ffc040", white: "#fff4c4" }, opacity: 0.78 },
  { painter: "cobblestone", palette: { base: "#7a7e7f", light: "#a6a9a8", dark: "#4d5152", mortar: "#2a2d2e", warm: "#8c8172" } },
  { painter: "obsidian", palette: { dark: "#0b0812", base: "#1d1530", light: "#3b2c5e", sheen: "#7d68b8" } },
  { painter: "glass", palette: { base: "#bfe0ea", light: "#f3fbfd", dark: "#8ab7c7", frame: "#eaf6fa", edge: "#7fa9b8" } },
  {
    painter: "chest",
    palette: { ...PLANK_PALETTE, latch: "#c9a04a", latchDark: "#6f5420", latchLight: "#f3d88a", shadow: "#140e08" },
  },
  { painter: "crafting_table", palette: { ...PLANK_PALETTE, wood: "#94643a", top: "#b88552" } },
];

const BLOCK_TEXTURE_NAMES = [
  "air",
  "stone",
  "dirt",
  "grass",
  "leaves",
  "wood",
  "sand",
  "water",
  "coal_ore",
  "iron_ore",
  "diamond_ore",
  "furnace",
  "torch",
  "bed",
  "closed_door",
  "open_door",
  "wheat_crop",
  "growing_wheat",
  "ripe_wheat",
  "mature_wheat",
  "farmland",
  "grass_top",
  "wood_top",
  "lava",
  "fire",
  "cobblestone",
  "obsidian",
  "glass",
  "chest",
  "crafting_table",
];

// Variants reuse their base material's painter and palette with a different
// seed, so a variant is the same material laid out differently.
const VARIANT_BASES = Object.freeze([1, 2, 3, 4, 5, 6, 25, 26, 21, 7]);
const VARIANT_TEXTURE_NAMES = [
  "stone_variant", "dirt_variant", "grass_variant", "leaves_variant", "wood_variant",
  "sand_variant", "cobblestone_variant", "obsidian_variant", "grass_top_variant", "water_variant",
];
const VARIANT_TEXTURE_SPECS = VARIANT_BASES.map((base) => BLOCK_TEXTURE_SPECS[base]);

const ENTITY_TEXTURE_NAMES = [
  "zombie_skin", "zombie_shirt", "zombie_pants", "pig_skin", "pig_snout",
  "villager_skin", "villager_robe_green", "villager_robe_brown", "entity_eye", "player_sleeve",
  "cow_hide", "cow_snout", "cow_face", "sheep_wool", "sheep_face", "chicken_feather", "chicken_beak",
];

const ENTITY_TEXTURE_SPECS = [
  { painter: "skin", palette: { base: "#6fa45b", light: "#9dca76", dark: "#3f6f4a" } },
  { painter: "fabric", palette: { base: "#2d777c", light: "#55a6a3", dark: "#1f4c5a", trim: "#82d0c3" } },
  { painter: "fabric", palette: { base: "#3f4f83", light: "#6377ad", dark: "#27345d" }, options: { threads: 40 } },
  { painter: "skin", palette: { base: "#dda18f", light: "#f2c5ae", dark: "#a96867" } },
  { painter: "skin", palette: { base: "#c57473", light: "#e7a0a0", dark: "#8c4c56" }, options: { nostrils: true } },
  { painter: "skin", palette: { base: "#bf865e", light: "#dda27a", dark: "#8d5748" } },
  { painter: "fabric", palette: { base: "#477a4b", light: "#6fa45d", dark: "#2d5039", trim: "#a0c97e" } },
  { painter: "fabric", palette: { base: "#8b623d", light: "#b27d4e", dark: "#5c3e2c", trim: "#d19a5f" } },
  { painter: "eye", palette: { base: "#2a3132", light: "#6b7572", dark: "#080b0c", glint: "#dcefe2" } },
  { painter: "fabric", palette: { base: "#3a6a9f", light: "#5e91c4", dark: "#25476e", trim: "#9ac7e8" } },
  // Farm animals. Each one owns its own hide, because a cow painted in the pig's
  // pink is a pig wearing a cow's silhouette - the same mistake as the missing
  // brute model, one layer down.
  { painter: "skin", palette: { base: "#7a5236", light: "#a3744f", dark: "#4a3122" } },
  { painter: "skin", palette: { base: "#e0a79c", light: "#f3c9bf", dark: "#a9736d" }, options: { nostrils: true } },
  { painter: "skin", palette: { base: "#e6e1d2", light: "#fbf8ef", dark: "#b0a997" } },
  { painter: "fabric", palette: { base: "#ece8dc", light: "#fdfbf4", dark: "#bcb7a7", trim: "#d8d3c3" } },
  { painter: "skin", palette: { base: "#cfc2ad", light: "#eee3d2", dark: "#9c8f7b" } },
  { painter: "fabric", palette: { base: "#f4f2ec", light: "#ffffff", dark: "#cbc7bc", trim: "#e2ded2" } },
  { painter: "skin", palette: { base: "#e8a53a", light: "#f7cd77", dark: "#a86f1c" } },
];

function freezeBlockTexture(spec, id, name = BLOCK_TEXTURE_NAMES[id]) {
  return Object.freeze({
    id,
    name,
    painter: spec.painter,
    palette: Object.freeze({ ...spec.palette }),
    options: Object.freeze({ ...(spec.options ?? {}) }),
    opacity: spec.opacity ?? 1,
    seed: materialSeed(name),
    pass: ATLAS_TEXTURE_PASS.id,
    tile: Object.freeze({
      column: id % ATLAS_COLUMNS,
      row: Math.floor(id / ATLAS_COLUMNS),
    }),
  });
}

export const BLOCK_TEXTURES = Object.freeze(BLOCK_TEXTURE_SPECS.map((spec, id) => freezeBlockTexture(spec, id)));
export const VARIANT_TEXTURES = Object.freeze(
  VARIANT_TEXTURE_SPECS.map((spec, index) => freezeBlockTexture(spec, 30 + index, VARIANT_TEXTURE_NAMES[index])),
);
export const ENTITY_TEXTURES = Object.freeze(
  ENTITY_TEXTURE_SPECS.map((spec, index) => freezeBlockTexture(spec, 40 + index, ENTITY_TEXTURE_NAMES[index])),
);
export const ENTITY_TEXTURE_TILES = Object.freeze({
  zombieSkin: 40,
  zombieShirt: 41,
  zombiePants: 42,
  pigSkin: 43,
  pigSnout: 44,
  villagerSkin: 45,
  villagerRobeGreen: 46,
  villagerRobeBrown: 47,
  eye: 48,
  playerSleeve: 49,
  cowHide: 50,
  cowSnout: 51,
  cowFace: 52,
  sheepWool: 53,
  sheepFace: 54,
  chickenFeather: 55,
  chickenBeak: 56,
});
export const ATLAS_TEXTURES = Object.freeze([...BLOCK_TEXTURES, ...VARIANT_TEXTURES, ...ENTITY_TEXTURES]);
const ATLAS_SOURCE_CANVASES = new WeakMap();
export const BLOCK_TEXTURES_BY_ID = Object.freeze(
  Object.fromEntries(BLOCK_TEXTURES.map((texture) => [texture.id, texture])),
);
const BLOCK_TEXTURES_BY_NAME = Object.freeze(
  Object.fromEntries(BLOCK_TEXTURES.map((texture) => [texture.name, texture])),
);

for (const texture of ATLAS_TEXTURES) {
  if (MATERIAL_PAINTERS[texture.painter] === undefined) {
    throw new Error(`Atlas texture ${texture.name} names unknown painter ${texture.painter}.`);
  }
}

function numericBlockId(value) {
  if (typeof value === "bigint") {
    if (value < 0n || value >= BigInt(BLOCK_TEXTURES.length)) return null;
    return Number(value);
  }
  if (!Number.isInteger(value) || value < 0 || value >= BLOCK_TEXTURES.length) return null;
  return value;
}

/** Return the immutable descriptor for a block, or null for an unknown block. */
export function blockTexture(value) {
  const numeric = numericBlockId(value);
  if (numeric !== null) return BLOCK_TEXTURES[numeric];
  if (typeof value === "string") return BLOCK_TEXTURES_BY_NAME[value] ?? null;
  if (value === null || typeof value !== "object") return null;
  if (Object.prototype.hasOwnProperty.call(value, "name")) return blockTexture(value.name);
  if (Object.prototype.hasOwnProperty.call(value, "block")) return blockTexture(value.block);
  if (Object.prototype.hasOwnProperty.call(value, "id")) return blockTexture(value.id);
  return null;
}

export function atlasTile(block) {
  const id = Math.max(0, Math.min(ATLAS_TEXTURES.length - 1, Number(block) || 0));
  return { column: id % ATLAS_COLUMNS, row: Math.floor(id / ATLAS_COLUMNS) };
}

// Face-aware tile: 0 is +Y (top), 1 is -Y (bottom), 2..5 are the sides.
export function blockFaceTile(block, faceIndex) {
  const id = Number(block) || 0;
  if (id === 3) {
    if (faceIndex === 0) return 21;
    if (faceIndex === 1) return 2;
    return 3;
  }
  if (id === 5 && (faceIndex === 0 || faceIndex === 1)) return 22;
  if (id === 21) return 23;
  if (id === 22) return 25;
  if (id === 23) return 26;
  if (id === 25) return 27;
  if (id === 26) return 28;
  if (id === 27) return 29;
  return Math.max(0, Math.min(ATLAS_TEXTURES.length - 1, id));
}

function variantParity(x, z) {
  return ((Math.trunc(Number(x)) * 31 + Math.trunc(Number(z)) * 17) % 2 + 2) % 2;
}

function pickVariant(base, variant, x, z) {
  return variantParity(x, z) === 0 ? base : variant;
}

export function blockFaceTileAt(block, faceIndex, x = 0, z = 0) {
  const id = Number(block) || 0;
  if (id === 1) return 1;
  if (id === 2) return 2;
  if (id === 3) {
    if (faceIndex === 0) return 21;
    if (faceIndex === 1) return 2;
    return 3;
  }
  if (id === 4) return 4;
  if (id === 5) return faceIndex === 0 || faceIndex === 1 ? 22 : 5;
  if (id === 6) return 6;
  if (id === 7) return 7;
  if (id === 22) return pickVariant(25, 36, x, z);
  if (id === 23) return pickVariant(26, 37, x, z);
  if (id === 25) return 27;
  if (id === 26) return 28;
  if (id === 27) return 29;
  return blockFaceTile(id, faceIndex);
}

// `atlasUV` takes an atlas tile slot, which is what `blockFaceTileAt` returns
// and what `atlasTile` already resolves.
export function atlasUV(tile) {
  const [u0, v0, u1, v1] = atlasTileUV(tile);
  return [u0, v0, u1, v0, u1, v1, u0, v1];
}

function colorLuminance(color) {
  const match = /^#([0-9a-f]{6})$/i.exec(color);
  if (match === null) return 0;
  const value = Number.parseInt(match[1], 16);
  const red = (value >> 16) & 0xff;
  const green = (value >> 8) & 0xff;
  const blue = value & 0xff;
  return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
}

function hexBytes(color) {
  const value = Number.parseInt(String(color).slice(1), 16);
  return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

function paletteEdgeColors(palette) {
  const colors = Object.values(palette).filter((color) => typeof color === "string");
  if (colors.length === 0) return { highlight: "#ffffff", shadow: "#000000" };
  return {
    highlight: colors.reduce((best, color) => colorLuminance(color) > colorLuminance(best) ? color : best),
    shadow: colors.reduce((best, color) => colorLuminance(color) < colorLuminance(best) ? color : best),
  };
}

// Painting a tile is the expensive part of an atlas build, and the game builds
// the atlas more than once (the WebGL upload, the mip certification copy, the
// first-person view, the WebGPU path). The pixels are a pure function of the
// descriptor, so each tile is synthesised once per page and reused.
const TILE_PIXEL_CACHE = new Map();

/** RGBA bytes of one atlas tile, synthesised on first use. */
export function atlasTilePixels(tile) {
  const texture = ATLAS_TEXTURES[tile];
  if (texture === undefined) return null;
  let pixels = TILE_PIXEL_CACHE.get(texture.id);
  if (pixels === undefined) {
    pixels = paintMaterial(texture.painter, ATLAS_TILE_SIZE, texture.seed, texture.palette, {
      opacity: texture.opacity,
      options: texture.options,
    });
    TILE_PIXEL_CACHE.set(texture.id, pixels);
  }
  return pixels;
}

/** Source-over of one colour at `alpha` onto an RGBA texel. */
function blendOver(data, offset, rgb, alpha) {
  const backdropAlpha = data[offset + 3] / 255;
  const outAlpha = alpha + backdropAlpha * (1 - alpha);
  if (outAlpha <= 0) return;
  for (let channel = 0; channel < 3; channel += 1) {
    data[offset + channel] = (rgb[channel] * alpha + data[offset + channel] * backdropAlpha * (1 - alpha)) / outAlpha;
  }
  data[offset + 3] = outAlpha * 255;
}

// A composed cell is a function of the tile and its tint, and the game tints
// with one fixed colour table, so a cell is composed once and reused.
const CELL_PIXEL_CACHE = new Map();

/**
 * The full padded cell of one tile, `ATLAS_TILE_STRIDE` square: the painted
 * tile, its faint edge lighting and outline, the block-colour tint, and the
 * gutter filled from the tile's own edge texels.
 *
 * Everything is composed in memory and uploaded with a single putImageData.
 * The previous path bled each gutter with drawImage from the atlas canvas onto
 * itself, and a self-draw copies the whole canvas: eight full-canvas copies per
 * tile, which at 2048x2048 costs seconds on a software-rasterised canvas.
 */
export function atlasCellPixels(tile, tint = null) {
  const texture = ATLAS_TEXTURES[tile];
  if (texture === undefined) return null;
  const key = `${texture.id}:${tint === null || tint === undefined ? "none" : tint.join(",")}`;
  const cached = CELL_PIXEL_CACHE.get(key);
  if (cached !== undefined) return cached;

  const size = ATLAS_TILE_SIZE;
  const tilePixels = new Uint8ClampedArray(atlasTilePixels(tile));
  const { highlight, shadow } = paletteEdgeColors(texture.palette);
  const highlightRgb = hexBytes(highlight);
  const shadowRgb = hexBytes(shadow);
  const at = (x, y) => (y * size + x) * 4;
  // Edge lighting: a lit top and left edge, a shaded bottom and right edge.
  for (let x = 0; x < size; x += 1) blendOver(tilePixels, at(x, 0), highlightRgb, TEXTURE_PASS.edgeHighlightAlpha);
  for (let y = 1; y < size - 1; y += 1) blendOver(tilePixels, at(0, y), highlightRgb, TEXTURE_PASS.edgeHighlightAlpha);
  for (let x = 0; x < size; x += 1) blendOver(tilePixels, at(x, size - 1), shadowRgb, TEXTURE_PASS.edgeShadowAlpha);
  for (let y = 1; y < size - 1; y += 1) blendOver(tilePixels, at(size - 1, y), shadowRgb, TEXTURE_PASS.edgeShadowAlpha);
  // The one-texel outline ring.
  const outline = /rgba?\(([^)]+)\)/.exec(TEXTURE_PASS.outline)[1].split(",").map(Number);
  const outlineAlpha = outline[3] ?? 1;
  for (let index = 0; index < size; index += 1) {
    blendOver(tilePixels, at(index, 0), outline, outlineAlpha);
    blendOver(tilePixels, at(index, size - 1), outline, outlineAlpha);
    if (index > 0 && index < size - 1) {
      blendOver(tilePixels, at(0, index), outline, outlineAlpha);
      blendOver(tilePixels, at(size - 1, index), outline, outlineAlpha);
    }
  }
  // A faint multiply toward the block's reported colour.
  if (tint !== null && tint !== undefined) {
    const strength = 0.08;
    for (let offset = 0; offset < tilePixels.length; offset += 4) {
      for (let channel = 0; channel < 3; channel += 1) {
        const factor = Math.max(0, Math.min(1, Number(tint[channel]) || 0));
        tilePixels[offset + channel] *= 1 - strength + strength * factor;
      }
    }
  }

  // Bleed the tile's own edge texels across its gutter, corners included, so
  // no mip level can average this tile with a transparent gap or a neighbour.
  const stride = ATLAS_TILE_STRIDE;
  const gutter = ATLAS_TILE_GUTTER;
  const cell = new Uint8ClampedArray(stride * stride * 4);
  for (let y = 0; y < stride; y += 1) {
    const sourceY = Math.max(0, Math.min(size - 1, y - gutter));
    for (let x = 0; x < stride; x += 1) {
      const sourceX = Math.max(0, Math.min(size - 1, x - gutter));
      const from = (sourceY * size + sourceX) * 4;
      const to = (y * stride + x) * 4;
      cell[to] = tilePixels[from];
      cell[to + 1] = tilePixels[from + 1];
      cell[to + 2] = tilePixels[from + 2];
      cell[to + 3] = tilePixels[from + 3];
    }
  }
  CELL_PIXEL_CACHE.set(key, cell);
  return cell;
}

function putCell(context, tile, tint) {
  const { x, y } = atlasCellOrigin(tile);
  const image = context.createImageData(ATLAS_TILE_STRIDE, ATLAS_TILE_STRIDE);
  // putImageData ignores globalAlpha and compositing by specification, so a
  // translucent tile (water, fire) carries its opacity in its own alpha.
  image.data.set(atlasCellPixels(tile, tint));
  context.putImageData(image, x, y);
}

export function createAtlasCanvas(blockColors) {
  const canvas = document.createElement("canvas");
  canvas.width = ATLAS_WIDTH;
  canvas.height = ATLAS_HEIGHT;
  const context = canvas.getContext("2d");
  if (context === null) throw new Error("2D canvas is required to create the texture atlas.");

  context.imageSmoothingEnabled = false;
  const tintFor = (tile) => blockColors?.[ATLAS_TINT_BLOCKS[tile] ?? tile] ?? null;
  for (let tile = 0; tile < ATLAS_CAPACITY; tile += 1) {
    if (ATLAS_TEXTURES[tile] === undefined) {
      const { x, y } = atlasCellOrigin(tile);
      context.clearRect(x, y, ATLAS_TILE_STRIDE, ATLAS_TILE_STRIDE);
      continue;
    }
    putCell(context, tile, tintFor(tile));
  }
  // Some Chromium canvas-to-WebGL uploads can expose the first six source
  // tiles as transparent even though the initial draw painted them. Repaint
  // those common blocks immediately before upload.
  for (let tile = 0; tile < 6; tile += 1) putCell(context, tile, tintFor(tile));
  return canvas;
}

export function createTextureAtlas(gl, blockColors, { mipmaps = false, mipmapSafe = false } = {}) {
  const canvas = createAtlasCanvas(blockColors);
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, canvas);
  // Mipmaps only run once the padded atlas has been certified free of foreign
  // tile contamination; an unproven atlas keeps the deterministic LINEAR path.
  const hasMipmaps = mipmaps && mipmapSafe && typeof gl.generateMipmap === "function";
  const minFilter = hasMipmaps && gl.LINEAR_MIPMAP_LINEAR !== undefined
    ? gl.LINEAR_MIPMAP_LINEAR
    : gl.LINEAR;
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, minFilter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  if (hasMipmaps) gl.generateMipmap(gl.TEXTURE_2D);
  const anisotropy = typeof gl.getExtension === "function"
    ? gl.getExtension("EXT_texture_filter_anisotropic")
    : null;
  if (anisotropy && typeof gl.texParameterf === "function") {
    const maximum = typeof gl.getParameter === "function"
      ? Number(gl.getParameter(anisotropy.MAX_TEXTURE_MAX_ANISOTROPY_EXT))
      : 1;
    // Detailed tiles alias along grazing ground far sooner than flat ones, so
    // the anisotropy ceiling follows the hardware up to 8x.
    gl.texParameterf(gl.TEXTURE_2D, anisotropy.TEXTURE_MAX_ANISOTROPY_EXT, Math.min(8, maximum));
  }
  ATLAS_SOURCE_CANVASES.set(texture, canvas);
  gl.bindTexture(gl.TEXTURE_2D, null);
  return texture;
}

export function atlasSourceCanvas(texture) {
  return ATLAS_SOURCE_CANVASES.get(texture) ?? null;
}
