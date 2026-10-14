// The multiplayer server's villagers: world/villagers.bend stepped once a
// second for the player nearest the village, with the village path grid
// recomputed after edits near the village, and the doors villagers open and
// close submitted as ordinary edits.
import { Structures, Villagers } from "../web/bend-modules.js";

const STEP_SECONDS = 1;
const SIMULATION_RADIUS = 16;
// Edits inside this margin around the village origin can change its paths.
const VILLAGE_MARGIN = 32;

const round = (value) => Math.round(Number(value) * 1000) / 1000;

export function villagerToWire(villager) {
  return [
    Number(villager.id), Number(villager.profession), round(villager.x), round(villager.y), round(villager.z),
    Number(villager.home_x), Number(villager.home_z), villager.resting ? 1 : 0,
  ];
}

function editMap(list) {
  const values = new Map();
  for (let node = list; node?.$ === "Con"; node = node.tail) {
    values.set(`${node.head.x},${node.head.y},${node.head.z}`, Number(node.head.block));
  }
  return values;
}

/**
 * @param {object} options
 * @param {bigint} options.seed
 * @param {() => object} options.edits  the room's current Bend edit log
 */
export function createVillagerWorld({ seed, edits }) {
  let villagers = Villagers.spawn(seed);
  let tick = 0;
  let grid = null;
  let elapsed = 0;
  const originX = Number(Structures.village_origin_x(seed));
  const originZ = Number(Structures.village_origin_z(seed));

  /** Changed cells (signed world coordinates) near the village reset its paths. */
  function blocksChanged(changes) {
    if (changes.some(({ x, z }) => Math.abs(x - originX) <= VILLAGE_MARGIN && Math.abs(z - originZ) <= VILLAGE_MARGIN)) {
      grid = null;
    }
  }

  /**
   * Advances the villagers. Returns the door edits they made, as wire edits in
   * stored coordinates, for the room to submit.
   */
  function step(dt, players) {
    elapsed += dt;
    if (elapsed < STEP_SECONDS || players.length === 0) return [];
    elapsed = 0;
    const nearest = players.reduce((best, player) => (
      Math.hypot(player.x - originX, player.z - originZ) < Math.hypot(best.x - originX, best.z - originZ) ? player : best
    ));
    if (grid === null) grid = Villagers.path_grid(seed, edits());
    villagers = Villagers.step_near(villagers, seed, grid, BigInt(tick), 1.0, nearest.x, nearest.z, SIMULATION_RADIUS);
    tick = (tick + 1) % 24;
    const current = edits();
    const opened = Villagers.open_doors(villagers, seed, current);
    const next = Villagers.door_edits(Villagers.update_doors_result(villagers, seed, opened, nearest.x, nearest.z));
    const before = editMap(current);
    const changes = [];
    for (let node = next; node?.$ === "Con"; node = node.tail) {
      const { x, y, z, block } = node.head;
      if (before.get(`${x},${y},${z}`) !== Number(block)) changes.push([Number(x), Number(y), Number(z), Number(block)]);
    }
    return changes;
  }

  return {
    step,
    blocksChanged,
    snapshot: () => ({ villagers: (function list() {
      const wire = [];
      for (let node = villagers; node?.$ === "Con"; node = node.tail) wire.push(villagerToWire(node.head));
      return wire;
    }()), villagerTick: tick }),
  };
}
