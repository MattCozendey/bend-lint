// The block-level world simulation: fluids, fire, crops and farmland, driven
// by the Bend contracts in world/simulation.bend, fluids.bend, fire.bend,
// crops.bend and farmland.bend.
//
// Single player runs it over the browser's chunk cache; the multiplayer server
// runs the same module over its own cache (server/world-cache.js). The module
// owns the simulation state and turns Bend's results into block changes; the
// host decides how a change reaches the world (`world.setBlocks`) and what it
// costs the player (inventory stays with the caller).
import { Crops, Farmland, Fire, Fluids, Simulation, Structures, bareTag } from "./bend-modules.js";

export const WATER = 7;
export const LAVA = 21;
export const FIRE = 24;
export const FARMLAND = 20;
export const FIRST_CROP_BLOCK = 16;
export const RIPE_CROP_BLOCK = 19;

export function isFluidBlock(block) {
  return block === WATER || block === LAVA;
}

export function isTransientBlock(block) {
  return isFluidBlock(block) || block === FIRE;
}

export function isCropBlock(block) {
  return block >= FIRST_CROP_BLOCK && block <= RIPE_CROP_BLOCK;
}

function bendList(items) {
  let list = { $: "Nil" };
  for (let index = items.length - 1; index >= 0; index -= 1) list = { $: "Con", head: items[index], tail: list };
  return list;
}

// Saves from before the fluid `source` and `block` fields existed carry flows
// without them; they are filled with the defaults the rules assume.
export function normalizeFluidState(value) {
  if (bareTag(value?.$) !== "State") return Fluids.empty();
  const flows = [];
  for (let node = value.flows; node?.$ === "Con"; node = node.tail) {
    const flow = node.head;
    flows.push({
      $: "Flow",
      x: flow.x,
      y: flow.y,
      z: flow.z,
      level: flow.level,
      source: flow.source ?? false,
      block: flow.block ?? WATER,
    });
  }
  return { $: "State", flows: bendList(flows) };
}

/** The simulation state a save carries, or a fresh one. */
export function restoreSimulationState(saved) {
  // The nested states arrive carrying their owner's qualifier (`crops.State`),
  // so the two checks have to read the bare tag; the outer one is this module's
  // own type and comes back bare.
  let simulation = saved?.simulation?.$ === "Simulation"
    && bareTag(saved.simulation.crops?.$) === "State"
    && bareTag(saved.simulation.farmland?.$) === "State"
    ? saved.simulation
    : Simulation.empty();
  const crops = bareTag(saved?.crops?.$) === "State" ? saved.crops : Simulation.sim_crops(simulation);
  const farmland = bareTag(saved?.farmland?.$) === "State" ? saved.farmland : Simulation.sim_farmland(simulation);
  simulation = Simulation.with_crops(simulation, crops);
  simulation = Simulation.with_farmland(simulation, farmland);
  return {
    simulation,
    crops,
    farmland,
    fluids: bareTag(saved?.fluids?.$) === "State" ? Fluids.limit(normalizeFluidState(saved.fluids)) : Fluids.empty(),
    fire: bareTag(saved?.fire?.$) === "State" ? saved.fire : Fire.empty(),
  };
}

/**
 * @param {object} options
 * @param {bigint} options.seed
 * @param {number} options.chunkSize
 * @param {object} options.world  { blockAt(x, y, z), inside(x, y, z), isActive(x, z),
 *   setBlocks(changes), pinChunk(chunkX, chunkZ), unpinChunk(chunkX, chunkZ) }
 * @param {object} [options.state]  from restoreSimulationState
 * @param {(chunkX: number, chunkZ: number) => boolean} [options.keepChunk]
 *   other reasons (furnaces) to keep a chunk pinned when crops leave it
 */
