// Checks relayed player poses against the Bend movement contract
// (world/multiplayer_moves.bend): speed and rise budgets, no walking into
// solid blocks, respawns onto the world spawn. This module only samples the
// server's terrain cache and keeps each player's budget between poses.
import { MultiplayerMoves as Moves, World } from "../web/bend-modules.js";

const LEGS = 0.5;
const HEAD = 1.5;

/**
 * @param {object} options
 * @param {bigint} options.seed
 * @param {{ blockAt(x: number, y: number, z: number): number }} options.cache
 */
export function createMoveGuard({ seed, cache }) {
  const spawn = World.spawn_cell(seed);
  const spawnX = Number(spawn.x) + 0.5;
  const spawnZ = Number(spawn.z) + 0.5;
  // Per player: the Bend budget and when it was last checked.
  const budgets = new Map();

  const cell = (x, y, z) => cache.blockAt(Math.floor(x), Math.floor(y), Math.floor(z));

  /**
   * Whether player `id` may move from its last accepted pose `from` (null for
   * the first pose) to `to`, at `at` milliseconds.
   */
  function check(id, from, to, at) {
    const last = budgets.get(id);
    if (from === null || last === undefined) {
      budgets.set(id, { budget: Moves.fresh(), at });
      return true;
    }
    const move = Moves.step(
      last.budget, (at - last.at) / 1000,
      from.x, from.y, from.z, to.x, to.y, to.z,
      cell(from.x, from.y + LEGS, from.z), cell(from.x, from.y + HEAD, from.z),
      cell(to.x, to.y + LEGS, to.z), cell(to.x, to.y + HEAD, to.z),
      spawnX, spawnZ,
    );
    budgets.set(id, { budget: Moves.move_budget(move), at });
    return Moves.accepted(move);
  }

  return {
    check,
    forget: (id) => budgets.delete(id),
  };
}
