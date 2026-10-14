# lab/native/paint

Measures `native/paint.bend`: the frame painted as one tile and as the 64-pixel tiles
the client draws with, at every window size the selector offers and at several thread
counts, and the client's own frame over its view region.

```bash
bash lab/native/paint/run.sh                      # 7 samples at 1, 2, 4 and 8 threads
RUNS=3 THREAD_COUNTS="1 8" bash lab/native/paint/run.sh
```

`paint_bench.bend` has four phases, 40 draws each, and reads every image back through
`Voxel.fingerprint` before releasing it. The read-back is the same quadtree walk
`window_show` performs, so a phase is the draw plus the present's walk and leaves out
only the X transfer.

| phase | what it draws |
| --- | --- |
| `whole` | the spawn chunk's 1,654 faces, the frame as one tile |
| `tiles` | the same faces, in 64-pixel tiles |
| `client` | `Play.image_at_depth` over the client's five-by-five view region, from the spawn |
| `north`, `east`, `south`, `west`, `down`, `up` | the same frame at 1024 from open ground in the middle of the region, looking each way |
| `crowd` | the `east` frame with eight of a room's other players in it, through `Play.image_among` |
| `herd` | the `east` frame with forty of a room's mobs in it |
| `build` | `Slabs.world_built`: the whole region's slabs from nothing |
| `slab` | `Slabs.world_for` after one edit: the one slab rebuilt and the region merged |
| `collide` | `Play.collision_region`: the two-by-two grid the player collides with |

The script fails if `whole` and `tiles` print a different digest for one size, or if any
phase prints a different digest at two thread counts. A frame that changes with how it
is divided, or with the thread count, is a bug and not a speedup.

```bash
bash lab/native/paint/shot.sh [label]             # the frame as PNG files
```

`shot.bend` paints the client's own frame from twenty-two cameras, hours and screens, as one tile,
and prints each as numbers; `shot.py` turns them into `scratchpad/shots/<label><view>.png`
with nothing but the standard library. A label keeps two runs side by side. The views are
the benchmark's seven, then from above the trees — `vista`, `lake` — and at other hours:
`noon`, `sunset`, `dusk`, `night`, `dawn`. `players` and `players-night` are the east
view with four of a room's other players standing in it, and `creatures` the same view with
one of each thing a room simulates. `inventory` and `inventory-empty` are the inventory
screen open over the east view, with and without a log in its crafting grid, and `table`,
`chest` and `furnace` the other three screens.

## Measured with a room's players and creatures in the frame

2026-10-02, the same machine and lane as the sections below — AMD Ryzen 7 9800X3D, WSL2,
Bend 2.0.32 to native C, `--gpu off` — medians of five samples, milliseconds. Digests
agreed across thread counts. `crowd` is the `east` camera with eight players standing
between three and forty cells in front of it and `herd` the same camera with forty mobs in
rows (`native/body.bend`); `east` is the same frame with nobody there, from the same run:

| phase | size | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: | ---: |
| east | 1024 | 15.57 | 10.12 | 7.33 | 6.10 |
| crowd | 1024 | 15.28 | 9.78 | 7.00 | 5.85 |
| herd | 1024 | 15.93 | 9.80 | 7.22 | 6.28 |
| east | 32 | 0.35 | 0.45 | 0.65 | 0.82 |
| crowd | 32 | 0.47 | 0.57 | 0.75 | 0.95 |
| herd | 32 | 1.07 | 1.15 | 1.38 | 1.55 |

Eight players cost about 0.12 ms and forty mobs about 0.7 ms, whatever the window: at 32
that is the whole difference, and at 1024 it is inside the spread between samples, because
a pixel a body covers is a flat colour where the block behind it would have been a texel.
The cost is the front half, on one thread: every box turned, culled and projected.

The first painter of bodies put every side of every box into one list by walking it, and
eight players cost 0.8 ms (`crowd` at 32 was 1.12). The bodies are now put in order first
and each one's boxes among themselves, so a side is placed in a list of its own body's and
not of everyone's.

The names over the players (`native/tag.bend`) came after this run and did not move it:
with them `crowd` read 0.47 at 32 and 15.15, 9.82, 7.03 and 5.95 at 1024.

The `client` row of this run was 24.93, 13.95, 8.40 and 6.08 at 1024, which is the table
below. The numbers the client prints were not changed.

## Measured with the front half a chunk at a time

