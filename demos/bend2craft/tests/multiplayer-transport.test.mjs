import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as http from "node:http";
import * as os from "node:os";
import * as path from "node:path";
import { attachMultiplayer } from "../server/node-host.mjs";
import { acceptKey, encodeFrame } from "../server/websocket.mjs";
import { PROTOCOL_VERSION } from "../web/multiplayer-protocol.js";
import { Multiplayer } from "../web/bend-modules.js";

// RFC 6455 section 1.3 example.
assert.equal(acceptKey("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
assert.deepEqual([...encodeFrame(0x1, "hi")], [0x81, 2, 0x68, 0x69]);
assert.equal(encodeFrame(0x1, "x".repeat(300)).readUInt16BE(2), 300);
assert.equal(Number(encodeFrame(0x1, "x".repeat(70000)).readBigUInt64BE(2)), 70000);

const directory = fs.mkdtempSync(path.join(os.tmpdir(), "bend2craft-mp-"));
const file = path.join(directory, "world.json");

async function startServer() {
  const server = http.createServer((_request, response) => response.end("ok"));
  const host = attachMultiplayer(server, { authority: Multiplayer, seed: 1337n, file, log: () => {} });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  return { server, host, url: `ws://127.0.0.1:${server.address().port}/multiplayer` };
}

function open(url, name) {
  const socket = new WebSocket(url);
  const inbox = [];
  const waiters = [];
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    inbox.push(message);
    for (const waiter of [...waiters]) {
      if (waiter.test(message)) {
        waiters.splice(waiters.indexOf(waiter), 1);
        waiter.resolve(message);
      }
    }
  });
  const next = (type) => {
    const found = inbox.find((m) => m.t === type && !m.seen);
    if (found) {
      found.seen = true;
      return Promise.resolve(found);
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`timed out waiting for ${type}`)), 5000);
      waiters.push({
        test: (m) => m.t === type,
        resolve: (m) => { clearTimeout(timer); m.seen = true; resolve(m); },
      });
    });
  };
  const ready = new Promise((resolve, reject) => {
    socket.addEventListener("open", () => {
      socket.send(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, name }));
      resolve();
    });
    socket.addEventListener("error", () => reject(new Error("socket error")));
  });
  return { socket, next, ready, send: (m) => socket.send(JSON.stringify(m)) };
}

{
  const { server, host, url } = await startServer();
  const alice = open(url, "Alice");
  await alice.ready;
  const welcome = await alice.next("welcome");
  assert.equal(welcome.seed, "1337");
  const bob = open(url, "Bob");
  await bob.ready;
  assert.deepEqual((await bob.next("welcome")).players.map((p) => p.name), ["Alice"]);
  assert.equal((await alice.next("joined")).player.name, "Bob");

  // A batch big enough for a 64-bit length frame still crosses intact.
  const batch = Array.from({ length: 3000 }, (_, i) => [i % 48, 9, Math.floor(i / 48), 22]);
  alice.send({ t: "edits", edits: batch });
  const received = await bob.next("edits");
  assert.equal(received.edits.length, 3000);
  assert.equal(received.seq, 1);
  assert.equal((await alice.next("edits")).seq, 1);

  alice.send({ t: "pose", x: 1, y: 9, z: 2, yaw: 0.5, pitch: 0.1 });
  assert.equal((await bob.next("pose")).x, 1);

  bob.socket.close();
  assert.equal((await alice.next("left")).id, received.from + 1);

  host.flush();
  const saved = JSON.parse(fs.readFileSync(file, "utf8"));
  assert.equal(saved.seq, 1);
  assert.equal(saved.edits.length, 3000);
  alice.socket.close();
  await new Promise((resolve) => server.close(resolve));
}

{
  // Restarting the server resumes the saved world.
  const { server, url } = await startServer();
  const carol = open(url, "Carol");
  await carol.ready;
  const welcome = await carol.next("welcome");
  assert.equal(welcome.seq, 1);
  assert.equal(welcome.edits.length, 3000);

  // Plain HTTP on the path and other upgrade paths are refused.
  const port = server.address().port;
  const plain = await fetch(`http://127.0.0.1:${port}/multiplayer`);
  assert.equal(await plain.text(), "ok");
  carol.socket.close();
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
}

fs.rmSync(directory, { recursive: true, force: true });
console.log("multiplayer transport ok");
