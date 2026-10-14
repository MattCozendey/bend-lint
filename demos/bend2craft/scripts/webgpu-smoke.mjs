import assert from "node:assert/strict";
import { chromium } from "playwright";
import {
  WEBGPU_SKY_SHADER,
  WEBGPU_TERRAIN_SHADER,
} from "../web/webgpu-terrain-renderer.js";
import {
  cullingAgreesWithProbe,
  frameReadbackReason,
  probeSceneFrame,
} from "../web/webgpu-frame-readback.js";
// The same layout the renderer declares. This used to be a hand-copied list that
// fell behind the shader, so a layout change surfaced here as a bogus shader
// error instead of as the stale copy it was.
import { TERRAIN_VERTEX_LAYOUT } from "../web/webgpu-chunk-buffers.js";

const baseUrl = process.argv[2] ?? null;
const browser = await chromium.launch({
  headless: true,
  args: ["--enable-unsafe-webgpu", "--use-angle=swiftshader"],
});

async function inspectRuntime(renderer) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const consoleErrors = [];
  const consoleWarnings = [];
  const pageErrors = [];
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
    if (message.type() === "warning") consoleWarnings.push(message.text());
  });
  page.on("pageerror", (error) => pageErrors.push(String(error)));
  try {
    await page.goto(`${baseUrl}/?play=1&renderer=${renderer}&seed=1337`, {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });
    await page.waitForFunction(
      () => window.__bend2craft?.getFrameDiagnostics?.() !== undefined
        || document.getElementById("error")?.hidden === false
        // A backend that cannot start returns the player to the menu with a
        // banner instead of stranding them on an error page, so the banner is a
        // third way this navigation can finish. Waiting only on the first two
        // spent the whole timeout here on every fallback.
        || document.getElementById("backend-notice")?.hidden === false,
      null,
      { timeout: 30000 },
    ).catch(() => {});
    await page.waitForFunction(
      () => window.__bend2craft?.world?.activeChunks > 0
        && window.__bend2craft?.world?.pendingChunks === 0
        && window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false,
      null,
      { timeout: 30000 },
    ).catch(() => {});
    const state = await page.evaluate(() => ({
      frame: window.__bend2craft?.getFrameDiagnostics?.() ?? null,
      gpuBuffers: window.__bend2craft?.glBufferSizes?.() ?? null,
      readbackSupport: window.__bend2craft?.getFrameReadbackSupport?.() ?? null,
      errorHidden: document.getElementById("error")?.hidden ?? false,
      errorText: document.getElementById("error")?.textContent ?? "",
      // The recovery surface. A failed backend leaves no error page behind: it
      // hands the player back to the menu with a banner and a released pin, so
      // both halves of that are observable state rather than an assumption.
      noticeHidden: document.getElementById("backend-notice")?.hidden ?? null,
      noticeText: document.getElementById("backend-notice")?.textContent ?? "",
      storedRenderer: (() => {
        try {
          const raw = window.localStorage.getItem("bend2craft-options");
          return raw === null ? null : (JSON.parse(raw).renderer ?? null);
        } catch {
          return null;
        }
      })(),
      query: window.location.search,
    }));
    return { state, consoleErrors, consoleWarnings, pageErrors };
  } finally {
    await page.close();
  }
}

