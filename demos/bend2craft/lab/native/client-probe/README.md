# native/client-probe

The native client's own frame cost, and the end-to-end proof that it runs under a
real display.

`frame_bench.bend` is the clock; `native/client.bend` is the client. Nothing in the
benchmark reimplements a rule: every stage calls the client's or a probe's own def,
so a phase can only be as wrong as the rule it calls.

`run-bench.sh` times the client's stages. `run-fps.sh` answers a different question —
how many frames the live client actually presents — and `fps_probe.bend` is what it
runs.

Three more probes here answer questions the stage timings cannot, and they are the
reason a resolution above 128x128 is known to be out of reach for this renderer and
known to be reachable for a different one:

- `output_probe.bend` — the floor under every resolution. It builds and releases an
  `Image` quadtree in one colour, with no face, no projection, no bucket and no walk,
  so it prices only what the runtime's output costs. **4.50 ms at 1024x1024** against
  a 16.67 ms tick, which is the measurement that says the output is not the wall.
- `array_probe.bend` — what one random-access touch costs at a frame's size. An
  `Array<U32>` write is **0.24 ns** and a read **0.20 ns** at 1,048,576 slots, so the
  structure a painting renderer would keep its frame in is not a cost. A read walk
  that reads and discards measures 0 ms, so both walks fold what they read into a
  digest; without that they measure nothing.
- `span_probe.bend` — a painter's algorithm, built to be measured rather than shipped,
  in three priced phases. **fill** projects each face's quad, walks the quad's scanlines,
  computes each line's x-range from the two edges that straddle it, and writes the span
  into a flat array: **2.4 ms at 1024x1024**, against a walk that would need 3.0 seconds
  at the same size. **order** sorts the faces back to front once, by each face's farthest
  corner in camera space, so the last write to a pixel is the nearest face covering it and
  no depth buffer is needed: **0-1 ms** for 1,654 faces. **fold** reads the frame back into
  the `Image` quadtree `Window.frame` takes, and it is the wall: **79 ms at 1024x1024**
  against a 4.50 ms constant build of the same tree. See "The wall is the read-back" below.

Per frame, all three phases, against a 16.67 ms tick:

| size | order | fill | fold | total | fits 60 Hz |
| --- | ---: | ---: | ---: | ---: | --- |
| 128x128 | 0-1 | 0.26 | 2 | ~2.3 | yes |
| 256x256 | 0-1 | 0.49 | 5-6 | ~6.5 | yes |
| 512x512 | 0-1 | 1.1 | 20-21 | ~22 | no |
| 1024x1024 | 0-1 | 2.4 | 78-79 | ~81 | no |

`fill` is timed over 200/100/30/10 iterations and divided; `order` and `fold` are timed
once each and are not divided, because neither is per-iteration work. The read-back's
`fold_check` gate folds a frame of `tint(index)` at every depth from 0 to 8 and reads every
pixel back, and it was confirmed able to fail: shifting the expected index by one makes it
report the deepest depth checked. A fold whose index arithmetic was wrong would still
produce a full-depth quadtree, still fill the window, and still have a fingerprint, so this
is the only thing standing behind those numbers.

### The wall is the read-back, and it is the handle

The fold costs 79 ms where a constant build of the *same tree* costs 4.50 ms. Nothing
about the pixels got more expensive in between: the read is 0.20 ns a pixel and there are
1,048,576 of them. What changed is the sharing. A four-way parallel let over a `U32` — what
`const_image` does — hands each branch the same affine value, which is free. `Array` is a
`Type`, and Bend's only sharing quantifier, `+`, is for `Data`, so one array handle cannot
be handed to four parallel calls at all. `Array.fork` is the way round it: a second handle
to the same cells in O(1). But a handle is a refcount on cells all four branches share, so
every fork inside a parallel let is an atomic on one cache line that eight cores are
writing. The fold spends twelve forks per node over 1.4 million nodes, and that is where
the 75 ms goes.

