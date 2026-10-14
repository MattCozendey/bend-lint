export const SURFACE_MATERIAL_WATER = 1;
export const SURFACE_MATERIAL_LAVA = 2;
export const SURFACE_MATERIAL_FIRE = 3;
export const SURFACE_MATERIAL_OPAQUE_BASE = 10;

// The material channel is a band, not an enum. Water encodes its normalized
// depth as `WATER + depth`, so a deep ocean can be tinted without adding a second
// vertex attribute or a per-fragment world query.
export function inMaterialBand(material, low) {
  const value = Number(material);
  return value >= low && value < low + 1;
}

export function waterMaterial(depth) {
  const clamped = Math.max(0, Math.min(0.999, Number(depth) || 0));
  return SURFACE_MATERIAL_WATER + clamped;
}

export function waterDepth(material) {
  if (!inMaterialBand(material, SURFACE_MATERIAL_WATER)) return 0;
  return Math.max(0, Math.min(1, Number(material) - SURFACE_MATERIAL_WATER));
}

export function isWaterMaterial(material) {
  return inMaterialBand(material, SURFACE_MATERIAL_WATER);
}

export function isLavaMaterial(material) {
  return inMaterialBand(material, SURFACE_MATERIAL_LAVA);
}

export function isFireMaterial(material) {
  return inMaterialBand(material, SURFACE_MATERIAL_FIRE);
}

/**
 * Opaque terrain encodes its block as `10 + block`, so it must be routed to the
 * solid layer even though it sorts above every fluid band.
 */
export function isOpaqueMaterial(material) {
  return Number(material) >= SURFACE_MATERIAL_OPAQUE_BASE;
}

export function surfaceMaterial(block) {
  if (Number(block) === 7) return SURFACE_MATERIAL_WATER;
  if (Number(block) === 21) return SURFACE_MATERIAL_LAVA;
  if (Number(block) === 24) return SURFACE_MATERIAL_FIRE;
  return SURFACE_MATERIAL_OPAQUE_BASE + Number(block);
}

export function movesSurfaceGeometry(material) {
  return isWaterMaterial(material);
}
