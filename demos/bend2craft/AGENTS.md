# Bend2Craft repository instructions

When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible.

## Project constitution: Bend 2 first

This project's primary objective is to stress-test Bend 2 as the engine for large games. Prefer Bend 2 for every domain rule, simulation transition, world query, chunk generator, inventory/crafting operation, collision rule, and authoritative state that it can express. Treat browser JavaScript as a thin adapter for presentation, input capture, cache management, and APIs Bend 2 cannot currently provide.

Non-negotiable rules:

- Before adding domain logic to JavaScript, check whether a typed, pure Bend 2 contract can own it. If it can, implement and prove it in Bend 2 first.
- Expose bulk Bend 2 operations at boundaries. Do not make per-cell or per-entity JavaScript calls when Bend 2 can return the batch.
- Use Bend 2's parallel/native execution features when the selected target supports them, and benchmark the selected target. Never claim browser GPU or multithread acceleration when the JavaScript target ignores `!`, `--threads` and `--gpu`.
- Keep browser code limited to adapting Bend 2 values into WebGL/WebGPU presentation, input events, local caches and unavoidable browser APIs. Do not duplicate formulas or silently make browser state authoritative.
- Every performance-sensitive Bend 2 change needs a reproducible benchmark and a focused correctness test; report measured results, not assumed speedups.

The current browser slice is not fully migrated yet: `web/game-state.js` still owns player physics, collision, raycast and movement transitions. Do not expand those JavaScript authorities; migrate new behavior to Bend 2 as those contracts are extended.

## Project

Bend2Craft is a small Minecraft-inspired voxel sandbox. The canonical repository is https://github.com/lennix1337/bend2craft.

The game model is authored in Bend 2 under `world/`. Two targets consume it:

- **Browser** — `web/` is an adapter: it materializes Bend contracts, captures camera/input, maintains derived caches, and renders with WebGL. Do not duplicate domain formulas or authoritative transitions in JavaScript.
- **Native** — `native/` is a Bend 2 program with its own window, compiled by the pinned CLI to a native executable. It is not a port of the browser: it reuses `world/` and owns its own renderer, player region and save codec.

Start here:

- Bend world contract: `world/world.bend`
- Bend laws and proofs: `world/LAWS.bend`, `world/PROOF.bend` (114 laws, 31 of them for
  every input; see "Laws" below)
- Bend module boundary: `web/bend-modules.js` (wraps every `world/*.bend`
  module; the only place that knows how the JS lane names a datatype)
