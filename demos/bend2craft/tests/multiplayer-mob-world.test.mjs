import assert from "node:assert/strict";
import { createMobWorld } from "../server/mob-world.js";
import { createWorldCache } from "../server/world-cache.js";
import { createServerWorld } from "../server/server-world.js";
import { createMultiplayerRoom } from "../server/multiplayer-room.js";
import { PROTOCOL_VERSION, decodeClientMessage, decodeServerMessage } from "../web/multiplayer-protocol.js";
import { Entities, Multiplayer, World, WorldState } from "../web/bend-modules.js";

const SEED = 1337n;
const list = (items) => items.reduceRight((tail, head) => ({ $: "Con", head, tail }), { $: "Nil" });
let edits = WorldState.empty();

// The server's terrain cache agrees with the Bend world and follows edits.
const mobsOver = (options) => {
  const cache = createWorldCache({ seed: SEED, edits: () => edits });
  const world = createMobWorld({ seed: SEED, cache, edits: () => edits, ...options });
  return Object.assign(world, { cache });
};
const mobWorld = mobsOver({ random: () => 0.5 });
for (const [x, y, z] of [[20, 8, 20], [3, 5, 3], [-5, 6, -7], [40, 15, 40]]) {
  assert.equal(
    mobWorld.cache.blockAt(x, y, z),
    Number(WorldState.block(edits, SEED, BigInt(x < 0 ? x + 94371840 : x), BigInt(y), BigInt(z < 0 ? z + 94371840 : z))),
    `cell ${x},${y},${z}`,
  );
}
edits = WorldState.set(edits, 20n, 8n, 20n, 22);
mobWorld.blocksChanged(mobWorld.cache.applyEdits([[20, 8, 20, 22]]));
assert.equal(mobWorld.cache.blockAt(20, 8, 20), 22, "an accepted edit reaches the cached chunk");
assert.ok(mobWorld.cache.size() > 0);

// No players, no simulation.
assert.equal(mobWorld.tick(0.2, 100, []).size, 0);
assert.deepEqual(mobWorld.snapshot().mobs, []);

// The first tick with a player populates the world like single player does.
const surface = Number(World.column_height(SEED, 25n, 16n));
mobWorld.tick(0.2, 20, [{ id: 1, x: 25.5, y: surface, z: 16.5 }]);
const populated = mobWorld.snapshot().mobs;
assert.ok(populated.length > 0, "mobs spawn around the world origin");
assert.ok(populated.every((mob) => mob.length === 11));

// A zombie next to a player hurts that player, not a far one, and walks to it.
const zombieY = surface;
mobWorld.setMobsForTest(list([Entities.make_mob(900n, 2, 30.5, zombieY, 16.5, 20, true)]));
const near = { id: 1, x: 31.3, y: zombieY, z: 16.5 };
const far = { id: 2, x: 60.5, y: zombieY, z: 16.5 };
let hurt = 0;
for (let step = 0; step < 5; step += 1) {
  const hurts = mobWorld.tick(0.2, 20, [near, far]);
  hurt += hurts.get(1) ?? 0;
  assert.equal(hurts.get(2), undefined);
}
assert.ok(hurt > 0, "the near player takes damage");

// Attacks go through the Bend rules with the attacker's pose.
const [zombie] = mobWorld.snapshot().mobs;
assert.equal(mobWorld.attack({ x: 80, y: zombieY, z: 80 }, 900, 7, false).hit, false, "out of reach");
let result = mobWorld.attack(near, 900, 50, false);
assert.equal(result.hit, true);
assert.equal(result.kind, 2);
assert.ok(mobWorld.snapshot().mobs[0][7] < zombie[7], "health dropped");
result = mobWorld.attack(near, 900, 7, false);
result = mobWorld.attack(near, 900, 7, false);
assert.equal(result.killed, true);
const [corpseDrop] = mobWorld.snapshot().drops;
assert.equal(corpseDrop[0], 900, "a kill drops loot where the mob fell");

