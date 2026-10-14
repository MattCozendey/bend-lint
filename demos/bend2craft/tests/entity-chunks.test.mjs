import assert from "node:assert/strict";
import { buildChunkBuckets, concatBendLists, chunkKey } from "../web/entity-chunks.js";

const entries = {
  $: "Con",
  head: { id: 1, x: 1.5, z: 2.5 },
  tail: {
    $: "Con",
    head: { id: 2, x: 17.5, z: 2.5 },
    tail: { $: "Nil" },
  },
};
const buckets = buildChunkBuckets(entries, 16, (entry) => ({ x: entry.x, z: entry.z }));
assert.equal(chunkKey(0, 0), "0,0");
assert.equal(chunkKey(1, 0), "1,0");
assert.equal(buckets.size, 2);
assert.equal(buckets.get("0,0").head.id, 1);
assert.equal(buckets.get("1,0").head.id, 2);
const merged = concatBendLists(buckets.get("0,0"), buckets.get("1,0"));
assert.equal(merged.head.id, 1);
assert.equal(merged.tail.head.id, 2);
console.log("entity chunks ok");
