import assert from "node:assert/strict";
import { createMultiplayerRoom } from "../server/multiplayer-room.js";
import { createServerWorld } from "../server/server-world.js";
import { PROTOCOL_VERSION, decodeClientMessage, decodeServerMessage } from "../web/multiplayer-protocol.js";
import { Multiplayer, Structures, World, WorldState } from "../web/bend-modules.js";

const SEED = 1337n;
const room = createMultiplayerRoom({ authority: Multiplayer, seed: SEED, createServerWorld, peaceful: true, now: () => 0 });
const inbox = [];
const player = room.connect((text) => inbox.push(JSON.parse(text)));
player.receive(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, name: "Lucas" }));
const last = (type) => inbox.filter((m) => m.t === type).at(-1);
const serverEdits = () => inbox.filter((m) => m.t === "edits" && m.from === 0).flatMap((m) => m.edits);
let nextId = 1;
const interact = (op, pos) => {
  player.receive(JSON.stringify({ t: "interact", id: nextId, op, pos }));
  nextId += 1;
  return last("interact-result");
};
const blockOf = (x, y, z) => Number(WorldState.block(Multiplayer.room_edits(room.world() && roomState()), SEED, BigInt(x), BigInt(y), BigInt(z)));
function roomState() {
  // The welcome of a fresh connection is the room's current log.
  const probe = [];
  const handle = room.connect((text) => probe.push(JSON.parse(text)));
  handle.receive(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, name: "probe" }));
  handle.disconnect();
  return Multiplayer.restore(0, probe[0].edits.reduceRight((tail, [x, y, z, block]) => ({ $: "Con", head: WorldState.make_edit(BigInt(x), BigInt(y), BigInt(z), block), tail }), { $: "Nil" }), Multiplayer.room_chests(Multiplayer.empty()), Multiplayer.room_furnaces(Multiplayer.empty()));
}

// Messages.
assert.equal(decodeClientMessage(JSON.stringify({ t: "interact", id: 1, op: "explode", pos: [1, 2, 3] })), null);
assert.ok(decodeClientMessage(JSON.stringify({ t: "interact", id: 1, op: "water", pos: [1, 2, 3] })));

// Open grass on the spawn plains (seed 1337): water at (22, 17), a field at
// (28, 11) and a fire at (31, 11), all within reach of a player at (25, 14).
const surfaceAt = (cx, cz) => Number(World.column_height(SEED, BigInt(cx), BigInt(cz)));
const x = 22;
const z = 17;
const surface = surfaceAt(x, z);
player.receive(JSON.stringify({ t: "pose", x: 25.5, y: surfaceAt(25, 14), z: 14.5, yaw: 0, pitch: 0 }));
assert.equal(room.world().cache.blockAt(x, surface, z), 0, "air above the surface");

// Out of reach is refused.
assert.equal(interact("water", [x + 40, surface, z]).ok, false);
assert.equal(last("interact-result").reason, "reach");

// A bucket of water: the room sends the cell to everyone, and the server's
// simulation spreads it over ticks as server batches.
assert.equal(interact("water", [x, surface, z]).ok, true);
assert.ok(serverEdits().some(([ex, ey, ez, block]) => ex === x && ey === surface && ez === z && block === 7));
assert.equal(blockOf(x, surface, z), 7);
for (let step = 0; step < 10; step += 1) room.tick();
const flowed = serverEdits().filter(([, , , block]) => block === 7).length;
assert.ok(flowed > 1, `water spreads (${flowed} cells)`);
assert.ok(decodeServerMessage(JSON.stringify(last("entities"))), "entity snapshots carry villagers");
// Taking it back with a bucket.
const collected = interact("collect", [x, surface, z]);
assert.deepEqual([collected.ok, collected.block], [true, 7]);
assert.equal(blockOf(x, surface, z), 0);
assert.equal(interact("collect", [x + 1, surface - 1, z]).ok, false, "ground is not a fluid");

// Farming: till, plant; a young crop refuses the harvest.
const fx = 28;
const fz = 11;
const field = surfaceAt(fx, fz);
assert.equal(interact("till", [fx, field - 1, fz]).ok, true);
assert.equal(blockOf(fx, field - 1, fz), 20);
assert.equal(interact("plant", [fx, field, fz]).ok, true);
assert.equal(blockOf(fx, field, fz), 16);
assert.equal(interact("harvest", [fx, field, fz]).ok, false);
assert.deepEqual(room.world().simulation.cropViews().map((c) => [c.x, c.y, c.z]), [[fx, field, fz]]);
// Mining the crop through an ordinary edit forgets it.
player.receive(JSON.stringify({ t: "edits", edits: [[fx, field, fz, 0]] }));
assert.deepEqual(room.world().simulation.cropViews(), []);

// Fire burns out on the server.
const fireX = 31;
const fireY = surfaceAt(fireX, fz);
assert.equal(interact("fire", [fireX, fireY, fz]).ok, true);
assert.equal(blockOf(fireX, fireY, fz), 24);
let burned = false;
for (let step = 0; step < 400 && !burned; step += 1) {
  room.tick();
  burned = serverEdits().some(([ex, ey, ez, block]) => ex === fireX && ey === fireY && ez === fz && block === 0);
}
assert.ok(burned, "the fire burned out and the room heard it");

// The simulation state is saved with the world and comes back.
player.receive(JSON.stringify({ t: "interact", id: 99, op: "water", pos: [x, surface, z] }));
const snapshot = room.snapshot();
assert.equal(typeof snapshot.simulation, "string");
const resumed = createMultiplayerRoom({ authority: Multiplayer, seed: SEED, createServerWorld, peaceful: true, now: () => 0, snapshot: JSON.parse(JSON.stringify(snapshot)) });
assert.ok(resumed.world().simulation.fluids.flows.$ === "Con", "the water source survives a restart");

// Villagers are simulated by the server near the village and sent to players.
const villageX = Number(Structures.village_origin_x(SEED));
const villageZ = Number(Structures.village_origin_z(SEED));
player.receive(JSON.stringify({ t: "pose", x: villageX + 0.5, y: surface + 1, z: villageZ + 0.5, yaw: 0, pitch: 0 }));
for (let step = 0; step < 12; step += 1) room.tick();
const villagers = last("entities").villagers;
assert.ok(Array.isArray(villagers) && villagers.length > 0, "villagers reach the players");
const createWorld = createServerWorld({ seed: SEED, edits: () => WorldState.empty(), peaceful: true });
assert.equal(createWorld.persistentState(), null, "nothing to save before anything changed");

console.log("multiplayer server world ok");
