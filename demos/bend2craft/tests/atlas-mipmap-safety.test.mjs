import assert from "node:assert/strict";
import {
  ATLAS_COLUMNS,
  ATLAS_MIPMAP_SAFE_LEVELS,
  ATLAS_MIPMAP_TOLERANCE,
  ATLAS_ROWS,
  ATLAS_TILE_GUTTER,
  ATLAS_TILE_SIZE,
  ATLAS_TILE_STRIDE,
  atlasCellOrigin,
  atlasBoxDownsample,
  atlasMipLevelGeometry,
  atlasTileUV,
  atlasUV,
  foreignTileContamination,
  isAtlasMipmapSafe,
  maxChannelDelta,
} from "../web/texture-atlas.js";

// A tiled atlas can only take mipmaps when every tile owns padding, because a
// mip texel that averages two neighbouring materials is a visible defect. These
// tests pin the layout that makes the mip chain safe and prove the verdict can
// actually detect contamination.

assert.ok(ATLAS_TILE_GUTTER > 0, "the atlas must pad each tile before enabling mipmaps");
assert.equal(ATLAS_TILE_STRIDE, ATLAS_TILE_SIZE + 2 * ATLAS_TILE_GUTTER);

// The atlas must stay a power of two, or mip generation is not available at all.
const atlasWidth = ATLAS_COLUMNS * ATLAS_TILE_STRIDE;
const atlasHeight = ATLAS_ROWS * ATLAS_TILE_STRIDE;
assert.ok(Number.isInteger(Math.log2(atlasWidth)), `atlas width ${atlasWidth} must be a power of two`);
assert.ok(Number.isInteger(Math.log2(atlasHeight)), `atlas height ${atlasHeight} must be a power of two`);
assert.equal(atlasWidth, 2048, "a 128-texel tile with a 64-texel gutter over 8 columns");
assert.equal(atlasHeight, 2048);

// Every tile owns a padded cell, and horizontally adjacent tiles keep a gutter.
for (let tile = 0; tile < ATLAS_COLUMNS * ATLAS_ROWS; tile += 1) {
  const origin = atlasCellOrigin(tile);
  assert.ok(origin.x + ATLAS_TILE_STRIDE <= atlasWidth);
  assert.ok(origin.y + ATLAS_TILE_STRIDE <= atlasHeight);
  if (tile + 1 >= ATLAS_COLUMNS * ATLAS_ROWS) continue;
  const neighbor = atlasCellOrigin(tile + 1);
  if (origin.y === neighbor.y) {
    const gap = neighbor.x - origin.x - ATLAS_TILE_SIZE;
    assert.equal(gap, 2 * ATLAS_TILE_GUTTER, "a tile must be followed by a full gutter");
  }
}

// The reference mip chain is what makes a hand-written WebGPU downsample
// checkable at all: the WebGL path uses the driver's `generateMipmap`, and a
// gate that builds both sides with its own generator certifies a broken chain
// as clean. These tests pin the reference itself.
const ramp = new Uint8Array(atlasWidth * atlasHeight * 4);
for (let index = 0; index < atlasWidth * atlasHeight; index += 1) {
  ramp[index * 4] = index % 256;
  ramp[index * 4 + 1] = (index * 7) % 256;
  ramp[index * 4 + 2] = (index * 13) % 256;
  ramp[index * 4 + 3] = 255;
}
const chainZero = atlasBoxDownsample(atlasWidth, ramp, 0);
assert.equal(chainZero.size, atlasWidth, "level zero is the source");
assert.deepEqual([...chainZero.pixels.subarray(0, 16)], [...ramp.subarray(0, 16)]);

const chainOne = atlasBoxDownsample(atlasWidth, ramp, 1);
assert.equal(chainOne.size, atlasWidth / 2);
assert.equal(chainOne.pixels.length, (atlasWidth / 2) * (atlasWidth / 2) * 4);
// Every output texel is the mean of exactly the 2x2 block above it.
for (let y = 0; y < 4; y += 1) {
  for (let x = 0; x < 4; x += 1) {
    for (let channel = 0; channel < 3; channel += 1) {
      let sum = 0;
      for (let dy = 0; dy < 2; dy += 1) {
        for (let dx = 0; dx < 2; dx += 1) {
          sum += ramp[((y * 2 + dy) * atlasWidth + (x * 2 + dx)) * 4 + channel];
        }
      }
      assert.equal(
        chainOne.pixels[(y * chainOne.size + x) * 4 + channel],
        Math.round(sum / 4),
        `level 1 texel ${x},${y} channel ${channel} must be the 2x2 mean`,
      );
    }
  }
}
// Repeated 2x2 averaging is the same as one pass, so the chain has to be
// self-consistent rather than drifting a little at every level.
const chainTwo = atlasBoxDownsample(atlasWidth, ramp, 2);
assert.equal(chainTwo.size, atlasWidth / 4);
const chainTwoFromOne = atlasBoxDownsample(chainOne.size, chainOne.pixels, 1);
assert.equal(maxChannelDelta(chainTwo.pixels, chainTwoFromOne.pixels), 0,
  "a level must not depend on whether it was reached in one pass or two");
