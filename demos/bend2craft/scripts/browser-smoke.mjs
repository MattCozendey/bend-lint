import assert from "node:assert/strict";
import { chromium } from "playwright";

const baseUrl = process.argv[2] ?? "http://127.0.0.1:3000";

// The smoke waits for real pointer lock, which the default headless builds
// (chrome-headless-shell) refuse with a pointerlockerror. Prefer the full
// Chromium build and fall back to the default headless browser only when the
// full one is not installed.
async function launchBrowser() {
  try {
    return await chromium.launch({ headless: true, channel: "chromium" });
  } catch {
    return chromium.launch({ headless: true });
  }
}

const browser = await launchBrowser();
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const consoleErrors = [];
const pageErrors = [];
page.on("console", (message) => {
  if (message.type() === "error") consoleErrors.push(message.text());
});
page.on("pageerror", (error) => pageErrors.push(String(error)));

// The one definition of "the reloaded world is ready to assert against". Chunks
// resident and mesh rebuilds drained are separate conditions, and a reload that
// only waited for the first would read state from a half-built world.
async function reloadAndSettle() {
  await page.reload({ waitUntil: "domcontentloaded", timeout: 30000 });
  await page.waitForFunction(
    () => window.__bend2craft?.world?.activeChunks > 0 && window.__bend2craft?.world?.pendingChunks === 0,
    null,
    { timeout: 30000 },
  );
  await page.waitForFunction(
    () => window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false,
    null,
    { timeout: 30000 },
  );
}

