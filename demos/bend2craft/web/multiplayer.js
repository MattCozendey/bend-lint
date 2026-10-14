// Browser side of multiplayer: the connection to the server and the remote
// players' presence. This module does not decide anything about the world:
// the server's Bend room (world/multiplayer.bend) orders and validates every
// edit, and game.js replays the batches the server sends back.
import {
  MAX_EDITS_PER_MESSAGE,
  POSE_INTERVAL_MS,
  PROTOCOL_VERSION,
  decodeServerMessage,
} from "./multiplayer-protocol.js";

const CONNECT_TIMEOUT_MS = 10_000;
const REQUEST_TIMEOUT_MS = 8_000;
// Remote poses arrive about every POSE_INTERVAL_MS; rendering them this far in
// the past keeps two snapshots to blend between, so movement stays smooth.
export const INTERPOLATION_DELAY_MS = POSE_INTERVAL_MS * 1.5;

function lerp(a, b, t) {
  return a + (b - a) * t;
}

/** Blends two angles along the shorter arc. */
export function lerpAngle(a, b, t) {
  let delta = (b - a) % (Math.PI * 2);
  if (delta > Math.PI) delta -= Math.PI * 2;
  if (delta < -Math.PI) delta += Math.PI * 2;
  return a + delta * t;
}

/**
 * Remote player presence: names, and pose snapshots blended for rendering.
 * `now` is a millisecond clock (performance.now()).
 */
export function createRemotePlayers({ delayMs = INTERPOLATION_DELAY_MS } = {}) {
  const players = new Map();

  function upsert(id, name) {
    let player = players.get(id);
    if (player === undefined) {
      player = { id, name, samples: [] };
      players.set(id, player);
    } else if (typeof name === "string") {
      player.name = name;
    }
    return player;
  }

  function pose(id, value, now) {
    const player = players.get(id);
    if (player === undefined) return false;
    const sample = { t: now, x: value.x, y: value.y, z: value.z, yaw: value.yaw, pitch: value.pitch };
    player.samples.push(sample);
    // Two snapshots older than the render time are enough to blend from.
    while (player.samples.length > 2 && player.samples[1].t <= now - delayMs * 2) player.samples.shift();
    if (player.samples.length > 8) player.samples.splice(0, player.samples.length - 8);
    return true;
  }

  function view(player, now) {
    const { samples } = player;
    if (samples.length === 0) return null;
    const renderTime = now - delayMs;
    let from = samples[0];
    let to = samples[samples.length - 1];
    for (let index = 0; index < samples.length - 1; index += 1) {
      if (samples[index].t <= renderTime && samples[index + 1].t >= renderTime) {
        from = samples[index];
        to = samples[index + 1];
        break;
      }
    }
    if (renderTime <= samples[0].t) to = from;
    const span = to.t - from.t;
    const t = span > 0 ? Math.min(1, Math.max(0, (renderTime - from.t) / span)) : 1;
    const speed = span > 0 ? Math.hypot(to.x - from.x, to.z - from.z) / (span / 1000) : 0;
    return {
      id: player.id,
      name: player.name,
      x: lerp(from.x, to.x, t),
      y: lerp(from.y, to.y, t),
      z: lerp(from.z, to.z, t),
      yaw: lerpAngle(from.yaw, to.yaw, t),
      pitch: lerp(from.pitch, to.pitch, t),
      speed: Math.min(speed, 12),
    };
  }

  return {
    join(player, now = 0) {
      upsert(player.id, player.name);
      if (player.pose) pose(player.id, player.pose, now);
    },
    leave(id) {
      return players.delete(id);
    },
    pose,
    name: (id) => players.get(id)?.name ?? null,
    count: () => players.size,
    views(now) {
      const views = [];
      for (const player of players.values()) {
        const current = view(player, now);
        if (current !== null) views.push(current);
      }
      return views;
    },
  };
}

/**
 * Opens a session: connects, says hello and resolves with the server's welcome
 * (seed, sequence, edit log, players). Later messages go to `session.on(type)`
 * listeners once `session.start()` is called; until then they are held in
 * arrival order. `WebSocketImpl` is injectable for tests.
 */
