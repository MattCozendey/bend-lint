import { chromium } from "playwright";

const baseUrl = process.argv[2] ?? "http://127.0.0.1:3000";
const durationMs = Math.max(1000, Number(process.argv[3] ?? 2500));
const renderDistance = Math.max(2, Math.min(6, Number(process.env.RENDER_DISTANCE ?? 2)));
const browser = await chromium.launch({
  headless: true,
  args: ["--enable-unsafe-webgpu", "--use-angle=swiftshader"],
});

async function run(renderer) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await context.newPage();
  const errors = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(String(error)));
  try {
    await page.addInitScript(({ rendererValue, renderDistanceValue }) => {
      window.localStorage.setItem("bend2craft-options", JSON.stringify({
        fov: 75,
        sensitivity: 1,
        showCoords: true,
        renderDistance: renderDistanceValue,
        renderer: rendererValue,
      }));
    }, { rendererValue: renderer, renderDistanceValue: renderDistance });
    await page.goto(`${baseUrl}/?play=1&renderer=${renderer}&seed=1337`, {
      waitUntil: "networkidle",
      timeout: 30000,
    });
    await page.waitForFunction(
      () => window.__bend2craft !== undefined || document.getElementById("error")?.hidden === false,
      null,
      { timeout: 30000 },
    );
    const startupError = await page.evaluate(() => document.getElementById("error")?.hidden === false
      ? document.getElementById("error").textContent
      : null);
    if (startupError !== null) throw new Error(startupError);
    await page.waitForFunction(
      () => window.__bend2craft?.world?.activeChunks > 0
        && window.__bend2craft?.world?.pendingChunks === 0,
      null,
      { timeout: 30000 },
    );
    await page.waitForFunction(
      () => window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false,
      null,
      { timeout: 30000 },
    );
    await page.waitForTimeout(500);
    const frameSamples = await page.evaluate(async (sampleDuration) => new Promise((resolve) => {
      const samples = [];
      let previous = performance.now();
      const end = previous + sampleDuration;
      function sample(now) {
        samples.push(now - previous);
        previous = now;
        if (now >= end) resolve(samples);
        else requestAnimationFrame(sample);
      }
      requestAnimationFrame(sample);
    }), durationMs);
    const diagnostics = await page.evaluate(() => window.__bend2craft.getFrameDiagnostics());
    const submit = await page.evaluate(() => window.__bend2craft.glBufferSizes?.() ?? null);
    const sortedSamples = [...frameSamples].sort((a, b) => a - b);
    const percentile = (fraction) => sortedSamples[Math.min(
      sortedSamples.length - 1,
      Math.max(0, Math.ceil(sortedSamples.length * fraction) - 1),
    )] ?? 0;
    const averageFrameMs = frameSamples.reduce((sum, value) => sum + value, 0) / Math.max(1, frameSamples.length);
    return {
      renderer,
      actualRenderer: diagnostics.renderer,
      rendererName: diagnostics.rendererName,
      shaderQuality: diagnostics.shaderQuality,
      durationMs,
      sampleCount: frameSamples.length,
      fps: 1000 / averageFrameMs,
      minFps: 1000 / Math.max(...frameSamples),
      p95FrameMs: percentile(0.95),
      p99FrameMs: percentile(0.99),
      maxFrameMs: Math.max(...frameSamples),
      activeChunks: diagnostics.activeChunks,
      renderDistance,
      terrainQuads: diagnostics.terrainQuads,
      meshRebuilds: diagnostics.meshRebuilds,
      // Chunk culling accounting. WebGL has no per-chunk submit, so the GPU
      // backend reports the resident and visible split that the culler decided.
      culling: submit?.backend === "webgpu"
        ? {
          residentChunks: submit.residentChunks,
          visibleChunks: submit.visibleChunks,
          culledChunks: submit.culledChunks,
          drawCalls: submit.drawCalls,
          submittedVertices: submit.submittedVertices,
          submittedVertexBytes: submit.submittedVertexBytes,
        }
        : null,
      errors,
    };
  } finally {
    await context.close();
  }
}

try {
  const webgpuSupport = await (async () => {
    const page = await browser.newPage();
    try {
      await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 30000 });
      return await page.evaluate(async () => {
        if (navigator.gpu === undefined) return false;
        return (await navigator.gpu.requestAdapter()) !== null;
      });
    } finally {
      await page.close();
    }
  })();
  const results = [await run("webgl")];
  if (webgpuSupport) {
    try {
      results.push(await run("webgpu"));
    } catch (error) {
      results.push({
        renderer: "webgpu",
        skipped: true,
        reason: error instanceof Error ? error.message : String(error),
      });
    }
  }
  const runtimeErrors = results.flatMap((result) => result.errors ?? []);
  if (runtimeErrors.length > 0) {
    throw new Error(`Renderer benchmark reported browser errors: ${runtimeErrors.join(" | ")}`);
  }
  const softwareFallbackMissed = results.some((result) => (
    /swiftshader|llvmpipe|basic render/i.test(result.rendererName ?? "")
    && result.shaderQuality !== 0
  ));
  if (softwareFallbackMissed) {
    throw new Error("Software renderer did not select the compiled fallback shader permutation.");
  }
  console.log(JSON.stringify({ webgpuSupport, results }));
} finally {
  await browser.close();
}
