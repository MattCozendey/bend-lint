import {
  World,
  WorldState,
  Light,
  Dirty as LightDirty,
  Entities,
  Villagers,
  Furnace,
  Furnaces,
  Chest as ChestDomain,
  Chests,
  Equipment,
  Simulation,
  Experience,
  Fluids,
  Fire,
  Multiplayer,
  RedstoneAll,
} from "./bend-modules.js";
import {
  createRedstone,
  circuitOf,
  tickRedstone,
  placeRedstoneComponent,
  breakRedstoneAt,
  toggleLever,
  lampLitAt,
  torchLitAt,
  pistonExtendedAt,
  wirePowerAt,
} from "./redstone.js";
import {
  HOTBAR_SIZE,
  MAX_STACK,
  ITEM_IDS,
  RECIPES,
  blockForItem,
  canCraft,
  collectItem,
  consume,
  createInventory,
  craft,
  craftGrid,
  emptyBucket,
  emptyLavaBucket,
  fillBucket,
  fillLavaBucket,
  foodValue,
  itemColor,
  itemId,
  itemName,
  itemNameFromId,
  mineInteraction,
  miningDuration,
  placeInteraction,
  moveItem,
  selectedItem,
  shapedRecipePattern,
  tradeInventory,
  handDamage,
  useTool,
  weaponDamage,
} from "./inventory.js";
import { dropAmount, findShiftTarget, transferAmount } from "./inventory-ux.js";
import {
  EYE_HEIGHT,
  SNEAK_EYE_HEIGHT,
  DOMAIN_COORDINATE_OFFSET,
  applyDamage,
  applyLavaDamage,
  applyPoison,
  cameraDirection,
  clampPlayer,
  createPlayer,
  eatFood,
  isHeadUnderwater,
  isInWater,
  isPlayerAlive,
  isSneaking,
  isSprinting,
  mobRegion,
  movePlayer,
  lavaContact,
  overlapsPlayer,
  raycast,
  placePlayer,
  respawnPlayer,
  waterCurrentPush,
} from "./game-state.js";
import { createChunkedWorld } from "./chunk-world.js";
import {
  canonicalCells,
  generationChunkCoordinate,
  migrateLegacyEdits,
  stencilCoordinate,
  storageCoordinate as storageCoordinateFor,
  worldCoordinate,
} from "./world-coordinates.js";
import { bindInterleavedPositions, bindInterleavedTerrain, createWebglChunkBuffers } from "./webgl-chunk-buffers.js";
import { extractClipPlanes } from "./chunk-frustum.js";
import { MOB_BODY, dropBoxes, faceYaw, mobBoxes, playerBoxes, villagerBoxes } from "./mob-models.js";
import { connectMultiplayer, createEntityMirror, createRemotePlayers } from "./multiplayer.js";
import { NIGHT_DAYLIGHT, daylightForTime } from "./daylight.js";
import { nightSpawns } from "./mob-spawning.js";
import { createWorldSimulation, restoreSimulationState } from "./world-simulation.js";
import { multiplayerUrl, wireEditsToBend, wireFurnaceToBend, wireSlotsToBend } from "./multiplayer-protocol.js";
import { isHostileKind, mobKind } from "./mob-kinds.js";
import { createAsyncChunkMeshCache } from "./mesh-cache.js";
import { createMeshRebuildScheduler } from "./mesh-rebuild-scheduler.js";
import { villagerEditsChanged } from "./villager-simulation.js";
import { createLodTerrain, normalizeLodDistance } from "./lod-terrain.js";
import { certifyAtlasMipmaps, readAtlasTilePixels } from "./atlas-probe.js";
import {
  ATLAS_TILE_GUTTER,
  ATLAS_TILE_SIZE,
  atlasCellOrigin,
  atlasSourceCanvas,
  atlasUV,
  blockFaceTileAt,
  createAtlasCanvas,
  createTextureAtlas,
} from "./texture-atlas.js";
import { drawItemTexture, itemTexture } from "./item-atlas.js";
import { characterRenderDescriptor, heldItemPose } from "./character-view.js";
import { cameraMotion } from "./visual-motion.js";
import { cameraFov } from "./camera.js";
import { firstAimedMob } from "./aim.js";
import { getAudioMixer } from "./audio.js";
import { createFrameMetrics, framePercentiles, formatDebugText, sampleFrame } from "./frame-metrics.js";
import { CLOUD_TEXTURE_SIZE, createCloudTextureData } from "./cloud-texture.js";
import { entityShadow } from "./entity-shadow.js";
import { drawFirstPersonOverlay } from "./first-person-overlay.js";
import { nextFocusTarget, setShellInert } from "./modal-focus.js";
import { furnaceControlHidden } from "./hud-visibility.js";
import {
  FACE_NORMALS,
  quadCorners,
} from "./greedy-mesh.js";
import {
  TERRAIN_FACE_SHADES,
  blockLightLevel,
  cornerOcclusion,
  faceColorGrade,
  litEntityFaceColor,
} from "./material-lighting.js";
import { createMiningState, miningStateMatches } from "./mining-controller.js";
import { miningProgress } from "./mining-progress.js";
import {
  CLOUD_MAX_STEPS,
  SHADOW_MAX_TAPS,
  WEBGL_SKY_FALLBACK_FRAGMENT_SHADER,
  WEBGL_SKY_VERTEX_SHADER,
  WEBGL_TERRAIN_FALLBACK_FRAGMENT_SHADER,
  WEBGL_TERRAIN_FALLBACK_VERTEX_SHADER,
  createWebglSkyFragmentShader,
  createWebglTerrainShaderSources,
  isSoftwareRenderer,
} from "./webgl-shaders.js";
import {
  SHADOW_FADE_END,
  SHADOW_FADE_START,
  SHADOW_FLOOR,
  SHADOW_RADIUS,
  createSunShadowPass,
  createVogelDiskTexture,
  fitSunShadowMatrix,
} from "./webgl-shadow.js";
import { createPostPipeline } from "./webgl-post.js";
import {
  appendVfxQuads,
  createVfx,
  emitBlockDebris,
  emitDeathPuff,
  emitFlame,
  emitImpact,
  emitSmoke,
  emitSparkle,
  hexToRgb,
} from "./vfx.js";
import { cross, dot, lookAt, multiply4, normalize, perspective, transformPoint } from "./gl-matrix.js";
import {
  AMBIENT_DESATURATION,
  AMBIENT_STRENGTH,
  BUMP_STRENGTH,
  DETAIL_SCALE,
  DETAIL_STRENGTH,
  CLOUD_COVERAGE,
  CLOUD_WIND_SPEED,
  GROUND_BOUNCE,
  SUN_INTENSITY,
  WATER_DETAIL_STRENGTH,
} from "./terrain-presentation.js";
import {
  createVisualQualityController,
  parseVisualQuality,
  VISUAL_QUALITY_TIERS,
} from "./visual-quality.js";
import { resolveGraphicsEffects } from "./graphics-effects.js";
import { createFramePacer, measureDisplayCadenceMs } from "./frame-pacer.js";
import { concatFloat32Arrays } from "./vertex-buffer-compose.js";
import { skyPalette } from "./sky-palette.js";
import { decodeSave } from "./save-state.js";
import { loadTransactional, saveTransactional } from "./persistent-save.js";
import { packEntityState, restoreEntities, restoreVillagers } from "./entity-save.js";
import { createFixedTicker } from "./simulation-ticker.js";
import { createColumnHeightCache, isDropSolid } from "./drop-ground-cache.js";
import { buildChunkBuckets, concatBendLists } from "./entity-chunks.js";
import { seedFromSearch, seedLabel } from "./seed.js";
import { createPointerLockController } from "./pointer-lock.js";
import {
  createProfile,
  getActiveProfile,
  getProfile,
  getWorld,
  loadProfilesDoc,
  migrateLegacySave,
  saveKeyFor,
  saveProfilesDoc,
  touchProfile,
  touchWorld,
} from "./profiles.js";
import {
  audioVolumesFromOptions,
  loadOptions,
  normalizeWorldMode,
  runtimeRendererMode,
  worldModeLabel,
} from "./settings.js";
import { createWorkerScheduler } from "./worker-scheduler.js";
import { chooseRenderer, probeWebGpu, withTimeout } from "./webgpu-capabilities.js";
import { reportBackendFailureAndReturnToMenu } from "./backend-notice.js";
import { createWebGpuTerrainRenderer } from "./webgpu-terrain-renderer.js";

const canvas = document.getElementById("game");
const gameShell = document.getElementById("game-shell");
const worldLoadingEl = document.getElementById("world-loading");
const loadingWorldNameEl = document.getElementById("loading-world-name");
const loadingProgressEl = document.getElementById("loading-progress");
const crosshairEl = document.getElementById("crosshair");
const miningProgressEl = document.getElementById("mining-progress");
const miningProgressFillEl = document.getElementById("mining-progress-fill");
const coordsEl = document.getElementById("coords");
const seedEl = document.getElementById("seed");
const selectedEl = document.getElementById("selected");
const statsEl = document.getElementById("stats");
const debugOverlayEl = document.getElementById("debug-overlay");
const vitalsEl = document.getElementById("vitals");
const survivalAnnouncerEl = document.getElementById("survival-announcer");
const heartsEl = document.getElementById("hearts");
const hungerEl = document.getElementById("hunger");
const airEl = document.getElementById("air");
const xpHudEl = document.getElementById("xp-hud");
const xpLevelEl = document.getElementById("xp-level");
const xpTrackEl = document.getElementById("xp-track");
const xpFillEl = document.getElementById("xp-fill");
const damageFlashEl = document.getElementById("damage-flash");
const blockHighlightEl = document.getElementById("block-highlight");
const toastEl = document.getElementById("toast");
const particlesEl = document.getElementById("particles");
const pauseEl = document.getElementById("pause");
const pauseSubtitleEl = document.getElementById("pause-subtitle");
const deathEl = document.getElementById("death");
const deathStatsEl = document.getElementById("death-stats");
const hotbarEl = document.getElementById("hotbar-slots");
const firstPersonHandCanvasEl = document.getElementById("first-person-hand-canvas");
const firstPersonHandContext = firstPersonHandCanvasEl?.getContext("2d") ?? null;
const heldItemViewEl = document.getElementById("held-item-view");
const heldItemLabelEl = document.getElementById("held-item-label");
const inventoryToggleEl = document.getElementById("inventory-toggle");
const furnaceToggleEl = document.getElementById("furnace-toggle");
const chestToggleEl = document.getElementById("chest-toggle");
const inventoryPanelEl = document.getElementById("inventory-panel");
const furnacePanelEl = document.getElementById("furnace-panel");
const chestPanelEl = document.getElementById("chest-panel");
const inventorySlotsEl = document.getElementById("inventory-slots");
const equipmentSlotsEl = document.getElementById("equipment-slots");
const chestSlotsEl = document.getElementById("chest-slots");
const recipeListEl = document.getElementById("recipe-list");
const shapedRecipeEl = document.getElementById("shaped-recipe");
const craftingGridEl = document.getElementById("crafting-grid");
const craftingOutputEl = document.getElementById("crafting-output");
const shapedStatusEl = document.getElementById("shaped-status");
const inventoryMessageEl = document.getElementById("inventory-message");
const furnaceStatusEl = document.getElementById("furnace-status");
const chestStatusEl = document.getElementById("chest-status");
const lockHintEl = document.getElementById("lock-hint");
const helpEl = document.getElementById("help");
const errorEl = document.getElementById("error");
const playersOnlineEl = document.getElementById("players-online");
const nametagsEl = document.getElementById("nametags");
const sessionParams = new URLSearchParams(window.location.search);
const testMode = sessionParams.get("test") === "1";
const options = loadOptions(window.localStorage);

function resolveSession() {
  let doc = loadProfilesDoc(window.localStorage);
  let profile = sessionParams.get("profile") !== null
    ? getProfile(doc, sessionParams.get("profile"))
    : getActiveProfile(doc);
  if (profile === null) {
    const created = createProfile(doc, "Player 1");
    if (created.ok) {
      doc = created.doc;
      saveProfilesDoc(window.localStorage, doc);
      profile = created.profile;
    }
  }
  let worldName = "Wilderness";
  let mode = "survival";
  let seed = null;
  const worldId = sessionParams.get("world");
  if (profile !== null && worldId !== null) {
    const entry = getWorld(doc, profile.id, worldId);
    if (entry !== null) {
      worldName = entry.name;
      mode = normalizeWorldMode(entry.mode);
      try {
        seed = BigInt(entry.seed);
      } catch {
        seed = null;
      }
    }
  }
  if (seed === null) {
    seed = seedFromSearch(window.location.search, World.default_seed());
  }
  const profileId = profile === null ? "guest" : profile.id;
  const profileName = profile === null ? "Guest" : profile.name;
  return { doc, profile, profileId, profileName, worldId, worldName, mode, seed };
}

const session = resolveSession();
// Multiplayer: `?mp=1` joins the server that served this page, and
// `&server=host:port` (or a ws:// / wss:// URL) joins another one. The server
// owns the seed and the shared edit log, so both come from its welcome; this
// profile's player, inventory and equipment are kept per server.
const MULTIPLAYER_REQUESTED = sessionParams.get("mp") === "1";
let multiplayer = null;
if (MULTIPLAYER_REQUESTED) {
  if (loadingWorldNameEl !== null) loadingWorldNameEl.textContent = "Joining the multiplayer server…";
  try {
    multiplayer = await connectMultiplayer({
      url: multiplayerUrl(sessionParams.get("server") ?? "", window.location),
      name: session.profileName,
    });
  } catch (error) {
    if (worldLoadingEl !== null) worldLoadingEl.hidden = true;
    const reason = error instanceof Error ? error.message : String(error);
    showError(new Error(`${reason}\nCheck the server address and that the server is running.`));
  }
}
const MULTIPLAYER_HOST = multiplayer === null ? null : new URL(multiplayer.url).host;
const SEED = multiplayer === null ? session.seed : BigInt(multiplayer.seed);
const SAVE_KEY = saveKeyFor(
  session.profileId,
  multiplayer === null ? seedLabel(SEED) : `mp-${MULTIPLAYER_HOST}-${seedLabel(SEED)}`,
);
const WORLD_NAME = multiplayer === null ? session.worldName : `Multiplayer · ${MULTIPLAYER_HOST}`;
const PROFILE_NAME = session.profileName;
const WORLD_MODE = session.mode;
const PEACEFUL = WORLD_MODE === "peaceful";
const VILLAGER_SIMULATION_RADIUS = 16;
const MESH_TARGET_BATCH_SIZE = 64;
const MELEE_ATTACK_RANGE = 4.0;
const RANGED_ATTACK_RANGE = 16.0;
document.body.dataset.mode = "game";
document.body.classList.remove("is-world-ready");
if (worldLoadingEl !== null) worldLoadingEl.hidden = false;
if (loadingWorldNameEl !== null) loadingWorldNameEl.textContent = `${WORLD_NAME} · seed ${seedLabel(SEED)}`;
const pointerLock = createPointerLockController(
  () => document.pointerLockElement === canvas,
  () => canvas.requestPointerLock(),
);
const reducedMotionQuery = window.matchMedia?.("(prefers-reduced-motion: reduce)") ?? null;

const BLOCK_COLORS = {
  1: [0.34, 0.38, 0.42],
  2: [0.53, 0.34, 0.2],
  3: [0.35, 0.72, 0.28],
  4: [0.18, 0.55, 0.26],
  5: [0.55, 0.34, 0.18],
  6: [0.82, 0.7, 0.4],
  7: [0.16, 0.5, 0.82],
  8: [0.12, 0.13, 0.15],
  9: [0.62, 0.38, 0.3],
  10: [0.2, 0.8, 0.78],
  11: [0.28, 0.3, 0.34],
  12: [1.0, 0.62, 0.16],
  13: [0.78, 0.25, 0.38],
  14: [0.55, 0.32, 0.18],
  15: [0.72, 0.48, 0.3],
  16: [0.34, 0.62, 0.2],
  17: [0.55, 0.72, 0.24],
  18: [0.78, 0.68, 0.2],
  19: [0.92, 0.76, 0.24],
  20: [0.32, 0.24, 0.16],
};
const firstPersonAtlasCanvas = createAtlasCanvas(BLOCK_COLORS);
const FACES = [
  { dir: [0, 1, 0], corners: [[0, 1, 0], [1, 1, 0], [1, 1, 1], [0, 1, 1]] },
  { dir: [0, -1, 0], corners: [[0, 0, 1], [1, 0, 1], [1, 0, 0], [0, 0, 0]] },
  { dir: [1, 0, 0], corners: [[1, 0, 0], [1, 0, 1], [1, 1, 1], [1, 1, 0]] },
  { dir: [-1, 0, 0], corners: [[0, 0, 1], [0, 0, 0], [0, 1, 0], [0, 1, 1]] },
  { dir: [0, 0, 1], corners: [[1, 0, 1], [0, 0, 1], [0, 1, 1], [1, 1, 1]] },
  { dir: [0, 0, -1], corners: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]] },
];

function asNumber(value) {
  return Number(value);
}

function showError(error) {
  const message = error instanceof Error ? error.message : String(error);
  errorEl.textContent = `Could not start the world.\n${message}`;
  errorEl.hidden = false;
  throw error;
}

const modalPanels = [deathEl, pauseEl, inventoryPanelEl, furnacePanelEl, chestPanelEl];

function activeModalPanel() {
  return modalPanels.find((panel) => panel !== null && panel.hidden === false) ?? null;
}

function syncModalIsolation() {
  if (gameShell !== null) setShellInert(gameShell, activeModalPanel());
}

function trapModalFocus(event) {
  if (event.key !== "Tab") return;
  const panel = activeModalPanel();
  if (panel === null) return;
  const target = nextFocusTarget(panel, document.activeElement, event.shiftKey);
  event.preventDefault();
  target?.focus({ preventScroll: true });
}

document.addEventListener("keydown", trapModalFocus, true);

function setDialogVisibility(panel, toggle, open) {
  if (panel === null) return;
  panel.hidden = !open;
  panel.setAttribute("aria-hidden", String(!open));
  syncModalIsolation();
  if (open) {
    window.requestAnimationFrame(() => {
      panel.querySelector("[data-close-inventory], [data-close-furnace], [data-close-chest]")?.focus({ preventScroll: true });
    });
  } else if (panel.contains(document.activeElement)) {
    (toggle ?? canvas).focus({ preventScroll: true });
  }
}

