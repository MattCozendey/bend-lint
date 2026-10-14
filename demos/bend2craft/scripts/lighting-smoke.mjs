import assert from "node:assert/strict";
import { chromium } from "playwright";

const baseUrl = process.argv[2] ?? "http://127.0.0.1:3000";
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
try {
  await page.addInitScript(() => {
    window.localStorage.setItem(
      "bend2craft-options",
      JSON.stringify({ fov: 75, sensitivity: 1, showCoords: true, renderDistance: 2 }),
    );
  });
  await page.goto(`${baseUrl}/?play=1&seed=1337`, { waitUntil: "networkidle", timeout: 30000 });
  await page.waitForFunction(
    () => window.__bend2craft?.world?.activeChunks > 0
      && window.__bend2craft?.world?.pendingChunks === 0
      && window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false,
    null,
    { timeout: 90000 },
  );

  const target = await page.evaluate(() => {
    const player = window.__bend2craft.getPlayer();
    for (let y = 16; y >= 1; y -= 1) {
      for (let x = Math.floor(player.x) - 6; x <= Math.floor(player.x) + 6; x += 1) {
        for (let z = Math.floor(player.z) - 6; z <= Math.floor(player.z) + 6; z += 1) {
          const block = window.__bend2craft.getBlock(x, y, z);
          if (block !== 3 || window.__bend2craft.getBlock(x, y + 1, z) !== 0) continue;
          const dx = x + 0.5 - player.x;
          const dy = y + 0.5 - (player.y + 1.62);
          const dz = z + 0.5 - player.z;
          const horizontal = Math.hypot(dx, dz);
          const distance = Math.hypot(horizontal, dy);
          if (horizontal < 0.5 || distance > 7.5) continue;
          const yaw = Math.atan2(dx, -dz);
          const pitch = Math.atan2(dy, horizontal);
          const ray = window.__bend2craft.setViewForTest(player.x, player.y, player.z, yaw, pitch);
          if (ray?.hit?.[0] === x && ray.hit[1] === y && ray.hit[2] === z) {
            return { x, y, z, block, ray };
          }
        }
      }
    }
    return null;
  });
  assert.ok(target, "a grass surface block target is required");

  const before = await page.evaluate(({ x, y, z }) => ({
    block: window.__bend2craft.getBlock(x, y, z),
    light: window.__bend2craft.getLight(x, y, z),
    aboveLight: window.__bend2craft.getLight(x, y + 1, z),
  }), target);
  assert.equal(before.block, 3);
  assert.equal(before.light, 0);
  assert.equal(before.aboveLight, 15);

  await page.evaluate(async () => {
    window.__bend2craft.resumeForTest();
    window.__bend2craft.interactForTest(0);
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
  });
  await page.waitForFunction(
    ({ x, y, z }) => window.__bend2craft.getBlock(x, y, z) === 0,
    target,
    { timeout: 5000 },
  );
  await page.waitForFunction(
    () => window.__bend2craft.getFrameDiagnostics().meshRebuildPending === false,
    null,
    { timeout: 5000 },
  );

  const after = await page.evaluate(({ x, y, z }) => ({
    block: window.__bend2craft.getBlock(x, y, z),
    light: window.__bend2craft.getLight(x, y, z),
    aboveLight: window.__bend2craft.getLight(x, y + 1, z),
    diagnostics: window.__bend2craft.getFrameDiagnostics(),
  }), target);
  assert.equal(after.block, 0);
  assert.equal(after.light, 15, "removing a surface block must expose sky light");
  assert.equal(after.light, after.aboveLight);
  console.log(JSON.stringify({ target, before, after }));
} finally {
  await browser.close();
}
