import assert from "node:assert/strict";
import { bendList, listLength, listValues } from "../web/bend-list.js";

// This module encodes the shape the compiled Bend runtime links against, so the
// assertions below are about the exact tag names and the tail link, not about
// behaviour a future refactor could reasonably change.

assert.deepEqual(bendList([]), { $: "Nil" });
assert.deepEqual(bendList([1]), { $: "Con", head: 1, tail: { $: "Nil" } });
assert.deepEqual(bendList([1, 2]), {
  $: "Con",
  head: 1,
  tail: { $: "Con", head: 2, tail: { $: "Nil" } },
});

// Order must survive the fold in both directions, or a Bend function would
// consume its arguments reversed while every caller believed the order held.
assert.deepEqual(listValues(bendList([1, 2, 3])), [1, 2, 3]);
assert.deepEqual(listValues(bendList(["a", "b"])), ["a", "b"]);
assert.deepEqual(listValues({ $: "Nil" }), []);
assert.equal(listLength(bendList([1, 2, 3])), 3);
assert.equal(listLength({ $: "Nil" }), 0);

assert.deepEqual(bendList(listValues(bendList([7, 8, 9]))), bendList([7, 8, 9]));
assert.deepEqual(bendList([null, undefined]), { $: "Con", head: null, tail: { $: "Con", head: undefined, tail: { $: "Nil" } } });

console.log("bend list ok");
