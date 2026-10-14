import assert from "node:assert/strict";
import {
  CLIP_PLANE_COUNT,
  boundsFromPositions,
  createSubmitMetrics,
  emptyBounds,
  expandBounds,
  extractClipPlanes,
  isBoundsVisible,
  isEmptyBounds,
  mergeBounds,
  selectVisibleChunks,
} from "../web/chunk-frustum.js";
import { TERRAIN_VERTEX_STRIDE_BYTES } from "../web/webgpu-chunk-buffers.js";
import { identity4, lookAt, multiply4, perspective } from "../web/gl-matrix.js";

// The camera matrices come from the canonical module the renderer itself
// uploads, not from a copy kept in step by hand. A local reimplementation would
// keep asserting a convention the shipped code is free to drift away from, so
// the culling decisions below would stay green while the real camera regressed.

// The frustum planes are extracted in column-major order, so a transposed
// projection would silently swap the near/far pair and cull the world. Pin the
// layout the renderer depends on: element (row, column) at `column * 4 + row`.
const identity = identity4;
const probe = perspective(Math.PI / 2, 1, 0.1, 200);
assert.equal(probe[0], 1, "perspective must write f/aspect at column 0, row 0");
assert.equal(probe[5], 1, "perspective must write f at column 1, row 1");
assert.equal(probe[11], -1, "perspective must write -1 at column 2, row 3");
assert.equal(multiply4(identity4(), identity4())[15], 1, "identity must multiply to identity");

function box(minX, minY, minZ, maxX, maxY, maxZ) {
  const bounds = emptyBounds();
  expandBounds(bounds, minX, minY, minZ);
  expandBounds(bounds, maxX, maxY, maxZ);
  return bounds;
}

assert.equal(CLIP_PLANE_COUNT, 6);
assert.equal(isEmptyBounds(emptyBounds()), true);
assert.equal(isEmptyBounds(box(0, 0, 0, 1, 1, 1)), false);

// Bounds come from the packed positions the GPU buffer already holds, so a
// degenerate layer must produce an empty box rather than a phantom cube.
const quadPositions = new Float32Array([
  0, 0, 0,
  1, 0, 0,
  1, 1, 0,
]);
assert.deepEqual(
  boundsFromPositions(quadPositions),
  { minX: 0, minY: 0, minZ: 0, maxX: 1, maxY: 1, maxZ: 0 },
);
assert.equal(isEmptyBounds(boundsFromPositions(new Float32Array())), true);
assert.equal(isEmptyBounds(boundsFromPositions(null)), true);
assert.equal(isEmptyBounds(boundsFromPositions(undefined)), true);

// A chunk with only one non-empty layer must keep that layer's box; merging an
// empty layer in must not collapse the union.
const solid = box(0, 0, 0, 2, 2, 2);
const water = box(-4, 0, 0, -2, 1, 1);
assert.deepEqual(mergeBounds(solid, emptyBounds()), solid);
assert.deepEqual(mergeBounds(emptyBounds(), water), water);
assert.deepEqual(mergeBounds(solid, water), box(-4, 0, 0, 2, 2, 2));

const planes = extractClipPlanes(identity());
assert.equal(planes.length, CLIP_PLANE_COUNT);
for (const plane of planes) {
  assert.equal(plane.length, 4);
  for (const component of plane) assert.ok(Number.isFinite(component));
}
assert.equal(extractClipPlanes(null), null);
assert.equal(extractClipPlanes(new Float32Array(9)), null);

// A degenerate matrix must not produce NaN planes that cull the whole world.
const degenerate = extractClipPlanes(new Float32Array(16));
assert.equal(degenerate.length, CLIP_PLANE_COUNT);
for (const plane of degenerate) {
  for (const component of plane) assert.ok(Number.isFinite(component));
}

// A camera at the origin looking down -Z with a 90 degree field of view. `up`
// is passed explicitly because the renderer's two call sites both do, and a
// hidden default here would let the test drift away from that contract.
const viewProjection = multiply4(
  perspective(Math.PI / 2, 1, 0.1, 200),
  lookAt([0, 0, 0], [0, 0, -1], [0, 1, 0]),
);
const frustum = extractClipPlanes(viewProjection);
assert.equal(frustum.length, CLIP_PLANE_COUNT);

