// Chests and furnaces: room transitions in Bend (Multiplayer.deposit,
// withdraw, furnace_op, tick), answered to the asking player and broadcast to
// everyone as the container's full state.
import {
  bendChestsToWire,
  bendFurnaceToWire,
  bendFurnacesToWire,
  bendSlotsToWire,
} from "../../web/multiplayer-protocol.js";

const FURNACE_OPS = Object.freeze({ input: 0, fuel: 1, output: 2 });

export function createContainers(ctx) {
  const { authority } = ctx;

  function chestAt([x, y, z]) {
    const at = [BigInt(x), BigInt(y), BigInt(z)];
    return {
      pos: [x, y, z],
      slots: authority.has_chest(ctx.state, ...at) ? bendSlotsToWire(authority.chest_slots(ctx.state, ...at)) : null,
    };
  }

  function furnaceAt([x, y, z]) {
    const at = [BigInt(x), BigInt(y), BigInt(z)];
    return {
      pos: [x, y, z],
      state: authority.has_furnace(ctx.state, ...at) ? bendFurnaceToWire(authority.furnace_state(ctx.state, ...at)) : null,
    };
  }

  /** The chests and furnaces a submission placed or broke, as full states. */
  function changedBy(changeList) {
    const chests = [];
    const furnaces = [];
    for (let node = changeList; node?.$ === "Con"; node = node.tail) {
      const pos = [Number(node.head.x), Number(node.head.y), Number(node.head.z)];
      // Tags can carry a module prefix ("multiplayer.ChestPlaced").
      if (node.head.$.includes("Chest")) chests.push(chestAt(pos));
      else furnaces.push(furnaceAt(pos));
    }
    return { chests, furnaces };
  }

  function chest(player, message) {
    const [x, y, z] = message.pos.map(BigInt);
    const outcome = message.op === "deposit"
      ? authority.deposit(ctx.state, x, y, z, message.item, message.count, message.durability)
      : authority.withdraw(ctx.state, x, y, z, BigInt(message.index), message.amount);
    const ok = authority.outcome_ok(outcome);
    ctx.send(player, {
      t: "chest-result",
      id: message.id,
      ok,
      op: message.op,
      item: Number(authority.outcome_item(outcome)),
      amount: Number(authority.outcome_amount(outcome)),
      durability: Number(authority.outcome_durability(outcome)),
    });
    if (!ok) return;
    ctx.state = authority.outcome_room(outcome);
    const changed = chestAt(message.pos);
    ctx.broadcast({ t: "chest", ...changed });
    ctx.changed({ chests: [changed] });
  }

  function furnace(player, message) {
    const [x, y, z] = message.pos.map(BigInt);
    const outcome = authority.furnace_op(ctx.state, FURNACE_OPS[message.op], x, y, z, message.item);
    const ok = authority.outcome_ok(outcome);
    ctx.send(player, {
      t: "furnace-result",
      id: message.id,
      ok,
      op: message.op,
      item: Number(authority.outcome_item(outcome)),
      amount: Number(authority.outcome_amount(outcome)),
    });
    if (!ok) return;
    ctx.state = authority.outcome_room(outcome);
    const changed = furnaceAt(message.pos);
    ctx.broadcast({ t: "furnace", ...changed });
    ctx.changed({ furnaces: [changed] });
  }

  // One smelting step; only the furnaces that moved are sent.
  function tick() {
    const before = bendFurnacesToWire(authority.room_furnaces(ctx.state));
    if (before.length === 0) return 0;
    ctx.state = authority.tick(ctx.state);
    const after = bendFurnacesToWire(authority.room_furnaces(ctx.state));
    const moved = after.filter((entry, index) => entry.state.join() !== before[index]?.state.join());
    if (moved.length === 0) return 0;
    ctx.broadcast({ t: "furnaces", furnaces: moved });
    ctx.changed({ furnaces: moved, tick: true });
    return moved.length;
  }

  return {
    chestAt,
    furnaceAt,
    changedBy,
    tick,
    handlers: { chest, furnace },
    welcome: () => ({
      chests: bendChestsToWire(authority.room_chests(ctx.state)),
      furnaces: bendFurnacesToWire(authority.room_furnaces(ctx.state)),
    }),
  };
}
