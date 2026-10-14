import assert from "node:assert/strict";
import { Entities, World } from "../web/bend-modules.js";
import { bendList, bendPlanes, listValues } from "../web/bend-list.js";
import { mobBox, rayHitBox } from "../web/aim.js";
import { mobHeight } from "../web/mob-kinds.js";

// The Region record is a Bend ADT, so it can only be built field by field. Three
// builders below need it, and one list fold serves all of them, so the shape lives
// here instead of drifting across the copies.
const REGION_SIZE = { width: 5, height: 6, depth: 5 };
const PLANE_CELLS = REGION_SIZE.width * REGION_SIZE.depth;

// `values` arrives in the region's own cell order, y-major, so the plane at height
// `y` is the slice of `PLANE_CELLS` cells starting at `y * PLANE_CELLS`.
function bendRegion(originX, originY, originZ, values) {
  return {
    $: "Region",
    blocks: bendPlanes(values, PLANE_CELLS),
    origin_x: BigInt(originX),
    origin_y: BigInt(originY),
    origin_z: BigInt(originZ),
    width: BigInt(REGION_SIZE.width),
    height: BigInt(REGION_SIZE.height),
    depth: BigInt(REGION_SIZE.depth),
  };
}

const regionList = bendList;

function flatRegion(originX, originY, originZ, wallX = null) {
  const values = [];
  for (let ly = 0; ly < REGION_SIZE.height; ly += 1) {
    for (let lz = 0; lz < REGION_SIZE.depth; lz += 1) {
      for (let lx = 0; lx < REGION_SIZE.width; lx += 1) {
        const wx = originX + lx;
        const wy = originY + ly;
        values.push(wy === 0 || (wallX !== null && wx === wallX && wy <= 3) ? 1 : 0);
      }
    }
  }
  return bendRegion(originX, originY, originZ, values);
}

function airRegions(count) {
  const cells = REGION_SIZE.width * REGION_SIZE.height * REGION_SIZE.depth;
  const region = bendRegion(0, 0, 0, new Array(cells).fill(0));
  return bendList(new Array(count).fill(region));
}

// Melee line-of-sight needs the same small block window the browser already
// builds for `step_world`: the mob cell plus two cells of slack on each side.
function meleeRegion(mobX, mobY, mobZ, isSolid = () => false) {
  const originX = Math.max(0, Math.floor(mobX) - 2);
  const originY = Math.max(0, Math.floor(mobY) - 2);
  const originZ = Math.max(0, Math.floor(mobZ) - 2);
  const values = [];
  for (let ly = 0; ly < REGION_SIZE.height; ly += 1) {
    for (let lz = 0; lz < REGION_SIZE.depth; lz += 1) {
      for (let lx = 0; lx < REGION_SIZE.width; lx += 1) {
        values.push(isSolid(originX + lx, originY + ly, originZ + lz) ? 1 : 0);
      }
    }
  }
  return bendRegion(originX, originY, originZ, values);
}

function regionListFor(list) {
  return regionList(listValues(list).map((mob) => meleeRegion(Number(mob.x), Number(mob.y), Number(mob.z))));
}

const mobState = Entities.spawn(1337n, 0.0, 0n, 0n, 80n, 80n);
const mobs = listValues(mobState);
assert.ok(mobs.length > 0);
assert.ok(mobs.every((mob) => mob.$ === "Mob" && mob.alive === true && Number(mob.panic) === 0));
assert.ok(mobs.every((mob) => Number(mob.health) === (Number(mob.kind) === 4 ? 40 : 20)));
assert.ok(new Set(mobs.map((mob) => Number(mob.kind))).size >= 1);
const peacefulMobs = listValues(Entities.spawn_for_mode(1337n, 0.0, 0n, 0n, 80n, 80n, true));
assert.ok(peacefulMobs.length > 0);
assert.ok(peacefulMobs.length < mobs.length);
assert.ok(peacefulMobs.every((mob) => Entities.kind_is_animal(Number(mob.kind))));
assert.ok(peacefulMobs.every((mob) => !Entities.hostile_kind(Number(mob.kind), true)));
const protectedMobs = listValues(Entities.spawn_for_player(1337n, 0.0, 0n, 0n, 80n, 80n, 40n, 0n, false));
assert.ok(protectedMobs.every((mob) => !(Number(mob.x) === 40.5 && Number(mob.z) === 0.5)));
const safeAreaMobs = listValues(Entities.spawn_for_player(1337n, 0.0, 0n, 0n, 80n, 80n, 40n, 24n, false));
assert.ok(safeAreaMobs.every((mob) => (
  Math.abs(Number(mob.x) - 40.5) > 8.1
    || Math.abs(Number(mob.z) - 24.5) > 8.1
)));
const safeWorldMobs = listValues(Entities.spawn_for_player(1337n, 0.0, 0n, 0n, 48n, 48n, 40n, 24n, false));
assert.ok(safeWorldMobs.every((mob) => (
  Math.abs(Number(mob.x) - 40.5) > 8.1
    || Math.abs(Number(mob.z) - 24.5) > 8.1
)));
// Hostile spawn must respect sunlight. The open surface is fully lit during the
// day, so a hostile may only appear where the sky is blocked, or once night
// falls. A farm animal is the opposite case: it never burns, so it has to be
// allowed to stand in the open, which is the only place a player meets one.
const daySpawn = listValues(Entities.spawn(1337n, 1.0, 0n, 0n, 80n, 80n));
const nightSpawn = listValues(Entities.spawn(1337n, 0.0, 0n, 0n, 80n, 80n));
assert.ok(nightSpawn.length > 0);
assert.ok(daySpawn.length < nightSpawn.length);
assert.ok(daySpawn.every((mob) => !Entities.hostile_kind(Number(mob.kind), true)
  || !Entities.sun_exposed_generated(1337n, Number(mob.x), Number(mob.y), Number(mob.z))));
