import assert from "node:assert/strict";
import {
  DEFAULT_LOD_DISTANCE,
  LOD_TILE_CELLS,
  buildLodTileMesh,
  createLodTerrain,
  decodeLodSample,
  lodLevels,
  lodSamplePoints,
  normalizeLodDistance,
  selectLodTiles,
} from "../web/lod-terrain.js";

const CHUNK = 16;
const encode = ({ ground, surface = 3, canopy = 0, water = false }) =>
  (ground + surface * 256 + canopy * 65536 + (water ? 16777216 : 0)) >>> 0;

// --- settings --------------------------------------------------------------
assert.equal(normalizeLodDistance(1024), 1024);
assert.equal(normalizeLodDistance(0), 0);
assert.equal(normalizeLodDistance(333), DEFAULT_LOD_DISTANCE);
assert.equal(normalizeLodDistance("junk"), DEFAULT_LOD_DISTANCE);

// --- ring layout -----------------------------------------------------------
for (const renderDistance of [2, 4, 8]) {
  const layout = lodLevels({ renderDistance, chunkSize: CHUNK, lodDistance: 1024 });
  const streamedReach = (renderDistance + 1) * CHUNK * Math.SQRT2;
  assert.ok(layout.baseDistance > streamedReach, "ring 0 must reach past every streamed chunk");
  layout.levels.forEach((level, index) => {
    assert.equal(level.step, 4 * 2 ** index);
    assert.equal(level.tileSize, LOD_TILE_CELLS * level.step);
    assert.equal(level.distance, layout.baseDistance * 2 ** index);
  });
  assert.ok(layout.levels.at(-1).distance >= 1024);
  assert.ok(layout.levels.at(-2)?.distance ?? 0 < 1024);
}
assert.deepEqual(lodLevels({ renderDistance: 4, chunkSize: CHUNK, lodDistance: 0 }).levels, []);

// --- selection covers the disc exactly once --------------------------------
function coverage(draw, x, z) {
  return draw.filter((tile) => x >= tile.originX && x < tile.originX + tile.tileSize
    && z >= tile.originZ && z < tile.originZ + tile.tileSize);
}
for (const [cameraX, cameraZ, renderDistance] of [[8, 8, 2], [-300.5, 77.25, 4], [5000, -12000, 8]]) {
  const layout = lodLevels({ renderDistance, chunkSize: CHUNK, lodDistance: 1024 });
  const { draw, want } = selectLodTiles({ cameraX, cameraZ, layout });
  assert.equal(draw.length, want.length, "with every tile ready the leaves are drawn");
  const keys = new Set(draw.map((tile) => tile.key));
  assert.equal(keys.size, draw.length, "no tile is drawn twice");
  for (let dz = -900; dz <= 900; dz += 37) {
    for (let dx = -900; dx <= 900; dx += 41) {
      if (Math.hypot(dx, dz) > 880) continue;
      const hits = coverage(draw, cameraX + dx, cameraZ + dz);
      assert.equal(hits.length, 1, `point ${dx},${dz} must be covered exactly once`);
    }
  }
  // Only ring 0 may touch the streamed square around the camera chunk.
  const chunkX = Math.floor(cameraX / CHUNK);
  const chunkZ = Math.floor(cameraZ / CHUNK);
  const minX = (chunkX - renderDistance) * CHUNK;
  const maxX = (chunkX + renderDistance + 1) * CHUNK;
  const minZ = (chunkZ - renderDistance) * CHUNK;
  const maxZ = (chunkZ + renderDistance + 1) * CHUNK;
  for (const tile of draw) {
    if (tile.level === 0) continue;
    const overlaps = tile.originX < maxX && tile.originX + tile.tileSize > minX
      && tile.originZ < maxZ && tile.originZ + tile.tileSize > minZ;
    assert.equal(overlaps, false, `ring ${tile.level} tile ${tile.key} overlaps streamed chunks`);
  }
  // The request order is nearest first.
  for (let index = 1; index < want.length; index += 1) assert.ok(want[index].distance >= want[index - 1].distance);
}

// A split tile whose children are not generated yet keeps drawing itself.
{
  const layout = lodLevels({ renderDistance: 2, chunkSize: CHUNK, lodDistance: 512 });
  const top = layout.levels.length - 1;
  const readyKeys = new Set();
  const all = selectLodTiles({ cameraX: 0, cameraZ: 0, layout }).draw;
  // Only the coarsest ancestors are cached.
  for (const tile of all) {
    const factor = 2 ** (top - tile.level);
    readyKeys.add(`${top}:${Math.floor(tile.tileX / factor)},${Math.floor(tile.tileZ / factor)}`);
  }
  const partial = selectLodTiles({ cameraX: 0, cameraZ: 0, layout, isReady: (key) => readyKeys.has(key) });
  assert.ok(partial.draw.length > 0);
  assert.ok(partial.draw.every((tile) => tile.level === top), "fallback draws the cached coarse tiles");
  for (let dz = -400; dz <= 400; dz += 50) {
    for (let dx = -400; dx <= 400; dx += 50) {
      if (Math.hypot(dx, dz) > 380) continue;
      assert.equal(coverage(partial.draw, dx, dz).length, 1);
    }
  }
  assert.ok(partial.want.every((tile) => !readyKeys.has(tile.key) || tile.level === top));
}

