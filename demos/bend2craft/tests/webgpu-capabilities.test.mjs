import assert from "node:assert/strict";
import {
  RENDERER_MODES,
  chooseRenderer,
  describeBrowserExecution,
  normalizeRendererMode,
  probeWebGpu,
  withTimeout,
} from "../web/webgpu-capabilities.js";

assert.equal(normalizeRendererMode("webgpu"), RENDERER_MODES.WEBGPU);
assert.equal(normalizeRendererMode("webgl"), RENDERER_MODES.WEBGL);
assert.equal(normalizeRendererMode("unknown"), RENDERER_MODES.AUTO);

assert.equal(chooseRenderer({ requested: "auto", webgpu: { supported: true } }), "webgpu");
assert.equal(chooseRenderer({ requested: "auto", webgpu: { supported: false } }), "webgl");
assert.equal(chooseRenderer({ requested: "webgl", webgpu: { supported: true } }), "webgl");
assert.throws(
  () => chooseRenderer({ requested: "webgpu", webgpu: { supported: false } }),
  /WebGPU was requested but is unavailable/,
);

assert.deepEqual(describeBrowserExecution(), {
  target: "browser-javascript",
  bendParallel: false,
  bendGpu: false,
  note: "Bend 2 JavaScript evaluation is sequential; WebGPU accelerates presentation only.",
});

const adapter = await probeWebGpu({
  gpu: {
    async requestAdapter() {
      return { name: "test-adapter" };
    },
  },
});
assert.deepEqual(adapter, { supported: true, adapterName: "test-adapter", reason: null });
assert.deepEqual(await probeWebGpu({}), {
  supported: false,
  adapterName: null,
  reason: "navigator.gpu is unavailable",
});
assert.deepEqual(await probeWebGpu({ gpu: { async requestAdapter() { return null; } } }), {
  supported: false,
  adapterName: null,
  reason: "no WebGPU adapter was returned",
});
assert.equal(await withTimeout(Promise.resolve("ready"), 50, "late"), "ready");
await assert.rejects(
  withTimeout(new Promise(() => {}), 5, "probe timed out"),
  /probe timed out/,
);

console.log("webgpu capabilities ok");
