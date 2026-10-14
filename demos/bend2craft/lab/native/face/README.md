# Native visible-face probe

This probe compares the per-pixel ray renderer in
`lab/native/voxel/voxel.bend` with a visible-face renderer. Both use the
same camera rays, palette, per-face tint and quadtree image shape.

**The agreement fix now produces identical block and face IDs for every pixel in
the pinned seed-1337 view at 32², 64² and 128².** The cost is substantial: with
the selected 8-pixel tile edge, 128² takes 46.375 ms at one thread and 19.500 ms
at eight threads, so it no longer meets a 16.7 ms budget. An edge-16 experiment
measures 13.875 ms at 128²/eight threads, but is slower at one thread; the
production default remains edge 8 pending a target-thread choice.

## Pipeline and pixel correctness

1. `faces_from_chunk` walks all 5,120 cells in y/z/x order and emits every
   exposed face. Neighbor values come from carried rows, not per-cell lookups.
   `render_faces_at_with_tile_size` takes that list from the caller, so a client
   that extracts once and then only renders is not paying for a world that did
   not move.
2. `bucket_faces` projects the four face corners to a conservative screen box
   and inserts each face into every overlapping tile. The box is stored packed,
   `low = x0 | y0 << 16` and `high = x1 | y1 << 16`, because the per-pixel walk
   is the whole frame and two unsigned compares on the packed words decide the
   box where four compares on four numbers used to. If a face crosses the
   near plane, its candidate box covers the frame; wholly-behind faces are
   discarded. Screen-coordinate conversion is clamped before integer conversion.
3. At each pixel, the renderer builds the same normalized ray as the reference,
   intersects every candidate face plane, and compares the per-pixel ray
   distance. A candidate owns the pixel only when the hit point lies within the
   face's unit square. This world-space plane/quad test is equivalent to a
   point-in-projected-quad test, without a screen-edge winding convention.

The conservative near-plane box can add candidates, but it cannot add visible
pixels: the ray/plane intersection and unit-square test remain authoritative.
An exactly parallel ray has no plane hit (`abs(direction) <= 0.00001`); a hit
must be farther than `0.0001`. The local quad test allows `0.00001` world-space
tolerance for floating-point boundary comparisons.

The focused test covers a single-block silhouette, a parallel/edge-on face, a
face crossing the near plane, a subpixel face between pixel sample centres, and
a camera inside a solid block. It also checks front/back/away views, exact face
extraction masks, and every cell in the real chunk. The extraction scan reports
**1,298 emitted, 1,298 expected, zero mismatches**.

## Agreement gate

On `World.chunk(1337n, 0n, 0n)` at eye `(8, 14, 0.5)`, yaw `0.7`, pitch `0.30`,
the regression compares every pixel's block and face against the ray renderer.
`wrong_block` counts different blocks when both renderers hit a block;
`only_face` counts a face-renderer block where the ray sees sky; `only_ray` is the
opposite. `block_diff` includes all block-visibility or block-identity
disagreements, and `face_only` is a same-block/different-face result.

The test fails if `wrong_block`, `only_face`, or total `block_diff` exceeds 1%
of frame pixels, and pins `only_ray=0`. This is a ceiling, not an acceptable
measured error rate: the three tested frames currently have **0% wrong-block,
0% spurious-block, and 0% total block disagreement**.

| size | pixels | same | both empty | face only | block diff | only face | only ray | wrong block |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 32² | 1,024 | 1,024 | 553 | 0 | 0 | 0 | 0 | 0 |
| 64² | 4,096 | 4,096 | 2,219 | 0 | 0 | 0 | 0 | 0 |
| 128² | 16,384 | 16,384 | 8,889 | 0 | 0 | 0 | 0 | 0 |

`same` includes both-empty pixels; `same + face_only + block_diff` equals the
frame pixel count. Zero disagreement is established only for this fixed chunk,
camera and tested sizes. The 1% gate leaves a bounded allowance for future
floating-point boundary cases; arbitrary chunks and camera poses are not proven
by this fixture.

## Reproduce

```bash
bash lab/native/face/run.sh
```

The harness requires Bend 2.0.32 and a native C compiler. It runs correctness
checks with `--gpu off` at `--threads 1` and `8` before collecting seven timing
samples per phase. Timings are milliseconds per call, shown as median and
minimum–maximum range. Measurements below are from WSL2 x86_64, AMD Ryzen 7
9800X3D (8 cores visible), Ubuntu clang 21.1.8.

## Full-frame measurements

The selected production path is scatter bucketing with `tile_size() = 8`. A
frame includes chunk generation, extraction, projection/bucketing, image
generation and fingerprinting. All frame sizes below were measured with seven
samples at both thread counts.

| threads | size | face frame ms |
| --- | ---: | ---: |
| 1 | 32² | 7.188 [6.875, 7.438] |
| 1 | 64² | 14.438 [13.938, 14.875] |
| 1 | 128² | 46.375 [45.875, 47.375] |
| 1 | 256² | 222.500 [218.250, 227.250] |
| 8 | 32² | 4.000 [3.875, 4.188] |
| 8 | 64² | 6.625 [6.562, 6.938] |
| 8 | 128² | 19.500 [18.750, 19.875] |
| 8 | 256² | 97.750 [96.500, 99.250] |

