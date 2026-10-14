// Where night monsters appear around a player. Single player spawns around
// its one player; the multiplayer server calls the same function for each
// player, so both follow one rule. The terrain queries are Bend's.
import { World } from "./bend-modules.js";
import { isHostileKind } from "./mob-kinds.js";

export const NIGHT_SPAWN = Object.freeze({
  maxAlive: 24,
  maxHostile: 8,
  attempts: 6,
  perCall: 2,
  minDistance: 18,
  spread: 10,
});

/**
 * Up to `perCall` new monsters in a ring around (anchorX, anchorZ), standing on
 * generated ground with two air cells above. `mobs` are views with `alive` and
 * `kind`. Returns [{ kind, x, y, z, health }].
 */
export function nightSpawns({ seed, mobs, anchorX, anchorZ, maxY, random = Math.random, limits = NIGHT_SPAWN }) {
  const alive = mobs.filter((mob) => mob.alive);
  if (alive.length >= limits.maxAlive) return [];
  if (alive.filter((mob) => isHostileKind(mob.kind)).length >= limits.maxHostile) return [];
  const spawns = [];
  for (let attempt = 0; attempt < limits.attempts && spawns.length < limits.perCall; attempt += 1) {
    const angle = random() * Math.PI * 2;
    const dist = limits.minDistance + random() * limits.spread;
    const nx = Math.floor(anchorX + Math.cos(angle) * dist);
    const nz = Math.floor(anchorZ + Math.sin(angle) * dist);
    if (nx < 0 || nz < 0) continue;
    const height = Number(World.column_height(seed, BigInt(nx), BigInt(nz)));
    if (!Number.isFinite(height) || height <= 0 || height >= maxY - 2) continue;
    if (Number(World.block(seed, BigInt(nx), BigInt(height), BigInt(nz))) !== 0) continue;
    if (Number(World.block(seed, BigInt(nx), BigInt(height + 1), BigInt(nz))) !== 0) continue;
    const kind = random() < 0.8 ? 2 : 4;
    spawns.push({ kind, x: nx + 0.5, y: height, z: nz + 0.5, health: kind === 4 ? 40.0 : 20.0 });
  }
  return spawns;
}
