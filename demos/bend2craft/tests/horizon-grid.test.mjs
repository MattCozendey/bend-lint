import assert from "node:assert/strict";
import Horizon from "../world/horizon.bend";
import { sampleSignedSurfaceGrid } from "../web/horizon-grid.js";

let sampleCount = null;
let sampledPoints = [];
const result = sampleSignedSurfaceGrid({
  minX: -8,
  minZ: -4,
  columns: 3,
  rows: 2,
  step: 4,
  chunkSize: 16,
  encodeCoordinate: (value) => value + 100,
  sample: (count, points) => {
    sampleCount = count;
    for (let node = points; node?.$ === "Con"; node = node.tail) {
      sampledPoints.push({ x: Number(node.head.x), z: Number(node.head.z) });
    }
    return sampledPoints.map(({ x, z }) => x + z);
  },
});

assert.equal(sampleCount, 6n);
assert.deepEqual(result.coordinates, [
  [-8, -4], [-4, -4], [0, -4],
  [-8, 0], [-4, 0], [0, 0],
]);
assert.deepEqual(sampledPoints, [
  { x: 92, z: 96 }, { x: 96, z: 96 }, { x: 100, z: 96 },
  { x: 92, z: 100 }, { x: 96, z: 100 }, { x: 100, z: 100 },
]);
assert.deepEqual(result.values, [188, 192, 196, 192, 196, 200]);

const CHUNK_SIZE = 16;
const GENERATION_CHUNK_OFFSET = 1_000_000;
function storageCoordinate(value) {
  if (value >= 0) return value;
  const chunk = Math.floor(value / CHUNK_SIZE);
  const local = value - chunk * CHUNK_SIZE;
  return (GENERATION_CHUNK_OFFSET + (-chunk)) * CHUNK_SIZE + local;
}

const signed = sampleSignedSurfaceGrid({
  minX: -16,
  minZ: -16,
  columns: 3,
  rows: 3,
  step: 8,
  encodeCoordinate: storageCoordinate,
  sample: (count, points) => Horizon.surface_points(1337n, count, points),
});
for (const [index, [x, z]] of signed.coordinates.entries()) {
  const expected = Horizon.surface_grid(
    1337n,
    BigInt(storageCoordinate(x)),
    BigInt(storageCoordinate(z)),
    1n,
    1n,
    1n,
  )[0];
  assert.equal(signed.values[index], Number(expected));
}
console.log("horizon signed grid ok");
