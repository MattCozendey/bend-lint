import assert from "node:assert/strict";
import {
  cameraDirection,
  applyLavaDamage,
  collidesAt,
  createPlayer,
  createWorldState,
  isHeadUnderwater,
  isInWater,
  isSneaking,
  isSprinting,
  mobRegion,
  lavaContact,
  movePlayer,
  overlapsPlayer,
  raycast,
  respawnPlayer,
  waterContact,
  waterCurrentPush,
} from "../web/game-state.js";

const world = createWorldState(6, 6, 6);
for (let z = 0; z < 6; z += 1) {
  for (let x = 0; x < 6; x += 1) world.setBlock(x, 0, z, 1);
}
world.setBlock(3, 1, 2, 1);
world.setBlock(2, 2, 1, 1);
world.setBlock(4, 1, 4, 7);

const player = createPlayer([2, 2], 1);
assert.equal(collidesAt(world, player, 2.5, 1, 2.5), false);
assert.equal(collidesAt(world, player, 4.5, 1, 4.5), false);
assert.equal(overlapsPlayer(player, 2, 1, 2), true);

const region = mobRegion(world, 2.5, 1.2, 2.5);
assert.equal(region.width, 5n);
assert.equal(region.height, 6n);
assert.equal(region.depth, 5n);
// The region is a list of y-planes, so the cell count is the sum over the planes.
// Both numbers are asserted: 6 planes is the layout `Player.region_block` reads, and
// 150 cells is the window those planes have to cover between them.
let regionPlanes = 0;
let regionCells = 0;
for (let plane = region.blocks; plane?.$ === "Con"; plane = plane.tail) {
  regionPlanes += 1;
  for (let cell = plane.head; cell?.$ === "Con"; cell = cell.tail) regionCells += 1;
}
assert.equal(regionPlanes, 6);
assert.equal(regionCells, 150);
player.health = 0;
movePlayer(world, player, new Set(), 0.016, [2, 2], 1);
assert.equal(player.health, 0);
respawnPlayer(player, [2, 2], 1);
assert.equal(player.health, 20);
assert.ok(Math.abs(player.x - 2.5) < 0.001);

const lavaWorld = createWorldState(6, 6, 6);
lavaWorld.setBlock(2, 0, 2, 1);
lavaWorld.setBlock(2, 1, 2, 21);
const lavaPlayer = createPlayer([2, 2], 1);
assert.equal(lavaContact(lavaWorld, lavaPlayer), true);
applyLavaDamage(lavaPlayer, 0.5);
assert.equal(lavaPlayer.health, 18);

const freeWorld = createWorldState(8, 8, 6);
for (let z = 0; z < 8; z += 1) for (let x = 0; x < 8; x += 1) freeWorld.setBlock(x, 0, z, 1);
const freePlayer = createPlayer([3, 3], 1);
movePlayer(freeWorld, freePlayer, new Set(["KeyW"]), 0.2, [3, 3], 1);
assert.ok(freePlayer.z < 3.5);

// Diagonal movement uses small per-tick displacements. With single-precision
// domain coordinates the F32 step must stay well above the float grid,
// otherwise W at 45 degrees freezes while cardinals keep moving.
const diagPlayer = createPlayer([3, 3], 1);
diagPlayer.x = 3.5;
diagPlayer.y = 1.05;
diagPlayer.z = 3.5;
diagPlayer.yaw = Math.PI / 4;
diagPlayer.pitch = 0;
diagPlayer.velocityY = 0;
diagPlayer.grounded = true;
for (let i = 0; i < 12; i += 1) {
  movePlayer(freeWorld, diagPlayer, new Set(["KeyW"]), 1 / 60, [3, 3], 1);
}
assert.ok(diagPlayer.x - 3.5 > 0.3, `diagonal W must move +x, got ${diagPlayer.x - 3.5}`);
assert.ok(3.5 - diagPlayer.z > 0.3, `diagonal W must move -z, got ${3.5 - diagPlayer.z}`);

movePlayer(world, player, new Set(["KeyD"]), 0.05, [2, 2], 1);
assert.equal(player.x, 2.5);

for (let i = 0; i < 20; i += 1) {
  movePlayer(world, player, new Set(), 0.05, [2, 2], 1);
}
assert.equal(player.grounded, true);
assert.equal(player.y, 1);

const direction = cameraDirection(player);
assert.ok(direction[2] < 0);
const hit = raycast(world, player);
assert.deepEqual(hit?.hit, [2, 2, 1]);