2026-10-02, the same machine and lane as the section below, medians of five samples,
milliseconds. Digests agreed. What changed is the front half of a frame: the painter takes
the slabs as groups, skips a chunk whose box cannot be seen, finds and projects the faces
of each chunk it keeps in its own task, and puts the polygons in order with a bucket per
whole cell of distance in place of a sort. The client's frame at the spawn:

| size | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| 32 | 0.88 | 0.82 | 0.95 | 1.07 |
| 64 | 1.02 | 1.05 | 1.15 | 1.30 |
| 128 | 1.55 | 1.52 | 1.68 | 1.98 |
| 256 | 2.90 | 2.23 | 2.12 | 2.25 |
| 512 | 7.55 | 4.83 | 3.62 | 3.17 |
| 1024 | 24.52 | 13.93 | 8.40 | 6.10 |

1024 from open ground in the middle of the region, and the same view at 32, which is the
front half alone:

| looking | 1 thread | 2 threads | 4 threads | 8 threads | at 32, 1 thread | at 32, 8 threads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| north | 23.52 | 14.65 | 10.03 | 8.32 | 1.57 | 1.60 |
| east | 15.50 | 9.90 | 7.22 | 6.15 | 0.33 | 0.82 |
| south | 17.77 | 10.93 | 7.60 | 6.30 | 0.28 | 0.78 |
| west | 24.93 | 15.40 | 10.45 | 8.32 | 1.40 | 1.52 |
| down across the terrain | 27.20 | 16.25 | 10.75 | 8.47 | 0.72 | 1.00 |
| up | 11.25 | 7.15 | 5.20 | 4.42 | 0.53 | 0.85 |

`slab` 2.55, `collide` 2.40, `build` 32.40.

- **The front half went from 2.80 to 1.57 ms looking north** and from 0.62 to 0.33 looking
  east, on one thread, and the dearest 1024 frame on eight threads from 10.28 to 8.47.
- **A first attempt was slower and is not here.** Sorting each chunk's polygons in its own
  task and merging the sorted lists up the tree made the front half 4.83 ms looking north:
  five levels of merge and reverse walk every polygon ten times, where one sort had walked
  them a dozen. The order does not need a sort at all, and the buckets are what replaced
  both.
- **The pool is not free at 32x32**: 0.33 ms on one thread and 0.82 on eight looking east.
- **Looking up is 4.42 ms on eight threads**, with almost nothing to paint. That is the
  tiles' quadtrees built and walked: a million `Pix` at 1024, read one by one. It is the
  floor of a 1024 frame and it is the runtime's present, not the painter.

## Measured with the light, the air, the sky and a five-by-five region

2026-10-02, AMD Ryzen 7 9800X3D, Windows 11, WSL2 Ubuntu, Bend 2.0.32, native C,
`--gpu off`, medians of five samples, milliseconds. Digests agreed. No GPU run and no
macOS run has been made.

The region is 25 chunks and 40,656 faces. Each face carries the light of its four
corners; a pixel is a texel under that light and the hour's, seen through the air; behind
the scene are the clouds, the sun, the moon and the stars. The client's frame at the spawn:

| size | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| 32 | 1.48 | 1.48 | 1.60 | 1.50 |
| 64 | 1.70 | 1.62 | 1.68 | 1.68 |
| 128 | 2.23 | 2.23 | 2.38 | 2.52 |
| 256 | 3.50 | 3.02 | 2.90 | 3.02 |
| 512 | 8.22 | 5.58 | 4.35 | 3.95 |
| 1024 | 25.30 | 14.57 | 9.25 | 7.00 |

1024 from open ground in the middle of the region:

| looking | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| north | 23.88 | 16.75 | 12.10 | 10.18 |
| east | 14.93 | 10.35 | 7.25 | 5.97 |
| south | 17.10 | 11.15 | 7.62 | 6.17 |
| west | 24.62 | 17.35 | 12.35 | 10.28 |
| down across the terrain | 25.65 | 16.77 | 10.97 | 8.93 |
| up | 11.25 | 7.38 | 5.30 | 4.50 |

`slab` 2.50, `collide` 2.40, `build` 32.30.

What each step cost, at 1024 on eight threads, three samples each as it went in:

| step | spawn | dearest view |
| --- | ---: | ---: |
| three by three, textured (the table below) | 4.92 | 7.75 |
| + corner light, air, the sky over the view | 5.22 | 7.90 |
| + five by five, clouds and sun | 6.70 | 10.38 |
| + the hour, moon and stars, faces past the air dropped | 7.00 | 10.28 |

