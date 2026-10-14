import assert from "node:assert/strict";
import {
  atlasMipLevelGeometry,
  atlasUV,
  atlasCellOrigin,
  atlasTile,
  blockFaceTile,
  ATLAS_COLUMNS,
  ATLAS_ROWS,
  ATLAS_CAPACITY,
  ATLAS_MIPMAP_SAFE_LEVELS,
  ATLAS_TILE_GUTTER,
  ATLAS_TILE_SIZE,
  ATLAS_TILE_STRIDE,
  ATLAS_WIDTH,
  ATLAS_HEIGHT,
  BLOCK_TEXTURES,
  ATLAS_TEXTURES,
  ENTITY_TEXTURES,
  ENTITY_TEXTURE_TILES,
  VARIANT_TEXTURES,
  TEXTURE_PASS,
  ATLAS_TEXTURE_PASS,
  atlasTilePixels,
  atlasCellPixels,
  blockTexture,
  blockFaceTileAt,
  createAtlasCanvas,
  createTextureAtlas,
} from "../web/texture-atlas.js";
import { MATERIAL_PAINTERS } from "../web/material-textures.js";

assert.equal(ATLAS_COLUMNS, 8);
assert.equal(ATLAS_ROWS, 8);
assert.equal(ATLAS_CAPACITY, 64);
assert.equal(ATLAS_TILE_SIZE, 128, "a face up close spans hundreds of pixels, so a 64-texel tile smeared into soft cells");
assert.ok(ATLAS_TILE_GUTTER > 0, "each tile must own padding so the mip chain cannot blend materials");
assert.equal(ATLAS_TILE_STRIDE, ATLAS_TILE_SIZE + 2 * ATLAS_TILE_GUTTER);
assert.equal(ATLAS_WIDTH, 2048, "the padded terrain atlas must remain power-of-two for mipmaps");
assert.equal(ATLAS_HEIGHT, 2048, "the padded terrain atlas must remain power-of-two for mipmaps");
assert.deepEqual([...ATLAS_MIPMAP_SAFE_LEVELS], [1, 2, 3, 4, 5, 6], "a 64-texel gutter certifies through level 6");
// Every certified mip level has to be backed by its own padding, or the chain
// blends a tile into its neighbour at a level the shader is allowed to sample.
for (const level of ATLAS_MIPMAP_SAFE_LEVELS) {
  const geometry = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, level);
  assert.ok(
    geometry.padding >= 1,
    `mip level ${level} leaves no padding, so a tile would blend into its neighbour`,
  );
  assert.ok(
    geometry.interior >= 1,
    `mip level ${level} shrinks the tile below a pixel`,
  );
}
// The chain must stop at the last level that still has both padding and more
// than one interior texel, and must not certify a level past it.
const lastCertified = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, ATLAS_MIPMAP_SAFE_LEVELS.at(-1));
assert.ok(lastCertified.interior >= 2 && lastCertified.padding >= 1,
  "the last certified level must still keep a tile and its padding apart");
const nextLevel = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, ATLAS_MIPMAP_SAFE_LEVELS.at(-1) + 1);
assert.ok(nextLevel.interior < 2 || nextLevel.padding < 1,
  "the level past the certified range must genuinely be unusable");
