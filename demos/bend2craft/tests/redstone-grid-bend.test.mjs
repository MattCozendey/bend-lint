import assert from "node:assert/strict";
import { Redstone, RedstoneGrid as Grid } from "../web/bend-modules.js";

const EMPTY = { $: "Nil" };
const heads = (node) => {
  const out = [];
  for (let cursor = node; cursor?.$ === "Con"; cursor = cursor.tail) out.push(cursor.head);
  return out;
};
// The reached cells as a position -> power map, which is what the two floods have
// to agree about; the order they were discovered in is not part of the contract.
function powerMap(reached) {
  const map = new Map();
  for (const wire of heads(reached)) {
    map.set(`${wire.x},${wire.y},${wire.z}`, Number(wire.power));
  }
  return map;
}

// The window is the circuit's own bounding box and the array is sized to match,
// which is what the browser does. The buffer is deliberately reused across calls
// and only grown, because that is the adapter's side of the contract and it is the
// case that used to break: a fixed window dropped a circuit that reached past it,
// and nothing said so.
const buffer = { grid: new Uint32Array(64), key: null };
const floodKey = (w) => `${w.ox},${w.oy},${w.oz},${w.width},${w.depth},${w.height}`;
function windowFor(state) {
  const window = Grid.flood_of_state(state);
  const cells = Number(Grid.flood_cells(window));
  if (buffer.grid.length < cells) buffer.grid = new Uint32Array(cells);
  // The index is relative to the window's origin, so a mark left under one layout
  // would be read as dust at a different cell under the next. A changed window
  // resets the buffer, which is what web/redstone.js does.
  const key = floodKey(window);
  if (buffer.key !== key) {
    buffer.grid.fill(0);
    buffer.key = key;
  }
  return { window, grid: buffer.grid };
}
// The flood hands the array back beside the reached cells, because in Bend an array
// has one owner: a caller that floods again has to be able to name the array it
// passed in. In JavaScript that is the same object, so the second element is dropped.
const reached = (pair) => pair.fst;

const gridFlood = (state) => {
  const { window, grid } = windowFor(state);
  return reached(Grid.flood_power(Redstone.state_wires(state), Redstone.emits(state, EMPTY), window, grid));
};
const gridResolve = (state, outputs) => {
  const { window, grid } = windowFor(state);
  return Grid.resolve_grid(state, outputs, window, grid).fst;
};

function build(spec) {
  let state = Redstone.empty();
  for (const [x, y, z] of spec.wires ?? []) state = Redstone.place_wire(state, BigInt(x), BigInt(y), BigInt(z));
  for (const [x, y, z] of spec.torches ?? []) state = Redstone.place_torch(state, BigInt(x), BigInt(y), BigInt(z));
  for (const [x, y, z] of spec.blocks ?? []) state = Redstone.place_power_block(state, BigInt(x), BigInt(y), BigInt(z));
  for (const [x, y, z] of spec.lamps ?? []) state = Redstone.place_lamp(state, BigInt(x), BigInt(y), BigInt(z));
  return state;
}

// --- the two floods agree ---------------------------------------------------
function assertAgree(name, spec) {
  const state = build(spec);
  const listResult = powerMap(Redstone.flood_power(Redstone.state_wires(state), Redstone.emits(state, EMPTY)));
  const gridResult = powerMap(gridFlood(state));
  assert.deepEqual(
    [...gridResult.entries()].sort(),
    [...listResult.entries()].sort(),
    `the grid flood must agree with the list flood on ${name}`,
  );
  return listResult;
}

// A plain line off a redstone block, the basic decay.
assertAgree("a line of dust", {
  wires: Array.from({ length: 20 }, (_, i) => [i + 1, 0, 0]),
  blocks: [[0, 0, 0]],
});

// A shape with two arms meeting at a tip, so the first visit is not the closest
// one and the level ordering has to matter.
assertAgree("a U of dust", {
  wires: [
    ...Array.from({ length: 5 }, (_, i) => [i + 1, 0, 0]),
    ...Array.from({ length: 5 }, (_, i) => [i + 1, 0, 1]),
    [3, 0, 2],
  ],
  blocks: [[0, 0, 0]],
});

// A column, which is the direct vertical connection the list flood added.
assertAgree("a column of dust", {
  wires: [[1, 0, 0], [1, 1, 0], [1, 2, 0], [2, 2, 0]],
  blocks: [[0, 0, 0]],
});

// Dust that is not all at once: a gap the signal cannot cross, so the far side
// stays dark in both.
assertAgree("a gap in the dust", {
  wires: [[1, 0, 0], [3, 0, 0], [4, 0, 0]],
  blocks: [[0, 0, 0]],
});

