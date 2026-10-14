import assert from "node:assert/strict";
import {
  createProfile,
  createWorld,
  deleteProfile,
  deleteWorld,
  emptyProfilesDoc,
  getActiveProfile,
  getWorld,
  legacySaveKeyFor,
  loadProfilesDoc,
  migrateLegacySave,
  saveKeyFor,
  saveProfilesDoc,
  touchProfile,
  touchWorld,
} from "../web/profiles.js";
import { seedLabel, seedFromSearch } from "../web/seed.js";

function memoryStore(entries = {}) {
  const data = new Map(Object.entries(entries));
  return {
    getItem: (key) => (data.has(key) ? data.get(key) : null),
    setItem: (key, value) => { data.set(key, String(value)); },
    removeItem: (key) => { data.delete(key); },
    has: (key) => data.has(key),
  };
}

const empty = loadProfilesDoc(memoryStore());
assert.deepEqual(empty, { version: 1, activeProfileId: null, profiles: [] });
assert.equal(getActiveProfile(empty), null);

const badName = createProfile(empty, "   ");
assert.equal(badName.ok, false);

const created = createProfile(empty, "  Alex  ");
assert.equal(created.ok, true);
assert.equal(created.profile.name, "Alex");
assert.equal(getActiveProfile(created.doc).id, created.profile.id);
assert.ok(saveProfilesDoc(memoryStore(), created.doc));

const second = createProfile(created.doc, "Sam");
assert.equal(second.doc.profiles.length, 2);
assert.notEqual(second.profile.id, created.profile.id);

const touched = touchProfile(second.doc, created.profile.id);
assert.equal(getActiveProfile(touched).id, created.profile.id);

const noWorld = createWorld(touched, created.profile.id, { name: "  " });
assert.equal(noWorld.ok, false);

const mine = createWorld(touched, created.profile.id, { name: "Home", seedText: "forest" });
assert.equal(mine.ok, true);
assert.equal(mine.world.name, "Home");
assert.equal(mine.world.seedText, "forest");
assert.equal(mine.world.mode, "survival");
assert.equal(mine.world.seed, seedLabel(seedFromSearch("?seed=forest")));
assert.equal(getWorld(mine.doc, created.profile.id, mine.world.id).seedText, "forest");

const peaceful = createWorld(touched, created.profile.id, { name: "Lab", seedText: "forest", mode: "peaceful" });
assert.equal(peaceful.ok, true);
assert.equal(peaceful.world.mode, "peaceful");

const random = createWorld(touched, created.profile.id, { name: "Wilds", seedText: "   " });
assert.equal(random.ok, true);
assert.ok(/^\d+$/.test(random.world.seedText));
assert.equal(random.world.seed, seedLabel(seedFromSearch(`?seed=${random.world.seedText}`)));

const played = touchWorld(mine.doc, created.profile.id, mine.world.id);
assert.ok(getWorld(played, created.profile.id, mine.world.id).lastPlayed > 0);

const removedWorld = deleteWorld(played, created.profile.id, mine.world.id);
assert.equal(getWorld(removedWorld, created.profile.id, mine.world.id), null);

const removed = deleteProfile(removedWorld, created.profile.id);
assert.equal(removed.profiles.length, 1);
assert.equal(getActiveProfile(removed), null);

const reloaded = loadProfilesDoc(memoryStore({ "bend2craft-profiles": JSON.stringify(removed) }));
assert.equal(reloaded.profiles.length, 1);
assert.deepEqual(loadProfilesDoc(memoryStore({ "bend2craft-profiles": "nope{" })), emptyProfilesDoc());
const legacyWorldDoc = loadProfilesDoc(memoryStore({ "bend2craft-profiles": JSON.stringify({ profiles: [{ id: "p", name: "Player", worlds: [{ id: "w", name: "Old", seedText: "1337" }] }] }) }));
assert.equal(legacyWorldDoc.profiles[0].worlds[0].mode, "survival");

assert.equal(saveKeyFor("p-abc", "1337"), "bend2craft-save-p-abc-1337");
assert.equal(legacySaveKeyFor("1337"), "bend2craft-save-1337");

const legacy = memoryStore({ "bend2craft-save-1337": "{\"version\":1}" });
assert.equal(migrateLegacySave(legacy, "p-abc", "1337"), "{\"version\":1}");
assert.equal(legacy.getItem("bend2craft-save-p-abc-1337"), "{\"version\":1}");
assert.equal(legacy.has("bend2craft-save-1337"), false);
assert.equal(migrateLegacySave(legacy, "p-abc", "1337"), null);
console.log("profiles ok");
