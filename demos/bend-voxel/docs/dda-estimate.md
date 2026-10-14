# Corrected region-event count

The corrected estimate replaces the accepted region DDA's binary search in `Axis.count`. It is retained because two independent CPU12 batches reduce complete frame time by 14.8% and 12.5%. Every candidate process beats its paired baseline. Exactly one optimization is tested: estimate the event count, then correct it with the original plane predicate. The [engine diff](dda-estimate-data/candidate.patch) changes only counting and its call in `Axis.advance`.

## Estimate and exact correction

For an axis moving forward, the region permits `L = high - cell` events. Moving backward, it permits `L = cell - low + 1`. In real arithmetic, write `q = origin + time * delta`. The number of crossed planes is `floor(q - cell)` forward and `floor(cell + 1 - q)` backward. The latter equals `cell + 1 - ceil(q)` when the cell is an integer.

The implementation computes that estimate in F32, clamps it before conversion, and applies `U32.min(limit, estimate)` after conversion. The integer clamp also protects the bound when converting a large U32 limit to F32 rounds upward. The estimate is always in `[0,L]`.

`Axis.before` retains the accepted predicate's conversion, subtraction, division, and comparison:

```text
P(0) = true
plane(k) = cell + k            forward
plane(k) = cell + 1 - k        backward
P(k) = (F32(plane(k)) - origin) / delta <= time
```

Within the valid region's plane range, plane times are monotone in event order. If `P(estimate)` is false, correction decrements until the first accepted count. If true, it increments until the first rejected count or the accepted region limit, then returns the last accepted count. This finds the same greatest accepted count as the original search. No fixed rounding-error tolerance or assumption that the estimate differs by at most one is needed. At most `L + 1` different counts are evaluated; the shrinking fuel covers that bound.

`Axis.advanced` still reconstructs the last original plane and checks whether its divided time equals the region exit time. This preserves simultaneous axis crossings, previous cells, and X/Y/Z face priority. The estimated point never selects a final hit directly.

The [formal claims](dda-estimate-data/laws.patch) and [proofs](dda-estimate-data/proof.patch) establish the zero-event sentinel and the correction stopping cases. [Kernel checking passes](dda-estimate-data/proof.txt). These claims do not constitute a formal proof of complete floating-point traversal equivalence; the complete runtime scans below verify the existing scenes.

## Actual work

The baseline's [executed predicate-site counter](dda-estimate-data/baseline-counters-frame.tsv) is named `axis_count_iterations`. The candidate's [counter](dda-estimate-data/candidate-counters-frame.tsv) records the actual comparison site in `Axis.before`, including the zero-event sentinel. Atomic hooks run only in emitted CPU diagnostic C. They are absent from the release binaries and the portable Bend engine. They count predicate executions, not retired floating-point instructions.

| Work per opening frame | Baseline | Candidate |
| --- | ---: | ---: |
| Region lookups | 3,824,783 | 3,824,783 |
| Outside lookups | 83,814 | 83,814 |
| Tree descents / returned leaves | 3,740,969 | 3,740,969 |
| Tree branches visited | 59,823,748 | 59,823,748 |
| Region crossings | 3,562,639 | 3,562,639 |
| Axis advancement / count calls | 10,687,917 | 10,687,917 |
| Actual plane predicate evaluations | 41,374,834 | 17,952,681 |
| Evaluations with event count zero | 906,491 | 2,029,727 |
| Nonzero-event predicate evaluations | 40,468,343 | 15,922,954 |
| Region-trace iterations | 3,824,783 | 3,824,783 |
| Final world hits | 178,330 | 178,330 |
| Final world misses | 83,814 | 83,814 |
| Pixel values constructed | 262,144 | 262,144 |
| Quadtree nodes constructed | 87,381 | 87,381 |
| Image roots | 1 | 1 |

Predicate evaluations fall by 56.6%. The candidate performs 7,264,728 upward probes and 36 downward corrections per frame, with zero fuel exhaustions. Upward probes include the first rejected successor. They are not all changes to the returned estimate. `Pix` is a packed value; `Qua` creates a heap node.

