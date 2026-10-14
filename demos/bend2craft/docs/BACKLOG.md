# Bend2Craft backlog

This file is the canonical, reviewable backlog for the repository. GitHub Projects is the execution view: cards can be moved, assigned and filtered there, while changes to scope and acceptance criteria remain versioned here.

Status markers:

- `[x]` implemented and covered by the current verification gates
- `[~]` partially implemented; the remaining scope is stated below
- `[ ]` not implemented

## Current foundation

- [x] Bend2 owns terrain, chunk generation, edits, player physics, collision, raycast, inventory transitions, fluids, survival, entities and the current crafting/furnace/chest contracts.
- [x] `npm run verify` covers Bend checks, proofs, regression tests, static build and `git diff --check`.
- [x] Browser smoke covers chunk hydration, interaction, persistence, negative coordinates, inventory UI, shaped crafting, chest storage, equipment/offhand and item drops.

## P0 — combat, culling and material contract

- [x] Bend owns melee line-of-sight: a hostile cannot damage a player across a solid cell, and the eye ray runs at eye height so a one-block step is not mistaken for cover.
- [x] Bend owns the melee attack cone: a hostile must be facing the player, with a wider cone for the brute. A dead mob never contributes damage on a later tick.
- [x] One mob roster across both layers: pig, zombie, sheep, brute, cow and chicken, each with its own model, hitbox, hurt voice and loot. A missing model used to draw a hostile brute as a pig that charged the player and burned in daylight.
- [x] Farm animals wander by default and run from the player only after being struck, through a `panic` timer that `attack` sets and the step functions spend.
- [x] Farm animals spawn in the open during the day; only a hostile waits for nightfall or a blocked sky, and the spawn grid is fine enough that a 48x48 world carries a real population.
- [x] Per-chunk frustum culling on the WebGPU terrain path, reporting visible chunks, culled chunks, draw calls and submitted vertex bytes.
- [x] A block edit re-uploads only the edited chunk instead of composing a whole-world vertex array on the per-chunk backend.
- [x] Padded atlas with a per-tile gutter, and mipmaps enabled only after a Foreign Tile Contamination probe passes against the real GPU mip chain.
- [x] High-definition procedural materials: 128-texel tiles painted per material (stones, blades, bark fissures, faceted ores, planks, bricks) in a 2048x2048 atlas certified through mip level 6, with the atlas composed in memory instead of self-copying the canvas.
- [ ] Item icons for placeable blocks drawn from the high-definition atlas instead of the 16px pixel pass.
- [x] Material response split into albedo, lighting and material stages with parity between the WebGL and WGSL sources, plus water depth tinting carried in the material band.
- [x] The WebGPU gate reads a real presented frame back out of the swap chain and probes the scene; an unavailable backend is marked skipped with an explicit diagnostic.

## P0 — movement and survival

- [x] Sneak with Shift and sprint with Ctrl.
- [x] Swim, float, drowning air and Bend-owned water currents.
- [x] Fall damage.
- [x] Regeneration while well-fed.
- [x] Rotten-flesh poison.
- [x] Death screen and inventory drops.
- [x] Swords, bow, arrows, shield mitigation, knockback and kill XP.
- [x] Continuous night mob respawn, distinct mob movement and distance despawn.
- [x] Furnace cooking/smelting, rotten flesh/wheat/bread/apple food loop, chest storage and placeable crafting table.
- [x] Shaped 3x3 crafting grid.
- [x] Drag-and-drop, half-stack transfer, shift-click section transfer and Q/Shift+Q drops.
- [x] Basic armor item recipes and equipment slots; offhand shield mitigation.
- [x] Control remapping for the main actions, tutorial/help copy, toast feedback, target highlight and FOV kick.
- [x] Break/place particles, procedural footsteps, ambient audio hooks and attack/game-feel feedback.

## P0 — world and performance

