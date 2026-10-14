# Combat Fairness, Chunk Culling and Material Response Plan

> **For agentic workers:** Execute the six phases in order. Each phase follows RED → GREEN → focused verification, then the full repository gates. Never move simulation authority into JavaScript.

**Goal:** Close the six gaps the previous combat/visual pass left open: melee line-of-sight and facing, per-chunk frustum culling with real submit metrics, incremental WebGPU terrain edits, a mipmap-safe atlas gutter, separated albedo/lighting/material shading with depth-aware water, and a WebGPU gate that proves a real frame instead of only a pipeline.

**Architecture:** Bend 2 stays authoritative for threat detection, line-of-sight, melee reach and world queries. JavaScript keeps presentation, chunk buffer lifetime, camera culling inputs, texture generation and browser-only readback. Every phase adds a pure test at the contract seam plus, where the symptom crosses WebGL/WebGPU or input, a browser assertion.

**Tech stack:** Bend 2, Bun, WebGL, WebGPU/WGSL, Playwright, existing atlas and renderer modules.

---

## Quality bar

- A hostile mob never damages a player across a solid block, and never damages a player outside its facing cone.
- The WebGPU renderer reports visible-chunk, draw-call and submitted-byte metrics, and a benchmark shows the culling win.
- A single mined or placed block re-uploads only the edited chunk and its seam neighbors, never the whole window.
- Atlas mipmaps are off until a foreign-tile-contamination probe passes, then on with a gutter.
- Albedo, lighting and material response are separate stages, with WebGL/WGSL parity asserted by one test.
- The WebGPU gate reads back a real rendered frame and probes the scene; a fallback reports `skipped` with an explicit diagnostic.

---

## Phase 1 — Line-of-sight and facing in Bend

**Files**

- Modify `world/entities.bend` — `threat_damage` requires unobstructed line-of-sight and a facing cone.
- Modify `tests/entities-bend.test.mjs` — pure LOS/facing/dead-state regressions.
- Modify `web/game.js` — pass the mob regions already built for `step_world` into `threat_damage`.
- Modify `scripts/browser-smoke.mjs` — wall-blocked attack and back-turned mob assertions.
- Modify `benchmarks/entities-step.mjs` — include the threat path in the reproducible benchmark.

**Tasks**

1. RED: a hostile 1.2 blocks away with a solid cell between it and the player must return `0` damage.
2. RED: a hostile at melee range whose heading points away from the player must return `0` damage.
3. RED: a hostile at melee range whose heading points at the player through clear air must return damage.
4. GREEN: implement `line_of_sight` over the existing `Region` block list, sampling only the cells strictly between mob and player.
5. GREEN: implement `facing_cone` as a dot product between the mob heading and the mob→player vector, with a per-kind half-angle and a distance-zero exemption for contact damage.
6. GREEN: keep the dead-record filter; add a test that a dead hostile inside the cone and in line of sight still deals no damage.
7. Run the focused entity test, `npm run check:bend`, `npm run proof`, `npm run bench:entities`.
8. GREEN: thread the regions through the browser bridge; add the browser smoke assertions.

---

## Phase 2 — Chunk culling and submit metrics

**Files**

- Create `web/chunk-frustum.js` — pure AABB/plane extraction, sphere tests, visibility contract.
- Create `tests/chunk-frustum.test.mjs` — pure culling and metrics regressions.
- Modify `web/webgpu-terrain-renderer.js` — cull per chunk before submit; count draw calls and bytes.
- Modify `benchmarks/renderer-benchmark.mjs` — report culled vs submitted chunk counts.

**Tasks**

1. RED: a chunk fully outside the frustum must be culled; a partially visible chunk must be kept.
2. RED: submit metrics must expose visible chunks, draw calls and submitted vertex bytes.
3. GREEN: extract the six clip planes from the view-projection matrix in column-major order.
4. GREEN: store a per-chunk AABB at upload time from the packed positions, and cull in `render()`.
5. GREEN: expose `visibleChunks`, `drawCalls`, `submittedVertexBytes`, `culledChunks` through `getStats()`.
6. GREEN: run `npm run bench:renderer-browser` before and after; report the measured numbers.

---

## Phase 3 — Incremental WebGPU terrain edits

**Files**

- Modify `web/webgpu-terrain-renderer.js` — separate bulk `uploadTerrain` from single-chunk `updateChunk`.
- Modify `web/game.js` — route block edits to `updateChunk` and full resyncs to `uploadTerrain`.
- Create `tests/webgpu-chunk-updates.test.mjs` — pure edit-vs-resync upload accounting.
- Modify `scripts/browser-smoke.mjs` — mine and place, then assert only the touched chunk re-uploaded.

