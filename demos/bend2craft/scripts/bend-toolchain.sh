#!/usr/bin/env bash
# Tracks the pinned Bend toolchain (vendor/bend submodule) against upstream.
#
# Usage (run from WSL at the repository root):
#   bash scripts/bend-toolchain.sh check    # read-only: pinned vs latest + changelog
#   bash scripts/bend-toolchain.sh update   # move the working tree to the latest tag (no commit)
#
# After `update`, run the full gate before committing the new pin:
#   npm run verify
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-check}"

pinned="$(git -C vendor/bend describe --tags)"
git -C vendor/bend fetch -q --tags origin
latest="$(git -C vendor/bend tag --list 'v2.*' --sort=-v:refname | head -n 1)"

printf 'bend pinned: %s\nbend latest: %s\n' "$pinned" "$latest"

if [[ "$pinned" == "$latest" ]]; then
  echo "bend is up to date."
  exit 0
fi

echo "--- upstream CHANGELOG ${pinned}..${latest} ---"
git -C vendor/bend diff "${pinned}..${latest}" -- CHANGELOG.md | head -n 120 || true

if [[ "$MODE" != "update" ]]; then
  echo "Run 'bash scripts/bend-toolchain.sh update' to move the working tree (then npm run verify)."
  exit 0
fi

# Guard against the Windows CRLF checkout problem: without this, every file
# in the submodule shows as modified and tag switches can abort.
git -C vendor/bend config core.autocrlf false
git -C vendor/bend reset --hard -q "$latest"
echo "vendor/bend now at $(git -C vendor/bend describe --tags) (working tree only, not committed)."
echo "Next: npm run verify, then commit the new pin (git add vendor/bend)."
