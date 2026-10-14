# Slice verification

`make test` reruns both formal gates, the real geometry reference, and actual renderer CPU/GPU comparisons. First-party validation includes no traditional test suites. `make ui UI_BEND='bun ../bend/bend2/main.ts'` verifies real native input and screenshots with the fork's owned-window APIs. `make benchmark` measures native displayed frames.

## Formal scope

`LAWS.bend` states seventeen local laws. `PROOF.bend` proves the four stable material IDs, known-material ID roundtrip, nonzero known IDs, and agreement between typed and raw-ID palette lookup. It also proves material erasure idempotence, preservation on a miss, removal on a hit, hidden faces, empty cells, and isolated solid faces. Geometry calls the proven erasure and face predicates. Palette laws quantify over symbolic swatches and do not invoke floating-point conversion. Daylight laws additionally prove typed/raw palette agreement, preservation of flat overlay colors for every visibility value, and the binary sun comparison outcomes.

Both `bend PROOF.bend` and `bend PROOF.bend --verdict` pass. These laws do not prove the complete body traversal, surface extraction, projection, native effects, or GPU runtime. Real-runtime validation covers those paths. No property that depends on an unsafe definition is claimed as formally proven.

## Material runtime properties

`make materials` runs `scripts/material_check.bend` on one CPU thread and strict GPU execution. It checks all four authored materials and six face directions. The unquantized bright sRGB channels must match the source palette's reference colors within 0.002. Linear shades must stay in gamut and follow the three brightness levels. Packed colors must repeat exactly and avoid the renderer's fixed edge color.

A 702-color grid includes achromatic colors, out-of-gamut chroma, lightness outside 0..1, and hues around the full circle. Independent inverse D65 matrices check retained clamped lightness and hue, and that fitted chroma does not increase. Invalid negative chroma, infinity, and NaN must be rejected. These are bounded runtime properties, not formal numerical proofs.

The checker sends actual bodies through `Surface.build`, `Projected.of`, and `RenderScene`. It scans all 512 stored cells in translated sparse bodies, checks every emitted face's material and color under two cameras, and compares real picking across a 256-point screen grid plus the centre and an out-of-bounds query. Materials 7 and 4294967295 retain occupied geometry and display magenta. Each known material exports full and cut images; each unsupported material exports its full image. `make materials` compares all ten CPU/GPU PPM files and the complete swatch inventory exactly under `build/materials`.

The OKLCH golden update was reviewed against fresh full and cut images. All sixteen existing tile/fork/lane exports matched byte-for-byte before the digests changed. Independent decoded RGB hashing confirmed both new digests and the 7,722-pixel delta. The complete legacy geometry dump remained byte-identical. The delta falls from 7,994 because replacing height-dependent colors makes some newly exposed faces match the faces they replace.

## Daylight runtime properties

`make lighting` runs the actual surface extraction, sun-depth renderer, and scene reprojection on CPU and strict GPU execution. An independent ray/AABB slab reference reads the actual occupied cells and checks every one of the 16,384 sun texels for full, carved, and empty bodies. It does not reuse surface faces, projection bounds, tile candidates, or ray/face intersection helpers. Depths agree within 0.00003 grid units, including empty texels.

All four materials, six directions, and ten visibility levels retain bounded, monotonically increasing RGB channels. Directions facing away from the sun have constant ambient-only ramps. A 64 × 64 grid over each of the solid body's three sun-facing planes requires full visibility at all 12,288 points, guarding filtered self-shadow artifacts. Every face-field and ground-field sample agrees with the original nine-tap visibility filter at its world-space texel centre, including quadtree compression. Camera reprojection preserves every cached depth bit and illumination field. Opposite-camera exports for all three bodies match exactly between CPU and GPU. These numeric and cache checks are runtime evidence, not formal floating-point or GPU proofs.

The daylight goldens were updated after visual inspection of fresh full and carved images and exact agreement of all sixteen tile/fork/lane exports. Independent hashing of decoded RGB bytes confirmed the recorded digests. Destruction changes 9,779 pixels, including changed sun visibility on surfaces and the ground. The complete geometry dump remains byte-identical to the pre-lighting engine. Night mode and the camera work light are excluded.

