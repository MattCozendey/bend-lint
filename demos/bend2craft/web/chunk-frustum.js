// Per-chunk frustum culling and submit accounting for the WebGPU terrain path.
// Dependency-free and testable without a browser: the renderer only supplies a
// view-projection matrix and the per-chunk bounds it already knows from the
// uploaded vertex data.

export const CLIP_PLANE_COUNT = 6;

export const EMPTY_BOUNDS = Object.freeze({
  minX: Number.POSITIVE_INFINITY,
  minY: Number.POSITIVE_INFINITY,
  minZ: Number.POSITIVE_INFINITY,
  maxX: Number.NEGATIVE_INFINITY,
  maxY: Number.NEGATIVE_INFINITY,
  maxZ: Number.NEGATIVE_INFINITY,
});

export function emptyBounds() {
  return { ...EMPTY_BOUNDS };
}

// Union of two boxes. An empty operand is ignored so merging a missing layer
// cannot poison a chunk that still has opaque geometry.
export function mergeBounds(a, b) {
  if (isEmptyBounds(b)) return a;
  if (isEmptyBounds(a)) return b;
  return {
    minX: Math.min(a.minX, b.minX),
    minY: Math.min(a.minY, b.minY),
    minZ: Math.min(a.minZ, b.minZ),
    maxX: Math.max(a.maxX, b.maxX),
    maxY: Math.max(a.maxY, b.maxY),
    maxZ: Math.max(a.maxZ, b.maxZ),
  };
}

export function isEmptyBounds(bounds) {
  return !(bounds.maxX >= bounds.minX && bounds.maxY >= bounds.minY && bounds.maxZ >= bounds.minZ);
}

export function expandBounds(bounds, x, y, z) {
  if (x < bounds.minX) bounds.minX = x;
  if (y < bounds.minY) bounds.minY = y;
  if (z < bounds.minZ) bounds.minZ = z;
  if (x > bounds.maxX) bounds.maxX = x;
  if (y > bounds.maxY) bounds.maxY = y;
  if (z > bounds.maxZ) bounds.maxZ = z;
  return bounds;
}

// The chunk bounds come from the same packed positions the GPU buffer already
// holds, so culling never needs a second copy of the geometry.
export function boundsFromPositions(positions) {
  const bounds = emptyBounds();
  if (positions === null || positions === undefined) return bounds;
  const count = Math.floor(positions.length / 3);
  for (let vertex = 0; vertex < count; vertex += 1) {
    expandBounds(
      bounds,
      positions[vertex * 3],
      positions[vertex * 3 + 1],
      positions[vertex * 3 + 2],
    );
  }
  return bounds;
}

function normalizePlane(a, b, c, d) {
  const length = Math.hypot(a, b, c);
  if (!(length > 0) || !Number.isFinite(length)) return [0, 0, 0, 1];
  return [a / length, b / length, c / length, d / length];
}

/**
 * Gribb-Hartmann plane extraction for a column-major 4x4 view-projection.
 * Element (row, column) lives at index `column * 4 + row`, matching the
 * renderer matrices, so row `i` is (m[i], m[4 + i], m[8 + i], m[12 + i]).
 * A point is inside a plane when a*x + b*y + c*z + d >= 0.
 */
export function extractClipPlanes(viewProjection) {
  const m = viewProjection;
  if (m === null || m === undefined || m.length < 16) return null;
  const row = (i) => [m[i], m[4 + i], m[8 + i], m[12 + i]];
  const r0 = row(0);
  const r1 = row(1);
  const r2 = row(2);
  const r3 = row(3);
  const sum = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]];
  const difference = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]];
  return [
    normalizePlane(...sum(r3, r0)),
    normalizePlane(...difference(r3, r0)),
    normalizePlane(...sum(r3, r1)),
    normalizePlane(...difference(r3, r1)),
    normalizePlane(...sum(r3, r2)),
    normalizePlane(...difference(r3, r2)),
  ];
}

/**
 * Conservative AABB test. Returns true when the box may be visible: only a box
 * whose positive vertex falls behind every single plane is rejected, so a
 * partially visible chunk is always kept.
 */
export function isBoundsVisible(planes, bounds) {
  // An empty chunk has no geometry to submit, so it is never visible even
  // without a frustum; this keeps the submit accounting honest.
  if (isEmptyBounds(bounds)) return false;
  if (planes === null || planes === undefined) return true;
  for (const plane of planes) {
    const [a, b, c, d] = plane;
    const x = a >= 0 ? bounds.maxX : bounds.minX;
    const y = b >= 0 ? bounds.maxY : bounds.minY;
    const z = c >= 0 ? bounds.maxZ : bounds.minZ;
    if (a * x + b * y + c * z + d < 0) return false;
  }
  return true;
}

export function createSubmitMetrics() {
  return {
    totalChunks: 0,
    visibleChunks: 0,
    culledChunks: 0,
    drawCalls: 0,
    submittedVertices: 0,
    submittedVertexBytes: 0,
  };
}

/**
 * Select the chunks that can contribute to this frame and account for the
 * submit. A chunk issues one draw per non-empty layer, so a chunk with only
 * opaque geometry costs a single call.
 */
export function selectVisibleChunks(chunks, planes) {
  const visible = [];
  const metrics = createSubmitMetrics();
  for (const chunk of chunks) {
    metrics.totalChunks += 1;
    if (!isBoundsVisible(planes, chunk.bounds)) {
      metrics.culledChunks += 1;
      continue;
    }
    metrics.visibleChunks += 1;
    const opaque = Number(chunk.opaqueVertices ?? 0);
    const water = Number(chunk.waterVertices ?? 0);
    const stride = Number(chunk.strideBytes ?? 0);
    if (opaque > 0) metrics.drawCalls += 1;
    if (water > 0) metrics.drawCalls += 1;
    metrics.submittedVertices += opaque + water;
    metrics.submittedVertexBytes += (opaque + water) * stride;
    visible.push(chunk);
  }
  return { visible, metrics };
}
