# DDA region traversal

Uniform-region traversal cuts native Atelier DDA frame time from 887 to 124 ms on twelve CPU threads, a 7.2× speedup. On the available GPU, fork depth 6 improves from 2780.5 to 815.5 ms, a 3.4× speedup. These are medians of five alternating samples. The recorded surfaces and complete exported images stay identical to unit DDA.

The minimal DDA's compressed tree already stores large empty regions. A unit-step walk discards that information and searches from the root at every voxel. The optimization returns a leaf's bounds with its material, then crosses the entire uniform region before reading the tree again.

## What the two upstream renderers share

Both implementations make occupancy cheaper to read than a general voxel record, but their storage fits different terrain limits.

| Renderer | World representation | Work during DDA |
| --- | --- | --- |
| [Costa's `world.bend`](https://github.com/costamatheus97/bend-craft/blob/1885dd3f836825c64a5d57590166ef25d8c17c4e/world.bend) | Dense terrain, 64 blocks high. Four byte-sized material IDs per word along Y. Columns grouped into 16×16 chunks. A separate bitmask describes occupied 4×4×4 groups. | Reads packed material words. The CPU can skip empty groups. |
| [Adriel's `world.bend`](https://github.com/AdrielSantana/bendcraft/blob/3c7775ae686ba30c5301defd9a497f680c884fa0/src/world.bend) | A moving 128×128 ring of columns, 32 blocks high. A column has one solid mask and four words of material nibbles, beside water and other state. | [Caches occupancy on entering a column](https://github.com/AdrielSantana/bendcraft/blob/3c7775ae686ba30c5301defd9a497f680c884fa0/src/render.bend). Vertical steps move a bit mask. The material is read at the hit. |
| This renderer | A compressed binary material tree over a power-of-two cube. Splits cycle through X, Y, and Z. | Previously searched the root at each voxel. Now reads one uniform region and crosses it. |

The transferable idea is to reuse occupancy knowledge until the ray leaves the region it describes. A dense column array would impose terrain dimensions and material packing on this engine, whose Atelier scene spans a 512³ extent and contains large holes. The existing tree provides those regions without a second world representation.

Costa's [optimization log](https://github.com/costamatheus97/bend-craft/blob/1885dd3f836825c64a5d57590166ef25d8c17c4e/OPTIMIZATIONS.md) reports that empty-group skipping helped the CPU and slowed the GPU. Adriel's [performance notes](https://github.com/AdrielSantana/bendcraft/blob/3c7775ae686ba30c5301defd9a497f680c884fa0/docs/perf.md) report little benefit from skipping empty grass steps because blade tests dominated that workload. Those results motivate separate measurements here. Their frame times use different scenes, hardware, presentation paths, and compiler branches, so they are not a speed comparison with this engine.

## How the jump preserves a surface

`Tree.region` returns the material and half-open bounds of the leaf containing a cell. `Crossing.region` computes the first region boundary along the ray. For each axis, `Axis.count` searches for the number of original grid-plane events at or before that time. It evaluates the same plane division as `Axis.next`.

This event count avoids reconstructing a cell by rounding `eye + t * ray`, which can choose a neighbor at a floating-point boundary. The jump advances every axis with an event at the exit time, restores the last previous cell, and retains the unit DDA's X, Y, Z face priority. A ray starting inside occupied material crosses uniform solid regions until it reaches air.

World construction and material IDs stay the same. The jump creates no parallel work at a leaf. Frame parallelism remains configurable, and the same Bend algorithm runs with GPU dispatch enabled or disabled.

The unit walk remains available as `--renderer dda-step`. `--verify-steps` compares both real traversals for all 262,144 pixel rays and fails on any difference in hit presence, exact depth, cell, direction, or material. The existing `--verify` compares against projected faces. Formal laws establish that a region lookup returns the same material as the unit lookup, outside regions are empty, stationary axes stay fixed, and zero fuel ends traversal. Full floating-point traversal equivalence is established by runtime evidence for the recorded scenes, not claimed as a general formal theorem.

## Native CPU measurements

The Atelier scene uses the real 512×512 native window. Every row is the median of five alternating samples, each after four warm-up frames. Timings include rendering, presentation, and image disposal. Initialization is outside the measurements. The machine has a Ryzen 5 1600 with twelve logical threads and runs Bend 2.0.34. Desktop applications remain open. [manifest.txt](dda-region-data/manifest.txt) identifies the source, native binaries, and machine.

| CPU configuration | Unit DDA ms/frame | Region DDA ms/frame | Reduction in frame time | Unshadowed faces ms/frame | Production ms/frame |
| --- | --- | --- | --- | --- | --- |
| 1 thread, fork depth 0 | 6741 | 856 | 87.3% | 589 | 652 |
| 6 threads, fork depth 6 | 1245.25 | 168.75 | 86.4% | 113.75 | 143.75 |
| 12 threads, fork depth 6 | 887 | 124 | 86.0% | 95.25 | 116 |

The one-thread region range is 854 to 862 ms, against 6706 to 6755 ms for the unit walk. The twelve-thread range is 121.5 to 129.75 ms, against 882.75 to 898.5 ms. Their measured speedups are 7.9× and 7.2× respectively. Each one-thread sample measures one frame, and each twelve-thread sample measures four frames. Raw samples are in [cpu-1.tsv](dda-region-data/cpu-1.tsv) and [cpu-12.tsv](dda-region-data/cpu-12.tsv).

The six-thread region range is 166.25 to 170.75 ms, against 1241.75 to 1253.5 ms for the unit walk, a 7.4× speedup. Each sample measures four frames. [cpu-6.tsv](dda-region-data/cpu-6.tsv) contains those samples.

Both traversal modes use the same typed split axes and tree. These unit results therefore isolate region traversal against the current unit reference. The historical [minimal DDA comparison](dda-comparison.md) used numeric split axes and a separately recorded build.

Region traversal closes much of the DDA's CPU gap, but the unshadowed face renderer remains faster on Atelier. The production renderer also includes shadows that both DDA modes omit. The application continues to use production rendering.

## GPU measurements and the smaller world

GPU execution uses the same algorithm on the GeForce GTX 1660 with strict `--gpu on`. Each sample measures two native frames after four warm-up frames. Fork depths are measured separately, with five alternating samples per configuration.

| GPU tile and fork depth | Unit DDA ms/frame | Region DDA ms/frame | Region range ms/frame | Unshadowed faces ms/frame | Production ms/frame |
| --- | --- | --- | --- | --- | --- |
| 5 | 3616 | 1382.5 | 1337–1395.5 | 4827.5 | 5078 |
| 6 | 2780.5 | 815.5 | 785.5–845 | 1257.5 | 1266 |
| 7 | 2903 | 823 | 806.5–861 | 763 | 759.5 |

Region traversal improves every measured GPU decomposition. Depths 6 and 7 have overlapping ranges, so this run does not establish a region-DDA winner between them. Unit ranges also overlap: 2668.5 to 2954 ms at depth 6 and 2712.5 to 3045.5 ms at depth 7. The respective speedups are 3.4× and 3.5×. At depth 5 the improvement is 2.6×, but broader sequential leaves remain expensive. Raw samples are in [gpu-5.tsv](dda-region-data/gpu-5.tsv), [gpu-6.tsv](dda-region-data/gpu-6.tsv), and [gpu-7.tsv](dda-region-data/gpu-7.tsv).

The face renderer and production renderer have lower medians at depth 7, but their ranges overlap region DDA. This GPU comparison does not establish a gain over the tuned face renderer. On this machine, twelve-thread CPU execution remains much faster than GPU execution for region DDA.

The carved 8³ cube shows no measurable difference. On twelve threads at fork depth 6, both traversals have a 17.42 ms/frame median across five alternating samples of twelve measured frames. The unit range is 16.83 to 17.50 ms, and the region range is 16.67 to 18.33 ms. The unshadowed face control measures 19.75 ms, and production with shadows measures 44.75 ms. [cube-cut.tsv](dda-region-data/cube-cut.tsv) records the samples. The optimization targets the large sparse world; this smaller world does not provide much traversal work to remove.

## Correctness and the work removed

Seven complete CPU comparisons cover the Atelier opening and its `--cut` variant and the opening, carved, inside-solid, axis-aligned, and opposite cube views. All 1,835,008 rays have exactly equal hit presence, depth, cell, direction, and material under region and unit traversal.

The opening Atelier exports match byte for byte across sequential CPU, twelve-thread CPU, and GPU fork depths 5, 6, and 7. They also match the export from the original pre-optimization build. The Atelier `--cut` variant and carved cube exports match between CPU and GPU. The Atelier variant leaves the opening-view export unchanged; the cube cut visibly changes its export. [verification.txt](dda-region-data/verification.txt) contains the results and image hashes. Comparison against the face renderer retains the earlier three boundary-color differences, with no coverage or depth differences.

Both `bend PROOF.bend` and `bend PROOF.bend --verdict` pass. [proof.txt](dda-region-data/proof.txt) records the result. The split axis is an explicit X, Y, or Z variant, so the lookup-preservation proof covers every internal axis state.

The earlier [CPU profile](dda-data/profile.txt) placed about 59.7% of sampled CPU time in tree lookup and 35.6% in the voxel walk. That one-thread diagnostic used the build before palette caching and typed axes. It identifies repeated root searches and scalar empty-voxel steps as the target, but its percentages are not an exact bound on current twelve-thread wall time. The remaining frame still performs region lookups, grid-plane event searches, shading, image construction, and native presentation. Separate phase diagnostics measure 112 ms rendering, 26 ms presenting, and 1 ms disposing on twelve CPU threads; the GPU diagnostic measures 787, 123, and 3 ms respectively. [profile.txt](dda-region-data/profile.txt) records those diagnostics, outside the reported benchmark runs.

## Reproduce

Run from the repository directory:

```sh
	make build/dda-compare build/dda-benchmark
	./build/dda-compare --gpu off --threads 1 -- --verify-steps
	./build/dda-compare --gpu off --threads 1 -- --cut --verify-steps
	./build/dda-compare --gpu off --threads 1 -- --cube --view inside --verify-steps
	./build/dda-benchmark --gpu off --threads 12 -- --steps --frames 4 --repeats 5 --label cpu-12-f6 --output build/dda-region-cpu.tsv
	./build/dda-benchmark --gpu on --threads 1 -- --steps --frames 2 --repeats 5 --tile-depth 6 --fork-depth 6 --label gpu-f6 --output build/dda-region-gpu.tsv
	bend PROOF.bend
	bend PROOF.bend --verdict
```

Use `--renderer dda-step` to render the unit reference and `--renderer dda` for region traversal. Both use the same daylight without shadows.
