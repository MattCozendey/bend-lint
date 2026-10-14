// Through the boundary: `Simulation.tick_with_fluids` takes `Fluids.State` and
// `Fluids.Sample` as foreign parameters, and the v2.0.32 JS lane wants those
// spelled `fluids.*` on the way in.
import { Fluids, Simulation } from "../web/bend-modules.js";
import { bendList, listLength } from "../web/bend-list.js";

function measure(fn, repeats = 10) {
  fn();
  const start = performance.now();
  for (let repeat = 0; repeat < repeats; repeat += 1) fn();
  return (performance.now() - start) / repeats;
}

const samples = bendList([
  Fluids.sample(2n, 2n, 2n, 1),
  Fluids.sample(1n, 3n, 2n, 0),
  Fluids.sample(3n, 3n, 2n, 0),
  Fluids.sample(2n, 3n, 1n, 0),
  Fluids.sample(2n, 3n, 3n, 0),
]);
const seeded = Fluids.seed(Fluids.empty(), 2n, 3n, 2n, 3);
const flowing = Fluids.tick(seeded, samples);
const simulation = Simulation.empty();
let manyFlows = Fluids.empty();
for (let index = 0; index < 40; index += 1) {
  manyFlows = Fluids.seed(manyFlows, BigInt(index), 1n, 1n, 8);
}

console.log(JSON.stringify({
  flowCount: listLength(Fluids.state_flows(flowing)),
  tickAndChangesMs: measure(() => {
    const next = Fluids.tick(seeded, samples);
    Fluids.changes(seeded, next);
  }),
  unifiedTickMs: measure(() => {
    Simulation.tick_with_fluids(simulation, 1n, { $: "Nil" }, seeded, samples);
  }),
  remove40Ms: measure(() => Fluids.remove(manyFlows, 39n, 1n, 1n)),
}));
