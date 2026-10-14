import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { FOREIGN, bend, qualify, simplify, bare } from "../web/bend-modules.js";
import { raw } from "../web/bend-modules.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const worldDir = path.join(here, "..", "world");

// 1. The loader's own contract, so the bridge below is not a superstition: a
// datatype owned by another file is rejected bare and accepted qualified. The
// loader throws a bare string here, not an Error. This is the assertion that
// fails first when a pin needs the bridge and the tree has been rewired away
// from it, so it states the rule rather than the outcome of one call.
const bareEdits = raw.WorldState.set(raw.WorldState.empty(), 26n, 9n, 27n, 1);
assert.equal(bareEdits.$, "Con", "a list leaves its module with a bare tag");
assert.equal(bareEdits.head.$, "Edit", "the owner spells its own type bare");
let rejected = null;
try {
  raw.Villagers.path_grid(1337n, bareEdits);
} catch (error) {
  rejected = String(error);
}
const consumerWantsQualified = /world_state\.Edit has no tag Edit/.test(rejected ?? "");
const grid = consumerWantsQualified
  ? raw.Villagers.path_grid(1337n, qualify(bareEdits, "world_state"))
  : raw.Villagers.path_grid(1337n, bareEdits);
assert.equal(grid.$, "Con", "a call the loader accepts returns a list");

// The two lanes are the whole point of the bridge, so pin which one this is
// rather than letting a reader guess from a passing assert.
if (consumerWantsQualified) {
  assert.match(rejected, /its tags: world_state\.Edit/,
    "the rejection must name the tag the consumer actually wants");
}

// 2. The bridge makes the same call work, in both directions, and hands the
// caller the bare naming back. `Villager` is owned by villagers.bend itself, so
// a hand-built villager keeps the bare tag, while the edits it carries do not.
const bridged = bend.villagers.path_grid(1337n, bareEdits);
assert.equal(bridged.$, "Con");
const villager = {
  $: "Con",
  head: {
    $: "Villager", id: 0n, profession: 1, x: 25.5, y: 9, z: 24.5,
    home_x: 25n, home_z: 27n, resting: false,
  },
  tail: { $: "Nil" },
};
const opened = bend.villagers.open_doors(villager, 1337n, bareEdits);
assert.equal(opened.$ in { Con: 1, Nil: 1 }, true, "the result is still a list");
const blockAt = (edits, x, y, z) => Number(bend.world_state.block(edits, 1337n, x, y, z));
assert.equal(blockAt(opened, 25n, 9n, 23n), 15, "open_doors opened the door it found");
assert.equal(blockAt(bareEdits, 25n, 9n, 23n), 14, "the edits it was given were left closed");
for (const node of [opened.head]) {
  if (node === null || node === undefined) continue;
  assert.equal(node.$.includes("."), false, `the bridge must not leak ${node.$} to the adapter`);
  assert.equal(node.$, "Edit", "an edit comes back spelled bare");
}
const closedAgain = bend.villagers.update_doors({ $: "Nil" }, 1337n, opened, 0.0, 0.0);
assert.equal(blockAt(closedAgain, 25n, 9n, 23n), 14, "an emptied villager list closes the door");

// 3. A composite: Simulation holds states that four other files own. An
// accessor hands the foreign state to the adapter, so the bridge normalises it;
// the composite itself keeps whatever spelling the loader gave it, because the
// adapter hands the whole composite back to the module that built it.
//
// How the loader spells a nested foreign field is its own business and has
// changed across pins (bare up to 2.0.28, `owner.Type` from 2.0.32), so what is
// asserted here is the invariant the adapter relies on: whatever comes out,
// everything the adapter can see or hand back is spelled bare, and a round trip
// through the owner preserves the data.
const noList = bend.world_state.empty();
const bareCrops = bend.crops.plant(bend.crops.empty(), 4n, 9n, 4n, 20, 0).state;
assert.equal(bareCrops.$, "State", "crops.bend spells its own state bare");
const sim = bend.simulation.with_crops(bend.simulation.empty(), bareCrops);
assert.equal(sim.$, "Simulation");
assert.equal(bend.simulation.sim_crops(sim).$, "State", "an accessor normalises what it returns");
const countCrops = (state) => {
  let count = 0;
  for (let node = bend.crops.entries(state); node?.$ === "Con"; node = node.tail) count += 1;
  return count;
};
assert.equal(countCrops(bend.simulation.sim_crops(sim)), 1, "so crops.bend accepts it back, crop intact");
const ticked = bend.simulation.tick_with_fluids_and_fire(
  sim, 1n, noList, bend.fluids.empty(), noList, bend.fire.empty(), noList,
);
assert.equal(bend.simulation.tick_simulation(ticked).$, "Simulation", "the composite goes back to its owner");
assert.equal(bend.simulation.tick_fluids(ticked).$, "State", "while the accessor normalises");
assert.equal(bend.simulation.tick_fire(ticked).$, "State");
const refarmed = bend.simulation.with_crops(
  ticked.simulation, bend.simulation.sim_crops(sim),
);
assert.equal(countCrops(bend.simulation.sim_crops(refarmed)), 1, "a normalised state can be handed back");
assert.equal(bend.simulation.sim_farmland(refarmed).$, "State");
assert.equal(raw.Simulation.with_crops !== undefined, true, "the raw module stays reachable");

