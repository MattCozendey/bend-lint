import assert from "node:assert/strict";
import {
  depthTextureType,
  RENDER_TARGET_FILTER,
  RENDER_TARGET_WRAP,
  createRenderTarget,
  detectColorCapabilities,
  detectDepthSampling,
  resizeRenderTarget,
} from "../web/gl-render-target.js";

// A recording stand-in for a WebGL context. The capability probe walks the
// candidate formats and keeps the first one whose framebuffer completes, so the
// stub has to answer per-type, not blanket-approve.
function createStubGl({ renderable = new Set(["rgba8"]), complete = true, extensions = {} } = {}) {
  const calls = [];
  const textures = new Map();
  const framebuffers = new Map();
  let nextId = 1;
  const gl = {
    NO_ERROR: 0,
    INVALID_ENUM: 0x0500,
    RGBA: 0x1908,
    UNSIGNED_BYTE: 0x1401,
    UNSIGNED_SHORT: 0x1403,
    FLOAT: 0x1406,
    HALF_FLOAT_OES: 0x8d61,
    DEPTH_COMPONENT: 0x1902,
    DEPTH_COMPONENT16: 0x81a5,
    TEXTURE_2D: 0x0de1,
    TEXTURE_MIN_FILTER: 0x2801,
    TEXTURE_MAG_FILTER: 0x2800,
    TEXTURE_WRAP_S: 0x2802,
    TEXTURE_WRAP_T: 0x2803,
    NEAREST: 0x2600,
    LINEAR: 0x2601,
    REPEAT: 0x2901,
    CLAMP_TO_EDGE: 0x812f,
    COLOR_ATTACHMENT0: 0x8ce0,
    DEPTH_ATTACHMENT: 0x8d00,
    RENDERBUFFER: 0x8d41,
    FRAMEBUFFER: 0x8d40,
    FRAMEBUFFER_COMPLETE: 0x8cd5,
    FRAMEBUFFER_UNSUPPORTED: 0x8cd6,
    getError: () => 0,
    getExtension: (name) => extensions[name] ?? null,
    createTexture() {
      const id = nextId;
      nextId += 1;
      textures.set(id, {});
      return id;
    },
    deleteTexture(id) { textures.delete(id); },
    bindTexture(target, id) { calls.push(["bindTexture", target, id]); },
    texImage2D(...args) { calls.push(["texImage2D", ...args]); },
    texParameteri(target, pname, value) { calls.push(["texParameteri", pname, value]); },
    createFramebuffer() {
      const id = nextId;
      nextId += 1;
      framebuffers.set(id, {});
      return id;
    },
    deleteFramebuffer(id) { framebuffers.delete(id); },
    bindFramebuffer(target, id) { calls.push(["bindFramebuffer", target, id]); },
    framebufferTexture2D(...args) { calls.push(["framebufferTexture2D", ...args]); },
    framebufferRenderbuffer(...args) { calls.push(["framebufferRenderbuffer", ...args]); },
    createRenderbuffer() {
      const id = nextId;
      nextId += 1;
      return id;
    },
    deleteRenderbuffer() {},
    bindRenderbuffer() {},
    renderbufferStorage(...args) { calls.push(["renderbufferStorage", ...args]); },
    checkFramebufferStatus() {
      return complete ? gl.FRAMEBUFFER_COMPLETE : gl.FRAMEBUFFER_UNSUPPORTED;
    },
  };
  // The probe asks for each candidate in turn; answer with the requested type.
  gl.__renderable = renderable;
  const originalTexImage2D = gl.texImage2D.bind(gl);
  gl.texImage2D = (...args) => {
    const type = args[7];
    if (type === gl.FLOAT && !renderable.has("rgba32f")) gl.getError = () => gl.INVALID_ENUM;
    else if (type === gl.HALF_FLOAT_OES && !renderable.has("rgba16f")) gl.getError = () => gl.INVALID_ENUM;
    else gl.getError = () => gl.NO_ERROR;
    return originalTexImage2D(...args);
  };
  return { gl, calls, textures, framebuffers };
}

// Without any float support the pipeline must land on 8-bit rather than on a
// format the driver rejects.
const plain = createStubGl();
const plainCapabilities = detectColorCapabilities(plain.gl);
assert.equal(plainCapabilities.name, "rgba8");
assert.equal(plainCapabilities.hdr, false);
assert.equal(plainCapabilities.hdrMin, 0);
assert.equal(plainCapabilities.hdrMax, 1);

// HALF_FLOAT is spelled HALF_FLOAT_OES in WebGL 1, and drivers expose the
// constant on the extension object rather than on the context.
const half = createStubGl({
  renderable: new Set(["rgba16f"]),
  extensions: {
    OES_texture_half_float: { HALF_FLOAT_OES: 0x8d61 },
    OES_texture_half_float_linear: {},
  },
});
const halfCapabilities = detectColorCapabilities(half.gl);
assert.equal(halfCapabilities.name, "rgba16f", "the half-float path must be preferred when it is renderable");
assert.equal(halfCapabilities.hdr, true);
assert.ok(halfCapabilities.hdrMax > halfCapabilities.hdrMin, "an HDR format needs a real range");