// No source at all: nothing is reached, in either.
assertAgree("an unpowered circuit", { wires: [[1, 0, 0], [2, 0, 0]] });

// A large circuit, the shape the optimisation exists for. The source sits at
// (0, 0, 1) so it is genuinely adjacent to the dust at (1, 0, 1).
{
  const result = assertAgree("a 400 cell circuit", {
    wires: Array.from({ length: 400 }, (_, i) => [i % 40 + 1, 0, Math.floor(i / 40) + 1]),
    blocks: [[0, 0, 1]],
  });
  // The circuit is 40 wide, and a signal dies after fifteen cells, so only the
  // first three columns and a bit are reached. Both floods agree on exactly how
  // many, which is the point.
  assert.equal(result.size, 105, "the signal reaches three and a bit columns");
  assert.equal(result.get("1,0,1"), 15, "the cell beside the source is full power");
  assert.equal(result.get("15,0,1"), 1, "and the fifteenth still carries a signal");
  assert.equal(result.has("16,0,1"), false, "the sixteenth is dark, as in vanilla");
}

// --- the window follows the circuit -----------------------------------------
// This is the case the fixed window got wrong, and it is why the window is derived
// rather than declared. A source on the last cell inside the old 32-wide window,
// with dust one cell past it: the list flood reached the outer cell at power 14
// and the grid flood did not reach it at all, with nothing to say so.
{
  let state = Redstone.place_wire(Redstone.empty(), 31n, 0n, 0n);
  state = Redstone.place_wire(state, 32n, 0n, 0n);
  state = Redstone.place_power_block(state, 30n, 0n, 0n);
  const listResult = powerMap(Redstone.flood_power(Redstone.state_wires(state), Redstone.emits(state, EMPTY)));
  const gridResult = powerMap(gridFlood(state));
  assert.equal(listResult.get("32,0,0"), 14, "the list flood reaches the cell past the old edge");
  assert.equal(gridResult.get("32,0,0"), 14, "and so does the grid flood now");
  assert.deepEqual([...gridResult.entries()].sort(), [...listResult.entries()].sort());
}

// The same, far from the origin in every axis at once, which is what a circuit
// built out in the world looks like rather than one tucked against zero.
{
  let state = Redstone.empty();
  for (let i = 0; i < 12; i++) state = Redstone.place_wire(state, BigInt(200 + i), 40n, 300n);
  state = Redstone.place_power_block(state, 199n, 40n, 300n);
  const listResult = powerMap(Redstone.flood_power(Redstone.state_wires(state), Redstone.emits(state, EMPTY)));
  const gridResult = powerMap(gridFlood(state));
  assert.equal(listResult.size, 12, "the list flood carries the signal all twelve cells");
  assert.deepEqual([...gridResult.entries()].sort(), [...listResult.entries()].sort(),
    "and the grid flood carries it the same distance from a far-off origin");
}

// A circuit taller than the old eight-cell window, which the fixed window could not
// hold either.
{
  let state = Redstone.empty();
  for (let y = 0; y < 20; y++) state = Redstone.place_wire(state, 5n, BigInt(y), 5n);
  state = Redstone.place_power_block(state, 4n, 0n, 5n);
  const listResult = powerMap(Redstone.flood_power(Redstone.state_wires(state), Redstone.emits(state, EMPTY)));
  const gridResult = powerMap(gridFlood(state));
  assert.equal(listResult.size, 20, "a column keeps its level all the way up");
  assert.deepEqual([...gridResult.entries()].sort(), [...listResult.entries()].sort());
}

// The window is the dust's box plus a one-cell margin, so a source beside the dust
// is inside it and a source far away is not - and a far one could not have reached
// dust anyway.
{
  const state = build({ wires: [[10, 10, 10], [11, 10, 10]], blocks: [[9, 10, 10]] });
  const window = Grid.flood_of_state(state);
  assert.equal(Number(window.ox), 9, "the window starts one cell before the dust");
  assert.equal(Number(window.oy), 9);
  assert.equal(Number(window.oz), 9);
  assert.equal(Number(window.width), 4, "two cells of dust plus the margin on each side");
  assert.equal(Number(window.depth), 3, "one cell of dust on that axis, plus the margin");
  assert.equal(Number(window.height), 3, "and a single layer is one cell plus the margin");
  assert.equal(Number(Grid.flood_cells(window)), 36);
}

// Against the origin the margin saturates rather than going negative, so a circuit
// at zero keeps its low edge and the array does not start at a wrapped index.
{
  const state = build({ wires: [[0, 0, 0], [1, 0, 0]], blocks: [[2, 0, 0]] });
  const window = Grid.flood_of_state(state);
  assert.equal(Number(window.ox), 0, "the low edge stays at zero");
  assert.equal(Number(window.oy), 0);
  assert.equal(Number(window.oz), 0);
  assert.equal(Number(Grid.flood_index(window, 0n, 0n, 0n)), 0, "and the origin is index zero");
}

