import assert from "node:assert/strict";
import { createSourceFieldCache, packChunkCells } from "../web/chunk-worker-core.js";

// packChunkCells keeps only the chunk's cells and narrows them to bytes.
const bendArray = Array.from({ length: 16 }, (_, index) => index * 3);
const packed = packChunkCells(bendArray, 10);
assert.ok(packed instanceof Uint8Array);
assert.equal(packed.length, 10);
assert.deepEqual([...packed], [0, 3, 6, 9, 12, 15, 18, 21, 24, 27]);
assert.throws(() => packChunkCells(bendArray, 17), RangeError);
assert.throws(() => packChunkCells(null, 1), TypeError);

// The field cache floods each source once and appends in list order.
const list = (...items) => items.reduceRight((tail, head) => ({ $: "Con", head, tail }), { $: "Nil" });
const toArray = (node) => {
  const out = [];
  for (; node.$ === "Con"; node = node.tail) out.push(node.head);
  return out;
};
let floods = 0;
const cache = createSourceFieldCache({
  flood: (source, seed) => {
    floods += 1;
    return list(`${seed}:${source.x}:a`, `${seed}:${source.x}:b`);
  },
  append: (fields, tail) => {
    const items = toArray(fields);
    return items.reduceRight((acc, head) => ({ $: "Con", head, tail: acc }), tail);
  },
  limit: 2,
});
const a = { $: "Edit", x: 1n, y: 2n, z: 3n, block: 12 };
const b = { $: "Edit", x: 4n, y: 2n, z: 3n, block: 12 };
const c = { $: "Edit", x: 7n, y: 2n, z: 3n, block: 21 };
assert.deepEqual(toArray(cache.fieldsFor(list(a, b), 9n)), ["9:1:a", "9:1:b", "9:4:a", "9:4:b"]);
assert.equal(floods, 2);
assert.deepEqual(toArray(cache.fieldsFor(list(b, a), 9n)), ["9:4:a", "9:4:b", "9:1:a", "9:1:b"]);
assert.equal(floods, 2, "cached sources must not flood again");
// A different seed is a different flood.
cache.fieldsFor(list(a), 10n);
assert.equal(floods, 3);
// The cache is bounded and evicts the least recently used source.
assert.equal(cache.size, 2);
cache.fieldsFor(list(c), 9n);
assert.equal(cache.size, 2);
assert.deepEqual(toArray(cache.fieldsFor({ $: "Nil" }, 9n)), []);

console.log("chunk worker core ok");