assert.ok(daySpawn.some((mob) => Entities.sun_exposed_generated(
  1337n,
  Number(mob.x),
  Number(mob.y),
  Number(mob.z),
)), "daylight must still be populated by animals standing in the open");
// A mob standing in the open at noon is lit, so a hostile daytime spawn there
// would burn on the first tick. Hostile spawns must therefore be shaded.
assert.ok(Entities.sun_exposed_generated(1337n, 40.5, 64.0, 40.5));
// The whole world is 48x48. On a coarse spawn grid a player could meet a single
// mob, or none at all, and none of the farm animals; the population has to be
// big enough to run into a pig, a cow, a sheep and a chicken.
const worldSpawn = listValues(Entities.spawn_for_player(1337n, 1.0, 0n, 0n, 48n, 48n, 40n, 24n, false));
const nightWorldSpawn = listValues(Entities.spawn_for_player(1337n, 0.0, 0n, 0n, 48n, 48n, 40n, 24n, false));
assert.ok(worldSpawn.length >= 6, `a 48x48 world needs a real population, got ${worldSpawn.length}`);
assert.ok(worldSpawn.every((mob) => Entities.kind_is_animal(Number(mob.kind))),
  'daylight fills the open surface with animals, never with a monster that would burn on the first tick');
assert.ok(nightWorldSpawn.some((mob) => Entities.hostile_kind(Number(mob.kind), true)),
  'nightfall is what puts a monster on the map');

const crowded = {
  $: "Con",
  head: Entities.make_mob(90n, 2, 40.5, 8.0, 24.5, 20.0, true),
  tail: {
    $: "Con",
    head: Entities.make_mob(91n, 1, 12.5, 8.0, 12.5, 20.0, true),
    tail: { $: "Nil" },
  },
};
const respawnSafe = listValues(Entities.remove_spawn_area(crowded, 40n, 24n));
assert.deepEqual(respawnSafe.map((mob) => Number(mob.id)), [91]);

const steppedRegions = airRegions(mobs.length);
const stepped = listValues(Entities.step_world(Entities.spawn(1337n, 0.0, 0n, 0n, 80n, 80n), 40.5, 40.5, 1.0, 3.0, 0n, steppedRegions));
assert.equal(stepped.length, mobs.length);

const budgetedInput = {
  $: "Con",
  head: Entities.make_mob(1n, 2, 10.0, 8.0, 0.5, 20.0, true),
  tail: {
    $: "Con",
    head: Entities.make_mob(2n, 2, 100.0, 8.0, 0.5, 20.0, true),
    tail: { $: "Nil" },
  },
};
const budgeted = listValues(Entities.step_budgeted(budgetedInput, 0.0, 0.5, 1.0, 32.0));
assert.ok(Number(budgeted[0].x) < 10.0);
assert.ok(Number(budgeted[1].x) < 100.0);
assert.ok(10.0 - Number(budgeted[0].x) > 100.0 - Number(budgeted[1].x));

const drop = Entities.drop_for(budgeted[0]);
const dropState = { $: "Con", head: drop, tail: { $: "Nil" } };
const ground = { $: "Con", head: { $: "Ground", x: Number(drop.x), z: Number(drop.z), y: 1.0 }, tail: { $: "Nil" } };
const fallingDrops = listValues(Entities.step_drops(dropState, 0.2, ground));
assert.ok(Number(fallingDrops[0].y) < Number(drop.y));
let landedDrops = dropState;
for (let index = 0; index < 20; index += 1) landedDrops = Entities.step_drops(landedDrops, 0.2, ground);
assert.equal(Number(listValues(landedDrops)[0].y), 1);
assert.equal(listValues(landedDrops)[0].settled, true);

// A drop rests on the floor of the column it is over, so the ground the host
// hands over is keyed by cell, not by the drop's exact position. The adapter
// builds one Ground per column at floor(x) + 0.5 while a drop sits at a
// fractional x, so an exact F32 match never fires and the drop falls to the
// bottom of the world instead of landing. Both the fractional and the whole
// column must settle on the same floor.
function land(columnX, columnZ, floorY) {
  const cell = { x: Math.floor(columnX) + 0.5, z: Math.floor(columnZ) + 0.5, y: floorY };
  const grounds = { $: "Con", head: { $: "Ground", ...cell }, tail: { $: "Nil" } };
  let state = { $: "Con", head: Entities.make_drop(7n, 12, columnX, floorY + 2, columnZ, 1), tail: { $: "Nil" } };
  for (let index = 0; index < 40; index += 1) state = Entities.step_drops(state, 0.05, grounds);
  const landed = listValues(state)[0];
  return { y: Number(landed.y), settled: landed.settled };
}

const fractional = land(13.27, 29.14, 8);
assert.equal(fractional.y, 8, "a drop over a fractional column must land on that column's floor");
assert.equal(fractional.settled, true, "a landed drop must report settled");
const whole = land(13, 29, 8);
assert.equal(whole.y, 8, "a whole-numbered column must land on the same floor");
assert.equal(whole.settled, true);
// The world runs on a negative domain offset, so the cell comparison has to hold
// below zero as well. A comparison routed through Nat folds every negative
// coordinate onto 0, which would land a drop in the wrong column.
for (const [label, x, z] of [["a negative fractional", -40.5, -41.25], ["a negative whole", -40, -41]]) {
  const below = land(x, z, 8);
  assert.equal(below.y, 8, `${label} column must land on its own floor`);
  assert.equal(below.settled, true, `${label} drop must report settled`);
}
// Two columns with different floors must not be confused for one another.
const neighbour = land(13.27, 30.6, 4);
assert.equal(neighbour.y, 4, "a neighbouring column keeps its own floor");
// A drop over a column with no ground entry still has to fall, not hang.
const noGround = (() => {
  let state = { $: "Con", head: Entities.make_drop(7n, 12, 40.5, 20, 40.5, 1), tail: { $: "Nil" } };
  for (let index = 0; index < 5; index += 1) state = Entities.step_drops(state, 0.05, { $: "Nil" });
  return Number(listValues(state)[0].y);
})();
assert.ok(noGround < 20, "a drop with no ground below it must keep falling");

const hostile = mobs.find((mob) => Number(mob.kind) === 2);
assert.ok(hostile);
assert.ok(Number(Entities.threat_damage(
  mobState,
  hostile.x,
  hostile.y,
  hostile.z,
  0n,
  regionListFor(mobState),
)) > 0);

const verticallySeparatedHostile = Entities.cons_mob(
  Entities.make_mob(3001n, 2, 0.5, 5.0, 0.5, 20.0, true),
  { $: "Nil" },
);
assert.equal(
  Number(Entities.threat_damage(
    verticallySeparatedHostile,
    0.5,
    0.5,
    0.5,
    0n,
    regionList([meleeRegion(0.5, 5.0, 0.5)]),
  )),
  0,
  "a hostile must not attack through a vertical gap",
);

