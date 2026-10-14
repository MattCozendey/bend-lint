// Articulated entity models expressed as textured boxes.
// Pure presentation data: same input always yields the same boxes.
// A box is { c: [x, y, z] center, s: [w, h, d] size, yaw, pitch,
// pivot: [x, y, z] | null, tile: block id, tint: [r, g, b] }.
// Models face -Z at yaw 0, with their origin at the feet center.
import { ENTITY_TEXTURE_TILES } from "./texture-atlas.js";

export const TILE_ZOMBIE_SKIN = ENTITY_TEXTURE_TILES.zombieSkin;
export const TILE_ZOMBIE_SHIRT = ENTITY_TEXTURE_TILES.zombieShirt;
export const TILE_ZOMBIE_PANTS = ENTITY_TEXTURE_TILES.zombiePants;
export const TILE_PIG_SKIN = ENTITY_TEXTURE_TILES.pigSkin;
export const TILE_PIG_SNOUT = ENTITY_TEXTURE_TILES.pigSnout;
export const TILE_COW_HIDE = ENTITY_TEXTURE_TILES.cowHide;
export const TILE_COW_SNOUT = ENTITY_TEXTURE_TILES.cowSnout;
export const TILE_COW_FACE = ENTITY_TEXTURE_TILES.cowFace;
export const TILE_SHEEP_WOOL = ENTITY_TEXTURE_TILES.sheepWool;
export const TILE_SHEEP_FACE = ENTITY_TEXTURE_TILES.sheepFace;
export const TILE_CHICKEN_FEATHER = ENTITY_TEXTURE_TILES.chickenFeather;
export const TILE_CHICKEN_BEAK = ENTITY_TEXTURE_TILES.chickenBeak;
export const TILE_VILLAGER_SKIN = ENTITY_TEXTURE_TILES.villagerSkin;
export const TILE_VILLAGER_ROBE_GREEN = ENTITY_TEXTURE_TILES.villagerRobeGreen;
export const TILE_VILLAGER_ROBE_BROWN = ENTITY_TEXTURE_TILES.villagerRobeBrown;
export const TILE_ENTITY_EYE = ENTITY_TEXTURE_TILES.eye;
export const TILE_PLAYER_SLEEVE = ENTITY_TEXTURE_TILES.playerSleeve;
export const TILE_WOOD = 5;

const EYE_TINT = [0.06, 0.06, 0.07];
const FLASH_TINT = [1.0, 0.3, 0.25];
const ZOMBIE_SKIN = [0.45, 0.75, 0.42];
const ZOMBIE_SHIRT = [0.3, 0.62, 0.62];
const ZOMBIE_PANTS = [0.35, 0.42, 0.62];
// The brute is the zombie build scaled up and a shade darker, which is what the
// same undead looks like when it has twice the mass. Reusing the tiles keeps the
// palette honest: a monster in armour is not a cow in a harness.
const BRUTE_SKIN = [0.26, 0.42, 0.24];
const BRUTE_SHIRT = [0.19, 0.38, 0.38];
const BRUTE_PANTS = [0.21, 0.25, 0.36];
const PIG_SKIN = [1.0, 0.72, 0.72];
const PIG_SNOUT = [0.95, 0.55, 0.55];
const COW_HIDE = [0.72, 0.55, 0.38];
const COW_FACE = [0.95, 0.93, 0.86];
const COW_SNOUT = [0.9, 0.62, 0.58];
const SHEEP_WOOL = [0.96, 0.95, 0.9];
const SHEEP_FACE = [0.85, 0.79, 0.7];
const CHICKEN_FEATHER = [0.98, 0.97, 0.94];
const CHICKEN_BEAK = [0.95, 0.68, 0.22];
const VILLAGER_SKIN = [0.89, 0.67, 0.52];
const VILLAGER_GREEN_ROBE = [0.35, 0.62, 0.35];
const VILLAGER_BROWN_ROBE = [0.72, 0.56, 0.36];

