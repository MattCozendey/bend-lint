import assert from "node:assert/strict";
import {
  audioVolumesFromOptions,
  createDefaultOptions,
  createWorldConfig,
  DEFAULT_CONTROLS,
  GRAPHICS_QUALITY_CHOICES,
  normalizeGraphicsQuality,
  DEFAULT_RENDERER,
  DEFAULT_RENDER_DISTANCE,
  DEFAULT_VOLUME_EFFECTS,
  DEFAULT_VOLUME_MASTER,
  DEFAULT_VOLUME_MUSIC,
  MAX_RENDER_DISTANCE,
  MIN_RENDER_DISTANCE,
  loadJson,
  loadOptions,
  randomSeedText,
  RENDERER_MODES,
  runtimeRendererMode,
  saveJson,
  saveOptions,
  sanitizeOptions,
  validateWorldConfig,
  WORLD_MODES,
  worldModeLabel,
  DEFAULT_LOD_DISTANCE,
  LOD_DISTANCE_CHOICES,
  normalizeLodDistance,
  DEFAULT_FPS_LIMIT,
  FPS_LIMIT_CHOICES,
  normalizeFpsLimit,
} from "../web/settings.js";
import { VISUAL_QUALITY_TIERS } from "../web/visual-quality.js";
import { createDefaultGraphicsEffects, graphicsEffectKeys } from "../web/graphics-effects.js";

function memoryStore(entries = {}) {
  const data = new Map(Object.entries(entries));
  return {
    getItem: (key) => (data.has(key) ? data.get(key) : null),
    setItem: (key, value) => { data.set(key, String(value)); },
  };
}

assert.equal(DEFAULT_RENDER_DISTANCE, 4);
assert.equal(MIN_RENDER_DISTANCE, 2);
assert.equal(MAX_RENDER_DISTANCE, 8);
assert.equal(DEFAULT_LOD_DISTANCE, 512);
assert.deepEqual(LOD_DISTANCE_CHOICES, [0, 256, 512, 1024, 2048]);
assert.equal(sanitizeOptions({ lodDistance: 0 }).lodDistance, 0, "distant terrain can be turned off");
assert.equal(sanitizeOptions({ lodDistance: 2048 }).lodDistance, 2048);
assert.equal(sanitizeOptions({ lodDistance: 700 }).lodDistance, DEFAULT_LOD_DISTANCE);
assert.equal(normalizeLodDistance("1024"), 1024);

// --- the frame rate cap -------------------------------------------------------
// The cap has to default to uncapped: a build that silently started rendering at
// 60 would look like a performance regression on a 120 Hz display, and the
// player never asked for it.
assert.equal(DEFAULT_FPS_LIMIT, 0, "the frame rate cap must default to uncapped");
assert.deepEqual([...FPS_LIMIT_CHOICES], [0, 30, 60, 120, 144, 240]);
assert.equal(createDefaultOptions().fpsLimit, 0);
assert.equal(sanitizeOptions({}).fpsLimit, 0);
// Every offered limit has to survive a round trip, or the menu would show a value
// that quietly reverts to uncapped the next time the panel is opened.
for (const limit of FPS_LIMIT_CHOICES) {
  assert.equal(normalizeFpsLimit(limit), limit);
  assert.equal(sanitizeOptions({ fpsLimit: limit }).fpsLimit, limit);
  assert.equal(saveOptions(memoryStore(), { ...createDefaultOptions(), fpsLimit: limit }), true);
}
const fpsStore = memoryStore();
assert.equal(saveOptions(fpsStore, { ...createDefaultOptions(), fpsLimit: 60 }), true);
assert.equal(loadOptions(fpsStore).fpsLimit, 60, "a chosen cap must survive a save/load round trip");
// A cap that is not on the menu is not a cap. Falling back to uncapped is the
// safe direction: it restores the pre-feature behaviour instead of pinning the
// game to a frame rate the player never chose.
for (const bad of [61, -30, 1e9, "fast", null, undefined, {}, []]) {
  assert.equal(
    normalizeFpsLimit(bad), 0,
    `a bad frame rate preference (${String(bad)}) must fall back to uncapped`,
  );
  assert.equal(sanitizeOptions({ fpsLimit: bad }).fpsLimit, 0);
}
// A document written before this option existed must load, and must not gain one.
assert.equal(loadOptions(memoryStore({ "bend2craft-options": '{"fov":90}' })).fpsLimit, 0);
assert.equal(DEFAULT_RENDERER, RENDERER_MODES.WEBGL);
assert.equal(runtimeRendererMode(RENDERER_MODES.AUTO), RENDERER_MODES.WEBGL);
assert.equal(runtimeRendererMode(RENDERER_MODES.WEBGPU), RENDERER_MODES.WEBGPU);
assert.equal(runtimeRendererMode(RENDERER_MODES.WEBGL), RENDERER_MODES.WEBGL);
assert.deepEqual(createDefaultOptions(), {
  fov: 75,
  sensitivity: 1,
  showCoords: true,
  renderDistance: 4,
  lodDistance: 512,
  renderer: "webgl",
  graphicsQuality: "auto",
  graphics: createDefaultGraphicsEffects(),
  fpsLimit: 0,
  volumeMaster: 0.7,
  volumeMusic: 0.7,
  volumeEffects: 0.9,
  controls: DEFAULT_CONTROLS,
});
assert.deepEqual(sanitizeOptions({ fov: 200, sensitivity: -1, renderDistance: 99 }), {
  fov: 110,
  sensitivity: 0.5,
  showCoords: true,
  renderDistance: 8,
  lodDistance: 512,
  renderer: "webgl",
  graphicsQuality: "auto",
  graphics: createDefaultGraphicsEffects(),
  fpsLimit: 0,
  volumeMaster: 0.7,
  volumeMusic: 0.7,
  volumeEffects: 0.9,
  controls: DEFAULT_CONTROLS,
});

