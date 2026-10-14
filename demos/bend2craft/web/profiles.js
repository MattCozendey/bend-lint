// Player profiles and per-profile worlds.
// Pure logic over an injected key/value store (localStorage in production,
// an in-memory map in tests). Saves are namespaced per profile and seed so
// players sharing one machine never overwrite each other.
import { seedFromSearch, seedLabel } from "./seed.js";
import { DEFAULT_WORLD_MODE, normalizeWorldMode } from "./settings.js";

export const PROFILES_KEY = "bend2craft-profiles";
export const PROFILES_VERSION = 1;
export const MAX_PROFILE_NAME = 24;
export const MAX_WORLD_NAME = 32;
export const MAX_SEED_TEXT = 64;

function now() {
  return Date.now();
}

function makeId(prefix) {
  return `${prefix}-${now().toString(36)}-${Math.floor(Math.random() * 0xffff).toString(36)}`;
}

function cleanName(name, max) {
  return String(name ?? "").trim().slice(0, max);
}

export function emptyProfilesDoc() {
  return { version: PROFILES_VERSION, activeProfileId: null, profiles: [] };
}

export function loadProfilesDoc(store) {
  try {
    const raw = store.getItem(PROFILES_KEY);
    if (!raw) return emptyProfilesDoc();
    const parsed = JSON.parse(raw);
    if (parsed === null || typeof parsed !== "object" || !Array.isArray(parsed.profiles)) {
      return emptyProfilesDoc();
    }
    const profiles = parsed.profiles
      .filter((profile) => profile !== null && typeof profile === "object" && typeof profile.id === "string")
      .map((profile) => ({
        id: profile.id,
        name: typeof profile.name === "string" && profile.name.trim() !== "" ? profile.name : "Player",
        createdAt: Number(profile.createdAt) || 0,
        lastPlayed: Number(profile.lastPlayed) || 0,
        worlds: Array.isArray(profile.worlds)
          ? profile.worlds
            .filter((world) => world !== null && typeof world === "object" && typeof world.id === "string")
            .map((world) => ({
              id: world.id,
              name: typeof world.name === "string" && world.name.trim() !== "" ? world.name : "World",
              seedText: typeof world.seedText === "string" ? world.seedText : "",
              seed: typeof world.seed === "string" && world.seed !== "" ? world.seed : seedLabel(seedFromSearch(`?seed=${encodeURIComponent(typeof world.seedText === "string" ? world.seedText : "")}`)),
              mode: normalizeWorldMode(world.mode ?? DEFAULT_WORLD_MODE),
              createdAt: Number(world.createdAt) || 0,
              lastPlayed: Number(world.lastPlayed) || 0,
            }))
          : [],
      }));
    const activeProfileId = typeof parsed.activeProfileId === "string"
      && profiles.some((profile) => profile.id === parsed.activeProfileId)
      ? parsed.activeProfileId
      : null;
    return { version: PROFILES_VERSION, activeProfileId, profiles };
  } catch {
    return emptyProfilesDoc();
  }
}

export function saveProfilesDoc(store, doc) {
  try {
    store.setItem(PROFILES_KEY, JSON.stringify(doc));
    return true;
  } catch {
    return false;
  }
}

export function getProfile(doc, profileId) {
  return doc.profiles.find((profile) => profile.id === profileId) ?? null;
}

export function getActiveProfile(doc) {
  if (doc.activeProfileId === null) return null;
  return getProfile(doc, doc.activeProfileId);
}

export function createProfile(doc, name) {
  const clean = cleanName(name, MAX_PROFILE_NAME);
  if (clean === "") return { ok: false, error: "Player name is missing." };
  const profile = {
    id: makeId("p"),
    name: clean,
    createdAt: now(),
    lastPlayed: 0,
    worlds: [],
  };
  const next = {
    ...doc,
    activeProfileId: profile.id,
    profiles: [...doc.profiles, profile],
  };
  return { ok: true, doc: next, profile };
}

export function deleteProfile(doc, profileId) {
  const profiles = doc.profiles.filter((profile) => profile.id !== profileId);
  return {
    ...doc,
    activeProfileId: doc.activeProfileId === profileId ? null : doc.activeProfileId,
    profiles,
  };
}

export function touchProfile(doc, profileId) {
  const timestamp = now();
  return {
    ...doc,
    activeProfileId: profileId,
    profiles: doc.profiles.map((profile) => profile.id === profileId
      ? { ...profile, lastPlayed: timestamp }
      : profile),
  };
}

export function getWorld(doc, profileId, worldId) {
  return getProfile(doc, profileId)?.worlds.find((world) => world.id === worldId) ?? null;
}

export function createWorld(doc, profileId, { name = "", seedText = "", mode = DEFAULT_WORLD_MODE } = {}) {
  const profile = getProfile(doc, profileId);
  if (profile === null) return { ok: false, error: "Player is missing." };
  const clean = cleanName(name, MAX_WORLD_NAME);
  if (clean === "") return { ok: false, error: "World name is missing." };
  if (typeof seedText !== "string") return { ok: false, error: "Seed must be text." };
  const text = seedText.trim().slice(0, MAX_SEED_TEXT) || String(Math.floor(Math.random() * 1000000));
  const world = {
    id: makeId("w"),
    name: clean,
    seedText: text,
    seed: seedLabel(seedFromSearch(`?seed=${encodeURIComponent(text)}`)),
    mode: normalizeWorldMode(mode),
    createdAt: now(),
    lastPlayed: 0,
  };
  const next = {
    ...doc,
    profiles: doc.profiles.map((entry) => entry.id === profileId
      ? { ...entry, worlds: [...entry.worlds, world] }
      : entry),
  };
  return { ok: true, doc: next, world };
}

export function deleteWorld(doc, profileId, worldId) {
  return {
    ...doc,
    profiles: doc.profiles.map((profile) => profile.id === profileId
      ? { ...profile, worlds: profile.worlds.filter((world) => world.id !== worldId) }
      : profile),
  };
}

export function touchWorld(doc, profileId, worldId) {
  const timestamp = now();
  return {
    ...doc,
    profiles: doc.profiles.map((profile) => {
      if (profile.id !== profileId) return profile;
      return {
        ...profile,
        lastPlayed: timestamp,
        worlds: profile.worlds.map((world) => world.id === worldId
          ? { ...world, lastPlayed: timestamp }
          : world),
      };
    }),
  };
}

/** Namespaced save slot for one player in one seed-labeled world. */
export function saveKeyFor(profileId, seedLabel) {
  return `bend2craft-save-${profileId}-${seedLabel}`;
}

/** Legacy single-slot key, kept for one-time migration. */
export function legacySaveKeyFor(seedLabel) {
  return `bend2craft-save-${seedLabel}`;
}

/**
 * Adopt a pre-profiles save into the current slot. Returns the raw save
 * string (or null) so the caller can decode it with the usual pipeline.
 * The legacy slot is removed after a successful read.
 */
export function migrateLegacySave(store, profileId, seedLabel) {
  const next = saveKeyFor(profileId, seedLabel);
  try {
    if (store.getItem(next) !== null) return null;
    const legacyKey = legacySaveKeyFor(seedLabel);
    const raw = store.getItem(legacyKey);
    if (raw === null) return null;
    store.setItem(next, raw);
    store.removeItem(legacyKey);
    return raw;
  } catch {
    return null;
  }
}
