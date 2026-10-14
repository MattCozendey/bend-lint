// Two browsers in one multiplayer world, against the dev server's room
// (`npm run browser:multiplayer-smoke`, which starts it in peaceful mode).
// Checks presence, a shared block edit, server-simulated water and farming,
// a shared chest, and the server's movement correction.
import assert from "node:assert/strict";
import { chromium } from "playwright";

const baseUrl = process.argv[2] ?? "http://127.0.0.1:3000";
const TIMEOUT = 60000;
const browsers = [];
const errors = [];

async function join(label) {
  // A browser each: separate storage, so each is its own player. (Two
  // contexts of one browser share its GPU process, and the second one's
  // chunk workers starve behind the first's software rendering.)
  const browser = await chromium.launch({ headless: true });
  browsers.push(browser);
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  page.on("pageerror", (error) => errors.push(`${label}: ${error}`));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(`${label}: ${message.text()}`);
  });
  await page.goto(`${baseUrl}/?play=1&mp=1&test=1`, { waitUntil: "load", timeout: TIMEOUT });
  try {
    await page.waitForFunction(
      () => window.__bend2craft?.multiplayer?.()?.connected === true
        && window.__bend2craft.world.activeChunks > 0 && window.__bend2craft.world.pendingChunks === 0,
      null,
      { timeout: TIMEOUT, polling: 250 },
    );
  } catch (error) {
    const state = await page.evaluate(() => ({
      multiplayer: window.__bend2craft?.multiplayer?.() ?? null,
      world: window.__bend2craft?.world ? { ...window.__bend2craft.world } : null,
      error: document.getElementById("error")?.textContent ?? null,
    }));
    throw new Error(`${label} never became ready: ${JSON.stringify(state)} ${errors.join("; ")}`, { cause: error });
  }
  return page;
}

async function until(page, fn, arg, timeout = 30000) {
  try {
    await page.waitForFunction(fn, arg, { timeout, polling: 200 });
  } catch (error) {
    const state = await Promise.race([
      page.evaluate(() => ({
        player: window.__bend2craft.getPlayer(),
        inventory: window.__bend2craft.getInventory().filter(Boolean).map((item) => item.item ?? item.block),
        multiplayer: window.__bend2craft.multiplayer(),
      })),
      new Promise((resolve) => setTimeout(() => resolve("page not answering"), 5000)),
    ]);
    throw new Error(`timed out waiting for ${fn} (${JSON.stringify(arg)}): ${JSON.stringify(state)}`, { cause: error });
  }
}
const call = (page, name, ...args) => page.evaluate(([fn, values]) => window.__bend2craft[fn](...values), [name, args]);

try {
  const first = await join("first");
  const second = await join("second");

  // Presence: each sees the other.
  await until(first, () => window.__bend2craft.multiplayer().players.length === 1);
  await until(second, () => window.__bend2craft.multiplayer().players.length === 1);

  // Work next to the first player's feet, on its own column.
  const spot = await first.evaluate(() => {
    const player = window.__bend2craft.getPlayer();
    const x = Math.floor(player.x) + 2;
    const z = Math.floor(player.z);
    let y = Math.floor(player.y) + 4;
    while (y > 0 && window.__bend2craft.getBlock(x, y - 1, z) === 0) y -= 1;
    return { x, y, z };
  });
  const ground = await call(first, "getBlock", spot.x, spot.y - 1, spot.z);
  assert.ok(ground === 2 || ground === 3, `grass or dirt beside the spawn (got ${ground})`);

  // A block edit reaches the other browser.
  const pillar = { x: spot.x, y: spot.y, z: spot.z + 2 };
  assert.equal(await call(first, "setBlockForTest", pillar.x, pillar.y, pillar.z, 5), 5);
  await until(second, (p) => window.__bend2craft.getBlock(p.x, p.y, p.z) === 5, pillar);

  // Farming runs on the server: till, then plant; both browsers see it.
  assert.equal(await call(first, "collect", "wooden_hoe", 1), true);
  assert.equal(await call(first, "collect", "wheat_seeds", 4), true);
  assert.equal(await call(first, "tillAt", spot.x, spot.y - 1, spot.z), true);
  const farmland = { x: spot.x, y: spot.y - 1, z: spot.z };
  await until(second, (p) => window.__bend2craft.getBlock(p.x, p.y, p.z) === 20, farmland);
  assert.equal(await call(first, "plantCropAt", spot.x, spot.y, spot.z), true);
  await until(second, (p) => window.__bend2craft.getBlock(p.x, p.y, p.z) === 16, spot);

  // A bucket of water: the server spreads it, and both browsers see the flow.
  const pool = { x: spot.x, y: spot.y, z: spot.z - 3 };
  assert.equal(await call(first, "collect", "water_bucket", 1), true);
  assert.equal(await call(first, "placeWaterAt", pool.x, pool.y, pool.z), true);
  await until(second, (p) => window.__bend2craft.getBlock(p.x, p.y, p.z) === 7, pool);
  await until(first, () => window.__bend2craft.getInventory().some((item) => item?.item === "empty_bucket"));

  // A chest placed by one player is filled by the other.
  const chest = { x: spot.x - 3, y: spot.y, z: spot.z };
  assert.equal(await call(first, "collect", "chest", 1), true);
  assert.equal(await call(first, "placeAt", "chest", chest.x, chest.y, chest.z), true);
  await until(second, (p) => window.__bend2craft.getBlock(p.x, p.y, p.z) === 26, chest);

  // Movement is validated: a teleport is refused and the player is sent back.
  const before = await call(first, "getPlayer");
  await call(first, "setViewForTest", before.x + 200, before.y + 30, before.z, before.yaw, before.pitch);
  await until(first, (x) => Math.abs(window.__bend2craft.getPlayer().x - x) < 2, before.x);
  const seen = await second.evaluate(() => window.__bend2craft.multiplayer().players[0]);
  assert.ok(Math.abs(seen.x - before.x) < 5, "the other browser never saw the teleport");

  assert.deepEqual(errors, []);
  console.log("multiplayer smoke ok");
} finally {
  await Promise.all(browsers.map((browser) => browser.close()));
}