The final daylight implementation passed six serialized native runs on an owned Xvfb display: ordinary input and lifecycle on CPU/Escape and GPU/Close, flight on both lanes, and brush targeting on both lanes. All eight brush captures and all ordinary UI captures match exactly between CPU and GPU. Native full and destroyed captures also match the standalone renderer exports. The checks exercise the actual shared renderer and reducer with native input and readback.

After selecting depth six, two more ordinary UI runs verified the new defaults on CPU/Escape and GPU/Close, with exact capture and standalone-export comparisons. A resettable Xvfb run encountered a transient display-open failure during the post-close expiry query. Both final runs passed with `Xvfb -noreset`, keeping the test display available after its last client closes.

## Geometry cases

`scripts/geometry_dump.bend` calls the actual body operations and surface extractor, then emits complete occupied cells and explicit faces. `scripts/reference_check.bend` launches that executable with GPU execution disabled and compares its output against an independent set translation reference. The checker imports only `Base`; it does not reuse engine geometry, indexing, or brush predicates. For each direction, it constructs the translated occupied set and takes the difference from the original set. A one-cell coordinate offset represents negative translations without unsigned wraparound.

`make geometry` compiles and runs both Bend programs. The check compares every occupied coordinate and material, every face direction and material, and the reported and emitted face counts. It also checks known surface counts, that the cut is a proper subset, and that repeating the cut preserves geometry. The parser rejects duplicate cells or cases, malformed records, missing counts, and unterminated cases; emitted face counts expose duplicate faces.

To check a saved candidate dump, run `./build/reference-check --gpu off -- --input path/to/dump.txt`. To select a candidate executable, use `--binary path/to/geometry-dump`. The default executable path is relative to the project root. Candidate runs have a 30-second timeout and a 1 MiB output limit. These geometry checks are runtime assertions, not formal proofs.

The checker passed all twelve cases on native CPU and Bun JavaScript execution, using the same native candidate executable. A tail-recursive line splitter handles the complete dump on both targets. Native execution also rejected twenty negative probes, covering changed materials, missing or duplicate faces, incorrect counts, malformed input, duplicate or missing cases, incomplete output, and a failed candidate process.

The checked legacy integer-brush results are below. These retain the original radius-three geometry fixtures; interactive cuts use the metric brush exercised by native UI checks.

| Case | Occupied cells | Exposed faces |
| --- | ---: | ---: |
| Empty 4³ body | 0 | 0 |
| One material-7 cell | 1 | 6 |
| Two adjacent material-7 cells | 2 | 10 |
| Solid 4³ body | 64 | 96 |
| One interior cell removed | 63 | 102 |
| Repeated interior removal | 63 | 102 |
| Out-of-bounds writes | 1 | 6 |
| Far outside sphere on a solid 4³ body | 64 | 96 |
| Separate opposite-edge cells | 2 | 12 |
| Solid 8³ body | 512 | 384 |
| Front sphere removed | 446 | 396 |
| Repeated front sphere | 446 | 396 |

The far-sphere case guards unsigned distance overflow. Bounds and edge cases guard accidental index wrapping. Full occupancy comparisons require the destruction operation to preserve every cell outside the brush.

## Image and native checks

`scripts/image_check.bend` runs the native renderer with one thread, first for the full scene and then for the destroyed scene. Each scene visits GPU off and strict GPU on at tile and fork depths 4/0, 4/4, 5/5, and 6/6. The default runs sixteen exports. `--cpu-only` runs eight. Every dispatch reserves a new directory under `build/image-check` through a checked `mktemp -d` call. The renderer receives its absent `render.ppm` path. The checker preserves filename spaces and removes only the reservation output's final newline. A missing new PPM fails even when the renderer exits zero and earlier exports remain valid.