The independent native window runs on [CPU1](dda-estimate-data/candidate-counters-cpu1.tsv) and [CPU12](dda-estimate-data/candidate-counters-cpu12.tsv) have byte-identical totals, exactly five times the frame counts, including four warmups. The corresponding baseline totals also agree. Instrumented exports retain the ordinary image hash. An initially copied baseline diagnostic contained an extra root hook; it was discarded and rebuilt from frozen C with the validated adapter before recording these results.

## Cumulative CPU profiles

Both [baseline](dda-estimate-data/baseline-gprof.txt) and [candidate](dda-estimate-data/candidate-gprof.txt) profiles aggregate three native window runs, each with 12 measured frames and four warmups. They use GPU off, CPU1, fork depth zero, and `clang -O3 -g -pg`. Only the region DDA renderer runs. Initialization is present in these diagnostic profiles; release timings exclude it. [Symbol bindings](dda-estimate-data/symbols.tsv) map generated functions to Bend definitions.

| Function | Baseline exclusive CPU | Baseline including callees | Candidate exclusive CPU | Candidate including callees |
| --- | ---: | ---: | ---: | ---: |
| `Trace.mode` | 1.10% | 93.2% | 1.31% | 90.6% |
| `Trace.regions` | 2.85% | 89.4% | 3.17% | 85.7% |
| `Crossing.region` | 11.42% | 52.3% | 15.40% | 41.3% |
| `Axis.advance`, including counting | 40.92% | 40.9% | 25.95% | 25.9% |
| `Grid.region`, including tree descent | 36.74% | 36.7% | 44.20% | 44.2% |

Inclusive rows overlap. Across the same 48 frames, axis advancement's sampled CPU time falls from 18.24 to 9.10 seconds. Region lookup changes from 16.38 to 15.50 seconds and becomes the dominant remaining cost. `Frame.seq` and its image-construction continuations account for about 3.5% exclusive CPU before and 4.9% after; construction counts are unchanged. Profile overhead and compiler inlining make these diagnostics unsuitable as release speed measurements.

The earlier [diagnostic that isolates `Axis.count`](dda-profile-data/accepted-count-gprof.txt), using this same frozen baseline source, attributes 33.84% of CPU time to the binary search. That identifies the search as the main component targeted inside axis advancement.

## Complete-frame measurements

The unchanged [A/B driver](../scripts/dda_ab.bend) runs five process pairs in order `AB, BA, AB, BA, AB`. Each process warms four complete frames. The interval includes 512 by 512 rendering, native window presentation, and image disposal. Scene construction is excluded. All processes exit successfully and finish their requested frames. No compilation, proof checking, profiling, or counter collection overlaps these release runs.

The machine is a Ryzen 5 1600 with six physical cores and twelve logical CPUs, a GTX 1660, and Bend 2.0.34. Desktop and browser applications remain active. [Hardware](dda-estimate-data/machine.txt) and [final-run load](dda-estimate-data/final-machine.txt) are recorded. Interleaved pairs and an independent CPU12 repeat account for the observed desktop noise. These results describe cached rendering on this machine.

| Configuration | Measured frames per process | Baseline median, min to max, ms/frame | Candidate median, min to max, ms/frame |
| --- | ---: | ---: | ---: |
| [CPU12, fork 6](dda-estimate-data/cpu12.tsv) | 32 | 132.8125, 125.25 to 139.15625 | 113.15625, 108.59375 to 126.96875 |
| [CPU12 independent repeat, fork 6](dda-estimate-data/cpu12-repeat.tsv) | 32 | 127.09375, 125.78125 to 132.6875 | 111.15625, 110.34375 to 112.84375 |
| [CPU1, fork 0](dda-estimate-data/cpu1.tsv) | 4 | 851.5, 843.5 to 888.25 | 723.25, 715.75 to 788.25 |
| [GPU, fork 6](dda-estimate-data/gpu6.tsv) | 2 | 834.0, 763.5 to 887.5 | 521.0, 503.0 to 545.0 |
| [GPU, fork 7](dda-estimate-data/gpu7.tsv) | 2 | 789.0, 771.5 to 846.5 | 520.5, 507.0 to 542.0 |
| [Carved cube, CPU12, fork 6](dda-estimate-data/cube-cut.tsv) | 32 | 17.0, 16.75 to 18.3125 | 16.90625, 16.71875 to 17.125 |

