export function cameraFov(baseFov, { sprinting = false, damage = 0, underwater = false } = {}) {
  const base = Number(baseFov);
  if (!Number.isFinite(base)) throw new TypeError("baseFov must be finite");
  const damageKick = Math.min(6, Math.max(0, Number(damage) || 0) * 0.15);
  const sprintKick = sprinting ? 4 : 0;
  const waterKick = underwater ? -5 : 0;
  return Math.min(130, Math.max(30, base + sprintKick + damageKick + waterKick));
}