For context, the reference ray renderer measured 21.812 [21.125, 22.688],
54.812 [52.812, 55.625], and 184.125 [179.625, 186.500] ms at sizes 32²,
64², and 128² with one thread. At eight threads it measured 16.938
[16.500, 17.062], 32.438 [32.000, 33.188], and 95.250 [94.750, 96.250] ms.

| threads | size | prep ms | extract ms | project ms |
| --- | ---: | ---: | ---: | ---: |
| 1 | 32² | 2.188 [2.062, 2.250] | 1.312 [1.266, 1.328] | 0.578 [0.547, 0.609] |
| 1 | 64² | 3.375 [3.188, 3.750] | 1.297 [1.250, 1.312] | 1.891 [1.797, 1.922] |
| 1 | 128² | 11.500 [10.750, 12.625] | 1.281 [1.266, 1.359] | 9.375 [9.203, 9.609] |
| 8 | 32² | 2.125 [2.000, 2.500] | 1.297 [1.250, 1.391] | 0.578 [0.562, 0.609] |
| 8 | 64² | 3.375 [3.312, 3.562] | 1.297 [1.266, 1.375] | 1.844 [1.797, 1.922] |
| 8 | 128² | 11.125 [11.000, 11.500] | 1.312 [1.266, 1.375] | 9.484 [9.188, 9.641] |

`extract` includes chunk generation and face extraction. `project` reuses an
extracted list and includes projection, bucketing and a full candidate digest.
The near-plane fallback accounts for additional candidates in this camera view;
the exact pixel test also performs more work per candidate than the former
scalar-depth box test.

## Tile and bucket measurements

The table compares scatter tile edges at 128². Candidate count is charged once
for each pixel in a tile. Edge 16 is a measured option, not the configured
default.

| edge | candidates | candidates/pixel | project, 1 thread | frame, 1 thread | project, 8 threads | frame, 8 threads |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 796,736 | 48.629 | 9.359 [9.234, 9.656] | 46.250 [45.000, 48.000] | 9.562 [9.453, 10.156] | 19.500 [19.375, 19.750] |
| 16 | 1,123,072 | 68.546 | 1.859 [1.812, 1.938] | 47.500 [46.875, 48.375] | 1.875 [1.844, 2.047] | 13.875 [13.625, 14.375] |
| 32 | 2,188,288 | 133.562 | 0.609 [0.578, 0.609] | 86.375 [84.500, 89.250] | 0.609 [0.578, 0.688] | 21.625 [21.500, 22.375] |

The whole-frame edge-8 timing in the previous table comes from the independent
frame benchmark; the tile comparison uses the tuning benchmark. They agree
within sampling variation. Edge 16 reduces scatter-build cost enough to win at
128²/eight threads, despite increasing candidate count, and is the only measured
configuration here that fits 16.7 ms at that size. It loses at one thread and
is not changed as the default in this visual-correctness task.

At edge 8, source-level bucket list-cell counts (not allocator/GC metadata) are:

| size | direct scatter grid | row-major grid | projected screen list | row-major total |
| --- | ---: | ---: | ---: | ---: |
| 32² | 13,664 | 2,150 | 1,298 | 3,448 |
| 64² | 46,719 | 4,456 | 1,298 | 5,754 |
| 128² | 234,161 | 12,721 | 1,298 | 14,019 |

Row-major uses fewer list cells but its tile-by-face containment scans remain a
measured alternative; scatter remains the selected builder.

## What the per-pixel walk actually costs

The tables above are one chunk at one camera. The client renders a 2x2 chunk
region from inside a village, and the cost model there is different enough to
be worth stating on its own. Measured at the client's own spawn camera, 64x64,
edge 16, native C, eight threads, seven samples:

| term | steps | note |
| --- | ---: | --- |
| faces in the region | 1,654 | 2x2 chunks, 20,480 cells |
| candidates the walk visits | 695,808 | 170 per pixel |
| same at edge 8 | 488,640 | 119 per pixel |
| same at edge 2 | 400,128 | 98 per pixel |
| live pixels the boxes cover | 390,799 | 236 per face, 5.8% of the frame |
| same at focal scale 24 | 666,624 | 96x the focal length, 4% fewer steps |

Three things follow, and each one closed off an option that had looked open.

**Rasterising loses on allocation count, not on step count.** It needs 390,799
steps against the walk's 695,808, so it wins on count by 1.78x — the ratio being
the tile quantisation, a box that straddles a tile boundary being placed in up
to four tiles. It loses because its depth test is against a persistent quadtree,
and each test rebuilds a six-level path: about 2.3M node allocations per frame
against the 5,461 the frame allocates today. For it to win, its per-pair cost
would have to come in under 1.78 x 25 ns = 44.5 ns, and the 1.78 is the whole
margin.

