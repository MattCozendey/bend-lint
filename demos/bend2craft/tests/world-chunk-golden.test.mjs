import assert from "node:assert/strict";
import World from "../world/world.bend";
import WorldState from "../world/world_state.bend";
import Light from "../world/light.bend";
import Horizon from "../world/horizon.bend";

// World generation runs through a U32 core with per-column precomputation, and
// chunk light is filled column by column from the top. Both must stay
// byte-identical to the original per-cell Nat rules. These fingerprints were
// taken from that original implementation (commit c66bfb1) before it was
// replaced; any drift here is a behaviour change, not a refactor.

function fnv16(values, count) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < count; i += 1) {
    hash ^= Number(values[i]) & 0xff;
    hash = Math.imul(hash, 0x01000193) >>> 0;
    hash ^= (Number(values[i]) >>> 8) & 0xff;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16);
}

function fnv8(values, count) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < count; i += 1) {
    hash ^= Number(values[i]) & 0xff;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16);
}

// Any drift here is a behaviour change, not a refactor. The chunk and edited
// fingerprints moved on 2026-10-03 three times: once when the bottom row of every
// chunk became bedrock (block 41) and max_y went from 20 to 64, again when the
// cave rule became a two-field lattice instead of one per-cell hash, and again
// when the ores became veins on an eight-cell lattice with vanilla's bands and
// densities. The light, height and surface fingerprints were unchanged by all
// three: an ore is as opaque as the stone it replaces.
const CELLS = 16 * 16 * 20;
const GOLDEN = {
  "chunks": {
    "1337:0,0": "cd119d3d",
    "1337:1,0": "f604008d",
    "1337:0,1": "ef0baa8c",
    "1337:1,1": "41f71ab3",
    "1337:2,1": "f248ab33",
    "1337:1,2": "502d1399",
    "1337:3,3": "54a117c4",
    "1337:5,2": "dbbc2964",
    "1337:1000001,0": "6a5be37",
    "1337:1000002,1000001": "ba5ba32c",
    "1337:0,1000003": "100f5f8c",
    "42:0,0": "6233c834",
    "42:1,0": "b99b6854",
    "42:0,1": "7a489615",
    "42:1,1": "233dc09b",
    "42:2,1": "4ea60ae0",
    "42:1,2": "34369980",
    "42:3,3": "d68131fb",
    "42:5,2": "2e04f19c",
    "42:1000001,0": "ec905da5",
    "42:1000002,1000001": "c0cd1cce",
    "42:0,1000003": "ff49bd20",
    "987654321:0,0": "e50ec58",
    "987654321:1,0": "e03f73fb",
    "987654321:0,1": "6f509522",
    "987654321:1,1": "f408495c",
    "987654321:2,1": "4ffc9e45",
    "987654321:1,2": "eb65b6b5",
    "987654321:3,3": "fa612704",
    "987654321:5,2": "b9ddd1d4",
    "987654321:1000001,0": "b4bd6e5",
    "987654321:1000002,1000001": "3499f9e",
    "987654321:0,1000003": "54d684b4",
    "1099511627783:0,0": "d2026ce4",
    "1099511627783:1,0": "7da2b4",
    "1099511627783:0,1": "5b5e4d64",
    "1099511627783:1,1": "4e352cbb",
    "1099511627783:2,1": "f7d8b1cf",
    "1099511627783:1,2": "828f272",
    "1099511627783:3,3": "bec2102a",
    "1099511627783:5,2": "503b8f53",
    "1099511627783:1000001,0": "a9f79fee",
    "1099511627783:1000002,1000001": "71c3cd87",
    "1099511627783:0,1000003": "144659",
  },
  "heights": {
    "42": "d418277",
    "1337": "c64aef7c",
    "987654321": "a487dbee",
    "1099511627783": "139f5083"
  },
  "light": {
    "1337:0,0": "8094d810",
    "1337:1,1": "73c2eeb7",
    "42:0,0": "7e1f6055",
    "42:1,1": "475fa146",
    "987654321:0,0": "c44bc7bc",
    "987654321:1,1": "57bed30f",
    "1099511627783:0,0": "522f769b",
    "1099511627783:1,1": "764d71af"
  },
  "surface": {
    "42": "f78a50f6",
    "1337": "81895b78",
    "987654321": "32958fdb",
    "1099511627783": "4d41eae1"
  },
  "edited": "4220372f"
};
const LIGHT_GOLDEN = {
  "nil:1337:0,0": "db7c8eff",
  "edits:1337:0,0": "78e22b30",
  "nil:1337:1,1": "b78b2ab3",
  "edits:1337:1,1": "5fe49905",
  "nil:1337:0,1": "4eec3dfb",
  "edits:1337:0,1": "30d30b55",
  "nil:1337:2,2": "8c9e726e",
  "edits:1337:2,2": "fa603199",
  "nil:1337:12,12": "8ad8d1f0",
  "edits:1337:12,12": "60978714",
  "nil:1337:1000001,1000001": "d7e5821f",
  "edits:1337:1000001,1000001": "697a23ab",
  "nil:42:0,0": "8daad123",
  "edits:42:0,0": "c94d13ee",
  "nil:42:1,1": "92a434ee",
  "edits:42:1,1": "e80397a8",
  "nil:42:0,1": "dfc230b7",
  "edits:42:0,1": "59d6a811",
  "nil:42:2,2": "a45163f7",
  "edits:42:2,2": "586c067c",
  "nil:42:12,12": "bbdef7bd",
  "edits:42:12,12": "7248bd30",
  "nil:42:1000001,1000001": "add6cb16",
  "edits:42:1000001,1000001": "ca950464",
  "nil:1099511627783:0,0": "2fbeb4f3",
  "edits:1099511627783:0,0": "c346c350",
  "nil:1099511627783:1,1": "84cebdf",
  "edits:1099511627783:1,1": "977b604",
  "nil:1099511627783:0,1": "6f741bfb",
  "edits:1099511627783:0,1": "72e0e76b",
  "nil:1099511627783:2,2": "f8a94889",
  "edits:1099511627783:2,2": "16f9610e",
  "nil:1099511627783:12,12": "388037e",
  "edits:1099511627783:12,12": "1ed17b91",
  "nil:1099511627783:1000001,1000001": "a207295b",
  "edits:1099511627783:1000001,1000001": "cb63b0e9"
};

