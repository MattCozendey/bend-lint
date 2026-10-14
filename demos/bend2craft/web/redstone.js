import { RedstoneAll, Redstone, RedstoneGrid } from "./bend-modules.js";

// ---------------------------------------------------------------------------
// Redstone adapter
//
// The adapter's whole job is: hold the circuit, gather the handful of world
// samples a redstone rule needs, call the Bend contract once per tick, and apply
// the world edits it gets back. It decides nothing. Every power level, every
// edge, every push and every delay is computed in Bend 2 - see
// world/redstone.bend, world/redstone_clock.bend, world/redstone_machines.bend
// and the world/redstone_all.bend entry point that orders them.
//
// Following the project constitution, this is presentation and cache work only:
// materialising Bend values, reading the world's block ids, and applying the
// edits. It does not loop over the circuit a cell at a time; the contract
// returns the power for a position, and this asks it once per cell it needs.
// ---------------------------------------------------------------------------

const EMPTY = { $: "Nil" };

// What makes a window a different window. The array's index is relative to the
// window's origin, so the same slot means a different cell under a different
// layout, and a buffer may only be carried over while the layout is identical.
const floodKey = (window) =>
  `${window.ox},${window.oy},${window.oz},${window.width},${window.depth},${window.height}`;

// The dust flood runs on an array the size of the circuit, and the array is the
// caller's own - the contract writes its reached marks into it in place. So the
// adapter owns one buffer, keeps it for as long as it is big enough, and grows it
// when a circuit outgrows it. Sizing a buffer is cache management, which is the
// adapter's job; what the window has to cover is world/redstone_grid.bend's.
// Item ids 51 through 62 carry the same order as `is_block_item` prints them
// in `world/inventory.bend` - one picked by each redstone block in `block_ids`
// order, minus the piston head. `Inventory.placed_block` refuses to name a
// redstone block, so this is the one place item names redstone's blocks.
export function redstoneBlockForItem(item) {
  const n = Number(item);
  if (!Number.isInteger(n) || n < 51 || n > 62) return null;
  const blocks = [];
  for (let node = Redstone.block_ids(); node?.$ === "Con"; node = node.tail) {
    const id = Number(node.head);
    if (id !== Number(Redstone.head_block())) blocks.push(id);
  }
  return blocks[n - 51] ?? null;
}

export function createRedstone(saved) {
  const circuit = saved?.$ === "Circuit" ? saved : RedstoneAll.empty();
  return {
    circuit,
    grid: new Uint32Array(64),
    gridKey: null,
    // The block ids a redstone rule may ask the world about. Redstone defines
    // these in one place; the game checks against the same constants rather than
    // repeating the numbers, so a redstone block can never drift from the
    // renderer.
    ids: Object.freeze({
      wire: Number(Redstone.wire_block()),
      torch: Number(Redstone.torch_block()),
      lever: Number(Redstone.lever_block()),
      power: Number(Redstone.power_block()),
      lamp: Number(Redstone.lamp_block()),
      repeater: Number(Redstone.repeater_block()),
      comparator: Number(Redstone.comparator_block()),
      plate: Number(Redstone.plate_block()),
      rail: Number(Redstone.rail_block()),
      piston: Number(Redstone.piston_block()),
      head: Number(Redstone.head_block()),
      stickyPiston: Number(Redstone.sticky_piston_block()),
      observer: Number(Redstone.observer_block()),
    }),
  };
}

export function circuitOf(state) {
  return state.circuit;
}

function cons(list, head) {
  return { $: "Con", head, tail: list };
}

