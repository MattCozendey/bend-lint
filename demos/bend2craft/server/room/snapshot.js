// What a multiplayer world saves, and how a saved world comes back.
import {
  bendChestsToWire,
  bendEditsToWire,
  bendFurnacesToWire,
  isWireChest,
  isWireEditList,
  isWireFurnace,
  wireChestsToBend,
  wireEditsToBend,
  wireFurnacesToBend,
} from "../../web/multiplayer-protocol.js";

// 1: edits. 2: chests, furnaces, clock. 3: the block simulation (fluids,
// fire, crops, farmland) as an encoded save string.
export const SNAPSHOT_VERSION = 3;

export function validSnapshot(snapshot, seed) {
  if (![1, 2, SNAPSHOT_VERSION].includes(snapshot?.version)) return false;
  if (!isWireEditList(snapshot.edits, Infinity) || !Number.isInteger(snapshot.seq)) return false;
  if (String(snapshot.seed) !== seed.toString()) return false;
  if (snapshot.version === 1) return true;
  return Array.isArray(snapshot.chests)
    && snapshot.chests.every((chest) => isWireChest(chest) && chest.slots !== null)
    && (snapshot.furnaces === undefined
      || (Array.isArray(snapshot.furnaces) && snapshot.furnaces.every((f) => isWireFurnace(f) && f.state !== null)))
    && Number.isFinite(snapshot.time) && snapshot.time >= 0
    && (snapshot.simulation === undefined || snapshot.simulation === null || typeof snapshot.simulation === "string");
}

/** The Bend room a snapshot describes. */
export function restoreRoom(authority, snapshot) {
  return authority.restore(
    snapshot.seq >>> 0,
    wireEditsToBend(snapshot.edits),
    wireChestsToBend(snapshot.chests ?? []),
    wireFurnacesToBend(snapshot.furnaces ?? []),
  );
}

export function roomSnapshot(authority, seed, state, time, simulation) {
  return {
    version: SNAPSHOT_VERSION,
    seed: seed.toString(),
    seq: Number(authority.room_seq(state)),
    edits: bendEditsToWire(authority.room_edits(state)),
    chests: bendChestsToWire(authority.room_chests(state)),
    furnaces: bendFurnacesToWire(authority.room_furnaces(state)),
    time,
    simulation,
  };
}
