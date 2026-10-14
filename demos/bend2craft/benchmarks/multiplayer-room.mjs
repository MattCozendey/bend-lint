import { bendEditsToWire, wireEditsToBend } from "../web/multiplayer-protocol.js";
import { Multiplayer, MultiplayerMoves as Moves, WorldState } from "../web/bend-modules.js";

// Reproducible multiplayer authority benchmark on the JavaScript target (the
// target the Node server, the Durable Object and the browser all run). It
// measures how the room's edit log scales: one player action, a fluid-sized
// batch, the client replay of one batch, and the welcome snapshot; and the
// per-pose movement check (independent of the log).

const SIZES = (process.env.ROOM_SIZES ?? "1000,5000,20000").split(",").map(Number);
const REPEAT = Number(process.env.ROOM_REPEAT ?? 20);
const SEED = 1337n;

function logOf(size) {
  const edits = [];
  for (let index = 0; index < size; index += 1) edits.push([index % 512, 1 + (index >> 9) % 18, (index >> 13) % 512 + 3, 1]);
  return edits;
}

function time(label, fn) {
  fn();
  const start = performance.now();
  for (let index = 0; index < REPEAT; index += 1) fn();
  return { label, ms: (performance.now() - start) / REPEAT };
}

const rows = [];
for (const size of SIZES) {
  const log = logOf(size);
  const room = Multiplayer.restore(0, wireEditsToBend(log), Multiplayer.room_chests(Multiplayer.empty()), Multiplayer.room_furnaces(Multiplayer.empty()));
  const one = wireEditsToBend([[600, 9, 600, 12]]);
  const batch = wireEditsToBend(Array.from({ length: 64 }, (_, i) => [700 + (i % 8), 9, 700 + (i >> 3), 7]));
  const edits = Multiplayer.room_edits(room);
  rows.push({ size, ...Object.fromEntries([
    time("submit 1", () => Multiplayer.submit(room, one)),
    time("submit 64", () => Multiplayer.submit(room, batch)),
    time("merge 1", () => Multiplayer.merge(one, edits)),
    time("welcome", () => bendEditsToWire(edits)),
    time("chunk", () => WorldState.chunk(SEED, 2n, 2n, edits)),
  ].map(({ label, ms }) => [label, Number(ms.toFixed(3))])) });
}
console.table(rows);

const budget = Moves.fresh();
const poses = 10000;
const start = performance.now();
for (let index = 0; index < poses; index += 1) {
  Moves.accepted(Moves.step(budget, 0.1, index, 70, 0, index + 0.6, 70, 0, 0, 0, 0, 0, 1e6, 1e6));
}
console.log(`movement check: ${((performance.now() - start) * 1000 / poses).toFixed(2)} us per pose`);
