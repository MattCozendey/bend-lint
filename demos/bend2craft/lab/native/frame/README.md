# Native frame-cost probe

The voxel probe answers "what does one render cost". The player probe answers "what
does one collision tick cost". Neither answers the question the client plan is
actually blocked on: **what does one whole frame of a native client cost, and can
it hold a frame budget?**

This probe times one frame end to end in a single process, breaks it into its
stages, measures what the timing harness itself costs, measures the frame again
when nothing changed, measures the pacer, and reports the budget for each window
size at two thread counts.

Nothing here re-implements physics, camera or rendering. The frame is composed of
the two probes that already own those:

- `lab/native/player/player.bend` owns the collision region and delegates
  the tick to `Player.step`.
- `lab/native/voxel/voxel.bend` owns `Camera.look`, `render_size_at` and
  the image fingerprint.

The only thing `frame.bend` owns is the frame that joins them, and one pure
rule inside it: the condition a client must test before it can skip a frame.

## The frame definition

One frame is exactly this, in this order:

1. **input** — the tick's `List<Event>` folded into the held-key mask `Player.step`
   reads and into the two mouse-look deltas, which are written onto yaw and pitch
   before the tick. `Frame.input`, `Frame.ready`.
2. **player tick** — `Player.step` at `dt = 1/60 s` against a cached 2x2-chunk
   collision region (`columns = rows = 2`, 20480 cells) built once from four bulk
   `WorldState.chunk` exports. `Frame.tick`, via `PlayerProbe.step`.
3. **camera** — the player's resulting eye, rebased from domain cells onto the
   render chunk and lifted by the eye height, then turned into a basis through the
   voxel probe's `Camera.look`. `Frame.pose`, `Frame.camera_of`.
4. **render** — `Voxel.render_size(grid, camera, depth)`. `Frame.render`, and that
   one function body is the only thing a face-based renderer has to replace.
5. **fingerprint** — `Voxel.fingerprint` over the resulting image.

The spawn is chunk `(1, 1)` of seed 1337 with the player at world `(25, 25, 9)`,
settled for 120 untimed ticks before any measurement, so the camera starts inside
the render chunk, standing on the terrain, with the world still. The focused test
pins that the settled frame's centre pixel is a block and not a sky pixel, so the
render is a real render and not an all-sky frame that would have measured nothing.

`Frame.frame` takes a `force` flag that is the whole difference between the two
rendering policies a client has:

- `force = True{}` redraws on every tick.
- `force = False{}` redraws only when `Frame.pose_changed` says the camera moved,
  and carries the previous fingerprint forward otherwise.

## The one new rule: the dirty-frame condition

```python
def pose_changed(+before: Pose, after: Pose) -> Bool
```

The camera is the only thing the render stage reads, and `Camera.look` uses the
eye's three components plus yaw and pitch and nothing else. So the image changes
exactly when one of those five numbers changes. The condition a client must test
before it can skip a frame is therefore:

> draw when the eye moved in x, y or z, or when yaw or pitch changed, **or** when
> the render grid changed under the camera. This probe measures the pose half; a
> world edit dirties the grid rather than the pose, so a client ORs a grid-version
> flag in at the same place — `Frame.draw.at` takes `changed` as that parameter.

The complement is pinned too, because it is the reason the rule is worth having:
a state that moves hunger, air, health, fall damage, velocity or the grounded flag
without moving the eye produces the same pixels, and must not cost a frame. The
focused test asserts all four of those are clean and all five camera inputs are
dirty.

## Running it

From the repository root, in WSL on Windows or a native Linux/macOS shell:

```bash
bash lab/native/frame/run.sh
```

The script uses `.tools/bend-local/bin/bend` by default or `BEND_BIN` when set,
requires `bend 2.0.32`, and prints the platform, the compiler version, the CPU, the
visible processor count and the thread counts. It compiles `frame_test.bend`
and `frame_bench.bend` into the ignored `scratchpad/frame-probe/`, runs the focused
test at **every** measured thread count before taking a single timing, warms the
executable, then takes seven samples of every phase at every thread count and
reports the median and the range over those seven, plus the per-frame figure and
the FPS that follow from them. Override the sweep with `THREAD_COUNTS="1 4 8"`.

Before any timing, the benchmark itself checks that the cached-grid frame and the
rebuild-per-frame frame fingerprint identically at 32x32, 64x64 and 128x128, and
that neither equals the `sky` control. All six checks pass at both thread counts,
so the two frame paths and the ceiling control are one program measured three ways
and not three different programs.

Every timed phase wraps its workload in `IO.now` and places a forcing `IO.print` of
the folded digest **inside** the timed region, so no phase can be dropped as dead
code. `phase=clock` measures what that harness costs on its own, which is what
makes the sub-millisecond phases below readable.

