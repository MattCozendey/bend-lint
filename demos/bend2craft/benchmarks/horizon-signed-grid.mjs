import Horizon from "../world/horizon.bend";

const CHUNK_SIZE = 16;
const GENERATION_CHUNK_OFFSET = 1_000_000;
const minX = -128;
const minZ = -128;
const columns = 65;
const rows = 65;
const step = 4;

function storageCoordinate(value) {
  if (value >= 0) return value;
  const chunk = Math.floor(value / CHUNK_SIZE);
  const local = value - chunk * CHUNK_SIZE;
  return (GENERATION_CHUNK_OFFSET + (-chunk)) * CHUNK_SIZE + local;
}

let points = { $: "Nil" };
for (let row = rows - 1; row >= 0; row -= 1) {
  for (let column = columns - 1; column >= 0; column -= 1) {
    const x = minX + column * step;
    const z = minZ + row * step;
    points = {
      $: "Con",
      head: { $: "SurfacePoint", x: BigInt(storageCoordinate(x)), z: BigInt(storageCoordinate(z)) },
      tail: points,
    };
  }
}

const start = performance.now();
const surface = Horizon.surface_points(1337n, BigInt(columns * rows), points);
console.log(JSON.stringify({
  cells: columns * rows,
  returned: surface.length,
  minX,
  minZ,
  ms: performance.now() - start,
}));
