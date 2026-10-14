import assert from "node:assert/strict";
import {
  COPY_SRC,
  FRAME_READBACK_BYTES_PER_PIXEL,
  MAP_READ,
  bytesPerRow,
  cullingAgreesWithProbe,
  describeFrameReadbackSupport,
  frameReadbackReason,
  probeSceneFrame,
  readbackRowTop,
  readbackTargetRow,
  sceneProbeVerdict,
  swapRedBlue,
} from "../web/webgpu-frame-readback.js";

// Phase 6 requires a real rendered frame, not just a valid pipeline. The
// readback contract and the scene probe are pure so both are testable without a
// GPU, and both refuse to certify a frame they cannot actually measure.

assert.equal(FRAME_READBACK_BYTES_PER_PIXEL, 4);
assert.equal(COPY_SRC, 0x01);
assert.equal(MAP_READ, 0x0001);

// WebGPU only needs a copyable canvas format plus mappable buffers. Anything
// that cannot do that must report a reason instead of pretending to work.
assert.deepEqual(describeFrameReadbackSupport({ hasCopySource: false, hasMapRead: true }), {
  supported: false,
  reason: "the WebGPU canvas format cannot be copied out of the swap chain",
});
assert.deepEqual(describeFrameReadbackSupport({ hasCopySource: true, hasMapRead: false }), {
  supported: false,
  reason: "the WebGPU device cannot map buffers for readback",
});
const supported = describeFrameReadbackSupport({ hasCopySource: true, hasMapRead: true });
assert.equal(supported.supported, true);
assert.equal(supported.reason, null);
assert.deepEqual(describeFrameReadbackSupport(null).supported, false);
assert.deepEqual(describeFrameReadbackSupport({ hasCopySource: true, hasMapRead: true }).reason, null);
assert.equal(
  frameReadbackReason(describeFrameReadbackSupport({ hasCopySource: false, hasMapRead: true })),
  "the WebGPU canvas format cannot be copied out of the swap chain",
);
assert.equal(frameReadbackReason(supported), null);
assert.equal(frameReadbackReason(null), "frame readback support was never probed");

// A copied region must be padded to the 256-byte row alignment the API
// requires, or the copy silently reads the wrong rows.
assert.equal(bytesPerRow(1), 256);
assert.equal(bytesPerRow(64), 256);
assert.equal(bytesPerRow(65), 512);
assert.equal(bytesPerRow(1280), 5120);
assert.equal(bytesPerRow(0), 256);
assert.equal(bytesPerRow(-4), 256, "a negative width must not produce a negative stride");

// A readback has to honour the region the caller asked for. A canvas texture is
// stored top-down while callers address it bottom-up like WebGL `readPixels`, so
// a copy that ignores both the origin and the row order hands back the top-left
// corner, mirrored. That is invisible in a pipeline-compiles test and obvious in
// a frame comparison.
assert.equal(readbackRowTop(720, 0, 180), 540, "a bottom strip starts at the mirrored top row");
assert.equal(readbackRowTop(720, 270, 180), 270, "a centred strip starts halfway up");
assert.equal(readbackRowTop(720, 540, 180), 0, "a top strip starts at row zero");
assert.equal(readbackRowTop(720, 0, 720), 0, "the whole frame starts at row zero");
assert.equal(readbackRowTop(720, 700, 180), 0, "an over-tall region must not go negative");
assert.notEqual(
  readbackRowTop(720, 270, 180),
  0,
  "a centred region must not collapse onto the top-left corner",
);

assert.equal(readbackTargetRow(180, 0), 179, "the first copied row is the last output row");
assert.equal(readbackTargetRow(180, 179), 0);
assert.equal(readbackTargetRow(1, 0), 0, "a single row is its own mirror");
assert.equal(readbackTargetRow(4, 9), 0, "an out-of-range row must clamp into the frame");

// The swap chain is usually BGRA, so a raw copy has red and blue exchanged. The
// browser presents it correctly, but a readback has to undo the swap or it
// disagrees with the WebGL backend pixel for pixel.
const swapped = swapRedBlue(Uint8Array.of(10, 20, 30, 255, 40, 50, 60, 128));
assert.deepEqual([...swapped], [30, 20, 10, 255, 60, 50, 40, 128], "red and blue must trade places");
assert.equal(swapped[3], 255, "alpha must survive the swap");
assert.equal(swapped[7], 128, "alpha must survive the swap");
const roundTrip = swapRedBlue(Uint8Array.from(swapped));
assert.deepEqual([...roundTrip], [10, 20, 30, 255, 40, 50, 60, 128], "the swap must be its own inverse");
assert.deepEqual(
  [...swapRedBlue(Uint8Array.of(1, 2, 3))],
  [1, 2, 3],
  "a trailing partial pixel must be left alone",
);

// A scene probe must distinguish a rendered scene from a blank, uniformly
// coloured frame. A cleared canvas has one distinct color; terrain has many.
const blank = {
  width: 64,
  height: 64,
  pixels: uniformPixels(64, 64, [7, 11, 19, 255]),
};
const terrain = {
  width: 64,
  height: 64,
  pixels: variedPixels(64, 64),
};

