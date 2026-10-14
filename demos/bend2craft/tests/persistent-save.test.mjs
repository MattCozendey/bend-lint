import assert from "node:assert/strict";
import {
  clearTransactional,
  loadTransactional,
  saveTransactional,
} from "../web/persistent-save.js";

function memoryStore(entries = {}) {
  const data = new Map(Object.entries(entries));
  return {
    getItem: (key) => (data.has(key) ? data.get(key) : null),
    setItem: (key, value) => { data.set(key, String(value)); },
    removeItem: (key) => { data.delete(key); },
    has: (key) => data.has(key),
    corrupt: (key) => { data.set(key, "not-json"); },
  };
}

const store = memoryStore();
assert.deepEqual(saveTransactional(store, "save", { edits: 1, seed: 1337n }), { revision: 1, slot: 0 });
assert.deepEqual(loadTransactional(store, "save"), { revision: 1, value: { edits: 1, seed: 1337n } });
assert.deepEqual(saveTransactional(store, "save", { edits: 2 }), { revision: 2, slot: 1 });
assert.deepEqual(loadTransactional(store, "save"), { revision: 2, value: { edits: 2 } });

// A torn metadata write still recovers the highest valid slot.
store.setItem("save-txn-meta", "not-json");
assert.deepEqual(loadTransactional(store, "save"), { revision: 2, value: { edits: 2 } });

// A corrupted newest slot falls back to the previous committed snapshot.
store.corrupt("save-txn-1");
assert.deepEqual(loadTransactional(store, "save"), { revision: 1, value: { edits: 1, seed: 1337n } });

clearTransactional(store, "save");
assert.equal(loadTransactional(store, "save"), null);
assert.equal(store.has("save"), false);
assert.equal(store.has("save-txn-0"), false);
assert.equal(store.has("save-txn-1"), false);
assert.equal(store.has("save-txn-meta"), false);
console.log("persistent save ok");
