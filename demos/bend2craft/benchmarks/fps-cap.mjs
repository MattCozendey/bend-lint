// Frame pacing benchmark: measures what a frame rate cap actually does, and
// proves the adaptive quality ladder follows the frame period it is given.
//
// Why this exists separately from renderer-benchmark.mjs: that one forces
// `--use-angle=swiftshader`, so it measures a software rasteriser and cannot say
// anything about a real GPU or a real display. This one asks for the platform's
// own backend (`--use-angle=metal`) and drives the game through the paces.
//
// Two things are measured, and they answer different questions:
//
//   1. The cap. `drawnFps` counts frames the game actually drew, differenced from
//      the frame counter the loop advances. Counting our own animation-frame
//      callbacks instead would be measuring the compositor, which keeps ticking
//      at the display cadence whether or not the game draws inside them - so a
//      fully capped game still reports 60 Hz that way.
//
//   2. The ladder. The tier settles wherever the frame budget puts it, so the
//      target-to-tier mapping is the evidence that a cadence-aware controller
//      responds to the display instead of parking in a dead band.
//
// The assertions are the point: this is a regression gate, not just a report.
// Run it with a dev server already up, or via `npm run bench:fps-cap`.
import { chromium } from "playwright";

const baseUrl = process.argv[2] ?? "http://127.0.0.1:3000";
const durationMs = Math.max(1500, Number(process.argv[3] ?? 4000));
const width = Number(process.env.VIEWPORT_W ?? 1512);
const height = Number(process.env.VIEWPORT_H ?? 945);
// Retina by default: the costs that matter are per-pixel, and at dpr 1 the whole
// scene fits inside a 120 Hz frame budget, which hides every effect being measured.
const deviceScaleFactor = Number(process.env.DSF ?? 2);
const renderDistance = Number(process.env.RENDER_DISTANCE ?? 4);
const limits = (process.env.FPS_LIMITS ?? "0,30,60,120").split(",").map((value) => Number(value.trim()));
// Pinning a tier turns the ladder off, which is how the per-tier cost table in
// DESIGN.md was measured: `QUALITY=low npm run bench:fps-cap` reports what one
// tier costs at this resolution, independent of where the ladder would settle.
const pinnedQuality = process.env.QUALITY ?? null;

/** Frames the game actually drew over a window, which is what a cap governs. */
const drawnFrameProbe = (duration) => new Promise((done) => {
  const first = window.__bend2craft.getFrameDiagnostics().frameCount;
  const startedAt = performance.now();
  setTimeout(() => {
    const last = window.__bend2craft.getFrameDiagnostics().frameCount;
    const elapsed = performance.now() - startedAt;
    done({ drawn: last - first, elapsedMs: elapsed, drawnFps: (last - first) / (elapsed / 1000) });
  }, duration);
});

const TIER_ORDER = Object.freeze({ minimal: 0, low: 1, medium: 2, high: 3, ultra: 4 });

const browser = await chromium.launch({
  headless: true,
  args: [
    "--enable-unsafe-webgpu",
    // The platform backend, not the software rasteriser. Headless keeps the
    // measurement non-interactive, and this flag is what makes it honest.
    "--use-angle=metal",
    "--ignore-gpu-blocklist",
    "--enable-gpu",
  ],
});

const rows = [];
const failures = [];

