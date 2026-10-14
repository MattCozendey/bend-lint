import assert from "node:assert/strict";
import { Farmland, Crops } from "../web/bend-modules.js";

let state = Farmland.empty();
const added = Farmland.add(state, 4n, 8n, 4n);
assert.equal(added.ok, true);
state = added.state;
assert.equal(Number(Farmland.moisture_at(state, 4n, 8n, 4n)), 0);

const water = {
  $: "Con",
  head: { $: "Water", x: 7n, z: 4n },
  tail: { $: "Nil" },
};
state = Farmland.tick(state, water);
assert.equal(Number(Farmland.moisture_at(state, 4n, 8n, 4n)), 7);
state = Farmland.tick(state, { $: "Nil" });
assert.equal(Number(Farmland.moisture_at(state, 4n, 8n, 4n)), 6);

let crops = Crops.empty();
const planted = Crops.plant(crops, 4n, 9n, 4n, 20, 0);
assert.equal(planted.ok, true);
crops = Crops.tick_with_farmland(planted.state, 4n, state);
assert.equal(Number(Crops.crop_block(Crops.entries(crops).head)), 17);

console.log("bend farmland ok");
