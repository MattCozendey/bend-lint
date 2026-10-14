// Wire protocol shared by the multiplayer client (web/multiplayer.js) and the
// server room (server/multiplayer-room.js). Messages are JSON text frames.
//
// This module only checks shapes, so a malformed message is dropped before it
// reaches Bend. Whether an edit is allowed in the world, and whether a pose is
// inside it, is decided by world/multiplayer.bend.
//
// Edits travel as [x, y, z, block] in stored (Bend) coordinates: the same
// non-negative encoding WorldState keeps (see web/world-coordinates.js).

export const PROTOCOL_VERSION = 5;
export const MULTIPLAYER_PATH = "/multiplayer";
export const MAX_MESSAGE_BYTES = 256 * 1024;
export const MAX_EDITS_PER_MESSAGE = 4096;
export const MAX_PLAYERS = 16;
export const MAX_NAME_LENGTH = 24;
export const POSE_INTERVAL_MS = 100;
export const CHEST_SLOTS = 9;
// World interactions the server simulates (server/server-world.js).
export const INTERACT_OPS = Object.freeze(["water", "lava", "fire", "collect", "till", "plant", "harvest"]);
export const MAX_STACK = 64;

function isStoredInteger(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

export function isWireEdit(value) {
  return Array.isArray(value)
    && value.length === 4
    && isStoredInteger(value[0])
    && isStoredInteger(value[1])
    && isStoredInteger(value[2])
    && Number.isInteger(value[3])
    && value[3] >= 0
    && value[3] <= 0xffffffff;
}

export function isWireEditList(value, limit = MAX_EDITS_PER_MESSAGE) {
  return Array.isArray(value) && value.length <= limit && value.every(isWireEdit);
}

function isU32(value) {
  return Number.isInteger(value) && value >= 0 && value <= 0xffffffff;
}

/** A chest position [x, y, z] in stored coordinates. */
export function isWirePosition(value) {
  return Array.isArray(value) && value.length === 3 && value.every(isStoredInteger);
}

/** A chest slot [item, count, durability]. */
export function isWireSlot(value) {
  return Array.isArray(value) && value.length === 3 && value.every(isU32);
}

/**
 * A furnace state [input, inputCount, fuel, fuelCount, output, outputCount,
 * progress, burn], the fields of world/furnace.bend's Furnace in order.
 */
export function isWireFurnaceState(value) {
  return Array.isArray(value) && value.length === 8 && value.every(isU32);
}

export function isWireFurnace(value) {
  return value !== null
    && typeof value === "object"
    && isWirePosition(value.pos)
    && (value.state === null || isWireFurnaceState(value.state));
}

export function isWireChest(value) {
  return value !== null
    && typeof value === "object"
    && isWirePosition(value.pos)
    && (value.slots === null || (Array.isArray(value.slots) && value.slots.every(isWireSlot)));
}

function isNumber(value) {
  return typeof value === "number";
}

export function isWirePose(value) {
  return value !== null
    && typeof value === "object"
    && isNumber(value.x)
    && isNumber(value.y)
    && isNumber(value.z)
    && isNumber(value.yaw)
    && isNumber(value.pitch);
}

/** A display name: trimmed, control characters removed, bounded length. */
export function sanitizeName(value, fallback = "Player") {
  if (typeof value !== "string") return fallback;
  const cleaned = value.replace(/\s+/g, " ").replace(/[\u0000-\u001f\u007f]/g, "").trim();
  return cleaned.length === 0 ? fallback : [...cleaned].slice(0, MAX_NAME_LENGTH).join("");
}

/**
 * Parses one client -> server message. Returns null for anything that is not
 * a well-formed message of a known type.
 */
export function decodeClientMessage(text) {
  if (typeof text !== "string" || text.length > MAX_MESSAGE_BYTES) return null;
  let message;
  try {
    message = JSON.parse(text);
  } catch {
    return null;
  }
  if (message === null || typeof message !== "object") return null;
  switch (message.t) {
    case "hello":
      if (message.v !== PROTOCOL_VERSION) return { t: "hello", v: message.v, name: sanitizeName(message.name) };
      return { t: "hello", v: PROTOCOL_VERSION, name: sanitizeName(message.name) };
    case "pose":
      return isWirePose(message)
        ? { t: "pose", x: message.x, y: message.y, z: message.z, yaw: message.yaw, pitch: message.pitch }
        : null;
    case "edits":
      return isWireEditList(message.edits) && message.edits.length > 0
        ? { t: "edits", edits: message.edits }
        : null;
    case "chest":
      if (!isU32(message.id) || !isWirePosition(message.pos)) return null;
      if (message.op === "deposit") {
        return isU32(message.item) && isU32(message.count) && isU32(message.durability)
          ? { t: "chest", op: "deposit", id: message.id, pos: message.pos, item: message.item, count: message.count, durability: message.durability }
          : null;
      }
      if (message.op === "withdraw") {
        return Number.isInteger(message.index) && message.index >= 0 && message.index < CHEST_SLOTS
          && Number.isInteger(message.amount) && message.amount > 0 && message.amount <= MAX_STACK
          ? { t: "chest", op: "withdraw", id: message.id, pos: message.pos, index: message.index, amount: message.amount }
          : null;
      }
      return null;
    case "time":
      return message.op === "morning" ? { t: "time", op: "morning" } : null;
    case "attack":
      return isU32(message.id) && isStoredInteger(message.mob) && Number.isFinite(message.damage)
        && message.damage >= 0 && typeof message.ranged === "boolean"
        ? { t: "attack", id: message.id, mob: message.mob, damage: message.damage, ranged: message.ranged }
        : null;
    case "interact":
      return isU32(message.id) && INTERACT_OPS.includes(message.op) && isWirePosition(message.pos)
        ? { t: "interact", id: message.id, op: message.op, pos: message.pos }
        : null;
    case "pickup":
      return isU32(message.id) && isStoredInteger(message.drop) ? { t: "pickup", id: message.id, drop: message.drop } : null;
    case "drop":
      return isU32(message.item) && message.item > 0 && Number.isInteger(message.amount)
        && message.amount > 0 && message.amount <= MAX_STACK
        && [message.x, message.y, message.z].every(Number.isFinite)
        ? { t: "drop", item: message.item, amount: message.amount, x: message.x, y: message.y, z: message.z }
        : null;
    case "furnace":
      if (!isU32(message.id) || !isWirePosition(message.pos)) return null;
      if (message.op !== "input" && message.op !== "fuel" && message.op !== "output") return null;
      if (message.op !== "output" && !isU32(message.item)) return null;
      return { t: "furnace", op: message.op, id: message.id, pos: message.pos, item: message.op === "output" ? 0 : message.item };
    default:
      return null;
  }
}

/** Parses one server -> client message; null when it is not well formed. */
export function decodeServerMessage(text) {
  if (typeof text !== "string") return null;
  let message;
  try {
    message = JSON.parse(text);
  } catch {
    return null;
  }
  if (message === null || typeof message !== "object" || typeof message.t !== "string") return null;
  switch (message.t) {
    case "welcome":
      return Number.isInteger(message.id)
        && typeof message.seed === "string"
        && /^\d+$/.test(message.seed)
        && Number.isInteger(message.seq)
        && isWireEditList(message.edits, Infinity)
        && Array.isArray(message.players)
        && Array.isArray(message.chests) && message.chests.every(isWireChest)
        && Array.isArray(message.furnaces) && message.furnaces.every(isWireFurnace)
        && Number.isFinite(message.time)
        ? message
        : null;
    case "edits":
    case "revert":
      return isWireEditList(message.edits, Infinity) ? message : null;
    case "pose":
      return Number.isInteger(message.id) && isWirePose(message) ? message : null;
    case "joined":
      return Number.isInteger(message.player?.id) && typeof message.player?.name === "string" ? message : null;
    case "left":
      return Number.isInteger(message.id) ? message : null;
    case "error":
      return typeof message.message === "string" ? message : null;
    case "chest":
      return isWireChest(message) ? message : null;
    case "entities":
      return Array.isArray(message.mobs) && message.mobs.every((mob) => Array.isArray(mob) && mob.length === 11 && mob.every(Number.isFinite))
        && Array.isArray(message.drops) && message.drops.every((drop) => Array.isArray(drop) && drop.length === 6 && drop.every(Number.isFinite))
        && (message.villagers === undefined
          || (Array.isArray(message.villagers) && message.villagers.every((v) => Array.isArray(v) && v.length === 8 && v.every(Number.isFinite))))
        ? message
        : null;
    case "hurt":
      return Number.isFinite(message.amount) && message.amount >= 0 ? message : null;
    case "correct":
      return [message.x, message.y, message.z].every(Number.isFinite) ? message : null;
    case "chest-result":
    case "furnace-result":
    case "pickup-result":
    case "interact-result":
      return isU32(message.id) && typeof message.ok === "boolean" ? message : null;
    case "attack-result":
      return isU32(message.id) && typeof message.hit === "boolean" && typeof message.killed === "boolean" ? message : null;
    case "furnace":
      return isWireFurnace(message) ? message : null;
    case "furnaces":
      return Array.isArray(message.furnaces) && message.furnaces.every(isWireFurnace) ? message : null;
    case "time":
      return Number.isFinite(message.time) ? message : null;
    default:
      return null;
  }
}

/** Converts wire edits to a Bend `List<Edit>` of `{ $: "Edit" }` records. */
export function wireEditsToBend(edits) {
  let list = { $: "Nil" };
  for (let index = edits.length - 1; index >= 0; index -= 1) {
    const [x, y, z, block] = edits[index];
    list = { $: "Con", head: { $: "Edit", x: BigInt(x), y: BigInt(y), z: BigInt(z), block }, tail: list };
  }
  return list;
}

/** Converts a Bend `List<Edit>` to wire edits. */
export function bendEditsToWire(list) {
  const edits = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) {
    const edit = node.head;
    edits.push([Number(edit.x), Number(edit.y), Number(edit.z), Number(edit.block)]);
  }
  return edits;
}

