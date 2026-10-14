export const TERRAIN_FOG_START = 24;
export const TERRAIN_MATERIAL_VARIATION_MIN = 0.985;
export const TERRAIN_MATERIAL_VARIATION_MAX = 1.015;
export const TERRAIN_VARIATION_X = 12.9898;
export const TERRAIN_VARIATION_Z = 78.233;
export const TERRAIN_VARIATION_SEED = 43758.5453;
export const MINING_FRACTURE_PROGRESS = 0.02;
export const MOON_FILL_STRENGTH = 0.72;
export const NIGHT_AMBIENT_R = 0.035;
export const NIGHT_AMBIENT_G = 0.055;
export const NIGHT_AMBIENT_STRENGTH = 0.7;
export const LAVA_PULSE_AMPLITUDE = 0.16;
export const LAVA_PULSE_SPEED = 2.4;
export const LAVA_PULSE_SPATIAL_FREQUENCY = 0.5;
export const LAVA_ALPHA = 0.86;
export const FIRE_PULSE_AMPLITUDE = 0.25;
export const FIRE_PULSE_SPEED = 8;
export const FIRE_PULSE_SPATIAL_FREQUENCY = 4;
export const FIRE_ALPHA = 0.9;
export const WATER_DARK_R = 0.025;
export const WATER_DARK_G = 0.22;
export const WATER_DARK_B = 0.34;
export const WATER_LIGHT_R = 0.12;
export const WATER_LIGHT_G = 0.62;
export const WATER_LIGHT_B = 0.72;
export const WATER_FRESNEL_POWER = 3;
export const WATER_SPECULAR_POWER = 48;
export const WATER_FOAM_THRESHOLD = 0.94;
export const WATER_NORMAL_STRENGTH = 6;
export const WATER_FOAM_STRENGTH = 0.035;
export const WATER_CAUSTIC_STRENGTH = 0.18;
export const WATER_CAUSTIC_THRESHOLD_START = 0.54;
export const WATER_CAUSTIC_THRESHOLD_END = 0.72;
export const AERIAL_FOG_MIN_DENSITY = 0.42;
export const AERIAL_FOG_HEIGHT_FALLOFF = 0.028;

// Per-pixel lighting response. The sun term is deliberately brighter than a
// baked constant: the tonemapper downstream rolls off anything much above this,
// which is what buys the headroom the bloom and the god rays need.
//
// AMBIENT_STRENGTH is scene-referred, not display-referred. `uSkyColor` is the
// colour the sky is *displayed* as, which for a mid-blue is around 0.2-0.5; the
// radiance of that sky is several times higher, so the ambient has to be scaled
// up by roughly that factor or every shadowed surface collapses to near black.
export const SUN_INTENSITY = 0.95;
// Ambient can afford to be generous now that the sun is no longer doing the work
// alone. It used to be balanced against a 2.35 sun, which meant it had to stay
// small to keep a sunlit surface out of the tonemap's shoulder, and the cost was
// that a backlit face - a wall with the sun behind it, filling a third of the
// frame - collapsed to black and lost its material. With the sun term scaled
// back, the same tonemap budget is available to the sky fill instead.
export const AMBIENT_STRENGTH = 1.8;
/** Bounce colour from the ground onto downward-facing surfaces. */
export const GROUND_BOUNCE = Object.freeze([0.16, 0.15, 0.12]);
/** Height-field amplitude for the derivative bump, in world units per unit height. */
export const BUMP_STRENGTH = 0.055;
/** Amplitude of the per-block detail resample that hides the tile repeat. */
export const DETAIL_STRENGTH = 0.1;
/** How many times the tile repeats inside one block face for the detail layer. */
export const DETAIL_SCALE = 3.0;
/** Grass and leaf sway, scaled by the adaptive quality tier. */
export const GRASS_WIND_STRENGTH = 1;
/** How much fine wave detail the water surface keeps. */
export const WATER_DETAIL_STRENGTH = 1;
/** Volumetric cloud raymarch samples at the top quality tier. */
export const CLOUD_COVERAGE = 0.42;
export const CLOUD_WIND_SPEED = 1;
// How a lit cloud gets its light, split in two. The isotropic part is the whole
// sunlit hemisphere arriving on a bright diffuse reflector, which is where most of
// a cloud's brightness actually comes from; the phase part is the extra forward
// glow around the sun, which is what the Henyey-Greenstein lobe describes and what
// makes a backlit edge shine.
//
// With the phase term alone the deck could never be brighter than the sky behind
// it, which is what made it read as a flat grey stain rather than as a volume:
// away from the sun the sun contributed a few percent of the sky's own colour.
// The gain below is calibrated from pictures rather than derived - see
// `tests/cloud-lighting.test.mjs`, which holds the measured span.
export const CLOUD_DIFFUSE_SCATTER = 1.8;
export const CLOUD_PHASE_SCATTER = 0.9;
/** How much of the ambient's blue cast is washed out toward neutral. */
export const AMBIENT_DESATURATION = 0.34;

