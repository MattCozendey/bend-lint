import assert from "node:assert/strict";
import { Multiplayer, WorldState, World } from "../web/bend-modules.js";

const SEED = 1337n;
const list = (items) => items.reduceRight((tail, head) => ({ $: "Con", head, tail }), { $: "Nil" });
const array = (node) => {
  const items = [];
  for (; node?.$ === "Con"; node = node.tail) items.push(node.head);
  assert.equal(node?.$, "Nil");
  return items;
};
const edit = (x, y, z, block) => WorldState.make_edit(BigInt(x), BigInt(y), BigInt(z), block);
const cells = (edits) => array(edits).map((e) => [Number(e.x), Number(e.y), Number(e.z), Number(e.block)]);

// An empty room starts at sequence 0 with no edits.
const empty = Multiplayer.empty();
assert.equal(Number(Multiplayer.room_seq(empty)), 0);
assert.equal(Multiplayer.room_edits(empty).$, "Nil");

// Valid edits are accepted in order, applied, and advance the sequence.
const first = Multiplayer.submit(empty, list([edit(40, 8, 40, 12), edit(41, 8, 40, 0)]));
const room1 = Multiplayer.submission_room(first);
assert.equal(Number(Multiplayer.room_seq(room1)), 1);
assert.deepEqual(cells(Multiplayer.submission_accepted(first)), [[40, 8, 40, 12], [41, 8, 40, 0]]);
assert.equal(Multiplayer.submission_rejected(first).$, "Nil");
assert.equal(Number(WorldState.block(Multiplayer.room_edits(room1), SEED, 40n, 8n, 40n)), 12);
assert.equal(Number(WorldState.block(Multiplayer.room_edits(room1), SEED, 41n, 8n, 40n)), 0);

// A later edit of the same cell wins, and the log keeps one entry per cell.
const second = Multiplayer.submit(room1, list([edit(40, 8, 40, 22)]));
const room2 = Multiplayer.submission_room(second);
assert.equal(Number(Multiplayer.room_seq(room2)), 2);
assert.equal(Number(WorldState.block(Multiplayer.room_edits(room2), SEED, 40n, 8n, 40n)), 22);
assert.equal(array(Multiplayer.room_edits(room2)).length, 2);

// Unknown blocks, out-of-height cells and out-of-range coordinates are refused
// individually; the valid edits of the same batch still land.
const origin = Number(World.negative_origin());
const mixed = Multiplayer.submit(room2, list([
  edit(10, 8, 10, 99),
  edit(10, Number(World.max_y()), 10, 1),
  edit(origin, 8, 10, 1),
  edit(origin - 5, 8, 10, 1),
]));
assert.deepEqual(cells(Multiplayer.submission_accepted(mixed)), [[origin - 5, 8, 10, 1]]);
assert.equal(array(Multiplayer.submission_rejected(mixed)).length, 3);
const room3 = Multiplayer.submission_room(mixed);
assert.equal(Number(WorldState.block(Multiplayer.room_edits(room3), SEED, 10n, 8n, 10n)), Number(World.block(SEED, 10n, 8n, 10n)));

// Rejected in-world cells come back with their authoritative value, so the
// client can undo its prediction; cells outside the world have none.
const reverted = cells(Multiplayer.revert(Multiplayer.submission_rejected(mixed), Multiplayer.room_edits(room3), SEED));
assert.deepEqual(reverted, [[10, 8, 10, Number(World.block(SEED, 10n, 8n, 10n))]]);
const revertEdited = cells(Multiplayer.revert(list([edit(40, 8, 40, 99)]), Multiplayer.room_edits(room3), SEED));
assert.deepEqual(revertEdited, [[40, 8, 40, 22]]);

// An oversized batch is refused whole and leaves the room untouched.
const oversized = list(Array.from({ length: Number(Multiplayer.max_batch()) + 1 }, (_, i) => edit(i % 40, 8, 5, 1)));
const refused = Multiplayer.submit(room3, oversized);
assert.equal(Multiplayer.submission_accepted(refused).$, "Nil");
assert.equal(Number(Multiplayer.room_seq(Multiplayer.submission_room(refused))), Number(Multiplayer.room_seq(room3)));
const atLimit = list(Array.from({ length: Number(Multiplayer.max_batch()) }, (_, i) => edit(i % 40, 8, 5, 1)));
assert.equal(array(Multiplayer.submission_accepted(Multiplayer.submit(room3, atLimit))).length, Number(Multiplayer.max_batch()));

