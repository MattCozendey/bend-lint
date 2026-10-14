# Bend2Craft

Bend2Craft is a small Minecraft-inspired voxel sandbox built around Bend 2 and a dependency-free WebGL browser client.

Repository: https://github.com/lennix1337/bend2craft

## Architecture

Bend 2 is the source of truth for global terrain, block IDs, bulk chunks, inventory/crafting transitions, player physics, collision, raycast and edit validation. The browser layer asks Bend for chunk/state results, keeps only derived caches and view models, captures input, handles browser APIs and renders visible faces with the verified WebGL path by default; WebGPU is an explicit opt-in presentation path. It must not call `World.block` once per cell during normal chunk loading or duplicate domain formulas in JavaScript. Chunk terrain/light generation runs in dedicated bundled workers during development/build, while the main thread only hydrates caches and renders. In the browser target, Bend 2.0.19's JavaScript evaluator remains sequential; native C/Metal/CUDA targets can use Bend's `!` parallel calls and `--threads`/`--gpu`, but those flags do not turn the browser bundle into a native Bend runtime. WebGPU accelerates browser presentation and buffer uploads, not Bend's JavaScript evaluator.

The renderer can be controlled from Options → Graphics API (`Auto`, `WebGPU` or `WebGL fallback`) or with the `renderer` query parameter. `Auto` uses the verified WebGL path so a blocked browser GPU probe cannot freeze world entry; WebGPU is explicit opt-in and still requires a real adapter/presentation probe. WebGPU uploads interleaved per-chunk terrain buffers and keeps dynamic entity buffers separate, so a dirty chunk does not require rebuilding one global GPU buffer. The browser smoke suite includes a WebGPU path when the browser exposes an adapter; otherwise it records the capability as unavailable instead of claiming GPU acceleration.

`npm run bench:bend-native` compiles a small Bend `!` fork/join workload to the native runtime and measures `--threads` values separately from the browser benchmark. On the validation machine, the WSL environment exposes an NVIDIA GeForce RTX 4070 SUPER, but GPU execution is deliberately reported as `unverified`; the browser game still runs the JavaScript Bend target and does not silently route authoritative state through a native process.

The Bend 2 compiler is pinned as the `vendor/bend` submodule. Bend 2's JavaScript target does not provide graphics, and native support on Windows is not available yet, so the development toolchain runs through WSL while the final game runs in the browser.

## Two targets

The rules are `world/*.bend`, and two programs run them.

- **The browser** (`web/`) is the complete game: everything under "Current slice" below.
  It runs Bend's JavaScript lane, which is sequential, and renders with WebGL or WebGPU.
- **The native client** (`native/`) is a Bend 2 program with its own window, compiled by
  the pinned CLI to C. It reuses `world/` and owns its renderer, which is written in Bend
  and runs on CPU threads: there is no OpenGL, no shader and no engine under it. It has
  the world, walking, digging, placing, the bag, the inventory, crafting table, chest and
  furnace screens, a save of the world and of the bag, and a place in a multiplayer room; it
  does not yet have redstone or armour.

### What the native client draws

A view region of five chunks by five that follows the player, 40,656 faces at the spawn,
painted nearest first in 64-pixel tiles, one tile a task, a pixel written once.

- Sixteen-by-sixteen procedural textures, in perspective.
- Light at every corner of every face: open sky, shade under leaves and roofs, and the dark
  crease where a wall meets the ground, worked out once per chunk.
- Air that starts to show at 22 cells and hides everything at 58, in the colour the sky has
  at the horizon, so the region's edge is behind it and far water takes the sky.
- A sky that is a gradient over the view, clouds that drift, and a twelve-minute day: the
  sun crosses the sky and sets orange, the world's colours fall to a quarter of their light,
  and the moon and the stars come out.

### How fast, and where that was measured

One frame of the native client, in milliseconds, at the spawn (`bash lab/native/paint/run.sh`,
medians of five):

| window | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| 128x128 | 1.55 | 1.52 | 1.68 | 1.98 |
| 256x256 | 2.90 | 2.23 | 2.12 | 2.25 |
| 512x512 | 7.55 | 4.83 | 3.62 | 3.17 |
| 1024x1024 | 24.52 | 13.93 | 8.40 | 6.10 |

The spawn is inside a house, the cheapest view. From open ground 1024x1024 costs 6.15 to
8.47 ms on eight threads depending on which way the player looks. The runtime paces every
presented frame to 16.67 ms, so 60 FPS is the ceiling: every size holds it on eight
threads, and 1024x1024 does not on one. Walking across open ground in a real window, the
client presented 59.99 frames a second at 1024x1024 with one late frame in 869.

