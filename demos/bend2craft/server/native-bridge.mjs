// The native client's door into a multiplayer room.
//
// A browser joins a room over a WebSocket and speaks JSON. The native client is a Bend 2
// program whose sockets carry text and which has no JSON, no SHA-1 and no HTTP, so it joins
// through this instead: a plain TCP port that speaks one short ASCII line per message and
// hands what the lines say to the same room, as the same messages a browser sends. The room
// cannot tell the two kinds of player apart, and nothing about the world is decided here:
// an edit from a native client goes through `world/multiplayer.bend` like any other.
//
// The lines (native/net.bend is the other end, and documents them too):
//
//   client to server    H <version> <name>                  join the room
//                       E <x> <y> <z> <block>               this cell is now this block
//                       P <x> <y> <z> <yaw> <pitch>         this is where I am
//                       A <mob> <damage>                    I hit that mob, this hard
//                       K <drop>                            I pick that item up
//                       CD <x> <y> <z> <item> <count> <wear>  put this in that chest
//                       CW <x> <y> <z> <slot> <amount>        take this many from that slot of it
//                       FI <x> <y> <z> <item>               put one of this in that furnace to smelt
//                       FF <x> <y> <z> <item>               put one of this in it to burn
//                       FO <x> <y> <z>                      take what it made
//   server to client    W <id> <seed>                       joined: the player's id, the world's seed
//                       B <x> <y> <z> <block>               this cell is this block
//                       P <id> <x> <y> <z> <yaw> <pitch>    this is where that player is
//                       J <id> <name>                       that player is in the room, by that name
//                       L <id>                              that player left
//                       C <x> <y> <z>                       that move was refused: stand here
//                       T <turn> <day>                      the hour: how far round the day, and a day's length
//                       M <id> <kind> <x> <y> <z> <yaw>     a mob of that kind stands there, facing that way
//                       D <id> <item> <amount> <x> <y> <z>  that many of that item lie there
//                       V <profession> <x> <y> <z>          a villager of that profession stands there
//                       N                                   and those are all of them
//                       U <amount>                          you were hurt by that much
//                       G <item> <amount>                   the item you asked for is yours
//                       S <x> <y> <z> <slots>               that chest holds this; none: it is gone
//                       O <x> <y> <z> <eight numbers>       that furnace is this; none: it is gone
//                       R <ok> <item> <amount> <wear>       the answer to a chest or furnace request
//                       X <reason>                          refused; the connection ends
//
// A cell's coordinates are the room's stored ones, as on the browser's wire. Everything the
// room says about a cell — its log on joining, an accepted batch, a revert — is a `B`,
// because the client does the same thing with each: it sets the cell.
//
// A pose is world coordinates, feet first, and radians, as on the browser's wire, written as
// whole thousandths with a sign: the pinned Bend reads and writes no decimal. A `P` is every
// way the room says where a player is: the players already there on joining, and each move.
//
// The hour is the room's clock as the angle of its day, in thousandths of a radian from the
// morning it starts on, and how long a day lasts in milliseconds. The client is told on
// joining and whenever someone calls the morning, and runs the day on from there itself.
//
// The room says what it simulates five times a second, whole: every living mob, every item
// on the ground and every villager. Each is a line, and `N` ends the list, so a client
// swaps the old list for the new one when it has all of it and never draws half. A mob's
// heading is sent as the yaw it comes to; its health and whether it burns are not.
//
// A hit and a pickup are the room's `attack` and `pickup` requests, which a browser numbers
// to match the answer; the bridge numbers them for the client. The room judges both from the
// pose it holds for the player (`world/multiplayer_mobs.bend`). A hit's answer is the next
// list, so it is not sent; a pickup's is the item, and only when the room gave it. Damage
// is thousandths, like a pose.
// A `J` is every way the room names a player: the ones already there on joining, before
// where each stands, and each one who joins after. The name is the room's own, already
// cleaned to one line, and is the rest of the line.
//
// A chest and a furnace are the room's `chest` and `furnace` requests and its `chest`,
// `furnace` and `furnaces` messages: what each holds on joining and whenever one changes,
// as its cell and its numbers, and nothing after the cell when it is gone. The answer to a
// request is an `R`, one for one and in order, since a client waits for each before it asks
// again.
import * as net from "node:net";
import { DAY_RATE, dayTurn } from "../web/daylight.js";
import { MAX_EDITS_PER_MESSAGE, PROTOCOL_VERSION } from "../web/multiplayer-protocol.js";

export const NATIVE_PROTOCOL = 1;
// The longest line a client may send: a hello with the longest name the room keeps.
export const MAX_NATIVE_LINE = 256;

const blockLines = (edits) => edits.map(([x, y, z, block]) => `B ${x} ${y} ${z} ${block}\n`).join("");

// A number as whole thousandths. A value that rounds to nothing is "0", never "-0".
const milli = (value) => String(Math.round(value * 1000) + 0);

