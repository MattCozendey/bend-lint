# Native Bend2Craft Feasibility Plan

**Goal:** Establish whether the pinned Bend 2 can deliver a playable native slice before replacing the browser client.

**Architecture:** Reuse `world/*.bend` directly in a small native executable. Use Bend's `Window`, `Image`, `Event` and `File` effects; do not add game rules in a host language. Keep the browser and Bun paths intact during this experiment.

**Dependencies:** None of the other native migration plans may remove an existing path until this gate passes.

**Current evidence (2026-09-28):** A locally compiled Bend 2.0.32 CLI checks the world and proof files, compiles a native benchmark and builds `native/main.bend` without Bun on `PATH`. The authorized X11 and ALSA development headers are installed in WSL. Headless tests verify a world-derived image and a single edit through Bend `File`. Direct execution reports `Window.open: no display` because `DISPLAY` is unset. Under Xvfb, `lab/native/window-probe/smoke.sh` observes world-derived pixels, real X11 W/E/Escape keys, an edit saved as `[8,7]`, process exit and restart, and the restored edit displayed as stone `#858585` after moving the cursor. `lab/native/bench-probe/run.sh` is a reproducible single-thread CPU baseline: on the WSL2 Ryzen 7 9800X3D, the parent run measured medians of 0.142 ms per chunk build **plus fingerprint** and 0.373 ms per 16×16 image **plus fingerprint**. This verifies the virtual-display slice, **not** a desktop-visible window, full game performance or an improvement over the browser.

## File boundaries

- Create `native/main.bend` for the bounded window/input/frame experiment, importing existing world contracts.
- Put pure state/render helpers in `native/` only when they would otherwise obscure the experiment's checks.
- Add a focused Bend test for every pure rule introduced; do not rewrite existing JS tests yet.
- Do not edit `vendor/bend`, `web/`, `server/` or `cloudflare/` for this spike. Register the focused Bend checks in the existing test script without changing its browser test list.

## Tasks

- [x] First establish a failing focused test for a world-derived pixel or state transition; then implement the minimum pure Bend function that passes it.
- [x] Build with the pinned Bend 2 compiler under WSL on Windows, targeting a native executable rather than JavaScript; install system packages only with authorization.
- [x] Draw an image dependent on real data from `World.chunk`; the 16×16 slice and edit change observed pixels.
- [x] Observe an X11 key changing state and a subsequent pixel under Xvfb. A desktop-visible window remains unverified.
- [x] Save one world edit to a disposable file with Bend `File` effects, restart the process, load it, and observe the restored stone pixel. Existing user saves are not compatible.
- [x] Capture a native CPU baseline for chunk build and 16×16 image construction at seed 1337, chunk (0,0), with `bash lab/native/bench-probe/run.sh`; fingerprints are included in the timings.
- [ ] Measure complete window frame-time and compare to the browser only under comparable conditions. A 256×256 native slice does not establish a game-FPS result or speedup.
- [x] Re-run the focused Bend checks and `npm run verify` after registering the native benchmarks and contract checks; all 122 JavaScript tests, eight Bend probes and the browser build passed. `--verdict` remains blocked by missing Lean; the existing `proof` gate does not run it.

## Exit gate

A buildable native executable, an observed world-derived frame, an observed input-to-frame transition and a restart/load check. Missing criteria block the decision to replace the browser client; keep the prototype and browser side by side.