const seeds = [1337n, 42n, 987654321n, (1n << 40n) + 7n];
const chunks = [[0, 0], [1, 0], [0, 1], [1, 1], [2, 1], [1, 2], [3, 3], [5, 2], [1000001, 0], [1000002, 1000001], [0, 1000003]];
const torchEdits = WorldState.set(WorldState.set(WorldState.empty(), 20n, 12n, 20n, 12), 21n, 9n, 20n, 0);
for (const seed of seeds) {
  for (const [cx, cz] of chunks) {
    const blocks = WorldState.chunk(seed, BigInt(cx), BigInt(cz), WorldState.empty());
    assert.equal(fnv16(blocks, CELLS), GOLDEN.chunks[`${seed}:${cx},${cz}`], `chunk ${seed}:${cx},${cz}`);
  }
  const heights = [];
  for (let x = 0; x < 200; x += 7) for (let z = 0; z < 200; z += 11) heights.push(Number(World.column_height(seed, BigInt(x), BigInt(z))));
  heights.push(Number(World.column_height(seed, 16000031n, 16000017n)));
  assert.equal(fnv16(heights, heights.length), GOLDEN.heights[String(seed)], `heights ${seed}`);
  for (const [cx, cz] of [[0, 0], [1, 1]]) {
    const light = Light.chunk_with_edits(WorldState.light_sources(torchEdits), torchEdits, seed, BigInt(cx), BigInt(cz));
    assert.equal(fnv16(light, CELLS), GOLDEN.light[`${seed}:${cx},${cz}`], `light ${seed}:${cx},${cz}`);
  }
  let points = { $: "Nil" };
  for (let i = 0; i < 300; i += 1) {
    points = { $: "Con", head: { $: "SurfacePoint", x: BigInt(i * 13 % 500), z: BigInt(i * 29 % 700) }, tail: points };
  }
  assert.equal(fnv16(Horizon.surface_points(seed, 300n, points), 300), GOLDEN.surface[String(seed)], `surface ${seed}`);
}
assert.equal(fnv16(WorldState.chunk(1337n, 1n, 1n, torchEdits), CELLS), GOLDEN.edited, "edited chunk");

// Light: a fresh world (no edits) and a save with near and far torches, a lava
// bucket, dug cells, a placed block, glass and an open door.
let edits = WorldState.empty();
edits = WorldState.set(edits, 20n, 12n, 20n, 12);
edits = WorldState.set(edits, 5n, 4n, 5n, 21);
edits = WorldState.set(edits, 200n, 12n, 200n, 12);
edits = WorldState.set(edits, 21n, 9n, 20n, 0);
edits = WorldState.set(edits, 22n, 15n, 22n, 1);
edits = WorldState.set(edits, 3n, 9n, 3n, 0);
edits = WorldState.set(edits, 3n, 8n, 3n, 0);
edits = WorldState.set(edits, 9n, 16n, 9n, 25);
edits = WorldState.set(edits, 12n, 6n, 12n, 15);
edits = WorldState.set(edits, 16000020n, 12n, 16000020n, 12);
const sources = WorldState.light_sources(edits);
const fieldCache = new Map();
for (const seed of [1337n, 42n, (1n << 40n) + 7n]) {
  for (const [cx, cz] of [[0, 0], [1, 1], [0, 1], [2, 2], [12, 12], [1000001, 1000001]]) {
    const empty = Light.chunk_with_edits(WorldState.light_sources(WorldState.empty()), WorldState.empty(), seed, BigInt(cx), BigInt(cz));
    assert.equal(fnv8(empty, CELLS), LIGHT_GOLDEN[`nil:${seed}:${cx},${cz}`], `fresh light ${seed}:${cx},${cz}`);
    const lit = Light.chunk_with_edits(sources, edits, seed, BigInt(cx), BigInt(cz));
    assert.equal(fnv8(lit, CELLS), LIGHT_GOLDEN[`edits:${seed}:${cx},${cz}`], `edited light ${seed}:${cx},${cz}`);

    // The cached-field entry point the chunk worker uses must agree exactly.
    const relevant = [];
    for (let node = Light.relevant_sources(sources, BigInt(cx), BigInt(cz)); node.$ === "Con"; node = node.tail) relevant.push(node.head);
    let fields = { $: "Nil" };
    for (let index = relevant.length - 1; index >= 0; index -= 1) {
      const source = relevant[index];
      const key = `${seed}:${source.x},${source.y},${source.z},${source.block}`;
      if (!fieldCache.has(key)) fieldCache.set(key, Light.source_fields_one(source, seed));
      fields = Light.append_fields(fieldCache.get(key), fields);
    }
    const cached = Light.chunk_with_fields(fields, edits, seed, BigInt(cx), BigInt(cz));
    assert.equal(fnv8(cached, CELLS), LIGHT_GOLDEN[`edits:${seed}:${cx},${cz}`], `cached-field light ${seed}:${cx},${cz}`);
  }
}

console.log("world chunk golden fingerprints match");
