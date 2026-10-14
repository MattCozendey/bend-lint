import assert from "node:assert/strict";
import { decodeSave, encodeSave } from "../web/save-state.js";

const original = {
  edits: {
    $: "Con",
    head: { $: "Edit", x: 40n, y: 9n, z: 40n, block: 14 },
    tail: { $: "Nil" },
  },
  player: { x: 40.5, y: 9, z: 40.5 },
  furnaces: { $: "World", entries: { $: "Nil" } },
  crops: { $: "State", crops: { $: "Con", head: { $: "Crop", x: 34n, y: 8n, z: 34n, stage: 19, age: 0n }, tail: { $: "Nil" } } },
  farmland: { $: "State", plots: { $: "Con", head: { $: "Plot", x: 34n, y: 7n, z: 34n, moisture: 7 }, tail: { $: "Nil" } } },
  simulation: { $: "Simulation", time: 12n, chunks: { $: "Con", head: { $: "Chunk", x: 2n, z: 2n, ticks: 12n }, tail: { $: "Nil" } }, crops: { $: "State", crops: { $: "Nil" } }, farmland: { $: "State", plots: { $: "Nil" } } },
};
const encoded = encodeSave(original);
assert.equal(typeof encoded, "string");
const restored = decodeSave(encoded);
assert.deepEqual(restored, original);
assert.equal(typeof restored.edits.head.x, "bigint");
assert.equal(restored.edits.head.x, 40n);
assert.equal(restored.crops.crops.head.x, 34n);
assert.equal(restored.farmland.plots.head.moisture, 7);
assert.equal(restored.simulation.chunks.head.ticks, 12n);
assert.equal(decodeSave("not-json"), null);
console.log("save state ok");
