import assert from "node:assert/strict";
import { Simulation, Crops, Farmland, Fluids } from "../web/bend-modules.js";

function listLength(list) {
  let count = 0;
  for (let node = list; node?.$ === "Con"; node = node.tail) count += 1;
  return count;
}

let state = Simulation.empty();
assert.equal(state.$, "Simulation");
const planted = Crops.plant(Crops.empty(), 4n, 9n, 4n, 20, 0);
state = Simulation.with_crops(state, planted.state);
state = Simulation.with_farmland(state, Farmland.add(Farmland.empty(), 4n, 8n, 4n).state);
state = Simulation.pin(state, 2n, 3n);
state = Simulation.pin(state, 8n, 9n);
assert.equal(Number(Simulation.pinned_count(state)), 2);
const water = { $: "Con", head: { $: "Water", x: 7n, z: 4n }, tail: { $: "Nil" } };
state = Simulation.tick_with_water(state, 4n, water);
assert.equal(Number(Simulation.time(state)), 4);
assert.equal(Number(Simulation.chunk_ticks(state, 2n, 3n)), 4);
assert.equal(Number(Simulation.sim_crops(state).crops.head.stage), 17);
state = Simulation.tick_with_water(state, 4n, water);
assert.equal(Number(Simulation.sim_crops(state).crops.head.stage), 18);
state = Simulation.tick_with_water(state, 4n, water);
assert.equal(Number(Simulation.sim_crops(state).crops.head.stage), 19);
state = Simulation.unpin(state, 2n, 3n);
assert.equal(Number(Simulation.pinned_count(state)), 1);
assert.equal(Number(Simulation.chunk_ticks(state, 2n, 3n)), 0);

const fluidSamples = {
  $: "Con",
  head: Fluids.sample(2n, 2n, 2n, 1),
  tail: {
    $: "Con",
    head: Fluids.sample(1n, 3n, 2n, 0),
    tail: {
      $: "Con",
      head: Fluids.sample(3n, 3n, 2n, 0),
      tail: {
        $: "Con",
        head: Fluids.sample(2n, 3n, 1n, 0),
        tail: { $: "Con", head: Fluids.sample(2n, 3n, 3n, 0), tail: { $: "Nil" } },
      },
    },
  },
};
const fluidState = Fluids.seed(Fluids.empty(), 2n, 3n, 2n, 3);
const advanced = Simulation.tick_with_fluids(state, 1n, water, fluidState, fluidSamples);
assert.equal(advanced.$, "Tick");
assert.equal(Number(Simulation.tick_time(advanced)), Number(Simulation.time(state)) + 1);
assert.equal(listLength(Fluids.state_flows(Simulation.tick_fluids(advanced))), 5);
console.log("bend simulation ok");
