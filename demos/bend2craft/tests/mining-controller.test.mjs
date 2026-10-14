import assert from "node:assert/strict";
import { createMiningState, miningStateMatches } from "../web/mining-controller.js";

const state = createMiningState({
  x: 4,
  y: 5,
  z: 6,
  block: 1,
  slot: 2,
  item: "stone_pickaxe",
  duration: 0.8,
  startedAt: 100,
});
assert.deepEqual(state, {
  x: 4,
  y: 5,
  z: 6,
  block: 1,
  slot: 2,
  item: "stone_pickaxe",
  duration: 0.8,
  startedAt: 100,
});
assert.equal(miningStateMatches(state, { hit: [4, 5, 6] }, () => 1, 2, "stone_pickaxe"), true);
assert.equal(miningStateMatches(state, { hit: [4, 5, 7] }, () => 1, 2, "stone_pickaxe"), false);
assert.equal(miningStateMatches(state, { hit: [4, 5, 6] }, () => 2, 2, "stone_pickaxe"), false);
assert.equal(miningStateMatches(state, { hit: [4, 5, 6] }, () => 1, 1, "stone_pickaxe"), false);
assert.equal(miningStateMatches(null, { hit: [4, 5, 6] }, () => 1, 2, "stone_pickaxe"), false);

console.log("mining controller ok");
