import assert from "node:assert/strict";
import Flood from "../world/lightflood.bend";
import Light from "../world/light.bend";

// The torch flood runs on a grid (`Flood.run_grid`) instead of lists
// (`Flood.run`). It must return the very same visited list, in the same order,
// because every light field is built from it.

function cells(list) {
  const out = [];
  for (let node = list; node.$ === "Con"; node = node.tail) out.push(`${node.head.x},${node.head.z},${node.head.light}`);
  return out;
}

let seed = 12345;
const random = () => {
  seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
  return seed / 4294967296;
};
for (let trial = 0; trial < 40; trial += 1) {
  const density = [0, 0.1, 0.25, 0.45][trial % 4];
  const grid = new Array(1024).fill(0);
  let walls = Flood.empty_walls();
  for (let index = 0; index < 1024; index += 1) {
    if (random() < density) {
      grid[index] = 1;
      walls = Flood.wall_list(walls, BigInt(index % 32), BigInt(Math.floor(index / 32)));
    }
  }
  // Sources anywhere, including the window edges and on top of a wall.
  const sx = BigInt(trial % 3 === 0 ? 0 : Math.floor(random() * 32));
  const sz = BigInt(trial % 5 === 0 ? 31 : Math.floor(random() * 32));
  const source = trial % 7 === 0 ? Flood.lava_source(sx, sz) : Flood.source(sx, sz);
  const expected = cells(Flood.run(Flood.sources(source), walls, 1024n));
  const actual = cells(Flood.run_grid(source, grid));
  assert.deepEqual(actual, expected, `trial ${trial}`);
}

// Source fields (flood plus window walls from generated terrain), pinned to
// fingerprints of the list implementation.
const GOLDEN = {
  "1337:20,12,20,12": "365:af737839",
  "1337:5,4,5,21": "5:77f73f3",
  "1337:0,9,3,12": "141:610a7cfb",
  "1337:2,8,0,12": "130:63982f94",
  "1337:200,12,200,12": "291:6f4ad1eb",
  "1337:35,5,35,12": "1:d9f9f97f",
  "1337:14,10,6,12": "316:f0fbf51c",
  "1337:94371830,9,94371835,12": "72:f9112c39",
  "1337:16000020,12,16000020,12": "76:e2ec21e0",
  "1337:60,2,61,21": "5:f6fc5ce9",
  "1337:300,15,17,12": "247:f524997f",
  "42:20,12,20,12": "365:af737839",
  "42:5,4,5,21": "5:77f73f3",
  "42:0,9,3,12": "141:610a7cfb",
  "42:2,8,0,12": "124:4c0e6261",
  "42:200,12,200,12": "292:4af870aa",
  "42:35,5,35,12": "1:d9f9f97f",
  "42:14,10,6,12": "316:f0fbf51c",
  "42:94371830,9,94371835,12": "1:4e197330",
  "42:16000020,12,16000020,12": "1:4de216cd",
  "42:60,2,61,21": "5:f6fc5ce9",
  "42:300,15,17,12": "365:62f97f68"
};
const sources = [
  [20n, 12n, 20n, 12], [5n, 4n, 5n, 21], [0n, 9n, 3n, 12], [2n, 8n, 0n, 12], [200n, 12n, 200n, 12],
  [35n, 5n, 35n, 12], [14n, 10n, 6n, 12], [94371830n, 9n, 94371835n, 12], [16000020n, 12n, 16000020n, 12], [60n, 2n, 61n, 21], [300n, 15n, 17n, 12],
];
for (const worldSeed of [1337n, 42n]) {
  for (const [x, y, z, block] of sources) {
    const fields = Light.source_fields_one({ $: "Edit", x, y, z, block }, worldSeed);
    const items = [];
    for (let node = fields; node.$ === "Con"; node = node.tail) items.push(`${node.head.x},${node.head.y},${node.head.z},${node.head.light}`);
    let hash = 0x811c9dc5;
    const text = items.join(";");
    for (let index = 0; index < text.length; index += 1) {
      hash ^= text.charCodeAt(index);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    const key = `${worldSeed}:${x},${y},${z},${block}`;
    assert.equal(`${items.length}:${hash.toString(16)}`, GOLDEN[key], key);
  }
}
console.log("grid flood matches the list flood");
