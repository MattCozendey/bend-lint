---
name: Bend2Craft
description: A world-first, tactile voxel sandbox with restrained Bend 2 signals.
colors:
  coal: "#101310"
  deep-moss: "#172019"
  moss: "#2f4a32"
  grass: "#6f9b45"
  stone: "#5e625d"
  slate: "#2b302d"
  iron: "#8b918c"
  parchment: "#f2edda"
  muted: "#c5c4b6"
  wood: "#8a5a34"
  amber: "#f0bd55"
  amber-deep: "#9b6725"
  bend-mint: "#78dbc1"
  danger: "#e45b4f"
  world-sky: "#6f9bb4"
  world-horizon: "#b5d8d7"
  panel: "rgba(20, 24, 21, 0.97)"
  panel-soft: "rgba(33, 39, 34, 0.94)"
  line: "rgba(242, 237, 218, 0.2)"
  bevel-light: "rgba(255, 255, 255, 0.22)"
  bevel-dark: "rgba(0, 0, 0, 0.72)"
typography:
  display:
    fontFamily: "Silkscreen, Courier New, monospace"
    fontSize: "clamp(30px, 4.6vw, 58px)"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.03em"
  title:
    fontFamily: "Silkscreen, Courier New, monospace"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Trebuchet MS, Segoe UI, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.5
  data:
    fontFamily: "ui-monospace, SFMono-Regular, Consolas, monospace"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "ui-monospace, SFMono-Regular, Consolas, monospace"
    fontSize: "10px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0.08em"
rounded:
  none: "0px"
  slot: "0px"
spacing:
  hairline: "1px"
  tight: "5px"
  base: "8px"
  panel: "18px"
  edge: "clamp(18px, 3vw, 42px)"
components:
  button-primary:
    backgroundColor: "{colors.grass}"
    textColor: "{colors.coal}"
    rounded: "{rounded.none}"
    padding: "10px 14px"
    height: "42px"
  button-secondary:
    backgroundColor: "{colors.slate}"
    textColor: "{colors.parchment}"
    rounded: "{rounded.none}"
    padding: "8px 10px"
    height: "36px"
  field:
    backgroundColor: "{colors.coal}"
    textColor: "{colors.parchment}"
    rounded: "{rounded.none}"
    padding: "9px 10px"
    height: "42px"
  panel:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.parchment}"
    rounded: "{rounded.none}"
    padding: "18px"
  hud-status:
    backgroundColor: "{colors.coal}"
    textColor: "{colors.parchment}"
    rounded: "{rounded.none}"
    padding: "8px 12px"
  inventory-panel:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.parchment}"
    rounded: "{rounded.none}"
    padding: "18px"
  slot:
    backgroundColor: "{colors.stone}"
    textColor: "{colors.parchment}"
    rounded: "{rounded.slot}"
    size: "clamp(32px, 3.4vw, 48px)"
---

# Design System: Bend2Craft

## Overview

**Creative North Star: "The Crafted World"**

Bend2Craft is a familiar first-person voxel sandbox whose interface is built from the same material logic as the world it presents. The world is the hero: sky, terrain, water, trees, and light carry the atmosphere, while menus and HUD elements behave like compact pieces of equipment laid over that scene. The visual language is tactile and confident rather than soft or futuristic.

The implemented system uses a coal-and-parchment control surface, grass green for the primary path, torch amber for selection and progress, and a small amount of Bend mint for provenance. Mint appears in seed/loading labels, coordinates and selected-system states; it never becomes a neon HUD takeover. Pixel geometry, hard square silhouettes, inset/outset bevels, 16px material tiles, and small offset shadows make the controls feel constructed from blocks without copying Minecraft branding or assets.

**Key Characteristics:**
- The world fills the viewport before any menu card or dashboard chrome.
- Green, amber, and mint have stable semantic jobs: go, select/progress, and engine provenance.
- The HUD hugs the edges of play and keeps the crosshair, hotbar, and survival state close to the action.
- Inventory and operating surfaces use dense, scroll-safe grids with material-specific item icons.
- Motion is purposeful: water, hand bob, loading progress, mining feedback, and short state transitions.

### Interaction model

