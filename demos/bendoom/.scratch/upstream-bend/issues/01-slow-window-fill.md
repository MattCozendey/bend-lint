# Report the CPU window painter upstream

**Status:** ready-for-human

The CPU `window_fill` in `bend2/effs/window_frame.c` walks the image tree from
its root for every pixel. `nix/window-fill.patch` instead visits each square
once and fills its rectangle. Bendoom applies this through `nix/bend.nix`.

Report the patch upstream with a fresh comparison of frame time and pixels
against the unpatched runtime. Remove the patch when upstream supplies the fix.