Three forks per node is the floor for a four-way fan-out over an unshareable value, and
the language cannot reach it: a `match` may not be preceded by a destructuring statement,
so the four handles a fork produces cannot be named inside the def that matches the level,
and a helper that could name them would have to call the matcher back — a cycle, which
this language has none of.

Collapsing a node to a single `Pix` when all four of its children are one colour would cut
both the allocations and the recursion, and the runtime reads a `Pix` at any level by filling
the whole block with it, so a shallower tree is the same picture. It is implemented
(`Flat` in `span_probe.bend`) but it runs bottom-up, so the forks are already paid — 79 ms
before and 79 ms after.

**How much of the frame is one colour**, which is what decides whether testing *before* the
fan-out pays. `span_probe.bend` walks the painted frame once and counts:

| size | 8x8 blocks uniform | 32x32 blocks uniform |
| --- | ---: | ---: |
| 128 | 45 / 256 | 0 / 16 |
| 256 | 434 / 1024 | 0 / 64 |
| 512 | 2645 / 4096 | 0 / 256 |
| 1024 | **12800 / 16384 (78.1%)** | **0 / 1024** |

The control is a one-colour frame at side 8 over 64 pixels, which reports 64/64, so the counts
are counts. 78% of 8x8 blocks uniform at 1024 is the good half: a 1024 frame has 16,384
level-4 nodes and each collapsing one takes 1,365 nodes beneath it, so most of a 1.4-million
node tree goes. The zero at 32x32 is the other half and says why the side has to be 8: a
voxel face is shaded per direction, so adjacent blocks differ, and a 32x32 block always
straddles a face boundary. It also says why the 8x8 figure climbs with resolution — a face
is 30 pixels across at 128 and 1 at 1024, so more of the frame falls inside a single face.

The obstacle is narrower than an earlier note in this file had it, and that note was wrong. A
strided walk threads a handle perfectly well — the uniformity walk is one. What the language
will not do is let a caller open a call's result, so a parent cannot split the scan's answer
into the two arguments its children's calls need without a helper, and a helper that opens the
scan and then fans out is a cycle, because the fan-out is the recursion. The way round it: the
scan returns one `U32` (the colour, or a sentinel), and the parent pays one extra `Array.fork`
per child so it still has a handle to hand the child. Four forks per node instead of twelve,
and a uniform node pays none of them. Not written yet.

Each probe is run directly:

```bash
.tools/bend-local/bin/bend lab/native/client-probe/output_probe.bend -o scratchpad/output-probe/output_probe
.tools/bend-local/bin/bend lab/native/client-probe/array_probe.bend  -o scratchpad/output-probe/array_probe
.tools/bend-local/bin/bend lab/native/client-probe/span_probe.bend   -o scratchpad/output-probe/span_probe
./scratchpad/output-probe/output_probe --threads 8
./scratchpad/output-probe/array_probe  --threads 8
./scratchpad/output-probe/span_probe   --threads 8
```

The measurements and what follows from them are in
`docs/2026-09-30-native-renderer-investigation.md`, session four.

## The presented frame rate

`App.loop`'s third argument is a frame countdown: the prelude decrements it once per
`App.step`, and one `App.step` is one `Window.frame`, which is one `XPutImage`. So a
probe that hands `App.loop` a known count and times the call measures the presented rate
exactly. The probe uses the client's own `start`, `view`, `tick`, window size and tile
edge, so the frame it draws is the frame the client ships; `native/client.bend` is not
modified to accommodate it.

The runtime's `window_pace` sleeps every presented frame to the next 16.67 ms tick, so
60 is the ceiling and anything under it is a frame that overran. Measured over three
600-frame runs at 64x64: **59.79, 59.72 and 59.75**. On the shipping 128x128 build, four
600-frame runs: **60.01, 60.00, 59.99, 59.98** — the ceiling, with the sub-0.05 Hz drift
being the pace accumulating over 600 intervals rather than a frame that overran. Passing
`--threads 8`, which is what `run-bench.sh` uses, changes it by nothing.

