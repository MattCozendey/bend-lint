// Through the boundary: `Entities.sunlight_damage` takes a `WorldState` as a
// foreign parameter. The `{ $: "Nil" }` this benchmark passes is a Base list
// constructor and stays bare either way, so routing it changes nothing measured.
import { Entities } from "../web/bend-modules.js";

const ITERATIONS = 100;

function elapsed(run) {
  // Warm the generated recursion before timing so the first scenario does not
  // absorb the whole run's JIT cost and report a fictional slowdown.
  for (let index = 0; index < 20; index += 1) run();
  const start = performance.now();
  let state = null;
  for (let index = 0; index < ITERATIONS; index += 1) state = run();
  return { ms: performance.now() - start, state };
}

const initial = Entities.spawn(1337n, 0.0, 0n, 0n, 256n, 256n);
let count = 0;
for (let node = initial; node?.$ === "Con"; node = node.tail) count += 1;
let airCells = { $: "Nil" };
for (let index = 5 * 6 * 5 - 1; index >= 0; index -= 1) {
  airCells = { $: "Con", head: 0, tail: airCells };
}
const airRegion = {
  $: "Region",
  blocks: airCells,
  origin_x: 0n,
  origin_y: 0n,
  origin_z: 0n,
  width: 5n,
  height: 6n,
  depth: 5n,
};
let airRegions = { $: "Nil" };
for (let index = 0; index < count; index += 1) {
  airRegions = { $: "Con", head: airRegion, tail: airRegions };
}
const full = elapsed(() => Entities.step_world(initial, 40.5, 40.5, 0.2, 10.0, 0n, airRegions));
const budgeted = elapsed(() => Entities.step_budgeted(initial, 40.5, 40.5, 0.2, 32.0));
const sunlight = elapsed(() => Entities.sunlight_damage(initial, { $: "Nil" }, 1337n, 1.0, 0.2, { $: "Nil" }));
// The threat query now carries a block window and an eye-ray scan, so measure
// it explicitly instead of assuming it stays inside the movement budget.
function firstHostile(list) {
  for (let node = list; node?.$ === "Con"; node = node.tail) {
    if (Number(node.head.kind) === 2 || Number(node.head.kind) === 4) return node.head;
  }
  return null;
}

const contactMob = firstHostile(initial);
const threat = elapsed(() => Entities.threat_damage(initial, 40.5, 40.5, 40.5, 0n, airRegions));
const threatFar = elapsed(() => Entities.threat_damage(initial, 500.5, 40.5, 500.5, 0n, airRegions));
// Worst case: the player stands on a hostile, so that mob pays the full
// eight-sample eye ray while every other mob short-circuits on range.
const threatContact = elapsed(() => Entities.threat_damage(
  initial,
  Number(contactMob.x),
  Number(contactMob.y),
  Number(contactMob.z),
  0n,
  airRegions,
));
console.log(JSON.stringify({
  count,
  iterations: ITERATIONS,
  fullMsPerCall: Number((full.ms / ITERATIONS).toFixed(3)),
  budgetedMsPerCall: Number((budgeted.ms / ITERATIONS).toFixed(4)),
  sunlightMsPerCall: Number((sunlight.ms / ITERATIONS).toFixed(3)),
  threatMsPerCall: Number((threat.ms / ITERATIONS).toFixed(4)),
  threatFarMsPerCall: Number((threatFar.ms / ITERATIONS).toFixed(4)),
  threatContactMsPerCall: Number((threatContact.ms / ITERATIONS).toFixed(4)),
  threatContactDamage: Number(threatContact.state),
}));