const poseLine = (id, { x, y, z, yaw, pitch }) =>
  `P ${id} ${milli(x)} ${milli(y)} ${milli(z)} ${milli(yaw)} ${milli(pitch)}\n`;

// A whole turn is a hair over 6283 thousandths, so no angle of a day rounds past that.
const DAY_MS = Math.round((2 * Math.PI * 1000) / DAY_RATE);
const hourLine = (time) => `T ${Math.min(Math.round(dayTurn(time) * 1000), 6283)} ${DAY_MS}\n`;

const whole = (value) => Math.max(0, Math.trunc(value));

const chestLine = ({ pos, slots }) => `S ${pos.join(" ")}${slots === null ? "" : ` ${slots.flat().join(" ")}`}\n`;
const furnaceLine = ({ pos, state }) => `O ${pos.join(" ")}${state === null ? "" : ` ${state.join(" ")}`}\n`;

/** The room's mobs, drops and villagers as the lines of one list. */
function sightLines({ mobs = [], drops = [], villagers = [] }) {
  const lines = [];
  for (const [id, kind, x, y, z, headingX, headingZ, , alive] of mobs) {
    if (alive === 1) lines.push(`M ${whole(id)} ${whole(kind)} ${milli(x)} ${milli(y)} ${milli(z)} ${milli(Math.atan2(headingX, -headingZ))}`);
  }
  for (const [id, item, x, y, z, amount] of drops) lines.push(`D ${whole(id)} ${whole(item)} ${whole(amount)} ${milli(x)} ${milli(y)} ${milli(z)}`);
  for (const [, profession, x, y, z] of villagers) lines.push(`V ${whole(profession)} ${milli(x)} ${milli(y)} ${milli(z)}`);
  lines.push("N");
  return `${lines.join("\n")}\n`;
}

// A player is its name, and where it stands once it has said: one who has only joined has
// no pose and no pose line.
const playerLine = (player) => (player
  ? `J ${player.id} ${player.name}\n${player.pose ? poseLine(player.id, player.pose) : ""}`
  : "");

/** One of the room's messages as the lines a native client reads; "" when it reads none. */
export function nativeLines(message) {
  switch (message?.t) {
    case "welcome":
      return `W ${message.id} ${message.seed}\n${blockLines(message.edits)}${hourLine(message.time ?? 0)}${(message.chests ?? []).map(chestLine).join("")}${(message.furnaces ?? []).map(furnaceLine).join("")}${(message.players ?? []).map(playerLine).join("")}`;
    case "edits":
    case "revert":
      return blockLines(message.edits);
    case "pose":
      return poseLine(message.id, message);
    case "joined":
      return playerLine(message.player);
    case "left":
      return `L ${message.id}\n`;
    case "time":
      return hourLine(message.time);
    case "entities":
      return sightLines(message);
    case "chest":
      return chestLine(message);
    case "furnace":
      return furnaceLine(message);
    case "furnaces":
      return message.furnaces.map(furnaceLine).join("");
    case "chest-result":
      return `R ${message.ok ? 1 : 0} ${whole(message.item)} ${whole(message.amount)} ${whole(message.durability)}\n`;
    case "furnace-result":
      return `R ${message.ok ? 1 : 0} ${whole(message.item)} ${whole(message.amount)} 0\n`;
    case "hurt":
      return `U ${milli(message.amount)}\n`;
    case "pickup-result":
      return message.ok ? `G ${whole(message.item)} ${whole(message.amount)}\n` : "";
    case "correct":
      return `C ${milli(message.x)} ${milli(message.y)} ${milli(message.z)}\n`;
    case "error":
      return `X ${String(message.message).replace(/\s+/g, " ").trim()}\n`;
    default:
      return "";
  }
}

// How many whole numbers follow each chest or furnace request's tag.
const STORE_FIELDS = Object.freeze({ CD: 6, CW: 5, FI: 4, FF: 4, FO: 3 });

const NUMBER = /^(0|[1-9]\d*)$/;
const SIGNED = /^-?(0|[1-9]\d*)$/;

/** `fields` as that many whole numbers, or null when they are not. */
function wholes(fields, count) {
  if (fields.length !== count || !fields.every((field) => NUMBER.test(field))) return null;
  const numbers = fields.map(Number);
  return numbers.every(Number.isSafeInteger) ? numbers : null;
}

/** `P x y z yaw pitch` as a pose message, or null when the line is not one. */
function poseOf(fields) {
  if (fields.length !== 5 || !fields.every((field) => SIGNED.test(field))) return null;
  const [x, y, z, yaw, pitch] = fields.map((field) => Number(field) / 1000);
  return { t: "pose", x, y, z, yaw, pitch };
}

/** `E x y z block` as a wire edit, or null when the line is not one. */
function editOf(fields) {
  if (fields.length !== 4 || !fields.every((field) => NUMBER.test(field))) return null;
  const edit = fields.map(Number);
  return edit.every(Number.isSafeInteger) && edit[3] <= 0xffffffff ? edit : null;
}

