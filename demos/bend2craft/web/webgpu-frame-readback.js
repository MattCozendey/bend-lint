// Real-frame WebGPU readback and scene probing. The pure parts live here so the
// gate can be tested without a GPU: the renderer owns the device calls, and this
// module owns the byte accounting and the verdicts.

export const FRAME_READBACK_BYTES_PER_PIXEL = 4;
export const COPY_SRC = 0x01;
export const MAP_READ = 0x0001;
// WebGPU requires a copied region to be padded to this row alignment.
export const COPY_ROW_ALIGNMENT = 256;

export function bytesPerRow(width) {
  const pixelWidth = Math.max(1, Math.trunc(Number(width) || 0));
  const rowBytes = pixelWidth * FRAME_READBACK_BYTES_PER_PIXEL;
  return Math.ceil(rowBytes / COPY_ROW_ALIGNMENT) * COPY_ROW_ALIGNMENT;
}

/**
 * Top row of a readback region, given the bottom-left origin the caller used.
 *
 * Callers address the frame the way WebGL `readPixels` does, with the origin at
 * the bottom left. A canvas texture is stored top-down, so the copy has to start
 * at the mirrored row. Without this the copy silently starts at row 0 and every
 * readback returns the top-left corner of the frame instead of the requested
 * region.
 */
export function readbackRowTop(canvasHeight, bottom, height) {
  const total = Math.max(1, Math.trunc(Number(canvasHeight) || 0));
  const from = Math.trunc(Number(bottom) || 0);
  const rows = Math.max(1, Math.trunc(Number(height) || 0));
  return Math.max(0, total - from - rows);
}

/** Where a copied row belongs in the returned buffer, so the frame is upright. */
export function readbackTargetRow(height, row) {
  const rows = Math.max(1, Math.trunc(Number(height) || 0));
  return rows - 1 - Math.max(0, Math.min(rows - 1, Math.trunc(Number(row) || 0)));
}

/**
 * Undo the swap chain's channel order.
 *
 * The preferred canvas format is normally `bgra8unorm`, so a raw copy comes back
 * with red and blue exchanged. The browser presents the frame correctly, but
 * anything that reads the pixels back has to undo the swap or it disagrees with
 * the WebGL backend, which reports RGBA.
 */
export function swapRedBlue(pixels) {
  for (let index = 0; index + 3 < pixels.length; index += 4) {
    const red = pixels[index];
    pixels[index] = pixels[index + 2];
    pixels[index + 2] = red;
  }
  return pixels;
}

/**
 * Whether this device can actually hand a rendered frame back to JavaScript.
 * A pipeline that compiles is not the same thing as a frame we can measure, so
 * an unsupported path reports why instead of silently skipping.
 */
export function describeFrameReadbackSupport(support) {
  if (support === null || typeof support !== "object") {
    return { supported: false, reason: "the WebGPU device never reported readback support" };
  }
  if (support.hasCopySource !== true) {
    return {
      supported: false,
      reason: "the WebGPU canvas format cannot be copied out of the swap chain",
    };
  }
  if (support.hasMapRead !== true) {
    return { supported: false, reason: "the WebGPU device cannot map buffers for readback" };
  }
  return { supported: true, reason: null };
}

export function frameReadbackReason(support) {
  if (support === null || support === undefined) return "frame readback support was never probed";
  return support.reason ?? null;
}

/**
 * Score one readback region. A rendered scene has a wide tonal range and many
 * distinct colors; a cleared or blank compositor surface has one. Anything that
 * cannot be measured fails closed with a reason.
 */
export function sceneProbeVerdict(region) {
  const failure = (reason) => ({
    scored: false,
    reason,
    nonBlank: false,
    brightPixels: 0,
    distinctColors: 0,
    meanLuma: 0,
    lumaSpread: 0,
    pixels: 0,
    width: 0,
    height: 0,
  });
  if (region === null || typeof region !== "object") return failure("the frame region was never read back");
  const width = Math.trunc(Number(region.width) || 0);
  const height = Math.trunc(Number(region.height) || 0);
  const pixels = region.pixels;
  if (width < 1 || height < 1) return failure("the frame region has no pixels");
  if (pixels === null || pixels === undefined) return failure("the frame region has no pixel data");
  const total = width * height;
  if (pixels.length < total * FRAME_READBACK_BYTES_PER_PIXEL) {
    return failure("the frame readback is shorter than the region it claims to cover");
  }
  const colors = new Set();
  let bright = 0;
  let lumaSum = 0;
  let lumaMin = 255;
  let lumaMax = 0;
  for (let index = 0; index < total; index += 1) {
    const base = index * FRAME_READBACK_BYTES_PER_PIXEL;
    const alpha = pixels[base + 3];
    const luma = Math.round(
      pixels[base] * 0.2126 + pixels[base + 1] * 0.7152 + pixels[base + 2] * 0.0722,
    );
    lumaSum += luma;
    if (luma < lumaMin) lumaMin = luma;
    if (luma > lumaMax) lumaMax = luma;
    if (alpha > 16 && luma > 24) bright += 1;
    colors.add((pixels[base] >> 3 << 10) | (pixels[base + 1] >> 3 << 5) | (pixels[base + 2] >> 3));
  }
  const distinctColors = colors.size;
  const nonBlank = bright > 0 && distinctColors > 1;
  return {
    scored: true,
    reason: nonBlank ? null : "the readback region carries no rendered scene",
    nonBlank,
    brightPixels: bright,
    distinctColors,
    meanLuma: lumaSum / total,
    lumaSpread: lumaMax - lumaMin,
    pixels: total,
    width,
    height,
  };
}

/** Probe several regions of one frame and require all of them to be a scene. */
export function probeSceneFrame(regions) {
  if (!Array.isArray(regions) || regions.length === 0) {
    return {
      passed: false,
      reason: "no frame regions were read back",
      regions: [],
    };
  }
  const scored = regions.map((region) => sceneProbeVerdict(region));
  const failed = scored.find((region) => !region.nonBlank);
  return {
    passed: failed === undefined,
    reason: failed === undefined ? null : failed.reason,
    regions: scored,
  };
}

/**
 * The frame the gate read back must be the frame the culler described, so the
 * culled/visible split has to account for every resident chunk and something
 * must still be visible.
 */
export function cullingAgreesWithProbe(stats, probe) {
  if (stats === null || stats === undefined) return false;
  if (probe === null || probe === undefined) return false;
  const resident = Number(stats.residentChunks);
  const visible = Number(stats.visibleChunks);
  const culled = Number(stats.culledChunks);
  if (!Number.isInteger(resident) || !Number.isInteger(visible) || !Number.isInteger(culled)) return false;
  if (resident < 1) return false;
  if (visible + culled !== resident) return false;
  if (visible < 1) return false;
  return probe.passed === true;
}
