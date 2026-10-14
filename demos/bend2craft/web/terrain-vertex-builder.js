import { faceNormal, quadCorners } from "./greedy-mesh.js";
import { atlasUV, blockFaceTileAt } from "./texture-atlas.js";
import { faceColorGrade } from "./material-lighting.js";
import { WATER_DEPTH_MAX } from "./terrain-presentation.js";
import {
  isFireMaterial,
  isLavaMaterial,
  isWaterMaterial,
  surfaceMaterial,
  waterMaterial,
} from "./surface-materials.js";

// The vertex layout the presentation shaders read:
//
//   aColor   vec3  per-face colour grade only, no light folded in
//   aLight   vec2  (ambient occlusion, baked block light 0..1)
//   aNormal  vec3  outward face normal
//   aUV      vec2  tile-local UV in blocks
//   aTileRect vec4  atlas sub-rectangle
//   aMaterial float surface material band, water carries its depth inside it
//
// Lighting used to be baked into `aColor` together with the day/night term,
// which meant the fragment shader could not light a surface from a real sun
// direction. Splitting occlusion and block light into `aLight` lets the shader
// apply the sun, its shadow and a hemispheric ambient independently, and makes
// the mesh independent of the time of day so it no longer has to be rebuilt as
// the sun moves.

function quadMaterial(quad) {
  const material = surfaceMaterial(quad.block);
  if (!isWaterMaterial(material)) return material;
  // Water carries its sampled column depth in the material band.
  return waterMaterial(Number(quad.waterDepthCells ?? 0) / WATER_DEPTH_MAX);
}

function appendQuad(layer, quad) {
  const color = faceColorGrade(quad.faceIndex, quad.x, quad.z);
  const corners = quadCorners(quad);
  const normal = faceNormal(quad.faceIndex);
  const tile = quad.tile ?? blockFaceTileAt(quad.block, quad.faceIndex, quad.x, quad.z);
  const uv = atlasUV(tile);
  const tileRect = quad.faceIndex >= 2
    ? [uv[0], uv[5], uv[4], uv[1]]
    : [uv[0], uv[1], uv[4], uv[5]];
  const localUv = [[0, 0], [quad.width, 0], [quad.width, quad.height], [0, quad.height]];
  const material = quadMaterial(quad);
  const lightLevel = Math.max(0, Math.min(15, Number(quad.light ?? 15))) / 15;
  for (const cornerIndex of [0, 1, 2, 0, 2, 3]) {
    const corner = corners[cornerIndex];
    const ao = quad.ao?.[cornerIndex] ?? 1;
    layer.positions.push(corner[0], corner[1], corner[2]);
    layer.colors.push(color[0], color[1], color[2]);
    layer.lights.push(ao, lightLevel);
    layer.normals.push(normal[0], normal[1], normal[2]);
    layer.uvs.push(localUv[cornerIndex][0], localUv[cornerIndex][1]);
    layer.tiles.push(...tileRect);
    layer.materials.push(material);
  }
  layer.quadCount += 1;
}

function typedLayer(layer) {
  return {
    positions: new Float32Array(layer.positions),
    colors: new Float32Array(layer.colors),
    lights: new Float32Array(layer.lights),
    normals: new Float32Array(layer.normals),
    uvs: new Float32Array(layer.uvs),
    materials: new Float32Array(layer.materials),
    tiles: new Float32Array(layer.tiles),
    quadCount: layer.quadCount,
  };
}

export function buildTerrainVertexArrays(quads) {
  if (!Array.isArray(quads)) throw new TypeError("terrain vertex builder requires quads");
  const opaque = emptyLayer();
  const water = emptyLayer();
  for (const quad of quads) {
    const material = quadMaterial(quad);
    const target = isWaterMaterial(material) || isLavaMaterial(material) || isFireMaterial(material)
      ? water
      : opaque;
    appendQuad(target, quad);
  }
  return { opaque: typedLayer(opaque), water: typedLayer(water) };
}

function emptyLayer() {
  return {
    positions: [],
    colors: [],
    lights: [],
    normals: [],
    uvs: [],
    materials: [],
    tiles: [],
    quadCount: 0,
  };
}
