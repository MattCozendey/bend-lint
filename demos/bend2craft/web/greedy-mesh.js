import { blockFaceTileAt } from "./texture-atlas.js";
import { WATER_DEPTH_MAX } from "./terrain-presentation.js";

export const LEAF_FACE_INSET = 0.025;

const FACE_DIRECTIONS = [
  [0, 1, 0],
  [0, -1, 0],
  [1, 0, 0],
  [-1, 0, 0],
  [0, 0, 1],
  [0, 0, -1],
];

/**
 * Outward face normal per FACE_DIRECTIONS index. The presentation shaders light
 * every surface from a real sun direction, so the mesh has to carry the normal
 * instead of inferring a fake face shade from the vertex colour.
 */
export const FACE_NORMALS = Object.freeze(FACE_DIRECTIONS.map((direction) => Object.freeze([...direction])));

export function faceNormal(faceIndex) {
  return FACE_NORMALS[faceIndex] ?? FACE_NORMALS[0];
}

function cellKey(u, v) {
  return `${u},${v}`;
}

function planeCell(faceIndex, x, y, z) {
  switch (faceIndex) {
    case 0:
      return { fixed: y + 1, u: x, v: z };
    case 1:
      return { fixed: y, u: x, v: z };
    case 2:
      return { fixed: x + 1, u: z, v: y };
    case 3:
      return { fixed: x, u: z, v: y };
    case 4:
      return { fixed: z + 1, u: x, v: y };
    case 5:
      return { fixed: z, u: x, v: y };
    default:
      throw new RangeError(`Unknown face index: ${faceIndex}`);
  }
}

const AO_MERGE_EPSILON = 0.3;

function sameAo(a, b) {
  if (a === b) return true;
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
  return a.every((value, index) => Math.abs(value - b[index]) <= AO_MERGE_EPSILON);
}

function sameCell(mask, visited, u, v, block, light, tile, ao, waterDepthCells) {
  const key = cellKey(u, v);
  const cell = mask.get(key);
  return !visited.has(key)
    && cell?.block === block
    && cell?.light === light
    && cell?.tile === tile
    && cell?.waterDepthCells === waterDepthCells
    && sameAo(cell?.ao, ao);
}

function mergePlane(faceIndex, fixed, mask) {
  const cells = [...mask.entries()]
    .map(([key, cell]) => {
      const [u, v] = key.split(",").map(Number);
      return { u, v, ...cell };
    })
    .sort((a, b) => a.v - b.v || a.u - b.u);
  const visited = new Set();
  const quads = [];

  for (const start of cells) {
    const startKey = cellKey(start.u, start.v);
    if (visited.has(startKey)) continue;
    const { block, light, tile, ao, waterDepthCells } = start;
    if (block === 4) {
      visited.add(startKey);
      quads.push({
        faceIndex,
        fixed,
        u: start.u,
        v: start.v,
        width: 1,
        height: 1,
        block,
        x: start.x,
        y: start.y,
        z: start.z,
        light,
        waterDepthCells,
        tile,
        ao,
      });
      continue;
    }
    let width = 1;
    while (sameCell(mask, visited, start.u + width, start.v, block, light, tile, ao, waterDepthCells)) width += 1;

    let height = 1;
    while (true) {
      const row = [];
      for (let offset = 0; offset < width; offset += 1) {
        const u = start.u + offset;
        const v = start.v + height;
        if (!sameCell(mask, visited, u, v, block, light, tile, ao, waterDepthCells)) break;
        row.push(cellKey(u, v));
      }
      if (row.length !== width) break;
      height += 1;
    }

    for (let offsetV = 0; offsetV < height; offsetV += 1) {
      for (let offsetU = 0; offsetU < width; offsetU += 1) {
        visited.add(cellKey(start.u + offsetU, start.v + offsetV));
      }
    }
    quads.push({
      faceIndex,
      fixed,
      u: start.u,
      v: start.v,
      width,
      height,
      block,
      x: start.x,
      y: start.y,
      z: start.z,
      light,
      waterDepthCells,
      tile,
      ao,
    });
  }
  return quads;
}

