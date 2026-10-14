import {
  ATLAS_COLUMNS,
  ATLAS_HEIGHT,
  ATLAS_MIPMAP_SAFE_LEVELS,
  ATLAS_TEXTURES,
  ATLAS_TILE_GUTTER,
  ATLAS_TILE_SIZE,
  ATLAS_TILE_STRIDE,
  ATLAS_WIDTH,
  createAtlasCanvas,
  atlasCellOrigin,
  atlasMipLevelGeometry,
  atlasTileUV,
  foreignTileContamination,
  maxChannelDelta,
} from "./texture-atlas.js";

/** UV rect of a tile's whole padded cell, gutter included. */
function atlasCellRect(tile) {
  const { x, y } = atlasCellOrigin(tile);
  return [
    x / ATLAS_WIDTH,
    y / ATLAS_HEIGHT,
    (x + ATLAS_TILE_STRIDE) / ATLAS_WIDTH,
    (y + ATLAS_TILE_STRIDE) / ATLAS_HEIGHT,
  ];
}

const RESOURCES = new WeakMap();

function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(`Atlas probe shader compilation failed: ${gl.getShaderInfoLog(shader)}`);
  }
  return shader;
}

function resourcesFor(gl) {
  let resources = RESOURCES.get(gl);
  if (resources !== undefined) return resources;
  const vertex = compileShader(gl, gl.VERTEX_SHADER, `
    attribute vec2 aPosition;
    attribute vec2 aUv;
    varying vec2 vUv;
    void main() {
      vUv = aUv;
      gl_Position = vec4(aPosition, 0.0, 1.0);
    }
  `);
  const fragment = compileShader(gl, gl.FRAGMENT_SHADER, `
    precision mediump float;
    uniform sampler2D uAtlas;
    varying vec2 vUv;
    void main() {
      gl_FragColor = texture2D(uAtlas, vUv);
    }
  `);
  const program = gl.createProgram();
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error(`Atlas probe program link failed: ${gl.getProgramInfoLog(program)}`);
  }
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  resources = {
    program,
    positionBuffer: gl.createBuffer(),
    uvBuffer: gl.createBuffer(),
    framebuffer: gl.createFramebuffer(),
    targetTexture: gl.createTexture(),
    positionLocation: gl.getAttribLocation(program, "aPosition"),
    uvLocation: gl.getAttribLocation(program, "aUv"),
    atlasLocation: gl.getUniformLocation(program, "uAtlas"),
  };
  RESOURCES.set(gl, resources);
  return resources;
}

export function readAtlasTilePixels(gl, atlasTexture, tile, size = ATLAS_TILE_SIZE, level = 0) {
  return readAtlasRegion(gl, atlasTexture, tile, size, level, false);
}

// Reads a tile's whole padded cell, gutter included, which is what the
// contamination probe needs to compare against an isolated copy.
export function readAtlasCellPixels(gl, atlasTexture, tile, size = ATLAS_TILE_STRIDE, level = 0) {
  return readAtlasRegion(gl, atlasTexture, tile, size, level, true);
}