async function bootGame() {
let gl = null;
let program;
let skyProgram;
let skyPositionBuffer;
let dynamicPositionBuffer;
let dynamicColorBuffer;
let dynamicLightBuffer;
let dynamicNormalBuffer;
let dynamicUvBuffer;
let dynamicTileBuffer;
let shadowPositionBuffer;
let shadowColorBuffer;
let shadowLightBuffer;
let shadowNormalBuffer;
let shadowUvBuffer;
let vfxPositionBuffer;
let vfxColorBuffer;
let vfxLightBuffer;
let vfxNormalBuffer;
let vfxUvBuffer;
let vfxTileBuffer;
let positionLocation;
let colorLocation;
let lightLocation;
let normalLocation;
let uvLocation;
let materialLocation;
let tileLocation;
let viewProjectionLocation;
let cameraLocation;
let terrainSkyColorLocation;
let terrainSkyHorizonColorLocation;
let terrainSunDirectionLocation;
let terrainSunColorLocation;
let atlasLocation;
let terrainCloudMapLocation;
let shadowPassLocation;
let vfxPassLocation;
let miningProgressLocation;
let skyPositionLocation;
let skyCameraForwardLocation;
let skyCameraRightLocation;
let skyCameraUpLocation;
let skyColorLocation;
let skyHorizonColorLocation;
let skySunDirectionLocation;
let skySunColorLocation;
let skyAspectLocation;
let skyTanHalfFovLocation;
let skyDaylightLocation;
let skyTimeLocation;
let skyCloudStepsLocation;
let skyCloudLightStepsLocation;
let skyCloudCoverageLocation;
let skyWindSpeedLocation;
let skyCameraPositionLocation;
let terrainGroundBounceLocation;
let terrainSunIntensityLocation;
let terrainAmbientStrengthLocation;
let terrainAmbientDesaturationLocation;
let terrainBumpStrengthLocation;
let terrainDetailStrengthLocation;
let terrainDetailScaleLocation;
let terrainWaterDetailLocation;
let terrainCameraPositionLocation;
let terrainNearLocation;
let terrainFarLocation;
let terrainSceneDepthLocation;
// The terrain samplers. The unit a texture is *bound* to and the unit the shader
// *reads* from are two separate pieces of state, and a sampler left at its
// default of 0 silently reads whatever is on unit 0. Writing the numbers in one
// place and using them for both is the only way they cannot drift apart.
const TERRAIN_TEXTURE_UNIT = Object.freeze({
  atlas: 0,
  cloudMap: 1,
  shadowMap: 2,
  shadowDisk: 3,
  sceneDepth: 4,
});
let shadowMapLocation;
let shadowDiskLocation;
let lightViewProjectionLocation;
let shadowTexelSizeLocation;
let shadowRadiusLocation;
let shadowFadeLocation;
let shadowStrengthLocation;
let shadowTapsLocation;
let shadowFloorLocation;
let postPipeline = null;
let shadowPass = null;
let shadowDiskTexture = null;
let shadowFallbackTexture = null;
let visualQuality = null;
let framePacer = null;
// The player's dial, resolved once at boot: the quality tier owns what a frame
// may cost and these own how much of each effect it shows. Resolved here rather
// than inside the WebGL setup because both renderers read it, and per frame would
// only re-read a document that cannot change mid-session - the options screen is
// on the title, so a change is a world reload.
const graphicsEffects = resolveGraphicsEffects(options.graphics);
let terrainVertexCount = 0;
let waterVertexCount = 0;
let dynamicVertexCount = 0;
let shadowVertexCount = 0;
let vfxVertexCount = 0;
let terrainQuadCount = 0;
let waterQuadCount = 0;
let dynamicQuadCount = 0;
let shadowQuadCount = 0;
let visibleFaceCount = 0;
let daylight = 1;
let worldTime = 0;
let skyCssTick = -1;
let frameMetrics = createFrameMetrics();
let debugVisible = false;
let rendererKind = "webgl";
let rendererName = "unknown";
let shaderQuality = 1;
let webgpuProbe = { supported: false, adapterName: null, reason: "not probed" };
let gpuRenderer = null;
let lastGpuChunkUpdate = null;
// WebGL keeps one interleaved buffer per chunk (and per LOD section), like the
// WebGPU backend, instead of one whole-world array re-uploaded on every change.
let glChunkBuffers = null;
let glSubmit = null;
let timeLocation;
let daylightLocation;
let surfacePassLocation;
let atlasTexture = null;
let atlasMipmapVerdict = { safe: false, reason: "not probed", levels: [], contaminated: [] };
let cloudTexture = null;


function createWebglContext() {
  const probeCanvas = document.createElement("canvas");
  const probe = probeCanvas.getContext("webgl", { antialias: false });
  const debugRendererInfo = probe?.getExtension?.("WEBGL_debug_renderer_info");
  const probeName = String(debugRendererInfo
    ? probe.getParameter(debugRendererInfo.UNMASKED_RENDERER_WEBGL)
    : probe?.getParameter?.(probe.RENDERER) ?? "");
  probe?.getExtension?.("WEBGL_lose_context")?.loseContext();
  return canvas.getContext("webgl", {
    antialias: !isSoftwareRenderer(probeName),
    alpha: true,
    preserveDrawingBuffer: true,
  });
}

function configureWebglQuality() {
  const debugRendererInfo = gl.getExtension("WEBGL_debug_renderer_info");
  rendererName = String(debugRendererInfo
    ? gl.getParameter(debugRendererInfo.UNMASKED_RENDERER_WEBGL)
    : gl.getParameter(gl.RENDERER));
  shaderQuality = isSoftwareRenderer(rendererName) ? 0 : 1;
  if (testMode && sessionParams.get("quality") === "high") shaderQuality = 1;
}

function webgpuRequestedExplicitly(requested, configured) {
  // A stored preference counts as explicit. The player chose WebGPU in the menu,
  // so silently running something else would be a lie about what they asked for.
  return requested === "webgpu" && configured !== "auto";
}

try {
  const configuredRenderer = sessionParams.get("renderer") ?? options.renderer ?? "auto";
  const requestedRenderer = runtimeRendererMode(configuredRenderer);
  webgpuProbe = requestedRenderer === "webgl"
    ? { supported: false, adapterName: null, reason: configuredRenderer === "auto" ? "renderer=auto-safe" : "renderer=webgl" }
    : await probeWebGpu(globalThis.navigator, canvas);
  // `chooseRenderer` throws when WebGPU was asked for and is not there. That
  // throw used to land in the outer handler and leave the player on a dead page
  // with an error and no route back to the setting that would fix it, so the
  // decision is caught here and turned into the same recovery the later failures
  // use.
  try {
    rendererKind = chooseRenderer({ requested: requestedRenderer, webgpu: webgpuProbe });
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    if (webgpuRequestedExplicitly(requestedRenderer, configuredRenderer)) {
      reportBackendFailureAndReturnToMenu({ renderer: "webgpu", reason });
      return;
    }
    throw error;
  }
  if (rendererKind === "webgl") {
    // Keep the last frame readable for browser compositors and visual smoke tests.
    gl = createWebglContext();
    if (!gl) throw new Error("WebGL is not available in this browser.");
    configureWebglQuality();
  }
  // The shared instance, not a private one: the menu's volume sliders drive the
  // same graph the game plays through, so what a player hears while adjusting is
  // what they get in the world.
  const audio = getAudioMixer();
  audio.setVolumes(audioVolumesFromOptions(options));

  let savedGame = null;
  try {
    const migrated = multiplayer === null
      ? migrateLegacySave(window.localStorage, session.profileId, seedLabel(SEED))
      : null;
    savedGame = migrated !== null
      ? decodeSave(migrated)
      : loadTransactional(window.localStorage, SAVE_KEY)?.value ?? null;
  } catch {
    savedGame = null;
  }
  // On a multiplayer server the world belongs to the server: only what this
  // player carries is restored, never a local edit log or local simulations
  // that would replay into the shared world.
  if (multiplayer !== null && savedGame !== null) {
    savedGame = {
      player: savedGame.player,
      inventory: savedGame.inventory,
      equipment: savedGame.equipment,
      craftingGrid: savedGame.craftingGrid,
      xp: savedGame.xp,
    };
  }
  const remotePlayers = createRemotePlayers();
  // On a multiplayer server, mobs and drops are the server's: this mirror holds
  // its snapshots and the game only renders and aims at them.
  const entityMirror = createEntityMirror();
  const pendingPickups = new Set();
  const nametagElements = new Map();

  // A torch flood depends only on the seed and the source (its walls are the
  // generated terrain), so a cached field stays valid across every other edit.
  // Only placing or removing a light source changes which fields exist.
  const lightSourceFieldCache = new Map();
  const sourceFieldKey = (source) => `${source.x},${source.y},${source.z},${source.block}`;
  const invalidateLightFields = (x, y, z, previousBlock, value) => {
    const touchesSource = [previousBlock, value].some((block) => block === 12 || block === 21);
    if (!touchesSource) return;
    const storedX = storageCoordinateFor(x, asNumber(World.chunk_size()));
    const storedZ = storageCoordinateFor(z, asNumber(World.chunk_size()));
    for (const block of [12, 21]) lightSourceFieldCache.delete(`${storedX},${y},${storedZ},${block}`);
  };
  const lightFieldsFor = (source) => {
    const key = sourceFieldKey(source);
    let own = lightSourceFieldCache.get(key);
    if (own === undefined) {
      own = Light.source_fields_one(source, SEED);
      lightSourceFieldCache.set(key, own);
    }
    return own;
  };
  // Light for a batch of dirty cells (stored coordinates). Only the sources
  // whose flood can reach the cells' chunks contribute fields, and only the
  // edits inside the cells' bounding box are scanned; both are exact, since a
  // field outside its flood never matches and a cell reads only its column.
  const generateLightCells = (cells, edits) => {
    const chunkSize = asNumber(World.chunk_size());
    const chunks = new Map();
    let minX = Infinity;
    let minZ = Infinity;
    let maxX = -Infinity;
    let maxZ = -Infinity;
    for (let node = cells; node?.$ === "Con"; node = node.tail) {
      const x = Number(node.head.x);
      const z = Number(node.head.z);
      minX = Math.min(minX, x);
      minZ = Math.min(minZ, z);
      maxX = Math.max(maxX, x);
      maxZ = Math.max(maxZ, z);
      const chunkX = Math.floor(x / chunkSize);
      const chunkZ = Math.floor(z / chunkSize);
      chunks.set(`${chunkX},${chunkZ}`, [chunkX, chunkZ]);
    }
    if (chunks.size === 0) return { $: "Nil" };
    const sources = WorldState.light_sources(edits);
    const relevant = new Map();
    for (const [chunkX, chunkZ] of chunks.values()) {
      for (let node = Light.relevant_sources(sources, BigInt(chunkX), BigInt(chunkZ)); node?.$ === "Con"; node = node.tail) {
        relevant.set(sourceFieldKey(node.head), node.head);
      }
    }
    let fields = { $: "Nil" };
    for (const source of relevant.values()) fields = Light.append_fields(lightFieldsFor(source), fields);
    return Light.patch_fields_box(fields, edits, SEED, cells, BigInt(minX), BigInt(minZ), BigInt(maxX), BigInt(maxZ));
  };

  const MAX_Y = asNumber(World.max_y());
  const CHUNK_SIZE = asNumber(World.chunk_size());
  const CHUNK_RENDER_RADIUS = options.renderDistance;
  // Keep the camera clip and fog beyond the selected chunk window. Without
  // this, a larger setting would load chunks that WebGL immediately clips or
  // fades into the sky.
  // Distant terrain (the LOD rings) extends the view far past the streamed
  // chunks, so the far plane and the fog follow the LOD distance when it is on.
  const LOD_DISTANCE = normalizeLodDistance(options.lodDistance);
  const RENDER_FAR = Math.max(
    120,
    Math.ceil((CHUNK_RENDER_RADIUS + 2) * CHUNK_SIZE * Math.SQRT2),
    Math.ceil(LOD_DISTANCE * 1.05 + 32),
  );
  const FOG_DISTANCE = Math.max(
    72,
    (CHUNK_RENDER_RADIUS + 1) * CHUNK_SIZE * 1.5 - 24,
    LOD_DISTANCE * 1.1,
  );
  // The negative-coordinate mapping belongs to web/world-coordinates.js, which
  // owns it for the main thread and every worker. `NEGATIVE_ORIGIN` is a
  // multiple of every period in the terrain formulas, so the terrain below zero
  // continues the terrain above it, and the same constant lives in Bend as
  // `World.negative_origin()` with a test pinning the two together.
  const storageCoordinate = (value) => storageCoordinateFor(value, CHUNK_SIZE);
  // A Bend Nat cannot be negative and the 2.0.32 JS lane refuses a negative host
  // value outright rather than truncating it, so a cell below the origin is
  // stored at NEGATIVE_ORIGIN + x and read back the same way. These three are
  // the only spellings of a cell that crosses into the domain; a call site that
  // builds its own Nat addresses a cell nothing else names. y is never shifted,
  // because the domain has no rows below zero.
  const cellNat = (value) => BigInt(Math.trunc(storageCoordinate(Number(value))));
  const cellRow = (value) => BigInt(Math.trunc(Number(value)));
  const cellPosition = (x, y, z) => [cellNat(x), cellRow(y), cellNat(z)];
  // A chunk coordinate is a Nat for the same reason a cell is.
  const chunkNat = (chunk) => BigInt(generationChunkCoordinate(Math.trunc(Number(chunk)), CHUNK_SIZE));
  if (rendererKind === "webgpu") {
    try {
      // The WebGPU path has no WebGL context to certify against, so the
      // renderer certifies the atlas on its own device before it builds the
      // texture it samples. It reports the verdict so the diagnostics agree
      // with whichever backend is live.
      gpuRenderer = await withTimeout(
        createWebGpuTerrainRenderer({
          canvas,
          atlasCanvas: createAtlasCanvas(BLOCK_COLORS),
        }),
        3000,
        "WebGPU renderer initialization timed out.",
      );
      atlasMipmapVerdict = gpuRenderer.getAtlasMipmapVerdict();
      // A device can die long after boot, and nothing about it is visible: submits
      // are dropped and reads stay pending, so the loop keeps running over a still
      // image. Both the event and a per-frame poll are needed - the event alone
      // misses a loss the implementation chooses not to report, and the poll alone
      // would only notice on the next frame that is never drawn.
      gpuRenderer.onDeviceFailure((failure) => {
        reportBackendFailureAndReturnToMenu({ renderer: "webgpu", reason: failure.reason });
      });
    } catch (error) {
      // A backend that cannot start is not a reason to leave the player on a dead
      // page. Falling back and telling them is the only recovery: the alternative
      // is a frozen window with no way back to the setting that would fix it.
      const reason = error instanceof Error ? error.message : String(error);
      if (webgpuRequestedExplicitly(requestedRenderer, configuredRenderer)) {
        reportBackendFailureAndReturnToMenu({ renderer: "webgpu", reason });
        return;
      }
      rendererKind = "webgl";
      webgpuProbe = { ...webgpuProbe, reason };
      gl = createWebglContext();
      if (!gl) {
        reportBackendFailureAndReturnToMenu({
          renderer: "webgpu",
          reason: `${reason} (and WebGL is unavailable too)`,
        });
        return;
      }
      configureWebglQuality();
    }
  }
  let world;
  let terrainMeshCache;
  let streamingMeshScheduler = null;
  let deferredMeshRebuildTimer = null;
  let workerRequestId = 0;
  let workerRequestCount = 0;
  let workerResponseCount = 0;
  let workerHydrateCount = 0;
  let workerRejectCount = 0;
  let meshWorkerRequestCount = 0;
  let meshWorkerResponseCount = 0;
  let meshWorkerRejectCount = 0;
  const CHUNK_WORKER_COUNT = Math.min(4, Math.max(2, Number(navigator.hardwareConcurrency) || 2));
  const chunkWorkers = Array.from(
    { length: CHUNK_WORKER_COUNT },
    () => new Worker("/chunk-worker.js", { type: "module" }),
  );
  const chunkWorkerScheduler = createWorkerScheduler(chunkWorkers.length);
  const meshWorker = new Worker("/mesh-worker.js", { type: "module" });
  let villagerPathWorker = null;
  let villagerPathRequestId = 0;
  let villagerPathLatestRequestId = 0;
  let villagerPathPending = false;
  let villagerPathRequestTimer = null;
  let villagerPathWorkerRequests = 0;
  let villagerPathWorkerResponses = 0;
  let villagerPathWorkerRejects = 0;
  function ensureVillagerPathWorker() {
    if (villagerPathWorker !== null) return;
    villagerPathWorker = new Worker("/chunk-worker.js", { type: "module" });
    villagerPathWorker.onmessage = (event) => {
      const message = event.data;
      if (message?.type !== "pathGrid") return;
      if (message.requestId !== villagerPathLatestRequestId) return;
      villagerPathPending = false;
      if (message.error !== undefined) {
        villagerPathWorkerRejects += 1;
        return;
      }
      villagerPathWorkerResponses += 1;
      villagerPathGrid = message.grid;
    };
    villagerPathWorker.onerror = () => {
      villagerPathPending = false;
      villagerPathWorkerRejects += 1;
    };
  }
  const requestMeshBuild = (job) => {
    meshWorkerRequestCount += 1;
    const transferables = [];
    for (const chunk of job.chunks) {
      transferables.push(chunk.data.buffer, chunk.light.buffer);
    }
    meshWorker.postMessage({ ...job, daylight: 1 }, transferables);
  };
  meshWorker.onmessage = (event) => {
    const { id, error } = event.data;
    if (error !== undefined) {
      meshWorkerRejectCount += 1;
      showError(new Error(`Mesh build failed: ${error}`));
      return;
    }
    if (terrainMeshCache?.applyBuild(id, event.data)) {
      meshWorkerResponseCount += 1;
      // Both backends upload per chunk, so a finished edit rebuild costs one
      // small upload: publish it at once so the edited block updates without
      // waiting for the streaming cadence.
      if (hiddenTerrainBlocks.size > 0 || streamingMeshScheduler === null) rebuildMesh(false);
      else streamingMeshScheduler.request();
    }
  };
  meshWorker.onerror = (event) => {
    meshWorkerRejectCount += 1;
    showError(new Error(event.message || "Mesh worker failed."));
  };
  const handleChunkMessage = (event) => {
    const { chunkX, chunkZ, blocks, lights, version, error, workerReady } = event.data;
    if (workerReady) return;
    workerResponseCount += 1;
    if (error !== undefined) {
      showError(new Error(`Chunk ${chunkX},${chunkZ} failed: ${error}`));
      return;
    }
    if (world.hydrateChunk(chunkX, chunkZ, blocks, lights, version)) {
      dropGroundCache?.clear();
      workerHydrateCount += 1;
      const ready = world.loadAround(player.x, player.z);
      if (ready.changed) {
        streamingMeshScheduler?.request();
      }
      updateWorldLoading();
    } else {
      workerRejectCount += 1;
    }
  };
  for (const chunkWorker of chunkWorkers) {
    chunkWorker.onmessage = handleChunkMessage;
    chunkWorker.onerror = (event) => showError(new Error(event.message || "Chunk worker failed."));
  }
  world = createChunkedWorld({
    chunkSize: CHUNK_SIZE,
    maxY: MAX_Y,
    renderRadius: CHUNK_RENDER_RADIUS,
    loadBudget: CHUNK_WORKER_COUNT,
    // Saves from before the continuous negative mapping stored x < 0 edits in
    // a remapped chunk range; they are moved to the current encoding on load.
    initialEdits: multiplayer !== null
      ? wireEditsToBend(multiplayer.edits)
      : savedGame?.edits?.$ === "Nil" || savedGame?.edits?.$ === "Con"
        ? migrateLegacyEdits(savedGame.edits, CHUNK_SIZE)
        : WorldState.empty(),
    generateChunk: (chunkX, chunkZ, edits) => WorldState.chunk(
      SEED,
      BigInt(generationChunkCoordinate(chunkX, CHUNK_SIZE)),
      BigInt(generationChunkCoordinate(chunkZ, CHUNK_SIZE)),
      edits,
    ),
    generateLightChunk: (chunkX, chunkZ, edits) => Light.chunk_with_edits(
      WorldState.light_sources(edits),
      edits,
      SEED,
      BigInt(generationChunkCoordinate(chunkX, CHUNK_SIZE)),
      BigInt(generationChunkCoordinate(chunkZ, CHUNK_SIZE)),
    ),
    generateLightCells,
    affectedLightChunks: (x, z, chunkSize) => LightDirty.chunks(BigInt(x), BigInt(z), BigInt(chunkSize)),
    // Dirty-cell stencils run on aliased coordinates so they can step across
    // zero, then come back in the canonical encoding the light rules read.
    affectedLightCells: (x, y, z) => canonicalCells(
      LightDirty.cells_plane(BigInt(stencilCoordinate(x)), BigInt(y), BigInt(stencilCoordinate(z))),
      CHUNK_SIZE,
    ),
    affectedLightColumnCells: (x, y, z) => canonicalCells(
      LightDirty.cells_column(BigInt(stencilCoordinate(x)), BigInt(y), BigInt(stencilCoordinate(z))),
      CHUNK_SIZE,
    ),
    affectedLightSelfCells: (x, y, z) => canonicalCells(
      LightDirty.cells_self(BigInt(stencilCoordinate(x)), BigInt(y), BigInt(stencilCoordinate(z))),
      CHUNK_SIZE,
    ),
    lightNeutral: (previous, next) => LightDirty.light_neutral(previous, next),
    lightCellCoordinate: worldCoordinate,
    invalidateLightFields,
    requestChunk: (chunkX, chunkZ, edits, version) => {
      workerRequestCount += 1;
      chunkWorkers[chunkWorkerScheduler.next()].postMessage({
        id: workerRequestId += 1,
        version,
        seed: SEED,
        chunkX,
        chunkZ,
        generationChunkX: generationChunkCoordinate(chunkX, CHUNK_SIZE),
        generationChunkZ: generationChunkCoordinate(chunkZ, CHUNK_SIZE),
        cellCount: CHUNK_SIZE * CHUNK_SIZE * MAX_Y,
        edits,
      });
    },
    applyEdit: (edits, x, y, z, value) => WorldState.set(
      edits,
      cellNat(x),
      cellRow(y),
      cellNat(z),
      value,
    ),
    // Fluid, fire and crop steps change many cells at once: one pass over the log.
    applyEdits: (edits, changes) => WorldState.set_many(
      edits,
      wireEditsToBend(changes.map((change) => [storageCoordinate(change.x), change.y, storageCoordinate(change.z), change.value])),
    ),
  });
  const { inside, blockAt, lightAt, setBlock: rawSetBlock, setBlocks: rawSetBlocks } = world;
  let dropGroundCache = null;
  let terrainImmediateDirty = false;
  const hiddenTerrainBlocks = new Set();
  // Every local block change is predicted here and sent to the multiplayer
  // server, which orders it and sends it back to everyone (see
  // applyServerEdits). Batches from the server never pass through these
  // wrappers, so nothing is echoed twice.
  const shareEdits = (changes) => {
    if (multiplayer === null) return;
    for (const change of changes) {
      multiplayer.queueEdit([storageCoordinate(change.x), change.y, storageCoordinate(change.z), change.value]);
    }
  };
  const setBlock = (x, y, z, value) => {
    dropGroundCache?.invalidate(Math.floor(x), Math.floor(z));
    const previous = blockAt(x, y, z);
    const changed = rawSetBlock(x, y, z, value);
    if (changed && previous !== value && previous !== 0) hiddenTerrainBlocks.add(`${x},${y},${z}`);
    if (changed) shareEdits([{ x, y, z, value }]);
    terrainImmediateDirty = terrainImmediateDirty || changed;
    return changed;
  };
  const setBlocks = (changes) => {
    const previous = changes.map((change) => blockAt(change.x, change.y, change.z));
    for (const change of changes) dropGroundCache?.invalidate(Math.floor(change.x), Math.floor(change.z));
    const changed = rawSetBlocks(changes);
    if (changed) {
      changes.forEach((change, index) => {
        if (previous[index] !== change.value && previous[index] !== 0) {
          hiddenTerrainBlocks.add(`${change.x},${change.y},${change.z}`);
        }
      });
      shareEdits(changes);
    }
    terrainImmediateDirty = terrainImmediateDirty || changed;
    return changed;
  };
  // Fluids, fire, crops and farmland: the shared simulation module, run over
  // this browser's chunk cache. Its block changes go through setBlocks like
  // any other edit, so the mesh and the light follow them.
  const worldSimulation = createWorldSimulation({
    seed: SEED,
    chunkSize: CHUNK_SIZE,
    state: restoreSimulationState(savedGame),
    world: {
      blockAt,
      inside,
      isActive: (x, z) => world.isActive(x, z),
      setBlocks: (changes) => {
        setBlocks(changes);
        for (const change of changes) terrainMeshCache?.invalidateBlock(change.x, change.z);
      },
      pinChunk: (chunkX, chunkZ) => world.pinChunk(chunkX, chunkZ),
      unpinChunk: (chunkX, chunkZ) => world.unpinChunk(chunkX, chunkZ),
    },
    keepChunk: (chunkX, chunkZ) => hasFurnaceInChunk(chunkX, chunkZ),
  });
  worldSimulation.pinStored();

  // The redstone circuit, restored from the save or started empty. The contract
  // in world/redstone_all.bend owns every rule; the adapter only ticks it and
  // applies the world edits it returns.
  const redstoneState = createRedstone(savedGame?.redstone);
  const redstoneIds = redstoneState.ids;
  let blockCount = 0;

  if (rendererKind === "webgl") {
    // The derivative bump needs OES_standard_derivatives. SwiftShader and some
    // older mobile drivers do not expose it, so the shader is built without the
    // derivative path there instead of failing to compile.
    const derivatives = Boolean(gl.getExtension("OES_standard_derivatives"));
    const advancedTerrainSources = createWebglTerrainShaderSources(FOG_DISTANCE, {
      bumpMapping: derivatives,
      waterDetail: true,
      grassWind: true,
    });
    const fallbackTerrainSources = createWebglTerrainShaderSources(FOG_DISTANCE, {
      bumpMapping: false,
      waterDetail: false,
      grassWind: false,
    });
    const terrainSources = shaderQuality >= 0.5 ? advancedTerrainSources : fallbackTerrainSources;

  function compileShader(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const info = gl.getShaderInfoLog(shader);
      gl.deleteShader(shader);
      throw new Error(`WebGL shader compilation failed: ${info}`);
    }
    return shader;
  }

  function linkProgram(vertexShaderSource, fragmentShaderSource) {
    const vertexShader = compileShader(gl.VERTEX_SHADER, vertexShaderSource);
    let fragmentShader;
    try {
      fragmentShader = compileShader(gl.FRAGMENT_SHADER, fragmentShaderSource);
    } catch (error) {
      gl.deleteShader(vertexShader);
      throw error;
    }
    const linkedProgram = gl.createProgram();
    gl.attachShader(linkedProgram, vertexShader);
    gl.attachShader(linkedProgram, fragmentShader);
    gl.linkProgram(linkedProgram);
    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);
    if (!gl.getProgramParameter(linkedProgram, gl.LINK_STATUS)) {
      const info = gl.getProgramInfoLog(linkedProgram);
      gl.deleteProgram(linkedProgram);
      throw new Error(`Failed to link the WebGL program: ${info}`);
    }
    return linkedProgram;
  }

  function createPermutedProgram(
    vertexShaderSource,
    fragmentShaderSource,
    fallbackVertexShaderSource,
    fallbackFragmentShaderSource,
  ) {
    try {
      return {
        program: linkProgram(vertexShaderSource, fragmentShaderSource),
        usedFallback: false,
      };
    } catch (error) {
      if (vertexShaderSource === fallbackVertexShaderSource
        && fragmentShaderSource === fallbackFragmentShaderSource) throw error;
      // Falling back silently would hide a real shader bug behind a flat-looking
      // world, so the reason is reported rather than swallowed.
      console.warn("[webgl] advanced shader failed to build, using the fallback:", error.message);
      return {
        program: linkProgram(fallbackVertexShaderSource, fallbackFragmentShaderSource),
        usedFallback: true,
      };
    }
  }

  const terrainProgram = createPermutedProgram(
    terrainSources.vertexSource,
    terrainSources.fragmentSource,
    fallbackTerrainSources.vertexSource,
    fallbackTerrainSources.fragmentSource,
  );
  program = terrainProgram.program;
  if (terrainProgram.usedFallback) shaderQuality = 0;

  glChunkBuffers = createWebglChunkBuffers(gl);
  dynamicPositionBuffer = gl.createBuffer();
  dynamicColorBuffer = gl.createBuffer();
  dynamicLightBuffer = gl.createBuffer();
  dynamicNormalBuffer = gl.createBuffer();
  dynamicUvBuffer = gl.createBuffer();
  dynamicTileBuffer = gl.createBuffer();
  shadowPositionBuffer = gl.createBuffer();
  shadowColorBuffer = gl.createBuffer();
  shadowLightBuffer = gl.createBuffer();
  shadowNormalBuffer = gl.createBuffer();
  shadowUvBuffer = gl.createBuffer();
  vfxPositionBuffer = gl.createBuffer();
  vfxColorBuffer = gl.createBuffer();
  vfxLightBuffer = gl.createBuffer();
  vfxNormalBuffer = gl.createBuffer();
  vfxUvBuffer = gl.createBuffer();
  vfxTileBuffer = gl.createBuffer();
  positionLocation = gl.getAttribLocation(program, "aPosition");
  colorLocation = gl.getAttribLocation(program, "aColor");
  lightLocation = gl.getAttribLocation(program, "aLight");
  normalLocation = gl.getAttribLocation(program, "aNormal");
  uvLocation = gl.getAttribLocation(program, "aUV");
  materialLocation = gl.getAttribLocation(program, "aMaterial");
  tileLocation = gl.getAttribLocation(program, "aTileRect");
  viewProjectionLocation = gl.getUniformLocation(program, "uViewProjection");
  cameraLocation = gl.getUniformLocation(program, "uCamera");
  timeLocation = gl.getUniformLocation(program, "uTime");
  daylightLocation = gl.getUniformLocation(program, "uDaylight");
  surfacePassLocation = gl.getUniformLocation(program, "uSurfacePass");
  shadowPassLocation = gl.getUniformLocation(program, "uShadowPass");
  vfxPassLocation = gl.getUniformLocation(program, "uVfxPass");
  miningProgressLocation = gl.getUniformLocation(program, "uMiningProgress");
  terrainSkyColorLocation = gl.getUniformLocation(program, "uSkyColor");
  terrainSkyHorizonColorLocation = gl.getUniformLocation(program, "uSkyHorizonColor");
  terrainGroundBounceLocation = gl.getUniformLocation(program, "uGroundBounce");
  terrainSunDirectionLocation = gl.getUniformLocation(program, "uSunDirection");
  terrainSunColorLocation = gl.getUniformLocation(program, "uSunColor");
  terrainSunIntensityLocation = gl.getUniformLocation(program, "uSunIntensity");
  terrainAmbientStrengthLocation = gl.getUniformLocation(program, "uAmbientStrength");
  terrainAmbientDesaturationLocation = gl.getUniformLocation(program, "uAmbientDesaturation");
  terrainBumpStrengthLocation = gl.getUniformLocation(program, "uBumpStrength");
  terrainDetailStrengthLocation = gl.getUniformLocation(program, "uDetailStrength");
  terrainDetailScaleLocation = gl.getUniformLocation(program, "uDetailScale");
  terrainWaterDetailLocation = gl.getUniformLocation(program, "uWaterDetail");
  terrainCameraPositionLocation = gl.getUniformLocation(program, "uCameraPosition");
  terrainNearLocation = gl.getUniformLocation(program, "uNear");
  terrainFarLocation = gl.getUniformLocation(program, "uFar");
  atlasLocation = gl.getUniformLocation(program, "uAtlas");
  terrainCloudMapLocation = gl.getUniformLocation(program, "uCloudMap");
  terrainSceneDepthLocation = gl.getUniformLocation(program, "uSceneDepth");
  shadowMapLocation = gl.getUniformLocation(program, "uShadowMap");
  shadowDiskLocation = gl.getUniformLocation(program, "uShadowDisk");
  lightViewProjectionLocation = gl.getUniformLocation(program, "uLightViewProjection");
  shadowTexelSizeLocation = gl.getUniformLocation(program, "uShadowTexelSize");
  shadowRadiusLocation = gl.getUniformLocation(program, "uShadowRadius");
  shadowFadeLocation = gl.getUniformLocation(program, "uShadowFade");
  shadowStrengthLocation = gl.getUniformLocation(program, "uShadowStrength");
  shadowTapsLocation = gl.getUniformLocation(program, "uShadowTaps");
  shadowFloorLocation = gl.getUniformLocation(program, "uShadowFloor");
  // Mipmaps stay off until the padded atlas is certified free of foreign tile
  // contamination on a throwaway mip chain, so a bad atlas can never ship. The
  // WebGPU path certifies on its own device before it builds its atlas, and its
  // verdict is already in `atlasMipmapVerdict` by the time diagnostics read it.
  atlasMipmapVerdict = certifyAtlasMipmaps(gl, BLOCK_COLORS);
  atlasTexture = createTextureAtlas(gl, BLOCK_COLORS, {
    mipmaps: true,
    mipmapSafe: atlasMipmapVerdict.safe,
  });
  gl.useProgram(program);
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, atlasTexture);
  gl.uniform1i(atlasLocation, TERRAIN_TEXTURE_UNIT.atlas);
  gl.uniform1i(terrainCloudMapLocation, TERRAIN_TEXTURE_UNIT.cloudMap);
  gl.uniform1i(shadowMapLocation, TERRAIN_TEXTURE_UNIT.shadowMap);
  gl.uniform1i(shadowDiskLocation, TERRAIN_TEXTURE_UNIT.shadowDisk);
  gl.uniform1i(terrainSceneDepthLocation, TERRAIN_TEXTURE_UNIT.sceneDepth);

  const skyProgramAttempt = createPermutedProgram(
    WEBGL_SKY_VERTEX_SHADER,
    createWebglSkyFragmentShader({ volumetricClouds: shaderQuality >= 0.5 }),
    WEBGL_SKY_VERTEX_SHADER,
    WEBGL_SKY_FALLBACK_FRAGMENT_SHADER,
  );
  skyProgram = skyProgramAttempt.program;
  if (skyProgramAttempt.usedFallback) shaderQuality = 0;
  skyPositionBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, skyPositionBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  skyPositionLocation = gl.getAttribLocation(skyProgram, "aPosition");
  skyCameraForwardLocation = gl.getUniformLocation(skyProgram, "uCameraForward");
  skyCameraRightLocation = gl.getUniformLocation(skyProgram, "uCameraRight");
  skyCameraUpLocation = gl.getUniformLocation(skyProgram, "uCameraUp");
  skyCameraPositionLocation = gl.getUniformLocation(skyProgram, "uCameraPosition");
  skyColorLocation = gl.getUniformLocation(skyProgram, "uSkyColor");
  skyHorizonColorLocation = gl.getUniformLocation(skyProgram, "uSkyHorizonColor");
  skySunDirectionLocation = gl.getUniformLocation(skyProgram, "uSunDirection");
  skySunColorLocation = gl.getUniformLocation(skyProgram, "uSunColor");
  skyAspectLocation = gl.getUniformLocation(skyProgram, "uAspect");
  skyTanHalfFovLocation = gl.getUniformLocation(skyProgram, "uTanHalfFov");
  skyDaylightLocation = gl.getUniformLocation(skyProgram, "uDaylight");
  skyTimeLocation = gl.getUniformLocation(skyProgram, "uTime");
  skyCloudStepsLocation = gl.getUniformLocation(skyProgram, "uCloudSteps");
  skyCloudLightStepsLocation = gl.getUniformLocation(skyProgram, "uCloudLightSteps");
  skyCloudCoverageLocation = gl.getUniformLocation(skyProgram, "uCloudCoverage");
  skyWindSpeedLocation = gl.getUniformLocation(skyProgram, "uWindSpeed");
  cloudTexture = gl.createTexture();
  gl.activeTexture(gl.TEXTURE1);
  gl.bindTexture(gl.TEXTURE_2D, cloudTexture);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texImage2D(
    gl.TEXTURE_2D,
    0,
    gl.RGBA,
    CLOUD_TEXTURE_SIZE,
    CLOUD_TEXTURE_SIZE,
    0,
    gl.RGBA,
    gl.UNSIGNED_BYTE,
    createCloudTextureData(),
  );
  gl.bindTexture(gl.TEXTURE_2D, null);

  // ---------------------------------------------------------------------------
  // Presentation pipeline: HDR scene target, bloom, god rays, tonemap and
  // grade, plus a single-cascade sun shadow map. Both degrade independently:
  // no post target means the scene draws straight to the canvas, and no
  // sampleable depth means no shadow cascade and no god rays.
  // ---------------------------------------------------------------------------
  // A `?graphics=` override pins the tier and switches adaptation off. It is how
  // a player forces a look, and how the visual smoke test proves which effect
  // belongs to which tier instead of guessing. The saved Options preference is
  // the next authority, and only when the URL is silent: a URL is a deliberate
  // per-session instruction and must not be shadowed by stored state.
  const graphicsParam = parseVisualQuality(sessionParams.get("graphics"));
  const savedGraphics = options.graphicsQuality;
  const graphicsOverride = graphicsParam ?? (savedGraphics === "auto" ? null : parseVisualQuality(savedGraphics));
  // The pacer owns the cap and the learned display cadence, and the quality
  // controller is pointed at whatever period it currently considers the target.
  // The two have to agree: a controller judging the frame rate against its own
  // assumption is what makes auto sit still at a tier the machine cannot hold.
  framePacer = createFramePacer({ limit: options.fpsLimit });
  visualQuality = createVisualQualityController({
    // A software rasteriser cannot afford the top tier; the visual smoke test
    // opts in explicitly so it still exercises the advanced path.
    initial: graphicsOverride ?? (isSoftwareRenderer(rendererName)
      && !(testMode && sessionParams.get("quality") === "high")
      ? 1
      : VISUAL_QUALITY_TIERS.length - 1),
    auto: graphicsOverride === null,
    targetFrameMs: framePacer.targetFrameMs,
  });
  if (graphicsOverride !== null) visualQuality.setLevel(graphicsOverride);
  postPipeline = createPostPipeline(gl, { quality: shaderQuality >= 0.5 ? 1 : 0 });
  shadowPass = createSunShadowPass(gl, {
    mapSize: visualQuality.tier.shadowMapSize,
    depthSampling: postPipeline.depthSampling,
  });
  shadowDiskTexture = createVogelDiskTexture(gl, 64);
  // A 1x1 white stand-in keeps the shadow sampler bound on contexts that cannot
  // provide a depth texture, where uShadowStrength is pinned to zero anyway.
  shadowFallbackTexture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, shadowFallbackTexture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([255, 255, 255, 255]));
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.bindTexture(gl.TEXTURE_2D, null);
  }

  const lightViewProjection = new Float32Array(16);
  const sunScreenPosition = [0.5, 0.5];
  let sunVisibleForGodrays = 0;
  // Exposed so the visual smoke test can assert the sun really is where the
  // god-ray stage thinks it is, instead of trusting a constant.
  let lastSunDirection = [0, 1, 0];

  // Distant terrain: a quadtree of cached LOD tiles generated by its own worker
  // from the Bend `Horizon.lod_points` sampler (see web/lod-terrain.js).
  let lodWorker = null;
  let lodWorkerFailures = 0;
  const lodTerrain = createLodTerrain({
    chunkSize: CHUNK_SIZE,
    requestTile: (job) => {
      lodWorker?.postMessage({
        type: "lodTile",
        ...job,
        seed: SEED,
        chunkSize: CHUNK_SIZE,
        waterSurface: asNumber(World.sea_level()) + 1,
      });
    },
  });
  if (LOD_DISTANCE > 0) {
    try {
      lodWorker = new Worker("/lod-worker.js", { type: "module" });
      lodWorker.onmessage = (event) => {
        const message = event.data;
        if (message?.type !== "lodTile") return;
        if (message.error !== undefined) {
          lodWorkerFailures += 1;
          lodTerrain.fail(message.id);
          console.warn(`LOD tile failed: ${message.error}`);
          return;
        }
        if (lodTerrain.receive(message.id, message.sections)) streamingMeshScheduler?.request();
      };
      lodWorker.onerror = (event) => {
        // Distant terrain is optional: without its worker the game keeps
        // running on the streamed chunks alone.
        lodWorkerFailures += 1;
        console.warn(`LOD worker unavailable: ${event.message ?? "error"}`);
        lodWorker = null;
        lodTerrain.configure({ renderDistance: CHUNK_RENDER_RADIUS, lodDistance: 0 });
      };
    } catch (error) {
      lodWorker = null;
    }
  }
  lodTerrain.configure({ renderDistance: CHUNK_RENDER_RADIUS, lodDistance: lodWorker === null ? 0 : LOD_DISTANCE });

  // Returns true when the drawn LOD set changed and needs a publication.
  function rebuildHorizon() {
    return lodTerrain.update(player.x, player.z);
  }

  // The LOD sections to publish next to the real chunks. A real chunk that is
  // drawn hides its stand-in, which reappears if the chunk is unloaded.
  function horizonSections(realChunks) {
    return lodTerrain.sections(new Set(realChunks.map((chunk) => String(chunk.key))));
  }

  function rotatePartPoint(x, y, z, part) {
    // Exact composition: the orbit step already placed center/pivot in the
    // world, so un-rotate into the box frame, pitch about the local pivot,
    // then yaw back. Keeps swinging limbs rigid at any facing.
    const yawSin = Math.sin(part.yaw);
    const yawCos = Math.cos(part.yaw);
    const pitchSin = Math.sin(part.pitch);
    const pitchCos = Math.cos(part.pitch);
    const relX = x - part.c[0];
    const relY = y - part.c[1];
    const relZ = z - part.c[2];
    // Into box frame (inverse yaw).
    const localX = relX * yawCos + relZ * yawSin;
    const localY = relY;
    const localZ = -relX * yawSin + relZ * yawCos;
    let outX = localX;
    let outY = localY;
    let outZ = localZ;
    if (part.pitch !== 0) {
      const pivot = part.pivot ?? part.c;
      const pivotX = (pivot[0] - part.c[0]) * yawCos + (pivot[2] - part.c[2]) * yawSin;
      const pivotY = pivot[1] - part.c[1];
      const pivotZ = -(pivot[0] - part.c[0]) * yawSin + (pivot[2] - part.c[2]) * yawCos;
      const armY = localY - pivotY;
      const armZ = localZ - pivotZ;
      outX = localX;
      outY = pivotY + armY * pitchCos - armZ * pitchSin;
      outZ = pivotZ + armY * pitchSin + armZ * pitchCos;
    }
    // Back to world (yaw).
    return [
      part.c[0] + outX * yawCos - outZ * yawSin,
      part.c[1] + outY,
      part.c[2] + outX * yawSin + outZ * yawCos,
    ];
  }

  function appendBox(positions, colors, lights, normals, uvs, tiles, part) {
    const uniformUv = part.faceTiles === undefined ? atlasUV(part.tile) : null;
    const localUv = [[0, 0], [1, 0], [1, 1], [0, 1]];
    for (let faceIndex = 0; faceIndex < FACES.length; faceIndex += 1) {
      const uv = uniformUv ?? atlasUV(part.faceTiles[faceIndex]);
      const tileRect = part.faceTiles !== undefined && faceIndex >= 2
        ? [uv[0], uv[5], uv[4], uv[1]]
        : [uv[0], uv[1], uv[4], uv[5]];
      const color = litEntityFaceColor(part.tint, faceIndex, 1, TERRAIN_FACE_SHADES[faceIndex]);
      const faceDir = FACES[faceIndex].dir;
      for (const cornerIndex of [0, 1, 2, 0, 2, 3]) {
        const corner = FACES[faceIndex].corners[cornerIndex];
        const [px, py, pz] = rotatePartPoint(
          part.c[0] + (corner[0] - 0.5) * part.s[0],
          part.c[1] + (corner[1] - 0.5) * part.s[1],
          part.c[2] + (corner[2] - 0.5) * part.s[2],
          part,
        );
        positions.push(px, py, pz);
        colors.push(color[0], color[1], color[2]);
        // Entities are not part of the block light grid, so they read as
        // unoccluded and fully sky-lit; the shadow map grounds them instead.
        lights.push(1, 1);
        normals.push(faceDir[0], faceDir[1], faceDir[2]);
        uvs.push(localUv[cornerIndex][0], localUv[cornerIndex][1]);
        tiles.push(...tileRect);
      }
    }
  }

  function appendMiningCrack(positions, colors, lights, normals, uvs, tiles) {
    if (miningState === null) return;
    const target = raycast(world, player);
    if (target === null || target.place === null) return;
    if (target.hit[0] !== miningState.x || target.hit[1] !== miningState.y || target.hit[2] !== miningState.z) return;
    const normal = [
      target.place[0] - target.hit[0],
      target.place[1] - target.hit[1],
      target.place[2] - target.hit[2],
    ];
    const faceIndex = FACES.findIndex((face) => face.dir.every((value, index) => value === normal[index]));
    if (faceIndex === -1) return;
    const face = FACES[faceIndex];
    const corners = face.corners.map(([x, y, z]) => [
      target.hit[0] + x + normal[0] * 0.004,
      target.hit[1] + y + normal[1] * 0.004,
      target.hit[2] + z + normal[2] * 0.004,
    ]);
    const localUv = [[0, 0], [1, 0], [1, 1], [0, 1]];
    for (const cornerIndex of [0, 1, 2, 0, 2, 3]) {
      const corner = corners[cornerIndex];
      positions.push(corner[0], corner[1], corner[2]);
      colors.push(1, 1, 1);
      lights.push(1, 1);
      normals.push(normal[0], normal[1], normal[2]);
      uvs.push(localUv[cornerIndex][0], localUv[cornerIndex][1]);
      tiles.push(-1, -1, -1, -1);
    }
  }

  function appendShadow(positions, colors, lights, normals, uvs, entity) {
    const shadow = entityShadow(entity);
    positions.push(...shadow.positions);
    for (let index = 0; index < 6; index += 1) {
      colors.push(1, 1, 1);
      lights.push(1, 1);
      normals.push(0, 1, 0);
    }
    uvs.push(0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1);
  }

  let dynamicStatsTick = -1;

  function rebuildDynamicMesh(time) {
    const positions = [];
    const colors = [];
    const lights = [];
    const normals = [];
    const uvs = [];
    const tiles = [];
    const shadowPositions = [];
    const shadowColors = [];
    const shadowLights = [];
    const shadowNormals = [];
    const shadowUvs = [];
    for (const mob of mobs) {
      if (!mob.alive) continue;
      appendShadow(shadowPositions, shadowColors, shadowLights, shadowNormals, shadowUvs, mob);
      const flashed = worldTime - (mobFlash.get(mob.id) ?? -10) < 0.3;
      const heading = Math.atan2(mob.headingX ?? 0, -(mob.headingZ ?? -1));
      for (const part of mobBoxes(mob, time, heading, flashed)) {
        appendBox(positions, colors, lights, normals, uvs, tiles, part);
      }
    }
    for (const villager of villagers) {
      appendShadow(shadowPositions, shadowColors, shadowLights, shadowNormals, shadowUvs, villager);
      for (const part of villagerBoxes(villager, time, faceYaw(villager.x, villager.z, player.x, player.z))) {
        appendBox(positions, colors, lights, normals, uvs, tiles, part);
      }
    }
    for (const drop of drops) {
      appendShadow(shadowPositions, shadowColors, shadowLights, shadowNormals, shadowUvs, drop);
      for (const part of dropBoxes(drop, time)) appendBox(positions, colors, lights, normals, uvs, tiles, part);
    }
    for (const remote of remotePlayers.views(performance.now())) {
      appendShadow(shadowPositions, shadowColors, shadowLights, shadowNormals, shadowUvs, remote);
      for (const part of playerBoxes(remote, time)) appendBox(positions, colors, lights, normals, uvs, tiles, part);
    }
    appendMiningCrack(positions, colors, lights, normals, uvs, tiles);
    shadowVertexCount = shadowPositions.length / 3;
    shadowQuadCount = shadowVertexCount / 6;
    dynamicVertexCount = positions.length / 3;
    dynamicQuadCount = dynamicVertexCount / 6;
    if (gpuRenderer !== null) {
      gpuRenderer.uploadDynamic({
        dynamic: {
          positions: new Float32Array(positions),
          colors: new Float32Array(colors),
          lights: new Float32Array(lights),
          normals: new Float32Array(normals),
          uvs: new Float32Array(uvs),
          tiles: new Float32Array(tiles),
        },
        shadow: {
          positions: new Float32Array(shadowPositions),
          colors: new Float32Array(shadowColors),
          lights: new Float32Array(shadowLights),
          normals: new Float32Array(shadowNormals),
          uvs: new Float32Array(shadowUvs),
          tiles: new Float32Array((shadowPositions.length / 3) * 4),
        },
      });
    } else {
      gl.bindBuffer(gl.ARRAY_BUFFER, dynamicPositionBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, dynamicColorBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(colors), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, dynamicLightBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(lights), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, dynamicNormalBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(normals), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, dynamicUvBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(uvs), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, dynamicTileBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(tiles), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, shadowPositionBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(shadowPositions), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, shadowColorBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(shadowColors), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, shadowLightBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(shadowLights), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, shadowNormalBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(shadowNormals), gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, shadowUvBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(shadowUvs), gl.DYNAMIC_DRAW);
    }
    visibleFaceCount = terrainQuadCount + waterQuadCount + dynamicQuadCount;
    const statsTick = Math.floor(time * 4);
    if (statsTick !== dynamicStatsTick) {
      dynamicStatsTick = statsTick;
      statsEl.textContent = `${blockCount} blocks · ${visibleFaceCount} faces · ${world.activeChunkCount()} chunks · ${mobs.filter((mob) => mob.alive).length} mobs · ${villagers.length} villagers · ${drops.length} drops`;
    }
  }

  function appendTexturedQuad(positions, colors, lights, normals, uvs, quad, materials = null, tiles = null) {
    const color = faceColorGrade(quad.faceIndex, quad.x, quad.z);
    const corners = quadCorners(quad);
    const normal = FACE_NORMALS[quad.faceIndex] ?? FACE_NORMALS[0];
    const uv = atlasUV(blockFaceTileAt(quad.block, quad.faceIndex, quad.x, quad.z));
    const tileRect = quad.faceIndex >= 2
      ? [uv[0], uv[5], uv[4], uv[1]]
      : [uv[0], uv[1], uv[4], uv[5]];
    const localUv = [[0, 0], [quad.width, 0], [quad.width, quad.height], [0, quad.height]];
    const lightLevel = blockLightLevel(quad.light);
    for (const cornerIndex of [0, 1, 2, 0, 2, 3]) {
      const corner = corners[cornerIndex];
      positions.push(corner[0], corner[1], corner[2]);
      colors.push(color[0], color[1], color[2]);
      lights.push(cornerOcclusion(quad.ao?.[cornerIndex]), lightLevel);
      normals.push(normal[0], normal[1], normal[2]);
      uvs.push(localUv[cornerIndex][0], localUv[cornerIndex][1]);
      if (tiles !== null) tiles.push(...tileRect);
      if (materials !== null) {
        materials.push(quad.block === 7 ? 1 : quad.block === 21 ? 2 : quad.block === 24 ? 3 : 10 + quad.block);
      }
    }
  }

  function rebuildMesh() {
    terrainImmediateDirty = false;
    terrainMeshCache.rebuildDirty();
    const terrain = terrainMeshCache.snapshot(false);
    if (terrain.chunks.some((chunk) => chunk.key === spawnChunkKey)) spawnMeshReady = true;
    if (!terrainMeshCache.pending && hiddenTerrainBlocks.size > 0) hiddenTerrainBlocks.clear();
    blockCount = terrain.blockCount;
    const chunks = [
      ...(terrain.chunks ?? []),
      ...horizonSections(terrain.chunks ?? []),
    ];
    if (gpuRenderer !== null) {
      // An edit keeps the resident set and only replaces the chunks whose
      // vertex data changed; streaming changes retire buffers and resync.
      lastGpuChunkUpdate = gpuRenderer.updateChunks(chunks);
      terrainQuadCount = chunks.reduce((sum, chunk) => sum + (chunk.vertexData?.opaque?.quadCount ?? 0), 0);
      waterQuadCount = chunks.reduce((sum, chunk) => sum + (chunk.vertexData?.water?.quadCount ?? 0), 0);
      terrainVertexCount = chunks.reduce(
        (sum, chunk) => sum + ((chunk.vertexData?.opaque?.positions?.length ?? 0) / 3),
        0,
      );
      waterVertexCount = chunks.reduce(
        (sum, chunk) => sum + ((chunk.vertexData?.water?.positions?.length ?? 0) / 3),
        0,
      );
      return;
    }
    lastGpuChunkUpdate = glChunkBuffers.update(chunks);
    const totals = glChunkBuffers.totals();
    terrainQuadCount = totals.opaqueQuads;
    waterQuadCount = totals.waterQuads;
    terrainVertexCount = totals.opaqueVertices;
    waterVertexCount = totals.waterVertices;
  }

  streamingMeshScheduler = createMeshRebuildScheduler(
    () => {
      rebuildHorizon();
      rebuildMesh();
    },
    (callback) => window.setTimeout(() => window.requestAnimationFrame(callback), 100),
  );

  // Matrix and vector helpers live in ./gl-matrix.js so the shadow, post and
  // terrain passes all build matrices the same way.
  function resizeCanvas() {
    const scale = Math.min(window.devicePixelRatio || 1, 2);
    const width = Math.floor(canvas.clientWidth * scale);
    const height = Math.floor(canvas.clientHeight * scale);
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
  }

  const spawnContract = World.spawn_cell(SEED);
  const spawnCell = [Number(spawnContract.x), Number(spawnContract.z)];
  const spawnChunkKey = `${Math.floor(spawnCell[0] / Number(World.chunk_size()))},${Math.floor(spawnCell[1] / Number(World.chunk_size()))}`;
  const spawnHeight = Number(spawnContract.height);
  const player = createPlayer(spawnCell, spawnHeight);
  if (savedGame?.player !== null && typeof savedGame?.player === "object") {
    Object.assign(player, savedGame.player);
  }
  clampPlayer(player, Number(World.width()), Number(World.depth()));
  let visualSample = { x: player.x, z: player.z, time: performance.now() };
  let visualSpeed = 0;
  world.loadAround(spawnCell[0], spawnCell[1], undefined, 9);
  terrainMeshCache = createAsyncChunkMeshCache(world, requestMeshBuild, null, {
    maxTargetsPerJob: MESH_TARGET_BATCH_SIZE,
    // Both backends upload one buffer per chunk and never read a merged
    // snapshot, so the worker must not compose one on every edit.
    perChunkOnly: true,
  });
  const inventory = createInventory();
  if (Array.isArray(savedGame?.inventory) && savedGame.inventory.length === inventory.length) {
    inventory.splice(0, inventory.length, ...savedGame.inventory);
  }
  let equipmentState = savedGame?.equipment?.$ === "Equipment" ? savedGame.equipment : Equipment.empty();
  let selectedSlot = 0;
  let inventoryCursor = null;
  let inventoryCursorAmount = null;
  let craftingGrid = Array.isArray(savedGame?.craftingGrid) && savedGame.craftingGrid.length === 9
    ? savedGame.craftingGrid.map((item) => ({ ...item }))
    : Array.from({ length: 9 }, () => ({ block: 0, count: 0 }));
  let inventoryOpen = false;
  let furnaceWorldState = Furnaces.empty();
  let activeFurnace = null;
  let furnaceOpen = false;
  // On a multiplayer server the chests are the server's: this is a mirror of
  // them, updated from its broadcasts (see mirrorServerChest).
  let chestWorldState = multiplayer !== null
    ? multiplayer.chests.reduce((state, chest) => mirrorServerChest(state, chest), Chests.empty())
    : savedGame?.chests?.$ === "World" ? savedGame.chests : Chests.empty();
  let activeChest = null;
  let chestOpen = false;
  const held = new Set();
  const restoredEntities = restoreEntities(savedGame, null, null);
  let mobDomainState = PEACEFUL ? { $: "Nil" } : restoredEntities.mobs;
  if (!PEACEFUL && mobDomainState?.$ === "Con") {
    mobDomainState = Entities.remove_spawn_area(
      mobDomainState,
      BigInt(spawnCell[0]),
      BigInt(spawnCell[1]),
    );
  }
  let mobs = [];
  const mobFlash = new Map();
  let handSwingTime = -10;
  let villagerDomainState = restoreVillagers(savedGame, Villagers.spawn(SEED));
  let villagerPathGrid = null;
  function requestVillagerPathGrid() {
    ensureVillagerPathWorker();
    const requestId = ++villagerPathRequestId;
    villagerPathLatestRequestId = requestId;
    villagerPathPending = true;
    villagerPathWorkerRequests += 1;
    try {
      villagerPathWorker.postMessage({
        type: "pathGrid",
        requestId,
        seed: SEED,
        edits: world.getEdits(),
      });
    } catch {
      villagerPathPending = false;
      villagerPathWorkerRejects += 1;
    }
  }
  function scheduleVillagerPathGrid() {
    villagerPathLatestRequestId += 1;
    villagerPathGrid = null;
    if (villagerPathRequestTimer !== null) return;
    villagerPathRequestTimer = window.setTimeout(() => {
      villagerPathRequestTimer = null;
      requestVillagerPathGrid();
    }, 0);
  }
  scheduleVillagerPathGrid();
  let villagers = [];
  let villagerTick = Number(savedGame?.villagerTick ?? 0);
  let dropDomainState = restoredEntities.drops;
  let drops = [];
  let xpState = savedGame?.xp?.$ === "XP" ? savedGame.xp : Experience.empty();
  let simulationTerrainDirty = false;
  // A redstone tick that moved a block leaves the mesh showing the old cell, and
  // a lamp or a torch that changed state leaves the old colour in the vertex
  // buffer. Both are cleared when the circuit is drawn again.
  // Redstone runs at 20Hz, its own clock. The rest of the simulation runs at
  // 5Hz because crops and fluids do not need to be smoother than that, but a
  // two-tick repeater at 5Hz reads as a stutter rather than a delay.
  const REDSTONE_TICK_SECONDS = 0.05;
  let redstoneAccumulator = 0;
  let playerStreamingDirty = false;
  let playerSpawnReady = Boolean(savedGame?.player && typeof savedGame.player === "object");
  let entityBucketStats = { mobBuckets: 0, activeMobBuckets: 0, dropBuckets: 0, activeDropBuckets: 0 };
  let moveFrameCalls = 0;
  let moveFrameActive = false;
  let worldReady = false;
  let spawnMeshReady = false;
  let loadingProgressValue = -1;

  function updateWorldLoading() {
    if (worldReady) return;
    const initialChunkTarget = Math.min(9, world.activeChunkCount() + world.pendingChunkCount());
    const hydrated = Math.min(initialChunkTarget, world.activeChunkCount());
    const meshReady = terrainMeshCache !== undefined
      && terrainMeshCache !== null
      && !terrainMeshCache.pending
      && spawnMeshReady
      && terrainQuadCount > 0 ? 16 : 0;
    const progress = Math.min(100, Math.round((hydrated / Math.max(1, initialChunkTarget)) * 84 + meshReady));
    if (loadingProgressEl !== null && progress !== loadingProgressValue) {
      loadingProgressValue = progress;
      loadingProgressEl.setAttribute("aria-valuenow", String(progress));
      loadingProgressEl.firstElementChild?.style.setProperty("--loading-progress", String(progress / 100));
    }
    const spawnReady = playerSpawnReady
      && world.isActive(Math.floor(player.x), Math.floor(player.z))
      && terrainQuadCount > 0;
    if (!spawnReady) return;
    worldReady = true;
    // Loading/mesh hydration is reported separately; active-play percentiles
    // should not retain the first-frame stall from world bootstrap.
    frameMetrics = createFrameMetrics();
    if (loadingProgressEl !== null) {
      loadingProgressEl.setAttribute("aria-valuenow", "100");
      loadingProgressEl.firstElementChild?.style.setProperty("--loading-progress", "1");
    }
    document.body.classList.add("is-world-ready");
    worldLoadingEl?.setAttribute("aria-busy", "false");
    window.setTimeout(() => {
      if (worldLoadingEl !== null) worldLoadingEl.hidden = true;
    }, 420);
  }

  function invalidateVillagerPath(x, y, z) {
    if (x < 17 || x >= 45 || z < 19 || z >= 45 || y > 10) return;
    scheduleVillagerPathGrid();
  }

  function editValues(edits) {
    const values = new Map();
    for (let node = edits; node?.$ === "Con"; node = node.tail) {
      const edit = node.head;
      const x = Number(edit.x);
      const y = Number(edit.y);
      const z = Number(edit.z);
      values.set(`${x},${y},${z}`, Number(edit.block));
    }
    return values;
  }

  function activeEditChanges(previousEdits, nextEdits) {
    const previous = editValues(previousEdits);
    const changes = [];
    for (let node = nextEdits; node?.$ === "Con"; node = node.tail) {
      const edit = node.head;
      const x = Number(edit.x);
      const y = Number(edit.y);
      const z = Number(edit.z);
      const value = Number(edit.block);
      if (previous.get(`${x},${y},${z}`) === value || !world.isActive(x, z)) continue;
      changes.push({ x, y, z, value });
    }
    return changes;
  }

  function toggleDoorAt(x, y, z) {
    const current = blockAt(x, y, z);
    if (current !== 14 && current !== 15) return false;
    let bottom = y;
    if (bottom > 0 && (blockAt(x, bottom - 1, z) === 14 || blockAt(x, bottom - 1, z) === 15)) bottom -= 1;
    const next = current === 14 ? 15 : 14;
    if (bottom + 1 >= MAX_Y) return false;
    setBlock(x, bottom, z, next);
    setBlock(x, bottom + 1, z, next);
    invalidateVillagerPath(x, bottom, z);
    invalidateVillagerPath(x, bottom + 1, z);
    terrainMeshCache.invalidateBlock(x, z);
    rebuildMesh();
    return true;
  }

  function pinStoredFurnaces() {
    for (let node = Furnaces.entries(furnaceWorldState); node?.$ === "Con"; node = node.tail) {
      worldSimulation.pin(
        Math.floor(Number(node.head.x) / CHUNK_SIZE),
        Math.floor(Number(node.head.z) / CHUNK_SIZE),
      );
    }
  }

  function hasFurnaceInChunk(chunkX, chunkZ) {
    for (let node = Furnaces.entries(furnaceWorldState); node?.$ === "Con"; node = node.tail) {
      if (Math.floor(Number(node.head.x) / CHUNK_SIZE) === chunkX && Math.floor(Number(node.head.z) / CHUNK_SIZE) === chunkZ) return true;
    }
    return false;
  }

  // The redstone blocks, read off the one contract in world/redstone.bend rather
  // than repeated here, so the renderer, the interaction and the simulation can
  // never disagree about which ids are redstone's.
  function isRedstoneBlock(block) {
    return block >= redstoneIds.wire && block <= redstoneIds.stickyPiston;
  }

  // The blocks a player interacts with rather than places: a lever is flipped,
  // not placed, and a torch is a redstone torch. Everything else in the redstone
  // range is placed and broken like any other block.
  function isRedstoneInteractive(block) {
    return block === redstoneIds.lever;
  }

  function tickFluids() {
    return worldSimulation.tick().length > 0;
  }

  // Multiplayer world interactions: the server's simulation performs them
  // (within reach of this player's pose) and its edits arrive as server
  // batches; this client only settles the inventory from the answer.
  function sharedInteract(op, x, y, z, settle = () => {}) {
    multiplayer.interactRequest(op, [storageCoordinate(x), y, storageCoordinate(z)]).then(
      (result) => {
        settle(result);
        refreshInventoryUi();
        updateHud();
        saveGame();
      },
      () => setInventoryMessage("The server did not answer."),
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Redstone
  //
  // Redstone runs on its own faster clock than the rest of the simulation,
  // because a two-tick repeater has to be able to answer inside a tenth of a
  // second for a circuit to feel like a clock rather than a stutter. Every rule
  // is the contract's; this gathers the few world samples the machines need,
  // ticks once, and applies the world edits the piston asked for.
  // ---------------------------------------------------------------------------

  // A redstone block that should be lit right now, for the renderer.
  function redstoneLit(block, x, y, z) {
    if (block === redstoneIds.lamp) return lampLitAt(redstoneState, x, y, z);
    if (block === redstoneIds.torch) return torchLitAt(redstoneState, x, y, z);
    if (block === redstoneIds.head) {
      // A piston head is drawn as the piston that owns it, so it reads its
      // state from the base rather than carrying one of its own.
      return pistonExtendedAt(redstoneState, x, y, z);
    }
    return false;
  }

  // The power a dust cell is holding, for the renderer.
  function redstonePower(x, y, z) {
    return wirePowerAt(redstoneState, x, y, z);
  }

  // A block id a redstone component can be broken out of. Block 38 is a piston
  // head: the piston put it there, so breaking it drops the piston, not a head.
  function redstoneBlockAt(x, y, z) {
    const block = blockAt(x, y, z);
    return isRedstoneBlock(block) ? block : 0;
  }

  function tickRedstoneOnce() {
    const edits = tickRedstone(redstoneState, blockAt, inside);
    const batch = [];
    for (const edit of edits) {
      if (!inside(edit.x, edit.y, edit.z) || !world.isActive(edit.x, edit.z)) continue;
      const current = blockAt(edit.x, edit.y, edit.z);
      // A piston never moves a fluid or fire into place, and never clears a
      // block it did not put there: the contract decided, the world still gets
      // the last word on cells that moved out from under it.
      if (edit.value === 0 && !isRedstoneBlock(current)) continue;
      if (edit.value !== 0 && (isFluidBlock(current) || current === 24)) continue;
      batch.push(edit);
    }
    if (batch.length > 0) {
      setBlocks(batch);
      for (const change of batch) terrainMeshCache.invalidateBlock(change.x, change.z);
    }
    return batch.length > 0;
  }

  function seedWaterAt(x, y, z, level = 8) {
    if (multiplayer !== null) return sharedInteract("water", x, y, z);
    if (!worldSimulation.seedFluid(7, x, y, z, level)) return false;
    saveGame();
    rebuildMesh();
    return true;
  }

  function seedLavaAt(x, y, z, level = 8) {
    if (multiplayer !== null) return sharedInteract("lava", x, y, z);
    if (!worldSimulation.seedFluid(21, x, y, z, level)) return false;
    saveGame();
    rebuildMesh();
    return true;
  }

  function igniteFireAt(x, y, z) {
    if (multiplayer !== null) return sharedInteract("fire", x, y, z);
    if (!worldSimulation.ignite(x, y, z)) return false;
    saveGame();
    rebuildMesh();
    return true;
  }

  function collectFluidAt(x, y, z, block, fill) {
    const slot = furnaceSlot("empty_bucket");
    if (slot === -1 || blockAt(x, y, z) !== block) return false;
    if (multiplayer !== null) {
      return sharedInteract("collect", x, y, z, (result) => {
        if (!result.ok) return;
        const empty = furnaceSlot("empty_bucket");
        if (empty !== -1) (result.block === 21 ? fillLavaBucket : fillBucket)(inventory, empty);
      });
    }
    if (!fill(inventory, slot)) return false;
    worldSimulation.removeFluid(x, y, z);
    saveGame();
    rebuildMesh();
    return true;
  }

  function collectWaterAt(x, y, z) {
    return collectFluidAt(x, y, z, 7, fillBucket);
  }

  function collectLavaAt(x, y, z) {
    return collectFluidAt(x, y, z, 21, fillLavaBucket);
  }

  function placeFluidAt(x, y, z, block, bucket, empty) {
    const slot = furnaceSlot(bucket);
    if (slot === -1 || !inside(x, y, z) || blockAt(x, y, z) !== 0 || overlapsPlayer(player, x, y, z)) return false;
    if (multiplayer !== null) {
      return sharedInteract(block === 21 ? "lava" : "water", x, y, z, (result) => {
        const full = furnaceSlot(bucket);
        if (result.ok && full !== -1) empty(inventory, full);
      });
    }
    if (!world.isActive(x, z) || !empty(inventory, slot)) return false;
    worldSimulation.seedFluid(block, x, y, z, 8);
    saveGame();
    rebuildMesh();
    return true;
  }

  function placeWaterAt(x, y, z) {
    return placeFluidAt(x, y, z, 7, "water_bucket", emptyBucket);
  }

  function placeLavaAt(x, y, z) {
    return placeFluidAt(x, y, z, 21, "lava_bucket", emptyLavaBucket);
  }

  // Spawn reads the time of day, so resolve it before the one-shot mob spawn
  // instead of trusting the initial daylight constant.
  daylight = daylightForTime(worldTime);
  refreshMobs();
  villagers = villagerViews(villagerDomainState);
  if (savedGame?.furnaces?.$ === "World") furnaceWorldState = savedGame.furnaces;
  if (multiplayer !== null) {
    furnaceWorldState = multiplayer.furnaces.reduce((state, furnace) => mirrorServerFurnace(state, furnace), Furnaces.empty());
  }
  pinStoredFurnaces();
  worldSimulation.syncBlocks();

  function mobViews(list) {
    const views = [];
    for (let node = list; node?.$ === "Con"; node = node.tail) {
      const mob = node.head;
      views.push({
        id: Number(mob.id),
        kind: Number(mob.kind),
        x: Number(mob.x),
        y: Number(mob.y),
        z: Number(mob.z),
        headingX: Number(mob.heading_x ?? 0),
        headingZ: Number(mob.heading_z ?? -1),
        health: Number(mob.health),
        alive: mob.alive,
        // The domain's own fire flag, carried through untouched. A save written
        // before the flag existed normalises to false, so an old world never
        // loads with every mob already alight.
        burning: mob.burning === true,
      });
    }
    return views;
  }

  function villagerViews(list) {
    const views = [];
    for (let node = list; node?.$ === "Con"; node = node.tail) {
      const villager = node.head;
      views.push({
        id: Number(villager.id),
        profession: Number(villager.profession),
        x: Number(villager.x),
        y: Number(villager.y),
        z: Number(villager.z),
        homeX: Number(villager.home_x),
        homeZ: Number(villager.home_z),
        resting: villager.resting,
      });
    }
    return views;
  }

  function dropViews(list) {
    const views = [];
    for (let node = list; node?.$ === "Con"; node = node.tail) {
      const drop = node.head;
      views.push({
        id: Number(drop.id),
        item: Number(drop.item),
        x: Number(drop.x),
        y: Number(drop.y),
        z: Number(drop.z),
        amount: Number(drop.amount),
        velocityY: Number(drop.velocity_y ?? 0),
        settled: drop.settled ?? false,
      });
    }
    return views;
  }

  function splitActiveEntityBuckets(list, getPosition, kind) {
    const buckets = buildChunkBuckets(list, CHUNK_SIZE, getPosition);
    const centerX = Math.floor(player.x / CHUNK_SIZE);
    const centerZ = Math.floor(player.z / CHUNK_SIZE);
    const active = [];
    const dormant = [];
    for (const [key, bucket] of buckets) {
      const [chunkX, chunkZ] = key.split(",").map(Number);
      const target = Math.abs(chunkX - centerX) <= CHUNK_RENDER_RADIUS
        && Math.abs(chunkZ - centerZ) <= CHUNK_RENDER_RADIUS
        ? active
        : dormant;
      target.push(bucket);
    }
    entityBucketStats = {
      ...entityBucketStats,
      [`${kind}Buckets`]: buckets.size,
      [`active${kind[0].toUpperCase()}${kind.slice(1)}Buckets`]: active.length,
    };
    return {
      active: active.reduce(concatBendLists, { $: "Nil" }),
      dormant: dormant.reduce(concatBendLists, { $: "Nil" }),
    };
  }

  function mobRegionsFor(domainList) {
    const regions = [];
    for (let node = domainList; node?.$ === "Con"; node = node.tail) {
      const mob = node.head;
      const region = mobRegion(world, Number(mob.x), Number(mob.y), Number(mob.z));
      regions.push({
        $: "Region",
        blocks: region.blocks,
        origin_x: region.originX,
        origin_y: region.originY,
        origin_z: region.originZ,
        width: region.width,
        height: region.height,
        depth: region.depth,
      });
    }
    let list = { $: "Nil" };
    for (let index = regions.length - 1; index >= 0; index -= 1) {
      list = { $: "Con", head: regions[index], tail: list };
    }
    return list;
  }

  function stepMobsBudgeted(dt) {
    const partition = splitActiveEntityBuckets(
      mobDomainState,
      (mob) => ({ x: Number(mob.x), z: Number(mob.z) }),
      "mob",
    );
    // The same per-mob block window drives movement and the melee line-of-sight
    // query, so Bend reads one window per active mob per tick.
    const activeRegions = mobRegionsFor(partition.active);
    mobDomainState = concatBendLists(
      Entities.step_world(
        partition.active,
        player.x,
        player.z,
        dt,
        worldTime,
        BigInt(DOMAIN_COORDINATE_OFFSET),
        activeRegions,
      ),
      Entities.step_budgeted(partition.dormant, player.x, player.z, dt / 5, 32.0),
    );
    return activeRegions;
  }

  function refreshMobs() {
    if (mobDomainState === null) mobDomainState = PEACEFUL || multiplayer !== null
      ? { $: "Nil" }
      : Entities.spawn_for_player(
        SEED,
        daylight,
        0n,
        0n,
        World.width(),
        World.depth(),
        BigInt(spawnCell[0]),
        BigInt(spawnCell[1]),
        false,
      );
    mobs = mobViews(mobDomainState);
    if (dropDomainState === null) dropDomainState = Entities.empty_drops();
    drops = dropViews(dropDomainState);
  }

  dropGroundCache = createColumnHeightCache({ maxY: MAX_Y, blockAt, isSolid: isDropSolid });

  function groundSourcesForDrops(list = dropDomainState) {
    let grounds = { $: "Nil" };
    for (let node = list; node?.$ === "Con"; node = node.tail) {
      const drop = node.head;
      const x = Math.floor(Number(drop.x));
      const z = Math.floor(Number(drop.z));
      const floorY = dropGroundCache.get(x, z);
      // Entities.ground_y matches a drop's own x and z exactly, so the ground
      // source carries them; a cell-centre key only matched drops that sat on
      // a cell centre, and every other drop fell out of the world.
      grounds = {
        $: "Con",
        head: { $: "Ground", x: Number(drop.x), z: Number(drop.z), y: floorY },
        tail: grounds,
      };
    }
    return grounds;
  }

  function stepDrops(dt) {
    if (world.pendingChunkCount() > 0) return;
    if (dropDomainState?.$ !== "Con") return;
    const partition = splitActiveEntityBuckets(
      dropDomainState,
      (drop) => ({ x: Number(drop.x), z: Number(drop.z) }),
      "drop",
    );
    dropDomainState = concatBendLists(
      Entities.step_drops(partition.active, dt, groundSourcesForDrops(partition.active)),
      Entities.step_drops(partition.dormant, dt / 5, groundSourcesForDrops(partition.dormant)),
    );
    drops = dropViews(dropDomainState);
  }

  function updateMobs(dt) {
    if (mobDomainState === null) return false;
    if (!isPlayerAlive(player)) {
      showDeath();
      return true;
    }
    const activeRegions = stepMobsBudgeted(dt);
    const beforeSunlight = mobs;
    mobs = mobViews(mobDomainState);
    const sunlight = Entities.sunlight_damage(
      mobDomainState,
      world.getEdits(),
      SEED,
      daylight,
      dt,
      dropDomainState,
    );
    mobDomainState = sunlight.mobs;
    dropDomainState = sunlight.drops;
    mobs = mobViews(mobDomainState);
    drops = dropViews(dropDomainState);
    if (sunlight.hit) {
      let solarKills = 0;
      for (const previous of beforeSunlight) {
        const current = mobs.find((mob) => String(mob.id) === String(previous.id));
        if (previous.alive && current !== undefined && !current.alive) {
          solarKills += 1;
          killCount += 1;
          xpState = Experience.award(xpState, Number(previous.kind ?? 2));
          // A body the sun finished off collapses where it stood. Without this
          // the mob simply stops being drawn between two simulation ticks, which
          // is the one thing that makes a death read as a glitch.
          emitDeathPuff(vfx, previous.x, previous.y, previous.z, mobPuffTint(previous.kind), 18);
        }
      }
      if (solarKills > 0) {
        setInventoryMessage(`${solarKills} monster${solarKills === 1 ? "" : "s"} burned away in daylight.`);
      }
    }
    // Re-bucket after sunlight so a mob killed by the sun cannot contribute
    // damage on the same tick. Sunlight never moves a body, so the windows
    // built for the movement step still line up with the surviving order.
    const threatened = splitActiveEntityBuckets(
      mobDomainState,
      (mob) => ({ x: Number(mob.x), z: Number(mob.z) }),
      "mob",
    ).active;
    const threat = Number(Entities.threat_damage(
      threatened,
      player.x,
      player.y,
      player.z,
      BigInt(DOMAIN_COORDINATE_OFFSET),
      activeRegions,
    ));
    if (threat > 0) {
      const blocking = Equipment.blocks_damage(equipmentState)
        || itemId(selectedItem(inventory, selectedSlot)) === "shield";
      applyDamage(player, threat * (blocking ? 0.34 : 1) * dt);
      audio.play("hurt");
    }
    collectNearbyDrops();
    return true;
  }

  function updateVillagers(dt) {
    if (villagerPathGrid === null) return false;
    villagerDomainState = Villagers.step_near(
      villagerDomainState,
      SEED,
      villagerPathGrid,
      BigInt(villagerTick),
      dt,
      player.x,
      player.z,
      VILLAGER_SIMULATION_RADIUS,
    );
    villagerTick = (villagerTick + 1) % 24;
    villagers = villagerViews(villagerDomainState);
    const currentEdits = world.getEdits();
    const openedEdits = Villagers.open_doors(villagerDomainState, SEED, currentEdits);
    const doorResult = Villagers.update_doors_result(villagerDomainState, SEED, openedEdits, player.x, player.z);
    const nextEdits = Villagers.door_edits(doorResult);
    const changes = activeEditChanges(currentEdits, nextEdits);
    if (villagerEditsChanged(changes) && world.patchEdits(nextEdits, changes)) {
      world.loadAround(player.x, player.z);
      for (const change of changes) terrainMeshCache.invalidateBlock(change.x, change.z);
      scheduleVillagerPathGrid();
      return true;
    }
    return false;
  }

  function tradeNearestVillager() {
    let nearest = null;
    let nearestDistance = 3 * 3;
    for (const villager of villagers) {
      const dx = villager.x - player.x;
      const dz = villager.z - player.z;
      const distance = dx * dx + dz * dz;
      if (distance < nearestDistance) {
        nearest = villager;
        nearestDistance = distance;
      }
    }
    if (nearest === null) {
      setInventoryMessage("No villager is close enough.");
      return false;
    }
    const offer = Villagers.trade(villagerDomainState, BigInt(nearest.id), player.x, player.z);
    if (!offer.ok) {
      setInventoryMessage("This villager cannot trade right now.");
      return false;
    }
    const ok = tradeInventory(
      inventory,
      offer.cost_item,
      offer.cost_amount,
      offer.reward_item,
      offer.reward_amount,
    );
    setInventoryMessage(ok ? "Trade complete: rotten flesh for iron." : "You need more rotten flesh or inventory space.");
    if (ok) {
      refreshInventoryUi();
      updateHud();
    }
    return ok;
  }

  function sleepAtBed() {
    const result = Villagers.sleep(
      villagerDomainState,
      SEED,
      world.getEdits(),
      player.x,
      player.z,
      BigInt(villagerTick),
    );
    if (!result.ok) {
      setInventoryMessage("You can only sleep near a bed at night.");
      return false;
    }
    villagerTick = Number(result.next_tick);
    worldTime = 0;
    multiplayer?.sendMorning();
    setInventoryMessage("Good morning.");
    updateHud();
    return true;
  }

  function swingHand() {
    handSwingTime = worldTime;
  }

  // A mob comes apart in its own colours, so a zombie comes apart green and a
  // pig pink. The tints live in the roster next to the model they belong to, so
  // the puff and the body it replaces cannot drift apart.
  const HIT_SPARK_TINT = [1.0, 0.86, 0.52];

  function mobPuffTint(kind) {
    return mobKind(kind)?.puff ?? [0.8, 0.8, 0.8];
  }

  /**
   * What a mob sounds like when it is hurt. The voice is the only cue that tells
   * the player which of the things walking towards them fights back, and which
   * one is livestock that will bolt the moment it is struck.
   */
  function playMobHurtSound(kind) {
    audio.play(mobKind(kind)?.hurt ?? "oink");
  }

  // The single owner of everything a confirmed hit does to shared state. The
  // melee and arrow paths used to carry their own copy of this tail and had
  // already drifted: the bounded mobFlash prune only ran for melee, so a player
  // who only shot arrows grew the map for every mob ever hit, without limit.
  // `slainLabel` and `hitLabel` are the only part that legitimately differs.
  function applyMobHit(result, target, slainLabel, hitLabel) {
    mobDomainState = result.mobs;
    mobs = mobViews(mobDomainState);
    dropDomainState = result.drops;
    drops = dropViews(dropDomainState);
    const slain = mobs.find((mob) => String(mob.id) === String(target.id));
    if (slain !== undefined && !slain.alive) {
      killCount += 1;
      const xp = Number(Experience.xp_for_kind(Number(target.kind ?? 2)));
      xpState = Experience.award(xpState, Number(target.kind ?? 2));
      emitDeathPuff(vfx, target.x, target.y, target.z, mobPuffTint(target.kind), 16);
      setInventoryMessage(`${slainLabel} (+${xp} XP).`);
    } else {
      setInventoryMessage(hitLabel);
    }
    mobFlash.set(target.id, worldTime);
    if (mobFlash.size > 64) {
      for (const key of mobFlash.keys()) {
        if (worldTime - mobFlash.get(key) > 1) mobFlash.delete(key);
        if (mobFlash.size <= 32) break;
      }
    }
    crosshairEl?.animate(
      [
        { transform: "translate(-50%, -50%) scale(1)" },
        { transform: "translate(-50%, -50%) scale(1.8)" },
        { transform: "translate(-50%, -50%) scale(1)" },
      ],
      { duration: 180 },
    );
    refreshInventoryUi();
    rebuildDynamicMesh(worldTime);
    return true;
  }

  // Multiplayer hits: the server applies them to its mobs (Bend's rules, from
  // this player's pose) and answers; effects and XP follow its answer.
  function sharedAttack(target, damage, ranged, slainLabel, hitLabel, onHit = () => {}) {
    multiplayer.attackRequest({ mob: Number(target.id), damage: Number(damage), ranged }).then(
      (result) => {
        if (!result.hit) return;
        audio.play("pop");
        playMobHurtSound(target.kind);
        emitImpact(vfx, target.x, target.y + 0.9, target.z, HIT_SPARK_TINT, ranged ? 7 : 6);
        onHit();
        if (result.killed) {
          killCount += 1;
          const xp = Number(Experience.xp_for_kind(Number(result.kind || target.kind || 2)));
          xpState = Experience.award(xpState, Number(result.kind || target.kind || 2));
          emitDeathPuff(vfx, target.x, target.y, target.z, mobPuffTint(target.kind), 16);
          setInventoryMessage(`${slainLabel} (+${xp} XP).`);
        } else {
          setInventoryMessage(hitLabel);
        }
        mobFlash.set(target.id, worldTime);
        refreshInventoryUi();
        updateHud();
      },
      () => setInventoryMessage("The server did not answer."),
    );
    return true;
  }

  function attackMob(target, damage, selectedId) {
    if (mobDomainState === null) return false;
    if (multiplayer !== null) {
      return sharedAttack(target, damage, false, "Mob slain", "Mob hit.", () => {
        if (["wooden_sword", "stone_sword", "iron_sword", "diamond_sword"].includes(selectedId)) {
          useTool(inventory, selectedSlot);
        }
      });
    }
    const result = Entities.attack(mobDomainState, BigInt(target.id), damage, player.x, player.y, player.z, MELEE_ATTACK_RANGE, dropDomainState);
    if (!result.hit) return false;
    audio.play("pop");
    playMobHurtSound(target.kind);
    // The spark lands on the body that was hit, at chest height, so it reads as
    // contact rather than as a burst in the middle of the screen.
    emitImpact(vfx, target.x, target.y + 0.9, target.z, HIT_SPARK_TINT, 6);
    if (["wooden_sword", "stone_sword", "iron_sword", "diamond_sword"].includes(selectedId)) {
      useTool(inventory, selectedSlot);
    }
    return applyMobHit(result, target, "Mob slain", "Mob hit.");
  }

  function aimedMob(maxDistance = 4) {
    return firstAimedMob(
      [player.x, player.y + EYE_HEIGHT, player.z],
      cameraDirection(player),
      mobs,
      maxDistance,
    );
  }

  function attackNearestMob() {
    swingHand();
    if (mobDomainState === null) return false;
    const selected = selectedItem(inventory, selectedSlot);
    if (itemId(selected) === "bow") return shootArrow(selected);
    let nearest = null;
    let nearestDistance = 4 * 4;
    for (const mob of mobs) {
      if (!mob.alive) continue;
      const dx = mob.x - player.x;
      const dy = mob.y - player.y;
      const dz = mob.z - player.z;
      const distance = dx * dx + dy * dy + dz * dz;
      if (distance < nearestDistance) {
        nearest = mob;
        nearestDistance = distance;
      }
    }
    if (nearest === null) return false;
    const selectedId = itemId(selected);
    const damage = ["wooden_sword", "stone_sword", "iron_sword", "diamond_sword"].includes(selectedId)
      ? weaponDamage(selected)
      : handDamage();
    return attackMob(nearest, damage, selectedId);
  }

  function attackAimedMob() {
    if (mobDomainState === null) return false;
    const selected = selectedItem(inventory, selectedSlot);
    if (itemId(selected) === "bow") return shootArrow(selected);
    const target = aimedMob();
    if (target === null) return false;
    swingHand();
    const selectedId = itemId(selected);
    const damage = ["wooden_sword", "stone_sword", "iron_sword", "diamond_sword"].includes(selectedId)
      ? weaponDamage(selected)
      : handDamage();
    return attackMob(target, damage, selectedId);
  }

  function primaryAction(button) {
    if (button === 0 && attackAimedMob()) return true;
    return interact(button);
  }

  function shootArrow(selected) {
    if (mobDomainState === null) return false;
    const arrowSlot = inventory.findIndex((slot) => itemId(slot) === "arrow");
    if (arrowSlot === -1) {
      setInventoryMessage("No arrows.");
      return false;
    }
    const direction = cameraDirection(player);
    const eyeX = player.x;
    const eyeY = player.y + EYE_HEIGHT;
    const eyeZ = player.z;
    let target = null;
    let targetDistance = 16;
    for (const mob of mobs) {
      if (!mob.alive) continue;
      const vx = mob.x - eyeX;
      const vy = (mob.y ?? eyeY) + 0.9 - eyeY;
      const vz = mob.z - eyeZ;
      const dist = Math.hypot(vx, vy, vz);
      if (dist > 16 || dist < 0.001) continue;
      const cos = (vx * direction[0] + vy * direction[1] + vz * direction[2]) / dist;
      if (cos > 0.985 && dist < targetDistance) {
        target = mob;
        targetDistance = dist;
      }
    }
    if (target === null) {
      useTool(inventory, selectedSlot);
      consume(inventory, arrowSlot, 1);
      setInventoryMessage("Arrow missed.");
      refreshInventoryUi();
      return true;
    }
    if (multiplayer !== null) {
      useTool(inventory, selectedSlot);
      consume(inventory, arrowSlot, 1);
      refreshInventoryUi();
      return sharedAttack(target, 6.0, true, "Mob shot", "Arrow hit.");
    }
    const result = Entities.attack(mobDomainState, BigInt(target.id), 6.0, player.x, player.y, player.z, RANGED_ATTACK_RANGE, dropDomainState);
    if (!result.hit) return false;
    useTool(inventory, selectedSlot);
    consume(inventory, arrowSlot, 1);
    audio.play("pop");
    playMobHurtSound(target.kind);
    // An arrow used to land with no effect at all: the mob flashed for a third
    // of a second and nothing marked where the shot went.
    emitImpact(vfx, target.x, target.y + 0.9, target.z, HIT_SPARK_TINT, 7);
    return applyMobHit(result, target, "Mob shot", "Arrow hit.");
  }

  // Multiplayer pickups: the nearest server drop within reach is asked for; the
  // server removes it and hands it over (or refuses if someone was first).
  function sharedCollectDrops() {
    let list = Entities.empty_drops();
    for (const drop of drops) {
      if (pendingPickups.has(drop.id)) continue;
      list = Entities.cons_drop(Entities.make_drop(BigInt(drop.id), drop.item, drop.x, drop.y, drop.z, drop.amount), list);
    }
    const target = Entities.nearest_drop(list, player.x, player.y, player.z);
    if (!String(target.$).endsWith("DropFound")) return false;
    const item = itemNameFromId(target.item);
    const trial = inventory.map((entry) => ({ ...entry }));
    if (item === null || !collectItem(trial, item, Number(target.amount))) return false;
    const dropId = Number(target.id);
    pendingPickups.add(dropId);
    multiplayer.pickupRequest({ drop: dropId }).then(
      (result) => {
        pendingPickups.delete(dropId);
        const name = result.ok ? itemNameFromId(result.item) : null;
        if (name === null) return;
        if (!collectItem(inventory, name, Number(result.amount))) {
          multiplayer.sendDrop({ item: result.item, amount: result.amount, x: player.x, y: player.y + 0.6, z: player.z });
          return;
        }
        emitSparkle(vfx, player.x, player.y + 0.3, player.z, hexToRgb(itemColor({ item: name })), 6);
        setInventoryMessage(`${itemName({ item: name })} collected.`);
        refreshInventoryUi();
        updateHud();
      },
      () => pendingPickups.delete(dropId),
    );
    return true;
  }

  function collectNearbyDrops() {
    if (multiplayer !== null) return sharedCollectDrops();
    const target = Entities.nearest_drop(dropDomainState, player.x, player.y, player.z);
    if (target.$ !== "DropFound") return false;
    const item = itemNameFromId(target.item);
    if (item === null || !collectItem(inventory, item, Number(target.amount))) return false;
    // Sparkle at the player's feet: the drop is gone from the world, and without
    // a mark at the pickup point the item vanishes with nothing to explain it.
    emitSparkle(vfx, player.x, player.y + 0.3, player.z, hexToRgb(itemColor({ item })), 6);
    dropDomainState = Entities.remove_drop(dropDomainState, BigInt(target.id));
    drops = dropViews(dropDomainState);
    setInventoryMessage(`${itemName({ item })} collected.`);
    refreshInventoryUi();
    updateHud();
    return true;
  }

  function dropInventoryItem(slot = selectedSlot, stack = false) {
    const item = selectedItem(inventory, slot);
    const id = itemId(item);
    const amount = dropAmount(item?.count ?? 0, stack);
    if (id === null || amount <= 0 || ITEM_IDS[id] === undefined) return false;
    if (!consume(inventory, slot, amount)) return false;
    if (multiplayer !== null) {
      multiplayer.sendDrop({ item: ITEM_IDS[id], amount, x: player.x, y: player.y + 0.6, z: player.z });
      setInventoryMessage(`${itemName(item)} dropped${stack ? " (stack)" : ""}.`);
      refreshInventoryUi();
      updateHud();
      return true;
    }
    const dropId = BigInt(Date.now()) * 1000n + BigInt(drops.length);
    dropDomainState = Entities.cons_drop(
      Entities.make_drop(dropId, ITEM_IDS[id], player.x, player.y + 0.6, player.z, amount),
      dropDomainState,
    );
    drops = dropViews(dropDomainState);
    setInventoryMessage(`${itemName(item)} dropped${stack ? " (stack)" : ""}.`);
    refreshInventoryUi();
    updateHud();
    rebuildDynamicMesh(worldTime);
    return true;
  }

  let toastTimer = null;

  function showToast(message) {
    if (toastEl === null) return;
    toastEl.textContent = message;
    toastEl.hidden = false;
    if (toastTimer !== null) window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => {
      toastEl.hidden = true;
      toastTimer = null;
    }, 2200);
  }

  function spawnParticles(color = "#d8cfc0", count = 8) {
    if (particlesEl === null) return;
    for (let index = 0; index < count; index += 1) {
      const particle = document.createElement("span");
      particle.className = "particle";
      particle.style.setProperty("--particle-color", color);
      particle.style.setProperty("--particle-x", `${(Math.random() - 0.5) * 130}px`);
      particle.style.setProperty("--particle-y", `${(Math.random() - 0.5) * 100}px`);
      particlesEl.append(particle);
      window.setTimeout(() => particle.remove(), 500);
    }
  }

  /**
   * World-space effects. Every emitter below places its particles at a real
   * coordinate, so a block that shatters throws its own colour at the player
   * instead of a burst in the middle of the display that could have come from
   * anywhere on screen.
   *
   * The screen-space overlay above is still the right tool for feedback that is
   * genuinely about the player rather than the world - the red flash on death
   * has no position to point at.
   */
  const vfx = createVfx();

  // Fire is emitted per burning body, per frame, at a rate that reads as a
  // continuous plume rather than a flicker. The count is scaled by the frame
  // time so a slow machine emits fewer, not a denser plume running slow.
  const FLAME_RATE = 40;
  const SMOKE_RATE = 8;

  function updateVfx(dt) {
    vfx.update(dt);
    const flames = Math.min(6, Math.ceil(FLAME_RATE * dt));
    const puffs = Math.ceil(SMOKE_RATE * dt);
    for (const mob of mobs) {
      if (!mob.alive || !mob.burning) continue;
      // The plume wraps the body from the outside, because a particle behind the
      // mob's own front faces loses the depth test and the mob looks unlit. It
      // climbs the full height, because a ring at one height is a hoop.
      emitFlame(vfx, mob.x, mob.y, mob.z, flames, MOB_BODY.radius, MOB_BODY.height);
      if (puffs > 0 && vfx.random() < SMOKE_RATE * dt) {
        emitSmoke(vfx, mob.x, mob.y + MOB_BODY.height, mob.z, puffs, MOB_BODY.radius * 0.7);
      }
    }
  }

  /**
   * Fire is audible slightly before it is legible, but only from a body the
   * player could plausibly be looking at. A crackle from a burning zombie
   * across the map is a sound with no visible source, which reads as a bug
   * rather than as atmosphere, so the range gate is part of the effect and not
   * an optimisation.
   */
  const BURN_AUDIO_RANGE = 14;
  const BURN_AUDIO_INTERVAL = 0.45;
  let burnAudioCooldown = 0;

  function updateBurnAudio(dt) {
    if (burnAudioCooldown > 0) burnAudioCooldown -= dt;
    if (burnAudioCooldown > 0) return;
    for (const mob of mobs) {
      if (!mob.alive || !mob.burning) continue;
      const dx = mob.x - player.x;
      const dy = mob.y - player.y;
      const dz = mob.z - player.z;
      if (dx * dx + dy * dy + dz * dz > BURN_AUDIO_RANGE * BURN_AUDIO_RANGE) continue;
      if (audio.play("burn")) burnAudioCooldown = BURN_AUDIO_INTERVAL;
      return;
    }
  }

  /**
   * Build the particle batch and upload it. This runs inside the frame rather
   * than with the other dynamic geometry because the quads are camera-facing:
   * they need the basis the camera was just built from, and a mob billboard
   * baked against last frame's camera would swim when the player turned.
   */
  function rebuildVfxMesh(right, up) {
    const particles = vfx.particles;
    if (particles.length === 0) {
      vfxVertexCount = 0;
      return;
    }
    const batches = { positions: [], colors: [], lights: [], normals: [], uvs: [], tiles: [] };
    vfxVertexCount = appendVfxQuads(batches, particles, right, up);
    if (gpuRenderer !== null) {
      gpuRenderer.uploadVfx(batches);
      return;
    }
    gl.bindBuffer(gl.ARRAY_BUFFER, vfxPositionBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(batches.positions), gl.DYNAMIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER, vfxColorBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(batches.colors), gl.DYNAMIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER, vfxLightBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(batches.lights), gl.DYNAMIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER, vfxNormalBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(batches.normals), gl.DYNAMIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER, vfxUvBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(batches.uvs), gl.DYNAMIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER, vfxTileBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(batches.tiles), gl.DYNAMIC_DRAW);
  }

  function setInventoryMessage(message) {
    inventoryMessageEl.textContent = message;
    showToast(message);
  }

  const slotIconUrls = new Map();
  function slotIconUrl(name) {
    if (slotIconUrls.has(name)) return slotIconUrls.get(name);
    const texture = itemTexture(name);
    if (texture === null) return null;
    const iconCanvas = document.createElement("canvas");
    iconCanvas.width = 24;
    iconCanvas.height = 24;
    const iconContext = iconCanvas.getContext("2d");
    if (iconContext === null) return null;
    drawItemTexture(iconContext, texture, { size: 24, clear: true });
    const url = iconCanvas.toDataURL("image/png");
    slotIconUrls.set(name, url);
    return url;
  }

  function paintSlotIcons() {
    for (const swatch of document.querySelectorAll(".slot-swatch[data-item]")) {
      const name = swatch.dataset.item;
      if (name === undefined || name === "") continue;
      const url = slotIconUrl(name);
      if (url === null) continue;
      swatch.style.backgroundColor = "transparent";
      swatch.style.backgroundImage = `url("${url}")`;
    }
  }

  function slotMarkup(item, slot, className) {
    const id = itemId(item);
    const empty = id === null;
    const selected = slot === selectedSlot;
    const cursor = slot === inventoryCursor;
    const name = itemName(item);
    const count = item?.count || 0;
    return `<button class="${className}${selected ? " selected" : ""}${cursor ? " cursor" : ""}${empty ? " empty" : ""}"
      type="button" draggable="true" data-slot="${slot}" aria-label="Slot ${slot + 1}: ${name}, ${count}"
      aria-pressed="${selected || cursor}" title="${slot + 1}: ${name}">
      <span class="slot-key">${slot + 1}</span>
      <span class="slot-swatch" data-item="${empty ? "" : name}" style="--slot-color: ${itemColor(item)}"></span>
      <span class="slot-name">${name}</span>
      <span class="slot-count">${count || ""}</span>
      ${item?.durability ? `<span class="slot-durability" style="--durability: ${Math.max(0, Math.min(100, item.durability / item.durabilityMax * 100))}%"></span>` : ""}
    </button>`;
  }

  function renderHotbar() {
    hotbarEl.innerHTML = inventory
      .slice(0, HOTBAR_SIZE)
      .map((item, slot) => slotMarkup(item, slot, "hotbar-slot"))
      .join("");
  }

  function emptyCraftingGrid() {
    return Array.from({ length: 9 }, () => ({ block: 0, count: 0 }));
  }

  const equipmentSlots = [
    [0, "offhand", "Offhand"],
    [1, "helmet", "Helmet"],
    [2, "chest", "Chest"],
    [3, "legs", "Legs"],
    [4, "boots", "Boots"],
  ];

  function equipmentItem(field) {
    return Number(equipmentState[field] ?? 0);
  }

  function renderEquipment() {
    if (equipmentSlotsEl === null) return;
    equipmentSlotsEl.innerHTML = equipmentSlots.map(([slot, field, label]) => {
      const itemNumber = equipmentItem(field);
      const name = itemNumber === 0 ? label : (itemNameFromId(itemNumber) ?? label);
      const empty = itemNumber === 0;
      return `<button class="equipment-slot${empty ? " empty" : ""}" type="button" data-equipment-slot="${slot}"
        aria-label="${label}: ${name}">
        <span class="slot-swatch" data-item="${empty ? "" : name}" style="--slot-color: ${empty ? "transparent" : itemColor({ item: name })}"></span>
        <span class="slot-name">${name}</span>
      </button>`;
    }).join("");
    paintSlotIcons();
  }

  function equipInventorySlot(slot) {
    const item = selectedItem(inventory, slot);
    const id = itemId(item);
    if (id === null || ITEM_IDS[id] === undefined) return false;
    const result = Equipment.equip(equipmentState, ITEM_IDS[id]);
    if (!result.ok) return false;
    if (!consume(inventory, slot)) return false;
    equipmentState = result.equipment;
    setInventoryMessage(`${itemName(item)} equipped.`);
    refreshInventoryUi();
    saveGame();
    return true;
  }

  function unequipEquipmentSlot(slot) {
    const result = Equipment.take_slot(equipmentState, BigInt(slot));
    if (!result.ok) return false;
    const name = itemNameFromId(result.item);
    if (name === null) return false;
    const trial = inventory.map((item) => ({ ...item }));
    if (!collectItem(trial, name, 1)) {
      setInventoryMessage("Make room before removing equipment.");
      return false;
    }
    inventory.splice(0, inventory.length, ...trial);
    equipmentState = result.equipment;
    setInventoryMessage(`${name} unequipped.`);
    refreshInventoryUi();
    saveGame();
    return true;
  }

  function renderCraftingGrid() {
    if (craftingGridEl === null) return;
    craftingGridEl.innerHTML = craftingGrid.map((item, slot) => {
      const empty = itemId(item) === null;
      const name = itemName(item);
      return `<button class="inventory-slot${empty ? " empty" : ""}" type="button" data-crafting-slot="${slot}"
        aria-label="Crafting slot ${slot + 1}: ${name}, ${item?.count ?? 0}">
        <span class="slot-swatch" data-item="${empty ? "" : name}" style="--slot-color: ${itemColor(item)}"></span>
        <span class="slot-count">${item?.count || ""}</span>
      </button>`;
    }).join("");
    paintSlotIcons();
  }

  function returnCraftingGrid() {
    if (!craftingGrid.some((item) => itemId(item) !== null && Number(item.count) > 0)) return true;
    const trial = inventory.map((slot) => ({ ...slot }));
    for (const item of craftingGrid) {
      const name = itemId(item);
      const count = Number(item.count ?? 0);
      if (name === null || count <= 0) continue;
      if (!collectItem(trial, name, count)) {
        if (shapedStatusEl !== null) shapedStatusEl.textContent = "Make room before returning the crafting grid.";
        return false;
      }
    }
    inventory.splice(0, inventory.length, ...trial);
    craftingGrid = emptyCraftingGrid();
    return true;
  }

  function loadShapedRecipe(recipeId = shapedRecipeEl?.value ?? RECIPES[0]?.id) {
    if (recipeId === undefined) return false;
    if (!returnCraftingGrid()) return false;
    const pattern = shapedRecipePattern(recipeId);
    if (pattern === null) return false;
    const trial = inventory.map((slot) => ({ ...slot }));
    const nextGrid = emptyCraftingGrid();
    for (let index = 0; index < pattern.length; index += 1) {
      const itemNumber = pattern[index];
      if (itemNumber === 0) continue;
      const name = itemNameFromId(itemNumber);
      const sourceIndex = trial.findIndex((slot) => itemId(slot) === name && Number(slot.count) > 0);
      if (sourceIndex === -1 || !consume(trial, sourceIndex, 1)) {
        if (shapedStatusEl !== null) shapedStatusEl.textContent = `Missing ${name} for this pattern.`;
        return false;
      }
      const source = inventory.find((slot) => itemId(slot) === name);
      nextGrid[index] = source?.block !== undefined
        ? { block: source.block, count: 1 }
        : { item: name, count: 1 };
    }
    inventory.splice(0, inventory.length, ...trial);
    craftingGrid = nextGrid;
    if (shapedStatusEl !== null) shapedStatusEl.textContent = "Pattern loaded. Craft or return the ingredients.";
    refreshInventoryUi();
    return true;
  }

  function craftShapedRecipe(recipeId = shapedRecipeEl?.value ?? RECIPES[0]?.id) {
    if (recipeId === undefined) return false;
    const result = craftGrid(inventory, craftingGrid, recipeId);
    if (!result.ok) {
      if (shapedStatusEl !== null) shapedStatusEl.textContent = "The 3×3 pattern is not valid or the inventory is full.";
      return false;
    }
    craftingGrid = result.grid;
    const outputName = itemNameFromId(result.output) ?? "item";
    if (shapedStatusEl !== null) shapedStatusEl.textContent = `Crafted ${result.amount} ${outputName}.`;
    refreshInventoryUi();
    return true;
  }

  function renderCraftingOutput() {
    if (craftingOutputEl === null) return;
    const recipeId = shapedRecipeEl?.value ?? RECIPES[0]?.id;
    const recipe = RECIPES.find((entry) => entry.id === recipeId);
    if (recipe === undefined) {
      craftingOutputEl.textContent = "";
      return;
    }
    const output = recipe.output;
    const name = itemName(output.item);
    craftingOutputEl.innerHTML = `
      <span class="slot-swatch" data-item="${name}" style="--slot-color: ${itemColor(output.item)}"></span>
      <span class="slot-count">${output.count}</span>
    `;
    craftingOutputEl.setAttribute("aria-label", `Output: ${output.count} ${name}`);
  }

  function renderInventoryPanel() {
    inventorySlotsEl.innerHTML = inventory
      .map((item, slot) => slotMarkup(item, slot, "inventory-slot"))
      .join("");
    renderEquipment();
    if (shapedRecipeEl !== null && shapedRecipeEl.options.length === 0) {
      shapedRecipeEl.innerHTML = RECIPES.map((recipe) => `<option value="${recipe.id}">${recipe.name}</option>`).join("");
    }
    renderCraftingGrid();
    renderCraftingOutput();
    recipeListEl.innerHTML = RECIPES.map((recipe) => {
      const ingredients = recipe.ingredients
        .map(({ item, count }) => `${count} ${itemName(item)}`)
        .join(" + ");
      const available = canCraft(inventory, recipe.id);
      return `<button class="recipe-button" type="button" data-recipe="${recipe.id}" ${available ? "" : "disabled"}>
        <span class="recipe-name">${recipe.name}</span>
        <span class="recipe-cost">${ingredients}</span>
        <span class="recipe-output">→ ${recipe.output.count} ${itemName(recipe.output.item)}</span>
      </button>`;
    }).join("");
  }

  function refreshInventoryUi() {
    renderHotbar();
    renderInventoryPanel();
    paintSlotIcons();
    updateHeldItemUi();
  }

  function updateHeldItemUi() {
    heldItemViewEl.hidden = true;
    heldItemLabelEl.textContent = "";
  }

  function selectSlot(slot) {
    if (slot < 0 || slot >= HOTBAR_SIZE) return;
    cancelMining();
    selectedSlot = slot;
    refreshInventoryUi();
    updateHud();
  }

  function setInventoryOpen(open) {
    if (open) {
      held.clear();
      cancelMining();
    }
    if (open && furnaceOpen) setFurnaceOpen(false);
    if (open && chestOpen) setChestOpen(false);
    if (!open && !returnCraftingGrid()) return;
    inventoryOpen = open;
    inventoryCursor = null;
    inventoryCursorAmount = null;
    setDialogVisibility(inventoryPanelEl, inventoryToggleEl, open);
    inventoryToggleEl.setAttribute("aria-expanded", String(open));
    inventoryToggleEl.textContent = open ? "Close inventory (E)" : "Inventory (E)";
    if (open && document.pointerLockElement === canvas && typeof document.exitPointerLock === "function") {
      document.exitPointerLock();
    }
    renderInventoryPanel();
    if (open) paintSlotIcons();
  }

  function toggleInventory() {
    setInventoryOpen(!inventoryOpen);
  }

  function furnaceSlot(item) {
    return inventory.findIndex((slot) => itemId(slot) === item);
  }

  function activeFurnaceState() {
    if (activeFurnace === null) return null;
    const [x, y, z] = cellPosition(...activeFurnace);
    const lookup = Furnaces.at(furnaceWorldState, x, y, z);
    return lookup.$ === "FurnaceFound" ? lookup.furnace : null;
  }

  function setActiveFurnaceState(state) {
    if (activeFurnace === null) return false;
    const [x, y, z] = cellPosition(...activeFurnace);
    furnaceWorldState = Furnaces.set(furnaceWorldState, x, y, z, state);
    return true;
  }

  function updateFurnaceStatus() {
    const state = activeFurnaceState();
    if (state === null) {
      furnaceStatusEl.textContent = "Right-click a placed furnace to open its container.";
      return;
    }
    const input = Number(state.input_count);
    const fuel = Number(state.fuel_count);
    const output = Number(state.output_count);
    const progress = Number(state.progress);
    const burn = Number(state.burn);
    const inputName = itemNameFromId(Number(state.input)) ?? "empty";
    const outputName = itemNameFromId(Number(state.output)) ?? "empty";
    furnaceStatusEl.textContent = `Input: ${input} ${inputName} · fuel: ${fuel} coal · progress: ${progress}/8 · burn: ${burn} · output: ${output} ${outputName}`;
  }

  function setFurnaceOpen(open, location = activeFurnace) {
    if (open) {
      held.clear();
      cancelMining();
    }
    if (open) {
      if (location !== null) activeFurnace = location.map((value) => Math.trunc(value));
      if (activeFurnaceState() === null) {
        setInventoryMessage("Right-click a placed furnace first.");
        return false;
      }
    }
    furnaceOpen = open;
    furnaceToggleEl.hidden = furnaceControlHidden(activeFurnace, open);
    setDialogVisibility(furnacePanelEl, furnaceToggleEl, open);
    furnaceToggleEl.setAttribute("aria-expanded", String(open));
    furnaceToggleEl.textContent = open ? "Close furnace (R)" : "Furnace (R)";
    if (open) {
      inventoryOpen = false;
      setDialogVisibility(inventoryPanelEl, inventoryToggleEl, false);
      inventoryToggleEl.setAttribute("aria-expanded", "false");
      inventoryToggleEl.textContent = "Inventory (E)";
      if (chestOpen) setChestOpen(false);
      if (document.pointerLockElement === canvas && typeof document.exitPointerLock === "function") {
        document.exitPointerLock();
      }
    }
    updateFurnaceStatus();
    return true;
  }

  function toggleFurnace(location = activeFurnace) {
    return setFurnaceOpen(!furnaceOpen, location);
  }

  // Server furnaces are keyed by stored coordinates; the local furnace state
  // by signed cells.
  function mirrorServerFurnace(state, furnace) {
    const x = BigInt(worldCoordinate(furnace.pos[0]));
    const y = BigInt(furnace.pos[1]);
    const z = BigInt(worldCoordinate(furnace.pos[2]));
    if (furnace.state === null) return Furnaces.remove(state, x, y, z).world;
    // Furnaces.set only replaces an existing entry, so a new furnace is added first.
    return Furnaces.set(Furnaces.add(state, x, y, z).world, x, y, z, wireFurnaceToBend(furnace.state));
  }

  // Puts items on the ground at the player's feet, for items the server
  // handed over after the inventory filled up.
  function dropAtPlayer(numericItem, amount) {
    if (!(amount > 0)) return;
    if (multiplayer !== null) {
      multiplayer.sendDrop({ item: numericItem, amount, x: player.x, y: player.y + 0.6, z: player.z });
      return;
    }
    const dropId = BigInt(Date.now()) * 1000n + BigInt(drops.length);
    dropDomainState = Entities.cons_drop(
      Entities.make_drop(dropId, numericItem, player.x, player.y + 0.6, player.z, amount),
      dropDomainState,
    );
    drops = dropViews(dropDomainState);
    rebuildDynamicMesh(worldTime);
  }

  // Multiplayer furnace actions go through the server's Bend room, like chests:
  // a loaded item leaves the inventory at once and comes back if refused.
  function sharedFurnaceAction(action, current) {
    const pos = [storageCoordinate(activeFurnace[0]), activeFurnace[1], storageCoordinate(activeFurnace[2])];
    const refresh = () => {
      refreshInventoryUi();
      updateHud();
      updateFurnaceStatus();
      saveGame();
    };
    if (action === "input" || action === "fuel") {
      const name = action === "fuel" ? "coal" : (furnaceSlot("raw_iron") !== -1 ? "raw_iron" : "wheat");
      const slot = furnaceSlot(name);
      if (slot === -1) {
        setInventoryMessage(action === "fuel" ? "You need coal to fuel the furnace." : "You need raw iron or wheat to smelt.");
        return false;
      }
      const numericId = action === "fuel" ? 14 : ITEM_IDS[name];
      const loaded = action === "fuel"
        ? Furnace.load_fuel(current, numericId, 1n)
        : Furnace.load_input(current, numericId, 1n);
      if (!loaded.ok || !consume(inventory, slot)) {
        setInventoryMessage(action === "fuel" ? "The furnace fuel slot is full." : "The furnace input is full.");
        return false;
      }
      refresh();
      const giveBack = (message) => {
        collectItem(inventory, name, 1);
        setInventoryMessage(message);
        refresh();
      };
      multiplayer.furnaceRequest(action, { pos, item: numericId }).then(
        (result) => {
          if (!result.ok) giveBack(action === "fuel" ? "The furnace fuel slot is full." : "The furnace input is full.");
        },
        () => giveBack("The server did not answer; the item is back in your inventory."),
      );
      return true;
    }
    if (action === "output") {
      const ready = Number(current.output_count);
      const outputName = itemNameFromId(Number(current.output));
      if (ready === 0 || outputName === null) {
        setInventoryMessage("The furnace has no iron ingot ready.");
        return false;
      }
      const trial = inventory.map((entry) => ({ ...entry }));
      if (!collectItem(trial, outputName, ready)) {
        setInventoryMessage("Make room in the inventory first.");
        return false;
      }
      multiplayer.furnaceRequest("output", { pos }).then(
        (result) => {
          const taken = result.ok ? itemNameFromId(result.item) : null;
          if (taken === null) {
            setInventoryMessage("Someone got there first: the furnace is empty.");
          } else if (!collectItem(inventory, taken, Number(result.amount))) {
            dropAtPlayer(Number(result.item), Number(result.amount));
            setInventoryMessage(`No room for ${taken}: dropped at your feet.`);
          }
          refresh();
        },
        () => setInventoryMessage("The server did not answer."),
      );
      return true;
    }
    return false;
  }

  function furnaceAction(action) {
    if (!furnaceOpen) return false;
    const current = activeFurnaceState();
    if (current === null) return false;
    if (multiplayer !== null) return sharedFurnaceAction(action, current);
    if (action === "input") {
      const inputName = furnaceSlot("raw_iron") !== -1 ? "raw_iron" : "wheat";
      const slot = furnaceSlot(inputName);
      if (slot === -1) {
        setInventoryMessage("You need raw iron or wheat to smelt.");
        return false;
      }
      const loaded = Furnace.load_input(current, ITEM_IDS[inputName], 1n);
      if (!loaded.ok || !consume(inventory, slot)) {
        setInventoryMessage("The furnace input is full.");
        return false;
      }
      setActiveFurnaceState(loaded.furnace);
    } else if (action === "fuel") {
      const slot = furnaceSlot("coal");
      if (slot === -1) {
        setInventoryMessage("You need coal to fuel the furnace.");
        return false;
      }
      const loaded = Furnace.load_fuel(current, 14, 1n);
      if (!loaded.ok || !consume(inventory, slot)) {
        setInventoryMessage("The furnace fuel slot is full.");
        return false;
      }
      setActiveFurnaceState(loaded.furnace);
    } else if (action === "output") {
      const extracted = Furnace.take_output(current);
      if (!extracted.ok) {
        setInventoryMessage("The furnace has no iron ingot ready.");
        return false;
      }
      const item = itemNameFromId(extracted.item);
      if (item === null || !collectItem(inventory, item, Number(extracted.amount))) {
        setInventoryMessage("Make room in the inventory first.");
        return false;
      }
      setActiveFurnaceState(extracted.furnace);
    } else {
      return false;
    }
    refreshInventoryUi();
    updateHud();
    updateFurnaceStatus();
    return true;
  }

  function tickFurnace() {
    // A multiplayer server ticks its furnaces and sends the result.
    if (multiplayer === null) furnaceWorldState = Furnaces.tick_world(furnaceWorldState);
    if (multiplayer === null && worldSimulation.syncBlocks().length > 0) simulationTerrainDirty = true;
    if (furnaceOpen) updateFurnaceStatus();
    return true;
  }

  function chestPosition(x, y, z) {
    return cellPosition(x, y, z);
  }

  // Server chests are keyed by stored (Bend) coordinates; the local chest state
  // uses the chest domain's positions.
  function mirrorServerChest(state, chest) {
    const [x, y, z] = chestPosition(worldCoordinate(chest.pos[0]), chest.pos[1], worldCoordinate(chest.pos[2]));
    return chest.slots === null
      ? Chests.remove(state, x, y, z).world
      : Chests.set(state, x, y, z, wireSlotsToBend(chest.slots));
  }

  function activeChestServerPosition() {
    return [storageCoordinate(activeChest[0]), activeChest[1], storageCoordinate(activeChest[2])];
  }

  // Multiplayer chest actions: the server's Bend room decides. A deposit takes
  // the item from the inventory at once and gives it back if the server
  // refuses; a withdrawal adds the items once the server has removed them.
  function sharedChestAction(action, slotIndex, current) {
    const pos = activeChestServerPosition();
    const refresh = () => {
      refreshInventoryUi();
      updateHud();
      saveGame();
    };
    if (action === "deposit") {
      const item = selectedItem(inventory, selectedSlot);
      const id = itemId(item);
      if (id === null || id === "empty") {
        setInventoryMessage("Select an item to deposit.");
        return false;
      }
      const numericId = ITEM_IDS[id];
      const name = itemName(item);
      const durability = Number(item?.durability ?? 0);
      if (!ChestDomain.deposit(current, numericId, 1, durability).ok || !consume(inventory, selectedSlot)) {
        setInventoryMessage("The chest is full.");
        return false;
      }
      refresh();
      const giveBack = (message) => {
        collectItem(inventory, itemNameFromId(numericId), 1);
        setInventoryMessage(message);
        refresh();
      };
      multiplayer.chestRequest("deposit", { pos, item: numericId, count: 1, durability }).then(
        (result) => (result.ok ? setInventoryMessage(`${name} deposited.`) : giveBack("The chest is full.")),
        () => giveBack("The server did not answer; the item is back in your inventory."),
      );
      return true;
    }
    if (action === "withdraw" && slotIndex !== null) {
      const slot = chestSlotsView(current)[slotIndex];
      if (slot === undefined || slot.item === 0 || slot.count === 0) return false;
      const name = itemNameFromId(slot.item);
      if (name === null) return false;
      const trial = inventory.map((entry) => ({ ...entry }));
      if (!collectItem(trial, name, slot.count)) {
        setInventoryMessage("Make room in the inventory first.");
        return false;
      }
      multiplayer.chestRequest("withdraw", { pos, index: slotIndex, amount: 64 }).then(
        (result) => {
          const taken = result.ok ? itemNameFromId(result.item) : null;
          if (taken === null) {
            setInventoryMessage("Someone got there first: that slot is empty.");
          } else if (collectItem(inventory, taken, Number(result.amount))) {
            setInventoryMessage(`${taken} withdrawn.`);
          } else {
            // The inventory filled up while the request was in flight.
            dropAtPlayer(Number(result.item), Number(result.amount));
            setInventoryMessage(`No room for ${taken}: dropped at your feet.`);
          }
          refresh();
        },
        () => setInventoryMessage("The server did not answer."),
      );
      return true;
    }
    return false;
  }

  function activeChestState() {
    if (activeChest === null) return null;
    const [x, y, z] = chestPosition(...activeChest);
    const lookup = Chests.at(chestWorldState, x, y, z);
    return lookup.$ === "ChestFound" ? lookup.slots : null;
  }

  function chestSlotsView(slots) {
    const view = [];
    for (let node = slots; node?.$ === "Con"; node = node.tail) {
      const slot = node.head;
      view.push({
        item: Number(slot.item),
        count: Number(slot.count),
        durability: Number(slot.durability),
      });
    }
    return view;
  }

  function chestSlotMarkup(slot, index) {
    const name = slot.item === 0 ? "empty" : (itemNameFromId(slot.item) ?? "unknown item");
    const empty = slot.item === 0 || slot.count === 0;
    return `<button class="inventory-slot${empty ? " empty" : ""}" type="button" data-chest-slot="${index}"
      aria-label="Chest slot ${index + 1}: ${name}, ${slot.count}">
      <span class="slot-key">${index + 1}</span>
      <span class="slot-swatch" data-item="${empty ? "" : name}" style="--slot-color: ${empty ? "transparent" : itemColor({ item: name })}"></span>
      <span class="slot-name">${name}</span>
      <span class="slot-count">${slot.count || ""}</span>
    </button>`;
  }

  function refreshChestUi() {
    if (chestSlotsEl === null) return;
    const slots = activeChestState();
    if (slots === null) {
      chestSlotsEl.innerHTML = "";
      if (chestStatusEl !== null) chestStatusEl.textContent = "Right-click a placed chest first.";
      return;
    }
    const view = chestSlotsView(slots);
    chestSlotsEl.innerHTML = view.map(chestSlotMarkup).join("");
    const filled = view.filter((slot) => slot.item !== 0 && slot.count > 0).length;
    if (chestStatusEl !== null) chestStatusEl.textContent = `${filled}/9 slots used · click a slot to withdraw.`;
    paintSlotIcons();
  }

  function setChestSlots(slots) {
    if (activeChest === null) return false;
    const [x, y, z] = chestPosition(...activeChest);
    chestWorldState = Chests.set(chestWorldState, x, y, z, slots);
    return true;
  }

  function setChestOpen(open, location = activeChest) {
    if (open) {
      held.clear();
      cancelMining();
    }
    if (open) {
      if (location !== null) activeChest = location.map((value) => Math.trunc(value));
      if (activeChestState() === null) {
        setInventoryMessage("Right-click a placed chest first.");
        return false;
      }
    }
    chestOpen = open;
    if (chestToggleEl !== null) {
      chestToggleEl.hidden = activeChest === null;
      chestToggleEl.setAttribute("aria-expanded", String(open));
      chestToggleEl.textContent = open ? "Close chest (C)" : "Chest (C)";
    }
    setDialogVisibility(chestPanelEl, chestToggleEl, open);
    if (open) {
      inventoryOpen = false;
      setDialogVisibility(inventoryPanelEl, inventoryToggleEl, false);
      inventoryToggleEl.setAttribute("aria-expanded", "false");
      inventoryToggleEl.textContent = "Inventory (E)";
      if (furnaceOpen) setFurnaceOpen(false);
      if (document.pointerLockElement === canvas && typeof document.exitPointerLock === "function") {
        document.exitPointerLock();
      }
    }
    refreshChestUi();
    return true;
  }

  function toggleChest(location = activeChest) {
    return setChestOpen(!chestOpen, location);
  }

  function chestAction(action, slotIndex = null) {
    if (!chestOpen) return false;
    const current = activeChestState();
    if (current === null) return false;
    if (multiplayer !== null) return sharedChestAction(action, slotIndex, current);
    if (action === "deposit") {
      const item = selectedItem(inventory, selectedSlot);
      const id = itemId(item);
      if (id === null || id === "empty") {
        setInventoryMessage("Select an item to deposit.");
        return false;
      }
      const result = ChestDomain.deposit(
        current,
        ITEM_IDS[id],
        1,
        Number(item?.durability ?? 0),
      );
      if (!result.ok || !consume(inventory, selectedSlot)) {
        setInventoryMessage("The chest is full.");
        return false;
      }
      setChestSlots(ChestDomain.deposit_slots(result));
      setInventoryMessage(`${itemName(item)} deposited.`);
    } else if (action === "withdraw" && slotIndex !== null) {
      const result = ChestDomain.withdraw(current, BigInt(slotIndex), 64);
      if (!result.ok) return false;
      const itemNameValue = itemNameFromId(result.item);
      if (itemNameValue === null) return false;
      const trial = inventory.map((slot) => ({ ...slot }));
      if (!collectItem(trial, itemNameValue, Number(result.amount))) {
        setInventoryMessage("Make room in the inventory first.");
        return false;
      }
      inventory.splice(0, inventory.length, ...trial);
      setChestSlots(ChestDomain.withdraw_slots(result));
      setInventoryMessage(`${itemNameValue} withdrawn.`);
    } else {
      return false;
    }
    refreshChestUi();
    refreshInventoryUi();
    updateHud();
    saveGame();
    return true;
  }

  function craftRecipe(recipeId) {
    const recipe = RECIPES.find((entry) => entry.id === recipeId);
    if (recipe === undefined || !craft(inventory, recipeId)) {
      setInventoryMessage("Missing materials or inventory space.");
      return false;
    }
    setInventoryMessage(`${recipe.name} crafted.`);
    refreshInventoryUi();
    return true;
  }

  function eatSelected() {
    const item = selectedItem(inventory, selectedSlot);
    const nutrition = foodValue(item);
    if (nutrition <= 0) {
      setInventoryMessage("The selected item is not food.");
      return false;
    }
    if (player.hunger >= 20) {
      setInventoryMessage("You are not hungry.");
      return false;
    }
    if (!consume(inventory, selectedSlot)) return false;
    eatFood(player, nutrition);
    audio.play("eat");
    emitSparkle(vfx, player.x, player.y + 1.0, player.z, hexToRgb("#d59b45"), 5);
    if (itemId(item) === "rotten_flesh") {
      applyPoison(player, 10.0);
      setInventoryMessage("Rotten flesh eaten (you feel sick).");
    } else {
      setInventoryMessage(`${itemName(item)} eaten.`);
    }
    refreshInventoryUi();
    updateHud();
    return true;
  }

  function sameFurnacePosition(position, x, y, z) {
    return position !== null && position[0] === x && position[1] === y && position[2] === z;
  }

  function placeBlockAt(x, y, z, item) {
    const block = blockForItem(item);
    if (block === null) return false;
    let nextFurnaces = furnaceWorldState;
    let nextChests = chestWorldState;
    if (block === 11) {
      const [fx, fy, fz] = cellPosition(x, y, z);
      const added = Furnaces.add(furnaceWorldState, fx, fy, fz);
      if (!added.ok) return false;
      nextFurnaces = added.world;
    }
    if (block === 26) {
      const [cx, cy, cz] = cellPosition(x, y, z);
      const added = Chests.add(chestWorldState, cx, cy, cz);
      if (!added.ok) return false;
      nextChests = added.world;
    }
    const placement = placeInteraction(
      inventory,
      selectedSlot,
      item,
      block,
      x,
      y,
      z,
      blockAt(x, y, z) === 0,
      inside(x, y, z),
      overlapsPlayer(player, x, y, z),
    );
    if (!placement.ok) return false;
    furnaceWorldState = nextFurnaces;
    chestWorldState = nextChests;
    if (block === 11) worldSimulation.pin(Math.floor(x / CHUNK_SIZE), Math.floor(z / CHUNK_SIZE));
    setBlock(x, y, z, Number(placement.edit.block));
    // A redstone block placed is a redstone component placed. The contract owns
    // what it does; this only tells it the cell now holds one.
    if (isRedstoneBlock(Number(placement.edit.block))) {
      redstoneState.circuit = placeRedstoneComponent(
        circuitOf(redstoneState),
        Number(placement.edit.block),
        x,
        y,
        z,
      );
    }
    audio.play("place");
    // A placed block puffs its own colour off the top face, tighter and slower
    // than a mined one: the block is still standing, so the debris has less far
    // to travel.
    emitBlockDebris(vfx, x + 0.5, y + 1, z + 0.5, hexToRgb(itemColor(item)), 6, 0.7);
    invalidateVillagerPath(x, y, z);
    terrainMeshCache.invalidateBlock(x, z);
    if (block === 11) {
      activeFurnace = [x, y, z];
      furnaceToggleEl.hidden = false;
    }
    if (block === 26) {
      activeChest = [x, y, z];
      if (chestToggleEl !== null) chestToggleEl.hidden = false;
    }
    return true;
  }

  function isCropBlock(block) {
    return block >= 16 && block <= 19;
  }

  function tillBlockAt(x, y, z) {
    if (itemId(selectedItem(inventory, selectedSlot)) !== "wooden_hoe") return false;
    if (multiplayer !== null) {
      const ground = blockAt(x, y, z);
      if (ground !== 2 && ground !== 3) return false;
      const hoeSlot = selectedSlot;
      return sharedInteract("till", x, y, z, (result) => {
        if (!result.ok) return;
        useTool(inventory, hoeSlot);
        setInventoryMessage("Soil tilled into farmland.");
      });
    }
    if (!worldSimulation.till(x, y, z)) return false;
    useTool(inventory, selectedSlot);
    setInventoryMessage("Soil tilled into farmland.");
    return true;
  }

  function placeCropAt(x, y, z) {
    if (itemId(selectedItem(inventory, selectedSlot)) !== "wheat_seeds") return false;
    if (multiplayer !== null) {
      return sharedInteract("plant", x, y, z, (result) => {
        const seeds = inventory.findIndex((slot) => itemId(slot) === "wheat_seeds");
        if (result.ok && seeds !== -1) {
          consume(inventory, seeds);
          setInventoryMessage("Wheat planted.");
        } else if (!result.ok) {
          setInventoryMessage("Seeds need an empty block above hydrated farmland.");
        }
      });
    }
    // The seed is spent only when the crop takes.
    const trial = inventory.map((slot) => ({ ...slot }));
    if (!consume(trial, selectedSlot) || !worldSimulation.plant(x, y, z)) {
      setInventoryMessage("Seeds need an empty block above hydrated farmland.");
      return false;
    }
    inventory.splice(0, inventory.length, ...trial);
    setInventoryMessage("Wheat planted.");
    return true;
  }

  function collectCropHarvest(result) {
    const trial = inventory.map((slot) => ({ ...slot }));
    if (!collectItem(trial, "wheat_seeds", Number(result.seeds))) return false;
    if (!collectItem(trial, "wheat", Number(result.wheat))) return false;
    inventory.splice(0, inventory.length, ...trial);
    return true;
  }

  function harvestCropAt(x, y, z) {
    if (multiplayer !== null) {
      return sharedInteract("harvest", x, y, z, (result) => {
        if (!result.ok) return;
        // Whatever does not fit lands at the player's feet.
        if (!collectItem(inventory, "wheat_seeds", Number(result.seeds))) dropAtPlayer(ITEM_IDS.wheat_seeds, Number(result.seeds));
        if (!collectItem(inventory, "wheat", Number(result.wheat))) dropAtPlayer(ITEM_IDS.wheat, Number(result.wheat));
        setInventoryMessage("Wheat harvested.");
      });
    }
    const result = worldSimulation.harvest(x, y, z, collectCropHarvest);
    if (result.refused) setInventoryMessage("Make room for seeds and wheat first.");
    if (!result.ok) return false;
    setInventoryMessage("Wheat harvested.");
    return true;
  }

  function cropViews() {
    return worldSimulation.cropViews();
  }

  function farmlandViews() {
    return worldSimulation.farmlandViews();
  }

  let miningState = null;

  function renderMiningProgress(now = performance.now()) {
    const active = miningState !== null;
    const progress = miningProgress(miningState, now);
    if (miningProgressEl !== null) miningProgressEl.hidden = !active;
    if (miningProgressFillEl !== null) {
      miningProgressFillEl.style.transform = `scaleX(${progress.toFixed(3)})`;
      miningProgressFillEl.setAttribute("aria-valuenow", String(Math.round(progress * 100)));
    }
  }

  function cancelMining() {
    miningState = null;
    renderMiningProgress();
  }

  function completeMiningAt(x, y, z) {
    const removedBlock = blockAt(x, y, z);
    if (removedBlock === 26) {
      const [cx, cy, cz] = chestPosition(x, y, z);
      const stored = Chests.at(chestWorldState, cx, cy, cz);
      for (let node = stored.slots; stored.$ === "ChestFound" && node?.$ === "Con"; node = node.tail) {
        if (Number(node.head.count) > 0) {
          setInventoryMessage("Empty the chest before breaking it.");
          return false;
        }
      }
    }
    if (isCropBlock(removedBlock) && removedBlock === 19 && harvestCropAt(x, y, z)) {
      refreshInventoryUi();
      updateHud();
      rebuildMesh();
      return true;
    }
    const mining = mineInteraction(
      inventory,
      selectedSlot,
      selectedItem(inventory, selectedSlot),
      removedBlock,
      x,
      y,
      z,
    );
    if (!mining.ok) {
      setInventoryMessage("The selected tool cannot mine this block.");
      return false;
    }
    setBlock(x, y, z, Number(mining.edit.block));
    audio.play("break");
    // Debris comes off the cell that was just emptied, in that block's own
    // colour. This is the effect the old screen-space burst was standing in for:
    // it used to fire from the middle of the display, so a block mined off
    // screen looked identical to one mined under the crosshair.
    emitBlockDebris(vfx, x + 0.5, y + 0.5, z + 0.5, hexToRgb(itemColor({ block: removedBlock })), 12, 0.9);
    worldSimulation.blockChanged(x, y, z, removedBlock, Number(mining.edit.block));
    // A redstone block broken is a redstone component broken. The contract drops
    // it and the cell's cached power in one step, so a wire that loses its source
    // reads dark on the very next tick rather than staying lit. A piston head is
    // the one case that is not its own component: it retracts the piston that
    // pushed it, which the adapter knows how to find.
    if (removedBlock === redstoneIds.head) {
      breakRedstoneAt(redstoneState, x, y, z);
    } else if (isRedstoneBlock(removedBlock)) {
      redstoneState.circuit = RedstoneAll.remove_at(circuitOf(redstoneState), BigInt(x), BigInt(y), BigInt(z));
    }
    invalidateVillagerPath(x, y, z);
    terrainMeshCache.invalidateBlock(x, z);
    if (removedBlock === 11) {
      const [fx, fy, fz] = cellPosition(x, y, z);
      const removed = Furnaces.remove(furnaceWorldState, fx, fy, fz);
      furnaceWorldState = removed.world;
      if (!hasFurnaceInChunk(Math.floor(x / CHUNK_SIZE), Math.floor(z / CHUNK_SIZE))) {
        worldSimulation.releaseChunk(Math.floor(x / CHUNK_SIZE), Math.floor(z / CHUNK_SIZE));
      }
      if (sameFurnacePosition(activeFurnace, x, y, z)) {
        activeFurnace = null;
        setFurnaceOpen(false);
      }
    }
    if (removedBlock === 26) {
      const [cx, cy, cz] = chestPosition(x, y, z);
      chestWorldState = Chests.remove(chestWorldState, cx, cy, cz).world;
      if (activeChest !== null && sameFurnacePosition(activeChest, x, y, z)) {
        setChestOpen(false);
        activeChest = null;
        if (chestToggleEl !== null) chestToggleEl.hidden = true;
      }
    }
    refreshInventoryUi();
    updateHud();
    rebuildMesh();
    return true;
  }

  function startMining(target) {
    const [x, y, z] = target.hit;
    const block = blockAt(x, y, z);
    if (isCropBlock(block) && block === 19) {
      completeMiningAt(x, y, z);
      return;
    }
    const item = selectedItem(inventory, selectedSlot);
    const duration = miningDuration(item, block);
    if (!(duration > 0)) {
      setInventoryMessage("The selected tool cannot mine this block.");
      return;
    }
    miningState = createMiningState({
      x,
      y,
      z,
      block,
      slot: selectedSlot,
      item: itemId(item),
      duration,
      startedAt: performance.now(),
    });
    renderMiningProgress(miningState.startedAt);
  }

  function updateMining(now) {
    if (miningState === null) {
      renderMiningProgress(now);
      return;
    }
    const state = miningState;
    const target = raycast(world, player);
    if (!miningStateMatches(
      state,
      target,
      blockAt,
      selectedSlot,
      itemId(selectedItem(inventory, selectedSlot)),
    )) {
      cancelMining();
      return;
    }
    renderMiningProgress(now);
    if (miningProgress(state, now) < 1) return;
    cancelMining();
    completeMiningAt(state.x, state.y, state.z);
  }

  function interact(button) {
    const target = raycast(world, player);
    if (!target) return;
    const [x, y, z] = target.hit;
    if (button === 2 && itemId(selectedItem(inventory, selectedSlot)) === "wooden_hoe" && tillBlockAt(x, y, z)) {
      refreshInventoryUi();
      updateHud();
      rebuildMesh();
      return;
    }
    if (button === 2 && (blockAt(x, y, z) === 14 || blockAt(x, y, z) === 15)) {
      toggleDoorAt(x, y, z);
      return;
    }
    // A lever is the one redstone block a player operates rather than places, so
    // right-clicking it flips the contract's state instead of placing anything. The
    // flip is an input edge, not a world change: the circuit does the rest on its
    // own clock.
    if (button === 2 && isRedstoneInteractive(blockAt(x, y, z))) {
      toggleLever(redstoneState, x, y, z);
      audio.play("place");
      return;
    }
    if (button === 2 && blockAt(x, y, z) === 11) {
      setFurnaceOpen(true, [x, y, z]);
      return;
    }
    if (button === 2 && blockAt(x, y, z) === 26) {
      setChestOpen(true, [x, y, z]);
      return;
    }
    if (button === 0) {
      startMining(target);
      return;
    } else if (button === 2 && target.place) {
      const [px, py, pz] = target.place;
      const item = selectedItem(inventory, selectedSlot);
      if (itemId(item) === "wheat_seeds" && placeCropAt(px, py, pz)) {
        refreshInventoryUi();
        updateHud();
        rebuildMesh();
        return;
      }
      if (!placeBlockAt(px, py, pz, item)) return;
    } else {
      return;
    }
    refreshInventoryUi();
    updateHud();
    rebuildMesh();
  }

  const heartPips = [];
  const hungerPips = [];
  const airPips = [];
  for (let index = 0; index < 10; index += 1) {
    const heart = document.createElement("div");
    heart.className = "pip full";
    heartsEl.append(heart);
    heartPips.push(heart);
    const food = document.createElement("div");
    food.className = "pip full";
    hungerEl.append(food);
    hungerPips.push(food);
    const bubble = document.createElement("div");
    bubble.className = "pip full";
    airEl.append(bubble);
    airPips.push(bubble);
  }
  let vitalsKey = "";
  let survivalAnnouncementKey = "";
  let survivalAnnouncementReady = false;
  let lastHealth = 20;
  let debugOverlayTick = -1;

  function paintPips(pips, points) {
    const clamped = Math.max(0, Math.min(20, points));
    pips.forEach((pip, index) => {
      const value = Math.max(0, Math.min(2, clamped - index * 2));
      pip.className = `pip${value >= 2 ? " full" : value > 0 ? " half" : ""}`;
    });
  }

  function updateTargetHighlight() {
    if (blockHighlightEl === null) return;
    const target = raycast(world, player);
    if (target === null) {
      blockHighlightEl.hidden = true;
      return;
    }
    const block = Number(blockAt(...target.hit));
    if (block === 0) {
      blockHighlightEl.hidden = true;
      return;
    }
    blockHighlightEl.textContent = `${itemName({ block })} · ${target.hit.join(", ")}`;
    blockHighlightEl.hidden = false;
  }

  function updateHud() {
    const item = selectedItem(inventory, selectedSlot);
    const name = itemName(item);
    const count = item === null ? 0 : item.count;
    coordsEl.textContent = `x ${player.x.toFixed(1)} · y ${player.y.toFixed(1)} · z ${player.z.toFixed(1)}`;
    seedEl.textContent = `seed: ${seedLabel(SEED)}`;
    statsEl.textContent = `${blockCount} blocks · ${terrainQuadCount + waterQuadCount} faces · ${world.activeChunkCount()} chunks · ${mobs.filter((mob) => mob.alive).length} mobs · ${villagers.length} villagers · ${drops.length} drops · Lv ${Number(Experience.xp_level(xpState))}${(player.poison ?? 0) > 0 ? ` · poisoned ${Math.ceil(player.poison)}s` : ""}`;
    selectedEl.textContent = count > 0
      ? `${name}${count > 1 ? ` ×${count}` : ""}`
      : "Empty hand";
    const key = `${Math.round(player.health * 2)}|${Math.round(player.hunger * 2)}|${Math.round((player.air ?? 10) * 2)}`;
    if (key !== vitalsKey) {
      vitalsKey = key;
      paintPips(heartPips, player.health);
      paintPips(hungerPips, player.hunger);
      paintPips(airPips, (player.air ?? 10) * 2);
    }
    airEl.hidden = (player.air ?? 10) >= 9.99 && !isHeadUnderwater(world, player);
    heartsEl.setAttribute("aria-label", `Health ${Math.ceil(player.health)} of 20`);
    hungerEl.setAttribute("aria-label", `Hunger ${Math.ceil(player.hunger)} of 20`);
    airEl.setAttribute("aria-label", `Air ${Math.ceil((player.air ?? 10) * 2)} of 20`);
    const xpLevel = Number(Experience.xp_level(xpState));
    const xpPoints = Number(Experience.xp_points(xpState));
    const xpThreshold = Math.max(1, Number(Experience.threshold(xpLevel)));
    const xpProgress = Math.max(0, Math.min(100, Math.round((xpPoints / xpThreshold) * 100)));
    if (xpHudEl !== null) {
      xpHudEl.hidden = false;
      xpHudEl.setAttribute("aria-label", `Experience level ${xpLevel}, ${xpProgress}% to next level`);
    }
    if (xpLevelEl !== null) xpLevelEl.textContent = String(xpLevel);
    if (xpTrackEl !== null) xpTrackEl.setAttribute("aria-valuenow", String(xpProgress));
    if (xpFillEl !== null) xpFillEl.style.transform = `scaleX(${(xpProgress / 100).toFixed(3)})`;
    const survivalKey = [
      Math.ceil(player.health),
      Math.ceil(player.hunger),
      Math.ceil(player.air ?? 10),
      xpLevel,
    ].join("|");
    if (survivalAnnouncementReady && survivalKey !== survivalAnnouncementKey && survivalAnnouncerEl !== null) {
      const previous = survivalAnnouncementKey.split("|").map(Number);
      const current = survivalKey.split("|").map(Number);
      const messages = [];
      if (current[0] !== previous[0]) messages.push(`Health ${current[0]} of 20`);
      if (current[1] !== previous[1]) messages.push(`Hunger ${current[1]} of 20`);
      if (current[2] !== previous[2]) messages.push(`Air ${current[2]} of 10`);
      if (current[3] !== previous[3]) messages.push(`Level ${current[3]}`);
      if (messages.length > 0) survivalAnnouncerEl.textContent = `${messages.join(". ")}.`;
    }
    survivalAnnouncementKey = survivalKey;
    survivalAnnouncementReady = true;
    if (player.health < lastHealth - 0.001 && damageFlashEl !== null) {
      damageFlashEl.animate([{ opacity: 0.9 }, { opacity: 0 }], { duration: 450 });
    }
    lastHealth = player.health;
    updateWorldLoading();
  }

  function atlasTexelDiagnostics(tile) {
    const size = ATLAS_TILE_SIZE;
    const rendered = readAtlasTilePixels(gl, atlasTexture, tile, size);
    const canvasRef = atlasSourceCanvas(atlasTexture);
    const context = canvasRef?.getContext("2d", { willReadFrequently: true });
    if (context === null || context === undefined) throw new Error("Atlas source pixels are unavailable");
    const source = context.getImageData(0, 0, canvasRef.width, canvasRef.height).data;
    // The atlas is padded, so the tile sits inside its own cell.
    const cell = atlasCellOrigin(tile);
    const tileX = cell.x + ATLAS_TILE_GUTTER;
    const tileY = cell.y + ATLAS_TILE_GUTTER;
    const probeInset = 0;
    let mismatches = 0;
    let exactMismatches = 0;
    let flippedMismatches = 0;
    let maxDelta = 0;
    for (let y = probeInset; y < size - probeInset; y += 1) {
      for (let x = probeInset; x < size - probeInset; x += 1) {
        const renderedIndex = (y * size + x) * 4;
        const normalIndex = ((tileY + y) * canvasRef.width + tileX + x) * 4;
        const flippedIndex = ((tileY + size - 1 - y) * canvasRef.width + tileX + x) * 4;
        for (let channel = 0; channel < 4; channel += 1) {
          const delta = Math.abs(rendered[renderedIndex + channel] - source[normalIndex + channel]);
          maxDelta = Math.max(maxDelta, delta);
          if (delta > 2) mismatches += 1;
          if (delta !== 0) exactMismatches += 1;
          if (rendered[renderedIndex + channel] !== source[flippedIndex + channel]) flippedMismatches += 1;
        }
      }
    }
    return {
      tile,
      pixels: size * size,
      mismatches,
      exactMismatches,
      flippedMismatches,
      maxDelta,
      probeInset,
    };
  }

  function frameDiagnostics() {
    const { frameTimes, ...publicFrameMetrics } = frameMetrics;
    return {
      ...publicFrameMetrics,
      ...framePercentiles(frameMetrics),
      renderer: rendererKind,
      rendererName,
      fpsLimit: framePacer?.limit ?? 0,
      frameBudgetMs: framePacer?.targetFrameMs ?? 0,
      shaderQuality,
      webgpu: { ...webgpuProbe },
      atlasMipmaps: {
        safe: atlasMipmapVerdict.safe,
        reason: atlasMipmapVerdict.reason ?? null,
        levels: atlasMipmapVerdict.levels ?? [],
        contaminated: (atlasMipmapVerdict.contaminated ?? []).length,
      },
      player: { ...player },
      playerSpawnReady,
      spawnMeshReady,
      activeChunks: world.activeChunkCount(),
      pendingChunks: world.pendingChunkCount(),
      pinnedChunks: world.pinnedChunkCount(),
      blockCount,
      terrainQuads: terrainQuadCount,
      waterQuads: waterQuadCount,
      dynamicQuads: dynamicQuadCount,
      shadowQuads: shadowQuadCount,
      meshRebuilds: terrainMeshCache.rebuildCount,
      meshRebuildRequests: streamingMeshScheduler?.requestCount ?? 0,
      meshRebuildRuns: streamingMeshScheduler?.runCount ?? 0,
      // Distant terrain still generating counts as pending: until its tiles
      // land the far view changes from one frame to the next.
      meshRebuildPending: (streamingMeshScheduler?.pending ?? false) || (terrainMeshCache?.pending ?? false)
        || lodTerrain.stats().inFlight > 0 || lodTerrain.stats().missingTiles > 0,
      lastGpuChunkUpdate,
      lod: { ...lodTerrain.stats(), workerFailures: lodWorkerFailures },
      meshWorkerRequests: meshWorkerRequestCount,
      meshWorkerResponses: meshWorkerResponseCount,
      meshWorkerRejects: meshWorkerRejectCount,
      workerRequests: workerRequestCount,
      workerHydrates: workerHydrateCount,
      workerRejects: workerRejectCount,
      villagerPathWorkerRequests: villagerPathWorkerRequests,
      villagerPathWorkerResponses: villagerPathWorkerResponses,
      villagerPathWorkerRejects: villagerPathWorkerRejects,
      villagerPathPending,
      simulationTime: Number(Simulation.time(worldSimulation.simulation)),
      mobs: mobs.filter((mob) => mob.alive).length,
      villagers: villagers.length,
      drops: drops.length,
      worldTime,
      daylight,
      paused,
    };
  }

  function updateDebugOverlay() {
    if (!debugVisible || debugOverlayEl === null) return;
    const tick = Math.floor(performance.now() / 250);
    if (tick === debugOverlayTick) return;
    debugOverlayTick = tick;
    debugOverlayEl.textContent = formatDebugText(frameDiagnostics());
  }

  function setDebugVisible(visible) {
    debugVisible = Boolean(visible);
    if (debugOverlayEl !== null) debugOverlayEl.hidden = !debugVisible;
    updateDebugOverlay();
  }

  function toggleDebugOverlay() {
    setDebugVisible(!debugVisible);
  }

  function saveGame() {
    try {
      saveTransactional(window.localStorage, SAVE_KEY, {
        version: 1,
        // A multiplayer world's edit log lives on the server.
        edits: multiplayer === null ? world.getEdits() : WorldState.empty(),
        player: { ...player },
        inventory: inventory.map((item) => ({ ...item })),
        equipment: equipmentState,
        craftingGrid: craftingGrid.map((item) => ({ ...item })),
        furnaces: furnaceWorldState,
        chests: chestWorldState,
        crops: worldSimulation.crops,
        farmland: worldSimulation.farmland,
        fluids: worldSimulation.fluids,
        fire: worldSimulation.fire,
        redstone: circuitOf(redstoneState),
        simulation: worldSimulation.simulation,
        entities: packEntityState(mobDomainState, dropDomainState),
        xp: xpState,
        villagers: villagerDomainState,
        villagerTick: BigInt(villagerTick),
      });
      if (session.profile !== null) {
        let doc = loadProfilesDoc(window.localStorage);
        if (session.worldId !== null && getWorld(doc, session.profileId, session.worldId) !== null) {
          doc = touchWorld(doc, session.profileId, session.worldId);
        } else {
          doc = touchProfile(doc, session.profileId);
        }
        saveProfilesDoc(window.localStorage, doc);
      }
    } catch {
      // Saving is best-effort when storage is disabled or full.
    }
  }

  function render() {
    resizeCanvas();
    const palette = skyPalette(daylight, worldTime);
    const sky = palette.top;
    const skyHorizon = palette.horizon;
    const sunDirection = palette.sunDirection;
    const sunColor = palette.sunColor;
    const shaderTime = reducedMotionQuery?.matches ? 0 : worldTime;
    const skyTick = Math.floor(worldTime * 4);
    if (skyTick !== skyCssTick) {
      skyCssTick = skyTick;
      canvas.style.setProperty("--sky-top", palette.cssTop);
      canvas.style.setProperty("--sky-horizon", palette.cssHorizon);
      canvas.style.setProperty("--sun-alpha", String(Math.max(0, ((daylight - 0.28) / 0.72) * 0.24)));
    }
    const motion = cameraMotion(worldTime, {
      speed: visualSpeed,
      grounded: player.grounded,
    });
    if (firstPersonHandCanvasEl !== null && firstPersonHandContext !== null) {
      firstPersonHandCanvasEl.hidden = activeModalPanel() !== null || paused;
      if (!firstPersonHandCanvasEl.hidden) {
        const selection = selectedItem(inventory, selectedSlot);
        const swing = Math.max(0, Math.min(1, (0.26 - (worldTime - handSwingTime)) / 0.26));
        drawFirstPersonOverlay(firstPersonHandContext, {
          atlasCanvas: firstPersonAtlasCanvas,
          selectedBlock: blockForItem(selection),
          selectedItem: selection,
          time: worldTime,
          speed: visualSpeed,
          grounded: player.grounded,
          swing,
          motionEnabled: !reducedMotionQuery?.matches,
        });
      }
    }
    heldItemViewEl?.style.setProperty("--held-sway", `${(motion.sway * 180).toFixed(2)}px`);
    heldItemViewEl?.style.setProperty("--held-bob", `${(-motion.bob * 180).toFixed(2)}px`);
    heldItemViewEl?.style.setProperty("--held-roll", `${(motion.roll * 140).toFixed(2)}deg`);
    const eye = [player.x + motion.sway * 0.5, player.y + (isSneaking(held, options.controls) ? SNEAK_EYE_HEIGHT : EYE_HEIGHT) + motion.bob, player.z];
    const direction = cameraDirection(player);
    const cameraRight = normalize(cross(direction, [0, 1, 0]));
    const cameraUp = normalize(cross(cameraRight, direction));
    const center = [eye[0] + direction[0], eye[1] + direction[1], eye[2] + direction[2]];
    const view = lookAt(eye, center, [0, 1, 0]);
    const fov = cameraFov(options.fov, {
      sprinting: isSprinting(held, options.controls),
      damage: 20 - Number(player.health),
      underwater: isHeadUnderwater(world, player),
    });
    const projection = perspective(fov * Math.PI / 180, canvas.width / canvas.height, 0.05, RENDER_FAR);
    if (multiplayer !== null) updateNametags(multiply4(projection, view));
    if (gpuRenderer !== null) {
      // The particle batch rides the same vertex layout as the entities, so the
      // WebGPU path only has to upload it alongside them.
      rebuildVfxMesh(cameraRight, cameraUp);
      gpuRenderer.render({
        viewProjection: multiply4(projection, view),
        camera: eye,
        cameraRight,
        cameraUp,
        cameraForward: direction,
        skyColor: sky,
        skyHorizon,
        sunDirection,
        sunColor,
        daylight,
        time: shaderTime,
        miningProgress: miningProgress(miningState, performance.now()),
        fogDistance: FOG_DISTANCE,
        aspect: canvas.width / canvas.height,
        tanHalfFov: Math.tan(fov * Math.PI / 360),
      });
      return;
    }
    // ---- adaptive quality -------------------------------------------------
    const tier = visualQuality.sample(frameMetrics.frameMs || 16.7);
    const viewProjectionMatrix = multiply4(projection, view);

    // Project the sun into screen space once; both the god-ray mask and the
    // shaft origin need it, and the camera basis is already at hand.
    lastSunDirection = [...sunDirection];
    const sunClip = transformPoint(viewProjectionMatrix, sunDirection);
    const sunForward = dot(direction, sunDirection);
    const behindCamera = sunForward < 0.05;
    if (!behindCamera && Math.abs(sunClip[3]) > 1e-5) {
      const inverseW = 1 / sunClip[3];
      sunScreenPosition[0] = (sunClip[0] * inverseW) * 0.5 + 0.5;
      sunScreenPosition[1] = (sunClip[1] * inverseW) * 0.5 + 0.5;
    } else {
      // Behind the camera: park the origin off-screen so the radial march has
      // nothing to smear, and let sunVisibleForGodrays fade the stage out.
      sunScreenPosition[0] = -4;
      sunScreenPosition[1] = -4;
    }
    const onScreen = !behindCamera
      && sunScreenPosition[0] > -0.35 && sunScreenPosition[0] < 1.35
      && sunScreenPosition[1] > -0.35 && sunScreenPosition[1] < 1.35;
    // Shafts need the sun above the horizon and reasonably in front, otherwise
    // they are just a wash over the whole frame.
    sunVisibleForGodrays = onScreen
      ? Math.max(0, Math.min(1, (sunDirection[1] - 0.02) / 0.3)) * Math.max(0, Math.min(1, sunForward * 1.6))
      : 0;

    // ---- shadow cascade ---------------------------------------------------
    // The cascade resolution follows the tier: a depth-only map that covers a
    // fixed world area can easily out-rasterise the whole colour frame. A player
    // who turned shadows off gets no pass at all rather than a pass nobody reads.
    shadowPass.resize(tier.shadowMapSize);
    const shadowsOn = shadowPass.supported && graphicsEffects.shadows > 0;
    if (shadowsOn) {
      lightViewProjection.set(
        fitSunShadowMatrix(sunDirection, [player.x, player.y, player.z], {
          radius: SHADOW_RADIUS,
          mapSize: shadowPass.mapSize,
        }),
      );
      renderShadowPass(shaderTime);
    }

    // ---- scene into the HDR target ---------------------------------------
    postPipeline.resize(canvas.width, canvas.height, tier.renderScale * graphicsEffects.renderScale);
    postPipeline.beginScene();
    gl.clearColor(sky[0], sky[1], sky[2], 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.useProgram(program);

    gl.uniformMatrix4fv(viewProjectionLocation, false, viewProjectionMatrix);
    gl.uniform3f(cameraLocation, eye[0], eye[1], eye[2]);
    gl.uniform3f(terrainCameraPositionLocation, eye[0], eye[1], eye[2]);
    gl.uniform1f(timeLocation, shaderTime);
    gl.uniform1f(daylightLocation, daylight);
    gl.uniform3f(terrainSkyColorLocation, sky[0], sky[1], sky[2]);
    gl.uniform3f(terrainSkyHorizonColorLocation, skyHorizon[0], skyHorizon[1], skyHorizon[2]);
    gl.uniform3f(terrainGroundBounceLocation, GROUND_BOUNCE[0], GROUND_BOUNCE[1], GROUND_BOUNCE[2]);
    gl.uniform3f(terrainSunDirectionLocation, sunDirection[0], sunDirection[1], sunDirection[2]);
    gl.uniform3f(terrainSunColorLocation, sunColor[0], sunColor[1], sunColor[2]);
    gl.uniform1f(terrainSunIntensityLocation, SUN_INTENSITY);
    gl.uniform1f(terrainAmbientStrengthLocation, AMBIENT_STRENGTH);
    gl.uniform1f(terrainAmbientDesaturationLocation, AMBIENT_DESATURATION);
    gl.uniform1f(terrainBumpStrengthLocation, shaderQuality >= 0.5 ? BUMP_STRENGTH : 0);
    gl.uniform1f(terrainDetailStrengthLocation, DETAIL_STRENGTH);
    gl.uniform1f(terrainDetailScaleLocation, DETAIL_SCALE);
    gl.uniform1f(terrainWaterDetailLocation, WATER_DETAIL_STRENGTH * tier.waterDetail * graphicsEffects.waterDetail);
    gl.uniform1f(terrainNearLocation, 0.05);
    gl.uniform1f(terrainFarLocation, RENDER_FAR);
    gl.uniformMatrix4fv(lightViewProjectionLocation, false, lightViewProjection);
    gl.uniform1f(shadowTexelSizeLocation, 1 / shadowPass.mapSize);
    gl.uniform1f(shadowRadiusLocation, SHADOW_RADIUS);
    gl.uniform2f(shadowFadeLocation, SHADOW_FADE_START, SHADOW_FADE_END);
    gl.uniform1f(
      shadowStrengthLocation,
      // A sun on the horizon casts almost no readable shadow, and the cascade
      // would only produce noise there, so fade the term out with it.
      shadowsOn
        ? Math.max(0, Math.min(1, (sunDirection[1] + 0.05) / 0.25)) * 0.94 * graphicsEffects.shadows
        : 0,
    );
    gl.uniform1f(shadowTapsLocation, tier.shadowTaps);
    gl.uniform1f(shadowFloorLocation, SHADOW_FLOOR);
    gl.activeTexture(gl.TEXTURE0 + TERRAIN_TEXTURE_UNIT.atlas);
    gl.bindTexture(gl.TEXTURE_2D, atlasTexture);
    gl.activeTexture(gl.TEXTURE0 + TERRAIN_TEXTURE_UNIT.cloudMap);
    gl.bindTexture(gl.TEXTURE_2D, cloudTexture);
    gl.activeTexture(gl.TEXTURE0 + TERRAIN_TEXTURE_UNIT.shadowMap);
    gl.bindTexture(gl.TEXTURE_2D, shadowPass.texture ?? shadowFallbackTexture);
    gl.activeTexture(gl.TEXTURE0 + TERRAIN_TEXTURE_UNIT.shadowDisk);
    gl.bindTexture(gl.TEXTURE_2D, shadowDiskTexture);
    gl.activeTexture(gl.TEXTURE0 + TERRAIN_TEXTURE_UNIT.sceneDepth);
    gl.bindTexture(gl.TEXTURE_2D, postPipeline.scene.depthTexture ?? atlasTexture);

    gl.uniform1f(surfacePassLocation, 0);
    gl.uniform1f(shadowPassLocation, 0);
    // One draw per chunk that survives the frustum test. The water pass below
    // reuses the same selection.
    const terrainSelection = glChunkBuffers.select(extractClipPlanes(viewProjectionMatrix));
    glSubmit = terrainSelection.metrics;
    const terrainLocations = {
      position: positionLocation,
      color: colorLocation,
      light: lightLocation,
      normal: normalLocation,
      uv: uvLocation,
      material: materialLocation,
      tile: tileLocation,
    };
    for (const chunk of terrainSelection.visible) {
      if (chunk.opaque === null) continue;
      bindInterleavedTerrain(gl, chunk.opaque, terrainLocations);
      gl.drawArrays(gl.TRIANGLES, 0, chunk.opaqueVertices);
    }

    // The sky only needs to shade untouched depth. Drawing it after opaque
    // terrain avoids running the cloud march for pixels the world already covers.
    gl.depthMask(false);
    gl.depthFunc(gl.LEQUAL);
    gl.useProgram(skyProgram);
    gl.bindBuffer(gl.ARRAY_BUFFER, skyPositionBuffer);
    gl.enableVertexAttribArray(skyPositionLocation);
    gl.vertexAttribPointer(skyPositionLocation, 2, gl.FLOAT, false, 0, 0);
    gl.uniform3f(skyCameraForwardLocation, direction[0], direction[1], direction[2]);
    gl.uniform3f(skyCameraRightLocation, cameraRight[0], cameraRight[1], cameraRight[2]);
    gl.uniform3f(skyCameraUpLocation, cameraUp[0], cameraUp[1], cameraUp[2]);
    gl.uniform3f(skyCameraPositionLocation, eye[0], eye[1], eye[2]);
    gl.uniform3f(skyColorLocation, sky[0], sky[1], sky[2]);
    gl.uniform3f(skyHorizonColorLocation, skyHorizon[0], skyHorizon[1], skyHorizon[2]);
    gl.uniform3f(skySunDirectionLocation, sunDirection[0], sunDirection[1], sunDirection[2]);
    gl.uniform3f(skySunColorLocation, sunColor[0], sunColor[1], sunColor[2]);
    gl.uniform1f(skyAspectLocation, canvas.width / canvas.height);
    gl.uniform1f(skyTanHalfFovLocation, Math.tan(fov * Math.PI / 360));
    gl.uniform1f(skyDaylightLocation, daylight);
    gl.uniform1f(skyTimeLocation, shaderTime);
    gl.uniform1f(skyCloudStepsLocation, tier.cloudSteps * graphicsEffects.clouds);
    gl.uniform1f(skyCloudLightStepsLocation, tier.cloudLightSteps);
    gl.uniform1f(skyCloudCoverageLocation, CLOUD_COVERAGE);
    gl.uniform1f(skyWindSpeedLocation, CLOUD_WIND_SPEED);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.depthFunc(gl.LESS);
    gl.depthMask(true);
    gl.useProgram(program);

    if (waterVertexCount > 0) {
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      gl.depthMask(false);
      gl.uniform1f(surfacePassLocation, 1);
      for (const chunk of terrainSelection.visible) {
        if (chunk.water === null) continue;
        bindInterleavedTerrain(gl, chunk.water, terrainLocations);
        gl.drawArrays(gl.TRIANGLES, 0, chunk.waterVertices);
      }
      gl.depthMask(true);
      gl.disable(gl.BLEND);
    }
    if (shadowVertexCount > 0) {
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      gl.depthMask(false);
      gl.uniform1f(shadowPassLocation, 1);
      bindTerrainAttributes({
        position: shadowPositionBuffer,
        color: shadowColorBuffer,
        light: shadowLightBuffer,
        normal: shadowNormalBuffer,
        uv: shadowUvBuffer,
        material: null,
        tile: null,
      }, false);
      gl.drawArrays(gl.TRIANGLES, 0, shadowVertexCount);
      gl.depthMask(true);
      gl.disable(gl.BLEND);
    }
    gl.uniform1f(shadowPassLocation, 0);
    gl.uniform1f(surfacePassLocation, 0);
    bindTerrainAttributes({
      position: dynamicPositionBuffer,
      color: dynamicColorBuffer,
      light: dynamicLightBuffer,
      normal: dynamicNormalBuffer,
      uv: dynamicUvBuffer,
      material: null,
      tile: dynamicTileBuffer,
    }, false);
    gl.uniform1f(miningProgressLocation, miningProgress(miningState, performance.now()));
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.drawArrays(gl.TRIANGLES, 0, dynamicVertexCount);
    gl.disable(gl.BLEND);

    // ---- particles --------------------------------------------------------
    // Drawn last in the scene, over the entities, so a burning mob is visibly
    // alight. Premultiplied output means one batch and one blend state cover
    // both an additive spark and a covering puff of smoke: the shader writes a
    // zero destination weight for the additive ones. Depth writes stay off, or
    // a particle would carve its own silhouette into the depth buffer and cull
    // every particle behind it.
    rebuildVfxMesh(cameraRight, cameraUp);
    if (vfxVertexCount > 0) {
      gl.useProgram(program);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      gl.depthMask(false);
      gl.uniform1f(vfxPassLocation, 1);
      bindTerrainAttributes({
        position: vfxPositionBuffer,
        color: vfxColorBuffer,
        light: vfxLightBuffer,
        normal: vfxNormalBuffer,
        uv: vfxUvBuffer,
        material: null,
        tile: vfxTileBuffer,
      }, false);
      gl.drawArrays(gl.TRIANGLES, 0, vfxVertexCount);
      gl.uniform1f(vfxPassLocation, 0);
      gl.depthMask(true);
      gl.disable(gl.BLEND);
    }

    // ---- composite --------------------------------------------------------
    // The shipped values below are what the pipeline was tuned against; the
    // player's sliders are multipliers on top of them, so 100% is the look these
    // comments describe and a stored preference is a deliberate departure from it.
    const headUnderwater = isHeadUnderwater(world, player);
    postPipeline.composite({
      // Exposure sets how much of the HDR range the tonemapper gets to work with.
      // A front-lit surface with a 0.35 albedo already lands near 1.0 under a 2.35
      // sun, so a higher exposure pushes the whole midtone band into the shoulder
      // of the ACES curve, where tonal separation - and therefore the texture
      // detail the atlas just gained - is compressed away. Sitting lower keeps the
      // highlights for the bloom and the god rays and leaves the midtones legible.
      exposure: headUnderwater ? 1.6 : 1.9,
      bloomThreshold: 0.42,
      bloomStrength: 0.062 * graphicsEffects.bloom,
      bloomRadius: 1.0,
      godrayStrength: sunVisibleForGodrays * 0.34 * graphicsEffects.godRays,
      godrayColor: sunColor,
      godrayDensity: 0.78,
      godrayDecay: 0.955,
      godrayWeight: 1.0,
      sunUv: sunScreenPosition,
      sunVisible: sunVisibleForGodrays,
      vignette: 0.3 * graphicsEffects.vignette,
      // Lateral chromatic aberration, scaled by the squared radius. This is a
      // lens artefact and it only reads as one at the very edge of the frame: at
      // 0.0018 it was fringing the red and green channels apart along every
      // high-contrast edge, including near the centre, which is a defect rather
      // than an effect. Keep it just visible in the corners.
      aberration: 0.0007 * graphicsEffects.aberration,
      grain: 0.02 * graphicsEffects.grain,
      sharpen: 0.2 * graphicsEffects.sharpen,
      saturation: 1.0,
      contrast: 1.06,
      lift: [-0.004, -0.002, 0.004],
      gain: [1.0, 0.995, 0.985],
      fxaa: 0.9 * graphicsEffects.antiAliasing,
      underwater: headUnderwater ? 1 : 0,
      underwaterColor: [0.26, 0.55, 0.64],
      caustics: 0.75 * graphicsEffects.caustics,
      time: shaderTime,
      near: 0.05,
      far: RENDER_FAR,
    });
  }

  /**
   * Bind the terrain program's attribute set for one draw batch. The four
   * batches (terrain, water, entity blobs, entities) share one program and one
   * layout, so a single helper keeps them from drifting apart. `withMaterial`
   * is false for the batches that carry no material band, which is pinned to
   * zero instead of being left pointing at the previous batch's buffer.
   */
  function bindTerrainAttributes(buffers, withMaterial) {
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.position);
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 3, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.color);
    gl.enableVertexAttribArray(colorLocation);
    gl.vertexAttribPointer(colorLocation, 3, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.light);
    gl.enableVertexAttribArray(lightLocation);
    gl.vertexAttribPointer(lightLocation, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.normal);
    gl.enableVertexAttribArray(normalLocation);
    gl.vertexAttribPointer(normalLocation, 3, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.uv);
    gl.enableVertexAttribArray(uvLocation);
    gl.vertexAttribPointer(uvLocation, 2, gl.FLOAT, false, 0, 0);
    if (withMaterial && buffers.material !== null) {
      gl.bindBuffer(gl.ARRAY_BUFFER, buffers.material);
      gl.enableVertexAttribArray(materialLocation);
      gl.vertexAttribPointer(materialLocation, 1, gl.FLOAT, false, 0, 0);
    } else {
      gl.disableVertexAttribArray(materialLocation);
      gl.vertexAttrib1f(materialLocation, 0);
    }
    if (buffers.tile !== null) {
      gl.bindBuffer(gl.ARRAY_BUFFER, buffers.tile);
      gl.enableVertexAttribArray(tileLocation);
      gl.vertexAttribPointer(tileLocation, 4, gl.FLOAT, false, 0, 0);
    } else {
      gl.disableVertexAttribArray(tileLocation);
      gl.vertexAttrib4f(tileLocation, 0, 0, 1, 1);
    }
  }

  /** Depth-only pass from the sun, drawing everything that can cast. */
  function renderShadowPass(shaderTimeValue) {
    const depthProgram = shadowPass.begin();
    gl.uniformMatrix4fv(depthProgram.lightViewProjection, false, lightViewProjection);
    gl.uniform1f(depthProgram.time, shaderTimeValue);
    // Only chunks inside the sun's cascade can cast into it.
    const casters = glChunkBuffers.select(extractClipPlanes(lightViewProjection)).visible;
    for (const chunk of casters) {
      if (chunk.lod) continue;
      if (chunk.opaque !== null) {
        bindInterleavedPositions(gl, chunk.opaque, 0);
        gl.drawArrays(gl.TRIANGLES, 0, chunk.opaqueVertices);
      }
      if (chunk.water !== null) {
        bindInterleavedPositions(gl, chunk.water, 0);
        gl.drawArrays(gl.TRIANGLES, 0, chunk.waterVertices);
      }
    }
    gl.enableVertexAttribArray(0);
    if (dynamicVertexCount > 0) {
      gl.bindBuffer(gl.ARRAY_BUFFER, dynamicPositionBuffer);
      gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
      gl.drawArrays(gl.TRIANGLES, 0, dynamicVertexCount);
    }
    gl.disableVertexAttribArray(0);
    shadowPass.end();
  }

  function updateLockHint() {
    const locked = document.pointerLockElement === canvas;
    lockHintEl.textContent = locked
      ? "Press Esc to release the mouse"
      : "Click to capture the mouse";
    helpEl?.classList.toggle("is-locked", locked);
  }

  hotbarEl.addEventListener("click", (event) => {
    const button = event.target.closest("[data-slot]");
    if (button !== null) selectSlot(Number(button.dataset.slot));
  });
  inventoryToggleEl.addEventListener("click", toggleInventory);
  furnaceToggleEl.addEventListener("click", toggleFurnace);
  function handleInventorySlot(slot, button = 0) {
    if (!Number.isInteger(slot) || slot < 0 || slot >= inventory.length) return;
    if (inventoryCursor === null) {
      const source = inventory[slot];
      const amount = transferAmount(source?.count ?? 0, button);
      if (amount <= 0 || itemId(source) === null) {
        setInventoryMessage("That slot is empty.");
        return;
      }
      inventoryCursor = slot;
      inventoryCursorAmount = amount;
      setInventoryMessage(button === 2
        ? `Picked up half the stack (${amount}). Choose a destination.`
        : "Choose a destination slot to move this stack.");
    } else if (slot === inventoryCursor) {
      inventoryCursor = null;
      inventoryCursorAmount = null;
      setInventoryMessage("Move cancelled.");
    } else if (moveItem(inventory, inventoryCursor, slot, inventoryCursorAmount ?? null)) {
      inventoryCursor = null;
      inventoryCursorAmount = null;
      setInventoryMessage("Item moved.");
    } else {
      setInventoryMessage("That slot cannot accept this item.");
    }
    refreshInventoryUi();
  }

  inventorySlotsEl.addEventListener("click", (event) => {
    const button = event.target.closest("[data-slot]");
    if (button === null) return;
    const slot = Number(button.dataset.slot);
    const slotItem = itemId(inventory[slot]);
    if (inventoryCursor === null && slotItem !== null && ITEM_IDS[slotItem] !== undefined
      && Number(Equipment.slot_for_item(ITEM_IDS[slotItem])) < 5) {
      if (equipInventorySlot(slot)) return;
    }
    if (event.shiftKey && inventoryCursor === null) {
      const target = findShiftTarget(inventory, slot, HOTBAR_SIZE, MAX_STACK);
      const source = inventory[slot];
      if (target !== -1 && moveItem(inventory, slot, target, source?.count ?? 0)) {
        setInventoryMessage("Item moved to the other inventory section.");
      } else {
        setInventoryMessage("No room in the other inventory section.");
      }
      refreshInventoryUi();
      return;
    }
    handleInventorySlot(slot, event.button);
  });
  inventorySlotsEl.addEventListener("contextmenu", (event) => {
    const button = event.target.closest("[data-slot]");
    if (button === null) return;
    event.preventDefault();
    handleInventorySlot(Number(button.dataset.slot), 2);
  });
  inventorySlotsEl.addEventListener("dragstart", (event) => {
    const button = event.target.closest("[data-slot]");
    if (button === null) return;
    const slot = Number(button.dataset.slot);
    if (itemId(inventory[slot]) === null) {
      event.preventDefault();
      return;
    }
    inventoryCursor = slot;
    inventoryCursorAmount = Number(inventory[slot].count ?? 0);
    event.dataTransfer.effectAllowed = "move";
  });
  inventorySlotsEl.addEventListener("dragover", (event) => {
    if (event.target.closest("[data-slot]") !== null) event.preventDefault();
  });
  inventorySlotsEl.addEventListener("drop", (event) => {
    const button = event.target.closest("[data-slot]");
    if (button === null || inventoryCursor === null) return;
    event.preventDefault();
    handleInventorySlot(Number(button.dataset.slot), 0);
  });
  inventorySlotsEl.addEventListener("dragend", () => {
    inventoryCursor = null;
    inventoryCursorAmount = null;
    refreshInventoryUi();
  });
  recipeListEl.addEventListener("click", (event) => {
    const button = event.target.closest("[data-recipe]");
    if (button !== null) craftRecipe(button.dataset.recipe);
  });
  shapedRecipeEl?.addEventListener("change", renderCraftingOutput);
  inventoryPanelEl.addEventListener("click", (event) => {
    if (event.target.closest("[data-close-inventory]") !== null) toggleInventory();
    const equipmentSlot = event.target.closest("[data-equipment-slot]")?.dataset.equipmentSlot;
    if (equipmentSlot !== undefined) unequipEquipmentSlot(Number(equipmentSlot));
    const action = event.target.closest("[data-shaped-action]")?.dataset.shapedAction;
    if (action === "load") loadShapedRecipe();
    else if (action === "craft") craftShapedRecipe();
    else if (action === "return") {
      if (returnCraftingGrid()) {
        if (shapedStatusEl !== null) shapedStatusEl.textContent = "Ingredients returned.";
        refreshInventoryUi();
      }
    }
  });
  furnacePanelEl.addEventListener("click", (event) => {
    if (event.target.closest("[data-close-furnace]") !== null) {
      setFurnaceOpen(false);
      return;
    }
    const action = event.target.closest("[data-furnace-action]")?.dataset.furnaceAction;
    if (action !== undefined) furnaceAction(action);
  });
  chestToggleEl?.addEventListener("click", () => toggleChest());
  chestPanelEl?.addEventListener("click", (event) => {
    if (event.target.closest("[data-close-chest]") !== null) {
      setChestOpen(false);
      return;
    }
    const slot = event.target.closest("[data-chest-slot]")?.dataset.chestSlot;
    if (slot !== undefined) chestAction("withdraw", Number(slot));
    const action = event.target.closest("[data-chest-action]")?.dataset.chestAction;
    if (action !== undefined) chestAction(action);
  });
  canvas.addEventListener("click", () => {
    audio.ensure();
    if (!inventoryOpen && !furnaceOpen && !chestOpen) pointerLock.request();
  });
  canvas.addEventListener("mousedown", (event) => {
    event.preventDefault();
    audio.ensure();
    if (inventoryOpen || furnaceOpen || chestOpen) return;
    if (document.pointerLockElement !== canvas) {
      pointerLock.request();
      return;
    }
    primaryAction(event.button);
  });
  window.addEventListener("mouseup", (event) => {
    if (event.button === 0) cancelMining();
  });
  window.addEventListener("blur", cancelMining);
  canvas.addEventListener("contextmenu", (event) => event.preventDefault());
  let paused = false;
  let hasLockedOnce = false;
  let deadShown = false;
  let killCount = 0;
  window.setInterval(() => {
    if (!paused && document.pointerLockElement === canvas) audio.play("ambient");
  }, 5000);
  // One daylight cycle (sin(worldTime * 0.08)) lasts 2*PI/0.08 seconds.
  const DAY_SECONDS = 78.54;
  function scatterDeathDrops() {
    const base = BigInt(Date.now()) * 1000n;
    let scattered = 0;
    for (let index = 0; index < inventory.length; index += 1) {
      const slot = inventory[index];
      const name = itemId(slot);
      const count = Number(slot?.count ?? 0);
      if (name === null || count <= 0) continue;
      if (multiplayer !== null) {
        // Stacks above 64 go out as several drops.
        for (let left = count; left > 0; left -= 64) {
          multiplayer.sendDrop({ item: ITEM_IDS[name], amount: Math.min(64, left), x: player.x, y: player.y + 0.5, z: player.z });
        }
        scattered += 1;
        continue;
      }
      dropDomainState = Entities.cons_drop(
        Entities.make_drop(base + BigInt(scattered), ITEM_IDS[name], player.x, player.y + 0.5, player.z, count),
        dropDomainState,
      );
      scattered += 1;
    }
    if (scattered > 0) {
      drops = dropViews(dropDomainState);
      for (let index = 0; index < inventory.length; index += 1) {
        const count = Number(inventory[index]?.count ?? 0);
        if (count > 0) consume(inventory, index, count);
      }
      refreshInventoryUi();
      rebuildDynamicMesh(worldTime);
    }
  }
  function closeContainerPanels() {
    if (craftingGrid.some((item) => itemId(item) !== null)) returnCraftingGrid();
    if (inventoryOpen) setInventoryOpen(false);
    if (furnaceOpen) setFurnaceOpen(false);
    if (chestOpen) setChestOpen(false);
    for (const panel of [inventoryPanelEl, furnacePanelEl, chestPanelEl]) {
      if (panel.hidden) continue;
      panel.hidden = true;
      panel.setAttribute("aria-hidden", "true");
    }
    inventoryOpen = false;
    furnaceOpen = false;
    chestOpen = false;
    inventoryCursor = null;
    inventoryCursorAmount = null;
  }

  function showDeath() {
    if (deadShown) return;
    deadShown = true;
    paused = true;
    held.clear();
    cancelMining();
    closeContainerPanels();
    audio.play("death");
    // The player has no body to come apart, so the red burst stays in
    // screen-space where it reads as "you died" rather than as a thing that
    // happened at a coordinate. The world-space puff marks where they fell.
    spawnParticles("#d03030", 14);
    emitDeathPuff(vfx, player.x, player.y, player.z, [0.62, 0.16, 0.14], 18);
    scatterDeathDrops();
    saveGame();
    if (document.pointerLockElement === canvas && typeof document.exitPointerLock === "function") {
      document.exitPointerLock();
    }
    const days = worldTime / DAY_SECONDS;
    deathStatsEl.textContent = `Survived ${days.toFixed(1)} days · level ${Number(Experience.xp_level(xpState))} · ${killCount} mob ${killCount === 1 ? "kill" : "kills"} · ${WORLD_NAME}`;
    deathEl.hidden = false;
    deathEl.setAttribute("aria-hidden", "false");
    syncModalIsolation();
    deathEl.querySelector('[data-action="respawn"]')?.focus({ preventScroll: true });
  }
  deathEl.addEventListener("click", (event) => {
    const button = event.target.closest("[data-action]");
    if (button === null) return;
    if (button.dataset.action === "respawn") {
      respawnPlayer(player, spawnCell, spawnHeight);
      mobDomainState = Entities.remove_spawn_area(
        mobDomainState,
        BigInt(spawnCell[0]),
        BigInt(spawnCell[1]),
      );
      refreshMobs();
      deadShown = false;
      paused = false;
      deathEl.hidden = true;
      deathEl.setAttribute("aria-hidden", "true");
      syncModalIsolation();
      canvas.focus({ preventScroll: true });
      updateHud();
      rebuildDynamicMesh(worldTime);
      saveGame();
      pointerLock.request();
    } else if (button.dataset.action === "quit-title") {
      saveGame();
      window.location.href = window.location.pathname;
    }
  });
  function setPaused(open) {
    if (open === paused) return;
    paused = open;
    if (open) {
      held.clear();
      cancelMining();
      saveGame();
      if (document.pointerLockElement === canvas && typeof document.exitPointerLock === "function") {
        document.exitPointerLock();
      }
      pauseSubtitleEl.textContent = `${WORLD_NAME} · ${PROFILE_NAME}`;
    }
    pauseEl.hidden = !open;
    pauseEl.setAttribute("aria-hidden", String(!open));
    syncModalIsolation();
    if (open) pauseEl.querySelector('[data-action="resume"]')?.focus({ preventScroll: true });
    else canvas.focus({ preventScroll: true });
  }
  pauseEl.addEventListener("click", (event) => {
    const button = event.target.closest("[data-action]");
    if (button === null) return;
    if (button.dataset.action === "resume") {
      setPaused(false);
      pointerLock.request();
    } else if (button.dataset.action === "quit-title") {
      saveGame();
      window.location.href = window.location.pathname;
    }
  });
  document.addEventListener("pointerlockchange", () => {
    const locked = document.pointerLockElement === canvas;
    cancelMining();
    if (locked) hasLockedOnce = true;
    pointerLock.handleChange();
    updateLockHint();
    if (!locked && hasLockedOnce && !inventoryOpen && !furnaceOpen && !chestOpen && !paused && Number(player.health) > 0) {
      setPaused(true);
    }
  });
  document.addEventListener("mousemove", (event) => {
    if (document.pointerLockElement !== canvas) return;
    const sensitivity = options.sensitivity * 0.0022;
    player.yaw += event.movementX * sensitivity;
    player.pitch = Math.max(-1.45, Math.min(1.45, player.pitch - event.movementY * sensitivity));
  });
  window.addEventListener("keydown", (event) => {
    audio.ensure();
    if (event.code === "F3") {
      event.preventDefault();
      toggleDebugOverlay();
      return;
    }
    const modal = activeModalPanel();
    if (event.code === "Escape") {
      if (inventoryOpen) toggleInventory();
      else if (furnaceOpen) setFurnaceOpen(false);
      else if (chestOpen) setChestOpen(false);
      else if (paused) {
        setPaused(false);
        pointerLock.request();
      }
      if (modal !== null) event.preventDefault();
      return;
    }
    if (modal !== null) {
      if (inventoryOpen && event.code === (options.controls.inventory ?? "KeyE")) {
        event.preventDefault();
        toggleInventory();
      } else if (furnaceOpen && event.code === (options.controls.furnace ?? "KeyR")) {
        event.preventDefault();
        setFurnaceOpen(false);
      } else if (chestOpen && event.code === (options.controls.chest ?? "KeyC")) {
        event.preventDefault();
        setChestOpen(false);
      }
      return;
    }
    if (paused) return;
    if (event.code === (options.controls.inventory ?? "KeyE")) {
      event.preventDefault();
      toggleInventory();
      return;
    }
    if (event.code === (options.controls.furnace ?? "KeyR")) {
      event.preventDefault();
      toggleFurnace();
      return;
    }
    if (event.code === (options.controls.chest ?? "KeyC")) {
      event.preventDefault();
      toggleChest();
      return;
    }
    if (event.code === (options.controls.eat ?? "KeyG")) {
      event.preventDefault();
      eatSelected();
      return;
    }
    const slot = ["Digit1", "Digit2", "Digit3", "Digit4", "Digit5", "Digit6", "Digit7", "Digit8", "Digit9"].indexOf(event.code);
    if (slot !== -1) {
      event.preventDefault();
      selectSlot(slot);
      return;
    }
    if (event.code === (options.controls.attack ?? "KeyF")) {
      event.preventDefault();
      attackNearestMob();
      return;
    }
    if (event.code === (options.controls.trade ?? "KeyT")) {
      event.preventDefault();
      tradeNearestVillager();
      return;
    }
    if (event.code === (options.controls.sleep ?? "KeyN")) {
      event.preventDefault();
      sleepAtBed();
      return;
    }
    if (event.code === (options.controls.drop ?? "KeyQ")) {
      event.preventDefault();
      if (!event.repeat) dropInventoryItem(selectedSlot, event.shiftKey);
      return;
    }
    const movementCodes = new Set([
      "KeyW", "KeyA", "KeyS", "KeyD", "Space", "ShiftLeft", "ShiftRight", "ControlLeft", "ControlRight",
      options.controls.sneak,
      options.controls.sprint,
    ]);
    if (movementCodes.has(event.code)) {
      event.preventDefault();
      held.add(event.code);
    }
  });
  window.addEventListener("keyup", (event) => held.delete(event.code));
  window.addEventListener("resize", resizeCanvas);
  window.addEventListener("beforeunload", saveGame);

  rebuildHorizon();
  rebuildMesh();
  rebuildDynamicMesh(worldTime);
  refreshInventoryUi();
  setInventoryOpen(false);
  setFurnaceOpen(false);
  updateLockHint();
  vitalsEl.hidden = false;
  coordsEl.style.display = options.showCoords ? "" : "none";
  const brandSpan = document.querySelector("#hud .brand span");
  if (brandSpan !== null) brandSpan.textContent = `${WORLD_NAME} · ${PROFILE_NAME} · ${worldModeLabel(WORLD_MODE)}`;
  updateHud();
  const testApi = testMode ? {
    // Test-only spawner for a single mob of a chosen kind. The roster owns the
    // kind list, so the smoke can ask for a cow as easily as for a brute and then
    // compare what each body actually puts on the GPU.
    spawnMobForTest: (kind = 2, distance = 0.5) => {
      if (PEACEFUL || mobDomainState === null) return null;
      const entry = mobKind(kind);
      if (entry === null) return null;
      const id = Math.max(0, ...mobs.map((mob) => Number(mob.id))) + 1;
      const offset = Number.isFinite(Number(distance)) ? Number(distance) : 0.5;
      mobDomainState = Entities.cons_mob(
        Entities.make_mob(
          BigInt(id),
          entry.kind,
          player.x + offset,
          player.y,
          player.z + 0.5,
          entry.kind === 4 ? 40.0 : 20.0,
          true,
        ),
        mobDomainState,
      );
      mobs = mobViews(mobDomainState);
      rebuildDynamicMesh(worldTime);
      return { ...mobs[0] };
    },
    setWorldTimeForTest: (value) => {
      worldTime = Math.max(0, Number(value) || 0);
      daylight = daylightForTime(worldTime);
      return { worldTime, daylight };
    },
    // Test-only wall builder for the melee line-of-sight smoke. It reuses the
    // same edit path as a player placement so the mesh and light stay coherent.
    setBlockForTest: (x, y, z, block = 1) => {
      const cellX = Math.trunc(Number(x));
      const cellY = Math.trunc(Number(y));
      const cellZ = Math.trunc(Number(z));
      if (!inside(cellX, cellY, cellZ) || !world.isActive(cellX, cellZ)) return false;
      setBlock(cellX, cellY, cellZ, Math.trunc(Number(block)) || 1);
      terrainMeshCache.invalidateBlock(cellX, cellZ);
      rebuildMesh();
      return blockAt(cellX, cellY, cellZ);
    },
    // Test-only cleanup so a combat scenario can start from a known mob set.
    // It calls the same Bend despawn contract the simulation timer uses.
    despawnMobsForTest: (radius = 0) => {
      if (mobDomainState === null) return 0;
      mobDomainState = Entities.despawn(mobDomainState, player.x, player.z, Math.max(0, Number(radius) || 0));
      mobs = mobViews(mobDomainState);
      rebuildDynamicMesh(worldTime);
      return mobs.length;
    },
  } : {};

  window.__bend2craft = {
    multiplayer: () => (multiplayer === null ? null : {
      id: multiplayer.id,
      connected: multiplayer.connected,
      seq: multiplayer.seq,
      seed: multiplayer.seed,
      time: multiplayer.worldTime(),
      stats: { ...multiplayer.stats },
      players: remotePlayers.views(performance.now()).map(({ id, name, x, y, z }) => ({ id, name, x, y, z })),
    }),
    presentation: {
      get renderer() { return rendererKind; },
      get shaderQuality() { return shaderQuality; },
      get postColorFormat() { return postPipeline?.capabilities.name ?? null; },
      get depthSampling() { return postPipeline?.depthSampling.supported ?? false; },
      get shadowSupported() { return shadowPass?.supported ?? false; },
      get shadowMapSize() { return shadowPass?.mapSize ?? 0; },
      get visualQualityLevel() { return visualQuality?.level ?? -1; },
      get visualQualityName() { return visualQuality?.tier.name ?? null; },
      // A pinned tier turns the frame-time safety net off, so the diagnostic
      // has to report that or a smooth frame is indistinguishable from a
      // deliberately held tier.
      get visualQualityAuto() { return visualQuality?.auto ?? false; },
      get cloudSteps() { return visualQuality?.tier.cloudSteps ?? 0; },
      get smoothedFrameMs() { return visualQuality?.smoothedFrameMs ?? 0; },
      get sunScreen() { return [...sunScreenPosition]; },
      get sunVisibleForGodrays() { return sunVisibleForGodrays; },
      get sceneTargetSize() {
        return postPipeline === null ? null : [postPipeline.scene.width, postPipeline.scene.height];
      },
      get sunDirection() { return lastSunDirection; },
      // Effect diagnostics. A particle system that silently stops emitting looks
      // exactly like a particle system that is drawing perfectly, so the count
      // of live particles and of burning bodies has to be observable from
      // outside for a browser check to mean anything.
      get vfxParticles() { return vfx.count; },
      get vfxVertexCount() { return vfxVertexCount; },
      // The pacing state, so a browser check can tell "the cap is applied" from
      // "the cap is stored but the loop ignores it" - a difference no screenshot
      // and no frame-rate number alone can establish.
      get fpsLimit() { return framePacer?.limit ?? 0; },
      get frameBudgetMs() { return framePacer?.targetFrameMs ?? 0; },
      get displayCeilingMs() { return framePacer?.ceilingMs ?? null; },
      get burningMobs() { return mobs.filter((mob) => mob.alive && mob.burning).length; },
    },
    world: {
      seed: seedLabel(SEED),
      mode: WORLD_MODE,
      chunkSize: CHUNK_SIZE,
      renderRadius: CHUNK_RENDER_RADIUS,
      maxY: MAX_Y,
      get activeChunks() { return world.activeChunkCount(); },
      get pinnedChunks() { return world.pinnedChunkCount(); },
      get pendingChunks() { return world.pendingChunkCount(); },
      get simulationTime() { return Number(Simulation.time(worldSimulation.simulation)); },
      get simulationChunks() { return Number(Simulation.pinned_count(worldSimulation.simulation)); },
      workerCount: chunkWorkers.length,
      get workerRequests() { return workerRequestCount; },
      get workerResponses() { return workerResponseCount; },
      get workerHydrates() { return workerHydrateCount; },
      get workerRejects() { return workerRejectCount; },
      get blockCount() { return blockCount; },
    },
    getMeshStats: () => {
      const mesh = terrainMeshCache.snapshot();
      return {
        blockCount: mesh.blockCount,
        // Per-chunk publication keeps no merged quad list; report the uploaded
        // terrain faces instead (distant LOD sections included).
        quadCount: terrainQuadCount + waterQuadCount,
        rebuildCount: mesh.rebuildCount,
        dirtyChunks: mesh.dirtyChunks,
        sample: mesh.quads
          .filter((quad) => quad.block === 4 || quad.block === 5)
          .slice(0, 12)
          .map((quad) => ({
            block: quad.block,
            face: quad.faceIndex,
            x: quad.x,
            y: quad.y,
            z: quad.z,
            light: quad.light,
          })),
      };
    },
    getBlock: (x, y, z) => blockAt(x, y, z),
    setViewForTest: (x, y, z, yaw, pitch) => {
      Object.assign(player, {
        x: Number(x),
        y: Number(y),
        z: Number(z),
        yaw: Number(yaw),
        pitch: Number(pitch),
        velocityY: 0,
        grounded: true,
      });
      cancelMining();
      return raycast(world, player);
    },
    getRaycastTarget: () => raycast(world, player),
    interactForTest: (button) => {
      interact(Number(button));
      return raycast(world, player);
    },
    getLight: (x, y, z) => lightAt(x, y, z),
    getEdits: () => world.getEdits(),
    getLightDirtyCells: () => world.getLightDirtyCells(),
    getInventory: () => inventory.map((item) => ({ ...item })),
    getHeldItem: () => heldItemPose(selectedItem(inventory, selectedSlot)),
    getCharacterView: () => characterRenderDescriptor(selectedItem(inventory, selectedSlot)),
    getMobs: () => mobs.map((mob) => ({ ...mob })),
    ...testApi,
    getVillagers: () => villagers.map((villager) => ({ ...villager })),
    getDrops: () => drops.map((drop) => ({ ...drop })),
    getChest: () => chestSlotsView(activeChestState() ?? ChestDomain.empty()),
    getEquipment: () => ({ ...equipmentState }),
    getDropGroundStats: () => dropGroundCache?.stats() ?? { hits: 0, misses: 0, size: 0 },
    getEntityBucketStats: () => ({ ...entityBucketStats }),
    getCrops: cropViews,
    getFarmland: farmlandViews,
    getFluids: () => {
      const flows = [];
      for (let node = Fluids.state_flows(worldSimulation.fluids); node?.$ === "Con"; node = node.tail) {
        flows.push({
          x: Number(node.head.x),
          y: Number(node.head.y),
          z: Number(node.head.z),
          level: Number(node.head.level),
          block: Number(node.head.block),
        });
      }
      return flows;
    },
    getFire: () => {
      const cells = [];
      for (let node = Fire.state_cells(worldSimulation.fire); node?.$ === "Con"; node = node.tail) {
        cells.push({
          x: Number(node.head.x),
          y: Number(node.head.y),
          z: Number(node.head.z),
          age: Number(node.head.age),
        });
      }
      return cells;
    },
    getPlayer: () => ({ ...player }),
    getInputState: () => ({
      held: [...held],
      pointerLocked: document.pointerLockElement === canvas,
      inventoryOpen,
      furnaceOpen,
      chestOpen,
      paused,
    }),
    getMovementDiagnostics: () => ({ calls: moveFrameCalls, active: moveFrameActive, player: { ...player } }),
    getVisualMotion: () => ({
      speed: visualSpeed,
      sample: { ...visualSample },
      motion: cameraMotion(worldTime, { speed: visualSpeed, grounded: player.grounded }),
    }),
    getFrameDiagnostics: () => ({ ...frameDiagnostics(), debugVisible }),
    getAtlasTexelProbe: (tile = 1) => atlasTexelDiagnostics(Math.trunc(tile)),
    // Synchronous WebGL readback keeps the historical flat RGBA array. The
    // WebGPU path is inherently async, so it refuses here with an explicit
    // pointer instead of returning a promise that callers would not await.
    readFramePixels: (x, y, width, height) => {
      if (gpuRenderer !== null) {
        throw new Error(
          "WebGPU frame readback is asynchronous; use readFramePixelsAsync instead.",
        );
      }
      const left = Math.trunc(x);
      const bottom = Math.trunc(y);
      const pixelWidth = Math.trunc(width);
      const pixelHeight = Math.trunc(height);
      if (left < 0 || bottom < 0 || pixelWidth < 1 || pixelHeight < 1
        || left + pixelWidth > canvas.width || bottom + pixelHeight > canvas.height) {
        throw new RangeError("frame pixel region is outside the canvas");
      }
      const pixels = new Uint8Array(pixelWidth * pixelHeight * 4);
      gl.readPixels(left, bottom, pixelWidth, pixelHeight, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
      return Array.from(pixels);
    },
    readFramePixelsAsync: async (x, y, width, height) => {
      if (gpuRenderer === null) {
        const left = Math.trunc(x);
        const bottom = Math.trunc(y);
        const pixelWidth = Math.trunc(width);
        const pixelHeight = Math.trunc(height);
        if (left < 0 || bottom < 0 || pixelWidth < 1 || pixelHeight < 1
          || left + pixelWidth > canvas.width || bottom + pixelHeight > canvas.height) {
          throw new RangeError("frame pixel region is outside the canvas");
        }
        const pixels = new Uint8Array(pixelWidth * pixelHeight * 4);
        gl.readPixels(left, bottom, pixelWidth, pixelHeight, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        return { left, bottom, width: pixelWidth, height: pixelHeight, pixels: Array.from(pixels) };
      }
      const region = await gpuRenderer.readFramePixels(x, y, width, height);
      return { ...region, pixels: Array.from(region.pixels) };
    },
    getFrameReadbackSupport: () => (gpuRenderer === null
      ? { supported: true, reason: null, backend: "webgl" }
      : { ...gpuRenderer.getReadbackSupport(), backend: "webgpu" }),
    toggleDebug: toggleDebugOverlay,
    hurt: (amount) => applyDamage(player, amount),
    glBufferSizes: () => {
      if (gpuRenderer !== null) return gpuRenderer.getStats();
      return {
        ...glChunkBuffers.stats(),
        ...(glSubmit ?? {}),
        terrainVertexCount,
        waterVertexCount,
        dynamicVertexCount,
        positionNull: glChunkBuffers === null,
      };
    },
    toggleInventory,
    toggleChest,
    selectSlotForTest: (slot) => {
      selectSlot(slot);
      return true;
    },
    loadChunksAt: (x, z, budget = Infinity, render = true) => {
      const result = world.loadAround(x, z, undefined, budget);
      if (result.changed && render) rebuildMesh();
      return result;
    },
    teleportForTest: (x, z, y = 8, yaw = player.yaw, pitch = player.pitch) => {
      setPaused(true);
      Object.assign(player, {
        x: Number(x),
        y: Number(y),
        z: Number(z),
        yaw: Number(yaw),
        pitch: Number(pitch),
        velocityY: 0,
        grounded: true,
      });
      cancelMining();
      rebuildHorizon();
      const result = world.loadAround(player.x, player.z, undefined, 9);
      streamingMeshScheduler?.request();
      updateHud();
      return result;
    },
    resumeForTest: () => {
      setPaused(false);
      return { x: player.x, y: player.y, z: player.z };
    },
    setVisualTimeForTest: (seconds) => {
      worldTime = Math.max(0, Number(seconds) || 0);
      daylight = daylightForTime(worldTime);
      skyCssTick = -1;
      return { worldTime, daylight };
    },
    pinChunk: (x, z) => world.pinChunk(x, z),
    unpinChunk: (x, z) => world.unpinChunk(x, z),
    save: saveGame,
    // The redstone surface a browser smoke drives: place a component, operate a
    // lever, step the circuit, and read what the contract decided. Every answer
    // comes from the contract in world/redstone_all.bend.
    redstoneIds: () => ({ ...redstoneIds }),
    redstoneBlockAt: (x, y, z) => redstoneBlockAt(x, y, z),
    redstoneWirePowerAt: (x, y, z) => redstonePower(x, y, z),
    redstoneLampLitAt: (x, y, z) => redstoneLit(redstoneIds.lamp, x, y, z),
    redstoneTorchLitAt: (x, y, z) => redstoneLit(redstoneIds.torch, x, y, z),
    redstonePistonExtendedAt: (x, y, z) => redstoneLit(redstoneIds.head, x, y, z),
    redstoneToggleLeverAt: (x, y, z) => {
      toggleLever(redstoneState, x, y, z);
      return true;
    },
    redstonePlaceAt: (block, x, y, z) => {
      redstoneState.circuit = placeRedstoneComponent(circuitOf(redstoneState), block, x, y, z);
      setBlock(x, y, z, block);
      terrainMeshCache.invalidateBlock(x, z);
      return blockAt(x, y, z) === block;
    },
    redstoneStep: (ticks = 1) => {
      for (let tick = 0; tick < Number(ticks); tick += 1) tickRedstoneOnce();
      return true;
    },
    attack: attackNearestMob,
    primaryActionForTest: (button) => primaryAction(Number(button)),
    drop: (stack = false) => dropInventoryItem(selectedSlot, stack),
    trade: tradeNearestVillager,
    sleep: sleepAtBed,
    seedWaterAt,
    seedLavaAt,
    igniteFireAt,
    collectWaterAt,
    collectLavaAt,
    placeWaterAt,
    placeLavaAt,
    toggleDoor: toggleDoorAt,
    tickVillagers: (dt = 1) => {
      const changed = updateVillagers(dt);
      if (changed) rebuildDynamicMesh(worldTime);
      return changed;
    },
    craft: craftRecipe,
    eat: eatSelected,
    chestAction,
    // Test-only: open a container without aiming at it (multiplayer smoke).
    openChestForTest: (x, y, z) => setChestOpen(true, [x, y, z]),
    openFurnaceForTest: (x, y, z) => setFurnaceOpen(true, [x, y, z]),
    collect: (item, amount = 1) => {
      const ok = collectItem(inventory, item, amount);
      if (ok) {
        refreshInventoryUi();
        updateHud();
      }
      return ok;
    },
    getFurnace: () => {
      const state = activeFurnaceState();
      return state === null ? null : { ...state };
    },
    getFurnacePosition: () => activeFurnace?.slice() ?? null,
    placeFurnaceAt: (x, y, z) => {
      const slot = furnaceSlot("furnace");
      if (slot === -1) return false;
      selectedSlot = slot;
      const ok = placeBlockAt(x, y, z, selectedItem(inventory, selectedSlot));
      if (ok) {
        refreshInventoryUi();
        updateHud();
        rebuildMesh();
      }
      return ok;
    },
    placeAt: (item, x, y, z) => {
      const slot = furnaceSlot(item);
      if (slot === -1) return false;
      selectedSlot = slot;
      const ok = placeBlockAt(x, y, z, selectedItem(inventory, selectedSlot));
      if (ok) {
        refreshInventoryUi();
        updateHud();
        rebuildMesh();
      }
      return ok;
    },
    getFurnaces: () => furnaceWorldState,
    tillAt: (x, y, z) => {
      const slot = furnaceSlot("wooden_hoe");
      if (slot === -1) return false;
      selectedSlot = slot;
      const ok = tillBlockAt(x, y, z);
      if (ok) {
        refreshInventoryUi();
        updateHud();
        rebuildMesh();
      }
      return ok;
    },
    plantCropAt: (x, y, z) => {
      const slot = furnaceSlot("wheat_seeds");
      if (slot === -1) return false;
      selectedSlot = slot;
      const ok = placeCropAt(x, y, z);
      if (ok) {
        refreshInventoryUi();
        updateHud();
        rebuildMesh();
      }
      return ok;
    },
    harvestCropAt,
    furnaceAction,
    tickFurnace,
    toggleFurnace,
    get isInventoryOpen() { return inventoryOpen; },
    get isFurnaceOpen() { return furnaceOpen; },
    get isChestOpen() { return chestOpen; },
  };

  let villagerSimulationSteps = 0;
  let footstepTimer = 0;
  const playerTicker = createFixedTicker(1 / 60, (dt) => {
    if (!playerSpawnReady) {
      const cellX = Math.floor(player.x);
      const cellY = Math.floor(player.y) - 1;
      const cellZ = Math.floor(player.z);
      const below = cellY >= 0 ? blockAt(cellX, cellY, cellZ) : 0;
      if (!world.isActive(cellX, cellZ) || below === 0 || below === 7 || below === 21 || below === 24) {
        moveFrameActive = false;
        return;
      }
      playerSpawnReady = true;
    }
    if (world.activeChunkCount() <= 0) {
      moveFrameActive = false;
      return;
    }
    moveFrameCalls += 1;
    moveFrameActive = true;
    movePlayer(world, player, held, dt, spawnCell, spawnHeight, Number(World.width()), Number(World.depth()), options.controls);
    if (player.grounded && visualSpeed > 0.65) {
      footstepTimer += dt;
      if (footstepTimer >= 0.38) {
        footstepTimer = 0;
        audio.play("step");
      }
    } else {
      footstepTimer = 0;
    }
    if (isInWater(world, player)) {
      // The whole field, not a slice of it: a bounded window here reads as a current
      // that stops at an invisible line partway across a pool. The contract's own
      // cap is already applied to the state, so this is at most that many cells.
      const [pushX, pushZ] = waterCurrentPush(Fluids.state_flows(worldSimulation.fluids), player.x, player.y, player.z);
      if (pushX !== 0 || pushZ !== 0) {
        player.x += pushX * dt;
        player.z += pushZ * dt;
      }
    }
    if (world.loadAround(player.x, player.z).changed) playerStreamingDirty = true;
  });
  let previousPlayerTime = performance.now();
  window.setInterval(() => {
    const now = performance.now();
    const elapsed = Math.min((now - previousPlayerTime) / 1000, 0.25);
    previousPlayerTime = now;
    if (!paused) playerTicker.advance(elapsed);
  }, 16);

  // Night spawns use Bend ground queries for validation; candidate cells
  // with negative coordinates are skipped because the Bend world contract
  // addresses columns with Nat.
  function spawnNightMobs() {
    if (PEACEFUL || mobDomainState === null) return;
    const spawns = nightSpawns({ seed: SEED, mobs, anchorX: player.x, anchorZ: player.z, maxY: MAX_Y });
    let nextId = 1;
    for (const mob of mobs) nextId = Math.max(nextId, Number(mob.id) + 1);
    for (const spawn of spawns) {
      mobDomainState = Entities.cons_mob(
        Entities.make_mob(BigInt(nextId), spawn.kind, spawn.x, spawn.y, spawn.z, spawn.health, true),
        mobDomainState,
      );
      nextId += 1;
    }
    if (spawns.length > 0) {
      mobs = mobViews(mobDomainState);
      rebuildDynamicMesh(worldTime);
    }
  }
  let nightSpawnTimer = 0;
  let despawnTimer = 0;
  const simulationTicker = createFixedTicker(0.2, (dt) => {
    if (!isPlayerAlive(player)) {
      showDeath();
      return;
    }
    // A multiplayer server runs the mobs and drops; this client only picks up.
    if (multiplayer === null) {
      updateMobs(dt);
      stepDrops(dt);
    }
    collectNearbyDrops();
    // A multiplayer server simulates fluids, fire, crops and villagers.
    if (multiplayer === null && tickFluids()) simulationTerrainDirty = true;
    if (lavaContact(world, player)) applyLavaDamage(player, dt);
    nightSpawnTimer += dt;
    if (nightSpawnTimer >= 5) {
      nightSpawnTimer = 0;
      if (daylight < NIGHT_DAYLIGHT && multiplayer === null) spawnNightMobs();
    }
    despawnTimer += dt;
    if (despawnTimer >= 10) {
      despawnTimer = 0;
      if (mobDomainState !== null && multiplayer === null) {
        mobDomainState = Entities.despawn(mobDomainState, player.x, player.z, 48.0);
        mobs = mobViews(mobDomainState);
      }
    }
    villagerSimulationSteps += 1;
    if (villagerSimulationSteps >= 5 && multiplayer === null) {
      villagerSimulationSteps = 0;
      if (updateVillagers(1.0)) simulationTerrainDirty = true;
    }
    tickFurnace();
  });
  let previousSimulationTime = performance.now();
  window.setInterval(() => {
    const now = performance.now();
    const elapsed = Math.min((now - previousSimulationTime) / 1000, 1.6);
    previousSimulationTime = now;
    if (!paused) simulationTicker.advance(elapsed);
  }, 50);

  // Keep edits, inventory and simulation state durable during long sessions;
  // beforeunload alone loses progress when a tab or browser process crashes.
  window.setInterval(saveGame, 5000);

  // Measure the display's refresh cadence from an empty animation-frame loop,
  // before the world is drawn. The pacer cannot infer it from the game's own
  // frames: if the renderer is already slower than the panel, every interval on
  // record is slow, and a quality controller aiming at that "ceiling" believes it
  // is on budget while dropping half its frames. Measured on an M1 Pro at
  // 3024x1890, that is the difference between auto settling on `medium` at 67 FPS
  // and `low` at 105 FPS on the same machine.
  const probedCadenceMs = await measureDisplayCadenceMs();
  framePacer.seedCeiling(probedCadenceMs);
  visualQuality.setTargetFrameMs(framePacer.targetFrameMs);

  let previousTime = performance.now();
  let highlightFrame = 0;
  function frame(now) {
    // The cap is applied here, at the one place that decides whether the frame
    // body runs. Everything downstream - simulation, mesh rebuilds, the debug
    // overlay - is downstream of this branch, so a capped frame costs a callback
    // and nothing else.
    //
    // `dt` is measured from the last *drawn* frame, not the last callback, so a
    // skipped frame does not silently advance the world clock in 8 ms steps
    // while every movement stays correct.
    if (!framePacer.shouldRender(now)) {
      requestAnimationFrame(frame);
      return;
    }
    const frameElapsedMs = Math.max(now - previousTime, 0.1);
    const dt = Math.min(frameElapsedMs / 1000, 0.05);
    previousTime = now;
    frameMetrics = sampleFrame(frameMetrics, frameElapsedMs);
    // The pacer may have learned a faster (or slower) display cadence since the
    // last frame, and the cap can be the target outright. Re-pointing the
    // controller every frame keeps its budgets on the period actually being asked
    // for, which is what stops a 30 FPS cap from reading as a renderer in trouble.
    visualQuality.setTargetFrameMs(framePacer.targetFrameMs);
    if (!paused) {
      // Redstone ticks on its own 20Hz clock, counted from real elapsed time so a
      // slow frame does not silently speed the circuit up or stall it. The whole
      // circuit is stepped at most a few times per frame; a frame that lands no
      // tick costs one accumulator add.
      redstoneAccumulator += dt;
      let redstoneSteps = 0;
      while (redstoneAccumulator >= REDSTONE_TICK_SECONDS && redstoneSteps < 4) {
        redstoneAccumulator -= REDSTONE_TICK_SECONDS;
        redstoneSteps += 1;
        tickRedstoneOnce();
      }
      // A frame that fell far behind drops the backlog rather than trying to catch
      // up, which would make a slow machine run the circuit even slower.
      if (redstoneAccumulator > REDSTONE_TICK_SECONDS * 4) redstoneAccumulator = 0;
      updateMining(now);
      const sampleSeconds = Math.max((now - visualSample.time) / 1000, 0.001);
      visualSpeed = Math.min(6, Math.hypot(player.x - visualSample.x, player.z - visualSample.z) / sampleSeconds);
      visualSample = { x: player.x, z: player.z, time: now };
      // A multiplayer world runs on the server's clock, so everyone shares one day.
      worldTime = multiplayer === null ? worldTime + dt : multiplayer.worldTime();
      daylight = daylightForTime(worldTime);
      if (playerStreamingDirty) playerStreamingDirty = false;
      if (world.loadAround(player.x, player.z).changed) {
        rebuildHorizon();
        rebuildMesh(false);
      } else if (rebuildHorizon()) {
        streamingMeshScheduler?.request();
      }
      if (simulationTerrainDirty) {
        simulationTerrainDirty = false;
        rebuildMesh(false);
      }
      if (multiplayer !== null) {
        mobs = entityMirror.mobs(now);
        drops = entityMirror.drops();
      }
      rebuildDynamicMesh(worldTime);
      multiplayer?.sendPose({ x: player.x, y: player.y, z: player.z, yaw: player.yaw, pitch: player.pitch }, now);
      // Fire is emitted from the frame, not the simulation tick: the domain
      // decides which mobs are burning, but the plume has to run at the rate the
      // player sees, and the simulation only steps at 5Hz.
      updateVfx(dt);
      updateBurnAudio(dt);
      updateHud();
      highlightFrame = (highlightFrame + 1) % 6;
      if (highlightFrame === 0) updateTargetHighlight();
      if (!deadShown && Number(player.health) <= 0) showDeath();
    }
    updateDebugOverlay();
    render();
    requestAnimationFrame(frame);
  }

  // ---- multiplayer --------------------------------------------------------
  // The server's Bend room orders every edit; each accepted batch comes back
  // to every player, this one included, and is replayed here in sequence
  // order, so all players converge on the room's world. Cells in loaded chunks
  // are written and relit; the rest only join the edit log, and any chunk
  // request in flight for them is re-requested with the new log.
  function applyServerEdits(wireEdits, fromSelf = false) {
    const changes = [];
    const unloaded = [];
    for (const [storedX, y, storedZ, value] of wireEdits) {
      const x = worldCoordinate(storedX);
      const z = worldCoordinate(storedZ);
      if (!inside(x, y, z)) continue;
      if (!world.isLoaded(x, z)) unloaded.push({ x, y, z, value });
      else if (blockAt(x, y, z) !== value) changes.push({ x, y, z, value });
    }
    // Our own batch, already predicted everywhere it is loaded: nothing moves.
    if (fromSelf && unloaded.length === 0 && changes.length === 0) return false;
    const previous = changes.map((change) => blockAt(change.x, change.y, change.z));
    const nextEdits = Multiplayer.merge(wireEditsToBend(wireEdits), world.getEdits());
    if (!world.mergeEdits(nextEdits, changes, unloaded)) return false;
    changes.forEach((change, index) => {
      dropGroundCache?.invalidate(change.x, change.z);
      if (previous[index] !== 0) hiddenTerrainBlocks.add(`${change.x},${change.y},${change.z}`);
      terrainMeshCache.invalidateBlock(change.x, change.z);
      invalidateVillagerPath(change.x, change.y, change.z);
    });
    if (changes.length > 0) {
      terrainImmediateDirty = true;
      simulationTerrainDirty = true;
      // The frame loop rebuilds on its own; a paused game still shows the
      // other players' work.
      if (paused) rebuildMesh(false);
    }
    return changes.length > 0;
  }

  function updatePlayersOnline() {
    if (playersOnlineEl === null) return;
    if (multiplayer === null) {
      playersOnlineEl.hidden = true;
      return;
    }
    playersOnlineEl.hidden = false;
    const connected = multiplayer.connected;
    playersOnlineEl.classList.toggle("is-offline", !connected);
    playersOnlineEl.textContent = connected
      ? `${remotePlayers.count() + 1} online · ${MULTIPLAYER_HOST}`
      : `offline · ${MULTIPLAYER_HOST}`;
  }

  // Names float above remote players, projected with the frame's camera.
  function updateNametags(viewProjection) {
    if (nametagsEl === null) return;
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    const seen = new Set();
    for (const remote of remotePlayers.views(performance.now())) {
      seen.add(remote.id);
      let tag = nametagElements.get(remote.id);
      if (tag === undefined) {
        tag = document.createElement("div");
        tag.className = "nametag";
        nametagsEl.append(tag);
        nametagElements.set(remote.id, tag);
      }
      if (tag.textContent !== remote.name) tag.textContent = remote.name;
      const clip = transformPoint(viewProjection, [remote.x, remote.y + 2.15, remote.z]);
      const distance = Math.hypot(remote.x - player.x, remote.y - player.y, remote.z - player.z);
      const ndcX = clip[0] / clip[3];
      const ndcY = clip[1] / clip[3];
      const visible = clip[3] > 0.1 && distance < 64 && Math.abs(ndcX) < 1.2 && Math.abs(ndcY) < 1.2;
      tag.hidden = !visible;
      if (!visible) continue;
      tag.style.transform = `translate(${((ndcX * 0.5 + 0.5) * width).toFixed(1)}px, ${((0.5 - ndcY * 0.5) * height).toFixed(1)}px) translate(-50%, -100%)`;
    }
    for (const [id, tag] of nametagElements) {
      if (seen.has(id)) continue;
      tag.remove();
      nametagElements.delete(id);
    }
  }

  if (multiplayer !== null) {
    const joinedAt = performance.now();
    for (const other of multiplayer.players) remotePlayers.join(other, joinedAt);
    multiplayer.on("edits", (message) => applyServerEdits(message.edits, message.from === multiplayer.id));
    multiplayer.on("revert", (message) => applyServerEdits(message.edits));
    const applyServerFurnace = (furnace) => {
      furnaceWorldState = mirrorServerFurnace(furnaceWorldState, furnace);
      const x = worldCoordinate(furnace.pos[0]);
      const z = worldCoordinate(furnace.pos[2]);
      if (!sameFurnacePosition(activeFurnace, x, furnace.pos[1], z)) return;
      if (furnace.state === null) {
        activeFurnace = null;
        setFurnaceOpen(false);
      } else if (furnaceOpen) {
        updateFurnaceStatus();
      }
    };
    multiplayer.on("furnace", applyServerFurnace);
    multiplayer.on("entities", (message) => {
      const now = performance.now();
      entityMirror.push(message, now);
      if (Array.isArray(message.villagers)) {
        let list = { $: "Nil" };
        for (let index = message.villagers.length - 1; index >= 0; index -= 1) {
          const [id, profession, vx, vy, vz, homeX, homeZ, resting] = message.villagers[index];
          list = {
            $: "Con",
            head: { $: "Villager", id: BigInt(id), profession, x: vx, y: vy, z: vz, home_x: BigInt(homeX), home_z: BigInt(homeZ), resting: resting === 1 },
            tail: list,
          };
        }
        villagerDomainState = list;
        villagers = villagerViews(villagerDomainState);
        if (Number.isInteger(message.villagerTick)) villagerTick = message.villagerTick;
      }
      // The frame blends positions; this keeps a paused client current too.
      mobs = entityMirror.mobs(now);
      drops = entityMirror.drops();
    });
    multiplayer.on("hurt", (message) => {
      if (!isPlayerAlive(player)) return;
      const blocking = Equipment.blocks_damage(equipmentState)
        || itemId(selectedItem(inventory, selectedSlot)) === "shield";
      applyDamage(player, Number(message.amount) * (blocking ? 0.34 : 1));
      audio.play("hurt");
      if (!isPlayerAlive(player)) showDeath();
    });
    // The server refused a move (too fast, or into a block): back to the last
    // pose it accepted.
    multiplayer.on("correct", (message) => placePlayer(player, message.x, message.y, message.z));
    multiplayer.on("furnaces", (message) => message.furnaces.forEach(applyServerFurnace));
    multiplayer.on("chest", (chest) => {
      chestWorldState = mirrorServerChest(chestWorldState, chest);
      const x = worldCoordinate(chest.pos[0]);
      const z = worldCoordinate(chest.pos[2]);
      if (activeChest === null || !sameFurnacePosition(activeChest, x, chest.pos[1], z)) return;
      if (chest.slots === null) {
        setChestOpen(false);
        activeChest = null;
        if (chestToggleEl !== null) chestToggleEl.hidden = true;
      } else if (chestOpen) {
        refreshChestUi();
      }
    });
    multiplayer.on("pose", (message) => remotePlayers.pose(message.id, message, performance.now()));
    multiplayer.on("joined", (message) => {
      remotePlayers.join(message.player, performance.now());
      showToast(`${message.player.name} joined the game`);
      updatePlayersOnline();
    });
    multiplayer.on("left", (message) => {
      const name = remotePlayers.name(message.id);
      remotePlayers.leave(message.id);
      if (name !== null) showToast(`${name} left the game`);
      updatePlayersOnline();
    });
    multiplayer.on("disconnect", () => {
      showToast("Lost the connection to the server. Your changes are no longer shared.");
      updatePlayersOnline();
    });
    multiplayer.start();
    updatePlayersOnline();
  }
  requestAnimationFrame(frame);
} catch (error) {
  showError(error);
}
}

await bootGame();
