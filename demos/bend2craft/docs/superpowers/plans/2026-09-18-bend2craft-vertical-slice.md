# Bend2Craft Vertical Slice Implementation Plan

> **For implementation:** execute the tasks in order and keep the checkboxes current. The first slice must remain playable and verifiable before expanding it.

**Goal:** deliver a browser-playable voxel sandbox with a deterministic Bend 2 world, first-person camera, simple collision, and block removal/placement.

**Architecture:** Bend 2 is the source of truth for world dimensions, column heights and block types. The JavaScript frontend only materializes that contract into a voxel buffer, simulates browser input and camera state, and renders cubes with WebGL. The Bend runtime is pinned as a `vendor/bend` submodule and runs through Bun inside WSL on this Windows host.

**Tech Stack:** Bend 2.0.12, Bun, HTML/CSS/JavaScript ES modules and dependency-free WebGL 1.

---

## First-slice scope

The verifiable result is a page that:

- generates a deterministic 24 x 24 world from `world/world.bend`;
- draws grass, dirt and stone blocks in 3D perspective;
- moves the player with WASD, looks with the mouse after clicking the canvas, and jumps with Space;
- blocks the player at solid faces;
- removes the targeted block with left click and places a selected block with right click;
- shows coordinates, selected block and controls in the HUD;
- passes the Bend checker and the Bun bundle step.

Persistent inventory, crafting, mobs, dynamic lighting, infinite chunks, multiplayer and audio are intentionally outside this slice.

## Files and responsibilities

- Create: `.gitmodules` — pins `bendlang/bend` at `vendor/bend`.
- Create: `.gitignore` — ignores local Bun, bundles and caches without hiding source files.
- Create: `package.json` — minimal check, proof, serve and bundle scripts.
- Create: `bunfig.toml` — registers the Bend 2 `.bend` loader for Bun.
- Create: `scripts/run-bun.sh` — selects the local WSL Bun or a Bun already on PATH.
- Create: `scripts/check-bend.sh` — runs the checker with telemetry disabled.
- Create: `world/world.bend` — pure world contract and terrain generation.
- Create: `world/LAWS.bend` — block invariants for the slice.
- Create: `world/PROOF.bend` — closed proofs for the declared invariants.
- Create: `web/index.html` — accessible application shell and HUD elements.
- Create: `web/styles.css` — responsive layout, HUD and crosshair.
- Create: `web/main.js` — Bend bridge, game state, input, collision, raycast and render loop.
- Create: `README.md` — WSL setup, commands and controls.

## Bend/JavaScript contract

`world/world.bend` exposes pure functions consumed by the JavaScript bridge. Because the file is imported with the alias `World`, the unprefixed definitions below appear to consumers as `World.width`, `World.depth` and so on:

```bend
import Base

def width() -> Nat:
  24n

def depth() -> Nat:
  24n

def max_y() -> Nat:
  12n

def column_height(+x: Nat, +z: Nat) -> Nat:
  +wave = Nat.mod(Nat.add(Nat.mul(x, 13n), Nat.mul(z, 31n)), 5n)
  Nat.add(4n, wave)

def same(+a: Nat, +b: Nat) -> Bool:
  Nat.is_eq(a, b)

def block(+x: Nat, +y: Nat, +z: Nat) -> U32:
  +h = column_height(x, z)
  +inside = Nat.is_lt(y, h)
  +top = same(y, Nat.sub(h, 1n))
  +deep = Nat.is_lt(y, Nat.sub(h, 3n))
  Bool.pick(U32, inside,
    Bool.pick(U32, top, 3, Bool.pick(U32, deep, 1, 2)),
    0)
```

`World.block` values are stable: `0` air, `1` stone, `2` dirt and `3` grass. JavaScript passes `Nat` arguments as `BigInt` and converts the result to `Number` only at the rendering boundary.

### Task 1: Reproducible bootstrap

**Files:**
- Create: `.gitmodules`
- Create: `.gitignore`
- Create: `package.json`
- Create: `bunfig.toml`
- Create: `scripts/run-bun.sh`
- Create: `scripts/check-bend.sh`

- [x] **Step 1: Register the Bend 2 runtime**

Add to `.gitmodules`:

```ini
[submodule "vendor/bend"]
\tpath = vendor/bend
\turl = https://github.com/bendlang/bend.git
```

Run:

```bash
git submodule add --depth 1 https://github.com/bendlang/bend.git vendor/bend
```

Expected: `vendor/bend/bend2/main.ts` exists and `git submodule status` reports an upstream commit.

- [x] **Step 2: Add minimal ignores**

Create `.gitignore`:

```gitignore
.tools/
dist/
.bend/
node_modules/
```

- [x] **Step 3: Create project scripts**

`package.json`:

```json
{
  "name": "bend2craft",
  "private": true,
  "type": "module",
  "scripts": {
    "check:bend": "bash scripts/check-bend.sh world/world.bend",
    "proof": "bash scripts/check-bend.sh world/PROOF.bend",
    "dev": "bash scripts/run-bun.sh web/index.html",
    "build": "BEND_NO_TELEMETRY=1 bash scripts/run-bun.sh vendor/bend/bend2/main.ts web/index.html -o dist"
  }
}
```

`bunfig.toml`:

```toml
preload = ["./vendor/bend/bend2/main.ts"]

[serve.static]
plugins = ["./vendor/bend/bend2/main.ts"]
```

