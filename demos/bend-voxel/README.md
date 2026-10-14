# Bend voxel rewrite

Run the editable Light Atelier sculpture court in a native window. The default scene contains Suzanne, Oculus, Twist, a backdrop, and a slatted canopy. Use `--cube` to open the original 8³ body.

![Light Atelier sculpture court](docs/atelier.png)

## Run the slice

Use Bend 2.0.34 or newer. Native GPU builds require the compiler and SDK for the available Bend execution lane. On Linux, install `libx11-dev` for the window.

```sh
	make
	make run
```

`make run` uses CPU rendering with Bend's default worker count, the logical CPU count. The native Atelier workload ran faster on CPU than GPU on the development machine. Override the execution lane and worker count through `RUN_ARGS`:

```sh
	make run RUN_ARGS='--gpu on'
	make run RUN_ARGS='--gpu off --threads 4'
```

Use these controls:

- Hold **W/S** to fly along the view direction, and **A/D** to strafe.
- Hold **Q/E** to descend or ascend along the world's vertical axis.
- Hold the right mouse button and move the mouse to look around.
- Press **Space** to carve the Oculus edge in the opening view, or the front corner with `--cube`.
- Move the mouse over the body to preview a yellow sphere and its selected cells. Click to carve at the continuous surface point; while holding RMB, the brush targets the screen centre.
- Press **R** to restore the scene while keeping your camera position and view.
- Press **Escape**, or close the window, to exit.

The perspective camera can fly through the scene. Movement uses elapsed time and normalizes combined directions. Each voxel is 10cm wide. The spherical brush has a 20cm radius and removes occupied cells whose centres are inside or on its boundary. With `--cube`, Space uses the fixed centre (65,65,65)cm; repeating that cut leaves the body unchanged. Hovering over the background clears the preview.

