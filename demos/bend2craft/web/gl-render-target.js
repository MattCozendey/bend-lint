// Offscreen render targets for the WebGL 1 presentation pipeline.
//
// WebGL 1 has no renderbuffers-with-texture-storage and no float render target
// by default, so every capability is probed once and the result is reused for
// the life of the context. The pipeline degrades in a fixed order:
//   HDR float colour -> 8-bit colour -> direct-to-default-framebuffer.
// Depth is a sampleable texture when WEBGL_depth_texture is present, which is
// what the shadow pass and the god-ray mask read; without it the caller falls
// back to a depth renderbuffer and disables the passes that need to read it.

export const RENDER_TARGET_FILTER = Object.freeze({
  NEAREST: "nearest",
  LINEAR: "linear",
});

export const RENDER_TARGET_WRAP = Object.freeze({
  CLAMP: "clamp",
  REPEAT: "repeat",
});

function glFilter(gl, name) {
  return name === RENDER_TARGET_FILTER.NEAREST ? gl.NEAREST : gl.LINEAR;
}

/**
 * Pick the best colour format this context can actually render into.
 *
 * Rather than trusting the extension strings, each candidate is trialled against
 * a throwaway framebuffer: a driver can advertise WEBGL_color_buffer_float and
 * still reject the type the platform actually exposes, and failing to allocate
 * at boot is far worse than a slightly narrower format.
 */
export function detectColorCapabilities(gl) {
  const halfFloatLinear = gl.getExtension("OES_texture_half_float_linear");
  const halfFloat = gl.getExtension("OES_texture_half_float");
  const colorBufferFloat = gl.getExtension("WEBGL_color_buffer_float");
  const floatLinear = gl.getExtension("OES_texture_float_linear");

  const candidates = [];
  // HALF_FLOAT is spelled HALF_FLOAT_OES in WebGL 1, and drivers expose the
  // constant on the extension object rather than on the context, so read it from
  // there. 0x8D61 is the value the extension defines.
  const halfFloatType = halfFloat?.HALF_FLOAT_OES ?? 0x8d61;
  if (halfFloat && halfFloatLinear && typeof halfFloatType === "number") {
    candidates.push({
      name: "rgba16f",
      internalFormat: gl.RGBA,
      type: halfFloatType,
      linearFilter: true,
      hdr: true,
      hdrMin: 0.0001,
      hdrMax: 56000,
    });
  }
  if (colorBufferFloat) {
    candidates.push({
      name: floatLinear ? "rgba32f" : "rgba32f-point",
      internalFormat: gl.RGBA,
      type: gl.FLOAT,
      // Without OES_texture_float_linear a float target must be point sampled;
      // the blur stages read a single tap, so the loss is a slightly harsher
      // bloom edge, which is far better than an unfilterable texture.
      linearFilter: Boolean(floatLinear),
      hdr: true,
      hdrMin: 0.0001,
      hdrMax: 3000,
    });
  }
  candidates.push({
    name: "rgba8",
    internalFormat: gl.RGBA,
    type: gl.UNSIGNED_BYTE,
    linearFilter: true,
    hdr: false,
    hdrMin: 0,
    hdrMax: 1,
  });

  const trials = [];
  // Some drivers only honour a float colour attachment once the context has
  // already created one: the very first RGBA32F texImage2D raises INVALID_ENUM
  // and reports an incomplete framebuffer, while the identical call a moment
  // later succeeds. So every HDR candidate is trialled for a full second pass
  // before the pipeline is allowed to settle for 8-bit, which costs two 4x4
  // textures per candidate at boot.
  const hdrCandidates = candidates.filter((candidate) => candidate.hdr);
  for (let pass = 0; pass < 2; pass += 1) {
    for (const candidate of hdrCandidates) {
      const accepted = probeColorTarget(gl, candidate);
      trials.push({ name: candidate.name, pass, accepted });
      if (accepted) {
        candidate.trials = trials;
        return candidate;
      }
    }
  }
  // The 8-bit path cannot fail on a conformant context, so it is the floor.
  const fallback = candidates[candidates.length - 1];
  fallback.trials = trials;
  return fallback;
}

/**
 * Can this context actually render into `candidate`?
 *
 * `checkFramebufferStatus` is the authoritative test: some drivers accept a
 * float `texImage2D` while still leaving a pending error flag from an unrelated
 * earlier call, so gating on `getError` alone rejects formats that work. The
 * error queue is drained up front so a stale flag cannot leak in either.
 */
function probeColorTarget(gl, candidate) {
  for (let guard = 0; guard < 32 && gl.getError() !== gl.NO_ERROR; guard += 1) {
    // drain
  }
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, candidate.internalFormat, 4, 4, 0, gl.RGBA, candidate.type, null);
  const filter = candidate.linearFilter ? gl.LINEAR : gl.NEAREST;
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  const framebuffer = gl.createFramebuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
  const complete = gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE;
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  gl.deleteFramebuffer(framebuffer);
  gl.deleteTexture(texture);
  if (complete) {
    // Leave the queue clean so a later probe cannot be poisoned by this one.
    for (let guard = 0; guard < 32 && gl.getError() !== gl.NO_ERROR; guard += 1) {
      // drain
    }
  }
  return complete;
}

