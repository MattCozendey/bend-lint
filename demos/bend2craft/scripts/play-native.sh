#!/usr/bin/env bash
# Run the native client from the repository root, compiling it first when a
# source it is built from is newer than the binary. Arguments go to the client.
set -euo pipefail

cd "$(dirname "$0")/.."

bend=.tools/bend-local/bin/bend
client=.tools/bend-local/bin/bend2craft-client

if [ ! -x "$bend" ]; then
  echo "The native Bend CLI is missing. Run: bash scripts/bootstrap-native-bend.sh" >&2
  exit 1
fi

stale=""
if [ -x "$client" ]; then
  stale="$(find native world \( -name '*.bend' -o -name '*.c' \) -newer "$client" -print | head -n 1)"
fi

if [ ! -x "$client" ] || [ -n "$stale" ]; then
  echo "Compiling the native client..."
  "$bend" native/client.bend -o "$client"
fi

exec "$client" "$@"