- **Entry and return:** The router boots the menu without the game engine when `play=1` is absent. A selected profile/world or the first-world flow leads through a short loading screen, then a full reload starts a clean game session. Quitting to title returns to the world-first menu.
- **Title flow:** The title view shows the current world summary when a save exists, otherwise it offers `Create Your First World`. Profile selection, world selection, creation, deletion, random seed, help, and options are linear screens inside the menu dialog. Profiles, worlds, options, and saves are local to the browser.
- **Play capture:** Clicking the canvas captures the mouse. `WASD` moves, the mouse looks, `Space` jumps/swims, `Shift` sneaks, `Ctrl` sprints, `1`–`9` select hotbar slots, and `Esc` releases pointer lock. Left click attacks a mob under the crosshair or mines when no mob is targeted, right click places, and `F` attacks or shoots.
- **Manage during play:** `E` opens inventory and crafting, `R` opens a furnace when available, `C` opens a chest, `G` eats, `Q` drops, `T` trades, and `N` sleeps. Inventory, furnace, and chest actions also have compact HUD buttons where the current state makes them relevant.
- **Inventory transfer:** Click an item and then a destination slot; right-click picks up half a stack, drag-and-drop moves a full stack, and Shift-click transfers between inventory sections. Equipment, shaped crafting, furnace, and chest panels close explicitly and return focus to their trigger or the canvas.
- **Feedback loop:** The crosshair owns center, the selected-item label sits above the hotbar, health/hunger/air and experience sit near the lower edge, and mining, toasts, particles, damage flash, and lock hints explain state changes without a tutorial wall.
- **Accessible states:** Menu and container surfaces use dialog roles, modal game surfaces inert the background and contain focus, Escape closes recoverable panels, loading surfaces use honest live status/progress semantics, controls receive focus, errors are announced, and `prefers-reduced-motion` disables authored transitions.

### Renderer parity

The two renderer paths share an authored presentation contract; they are not claimed to be bit-identical across APIs. WebGL is the verified local presentation path. WebGPU is optional and uses the same visual constants and vertex data with a different buffer/pipeline organization. WGSL texture sampling is kept in uniform control flow, and WebGPU-capable runs use asynchronous render-pipeline creation so shader validation is not reduced to a source-string check.

| Shared contract | Evidence | WebGL implementation | WebGPU implementation |
| --- | --- | --- | --- |
| Opaque/water geometry, greedy merging, atlas UVs | `web/terrain-vertex-builder.js`, `web/mesh-cache.js` | Combined typed arrays and terrain/water passes | Interleaved per-chunk terrain and water buffers |
| Vertex lighting inputs | `web/terrain-vertex-builder.js`, `web/greedy-mesh.js` | `aNormal` + `aLight` (occlusion, block light); `aColor` is a per-face grade only | Same layout, interleaved into a per-chunk buffer at stride 18 floats |
| Per-pixel lighting | `web/terrain-presentation.js`, `web/webgl-shaders.js` | Sun term from the sun direction, hemispheric sky ambient gated by occlusion, GGX specular | Matching sun and ambient terms from the same constants |
| Sun shadow cascade | `web/webgl-shadow.js` | Depth-texture cascade, per-pixel rotated Vogel filter, normal-offset bias, light floor | Not implemented; the WebGPU stage has no cascade |
| Volumetric clouds, god rays, HDR post | `web/webgl-post.js`, `web/webgl-shaders.js` | Raymarched cloud deck, depth-derived god rays, bloom, ACES tonemap, grade, FXAA | Not implemented; WebGPU presents the scene directly |
| Material texture synthesis | `web/material-textures.js`, `web/texture-atlas.js` | One procedural painter per material (colour and height field, tileable noise), composed into a shared padded atlas canvas | Shares the same atlas canvas |
| Painterly water | `web/terrain-presentation.js` | Gerstner swell, per-pixel wave normals, depth absorption, foam, caustics, sun glitter | Matching swell and water branches, without the advanced terms |
| Lava, fire, and mining feedback | `web/terrain-presentation.js`, `web/mining-controller.js` | Alpha/pulse/crack shader branches | Matching alpha/pulse/crack branches |
| First-person hand, entities, and shadows | `web/first-person-hand.js`, `web/game.js` | Dynamic vertex buffer | Separate dynamic and shadow vertex buffers |
| World-space particles | `web/vfx.js`, `web/webgl-shaders.js` | Camera-facing quads in the terrain vertex layout, shaded procedurally and blended premultiplied | Mode 4 pipeline over the same layout, same premultiplied blend |
| Capability and fallback behavior | `web/webgpu-capabilities.js`, `web/game.js` | Forced `renderer=webgl` smoke path | Adapter and visible-presentation probe before use |

Shared presentation values include fog start `24`, material variation `0.985–1.015`, sun intensity `2.35`, ambient strength `1.25`, ambient desaturation `0.34`, shadow floor `0.16`, water normal strength `6`, Fresnel power `3`, water depth tint `0.34`, lava pulse amplitude `0.16`, lava alpha `0.86`, fire pulse amplitude `0.25`, and fire alpha `0.9`. The WebGPU path uploads per-chunk buffers and keeps dynamic geometry separate; this is a renderer implementation detail, not a new gameplay contract.