## Measurements

Platform for every table below: WSL2 x86_64 on an AMD Ryzen 7 9800X3D (8 cores
visible to WSL), Bend 2.0.32, Ubuntu clang 21.1.8, native C target, `--gpu off`,
seven samples of one `run.sh` invocation from a fresh compile, on an otherwise idle
machine. Medians over the seven samples, with the range in brackets. A full sweep
of the same harness on the same machine minutes apart reproduced every figure here
to within 3%, apart from the 128x128 `--threads 8` frame, which moved 4.7%.

### The clock, and what it can resolve

| phase | what it times | iterations | median ms | per item |
| --- | --- | --- | --- | --- |
| `clock` | one empty timed region: two `IO.now` and one `IO.print` | 2000 | 3 [2,3] | 1.5 us |

`IO.now` has millisecond resolution on this native C lane. A phase is therefore
only readable if its batch is long enough that one millisecond is a small fraction
of it. The phases below are sized so each batch is at least tens of milliseconds,
which puts the resolution at 0.03 ms or better per frame; the phases that came back
as `0` are reported as bounds derived from their batch size, not as measurements.

### Per-stage cost, `--threads 1`

| stage | 32x32 | 64x64 | 128x128 |
| --- | --- | --- | --- |
| `input` — fold the tick's events | `< 0.25 us` | — | — |
| `tick` — `Player.step` on the cached 2x2 region | 0.97 ms | — | — |
| `camera` — rebased eye and `Camera.look` | `< 0.25 us` | — | — |
| `render` — image build plus release | 5.25 ms [5.13,5.50] | 21.06 ms [20.6,21.3] | 82.88 ms [82.1,87.5] |
| `render_fingerprint` — image build plus the fold | 5.38 ms [5.13,5.44] | 20.75 ms [20.6,21.1] | 82.50 ms [81.9,87.8] |
| `fingerprint` — the fold alone, over images built before the window | `< 0.03 ms` | `< 0.06 ms` | 0.13 ms |
| `drop` — the image release alone, over the same list | `< 0.03 ms` | `< 0.06 ms` | 0.13 ms |

Two independent measurements of the same image construction agree:
`render_fingerprint - fingerprint` and `render - drop` land inside each other's
error bars at every size, so the construction is the whole cost and the fold and
the release are both at or below the clock's resolution here.

### The frame, against a frame budget

`frame` is the whole pipeline at `force = True{}`, so it redraws every tick. It is
measured in the same process as the stages above, against the same cached region
and the same cached grid.

| threads | 32x32 | 64x64 | 128x128 |
| --- | --- | --- | --- |
| 1 | **6.22 ms / 161 FPS** [6.03,6.25] | 21.69 ms / 46.1 FPS [21.4,22.3] | 84.13 ms / 11.9 FPS [82.8,86.6] |
| 8 | **4.47 ms / 224 FPS** [4.31,4.56] | **13.06 ms / 76.6 FPS** [12.5,13.3] | 47.25 ms / 21.2 FPS [44.0,47.5] |

Against a **16.7 ms / 60 FPS** budget: 32x32 fits at both thread counts; 64x64 fits
only at `--threads 8`; 128x128 fits at neither. Against a **33.3 ms / 30 FPS**
budget: 32x32 and 64x64 fit at both thread counts, and 128x128 fits at neither.

### The same frame with the chunk rebuilt every tick

`frame_rebuild` is the identical frame routed through the voxel probe's own
chunk-level `render_size_at`, which rebuilds the nested grid from a fresh bulk
chunk on every call. A client that streams and caches a chunk pays the cheap path;
one that re-materializes per frame pays this. The digests are identical, so the two
paths are the same pixels and only the grid build differs.

| threads | 32x32 | 64x64 | 128x128 |
| --- | --- | --- | --- |
| 1 | 15.97 ms / 62.6 FPS [15.7,16.7] | 31.50 ms / 31.7 FPS [31.4,32.6] | 94.13 ms / 10.6 FPS [92.6,97.8] |
| 8 | 14.69 ms / 68.1 FPS [14.7,15.0] | 23.00 ms / 43.5 FPS [22.6,23.4] | 56.00 ms / 17.9 FPS [54.4,56.5] |

Rebuilding per frame costs **9.75 ms at 32x32**, **9.81 ms at 64x64** and
**10.00 ms at 128x128**: a flat offset, because the grid build does not scale with
the frame size. `phase=bootstrap` measures the whole one-time cost a client
amortizes — one bulk chunk, the nested grid and the 2x2 collision region — at
**11.63 ms** [11.4,12.1], paid once and not per frame.