// Melee threat needs a world and an orientation: a hostile may only damage a
// player it can see and only from inside its attack cone. The fixture is a
// diagonal stand-off where one corner block sits between the two bodies.
const meleeMobX = 0.1;
const meleeMobY = 1.0;
const meleeMobZ = 0.5;
const meleePlayerX = 1.4;
const meleePlayerY = 1.0;
const meleePlayerZ = 1.1;
const meleeReach = Math.hypot(meleePlayerX - meleeMobX, meleePlayerZ - meleeMobZ);
assert.ok(
  meleeReach < 1.5,
  `the melee fixture must stay inside the documented radius, got ${meleeReach}`,
);
const meleeHeadingX = (meleePlayerX - meleeMobX) / meleeReach;
const meleeHeadingZ = (meleePlayerZ - meleeMobZ) / meleeReach;
const meleeOpenRegion = meleeRegion(meleeMobX, meleeMobY, meleeMobZ);
const meleeWallRegion = meleeRegion(meleeMobX, meleeMobY, meleeMobZ, (x, _y, z) => x === 1 && z === 0);

function facingHostile(id, headingX, headingZ, alive = true, kind = 2) {
  return Entities.cons_mob(
    Entities.make_mob_heading(BigInt(id), kind, meleeMobX, meleeMobY, meleeMobZ, headingX, headingZ, 20.0, alive, false, 0.0),
    { $: "Nil" },
  );
}

assert.equal(Entities.line_of_sight(
  meleeOpenRegion.blocks,
  meleeOpenRegion.origin_x,
  meleeOpenRegion.origin_y,
  meleeOpenRegion.origin_z,
  meleeOpenRegion.width,
  meleeOpenRegion.height,
  meleeOpenRegion.depth,
  meleeMobX,
  meleeMobY,
  meleeMobZ,
  meleePlayerX,
  meleePlayerY,
  meleePlayerZ,
  8n,
), true, "open air between the two bodies must stay visible");
assert.equal(Entities.line_of_sight(
  meleeWallRegion.blocks,
  meleeWallRegion.origin_x,
  meleeWallRegion.origin_y,
  meleeWallRegion.origin_z,
  meleeWallRegion.width,
  meleeWallRegion.height,
  meleeWallRegion.depth,
  meleeMobX,
  meleeMobY,
  meleeMobZ,
  meleePlayerX,
  meleePlayerY,
  meleePlayerZ,
  8n,
), false, "a corner block between the two bodies must break line of sight");

// Face-adjacent bodies share a face, so no cell sits between them: the block
// each body stands in is never treated as cover, even when it is solid.
const meleeAdjacentRegion = meleeRegion(0.5, 1.0, 0.5, (x, _y, z) => x === 1 && z === 0);
assert.equal(Entities.line_of_sight(
  meleeAdjacentRegion.blocks,
  meleeAdjacentRegion.origin_x,
  meleeAdjacentRegion.origin_y,
  meleeAdjacentRegion.origin_z,
  meleeAdjacentRegion.width,
  meleeAdjacentRegion.height,
  meleeAdjacentRegion.depth,
  0.5,
  1.0,
  0.5,
  1.5,
  1.0,
  0.5,
  8n,
), true, "the cell a body stands in must not block its own line of sight");

assert.equal(
  Number(Entities.threat_damage(
    facingHostile(5001, meleeHeadingX, meleeHeadingZ),
    meleePlayerX,
    meleePlayerY,
    meleePlayerZ,
    0n,
    regionList([meleeOpenRegion]),
  )),
  2,
  "a facing hostile in open air must deal its documented melee damage",
);
assert.equal(
  Number(Entities.threat_damage(
    facingHostile(5002, meleeHeadingX, meleeHeadingZ),
    meleePlayerX,
    meleePlayerY,
    meleePlayerZ,
    0n,
    regionList([meleeWallRegion]),
  )),
  0,
  "a hostile must not attack through a solid block",
);
assert.equal(
  Number(Entities.threat_damage(
    facingHostile(5003, -meleeHeadingX, -meleeHeadingZ),
    meleePlayerX,
    meleePlayerY,
    meleePlayerZ,
    0n,
    regionList([meleeOpenRegion]),
  )),
  0,
  "a hostile facing away from the player must not deal melee damage",
);
assert.equal(
  Number(Entities.threat_damage(
    facingHostile(5004, meleeHeadingX, meleeHeadingZ, false),
    meleePlayerX,
    meleePlayerY,
    meleePlayerZ,
    0n,
    regionList([meleeOpenRegion]),
  )),
  0,
  "a dead hostile must not deal melee damage on a later tick",
);
// The brute owns a wider cone, so a heavy mob still connects off-axis. The
// fixture is rotated 70 degrees off the player: outside the hostile cone,
// inside the brute cone.
const offAxis = 1.2217;
const rotateHeading = (radians) => [
  Math.cos(radians) * meleeHeadingX - Math.sin(radians) * meleeHeadingZ,
  Math.sin(radians) * meleeHeadingX + Math.cos(radians) * meleeHeadingZ,
];
const [bruteHeadingX, bruteHeadingZ] = rotateHeading(offAxis);
const [backBruteHeadingX, backBruteHeadingZ] = rotateHeading(Math.PI);
assert.ok(
  bruteHeadingX * meleeHeadingX + bruteHeadingZ * meleeHeadingZ < Entities.attack_cone_cosine(2),
  "the brute fixture must sit outside the hostile cone",
);
assert.ok(
  bruteHeadingX * meleeHeadingX + bruteHeadingZ * meleeHeadingZ >= Entities.attack_cone_cosine(4),
  "the brute cone must be wider than the hostile cone",
);
assert.equal(
  Number(Entities.threat_damage(
    facingHostile(5005, bruteHeadingX, bruteHeadingZ, true, 4),
    meleePlayerX,
    meleePlayerY,
    meleePlayerZ,
    0n,
    regionList([meleeOpenRegion]),
  )),
  4,
  "the brute must connect inside its wider cone",
);
assert.equal(
  Number(Entities.threat_damage(
    facingHostile(5006, backBruteHeadingX, backBruteHeadingZ, true, 4),
    meleePlayerX,
    meleePlayerY,
    meleePlayerZ,
    0n,
    regionList([meleeOpenRegion]),
  )),
  0,
  "the brute must not connect behind itself",
);
// A one-block step under the line of sight is not a wall: the eye ray runs
// above the feet, so a mob on the ground must still hit a player on the step.
const meleeStepRegion = meleeRegion(2.5, 1.0, 2.5, (x, y) => x === 3 && y === 1);
assert.equal(
  Number(Entities.threat_damage(
    Entities.cons_mob(
      Entities.make_mob_heading(5007n, 2, 2.5, 1.0, 2.5, 1.0, 0.0, 20.0, true, false, 0.0),
      { $: "Nil" },
    ),
    3.5,
    2.0,
    2.5,
    0n,
    regionList([meleeStepRegion]),
  )),
  2,
  "a solid step below eye level must not block melee",
);

