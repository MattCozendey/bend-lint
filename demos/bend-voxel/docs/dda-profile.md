# Accepted region DDA profile

The accepted region DDA is retained. Exactly one candidate was tested: stop `Axis.count` when its binary-search bounds converge. It removed 9.59% of search iterations, preserved exact hits and images, and produced no repeatable end-to-end improvement. The candidate was reverted. No traversal, world representation, parallel decomposition, or shading changes remain in `dda.bend`.

## Cumulative CPU cost

These profiles run only `--renderer dda` on the Atelier opening, with GPU dispatch disabled, one CPU thread, and fork depth zero. They include native window presentation and image disposal. Initialization and four warmup frames per process appear in the cumulative profile; release benchmark timings exclude both initialization and warmup.

The accepted source and native executable were frozen before profiling. Three `clang -O3 -g -pg` runs, each with 16 measured frames and four warmups, were combined with `gprof -s`. The [full flat profile and cumulative call graph](dda-profile-data/accepted-gprof.txt) cover 60 rendered frames and 54.55 sampled CPU seconds.

| Function | Exclusive CPU | Including callees | Calls per frame |
| --- | ---: | ---: | ---: |
| `Trace.mode` | 1.15% | 93.6% | 262,144 |
| `Trace.regions` | 2.46% | 89.6% | 262,144 |
| `Crossing.region` | 11.79% | 53.7% | 3,562,639 |
| `Axis.advance`, including inlined `Axis.count` | 41.92% | 41.9% | 10,687,917 |
| `Grid.region`, including tree descent | 35.89% | 35.9% | 3,824,783 |

Inclusive rows overlap and must not be added. The dominant remaining cost is axis advancement, with region lookup close behind. The generated symbol bindings are `spin_45` = `Axis.count`, `spin_61` = `Axis.advance`, `spin_63` = `Tree.region`, `spin_99` = `Crossing.region`, `spin_102` = `Grid.region`, `spin_103` = `Grid.region.valid`, `spin_141` = `Trace.regions`, and `spin_181` = `Trace.mode`.

A second [cumulative profile](dda-profile-data/accepted-count-gprof.txt) makes only `spin_45` non-inline in the emitted C. Three runs of 12 measured frames plus four warmups cover 48 frames and 44.06 sampled CPU seconds. It attributes 33.84% of CPU time to `Axis.count` itself. Region lookup takes 36.90%; crossing calculations take 18.34% exclusively and 52.2% including the search. This diagnostic changes call overhead, so its percentages are explanatory and its timings are not speedup measurements.

`Frame.seq` and its four image-construction continuations account for about 3.5% exclusive CPU in the first profile. Its 95.1% inclusive cost includes tracing every pixel. The image-construction counters below distinguish those costs. `Pix` is a packed value in emitted C; it does not allocate a heap node. `Qua` constructs a node containing four children.

## Actual work counters

[The profiling adapter](../scripts/dda_profile.bend) is written in Bend. It injects atomic counters at actual emitted native function entries, tail-loop bodies, plane-predicate evaluations, final ray returns, and image constructor sites. It checks parameter anchors for all eight function bindings before writing an instrumented file. No alternate tracer or synthetic workload supplies these counts. The C hooks are confined to this CPU diagnostic tool and are absent from release binaries and core GPU algorithms.

[One complete frame](dda-profile-data/counters-one-frame.tsv) records the following work. The independently instrumented [1-thread native window run](dda-profile-data/counters-cpu-1.tsv) and [12-thread native window run](dda-profile-data/counters-cpu-12.tsv) each render five frames, including warmup, and have identical totals. Counter overhead is substantial; those elapsed times are not used in performance comparisons.

