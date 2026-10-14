import { Player as PlayerDomain, Fluids as FluidsDomain } from "./bend-modules.js";
import { bendList, bendPlanes } from "./bend-list.js";

export const PLAYER_RADIUS = 0.3;
export const PLAYER_HEIGHT = 1.8;
export const EYE_HEIGHT = 1.62;
export const MOVE_SPEED = 4.5;
export const SPRINT_SPEED = 6.75;
export const SNEAK_SPEED = 1.3;
export const SNEAK_EYE_HEIGHT = 1.27;
export const JUMP_SPEED = 7.0;
export const GRAVITY = 20.0;

const SPRINT_KEYS = ["ControlLeft", "ControlRight", "Sprint"];
const SNEAK_KEYS = ["ShiftLeft", "ShiftRight", "Shift"];

export function isSprinting(held, controls = {}) {
  const keys = controls.sprint === undefined ? SPRINT_KEYS : [controls.sprint, ...SPRINT_KEYS];
  for (const key of keys) {
    if (held.has(key)) return true;
  }
  return false;
}

export function isSneaking(held, controls = {}) {
  const keys = controls.sneak === undefined ? SNEAK_KEYS : [controls.sneak, ...SNEAK_KEYS];
  for (const key of keys) {
    if (held.has(key)) return true;
  }
  return false;
}

const PLAYER_STATES = new WeakMap();
// Shifts possibly-negative world coordinates into Nat range for the Bend
// domain. Keep it small: domain positions are F32, and at 2^20 the float
// grid (0.125) is wider than a per-tick diagonal step (~0.053), which froze
// diagonal movement while cardinals kept going. At 2^15 the grid is 0.0039
// and still leaves +/-32768 blocks of negative reach.
export const DOMAIN_COORDINATE_OFFSET = 32768;
const COLLISION_WIDTH = 5;
const COLLISION_HEIGHT = 6;
const COLLISION_DEPTH = 5;

export function createWorldState(width, depth, maxY) {
  const blocks = new Uint8Array(width * depth * maxY);
  const indexOf = (x, y, z) => x + width * (z + depth * y);
  const inside = (x, y, z) =>
    x >= 0 && x < width && y >= 0 && y < maxY && z >= 0 && z < depth;
  const blockAt = (x, y, z) => inside(x, y, z) ? blocks[indexOf(x, y, z)] : 0;
  const setBlock = (x, y, z, value) => {
    if (inside(x, y, z)) blocks[indexOf(x, y, z)] = value;
  };
  return { width, depth, maxY, blocks, inside, blockAt, setBlock };
}

function stateView(raw) {
  return {
    x: Number(raw.x) - DOMAIN_COORDINATE_OFFSET,
    y: Number(raw.y),
    z: Number(raw.z) - DOMAIN_COORDINATE_OFFSET,
    yaw: Number(raw.yaw),
    pitch: Number(raw.pitch),
    velocityY: Number(raw.velocity_y),
    grounded: raw.grounded,
    health: Number(raw.health),
    hunger: Number(raw.hunger),
    air: Number(raw.air),
    fall: Number(raw.fall),
    poison: Number(raw.poison),
  };
}

