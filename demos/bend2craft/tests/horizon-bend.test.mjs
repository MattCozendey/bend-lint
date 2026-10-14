import assert from "node:assert/strict";
import Horizon from "../world/horizon.bend";
import World from "../world/world.bend";

const grid = Horizon.grid(1337n, 0n, 0n, 5n, 5n, 4n);
assert.equal(Array.isArray(grid), true);
assert.equal(grid.length, 8192);
assert.equal(Number(grid[0]), Number(World.column_height(1337n, 0n, 0n)));
assert.equal(Number(grid[6]), Number(World.column_height(1337n, 4n, 4n)));
assert.deepEqual(
  Array.from(Horizon.grid(1337n, 0n, 0n, 5n, 5n, 4n)).slice(0, 25),
  Array.from(grid).slice(0, 25),
);
assert.notDeepEqual(
  Array.from(Horizon.grid(7331n, 0n, 0n, 5n, 5n, 4n)).slice(0, 25),
  Array.from(grid).slice(0, 25),
);
let waterSample = null;
for (let x = 0n; x < 48n && waterSample === null; x += 1n) {
  for (let z = 0n; z < 48n; z += 1n) {
    if (World.water_at(1337n, x, World.sea_level(), z)) {
      waterSample = [x, z];
      break;
    }
  }
}
assert.ok(waterSample !== null);
const surface = Horizon.surface_grid(1337n, waterSample[0], waterSample[1], 1n, 1n, 1n);
assert.ok(Number(surface[0]) >= 32);
const points = {
  $: "Con",
  head: { $: "SurfacePoint", x: waterSample[0], z: waterSample[1] },
  tail: {
    $: "Con",
    head: { $: "SurfacePoint", x: 4n, z: 7n },
    tail: { $: "Nil" },
  },
};
const pointSurface = Horizon.surface_points(1337n, 2n, points);
assert.equal(Number(pointSurface[0]), Number(surface[0]));
const secondSurface = Horizon.surface_grid(1337n, 4n, 7n, 1n, 1n, 1n);
assert.equal(Number(pointSurface[1]), Number(secondSurface[0]));
console.log("horizon grid ok");