const targetId = Number(mobs[0].id);
const firstTarget = mobs[0];
const attacked = Entities.attack(
  Entities.spawn(1337n, 0.0, 0n, 0n, 80n, 80n),
  BigInt(targetId),
  4.0,
  firstTarget.x,
  firstTarget.y,
  firstTarget.z,
  4.0,
  { $: "Nil" },
);
assert.equal(attacked.hit, true);

const outOfRangeTarget = {
  $: "Con",
  head: Entities.make_mob(4001n, 2, 0.5, 8.0, 0.5, 20.0, true),
  tail: { $: "Nil" },
};
const outOfRangeAttack = Entities.attack(outOfRangeTarget, 4001n, 4.0, 0.0, 0.0, 0.5, 4.0, { $: "Nil" });
assert.equal(outOfRangeAttack.hit, false, "vertical melee range must be enforced by Bend");
assert.equal(Number(listValues(outOfRangeAttack.mobs)[0].health), 20);
const distantTarget = {
  $: "Con",
  head: Entities.make_mob(4002n, 2, 6.5, 0.0, 0.5, 20.0, true),
  tail: { $: "Nil" },
};
const distantAttack = Entities.attack(distantTarget, 4002n, 4.0, 0.0, 0.0, 0.5, 4.0, { $: "Nil" });
assert.equal(distantAttack.hit, false, "horizontal melee range must be enforced by Bend");
const rangedTarget = {
  $: "Con",
  head: Entities.make_mob(4003n, 2, 10.5, 0.0, 0.5, 20.0, true),
  tail: { $: "Nil" },
};
const rangedAttack = Entities.attack(rangedTarget, 4003n, 6.0, 0.0, 0.0, 0.5, 16.0, { $: "Nil" });
assert.equal(rangedAttack.hit, true, "ranged attacks must use their explicit reach");
assert.equal(Number(listValues(rangedAttack.mobs)[0].health), 14);
assert.equal(Number(listValues(attacked.mobs)[0].health), 16);
let killed = Entities.spawn(1337n, 0.0, 0n, 0n, 80n, 80n);
let killedResult = null;
for (let index = 0; index < 5; index += 1) {
  const currentTarget = listValues(killed).find((mob) => Number(mob.id) === targetId);
  killedResult = Entities.attack(
    killed,
    BigInt(targetId),
    4.0,
    currentTarget.x,
    currentTarget.y,
    currentTarget.z,
    4.0,
    { $: "Nil" },
  );
  killed = killedResult.mobs;
}
assert.equal(killedResult.drops.$, "Con");
assert.ok([12, 13].includes(Number(killedResult.drops.head.item)));
const deadTarget = listValues(killed).find((mob) => Number(mob.id) === targetId);
const deadDropCount = listValues(killedResult.drops).length;
const repeatAttack = Entities.attack(
  killed,
  BigInt(targetId),
  4.0,
  deadTarget.x,
  deadTarget.y,
  deadTarget.z,
  4.0,
  killedResult.drops,
);
assert.equal(repeatAttack.hit, false, "a dead mob must not be hit again");
assert.equal(Number(listValues(repeatAttack.mobs).find((mob) => Number(mob.id) === targetId).health), 0);
assert.equal(listValues(repeatAttack.drops).length, deadDropCount, "a dead mob must not create duplicate drops");

// Existing drops survive attacks, including one that kills.
const secondId = Number(listValues(killed)[1].id);
const oldDrop = Entities.drop_for(listValues(killed)[1]);
const priorDrops = { $: "Con", head: oldDrop, tail: { $: "Nil" } };
let preserving = null;
let preservingMobs = killed;
for (let index = 0; index < 5; index += 1) {
  const currentTarget = listValues(preservingMobs).find((mob) => Number(mob.id) === secondId);
  preserving = Entities.attack(
    preservingMobs,
    BigInt(secondId),
    4.0,
    currentTarget.x,
    currentTarget.y,
    currentTarget.z,
    4.0,
    index === 0 ? priorDrops : preserving.drops,
  );
  preservingMobs = preserving.mobs;
}
assert.equal(listValues(preserving.drops).length, 2);

// Knockback pushes the target away from the attacker.
const loneVictim = {
  $: "Con",
  head: Entities.make_mob(11n, 2, 10.5, 1.0, 2.5, 20.0, true),
  tail: { $: "Nil" },
};
const pushed = Entities.attack(loneVictim, 11n, 4.0, 7.0, 1.0, 2.5, 4.0, { $: "Nil" });
assert.equal(pushed.hit, true);
assert.ok(Number(listValues(pushed.mobs)[0].x) > 10.5);

// Hostile walks toward the player on flat ground and stays grounded.
const openChaser = {
  $: "Con",
  head: Entities.make_mob(12n, 2, 10.5, 1.0, 2.5, 20.0, true),
  tail: { $: "Nil" },
};
const openChaserRegions = {
  $: "Con",
  head: flatRegion(8, 0, 0),
  tail: { $: "Nil" },
};
let chase = openChaser;
for (let index = 0; index < 5; index += 1) {
  chase = Entities.step_world(chase, 0.0, 2.5, 0.2, 1.0, 0n, openChaserRegions);
}
const chaser = listValues(chase)[0];
assert.ok(Number(chaser.x) < 10.5);
assert.equal(Number(chaser.y), 1);
assert.ok(Number(chaser.heading_x) < -0.99);
assert.ok(Math.abs(Number(chaser.heading_z)) < 0.01);

