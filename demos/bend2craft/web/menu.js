// Main-menu controller: profiles, worlds, options and help screens.
// Runs instead of the game when the page loads without ?play=1. Starting a
// session navigates (full reload), so the engine always boots clean and no
// teardown is needed when quitting back to the title.
import {
  createProfile,
  createWorld,
  deleteProfile,
  deleteWorld,
  getActiveProfile,
  getProfile,
  getWorld,
  loadProfilesDoc,
  saveKeyFor,
  saveProfilesDoc,
  touchProfile,
  touchWorld,
} from "./profiles.js";
import {
  audioVolumesFromOptions,
  createDefaultOptions,
  createWorldConfig,
  DEFAULT_GRAPHICS_QUALITY,
  DEFAULT_RENDER_DISTANCE,
  GRAPHICS_EFFECTS,
  GRAPHICS_QUALITY_CHOICES,
  MAX_RENDER_DISTANCE,
  MAX_VOLUME,
  MIN_RENDER_DISTANCE,
  MIN_VOLUME,
  loadOptions,
  randomSeedText,
  saveOptions,
  validateWorldConfig,
  worldModeLabel,
  DEFAULT_LOD_DISTANCE,
  normalizeLodDistance,
  DEFAULT_FPS_LIMIT,
  FPS_LIMIT_CHOICES,
  normalizeFpsLimit,
} from "./settings.js";
import { VISUAL_QUALITY_TIERS } from "./visual-quality.js";
import { graphicsEffectByKey, normalizeGraphicsEffects } from "./graphics-effects.js";
import { getAudioMixer } from "./audio.js";
import { probeWebGpu } from "./webgpu-capabilities.js";
import { describeBackendNotice, takeBackendNotice } from "./backend-notice.js";
import { clearTransactional } from "./persistent-save.js";
import { continueTarget } from "./menu-navigation.js";
import { nextFocusTarget, setShellInert } from "./modal-focus.js";
import { multiplayerUrl } from "./multiplayer-protocol.js";

const LAST_SERVER_KEY = "bend2craft-last-server";

function element(id) {
  const node = document.getElementById(id);
  if (node === null) throw new Error(`Menu element is missing: ${id}.`);
  return node;
}

function formatDate(timestamp) {
  if (!timestamp) return "never played";
  return new Date(timestamp).toLocaleString();
}

function playUrl(profileId, worldId) {
  const test = new URLSearchParams(window.location.search).get("test") === "1" ? "&test=1" : "";
  return `${window.location.pathname}?play=1&profile=${encodeURIComponent(profileId)}&world=${encodeURIComponent(worldId)}${test}`;
}

function multiplayerPlayUrl(profileId, server) {
  const test = new URLSearchParams(window.location.search).get("test") === "1" ? "&test=1" : "";
  const address = server === "" ? "" : `&server=${encodeURIComponent(server)}`;
  return `${window.location.pathname}?play=1&mp=1&profile=${encodeURIComponent(profileId)}${address}${test}`;
}

