import assert from "node:assert/strict";
import Furnace from "../world/furnace.bend";

let furnace = Furnace.empty();
assert.equal(Number(furnace.input), 0);
assert.equal(Number(furnace.output_count), 0);
assert.equal(Furnace.load_input(furnace, 1, 1n).ok, false);
assert.equal(Furnace.load_fuel(furnace, 15, 1n).ok, false);

let loaded = Furnace.load_input(furnace, 15, 2n);
assert.equal(loaded.ok, true);
furnace = loaded.furnace;
loaded = Furnace.load_fuel(furnace, 14, 1n);
assert.equal(loaded.ok, true);
furnace = loaded.furnace;

let idle = Furnace.tick(Furnace.empty());
assert.equal(idle.ok, false);
assert.equal(idle.produced, false);

let produced = false;
for (let index = 0; index < 8; index += 1) {
  const step = Furnace.tick(furnace);
  assert.equal(step.ok, true);
  produced = produced || step.produced;
  furnace = step.furnace;
}
assert.equal(produced, true);
assert.equal(Number(furnace.input), 15);
assert.equal(Number(furnace.input_count), 1);
assert.equal(Number(furnace.output), 20);
assert.equal(Number(furnace.output_count), 1);

const extracted = Furnace.take_output(furnace);
assert.equal(extracted.ok, true);
assert.equal(Number(extracted.item), 20);
assert.equal(Number(extracted.amount), 1);
assert.equal(Number(extracted.furnace.output_count), 0);

let breadFurnace = Furnace.load_input(Furnace.empty(), 26, 1n);
assert.equal(breadFurnace.ok, true);
breadFurnace = Furnace.load_fuel(breadFurnace.furnace, 14, 1n);
assert.equal(breadFurnace.ok, true);
for (let index = 0; index < 8; index += 1) breadFurnace = Furnace.tick(breadFurnace.furnace);
assert.equal(Number(breadFurnace.furnace.output), 41);
console.log("bend furnace ok");
