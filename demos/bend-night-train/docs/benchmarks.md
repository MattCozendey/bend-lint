*English | [Русский](ru/benchmarks.md)*

# Benchmarks: Bend 2 parallelism on a real workload

All numbers below were produced on this machine and are reproducible with the
commands in the text. Raw data: `bench/results.csv` (54 runs).

## The machine

| | |
|---|---|
| CPU | Intel Core i9-14900HX, 24 physical cores |
| Logical CPUs | 32 (`nproc` → 32), two hardware threads per core (SMT) |
| RAM | 125 GiB |
| CPU scaling | `intel_pstate`, governor `performance` for the sweep (the host idles on `powersave`), turbo enabled, frequency not pinned |
| clang | 18.1.3 |
| Bend | 2.0.5, launched through `tools/bend` |
| Workload | `src/main.bend` — the rasteriser: a four-way parallel quadtree walk, one tile of pixels per leaf |

A frame is a quadtree of depth `d`, that is `2^d × 2^d` pixels. Depths 8 / 9 /
10 are 65 536 / 262 144 / 1 048 576 pixels. Unlike the earlier ray-marching
renderer, a leaf is not one pixel but an 8×8 tile that carries the triangles
whose screen box reaches it, so the tree is `d - 3` levels deep.

## Method

```sh
make build
REPS=3 ./bench/bench.sh out/night-train bench/results.csv
```

`bench/bench.sh` covers every `(depth, threads)` cell three times, after a single
warm-up pass, and times each run with `/usr/bin/time -f "%e %U"`. Every run sets
`NT_PPM=0`, so PPM I/O is not timed. The number reported below is the median of
the three reps. There is one lane only: the renderer has no `!` call, so
`--backend`, `--bang` and `--gpu` no longer exist.

For resolution finer than `/usr/bin/time`'s centiseconds, `bench/measure.py`
repeats a single command with `perf_counter` and `getrusage` and prints the
median:

```sh
python3 bench/measure.py --reps 5 --env NT_DEPTH=10 --env NT_PPM=0 -- ./out/night-train --threads 8
```

## 1. Scaling with cores

`bench/results.csv`, median of 3 reps, seconds. Each cell is
`wall_s / user_s / (user_s ÷ wall_s)`:

| depth | t=1 | t=2 | t=4 | t=8 | t=16 | t=32 | checksum |
|---|---|---|---|---|---|---|---|
| 8 (256²) | 0.360 / 0.33 / 0.92 | 0.260 / 0.39 / 1.50 | 0.220 / 0.44 / 2.00 | 0.200 / 0.47 / 2.35 | 0.190 / 0.48 / 2.53 | 0.160 / 0.49 / 3.06 | 299380445 |
| 9 (512²) | 0.660 / 0.62 / 0.94 | 0.400 / 0.67 / 1.68 | 0.290 / 0.72 / 2.48 | 0.240 / 0.76 / 3.17 | 0.230 / 0.84 / 3.65 | 0.190 / 0.92 / 4.84 | 1065901264 |
| 10 (1024²) | 1.660 / 1.63 / 0.98 | 0.900 / 1.65 / 1.83 | 0.580 / 1.71 / 2.95 | 0.430 / 1.79 / 4.16 | 0.370 / 2.05 / 5.54 | 0.310 / 2.55 / 8.23 | 3959815329 |

Speed-up at 32 threads: depth 8 = 2.3×, depth 9 = 3.5×, depth 10 = 5.4×.
Wall time keeps falling all the way to 32 threads; there is no ceiling.

![Wall time against thread count for depths 8, 9 and 10; depth 10 falls from 1.66 s to 0.31 s](../assets/readme/bench-scaling.svg)

*The same numbers as a picture. The digest is one value per depth at every thread count,
so the shape of the curves is scheduling, not a change in the picture.*

## 2. Where the CPU goes

Total child CPU grows far more slowly than the speed-up, not faster:

| depth | CPU at 1 thread | CPU at 32 threads | CPU growth | wall speed-up |
|---|---|---|---|---|
| 8 | 0.33 s | 0.49 s | 1.5× | 2.3× |
| 9 | 0.62 s | 0.92 s | 1.5× | 3.5× |
| 10 | 1.63 s | 2.55 s | 1.6× | 5.4× |

At depth 10 the total CPU rises by 56% while wall time falls 5.4×, and
`user ÷ wall` reaches 8.2 at 32 threads. (The ray-marching renderer, by
contrast, pinned at 2.7× with CPU growing roughly eightfold.)

What the source supports about the shape of the work: the leaf of the tree is
an 8×8 tile, and `Frame.build` hands each leaf only the triangles
(`Tri.keep`) and billboards (`Spr.keep`) whose screen bounds reach that tile.
Every pixel of the tile then walks that short list once and is shaded by at
most one triangle, so a leaf's cost is bounded by its pixel count times a
small, local list — not by a per-pixel march whose length depends on what the
ray meets. That is consistent with the measured behaviour: more threads keep
helping, and the CPU cost grows slowly. The scheduler itself was not profiled,
so no claim is made here about why it behaves as it does at a given thread
count.

## 3. Purity check

All 54 runs gave exactly one digest per depth, independent of the thread count:

| depth | pixels | digest |
|---|---|---|
| 8 | 65 536 | 299380445 |
| 9 | 262 144 | 1065901264 |
| 10 | 1 048 576 | 3959815329 |

`Raster.digest` folds the frame with `Frame.sum`, which adds an avalanche-mixed
hash of each pixel (`Frame.hash1`). Addition commutes, so equal digests prove
the same *set* of pixels, not their arrangement; placement is checked visually
against the frames in `assets/frames/`. Equality across thread counts is the
parallelism correctness check: the picture does not depend on the walk order.

## 4. Limits of the measurement

- `/usr/bin/time %e` prints centiseconds, so every wall and user figure carries a 10 ms quantum. At depth 8 with one thread (0.36 s) that is about 3% of the number, and smaller differences are not resolved.
- Three reps per cell, median only. No spread or confidence interval is reported.
- The 32 logical CPUs are 24 physical cores under SMT. Thread counts above 16 land on hardware threads, not on extra cores, so part of the curve above 16 is SMT, not more silicon.
- The scaling governor was set to `performance` before the sweep, since the host idles on `powersave` and a short frame is exactly where the governor's ramping shows up. The numbers are therefore not directly comparable with runs taken at the idle setting. Turbo is still enabled and the clock is not pinned, so wall time depends on the boost and thermal state around each run; the medians reduce this but do not remove it. The sweep was taken on an otherwise quiet host; no contended run is published here.
- Wall time includes fixed per-process cost (start-up, binary load, geometry projection), not only the tile loop. `NT_PPM=0` removes PPM file I/O, so the figure is a whole program run, not a rasteriser kernel time.
- One host, one compiler, one build, one scene. There is no second backend or compiler to compare against.