**Measured on one machine and one lane**: an AMD Ryzen 7 9800X3D under Windows 11, inside
WSL2 Ubuntu, shown through WSLg, native C, on the **CPU's threads**. Every number is
`--gpu off`. **The native client has no GPU path yet.** Bend puts a call on the GPU only
where the source marks it with `!`, and the client marks none, so on any machine it runs on
CPU threads. Marking one is not enough: the painter's tiles write into arrays, which Bend's
own shader guide rules out on a device, so a GPU painter is a piece of work and not a flag.
It also cannot be tried on this machine: the runtime refuses CUDA under WSL2. **No macOS
build of the native client has been made** either; it should build and run on its CPU
threads there, and that is untested.

```bash
bash scripts/bootstrap-native-bend.sh      # once: builds the pinned CLI
bash scripts/play-native.sh --size=1024    # compiles the client when stale, and runs it
```

On Windows that is run inside WSL. `native/README.md` has the controls and the layout.

### Laws

`world/LAWS.bend` states 114 laws about the rules and `world/PROOF.bend` proves every one;
`npm run proof` is the gate and prints `ALL PROOFS CHECK`.

**Thirty-one hold for every input**, proved by cases and induction. Among them:

- an edit reads back from any edit log, for every log, seed, cell and block;
- an edit changes no other cell;
- a refused mining or placing hands back the bag it was given, whatever refused it;
- mining, placing, adding and removing never change how many slots a bag has;
- placing into an occupied cell, outside the world or into the player is refused, as is
  mining the bottom layer, for every bag and item;
- a refused load or take leaves a furnace as it was, and a withdrawal a chest's slots;
- above a column's height the terrain rule answers air, its top is sand by the sea and
  grass above it, and no cell above sea level is generated as water.

**Sixty-one are values** the game depends on, computed by the checker from the definition
the game runs: the default seed's terrain at eleven cells, what each pickaxe breaks, what
each block drops and that the drop places the block again, the recipes that turn two logs
into a pickaxe, the furnace, crops, farmland, armour, experience, the mob roster, and that
no block id is both solid and something light passes.

The checker decides integers, booleans, naturals and lists, not floats, so the player's
physics and both renderers are held by tests rather than laws.

## Current slice

