import assert from "node:assert/strict";
import { createPointerLockController } from "../web/pointer-lock.js";

let requests = 0;
let rejectRequest;
const controller = createPointerLockController(
  () => false,
  () => {
    requests += 1;
    return new Promise((resolve, reject) => {
      rejectRequest = reject;
    });
  },
);

assert.equal(controller.request(), true);
assert.equal(controller.request(), false);
assert.equal(requests, 1);
rejectRequest(new Error("pointer lock cooldown"));
await Promise.resolve();
assert.equal(controller.request(), true);
assert.equal(requests, 2);
console.log("pointer lock ok");