That pair of rows is the most actionable measurement in this probe: at 32x32 the
raycast frame is 6.22 ms with a cached grid and 15.97 ms without one. The streaming
cache is not an optimization here, it is the difference between comfortably fitting
a 60 FPS budget and barely fitting it.

### The dirty frame

`frame_dirty` is the same frame with `force = False{}` against a player standing
still, so the pose does not move and the render is skipped. The benchmark folds the
number of frames that actually reached the render stage and `IO.die`s unless it is
zero, so a dirty phase that quietly rendered would fail the run rather than report
a cheap frame.

| threads | iterations | median ms | per frame | renders |
| --- | --- | --- | --- | --- |
| 1 | 64 | 61 [60,65] | **0.95 ms / 1049 FPS** | 0 |
| 8 | 64 | 63 [61,64] | **0.98 ms / 1016 FPS** | 0 |

A frame that has nothing to draw costs **0.95 ms**, and the standalone `tick` phase
measures 0.97 ms for the same work. The dirty frame *is* the player tick: input,
collision and the dirty test together are indistinguishable from `Player.step`
alone, because `Player.region_block` walks a 20480-cell list on every collision
probe and that walk is the cost.

So the two FPS figures for the same window are **161 FPS redrawing every tick** and
**1049 FPS when nothing changed**, at 32x32 and `--threads 1` — a 6.5x saving on a
stationary camera, for one comparison of five floats.

### The pacer

`IO.sleep` takes whole milliseconds, so a 60 FPS budget is targeted as a 16 ms slot
and the achieved interval is compared against both that slot and the 16.67 ms of a
true 60 FPS frame. The pacer schedules against an absolute deadline that advances by
exactly one slot per frame; sleeping for "slot minus this frame's cost" instead
would add that cost to every interval and settle at half the target, which is a real
result and is why the loop is written this way.

| phase | render | threads | achieved interval | FPS | overshoot vs the 16 ms slot |
| --- | --- | --- | --- | --- | --- |
| `pacer_free` | `sky` | 1 | 0.97 ms | 1035 | — |
| `pacer_60` | `sky` | 1 | **16.02 ms** | **62.4** | **+0.02 ms** |
| `pacer_60` | `sky` | 8 | 16.03 ms | 62.4 | +0.03 ms |
| `pacer_free_solid` | raycast 32x32 | 1 | 6.23 ms | 160 | — |
| `pacer_60_solid` | raycast 32x32 | 1 | **16.10 ms** | **62.1** | **+0.10 ms** |
| `pacer_free_solid64` | raycast 64x64 | 1 | 21.77 ms | 45.9 | — |
| `pacer_60_solid64` | raycast 64x64 | 1 | **22.30 ms** | **44.8** | **+0.53 ms** |
| `pacer_free_solid64` | raycast 64x64 | 8 | 13.10 ms | 76.3 | — |
| `pacer_60_solid64` | raycast 64x64 | 8 | **16.43 ms** | **60.9** | **+0.43 ms** |

Three things this measures rather than assumes:

- **The pacer holds the budget when the frame fits.** A 0.97 ms frame and a 6.23 ms
  frame both land on 16.02 and 16.10 ms, i.e. 62.4 and 62.1 FPS against a 60 FPS
  target, with an overshoot of 0.02 and 0.10 ms per frame. That residual is
  `IO.sleep`'s millisecond granularity, not the renderer's cost.
- **The pacer cannot rescue a frame that does not fit.** At `--threads 1` the 64x64
  raycast frame costs 21.77 ms, already over the 16.67 ms budget, and the paced run
  still takes 22.30 ms — the pacer sleeps zero and the frame rate stays at 44.8 FPS.
  At `--threads 8` the same frame is 13.10 ms, and the pacer *does* bring it to
  16.43 ms / 60.9 FPS. Whether a window is playable is decided before the pacer is
  written.
- **Pacing costs nothing when it is not needed.** `pacer_free` at 32x32 is 0.97 ms
  per frame; the difference against `frame`'s 6.22 ms for the same work is the
  single `IO.now` per frame, which the `clock` phase bounds at 1.5 us.

### The ceiling a non-tracing rasterizer would have to beat

`frame_sky` is the same frame with the render stage replaced by the voxel probe's
`sky` control: the same quadtree, the same per-pixel ray, the same leaf shape and
the same fingerprint fold, with the trace and its grid reads removed. The ray is
folded into the color so it cannot be dropped as dead code, so what this control
omits is exactly the trace. **This is the measured ceiling a face-based renderer
would have to reach without changing anything else** — not an estimate, a whole
measured frame at each size.

