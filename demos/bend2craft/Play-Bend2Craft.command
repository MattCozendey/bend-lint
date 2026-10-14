#!/usr/bin/env bash
# Build the current bundle and serve it: the macOS counterpart of
# Jogar-Bend2Craft.bat. The Bend toolchain runs natively here, so unlike the
# Windows launcher there is no WSL hop -- the pinned vendor/bend submodule and
# the project-local Bun are used directly.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

OPEN_BROWSER=1
SERVER_FLAGS=()
for argument in "$@"; do
  case "$argument" in
    --no-open) OPEN_BROWSER=0 ;;
    --lan) SERVER_FLAGS+=(--lan) ;;
    *)
      printf 'Usage: %s [--no-open] [--lan]\n' "$(basename "$0")"
      printf '  Default: build the current bundle and open the browser after listening.\n'
      printf '  --no-open: build and serve without opening a browser window.\n'
      printf '  --lan: let players on your network join the multiplayer world.\n'
      exit 2
      ;;
  esac
done

PORT="${PORT:-8080}"

if ! command -v node >/dev/null 2>&1; then
  printf 'Node.js was not found. Install Node.js to run the local server.\n' >&2
  exit 1
fi

if [[ ! -f vendor/bend/bend2/main.ts ]]; then
  printf 'vendor/bend is empty. Run: git submodule update --init --recursive\n' >&2
  exit 1
fi

printf 'Building the current Bend2Craft bundle...\n'
if ! npm run build; then
  printf 'Build failed. The old bundle was not served.\n' >&2
  exit 1
fi

for required in dist/index.html dist/chunk-worker.js dist/mesh-worker.js dist/lod-worker.js; do
  if [[ ! -f "$required" ]]; then
    printf 'The build completed without %s. Nothing was served.\n' "$required" >&2
    exit 1
  fi
done

printf 'Starting Bend2Craft at http://localhost:%s/?play=1&seed=1337 ...\n' "$PORT"
printf 'Keep this window open while you play. Press Ctrl+C to stop.\n'
if [[ "$OPEN_BROWSER" == "1" ]]; then
  node scripts/play-server.mjs --open ${SERVER_FLAGS[@]+"${SERVER_FLAGS[@]}"} || exit $?
else
  node scripts/play-server.mjs ${SERVER_FLAGS[@]+"${SERVER_FLAGS[@]}"} || exit $?
fi

printf 'Bend2Craft server stopped.\n'
# Finder launches a .command in a Terminal window that closes on exit, so hold
# the window open the way the Windows launcher does with `pause`.
if [[ -t 0 ]]; then
  read -r -p 'Press Enter to close this window.' _
fi
