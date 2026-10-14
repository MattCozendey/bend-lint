export function withTimeout(promise, timeoutMs, message) {
  let timer = null;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), timeoutMs);
  });
  return Promise.race([Promise.resolve(promise), timeout]).finally(() => {
    if (timer !== null) clearTimeout(timer);
  });
}

const WEBGPU_PROBE_TIMEOUT_MS = 2000;

export const RENDERER_MODES = Object.freeze({
  AUTO: "auto",
  WEBGPU: "webgpu",
  WEBGL: "webgl",
});

export function normalizeRendererMode(value) {
  return Object.values(RENDERER_MODES).includes(value) ? value : RENDERER_MODES.AUTO;
}

export function chooseRenderer({ requested = RENDERER_MODES.AUTO, webgpu = { supported: false } } = {}) {
  const mode = normalizeRendererMode(requested);
  if (mode === RENDERER_MODES.WEBGL) return RENDERER_MODES.WEBGL;
  if (mode === RENDERER_MODES.WEBGPU) {
    if (!webgpu.supported) throw new Error("WebGPU was requested but is unavailable.");
    return RENDERER_MODES.WEBGPU;
  }
  return webgpu.supported ? RENDERER_MODES.WEBGPU : RENDERER_MODES.WEBGL;
}

export function describeBrowserExecution() {
  return {
    target: "browser-javascript",
    bendParallel: false,
    bendGpu: false,
    note: "Bend 2 JavaScript evaluation is sequential; WebGPU accelerates presentation only.",
  };
}

async function probePresentation(canvas, gpu, adapter) {
  if (canvas === null || typeof globalThis.createImageBitmap !== "function" || typeof document === "undefined") {
    return null;
  }
  const target = document.createElement("canvas");
  target.width = Math.max(1, Math.min(64, canvas.width || 64));
  target.height = Math.max(1, Math.min(64, canvas.height || 64));
  const device = await adapter.requestDevice();
  const context = target.getContext("webgpu");
  if (context === null) return "WebGPU canvas context is unavailable";
  const format = gpu.getPreferredCanvasFormat?.() ?? "bgra8unorm";
  context.configure({ device, format, alphaMode: "opaque" });
  const encoder = device.createCommandEncoder();
  const pass = encoder.beginRenderPass({
    colorAttachments: [{
      view: context.getCurrentTexture().createView(),
      clearValue: { r: 1, g: 0, b: 0, a: 1 },
      loadOp: "clear",
      storeOp: "store",
    }],
  });
  pass.end();
  device.queue.submit([encoder.finish()]);
  await new Promise((resolve) => requestAnimationFrame(resolve));
  const bitmap = await createImageBitmap(target);
  const probe = document.createElement("canvas");
  probe.width = 1;
  probe.height = 1;
  const context2d = probe.getContext("2d", { willReadFrequently: true });
  context2d.drawImage(bitmap, 0, 0, 1, 1);
  bitmap.close();
  const pixel = context2d.getImageData(0, 0, 1, 1).data;
  return pixel[0] > 180 && pixel[1] < 100 && pixel[2] < 100 && pixel[3] > 180
    ? null
    : "WebGPU presentation is unavailable; refusing a blank canvas";
}

export async function probeWebGpu(navigatorLike = globalThis.navigator, canvas = null) {
  const gpu = navigatorLike?.gpu;
  if (gpu === undefined || typeof gpu.requestAdapter !== "function") {
    return { supported: false, adapterName: null, reason: "navigator.gpu is unavailable" };
  }
  try {
    const adapter = await withTimeout(
      gpu.requestAdapter(),
      WEBGPU_PROBE_TIMEOUT_MS,
      "WebGPU adapter probe timed out.",
    );
    if (adapter === null) {
      return { supported: false, adapterName: null, reason: "no WebGPU adapter was returned" };
    }
    const presentationError = await withTimeout(
      probePresentation(canvas, gpu, adapter),
      WEBGPU_PROBE_TIMEOUT_MS,
      "WebGPU presentation probe timed out.",
    );
    return {
      supported: presentationError === null,
      adapterName: adapter.name ?? null,
      reason: presentationError,
    };
  } catch (error) {
    return {
      supported: false,
      adapterName: null,
      reason: error instanceof Error ? error.message : String(error),
    };
  }
}
