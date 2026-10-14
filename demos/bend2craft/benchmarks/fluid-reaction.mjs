import Fluids from "../world/fluids.bend";
import { bendList, listLength } from "../web/bend-list.js";

const sampleValues = [];
for (let x = 0; x < 24; x += 1) {
  for (let z = 0; z < 24; z += 1) sampleValues.push(Fluids.sample(BigInt(x), 3n, BigInt(z), 0));
}
const samples = bendList(sampleValues);
let state = Fluids.seed_lava(Fluids.empty(), 2n, 3n, 2n, 8);
for (let index = 0; index < 10; index += 1) state = Fluids.tick(state, samples);
const start = performance.now();
const reactions = Fluids.reactions(state, samples);
const elapsedMs = performance.now() - start;
console.log(JSON.stringify({ flows: listLength(Fluids.state_flows(state)), reactions: listLength(reactions), elapsedMs }));
