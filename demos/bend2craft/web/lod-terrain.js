// Distant terrain in the spirit of the Distant Horizons mod.
//
// Past the streamed chunks the world is drawn from coarse, cached tiles laid
// out as a quadtree of rings: every ring doubles both its reach and its cell
// size, so the cost per ring stays constant however far the view goes. Tiles
// are aligned to a fixed world grid, generated off the main thread from the
// Bend `Horizon.lod_points` sampler, meshed into the ordinary terrain vertex
// format and kept in a cache, so moving only generates the tiles that newly
// come into view. The nearest ring is split per chunk so that each chunk's
// stand-in disappears exactly when the real chunk is drawn, and shows up again
// (instead of a hole) while a chunk is still streaming in.
//
// This module is pure: selection, decoding, meshing and caching. The worker and
// the renderer wiring live in `lod-worker-entry.js` and `game.js`.

import { buildTerrainVertexArrays } from "./terrain-vertex-builder.js";
import { DEFAULT_LOD_DISTANCE, LOD_DISTANCE_CHOICES, normalizeLodDistance } from "./settings.js";

export { DEFAULT_LOD_DISTANCE, LOD_DISTANCE_CHOICES, normalizeLodDistance };

export const LOD_TILE_CELLS = 16;
export const LOD_BASE_STEP = 4;

const GRASS = 3;
const DIRT = 2;
const SAND = 6;
const LEAVES = 4;
const WATER = 7;

/**
 * The ring layout for a render distance. The nearest ring must reach past the
 * streamed square in every direction (the split test uses Euclidean distance,
 * the streamed window is a square), so only ring 0 ever overlaps real chunks.
 */
export function lodLevels({
  renderDistance,
  chunkSize,
  lodDistance,
  baseStep = LOD_BASE_STEP,
  cells = LOD_TILE_CELLS,
}) {
  if (!(lodDistance > 0)) return { baseDistance: 0, levels: [], lodDistance: 0 };
  const streamedReach = (renderDistance + 1.5) * chunkSize * Math.SQRT2;
  const baseDistance = Math.max(8 * chunkSize, Math.ceil(streamedReach / chunkSize) * chunkSize);
  const levels = [];
  for (let level = 0; ; level += 1) {
    const step = baseStep * 2 ** level;
    const distance = baseDistance * 2 ** level;
    levels.push({ level, step, tileSize: cells * step, distance });
    if (distance >= lodDistance || level >= 10) break;
  }
  return { baseDistance, levels, lodDistance: Math.max(lodDistance, baseDistance) };
}

function rectDistance(x, z, minX, minZ, size) {
  const dx = Math.max(minX - x, 0, x - (minX + size));
  const dz = Math.max(minZ - z, 0, z - (minZ + size));
  return Math.hypot(dx, dz);
}

export function lodTileKey(level, tileX, tileZ) {
  return `${level}:${tileX},${tileZ}`;
}

function tileAt(levels, level, tileX, tileZ, cameraX, cameraZ) {
  const { step, tileSize } = levels[level];
  const originX = tileX * tileSize;
  const originZ = tileZ * tileSize;
  return {
    key: lodTileKey(level, tileX, tileZ),
    level,
    tileX,
    tileZ,
    step,
    tileSize,
    originX,
    originZ,
    distance: rectDistance(cameraX, cameraZ, originX, originZ, tileSize),
  };
}

/**
 * Pick the tiles to draw around the camera.
 *
 * A tile splits into its four children while the camera is closer than the
 * next finer ring's reach; otherwise it is a leaf. Roots are the coarsest tiles
 * within the view distance. This covers the disc exactly once: no overlaps, no
 * holes. `isReady(key)` lets a node that should split keep drawing itself while
 * any of its children is still generating, so moving never opens a hole where a
 * coarser tile is already cached.
 *
 * Returns `draw` (tiles to render now) and `want` (leaf tiles that should
 * exist, nearest first).
 */