`scripts/image_data.bend` retains the first accepted CPU image for each scene as packed RGB lists and streams each later candidate against that CPU reference. Equality compares every channel through byte-equivalent packing, independently of the golden SHA-256 gate. This checks CPU variant agreement and CPU/GPU agreement. The first result reports only golden acceptance. The checker requires full-scene samples `(16,24,32)`, `(57,151,128)`, and `(57,151,128)` at `(0,0)`, `(256,256)`, and `(256,300)`. It counts each changed pixel once and requires exactly 9,779 changes.

The parser accepts unsigned ASCII P3 exports with the literal header tokens `P3`, `512`, `512`, and `255`, followed by exactly 786,432 channels in 0..255. ASCII whitespace and leading channel zeros are accepted. Comments, signs, digit underscores, Unicode digits, truncation, and extra channels are rejected. The reader scans bounded chunks, continues after nonempty short reads, checks progress against the file's reported size, and probes actual EOF. It adds no arbitrary file-size cap. Base's `File.size` rejects files larger than its U32 size range.

`scripts/sha256.bend` hashes every validated export as decoded row-major red, green, and blue bytes. The 786,432-byte hash input excludes the PPM header and whitespace. `Scene.expected_hash` fixes the full digest to `02befa6e6575a5b6d3ea774e7df29e0a1f96d8c8d9fe2fb5149502b6694878db` and the destroyed digest to `fad7c6dca2cad4341c84767ff7b9e6895e8d50241e78a09c7af928d7804f9a33`. Every variant must pass its scene's golden before exact agreement is checked. Agreement among equally wrong outputs cannot satisfy that gate.

The checker derives its root from its executable directory's parent. Absolute or relative executable paths work outside the repository. Bare `PATH` invocation requires `--root repository`. `--binary renderer` accepts absolute paths or paths under that root. Child processes have a 180-second timeout and a 16 MiB combined stdout and stderr limit. Directory setup and reservation use checked direct `mkdir` and `mktemp` calls with 30-second timeouts. File and process failures stop the check before a successful report.

The recorded goldens were checked against native CPU and GPU exports and independently hashed after RGB decoding. The actual renderer matrix exercises SHA-256, image parsing, equality, freshness, and foreign IO. No formal SHA or parser proof is claimed.

### Update the image goldens

Golden updates are explicit source edits. The checker has no automatic update option.

1. Identify why the scene or renderer changed. Resolve unexpected differences before changing either digest.
2. Export fresh full and cut images. Inspect both images visually, including the removed region and exposed surfaces.
3. Confirm complete 512x512 data and exact agreement across CPU variants and CPU/GPU variants. Compute SHA-256 over decoded row-major RGB bytes, independently of the checker's hash implementation.
4. Update `Scene.expected_hash` in `scripts/image_check.bend`. Update the recorded digests here. Change sample values or the destruction delta only when the reviewed scene change explains those differences.
5. Run `make images` and both proof gates. Record the cause and review evidence with the change.

`scripts/ui_check.bend` opens the slice's native window and drives `Interactive.step`, the same capture wrapper used by standalone interaction. The wrapper delegates the real view and reducer to `App.step`. The test exports `X11WindowRef{display, id}` after the first frames. A separate X11 connection sends input to that reference and checks its expiry; the test never enumerates windows or matches titles. The owner is renamed during the test, and repeated exports must preserve its identity.

The fork's `Window.capture` returns the same owned window and `Result<Capture>`. Its Linux/X11 implementation reads the actual client drawable after completing earlier output requests. Keep the client fully on-screen and unobscured; capture excludes its border and the cursor. Unsupported backends fail rather than substituting the renderer's input image. Capture or conversion failures close the returned window before exiting.

`scripts/ui_capture.bend` converts `Capture{width, height, pixels}` to an `Image`. The checker requires 512x512 dimensions and exactly 262144 array entries before reading. Each leaf reads the top-left row-major index `y * 512 + x`. The affine array owner passes sequentially through all four quadrants and is released after conversion. RGB words retain all 24 bits. Native screenshot comparisons validate conversion of the actual capture data.