// The world samples a redstone rule needs this tick, gathered once and handed to
// the contract. This is the boundary the constitution asks for: the browser
// collects the facts, the contract decides what they mean.
function gatherSamples(circuit, blockAt, inside) {
  let samples = EMPTY;
  const core = RedstoneAll.circuit_core(circuit);
  const machines = RedstoneAll.circuit_machines(circuit);

  // A pressure plate asks what is standing on it; a piston asks what is in the
  // three cells along its face; an observer asks what is in the one cell in front
  // of it. Those are the only world facts the machines consult, so those are the
  // only cells read here.
  const wanted = new Set();
  for (let node = machines.plates; node?.$ === "Con"; node = node.tail) {
    const cell = node.head;
    wanted.add(`${Number(cell.x)},${Number(cell.y) + 1},${Number(cell.z)}`);
  }
  for (let node = machines.pistons; node?.$ === "Con"; node = node.tail) {
    const cell = node.head;
    // A Bend `Nat` crosses as a BigInt; the sample keys below are plain numbers
    // so they can be compared with the world's own cell ids.
    const x = Number(cell.x);
    const y = Number(cell.y);
    const z = Number(cell.z);
    const [dx, dy, dz] = faceStep(Number(cell.face));
    for (let step = 1; step <= 3; step += 1) {
      wanted.add(`${x + dx * step},${y + dy * step},${z + dz * step}`);
    }
  }
  for (let node = machines.observers; node?.$ === "Con"; node = node.tail) {
    const cell = node.head;
    const [dx, dy, dz] = faceStep(Number(cell.face));
    // The face arithmetic is the contract's, so the cell read here is the cell it
    // watches - including the case where the step saturates onto the observer
    // itself, which the contract then declines to watch.
    wanted.add(`${Number(cell.x) + dx},${Number(cell.y) + dy},${Number(cell.z) + dz}`);
  }
  for (const key of wanted) {
    const [x, y, z] = key.split(",").map((value) => Number(value));
    if (!inside(x, y, z)) continue;
    samples = cons(samples, Redstone.sample(BigInt(x), BigInt(y), BigInt(z), Number(blockAt(x, y, z) ?? 0)));
  }
  void core;
  return samples;
}

// The unit step of a piston face, matching world/redstone_machines.bend.
function faceStep(face) {
  switch (face) {
    case 0:
      return [1, 0, 0];
    case 1:
      return [-1, 0, 0];
    case 2:
      return [0, 0, 1];
    case 3:
      return [0, 0, -1];
    case 4:
      return [0, 1, 0];
    default:
      return [0, -1, 0];
  }
}

// One game tick. Returns the world edits the machines asked for; the caller
// applies them. The circuit is updated in place on the state object.
export function tickRedstone(state, blockAt, inside) {
  const circuit = state.circuit;
  const emits = Redstone.emits(RedstoneAll.circuit_core(circuit), EMPTY);
  const samples = gatherSamples(circuit, blockAt, inside);
  // The window is the dust's own bounding box and the array is sized to match. It
  // can only be reused while that box has not moved: the index is relative to the
  // window's origin, so a mark left by one layout would be read as dust at a
  // different cell under the next. A changed window therefore resets the buffer,
  // which is one native fill rather than an allocation.
  const window = RedstoneGrid.flood_of_state(RedstoneAll.circuit_core(circuit));
  const cells = Number(RedstoneGrid.flood_cells(window));
  if (state.grid.length < cells) state.grid = new Uint32Array(cells);
  const key = floodKey(window);
  if (state.gridKey !== key) {
    state.grid.fill(0);
    state.gridKey = key;
  }
  const stepped = RedstoneAll.tick(circuit, emits, samples, window, state.grid).fst;
  state.circuit = RedstoneAll.stepped_circuit(stepped);

  const edits = [];
  for (let node = RedstoneAll.stepped_edits(stepped); node?.$ === "Con"; node = node.tail) {
    const edit = node.head;
    edits.push({
      x: Number(edit.x),
      y: Number(edit.y),
      z: Number(edit.z),
      value: Number(edit.block),
    });
  }
  return edits;
}

// --- placing and breaking ---------------------------------------------------
//
// The world tells the adapter which block a player put down or knocked out; the
// adapter tells the contract. Which component that block is, and what a piston
// head belongs to, is read from the circuit rather than guessed here.

