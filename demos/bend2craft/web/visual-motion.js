const MAX_WALK_SPEED = 4.5;

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

/** Deterministic first-person motion from the already-authoritative player view. */
export function cameraMotion(time, { speed = 0, grounded = false } = {}) {
  const stride = grounded ? clamp01(Math.abs(Number(speed)) / MAX_WALK_SPEED) : 0;
  if (stride <= 0 || !Number.isFinite(Number(time))) {
    return { bob: 0, sway: 0, roll: 0, stride: 0 };
  }
  const phase = Number(time) * (8.5 + stride * 4.5);
  return {
    bob: Math.sin(phase * 2) * 0.035 * stride,
    sway: Math.cos(phase) * 0.018 * stride,
    roll: Math.sin(phase) * 0.006 * stride,
    stride,
  };
}

/** Small world-space displacement used by the water vertex pass. */
export function waterWave(x, z, time) {
  const phase = Number(time);
  if (![x, z, phase].every(Number.isFinite)) return 0;
  return (
    Math.sin(phase * 1.6 + Number(x) * 0.38 + Number(z) * 0.27) * 0.028
    + Math.sin(phase * 2.7 - Number(z) * 0.19 + Number(x) * 0.11) * 0.012
  );
}
