/** Return whether the furnace shortcut should be visible in the game HUD. */
export function furnaceControlHidden(activeFurnace, open) {
  return !open && activeFurnace === null;
}
