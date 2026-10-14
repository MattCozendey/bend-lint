// Pure textured mob models built from the shared texture atlas.
// Emits positions/colors/uvs triples for the WebGL adapter in main.js.
// Local -Z is the mob's forward; pass yaw = -dir * PI / 4 to face travel.

import { atlasUV } from "./texture-atlas.js";

export const MOB_TILES = Object.freeze({
  pigFace: 21,
  pigSkin: 22,
  zombieFace: 23,
  zombieSkin: 24,
});

const FACE_SHADES = Object.freeze({
  top: 1.0,
  bottom: 0.55,
  front: 0.9,
  back: 0.65,
  right: 0.8,
  left: 0.7,
});

export function facingYaw(dir) {
  return -dir * (Math.PI / 4);
}

export function createModelArrays() {
  return { positions: [], colors: [], uvs: [] };
}

// Quad corners are [topLeft, topRight, bottomRight, bottomLeft] so the
// atlas tile maps upright on every side; emitted as two triangles.
function emitFace(arrays, quad, tile, shade, tint, daylight) {
  const uv = atlasUV(tile);
  const light = shade * daylight;
  for (const index of [0, 1, 2, 0, 2, 3]) {
    const point = quad[index];
    arrays.positions.push(point[0], point[1], point[2]);
    arrays.colors.push(tint[0] * light, tint[1] * light, tint[2] * light);
    arrays.uvs.push(uv[index * 2], uv[index * 2 + 1]);
  }
}

// Corner order per face is [topLeft, topRight, bottomRight, bottomLeft]
// so the atlas tile maps upright on every side.
function boxFaces(hx, hy, hz) {
  return {
    top: [[-hx, hy, -hz], [hx, hy, -hz], [hx, hy, hz], [-hx, hy, hz]],
    bottom: [[-hx, -hy, hz], [hx, -hy, hz], [hx, -hy, -hz], [-hx, -hy, -hz]],
    front: [[-hx, hy, -hz], [hx, hy, -hz], [hx, -hy, -hz], [-hx, -hy, -hz]],
    back: [[hx, hy, hz], [-hx, hy, hz], [-hx, -hy, hz], [hx, -hy, hz]],
    right: [[hx, hy, -hz], [hx, hy, hz], [hx, -hy, hz], [hx, -hy, -hz]],
    left: [[-hx, hy, hz], [-hx, hy, -hz], [-hx, -hy, -hz], [-hx, -hy, hz]],
  };
}

function rotateYaw(lx, ly, lz, yaw) {
  const sin = Math.sin(yaw);
  const cos = Math.cos(yaw);
  return [lx * cos + lz * sin, ly, -lx * sin + lz * cos];
}

export function appendTexturedBox(arrays, cx, cy, cz, sx, sy, sz, yaw, tiles, daylight, tint = [1, 1, 1]) {
  const faces = boxFaces(sx / 2, sy / 2, sz / 2);
  for (const [name, quad] of Object.entries(faces)) {
    const placed = quad.map(([lx, ly, lz]) => {
      const [rx, ry, rz] = rotateYaw(lx, ly, lz, yaw);
      return [cx + rx, cy + ry, cz + rz];
    });
    emitFace(arrays, placed, tiles[name], FACE_SHADES[name], tint, daylight);
  }
}

// Hanging limb pivoted at (px, py, pz), swinging around X, then yawed.
export function appendLimb(arrays, px, py, pz, w, len, d, swing, restPitch, yaw, tile, daylight, tint = [1, 1, 1]) {
  const total = swing + restPitch;
  const sinP = Math.sin(total);
  const cosP = Math.cos(total);
  const corners = [];
  for (const lx of [-w / 2, w / 2]) {
    for (const lz of [-d / 2, d / 2]) {
      for (const ly of [0, -len]) {
        const ry = ly * cosP - lz * sinP;
        const rz = ly * sinP + lz * cosP;
        const [rx, y2, rz2] = rotateYaw(lx, ry, rz, yaw);
        corners.push([px + rx, py + y2, pz + rz2]);
      }
    }
  }
  // corners: x{0,1} z{0,1} y{top,bot} -> idx = x*4 + z*2 + y
  const at = (x, z, y) => corners[x * 4 + z * 2 + y];
  const faces = {
    top: [at(0, 0, 0), at(1, 0, 0), at(1, 1, 0), at(0, 1, 0)],
    bottom: [at(0, 1, 1), at(1, 1, 1), at(1, 0, 1), at(0, 0, 1)],
    front: [at(0, 0, 0), at(1, 0, 0), at(1, 0, 1), at(0, 0, 1)],
    back: [at(1, 1, 0), at(0, 1, 0), at(0, 1, 1), at(1, 1, 1)],
    right: [at(1, 0, 0), at(1, 1, 0), at(1, 1, 1), at(1, 0, 1)],
    left: [at(0, 1, 0), at(0, 0, 0), at(0, 0, 1), at(0, 1, 1)],
  };
  for (const [name, quad] of Object.entries(faces)) {
    emitFace(arrays, quad, tile, FACE_SHADES[name] * 0.9, tint, daylight);
  }
}

