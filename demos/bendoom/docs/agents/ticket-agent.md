# Working a ticket

Read `AGENTS.md`, `docs/bend.md`, the ticket and its spec if present.
The dispatch names the worktree, branch and integration base. Work only there;
leave integration and pushing to the parent agent. Kill only processes you started.

Use `nix develop -c <command>` for the toolchain. The dev shell uses Freedoom.
Keep game code in Bend; use Nushell for tools and scratch calculations. Temporary outputs and research
belong under ignored `research/` in your worktree.

## Verification

- Use Chocolate Doom's source or WAD data for expected values, as `AGENTS.md` requires.
- Run affected Bend tests on native and JavaScript backends; `nix/tests.nix` defines both.
- Check changed rendering against `tools/oracle.nu` on its headless display.
  Build the frame dump first and pass its path with `--frame`.
  Regenerate frame hashes only after the oracle reports zero differing pixels.
- When changing laws or proofs, run
  `flock /tmp/bendoom-heavy.lock nix develop -c bend PROOF.bend`.
  The lock serializes memory-heavy proof checks across agents.
- The parent runs `nix flake check` after integration and repeats affected oracle checks.

## Handoff

Commit with a conventional prefix and the configured GitHub no-reply identity,
without a co-author trailer.
Report commit hashes, checks run, failures and remaining work to the parent.
Update an unfinished ticket with blockers or missing evidence. Once verified
complete, delete it; keep session reports out of tracked documentation.
