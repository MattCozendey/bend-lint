// The native client's door into a multiplayer room (server/native-bridge.mjs): a line
// protocol over plain TCP, translated to and from the room the browsers are in. The lines
// are the ones native/net.bend writes and reads; native/net_test.bend holds that side.
import assert from "node:assert/strict";
import * as net from "node:net";
import { createMultiplayerRoom } from "../server/multiplayer-room.js";
import { MAX_NATIVE_LINE, attachNativeBridge, connectNative, nativeLines } from "../server/native-bridge.mjs";
import { PROTOCOL_VERSION } from "../web/multiplayer-protocol.js";
import { Multiplayer } from "../web/bend-modules.js";

const SEED = 1337n;
const room = createMultiplayerRoom({ authority: Multiplayer, seed: SEED });

const joinWeb = (name) => {
  const inbox = [];
  const handle = room.connect((text) => inbox.push(JSON.parse(text)));
  handle.receive(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, name }));
  return { inbox, send: (message) => handle.receive(JSON.stringify(message)) };
};

const joinNative = () => {
  const lines = [];
  let ended = false;
  const handle = connectNative(room, (text) => {
    assert.ok(text.endsWith("\n"), "the bridge writes whole lines");
    lines.push(...text.slice(0, -1).split("\n"));
  }, () => { ended = true; });
  return { lines, handle, ended: () => ended, send: (text) => handle.receive(text) };
};

// A browser is in the room and has already dug a block.
const web = joinWeb("Bia");
web.send({ t: "edits", edits: [[25, 9, 25, 0]] });
assert.deepEqual(web.inbox.at(-1), { t: "edits", seq: 1, from: 1, edits: [[25, 9, 25, 0]] });

// A native client joins: it is told who it is, which world this is, and every cell the
// room's log holds.
const native = joinNative();
native.send("H 1 Lucas\n");
assert.equal(native.lines[0], "W 2 1337", "the welcome is the player's id and the world's seed");
assert.equal(native.lines[1], "B 25 9 25 0", "the room's log arrives as block lines");
assert.equal(native.lines[3], "J 1 Bia", "and who is in the room, by name");
// And what hour it is: how far round the room's day, in thousandths of a radian, and how
// long that day is, in milliseconds. The room has only just opened.
assert.match(native.lines[2], /^T \d+ 78540$/, "the welcome says the hour and the length of a day");
assert.ok(Number(native.lines[2].split(" ")[1]) < 100, "a room just opened is at the start of its day");
assert.equal(native.lines.length, 4);
assert.equal(web.inbox.at(-1).t, "joined");
assert.equal(web.inbox.at(-1).player.name, "Lucas", "the browser sees the native player join by name");
assert.equal(room.playerCount(), 2);

// The native client places a block: the browser hears it as an ordinary edit batch, and
// the native client hears its own edit back, as every player of the room does.
native.lines.length = 0;
native.send("E 26 9 25 1\n");
assert.deepEqual(web.inbox.at(-1), { t: "edits", seq: 2, from: 2, edits: [[26, 9, 25, 1]] });
assert.deepEqual(native.lines, ["B 26 9 25 1"]);

// The browser digs it again: the native client hears the cell.
native.lines.length = 0;
web.send({ t: "edits", edits: [[26, 9, 25, 0]] });
assert.deepEqual(native.lines, ["B 26 9 25 0"]);

// TCP hands over bytes, not lines: an edit split across two chunks is one edit, and two
// edits in one chunk are one batch.
native.lines.length = 0;
native.send("E 27 9");
assert.deepEqual(native.lines, [], "half a line is not an edit");
native.send(" 25 1\nE 28 9 25 1\nE 29");
assert.deepEqual(web.inbox.at(-1).edits, [[27, 9, 25, 1], [28, 9, 25, 1]], "the two whole lines are one batch");
native.send(" 9 25 1\n");
assert.deepEqual(web.inbox.at(-1).edits, [[29, 9, 25, 1]]);

// An edit the room refuses reaches nobody. This one is above the top of the world, a cell
// the room has no value to send back for.
native.lines.length = 0;
const before = web.inbox.length;
native.send("E 25 400 25 1\n");
assert.equal(web.inbox.length, before, "a refused edit reaches no other player");
assert.deepEqual(native.lines, [], "and is not echoed to its sender as accepted");

// Lines that are not the protocol's are dropped, not guessed at.
native.lines.length = 0;
native.send("E 1 2 3\nE a b c d\nQ 1 2 3 4\n\nE 1 2 3 -4\nE 1 2 3 4.5\n");
assert.deepEqual(native.lines, []);
assert.equal(native.ended(), false, "noise does not end the connection");