try {
  for (const limit of limits) {
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor });
    const page = await context.newPage();
    const pageErrors = [];
    page.on("pageerror", (error) => pageErrors.push(String(error)));
    try {
      await page.addInitScript(({ value, quality }) => {
        window.localStorage.setItem("bend2craft-options", JSON.stringify({
          fov: 75,
          sensitivity: 1,
          showCoords: true,
          renderDistance: Number(new URLSearchParams(location.search).get("rd") ?? 4),
          lodDistance: 512,
          renderer: "webgl",
          graphicsQuality: quality,
          fpsLimit: value,
        }));
      }, { value: limit, quality: pinnedQuality ?? "auto" });
      await page.goto(`${baseUrl}/?play=1&seed=1337&rd=${renderDistance}`, {
        waitUntil: "networkidle",
        timeout: 60000,
      });
      const startupError = await page.evaluate(() => {
        const error = document.getElementById("error");
        return error !== null && error.hidden === false ? error.textContent : null;
      });
      if (startupError !== null) throw new Error(startupError);
      await page.waitForFunction(
        () => window.__bend2craft?.getFrameDiagnostics?.().meshRebuildPending === false,
        null,
        { timeout: 60000 },
      );
      // Let the ladder settle. Sampling during the walk down would report a tier
      // the controller is still leaving, and a frame rate it has not committed to.
      await page.waitForTimeout(3000);

      const drawn = await page.evaluate(drawnFrameProbe, durationMs);
      const state = await page.evaluate(() => {
        const presentation = window.__bend2craft.presentation;
        const diagnostics = window.__bend2craft.getFrameDiagnostics();
        return {
          appliedLimit: presentation.fpsLimit,
          budgetMs: Number(presentation.frameBudgetMs.toFixed(2)),
          ceilingMs: presentation.displayCeilingMs === null
            ? null
            : Number(presentation.displayCeilingMs.toFixed(2)),
          tier: presentation.visualQualityName,
          smoothedFrameMs: Number(presentation.smoothedFrameMs.toFixed(2)),
          renderer: diagnostics.rendererName,
          terrainQuads: diagnostics.terrainQuads,
        };
      });

      const row = {
        storedLimit: limit,
        drawnFps: Number(drawn.drawnFps.toFixed(1)),
        drawnFrames: drawn.drawn,
        windowMs: Number(drawn.elapsedMs.toFixed(0)),
        ...state,
        pageErrors: pageErrors.length,
      };
      rows.push(row);
      console.error(
        `[fps-cap] limit=${limit} drawn=${row.drawnFps}fps `
        + `(${drawn.drawn}/${drawn.elapsedMs.toFixed(0)}ms) budget=${state.budgetMs}ms `
        + `cadence=${state.ceilingMs}ms tier=${state.tier}`,
      );

      if (state.appliedLimit !== limit) {
        failures.push(`stored cap ${limit} was not applied (runtime has ${state.appliedLimit})`);
      }
      if (pageErrors.length > 0) failures.push(`cap ${limit} reported ${pageErrors.length} page errors`);

      if (limit > 0) {
        if (row.drawnFps > limit * 1.1) failures.push(`cap ${limit} exceeded: drew ${row.drawnFps} fps`);
        // A cap the display can actually reach must also be reached, or it is
        // throttling the game rather than bounding it.
        const cadenceFps = state.ceilingMs === null ? Infinity : 1000 / state.ceilingMs;
        if (limit <= cadenceFps && row.drawnFps < limit * 0.85) {
          failures.push(`cap ${limit} starved the frame rate: drew ${row.drawnFps} fps`);
        }
        const expectedBudget = 1000 / limit;
        if (Math.abs(state.budgetMs - expectedBudget) > 0.01) {
          failures.push(
            `cap ${limit} did not become the frame budget `
            + `(got ${state.budgetMs}ms, want ${expectedBudget.toFixed(2)}ms)`,
          );
        }
      } else {
        if (state.ceilingMs === null) failures.push("uncapped run never learned a display cadence");
        if (state.budgetMs > 20) {
          failures.push(`uncapped budget ${state.budgetMs}ms is not tracking the display cadence`);
        }
      }
    } catch (error) {
      failures.push(`cap ${limit} failed: ${error instanceof Error ? error.message : String(error)}`);
      console.error(`[fps-cap] limit=${limit} ERROR ${error}`);
    } finally {
      await context.close();
    }
  }

  // A cap is a ceiling and never a floor: one above the cadence the compositor
  // grants must leave the drawn rate alone rather than invent frame drops.
  const uncapped = rows.find((row) => row.storedLimit === 0);
  const overCadence = limits
    .filter((limit) => {
      const row = rows.find((entry) => entry.storedLimit === limit);
      return row !== undefined && row.ceilingMs !== null && limit > 1000 / row.ceilingMs;
    })
    .map((limit) => rows.find((row) => row.storedLimit === limit));
  for (const row of overCadence) {
    if (uncapped !== undefined && uncapped.drawnFps - row.drawnFps > uncapped.drawnFps * 0.1) {
      failures.push(
        `a cap above the display cadence dropped the drawn rate: `
        + `${uncapped.drawnFps} -> ${row.drawnFps} fps`,
      );
    }
  }

  // The ladder must follow the budget: a looser frame period has to buy a richer
  // tier, and a tighter one must not. This is the regression the cadence-aware
  // budget exists to catch - a controller judging frame times against a fixed
  // assumption sits at `medium` on a fast panel while `low` is available. It only
  // means anything with adaptation on, so a pinned tier skips it.
  if (pinnedQuality === null) {
    const ordered = [...rows]
      .filter((row) => row.storedLimit > 0)
      .sort((a, b) => a.budgetMs - b.budgetMs);
    for (let index = 1; index < ordered.length; index += 1) {
      const tighter = ordered[index - 1];
      const looser = ordered[index];
      if (TIER_ORDER[looser.tier] < TIER_ORDER[tighter.tier]) {
        failures.push(
          `a looser target must not lower the tier: budget ${tighter.budgetMs}ms gave `
          + `${tighter.tier}, budget ${looser.budgetMs}ms gave ${looser.tier}`,
        );
      }
    }
  }
} finally {
  await browser.close();
}

console.log(JSON.stringify({
  renderer: rows[0]?.renderer ?? null,
  viewport: { width, height, deviceScaleFactor },
  renderDistance,
  pinnedQuality,
  rows,
  failures,
}, null, 2));

if (failures.length > 0) {
  console.error(`\n${failures.length} failure(s):\n${failures.map((f) => ` - ${f}`).join("\n")}`);
  process.exit(1);
}
console.error("\nframe pacing ok");
