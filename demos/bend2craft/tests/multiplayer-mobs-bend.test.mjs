import assert from "node:assert/strict";
import { DOMAIN_COORDINATE_OFFSET, mobRegion } from "../web/game-state.js";
import { Entities, MultiplayerMobs } from "../web/bend-modules.js";

const list = (items) => items.reduceRight((tail, head) => ({ $: "Con", head, tail }), { $: "Nil" });
const array = (node) => {
  const items = [];
  for (; node?.$ === "Con"; node = node.tail) items.push(node.head);
  return items;
};
const target = (x, y, z) => MultiplayerMobs.make_target(x, y, z);
// A flat world: solid below y = 8, air above.
const flat = { blockAt: (_x, y) => (y < 8 ? 1 : 0), maxY: 20 };
const regionFor = (mob) => {
  const region = mobRegion(flat, Number(mob.x), Number(mob.y), Number(mob.z));
  return {
    $: "Region",
    blocks: region.blocks,
    origin_x: region.originX,
    origin_y: region.originY,
    origin_z: region.originZ,
    width: region.width,
    height: region.height,
    depth: region.depth,
  };
};
const OFFSET = BigInt(DOMAIN_COORDINATE_OFFSET);

// The nearest target wins.
const near = MultiplayerMobs.nearest(list([target(20, 8, 10), target(-30, 8, 10)]), 10, 10, MultiplayerMobs.far_target());
assert.equal(Number(near.x), 20);
assert.equal(Number(MultiplayerMobs.nearest({ $: "Nil" }, 0, 0, target(5, 5, 5)).x), 5);

// A zombie between two players walks toward the nearer one; a second zombie
// on the other side walks toward the other player.
const zombies = list([
  Entities.make_mob(1n, 2, 12.5, 8, 10.5, 20, true),
  Entities.make_mob(2n, 2, -20.5, 8, 10.5, 20, true),
]);
const regions = list(array(zombies).map(regionFor));
const players = list([target(20, 8, 10.5), target(-30, 8, 10.5)]);
const stepped = array(MultiplayerMobs.step_world(zombies, players, 0.2, 0, OFFSET, regions));
assert.equal(stepped.length, 2);
assert.ok(Number(stepped[0].x) > 12.5, `zombie 1 moved toward the player at x=20 (${stepped[0].x})`);
assert.ok(Number(stepped[1].x) < -20.5, `zombie 2 moved toward the player at x=-30 (${stepped[1].x})`);
// Missing regions stop the list, like Entities.step_world.
assert.equal(array(MultiplayerMobs.step_world(zombies, players, 0.2, 0, OFFSET, { $: "Nil" })).length, 0);

// Despawn keeps a mob near any player.
const kept = array(MultiplayerMobs.despawn(zombies, list([target(-25, 8, 10)]), 48));
assert.deepEqual(kept.map((mob) => Number(mob.id)), [1, 2]);
const far = array(MultiplayerMobs.despawn(zombies, list([target(100, 8, 10)]), 48));
assert.deepEqual(far.map((mob) => Number(mob.id)), []);
assert.deepEqual(array(MultiplayerMobs.despawn(zombies, list([target(60, 8, 10)]), 48)).map((mob) => Number(mob.id)), [1]);

// Attacks clamp the damage and respect melee and bow range.
const pig = list([Entities.make_mob(7n, 1, 5, 8, 5, 10, true)]);
const heavy = MultiplayerMobs.attack(pig, 7n, 1000, 5, 8, 6, false, Entities.empty_drops());
assert.equal(heavy.hit, true);
assert.ok(Math.abs(Number(array(heavy.mobs)[0].health) - 3) < 1e-5, "1000 damage is clamped to 7");
assert.equal(MultiplayerMobs.attack(pig, 7n, 4, 5, 8, 15, false, Entities.empty_drops()).hit, false, "10 blocks is out of melee reach");
assert.equal(MultiplayerMobs.attack(pig, 7n, 4, 5, 8, 15, true, Entities.empty_drops()).hit, true, "but inside bow range");
const killed = MultiplayerMobs.attack(list([Entities.make_mob(8n, 1, 5, 8, 5, 3, true)]), 8n, 5, 5, 8, 6, false, Entities.empty_drops());
assert.equal(array(killed.mobs)[0].alive, false);
assert.equal(array(killed.drops).length, 1);

// Pickups need the drop to exist and be within reach.
const drops = list([Entities.make_drop(40n, 48, 3, 8, 3, 2), Entities.make_drop(41n, 12, 30, 8, 30, 1)]);
const taken = MultiplayerMobs.pickup(drops, 40n, 4, 8, 3);
assert.equal(MultiplayerMobs.pickup_ok(taken), true);
assert.deepEqual([Number(MultiplayerMobs.pickup_item(taken)), Number(MultiplayerMobs.pickup_amount(taken))], [48, 2]);
assert.deepEqual(array(MultiplayerMobs.pickup_drops(taken)).map((drop) => Number(drop.id)), [41]);
assert.equal(MultiplayerMobs.pickup_ok(MultiplayerMobs.pickup(drops, 41n, 4, 8, 3)), false, "too far");
assert.equal(array(MultiplayerMobs.pickup_drops(MultiplayerMobs.pickup(drops, 41n, 4, 8, 3))).length, 2);
assert.equal(MultiplayerMobs.pickup_ok(MultiplayerMobs.pickup(drops, 99n, 4, 8, 3)), false, "no such drop");

console.log("bend multiplayer mobs ok");