- **The light and the air are nearly free**: 0.3 ms. The levels are worked out when a
  slab is built, a face with every corner lit and a pixel nearer than the air do no
  arithmetic, and those are most of a frame.
- **The region is what costs.** Going from nine chunks to twenty-five is 1.5 ms at the
  spawn and 2.5 looking across open ground, and it is on one thread: the walk over every
  face to find the ones that can paint, the sort and the projection. At 32x32 it is the
  whole frame, 1.5 ms where nine chunks were 0.5. Eight threads are 3.6x faster than one
  at the spawn and 2.4x looking north.
- **`build` is 32 ms**, once at start, and a region that moves builds its five new slabs
  one a frame.

Live on WSLg, `DISPLAY=:0 bash lab/native/client-probe/run-pace.sh --size=1024`, the
player walking south across open ground for 869 timed frames: 59.99 FPS, one late, worst
frame 19 ms. At 512: 59.98, one late, worst 19 ms.

## Measured, culled and kept by chunk

Earlier on 2026-10-02, before the light, the air and the larger region: three chunks by
three, 12,884 faces, the open-ground camera fifteen cells east of the spawn. Same machine,
medians of seven samples, milliseconds. Digests agreed. The `client` phase is the textured
frame under the hotbar, hearts and hand, from the spawn; `tiles` and `whole` are the flat
frame.

| size | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| 32 | 0.53 | 0.53 | 0.53 | 0.55 |
| 64 | 0.62 | 0.62 | 0.62 | 0.65 |
| 128 | 0.93 | 1.00 | 1.20 | 1.35 |
| 256 | 2.02 | 1.62 | 1.55 | 1.57 |
| 512 | 5.78 | 3.80 | 2.75 | 2.35 |
| 1024 | 19.98 | 11.47 | 6.92 | 4.92 |

The spawn is inside a house facing a wall, the cheapest frame there is. The phases named
for a direction draw 1024 from open ground fifteen cells east of it:

| looking | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| north | 11.10 | 7.47 | 5.40 | 4.47 |
| east | 17.60 | 11.32 | 7.60 | 6.00 |
| south | 19.43 | 12.32 | 8.25 | 6.35 |
| west | 20.62 | 11.82 | 7.08 | 5.17 |
| down across the terrain | 24.48 | 15.45 | 10.05 | 7.75 |
| up | 4.80 | 3.40 | 2.67 | 2.50 |

What an edit costs: `slab` 2.00 (the one chunk's faces and the merge), `collide` 2.50 (the
two-by-two collision region). `build`, the whole nine-chunk region from nothing, is 11.80
and is paid once at start.

Three changes are in these numbers, against the table below:

- **Only what can paint is sorted.** A face behind the near plane, outside the view, or
  turned away from the eye is dropped before the sort. 1024 at the spawn went from 9.70 to
  4.92 ms on eight threads and 128 from 3.25 to 1.35; looking down across the terrain,
  13.82 to 7.75.
- **A slab per chunk.** An edit used to rebuild all nine chunks' faces, 21.20 ms, and the
  three-by-three collision region, 8.30. It is now one slab and a two-by-two region.
- **The seam faces.** A slab is extracted with air outside its chunk, so the region holds
  12,884 faces where it held 9,784. They are never painted and mostly culled.

Live on WSLg, `DISPLAY=:0 bash lab/native/client-probe/run-pace.sh --size=1024`, the
player walking south across open ground for 869 timed frames: 59.99 FPS, none late, worst
frame 18 ms. Before these three changes the same run read 58.94 FPS, 16 late, worst 51 ms.
At 128 and 512 it reads 59.99 with at most one late frame.

## Measured, textured and nearest first

2026-10-02, before the culling and the slabs. The client's frame at the spawn:

| size | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| 32 | 1.98 | 2.05 | 1.98 | 2.00 |
| 64 | 2.20 | 2.23 | 2.23 | 2.23 |
| 128 | 2.80 | 2.92 | 3.15 | 3.25 |
| 256 | 4.30 | 3.90 | 3.83 | 3.95 |
| 512 | 9.10 | 6.55 | 5.35 | 5.00 |
| 1024 | 25.57 | 15.25 | 10.07 | 8.18 |

The cold path on eight threads: `build` 21.20, `collide` 8.30.

Texturing costs a division and a texel per visible pixel: 1024 on eight threads went from
6.15 ms flat to 8.18 textured. That it is this little is the nearest-first order: each
pixel is computed once.

## Measured before the textures, with the near-plane cut and the three-by-three view

2026-10-01, same machine, flat colours painted farthest first.

