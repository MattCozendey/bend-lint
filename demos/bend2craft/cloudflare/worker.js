// Cloudflare deployment: one Worker serves the built game from dist/ and
// routes /multiplayer to a Durable Object that holds the shared world. The
// Durable Object runs the same room as the Node server, with the compiled Bend
// authority, and keeps the edit log in its SQLite storage.
//
// Deploy with `npm run build` and then `npx wrangler deploy` (see README).
import { DurableObject } from "cloudflare:workers";
import authority, { createServerWorld } from "../dist/multiplayer-authority.js";
import { TICK_MS, createMultiplayerRoom, SNAPSHOT_VERSION } from "../server/multiplayer-room.js";

// Furnace smelting changes state five times a second; its rows are written at
// most this often so a long smelt stays inside the free plan's write budget.
const TICK_SAVE_MS = 30_000;
import { MAX_MESSAGE_BYTES, MULTIPLAYER_PATH } from "../web/multiplayer-protocol.js";

const DEFAULT_SEED = "1337";

export class MultiplayerWorld extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    const sql = ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
    sql.exec(
      "CREATE TABLE IF NOT EXISTS edits (x INTEGER NOT NULL, y INTEGER NOT NULL, z INTEGER NOT NULL,"
      + " block INTEGER NOT NULL, PRIMARY KEY (x, y, z))",
    );
    sql.exec(
      "CREATE TABLE IF NOT EXISTS chests (x INTEGER NOT NULL, y INTEGER NOT NULL, z INTEGER NOT NULL,"
      + " slots TEXT NOT NULL, PRIMARY KEY (x, y, z))",
    );
    sql.exec(
      "CREATE TABLE IF NOT EXISTS furnaces (x INTEGER NOT NULL, y INTEGER NOT NULL, z INTEGER NOT NULL,"
      + " state TEXT NOT NULL, PRIMARY KEY (x, y, z))",
    );
    const meta = new Map(sql.exec("SELECT key, value FROM meta").toArray().map((row) => [row.key, row.value]));
    const configured = /^\d+$/.test(String(env.SEED ?? "")) ? String(env.SEED) : DEFAULT_SEED;
    const seed = meta.get("seed") ?? configured;
    if (!meta.has("seed")) sql.exec("INSERT INTO meta (key, value) VALUES ('seed', ?)", seed);
    const edits = sql.exec("SELECT x, y, z, block FROM edits").toArray().map((row) => [row.x, row.y, row.z, row.block]);
    const chests = sql.exec("SELECT x, y, z, slots FROM chests").toArray()
      .map((row) => ({ pos: [row.x, row.y, row.z], slots: JSON.parse(row.slots) }));
    const furnaces = sql.exec("SELECT x, y, z, state FROM furnaces").toArray()
      .map((row) => ({ pos: [row.x, row.y, row.z], state: JSON.parse(row.state) }));
    const saveFurnace = ({ pos: [x, y, z], state }) => {
      if (state === null) sql.exec("DELETE FROM furnaces WHERE x = ? AND y = ? AND z = ?", x, y, z);
      else {
        sql.exec(
          "INSERT INTO furnaces (x, y, z, state) VALUES (?, ?, ?, ?)"
          + " ON CONFLICT (x, y, z) DO UPDATE SET state = excluded.state",
          x, y, z, JSON.stringify(state),
        );
      }
    };
    // Smelting ticks are collected here and written together.
    const tickedFurnaces = new Map();
    let tickSaveTimer = null;
    const flushTicks = () => {
      tickSaveTimer = null;
      for (const furnace of tickedFurnaces.values()) saveFurnace(furnace);
      tickedFurnaces.clear();
    };
    // The block simulation (fluids, fire, crops) changes every tick; it is
    // written with the smelting batch, and when the last player leaves.
    this.flushTicks = () => {
      flushTicks();
      const simulation = this.room?.simulationState();
      if (simulation) saveMeta("simulation", simulation);
    };
    const saveMeta = (key, value) => sql.exec(
      "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
      key,
      String(value),
    );
    // The world clock is saved as its time at the last change, plus the wall
    // time it was saved at, so it resumes after the object is evicted.
    const savedTime = Number(meta.get("time") ?? 0);
    const savedAt = Number(meta.get("timeSavedAt") ?? Date.now());
    const resumedTime = savedTime + Math.max(0, Date.now() - savedAt) / 1000;
    this.room = createMultiplayerRoom({
      authority,
      seed: BigInt(seed),
      createServerWorld,
      peaceful: env.PEACEFUL === "1",
      snapshot: {
        version: SNAPSHOT_VERSION, seed, seq: Number(meta.get("seq") ?? 0), edits, chests, furnaces, time: resumedTime,
        simulation: meta.get("simulation") ?? null,
      },
      onChange: ({ seq, edits: accepted, chests: changedChests, furnaces: changedFurnaces, time, tick }) => {
        if (tick) {
          for (const furnace of changedFurnaces) tickedFurnaces.set(furnace.pos.join(), furnace);
          if (tickSaveTimer === null) tickSaveTimer = setTimeout(() => this.flushTicks(), TICK_SAVE_MS);
          return;
        }
        for (const furnace of changedFurnaces) {
          tickedFurnaces.delete(furnace.pos.join());
          saveFurnace(furnace);
        }
        for (const [x, y, z, block] of accepted) {
          sql.exec(
            "INSERT INTO edits (x, y, z, block) VALUES (?, ?, ?, ?)"
            + " ON CONFLICT (x, y, z) DO UPDATE SET block = excluded.block",
            x, y, z, block,
          );
        }
        for (const { pos: [x, y, z], slots } of changedChests) {
          if (slots === null) sql.exec("DELETE FROM chests WHERE x = ? AND y = ? AND z = ?", x, y, z);
          else {
            sql.exec(
              "INSERT INTO chests (x, y, z, slots) VALUES (?, ?, ?, ?)"
              + " ON CONFLICT (x, y, z) DO UPDATE SET slots = excluded.slots",
              x, y, z, JSON.stringify(slots),
            );
          }
        }
        saveMeta("seq", seq);
        saveMeta("time", time ?? this.room.worldTime());
        saveMeta("timeSavedAt", Date.now());
      },
    });
  }

  async fetch(request) {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("Expected a WebSocket upgrade", { status: 426 });
    }
    const { 0: client, 1: server } = new WebSocketPair();
    server.accept();
    // The furnaces tick while anyone is connected.
    this.ticker ??= setInterval(() => {
      this.room.tick();
      this.ticks = (this.ticks ?? 0) + 1;
      if (this.ticks % Math.round(TICK_SAVE_MS / TICK_MS) === 0) this.flushTicks();
    }, TICK_MS);
    const handle = this.room.connect(
      (text) => {
        try {
          server.send(text);
        } catch {
          // The peer is gone; its close event removes it from the room.
        }
      },
      (code, reason) => server.close(code, reason),
    );
    server.addEventListener("message", (event) => {
      const data = typeof event.data === "string" ? event.data : new TextDecoder().decode(event.data);
      if (data.length > MAX_MESSAGE_BYTES) {
        server.close(1009, "Message too big");
        return;
      }
      handle.receive(data);
    });
    const leave = () => {
      handle.disconnect();
      if (this.room.playerCount() === 0 && this.ticker) {
        clearInterval(this.ticker);
        this.ticker = null;
        this.flushTicks();
      }
    };
    server.addEventListener("close", leave);
    server.addEventListener("error", leave);
    return new Response(null, { status: 101, webSocket: client });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === MULTIPLAYER_PATH) {
      // One shared world per deployment.
      const world = env.MULTIPLAYER_WORLD.get(env.MULTIPLAYER_WORLD.idFromName("world"));
      return world.fetch(request);
    }
    return env.ASSETS.fetch(request);
  },
};