- [x] Chunk streaming keeps desired/active/pending state separate and supports render distances 2–8 (default 4).
- [x] Terrain chunk generation runs through a U32 core with per-column precomputation, byte-identical to the original Nat rules (`tests/world-chunk-golden.test.mjs`); `bench:chunks` dropped from ~475 ms to ~4 ms per chunk.
- [x] Chunk light is filled column by column with chunk-local edits, pre-binned torch fields and lazy source floods; the chunk worker caches each source's flood.
- [x] Chunk and mesh workers transfer typed arrays instead of structured-cloning them, and per-chunk mesh jobs no longer ship every resident mesh to the worker.
- [x] WebGL keeps one interleaved buffer per chunk with frustum culling (view and sun cascade) instead of a whole-world array re-uploaded on every change; edits publish as soon as their chunk is rebuilt.
- [x] 24-bit depth texture for the HDR scene where available.
- [x] Distant terrain (Distant Horizons style): quadtree LOD rings of cached tiles from the Bend `Horizon.lod_points` sampler on a dedicated worker, per-chunk stand-ins in the nearest ring, skirts between rings, Off/256/512/1024/2048-block option.
- [x] Per-effect graphics options: one slider per effect the pipeline already had, generated from the table the renderer resolves through (`web/graphics-effects.js`), as a share of the shipped look so 0% is off. The quality tier keeps owning what a frame may cost and these own how much of an effect is shown, and bloom and shadows are skipped outright at 0% rather than multiplied by zero. Disabled with a stated reason on an explicit WebGPU pin, which has no post chain.
- [x] The cloud deck is lit as the bright diffuse reflector it is: an isotropic sun term plus the forward lobe, with the gain calibrated from pictures. Lit by the lobe alone it could never out-shine the sky behind it and read as a flat grey stain; the measured span the gain has to stay inside is held by `tests/cloud-lighting.test.mjs`.
- [ ] Torch floods (`world/lightflood.bend`) still use list-based BFS with O(n²) visited and wall scans (~50 ms per source); an array-backed flood would make torch placement and first-time chunk light cheap.
- [ ] Village structure cells still run through the Nat `Structures.block` path (~20 ms for a village chunk versus ~4 ms elsewhere).
- [x] Negative coordinates are generated through the `NEGATIVE_ORIGIN` shift (`web/world-coordinates.js`), which any terrain period divides, so the world continues across x = 0 and z = 0 instead of cutting. `World.negative_origin()` holds the same constant in Bend; `tests/world-coordinates.test.mjs` pins height continuity and whole-chunk shift invariance, and `migrateLegacyEdits` rewrites saves written under the legacy `1_000_000 + |chunk|` mapping.
- [x] Ores generate where vanilla generates them, in veins. Each ore has a band and a density from the vanilla ore table: diamond in the bottom quarter of the column and about 0.13% of the rock, iron through the whole column at 0.40%, coal through the whole column at 1.67% — where before it was one block per hash, uniform at every depth. A vein is placed per eight-cell lattice cell, the cell's hash naming the ore and three more the centre, held far enough from the edge that a vein never reaches across the cell it was not placed in (`World.ore_vein_of`, `ore_band`, `ore_reach`, `ore_offset`, `ore_filled`). `tests/ore-distribution.test.mjs` holds the bands, the densities, and that most ore cells have an ore beside them; six laws hold the band's fraction at named heights, the reach, and the rarity order of a lattice row — as values, not as universal facts, because `World.ore_band` is one line and a `for` over it would prove the definition. `world/world.bend`'s U32 chunk path reads the same lattice, so the fast per-chunk route and the per-cell query carve one world; the chunk golden fingerprints moved and the light, height and surface fingerprints did not, because an ore is as opaque as the stone it replaces.
- [ ] LOD tiles are generated from the pure world generator, so player edits outside the streamed window are not reflected in the distant rings.
- [x] Edited blocks, entities and simulation state are persisted in the seed-scoped save.
- [ ] Fix the WebGPU atlas mip generator, then enable the chain. WebGPU has no `generateMipmap`, so each level is written by hand. The current implementation renders each level while sampling the same texture, which WebGPU forbids, so the levels stay zero-initialized and the chain misses the box-filter reference by a max delta of 255. The gate detects this and refuses the chain, so WebGPU currently samples the base level with linear minification. The ping-pong version through a scratch texture is in place; the remaining work is making the downsample match `atlasBoxDownsample`. Measured cost of shipping the broken chain: mean per-pixel delta against WebGL rises from 1.43 to 41.77, with 76% of pixels differing by more than 8.
- [x] Larger `max_y`: the world is 64 rows, benchmarked before the change. `npm run bench:chunks` moved from 0.52 ms to 0.61 ms per chunk (fresh, median of 16) and the light phase from 0.09 ms to 0.11 ms. The per-chunk arrays are now `Array.new(U32, 14n, 0)` (16,384 cells) and the golden fingerprints moved, with the change recorded in `tests/world-chunk-golden.test.mjs`. The browser smoke's block count and terrain quads (56,638 and 66,675 at the spawn) moved as well, because the lattice cave rule below carves different cells.
- [~] Finalize a reproducible save/load chunk benchmark and p95/p99 streaming budget on target hardware; default render distance 2 is the smooth baseline, while distance 6 remains an explicit stress setting.

