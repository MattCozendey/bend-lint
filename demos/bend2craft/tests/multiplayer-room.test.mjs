import assert from "node:assert/strict";
import { createMultiplayerRoom } from "../server/multiplayer-room.js";
import {
  MAX_PLAYERS,
  PROTOCOL_VERSION,
  bendEditsToWire,
  decodeClientMessage,
  decodeServerMessage,
  multiplayerUrl,
  sanitizeName,
  wireEditsToBend,
} from "../web/multiplayer-protocol.js";
import { Multiplayer, WorldState, World } from "../web/bend-modules.js";

const SEED = 1337n;
// An edit log holds one entry per cell; its order carries no meaning.
const byCell = (edits) => [...edits].sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]);

// Protocol shapes -------------------------------------------------------------
assert.equal(decodeClientMessage("not json"), null);
assert.equal(decodeClientMessage(JSON.stringify({ t: "edits", edits: [[1, 2, 3]] })), null);
assert.equal(decodeClientMessage(JSON.stringify({ t: "edits", edits: [[-1, 2, 3, 1]] })), null);
assert.equal(decodeClientMessage(JSON.stringify({ t: "edits", edits: [[1.5, 2, 3, 1]] })), null);
assert.equal(decodeClientMessage(JSON.stringify({ t: "edits", edits: [] })), null);
assert.deepEqual(decodeClientMessage(JSON.stringify({ t: "edits", edits: [[1, 2, 3, 4]] })), { t: "edits", edits: [[1, 2, 3, 4]] });
assert.equal(decodeClientMessage(JSON.stringify({ t: "pose", x: 1, y: 2, z: 3, yaw: "a", pitch: 0 })), null);
assert.equal(decodeClientMessage(JSON.stringify({ t: "teleport" })), null);
assert.equal(sanitizeName("  Lu\u0007cas   the\tgreat  "), "Lucas the great");
assert.equal(sanitizeName("x".repeat(80)).length, 24);
assert.equal(sanitizeName(""), "Player");
assert.equal(decodeServerMessage(JSON.stringify({ t: "left" })), null);
assert.deepEqual(bendEditsToWire(wireEditsToBend([[1, 2, 3, 4], [5, 6, 7, 0]])), [[1, 2, 3, 4], [5, 6, 7, 0]]);
// The wire list builds the same records WorldState makes.
assert.deepEqual(wireEditsToBend([[1, 2, 3, 4]]).head, WorldState.make_edit(1n, 2n, 3n, 4));
const page = { protocol: "http:", host: "192.168.0.10:8080" };
assert.equal(multiplayerUrl("", page), "ws://192.168.0.10:8080/multiplayer");
assert.equal(multiplayerUrl("", { protocol: "https:", host: "craft.example.dev" }), "wss://craft.example.dev/multiplayer");
assert.equal(multiplayerUrl("10.0.0.5:8080", page), "ws://10.0.0.5:8080/multiplayer");
assert.equal(multiplayerUrl("https://abc.trycloudflare.com/?play=1", page), "wss://abc.trycloudflare.com/multiplayer");
assert.equal(multiplayerUrl("ws://host:9000/custom", page), "ws://host:9000/custom");
assert.throws(() => multiplayerUrl("ftp://host", page));

// Room ------------------------------------------------------------------------
function client(room, name) {
  const inbox = [];
  const closed = [];
  const handle = room.connect((text) => inbox.push(JSON.parse(text)), (code, reason) => closed.push({ code, reason }));
  handle.receive(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, name }));
  return { handle, inbox, closed, last: (type) => inbox.filter((m) => m.t === type).at(-1) };
}

let changes = 0;
let clock = 1_000_000;
const now = () => clock;
const room = createMultiplayerRoom({ authority: Multiplayer, seed: SEED, now, onChange: () => { changes += 1; } });
const alice = client(room, "Alice");
const welcomeA = alice.last("welcome");
assert.ok(decodeServerMessage(JSON.stringify(welcomeA)));
assert.equal(welcomeA.seed, "1337");
assert.equal(welcomeA.seq, 0);
assert.deepEqual(welcomeA.edits, []);
assert.deepEqual(welcomeA.players, []);
assert.deepEqual(welcomeA.chests, []);
assert.deepEqual(welcomeA.furnaces, []);
assert.equal(welcomeA.time, 0);

