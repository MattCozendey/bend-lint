import assert from "node:assert/strict";
import { createWorkerScheduler } from "../web/worker-scheduler.js";

const scheduler = createWorkerScheduler(2);
assert.deepEqual(
  [scheduler.next(), scheduler.next(), scheduler.next(), scheduler.next(), scheduler.next()],
  [0, 1, 0, 1, 0],
);
assert.equal(scheduler.size, 2);
assert.throws(() => createWorkerScheduler(0), /positive integer/);
assert.throws(() => createWorkerScheduler(1.5), /positive integer/);
console.log("worker scheduler ok");
