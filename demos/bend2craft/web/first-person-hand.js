import { cameraMotion } from "./visual-motion.js";
import { blockFaceTile, ENTITY_TEXTURE_TILES } from "./texture-atlas.js";

const NEUTRAL_TINT = [1, 1, 1];

function add(a, b) {
  return [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
}

function scale(value, factor) {
  return [value[0] * factor, value[1] * factor, value[2] * factor];
}

function part(center, size, tile, tint, pitch = 0, yaw = 0, faceTiles = null) {
  const box = {
    c: [...center],
    s: [...size],
    yaw,
    pitch,
    pivot: null,
    tile,
    tint: [...tint],
  };
  if (faceTiles !== null) box.faceTiles = [...faceTiles];
  return box;
}

/** Return camera-local first-person arm and held-block boxes for presentation. */
export function firstPersonHandParts({
  eye,
  direction,
  right,
  up,
  cameraYaw = 0,
  cameraPitch = 0,
  time,
  speed,
  grounded,
  selectedBlock = null,
  selectedItem = null,
  swing = 0,
}) {
  const motion = cameraMotion(time, { speed, grounded });
  const sway = scale(right, motion.sway * 0.8);
  const bob = scale(up, motion.bob * 0.8);
  const forward = scale(direction, 0.92);
  const handBase = add(add(add(eye, forward), scale(right, 0.37)), add(scale(up, -0.34), add(sway, bob)));
  const normalizedSwing = Number.isFinite(swing) ? Math.max(0, Math.min(1, swing)) : 0;
  const swingWeight = normalizedSwing === 0 || normalizedSwing === 1
    ? 0
    : Math.sin(Math.PI * normalizedSwing);
  const swingOffset = scale(direction, -0.16 * swingWeight);
  const swingDrop = scale(up, 0.14 * swingWeight);
  const arm = add(handBase, scale(up, -0.2));
  const hand = add(add(handBase, swingOffset), swingDrop);
  const parts = [
    part(arm, [0.16, 0.46, 0.16], ENTITY_TEXTURE_TILES.playerSleeve, NEUTRAL_TINT, cameraPitch - motion.roll * 2, cameraYaw),
    part(hand, [0.22, 0.22, 0.22], ENTITY_TEXTURE_TILES.villagerSkin, NEUTRAL_TINT, cameraPitch - motion.roll * 2, cameraYaw),
  ];
  const itemName = typeof selectedItem === "string" ? selectedItem : selectedItem?.item;
  if (typeof itemName === "string" && itemName.includes("pickaxe")) {
    const toolBase = add(handBase, add(scale(direction, 0.22), swingOffset));
    parts.push(part(add(toolBase, scale(up, 0.08)), [0.08, 0.54, 0.08], 5, [0.72, 0.42, 0.26], cameraPitch - motion.roll, cameraYaw));
    parts.push(part(add(toolBase, scale(up, 0.3)), [0.42, 0.1, 0.1], 1, [0.72, 0.74, 0.76], cameraPitch - motion.roll, cameraYaw));
  } else if (itemName === "torch") {
    parts.push(part(add(handBase, add(scale(direction, 0.18), swingOffset)), [0.14, 0.58, 0.14], 12, [1, 0.72, 0.28], cameraPitch - motion.roll, cameraYaw));
  } else if (Number.isInteger(selectedBlock) && selectedBlock > 0) {
    const faceTiles = [0, 1, 2, 3, 4, 5].map((faceIndex) => blockFaceTile(selectedBlock, faceIndex));
    parts.push(part(
      add(handBase, add(scale(direction, 0.24), swingOffset)),
      [0.16, 0.16, 0.16],
      selectedBlock,
      NEUTRAL_TINT,
      cameraPitch - motion.roll,
      cameraYaw,
      faceTiles,
    ));
  }
  return parts;
}
