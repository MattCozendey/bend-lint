import { mergeBounds, selectVisibleChunks, emptyBounds } from "./chunk-frustum.js";
import {
  TERRAIN_VERTEX_LAYOUT,
  TERRAIN_VERTEX_STRIDE_BYTES,
  classifyChunkUpdate,
  packTerrainLayer,
  packedLayerBounds,
} from "./webgpu-chunk-buffers.js";

/**
 * Per-chunk terrain buffers for the WebGL backend.
 *
 * WebGL used to concatenate every chunk (and the horizon) into one set of
 * attribute arrays and re-upload all of it whenever a single chunk streamed in
 * or a block changed, which made streaming cost grow with the render distance.
 * This mirrors the WebGPU backend instead: one interleaved buffer per chunk
 * layer, reused while its vertex data is the same object, retired when the
 * chunk leaves the resident set, and culled per chunk against the frustum.
 */
export function createWebglChunkBuffers(gl) {
  if (gl === null || gl === undefined) throw new TypeError("WebGL chunk buffers need a context");
  const resident = new Map();
  let uploads = 0;
  let reuses = 0;
  let uploadedBytes = 0;

  function uploadLayer(previous, packed) {
    if (packed.vertexCount === 0) {
      if (previous !== null && previous !== undefined) gl.deleteBuffer(previous);
      return null;
    }
    const buffer = previous ?? gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, packed.data, gl.STATIC_DRAW);
    uploadedBytes += packed.data.byteLength;
    return buffer;
  }

  function store(key, opaqueSource, waterSource, lod) {
    const previous = resident.get(key);
    if (previous !== undefined
      && previous.opaqueSource === opaqueSource
      && previous.waterSource === waterSource) {
      reuses += 1;
      return false;
    }
    const opaque = packTerrainLayer(opaqueSource);
    const water = packTerrainLayer(waterSource);
    resident.set(key, {
      key,
      lod,
      opaque: uploadLayer(previous?.opaque, opaque),
      water: uploadLayer(previous?.water, water),
      opaqueSource,
      waterSource,
      opaqueVertices: opaque.vertexCount,
      waterVertices: water.vertexCount,
      opaqueQuads: opaque.quadCount,
      waterQuads: water.quadCount,
      strideBytes: TERRAIN_VERTEX_STRIDE_BYTES,
      bounds: mergeBounds(packedLayerBounds(opaque, emptyBounds), packedLayerBounds(water, emptyBounds)),
    });
    uploads += 1;
    return true;
  }

  function retire(key) {
    const entry = resident.get(key);
    if (entry === undefined) return;
    if (entry.opaque !== null) gl.deleteBuffer(entry.opaque);
    if (entry.water !== null) gl.deleteBuffer(entry.water);
    resident.delete(key);
  }

  /**
   * Apply a publication: `chunks` is the complete resident set, each entry a
   * `{ key, vertexData: { opaque, water }, lod? }` in the terrain layer format.
   * `lod` marks distant-terrain sections, which never cast into the shadow map.
   */
  function update(chunks) {
    if (!Array.isArray(chunks)) throw new TypeError("chunk publication must be an array");
    const keys = chunks.map((chunk) => String(chunk.key));
    const mode = classifyChunkUpdate([...resident.keys()], keys);
    if (mode === "resync") {
      const incoming = new Set(keys);
      for (const key of [...resident.keys()]) {
        if (!incoming.has(key)) retire(key);
      }
    }
    let changed = 0;
    for (const chunk of chunks) {
      const stored = store(
        String(chunk.key),
        chunk.vertexData?.opaque ?? null,
        chunk.vertexData?.water ?? null,
        chunk.lod === true,
      );
      if (stored) changed += 1;
    }
    return { mode, changed, resident: resident.size };
  }

  function totals() {
    let opaqueVertices = 0;
    let waterVertices = 0;
    let opaqueQuads = 0;
    let waterQuads = 0;
    for (const entry of resident.values()) {
      opaqueVertices += entry.opaqueVertices;
      waterVertices += entry.waterVertices;
      opaqueQuads += entry.opaqueQuads;
      waterQuads += entry.waterQuads;
    }
    return { opaqueVertices, waterVertices, opaqueQuads, waterQuads };
  }

  /** Chunks that can contribute under `planes` (null keeps everything). */
  function select(planes) {
    return selectVisibleChunks([...resident.values()], planes);
  }

  function dispose() {
    for (const key of [...resident.keys()]) retire(key);
  }

  return {
    update,
    select,
    totals,
    dispose,
    get size() { return resident.size; },
    stats: () => ({ resident: resident.size, uploads, reuses, uploadedBytes }),
  };
}

/**
 * Point the terrain program's attributes at one interleaved chunk buffer. The
 * offsets come from the shared layout so WebGL and WebGPU read the same bytes.
 */
export function bindInterleavedTerrain(gl, buffer, locations) {
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  const stride = TERRAIN_VERTEX_LAYOUT.arrayStride;
  const order = [
    [locations.position, 3],
    [locations.color, 3],
    [locations.light, 2],
    [locations.normal, 3],
    [locations.uv, 2],
    [locations.material, 1],
    [locations.tile, 4],
  ];
  order.forEach(([location, size], index) => {
    if (location === null || location === undefined || location < 0) return;
    gl.enableVertexAttribArray(location);
    gl.vertexAttribPointer(location, size, gl.FLOAT, false, stride, TERRAIN_VERTEX_LAYOUT.attributes[index].offset);
  });
}

/** Position-only binding of an interleaved chunk buffer, for depth passes. */
export function bindInterleavedPositions(gl, buffer, location) {
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.enableVertexAttribArray(location);
  gl.vertexAttribPointer(location, 3, gl.FLOAT, false, TERRAIN_VERTEX_LAYOUT.arrayStride, 0);
}