// Replaying accepted batches in sequence order on a client converges on the
// room's log, whatever the client predicted locally in between.
let client = WorldState.set(WorldState.empty(), 40n, 8n, 40n, 5);
client = Multiplayer.merge(Multiplayer.submission_accepted(first), client);
client = Multiplayer.merge(Multiplayer.submission_accepted(second), client);
client = Multiplayer.merge(Multiplayer.submission_accepted(mixed), client);
for (const [x, y, z] of [[40, 8, 40], [41, 8, 40], [origin - 5, 8, 10], [10, 8, 10]]) {
  assert.equal(
    Number(WorldState.block(client, SEED, BigInt(x), BigInt(y), BigInt(z))),
    Number(WorldState.block(Multiplayer.room_edits(room3), SEED, BigInt(x), BigInt(y), BigInt(z))),
  );
}

// A restored room keeps its sequence and log.
const restored = Multiplayer.restore(7, Multiplayer.room_edits(room3), Multiplayer.room_chests(room3), Multiplayer.room_furnaces(room3));
assert.equal(Number(Multiplayer.room_seq(restored)), 7);

// Poses: finite, inside the world band; NaN and infinities refused.
assert.equal(Multiplayer.valid_pose(12.5, 9.0, -30.25, 1.2, -0.4), true);
assert.equal(Multiplayer.valid_pose(Number.NaN, 9.0, 0.0, 0.0, 0.0), false);
assert.equal(Multiplayer.valid_pose(0.0, Number.POSITIVE_INFINITY, 0.0, 0.0, 0.0), false);
assert.equal(Multiplayer.valid_pose(0.0, 9.0, 0.0, Number.NEGATIVE_INFINITY, 0.0), false);
assert.equal(Multiplayer.valid_pose(0.0, 400.0, 0.0, 0.0, 0.0), false);
assert.equal(Multiplayer.valid_pose(0.0, -65.0, 0.0, 0.0, 0.0), false);
assert.equal(Multiplayer.valid_pose(5e7, 9.0, 0.0, 0.0, 0.0), false);
assert.ok(Math.abs(Multiplayer.clamp_pitch(3.0) - 1.5533) < 1e-4);
assert.ok(Math.abs(Multiplayer.clamp_pitch(-3.0) + 1.5533) < 1e-4);
assert.ok(Math.abs(Multiplayer.clamp_pitch(0.25) - 0.25) < 1e-6);

// Chests ---------------------------------------------------------------------
const changes = (submission) => array(Multiplayer.submission_changes(submission))
  .map((change) => [change.$, Number(change.x), Number(change.y), Number(change.z)]);
const slots = (room, x, y, z) => array(Multiplayer.chest_slots(room, BigInt(x), BigInt(y), BigInt(z)))
  .map((slot) => [Number(slot.item), Number(slot.count), Number(slot.durability)]);
const emptySlots = Array.from({ length: 9 }, () => [0, 0, 0]);

// Placing a chest block opens an empty chest; placing it again changes nothing.
const placed = Multiplayer.submit(Multiplayer.empty(), list([edit(30, 9, 30, 26), edit(30, 9, 30, 26)]));
let chestRoom = Multiplayer.submission_room(placed);
assert.deepEqual(changes(placed), [["ChestPlaced", 30, 9, 30]]);
assert.equal(Multiplayer.has_chest(chestRoom, 30n, 9n, 30n), true);
assert.deepEqual(slots(chestRoom, 30, 9, 30), emptySlots);
assert.equal(Multiplayer.has_chest(chestRoom, 31n, 9n, 30n), false);

