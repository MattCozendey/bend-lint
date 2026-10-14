# Combat Fairness and Visual Quality Implementation Plan

> **For agentic workers:** Execute the tasks in order. Each behavior change follows RED → GREEN → focused verification, then the full repository gates.

**Goal:** Make hostile-mob damage obey a short, explicit melee contract and raise the voxel presentation from noisy low-resolution tiles to a coherent, validated material pass without moving simulation authority into JavaScript.

**Architecture:** Bend remains authoritative for mob state, attack range, damage, death, drops, terrain, and world generation. JavaScript only presents Bend state, captures input, updates browser meshes/caches, and selects WebGL/WebGPU quality tiers. Texture generation and sampling stay dependency-free and deterministic so the same assets can be validated in Node tests and in both browser renderers.

**Tech Stack:** Bend 2, Bun, WebGL, WebGPU/WGSL, Playwright, existing atlas and renderer modules.

---

## Quality bar

- A hostile mob cannot damage a player outside the documented melee radius.
- A mob with `alive == false` cannot contribute damage on a later simulation tick or browser frame.
- Static terrain does not flicker, atlas sampling does not bleed between tiles, and material changes remain within the existing software-renderer budget.
- Day/night, water, terrain, and mob captures are reviewed at fixed camera poses with reproducible seeds.
- WebGL and WebGPU use equivalent material sampling and grading contracts; unsupported WebGPU presentation falls back without shader errors.

## File map

- Modify: `world/entities.bend` — authoritative hostile threat range and dead-state filtering.
- Modify: `tests/entities-bend.test.mjs` — pure range/death regressions.
- Modify: `web/game.js` — browser bridge checks and presentation-safe mob state refresh.
- Modify: `scripts/browser-smoke.mjs` — end-to-end far-attack and post-death assertions.
- Modify: `web/texture-atlas.js` — higher-resolution coherent material patterns and atlas metrics.
- Modify: `tests/texture-atlas.test.mjs` — deterministic tile, UV, contrast, and atlas-size regressions.
- Modify: `web/terrain-presentation.js` — shared material/tile presentation constants.
- Modify: `web/webgl-shaders.js` — filtered material sampling and restrained detail/grade changes.
- Modify: `web/webgpu-terrain-renderer.js` — matching sampler and WGSL material contract.
- Modify: `tests/webgpu-terrain-presentation.test.mjs` — WebGL/WGSL parity checks.
- Create: `scripts/visual-quality-smoke.mjs` — fixed-pose capture and image-quality probes.
- Modify: `package.json` — `browser:visual-quality` command.

---

### Task 1: Lock the hostile-mob contract with failing Bend tests

- [x] Add a test that places a hostile beyond the melee radius, advances `Entities.step_world`, and asserts the returned player damage is zero.
- [x] Add a test that marks a hostile dead, advances at least two subsequent ticks, and asserts no damage is returned and the mob remains dead.
- [x] Run `bash scripts/run-bun.sh tests/entities-bend.test.mjs` and record the pre-fix failure.

### Task 2: Fix range and death at the Bend boundary

- [x] Trace the exact arguments and returned state from `Entities.step_world` before changing code.
- [x] Make threat contribution require both a hostile kind and `alive`, and compare the documented horizontal melee radius using the same player/mob coordinates passed by the browser bridge.
- [x] Ensure dead records are filtered before threat accumulation and cannot be reintroduced by a later tick.
- [x] Run the focused entity test, `npm run check:bend`, and `npm run proof`.

### Task 3: Add browser regressions and verify the bridge

- [x] Add a browser-smoke scenario that pauses the simulation, places the player beyond melee range, resumes for bounded ticks, and asserts health is unchanged.
- [x] Kill a hostile through the real primary-action path, then resume for bounded ticks and assert health is unchanged while the mob remains dead.
- [x] Run `npm run browser:smoke` and confirm no console/page errors.

### Task 4: Upgrade the atlas without breaking UV parity

- [x] Add pure tests for the new tile size, UV bounds, deterministic output, minimum contrast, and no cross-tile edge contamination.
- [x] Increase the generated material tile resolution while keeping the atlas dimensions power-of-two and the existing tile registry stable.
- [x] Replace isolated per-pixel noise with coherent multi-scale patterns for stone, dirt, grass, wood, leaves, ores, sand, and fluids; retain deterministic seeds and restrained face variation.
- [x] Keep item/first-person atlas consumers on the same explicit tile contract.

### Task 5: Improve texture sampling in both renderers

- [x] Use linear magnification, mipmap/minification filtering where supported, clamped atlas edges, and conservative half-texel UV insets.
- [x] Add anisotropy only when the WebGL extension is present; keep a deterministic fallback.
- [x] Match WebGPU sampler state and material grading with the WebGL advanced path.
- [x] Update the WebGPU parity tests and run the shader-validation smoke.

### Task 6: Add restrained material lighting

- [x] Preserve the current authored palette and face shading while adding low-amplitude detail derived from the material sample.
- [x] Keep the software fallback shader simpler than the advanced shader and avoid per-cell JavaSScript work.
- [x] Verify that static screenshots do not flicker and that water/terrain silhouettes remain readable at day and night.

### Task 7: Add a reproducible visual-quality gate

- [ ] Capture fixed seed/camera/time poses for day, night, shoreline, mining edit, and mob combat.
- [ ] Probe static-region changed pixels, nonblank output, tile contrast, and renderer error arrays.
- [ ] Add `npm run browser:visual-quality` and keep the script bounded with a timeout and cleanup.
- [ ] Run the visual gate, `npm run browser:lighting-smoke`, `npm run browser:webgpu-smoke`, and `npm run bench:renderer-browser`.

### Task 8: Final quality review

- [ ] Run `npm run verify` after every merged phase.
- [ ] Inspect `git diff --check`, `git status`, and the scoped diff; do not overwrite unrelated pre-existing worktree changes.
- [ ] Report measured FPS/p95/p99, renderer used, remaining hardware limitations, and the exact captures reviewed. Do not claim AAA certification; report the achieved quality gates and remaining art/content work.
