import { mkdir, rm } from "node:fs/promises";
import * as path from "node:path";
import bendPlugin from "../vendor/bend/bend2/main.ts";
import { Multiplayer } from "../web/bend-modules.js";
import { TICK_MS, createMultiplayerRoom } from "../server/multiplayer-room.js";
import { createServerWorld } from "../server/server-world.js";
import { MAX_MESSAGE_BYTES, MULTIPLAYER_PATH } from "../web/multiplayer-protocol.js";

const outdir = path.resolve(".dev");
await rm(outdir, { recursive: true, force: true });
await mkdir(outdir, { recursive: true });
const page = await Bun.build({
  entrypoints: [path.resolve("web/index.html")],
  outdir,
  plugins: [bendPlugin],
  target: "browser",
  minify: false,
  sourcemap: "none",
});
if (!page.success) {
  console.error(page.logs);
  process.exit(1);
}
const worker = await Bun.build({
  entrypoints: [path.resolve("web/chunk-worker-entry.js")],
  outdir,
  plugins: [bendPlugin],
  target: "browser",
  minify: false,
  sourcemap: "none",
});
if (!worker.success) {
  console.error(worker.logs);
  process.exit(1);
}
await Bun.write(path.join(outdir, "chunk-worker.js"), await worker.outputs[0].arrayBuffer());
const meshWorker = await Bun.build({
  entrypoints: [path.resolve("web/mesh-worker-entry.js")],
  outdir,
  target: "browser",
  minify: false,
  sourcemap: "none",
});
if (!meshWorker.success) {
  console.error(meshWorker.logs);
  process.exit(1);
}
await Bun.write(path.join(outdir, "mesh-worker.js"), await meshWorker.outputs[0].arrayBuffer());
const lodWorker = await Bun.build({
  entrypoints: [path.resolve("web/lod-worker-entry.js")],
  outdir,
  plugins: [bendPlugin],
  target: "browser",
  minify: false,
  sourcemap: "none",
});
if (!lodWorker.success) {
  console.error(lodWorker.logs);
  process.exit(1);
}
await Bun.write(path.join(outdir, "lod-worker.js"), await lodWorker.outputs[0].arrayBuffer());

// The dev server hosts an in-memory multiplayer room (nothing is saved), so
// `?play=1&mp=1` works against it the same way it does against play-server.
const room = createMultiplayerRoom({
  authority: Multiplayer,
  seed: BigInt(process.env.SEED ?? "1337"),
  createServerWorld,
  peaceful: process.env.PEACEFUL === "1",
});
setInterval(() => room.tick(), TICK_MS);

const server = Bun.serve({
  port: Number(process.env.PORT ?? 3000),
  websocket: {
    maxPayloadLength: MAX_MESSAGE_BYTES,
    open(socket) {
      socket.data.handle = room.connect((text) => socket.send(text), (code, reason) => socket.close(code, reason));
    },
    message(socket, message) {
      socket.data.handle.receive(typeof message === "string" ? message : new TextDecoder().decode(message));
    },
    close(socket) {
      socket.data.handle?.disconnect();
    },
  },
  async fetch(request, bunServer) {
    const url = new URL(request.url);
    if (url.pathname === MULTIPLAYER_PATH) {
      if (bunServer.upgrade(request, { data: { handle: null } })) return undefined;
      return new Response("Expected a WebSocket upgrade", { status: 426 });
    }
    const relative = url.pathname === "/" ? "/index.html" : url.pathname;
    const file = Bun.file(path.join(outdir, relative));
    if (await file.exists()) return new Response(file);
    return new Response("Not found", { status: 404 });
  },
});
console.log(`url: ${server.url}`);
await new Promise(() => {});
