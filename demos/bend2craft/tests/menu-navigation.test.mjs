import assert from "node:assert/strict";
import { continueTarget } from "../web/menu-navigation.js";

assert.equal(continueTarget({ activeProfileId: null, profiles: [] }), null);

const profiles = [
  {
    id: "p-sam",
    lastPlayed: 80,
    worlds: [
      { id: "w-old", lastPlayed: 30 },
      { id: "w-new", lastPlayed: 70 },
    ],
  },
  {
    id: "p-alex",
    lastPlayed: 10,
    worlds: [{ id: "w-other", lastPlayed: 100 }],
  },
];

assert.deepEqual(continueTarget({ activeProfileId: "p-sam", profiles }), {
  profileId: "p-sam",
  worldId: "w-new",
});

assert.deepEqual(continueTarget({ activeProfileId: "p-sam", profiles: [profiles[0]] }), {
  profileId: "p-sam",
  worldId: "w-new",
});

assert.equal(continueTarget({ activeProfileId: "missing", profiles }), null);

console.log("menu navigation ok");