export function selectLodTiles({ cameraX, cameraZ, layout, isReady = () => true }) {
  const { levels, lodDistance } = layout;
  const draw = [];
  const want = [];
  if (levels.length === 0) return { draw, want };
  const top = levels.length - 1;

  function resolve(tile) {
    const split = tile.level > 0 && tile.distance < levels[tile.level - 1].distance;
    if (!split) {
      want.push(tile);
      return isReady(tile.key) ? [tile] : null;
    }
    const parts = [];
    let complete = true;
    for (let dz = 0; dz < 2; dz += 1) {
      for (let dx = 0; dx < 2; dx += 1) {
        const child = tileAt(levels, tile.level - 1, tile.tileX * 2 + dx, tile.tileZ * 2 + dz, cameraX, cameraZ);
        const resolved = resolve(child);
        if (resolved === null) complete = false;
        else parts.push(...resolved);
      }
    }
    if (complete) return parts;
    if (isReady(tile.key)) return [tile];
    return parts.length > 0 ? parts : null;
  }

  const { tileSize } = levels[top];
  const minX = Math.floor((cameraX - lodDistance) / tileSize);
  const maxX = Math.floor((cameraX + lodDistance) / tileSize);
  const minZ = Math.floor((cameraZ - lodDistance) / tileSize);
  const maxZ = Math.floor((cameraZ + lodDistance) / tileSize);
  for (let tileZ = minZ; tileZ <= maxZ; tileZ += 1) {
    for (let tileX = minX; tileX <= maxX; tileX += 1) {
      const root = tileAt(levels, top, tileX, tileZ, cameraX, cameraZ);
      if (root.distance >= lodDistance) continue;
      const resolved = resolve(root);
      if (resolved !== null) draw.push(...resolved);
    }
  }
  want.sort((a, b) => a.distance - b.distance || a.level - b.level);
  return { draw, want };
}

/** The world-space sample point of every cell of a tile, row by row. */
export function lodSamplePoints(tile, cells = LOD_TILE_CELLS) {
  const points = [];
  const half = Math.floor(tile.step / 2);
  for (let row = 0; row < cells; row += 1) {
    for (let column = 0; column < cells; column += 1) {
      points.push([tile.originX + column * tile.step + half, tile.originZ + row * tile.step + half]);
    }
  }
  return points;
}

/** Unpacks one `Horizon.lod_points` value. */
export function decodeLodSample(value) {
  const encoded = Number(value) >>> 0;
  return {
    ground: encoded & 0xff,
    surface: (encoded >>> 8) & 0xff,
    canopy: (encoded >>> 16) & 0xff,
    water: ((encoded >>> 24) & 1) === 1,
  };
}

function columnOf(sample, waterSurface) {
  const canopy = sample.canopy > 0;
  return {
    ground: sample.ground,
    groundBlock: sample.surface === SAND ? SAND : GRASS,
    top: canopy ? Math.max(sample.canopy, sample.ground) : sample.ground,
    topBlock: canopy ? LEAVES : (sample.surface === SAND ? SAND : GRASS),
    canopy,
    water: sample.water && !canopy,
    waterSurface,
  };
}

// The block drawn on a wall band. Grass shows its side face only on the top
// block, soil below it, the way a real cliff reads. Coarser rings draw one band
// per wall (grass side for a short step, soil for a cliff): at their distance
// the split is invisible and it would double the wall count.
function wallBands(column, low, high, detailed = true) {
  const bands = [];
  if (high <= low) return bands;
  if (column.canopy) {
    const leafLow = Math.max(low, column.ground);
    if (high > leafLow) bands.push([leafLow, high, LEAVES]);
    high = Math.min(high, column.ground);
    if (high <= low) return bands;
  }
  if (column.groundBlock === GRASS && !detailed) {
    bands.push([low, high, high === column.ground && high - low <= 2 ? GRASS : DIRT]);
  } else if (column.groundBlock === GRASS) {
    const grassLow = Math.max(low, high - 1);
    if (high === column.ground) {
      bands.push([grassLow, high, GRASS]);
      if (grassLow > low) bands.push([low, grassLow, DIRT]);
    } else {
      bands.push([low, high, DIRT]);
    }
  } else {
    bands.push([low, high, SAND]);
  }
  return bands;
}