const FLUID_BLOCKS = new Set([7, 21, 24]);

function isFluid(block) {
  return FLUID_BLOCKS.has(block);
}

// Water depth is sampled with a bounded downward scan from the surface cell, so
// it costs at most WATER_DEPTH_MAX lookups per water surface face and never
// walks the whole column. The scan stops at the first solid floor.
export function waterColumnDepth(x, y, z, blockAt, isActive, maxDepth) {
  let fluid = 0;
  for (let step = 1; step <= maxDepth; step += 1) {
    const below = y - step;
    if (below < 0) break;
    const block = isActive(x, z) ? Number(blockAt(x, below, z) ?? 0) : 0;
    if (!isFluid(block)) break;
    fluid = step;
  }
  return fluid;
}

function isOpaque(block) {
  return block !== 0 && !isFluid(block);
}

function occupied(blockAt, isActive, x, y, z) {
  return isActive(x, z) && isOpaque(Number(blockAt(x, y, z) ?? 0));
}

function topCornerAmbient(quad, cornerIndex, blockAt, isActive) {
  const minX = quad.u;
  const maxX = quad.u + quad.width;
  const minZ = quad.v;
  const maxZ = quad.v + quad.height;
  const vertexX = cornerIndex === 0 || cornerIndex === 3 ? minX : maxX;
  const vertexZ = cornerIndex === 0 || cornerIndex === 1 ? minZ : maxZ;
  const wall = (x, z) => occupied(blockAt, isActive, x, quad.y, z)
    && occupied(blockAt, isActive, x, quad.y + 1, z);
  const sideX = wall(
    vertexX === minX ? vertexX - 1 : vertexX,
    Math.floor(vertexZ),
  );
  const sideZ = wall(
    Math.floor(vertexX),
    vertexZ === minZ ? vertexZ - 1 : vertexZ,
  );
  const diagonal = wall(
    vertexX === minX ? vertexX - 1 : vertexX,
    vertexZ === minZ ? vertexZ - 1 : vertexZ,
  );
  const overheadX = occupied(
    blockAt,
    isActive,
    vertexX,
    quad.y + 1,
    Math.floor(vertexZ),
  );
  const overheadZ = occupied(
    blockAt,
    isActive,
    Math.floor(vertexX),
    quad.y + 1,
    vertexZ,
  );
  const overheadDiagonal = occupied(
    blockAt,
    isActive,
    vertexX,
    quad.y + 1,
    vertexZ,
  );
  const sideOcclusion = sideX && sideZ
    ? 0.42
    : (sideX ? 0.16 : 0) + (sideZ ? 0.16 : 0) + (diagonal ? 0.1 : 0);
  const overheadOcclusion = overheadX && overheadZ
    ? 0.32
    : (overheadX ? 0.16 : 0) + (overheadZ ? 0.16 : 0) + (overheadDiagonal ? 0.1 : 0);
  return Math.max(0.4, (1 - sideOcclusion) * (1 - overheadOcclusion));
}

function ambientCorners(quad, blockAt, isActive) {
  if (quad.faceIndex !== 0 || isFluid(quad.block)) return [1, 1, 1, 1];
  return [0, 1, 2, 3].map((cornerIndex) => topCornerAmbient(quad, cornerIndex, blockAt, isActive));
}