The public API of `deps/bend-ui-test/uitest.bend` is the boundary for key and mouse events, close requests, and checking that the exported window has expired. The checker passes `WindowRef` directly to the library. Its native backend sends real X11 events through a separate connection. Successful send means server acceptance. The existing frame waits and `App.step` check app processing. Bend checks every pixel and writes PPM evidence. The project has no local `ui_native` adapter. No Python, Pillow, ImageMagick, or python-xlib is used by the native check. The library's JavaScript backend reports unsupported native X11 operations.

The test captures the client image before destruction, after Space, after repeating Space, after reset, and after primary-click carving. Space must change exactly 9,779 pixels; repeating it must preserve the image. Background clicks must preserve the image. Both resets must restore every pixel. Primary click must carve a different region from Space. Escape and the window close event must stop the actual app reducer, and the exported window must then be gone. A completion channel prevents an unexpected early Close from being counted as success.

The assertions are runtime checks. Native identity, capture, event delivery, and lifetime depend on foreign IO and are not claimed as formally proven. Compile and run the UI check; `--verdict` remains the gate for `PROOF.bend`'s local laws.

`make flight-ui UI_BEND='bun ../bend/bend2/main.ts'` additionally requires `xdotool` on `PATH`. The Bend driver directs held key and right-button edges to the exported window. Actual pointer motion exercises native capture and relative `Look`. Each WASDQE hold must move along its expected direction; its release must stop both pose and native pixels. The test checks a literal 40,20 mouse displacement, ignored motion after release, primary carving after flight, an exact body reset at the preserved pose, and Escape. A completion channel rejects a premature Close with status 1. Native readback writes the evidence into its output directory. Run native window tests sequentially.

The metric brush update preserves the perspective full-scene golden and changes the cut golden for the 30-cell demo removal. Fresh full, cut, and preview frames were visually reviewed before updating literals. CPU and GPU exports matched byte-for-byte, independent decoded RGB hashing confirmed the digests, and Bend counted 7,994 changed pixels. No camera, floating-point, or input property is claimed as formally proven. The native Event API has no focus-loss event or key-state query, so automatic held-key cleanup after focus loss remains unsupported.

`make brush-ui UI_BEND='bun ../bend/bend2/main.ts'` requires `xdotool` and exercises native absolute hover, selected yellow pixels, background clearing, and centre targeting while RMB is held. Each free and captured click must produce the complete material set predicted by its presented sphere. The target must change after carving, and resets compare captures at the same hover position. Captures must match `RenderScene.preview`; Close must stop the real reducer. A guarded completion channel rejects early Close. Run it sequentially with the other native checks.

The metric-brush native suite was run on an owned Xvfb display with real X11 windows, input events, and `Window.capture`. This verifies the X11 boundary on CPU and GPU. The development niri/Wayland session accepted X11 focus and fake pointer warps without delivering physical hover to the test surface; its pointer remained on another surface. That compositor injection path is not covered by these successful runs. The test raises its owned window and forces a distinct starting pointer position, but still requires an unobscured client and working X11 pointer delivery.

Fresh CPU and strict GPU brush runs passed, and all eight native brush captures matched byte-for-byte. Ordinary UI runs covered both CPU/GPU lanes and both Escape/Close methods. CPU and strict GPU flight checks passed real held WASDQE, captured 40,20 relative motion, released motion, carving, and exact reset at the preserved camera and hover position. Raw image checks separately passed all sixteen tile/fork/lane exports.

The harness owns its window in the test process and imports the slice's shared view and reducer. It does not launch the standalone application binary. Before the metric brush change, the development run passed CPU and GPU execution with both Escape and Close, and all seven captured states matched across the four runs. The full and destroyed captures matched the then-current renderer exports. An injected premature Close exited with status 1 without reporting success. The JavaScript adapter's unsupported path exited with status 95.

The `Window.capture` migration was validated with fork commit `de38700481244494b56a2f947df6fba25f798887`, which contains the capture API merged in `ecde8700807c5b7a5e5da49eaede0c5749d6e435`. Four serialized native runs covered CPU and strict GPU execution with both Escape and the window close request. All seven PPM files from each run matched the pre-migration C-capture baseline byte-for-byte, for 28 comparisons. Both proof gates also passed with the installed compiler and the fork. These checks preserve the existing UI contract; they do not formally prove native readback.