// Pickups need reach; thrown items join the drops.
assert.equal(mobWorld.pickup({ x: 90, y: 9, z: 90 }, 900).ok, false);
const [, , dx, dy, dz] = corpseDrop;
const picked = mobWorld.pickup({ x: dx, y: dy, z: dz }, 900);
assert.deepEqual([picked.ok, picked.item, picked.amount], [true, 13, 1]);
assert.equal(mobWorld.pickup({ x: dx, y: dy, z: dz }, 900).ok, false, "only once");
const thrown = mobWorld.addDrop(5, 3, 26, surface + 1, 16);
assert.ok(thrown >= 1_000_000_000);
assert.equal(mobWorld.snapshot().drops.find((drop) => drop[0] === thrown)[5], 3);

// Drops settle on the ground wherever they fall, not only on cell centres.
const settle = mobsOver({ random: () => 0.5 });
settle.setMobsForTest({ $: "Nil" });
const offCentre = settle.addDrop(5, 1, 26.27, surface + 2, 16.81);
for (let step = 0; step < 10; step += 1) settle.tick(0.2, 20, [{ id: 1, x: 25.5, y: surface, z: 16.5 }]);
const settled = settle.snapshot().drops.find((drop) => drop[0] === offCentre);
assert.equal(settled[3], Number(World.column_height(SEED, 26n, 16n)), `the drop rests on the surface (${settled[3]})`);

// Night spawns come around each player (random fixed at 0.5).
const night = mobsOver({ random: () => 0.5 });
night.setMobsForTest({ $: "Nil" });
for (let step = 0; step < 26; step += 1) night.tick(0.2, 3 * Math.PI / 0.16, [{ id: 1, x: 25.5, y: surface, z: 16.5 }]);
assert.ok(night.snapshot().mobs.length > 0, "monsters spawn at night");
const peaceful = mobsOver({ peaceful: true, random: () => 0.5 });
peaceful.setMobsForTest({ $: "Nil" });
for (let step = 0; step < 26; step += 1) peaceful.tick(0.2, 3 * Math.PI / 0.16, [{ id: 1, x: 25.5, y: surface, z: 16.5 }]);
assert.equal(peaceful.snapshot().mobs.length, 0, "not in a peaceful world");

// The room: entity snapshots every tick, hurts to the right player, attacks,
// pickups and thrown items through messages.
assert.equal(decodeClientMessage(JSON.stringify({ t: "attack", id: 1, mob: 3, damage: -1, ranged: false })), null);
assert.equal(decodeClientMessage(JSON.stringify({ t: "drop", item: 5, amount: 65, x: 0, y: 0, z: 0 })), null);
const room = createMultiplayerRoom({ authority: Multiplayer, seed: SEED, createServerWorld, now: () => 0 });
const inbox = [];
const handle = room.connect((text) => inbox.push(JSON.parse(text)));
handle.receive(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, name: "Lucas" }));
room.tick();
assert.equal(inbox.filter((m) => m.t === "entities").length, 0, "no pose, no simulation");
handle.receive(JSON.stringify({ t: "pose", x: 25.5, y: surface, z: 16.5, yaw: 0, pitch: 0 }));
room.tick();
const entities = inbox.filter((m) => m.t === "entities").at(-1);
assert.ok(decodeServerMessage(JSON.stringify(entities)));
assert.ok(entities.mobs.length > 0);
handle.receive(JSON.stringify({ t: "drop", item: 5, amount: 2, x: 25.5, y: surface + 0.6, z: 16.5 }));
const thrownDrop = inbox.filter((m) => m.t === "entities").at(-1).drops.find((drop) => drop[1] === 5);
assert.ok(thrownDrop);
handle.receive(JSON.stringify({ t: "pickup", id: 4, drop: thrownDrop[0] }));
assert.deepEqual(
  (({ t, id, ok, item, amount }) => ({ t, id, ok, item, amount }))(inbox.filter((m) => m.t === "pickup-result").at(-1)),
  { t: "pickup-result", id: 4, ok: true, item: 5, amount: 2 },
);
handle.receive(JSON.stringify({ t: "attack", id: 5, mob: 123456, damage: 4, ranged: false }));
assert.equal(inbox.filter((m) => m.t === "attack-result").at(-1).hit, false);
// A room without the mob world keeps working as before.
const plain = createMultiplayerRoom({ authority: Multiplayer, seed: SEED });
assert.equal(plain.tick(), 0);

console.log("multiplayer mob world ok");
