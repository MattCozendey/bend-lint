import assert from "node:assert/strict";
import Crops from "../world/crops.bend";

let state = Crops.empty();
const planted = Crops.plant(state, 4n, 9n, 4n, 20, 0);
assert.equal(planted.ok, true);
state = planted.state;
assert.equal(Number(Crops.crop_block(Crops.entries(state).head)), 16);
for (let tick = 0; tick < 12; tick += 1) state = Crops.tick(state, 1n);
assert.equal(Number(Crops.crop_block(Crops.entries(state).head)), 19);
const harvested = Crops.harvest(state, 4n, 9n, 4n);
assert.equal(harvested.ok, true);
assert.equal(Number(harvested.seeds), 1);
assert.equal(Number(harvested.wheat), 1);
assert.equal(Crops.entries(harvested.state).$, "Nil");
assert.equal(Crops.plant(state, 4n, 9n, 4n, 1, 0).ok, false);
console.log("bend crops ok");
