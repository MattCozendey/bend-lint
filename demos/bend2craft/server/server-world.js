// Everything the multiplayer server simulates, over one terrain cache:
// mobs and drops (mob-world.js), fluids, fire, crops and farmland (the shared
// web/world-simulation.js), and villagers (villager-world.js).
//
// The room (multiplayer-room.js) owns the edit log through the Bend room
// contract. This module never writes the log itself: block changes it makes
// are queued as wire edits, the room submits them to Bend like a player's
// batch, and the accepted edits come back through `applyEdits`.
import { Multiplayer } from "../web/bend-modules.js";
import { decodeSave, encodeSave } from "../web/save-state.js";
import { createWorldSimulation, isFluidBlock, restoreSimulationState } from "../web/world-simulation.js";
import { storageCoordinate, worldCoordinate } from "../web/world-coordinates.js";
import { createMobWorld } from "./mob-world.js";
import { createMoveGuard } from "./move-guard.js";
import { createVillagerWorld } from "./villager-world.js";
import { CHUNK_SIZE, createWorldCache } from "./world-cache.js";

const EVICT_EVERY_TICKS = 50;
const WATER = 7;
const LAVA = 21;

/**
 * @param {object} options
 * @param {bigint} options.seed
 * @param {() => object} options.edits  the room's current Bend edit log
 * @param {boolean} [options.peaceful]
 * @param {string|null} [options.saved]  a previous `persistentState()`
 * @param {() => number} [options.random]
 */
export function createServerWorld({ seed, edits, peaceful = false, saved = null, random = Math.random }) {
  const cache = createWorldCache({ seed, edits });
  const pending = [];
  const queue = (x, y, z, value) => pending.push([storageCoordinate(x, CHUNK_SIZE), y, storageCoordinate(z, CHUNK_SIZE), value]);
  const simulation = createWorldSimulation({
    seed,
    chunkSize: CHUNK_SIZE,
    state: restoreSimulationState(typeof saved === "string" ? decodeSave(saved) : null),
    world: {
      blockAt: cache.blockAt,
      inside: cache.inside,
      // The cache loads any chunk on demand, so every cell simulates.
      isActive: () => true,
      setBlocks(changes) {
        for (const { x, y, z, value } of changes) {
          cache.write(x, y, z, value);
          queue(x, y, z, value);
        }
      },
      pinChunk: () => {},
      unpinChunk: () => {},
    },
  });
  simulation.pinStored();
  const mobs = createMobWorld({ seed, cache, edits, peaceful, random });
  const villagers = createVillagerWorld({ seed, edits });
  const moves = createMoveGuard({ seed, cache });
  let ticks = 0;
  let simulationDirty = false;

  /** Accepted wire edits: the cache, the crops and the villagers follow them. */
  function applyEdits(wireEdits) {
    const changes = cache.applyEdits(wireEdits);
    for (const change of changes) {
      if (change.previous !== null && change.previous !== change.value) {
        simulation.blockChanged(change.x, change.y, change.z, change.previous, change.value);
        simulationDirty = true;
      }
    }
    mobs.blocksChanged(changes);
    villagers.blocksChanged(changes);
  }

  function anchors(players) {
    const cells = [...simulation.cropViews(), ...simulation.farmlandViews()];
    return [...players, ...mobs.anchors(), ...cells];
  }

  /**
   * One step (TICK_MS). `players` are [{ id, x, y, z }] with a known pose.
   * Returns the damage per player; queued edits are taken with takeEdits().
   */
  function tick(dt, time, players) {
    const hurts = mobs.tick(dt, time, players);
    if (players.length > 0) {
      simulation.tick();
      simulation.syncBlocks();
      simulationDirty = true;
      pending.push(...villagers.step(dt, players));
    }
    ticks += 1;
    if (ticks % EVICT_EVERY_TICKS === 0) cache.evict(anchors(players));
    return hurts;
  }

  function takeEdits() {
    return pending.splice(0, pending.length);
  }

  /**
   * A player's world interaction at a stored position: "water", "lava",
   * "fire", "collect", "till", "plant" or "harvest". The cell must be within
   * reach of the player's pose. Returns the answer for the player.
   */
  function interact(pose, op, [storedX, y, storedZ]) {
    const x = worldCoordinate(storedX);
    const z = worldCoordinate(storedZ);
    if (pose === null || !Multiplayer.within_reach(pose.x, pose.y, pose.z, x + 0.5, y + 0.5, z + 0.5)) {
      return { ok: false, reason: "reach" };
    }
    simulationDirty = true;
    switch (op) {
      case "water":
        return { ok: simulation.seedFluid(WATER, x, y, z, 8) };
      case "lava":
        return { ok: simulation.seedFluid(LAVA, x, y, z, 8) };
      case "fire":
        return { ok: simulation.ignite(x, y, z) };
      case "collect": {
        if (!isFluidBlock(cache.blockAt(x, y, z))) return { ok: false };
        const block = simulation.removeFluid(x, y, z);
        return { ok: block !== 0, block };
      }
      case "till":
        return { ok: simulation.till(x, y, z) };
      case "plant":
        return { ok: simulation.plant(x, y, z) };
      case "harvest": {
        const result = simulation.harvest(x, y, z);
        return { ok: result.ok, seeds: result.seeds, wheat: result.wheat };
      }
      default:
        return { ok: false };
    }
  }

  return {
    tick,
    takeEdits,
    applyEdits,
    interact,
    attack: mobs.attack,
    pickup: mobs.pickup,
    addDrop: mobs.addDrop,
    /** Whether a player may move from its last accepted pose (null: none yet) to `to`. */
    checkMove: moves.check,
    forgetPlayer: moves.forget,
    snapshot: () => ({ ...mobs.snapshot(), ...villagers.snapshot() }),
    /** The simulation state to save, or null when nothing changed since the last call. */
    persistentState(force = false) {
      if (!simulationDirty && !force) return null;
      simulationDirty = false;
      return encodeSave(simulation.state());
    },
    simulation,
    cache,
    mobs,
  };
}