/**
 * The envelope every articulated model in this module fits inside, measured from
 * the feet origin and taken as the worst case across all of them - so a pig is
 * not measured by a zombie's arms, and a cow is not measured by a pig's snout.
 * The fire plume is emitted in a ring at this radius for a reason: a particle
 * spawned inside the body is behind the body's own front faces, and the depth test
 * throws it away against the very thing it is meant to be licking. Anything that
 * needs to know how big a mob is - the plume, a highlight, a sound origin - should
 * read it from here rather than hardcode a number that silently drifts when a
 * model changes. `tests/mob-models.test.mjs` measures every box against it.
 */
export const MOB_BODY = Object.freeze({ radius: 0.95, height: 1.93 });

/** Yaw (radians) that faces a model at (fromX, fromZ) toward (toX, toZ). */
export function faceYaw(fromX, fromZ, toX, toZ) {
  return Math.atan2(toX - fromX, -(toZ - fromZ));
}

function box(center, size, tile, tint, extra = {}) {
  return {
    c: [...center],
    s: [...size],
    yaw: 0,
    pitch: 0,
    pivot: null,
    tile,
    tint: [...tint],
    ...extra,
  };
}

function orbit(parts, cx, cz, yaw) {
  if (yaw === 0) return parts;
  const sin = Math.sin(yaw);
  const cos = Math.cos(yaw);
  // Matches faceYaw: a part authored at -Z ends up along (sin yaw, -cos yaw).
  const turn = ([x, y, z]) => {
    const ox = x - cx;
    const oz = z - cz;
    return [cx + ox * cos - oz * sin, y, cz + ox * sin + oz * cos];
  };
  return parts.map((part) => ({
    ...part,
    c: turn(part.c),
    pivot: part.pivot === null ? null : turn(part.pivot),
    yaw: part.yaw + yaw,
  }));
}

function swingPhase(id) {
  return (Number(id) % 8) * (Math.PI / 4);
}

export function blinkFactor(id, time) {
  const phase = (Number(id) % 5) * 0.63;
  const cycle = (Number(time) + phase) % 5.2;
  return cycle > 4.82 ? 0.12 : 1;
}

/**
 * The two undead builds, as numbers. The brute is the same body with twice the
 * mass: wider torso, thicker limbs, arms that reach further, and a darker grade
 * of the same hide. Keeping it at zombie height is deliberate - the aimed
 * hitbox and the fire plume envelope are both sized from the standing body, and
 * a monster that is only distinguishable by being taller is a monster the player
 * cannot tell apart in the dark.
 */
const UNDEAD_BUILDS = Object.freeze({
  zombie: Object.freeze({
    legSize: [0.2, 0.75, 0.2],
    legY: 0.375,
    legX: 0.12,
    torsoSize: [0.52, 0.72, 0.34],
    torsoY: 1.1,
    armX: 0.35,
    armSize: [0.18, 0.62, 0.18],
    armY: 1.15,
    handY: 0.84,
    handX: 0.39,
    handZ: -0.58,
    shoulderY: 1.4,
    headSize: [0.46, 0.46, 0.44],
    faceZ: -0.215,
    headY: 1.68,
    armPitch: -1.15,
    armSwing: 0.3,
    pauldrons: false,
    skin: ZOMBIE_SKIN,
    shirt: ZOMBIE_SHIRT,
    pants: ZOMBIE_PANTS,
  }),
  brute: Object.freeze({
    legSize: [0.3, 0.75, 0.3],
    legY: 0.375,
    legX: 0.19,
    torsoSize: [0.76, 0.76, 0.5],
    torsoY: 1.1,
    armX: 0.47,
    armSize: [0.28, 0.66, 0.28],
    armY: 1.13,
    handY: 0.78,
    handX: 0.52,
    handZ: -0.66,
    shoulderY: 1.4,
    headSize: [0.56, 0.56, 0.54],
    faceZ: -0.265,
    headY: 1.62,
    armPitch: -1.05,
    armSwing: 0.22,
    pauldrons: true,
    skin: BRUTE_SKIN,
    shirt: BRUTE_SHIRT,
    pants: BRUTE_PANTS,
  }),
});

