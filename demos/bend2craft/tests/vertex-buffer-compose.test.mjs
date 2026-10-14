import assert from "node:assert/strict";
import { concatFloat32Arrays } from "../web/vertex-buffer-compose.js";

const result = concatFloat32Arrays(
  Float32Array.of(1, 2),
  [3, 4, 5],
  new Float32Array(),
);
assert.ok(result instanceof Float32Array);
assert.deepEqual(Array.from(result), [1, 2, 3, 4, 5]);
assert.equal(concatFloat32Arrays().length, 0);
assert.throws(() => concatFloat32Arrays(null), TypeError);
console.log("vertex buffer compose ok");