// A wall stops the chase: no clipping through.
const walledChaser = {
  $: "Con",
  head: Entities.make_mob(13n, 2, 10.5, 1.0, 2.5, 20.0, true),
  tail: { $: "Nil" },
};
const walledRegion = {
  $: "Con",
  head: flatRegion(8, 0, 0, 9),
  tail: { $: "Nil" },
};
let blocked = walledChaser;
for (let index = 0; index < 10; index += 1) {
  blocked = Entities.step_world(blocked, 0.0, 2.5, 0.2, 1.0, 0n, walledRegion);
}
const stopped = listValues(blocked)[0];
assert.ok(Number(stopped.x) < 10.5);
assert.ok(Number(stopped.x) > 9.5);
assert.equal(Number(stopped.y), 1);

// Falling mobs snap to the floor instead of hovering.
const fallingMob = {
  $: "Con",
  head: Entities.make_mob(14n, 2, 10.5, 5.0, 2.5, 20.0, true),
  tail: { $: "Nil" },
};
const landed = listValues(Entities.step_world(fallingMob, 0.0, 2.5, 0.2, 1.0, 0n, openChaserRegions))[0];
assert.equal(Number(landed.y), 1);

// Passive mobs wander instead of standing still.
const grazer = {
  $: "Con",
  head: Entities.make_mob(15n, 1, 5.5, 1.0, 2.5, 20.0, true),
  tail: { $: "Nil" },
};
const grazeRegion = {
  $: "Con",
  head: flatRegion(3, 0, 0),
  tail: { $: "Nil" },
};
const grazedEarly = listValues(Entities.step_world(grazer, 0.0, 2.5, 0.2, 0.0, 0n, grazeRegion))[0];
const grazedLate = listValues(Entities.step_world(grazer, 0.0, 2.5, 0.2, 3.0, 0n, grazeRegion))[0];
assert.ok(Math.abs(Number(grazedEarly.x) - 5.5) + Math.abs(Number(grazedEarly.z) - 2.5) > 0.01);
assert.ok(Math.abs(Number(grazedLate.x) - Number(grazedEarly.x)) + Math.abs(Number(grazedLate.z) - Number(grazedEarly.z)) > 0.01);

// A one-block ledge is climbed, not treated as a wall.
function ledgeRegion() {
  const values = [];
  for (let ly = 0; ly < 6; ly += 1) {
    for (let lz = 0; lz < 5; lz += 1) {
      for (let lx = 0; lx < 5; lx += 1) {
        const wx = 4 + lx;
        const wy = ly;
        values.push(wy === 0 || (wx === 5 && wy === 1) ? 1 : 0);
      }
    }
  }
  return {
    $: "Con",
    head: {
      $: "Region",
      blocks: bendPlanes(values, 5 * 5),
      origin_x: 4n,
      origin_y: 0n,
      origin_z: 0n,
      width: 5n,
      height: 6n,
      depth: 5n,
    },
    tail: { $: "Nil" },
  };
}

const climber = {
  $: "Con",
  head: Entities.make_mob(16n, 2, 7.5, 1.0, 2.5, 20.0, true),
  tail: { $: "Nil" },
};
let climbing = climber;
for (let index = 0; index < 12; index += 1) {
  climbing = Entities.step_world(climbing, 0.0, 2.5, 0.2, 1.0, 0n, ledgeRegion());
}
const climbed = listValues(climbing)[0];
assert.ok(Number(climbed.x) < 7.5);
assert.equal(Number(climbed.y), 2);
const deathDrop = Entities.make_drop(999n, 5, 3.5, 2.5, 3.5, 8);
assert.equal(deathDrop.$, 'Drop');
assert.equal(Number(deathDrop.item), 5);
assert.equal(Number(deathDrop.amount), 8);
const scattered = Entities.cons_drop(deathDrop, Entities.empty_drops());
assert.equal(Entities.remove_drop(scattered, 999n).$, 'Nil');
console.log('death drops ok');

// Distinct AI: brutes threaten harder, skittish flee, despawn clears the far.
const brute = Entities.make_mob(1001n, 4, 10.5, 1.0, 10.5, 40.0, true);
const skittish = Entities.make_mob(1002n, 3, 20.5, 1.0, 20.5, 20.0, true);
assert.equal(Number(Entities.drop_for(brute).item), 13);
assert.equal(Number(Entities.drop_for(skittish).item), 12);
assert.equal(Number(Entities.threat_damage(
  Entities.cons_mob(brute, { $: "Nil" }),
  10.5,
  1.0,
  10.5,
  0n,
  regionList([meleeRegion(10.5, 1.0, 10.5)]),
)), 4);
assert.equal(Number(Entities.threat_damage(
  Entities.cons_mob(skittish, { $: "Nil" }),
  20.5,
  1.0,
  20.5,
  0n,
  regionList([meleeRegion(20.5, 1.0, 20.5)]),
)), 0);
const mixed = Entities.cons_mob(skittish, Entities.cons_mob(brute, { $: "Nil" }));
assert.equal(Number(Entities.threat_damage(
  mixed,
  10.5,
  1.0,
  10.5,
  0n,
  regionList([meleeRegion(20.5, 1.0, 20.5), meleeRegion(10.5, 1.0, 10.5)]),
)), 4);
const kept = Entities.despawn(mixed, 10.5, 10.5, 48.0);
assert.equal(Number(Entities.count_alive(kept, 0n)), 2);
const cleared = Entities.despawn(mixed, 500.5, 500.5, 48.0);
assert.equal(Number(Entities.count_alive(cleared, 0n)), 0);
const deadFar = Entities.cons_mob(
  Entities.make_mob(1003n, 2, 500.5, 1.0, 500.5, 0.0, false),
  { $: "Nil" },
);
assert.equal(Entities.despawn(deadFar, 0.0, 0.0, 48.0).$, "Nil", "dead records must not accumulate forever");
const fled = Entities.step_budgeted(Entities.cons_mob(skittish, { $: "Nil" }), 20.5, 25.5, 1.0, 64.0);
assert.ok(Math.abs(20.5 - Number(fled.head.z)) <= 0.4 + 1e-6,
  `an unstruck animal must wander, not flee, z=${Number(fled.head.z)}`);
