# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

The primary user is a player opening a desktop browser to explore, build, survive, and play inside a Minecraft-inspired voxel sandbox. The experience must be immediately understandable and playable without a technical briefing.

Bend 2 and engine developers are a secondary audience evaluating whether Bend 2 can safely power the systems and workload of a large game.

## Product Purpose

Bend2Craft is a small Minecraft-inspired voxel sandbox built around Bend 2 and a dependency-free browser client. It exists both as a playable world and as a sustained stress test of Bend 2 as an engine for large games.

Success means a player can enter a world, understand the controls, and start playing with minimal friction while the game consistently presents Bend 2 as the authority for world and simulation rules.

## Positioning

Bend2Craft combines a conventional first-person voxel sandbox loop with typed, pure Bend 2 contracts for world generation, simulation, inventory, combat, farming, lighting, and related authoritative state. The browser is a presentation, input, cache, and platform adapter rather than the source of game truth.

## Operating Context

Players create or select a local profile, create or select a world, optionally configure graphics and controls, and enter a first-person session. Worlds are deterministic from a textual or numeric seed and persist locally with player, inventory, world-edit, entity, village, farm, furnace, chest, and progression state.

The normal play session uses a desktop browser, mouse look with pointer lock, and keyboard controls. A player explores streamed terrain, gathers resources, crafts tools, builds structures, tends crops, uses furnaces and chests, interacts with villagers, survives environmental hazards, and fights or avoids mobs.

The repository is also a technical proving ground. Bend 2 checks, proofs, regressions, builds, benchmarks, and browser smoke tests are part of evaluating changes before they ship.

## Capabilities and Constraints

- Bend 2 owns domain contracts wherever they are implemented; JavaScript must not silently become authoritative for new world or simulation behavior.
- The browser client uses ES modules, Web Workers, local storage, WebAudio, WebGL, and optional WebGPU without an application dependency framework.
- The game supports deterministic procedural terrain, trees, ores, villages, villagers, mobs, survival, combat, inventory, crafting, farming, containers, furnaces, fluids, fire, lighting, day/night presentation, world edits, and seed-scoped local persistence.
- Current world slices are intentionally small and deterministic; feature breadth does not imply production-scale content or multiplayer.
- Browser-side Bend evaluation is sequential. WebGPU accelerates presentation and uploads, not Bend execution, and no browser multithread or native-GPU acceleration may be claimed without target-specific evidence.
- A broad UX and game-feel redesign is in scope. Existing mechanics and controls should only be replaced when a clearer interaction or demonstrable usability gain justifies the change.
- The Windows development toolchain runs through WSL; the shipped client runs in a browser.
- Block IDs and item IDs are separate namespaces.

## Brand Commitments

- The product name is Bend2Craft.
- The game is a Minecraft-inspired voxel sandbox, not a reproduction of Minecraft branding, assets, or copy.
- The player explicitly chose the category-standard canon for the visual redesign, using Minecraft and Terraria as the quality bar for world legibility, play, progression, and game feel. Execute that familiar language confidently rather than making the sandbox remote or technically clinical.
- The player-facing experience should foreground play. Bend 2 is part of the project's identity and technical credibility, but it should not force players to understand the engine before they can enjoy the world.
- Voice and product copy are authored in English throughout the repository.

## Evidence on Hand

- `README.md` documents the current product slice, controls, architecture, deterministic world, measurable behavior, and benchmark results.
- `AGENTS.md` defines the Bend 2-first engineering constitution and browser-adapter boundaries.
- `world/LAWS.bend` and `world/PROOF.bend` provide checked examples of core world invariants.
- `tests/` and `scripts/browser-smoke.mjs` provide regression and browser behavior evidence.
- `web/texture-atlas.js`, `web/item-atlas.js`, generated texture fallbacks, and oscillator-based sound provide current procedural visual and audio assets.
- No user research, playtest findings, commercial claims, testimonials, or production-readiness evidence exist. `web/assets/world-preview.webp` is a project-generated render capture used as a menu backdrop; future design work must not fabricate evidence beyond it.

## Product Principles

1. Put the playable world first; make technical machinery legible through the experience rather than through setup burden.
2. Preserve Bend 2 authority and prove authoritative changes with focused contracts and tests.
3. Make the first minutes coherent: launch, profile, world, controls, and the first meaningful interaction should form one confident path.
4. Favor strong, readable feedback over decorative interface noise during play.
5. Treat determinism, persistence, and performance claims as product trust, not only engineering details.
