# Bend toolchain tracking

`vendor/bend` is pinned as a submodule. This file tracks the pin and the
policy for moving it. Upstream keeps its own per-release notes in
`vendor/bend/CHANGELOG.md` (worth reading before every bump).

## Current pin

- Pinned: `v2.0.35` (2026-10-03), commit `79df8d9`. `scripts/bootstrap-native-bend.sh` carries the
  same commit and builds the native CLI from it.
- Commands: `bash scripts/bend-toolchain.sh check` (read-only),
  `bash scripts/bend-toolchain.sh update` (working tree only, no commit).

## Policy

- Never auto-update on build. Compiler releases break sources (for example,
  2.0.17 changed operator type inference to require an annotation around
  each operator expression), so every bump is followed by `npm run verify`
  and only then committed (`git add vendor/bend`).
- `update` also forces `core.autocrlf=false` inside the submodule: a Windows
  CRLF checkout marks every upstream file as modified and can abort tag
  switches.
- Run the gate from a login WSL shell (`wsl -e bash -lc "npm run verify"`). A
  non-login shell leaves the Windows npm ahead of the Linux one on PATH, and
  its cmd.exe script shell rejects the `BEND_NO_TELEMETRY=1 ...` prefix the
  `build` script uses. The failure is `'BEND_NO_TELEMETRY' is not
  recognized`, which reads like a toolchain bug and is not one.
- Do not edit `vendor/bend` for application features; it is upstream code.

## History

- `v2.0.32` -> `v2.0.35` (2026-10-03): moved so that the native client builds on Apple Silicon.
  Since 2.0.29 Apple's shader compiler died on the GPU program of any program with a `!` on M1 and
  M2 chips, and on macOS every windowed program has one (`Image.drop!` in `App.turn`), so the
  native client could not be built there at all (`XPC_ERROR_CONNECTION_INTERRUPTED`, a crash in
  `MTLCompilerService`: `unable to legalize instruction ... load monotonic`). 2.0.35 fixes it
  (upstream #1154). The gate was run on the new pin before it was recorded here. Two Base changes
  that touch our code were read before the bump: `U32.to_nat` widens to u64 in C (2.0.33) and
  `U32.min`/`max`/`List.sort` open their argument first (2.0.33).

- `v2.0.19` -> `v2.0.32` (2026-09-27): 13 upstream releases. This one needed
  source changes on our side, and every one of them came from two upstream
  behaviour changes, both measured rather than assumed:
  - **A datatype is spelled by the file that owns it.** A value leaves its
    module with the bare tag (`Edit`, `State`), but a module that *imported*
    that type wants `owner.Type` on the way in, and the loader rejects the bare
    one instead of coercing it. Upstream tracks this as #1105 and says a later
    version will make the tag the same everywhere. `web/bend-modules.js` is the
    single place that knows it: it wraps every world module once, qualifies the
    declared foreign parameters and normalises the results that carry a
    qualified tag, so the adapter only ever sees the bare tag it always saw.
    Its table is derived from the `Alias.Type` annotations in the world
    signatures, and `tests/bend-bridge.test.mjs` re-derives it from the sources
    and fails on any disagreement, so the table cannot drift.
  - **A host `Nat` may not be negative.** From 2.0.32 the JS lane refuses a
    negative Nat with `a Nat past the largest immediate 2^48-1` rather than
    truncating it, and this world addresses cells below the origin, so every
    cell that crosses the adapter is now spelled shifted into the positive range
    by `cellNat` (and every chunk by `chunkNat`). Two rules used to spell a cell
    below the origin differently, the chunk grid and the cell grid; both now
    fold through the one rule, so one cell has one name. `tests/inventory.test.mjs`
    pins the offset that `web/inventory.js` and `web/game.js` each carry a copy
    of, because a drift between them would address a cell one of them never saw.
  - From upstream we also take the literal and decode checker work (2.0.24,
    2.0.25), wide records past 255 words (2.0.25), the shared-block
    `Array.fork`/`Array.join`/`Array.atomic.*` API (2.0.22), the device leaf
    handoff fix (2.0.24), the one-verdict proof output (2.0.32: `ALL PROOFS
    CHECK` or `SOME PROOFS FAIL` in place of `All terms check.`) and the
    rewritten JS lane (2.0.29), which is the lane every browser build here
    runs on.
- One gameplay bug predates the upgrade and the 2.0.32 timing only exposed it:
  `Entities.ground_y` matched a column with exact F32 equality while the adapter
  writes the ground at `floor(x) + 0.5`, so a drop at a fractional x never
  found its floor and fell to `y = -100` instead of landing. The same drop is
  collectable only for a narrow window of simulation time, and the faster JS
  lane fell outside it. `ground_y` now compares the column both values are in;
  `tests/entities-bend.test.mjs` covers a fractional, a whole, a negative and a
  neighbouring column, and fails if the fix is reverted.
- `web/bend-modules.js` passes its own test on `v2.0.19`, `v2.0.26` and
  `v2.0.32`, so it is inert on the pins that do not need it. When upstream
  unifies the tag in #1105 this file collapses to a passthrough and
  `cellNat` becomes a no-op for cells on or above the origin.
- `v2.0.12` -> `v2.0.19` (2026-09-20): 74 upstream commits. Highlights from
  the upstream changelog: faster binary startup (8 GiB arena, #881),
  records past 256 words compile (#843), dense `U32` matches become lookup
  tables (#867), Metal-lane fast trig for `sin`/`cos`/`tan` (#887),
  breaking operator-inference change plus `~`-template/law verdict rework
  (2.0.17, #848), JS-lane fixes for dotted field names and channel
  deadlocks (2.0.18, #868, #871). Our sources needed no changes:
  `check:bend` (18 files), `proof`, full `test` and `build` all pass.