const jumpWorld = createWorldState(4, 4, 4);
for (let z = 0; z < 4; z += 1) {
  for (let x = 0; x < 4; x += 1) jumpWorld.setBlock(x, 0, z, 1);
}
const heldJumpPlayer = createPlayer([1, 1], 1);
heldJumpPlayer.y = 1.2;
heldJumpPlayer.velocityY = -2;
const heldSpace = new Set(["Space"]);
for (let i = 0; i < 60 && !heldJumpPlayer.grounded; i += 1) {
  movePlayer(jumpWorld, heldJumpPlayer, heldSpace, 0.016, [1, 1], 1);
}
assert.equal(heldJumpPlayer.grounded, true);
movePlayer(jumpWorld, heldJumpPlayer, heldSpace, 0.016, [1, 1], 1);
assert.equal(heldJumpPlayer.grounded, false);
assert.ok(heldJumpPlayer.velocityY > 0);

assert.equal(isSprinting(new Set(["ControlLeft"])), true);
assert.equal(isSprinting(new Set(["ControlRight"])), true);
assert.equal(isSprinting(new Set(["ShiftLeft"])), false);
assert.equal(isSneaking(new Set(["ShiftLeft"])), true);
assert.equal(isSneaking(new Set(["ShiftRight"])), true);
assert.equal(isSneaking(new Set(["ControlLeft"])), false);

const sneakWorld = createWorldState(8, 8, 6);
for (let z = 0; z < 8; z += 1) for (let x = 0; x < 8; x += 1) sneakWorld.setBlock(x, 0, z, 1);
const sneakWalker = createPlayer([3, 3], 1);
const sneakSneaker = createPlayer([3, 3], 1);
const sneakRunner = createPlayer([3, 3], 1);
for (let i = 0; i < 30; i += 1) {
  movePlayer(sneakWorld, sneakWalker, new Set(["KeyW"]), 0.016, [3, 3], 1);
  movePlayer(sneakWorld, sneakSneaker, new Set(["KeyW", "ShiftLeft"]), 0.016, [3, 3], 1);
  movePlayer(sneakWorld, sneakRunner, new Set(["KeyW", "ControlLeft"]), 0.016, [3, 3], 1);
}
assert.ok(3.5 - sneakSneaker.z < (3.5 - sneakWalker.z) * 0.75, "Shift must sneak slower than walk");
assert.ok(3.5 - sneakRunner.z > (3.5 - sneakWalker.z) * 1.25, "Ctrl must sprint faster than walk");

// Water detection, swim-up and current push (adapter over Bend water rules).
const poolWorld = createWorldState(8, 8, 6);
for (let z = 0; z < 8; z += 1) for (let x = 0; x < 8; x += 1) poolWorld.setBlock(x, 0, z, 1);
for (let z = 2; z < 6; z += 1) for (let x = 2; x < 6; x += 1) {
  poolWorld.setBlock(x, 1, z, 7);
  poolWorld.setBlock(x, 2, z, 7);
}
const swimmer = createPlayer([3, 3], 1);
swimmer.x = 3.5;
swimmer.y = 1.1;
swimmer.z = 3.5;
swimmer.velocityY = 0;
swimmer.grounded = false;
assert.equal(isInWater(poolWorld, swimmer), true);
assert.equal(isHeadUnderwater(poolWorld, swimmer), true);
assert.equal(waterContact(poolWorld, swimmer), true);
const sankStart = swimmer.y;
for (let i = 0; i < 30; i += 1) {
  movePlayer(poolWorld, swimmer, new Set(), 0.016, [3, 3], 1);
}
assert.ok(swimmer.y > sankStart - 1.2, "water must slow sinking");
const floater = createPlayer([3, 3], 1);
floater.x = 3.5;
floater.y = 1.1;
floater.z = 3.5;
floater.velocityY = 0;
floater.grounded = false;
for (let i = 0; i < 30; i += 1) {
  movePlayer(poolWorld, floater, new Set(["Space"]), 0.016, [3, 3], 1);
}
assert.ok(floater.y > 1.1, `Space must swim up, y=${floater.y}`);
// The head needs its tag: since 2.0.27 the loader checks the constructor name
// of a host value, and `Flow` is one of `fluids.bend`'s own types, so it is
// spelled bare here.
const flows = {
  $: "Con",
  head: { $: "Flow", x: 2n, y: 1n, z: 3n, level: 8, source: false, block: 7 },
  tail: { $: "Nil" },
};
const [pushX, pushZ] = waterCurrentPush(flows, 3.5, 1.1, 3.0);
assert.ok(pushX > 0, `current must push away from high-level flow, got ${pushX}`);
assert.deepEqual(waterCurrentPush({ $: "Nil" }, 3.5, 1.1, 3.0), [0, 0]);
console.log("game state ok");