// An empty circuit still has a window, and a one-cell one is enough to hold it.
{
  const window = Grid.flood_of_state(Redstone.empty());
  assert.equal(Number(Grid.flood_cells(window)), 8, "one cell plus the margin on each side");
  assert.equal(powerMap(gridFlood(Redstone.empty())).size, 0, "and nothing is reached");
}

// The box is the dust's own extent, not an origin-anchored one. A circuit far out
// in the world gets a window far out with it, rather than a window reaching all the
// way back to zero - which is what a box folded from zeros would have produced.
{
  let state = Redstone.empty();
  for (let i = 0; i < 6; i++) state = Redstone.place_wire(state, BigInt(1000 + i), 70n, 2000n);
  const window = Grid.flood_of_state(state);
  assert.equal(Number(window.ox), 999, "the window hugs the dust");
  assert.equal(Number(window.oy), 69);
  assert.equal(Number(window.oz), 1999);
  assert.equal(Number(window.width), 8, "six cells of dust plus the margin");
  assert.equal(Number(window.depth), 3);
  assert.equal(Number(window.height), 3);
  assert.equal(Number(Grid.flood_cells(window)), 72, "a small array, not one spanning the origin");
}

// --- the whole fixed point, through the grid --------------------------------
// The point of the module is the tick, not the flood, so the thing that has to hold
// is that `resolve_grid` settles a circuit to exactly what `Redstone.resolve`
// settles it to - every wire's power, every torch and every lamp - because the two
// share the core's pass and differ only in which flood feeds it.
function assertResolves(name, spec) {
  const state = build(spec);
  const outputs = Redstone.emits(state, EMPTY);
  const expected = Redstone.resolve(Redstone.resolve_fuel(), state, outputs);
  const actual = gridResolve(state, outputs);

  const wiresOf = (st) => {
    const map = new Map();
    for (const wire of heads(Redstone.state_wires(st))) {
      map.set(`${wire.x},${wire.y},${wire.z}`, Number(wire.power));
    }
    return map;
  };
  assert.deepEqual(
    [...wiresOf(actual).entries()].sort(),
    [...wiresOf(expected).entries()].sort(),
    `the grid fixed point must settle ${name} the same way the list one does`,
  );
  for (const [x, y, z] of spec.torches ?? []) {
    assert.equal(
      Redstone.torch_lit(actual, BigInt(x), BigInt(y), BigInt(z)),
      Redstone.torch_lit(expected, BigInt(x), BigInt(y), BigInt(z)),
      `the torch at ${x},${y},${z} must settle the same way in ${name}`,
    );
  }
  for (const [x, y, z] of spec.lamps ?? []) {
    assert.equal(
      Redstone.lamp_lit(actual, BigInt(x), BigInt(y), BigInt(z)),
      Redstone.lamp_lit(expected, BigInt(x), BigInt(y), BigInt(z)),
      `the lamp at ${x},${y},${z} must settle the same way in ${name}`,
    );
  }
  return actual;
}

assertResolves("a plain powered line", {
  wires: Array.from({ length: 20 }, (_, i) => [i + 1, 0, 0]),
  blocks: [[0, 0, 0]],
});

assertResolves("a torch inverter", {
  wires: Array.from({ length: 12 }, (_, i) => [i + 1, 0, 0]),
  torches: [[2, 1, 0]],
  blocks: [[0, 0, 0]],
});

// A torch standing on powered dust is an inverter: placed, it burns; once the dust
// under it is live, it goes out. The parity check above would also pass on a loop
// that never ran, so the loop is pinned here against a zero-fuel resolve, which is
// the state exactly as placed.
{
  let state = Redstone.empty();
  for (let i = 1; i <= 12; i++) state = Redstone.place_wire(state, BigInt(i), 0n, 0n);
  state = Redstone.place_torch(state, 2n, 1n, 0n);
  state = Redstone.place_power_block(state, 0n, 0n, 0n);
  const outputs = Redstone.emits(state, EMPTY);

  assert.equal(Redstone.torch_lit(Redstone.resolve(0n, state, outputs), 2n, 1n, 0n), true,
    "a resolve with no fuel leaves the circuit as placed");
  assert.equal(Redstone.torch_lit(gridResolve(state, outputs), 2n, 1n, 0n), false,
    "and the grid loop turns the torch off, as the core does");
}

// A circuit far from the origin settles the same through the grid, which is the
// case the old fixed window could not express at all.
assertResolves("a circuit far from the origin", {
  wires: Array.from({ length: 30 }, (_, i) => [i + 500, 64, 900]),
  torches: [[503, 65, 900]],
  blocks: [[499, 64, 900]],
  lamps: [[502, 65, 900]],
});

