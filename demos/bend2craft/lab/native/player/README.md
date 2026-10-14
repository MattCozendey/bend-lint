# Native player collision-region probe

This probe owns the collision region the native client hands to `Player.step`.
A region is one box of cells, so crossing a chunk boundary used to mean walking
into the edge of the one chunk it covered: `Player.collides` treats every cell
outside the region as solid, and the region was built from exactly one bulk
`WorldState.chunk` call. `checked_from_world_state` now composes a
`columns` × `rows` grid of bulk chunk exports into one region, and the guard
below refuses a grid the storage encoding cannot name instead of addressing a
world cell nothing else reads.

## The contract

- `checked_from_world_state(seed, chunk_x, chunk_z, columns, rows, edits) ->
  Maybe<&1, Region>` is the client entry point. `(chunk_x, chunk_z)` is the
  region's minimum corner, so the player starts one chunk inside the region and
  has `columns - 1` chunks of room on `+x` and `+z`. It is `None` when the grid
  is empty, larger than 16 chunks, sits on a stored cell at or above
  `negative_origin()/2`, or runs past the `[-32768, 32768]` movement window.
- `from_bulk(chunk, chunk_x, chunk_z) -> Region` and
  `from_world_state(seed, chunk_x, chunk_z, edits) -> Region` keep their
  signatures and still build a one-chunk region. A single bulk export already
  sits in the region's cell order, so that path copies no cell; it is split into
  y-planes on the way in, which copies no cell either.
- `step(state, keys, dt, region, spawn_x, spawn_z, spawn_height) ->
  Player.State` is unchanged, and `checked_step` is the same tick behind the
  guard: a player outside the encoded window or below the world floor is refused
  rather than floored into a cell the region never named.
- `checked_create_player(world_x, world_z, spawn_height) -> Maybe<&1,
  Player.State>` is the guarded spawn; `create_player` is unchanged.
- `region_is_refused` / `player_is_refused` are the refusal predicates the
  focused test uses.

Grid materialization is bulk end to end: one `WorldState.chunk` call per chunk
(which applies the edit log itself) and one cell copy per cell into a region
array, then one array-to-list conversion. `World.block` is never called per
cell. A chunk export is read once in its own cell order, so the copy is a
forward walk; the target index is `x + width * (z + depth * y)`, the order
`Player.region_block` reads. The flat list is then cut into y-planes of
`width * depth` cells, which is the shape `Player.region_block` indexes: `plane_at`
for the height, `list_at` for the cell within the plane.

## The storage guard

`domain_cell` folds a stored world cell onto the movement window as
`stored cell + 32768`, which is lossy: stored cell 94400000 decodes to the same
player cell (32768) as stored cell 0, and stored cell 47185920 saturates onto
world cell -32768. The guard is therefore two predicates, not one:

- `player_cell_is_sound(stored_cell)` — canonical storage
  (`stored < negative_origin()`) and inside the window.
- `chunk_grid_is_sound(chunk, chunks)` — a chunk coordinate is never negative,
  so its stored cell must stay below `negative_origin()/2` and the whole span of
  `chunks` chunks must fit the window.

`verify_storage_guard` pins both aliases and then pins that each of them, a grid
that runs past the window, a player cell outside the window, and a player
position below the floor are all refused, while a sound grid and a sound player
cell are not.

## Running it

From the repository root, in WSL on Windows or a native Linux/macOS shell:

```bash
# focused test only
.tools/bend-local/bin/bend lab/native/player/player_test.bend -o scratchpad/player-probe/player_probe_test
scratchpad/player-probe/player_probe_test --threads 1 --gpu off

# test, then seven timed samples of every phase
bash lab/native/player/run-bench.sh
```

The script uses `.tools/bend-local/bin/bend` (or `BEND_BIN`) and requires
`bend 2.0.32`, prints the platform, runs the test with `--threads 1 --gpu off`,
then takes seven samples of each phase and reports its median and range. All
timing is native single-thread CPU, not a WebGL/GPU or multithread number.

## Measurements

Platform: WSL2 x86_64 on an AMD Ryzen 7 9800X3D, Bend 2.0.32, native C target,
`--threads 1 --gpu off`, seven samples of one `run-bench.sh` invocation. One
untimed warmup pass over every phase runs first, so these are steady state.
Medians with the range over the seven samples:

| phase | what it times | median ms | range ms | per tick |
| --- | --- | --- | --- | --- |
| `one_chunk_every_tick` | 1 bulk chunk + 1-chunk region + 32 ticks (the recorded baseline) | 12 | 12–13 | 0.38 ms |
| `one_chunk_cached` | 32 ticks against a one-chunk region | 0 | 0–1 | 0.02 ms |
| `four_chunk_frame` | 4 bulk chunks + 2×2 region + 32 ticks | 2 | 2–2 | 0.06 ms |
| `four_chunk_materialize` | 4 bulk chunks + 2×2 region, no ticks | 2 | 1–2 | — |

`one_chunk_every_tick` is the phase the client plan recorded as
`world_state_chunk_to_player_step`, so the two numbers are comparable.

The multi-chunk frame used to cost 31 ms for the same 32 ticks against 7 ms for the
one-chunk path, and only 2 ms of that was materialization. The rest was the tick
itself, and it was the index rather than the work: `Player.region_block` read a cell
out of a flat `List<&2, U32>` of the whole region by walking to the cell's index, so
a lookup cost the cell's position, a 32×20×32 region was four times as long as a
16×20×16 one, and every collision probe paid for it. Four times the cells gave four
times the cost at the same number of lookups.

The region is now one list of y-planes, each holding `width * depth` cells in the
region's own cell order, and a lookup is `plane_at` then `list_at`. That is
`height + width * depth` in the worst case and about `height / 2 + width * depth / 2`
in practice — 522 cells against 6,272 for the flat walk on the 2×2 region — and
`four_chunk_frame` fell from 31 ms to 2 ms, 16 times off the tick. A lookup outside
the region got cheaper too, because it runs off the end of twenty planes and finds an
empty one where the flat walk ran off the end of 20,480 cells.

`one_chunk_every_tick` is now dominated by the bulk chunk export the tick re-reads,
not by the collision probes, which is why the recorded baseline moved 16 ms to 12 ms
rather than to 2.

## Limits

- The region is a box anchored at `(chunk_x, chunk_z)`, so the player has room
  on `+x` and `+z` and immediately hits the region edge walking `-x` or `-z`.
  A client has to re-anchor the grid when the player approaches that edge; no
  re-anchoring or streaming rule exists yet.
- The grid is bounded at 16 chunks (81920 cells) so a mistyped size cannot ask
  for an unbounded allocation. A 3×3 grid around an interior player is
  supported by the same contract but is not measured here.
- Chunk coordinates are `Nat`, so `WorldState.chunk` can only export
  non-negative world cells. Negative world cells exist in the storage encoding
  and `player_cell_is_sound` accepts them for a player, but no bulk export
  covers them yet.
- The seam tests flatten their own corridor with edits, so they pin the
  boundary's arithmetic, not terrain traversal. Generated terrain, trees and
  structures along a seam are not part of this contract.
- The probe has no window, no input loop and no render; it is the collision and
  materialization boundary only.