function readAtlasRegion(gl, atlasTexture, tile, size, level, wholeCell) {
  if (!Number.isInteger(tile) || tile < 0 || !Number.isInteger(size) || size < 1) {
    throw new RangeError("atlas probe tile and size must be positive integers");
  }
  if (!Number.isInteger(level) || level < 0) {
    throw new RangeError("atlas probe mip level must be a non-negative integer");
  }
  const resources = resourcesFor(gl);
  const rect = wholeCell ? atlasCellRect(tile) : atlasTileUV(tile);
  const [u0, v0, u1, v1] = rect;
  const uv = [u0, v0, u1, v0, u1, v1, u0, v1];
  const positions = new Float32Array([
    -1, -1, 1, -1, 1, 1,
    -1, -1, 1, 1, -1, 1,
  ]);
  const uvs = new Float32Array([
    uv[0], uv[1], uv[2], uv[3], uv[4], uv[5],
    uv[0], uv[1], uv[4], uv[5], uv[6], uv[7],
  ]);
  const pixels = new Uint8Array(size * size * 4);

  gl.bindTexture(gl.TEXTURE_2D, resources.targetTexture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, size, size, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.bindFramebuffer(gl.FRAMEBUFFER, resources.framebuffer);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, resources.targetTexture, 0);
  if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
    throw new Error("Atlas probe framebuffer is incomplete");
  }
  gl.viewport(0, 0, size, size);
  gl.disable(gl.DEPTH_TEST);
  gl.disable(gl.BLEND);
  const cullEnabled = typeof gl.isEnabled === "function" ? gl.isEnabled(gl.CULL_FACE) : false;
  gl.disable(gl.CULL_FACE);
  gl.useProgram(resources.program);
  gl.bindBuffer(gl.ARRAY_BUFFER, resources.positionBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STREAM_DRAW);
  gl.enableVertexAttribArray(resources.positionLocation);
  gl.vertexAttribPointer(resources.positionLocation, 2, gl.FLOAT, false, 0, 0);
  gl.bindBuffer(gl.ARRAY_BUFFER, resources.uvBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, uvs, gl.STREAM_DRAW);
  gl.enableVertexAttribArray(resources.uvLocation);
  gl.vertexAttribPointer(resources.uvLocation, 2, gl.FLOAT, false, 0, 0);
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, atlasTexture);
  const previousMinFilter = typeof gl.getTexParameter === "function"
    ? gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER)
    : null;
  const previousMagFilter = typeof gl.getTexParameter === "function"
    ? gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER)
    : null;
  const previousBaseLevel = typeof gl.getTexParameter === "function" && gl.TEXTURE_BASE_LEVEL !== undefined
    ? gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_BASE_LEVEL)
    : null;
  const previousMaxLevel = typeof gl.getTexParameter === "function" && gl.TEXTURE_MAX_LEVEL !== undefined
    ? gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL)
    : null;
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  if (gl.TEXTURE_BASE_LEVEL !== undefined) gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_BASE_LEVEL, level);
  if (gl.TEXTURE_MAX_LEVEL !== undefined) gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, level);
  gl.uniform1i(resources.atlasLocation, 0);
  gl.drawArrays(gl.TRIANGLES, 0, 6);
  gl.readPixels(0, 0, size, size, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
  if (previousMinFilter !== null) gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, previousMinFilter);
  if (previousMagFilter !== null) gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, previousMagFilter);
  if (previousBaseLevel !== null) gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_BASE_LEVEL, previousBaseLevel);
  if (previousMaxLevel !== null) gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, previousMaxLevel);
  if (cullEnabled) gl.enable(gl.CULL_FACE);
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
  gl.enable(gl.DEPTH_TEST);
  gl.depthMask(true);
  return Array.from(pixels);
}

/**
 * Foreign Tile Contamination probe. For every tile and mip level it compares the
 * cell read back from the full atlas against the same cell read back from a
 * reference texture that holds only that tile. A difference means another
 * tile's material reached into this one.
 *
 * The reference texture is built once and reused: only the probed cell is
 * re-uploaded per tile, so the whole gate stays a bounded boot cost instead of
 * one full atlas upload per tile.
 */
export function probeAtlasMipmapSafety(
  gl,
  atlasTexture,
  tiles,
  levels = ATLAS_MIPMAP_SAFE_LEVELS,
  gutter = ATLAS_TILE_GUTTER,
) {
  const contaminated = [];
  let worstDelta = 0;
  const reference = createIsolationReference(gl);
  if (reference === null) {
    return { safe: false, reason: "the WebGL context cannot build an isolation reference", levels: [...levels], contaminated: [] };
  }
  try {
    for (const tile of tiles) {
      const cell = Uint8Array.from(
        readAtlasCellPixels(gl, atlasTexture, tile, ATLAS_TILE_STRIDE, 0),
      );
      writeIsolationCell(gl, reference, tile, cell);
      for (const level of levels) {
        const geometry = atlasMipLevelGeometry(gutter, ATLAS_TILE_SIZE, level);
        if (geometry.size < 1) continue;
        const observed = Uint8Array.from(
          readAtlasCellPixels(gl, atlasTexture, tile, geometry.size, level),
        );
        const expected = Uint8Array.from(
          readAtlasCellPixels(gl, reference, tile, geometry.size, level),
        );
        const delta = maxChannelDelta(observed, expected);
        if (delta > worstDelta) worstDelta = delta;
        if (foreignTileContamination(
          { size: geometry.size, pixels: observed },
          { size: geometry.size, pixels: expected },
        )) {
          contaminated.push({ tile, level, maxDelta: delta });
        }
      }
    }
  } finally {
    gl.deleteTexture?.(reference);
    gl.bindTexture(gl.TEXTURE_2D, null);
  }
  return { safe: contaminated.length === 0, levels: [...levels], contaminated, worstDelta };
}