- Deterministic chunk-streamed world with `16 x 16 x 20` chunks, a configurable `2–8` chunk render distance (default `4`) and dedicated workers for Bend2 chunk generation.
- Distant terrain in the spirit of the Distant Horizons mod: past the streamed chunks the world is drawn from cached LOD tiles (Off, 256, 512, 1024 or 2048 blocks; default 512) laid out as a quadtree of rings that double their reach and cell size, sampled in bulk from the Bend `Horizon.lod_points` contract on their own worker. The nearest ring is split per chunk, so a chunk's stand-in disappears exactly when the real chunk is drawn and fills the gap while it is still streaming.
- Minecraft-style deterministic seed input through `?seed=...` (numeric or text).
- A flatter starting plains biome with gentle paths, ponds and sandy shorelines.
- Forest, desert and mountain biome regions beyond the starting plains, generated by Bend 2.
- Deterministic lazy chunk generation in every horizontal direction; negative and positive chunk coordinates stream through the Bend worker without a finite world edge.
- Deterministic trees with wood trunks and leaf canopies.
- Deterministic Bend2 village structures with a main house, two outbuildings, stone floors/paths, windows and a furnace.
- Three Bend-owned villagers with deterministic professions, day/night home routines, wall-aware local routing and a validated rotten-flesh-for-iron trade (`T`).
- Bounded Bend2 BFS over a cached village walkability grid, with browser scheduling at one villager tick per second to keep pathfinding off the render-rate hot path.
- Bend2 doors with closed/open states, persistent world edits, player collision, villager routing and right-click toggling.
- Villagers can open an adjacent closed door through a Bend2 world-state transition; both door halves are updated atomically.
- Doors close automatically when no villager or player is within the clearance radius, while remaining open during traversal.
- Bed interaction (`N`) is validated in Bend2 and advances the village clock to dawn only during the night and near an intact bed.
- Small underground caves.
- Bend-owned inventory, crafting, player physics, collision, raycast and edit validation contracts.
- Bend-owned health and hunger survival loop with visible HUD values.
- Fall damage, full-hunger regeneration, drowning air, and Bend-owned rotten-flesh poison.
- Rotten flesh, wheat, bread and apples can be eaten through the Bend2 hunger transition (`G`).
- Deterministic Bend-owned mobs with distinct passive, hostile, skittish and brute movement, player damage, aimed left-click combat and `F` melee attacks.
- One mob roster shared by both layers: a pig, a zombie, a sheep, a brute, a cow and a chicken, with `kind_is_hostile` in Bend as the only place that decides which kinds hunt and which burn, and `web/mob-kinds.js` carrying the model, hitbox, hurt voice and death-puff tint of each. Every kind owns a model, so a hostile is never drawn with a farm animal's body, and `tests/mob-models.test.mjs` cross-checks the two lists against each other.
- Farm animals wander, never damage the player and never burn. They run from the player only after the player hits one: `Entities.attack` sets a `panic` timer on the struck body and the step functions are the only things that spend it, so being struck is what makes a sheep bolt rather than a rule that keeps a cow permanently skittish.
- Animals stand in the open during the day and only a hostile has to wait for nightfall or a blocked sky, because an animal is the one body that never catches fire. The spawn grid is four blocks on a side so a 48x48 world carries a real population of five to fourteen animals rather than a lottery of one.
- Exposed hostile mobs burn during daylight and drop through the same authoritative death path. The fire itself is world state, not a browser effect: `Entities.sunlight_damage` publishes a `burning` flag per mob, and the browser draws flames and smoke from that flag rather than deciding for itself that a mob should be alight.
- Wooden, stone, iron and diamond swords, bows, arrows, shields and kill XP with Bend-owned damage/durability rules.
- Night mob respawn, distance despawn and death inventory drops.
- Mob state is spawned once for the world and preserved while the active chunk window streams; crossing chunks no longer respawns mobs or drops.
- Mob, drop and villager Bend states are included in the seed-scoped save and restored before the first simulation tick.
- Entity simulation uses a fixed Bend2 budget: mobs within the active radius use the full step, while distant mobs advance at one-fifth cadence; `bench:entities` compares both paths.
- Mobs and drops are indexed into chunk buckets before each Bend2 step; active buckets use the full tick and dormant buckets use the reduced tick without traversing a distance rule for every entity.
- Mob drops (wool, raw porkchop, raw beef, raw chicken and rotten flesh) rendered in-world and auto-collected through the Bend inventory contract. Loot follows the animal: the sheep shears and the three others leave raw meat.
- Coal, iron and diamond ore generated underground by Bend 2.
- Wooden, stone, iron and diamond pickaxes with Bend-owned tiered mining rules and durability state.
- Ore drops and resource progression through stone/iron/diamond pickaxe recipes.
- Bend-owned per-block furnace containers with coal fuel, raw iron smelting and iron ingot extraction.
- Furnaces also cook wheat into bread; placeable glass, crafting tables and nine-slot chests use Bend-owned item/block contracts and save state.
- Bend-owned wheat crops with validated planting, four growth stages, harvesting and seed/wheat drops.
- Planting requires tilled farmland; a wooden hoe converts dirt/grass into persistent farmland.
- Pinned simulation chunks keep furnaces, farmland and crops ticking outside the visual radius; farm state is saved with the seed-scoped world.
- Greedy WebGL meshing merges coplanar same-block faces before upload.
- Procedurally synthesized high-definition texture atlas for blocks and entities. Every tile is painted by a dedicated material painter in `web/material-textures.js` rather than from an authored 16x16 pattern: cobblestone is a Worley partition into rounded stones with mortar between them, bark is a field of vertical fissures, grass is thousands of individual blades, leaves are overlapping lens-shaped leaves, ores are faceted crystals embedded in exactly the stone the stone block uses, and furnaces, chests, doors, beds and crafting tables are built from planks, bricks, iron and glass. Each painter writes a colour field and a height field; the height bakes a top-left relief and matches the luminance the terrain shader derives its bump from. Ground materials are built from tileable gradient and Worley noise, so the same tile repeats across blocks without a seam, and every feature is at least a few texels wide so a magnified tile never turns into per-pixel stipple. Tiles are 128 texels in a 2048x2048 padded atlas with a 64-texel gutter, which certifies mip levels 1-6. Painting is a pure function of each descriptor and is cached per page, so the game's several atlas builds pay for it once, and each padded cell is composed in memory and uploaded with a single `putImageData`. Face UVs, block IDs and deterministic material variants are unchanged. The block item icons in `web/item-atlas.js` remain deliberate 16px pixel art.
- Per-pixel terrain lighting. The vertex stream carries a face normal and a packed (occlusion, block-light) pair, and the fragment stage owns the lighting: a sun term from the real sun direction, a hemispheric sky ambient gated by occlusion, and a GGX specular lobe. The baked vertex colour is now only a small per-face grade, so a face pointing at the sun is genuinely brighter than one pointing away.
- Deterministic 16px pixel-art item atlas for all current item IDs, including tools, food, bed, door and buckets.
- Dedicated entity materials, refined first-person hand/held-item geometry and public character-view API.
- Bend2 bulk sky/cave light levels and dynamic torch point light feed face shading without per-cell bridge calls.
- Standalone Bend2 light flood-fill primitive with walls, alternate routes and bounded propagation tests.
- Sun shadow mapping: a single orthographic cascade fitted around the player, re-fitted and snapped to the shadow texel grid every frame so the edges do not crawl, filtered with a per-pixel rotated Vogel disk and a normal-offset bias, with a light floor so a shadowed surface still catches scattered light.
- Volumetric cloud deck: a raymarched slab with a 3D-shearing density field, an in-scattering light march toward the sun, a Henyey-Greenstein phase term for the backlit silver lining, and energy-conserving absorption.
- God rays: a depth-derived sky occlusion mask and a per-pixel dithered radial march from the sun's projected screen position.
- Water with Gerstner swell in the vertex stage and per-pixel wave normals, Beer-Lambert depth absorption, Fresnel sky reflection, crest and shoreline foam, floor caustics and a sun glitter term, all faded with distance so the horizon does not alias.
- Grass and leaf wind: a smooth gust field evaluated in world space, so it stays coherent across greedy-merged quads of any size.
- HDR post-processing: the scene renders into an offscreen float target, then a six-step bloom chain, the god-ray pass, an ACES filmic tonemap, lift/gain/saturation/contrast grading, vignette, lateral chromatic aberration, shadow-weighted grain, an unsharp mask and FXAA. Every one of those is a slider in the options; the bloom chain and the shadow pass are skipped outright when theirs is at `0%`.
- Lit volumetric clouds. A cloud is a bright diffuse reflector, so most of its light is the whole sunlit hemisphere arriving on it, with the forward-scattering lobe adding the glow around the sun. Lighting the deck from the lobe alone capped it below the brightness of the sky behind it, which read as a flat grey stain across a blue sky; splitting the sun term into an isotropic part and the lobe lets the deck out-shine the sky and read as a volume. The gain was calibrated from pictures rather than derived, and `tests/cloud-lighting.test.mjs` holds the measured span it has to stay inside.
- Adaptive quality: five tiers that scale the cloud march, shadow filter taps, cascade resolution, water detail, foliage wind, internal render scale and bloom depth. The controller watches a smoothed frame time, with a fast multi-step drop for a catastrophic frame.
- Grouped options screen. **Video** holds graphics quality, graphics API, field of view, render distance and the frame rate limit; **Graphics** holds one slider per effect; **Audio** holds master, ambience and sound-effect levels; **Controls** holds mouse sensitivity and the key bindings; **Interface** holds the coordinates readout. The quality list is generated from the same tier table the runtime walks, so the panel cannot offer a tier that does not exist or lose one that does, and each entry states what it costs. A pinned tier turns frame-rate adaptation off. A `?graphics=<tier>` URL parameter still pins one for a single session and wins over the stored preference.
- Per-effect graphics options, in their own **Graphics** section. Every effect the pipeline already had is now a slider: sun shadows, volumetric clouds, water surface detail, resolution scale, bloom, sunbeams, water caustics, sharpening, vignette, film grain, chromatic aberration and anti-aliasing. Each is a percentage of the game's own look, so `0%` switches the effect off, `100%` is how it ships and `200%` doubles it; the controls are generated from the same table the renderer resolves its amounts through (`web/graphics-effects.js`), so the panel cannot offer an effect the pipeline does not have. The two levers do not overlap: the quality tier still owns what a frame may cost, and these own how much of each effect is shown, whichever tier is running. Turning shadows or bloom off skips the pass entirely rather than multiplying the result by zero, and the four that the tier prices per frame are the only ones whose default is held at `100%`, so the shipped frame costs what its tier says it costs. The optional WebGPU lane draws straight to the canvas with no post chain, so on an explicit WebGPU pin these controls are disabled and say why.
- Frame rate limit, in **Video**. The loop is uncapped by default, so on a high-refresh display it runs as fast as the panel allows. That is a real cost: holding 120 FPS on a 120 Hz screen draws roughly twice as often as 60, and the sustained GPU load is what makes macOS give up and park the panel at a lower refresh rate. Capping it is the direct remedy, and it is also the honest answer to "the game sits at 30 FPS": a cap can only ever lower the ceiling, never raise it, so a machine that cannot reach the cap keeps the frame rate it has. The list is generated from the table the pacer enforces, so the menu cannot offer a limit the runtime would ignore. The cap also becomes the target the adaptive quality ladder measures against — without that, a 30 FPS cap reads as a renderer in trouble and the picture degrades to the point at exactly the frame rate you asked for. `npm run bench:fps-cap` measures the result on the real GPU.
- Two-bus audio. Everything routes through a master and then splits into ambience and effects, so the world can stay audible with the music turned down. Levels are live and the menu previews a tone as a slider moves, through the same mixer instance the game plays on rather than a second audio context. A muted master or bus schedules nothing at all. **Reset to defaults** rewrites the whole option document, so a preference this build no longer knows about cannot survive it.
- Aerial perspective with sun-facing inscattering, and a day/night presentation cycle; the Options screen controls FOV, mouse sensitivity, coordinates, render distance and every graphics effect.
- Seed-scoped local save/load for player, inventory and Bend-owned block edits.
- First-person camera, WASD movement, mouse look and jumping.
- AABB collision, block raycast, block removal and block placement.
- Nine-slot hotbar inventory with stack counts.
- Inventory drag transfer, half-stack right-click moves, shift-click section transfer and `Q` item drops.
- Collecting a block adds it to the inventory; placing consumes one item.
- Bend laws and proofs: 114 laws in `world/LAWS.bend`, 31 of them for every input (see
  "Laws" above).