## P1 — faithful world

- [x] Increase terrain height and add a bedrock layer. `World.max_y` is 64 and row `y = 0` is bedrock (block 41) in both the per-cell rule and the fast per-chunk path, so `World.block` and `World.chunk` never disagree about the floor. Bedrock is not in `Inventory.mining_block`, so no tool can scoop it. `the_bottom_row_is_bedrock` is a law.
- [x] Replace the small cave rule with 3D noise caves. Two banded hash fields read on a four-cell lattice, carved only where both sit in their band, so caves run as pockets instead of speckling. The same rule is implemented once per cell (`World.cave_lattice_at`) and once for the fast per-chunk path (`chunk32.cave_lattice`), both short-circuited to enclosed rows, and `tests/world-block-chunk.test.mjs` holds them to the same answer on 24,524 sampled cells (lava is the one documented difference, left to the fluid simulation). Three laws: `cave_is_air`, `caves_run`, `ground_beside_a_cave_is_solid`. Cost: fresh chunk generation moved from 0.61 ms to 0.78 ms (median of 16, `npm run bench:chunks`).
- [ ] Generate continuous oceans and rivers.
- [ ] Add temperature/humidity biome fields and biome transitions.
- [ ] Add biome-specific terrain, vegetation and resource distribution.

## P1 — structures and dimensions

- [~] Expand from the current deterministic village slice to multiple villages per world.
- [ ] Add temples.
- [ ] Add dungeons and underground structures.
- [ ] Add Nether portal validation and a Nether dimension.
- [ ] Add End portal validation and an End dimension.
- [ ] Persist dimension-scoped edits, entities and player transitions.

## P1 — blocks and tools

- [x] Glass item/block contract.
- [~] Wool item/drop contract; add a placeable wool block and wool textures.
- [ ] Add stairs, slabs and fences with correct collision and greedy-mesh geometry.
- [x] Add shovel, axe and shears with Bend-owned mining rules and durability. Four tiers of each shovel and axe (ids 63-70) and a pair of shears (71), with `Inventory.tool_kind` naming what kind of tool a thing is, `suited_kind` what a block wants, `tool_tier` what a tool is worth and `tool_max_durability` how long it lasts. A tool that suits its material works at its tier's speed; one that does not is worse than a bare hand, the way it is in vanilla. Nine recipes, icons for all nine, and six laws: `the_tool_kinds_are_what_they_are`, `the_tool_tiers_run_wooden_to_diamond`, `a_tool_wears_by_its_tier`, `the_tools_place_nothing`, `the_tools_break_what_they_are_for`, `each_block_wants_its_tool`.
- [ ] Shears on a live sheep drop wool rather than a cut; the item exists, the behaviour does not.
- [ ] Add gold, redstone, lapis lazuli, emerald and copper materials/ores/items.
- [ ] Add material tool progression for the new resources.
- [ ] Add Fortune and Silk Touch validation and drop behavior.

## P1 — farming, villages and fluids

- [x] Wheat, farmland, crop ticking and basic villager trade/pathing.
- [x] Water/lava flow, buckets, doors and fire primitives. Two bugs made a placed pool fall apart on 2026-10-03 and are fixed in `world/fluids.bend`: a cell took the lower level a neighbour offered it, so a pool ratcheted itself down one step per tick and drained, and a tick walked only the first 64 flows, so any wider pool lost cells every tick and the world cleared them. A flow now stays while something feeds it (a source, a stronger neighbour, or water on top of it) and every flow in the field is advanced. The browser's sample window also grew to include the cell above each flow, which is what tells a flow a column landed on it. Laws: `a_settled_pool_keeps_its_cells`, `an_unfed_flow_dries_up`.
- [ ] Water is drawn as a full block: the surface of a one-deep sheet sits at the top of the cell instead of below it, so shallow water reads as a row of cubes. This is presentation, not the rule.
- [ ] Add carrots, potatoes and sugar cane.
- [ ] Add bonemeal and crop acceleration rules.
- [ ] Add breeding and animal population rules.
- [~] Raw porkchop, raw beef and raw chicken are collectible and edible as they drop; add cooking recipes and a placeable cooked-meal tier.
- [~] Expand villagers into profession work schedules and workstation behavior.
- [ ] Add iron golems and raids.
- [ ] Add infinite-water source rules.
- [ ] Add flint-and-steel and player-initiated fire.