export function buildGreedyQuads({ forEachLoadedBlock, blockAt, isActive, lightAt = null }) {
  if (typeof forEachLoadedBlock !== "function" || typeof blockAt !== "function" || typeof isActive !== "function") {
    throw new TypeError("greedy meshing requires forEachLoadedBlock, blockAt and isActive");
  }

  const planes = new Map();
  let blockCount = 0;
  forEachLoadedBlock((x, y, z, value) => {
    const block = Number(value);
    if (block === 0) return;
    blockCount += 1;
    for (let faceIndex = 0; faceIndex < FACE_DIRECTIONS.length; faceIndex += 1) {
      const [dx, dy, dz] = FACE_DIRECTIONS[faceIndex];
      const neighborX = x + dx;
      const neighborY = y + dy;
      const neighborZ = z + dz;
      const neighbor = isActive(neighborX, neighborZ) ? Number(blockAt(neighborX, neighborY, neighborZ) ?? 0) : 0;
      // Fluids are transparent: terrain under a fluid keeps its faces,
      // while same-fluid interior faces stay culled.
      if (isOpaque(neighbor) || (neighbor === block && isFluid(block))) continue;
      const { fixed, u, v } = planeCell(faceIndex, x, y, z);
      const light = typeof lightAt === "function"
        ? Number(lightAt(neighborX, neighborY, neighborZ))
        : 15;
      const planeKey = `${faceIndex}:${fixed}`;
      let mask = planes.get(planeKey);
      if (mask === undefined) {
        mask = new Map();
        planes.set(planeKey, mask);
      }
      const cellQuad = { faceIndex, fixed, u, v, width: 1, height: 1, block, x, y, z };
      // Only the visible top face of a water column carries depth; side faces
      // are the same body of water and stay at depth zero.
      const waterDepthCells = block === 7 && faceIndex === 0
        ? waterColumnDepth(x, y, z, blockAt, isActive, WATER_DEPTH_MAX)
        : 0;
      mask.set(cellKey(u, v), {
        block,
        x,
        y,
        z,
        light,
        waterDepthCells,
        tile: blockFaceTileAt(block, faceIndex, x, z),
        ao: ambientCorners(cellQuad, blockAt, isActive),
      });
    }
  });

  const quads = [];
  for (const [planeKey, mask] of planes) {
    const separator = planeKey.indexOf(":");
    const faceIndex = Number(planeKey.slice(0, separator));
    const fixed = Number(planeKey.slice(separator + 1));
    quads.push(...mergePlane(faceIndex, fixed, mask));
  }
  for (const quad of quads) {
    if (quad.ao === undefined) quad.ao = ambientCorners(quad, blockAt, isActive);
  }
  return { blockCount, quads };
}

export function quadCorners(quad) {
  const { faceIndex, fixed, u, v, width, height } = quad;
  // Recessed top surfaces read as soil/water instead of full cubes.
  const topInset = quad.block === 20 ? 1 / 16 : isFluid(quad.block) ? 2 / 16 : 0;
  // Distant (LOD) canopy quads span many blocks and must meet their
  // neighbours edge to edge, so only real leaf cells are inset.
  const faceInset = quad.block === 4 && quad.lod !== true ? LEAF_FACE_INSET : 0;
  const minU = u + faceInset;
  const maxU = u + width - faceInset;
  const minV = v + faceInset;
  const maxV = v + height - faceInset;
  switch (faceIndex) {
    case 0:
      return [[minU, fixed - topInset, minV], [maxU, fixed - topInset, minV], [maxU, fixed - topInset, maxV], [minU, fixed - topInset, maxV]];
    case 1:
      return [[minU, fixed, maxV], [maxU, fixed, maxV], [maxU, fixed, minV], [minU, fixed, minV]];
    case 2:
      return [[fixed, minV, minU], [fixed, minV, maxU], [fixed, maxV - topInset, maxU], [fixed, maxV - topInset, minU]];
    case 3:
      return [[fixed, maxV, maxU], [fixed, maxV, minU], [fixed, minV, minU], [fixed, minV, maxU]];
    case 4:
      return [[maxU, minV, fixed], [minU, minV, fixed], [minU, maxV - topInset, fixed], [maxU, maxV - topInset, fixed]];
    case 5:
      return [[minU, minV, fixed], [maxU, minV, fixed], [maxU, maxV - topInset, fixed], [minU, maxV - topInset, fixed]];
    default:
      throw new RangeError(`Unknown face index: ${faceIndex}`);
  }
}