// --- sample points and decoding ---------------------------------------------
const tile = { level: 0, tileX: -1, tileZ: 2, step: 4, tileSize: 64, originX: -64, originZ: 128 };
const points = lodSamplePoints(tile);
assert.equal(points.length, 256);
assert.deepEqual(points[0], [-62, 130]);
assert.deepEqual(points[17], [-58, 134]);
assert.deepEqual(decodeLodSample(encode({ ground: 9, surface: 6, canopy: 13, water: true })), {
  ground: 9, surface: 6, canopy: 13, water: true,
});

// --- meshing ---------------------------------------------------------------
function quadsOf(section) {
  return (section.vertexData.opaque.quadCount ?? 0) + (section.vertexData.water.quadCount ?? 0);
}
{
  // A flat grass tile: ring 0 is split per chunk, each section is one merged top
  // plus skirts on its tile-border sides only.
  const flat = new Array(256).fill(encode({ ground: 9 }));
  const sections = buildLodTileMesh({ tile, samples: flat, sectionCells: 4, chunkSize: CHUNK });
  assert.equal(sections.length, 16);
  assert.deepEqual(sections[0].chunkKey, "-4,8");
  assert.equal(sections[0].key, "lod:-4,8");
  const interior = sections[5];
  assert.equal(interior.vertexData.opaque.quadCount, 1, "an interior flat section is a single top");
  const corner = sections[0];
  // Two skirt sides, each a grass band and a dirt band below it.
  assert.equal(corner.vertexData.opaque.quadCount, 1 + 2 * 2);
  const positions = interior.vertexData.opaque.positions;
  assert.ok([...positions].filter((_, index) => index % 3 === 1).every((y) => y === 9));
}
{
  // Coarse rings are one section per tile keyed by tile.
  const coarse = { level: 2, tileX: 3, tileZ: -1, step: 16, tileSize: 256, originX: 768, originZ: -256 };
  const samples = new Array(256).fill(0).map((_, index) => encode({ ground: 6 + (index % 16 < 8 ? 0 : 3) }));
  const sections = buildLodTileMesh({ tile: coarse, samples, chunkSize: CHUNK });
  assert.equal(sections.length, 1);
  assert.equal(sections[0].key, "lod2:3,-1");
  assert.equal(sections[0].chunkKey, null);
  // The 3-block step between the halves becomes one merged wall.
  const normals = sections[0].vertexData.opaque.normals;
  let minusX = 0;
  for (let index = 0; index < normals.length; index += 3) if (normals[index] === -1) minusX += 1;
  assert.ok(minusX > 0);
}
{
  // Water columns get a transparent surface at sea level + 1 carrying depth;
  // canopy columns are raised with leaves.
  const mixed = new Array(256).fill(encode({ ground: 5, surface: 6, water: true }));
  mixed[0] = encode({ ground: 10, canopy: 14 });
  const [section] = buildLodTileMesh({
    tile: { level: 1, tileX: 0, tileZ: 0, step: 8, tileSize: 128, originX: 0, originZ: 0 },
    samples: mixed,
    waterSurface: 8,
  });
  assert.ok(section.vertexData.water.quadCount >= 1);
  const waterY = section.vertexData.water.positions[1];
  assert.ok(waterY < 8 && waterY > 7.8, "water sits just below the block top");
  const opaqueY = [...section.vertexData.opaque.positions].filter((_, index) => index % 3 === 1);
  assert.ok(opaqueY.includes(14), "the canopy top is drawn");
  assert.ok(quadsOf(section) > 2);
}
assert.throws(() => buildLodTileMesh({ tile, samples: [], sectionCells: 4 }), RangeError);
assert.throws(() => buildLodTileMesh({ tile, samples: new Array(256).fill(0), sectionCells: 5 }), RangeError);

// --- manager ---------------------------------------------------------------
{
  const jobs = [];
  const lod = createLodTerrain({ requestTile: (job) => jobs.push(job), chunkSize: CHUNK, maxInFlight: 2 });
  lod.configure({ renderDistance: 2, lodDistance: 256 });
  assert.equal(lod.update(8, 8), false, "nothing is drawn before a tile arrives");
  assert.equal(jobs.length, 2, "requests are bounded");
  assert.equal(lod.update(9, 9), false, "moving inside a cell does not reselect");
  assert.equal(jobs.length, 2);
  // Answer every job with a flat tile until the view is complete.
  let changed = false;
  let guard = 0;
  while (jobs.length > 0 && guard < 500) {
    guard += 1;
    const job = jobs.shift();
    const sections = buildLodTileMesh({
      tile: job,
      samples: new Array(256).fill(encode({ ground: 8 })),
      sectionCells: job.sectionCells,
      chunkSize: CHUNK,
    });
    changed = lod.receive(job.id, sections) || changed;
  }
  assert.ok(changed);
  const stats = lod.stats();
  assert.equal(stats.missingTiles, 0);
  assert.equal(stats.inFlight, 0);
  const all = lod.sections();
  assert.ok(all.length > 0);
  assert.ok(all.every((section) => section.lod === true));
  // A drawn real chunk hides exactly its stand-in section.
  const masked = lod.sections(new Set(["0,0"]));
  assert.equal(masked.length, all.length - 1);
  assert.equal(masked.some((section) => section.chunkKey === "0,0"), false);
  // Section objects keep their identity between publications.
  assert.equal(lod.sections()[3], all[3]);
  // A stale answer after reconfiguration is ignored.
  lod.configure({ renderDistance: 2, lodDistance: 512 });
  assert.equal(lod.receive(1, []), false);
  lod.configure({ renderDistance: 2, lodDistance: 0 });
  assert.equal(lod.update(0, 0), false);
  assert.deepEqual(lod.sections(), []);
}

console.log("lod terrain ok");
