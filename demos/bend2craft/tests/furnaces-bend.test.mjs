import assert from "node:assert/strict";
import Furnace from "../world/furnace.bend";
import Furnaces from "../world/furnaces.bend";

let world = Furnaces.empty();
const first = Furnaces.add(world, 10n, 5n, 10n);
assert.equal(first.ok, true);
world = first.world;
const second = Furnaces.add(world, 20n, 5n, 20n);
assert.equal(second.ok, true);
world = second.world;
assert.equal(Furnaces.add(world, 10n, 5n, 10n).ok, false);

const firstLookup = Furnaces.at(world, 10n, 5n, 10n);
assert.equal(firstLookup.$, "FurnaceFound");
const loaded = Furnace.load_input(firstLookup.furnace, 15, 1n);
assert.equal(loaded.ok, true);
const fueled = Furnace.load_fuel(loaded.furnace, 14, 1n);
assert.equal(fueled.ok, true);
world = Furnaces.set(world, 10n, 5n, 10n, fueled.furnace);
for (let tick = 0; tick < 8; tick += 1) world = Furnaces.tick_world(world);
assert.equal(Number(Furnaces.at(world, 10n, 5n, 10n).furnace.output_count), 1);

const secondLookup = Furnaces.at(world, 20n, 5n, 20n);
assert.equal(secondLookup.$, "FurnaceFound");
assert.equal(Number(secondLookup.furnace.input_count), 0);
assert.equal(Number(Furnaces.at(world, 10n, 5n, 10n).furnace.input_count), 0);

const removed = Furnaces.remove(world, 10n, 5n, 10n);
assert.equal(removed.ok, true);
assert.equal(Furnaces.at(removed.world, 10n, 5n, 10n).$, "FurnaceMissing");
assert.equal(Furnaces.at(removed.world, 20n, 5n, 20n).$, "FurnaceFound");
console.log("bend furnace containers ok");
