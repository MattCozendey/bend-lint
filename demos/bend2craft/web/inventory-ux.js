const DEFAULT_HOTBAR_SIZE = 9;
const DEFAULT_MAX_STACK = 64;

export function transferAmount(count, button = 0) {
  const normalized = Math.max(0, Math.trunc(Number(count) || 0));
  if (normalized === 0) return 0;
  return Number(button) === 2 ? Math.ceil(normalized / 2) : normalized;
}

export function dropAmount(count, dropStack = false) {
  const normalized = Math.max(0, Math.trunc(Number(count) || 0));
  return dropStack ? normalized : Math.min(1, normalized);
}

export function slotKey(slot) {
  if (slot === null || typeof slot !== "object" || Number(slot.count ?? 0) <= 0) return null;
  if (typeof slot.item === "string" && slot.item.length > 0) return `item:${slot.item}`;
  if (Number.isInteger(slot.block) && slot.block !== 0) return `block:${slot.block}`;
  return null;
}

export function findShiftTarget(
  inventory,
  sourceSlot,
  hotbarSize = DEFAULT_HOTBAR_SIZE,
  maxStack = DEFAULT_MAX_STACK,
) {
  if (!Array.isArray(inventory) || !Number.isInteger(sourceSlot)) return -1;
  if (sourceSlot < 0 || sourceSlot >= inventory.length) return -1;
  const sourceKey = slotKey(inventory[sourceSlot]);
  if (sourceKey === null) return -1;
  const start = sourceSlot < hotbarSize ? hotbarSize : 0;
  const end = sourceSlot < hotbarSize
    ? inventory.length
    : Math.min(hotbarSize, inventory.length);
  for (let index = start; index < end; index += 1) {
    if (slotKey(inventory[index]) === sourceKey && Number(inventory[index].count) < maxStack) return index;
  }
  for (let index = start; index < end; index += 1) {
    if (slotKey(inventory[index]) === null) return index;
  }
  return -1;
}
