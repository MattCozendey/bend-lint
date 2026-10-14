# Native voxel Image probe

This probe proves a bounded 32×32 perspective voxel `Image` from the bulk
`World.chunk(1337n, 0n, 0n)` result. Each pixel ray uses a camera basis and a
3D grid DDA; the first non-air cell is opaque. The focused binary test pins two
camera-yaw fingerprints, checks that a near block wins over a farther block
along the same ray, and pins that moving or turning a position-aware camera
changes specific pixel colors while an eye outside the chunk still produces a
defined sky frame. The flat bulk array is materialized once as shared nested
y/z/x lists; each cell lookup traverses at most 20 + 16 + 16 list entries.

The renderer is position-aware through one pure typed camera:

- `Camera.look(eye, yaw, pitch) -> Camera` is the only basis; the eye is data
  on the camera, so any frame position is a value, not a code path.
- `Camera.at(yaw)` keeps the probe's pinned frame — the eye at
  `Vec{8.0, 14.0, 0.5}` and pitch 0.30 — so the two golden 32×32 fingerprints
  are byte-identical before and after the refactor.
- `render_view(grid, camera)` and `render_at(chunk, eye, yaw, pitch)` render
  the pinned 32×32 size; `render_size(grid, camera, depth)` and
  `render_size_at(chunk, eye, yaw, pitch, depth)` render any 2^depth frame
  (depth 5 = 32, 6 = 64, 7 = 128). `projection_half(depth)` keeps one field of
  view across sizes by pairing the half-width with a 1.5× focal length.
- `voxel_probe_parallel.bend` is the same renderer behind a parallel entry
  point: `render_size_at_parallel`, `render_at_parallel` and friends are the
  single-thread functions above with a bang on the image call. The quadtree
  recursion already forks its four quadrants, so nothing about the pixels
  changes and the forked frame is the single-thread frame byte for byte.

Run from the repository root in WSL on Windows, or a native Linux/macOS shell:

```bash
bash lab/native/voxel/run.sh
bash lab/native/voxel/run-parallel.sh
```

The script uses `.tools/bend-local/bin/bend` by default or `BEND_BIN` when set.
It clears stale binaries, compiles the test and the frame benchmark to ignored
`scratchpad/voxel-probe/`, runs the native test with `--threads 1 --gpu off`,
then takes seven timed samples of the benchmark and reports the median and range
of every timed phase. All timing is a native single-thread CPU measurement, not
a WebGL/GPU or multithread number.

`run-parallel.sh` is the same harness shape for the parallel lane: it also
builds and runs `voxel_probe_parallel_test.bend` at every measured thread count
before it collects any timing, then sweeps `--threads` over `1 4 8 16` (override
with `THREAD_COUNTS`) with `--gpu off` throughout.

## The full-frame benchmark

`frame_bench.bend` times a whole frame, not a stripped-down render. Each timed
phase uses `IO.now` for its start and end and places a forcing `IO.print` of the
folded digest inside the timed region, so nothing is dropped as dead code. The
digest is also printed per phase; the 32-phase and 32 `render_only` digest match
(4066811413), which is the check that the full frame and the prebuilt-grid render
produce the same pixels.

- `bootstrap` — one bulk `World.chunk` plus the nested y/z/x grid, consumed by a
  `grid_at` so the work is real. This is the fixed per-frame chunk cost.
- `render_only size=32` — the prebuilt-grid image + fingerprint path the earlier
  `render_bench.bend` measured, kept as the control that the position-aware
  camera did not change the 32×32 render cost.
- `frame size=32|64|128` — the full frame: bulk chunk + nested grid + image at
  an arbitrary eye + fingerprint, at depths 5, 6 and 7.

## Measurements

Platform for the run below: WSL2 x86_64 on an AMD Ryzen 7 9800X3D, Bend 2.0.32,
Ubuntu clang 21.1.8, native C target, `--threads 1 --gpu off`, seven samples,
one `run.sh` invocation on an otherwise idle machine. Medians with the range
over those seven samples:

| phase | per batch | median ms | range ms | per frame |
| --- | --- | --- | --- | --- |
| bootstrap (16× chunk+grid) | 16 | 155 | 153–157 | 9.7 ms |
| render_only 32 (16× image+fp) | 16 | 200 | 199–203 | 12.5 ms |
| frame 32 (16× full) | 16 | 360 | 353–362 | 22.5 ms |
| frame 64 (16× full) | 16 | 964 | 951–967 | 60.3 ms |
| frame 128 (8× full) | 8 | 1713 | 1699–1735 | 214.1 ms |

Two earlier full invocations of the same harness, taken back to back on a
busier machine, reported 328 / 886 / 1564 ms for the 32 / 64 / 128 frame batches
and 144 / 187 ms for bootstrap / render_only. So expect roughly 8–10% faster
numbers when the host is busier than the table above; within one run the samples
are tight.

`IO.now` has millisecond precision on this native C lane, so the bootstrap and
32-frame numbers each carry about ±1 ms of quantization. The `render_only`
control at 12.5 ms per 32×32 image (200/16) is consistent with the previously
documented 12.438 ms post-index median, confirming the position-aware camera
did not regress the pinned render. The earlier pre-index baseline was 793 ms per
32×32 image.

**Frame budget against a game window — not met.** A plausible game window is far
larger than these probe frames. Scaling the measured per-pixel cost: the 128×128
frame is 16384 pixels at 214.1 ms, about 13.1 µs per pixel including one chunk
bootstrap. A 320×180 window is 57600 pixels, roughly 0.75 s per frame. A
640×360 window is 230400 pixels, roughly 3.0 s per frame. At 60 FPS a frame
budget is 16.7 ms, or about 1280 pixels of this renderer per frame; the probe
itself renders 128×128 in ~214 ms. So this software DDA renderer is two to three
orders of magnitude short of an interactive game window, and reaching it would
need a fundamentally different rasterizer (GPU scanline or a coarser screen
resolution), not a tuning pass. No speedup is claimed for the camera change
itself: it is an API extension whose cost is the `render_only` control above,
statistically indistinguishable from the pre-refactor 32×32 cost.

The focused diagnostic (`diagnostic_bench.bend`) still applies: across three
native runs, DDA visits 21,663 cells (21.16 per ray) and took a median 791 ms
with flat `List.get`; with the nested grid the same-count replay took 11 ms at
y=10 and 14 ms at y=14, while DDA took 12 ms. The data supports flat-list
indexing as the dominant original cost; exact attribution is limited by the
representative lookup replay and clock resolution. Reproduce it with:

```bash
.tools/bend-local/bin/bend lab/native/voxel/diagnostic_bench.bend -o scratchpad/voxel-probe/diagnostic_bench
scratchpad/voxel-probe/diagnostic_bench --threads 1 --gpu off
```

## The parallel frame

`voxel_probe_parallel.bend` adds one thing to the renderer: a bang. The
recursion in `image` already forks its four independent quadrants with a
parallel let —

```python
tl tr bl br = image(p, grid, camera, half, focal, x, y)
  image(p, grid, camera, half, focal, (x + step : U32), y)
  image(p, grid, camera, half, focal, x, (y + step : U32))
  image(p, grid, camera, half, focal, (x + step : U32), (y + step : U32))
```

— so 4-way fan-out needs no nesting and no second recursion. The parallel
entry point is that same call marked for parallel execution at its root:

```python
def render_size_parallel(+grid, +camera, +depth) -> Image:
  +half = Voxel.projection_half(depth)
  image_root!(depth, grid, camera, half, F32.mul(1.5, half), 0, 0)
```

`render_size_at_parallel`, `render_at_parallel`, `render_chunk_parallel`,
`render_grid_parallel` and `render_view_parallel` are the single-thread
functions with that bang. No pixel, ray, grid read or fingerprint step changes,
and `voxel.bend` itself is untouched, so the pinned goldens cannot move.

`voxel_probe_parallel_test.bend` is the focused test. It pins that the forked
frame's fingerprint equals the single-thread frame's at 32×32 and at 64×64, that
the forked frame still changes when the eye moves and when the yaw turns, and
that the forked path still produces the two pinned 32×32 goldens (3923257805 at
yaw 0, 2153099706 at yaw 0.7). Every failure is `IO.die`. `run-parallel.sh`
runs it at 1, 4, 8 and 16 threads before it collects a single timing, so a fork
tree that changed the pixels at a higher thread count would fail the run rather
than look faster.

