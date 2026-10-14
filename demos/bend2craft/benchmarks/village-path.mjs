// Through the boundary: `Villagers.path_grid` takes a `WorldState` as a foreign
// parameter, and which spelling the JS lane wants depends on the module the
// value last passed through (bend-lang/bend#1105).
import { Villagers, WorldState } from "../web/bend-modules.js";
import Path from "../world/village_path.bend";

const routes = [
  [26n, 27n, 20n, 27n],
  [27n, 27n, 23n, 27n],
  [25n, 37n, 25n, 27n],
];
const gridStart = performance.now();
const grid = Villagers.path_grid(1337n, WorldState.empty());
const gridMs = performance.now() - gridStart;
function measure(repeats) {
  const start = performance.now();
  let found = 0;
  for (let repeat = 0; repeat < repeats; repeat += 1) {
    for (const [x, z, targetX, targetZ] of routes) {
      const result = Path.next(grid, x, z, targetX, targetZ, 17n, 19n, 28n, 26n);
      if (result.found) found += 1;
    }
  }
  return { repeats, routes: routes.length, found, pathMs: performance.now() - start, gridMs };
}

console.log(JSON.stringify(measure(10)));
