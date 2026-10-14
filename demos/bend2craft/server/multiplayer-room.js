// One multiplayer world: the connected players and the Bend room that owns
// the shared state. The room is transport-agnostic: the Node LAN server
// (server/node-host.mjs), the Bun dev server and the Cloudflare Durable Object
// (cloudflare/worker.js) each hand it a `send(text)` per connection and feed
// it the text frames they receive, and call `tick()` every TICK_MS.
//
// Authority lives in Bend (world/multiplayer.bend): this module decodes
// messages and routes them to the parts of the room, which call Bend with
// whole batches and fan the results out.
//
//   room/edits.js       edit batches (players' and the simulation's)
//   room/containers.js  chests and furnaces
//   room/world.js       mobs, drops, villagers, fluids, fire and farming
//   room/snapshot.js    what a world saves and how it comes back
import { MAX_PLAYERS, PROTOCOL_VERSION, bendEditsToWire, decodeClientMessage, sanitizeName } from "../web/multiplayer-protocol.js";
import { createContainers } from "./room/containers.js";
import { createEdits } from "./room/edits.js";
import { SNAPSHOT_VERSION, restoreRoom, roomSnapshot, validSnapshot } from "./room/snapshot.js";
import { createWorldHandlers } from "./room/world.js";

export { SNAPSHOT_VERSION };
export const TICK_MS = 200;

/**
 * @param {object} options
 * @param {object} options.authority   the compiled world/multiplayer.bend module
 * @param {bigint} options.seed        the world seed
 * @param {object} [options.snapshot]  a snapshot from `room.snapshot()` to resume
 * @param {(change: {
 *   seq: number, edits: number[][], chests: { pos: number[], slots: number[][] | null }[],
 *   furnaces: { pos: number[], state: number[] | null }[], time?: number, tick?: boolean
 * }) => void} [options.onChange]
 *   called after the room changed: accepted edits, chests and furnaces that
 *   changed (null: removed), the new world time when the clock was reset, and
 *   `tick: true` when only furnace smelting moved
 * @param {(event: "joined" | "left", player: object) => void} [options.onPresence]
 * @param {() => number} [options.now]  millisecond wall clock
 * @param {Function} [options.createServerWorld]  server/server-world.js's factory
 *   (bundled with the authority); without it the room simulates nothing
 * @param {boolean} [options.peaceful]  a world without monsters
 */