/**
 * The WebSocket URL of a multiplayer server. An explicit address may be a full
 * ws:// or wss:// URL, an http(s):// page URL, or a bare host[:port]; with no
 * address the page's own origin hosts the server.
 */
export function multiplayerUrl(address, location) {
  const pageSecure = location?.protocol === "https:";
  const raw = typeof address === "string" ? address.trim() : "";
  if (raw === "") {
    return `${pageSecure ? "wss" : "ws"}://${location.host}${MULTIPLAYER_PATH}`;
  }
  let url;
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(raw)) {
    url = new URL(raw);
  } else {
    url = new URL(`${pageSecure ? "wss" : "ws"}://${raw}`);
  }
  if (url.protocol === "http:") url.protocol = "ws:";
  if (url.protocol === "https:") url.protocol = "wss:";
  if (url.protocol !== "ws:" && url.protocol !== "wss:") throw new Error(`Unsupported server address: ${raw}`);
  if (url.pathname === "/" || url.pathname === "") url.pathname = MULTIPLAYER_PATH;
  url.search = "";
  url.hash = "";
  return url.toString();
}

/** Converts a Bend `List<Chest.Slot>` to wire slots. */
export function bendSlotsToWire(list) {
  const slots = [];
  for (let node = list; node?.$ === "Con"; node = node.tail) {
    slots.push([Number(node.head.item), Number(node.head.count), Number(node.head.durability)]);
  }
  return slots;
}