console.log('mob AI ok');

// The roster: 1 pig, 2 zombie, 3 sheep, 4 brute, 5 cow, 6 chicken. A farm animal
// walks around, never touches the player and never burns; a hostile hunts the
// player and burns in the open. Both halves are read from `hostile_kind`, so a
// new kind cannot quietly become a pig that attacks you.
const ANIMALS = [1, 3, 5, 6];
const HOSTILES = [2, 4];
const solo = (id, kind) => Entities.cons_mob(Entities.make_mob(id, kind, 20.5, 1.0, 20.5, 20.0, true), { $: "Nil" });
// The open sky, so the sunlight tick has something to burn.
const soloInSun = (kind) => Entities.cons_mob(Entities.make_mob(1100n, kind, 10.5, 15.0, 5.5, 20.0, true), { $: "Nil" });
for (const kind of ANIMALS) {
  assert.ok(Entities.kind_is_animal(kind), `kind ${kind} is a farm animal`);
  assert.ok(!Entities.hostile_kind(kind, true), `kind ${kind} never hunts the player`);
  assert.equal(Number(Entities.threat_damage(solo(1100n, kind), 20.5, 1.0, 20.5, 0n, regionList([meleeRegion(20.5, 1.0, 20.5)]))), 0,
    `kind ${kind} must never damage the player`);
  const sunlit = Entities.sunlight_damage(soloInSun(kind), { $: "Nil" }, 1337n, 1.0, 0.2, { $: "Nil" });
  assert.equal(Number(listValues(sunlit.mobs)[0].health), 20, `kind ${kind} does not burn in daylight`);
  assert.equal(listValues(sunlit.mobs)[0].burning, false, `kind ${kind} is never published as burning`);
  assert.equal(Entities.peaceful_mobs(solo(1100n, kind)).$, "Con", `kind ${kind} survives peaceful mode`);
}
for (const kind of HOSTILES) {
  assert.ok(!Entities.kind_is_animal(kind), `kind ${kind} is not a farm animal`);
  assert.ok(Entities.hostile_kind(kind, true), `kind ${kind} hunts the player`);
  assert.equal(Entities.peaceful_mobs(solo(1100n, kind)).$, "Nil", `kind ${kind} is removed in peaceful mode`);
  const sunlit = Entities.sunlight_damage(soloInSun(kind), { $: "Nil" }, 1337n, 1.0, 0.2, { $: "Nil" });
  assert.ok(Number(listValues(sunlit.mobs)[0].health) < 20, `kind ${kind} burns in daylight`);
  assert.equal(listValues(sunlit.mobs)[0].burning, true, `kind ${kind} is published as burning`);
}
// Loot follows the animal, not the passivity: the sheep still shears.
assert.equal(Number(Entities.drop_for(Entities.make_mob(1n, 1, 0.5, 1.0, 0.5, 20.0, true)).item), 48);
assert.equal(Number(Entities.drop_for(Entities.make_mob(1n, 3, 0.5, 1.0, 0.5, 20.0, true)).item), 12);
assert.equal(Number(Entities.drop_for(Entities.make_mob(1n, 5, 0.5, 1.0, 0.5, 20.0, true)).item), 49);
assert.equal(Number(Entities.drop_for(Entities.make_mob(1n, 6, 0.5, 1.0, 0.5, 20.0, true)).item), 50);
assert.equal(Number(Entities.drop_for(Entities.make_mob(1n, 2, 0.5, 1.0, 0.5, 20.0, true)).item), 13);
assert.equal(Number(Entities.drop_for(Entities.make_mob(1n, 4, 0.5, 1.0, 0.5, 20.0, true)).item), 13);

// Panic is the whole flee rule: an animal runs from the player for a while after
// the player hits it, and walks around normally until then.
const calmPig = solo(1101n, 1);
const struckPig = Entities.attack(calmPig, 1101n, 4.0, 20.5, 1.0, 25.5, 8.0, { $: "Nil" });
assert.equal(Number(listValues(Entities.combat_mobs(struckPig))[0].panic), Number(Entities.panic_seconds()),
  'a struck animal starts running from the player');
const struckZombie = Entities.attack(solo(1102n, 2), 1102n, 4.0, 20.5, 1.0, 25.5, 8.0, { $: "Nil" });
assert.equal(Number(listValues(Entities.combat_mobs(struckZombie))[0].panic), 0,
  'a hostile answers a hit by charging, not by running');
const outOfReach = Entities.attack(calmPig, 1101n, 4.0, 20.5, 1.0, 25.5, 0.5, { $: "Nil" });
assert.equal(Number(listValues(Entities.combat_mobs(outOfReach))[0].panic), 0,
  'an animal out of reach is never struck');

const panicking = Entities.cons_mob(
  Entities.make_mob_heading(1103n, 1, 20.5, 1.0, 20.5, 0.0, -1.0, 20.0, true, false, Entities.panic_seconds()),
  { $: "Nil" },
);
const ran = listValues(Entities.step_budgeted(panicking, 20.5, 25.5, 1.0, 64.0))[0];
assert.ok(20.5 - Number(ran.z) > 0.7, `a panicking animal must run from the player, z=${Number(ran.z)}`);
assert.ok(Number(ran.panic) < Number(Entities.panic_seconds()) && Number(ran.panic) > 0, 'panic decays while running');
const wandered = listValues(Entities.step_budgeted(calmPig, 20.5, 25.5, 1.0, 64.0))[0];
assert.equal(Number(wandered.z), 20.5, 'an unstruck animal stands still on the budgeted path');
let settled = panicking;
for (let index = 0; index < 10; index += 1) settled = Entities.step_budgeted(settled, 20.5, 25.5, 1.0, 64.0);
assert.equal(Number(listValues(settled)[0].panic), 0, 'panic runs out and the animal calms down');

