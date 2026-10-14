#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
RUNS="${BEND_NATIVE_RUNS:-100}"
BINARY="$ROOT/.dev/bend-native-parallel"
mkdir -p "$ROOT/.dev"

bash "$ROOT/scripts/run-bun.sh" vendor/bend/bend2/main.ts \
  benchmarks/bend-native-parallel.bend -o "$BINARY" >/dev/null

expected="549755289600"
rows=()
for threads in 1 2 4 8; do
  start=$(date +%s%N)
  output=""
  for _ in $(seq 1 "$RUNS"); do
    output="$($BINARY --threads="$threads")"
  done
  end=$(date +%s%N)
  if [[ "$output" != "$expected" ]]; then
    printf 'unexpected native output for threads=%s: %s\n' "$threads" "$output" >&2
    exit 1
  fi
  elapsed_ms=$(( (end - start) / 1000000 ))
  rows+=("{\"threads\":$threads,\"runs\":$RUNS,\"elapsedMs\":$elapsed_ms,\"output\":\"$output\"}")
done

if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | tr '\n' ';')
  gpu_available=true
else
  gpu_name=""
  gpu_available=false
fi

printf '{"workload":"bend-native-parallel","gpuAvailable":%s,"gpuName":"%s","gpuExecution":"unverified","rows":[%s]}\n' \
  "$gpu_available" "$gpu_name" "$(IFS=,; printf '%s' "${rows[*]}")"
