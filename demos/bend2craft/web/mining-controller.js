export function createMiningState({ x, y, z, block, slot, item, duration, startedAt }) {
  return Object.freeze({
    x: Number(x),
    y: Number(y),
    z: Number(z),
    block: Number(block),
    slot: Number(slot),
    item: item ?? null,
    duration: Number(duration),
    startedAt: Number(startedAt),
  });
}

export function miningStateMatches(state, target, blockAt, selectedSlot, selectedItem) {
  if (state === null || target?.hit === undefined || typeof blockAt !== "function") return false;
  const hit = target.hit;
  return selectedSlot === state.slot
    && selectedItem === state.item
    && hit[0] === state.x
    && hit[1] === state.y
    && hit[2] === state.z
    && blockAt(state.x, state.y, state.z) === state.block;
}