// Where a player is goes both ways, in whole thousandths: world coordinates, feet first,
// as on the browser's wire. The native client says where it is and the browser hears a pose.
native.lines.length = 0;
native.send("P 25500 9050 -3250 -500 250\n");
assert.deepEqual(web.inbox.at(-1), { t: "pose", id: 2, x: 25.5, y: 9.05, z: -3.25, yaw: -0.5, pitch: 0.25 });
assert.deepEqual(native.lines, [], "a player is not told its own pose");

// The browser moves: the native client hears who and where.
web.send({ t: "pose", x: 30.5, y: 10, z: -26.5, yaw: 1.5, pitch: -0.25 });
assert.deepEqual(native.lines, ["P 1 30500 10000 -26500 1500 -250"]);

// A pose that is not five whole numbers is dropped.
native.lines.length = 0;
const posesBefore = web.inbox.length;
native.send("P 1 2 3 4\nP 1 2 3 4 x\nP 1.5 2 3 4 5\n");
assert.equal(web.inbox.length, posesBefore, "a malformed pose reaches nobody");

// A player who joins after others have moved is told where they are, after the world.
const late = joinNative();
late.send("H 1 Late\n");
assert.ok(late.lines.includes("P 1 30500 10000 -26500 1500 -250"), "the welcome names the browser's pose");
assert.ok(late.lines.includes("P 2 25500 9050 -3250 -500 250"), "and the other native player's");
assert.ok(late.lines.indexOf("J 2 Lucas") < late.lines.indexOf("P 2 25500 9050 -3250 -500 250"), "each by name before its place");
assert.ok(native.lines.includes("J 3 Late"), "a native client is told who joined");
native.lines.length = 0;
late.handle.disconnect();
assert.deepEqual(native.lines, ["L 3"], "a native client is told who left");

// A hit and a pickup are the room's own requests, numbered by the bridge. This room
// simulates nothing, so it answers that the hit missed and the pickup was refused, and the
// client is told neither.
native.lines.length = 0;
const counted = room.counters().dropped;
native.send("A 7 4000\nK 3\nA 7\nK x\n");
assert.equal(room.counters().dropped, counted, "a hit and a pickup are messages the room reads");
assert.deepEqual(native.lines, [], "a miss and a refusal are not sent to the client");

// A chest: the browser places one, which makes it the room's. The native client is told it
// is there and empty, puts ten stone in it and is answered, and every player is told what
// the chest holds; then it takes four back and is told what came out.
web.send({ t: "edits", edits: [[40, 9, 25, 26]] });
native.lines.length = 0;
native.send("CD 40 9 25 1 10 0\n");
assert.ok(native.lines.includes("R 1 1 10 0"), `a deposit the room took is answered: ${native.lines}`);
assert.ok(native.lines.some((line) => line.startsWith("S 40 9 25 1 10 0")), "and the chest's slots are told");
assert.deepEqual(web.inbox.at(-1).slots[0], [1, 10, 0], "the browser is told the same chest");
native.lines.length = 0;
native.send("CW 40 9 25 0 4\n");
assert.ok(native.lines.includes("R 1 1 4 0"), "a withdrawal is answered with what came out");
assert.ok(native.lines.some((line) => line.startsWith("S 40 9 25 1 6 0")), "and the chest holds the rest");
native.lines.length = 0;
native.send("CW 41 9 25 0 4\n");
assert.deepEqual(native.lines, ["R 0 0 0 0"], "a chest that is not there is a refusal");

// A furnace: sand to smelt and coal to burn, one item a request.
web.send({ t: "edits", edits: [[42, 9, 25, 11]] });
native.lines.length = 0;
native.send("FI 42 9 25 6\nFF 42 9 25 14\n");
assert.equal(native.lines.filter((line) => line === "R 1 6 1 0" || line === "R 1 14 1 0").length, 2, `both loads are answered: ${native.lines}`);
assert.ok(native.lines.some((line) => line.startsWith("O 42 9 25 6 1 14 1")), "and the furnace is told as it now is");
assert.equal(nativeLines({ t: "chest", pos: [1, 2, 3], slots: null }), "S 1 2 3\n", "a chest that is gone is its cell alone");
assert.equal(nativeLines({ t: "furnaces", furnaces: [{ pos: [1, 2, 3], state: [6, 1, 14, 1, 0, 0, 2, 6] }] }), "O 1 2 3 6 1 14 1 0 0 2 6\n");

// Leaving: the browser is told, as for any player.
native.handle.disconnect();
assert.deepEqual(web.inbox.at(-1), { t: "left", id: 2 });
assert.equal(room.playerCount(), 1);

// A client that speaks another version is refused in words and the connection ends.
const old = joinNative();
old.send("H 7 Old\n");
assert.match(old.lines[0], /^X .*protocol 1/);
assert.equal(old.ended(), true);
assert.equal(room.playerCount(), 1, "a refused client never joined");