// Frames before hello are ignored; a second player sees the first.
const early = room.connect(() => assert.fail("no reply before hello"));
early.receive(JSON.stringify({ t: "edits", edits: [[1, 8, 1, 0]] }));
early.disconnect();
const bob = client(room, "Bob");
assert.deepEqual(bob.last("welcome").players.map((p) => p.name), ["Alice"]);
assert.equal(alice.last("joined").player.name, "Bob");

// Poses are validated in Bend and relayed to the others only.
alice.handle.receive(JSON.stringify({ t: "pose", x: 10.5, y: 9, z: -4, yaw: 1, pitch: 9 }));
const pose = bob.last("pose");
assert.equal(pose.id, alice.handle.id);
assert.ok(Math.abs(pose.pitch - 1.5533) < 1e-4, "pitch is clamped by the room");
assert.equal(alice.last("pose"), undefined);
const posesBefore = bob.inbox.length;
alice.handle.receive(JSON.stringify({ t: "pose", x: 0, y: 1e9, z: 0, yaw: 0, pitch: 0 }));
assert.equal(bob.inbox.length, posesBefore, "an out-of-world pose is dropped");

// Edits: accepted batches go to everyone in sequence order, the sender too.
alice.handle.receive(JSON.stringify({ t: "edits", edits: [[40, 8, 40, 12], [41, 8, 40, 0]] }));
assert.deepEqual(alice.last("edits"), { t: "edits", seq: 1, from: alice.handle.id, edits: [[40, 8, 40, 12], [41, 8, 40, 0]] });
assert.deepEqual(bob.last("edits"), alice.last("edits"));
assert.equal(changes, 1);

// A partly invalid batch: the valid edit lands, the sender gets the
// authoritative value of the refused in-world cell.
bob.handle.receive(JSON.stringify({ t: "edits", edits: [[40, 8, 40, 99], [42, 8, 40, 22]] }));
assert.deepEqual(alice.last("edits").edits, [[42, 8, 40, 22]]);
assert.equal(alice.last("edits").seq, 2);
assert.deepEqual(bob.last("revert"), { t: "revert", edits: [[40, 8, 40, 12]] });
assert.equal(alice.last("revert"), undefined);

// A late joiner receives the whole log.
const carol = client(room, "Carol");
assert.equal(carol.last("welcome").seq, 2);
assert.deepEqual(byCell(carol.last("welcome").edits), [[40, 8, 40, 12], [41, 8, 40, 0], [42, 8, 40, 22]]);
assert.deepEqual(carol.last("welcome").players.map((p) => p.name).sort(), ["Alice", "Bob"]);
assert.equal(carol.last("welcome").players.find((p) => p.name === "Alice").pose.x, 10.5);

// Leaving is announced once.
carol.handle.disconnect();
carol.handle.disconnect();
assert.equal(alice.inbox.filter((m) => m.t === "left").length, 1);
assert.equal(room.playerCount(), 2);

