export function miningProgress(state, now) {
  if (state === null || typeof state !== "object") return 0;
  const duration = Number(state.duration);
  const startedAt = Number(state.startedAt);
  const current = Number(now);
  if (!Number.isFinite(duration) || duration <= 0) return 1;
  if (!Number.isFinite(startedAt) || !Number.isFinite(current)) return 0;
  return Math.max(0, Math.min(1, (current - startedAt) / (duration * 1000)));
}