An earlier version of this table put the rasteriser figure at 3,094,159 and
concluded the walk won by 4.4x. The fold was summing the dead faces, whose
clipped box has `x0 > x1`, so the width underflowed and one term wrapped the
total. `frame_bench`'s `clip_area` now skips them on the liveness flag, which is
the only way to sum a box whose corners are inverted. The corrected figure has an
independent check: at edge 2 a tile is 2x2 pixels, so a face's placements
approach its covered pixels one for one, and edge 2 measures 400,128 against
390,799 — 2.4% apart, where the old figure was 7.9x out.

**The field of view is not a lever.** A face's projected box scales with the
focal length, and the walk's step count is the sum of the boxes, so a wider or
narrower view should change the frame. It does not: 96x of focal length moves the
count by 4.4%, because the faces near this camera are small enough that shrinking
them shrinks tiles they already fit inside rather than the number of tiles they
occupy. There is no frame rate in the field of view, and so no reason to change
what the player sees.

**The tile edge is set by the builder, not the walk.** The walk is cheaper at a
smaller edge and the scatter builder is dearer, and only the walk is parallel.
The builder's cost is `2 * across * placements` list steps, because a placement
costs two `List.set` calls and `List.set` is linear in the grid's width: 21,744
steps at edge 16, 134,976 at edge 8. Edge 8 measured 9.50 ms of render against
7.75 at edge 16 — the walk saves 4.0 ms and the builder spends 2.5 ms of it
back.

The alternative builder is measured too, not just modelled. Row-major fills one
tile row at a time, so every placement is a cons and the grid is never indexed at
random — the thing that makes the scatter builder dear. In exchange it tests every
face's box once per row, so its cost is `across` box tests per face plus a cons per
placement. The prediction was that this is cheaper, because the walk's saving at
edge 8 is larger than the scatter builder's penalty, and the measurement is that it
is not: 2.90 ms for the scatter builder at edge 16, 3.00 for row-major at edge 16,
and 5.15 for row-major at edge 8, all building the grid inside the timed loop so the
three are like for like.

The model was wrong by a factor of about eight on the row-major term, and the reason
is worth keeping: it counted "one visit per face per row" as one step, and a visit is
a `project_screens` field read, two integer divisions by the edge, a `place` call and
its `match`. **A builder's cost is not its placement count; it is its placement count
times the work of reaching a placement.** The scatter builder reaches a placement in a
short walk and the row-major builder reaches it by re-deciding it, and the second is
dearer however few list steps it spends.

**The walk is the runtime's list step, not the arithmetic.** Four walks over the
same 695,808 candidates, timed by `native/client-probe` at 64x64, edge 16, eight
threads, seven samples:

| phase | what the reject path does | ms | ns per candidate |
| --- | --- | ---: | ---: |
| `bare` | one cons cell and a tail call, nothing else | 16.05 | 23.1 |
| `step` | the same, plus the seven-field destructure | 16.00 | 23.0 |
| `pixel` | the shipped walk: split box test, two calls | 18.20 | 26.2 |
| `one` | the box test folded into one `Bool.and`, one call | 18.40 | 26.5 |

Three things fall out of that table, and each one closes an option.

**There is nothing left to win in the walk's body.** The bare iteration is 88%
of it. The whole of the box test, the branch and the call structure is 2.2 ms of
18.2, and the runtime's cons-cell step is the other 16.

**Splitting `Screen` to avoid the destructure would gain nothing.** `bare` and
`step` are within noise of each other, and `step` is the one that reads all seven
record fields, because a pattern must list every field of a constructor. The five
the walk never reads are free. That was the last idea for the step cost, and it is
now measured dead rather than argued.

**The split box test is kept, and the folded one buys nothing.** Collapsing the two
halves into one `Bool.and` does make the reject path a single call instead of two,
and it measures the same: 18.40, 18.30 and 18.25 ms against the shipped walk's 18.20,
18.15 and 18.25 over three runs. The saving is real in dispatch count and lost in the
second compare, which is then paid on every candidate instead of only on the ones the
first admits. There is no case for churning a measured path, so the shipped walk keeps
the split. `face_probe_test` holds the two shapes to the same answer on every pixel of
a real grid, so the comparison is a measurement and not an opinion.

## Budget verdict and limits

- With the configured edge 8, **128² does not fit 16.7 ms** at one or eight
  threads. The largest measured size meeting that budget at both thread counts
  is 64². The measured edge-16/eight-thread option fits 128² at 13.875 ms.
- At 33.3 ms, configured edge 8 supports 128² at eight threads but not at one;
  256² exceeds the budget at both thread counts.
- The agreement gate is verified only for one generated chunk and one camera
  pose. This remains a single-chunk opaque renderer with no streaming,
  transparency, texture, or lighting model. Near-plane-crossing faces use a
  conservative full-frame candidate box, so other camera poses may have
  different performance even though exact per-pixel coverage is retained. At the
  client's own camera those faces are most of the walk: 98 candidates per pixel
  survive at edge 2, where a bucket holds only the faces whose box contains the
  pixel, so the floor is set by the near-plane fallback rather than by the tile
  size.