Block IDs:

- `0`: air
- `1`: stone
- `2`: dirt
- `3`: grass
- `4`: leaves
- `5`: wood
- `6`: sand
- `7`: water (fluid; bucket collection and placement are Bend-validated)
- `8`: coal ore
- `9`: iron ore
- `10`: diamond ore
- `11`: furnace
- `12`: torch
- `13`: bed
- `14`: closed door
- `15`: open door
- `16`: wheat crop
- `17`: growing wheat
- `18`: ripe wheat
- `19`: mature wheat
- `20`: farmland
- `21`: lava (fluid; emits light and supports bucket collection/placement)
- `22`: cobblestone
- `23`: obsidian
- `24`: fire
- `25`: glass
- `26`: chest
- `27`: crafting table

Crop items:

- `25`: wheat seeds
- `26`: wheat
- `27`: wooden hoe

Utility and material items:

- `28`: empty bucket
- `29`: water bucket
- `30`: lava bucket
- `31`: cobblestone
- `32`: obsidian
- `33–36`: wooden, stone, iron and diamond swords
- `37`: bow
- `38`: shield
- `39`: arrow
- `40`: glass
- `41`: bread
- `42`: apple
- `43`: chest

The current greedy meshing benchmark over the nine active chunks preserves all `19,880` solid blocks and reduces visible terrain quads from `10,250` to `3,275` (`68.0%` fewer). The CPU mesh-build pass measured `36.7 ms` versus `32.2 ms` for the scalar face pass in the same Bun run, so the geometry reduction is validated but the rebuild path still needs profiling before claiming an end-to-end speedup.