The HDR presentation stages (shadow cascade, volumetric clouds, god rays, bloom, tonemap) exist only on the WebGL path. That asymmetry is deliberate and recorded here rather than claimed as parity: WebGL is the verified presentation path, and the WebGPU stage is kept correct against the same vertex layout and lighting constants so it does not render a stale or wrong world. Closing the WebGPU gap would mean porting the cascade and the post chain to WGSL, which is not attempted here.

A single orthographic cascade covers a square in the light's own space, which is rotated in world space, so the region guaranteed for every sun direction is the inscribed circle of radius `SHADOW_RADIUS / sqrt(2)`. Sizing anything against the circumscribed value would overstate the coverage.

Villager pathfinding remains Bend-owned. The path grid is stored as one walkability bitmask per row, built by a dedicated worker during boot, and the simulation only evaluates villagers within the local player activity radius; this removes repeated multi-hundred-millisecond search/snapshot spikes without moving villager authority into JavaScript.

`Auto` uses the verified WebGL path so a blocked browser GPU probe cannot freeze world entry. WebGPU remains explicit opt-in and must pass a real adapter/presentation probe. Bend 2 browser evaluation remains sequential, and no browser GPU or multithread acceleration is claimed.

### Verification notes

The evidence for this record is bounded and reproducible:

| Evidence | What it establishes | Status |
| --- | --- | --- |
| `.impeccable/review/desktop-final.png` and `.impeccable/review/mobile-final.png` | Final title composition at 1440×900 and 390×844 | Visual review complete |
| `.impeccable/review/game-final.png` and `.impeccable/review/game-mobile-final.png` | Final game HUD, water, hand, hotbar, and survival composition at both sizes | Visual review complete |
| `.impeccable/review/inventory-final.png` and `.impeccable/review/inventory-mobile-final.png` | Final desktop three-column inventory and mobile stacked inventory | Visual review complete |
| `web/assets/world-preview.provenance.json` | The menu backdrop is a static project-generated WebGL render capture, 1440×900, seed `1337`, with overlays removed | Asset provenance recorded |
| `scripts/browser-smoke.mjs` / `npm run browser:smoke` | Returning-title navigation, menu focus, WebGL world hydration, spawn-mesh loading completion, HUD, modal focus/inert behavior, shortcut suppression, death cleanup, mining, placement, combat, inventory, containers, persistence, narrow overflow, and errors | **WebGL smoke passed** |
| `scripts/renderer-benchmark.mjs` / `npm run bench:renderer-browser` | Warmed browser frame sampling and renderer diagnostics; the latest default run used 1280×720, render distance 2, 2.5s, 71 samples, 27.78 FPS, p95 66.7 ms, p99 66.7 ms, minimum 14.99 FPS, and no errors; treat this as a headless diagnostic, not a target guarantee | **WebGL benchmark passed** |
| `RENDER_DISTANCE=6 npm run bench:renderer-browser` | Stress run at render distance 6: 169 active chunks, 133,106 terrain quads, 15.78 FPS, p95 116.7 ms, p99 116.8 ms, minimum 8.56 FPS, no errors | **High-distance stress measured; not a default-quality claim** |
| `npm run browser:streaming-smoke` | Distance-six progressive hydration with 64-target mesh batches and deferred WebGL publication; latest runs reached 169 active chunks and `pendingChunks: 0` in 5.8–6.7 s | **Streaming improvement measured** |
| `npm run verify` (WSL) | Bend checks, proof, 88 regression tests, static build, and repository diff check | Passed |
| `tests/ui-shell.test.mjs`, `tests/menu-navigation.test.mjs`, `tests/modal-focus.test.mjs`, `tests/villager-terrain.test.mjs`, `tests/startup-contract.test.mjs`, `tests/boot-resilience.test.mjs` | World-first shell semantics, dialog states, focus containment, reduced-motion contract, villager dirty policy, startup ordering, boot resilience, and continue-world selection | Contract tests pass |
| `tests/webgpu-terrain-presentation.test.mjs`, `tests/material-lighting.test.mjs` | Shared presentation constants, per-pixel lighting on both backends, shadow sampling, the volumetric cloud march, and surface effects | Contract tests pass |
| `tests/material-textures.test.mjs` | Tileable noise, painter determinism and seed dependence, palette validation, and the upper-left direction of the baked relief | Contract tests pass |
| `benchmarks/fps-cap.mjs` / `npm run bench:fps-cap` | Frame pacing on the real GPU (`--use-angle=metal`, headless, native retina): each stored cap is applied to the running loop, the drawn frame rate is differenced from the loop's own frame counter, the cap becomes the quality controller's budget, a cap above the display cadence drops no frames, and the ladder follows the budget. Latest run: uncapped `59.4 FPS` at a 16.6 ms budget settling on `medium`; 30 FPS cap `29.7 FPS` (119 frames/4001 ms) at 33.33 ms settling on `ultra`; 60 FPS cap `59.2 FPS` at 16.67 ms on `medium`; 120 FPS cap `59.5 FPS` at 8.33 ms on `minimal`; no page errors | **Frame pacing passed on Apple M1 Pro / ANGLE Metal** |
| `tests/visual-quality.test.mjs` | Tier monotonicity, hysteresis, the catastrophic-frame drop, recovery, that a tier *name* resolves to its own index instead of the default, and that the frame-time budgets follow a supplied target period instead of assuming a 60 Hz display | Contract tests pass |
| `tests/frame-pacer.test.mjs` | The offered limit set and the uncapped default, untrusted stored values, a cap that holds and a cap that never starves or floors the frame rate, a backwards clock, the learned display cadence in both directions, rejection of implausible cadences and coalesced outliers, and the startup probe's median | Contract tests pass |
| `tests/gl-render-target.test.mjs` | Colour-format selection under a driver that advertises but cannot render a format, filter enum resolution, depth attachment, and resize | Contract tests pass |
| `tests/sun-shadow.test.mjs` | Cascade framing for extreme sun angles, texel snapping, NaN freedom, and the declared uniform set | Contract tests pass |
| `tests/sun-shadow-wiring.test.mjs` | Every sampler the terrain program declares is located *and* assigned a texture unit, that the assigned unit matches the per-frame binding, and that the units are distinct | Contract tests pass; the test was confirmed to fail when an assignment is removed |
| `web/texture-atlas.js` tile and gutter size | 128-texel tiles in a 2048x2048 atlas, with a 64-texel gutter certifying mip levels 1-6. Level 7 is deliberately excluded: it leaves one interior texel and no padding, so there is nothing left to keep separate. Each padded cell is composed in memory and uploaded with one `putImageData` instead of eight self-copies of the canvas per tile | Contract tests pass: seamless wrap for ground materials, structure rather than per-texel noise, material identity, ores embedded texel-for-texel in the stone texture |
| `web/material-textures.js` feature size | Every painted feature is at least a few texels wide, because the derivative bump turns one- and two-texel grain into lighting stipple once a tile is magnified up close | Contract tests pass |
| `web/backend-notice.js`, `web/webgpu-capabilities.js` | A lost or unbuildable WebGPU backend hands the player back to the menu with the reason, releases the stored pin so the next launch does not repeat the failure, and a storage that refuses writes still navigates. The menu probes before offering the option and disables it with the reason shown | Contract tests pass; the browser probe forces `navigator.gpu` away and confirms the redirect, the notice, the released pin and the disabled option |
| `web/webgpu-terrain-renderer.js` device failure | `device.lost` and `uncapturederror` are observed, and every `mapAsync` goes through a bounded helper | Contract tests pass |
| `tests/options-panel.test.mjs` | The options panel stays grouped in order, every control has a handler (by id or by family prefix), every readout is driven, the quality list is generated rather than duplicated, reset writes the full default document, and the runtime reads what the panel writes | Contract tests pass |
| `tests/audio.test.mjs` | The master and two buses are wired to the destination in the right order, volumes clamp and survive partial updates, a muted bus schedules nothing, and the menu and game share one mixer instance | Contract tests pass |
| `web/settings.js` `graphicsQuality` Options-screen tier pin, validated against the real tier ladder so a corrupted preference falls back to `auto` rather than pinning a tier the player never chose and losing the frame-time safety net | Covered by `tests/settings.test.mjs` |
| `web/settings.js` `fpsLimit` Options-screen frame rate cap, validated against the pacer's own choice list so a corrupted preference falls back to uncapped rather than pinning a rate the player never chose and cannot undo from the panel | Covered by `tests/settings.test.mjs` |
| `npm run browser:visual-quality` | Advanced shader path forced on, five sun-facing poses captured, per-frame non-blank and non-flicker probes, and an exact atlas texel match; latest run reported zero console errors, zero page errors, and `mismatches: 0` | **Visual smoke passed** |

Two open defects remain that this record does not claim as fixed. The first is a contrast problem, not a level one: sunlit grass measures a mean of `#62905f` against an authored palette of `#416b3c`-`#6f9e57`, so the level and hue are inside the authored range, but the per-region spread runs p05 23 to p95 185. Exposure is not the lever - a 1.6x cut moved the mean by under 2%, because the frame sits deep in the ACES shoulder - and lowering the light 2.5x overshot to a third of the target. The remaining cause has not been isolated.

