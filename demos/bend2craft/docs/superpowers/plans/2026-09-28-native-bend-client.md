# Native Bend2Craft Client Plan

**Goal:** Replace browser-only gameplay and presentation with a native Bend 2 application while retaining the current world's observable behavior.

**Architecture:** Keep `world/*.bend` authoritative. The native client owns a bounded fixed-step game loop, input capture, view generation, audio and local caches; it uses Bend `Window`, `Image` and `Audio` rather than browser APIs. Treat the pinned `vendor/bend/demos/app_slash_boss_3d` as a feasibility reference, not application code to modify.

**Dependency:** Start after the feasibility plan's window/input/frame gate passes. Prepare detailed task-level plans for rendering and gameplay separately once native frame costs are known.

**Platform decision (2026-09-28):** Ship the native client on Linux and macOS, and support Windows through WSL with a configured graphical display. A Windows `.exe` is not a target for the current Bend pin; Xvfb smoke does not replace a desktop-visible platform test.

**Current evidence (2026-09-28):** `lab/native/render-probe/` constructs a 16×16 Bend `Image` from bulk `World.chunk`; its regression distinguishes a neighboring chunk and edited surface. `lab/native/voxel/` pins perspective views, near-block occlusion and a position-aware camera. Replacing per-ray flat-list indexing with a nested y/z/x grid cut the 32×32 render from about 793 ms to 12.4 ms, and the parent rerun of the agent's full-frame benchmark (chunk + grid + image + fingerprint, single thread, `--gpu off`) measured medians of **22.2 ms at 32×32, 60.5 ms at 64×64 and 212.6 ms at 128×128**, with chunk+grid bootstrap 9.7 ms per frame. Only power-of-two square frames exist, because the native `Image` is a quadtree. **No plausible game window meets a 16.7 ms budget with this per-pixel raycaster**; the Xvfb smoke still shows only the simpler y=8 world slice.

**Parallelism is exhausted (2026-09-29):** `lab/native/voxel/run-parallel.sh` sweeps `--threads 1 4 8 16` with seven samples each, and the parent reran the whole sweep: all 28 runs produced the same digest for the forked frame as for the single-thread frame, and the `!` bang on the root image call changes nothing, because `image` already forks its four quadrants with a parallel let. Per-frame medians on the WSL2 Ryzen 7 9800X3D (8 cores visible to WSL): 32×32 from 22.3 ms to 17.4 ms, 64×64 from 60.3 ms to 36.0 ms, 128×128 from 211.8 ms to 111.1 ms — a maximum of **1.9×**, saturated at 8 threads. The cost is data structure, not arithmetic: each voxel probe walks three nested `List.get` chains (~52 cons steps) and the DDA takes ~21 probes per pixel. The pinned Base has no faster numeric lookup, because `Array<U32>` is a `Type` and so cannot be shared by a parameter used many times, and `Map` is String-keyed. **No 60 FPS native window is reachable from the per-pixel raycast.**

**Chosen approach (2026-09-29):** replace per-pixel raycasting with a visible-face renderer that extracts every exposed face in one forward pass, projects and buckets faces by screen tile, and lets each pixel pick the nearest covering face from its tile bucket. The parent rerun measures, per frame at `--threads 1`: 4.9 ms at 32×32, 7.1 ms at 64×64, **15.8 ms at 128×128** and 65.0 ms at 256×256, against 20.5 / 52.3 / 179.4 for the ray renderer. Face extraction is 1.3 ms and camera-independent; projection plus bucketing is 0.4 / 0.9 / 2.4 ms. A bucket-lookup defect that made the per-pixel path scan the whole bucket grid was found and fixed during this work, which is what moved 128×128 from 35 ms to 15.8 ms. `face_extraction_test.bend` pins 2102 solid cells and 1298 exposed faces for chunk 1337 at 0,0, counted by two independent routes, so an under-extracting renderer can no longer pass as a fast one.

**Target and its two hard limits (2026-09-29, corrected 2026-09-30):** the user decided not to fork the pinned runtime. Two measured blockers put 1920×1080 at 144 Hz out of reach, and neither is a tuning problem:
- The runtime's own window effect paces every frame to a hardcoded 16,666,667 ns (60 Hz) in `vendor/bend/bend2/effs/window.c`, so no native window can exceed about 60 FPS at any resolution without editing upstream.
- The image pipeline costs about 7.4 ns per pixel even for a renderer that does no visibility work at all, which caps a free renderer at roughly 70 FPS at 1920×1080. The face renderer costs about 550 ns per pixel, about 164 times the 3.3 ns a 144 Hz 1080p frame would need, and it measures 2.9 s at 1024×1024 with eight threads.

The measured ceiling of a free renderer is 1024×1024 at 60 FPS. The dirty-frame policy cannot extend it either: `Window.frame` consumes the image and `App.turn` frees it, so every displayed frame must be rendered.