// A flat atlas must stay flat all the way down, or the chain is inventing detail.
const flat = new Uint8Array(atlasWidth * atlasHeight * 4).fill(90);
for (let level = 1; level <= 4; level += 1) {
  const flatLevel = atlasBoxDownsample(atlasWidth, flat, level);
  for (let index = 0; index < flatLevel.pixels.length; index += 4) {
    assert.equal(flatLevel.pixels[index], 90, `level ${level} must not lift a flat atlas`);
    assert.equal(flatLevel.pixels[index + 1], 90);
    assert.equal(flatLevel.pixels[index + 2], 90);
  }
}
assert.equal(atlasBoxDownsample(0, new Uint8Array(0), 0).size, 1, "an empty input must not divide by zero");

// Sampling must inset by the gutter so linear filtering cannot reach the
// neighbouring material even at the tile's own edge.
const uv = atlasUV(1);
// `atlasUV` keeps the two-triangle corner order the vertex builder expects.
assert.equal(uv.length, 8);
const insetU = ATLAS_TILE_GUTTER / atlasWidth;
const insetV = ATLAS_TILE_GUTTER / atlasHeight;
const stoneOrigin = atlasCellOrigin(1);
assert.deepEqual(atlasTileUV(1), [
  (stoneOrigin.x + ATLAS_TILE_GUTTER) / atlasWidth,
  (stoneOrigin.y + ATLAS_TILE_GUTTER) / atlasHeight,
  (stoneOrigin.x + ATLAS_TILE_GUTTER + ATLAS_TILE_SIZE) / atlasWidth,
  (stoneOrigin.y + ATLAS_TILE_GUTTER + ATLAS_TILE_SIZE) / atlasHeight,
]);
assert.equal(uv[0], (stoneOrigin.x + ATLAS_TILE_GUTTER) / atlasWidth);
assert.equal(uv[5], (stoneOrigin.y + ATLAS_TILE_GUTTER + ATLAS_TILE_SIZE) / atlasHeight);
assert.ok(uv[0] > insetU - 1e-9, "the tile inset must be at least the gutter");
assert.ok(uv[4] < 1 - insetU + 1e-9, "the far edge must stay inside the atlas");
assert.ok(uv[1] > insetV - 1e-9);
assert.ok(uv[5] < 1 - insetV + 1e-9);
assert.ok(
  uv[4] * atlasWidth <= stoneOrigin.x + ATLAS_TILE_GUTTER + ATLAS_TILE_SIZE + 1e-6,
  "the sampled window must stop at the tile edge",
);
assert.ok(
  uv[0] * atlasWidth >= stoneOrigin.x + ATLAS_TILE_GUTTER - 1e-6,
  "the sampled window must start at the gutter",
);

// The geometry the mip probe reads back must shrink the cell predictably.
const level1 = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, 1);
assert.deepEqual(level1, { interior: 64, padding: 32, size: 128, factor: 2 });
const level4 = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, 4);
assert.deepEqual(level4, { interior: 8, padding: 4, size: 16, factor: 16 });
const level6 = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, 6);
assert.deepEqual(level6, { interior: 2, padding: 1, size: 4, factor: 64 });
for (const level of ATLAS_MIPMAP_SAFE_LEVELS) {
  const geometry = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, level);
  // The outermost interior texel at this level reaches 2^(level-1) source
  // texels past the tile edge, so the gutter has to be at least that wide.
  assert.ok(
    2 ** (level - 1) <= ATLAS_TILE_GUTTER,
    `level ${level} reaches past the gutter`,
  );
  assert.ok(geometry.padding >= 1, `level ${level} must keep a readable gutter`);
  assert.ok(geometry.size >= 1, `level ${level} must keep a probeable cell`);
}