function quad(faceIndex, fixed, u, v, width, height, block, x, z, extra = null) {
  return {
    faceIndex,
    fixed,
    u,
    v,
    width,
    height,
    block,
    x,
    z,
    light: 15,
    lod: true,
    ...(extra ?? {}),
  };
}

/**
 * Mesh one tile of samples into sections of terrain quads.
 *
 * Tops are merged into rectangles; walls run from each column down to its lower
 * neighbour. A wall at the tile border has no neighbour sample, so it becomes a
 * skirt that reaches down to `skirtFloor`, which hides the seams between tiles
 * of different rings. `sectionCells` splits the tile into square sections (the
 * nearest ring uses one section per chunk).
 */
export function buildLodTileMesh({
  tile,
  samples,
  cells = LOD_TILE_CELLS,
  sectionCells = cells,
  chunkSize = 16,
  waterSurface = 8,
  skirtFloor = 2,
}) {
  if (!tile || !Number.isInteger(tile.step) || tile.step < 1) throw new TypeError("tile must carry an integer step");
  if (samples.length < cells * cells) throw new RangeError("tile samples are incomplete");
  if (!Number.isInteger(sectionCells) || sectionCells < 1 || cells % sectionCells !== 0) {
    throw new RangeError("sectionCells must divide the tile");
  }
  const { step, originX, originZ } = tile;
  const columns = new Array(cells * cells);
  for (let index = 0; index < cells * cells; index += 1) {
    columns[index] = columnOf(decodeLodSample(samples[index]), waterSurface);
  }
  const at = (column, row) => (column < 0 || row < 0 || column >= cells || row >= cells
    ? null
    : columns[column + row * cells]);

  const sections = [];
  for (let sectionRow = 0; sectionRow < cells; sectionRow += sectionCells) {
    for (let sectionColumn = 0; sectionColumn < cells; sectionColumn += sectionCells) {
      const quads = [];
      // Tops: merge equal runs along x, then stack identical runs along z.
      let open = new Map();
      const closeAll = (keep) => {
        for (const [key, rect] of open) {
          if (keep.has(key)) continue;
          quads.push(rect.quad);
          open.delete(key);
        }
      };
      for (let row = sectionRow; row < sectionRow + sectionCells; row += 1) {
        const seen = new Set();
        let column = sectionColumn;
        while (column < sectionColumn + sectionCells) {
          const first = at(column, row);
          let end = column + 1;
          while (end < sectionColumn + sectionCells) {
            const next = at(end, row);
            if (next.top !== first.top || next.topBlock !== first.topBlock) break;
            end += 1;
          }
          const key = `${column}:${end}:${first.top}:${first.topBlock}`;
          const rect = open.get(key);
          if (rect !== undefined && rect.lastRow === row - 1) {
            rect.quad.height += step;
            rect.lastRow = row;
          } else {
            if (rect !== undefined) quads.push(rect.quad);
            const x = originX + column * step;
            const z = originZ + row * step;
            open.set(key, {
              lastRow: row,
              quad: quad(0, first.top, x, z, (end - column) * step, step, first.topBlock, x, z),
            });
          }
          seen.add(key);
          column = end;
        }
        closeAll(seen);
      }
      closeAll(new Set());
      open = null;

      // Water surfaces, merged along x.
      for (let row = sectionRow; row < sectionRow + sectionCells; row += 1) {
        let column = sectionColumn;
        while (column < sectionColumn + sectionCells) {
          const first = at(column, row);
          if (!first.water) {
            column += 1;
            continue;
          }
          let end = column + 1;
          while (end < sectionColumn + sectionCells && at(end, row).water) end += 1;
          const x = originX + column * step;
          const z = originZ + row * step;
          const depth = Math.max(0, waterSurface - first.ground);
          quads.push(quad(0, waterSurface, x, z, (end - column) * step, step, WATER, x, z, { waterDepthCells: depth }));
          column = end;
        }
      }

      // Walls, one direction at a time, merged along the edge.
      const directions = [
        { faceIndex: 2, dx: 1, dz: 0 },
        { faceIndex: 3, dx: -1, dz: 0 },
        { faceIndex: 4, dx: 0, dz: 1 },
        { faceIndex: 5, dx: 0, dz: -1 },
      ];
      for (const { faceIndex, dx, dz } of directions) {
        const alongX = dz !== 0;
        for (let lane = 0; lane < sectionCells; lane += 1) {
          // The bands of the current run; a cell whose bands match extends
          // every one of them, anything else closes the run.
          let pending = [];
          const flush = () => {
            quads.push(...pending);
            pending = [];
          };
          for (let offset = 0; offset < sectionCells; offset += 1) {
            const column = sectionColumn + (alongX ? offset : lane);
            const row = sectionRow + (alongX ? lane : offset);
            const self = at(column, row);
            const neighbor = at(column + dx, row + dz);
            const low = neighbor === null ? Math.min(skirtFloor, self.top) : neighbor.top;
            const bands = wallBands(self, low, self.top, tile.level === 0);
            const continues = bands.length > 0
              && bands.length === pending.length
              && bands.every(([bandLow, bandHigh, block], index) => pending[index].v === bandLow
                && pending[index].height === bandHigh - bandLow
                && pending[index].block === block);
            if (continues) {
              for (const wall of pending) wall.width += step;
              continue;
            }
            flush();
            pending = bands.map(([bandLow, bandHigh, block]) => wallQuad(faceIndex, column, row, bandLow, bandHigh, block));
          }
          flush();
        }
      }

      const minX = originX + sectionColumn * step;
      const minZ = originZ + sectionRow * step;
      sections.push({
        key: tile.level === 0
          ? `lod:${Math.floor(minX / chunkSize)},${Math.floor(minZ / chunkSize)}`
          : `lod${tile.level}:${tile.tileX},${tile.tileZ}`,
        chunkKey: tile.level === 0 ? `${Math.floor(minX / chunkSize)},${Math.floor(minZ / chunkSize)}` : null,
        vertexData: buildTerrainVertexArrays(quads),
      });
    }
  }
  return sections;

  function wallQuad(faceIndex, column, row, low, high, block) {
    const x = originX + column * step;
    const z = originZ + row * step;
    switch (faceIndex) {
      case 2:
        return quad(2, x + step, z, low, step, high - low, block, x, z);
      case 3:
        return quad(3, x, z, low, step, high - low, block, x, z);
      case 4:
        return quad(4, z + step, x, low, step, high - low, block, x, z);
      default:
        return quad(5, z, x, low, step, high - low, block, x, z);
    }
  }
}

