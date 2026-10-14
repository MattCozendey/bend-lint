// Menu options and world creation settings.
// Pure and dependency-free; persistence is injected by the caller so the
// rules stay testable without a browser. Only options the game implements
// are exposed: field of view, mouse sensitivity, render distance, distant
// terrain, the coordinates readout, the renderer backend, the graphics
// quality tier and the per-effect graphics amounts.
import { normalizeRendererMode, RENDERER_MODES } from "./webgpu-capabilities.js";
import { VISUAL_QUALITY_TIERS } from "./visual-quality.js";
import { createDefaultGraphicsEffects, normalizeGraphicsEffects } from "./graphics-effects.js";
import { DEFAULT_FPS_LIMIT, normalizeFpsLimit } from "./frame-pacer.js";

export { RENDERER_MODES };
export { GRAPHICS_EFFECTS, createDefaultGraphicsEffects } from "./graphics-effects.js";

/** Tier names, cheapest first, with `auto` in front to leave adaptation on. */
export const GRAPHICS_QUALITY_CHOICES = Object.freeze([
  "auto",
  ...VISUAL_QUALITY_TIERS.map((tier) => tier.name),
]);
export const DEFAULT_GRAPHICS_QUALITY = "auto";
export const MIN_VOLUME = 0;
export const MAX_VOLUME = 1;
/** The mixer's own default was 0.18, which is far too quiet to be a menu default. */
export const DEFAULT_VOLUME_MASTER = 0.7;
export const DEFAULT_VOLUME_MUSIC = 0.7;
export const DEFAULT_VOLUME_EFFECTS = 0.9;

function clampVolume(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(MAX_VOLUME, Math.max(MIN_VOLUME, parsed));
}

/**
 * A stored value is either a tier name or `auto`. Anything else falls back to
 * `auto` rather than to a specific tier: a corrupted preference must not leave
 * the game pinned to a quality the player never asked for, which would also
 * disable the frame-time safety net.
 */
export function normalizeGraphicsQuality(value) {
  return GRAPHICS_QUALITY_CHOICES.includes(value) ? value : DEFAULT_GRAPHICS_QUALITY;
}

export function runtimeRendererMode(value) {
  const mode = normalizeRendererMode(value);
  return mode === RENDERER_MODES.AUTO ? RENDERER_MODES.WEBGL : mode;
}

export const OPTIONS_KEY = "bend2craft-options";
export const MIN_FOV = 60;
export const MAX_FOV = 110;
export const MIN_SENSITIVITY = 0.5;
export const MAX_SENSITIVITY = 3;
export const MIN_RENDER_DISTANCE = 2;
// Chunk generation runs through the U32 terrain core and the renderers keep one
// buffer per chunk, so a wider window no longer costs a whole-world rebuild.
export const MAX_RENDER_DISTANCE = 8;
export const DEFAULT_RENDER_DISTANCE = 4;
// Distant terrain (LOD rings past the streamed chunks), in blocks. 0 turns it off.
export const LOD_DISTANCE_CHOICES = Object.freeze([0, 256, 512, 1024, 2048]);
export const DEFAULT_LOD_DISTANCE = 512;

export function normalizeLodDistance(value) {
  const parsed = Number(value);
  return LOD_DISTANCE_CHOICES.includes(parsed) ? parsed : DEFAULT_LOD_DISTANCE;
}
// The frame rate cap, its choices and its default come from the pacer, which is
// the module that has to honour them. Re-exporting keeps one source of truth: a
// second copy of this list in the settings layer is how the menu ends up offering
// a limit the runtime does not implement.
export {
  DEFAULT_FPS_LIMIT,
  FPS_LIMIT_CHOICES,
  framePeriodMs,
  normalizeFpsLimit,
} from "./frame-pacer.js";
export const DEFAULT_RENDERER = RENDERER_MODES.WEBGL;
export const DEFAULT_CONTROLS = Object.freeze({
  sneak: "ShiftLeft",
  sprint: "ControlLeft",
  inventory: "KeyE",
  furnace: "KeyR",
  chest: "KeyC",
  eat: "KeyG",
  drop: "KeyQ",
  attack: "KeyF",
  trade: "KeyT",
  sleep: "KeyN",
});
export const DEFAULT_WORLD_NAME = "New World";
export const WORLD_MODES = Object.freeze({
  SURVIVAL: "survival",
  PEACEFUL: "peaceful",
});
export const DEFAULT_WORLD_MODE = WORLD_MODES.SURVIVAL;

export function normalizeWorldMode(value) {
  return value === WORLD_MODES.PEACEFUL ? WORLD_MODES.PEACEFUL : DEFAULT_WORLD_MODE;
}

