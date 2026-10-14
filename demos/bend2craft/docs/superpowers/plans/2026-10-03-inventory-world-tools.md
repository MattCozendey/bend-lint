# Plan — Bend-first migrations, terrain continuity, world depth, tools (2026-10-03)

Approved sequence, each phase gated by `npm run verify` and, where the browser
boundary is crossed, `npm run browser:smoke`:

1. **Inventory and crafting move into Bend in the browser.** DONE (2026-10-03): every
   item<->block lookup now reads `Inventory.placed_block`/`Inventory.mining_item`;
   `Inventory.mining_item` itself was fixed for redstone blocks and the open door and
   is pinned by two new laws (`what_a_redstone_block_drops`, `what_an_open_door_drops`);
   `tests/inventory-bend-contract.test.mjs` locks the contract to the browser view.
   Verified: `npm run verify`, `npm run browser:smoke`.
2. **Terrain seam at x = 0 / z = 0.** CLOSED AS STALE (2026-10-03): the
   `NEGATIVE_ORIGIN` mapping and `World.negative_origin()` already make the
   world continuous across the axes and migrate legacy saves; the backlog entry
   predated that fix. Closed with the crate-of-record tests unchanged and
   green.
3. **Deeper world.** PHASES A AND B DONE (2026-10-03):
   - A: `max_y` 20 -> 64 and a bedrock row (block 41) at `y = 0`, in `World.block`,
     in the fast `chunk32` path, and in the native colour table; the per-chunk
     arrays are `Array.new(U32, 14n, 0)`; `the_bottom_row_is_bedrock` is a law.
   - B: caves are two banded fields on a four-cell lattice, implemented once per
     cell and once for the chunk path and held to the same answer by
     `tests/world-block-chunk.test.mjs`; `cave_is_air`, `caves_run` and
     `ground_beside_a_cave_is_solid` are laws.

   Benchmark, verify and browser smoke are green for both. Remaining: continuous
   oceans and rivers, temperature/humidity biome fields, biome-specific
   terrain/vegetation/ores, multiple villages.
4. **Tools and blocks.** Shovel, axe, shears with Bend-owned mining rules and
   durability; stairs, slabs and fences (also unblocking diagonal redstone
   dust); placeable wool; gold, redstone, lapis, emerald and copper materials
   with a tool progression.

Order rationale: (1) removes the biggest rule violation and unblocks the
multiplayer authority fixes; (2) is user-visible but isolated; (3) is the
largest and benefits from pure-Bend terrain ownership; (4) depends on nothing
blocked by (1)–(3) except redstone dust, which it unblocks.
