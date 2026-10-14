import assert from "node:assert/strict";
import { createMeshRebuildScheduler } from "../web/mesh-rebuild-scheduler.js";

const callbacks = [];
let rebuilds = 0;
const scheduler = createMeshRebuildScheduler(
  () => { rebuilds += 1; },
  (callback) => callbacks.push(callback),
);

assert.equal(scheduler.request(), true);
assert.equal(scheduler.request(), false);
assert.equal(scheduler.pending, true);
assert.equal(scheduler.requestCount, 2);
assert.equal(scheduler.runCount, 0);
assert.equal(callbacks.length, 1);

callbacks.shift()();
assert.equal(rebuilds, 1);
assert.equal(scheduler.pending, false);
assert.equal(scheduler.runCount, 1);
assert.equal(scheduler.request(), true);
callbacks.shift()();
assert.equal(rebuilds, 2);
assert.equal(scheduler.runCount, 2);
console.log("mesh rebuild scheduler ok");