The second is a fine bright stipple across water surfaces, denser in the foreground and coarser at a reduced internal render scale. It is not in the shadow term, the wave normal, the foam, the caustics, the sun glitter or the water tile's albedo - each of those was removed or reduced by a large factor with the artifact unchanged - so it is still unaccounted for, and the next step is to bisect the remaining water terms rather than keep guessing.

A reported bug - a transparent patch of ground left behind after breaking a block - could not be reproduced. Breaking a block four cells ahead and then digging a four-block column both complete: the terrain quad count updates and `meshRebuildPending` returns to false within about 700 ms, and the captures show continuous ground with no hole. It is recorded as unconfirmed rather than fixed.

An earlier open defect, the water stipple, was previously recorded as follows: a fine bright stipple across water surfaces, denser in the foreground and coarser at a reduced internal render scale. It is not in the shadow term, the wave normal, the foam, the caustics, the sun glitter or the water tile's albedo - each of those was removed or reduced by a large factor with the artifact unchanged - so it is still unaccounted for, and the next step is to bisect the remaining water terms rather than keep guessing. Everything else reported here was verified by a capture or a test.

The browser smoke that exercises pointer lock (`npm run browser:smoke`) does not pass in this environment, and did not before the HDR pipeline was added: the headless Chromium here raises `pointerlockerror` on every canvas click, so the run times out waiting for pointer lock. That was confirmed by stashing the whole change set and reproducing the identical failure on clean `HEAD`. It is recorded as a pre-existing environment limitation, not a pass and not a regression.

Frame times for the HDR pipeline on the software rasteriser available here settle the adaptive controller on the lowest tier and still measure `280–580 ms` per frame at `1440 x 900` against `100–150 ms` for the previous single-pass renderer. The two levers that keep it in bounds are the tier's internal render scale, which shrinks the offscreen colour, bloom and composite targets, and the tier's cascade resolution, which at 2048 would otherwise be a larger depth-only buffer than the entire colour frame. That software-rasteriser figure says nothing about a real GPU, so real frame times were measured separately on an M1 Pro through ANGLE's Metal backend (`benchmarks/fps-cap.mjs` and the tier sweep below).

On that machine, at native retina (`1512 x 945` at `dpr 2`, 5.72 MP, render distance 4), a blank page's `requestAnimationFrame` cadence measured a 120 Hz ceiling of 8.33 ms per frame, and the game was **cost-bound against it rather than cadence-bound**: the adaptive controller settled on `medium` and held `62–67 FPS`, p95 `25 ms`, p99 `33.6 ms`. The p99 landing on exactly two 16.7 ms periods is the shape of a frame that regularly misses vsync. Timing the frame body separately from the interval showed the CPU side is not the constraint (`2.53 ms` average, p50 `1.1 ms` against an `18.7 ms` gap at the `high` tier), so the cost is GPU-side and the rAF interval is reporting it honestly.

The cause was the controller's budgets, not the renderer. `DOWNGRADE_BUDGET_MS` of 26 ms and `UPGRADE_BUDGET_MS` of 12 ms assume a ~60 Hz display, and on a 120 Hz panel a frame that misses every other vsync measures 16.7 ms — inside that dead band, so neither branch fires and the tier never moves. Per-tier cost at the same resolution, all measured: `high` (scale 1.00) `47.3 FPS` / `21.98 ms`, `medium` (0.88) `66.9 FPS` / `15.84 ms`, `low` (0.72) `105.4 FPS` / `10.38 ms`, `minimal` (0.55) `115.9 FPS` / `8.87 ms`. Auto was giving up roughly a 1.6x frame rate that the same machine could already render. The budgets are now relative to a target frame period, and the controller is pointed at the display cadence the compositor actually grants, so a 120 Hz panel asks for 8.33 ms and the ladder walks down instead of parking.

What is and is not verified: the target-to-ladder mapping is verified end to end on the real GPU (`8.33 ms` target settles at `minimal`, `16.7 ms` at `medium`, `33.3 ms` at `ultra`), and the cap is verified to hold the drawn rate exactly (`30.0 FPS` at a 30 FPS cap, 120 drawn frames over 4001 ms). The combined end-to-end result on a live 120 Hz panel — auto moving from `medium` at 67 FPS to `low` at 105 FPS — is **not** claimed. Headless Chromium drives animation frames at a fixed 60 Hz, so it cannot expose a 120 Hz ceiling, and `QUALITY=<tier> npm run bench:fps-cap` reproduces only the part of the per-tier table that a 60 Hz cadence cannot hide: the pinned `high` tier measures `51.5 FPS` there against `47.3 FPS` measured on the 120 Hz panel, which is close agreement across two very different conditions, while `medium`, `low` and `minimal` all sit on the 60 Hz ceiling headless and their 105/116 FPS figures come from the 120 Hz panel only. Those per-tier costs are the measured inputs to the prediction, not the prediction itself. Note also that headless can still measure the real GPU: `--use-angle=metal --enable-gpu` selects the Metal backend without a window, and it is what separates a real frame cost from a SwiftShader one.

