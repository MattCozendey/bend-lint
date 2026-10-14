import assert from "node:assert/strict";
import { chromium } from "playwright";

// All throwaway output goes in the repo's single gitignored scratch folder, so
// no session ever needs a new directory or a new permission grant.
const SCRATCHPAD = "scratchpad";

const baseUrl = process.argv[2] ?? "http://127.0.0.1:3000";
const captureDir = process.env.BEND2CRAFT_CAPTURE_DIR ?? `${SCRATCHPAD}/quality`;
const browser = await chromium.launch({ headless: true, args: ["--use-angle=swiftshader"] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
const consoleErrors = [];
const pageErrors = [];
page.on("console", (message) => { if (message.type() === "error") consoleErrors.push(message.text()); });
page.on("pageerror", (error) => pageErrors.push(String(error)));

try {
  await page.goto(`${baseUrl}/?test=1&quality=high&play=1&seed=1337&renderer=webgl&world=visual-quality`, { waitUntil: "domcontentloaded", timeout: 30000 });
  await page.waitForFunction(
    () => window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false
      && window.__bend2craft?.world?.pendingChunks === 0,
    null,
    { timeout: 30000 },
  );

  // The camera looks along [sin(yaw), sin(pitch), -cos(yaw)], so aiming at the
  // sun is yaw = atan2(sunX, -sunZ) for sunDirection = [-cos(0.08t), sin(0.08t), 0.28].
  // Poses are chosen to actually look at the sun and at open ground: a pose that
  // points into a tree canopy checks the frame is non-blank but nothing else.
  // The teleport helper pauses the game, which raises the pause dialog over the
  // scene. Hide the overlays so a capture is evidence about the rendered world
  // rather than about the pause menu.
  // Remove the overlays from the DOM rather than hiding them with CSS: the
  // stylesheet uses `!important` on several of them, and a specificity fight
  // over a cosmetic rule is not worth it in a check whose job is to capture the
  // rendered world.
  await page.evaluate(() => {
    // Removing rather than hiding: the stylesheet marks several of these
    // `!important`, and a specificity fight over a cosmetic rule is not worth it
    // in a check whose job is to capture the rendered world. The list is the set
    // of nodes that still paint over the canvas, measured rather than guessed.
    for (const id of ["pause", "hud", "help", "toast", "lock-hint", "hotbar", "vitals", "crosshair", "xp-hud", "inventory-toggle", "selected", "vignette", "particles"]) {
      document.getElementById(id)?.remove();
    }
  });

  const sunYaw = (time) => {
    const phase = time * 0.08;
    return Math.atan2(-Math.cos(phase), -0.28);
  };
  const poses = [
    { name: "sun-facing-day", time: 32, x: 25.5, z: 16.5, yaw: sunYaw(32), pitch: 0.14 },
    { name: "open-terrain", time: 32, x: 25.5, z: 16.5, yaw: sunYaw(32) + Math.PI, pitch: 0.02 },
    { name: "golden-hour", time: 36, x: 25.5, z: 16.5, yaw: sunYaw(36), pitch: 0.1 },
    { name: "spawn-night", time: 58.9, x: 25.5, z: 16.5, yaw: sunYaw(58.9), pitch: 0.3 },
    // Eye height with the ground filling the lower frame. Every other pose looks
    // across the world from far enough that a moving block surface is sub-pixel,
    // so a capture set without this one cannot show whether the ground a player
    // is standing on is actually still. This is the pose the wind-on-terrain
    // regression showed up in: 29k pixels of near ground moved with it.
    { name: "ground-level-grass", time: 32, x: 25.5, z: 16.5, yaw: sunYaw(32) + Math.PI, pitch: 0.3 },
  ];
  const captures = [];
  for (const pose of poses) {
    await page.evaluate(({ time, x, z, yaw, pitch }) => {
      window.__bend2craft.setWorldTimeForTest(time);
      window.__bend2craft.teleportForTest(x, z, 9, yaw, pitch);
    }, pose);
    await page.waitForTimeout(500);
    const path = `${captureDir}/${pose.name}.png`;
    await page.screenshot({ path });
    const probe = await page.evaluate(async () => {
      const region = [300, 210, 96, 96];
      const first = window.__bend2craft.readFramePixels(...region);
      await new Promise((resolve) => requestAnimationFrame(() => resolve()));
      const second = window.__bend2craft.readFramePixels(...region);
      let changedPixels = 0;
      let nonBlackPixels = 0;
      for (let index = 0; index < first.length; index += 4) {
        if (first[index] !== second[index]
          || first[index + 1] !== second[index + 1]
          || first[index + 2] !== second[index + 2]
          || first[index + 3] !== second[index + 3]) changedPixels += 1;
        if (first[index] + first[index + 1] + first[index + 2] > 12) nonBlackPixels += 1;
      }
      return { pixels: first.length / 4, changedPixels, nonBlackPixels, frame: window.__bend2craft.getFrameDiagnostics() };
    });
    assert.ok(probe.pixels > 0);
    assert.equal(probe.frame.shaderQuality, 1, "visual-quality smoke must exercise the advanced shader path");
    assert.ok(probe.nonBlackPixels > probe.pixels * 0.2, `${pose.name} should not render a blank frame`);
    assert.ok(probe.changedPixels <= 96, `${pose.name} should not flicker in a static pose`);
    captures.push({ ...pose, path, probe });
  }

  const atlas = await page.evaluate(() => {
    const probes = Array.from({ length: 50 }, (_, tile) => window.__bend2craft.getAtlasTexelProbe(tile));
    return {
      mismatches: probes.reduce((sum, probe) => sum + probe.mismatches, 0),
      flipped: probes.reduce((sum, probe) => sum + probe.flippedMismatches, 0),
    };
  });
  assert.equal(atlas.mismatches, 0, "visible atlas texels must match the source canvas");
  assert.deepEqual(consoleErrors, []);
  assert.deepEqual(pageErrors, []);
  console.log(JSON.stringify({ captures, atlas, consoleErrors, pageErrors }));
} finally {
  await browser.close();
}