export function worldModeLabel(value) {
  return normalizeWorldMode(value) === WORLD_MODES.PEACEFUL ? "Peaceful" : "Survival";
}

export function createDefaultOptions() {
  return {
    fov: 75,
    sensitivity: 1,
    showCoords: true,
    renderDistance: DEFAULT_RENDER_DISTANCE,
    lodDistance: DEFAULT_LOD_DISTANCE,
    renderer: DEFAULT_RENDERER,
    graphicsQuality: DEFAULT_GRAPHICS_QUALITY,
    graphics: createDefaultGraphicsEffects(),
    fpsLimit: DEFAULT_FPS_LIMIT,
    volumeMaster: DEFAULT_VOLUME_MASTER,
    volumeMusic: DEFAULT_VOLUME_MUSIC,
    volumeEffects: DEFAULT_VOLUME_EFFECTS,
    controls: { ...DEFAULT_CONTROLS },
  };
}

function clampNumber(value, min, max, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function clampInteger(value, min, max, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(parsed)));
}

export function sanitizeOptions(raw = {}) {
  const fallback = createDefaultOptions();
  const controls = { ...DEFAULT_CONTROLS };
  if (raw.controls !== null && typeof raw.controls === "object") {
    for (const key of Object.keys(DEFAULT_CONTROLS)) {
      if (typeof raw.controls[key] === "string" && raw.controls[key].trim().length > 0) {
        controls[key] = raw.controls[key].trim();
      }
    }
  }
  return {
    fov: clampNumber(raw.fov, MIN_FOV, MAX_FOV, fallback.fov),
    sensitivity: clampNumber(raw.sensitivity, MIN_SENSITIVITY, MAX_SENSITIVITY, fallback.sensitivity),
    showCoords: raw.showCoords === undefined ? fallback.showCoords : Boolean(raw.showCoords),
    renderDistance: clampInteger(raw.renderDistance, MIN_RENDER_DISTANCE, MAX_RENDER_DISTANCE, fallback.renderDistance),
    lodDistance: raw.lodDistance === undefined ? fallback.lodDistance : normalizeLodDistance(raw.lodDistance),
    renderer: runtimeRendererMode(raw.renderer),
    graphicsQuality: normalizeGraphicsQuality(raw.graphicsQuality),
    graphics: normalizeGraphicsEffects(raw.graphics),
    fpsLimit: normalizeFpsLimit(raw.fpsLimit),
    volumeMaster: clampVolume(raw.volumeMaster, fallback.volumeMaster),
    volumeMusic: clampVolume(raw.volumeMusic, fallback.volumeMusic),
    volumeEffects: clampVolume(raw.volumeEffects, fallback.volumeEffects),
    controls,
  };
}

export function loadOptions(store) {
  try {
    const raw = store.getItem(OPTIONS_KEY);
    if (!raw) return createDefaultOptions();
    return sanitizeOptions(JSON.parse(raw));
  } catch {
    return createDefaultOptions();
  }
}

export function saveOptions(store, options) {
  try {
    store.setItem(OPTIONS_KEY, JSON.stringify(sanitizeOptions(options)));
    return true;
  } catch {
    return false;
  }
}

/** The three stored volumes in the shape the mixer expects. */
export function audioVolumesFromOptions(options) {
  const source = options ?? {};
  return {
    master: clampVolume(source.volumeMaster, DEFAULT_VOLUME_MASTER),
    music: clampVolume(source.volumeMusic, DEFAULT_VOLUME_MUSIC),
    effects: clampVolume(source.volumeEffects, DEFAULT_VOLUME_EFFECTS),
  };
}

export function createWorldConfig({ name = "", seedText = "", mode = DEFAULT_WORLD_MODE } = {}) {
  return {
    name: String(name ?? "").trim() || DEFAULT_WORLD_NAME,
    seedText: String(seedText ?? "").trim(),
    mode: normalizeWorldMode(mode),
  };
}

export function validateWorldConfig(config) {
  const errors = [];
  if (!config || typeof config !== "object") return ["World settings are missing."];
  if (typeof config.name !== "string" || config.name.trim().length === 0) {
    errors.push("World name is missing.");
  }
  if (typeof config.seedText !== "string") errors.push("Seed must be text.");
  if (config.mode !== WORLD_MODES.SURVIVAL && config.mode !== WORLD_MODES.PEACEFUL) {
    errors.push("World mode is invalid.");
  }
  return errors;
}

export function randomSeedText() {
  return String(Math.floor(Math.random() * 1000000));
}

export function loadJson(store, key, fallback) {
  try {
    const raw = store.getItem(key);
    if (!raw) return fallback;
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

export function saveJson(store, key, value) {
  try {
    store.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}
