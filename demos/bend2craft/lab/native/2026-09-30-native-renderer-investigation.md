# Native renderer investigation log

A record of the investigation sessions, kept because the measurements are the
useful part and because several of the conclusions here contradict what the code
looks like at a glance. Every number below was measured on the machine named in
each table; none is extrapolated unless it says so.

Platform: WSL2 on an AMD Ryzen 7 9800X3D (8 cores visible to WSL), Bend 2.0.32
pinned, native C target, `--gpu off`, 7-9 samples, per-call medians. **The thread count is
per-section**: session seven measured at eight because the client launched that way, and
session eight found that eight is the wrong number for a frame, and session ten found that
it was the wrong number for *that painter* and is the right one for the one that replaced it.

## Session ten: 1024x1024 at 60 Hz, and a mouse that is read where it moves

2026-10-01. Two things were left: 1024x1024 presented at 20.73 FPS, and the mouse did not
turn the camera under WSLg. Both are closed, and both turned on something the earlier
sessions had already written down and not acted on.

### The frame: partition the writes, and stop forking the fold

Session eight ended on "1024x1024 is reachable only by making that work partitionable
rather than shared". `native/paint.bend` now does that. The faces are sorted and projected
once into a flat list of quads; a fork tree deals the list down to 64-pixel tiles; each tile
paints its quads into an array of its own and folds that array into its quadtree in the same
task. A region no quad reaches answers its sky without an array.

`bash lab/native/paint/run.sh`, medians of seven, milliseconds per draw:

| size | whole-frame, 1 thread | whole-frame, 8 | tiles, 1 thread | tiles, 8 |
| --- | ---: | ---: | ---: | ---: |
| 128 | 1.20 | 2.35 | 0.70 | 1.18 |
| 256 | 3.52 | 6.25 | 1.40 | 1.30 |
| 512 | 12.47 | 21.52 | 3.77 | 1.77 |
| 1024 | 47.65 | 81.90 | 11.65 | 3.20 |

The one-thread column is the surprise: 4.1x at 1024 with no parallelism at all. The cost
was never the span fill. It was `fold.go`, which forks an array handle and four tasks at
every node of the quadtree — about 350,000 interior nodes at 1024 — where a tile's fold is
one task threading one handle. The eight-thread column is the partitioning: 3.6x on top.

The two painters print the same digest at every size and every thread count, and
`native/paint_test.bend` holds them to the same quadtree on four cameras, so this is the
same picture and the tallies against the walk are unchanged.

Live, `bash lab/native/client-probe/run-fps.sh --size=1024`, 600 frames under Xvfb: 60.06
on the default pool and 59.89 on one thread. It was 20.73.

`lab/native/paint/README.md` has the full tables, the tile-edge sweep and a defect both
painters share (a one-pixel write in the last column).

### The mouse: the display has nothing to give, so ask the host

Session nine measured one `Look` in a whole WSLg session and concluded the fault was
upstream. It is further upstream than `window.c`. WSLg carries the window over RDP with
FreeRDP 2.4.0, which has no relative pointer input, so no X client can be told how far the
mouse moved; `window.c` is also byte-identical through 2.0.34, so a newer pin changes
nothing.

Two measurements decided the design:

- `bash lab/native/pointer/census-xvfb.sh`: on a real X server the grab works and a `Look`
  is a delta. Eight relative steps of ten pixels are eight `Look{10 0}`.
- The fold session nine left differenced each `Look` against the previous one. For that
  travel it turns once and then reads a steady sweep as a still mouse — and in the client
  it differenced each frame's `Look` against that same frame's, so it turned by nothing on
  any display.

So the fold sums deltas again, and under WSL the delta comes from Windows.
`native/pointer.bend` starts `native/pointer-host.ps1` through interop; the script holds the
Windows cursor at the centre of the client's window and writes each displacement as a line;
the client reads the lines each tick, sums them in Bend and gives the fold one `Look`.

Both paths were run end to end through the client's own tick, with the yaw printed every
frame, for 80 px of travel and back: `0 120 240 359 480 600 720 840 960 840 720 600 480 359
239 119 -0` ten-thousandths of a radian on the runtime's grab under Xvfb, and the same
sequence through the host script with the real Windows cursor, which it pulled back to the
centre on 16 of 16 steps. `lab/native/pointer/README.md` has both runs and what is still
unmeasured in a live WSLg window.

### What went wrong on the way

- WSLg's compositor died mid-session and would not restart: `WSLGd` exits with
  `Input/output error @main.cpp:324`, the `chmod` of its virtiofs shared-memory mount,
  every time the distro starts. It began when the idle distro restarted between two
  commands. It needs `wsl --shutdown`, which also stops Docker Desktop's distro, so it was
  left. Everything after that was measured under Xvfb and on the Windows desktop.
- Under WSL `/tmp/.X11-unix` is a read-only mount, so Xvfb has to be started with
  `-nolisten unix -listen local`, on the abstract socket only.
- `lab/native/client-probe/run-fps.sh` resolved the repository root one level short since
  the lab was split out; it is fixed. The other `lab/native/*/run*.sh` scripts still have
  the same `../..`, and `client-probe/frame_bench.bend` builds a `Client` with the wrong
  number of fields. Neither was touched.

## Session eight: the painter ships, and one thread beats eight

Session seven ended with the painter correct to within 0.5-0.8% wrong blocks on the two
hardest cameras and 0 on the one the client ships from, still sitting in `lab/` as a probe.
This session promotes it to `native/paint.bend`, wires the client to it, gates it against the
walk, and finds that the thread pool — not the renderer — was the last limit.

### What shipped

`native/paint.bend` draws the window: it sorts the faces back to front on one depth key,
resolves each face's quad to an integer span per scanline, and lets the last write win. The
client's render call changed and nothing else did:

```python
# before
Face.render_faces_at_with_tile_size(w_faces(world), eye, yaw, pitch, depth, tile_edge_at(depth))
# after
Paint.paint_faces_at(w_faces(world), eye, yaw, pitch, depth)
```

`Face` still answers the pointer's ray and is what the painter is held against.
`native/paint_test.bend` compares the two on colours, which is the question — "do they draw
the same pixel" — rather than on a shared internal encoding, and applies the same three 1%
limits `native/face_test.bend` applies to the walk:

| camera | size | same | wrong_block | spurious | missing | face_only |
|---|---:|---:|---:|---:|---:|---:|
| `spawn` | 128 | 16128 | **0** | 0 | 0 | 256 |
| `level` | 128 | 16220 | 83 | 0 | 0 | 81 |
| `down` | 128 | 16384 | **0** | 0 | 0 | 0 |
| `inside` | 128 | 15863 | 131 | 0 | 0 | 390 |
| `spawn` | 256 | 65024 | **0** | 0 | 0 | 512 |
| `level` | 256 | 65212 | 163 | 0 | 0 | 161 |
| `spawn` | 512 | 261117 | **3** | 0 | 0 | 1024 |
| `down` | 512 | 262144 | **0** | 0 | 0 | 0 |

Limits are 163, 163, 163, 163, 655, 655, 2621 and 2621. Every gated class is inside every
limit at every size. `face_only` is the class `face_test.bend` measures and does not limit,
and it is printed rather than hidden: it is the honest measure of how much the two renderers
differ visibly, and on the spawn camera it is 1.6% of the frame at 128.

### The measured costs, and on how many threads

The client's own stages, at its own spawn camera over its own region, native C, `--gpu off`,
`lab/native/client-probe/run-bench.sh`:

| size | walk (8 threads) | painter, 1 thread | painter, 8 threads |
|---|---:|---:|---:|
| 32 | 3.21 | **0.64** | — |
| 64 | 5.83 | **0.81** | — |
| 128 | 13.95 | **1.38** | 2.48 |
| 256 | 49.00 | **3.60** | 6.40 |
| 512 | 152.50 | **12.40** | 21.70 |
| 1024 | — | **48.00** | 82.25 |

Every painter row is the same phase — `draw_*`, medians of seven samples, reading one pixel
down the quadtree's left spine so the render cannot be optimised away. The 32 and 64 rows were
originally taken from `span_probe`'s own copy of the painter on a single chunk, which is not
the client's region and not the same measurement; `draw_32` and `draw_64` were added so all six
rows come from one phase.

`frame_held` at 128 falls from 14.05 ms to 1.35 ms and `frame_edited` from 16.05 ms to
3.35 ms.

### **One thread draws a frame faster than eight, by 1.75x at every size**

That ratio is flat from 128 to 1024, which is the signature of contention rather than of a
workload that parallelises: the sort and the per-face projection do parallelise, and the
writes into the one shared frame array do not, and every thread that touches the same array
node pays for it. More threads make it monotonically worse, not merely no better:

| threads | `draw_256` | `draw_512` | `frame_held` |
|---|---:|---:|---:|
| **1** | **3.60** | **12.40** | **1.35** |
| 2 | 5.60 | 20.30 | 1.95 |
| 3 | 5.90 | 20.90 | 2.15 |
| 4 | 5.95 | 21.00 | 2.25 |
| 8 | 6.40 | 21.70 | 2.48 |

The thread count is a launch flag the runtime reads before `main`, so the client cannot set
it. It can read it, so it prints a warning when it is above one, and the epilogue says how to
launch it right.

This is also why 512 became affordable at all: at eight threads it measured 21.30 ms and
missed the tick by 4.6 ms, and on one thread it is 12.20 ms with 4.4 ms of slack.

### Live, under a real X server

`lab/native/client-probe/run-fps.sh --size=N --threads 1`, 600 presented frames each, Xvfb,
`window_pace` capping at 60:

| size | frames | elapsed | FPS |
|---|---|---|---|
| 128 | 600 | 9986 ms | **60.08** |
| 256 | 600 | 9988 ms | **60.07** |
| 512 | 600 | 9998 ms | **60.01** |
| 1024 | 600 | 28933 ms | 20.73 |

The 1024 live number cross-checks the harness: the table's 480 tenths is 48.03 ms, which is
10000 / 480 = 20.8 FPS, against 20.73 measured.

### 1024 is the open one, and three attempts to close it that did not work

48.00 ms against a 16.67 ms tick, so 2.9x away. The obvious suspect was the two costs that
scale with `size * size` — the quadtree fold and the sky pre-fill, a million operations each
— and the sky pre-fill is not one of them: `sky_1024` is **0.25 ms**, 0.5% of the frame.

**Back-face culling: implemented, measured, reverted.** `emit_sides` labels the six sides
0/+x, 1/+y, 2/+z, 3/-x, 4/-y, 5/-z, so a face is back-facing exactly when the eye is on the
inside of its plane, and its own block's front face covers the same pixels from nearer.
Dropping those faces before the projection is textbook:

| size | without | with | gain |
|---|---:|---:|---:|
| 128 | 1.35 | 0.93 | 1.45x |
| 256 | 3.55 | 3.05 | 1.16x |
| 512 | 12.20 | 11.60 | 1.05x |
| 1024 | 46.25 | 45.75 | **1.01x** |

It is out because of the last row and because of what it costs. Back faces were already nearly
free — their spans come out empty or a pixel wide — so at the one size anyone would want the
cull for it buys 1%. And it is *wrong* when the eye is inside a solid block, which culls all
six faces of the block the camera is standing in: the `inside` gate camera went from 131 wrong
blocks and 0 missing to 156 and **93 missing**. The assumption that makes it safe is that the
camera is outside the geometry.

**Reciprocal slopes: implemented, measured, reverted.** `crossing_x` divided by `by - ay` once
per edge per row, and that divisor is loop-invariant over a face's rows, so the arithmetic was
rewritten to divide once per face into a `Ramp` of four slopes and multiply per row. On paper
that is four divides per face instead of four per face-row, which at 1024 over a region of
about 26000 faces is ~100000 divides instead of ~3 million. The measured medians were
**identical at every size** (1.38 / 3.60 / 12.40 / 48.00 against 1.35 / 3.55 / 12.20 / 46.25,
all within run-to-run variance). The C backend had already hoisted the invariant division. An
operation count is not a cost, and the gate output was byte-identical both ways, so there was
nothing to gain and a `Ramp` type with four accessors and a parameter through three functions
to carry.