The client's frame (`client`):

| size | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| 32 | 2.12 | 1.93 | 2.35 | 1.90 |
| 64 | 2.12 | 2.05 | 2.30 | 2.12 |
| 128 | 2.48 | 2.55 | 2.98 | 3.02 |
| 256 | 3.30 | 3.12 | 3.70 | 3.38 |
| 512 | 5.97 | 4.58 | 4.62 | 4.22 |
| 1024 | 15.00 | 9.78 | 7.00 | 6.15 |

The cold path, on eight threads: `build` 19.50, `collide` 8.50.

These are from after the region's layout was fixed. Before it the region held 10,618
faces of scrambled terrain and the same frame read 7.45 ms at 1024 on eight threads.

The spawn chunk alone, in tiles (`tiles`) and as one tile (`whole`):

| size | tiles, 1 | tiles, 8 | whole, 1 | whole, 8 |
| --- | ---: | ---: | ---: | ---: |
| 128 | 0.53 | 1.12 | 0.53 | 0.57 |
| 256 | 1.18 | 1.40 | 1.07 | 1.07 |
| 512 | 3.33 | 1.93 | 2.95 | 3.17 |
| 1024 | 11.35 | 3.50 | 10.20 | 10.65 |

Three things these say:

- **The region costs about 2 ms a frame whatever the window.** It is the sort and the
  projection of the faces not wholly behind the eye, on one thread. Before those faces
  were dropped ahead of the sort the same frame was 6.25 ms at 128 and 12.25 at 1024 on
  eight threads.
- **One tile is as fast as 64-pixel tiles on one thread, and does not scale.** That is
  the whole of what the tiles are for.
- **The cold path is over a tick.** It was 1.88 ms for one chunk and is 19.50 for nine,
  plus 8.50 for the collision region, so an edit costs a late frame or two.

The live presented rate with the three-by-three view, `bash
lab/native/client-probe/run-fps.sh --size=N`, 600 frames under Xvfb on the default pool:
60.06 at 128, 256 and 512, 60.03 at 1024. On one thread 1024 reads 58.49, which is the
1.4 ms of slack not being enough. A second client left running on the same machine took
512 down to 50.87 and 58.12 while 1024 held 60, so measure on a quiet machine.

## Measured before, with the first painter

Earlier the same day, same machine, one chunk, before the near-plane cut. The
"whole-frame painter" here is the first one written, which folded its array by forking a
handle and four tasks at every node; it has since been replaced by the one-tile frame
above, which is the same code as the tiles. Digests agreed across both painters and all
four thread counts at every size.

Partitioned painter (`paint_tiles_at`), 64-pixel tiles:

| size | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| 32 | 0.45 | 0.45 | 0.45 | 0.45 |
| 64 | 0.50 | 0.50 | 0.50 | 0.50 |
| 128 | 0.70 | 0.78 | 1.05 | 1.18 |
| 256 | 1.40 | 1.15 | 1.23 | 1.30 |
| 512 | 3.77 | 2.35 | 1.80 | 1.77 |
| 1024 | 11.65 | 6.47 | 4.22 | 3.20 |

Whole-frame painter (`paint_faces_at`):

| size | 1 thread | 2 threads | 4 threads | 8 threads |
| --- | ---: | ---: | ---: | ---: |
| 32 | 0.50 | 0.68 | 0.82 | 1.02 |
| 64 | 0.65 | 0.90 | 1.07 | 1.30 |
| 128 | 1.20 | 1.85 | 2.15 | 2.35 |
| 256 | 3.52 | 5.58 | 5.95 | 6.25 |
| 512 | 12.47 | 20.30 | 21.07 | 21.52 |
| 1024 | 47.65 | 78.03 | 81.03 | 81.90 |

Two things moved, and they are separate:

- **One thread, 1024: 47.65 to 11.65 ms.** The whole-frame painter folds its array into
  the quadtree with `fold.go`, which forks an array handle and four tasks at every node:
  about 350,000 interior nodes at 1024. A tile folds its own array in one task, threading
  the one handle through the four quarters, and only the 85 nodes above the 256 tiles
  fork. A region no quad reaches answers its sky without an array at all.
- **Eight threads, 1024: 81.90 to 3.20 ms.** A tile's array is created, written and
  folded inside one task, so nothing is shared and the pool divides the tiles. The
  whole-frame painter's one array has one owner, and every thread added makes it slower.

