// The one mob roster the browser reads, kept next to the models it describes so
// a kind cannot be drawn, hit or heard as something it is not.
//
// `world/entities.bend` owns the rules: which kinds hunt, which burn in the sun,
// what they drop. This file owns the presentation: how tall each body is, what
// colour its death puff is, what it sounds like when struck. The two are two
// layers of one list, so `tests/mob-models.test.mjs` cross-checks `animal` and
// the roster length against the Bend definitions instead of trusting them to
// stay in step. A new kind added to one without the other fails that test.
//
// Deliberately dependency-free, like `aim.js`, so the hitbox and the model can
// share it without dragging the texture atlas into a headless test.

// kind must match `kind_is_animal` in `world/entities.bend`; `height` is the
// aimed hitbox, and `tests/mob-models.test.mjs` checks each model is at least
// that tall so a shot cannot pass over a body the player can see.
export const MOB_KINDS = Object.freeze([
  Object.freeze({ kind: 1, id: "pig", animal: true, height: 1.2, hurt: "oink", puff: Object.freeze([0.94, 0.72, 0.74]) }),
  Object.freeze({ kind: 2, id: "zombie", animal: false, height: 1.9, hurt: "groan", puff: Object.freeze([0.42, 0.62, 0.36]) }),
  Object.freeze({ kind: 3, id: "sheep", animal: true, height: 1.3, hurt: "baa", puff: Object.freeze([0.96, 0.94, 0.9]) }),
  Object.freeze({ kind: 4, id: "brute", animal: false, height: 1.9, hurt: "groan", puff: Object.freeze([0.3, 0.44, 0.3]) }),
  Object.freeze({ kind: 5, id: "cow", animal: true, height: 1.4, hurt: "moo", puff: Object.freeze([0.55, 0.4, 0.26]) }),
  Object.freeze({ kind: 6, id: "chicken", animal: true, height: 0.8, hurt: "cluck", puff: Object.freeze([0.95, 0.93, 0.88]) }),
]);

/** How many kinds `world/entities.bend` spawns from. */
export const MOB_ROSTER_LENGTH = 6;

const BY_KIND = new Map(MOB_KINDS.map((entry) => [entry.kind, entry]));

/** The roster entry for a kind, or null for anything the roster does not know. */
export function mobKind(kind) {
  return BY_KIND.get(Number(kind)) ?? null;
}

/** True for a kind that hunts the player. An unknown kind is not a monster. */
export function isHostileKind(kind) {
  const entry = mobKind(kind);
  return entry !== null && !entry.animal;
}

/** The aimed hitbox height of a kind, falling back to the tallest body. */
export function mobHeight(kind) {
  const entry = mobKind(kind);
  return entry === null ? 1.9 : entry.height;
}
