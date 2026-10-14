import assert from "node:assert/strict";
import World from "../world/world.bend";
import WorldState from "../world/world_state.bend";
import {
  NEGATIVE_ORIGIN,
  canonicalCells,
  generationChunkCoordinate,
  isLegacyNegativeCoordinate,
  migrateLegacyCoordinate,
  migrateLegacyEdits,
  stencilCoordinate,
  storageCoordinate,
  worldCoordinate,
} from "../web/world-coordinates.js";

const CHUNK = 16;

// One constant on both sides of the boundary.
assert.equal(NEGATIVE_ORIGIN, Number(World.negative_origin()));
assert.equal(NEGATIVE_ORIGIN % CHUNK, 0);

// Round trip, and chunk coordinates agree with block coordinates.
for (const x of [0, 1, 15, 16, 95, 96, 1000, 123456, -1, -15, -16, -17, -1000, -123457]) {
  const stored = storageCoordinate(x, CHUNK);
  assert.ok(stored >= 0);
  assert.equal(worldCoordinate(stored), x);
  const chunk = Math.floor(x / CHUNK);
  const local = x - chunk * CHUNK;
  assert.equal(generationChunkCoordinate(chunk, CHUNK) * CHUNK + local, stored, `chunk mapping for ${x}`);
  assert.equal(worldCoordinate(BigInt(stored)), x);
  assert.equal(worldCoordinate(stencilCoordinate(x)), x, "stencil aliases decode to the same cell");
}

// The terrain continues across zero: with z >= 96 (outside the spawn plains)
// the columns stored just above NEGATIVE_ORIGIN (world x >= 0 seen from the
// negative side) are the same columns as world x >= 0, so the heights at world
// x = -1, -2, ... run straight into those at 0, 1, ... without a cut.
for (const seed of [1337n, 42n]) {
  for (const z of [96, 130, 511]) {
    for (let k = 0; k < 32; k += 1) {
      assert.equal(
        World.column_height(seed, BigInt(NEGATIVE_ORIGIN + k), BigInt(z)),
        World.column_height(seed, BigInt(k), BigInt(z)),
        `height continuity at x=${k}, z=${z}`,
      );
    }
  }
}
// Away from the origin-anchored features whole chunks are shift invariant.
for (const [chunkX, chunkZ] of [[6, 0], [9, 3], [7, 20]]) {
  const shifted = WorldState.chunk(1337n, BigInt(chunkX + NEGATIVE_ORIGIN / CHUNK), BigInt(chunkZ), WorldState.empty());
  const plain = WorldState.chunk(1337n, BigInt(chunkX), BigInt(chunkZ), WorldState.empty());
  assert.deepEqual(Array.from(shifted).slice(0, CHUNK * CHUNK * 20), Array.from(plain).slice(0, CHUNK * CHUNK * 20));
}

// Entities read the same stored cells.
assert.equal(World.cell(3.7), 3n);
assert.equal(World.cell(0), 0n);
assert.equal(World.cell(-0.25), BigInt(storageCoordinate(-1)));
assert.equal(World.cell(-17.5), BigInt(storageCoordinate(-18)));

// Legacy saves: negative coordinates lived in chunk 1_000_000 + |chunk|.
function legacyStorage(value) {
  if (value >= 0) return value;
  const chunk = Math.floor(value / CHUNK);
  const local = value - chunk * CHUNK;
  return (1_000_000 + (-chunk)) * CHUNK + local;
}
for (const x of [-1, -16, -17, -300, -99999]) {
  const legacy = legacyStorage(x);
  assert.ok(isLegacyNegativeCoordinate(legacy, CHUNK));
  assert.equal(migrateLegacyCoordinate(legacy, CHUNK), storageCoordinate(x, CHUNK));
}
for (const stored of [0, 5, 5000, storageCoordinate(-5)]) {
  assert.equal(isLegacyNegativeCoordinate(stored, CHUNK), false);
  assert.equal(migrateLegacyCoordinate(stored, CHUNK), stored);
}
const legacyEdits = WorldState.set(
  WorldState.set(WorldState.empty(), BigInt(legacyStorage(-3)), 9n, 12n, 0),
  4n, 10n, BigInt(legacyStorage(-40)), 12,
);
const migrated = migrateLegacyEdits(legacyEdits, CHUNK);
const heads = [];
for (let node = migrated; node.$ === "Con"; node = node.tail) heads.push([Number(node.head.x), Number(node.head.y), Number(node.head.z), Number(node.head.block)]);
assert.deepEqual(heads.sort(), [
  [storageCoordinate(-3), 9, 12, 0],
  [4, 10, storageCoordinate(-40), 12],
].sort());
const current = WorldState.set(WorldState.empty(), BigInt(storageCoordinate(-3)), 9n, 12n, 0);
assert.equal(migrateLegacyEdits(current, CHUNK), current, "a current save is returned untouched");

// Stencil cells come back canonical.
const cells = { $: "Con", head: { $: "Cell", x: BigInt(stencilCoordinate(2)), y: 5n, z: BigInt(stencilCoordinate(-2)) }, tail: { $: "Nil" } };
const canonical = canonicalCells(cells, CHUNK);
assert.equal(canonical.head.x, 2n);
assert.equal(canonical.head.z, BigInt(storageCoordinate(-2)));
assert.equal(canonical.head.y, 5n);

console.log("world coordinates ok");