assert.equal(
  isBoundsVisible(frustum, box(-1, -1, -11, 1, 1, -9)),
  true,
  "a chunk straight ahead must stay visible",
);
assert.equal(
  isBoundsVisible(frustum, box(-1, -1, 9, 1, 1, 11)),
  false,
  "a chunk directly behind the camera must be culled",
);
assert.equal(
  isBoundsVisible(frustum, box(12, -1, -11, 14, 1, -9)),
  false,
  "a chunk far off the horizontal axis must be culled",
);
assert.equal(
  isBoundsVisible(frustum, box(9, -1, -11, 11, 1, -9)),
  true,
  "a chunk that only touches the frustum edge must be kept",
);
assert.equal(
  isBoundsVisible(frustum, box(-40, -1, -41, 40, 1, -39)),
  true,
  "a partially visible chunk must never be culled",
);
assert.equal(
  isBoundsVisible(frustum, box(-1, -1, -301, 1, 1, -299)),
  false,
  "a chunk beyond the far plane must be culled",
);
assert.equal(
  isBoundsVisible(frustum, box(-1, -1, 0.001, 1, 1, 0.002)),
  false,
  "a chunk straddling the near plane from behind must be culled",
);
assert.equal(
  isBoundsVisible(frustum, box(0, 0, -5, 0, 0, -5)),
  true,
  "a degenerate box in front of the camera must stay visible",
);
assert.equal(
  isBoundsVisible(frustum, box(0, 0, 0, 0, 0, 0)),
  false,
  "a degenerate box on the eye sits behind the near plane",
);
assert.equal(isBoundsVisible(null, box(0, 0, 0, 1, 1, 1)), true, "a missing frustum must not cull");
assert.equal(isBoundsVisible(frustum, emptyBounds()), false, "an empty box contributes nothing");

assert.deepEqual(createSubmitMetrics(), {
  totalChunks: 0,
  visibleChunks: 0,
  culledChunks: 0,
  drawCalls: 0,
  submittedVertices: 0,
  submittedVertexBytes: 0,
});

// Submit accounting must reflect the culled set, not the resident set.
const chunks = [
  { key: "ahead", bounds: box(-1, -1, -11, 1, 1, -9), opaqueVertices: 600, waterVertices: 0 },
  { key: "ahead-water", bounds: box(-1, -1, -11, 1, 1, -9), opaqueVertices: 0, waterVertices: 60 },
  { key: "behind", bounds: box(-1, -1, 9, 1, 1, 11), opaqueVertices: 600, waterVertices: 60 },
  { key: "empty", bounds: emptyBounds(), opaqueVertices: 0, waterVertices: 0 },
].map((chunk) => ({ ...chunk, strideBytes: TERRAIN_VERTEX_STRIDE_BYTES }));

const selection = selectVisibleChunks(chunks, frustum);
assert.deepEqual(selection.visible.map((chunk) => chunk.key), ["ahead", "ahead-water"]);
assert.equal(selection.metrics.totalChunks, 4);
assert.equal(selection.metrics.visibleChunks, 2);
assert.equal(selection.metrics.culledChunks, 2);
assert.equal(selection.metrics.drawCalls, 2, "each non-empty layer costs one draw call");
assert.equal(selection.metrics.submittedVertices, 660);
assert.equal(selection.metrics.submittedVertexBytes, 660 * TERRAIN_VERTEX_STRIDE_BYTES);
// 18 floats per vertex: position, colour, light, normal, uv, material, tileRect.
assert.equal(TERRAIN_VERTEX_STRIDE_BYTES, 72);

// Without a frustum every resident chunk is submitted, which is the contract
// the culling benchmark compares against.
const unculled = selectVisibleChunks(chunks, null);
assert.equal(unculled.visible.length, 3);
assert.equal(unculled.metrics.culledChunks, 1);
assert.equal(unculled.metrics.drawCalls, 4, "the behind chunk contributes both of its layers");
assert.equal(
  unculled.metrics.submittedVertexBytes - selection.metrics.submittedVertexBytes,
  660 * TERRAIN_VERTEX_STRIDE_BYTES,
  "culling must remove the behind-camera chunk from the submit",
);

console.log("chunk frustum culling ok");