function finiteOr(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function stateRaw(player) {
  const raw = PlayerDomain.state_full(
    Number(player.x) + DOMAIN_COORDINATE_OFFSET,
    Number(player.y),
    Number(player.z) + DOMAIN_COORDINATE_OFFSET,
    Number(player.yaw),
    Number(player.pitch),
    Number(player.velocityY),
    Boolean(player.grounded),
    finiteOr(player.health, 20),
    finiteOr(player.hunger, 20),
    finiteOr(player.air, 10),
    finiteOr(player.fall, 0),
    finiteOr(player.poison, 0),
  );
  PLAYER_STATES.set(player, raw);
  return raw;
}

export function createPlayer(spawnCell, spawnHeight) {
  const raw = PlayerDomain.create(
    BigInt(spawnCell[0]) + BigInt(DOMAIN_COORDINATE_OFFSET),
    BigInt(spawnCell[1]) + BigInt(DOMAIN_COORDINATE_OFFSET),
    BigInt(spawnHeight),
  );
  const player = stateView(raw);
  PLAYER_STATES.set(player, raw);
  return player;
}

export function clampPlayer(player, width = 48, depth = 48) {
  return player;
}

// A Bend region is a list of y-planes, each holding `width * depth` cells in the
// region's own cell order, because `Player.region_block` indexes the region with a
// list walk and a flat list makes every cell lookup cost the cell's position. Every
// builder below fills `values` in y-major order, so the plane at height `y` is
// exactly the slice starting at `y * width * depth`.
function blockPlanes(values, width, depth) {
  return bendPlanes(values, width * depth);
}

function collisionRegion(world, x, y, z) {
  const originX = Math.floor(x) - 2;
  const originY = Math.max(0, Math.floor(y) - 1);
  const originZ = Math.floor(z) - 2;
  const values = [];
  for (let localY = 0; localY < COLLISION_HEIGHT; localY += 1) {
    for (let localZ = 0; localZ < COLLISION_DEPTH; localZ += 1) {
      for (let localX = 0; localX < COLLISION_WIDTH; localX += 1) {
        values.push(world.blockAt(originX + localX, originY + localY, originZ + localZ));
      }
    }
  }
  return {
    // `blocks` is what `Player.region_block` indexes, so it is the plane list.
    // `cells` is the same window flattened, for the rules that ask whether the window
    // holds any block at all and so have no cell to index by.
    blocks: blockPlanes(values, COLLISION_WIDTH, COLLISION_DEPTH),
    cells: bendList(values),
    originX: originX + DOMAIN_COORDINATE_OFFSET,
    originY,
    originZ: originZ + DOMAIN_COORDINATE_OFFSET,
  };
}

export function isSolid(block) {
  return PlayerDomain.solid(block);
}

export const MOB_REGION_WIDTH = 5;
export const MOB_REGION_HEIGHT = 6;
export const MOB_REGION_DEPTH = 5;

// Small collision region around a mob, in the same offset frame the Bend
// domain expects. Returned origins are BigInt Nats; blocks is a Bend list.
export function mobRegion(world, x, y, z) {
  const originX = Math.floor(x) - 2;
  const originY = Math.max(0, Math.floor(y) - 2);
  const originZ = Math.floor(z) - 2;
  const values = [];
  for (let localY = 0; localY < MOB_REGION_HEIGHT; localY += 1) {
    for (let localZ = 0; localZ < MOB_REGION_DEPTH; localZ += 1) {
      for (let localX = 0; localX < MOB_REGION_WIDTH; localX += 1) {
        values.push(world.blockAt(originX + localX, originY + localY, originZ + localZ));
      }
    }
  }
  return {
    blocks: blockPlanes(values, MOB_REGION_WIDTH, MOB_REGION_DEPTH),
    originX: BigInt(originX + DOMAIN_COORDINATE_OFFSET),
    originY: BigInt(originY),
    originZ: BigInt(originZ + DOMAIN_COORDINATE_OFFSET),
    width: BigInt(MOB_REGION_WIDTH),
    height: BigInt(MOB_REGION_HEIGHT),
    depth: BigInt(MOB_REGION_DEPTH),
  };
}

export function collidesAt(world, player, x, y, z) {
  const region = collisionRegion(world, x, y, z);
  return PlayerDomain.collides(
    stateRaw(player),
    x + DOMAIN_COORDINATE_OFFSET,
    y,
    z + DOMAIN_COORDINATE_OFFSET,
    region.blocks,
    BigInt(region.originX),
    BigInt(region.originY),
    BigInt(region.originZ),
    BigInt(COLLISION_WIDTH),
    BigInt(COLLISION_HEIGHT),
    BigInt(COLLISION_DEPTH),
  );
}

export function lavaContact(world, player) {
  const region = collisionRegion(world, player.x, player.y, player.z);
  return PlayerDomain.lava_contact(region.cells);
}

export function waterContact(world, player) {
  const region = collisionRegion(world, player.x, player.y, player.z);
  return PlayerDomain.water_contact(region.cells);
}

export function isHeadUnderwater(world, player) {
  return world.blockAt(Math.floor(player.x), Math.floor(player.y + 1.62), Math.floor(player.z)) === 7;
}

export function isInWater(world, player) {
  return world.blockAt(Math.floor(player.x), Math.floor(player.y + 0.4), Math.floor(player.z)) === 7
    || isHeadUnderwater(world, player);
}

export function waterCurrentPush(flows, x, y, z) {
  const current = FluidsDomain.current(flows, x, y, z);
  return [
    Number(FluidsDomain.current_x(current)),
    Number(FluidsDomain.current_z(current)),
  ];
}

export function overlapsPlayer(player, x, y, z) {
  return PlayerDomain.overlaps(
    stateRaw(player),
    BigInt(x) + BigInt(DOMAIN_COORDINATE_OFFSET),
    BigInt(y),
    BigInt(z) + BigInt(DOMAIN_COORDINATE_OFFSET),
  );
}

export function isPlayerAlive(player) {
  return PlayerDomain.alive(stateRaw(player));
}

export function applyDamage(player, amount) {
  if (!isPlayerAlive(player)) return player.health;
  const raw = PlayerDomain.damage(stateRaw(player), amount);
  Object.assign(player, stateView(raw));
  PLAYER_STATES.set(player, raw);
  return player.health;
}

export function applyLavaDamage(player, dt) {
  const raw = PlayerDomain.lava_damage(stateRaw(player), dt);
  Object.assign(player, stateView(raw));
  PLAYER_STATES.set(player, raw);
  return player.health;
}

export function eatFood(player, nutrition) {
  const raw = PlayerDomain.eat(stateRaw(player), nutrition);
  Object.assign(player, stateView(raw));
  PLAYER_STATES.set(player, raw);
  return player.hunger;
}

export function applyPoison(player, seconds) {
  const raw = PlayerDomain.poison_tick(stateRaw(player), seconds);
  Object.assign(player, stateView(raw));
  PLAYER_STATES.set(player, raw);
  return player.poison;
}

export function cameraDirection(player) {
  const direction = PlayerDomain.direction(stateRaw(player));
  return [Number(direction.x), Number(direction.y), Number(direction.z)];
}

export function raycast(world, player) {
  const rayWidth = 17;
  const rayDepth = 17;
  const rayHeight = world.maxY + 16;
  const originX = Math.floor(player.x) - 8;
  const originZ = Math.floor(player.z) - 8;
  const values = [];
  for (let y = 0; y < rayHeight; y += 1) {
    for (let z = 0; z < rayDepth; z += 1) {
      for (let x = 0; x < rayWidth; x += 1) {
        values.push(y < world.maxY
          ? world.blockAt(originX + x, y, originZ + z)
          : 0);
      }
    }
  }
  const result = PlayerDomain.raycast(
    stateRaw(player),
    blockPlanes(values, rayWidth, rayDepth),
    BigInt(originX + DOMAIN_COORDINATE_OFFSET),
    0n,
    BigInt(originZ + DOMAIN_COORDINATE_OFFSET),
    BigInt(rayWidth),
    BigInt(rayHeight),
    BigInt(rayDepth),
  );
  if (result.$ !== "Hit") return null;
  return {
    hit: [Number(result.hit_x) - DOMAIN_COORDINATE_OFFSET, Number(result.hit_y), Number(result.hit_z) - DOMAIN_COORDINATE_OFFSET],
    place: result.has_place
      ? [Number(result.place_x) - DOMAIN_COORDINATE_OFFSET, Number(result.place_y), Number(result.place_z) - DOMAIN_COORDINATE_OFFSET]
      : null,
  };
}

export function respawnPlayer(player, spawnCell, spawnHeight) {
  const respawned = PlayerDomain.create(
    BigInt(spawnCell[0]) + BigInt(DOMAIN_COORDINATE_OFFSET),
    BigInt(spawnCell[1]) + BigInt(DOMAIN_COORDINATE_OFFSET),
    BigInt(spawnHeight),
  );
  Object.assign(player, stateView(respawned));
  PLAYER_STATES.set(player, respawned);
}

/** Puts the player at a position the server corrected it to, at rest. */
export function placePlayer(player, x, y, z) {
  Object.assign(player, { x, y, z, velocityY: 0, fall: 0 });
  PLAYER_STATES.delete(player);
}

export function movePlayer(world, player, held, dt, spawnCell, spawnHeight, width = 48, depth = 48, controls = {}) {
  if (Number(player.health) <= 0) {
    return;
  }
  let keys = 0;
  if (held.has("KeyW")) keys |= 1;
  if (held.has("KeyA")) keys |= 2;
  if (held.has("KeyS")) keys |= 4;
  if (held.has("KeyD")) keys |= 8;
  if (held.has("Space")) keys |= 16;
  if (isSprinting(held, controls)) keys |= 32;
  if (isSneaking(held, controls)) keys |= 64;

  const region = collisionRegion(world, player.x, player.y, player.z);
  const raw = PlayerDomain.step(
    stateRaw(player),
    keys,
    dt,
    region.blocks,
    BigInt(region.originX),
    BigInt(region.originY),
    BigInt(region.originZ),
    BigInt(COLLISION_WIDTH),
    BigInt(COLLISION_HEIGHT),
    BigInt(COLLISION_DEPTH),
    BigInt(spawnCell[0]) + BigInt(DOMAIN_COORDINATE_OFFSET),
    BigInt(spawnCell[1]) + BigInt(DOMAIN_COORDINATE_OFFSET),
    BigInt(spawnHeight),
  );
  const next = stateView(raw);
  Object.assign(player, next);
  PLAYER_STATES.set(player, raw);
}