## P2 — redstone

Minecraft's redstone is the most heavily specified system the game has, with years of
community-documented edge cases. The slice below is the combinational core, the timed
components and the machines, split by concern so the web layer has a single seam:

- `world/redstone.bend` — dust, torch, lever, block, lamp, repeater/comparator core, burnout
- `world/redstone_clock.bend` — repeater/comparator counters and the per-tick order
- `world/redstone_machines.bend` — door, pressure plate, activator rail, piston, observer
- `world/redstone_grid.bend` — the array-backed dust flood
- `world/redstone_all.bend` — the one entry point the browser ticker calls

- [x] Redstone dust with vanilla decay, strong/weak power split, vertical connection, and a power map that does not depend on placement order.
- [x] Redstone torch (with self-exclusion and vanilla burnout), lever, redstone block, redstone lamp.
- [x] Redstone repeater at all four delays and the comparator in both modes.
- [x] Door, pressure plate, activator rail, piston and sticky piston, with the world edits they ask for.
- [x] Observer: the one component with no signal input. Fires for two ticks when the block in front *changes*, adopts its first sight without firing, and does not watch a front cell that saturates back onto itself.
- [x] A 20Hz ticker, circuit persistence, and one item per placeable block held in a single contract across three files.
- [x] A linear array-backed dust flood replacing a quadratic list flood, and a window sized to the circuit so a circuit of any size settles.
- [x] Redstone blocks now drop their own items through `Inventory.mining_item`, and the open door drops a door: both are pinned by laws, and the browser's `blockForItem`/`itemId` read `Inventory.placed_block`/`Inventory.mining_item` directly instead of keeping a third copy of the table. A piston head drops nothing.
- [ ] **Configurability the contracts already have and the player cannot reach.** This is the largest gap in the slice, and it is in the adapter rather than in Bend. `place_repeater` takes a direction and a delay, `place_comparator` a direction and a mode, `place_piston` a face, `place_observer` a face — and `web/redstone.js` passes `0` for every one of them on every placement. So a placed repeater is always one tick facing east, a comparator is always compare mode facing east, and a piston or observer always points east. The contract implements and tests all four repeater delays and both comparator modes; none of them is reachable in game. This also needs the right-click interaction vanilla has, since a repeater's delay is raised by clicking it and a comparator's mode is toggled by clicking it, and `isRedstoneInteractive` currently recognises only the lever.
- [ ] Dust climbing stairs and slabs diagonally (1.17+). Blocked on the P1 stairs/slabs/fences entry: the diagonal connection needs those blocks to exist, and the flood needs a per-cell answer about what a neighbour is.
- [ ] Buttons: a fixed pulse rather than a held level, so the circuit gets a real second timing model alongside the lever.
- [ ] Weighted pressure plates (light and heavy), with output strength by the number and kind of entities standing on them. The current plate is a single on/off model.
- [ ] Target block: a source whose strength a comparator reads.
- [ ] Redstone wall torch, which is a distinct block with a face rather than a torch standing on a block.
- [ ] Quasi-connectivity, the vanilla behaviour where a component is powered through a diagonal or around a block. It changes what a large number of circuits do.
- [ ] Scheduled tick ordering and block-update priority. Vanilla gives dispensers and hopers an explicit order; this contract settles machines level by level and does not model it.
- [ ] Piston fidelity: the push limit is 2 cells where vanilla is 12, and there are no immovable blocks, no slime/honey/moving rules and no block-entity preservation. The shorter limit is deliberate for now and documented in `world/redstone_machines.bend`; the immovability rules are the part that changes what a contraption can do.
- [ ] Detector rail and powered rail; the activator rail is the only rail, and it has no minecart detection (a documented gap, not a faked one).
- [ ] Lamp burnout. Vanilla's lamp is destroyed after 0.1s of destruction; the burnout here is the torch's.
- [ ] A lit lamp or redstone torch actually lights the world. The circuit decides, the adapter exposes the read, and nothing consumes it yet: `world/light.bend` classifies light sources by block id and a lamp's id says nothing about its state, so this needs a state-aware source rather than a block id.
- [ ] Per-block appearance, which is presentation rather than light and is a separate piece of work. The adapter already reads a dust cell's power and whether a lamp or torch is on, and the mesh pipeline takes its vertex colour from `faceColorGrade` and the atlas, so a powered wire currently draws exactly like an unpowered one. Nothing consumes the two reads.
- [ ] The clock period is one tick longer than vanilla's (`2*latency + 3` against vanilla's 4 for a one-tick repeater). This is the cost of advancing timers once per tick instead of cascading within a tick, and it is pinned in a test with the comparison stated.

