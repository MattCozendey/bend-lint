# Visual Bend experiments

All twelve demos implement their computation in Bend. The official Bend examples
and guide informed the runtime setup; no JavaScript physics or Life rules are used.
The native demos produce pixels or recorded simulation states. The Rubik demo
runs Bend's JavaScript output live in the browser and displays vector geometry.
The times-table demo computes its geometry in a worker using Bend's JavaScript output.

## First run

Git, Node.js 24+, and Clang are needed. The scripts download the pinned Bend
compiler on first use if necessary. For CUDA, Linux/NVIDIA, Clang 19+, a working
NVIDIA driver and NVRTC are required:

```sh
npm run setup:gpu  # Only needed if CUDA NVRTC is not already available
npm run raytracer -- --gpu
npm run life -- --gpu
npm run cubes -- --gpu --digits 3
npm run playground
```

Visit http://localhost:3000. The viewer can submit new Bend jobs, download the
RGB output as PPM, and play/pause/step/scrub Life's recorded generations. One compute
job runs at a time. Changing the compute device or settings applies on the next
Render/Generate action. `PORT=3001 npm run playground` changes the server port.
The viewer loads each demo only when opened and refreshes only the result of
the current job. Replay downloads are compressed; revisiting a tab reuses its
loaded replay and preserves your settings. Long jobs show elapsed time and
can be stopped with Cancel computation before trying other settings.

The cubes tab shows flat 2D blocks and has play/pause, step, reset, collision scrubbing and playback
speed (0.01× through 2×). The timeline is simulation time in seconds. Link
directly to it with `#cubes` after the viewer URL.

The command-line programs work without the viewer. CUDA runs explicitly require
the GPU and reserve 1 GiB for Bend's runtime. CPU runs use one thread by default.
Artifacts are saved under `output/`; each run replaces that demo's last output.

## Ray tracer

```sh
npm run raytracer -- --gpu --width 1024 --height 640 --bounces 4
npm run raytracer -- --threads 8 --width 512 --height 320
```

The original `mirrors` scene defaults to 512 × 320, three reflection levels,
and four samples per pixel.
`--bounces 0` shows the sky only. The scene contains four colored/reflective
spheres and a checkerboard floor, with analytic sphere/plane intersections,
directional lighting, hard shadows, recursive reflections and gamma encoding.
A ray stops as soon as it misses the scene. Reflection depth is an upper bound;
raising it does not force escaped rays through unnecessary reflection work.