`parallel_frame_bench.bend` times the same full frame `frame_bench.bend` times
— bulk `World.chunk(1337n, 0n, 0n)`, the nested y/z/x grid, the 2^depth image
at an arbitrary eye, the fingerprint — in three phases per size, each with
`IO.now` around a forcing `IO.print` of the folded digest:

- `frame` — the single-thread path, the control.
- `frame_par` — the same frame through the banged entry point.
- `sky` — a control with the DDA left out: the same quadtree, the same
  per-pixel rays and the same fingerprint fold, over a sky color. The ray is
  folded into the color so it cannot be dropped as dead code, so what this
  control omits is exactly the trace and its reads of the shared grid.

Every run also checks in-process that `frame` and `frame_par` produced the same
digest at the same size, and the harness fails the run if they differ. All 28
runs of the sweep below (7 samples × 4 thread counts) matched.

Platform for the run below: WSL2 x86_64 on an AMD Ryzen 7 9800X3D (8 cores, 16
hardware threads, 8 visible to WSL), Bend 2.0.32, Ubuntu clang 21.1.8, native C
target, `--gpu off` throughout, seven samples, one `run-parallel.sh` invocation
from a fresh compile of these sources. Per-frame medians, with the measured
speedup against `--threads 1` in brackets:

| threads | frame 32×32 | frame 64×64 | frame 128×128 |
| --- | --- | --- | --- |
| 1 | 22.3 ms (1.00×) | 60.0 ms (1.00×) | 210.5 ms (1.00×) |
| 4 | 18.3 ms (1.22×) | 42.8 ms (1.40×) | 139.1 ms (1.51×) |
| 8 | 17.4 ms (1.28×) | 37.9 ms (1.58×) | 117.3 ms (1.80×) |
| 16 | 17.7 ms (1.26×) | 37.9 ms (1.58×) | 115.9 ms (1.82×) |

The same table for the banged entry point, `frame_par`:

| threads | frame_par 32×32 | frame_par 64×64 | frame_par 128×128 |
| --- | --- | --- | --- |
| 1 | 22.4 ms | 59.9 ms | 210.6 ms |
| 4 | 18.6 ms | 43.1 ms | 139.9 ms |
| 8 | 17.3 ms | 37.8 ms | 117.9 ms |
| 16 | 17.6 ms | 37.7 ms | 115.6 ms |

And the `sky` control, per frame, which is what fork and schedule cost alone:

| threads | sky 32×32 | sky 64×64 | sky 128×128 |
| --- | --- | --- | --- |
| 1 | 0.19 ms | 0.25 ms | 0.38 ms |
| 4 | 0.31 ms | 0.44 ms | 0.50 ms |
| 8 | 0.56 ms | 0.56 ms | 0.63 ms |
| 16 | 0.88 ms | 0.81 ms | 0.88 ms |

The batch medians behind the table, 16 frames at 32×32 and 64×64 and 8 at
128×128, with the range over the seven samples: `frame` 32×32 356 [354, 360] /
292 [288, 296] / 279 [276, 281] / 283 [280, 287] ms at 1/4/8/16 threads;
`frame` 64×64 960 [954, 972] / 684 [675, 696] / 607 [601, 610] / 606 [603, 614]
ms; `frame` 128×128 1684 [1676, 1688] / 1113 [1108, 1124] / 938 [934, 950] /
927 [919, 935] ms. `IO.now` has millisecond precision here, so the 32×32 and
`sky` numbers each carry about ±1 ms of quantization. A `run.sh` invocation on
the same machine minutes earlier gave 22.2 / 60.1 / 210.8 ms per frame at
`--threads 1`, which reproduces the table in the previous section (22.5 / 60.3 /
214.1 ms) to within 2%.

### Verdict: no, not at any thread count