At 128 the frame is four tiles and at 32 and 64 it is one, so there is nothing for a
pool to divide: 128 pays about half a millisecond for waking it. Every cell of the
first table is far inside the 16.67 ms tick, so the client needs no launch flag.

The tile edge, one 1024x1024 draw, three samples:

| edge | 1 thread | 8 threads |
| ---: | ---: | ---: |
| 16 | 15.85 | 4.22 |
| 32 | 13.32 | 3.52 |
| 64 | 11.75 | 3.05 |
| 128 | 10.93 | 2.98 |

The live presented rate, `bash lab/native/client-probe/run-fps.sh --size=1024`, 600
frames under Xvfb: 60.06 at 1024 and 60.07 at 512 on the default pool, 59.89 at 1024 on
one thread. The same probe read 20.73 at 1024 with the whole-frame painter.

## A defect that was here

`half_open_bounds` resolved a row no edge crosses to the span `[last, last]`, and the
fill wrote at least one pixel, so a quad whose top was not on a pixel row wrote one pixel
in the frame's last column. `span_edges` now answers an empty span for a row nothing
crosses. The gate's tallies did not move, so on those cameras the write was being painted
over.

## Measured on Apple Silicon, macOS: a second lane

Everything above this section is the WSL lane and is not touched by it. This is a different machine
and a different OS, so the two are not comparable and nothing here replaces a number above.

Platform: Apple M1 Pro (10 cores, 8 performance and 2 efficiency), 16-core GPU, macOS 27.0 (26A428),
Apple clang 21, native C, run from `bash lab/native/paint/run.sh` with `RUNS=5 THREAD_COUNTS="1 8"`
(two thread counts, not the four the sections above use), medians of five samples, milliseconds,
2026-10-03. Every run's digests agreed across thread counts. **The Mac was on battery (22%) with Low
Power Mode on for every run in this section**, which lowers CPU and GPU clocks, so the absolute figures are
lower bounds on what the machine does plugged in; the before/after pairs were run back to back in the same
state. They have not been repeated on AC power.

### Before and after the refactor of `native/client.bend`

The client was split into `play`, `room`, `action`, `slabs`, `hour` and `size`, its records were
nested, and three rules moved into `world/`. The same benchmark, on Bend 2.0.32, `--gpu off`, on the
commit before the refactor (`HEAD`, `e1bc69a`) and on the refactored tree. Every phase of a
millisecond or more is within 3% of the other, which is run-to-run noise; none is a measured speedup
or slowdown. What the benchmark does **not** cover is the tick: `lab/native/client-probe/frame_bench.bend`
is the only thing that timed it and it does not compile (it builds the 8-field `Client`, as it did at `HEAD`).

| phase | size | 1 thread, before | 1 thread, after | 8 threads, before | 8 threads, after |
| --- | ---: | ---: | ---: | ---: | ---: |
| client | 32 | 1.30 | 1.32 | 1.07 | 1.07 |
| client | 128 | 2.42 | 2.42 | 1.95 | 1.98 |
| client | 1024 | 37.60 | 37.35 | 8.00 | 8.25 |
| north | 1024 | 35.88 | 35.30 | 14.30 | 14.55 |
| east | 1024 | 22.80 | 22.48 | 10.62 | 10.70 |
| south | 1024 | 26.43 | 25.85 | 10.35 | 10.60 |
| west | 1024 | 38.73 | 37.62 | 15.72 | 15.75 |
| down | 1024 | 40.33 | 38.98 | 15.62 | 15.90 |
| up | 1024 | 16.68 | 16.50 | 7.10 | 7.05 |
| crowd | 1024 | 22.82 | 22.35 | 10.70 | 10.85 |
| herd | 1024 | 23.10 | 22.77 | 10.62 | 10.72 |
| build | — | 46.40 | 46.10 | 49.80 | 50.80 |
| slab | — | 3.50 | 3.50 | 4.00 | 3.90 |
| collide | — | 4.50 | 4.50 | 4.50 | 4.40 |

### `--gpu on` and `--gpu off`, Bend 2.0.35

`--gpu on` makes no difference, and it should not: the painter has no device leaf. `paint_bench` is
compiled with `BANGS 0` (no `!` call), so there is nothing for the runtime to send to the device and
`--gpu on` runs the same CPU pool. Over every phase of a millisecond or more the ratio of on to off is
0.96 to 1.06. What this does show is that the GPU build step now works on this machine (see below),
and that 2.0.35 on the CPU is a little faster than 2.0.32 above: 4% to 8% less on the 1024 frames at
eight threads. That comparison is one run of each compiler, the 2.0.35 runs used the released
`~/.bend/bin/bend` binary rather than the one built from the pin, and it was not repeated, so read it as
a direction and not a figure.