// 4. The other two foreign shapes the adapter uses: a chest slot list and a
// furnace record, each owned by a file the caller did not import. Both are
// round trips: the value comes out of the owner, is handed back, and survives.
const chestWorld = bend.chests.add(bend.chests.empty(), 4n, 5n, 6n).world;
const foundChest = bend.chests.at(chestWorld, 4n, 5n, 6n);
const slots = bend.chests.lookup_slots(foundChest);
assert.equal(slots.$, "Con", "lookup_slots hands the adapter a bare slot list");
let slotCount = 0;
for (let node = slots; node?.$ === "Con"; node = node.tail) slotCount += 1;
assert.equal(slotCount, 9, "a chest keeps its nine slots across the hand-off");
const replacedChest = bend.chests.set(chestWorld, 4n, 5n, 6n, slots);
assert.equal(bend.chests.at(replacedChest, 4n, 5n, 6n).$, "ChestFound");

const furnaceWorld = bend.furnaces.add(bend.furnaces.empty(), 10n, 5n, 10n).world;
const foundFurnace = bend.furnaces.at(furnaceWorld, 10n, 5n, 10n);
const loaded = raw.Furnace.load_input(foundFurnace.furnace, 15, 1n);
const refuelled = raw.Furnace.load_fuel(loaded.furnace, 14, 1n);
const setFurnace = bend.furnaces.set(furnaceWorld, 10n, 5n, 10n, refuelled.furnace);
assert.equal(bend.furnaces.at(setFurnace, 10n, 5n, 10n).furnace.input, 15,
  "the furnace record reached the container intact");

// 5. The helpers themselves, including that a rewrite allocates nothing when
// the value is already spelled the way the callee wants it.
assert.equal(bare("world_state.Edit"), "Edit");
assert.equal(bare("Edit"), "Edit");
assert.equal(bare("light-dirty.Chunk"), "Chunk");
const already = { $: "world_state.Edit", x: 1n, y: 2n, z: 3n, block: 1 };
assert.equal(qualify(already, "world_state"), already, "a qualified value is not rebuilt");
const list = { $: "Con", head: already, tail: { $: "Nil" } };
assert.equal(qualify(list, "villagers").head.$, "villagers.Edit", "a new owner replaces the old one");
assert.equal(simplify(list).head.$, "Edit");
assert.equal(qualify(7, "world_state"), 7, "a number is not a datatype");
assert.equal(qualify([1, 2], "world_state").length, 2, "a Bend array is a JS array");
assert.deepEqual({ ...qualify({ a: 1, $: "Mob" }, "entities") }, { a: 1, $: "entities.Mob" });

// 5b. A cons list deep enough to blow the stack if the spine were walked by
// recursion. An edit log reaches this size on a long-lived world and every
// wrapped call with a foreign parameter walks it, so the spine has to be a loop.
// The rewrite used to recurse into `tail` and died somewhere past 19,000 cells,
// which is inside the range `benchmarks/multiplayer-room.mjs` measures.
const DEEP = 200000;
let deep = { $: "Nil" };
for (let index = 0; index < DEEP; index += 1) {
  deep = { $: "Con", head: { $: "Edit", x: BigInt(index), y: 1n, z: 1n, block: 1 }, tail: deep };
}
const deepQualified = qualify(deep, "world_state");
assert.equal(deepQualified.head.$, "world_state.Edit", "the head of a deep list is spelled");
let deepCount = 0;
for (let node = deepQualified; node.$ === "Con"; node = node.tail) deepCount += 1;
assert.equal(deepCount, DEEP, "a deep list keeps every cell across the boundary");
assert.equal(deepQualified.tail.tail === undefined, false, "the spine ends in a Nil");
let bareCount = 0;
for (let node = simplify(deepQualified); node.$ === "Con"; node = node.tail) {
  if (node.head.$ !== "Edit") break;
  bareCount += 1;
}
assert.equal(bareCount, DEEP, "and comes back bare, one cell at a time, without recursing");