**Tasks**

1. RED: an edit must re-upload only the edited chunk and its seam neighbors, not the whole window.
2. RED: a streaming resync must still retire chunks that left the active set.
3. GREEN: add `updateChunk({ key, chunkX, chunkZ, vertexData })` with the same source-identity reuse rule.
4. GREEN: track `editUploads` and `resyncUploads` separately in the stats.
5. GREEN: route the mined/placed path through `updateChunk`.
6. Validate mining and placement visually at fixed camera poses.

---

## Phase 4 — Mipmap-safe atlas with a gutter

**Files**

- Modify `web/texture-atlas.js` — gutter/padding layout, atlas metrics, mipmap-aware upload.
- Modify `web/atlas-probe.js` — foreign-tile-contamination probe helpers.
- Modify `tests/texture-atlas.test.mjs` — gutter, UV inset, mipmap chain regressions.
- Create `tests/atlas-mipmap-safety.test.mjs` — pure foreign-tile contamination test.
- Modify `web/game.js` — enable mipmaps only after the probe passes.

**Tasks**

1. RED: without a gutter, mip level 1 mixes neighboring tiles and must be reported as contaminated.
2. RED: with a gutter, the mip chain must stay inside the owning tile.
3. GREEN: add `ATLAS_TILE_GUTTER` and grow the atlas so each tile owns a padded cell.
4. GREEN: inset UVs by half a texel of the padded cell so linear filtering never crosses the gutter.
5. GREEN: add `foreignTileContamination(tile, level)` that compares mip texels against the owning tile only.
6. GREEN: enable `generateMipmap` only when the contamination probe is clean; keep the deterministic fallback and record the decision in the frame diagnostics.

---

## Phase 5 — Material response and water depth

**Files**

- Modify `web/terrain-presentation.js` — albedo/lighting/material constants, roughness, water depth.
- Modify `web/webgl-shaders.js` — separated albedo → lighting → material stages.
- Modify `web/webgpu-terrain-renderer.js` — matching WGSL material contract.
- Modify `tests/webgpu-terrain-presentation.test.mjs` — WebGL/WGSL parity assertions.

**Tasks**

1. RED: assert the WebGL and WGSL sources declare the same stage order, roughness, detail and water-depth constants.
2. RED: assert water color responds to depth and roughness, and that the terrain path is not tinted by water constants.
3. GREEN: split the fragment path into albedo (texture + variation), lighting (daylight, ambient, moon) and material (roughness, detail shading, specular).
4. GREEN: add low-amplitude detail shading derived from the material sample, keeping the software fallback simpler.
5. GREEN: add water depth attenuation and a controlled roughness/specular term in both backends.
6. Run `npm run test` and `npm run browser:lighting-smoke`.

---

## Phase 6 — Visible WebGPU validation

**Files**

- Modify `web/webgpu-terrain-renderer.js` — async frame readback into a mappable buffer.
- Modify `web/game.js` — `readFramePixels` on the WebGPU path plus scene probe diagnostics.
- Modify `scripts/webgpu-smoke.mjs` — real-frame probes and explicit `skipped` diagnostics.
- Modify `tests/webgpu-frame-readback.test.mjs` — pure readback contract regressions.

**Tasks**

1. RED: `readFramePixels` on the WebGPU path must return real pixels, not throw.
2. RED: the gate must probe the scene (non-blank, terrain present, culling metrics consistent), not only the pipeline.
3. GREEN: copy the swap-chain texture to a `COPY_SRC` texture, map it, and return RGBA bytes.
4. GREEN: add scene probes: distinct colors in a fixed region, horizon silhouette, and culled-vs-visible chunk agreement.
5. GREEN: when WebGPU presentation is unavailable, emit `status: "skipped"` with the probe reason, the browser flags, and the fallback renderer actually used.
6. Run `npm run browser:webgpu-smoke` and record whether the run passed or skipped, with the diagnostic.

---

## Verification gates

- `npm run verify` after every phase.
- `npm run test` focused on the touched seam before the full suite.
- `npm run browser:smoke` for phases 1, 3, 4 and 5.
- `npm run browser:webgpu-smoke` for phases 2, 3 and 6.
- `npm run bench:entities` for phase 1 and `npm run bench:renderer-browser` for phase 2.
- Inspect `git status` and `git diff` before every commit; do not touch unrelated worktree changes.