**The 128x128 claim was wrong, and here is the measurement that corrected it (2026-09-30).** The plan above shipped 128x128 on the strength of a face-probe figure of 12.6 ms at 128x128 and eight threads. That figure came from the face probe's own pinned camera, a sparse synthetic pose, not from the client's. `lab/native/client-probe/` now measures the client's real stages at the client's real spawn camera, with the image read back through the same quadtree walk `window_show` performs. Per-call medians over seven samples, native C, `--gpu off`, on the WSL2 Ryzen 7 9800X3D with eight threads:

| phase | 32x32 | 64x64 | 128x128 |
| --- | --- | --- | --- |
| render | 5.98 ms | 9.45 ms | 22.55 ms |
| tick | — | 0.88 ms | 0.88 ms |
| frame (the two together) | — | ~10.3 ms | 24.35 ms |

So **128x128 is about 41 FPS and does not meet 60 Hz**; **64x64 is about 97 FPS and fits with roughly 6 ms of headroom**. The 128x128 target is withdrawn in favour of 64x64 unless the renderer gets faster, and the honest reading is that 64x64 is the size this engine holds at 60 Hz on this machine.

Three things that measurement settles, each of which a smaller benchmark could not have:

- **The per-frame chunk rebuild is not the problem.** `WorldState.chunk` from the seed and the edit log costs **0.10 ms**, so caching the chunk would save nothing worth having. The constitution's "build a chunk once, then only render it" is still the right rule, but it is not what is costing the frame here.
- **Threads buy about 3.4x, not 8x.** 82.40 ms down to 22.55 ms at 128x128. The bucketing pass forks, the per-pixel selection does not, so the render is partly serial.
- **The face renderer's agreement is not free of consequence.** The 64x64 figure is at the same pose as the 128x128 one, so the two are comparable, but neither is a worst case: a camera looking across a wide valley will show more faces than the spawn camera, and the cost moves with the pose.

**The client's own end-to-end proof (2026-09-30).** `lab/native/client-probe/smoke.sh` runs the compiled client under Xvfb, waits for its window by title, focuses it (the bare Xvfb has no window manager, and the runtime's pointer grab refuses to engage without focus, so without this the player can never turn), sends real key events, digests the window's own pixels from the XWD framebuffer after each press, and reads back the saved world. It verifies that walking changes the frame, that turning changes the frame, that escape closes the loop, and that the save key wrote a `B2CW:1` snapshot. `native/client_test.bend` proves the same client's headless contracts.

**Player boundary evidence:** `lab/native/player/` composes several bulk `WorldState.chunk` exports into one collision region, refuses ambiguous or out-of-range stored coordinates at the Bend boundary, and delegates movement, seam crossing and neighbouring-chunk collision to `Player.step`. The focused native test passes and the parent reran it. Single-thread WSL2 medians over 32 ticks: one chunk re-materialized per tick 17 ms, one cached region 8 ms, a 2×2-chunk region 31 ms, materialization alone 1–2 ms. Tick cost is linear in region volume because `Player.region_block` walks the region list from its head, so a 3×3 grid roughly doubles the frame again; the grid is anchored at its chunk with no re-anchoring rule, and `WorldState.chunk` cannot materialize negative world cells.

## File boundaries

- Create `native/game.bend` for game-loop state and calls into existing Bend rules.
- Create `native/view.bend` for native frame/image construction and `native/input.bend` for `Event` to domain input translation only if the small client cannot stay readable in fewer files.
- Create `native/audio.bend` for sound generation and `native/save.bend` for save/load once those boundaries have tested contracts.
- Extend `world/*.bend` and its focused tests only when a rule now in `web/inventory.js`, `web/game-state.js`, `web/chunk-world.js` or other browser modules genuinely lacks a Bend contract.
- Keep `web/` and `scripts/` running until the replacement passes its gate; do not make `vendor/bend` an application fork.

## Tasks

- [ ] Pin parity fixtures for a seed, generated and edited chunk, inventory/crafting, movement/collision/raycast and restart before changing their paths. Add a failing test at each Bend contract seam.
- [ ] Implement the native fixed-step loop with bounded update time and Bend-owned player/world transitions. Validate movement, collision, mining, placement, selected inventory slot and tree visibility through the real window.
- [ ] Port chunk materialization, lighting, visible-face generation, camera and UI to Bend, in batches; keep rendering-derived caches distinct from authoritative state. Profile chunk bootstrap and frame p95 for each increment.
- [ ] Add input-driven inventory, crafting, health, sound and save/load. Check action → state transition → rendered result, not only unit outputs.
- [ ] Test the native path on each intended platform. The current Bend pin has no direct Windows native target; WSL is not equivalent to a supported Windows desktop build.
- [ ] Re-run focused Bend checks, proofs, regression fixtures, `npm run verify` and representative native benchmarks after each vertical slice. Preserve the browser regression suite until the native suite covers its behavior.

## Exit gate

The native executable demonstrates the agreed single-player features with verified input, simulation, visible frames, audio and restart/load; measured frame and chunk costs are documented. Visual equivalence to the current WebGL/WebGPU renderer is a separate acceptance decision, not assumed from the native 3D demo.
