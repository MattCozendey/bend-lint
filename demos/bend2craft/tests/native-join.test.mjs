// A native client and a browser player in one room, end to end: the real room, the real
// native door on a real socket, and the native client's own session code
// (lab/native/net/join_probe.bend) compiled and run by the pinned Bend.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { TICK_MS, createMultiplayerRoom } from "../server/multiplayer-room.js";
import { createServerWorld } from "../server/server-world.js";
import { attachNativeBridge } from "../server/native-bridge.mjs";
import { PROTOCOL_VERSION } from "../web/multiplayer-protocol.js";
import { Multiplayer, World } from "../web/bend-modules.js";

const root = fileURLToPath(new URL("..", import.meta.url));
// The room simulates its world, as the play server's does, so there are animals to be told of.
const room = createMultiplayerRoom({ authority: Multiplayer, seed: 1337n, createServerWorld, peaceful: true });
const ticking = setInterval(() => room.tick(), TICK_MS);
const inbox = [];
const web = room.connect((text) => inbox.push(JSON.parse(text)));
const say = (message) => web.receive(JSON.stringify(message));
say({ t: "hello", v: PROTOCOL_VERSION, name: "Browser" });
// The browser dug a block before the native client arrived.
say({ t: "edits", edits: [[25, 9, 25, 0]] });
// And it stands somewhere, which the native client is told when it joins.
say({ t: "pose", x: 30.5, y: 10, z: 26.5, yaw: 1.5, pitch: 0 });
// And it threw two stone down on the open ground the native client will stand on.
say({ t: "drop", item: 1, amount: 2, x: 56.5, y: 12, z: 41.5 });
// And it stood a chest beside that spot and put five dirt in it.
const chestY = Number(World.column_height(1337n, 58n, 41n));
say({ t: "edits", edits: [[58, chestY, 41, 26]] });
say({ t: "chest", op: "deposit", id: 1, pos: [58, chestY, 41], item: 2, count: 5, durability: 0 });

const bridge = attachNativeBridge(room, { host: "127.0.0.1", port: 0 });
await new Promise((resolve) => bridge.once("listening", resolve));

const probe = spawn("bash", ["scripts/check-bend.sh", "lab/native/net/join_probe.bend"], {
  cwd: root,
  env: { ...process.env, BEND_NO_TELEMETRY: "1", B2C_JOIN: `127.0.0.1:${bridge.address().port}` },
});
let output = "";
probe.stdout.on("data", (chunk) => { output += chunk; });
probe.stderr.on("data", (chunk) => { output += chunk; });
const exited = new Promise((resolve) => probe.once("exit", resolve));

// When the browser hears the native client's block, it places one of its own.
let answered = false;
const watch = setInterval(() => {
  const mine = inbox.find((m) => m.t === "edits" && m.from !== 1 && m.edits.some((e) => e.join() === "30,9,25,1"));
  if (mine && !answered) {
    answered = true;
    say({ t: "edits", edits: [[31, 9, 25, 1]] });
  }
}, 10);

const timeout = setTimeout(() => probe.kill(), 60000);
const code = await exited;
clearInterval(watch);
clearInterval(ticking);
clearTimeout(timeout);
await new Promise((resolve) => bridge.close(resolve));

assert.equal(code, 0, `the native client did not finish:\n${output}`);
assert.match(output, /join_probe: heard the room's log/, "the native client read the room's log on joining");
assert.match(output, /join_probe: saw the browser's player/, "the native client was told the browser's player by name and where it stands");
assert.match(output, /join_probe: heard the room's hour/, "the native client was told the room's hour and timed it");
assert.match(output, /join_probe: saw what the room simulates/, "the native client was told the room's mobs");
assert.match(output, /join_probe: picked up the item beside it/, "the native client asked for the item at its feet and was handed it");
assert.match(output, /join_probe: took the dirt out of the room's chest/, "the native client clicked the room's chest and was handed what it held");
assert.match(output, /join_probe=pass/, "the native client heard the browser's later edit");
assert.ok(
  inbox.some((m) => m.t === "chest" && m.pos.join() === `58,${chestY},41` && m.slots !== null && m.slots.every((slot) => slot[1] === 0)),
  "the browser was told the chest is empty after the native client took from it",
);
// The native client stands in the middle of world cell (56, 41), and says so.
assert.ok(
  inbox.some((m) => m.t === "pose" && m.id !== 1 && Math.abs(m.x - 56.5) < 0.01 && Math.abs(m.z - 41.5) < 0.01),
  "the browser was told where the native player stands",
);
assert.ok(inbox.some((m) => m.t === "joined" && m.player.name === "Native"), "the browser saw the native player join");
assert.ok(answered, "the browser heard the block the native client placed");
console.log("native join ok");