// The browser drives active mobs through `step_world`, so the flee rule has to
// hold on the collision-aware path too, not only on the budgeted one. A panicking
// animal sprints at 1.2 blocks a second while a wandering one drifts at 0.4.
const atRest = (id, panic) => Entities.cons_mob(
  Entities.make_mob_heading(id, 1, 2.5, 1.0, 2.5, 0.0, -1.0, 20.0, true, false, panic),
  { $: "Nil" },
);
const activeFlee = Entities.step_world(atRest(1104n, Entities.panic_seconds()), 2.5, 7.5, 0.2, 1.0, 0n, regionList([meleeRegion(2.5, 1.0, 2.5)]));
assert.ok(2.5 - Number(listValues(activeFlee)[0].z) > 0.2, 'an active panicking animal must run from the player');
const activeWander = Entities.step_world(atRest(1105n, 0.0), 2.5, 7.5, 0.2, 1.0, 0n, regionList([meleeRegion(2.5, 1.0, 2.5)]));
assert.ok(Math.abs(2.5 - Number(listValues(activeWander)[0].z)) <= 0.09, 'an active unstruck animal only wanders');
console.log('mob roster ok');

// Daylight burns hostile mobs in exposed sky, while night, shade and passive
// mobs remain undamaged. A solar death uses the same authoritative drop path.
const sunMobs = {
  $: "Con",
  head: Entities.make_mob(2001n, 2, 10.5, 15.0, 5.5, 20.0, true),
  tail: {
    $: "Con",
    head: Entities.make_mob(2002n, 1, 12.5, 15.0, 5.5, 20.0, true),
    tail: { $: "Nil" },
  },
};
const sunnyTick = Entities.sunlight_damage(sunMobs, { $: "Nil" }, 1337n, 1.0, 0.2, { $: "Nil" });
const sunnyMobs = listValues(sunnyTick.mobs);
assert.ok(Math.abs(Number(sunnyMobs[0].health) - 19.8) < 0.001);
assert.equal(Number(sunnyMobs[1].health), 20);
const moonlitTick = Entities.sunlight_damage(sunMobs, { $: "Nil" }, 1337n, 0.28, 0.2, { $: "Nil" });
assert.equal(Number(listValues(moonlitTick.mobs)[0].health), 20);
const bruteSun = Entities.sunlight_damage(
  { $: "Con", head: Entities.make_mob(2003n, 4, 14.5, 15.0, 5.5, 40.0, true), tail: { $: "Nil" } },
  { $: "Nil" },
  1337n,
  1.0,
  0.2,
  { $: "Nil" },
);
assert.ok(Number(listValues(bruteSun.mobs)[0].health) < 40);
const underground = Entities.sunlight_damage(
  { $: "Con", head: Entities.make_mob(2004n, 2, 10.5, 0.0, 5.5, 20.0, true), tail: { $: "Nil" } },
  { $: "Nil" },
  1337n,
  1.0,
  0.2,
  { $: "Nil" },
);
assert.equal(Number(listValues(underground.mobs)[0].health), 20);
const roof = {
  $: "Con",
  head: { $: "Edit", x: 10n, y: 16n, z: 5n, block: 1 },
  tail: { $: "Nil" },
};
const shadedTick = Entities.sunlight_damage(sunMobs, roof, 1337n, 1.0, 0.2, { $: "Nil" });
assert.equal(Number(listValues(shadedTick.mobs)[0].health), 20);
const canopyMobs = {
  $: "Con",
  head: Entities.make_mob(2005n, 2, 176.5, 7.0, 2.5, 20.0, true),
  tail: { $: "Nil" },
};
const canopyHeight = Number(World.column_height(1337n, 176n, 2n));
assert.equal(Number(World.block(1337n, 176n, BigInt(canopyHeight + 5), 2n)), 0);
assert.equal(Number(World.block(1337n, 176n, BigInt(canopyHeight + 6), 2n)), 4);
const canopyTick = Entities.sunlight_damage(canopyMobs, { $: "Nil" }, 1337n, 1.0, 0.2, { $: "Nil" });
assert.equal(Number(listValues(canopyTick.mobs)[0].health), 20, "generated canopy above an air gap must shade the mob");
let burning = sunMobs;
let burnResult = null;
for (let index = 0; index < 100; index += 1) {
  burnResult = Entities.sunlight_damage(burning, { $: "Nil" }, 1337n, 1.0, 0.2, burnResult?.drops ?? { $: "Nil" });
  burning = burnResult.mobs;
}
const burned = listValues(burning);
assert.equal(burned[0].alive, false);
assert.equal(burned[1].alive, true);
assert.equal(listValues(burnResult.drops).length, 1);
console.log('sunlight damage ok');

// Which mobs are on fire is domain state, not a browser guess: the browser only
// presents it. So the sunlight tick has to publish the flag per mob, and every
// other tick that rebuilds a Mob has to carry it through untouched. A flag that
// reset on movement would make the flames stutter every simulation step.
const flagOf = (result, index = 0) => listValues(result.mobs)[index].burning;
assert.equal(flagOf(sunnyTick, 0), true, "a hostile mob in direct sun must report itself burning");
assert.equal(flagOf(sunnyTick, 1), false, "a passive mob never burns in sunlight");
assert.equal(flagOf(moonlitTick, 0), false, "night must clear the fire");
assert.equal(flagOf(underground, 0), false, "a mob under the terrain must not burn");
assert.equal(flagOf(shadedTick, 0), false, "an opaque edit overhead must clear the fire");
assert.equal(flagOf(canopyTick, 0), false, "a generated canopy must clear the fire");
assert.equal(burned[0].burning, false, "a mob the sun finished off must not be left burning on the corpse");

// Water is the way out of the fire: a body touching water is not in direct sun,
// so it neither catches nor keeps the flame. Both halves of the world have to
// answer it, because a mob can reach water as generated sea or as a bucket the
// player poured on it.
const seaMobs = {
  $: "Con",
  head: Entities.make_mob(2006n, 2, 0.5, 7.0, 0.5, 20.0, true),
  tail: { $: "Nil" },
};
// The regression only means anything in a cell that is both open sky and water,
// so the fixture is checked instead of assumed: the ocean surface of this seed
// sits at sea level, above a seabed that leaves the sky clear.
assert.equal(World.water_at(1337n, 0n, 7n, 0n), true, "the fixture column must hold generated water");
assert.equal(Entities.sun_exposed_generated(1337n, 0.5, 7.0, 0.5), true, "the fixture column must be open sky");
const seaTick = Entities.sunlight_damage(seaMobs, { $: "Nil" }, 1337n, 1.0, 0.2, { $: "Nil" });
assert.equal(Number(listValues(seaTick.mobs)[0].health), 20, "a mob under the sea must not burn in daylight");
assert.equal(flagOf(seaTick, 0), false, "a mob in the sea must not be reported burning");