**What is left is overdraw.** One chunk's spans at 1024 cover 5.46 million pixels
(`span_probe`'s `spanpixels`) against a frame of 1.05 million, so the painter writes each pixel
about five times over on one chunk and the region has roughly sixteen times the faces. The
remaining ~39 ms is the writes, not the arithmetic that finds them — which is consistent with
both failures above, since neither one reduced the number of writes. Cutting it needs
occlusion culling rather than painter's-algorithm ordering: a hierarchical depth buffer that a
whole sub-quad can be rejected against, so distant terrain stops being rasterised behind
nearer terrain. That is a real piece of work and it is not started. 1024 is recorded here as
measured and not reached rather than as a target with an estimate attached.

### Two defects found in the measuring harness, again

**`Array.new`'s third argument is a depth, not a count.** `d = 1n + p` builds a tree whose
halves are `T^p`, so `d = 11n` holds 8192 cells and a 32x32 frame is `5n`, not `1024n`.
Passing the element count fail-stops with "an array past the deepest block class 31", and
passing too few wraps *silently*, because both `Array.get.at` and `Array.swap.at` mask the
index with `n - 1`. The painter measured this the hard way: it produced a plausible picture,
at the wrong size, with no error.

**Two phases read 0.00 ms** in their first versions, for one reason worth recording: `draw_*`
because `Image.drop` on an unread image leaves the whole fill as dead code, and `sky_*` because
the filled array was threaded forward and never read. Reading one pixel is what forces the
work, and reading one pixel is what the runtime does to present a frame anyway. A phase that
reads zero has measured nothing, and both of them looked like enormous wins.

## Session seven: the painter was drawing the wrong picture

Session five priced the painter at about 6.5 ms against the walk's 44.33 ms at 256 and
concluded that the painter was the way to 256. **That conclusion was drawn from timings
without ever checking that the painter drew the same image as the walk**, which is the
cheapest available check and was not run. It does not. This session runs that check, finds
out why, fixes it, and re-prices it.

The gate is `lab/native/client-probe/painter_agree_test.bend`: it scores the painter and the
walk against the ray renderer on five isolated fixtures and eight scene cameras, and it
reports rather than dies, so one camera's failure does not hide the next one's numbers.

### It fails totally, and only on some cameras

| camera | painter wrong @128 | walk wrong |
|---|---:|---:|
| `down` | **0** | 0 |
| `level` | 16384 (every pixel) | 0 |
| `inside` | 16384 | 0 |
| `ceiling` | 16384 | 0 |

A renderer with a small coverage defect cannot be perfect on one camera and wrong on every
pixel of another. `phantom=0` throughout, so nothing was being invented where the ray sees
sky: every wrong pixel was solid-versus-solid, a *different block*.

### Two hypotheses, both wrong

**Overlap.** The obvious explanation is that the painter fails where many faces cover one
pixel, since `down` looks steeply down where visible faces barely overlap. Counting how many
faces' spans cover each pixel, per camera, refutes it outright:

| camera | painter wrong | pixels with several faces | deepest pixel |
|---|---:|---:|---:|
| `down` | **0** | **954** | 8 |
| `level` | 16384 | 992 | 6 |
| `ceiling` | 16384 | 992 | **4** |
| `inside` | 16384 | 976 | 6 |

`down` is the most overlapped camera and the only perfect one; `ceiling` is the least
deeply overlapped and totally wrong. Overlap anti-predicts the failure.

**Ordering.** Refuted by printing what each renderer named at the first disagreements. At
`level`, `py=0`:

```
px=0  ray=44 walk=44 painter=40
px=1  ray=44 walk=44 painter=117
px=2  ray=44 walk=44 painter=117
```

Keys are `block * 8 + dir`, so the ray and the walk both say **block 5** and the painter
says block 5 dir 0 at the left edge and **block 14** dir 5 everywhere else. It is not
choosing the wrong face of the right block; it is stamping a different block, and a
different one again at the row's first pixel. That is a coordinate error, not an ordering
one.

### The cause: `project` clamps the near plane instead of clipping against it

`native/face.bend:467`:

```python
+safe_depth = F32.max(depth, 0.0001)
```

A corner behind the eye has negative depth, so its screen coordinate becomes
`half + focal * lateral / 0.0001` — tens of millions of pixels. `crossing_x` interpolates
that against a normal corner, `half_open_bounds` clamps the result into `[0, size-1]`, and
the span covers **the whole row**. `fill.go` rasterized every face unconditionally, so one
such face paints a full-width band over everything behind it.

Counting the straddling faces per camera settles it, and the correlation is monotone:

| camera | faces | straddling the eye | painter wrong |
|---|---:|---:|---:|
| `cube` | 6 | **0** | 3 of 1024 |
| `row-8` | 34 | **0** | 12 of 1024 |
| `down` | 1654 | 91 | **0** |
| `spawn` | 1654 | 750 | 6400 of 16384 |
| `level` | 1654 | 932 | 16384 |
| `inside` | 1654 | 1078 | 16384 |
| `ceiling` | 1654 | 1415 | 16384 |
| `cube-away` | 6 | **6** | 1024 |

Zero straddling faces scores 0.3-1.2% at every size. `cube-away` is the pure case: the
camera faces away from the cube, all six faces straddle, every pixel is wrong.

`down` has 91 straddling faces and is still perfect, so it is not "any straddle fails" — a
straddling face only corrupts the rows it lands on, and looking steeply down those rows
fall outside the frame.

### Fixing it: skip, and then what skip costs

Skipping a face whose corner is behind the eye is one line. The walk resolves such a face
exactly, by intersecting the pixel's ray with the face's plane (`face_contains_hit`), so it
keeps the sliver that is genuinely visible — which means skipping is not free, and the
question is whether the sliver is more than 1% of the frame.

The gate answers it by scoring the same disagreement twice, at `block * 8 + dir` and at
`block` alone. That split is not a convenience: it separates "a wrong block is a hole in
the image" from "another face of the right block is a shading difference", which need
different fixes.

| camera | strict wrong | wrong block | face-only | phantom |
|---|---:|---:|---:|---:|
| `spawn` 32 / 64 / 128 | 64 / 128 / 256 | **0 / 0 / 0** | 64 / 128 / 256 | 0 |
| `ceiling` 128 | 256 | **0** | 256 | 0 |
| `down` 128 | 0 | **0** | 0 | 0 |
| `cube-away` 32 | 0 | **0** | 0 | 0 |
| `level` 128 | 205 | **83** | 122 | 0 |
| `inside` 128 | 521 | **131** | 390 | 0 |

The residual is exactly proportional to `size` (64 / 128 / 256), not to `size * size`, so it
is a 1-2 pixel ring on the frame border — the visible sliver of the straddling faces.

### The gate the painter is held to

`native/face_test.bend:586-590` limits three classes separately at `pixels / 100` each — the
wrong-block rate, the spurious-block rate, and the block-difference rate — and deliberately
does **not** limit `face_only`, the pixels where both renderers name the same block but a
different face. That omission is deliberate: another face of the right block is a shading
difference on that block, not a wrong image.

The painter gate originally used the strict `block * 8 + dir` identity, which is the union
of wrong-block and face-only. That was stricter than the project it was measuring against,
and it made the painter look broken for pixels where the image is right. It now applies
`face_test.bend`'s gate, and still prints `face_only` so the residual is visible rather than
hidden by the choice of gate.

Against that gate the painter passes everywhere except two places, both real:

| camera | size | wrong block | limit | verdict |
|---|---|---:|---:|---|
| `spawn` | 32 / 64 / 128 | 0 | 10 / 40 / 163 | pass |
| `down`, `cube-away`, `ceiling` | 32 / 128 | 0 | 10 / 163 | pass |
| `level` | 128 | 83 | 163 | pass |
| `inside` | 128 | 131 | 163 | pass |
| `row-8` | 32 | 12 | 10 | **fail** |
| `level` | 32 | 25 | 10 | **fail** |
| `up` | 128 | 2075 | 163 | **fail**, and unfair: see below |

`up` puts the eye at y=8, inside terrain, so every ray starts in solid and *the walk itself*
scores 16384 wrong. It is kept and documented rather than hidden.

### The rest of the residual is a per-edge coverage bias, not the span's placement

The `row-8` and `level`-at-32 failures happen with **zero** straddling faces, so they are
the rasterizer. Three rounding rules for the span's two bounds were measured:

| rule | cube | row-8 | spawn wrong blocks | `inside` |
|---|---:|---:|---:|---:|
| `ceil(e4) .. floor(f4)` | 3 | 12 | **0** | **131** |
| `ceil(e4) .. ceil(f4)` | 7 | 26 | 0 | 521 |
| `ceil(e4-.5) .. floor(f4-.5)+1` | 3 | 26 | 104 | 199 |

The third is the derived one: `ray_for` samples pixel `px` at `px + 0.5`
(`native/voxel.bend:81`) while `Face.project` emits `half - 0.5 + focal * lateral / depth`
(`native/face.bend:468`), so `project.sx` is the walk coordinate plus 0.5 and the span
should be `[ceil(e4 - 0.5), floor(f4 - 0.5) + 1)`. Deriving it and measuring it disagree.
The residual is therefore not where the window sits but a fraction-of-a-pixel bias on each of
a quad's four edges; moving the window trades one edge's loss for another's. The shipped rule
is the first, which is the best of the three and scores 0.3% on the plain cube.

Clamping each corner into the frame — the same convention `Face.shoelace2` applies to these
quads, and the cheap half of a near-plane clip — is much worse: `spawn` 0 -> 6344, `ceiling`
0 -> 16257, `level` 83 -> 16177. The clamped hull of a face the eye is inside of covers
nearly the whole frame, which is the original defect under another name.

Recovering the sliver properly needs a real clip against the near plane, which yields a
polygon the four-corner span arithmetic cannot describe. That is the honest remaining
correctness work and it is not done.

### The painter, priced with the fix

`lab/native/client-probe/span_probe.bend`, the client's own spawn camera and region,
`--gpu off`, 8 threads:

| size | fill ms per frame | walk render ms | ratio |
|---|---:|---:|---:|
| 128 | **0.58** | 14.00 | 24x |
| 256 | **0.86** | 44.33 | 52x |
| 512 | **2.17** | 152.50 | 70x |
| 1024 | **5.80** | not measured | — |

So 256 is not marginal: 0.86 ms of fill inside a 16.67 ms frame. The span arithmetic is
0.49 ms of it and the rest is the per-pixel writes. Skipping the straddling faces also makes
the fill cheaper, because at `level` 932 of 1654 faces are skipped.

### Two defects in the measuring harness itself

Recorded because both produced confident wrong readings first.

**`first_bad` overflowed.** It packed `py * 1000 + px` above bit 24, which wraps `U32` for
any frame larger than 32. `first_bad=3724552704` was a wrapped number, not a coordinate, and
nothing could be concluded from it. It is now two byte-wide fields plus a flag bit.

**Record patterns bind positionally.** Adding a field to `Tally` and inserting its name at
the end of the patterns left `tally_walk_same` returning the new field: the sixth name in the
pattern bound the sixth *field*, not the sixth named field. The symptom was a column reading
`0` while `wrong=0` on the same line, and it moved in lockstep with the new field's value —
which is what identified it. The gate's own verdicts read `paint_block` and `paint_only`,
which landed on the right fields, so the pass/fail results above are unaffected; two printed
columns were wrong and are now fixed.

## Session six: how much of the frame is one colour

Session five ended with the read-back at 79 ms and a claim that the fix — testing a node's
uniformity *before* its fan-out, so a uniform node never forks — was not expressible. The
claim was about a strided walk, and **it was wrong**. This session measured the thing the
whole design turns on and corrected the claim.

### The measurement

`span_probe.bend` now walks the painted frame once and counts the blocks that are a single
colour, at two block sides. A node of the quadtree whose pixels are all one colour can be one
`Pix`: the runtime's `window_sq` only descends into a constructor, so a `Pix` at any level
fills its whole block, and a shallower tree is the same picture. So the count is the fraction
of the tree that collapsing can remove.

| size | 8x8 blocks uniform | 32x32 blocks uniform |
| --- | ---: | ---: |
| 128 | 45 / 256 (17.6%) | 0 / 16 |
| 256 | 434 / 1024 (42.4%) | 0 / 64 |
| 512 | 2645 / 4096 (64.6%) | 0 / 256 |
| 1024 | **12800 / 16384 (78.1%)** | **0 / 1024** |

The control is a frame of one colour at side 8 over 64 pixels, which reports **64/64**. A walk
that only ever examined the first block could not pass that, so the counts are counts.

**78% of the frame's 8x8 blocks are one colour at 1024, and not one 32x32 block is.** Both
halves of that matter and they pull opposite ways.

The first is the good news, and it is the whole ballgame: the frame is mostly large flat
regions, so collapsing at 8x8 granularity removes most of the tree. A 1024x1024 frame has
1,398,100 nodes; 16,384 of them are level 4, and a level-4 node that collapses takes 1,365
nodes beneath it with it. Collapsing most of level 4 takes the tree from 1.4 million nodes to
a few hundred thousand, which is the difference between 79 ms and something that fits.

The second explains why the first is not simply available. A voxel face is shaded per
direction, so two adjacent blocks of the same material are different colours, and a 32x32
block at this camera always straddles a face boundary. Uniformity is a property of a *run* of
one face in screen space, and a face is 1 to 2 pixels across at 1024 and 30 at 128. **This is
also why the 8x8 figure climbs with resolution while the 32x32 figure stays at zero**: as the
resolution rises, more of the frame falls inside a single face.

So the collapse has to be tested at 8x8, which is level 3 in the quadtree, and the tree below
level 4 is where the nodes are. That is the right shape. It is not available for free, and the
reason is narrower than session five said.

### The corrected constraint

A handle threads through a strided walk perfectly well. The walk above is one flat pass with
two counters, the read pair carried as a *parameter* and the next pixel passed as a call in
argument position, and the block boundaries done in arithmetic rather than a nested loop. What
the language will not do is let a caller open a call's result, and that is the actual
obstacle:

- the scan's answer is a pair — uniform or not, and the colour if so;
- the fan-out's four branches are the recursion, and each branch's call needs that answer as
  arguments;
- a parent that splits the scan's pair to supply them needs a helper, and a helper that opens
  the scan and then fans out is a cycle, because the fan-out is the recursion.

The way round it is to make the scan return **one** `U32` — the colour if the region is
uniform, a sentinel if not — so the caller can use it twice without splitting it, and to have
the parent pay one extra `Array.fork` per child so it still has a handle to hand the child
after spending one on the scan. That is four forks per node instead of twelve, and uniform
nodes pay none of it.

Neither half of that is written. What is written is the measurement and the corrected
constraint, and the two together are a smaller and more specific thing than session five left
behind.

### The numbers this session did not change

Nothing about the painter's cost moved: order 0-1 ms, fill 2.4 ms, fold 79 ms at 1024. The
fold is still 79 ms because the collapse in it is still bottom-up, and the fork count is still
twelve per node. `fold_check` still reports 99, meaning every depth from 0 to 8 passes, and
the uniformity control reports 64/64.

## Session five: the painter, priced end to end

Session four established that the per-pixel bucket walk cannot reach 1000x1000: it
charges 119 candidate visits per pixel, and 1,048,576 pixels would need 3.0 seconds of
sequential work against a 16.67 ms tick. It also established the one number that said a
different renderer *could* get there — a constant `Image` quadtree build at 1024x1024 is
4.50 ms, so the output is not the wall. What was missing was every term between the world
and that quadtree, and this session priced all three of them.

The answer is that 1000x1000 is not reachable, and the reason is narrower and more
useful than "the walk is too slow": it is the read-back, and it is the *handle*, not the
pixels.

### The three phases

`lab/native/client-probe/span_probe.bend` now runs a whole painter and times each phase
separately, because they are separately improvable and only the sum is the answer.

| size | order | fill | fold | total | against 16.67 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 128 | 0-1 | 0.26 | 2 | ~2.3 | 14% |
| 256 | 0-1 | 0.49 | 5-6 | ~6.5 | 39% |
| 512 | 0-1 | 1.1 | 20-21 | ~22 | 132% |
| 1024 | 0-1 | 2.4 | 78-79 | ~81 | 486% |

All in milliseconds at the client's own spawn camera over 1,654 faces. `fill` is timed
over 200/100/30/10 iterations and divided; `order` and `fold` are timed once each and are
not divided, because neither is per-iteration work — a comment in the probe says so, and
an earlier reading of that same line as a per-iteration figure is what made the fold look
like 7.9 ms instead of 79 and briefly made the whole thing look solved.

**`fill` — 2.4 ms at 1024.** 111,142 spans covering 5,460,360 pixels, which is 5.2x
overdraw. The cost is one projection per face, one span per scanline, one array write per
pixel, and nothing else. No depth test and no ordering, deliberately: it is the cheapest a
painter can be, so the two phases that are not free are priced separately rather than
folded in here.

**`order` — 0-1 ms at every size.** 1,654 faces sorted back to front once per frame by
`List.sort` on each face's farthest corner in camera space. This is the phase that lets the
painter drop a depth buffer, and the geometry says it can: two axis-aligned unit faces on
the integer lattice never interpenetrate, they share at most an edge, and the projection
of a plane is injective, so two faces either do not overlap on screen at all or one is in
front of the other across the whole overlap. Order once, and the last write to a pixel is
the nearest face covering it. The *farthest* corner is the key rather than the centre
because a centre key mis-orders two overlapping faces whenever the nearer face's centre is
further from the eye than the farther one's, which is what a face at a grazing angle does.
The face count does not grow with resolution, which is why this is flat while the other
two are quadratic.

**`fold` — 79 ms at 1024.** Reading the `size * size` frame back into the `Image` quadtree
`Window.frame` takes. This is the wall, and the interesting part is why.

### The fold's 79 ms is not pixels

A constant build of the *same* tree — 1,048,576 `Pix` and 349,525 `Qua` — is 4.50 ms, and
the reads are 0.20 ns a pixel, so 1,048,576 of them are 0.2 ms. 4.5 + 0.2 is 4.7 ms, and
the fold measures 79. The 75 ms in between is entirely the fan-out.

The fan-out is the interesting part, and it is a language constraint rather than an
algorithmic one. `const_image` builds a quadtree with a four-way parallel let, handing each
branch the same `+color: U32`; `+` means "may be used many times" and costs nothing to
duplicate. `Array` is a `Type`, and `+` is for `Data`, so **one array handle cannot be
handed to four parallel calls at all**. Nor can it be threaded through four sequential
calls: a pair a call returns cannot be destructured by its caller, and the helper that
would do the destructuring would have to call back into the fold, which is a cycle this
language does not have.

`Array.fork` is the way round both, and it is what the fold uses: a second handle to the
same cells in O(1), four handles as two nested products, four branches each with its own.
But a handle is a refcount on cells that every branch shares, so a fork inside a parallel
let is an atomic on one cache line that eight cores are writing. Twelve forks per node
over 1.4 million nodes is 16.8 million contended atomics, and 75 ms is what they cost.

**The measurement that isolates this**: `output_probe.bend`'s constant build and
`span_probe.bend`'s fold produce the same shape of tree over the same number of nodes, and
differ in exactly two ways — the constant is `Data` and the array is a `Type`, and the
constant's pixels are free to share while the array's are not. 4.50 ms against 79 ms is
the price of that difference, and it is 17x.

Three forks per node is the floor for a four-way fan-out over an unshareable value. The
fold reaches twelve because each of the four branches forks its own three, and the
language will not let it do better: `fork4` returns four handles as a value, but a `match`
may not be preceded by a destructuring statement, so those four handles cannot be named
inside the def that matches the level. Every shape that would name them needs a helper
that calls the matcher back.

### Collapsing uniform nodes, and why it did not help

A `Qua` whose four children are all one colour can be a single `Pix`, and the runtime
reads a `Pix` at any level by filling the whole block with it — `window_sq` only descends
into a constructor — so a shallower tree is the same picture. That is implemented
(`Flat` carries the first pixel's colour and a uniformity flag alongside the image) and
measured: **79 ms before, 79 ms after**.

The reason is the direction of the test. `Flat` collapses bottom-up, so a node's four
children have already been fetched — and forked — by the time the node learns they agree.
Bottom-up collapsing removes allocations, and the allocations were never the cost.

To save the forks the test has to come *before* the fan-out: scan the node's whole region,
and if it is one colour, do not fork and do not recurse. A voxel frame at this camera is
mostly sky and mostly flat wall, so that would remove most of the tree. This is the one
thing between the current fold and a 1024x1024 frame, and it is blocked by a language
constraint of the same family as the one above: the scan is a *strided* walk — `2^level`
rows of `2^level` pixels, one row's worth of stride between them — and a strided walk
cannot thread a linear handle through a loop here. The counter and the read pair would
both have to be matched in one `match`, and a product is not a pattern, so the pair cannot
be bound in the pattern that matches the counter.

### The gate, and that it can fail

The read-back's index arithmetic is the one part of this with no visible failure when it is
wrong: a mis-addressed pixel still produces a full-depth quadtree, still fills the window,
and still has a fingerprint. So it is gated. `frame_of` fills a frame with
`tint(index) = index * 2654435761 + 7`, which is injective, the fold runs, and every
pixel is read back out of the resulting `Image` and compared against `tint(y * size + x)`.
Any swapped quadrant, wrong stride or wrong tree depth moves a pixel and fails.

`fold_check` reports the last depth that failed, and prints 99 when every depth from 0 to 8
passes. The check was confirmed able to fail before being believed: shifting the expected
index by one makes it report 8, the deepest depth checked.

Two things about writing that gate are worth recording because both looked like the fold
being wrong. `Array.map` is the obvious way to fill a frame with `tint(index)` and is the
wrong one — it allocates `Array.new(U, log2(n), v)`, which is `n * n` slots, so at
256-square it asks for four billion of them and the first version failed at exactly depth 8
and no other. And a first attempt filled `4 * depth` entries instead of `2^(2*depth)`, which
failed at every depth and was the more honest of the two failures.

### What this session changes

Nothing ships. The resolution stays at 128x128, which presents 60 frames a second. What
changed is that the reason is no longer "the walk is quadratic" but a specific 17x charge
on one operation, with a specific next step and a specific reason the next step is hard.

A painter would be a large win where it fits: at 256x256 it is ~6.5 ms against a walk's
45.67 ms, which is 21.33 FPS. So 256x256 at 60 Hz is a real target for a renderer that
avoids the contended fan-out, and 512x512 is not (132% of the tick) unless the fold's
uniformity test can be made expressible.

## Session four: whether 1000x1000 is reachable at all

The goal for this session was to raise the resolution until the client presented 60
frames a second at 1000x1000. Every earlier session's answer was a resolution the
client could hold, and the last of them measured 256x256 at 21.33 FPS, so the
question here was not "how do we get a bit more" but "what is the ceiling, and what
architecture would reach it". Three measurements answer the first half and one
proposal answers the second.

**The answer to the first half is that the walk cannot be made to reach it.** The
session did not find a way to raise 256x256, and the reason is structural rather
than a shortage of tuning: the walk's cost is `pixels x candidates-per-pixel`, and
at 128x128 the second factor is already 119. Reaching 1000x1000 means 1,048,576
pixels, so at the measured 119 candidates and 24 ns a step the walk would be 3.0
seconds of sequential work per frame. That is 180x the 16.67 ms tick. No constant
factor gets there, because the constant factor that matters — the candidates per
pixel — is the box's area over the pixel count, and it is the *shape* of the
geometry that sets it, not the tile edge or the builder or the thread count.

### The output stage was never the wall, and it is cheap at every depth

`lab/native/client-probe/output_probe.bend` builds and releases an `Image` quadtree in
one colour, with no face, no projection, no bucket and no walk, so it prices the
floor under every resolution: one `Pix` per pixel and one `Qua` per four of them,
built and freed in Bend, then walked once more in C by `window_sq`. Per frame at
the client's own eight threads:

| depth | size | build + release |
| --- | ---: | ---: |
| 5 | 32x32 | 0.60 ms |
| 6 | 64x64 | 0.55 ms |
| 7 | 128x128 | 0.70 ms |
| 8 | 256x256 | 0.83 ms |
| 9 | 512x512 | 1.67 ms |
| 10 | 1024x1024 | **4.50 ms** |

**The whole output path costs 4.50 ms at 1024x1024, against a 16.67 ms tick.** That
is the finding that makes the rest of this session worth doing: 1000x1000 has 12
milliseconds of headroom before a single face is looked at, and this file had been
carrying the assumption — never tested, always inherited — that the output is where
high resolutions die. It is not. It is where 27% of the budget goes at the target
resolution, and 4% of it at the one the client ships.

That number also bounds the painter's read-back: whatever fills the frame has to be
read back out and folded into this same quadtree, so the quadtree is not a one-off
cost the painter escapes. At 1024x1024 it is 4.50 ms, and the painter's own fill has
to fit in what is left.

### Random access is free at these sizes, which removes the objection that killed
### rasterising once

Earlier in this file, rasterising was rejected partly because the only random-access
structure Bend 2.0.32 offers is an `Array`, and "an `Array` is a persistent tree
whose `set` and `get` both rebuild the path". That is true of the shape and it was
decided on the shape. `lab/native/client-probe/array_probe.bend` prices an actual
`Array` touch at the sizes a frame needs — in place, walked in index order, which is
what a scanline fill and a read-back both do. 1,048,576 writes at depth 20:

| | 40 rounds | 400 rounds | per write |
| --- | ---: | ---: | ---: |
| `Array<U32>` write | 9 ms | 99 ms | **0.24 ns** |
| `Array<U32>` read | 8 ms | 83 ms | **0.20 ns** |

Twenty levels of descent for a quarter of a nanosecond is not a tree walk; the
runtime's arrays are a flat block with an in-place rewrite, and the earlier
conclusion was wrong for the same reason the `boxarea` figure was wrong — it was
read off the type rather than measured on the value. The costs that measurement
found instead are in the record:

- a read walk that reads and discards measures **0 ms**, because the runtime drops
  it. The walks above fold every value they read into a digest. A first run of this
  probe reported 0 ms for 400 million reads for exactly that reason;
- `Array.new` takes the depth as a `Nat` and a `U32.to_nat` around it does not
  compile — the signature is `Array.new(-T: Data, +d: Nat, +v: T)`;
- an `Array` cannot hold an `Array`, so a colour buffer and a depth buffer cannot
  ride in one record. They are threaded as separate parameters.

### A painter's algorithm is 30x less work than the walk, and that is measurable
### before it is built

The walk is charged one candidate per face whose *bounding box* overlaps a pixel's
tile, and it rejects the ones that are not there. A painter asks a different
question: for each face, which pixels does its own quad cover? `Face.quad_area` in
`lab/native/face/face.bend` answers it by the shoelace over the four
projected corners, at the client's own camera and region:

| | pixels |
| --- | ---: |
| faces | 1,654 |
| the walk's boxes, `clip_area` | 1,547,675 |
| the walk's candidates | 1,957,888 |
| the faces' own quads, `quadarea` | **50,102** |
| the canvas | 16,384 |

**31x.** The geometry the walk pays for is thirty-one times the geometry there is,
and the gap is the box's waste over the quad: a face seen at a grazing angle is long
and thin, and a bounding box around one is nearly square. This is the first
measurement in three sessions that moves the work by an order of magnitude rather
than by a factor, and it says the 119-candidates-per-pixel figure is an artefact of
using boxes, not of the scene.

Two things had to be fixed before that number could be believed, and both are the
kind this file has already recorded twice:

- **The shoelace over faces that cross the eye plane wrapped the total.** The first
  run reported `quadarea:4193030645` for a 16,384-pixel canvas — a 255,000x
  overcount. A corner behind the eye projects to a coordinate of tens of thousands of
  pixels, and one such corner makes its edge term enormous. Clamping every corner
  into the frame before the shoelace, and counting the crossing faces separately
  (`behind:True` at this camera), gives 50,102. This is the third instance of the
  same mistake in this file: **a number that has not been counted looks attributed
  the moment it is printed.**
- **`F32.to_u32` of a negative floor is not a small number.** A face wholly above or
  below the frame gives a span whose bounds are negative, and converting one without
  clamping produced a four-billion-pixel span that hung the probe. Both bounds are
  now clamped as floats before they become pixel indices.

### What the painter costs, measured at every resolution

`lab/native/client-probe/span_probe.bend` is the painter's algorithm, built for
measurement: for each face it projects the quad, walks the quad's scanlines, computes
each line's x-range from the two edges that straddle it, and writes the span into a
flat `Array<U32>` frame. There is no depth test and no ordering, which is deliberate:
this is the cheapest a painter can be, and it is the right shape for asking whether
the term underneath a depth test is affordable. Per fill, at the client's own camera
and 8 threads:

| size | spans | span pixels | fill |
| --- | ---: | ---: | ---: |
| 128x128 | 14,312 | 97,378 | **0.26 ms** |
| 256x256 | 28,116 | 361,256 | **0.46 ms** |
| 512x512 | 55,798 | 1,391,252 | **1.00 ms** |
| 1024x1024 | 111,142 | 5,460,360 | **2.30 ms** |

Against the walk, at the size the client ships:

| | walk `render` | painter fill |
| --- | ---: | ---: |
| 128x128 | 14.40 ms | 0.26 ms |
| 256x256 | 44.67 ms | 0.46 ms |

**At 1024x1024 the painter's fill is 2.30 ms and the output quadtree is 4.50 ms, so
6.80 ms of the 16.67 ms tick is accounted for before any depth test.** The walk
would need 3.0 seconds. That is the whole finding: the target resolution is not out
of reach, it is out of reach *by this renderer*, and the renderer is the thing that
has to change.

Two numbers in that table are worth reading carefully, because they are the ones
that would sink the idea if they were wrong:

- **the span pixels are 3.3x the canvas at every resolution.** A painter overdraws,
  and 3.3x is the overdraw this scene has. It does not grow with resolution —
  97,378 / 16,384, 361,256 / 65,536 and 5,460,360 / 1,048,576 are all 5.9, 5.5 and
  5.2 — which is the signature of a painter's cost being proportional to *geometry*
  and not to the frame. A renderer whose cost grew with resolution would be a
  different proposal with a different answer;
- **the spans roughly double with each doubling of the frame** (14,312 to 28,116 to
  55,798 to 111,142), so the per-span setup cost — four edge intersections and their
  comparisons — is paid about 111,000 times at the target. That is the term a painter
  can be made faster on, and it is 111,142 units of work against 5,460,360 pixel
  writes.

### What it would take, and what is not yet true

A painter that is correct needs three things this probe does not have, and the
arithmetic above is a lower bound rather than a forecast:

1. **a depth test**, one compare and one conditional write per span pixel. At
   0.24 ns per array write, a second array and a compare is well inside the measured
   fill's margin, but it has not been measured;
2. **back-to-front ordering**, because painter's algorithm is wrong without it.
   The face list is already in scan order and would need a sort by depth, which is
   `1,654` elements and not measured either;
3. **the read-back into the quadtree**, which the 4.50 ms output figure does not
   include: `const_image` there builds from a constant, and a painter's fold reads
   1,048,576 values out of the frame instead.

So: **1000x1000 at 60 Hz is reachable on this machine, and the renderer has to be a
painter's algorithm rather than a per-pixel bucket walk.** The three measurements
that decide it are the 4.50 ms output floor, the 0.24 ns array write, and the
2.30 ms fill. None of them is a guess and all three are reproducible with the probes
this session added. What is not yet done is the depth test, the ordering, and the
read-back, and until those three are built and measured the claim is an upper bound
on a design, not a shipped renderer.

### The client ships 128x128 and that has not moved

`lab/native/client-probe/run-fps.sh`, 600 live frames at the shipping size, five runs in
one sitting:

| run | frames | elapsed | FPS |
| --- | ---: | ---: | ---: |
| 1 | 600 | 10,048 ms | 59.71 |
| 2 | 600 | 10,002 ms | 59.98 |
| 3 | 600 | 10,009 ms | 59.94 |
| 4 | 600 | 10,007 ms | 59.95 |
| 5 | 600 | 12,103 ms | **49.57** |

**Runs 1 to 4 sit on the ceiling. Run 5 does not, and it is reported rather than dropped
because the goal asks for every size to be at 60.** A 49.57 is 111 frames over ten
seconds, which is not a frame that overran the tick — it is a *lot* of frames that did
not, and the only mechanism that produces that is the host: WSL2 shares eight logical
CPUs with Windows, and a preemption there lands on whichever frames the scheduler was
running. The earlier sessions' maxima of 22 to 30 ms inside `frame_held` — a phase no
phase should be able to exceed — are the same host, measured at the same time. The
honest reading is that 128x128 presents 60 when the host is quiet and can be starved by
it, and that no renderer change fixes a starved CPU.

And the harness the goal is judged on, 21 samples at 8 threads:

| phase | median | against 16.67 ms |
| --- | ---: | ---: |
| `render_32` | 3.25 ms | 19% |
| `render_64` | 6.08 ms | 36% |
| `render_128` | 14.50 ms | 87% |
| `render_256` | 44.67 ms | 268% |
| `render_512` | 158.00 ms | 948% |

The frame is unchanged from the last session and the reason is in the table: the
dig frame still sits at 16.60 ms against a 16.67 ms tick, so there is no headroom to
spend on resolution even if a larger one fit. **Raising the shipping resolution is
not a tuning problem on this renderer, and the honest answer to the goal is that it
needs the rewrite the measurements above justify rather than a bigger window.**

## Session two: what the frame is actually made of

The first session ended with a client that worked and a frame over budget, and
with one claim about the renderer's cost that turned out to be about a path the
client does not take. This session split the frame into its stages, found each
term in turn, and changed four things. The frame went from 10.40 ms to 6.00 ms at
64x64 and eight threads, which is a budget of 96 frames per second to 168 — against
a runtime that presents at 60 and has done all along.

### The stages, at the client's own camera and region

`native/client-probe` was measuring one number for the whole render. Splitting it
at 64x64, edge 16, region 2x2 chunks, eight threads, five samples, before
anything was changed:

| phase | ms | what it is |
| --- | ---: | --- |
| tick | 0.86 | input fold and the player transition |
| region | 0.30 | the four chunks generated |
| faces | 2.08 | the region walked into exposed faces |
| project | 2.17 | the above plus every face projected and clipped |
| grid | 2.80 | the above plus the scatter into the tile grid |
| render | 8.70 | all of it, plus the quadtree fold and the read-back |
| frame | 10.40 | the tick and the render, in the loop's order |

`render - grid` is 5.90 ms, and it is the per-pixel term. So the frame was 23%
world, 8% bucketing, 57% per-pixel, 8% tick, and the tick and the bucketing were
never the problem — which turned out to be half true, because the tick was the
problem once the world was out of the frame.

### The per-candidate allocation

`Best` is a `Data` record, and the walk allocated one of them for every candidate
the box test rejected — the common case by two orders of magnitude, since a
bucket holds every face overlapping its tile and a pixel is covered by the few
whose box contains it. At this camera that is 170 allocations for each of 4,096
pixels, in the loop whose whole job is to reject them. `nearer` built a winner
and a loser before choosing between them, so a covering candidate cost two.

The walk now carries the winning `Screen` and a rejected candidate allocates
nothing. The candidate count the record used to carry is gone rather than
moved: it advanced once per candidate, so it reported `List.length` of the
pixel's own bucket, which `Face.candidate_count` already reports with no
per-candidate work at all. `subpixel_face_test` now asserts against the bucket.

**15% off the walk, 8.6% off the render.** The agreement gate was unchanged
throughout: `same=1024/4096/16384`, `wrong_block=0`.

### The box test was four calls where two would do

`U32.is_le` is a dispatch, so four of them and three `Bool.and` were seven
dispatches per candidate for a four-integer-compare test. The box is now stored
packed — `low = x0 | y0 << 16`, `high = x1 | y1 << 16` — and the pixel packs the
same way once per pixel. The halves occupy disjoint bit ranges with y in the more
significant one, so `low <= pix <= high` as two unsigned compares is exactly
`x0 <= px <= x1 and y0 <= py <= y1`, and splitting it across two `match`es makes
the second compare conditional.

**4.5% off the walk.** That is the honest number, and it is the number that
mattered most, because it is what said the rest of the walk was not arithmetic.

### The walk is the runtime's list step

With the box test, the plane intersection and the quad test all deleted — nothing
left but the traversal, the destructure and the call back into the loop — the walk
measured 17.00 ms against 17.85 ms. **The entire test cost 4.8% of the walk.**

A step of the pinned runtime's own list walk is about 25 ns, and the walk is
695,808 steps. So the render's dominant term is not arithmetic, not candidate
count, and not memory: it is the number of steps, and the only lever is fewer of
them. Every option that reduces steps without paying elsewhere was measured:

| edge | tiles | candidates | walk steps | builder steps | whole render |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | 16 | 695,808 | 695,808 | 21,744 | 7.75 ms |
| 8 | 64 | 488,640 | 488,640 | 134,976 | 9.50 ms |
| 4 | 256 | 423,072 | 423,072 | 423,072 | — |
| 2 | 1,024 | 400,128 | 400,128 | 6,404,096 | — |

The builder is `2 * across * placements` list steps, because a placement costs
two `List.set` calls and `List.set` is linear in the grid's width. It is also the
one term that does not parallelise, so it counts at full weight against a walk
that divides by 3.7. **Edge 16 is the measured optimum, and it is what ships.**

Rasterising, the obvious way to make the walk proportional to the pixels a face
covers rather than to the pixels in its tile, was ruled out here on a number that
has since turned out to be wrong. The `boxarea` fact summed the dead faces, whose
clipped box has `x0 > x1`, so the width underflowed and one term wrapped the total:
3,094,159 against a true 390,799. Rasterising needs 1.78x *fewer* steps than the
walk, not 4.4x more, and it is still the wrong trade — but for the reason given
under "Not rasterisation" below, on allocation count rather than on step count. The
conclusion held; the argument did not, and it took a second session to find out
which part was load-bearing.

### The client rebuilt the world every frame

The `faces` phase was 2.08 ms of a 10.40 ms frame: the whole 20,480-cell region,
regenerated and re-extracted on every tick, to draw a world that had not changed.
The view region is a fixed set of chunks, so walking does not change its cells and
only the camera moves; the camera is read after the world, not before it.

The client now holds the region's exposed faces in its state and rebuilds them
when the edit log says the world did. The key is the log itself and not its
length, because `WorldState.set` replaces an existing entry in place: digging the
same cell twice leaves the log the same size and the cell a different value. The
log holds one entry per edited cell and a session edits a handful, so comparing
it is a few dozen field reads against a 20,480-cell walk.

`render` split into the frame that ships and the frame that follows a dig, nine
samples at eight threads:

| | ms |
| --- | ---: |
| render, world held | 5.90 |
| render, world re-extracted | 8.45 |
| frame, held key | 6.00 [5.65, 6.35] |
| frame, look | 5.95 [5.65, 7.90] |
| frame, world re-extracted | 8.55 [8.40, 18.90] |

The regression is in `native/client_test.bend`: a state that did not move must hand
back the same faces and draw the same frame, and a dig must change both. Both
directions were checked by breaking the invalidation and watching the test fail.

### The collision region was indexed by walking it

With the world out of the frame, the tick was the next term: 0.88 ms, fully serial, at
every thread count. `Player.region_block` read a cell out of a flat
`List<&2, U32>` of the whole region by walking to the cell's index, so a lookup cost
the cell's position and a tick cost the position of the player's own cells. A 2x2
chunk region is 32 x 20 x 32 cells, the player stands about a third of the way down,
and each of the roughly fifteen lookups a step makes walked the same several thousand
cells.

`native/player-probe` already separated the two halves of that cost, and the ratio is
the whole diagnosis:

| region | cells | ms per 32 ticks | ms per tick |
| --- | ---: | ---: | ---: |
| one chunk | 5,120 | 8 | 0.25 |
| 2x2 chunks | 20,480 | 32 | 1.00 |

Four times the cells, four times the cost, with the same number of lookups. That is
the signature of an index, not of the work.

The region is now one list of y-planes, each holding `width * depth` cells in the
region's own cell order, and a lookup is `plane_at` then `list_at`: `height +
width * depth` in the worst case and about `height / 2 + width * depth / 2` in
practice, which is 522 cells against 6,272 for the flat walk. A lookup outside the
region got cheaper too, because it runs off the end of twenty planes and finds an
empty one where the flat walk ran off the end of 20,480 cells.

| | before | after |
| --- | ---: | ---: |
| 2x2 chunks, ms per tick | 1.00 | 0.06 |
| one chunk, ms per 32 ticks | 8 | 0 |
| the client's tick | 0.88 ms | 0.03 ms |

**Sixteen times off the player transition, and the tick is no longer a term worth
naming.** The change is a layout, not an algorithm, and the same layout is what the
browser lane's `collisionRegion` and `mobRegion` build — `web/bend-list.js` grew one
`bendPlanes` so the two lanes cannot spell the region differently.

The regression here was caught by `lab/native/player/player_test.bend` and it
was mine: the slices are taken front to back and consed onto the front of the
accumulator, which leaves them reversed, and the player walked through the wall the
test builds. The fix is the one reverse pass the extraction walks already use, and the
lesson is that a partition has an order whether or not anyone writes it down.

## Session three: the resolution, and the builder that made it fit

The frame was at 5.85 ms at 64x64 with 10.8 ms of slack and a measured ceiling of 60
presented frames a second, so the frame cost had stopped being the interesting number
and the resolution had started being it. 128x128 needed 24.35 ms at the start of this
work. Raising the window is a one-line product decision that the measurements had
already earned, so it was taken — and then it did not fit, which made the last of the
frame cost matter in a way it had not since the world cache.

### Row-major wins where scatter loses, and the size moved that

Raising the window to depth 7 puts eight tiles across a row instead of four, and that
changes which of the two grid builders is cheaper. They are equivalent
(`row_major_matches_scatter` holds that), and they fail in opposite directions: scatter
pays `2 * across * placements` list steps because a placement costs a `List.get` and a
`List.set` and both walk the row they index, while row-major pays no index at all and
re-decides every face's placement once per row instead, at about eight operations a
visit. So a short row favours scatter and a long one favours row-major.

Measured at the client's own region and camera, grid build inclusive of projection:

| tiles across | scatter | row-major |
| --- | ---: | ---: |
| 4 (64x64) | **2.90** | 3.00 |
| 8 (128x128) | 5.40 | **5.10** |

At 64x64 scatter was right and row-major was 0.10 ms behind. At 128x128 the order
reverses, because the scatter's term doubles with `across` while row-major's grows with
one face visit per row. `bucket_faces_with_tile_size` now picks on `across >= 8`, and
the comment carries both measurements so the threshold is not a taste.

That is 1.4 ms off the frame, and it is what turned 128x128 from "fits the bench" into
"holds the live rate":

| | 64x64 | 128x128 before | 128x128 now |
| --- | ---: | ---: | ---: |
| `render` | 5.83 | 15.65 | **13.95** |
| frame, world held | 5.85 | 15.55 | **14.20** |
| frame, world re-extracted | 8.50 | 18.40 | **16.55** |
| live presented FPS | 59.79 | 59.13 | **59.98 / 60.00 / 59.99** |

**The client ships 128x128 at the 60 Hz ceiling**, four times the pixels of the 64x64
that was shipping, at the same presented rate. The live probe is the number that
matters and it is measured over 600-frame runs, not inferred from the benchmark — the
benchmark alone read 59.13 at 128x128, and it was the builder change, not the
benchmark, that found the 0.9 Hz.

### The dig frame, fixed by the same trap a third time

The frame that follows a dig was 16.55 ms over fifteen samples against a 16.67 ms tick,
ranging 16.20 to 17.20 — so a dig dropped a frame some of the time. Its extra 2.35 ms
over the warm frame is the region's face extraction, and the first thing to settle was
whether that extraction was at its floor.

It was not, and for the reason this file has now recorded three times. The extraction
walks the region's layers carrying cursors rather than indexing them, which is careful
work, and it asked for its air defaults through `Maybe.default`:

```bend
+zprow = Maybe.default(&2, List<&2, U32>, List.head(&2, List<&2, U32>, ht), air_row(cells))
+l3_next = Maybe.default(&2, List<&2, List<&2, U32>>,
  List.head(&2, List<&2, List<&2, U32>>, rest), air_layer(cells, rows_deep))
```

**`Maybe.default`'s default argument is built before the call.** The air row is only
wanted on the last row of a layer, and the air layer only past the last real one, but the
walk asks 20 layers times 32 rows either way: 640 times for a 32-cell air row and 20
times for a 1,024-cell air layer, so about 41,000 cons cells per cold frame went into
building air that was then thrown away. `head_layer` in the same file already had the
lazy shape; the fix is to use it, and to add the same one for rows.

| | before | after |
| --- | ---: | ---: |
| `faces`, the cold path | 2.15 | **1.88** |
| `extract`, one chunk | 1.35 | **1.05** |
| frame, world re-extracted | 16.55 [16.20, 17.20] | **16.05 [15.75, 16.50]** |

The estimate for this was 1.02 ms and the delivery was 0.27 ms, so the estimate was 2x
high — `List.replicate` is cheaper per cell than a general cons step. The tail is what
mattered: **16.50 ms against a 16.67 ms tick, where it was 17.20.** Every frame the
client can draw is now inside the tick.

**That is the third time this language has charged for a guard's arguments, in three
shapes** — `Bool.and` in the walk's hit test, `Maybe.default` in the layer walk, and a
`Bool`-guarded `Client.world_built` in the benchmark. The generalisation worth carrying
is that *a guard around a call is not a guard around its arguments*; and where every value
is consumed once, the argument is also built, allocated and discarded even when the guard
is false. Grepping a hot path for `Maybe.default(` and `Bool.and(` and asking "is the
expensive operand on the right of the call?" finds more than reasoning about the
algorithm does.

### And three times the same idea then lost, which is the other half of the lesson

Having found the trap three times, the next three places it looked like it applied were
tried, and all three were reverted. They are worth recording together, because the reason
they lost is the mirror image of the reason one of them won.

| attempt | measured | against |
| --- | ---: | ---: |
| drop the always-true third coordinate of the quad test | 17.90 | 17.80 |
| short-circuit the three coordinates behind `match`es | 54.45 | 52.50 |
| split the colour `Bool.pick` and read the winner once | 53.70 | 52.80 |

(all sequential walk at 128x128, milliseconds; the bare iteration unchanged in each case,
so the runs are comparable)

The depth short-circuit won because **its guard usually fails**: most candidates in a
tile are farther than the running best, so putting the quad test behind the depth test
skips it for the majority. Both of the later ones lost because **their guards usually
pass**:

- the quad test only runs for candidates that already passed the box test *and* beat the
  running best on depth, so its three coordinates usually hold — guarding them skips
  nothing and pays a dispatch;
- the colour's solid arm is three integer divides and a thirty-case palette match, and
  skipping it for a sky pixel saves about 23 cycles per divide while a dispatch is well
  under ten. Two helpers to make the skip possible are two dispatches against the one
  they remove, and `Bool.pick` is one dispatch for both arms.

So the rule that survives contact with the measurements is narrower than "guards are
expensive": **a short-circuit pays when the guarded operand usually fails, and costs when
it usually holds — so the bias of the guarded test decides, and the cost of reaching the
guard has to be smaller than what skipping saves.** Check which way the bias runs before
reaching for it, and price the dispatch you are adding.


### The fix that cannot fire

The dig frame's remaining cost is the region's face extraction, and the obvious further
step is caching the view region's chunks. It was built, measured against the shape it
would actually run in, and removed. The reason is structural, not a trade.

The cold path splits like this:

| part | ms | cacheable per chunk? |
| --- | ---: | --- |
| the view chunk's export | 0.35 | yes |
| the region-wide face extraction | 1.53 | **no** |

A per-chunk cells cache is sound — the extraction still runs region-wide over complete
data, so its answer cannot depend on where a chunk's cells came from — and the arithmetic
put it at **0.26 ms**. That estimate assumed four chunks in view, carried from the
two-by-two region. The shipped view is one chunk: `Frame.view_columns` and
`Frame.view_rows` are both 1, because a two-by-two region costs 19.10 ms against a
16.67 ms budget. With one chunk the cache has a single key, that key is the whole edit
log, and `world_for` only rebuilds when the log has changed — so **every rebuild missed**.
The cache bought a record, a list and a per-edit filter pass in exchange for the same
cells.

The faces cannot be cached per chunk either, and that half was never in doubt: a face on
a chunk seam is decided by the neighbouring chunk. `faces_from_chunks` flattens the
region's chunks, pads it and reads six neighbours per cell precisely so that the seam is
right. A cache of *faces* would have to invalidate neighbours too, and a cache that
misses that shows stale seam faces — wrong rendering at a boundary, not a failed
assertion.

So the quarter of a millisecond is real and unreachable: a per-chunk cache needs a
per-chunk region to pay off, and the frame budget forbids the region. The arithmetic is
recorded at `world_built` so the next reader does not re-derive it. **A cache whose key
space has one element and whose only miss reason is "the thing changed" is not a cache.**

### 256x256 was measured, not assumed, and 60 Hz is out of reach there

The next resolution up is 256x256, and the client was built at it and run:

| | ms |
| --- | ---: |
| live presented FPS | **21.33** |
| frame, world held | 45.85 |
| the walk | 45.65 |
| candidates | 7,828,480 |
| bare iteration, per candidate | 24.1 ns |

**The walk is 99.6% of the frame, and 89% of the walk is the bare cons-cell iteration**
— 7,828,480 candidate visits at 24.1 ns, which is 188 ms of sequential work spread
over four physical cores and their SMT siblings. Reaching 60 Hz needs 16.67 ms, so the
walk would have to get 2.8x faster, and there is no measured lever worth a tenth of
that:

- the step count is 1.27x the faces' live box coverage, and the only way to shrink it is
  a smaller tile edge, which the serial builder forbids (measured under both builders);
- the step cost is 24.1 ns of which the bare iteration is 89%, and that is the pinned
  runtime's list walk;
- the walk is at the parallel knee, and the knee is at 8 threads. Measured across the
  whole pool on this host, `render` median at 9 samples each:

  | threads | 1 | 2 | 4 | 6 | **8** | 12 | 16 |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
  | `render` ms | 55.85 | 32.25 | 19.55 | 15.80 | **13.95** | 14.00 | 14.05 |
  | speed-up | 1.00x | 1.73x | 2.86x | 3.54x | **4.00x** | 3.99x | 3.98x |

  Twelve and sixteen threads buy nothing over eight, so the pool is saturated at the
  host's logical CPU count. The 4.00x is not four physical cores' worth of work: four
  threads reach only 2.86x, and the last 1.40x is SMT hiding the memory latency of a
  pointer-chasing walk. Two siblings per core share one core's load and store units while
  each waits on its own list walk, which is exactly the shape of this workload.
- **`--threads` is load-bearing for 60 Hz, not a tuning knob.** At four threads the
  render is 19.55 ms and the frame misses the budget outright. The runtime defaults
  `--threads` to the CPU count, which is 8 here and is what the client must launch with;
  pinning it lower trades 60 FPS for nothing, since the walk is the whole frame. Worth
  stating because the previous form of this claim — "4.0x on the four physical cores" —
  reads as though four threads suffice, and they do not;
- `--gpu` addresses only `XPutImage` and the pixmap fill, which together are ~0.30 ms,
  and its lane is not even buildable on this host (see below);
- the field of view moves the candidate count 4% over a 96x change;
- a rasteriser would need 1.78x fewer steps but replaces an allocation-free read with
  a depth test that rebuilds a six-level persistent path, and 256x256's 6,159,341
  covered pixels would mean millions of node allocations a frame against the 5,461 the
  frame makes today.

So **128x128 at a measured 60.00 FPS is the largest window this renderer sustains at the
runtime's ceiling**, and it is what ships. The 256x256 build is left in the
investigation log because "it was measured and here is the arithmetic" is worth more
than an assertion.


### The walk was paying for the expensive half of its own hit test

`nearer` decided whether a candidate owned a pixel with one expression:

```bend
decide(Bool.and(Bool.and(F32.is_gt(distance, 0.0001), F32.is_lt(distance, s_depth(win))),
  face_contains_hit(origin, eye, ray, distance)), s, distance, win)
```

The two float compares are cheap. `face_contains_hit` is three multiplies, three adds
and six compares. `Bool.and` evaluates both arguments before the call, so **the quad
test ran for every candidate that reached the plane test, including the ones already
rejected on depth** — and that is the overwhelming majority, because once a pixel has a
winner its depth is the bar every later candidate has to clear.

This is the same trap this file already records twice, in the benchmark's
`Bool`-guarded `world_built` call and in the guarded `frame_fold`: in this language, as
in any, a guard around a call is not a guard around its arguments. It had been sitting
in the shipping hot path the whole time, under a comment about the plane test being
"most of the per-pixel cost".

The fix is the pattern the renderer already uses elsewhere — put the cheap comparisons
in the argument and the expensive one behind a `match` on a parameter:

```bend
def decide.quad(nearer_than_win: Bool, +s, +origin, +eye, +ray, +distance, +win):
  match nearer_than_win:
    case False{}: win
    case True{}: decide(face_contains_hit(origin, eye, ray, distance), s, distance, win)
```

Only the candidates that successively beat the running best reach the quad test, and
the expected number of those is the harmonic number of a pixel's depth-hits rather than
the depth-hits themselves. Measured, 11 samples at eight threads:

| | before | after |
| --- | ---: | ---: |
| walk, sequential | 18.25 | 17.70 |
| `image` | 5.10 | 4.85 |
| `render`, world held | 5.95 | 5.75 |
| `frame` | 6.20 | **5.85** |
| `frame`, world re-extracted | 8.75 | 7.80 |

**Eight percent of the frame for a reordering**, with the pixel-exact agreement gate
unchanged at `same=1024/4096/16384`, `wrong_block=0`. The frame's median reads 5.65 to
5.85 across four runs on an idle host with a minimum of 5.50; the table takes the most
recent thirteen-sample run, because the earlier and later runs on a loaded host read
6.00 to 6.15 on the same code and a single median would have hidden that.

A second half of the same idea was tried and **rejected on measurement**. The hit's
coordinate along the face's own normal is the plane coordinate by construction, so one
of the three `within_unit` calls always passes and could be dropped by choosing the
normal's axis in a `match` first. The sequential walk came out 17.90 ms against 17.80,
because the two nested matches cost about what the multiply, add and `within_unit` they
remove cost. It is reverted; the three-coordinate form carries a comment recording both
the fact and the measurement, so nobody re-derives it.

### Where the frame stands

Retaken on the shipping code at twenty-one samples, eight threads, per-call medians. The
earlier table in this session was taken before the tick and extraction work, so the
64x64 and 128x128 rows have both moved:

| size | render | frame | headroom against the 60 Hz cap |
| --- | ---: | ---: | ---: |
| 32x32 | 3.30 | — | 13.4 ms |
| 64x64 | 6.08 | — | 10.6 ms |
| 128x128 | 14.40 | **14.75** | 1.9 ms |
| 256x256 | 45.67 | 45.67 | none, at 21.33 FPS |

The frame the client ships is 128x128. Across two twenty-one-sample runs at eight
threads, per call:

| phase | run A median [min, max] | run B median [min, max] | against 16.67 |
| --- | --- | --- | ---: |
| `frame_held` | 14.75 [13.95, 16.00] | 14.50 [13.80, 29.80] | 87% |
| `frame_look` | 14.45 [13.85, 24.80] | 14.35 [13.85, 22.40] | 86% |
| `frame_edited` | 16.25 [15.80, 29.75] | **16.65** [15.80, 30.00] | 100% |
| `render`, world held | 14.40 [13.95, 15.70] | 14.10 [13.75, 19.55] | 85% |
| `render`, cold | 16.60 [16.00, 17.90] | 16.30 [15.80, 29.95] | 98% |

**The dig frame sits at the tick, not comfortably inside it.** Its median was 16.25 and
then 16.65 against 16.67, so the dig frame presents at 60 by a margin that a busy host
can take away, and that is the one honest caveat in this table. The maxima of 22 to 30 ms
appear in every phase including `frame_held`, which no phase should be able to exceed, so
they are the shared host rather than the client — WSL2 divides eight logical CPUs with
Windows, and a scheduler preemption lands on whichever phase is running. The dig frame's
own spread is narrower than that: 15.80 at the floor in both runs.

**The frame rate the player sees is not in that table.** `window_pace` in
`vendor/bend/bend2/effs/window.c` sleeps every presented frame to the next 16.67 ms
tick:

```c
// A frame waits for the next 60 Hz tick, as the Mac's display sync.
static void window_pace(void) {
  static u64 due;
  u64 now = io_tick();
  if (due > now) { ... nanosleep ... }
  due = (due > now ? due : now) + 16666667;
}
```

`window_show` calls it before every `XPutImage`, so the client presents at 60 Hz
however fast the frame is, and `vendor/bend` is upstream code the repository does not
edit. Every "FPS" figure in either session's notes is therefore a frame budget, not a
presented rate: this session took the budget at 64x64 from 10.40 ms to 5.85 ms.

### The presented rate, measured end to end

That is a claim about the runtime and the benchmark, not about the client, and the
client was never actually counted. It is countable: `App.loop`'s third argument is a
frame countdown — the prelude decrements it once per `App.step`, and one `App.step` is
one `Window.frame`, which is one `XPutImage`. So `lab/native/client-probe/fps_probe.bend`
runs the client's own `start`, `view`, `tick`, window size and tile edge through
`App.loop` with a fixed 600-frame countdown under Xvfb and times it. Nothing in
`native/client.bend` is changed; `lab/native/client-probe/run-fps.sh` is the harness.

| run | frames | elapsed | ms per frame | presented |
| --- | ---: | ---: | ---: | ---: |
| 1 | 600 | 10,035 ms | 16 | **59.79** |
| 2 | 600 | 10,046 ms | 16 | 59.72 |
| 3 | 600 | 10,041 ms | 16 | 59.75 |
| with `--threads 8` | 600 | 10,044 ms | 16 | 59.73 |
| after the 128x128 move | 600 | 9,999 ms | 16 | **60.00** |
| " | 600 | 10,001 ms | 16 | 59.99 |
| " | 600 | 10,003 ms | 16 | 59.98 |
| " (first of four) | 600 | 9,998 ms | 16 | 60.01 |

**The live client presents 60 frames a second, which is the 60 Hz ceiling**, and the
explicit `--threads 8` pool the benchmark uses changes it by nothing, because the frame
fits inside the tick either way. The last four rows are the shipping build at 128x128:
elapsed sits at ten seconds for 600 frames, where the 59.7 rows at 64x64 accumulated a
per-frame deficit across the run. What remains under the ceiling — 59.98 against 60.00 —
is the pace accumulating over 600 intervals, not a frame that overran.

Getting there took one wrong instrument and one wrong reading. The wrong instrument
read `/proc`'s CPU time across a fixed wall interval and divided by an assumed 60 Hz to
get a per-frame cost; it reported the client was *missing* the tick at 17.7 ms a frame,
which is impossible against a 5.85 ms benchmark and against the probe's 16.65 ms. The
reason is that CPU time summed across threads does not separate a frame's cost from
the number of frames — it only bounds their product — so the instrument was
under-determined and its verdict was an artifact of the assumption. It was deleted
rather than repaired, because the probe measures the thing directly and there was
nothing to salvage. The wrong reading was in the probe's first run, which printed
`6.00` for a rate of `60.00`, from `frames * 10000` where the elapsed is in
milliseconds and the factor is `100000`.

### A third wrong instrument, and the two bugs the hunt for it found

The dig frame is the only one without slack, and the probe drives no input, so the live
rate said nothing about it. A synthetic-key driver was built to dig while the loop ran,
and it is worth recording because it failed in a way that is easy to mistake for a
result.

Its numbers looked like findings: 58.39 FPS digging every thirtieth frame, 55.65 with a
wall-clock-bounded driver, 53.16 with one process per stream. All three are below 60,
and the tempting reading is that digging costs four to seven frames a second. It does
not. Each `xdotool` invocation is a Python process competing with the client for the
same four cores, and the probe with no input at all reads 60.00 in the same harness on
the same host. **The number moved with the driver, not with the client.** The tell was
that "less driver" gave "more FPS" in every comparison, which is backwards for a
measurement of the client and is therefore a measurement of something else.

The dig frame turned out not to need confirming. `frame_edited` forces a cold world
rebuild on *every* iteration, which is strictly worse than a real session where digs
alternate with held frames, and it measures 16.25 ms against a 16.67 ms tick. And
`window_pace` sleeps any frame shorter than the tick, quoted above, so a sub-tick frame
presents at the ceiling by construction rather than by inference. The harness median
plus the pacing code is stronger evidence than a live run the driver contaminates, so
the driver was removed and `run-fps.sh` now says why in its header.

Two real bugs surfaced on the way, both in the harness, both worth keeping fixed:

- **The probe's save path could not resolve.** `Client.path()` is the *relative* path
  `native/client-world.b2cw`, so it resolves against the process's working directory,
  and the probe runs from the scratch folder rather than the repository root. Pressing
  save there failed with `No such file or directory` and took the client down with it —
  `err_fail` and `IO.die`. The cleanup line also targeted the wrong path, so it had been
  removing a file the client never wrote. Both are fixed by creating `$RUN_DIR/native`
  and pointing `WORLD_FILE` at the path the client actually resolves.
- **The probe skipped the grab wait.** `Client.run` sleeps `grab_wait_ms` after grabbing
  and then grabs again, for a documented reason: the grab refuses to engage until the
  window holds input focus, and focus arrives after the window is mapped. The probe
  grabbed once and looped immediately, so it lost that race every run. It costs nothing
  when the probe presents frames and only matters the moment something asks the camera
  to turn, which is why it went unnoticed.

What the work bought is headroom, and headroom converts into resolution rather than
into frames. **128x128 now holds 60 Hz; it did not before.** It measured 24.35 ms at the
start of this work and 14.75 ms now, against the 16.67 ms cap. 128x128 is what ships:
64x64 also presents at 60, but it presents at 60 with ten milliseconds of slack, and
slack is what absorbs the frame that follows a dig — 16.25 ms against a 14.75 ms median
here, the same shape as 8.50 against 5.85 at 64x64. The size that stays smooth when a
frame costs more than its median is the one to ship, and at 128x128 the dig frame still
fits inside the tick.

The session opened at 10.40 ms and closes at 14.75 ms at a size four times the area;
64x64 went 10.40 -> 5.85 ms over the same work. The changes account for it in the order
they were found: the walk's per-candidate allocations and its box test took 3.35 ms, the
world cache took 1.75 ms, the region layout took 0.85 ms, the hit test's short-circuit
took 0.35 ms, and the lazy layer and row walks took a further 0.27 ms off the cold path.
Only one of the five was where the first two sessions' notes pointed.

### What the frame is now made of

| term | ms | share |
| --- | ---: | ---: |
| per-pixel bucket walk | 4.40 | 78% |
| scatter into the tile grid | 0.45 | 8% |
| project and clip | 0.20 | 4% |
| quadtree fold and read-back | 0.30 | 5% |
| tick | 0.03 | 1% |
| `XPutImage` and the pixmap fill | ~0.30 | 5% |

The shares are the 64x64 split this session measured and the absolute terms at 128x128
are the twenty-one-sample run: `image` 12.20 ms of a 14.40 ms render, `project` 2.00 ms,
`grid` 5.10 ms, `region` 0.35 ms, `faces` 1.88 ms on the cold path, `tick_held` 0.03 ms.

**There is no GPU path to the 78%.** `--gpu` compiles the binary with `-DBEND_CUDA=1`,
and the only CUDA site in the runtime is `window_fill`, which is the quadtree-to-
framebuffer copy. The projection, the bucketing, the walk and the quadtree fold are
Bend code on the CPU interpreter under every setting, and `native/client-probe` measured
`--gpu on` as a no-op because the benchmark never opens a window. So the walk is not
reachable by a faster device, only by a cheaper step, and the cheaper step is
`vendor/bend`.

The part a device *could* address is already in the table above: `XPutImage` and the
pixmap fill together are ~0.30 ms, 2% of a 14.40 ms render. Replacing a 16 KB pixel write
with a kernel launch and a `cuMemcpyDtoH` cannot move 2%, and the kernel's output still
goes through the unchanged `XPutImage` host upload. Two further facts bound it harder,
and both are worth recording so the claim is not re-litigated on a different host:

- **The lane is not buildable here.** `bangs` requires `nvrtc.h` under `$CUDA_HOME` and
  clang 19 (`vendor/bend/bend2/main.ts:425`). This host has neither — no CUDA toolkit
  headers and no clang — although `nvidia-smi` does report an RTX 4070 SUPER through the
  Windows driver. So `--gpu` was never *executed* against the client window; it was read
  off the source, which is why the structural argument above carries the conclusion and
  the benchmark's no-op is only corroboration.
- **A reader on a CUDA-capable host should not expect a different answer.** The
  conclusion does not depend on this machine. It depends on the walk being Bend code
  outside the one CUDA function, and that is a property of the pinned runtime.

Four fifths of the frame is 695,808 list steps, and this session established what that
number is and is not:

- **Not the walk's own code.** Four walks over the same 695,808 candidates, timed by
  `native/client-probe` at 64x64, edge 16, eight threads, seven samples:

  | phase | what the reject path does | ms | ns per candidate |
  | --- | --- | ---: | ---: |
  | `bare` | one cons cell and a tail call, nothing else | 16.05 | 23.1 |
  | `step` | the same, plus the seven-field destructure | 16.00 | 23.0 |
  | `pixel` | the shipped walk: split box test, two calls | 18.20 | 26.2 |
  | `one` | the box test folded into one `Bool.and`, one call | 18.40 | 26.5 |

  The bare iteration is 88% of the walk. The box test, the branch and the call
  structure together are 2.2 ms of 18.2, and the runtime's cons-cell step is the
  other 16. Three ideas died on that table rather than on an argument:

  - **Splitting `Screen`** so the walk reads two fields instead of seven gains
    nothing. `bare` and `step` are within noise, and `step` is the one reading all
    seven, because a pattern must list every field of a constructor. The five unread
    fields are free. This was the last idea for the step cost.
  - **Folding the box test into one `Bool.and`**, which does make the reject path a
    single call instead of two, measures the *same*: 18.40, 18.30 and 18.25 ms against
    the shipped walk's 18.20, 18.15 and 18.25 over three runs. The saving is real in
    dispatch count and lost in the second compare, which is then paid on every
    candidate instead of only on the ones the first admits. Two runs said the folded
    shape was 1% slower and the third said they were equal, so the honest reading is
    that there is no difference to collect. The shipped walk keeps the split, and
    `face_probe_test` holds the two shapes to the same answer on every pixel of a real
    grid, so that is a measurement and not an opinion.
  - **Removing the arithmetic.** An earlier version of this file priced the box test,
    the plane intersection and the quad test at 0.85 ms of 17.85 by deleting them,
    which left the calls in place and so measured the arithmetic rather than the step.
    The four-walk table is the version that separates them.

So the walk is a step count multiplied by a step cost, and the step cost is 23 ns of
which the pinned runtime's list iteration is essentially all. The step count is pinned
by the tile-edge balance below. A cheaper step is the one thing that would move it, and
that is a change to `vendor/bend`, which this repository does not make.
- **Not rasterisation — but the number that said so was wrong.** A rasteriser's work is
  the sum of the live faces' clipped box areas, **390,799**, against 695,808 for the
  walk. So a rasteriser needs 1.78x *fewer* steps, not the 4.4x more this file claimed
  when it was written. The `boxarea` fact was summing the dead faces, whose clipped box
  has `x0 > x1`, so `min(x1, last) - min(x0, last)` underflowed to about four billion
  and one such term wrapped the total: 3,094,159 against a true 390,799, 7.9x too high.
  It reached the right verdict from a broken input, which is worse than being wrong,
  because it looked settled.

  The margin is still against rasterisation, on cost rather than count. The 1.78x is
  the tile quantisation: a face whose box straddles a tile boundary is placed in up to
  four tiles and so is stepped on by up to four times its area. A rasteriser would
  recover exactly that, and it would recover all of it — but it replaces an
  allocation-free 25 ns cons-cell read with a depth test against a persistent quadtree,
  and every such test rebuilds a six-level path. 390,799 tests at six rebuilds is
  about 2.3M node allocations per frame against the 5,461 the frame allocates today, a
  factor of 428. For rasterisation to win, its per-pair cost has to come in under
  1.78 x 25 ns = 44.5 ns, and the whole margin is that 1.78. That is a bet with poor
  odds on a large rewrite, and it is recorded here as measured rather than left as an
  intuition.
- **Not the field of view.** `focal` is `scale * half` and the vertical angle is
  `2 * atan(1 / scale)`, so the shipping 1.5 is 67.4 degrees. The candidate count is
  nearly flat in it — 681,984 at 0.25, 695,808 at 1.5, 685,312 at 3.0, 666,624 at 24 —
  so a 96x change in the focal length moves the walk's step count by 4.4%. The faces
  near this camera are small on screen (390,799 pixels over 1,654 faces is 236 each,
  5.8% of the frame), and shrinking them further shrinks tiles they already fit inside
  rather than the number of tiles they occupy. There is no frame rate here, and
  therefore no reason to touch what the player sees.
- **Not the near-plane fallback.** Faces crossing the eye plane get the whole frame as
  their candidate box, and at this camera that count is **zero**. The 98 candidates per
  pixel that survive at edge 2, where a bucket holds only the faces whose box contains
  the pixel, are real close-up geometry with large projected boxes. The clipping idea
  had no headroom to recover.
- **Not the tile size.** Edge 16 is the measured optimum, and it is the optimum under
  *both* builders Bend 2.0.32 can express. The scatter builder costs
  `2 * across * placements` steps because `List.set` is the only random access there
  is, and a `List` placement is a short walk. Row-major needs no random access — every
  placement is a cons — but it re-decides each placement from the face's box, once per
  row. The prediction was that row-major is cheaper, because the walk's saving at edge
  8 outruns the scatter builder's penalty. Measured, with all three phases building the
  grid inside the timed loop: **2.90 ms scatter at edge 16, 3.00 row-major at edge 16,
  5.15 row-major at edge 8.** The model was wrong by about a factor of eight on the
  row-major term because it counted a face visit as one step, and a visit is a field
  read, two integer divisions by the edge, a `place` call and its `match`. A builder's
  cost is not its placement count; it is its placement count times the work of reaching
  a placement.
- **Not the thread count.** 8 is this machine's ceiling: 4 threads gives 9.30 ms and
  8 gives 6.00, 12 gives 7.20 and 16 gives 7.25. WSL exposes 8 logical CPUs on 4
  physical cores, and the walk is 3.5x faster on 8 than on 1, which is close to what
  two SMT siblings on four cores can do to a pointer-chasing loop.

So the walk is a step count multiplied by a step cost, and both are pinned: the step
count by the tile-edge balance, the step cost by the pinned runtime's list iteration.
A cheaper step is the one thing that would move it, and that is a change to
`vendor/bend`, which this repository does not make.

There is one asymmetry worth carrying to the next session, because it explains every
negative result above at once. **The walk is 3.5x parallel and the builder is not.** A
list step in the walk therefore costs 7 ns of wall time and a list step in the scatter
builder costs 25 ns, so any structure that adds builder steps to remove walk steps is
charged 3.5x for the trade. A finer grid, per-tile depth sub-buckets, a per-tile
bounding test for sky pixels, row-at-a-time assembly — each is a good idea on step
count and each loses to the multiplier. The tile edge is not a tuned constant; it is
where that multiplier stops dominating.

### Three measurements that were wrong before they were right

All three are the same mistake, and they are recorded because the shape of the mistake
is more useful than the numbers.

**A diagnostic that perturbs the thing it measures.** The region dump builds a grid per
focal scale and per tile edge — eight extra grids, about 174,000 builder steps of
allocation churn — and it was printed between the tick phases and the render phases.
Adding the focal sweep moved `image` from 4.90 ms to 5.20 ms and the frame from 6.00 to
6.15, which is 6% of the largest term in the frame, from adding a diagnostic. It now
runs after every timed phase. A benchmark's untimed setup is still inside the process
the timed phases run in, and a benchmark that allocates near its own measurements will
eventually measure itself.

**A fold over a set it had not checked.** The `boxarea` fact summed the dead faces,
whose clipped box has `x0 > x1`, so the width underflowed to about four billion and one
term wrapped the total: 3,094,159 against a true 390,799. It reached the right verdict
— rasterising loses — from a broken input, and the input was 7.9x wrong in the
direction that made the verdict look comfortable. `clip_area` now skips the dead faces
on the liveness flag. The corrected number has an independent check: at edge 2 a tile is
2x2 pixels, so placements approach covered pixels one for one, and edge 2 measures
400,128 against 390,799.

**A number that had not been counted.** The near-plane claim arrived by subtraction from
a total, and one counter would have caught it.

A guard around a call is not a guard around its arguments, in this language or any
other, and a benchmark that constructs its own fixture inside the timed loop will
eventually time the fixture instead of the program. The common thread is narrower than
that: **a number that has not been counted looks attributed the moment it is printed**,
and the tell in all three cases is the same — a figure too tidy to be surprising.

### What is left, and what it would take

**Presented frame rate: nothing is left.** The runtime paces every frame to a 16.67 ms
tick and `vendor/bend` is not ours to edit, so 60 FPS is the ceiling, and four live
600-frame runs on the shipping build read 60.01, 60.00, 59.99 and 59.98. The held frame
at 14.50 to 14.75 ms is inside the tick with room. **The dig frame is not**: its median
was 16.25 in one run and 16.65 in the next, so it presents at 60 by a margin a busy host
can take away. That is the one place where more frame cost would still buy something, and
it buys it on a frame that is 100% of the tick rather than 87% of it.

**Frame cost: one lever, and it is smaller than it looks.** The dig frame's 1.88 ms of
extra work is the whole region's face extraction. Two caches were considered and both are
closed:

- caching the region's *faces* is unsound, because a face on a chunk seam is decided by
  the neighbouring chunk, and a cache that misses a neighbour shows stale seam faces —
  wrong rendering at a boundary rather than a failed assertion;
- caching the chunks' *cells* is sound and was built and measured, and it cannot fire:
  the rendered region is one chunk, so the cache has a single key, that key is the whole
  edit log, and `world_for` only rebuilds when the log has changed. Every rebuild missed.

What remains is splitting the chunk's extraction into sub-blocks and re-extracting only
the one a dig touched, worth about 1.4 ms. It is sound for a one-chunk view, because a
sub-block's boundary faces are decided by a one-cell halo that a full extraction would
have read anyway, so the union over sub-blocks is exactly the full face set. It is not
done because the face *order* changes — grouped by sub-block rather than by scan — and
the order is what the tile-edge dispatch and the bucketing's locality depend on, so the
trade is 1.4 ms on the one frame that already fits against an unmeasured regression risk
on the frame that is 85% of every other one. **The honest version of that is that it
would need measuring, not that it is safe.**

The walk's step count falls with the tile edge and the builder's rises faster,
because the builder is `O(across)` per placement and `List.set` is the only
random access Bend 2.0.32 offers. An `Array` is a persistent tree whose `set` and
`get` both rebuild the path, and a `Map` is a String-keyed radix trie; neither is
cheaper than a short list at these widths. So the builder cannot be made
`O(1)` per placement from Bend as it stands, and the tile edge is pinned where the
table above puts it.

> **The second paragraph here was wrong, and it is the most expensive wrong answer in
> this file.** It said the 98 candidates per pixel that survive at edge 2 — where a
> bucket holds only the faces whose box contains the pixel — are the near-plane
> fallback, and that clipping the quad against the near plane would tighten them. The
> fallback count at the client's camera is **zero**: not one face has a corner behind
> the eye.
>
> It also offered a number in support, and that number was broken too: 3,094,159
> pixels of clamped box area, an average of 1,870 per face against a 4,096-pixel frame.
> The true figure is 390,799, an average of 236 per face, or 5.8% of the frame. So the
> faces near this camera are *small* on screen, not enormous, and the two wrong answers
> were pointing in opposite directions from the same measurement.
>
> The general shape of the mistake is worth keeping, because both instances of it are
> the same mistake. **A number that has not been counted looks attributed the moment it
> is printed.** The near-plane claim arrived by subtraction from a total, and the
> clamped-area claim arrived from a fold that summed a set it had not checked for the
> values that make a subtraction meaningless. One counter catches the first; one
> `Bool.pick` on the liveness flag catches the second. Both were available the whole
> time, and the tell in both cases is the same: a number too tidy to be surprising.
> 3,094,159 is 7.9x the truth and looked like a measurement; 98 candidates a pixel is a
> suspiciously round attribution and was not a measurement at all. Measure the thing you
> are about to explain before you explain it.

---

## Session one: showing a world at all

The native client works: it opens a real window on the Windows desktop, takes
real key events, moves, collides, digs, places, saves and quits cleanly. What it
could not do, until this session, was show a world, and the reasons turned out to
be four separate defects rather than one.

The renderer's cost is dominated by a quadratic term that nobody had measured, and
the agreement gate between the two renderers is structurally incapable of
catching a whole class of visual bugs, because it compares which block is nearest
and never what gets painted.

### Defects found and fixed

### The palette covered 11 of 30 block ids

`Voxel.block_color` knew ids 0-10 and returned one flat `rgb(170, 170, 170)` for
everything above. `world/structures.bend` builds a village out of ids 11 (furnace),
13 (bed) and 14 (door), so the entire village painted as a single grey slab, shaded
to `0x8E8E8E` on the 84% face.

Fixed by rewriting the table as a `match` over the id, with 11-29 taken from the
base colour of the matching material in `web/texture-atlas.js` — the renderer that
has always displayed them correctly. Ids 0-10 are byte-identical, so every pinned
golden still holds.

### The agreement gate could not see it

`native/face-probe` compares the face renderer against the per-pixel ray renderer
and reports zero disagreements at 32x32, 64x64 and 128x128. It compares *which
block is nearest*, never the colour painted. A renderer that paints every surface
one colour passes that gate with a perfect score.

Added `palette_walk`, which fails on the first id with no colour, and
`village_palette_test`, which requires furnace, bed and door to be mutually
distinct. `unknown_block_color()` is now a named constant so "the palette ran out"
is visible in a frame instead of looking like a material.

### The client crashed on its way out

`native-client: the loop asked for a step on a closed frame`. The loop turned a
spent frame, whose empty events set `running` back to true, so the client neither
drew nor quit. `lab/native/client-probe/smoke.sh` passed anyway, because it only
checked that the process was gone — which a crash also satisfies. The smoke now
requires exit status 0.

The fix is not a patch to the old loop. A self-recursive loop in Bend 2.0.32
cannot both end on a data condition and satisfy the termination checker: the
checker needs every self-call argument unchanged up to the one that visibly
shrank, and a `case` that binds a frame's fields makes every other parameter
unmatchable. The `Maybe` the tick returns is the mechanism `App.loop` already uses
to end, which is why it exists. The client uses it, and the pointer grab became
two grabs with a pause between them, because a `Window` is a linear handle and a
retry loop would need the same one twice in a pass.

### The renderer could only see one chunk

`Face.render_size_at_with_tile_size` took a single `Array<U32>`, capping the
visible world at 16x16 cells. From inside the village at spawn that is a wooden
wall; at a chunk edge it is an all-sky frame.

The walk was already generic in its step count, so generalising it was
parameterising the extent and adding a builder that lays several chunks out as one
array. The gate came back with identical numbers (`faces=1298`, `same=1024/4096/16384`,
`wrong_block=0`), so the refactor is semantically transparent.

## The spawn contract, and why the client cannot use it yet

The browser asks `World.spawn_cell(seed)`. The client hardcoded `(25, 25, 9)`.
For seed 1337 the contract answers `(25, 16, 9)` — and with the region at chunk
(1, 1) that is local `(9, 0)`, the minimum z edge. A camera at yaw 0 looks toward
-z with zero rows of world in front of it, so the frame is all sky and a dig ray
leaves the region before it reaches anything.

Wiring the contract in is blocked on the region origin, and the origin is also what
the camera's eye is rebased onto. Moving it to chunk (0, 0) covers the whole
48x48 world and fixes the spawn, but it invalidates the frame probe's single-chunk
render fixtures, which compare a one-chunk ray render against a sky control. Three
chunks per axis at origin (0, 0) also built a 46,080-cell collision region and the
machine stack overflowed, so the view region and the collision region have to be
sized apart.

## Measurements

### Resolution, one chunk

| size | pixels | render | marginal |
|------|--------|--------|----------|
| 32x32 | 1,024 | 6.56 ms | |
| 64x64 | 4,096 | 8.65 ms | 0.68 us/px |
| 128x128 | 16,384 | 22.80 ms | 1.15 us/px |
| 256x256 | 65,536 | 74.33 ms | 1.09 us/px |
| 512x512 | 262,144 | 349.50 ms | 1.42 us/px |

Cost is linear in pixels at roughly 1.1-1.4 us each. `640x480` is 307,200 pixels,
which projects to about 436 ms against a 16.7 ms budget: **26x over**.

**64x64 is the largest power-of-two size that fits 60 Hz.** 128x128 is ~24 ms,
about 41 FPS. A 128x128 window at 41 FPS against 64x64 at ~87 FPS is a product
decision, not an engineering one, and it has not been made.

### Region width

| | 1 chunk | 2x2 region |
|---|---|---|
| frame 64x64 | 11.10 ms | 26.30 ms |
| render 32x32 | 6.93 | 21.41 |
| render 64x64 | 9.85 | 19.10 |
| region build | 0.35 | 1.30 |

The region misses the budget at *every* resolution, which is the tell: 32x32 costs
more than 64x64. The cost is not per-pixel, it is the four times the data going
through passes that are already O(n) per layer.

### Tile edge

| depth | size | edge 8 | edge 16 | edge 32 |
|-------|------|--------|---------|---------|
| 5 | 32x32 | 6.49 | 6.57 | 10.32 |
| 6 | 64x64 | 10.30 | 8.65 | 12.55 |
| 7 | 128x128 | 38.90 | 20.80 | 24.40 |
| 8 | 256x256 | 218.67 | 74.33 | 64.33 |
| 9 | 512x512 | 1370.00 | 349.50 | 222.00 |

The crossover sits between 128 and 256. Below it the per-tile cost dominates and
16 wins; above it the per-pixel bucket walk dominates and 32 wins. The client now
derives the edge from the depth of the frame being built: 16 below 256x256, 32
above. This is worth 32% at 512x512.

### Where the render time actually goes

| phase | cost |
|-------|------|
| world build | 0.35 ms |
| face extraction | 1.35 ms |
| everything else | ~5-7 ms |

Face extraction is 15% of the render. The rest is projection and bucketing, and
`lab/native/face/face.bend` says why, at the comment above `bucket_all`:

> The row-major builder below scans this list once per tile and conses matches
> into that tile's bucket.

It scans the 1,298 projected screens once **per tile**. The term is
`tiles x faces`:

| size | tiles (edge 16) | screen visits |
|------|-----------------|---------------|
| 32x32 | 2x2 | 5,192 |
| 64x64 | 4x4 | 20,768 |
| 128x128 | 8x8 | 83,072 |
| 256x256 | 16x16 | 332,288 |
| 512x512 | 32x32 | 1,328,576 |

> **Corrected by session two.** That term is real, and it is not the one the client
> pays. The builder above is `bucket_faces_row_major_*`, which is measured but is
> not the shipping path: `bucket_faces_with_tile_size` scatters each face into the
> tiles its box meets as it goes, and costs `2 * across * placements` list steps
> instead. Measured at the client's own camera, the frame's dominant term is the
> **per-pixel bucket walk** — 695,808 candidates at 64x64 — and it is the pinned
> runtime's list step rather than the scans above. The 20,768 visits at 64x64 would
> be 5% of the walk. The "highest-value change left" named here was worth nothing,
> and the reason it looked valuable is the same reason the arithmetic
> short-circuit below looked valuable: both were guesses about where the time went
> that a measurement would have settled for the price of one run.

Bucketing by tile **row** instead of by tile would reduce the row-major term to
`across x faces` — 4x fewer visits at 128x128 and 16x fewer at 512x512.

## Attempts that did not land

### Short-circuiting the candidate test

`closer` computed the plane intersection — a divide, three multiplies and six float
compares — for every candidate in a tile, even when the cheap screen-box test had
already rejected it. Splitting the two across a `match` on a *parameter* (rather
than `Bool.pick`, whose arguments are built before the call) skips the rejected
branch.

Worth 9% at 64x64 and 1.7% at 512x512. It is in, and the gate is unchanged, but it
is small — and being small is what identified the real bottleneck above. A guess
that costs 9% is a sign the hypothesis was wrong, not that the work was wasted.

### One-pass region layout

`List.drop` is O(n) and the region builder called it once per chunk per layer, so
laying four chunks out cost `chunks * layers` full passes before any face was
looked at. The fix is to consume each chunk's cells once.

It is a nested loop, and Bend allows no helper cycles, so every decomposition hit
the same wall: separate helpers are a cycle; flattening into one loop needs two
fields of a record read inside a `match` arm, which is a scrutinee error; unrolling
the chunk loop for 1, 2, 4 and 9 works but only for sizes already known. Reverted.
The target is still right — it is just not reachable from Bend's recursion rules
without changing the data the walk consumes.

### Faster compilation

Bend 2.0.34 was evaluated and the pin left at 2.0.32. `window.c` is byte-identical
between the two, so the 60 Hz cap (`due = ... + 16666667`) and the X11 backend are
unchanged. The `base.bend` diff is 181 lines of internal refactor — `Bool.full_add`
rewritten with `xor`/`and`/`or`, some `Cmp` cleanup — with no new defs. Compiled the
benchmark with both and ran seven samples of each:

| phase | 2.0.32 | 2.0.34 |
|-------|--------|---------|
| frame 64x64 | 11.45 ms | 11.85 ms |
| render 128x128 | 22.70 | 22.20 |
| render 256x256 | 76.67 | 79.67 |
| render 512x512 | 355.50 | 362.00 |

Everything is inside +/-4%, which is noise. **The compiler version is not a
performance lever here**, and that is now a measurement rather than an inference.

## Bend 2 and Windows

The runtime does not support Windows, and says so in `vendor/bend/WONTFIX.txt`:

> A handle type is a law of Base (#825) ... A user law of kind `Type` counts as
> open, so a custom effect reuses a Base handle type.
>
> CAPACITY ... Windows is not supported (#788). Use WSL.

`Window` is a `law`, not a `def`, so a project cannot shadow it, and a
project-authored Win32 effect would need a user handle type, which is an open
compiler item. The link flags in `cli_build` are conditional on the generated C
including `<X11/`, which looked like a way in until it became clear that the
runtime's own `io_eff` constructor still registers the X11 implementation and the
link resolves to it regardless.

A Windows build therefore needs a fork, at one of three depths. The cheapest is
pointing `base.bend`'s `Window` effects at a Win32 C file in `.tools/bend-local`,
which leaves `vendor/bend` untouched but is still a fork. Not taken.

WSLg, by contrast, was a configuration problem: `guiApplications=false` in
`~/.wslconfig`, off deliberately to save 200-400 MB. With it on, the client opens a
real window on the desktop at `(4841, 490)`, 64x64, accepts `w a s d`, and exits on
escape with status 0. The backup is `~/.wslconfig.bak-before-wslg`.

## Also found

**The raycast cannot reach the ground the player is standing on.**
`Player.raycast.loop(160n, ...)` steps 0.05 at a time from 0.1, so the reach is
8.05 cells. The spawn pitch is -0.18, which puts flat ground about 9.3 cells away.
The player spawns unable to dig until they look down. The save test used to pass
by accident, because the old spawn was inside a village and a wall happened to be
within reach.

**The collision region was two-thirds of the world.** Two chunks per axis from
chunk (1, 1) is 32x32 of a 48x48 world, so a third of it had no collision at all.

**The frame benchmark was measuring a different program.** `frame_bench.bend`
inlined its own copy of the render call over a single chunk, which stopped being
what the client does the moment the client rendered a region, and its `chunk` phase
generated one chunk when the client generates the region. A benchmark that measures
a different program than the one that ships is worse than no benchmark. The client
now exposes `image_at_depth` and the benchmark calls it.

## Session nine — the mouse does not work under WSLg, and that is a measurement

The renderer reached 60 FPS at 128, 256 and 512 (60.08, 60.07, 60.01 presented
under Xvfb over 600 frames, `--threads 1`; 20.73 at 1024). What was left was the
mouse, and the mouse turned out to be the more interesting problem.

### What the census said

An instrumented client printing one line per event, for one whole session:

| event | count |
| --- | ---: |
| `Key` | hundreds — `w a s d`, escape, alt |
| `Mouse` (clicks) | 15, **every one at `x=256 y=256`** |
| `Look` | **1** — `dx=5 dy=217` |
| `Move` | **0** |

512/2 is 256. Every click landed exactly on the window's centre, which is where
`window.c:594` warps the pointer. One `Look` in a session of continuous mouse
movement.

### What that establishes

The grab **does** engage. It is gated on `XGetInputFocus` returning `win->win`
(`window.c:774`), the window is a plain toplevel created under `RootWindow` with
no WM to reparent it (`window.c:264`), and it has focus — keys arrive, which is the
proof, since keys need focus. So `XGrabPointer` succeeded.

The pointer is therefore **confined and warped to the centre, and stays there**.
A pointer that cannot leave the centre cannot report having moved, so
`MotionNotify` never carries an off-centre position, and `window.c:591` — which
pushes `Look` only `if (win->grab && (x != cx || y != cy))` — never fires again.
That single `Look` is the one frame where X did report an off-centre position.

`Move` is only pushed `if (!win->grab)` (`window.c:578`), so a grabbed pointer
never produces it. That is why reading `Move` as well as `Look` changed nothing:
the ungrabbed path is starved by the same fact that makes the grabbed path dead.
`PointerMotionMask` *is* selected at creation (`window.c:275`), so this is not an
event-mask problem.

The fault is upstream. `vendor/bend` is pinned and not edited for application
features, and `Window.grab` is the client's only pointer API. Nothing in `native/`
can read the Windows host mouse.

### What changed

The arrow keys turn the camera. Not as a fallback — as **the** look under WSLg.

- `Frame.turn_rate` 1.6 rad/s (92 deg/s) for yaw, `Frame.tilt_rate` 0.8 for pitch.
  A rate scaled by the tick, not a jump per press, so a held key sweeps at a
  constant pace.
- Codes 63232/63233/63234/63235 — the runtime's own translation of the arrow
  keysyms at `window.c:507`, chosen over raw X keycodes because those are stable
  across layouts and keycodes are not.
- Applied in `Frame.ready_holding`, so the key rate and the mouse delta add to the
  same yaw rather than one overwriting the other.
- Holding both keys of an axis is `0`, not a sum: `1.6 + 1.6` would be 3.2 rad/s.

The mouse path is unchanged and still gated, for a real X server:
`input_turns_by_the_change_in_the_offset`, `input_ignores_a_repeated_look`,
`input_reads_move_when_there_is_no_grab`.

### The failures along the way

Four input bugs in this session and in the last, all the same mistake: assuming
what the runtime does instead of measuring it.

1. The key mask was rebuilt from zero every frame, so movement rode X11
   auto-repeat instead of the loop.
2. `fold_tilt` had the pitch sign backwards.
3. `Client.share_events.go` prepended, reversing the order within a frame so a
   press and a release in the same frame left the key stuck.
4. `App.loop` was used instead of `App.step`, so the grab was requested once and
   never re-asked.

Then two more once instrumented: `3 * half` where the intent was `3/4 * half`,
putting the edge threshold outside the window; and a `Read` that treated "the two
yaws are the same" with the assertion meant for "they differ", which passed a spin
and failed a still camera in the same run.

The lesson is the boring one, and it cost a session: **the census would have found
three of the six in its first minute.** Print what arrived, then read it.

### Method


Three times in this session the intuition about where the render time went was
wrong: it was assumed to be arithmetic, then candidate count, then the region
builder. The arithmetic short-circuit was the last to be tried and the first to be
measured, and its 9% is what pointed at the real term.

The rule that came out of it: when cost grows worse than linearly with resolution,
look for a nested loop over a variable-sized structure, and count its visits
before changing anything. The table above is four measurements agreeing, not a
conclusion from reading the code.

`bend <file> --check-only` takes seconds and the native build takes six. Use it
before launching a build, every time.
