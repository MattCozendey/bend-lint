import assert from "node:assert/strict";
import { createFixedTicker } from "../web/simulation-ticker.js";

const steps = [];
const ticker = createFixedTicker(0.2, (dt) => steps.push(dt));
assert.equal(ticker.advance(0.05), 0);
assert.equal(ticker.advance(0.15), 1);
assert.equal(ticker.advance(0.65), 3);
assert.deepEqual(steps, [0.2, 0.2, 0.2, 0.2]);
assert.ok(ticker.remainder() >= 0 && ticker.remainder() < 0.2);
ticker.reset();
assert.equal(ticker.remainder(), 0);
console.log("simulation ticker ok");