export function createMultiplayerRoom({
  authority, seed, snapshot = null, onChange = () => {}, onPresence = () => {}, now = () => Date.now(),
  createServerWorld = null, peaceful = false,
}) {
  if (typeof seed !== "bigint") throw new TypeError("seed must be a bigint");
  if (snapshot !== null && !validSnapshot(snapshot, seed)) {
    throw new Error("The multiplayer world snapshot is not valid for this seed.");
  }
  const players = new Map();
  let nextId = 1;
  // The clock runs while the server runs and resumes where it stopped.
  let clockOrigin = now() - (snapshot?.time ?? 0) * 1000;
  const worldTime = () => Math.max(0, (now() - clockOrigin) / 1000);

  // The context every part of the room shares.
  const ctx = {
    authority,
    seed,
    state: snapshot === null ? authority.empty() : restoreRoom(authority, snapshot),
    world: null,
    counters: { accepted: 0, rejected: 0, dropped: 0, corrected: 0 },
    send(player, message) {
      player.send(JSON.stringify(message));
    },
    broadcast(message, except = null) {
      const text = JSON.stringify(message);
      for (const player of players.values()) {
        if (player !== except && player.ready) player.send(text);
      }
    },
    changed(change) {
      onChange({ seq: Number(authority.room_seq(ctx.state)), edits: [], chests: [], furnaces: [], ...change });
    },
  };
  if (createServerWorld !== null) {
    ctx.world = createServerWorld({
      seed,
      edits: () => authority.room_edits(ctx.state),
      peaceful,
      saved: snapshot?.simulation ?? null,
    });
  }
  const containers = createContainers(ctx);
  const edits = createEdits(ctx, containers);
  const worldHandlers = createWorldHandlers(ctx, edits);

  function publicPlayer(player) {
    return { id: player.id, name: player.name, pose: player.pose };
  }

  function welcome(player) {
    ctx.send(player, {
      t: "welcome",
      v: PROTOCOL_VERSION,
      id: player.id,
      seed: seed.toString(),
      seq: Number(authority.room_seq(ctx.state)),
      edits: bendEditsToWire(authority.room_edits(ctx.state)),
      ...containers.welcome(),
      time: worldTime(),
      players: [...players.values()].filter((other) => other !== player && other.ready).map(publicPlayer),
    });
  }

  function pose(player, message) {
    if (!authority.valid_pose(message.x, message.y, message.z, message.yaw, message.pitch)) {
      ctx.counters.dropped += 1;
      return;
    }
    // A move the Bend movement contract refuses is not relayed; the player is
    // sent back to its last accepted pose.
    if (ctx.world !== null && !ctx.world.checkMove(player.id, player.pose, message, now())) {
      ctx.counters.corrected += 1;
      const { x, y, z } = player.pose;
      ctx.send(player, { t: "correct", x, y, z });
      return;
    }
    player.pose = {
      x: message.x,
      y: message.y,
      z: message.z,
      yaw: message.yaw,
      pitch: authority.clamp_pitch(message.pitch),
    };
    ctx.broadcast({ t: "pose", id: player.id, ...player.pose }, player);
  }

  function time(_player, message) {
    if (message.op !== "morning") return;
    clockOrigin = now();
    ctx.broadcast({ t: "time", time: 0 });
    ctx.changed({ time: 0 });
  }

  const handlers = {
    pose,
    time,
    ...edits.handlers,
    ...containers.handlers,
    ...worldHandlers.handlers,
  };

  /**
   * Registers a connection. `send` delivers one text frame and `close` ends
   * the connection; the returned handle receives this connection's frames.
   */
  function connect(send, close = () => {}) {
    const player = { id: 0, name: "", pose: null, ready: false, send, close };
    let closed = false;

    function refuse(message) {
      send(JSON.stringify({ t: "error", message }));
      closed = true;
      close(1008, message);
    }

    function hello(message) {
      if (message.t !== "hello") return;
      if (message.v !== PROTOCOL_VERSION) {
        refuse(`This server speaks multiplayer protocol ${PROTOCOL_VERSION}; update the game.`);
        return;
      }
      if (players.size >= MAX_PLAYERS) {
        refuse(`The server is full (${MAX_PLAYERS} players).`);
        return;
      }
      player.id = nextId;
      nextId += 1;
      player.name = sanitizeName(message.name, `Player ${player.id}`);
      players.set(player.id, player);
      welcome(player);
      player.ready = true;
      ctx.broadcast({ t: "joined", player: publicPlayer(player) }, player);
      onPresence("joined", publicPlayer(player));
    }

    function receive(text) {
      if (closed) return;
      const message = decodeClientMessage(typeof text === "string" ? text : String(text));
      if (message === null) {
        ctx.counters.dropped += 1;
        return;
      }
      if (!player.ready) {
        hello(message);
        return;
      }
      handlers[message.t]?.(player, message);
    }

    function disconnect() {
      if (closed && !players.has(player.id)) return;
      closed = true;
      if (players.get(player.id) === player) {
        players.delete(player.id);
        ctx.world?.forgetPlayer(player.id);
        ctx.broadcast({ t: "left", id: player.id });
        onPresence("left", publicPlayer(player));
      }
    }

    return { receive, disconnect, get id() { return player.id; } };
  }

  /** One simulation step: the world (while anyone is online) and furnaces. */
  function tick() {
    const online = [...players.values()].filter((player) => player.ready && player.pose !== null);
    worldHandlers.tick(TICK_MS / 1000, worldTime(), online);
    return containers.tick();
  }

  return {
    connect,
    tick,
    snapshot: () => roomSnapshot(authority, seed, ctx.state, worldTime(), ctx.world?.persistentState(true) ?? null),
    /** The simulation state when it changed since the last call (for incremental saves). */
    simulationState: () => ctx.world?.persistentState() ?? null,
    playerCount: () => players.size,
    worldTime,
    players: () => [...players.values()].map(publicPlayer),
    counters: () => ({ ...ctx.counters }),
    world: () => ctx.world,
  };
}