`scripts/run-bun.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUN_BIN="${BUN_BIN:-$ROOT/.tools/bun/bin/bun}"

if [[ ! -x "$BUN_BIN" ]]; then
  BUN_BIN="$(command -v bun || true)"
fi
if [[ -z "$BUN_BIN" || ! -x "$BUN_BIN" ]]; then
  printf '%s\n' 'Bun not found. Install Bun in WSL or set BUN_BIN.' >&2
  exit 1
fi

exec "$BUN_BIN" "$@"
```

`scripts/check-bend.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${1:?usage: scripts/check-bend.sh <file.bend>}"

BEND_NO_TELEMETRY=1 bash "$ROOT/scripts/run-bun.sh" \
  "$ROOT/vendor/bend/bend2/main.ts" "$ROOT/$FILE"
```

Run `chmod +x scripts/run-bun.sh scripts/check-bend.sh` inside WSL. The script must fail with a direct message when Bun is unavailable instead of downloading tools silently.

### Task 2: Deterministic world and minimal proof

**Files:**
- Create: `world/world.bend`
- Create: `world/LAWS.bend`
- Create: `world/PROOF.bend`

- [x] **Step 1: Write the pure world contract**

Create `world/world.bend` with fixed dimensions, modular noise and height-based block selection. Run `scripts/check-bend.sh world/world.bend`; expected output: `All terms check.`.

- [x] **Step 2: Declare frontend invariants**

Create `world/LAWS.bend` with closed air and surface-grass laws that protect the frontend contract without introducing a generic terrain prover.

- [x] **Step 3: Close the laws in a separate file**

Create `world/PROOF.bend` with a matching proof definition for every law. Run `scripts/check-bend.sh world/PROOF.bend`; expected output: `All terms check.`. Do not silence failed proofs with `@unsafe`.

### Task 3: Verifiable web shell

**Files:**
- Create: `web/index.html`
- Create: `web/styles.css`

- [x] **Step 1: Build the page structure**

`web/index.html` contains `canvas#game`, HUD elements, a centered crosshair and the `./main.js` module. The canvas has `aria-label="Voxel world"` and the HUD does not block canvas input.

- [x] **Step 2: Define the game layout**

`web/styles.css` fills the viewport, positions the HUD in the top-left corner, draws the crosshair with CSS and keeps the help panel readable on narrow viewports.

- [x] **Step 3: Validate the shell before the engine**

Open the page with the Bun server and confirm that the module loads without missing-resource errors.

### Task 4: First-person voxel WebGL

**File:**
- Create: `web/main.js`

- [x] **Step 1: Import Bend and materialize the world once**

The file imports `World` from `../world/world.bend` and materializes `width`, `depth`, `maxY` and `block` into a `Uint8Array` indexed by `x + width * (z + depth * y)`. JavaScript does not reimplement the terrain formula.

- [x] **Step 2: Build the minimal WebGL pipeline**

Use inline position/color shaders, generate faces only when the neighbor is air, and rebuild the mesh after block edits.

- [x] **Step 3: Implement camera and movement**

Maintain `{x, y, z, yaw, pitch, velocityY, grounded}`. Use WASD for yaw-relative movement, pointer lock for mouse look, clamp pitch between `-1.45` and `1.45`, apply gravity and allow Space to jump only while grounded.

- [x] **Step 4: Implement simple AABB collision**

The player has a horizontal radius of `0.3` and height `1.8`. Resolve X/Z separately and resolve Y against block tops and ceilings.

- [x] **Step 5: Implement raycast and editing**

Cast a ray through the screen center in `0.05` steps up to `8` units. Left click removes the first solid block; right click places the selected block in the last empty cell when it does not intersect the player.

- [x] **Step 6: Connect HUD and loop**

Show coordinates, selected block, block count and help text. Use `requestAnimationFrame`, cap `dt` at `0.05` seconds and display a pointer-lock hint.

### Task 5: Documentation and validation

**File:**
- Create: `README.md`

- [x] **Step 1: Document real commands**

Document the Bend 2 submodule, WSL setup, commands and controls.

- [x] **Step 2: Run the narrow gates**

```bash
npm run check:bend
npm run proof
npm run build
```

Expected: both Bend commands print `All terms check.` and the bundle creates `dist/index.html`.

- [x] **Step 3: Perform the browser smoke test**

With `npm run dev`, verify that the canvas and HUD render, movement and collision work, jumping works, block removal/placement work, and the Bend proof still passes after interaction.

## Roadmap after the first slice

1. Add chunks and balanced parallel generation with Bend `!` calls.
2. Move movement, collision and editing rules into pure Bend, leaving JavaScript as the browser adapter.
3. Add the hotbar inventory, visual selection and versioned local save state.
4. Add face lighting, water, trees and biomes while preserving the block contract.
5. Evaluate multiplayer only after authoritative state and serialization are defined.

## Plan review

- Coverage: bootstrap, Bend contract, proofs, web shell, WebGL, movement, collision, editing, documentation and validation are represented.
- Placeholders: there are no `TBD`, `TODO` or implicit dependencies in the actionable steps.
- Consistency: `World.width`, `World.depth`, `World.max_y`, `World.column_height` and `World.block` are used consistently across the Bend module, bridge and documentation.