// Material response is split into three ordered stages so both backends grade a
// pixel the same way: albedo from the material sample, then lighting from the
// day/ambient model, then the material lobe (detail, roughness, specular).
export const MATERIAL_ALBEDO_STAGE = 1;
export const MATERIAL_LIGHTING_STAGE = 2;
export const MATERIAL_DETAIL_STAGE = 3;
export const MATERIAL_STAGE_ORDER = Object.freeze([
  MATERIAL_ALBEDO_STAGE,
  MATERIAL_LIGHTING_STAGE,
  MATERIAL_DETAIL_STAGE,
]);
// Detail is a bounded multiplier on the albedo, never a replacement for it.
export const MATERIAL_DETAIL_NEUTRAL = 1;
export const MATERIAL_DETAIL_STRENGTH = 0.09;
export const MATERIAL_ROUGHNESS_MIN = 0.55;
export const MATERIAL_ROUGHNESS_MAX = 0.95;
export const MATERIAL_SPECULAR_POWER = 24;
export const MATERIAL_SPECULAR_STRENGTH = 0.18;
// Water reads its depth from the surface height difference and tints toward a
// cool floor, saturating at the documented maximum so a deep ocean cannot go
// black and lose its silhouette.
export const WATER_DEPTH_MAX = 5;
export const WATER_DEPTH_TINT_STRENGTH = 0.34;
export const WATER_DEPTH_FLOOR_R = 0.04;

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function fract(value) {
  return value - Math.floor(value);
}

function smoothstep(edgeStart, edgeEnd, value) {
  const amount = clamp01((Number(value) - edgeStart) / (edgeEnd - edgeStart));
  return amount * amount * (3 - 2 * amount);
}

export function materialVariationMultiplier(x, z) {
  const cell = Math.sin(
    Math.floor(Number(x)) * TERRAIN_VARIATION_X
      + Math.floor(Number(z)) * TERRAIN_VARIATION_Z,
  ) * TERRAIN_VARIATION_SEED;
  return TERRAIN_MATERIAL_VARIATION_MIN
    + (TERRAIN_MATERIAL_VARIATION_MAX - TERRAIN_MATERIAL_VARIATION_MIN) * fract(cell);
}

export function terrainFog(distance, fogDistance) {
  return clamp01((Number(distance) - TERRAIN_FOG_START) / Number(fogDistance));
}

export function aerialPerspective(distance, fogDistance, cameraY, worldY) {
  const baseFog = terrainFog(distance, fogDistance);
  const relativeHeight = Math.max(0, Number(worldY) - Number(cameraY));
  const heightAttenuation = Math.exp(-relativeHeight * AERIAL_FOG_HEIGHT_FALLOFF);
  return clamp01(baseFog * (
    AERIAL_FOG_MIN_DENSITY
    + (1 - AERIAL_FOG_MIN_DENSITY) * heightAttenuation
  ));
}

export function waterCaustic(pattern, facing = 1) {
  const crest = smoothstep(
    WATER_CAUSTIC_THRESHOLD_START,
    WATER_CAUSTIC_THRESHOLD_END,
    pattern,
  );
  return crest * WATER_CAUSTIC_STRENGTH * (0.35 + clamp01(facing) * 0.65);
}