/** The transferable buffers of a set of meshed sections. */
export function lodSectionTransferables(sections) {
  const buffers = [];
  for (const section of sections) {
    for (const layer of [section.vertexData?.opaque, section.vertexData?.water]) {
      if (!layer) continue;
      for (const name of ["positions", "colors", "lights", "normals", "uvs", "materials", "tiles"]) {
        const array = layer[name];
        if (ArrayBuffer.isView(array) && !buffers.includes(array.buffer)) buffers.push(array.buffer);
      }
    }
  }
  return buffers;
}

/**
 * The main-thread side: which tiles to draw, which to request, and the cache.
 *
 * `requestTile(job)` must eventually answer with `receive(job.id, sections)`.
 * The renderer asks for `sections(maskedChunkKeys)` on every publication; the
 * section objects keep their identity so per-chunk buffers are reused.
 */
export function createLodTerrain({
  requestTile,
  chunkSize = 16,
  cells = LOD_TILE_CELLS,
  baseStep = LOD_BASE_STEP,
  maxInFlight = 2,
  cacheLimit = 512,
}) {
  if (typeof requestTile !== "function") throw new TypeError("LOD terrain needs a tile request function");
  const cache = new Map();
  const inFlight = new Map();
  let layout = { baseDistance: 0, levels: [], lodDistance: 0 };
  let selection = { draw: [], want: [] };
  let generation = 0;
  let nextId = 0;
  let camera = null;
  let drawKey = "";
  let generated = 0;

  function configure({ renderDistance, lodDistance }) {
    layout = lodLevels({ renderDistance, chunkSize, lodDistance, baseStep, cells });
    generation += 1;
    cache.clear();
    inFlight.clear();
    selection = { draw: [], want: [] };
    drawKey = "";
    camera = null;
    return layout;
  }

  function reselect() {
    if (camera === null) return false;
    selection = selectLodTiles({
      cameraX: camera[0],
      cameraZ: camera[1],
      layout,
      isReady: (key) => cache.has(key),
    });
    const nextKey = selection.draw.map((tile) => tile.key).join("|");
    const changed = nextKey !== drawKey;
    drawKey = nextKey;
    return changed;
  }

  function pump() {
    for (const tile of selection.want) {
      if (inFlight.size >= maxInFlight) break;
      if (cache.has(tile.key)) continue;
      let busy = false;
      for (const job of inFlight.values()) {
        if (job.key === tile.key) {
          busy = true;
          break;
        }
      }
      if (busy) continue;
      const id = nextId += 1;
      const job = {
        id,
        generation,
        key: tile.key,
        level: tile.level,
        tileX: tile.tileX,
        tileZ: tile.tileZ,
        step: tile.step,
        originX: tile.originX,
        originZ: tile.originZ,
        cells,
        sectionCells: tile.level === 0 ? Math.max(1, Math.floor(chunkSize / tile.step)) : cells,
      };
      inFlight.set(id, job);
      requestTile(job);
    }
  }

  function evict() {
    if (cache.size <= cacheLimit) return;
    const keep = new Set(selection.draw.map((tile) => tile.key));
    for (const tile of selection.want) keep.add(tile.key);
    for (const [key, entry] of [...cache.entries()].sort((a, b) => a[1].used - b[1].used)) {
      if (cache.size <= cacheLimit) break;
      if (!keep.has(key)) cache.delete(key);
    }
  }

  /**
   * Move the camera. Selection only changes when the camera crosses a base
   * cell, so calling this every frame is cheap. Returns true when the drawn
   * set changed and the terrain should be republished.
   */
  function update(cameraX, cameraZ) {
    if (layout.levels.length === 0) return false;
    const quantum = baseStep * 4;
    const snapped = [Math.floor(cameraX / quantum) * quantum + quantum / 2, Math.floor(cameraZ / quantum) * quantum + quantum / 2];
    if (camera !== null && camera[0] === snapped[0] && camera[1] === snapped[1]) {
      pump();
      return false;
    }
    camera = snapped;
    const changed = reselect();
    pump();
    return changed;
  }

  /** A worker answer. Returns true when the drawn set changed. */
  function receive(id, sections) {
    const job = inFlight.get(id);
    if (job === undefined) return false;
    inFlight.delete(id);
    if (job.generation !== generation || !Array.isArray(sections)) {
      pump();
      return false;
    }
    cache.set(job.key, {
      used: generated += 1,
      sections: sections.map((section) => ({ ...section, lod: true })),
    });
    const changed = reselect();
    evict();
    pump();
    return changed;
  }

  function fail(id) {
    inFlight.delete(id);
  }

  function sections(maskedChunkKeys = new Set()) {
    const out = [];
    for (const tile of selection.draw) {
      const entry = cache.get(tile.key);
      if (entry === undefined) continue;
      entry.used = generated += 1;
      for (const section of entry.sections) {
        if (section.chunkKey !== null && maskedChunkKeys.has(section.chunkKey)) continue;
        out.push(section);
      }
    }
    return out;
  }

  return {
    configure,
    update,
    receive,
    fail,
    sections,
    get layout() { return layout; },
    stats: () => ({
      cachedTiles: cache.size,
      inFlight: inFlight.size,
      drawnTiles: selection.draw.length,
      wantedTiles: selection.want.length,
      missingTiles: selection.want.filter((tile) => !cache.has(tile.key)).length,
      levels: layout.levels.length,
      lodDistance: layout.lodDistance,
    }),
  };
}