// 6. Anti-drift: FOREIGN must describe exactly the foreign types the world
// signatures declare. A new cross-file parameter fails here until the table
// learns about it, and a stale entry fails too.
const BASE_TYPES = new Set([
  "Nat", "U32", "U8", "U16", "U64", "I32", "I64", "F32", "F64", "Bool", "String",
  "Char", "List", "Maybe", "Map", "IO", "Data", "Empty", "Word", "Pair", "Array",
]);
// LAWS.bend and PROOF.bend are read by the checker only: their defs are lemmas whose
// "types" are propositions, and nothing in them crosses into the JS lane.
const PROOF_FILES = new Set(["LAWS.bend", "PROOF.bend"]);
const files = readdirSync(worldDir).filter((name) => name.endsWith(".bend") && !PROOF_FILES.has(name));
const sources = new Map();
const defines = new Map();
const aliasToFile = new Map();
for (const name of files) {
  const source = readFileSync(path.join(worldDir, name), "utf8").replace(/\r\n/g, "\n");
  sources.set(name, source);
  defines.set(name, new Set([...source.matchAll(/^type\s+(\w+)\s+is\s+Data:/gm)].map((m) => m[1])));
  for (const m of source.matchAll(/^import\s+\.\/(\w[\w-]*)\.bend(?:\s+as\s+(\w+))?/gm)) {
    aliasToFile.set(`${name.replace(/\.bend$/, "")}.${m[2] ?? m[1]}`, m[1]);
  }
}
const mentioned = (text) => [...text.matchAll(/(?:(\w+)\.)?(\w+)/g)]
  .filter((m) => m[1] || (!BASE_TYPES.has(m[2]) && !/^\d+$/.test(m[2])))
  .map((m) => (m[1] ? `${m[1]}.${m[2]}` : m[2]));
const splitTop = (text) => {
  const parts = [];
  let depth = 0;
  let current = "";
  for (const ch of text) {
    if (ch === "<") depth += 1;
    if (ch === ">") depth -= 1;
    if (ch === "," && depth === 0) { parts.push(current); current = ""; continue; }
    current += ch;
  }
  if (current.trim()) parts.push(current);
  return parts.map((part) => part.trim()).filter(Boolean);
};

const expected = {};
let foreignReturns = 0;
for (const [name, source] of sources) {
  const module = name.replace(/\.bend$/, "");
  for (const m of source.matchAll(/^def\s+(\w+)\s*\(([^)]*)\)\s*(?:->\s*([^:\n]+))?:/gm)) {
    const [, def, paramText, retText] = m;
    const spec = {};
    splitTop(paramText).forEach((raw, index) => {
      const body = raw.replace(/^[+~-]+\s*/, "");
      if (!body.includes(":")) return;
      for (const type of mentioned(body.slice(body.indexOf(":") + 1))) {
        if (!type.includes(".")) continue;
        const [alias, typeName] = type.split(".");
        const owner = aliasToFile.get(`${module}.${alias}`);
        assert.ok(owner, `${module}.${def} names ${type}, whose import alias is unknown`);
        assert.ok(
          defines.get(`${owner}.bend`).has(typeName),
          `${module}.${def} names ${type}, which ${owner}.bend does not define`,
        );
        spec[index] = owner;
      }
    });
    for (const type of retText ? mentioned(retText).filter((entry) => entry.includes(".")) : []) {
      const [alias, typeName] = type.split(".");
      const owner = aliasToFile.get(`${module}.${alias}`);
      assert.ok(owner, `${module}.${def} returns ${type}, whose import alias is unknown`);
      assert.ok(
        defines.get(`${owner}.bend`).has(typeName),
        `${module}.${def} returns ${type}, which ${owner}.bend does not define`,
      );
      foreignReturns += 1;
      spec.out = true;
    }
    if (Object.keys(spec).length > 0) expected[module] ??= {}, expected[module][def] = spec;
  }
}
assert.deepEqual(
  FOREIGN,
  expected,
  "FOREIGN must match the foreign parameters declared in the world signatures",
);
const documented = Object.values(FOREIGN)
  .reduce((total, defs) => total + Object.keys(defs).length, 0);
const scanned = Object.values(expected)
  .reduce((total, defs) => total + Object.keys(defs).length, 0);
assert.equal(documented, scanned, "the table must not carry a stale or missing entry");
assert.ok(scanned >= 30, `expected the known cross-file surface, found ${scanned}`);
assert.ok(foreignReturns >= 6, `expected foreign return types to be validated, found ${foreignReturns}`);
console.log(`bend bridge ok (${scanned} cross-file defs, ${foreignReturns} foreign returns)`);