- Current inventory adapter/migration target: `web/inventory.js`
- Chunk cache/streaming adapter: `web/chunk-world.js`
- Pure player/world state: `web/game-state.js`
- Browser entry router/menu: `web/main.js`; WebGL/game runtime: `web/game.js`
- Native client: `native/client.bend` (the entry point: the window and the frame loop); the
  client itself is `native/play.bend` (the player, the world it holds, one tick and one frame,
  the save), with `native/action.bend` (the ray as the world's cell, dig and place, how long a
  block takes), `native/slabs.bend` (the world's faces, a chunk at a time), `native/hour.bend`
  (a room's clock), `native/room.bend` (a multiplayer room, from the client's side) and
  `native/size.bend` (the window's size and the table that prices it). Its other modules are
  `native/voxel.bend`,
  `native/face.bend` (the ray walk: the pointer's ray, the tests' reference, and
  what `native/paint_test.bend` holds the painter against),
  `native/paint.bend` (what draws the window), `native/frame.bend`,
  `native/pointer.bend` (the look under WSLg, read from the Windows host),
  `native/texture.bend` (the blocks' 16x16 surfaces, as a rule per texel),
  `native/shade.bend` (the light each corner of a face takes, worked out per chunk),
  `native/sky.bend` (the sky's gradient, the air between, and the hour),
  `native/scenery.bend` (clouds, sun, moon and stars, and the frame's entry point),
  `native/bag.bend` (the inventory, wired to `world/inventory.bend`),
  `native/hud.bend` (the hand, hotbar, hearts and crosshair painted over the frame),
  `native/screen.bend` (the inventory, crafting table, chest and furnace screens: their
  layout, their arrow and their picture), `native/stores.bend` (what a click does to a chest
  or a furnace), `native/stash.bend` (the bag and the chests and furnaces, saved as text),
  `native/net.bend` (the lines a native client and a multiplayer room exchange),
  `native/body.bend` (a room's other players, mobs, villagers and dropped items, as boxes
  the painter takes among the faces),
  `native/tag.bend` (a player's name over its head, in the overlay's dots),
  `native/player.bend`, `native/save.bend`
- Native experiments and their measurements: `lab/native/`
- Multiplayer (room, server simulation, protocol): `docs/MULTIPLAYER.md`
- Regression tests: `tests/`

## The two targets run one engine

The browser and the native client are the same Bend 2 program on two lanes:
`vendor/bend/bend2/main.ts` under Bun for the bundle, and the same vendored
sources compiled by the pinned CLI to C for the executable. The rules are
`world/*.bend` either way, so a rule cannot mean one thing in the browser and
another natively.

Keep it that way, and prove it rather than assume it:

- **One vendored compiler.** `vendor/bend` is pinned, and the native CLI is
  built from that exact commit by `scripts/bootstrap-native-bend.sh`. If the
  pin moves, both lanes move together or the comparison is meaningless.
- **Cross-lane equality is already a check.**
  `benchmarks/bend-native-parallel.bend` is run by `npm run check:bend` through
  Bun and by `npm run bench:bend-native` as a native binary, and both must
  print `549755289600`. Any change to `world/` that moves one lane and not the
  other fails one of them.
- **Never fork a rule per target.** If the native client needs behaviour the
  browser does not, put it in `world/` or in `native/`, not in a copy.
- The JS lane and the native lane are not interchangeable at the margins. The
  JS lane refuses a negative `Nat`, and the native target's `Nat` is
  unsigned for the same reason. Benchmarks taken in one lane are not evidence
  about the other unless the script says which lane it ran in.

## Native target

`native/` is the target that ships. `lab/native/` is everything that was tried
or measured. **Nothing in `native/` imports from `lab/native/`**, and the
dependency only runs that way: a lab module that stopped matching its client
would be measuring a different program.

- `native/client.bend` is the entry point. It opens the window and runs the frame loop over
  `native/play.bend` and `native/room.bend`; it owns no game rule and no state, and neither
  does `play.bend`, which wires the world, the camera, the input fold, the tick and the save.
- Each `lab/native/<module>/` holds the benchmarks and the recorded numbers for
  the `native/<module>.bend` beside it. The module ships; the measurement does
  not.
- `native/main.bend` and `native/world.bend` are the 16x16 feasibility slice,
  kept as the smallest thing that opens a window. Their two-byte save is not
  compatible with `native/save.bend` or with browser saves.
- The native save is `B2CW:1` in `native/save.bend`, which also migrates the
  legacy browser and multiplayer snapshots. `native/client-world.b2cw` is
  gitignored and written by the save key.
- Two lab probes fail and are not in the gate:
  `lab/native/voxel/voxel_probe_parallel_test.bend` (fails at the pinned commit
  too) and `lab/native/client-probe/span_probe.bend` (passes its assertions,
  then overflows the stack in a walk that follows). Do not treat either as a
  regression signal, and do not quietly delete the assertion that caught it.
- `lab/native/client-probe/painter_agree_test.bend` is the investigation gate
  that found the painter's near-plane defect and is **not** in the suite: it
  reports rather than dies and its cameras include `up`, whose eye is inside
  terrain. The gate that *is* in the suite is `native/paint_test.bend`, which
  compares `Paint` against `Face` on the spawn scene at 128, 256 and 512.

### Where this was measured, and where it was not

Everything in this file about the native client was measured on **one machine and one
lane**: an AMD Ryzen 7 9800X3D (8 cores) under Windows 11, inside **WSL2 Ubuntu**, shown
through **WSLg**, compiled by Bend 2.0.32 to native C and run with the default
thread pool on the **CPU**. Every number is `--gpu off`. (The pin is now 2.0.35; these were taken
on 2.0.32 and are not re-measured. The Mac numbers are a separate lane, in `lab/native/paint/README.md`.)

- **The client has no GPU path.** The runtime only builds a
  device program when the source has a `!` call (`BANGS != 0` in the runtime, and
  `main.ts` links CUDA or Metal only then), and `native/` has none: `--gpu on` is refused
  and the fork tree runs on the CPU pool. Adding one is not a flag. `vendor/bend/guide/SHADERS.md`
  is the contract: one bang a frame, leaves that are flat loops over cons lists, and no
  `Array` down the fork tree — and a tile here paints into an `Array` and folds it with a
  non-tail walk, which is the shape that guide measures as the slow one. A device painter
  is a second leaf, not a marked call.
- **A CUDA device cannot be used under WSL2 at all** with the pinned runtime: it needs
  concurrent managed memory, which WSL2 lacks, and the runtime says so and stops. So the
  RTX 4070 SUPER this machine has is not a way to test a device painter; a native Linux
  with the CUDA toolkit, or a Mac with Metal, is. Do not write that the client runs on a
  GPU, or how fast, until someone has run it there and the digest matched the CPU's.
- **macOS has been run, once, on one machine, and only the benchmark and the build.** An Apple
  M1 Pro under macOS 27.0 built the native client and ran `lab/native/paint/run.sh`; the
  numbers are in their own section of `lab/native/paint/README.md` and are not comparable
  with the WSL ones. A window was not driven by hand there, so nothing says the client plays
  correctly on macOS. On macOS the compiler builds a Metal program for any program with a `!`,
  and every windowed program has one (`Image.drop!` in `Base`'s `App.turn`); that step crashed
  Apple's shader compiler on M1 and M2 from Bend 2.0.29 to 2.0.34, which is why the pin is 2.0.35.
- **`--gpu on` was run, and it changes nothing.** On the Mac the benchmark ran with `--gpu on`
  and `--gpu off` and agreed within noise (0.96 to 1.06), because `paint_bench` has no `!` call
  and the painter has no device leaf. That is not a GPU painter: the claim above stands that
  there is none, and a device painter is still a second leaf and not a flag.
- **A device leaf was tried once, as a throwaway, and is slower.** `lab/native/gpu-probe/` draws the
  textured frame from flat loops under one bang, on Metal, with the same picture as the CPU painter to
  within float rounding (54 of a million pixels differ at 1024x1024), and costs 82 ms a frame at best (after the
  optimizing in its README) against the CPU painter's 6 ms. Forking to more leaves helped at small sizes and then stopped helping;
  the cost is spread over every layer (structure 25 ms, list walk 37, coverage 16, texel 55 of 133), and the
  reference rasterizer it was modelled on differs in ways the README lists. **On this M1 Pro that reference is
  itself twice as slow on the GPU as on the CPU pool** (`lab/native/gpu-probe/control.sh`: 11.0 against 5.7 ms to
  draw 1920x1200), so a GPU painter is not expected to win on this hardware whatever the leaf; the guide's
  figures are from an M4. It is a spike
  and not a path, and its README says what it did not settle.
- **Native Windows is not a target.** The toolchain runs in WSL.

A number from this machine is a number about this machine. Quote it with the lane, and
re-run `lab/native/paint/run.sh` before changing it.

### Frame budget

The pinned runtime's `window_pace` sleeps every presented frame to a hardcoded
16666667 ns interval, so **60 Hz is a ceiling, not a budget** and no renderer
here can present faster. What is ours is the frame cost, and therefore how large
a window fits inside the cap.

**`Paint` draws the window, one tile per task, nearest first.** `native/paint.bend` orders
the faces **by block**, nearest first, and projects each one once into a flat list of
screen polygons, after the overlay's. Before that it drops every face that cannot
paint: wholly behind the near plane, outside the view (the frame is two thirds of the
distance ahead to each side, with a block's own reach allowed), turned away from the
eye, or past the end of the air. That is most of a region. The order is
each block's distance from the eye summed along the three axes, which is exact for blocks
on a grid; the key it replaced was each face's own farthest corner, a partial order whose
ties let a far face paint over a near one. A face that crosses the near plane is **cut**
there, not skipped: skipping it made the wall a player stands against invisible. A fork
tree deals the list down to 64-pixel tiles; each tile resolves its polygons to an integer
span per scanline in an array of its own, **writes a pixel only if nothing has**, and folds
the array into its quadtree. A region no polygon reaches answers its sky without an array.

**A pixel is a texel, its light and its air.** A face carries its own plane as three
functions of the pixel (`Paint.Ink`), so a pixel is three additions, three divisions and
`Texture.texel_lit`: where on the face it looks, in sixteenths, the material's colour
there, the light of the face's four corners at that texel, the hour's light, and then
`Sky.hazed`, the air between the eye and the face. That is affordable only because the
frame is painted nearest first — a pixel a near face covers is never computed for the
faces behind it. `native/texture.bend` is the materials, as arithmetic on
`Voxel.block_color`; there is no atlas, because a tile shares nothing. The two commonest
cases do no arithmetic at all: a face with every corner fully lit, and a pixel nearer than
where the air starts.

**The light is worked out per chunk, not per frame.** `native/shade.bend` gives every
cell of a chunk a level — 15 under open sky, less under leaves and through water, 5
under anything solid — and every corner of a face the mean of the four cells it touches,
a filled cell counting as nothing. That one rule is the dark crease where a wall meets
the ground and the soft edge of the shade under a tree. The four levels ride in the
face's `block` above the block id, as how far each is **below** full light, so a face
with no levels is a fully lit face and everything that reads a plain block id still
works. What lets light through is `Light.transparent_block`, the world's own answer.
A cell outside the chunk is not known to a slab and is read as the cell the face looks
into, which leaves a corner on a chunk's edge neither darker nor lighter for it.

**The sky and the air are one colour rule** (`native/sky.bend`), so a hill at the edge of
what is drawn fades into the sky behind it instead of ending against it. The sky is a
gradient over the view, not the screen: the horizon is where the camera's pitch puts it.
The air starts to show at 22 cells and hides everything at 58. A frame is painted under
one `air` — the horizon's and the zenith's colours in one word — and at one `level`, both
worked out once from the client's clock, so a pixel never asks what time it is. A day is
twelve minutes: `Sky.day_ticks`. The clock is not saved; a session starts mid-morning.

**Clouds, the sun, the moon and the stars are flat polygons behind the scene**
(`native/scenery.bend`). The painter takes a list of polygons that are further than every
face and paints them last, so each costs a projection and no pixel is written twice. The
clouds are a rule on the world's own cells, so they stay put while the region moves under
them, and they drift with the clock.

`native/paint_test.bend` holds the **flat** frame — one colour per face, which is what
names a block and a side — to `Face`, the ray walk that still answers the pointer, at the
same three 1% limits `native/face_test.bend` holds the walk to the ray renderer; holds the
tiled frame to the same frame painted as one tile, node for node; and holds the textured
frame to the texel each corner of a face must show and to the flat frame's coverage. The
flat frame has no light, no air and the ray renderers' own sky, which is what lets it be
compared with them. `native/shade_test.bend` holds the corner levels and, from a picture,
that the painter lays them on the side of a face the wall is on; `native/sky_test.bend`
the air, the horizon, the fog and the hour; `native/scenery_test.bend` the sun's path,
the clouds and what is in the frame at noon and at midnight.

**The tiles are why threads help.** A painter that writes every span into one frame-wide
array has one owner for it, so it was 1.75x *slower* on eight threads than on one and
1024x1024 cost 47.65 ms. A tile's array is created, written and folded inside one task, so
nothing is shared.

**The region is five chunks by five and follows the player.** `Frame.Home` is its
first chunk. It stays put while the player is in its middle chunk or within four cells of
it, and past that `Frame.home_for` moves it so the player's chunk is the middle one again;
the margin keeps a player on a chunk boundary from moving it with every step. It was three
by three, and the world ended sixteen cells from the player; at five there are at least
twenty-eight cells in every direction, which is past where the air starts.
`Slabs.world_for` brings the faces after it on the next views, and the tick keeps the
collision region around the player, so there is nothing near the player in the picture
that they cannot walk up to. `Home` is in **window chunks** — chunks of the
player's movement window, where world chunk 0 is `PlayerProbe.window_origin_chunk` — so the
region is consecutive across the world's origin; `PlayerProbe.stored_chunk` is the one
place a window chunk becomes storage's spelling, which counts a chunk before the origin
from `World.negative_origin`. `bash lab/native/pointer/walk-probe.sh s` holds a key in the
client's own loop and prints each place the region was. The pose is still counted from chunk (1, 1) — `Frame.origin_x` —
whatever the region's place: `Frame.view_eye` is the signed shift for the renderer, and
`Action.aim_cast` goes back into the player's window by the pose's origin, not the
region's. One client frame in milliseconds, native C, `--gpu off`, from the spawn pose,
40,656 faces, the `client` phase of `bash lab/native/paint/run.sh`, medians of five:

| size | 1 thread | 2 threads | 4 threads | 8 threads | fits 60 Hz |
| --- | ---: | ---: | ---: | ---: | --- |
| 32 | 0.88 | 0.82 | 0.95 | 1.07 | yes |
| 64 | 1.02 | 1.05 | 1.15 | 1.30 | yes |
| 128 | 1.55 | 1.52 | 1.68 | 1.98 | yes |
| 256 | 2.90 | 2.23 | 2.12 | 2.25 | yes |
| 512 | 7.55 | 4.83 | 3.62 | 3.17 | yes |
| 1024 | 24.52 | 13.93 | 8.40 | 6.10 | on four or eight; **no on one**, and barely on two |

**The spawn is the cheapest frame there is**: it is inside a house facing a wall. The same
script draws 1024 from open ground in the middle of the region, in milliseconds:

| looking | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| north | 23.52 | 14.65 | 10.03 | 8.32 |
| east | 15.50 | 9.90 | 7.22 | 6.15 |
| south | 17.77 | 10.93 | 7.60 | 6.30 |
| west | 24.93 | 15.40 | 10.45 | 8.32 |
| down across the terrain | 27.20 | 16.25 | 10.75 | 8.47 |
| up | 11.25 | 7.15 | 5.20 | 4.42 |

So **1024 needs the pool**: on one thread it misses the tick almost everywhere and on two
it is within half a millisecond of it looking down. The client's epilogue says so. The numbers
the client prints live above `sizes()` in `native/size.bend` and are the spawn's
eight-thread column plus the measured 0.03 ms tick.

**The front half of a frame is done a chunk at a time.** The painter is handed the slabs
as groups (`Paint.Group`): each chunk's faces in its own cells, beside where the chunk is.
A chunk whose box is behind the near plane, outside a side of the view or past the air is
not read at all, and the chunks that are kept are each their own task: their faces that can
paint are found and projected there. The polygons are then put in order **by counting, not
by sorting**: the order between two blocks only matters when one can hide the other, and
then their summed distances differ by a whole cell, so a bucket per whole cell of distance,
read farthest first, is the order. That is one pass to fill and one to read. Before this the
whole region was walked, sorted and projected on one thread, 2.8 ms looking north across
open ground; it is now 1.5, and 0.3 where most chunks are behind the player.

**What is left that one thread does** is about four milliseconds of a 1024 frame and is
not the painter's: the tiles' quadtrees are a million `Pix` and the present walks them one
by one (`window_show`, which the benchmark's read-back stands in for). Looking up at the sky
is 4.42 ms on eight threads for that reason. It is why eight threads are 3x to 4x faster
than one and not 8x, and it cannot be cut from here: `vendor/bend` is not ours to edit.

**The pool costs a small frame.** Forking the chunks wakes it, so 32x32 looking east is
0.33 ms on one thread and 0.82 on eight. Every size still fits the tick many times over.

**The world is kept one chunk at a time, and an edit is 5 ms.** `Slabs.World` holds a
slab of faces per chunk (`Slabs.Slab`), each extracted from its own chunk with air outside
it, each face with its corner levels. An edit rebuilds the one slab it is in and merges
the region again (2.55 ms, `slab`) and rebuilds the collision region (2.40 ms, `collide`);
a region that moved builds the five slabs that came into view one a frame. The whole
region from nothing is 32 ms (`build`), paid once at start. The price of a slab being its
own is the faces between two solid blocks on a chunk's edge, which a region extracted as
one piece leaves out. Nothing can see them — any ray that reaches one entered the block in
front through a nearer face — so they are projected when they survive the culling and never
painted.

**Every walk over the region's faces is a loop.** A region is tens of thousands of faces,
and a `def` that calls itself before combining its result is a call per face: `Face.face_total`
and the painter's culling pass overflowed the machine stack at five chunks by five until
each carried its result down instead. Write a new pass over `w_faces` with an accumulator.

**The collision region is two chunks by two**, placed by `Frame.den_for` so the player is
at least six cells inside it. The player only touches what is near, and it is rebuilt whole
on every edit.

`DISPLAY=:0 bash lab/native/client-probe/run-pace.sh --size=1024` times every frame of the
client's own loop while the player walks across open ground, on the real display. On WSLg,
with the five-by-five region, the light, the air and the sky, it read **59.99 FPS with one
late frame and a worst of 19 ms** at 1024 and 59.98 with one late at 512, over 869 frames.
`run-fps.sh` stands still at the spawn and cannot see a late frame.

**A region of several chunks is laid out row by row across its chunks**
(`Face.region_layer`). Concatenating each chunk's whole layer is the right order for one
chunk and a scramble for more: it drew plausible terrain that was not the world, and the
player walked through walls they could see and into walls they could not.
`native/face_extraction_test.bend` holds a two-by-two region to `World.block` cell for
cell.

`bash lab/native/client-probe/run-fps.sh --size=1024` re-measures the live presented rate
under a real X server over 600 frames. Re-run it after any change to the region or the
painter; the last reading is in `lab/native/paint/README.md`.

`lab/native/paint/run.sh` fails if the tiled frame and the one-tile frame, or any two
thread counts, print a different digest for the same size. Keep it that way: a frame that
changes with how it is divided, or with the thread count, is a bug and not a speedup.

`bash lab/native/paint/shot.sh [label]` paints the client's frame from twenty-two cameras
and hours and writes each as a PNG under `scratchpad/shots/`. **Look at the picture after
a change to what a pixel is.** A test can say a corner is darker; only the picture says
whether the world looks right, and every change to the light, the air and the sky here
was judged from one.

`Voxel.sky_color` is a 32-row gradient and overflows its channels on a taller frame, which
drew the sky as coloured bands. The flat frame uses `Voxel.sky_color_at(y, size)`, the
textured one `Sky.color`; the legacy 32x32 renderers still use the old one, which is
correct at their size.

The native client picks its size from `--size=32|64|128|256|512|1024` and prints
that table before the window opens, so a player chooses against the cost instead
of guessing. Bend 2.0.32 has no stdin, so the choice is a flag and not a prompt.
Quote the numbers as measured on the machine named in
`lab/native/2026-09-30-native-renderer-investigation.md`, never as a property of
the renderer. Re-run the benchmark before changing any of them, and never widen
the window on an extrapolation. `native/size_test.bend` divides the rate back
out of each cost field rather than reading it from a table, so a drifted
measurement fails the gate.

### `Array.new`'s third argument is a depth

`Array.new(T, d, v)` builds a tree whose halves are `T^p` for `d = 1n + p`, so
`d = 11n` holds 8192 cells and a 32x32 frame is `5n`, **not** `1024n`. Passing the
element count fail-stops with "an array past the deepest block class 31". Passing
too few wraps *silently*, because `Array.get.at` and `Array.swap.at` both mask the
index with `n - 1` — so an undersized array produces a plausible picture at the
wrong size with no error at all. `[v : T^d]` is `2^d` slots, so a square of edge
`2^t` is `2 * t`, which is what `Paint.tile.painted` passes.

### Bend 2.0.32 has no stdin

`IO` offers `print`, `args`, `get_env`, `sleep`, `now`, `thread_count` and
`random_u32`, and there is no way to read a key from a terminal. Anything that
must be chosen before the window opens is chosen from `IO.args()` or an
environment variable, and the choice is echoed to stdout. Do not design a
console prompt and discover this at the end.

### The inventory is the rules', and the client only holds it

`native/bag.bend` is the slots and which hotbar slot is in hand. Mining is
`Inventory.mine_interaction_at` and placing is `Inventory.place_interaction` — the same two
calls the browser makes — so what a hand can break, what a block drops, what a tool wears
and what an item places are `world/inventory.bend`'s answers on both targets.
`Inventory.placed_block` and `Inventory.mining_item` own the item-to-block table on
both targets; the browser reads them through `web/inventory.js`'s
`blockForItem`/`itemId` and keeps no second copy of its own.

- **A refused action changes nothing.** By the rules a bare hand cannot break stone. The
  starting bag is `Inventory.create()` plus a diamond pickaxe in the sixth slot, because
  the digging tests dig with it; it can go once they make their own. The bag also starts with
  a crafting table, because by the rules a crafting table is nine planks in a grid of three
  by three and the inventory's grid is two by two, and with a chest, because the rules have
  no recipe for one.
- **`R` places and touches no other cell.** It used to dig the cell the ray hit before
  placing beside it, which is the block next to a new one vanishing.
- **The world's save is the edit log only.** `B2CW:1` carries nothing a player holds; that is
  the stash's. Without a stash a restart is the
  starting bag again.
- `native/hud.bend` paints the arm and what it holds, the nine hotbar slots, ten hearts,
  ten food and a crosshair, as flat quads (`Paint.rect`, `Paint.quad`) handed to the painter
  ahead of the scene, so they are painted first and stay on top. `native/hud_test.bend`
  reads them back out of a painted frame.
- **The mouse buttons hold bits of their own.** `Frame.fold_keys` holds `Frame.left_bit` for
  the left button and `Frame.right_bit` for the right, so a click is an edge like a key
  press. The left button digs and `F` digs from the keyboard; the right button and `R` place.
  They shared `E`'s and `R`'s bits until `E` became the inventory's key.
- **`E` opens the inventory screen, laid out as the original's.** `native/screen.bend` is the
  176-by-166 panel of the game this one is modelled on, slot for slot: the hotbar at
  (8, 142), three rows of nine from (8, 84), the two-by-two crafting grid from (98, 18) and
  its result at (154, 28), a slot sixteen units inside a one-unit edge. A unit is a whole
  number of pixels from 176 across and the panel is squeezed below that. The rules are
  `world/inventory.bend`'s: `Inventory.click` is a click (the left button takes, puts, tops
  up or swaps; the right takes half or puts one), `Inventory.craft_preview` what the grid
  shows and `Inventory.craft_take` taking it onto the arrow.
- **The screen's state is the bag's, and its input is edges of the mask.** `Bag.Desk` holds
  whether it is open, where the arrow is, the stack on the arrow and the grid, so nothing an
  arrow carries can be lost between two ticks. `Screen.step` reads the open key, escape and
  the buttons as edges of the held-key mask, not as events, because X11 repeats a held key;
  and it moves the arrow by `Frame.look_dx` and `look_dy`, the pointer's movement before the
  sensitivity. While it is open the tick steps the player with nothing held, digs and places
  nothing, and escape closes the screen instead of the client — quitting is an edge now, so
  an escape still held on the tick after does not quit. There is no system cursor: the
  window holds the mouse, so the arrow is drawn.
- **Closing puts everything back, and loses nothing.** The arrow's stack and the grid go back
  among the slots (`Screen.closed`); a tool goes whole into the first empty slot, with its
  wear. What finds no room stays on the desk and is there when the screen opens again.
- **The place key on a block with a screen opens it.** A crafting table (block 27) is the
  same panel with the whole of the rules' grid, three by three from (30, 17) and its result
  at (124, 35). A chest (26) is a row of nine from (8, 18) — `world/chest.bend`'s chest holds
  nine, not the original's twenty-seven — and a furnace (11) the original's three slots, a
  flame and an arrow that fills. `Bag.Desk`'s first field is which screen is open, and one
  space of slot numbers serves them all (`Screen.present` says which a screen has).
- **A chest and a furnace are clicked through the rules a room applies.** `native/stores.bend`
  turns a click into `Chest.deposit` or `Chest.withdraw`, `Furnace.load_input`, `load_fuel` or
  `take_output`, chosen by what the arrow carries, so a deposit lands where the rule puts it
  and not always under the arrow, and nothing can be taken back out of a furnace's first two
  slots. Furnaces step once a second, open or not (`Stores.ticked`), and a chest that holds
  something cannot be dug, as in the browser. The chests and furnaces ride in the bag
  (`Bag.Store`), because an item leaves a slot and enters a chest in one transition.
- **In a room a chest and a furnace are the room's, and a click asks.** The room says what
  each holds on joining and whenever one changes (`S`, `O`), and `Stores.put` keeps the
  client's copy the room's. A click then changes nothing: it leaves a request in the store
  (`Bag.Ask`), the session sends it (`CD`, `CW`, `FI`, `FF`, `FO`), and the arrow changes
  when the room answers (`R`, `Stores.answered`). One request waits at a time and a click
  while one waits is dropped, so an answer is never matched to the wrong click; a quick move
  there is a plain click, and a furnace is loaded one item a request, which is the room's
  rule. Out of a room the same clicks apply the same rules at once. `Play.tick.room` with `roomed` set is the
  room's tick: it marks the store as the room's and does not step the furnaces.
- **A block comes away when the dig button has been held on it long enough.**
  `Inventory.mining_duration` says how long, with what is in hand; `Digging.Dig` (`world/digging.bend`, where
  `Digging.step` is the rule and `a_refused_dig_gets_nowhere` its law) is the cell
  being dug and the time so far, and a bar under the crosshair fills with it. Looking at
  another cell or letting go starts over, and a block the hand cannot break gets nowhere. A
  press alone digs nothing, so the tests dig by holding (`dig_held` in
  `native/play_test.bend`). A hit on a room's mob is still the press.
- **Shift and the left button send a stack without carrying it** (`Screen.quick.at`): between
  the hotbar and the rows, into an open chest or furnace, and back out. Shift is the sneak
  bit: `Frame.key_bit` maps the runtime's codes for Shift to it and for Control to the sprint
  bit, which were on 16 and 17, codes the runtime never sends.
- **The bag is saved, beside the world.** `T` writes `B2CI:1` to the world's path plus
  `.bag` (`native/stash.bend`): the slots with their wear, the slot in hand, and every chest
  and furnace by its cell. A client starts from it when it is there. `B2CW:1` is unchanged.
- **What the screens do not do yet:** drag a stack across slots, swap with a number key,
  throw a stack out by clicking outside, craft all with Shift, wear armour, or draw the
  player in its box.

`Voxel.block_color` is indexed by the **world's** block ids (`world/world.bend`). Ids 21-29
were once in the texture atlas's order, four ids out of step, and a crafting table painted
as glass; `native/voxel_test.bend` names the colours.

### A tool is a kind and a tier, and only one block wants it

`world/inventory.bend` answers two questions about what is in hand, and they are
separate on purpose:

- **Kind** (`Inventory.tool_kind`): 0 nothing, 1 pickaxe, 2 axe, 3 shovel (a hoe is
  one for digging), 4 shears. `Inventory.suited_kind` says which kind a block
  wants: dirt, grass, sand and farmland a shovel, wood an axe, leaves shears,
  everything else a pickaxe.
- **Tier** (`Inventory.tool_tier`): 1 wooden, 2 stone, 3 iron, 4 diamond, 5
  shears. The durability is the tier's (`tool_max_durability`), so a wooden
  shovel lasts as long as a wooden pickaxe and a diamond axe as long as a diamond
  pickaxe.

`mining_duration` gives a block's row of speeds to the tool that suits it and
reads the row's hand figure for a bare hand; a tool that suits nothing is worse
than a hand (`mining_duration.mismatched`), as in vanilla. Six laws name the
kinds, tiers, durability, what each block wants and that none of them places a
block; `tests/inventory-bend.test.mjs` holds the speeds, which the checker
computes no floats for.

### Water and lava are one field that has to hold still

`world/fluids.bend` is the whole rule: a flow is water or lava at a cell with a
level that says how far that cell is from its source (8 at the source), and a tick
decides two things for each flow — where it reaches, and whether it stays.

- **A cell that is still fed keeps its own level.** A neighbour that reaches a
  cell this tick always offers a *lower* level, and taking that offer ratchets a
  whole pool down one step per tick until it drains. The old code rebuilt the
  field from the spreads alone, which is how a placed pool shrank to a puddle and
  then vanished.
- **A flow stays only while something feeds it**: a source always does, a falling
  flow does not (it moves down instead), and a flow that cannot fall needs a
  stronger flow beside it or water above it. So a pool holds while its source
  does and drains from the inside out when the source goes, which is what the
  bucket tests expect.
- **Every flow is advanced each tick.** The tick used to walk the first 64 flows
  and drop the rest; the world then cleared those cells, so any pool wider than
  the bound lost water every tick and the shape flickered. `max_flow_cells` (256)
  is the only bound, and new cells land at the end of the list, so past the cap a
  field stops spreading instead of disappearing.
- **The adapter's sample window has to include the cell above each flow.** That
  cell is what tells a flow a column landed on it; without it the rules read it
  as stone and a pool stops at the foot of a waterfall.
- The shape from one source is a 7-wide diamond, because spread is to the four
  sides and the level drops by one each step. That is the shape the rules define,
  not an accident.

Laws: `a_settled_pool_keeps_its_cells`, `an_unfed_flow_dries_up`. The shapes are
held by `tests/fluids-bend.test.mjs`, which pours a pool on a flat floor, lets it
settle, and asserts the next tick tells the world nothing.

### A native client joins the browsers' room, through a door on the server

`--join=host:port` puts the native client in a multiplayer room. It is the **same room**
the browsers are in, and its authority is still `world/multiplayer.bend`: the server has a
plain TCP port (`server/native-bridge.mjs`, opened by `scripts/play-server.mjs` on the HTTP
port plus one) that turns short ASCII lines into the JSON messages a browser sends and
back. `native/net.bend` is the lines on the Bend side and owns no socket;
`native/room.bend` owns the socket and reads it once a tick. `docs/MULTIPLAYER.md` has
the table of lines.

- **The bridge is on the server because Bend 2.0.32 cannot be a WebSocket client cheaply**:
  its sockets carry text, and it has no JSON, no SHA-1 and no HTTP. Do not write those in
  Bend to avoid ten lines of Node.
- **Playing together is keeping two edit logs the same.** The room's world is its seed and
  its log, and so is the client's. Each tick the client sends what its own tick changed
  (`Net.unheard`, one pass: `WorldState.set` either puts an entry at the head or replaces
  one in place) and sets every cell the room names (`WorldState.set_many`, then the
  collision region is rebuilt, or another player's block is in the picture and not in the
  way).
- **The socket is linear, so it rides in the loop's state.** `App<S>` takes a `Type`, so the
  window runs `Room.Session` — the client and its `Link` — and `Play.app()` is still
  the client alone, which is what the probes and tests drive.
- **The read never waits.** `TCP.poll(socket, max, 0)` answers `None` when nothing has
  arrived, `Some{""}` when the peer closed, and at most `read_most()` bytes otherwise; a
  room's whole log arrives over the ticks after the join.
- **Blocks, players, the hour and what the room simulates are shared.** The native client
  draws the room's mobs, villagers and dropped items, hits a mob, is hurt by one and picks
  an item up, and writes each player's name over its head. It draws no chest.
- **A name is in the overlay, not in the scene.** The room names a player with `J` — the
  ones already there on joining, and each who joins — and places it with its first `P`, so
  `Net.Other` carries `seen` and a player who has only joined is not drawn. `native/tag.bend`
  writes the name in the hotbar's dots, three wide and five high, capitals only, centred
  over the head's place in the frame. It is painted ahead of every face: a name shows
  through a wall, as the browser's does, is one size at any distance, and is left out when
  it would not fit whole inside the frame or the player is past 48 cells. A character the
  font does not have is a space.
- **A hit, a pickup and being hurt are the room's, asked the way a browser asks.** The dig
  key with a mob under the crosshair is `A <mob> <damage>` and leaves the block behind
  alone (`Play.tick.room`'s `guarded`); an item on the ground in reach that the bag has room for is
  `K <drop>`; the room answers a pickup with `G <item> <amount>` and a mob's blow is
  `U <amount>`. Every rule is `world/`'s: which mob the ray meets is
  `Entities.aim_step` (with `kind_is_mob`, `aim_distance` and `body_height`), the damage `Inventory.melee_damage`,
  the reach `MultiplayerMobs.melee_range`, the item `Entities.nearest_drop`, the harm
  `Player.damage`; and the room judges each from the pose it holds. The session works out
  the mob and the item **before** the client's tick, from the pose the tick starts with, and
  reads the dig edge off the keys after it, so the `Client` record did not grow a field.
  `web/aim.js` is the older copy of the aim rule and a migration target;
  `tests/entities-bend.test.mjs` holds the two to the same answers.
- **What the native client still does not do with a mob:** a sword does not wear, a kill
  earns no experience, nothing flashes or sounds, there is no bow, and a player a mob kills
  starts again at the spawn at once, bag intact, with no death screen. Add a line to the protocol and wire the rule that already exists in
  `world/`; do not grow a second rule in `native/` or in the bridge.
- **A pose is the world's coordinates as whole thousandths, signed.** Bend 2.0.32 reads and
  writes no decimal, so `Net.milli` is the number on the wire and the bridge divides by a
  thousand. A room counts a player from the world's origin and the client from its movement
  window's first cell: `Room.place_of` and `Room.stood_at` are the only two places that
  cross, by `Play.window_origin`. The client says where it is when that changed, at most
  every third tick; the room's `Multiplayer.valid_pose` and `MultiplayerMoves.step` judge
  it as they judge a browser's, and a refused move comes back as `C` and the player is put
  there (`Room.recalled`).
- **In a room the hour is the room's, and it is worked out from the time, not counted.**
  The room's day is `web/daylight.js`'s, 78.54 s, not the client's twelve minutes. The
  bridge says the angle of the day and its length (`T`, on joining and when someone calls
  the morning); `Hour.Hour` keeps the clock that was and when, and every tick reads
  `IO.now` and works out the clock now (`Sky.clock_after`). A count of ticks would fall
  behind by every late frame. Only the sun, the air and the light read the hour: the clouds
  still drift on the client's own `clock`, or they would cross the sky nine times as fast.
  `DAY_RATE` stays in `web/daylight.js`; nothing in `native/` knows how long a room's day is.
- **What the room simulates comes whole and is swapped whole.** The room broadcasts every
  mob, drop and villager five times a second. The bridge writes one line each and an `N`
  after the last; `Net.Sights` keeps the list being told apart from the one shown and swaps
  them at the `N`, so a list split across two reads is never drawn half. Nothing is blended
  between two lists, so a mob moves in steps of a fifth of a second. A thing's `kind` is
  `Body`'s: 1 to 6 a mob, 10 and its profession a villager, 1000 and its id an item. A mob
  and an item carry the room's `id`, which is what a hit and a pickup name.
- **The other players ride beside the socket, not in the client.** `Peers` (what the room has said, `Told`, and what the client has left to say, `Outbox`) is in the `Link`,
  `Net.inbox` is handed the list and answers it changed, and `session.view` hands it to
  `Play.view_among`. A `Client` is six fields, three of them records (`Avatar`, `Ground`, `Setup`), so a
  change to the player lists the player's fields and not all of the client's; `Play.player_of`, `with_bag` and
  the rest are how a test or a probe reaches one.
- **A player is painted among the faces, not over them.** The painter has no depth buffer:
  `native/body.bend` hands each side of each box to `Paint.tiles_frame_among` with how far
  its box is, and it goes into the same buckets as the blocks, ahead of them. So a wall
  hides a player behind it, and a player less than a cell behind a block can show through
  it, which is the price of a bucket per whole cell. The bodies are ranked by distance first
  and each one's boxes among themselves, so a side is never sorted against another body's.
  On the machine above eight players cost about 0.12 ms and forty mobs about 0.7 ms (`crowd`
  and `herd` in `lab/native/paint/run.sh`); none cost nothing.
- **A joined client never touches the single-player save**: it starts from the room's log
  and writes `native/client-room.b2cw`.

Five gates hold it: `native/net_test.bend` (the lines), `native/body_test.bend` (a player
read back out of a painted frame, in front of and behind a block), `native/tag_test.bend`
(the font, and a name read back out of a painted frame),
`tests/native-bridge.test.mjs` (the bridge against a real room and a real socket) and
`tests/native-join.test.mjs`, which compiles `lab/native/net/join_probe.bend` — the
client's own session code without its window — and plays a browser against it: blocks and
poses, both ways, the hour, the mobs of a room that simulates its world, an item thrown
down beside the client picked up into its bag, and five dirt taken out of a chest the
browser stocked, by a click on its screen. Verified live on one machine with the real window: server and native
client inside WSL2, the browser on Windows, for blocks; for poses, the real window against
the real server and a WebSocket player that printed the native client's poses. `native/room_test.bend` holds which mob is under the crosshair, which item is asked for,
the harm and the guarded dig. **Not played end to end:** a hit landing on a real room's
mob, and a zombie hurting a native player; the hit is held as a line the bridge turns into
the room's request, not as a mob that lost health. **Not yet
looked at in a live window:** another player walking, or a mob. The picture of one is
`shot.sh`'s `players` view, and of the mobs its `creatures` view. A server started on
the Windows side listens on `127.0.0.1` there, which WSL does not reach by default.

### Under WSLg the mouse is read from the Windows host

**Measured, not inferred.** An instrumented client printing one line per event for a
whole WSLg session received keys and clicks and exactly **one** `Look{dx=5, dy=217}`.
Every click landed at the exact centre of the window, which is where `window.c:594`
puts the pointer.

- **The display cannot deliver relative motion.** WSLg carries the window over RDP with
  FreeRDP 2.4.0, which has no relative pointer input. The X server only learns an
  absolute cursor position while the cursor is over the window, and the runtime's
  `XWarpPointer` never reaches the Windows cursor. No X-side change can fix that, and
  `window.c` is byte-identical upstream through 2.0.34, so moving the pin does not either.
- **On a real X server the runtime's grab is correct.** `bash
  lab/native/pointer/census-xvfb.sh` moves the pointer by eight relative steps of ten
  pixels and the census prints eight `Look{10 0}`, one per frame. A `Look` is a delta.
- **So `Frame.fold_turn` sums deltas.** An earlier fold differenced each `Look` against
  the previous offset, on the theory that WSLg reported positions; that reads a steady
  sweep on a working display as a still mouse. Do not bring it back.

`native/pointer.bend` is the look under WSL. `host_open` starts
`native/pointer-host.ps1` through WSL interop; the script holds the Windows cursor at the
centre of the client's window while that window is in front and the cursor is inside it,
and writes each displacement as a `dx dy` line. `host_read` returns the complete lines
since the last frame, `Pointer.delta` sums them in Bend, and `Pointer.events` hands the
fold one `Look` in place of the display's own pointer events. `native/pointer.c` is a pipe
and a child process and nothing else. Outside WSL, or when the script is not at
`native/pointer-host.ps1` relative to the working directory, `host_open` answers `0` and
the client keeps the runtime's grab. The client prints which one it chose.

Two probes hold this, and neither is in the gate because both need a display:

- `bash lab/native/pointer/look-probe.sh display` runs the client's own tick under Xvfb on
  the runtime's grab and moves the pointer by 80 px and back: the yaw goes 0 to 0.0960 rad
  and returns to 0.
- `lab\native\pointer\host-probe.ps1`, run from Windows, does the same through the host
  script with the real cursor: `pointer=host`, the cursor pulled back to the centre on 16
  of 16 steps, and the same yaw.

**Not yet measured in a live WSLg window:** that the window's Windows title starts with
`Bend2Craft native` (the host script matches on that prefix; WSLg appends the distro name)
and that the grab's blank cursor hides the Windows cursor. Measure both before writing
either down as true.

The arrow keys still turn the camera at `Frame.turn_rate` 1.6 rad/s for yaw and
`Frame.tilt_rate` 0.8 for pitch, applied in `Frame.ready_holding` so both looks add. The
codes are the runtime's own translation of the arrow keysyms (`window.c:507`:
63232/63233/63234/63235), not raw X keycodes. Holding both keys of an axis is `0`, not a
sum.

Every input bug in this client had one root cause: **assuming what the runtime or the
display does instead of measuring it.** Instrument and read the numbers first.

### A foreign effect is a `def` with two imports

`def name(args) -> IO(R):` whose body is `import "./x.c"` and `import "./x.js"` is an
effect the program owns; `vendor/bend/guide/EFFECTS.md` is the contract and
`native/pointer.bend` is the example here. The C is spliced into the program after the
runtime, registers itself with `io_eff(CID(name), run, 0)`, and may guard a def the
program does not use with `#ifdef CID(name)`. The compiler links only `-lX11` and
`-lasound`, chosen from the includes, so an effect cannot add a library. A user handle
type is not available, so per-process state is a C static. Keep the rule in Bend and the
bytes in C: the effect returns text or words, and a Bend `def` with a test decides what
they mean.

## Laws

`world/LAWS.bend` states 114 laws and `world/PROOF.bend` closes every one; `npm run proof`
prints `ALL PROOFS CHECK` in about nine seconds. There are two kinds, and the difference
matters:

- **A law with a `for` holds for every value of what it names** — every log, every bag,
  every coordinate. There are 31. The ones the game leans on: an edit reads back from any
  log (`an_edit_reads_back`); an edit changes no other cell (`an_edit_keeps_every_other_cell`);
  a refused mining or placing returns the bag it was given (`a_refused_mining_keeps_the_bag`,
  `a_refused_placing_keeps_the_bag`); mining, placing, adding and removing never change how
  many slots a bag has; the terrain rule answers air at and above a column's height.
- **A law without one is a value**, computed by the checker from the same definition the
  game runs: a block id, a recipe, what a pickaxe breaks, the default seed's terrain at a
  cell. There are 64. They say the table is what the game depends on; they do not say the
  rule is right for inputs nobody listed.

Do not call a law universal because it is in `LAWS.bend`. Say which kind it is.

What the checker decides is integers, booleans, naturals and lists. It computes no floats,
so the player's physics and the renderer are held by tests, not laws. A `U32` operation on
a **variable** does not reduce — a word is 32 booleans and the checker will not case on
them — so a universal law is about structure (`Nat`, `Bool`, a list's shape, which branch
a refusal takes) and treats `U32` arithmetic as opaque. A **closed** `Nat` is counted out
in unary: `94371840n` in a law is a stack overflow, so say a large number as a `U32`.

Three moves prove almost every universal law here, and `PROOF.bend` opens with them:

- **A computed condition cannot be matched**, so the lemma takes it as a parameter
  (`valid: Bool`) and is called with the condition. When a case needs to know *which*
  condition it was, the lemma also takes `{condition == valid}` and is called with `{==}`.
- **`%e : P` rewrites the goal with `e : {a == b}`**: `P` is the goal with `_` where `b`
  stands, and the goal becomes `P` with `a` there. So to turn an `x` in the goal into `y`
  you need `{y == x}`, which is `Equal.sym` of the lemma as it is usually stated. Rewrites
  apply in the order written, each to the goal the one before it left.
- **An impossible case holds `{True{} == False{}}`**, which `is_true` turns into `Empty`,
  and `Empty.absurd` into whatever the case wanted.

And three rules of the checker that cost a failed proof to find:

- **Matches follow binder order.** A proof may not match a later parameter and then an
  earlier one, and may not match anything after a rewrite. Order the lemma's parameters
  the way they are matched, and put what must be reduced after a rewrite in its own lemma.
- **An induction hypothesis that is needed twice is a `+` parameter**, as is any
  hypothesis: `+hm: {...}`.
- **A lemma's arguments are written out**, the erased ones too. When the argument is a
  long expression the definition spells with `let`s, give it a `def` in `PROOF.bend`
  (`existing_added`, `inside_column`) rather than pasting it twice.

Add a law when a rule is one the game leans on and the checker can decide it; prove it
before the commit. A law with no proof is an open claim and fails the gate, and a law
that had to be weakened to pass says so in its own comment.

## Toolchain

- Bend 2 is pinned as the `vendor/bend` submodule.
- On Windows, run the toolchain inside WSL. On macOS and Linux it runs natively; keep scripts portable to the bash 3.2 that macOS ships, so no bash 4+ builtin (`declare -A`, `mapfile`, `readarray`) and no Linux-only binary such as `setsid`.
- Bun is preferred from `.tools/bun/bin/bun`; `scripts/run-bun.sh` selects it automatically.
- The native CLI lives in the ignored `.tools/bend-local/`, built once by `scripts/bootstrap-native-bend.sh`. It refuses to overwrite an existing compiler, so delete that directory deliberately if a rebuild is what you mean.
- `vendor/bend` is upstream code. Do not edit it for application features.

## Required checks

Run at the repository root, from WSL on Windows and from a normal shell on macOS
or Linux:

```bash
npm run verify       # all Bend, proof, test, build and diff checks
npm run check:bend   # focused Bend checker
npm run proof        # focused law/proof check
npm run test         # world, inventory and game-state regressions, then the native Bend regressions
npm run build        # static browser bundle
```

`npm run test` runs the `native/*_test.bend` regressions in a throwaway working
directory under `scratchpad/`, because the native tests write save files
relative to it.

A shell script written from the Windows side goes in a file. A heredoc whose body has an
apostrophe in it does not survive the trip into WSL, and a `$variable` in an inline
`wsl.exe ... bash -c` is expanded to nothing before bash sees it.

For browser behavior, run `npm run browser:smoke` when a local Playwright browser binary is available, then validate the canvas at `http://localhost:3000/`. Use `npm run smoke:dev` for a bounded server/readiness check. Test movement, collision, inventory selection, block removal/placement, and tree rendering when those features exist.

To play, run `Jogar-Bend2Craft.bat` on Windows or `Play-Bend2Craft.command` on
macOS: it rebuilds the bundle in WSL and serves `dist/` on port 8080.

For the native client, compile and run it inside WSL with WSLg, from the repository
root: the save and the host pointer script are both found relative to the working
directory. The runtime's default thread pool is the right one (see the frame budget
above):

```bash
.tools/bend-local/bin/bend native/client.bend -o .tools/bend-local/bin/bend2craft-client
.tools/bend-local/bin/bend2craft-client --size=1024
```

`bash scripts/play-native.sh --size=1024` does both: it compiles the client when a
`.bend` or `.c` under `native/` or `world/` is newer than the binary, and runs it from
the repository root whatever directory it was called from.

## Bend 2 authoring rules (established against 2.0.32; the pin is now 2.0.35 and the gate passes, but these were not re-measured)

These were established by experiment against the pinned compiler. They are not
obvious from the guide and each one costs a failed check to rediscover, so keep
new `world/`, `native/` and test code consistent with them.

- **No forward references.** A `def` must be written before any `def` that calls
  it. Calling a later definition is reported as "expected: a filled definition
  (an unfilled law is a dead claim)". A helper cycle is therefore impossible;
  only direct self-recursion is available.
- **`do` blocks take binds and one final term.** No tuple-destructuring
  statement (`(a, b) = pair`), no `match`, no bare constructor and no two
  consecutive actions. Return a built value with `return <value>`; hand a bound
  pair to a helper that destructures it in a plain `def`.
- **A `match` scrutinizes a parameter or a field only.** Not a computed value,
  not a local binder, not a closure binder and not an affine (`+`) parameter. To
  branch on a computed result, pass it to a `def` whose parameter is matched.
  A destructuring `K{a, b} = f(x)` is a match and is refused the same way.
- **A self-call must shrink.** The checker reads the arguments left to right and
  wants each passed unchanged until one is smaller, so `f(1n+r, ..)` calling
  `f(Nat.add(1n, r), ..)` is refused. With no forward references, a def that has
  to hand a computed record back to itself takes it as a parameter: give the
  argument a sum type with one constructor per stage and spend one unit of fuel
  per stage. `Paint.node` is the example.
- **A `1n+r` binder read twice needs a `+` parameter.** `def f(+k: Nat)`, or the
  second read of `r` is "consumed more than once".
- **Constructor names are global.** A `type` in any module may not reuse a
  constructor Base declares (`SNil`, `SCon`, `Done`, `Fail`, ...).
- **Every value is consumed once.** A `U32` local, a data record and a frame all
  support exactly one use, so a room or frame cannot be read and then stored.
  Thread linear state through records and recompute what a second use needs.
- **Products are binary.** Use `A & B`; there is no `A & B & C`. Give multi-field
  state a `type ... is Type` record instead of a tuple.
- **A generic type argument cannot be a product.** `def f(-A: Type, ...)` may be
  instantiated with `Socket` or a record, but not with `Socket & String`; give
  that shape its own failure helper.
- **Patterns list every field** of the constructor (`Record{a, b, c}`), and a
  `case` body is a single term. Adding a field to a record is a change to every
  construction and every pattern of it, in the tests too. The names in a pattern
  bind **positionally**, so their order must match the declaration's order: a
  pattern that lists all the fields but lists them in another order compiles,
  type-checks and silently returns the wrong field.
- **Match usage annotations to the producer.** A value typed `Maybe<&2, T>` must
  be received as `Maybe<&2, T>`.
- **A template parameter (`~f`) comes first** in the parameter list, or the def is
  refused with "only leading binders take ~".
- **A def may not be named like an imported module's.** In a file that imports
  `./face.bend as Face`, `def face.corners` is refused as a duplicate of `Face.corners`.
- **Destructuring follows binder order too.** `K{a} = second` before `K{b} = first` is
  refused the same way a match out of order is.

## Implementation rules

- Keep world generation pure and typed in Bend.
- Keep chunk generation and bulk block materialization in Bend. The browser must call a bulk Bend chunk export, then only cache, stream and render the returned data; never loop over `World.block` once per cell for normal chunk loading. Benchmark chunk bootstrap when changing this boundary.
- Keep browser adapters dependency-free and tested, but keep authoritative inventory/crafting rules in Bend 2 as they migrate.
- Reach a `world/*.bend` module only through `web/bend-modules.js`. It is the
  single place that knows how the JS lane spells a datatype, so a second path
  around it reintroduces the bug it exists to prevent.
- A Bend `Nat` cannot be negative and the 2.0.32 JS lane refuses one, so a cell
  or chunk below the origin is spelled by `cellNat`/`chunkNat` on the way in and
  read back the same way. Never spell a cell twice: a double fold addresses a
  cell nothing else names. `tests/inventory.test.mjs` pins the offset.
- Keep all repository-authored source comments, UI copy, tests, plans and documentation in English.
- Add a failing test before changing behavior, then run the focused test, implement the smallest fix, and run the full checks.
- For a bug fix, keep the regression at the failing contract seam and add a browser smoke assertion when the symptom crosses into WebGL or input handling.
- Do not expand adjacent block/item contracts while fixing one behavior without a focused test and an explicit scope justification in the final report.
- Treat delegated changes as untrusted until the parent reviews their diff and reruns the affected focused checks plus `npm run verify`.
- Keep block IDs and their meanings synchronized through one explicit contract. Current IDs are documented in `world/world.bend` and `web/inventory.js`.
- Preserve affine/termination guarantees in Bend. Do not use `@unsafe` to hide a failed proof.
- Prefer focused changes over broad refactors. Do not add a dependency when WebGL or the existing runtime is enough.
- When moving a file, move its callers with it in the same change: every `import`,
  every shell script path, every `scripts/test-suite.sh` entry and every prose
  reference. Then run `npm run verify`, which is what catches the ones missed.
- Never commit credentials, generated `dist/`, `.tools/`, or local caches.

## GitHub

The origin is `https://github.com/lennix1337/bend2craft.git`. Always use the `lennix1337` GitHub account in this repository (`gh auth switch --user lennix1337`); never use any other authenticated account here. Do not force-push, merge, release, or change repository settings without explicit authorization. Before pushing, run the checks above and inspect `git status` and `git diff`.