| Event | Accepted per frame | Candidate per frame |
| --- | ---: | ---: |
| Region lookups, including outside queries | 3,824,783 | 3,824,783 |
| Outside queries | 83,814 | 83,814 |
| Tree descents / returned leaves | 3,740,969 | 3,740,969 |
| Branch nodes visited during descents | 59,823,748 | 59,823,748 |
| Region crossings | 3,562,639 | 3,562,639 |
| Axis advancement calls | 10,687,917 | 10,687,917 |
| `Axis.count` calls | 10,687,917 | 10,687,917 |
| `Axis.count` iterations evaluating the plane predicate | 41,374,834 | 37,406,545 |
| Predicate evaluations after bounds converge | 3,968,289 | 0 |
| Predicate evaluations with midpoint zero | 906,491 | 0 |
| Region-trace loop iterations | 3,824,783 | 3,824,783 |
| Final world hits | 178,330 | 178,330 |
| Final world misses | 83,814 | 83,814 |
| Pixel values constructed | 262,144 | 262,144 |
| Quadtree nodes constructed | 87,381 | 87,381 |
| Image roots dispatched | 1 | 1 |

Hits and misses are `SurfaceHit` results before ground/background shading. Search iterations count executed source-level predicate sites, not retired processor instructions. The [candidate frame counters](dda-profile-data/candidate-counters-one-frame.tsv) and [candidate 12-thread totals](dda-profile-data/candidate-counters-cpu-12.tsv) confirm that only search work changes. Instrumented exports also match the ordinary renderer byte for byte.

## One optimization experiment

The [candidate diff](dda-profile-data/candidate.patch) carries a Boolean indicating that the updated search bounds are equal. On the next call, the search returns its lower bound immediately. All remaining comparisons use the original plane conversion, subtraction, division, and comparison. Crossing selection, tied axes, entry/exit surfaces, and tree queries are unchanged.

The search starts with lower bound zero. Each successful comparison establishes that the new lower bound is accepted; a failed comparison retains that bound. With converged bounds, repeated comparisons cannot change the selected count for the current valid grid ranges. The archived [formal claim](dda-profile-data/candidate-laws.patch) and [proof](dda-profile-data/candidate-proof.patch) establish that a settled search returns its bound for every fuel value. They do not claim a formal proof of complete floating-point traversal equivalence; real hit and image equality checks establish the tested workload behavior.

Before timing, the expected benefit was small: only 9.59% of this search's iterations were redundant, against roughly one third of CPU time. The candidate also adds a bounds comparison and a branch. Reducing the count alone therefore did not establish a speedup.

[The A/B runner](../scripts/dda_ab.bend) invokes the frozen accepted and candidate release executables in alternating pair order, `AB, BA, AB, BA, AB`. Every process warms up four full native window frames before its measured interval. Rendering, window presentation, and image disposal are measured; construction of the scene is excluded. Both sides use identical thread and decomposition settings. All ten processes in each configuration completed successfully. Desktop and browser applications remained active; [machine information](dda-profile-data/benchmark-machine.txt) records the load and CPU. No compilation, proof checking, profiling, or counter runs overlapped the release timing matrix.

The machine has an AMD Ryzen 5 1600, six physical cores and twelve logical CPUs, with a GTX 1660 and Bend 2.0.34. CPU and GPU decomposition are measured separately; GPU results are not inferred from CPU thread scaling.

| Configuration | Measured frames per process | Accepted median, range, ms/frame | Candidate median, range, ms/frame |
| --- | ---: | ---: | ---: |
| [CPU, 1 thread, fork 0](dda-profile-data/cpu-1.tsv) | 4 | 865.0, 854.5–910.5 | 853.0, 835.75–860.5 |
| [CPU, 12 threads, fork 6](dda-profile-data/cpu-12.tsv) | 16 | 134.3125, 125.5–139.6875 | 138.8125, 131.9375–139.5 |
| [GPU, fork 6](dda-profile-data/gpu-6.tsv) | 2 | 825.0, 776.0–920.5 | 965.0, 781.0–990.0 |
| [GPU, fork 7](dda-profile-data/gpu-7.tsv) | 2 | 862.0, 799.0–951.5 | 871.5, 792.0–965.5 |
| [Carved cube, CPU 12, fork 6](dda-profile-data/cube-cut.tsv) | 32 | 18.09375, 17.59375–18.53125 | 18.125, 17.34375–19.15625 |

Each median and range uses five independent process samples per side. Ranges overlap in every configuration. The small 1-thread median improvement does not establish a repeatable gain, and the primary 12-thread configuration has a higher candidate median. Both GPU medians are higher, especially at fork 6. The candidate is rejected. No second optimization was tested.

