#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SCRATCH="$ROOT/scratchpad/voxel-probe"
BEND="${BEND_BIN:-$ROOT/.tools/bend-local/bin/bend}"
RUNS=7

if [ ! -x "$BEND" ]; then
  printf 'Bend 2 compiler is missing or not executable: %s\n' "$BEND" >&2
  exit 1
fi
if [ "$("$BEND" version)" != 'bend 2.0.35' ]; then
  printf 'Native voxel probe requires Bend 2.0.35: %s\n' "$BEND" >&2
  exit 1
fi

mkdir -p "$SCRATCH"
TEST_BIN="$SCRATCH/voxel_probe_test"
BENCH_BIN="$SCRATCH/frame_bench"
RUN_OUTPUT="$SCRATCH/run-output.txt"
SAMPLES="$SCRATCH/phase-samples.txt"

printf 'compiler: '
"$BEND" version
printf 'target: native C executable; --threads 1 --gpu off; single-thread CPU renderer\n'
printf 'platform: '
uname -a
if [ -r /proc/cpuinfo ]; then
  printf 'cpu: '
  awk -F: '/^model name[[:space:]]*:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }' /proc/cpuinfo
else
  printf 'cpu: unavailable\n'
fi
printf 'C compiler: '
clang --version | sed -n '1p'

# A stale binary would let a failed check look green, so clear it first and
# treat any checker complaint as a hard failure.
rm -f "$TEST_BIN" "$BENCH_BIN"
"$BEND" lab/native/voxel/voxel_test.bend -o "$TEST_BIN"
"$BEND" lab/native/voxel/frame_bench.bend -o "$BENCH_BIN"

# Collect no timing until the real goldens, the position-aware camera tests and
# the bulk-chunk frame build pass.
"$TEST_BIN" --threads 1 --gpu off

# Warm the executable and its code pages; each measured process re-runs every
# timed phase, and every timed phase prints its own forcing IO.print.
"$BENCH_BIN" --threads 1 --gpu off > /dev/null

: > "$SAMPLES"
run=1
while [ "$run" -le "$RUNS" ]; do
  "$BENCH_BIN" --threads 1 --gpu off > "$RUN_OUTPUT"
  grep '^phase=' "$RUN_OUTPUT" >> "$SAMPLES"
  printf 'sample=%d\n' "$run"
  grep '^phase=' "$RUN_OUTPUT" | sed 's/^/  /'
  run=$((run + 1))
done

# Median and range per phase, keyed by the phase's own name and size fields.
awk '
  /^phase=/ {
    phase = ""
    size = ""
    iters = ""
    for (i = 1; i <= NF; i++) {
      split($i, kv, "=")
      if (kv[1] == "phase") phase = kv[2]
      else if (kv[1] == "size") size = kv[2]
      else if (kv[1] == "iterations") iters = kv[2]
      else if (kv[1] == "elapsed_ms") {
        key = phase " size=" size " iterations=" iters
        n[key]++
        value[key, n[key]] = kv[2] + 0
      }
    }
  }
  END {
    for (key in n) {
      count = n[key]
      for (i = 2; i <= count; i++) {
        current = value[key, i]
        j = i - 1
        while (j >= 1 && value[key, j] > current) {
          value[key, j + 1] = value[key, j]
          j--
        }
        value[key, j + 1] = current
      }
      median = value[key, (count + 1) / 2]
      printf "%s median_ms=%.0f range_ms=[%.0f,%.0f] samples=%d\n",
        key, median, value[key, 1], value[key, count], count
    }
  }
' "$SAMPLES" | sort