In the local compositor used for this record, the adapter probe reported WebGPU support and the WGSL shader/pipeline validation completed with zero errors, but the visible-presentation probe rejected the canvas as blank and the runtime used WebGL. The WebGPU smoke therefore reports `skipped`/fallback and records the actual renderer as WebGL; shader validation is not visual presentation evidence. That `skipped` report is itself asserted rather than assumed: an explicitly requested WebGPU that cannot start has to leave no error page behind, return the player to the menu with a banner naming the backend and the reason, and release the stored renderer pin, so the next launch does not walk into the same failure. The banner is where the diagnostic is read from, which is why a fallback that reported nothing at all cannot pass. No WebGPU visual output, frame-time comparison, or pixel-identity claim is made. The six screenshots are visual evidence for the implemented composition; they are not a substitute for a target-hardware WebGPU capture.

## Colors

The palette is a dark mineral control surface placed against a bright, material-rich world. Color is used as a compact language rather than a decorative wash.

### Primary

- **Grass action green** (`#6f9b45`): primary play actions, world/grass association, and the visual cue for the next available step.
- **Forest/moss greens** (`#172019`, `#2f4a32`): world identity, selected world entries, and darker organic panel tones.

### Secondary

- **Torch amber** (`#f0bd55`, with deep amber `#9b6725`): headings, progress, selection, hotbar emphasis, mining, and the primary action's hover family.
- **Warm wood** (`#8a5a34`): loading bars and warm material associations; it is not a large decorative field.

### Tertiary

- **Bend mint** (`#78dbc1`): provenance and verified system signals—loading labels, focus, coordinates, selected system slots, and small footer text.

### Neutral

- **Coal and deep moss** (`#101310`, `#172019`): canvas fallback, borders, hard shadows, and opaque operating surfaces.
- **Parchment and muted text** (`#f2edda`, `#c5c4b6`): readable copy over dark panels and the world.
- **Stone, slate, and iron** (`#5e625d`, `#2b302d`, `#8b918c`): slot faces, secondary controls, dividers, and quiet metadata.
- **World sky and horizon** (`#6f9bb4`, `#b5d8d7`): atmospheric canvas fallbacks and the daylight-to-horizon transition.

### Named Rules

**The World Before Chrome Rule.** Keep the world visible and dominant on the title and in play. Use shade for legibility; do not replace the scene with a centered dashboard card.

**The Mint Means Provenance Rule.** Mint is reserved for Bend 2 identity, verified state, focus, and selected system context. It is not a general neon accent.

**The Amber Means Selection Rule.** Amber identifies the current action, selected slot, progress, or important status. Keep it scarce enough that selection remains obvious.

## Typography

- **Display Font:** Silkscreen (self-hosted at `web/assets/silkscreen-bold.ttf`) with Courier New and monospace fallbacks.
- **Body Font:** Trebuchet MS with Segoe UI, system UI, and sans-serif fallbacks.
- **Label/Data Font:** `ui-monospace`, SFMono-Regular, and Consolas fallbacks.

**Character:** The display face is blocky, authored, and unmistakably part of the voxel world. The body face stays friendly and legible for ordinary operating copy. Monospace is reserved for coordinates, seeds, counts, diagnostics, and short system labels rather than used as a costume for every sentence.

### Hierarchy

- **Display** (700, `clamp(30px, 4.6vw, 58px)`, line-height 1): the BEND2CRAFT wordmark and major loading presentation.
- **Headline/title** (700, 18–22px, line-height 1.2): menu and inventory headings such as `Inventory & crafting`.
- **Body** (400, 12–13px, line-height about 1.5): instructions, field labels, help, and explanatory copy.
- **Label** (700, 9–11px, `0.08em` uppercase tracking): section labels, seed/provenance lines, and compact HUD metadata.
- **Data** (400, 10–12px, tabular numerals where counts change): coordinates, stack counts, debug values, and status output.

### Named Rule

**The Engine Does Not Shout.** Monospace and mint communicate measurement or provenance, not a replacement visual voice for the player-facing world.

## Layout

The shell is a full-viewport canvas (`100vw × 100vh`) with overlays positioned against safe-area insets. The title composition is intentionally left-aligned: brand and tagline at upper-left, quiet labeled tools at upper-right, world summary and one dominant action at lower-left, and a small provenance footer at the lower-right. The title is not a centered card. `world-preview.webp` is cover-positioned and shaded with a left-to-right/bottom gradient so copy stays readable without hiding the terrain.

