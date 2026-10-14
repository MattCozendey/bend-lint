// Hosts one multiplayer room on a Node http server: WebSocket upgrades on
// MULTIPLAYER_PATH, and the room's edit log saved to a JSON file.
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { MAX_MESSAGE_BYTES, MULTIPLAYER_PATH } from "../web/multiplayer-protocol.js";
import { TICK_MS, createMultiplayerRoom } from "./multiplayer-room.js";
import { acceptWebSocket } from "./websocket.mjs";

const SAVE_DELAY_MS = 2000;

function readSnapshot(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw new Error(`Could not read the multiplayer world ${file}: ${error.message}`);
  }
}

function writeSnapshot(file, snapshot) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(snapshot)}\n`);
  fs.renameSync(temporary, file);
}

/** The IPv4 addresses other machines on the network can use to reach this one. */
export function lanAddresses() {
  const addresses = [];
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries ?? []) {
      if ((entry.family === "IPv4" || entry.family === 4) && !entry.internal) addresses.push(entry.address);
    }
  }
  return addresses;
}

/**
 * @param {import("node:http").Server} server
 * @param {object} options
 * @param {object} options.authority  the compiled world/multiplayer.bend module
 * @param {bigint} options.seed        seed for a new world (a saved world keeps its own)
 * @param {string|null} options.file   where the world is saved; null keeps it in memory
 * @param {Function} [options.createServerWorld]  the server-simulated world
 * @param {boolean} [options.peaceful]  no monsters
 */
export function attachMultiplayer(server, {
  authority, seed, file = null, log = console.log, createServerWorld = null, peaceful = false,
}) {
  const saved = file === null ? null : readSnapshot(file);
  const worldSeed = saved === null ? seed : BigInt(saved.seed);
  let saveTimer = null;
  const save = () => {
    saveTimer = null;
    if (file === null) return;
    try {
      writeSnapshot(file, room.snapshot());
    } catch (error) {
      log(`Could not save the multiplayer world: ${error.message}`);
    }
  };
  const room = createMultiplayerRoom({
    authority,
    seed: worldSeed,
    snapshot: saved,
    createServerWorld,
    peaceful,
    onChange: () => {
      if (saveTimer === null) saveTimer = setTimeout(save, SAVE_DELAY_MS);
    },
    onPresence: (event, player) => {
      log(`${player.name} ${event === "joined" ? "joined" : "left"} (${room.playerCount()} online).`);
    },
  });

  // Furnaces smelt on the server's clock.
  // The block simulation changes every tick; it is saved every 30 seconds.
  let ticks = 0;
  const ticker = setInterval(() => {
    room.tick();
    ticks += 1;
    if (ticks % 150 === 0 && room.simulationState() !== null && saveTimer === null) {
      saveTimer = setTimeout(save, SAVE_DELAY_MS);
    }
  }, TICK_MS);
  ticker.unref?.();
  server.on("close", () => clearInterval(ticker));

  server.on("upgrade", (request, socket, head) => {
    let pathname = "";
    try {
      pathname = new URL(request.url ?? "/", "http://localhost").pathname;
    } catch {
      pathname = "";
    }
    if (pathname !== MULTIPLAYER_PATH) {
      socket.end("HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
      return;
    }
    let handle = null;
    const connection = acceptWebSocket(request, socket, head, {
      maxPayload: MAX_MESSAGE_BYTES,
      onMessage: (text) => handle?.receive(text),
      onClose: () => handle?.disconnect(),
    });
    if (connection === null) return;
    handle = room.connect((text) => connection.send(text), (code, reason) => connection.close(code, reason));
  });

  return {
    room,
    seed: worldSeed,
    // Saves now (on shutdown), so the world clock resumes where it stopped.
    flush() {
      if (saveTimer !== null) clearTimeout(saveTimer);
      save();
    },
  };
}