export function runMenu() {
  document.body.dataset.mode = "menu";
  const menu = element("menu");
  const gameShell = document.getElementById("game-shell");
  menu.hidden = false;
  const syncMenuIsolation = () => {
    if (gameShell !== null) setShellInert(gameShell, menu);
  };
  const trapMenuFocus = (event) => {
    if (event.key !== "Tab") return;
    const screen = [...menu.querySelectorAll("[data-screen]")].find((node) => !node.hidden);
    if (screen === undefined) return;
    const target = nextFocusTarget(screen, document.activeElement, event.shiftKey);
    event.preventDefault();
    target?.focus({ preventScroll: true });
  };
  document.addEventListener("keydown", trapMenuFocus, true);
  syncMenuIsolation();
  // The game HUD belongs to playing sessions only.
  for (const id of [
    "hud",
    "hotbar",
    "held-item-view",
    "selected",
    "help",
    "crosshair",
    "mining-progress",
    "vitals",
    "inventory-toggle",
    "furnace-toggle",
    "chest-toggle",
    "inventory-panel",
    "furnace-panel",
    "chest-panel",
    "world-loading",
  ]) {
    const node = document.getElementById(id);
    if (node !== null) node.hidden = true;
  }
  const screens = [...menu.querySelectorAll("[data-screen]")];
  const showScreen = (id, focus = true) => {
    let activeScreen = null;
    for (const screen of screens) {
      const active = screen.id === id;
      screen.hidden = !active;
      screen.setAttribute("aria-hidden", String(!active));
      if (active) activeScreen = screen;
    }
    syncMenuIsolation();
    menu.setAttribute("aria-busy", String(id === "screen-loading"));
    if (focus && activeScreen !== null) {
      window.requestAnimationFrame(() => {
        const target = activeScreen.querySelector("input:not([hidden]), select:not([hidden]), button:not([hidden])");
        target?.focus({ preventScroll: true });
      });
    }
  };

  let doc = loadProfilesDoc(window.localStorage);
  let selectedProfileId = doc.activeProfileId;
  let selectedWorldId = null;
  let optionsReturn = "screen-title";
  let navigatingToWorld = false;

  const persistProfiles = () => saveProfilesDoc(window.localStorage, doc);

  function updateTitle() {
    const target = continueTarget(doc);
    const button = element("continue-world-button");
    const startButton = element("title-start-button");
    if (target === null) {
      button.hidden = true;
      startButton.textContent = "Create Your First World";
      startButton.classList.add("primary");
      element("title-world-name").textContent = "Start a new world";
      element("title-world-meta").textContent = "Create a player, choose a seed, and begin exploring.";
      return;
    }
    const profile = getProfile(doc, target.profileId);
    const world = getWorld(doc, target.profileId, target.worldId);
    if (profile === null || world === null) return;
    button.hidden = false;
    button.setAttribute("aria-label", `Enter ${world.name} as ${profile.name}`);
    startButton.textContent = "Choose Another World";
    startButton.classList.remove("primary");
    element("title-world-name").textContent = world.name;
    element("title-world-meta").textContent = `${profile.name} · ${worldModeLabel(world.mode)} · seed ${world.seed}`;
  }

  function beginNavigation(url, worldName) {
    if (navigatingToWorld) return;
    navigatingToWorld = true;
    element("menu-loading-world-name").textContent = worldName;
    const progress = element("menu-loading-progress");
    const setProgress = (label) => {
      progress.setAttribute("aria-valuetext", label);
    };
    setProgress("Opening world");
    showScreen("screen-loading", false);
    element("screen-loading").focus({ preventScroll: true });
    window.setTimeout(() => setProgress("Generating terrain"), 90);
    window.setTimeout(() => setProgress("Preparing play space"), 210);
    window.setTimeout(() => {
      window.location.href = url;
    }, 320);
  }

  function beginWorldNavigation(profileId, worldId, worldName) {
    beginNavigation(playUrl(profileId, worldId), worldName);
  }

  function renderProfiles() {
    const list = element("profile-list");
    list.innerHTML = "";
    if (doc.profiles.length === 0) {
      const empty = document.createElement("p");
      empty.className = "world-empty";
      empty.textContent = "No players yet. Create one to keep a personal save.";
      list.append(empty);
      selectedProfileId = null;
      return;
    }
    if (selectedProfileId === null || getProfile(doc, selectedProfileId) === null) {
      selectedProfileId = doc.profiles[0].id;
    }
    for (const profile of doc.profiles) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `world-entry${profile.id === selectedProfileId ? " selected" : ""}`;
      button.dataset.profile = profile.id;
      const name = document.createElement("strong");
      name.textContent = profile.name;
      const meta = document.createElement("span");
      meta.textContent = `${profile.worlds.length} worlds · last played ${formatDate(profile.lastPlayed)}`;
      button.append(name, meta);
      button.addEventListener("click", () => {
        selectedProfileId = profile.id;
        renderProfiles();
      });
      list.append(button);
    }
  }

  function renderWorlds() {
    const profile = getProfile(doc, selectedProfileId);
    element("worlds-title").textContent = profile === null ? "Select World" : `${profile.name}'s Worlds`;
    const list = element("world-list");
    list.innerHTML = "";
    const worlds = profile?.worlds ?? [];
    if (worlds.length === 0) {
      const empty = document.createElement("p");
      empty.className = "world-empty";
      empty.textContent = "No worlds yet. Create one to start playing.";
      list.append(empty);
      selectedWorldId = null;
      return;
    }
    if (selectedWorldId === null || getWorld(doc, selectedProfileId, selectedWorldId) === null) {
      selectedWorldId = worlds[0].id;
    }
    for (const world of worlds) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `world-entry${world.id === selectedWorldId ? " selected" : ""}`;
      button.dataset.world = world.id;
      const name = document.createElement("strong");
      name.textContent = world.name;
      const meta = document.createElement("span");
      meta.textContent = `${worldModeLabel(world.mode)} · seed ${world.seed} · last played ${formatDate(world.lastPlayed)}`;
      button.append(name, meta);
      button.addEventListener("click", () => {
        selectedWorldId = world.id;
        renderWorlds();
      });
      button.addEventListener("dblclick", () => playSelectedWorld());
      list.append(button);
    }
  }

  function showError(id, message) {
    const node = element(id);
    if (message === null) {
      node.hidden = true;
      node.textContent = "";
    } else {
      node.hidden = false;
      node.textContent = message;
    }
  }

  function playSelectedWorld() {
    const world = getWorld(doc, selectedProfileId, selectedWorldId);
    if (world === null) {
      showScreen("screen-worlds");
      return;
    }
    doc = touchWorld(doc, selectedProfileId, selectedWorldId);
    doc = touchProfile(doc, selectedProfileId);
    persistProfiles();
    updateTitle();
    beginWorldNavigation(selectedProfileId, selectedWorldId, world.name);
  }

  // The tier list is built from the same table the runtime walks, so adding a tier
  // cannot leave the menu offering a name the controller does not have, and a
  // rename cannot leave a stale option behind. Each entry carries what it costs,
  // because "Ultra" on its own tells a player nothing about the trade.
  const TIER_SUMMARY = Object.freeze({
    minimal: "Lowest cost: reduced render resolution, no god rays, small shadow map.",
    low: "Adds water detail and foliage wind at a reduced render resolution.",
    medium: "Adds god rays and a deeper bloom chain.",
    high: "Full detail at native resolution with a large shadow map.",
    ultra: "Highest cost: densest cloud march, widest shadow filter, full resolution.",
  });

  function buildGraphicsQualityOptions(select) {
    if (select === null || select.dataset.built === "true") return;
    const labels = {
      auto: "Auto (match frame rate)",
      minimal: "Minimal",
      low: "Low",
      medium: "Medium",
      high: "High",
      ultra: "Ultra",
    };
    for (const choice of GRAPHICS_QUALITY_CHOICES) {
      // `document`, not `doc`: in this module `doc` is the saved profiles data,
      // and reaching for it here throws inside the click handler, which then
      // never reaches the screen switch at all.
      const option = document.createElement("option");
      option.value = choice;
      option.textContent = labels[choice] ?? choice;
      select.append(option);
    }
    select.dataset.built = "true";
  }

  // The frame rate limits are built from the same table the pacer enforces, so the
  // menu cannot offer a cap the runtime would silently ignore. The labels spell
  // out what uncapped means, because "0" in a frame rate field reads as a bug
  // rather than as the absence of a limit.
  const FPS_LIMIT_LABELS = Object.freeze({
    0: "Uncapped (display refresh)",
    30: "30 FPS",
    60: "60 FPS",
    120: "120 FPS",
    144: "144 FPS",
    240: "240 FPS",
  });

  function buildFpsLimitOptions(select) {
    if (select === null || select.dataset.built === "true") return;
    for (const choice of FPS_LIMIT_CHOICES) {
      const option = document.createElement("option");
      option.value = String(choice);
      option.textContent = FPS_LIMIT_LABELS[choice] ?? `${choice} FPS`;
      select.append(option);
    }
    select.dataset.built = "true";
  }

  // The graphics section's own wording, read once from the markup before anything
  // can overwrite it, so the panel has one place that explains it and the WebGPU
  // case does not need a second copy of the default. `runMenu` owns the document,
  // so this is its own element lookup and not the `doc` that holds saved profiles.
  const graphicsEffectHintDefault = document.getElementById("graphics-effect-hint")?.textContent ?? "";

  // The per-effect controls are built from the same table the renderer resolves
  // its amounts through, so the panel cannot offer an effect the pipeline does
  // not have, and one it does have cannot go missing between the table and the
  // menu. Built in code rather than written into the markup because there are
  // twelve of them and every one has to stay in step with that table.
  function buildGraphicsEffectFields(container) {
    if (container === null || container.dataset.built === "true") return;
    for (const effect of GRAPHICS_EFFECTS) {
      const field = document.createElement("label");
      field.className = "field";
      const caption = document.createElement("span");
      caption.append(`${effect.label}: `);
      const readout = document.createElement("output");
      readout.id = `effect-${effect.key}-value`;
      readout.textContent = String(effect.amount);
      caption.append(readout, "%");
      const input = document.createElement("input");
      input.type = "range";
      input.id = `input-effect-${effect.key}`;
      input.min = String(effect.min);
      input.max = String(effect.max);
      input.step = String(effect.step);
      input.value = String(effect.amount);
      const hint = document.createElement("span");
      hint.className = "field-hint";
      hint.textContent = effect.hint;
      field.append(caption, input, hint);
      container.append(field);
    }
    container.dataset.built = "true";
  }

  // A WebGPU option the player can select but cannot run is worse than no option:
  // it looks like the browser is supported and the failure only shows up as a hang
  // at boot. So the menu probes the same way the runtime does and disables the
  // choice when it is not actually there, with the reason visible.
  const backendProbe = { webgpu: { supported: false, adapterName: null, reason: "not probed" } };

  async function probeBackends() {
    backendProbe.webgpu = await probeWebGpu(globalThis.navigator, null);
    applyRendererAvailability();
    return backendProbe.webgpu;
  }

  function applyRendererAvailability() {
    const select = element("input-renderer");
    if (select === null) return;
    const option = select.querySelector('option[value="webgpu"]');
    if (option === null) return;
    const probe = backendProbe.webgpu;
    option.disabled = !probe.supported;
    option.textContent = probe.supported
      ? `WebGPU${probe.adapterName ? ` (${probe.adapterName})` : ""}`
      : `WebGPU (unavailable: ${probe.reason})`;
    const hint = select.parentElement?.querySelector(".field-hint");
    if (hint !== null && hint !== undefined && !probe.supported) {
      hint.textContent = `This browser reports no usable WebGPU adapter (${probe.reason}), so the option is disabled. Auto already selects the verified WebGL path.`;
    }
    releaseUnusablePin();
  }

  /**
   * A stored WebGPU pin that cannot run would bounce the player between the world
   * and this menu on every attempt, because the pin survives the recovery unless
   * something here clears it. Two independent reasons release it, and they are
   * not the same question: the probe answers "is there a usable adapter", while a
   * failure notice answers "did it actually run here", which is the only evidence
   * that matters for this machine.
   */
  function releaseUnusablePin() {
    const current = loadOptions(window.localStorage);
    if (current.renderer !== "webgpu") return;
    const probeUnavailable = backendProbe.webgpu.reason !== "not probed" && !backendProbe.webgpu.supported;
    if (!probeUnavailable && !failedBackendNotice) return;
    saveOptions(window.localStorage, { ...current, renderer: "auto" });
    const select = element("input-renderer");
    if (select !== null && select.value === "webgpu") select.value = "auto";
  }



  function applyStoredVolumes() {
    getAudioMixer().setVolumes(audioVolumesFromOptions(loadOptions(window.localStorage)));
  }

  function renderOptions() {
    const fresh = loadOptions(window.localStorage);
    element("input-fov").value = String(fresh.fov);
    element("fov-value").textContent = String(fresh.fov);
    element("input-sensitivity").value = String(fresh.sensitivity);
    element("sensitivity-value").textContent = Number(fresh.sensitivity).toFixed(1);
    const renderDistance = element("input-render-distance");
    renderDistance.min = String(MIN_RENDER_DISTANCE);
    renderDistance.max = String(MAX_RENDER_DISTANCE);
    renderDistance.value = String(fresh.renderDistance ?? DEFAULT_RENDER_DISTANCE);
    element("render-distance-value").textContent = String(fresh.renderDistance ?? DEFAULT_RENDER_DISTANCE);
    element("input-lod-distance").value = String(normalizeLodDistance(fresh.lodDistance ?? DEFAULT_LOD_DISTANCE));
    const fpsLimit = element("input-fps-limit");
    buildFpsLimitOptions(fpsLimit);
    fpsLimit.value = String(normalizeFpsLimit(fresh.fpsLimit ?? DEFAULT_FPS_LIMIT));
    element("input-renderer").value = fresh.renderer;
    const quality = element("input-graphics-quality");
    buildGraphicsQualityOptions(quality);
    quality.value = fresh.graphicsQuality ?? DEFAULT_GRAPHICS_QUALITY;
    // The hint follows the selection, so the panel explains the tier in hand
    // rather than describing the ladder in the abstract.
    const summary = quality.parentElement?.querySelector(".field-hint");
    if (summary !== null && summary !== undefined) {
      const chosen = VISUAL_QUALITY_TIERS.find((tier) => tier.name === quality.value);
      summary.textContent = chosen === undefined
        ? "Auto scales shadows, volumetric clouds, water detail, cascade resolution and internal render resolution to hold the frame rate. Pinning a tier turns that off."
        : TIER_SUMMARY[chosen.name] ?? "";
    }
    buildGraphicsEffectFields(element("graphics-effect-fields"));
    // Normalised on the way in as well as on the way out, so the panel can only
    // ever show an amount the runtime is willing to apply.
    const effects = normalizeGraphicsEffects(fresh.graphics);
    // The optional WebGPU lane draws straight to the canvas: it has no bloom
    // chain, no god rays and no shadow cascade, so there is nothing for these
    // amounts to scale. Saying so is the whole point - a control that looks live
    // and quietly does nothing is worse than one that explains itself. `auto`
    // resolves to the verified WebGL path, so this only fires on an explicit pin.
    const postless = fresh.renderer === "webgpu";
    for (const effect of GRAPHICS_EFFECTS) {
      const input = element(`input-effect-${effect.key}`);
      input.value = String(effects[effect.key]);
      input.disabled = postless;
      element(`effect-${effect.key}-value`).textContent = String(effects[effect.key]);
    }
    const effectHint = element("graphics-effect-hint");
    // The default wording lives in the markup; only the WebGPU case is written
    // from here, and switching back to WebGL has to put the original back rather
    // than leave the excuse on screen.
    effectHint.textContent = postless
      ? "The WebGPU renderer draws straight to the canvas, with no bloom, sunbeams or sun shadows to scale, so these are unavailable on it. Choose WebGL under Graphics API to use them."
      : graphicsEffectHintDefault;
    for (const [key, option] of [["master", "volumeMaster"], ["music", "volumeMusic"], ["effects", "volumeEffects"]]) {
      const value = fresh[option];
      element(`input-volume-${key}`).value = String(Math.round(value * 100));
      element(`volume-${key}-value`).textContent = String(Math.round(value * 100));
    }
    element("input-show-coords").value = fresh.showCoords ? "on" : "off";
    for (const key of ["sneak", "sprint", "inventory", "drop", "attack"]) {
      const input = document.getElementById(`input-control-${key}`);
      if (input !== null) input.value = fresh.controls[key];
    }
    applyStoredVolumes();
  }

  menu.addEventListener("click", (event) => {
    const button = event.target.closest("[data-action]");
    if (button === null) return;
    const action = button.dataset.action;
    if (action === "continue-world") {
      const target = continueTarget(doc);
      if (target === null) return;
      const world = getWorld(doc, target.profileId, target.worldId);
      if (world === null) return;
      selectedProfileId = target.profileId;
      selectedWorldId = target.worldId;
      doc = touchWorld(doc, selectedProfileId, selectedWorldId);
      doc = touchProfile(doc, selectedProfileId);
      persistProfiles();
      updateTitle();
      beginWorldNavigation(selectedProfileId, selectedWorldId, world.name);
    } else if (action === "goto-profiles") {
      renderProfiles();
      showScreen("screen-profiles");
    } else if (action === "goto-options") {
      optionsReturn = "screen-title";
      renderOptions();
      showScreen("screen-options");
    } else if (action === "goto-help") {
      showScreen("screen-help");
    } else if (action === "back-title" || action === "back-title-help") {
      showScreen("screen-title");
    } else if (action === "back-profiles") {
      renderProfiles();
      showScreen("screen-profiles");
    } else if (action === "back-worlds") {
      renderWorlds();
      showScreen("screen-worlds");
    } else if (action === "play-profile") {
      if (selectedProfileId === null) return;
      doc = touchProfile(doc, selectedProfileId);
      persistProfiles();
      selectedWorldId = null;
      renderWorlds();
      showScreen("screen-worlds");
    } else if (action === "goto-create-profile") {
      element("input-profile-name").value = "";
      showError("profile-error", null);
      showScreen("screen-create-profile");
    } else if (action === "confirm-profile") {
      const created = createProfile(doc, element("input-profile-name").value);
      if (!created.ok) {
        showError("profile-error", created.error);
        return;
      }
      doc = created.doc;
      persistProfiles();
      selectedProfileId = created.profile.id;
      selectedWorldId = null;
      renderWorlds();
      showScreen("screen-worlds");
    } else if (action === "delete-profile") {
      if (selectedProfileId === null) return;
      const profile = getProfile(doc, selectedProfileId);
      if (profile !== null) {
        for (const world of profile.worlds) {
          try {
            clearTransactional(window.localStorage, saveKeyFor(profile.id, world.seed));
          } catch {
            // Deleting saves is best-effort.
          }
        }
      }
      doc = deleteProfile(doc, selectedProfileId);
      persistProfiles();
      selectedProfileId = doc.activeProfileId;
      updateTitle();
      renderProfiles();
    } else if (action === "goto-create-world") {
      if (selectedProfileId === null) return;
      element("input-world-name").value = "";
      element("input-seed").value = "";
      element("input-world-mode").value = "survival";
      showError("create-error", null);
      showScreen("screen-create-world");
    } else if (action === "goto-join-server") {
      if (selectedProfileId === null) return;
      let last = "";
      try {
        last = window.localStorage.getItem(LAST_SERVER_KEY) ?? "";
      } catch {
        last = "";
      }
      element("input-server-address").value = last;
      showError("join-error", null);
      showScreen("screen-join-server");
    } else if (action === "confirm-join-server") {
      if (selectedProfileId === null) return;
      const server = element("input-server-address").value.trim();
      let url;
      try {
        url = multiplayerUrl(server, window.location);
      } catch (error) {
        showError("join-error", error instanceof Error ? error.message : String(error));
        return;
      }
      try {
        window.localStorage.setItem(LAST_SERVER_KEY, server);
      } catch {
        // Remembering the address is a convenience.
      }
      doc = touchProfile(doc, selectedProfileId);
      persistProfiles();
      beginNavigation(multiplayerPlayUrl(selectedProfileId, server), `Multiplayer · ${new URL(url).host}`);
    } else if (action === "random-seed") {
      element("input-seed").value = randomSeedText();
    } else if (action === "confirm-world") {
      if (selectedProfileId === null) return;
      const config = createWorldConfig({
        name: element("input-world-name").value,
        seedText: element("input-seed").value,
        mode: element("input-world-mode").value,
      });
      const errors = validateWorldConfig(config);
      if (errors.length > 0) {
        showError("create-error", errors[0]);
        return;
      }
      const created = createWorld(doc, selectedProfileId, config);
      if (!created.ok) {
        showError("create-error", created.error);
        return;
      }
      doc = touchProfile(touchWorld(created.doc, selectedProfileId, created.world.id), selectedProfileId);
      persistProfiles();
      selectedWorldId = created.world.id;
      updateTitle();
      beginWorldNavigation(selectedProfileId, selectedWorldId, created.world.name);
    } else if (action === "play-world") {
      playSelectedWorld();
    } else if (action === "delete-world") {
      if (selectedProfileId === null || selectedWorldId === null) return;
      const world = getWorld(doc, selectedProfileId, selectedWorldId);
      if (world !== null) {
        try {
          clearTransactional(window.localStorage, saveKeyFor(selectedProfileId, world.seed));
        } catch {
          // Deleting saves is best-effort.
        }
      }
      doc = deleteWorld(doc, selectedProfileId, selectedWorldId);
      persistProfiles();
      selectedWorldId = null;
      updateTitle();
      renderWorlds();
    } else if (action === "options-reset") {
      // Reset writes the whole default document rather than clearing the key, so
      // a stored option this build no longer knows about cannot survive the reset.
      saveOptions(window.localStorage, createDefaultOptions());
      renderOptions();
    } else if (action === "options-done") {
      showScreen(optionsReturn);
    }
  });

  menu.addEventListener("input", (event) => {
    if (event.target.id === "input-fov") {
      const value = Number(event.target.value);
      element("fov-value").textContent = String(value);
      saveOptions(window.localStorage, { ...loadOptions(window.localStorage), fov: value });
    } else if (event.target.id === "input-sensitivity") {
      const value = Number(event.target.value);
      element("sensitivity-value").textContent = value.toFixed(1);
      saveOptions(window.localStorage, { ...loadOptions(window.localStorage), sensitivity: value });
    } else if (event.target.id === "input-render-distance") {
      const value = Number(event.target.value);
      element("render-distance-value").textContent = String(value);
      saveOptions(window.localStorage, { ...loadOptions(window.localStorage), renderDistance: value });
    } else if (event.target.id === "input-lod-distance") {
      const value = normalizeLodDistance(event.target.value);
      saveOptions(window.localStorage, { ...loadOptions(window.localStorage), lodDistance: value });
    } else if (event.target.id === "input-fps-limit") {
      // Normalised on the way in as well as on the way out, so a value the panel
      // cannot offer is never written to the stored document in the first place.
      const value = normalizeFpsLimit(event.target.value);
      event.target.value = String(value);
      saveOptions(window.localStorage, { ...loadOptions(window.localStorage), fpsLimit: value });
    } else if (event.target.id === "input-renderer") {
      saveOptions(window.localStorage, { ...loadOptions(window.localStorage), renderer: event.target.value });
    } else if (event.target.id === "input-graphics-quality") {
      saveOptions(window.localStorage, { ...loadOptions(window.localStorage), graphicsQuality: event.target.value });
      renderOptions();
    } else if (event.target.id?.startsWith("input-effect-")) {
      const key = event.target.id.replace("input-effect-", "");
      // A control this build does not know is a stale document or a stale panel,
      // and writing it through would put an effect the runtime cannot apply into
      // the stored options.
      const effect = graphicsEffectByKey(key);
      if (effect === null) return;
      const parsed = Number(event.target.value);
      if (!Number.isFinite(parsed)) return;
      const value = Math.min(effect.max, Math.max(effect.min, Math.round(parsed)));
      event.target.value = String(value);
      element(`effect-${key}-value`).textContent = String(value);
      const stored = loadOptions(window.localStorage);
      saveOptions(window.localStorage, {
        ...stored,
        graphics: { ...stored.graphics, [key]: value },
      });
    } else if (event.target.id === "input-show-coords") {
      saveOptions(window.localStorage, { ...loadOptions(window.localStorage), showCoords: event.target.value === "on" });
    } else if (event.target.id.startsWith("input-volume-")) {
      const bus = event.target.id.replace("input-volume-", "");
      const option = bus === "master" ? "volumeMaster" : bus === "music" ? "volumeMusic" : "volumeEffects";
      if (option === "volumeEffects" && bus !== "effects") return;
      const value = Math.max(MIN_VOLUME, Math.min(MAX_VOLUME, Number(event.target.value) / 100));
      element(`volume-${bus}-value`).textContent = String(Math.round(value * 100));
      const fresh = { ...loadOptions(window.localStorage), [option]: value };
      saveOptions(window.localStorage, fresh);
      // Applied immediately and previewed, so the level can be judged from the
      // menu rather than only after entering the world.
      const mixer = getAudioMixer();
      mixer.setVolumes(audioVolumesFromOptions(fresh));
      mixer.play(bus === "music" ? "ambient" : "click");
    } else if (event.target.id?.startsWith("input-control-")) {
      const key = event.target.id.replace("input-control-", "");
      saveOptions(window.localStorage, {
        ...loadOptions(window.localStorage),
        controls: { ...loadOptions(window.localStorage).controls, [key]: event.target.value },
      });
    }
  });

  const active = getActiveProfile(doc);
  if (active !== null) selectedProfileId = active.id;
  element("input-seed").value = "";
  updateTitle();
  showScreen("screen-title");

  // Surface a backend that failed during the last attempt, before anything else
  // draws attention, and start the capability probe. The probe resolves on its
  // own; the menu is usable while it is in flight, because the default is already
  // the verified path.
  showBackendNotice();
  probeBackends();
}

// Whether the last session reported a backend failure. The pin check below needs
// it and the notice reader produces it, so it lives beside the reader rather than
// inside the menu closure - a flag the reader cannot see is a flag that never gets
// set, and the pin is then never released.
let failedBackendNotice = false;

/** A one-shot banner explaining why the previous session ended up back here. */
function showBackendNotice() {
  const banner = document.getElementById("backend-notice");
  const notice = takeBackendNotice();
  failedBackendNotice = notice !== null && notice.renderer === "webgpu";
  if (banner === null) return;
  if (notice === null) {
    banner.hidden = true;
    return;
  }
  banner.textContent = describeBackendNotice(notice);
  banner.hidden = false;
}
