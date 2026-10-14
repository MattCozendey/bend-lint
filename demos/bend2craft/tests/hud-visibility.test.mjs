import assert from "node:assert/strict";
import { furnaceControlHidden } from "../web/hud-visibility.js";

assert.equal(furnaceControlHidden(null, false), true);
assert.equal(furnaceControlHidden(null, true), false);
assert.equal(furnaceControlHidden([25, 9, 27], false), false);
assert.equal(furnaceControlHidden([25, 9, 27], true), false);

console.log("hud visibility ok");