assert.equal(TEXTURE_PASS.id, "fallback-pixel-pass-v1");
assert.equal(TEXTURE_PASS.referenceSheet, null);
assert.equal(TEXTURE_PASS.gridSize, 8);
assert.equal(TEXTURE_PASS.blockGridSize, 16);
assert.ok(Object.isFrozen(TEXTURE_PASS));
assert.equal(TEXTURE_PASS.edgeHighlightAlpha, 0.05, "tile highlights should remain material detail, not a wireframe");
assert.equal(TEXTURE_PASS.edgeShadowAlpha, 0.06, "tile shadows should remain material detail, not a wireframe");
assert.equal(TEXTURE_PASS.outline, "rgba(19, 27, 28, 0.05)");
assert.ok(TEXTURE_PASS.noiseHighlightAlpha <= 0.06, "texture grain should stay subtle");
assert.ok(TEXTURE_PASS.noiseShadowAlpha <= 0.04, "texture grain should stay subtle");
assert.equal(BLOCK_TEXTURES.length, 30);
assert.equal(ATLAS_TEXTURE_PASS.id, "procedural-hd-pass-v1");
assert.equal(ATLAS_TEXTURE_PASS.tileSize, ATLAS_TILE_SIZE);
assert.ok(Object.isFrozen(ATLAS_TEXTURE_PASS));
assert.equal(VARIANT_TEXTURES.length, 10);
assert.equal(ENTITY_TEXTURES.length, 17);
assert.equal(blockTexture(1), BLOCK_TEXTURES[1]);
assert.equal(blockTexture({ id: 1 }), BLOCK_TEXTURES[1]);
assert.equal(blockTexture("stone"), BLOCK_TEXTURES[1]);
assert.equal(blockTexture("unknown"), null);
assert.equal(typeof createAtlasCanvas, "function");
assert.ok(Object.isFrozen(BLOCK_TEXTURES[1]));
assert.ok(Object.isFrozen(BLOCK_TEXTURES[1].palette));
assert.ok(Object.isFrozen(BLOCK_TEXTURES[1].options));
assert.deepEqual(atlasTile(1), { column: 1, row: 0 });
assert.deepEqual(atlasTile(10), { column: 2, row: 1 });
// An id past the last texture clamps onto it rather than pointing off the sheet.
assert.deepEqual(atlasTile(99), atlasTile(ATLAS_TEXTURES.length - 1));

for (const [index, texture] of ENTITY_TEXTURES.entries()) {
  assert.equal(texture.id, 40 + index);
}

// Every farm animal owns a hide, a face and whatever it shows, and each one is a
// distinct material: a cow drawn in the pig's pink reads as a pig.
assert.deepEqual(
  Object.fromEntries(Object.entries(ENTITY_TEXTURE_TILES).map(([name, id]) => [name, ENTITY_TEXTURES[id - 40].name])),
  {
    zombieSkin: "zombie_skin",
    zombieShirt: "zombie_shirt",
    zombiePants: "zombie_pants",
    pigSkin: "pig_skin",
    pigSnout: "pig_snout",
    villagerSkin: "villager_skin",
    villagerRobeGreen: "villager_robe_green",
    villagerRobeBrown: "villager_robe_brown",
    eye: "entity_eye",
    playerSleeve: "player_sleeve",
    cowHide: "cow_hide",
    cowSnout: "cow_snout",
    cowFace: "cow_face",
    sheepWool: "sheep_wool",
    sheepFace: "sheep_face",
    chickenFeather: "chicken_feather",
    chickenBeak: "chicken_beak",
  },
);
const entityMaterialNames = ENTITY_TEXTURES.map((texture) => texture.name);
assert.equal(new Set(entityMaterialNames).size, entityMaterialNames.length, "entity tiles need unique names");
assert.ok(ENTITY_TEXTURES.length + VARIANT_TEXTURES.length + BLOCK_TEXTURES.length <= ATLAS_CAPACITY,
  "the atlas has to hold every tile");