In game, the canvas owns the screen. A compact status block sits at the upper-left, container shortcuts sit at the upper-right, the crosshair is centered, and the survival stack, experience track, hotbar, selected-item label, and help strip form a lower-edge system. The held-item view sits at the lower-right when there is room.

The inventory is an operating surface rather than a game-world obstruction. At desktop width it uses three areas—equipment, items, and crafting—with a max width of `1120px`. At `900px` and below, crafting moves below equipment and items, and the held-item view is hidden. At `680px` and below, the panel is effectively full-width, stacks all three areas, shrinks the grid, and becomes a vertical operating surface with internal scrolling. At `390px` and below, hotbar slots reduce to `29px`, gaps tighten, and survival pips scale down. On the title at `680px` and below, Options and How to Play move to the bottom-right, the provenance footer moves to the bottom-left, the preview crop shifts to 62% center, and the extended help line is reduced. Mobile presentation remains legible; it does not imply touch-native movement or replace desktop pointer lock.

The supplied final captures are 1440×900 and 390×844. They show the same hierarchy at both sizes: title backdrop and lower-left action, edge-hugging HUD and hotbar in play, and a readable stacked inventory on narrow screens.

## Elevation & Depth

Depth is hybrid: tonal dark surfaces establish hierarchy, while pixel bevels and small hard offsets make controls feel built from blocks. Panels use an opaque mineral gradient, a `3px` coal border, inset light/dark bevels, and a broad soft drop shadow. Buttons use a lighter top-left inset, a dark bottom-right inset, and a short `4px` physical offset. The world adds its own depth through face lighting, fog, water transparency, entity shadows, vignette, and day/night sky color.

There is no generic glass treatment. The title backdrop uses a controlled dark shade, and the game uses a vignette and damage flash rather than a permanent blur. This keeps hierarchy legible over a busy world without adding a second visual world.

### Shadow Vocabulary

- **Control lift** (`inset 2px 2px ...`, `inset -2px -2px ...`, `0 4px 0 ...`): tactile press depth for buttons and slots.
- **Panel lift** (`inset 2px 2px ...`, `inset -3px -3px ...`, `0 18px 60px ...`): separation for menu, inventory, pause, death, and loading surfaces.
- **World edge** (radial vignette and a low-opacity bottom gradient): keeps the frame readable while preserving the scene.
- **State emphasis** (`0 0 0 2px` amber or mint): selected slots and focused system context; never a broad decorative halo.

### Named Rule

**Material Before Shadow.** Use bevels, borders, and authored material contrast first. Add a shadow only when the surface needs physical separation from the world or another surface.

## Shapes

The form language is orthogonal and pixel-built. Menus, fields, buttons, slots, and panels have square corners (`0px` radius). Most controls use `2px` coal borders; major surfaces use `3px`. The inset/outset pattern is intentionally visible at normal sizes so the interface feels carved from blocks rather than polished glass.

The world uses high-definition procedural material textures: `128`-texel block and entity tiles painted per material, sampled with linear filtering and a certified mip chain. Item art stays nearest-neighbor pixel texture: item atlas tiles are `16px` in a `5×9` grid, with item textures presented at a larger pixelated size. The logo cube, first-person hand, held block, hearts, hunger shapes, mining cracks, and recipe grids all reinforce the same stepped geometry. Clipped heart and hunger silhouettes are exceptions to the rectangle, but they remain pixel-derived rather than smooth iconography.

## Components

### World-first title

- **Shape:** full-bleed project-rendered world backdrop with a left-aligned vertical composition.
- **Color assignment:** parchment copy, amber logo/mark accents, grass CTA, and mint provenance footer.
- **States:** empty-save state (`Start a new world`), returning-save state (`Enter World` plus world metadata), loading state, and focused/hovered tool buttons.
- **Behavior:** the title uses a static project-generated scene from `web/assets/world-preview.webp`; it is not a blank gradient or generic dashboard.

### Buttons

- **Shape:** square, beveled block control; default min-height is `42px`, small controls are `36px`, and the title primary action is `56px` high in the implemented flow.
- **Primary:** grass gradient with coal text for AA contrast; use for creation, play, loading completion, and other forward actions.
- **Secondary:** stone/slate gradient with parchment text; use for back, cancel, delete, and quiet configuration actions.
- **Hover / Focus:** brighten slightly, shift up `1px` on hover/focus, and turn the border pale amber. Pressed controls settle down with a reduced shadow. Disabled controls become gray, desaturated, and non-interactive.
- **Guard:** labels name the action (`Create Your First World`, `Enter World`, `Close`, `Options`) instead of relying on unexplained icons.

### Menu panels and fields

