# Native Bend2Craft Persistence and Multiplayer Plan

**Goal:** Preserve world data and replace JavaScript multiplayer authority/hosts without silently weakening correctness or security.

**Architecture:** The server and client share pure `world/*.bend` transitions. Bend native `File` effects persist versioned world data; Bend TCP/UDP effects provide the available transport. The current browser WebSocket/JSON protocol and Cloudflare Durable Object deployment are distinct platform capabilities and must not be claimed as preserved by a native TCP server.

**Dependency:** Integrate the native host after native single-player movement, edits and save/restart work. The transport prototype can be developed independently, but its protocol cannot be finalized before the player/world state contract is defined.

**Product decision (2026-09-28):** Build a new native Bend host and protocol. Compatibility with the current browser WebSocket clients and Cloudflare Durable Object deployment is not required for the new runtime. Preserve existing user world data through an explicit migration path before retiring the old host; a protocol break does not authorize losing saves.

**Current evidence (2026-09-29):** `lab/native/save/` reads the real legacy `worlds/multiplayer.json` snapshot **version 1** (seed plus edit log) as a strict JSON subset and writes the native `B2CW:1` snapshot; the parent reran its focused test and it passes. It refuses unknown or missing versions, non-canonical, negative or oversized seeds, truncated documents, extra or repeated members, out-of-world cells and unknown block IDs (through `Multiplayer.valid_edit`, so block IDs cannot drift), two edits of one cell, and oversized input, always as a whole document, and it never opens or truncates a file, so a refusal cannot cost data. Its `max_edits` is 1024 so the test also runs in the TypeScript lane; raise it before importing a real world, since a refusal leaves the original file untouched. **Still not migrated:** snapshot versions 2 and 3 (chests, furnaces, world clock, block simulation), the room sequence, the browser save journal in `web/persistent-save.js` and player profiles. `native/world.bend` still persists only a two-byte cursor, and `lab/native/save-probe/` still tests an unrelated single-edit `B2CS:1` codec.

**Wire-contract evidence:** `lab/native/protocol-probe/` has a versioned fixed 28-byte Bend codec and pure two-client edit convergence test. `Multiplayer.submit` validates the edit; `Multiplayer.revert` supplies the authoritative block for a reject, so a tested in-world optimistic edit can be undone. An out-of-world reject carries block `0` and must not be merged as a world edit. This is **not** TCP reassembly or an authenticated server: message replay, sequence-gap recovery, rate limiting and confidentiality remain unverified.

**Transport constraint:** The pinned Bend `TCP.poll` has a deadline but decodes received bytes as UTF-8 (`io_str`); `TCP.recv_bytes` preserves arbitrary bytes but has no timeout. Do not put raw 28-byte frames through `TCP.poll`. `lab/native/tcp-probe/` therefore carries the 28-byte frame inside a fixed 56-character ASCII-hex envelope, and its focused test passes for split, coalesced, oversized and malformed input. `lab/native/tcp-probe/link.bend` frames a socket with a bounded poll, but the two-client session could not be completed: every Bend value is consumed once, so the server cannot read the accepted edit from the room for a broadcast and also keep that room for the next submission. Real sockets, sequencing, authentication and replay handling remain unverified.

## File boundaries

- Create `native/save.bend` to read/write versioned native snapshots and migrate known saves from `worlds/multiplayer.json` and the browser save format when the formats are confirmed.
- Create `native/protocol.bend` for bounded decoding/encoding and `native/server.bend` for socket lifecycle only after selecting a transport.
- Move shared state transitions into `world/*.bend` with focused tests instead of copying `server/multiplayer-room.js`, `server/server-world.js` or `server/room/` rules.
- Keep `server/node-host.mjs`, `cloudflare/worker.js`, `web/multiplayer-protocol.js` and `docs/MULTIPLAYER.md` until an explicit compatibility/deployment decision and end-to-end verification.

## Tasks

- [ ] Record and test the current on-disk snapshots and browser save fixtures. Define which inputs must round-trip, and reject unsupported or malformed versions without corrupting existing saves.
- [ ] Add a failing contract test for each server-owned player inventory, edit/reach, health, movement and world-tick invariant still enforced outside Bend.
- [ ] Implement native snapshot encode/decode and atomic replacement; test load → edit → save → restart → same state, including interrupted writes and unknown versions.
- [x] Select a new native host/protocol rather than browser WebSocket/JSON/Cloudflare compatibility. Bend's pinned base provides TCP/UDP; specify framing, size limits, malformed input behavior and authentication policy before implementation.
- [ ] Build a two-client end-to-end smoke: both connect, submit an edit, receive the same authoritative state, disconnect and reconnect to the persisted state. Check rejected reach/inventory actions too.
- [ ] Benchmark room tick, chunk load and edit-log growth; retain the existing performance-sensitive Bend correctness tests and run `npm run verify` while that gate is active.
- [ ] Decide how Cloudflare hosting is replaced or explicitly discontinued. A native Bend server cannot be deployed as the existing Durable Object without a JS host.

## Exit gate

Verified save migration and recovery, authoritative two-client convergence and an explicit hosting/protocol compatibility decision. Do not retire the existing multiplayer host merely because a native process accepts connections.