`raytracer/ray.bend` builds a balanced binary tree of pixel tasks. Padded leaves
outside the image return black. The native program returns packed RGB values;
the Node launcher unpacks those colors into `output/raytracer.ppm`, using the
plain-text P3 format from
[Ray Tracing in One Weekend](https://raytracing.github.io/books/RayTracingInOneWeekend.html#outputanimage/theppmimageformat):

```text
P3
width height
255
red green blue
...
```

Each channel is an integer from 0 to 255. Pixels are ordered left to right,
then top to bottom; padded leaves are omitted. Bend already applies gamma
encoding. The browser parses the RGB triplets, adds an opaque alpha channel,
and draws them using `ImageData` and `putImageData`. It does no ray tracing or
additional gamma correction. The server gzip-compresses PPM transfers, but the
saved/downloaded file remains plain text. No PNG encoder is used.

`output/raytracer.json` stores settings and timings only.

### Book-inspired scenes

```sh
npm run raytracer -- --gpu --scene materials --samples 16 --bounces 12
npm run raytracer -- --gpu --scene weekend --width 256 --height 160 --samples 4
npm run raytracer -- --threads 8 --scene weekend --samples 32 --seed 42
```

The scene selector keeps the original renderer and adds two Monte Carlo path
tracing scenes implemented in `raytracer/grid-path.bend`, with shared material
and sampling helpers in `raytracer/path.bend`:

- `materials`: three large spheres demonstrating Lambertian matte, polished
  metal, and glass on a neutral ground sphere.
- `weekend`: a seeded field inspired by the book's
  [final render](https://raytracing.github.io/books/RayTracingInOneWeekend.html#wherenext?/afinalrender),
  with hundreds of small matte, rough-metal, and glass spheres plus the three
  large spheres. Seed 42 produces 471 small spheres; clearances keep them out
  of the large spheres. This is a new deterministic arrangement, not an exact
  reproduction of the book's random image.

Bend computes random camera rays, cosine-weighted diffuse scattering, rough
metal reflection, Snell refraction, Schlick reflectance, total internal
reflection, sky illumination, and gamma encoding after averaging samples.
The camera uses a thin lens for depth of field. Rays traverse a uniform grid
through the layer of small spheres, checking neighboring cells because spheres
can overlap cell edges. Cell coordinates and the seed reconstruct the same
geometry without carrying a shared scene tree through every ray. Candidate
distance and object index fit in one immediate Nat; only the nearest hit needs
a full material/normal record. CPU and CUDA use the same Bend source; pixel
subtrees are independent parallel tasks. The original binary hierarchy remains
as a reference implementation for intersection tests.

New scenes default to 16 samples per pixel, 12 bounces, and seed 42. More
samples reduce noise; more bounces extend possible light paths. Zero bounces
returns black in the path tracer. Changing settings reuses the compiled binary.
All scenes produce the same P3 RGB format, and the browser only displays it.

Replacing shared-tree traversal with grid lookup, packing candidate hits, and
accumulating attenuation in a tail-recursive loop reduced this local RTX 3050
CUDA render without changing settings: `weekend`, 1024 × 640, 32 samples,
64 maximum bounces, seed 42.

| Timing | Before | After |
| --- | ---: | ---: |
| Compute | 62,667 ms | 7,295 ms |
| Whole process | 63,757 ms | 8,197 ms |

All 655,360 RGB pixels matched exactly. These are individual measurements;
compilation is excluded from both timings. The workload still traces 20,971,520
primary rays and their scattered paths. More samples require more work, and
maximum bounces is an upper bound, not a forced path length.

Tests compare hierarchy intersections with exhaustive sphere searches, compare
grid lookup with the reference hierarchy across seeded scenes and boundary rays,
check material scattering and glass refraction, verify seeds, and round-trip Bend
colors through PPM into canvas RGBA without altering channel values.

## Conway's Game of Life

```sh
npm run life -- --gpu --size 256 --steps 240 --pattern random --seed 123
npm run life -- --size 64 --steps 120 --pattern glider
npm run life -- --size 64 --steps 20 --pattern blinker
```

Defaults: 128 × 128, 120 generations, random soup, seed 42. `--steps 0` records
only the initial state. Seeds make random soup reproducible; glider and blinker
are deterministic and ignore the seed.

The grid wraps around both axes (a torus). Size must be a power of two and at
least 32 because each row is packed into 32-cell U32 words. A bit-plane neighbor
counter evaluates Conway's B3/S23 rule across all 32 cells at once. A persistent
tree lets tasks read the same old generation while building the next generation
in parallel. The replay engine in `life/sparse.bend` represents empty subtrees
compactly and tracks live-word bounds to skip regions that cannot change.
The same B3/S23 rules apply to all patterns; there is no glider shortcut.
Generations depend on one another and run sequentially, in batches of up to
32 per GPU call. All intermediate generations are retained.

`output/life.json` includes generation zero plus every computed generation.
With `encoding: "sparse-words"`, each frame contains flat word-index/value pairs;
omitted words are zero. The viewer also accepts older dense-word replays.
Replay speed only controls playback; it does not alter the simulation.
Sparse patterns now need much less storage and computation. Dense random
patterns still require updating most of the grid.

## Pi cubes

```sh
npm run cubes -- --gpu --digits 3
npm run cubes -- --digits 10
```

The counter reuses `accelerated.bend`. `cubes/replay.bend` evaluates selected
collision transformations independently on CPU/GPU, then recovers contact
positions from the conserved quantities `|x*w-y*v| = 1` and
`t*t*x*v+y*w = time-3`, where `t=1/sqrt(heavy mass)`.

This uses the requested mass ratio; it does not animate a smaller substitute
experiment. Up to 1,024 block/wall pairs are recorded. Below that, every impact
is present; above it, spaced pairs include the first and last collisions. The
viewer uses physical time, with constant velocity between impacts and two
seconds of outgoing motion after the final impact. For small runs, every
collision event determines the trajectory. For large runs, Bend independently
finds the last collision at each of 1,024 uniformly spaced timestamps using
extended-precision event-time comparisons, then evaluates the free-flight
position at that time. The viewer interpolates those time samples, so very
fast individual bounces may be unresolved, but omitted impacts no longer
become long pauses or jumps. Slow motion changes the playback clock only.
Step advances to the next collision in small runs or next time sample in
large runs. These sampling counts limit display data, not the collision count.

`output/cubes.json` stores the total count, pi estimate, impact snapshots, and
physical-time motion samples for large runs.
Counts remain exact machine integers; positions/velocities are exported as
F32 for display, after two-float calculations. There is no new digit cutoff.
The counter's finite precision and 48-bit Nat overflow limitations still apply,
and accuracy above 12 digits remains unverified.

Snapshot tests compare with the original event-by-event solver, an independent
double-precision simulation, energy invariants and large-count replay endpoints.
Physical-time queries are also checked against an independent event solver
before, during and after the collision burst; browser-clock tests cover contact
timing, velocity between impacts and continued motion after the final impact.

## Rubik's cube and sticker graph

Open `#rubik` in the playground. Inspired by
[the linked visualization](https://x.com/TheMathFlow/status/2101154346583154801),
the cube and graph share the same 54-sticker state. Each graph node is a sticker
position, grouped by face; edges show face-turn permutations. This is not the
graph of all possible cube states.

`rubik/cube.bend` computes integer-coordinate rotations, permutations, legal
scrambles, inverse moves, and solved-state detection. The server uses the
official Bend compiler to build `build/rubik-engine.js` on startup, reusing it
until the source changes. `npm run build:rubik` can also build it explicitly.
Moves run on the browser CPU, without CUDA, server calls, or compilation per turn.
`ui/src/lib/rubik-engine.ts` draws and interpolates SVG geometry; it does not implement the
cube's permutation rules.

Use the face buttons or U/R/F/D/L/B keys (Shift for inverse), or click graph
face labels. Drag the cube to orbit. Scramble adds legal random moves; Undo
move and Undo all reverse the recorded history. There is no arbitrary-state
solver. Pause freezes animation, and Reset cancels queued turns and returns to
the solved state. Switching tabs pauses any ongoing sequence.

Tests check face orientations, bijective permutations, fixed centers, cubie
integrity, inverse moves, four-turn cycles, opposite-face commutation, and
scramble reversal.

## Monte Carlo π and Buffon's needle

Open `#montecarlo` or `#buffon`, or run:

```sh
npm run probability -- --gpu --method montecarlo --samples 10000000 --seed 42
npm run probability -- --threads 8 --method buffon --samples 10000000 --seed 42
```

`probability/math.bend` generates independently indexed, seeded pseudorandom
samples. Monte Carlo uses a square `[-1,1]²` and counts `x²+y² ≤ 1`; the estimate
is `4 × inside / total`. Buffon uses needle length equal to the spacing between
parallel seams; its estimate is `2 × drops / crossings`, the equal-length case
of [Buffon's needle formula](https://mathworld.wolfram.com/BuffonsNeedleProblem.html).
Uniform needle directions come from rejection sampling a disk and normalizing,
so neither estimator needs a π constant. Exhausting the orientation sampler's
retry budget fails the run explicitly rather than substituting a biased angle.

`simulation.bend` forks independent counting chunks, uses short serial inner
loops, and returns 256 cumulative count checkpoints. Every requested sample
contributes to the exact U32 counts. Each checkpoint retains up to eight points or two needles, with actual
sample coordinates and hit flags, so replay size is bounded independently of
the sample count. The display explicitly labels this subset. Bend also computes
the estimates; JavaScript draws the output and a reference π line. These are
statistical estimates, not guaranteed decimal digits. Counts are exact integers;
the displayed ratios use F32.

Both methods share one cached native binary per backend. Changing sample count,
method, or seed changes environment inputs, not generated source. Results are
saved separately as `output/montecarlo.json` and `output/buffon.json`.

Single local runs on the RTX 3050, 10 million samples, seed 42:

| Method | CPU 8 threads compute | CUDA compute | CUDA process | JSON size |
| --- | ---: | ---: | ---: | ---: |
| Monte Carlo | 15 ms | 3 ms | 1,686 ms | 74 KB |
| Buffon | 41 ms | 9 ms | 188 ms | 38 KB |

Every CPU/GPU checkpoint count matched. Process time includes CUDA startup and
output; a fast kernel does not remove startup variability. Repeated runs and
setting changes were checked to reuse the same binary. One million samples in
the live UI loaded in about 290 ms in a warm run, including the request and JSON.

## Circle times tables

Open `#times-table`. `times-table/circle.bend` maps each evenly spaced point `i`
to `(multiplier × i) mod n` and returns the chord endpoints. Fractional
multipliers move continuously; ×2 produces the cardioid envelope. At ×0 every
chord ends at point 0; at ×1 every point connects to itself. The outline remains
visible at every multiplier. This demo visualizes modular multiplication and
does not calculate π.

The 0–200 animation has play/pause, reset, single-step, scrubbing, point density,
speed, and multiplier presets. `build-times-table.mjs` caches the 3.2 KB Bend
JavaScript module. A browser worker computes each requested frame and transfers
only packed coordinates to canvas. Only one frame request is in flight; newer
settings replace pending work instead of building an animation backlog. No
native build, server calculation, or output-file download occurs per frame.

Tests cover geometric predicates, uniform directions, seed repeatability,
parallel/serial counting agreement, replay coverage, invalid output, and
times-table endpoints against independent modular arithmetic.

## Tests and performance

```sh
npm test
npm run bench:demos
npm run bench:demos -- --demo raytracer --width 1024 --height 640
npm run bench:demos -- --demo life --size 256 --steps 240
```

The benchmark checks result agreement between one CPU thread, up to eight CPU
threads, and CUDA. Life must match exactly; original mirror-scene colors may
differ by at most 2/255 between CPU and GPU floating-point libraries. For the
stochastic scenes, the check uses RGB RMS error of at most 2/255 and reports
the largest channel difference, since grazing intersections can change an
individual path. In the original default runs here,
both outputs matched exactly. Benchmarks save `output/benchmarks.json`.

Initial single-run measurements on this machine's RTX 3050:

| Workload | CPU, 1 thread | CPU, 8 threads | CUDA |
| --- | ---: | ---: | ---: |
| Ray tracer, 512 × 320, depth 3 | 483 ms | 103 ms | 115 ms |
| Life, 128 × 128, 120 generations | 151 ms | 135 ms | 170 ms |

These are compute timings measured around Bend's work, with millisecond
resolution. Whole-process time is reported separately and includes startup,
CUDA context initialization and output. Native compilation is excluded. These
are single runs, not statistical performance claims; GPU startup and scheduling
can outweigh savings on small workloads.

Life's benchmark computes just the final state in one GPU call. Replay
generation batches up to 32 generations per GPU call and retains every state;
it should not be compared directly to that final-state-only timing.

After fixing eager reflection evaluation and sparse Life replay work, these
whole-process GPU measurements used the same settings and data as before:

| Workload | Before | After | Result comparison |
| --- | ---: | ---: | --- |
| Ray tracer, 1024 × 640, depth 128 | 18,324 ms | 1,422 ms | Identical PNG bytes (before the PPM change) |
| Life glider, 512 × 512, 1,000 generations | 62,074 ms | 1,752 ms | All 1,001 grids identical |

The glider replay shrank from 16.4 MB to 37 KB without dropping generations.
These are individual local measurements, not guarantees for every pattern.

The tests compare Life against an independent scalar implementation, including
word-boundary neighbors, torus wrapping, a stable block, a blinker and a glider.
Ray tests cover forward/missing/inside-sphere intersections, reflection, and
finite, varied image output. These are numerical tests, not formal proofs of
the rendering or Life implementations.

## Fourier, epicycles, Shakespeare, sorting, and polar curves

These five tabs adapt [krymancer/p5-projects](https://github.com/krymancer/p5-projects).
All mathematical/algorithmic kernels are Bend. The server builds and caches four
small JavaScript modules with `npm run build:labs`; each active tab uses a browser
worker. These are browser CPU demos. Their controls and animation do not invoke
the server, build native binaries, or compile shaders. Switching away terminates
the worker. The `Bend prepare` timing includes worker-side result packaging but
excludes fetching its module. Source changes rebuild the affected module on
server startup; settings changes reuse it.

- **Fourier** (`#fourier`): odd harmonics with amplitudes `4/(πn)` build a square
  wave. Adjust terms, playback speed, or phase. Bend computes coefficients,
  rotating vectors, and the reconstruction. The overshoot near discontinuities
  remains visible; it is not a numerical error to smooth away.
- **Epicycles** (`#epicycles`): complex DFT of the saved p5 drawing, ordered by
  coefficient amplitude, with signed frequencies. `demos/fourier/drawing.csv`
  comes from the original `epicycle/data.csv`; the original π rotation is retained.
  Draw your own closed outline with a mouse or touch. The UI normalizes input
  coordinates and resamples drawn outlines to 256 evenly spaced points. Bend
  computes the transform and curve. Changing term count reuses the transform;
  the full coefficient set reconstructs the original samples within F32 error.
- **Shakespeare** (`#shakespeare`): fitness-weighted selection, crossover that
  preserves correct letters, mutation of unmatched letters, and one elite survivor.
  Target phrase, population, mutation probability, and seed apply on Restart.
  Run/pause or advance one generation. An independent-random-typing mode starts
  every population afresh; best-so-far is display history, not selection. The
  original p5 program is a guided genetic search, not independent monkey typing.
  Unicode characters in the target are included in the sampling alphabet. A
  generation has a separate seed stream from its offspring, avoiding correlated
  reuse of mutation choices across generations. Zero mutation may stall a search.
- **Sorting** (`#sorting`): quicksort (Lomuto, last pivot), top-down merge sort,
  and bubble sort. Compare random, reversed, sorted, and few-distinct inputs with
  the same seed. Bend produces a compact operation tree, flattened into comparison,
  swap, write, and merge-buffer events. No full-array frame is saved for every
  comparison. The UI applies the recorded operations for play/pause, single-step,
  reset, and scrubbing. Merge comparisons read the visible saved buffer. Counts
  reflect actual comparisons and array writes; buffer-copy events are shown
  separately. Bubble sort uses shrinking passes without an early-exit optimization;
  both it and last-pivot quicksort have intentionally visible quadratic cases.
- **Polar curves** (`#polar`): the original parametric heart and quadratic spiral,
  plus an adjustable rose, cardioid, and Archimedean spiral. The original code's
  spiral uses `r ∝ θ²`, despite its Archimedean label. Here the separate Archimedean
  option uses `r ∝ θ`. Bend computes 2,049 coordinates per settings change; the
  browser reveals the curve and its radial guide during playback.

Local browser observations at default settings: Fourier preparation about 3 ms,
original-drawing DFT/reconstruction about 15 ms, 128-bar quicksort about 6 ms.
These are single measurements. Larger sorting traces still perform their actual
algorithmic work (512-bar bubble sort took about 270 ms in a Node run), with the
worker keeping that work off the UI thread. The four generated modules together
are about 45 KB before compression. Browsing verified no animation network
requests, all three sorting replays, drawn-input transforms, target convergence,
pausing/scrubbing, and mobile layout.

Tests independently verify complex DFT reconstruction and harmonic amplitudes,
curve equations, all three sorted results and complete event replays, comparison
counts, nonmutation of input trees, genetic fitness and weighted selection,
locked crossover, deterministic seeds, population size, and default-phrase
convergence. These are tests of the implemented algorithms, not formal proofs.