- **Corner style:** square, `3px` coal border, dark mineral gradient, `18px` desktop padding.
- **Background:** opaque enough for form reading while the world remains visible around the panel.
- **Fields:** coal fill, square border, `42px` minimum height, mint focus border/outline, and a red form-error message with recovery copy.
- **Navigation:** screen changes focus to the first available input/select/button; dialogs retain labels, `aria-modal`, and explicit close/back actions.
- **Data presentation:** world/profile entries use a small square marker, a strong name, and mono metadata; selected entries receive a grass tint and amber inset marker.

### HUD and game controls

- **Status block:** upper-left coal-to-transparent plate with amber pixel brand, world/profile/mode line, coordinates, and optional diagnostics.
- **Container buttons:** upper-right beveled buttons with explicit labels and expanded state; furnace visibility follows active context.
- **Crosshair:** centered, high-contrast, small enough to preserve the scene.
- **Vitals and experience:** hearts and hunger pips sit above the hotbar; air appears only when relevant; experience is a compact level badge and progress track.
- **Debug:** F3 reveals a mint-bordered diagnostic overlay; it is not part of the default player HUD.

### Hotbar and held item

- **Shape:** one continuous `3px`-bordered belt with nine square slots, `3px` gaps on desktop and tighter gaps on narrow screens.
- **Slots:** stone bevel faces, item-atlas swatches, slot key, stack count, and durability bar; empty slots are visibly quieter.
- **Selection:** amber border/glow and a slight lift identify the current slot; the selected item label sits above the belt.
- **Held item:** a pixelated canvas preview and short label occupy the lower-right on wider layouts; the view hides at the responsive breakpoint where it would compete with the HUD.

### Inventory, crafting, and containers

- **Layout:** equipment, nine-column inventory, and shaped crafting are separate labeled regions on desktop; they stack without losing their own dividers on narrow screens.
- **Interaction:** item icons come from `web/item-atlas.js`; click/right-click/drag/Shift-click states are visible through selected/cursor borders and live status copy.
- **Crafting:** the recipe selector, 3×3 bench, output slot, and `Load ingredients` / `Craft output` / `Return ingredients` actions are kept in one readable block with a live status line.
- **Containers:** furnace and chest dialogs reuse the panel language but reduce width to `540px` maximum; each has an explicit close action and state feedback.

### Feedback and state surfaces

- **Loading:** a dark full-screen preparation surface, B2 mark, world name, and explanatory copy use live status semantics. The menu's short redirect transition uses an indeterminate visual bar rather than claiming world-generation percentages; the in-game loader reports actual hydration progress.
- **Pause/death:** centered dark dialogs keep the world visible behind a shade, with one primary recovery action and one explicit quit action.
- **Error:** a coal/red-bordered alert sits at the visual center with plain recovery-oriented copy.
- **In-world feedback:** mining bar, block highlight, toast, particles, damage flash, vignette, and the pointer-lock hint are short-lived overlays that never compete with the terrain.
- **World effects:** fire, smoke, block debris, hit sparks, and death puffs are world-space particles anchored to the coordinate that caused them, not screen-space bursts at the middle of the display. A block mined off screen looks different from one mined under the crosshair, which is the whole reason they are in the world rather than in the DOM. Whether a mob is on fire is domain state: `Entities.sunlight_damage` sets `Mob.burning` and the browser only presents it. Emitters read the body's own measurements from `MOB_BODY`, because a particle spawned inside a mob loses the depth test against the body it is meant to be licking.

## Do's and Don'ts

### Do:

- **Do** let the world establish scale, atmosphere, and hierarchy before adding interface chrome.
- **Do** reuse the coal/parchment/grass/amber/mint roles and the existing square bevel language.
- **Do** make the next action obvious with one dominant action, explicit labels, and concise status copy.
- **Do** keep keyboard focus, dialog semantics, live status, safe-area insets, and reduced-motion behavior intact when extending a surface.
- **Do** derive renderer effects from the shared presentation constants and verify the WebGL path when changing a visual contract.
- **Do** use the responsive stack, scrolling, and compact slot sizing to preserve the operating model on narrow screens.

### Don't:

- **Don't** replace the world-first title with a centered card, generic dark dashboard, or decorative cyberpunk glow.
- **Don't** make mint a general neon accent; reserve it for provenance, focus, and verified system state.
- **Don't** add rounded glass cards or smooth pill controls when the established material language is square and pixel-built.
- **Don't** copy Minecraft branding, proprietary assets, or composition; the project uses its own generated atlas, item art, and menu capture.
- **Don't** claim WebGPU presentation, GPU acceleration, or pixel parity from an adapter probe alone. The local compositor did not provide usable WebGPU presentation; WebGL is the verified path for this record.
- **Don't** imply touch-native movement from a narrow layout, or let new browser-side behavior become authoritative for domain rules that belong in Bend 2.