export function lavaPulse(time, x) {
  return 1 + LAVA_PULSE_AMPLITUDE * Math.sin(
    Number(time) * LAVA_PULSE_SPEED + Number(x) * LAVA_PULSE_SPATIAL_FREQUENCY,
  );
}

export function lavaAlpha(alpha) {
  return Math.max(Number(alpha), LAVA_ALPHA);
}

export function firePulse(time, y) {
  return 1 + FIRE_PULSE_AMPLITUDE * Math.sin(
    Number(time) * FIRE_PULSE_SPEED + Number(y) * FIRE_PULSE_SPATIAL_FREQUENCY,
  );
}

export function fireAlpha(alpha) {
  return Math.max(Number(alpha), FIRE_ALPHA);
}

export function fractureVisibility(progress, fracture) {
  return Number(progress) >= MINING_FRACTURE_PROGRESS ? Number(fracture) : 0;
}

/**
 * Detail shading: low-amplitude surface relief derived from the material sample
 * and the surface's roughness. A rougher surface carries more micro-relief, so
 * its sample gets more contrast, while a polished surface stays flat.
 */
export function detailShade(sample, roughness, bias = 0) {
  const relief = (Number(sample) - 0.5) * 2;
  const amplitude = MATERIAL_DETAIL_STRENGTH * (0.5 + 0.5 * clamp01(roughness));
  return MATERIAL_DETAIL_NEUTRAL + amplitude * (relief + clamp01(bias));
}

/** Roughness response: 0 is the smoothest authored material, 1 the coarsest. */
export function materialRoughness(coarseness) {
  return MATERIAL_ROUGHNESS_MIN
    + (MATERIAL_ROUGHNESS_MAX - MATERIAL_ROUGHNESS_MIN) * clamp01(coarseness);
}

/** Specular lobe response, falling off as the surface gets rougher. */
export function materialSpecular(facing, roughness) {
  const clamped = clamp01(facing);
  const lobe = Math.pow(clamped, MATERIAL_SPECULAR_POWER);
  return MATERIAL_SPECULAR_STRENGTH * lobe * (1 - clamp01(roughness));
}

/** Normalized water depth in 0..1, saturating at the documented maximum. */
export function waterDepthTint(depth) {
  return clamp01(Number(depth) / WATER_DEPTH_MAX);
}

/**
 * Direct sun contribution for a surface: the wrapped N.L term, softened at the
 * terminator so a blocky world does not read as chipped. `shadow` is the
 * cascade lookup in 0..1 and `sunUp` is how far above the horizon the sun is.
 */
export function sunDiffuse(ndotl, shadow = 1, sunUp = 1) {
  const facing = Math.max(0, Number(ndotl) ?? 0);
  const wrapped = Math.max(0, (facing + 0.18) / 1.18);
  const visibility = smoothstep(-0.14, 0.06, Number(sunUp) ?? 0);
  return (facing * 0.65 + wrapped * 0.35) * clamp01(shadow) * visibility * SUN_INTENSITY;
}

/**
 * Hemispheric ambient for a surface. The sky term dominates up-facing surfaces,
 * the ground bounce dominates down-facing ones, and both are gated by the baked
 * sky-light level so an enclosed voxel stays dark.
 */
export function ambientResponse(normalY, skyLightLevel, occlusion) {
  const up = clamp01(Number(normalY) * 0.5 + 0.5);
  const openness = 0.24 + 0.76 * clamp01(skyLightLevel);
  return AMBIENT_STRENGTH * up * openness * clamp01(occlusion);
}

/**
 * Water color at a given depth. Shallow water keeps its albedo, and deeper
 * water darkens toward a cool floor so a deep ocean still reads as water.
 */
export function waterDepthColor(depth) {
  const amount = waterDepthTint(depth) * WATER_DEPTH_TINT_STRENGTH;
  const albedo = [WATER_LIGHT_R, WATER_LIGHT_G, WATER_LIGHT_B];
  const floor = [WATER_DEPTH_FLOOR_R, WATER_DARK_G * 0.5, WATER_DARK_B * 0.6];
  return albedo.map((channel, index) => channel + (floor[index] - channel) * amount);
}
