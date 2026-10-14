import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  drawFirstPersonOverlay,
  firstPersonOverlayItem,
  firstPersonOverlayPose,
} from "../web/first-person-overlay.js";
import { ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, atlasCellOrigin, blockFaceTile } from "../web/texture-atlas.js";

const neutral = firstPersonOverlayPose({
  time: 0,
  speed: 0,
  grounded: true,
  swing: 0,
  motionEnabled: true,
});
assert.deepEqual(neutral, { x: 0, y: 0, rotation: -0.32, scale: 1 });

const walking = firstPersonOverlayPose({
  time: 0.25,
  speed: 4.5,
  grounded: true,
  swing: 0,
  motionEnabled: true,
});
assert.notDeepEqual(walking, neutral);
assert.ok(walking.x !== 0 || walking.y !== 0);

const swinging = firstPersonOverlayPose({
  time: 0,
  speed: 0,
  grounded: true,
  swing: 0.5,
  motionEnabled: true,
});
assert.ok(swinging.y > neutral.y);
assert.ok(swinging.rotation < neutral.rotation);
assert.ok(swinging.scale > neutral.scale);

const reduced = firstPersonOverlayPose({
  time: 0.25,
  speed: 4.5,
  grounded: true,
  swing: 0,
  motionEnabled: false,
});
assert.deepEqual(reduced, neutral);

assert.deepEqual(firstPersonOverlayItem({ selectedBlock: null, selectedItem: null }), {
  kind: "empty",
  block: null,
  item: null,
  tile: null,
});
assert.deepEqual(firstPersonOverlayItem({ selectedBlock: 1, selectedItem: null }), {
  kind: "block",
  block: 1,
  item: null,
  tile: 1,
});
assert.deepEqual(firstPersonOverlayItem({ selectedBlock: 3, selectedItem: null }), {
  kind: "block",
  block: 3,
  item: null,
  tile: blockFaceTile(3, 1),
});
assert.deepEqual(firstPersonOverlayItem({
  selectedBlock: null,
  selectedItem: { item: "wooden_pickaxe" },
}), {
  kind: "item",
  block: null,
  item: "wooden_pickaxe",
  tile: null,
});

const gameSource = await readFile(new URL("../web/game.js", import.meta.url), "utf8");
const indexSource = await readFile(new URL("../web/index.html", import.meta.url), "utf8");
const styleSource = await readFile(new URL("../web/styles.css", import.meta.url), "utf8");
assert.doesNotMatch(gameSource, /for \(const part of firstPersonHandParts/);
assert.match(gameSource, /drawFirstPersonOverlay/);
assert.match(indexSource, /id="first-person-hand-canvas"/);
assert.match(styleSource, /#first-person-hand-canvas/);
assert.match(styleSource, /image-rendering:\s*pixelated/);

// The held block samples its tile from the padded atlas: the tile interior of
// its cell, not a 16px grid slot. Reading a 16px slot at the atlas origin lands
// in another tile's gutter, which drew the held block as a flat sliver of the
// wrong material.
{
  const sources = [];
  const noop = () => {};
  const context = {
    clearRect: noop, save: noop, restore: noop, translate: noop, rotate: noop, scale: noop,
    transform: noop, fillRect: noop, beginPath: noop, moveTo: noop, lineTo: noop, closePath: noop, fill: noop,
    set imageSmoothingEnabled(value) { this.smoothing = value; },
    drawImage(image, sx, sy, sw, sh) { if (image === atlasCanvas) sources.push([sx, sy, sw, sh]); },
  };
  const atlasCanvas = { width: 2048, height: 2048 };
  const descriptor = drawFirstPersonOverlay(context, { atlasCanvas, selectedBlock: 1 });
  assert.equal(descriptor.kind, "block");
  const origin = atlasCellOrigin(descriptor.tile);
  assert.ok(sources.length >= 3, "the held block draws its three visible faces from the atlas");
  for (const source of sources) {
    assert.deepEqual(source, [origin.x + ATLAS_TILE_GUTTER, origin.y + ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, ATLAS_TILE_SIZE]);
  }
}

console.log("first person overlay ok");