Every row uses five samples per side. The first CPU12 batch has overlapping overall ranges but all five paired comparisons improve. The independent repeat has non-overlapping ranges and all five paired comparisons improve. The CPU12 frame-time reductions are 14.8% and 12.5%, so the acceptance criterion is satisfied. CPU1 improves by 15.1%. GPU improves by 37.5% at fork 6 and 34.0% at fork 7, measured separately on the available GPU lane. The carved-cube ranges overlap, so no improvement is established for that smaller workload. No parallel decomposition or second optimization is introduced.

## Exact correctness and reproduction

[Seven complete CPU scans](dda-estimate-data/verification.txt) compare candidate region DDA with unit DDA on Atelier opening, Atelier `--cut`, cube, carved cube, inside, axis-aligned, and opposite views. All 1,835,008 rays have identical hit presence, exact F32 depth, cell, direction, and material. Every exported image is byte-identical to both the frozen region baseline and the unit reference. [GPU fork 6](dda-estimate-data/gpu-verification.txt) also preserves all seven images. The opening is additionally checked on CPU12 and GPU fork 7. The opening hash remains `c6a3a915ebfc7b8707b622aeab5f175939a9eff6cb3912716270db01b18e6de9`; the carved-cube hash remains `8ce41c1f33462090a5d0bfd9a8da2347a4cd371980d86a69f91117e472cc2119`.

The retained [candidate snapshot](dda-estimate-data/candidate-dda.bend) and root `dda.bend` have SHA-256 `0a20e959d87eec22b4c182e2eca7cb520d586c157c1366fa4a399d7bbf6f00d8`. The [baseline snapshot](dda-estimate-data/baseline-dda.bend) has SHA-256 `dd147799e61710421b30a022738f17f5c2a7aad73ecd3b2a74f65959ed2915da`. [Source](dda-estimate-data/source-hashes.txt), [build](dda-estimate-data/build-hashes.txt), and [image](dda-estimate-data/image-hashes.txt) manifests identify the artifacts. All reported candidate evidence uses the final integer-bounded build. Snapshots keep root-relative imports; copy them to `dda.bend` in separate copies of the project before compiling.

The local frozen binaries and emitted C are in `.audit/dda-estimate/`. The installed `build/dda-compare` is the retained candidate. To repeat the primary measurement and inspect counters:

```sh
make build/dda-compare build/dda-ab build/dda-profile build/dda-estimate-profile
bend PROOF.bend --verdict
build/dda-compare --gpu off --threads 1 -- --verify-steps
build/dda-ab --gpu off --threads 1 -- .audit/dda-estimate/baseline-renderer build/dda-compare 12 off 6 32 build/dda-count-ab.tsv
build/dda-ab --gpu off --threads 1 -- .audit/dda-estimate/baseline-renderer build/dda-compare 1 on 6 2 build/dda-count-gpu-ab.tsv

build/dda-profile --gpu off --threads 1 -- .audit/dda-estimate/baseline.c build/dda-baseline-counters.c counters
build/dda-estimate-profile --gpu off --threads 1 -- .audit/dda-estimate/candidate.c build/dda-estimate-counters.c
clang -D_GNU_SOURCE= -O3 -g build/dda-estimate-counters.c -o build/dda-estimate-counters -lm -lpthread -ldl -lX11
build/dda-estimate-counters --gpu off --threads 12 -- --renderer dda --fork-depth 6 --bench 1
```

The adapters validate emitted parameter anchors and predicate sites before instrumenting. Another compiler or source revision can change symbol bindings and requires inspection before updating the map. For cumulative CPU profiling, compile each frozen C file with `clang -O3 -g -pg`, run three GPU-off CPU1 batches with distinct `GMON_OUT_PREFIX` values, and combine their profile files with `gprof -s`. Keep those files separate for the two executables.