function undeadBoxes(mob, time, build) {
  const phase = swingPhase(mob.id);
  const legSwing = Math.sin(time * 9 + phase) * 0.55;
  const armSwing = Math.sin(time * 9 + phase + Math.PI) * build.armSwing;
  const bob = Math.sin(time * 2.4 + phase) * 0.018;
  const eyeOpen = blinkFactor(mob.id, time);
  const boxes = [];
  for (const side of [-1, 1]) {
    boxes.push(box(
      [mob.x + side * build.legX, mob.y + build.legY + bob, mob.z],
      [...build.legSize],
      TILE_ZOMBIE_PANTS,
      build.pants,
      { pitch: side < 0 ? legSwing : -legSwing, pivot: [mob.x + side * build.legX, mob.y + build.legY * 2, mob.z] },
    ));
  }
  boxes.push(box([mob.x, mob.y + build.torsoY + bob, mob.z], [...build.torsoSize], TILE_ZOMBIE_SHIRT, build.shirt));
  if (build.pauldrons) {
    for (const side of [-1, 1]) {
      // Pauldrons are what make the brute read as armoured mass at a distance
      // instead of a zombie that happens to be wider.
      boxes.push(box(
        [mob.x + side * (build.armX + build.armSize[0] * 0.35), mob.y + (build.shoulderY - 0.06) + bob, mob.z],
        [build.armSize[0] * 1.5, 0.16, build.armSize[2] * 1.6],
        TILE_ZOMBIE_PANTS,
        build.pants,
      ));
    }
  }
  for (const side of [-1, 1]) {
    const armPitch = build.armPitch + (side < 0 ? armSwing : -armSwing);
    const armPivot = [mob.x + side * build.armX, mob.y + build.shoulderY + bob, mob.z];
    boxes.push(box(
      [mob.x + side * build.armX, mob.y + build.armY + bob, mob.z - build.armSize[2] / 2],
      [...build.armSize],
      TILE_ZOMBIE_SKIN,
      build.skin,
      { pitch: armPitch, pivot: armPivot },
    ));
    boxes.push(box(
      [mob.x + side * build.handX, mob.y + build.handY + bob, mob.z + build.handZ],
      [build.armSize[0], build.armSize[0], build.armSize[0]],
      TILE_ZOMBIE_SKIN,
      build.skin,
      { pitch: armPitch, pivot: armPivot },
    ));
  }
  boxes.push(box([mob.x, mob.y + build.headY + bob, mob.z], [...build.headSize], TILE_ZOMBIE_SKIN, build.skin));
  boxes.push(box(
    [mob.x, mob.y + (build.headY - 0.09) + bob, mob.z + build.faceZ],
    [0.2, 0.055, 0.02],
    TILE_ENTITY_EYE,
    EYE_TINT,
  ));
  for (const side of [-1, 1]) {
    boxes.push(box(
      [mob.x + side * 0.1, mob.y + (build.headY + 0.04) + bob, mob.z + build.faceZ],
      [0.07, 0.08 * eyeOpen, 0.02],
      TILE_ENTITY_EYE,
      EYE_TINT,
    ));
  }
  return boxes;
}

/**
 * A four-legged grazer. The sheep and the cow share this rig - barrel body, head
 * carried in front, four swinging legs, a tail - and differ only in proportions
 * and hide. That is what separates a cow from a stretched pig at a distance:
 * proportion, not a new skeleton.
 */