The reference seed `1337` now materializes `597` Bend-owned village blocks in the `48 x 48` world. The village anchor is deterministic, remains inside the generated world, and includes a furnace at `(25, 9, 27)` for a stable contract proof.

The reproducible `bench:villagers` run builds the `28 x 26` walkability grid from the current Bend-owned edit state in `238.7 ms` and resolves 30 bounded BFS routes in `916.4 ms` (`30.5 ms` per route). In the browser, that grid is now built by a dedicated worker path-grid job, so the synchronous path cost no longer blocks world entry; the authoritative villager transition still runs once per second.

The incremental chunk cache now rebuilds only the edited chunk and boundary neighbors: one interior edit measured `4.97 ms` versus `15.43 ms` for rebuilding all nine chunks (`3.11x` faster). The boundary merge pass reduces the cached result to `3,307` terrain quads versus `3,275` for one global greedy pass, leaving only 32 extra quads.

The lighting chunk benchmark over nine chunks produced the same `73,728` cells as terrain generation: `402.7 ms` for empty-source light versus `2,590.9 ms` for the world chunks (`15.5%` of the terrain generation time). An integrated one-torch bounded-flood window measured `95.3 ms` and reached a neighboring chunk 12 cells away.

Terrain generation runs through a `U32` core: on the JavaScript target every `Nat` is a BigInt and every `Nat` operator a trampolined call, so the hot formulas are written over native 32-bit integers, and everything a cell needs that only depends on its column (height, biome hash, sand surface, tree, the canopy layers of the 3x3 neighbourhood) is computed once per column. Chunk light is filled column by column from the top, so the sky test is a running flag, only the edits inside the chunk's columns are scanned, torch fields are pre-binned into the output array, and a torch flood is only computed for sources within reach (the chunk worker also caches each source's flood). `tests/world-chunk-golden.test.mjs` pins both outputs to fingerprints of the original per-cell `Nat` rules across four seeds, positive and encoded negative chunks, and edited saves. `bench:chunks` (warm medians, 16 chunks) went from `~475 ms` terrain + `~78 ms` light per chunk to `~4–5 ms` terrain + `~1.5–2 ms` light for a fresh world (the village chunk peaks near `20 ms`), and a save with torches and a lava bucket went from `~900 ms` of light per chunk to `~5 ms` once the worker has cached its floods. In a headless SwiftShader browser, reaching `pendingChunks: 0` at render distance 4 dropped from `38.4 s` to `11.0 s`, and at distance 6 from `55.7 s` to `12.9 s`.

The final browser diagnostic measured `113–135 ms` to schedule adjacent swaps and `150 ms` including the streaming mesh upload, with `pendingChunks` reported instead of blocking on the whole radius. Mob IDs remained unchanged across the same swaps.

The distant-terrain rings (`bench:lod`) cost about `2 ms` of Bend sampling plus `1.6 ms` of meshing per 16 x 16-cell tile on the LOD worker; at render distance 4 the 512-block view is 68 tiles (about 57k quads) and the 2048-block view 116 tiles (about 96k quads). Both renderers keep one buffer per chunk and per LOD section: WebGL no longer concatenates and re-uploads the whole world on every streamed chunk or edit, and it culls chunks against the view (and the sun cascade) frustum. The HDR scene uses a 24-bit depth texture where available, so distant terrain does not z-fight.