## Exact correctness and final state

The candidate's region traversal and unit DDA produce identical hit presence, F32 depth, cell coordinates, direction, and material on all 262,144 rays for each of seven complete CPU scans: Atelier opening, Atelier `--cut`, full cube, carved cube, camera inside the cube, an axis-aligned view, and the opposite view. [Verification output](dda-profile-data/verification.txt) records zero mismatches on 1,835,008 rays.

For every scan, the accepted renderer, candidate, and unit reference export byte-identical PPMs. Additional accepted/candidate exports match on CPU 12 and on GPU fork depths 6 and 7. GPU carved-cube exports also match. [All hashes](dda-profile-data/image-hashes.txt) are preserved. The opening SHA-256 is `c6a3a915ebfc7b8707b622aeab5f175939a9eff6cb3912716270db01b18e6de9`; the carved-cube SHA-256 is `8ce41c1f33462090a5d0bfd9a8da2347a4cd371980d86a69f91117e472cc2119`.

The candidate passed both [Bend proof checking](dda-profile-data/proof.txt) and [kernel verdict checking](dda-profile-data/proof-verdict.txt). The rejected implementation and its formal claims are archived as evidence. Root `dda.bend`, `LAWS.bend`, and `PROOF.bend` were restored to the accepted versions, and [the final proof gate](dda-profile-data/final-proof.txt) was rerun. The retained engine source hash is `dd147799e61710421b30a022738f17f5c2a7aad73ecd3b2a74f65959ed2915da`.

## Reproduction

The [accepted source snapshot](dda-profile-data/accepted-dda.bend) and [candidate source snapshot](dda-profile-data/candidate-dda.bend) keep their original root-relative imports. Copy each into `dda.bend` in separate copies of this project before compiling. The source files in this evidence directory are snapshots, not standalone entry points. Do not replace the accepted root engine merely to rerun the rejected candidate. The existing `.audit/region-profile/` directory contains both frozen executables, GPU companions, emitted C, instrumented builds, and images.

After building `scripts/dda_compare.bend` to `accepted` and `candidate` in those copies, run the isolated A/B driver from the project root:

```sh
make build/dda-ab build/dda-profile
build/dda-ab --gpu off --threads 1 -- /path/to/accepted /path/to/candidate 12 off 6 16 build/region-ab.tsv
# GPU decomposition is a separate measurement.
build/dda-ab --gpu off --threads 1 -- /path/to/accepted /path/to/candidate 1 on 6 2 build/region-gpu-ab.tsv
```

Emit and profile the accepted renderer from the copy containing its source:

```sh
bend scripts/dda_compare.bend -o accepted.c
clang -O3 -g -pg accepted.c -o accepted-prof -lm -lpthread -ldl -lX11
GMON_OUT_PREFIX="$PWD/accepted-profile" ./accepted-prof --gpu off --threads 1 -- --renderer dda --fork-depth 0 --bench 16
gprof -b accepted-prof accepted-profile.* > accepted-gprof.txt
# Combine multiple profile files with gprof -s before displaying gmon.sum.

build/dda-profile --gpu off --threads 1 -- accepted.c accepted-count-prof.c profile
clang -O3 -g -pg accepted-count-prof.c -o accepted-count-prof -lm -lpthread -ldl -lX11

build/dda-profile --gpu off --threads 1 -- accepted.c accepted-counters.c counters
clang -D_GNU_SOURCE= -O3 -g accepted-counters.c -o accepted-counters -lm -lpthread -ldl -lX11
./accepted-counters --gpu off --threads 1 -- --renderer dda --fork-depth 0 --bench 1
./accepted-counters --gpu off --threads 12 -- --renderer dda --fork-depth 6 --bench 1
```

The adapter pins emitted symbol/parameter bindings to these Bend 2.0.34 builds and rejects a changed map. Inspect and update bindings if another compiler emits different functions. `-D_GNU_SOURCE=` enables the native diagnostic runtime's affinity declarations before the injected standard headers. These commands build CPU profiling tools; use Bend's ordinary build for GPU measurements.
