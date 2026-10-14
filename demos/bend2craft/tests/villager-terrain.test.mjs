import assert from "node:assert/strict";
import { villagerEditsChanged } from "../web/villager-simulation.js";

assert.equal(villagerEditsChanged([]), false);
assert.equal(villagerEditsChanged([{ x: 1, y: 2, z: 3 }]), true);
console.log("villager terrain policy ok");