The reproducible `bench:render-distance` mesh workload scales from `25` chunks at distance `2` to `81` and `169` chunks at distances `4` and `6`. On the validation machine, the synthetic full-window mesh pass measured `105.8 ms`, `233.7 ms` and `437.0 ms`. With per-chunk buffers on both renderers the default is now `4`, and distances up to `8` are available.

The browser streaming smoke at distance `6` uses up to four chunk workers, sends only each dirty chunk's 3x3 mesh neighborhood, batches mesh targets at 64, and defers the WebGL global buffer upload until the current mesh job is complete. The latest runs reached `pendingChunks: 0` in `5.8–6.7 s` with 169 active chunks.

The HDR presentation pipeline costs real work per frame, and the only machine available here rasterises WebGL in software (headless SwiftShader), so the frame numbers below are a floor rather than a target. On that software rasteriser at `1440 x 900` the pipeline settles on the lowest tier and still measures roughly `280–580 ms` per frame versus `100–150 ms` for the previous single-pass renderer. Two levers keep it in bounds: the tier's `renderScale` shrinks the whole offscreen target (halving the colour, bloom and composite pixel counts), and the tier's `shadowMapSize` shrinks the depth-only cascade, which at 2048 is otherwise larger than the entire colour frame. The high-definition atlas synthesis is a one-time boot cost: about `0.8 s` for all 50 tiles under Node on this 2-vCPU container, cached afterwards, and composing and uploading the 2048x2048 canvas costs about `0.1 s` in headless Chromium. The previous gutter bleed copied the atlas canvas onto itself eight times per tile, which cost about `4.6 s` at this atlas size on the same software canvas and is gone. It is not a per-frame factor. No frame-time claim is made for real GPU hardware: it has not been measured here.

The reproducible `bench:renderer-browser` run samples a warmed 2.5-second browser window at `1280 x 720` and reports frame-time p95/p99 plus the minimum FPS. The default render distance is 2; `RENDER_DISTANCE=6 npm run bench:renderer-browser` is a separate high-distance stress run (the latest headless SwiftShader sample measured 15.78 FPS at 169 active chunks). The validation machine's headless SwiftShader browser exposes a WebGPU adapter but returns a transparent presentation surface, so the runtime probe correctly rejects WebGPU; `Auto` stays on WebGL instead of shipping a blank canvas. Run `npm run browser:webgpu-smoke` and `npm run bench:renderer-browser` on target hardware; only compare WebGPU FPS after the smoke reports `renderer: "webgpu"` and a visible presentation.

Torches use Bend2 source lists with Manhattan attenuation from level `14`, a `32 x 32` bounded flood window around each source, and a dirty-cell patch on the loaded light cache when placed or removed. The patch recomputes only the affected same-height plane; browser smoke measured torch light `14` at the source and `0` behind an opaque neighbor.

The Bend2 flood-fill contract is now integrated through bounded `32 x 32` windows around torch sources: sources, walls, alternate routes and sealed cells are resolved before the light chunk is uploaded, including propagation across adjacent chunk boundaries.

The reproducible `bench:light` run compares dirty-cell patches with full light-chunk regeneration and measures the source-field cache used by the browser. On the reference seed, a `421`-cell dirty plane measured `12.8 ms` cold / `3.3 ms` cached versus `44.6 ms` full for one source (`13.67x` cached), `44.3 ms` cold / `3.4 ms` cached versus `84.4 ms` full for four sources (`25.07x` cached), and `232.4 ms` cold / `7.0 ms` cached versus `257.0 ms` full for twenty sources (`36.64x` cached). The patch output is checked against the corresponding full-chunk cell in the Bend regression test.

Removing an opaque block now sends a compact 20-cell vertical column through the Bend2 edit-aware light patch, so sky light reaches the newly opened cell and the blocks below it without rebuilding a full light chunk. The final benchmark measured the edit-aware column patch at `4.1–7.0 ms` versus `160.3–200.7 ms` for the old `421`-cell plane, and `browser:lighting-smoke` verified a surface grass block changing from light `0` to `15` after mining.

## Setup

The toolchain runs on Windows through WSL, and natively on macOS and Linux. All
three use the same pinned `vendor/bend` submodule and the same project-local Bun.

Clone the repository with its submodule:

```bash
git clone --recurse-submodules https://github.com/lennix1337/bend2craft.git
cd bend2craft
```

If you cloned without `--recurse-submodules`, populate it once:

```bash
git submodule update --init --recursive
```

Install Bun into the project-local tool directory when needed:

```bash
export BUN_INSTALL="$PWD/.tools/bun"
curl -fsSL https://bun.sh/install | bash
```

The project scripts automatically prefer `.tools/bun/bin/bun`.

### macOS

macOS needs no WSL, but two stock details differ from Linux:

- The system `bash` is 3.2. The repository scripts are written to run on it, so
  nothing else is required.
- `scripts/dev-smoke.sh` puts the dev server in its own process group with the
  bash `set -m` builtin instead of `setsid`, which macOS does not ship.

