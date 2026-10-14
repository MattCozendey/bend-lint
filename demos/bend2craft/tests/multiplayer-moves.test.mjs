import assert from "node:assert/strict";
import { createMultiplayerRoom } from "../server/multiplayer-room.js";
import { createServerWorld } from "../server/server-world.js";
import { PROTOCOL_VERSION, decodeServerMessage } from "../web/multiplayer-protocol.js";
import { Multiplayer, MultiplayerMoves as Moves, World } from "../web/bend-modules.js";

const AIR = 0;
const STONE = 1;
const WATER = 7;
const FAR = 1e6;

// The Bend contract: budgets, solid cells and respawns.
const step = (budget, elapsed, from, to, cells = [AIR, AIR, AIR, AIR], spawn = [FAR, FAR]) =>
  Moves.step(budget, elapsed, ...from, ...to, ...cells, ...spawn);
const walk = (budget, elapsed, dx, dy = 0, cells) => step(budget, elapsed, [0, 10, 0], [dx, 10 + dy, 0], cells);

assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 0.6)), true, "a sprint step passes");
assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 50)), false, "a teleport is refused");
assert.equal(Moves.accepted(walk(Moves.fresh(), 100, 13)), false, "idling does not bank a teleport");
assert.equal(Moves.accepted(walk(Moves.fresh(), 100, 11)), true, "the burst covers a lag spike");
assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 0, 5)), false, "flying up is refused");
assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 0, 1.2)), true, "a jump rises");
assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 0, -40)), true, "falling is free");
assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 0.5, 0, [AIR, AIR, STONE, AIR])), false, "no walking into stone");
assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 0.5, 0, [AIR, AIR, AIR, STONE])), false, "nor with the head");
assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 0.5, 0, [AIR, AIR, WATER, WATER])), true, "water is not solid");
assert.equal(Moves.accepted(walk(Moves.fresh(), 0.1, 0.5, 0, [STONE, AIR, STONE, AIR])), true, "a trapped player may move");
assert.equal(Moves.accepted(step(Moves.fresh(), 0.1, [0, 10, 0], [500.5, 70, 300.5], [AIR, AIR, AIR, AIR], [500.5, 300.5])), true, "respawn");
assert.equal(Moves.accepted(step(Moves.fresh(), 0.1, [0, 10, 0], [500.5, 70, 300.5], [AIR, AIR, STONE, AIR], [500.5, 300.5])), false);

// Many poses bunched by the network spend one budget; it refills with time.
let budget = Moves.fresh();
let x = 0;
for (let pose = 0; pose < 10; pose += 1) {
  const move = step(budget, 0, [x, 10, 0], [x + 1, 10, 0]);
  assert.equal(Moves.accepted(move), true);
  budget = Moves.move_budget(move);
  x += 1;
}
assert.equal(Moves.accepted(step(budget, 0, [x, 10, 0], [x + 3, 10, 0])), false, "the burst is spent");
assert.equal(Moves.accepted(step(budget, 0.5, [x, 10, 0], [x + 3, 10, 0])), true, "and refills over time");

// The room: refused poses are not relayed, and the mover is corrected.
const SEED = 1337n;
let clock = 0;
const room = createMultiplayerRoom({ authority: Multiplayer, seed: SEED, createServerWorld, peaceful: true, now: () => clock });
const join = (name) => {
  const inbox = [];
  const handle = room.connect((text) => inbox.push(JSON.parse(text)));
  handle.receive(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, name }));
  return { inbox, send: (message) => handle.receive(JSON.stringify(message)) };
};
const mover = join("Lucas");
const watcher = join("Bia");
const surface = Number(World.column_height(SEED, 25n, 14n));
const relayed = () => watcher.inbox.filter((m) => m.t === "pose").length;
const pose = (px, py, pz) => mover.send({ t: "pose", x: px, y: py, z: pz, yaw: 0, pitch: 0 });

pose(25.5, surface, 14.5);
assert.equal(relayed(), 1, "the first pose is taken as is");
clock += 200;
pose(26.5, surface, 14.5);
assert.equal(relayed(), 2, "a walk is relayed");
clock += 200;
pose(126.5, surface, 14.5);
assert.equal(relayed(), 2, "a teleport is not relayed");
const correction = mover.inbox.at(-1);
assert.deepEqual(correction, { t: "correct", x: 26.5, y: surface, z: 14.5 });
assert.ok(decodeServerMessage(JSON.stringify(correction)));
clock += 200;
pose(26.5, surface - 3, 14.5);
assert.equal(mover.inbox.at(-1).t, "correct", "sinking into the ground is refused");
clock += 200;
pose(27.3, surface, 14.5);
assert.equal(relayed(), 3, "moving on after a correction works");
assert.equal(room.counters().corrected, 2);

// Respawning onto the world spawn is a move from anywhere.
const spawn = World.spawn_cell(SEED);
clock += 200;
pose(Number(spawn.x) + 0.5, Number(spawn.height) + 0.05, Number(spawn.z) + 0.5);
assert.equal(relayed(), 4, "a respawn is relayed");

console.log("multiplayer moves ok");