function quadrupedBoxes(mob, time, build) {
  const phase = swingPhase(mob.id);
  const bob = Math.sin(time * 2.8 + phase) * 0.025;
  const graze = Math.sin(time * 1.3 + phase) * build.graze;
  const eyeOpen = blinkFactor(mob.id, time);
  const boxes = [];
  boxes.push(box([mob.x, mob.y + build.bodyY + bob, mob.z + build.bodyZ], [...build.bodySize], build.hideTile, build.hide));
  boxes.push(box(
    [mob.x, mob.y + build.headY + bob, mob.z + build.headZ],
    [...build.headSize],
    build.faceTile,
    build.face,
    { pitch: graze, pivot: [mob.x, mob.y + build.headTop, mob.z + build.headZ] },
  ));
  if (build.muzzle !== null) {
    boxes.push(box(
      [mob.x, mob.y + (build.headY - build.headSize[1] * 0.24) + bob, mob.z + build.muzzleZ],
      [...build.muzzle],
      build.muzzleTile,
      build.muzzleTint,
    ));
  }
  for (const side of [-1, 1]) {
    boxes.push(box(
      [mob.x + side * build.eyeX, mob.y + (build.headY + build.headSize[1] * 0.1) + bob, mob.z + build.eyeZ],
      [0.06, 0.07 * eyeOpen, 0.02],
      TILE_ENTITY_EYE,
      EYE_TINT,
    ));
  }
  build.legs.forEach(([ox, oz], index) => {
    const lift = Math.sin(time * 9 + phase + (index % 2) * Math.PI) * 0.4;
    boxes.push(box(
      [mob.x + ox, mob.y + build.legY + bob, mob.z + oz],
      [...build.legSize],
      build.legTile,
      build.leg,
      { pitch: lift, pivot: [mob.x + ox, mob.y + (build.legY + build.legSize[1] / 2), mob.z + oz] },
    ));
  });
  boxes.push(box(
    [mob.x, mob.y + build.tailY + bob, mob.z + build.tailZ],
    [...build.tailSize],
    build.tailTile,
    build.tail,
    { yaw: Math.sin(time * 4 + phase) * 0.35 },
  ));
  return boxes;
}

const GRAZER_BUILDS = Object.freeze({
  sheep: Object.freeze({
    bodySize: [0.7, 0.68, 1.04], bodyY: 0.86, bodyZ: 0.06,
    headSize: [0.4, 0.42, 0.4], headY: 1.12, headTop: 1.33, headZ: -0.6,
    hideTile: TILE_SHEEP_WOOL, hide: SHEEP_WOOL,
    faceTile: TILE_SHEEP_FACE, face: SHEEP_FACE,
    muzzle: null, muzzleZ: 0, muzzleTile: TILE_SHEEP_FACE, muzzleTint: SHEEP_FACE,
    eyeX: 0.09, eyeZ: -0.66,
    legs: [[-0.18, -0.32], [0.18, -0.32], [-0.18, 0.36], [0.18, 0.36]],
    legSize: [0.14, 0.52, 0.14], legY: 0.26, legTile: TILE_SHEEP_FACE, leg: SHEEP_FACE,
    tailSize: [0.12, 0.12, 0.16], tailY: 0.96, tailZ: 0.56, tailTile: TILE_SHEEP_WOOL, tail: SHEEP_WOOL,
    graze: 0.22,
  }),
  cow: Object.freeze({
    bodySize: [0.78, 0.74, 1.2], bodyY: 0.88, bodyZ: 0.04,
    headSize: [0.44, 0.44, 0.44], headY: 1.14, headTop: 1.36, headZ: -0.66,
    hideTile: TILE_COW_HIDE, hide: COW_HIDE,
    faceTile: TILE_COW_FACE, face: COW_FACE,
    muzzle: [0.3, 0.2, 0.08], muzzleZ: -0.88, muzzleTile: TILE_COW_SNOUT, muzzleTint: COW_SNOUT,
    eyeX: 0.1, eyeZ: -0.72,
    legs: [[-0.22, -0.38], [0.22, -0.38], [-0.22, 0.42], [0.22, 0.42]],
    legSize: [0.16, 0.5, 0.16], legY: 0.25, legTile: TILE_COW_HIDE, leg: COW_HIDE,
    tailSize: [0.08, 0.3, 0.08], tailY: 1.0, tailZ: 0.68, tailTile: TILE_COW_HIDE, tail: COW_HIDE,
    graze: 0.26,
  }),
});

