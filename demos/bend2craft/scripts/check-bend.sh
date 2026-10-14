#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${1:?usage: scripts/check-bend.sh <file.bend>}"

BEND_NO_TELEMETRY=1 bash "$ROOT/scripts/run-bun.sh" \
  "$ROOT/vendor/bend/bend2/main.ts" "$ROOT/$FILE"
