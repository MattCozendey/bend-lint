import assert from "node:assert/strict";
import {
  DEFAULT_SEED,
  SEED_MODULUS,
  seedFromSearch,
  seedLabel,
} from "../web/seed.js";

assert.equal(DEFAULT_SEED, 1337n);
assert.equal(seedFromSearch(""), 1337n);
assert.equal(seedFromSearch("?seed=42"), 42n);
assert.equal(seedFromSearch("?seed=-1"), SEED_MODULUS - 1n);
assert.equal(seedFromSearch("?seed=forest"), seedFromSearch("?seed=forest"));
assert.notEqual(seedFromSearch("?seed=forest"), seedFromSearch("?seed=desert"));
assert.equal(seedLabel(42n), "42");
console.log("seed input ok");