function pigBoxes(mob, time) {
  const phase = swingPhase(mob.id);
  const bob = Math.sin(time * 2.8 + phase) * 0.025;
  const eyeOpen = blinkFactor(mob.id, time);
  const boxes = [];
  boxes.push(box([mob.x, mob.y + 0.62 + bob, mob.z + 0.08], [0.64, 0.58, 1.02], TILE_PIG_SKIN, PIG_SKIN));
  boxes.push(box([mob.x, mob.y + 0.85 + bob, mob.z - 0.55], [0.52, 0.46, 0.44], TILE_PIG_SKIN, PIG_SKIN));
  boxes.push(box([mob.x, mob.y + 0.76 + bob, mob.z - 0.78], [0.2, 0.15, 0.06], TILE_PIG_SNOUT, PIG_SNOUT));
  for (const side of [-1, 1]) {
    boxes.push(box(
      [mob.x + side * 0.045, mob.y + 0.76 + bob, mob.z - 0.812],
      [0.035, 0.04, 0.012],
      TILE_ENTITY_EYE,
      EYE_TINT,
    ));
  }
  for (const side of [-1, 1]) {
    boxes.push(box(
      [mob.x + side * 0.1, mob.y + 0.9 + bob, mob.z - 0.62],
      [0.07, 0.08 * eyeOpen, 0.02],
      TILE_ENTITY_EYE,
      EYE_TINT,
    ));
    boxes.push(box(
      [mob.x + side * 0.18, mob.y + 1.08 + bob, mob.z - 0.56],
      [0.13, 0.16, 0.1],
      TILE_PIG_SKIN,
      PIG_SKIN,
      { yaw: side * 0.18 + Math.sin(time * 2 + phase) * 0.04 },
    ));
  }
  const corners = [[-0.2, -0.3], [0.2, -0.3], [-0.2, 0.38], [0.2, 0.38]];
  corners.forEach(([ox, oz], index) => {
    const lift = Math.sin(time * 9 + phase + (index % 2) * Math.PI) * 0.4;
    boxes.push(box(
      [mob.x + ox, mob.y + 0.2 + bob, mob.z + oz],
      [0.16, 0.4, 0.16],
      TILE_PIG_SNOUT,
      PIG_SNOUT,
      { pitch: lift, pivot: [mob.x + ox, mob.y + 0.4 + bob, mob.z + oz] },
    ));
  });
  boxes.push(box(
    [mob.x, mob.y + 0.68 + bob, mob.z + 0.58],
    [0.1, 0.1, 0.26],
    TILE_PIG_SNOUT,
    PIG_SNOUT,
    { yaw: Math.sin(time * 4 + phase) * 0.35 },
  ));
  return boxes;
}

/** A chicken is a bird: two thin legs, a round body, a comb and a beak. */
function chickenBoxes(mob, time) {
  const phase = swingPhase(mob.id);
  const bob = Math.sin(time * 3.2 + phase) * 0.02;
  const step = Math.sin(time * 12 + phase) * 0.5;
  const peck = Math.sin(time * 1.7 + phase) * 0.3;
  const eyeOpen = blinkFactor(mob.id, time);
  const boxes = [];
  for (const side of [-1, 1]) {
    boxes.push(box(
      [mob.x + side * 0.07, mob.y + 0.09 + bob, mob.z],
      [0.05, 0.18, 0.05],
      TILE_CHICKEN_BEAK,
      CHICKEN_BEAK,
      { pitch: side < 0 ? step : -step, pivot: [mob.x + side * 0.07, mob.y + 0.18, mob.z] },
    ));
  }
  boxes.push(box([mob.x, mob.y + 0.36 + bob, mob.z], [0.34, 0.36, 0.44], TILE_CHICKEN_FEATHER, CHICKEN_FEATHER));
  boxes.push(box(
    [mob.x, mob.y + 0.5 + bob, mob.z - 0.16],
    [0.16, 0.16, 0.1],
    TILE_CHICKEN_FEATHER,
    CHICKEN_FEATHER,
    { pitch: peck, pivot: [mob.x, mob.y + 0.58, mob.z - 0.1] },
  ));
  boxes.push(box([mob.x, mob.y + 0.63 + bob, mob.z - 0.2], [0.1, 0.09, 0.06], TILE_CHICKEN_BEAK, CHICKEN_BEAK));
  boxes.push(box([mob.x, mob.y + 0.48 + bob, mob.z - 0.24], [0.06, 0.09, 0.04], TILE_CHICKEN_BEAK, CHICKEN_BEAK));
  boxes.push(box([mob.x, mob.y + 0.72 + bob, mob.z - 0.14], [0.05, 0.09, 0.12], TILE_CHICKEN_BEAK, CHICKEN_BEAK));
  boxes.push(box([mob.x, mob.y + 0.38 + bob, mob.z + 0.26], [0.16, 0.2, 0.1], TILE_CHICKEN_FEATHER, CHICKEN_FEATHER));
  for (const side of [-1, 1]) {
    boxes.push(box(
      [mob.x + side * 0.06, mob.y + 0.54 + bob, mob.z - 0.21],
      [0.05, 0.06 * eyeOpen, 0.02],
      TILE_ENTITY_EYE,
      EYE_TINT,
    ));
  }
  return boxes;
}