export function connectMultiplayer({
  url,
  name,
  WebSocketImpl = globalThis.WebSocket,
  timeoutMs = CONNECT_TIMEOUT_MS,
  clock = () => performance.now(),
}) {
  return new Promise((resolve, reject) => {
    let socket;
    try {
      socket = new WebSocketImpl(url);
    } catch (error) {
      reject(new Error(`Could not open ${url}: ${error.message}`));
      return;
    }
    const listeners = new Map();
    let session = null;
    let settled = false;
    let pendingEdits = [];
    let flushQueued = false;
    let lastPoseAt = -Infinity;
    let lastPoseKey = "";
    let nextRequestId = 1;
    const pendingRequests = new Map();
    // The server's world clock: its time at `timeAt` on our clock.
    let timeBase = 0;
    let timeAt = 0;
    const stats = { sentEdits: 0, sentPoses: 0, received: 0, ignored: 0 };

    function settleRequests(error) {
      for (const [id, request] of pendingRequests) {
        clearTimeout(request.timer);
        request.reject(error);
        pendingRequests.delete(id);
      }
    }

    const timer = setTimeout(() => fail(new Error(`The server at ${url} did not answer.`)), timeoutMs);

    function fail(error) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try {
        socket.close();
      } catch {
        // Already closed.
      }
      reject(error);
    }

    // Messages that arrive between the welcome and `start()` wait here, so
    // the game can build its world from the welcome without missing a batch.
    let started = false;
    const backlog = [];

    function emit(type, payload) {
      if (!started) {
        backlog.push([type, payload]);
        return;
      }
      for (const listener of listeners.get(type) ?? []) listener(payload);
    }

    function send(message) {
      if (socket.readyState !== 1) return false;
      socket.send(JSON.stringify(message));
      return true;
    }

    // One request/answer exchange (chest and furnace operations), matched by id.
    function request(type, op, fields) {
      const id = nextRequestId;
      nextRequestId += 1;
      return new Promise((resolve, reject) => {
        const message = op === undefined ? { t: type, id, ...fields } : { t: type, op, id, ...fields };
        if (!send(message)) {
          resolve({ ok: false, hit: false, item: 0, amount: 0, durability: 0, offline: true });
          return;
        }
        const timer = setTimeout(() => {
          pendingRequests.delete(id);
          reject(new Error(`The server did not answer the ${type} request.`));
        }, REQUEST_TIMEOUT_MS);
        pendingRequests.set(id, { resolve, reject, timer });
      });
    }

    function flush() {
      flushQueued = false;
      while (pendingEdits.length > 0) {
        const batch = pendingEdits.slice(0, MAX_EDITS_PER_MESSAGE);
        pendingEdits = pendingEdits.slice(batch.length);
        if (send({ t: "edits", edits: batch })) stats.sentEdits += batch.length;
      }
    }

    socket.addEventListener("open", () => {
      send({ t: "hello", v: PROTOCOL_VERSION, name });
    });
    socket.addEventListener("message", (event) => {
      const message = decodeServerMessage(typeof event.data === "string" ? event.data : "");
      if (message === null) {
        stats.ignored += 1;
        return;
      }
      stats.received += 1;
      if (!settled) {
        if (message.t === "error") {
          fail(new Error(message.message));
          return;
        }
        if (message.t !== "welcome") return;
        settled = true;
        clearTimeout(timer);
        timeBase = message.time;
        timeAt = clock();
        session = {
          id: message.id,
          seed: message.seed,
          seq: message.seq,
          edits: message.edits,
          chests: message.chests,
          furnaces: message.furnaces,
          players: message.players,
          url,
          stats,
          get connected() {
            return socket.readyState === 1;
          },
          on(type, listener) {
            if (!listeners.has(type)) listeners.set(type, []);
            listeners.get(type).push(listener);
          },
          /** Queues one edit [x, y, z, block] in stored coordinates. */
          queueEdit(edit) {
            if (socket.readyState !== 1) return false;
            pendingEdits.push(edit);
            if (!flushQueued) {
              flushQueued = true;
              queueMicrotask(flush);
            }
            return true;
          },
          flush,
          /** Delivers the messages held since the welcome, then every later one. */
          start() {
            if (started) return;
            started = true;
            for (const [type, payload] of backlog.splice(0)) emit(type, payload);
          },
          /** Sends the local pose at most every POSE_INTERVAL_MS, and only when it moved. */
          sendPose(pose, now = clock()) {
            if (now - lastPoseAt < POSE_INTERVAL_MS) return false;
            const key = [pose.x, pose.y, pose.z, pose.yaw, pose.pitch].map((v) => v.toFixed(2)).join(",");
            if (key === lastPoseKey && now - lastPoseAt < 2000) return false;
            if (!send({ t: "pose", x: pose.x, y: pose.y, z: pose.z, yaw: pose.yaw, pitch: pose.pitch })) return false;
            lastPoseAt = now;
            lastPoseKey = key;
            stats.sentPoses += 1;
            return true;
          },
          /**
           * Asks the server to change a chest; resolves with its answer
           * `{ ok, item, amount, durability }` (ok false when refused or offline).
           */
          chestRequest(op, fields) {
            return request("chest", op, fields);
          },
          /**
           * Asks the server to load ("input", "fuel") or empty ("output") a
           * furnace; resolves with `{ ok, item, amount }`.
           */
          furnaceRequest(op, fields) {
            return request("furnace", op, fields);
          },
          /** Hits a mob; resolves with `{ hit, killed, kind }`. */
          attackRequest(fields) {
            return request("attack", undefined, fields);
          },
          /**
           * A world interaction the server simulates ("water", "lava", "fire",
           * "collect", "till", "plant", "harvest") at a stored position;
           * resolves with `{ ok, ... }` (collect: `block`; harvest: `seeds`, `wheat`).
           */
          interactRequest(op, pos) {
            return request("interact", op, { pos });
          },
          /** Picks up a drop; resolves with `{ ok, item, amount }`. */
          pickupRequest(fields) {
            return request("pickup", undefined, fields);
          },
          /** Puts an item the player threw or spilled into the world. */
          sendDrop(fields) {
            return send({ t: "drop", ...fields });
          },
          /** Starts a new day for everyone (after a successful sleep). */
          sendMorning() {
            return send({ t: "time", op: "morning" });
          },
          /** The shared world time in seconds. */
          worldTime(now = clock()) {
            return timeBase + Math.max(0, now - timeAt) / 1000;
          },
          close() {
            socket.close(1000, "Leaving");
          },
        };
        resolve(session);
        return;
      }
      if (message.t === "edits") session.seq = message.seq;
      if (message.t === "time") {
        timeBase = message.time;
        timeAt = clock();
      }
      if (message.t.endsWith("-result")) {
        const request = pendingRequests.get(message.id);
        if (request !== undefined) {
          pendingRequests.delete(message.id);
          clearTimeout(request.timer);
          request.resolve(message);
        }
        return;
      }
      emit(message.t, message);
    });
    socket.addEventListener("close", (event) => {
      if (!settled) {
        fail(new Error(`The server at ${url} closed the connection${event?.reason ? `: ${event.reason}` : "."}`));
        return;
      }
      settleRequests(new Error("Disconnected from the server."));
      emit("disconnect", { code: event?.code ?? 1006, reason: event?.reason ?? "" });
    });
    socket.addEventListener("error", () => {
      if (!settled) fail(new Error(`Could not reach the multiplayer server at ${url}.`));
    });
  });
}

