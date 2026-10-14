import { decodeSave, encodeSave } from "./save-state.js";

const SLOT_COUNT = 2;
const META_SUFFIX = "-txn-meta";
const SLOT_SUFFIX = "-txn-";

function slotKey(key, slot) {
  return `${key}${SLOT_SUFFIX}${slot}`;
}

function validRevision(value) {
  return Number.isSafeInteger(value) && value >= 1;
}

function readEnvelope(store, key, slot) {
  try {
    const parsed = decodeSave(store.getItem(slotKey(key, slot)));
    if (parsed?.$ !== "SaveTransaction" || !validRevision(Number(parsed.revision))) return null;
    if (!Object.prototype.hasOwnProperty.call(parsed, "payload")) return null;
    return { revision: Number(parsed.revision), slot, value: parsed.payload };
  } catch {
    return null;
  }
}

export function loadTransactional(store, key) {
  const candidates = [];
  for (let slot = 0; slot < SLOT_COUNT; slot += 1) {
    const envelope = readEnvelope(store, key, slot);
    if (envelope !== null) candidates.push(envelope);
  }
  if (candidates.length > 0) {
    candidates.sort((a, b) => b.revision - a.revision);
    const { revision, value } = candidates[0];
    return { revision, value };
  }

  // One-time compatibility with the pre-journal single-slot format.
  try {
    const value = decodeSave(store.getItem(key));
    return value === null ? null : { revision: 0, value };
  } catch {
    return null;
  }
}

export function saveTransactional(store, key, value) {
  const current = loadTransactional(store, key);
  const revision = (current?.revision ?? 0) + 1;
  const slot = ((revision + 1) % SLOT_COUNT);
  const envelope = encodeSave({ $: "SaveTransaction", revision, payload: value });
  try {
    // Write the snapshot before the pointer. Recovery scans both slots, so a
    // crash between these writes keeps the previous valid state available.
    store.setItem(slotKey(key, slot), envelope);
    store.setItem(`${key}${META_SUFFIX}`, JSON.stringify({ revision, slot }));
    try { store.removeItem(key); } catch { /* legacy cleanup is best-effort */ }
    return { revision, slot };
  } catch {
    return false;
  }
}

export function clearTransactional(store, key) {
  try {
    store.removeItem(key);
    store.removeItem(`${key}${META_SUFFIX}`);
    for (let slot = 0; slot < SLOT_COUNT; slot += 1) store.removeItem(slotKey(key, slot));
    return true;
  } catch {
    return false;
  }
}