/**
 * Registers one native connection with the room. `write` sends text to the client and `end`
 * closes the connection; the returned handle is fed the bytes that arrive, as text, in
 * whatever pieces TCP delivers them.
 */
export function connectNative(room, write, end) {
  let buffer = "";
  let handle = null;
  let closed = false;
  // A browser numbers its requests to match the answers; the bridge numbers the client's.
  let request = 0;

  /** `A mob damage` and `K drop` as the room's requests. */
  function ask(fields) {
    const hit = fields[0] === "A" ? wholes(fields.slice(1), 2) : null;
    if (hit !== null) {
      request += 1;
      handle.receive(JSON.stringify({ t: "attack", id: request, mob: hit[0], damage: hit[1] / 1000, ranged: false }));
    }
    const taken = fields[0] === "K" ? wholes(fields.slice(1), 1) : null;
    if (taken !== null) {
      request += 1;
      handle.receive(JSON.stringify({ t: "pickup", id: request, drop: taken[0] }));
    }
    const stored = STORE_FIELDS[fields[0]];
    const numbers = stored === undefined ? null : wholes(fields.slice(1), stored);
    if (numbers !== null) {
      request += 1;
      const pos = numbers.slice(0, 3);
      const rest = numbers.slice(3);
      const message = {
        CD: () => ({ t: "chest", op: "deposit", id: request, pos, item: rest[0], count: rest[1], durability: rest[2] }),
        CW: () => ({ t: "chest", op: "withdraw", id: request, pos, index: rest[0], amount: rest[1] }),
        FI: () => ({ t: "furnace", op: "input", id: request, pos, item: rest[0] }),
        FF: () => ({ t: "furnace", op: "fuel", id: request, pos, item: rest[0] }),
        FO: () => ({ t: "furnace", op: "output", id: request, pos, item: 0 }),
      }[fields[0]]();
      handle.receive(JSON.stringify(message));
    }
  }

  function refuse(reason) {
    write(`X ${reason}\n`);
    close();
  }

  function close() {
    if (closed) return;
    closed = true;
    handle?.disconnect();
    end();
  }

  function hello(fields) {
    if (fields[0] !== "H" || fields.length < 3) {
      refuse(`Say hello first: H ${NATIVE_PROTOCOL} <name>.`);
      return;
    }
    if (fields[1] !== String(NATIVE_PROTOCOL)) {
      refuse(`This server speaks native protocol ${NATIVE_PROTOCOL}; update the game.`);
      return;
    }
    handle = room.connect(
      (text) => {
        const lines = nativeLines(JSON.parse(text));
        if (lines !== "" && !closed) write(lines);
      },
      // The room refused the player (it is full, say): its reason is already on the wire.
      () => close(),
    );
    handle.receive(JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, name: fields.slice(2).join(" ") }));
  }

  function lines(whole) {
    const edits = [];
    for (const line of whole) {
      if (closed) return;
      const fields = line.split(" ");
      if (handle === null) {
        hello(fields);
        continue;
      }
      const edit = fields[0] === "E" ? editOf(fields.slice(1)) : null;
      if (edit !== null) edits.push(edit);
      const pose = fields[0] === "P" ? poseOf(fields.slice(1)) : null;
      if (pose !== null) handle.receive(JSON.stringify(pose));
      ask(fields);
    }
    // The whole lines of one chunk are one batch, as a browser sends one tick's edits.
    for (let start = 0; start < edits.length && !closed; start += MAX_EDITS_PER_MESSAGE) {
      handle.receive(JSON.stringify({ t: "edits", edits: edits.slice(start, start + MAX_EDITS_PER_MESSAGE) }));
    }
  }

  function receive(chunk) {
    if (closed) return;
    buffer += chunk;
    const pieces = buffer.split("\n");
    buffer = pieces.pop();
    if (buffer.length > MAX_NATIVE_LINE || pieces.some((line) => line.length > MAX_NATIVE_LINE)) {
      refuse("That line is too long.");
      return;
    }
    lines(pieces.map((line) => line.replace(/\r$/, "")));
  }

  function disconnect() {
    if (closed) return;
    closed = true;
    handle?.disconnect();
  }

  return { receive, disconnect };
}

/**
 * Opens the native port for a room.
 *
 * @param {object} room  a room from server/multiplayer-room.js
 * @param {object} options
 * @param {string} options.host
 * @param {number} options.port  0 picks a free one
 */
export function attachNativeBridge(room, { host, port, log = () => {} }) {
  const server = net.createServer((socket) => {
    socket.setEncoding("utf8");
    socket.setNoDelay(true);
    const connection = connectNative(room, (text) => socket.write(text), () => socket.end());
    socket.on("data", (chunk) => connection.receive(chunk));
    socket.on("close", () => connection.disconnect());
    socket.on("error", () => connection.disconnect());
  });
  server.on("error", (error) => log(`Native bridge error: ${error.message}`));
  server.listen(port, host);
  return server;
}