try {
  await page.goto(`${baseUrl}/?test=1`, { waitUntil: "load", timeout: 30000 });
  await page.waitForFunction(
    () => document.getElementById("world-preview")?.dataset.previewState === "ready",
    null,
    { timeout: 10000 },
  );
  await page.waitForFunction(
    () => {
      const screen = [...document.querySelectorAll("[data-screen]")].find((node) => !node.hidden);
      return screen?.contains(document.activeElement) ?? false;
    },
    null,
    { timeout: 10000 },
  );
  const titleShell = await page.evaluate(() => {
    const preview = document.getElementById("world-preview");
    const screen = [...document.querySelectorAll("[data-screen]")].find((node) => !node.hidden);
    const rect = preview?.getBoundingClientRect();
    return {
      previewState: preview?.dataset.previewState,
      previewImage: getComputedStyle(preview).backgroundImage,
      previewWidth: rect?.width ?? 0,
      previewHeight: rect?.height ?? 0,
      menuRole: document.getElementById("menu")?.getAttribute("role"),
      focusInside: screen?.contains(document.activeElement) ?? false,
      startPrimary: document.getElementById("title-start-button")?.classList.contains("primary") ?? false,
    };
  });
  assert.equal(titleShell.previewState, "ready");
  assert.match(titleShell.previewImage, /^url\(/);
  assert.ok(titleShell.previewWidth >= 1280 && titleShell.previewHeight >= 720);
  assert.equal(titleShell.menuRole, "dialog");
  assert.equal(titleShell.focusInside, true);
  assert.equal(titleShell.startPrimary, true);
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => {
    const screen = [...document.querySelectorAll("[data-screen]")].find((node) => !node.hidden);
    return screen?.contains(document.activeElement) ?? false;
  }), true);
  await page.evaluate(() => {
    localStorage.removeItem("bend2craft-save-p-smoke-1337");
    localStorage.setItem("bend2craft-profiles", JSON.stringify({
      version: 1,
      activeProfileId: "p-smoke",
      profiles: [{
        id: "p-smoke",
        name: "Voyager",
        createdAt: 1,
        lastPlayed: 1,
        worlds: [{
          id: "w-smoke",
          name: "Bend Valley",
          seedText: "1337",
          seed: "1337",
          mode: "survival",
          createdAt: 1,
          lastPlayed: 1,
        }],
      }],
    }));
  });
  await page.reload({ waitUntil: "load", timeout: 30000 });
  await page.waitForFunction(
    () => document.getElementById("world-preview")?.dataset.previewState === "ready",
    null,
    { timeout: 10000 },
  );
  await page.waitForFunction(
    () => [...document.querySelectorAll("[data-screen]")].some((node) => !node.hidden && node.contains(document.activeElement)),
    null,
    { timeout: 10000 },
  );
  const returningShell = await page.evaluate(() => ({
    continueVisible: document.getElementById("continue-world-button")?.hidden === false,
    worldName: document.getElementById("title-world-name")?.textContent,
    worldMeta: document.getElementById("title-world-meta")?.textContent,
  }));
  assert.deepEqual(returningShell, {
    continueVisible: true,
    worldName: "Bend Valley",
    worldMeta: "Voyager · Survival · seed 1337",
  });
  await page.locator("#continue-world-button").click();
  await page.waitForFunction(
    () => new URLSearchParams(window.location.search).get("world") === "w-smoke",
    null,
    { timeout: 10000 },
  );
  const continuedWorld = await page.evaluate(() => ({
    play: new URLSearchParams(window.location.search).get("play"),
    world: new URLSearchParams(window.location.search).get("world"),
  }));
  assert.deepEqual(continuedWorld, { play: "1", world: "w-smoke" });
  await page.goto(`${baseUrl}/?test=1`, { waitUntil: "load", timeout: 30000 });
  await page.waitForFunction(
    () => document.getElementById("world-preview")?.dataset.previewState === "ready",
    null,
    { timeout: 10000 },
  );
  await page.evaluate(() => localStorage.removeItem("bend2craft-profiles"));
  await page.reload({ waitUntil: "load", timeout: 30000 });
  await page.waitForFunction(
    () => document.getElementById("world-preview")?.dataset.previewState === "ready",
    null,
    { timeout: 10000 },
  );
  await page.locator('[data-action="goto-options"]').click();
  const renderDistanceOptions = await page.evaluate(() => {
    const input = document.getElementById("input-render-distance");
    const renderer = document.getElementById("input-renderer");
    return {
      min: Number(input?.min),
      max: Number(input?.max),
      value: Number(input?.value),
      output: document.getElementById("render-distance-value")?.textContent,
      rendererValue: renderer?.value,
      rendererOptions: [...(renderer?.options ?? [])].map((option) => option.value),
    };
  });
  assert.deepEqual(renderDistanceOptions, {
    min: 2,
    max: 8,
    value: 4,
    output: "4",
    rendererValue: "webgl",
    rendererOptions: ["auto", "webgpu", "webgl"],
  });
  await page.locator("#input-render-distance").evaluate((input) => {
    input.value = "5";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const savedRenderDistance = await page.evaluate(() => JSON.parse(
    window.localStorage.getItem("bend2craft-options"),
  ).renderDistance);
  assert.equal(savedRenderDistance, 5);
  await page.locator("#input-renderer").selectOption("webgl");
  const savedRenderer = await page.evaluate(() => JSON.parse(
    window.localStorage.getItem("bend2craft-options"),
  ).renderer);
  assert.equal(savedRenderer, "webgl");
  // The frame rate cap is edited the same way as every other video option, and it
  // has to reach the stored document or the control is decorative.
  await page.locator("#input-fps-limit").selectOption("30");
  const savedFpsLimit = await page.evaluate(() => JSON.parse(
    window.localStorage.getItem("bend2craft-options"),
  ).fpsLimit);
  assert.equal(savedFpsLimit, 30, "the frame rate cap must be stored when the menu writes it");
  await page.evaluate(() => window.localStorage.setItem(
    "bend2craft-options",
    JSON.stringify({ fov: 75, sensitivity: 1, showCoords: true, renderDistance: 2, renderer: "auto", fpsLimit: 30 }),
  ));

  // Functional smoke uses WebGL so headless SwiftShader cannot report a
  // successful WebGPU frame while presenting a blank compositor surface.
  // World readiness is asserted explicitly below because streaming workers
  // keep the page active after the initial document load.
  await page.goto(`${baseUrl}/?test=1&play=1&seed=1337&renderer=webgl`, { waitUntil: "domcontentloaded", timeout: 30000 });
  await page.waitForFunction(
    () => window.__bend2craft?.world?.activeChunks > 0 && window.__bend2craft?.world?.pendingChunks === 0,
    null,
    { timeout: 30000 },
  );
  await page.waitForFunction(
    () => window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false,
    null,
    { timeout: 30000 },
  );
  await page.waitForFunction(
    () => document.getElementById("world-loading")?.hidden === true,
    null,
    { timeout: 5000 },
  );

  // The stored cap has to reach the frame loop, and the loop has to keep drawing
  // while it is applied. The achieved frame rate is deliberately not asserted
  // here: this smoke runs on headless SwiftShader, where the renderer is orders of
  // magnitude slower than any cap, so a rate assertion would only measure the
  // software rasteriser. The pacing arithmetic and the cap-to-rate relationship
  // are covered by tests/frame-pacer.test.mjs and benchmarks/fps-cap.mjs.
  const pacing = await page.evaluate(() => {
    const presentation = window.__bend2craft.presentation;
    return {
      appliedLimit: presentation.fpsLimit,
      budgetMs: presentation.frameBudgetMs,
      frameCount: window.__bend2craft.getFrameDiagnostics().frameCount,
    };
  });
  assert.equal(pacing.appliedLimit, 30, "the stored frame rate cap must reach the running loop");
  assert.ok(
    Math.abs(pacing.budgetMs - 1000 / 30) < 0.01,
    `a 30 FPS cap must become the frame budget, got ${pacing.budgetMs}ms`,
  );
  // A cap that stopped the loop would freeze the world silently, so the drawn
  // frame count has to be moving by the time the world is up.
  await page.waitForFunction(
    (previous) => window.__bend2craft.getFrameDiagnostics().frameCount > previous,
    pacing.frameCount,
    { timeout: 15000 },
  );
  // The HUD fades in over a CSS transition. Reading the computed opacity while
  // that transition is still running reads a value between 0 and 1, so wait for
  // it to settle before asserting the opacity is exactly 1.
  await page.waitForFunction(
    () => {
      const read = (id) => Number(getComputedStyle(document.getElementById(id)).opacity);
      return Math.abs(read("hud") - 1) < 0.001 && Math.abs(read("hotbar") - 1) < 0.001;
    },
    null,
    { timeout: 10000 },
  );
  const state = await page.evaluate(() => ({
    errorHidden: document.getElementById("error")?.hidden ?? false,
    activeChunks: window.__bend2craft?.world?.activeChunks ?? 0,
    pendingChunks: window.__bend2craft?.world?.pendingChunks ?? -1,
    miningProgressHidden: document.getElementById("mining-progress")?.hidden ?? false,
    hudOpacity: getComputedStyle(document.getElementById("hud")).opacity,
    hotbarOpacity: getComputedStyle(document.getElementById("hotbar")).opacity,
    vitalsHidden: document.getElementById("vitals")?.hidden ?? true,
    crosshairOpacity: getComputedStyle(document.getElementById("crosshair")).opacity,
    xpHidden: document.getElementById("xp-hud")?.hidden ?? true,
    loadingHidden: document.getElementById("world-loading")?.hidden ?? false,
    renderer: window.__bend2craft?.getFrameDiagnostics?.().renderer ?? null,
    lightProbe: typeof window.__bend2craft?.getLight === "function",
    frame: window.__bend2craft?.getFrameDiagnostics?.() ?? null,
  }));
  assert.equal(state.errorHidden, true);
  assert.ok(state.activeChunks > 0);
  assert.equal(state.pendingChunks, 0);
  assert.equal(state.miningProgressHidden, true);
  assert.equal(state.hudOpacity, "1");
  assert.equal(state.hotbarOpacity, "1");
  assert.equal(state.vitalsHidden, false);
  assert.equal(state.crosshairOpacity, "1");
  assert.equal(state.xpHidden, false);
  assert.equal(state.loadingHidden, true);
  assert.equal(state.renderer, "webgl");
  assert.equal(state.lightProbe, true);
  assert.equal(state.frame?.playerSpawnReady, true);
  assert.equal(state.frame?.spawnMeshReady, true);
  assert.ok(state.frame?.meshRebuilds > 0);
  assert.ok(state.frame?.workerHydrates > 0);
  assert.ok(state.frame?.meshWorkerResponses > 0);

  // Every mob kind has to put its own body on the GPU. The symptom this guards is
  // the one a player reported: a hostile brute that chased them and burned in
  // daylight while being drawn as a pig, because the kind fell through to the pig
  // model. Measuring the uploaded dynamic mesh catches the miss at the boundary
  // where it happens, which a unit test on the model table alone cannot.
  const modelProbe = await page.evaluate(() => {
    const api = window.__bend2craft;
    api.despawnMobsForTest(0);
    const drawn = {};
    for (const kind of [1, 2, 3, 4, 5, 6]) {
      api.despawnMobsForTest(0);
      const mob = api.spawnMobForTest(kind);
      drawn[kind] = {
        spawned: mob !== null,
        kind: mob?.kind ?? null,
        vertices: api.glBufferSizes().dynamicVertexCount,
      };
    }
    api.despawnMobsForTest(0);
    return drawn;
  });
  for (const [kind, entry] of Object.entries(modelProbe)) {
    assert.ok(entry.spawned, `a mob of kind ${kind} must spawn for the model smoke`);
    assert.equal(entry.kind, Number(kind), `kind ${kind} must spawn as itself`);
    assert.ok(entry.vertices > 0, `kind ${kind} must draw something`);
  }
  assert.notEqual(modelProbe[4].vertices, modelProbe[1].vertices,
    "the hostile brute must not be drawn as a pig");
  assert.notEqual(modelProbe[4].vertices, modelProbe[2].vertices,
    "the brute needs its own body rather than the zombie's");
  const firstPersonOverlayProbe = await page.evaluate(async () => {
    const canvas = document.getElementById("first-person-hand-canvas");
    const player = window.__bend2craft.getPlayer();
    window.__bend2craft.setViewForTest(player.x, player.y, player.z, 0, 0);
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
    const forward = canvas.toDataURL();
    window.__bend2craft.setViewForTest(player.x, player.y, player.z, Math.PI / 2, 0);
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
    return {
      available: canvas instanceof HTMLCanvasElement,
      stable: forward === canvas.toDataURL(),
    };
  });
  assert.equal(firstPersonOverlayProbe.available, true);
  assert.equal(firstPersonOverlayProbe.stable, true, "held-item overlay must not rotate with the camera");
  await page.evaluate(() => {
    window.__bend2craft.teleportForTest(40.5, 24.5, 8);
    window.__bend2craft.resumeForTest();
  });

  const initialTarget = await page.evaluate(() => {
    const player = window.__bend2craft.getPlayer();
    for (let y = 8; y < 16; y += 1) {
      for (let x = Math.floor(player.x) - 6; x <= Math.floor(player.x) + 6; x += 1) {
        for (let z = Math.floor(player.z) - 6; z <= Math.floor(player.z) + 6; z += 1) {
          const block = window.__bend2craft.getBlock(x, y, z);
          if (block === 0 || block === 7 || block === 21 || block === 24
            || ![2, 3, 4, 5, 6, 13, 14, 15, 16, 17, 18, 19, 20].includes(block)) continue;
          const dx = x + 0.5 - player.x;
          const dy = y + 0.5 - (player.y + 1.62);
          const dz = z + 0.5 - player.z;
          const horizontal = Math.hypot(dx, dz);
          const distance = Math.hypot(horizontal, dy);
          if (horizontal < 0.5 || distance > 7.5) continue;
          const yaw = Math.atan2(dx, -dz);
          const pitch = Math.atan2(dy, horizontal);
          const target = window.__bend2craft.setViewForTest(player.x, player.y, player.z, yaw, pitch);
          if (target?.hit) return { block, target, x, y, z, yaw, pitch };
        }
      }
    }
    return null;
  });
  assert.ok(initialTarget?.target?.hit, "the first-person raycast must find a target block");

  let textureProbe = null;
  let animatedSurfaceProbe = null;
  let atlasProbe = null;
  if (state.frame?.renderer === "webgl") {
  textureProbe = await page.evaluate(async () => {
    const player = window.__bend2craft.getPlayer();
    window.__bend2craft.teleportForTest(player.x, player.z, player.y, player.yaw, player.pitch);
    const region = [500, 500, 64, 64];
    const first = window.__bend2craft.readFramePixels(...region);
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
    const second = window.__bend2craft.readFramePixels(...region);
    let changedPixels = 0;
    for (let index = 0; index < first.length; index += 4) {
      if (first[index] !== second[index]
        || first[index + 1] !== second[index + 1]
        || first[index + 2] !== second[index + 2]
        || first[index + 3] !== second[index + 3]) changedPixels += 1;
    }
    window.__bend2craft.resumeForTest();
    return { region, pixels: first.length / 4, changedPixels };
  });
  assert.ok(textureProbe.pixels > 0);
  assert.ok(textureProbe.changedPixels <= 64, `static terrain pixels should not flicker between frames (changed=${textureProbe.changedPixels})`);

  animatedSurfaceProbe = await page.evaluate(async () => {
    const region = [100, 210, 64, 64];
    const first = window.__bend2craft.readFramePixels(...region);
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
    const second = window.__bend2craft.readFramePixels(...region);
    let changedPixels = 0;
    for (let index = 0; index < first.length; index += 4) {
      if (first[index] !== second[index]
        || first[index + 1] !== second[index + 1]
        || first[index + 2] !== second[index + 2]
        || first[index + 3] !== second[index + 3]) changedPixels += 1;
    }
    return { region, pixels: first.length / 4, changedPixels };
  });
  assert.ok(animatedSurfaceProbe.changedPixels > 0, "animated surface should update over time");
  assert.ok(animatedSurfaceProbe.changedPixels < animatedSurfaceProbe.pixels, "animated surface must not flash the whole frame");

  atlasProbe = await page.evaluate(() => {
    const probes = Array.from({ length: 50 }, (_, tile) => window.__bend2craft.getAtlasTexelProbe(tile));
    return {
      tiles: probes.length,
      totalMismatches: probes.reduce((sum, probe) => sum + probe.mismatches, 0),
      maxMismatches: Math.max(...probes.map((probe) => probe.mismatches)),
      flippedMismatches: probes.reduce((sum, probe) => sum + probe.flippedMismatches, 0),
      mipmaps: window.__bend2craft.getFrameDiagnostics().atlasMipmaps,
    };
  });
  assert.equal(atlasProbe.tiles, 50);
  assert.equal(atlasProbe.totalMismatches, 0, "WebGL atlas texels must match all source tiles");
  // The Foreign Tile Contamination gate ran against the real mip chain. A
  // rejected verdict must keep mipmaps off rather than ship a blended atlas.
  assert.ok(atlasProbe.mipmaps !== undefined, "the atlas mipmap verdict must be reported");
  if (atlasProbe.mipmaps.safe) {
    assert.equal(atlasProbe.mipmaps.contaminated, 0, "a certified mip chain must report no contamination");
  } else {
    assert.ok(
      atlasProbe.mipmaps.reason !== null || atlasProbe.mipmaps.contaminated > 0,
      "a rejected mip chain must carry an explicit diagnostic",
    );
  }
  }

  const interactionProbe = await page.evaluate(async ({ targetInfo }) => {
    const beforeInventory = window.__bend2craft.getInventory();
    window.__bend2craft.resumeForTest();
    window.__bend2craft.interactForTest(0);
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
    return {
      hit: targetInfo.target.hit,
      beforeBlock: targetInfo.block,
      beforeInventory,
    };
  }, { targetInfo: initialTarget });
  const hitCoordinates = {
    x: interactionProbe.hit[0],
    y: interactionProbe.hit[1],
    z: interactionProbe.hit[2],
    beforeBlock: interactionProbe.beforeBlock,
  };
  await page.waitForFunction(
    ({ x, y, z, beforeBlock }) => window.__bend2craft.getBlock(x, y, z) !== beforeBlock,
    hitCoordinates,
    { timeout: 10000 },
  );
  const mined = await page.evaluate(({ x, y, z }) => ({
    block: window.__bend2craft.getBlock(x, y, z),
    inventory: window.__bend2craft.getInventory(),
  }), interactionProbe.hit);
  assert.equal(mined.block, 0);
  assert.notDeepEqual(mined.inventory, interactionProbe.beforeInventory);

  const placement = await page.evaluate(() => {
    const target = window.__bend2craft.getRaycastTarget();
    const result = window.__bend2craft.interactForTest(2);
    return { target, result };
  });
  assert.ok(placement.target?.place, "right-click raycast must expose a placement cell");
  const placeCoordinates = {
    x: placement.target.place[0],
    y: placement.target.place[1],
    z: placement.target.place[2],
  };
  await page.waitForFunction(
    ({ x, y, z }) => window.__bend2craft.getBlock(x, y, z) === 1,
    placeCoordinates,
    { timeout: 3000 },
  );
  const interactionResult = await page.evaluate(({ hit, place }) => ({
    placedBlock: window.__bend2craft.getBlock(...place),
  }), { hit: interactionProbe.hit, place: placement.target.place });
  assert.equal(interactionResult.placedBlock, 1);

  // A block edit must refresh only the chunks it touched, never the whole
  // render window. This is asserted through the mesh cache's rebuild counters
  // so it holds on both backends.
  const editScope = await page.evaluate(async ({ hit, place }) => {
    const before = window.__bend2craft.getFrameDiagnostics();
    const chunkSize = window.__bend2craft.world.chunkSize;
    const chunkOf = (value) => Math.floor(value / chunkSize);
    const touched = new Set([
      `${chunkOf(hit[0])},${chunkOf(hit[2])}`,
      `${chunkOf(place[0])},${chunkOf(place[2])}`,
    ]);
    window.__bend2craft.setBlockForTest(hit[0], hit[1] + 1, hit[2], 0);
    await new Promise((resolve) => window.setTimeout(resolve, 400));
    const after = window.__bend2craft.getFrameDiagnostics();
    return {
      activeChunks: after.activeChunks,
      rebuilds: after.meshRebuilds - before.meshRebuilds,
      touched: touched.size,
    };
  }, { hit: interactionProbe.hit, place: placement.target.place });
  assert.ok(
    editScope.rebuilds > 0,
    "the synthetic edit must actually rebuild a mesh",
  );
  assert.ok(
    editScope.rebuilds <= editScope.activeChunks,
    `an edit rebuilt ${editScope.rebuilds} chunks for a ${editScope.activeChunks} chunk window`,
  );
  assert.ok(
    editScope.rebuilds <= 9,
    `an edit rebuilt ${editScope.rebuilds} chunks, more than a 3x3 seam neighbourhood`,
  );

  // The world now carries farm animals as well as monsters, so a combat scenario
  // that grabs "whatever is alive" would sometimes be measuring a cow. Each of
  // these spawns the hostile it means to fight.
  const primaryInputSetup = await page.evaluate(() => {
    window.__bend2craft.despawnMobsForTest(0);
    const mob = window.__bend2craft.spawnMobForTest(2);
    if (mob === null) return null;
    window.__bend2craft.teleportForTest(mob.x, mob.z - 3, mob.y, Math.PI, -0.3);
    document.getElementById("pause").hidden = true;
    document.getElementById("game-shell").inert = false;
    document.getElementById("game").inert = false;
    return { id: mob.id, health: mob.health };
  });
  assert.ok(primaryInputSetup !== null, "a spawned mob is required for primary-click smoke");
  await page.locator("#game").click({ button: "left" });
  await page.waitForFunction(() => document.pointerLockElement?.id === "game", null, { timeout: 5000 });
  await page.evaluate(({ id }) => {
    const mob = window.__bend2craft.getMobs().find((entry) => entry.id === id);
    window.__bend2craft.setViewForTest(mob.x, mob.y, mob.z - 3, Math.PI, -0.3);
  }, primaryInputSetup);
  await page.mouse.down({ button: "left" });
  await page.mouse.up({ button: "left" });
  const primaryInputProbe = await page.evaluate(({ id }) => (
    window.__bend2craft.getMobs().find((entry) => entry.id === id)
  ), primaryInputSetup);
  await page.evaluate(() => window.__bend2craft.resumeForTest());
  assert.ok(primaryInputProbe?.health < primaryInputSetup.health, "left-click input must damage the mob under the crosshair");

  const mobProbe = await page.evaluate(() => {
    window.__bend2craft.despawnMobsForTest(0);
    const mob = window.__bend2craft.spawnMobForTest(2);
    if (mob === null) return null;
    window.__bend2craft.teleportForTest(mob.x, mob.z - 1, mob.y, Math.PI, -0.3);
    window.__bend2craft.setViewForTest(mob.x, mob.y, mob.z - 1, Math.PI, -0.3);
    const primaryHit = window.__bend2craft.primaryActionForTest(0);
    const hits = [primaryHit];
    for (let index = 0; index < 4; index += 1) {
      // Each hit knocks the mob back, so it leaves the 4-block reach after a
      // few blows. Stand up to it again between hits, or the last blow cannot
      // land and the mob is never actually killed.
      const current = window.__bend2craft.getMobs().find((entry) => entry.id === mob.id);
      window.__bend2craft.teleportForTest(current.x, current.z - 1, current.y, Math.PI, -0.3);
      hits.push(window.__bend2craft.attack());
    }
    const after = window.__bend2craft.getMobs().find((entry) => entry.id === mob.id);
    return {
      id: mob.id,
      kind: mob.kind,
      hits,
      beforeHealth: mob.health,
      afterHealth: after?.health ?? null,
      alive: after?.alive ?? null,
      drops: window.__bend2craft.getDrops(),
    };
  });
  assert.ok(mobProbe !== null, "a spawned mob is required for combat smoke");
  assert.ok(mobProbe.hits.some(Boolean));
  assert.ok(mobProbe.afterHealth < mobProbe.beforeHealth || mobProbe.alive === false);
  assert.equal(mobProbe.alive, false);
  assert.ok(mobProbe.drops.length > 0, "a killed mob must produce a Bend drop");
  const deathTickProbeBefore = await page.evaluate(({ mobId }) => {
    const deadMob = window.__bend2craft.getMobs().find((entry) => entry.id === mobId);
    window.__bend2craft.teleportForTest(deadMob.x + 6, deadMob.z, deadMob.y, 0, 0);
    return {
      health: window.__bend2craft.getPlayer().health,
      drops: window.__bend2craft.getDrops().length,
      alive: deadMob?.alive,
    };
  }, { mobId: mobProbe.id });
  await page.evaluate(() => window.__bend2craft.resumeForTest());
  await page.waitForTimeout(650);
  const deathTickProbeAfter = await page.evaluate(({ mobId }) => ({
    health: window.__bend2craft.getPlayer().health,
    drops: window.__bend2craft.getDrops().length,
    alive: window.__bend2craft.getMobs().find((entry) => entry.id === mobId)?.alive,
  }), { mobId: mobProbe.id });
  assert.equal(deathTickProbeAfter.health, deathTickProbeBefore.health, "a dead mob must not keep damaging the player");
  assert.equal(deathTickProbeAfter.alive, false);
  assert.equal(deathTickProbeAfter.drops, deathTickProbeBefore.drops);
  const drop = mobProbe.drops[0];
  const entityPersistenceBefore = await page.evaluate(({ mobId, dropId }) => {
    window.__bend2craft.teleportForTest(40.5, 24.5, 8);
    window.__bend2craft.save();
    return {
      mob: window.__bend2craft.getMobs().find((entry) => entry.id === mobId),
      drop: window.__bend2craft.getDrops().find((entry) => entry.id === dropId),
    };
  }, { mobId: mobProbe.id, dropId: drop.id });
  assert.equal(entityPersistenceBefore.mob?.alive, false);
  assert.ok(entityPersistenceBefore.drop !== undefined);

  await reloadAndSettle();
  const entityPersistenceAfter = await page.evaluate(({ mobId, dropId }) => ({
    mob: window.__bend2craft.getMobs().find((entry) => entry.id === mobId),
    drop: window.__bend2craft.getDrops().find((entry) => entry.id === dropId),
  }), { mobId: mobProbe.id, dropId: drop.id });
  assert.equal(entityPersistenceAfter.mob?.alive, false);
  assert.ok(entityPersistenceAfter.drop !== undefined);

  await page.evaluate(() => {
    const currentDrop = window.__bend2craft.getDrops()[0];
    window.__bend2craft.teleportForTest(currentDrop.x, currentDrop.z, currentDrop.y);
    window.__bend2craft.resumeForTest();
  });
  await page.waitForFunction(() => window.__bend2craft.getDrops().length === 0, null, { timeout: 15000 });
  const collectedInventory = await page.evaluate(() => window.__bend2craft.getInventory());
  assert.ok(collectedInventory.some((item) => item.item === "wool" || item.item === "rotten_flesh"));

  const farDamageSetup = await page.evaluate(() => {
    window.__bend2craft.teleportForTest(40.5, 24.5, 8);
    const hostile = window.__bend2craft.spawnMobForTest(2, 10.5);
    window.__bend2craft.resumeForTest();
    return { hostile, health: window.__bend2craft.getPlayer().health };
  });
  assert.ok(farDamageSetup.hostile !== null, "a far hostile is required for range smoke");
  await page.waitForTimeout(650);
  const farDamageProbe = await page.evaluate(() => window.__bend2craft.getPlayer());
  assert.equal(farDamageProbe.health, farDamageSetup.health, "a hostile beyond melee range must not damage the player");

  const damageSetup = await page.evaluate(() => {
    window.__bend2craft.teleportForTest(40.5, 24.5, 8);
    const hostile = window.__bend2craft.spawnMobForTest(2);
    window.__bend2craft.resumeForTest();
    return { hostile, health: window.__bend2craft.getPlayer().health };
  });
  assert.ok(damageSetup.hostile !== null, "a hostile mob is required for damage smoke");
  await page.waitForFunction(
    (health) => window.__bend2craft.getPlayer().health < health,
    damageSetup.health,
    { timeout: 5000 },
  );
  const damageProbe = await page.evaluate(() => window.__bend2craft.getPlayer());
  assert.ok(damageProbe.health < 20);

  // Bend owns melee line-of-sight: a hostile walled off from the player must
  // not reach through, and removing the wall must restore the same damage.
  const wallSetup = await page.evaluate(() => {
    window.__bend2craft.teleportForTest(40.5, 24.5, 8);
    // Earlier combat scenarios leave hostiles behind; clear them so this one
    // measures line of sight and not a leftover attacker.
    const remaining = window.__bend2craft.despawnMobsForTest(0);
    const ground = Math.floor(window.__bend2craft.getPlayer().y);
    const wall = [];
    for (let y = ground; y < ground + 3; y += 1) {
      wall.push(window.__bend2craft.setBlockForTest(42, y, 25, 1));
    }
    const hostile = window.__bend2craft.spawnMobForTest(2, 2.0);
    window.__bend2craft.resumeForTest();
    return { hostile, wall, remaining, health: window.__bend2craft.getPlayer().health };
  });
  assert.equal(wallSetup.remaining, 0, "the line-of-sight scenario needs an empty mob set");
  assert.ok(wallSetup.hostile !== null, "a walled hostile is required for line-of-sight smoke");
  assert.ok(wallSetup.wall.every(Boolean), "the smoke wall must be placeable in open air");
  await page.waitForTimeout(650);
  const walledProbe = await page.evaluate(() => window.__bend2craft.getPlayer());
  // Regeneration can raise health while the wall holds, so the contract is
  // "no damage", not "health unchanged".
  assert.ok(
    walledProbe.health >= wallSetup.health,
    `a hostile behind a wall must not damage the player, ${wallSetup.health} -> ${walledProbe.health}`,
  );

  const unwalledSetup = await page.evaluate(() => {
    const ground = Math.floor(window.__bend2craft.getPlayer().y);
    for (let y = ground; y < ground + 3; y += 1) {
      window.__bend2craft.setBlockForTest(42, y, 25, 0);
    }
    window.__bend2craft.resumeForTest();
    return { health: window.__bend2craft.getPlayer().health };
  });
  await page.waitForFunction(
    (health) => window.__bend2craft.getPlayer().health < health,
    unwalledSetup.health,
    { timeout: 5000 },
  );
  await page.waitForFunction(
    () => (document.getElementById("survival-announcer")?.textContent ?? "").length > 0,
    null,
    { timeout: 2000 },
  ).catch(() => {});

  // Water is the way out of a fire, and the symptom is on screen: a hostile
  // standing in the sea is in direct sun, and the water it is in has to put the
  // fire out and stop the sun damage. The fixture is checked from the outside, so
  // a body that walked out of the sea fails the scenario instead of quietly
  // passing it, and a tick that stopped publishing the flag cannot pass either.
  const seaSetup = await page.evaluate(() => {
    // Earlier combat scenarios leave hostiles behind, and this one counts burning
    // bodies, so it starts from an empty mob set.
    const remaining = window.__bend2craft.despawnMobsForTest(0);
    // 19.6 is the peak of the daylight curve, so the sun cannot drift toward dusk
    // in the middle of the measurement.
    window.__bend2craft.setWorldTimeForTest(19.6);
    // The open sea of this seed: a column at sea level whose top cell is water
    // and whose sky is clear, the one place a body is lit and wet at once.
    window.__bend2craft.teleportForTest(41.5, 8.5, 7);
    const hostile = window.__bend2craft.spawnMobForTest(2, 0.5);
    window.__bend2craft.resumeForTest();
    return { remaining, hostile };
  });
  assert.equal(seaSetup.remaining, 0, "the sea dousing scenario needs an empty mob set");
  assert.ok(seaSetup.hostile !== null, "a hostile in the sea is required for the dousing smoke");
  // Long enough for several sunlight ticks, since the first sample is taken
  // before the domain has run at all.
  await page.waitForTimeout(1500);
  const seaProbe = await page.evaluate(() => {
    const mob = window.__bend2craft.getMobs().find((entry) => entry.alive);
    return {
      health: mob.health,
      burning: mob.burning,
      burningMobs: window.__bend2craft.presentation.burningMobs,
      bodyBlock: window.__bend2craft.getBlock(Math.floor(mob.x), Math.floor(mob.y), Math.floor(mob.z)),
    };
  });
  assert.equal(seaProbe.bodyBlock, 7, "the dousing body has to be standing in water");
  assert.equal(seaProbe.burning, false, "a mob in the sea must not report itself burning");
  assert.equal(seaProbe.burningMobs, 0, "a mob in the sea must not be presented as burning");
  assert.ok(
    seaProbe.health >= seaSetup.hostile.health - 0.001,
    `the sun has to leave a mob in water alone, ${seaSetup.hostile.health} -> ${seaProbe.health}`,
  );

  await page.locator("#inventory-toggle").click();
  await page.waitForFunction(() => document.getElementById("inventory-panel")?.hidden === false);
  await page.evaluate(() => window.__bend2craft.hurt(100));
  await page.waitForFunction(() => document.getElementById("death")?.hidden === false, null, { timeout: 5000 });
  const deathModalProbe = await page.evaluate(() => ({
    inventoryHidden: document.getElementById("inventory-panel")?.hidden ?? false,
    canvasInert: document.getElementById("game")?.inert ?? true,
    miningHidden: document.getElementById("mining-progress")?.hidden ?? false,
    health: window.__bend2craft.getPlayer().health,
    paused: window.__bend2craft.getInputState().paused,
  }));
  assert.deepEqual(deathModalProbe, { inventoryHidden: true, canvasInert: true, miningHidden: true, health: 0, paused: true });
  await page.waitForTimeout(500);
  assert.equal(await page.evaluate(() => window.__bend2craft.getPlayer().health), 0, "death must latch at zero health");
  await page.locator('[data-action="respawn"]').click();
  await page.waitForFunction(
    () => window.__bend2craft.getPlayer().health > 0 && document.getElementById("death")?.hidden === true,
    null,
    { timeout: 5000 },
  );
  assert.equal(await page.evaluate(() => document.getElementById("game")?.inert), false);

  const recoveryInventory = await page.evaluate(() => ({
    collectedWool: window.__bend2craft.collect("wool"),
    collectedWood: window.__bend2craft.collect("wood"),
    inventory: window.__bend2craft.getInventory(),
  }));
  assert.equal(recoveryInventory.collectedWool, true);
  assert.equal(recoveryInventory.collectedWood, true);
  assert.ok(recoveryInventory.inventory.some((item) => item.item === "wool"));
  assert.ok(recoveryInventory.inventory.some((item) => item.block === 5));

  const persistenceBefore = await page.evaluate(({ place }) => {
    window.__bend2craft.save();
    return {
      player: window.__bend2craft.getPlayer(),
      inventory: window.__bend2craft.getInventory(),
      placedBlock: window.__bend2craft.getBlock(...place),
    };
  }, { place: placement.target.place });
  assert.ok(persistenceBefore.inventory.some((item) => item.item === "wool"));
  assert.equal(persistenceBefore.placedBlock, 1);

  await reloadAndSettle();
  const persistenceAfter = await page.evaluate(({ place }) => ({
    player: window.__bend2craft.getPlayer(),
    inventory: window.__bend2craft.getInventory(),
    placedBlock: window.__bend2craft.getBlock(...place),
  }), { place: placement.target.place });
  assert.ok(persistenceAfter.player.health > 0);
  assert.ok(persistenceAfter.inventory.some((item) => item.item === "wool"));
  assert.equal(persistenceAfter.placedBlock, 1);

  const negativeRequest = await page.evaluate(() => (
    window.__bend2craft.teleportForTest(-40, -40, 8, Math.PI * 0.25, -0.18)
  ));
  assert.ok(negativeRequest.pendingChunks > 0);
  await page.waitForFunction(
    () => {
      const diagnostics = window.__bend2craft.getFrameDiagnostics();
      return diagnostics.player.x < 0
        && diagnostics.player.z < 0
        && diagnostics.activeChunks > 0
        && diagnostics.pendingChunks === 0
        && diagnostics.meshRebuildPending === false;
    },
    null,
    { timeout: 30000 },
  );
  const negativeState = await page.evaluate(() => window.__bend2craft.getFrameDiagnostics());
  assert.ok(negativeState.player.x < 0 && negativeState.player.z < 0);
  assert.equal(negativeState.pendingChunks, 0);
  await page.evaluate(() => window.__bend2craft.resumeForTest());

  const streamingSwap = await page.evaluate(() => {
    const before = window.__bend2craft.world.activeChunks;
    const result = window.__bend2craft.loadChunksAt(256, 256, 1, false);
    return {
      before,
      after: window.__bend2craft.world.activeChunks,
      pending: window.__bend2craft.world.pendingChunks,
      reportedActive: result.activeChunks,
    };
  });
  assert.ok(streamingSwap.before > 0);
  assert.ok(streamingSwap.pending > 0);
  assert.ok(streamingSwap.after > 0, "keep the current render window while a swap is pending");
  assert.ok(streamingSwap.reportedActive > 0);

  await page.locator("#inventory-toggle").click();
  await page.waitForFunction(() => document.getElementById("inventory-panel")?.hidden === false);
  const inventoryIconProbe = await page.evaluate(() => {
    const swatches = [...document.querySelectorAll(".inventory-slot .slot-swatch[data-item]")];
    return {
      slots: document.querySelectorAll(".inventory-slot").length,
      painted: swatches.filter((node) => getComputedStyle(node).backgroundImage !== "none").length,
      namesHidden: [...document.querySelectorAll(".inventory-slot .slot-name")]
        .every((node) => getComputedStyle(node).display === "none"),
      draggable: [...document.querySelectorAll(".inventory-slot")]
        .filter((node) => node.draggable).length,
    };
  });
  assert.ok(inventoryIconProbe.slots > 0);
  assert.ok(inventoryIconProbe.painted > 0, "open inventory slots must use the item atlas icons");
  assert.equal(inventoryIconProbe.namesHidden, true);
  assert.ok(inventoryIconProbe.draggable > 0, "inventory slots must support drag transfer");
  // The panel moves focus into itself on the next animation frame, which is a
  // separate turn from the click, so wait for it rather than reading once.
  await page.waitForFunction(
    () => document.getElementById("inventory-panel")?.contains(document.activeElement) === true,
    null,
    { timeout: 5000 },
  );
  const modalProbe = await page.evaluate(() => {
    const panel = document.getElementById("inventory-panel");
    const canvas = document.getElementById("game");
    return {
      panelVisible: panel?.hidden === false,
      panelInert: panel?.inert === true,
      canvasInert: canvas?.inert === true,
      focusInside: panel?.contains(document.activeElement) ?? false,
    };
  });
  assert.deepEqual(modalProbe, {
    panelVisible: true,
    panelInert: false,
    canvasInert: true,
    focusInside: true,
  });
  const inventoryBeforeShortcut = await page.evaluate(() => window.__bend2craft.getInventory());
  await page.keyboard.press("KeyQ");
  assert.deepEqual(await page.evaluate(() => window.__bend2craft.getInventory()), inventoryBeforeShortcut);
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.getElementById("inventory-panel")?.contains(document.activeElement)), true);
  await page.keyboard.press("Escape");
  await page.waitForFunction(() => document.getElementById("inventory-panel")?.hidden === true);
  await page.locator("#inventory-toggle").click();
  await page.waitForFunction(() => document.getElementById("inventory-panel")?.hidden === false);
  await page.locator("#shaped-recipe").selectOption("planks");
  await page.locator('[data-shaped-action="load"]').click();
  const shapedLoaded = await page.evaluate(() => ({
    occupied: document.querySelectorAll("#crafting-grid .inventory-slot:not(.empty)").length,
    status: document.getElementById("shaped-status")?.textContent,
  }));
  assert.equal(shapedLoaded.occupied, 1);
  assert.match(shapedLoaded.status ?? "", /Pattern loaded/);
  await page.locator('[data-shaped-action="craft"]').click();
  const shapedCrafted = await page.evaluate(() => ({
    occupied: document.querySelectorAll("#crafting-grid .inventory-slot:not(.empty)").length,
    inventory: window.__bend2craft.getInventory(),
  }));
  assert.equal(shapedCrafted.occupied, 0, JSON.stringify(shapedCrafted));
  assert.ok(shapedCrafted.inventory.some((item) => item.item === "planks"));
  const shieldInventory = await page.evaluate(() => {
    const collected = window.__bend2craft.collect("shield");
    const inventory = window.__bend2craft.getInventory();
    return { collected, slot: inventory.findIndex((item) => item.item === "shield") };
  });
  assert.equal(shieldInventory.collected, true);
  assert.ok(shieldInventory.slot >= 0);
  await page.locator(`#inventory-slots [data-slot="${shieldInventory.slot}"]`).click();
  const equipped = await page.evaluate(() => window.__bend2craft.getEquipment());
  assert.equal(Number(equipped.offhand), 38);
  await page.locator('#equipment-slots [data-equipment-slot="0"]').click();
  const unequipped = await page.evaluate(() => window.__bend2craft.getEquipment());
  assert.equal(Number(unequipped.offhand), 0);
  await page.locator("[data-close-inventory]").click();
  await page.waitForFunction(() => document.getElementById("inventory-panel")?.hidden === true);

  const chestProbe = await page.evaluate(() => {
    const player = window.__bend2craft.getPlayer();
    let target = null;
    for (let y = 1; y < 14 && target === null; y += 1) {
      for (let x = Math.floor(player.x) - 4; x <= Math.floor(player.x) + 4 && target === null; x += 1) {
        for (let z = Math.floor(player.z) - 4; z <= Math.floor(player.z) + 4; z += 1) {
          if (Math.hypot(x + 0.5 - player.x, z + 0.5 - player.z) < 1.5) continue;
          if (window.__bend2craft.getBlock(x, y, z) === 0
            && window.__bend2craft.getBlock(x, y - 1, z) !== 0) {
            target = [x, y, z];
            break;
          }
        }
      }
    }
    if (target === null) return { target: null };
    const collected = window.__bend2craft.collect("chest");
    const placed = collected && window.__bend2craft.placeAt("chest", ...target);
    const opened = placed && window.__bend2craft.toggleChest();
    const selected = opened && window.__bend2craft.selectSlotForTest(0);
    const deposited = selected && window.__bend2craft.chestAction("deposit");
    const stored = window.__bend2craft.getChest()[0];
    const withdrawn = deposited && window.__bend2craft.chestAction("withdraw", 0);
    return {
      target,
      collected,
      placed,
      opened,
      deposited,
      withdrawn,
      block: window.__bend2craft.getBlock(...target),
      slots: window.__bend2craft.getChest().length,
      storedItem: stored?.item ?? null,
      afterWithdrawCount: window.__bend2craft.getChest()[0]?.count ?? null,
      panelHidden: document.getElementById("chest-panel")?.hidden ?? true,
    };
  });
  assert.ok(chestProbe.target !== null, "a chest placement target is required");
  assert.equal(chestProbe.collected, true);
  assert.equal(chestProbe.placed, true);
  assert.equal(chestProbe.block, 26);
  assert.equal(chestProbe.opened, true);
  assert.equal(chestProbe.deposited, true);
  assert.equal(chestProbe.withdrawn, true);
  assert.equal(chestProbe.slots, 9);
  assert.notEqual(chestProbe.storedItem, 0);
  assert.equal(chestProbe.afterWithdrawCount, 0);
  assert.equal(chestProbe.panelHidden, false);
  await page.evaluate(() => window.__bend2craft.toggleChest());
  const dropProbe = await page.evaluate(() => {
    const before = window.__bend2craft.getDrops().length;
    const ok = window.__bend2craft.drop(false);
    return { ok, before, after: window.__bend2craft.getDrops().length };
  });
  assert.equal(dropProbe.ok, true);
  assert.equal(dropProbe.after, dropProbe.before + 1);

  await page.setViewportSize({ width: 390, height: 844 });
  const narrowProbe = await page.evaluate(() => {
    const air = document.getElementById("air");
    const wasHidden = air?.hidden ?? true;
    if (air !== null) air.hidden = false;
    const airDisplay = air === null ? null : getComputedStyle(air).display;
    if (air !== null) air.hidden = wasHidden;
    return {
      overflow: document.documentElement.scrollWidth > window.innerWidth + 1
        || document.body.scrollWidth > window.innerWidth + 1,
      airDisplay,
    };
  });
  assert.equal(narrowProbe.overflow, false, "narrow game shell must not overflow horizontally");
  assert.notEqual(narrowProbe.airDisplay, "none", "narrow layouts must retain underwater air feedback");
  const narrowAir = [];
  for (const width of [320, 280]) {
    await page.setViewportSize({ width, height: 844 });
    narrowAir.push(await page.evaluate(() => {
      const air = document.getElementById("air");
      const wasHidden = air?.hidden ?? true;
      if (air !== null) air.hidden = false;
      const rect = air?.getBoundingClientRect();
      if (air !== null) air.hidden = wasHidden;
      return { left: rect?.left ?? 0, right: rect?.right ?? 0, viewport: window.innerWidth };
    }));
  }
  assert.ok(narrowAir.every((probe) => probe.left >= 0 && probe.right <= probe.viewport), "air pips must remain visible at 320px and 280px");

  assert.deepEqual(consoleErrors, []);
  assert.deepEqual(pageErrors, []);
  console.log(JSON.stringify({ ...state, continuedWorld, textureProbe, animatedSurfaceProbe, atlasProbe, interactionResult, mobProbe, collectedInventory, damageProbe, recoveryInventory, deathModalProbe, persistenceBefore, persistenceAfter, entityPersistenceBefore, entityPersistenceAfter, negativeState, streamingSwap, inventoryToggle: "ok", modalProbe, shapedLoaded, shapedCrafted, shieldInventory, equipped, unequipped, chestProbe, dropProbe, narrowProbe, narrowAir, consoleErrors, pageErrors }));
} catch (error) {
  // A bare Playwright timeout says which line waited, never why the page never
  // got there. The page's own errors are the only evidence, and the success path
  // asserts on them, so report them on the way out instead of discarding them.
  process.exitCode = 1;
  const detail = {
    message: error?.message ?? String(error),
    consoleErrors,
    pageErrors,
  };
  try {
    detail.url = page.url();
    detail.state = await page.evaluate(() => ({
      health: window.__bend2craft?.getPlayer?.().health ?? null,
      paused: window.__bend2craft?.getInputState?.().paused ?? null,
      visibleScreens: [...document.querySelectorAll("[data-screen]")]
        .filter((node) => !node.hidden)
        .map((node) => node.id),
      inventoryHidden: document.getElementById("inventory-panel")?.hidden ?? null,
      deathHidden: document.getElementById("death")?.hidden ?? null,
      modalInert: [...document.querySelectorAll("[inert]")].map((node) => node.id),
    }));
  } catch (probeError) {
    detail.stateUnavailable = String(probeError);
  }
  console.error(`browser smoke failed: ${JSON.stringify(detail, null, 2)}`);
  throw error;
} finally {
  await browser.close();
}