// Deposits merge stacks, withdrawals take from one slot.
let outcome = Multiplayer.deposit(chestRoom, 30n, 9n, 30n, 5, 10, 0);
assert.equal(Multiplayer.outcome_ok(outcome), true);
assert.equal(Number(Multiplayer.outcome_amount(outcome)), 10);
chestRoom = Multiplayer.outcome_room(outcome);
chestRoom = Multiplayer.outcome_room(Multiplayer.deposit(chestRoom, 30n, 9n, 30n, 5, 3, 0));
assert.deepEqual(slots(chestRoom, 30, 9, 30)[0], [5, 13, 0]);
outcome = Multiplayer.withdraw(chestRoom, 30n, 9n, 30n, 0n, 64);
assert.equal(Multiplayer.outcome_ok(outcome), true);
assert.equal(Number(Multiplayer.outcome_item(outcome)), 5);
assert.equal(Number(Multiplayer.outcome_amount(outcome)), 13);
const drained = Multiplayer.outcome_room(outcome);
assert.deepEqual(slots(drained, 30, 9, 30), emptySlots);
// Withdrawing an empty slot, or from no chest, is refused and changes nothing.
assert.equal(Multiplayer.outcome_ok(Multiplayer.withdraw(drained, 30n, 9n, 30n, 0n, 64)), false);
assert.equal(Multiplayer.outcome_ok(Multiplayer.withdraw(drained, 31n, 9n, 30n, 0n, 64)), false);
// Deposits need a chest and a real stack.
assert.equal(Multiplayer.outcome_ok(Multiplayer.deposit(chestRoom, 31n, 9n, 30n, 5, 1, 0)), false);
assert.equal(Multiplayer.outcome_ok(Multiplayer.deposit(chestRoom, 30n, 9n, 30n, 0, 1, 0)), false);
assert.equal(Multiplayer.outcome_ok(Multiplayer.deposit(chestRoom, 30n, 9n, 30n, 5, 0, 0)), false);
assert.equal(Multiplayer.outcome_ok(Multiplayer.deposit(chestRoom, 30n, 9n, 30n, 5, 65, 0)), false);
// Tools keep their durability.
const tooled = Multiplayer.outcome_room(Multiplayer.deposit(drained, 30n, 9n, 30n, 33, 1, 17));
assert.deepEqual(slots(tooled, 30, 9, 30)[0], [33, 1, 17]);
// A full chest refuses more.
let full = drained;
for (let index = 0; index < 9; index += 1) full = Multiplayer.outcome_room(Multiplayer.deposit(full, 30n, 9n, 30n, 33, 1, index));
const overflow = Multiplayer.deposit(full, 30n, 9n, 30n, 33, 1, 0);
assert.equal(Multiplayer.outcome_ok(overflow), false);
assert.equal(Number(Multiplayer.outcome_amount(overflow)), 0);

// A chest holding items cannot be broken; the edit is refused and the chest
// keeps its contents. Once emptied it can be broken, and the chest goes away.
const blocked = Multiplayer.submit(chestRoom, list([edit(30, 9, 30, 0), edit(31, 9, 30, 1)]));
assert.deepEqual(cells(Multiplayer.submission_rejected(blocked)), [[30, 9, 30, 0]]);
assert.deepEqual(cells(Multiplayer.submission_accepted(blocked)), [[31, 9, 30, 1]]);
assert.deepEqual(changes(blocked), []);
assert.deepEqual(slots(Multiplayer.submission_room(blocked), 30, 9, 30)[0], [5, 13, 0]);
assert.equal(
  Number(WorldState.block(Multiplayer.room_edits(Multiplayer.submission_room(blocked)), SEED, 30n, 9n, 30n)),
  26,
);
const broken = Multiplayer.submit(drained, list([edit(30, 9, 30, 0)]));
assert.deepEqual(changes(broken), [["ChestBroken", 30, 9, 30]]);
assert.equal(Multiplayer.has_chest(Multiplayer.submission_room(broken), 30n, 9n, 30n), false);
// Breaking a cell without a chest reports no chest change.
assert.deepEqual(changes(Multiplayer.submit(drained, list([edit(12, 9, 12, 0)]))), []);
// A room restored with its chests keeps them.
const restoredChests = Multiplayer.restore(3, Multiplayer.room_edits(chestRoom), Multiplayer.room_chests(chestRoom), Multiplayer.room_furnaces(chestRoom));
assert.deepEqual(slots(restoredChests, 30, 9, 30)[0], [5, 13, 0]);