assert.equal(sceneProbeVerdict(blank).nonBlank, false, "a uniformly cleared frame is not a scene");
assert.equal(sceneProbeVerdict(blank).distinctColors, 1);
assert.equal(sceneProbeVerdict(terrain).nonBlank, true);
assert.ok(sceneProbeVerdict(terrain).distinctColors > 8, "a rendered scene must have real tonal range");
assert.ok(sceneProbeVerdict(terrain).brightPixels > 0);
assert.equal(sceneProbeVerdict(terrain).lumaSpread > 0, true, "a scene must not be a flat tone");

// The verdict must fail closed on anything it cannot measure.
for (const bad of [null, undefined, {}, { width: 0, height: 0, pixels: new Uint8Array(0) }]) {
  const verdict = sceneProbeVerdict(bad);
  assert.equal(verdict.nonBlank, false, "an unreadable frame must never certify as a scene");
  assert.equal(verdict.reason !== null, true, "an unreadable frame must carry a reason");
}
const mismatched = { width: 8, height: 8, pixels: new Uint8Array(64) };
assert.equal(sceneProbeVerdict(mismatched).reason !== null, true, "a short readback must be rejected");
const zeroAlpha = { width: 4, height: 4, pixels: uniformPixels(4, 4, [200, 200, 200, 0]) };
assert.equal(sceneProbeVerdict(zeroAlpha).nonBlank, false, "a fully transparent frame is not a scene");

// A frame that lost its shading collapses to a flat near-white region. Measured
// on a real WebGPU capture of that bug, the gate fails because a terrain region
// drops to a single colour, so this pins the property the gate relies on.
const washedOut = { width: 64, height: 64, pixels: washedOutPixels(64, 64) };
const washVerdict = sceneProbeVerdict(washedOut);
assert.equal(washVerdict.distinctColors, 1, "a washed-out region collapses to one colour");
assert.equal(washVerdict.nonBlank, false, "a washed-out region must not certify as a scene");
assert.ok(washVerdict.reason !== null);
assert.equal(probeSceneFrame([washedOut]).passed, false, "the gate must reject a washed-out frame");
assert.equal(sceneProbeVerdict(terrain).nonBlank, true, "a real scene must still certify");

// The probe reports what it measured so the gate can print evidence.
const verdict = sceneProbeVerdict(terrain);
assert.equal(verdict.pixels, 64 * 64);
assert.equal(verdict.width, 64);
assert.equal(verdict.height, 64);
assert.equal(typeof verdict.lumaSpread, "number");
assert.equal(typeof verdict.meanLuma, "number");
assert.equal(verdict.reason, null);
assert.equal(verdict.scored, true);

// The gate must be able to tell "the scene rendered" from "the pipeline
// compiled", which is the whole point of the phase.
const pipelineOnly = probeSceneFrame([{ pixels: uniformPixels(8, 8, [0, 0, 0, 255]) }]);
assert.equal(pipelineOnly.passed, false, "a black frame cannot pass a scene probe");
assert.equal(pipelineOnly.reason !== null, true);
const realScene = probeSceneFrame([{ width: 32, height: 32, pixels: variedPixels(32, 32) }]);
assert.equal(realScene.passed, true);
assert.equal(realScene.regions.length, 1);
assert.equal(realScene.regions[0].nonBlank, true);
assert.equal(probeSceneFrame([]).passed, false, "no regions cannot certify a scene");
assert.equal(probeSceneFrame(null).passed, false);

// Culling accounting must be consistent with what the probe saw, or the frame
// is not the frame the metrics describe.
assert.equal(cullingAgreesWithProbe({ visibleChunks: 4, culledChunks: 6, residentChunks: 10 }, realScene), true);
assert.equal(cullingAgreesWithProbe({ visibleChunks: 4, culledChunks: 5, residentChunks: 10 }, realScene), false);
assert.equal(cullingAgreesWithProbe({ visibleChunks: 0, culledChunks: 10, residentChunks: 10 }, realScene), false);
assert.equal(cullingAgreesWithProbe(null, realScene), false);
assert.equal(cullingAgreesWithProbe({ visibleChunks: 4, culledChunks: 6, residentChunks: 10 }, null), false);

console.log("webgpu frame readback ok");

// The washed-out frame the WGSL shadowing bug produced: a flat, unshaded
// near-white surface with no tonal variation left.
function washedOutPixels(width, height) {
  const pixels = new Uint8Array(width * height * 4);
  for (let index = 0; index < width * height; index += 1) {
    pixels[index * 4] = 238;
    pixels[index * 4 + 1] = 237;
    pixels[index * 4 + 2] = 235;
    pixels[index * 4 + 3] = 255;
  }
  return pixels;
}

function uniformPixels(width, height, color) {
  const pixels = new Uint8Array(width * height * 4);
  for (let index = 0; index < width * height; index += 1) {
    pixels[index * 4] = color[0];
    pixels[index * 4 + 1] = color[1];
    pixels[index * 4 + 2] = color[2];
    pixels[index * 4 + 3] = color[3];
  }
  return pixels;
}

function variedPixels(width, height) {  const pixels = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const index = (y * width + x) * 4;
      const sky = y < height / 2;
      pixels[index] = sky ? 120 + ((x * 3) % 40) : 40 + ((x * 7 + y) % 60);
      pixels[index + 1] = sky ? 150 + ((x) % 30) : 70 + ((y * 5) % 50);
      pixels[index + 2] = sky ? 210 - ((x) % 20) : 40 + ((x * 2 + y * 3) % 40);
      pixels[index + 3] = 255;
    }
  }
  return pixels;
}
