# bench/ — the CPU timing harness

`bench.sh` times one rendered frame at several depths and thread counts and
records wall time, CPU time and the frame checksum.  `measure.py` times a single
command with `perf_counter` + `getrusage` and reports the median of N runs — use
it when centisecond `/usr/bin/time` resolution is too coarse, or to see the
CPU/wall ratio.

The renderer has no `!` call — the device lane was measured and dropped, see
`docs/journal.md` — so there is only one lane.  `bench.sh` has no backend or
call-form knob, and `--gpu` would be inert.

Build first:

```sh
make build
```

## Columns

`results.csv` has one schema:

| column | meaning |
|---|---|
| `depth` | quadtree depth `d`; the frame is `2^d × 2^d` pixels (`NT_DEPTH`) |
| `threads` | value passed to `--threads` |
| `rep` | 1-based repetition within this cell |
| `wall_s` | wall-clock seconds for the run (`/usr/bin/time %e`) |
| `user_s` | child CPU seconds (`/usr/bin/time %U`); the CPU/wall ratio is `user_s / wall_s` |
| `checksum` | the frame digest printed on stdout; the correctness check |

Every run writes `NT_PPM=0`, so the timed section is the render, not PPM I/O.

## Full sweep

```sh
REPS=3 ./bench/bench.sh out/night-train bench/results.csv
```

Defaults: `DEPTHS="8 9 10"`, `THREADS="1 2 4 8 16 32"`, `REPS=3`.  Every knob is
also a flag; flags override the environment.  A single warm-up pass runs before
the timed cells.

## One cell (`depth`, `threads`, `reps`)

Re-measure a single cell without the full 54-run sweep:

```sh
# depth 10, 8 threads, 5 reps, into its own file
./bench/bench.sh --depth 10 --threads 8 --reps 5 --out bench/results-d10.csv

# the same number with perf_counter resolution, no CSV
python3 bench/measure.py --env NT_DEPTH=10 --env NT_PPM=0 \
  --reps 5 -- ./out/night-train --threads 8
```

`--depth` and `--threads` take one value (single cell) or a quoted list (sweep).
`--out FILE` picks the CSV, and the first two positional arguments remain
`binary` and `csv`, so existing `make bench` invocations keep working.

## Correctness check

The render is pure, so the checksum must not depend on the thread count.
Verified for depths 8, 9 and 10, over all six thread counts and three reps (54
runs), one digest per depth:

| depth | pixels | checksum |
|---|---|---|
| 8 | 65 536 | 299380445 |
| 9 | 262 144 | 1065901264 |
| 10 | 1 048 576 | 3959815329 |

The digest is an order-independent fold: `Raster.digest` sums an
avalanche-mixed hash of every pixel (`Frame.hash1` → `Frame.sum`).  Addition
commutes, so equal digests prove the same *set* of pixels, not their positions;
placement is checked visually against `assets/frames/`.

## Publishing numbers

Only numbers from a quiet host are publishable.  While other builds or
renders run in parallel, wall time is contended: record such a run in
`bench/out/` (`/bench/out/` is gitignored) with `contended` in the filename,
never in `bench/results.csv`.
