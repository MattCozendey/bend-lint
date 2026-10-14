// Per-face colour grading for the presentation layer.
//
// The vertex colour no longer carries light. It carries only a small, static
// grade so a north face is fractionally cooler than a south one, which keeps
// the blocky read of the world without the fragment shader having to fight a
// baked directional term. Actual lighting is done per pixel from the sun
// direction, the shadow map and the baked occlusion/block-light in `aLight`.

export const TERRAIN_FACE_SHADES = Object.freeze([1, 0.68, 0.9, 0.82, 0.96, 0.74]);

const FACE_LIGHT_TINTS = Object.freeze([
  [1.04, 1.02, 0.96],
  [0.78, 0.84, 0.94],
  [1.0, 1.0, 1.0],
  [0.92, 0.96, 1.04],
  [1.02, 1.0, 0.96],
  [0.86, 0.91, 1.0],
]);

export function litFaceColor(faceIndex, daylight, light, shade = 1) {
  const tint = FACE_LIGHT_TINTS[Math.max(0, Math.min(5, Math.trunc(faceIndex)))] ?? FACE_LIGHT_TINTS[2];
  const lightFactor = 0.35 + 0.65 * Math.max(0, Math.min(15, Number(light))) / 15;
  const value = Math.min(1, Math.max(0, Number(daylight)) * lightFactor * Number(shade));
  return tint.map((channel) => Math.min(1, value * channel));
}

export function litEntityFaceColor(tint, faceIndex, daylight, shade = 1) {
  const base = litFaceColor(faceIndex, Math.max(0.36, Number(daylight)), 15, shade);
  return tint.map((channel, index) => Math.min(1, Math.max(0, Number(channel)) * base[index]));
}

/**
 * The per-face grade a terrain vertex carries. `x`/`z` seed a tiny positional
 * wobble so large flat runs of one block type are not perfectly uniform.
 */
export function faceColorGrade(faceIndex, x = 0, z = 0) {
  const index = Math.max(0, Math.min(5, Math.trunc(faceIndex)));
  const tint = FACE_LIGHT_TINTS[index] ?? FACE_LIGHT_TINTS[2];
  const wobble = 1 + (((Number(x) * 17 + Number(z) * 31) % 5) + 5) % 5 * 0.0024;
  return [tint[0] * wobble, tint[1] * wobble, tint[2] * wobble];
}

/** Baked ambient occlusion for one corner of a quad, normalised to 0..1. */
export function cornerOcclusion(ao) {
  return Math.max(0, Math.min(1, Number(ao ?? 1)));
}

/** Baked block/sky light level of a voxel, normalised to 0..1. */
export function blockLightLevel(light) {
  return Math.max(0, Math.min(15, Number(light ?? 15))) / 15;
}