| size | threads 1 | threads 8 | 60 FPS budget | 30 FPS budget |
| --- | --- | --- | --- | --- |
| 32x32 | 0.97 ms / 1032 FPS | 1.56 ms / 640 FPS | fits | fits |
| 64x64 | 1.00 ms / 1000 FPS | 1.63 ms / 615 FPS | fits | fits |
| 128x128 | 1.25 ms / 800 FPS | 1.75 ms / 571 FPS | fits | fits |
| 256x256 | 1.75 ms / 571 FPS | 2.13 ms / 471 FPS | fits | fits |
| 512x512 | 4.50 ms / 222 FPS | 3.50 ms / 286 FPS | fits | fits |
| 1024x1024 | **14.75 ms / 67.8 FPS** [14.5,17.0] | **7.75 ms / 129 FPS** [14.0,17.5] | **fits at both** | fits |
| 2048x2048 | 62.50 ms / 16.0 FPS [58,68] | 29.00 ms / 34.5 FPS [28,38.5] | does not fit | fits at t=8 |

The 0.97 ms floor at the small sizes is the player tick again: the render stage is
already free there, so the frame is bounded by `Player.region_block`, not by pixels.

## Verdict

**With this per-pixel raycaster, the largest window that holds 60 FPS is 32x32** —
1024 pixels, at both thread counts, and only because the chunk is cached and the
player is standing on the ground. At `--threads 1`: 32x32 is 6.22 ms, 64x64 is
21.69 ms, 128x128 is 84.13 ms.

Two measured caveats on that number, both in the frame's favour and both stated so
the decision is not made on the optimistic one:

- The frame above uses the **player's eye on the ground**, which traces short rays.
  The voxel probe's own pinned camera (`render_pinned`, eye at `(8, 14, 0.5)` looking
  down at 0.30) traces roughly twice as far and costs **10.34 ms at 32x32**
  [10.2,10.5] against the player's 5.25 ms, 41.75 ms at 64x64 and 164.75 ms at
  128x128. Added to the 0.97 ms tick, the pinned-camera frame is 11.3 ms at 32x32 —
  still inside 16.7 ms — and 42.7 ms at 64x64, which is not. The 32x32 answer
  survives either camera; the 64x64 answer at `--threads 8` does not.
- The frame **excludes the bootstrap**, which is the right thing to measure for a
  client that caches, and the `frame_rebuild` row is the price of not caching it.
  That is 9.75 ms per frame, flat, and it is the difference between a cached 32x32
  frame at 6.22 ms and an uncached one at 15.97 ms.

**What a face-based renderer would buy, measured: 1024x1024.** Replacing only
`Frame.render`'s body with a non-tracing rasterizer that costs what the `sky` control
costs moves the largest 60 FPS window from **32x32 to 1024x1024** at `--threads 1`,
and from 64x64 to 1024x1024 at `--threads 8` — a factor of 1024 in pixels at one
thread, from one function body. 2048x2048 does not fit 60 FPS at either thread
count (62.5 ms and 29.0 ms), so the ceiling is bracketed by two measured points
rather than by one point and an extrapolation.

That number is worth stating carefully, because the ceiling is not the renderer's.
At 1024x1024 the frame is 14.75 ms and the player tick is 0.97 ms of it: **the
render stage is no longer the binding constraint at or below 512x512**. A
face-based renderer that meets the `sky` cost buys the pixels, and then the next
thing on the critical path is the collision region's list walk, which this probe did
not fix and `native/player-probe` already documents as linear in region volume.

## Limits

- The render is the voxel probe's per-pixel DDA over a single 16x20x16 chunk, with a
  simple block-color palette and a per-face tint. There is no window, no lighting,
  no texture and no transparency. Neighbouring chunks are not streamed into the
  render grid, so a frame cannot show more than the one chunk.
- The collision region is a 2x2 grid anchored at its minimum chunk, so the player
  has room on `+x` and `+z` and hits the region edge walking `-x` or `-z`. There is
  no re-anchoring rule, and none is measured here.
- The player is settled and idle for every timed frame. That is the right shape for
  the render measurement — the camera is a real in-chunk view of terrain — and it is
  the shape the dirty case needs. A moving player would leave the chunk and render
  sky, which would make the render stage look cheaper than it is;
  `held_input_dirties_the_frame` pins that movement does dirty the frame.
- `IO.now` is millisecond-resolution here. `input`, `camera`, `fingerprint` and
  `drop` are therefore reported as upper bounds derived from their batch size, not as
  point measurements. That is why `phase=clock` is measured at all.
- The `sky` control is a lower bound on what a different rasterizer must cost, not a
  prediction of what one will cost. It leaves out the trace and nothing else, so a
  real renderer pays its own face extraction, projection and bucket lookup on top of
  it. The verdict is "this is the floor", not "this is what will happen".
- Timing is native single- and eight-thread CPU. `--gpu off` throughout. Nothing here
  is a WebGL or WebGPU number.