// Furnaces -------------------------------------------------------------------
const furnaceView = (room, x, y, z) => {
  if (!Multiplayer.has_furnace(room, BigInt(x), BigInt(y), BigInt(z))) return null;
  const f = Multiplayer.furnace_state(room, BigInt(x), BigInt(y), BigInt(z));
  return { input: Number(f.input), inputCount: Number(f.input_count), fuel: Number(f.fuel_count), output: Number(f.output), outputCount: Number(f.output_count), progress: Number(f.progress) };
};
const RAW_IRON = 15;
const COAL = 14;
const IRON_INGOT = 20;
const furnacePlaced = Multiplayer.submit(Multiplayer.empty(), list([edit(20, 9, 20, 11)]));
assert.deepEqual(changes(furnacePlaced), [["FurnacePlaced", 20, 9, 20]]);
let oven = Multiplayer.submission_room(furnacePlaced);
assert.deepEqual(furnaceView(oven, 20, 9, 20), { input: 0, inputCount: 0, fuel: 0, output: 0, outputCount: 0, progress: 0 });
// op 0 loads input, op 1 fuel, op 2 takes the output.
let op = Multiplayer.furnace_op(oven, 0, 20n, 9n, 20n, RAW_IRON);
assert.equal(Multiplayer.outcome_ok(op), true);
oven = Multiplayer.outcome_room(op);
assert.equal(Multiplayer.outcome_ok(Multiplayer.furnace_op(oven, 0, 20n, 9n, 20n, 7)), false, "only smeltable input");
assert.equal(Multiplayer.outcome_ok(Multiplayer.furnace_op(oven, 0, 21n, 9n, 20n, RAW_IRON)), false, "no furnace there");
assert.equal(Multiplayer.outcome_ok(Multiplayer.furnace_op(oven, 2, 20n, 9n, 20n, 0)), false, "nothing to take yet");
oven = Multiplayer.outcome_room(Multiplayer.furnace_op(oven, 1, 20n, 9n, 20n, COAL));
assert.equal(furnaceView(oven, 20, 9, 20).fuel, 1);
// Ticking smelts: eight steps turn one raw iron into one ingot.
for (let step = 0; step < 8; step += 1) oven = Multiplayer.tick(oven);
assert.deepEqual(furnaceView(oven, 20, 9, 20), { input: 0, inputCount: 0, fuel: 0, output: IRON_INGOT, outputCount: 1, progress: 0 });
op = Multiplayer.furnace_op(oven, 2, 20n, 9n, 20n, 0);
assert.deepEqual([Multiplayer.outcome_ok(op), Number(Multiplayer.outcome_item(op)), Number(Multiplayer.outcome_amount(op))], [true, IRON_INGOT, 1]);
oven = Multiplayer.outcome_room(op);
assert.equal(furnaceView(oven, 20, 9, 20).outputCount, 0);
// Replacing the furnace block removes the furnace.
const furnaceBroken = Multiplayer.submit(oven, list([edit(20, 9, 20, 0)]));
assert.deepEqual(changes(furnaceBroken), [["FurnaceBroken", 20, 9, 20]]);
assert.equal(furnaceView(Multiplayer.submission_room(furnaceBroken), 20, 9, 20), null);
// A chest and a furnace in one batch report both, in order.
assert.deepEqual(
  changes(Multiplayer.submit(Multiplayer.empty(), list([edit(1, 9, 1, 26), edit(2, 9, 1, 11), edit(1, 9, 1, 11)]))),
  [["ChestPlaced", 1, 9, 1], ["FurnacePlaced", 2, 9, 1], ["ChestBroken", 1, 9, 1], ["FurnacePlaced", 1, 9, 1]],
);

// Interaction reach.
assert.equal(Multiplayer.within_reach(10, 9, 10, 15.5, 9.5, 10.5), true);
assert.equal(Multiplayer.within_reach(10, 9, 10, 19.5, 9.5, 10.5), false);
assert.equal(Multiplayer.within_reach(10, 9, 10, Number.NaN, 9.5, 10.5), false);

console.log("bend multiplayer ok");
