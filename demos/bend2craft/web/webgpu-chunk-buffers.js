// position(3) + colour(3) + light(2) + normal(3) + uv(2) + material(1) + tile(4)
export const TERRAIN_VERTEX_STRIDE_FLOATS = 18;
export const TERRAIN_VERTEX_STRIDE_BYTES = TERRAIN_VERTEX_STRIDE_FLOATS * Float32Array.BYTES_PER_ELEMENT;

/**
 * The one description of the terrain vertex layout.
 *
 * The renderer and the WebGPU smoke both need it, and they used to carry their
 * own copies. The smoke's copy fell behind when the layout gained the normal,
 * the light pair and the tile rect, so it built a five-attribute pipeline
 * against a seven-attribute shader and failed validation with an error that
 * looked like a shader bug and was not one. Anything that declares a terrain
 * vertex buffer takes the layout from here.
 */
export const TERRAIN_VERTEX_LAYOUT = Object.freeze({
  arrayStride: TERRAIN_VERTEX_STRIDE_BYTES,
  attributes: Object.freeze([
    Object.freeze({ shaderLocation: 0, offset: 0, format: "float32x3" }),
    Object.freeze({ shaderLocation: 1, offset: 12, format: "float32x3" }),
    Object.freeze({ shaderLocation: 2, offset: 24, format: "float32x2" }),
    Object.freeze({ shaderLocation: 3, offset: 32, format: "float32x3" }),
    Object.freeze({ shaderLocation: 4, offset: 44, format: "float32x2" }),
    Object.freeze({ shaderLocation: 5, offset: 52, format: "float32" }),
    Object.freeze({ shaderLocation: 6, offset: 56, format: "float32x4" }),
  ]),
});

// The culler needs a per-chunk box, and the packed buffer already holds every
// position. Reading the bounds back from the packed data keeps the stride
// knowledge in this module instead of duplicating it in the renderer.
export function packedLayerBounds(packed, empty) {
  const bounds = empty();
  if (packed === null || packed === undefined || packed.vertexCount === 0) return bounds;
  const { data } = packed;
  for (let vertex = 0; vertex < packed.vertexCount; vertex += 1) {
    const base = vertex * TERRAIN_VERTEX_STRIDE_FLOATS;
    bounds.minX = Math.min(bounds.minX, data[base]);
    bounds.minY = Math.min(bounds.minY, data[base + 1]);
    bounds.minZ = Math.min(bounds.minZ, data[base + 2]);
    bounds.maxX = Math.max(bounds.maxX, data[base]);
    bounds.maxY = Math.max(bounds.maxY, data[base + 1]);
    bounds.maxZ = Math.max(bounds.maxZ, data[base + 2]);
  }
  return bounds;
}

function isNumericArray(value) {
  return Array.isArray(value) || ArrayBuffer.isView(value);
}

function requiredArray(layer, name) {
  const value = layer?.[name];
  if (!isNumericArray(value)) throw new TypeError(`terrain layer is missing ${name}`);
  return value;
}

function emptyLayer() {
  return {
    data: new Float32Array(),
    vertexCount: 0,
    strideBytes: TERRAIN_VERTEX_STRIDE_BYTES,
    quadCount: 0,
  };
}

export function packTerrainLayer(layer) {
  if (layer === null || layer === undefined) return emptyLayer();
  const positions = requiredArray(layer, "positions");
  const colors = requiredArray(layer, "colors");
  const lights = requiredArray(layer, "lights");
  const normals = requiredArray(layer, "normals");
  const uvs = requiredArray(layer, "uvs");
  const materials = requiredArray(layer, "materials");
  const tiles = requiredArray(layer, "tiles");
  if (positions.length % 3 !== 0) throw new RangeError("terrain positions must contain vec3 values");
  const vertexCount = positions.length / 3;
  if (colors.length !== vertexCount * 3) throw new RangeError("terrain colors do not match positions");
  if (lights.length !== vertexCount * 2) throw new RangeError("terrain lights do not match positions");
  if (normals.length !== vertexCount * 3) throw new RangeError("terrain normals do not match positions");
  if (uvs.length !== vertexCount * 2) throw new RangeError("terrain uvs do not match positions");
  if (materials.length !== vertexCount) throw new RangeError("terrain materials do not match positions");
  if (tiles.length !== vertexCount * 4) throw new RangeError("terrain tiles do not match positions");
  const data = new Float32Array(vertexCount * TERRAIN_VERTEX_STRIDE_FLOATS);
  for (let vertex = 0; vertex < vertexCount; vertex += 1) {
    const source = vertex * TERRAIN_VERTEX_STRIDE_FLOATS;
    const position = vertex * 3;
    const light = vertex * 2;
    const uv = vertex * 2;
    const tile = vertex * 4;
    data[source] = positions[position];
    data[source + 1] = positions[position + 1];
    data[source + 2] = positions[position + 2];
    data[source + 3] = colors[position];
    data[source + 4] = colors[position + 1];
    data[source + 5] = colors[position + 2];
    data[source + 6] = lights[light];
    data[source + 7] = lights[light + 1];
    data[source + 8] = normals[position];
    data[source + 9] = normals[position + 1];
    data[source + 10] = normals[position + 2];
    data[source + 11] = uvs[uv];
    data[source + 12] = uvs[uv + 1];
    data[source + 13] = materials[vertex];
    data[source + 14] = tiles[tile];
    data[source + 15] = tiles[tile + 1];
    data[source + 16] = tiles[tile + 2];
    data[source + 17] = tiles[tile + 3];
  }
  return {
    data,
    vertexCount,
    strideBytes: TERRAIN_VERTEX_STRIDE_BYTES,
    quadCount: Number(layer.quadCount ?? vertexCount / 6),
  };
}

/**
 * Decide how a chunk publication must be applied. The WebGPU backend keeps one
 * buffer per chunk, so an edit that leaves the resident key set untouched can
 * be applied in place, while a streaming change has to retire buffers and is a
 * full resync. Ordering is ignored because streaming reorders the resident map.
 */
export function classifyChunkUpdate(residentKeys, incomingKeys) {
  if (residentKeys === null || residentKeys === undefined) return "resync";
  const resident = new Set(residentKeys);
  const incoming = new Set(incomingKeys);
  if (resident.size !== incoming.size) return "resync";
  for (const key of incoming) {
    if (!resident.has(key)) return "resync";
  }
  return "edit";
}

export function packTerrainChunks(chunks) {
  if (!Array.isArray(chunks)) throw new TypeError("terrain chunks must be an array");
  return chunks.map((chunk) => ({
    key: String(chunk.key),
    opaque: packTerrainLayer(chunk.vertexData?.opaque),
    water: packTerrainLayer(chunk.vertexData?.water),
  }));
}