/** Converts wire slots to a Bend `List<Chest.Slot>`. */
export function wireSlotsToBend(slots) {
  let list = { $: "Nil" };
  for (let index = slots.length - 1; index >= 0; index -= 1) {
    const [item, count, durability] = slots[index];
    list = { $: "Con", head: { $: "Slot", item, count, durability }, tail: list };
  }
  return list;
}

/** Converts a Bend `Chests.World` to wire chests [{ pos, slots }]. */
export function bendChestsToWire(world) {
  const chests = [];
  for (let node = world?.entries; node?.$ === "Con"; node = node.tail) {
    const entry = node.head;
    chests.push({ pos: [Number(entry.x), Number(entry.y), Number(entry.z)], slots: bendSlotsToWire(entry.slots) });
  }
  return chests;
}

/** Converts wire chests to a Bend `Chests.World`. */
export function wireChestsToBend(chests) {
  let entries = { $: "Nil" };
  for (let index = chests.length - 1; index >= 0; index -= 1) {
    const { pos: [x, y, z], slots } = chests[index];
    entries = {
      $: "Con",
      head: { $: "Entry", x: BigInt(x), y: BigInt(y), z: BigInt(z), slots: wireSlotsToBend(slots) },
      tail: entries,
    };
  }
  return { $: "World", entries };
}

const FURNACE_FIELDS = ["input", "input_count", "fuel", "fuel_count", "output", "output_count", "progress", "burn"];

/** Converts a Bend `Furnace` to a wire furnace state. */
export function bendFurnaceToWire(furnace) {
  return FURNACE_FIELDS.map((field) => Number(furnace[field]));
}

/** Converts a wire furnace state to a Bend `Furnace`. */
export function wireFurnaceToBend(state) {
  return Object.fromEntries([["$", "Furnace"], ...FURNACE_FIELDS.map((field, index) => [field, state[index]])]);
}

/** Converts a Bend `Furnaces.World` to wire furnaces [{ pos, state }]. */
export function bendFurnacesToWire(world) {
  const furnaces = [];
  for (let node = world?.entries; node?.$ === "Con"; node = node.tail) {
    const entry = node.head;
    furnaces.push({ pos: [Number(entry.x), Number(entry.y), Number(entry.z)], state: bendFurnaceToWire(entry.furnace) });
  }
  return furnaces;
}

/** Converts wire furnaces to a Bend `Furnaces.World`. */
export function wireFurnacesToBend(furnaces) {
  let entries = { $: "Nil" };
  for (let index = furnaces.length - 1; index >= 0; index -= 1) {
    const { pos: [x, y, z], state } = furnaces[index];
    entries = {
      $: "Con",
      head: { $: "Entry", x: BigInt(x), y: BigInt(y), z: BigInt(z), furnace: wireFurnaceToBend(state) },
      tail: entries,
    };
  }
  return { $: "World", entries };
}
