import assert from "node:assert/strict";
import { createColumnHeightCache } from "../web/drop-ground-cache.js";

const blocks = new Map([["2,0,2", 1], ["4,0,4", 1]]);
let reads = 0;
const cache = createColumnHeightCache({
  maxY: 4,
  blockAt(x, y, z) {
    reads += 1;
    return blocks.get(`${x},${y},${z}`) ?? 0;
  },
  isSolid: (block) => block !== 0,
});
assert.equal(cache.get(2, 2), 1);
const firstReads = reads;
assert.equal(cache.get(2, 2), 1);
assert.equal(reads, firstReads);
assert.equal(cache.get(4, 4), 1);
assert.equal(cache.stats().hits, 1);
assert.equal(cache.stats().misses, 2);
cache.invalidate(2, 2);
assert.equal(cache.get(2, 2), 1);
assert.equal(cache.stats().misses, 3);
cache.clear();
assert.equal(cache.stats().size, 0);
console.log("drop ground cache ok");
