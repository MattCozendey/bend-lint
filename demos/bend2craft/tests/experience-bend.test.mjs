import assert from "node:assert/strict";
import XP from "../world/experience.bend";

const empty = XP.empty();
assert.equal(Number(XP.xp_level(empty)), 0);
assert.equal(Number(XP.xp_points(empty)), 0);
assert.equal(Number(XP.threshold(0)), 7);
assert.equal(Number(XP.threshold(3)), 13);
assert.equal(Number(XP.xp_for_kind(2)), 5);
assert.equal(Number(XP.xp_for_kind(1)), 2);

let state = XP.empty();
state = XP.award(state, 2);
assert.equal(Number(XP.xp_level(state)), 0);
assert.equal(Number(XP.xp_points(state)), 5);
state = XP.award(state, 2);
assert.equal(Number(XP.xp_level(state)), 1);
assert.equal(Number(XP.xp_points(state)), 3);
state = XP.add(state, 100);
assert.ok(Number(XP.xp_level(state)) > 1, "bulk XP must level up more than once");
assert.ok(Number(XP.xp_points(state)) < Number(XP.threshold(Number(XP.xp_level(state)))), "remainder must fit the next threshold");
console.log("bend experience ok");
