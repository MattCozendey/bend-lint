#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-3000}"
BASE_URL="http://127.0.0.1:${PORT}"
TMP_DIR="${TMPDIR:-/tmp}/bend2craft-smoke-$$"
LOG_FILE="$TMP_DIR/dev.log"
INDEX_FILE="$TMP_DIR/index.html"
SERVER_PID=""

run_followup() {
  if [[ "${1:-}" == "--browser" ]]; then
    bash "$ROOT/scripts/run-bun.sh" "$ROOT/scripts/browser-smoke.mjs" "$BASE_URL"
  elif [[ "${1:-}" == "--lighting" ]]; then
    bash "$ROOT/scripts/run-bun.sh" "$ROOT/scripts/lighting-smoke.mjs" "$BASE_URL"
  elif [[ "${1:-}" == "--streaming" ]]; then
    bash "$ROOT/scripts/run-bun.sh" "$ROOT/scripts/streaming-smoke.mjs" "$BASE_URL" 6
  elif [[ "${1:-}" == "--webgpu" ]]; then
    bash "$ROOT/scripts/run-bun.sh" "$ROOT/scripts/webgpu-smoke.mjs" "$BASE_URL"
  elif [[ "${1:-}" == "--visual-quality" ]]; then
    bash "$ROOT/scripts/run-bun.sh" "$ROOT/scripts/visual-quality-smoke.mjs" "$BASE_URL"
  elif [[ "${1:-}" == "--multiplayer" ]]; then
    bash "$ROOT/scripts/run-bun.sh" "$ROOT/scripts/multiplayer-smoke.mjs" "$BASE_URL"
  elif [[ "${1:-}" == "--renderer-benchmark" ]]; then
    bash "$ROOT/scripts/run-bun.sh" "$ROOT/scripts/renderer-benchmark.mjs" "$BASE_URL"
  elif [[ "${1:-}" == "--fps-cap" ]]; then
    bash "$ROOT/scripts/run-bun.sh" "$ROOT/benchmarks/fps-cap.mjs" "$BASE_URL"
  fi
}

mkdir -p "$TMP_DIR"

# A server left running from an earlier session answers on the port long before
# it reflects the current source. Reusing it would let every smoke below report a
# green result against a stale bundle, so an already-listening port is refused
# unless the caller asked for it with REUSE_SERVER=1 or picked another PORT.
if curl --max-time 2 -fsS "$BASE_URL/" -o "$INDEX_FILE" 2>/dev/null; then
  if [[ "${REUSE_SERVER:-0}" == "1" ]]; then
    printf 'dev server already ready at %s/ (reused by request)\n' "$BASE_URL"
    run_followup "${1:-}"
    exit 0
  fi
  printf 'a dev server is already answering on %s/.\n' "$BASE_URL" >&2
  printf 'It may predate the current source, so reusing it can report a stale build as passing.\n' >&2
  printf 'Stop it, or re-run with PORT=<free port> or REUSE_SERVER=1 to accept the risk.\n' >&2
  exit 1
fi

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill -- "-$SERVER_PID" 2>/dev/null || kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# Job control gives the server its own process group, so the group kill in
# cleanup() below reaps it with anything it spawned. This is a bash builtin,
# which keeps the script working on macOS, where setsid is not available.
set -m
bash "$ROOT/scripts/run-bun.sh" "$ROOT/scripts/dev-server.ts" >"$LOG_FILE" 2>&1 &
SERVER_PID=$!
set +m

for attempt in $(seq 1 30); do
  if curl --max-time 2 -fsS "$BASE_URL/" -o "$INDEX_FILE" 2>/dev/null; then
    printf 'dev server ready at %s/ on attempt %s\n' "$BASE_URL" "$attempt"
    run_followup "${1:-}"
    exit 0
  fi
  sleep 1
done

printf 'dev server did not become ready within 30 seconds\n' >&2
printf 'server log: %s\n' "$LOG_FILE" >&2
exit 1