/**
 * The server's mobs and drops, as the views the game renders. Snapshots arrive
 * every simulation tick; mob positions are blended from the previous snapshot
 * to the latest over one tick, so bodies glide instead of stepping.
 */
export function createEntityMirror({ tickMs = 200 } = {}) {
  let previous = new Map();
  let latest = [];
  let latestAt = 0;
  let drops = [];

  function mobView(wire) {
    const [id, kind, x, y, z, headingX, headingZ, health, alive, burning] = wire;
    return { id, kind, x, y, z, headingX, headingZ, health, alive: alive === 1, burning: burning === 1 };
  }

  return {
    push(message, now) {
      previous = new Map(latest.map((mob) => [mob.id, mob]));
      latest = message.mobs.map(mobView);
      latestAt = now;
      drops = message.drops.map(([id, item, x, y, z, amount]) => ({ id, item, x, y, z, amount, velocityY: 0, settled: true }));
    },
    mobs(now) {
      const t = Math.min(1, Math.max(0, (now - latestAt) / tickMs));
      return latest.map((mob) => {
        const from = previous.get(mob.id);
        if (from === undefined || t >= 1) return mob;
        return { ...mob, x: from.x + (mob.x - from.x) * t, y: from.y + (mob.y - from.y) * t, z: from.z + (mob.z - from.z) * t };
      });
    },
    drops: () => drops,
  };
}
