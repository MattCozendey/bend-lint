function finite(value, fallback = 0) {
  return Number.isFinite(Number(value)) ? Number(value) : fallback;
}

export function shadowRadius(entity) {
  if (entity?.kind !== undefined) return Number(entity.kind) === 2 ? 0.34 : 0.42;
  if (entity?.profession !== undefined) return 0.36;
  return 0.18;
}

/** Return a flat, camera-independent shadow quad for a presentation entity. */
export function entityShadow(entity, radius = shadowRadius(entity)) {
  const x = finite(entity?.x);
  const y = finite(entity?.y) + 0.012;
  const z = finite(entity?.z);
  const extent = Math.max(0.08, finite(radius, 0.35));
  const corners = [
    [x - extent, y, z - extent],
    [x + extent, y, z - extent],
    [x + extent, y, z + extent],
    [x - extent, y, z + extent],
  ];
  const positions = [];
  for (const index of [0, 1, 2, 0, 2, 3]) positions.push(...corners[index]);
  return { positions, radius: extent, alpha: 0.24 };
}