// The per-effect amounts ride inside the options document rather than beside it,
// so a stored set survives a save/load round trip and a document written before
// the effects existed still loads with the shipped look.
assert.deepEqual(Object.keys(createDefaultOptions().graphics), graphicsEffectKeys(),
  "every effect has to be in the default document the menu writes");
assert.equal(sanitizeOptions({ graphics: { bloom: 0 } }).graphics.bloom, 0,
  "an effect the player switched off has to survive sanitising");
assert.equal(sanitizeOptions({ graphics: { bloom: 0 } }).graphics.godRays, createDefaultGraphicsEffects().godRays,
  "editing one effect must not reset the others");
assert.deepEqual(loadOptions(memoryStore({ "bend2craft-options": '{"fov":90}' })).graphics,
  createDefaultGraphicsEffects(),
  "a document from before the effects existed must load the shipped look");
const effectStore = memoryStore();
assert.equal(saveOptions(effectStore, { ...createDefaultOptions(), graphics: { ...createDefaultGraphicsEffects(), bloom: 200 } }), true);
assert.equal(loadOptions(effectStore).graphics.bloom, 200, "a chosen amount must survive a round trip");

// The graphics tier must only ever hold a name the runtime has a tier for, and
// a corrupted preference must fall back to `auto` rather than to a specific
// tier: pinning a tier also switches off the frame-time safety net.
assert.equal(GRAPHICS_QUALITY_CHOICES[0], "auto");
assert.deepEqual(GRAPHICS_QUALITY_CHOICES.slice(1), VISUAL_QUALITY_TIERS.map((tier) => tier.name));
for (const name of GRAPHICS_QUALITY_CHOICES) {
  assert.equal(normalizeGraphicsQuality(name), name);
  assert.equal(sanitizeOptions({ graphicsQuality: name }).graphicsQuality, name);
}
for (const bad of ["nope", "", 7, null, undefined, "ULTRA", [], {}]) {
  assert.equal(
    normalizeGraphicsQuality(bad),
    "auto",
    `a bad graphics preference (${String(bad)}) must fall back to auto`,
  );
  assert.equal(sanitizeOptions({ graphicsQuality: bad }).graphicsQuality, "auto");
}
// A stored pin must survive a round trip, or the player silently loses it.
const qualityStore = memoryStore();
assert.equal(saveOptions(qualityStore, { ...createDefaultOptions(), graphicsQuality: "ultra" }), true);
assert.equal(loadOptions(qualityStore).graphicsQuality, "ultra");
assert.deepEqual(sanitizeOptions({ fov: "wide" }), createDefaultOptions());
assert.deepEqual(loadOptions(memoryStore()), createDefaultOptions());
assert.deepEqual(loadOptions(memoryStore({ "bend2craft-options": "{\"fov\":90}" })), {
  fov: 90,
  sensitivity: 1,
  showCoords: true,
  renderDistance: 4,
  lodDistance: 512,
  renderer: "webgl",
  graphicsQuality: "auto",
  graphics: createDefaultGraphicsEffects(),
  fpsLimit: 0,
  volumeMaster: 0.7,
  volumeMusic: 0.7,
  volumeEffects: 0.9,
  controls: DEFAULT_CONTROLS,
});
assert.equal(sanitizeOptions({ renderDistance: MIN_RENDER_DISTANCE - 1 }).renderDistance, MIN_RENDER_DISTANCE);

const store = memoryStore();
assert.equal(saveOptions(store, {
  fov: 90,
  sensitivity: 2,
  showCoords: false,
  renderDistance: 6,
  renderer: RENDERER_MODES.WEBGPU,
  controls: DEFAULT_CONTROLS,
}), true);
assert.deepEqual(loadOptions(store), {
  fov: 90,
  sensitivity: 2,
  showCoords: false,
  renderDistance: 6,
  lodDistance: 512,
  renderer: "webgpu",
  graphicsQuality: "auto",
  graphics: createDefaultGraphicsEffects(),
  fpsLimit: 0,
  volumeMaster: 0.7,
  volumeMusic: 0.7,
  volumeEffects: 0.9,
  controls: DEFAULT_CONTROLS,
});
const rebound = sanitizeOptions({ controls: { drop: "KeyX", attack: "Mouse4" } });
assert.equal(rebound.controls.drop, "KeyX");
assert.equal(rebound.controls.attack, "Mouse4");
assert.equal(rebound.controls.inventory, DEFAULT_CONTROLS.inventory);

assert.deepEqual(createWorldConfig({ name: "  ", seedText: 42 }), { name: "New World", seedText: "42", mode: "survival" });
assert.deepEqual(createWorldConfig({ name: "Lab", seedText: "forest", mode: WORLD_MODES.PEACEFUL }), { name: "Lab", seedText: "forest", mode: "peaceful" });
assert.equal(worldModeLabel("peaceful"), "Peaceful");
assert.equal(worldModeLabel("unknown"), "Survival");
assert.deepEqual(validateWorldConfig(createWorldConfig({ name: "Home", seedText: "forest" })), []);
assert.ok(validateWorldConfig(null).length > 0);
assert.ok(/^\d+$/.test(randomSeedText()));
assert.deepEqual(loadJson(memoryStore(), "missing", { a: 1 }), { a: 1 });
assert.equal(saveJson(store, "key", { b: 2 }), true);
assert.deepEqual(loadJson(store, "key", null), { b: 2 });
console.log("settings ok");