// The verdict compares a cell read from the full atlas against the same cell
// read from an isolated copy. A material with a legitimately varied interior and
// a matching gutter is clean, because the two readbacks agree.
const tile = makeCell();
assert.equal(foreignTileContamination(tile, tile), false, "an isolated tile cannot contaminate itself");
assert.equal(foreignTileContamination(tile, makeCell()), false, "two identical readbacks are clean");
assert.equal(maxChannelDelta(tile.pixels, tile.pixels), 0);

// Mip filtering rounds, so a clean comparison tolerates small differences.
const rounded = makeCell();
for (let index = 0; index < rounded.pixels.length; index += 1) {
  rounded.pixels[index] = Math.min(255, rounded.pixels[index] + ATLAS_MIPMAP_TOLERANCE);
}
assert.equal(foreignTileContamination(tile, rounded), false, "rounding must not read as contamination");
assert.equal(
  foreignTileContamination(tile, makeCell({ shift: ATLAS_MIPMAP_TOLERANCE + 1 })),
  true,
  "a difference past the tolerance is contamination",
);

// A neighbour that bled into the gutter is contamination at every level.
for (const level of ATLAS_MIPMAP_SAFE_LEVELS) {
  const geometry = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, level);
  const observed = makeCell({ size: geometry.size, bleedRight: true });
  const reference = makeCell({ size: geometry.size });
  assert.equal(
    foreignTileContamination(observed, reference),
    true,
    `a bled neighbour must be detected at level ${level}`,
  );
  const clean = makeCell({ size: geometry.size });
  assert.equal(
    foreignTileContamination(clean, makeCell({ size: geometry.size })),
    false,
    `an unpadded cell level ${level} must read as clean`,
  );
}

// Mismatched or missing readbacks are never certified.
assert.equal(foreignTileContamination(tile, makeCell({ size: 8 })), true, "sizes must match");
assert.equal(foreignTileContamination(null, tile), true);
assert.equal(foreignTileContamination(tile, null), true);
assert.equal(foreignTileContamination({ size: 4, pixels: new Uint8Array(8) }, tile), true, "a short readback is never certified");

const cleanPairs = ATLAS_MIPMAP_SAFE_LEVELS.map((level) => {
  const geometry = atlasMipLevelGeometry(ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, level);
  return { observed: makeCell({ size: geometry.size }), reference: makeCell({ size: geometry.size }) };
});
assert.equal(isAtlasMipmapSafe(cleanPairs), true);
assert.equal(isAtlasMipmapSafe(cleanPairs.slice(0, 2)), true, "a subset of probed levels is still a verdict");
assert.equal(
  isAtlasMipmapSafe([...cleanPairs, { observed: makeCell({ bleedRight: true }), reference: makeCell() }]),
  false,
  "one contaminated level fails the whole atlas",
);
assert.equal(isAtlasMipmapSafe([]), false, "no probed levels cannot certify mipmaps");
assert.equal(isAtlasMipmapSafe(null), false);

console.log("atlas mipmap safety ok");

// A stand-in for one mip level of a padded tile. Without `bleedRight` the cell
// only carries its own material, which is what an isolated reference produces.
// With it, a foreign material occupies the right-hand gutter, which is what a
// neighbour that leaked into the cell looks like.
function makeCell({ size = ATLAS_TILE_STRIDE, bleedRight = false, shift = 0 } = {}) {
  const padding = Math.floor(ATLAS_TILE_SIZE / (ATLAS_TILE_STRIDE / size)) || 1;
  const interior = Math.max(1, size - 2 * padding);
  const pixels = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const index = (y * size + x) * 4;
      const inGutter = x < padding || x >= padding + interior || y < padding || y >= padding + interior;
      const foreign = bleedRight && inGutter && x >= padding + interior;
      // A material is not one flat color: the interior carries its own
      // variation, so a clean comparison can only work against a reference.
      const base = foreign ? 220 : 40 + ((x * 7 + y * 13) % 60);
      pixels[index] = Math.min(255, base + shift);
      pixels[index + 1] = Math.min(255, (foreign ? 20 : 60 + ((x * 3 + y * 5) % 50)) + shift);
      pixels[index + 2] = Math.min(255, (foreign ? 20 : 30 + ((x * 11 + y * 2) % 40)) + shift);
      pixels[index + 3] = 255;
    }
  }
  return { size, padding, interior, pixels };
}
