import assert from "node:assert/strict";
import { entityShadow, shadowRadius } from "../web/entity-shadow.js";

assert.equal(shadowRadius({ kind: 2 }), 0.34);
assert.equal(shadowRadius({ kind: 1 }), 0.42);
assert.equal(shadowRadius({ profession: 1 }), 0.36);
assert.equal(shadowRadius({ item: 12 }), 0.18);

const shadow = entityShadow({ x: 4.5, y: 8, z: -2.5 }, 0.4);
assert.equal(shadow.positions.length, 18);
assert.equal(shadow.positions[1], 8.012);
assert.equal(shadow.positions[0], 4.1);
assert.equal(shadow.positions[3], 4.9);
assert.equal(shadow.radius, 0.4);
assert.equal(shadow.alpha, 0.24);
assert.deepEqual(
  entityShadow({ x: 4.5, y: 8, z: -2.5 }, 0.4),
  entityShadow({ x: 4.5, y: 8, z: -2.5 }, 0.4),
);

console.log("entity shadows ok");