const waterEdit = (y) => ({
  $: "Con",
  head: { $: "Edit", x: 10n, y: BigInt(y), z: 5n, block: 7 },
  tail: { $: "Nil" },
});
const dousedTick = Entities.sunlight_damage(sunMobs, waterEdit(15), 1337n, 1.0, 0.2, { $: "Nil" });
assert.equal(Number(listValues(dousedTick.mobs)[0].health), 20, "water at a mob's feet must stop the sun");
assert.equal(flagOf(dousedTick, 0), false, "water under a burning mob must put the fire out on the next tick");
const wadingTick = Entities.sunlight_damage(sunMobs, waterEdit(16), 1337n, 1.0, 0.2, { $: "Nil" });
assert.equal(flagOf(wadingTick, 0), false, "water at head height must put the fire out too");
const dryTick = Entities.sunlight_damage(
  sunMobs,
  { $: "Con", head: { $: "Edit", x: 10n, y: 14n, z: 5n, block: 7 }, tail: { $: "Nil" } },
  1337n,
  1.0,
  0.2,
  { $: "Nil" },
);
assert.equal(flagOf(dryTick, 0), true, "water in a neighbouring cell must not douse the mob");

// Movement, knockback and the despawn filter all rebuild the record, so each of
// them has to preserve the flag rather than default it back to false.
const litZombie = listValues(sunnyTick.mobs)[0];
const burningStep = Entities.step_budgeted(
  Entities.cons_mob(litZombie, { $: "Nil" }), 10.5, 5.5, 0.2, 64.0,
);
assert.equal(burningStep.head.burning, true, "a burning mob that takes a step must stay burning");
const struck = Entities.attack(
  Entities.cons_mob(litZombie, { $: "Nil" }), litZombie.id, 1.0, 10.5, 15.0, 5.5, 4.0, { $: "Nil" },
);
assert.equal(struck.mobs.head.burning, true, "a burning mob that is hit must stay burning");
const keptBurning = Entities.despawn(
  Entities.cons_mob(litZombie, { $: "Nil" }), 10.5, 5.5, 48.0,
);
assert.equal(keptBurning.head.burning, true, "despawn must not clear the fire on a mob it keeps");
console.log('sunlight burning flag ok');

// The aim rule: Bend's is the one the native client asks, and the browser still asks
// web/aim.js. Until the browser migrates, the two answer the same for the same ray.
for (const kind of [1, 2, 3, 4, 5, 6, 9]) {
  assert.ok(Math.abs(Number(Entities.body_height(kind)) - mobHeight(kind)) < 1e-6, `kind ${kind} is as tall in Bend as in the roster`);
}
const aimRays = [
  { origin: [10.5, 11.62, 8.5], direction: [0, 0, -1] },
  { origin: [10.5, 11.62, 8.5], direction: [0, -0.6, -0.8] },
  { origin: [10.5, 11.62, 8.5], direction: [0.6, 0, -0.8] },
  { origin: [10.5, 11.62, 8.5], direction: [0, 0, 1] },
  { origin: [10.5, 13.5, 8.5], direction: [0, 0, -1] },
  { origin: [10.5, 10.5, 5.5], direction: [0, 1, 0] },
  { origin: [14.5, 11.0, 5.5], direction: [-1, 0, 0] },
];
for (const kind of [1, 2, 6]) {
  const mob = { x: 10.5, y: 10, z: 5.5, kind };
  for (const { origin, direction } of aimRays) {
    const want = rayHitBox(origin, direction, mobBox(mob), 4);
    const got = Number(Entities.aim_distance(...origin, ...direction, mob.x, mob.y, mob.z, mobHeight(kind), 4));
    if (want === null) assert.ok(got < 0, `a ray web/aim.js misses kind ${kind} with is a miss in Bend`);
    else assert.ok(Math.abs(got - want) < 1e-4, `kind ${kind}: Bend's distance ${got} is web/aim.js's ${want}`);
  }
}

// Which bodies a ray can hit: the roster's mobs and nothing else. A villager and an item on
// the ground are told apart from a mob by the number that names their kind, and the native
// client asks this rather than keeping a range of its own.
for (const [kind, isMob] of [[0, false], [1, true], [2, true], [3, true], [4, true], [5, true], [6, true], [7, false], [10, false], [11, false], [12, false], [1000, false], [1001, false]]) {
  assert.equal(Entities.kind_is_mob(kind), isMob, `kind ${kind} ${isMob ? "is" : "is not"} a mob`);
}
// The mob under the crosshair is the nearest one the ray meets within reach: each body is
// only tested out to the nearest found so far, so a nearer mob replaces it and a farther one,
// or anything that is not a mob, leaves it.
const eye = [10.5, 11.62, 8.5];
const forward = [0, 0, -1];
const found = (best, id, kind, z) => Entities.aim_step(best, ...eye, ...forward, id, kind, 10.5, 10, z);
let nearest = Entities.aim_none(4);
assert.equal(nearest.found, false, "nothing has been found before a body is tested");
nearest = found(nearest, 7, 2, 5.5);
assert.deepEqual([nearest.found, Number(nearest.id)], [true, 7], "a zombie on the ray is under the crosshair");
assert.ok(Math.abs(Number(nearest.away) - 2.6) < 1e-4, "it is as far as its box is along the ray");
nearest = found(nearest, 8, 2, 6.5);
assert.equal(Number(nearest.id), 8, "a nearer zombie replaces it");
nearest = found(nearest, 9, 2, 4.5);
assert.equal(Number(nearest.id), 8, "a farther zombie does not");
assert.equal(found(Entities.aim_none(4), 13, 1, 5.5).found, false, "a ray at eye height passes over a pig, which is not that tall");
nearest = found(nearest, 10, 11, 7.0);
assert.equal(Number(nearest.id), 8, "a villager in front of it is not hit like a mob");
assert.equal(found(Entities.aim_none(4), 11, 2, 3.0).found, false, "a mob past the reach is not under the crosshair");
assert.equal(found(Entities.aim_none(4), 12, 1001, 6.5).found, false, "an item on the ground is not a mob");
console.log('aim rule ok');
