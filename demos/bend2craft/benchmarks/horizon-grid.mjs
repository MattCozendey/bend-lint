import Horizon from "../world/horizon.bend";

const start = performance.now();
const grid = Horizon.grid(1337n, 0n, 0n, 65n, 65n, 4n);
console.log(JSON.stringify({ cells: 65 * 65, returned: grid.length, ms: performance.now() - start }));