export function placeRedstoneComponent(circuit, block, x, y, z) {
  const bx = BigInt(x);
  const by = BigInt(y);
  const bz = BigInt(z);
  switch (block) {
    case 28:
      return RedstoneAll.place_wire(circuit, bx, by, bz);
    case 29:
      return RedstoneAll.place_torch(circuit, bx, by, bz);
    case 30:
      return RedstoneAll.place_lever(circuit, bx, by, bz, false);
    case 31:
      return RedstoneAll.place_power_block(circuit, bx, by, bz);
    case 32:
      return RedstoneAll.place_lamp(circuit, bx, by, bz);
    case 33:
      return RedstoneAll.place_repeater(circuit, bx, by, bz, 0, 0);
    case 34:
      return RedstoneAll.place_comparator(circuit, bx, by, bz, 0, 0);
    case 35:
      return RedstoneAll.place_door(circuit, bx, by, bz);
    case 36:
      return RedstoneAll.place_rail(circuit, bx, by, bz);
    case 37:
      return RedstoneAll.place_piston(circuit, bx, by, bz, 0, false);
    case 39:
      return RedstoneAll.place_piston(circuit, bx, by, bz, 0, true);
    case 40:
      return RedstoneAll.place_observer(circuit, bx, by, bz, 0);
    default:
      return circuit;
  }
}

// A lever is the one redstone block a player operates rather than places.
export function toggleLever(state, x, y, z) {
  state.circuit = RedstoneAll.flip_lever(state.circuit, BigInt(x), BigInt(y), BigInt(z));
}

// Break a redstone block. A piston head is the one block that is not its own
// component: the player broke the head, so the piston that pushed it goes back
// in. The circuit knows which piston owns a head, so the adapter asks it rather
// than searching the world for a base.
export function breakRedstoneAt(state, x, y, z) {
  const owner = findPistonHeadOwner(state.circuit, x, y, z);
  state.circuit = RedstoneAll.remove_at(
    state.circuit,
    BigInt(owner === null ? x : owner.x),
    BigInt(y),
    BigInt(owner === null ? z : owner.z),
  );
  return owner;
}

// The base of the piston whose head currently sits at this cell, or null.
function findPistonHeadOwner(circuit, x, y, z) {
  const machines = RedstoneAll.circuit_machines(circuit);
  for (let node = machines.pistons; node?.$ === "Con"; node = node.tail) {
    const piston = node.head;
    if (!All_isExtended(piston)) continue;
    const [dx, dy, dz] = faceStep(Number(piston.face));
    const hx = Number(piston.x) + dx;
    const hy = Number(piston.y) + dy;
    const hz = Number(piston.z) + dz;
    if (hx === x && hy === y && hz === z) {
      return { x: Number(piston.x), y: Number(piston.y), z: Number(piston.z) };
    }
  }
  return null;
}

function All_isExtended(piston) {
  return piston.extended === true || piston.extended?.$ === "True";
}

// --- reading the circuit for the renderer ----------------------------------
//
// The renderer needs to know, per block, what to draw: a dust cell's brightness
// follows its power, a torch and a lamp follow whether they are on. These read
// the settled contract; they compute nothing.

export function wirePowerAt(state, x, y, z) {
  return Number(RedstoneAll.wire_power(state.circuit, BigInt(x), BigInt(y), BigInt(z)));
}

export function torchLitAt(state, x, y, z) {
  return RedstoneAll.torch_lit(state.circuit, BigInt(x), BigInt(y), BigInt(z));
}

export function lampLitAt(state, x, y, z) {
  return RedstoneAll.lamp_lit(state.circuit, BigInt(x), BigInt(y), BigInt(z));
}

export function pistonExtendedAt(state, x, y, z) {
  return RedstoneAll.piston_is_extended(state.circuit, BigInt(x), BigInt(y), BigInt(z));
}

// The dust tone for a power level, from the unpowered base colour in the block
// contract up to a lit one. The renderer blends these; the rule that a level is
// 0-15 is the contract's.
export function wireColor(state, ids, baseColor, litColor, x, y, z) {
  const power = wirePowerAt(state, x, y, z);
  void ids;
  return { power, color: blend(baseColor, litColor, power / 15) };
}

function blend(from, to, amount) {
  const a = parseInt(from.slice(1), 16);
  const b = parseInt(to.slice(1), 16);
  const mix = (shift) => {
    const left = (a >> shift) & 0xff;
    const right = (b >> shift) & 0xff;
    return Math.round(left + (right - left) * amount);
  };
  return `rgb(${mix(16)}, ${mix(8)}, ${mix(0)})`;
}
