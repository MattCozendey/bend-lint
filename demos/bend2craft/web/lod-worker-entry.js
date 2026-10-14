import { Horizon } from "./bend-modules.js";
import { buildLodTileMesh, lodSamplePoints, lodSectionTransferables } from "./lod-terrain.js";
import { storageCoordinate } from "./world-coordinates.js";

// Distant terrain tiles: sample the Bend LOD contract in bulk, then mesh the
// columns into terrain sections. Runs on its own worker so chunk generation is
// never queued behind the horizon.
function pointList(points, chunkSize) {
  let list = { $: "Nil" };
  for (let index = points.length - 1; index >= 0; index -= 1) {
    const [x, z] = points[index];
    list = {
      $: "Con",
      head: {
        $: "SurfacePoint",
        x: BigInt(storageCoordinate(x, chunkSize)),
        z: BigInt(storageCoordinate(z, chunkSize)),
      },
      tail: list,
    };
  }
  return list;
}

self.postMessage({ workerReady: true });
self.onmessage = (event) => {
  const job = event.data;
  if (job?.type !== "lodTile") return;
  try {
    const tile = {
      level: job.level,
      tileX: job.tileX,
      tileZ: job.tileZ,
      step: job.step,
      originX: job.originX,
      originZ: job.originZ,
    };
    const points = lodSamplePoints(tile, job.cells);
    const samples = Horizon.lod_points(BigInt(job.seed), BigInt(points.length), pointList(points, job.chunkSize));
    const sections = buildLodTileMesh({
      tile,
      samples,
      cells: job.cells,
      sectionCells: job.sectionCells,
      chunkSize: job.chunkSize,
      waterSurface: job.waterSurface,
    });
    self.postMessage({ type: "lodTile", id: job.id, sections }, lodSectionTransferables(sections));
  } catch (error) {
    self.postMessage({ type: "lodTile", id: job.id, error: String(error?.stack ?? error) });
  }
};