// Every tile is painted by a named material painter, and the descriptor has to
// carry every colour that painter reads.
for (const texture of ATLAS_TEXTURES) {
  const painter = MATERIAL_PAINTERS[texture.painter];
  assert.notEqual(painter, undefined, `${texture.name} names an unknown painter ${texture.painter}`);
  for (const key of painter.palette) {
    assert.match(texture.palette[key] ?? "", /^#[0-9a-f]{6}$/i, `${texture.name} must define palette colour ${key}`);
  }
  assert.equal(texture.pass, ATLAS_TEXTURE_PASS.id);
}
// A variant is the same material laid out differently, not a different one.
for (const [index, base] of [1, 2, 3, 4, 5, 6, 25, 26, 21, 7].entries()) {
  assert.equal(VARIANT_TEXTURES[index].painter, BLOCK_TEXTURES[base].painter);
  assert.notEqual(VARIANT_TEXTURES[index].seed, BLOCK_TEXTURES[base].seed);
}

for (const block of [1, 5, 8, 10, 11, 16, 17, 18, 19]) {
  const uv = atlasUV(block);
  assert.equal(uv.length, 8);
  for (const value of uv) assert.ok(value >= 0 && value <= 1);
}

assert.equal(blockTexture("grass_top").id, 21);
assert.equal(blockTexture("wood_top").id, 22);
assert.equal(blockTexture("lava").id, 23);
assert.equal(blockTexture("fire").id, 24);
assert.equal(blockTexture("cobblestone").id, 25);
assert.equal(blockTexture("obsidian").id, 26);
assert.equal(blockFaceTile(3, 0), 21);
assert.equal(blockFaceTile(3, 1), 2);
assert.equal(blockFaceTile(3, 4), 3);
assert.equal(blockFaceTile(5, 0), 22);
assert.equal(blockFaceTile(5, 1), 22);
assert.equal(blockFaceTile(5, 3), 5);
assert.equal(blockFaceTile(1, 0), 1);
assert.equal(blockFaceTile(7, 0), 7);
assert.equal(blockFaceTile(21, 0), 23);
assert.equal(blockFaceTile(22, 0), 25);
assert.equal(blockFaceTile(23, 0), 26);
// A block id past the last texture clamps onto it, the same way a tile does.
assert.equal(blockFaceTile(99, 0), ATLAS_TEXTURES.length - 1);
assert.equal(blockFaceTileAt(1, 0, 4, 8), 1);
assert.equal(blockFaceTileAt(1, 0, 5, 8), 1);
assert.equal(blockFaceTileAt(2, 0, 4, 8), 2);
assert.equal(blockFaceTileAt(3, 0, 4, 8), 21);
assert.equal(blockFaceTileAt(3, 2, 4, 8), 3);
assert.equal(blockFaceTileAt(4, 2, 4, 8), 4);
assert.equal(blockFaceTileAt(5, 2, 4, 8), 5);
assert.equal(blockFaceTileAt(6, 0, 4, 8), 6);

const fills = [];
const strokes = [];
const draws = [];
const imagePlacements = [];
const context = {
  imageSmoothingEnabled: true,
  fillStyle: "",
  strokeStyle: "",
  globalAlpha: 1,
  globalCompositeOperation: "source-over",
  clearRect(x, y, width, height) {
    fills.push({ x, y, width, height, fillStyle: "", globalAlpha: this.globalAlpha, globalCompositeOperation: this.globalCompositeOperation, cleared: true });
  },
  fillRect(x, y, width, height) {
    fills.push({
      x,
      y,
      width,
      height,
      fillStyle: this.fillStyle,
      globalAlpha: this.globalAlpha,
      globalCompositeOperation: this.globalCompositeOperation,
    });
  },
  strokeRect(x, y, width, height) {
    strokes.push({ x, y, width, height, strokeStyle: this.strokeStyle });
  },
  drawImage(...args) {
    draws.push(args);
  },
  // The atlas painter writes each tile through ImageData so the material
  // surface can be applied per texel, so the stub has to model a real pixel
  // buffer rather than pretend the call did nothing.
  createImageData(width, height) {
    const size = width * height * 4;
    return { width, height, data: new Uint8ClampedArray(size) };
  },
  putImageData(image, x, y) {
    imagePlacements.push({ x, y, width: image.width, height: image.height, image });
  },
};
const canvas = {
  width: 0,
  height: 0,
  getContext(kind) {
    assert.equal(kind, "2d");
    return context;
  },
};
context.canvas = canvas;
const previousDocument = globalThis.document;
const glCalls = [];
const gl = {
  TEXTURE_2D: "TEXTURE_2D",
  RGBA: "RGBA",
  UNSIGNED_BYTE: "UNSIGNED_BYTE",
  UNPACK_FLIP_Y_WEBGL: "UNPACK_FLIP_Y_WEBGL",
  TEXTURE_MIN_FILTER: "TEXTURE_MIN_FILTER",
  TEXTURE_MAG_FILTER: "TEXTURE_MAG_FILTER",
  TEXTURE_WRAP_S: "TEXTURE_WRAP_S",
  TEXTURE_WRAP_T: "TEXTURE_WRAP_T",
  NEAREST: "NEAREST",
  LINEAR: "LINEAR",
  LINEAR_MIPMAP_LINEAR: "LINEAR_MIPMAP_LINEAR",
  CLAMP_TO_EDGE: "CLAMP_TO_EDGE",
  createTexture() {
    return { kind: "texture" };
  },
  bindTexture(...args) {
    glCalls.push(["bindTexture", ...args]);
  },
  pixelStorei(...args) {
    glCalls.push(["pixelStorei", ...args]);
  },
  texImage2D(...args) {
    glCalls.push(["texImage2D", ...args]);
  },
  texParameteri(...args) {
    glCalls.push(["texParameteri", ...args]);
  },
  generateMipmap(...args) {
    glCalls.push(["generateMipmap", ...args]);
  },
  getExtension() {
    return null;
  },
};

try {
  globalThis.document = {
    createElement(kind) {
      assert.equal(kind, "canvas");
      return canvas;
    },
  };
  assert.deepEqual(createTextureAtlas(gl, {
    1: [0.34, 0.38, 0.42],
    7: [0.16, 0.5, 0.82],
  }), { kind: "texture" });
} finally {
  if (previousDocument === undefined) delete globalThis.document;
  else globalThis.document = previousDocument;
}

assert.equal(canvas.width, ATLAS_WIDTH);
assert.equal(canvas.height, ATLAS_HEIGHT);
// Each tile is uploaded as one composed padded cell. A drawImage from the atlas
// canvas onto itself copies the whole canvas, and the old gutter bleed did that
// eight times per tile; that is what made a 2048x2048 atlas cost seconds.
assert.equal(draws.length, 0, "the atlas must not copy itself to fill gutters");
assert.equal(strokes.length, 0);
function cellPlacement(block) {
  const { x, y } = atlasCellOrigin(block);
  return imagePlacements.find((entry) => entry.x === x && entry.y === y && entry.width === ATLAS_TILE_STRIDE) ?? null;
}
for (let block = 0; block < ATLAS_TEXTURES.length; block += 1) {
  const placement = cellPlacement(block);
  assert.ok(placement !== null, `tile ${block} must be uploaded as a full padded cell`);
  assert.equal(placement.height, ATLAS_TILE_STRIDE);
}
// Every tile must bleed its own material into its gutter, otherwise the mip
// chain averages the gap with the neighbouring material.
{
  const cell = cellPlacement(1).image.data;
  const stride = ATLAS_TILE_STRIDE;
  const gutter = ATLAS_TILE_GUTTER;
  const texel = (x, y) => Array.from(cell.slice((y * stride + x) * 4, (y * stride + x) * 4 + 4));
  for (const [gx, gy, ex, ey] of [
    [0, gutter + 10, gutter, gutter + 10],
    [stride - 1, gutter + 10, gutter + ATLAS_TILE_SIZE - 1, gutter + 10],
    [gutter + 10, 0, gutter + 10, gutter],
    [gutter + 10, stride - 1, gutter + 10, gutter + ATLAS_TILE_SIZE - 1],
    [0, 0, gutter, gutter],
    [stride - 1, stride - 1, gutter + ATLAS_TILE_SIZE - 1, gutter + ATLAS_TILE_SIZE - 1],
  ]) {
    assert.deepEqual(texel(gx, gy), texel(ex, ey), `gutter texel ${gx},${gy} must carry the tile's edge texel`);
  }
  for (let index = 3; index < cell.length; index += 4) assert.equal(cell[index], 255, "no transparent texel may remain in an opaque cell");
}
assert.equal(glCalls.filter(([name]) => name === "texImage2D").length, 1);
assert.equal(glCalls.filter(([name]) => name === "pixelStorei").length, 0);
assert.equal(glCalls.filter(([name]) => name === "generateMipmap").length, 0, "packed atlas must not mix neighboring mip levels");
assert.ok(glCalls.some(([name, target, parameter, value]) => (
  name === "texParameteri" && target === "TEXTURE_2D" && parameter === "TEXTURE_MIN_FILTER" && value === "LINEAR"
)));
assert.ok(glCalls.some(([name, target, parameter, value]) => (
  name === "texParameteri" && target === "TEXTURE_2D" && parameter === "TEXTURE_MAG_FILTER" && value === "LINEAR"
)));

// Mipmaps are gated on a proven-clean padded atlas. An uncertified atlas must
// keep the deterministic LINEAR path, and a certified one must build the chain.
function uploadWith(options) {
  glCalls.length = 0;
  return createTextureAtlas(gl, { 1: [0.34, 0.38, 0.42] }, options);
}
function minFilterValue() {
  const call = glCalls.find(([name, , parameter]) => (
    name === "texParameteri" && parameter === "TEXTURE_MIN_FILTER"
  ));
  return call?.[3] ?? null;
}
function mipmapCalls() {
  return glCalls.filter(([name]) => name === "generateMipmap").length;
}

try {
  globalThis.document = {
    createElement(kind) {
      assert.equal(kind, "canvas");
      return canvas;
    },
  };
  uploadWith({ mipmaps: true, mipmapSafe: false });
  assert.equal(mipmapCalls(), 0, "an uncertified atlas must not build a mip chain");
  assert.equal(minFilterValue(), "LINEAR", "an uncertified atlas must stay on the LINEAR fallback");

  uploadWith({ mipmaps: false, mipmapSafe: true });
  assert.equal(mipmapCalls(), 0, "mipmaps stay off when they are not requested");
  assert.equal(minFilterValue(), "LINEAR");

  uploadWith({ mipmaps: true, mipmapSafe: true });
  assert.equal(mipmapCalls(), 1, "a certified atlas must build exactly one mip chain");
  assert.equal(minFilterValue(), "LINEAR_MIPMAP_LINEAR", "a certified atlas must use mip filtering");
  assert.ok(glCalls.some(([name, target, parameter, value]) => (
    name === "texParameteri" && target === "TEXTURE_2D" && parameter === "TEXTURE_WRAP_S" && value === "CLAMP_TO_EDGE"
  )), "the atlas must stay clamped so filtering cannot wrap into another tile");
} finally {
  if (previousDocument === undefined) delete globalThis.document;
  else globalThis.document = previousDocument;
}

// The tile interior of an uploaded cell, as the renderer will sample it.
function tilePixels(block) {
  const placement = cellPlacement(block);
  if (placement === null) return null;
  const out = new Uint8ClampedArray(ATLAS_TILE_SIZE * ATLAS_TILE_SIZE * 4);
  for (let y = 0; y < ATLAS_TILE_SIZE; y += 1) {
    const from = ((y + ATLAS_TILE_GUTTER) * ATLAS_TILE_STRIDE + ATLAS_TILE_GUTTER) * 4;
    out.set(placement.image.data.subarray(from, from + ATLAS_TILE_SIZE * 4), y * ATLAS_TILE_SIZE * 4);
  }
  return out;
}
// The painted surface arrives untouched in the interior; only the one-texel
// edge ring carries the faint edge lighting and outline, and a tint is a small
// multiply rather than a repaint.
{
  const painted = atlasTilePixels(1);
  const untinted = atlasCellPixels(1);
  const stride = ATLAS_TILE_STRIDE;
  const gutter = ATLAS_TILE_GUTTER;
  let interiorDelta = 0;
  let edgeDelta = 0;
  for (let y = 0; y < ATLAS_TILE_SIZE; y += 1) {
    for (let x = 0; x < ATLAS_TILE_SIZE; x += 1) {
      const a = (y * ATLAS_TILE_SIZE + x) * 4;
      const b = ((y + gutter) * stride + x + gutter) * 4;
      const delta = Math.abs(painted[a] - untinted[b]) + Math.abs(painted[a + 1] - untinted[b + 1]);
      const edge = x === 0 || y === 0 || x === ATLAS_TILE_SIZE - 1 || y === ATLAS_TILE_SIZE - 1;
      if (edge) edgeDelta += delta;
      else interiorDelta += delta;
    }
  }
  assert.equal(interiorDelta, 0, "the interior of an untinted cell is exactly the painted tile");
  assert.ok(edgeDelta > 0, "the tile edge must carry its edge lighting");
  assert.ok(edgeDelta / (ATLAS_TILE_SIZE * 4) < 20, "edge lighting must stay a faint detail, not a wireframe");
  const tinted = atlasCellPixels(1, [0, 0, 0]);
  const probe = ((gutter + 40) * stride + gutter + 40) * 4;
  assert.ok(Math.abs(tinted[probe] - untinted[probe] * 0.92) <= 1, "a tint is a faint multiply");
  assert.equal(atlasCellPixels(1), untinted, "composed cells are cached");
}
function parseHex(value) {
  const parsed = Number.parseInt(value.replace("#", ""), 16);
  return [(parsed >> 16) & 0xff, (parsed >> 8) & 0xff, parsed & 0xff];
}
for (const block of [3, 5, 1]) {
  const pixels = tilePixels(block);
  assert.ok(pixels instanceof Uint8ClampedArray, `block ${block} must paint through ImageData`);
  assert.equal(pixels.length, ATLAS_TILE_SIZE * ATLAS_TILE_SIZE * 4);
  // Opaque blocks paint every texel opaque: a hole in the alpha channel would
  // let the gutter bleed into the tile. Water and fire are deliberately
  // translucent, so they are checked separately below.
  if (block !== 7 && block !== 24) {
    for (let index = 3; index < pixels.length; index += 4) {
      assert.equal(pixels[index], 255, `block ${block} must paint every texel opaque`);
    }
  }
}
// The material surface must actually vary the texels, or the tiles are flat.
const stonePixels = tilePixels(1);
const stoneLuma = [];
for (let index = 0; index < stonePixels.length; index += 4) {
  stoneLuma.push(0.2126 * stonePixels[index] + 0.7152 * stonePixels[index + 1] + 0.0722 * stonePixels[index + 2]);
}
const stoneMin = Math.min(...stoneLuma);
const stoneMax = Math.max(...stoneLuma);
assert.ok(stoneMax - stoneMin > 4, `a stone tile must carry surface variation, got ${stoneMax - stoneMin}`);
// The variation stays in the material's own neighbourhood, so a tile never
// drifts to a colour the block does not own.
const stonePalette = Object.values(BLOCK_TEXTURES[1].palette).map(parseHex);
for (let index = 0; index < stonePixels.length; index += 4) {
  const channels = [stonePixels[index], stonePixels[index + 1], stonePixels[index + 2]];
  const nearest = Math.min(...stonePalette.map(([r, g, b]) => (
    Math.abs(channels[0] - r) + Math.abs(channels[1] - g) + Math.abs(channels[2] - b)
  )));
  assert.ok(nearest < 150, `a stone texel ${channels} drifted far from the palette`);
}
// A translucent tile has to keep its translucency. putImageData ignores
// globalAlpha, so the painter bakes the opacity into the alpha channel and this
// is the assertion that stops water silently turning opaque.
const waterPixels = tilePixels(7);
for (let index = 3; index < waterPixels.length; index += 4) {
  assert.ok(
    waterPixels[index] > 150 && waterPixels[index] < 210,
    `a water texel must stay translucent, got alpha ${waterPixels[index]}`,
  );
}
// The old painter scattered 1x1 noise rects; the new one bakes the grain into
// the tile, so the equivalent guarantee is that adjacent texels differ. Without
// it a surface is perfectly smooth and the derivative bump has nothing to read.
for (const block of [3, 7]) {
  const pixels = tilePixels(block);
  let differing = 0;
  for (let y = 0; y < ATLAS_TILE_SIZE; y += 1) {
    for (let x = 1; x < ATLAS_TILE_SIZE; x += 1) {
      const left = (y * ATLAS_TILE_SIZE + x - 1) * 4;
      const right = (y * ATLAS_TILE_SIZE + x) * 4;
      if (pixels[left] !== pixels[right] || pixels[left + 1] !== pixels[right + 1]) differing += 1;
    }
  }
  assert.ok(
    differing > ATLAS_TILE_SIZE * 2,
    `block ${block} must carry per-texel grain, only ${differing} adjacent texel pairs differ`,
  );
}

const signatures = new Set();
for (let block = 0; block < ATLAS_TEXTURES.length; block += 1) {
  const pixels = tilePixels(block);
  assert.ok(pixels instanceof Uint8ClampedArray, `block ${block} must paint through ImageData`);
  signatures.add(Buffer.from(pixels.buffer, pixels.byteOffset, pixels.byteLength).toString("base64"));
}
assert.equal(signatures.size, ATLAS_TEXTURES.length, "every atlas tile should contain a distinct texture");

// ---------------------------------------------------------------------------
// High-definition material contract
// ---------------------------------------------------------------------------

const SIZE = ATLAS_TILE_SIZE;
function luma(pixels, index) {
  return 0.2126 * pixels[index * 4] + 0.7152 * pixels[index * 4 + 1] + 0.0722 * pixels[index * 4 + 2];
}
function meanColor(pixels, rows = [0, SIZE]) {
  const sum = [0, 0, 0];
  let count = 0;
  for (let y = rows[0]; y < rows[1]; y += 1) {
    for (let x = 0; x < SIZE; x += 1) {
      const index = y * SIZE + x;
      for (let channel = 0; channel < 3; channel += 1) sum[channel] += pixels[index * 4 + channel];
      count += 1;
    }
  }
  return sum.map((value) => value / count);
}
function meanLuma(pixels) {
  let total = 0;
  for (let index = 0; index < SIZE * SIZE; index += 1) total += luma(pixels, index);
  return total / (SIZE * SIZE);
}
/** Mean luminance step between texels `distance` apart along one axis. */
function meanStep(pixels, distance, axis = "x") {
  let total = 0;
  let count = 0;
  for (let y = 0; y < SIZE - (axis === "y" ? distance : 0); y += 1) {
    for (let x = 0; x < SIZE - (axis === "x" ? distance : 0); x += 1) {
      const a = y * SIZE + x;
      const b = axis === "x" ? a + distance : a + distance * SIZE;
      total += Math.abs(luma(pixels, a) - luma(pixels, b));
      count += 1;
    }
  }
  return total / count;
}
/** Mean luminance step across the wrap seam, last column to first. */
function seamStep(pixels, axis = "x") {
  let total = 0;
  for (let k = 0; k < SIZE; k += 1) {
    const a = axis === "x" ? k * SIZE + SIZE - 1 : (SIZE - 1) * SIZE + k;
    const b = axis === "x" ? k * SIZE : k;
    total += Math.abs(luma(pixels, a) - luma(pixels, b));
  }
  return total / SIZE;
}

// Determinism: a tile is synthesised once and is a pure function of its
// descriptor, so the texel probe can certify it and it never changes between
// boots.
assert.equal(atlasTilePixels(1), atlasTilePixels(1), "tile pixels must be cached, not repainted per atlas build");
assert.equal(atlasTilePixels(99), null);
assert.equal(atlasTilePixels(1).length, SIZE * SIZE * 4);

// Seamless materials: a ground or wall material is repeated across every block,
// so the step across the wrap seam must look like any other step inside it.
// The edge-lighting bevel is drawn by the atlas on top, not by the painter, so
// the painter output is what this measures.
const TILEABLE_BOTH = [1, 2, 4, 5, 6, 7, 20, 21, 23, 25, 26];
const TILEABLE_X = [3, 16, 17, 18, 19, 24];
for (const tile of [...TILEABLE_BOTH, ...TILEABLE_X]) {
  const pixels = atlasTilePixels(tile);
  const inside = meanStep(pixels, 1, "x");
  const seam = seamStep(pixels, "x");
  assert.ok(seam <= inside * 1.8 + 3, `${ATLAS_TEXTURES[tile].name} shows a vertical seam (${seam.toFixed(1)} vs ${inside.toFixed(1)})`);
  if (TILEABLE_BOTH.includes(tile)) {
    const insideY = meanStep(pixels, 1, "y");
    const seamY = seamStep(pixels, "y");
    assert.ok(seamY <= insideY * 1.8 + 3, `${ATLAS_TEXTURES[tile].name} shows a horizontal seam (${seamY.toFixed(1)} vs ${insideY.toFixed(1)})`);
  }
}

// Resolvable structure, not per-texel noise: in a real material neighbouring
// texels are more alike than texels a few apart. White noise fails this, and
// white noise is exactly what reads as cheap stipple once a tile is magnified.
for (const tile of [1, 2, 3, 4, 5, 6, 21, 22, 25, 26]) {
  const pixels = atlasTilePixels(tile);
  const near = meanStep(pixels, 1, "x");
  const far = meanStep(pixels, 6, "x");
  assert.ok(near < far * 0.8, `${ATLAS_TEXTURES[tile].name} is noise rather than structure (${near.toFixed(1)} vs ${far.toFixed(1)})`);
}

// Materials must carry visible detail but stay within the material's own range.
for (const tile of [1, 2, 3, 4, 5, 6, 8, 9, 10, 21, 25, 26]) {
  const pixels = atlasTilePixels(tile);
  const mean = meanLuma(pixels);
  let variance = 0;
  for (let index = 0; index < SIZE * SIZE; index += 1) variance += (luma(pixels, index) - mean) ** 2;
  const sigma = Math.sqrt(variance / (SIZE * SIZE));
  assert.ok(sigma > 5, `${ATLAS_TEXTURES[tile].name} is flat (sigma ${sigma.toFixed(1)})`);
  assert.ok(sigma < 60, `${ATLAS_TEXTURES[tile].name} is garish (sigma ${sigma.toFixed(1)})`);
}

// Material identity.
const grassTop = meanColor(atlasTilePixels(21));
assert.ok(grassTop[1] > grassTop[0] * 1.2 && grassTop[1] > grassTop[2] * 1.2, "grass top must read green");
const grassSide = atlasTilePixels(3);
const turf = meanColor(grassSide, [0, Math.round(SIZE * 0.1)]);
const soil = meanColor(grassSide, [Math.round(SIZE * 0.5), SIZE]);
assert.ok(turf[1] > turf[0], "the top of a grass side must be turf");
assert.ok(soil[0] > soil[1], "the bottom of a grass side must be soil");
assert.ok(meanLuma(atlasTilePixels(6)) > meanLuma(atlasTilePixels(2)) + 40, "sand must be much lighter than dirt");
assert.ok(meanLuma(atlasTilePixels(26)) < meanLuma(atlasTilePixels(1)) * 0.5, "obsidian must be far darker than stone");
// Cobblestone is individual stones: the mortar between them is a visible share
// of the face, darker than the stones.
const cobble = atlasTilePixels(25);
const cobbleMean = meanLuma(cobble);
let mortar = 0;
for (let index = 0; index < SIZE * SIZE; index += 1) if (luma(cobble, index) < cobbleMean * 0.55) mortar += 1;
assert.ok(mortar > SIZE * SIZE * 0.04, `cobblestone needs mortar between stones (${mortar} dark texels)`);
// An ore is embedded in the same stone as the stone block, so an ore block
// placed next to stone continues it instead of switching to another grey.
const stonePixelsHd = atlasTilePixels(1);
for (const ore of [8, 9, 10]) {
  const pixels = atlasTilePixels(ore);
  let same = 0;
  for (let index = 0; index < SIZE * SIZE * 4; index += 4) {
    if (pixels[index] === stonePixelsHd[index] && pixels[index + 1] === stonePixelsHd[index + 1]
      && pixels[index + 2] === stonePixelsHd[index + 2]) same += 1;
  }
  assert.ok(same > SIZE * SIZE * 0.5, `${ATLAS_TEXTURES[ore].name} must be embedded in the stone texture (${same} matching texels)`);
  assert.ok(same < SIZE * SIZE * 0.97, `${ATLAS_TEXTURES[ore].name} must show its ore (${same} matching texels)`);
}

console.log("texture atlas ok");