To build and play, double-click `Play-Bend2Craft.command`, or run it directly:

```bash
./Play-Bend2Craft.command            # build, serve and open the browser
./Play-Bend2Craft.command --no-open  # build and serve without opening a browser
```

It builds the current bundle, fails closed if the build is missing or invalid,
serves with browser caching disabled, and opens the browser only after the port
is listening. `npm run build` followed by `node scripts/play-server.mjs --open`
does the same thing by hand.

## Multiplayer

Several players can share one world, and a native client can be one of them: it joins the
same room as the browsers and every block dug or placed goes both ways. Blocks are all it
shares so far; see "A native client in the room" below.

Several players can share one world. The server holds the world's seed and its
ordered edit log; the authority is `world/multiplayer.bend`, which validates each
submitted batch (in-world cell, known block, bounded batch size), folds the
accepted edits into the log in one `WorldState.set_many` pass, and advances a sequence
number. Poses are validated there too (finite, inside the world band, pitch
clamped). Every accepted batch is sent to every player, the sender included, and
each client replays the batches in sequence order with `Multiplayer.merge`, so
all players converge on the room's world. A rejected edit comes back to its
sender with the authoritative value of that cell.

Chests and furnaces belong to the room too, keyed by the same stored
coordinates. An accepted edit that places a chest (26) or furnace (11) opens an
empty one, and one that replaces it removes it; a chest that still holds items
cannot be broken (the edit is refused and the chest comes back). Deposits,
withdrawals, loading fuel and input and taking the output are Bend room
transitions (`Multiplayer.deposit`, `withdraw`, `furnace_op`), and the server
smelts with `Multiplayer.tick` every 200 ms. Every change goes to every player
as the container's full state; a refused deposit gives the item back, and
items handed over after the inventory filled up drop at the player's feet. The
world clock is the server's as well: every player sees the same time of day,
and sleeping starts the morning for everyone.