const KIND_BUILDERS = Object.freeze({
  1: pigBoxes,
  2: (mob, time) => undeadBoxes(mob, time, UNDEAD_BUILDS.zombie),
  3: (mob, time) => quadrupedBoxes(mob, time, GRAZER_BUILDS.sheep),
  4: (mob, time) => undeadBoxes(mob, time, UNDEAD_BUILDS.brute),
  5: (mob, time) => quadrupedBoxes(mob, time, GRAZER_BUILDS.cow),
  6: chickenBoxes,
});

/**
 * Boxes for a mob view { id, kind, x, y, z } at a time in seconds. Yaw faces -Z.
 *
 * Every kind in `web/mob-kinds.js` owns a builder. The kind used to fall through
 * to the pig, which is how a hostile brute ended up drawn as a pig that charged
 * the player and burned in daylight; an unknown kind now falls through to the
 * zombie, the one body a stranger is least likely to be mistaken for.
 */
export function mobBoxes(mob, time, yaw = 0, flash = false) {
  const build = KIND_BUILDERS[Number(mob.kind)] ?? KIND_BUILDERS[2];
  const raw = build(mob, time);
  const tinted = flash
    ? raw.map((part) => ({ ...part, tint: [...FLASH_TINT] }))
    : raw;
  return orbit(tinted, mob.x, mob.z, yaw);
}

export function villagerRobeTint(profession) {
  return Number(profession) === 2 ? [...VILLAGER_GREEN_ROBE] : [...VILLAGER_BROWN_ROBE];
}

/** Boxes for a villager view { id, profession, x, y, z } at a time in seconds. */
export function villagerBoxes(villager, time, yaw = 0) {
  const robe = villagerRobeTint(villager.profession);
  const robeTile = Number(villager.profession) === 2 ? TILE_VILLAGER_ROBE_GREEN : TILE_VILLAGER_ROBE_BROWN;
  const bob = Math.sin(time * 2 + swingPhase(villager.id)) * 0.03;
  const armSwing = Math.sin(time * 4.5 + swingPhase(villager.id)) * 0.28;
  const eyeOpen = blinkFactor(villager.id, time);
  const parts = [
    box([villager.x, villager.y + 0.58 + bob, villager.z], [0.66, 1.12, 0.52], robeTile, robe),
    box([villager.x, villager.y + 1.5 + bob, villager.z], [0.42, 0.42, 0.42], TILE_VILLAGER_SKIN, VILLAGER_SKIN),
    box([villager.x, villager.y + 1.46 + bob, villager.z - 0.24], [0.12, 0.2, 0.1], TILE_VILLAGER_SKIN, VILLAGER_SKIN),
  ];
  for (const side of [-1, 1]) {
    parts.push(box(
      [villager.x + side * 0.36, villager.y + 1.12 + bob, villager.z],
      [0.19, 0.62, 0.19],
      robeTile,
      robe,
      { pitch: side < 0 ? armSwing : -armSwing, pivot: [villager.x + side * 0.36, villager.y + 1.37 + bob, villager.z] },
    ));
  }
  for (const side of [-1, 1]) {
    parts.push(box(
      [villager.x + side * 0.09, villager.y + 1.54 + bob, villager.z - 0.205],
      [0.06, 0.07 * eyeOpen, 0.02],
      TILE_ENTITY_EYE,
      EYE_TINT,
    ));
  }
  return orbit(parts, villager.x, villager.z, yaw);
}