function flatTiles(tile) {
  return { top: tile, bottom: tile, front: tile, back: tile, left: tile, right: tile };
}

function headTiles(face, side, top) {
  return { top, bottom: side, front: face, back: side, left: side, right: side };
}

export function appendMobModel(arrays, mob, daylight, now = 0) {
  const flash = mob.hurtTimer > 0;
  const tint = flash ? [2.5, 2.5, 2.5] : [1, 1, 1];
  const stepping = mob.moving && mob.grounded !== false;
  const phase = stepping ? now / 160 : 0;
  const swingOf = (offset) => (stepping ? Math.sin(phase + offset) * 0.55 : 0);
  const bob = stepping ? Math.abs(Math.sin(phase)) * 0.04 : 0;
  const yaw = facingYaw(mob.dir ?? 0);
  const cos = Math.cos(-yaw);
  const sin = Math.sin(-yaw);
  // World offset matching the builder rotation (inverse-angle basis).
  const at = (lx, ly, lz) => [
    mob.x + lx * cos - lz * sin,
    mob.y + ly + bob,
    mob.z + lx * sin + lz * cos,
  ];
  if (mob.kind === 1) {
    const [bx, by, bz] = at(0, 0.62, 0);
    appendTexturedBox(arrays, bx, by, bz, 0.7, 0.55, 0.95, yaw, flatTiles(MOB_TILES.pigSkin), daylight, tint);
    const head = headTiles(MOB_TILES.pigFace, MOB_TILES.pigSkin, MOB_TILES.pigSkin);
    const [hx, hy, hz] = at(0, 1.0, -0.55);
    appendTexturedBox(arrays, hx, hy, hz, 0.5, 0.5, 0.5, yaw, head, daylight, tint);
    const [sx, sy, sz] = at(0, 0.93, -0.83);
    appendTexturedBox(arrays, sx, sy, sz, 0.3, 0.22, 0.14, yaw, flatTiles(MOB_TILES.pigSkin), daylight, tint);
    for (const ex of [-0.16, 0.16]) {
      const [px, py, pz] = at(ex, 1.32, -0.5);
      appendTexturedBox(arrays, px, py, pz, 0.14, 0.2, 0.08, yaw, flatTiles(MOB_TILES.pigSkin), daylight, tint);
    }
    const legs = [[-0.22, -0.3, 0], [0.22, -0.3, Math.PI], [-0.22, 0.3, Math.PI], [0.22, 0.3, 0]];
    for (const [lx, lz, offset] of legs) {
      const [px, py, pz] = at(lx, 0.38, lz);
      appendLimb(arrays, px, py, pz, 0.22, 0.38, 0.22, swingOf(offset), 0, yaw, MOB_TILES.pigSkin, daylight, tint);
    }
  } else {
    const skin = MOB_TILES.zombieSkin;
    const head = headTiles(MOB_TILES.zombieFace, skin, skin);
    for (const [lx, offset] of [[-0.16, 0], [0.16, Math.PI]]) {
      const [px, py, pz] = at(lx, 0.85, 0);
      appendLimb(arrays, px, py, pz, 0.28, 0.85, 0.28, swingOf(offset), 0, yaw, skin, daylight, tint);
    }
    const [bx, by, bz] = at(0, 1.2, 0);
    appendTexturedBox(arrays, bx, by, bz, 0.62, 0.72, 0.36, yaw, flatTiles(skin), daylight, [0.35 * tint[0], 0.75 * tint[1], 0.7 * tint[2]]);
    for (const [lx, offset] of [[-0.4, Math.PI], [0.4, 0]]) {
      const [px, py, pz] = at(lx, 1.48, -0.05);
      appendLimb(arrays, px, py, pz, 0.22, 0.72, 0.22, swingOf(offset) * 0.3, 1.25, yaw, skin, daylight, tint);
    }
    const [hx, hy, hz] = at(0, 1.78, -0.02);
    appendTexturedBox(arrays, hx, hy, hz, 0.5, 0.5, 0.5, yaw, head, daylight, tint);
  }
}
