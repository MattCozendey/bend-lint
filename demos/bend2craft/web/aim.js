// Aimed combat helpers. Slab ray test against an axis-aligned body box.
// Dependency-free and testable without a browser.
import { mobHeight } from "./mob-kinds.js";

export function bodyBox(x, y, z, height, halfWidth = 0.4) {
  return {
    minX: x - halfWidth,
    minY: y,
    minZ: z - halfWidth,
    maxX: x + halfWidth,
    maxY: y + height,
    maxZ: z + halfWidth,
  };
}

// Height comes from the roster rather than from a "is this the tall one" test,
// so a brute is shootable in the head and a chicken is hittable at all.
export function mobBox(mob) {
  return bodyBox(mob.x, mob.y, mob.z, mobHeight(mob.kind));
}

// Returns the ray distance to the box, or null on miss/out of range.
export function rayHitBox(origin, direction, box, maxDistance) {
  const mins = [box.minX, box.minY, box.minZ];
  const maxs = [box.maxX, box.maxY, box.maxZ];
  let near = 0;
  let far = maxDistance;
  for (let axis = 0; axis < 3; axis += 1) {
    const o = origin[axis];
    const d = direction[axis];
    if (Math.abs(d) < 1e-9) {
      if (o < mins[axis] || o > maxs[axis]) return null;
    } else {
      let t0 = (mins[axis] - o) / d;
      let t1 = (maxs[axis] - o) / d;
      if (t0 > t1) [t0, t1] = [t1, t0];
      near = Math.max(near, t0);
      far = Math.min(far, t1);
      if (near > far) return null;
    }
  }
  return near;
}

export function firstAimedMob(origin, direction, mobs, maxDistance) {
  let target = null;
  let targetDistance = maxDistance;
  for (const mob of mobs) {
    if (!mob.alive) continue;
    const distance = rayHitBox(origin, direction, mobBox(mob), targetDistance);
    if (distance === null) continue;
    target = mob;
    targetDistance = distance;
  }
  return target;
}
