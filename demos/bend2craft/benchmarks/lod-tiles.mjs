import Horizon from "../world/horizon.bend";
import { buildLodTileMesh, lodLevels, lodSamplePoints, selectLodTiles } from "../web/lod-terrain.js";
import { storageCoordinate } from "../web/world-coordinates.js";

// Cost of the distant-terrain rings as the LOD worker pays it: Bend sampling
// (`Horizon.lod_points`) plus meshing, for every tile around a camera, and the
// resulting geometry size, per view distance.
const CHUNK = 16;
const seed = 1337n;

function pointList(points) {
  let list = { $: "Nil" };
  for (let index = points.length - 1; index >= 0; index -= 1) {
    const [x, z] = points[index];
    list = { $: "Con", head: { $: "SurfacePoint", x: BigInt(storageCoordinate(x, CHUNK)), z: BigInt(storageCoordinate(z, CHUNK)) }, tail: list };
  }
  return list;
}

const rows = [];
for (const lodDistance of [256, 512, 1024, 2048]) {
  const layout = lodLevels({ renderDistance: 4, chunkSize: CHUNK, lodDistance });
  const { want } = selectLodTiles({ cameraX: 40, cameraZ: -24, layout });
  let sampleMs = 0;
  let meshMs = 0;
  let quads = 0;
  let vertices = 0;
  let sections = 0;
  for (const tile of want) {
    let start = performance.now();
    const points = lodSamplePoints(tile);
    const samples = Horizon.lod_points(seed, BigInt(points.length), pointList(points));
    sampleMs += performance.now() - start;
    start = performance.now();
    const built = buildLodTileMesh({ tile, samples, sectionCells: tile.level === 0 ? CHUNK / tile.step : 16, chunkSize: CHUNK });
    meshMs += performance.now() - start;
    sections += built.length;
    for (const section of built) {
      quads += section.vertexData.opaque.quadCount + section.vertexData.water.quadCount;
      vertices += (section.vertexData.opaque.positions.length + section.vertexData.water.positions.length) / 3;
    }
  }
  rows.push({
    lodDistance,
    levels: layout.levels.length,
    tiles: want.length,
    sections,
    quads,
    vertexMiB: Number((vertices * 72 / 1048576).toFixed(1)),
    sampleMsPerTile: Number((sampleMs / want.length).toFixed(2)),
    meshMsPerTile: Number((meshMs / want.length).toFixed(2)),
    totalMs: Math.round(sampleMs + meshMs),
  });
}
console.log(JSON.stringify(rows, null, 1));