// Chests: placing one opens it for everyone; deposits and withdrawals are
// answered to the sender and the new slots go to every player.
const emptySlots = Array.from({ length: 9 }, () => [0, 0, 0]);
alice.handle.receive(JSON.stringify({ t: "edits", edits: [[30, 9, 30, 26]] }));
assert.deepEqual(bob.last("chest"), { t: "chest", pos: [30, 9, 30], slots: emptySlots });
alice.handle.receive(JSON.stringify({ t: "chest", op: "deposit", id: 7, pos: [30, 9, 30], item: 5, count: 3, durability: 0 }));
assert.deepEqual(alice.last("chest-result"), { t: "chest-result", id: 7, ok: true, op: "deposit", item: 5, amount: 3, durability: 0 });
assert.deepEqual(bob.last("chest").slots[0], [5, 3, 0]);
assert.equal(bob.last("chest-result"), undefined, "results go to the sender only");
bob.handle.receive(JSON.stringify({ t: "chest", op: "withdraw", id: 1, pos: [30, 9, 30], index: 0, amount: 2 }));
assert.deepEqual(bob.last("chest-result"), { t: "chest-result", id: 1, ok: true, op: "withdraw", item: 5, amount: 2, durability: 0 });
assert.deepEqual(alice.last("chest").slots[0], [5, 1, 0]);
// A refused operation answers ok: false and broadcasts nothing.
const chestsBefore = alice.inbox.filter((m) => m.t === "chest").length;
bob.handle.receive(JSON.stringify({ t: "chest", op: "withdraw", id: 2, pos: [31, 9, 30], index: 0, amount: 2 }));
assert.equal(bob.last("chest-result").ok, false);
assert.equal(alice.inbox.filter((m) => m.t === "chest").length, chestsBefore);
// Malformed chest messages are dropped.
assert.equal(decodeClientMessage(JSON.stringify({ t: "chest", op: "withdraw", id: 3, pos: [1, 2, 3], index: 9, amount: 1 })), null);
assert.equal(decodeClientMessage(JSON.stringify({ t: "chest", op: "burn", id: 3, pos: [1, 2, 3] })), null);
// Breaking a chest that holds items is refused; the sender gets the block and
// the chest back. Emptied, it breaks and everyone hears it is gone.
bob.handle.receive(JSON.stringify({ t: "edits", edits: [[30, 9, 30, 0]] }));
assert.deepEqual(bob.last("revert").edits, [[30, 9, 30, 26]]);
assert.deepEqual(bob.last("chest"), { t: "chest", pos: [30, 9, 30], slots: [[5, 1, 0], ...emptySlots.slice(1)] });
alice.handle.receive(JSON.stringify({ t: "chest", op: "withdraw", id: 8, pos: [30, 9, 30], index: 0, amount: 64 }));
alice.handle.receive(JSON.stringify({ t: "edits", edits: [[30, 9, 30, 0]] }));
assert.deepEqual(bob.last("chest"), { t: "chest", pos: [30, 9, 30], slots: null });
alice.handle.receive(JSON.stringify({ t: "edits", edits: [[31, 9, 31, 26]] }));
alice.handle.receive(JSON.stringify({ t: "chest", op: "deposit", id: 9, pos: [31, 9, 31], item: 33, count: 1, durability: 12 }));

// Furnaces: placed by an edit, loaded and emptied through the room, smelted by
// tick(); every change reaches every player.
alice.handle.receive(JSON.stringify({ t: "edits", edits: [[33, 9, 33, 11]] }));
assert.deepEqual(bob.last("furnace"), { t: "furnace", pos: [33, 9, 33], state: [0, 0, 0, 0, 0, 0, 0, 0] });
alice.handle.receive(JSON.stringify({ t: "furnace", op: "input", id: 20, pos: [33, 9, 33], item: 15 }));
assert.deepEqual(alice.last("furnace-result"), { t: "furnace-result", id: 20, ok: true, op: "input", item: 15, amount: 1 });
bob.handle.receive(JSON.stringify({ t: "furnace", op: "fuel", id: 21, pos: [33, 9, 33], item: 14 }));
assert.equal(bob.last("furnace-result").ok, true);
bob.handle.receive(JSON.stringify({ t: "furnace", op: "input", id: 22, pos: [33, 9, 33], item: 3 }));
assert.equal(bob.last("furnace-result").ok, false, "dirt does not smelt");
assert.deepEqual(alice.last("furnace").state, [15, 1, 14, 1, 0, 0, 0, 0]);
for (let step = 0; step < 8; step += 1) room.tick();
assert.deepEqual(bob.last("furnaces").furnaces, [{ pos: [33, 9, 33], state: [0, 0, 14, 0, 20, 1, 0, 0] }]);
const furnaceMessages = bob.inbox.filter((m) => m.t === "furnaces").length;
assert.equal(room.tick(), 0, "an idle furnace sends nothing");
assert.equal(bob.inbox.filter((m) => m.t === "furnaces").length, furnaceMessages);
bob.handle.receive(JSON.stringify({ t: "furnace", op: "output", id: 23, pos: [33, 9, 33] }));
assert.deepEqual(bob.last("furnace-result"), { t: "furnace-result", id: 23, ok: true, op: "output", item: 20, amount: 1 });
alice.handle.receive(JSON.stringify({ t: "edits", edits: [[34, 9, 33, 11]] }));