Mobs, dropped items, villagers, fluids, fire, crops and farmland run on the
server too (`server/server-world.js`). The server caches the chunks around
players and mobs with Bend's bulk `WorldState.chunk`, patches them with every
accepted edit, and every 200 ms runs the Bend entity, villager and simulation
rules for every player: mobs chase or flee the nearest player
(`MultiplayerMobs.step_world`), burn in daylight, hurt the players they reach,
spawn at night around every player and despawn only far from all of them;
villagers walk and open doors; water and lava flow, fire spreads and burns
out, and crops grow. Its block changes reach the edit log as server batches.
Hits (damage clamped to the strongest weapon, reach measured from the server's
pose of the attacker), pickups (two players cannot take the same drop), thrown
items and world interactions (buckets, fire, hoes, seeds and harvests, within
reach of the player's pose) are requests the server answers. Player movement is
checked against `world/multiplayer_moves.bend` (speed and rise budgets, no
walking into blocks); a refused pose is not relayed and the player is sent
back. `PEACEFUL=1` (or `vars.PEACEFUL` in `wrangler.jsonc`) hosts a world
without monsters. [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md) maps every rule to
its Bend contract and server module.

- `server/multiplayer-room.js`, `server/room/`: the transport-agnostic room
  (players, routing, fan-out, snapshots) around the compiled Bend authority.
- `server/server-world.js`: the server-simulated world (terrain cache, mobs,
  villagers, fluids, fire, crops, movement checks).
- `server/websocket.mjs`, `server/node-host.mjs`: a dependency-free WebSocket
  endpoint on `/multiplayer` for `scripts/play-server.mjs`, saving the world to
  `worlds/multiplayer.json` (git-ignored).
- `web/multiplayer.js`, `web/multiplayer-protocol.js`: the browser session,
  remote-player interpolation and the wire format (edits travel as
  `[x, y, z, block]` in stored Bend coordinates).
- `cloudflare/worker.js`, `wrangler.jsonc`: the same room in a Durable Object
  with SQLite storage, with the game served as Worker static assets.

Play on your network:

```bash
./Play-Bend2Craft.command --lan   # macOS; Jogar-Bend2Craft.bat --lan on Windows
# or: npm run build && node scripts/play-server.mjs --lan
```

The server prints the address friends open, `http://<your-ip>:8080/?play=1&mp=1`.
From the menu, "Join Multiplayer..." on the world list joins the server the page
came from, or any `host:port`, `http(s)://` or `ws(s)://` address. `SEED` picks
the seed of a new multiplayer world and `MULTIPLAYER_WORLD` the file it is saved
to; an existing file keeps its own seed. `npm run dev` hosts an in-memory room.

Play over the internet without a deployment: keep the server running and
expose it with a Cloudflare quick tunnel, then share the printed
`https://….trycloudflare.com/?play=1&mp=1` link (WebSockets pass through):

```bash
cloudflared tunnel --url http://localhost:8080
```

### A native client in the room

The server opens a second, plain TCP port for native clients, one above the HTTP port
(`NATIVE_PORT` changes it, `NATIVE_PORT=0` closes it), and prints the command to join:

```bash
npm run build && node scripts/play-server.mjs      # the server, on 8080 and 8081
bash scripts/play-native.sh --size=512 --join=127.0.0.1:8081
```

The native client and the browsers are then in one world: dig a block in one and it is gone
in the other, and each sees the others walk. A browser draws the native player like any
other; the native client draws the others as plain figures with their names over them, and
its day and night are the room's. It sees the room's animals, monsters, villagers and dropped
items, hits a mob with the dig key, is hurt by a monster and picks up what lies beside it.
It opens the room's chests and furnaces, and each click on
them asks the room. It plays in the room's world, not its own
save, and it refuses a room whose seed is not the native client's (1337).

On Windows the native client runs inside WSL, so start the server inside WSL too: the
launcher `Jogar-Bend2Craft.bat` starts it on the Windows side at `127.0.0.1`, which a
program inside WSL does not reach by default. Verified on one machine: Windows 11, WSL2,
server and native client both in WSL, the browser on Windows. The Cloudflare deployment
has no native port.

Deploy to Cloudflare (Workers Free plan; Durable Objects with SQLite storage):

```bash
npm run build
npx wrangler login
npx wrangler deploy
```

Then open `https://<worker>.workers.dev/?play=1&mp=1`. The deployment hosts one
shared world; `vars.SEED` in `wrangler.jsonc` sets the seed of a new one.

Scope so far: blocks, player presence and movement, chests, furnaces, the time
of day, mobs, drops, villagers, fluids, fire and crops are shared and
server-owned. Inventory, equipment and position are saved per profile and per
server in each browser. On Cloudflare, furnace progress and simulation state
are written to storage at most every 30 seconds.

## Commands

Run these commands at the repository root, from WSL on Windows and from a normal
shell on macOS or Linux:

```bash
npm run verify       # all Bend, proof, test, build and diff checks
npm run check:bend   # type-check world/world.bend
npm run proof        # prove all 114 laws of world/LAWS.bend
npm run test         # world, inventory and game-state regression tests, then the native Bend ones
bash lab/native/paint/run.sh   # the native client's frame cost, per size and thread count
bash lab/native/paint/shot.sh  # the native client's frame as PNG files
npm run bench:light  # compare dirty-cell and full light updates
npm run bench:render-distance # measure mesh cost for distances 2/4/6/8
npm run dev          # start the Bun development server
npm run smoke:dev    # bounded readiness smoke; always cleans up its server
npm run browser:smoke # Playwright browser smoke; requires a local browser binary
npm run browser:lighting-smoke # verify sky light after mining a surface block
npm run browser:streaming-smoke # measure radius-six chunk hydration and mesh readiness
npm run browser:multiplayer-smoke # two browsers sharing one dev-server world
npm run bench:multiplayer # room batch, merge, welcome and movement-check costs
npm run build        # clean dist/ and create the current static bundle
```

On Windows, double-click `Jogar-Bend2Craft.bat`. It builds the current bundle through WSL before serving, fails closed if the build is missing or invalid, serves with browser caching disabled, and opens the browser only after port `8080` is listening. Use `Jogar-Bend2Craft.bat --no-open` when launching manually. On macOS, `Play-Bend2Craft.command` is the equivalent and builds natively instead of through WSL.

Open the URL printed by the launcher in your browser.

## Development workflow

The pure player/world state lives in `web/game-state.js` and is tested without a browser. The browser entry router/menu lives in `web/main.js`; the WebGL/game runtime lives in `web/game.js`. Validate the served game manually with `npm run smoke:dev` and a browser after passing `npm run verify`.

For a long-lived local server, keep the background process silent, check readiness once with `curl`, and stop it after the browser smoke test. This avoids stale readiness notifications after the server has been killed.

## Seeds

The default seed is `1337`. Open a specific numeric or text seed directly:

```text
http://localhost:3000/?seed=1337
http://localhost:3000/?seed=forest
```

The same seed produces the same heights, trees and block layout. Different seeds change the terrain and tree distribution while preserving the world dimensions and block contract.

## Controls

- `WASD`: move
- Mouse: look after clicking the canvas
- `Space`: jump or swim upward while held; keep it held to jump again as soon as you land
- `1` through `9`: select a hotbar slot
- `E`: open the inventory and wood crafting panel
- Right-click a placed furnace or press `R` after selecting one to open its container
- `G`: eat the selected food item
- Left click: attack the mob under the crosshair, or mine the targeted block when no mob is targeted; hard blocks require the correct pickaxe tier
- Right click: place the selected block if the stack has items
- `F`: attack/shoot the nearest valid target; a bow requires arrows
- `Esc`: release the mouse pointer lock

## Development rules

Read `AGENTS.md` before changing the project. Keep generation and block semantics in Bend, write a failing regression test before behavior changes, and run all four commands above before publishing changes.