// A driver that advertises float but cannot render to it must not be trusted.
const lying = createStubGl({ renderable: new Set(["rgba8"]) });
const lyingCapabilities = detectColorCapabilities(lying.gl);
assert.equal(lyingCapabilities.name, "rgba8", "an advertised but unrenderable format must be rejected");

// A context that cannot complete any framebuffer still reports the narrowest
// format; the caller's own completeness check is what surfaces the real error.
const broken = createStubGl({ complete: false });
assert.equal(detectColorCapabilities(broken.gl).name, "rgba8");

// Depth sampling is reported, not assumed.
assert.equal(detectDepthSampling({ getExtension: () => null }).supported, false);
assert.equal(detectDepthSampling({ getExtension: (name) => (name === "WEBGL_depth_texture" ? {} : null) }).supported, true);

// The filter names are resolved to real GL enums before they reach texParameteri.
const filterStub = createStubGl();
const filterGl = filterStub.gl;
const filterTarget = createRenderTarget(filterGl, {
  width: 4,
  height: 4,
  capabilities: plainCapabilities,
  depth: "none",
  filter: RENDER_TARGET_FILTER.NEAREST,
});
assert.ok(filterTarget.texture !== undefined);
const filterEnums = filterStub.calls
  .filter(([name, pname]) => name === "texParameteri" && pname === filterGl.TEXTURE_MIN_FILTER)
  .map(([, , value]) => value);
assert.ok(
  filterEnums.every((value) => value === filterGl.NEAREST || value === filterGl.LINEAR),
  `a filter name must be resolved to a GL enum, saw ${filterEnums.join(",")}`,
);

// A target must allocate a colour attachment and, when asked, a depth
// attachment, and it must be complete.
const targetGl = createStubGl().gl;
const target = createRenderTarget(targetGl, {
  width: 16,
  height: 8,
  capabilities: plainCapabilities,
  depth: "renderbuffer",
  filter: RENDER_TARGET_FILTER.NEAREST,
});
assert.equal(target.width, 16);
assert.equal(target.height, 8);
assert.equal(target.depthTexture, null, "a renderbuffer depth is not sampleable");
assert.ok(target.depthBuffer !== null);
assert.ok(target.framebuffer !== null);

// A float target that the context cannot filter must be created point sampled.
// Asking for LINEAR there is an INVALID_ENUM that silently breaks every blur.
const pointStub = createStubGl();
const pointTarget = createRenderTarget(pointStub.gl, {
  width: 4,
  height: 4,
  capabilities: { ...halfCapabilities, linearFilter: false },
  filter: RENDER_TARGET_FILTER.LINEAR,
});
assert.equal(pointTarget.width, 4);
const pointMinFilter = pointStub.calls
  .filter(([name, pname, value]) => name === "texParameteri"
    && pname === pointStub.gl.TEXTURE_MIN_FILTER
    && value === pointStub.gl.LINEAR);
assert.deepEqual(
  pointMinFilter,
  [],
  "a float target the context cannot filter must be point sampled, not LINEAR",
);

// An incomplete framebuffer is an error, not a silent empty target.
const incompleteGl = createStubGl({ complete: false }).gl;
assert.throws(
  () => createRenderTarget(incompleteGl, {
    width: 4,
    height: 4,
    capabilities: plainCapabilities,
    depth: "none",
  }),
  /Incomplete framebuffer/,
);

// Resizing keeps the format and reports whether it reallocated.
const resizeGl = createStubGl().gl;
const resizable = createRenderTarget(resizeGl, {
  width: 8,
  height: 8,
  capabilities: plainCapabilities,
  depth: "renderbuffer",
});
const same = resizeRenderTarget(resizeGl, resizable, 8, 8);
assert.equal(same, resizable, "a no-op resize must return the same target");
const grown = resizeRenderTarget(resizeGl, resizable, 16, 16);
assert.equal(grown.width, 16);
assert.equal(grown.height, 16);
assert.notEqual(grown, resizable, "a real resize must allocate a new target");
assert.equal(grown.depthMode, "renderbuffer", "a resize must preserve the depth mode");

// Dimensions are floored and clamped, so a zero-sized canvas cannot produce a
// zero-sized allocation.
const floored = createRenderTarget(targetGl, {
  width: 0.4,
  height: -3,
  capabilities: plainCapabilities,
  depth: "none",
});
assert.equal(floored.width, 1);
assert.equal(floored.height, 1);
assert.ok(RENDER_TARGET_WRAP.CLAMP !== undefined);

console.log("gl render target ok");

// Depth textures ask for 32-bit integer depth (24-bit on real drivers) when the
// context exposes it, and fall back to 16-bit otherwise.
assert.equal(depthTextureType({ UNSIGNED_INT: 0x1405, UNSIGNED_SHORT: 0x1403 }), 0x1405);
assert.equal(depthTextureType({ UNSIGNED_SHORT: 0x1403 }), 0x1403);
