// Edit batches, from players and from the server's own simulation, through
// the Bend room (Multiplayer.submit). Every accepted batch goes to every player
// in sequence order; a refused cell goes back to whoever sent it with its
// authoritative value.
import { MAX_EDITS_PER_MESSAGE, bendEditsToWire, wireEditsToBend } from "../../web/multiplayer-protocol.js";

// Server-originated batches carry this sender id.
export const SERVER_SENDER = 0;

export function createEdits(ctx, containers) {
  const { authority, seed } = ctx;

  /**
   * Submits one batch (wire edits, stored coordinates). `player` is the sender,
   * or null for the server's simulation. Returns the accepted wire edits.
   */
  function submit(batch, player = null) {
    const result = authority.submit(ctx.state, wireEditsToBend(batch));
    ctx.state = authority.submission_room(result);
    const accepted = bendEditsToWire(authority.submission_accepted(result));
    const rejected = authority.submission_rejected(result);
    const { chests, furnaces } = containers.changedBy(authority.submission_changes(result));
    if (accepted.length > 0) {
      ctx.counters.accepted += accepted.length;
      const seq = Number(authority.room_seq(ctx.state));
      ctx.broadcast({ t: "edits", seq, from: player?.id ?? SERVER_SENDER, edits: accepted });
      ctx.world?.applyEdits(accepted);
      for (const chest of chests) ctx.broadcast({ t: "chest", ...chest });
      for (const furnace of furnaces) ctx.broadcast({ t: "furnace", ...furnace });
      ctx.changed({ edits: accepted, chests, furnaces });
    }
    if (rejected.$ === "Con") {
      const revert = bendEditsToWire(authority.revert(rejected, authority.room_edits(ctx.state), seed));
      ctx.counters.rejected += batch.length - accepted.length;
      if (player === null) {
        // The simulation wrote its own cache first: the room's value wins.
        ctx.world?.applyEdits(revert);
      } else {
        if (revert.length > 0) ctx.send(player, { t: "revert", edits: revert });
        // A refused break of a chest leaves the chest standing: resend it so the
        // sender's predicted removal is undone too.
        for (const pos of revert) {
          const chest = containers.chestAt(pos.slice(0, 3));
          if (chest.slots !== null) ctx.send(player, { t: "chest", ...chest });
        }
      }
    }
    return accepted;
  }

  /** The simulation's queued edits, in batches the room accepts. */
  function flushServerEdits() {
    const queued = ctx.world?.takeEdits() ?? [];
    for (let start = 0; start < queued.length; start += MAX_EDITS_PER_MESSAGE) {
      submit(queued.slice(start, start + MAX_EDITS_PER_MESSAGE), null);
    }
  }

  return {
    submit,
    flushServerEdits,
    handlers: { edits: (player, message) => submit(message.edits, player) },
  };
}