| phase | size | 1 thread, off | 1 thread, on | 8 threads, off | 8 threads, on |
| --- | ---: | ---: | ---: | ---: | ---: |
| client | 32 | 1.32 | 1.32 | 0.93 | 0.90 |
| client | 128 | 2.42 | 2.40 | 1.80 | 1.80 |
| client | 1024 | 36.33 | 35.90 | 7.78 | 7.72 |
| north | 1024 | 34.40 | 33.55 | 13.60 | 13.53 |
| east | 1024 | 21.98 | 21.38 | 9.82 | 9.95 |
| down | 1024 | 39.27 | 38.00 | 15.20 | 15.10 |
| build | — | 45.70 | 45.10 | 48.70 | 49.50 |
| slab | — | 3.50 | 3.50 | 3.95 | 4.20 |

### What it took to build and run on this machine

- The native client builds with `bend native/client.bend -o <out>`, but on macOS the compiler also
  builds a Metal program for any program containing a `!`, and every windowed program does:
  `Image.drop!` in `Base`'s `App.turn` frees the last frame's image. On WSL that step is skipped
  unless CUDA headers exist, which is why `AGENTS.md` says the client has no bang: that is true of
  `native/`, not of the compiled program.
- On Bend 2.0.32 that Metal step failed on this M1 Pro with `XPC_ERROR_CONNECTION_INTERRUPTED`.
  The cause is a crash of Apple's `MTLCompilerService` (`unable to legalize instruction ... load
  monotonic`), upstream issue #1154, present from 2.0.29 on M1 and M2 and fixed in 2.0.35. The CPU
  half of the build still produced a working binary, and `--gpu off` runs it.
- The pin was moved to 2.0.35 for that reason (`docs/vendor-bend.md`).
- The client prints its resolution table and starts, and `--size=` is read by `native/size.bend`. A
  window was not driven by hand, so nothing here says the client plays correctly on macOS.

### The same benchmark plugged in

The runs above were on battery with Low Power Mode on. Repeated on AC power with Low Power Mode off, `--gpu off`,
Bend 2.0.35 built from the pin, the refactored tree, the same `RUNS=5 THREAD_COUNTS="1 8"`, milliseconds:

| phase | size | 1 thread, battery | 1 thread, AC | 8 threads, battery | 8 threads, AC |
| --- | ---: | ---: | ---: | ---: | ---: |
| client | 32 | 1.32 | 1.07 | 0.93 | 0.80 |
| client | 128 | 2.42 | 1.98 | 1.80 | 1.60 |
| client | 1024 | 36.33 | 29.52 | 7.78 | 7.67 |
| east | 1024 | 21.98 | 18.98 | 9.82 | 10.70 |
| north | 1024 | 34.40 | — | 13.60 | 14.65 |
| down | 1024 | 39.27 | — | 15.20 | 18.12 |

Across the phases of a millisecond or more the median ratio of AC to battery is 0.87 (0.77 to 1.19): the
single-thread phases are 14% to 21% faster plugged in, and the eight-thread phases are not consistently faster
(several are within 20% either way, which this benchmark's run-to-run spread does not rule out). Digests agreed.

### The live client on macOS, with the GPU on and off

`bash lab/native/client-probe/run-pace.sh --size=N --gpu on|off` opens a real window and walks the player across
open ground for 900 frames (869 presented), timing each. The same Apple M1 Pro, plugged in, Low Power Mode off,
Bend 2.0.35 built from the pin, the client at the commit that adds this section:

| window | `--gpu` | frames a second | frames over the tick by more than 1 ms | longest frame |
| --- | --- | ---: | ---: | ---: |
| 512 | on | 117.6 | 3 | 19 ms |
| 512 | off | 119.8 | 0 | 11 ms |
| 1024 | on | 77.3 | 24 | 27 ms |
| 1024 | off | 94.9 | 0 | 18 ms |

The client runs on this machine with either setting. `--gpu on` is slower, by 2% at 512 and by 19% at 1024 with
late frames, and that is expected: the painter has no device leaf, so the one bang the program contains
(`Image.drop!`, freeing the last frame's image) is the only thing sent to the device. One run of each, so read the
512 pair as the same. These rates are about twice the 60 Hz that the WSL sections record as the ceiling, so that
ceiling is a property of the WSL/X11 pacing and not of the client. A picture was not captured: the shell used had
no Screen Recording permission.
