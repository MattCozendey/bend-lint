function finite(value, fallback = 0) {
  return Number.isFinite(Number(value)) ? Number(value) : fallback;
}

export const FRAME_SAMPLE_CAPACITY = 240;

export function createFrameMetrics() {
  return {
    fps: 0,
    frameMs: 0,
    frameCount: 0,
    minFps: Infinity,
    maxFps: 0,
    frameTimes: new Float32Array(FRAME_SAMPLE_CAPACITY),
    frameTimeCount: 0,
    frameTimeIndex: 0,
  };
}

/** Update a smoothed frame-time sample without touching browser state. */
export function sampleFrame(metrics, elapsedMs) {
  const frameMs = Math.max(0.1, finite(elapsedMs, 0.1));
  const instantFps = Math.min(240, 1000 / frameMs);
  const fps = metrics.frameCount === 0
    ? instantFps
    : metrics.fps * 0.9 + instantFps * 0.1;
  const frameTimes = metrics.frameTimes ?? new Float32Array(FRAME_SAMPLE_CAPACITY);
  const frameTimeIndex = metrics.frameTimeIndex ?? 0;
  frameTimes[frameTimeIndex] = frameMs;
  return {
    ...metrics,
    fps,
    frameMs,
    frameCount: metrics.frameCount + 1,
    minFps: Math.min(metrics.minFps, instantFps),
    maxFps: Math.max(metrics.maxFps, instantFps),
    frameTimes,
    frameTimeCount: Math.min(FRAME_SAMPLE_CAPACITY, (metrics.frameTimeCount ?? 0) + 1),
    frameTimeIndex: (frameTimeIndex + 1) % FRAME_SAMPLE_CAPACITY,
  };
}

function nearestRank(values, fraction) {
  if (values.length === 0) return 0;
  const rank = Math.max(0, Math.min(values.length - 1, Math.ceil(values.length * fraction) - 1));
  return values[rank];
}

export function framePercentiles(metrics) {
  const count = Math.min(FRAME_SAMPLE_CAPACITY, Number(metrics?.frameTimeCount ?? 0));
  if (count === 0) return { p50FrameMs: 0, p95FrameMs: 0, p99FrameMs: 0 };
  const values = Array.from(metrics.frameTimes.slice(0, count)).sort((a, b) => a - b);
  return {
    p50FrameMs: nearestRank(values, 0.5),
    p95FrameMs: nearestRank(values, 0.95),
    p99FrameMs: nearestRank(values, 0.99),
  };
}

export function formatDebugText(snapshot) {
  const player = snapshot.player ?? {};
  const minFps = Number.isFinite(Number(snapshot.minFps)) ? Number(snapshot.minFps) : 0;
  const maxFps = Number.isFinite(Number(snapshot.maxFps)) ? Number(snapshot.maxFps) : 0;
  const p95FrameMs = finite(snapshot.p95FrameMs);
  const p99FrameMs = finite(snapshot.p99FrameMs);
  const percentileText = p95FrameMs > 0
    ? ` · p95 ${p95FrameMs.toFixed(1)} ms · p99 ${p99FrameMs.toFixed(1)} ms`
    : "";
  // The active cap sits next to the measured rate because the two have to be read
  // together: a rate sitting below the cap is the renderer, and a rate at it is
  // the cap. Reporting one without the other cannot tell those apart. A cap that
  // is set is never reported as uncapped, even before a budget has been measured.
  const cap = finite(snapshot.fpsLimit);
  const budget = finite(snapshot.frameBudgetMs);
  const capText = cap <= 0
    ? " · uncapped"
    : budget > 0
      ? ` · cap ${Math.trunc(cap)} (${budget.toFixed(1)} ms)`
      : ` · cap ${Math.trunc(cap)}`;
  return [
    `FPS ${finite(snapshot.fps).toFixed(0)} · ${finite(snapshot.frameMs).toFixed(1)} ms${percentileText}${capText} · min ${minFps.toFixed(0)} · max ${maxFps.toFixed(0)} · frames ${Math.trunc(finite(snapshot.frameCount))}`,
    `XYZ ${finite(player.x).toFixed(2)} ${finite(player.y).toFixed(2)} ${finite(player.z).toFixed(2)}`,
    `chunks ${Math.trunc(finite(snapshot.activeChunks))} active · ${Math.trunc(finite(snapshot.pendingChunks))} pending · ${Math.trunc(finite(snapshot.pinnedChunks))} pinned`,
    `mesh ${Math.trunc(finite(snapshot.blockCount)).toLocaleString("en-US")} blocks · ${Math.trunc(finite(snapshot.terrainQuads)).toLocaleString("en-US")} terrain quads · ${Math.trunc(finite(snapshot.waterQuads)).toLocaleString("en-US")} water quads · ${Math.trunc(finite(snapshot.dynamicQuads)).toLocaleString("en-US")} dynamic quads · ${Math.trunc(finite(snapshot.shadowQuads))} shadow quads · ${Math.trunc(finite(snapshot.meshRebuilds))} rebuilds`,
    `workers ${Math.trunc(finite(snapshot.workerRequests))} requests · ${Math.trunc(finite(snapshot.workerHydrates))} hydrated · ${Math.trunc(finite(snapshot.workerRejects))} rejects · sim ${finite(snapshot.simulationTime).toFixed(1)}`,
    `entities ${Math.trunc(finite(snapshot.mobs))} mobs · ${Math.trunc(finite(snapshot.villagers))} villagers · ${Math.trunc(finite(snapshot.drops))} drops`,
  ].join("\n");
}