// A torch and a lamp side by side: both directions of the same fixed point, so a
// loop that ran a pass too few or one too many shows up as a disagreement.
assertResolves("a torch and a lamp side by side", {
  wires: [[1, 0, 0], [2, 0, 0]],
  torches: [[1, 1, 0]],
  blocks: [[0, 0, 0]],
  lamps: [[2, 1, 0]],
});

// A source sitting exactly on the margin, in every direction. The margin exists
// for the source beside the dust and nothing else, so this is the case that says
// the window is the right size - and a window that was one cell short on the far
// side would drop these seeds and quietly lose power at the circuit's edge.
for (const [dx, dy, dz] of [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]]) {
  assertAgree(`a source on the margin at ${dx},${dy},${dz}`, {
    wires: [[20, 20, 20], [21, 20, 20], [22, 20, 20]],
    blocks: [[20 + dx, 20 + dy, 20 + dz]],
  });
}

// A buffer carried across a change of window. The index is relative to the
// window's origin, so a mark left under one layout means a different cell under the
// next - and the failure is a circuit that reaches cells holding no dust at all,
// which is what this caught.
{
  // One cell of dust at the origin, marked and reached.
  const atOrigin = build({ wires: [[1, 0, 0]], blocks: [[0, 0, 0]] });
  assert.equal(powerMap(gridFlood(atOrigin)).size, 1, "the first circuit reaches its one cell");

  // A different circuit with a different window, on the same buffer. Without the
  // reset the stale mark under the new layout is read as dust at a cell the new
  // circuit has no dust in.
  const elsewhere = build({ wires: [[40, 0, 0]], blocks: [[39, 0, 0]] });
  const listResult = powerMap(Redstone.flood_power(Redstone.state_wires(elsewhere), Redstone.emits(elsewhere, EMPTY)));
  const gridResult = powerMap(gridFlood(elsewhere));
  assert.deepEqual([...gridResult.entries()].sort(), [...listResult.entries()].sort(),
    "a circuit with a different window sees only its own dust");
}

// --- the window packing ----------------------------------------------------
assert.equal(Number(Grid.open_cell()), 0);
assert.equal(Number(Grid.dust_cell()), 1);
assert.equal(Number(Grid.reached_cell()), 2);

{
  // Index packing for a 4 x 4 x 3 window starting at (9, 9, 9).
  const window = { $: "Flood", ox: 9n, oy: 9n, oz: 9n, width: 4n, depth: 4n, height: 3n };
  const index = Grid.flood_index;
  assert.equal(Number(index(window, 9n, 9n, 9n)), 0, "the near corner is index zero");
  assert.equal(Number(index(window, 10n, 9n, 9n)), 1, "x is the fastest axis");
  assert.equal(Number(index(window, 9n, 9n, 10n)), 4, "then z");
  assert.equal(Number(index(window, 9n, 10n, 9n)), 16, "then y");
}

// A step that would leave the window stays put, so a dust cell on the edge cannot
// wrap onto the next row of the array.
{
  const window = { $: "Flood", ox: 0n, oy: 0n, oz: 0n, width: 4n, depth: 4n, height: 3n };
  assert.equal(Number(Grid["flood.step_x"](window, 3n)), 3, "the far edge does not step past itself");
  assert.equal(Number(Grid["flood.step_x"](window, 2n)), 3, "but a cell short of it does");
  assert.equal(Number(Grid["flood.step_back_x"](window, 0n)), 0, "and the near edge does not step below itself");
  assert.equal(Number(Grid["flood.step_y"](window, 2n)), 2, "the same at the top of a short window");
  assert.equal(Number(Grid["flood.step_y"](window, 1n)), 2);
  assert.equal(Grid["flood_fits"](window, 3n, 2n, 2n), true, "the far corner is inside");
  assert.equal(Grid["flood_fits"](window, 4n, 2n, 2n), false, "one past it is not");
  assert.equal(Grid["flood_fits"](window, 3n, 3n, 2n), false, "and neither is the top face");
  assert.equal(Grid["flood_fits"](window, 0n, 0n, 0n), true, "the near corner is inside");

  // The whole margin, in every direction, is inside the window: a source beside
  // the dust sits on it, and a source that is not inside is not seeded at all.
  for (const [x, y, z] of [[0, 0, 0], [3, 0, 0], [0, 2, 0], [0, 0, 2], [3, 2, 2]]) {
    assert.equal(Grid["flood_fits"](window, BigInt(x), BigInt(y), BigInt(z)), true,
      `the corner at ${x},${y},${z} is inside`);
  }
}

console.log("bend redstone grid ok");
