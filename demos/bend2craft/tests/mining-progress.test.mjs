import assert from "node:assert/strict";
import { miningProgress } from "../web/mining-progress.js";

assert.equal(miningProgress(null, 100), 0);
assert.equal(miningProgress({ startedAt: 100, duration: 2 }, 100), 0);
assert.equal(miningProgress({ startedAt: 100, duration: 2 }, 1100), 0.5);
assert.equal(miningProgress({ startedAt: 100, duration: 2 }, 2500), 1);
assert.equal(miningProgress({ startedAt: 100, duration: 0 }, 1100), 1);

console.log("mining progress ok");