## P2 — redstone as machines and items

Redstone in Minecraft is also a set of blocks that do work, and none of these exist. They
are separate from the signal layer above and each is its own contract:

- [ ] Redstone dust as an *item*: a player carries dust and places a line from one click, with the vanilla line-drag placement. Today the only redstone item is the block form.
- [ ] Redstone as a *liquid*. A dispenser filled with a bucket of redstone is a redstone source in vanilla, and the fluid is a distinct state from the block. This was excluded from the original slice along with the dust item, and the dust item has now come back in but the liquid has not.
- [ ] Trial chambers and the vault, which drive redstone from their own block states rather than from a placed circuit.
- [ ] Dispenser and dropper: place, dispense, and the one-tick-per-item move with hopper assistance.
- [ ] Hopper: transfer, the 8-slot container, and its place in the transfer priority order.
- [ ] Note block and the instruments it triggers.
- [ ] TNT priming from a signal, and the explosion rule.
- [ ] Sculk sensor and the calibrated sculk sensor, which respond to vibration rather than to a level and are the modern replacement for reading a change.
- [ ] Copper bulb with a configurable 1–4 tick delay, the component that makes a tunable clock out of one block.
- [ ] Charged blocks (chiseled bookshelf, decorated pot) that a comparator can read.

## P2 — large systems

- [~] Add redstone signals and redstone components. See P2 — redstone above for the implemented slice and the remaining scope.
- [~] Add pistons and block movement rules. Piston, sticky piston and the refusal rules are in; the push limit, immovables and block entities are not.
- [ ] Add potions and brewing.
- [ ] Add enchantment selection, storage and effect rules.
- [ ] Add elytra flight.
- [~] Add multiplayer/LAN transport and authoritative synchronization. Shared block edits, player presence, chests, furnaces, the day clock, mobs, drops, villagers, fluids, fire, crops and movement checks are in: a Bend-owned room (`world/multiplayer.bend`, `world/multiplayer_mobs.bend`, `world/multiplayer_moves.bend`) orders and validates edit batches, container transitions, hits, pickups, interactions and poses, and the server runs the Bend entity, villager and simulation rules for every player, behind a Node LAN server and a Cloudflare Durable Object (see `docs/MULTIPLAYER.md`). The remaining steps are tracked in the Roadmap section of `docs/MULTIPLAYER.md`.
- [ ] Add achievements and advancement tracking.
- [ ] Add a boss encounter and boss health presentation.
- [x] Add a dedicated XP bar; current XP is tracked and shown as a level in the HUD.

## Verification and release gates

- [ ] Add focused regression tests for every new contract seam.
- [x] `npm run verify` is green: Bend checks, proofs, 110 regression tests, static build and `git diff --check`.
- [x] Run browser smoke for every UI/world interaction that crosses the WebGL boundary. The gate was broken in this environment: Playwright's default headless build (chrome-headless-shell) refuses pointer lock, so the smoke timed out waiting for `document.pointerLockElement`. Fixed by launching the full Chromium build (`channel: "chromium"`) when it is installed. Two rotted assertions were repaired with the same contracts they always had: the mob combat probe re-approaches the mob between blows (each hit knocks it back out of the 4-block reach), and the inventory focus check waits one frame instead of reading synchronously.
- [ ] Commit each verified phase with a scoped message.
- [ ] Push only after the full phase gate passes and read back the published SHA.
