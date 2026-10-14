# Native Bend2Craft Toolchain Cutover Plan

**Goal:** Remove Bun and project-authored JavaScript from the active product and development flow only after their native replacements pass equivalent checks.

**Architecture:** Use the pinned Bend 2 compiler's standalone `bend` command for native build/check/proof. Keep small OS-level build and test launchers only where unavoidable, with game code in Bend. A native Bend executable still uses the generated runtime, system graphics/audio libraries and a compiler; "no Bun" does not mean "no external tooling."

**Dependencies:** Native client and persistence/multiplayer gates, or an explicit decision to ship single-player only and retire multiplayer/cloud hosting.

**Product decisions (2026-09-28):** Native Linux/macOS and Windows via WSL display are the supported target path. Replace Cloudflare/browser multiplayer with a native Bend host; do not retire the old deployment or its saves until migration and new-host recovery are verified.

**Current evidence (2026-09-28):** The pinned v2.0.32 source was compiled with project-local Bun into an ignored `.tools/bend-local/bin/bend`. With Bun absent from `PATH`, that CLI checked `world/world.bend` and `world/PROOF.bend` and compiled and ran the native parallel benchmark. This demonstrates Bun-free *use* after a local Bun bootstrap, not a Bun-free fresh-machine installation, native gameplay or the Lean-backed `--verdict` check.

**Reproducible local bootstrap:** `bash scripts/bootstrap-native-bend.sh` checks the vendored commit, builds a standalone CLI and copies its Base/effects/guide sidecars under ignored `.tools/bend-local/`; it refuses to overwrite an existing compiler. An isolated fresh local build and `world/world.bend --check-only` passed without Bun on the execution `PATH`. Bootstrap still needs the project-local Bun builder and therefore does not satisfy the final Bun-removal gate.

## File boundaries

- Replace `scripts/run-bun.sh`, `scripts/check-bend.sh`, `scripts/test-suite.sh` and the `package.json` commands with a documented native build/test entry point after determining how the standalone pinned compiler will be provisioned.
- Migrate focused `tests/*.test.mjs` contracts to Bend tests or native integration checks with equivalent assertions before removing each JS test.
- Remove `scripts/dev-server.ts`, `scripts/build-worker.ts`, browser bundling, `web/`, `server/`, `cloudflare/`, `wrangler.jsonc` and `bunfig.toml` only if no accepted native feature depends on them.
- Update `README.md`, `AGENTS.md`, `docs/MULTIPLAYER.md` and platform launchers to describe the shipped native architecture and its supported platforms.

## Tasks

- [ ] Inventory every Bun/Node/browser/Cloudflare dependency and associate it with a passing native replacement or an explicitly discontinued feature; do not classify a deleted test as a replacement.
- [ ] Prove that a fresh supported machine can obtain the pinned standalone Bend compiler and run native check, proof, test and build without invoking Bun. Do not replace a pinned compiler with an unpinned global install.
- [ ] Create native equivalents of the production smoke flows (real window/input/frame and save/restart, plus two clients if multiplayer is retained) and native performance baselines.
- [ ] Retire one old executable path at a time; before replacing the existing gate run `npm run verify`, and after each deletion run the equivalent native checks, inspect `git diff --check` and search for active references to removed files.
- [ ] Verify clean checkout → build → launch → play → save → relaunch, and document any OS library or compiler requirements. Only then remove Bun setup instructions, `package.json` and Bun configuration.

## Exit gate

No active project-authored JS/Bun dependency, no uncovered critical regression, and a verified native release flow on the supported platforms. The `vendor/bend` compiler itself is implemented in TypeScript upstream; removing or rewriting upstream's implementation is out of scope and must not be presented as accomplished.