The bend-ui-test integration pins library commit `90f8aa78802ea39d895c4c2bf8a9b4628cd3e98c` and was validated with the same fork revision. Four fresh pre-migration runs recorded the local adapter's seven native screenshots per run. Four post-migration runs covered CPU and strict GPU execution with both close methods. All existing assertions passed, and all 28 PPM comparisons were byte-identical. Both project proof gates passed with the installed compiler and the fork. The library's three event-plan laws also passed both proof gates with the fork. Those laws prove the pure event plans, not native delivery or window lifetime. Make dry runs confirmed that changing any of the library's four source files rebuilds the UI checker.

A clean recursive clone fetched the pinned library and built the UI checker. Its CPU window-close scenario passed, and all seven screenshots matched the corresponding pre-migration baseline.

`make ui` checks Escape. To check the window close event, run the built test:

```sh
	./build/ui-check --gpu on -- --close-method window --output .audit/screenshots/window-close
```

The development machine exercised the current Linux GPU lane. Metal and future WebGPU lanes have not been tested in this slice. Core code uses Bend types and parallel calls rather than backend-specific operations.

## Native measurement

`--bench N` opens a native window and shows N measured frames after eight warm-up frames. The scripted workload destroys the front sphere and resets the body every 24 frames. The scene is cached between edits. Rendering, edit rebuilds, `Window.frame`, and the same image disposal used by `App.run` occur inside the measured interval.

`IO.now` reports milliseconds in Bend 2.0.34. The executable prints `frames=N elapsed_ms=M`. `scripts/benchmark.bend` runs each configuration sequentially for three repeats by default and reverses the entire launch list on alternate repeats. The development CPU configurations use one, six, and twelve threads. Defaults use `getconf _NPROCESSORS_ONLN` for the logical system CPU count, falling back to one if the query fails. Explicit `--cpu-threads` counts retain their order and duplicates. Duplicate configurations share a report row but still launch every requested measurement. Rows keep their first-occurrence order, and each sample array keeps acquisition order. GPU configurations vary tile and fork depths independently of those CPU measurements.

The numerical contract is elapsed integer milliseconds divided by measured frames, in ms/frame. Each sample has a 53-bit binary significand and rounds to nearest with ties to even. The numeric median sorts stored samples. An odd count selects the middle sample. An even count takes the arithmetic mean of the two middle samples at the same precision. Progress rounds the stored sample to a multiple of 0.001 ms/frame with ties to even and prints exactly three fractional digits. JSON emits a decimal that round-trips the full stored value. It does not truncate samples to progress precision.

An independent mathematical reference uses exact integer ratios and an exact mean. With `u = 2^-53`, the sample relative error is at most `u`, and the median relative error is at most `2u`. A `4u` relative allowance accounts for independent host conversion and comparison. Zero remains exactly zero. For elapsed values below `2^48`, that allowance is less than one eighth of a 1 ms timer tick after division by frames. An even median uses a half-tick quantum, and its allowance is less than one quarter of that quantum. Losing a whole timer tick exceeds that allowance. These bounds come from the selected precision. A previous implementation's final decimal digits and JSON bytes are not a numerical specification.

The scanner selects the first complete stdout substring with unsigned ASCII digits in `frames=digits elapsed_ms=digits`. Exactly one literal space separates the fields. Prefix and suffix text are accepted, including a decimal suffix after the elapsed integer. Incomplete candidates are skipped before range validation. A first complete record with a wrong or overflowing frame count fails even if a later record is valid. Frames must match the request. Elapsed values admit 0..281474976710655, the current native timer range. CLI numbers use unsigned ASCII decimal integers in U32 range, including leading zeros. Frames require at least 24, repeats at least two, and CPU threads at least one. Signs, separators, and Unicode digit spellings are rejected.