export function createWorldSimulation({ seed, chunkSize, world, state = restoreSimulationState(null), keepChunk = () => false }) {
  let { simulation, crops, farmland, fluids, fire } = state;
  const villageChunkX = Math.floor(Number(Structures.village_origin_x(seed)) / chunkSize);
  const villageChunkZ = Math.floor(Number(Structures.village_origin_z(seed)) / chunkSize);

  const chunkOf = (value) => Math.floor(value / chunkSize);
  const blockAt = (x, y, z) => Number(world.blockAt(x, y, z) ?? 0);
  const simulated = (x, y, z) => world.inside(x, y, z) && world.isActive(x, z);

  function pin(chunkX, chunkZ) {
    world.pinChunk(chunkX, chunkZ);
    simulation = Simulation.pin(simulation, BigInt(chunkX), BigInt(chunkZ));
  }

  function unpin(chunkX, chunkZ) {
    world.unpinChunk(chunkX, chunkZ);
    simulation = Simulation.unpin(simulation, BigInt(chunkX), BigInt(chunkZ));
  }

  function hasEntryInChunk(entries, chunkX, chunkZ) {
    for (let node = entries; node?.$ === "Con"; node = node.tail) {
      if (chunkOf(Number(node.head.x)) === chunkX && chunkOf(Number(node.head.z)) === chunkZ) return true;
    }
    return false;
  }

  function releaseChunk(chunkX, chunkZ) {
    if (chunkX === villageChunkX && chunkZ === villageChunkZ) return;
    if (keepChunk(chunkX, chunkZ)) return;
    if (hasEntryInChunk(Crops.entries(crops), chunkX, chunkZ)) return;
    if (hasEntryInChunk(Farmland.entries(farmland), chunkX, chunkZ)) return;
    unpin(chunkX, chunkZ);
  }

  // The village's fields always simulate, and every stored crop or plot pins
  // its chunk so it keeps growing out of view.
  function pinStored() {
    pin(villageChunkX, villageChunkZ);
    for (const entries of [Crops.entries(crops), Farmland.entries(farmland)]) {
      for (let node = entries; node?.$ === "Con"; node = node.tail) pin(chunkOf(Number(node.head.x)), chunkOf(Number(node.head.z)));
    }
  }

  function apply(changes) {
    if (changes.length > 0) world.setBlocks(changes);
    return changes;
  }

  // Crop and farmland blocks follow their state (a crop grows a stage, a plot
  // is restored after a reload).
  function syncBlocks() {
    const changes = [];
    for (let node = Crops.entries(crops); node?.$ === "Con"; node = node.tail) {
      const crop = node.head;
      const x = Number(crop.x);
      const y = Number(crop.y);
      const z = Number(crop.z);
      const block = Number(Crops.crop_block(crop));
      if (blockAt(x, y, z) !== block) changes.push({ x, y, z, value: block });
    }
    for (let node = Farmland.entries(farmland); node?.$ === "Con"; node = node.tail) {
      const plot = node.head;
      const x = Number(plot.x);
      const y = Number(plot.y);
      const z = Number(plot.z);
      if (blockAt(x, y, z) !== FARMLAND) changes.push({ x, y, z, value: FARMLAND });
    }
    return apply(changes);
  }

  function waterSourcesForFarmland() {
    const waters = [];
    for (let node = Farmland.entries(farmland); node?.$ === "Con"; node = node.tail) {
      const plot = node.head;
      const x = Number(plot.x);
      const y = Number(plot.y);
      const z = Number(plot.z);
      for (let dx = -4; dx <= 4; dx += 1) {
        for (let dz = -4; dz <= 4; dz += 1) {
          const waterX = x + dx;
          const waterZ = z + dz;
          if (!world.inside(waterX, y, waterZ)) continue;
          if (blockAt(waterX, y, waterZ) !== WATER && blockAt(waterX, y + 1, waterZ) !== WATER) continue;
          waters.push({ $: "Water", x: BigInt(waterX), z: BigInt(waterZ) });
        }
      }
    }
    return bendList(waters.reverse());
  }

  // The cells a fluid rule asks about around each live flow: the one below it,
  // the four beside it, and the one above it. The cell above is what tells a
  // flow that a column landed on it, so a pool spreads where the water fell;
  // without it the rules read that cell as stone and the pool stops there.
  function fluidSamples(list) {
    const unique = new Map();
    for (let node = list; node?.$ === "Con"; node = node.tail) {
      const x = Number(node.head.x);
      const y = Number(node.head.y);
      const z = Number(node.head.z);
      for (const [sampleX, sampleY, sampleZ] of [
        [x, y - 1, z], [x, y + 1, z],
        [x - 1, y, z], [x + 1, y, z],
        [x, y, z - 1], [x, y, z + 1],
      ]) {
        if (!simulated(sampleX, sampleY, sampleZ)) continue;
        const key = `${sampleX},${sampleY},${sampleZ}`;
        if (!unique.has(key)) {
          unique.set(key, Fluids.sample(BigInt(sampleX), BigInt(sampleY), BigInt(sampleZ), Number(world.blockAt(sampleX, sampleY, sampleZ) ?? 1)));
        }
      }
    }
    return bendList([...unique.values()]);
  }

  function fireSamples(cells, flows) {
    const unique = new Map();
    for (const list of [cells, flows]) {
      for (let node = list; node?.$ === "Con"; node = node.tail) {
        const x = Number(node.head.x);
        const y = Number(node.head.y);
        const z = Number(node.head.z);
        for (let dy = -1; dy <= 1; dy += 1) {
          for (let dx = -1; dx <= 1; dx += 1) {
            for (let dz = -1; dz <= 1; dz += 1) {
              const sampleX = x + dx;
              const sampleY = y + dy;
              const sampleZ = z + dz;
              if (!simulated(sampleX, sampleY, sampleZ)) continue;
              const key = `${sampleX},${sampleY},${sampleZ}`;
              if (!unique.has(key)) {
                unique.set(key, Fire.sample(BigInt(sampleX), BigInt(sampleY), BigInt(sampleZ), Number(world.blockAt(sampleX, sampleY, sampleZ) ?? 1)));
              }
            }
          }
        }
      }
    }
    return bendList([...unique.values()]);
  }

  /**
   * One simulation step: fluids flow and react, fire spreads and burns out,
   * crops grow on hydrated farmland. Returns the block changes it made.
   */
  function tick() {
    const flows = Fluids.state_flows(fluids);
    const samples = fluidSamples(flows);
    const previousFluids = fluids;
    const previousFire = fire;
    const fireSampleList = fireSamples(Fire.state_cells(fire), flows);
    const reactionEdits = Fluids.reactions(fluids, samples);
    const advanced = Simulation.tick_with_fluids_and_fire(
      simulation,
      1n,
      waterSourcesForFarmland(),
      Fluids.react(fluids, samples),
      samples,
      fire,
      fireSampleList,
    );
    simulation = Simulation.tick_simulation(advanced);
    fluids = Simulation.tick_fluids(advanced);
    fire = Simulation.tick_fire(advanced);
    crops = Simulation.sim_crops(simulation);
    farmland = Simulation.sim_farmland(simulation);
    const changes = [];
    for (let node = Fluids.changes(previousFluids, fluids); node?.$ === "Con"; node = node.tail) {
      const x = Number(node.head.x);
      const y = Number(node.head.y);
      const z = Number(node.head.z);
      const value = Number(node.head.block);
      if (!simulated(x, y, z)) continue;
      const current = blockAt(x, y, z);
      if (value !== 0 && (isFluidBlock(value) || value === FIRE) && current !== 0) continue;
      if (value === 0 && !isTransientBlock(current)) continue;
      changes.push({ x, y, z, value });
    }
    for (let node = reactionEdits; node?.$ === "Con"; node = node.tail) {
      const x = Number(node.head.x);
      const y = Number(node.head.y);
      const z = Number(node.head.z);
      if (!simulated(x, y, z)) continue;
      changes.push({ x, y, z, value: Number(node.head.block) });
    }
    for (let node = Fire.changes(previousFire, fire); node?.$ === "Con"; node = node.tail) {
      const x = Number(node.head.x);
      const y = Number(node.head.y);
      const z = Number(node.head.z);
      const value = Number(node.head.block);
      if (!simulated(x, y, z)) continue;
      const current = blockAt(x, y, z);
      if (value !== 0 && value === FIRE && current !== 0) continue;
      if (value === 0 && current !== FIRE) continue;
      changes.push({ x, y, z, value });
    }
    return apply(changes);
  }

  function airAt(x, y, z) {
    return simulated(x, y, z) && blockAt(x, y, z) === 0;
  }

  /** Starts a water (or lava) source in an air cell. */
  function seedFluid(block, x, y, z, level = 8) {
    if (!airAt(x, y, z)) return false;
    fluids = block === LAVA
      ? Fluids.seed_lava(fluids, BigInt(x), BigInt(y), BigInt(z), Number(level))
      : Fluids.seed(fluids, BigInt(x), BigInt(y), BigInt(z), Number(level));
    apply([{ x, y, z, value: block }]);
    return true;
  }

  /** Takes the fluid out of a water or lava cell (a bucket fill). */
  function removeFluid(x, y, z) {
    const block = blockAt(x, y, z);
    if (!isFluidBlock(block)) return 0;
    fluids = Fluids.remove(fluids, BigInt(x), BigInt(y), BigInt(z));
    apply([{ x, y, z, value: 0 }]);
    return block;
  }

  function ignite(x, y, z) {
    if (!airAt(x, y, z)) return false;
    fire = Fire.ignite(fire, BigInt(x), BigInt(y), BigInt(z));
    apply([{ x, y, z, value: FIRE }]);
    return true;
  }

  /** Dirt or grass becomes farmland. */
  function till(x, y, z) {
    const ground = blockAt(x, y, z);
    if (ground !== 2 && ground !== 3) return false;
    farmland = Farmland.add(farmland, BigInt(x), BigInt(y), BigInt(z)).state;
    simulation = Simulation.with_farmland(simulation, farmland);
    pin(chunkOf(x), chunkOf(z));
    apply([{ x, y, z, value: FARMLAND }]);
    return true;
  }

  /** Plants wheat above farmland; false when Crops.plant refuses. */
  function plant(x, y, z) {
    const result = Crops.plant(crops, BigInt(x), BigInt(y), BigInt(z), blockAt(x, y - 1, z), blockAt(x, y, z));
    if (!result.ok) return false;
    crops = result.state;
    simulation = Simulation.with_crops(simulation, crops);
    pin(chunkOf(x), chunkOf(z));
    apply([{ x, y, z, value: FIRST_CROP_BLOCK }]);
    return true;
  }

  /**
   * Harvests the crop at a cell. `accept(result)` sees `{ seeds, wheat }` and
   * returns whether the harvest may happen (the caller's inventory has room).
   */
  function harvest(x, y, z, accept = () => true) {
    const result = Crops.harvest(crops, BigInt(x), BigInt(y), BigInt(z));
    if (!result.ok) return { ok: false, seeds: 0, wheat: 0 };
    const yielded = { seeds: Number(result.seeds), wheat: Number(result.wheat) };
    if (!accept(yielded)) return { ok: false, ...yielded, refused: true };
    crops = result.state;
    simulation = Simulation.with_crops(simulation, crops);
    apply([{ x, y, z, value: 0 }]);
    releaseChunk(chunkOf(x), chunkOf(z));
    return { ok: true, ...yielded };
  }

  /**
   * A block was replaced by something else (mined, built over): a crop or plot
   * that stood there is gone, and its chunk may stop simulating.
   */
  function blockChanged(x, y, z, previous, value) {
    if (isCropBlock(previous) && !isCropBlock(value)) {
      crops = Crops.remove(crops, BigInt(x), BigInt(y), BigInt(z));
      simulation = Simulation.with_crops(simulation, crops);
      releaseChunk(chunkOf(x), chunkOf(z));
    }
    if (previous === FARMLAND && value !== FARMLAND) {
      farmland = Farmland.remove(farmland, BigInt(x), BigInt(y), BigInt(z));
      simulation = Simulation.with_farmland(simulation, farmland);
      releaseChunk(chunkOf(x), chunkOf(z));
    }
  }

  function cropViews() {
    const views = [];
    for (let node = Crops.entries(crops); node?.$ === "Con"; node = node.tail) {
      const crop = node.head;
      views.push({ x: Number(crop.x), y: Number(crop.y), z: Number(crop.z), stage: Number(crop.stage), age: Number(crop.age) });
    }
    return views;
  }

  function farmlandViews() {
    const views = [];
    for (let node = Farmland.entries(farmland); node?.$ === "Con"; node = node.tail) {
      const plot = node.head;
      views.push({ x: Number(plot.x), y: Number(plot.y), z: Number(plot.z), moisture: Number(plot.moisture) });
    }
    return views;
  }

  return {
    tick,
    syncBlocks,
    pinStored,
    pin,
    unpin,
    releaseChunk,
    seedFluid,
    removeFluid,
    ignite,
    till,
    plant,
    harvest,
    blockChanged,
    cropViews,
    farmlandViews,
    state: () => ({ simulation, crops, farmland, fluids, fire }),
    get simulation() { return simulation; },
    get crops() { return crops; },
    get farmland() { return farmland; },
    get fluids() { return fluids; },
    get fire() { return fire; },
  };
}
