// Reproducible edit-log benchmark on the JavaScript target (browser, Node
// server and Durable Object all run it). The persistent edit log is a Bend
// list, so its cost grows with the world's edits; this measures the walks that
// run every tick or every edit: one `set`, a 64-edit batch, one `block` read,
// the villager door pass, and a light chunk with edits.
//
// WORLD_DIR points at another copy of world/ to compare two versions.
const worldDir = process.env.WORLD_DIR ?? "../world";
const { default: WorldState } = await import(`${worldDir}/world_state.bend`);
const { default: Villagers } = await import(`${worldDir}/villagers.bend`);
const { default: Light } = await import(`${worldDir}/light.bend`);

const SIZES = (process.env.EDIT_SIZES ?? "1000,4000,12000").split(",").map(Number);
const REPEAT = Number(process.env.EDIT_REPEAT ?? 5);
const SEED = 1337n;

function logOf(size) {
  let list = { $: "Nil" };
  for (let index = size - 1; index >= 0; index -= 1) {
    list = { $: "Con", head: WorldState.make_edit(BigInt(index % 512), BigInt(1 + ((index >> 9) % 18)), BigInt(((index >> 13) % 512) + 3), 1), tail: list };
  }
  return list;
}

function time(fn) {
  try {
    fn();
  } catch (error) {
    return String(error?.message ?? error).includes("call stack") ? "overflow" : "error";
  }
  const start = performance.now();
  for (let index = 0; index < REPEAT; index += 1) fn();
  return Number(((performance.now() - start) / REPEAT).toFixed(2));
}

const batch = Array.from({ length: 64 }, (_, i) => WorldState.make_edit(BigInt(700 + (i % 8)), 9n, BigInt(700 + (i >> 3)), 7));
const rows = [];
for (const size of SIZES) {
  const log = logOf(size);
  rows.push({
    edits: size,
    "set (ms)": time(() => WorldState.set(log, 600n, 9n, 600n, 12)),
    "64 sets (ms)": time(() => batch.reduce((edits, e) => WorldState.set(edits, e.x, e.y, e.z, e.block), log)),
    "set_many 64 (ms)": typeof WorldState.set_many === "function"
      ? time(() => WorldState.set_many(log, batch.reduceRight((tail, head) => ({ $: "Con", head, tail }), { $: "Nil" })))
      : "n/a",
    "block (ms)": time(() => WorldState.block(log, SEED, 600n, 9n, 600n)),
    "door pass (ms)": time(() => Villagers.update_doors_result({ $: "Nil" }, SEED, log, 0.0, 0.0)),
    "light chunk (ms)": time(() => Light.chunk_with_edits(WorldState.light_sources(log), log, SEED, 2n, 2n)),
  });
}
console.table(rows);