The scene uses green foundation at material ID 1, tan concrete at ID 2, blue frame at ID 3, orange machinery at ID 4, and pale plaster at ID 5. Colors come from the [stable OKLCH material palette](https://github.com/aivv73/bend-voxel/commit/02bbd4a6ab4ca746333473f6ca8b7ace9513ae61). Daylight follows the [reference lighting change](https://github.com/aivv73/bend-voxel/commit/cf188d2afeaf47836ffe023907f81efafc40878c): warm directional sunlight, cool sky ambient light, and soft sun shadows on voxel surfaces and the ground. Shading runs in linear RGB before sRGB encoding. The sun-depth cache survives camera movement and rebuilds after edits. Night mode and the camera work light are omitted. Carving preserves each surviving cell's material, and appearance depends on material, face direction, and sun visibility. Unsupported positive material IDs remain occupied and display diagnostic magenta.

Engine callers can fill or paint the existing body with named materials:

```bend
	import ./material.bend as M
	import ./voxel.bend as V

	body = V.Body.filled(3n, M.Material.id(M.Concrete{}))
	body = V.Body.write(body, V.Cell{2, 3, 4}, M.Material.id(M.Machinery{}))
```

To run on the CPU, disable GPU dispatch through Bend's runtime option:

```sh
	./build/bend-voxel-rewrite --gpu off
```

To require the available GPU lane, force GPU execution:

```sh
	./build/bend-voxel-rewrite --gpu on
```

Keep `build/bend-voxel-rewrite.gpu` beside the executable. On the development Linux machine, the CUDA SDK is at `/opt/cuda`. The Makefile detects that path at the build boundary. To use a different SDK path, set `CUDA_HOME`:

```sh
	make CUDA_HOME=/path/to/cuda
```

## Verify the slice

Run the formal laws, geometry reference cases, and complete CPU/GPU image comparisons:

```sh
	make test
```

Validation uses formal laws, actual engine geometry, real renderer exports, and native UI evidence. First-party validation includes no traditional test suites. The geometry reference check is written in Bend and compares complete cell and face sets, including materials. Run it separately with `make geometry`. `make lighting` compares every sun-depth texel against an occupied-cell ray reference, checks daylight ramps and self-shadow prevention, validates every compressed illumination sample, verifies camera cache reuse, and compares opposite-view CPU/GPU exports. `make materials` checks the palette's runtime properties and exports all four materials on CPU and GPU under `build/materials`. `make images` forces both `--gpu off` and `--gpu on` across four tile and fork configurations. Native UI checks cover flight, brush targeting, capture, and lifecycle behavior.

To compare images on a machine without a GPU, run the CPU cases:

```sh
	make build/image-checker
	./build/image-checker --gpu off -- --cpu-only
```

The checker reserves a fresh directory under `build/image-check` for each renderer dispatch and reads its new `render.ppm`. A zero-exit renderer that writes no file fails. Every complete 512x512 export must match the fixed full-scene or cut-scene RGB SHA-256 golden. Exact CPU variant and CPU/GPU comparisons run separately from the golden check. The sample pixels and 9,779-pixel destruction delta remain required. Read [the golden update procedure](docs/verification.md#update-the-image-goldens) before changing expected hashes.

The checker resolves the repository from its executable path, so absolute or relative invocations also work from another directory. If you invoke a bare executable name through `PATH`, supply `--root /path/to/repository`. Use `--binary path/to/renderer` to select another renderer. Relative renderer paths resolve under that root.

The parser accepts the renderer's unsigned ASCII P3 format with literal `P3 512 512 255` header tokens and exactly 786,432 channels in 0..255. ASCII whitespace and leading zeros in channels are accepted. PPM comments, signed values, digit underscores, and Unicode digits are rejected.

The native window check uses `Window.export_ref` and `Window.capture` from [the aivv73 Bend fork](https://github.com/aivv73/bend). Input and lifecycle checks use [bend-ui-test](https://github.com/aivv73/bend-ui-test), pinned as the `deps/bend-ui-test` submodule. The tested compiler revision is `de38700481244494b56a2f947df6fba25f798887`. With the fork checked out beside this project, initialize the pinned dependency and run:

```sh
	git submodule update --init --recursive
	make ui UI_BEND='bun ../bend/bend2/main.ts'
	./build/ui-check --gpu off -- --output .audit/screenshots/cpu
	./build/ui-check --gpu on -- --close-method window --output .audit/screenshots/window-close
```

The GPU target saves native PPM screenshots in `.audit/screenshots/ui`. The CPU command saves them in `.audit/screenshots/cpu`.

The native check uses the slice's `Interactive.step`, which handles pointer capture and delegates the real view and event reducer to `App.step`. `Window.capture` reads the owned window's client pixels after earlier output completes. Keep the client fully on-screen and unobscured during the test. `scripts/ui_capture.bend` converts its RGB array to an `Image`; Bend checks the pixels and exports screenshots. The checker passes `WindowRef` directly to `UITest.key`, `UITest.click`, `UITest.request_close`, and `UITest.alive`. The library owns native event delivery and expiry checks. A close request goes through the app reducer, which closes the owned window. The check requires Linux/X11 and `libX11`. Unsupported backends report an error.

To verify actual held flight keys and captured mouse motion, put `xdotool` on `PATH` and run `make flight-ui UI_BEND='bun ../bend/bend2/main.ts'`. This separate Bend check uses the same `Interactive.step` and saves native captures in `.audit/screenshots/flight-ui`. `make brush-ui` with the same compiler checks actual mouse hover, background clearing, complete removal sets for free and captured clicks, and same-hover resets. It saves captures in `.audit/screenshots/brush-ui`. Run native tests sequentially.

The library's native effects use Bend runtime internals. To rebuild with a different compiler, run `make -B ui UI_BEND='bun ../bend/bend2/main.ts'`. After checking out a different project revision, run `git submodule update --init --recursive` to select its pinned library version. Read [the verification notes](docs/verification.md) for the tested revisions and the scope of formal proofs and runtime checks.

## Export an image

Write the geometry view to a deterministic PPM file. These exports omit the interactive hover preview:

```sh
	./build/bend-voxel-rewrite --gpu on --dump build/full.ppm
	./build/bend-voxel-rewrite --gpu on --cut --dump build/destroyed.ppm
```

## Measure native frames

Measure displayed frames with cached scenes and scripted destruction and reset:

```sh
	make benchmark
```

The Bend command records sequential CPU and GPU measurements in `build/benchmark.json`. Each child opens a native window and excludes eight warm-up frames. CPU thread counts and GPU work decomposition are measured separately. The default CPU counts are one, half the logical system processors, and all logical system processors, with duplicate defaults removed. Override the workload and CPU counts through the built benchmark:

```sh
	./build/benchmark --gpu off -- --frames 120 --repeats 3 --cpu-threads 1 4 8
```

Samples measure elapsed integer milliseconds divided by measured frames, in ms/frame, with 53-bit binary precision. The median selects the middle sample for an odd count and averages the two middle samples for an even count. Progress rounds the stored sample to exactly three fractional digits with ties to even. Report numbers retain the full stored precision. Repeated thread entries run repeated measurements and share one report row. Each alternate repeat reverses the complete configuration list.

Numeric arguments accept unsigned ASCII decimal integers, including leading zeros. Frames must be in 24..4294967295, repeats in 2..4294967295, and thread counts in 1..4294967295. Options accept `--flag=value`; later occurrences replace earlier values. `--cpu-threads` accepts one or more counts. Use `--output path/to/report.json` to select a report path relative to your current directory.

The benchmark resolves its repository from the canonical executable or script path, including a bare executable found through `PATH`. `--root /path/to/repository` selects another root. `--binary path/to/renderer` accepts an absolute path or a path under that root. Child processes run in the repository directory. The host helpers require POSIX `sh`, `getconf`, and GNU `realpath`, `dirname`, `date`, and `mkdir`; the current GNU/Linux host is verified. Read [the measurement contract and limits](docs/verification.md#native-measurement).

To choose a work decomposition, set both depths:

```sh
	./build/bend-voxel-rewrite --gpu on --tile-depth 6 --fork-depth 6 --bench 120
```

The default tile and fork depths are both six. Native daylight measurements selected that configuration for the available CPU and GPU lanes.

`--tile-depth` chooses the tile tree depth within the 512-pixel image. `--fork-depth` chooses how many tile tree levels may fork. Both default to six and accept values from zero to nine. Leaves run sequentially. These settings change scheduling and candidate lists while preserving the pixels.

For native frame attribution and steady cached FPS, build the phase driver:

```sh
	make build/frame-profile
	./build/frame-profile --gpu off -- --frames 12
	./build/frame-profile --gpu off -- --bench 24
```

`--frames` reports initialization stages, cached rendering, hover preview, flight, cut, and reset. It separates model updates, rendering, presentation, and image disposal. Initialization is reconstructed for attribution, so use its stage times as diagnostics. `--bench` measures cached frames in a native window after eight warm-up frames, with initialization excluded. It keeps the camera fixed and performs no edits. The production renderer's `--bench` includes cut and reset. Both consume and dispose of every rendered image.

Read [the design notes](docs/design.md) for the data flow, boundaries, and examples considered.

## Compare a minimal DDA renderer

Build the independent voxel-traversal renderer and compare every image ray with the existing renderer:

```sh
	make dda
	./build/dda-compare --gpu off --threads 1 -- --verify
	./build/dda-compare --gpu off --threads 1 -- --verify-steps
	./build/dda-compare --gpu off -- --renderer dda --dump build/dda.ppm
	make build/dda-benchmark
	./build/dda-benchmark --gpu off --threads 12 -- --frames 12 --repeats 5 --label cpu-12 --output build/dda-comparison.tsv
```

The comparison includes the production renderer and a version of the existing face renderer with shadows omitted to match minimal DDA shading. Read [the DDA comparison](docs/dda-comparison.md) for scope, validation, images, and measurements. The default DDA crosses compressed uniform regions. [DDA region traversal](docs/dda-optimization.md) compares the upstream world representations and explains the optimization. [The region DDA profile](docs/dda-profile.md) records cumulative CPU costs, actual work counters, and one rejected search optimization. [Corrected event counting](docs/dda-estimate.md) replaces that baseline's binary search with a bounded estimate and exact plane correction, with repeated CPU12 gains and separate GPU measurements. Add `--steps` to the benchmark to include the unit-step reference.