function createIsolationReference(gl) {
  if (typeof gl.createTexture !== "function" || typeof gl.generateMipmap !== "function") return null;
  if (typeof gl.texSubImage2D !== "function" || typeof gl.texImage2D !== "function") return null;
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(
    gl.TEXTURE_2D,
    0,
    gl.RGBA,
    ATLAS_WIDTH,
    ATLAS_HEIGHT,
    0,
    gl.RGBA,
    gl.UNSIGNED_BYTE,
    new Uint8Array(ATLAS_WIDTH * ATLAS_HEIGHT * 4),
  );
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR ?? gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  return texture;
}

// Opaque black elsewhere, and only the probed tile's cell carries material, so
// the reference mip chain is exactly what this tile would produce in isolation.
function writeIsolationCell(gl, reference, tile, cell) {
  const { x, y } = atlasCellOrigin(tile);
  const black = new Uint8Array(ATLAS_TILE_STRIDE * ATLAS_TILE_STRIDE * 4);
  gl.bindTexture(gl.TEXTURE_2D, reference);
  gl.texSubImage2D(
    gl.TEXTURE_2D,
    0,
    x,
    y,
    ATLAS_TILE_STRIDE,
    ATLAS_TILE_STRIDE,
    gl.RGBA,
    gl.UNSIGNED_BYTE,
    black,
  );
  gl.texSubImage2D(
    gl.TEXTURE_2D,
    0,
    x,
    y,
    ATLAS_TILE_STRIDE,
    ATLAS_TILE_STRIDE,
    gl.RGBA,
    gl.UNSIGNED_BYTE,
    cell,
  );
  gl.generateMipmap(gl.TEXTURE_2D);
}

/**
 * Build the mip chain on a throwaway texture, read it back, and report whether
 * the padded atlas is free of foreign tile contamination. The shipping atlas
 * texture is only created with mipmaps after this returns a clean verdict, so a
 * contaminated atlas can never reach the screen.
 */
export function certifyAtlasMipmaps(
  gl,
  blockColors,
  { tiles, levels = ATLAS_MIPMAP_SAFE_LEVELS, gutter = ATLAS_TILE_GUTTER } = {},
) {
  // Contamination is a property of the padded layout, not of one material, so
  // the probe walks a spread of tiles that includes each atlas row.
  const probeTiles = tiles ?? spreadProbeTiles(ATLAS_TEXTURES.length, ATLAS_COLUMNS);
  if (typeof gl.createTexture !== "function" || typeof gl.generateMipmap !== "function") {
    return {
      safe: false,
      reason: "the WebGL context cannot build a mip chain",
      levels: [...levels],
      contaminated: [],
    };
  }
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, createAtlasCanvas(blockColors));
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR ?? gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.generateMipmap(gl.TEXTURE_2D);
  const verdict = probeAtlasMipmapSafety(gl, texture, probeTiles, levels, gutter);
  gl.deleteTexture?.(texture);
  gl.bindTexture(gl.TEXTURE_2D, null);
  return { ...verdict, tiles: probeTiles.length };
}

export function spreadProbeTiles(textureCount, columns) {
  const step = Math.max(1, Math.floor(textureCount / 16));
  const tiles = [];
  for (let tile = 0; tile < textureCount; tile += step) tiles.push(tile);
  // Keep the first two tiles of every row so horizontal neighbours are covered.
  for (let row = 0; row * columns < textureCount; row += 1) {
    for (let column = 0; column < 2; column += 1) {
      const tile = row * columns + column;
      if (tile < textureCount) tiles.push(tile);
    }
  }
  return [...new Set(tiles)].sort((a, b) => a - b);
}