**There is no size whose full-frame median fits inside 16.7 ms, at any thread
count.** The smallest frame this quadtree can build is 32×32 = 1024 pixels, and
its best median is 17.4 ms at `--threads 8` — above the budget, before the
frame is scaled to anything resembling a window. The best cell anywhere in
either table is `frame_par` at 32×32 and `--threads 8`, 17.3 ms, which is also
over. At 16 threads the single-thread frame is 17.7 ms, so the pool saturates at
the 8 cores WSL exposes and 16 threads buys under 3% on the largest size. 64×64
is 37.9 ms (26 FPS) and 128×128 is 115.9 ms (8.6 FPS) even at the best thread
count.

Two further facts shape that answer, and both are measured, not assumed:

- **The bang is worth nothing on this target.** `frame_par` and `frame` are
  within noise of each other at every size and every thread count: the largest
  gap is 6 ms on a 1113 ms median, and the sign alternates between cells, so it
  is not a direction, let alone a speedup. That is the expected result: the fork
  tree is the same one in both paths, because `image` already forks its
  quadrants, and on the native CPU lane a bang only marks a call for the same
  pool `--threads N` sizes. The knob that moves the frame is `--threads`, and it
  is worth 1.82× at 128×128 — 23% of the 8 visible cores, 11% of the 16
  hardware threads.
- **The per-pixel trace is the whole cost, and it barely forks.** The `sky`
  control pays the same fork, the same per-pixel camera math and the same
  fingerprint fold and costs 0.19–0.88 ms per frame, under 5% of any frame in
  the table. So essentially all of the frame is `trace_inside`, and the part of
  that which does not fork is the ~9.7 ms per frame of `World.chunk` plus the
  nested grid, which is built inside the sequential fold and is the same at every
  thread count. That serial floor is why 32×32 cannot drop below ~17 ms however
  many threads are added: ~9.7 ms of chunk and grid, plus ~7.7 ms of forked
  image at `--threads 8`.

**The honest reading: `!` gives no speedup here, and the renderer's per-pixel
work does not parallelize enough to make a real window plausible.** At the best
measured configuration a frame costs 7.2 µs per pixel (117.3 ms / 16384 px at
`--threads 8`), so a 320×180 window is 57600 pixels, roughly 416 ms a frame, and
a 640×360 window is 230400 pixels, roughly 1.66 s a frame. Fitting 320×180 into
a 16.7 ms budget needs 0.29 µs per pixel, 25× less than the 7.2 µs this renderer
costs per pixel at its best thread count, so the missing factor is a different
rasterizer (the GPU scanline path in `demos/app_slash_boss_3d`, or a coarser
screen resolution), not more threads.

Attribution of the 1.82× ceiling is a hypothesis consistent with the emitted C,
not a measured cause: every reusable (`+`) read of the shared grid and camera
compiles to `rfc_bump` → `a32_add`, an atomic add on one shared refcount
(`bend lab/native/voxel/parallel_frame_bench.bend -o out.c`, then look for
`rfc_bump` in `out.c`), and `trace_inside` does about 21 reusable reads of that
grid per pixel on the same counter, because the DDA visits 21.16 cells per ray
(diagnostic above). The guide names this cost directly ("a `+` value read by
every lane costs an atomic per read"; "one list per cell, not per pixel: a list
shared by pixels is contended atomics"). Testing it is a follow-up this probe
did not do: a sibling module whose trace threads the grid affinely, so a branch
owns its own copy and no lane reads a shared refcount, benchmarked against the
numbers above. The `sky` control bounds the alternative reading — if fork and
schedule overhead were the ceiling, the control would not be 5% of the frame.

Reproduce with:

```bash
bash lab/native/voxel/run-parallel.sh
```

## Limits

This is a feasibility proof, not renderer parity. It uses a simple block-color
palette and per-face tint, has no window or input loop, no lighting model, no
textures, no transparency, and no WebGL comparison. Rays only traverse the
bounded 16×20×16 bulk chunk: an eye inside the chunk renders blocks and sky, an
eye outside it renders a defined all-sky frame (pinned by the focused test), and
neighboring chunks are not yet streamed, so a frame cannot yet show more than
the one chunk. The 96×96 size named in the task is not benchmarked: the native
`Image` is a quadtree over 2^k × 2^k, so only square power-of-two frames (32, 64,
128) can be constructed; 64 and 128 bracket what 96×96 would cost.