The rate is also the first thing a busy host takes away, and that is worth stating rather
than leaving to a lucky run. Four further 600-frame runs at 128x128 in one sitting read
**59.94, 59.95, and 49.57** — the last one 111 frames short over ten seconds. A frame that
overran the tick costs at most one frame; 111 is a host that took the CPU away from the
loop, which on WSL2 is eight logical CPUs shared with Windows. So "at least 60 FPS" is a
statement about the renderer holding the tick when the machine is quiet, and the honest
caveat is the machine.

This has to be a separate check because the benchmark cannot answer it: the benchmark
times stages in a harness, and the harness never opens a window, so it never paces and
never presents. Nor is the rate countable from outside the process — `XPutImage`
cannot be traced here (no `strace`, `ltrace` or `perf`), and `/proc`'s CPU time summed
across the runtime's threads bounds the product of a frame's cost and the number of
frames without separating them. An earlier version of this check did exactly that and
reported the client missing the tick at 17.7 ms a frame; that was an artifact of
assuming 60 Hz, and the check was deleted rather than repaired.

**This probe drives no input, on purpose.** The dig frame is the only one without slack,
so a synthetic-key driver was built to dig while the loop ran, and it was removed: each
`xdotool` invocation is a Python process competing with the client for the same four
cores. Sixteen digs at thirty frames read 58.39 FPS with two processes per press, 55.65
with a wall-clock-bounded driver and 53.16 with one process per stream, against 60.00
with no input at all in the same harness on the same host. **Less driver gave more FPS
in every comparison**, which is backwards for a measurement of the client, so the number
was measuring the driver. The dig frame needs no live confirmation: `frame_edited`
forces a cold world rebuild on every iteration — strictly worse than a session where
digs alternate with held frames — and measures 16.25 ms against a 16.67 ms tick, and
`window_pace` sleeps any frame shorter than the tick, so a sub-tick frame presents at the
ceiling by construction.

## The evidence for the frame-rate goal

The goal is the client's maximum frame rate. Four claims, and how to check each.

**1. 60 is the ceiling, and it is not ours to raise.** `window_pace` in
`vendor/bend/bend2/effs/window.c` sleeps every presented frame to the next 16.67 ms
tick, before every `XPutImage`, unconditionally:

```c
// A frame waits for the next 60 Hz tick, as the Mac's display sync.
static void window_pace(void) {
  static u64 due;
  u64 now = io_tick();
  if (due > now) { ... nanosleep ... }
  due = (due > now ? due : now) + 16666667;
}
```

`vendor/bend` is upstream code and `AGENTS.md` forbids editing it, so no client change
can present faster than 60.

**2. The client presents 60.** Ten 600-frame runs on a quiet host at 64x64: 59.97, 59.92,
60.00, 60.00, 60.00, 60.01, 59.83, 60.01, 59.48, 59.65 — and on the shipping 128x128
build, four runs: **60.01, 60.00, 59.99, 59.98**. Check with:

    bash lab/native/client-probe/run-fps.sh

It reads 55 to 60 when the Windows host is busy, because WSL2 shares the host's CPUs
with it. That spread is the host, not the client: the same host reads 60.00 on an idle
machine and `render` measures 14.40 ms either way.

**3. The frame budget is inside the tick, for every frame the client can draw — except
the dig frame, which sits at it.** On the shipping build, two twenty-one-sample runs at
eight threads, per call:

| phase | run A median [min, max] | run B median [min, max] | against 16.67 |
| --- | --- | --- | ---: |
| `tick_held` | 0.03 | 0.03 | 0.2% |
| `render`, world held | 14.40 [13.95, 15.70] | 14.10 [13.75, 19.55] | 85% |
| `render`, cold | 16.60 [16.00, 17.90] | 16.30 [15.80, 29.95] | 98% |
| `frame_held` | 14.75 [13.95, 16.00] | 14.50 [13.80, 29.80] | 87% |
| `frame_look` | 14.45 [13.85, 24.80] | 14.35 [13.85, 22.40] | 86% |
| `frame_edited` | 16.25 [15.80, 29.75] | **16.65** [15.80, 30.00] | 100% |

The dig frame's median was 16.25 and then 16.65 against a 16.67 ms tick, so it presents
at 60 by a margin a busy host can take away. The maxima of 22 to 30 ms appear in every
phase including `frame_held`, which no phase should be able to exceed, so they are the
shared host rather than the client: WSL2 divides eight logical CPUs with Windows and a
scheduler preemption lands on whichever phase is running. The dig frame's own spread is
narrower than that — 15.80 at the floor in both runs.

Check with:

    RUNS=21 THREAD_COUNTS=8 bash lab/native/client-probe/run-bench.sh

**The thread count is load-bearing, and it is not a tuning knob.** Measured across the
whole pool, `render` median at nine samples each:

| threads | 1 | 2 | 4 | 6 | **8** | 12 | 16 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `render` ms | 55.85 | 32.25 | 19.55 | 15.80 | **13.95** | 14.00 | 14.05 |
| speed-up | 1.00x | 1.73x | 2.86x | 3.54x | **4.00x** | 3.99x | 3.98x |

Twelve and sixteen threads buy nothing over eight, so the pool saturates at the host's
logical CPU count. The 4.00x is not four cores' worth of work: four threads reach only
2.86x, and the last 1.40x is SMT hiding the memory latency of a pointer-chasing walk.
**At `--threads 4` the render is 19.55 ms and the client misses the tick outright**, so
the runtime's default of "CPU count" is what makes 60 Hz reachable and must not be
pinned lower. Check with:

    RUNS=9 THREAD_COUNTS="1 2 4 6 8 12 16" bash lab/native/client-probe/run-bench.sh

**4. No further client change can raise the presented rate**, and the walk that is 85%
of the frame is at its floor on both sides. Step count: 1.27x the faces' live box
coverage, reducible only by a smaller tile edge, which the serial grid builder forbids —
measured under both builders, at both sizes. Step cost: 24.1 ns of which 89% is the bare
cons-cell iteration, priced by four walks of the same grid, and the pool is saturated per
the table above, so 256x256 would need about twelve cores of this workload. `--gpu`
addresses only `XPutImage` and the pixmap fill, which are ~0.30 ms together, and its
lane is not buildable on this host anyway (no CUDA toolkit headers, no clang 19). Field
of view moves the candidate count 4% over a 96x change. A rasteriser needs 1.78x fewer
steps but replaces an allocation-free read with a persistent-path depth test.

**The next resolution up was built and measured rather than argued.** At 256x256 the
client presents **21.33 FPS**: 45.67 ms a frame, of which 45.65 is the walk over
7,828,480 candidate visits. Reaching 60 Hz there needs 2.8x, and no measured lever
offers a tenth of it. 128x128 is the largest window this renderer sustains at the ceiling.

**Known caveat, stated rather than buried.** The frame that follows a dig is the
tightest: 16.25 ms median in one run and 16.65 in the next, against a 16.67 ms tick, so a
dig can drop a frame when the host is busy. Its extra cost is the region's face
extraction, of which only 0.35 of 1.88 ms is cacheable per chunk. That cache was built
and then removed: the shipped view is a single chunk, so a per-chunk key space has one
entry, that entry is the whole edit log, and `world_for` only rebuilds when the log has
changed — every rebuild missed. The 0.26 ms needs a region wider than one chunk, and a
two-by-two region costs 19.10 ms against the 16.67 ms budget. What is left is splitting
the chunk's extraction into sub-blocks and re-extracting only the one a dig touched,
worth about 1.4 ms; it is sound for a one-chunk view but it reorders the face list, and
the order is what the tile-edge dispatch and the bucketing's locality depend on, so it
would have to be measured rather than assumed. The arithmetic is at `world_built` in
`native/client.bend`, and the measurement that closed the per-chunk version is in
`docs/2026-09-30-native-renderer-investigation.md`.


