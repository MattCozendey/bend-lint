// The server-simulated world (server/server-world.js): mobs, drops,
// villagers, fluids, fire, crops and farmland. Players hit mobs, pick up and
// throw items, and use buckets, fire, hoes and seeds through it; everything it
// changes reaches the edit log as server batches.
export function createWorldHandlers(ctx, edits) {
  function entities() {
    return { t: "entities", ...ctx.world.snapshot() };
  }

  function attack(player, message) {
    const result = ctx.world === null || player.pose === null
      ? { hit: false, killed: false, kind: 0 }
      : ctx.world.attack(player.pose, message.mob, message.damage, message.ranged);
    ctx.send(player, { t: "attack-result", id: message.id, mob: message.mob, ...result });
    if (result.hit) ctx.broadcast(entities());
  }

  function pickup(player, message) {
    const result = ctx.world === null || player.pose === null
      ? { ok: false, item: 0, amount: 0 }
      : ctx.world.pickup(player.pose, message.drop);
    ctx.send(player, { t: "pickup-result", id: message.id, drop: message.drop, ...result });
    if (result.ok) ctx.broadcast(entities());
  }

  function drop(_player, message) {
    if (ctx.world === null) return;
    ctx.world.addDrop(message.item, message.amount, message.x, message.y, message.z);
    ctx.broadcast(entities());
  }

  function interact(player, message) {
    const result = ctx.world === null
      ? { ok: false, reason: "unsupported" }
      : ctx.world.interact(player.pose, message.op, message.pos);
    ctx.send(player, { t: "interact-result", id: message.id, op: message.op, ...result });
    // The cells the interaction changed reach everyone right away.
    edits.flushServerEdits();
  }

  /** One simulation step; returns whether anyone was online to simulate for. */
  function tick(dt, time, online) {
    if (ctx.world === null || online.length === 0) return false;
    const hurts = ctx.world.tick(dt, time, online.map((player) => ({ id: player.id, ...player.pose })));
    for (const [id, amount] of hurts) {
      const player = online.find((candidate) => candidate.id === id);
      if (player !== undefined) ctx.send(player, { t: "hurt", amount });
    }
    edits.flushServerEdits();
    ctx.broadcast(entities());
    return true;
  }

  return { tick, handlers: { attack, pickup, drop, interact } };
}