// A real frame readback, not a pipeline check. The probe samples several
// regions of the presented swap-chain texture so a blank compositor surface or
// a cleared frame cannot pass.
async function probeRenderedFrame(renderer) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const consoleErrors = [];
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });
  try {
    await page.goto(`${baseUrl}/?test=1&play=1&renderer=${renderer}&seed=1337`, {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });
    await page.waitForFunction(
      () => window.__bend2craft?.world?.activeChunks > 0
        && window.__bend2craft?.world?.pendingChunks === 0
        && window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false,
      null,
      { timeout: 30000 },
    ).catch(() => {});
    const support = await page.evaluate(() => window.__bend2craft?.getFrameReadbackSupport?.() ?? null);
    if (support?.supported !== true) {
      return {
        probed: false,
        reason: frameReadbackReason(support),
        support,
        regions: [],
        stats: null,
        consoleErrors,
      };
    }
    // Let a few real frames land before sampling the swap chain.
    await page.evaluate(() => new Promise((resolve) => {
      let remaining = 3;
      const tick = () => (remaining-- <= 0 ? resolve() : requestAnimationFrame(tick));
      requestAnimationFrame(tick);
    }));
    const sampled = await page.evaluate(async () => {
      const canvas = document.getElementById("game");
      const width = Math.max(8, Math.min(96, Math.floor(canvas.width / 4)));
      const height = Math.max(8, Math.min(96, Math.floor(canvas.height / 4)));
      const regions = [
        { name: "horizon", x: Math.floor(canvas.width / 2) - width, y: Math.floor(canvas.height * 0.55) },
        { name: "lower-terrain", x: Math.floor(canvas.width / 2) - width, y: Math.floor(canvas.height * 0.15) },
        { name: "left-terrain", x: Math.floor(canvas.width * 0.15), y: Math.floor(canvas.height * 0.35) },
      ];
      const read = [];
      for (const region of regions) {
        const result = await window.__bend2craft.readFramePixelsAsync(
          region.x,
          region.y,
          width,
          height,
        );
        read.push({ name: region.name, ...result });
      }
      return {
        read,
        stats: window.__bend2craft.glBufferSizes?.() ?? null,
        canvas: { width: canvas.width, height: canvas.height },
      };
    });
    return {
      probed: true,
      reason: null,
      support,
      regions: sampled.read,
      stats: sampled.stats,
      canvas: sampled.canvas,
      consoleErrors,
    };
  } finally {
    await page.close();
  }
}

