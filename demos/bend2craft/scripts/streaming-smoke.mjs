import { chromium } from "playwright";

const baseUrl = process.argv[2] ?? "http://127.0.0.1:3000";
const distance = Number(process.argv[3] ?? 6);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
try {
  await page.addInitScript(({ value }) => window.localStorage.setItem(
    "bend2craft-options",
    JSON.stringify({ fov: 75, sensitivity: 1, showCoords: true, renderDistance: value }),
  ), { value: distance });
  const started = Date.now();
  await page.goto(`${baseUrl}/?play=1&seed=1337`, { waitUntil: "networkidle", timeout: 30000 });
  const boot = Date.now();
  await page.waitForFunction(
    ({ value }) => window.__bend2craft?.world?.renderRadius === value
      && window.__bend2craft?.world?.activeChunks > 0,
    { value: distance },
    { timeout: 30000 },
  );
  const firstActive = Date.now();
  await page.waitForFunction(
    ({ value }) => window.__bend2craft?.world?.renderRadius === value
      && window.__bend2craft?.world?.activeChunks === (value * 2 + 1) ** 2
      && window.__bend2craft?.world?.pendingChunks === 0
      && window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false,
    { value: distance },
    { timeout: 240000 },
  );
  const state = await page.evaluate(() => ({
    world: window.__bend2craft.world,
    frame: window.__bend2craft.getFrameDiagnostics(),
  }));
  console.log(JSON.stringify({
    distance,
    navigationMs: boot - started,
    firstActiveMs: firstActive - started,
    readyMs: Date.now() - started,
    workerCount: state.world.workerCount,
    workerRequests: state.world.workerRequests,
    workerHydrates: state.world.workerHydrates,
    activeChunks: state.world.activeChunks,
    pendingChunks: state.world.pendingChunks,
    fps: state.frame.fps,
    meshRebuilds: state.frame.meshRebuilds,
    meshWorkerRequests: state.frame.meshWorkerRequests,
  }));
} finally {
  await browser.close();
}