## What a frame is

Between two `Window.frame` calls the client does:

1. re-ask the pointer grab,
2. fold the tick's events into the held-key mask and run the player transition,
3. read the raycast an action key would read,
4. materialise the bulk chunk,
5. render it with the face renderer at the client's tile edge,
6. let `Window.frame` walk the image into the X pixmap and free it.

`frame` and `frame_look` are the two together, which is the number the 60 Hz budget
is judged on. `tick`, `chunk` and `render` are the parts, so a regression can be
attributed rather than guessed at.

The image is read back before it is released, because a build whose result nothing
observes is elidable and a phase that measured an elided build would report the cost
of nothing. The read is a full quadtree walk, and the client pays it too:
`Window.frame` calls `window_show`, which walks the same tree with `window_fill` into
the X pixmap before `XPutImage`. The fingerprint is a fair stand-in for the present
step and leaves out only the X transfer.

The action keys are deliberately not in a timed phase: dig and save both reach the
filesystem, and a benchmark that writes the world twenty times measures the disk
rather than the tick. The edit and save paths are covered by `native/play_test.bend`.

## Measured

`bash lab/native/client-probe/run-bench.sh` — 7 samples per phase, per-call medians,
native C executable, `--gpu off`.

AMD Ryzen 7 9800X3D, 8 cores visible to WSL2, Bend 2.0.32.

| threads | phase | size | median ms | min ms | max ms |
| --- | --- | --- | --- | --- | --- |
| 1 | tick | 128 | 0.90 | 0.90 | 0.91 |
| 1 | chunk | 128 | 0.05 | 0.05 | 0.10 |
| 1 | render | 128 | 82.40 | 79.45 | 85.75 |
| 1 | frame | 128 | 80.70 | 80.50 | 85.50 |
| 8 | tick | 128 | 0.88 | 0.88 | 0.88 |
| 8 | chunk | 128 | 0.10 | 0.05 | 0.10 |
| 8 | render | 32 | 5.98 | 5.97 | 6.30 |
| 8 | render | 64 | 9.45 | 9.45 | 9.85 |
| 8 | render | 128 | 22.55 | 22.45 | 23.40 |
| 8 | frame | 128 | 24.35 | 23.75 | 24.65 |

The 1-thread figures are 3 samples, not 7; the 8-thread ones are the current
seven-sample run. Re-run the script for the current table.

## What it says

- **64x64 fits 60 Hz with headroom.** 9.45 ms of render plus 0.88 ms of tick is
  about 10.3 ms against a 16.7 ms budget, so the client has roughly 6 ms of room
  for the X transfer and the window's own pacing.
- **128x128 does not fit 60 Hz.** 24.35 ms per frame is about 41 FPS. The plan
  previously claimed 128x128 at 60 Hz on the strength of a face-probe number taken
  at a different, sparser camera pose; measured at the client's own spawn camera,
  that claim is not supported and the plan now says so.
- **The chunk is not the cost.** Rebuilding `WorldState.chunk` every frame is
  0.10 ms, so caching the chunk would save nothing worth having. The whole cost is
  the face render at a camera that actually sees the world.
- **Threads help about 3.4x, not 8x.** The render is partly serial: the bucketing
  pass is parallel, the per-pixel selection is not.

The 16.7 ms budget comes from the pinned runtime's own frame pacing, which hardcodes
a 16666667 ns interval, so 60 Hz is the ceiling whatever the renderer does.