try {
  const supportPage = await browser.newPage();
  if (baseUrl !== null) {
    await supportPage.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 30000 });
  }
  const support = await supportPage.evaluate(async () => {
    if (navigator.gpu === undefined || typeof navigator.gpu.requestAdapter !== "function") {
      return { supported: false, adapterName: null, reason: "navigator.gpu is unavailable" };
    }
    const adapter = await navigator.gpu.requestAdapter();
    return adapter === null
      ? { supported: false, adapterName: null, reason: "no WebGPU adapter was returned" }
      : { supported: true, adapterName: adapter.name ?? null, reason: null };
  });
  await supportPage.close();

  const shaderValidation = support.supported && baseUrl !== null
    ? await (async () => {
      const page = await browser.newPage();
      try {
        await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 30000 });
        return await page.evaluate(async ({ terrainCode, skyCode, vertexLayout }) => {
          const adapter = await navigator.gpu.requestAdapter();
          if (adapter === null) return { supported: false, errors: ["no adapter"] };
          const device = await adapter.requestDevice();
          const terrainModule = device.createShaderModule({ code: terrainCode });
          const skyModule = device.createShaderModule({ code: skyCode });
          const compilations = await Promise.all([
            terrainModule.getCompilationInfo?.(),
            skyModule.getCompilationInfo?.(),
          ]);
          const errors = compilations
            .flatMap((compilation) => compilation?.messages ?? [])
            .filter((message) => message.type === "error")
            .map((message) => message.message);
          if (errors.length > 0) return { supported: true, errors };
          const bindGroupLayout = device.createBindGroupLayout({
            entries: [
              { binding: 0, visibility: 0x1 | 0x2, buffer: { type: "uniform" } },
              { binding: 1, visibility: 0x2, sampler: { type: "filtering" } },
              { binding: 2, visibility: 0x2, texture: { sampleType: "float" } },
              { binding: 3, visibility: 0x2, sampler: { type: "filtering" } },
              { binding: 4, visibility: 0x2, texture: { sampleType: "float" } },
            ],
          });
          const pipelineLayout = device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] });
          const createPipeline = device.createRenderPipelineAsync ?? device.createRenderPipeline;
          if (typeof createPipeline !== "function") {
            return { supported: true, errors: ["render pipeline creation is unavailable"] };
          }
          await createPipeline.call(device, {
            layout: pipelineLayout,
            vertex: {
              module: terrainModule,
              entryPoint: "vs_main",
              buffers: [vertexLayout],
            },
            fragment: {
              module: terrainModule,
              entryPoint: "fs_main",
              targets: [{ format: navigator.gpu.getPreferredCanvasFormat?.() ?? "bgra8unorm" }],
            },
            primitive: { topology: "triangle-list", cullMode: "none" },
            depthStencil: { format: "depth24plus", depthWriteEnabled: true, depthCompare: "less" },
          });
          await createPipeline.call(device, {
            layout: pipelineLayout,
            vertex: { module: skyModule, entryPoint: "sky_vs" },
            fragment: {
              module: skyModule,
              entryPoint: "sky_fs",
              targets: [{ format: navigator.gpu.getPreferredCanvasFormat?.() ?? "bgra8unorm" }],
            },
            primitive: { topology: "triangle-list" },
            depthStencil: { format: "depth24plus", depthWriteEnabled: false, depthCompare: "less-equal" },
          });
          return { supported: true, errors: [] };
        }, {
          terrainCode: WEBGPU_TERRAIN_SHADER,
          skyCode: WEBGPU_SKY_SHADER,
          // Serialised into the page, so the frozen object has to cross as data.
          vertexLayout: JSON.parse(JSON.stringify(TERRAIN_VERTEX_LAYOUT)),
        });
      } finally {
        await page.close();
      }
    })()
    : null;

  if (shaderValidation !== null) {
    assert.equal(shaderValidation.supported, true);
    assert.deepEqual(shaderValidation.errors, []);
  }
  if (!support.supported || baseUrl === null) {
    // No adapter at all: the gate is explicitly skipped with the reason and
    // what was and was not measured, so a skip is never read as a pass.
    console.log(JSON.stringify({
      status: "skipped",
      explicitFailure: false,
      skippedCapability: support.supported ? "no-server" : "no-adapter",
      reason: support.reason ?? "no dev server URL was provided",
      support,
      shaderValidation,
      measured: { shaderValidation: shaderValidation !== null, runtimeFrame: false, sceneProbe: false },
    }));
  } else {
    const auto = await inspectRuntime("auto");
    assert.equal(auto.state.errorHidden, true);
    assert.ok(auto.state.frame?.renderer === "webgl" || auto.state.frame?.renderer === "webgpu");
    assert.deepEqual(auto.consoleErrors, []);
    assert.deepEqual(auto.pageErrors, []);

    const explicit = await inspectRuntime("webgpu");
    if (explicit.state.frame?.renderer === "webgpu") {
      const culling = {
        residentChunks: explicit.state.gpuBuffers.residentChunks,
        visibleChunks: explicit.state.gpuBuffers.visibleChunks,
        culledChunks: explicit.state.gpuBuffers.culledChunks,
        drawCalls: explicit.state.gpuBuffers.drawCalls,
        submittedVertexBytes: explicit.state.gpuBuffers.submittedVertexBytes,
        editUploads: explicit.state.gpuBuffers.editUploads,
        resyncUploads: explicit.state.gpuBuffers.resyncUploads,
      };
      assert.equal(explicit.state.errorHidden, true);
      assert.ok(explicit.state.frame.pendingChunks === 0);
      assert.ok(explicit.state.frame.meshWorkerResponses > 0);
      assert.ok(explicit.state.gpuBuffers.chunks > 0);
      assert.equal(explicit.state.gpuBuffers.vertexStrideBytes, 52);
      assert.ok(explicit.state.gpuBuffers.terrainBufferReuses > 0);
      // Chunk culling must account for every resident chunk and must actually
      // remove something, otherwise the metrics are decorative.
      assert.equal(
        explicit.state.gpuBuffers.visibleChunks + explicit.state.gpuBuffers.culledChunks,
        explicit.state.gpuBuffers.residentChunks,
        "every resident chunk must be either submitted or culled",
      );
      assert.ok(
        explicit.state.gpuBuffers.culledChunks > 0,
        `frustum culling removed no chunks from ${explicit.state.gpuBuffers.residentChunks} resident chunks`,
      );
      assert.ok(explicit.state.gpuBuffers.visibleChunks > 0, "culling must not empty the frame");
      assert.ok(
        explicit.state.gpuBuffers.drawCalls > explicit.state.gpuBuffers.visibleChunks,
        "each visible chunk plus the sky and dynamic layers must be accounted for",
      );
      assert.ok(
        explicit.state.gpuBuffers.submittedVertexBytes
          === explicit.state.gpuBuffers.submittedVertices * 52,
        "submitted bytes must match the packed vertex stride",
      );
      assert.deepEqual(explicit.consoleErrors, []);
      assert.deepEqual(explicit.consoleWarnings.filter((message) => /webgpu|validation|gpu/i.test(message)), []);
      assert.deepEqual(explicit.pageErrors, []);

      // The frame the culler described must be the frame the GPU produced.
      // Probing the real swap chain is what separates "the pipeline compiled"
      // from "a scene is on screen".
      const readback = await probeRenderedFrame("webgpu");
      const probe = probeSceneFrame(readback.regions);
      if (!readback.probed) {
        // Presentation worked but the frame cannot be copied out, so the scene
        // probe is explicitly skipped rather than quietly reported as a pass.
        console.log(JSON.stringify({
          status: "skipped",
          explicitFailure: false,
          readbackSkipped: true,
          reason: readback.reason,
          support,
          shaderValidation,
          culling,
          auto,
          explicit,
        }));
      } else {
        assert.equal(probe.passed, true, `the presented WebGPU frame is not a scene: ${probe.reason}`);
        assert.deepEqual(readback.consoleErrors, []);
        assert.ok(readback.canvas.width > 0 && readback.canvas.height > 0);
        assert.equal(
          cullingAgreesWithProbe(readback.stats, probe),
          true,
          `the culled frame does not match the probe: ${JSON.stringify(readback.stats)}`,
        );
        console.log(JSON.stringify({
          status: "runtime-passed",
          visibleReadback: true,
          support,
          shaderValidation,
          culling,
          sceneProbe: {
            passed: probe.passed,
            regions: probe.regions.map((region, index) => ({
              name: readback.regions[index]?.name ?? `region-${index}`,
              distinctColors: region.distinctColors,
              brightPixels: region.brightPixels,
              meanLuma: Number(region.meanLuma.toFixed(2)),
              lumaSpread: region.lumaSpread,
              pixels: region.pixels,
            })),
          },
          auto,
          explicit,
        }));
      }
    } else {
      // The recovery contract, not the old dead-page contract. A backend that
      // cannot start must leave the player somewhere they can pick another one:
      // no error screen, a banner on the menu that names the backend and the
      // reason, and the stored pin released so the next launch does not walk
      // into the same wall and bounce between the world and the menu.
      assert.equal(explicit.state.errorHidden, true,
        "a failed backend must not leave the player on an error page");
      assert.equal(explicit.state.noticeHidden, false,
        "a failed backend must return the player to the menu with a banner");
      const notice = explicit.state.noticeText ?? "";
      assert.match(notice, /webgpu/i,
        `the banner must name the backend that failed, got: ${notice}`);
      assert.match(notice, /reason/i,
        `the banner must carry a reason, got: ${notice}`);
      // The reason has to be a real diagnostic. Reading it out of the banner is
      // what makes this meaningful: the old check read it from the error page,
      // which no longer exists, and fell through to a fallback string that its
      // own regex then matched - so it passed with nothing to report.
      const reason = notice.replace(/^.*?Reason:\s*/is, "").trim();
      assert.ok(reason.length > 0 && !/^could not start/i.test(reason),
        `the banner must carry the backend's own reason, got: ${reason}`);
      assert.match(reason, /unavailable|presentation|adapter|probe|fallback/i,
        `unexpected explicit WebGPU startup result: ${reason}`);
      assert.equal(explicit.state.storedRenderer, "auto",
        "a failed backend must release the stored renderer pin, or the next launch repeats the failure");
      assert.match(explicit.state.query ?? "", /renderer-fallback=1/,
        "the recovery has to route through the fallback marker so the menu knows this is not a cold start");
      assert.equal(explicit.state.frame, null,
        "a failed backend must not leave a half-started world behind");
      // Observability used to mean "an unhandled page error fired", because the
      // failure surfaced as a dead error page. The recovery is now a handled
      // path, so demanding a thrown exception asserts a crash - the opposite of
      // what this flow promises. The failure is reported through the banner and
      // the released pin, both asserted above; what is left to prove is that the
      // hand-back happened without anything blowing up on the way.
      assert.deepEqual(explicit.pageErrors, [],
        `the fallback must hand the player back without an unhandled error, got: ${explicit.pageErrors.join(" | ")}`);
      // A fallback must be marked skipped with a diagnostic that names the
      // capability, the browser's own verdict, and the backend actually used.
      console.log(JSON.stringify({
        status: "skipped",
        explicitFailure: true,
        skippedCapability: "webgpu-presentation",
        reason,
        notice,
        storedRenderer: explicit.state.storedRenderer,
        support,
        shaderValidation,
        fallback: {
          requestedRenderer: "webgpu",
          actualRenderer: auto.state.frame?.renderer ?? null,
          actualRendererName: auto.state.frame?.rendererName ?? null,
          autoModeReason: auto.state.frame?.webgpu?.reason ?? null,
        },
        auto,
        explicit,
      }));
    }
  }
} finally {
  await browser.close();
}
