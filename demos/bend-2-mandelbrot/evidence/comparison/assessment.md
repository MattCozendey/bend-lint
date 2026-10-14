# Performance comparison assessment — 20 September 2026

The viewer has measured local speedups, but there is no evidence that it is the fastest Mandelbrot viewer overall. The production renderer lacks several acceleration techniques present in established deep-zoom implementations. My expectation is that these implementations can outperform it on difficult high-iteration scenes; that is an inference from their algorithms, not a measured ranking.

## What our timings establish

The paired measurements in [the local benchmark summary](../acceleration/summary.json) compare successive versions of our own renderer. At 2200 × 1560 on an Apple M4 Pro, the 320-bit antenna scene improved from 284.8 to 65.9 ms with one worker and unchanged tile size. A separate tile/concurrency sweep measured 34.1–34.5 ms with two workers and 512-pixel tiles. These are warm full-image timings. They establish neither a cold-reference result at arbitrary coordinates nor a competitor comparison.

The scene is centered at `c = i`, whose known short orbit has a dedicated GPU shortcut in `precision.metal`. It avoids the general multiprecision reference recurrence. The iteration limit is 16,384, but it is only a ceiling. A fresh 8 × 8 stratified sample of this exact native-resolution scene found all 64 sampled pixels escaped in 185–198 iterations, median 187. Independent Decimal calculations at 150 and 200 decimal digits agreed. Boundary pixels outside this sample can take much longer. [Script](workload_audit.py), [results](workload-audit.json).

The precision label describes the fixed-point reference calculation. Pixel deltas use float mantissas and, at extreme depths, separate exponents. This is a standard perturbation approach, but a speed comparison must match numerical quality, not only the displayed reference precision. The local README records pre-existing errors at some chaotic generic samples. One sample per backing pixel is used; supersampled competitors must be configured comparably.

## Relevant competitors and source evidence

| Renderer | Verified relevant techniques | Comparison status |
|---|---|---|
| [FractalShark](https://github.com/mattsaccount364/FractalShark/tree/1f243ceae48182b8e13cc5608f10bf907f39ec4a) | CUDA linear approximation, reference reuse/compression, extended-range two-float arithmetic; fused NTT-based multiprecision reference generation at extreme precision | Requires NVIDIA hardware for its GPU path; no matched run on this M4 Pro |
| [Imagina](https://github.com/5E-324/Imagina/blob/master/HInfLAEvaluator.cpp) | Period-guided approximation stages, composed multi-iteration steps, approximation transforms, vectorized evaluation and fallback perturbation | Source inspected; not benchmarked locally |
| [Fraktaler 3](https://mathr.co.uk/web/fraktaler.html) | CPU/OpenCL backends selected through hardware benchmarks; [BLA, rebasing and interior detection](https://mathr.co.uk/web/deep-zoom.html) | Documentation inspected; no matched native local run |

FractalShark's published roughly 10× GPU-reference improvement compares its own RTX 4090 and multithreaded CPU implementations at 16,384 **32-bit limbs** (524,288 bits). It is not a comparison to our 320-bit viewer. Its author also reports CPU reference computation often winning at shallower depths. These statements come from its [current README](https://github.com/mattsaccount364/FractalShark/blob/1f243ceae48182b8e13cc5608f10bf907f39ec4a/README.md).

Our production pixel loop still advances one orbit iteration at a time. Established LA/BLA implementations combine many iterations into one evaluated step where their validity conditions hold. Our rejected prototype is not evidence against the technique. The author's [current deep-zoom description](https://mathr.co.uk/web/deep-zoom.html) explicitly corrects the validity test in older posts; a future implementation should use current theory and independent numerical checks.

I also found a published [Apple M4 Max Metal benchmark](https://performance.jakubjirak.com/) reporting 0.15 ms for a 1400 × 800, 256-iteration workload. Its shallow float32 computation and timing boundaries differ from this deep viewer, so dividing our timing by that number would be misleading. It does not establish a relevant winner.

## What would establish a defensible ranking

Use a shared, published coordinate suite including the antenna, high-period minibrots, difficult boundaries, interiors and repair-heavy regions. Match the image sampling grid, escape convention, iteration ceiling, antialiasing and acceptable numerical error. Record the actual escape-count distribution instead of treating the ceiling as executed work.

Measure cold reference preparation, warm complete-image rendering, time to first useful detail and input-to-detail latency during the same recorded pan/zoom path. Report median and p95 over repeated runs, along with hardware, renderer version and settings. Distinguish reprojected animation from newly computed pixels. FractalShark comparisons would require a supported NVIDIA machine; report hardware differences explicitly rather than claiming an algorithm-only speedup.

The most promising algorithm work is validated multi-iteration skipping, broader reference reuse during movement and avoiding full-budget work for detectable interiors. Additional worker concurrency alone cannot replace those reductions in computation. None of those changes were implemented as part of this research pass.
