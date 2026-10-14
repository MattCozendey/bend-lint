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