// The world clock: late joiners get the current time; "morning" resets it for all.
clock += 90_000;
const late = client(room, "Late");
assert.equal(late.last("welcome").time, 90);
assert.deepEqual(late.last("welcome").chests, [{ pos: [31, 9, 31], slots: [[33, 1, 12], ...emptySlots.slice(1)] }]);
assert.deepEqual(late.last("welcome").furnaces.map((f) => f.pos), [[34, 9, 33], [33, 9, 33]]);
bob.handle.receive(JSON.stringify({ t: "time", op: "morning" }));
assert.deepEqual(alice.last("time"), { t: "time", time: 0 });
assert.equal(room.worldTime(), 0);
clock += 5_000;
late.handle.disconnect();

// Snapshots resume the same world; a snapshot for another seed is refused.
const snapshot = room.snapshot();
assert.deepEqual({ ...snapshot, edits: byCell(snapshot.edits) }, {
  version: 3,
  seed: "1337",
  seq: 8,
  edits: byCell([[40, 8, 40, 12], [41, 8, 40, 0], [42, 8, 40, 22], [30, 9, 30, 0], [31, 9, 31, 26], [33, 9, 33, 11], [34, 9, 33, 11]]),
  chests: [{ pos: [31, 9, 31], slots: [[33, 1, 12], ...emptySlots.slice(1)] }],
  furnaces: [{ pos: [34, 9, 33], state: [0, 0, 0, 0, 0, 0, 0, 0] }, { pos: [33, 9, 33], state: [0, 0, 14, 0, 0, 0, 0, 0] }],
  time: 5,
  simulation: null,
});
const resumed = createMultiplayerRoom({ authority: Multiplayer, seed: SEED, now, snapshot: JSON.parse(JSON.stringify(snapshot)) });
const dave = client(resumed, "Dave");
assert.equal(dave.last("welcome").seq, 8);
assert.deepEqual(dave.last("welcome").edits, snapshot.edits);
assert.deepEqual(dave.last("welcome").chests, snapshot.chests);
assert.deepEqual(dave.last("welcome").furnaces, snapshot.furnaces);
assert.equal(dave.last("welcome").time, 5, "the clock resumes where it stopped");
// A version 1 snapshot (edits only) still loads.
const legacy = createMultiplayerRoom({
  authority: Multiplayer, seed: SEED, snapshot: { version: 1, seed: "1337", seq: 1, edits: [[1, 8, 1, 0]] },
});
assert.deepEqual(legacy.snapshot().edits, [[1, 8, 1, 0]]);
assert.deepEqual(legacy.snapshot().chests, []);
assert.throws(() => createMultiplayerRoom({ authority: Multiplayer, seed: 7n, snapshot }));

// Replaying the welcome log plus later batches gives the room's world.
let local = wireEditsToBend(dave.last("welcome").edits);
assert.equal(Number(WorldState.block(local, SEED, 42n, 8n, 40n)), 22);
assert.equal(Number(WorldState.block(local, SEED, 31n, 9n, 31n)), 26);
assert.equal(Number(WorldState.block(local, SEED, 20n, 8n, 20n)), Number(World.block(SEED, 20n, 8n, 20n)));
void local;

// Version mismatch and a full server are refused with a reason.
const stale = [];
const staleClosed = [];
room.connect((text) => stale.push(JSON.parse(text)), (code) => staleClosed.push(code))
  .receive(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION + 1, name: "Old" }));
assert.equal(stale[0].t, "error");
assert.deepEqual(staleClosed, [1008]);
const full = createMultiplayerRoom({ authority: Multiplayer, seed: SEED });
for (let index = 0; index < MAX_PLAYERS; index += 1) client(full, `P${index}`);
const extra = client(full, "Extra");
assert.equal(extra.inbox[0].t, "error");
assert.equal(full.playerCount(), MAX_PLAYERS);

console.log("multiplayer room ok");