// Anything before the hello is refused too, and so is a line that never ends.
const rude = joinNative();
rude.send("E 1 2 3 4\n");
assert.match(rude.lines[0], /^X /);
assert.equal(rude.ended(), true);
const endless = joinNative();
endless.send("H 1 ");
endless.send("x".repeat(MAX_NATIVE_LINE + 1));
assert.equal(endless.ended(), true, "a line past the limit ends the connection");

// A move the room refuses comes back as where the player stands.
assert.equal(nativeLines({ t: "correct", x: 25.5, y: 9, z: -1.5 }), "C 25500 9000 -1500\n");
assert.equal(nativeLines({ t: "pose", id: 1, x: -0.0001, y: 0, z: 0, yaw: 0, pitch: 0 }), "P 1 0 0 0 0 0\n");
// What the room says that the native client has no use for yet is not sent. A player who
// has only joined is a name with no pose: it is drawn when it first says where it is.
assert.equal(nativeLines({ t: "interact-result", id: 1, ok: true, op: "till" }), "");
// The room's clock is seconds; a native client is told the angle of the day. A morning
// someone called is the start of a day, and a quarter of a day on is a quarter turn.
assert.equal(nativeLines({ t: "time", time: 0 }), "T 0 78540\n");
assert.equal(nativeLines({ t: "time", time: 78.54 / 4 }), "T 1571 78540\n");
assert.equal(nativeLines({ t: "time", time: 78.54 * 3 + 78.54 / 4 }), "T 1571 78540\n");
assert.equal(nativeLines({ t: "joined", player: { id: 3, name: "Ana Lua", pose: null } }), "J 3 Ana Lua\n");
// What the room simulates is one list, ended by `N`: a living mob with the yaw its heading
// comes to, an item on the ground, a villager. A dead mob is not in it.
assert.equal(
  nativeLines({
    t: "entities",
    mobs: [[7, 5, 12.5, 9, -3, 1, 0, 10, 1, 0, 0], [8, 2, 1, 2, 3, 0, -1, 0, 0, 0, 0]],
    drops: [[3, 4, 12.5, 9, -3, 2]],
    villagers: [[1, 2, 12.5, 9, -3, 40, 40, 0]],
  }),
  "M 7 5 12500 9000 -3000 1571\nD 3 4 2 12500 9000 -3000\nV 2 12500 9000 -3000\nN\n",
);
assert.equal(nativeLines({ t: "entities", mobs: [], drops: [] }), "N\n", "nothing simulated is an empty list");
// Being hurt is an amount, and an item the room handed over is the item; a pickup the room
// refused is nothing, and so is the answer to a hit, which the next list shows.
assert.equal(nativeLines({ t: "hurt", amount: 1.5 }), "U 1500\n");
assert.equal(nativeLines({ t: "pickup-result", id: 4, drop: 3, ok: true, item: 13, amount: 2 }), "G 13 2\n");
assert.equal(nativeLines({ t: "pickup-result", id: 4, drop: 3, ok: false, item: 0, amount: 0 }), "");
assert.equal(nativeLines({ t: "attack-result", id: 4, mob: 7, hit: true, killed: false, kind: 1 }), "");
assert.equal(nativeLines({ t: "revert", edits: [[1, 2, 3, 4]] }), "B 1 2 3 4\n");
assert.equal(nativeLines({ t: "error", message: "The server is\nfull" }), "X The server is full\n");

// Over a real socket: the same exchange through the port the server opens.
const bridge = attachNativeBridge(room, { host: "127.0.0.1", port: 0 });
await new Promise((resolve) => bridge.once("listening", resolve));
const socket = net.connect(bridge.address().port, "127.0.0.1");
let received = "";
socket.setEncoding("utf8");
socket.on("data", (chunk) => { received += chunk; });
const until = async (done) => {
  for (let tries = 0; tries < 200 && !done(); tries += 1) await new Promise((resolve) => setTimeout(resolve, 10));
  assert.ok(done(), `timed out; received ${JSON.stringify(received)}`);
};
socket.write("H 1 Socket\n");
await until(() => received.includes("W ") && received.split("\n").length > 5);
assert.match(received, /^W \d+ 1337\n/);
assert.ok(received.includes("B 27 9 25 1\n"), "the log over the socket holds the earlier edits");
received = "";
socket.write("E 30 9 25 1\n");
await until(() => received.includes("B 30 9 25 1\n"));
assert.deepEqual(web.inbox.at(-1).edits, [[30, 9, 25, 1]], "the browser hears the edit sent over the socket");
socket.end();
await until(() => web.inbox.at(-1).t === "left");
await new Promise((resolve) => bridge.close(resolve));

console.log("native bridge ok");
