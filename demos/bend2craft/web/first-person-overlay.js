import { drawItemTexture, itemTexture } from "./item-atlas.js";
import { ATLAS_TILE_GUTTER, ATLAS_TILE_SIZE, atlasCellOrigin, blockFaceTile } from "./texture-atlas.js";
import { cameraMotion } from "./visual-motion.js";

export const FIRST_PERSON_OVERLAY_SIZE = 192;

function clamp01(value) {
  return Math.max(0, Math.min(1, Number(value)));
}

function itemName(value) {
  if (typeof value === "string") return value;
  if (value !== null && typeof value === "object" && typeof value.item === "string") return value.item;
  return null;
}

export function firstPersonOverlayItem({ selectedBlock = null, selectedItem = null } = {}) {
  if (Number.isInteger(selectedBlock) && selectedBlock > 0) {
    return {
      kind: "block",
      block: selectedBlock,
      item: null,
      tile: blockFaceTile(selectedBlock, 1),
    };
  }
  const item = itemName(selectedItem);
  if (item !== null) return { kind: "item", block: null, item, tile: null };
  return { kind: "empty", block: null, item: null, tile: null };
}

export function firstPersonOverlayPose({
  time,
  speed,
  grounded,
  swing = 0,
  motionEnabled = true,
} = {}) {
  const motion = motionEnabled ? cameraMotion(time, { speed, grounded }) : { sway: 0, bob: 0, roll: 0 };
  const phase = clamp01(swing);
  const arc = phase === 0 || phase === 1 ? 0 : Math.sin(Math.PI * phase);
  return {
    x: motion.sway * 12 - arc * 10,
    y: -motion.bob * 10 + arc * 18,
    rotation: -0.32 - motion.roll * 0.8 - arc * 0.24,
    scale: 1 + arc * 0.06,
  };
}

function drawArm(context) {
  context.fillStyle = "#244968";
  context.fillRect(-22, 14, 48, 92);
  context.fillStyle = "#3f6f9d";
  context.fillRect(-18, 16, 15, 84);
  context.fillStyle = "#172d43";
  context.fillRect(17, 16, 9, 90);
  context.fillStyle = "#c98f68";
  context.fillRect(-10, -5, 42, 40);
  context.fillStyle = "#e2ad82";
  context.fillRect(-7, -8, 31, 14);
  context.fillStyle = "#9f674c";
  context.fillRect(23, 1, 9, 32);
  context.fillStyle = "#d99b73";
  context.fillRect(-6, 28, 13, 18);
  context.fillRect(7, 28, 13, 18);
}

// The atlas is padded: each tile sits inside its own cell, offset by the
// gutter, so the source rectangle is the cell's interior at the atlas tile size.
function drawAtlasTile(context, atlasCanvas, tile, size) {
  const origin = atlasCellOrigin(tile);
  context.drawImage(
    atlasCanvas,
    origin.x + ATLAS_TILE_GUTTER,
    origin.y + ATLAS_TILE_GUTTER,
    ATLAS_TILE_SIZE,
    ATLAS_TILE_SIZE,
    0,
    0,
    size,
    size,
  );
}

function drawBlock(context, atlasCanvas, tile) {
  context.save();
  context.translate(4, -18);
  // A 128-texel tile lands on a face roughly thirty pixels across, so it is
  // filtered down; nearest sampling would alias it into speckle.
  context.imageSmoothingEnabled = true;
  if ("imageSmoothingQuality" in context) context.imageSmoothingQuality = "high";

  context.save();
  context.transform(1.75, -0.85, 1.75, 0.85, -28, -14);
  drawAtlasTile(context, atlasCanvas, tile, 16);
  context.restore();

  context.save();
  context.transform(1.75, 0.85, 0, 2.8, -28, 0);
  drawAtlasTile(context, atlasCanvas, tile, 16);
  context.restore();

  context.save();
  context.transform(1.75, -0.85, 0, 2.8, 0, -14);
  drawAtlasTile(context, atlasCanvas, tile, 16);
  context.restore();

  context.fillStyle = "rgba(10, 18, 14, 0.22)";
  context.fillRect(-27, 36, 55, 7);
  context.restore();
}

export function drawFirstPersonOverlay(context, {
  atlasCanvas = null,
  selectedBlock = null,
  selectedItem = null,
  time = 0,
  speed = 0,
  grounded = true,
  swing = 0,
  motionEnabled = true,
  size = FIRST_PERSON_OVERLAY_SIZE,
} = {}) {
  if (context === null || typeof context !== "object" || typeof context.clearRect !== "function") {
    throw new TypeError("A 2D canvas context is required for the first-person overlay.");
  }
  const descriptor = firstPersonOverlayItem({ selectedBlock, selectedItem });
  const pose = firstPersonOverlayPose({ time, speed, grounded, swing, motionEnabled });
  context.clearRect(0, 0, size, size);
  context.save();
  context.imageSmoothingEnabled = false;
  context.translate(size * 0.64 + pose.x, size * 0.4 + pose.y);
  context.rotate(pose.rotation);
  context.scale(pose.scale * 1.12, pose.scale * 1.12);
  drawArm(context);
  if (descriptor.kind === "block" && atlasCanvas !== null) {
    drawBlock(context, atlasCanvas, descriptor.tile);
  } else if (descriptor.kind === "item" && itemTexture(descriptor.item) !== null) {
    drawItemTexture(context, descriptor.item, {
      size: 76,
      x: -42,
      y: -58,
      clear: false,
      outline: "rgba(12, 18, 16, 0.7)",
    });
  }
  context.restore();
  return descriptor;
}
