# Bend2Craft Inventory, Terrain and Trees Plan

> **For implementation:** follow the RED → GREEN → REFACTOR loop for each behavior. Keep the first-person slice playable after every task.

**Goal:** expand the first slice into a larger deterministic voxel world with trees and a real hotbar inventory that controls collecting and placing blocks.

**Architecture:** Bend 2 remains the only source of truth for terrain, tree placement and block IDs. JavaScript receives the larger materialized block buffer, keeps session inventory state in a pure testable module, and owns only browser input/rendering/UI.

**Tech Stack:** Bend 2.0.12, Bun, WebGL 1, browser ES modules and Node/Bun `assert` tests.

---

## Contract

Block IDs:

- `0`: air
- `1`: stone
- `2`: dirt
- `3`: grass
- `4`: leaves
- `5`: wood

World dimensions become `48 x 48 x 20`. `World.block(x, y, z)` includes terrain, trunk and canopy blocks. `World.column_height(x, z)` remains the surface height used for spawning and tests.

## Files

- Modify: `world/world.bend` — larger terrain, deterministic tree centers and tree blocks.
- Modify: `world/LAWS.bend` — closed laws for air, grass, wood and leaves.
- Modify: `world/PROOF.bend` — proofs for those laws.
- Create: `web/inventory.js` — pure hotbar operations and block metadata.
- Create: `tests/world-bridge.test.mjs` — Bend bridge/dimension/tree regression test.
- Create: `tests/inventory.test.mjs` — inventory collect/consume/selection tests.
- Modify: `web/index.html` — hotbar markup.
- Modify: `web/styles.css` — hotbar layout, selected state and stack counts.
- Modify: `web/main.js` — larger buffers, tree palette, inventory bridge and interaction rules.
- Modify: `package.json` — `test` script.
- Modify: `README.md` — repository URL, feature list and updated controls.
- Create: `AGENTS.md` — durable repository instructions.

## Task 1: Tests first

- [x] **Step 1: Add the world regression test**

Create `tests/world-bridge.test.mjs`:

```js
import assert from "node:assert/strict";
import World from "../world/world.bend";

const width = Number(World.width());
const depth = Number(World.depth());
const maxY = Number(World.max_y());
assert.equal(width, 48);
assert.equal(depth, 48);
assert.equal(maxY, 20);

let wood = 0;
let leaves = 0;
let grass = 0;
for (let y = 0; y < maxY; y += 1) {
  for (let z = 0; z < depth; z += 1) {
    for (let x = 0; x < width; x += 1) {
      const block = Number(World.block(BigInt(x), BigInt(y), BigInt(z)));
      if (block === 3) grass += 1;
      if (block === 4) leaves += 1;
      if (block === 5) wood += 1;
    }
  }
}
assert.ok(grass > 0);
assert.ok(wood > 0);
assert.ok(leaves > 0);
console.log(JSON.stringify({ width, depth, maxY, grass, wood, leaves }));
```

Run `bash scripts/run-bun.sh tests/world-bridge.test.mjs`. It must fail before the world expansion because the current dimensions are 24 x 24 x 12.

- [x] **Step 2: Add the inventory regression test**

Create `tests/inventory.test.mjs`:

```js
import assert from "node:assert/strict";
import {
  createInventory,
  selectedItem,
  collect,
  consume,
} from "../web/inventory.js";

const inventory = createInventory();
assert.deepEqual(selectedItem(inventory, 0), { block: 1, count: 32 });
assert.equal(consume(inventory, 0), true);
assert.equal(selectedItem(inventory, 0).count, 31);
assert.equal(collect(inventory, 5), true);
assert.deepEqual(selectedItem(inventory, 4), { block: 5, count: 9 });
assert.equal(consume(inventory, 8), false);
console.log("inventory ok");
```

Run `bash scripts/run-bun.sh tests/inventory.test.mjs`. It must fail with a missing module before `web/inventory.js` exists.

## Task 2: Bend world expansion

- [x] **Step 1: Implement the larger deterministic terrain**

Change `width` to `48n`, `depth` to `48n`, `max_y` to `20n`, and make `column_height` return a bounded height between 4n and 12n using the existing Nat arithmetic. Preserve `0/1/2/3` terrain semantics.

- [x] **Step 2: Add deterministic trees**

Add pure helpers `near`, `tree_at`, `trunk_at` and `canopy_at`. A tree center is selected by a modular hash away from the world border. Its trunk occupies three blocks above the grass, block `5`; a two-layer radius-one canopy uses block `4`. `block` must prioritize trunk, then canopy, then terrain.

- [x] **Step 3: Run the focused world test**

Run `bash scripts/run-bun.sh tests/world-bridge.test.mjs`. It must pass and print positive grass, wood and leaves counts.

- [x] **Step 4: Add and prove laws**

Add closed laws for a known air cell, a known grass cell, and one deterministic wood/leaf cell. Run `npm run check:bend` and `npm run proof`; both must print `All terms check.`.

## Task 3: Inventory module

- [x] **Step 1: Implement the smallest pure inventory API**

Create `web/inventory.js` with `createInventory`, `selectedItem`, `collect`, `consume` and explicit `BLOCK_INFO`. Use nine slots, a maximum stack of 64, initial stacks `{1:32, 2:24, 3:16, 4:8, 5:8}`, and return `false` when collecting has no compatible slot or consuming lacks items.

- [x] **Step 2: Run the focused inventory test**

Run `bash scripts/run-bun.sh tests/inventory.test.mjs`. It must pass with `inventory ok`.

## Task 4: Browser inventory and larger renderer

- [x] **Step 1: Add the hotbar UI**

Add `#hotbar` with nine buttons to `web/index.html`. Each button must expose its slot with `data-slot`, show the block name and count, and be keyboard accessible.

- [x] **Step 2: Render the new block IDs**

Update the palette in `web/main.js` for leaves and wood, keep face culling unchanged, and derive buffer dimensions from `World.width`, `World.depth` and `World.max_y` rather than literals.

- [x] **Step 3: Connect inventory to interaction**

Removing a block must collect its ID before changing the world; if the inventory is full, leave the block untouched. Placing must require `consume(inventory, selectedSlot)` before changing the world. Keyboard `1` through `9` and hotbar clicks select slots. HUD updates after every collect/consume.

- [x] **Step 4: Run the browser smoke test**

Start `npm run dev`, open the local page, and verify: larger horizon, visible trees, hotbar counts, slot selection, removal increments a stack, placement decrements a stack, and full-inventory rejection leaves the block intact.

## Task 5: Documentation and full gates

- [x] **Step 1: Update README**

Replace the placeholder clone URL with `https://github.com/lennix1337/bend2craft.git`, document the 48 x 48 world, block IDs, trees, inventory controls and WSL requirement.

- [x] **Step 2: Run all gates**

```bash
npm run check:bend
npm run proof
npm run test
npm run build
```

Expected: all checks pass, tests print the world JSON and `inventory ok`, and `dist/index.html` is generated.

- [x] **Step 3: Review and publish**

Inspect `git status --short`, `git diff` and `git diff --cached`. Commit only the repository changes, push `main` to `https://github.com/lennix1337/bend2craft.git`, then read back the remote branch SHA and repository metadata.