const DROP_TILE_BY_ITEM = Object.freeze({ 12: 4, 13: 9, 48: 9, 49: 9, 50: 9 });
// Wool, rotten flesh and the three raw meats. The meats share one flesh tile and
// are told apart by tint, the way a dropped item is read at a glance.
const DROP_TINT_BY_ITEM = Object.freeze({
  12: [0.95, 0.93, 0.85],
  13: [0.6, 0.3, 0.28],
  48: [0.92, 0.6, 0.58],
  49: [0.72, 0.26, 0.24],
  50: [0.94, 0.86, 0.7],
});

/** Boxes for a drop view { id, item, x, y, z }. Spins slowly around Y. */
export function dropBoxes(drop, time) {
  const tile = DROP_TILE_BY_ITEM[drop.item] ?? 1;
  const tint = DROP_TINT_BY_ITEM[drop.item] ?? [0.8, 0.8, 0.8];
  return [box(
    [drop.x, drop.y + 0.14, drop.z],
    [0.28, 0.28, 0.28],
    tile,
    [...tint],
    { yaw: time * 2 + swingPhase(drop.id) },
  )];
}

// Remote players wear the same sleeve and skin tiles as the first-person hand
// (web/first-person-hand.js), untinted, so another player looks like the arm
// you see in your own view. Names above their heads tell players apart.
const PLAYER_TINT = [1, 1, 1];
const PLAYER_HAIR = [0.42, 0.28, 0.18];

/**
 * Boxes for a remote player view { id, x, y, z, yaw, pitch, speed }: feet at
 * y, facing yaw in the camera convention (sin yaw, -cos yaw). Limbs swing with
 * the walking speed and the head follows the pitch.
 */
export function playerBoxes(view, time) {
  const stride = Math.min(1, (Number(view.speed) || 0) / 4.3);
  const phase = swingPhase(view.id);
  const legSwing = Math.sin(time * 9 + phase) * 0.6 * stride;
  const armSwing = Math.sin(time * 9 + phase + Math.PI) * 0.5 * stride;
  const eyeOpen = blinkFactor(view.id, time);
  const pitch = Math.max(-1.2, Math.min(1.2, Number(view.pitch) || 0));
  const { x, y, z } = view;
  const headPivot = [x, y + 1.46, z];
  const parts = [];
  for (const side of [-1, 1]) {
    parts.push(box(
      [x + side * 0.12, y + 0.375, z],
      [0.2, 0.75, 0.2],
      TILE_ZOMBIE_PANTS,
      PLAYER_TINT,
      { pitch: side < 0 ? legSwing : -legSwing, pivot: [x + side * 0.12, y + 0.75, z] },
    ));
  }
  parts.push(box([x, y + 1.1, z], [0.5, 0.72, 0.28], TILE_PLAYER_SLEEVE, PLAYER_TINT));
  for (const side of [-1, 1]) {
    parts.push(box(
      [x + side * 0.34, y + 1.12, z],
      [0.18, 0.66, 0.18],
      TILE_PLAYER_SLEEVE,
      PLAYER_TINT,
      { pitch: side < 0 ? armSwing : -armSwing, pivot: [x + side * 0.34, y + 1.4, z] },
    ));
  }
  parts.push(box([x, y + 1.68, z], [0.46, 0.46, 0.44], TILE_VILLAGER_SKIN, PLAYER_TINT, { pitch, pivot: headPivot }));
  parts.push(box([x, y + 1.885, z + 0.02], [0.48, 0.06, 0.46], TILE_VILLAGER_SKIN, PLAYER_HAIR, { pitch, pivot: headPivot }));
  for (const side of [-1, 1]) {
    parts.push(box(
      [x + side * 0.1, y + 1.72, z - 0.225],
      [0.07, 0.07 * eyeOpen, 0.02],
      TILE_ENTITY_EYE,
      EYE_TINT,
      { pitch, pivot: headPivot },
    ));
  }
  return orbit(parts, x, z, Number(view.yaw) || 0);
}