export function detectDepthSampling(gl) {
  const extension = gl.getExtension("WEBGL_depth_texture");
  return {
    supported: Boolean(extension),
    extension,
  };
}

function createColorTexture(gl, capabilities, width, height, filter) {
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(
    gl.TEXTURE_2D,
    0,
    capabilities.internalFormat,
    width,
    height,
    0,
    gl.RGBA,
    capabilities.type,
    null,
  );
  // A float target is only filterable when the capability says so; asking for
  // LINEAR otherwise is an INVALID_ENUM and silently breaks every blur.
  const resolved = capabilities.linearFilter === false ? RENDER_TARGET_FILTER.NEAREST : filter;
  const minFilter = glFilter(gl, resolved);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, minFilter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, minFilter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.bindTexture(gl.TEXTURE_2D, null);
  return texture;
}

// WEBGL_depth_texture accepts UNSIGNED_INT for DEPTH_COMPONENT, which drivers
// back with a 24-bit (or better) depth buffer. A 16-bit buffer with the 0.05
// near plane resolves only ~3 blocks at 100 blocks away, so distant terrain
// z-fights; 24 bits keep sub-block precision out to the far LOD rings.
export function depthTextureType(gl) {
  return gl.UNSIGNED_INT ?? gl.UNSIGNED_SHORT;
}

function createDepthTexture(gl, width, height) {
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(
    gl.TEXTURE_2D,
    0,
    gl.DEPTH_COMPONENT,
    width,
    height,
    0,
    gl.DEPTH_COMPONENT,
    depthTextureType(gl),
    null,
  );
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.bindTexture(gl.TEXTURE_2D, null);
  return texture;
}

function createDepthBuffer(gl, width, height) {
  const buffer = gl.createRenderbuffer();
  gl.bindRenderbuffer(gl.RENDERBUFFER, buffer);
  gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, width, height);
  gl.bindRenderbuffer(gl.RENDERBUFFER, null);
  return buffer;
}

/**
 * A colour target, optionally with a sampleable depth texture.
 *
 * `depth: "none" | "texture" | "renderbuffer"`. Depth textures are only created
 * when the caller asked for one and the extension exists; the renderbuffer
 * variant keeps the framebuffer complete for callers that only need occlusion.
 */
export function createRenderTarget(gl, {
  width,
  height,
  capabilities,
  depth = "none",
  filter = RENDER_TARGET_FILTER.LINEAR,
  wrap = RENDER_TARGET_WRAP.CLAMP,
  anisotropy = 0,
  anisotropyExtension = null,
} = {}) {
  const w = Math.max(1, Math.floor(width));
  const h = Math.max(1, Math.floor(height));
  const texture = createColorTexture(gl, capabilities, w, h, filter);
  if (wrap === RENDER_TARGET_WRAP.REPEAT) {
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.bindTexture(gl.TEXTURE_2D, null);
  }
  if (anisotropy > 0 && anisotropyExtension !== null) {
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameterf(
      gl.TEXTURE_2D,
      anisotropyExtension.TEXTURE_MAX_ANISOTROPY_EXT,
      anisotropy,
    );
    gl.bindTexture(gl.TEXTURE_2D, null);
  }
  const framebuffer = gl.createFramebuffer();
  const depthTexture = depth === "texture" ? createDepthTexture(gl, w, h) : null;
  const depthBuffer = depth === "renderbuffer" ? createDepthBuffer(gl, w, h) : null;
  gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
  if (depthTexture !== null) {
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, depthTexture, 0);
  } else if (depthBuffer !== null) {
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depthBuffer);
  }
  const status = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  if (status !== gl.FRAMEBUFFER_COMPLETE) {
    gl.deleteFramebuffer(framebuffer);
    gl.deleteTexture(texture);
    if (depthTexture !== null) gl.deleteTexture(depthTexture);
    if (depthBuffer !== null) gl.deleteRenderbuffer(depthBuffer);
    throw new Error(`Incomplete framebuffer (0x${status.toString(16)}) for a ${w}x${h} target`);
  }
  return {
    framebuffer,
    texture,
    depthTexture,
    depthBuffer,
    width: w,
    height: h,
    capabilities,
    depthMode: depth,
    filterMode: filter,
    dispose() {
      gl.deleteFramebuffer(framebuffer);
      gl.deleteTexture(texture);
      if (depthTexture !== null) gl.deleteTexture(depthTexture);
      if (depthBuffer !== null) gl.deleteRenderbuffer(depthBuffer);
    },
  };
}

/** Reallocate a target at a new size, keeping its format. */
export function resizeRenderTarget(gl, target, width, height) {
  const w = Math.max(1, Math.floor(width));
  const h = Math.max(1, Math.floor(height));
  if (target.width === w && target.height === h) return target;
  target.dispose();
  return createRenderTarget(gl, {
    width: w,
    height: h,
    capabilities: target.capabilities,
    depth: target.depthMode,
    filter: target.filterMode,
  });
}

export function bindRenderTarget(gl, target) {
  gl.bindFramebuffer(gl.FRAMEBUFFER, target === null ? null : target.framebuffer);
  if (target !== null) {
    gl.viewport(0, 0, target.width, target.height);
  }
}

export function bindTextureUnit(gl, unit, texture) {
  gl.activeTexture(gl.TEXTURE0 + unit);
  gl.bindTexture(gl.TEXTURE_2D, texture);
  return unit;
}