The driver has three production modules. `benchmark.bend` owns options, configurations, row histories, the metric scanner, and report policy. `benchmark_number.bend` owns the bounded nonnegative number representation and its arithmetic and formatting. `benchmark_host.bend` owns paths, processes, system CPU count, UTC time, byte hashing, and file IO. It reuses `sha256.bend` unchanged. Counting, merge-sort passes, CPU-list construction, row operations, and report emission use tail recursion without an arbitrary history or CPU-entry cap. Arithmetic and host IO remain outside formal proof scope.

Reports retain the existing schema and include UTC time with six microsecond digits, the executable's SHA-256, and hashes of exactly `main.bend`, `voxel.bend`, `render.bend`, `material.bend`, `lighting.bend`, and `dump.bend`. The hashes cover raw bytes and exclude the GPU companion. The driver creates the report parent directory, then collects time and hashes after all measurements, then opens the output for writing. Any failure before that final open preserves an existing report. A failed write can leave a partial report. Hashes attest the files present at report creation; the driver does not detect changes during earlier measurements.

Root and executable paths are canonicalized before child execution. The child runs through a fixed positional `sh` wrapper with literal arguments and the repository as its working directory. An explicit relative output stays relative to the caller's directory. `mkdir -p --` creates its parent. The current host uses GNU `realpath`, `dirname`, `date`, and `mkdir`, plus POSIX `sh` and `getconf`. The UTC helper validates the returned six-digit microsecond format. These host utilities have been verified on the current GNU/Linux machine.

Base requires positive process limits. The driver uses its maximum U32 values, 4294967295 combined stdout and stderr bytes and 4294967295 milliseconds per child. Process input is empty, and Base waits for the direct child while draining available output. File hashing streams 65536-byte chunks, accepts nonempty short reads, checks progress against the reported file size, probes EOF, and closes the handle on every branch. Base's file-size operation rejects files larger than 4294967295 bytes.

Native display refresh can cap the observed CPU rate. This benchmark measures the complete slice rather than isolated GPU compute throughput.

The following medians are historical measurements of the fixed isometric renderer before the perspective camera change. They do not measure perspective flight or establish its current thread and GPU decomposition performance. Rerun `make benchmark` to measure the current cached-scene workload on the available hardware and display.

| Execution | CPU threads | Tile depth | Fork depth | Median ms per displayed frame |
| --- | ---: | ---: | ---: | ---: |
| CPU | 1 | 6 | 0 | 19.375 |
| CPU | 1 | 6 | 6 | 19.167 |
| CPU | 6 | 6 | 6 | 16.708 |
| CPU | 12 | 6 | 6 | 16.708 |
| GPU | 1 | 4 | 0 | 858.833 |
| GPU | 1 | 4 | 4 | 46.500 |
| GPU | 1 | 5 | 5 | 16.708 |
| GPU | 1 | 6 | 6 | 16.708 |

The daylight renderer was measured on the owned native Xvfb display with 48 measured frames, eight warm-up frames, two repetitions, and reversed launch order. Each run includes four edit/reset cache rebuilds. CPU thread counts and GPU decomposition were measured independently. These medians include cache construction and native presentation; they are not isolated GPU compute timings.

| Execution | CPU threads | Tile/fork depth | Median ms per displayed frame |
| --- | ---: | ---: | ---: |
| CPU | 1 | 5/5 | 127.688 |
| CPU | 6 | 5/5 | 62.604 |
| CPU | 12 | 5/5 | 54.042 |
| CPU | 1 | 6/6 | 113.854 |
| CPU | 6 | 6/6 | 59.479 |
| CPU | 12 | 6/6 | 51.302 |
| GPU | 1 | 5/5 | 174.281 |
| GPU | 1 | 6/6 | 90.229 |
| GPU | 1 | 7/7 | 91.042 |

Depth six improves both repetitions on the tested CPU configurations and nearly halves GPU frame time relative to depth five. Depth seven provides no repeatable GPU improvement. Tile and fork defaults therefore change to six, with the existing runtime overrides retained. All sixteen full/cut image exports at depths four through six remain byte-identical. Shadow construction stays sequential, with no new forks or backend-specific operations. Edits rebuild the entire daylight cache and remain more expensive than camera reprojection or idle frames. Metal and future WebGPU performance are unmeasured.
